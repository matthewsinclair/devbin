#!/usr/bin/env bats
# releasestatus.bats - `release status <version>`, the resume map (ST0007 WP-03)
#
# Every step of the core's sequence, read from the repository, its remotes and
# the release object -- never from a state file -- and printed as the table a
# cut's summary prints, writing nothing. A row a step, the postconditions steps
# 3, 4, 7, 8 and 9; the gates and confirm steps carry a predicate over other rows' readers,
# and the resolve, pre-flight, after and ci steps carry none. The states: `already`, `pending`,
# `skipped` (declared off), `not re-run`, and `UNREADABLE` -- a fact the run
# could not reach, which is never reported as false.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# released_project [config-tail] -- a release-enabled project at VERSION 1.0.0
# with a dated note, committed, and main pushed to one bare remote. No tag, no
# release object. Extra YAML on stdin is appended under the release: key's
# siblings, so an arm can declare what it needs.
released_project() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
YAML
  )"
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1" >>"$proj/bin/.devbin/config.yaml"
  fi
  with_dated_note "$proj"
  git_project "$proj"
  printf '%s\n' "$proj"
}

# commit_all <proj> <message> -- stage everything and commit.
commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}

# tag_release <proj> [tag] -- an annotated tag at HEAD, as the core makes one.
tag_release() {
  git -C "$1" -c user.name=t -c user.email=t@t tag -a "${2:-v1.0.0}" -m "- first" --cleanup=whitespace
}

# ============================================================================
# EVERY POSTCONDITION READER, EACH BOTH WAYS (AC-3.1)
# ============================================================================

# AT-3.1
@test "a fresh release reads every row: stamp and commit already, the rest pending or skipped" {
  proj="$(released_project)"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state resolve pending
  assert_state pre-flight pending
  assert_state stamp already
  assert_state commit already
  assert_state gates pending
  assert_state confirm pending
  assert_state tag pending
  assert_state push pending
  assert_state object pending
  assert_state after skipped
  assert_state ci skipped
  # A row a step of the core's sequence, in order, and nothing else claiming to
  # be one: the steps are read from the core's own table, not counted here.
  local want
  want="$(bash -c '. "$1/helpers" && . "$1/release.notes" && . "$1/release.steps" && printf "%s\n" "${_RELEASE_STEP_NAMES[*]}"' _ "$DEVBIN_LIB_DIR")" ||
    fail "the release core's step table could not be read"
  [ -n "$want" ] || fail "the release core's step table is empty"
  [ "$(awk '$0 ~ /^  [^ ]/ && $2 ~ /^(done|already|skipped|not|FAILED|would|pending|UNREADABLE)$/ { print $1 }' <<<"$output" | tr '\n' ' ')" = "$want " ] ||
    fail "the table is not a row a step, in order ($want):
$output"
}

# AT-3.1
@test "the stamp is pending when VERSION is not the target, and when the note is open" {
  proj="$(released_project)"
  printf '0.9.0\n' >"$proj/VERSION"
  commit_all "$proj" "back"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state stamp pending
  assert_output_contains "VERSION is 0.9.0"

  printf '1.0.0\n' >"$proj/VERSION"
  printf '# Changelog\n\n## [1.0.0] - Unreleased\n\n- first\n' >"$proj/CHANGELOG.md"
  commit_all "$proj" "open"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state stamp pending
  assert_output_contains "open"
}

# AT-3.1
@test "the stamp is pending when a generated notes view is STALE" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  mkdir -p "$proj/RELEASES"
  printf 'version: 1.0.0\nheadline: first\nstatus: released\ndate: 2026-01-01\n\n## Fixed\n\n- first\n' >"$proj/RELEASES/1.0.0.md"
  run release_in "$proj" notes
  assert_success
  commit_all "$proj" "notes"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state stamp already

  printf -- '- second\n' >>"$proj/RELEASES/1.0.0.md"
  commit_all "$proj" "note edited, views not regenerated"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state stamp pending
  assert_output_contains "STALE"
}

# AT-3.1
@test "the commit is pending while the stamp is only in the working tree, and already once committed" {
  proj="$(released_project)"
  printf '1.1.0\n' >"$proj/VERSION"
  printf '# Changelog\n\n## [1.1.0] - 2026-02-01\n\n- second\n\n## [1.0.0] - 2026-01-01\n\n- first\n' >"$proj/CHANGELOG.md"
  run release_in "$proj" status v1.1.0
  assert_success
  assert_state stamp already
  assert_state commit pending

  commit_all "$proj" "release: v1.1.0"
  run release_in "$proj" status v1.1.0
  assert_success
  assert_state commit already
}

# AT-3.1
@test "the commit is pending while the tag is absent and the tree is not clean, an untracked file included" {
  proj="$(released_project)"
  : >"$proj/stray"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state commit pending
  assert_output_contains "stray"
}

# AT-3.1
@test "the tag is pending until it exists, then already" {
  proj="$(released_project)"
  run release_in "$proj" status v1.0.0
  assert_state tag pending
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state tag already
}

# AT-3.1
@test "the push is already only when EVERY remote holds the release commit on branch AND the tag" {
  proj="$(released_project)"
  tag_release "$proj"
  git init -q --bare "$DEVBIN_TEST_TMPDIR/second.git"
  git -C "$proj" remote add second "$DEVBIN_TEST_TMPDIR/second.git"

  run release_in "$proj" status v1.0.0
  assert_success
  assert_state push pending

  git -C "$proj" push -q origin v1.0.0
  git -C "$proj" push -q second main v1.0.0
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state push already

  # A remote whose branch has moved PAST the release still holds it.
  git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m later
  git -C "$proj" push -q origin main
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state push already
}

# AT-3.1
@test "the push names the remote that is missing the tag" {
  proj="$(released_project)"
  tag_release "$proj"
  git init -q --bare "$DEVBIN_TEST_TMPDIR/second.git"
  git -C "$proj" remote add second "$DEVBIN_TEST_TMPDIR/second.git"
  git -C "$proj" push -q origin v1.0.0
  git -C "$proj" push -q second main
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state push pending
  assert_output_contains "second"
}

# AT-3.1
@test "the release object is pending until gh finds one for the tag, then already" {
  proj="$(released_project)"
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state object pending
  gh_object v1.0.0 v1.0.0 '- first'
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state object already
  assert_output_contains "carries this release's title and notes"
}

# UNDER object: local, AN OBJECT IS already ONLY WHEN IT CARRIES THIS RELEASE'S
# TITLE AND NOTES (R4). Status reads it through the reader a cut's confirm step
# reads it through, so the two cannot disagree about the object step's work.
@test "an object whose notes or title are not this release's is pending on the object row, named, and holds the confirmation open (R4)" {
  proj="$(released_project)"
  tag_release "$proj"
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 'something else'
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state object pending
  assert_output_contains "its notes are not this release's"
  assert_state confirm pending
  gh_object v1.0.0 'hand-made' '- first'
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state object pending
  assert_output_contains 'its title is "hand-made"'
}

@test "an object whose title and notes cannot be read is UNREADABLE on the object row, never already (R4)" {
  proj="$(released_project)"
  tag_release "$proj"
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 '- first'
  # Existence answers; the --json read of the title fails.
  perl -0pi -e 's{\A(#!/bin/sh\n)}{$1case "\$*" in *"--json name"*) echo "gh: HTTP 502" >&2; exit 1 ;; esac\n}' \
    "$DEVBIN_TEST_TMPDIR/stubs/gh"
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state object UNREADABLE
  assert_output_contains "HTTP 502"
  assert_state confirm UNREADABLE
}

# ============================================================================
# THE STATES NO POSTCONDITION PRODUCES (AC-3.1)
# ============================================================================

# AT-3.2
@test "the gates are never already: pending until the tag exists, then not re-run" {
  proj="$(released_project)"
  run release_in "$proj" status v1.0.0
  assert_state gates pending
  tag_release "$proj"
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 '- first'
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state gates "not re-run"
  refute_output_contains "passed"
}

# AT-3.2
@test "the confirmation is not re-run only when no irreversible step has work left" {
  proj="$(released_project)"
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_state confirm pending
  git -C "$proj" push -q origin v1.0.0
  run release_in "$proj" status v1.0.0
  # Every remote holds both, but object: local has not made the release object.
  assert_state confirm pending
  gh_object v1.0.0 v1.0.0 '- first'
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state confirm "not re-run"
}

# AT-3.2
@test "under object: ci the release object is not the core's to make, so it does not hold the confirmation" {
  proj="$(released_project '
release:
  object: ci')"
  tag_release "$proj"
  git -C "$proj" push -q origin v1.0.0
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state confirm "not re-run"
  assert_state object pending
}

# AT-3.2
@test "object: none, an undeclared after: and an undeclared ci.query are skipped, and a declared one is not" {
  proj="$(released_project '
release:
  object: none')"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state object skipped
  assert_state after skipped
  assert_state ci skipped

  proj2="$(released_project '
release:
  after:
    - echo done
  ci:
    query: echo green')"
  run release_in "$proj2" status v1.0.0
  assert_success
  assert_state after pending
  assert_state ci pending
}

# ============================================================================
# THE RELEASE COMMIT (AC-3.1)
# ============================================================================

# AT-3.3
@test "past the tag the release commit is the tag's commit, and ordinary work in the tree does not unmake the commit step" {
  proj="$(released_project)"
  tag_release "$proj"
  local tagged
  tagged="$(git -C "$proj" rev-parse --short HEAD)"
  # Development moves on: VERSION is bumped for the next cycle, and a file is
  # left modified. Neither touches the release that was tagged.
  printf '1.1.0\n' >"$proj/VERSION"
  commit_all "$proj" "next"
  : >"$proj/work-in-progress"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_output_contains "$tagged"
  assert_state stamp already
  assert_state commit already
  assert_state tag already
}

# AT-3.3
@test "past the tag a STALE view is named but does not unmake the stamp: nothing can regenerate a tagged commit" {
  # Found on devbin's own v0.1.1: its CHANGELOG.md reads STALE under TODAY's
  # renderer, because the generator changed after the tag. Staleness is measured
  # against the renderer of the day, so counting it past the tag would report
  # every earlier release unstamped the first time the renderer moved. While the
  # tag is absent it counts, because a run regenerates the views at the stamp step.
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  mkdir -p "$proj/RELEASES"
  printf 'version: 1.0.0\nheadline: first\nstatus: released\ndate: 2026-01-01\n\n## Fixed\n\n- first\n' >"$proj/RELEASES/1.0.0.md"
  run release_in "$proj" notes
  assert_success
  printf -- '- second\n' >>"$proj/RELEASES/1.0.0.md"
  commit_all "$proj" "released with a stale view"
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_state stamp already
  assert_state commit already
  assert_output_contains "STALE"
}

# AT-3.3
@test "before the tag the release commit is HEAD" {
  proj="$(released_project)"
  local head
  head="$(git -C "$proj" rev-parse --short HEAD)"
  run release_in "$proj" status v1.0.0
  assert_success
  assert_output_contains "$head"
}

# ============================================================================
# READ-ONLY, BY FINGERPRINT (AC-3.1)
# ============================================================================

# AT-3.4
@test "status writes nothing, in every state from fresh to fully released" {
  proj="$(released_project)"
  local before
  step_status() {
    before="$(fingerprint "$proj" --allow-gh-reads)"
    run release_in "$proj" status v1.0.0
    [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] ||
      fail "release status changed the repository ($1):
$(diff <(printf '%s\n' "$before") <(fingerprint "$proj" --allow-gh-reads))"
  }
  step_status fresh
  : >"$proj/stray"
  step_status "dirty tree"
  rm "$proj/stray"
  tag_release "$proj"
  step_status tagged
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 '- first'
  step_status released
  printf '1.1.0\n' >"$proj/VERSION"
  commit_all "$proj" "next"
  step_status "past the tag"
}

# ============================================================================
# ONE RENDERER (AC-3.1)
# ============================================================================

# AT-3.5
@test "every row is rendered by release_row, the function a cut's summary will call" {
  proj="$(released_project)"
  run release_in "$proj" status v1.0.0
  assert_success
  local good="$output"
  # The mutant: the one renderer, in the fixture's own vendored copy, marks
  # every row it prints. If status printed any row some other way, that row
  # would come out unmarked.
  local lib="$proj/bin/.devbin/lib/release.steps"
  [ -f "$lib" ] || fail "no vendored release.steps at $lib"
  printf '\nrelease_row() { printf "MUTANT %%s\\n" "$1"; }\n' >>"$lib"
  run release_in "$proj" status v1.0.0
  [ "$output" != "$good" ] || fail "a mutant renderer did not change the status output"
  local n names
  names="$(bash -c '. "$1/helpers" && . "$1/release.notes" && . "$1/release.steps" && printf "%s\n" "${_RELEASE_STEP_NAMES[@]}"' _ "$DEVBIN_LIB_DIR")" ||
    fail "the release core's step table could not be read"
  [ -n "$names" ] || fail "the release core's step table is empty"
  while IFS= read -r n; do
    grep -qx "MUTANT $n" <<<"$output" || fail "the $n row was not rendered by release_row:
$output"
  done <<<"$names"
}

# ============================================================================
# UNREADABLE IS NEVER FALSE (AC-3.1)
# ============================================================================

# AT-3.6
@test "a remote branch head this checkout does not hold is UNREADABLE, not pending, and nothing is fetched" {
  proj="$(released_project)"
  tag_release "$proj"
  git -C "$proj" push -q origin v1.0.0
  # Someone else pushes to the remote; this checkout never fetches it.
  git clone -q "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/other"
  git -C "$DEVBIN_TEST_TMPDIR/other" -c user.name=o -c user.email=o@o commit -q --allow-empty -m theirs
  git -C "$DEVBIN_TEST_TMPDIR/other" push -q origin main
  local refs_before
  refs_before="$(git -C "$proj" for-each-ref)"
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state push UNREADABLE
  assert_output_contains "origin"
  assert_output_contains "fetch"
  [ "$(git -C "$proj" for-each-ref)" = "$refs_before" ] || fail "status fetched: the refs changed"
}

# AT-3.6
@test "a remote carrying a lightweight tag where this release's is annotated is UNREADABLE, naming the difference" {
  proj="$(released_project)"
  # The remote gets a lightweight v1.0.0 at the release commit...
  git -C "$proj" tag v1.0.0
  git -C "$proj" push -q origin v1.0.0
  git -C "$proj" tag -d v1.0.0 >/dev/null
  # ...and this checkout holds the annotated one the core makes.
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state push UNREADABLE
  assert_output_contains "lightweight"
}

# ssh_stub -- an `ssh` on the stubs PATH that records what git handed it and
# fails the way an unreachable host does, so a remote read over ssh reaches it
# and nothing leaves the machine.
ssh_stub() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/ssh" <<SH
#!/bin/sh
printf 'prompt=%s argv=%s\n' "\${GIT_TERMINAL_PROMPT-unset}" "\$*" >>"$DEVBIN_TEST_TMPDIR/ssh.calls"
exit 255
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/ssh"
}

# 0088 row 3
@test "a remote read cannot ask at the terminal: git's credential prompt is off and ssh runs in batch mode" {
  # git asks for a credential on /dev/tty, not on stdin, so capturing the
  # call's output does not stop it: measured (0088), ls-remote BLOCKS on
  # a pty for an HTTP 401 and fails loudly with no tty. A bats run has no tty,
  # so the arm reads what git and ssh were handed rather than watching a prompt.
  proj="$(released_project)"
  git -C "$proj" remote add far ssh://git@example.invalid/demo.git
  ssh_stub
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state push UNREADABLE
  [ -s "$DEVBIN_TEST_TMPDIR/ssh.calls" ] || fail "no ssh was run: the arm did not reach a remote over ssh"
  local calls
  calls="$(cat "$DEVBIN_TEST_TMPDIR/ssh.calls")"
  grep -q 'prompt=0 ' <<<"$calls" || fail "git's terminal prompt was not turned off for the remote read:
$calls"
  grep -q -- '-o BatchMode=yes' <<<"$calls" || fail "ssh was not run in batch mode, so a passphrase or host-key ask reaches the terminal:
$calls"
}

# 0088 row 3
@test "batch mode is added to the person's own ssh command, never in place of it" {
  proj="$(released_project)"
  git -C "$proj" remote add far ssh://git@example.invalid/demo.git
  ssh_stub
  # core.sshCommand, as a project would set it.
  git -C "$proj" config core.sshCommand "ssh -o IdentitiesOnly=yes"
  run release_in "$proj" status v1.0.0
  assert_failure
  grep -q -- '-o IdentitiesOnly=yes -o BatchMode=yes' "$DEVBIN_TEST_TMPDIR/ssh.calls" ||
    fail "core.sshCommand was dropped or not extended:
$(cat "$DEVBIN_TEST_TMPDIR/ssh.calls")"
  # GIT_SSH_COMMAND outranks core.sshCommand in git, and here too.
  : >"$DEVBIN_TEST_TMPDIR/ssh.calls"
  GIT_SSH_COMMAND="ssh -o ConnectTimeout=7" run release_in "$proj" status v1.0.0
  assert_failure
  grep -q -- '-o ConnectTimeout=7 -o BatchMode=yes' "$DEVBIN_TEST_TMPDIR/ssh.calls" ||
    fail "GIT_SSH_COMMAND was dropped or not extended:
$(cat "$DEVBIN_TEST_TMPDIR/ssh.calls")"
  ! grep -q 'IdentitiesOnly' "$DEVBIN_TEST_TMPDIR/ssh.calls" ||
    fail "core.sshCommand was used although GIT_SSH_COMMAND is set"
}

# AT-3.6
@test "a note that cannot be read is UNREADABLE, never absent and never pending" {
  proj="$(released_project)"
  printf '# Changelog\n\n## [1.0.0] garbled\n\n- first\n' >"$proj/CHANGELOG.md"
  commit_all "$proj" "garbled"
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state stamp UNREADABLE
  assert_state commit UNREADABLE
}

# AT-3.6
@test "without gh the release object is UNREADABLE, and object: none never asks" {
  proj="$(released_project)"
  tag_release "$proj"
  # A PATH holding git and the shell's basics but no gh at all.
  mkdir -p "$DEVBIN_TEST_TMPDIR/nogh"
  local t
  for t in git bash sh awk sed grep cat mktemp rm tar find sort tr head cut date wc dirname basename env mkdir ls readlink cksum uname printf cp mv chmod touch diff tee od xargs; do
    [ -x "$(command -v "$t" 2>/dev/null)" ] && ln -sf "$(command -v "$t")" "$DEVBIN_TEST_TMPDIR/nogh/$t"
  done
  run env PATH="$DEVBIN_TEST_TMPDIR/nogh" bash -c "cd '$proj' && ./bin/devbin release status v1.0.0"
  assert_failure
  assert_state object UNREADABLE
  assert_output_contains "gh"
}

# ============================================================================
# THE MATERIALISER (AC-3.2)
# ============================================================================

# AT-3.7
@test "a commit's tree is materialised outside the project and removed on every exit path, a refusal included" {
  proj="$(released_project)"
  tag_release "$proj"
  local scratch="$DEVBIN_TEST_TMPDIR/scratch"
  mkdir -p "$scratch"
  TMPDIR="$scratch" run release_in "$proj" status v1.0.0
  assert_success
  [ -z "$(ls -A "$scratch")" ] || fail "the materialised tree was left behind: $(ls -A "$scratch")"

  # A refusal path: the note in the tagged tree cannot be read.
  printf '# Changelog\n\n## [1.0.0] garbled\n' >"$proj/CHANGELOG.md"
  commit_all "$proj" "garbled"
  git -C "$proj" tag -d v1.0.0 >/dev/null
  tag_release "$proj"
  TMPDIR="$scratch" run release_in "$proj" status v1.0.0
  assert_failure
  [ -z "$(ls -A "$scratch")" ] || fail "a refusal left the materialised tree behind: $(ls -A "$scratch")"
}

# AT-3.7
@test "a TMPDIR inside the project is refused, because a tree materialised there is dirt status would then report" {
  proj="$(released_project)"
  tag_release "$proj"
  mkdir -p "$proj/tmp"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  TMPDIR="$proj/tmp" run release_in "$proj" status v1.0.0
  assert_failure
  assert_output_contains "inside the project"
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "the refused run wrote into the project"
}

# ============================================================================
# EXPORT ATTRIBUTES DO NOT REACH THE MATERIALISED TREE (AC-3.2, amended). The
# first build used `git archive`, which applies them, and refused them on the
# paths a release owns; a parent directory's attribute and an OLDER note's got
# past that. The tree is now written from an index of its own, so each of these
# reads the commit's bytes.
# ============================================================================

# meta_versioned <proj> -- move the version file under meta/, and say so in the
# config, so a DIRECTORY attribute can reach it.
meta_versioned() {
  local cfg="$1/bin/.devbin/config.yaml"
  awk '{ print } /^  name: demo$/ { print "  version_from: meta/VERSION" }' "$cfg" >"$cfg.new" && mv -f "$cfg.new" "$cfg"
  mkdir -p "$1/meta"
  git -C "$1" mv VERSION meta/VERSION
  commit_all "$1" "version under meta/"
}

# two_notes <proj> -- notes.kind releases with an older note and the current
# one, and the views rendered from both, uncommitted.
two_notes() {
  mkdir -p "$1/RELEASES"
  printf 'version: 0.9.0\nheadline: zero\nstatus: released\ndate: 2025-12-01\n\n## Fixed\n\n- zero\n' >"$1/RELEASES/0.9.0.md"
  printf 'version: 1.0.0\nheadline: first\nstatus: released\ndate: 2026-01-01\n\n## Fixed\n\n- first\n' >"$1/RELEASES/1.0.0.md"
  run release_in "$1" notes
  assert_success
}

# AT-3.8
@test "an export-ignored note is read from the commit, never as an absent note" {
  proj="$(released_project)"
  printf 'CHANGELOG.md export-ignore\n' >"$proj/.gitattributes"
  commit_all "$proj" "export-ignore the changelog"
  tag_release "$proj"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
  assert_state commit already
  refute_output_contains "absent"
}

# AT-3.8
@test "export-ignore on a DIRECTORY above the version file does not hide it, in each spelling" {
  # git archive dropped the file for every one of these while check-attr on the
  # file answered `unspecified` (measured, git 2.55).
  local spelling
  for spelling in 'meta/ export-ignore' 'meta export-ignore' '/meta export-ignore'; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git"
    proj="$(released_project)"
    meta_versioned "$proj"
    printf '%s\n' "$spelling" >"$proj/.gitattributes"
    commit_all "$proj" "export-ignore meta"
    run release_in "$proj" status v1.0.0
    assert_state stamp already
    assert_state commit already
  done
}

# AT-3.8
@test "export-ignore on an OLDER note leaves the views current: they render from every note" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  two_notes "$proj"
  printf 'RELEASES/0.9.0.md export-ignore\n' >"$proj/.gitattributes"
  commit_all "$proj" "notes, an older one export-ignored"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
  assert_state commit already
  refute_output_contains "STALE"
}

@test "the same two notes with no attribute read already -- the older-note arm's control" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  two_notes "$proj"
  commit_all "$proj" "notes"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
  assert_state commit already
}

# AT-3.8
@test "export-subst does not rewrite the note: a tag whose message is the note's literal body is reused" {
  proj="$(released_project)"
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- first $Format:%%h$\n' >"$proj/CHANGELOG.md"
  printf 'CHANGELOG.md export-subst\n' >"$proj/.gitattributes"
  commit_all "$proj" "export-subst the changelog"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a v1.0.0 -m '- first $Format:%h$' --cleanup=whitespace
  run release_in "$proj" status v1.0.0
  assert_state commit already
  assert_state tag already
  refute_output_contains "is not the notes body"
}

# notes_tagged <proj> -- notes.kind releases, one note, committed and tagged.
notes_tagged() {
  mkdir -p "$1/RELEASES"
  printf 'version: 1.0.0\nheadline: first\nstatus: released\ndate: 2026-01-01\n\n## Fixed\n\n- first\n' >"$1/RELEASES/1.0.0.md"
  run release_in "$1" notes
  assert_success
  commit_all "$1" "notes"
  tag_release "$1"
}

# AT-3.8
@test "an eol attribute committed AFTER the tag does not rewrite the tagged release: its attributes are the commit's" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  notes_tagged "$proj"
  printf '* text eol=crlf\n' >"$proj/.gitattributes"
  commit_all "$proj" "later: eol attribute"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
  assert_state commit already
}

# AT-3.8
@test "an UNCOMMITTED attribute in the working tree does not rewrite the release commit either" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  notes_tagged "$proj"
  printf '* text eol=crlf\n' >"$proj/.gitattributes"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
}

@test "the same tagged release with an unrelated later commit reads already -- the later-attribute arms' control" {
  proj="$(released_project '
release:
  notes:
    kind: releases')"
  notes_tagged "$proj"
  printf 'later\n' >"$proj/LATER"
  commit_all "$proj" "later: unrelated"
  run release_in "$proj" status v1.0.0
  assert_state stamp already
  assert_state commit already
}

@test "a tag whose release commit cannot be materialised says its message could not be compared, not that it differs" {
  proj="$(released_project)"
  printf 'CHANGELOG.md filter=boom\n' >"$proj/.gitattributes"
  commit_all "$proj" "a filter on the changelog"
  tag_release "$proj"
  # Declared after the commit, so only the materialiser meets it: a required
  # smudge filter that fails fails checkout-index (git 2.55, measured).
  git -C "$proj" config filter.boom.smudge false
  git -C "$proj" config filter.boom.clean cat
  git -C "$proj" config filter.boom.required true
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state commit UNREADABLE
  assert_output_contains "could not materialise"
  assert_output_contains "could not be compared"
  refute_output_contains "is not the notes body"
}

# ============================================================================
# gh TOLD WHICH REPOSITORY (WP-03)
# ============================================================================

@test "gh is told the repository, read off origin's configured url, with its prompt off" {
  proj="$(released_project)"
  run release_in "$proj" status v1.0.0
  assert_state object pending
  grep -q -- 'release view v1.0.0 --repo t/demo\|release view --repo t/demo v1.0.0' "$DEVBIN_TEST_TMPDIR/gh.calls" ||
    fail "gh was not told t/demo:
$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  grep -q '^prompt=1 release view' "$DEVBIN_TEST_TMPDIR/gh.env" ||
    fail "gh's prompt was not disabled:
$(cat "$DEVBIN_TEST_TMPDIR/gh.env")"
}

@test "a declared release.repo is the repository gh is told, over the remote's" {
  proj="$(released_project 'release:
  repo: acme/widgets')"
  run release_in "$proj" status v1.0.0
  grep -q -- '--repo acme/widgets' "$DEVBIN_TEST_TMPDIR/gh.calls" ||
    fail "gh was not told acme/widgets:
$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  ! grep -q -- '--repo t/demo' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "the remote's repository was used over the declared one"
}

@test "a repository that cannot be resolved is UNREADABLE naming release.repo, and gh is never left to guess" {
  proj="$(released_project)"
  # origin now names a path, not a repository, and there is no declared key.
  git -C "$proj" remote set-url origin "$DEVBIN_TEST_TMPDIR/remote.git"
  : >"$DEVBIN_TEST_TMPDIR/gh.calls"
  run release_in "$proj" status v1.0.0
  assert_failure
  assert_state object UNREADABLE
  assert_output_contains "release.repo"
  ! grep -q 'release view' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was asked without a repository:
$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# ============================================================================
# release_repo'S URL SHAPES AND REMOTE CHOICE, AND release_gh'S STDIN (WP-03):
# each of these paths had no arm, and each arm kills a mutant written for it.
# ============================================================================

# repo_told <want> -- gh was asked with --repo <want>, or fail showing the calls.
repo_told() {
  grep -q -- "--repo $1\( \|\$\)" "$DEVBIN_TEST_TMPDIR/gh.calls" ||
    fail "gh was not told $1:
$(cat "$DEVBIN_TEST_TMPDIR/gh.calls" 2>/dev/null)
$output"
}

@test "each url shape origin can carry names the repository gh is told" {
  local shape want
  while IFS='|' read -r shape want; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project)"
    origin_at "$proj" "$shape"
    run release_in "$proj" status v1.0.0
    repo_told "$want"
  done <<'SHAPES'
git@github.com:t/demo.git|t/demo
ssh://git@github.com:22/t/demo.git|t/demo
https://someone@github.com/t/demo/|t/demo
https://ghe.example.com/t/demo.git|ghe.example.com/t/demo
SHAPES
}

@test "an scp url with no user, an ssh alias's form, names the repository gh is told, read by git's own rule (0218)" {
  # Refused as naming no host until url_host_path read the scp form as git
  # does: no / before the first :, with or without a user.
  proj="$(released_project)"
  origin_at "$proj" "github-alias:t/demo.git"
  run release_in "$proj" status v1.0.0
  repo_told github-alias/t/demo
}

@test "the FIRST declared remote names the repository, not origin" {
  proj="$(released_project '
release:
  remotes:
    - upstream
    - origin')"
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf https://github.com/u/up.git
  git -C "$proj" remote add upstream https://github.com/u/up.git
  run release_in "$proj" status v1.0.0
  repo_told u/up
}

@test "with no origin and exactly one remote, that remote names the repository" {
  proj="$(released_project)"
  git -C "$proj" remote rename origin hub
  run release_in "$proj" status v1.0.0
  repo_told t/demo
}

@test "with no origin and two remotes, nothing declared, the object is UNREADABLE naming release.repo and gh is never asked" {
  proj="$(released_project)"
  git -C "$proj" remote rename origin hub
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf https://github.com/a/other.git
  git -C "$proj" remote add another https://github.com/a/other.git
  : >"$DEVBIN_TEST_TMPDIR/gh.calls"
  run release_in "$proj" status v1.0.0
  assert_state object UNREADABLE
  assert_output_contains "release.repo"
  ! grep -q 'release view' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was asked: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "gh reads EOF on stdin even when the caller's stdin has an answer waiting" {
  proj="$(released_project)"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/gh" <<SH
#!/bin/sh
if read -r line; then echo "stdin=\$line" >>"$DEVBIN_TEST_TMPDIR/gh.stdin"; else echo "stdin=eof" >>"$DEVBIN_TEST_TMPDIR/gh.stdin"; fi
echo "release not found" >&2
exit 1
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/gh"
  # devbin_run gives every run </dev/null, so the answer is piped past it here.
  run bash -c 'cd "$1" && printf "y\n" | PATH="$2:$PATH" ./bin/devbin release status v1.0.0' _ "$proj" "$DEVBIN_TEST_TMPDIR/stubs"
  grep -qx 'stdin=eof' "$DEVBIN_TEST_TMPDIR/gh.stdin" || fail "gh read the caller's stdin: $(cat "$DEVBIN_TEST_TMPDIR/gh.stdin")"
}

# ============================================================================
# release_repo'S REFUSALS PRINT NO USERINFO (issue 0188). A remote's url can
# carry a token, and a refusal reaches the terminal, a cut's sealed log and CI's
# job log, so each refusal prints the url with its userinfo left out. The
# tokens below are fake, and each arm refutes their distinctive part,
# TOKEN-0188, and the user, fakeuser0188, in the output. That output is
# release_repo's alone: insteadOf hands git the bare remote's path before git
# parses the url, so git's and ssh's own messages, which can carry a url's
# userinfo against a real remote, are not under test here.
# ============================================================================

@test "release_repo's refusal that a url is not HOST/OWNER/NAME prints no userinfo, in the URL form and the scp form (0188)" {
  local url shown bad=""
  # The third holds glob characters, which are never read as a pattern. Every
  # url is read before the arm fails, so its failure names each one whose
  # refusal printed userinfo.
  while IFS='|' read -r url shown; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project)"
    origin_at "$proj" "$url"
    run release_in "$proj" status v1.0.0
    assert_state object UNREADABLE
    [[ "$(row_of object)" == *"remote origin's url ($shown) is not HOST/OWNER/NAME -- declare release.repo: OWNER/NAME" ]] ||
      bad+="
- $url: the object row does not name $shown, the url without its userinfo: $(row_of object)"
    [[ "$output" != *TOKEN-0188* && "$output" != *fakeuser0188* ]] ||
      bad+="
- $url: the output carries its userinfo"
  done <<'URLS'
https://fakeuser0188:FAKE-TOKEN-0188@gitlab.example/group/sub/repo.git|https://gitlab.example/group/sub/repo.git
FAKE-TOKEN-0188@gitlab.example:group/sub/repo|gitlab.example:group/sub/repo
https://fakeuser0188:FAKE[*]TOKEN-0188@gitlab.example/group/sub/repo.git|https://gitlab.example/group/sub/repo.git
URLS
  [ -z "$bad" ] || fail "release_repo's refusal printed userinfo:$bad"
}

@test "release_repo's refusal of a no-scheme url with a userinfo and no host:path prints no userinfo either (0188)" {
  proj="$(released_project)"
  # No scheme, and its first : comes before any /, so git reads it as the scp
  # form: host fakeuser0188, and a path that is not OWNER/NAME (0218; it was
  # refused as naming no host before release_repo read the scp form git's way).
  origin_at "$proj" "fakeuser0188:FAKE-TOKEN-0188@gitlab.example/group/repo"
  run release_in "$proj" status v1.0.0
  assert_state object UNREADABLE
  [[ "$(row_of object)" == *"remote origin's url (gitlab.example/group/repo) is not HOST/OWNER/NAME -- declare release.repo: OWNER/NAME" ]] ||
    fail "the object row does not name the url without its userinfo:
$output"
  refute_output_contains "TOKEN-0188"
  refute_output_contains "fakeuser0188"
}

@test "a url holding more than one @ ahead of its host is refused, its userinfo left out, and no part of its password reaches gh (0188)" {
  local url shown bad=""
  # Read at its first @, each of these gave a host holding the rest of the
  # password: the first a refusal that printed it, the other two, with an
  # OWNER/NAME path, a repository gh was told and pre-flight asked about. Each
  # is refused now, printed through release_url_shown, which reads at the last
  # @, so none of the password is in the refusal.
  while IFS='|' read -r url shown; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project)"
    origin_at "$proj" "$url"
    run release_in "$proj" status v1.0.0
    [ "$(state_of object)" = UNREADABLE ] &&
      [[ "$(row_of object)" == *"remote origin's url ($shown) holds more than one @ ahead of its host, so where its userinfo ends cannot be told -- write an @ in a userinfo as %40, or declare release.repo: OWNER/NAME" ]] ||
      bad+="
- $url: the object row does not refuse it naming $shown: $(row_of object)"
    [[ "$output" != *TOKEN-0188* && "$output" != *fakeuser0188* ]] ||
      bad+="
- $url: the output carries its userinfo"
    ! grep -q -e "TOKEN-0188" -e "fakeuser0188" "$DEVBIN_TEST_TMPDIR/gh.calls" 2>/dev/null ||
      bad+="
- $url: gh was told: $(grep -e "TOKEN-0188" -e "fakeuser0188" "$DEVBIN_TEST_TMPDIR/gh.calls")"
  done <<'URLS'
https://fakeuser0188:FAKE@TOKEN-0188@gitlab.example/group/sub/repo.git|https://gitlab.example/group/sub/repo.git
https://fakeuser0188:FAKE@TOKEN-0188@github.com/t/demo.git|https://github.com/t/demo.git
fakeuser0188@FAKE-TOKEN-0188@gitlab.example:group/repo|gitlab.example:group/repo
URLS
  [ -z "$bad" ] || fail "a url holding more than one @ ahead of its host was read:$bad"
}

@test "a url with no userinfo reads as before in both refusals, an @ in its path included, and OWNER/NAME read past a token prints no token (0188)" {
  local url why
  # THE CONTROLS: with no userinfo there is nothing to leave out, so each
  # refusal names the url as configured. An @ after the first / is in the
  # path, and is never read as the end of a userinfo.
  while IFS='|' read -r url why; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project)"
    origin_at "$proj" "$url"
    run release_in "$proj" status v1.0.0
    assert_state object UNREADABLE
    [[ "$(row_of object)" == *"remote origin's url ($url) $why -- declare release.repo: OWNER/NAME" ]] ||
      fail "the object row does not name $url as configured:
$output"
  done <<'URLS'
https://gitlab.example/group/sub/repo.git|is not HOST/OWNER/NAME
https://gitlab.example/group/sub@x/repo.git|is not HOST/OWNER/NAME
gitlab.example/group/repo|names no host
URLS
  # The OWNER/NAME path is unchanged: read past a token, it names the
  # repository, which repo_told holds. Nothing on that path prints the url, so
  # the refutes after it are guards: a token reaching gh's --repo fails
  # repo_told first.
  rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
  proj="$(released_project)"
  origin_at "$proj" "https://fakeuser0188:FAKE-TOKEN-0188@github.com/t/demo.git"
  run release_in "$proj" status v1.0.0
  repo_told t/demo
  refute_output_contains "TOKEN-0188"
  ! grep -q "TOKEN-0188" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was told the token:
$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "release_repo's refusal prints a url whose password holds a raw / with its userinfo left out, and a host:port with an @ in its path as configured (0189)" {
  local url shown
  # release_url_shown, which release_repo's refusals print through, read a
  # raw / in a password as the end of the url's host, so it printed the url
  # whole. A `:` ahead of that / that is no port's tells the two apart.
  while IFS='|' read -r url shown; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project)"
    origin_at "$proj" "$url"
    run release_in "$proj" status v1.0.0
    assert_state object UNREADABLE
    [[ "$(row_of object)" == *"remote origin's url ($shown) is not HOST/OWNER/NAME -- declare release.repo: OWNER/NAME" ]] ||
      fail "the object row does not name $shown:
$output"
    refute_output_contains "TOKEN0189"
    refute_output_contains "FAKE"
    refute_output_contains "fakeuser0189"
  done <<'URLS'
https://fakeuser0189:FAKE/TOKEN0189@gitlab.example/group/sub/repo.git|https://gitlab.example/group/sub/repo.git
https://gitlab.example:8443/group/sub@x/repo.git|https://gitlab.example:8443/group/sub@x/repo.git
URLS
}

@test "a remotes entry that is a url is UNREADABLE to release status, which names it with no part of its userinfo and never hands it to git (0189)" {
  local url
  while IFS= read -r url; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(released_project "
release:
  remotes:
    - $url")"
    run release_in "$proj" status v1.0.0
    assert_output_contains "remote https://host.invalid/o/r.git is declared and does not exist"
    refute_output_contains "did not answer ls-remote"
    refute_output_contains "TOKEN0189"
    refute_output_contains "FAKE"
    refute_output_contains "fakeuser0189"
  done <<'URLS'
https://fakeuser0189:FAKETOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE@TOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE/TOKEN0189@host.invalid/o/r.git
URLS
}
