#!/usr/bin/env bats
# releasecut.bats - a cut, the steps from resolve to after, with --dry-run and --yes
# (ST0007 WP-04 to WP-06, ST0011)
#
# Resolve, pre-flight, confirm, stamp, commit, legs, tag, push, object and
# after. Each step reads its postcondition first, so a re-run of the same
# target continues; each failure is a non-zero exit naming the step, and
# --dry-run runs no gate and prints each step as what it would do. The confirm
# step comes before anything runs (ST0011), so an arm that needs the stamp,
# commit and legs passes --yes, and one that needs a cut stopped after its
# legs stops it at the tag step (cut_to_tag_stop).

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# cut_project, the fixture every arm here starts from, is in
# tests/lib/release_fixtures.bash, since releaseattach.bats cuts it too.

# gate_does <script> -- what the probe gate does when it runs, as bash.
gate_does() { printf '%s\n' "$1" >"$DEVBIN_TEST_TMPDIR/gate.sh"; }

# gate_ran -- true when the probe gate ran in this arm.
gate_ran() { [ -s "$DEVBIN_TEST_TMPDIR/gate.calls" ]; }

# release_commits <proj> -- how many commits are release commits.
release_commits() { git -C "$1" log --format=%s | grep -c '^release: ' || true; }

# assert_stopped_at <step> -- the run failed at the <step> step, and said so.
assert_stopped_at() {
  assert_failure
  assert_state "$1" FAILED
  assert_output_contains "stopped at the $1 step"
}

# other_clone -- a second clone of the fixture's remote, committing as t.
other_clone() {
  local other="$DEVBIN_TEST_TMPDIR/other"
  git clone -q "$DEVBIN_TEST_TMPDIR/remote.git" "$other"
  git -C "$other" config user.name t
  git -C "$other" config user.email t@t
  printf '%s\n' "$other"
}

# last_line -- the last line of the last `run`'s output that is not blank.
last_line() { awk 'NF { last = $0 } END { print last }' <<<"$output"; }

# date_refused_path -- PATH with a date in front whose `+%F`, the cut's one
# read of the clock for the release's date, fails, saying so, and which runs
# the real date for everything else, as tag_refused_path does for git.
date_refused_path() {
  local shim="$DEVBIN_TEST_TMPDIR/daterefused" real
  real="$(command -v date)"
  mkdir -p "$shim"
  # shellcheck disable=SC2016 # the shim's own $1, expanded when it runs
  printf '#!/bin/sh\nif [ "$1" = +%%F ]; then echo "the fixture refuses date +%%F" >&2; exit 1; fi\nexec "%s" "$@"\n' "$real" >"$shim/date"
  chmod +x "$shim/date"
  printf '%s:%s\n' "$shim" "$PATH"
}

# ============================================================================
# THE WHOLE RUN, AND A RE-RUN
# ============================================================================

# AT-5.3, AT-2.1
@test "with no terminal and no --yes, a cut stops at the confirm step with exit 1, before anything is stamped, committed or run (AC-5.3, 0130, ST0011 WP02)" {
  local head
  proj="$(cut_project)"
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_state resolve done
  assert_state pre-flight done
  assert_state commit "(no row commit)"
  assert_state legs "(no row legs)"
  if gate_ran; then fail "a gate ran before the confirm step was answered"; fi
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "a commit was made before the confirm step was answered"
  [ "$(cat "$proj/VERSION")" = 1.0.0 ] || fail "the version was stamped before the confirm step was answered"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree was written before the confirm step was answered"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
}

@test "given --yes, a cut stamps, commits and gates after the confirm step, and the release commit carries the stamp (AC-5.3, ST0011)" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  assert_state confirm done
  assert_state stamp done
  assert_state commit done
  assert_state legs done
  [ "$(git -C "$proj" log -1 --format=%s)" = "release: v1.0.1" ]
  [ "$(git -C "$proj" show HEAD:VERSION)" = 1.0.1 ]
  local note
  note="$(git -C "$proj" show HEAD:CHANGELOG.md)" && grep -qF "## [1.0.1] - $(date +%F)" <<<"$note" ||
    fail "the release commit's note is not dated today"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree is not clean"
}

@test "--patch bumps the newest matching tag, and the summary names the version to resume with" {
  proj="$(cut_project)"
  run release_in "$proj" --patch
  assert_stopped_at_confirm
  assert_output_contains "1.0.1 from --patch, tag v1.0.1, new"
  assert_output_contains "resume with: bin/devbin release v1.0.1"
}

# AT-5.1, AT-1.3
@test "a re-run continues: stamp, commit and gates already, the gates' sealed green for the release commit standing for them, no second commit (ST0011)" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  head="$(git -C "$proj" rev-parse HEAD)"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state stamp already
  assert_state commit already
  assert_state legs already
  if gate_ran; then fail "a gate ran again over the gates' sealed green for the release commit"; fi
  [[ "$(row_of legs)" == *"${head:0:12}"*GATES.errors* ]] ||
    fail "the legs row does not name the release commit and the seal that stands for it: $(row_of legs)"
  [ "$(git -C "$proj" rev-parse 'v1.0.1^{commit}')" = "$head" ] || fail "the tag is not at the release commit the first run made"
  [ "$(release_commits "$proj")" -eq 1 ]
}

# AT-1.3
@test "a release commit made again is not the commit the gates' seal stands for: the gates run on it (ST0011)" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  head="$(git -C "$proj" rev-parse HEAD)"
  # The same tree and message under another commit, as a hand re-commit leaves it.
  GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" git -C "$proj" commit -q --amend --no-edit
  [ "$(git -C "$proj" rev-parse HEAD)" != "$head" ] || fail "the amend made no new commit"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state commit already
  assert_state legs done
  gate_ran || fail "the gates did not run on a release commit their seal does not name"
}

# AT-1.3
@test "a gates seal left in flight stands for nothing: the next run runs the gates (ST0011)" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  local seal
  seal="$(readlink -f "$proj/tmp/release/LATEST_GATES.errors")" && [ -f "$seal" ] ||
    fail "the cut left no gates seal under tmp/release/"
  # What a run killed before its seal leaves: the in-flight marker, from its one home.
  bash -c '. "$1/helpers" && . "$1/runlog" && inflight_marker' _ "$DEVBIN_LIB_DIR" >"$seal"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  gate_ran || fail "a gates seal in flight stood for the release commit"
}

# AT-2.3
@test "the cut's sealed log carries start and end clock lines in UTC, a host line, and one leg line for its gates: the word, the release commit, the seconds and the record (ST0011 WP02)" {
  local out sha clock
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  out="$(readlink -f "$proj/tmp/release/LATEST_RELEASE.out")" && [ -f "$out" ] ||
    fail "the cut left no RELEASE seal under tmp/release/"
  sha="$(git -C "$proj" rev-parse 'v1.0.1^{commit}')"
  clock='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
  grep -qE "^devbin\|   start: $clock\$" "$out" || fail "no start line in the invocation block: $(grep -F 'start' "$out" || echo '(none)')"
  grep -qE "^devbin\| end: $clock\$" "$out" || fail "no end line before the seal: $(grep -F 'end:' "$out" || echo '(none)')"
  grep -qxF "devbin|   host: $(uname -n)" "$out" || fail "no host line: $(grep -F 'host' "$out" || echo '(none)')"
  grep -qE "^devbin\| leg: local green $sha [0-9]+s /.*\\.GATES\\.errors\$" "$out" ||
    fail "no leg line naming the gates' green on the release commit: $(grep -F 'leg:' "$out" || echo '(none)')"
}

# AT-1.3
@test "release gates runs the declared gates in place under one GATES seal naming the commit it ran on, exits 1 when a gate fails, and refuses a tree that is not one commit, clean, writing no seal (ST0011 WP02)" {
  proj="$(cut_project)"
  run release_in "$proj" gates
  assert_success
  gate_ran || fail "release gates ran no gate"
  local out
  out="$(readlink -f "$proj/tmp/release/LATEST_GATES.out")" && [ -f "$out" ] ||
    fail "release gates left no GATES seal under tmp/release/"
  grep -qxF "devbin|   commit: $(git -C "$proj" rev-parse HEAD)" "$out" ||
    fail "the seal does not name HEAD as the commit it ran on: $(grep -F 'commit' "$out" || echo '(no commit line)')"
  grep -qF "devbin|   from: release.gates (probe) " "$out" ||
    fail "the seal does not name the gates it ran: $(grep -F 'from:' "$out" || echo '(no from line)')"
  [ ! -s "${out%.out}.errors" ] || fail "a green run sealed non-empty: $(cat "${out%.out}.errors")"
  gate_does 'exit 4'
  # --rerun: the green just sealed stands for HEAD, and would be read as already.
  run release_in "$proj" gates --rerun
  [ "$status" -eq 1 ] || fail "want exit 1 when a gate fails, got $status: $output"
  assert_output_contains "gate 'probe' failed (exit 4)"
  [ -s "$(readlink -f "$proj/tmp/release/LATEST_GATES.errors")" ] || fail "a red run sealed empty"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.sh" "$DEVBIN_TEST_TMPDIR/gate.calls"
  out="$(readlink -f "$proj/tmp/release/LATEST_GATES.out")"
  printf 'dirt\n' >>"$proj/README.md"
  run release_in "$proj" gates
  [ "$status" -eq 1 ] || fail "want exit 1 on a dirty tree, got $status: $output"
  assert_output_contains "is not one commit, clean"
  if gate_ran; then fail "a gate ran on a tree that is not one commit"; fi
  [ "$(readlink -f "$proj/tmp/release/LATEST_GATES.out")" = "$out" ] || fail "a dirty tree's run left a GATES seal"
}

@test "release gates reads its record first: over a sealed green for HEAD on this platform it prints the legs row already and runs nothing (ST0011 WP02)" {
  proj="$(cut_project)"
  run release_in "$proj" gates
  assert_success
  gate_ran || fail "the first release gates ran no gate"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" gates
  assert_success
  assert_state legs already
  [[ "$(row_of legs)" == *"$(git -C "$proj" rev-parse --short=12 HEAD)"*GATES.errors* ]] ||
    fail "the row does not name HEAD and the seal that stands for it: $(row_of legs)"
  if gate_ran; then fail "a gate ran over a sealed green for HEAD"; fi
}

@test "release gates --rerun runs the gates over a sealed green for HEAD on this platform (ST0011 WP02)" {
  proj="$(cut_project)"
  run release_in "$proj" gates
  assert_success
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" gates --rerun
  assert_success
  gate_ran || fail "--rerun ran no gate over a sealed green for HEAD"
}

@test "a cut refuses at pre-flight a RUNLOG_KEEP_RUNS the gates' purge would refuse, before anything runs, and release gates refuses it before any gate runs (ST0011 WP02)" {
  proj="$(cut_project)"
  RUNLOG_KEEP_RUNS=0 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at pre-flight
  assert_output_contains "RUNLOG_KEEP_RUNS=0 would purge the run being kept"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
  RUNLOG_KEEP_RUNS=many run release_in "$proj" gates
  assert_failure
  assert_output_contains "RUNLOG_KEEP_RUNS must be a whole number, got 'many'"
  if gate_ran; then fail "release gates ran a gate whose run it could not purge after"; fi
}

@test "a cut, release status and release gates name each git variable they clear, and the repository they use instead, and a cut under GIT_DIR commits into the project's own (ST0011 WP02)" {
  local other
  other="$DEVBIN_TEST_TMPDIR/other-repo"
  git init -q -b main "$other"
  git -C "$other" -c maintenance.auto=false -c gc.auto=0 -c user.name=t -c user.email=t@t commit -q --allow-empty -m "another repository"
  proj="$(cut_project)"
  GIT_DIR="$other/.git" cut_to_tag_stop "$proj" v1.0.1
  assert_output_contains "release: GIT_DIR inherited and cleared: every git read and write here is in the repository at"
  [ "$(git -C "$proj" log -1 --format=%s)" = "release: v1.0.1" ] || fail "the release commit is not in the project's repository"
  [ "$(git -C "$other" log -1 --format=%s)" = "another repository" ] || fail "the cut committed into the repository GIT_DIR named"
  GIT_DIR="$other/.git" run release_in "$proj" status v1.0.1
  assert_output_contains "release status: GIT_DIR inherited and cleared"
  GIT_DIR="$other/.git" run release_in "$proj" gates
  assert_output_contains "release gates: GIT_DIR inherited and cleared"
}

# ============================================================================
# EVERY STEP'S FAILURE IS A NON-ZERO EXIT NAMING THE STEP (AC-4.1)
# ============================================================================

# AT-4.1
@test "the resolve step fails, named: a target that is not above the newest release" {
  proj="$(cut_project)"
  run release_in "$proj" v0.9.0
  assert_stopped_at resolve
  assert_output_contains "not greater than the newest release, v1.0.0"
  [ "$(cat "$proj/VERSION")" = 1.0.0 ]
  if gate_ran; then fail "a gate ran after the resolve step failed"; fi
}

# AT-4.1
@test "the resolve step fails, named: --patch with no tag matching the template" {
  proj="$(cut_project '  tag: "rel-{version}"
  gates:
    - probe')"
  run release_in "$proj" --patch
  assert_stopped_at resolve
  assert_output_contains "there is none -- name the version"
}

# AT-4.1
@test "the pre-flight step fails, named: not on the release branch, and nothing is written" {
  proj="$(cut_project)"
  git -C "$proj" checkout -q -b topic
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "not on main: HEAD is topic"
  # The gated cut keeps its run log under the ignored tmp/release/, as every
  # gated verb does; that is the one thing a refused run may leave.
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a failed pre-flight wrote something"
  if gate_ran; then fail "a gate ran after pre-flight failed"; fi
}

# AT-4.1
@test "the stamp step fails, named: version set refuses" {
  proj="$(cut_project "" '  version_sidecars:
    - missing.txt')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at stamp
  assert_output_contains "version set 1.0.1 failed"
  if gate_ran; then fail "a gate ran after the stamp step failed"; fi
}

# AT-4.1
@test "the stamp step fails, named: a derived: command fails" {
  proj="$(cut_project '  derived:
    - false
  gates:
    - probe')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at stamp
  assert_output_contains "the derived: command 'false' failed"
  if gate_ran; then fail "a gate ran after the stamp step failed"; fi
}

# AT-4.1
@test "the commit step fails, named: the commit is refused by a hook, and no release commit is made" {
  proj="$(cut_project)"
  printf '#!/bin/sh\necho hook says no >&2\nexit 1\n' >"$proj/.git/hooks/pre-commit"
  chmod +x "$proj/.git/hooks/pre-commit"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at commit
  assert_output_contains "git commit failed"
  [ "$(release_commits "$proj")" -eq 0 ]
  if gate_ran; then fail "a gate ran after the commit step failed"; fi
}

# AT-4.1
@test "the gates step fails, named: a gate exits non-zero" {
  proj="$(cut_project)"
  gate_does 'exit 4'
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  assert_output_contains "gate 'probe' failed (exit 4)"
}

# ============================================================================
# THE GATES RUN ON THE RELEASE COMMIT, AND THE CORE CHECKS THAT THEY DID (AC-4.2)
# ============================================================================

# AT-4.2
@test "a gate that reads what only the stamp writes passes: the gates run after the stamp and commit steps" {
  proj="$(cut_project)"
  gate_does '[ "$(cat VERSION)" = 1.0.1 ] || { echo "gate saw VERSION $(cat VERSION)"; exit 9; }
[ "$(git log -1 --format=%s)" = "release: v1.0.1" ] || { echo "gate saw HEAD $(git log -1 --format=%s)"; exit 8; }'
  cut_to_tag_stop "$proj" v1.0.1
  assert_state legs done
}

# AT-4.2
@test "an untracked, non-ignored file outside the owned set is refused at pre-flight, naming it" {
  proj="$(cut_project)"
  : >"$proj/stray.txt"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "stray.txt"
  [ "$(cat "$proj/VERSION")" = 1.0.0 ]
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

# AT-4.2
@test "a gate that modifies a tracked path fails the gates step, naming it" {
  proj="$(cut_project)"
  gate_does 'echo more >>README.md'
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  assert_output_contains "a gate changed the tree: README.md"
}

# AT-4.2
@test "a gate that creates a path fails the gates step, naming it" {
  proj="$(cut_project)"
  gate_does ': >made-by-gate.txt'
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  assert_output_contains "a gate changed the tree: made-by-gate.txt"
}

# ============================================================================
# THE TREE RULE (AC-4.3)
# ============================================================================

# AT-4.3
@test "a dirty tracked path outside the owned set is refused at pre-flight, naming it" {
  proj="$(cut_project)"
  echo more >>"$proj/README.md"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "dirty outside what this release owns: README.md"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

@test "a project whose version cannot be read is refused at pre-flight in version_unread's words, and nothing is written: no VERSION, no release commit (0259)" {
  # The stamp step's version set starts a missing VERSION, and inside a cut
  # that is a side effect: a release commit holding a version file the project
  # never kept. So the cut refuses first, before any gate, stamp or commit.
  local head
  proj="$(cut_project)"
  git -C "$proj" rm -q VERSION
  git -C "$proj" commit -qm "no version file"
  git -C "$proj" push -q origin main
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "the version cannot be read: VERSION, the file project.version_from names, does not exist -- start it with: bin/devbin version set 0.1.0"
  [ ! -e "$proj/VERSION" ] || fail "the refused cut wrote VERSION"
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "the refused cut moved HEAD"
  ! git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null || fail "the refused cut made the tag"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

# AT-4.3
@test "a stamp a HUMAN wrote is committed as the release: dirt inside the owned set is not asked where it came from" {
  proj="$(cut_project)"
  printf '1.0.1\n' >"$proj/VERSION"
  sed "s/## \[1.0.1\] - Unreleased/## [1.0.1] - $(date +%F)/" "$proj/CHANGELOG.md" >"$proj/CHANGELOG.new"
  mv "$proj/CHANGELOG.new" "$proj/CHANGELOG.md"
  cut_to_tag_stop "$proj" v1.0.1
  assert_state stamp already
  assert_state commit done
  [ "$(git -C "$proj" show HEAD:VERSION)" = 1.0.1 ]
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree is not clean"
}

# AT-4.3, AT-5.1
@test "a stamp a KILLED RUN left is committed by the next run" {
  proj="$(cut_project)"
  # A run that stamped and then could not commit leaves the stamp in the tree.
  printf '#!/bin/sh\nexit 1\n' >"$proj/.git/hooks/pre-commit"
  chmod +x "$proj/.git/hooks/pre-commit"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at commit
  rm "$proj/.git/hooks/pre-commit"
  cut_to_tag_stop "$proj" v1.0.1
  assert_state stamp already
  assert_state commit done
  [ "$(release_commits "$proj")" -eq 1 ]
}

# ============================================================================
# THE REMOTES, BEFORE ANY GATE (AC-4.4)
# ============================================================================

# AT-4.4
@test "a remote whose branch has diverged from the release commit is refused, naming it, before any gate" {
  proj="$(cut_project)"
  other="$(other_clone)"
  git -C "$other" reset -q --hard HEAD~1
  echo elsewhere >"$other/elsewhere.txt"
  git -C "$other" add elsewhere.txt
  git -C "$other" commit -qm elsewhere
  git -C "$other" push -q -f origin main
  git -C "$proj" fetch -q origin
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "origin's main"
  assert_output_contains "has diverged from the release commit"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
  [ "$(cat "$proj/VERSION")" = 1.0.0 ]
}

# AT-4.4
@test "a remote that has moved past HEAD is refused while the release commit is still to be made on HEAD" {
  proj="$(cut_project)"
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  git -C "$proj" fetch -q origin
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "has moved past HEAD"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

# AT-4.4
@test "a remote that has moved past an existing release commit passes, its push already" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  git -C "$proj" push -q origin main
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  git -C "$proj" fetch -q origin
  cut_to_tag_stop "$proj" v1.0.1
  assert_state pre-flight done
  assert_state commit already
  assert_state legs already
  assert_output_contains "push tag to origin"
  refute_output_contains "push commit tag to origin"
}

# ============================================================================
# A TAG FOR THE TARGET MUST CARRY THE RELEASE (AC-4.5)
# ============================================================================

# AT-4.5
@test "a tag for the target whose VERSION is not the target is refused, and never moved or deleted" {
  proj="$(cut_project)"
  git -C "$proj" tag -a v1.0.1 -m wrong
  want="$(git -C "$proj" rev-parse refs/tags/v1.0.1)"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "v1.0.1 exists and its commit"
  assert_output_contains "does not carry the release"
  assert_output_contains "VERSION is 1.0.0"
  [ "$(git -C "$proj" rev-parse refs/tags/v1.0.1)" = "$want" ] || fail "the tag was moved"
}

# AT-4.5
@test "a tag for the target whose note is not dated is refused, and never moved or deleted" {
  proj="$(cut_project)"
  printf '1.0.1\n' >"$proj/VERSION"
  git -C "$proj" commit -qam "VERSION only"
  git -C "$proj" tag -a v1.0.1 -m wrong
  want="$(git -C "$proj" rev-parse refs/tags/v1.0.1)"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "the note for 1.0.1 is open"
  [ "$(git -C "$proj" rev-parse refs/tags/v1.0.1)" = "$want" ] || fail "the tag was moved"
}

# ============================================================================
# --dry-run (AC-4.6)
# ============================================================================

# AT-4.6, AT-2.3
@test "--dry-run writes nothing, runs no gate, reports every write through the object step as would, and names what it could not reach (ST0011 WP02)" {
  proj="$(cut_project)"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a dry run wrote something:
$output"
  assert_output_contains "DRY RUN"
  assert_state stamp would
  assert_state commit would
  assert_state legs would
  assert_state confirm would
  assert_state tag would
  assert_state push would
  assert_state object would
  if gate_ran; then fail "a dry run ran a gate"; fi
  assert_output_contains "NOT REACHED by this dry run"
  assert_output_contains "the confirm step's confirmation"
}

# AT-4.6
@test "--dry-run with derived: declared names the owned-set check it did not reach" {
  proj="$(cut_project '  derived:
    - true
  gates:
    - probe')"
  echo more >>"$proj/README.md"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a dry run wrote something"
  assert_output_contains "a dry run does not run derived: commands"
  assert_output_contains "the stamp step checks README.md against what derived: writes"
}

# AT-4.6
@test "--dry-run stops at a refusal it can reach, and writes nothing" {
  proj="$(cut_project)"
  : >"$proj/stray.txt"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ]
}

# AT-4.6
@test "a passing dry run's last line is its verdict: no step failed, and the cut stops to ask at the confirm step (0181)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_output_contains "NOT REACHED by this dry run"
  [ "$(last_line)" = "release: dry run of v1.0.1 -- no step failed; the cut stops to ask at the confirm step" ] ||
    fail "the last line is not the verdict:
$output"
}

# AT-4.6, AT-2.1
@test "a dry run's verdict says when the cut would not stop to ask: given --yes, or with nothing left, and the cut's own confirm row names the commit its commit step makes (0181, ST0011 WP02)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --dry-run --yes
  assert_success
  assert_state confirm would
  # --yes answers the question, so the row says so, as the cut's does, and the
  # confirmation is not among what the dry run could not predict: with no
  # derived: declared, nothing is.
  [[ "$(row_of confirm)" == *" --yes given: tag v1.0.1 at the release commit the commit step makes;"* ]] ||
    fail "the confirm row does not say --yes answers it:
$output"
  refute_output_contains "NOT REACHED"
  [ "$(last_line)" = "release: dry run of v1.0.1 -- no step failed; given --yes, the cut does not stop to ask" ] ||
    fail "the last line is not the verdict for --yes:
$output"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  # The cut's own confirm row says what the dry run's said: it asks before its commit
  # step runs (ST0011), so it names the commit that step makes.
  [[ "$(row_of confirm)" == *" --yes given: tag v1.0.1 at the release commit the commit step makes;"* ]] ||
    fail "the cut's confirm row does not say --yes answers it, of the commit its commit step makes:
$output"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state confirm "not re-run"
  [ "$(last_line)" = "release: dry run of v1.0.1 -- no step failed; the cut has nothing left to ask about" ] ||
    fail "the last line is not the verdict for a finished release:
$output"
}

# AT-4.6
@test "a failing dry run still ends at its stop, exit 1, with no verdict, and its header names the cut (0181)" {
  proj="$(cut_project)"
  : >"$proj/stray.txt"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  refute_output_contains "no step failed"
  [[ "$(last_line)" == "release: stopped at the pre-flight step. "* ]] || fail "the last line is not the stop:
$output"
  assert_output_contains " -- cut with: bin/devbin release v1.0.1"
}

@test "a command that fails at the resolve step stops a dry run and the cut alike: FAILED at resolve, naming it, exit 1 (issue 0304, ST0011 WP02b-2)" {
  proj="$(cut_project)"
  PATH="$(date_refused_path)" run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at resolve
  [[ "$(row_of resolve)" == *"the date cannot be read: date +%F exited"* ]] ||
    fail "the dry run's resolve row does not name the clock's read: $(row_of resolve)"
  PATH="$(date_refused_path)" run release_in "$proj" v1.0.1 --yes
  assert_stopped_at resolve
  [[ "$(row_of resolve)" == *"the date cannot be read: date +%F exited"* ]] ||
    fail "the cut's resolve row does not name the clock's read: $(row_of resolve)"
}

# AT-4.6, AT-2.3
@test "a dry run's header names the cut as the next command, says no gate runs, and a stopped cut's still names the resume (0181, ST0011 WP02)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_output_line "release: v1.0.1 (DRY RUN: no commit, tag, push or release object, and no gate runs) -- cut with: bin/devbin release v1.0.1"
  refute_output_contains "resume with"
  # THE CONTROL: a cut that stops at the confirm step is resumed, and says so.
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_output_line "release: v1.0.1 -- resume with: bin/devbin release v1.0.1"
  refute_output_contains "cut with"
}

# AT-4.6, AT-2.1
@test "with the commit step at would, a dry run's confirm, gates and tag rows name the commit the commit step makes, never HEAD (0181, ST0011 WP02)" {
  proj="$(cut_project)"
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit would
  [[ "$(row_of legs)" == *"would"*"on the release commit the commit step makes"* ]] || fail "the legs row does not say they would run on the commit the commit step makes:
$output"
  for n in confirm gates tag; do
    [[ "$(row_of "$n")" != *"${head:0:12}"* ]] || fail "row $n names HEAD's sha:
$output"
  done
  [[ "$(row_of confirm)" == *"ask before: tag v1.0.1 at the release commit the commit step makes;"* ]] ||
    fail "the confirm row does not ask about the commit the commit step makes:
$output"
  [[ "$(row_of tag)" == *"annotated tag v1.0.1 at the release commit the commit step makes, its message the notes body" ]] ||
    fail "the tag row does not tag the commit the commit step makes:
$output"
}

# AT-4.6
@test "with the commit step would and origin at HEAD, a dry run plans the commit's push as well as the tag's, in the confirm and push rows (0181)" {
  proj="$(cut_project)"
  head="$(git -C "$proj" rev-parse HEAD)"
  # The fixture pushed main, so origin is at HEAD. Read as holding the release
  # commit, it was planned the tag alone, where the cut sends both.
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" = "$head" ] ||
    fail "the fixture's origin is not at HEAD"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit would
  [[ "$(row_of confirm)" == *"; push commit tag to origin;"* ]] || fail "the confirm row does not plan the commit's push:
$output"
  [[ "$(row_of push)" == *" origin commit tag" ]] || fail "the push row does not plan the commit's push:
$output"
}

# AT-4.6
@test "once HEAD is the release commit, a dry run's confirm and tag rows name its sha, and a remote holding it is planned the tag alone (0181)" {
  proj="$(cut_project)"
  # THE CONTROL FOR THE ARM ABOVE: a cut stopped before its tag has made the
  # release commit, at HEAD, and origin lacks it.
  cut_to_tag_stop "$proj" v1.0.1
  rel="$(git -C "$proj" rev-parse HEAD)"
  # Run again with nobody to ask, the cut's own question names that commit, never
  # the HEAD the first run started on.
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_output_line "- tag v1.0.1 at ${rel:0:12}"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit already
  [[ "$(row_of confirm)" == *"ask before: tag v1.0.1 at ${rel:0:12}; push commit tag to origin;"* ]] ||
    fail "the confirm row does not name the release commit and its push:
$output"
  [[ "$(row_of tag)" == *"annotated tag v1.0.1 at ${rel:0:12}, its message the notes body" ]] ||
    fail "the tag row does not tag the release commit:
$output"
  [[ "$(row_of push)" == *" origin commit tag" ]] || fail "the push row does not plan the commit's push:
$output"
  # With the release commit on origin, the tag alone is left to push.
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [[ "$(row_of confirm)" == *"ask before: tag v1.0.1 at ${rel:0:12}; push tag to origin;"* ]] ||
    fail "the confirm row plans more than the tag:
$output"
  [[ "$(row_of push)" == *" origin tag" ]] || fail "the push row plans more than the tag:
$output"
}

# AT-4.6
@test "with the commit step at would, a dry run's legs row names the commit the commit step makes; once the release commit exists, its sha and each leg's record; once released, not re-run (0181, ST0011 WP02b)" {
  local head rel
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [[ "$(row_of legs)" == *"start candidate local together on the release commit the commit step makes"* ]] ||
    fail "the legs row does not name the commit the commit step makes:
$output"
  [[ "$(row_of legs)" != *"${head:0:12}"* ]] || fail "the legs row names HEAD's sha:
$output"
  # THE CONTROL: a cut stopped at its tag, after its legs, has made the release
  # commit at HEAD, and its stop deleted the candidate.
  cut_to_tag_stop --candidate "$proj" v1.0.1
  rel="$(git -C "$proj" rev-parse HEAD)"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the stop at the tag step left the candidate on the remote"; fi
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit already
  assert_state legs already
  [[ "$(row_of legs)" == *"every leg green at ${rel:0:12} already"*"candidate: run 7"* ]] ||
    fail "the legs row does not name the release commit and the candidate's record:
$output"
  # Released, and HEAD moved on: the tag exists, so a dry run's legs are not
  # re-run, whatever HEAD is.
  run release_in "$proj" v1.0.1 --yes
  assert_success
  [ "$(release_sha "$proj")" = "$rel" ] || fail "v1.0.1 does not tag the release commit $rel"
  printf 'later\n' >"$proj/later.txt"
  git -C "$proj" add later.txt
  git -C "$proj" commit -qm "later work"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state legs "not re-run"
}

# AT-4.6
@test "a dry run's verdict names the tag, where the tag differs from the target and from v<version> (0181)" {
  proj="$(cut_project '  tag: "{version}"
  gates:
    - probe')"
  # As in Utilz's shape (0106): under {version}, --patch bumps 1.0.0, so the
  # target is --patch, the version 1.0.1 and the tag 1.0.1, with no v.
  git -C "$proj" tag -a 1.0.0 -m first HEAD~1
  run release_in "$proj" --patch --dry-run
  assert_success
  assert_output_contains "1.0.1 from --patch, tag 1.0.1, new"
  [ "$(last_line)" = "release: dry run of 1.0.1 -- no step failed; the cut stops to ask at the confirm step" ] ||
    fail "the verdict does not name the tag:
$output"
}

# AT-4.4
@test "a remote that moves while a cut's gates run, after the confirm step read it, stops the cut at the tag step, and nothing is tagged or pushed (ST0011 WP02)" {
  proj="$(cut_project)"
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  later="$(git -C "$other" rev-parse HEAD)"
  # Pre-flight and the confirm step read origin at HEAD. The gate then pushes
  # the later commit and fetches it here, so the tag step reads a remote that
  # has diverged from the release commit made on HEAD.
  gate_does "git -C '$other' push -q origin main && git -C '$proj' fetch -q origin"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at tag
  assert_state legs done
  assert_output_contains "origin's main (${later:0:12}) has diverged from the release commit"
  assert_output_contains "This run tagged nothing and pushed nothing"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
}

# ============================================================================
# ONE SCRATCH ROOT, ONE TRAP (WP-04's lift)
# ============================================================================

@test "while the gates run, everything the cut put in TMPDIR is under one root, and a kill leaves nothing" {
  proj="$(cut_project)"
  local tmp="$DEVBIN_TEST_TMPDIR/scratchtmp"
  mkdir -p "$tmp"
  gate_does "ls -A '$tmp' >'$DEVBIN_TEST_TMPDIR/during'; kill -TERM \$PPID"
  TMPDIR="$tmp" run release_in "$proj" v1.0.1 --yes
  assert_failure
  run cat "$DEVBIN_TEST_TMPDIR/during"
  [ "${#lines[@]}" -eq 1 ] || fail "want one scratch root in TMPDIR during the gates, got: $output"
  assert_output_contains "devbin-release."
  [ -z "$(ls -A "$tmp")" ] || fail "the kill left: $(ls -A "$tmp")"
}

# ============================================================================
# PRE-FLIGHT'S gh HALF, AND THE GATE LOOP'S STDIN
# ============================================================================

@test "pre-flight refuses, naming the host, when gh is not signed in and object: local needs it" {
  proj="$(cut_project)"
  perl -0pi -e 's{\A(#!/bin/sh\n)}{$1if [ "\$1 \$2" = "auth status" ]; then echo "You are not logged into any GitHub hosts" >&2; exit 1; fi\n}' \
    "$DEVBIN_TEST_TMPDIR/stubs/gh"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "gh is not signed in to github.com"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

@test "pre-flight's refusal of a url that is not HOST/OWNER/NAME keeps its userinfo off the terminal and out of the cut's sealed log (0188)" {
  proj="$(cut_project)"
  # origin's configured url carries a fake token; origin_at keeps git's reads
  # of it off the network.
  origin_at "$proj" "https://fakeuser0188:FAKE-TOKEN-0188@gitlab.example/group/sub/repo.git"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "remote origin's url (https://gitlab.example/group/sub/repo.git) is not HOST/OWNER/NAME"
  refute_output_contains "TOKEN-0188"
  refute_output_contains "fakeuser0188"
  # The sealed log carries the refusal, so a scan of it that finds no userinfo
  # has read the line the userinfo would be on. The log is the terminal stream
  # itself, teed, so the refutes above fail first for any change to what
  # release_repo prints, and this scan guards the two ever diverging: with those
  # three assertions removed, it goes red on main's code.
  grep -rq "is not HOST/OWNER/NAME" "$proj/tmp/release" ||
    fail "the cut's sealed log does not carry the refusal: $(ls -R "$proj/tmp/release" 2>&1)"
  ! grep -rq -e "TOKEN-0188" -e "fakeuser0188" "$proj/tmp/release" ||
    fail "the cut's sealed log carries the url's userinfo: $(grep -r -e "TOKEN-0188" -e "fakeuser0188" "$proj/tmp/release")"
}

@test "pre-flight refuses a url holding more than one @ ahead of its host, so gh is never asked about a host carrying the password (0188)" {
  proj="$(cut_project)"
  # Read at its first @, this url's host was the rest of the password, and its
  # path OWNER/NAME, so pre-flight asked gh whether it was signed in there and
  # printed the host it asked about.
  origin_at "$proj" "https://fakeuser0188:FAKE@TOKEN-0188@gitlab.example/group/repo.git"
  run release_in "$proj" v1.0.1
  ! grep -q -e "TOKEN-0188" -e "fakeuser0188" "$DEVBIN_TEST_TMPDIR/gh.calls" 2>/dev/null ||
    fail "gh was asked about the password: $(grep -e "TOKEN-0188" -e "fakeuser0188" "$DEVBIN_TEST_TMPDIR/gh.calls")"
  refute_output_contains "TOKEN-0188"
  refute_output_contains "fakeuser0188"
  assert_stopped_at pre-flight
  assert_output_contains "remote origin's url (https://gitlab.example/group/repo.git) holds more than one @ ahead of its host"
  ! grep -rq -e "TOKEN-0188" -e "fakeuser0188" "$proj/tmp/release" ||
    fail "the cut's sealed log carries the url's userinfo: $(grep -r -e "TOKEN-0188" -e "fakeuser0188" "$proj/tmp/release")"
}

# ============================================================================
# 0189: GIT'S OWN WORDS ABOUT A REMOTE CARRY NO PART OF A PASSWORD
# ============================================================================
#
# git leaves a well-formed userinfo out of what it prints, but not a malformed
# one: read at its first @, the rest of a password holding a raw @ is printed
# as the host, and a url with a raw / in its password does not parse and is
# printed whole. Each url below is .invalid, and git rejects the malformed ones
# before it tries the network, so every arm here stays on the machine.

# remote_said <dir> <git-args>... -- what git itself says on stderr for one
# call to a remote, run as release_git_remote runs it, with no terminal to ask
# on: the words a control holds the release core to repeating as they came.
remote_said() {
  local dir="$1"
  shift
  GIT_TERMINAL_PROMPT=0 git -C "$dir" "$@" </dev/null 2>&1 >/dev/null || true
}

# read_remote <repo> -- release_read_remote origin, as pre-flight reads it, in
# <repo>, for a tag no remote holds.
read_remote() {
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; release_read_remote origin main v9.9.9 "$(git rev-parse HEAD)" preflight' _ "$DEVBIN_LIB_DIR" "$1"
}

@test "release_read_remote's UNREADABLE answer names the remote and git's reason and no part of a password, one holding a raw @ or / included (0189)" {
  local url repo="$BATS_TEST_TMPDIR/r189"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m r
  git -C "$repo" remote add origin https://host.invalid/o/r.git
  while IFS= read -r url; do
    git -C "$repo" remote set-url origin "$url"
    read_remote "$repo"
    assert_success
    assert_output_contains "UNREADABLE	origin did not answer ls-remote: fatal: unable to access 'https://host.invalid/o/r.git/'"
    refute_output_contains "TOKEN0189"
    refute_output_contains "FAKE"
    refute_output_contains "fakeuser0189"
  done <<'URLS'
https://fakeuser0189:FAKE@TOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE/TOKEN0189@host.invalid/o/r.git
URLS
}

@test "release_read_remote's UNREADABLE answer reads as git said it for a url with no password, a well-formed one, or an @ in its path (0189)" {
  local url said repo="$BATS_TEST_TMPDIR/r189"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m r
  git -C "$repo" remote add origin https://host.invalid/o/r.git
  # THE CONTROLS: git's own words, taken from git beside each answer, so a
  # change to what git says moves both halves together.
  while IFS= read -r url; do
    git -C "$repo" remote set-url origin "$url"
    said="$(remote_said "$repo" ls-remote origin refs/heads/main refs/tags/v9.9.9)"
    [ -n "$said" ] || fail "git said nothing for $url"
    read_remote "$repo"
    assert_success
    assert_output "$(printf 'UNREADABLE\torigin did not answer ls-remote: %s' "${said//$'\n'/ }")"
  done <<'URLS'
https://host.invalid/o/r.git
https://fakeuser0189:FAKETOKEN0189@host.invalid/o/r.git
https://host.invalid/group/sub@x/repo.git
https://host.invalid:8443/group/sub@x/repo.git
URLS
}

@test "a push that fails at the push step prints git's reason and no part of a password, one holding a raw @ or / included, on the terminal and in the sealed log (0189)" {
  local url
  # origin's pushurl is each url below, and only the push step's pushes read it:
  # pre-flight's reads, and the push step's read after its pushes, go through origin's
  # url to the bare remote.
  while IFS= read -r url; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(cut_project)"
    git -C "$proj" remote set-url --push origin "$url"
    run release_in "$proj" v1.0.1 --yes
    assert_stopped_at push
    assert_output_contains "pushing the release commit to origin's main failed"
    assert_output_contains "fatal: unable to access 'https://host.invalid/o/r.git/'"
    refute_output_contains "TOKEN0189"
    refute_output_contains "FAKE"
    refute_output_contains "fakeuser0189"
    # The sealed log is the terminal stream, teed: it carries git's line, so a
    # scan of it that finds no part of the password has read where it would be.
    grep -rq "fatal: unable to access" "$proj/tmp/release" ||
      fail "the cut's sealed log does not carry git's words: $(ls -R "$proj/tmp/release" 2>&1)"
    ! grep -rq -e "TOKEN0189" -e "FAKE" -e "fakeuser0189" "$proj/tmp/release" ||
      fail "the cut's sealed log carries part of the password: $(grep -r -e "TOKEN0189" -e "FAKE" -e "fakeuser0189" "$proj/tmp/release")"
  done <<'URLS'
https://fakeuser0189:FAKE@TOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE/TOKEN0189@host.invalid/o/r.git
URLS
}

@test "a push that fails at the push step prints git's words as git said them for a url with no password, a well-formed one, or an @ in its path (0189)" {
  local url said
  while IFS= read -r url; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(cut_project)"
    git -C "$proj" remote set-url --push origin "$url"
    said="$(remote_said "$proj" push -q origin HEAD:refs/heads/main)"
    [ -n "$said" ] || fail "git said nothing for $url"
    run release_in "$proj" v1.0.1 --yes
    assert_stopped_at push
    assert_output_contains "$said"
  done <<'URLS'
https://host.invalid/o/r.git
https://fakeuser0189:FAKETOKEN0189@host.invalid/o/r.git
https://host.invalid/group/sub@x/repo.git
https://host.invalid:8443/group/sub@x/repo.git
URLS
}

@test "release_text_shown leaves out every part of a url's userinfo the text carries, keeps an ssh user, and reads a token as text, never as a pattern (0189)" {
  shown() {
    run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; t="$2"; shift 2; release_text_shown "$t" "$@"' _ "$DEVBIN_LIB_DIR" "$@"
    assert_success
  }
  # The url printed whole, its password holding a raw / and pattern characters.
  shown "fatal: unable to access 'https://fakeuser0189:FA*K[E]/TOKEN0189@host.invalid/o/r.git/': URL rejected" \
    "https://fakeuser0189:FA*K[E]/TOKEN0189@host.invalid/o/r.git"
  assert_output "fatal: unable to access 'https://host.invalid/o/r.git/': URL rejected"
  # git read the userinfo to the first @ and kept the rest of a token as the host.
  shown "fatal: unable to access 'https://KEN0189@host.invalid/o/r.git/': URL rejected: Bad hostname" \
    "https://TO@KEN0189@host.invalid/o/r.git"
  assert_output "fatal: unable to access 'https://host.invalid/o/r.git/': URL rejected: Bad hostname"
  # Every url given is read: a pushurl beside the url, both in one text.
  shown $'x https://u:FAKE1@TOKEN0189@host.invalid/a.git\ny https://v:FAKE2/TOKEN0189@host.invalid/b.git' \
    "https://u:FAKE1@TOKEN0189@host.invalid/a.git" "https://v:FAKE2/TOKEN0189@host.invalid/b.git"
  assert_output $'x https://host.invalid/a.git\ny https://host.invalid/b.git'
  # A token with no `:`, printed whole after its scheme, and the user git names
  # when it asks for a password.
  shown "x https://TO@KEN0189@host.invalid/o/r.git" "https://TO@KEN0189@host.invalid/o/r.git"
  assert_output "x https://host.invalid/o/r.git"
  shown "fatal: could not read Password for 'https://fakeuser0189@host.invalid': terminal prompts disabled" \
    "https://fakeuser0189:FAKE0189@host.invalid/o/r.git"
  assert_output "fatal: could not read Password for 'https://host.invalid': terminal prompts disabled"
  # A password in an ssh url is one. Here it stands with no scheme ahead of it,
  # where only the removal that reads a password anywhere reaches it, and that
  # removal reads its pattern characters as text.
  shown "ssh: Could not resolve hostname fakeuser0189:FA*K[E]0189@host.invalid" "ssh://fakeuser0189:FA*K[E]0189@host.invalid/o/r.git"
  assert_output "ssh: Could not resolve hostname host.invalid"
  # An ssh url whose password holds a raw `/`: git hands ssh the userinfo up to
  # that `/` as the host, and ssh names it when it cannot resolve it.
  shown "ssh: Could not resolve hostname fakeuser0189:FAKE: nodename nor servname provided, or not known" \
    "ssh://fakeuser0189:FAKE/TOKEN0189@host.invalid/o/r.git"
  assert_output "ssh: Could not resolve hostname : nodename nor servname provided, or not known"
  # THE CONTROLS. An ssh user is no credential, and ssh's refusal names it.
  shown "git@github.com: Permission denied (publickey)." "git@github.com:t/demo.git"
  assert_output "git@github.com: Permission denied (publickey)."
  shown "git@github.com: Permission denied (publickey)." "ssh://git@github.com:22/t/demo.git"
  assert_output "git@github.com: Permission denied (publickey)."
  # No userinfo, an @ in the path with a host:port ahead of it, and an IPv6
  # host: nothing is read as a userinfo, so the text stands.
  local said
  for u in "https://host.invalid/group/sub@x/repo.git" "https://host.invalid:8443/group/sub@x/repo.git" "https://[::1]:8443/group/sub@x/repo.git" "host.invalid:group/sub@x/repo.git"; do
    said="fatal: unable to access '$u/': Could not resolve host"
    shown "$said" "$u"
    assert_output "$said"
  done
}

@test "a push whose pre-push hook leaves a job holding git's stderr returns when git does, within its bound and with the hook's words (0189)" {
  local repo="$BATS_TEST_TMPDIR/h189"
  git init -q --bare -b main "$repo.git"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m r
  git -C "$repo" remote add origin "$repo.git"
  # The hook says one line and leaves a job holding git's stderr for longer
  # than the bound, so git's words read through a pipe would wait for the job.
  printf '#!/bin/sh\necho "hook: notifying" >&2\nsleep 20 &\nexit 0\n' >"$repo/.git/hooks/pre-push"
  chmod +x "$repo/.git/hooks/pre-push"
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; rc=0; release_run_bounded 8 "$3/out" "$3/err" release_git_remote push -q origin HEAD:refs/heads/main || rc=$?; printf "rc %s\n" "$rc"; cat "$3/err"' _ "$DEVBIN_LIB_DIR" "$repo" "$BATS_TEST_TMPDIR" 3>&-
  assert_success
  assert_output_contains "rc 0"
  assert_output_contains "hook: notifying"
  [ "$(git -C "$repo.git" rev-parse refs/heads/main)" = "$(git -C "$repo" rev-parse HEAD)" ] || fail "the push did not land"
}

@test "a remotes entry that is a url is refused by pre-flight, which names it with no part of its userinfo (0189)" {
  local url
  while IFS= read -r url; do
    rm -rf "$DEVBIN_TEST_TMPDIR/demo" "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR/gh.calls"
    proj="$(cut_project "  remotes:
    - $url
  gates:
    - probe")"
    run release_in "$proj" v1.0.1 --yes
    assert_failure
    assert_output_contains "remote https://host.invalid/o/r.git is declared and does not exist"
    refute_output_contains "TOKEN0189"
    refute_output_contains "FAKE"
    refute_output_contains "fakeuser0189"
  done <<'URLS'
https://fakeuser0189:FAKETOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE@TOKEN0189@host.invalid/o/r.git
https://fakeuser0189:FAKE/TOKEN0189@host.invalid/o/r.git
URLS
}

@test "a gate that reads its stdin does not eat the gates after it" {
  proj="$(cut_project '  gates:
    - probe first
    - probe second')"
  gate_does 'cat >/dev/null'
  cut_to_tag_stop "$proj" v1.0.1
  run cat "$DEVBIN_TEST_TMPDIR/gate.calls"
  assert_output_contains "probe first"
  assert_output_contains "probe second"
}

# ============================================================================
# THE NOTE, AND WHAT derived: WRITES
# ============================================================================

@test "pre-flight refuses a target with no note, naming where it was looked for" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.2
  assert_stopped_at pre-flight
  assert_output_contains "there is no"
  assert_output_contains "write the note before the release"
  [ "$(cat "$proj/VERSION")" = 1.0.0 ]
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

@test "pre-flight refuses a note dated another day: a released note is never re-dated" {
  proj="$(cut_project)"
  sed 's/## \[1.0.1\] - Unreleased/## [1.0.1] - 2020-01-01/' "$proj/CHANGELOG.md" >"$proj/CHANGELOG.new"
  mv "$proj/CHANGELOG.new" "$proj/CHANGELOG.md"
  git -C "$proj" commit -qam "dated long ago"
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "released on 2020-01-01, not today"
}

# derived_project <body> -- cut_project with a committed ./gen.sh as its one
# derived: command; <body> is the script's body.
derived_project() {
  local proj
  proj="$(cut_project '  derived:
    - ./gen.sh
  gates:
    - probe')"
  printf '#!/bin/sh\n%s\n' "$1" >"$proj/gen.sh"
  chmod +x "$proj/gen.sh"
  git -C "$proj" add gen.sh
  git -C "$proj" commit -qm "the derived command"
  git -C "$proj" push -q origin main
  printf '%s\n' "$proj"
}

@test "a path a derived: command reports is owned, and goes into the release commit" {
  proj="$(derived_project 'echo generated >gen.txt; echo gen.txt')"
  cut_to_tag_stop "$proj" v1.0.1
  assert_state stamp done
  [ "$(git -C "$proj" show HEAD:gen.txt)" = generated ] || fail "gen.txt is not in the release commit"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree is not clean"
}

@test "a path a derived: command writes and does not report is refused at the stamp step, naming it" {
  proj="$(derived_project 'echo generated >gen.txt')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at stamp
  assert_output_contains "dirty outside what this release owns: gen.txt"
}

@test "with derived: declared, dirt outside the known owned set is checked at the stamp step and refused there" {
  proj="$(derived_project 'true')"
  echo more >>"$proj/README.md"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at stamp
  assert_output_contains "dirty outside what this release owns: README.md"
  [ "$(release_commits "$proj")" -eq 0 ]
  if gate_ran; then fail "a gate ran after the stamp step refused"; fi
}

# ============================================================================
# THE POST-GATE RE-READ SEES A REWRITE OF A FILE THAT WAS ALREADY DIRTY
# ============================================================================

# AT-4.2
@test "release_gates_run fails a gate that rewrites a file already dirty before the gates, naming it: the re-read compares bytes, not git status (ST0011 WP02)" {
  # A cut's gates and release gates each run on a clean tree, and a dry run runs
  # none, so only a call of the function reaches the case it still guards.
  proj="$(cut_project)"
  printf '1.0.1\n' >"$proj/VERSION"
  gate_does 'echo 9.9.9 >VERSION'
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; PROJECT_ROOT="$2"; release_gates_run probe' _ "$DEVBIN_LIB_DIR" "$proj"
  assert_failure
  assert_output_contains "a gate changed the tree: VERSION"
}

@test "--patch bumps the NEWEST matching tag, not the first one listed" {
  proj="$(cut_project)"
  # 1.9.0 is listed before 1.10.0 and 1.10.0 is the newer, so a text sort
  # picks the wrong one; both are above the fixture's v1.0.0.
  git -C "$proj" tag -a v1.9.0 -m older HEAD~1
  git -C "$proj" tag -a v1.10.0 -m older HEAD~1
  run release_in "$proj" --patch --dry-run
  assert_output_contains "1.10.1 from --patch, tag v1.10.1, new"
}

# AT-4.1
@test "a tag listed last that matches the template and names no version does not stop the resolve step (issue 0106)" {
  proj="$(cut_project)"
  # git lists tags in byte order, so v1.0.0-rc1 comes after v1.0.0: it matches
  # v{version} and names no X.Y.Z. release_versions took its loop's status from
  # the LAST tag's test, pipefail made that the pipeline's, and the resolve step failed
  # with an empty detail, for a relative target and an explicit one alike.
  git -C "$proj" tag -a v1.0.0-rc1 -m rc HEAD~1
  run release_in "$proj" --patch --dry-run
  assert_output_contains "1.0.1 from --patch, tag v1.0.1, new"
  run release_in "$proj" v1.0.1 --dry-run
  assert_output_contains "1.0.1 from v1.0.1, tag v1.0.1, new"
}

# AT-4.1
@test "Utilz's shape: tag {version}, with an older v-tag listed last, resolves both targets (issue 0106)" {
  proj="$(cut_project '  tag: "{version}"
  gates:
    - probe')"
  # The fixture's v1.0.0 matches {version} and names no version, and it is
  # listed after 1.0.0.
  git -C "$proj" tag -a 1.0.0 -m first HEAD~1
  run release_in "$proj" --patch --dry-run
  assert_output_contains "1.0.1 from --patch, tag 1.0.1, new"
  run release_in "$proj" 1.0.1 --dry-run
  assert_output_contains "1.0.1 from v1.0.1, tag 1.0.1, new"
}

# AT-4.1
@test "every way release_versions fails, it says why, so the resolve step never fails with an empty detail (issue 0106)" {
  proj="$(cut_project)"
  norepo="$BATS_TEST_TMPDIR/norepo"
  mkdir -p "$norepo"
  run env GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; release_versions "v{version}"' _ "$DEVBIN_LIB_DIR" "$norepo"
  assert_failure
  assert_output_contains "release: cannot list this repository's tags"
  # The ordering can fail too; a sort that refuses stands in for it.
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; sort() { return 3; }; release_resolve "v{version}" --patch' _ "$DEVBIN_LIB_DIR" "$proj"
  assert_failure
  assert_output_contains "release: cannot sort the versions named by the tags matching v{version}"
}

# ============================================================================
# A RE-RUN ON AN EXISTING RELEASE COMMIT RUNS NO derived:
# ============================================================================
#
# A run with no terminal and no --yes makes the release commit and stops at
# the confirm step (exit 1, nobody to ask), before anything outward: the state these
# arms are about.

@test "a re-run with a derived: command that is not byte-stable makes no second release commit" {
  proj="$(derived_project 'date +%s%N >gen.txt; echo gen.txt')"
  cut_to_tag_stop "$proj" v1.0.1
  head="$(git -C "$proj" rev-parse HEAD)"
  gen="$(cat "$proj/gen.txt")"
  sleep 1
  cut_to_tag_stop "$proj" v1.0.1
  assert_state stamp already
  assert_state commit already
  [ "$(release_commits "$proj")" -eq 1 ] || fail "a second release commit: $(git -C "$proj" log --format=%s)"
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "HEAD moved"
  [ "$(cat "$proj/gen.txt")" = "$gen" ] || fail "derived: ran again on the release commit"
}

@test "a remote moved past the release commit, then a re-run whose derived: rewrites, is not left diverged" {
  proj="$(derived_project 'date +%s%N >gen.txt; echo gen.txt')"
  cut_to_tag_stop "$proj" v1.0.1
  git -C "$proj" push -q origin main
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  git -C "$proj" fetch -q origin
  sleep 1
  cut_to_tag_stop "$proj" v1.0.1
  assert_state commit already
  git -C "$proj" merge-base --is-ancestor HEAD origin/main ||
    fail "a release commit was made that origin/main does not carry"
}

# ============================================================================
# WP-04: THE LIVE MUTANTS' ARMS
# ============================================================================

# AT-4.3
@test "a renamed path outside the owned set is refused naming both of its paths" {
  proj="$(cut_project)"
  git -C "$proj" mv README.md MOVED.md
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "dirty outside what this release owns: MOVED.md, README.md --"
}

@test "pre-flight asks gh about the host release.repo names, when it names one" {
  proj="$(cut_project '  repo: ghe.example.com/acme/demo
  gates:
    - probe')"
  run release_in "$proj" v1.0.1 --dry-run
  grep -qx -- 'gh auth status --hostname ghe.example.com' "$DEVBIN_TEST_TMPDIR/gh.calls" ||
    fail "gh was not asked about ghe.example.com: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls" 2>/dev/null)"
}

@test "a derived: command that reports an absolute path under the root is owned too" {
  proj="$(derived_project 'echo generated >gen.txt; echo "$PWD/gen.txt"')"
  cut_to_tag_stop "$proj" v1.0.1
  [ "$(git -C "$proj" show HEAD:gen.txt)" = generated ] || fail "gen.txt is not in the release commit"
}

# ============================================================================
# THE STEPS FROM CONFIRM TO OBJECT: CONFIRM, TAG, PUSH, THE RELEASE OBJECT (WP-05)
# ============================================================================

# remote_refs -- every ref the fixture's remote holds.
remote_refs() { git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref; }

# gh_calls is in tests/lib/release_fixtures.bash, as releaseattach.bats reads
# the calls too.

# gh_fails <verb> -- the gh stub fails `release <verb>` from now on.
gh_fails() {
  perl -0pi -e 's{\A(#!/bin/sh\n)}{$1if [ "\$1 \$2" = "release '"$1"'" ]; then echo "HTTP 502" >&2; exit 1; fi\n}' \
    "$DEVBIN_TEST_TMPDIR/stubs/gh"
}

# refuse_pushes <proj> / allow_pushes <proj> -- a pre-push hook that refuses.
refuse_pushes() {
  printf '#!/bin/sh\necho "push refused by hook" >&2\nexit 1\n' >"$1/.git/hooks/pre-push"
  chmod +x "$1/.git/hooks/pre-push"
}
allow_pushes() { rm -f "$1/.git/hooks/pre-push"; }

# assert_released <proj> -- the tag is annotated at the release commit, and
# the remote holds both.
assert_released() {
  local commit
  commit="$(git -C "$1" rev-parse 'refs/tags/v1.0.1^{commit}')"
  [ "$(git -C "$1" cat-file -t refs/tags/v1.0.1)" = tag ] || fail "v1.0.1 is not annotated"
  [ "$(git -C "$1" log -1 --format=%s "$commit")" = "release: v1.0.1" ] || fail "v1.0.1 is not at the release commit"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" = "$commit" ] ||
    fail "the remote's main is not the release commit"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/tags/v1.0.1)" = "$(git -C "$1" rev-parse refs/tags/v1.0.1)" ] ||
    fail "the remote does not carry the same v1.0.1"
}

# AT-5.5
@test "with --yes a cut runs to the end: tagged, pushed, one release object, exit 0" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state confirm done
  assert_state tag done
  assert_state push done
  assert_state object done
  assert_state after skipped
  assert_state legs done
  assert_output_contains "v1.0.1 is released"
  assert_released "$proj"
  [ "$(gh_calls 'release create')" -eq 1 ] || fail "want one release create: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  grep -q -- '--title v1.0.1' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "the object is not titled {tag}"
  # Without --verify-tag GitHub makes a missing tag from the default branch, and
  # without --repo gh picks the repository itself.
  create="$(grep '^gh release create' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [[ " $create " == *" --verify-tag "* ]] || fail "the create has no --verify-tag: $create"
  [[ " $create " == *" --repo t/demo "* ]] || fail "the create does not name the repository: $create"
}

# AT-5.3
@test "at a terminal, the cut asks once, naming what is left, and a y releases (AC-5.3)" {
  require_pty
  require_expect
  proj="$(cut_project)"
  run run_tty_answer y env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" sh -c "cd '$proj' && ./bin/devbin release v1.0.1"
  assert_success
  assert_output_contains "[y/N]"
  assert_output_contains "tag v1.0.1 at"
  assert_output_contains "push commit tag to origin"
  assert_output_contains "make the release object"
  assert_released "$proj"
}

# AT-5.3
@test "at a terminal, an n tags nothing and pushes nothing" {
  require_pty
  require_expect
  proj="$(cut_project)"
  before="$(remote_refs)"
  run run_tty_answer n env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" sh -c "cd '$proj' && ./bin/devbin release v1.0.1"
  # 1, declined. Nobody to ask exits 1 too since issue 0130, so the difference
  # between the two answers lives in the row: this pins declined, and
  # assert_stopped_at_confirm pins nobody to ask.
  [ "$status" -eq 1 ] || fail "want 1 (declined), got $status: $output"
  assert_output_contains "declined at the prompt"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "an n made the tag"; fi
  [ "$(remote_refs)" = "$before" ] || fail "an n pushed something"
  [ "$(gh_calls 'release create')" -eq 0 ]
}

# AT-5.1, AT-5.3
@test "resumed after the tag step, the cut asks before the first push, naming only the pushes and the object (AC-5.1, AC-5.3)" {
  proj="$(cut_project)"
  refuse_pushes "$proj"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at push
  assert_output_contains "This run tagged v1.0.1 locally"
  allow_pushes "$proj"
  before="$(remote_refs)"
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_state confirm FAILED
  assert_output_contains "push commit tag to origin"
  assert_output_contains "make the release object"
  refute_output_contains "tag v1.0.1 at"
  [ "$(remote_refs)" = "$before" ] || fail "a run with nobody to ask pushed something"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state stamp already
  assert_state commit already
  assert_state legs "not re-run"
  assert_state tag already
  assert_state push done
  assert_released "$proj"
}

# AT-5.1
@test "resumed after the push step, the cut makes the object and pushes nothing twice (AC-5.1)" {
  proj="$(cut_project)"
  gh_fails create
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at object
  assert_output_contains "This run tagged v1.0.1 locally, pushed main to origin, pushed v1.0.1 to origin."
  perl -0pi -e 's{if \[ "\$1 \$2" = "release create" \]; then echo "HTTP 502" >&2; exit 1; fi\n}{}' "$DEVBIN_TEST_TMPDIR/stubs/gh"
  before="$(remote_refs)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state push already
  assert_state object done
  [ "$(remote_refs)" = "$before" ] || fail "the resume pushed again"
}

# AT-5.2
@test "a finished release re-run after HEAD and the remote moved on, with work in progress, does nothing and asks nothing (AC-5.2)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  echo later >"$proj/later.txt"
  git -C "$proj" add later.txt
  git -C "$proj" commit -qm later
  git -C "$proj" push -q origin main
  echo wip >>"$proj/README.md"
  : >"$proj/untracked.txt"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  before="$(remote_refs)"
  calls="$(gh_calls 'release \(create\|edit\)')"
  run release_in "$proj" v1.0.1
  assert_success
  assert_state pre-flight done
  assert_state stamp already
  assert_state commit already
  assert_state legs "not re-run"
  assert_state confirm "not re-run"
  assert_state tag already
  assert_state push already
  assert_state object already
  refute_output_contains "[y/N]"
  if gate_ran; then fail "a gate ran on a finished release"; fi
  [ "$(remote_refs)" = "$before" ] || fail "a finished release pushed"
  [ "$(gh_calls 'release \(create\|edit\)')" = "$calls" ] || fail "a finished release wrote the object"
}

# AT-5.4
@test "the tag the core makes is annotated at the release commit, its message the notes body byte for byte, ### lines included (AC-5.4)" {
  proj="$(cut_project)"
  printf '# Changelog\n\n## [1.0.1] - Unreleased\n\n### Added\n\n- second\n\n### Fixed\n\n- third\n\n## [1.0.0] - 2026-01-01\n\n- first\n' >"$proj/CHANGELOG.md"
  git -C "$proj" commit -qam "sections"
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_released "$proj"
  want="$(printf '### Added\n\n- second\n\n### Fixed\n\n- third')"
  got="$(git -C "$proj" for-each-ref --format='%(contents)' refs/tags/v1.0.1)"
  [ "$got" = "$want" ] || fail "the tag message is not the notes body:
--- got
$got
--- want
$want"
}

# AT-5.4
@test "a lightweight tag the core finds is reused, reported on the tag step's line, and left as it is (AC-5.4)" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  git -C "$proj" tag v1.0.1
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state tag already
  assert_output_contains "it is lightweight"
  [ "$(git -C "$proj" cat-file -t refs/tags/v1.0.1)" = commit ] || fail "the lightweight tag was rewritten"
}

# AT-5.5
@test "the object's title comes from title:, and a confirmed resume edits the object rather than making a second (AC-5.5)" {
  proj="$(cut_project '  title: "demo {version}"
  gates:
    - probe')"
  refuse_pushes "$proj"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at push
  allow_pushes "$proj"
  # The object exists before the pushes did: made by a person, or by a run
  # whose gh call succeeded and then reported a failure.
  printf 'v1.0.1\n' >>"$DEVBIN_TEST_TMPDIR/gh.releases"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state object done
  assert_output_contains "its title and notes were set"
  [ "$(gh_calls 'release create')" -eq 0 ] || fail "a second object was made"
  [ "$(gh_calls 'release edit')" -eq 1 ]
  grep -q -- '--title demo 1.0.1' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "the title is not from title:"
}

# AT-5.5
@test "under object: none the cut makes no release object and needs no gh (AC-5.5)" {
  proj="$(cut_project '  object: none
  gates:
    - probe')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state object skipped
  assert_released "$proj"
  [ "$(gh_calls 'release')" -eq 0 ] || fail "gh was called: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(gh_calls 'auth status')" -eq 0 ] || fail "pre-flight asked gh under object: none"
}

@test "a pre-flight refuses a project whose run logs will not be ignored, naming the remedy" {
  # A log directory ignores itself (issue 0157), unless the project put its own
  # .gitignore there: then that file decides, and here it ignores nothing.
  proj="$(cut_project)"
  git -C "$proj" rm -q --cached .gitignore
  rm "$proj/.gitignore"
  mkdir -p "$proj/tmp/release"
  printf '!kept\n' >"$proj/tmp/release/.gitignore"
  git -C "$proj" add -f tmp/release/.gitignore
  git -C "$proj" commit -qm "no ignore, and the project's own file in the log directory"
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "add tmp/ to .gitignore"
}

@test "in a repository git refuses to read, the cut stops at resolve in git's own words, so the pre-flight's ignore-file remedy is never reached (0185)" {
  # Measured: listing the tags fails first, naming the ownership, so the
  # pre-flight's "add tmp/ to .gitignore" cannot be offered there, in a cut or a
  # dry run. A reorder that let the cut past resolve would offer it. LC_ALL=C:
  # the stop prints git's words, and git translates them.
  proj="$(cut_project)"
  mkdir -p "$proj/tmp/release"
  require_git_refusal "$proj"
  local mode
  for mode in cut --dry-run; do
    if [ "$mode" = cut ]; then
      LC_ALL=C GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run release_in "$proj" v1.0.1
    else
      LC_ALL=C GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run release_in "$proj" v1.0.1 --dry-run
    fi
    assert_failure
    assert_output_contains "stopped at the resolve step"
    assert_output_contains "detected dubious ownership"
    refute_output_contains "add tmp/ to .gitignore"
  done
}

@test "over an index git cannot read, the pre-flight says git could not say whether its log directory is ignored, never 'add tmp/ to .gitignore' (0186)" {
  # tmp/release/ ignores itself, as 0157's writer leaves it, and nothing else
  # ignores tmp/. Over the index, check-ignore failed, and the writer's rule,
  # which writes no file where one is already, read that as not ignored.
  proj="$(cut_project)"
  git -C "$proj" rm -q --cached .gitignore
  rm "$proj/.gitignore"
  git -C "$proj" commit -qm "no ignore"
  git -C "$proj" push -q origin main
  mkdir -p "$proj/tmp/release"
  printf '*\n' >"$proj/tmp/release/.gitignore"
  # THE CONTROL: with the index readable, the directory is ignored and the
  # pre-flight passes it.
  run release_in "$proj" v1.0.1 --dry-run --yes
  assert_success
  refute_output_contains "is not ignored"
  refute_output_contains "could not say whether"
  break_git_index "$proj"
  local mode
  for mode in cut --dry-run; do
    if [ "$mode" = cut ]; then
      run release_in "$proj" v1.0.1
    else
      run release_in "$proj" v1.0.1 --dry-run
    fi
    assert_stopped_at pre-flight
    assert_output_contains "git could not say whether tmp/release/ is ignored -- fatal: .git/index: index file smaller than expected"
    refute_output_contains "add tmp/ to .gitignore"
  done
}

@test "a tmp/ committed as a link out of the tree: the pre-flight says git could not say whether its log directory is ignored, in git's words, never 'add tmp/ to .gitignore' (0186)" {
  # With the index readable, check-ignore refuses a path beyond a symbolic link
  # at 128, and the fall to the writer's rule, which writes nothing outside the
  # tree, read that as not ignored. Its remedy cannot clear the refusal:
  # ignoring tmp/ leaves the path beyond the link. Both versions refuse such a
  # link, whose logs land outside the tree; whether the pre-flight should accept
  # it is not this arm's question.
  proj="$(cut_project)"
  # THE CONTROL: a plain tmp/ in the tree is ignored, and the pre-flight passes.
  mkdir -p "$proj/tmp"
  run release_in "$proj" v1.0.1 --dry-run --yes
  assert_success
  refute_output_contains "is not ignored"
  refute_output_contains "could not say whether"
  local outside="$DEVBIN_TEST_TMPDIR/outside" mode
  mkdir -p "$outside"
  rm -rf "$proj/tmp"
  ln -s "$outside" "$proj/tmp"
  git -C "$proj" add -f tmp
  git -C "$proj" commit -qm "tmp is a link out of the tree"
  git -C "$proj" push -q origin main
  for mode in cut --dry-run; do
    if [ "$mode" = cut ]; then
      run release_in "$proj" v1.0.1
    else
      run release_in "$proj" v1.0.1 --dry-run
    fi
    assert_stopped_at pre-flight
    assert_output_contains "git could not say whether tmp/release/ is ignored -- fatal: pathspec '"
    assert_output_contains "' is beyond a symbolic link"
    refute_output_contains "add tmp/ to .gitignore"
  done
}

@test "a project that ignores nothing reaches the same pre-flight verdict in a dry run and a cut, and the cut finds no dirt at the gates step (0157)" {
  # The pre-flight asked git alone: a cut, whose own log had made tmp/release
  # ignore itself, passed, and a dry run of the same tree refused.
  proj="$(cut_project)"
  git -C "$proj" rm -q --cached .gitignore
  rm "$proj/.gitignore"
  git -C "$proj" commit -qm "no ignore"
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1 --dry-run --yes
  assert_success
  refute_output_contains "is not ignored"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  refute_output_contains "is not ignored"
  refute_output_contains "changed the tree"
  assert_released "$proj"
}

# ============================================================================
# AN OBJECT THAT DIFFERS IS NAMED, AND ONLY A CONFIRMED RUN CHANGES IT
# ============================================================================

# AT-5.5
@test "a finished release whose object's title was changed by hand: a re-run names it at the confirm step and changes nothing unconfirmed" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  printf 'by hand\n' >"$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.name"
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_state confirm FAILED
  assert_output_contains 'its title is "by hand", not "v1.0.1"'
  refute_output_contains "9  object      already"
  [ "$(gh_calls 'release edit')" -eq 0 ] || fail "an unconfirmed run edited the object"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.name")" = "by hand" ]
}

# AT-5.5
@test "an object whose notes differ is named, a dry run says it would edit, and --yes sets them and reads them back" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  printf 'something else\n' >"$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.body"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state object would
  assert_output_contains "its notes are not this release's"
  [ "$(gh_calls 'release edit')" -eq 0 ] || fail "a dry run edited the object"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state confirm done
  assert_state object done
  [ "$(gh_calls 'release edit')" -eq 1 ]
  edit="$(grep '^gh release edit' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [[ " $edit " == *" --repo t/demo "* ]] || fail "the edit does not name the repository: $edit"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.body")" = "- second" ] ||
    fail "the notes were not set to the release's: $(cat "$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.body")"
}

# AT-5.5
@test "a finished release whose object matches reports the object row already, naming that its title and notes match" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  run release_in "$proj" v1.0.1
  assert_success
  assert_state object already
  assert_output_contains "carries this release's title and notes"
}

# AT-4.1
@test "a push the second remote refuses stops the push step, naming everything the first remote received" {
  proj="$(cut_project '  remotes:
    - origin
    - backup
  gates:
    - probe')"
  git init -q --bare -b main "$DEVBIN_TEST_TMPDIR/backup.git"
  git -C "$proj" remote add backup "$DEVBIN_TEST_TMPDIR/backup.git"
  git -C "$proj" push -q backup main
  printf '#!/bin/sh\necho "backup refuses" >&2\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/backup.git/hooks/pre-receive"
  chmod +x "$DEVBIN_TEST_TMPDIR/backup.git/hooks/pre-receive"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at push
  assert_output_contains "This run tagged v1.0.1 locally, pushed main to origin, pushed v1.0.1 to origin."
}

# ============================================================================
# WP-05'S MUTANTS: THE ARMS THEY ASKED FOR
# ============================================================================

# AT-4.2
@test "a gate that commits fails the gates step, naming that it moved HEAD, and nothing is tagged" {
  proj="$(cut_project)"
  gate_does 'git commit -q --allow-empty -m sneaky'
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  assert_output_contains "a gate moved HEAD from"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
}

# AT-4.1
@test "a remote that stops answering after the confirm step read it fails the tag step, naming it, and nothing is tagged or pushed (ST0011 WP02)" {
  # Pre-flight refuses an unreadable remote, and the confirm step reads each one
  # before the gates; the tag step reads them again once the release commit
  # exists, and a remote can stop answering in between. The gate moves the bare
  # remote aside: it is outside the project, so the gates step's checks pass.
  proj="$(cut_project)"
  gate_does "mv '$DEVBIN_TEST_TMPDIR/remote.git' '$DEVBIN_TEST_TMPDIR/remote.gone'"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at tag
  assert_output_contains "origin did not answer ls-remote"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
  [ "$(gh_calls 'release create')" -eq 0 ] || fail "an object was made"
}

# AT-4.1, AT-5.4
@test "a tag that does not read back as the annotated tag the tag step made fails the tag step" {
  # A git whose `tag -a` makes a LIGHTWEIGHT tag: the status still reads
  # `already`, so only the reuse note can tell, and the tag step must read it.
  proj="$(cut_project)"
  local real_git
  real_git="$(command -v git)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/gitshim"
  cat >"$DEVBIN_TEST_TMPDIR/gitshim/git" <<SH
#!/bin/sh
if [ "\$1" = tag ] && [ "\$2" = -a ]; then exec "$real_git" tag "\$3" "\$4"; fi
exec "$real_git" "\$@"
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/gitshim/git"
  PATH="$DEVBIN_TEST_TMPDIR/gitshim:$PATH" run release_in "$proj" v1.0.1 --yes
  assert_stopped_at tag
  assert_output_contains "does not read back as made"
  assert_output_contains "it is lightweight"
  [ "$(remote_refs | grep -c v1.0.1)" -eq 0 ] || fail "the tag was pushed"
}

@test "a remote that holds the release commit and has moved past it is sent only the tag" {
  proj="$(cut_project)"
  cut_to_tag_stop "$proj" v1.0.1
  git -C "$proj" push -q origin main
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  later="$(git -C "$other" rev-parse HEAD)"
  git -C "$proj" fetch -q origin
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "push tag to origin"
  refute_output_contains "push commit tag to origin"
  assert_state push done
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" = "$later" ] || fail "the remote's main was moved"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse 'refs/tags/v1.0.1^{commit}')" = "$(git -C "$proj" rev-parse 'v1.0.1^{commit}')" ] ||
    fail "the remote does not carry the tag at the release commit"
}

# AT-4.1
@test "a remote that accepts the push and does not keep the tag fails the push step on the read-back, at once (0194)" {
  proj="$(cut_project)"
  printf '#!/bin/sh\ngit update-ref -d refs/tags/v1.0.1 2>/dev/null\nexit 0\n' >"$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  chmod +x "$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  local start=$SECONDS
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at push
  assert_output_contains "origin does not hold the release after the push"
  refute_output_contains "could not read back"
  # An answer is not waited through: the read-back's 120s would show here.
  [ $((SECONDS - start)) -lt 60 ] || fail "the push step waited $((SECONDS - start))s on a remote that answered"
}

# AT-4.1, AT-5.5
@test "a gh release edit that does not take fails the object step on the read-back" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  printf 'something else\n' >"$DEVBIN_TEST_TMPDIR/gh.obj.v1.0.1.body"
  perl -0pi -e 's{\A(#!/bin/sh\n)}{$1if [ "\$1 \$2" = "release edit" ]; then echo "gh \$*" >>"'"$DEVBIN_TEST_TMPDIR"'/gh.calls"; exit 0; fi\n}' \
    "$DEVBIN_TEST_TMPDIR/stubs/gh"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at object
  assert_output_contains "does not read back as set"
}

# ============================================================================
# WP-06: object ci with object_wait
# ============================================================================

# ci_project <release-yaml-extra> -- cut_project with the probe gate and extra
# release: lines.
ci_project() {
  cut_project "$1
  gates:
    - probe"
}

# ci_query_decl and ci_answers, the fixture's ci.query, are in
# tests/lib/release_fixtures.bash, since releasepublish.bats asks it too.

# release_sha <proj> -- the commit v1.0.1 tags.
release_sha() { git -C "$1" rev-parse 'refs/tags/v1.0.1^{commit}'; }

# remote_holds <ref> -- true when the fixture's remote holds <ref>.
remote_holds() { git --git-dir="$DEVBIN_TEST_TMPDIR/remote.git" rev-parse -q --verify "$1" >/dev/null; }

# AT-6.1
@test "under object: ci the cut makes no object and waits for the workflow's: it appears on the second look, the object row done, exit 0 (AC-6.1)" {
  proj="$(ci_project '  object: ci
  object_wait: 3s')"
  local look=2 # the look on which the fake's release appears
  printf 'v1.0.1 %s\n' "$look" >"$DEVBIN_TEST_TMPDIR/gh.appear"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state object done
  assert_released "$proj"
  [ "$(gh_calls 'release create')" -eq 0 ] || fail "the core made an object under object: ci"
  [ "$(gh_calls 'release view.* v1.0.1')" -ge "$look" ] || fail "want at least $look looks: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  assert_output_contains "v1.0.1 is released"
}

# AT-4.1, AT-6.1, AT-2.4
@test "under object: ci the candidate's green does not stand in for the object: none appears, the object row FAILED, exit 1, and no query is asked once the tag exists (AC-6.1, ST0011 WP02b)" {
  proj="$(ci_project "  object: ci
  object_wait: 1s
$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  # The query records each ask it is given once the tag exists.
  printf 'if git -C "%s" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then echo "$*" >>"%s/ci.after-tag"; fi\n' \
    "$proj" "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state legs done
  assert_state object FAILED
  assert_output_contains "no release object for v1.0.1"
  assert_released "$proj"
  [ -s "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "the legs step never asked the query, so this arm shows nothing about the object step"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.after-tag" ] || fail "the query was asked once v1.0.1 existed: $(cat "$DEVBIN_TEST_TMPDIR/ci.after-tag")"
  assert_output_contains "pushed v1.0.1 to origin"
}

# AT-6.1
@test "under object: ci an object already there is the object row already, with no wait" {
  proj="$(ci_project '  object: ci
  object_wait: 20m')"
  printf 'v1.0.1\n' >"$DEVBIN_TEST_TMPDIR/gh.releases"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state object already
  [ "$(gh_calls 'release view.* v1.0.1')" -eq 1 ] || fail "want one look: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-6.1
@test "under object: ci a dry run says it would wait, and looks no further than once" {
  proj="$(ci_project '  object: ci
  object_wait: 20m')"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state object would
  assert_output_contains "object_wait"
  [ "$(gh_calls 'release view.* v1.0.1')" -le 1 ] || fail "a dry run waited: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# ============================================================================
# ST0011 WP02b: THE CANDIDATE LEG. With ci.query declared and no publish.url,
# the release commit is pushed to its candidate ref on the remote that names
# the project's repository, and its CI is read by ci.query with that ref,
# beside the local gates under one wait loop: the tag only after every leg is
# green, and the candidate deleted once the tag is pushed or the cut stops.
# ============================================================================

# candidate_seen -- the fixture's ci.query records in ci.seen, at each ask,
# what the remote's candidate/v1.0.1 holds, `none` before it is pushed, so an
# arm can tell its run was read while the candidate held the release commit.
candidate_seen() {
  printf 'git --git-dir="%s" rev-parse -q --verify refs/heads/candidate/v1.0.1 >>"%s/ci.seen" || echo none >>"%s/ci.seen"\n' \
    "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/ciq.sh"
}

# remote_refuses <case-pattern> <why> -- the fixture's remote refuses, in a
# pre-receive hook, every ref update whose `<ref> <new-sha>` matches the shell
# case pattern <case-pattern>, saying <why>, as a protected branch would.
remote_refuses() {
  # shellcheck disable=SC2016 # the hook's own $ref and $new, expanded when it runs
  printf '#!/bin/sh\nwhile read -r old new ref; do\n  case "$ref $new" in\n    %s) echo "%s" >&2; exit 1 ;;\n  esac\ndone\nexit 0\n' "$1" "$2" \
    >"$DEVBIN_TEST_TMPDIR/remote.git/hooks/pre-receive"
  chmod +x "$DEVBIN_TEST_TMPDIR/remote.git/hooks/pre-receive"
}

# assert_nothing_public <proj> -- a red stop of the legs step, HEAD the release
# commit: no v1.0.1 tag in <proj> or on its remote, the remote's main not at
# the release commit, no release object made, and no candidate on the remote.
assert_nothing_public() {
  [ "$(git -C "$1" log -1 --format=%s)" = "release: v1.0.1" ] || fail "HEAD is not the release commit: $(git -C "$1" log --oneline -1)"
  if git -C "$1" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "v1.0.1 was tagged"; fi
  if remote_holds refs/tags/v1.0.1; then fail "the remote holds v1.0.1"; fi
  [ "$(git --git-dir="$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" != "$(git -C "$1" rev-parse HEAD)" ] ||
    fail "the release commit was pushed to the remote's main"
  [ "$(gh_calls 'release create')" -eq 0 ] || fail "a release object was made: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the candidate was left on the remote"; fi
}

# AT-2.5, AT-2.6
@test "the candidate leg pushes the release commit to candidate/v1.0.1 on the remote that names the repository and reads its run by that ref while the candidate holds it; on green the cut tags and pushes, then deletes the candidate (AC-2.2, AC-2.3, ST0011 WP02b)" {
  local rel out
  proj="$(ci_project "$(ci_query_decl 0s)")"
  # The start's ask finds no green, so the candidate is pushed; the loop's
  # first ask reads it green.
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  candidate_seen
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 7"* ]] || fail "the legs row does not name the candidate's run: $(row_of legs)"
  rel="$(release_sha "$proj")"
  assert_output_contains "${rel:0:12} pushed to candidate/v1.0.1 on origin"
  # Every ask about the release commit alone, with the candidate's ref, never
  # the tag, in its environment.
  [ "$(sort -u "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$rel tag=candidate/v1.0.1" ] ||
    fail "want every ask about $rel with tag=candidate/v1.0.1: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  # The start's ask came before the push, and every later one while the
  # candidate held the release commit.
  [ "$(sed -n 1p "$DEVBIN_TEST_TMPDIR/ci.seen")" = none ] ||
    fail "the start's ask did not come before the push: $(cat "$DEVBIN_TEST_TMPDIR/ci.seen")"
  [ "$(sed 1d "$DEVBIN_TEST_TMPDIR/ci.seen" | sort -u)" = "$rel" ] ||
    fail "the candidate's run was not read while candidate/v1.0.1 held $rel: $(cat "$DEVBIN_TEST_TMPDIR/ci.seen")"
  assert_released "$proj"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the candidate is still on the remote after the tag was pushed"; fi
  # The RELEASE seal's line for each leg.
  out="$(readlink -f "$proj/tmp/release/LATEST_RELEASE.out")" && [ -f "$out" ] || fail "the cut left no RELEASE seal under tmp/release/"
  grep -qE "^devbin\| leg: candidate green $rel [0-9]+s run 7\$" "$out" ||
    fail "no leg line for the candidate's green: $(grep -F 'leg:' "$out" || echo '(none)')"
  grep -qE "^devbin\| leg: local green $rel [0-9]+s " "$out" ||
    fail "no leg line for the local gates' green: $(grep -F 'leg:' "$out" || echo '(none)')"
}

# AT-2.5, AT-2.6
@test "a red candidate stops the cut at the legs step, naming its run: nothing is tagged or public, the candidate is deleted, and the release commit stays here (AC-2.2, AC-2.3, ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\trun 42')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"candidate is red: run 42"* ]] || fail "the legs row does not name the red run: $(row_of legs)"
  assert_nothing_public "$proj"
  [ "$(release_commits "$proj")" -eq 1 ] || fail "want the one release commit: $(git -C "$proj" log --oneline)"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
  assert_output_contains "This run pushed the candidate candidate/v1.0.1 to origin, deleted the candidate candidate/v1.0.1 from origin."
}

# AT-2.5
@test "a candidate not yet green is read again each poll, the loop printing a line with the clock each time its answer changes, and its green within ci.wait tags (ST0011 WP02b)" {
  local -a answers
  local clock='[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z' want
  # A wait no read here reaches: the arm is the loop's reads and lines, not
  # its deadline.
  proj="$(ci_project "$(ci_query_decl 30s)")"
  # The start's ask, which finds no green and pushes, then one ask a poll.
  answers=("$(printf 'none\tno run yet')" "$(printf 'none\tno run yet')" "$(printf 'pending\trun 9')" "$(printf 'green\trun 9')")
  ci_answers "${answers[@]}"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [ "$(wc -l <"$DEVBIN_TEST_TMPDIR/ci.calls")" -ge "${#answers[@]}" ] ||
    fail "want an ask for each of the ${#answers[@]} answers: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  for want in "candidate pending: [0-9a-f]{12} pushed to candidate/v1.0.1 on origin" "candidate none: no run yet" "candidate pending: run 9" "candidate green: run 9"; do
    grep -qE "^release: legs: $clock $want" <<<"$output" || fail "no line with the clock for '$want':
$output"
  done
}

# AT-2.5
@test "a candidate with no verdict within ci.wait stops the cut at the legs step as a timeout, naming its last answer, with nothing public and the candidate deleted (AC-2.2, ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"a timeout: not green within 0s (ci.wait) of the loop's start: candidate (none: no run yet)"* ]] ||
    fail "the legs row does not name the timeout and the last answer: $(row_of legs)"
  assert_nothing_public "$proj"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
}

@test "an answer that is not a verdict is unknown, named on the loop's line as it comes, read again until ci.wait, and the timeout's stop names it (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "success"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  grep -qE '^release: legs: [0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z candidate unknown: the query printed "success", which is not a verdict' <<<"$output" ||
    fail "the loop's line does not name what the query said:
$output"
  [[ "$(row_of legs)" == *'candidate (unknown: the query printed "success", which is not a verdict'* ]] ||
    fail "the legs row does not name what the query said: $(row_of legs)"
  assert_nothing_public "$proj"
}

@test "a query that fails is unknown, naming what it said on stderr, and at ci.wait the cut stops as a timeout (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  printf 'echo "gh: HTTP 502" >&2; exit 4\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"candidate (unknown: the query exited 4: gh: HTTP 502)"* ]] ||
    fail "the legs row does not name the query's failure: $(row_of legs)"
  assert_nothing_public "$proj"
}

@test "a query that hangs is cut off at its bound as unknown, and the cut stops at ci.wait within seconds, not at the query's leisure (ST0011 WP02b)" {
  local start
  proj="$(ci_project "$(ci_query_decl 1s)")"
  printf 'sleep 60\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  start=$SECONDS
  DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  # 2s, the floor this arm sets, and not 15s, the default it would otherwise
  # wait out (0191).
  [[ "$(row_of legs)" == *"candidate (unknown: did not answer within 2s)"* ]] ||
    fail "the legs row does not name the cut-off ask: $(row_of legs)"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung query held the cut for $((SECONDS - start))s"
  assert_nothing_public "$proj"
}

@test "the candidate's remote is the first, in release.remotes' order, whose url names the repository, whatever its case (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  remotes:
    - backup
    - origin")"
  # backup names t/demo in another case, and reaches the same bare remote.
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf https://github.com/T/Demo.git
  git -C "$proj" remote add backup https://github.com/T/Demo.git
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "pushed to candidate/v1.0.1 on backup"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from backup"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the candidate is still on the remote after the tag was pushed"; fi
}

@test "pre-flight refuses a cut where no remote pushes to the repository the candidate runs in, naming it, before anything is stamped or asked (ST0011 WP02b)" {
  local before
  proj="$(ci_project "$(ci_query_decl 0s)
  repo: t/demo")"
  origin_at "$proj" https://github.com/t/other.git
  ci_answers "$(printf 'green\trun 7')"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at pre-flight
  assert_output_contains "no remote of this repository pushes to t/demo, the repository whose CI runs the candidate"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "the query was asked before pre-flight refused: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a refused pre-flight wrote something"
}

@test "a candidate push the remote refuses stops the cut at the legs step at once, in git's words, before any other leg starts, with nothing public (ST0011 WP02b)" {
  local start
  proj="$(ci_project "$(ci_query_decl 20m)")"
  ci_answers "$(printf 'none\tno run yet')"
  remote_refuses 'refs/heads/candidate/*' "candidate refs are protected here"
  start=$SECONDS
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"the candidate did not start: the candidate push to origin failed"* ]] ||
    fail "the legs row does not name the refused push: $(row_of legs)"
  assert_output_contains "candidate refs are protected here"
  if gate_ran; then fail "the local gates started after the candidate's push was refused"; fi
  # At once: never left to run out its 20m ci.wait.
  [ $((SECONDS - start)) -lt 60 ] || fail "the refused push held the cut for $((SECONDS - start))s"
  assert_nothing_public "$proj"
  assert_output_contains "This run tagged nothing and pushed nothing"
}

# AT-2.6
@test "a cut stopped red at the legs step is cut again, no tag existing: the stamp and the commit read already, and the candidate, pushed again, reads green and the cut tags (AC-2.3, ST0011 WP02b)" {
  local rel
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\trun 42')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  rel="$(git -C "$proj" rev-parse HEAD)"
  # A flaky red: the same version is cut again, and the candidate's new run
  # is green.
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 43')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state stamp already
  assert_state commit already
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 43"* ]] || fail "the legs row does not name the new run: $(row_of legs)"
  [ "$(release_sha "$proj")" = "$rel" ] || fail "v1.0.1 does not tag the release commit the first cut made"
  [ "$(release_commits "$proj")" -eq 1 ] || fail "a second release commit was made: $(git -C "$proj" log --oneline)"
  assert_released "$proj"
}

# AT-2.6
@test "a candidate a killed run left, holding the release commit, is deleted by the next cut once the tag is pushed, though that cut did not push it (AC-2.3, ST0011 WP02b)" {
  local rel
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  cut_to_tag_stop --candidate "$proj" v1.0.1
  rel="$(git -C "$proj" rev-parse HEAD)"
  # What a run killed after its candidate push leaves: the candidate on the
  # remote at the release commit, and no tag. Its run reads green from the start.
  git -C "$proj" push -q origin "$rel:refs/heads/candidate/v1.0.1"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs already
  refute_output_contains "pushed to candidate/v1.0.1 on origin"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the candidate a killed run left is still on the remote"; fi
  assert_released "$proj"
}

# AT-2.6
@test "a candidate that will not be deleted once the tag is pushed is named with the command that deletes it, and the cut ends at exit 1 with the release standing (AC-2.3, ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  # A deletion's new sha is all zeros.
  remote_refuses 'refs/heads/candidate/*" "0000000000000000000000000000000000000000*' "candidate refs are never deleted here"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state legs done
  assert_state push done
  assert_released "$proj"
  assert_output_contains "candidate refs are never deleted here"
  assert_output_contains "release: v1.0.1 is published, and the tag and the release stand."
  assert_output_contains "release: the candidate candidate/v1.0.1 on origin was NOT deleted ("
  # The command is the line's last word, so a copy of it takes no full stop.
  grep -qx -- "release: the candidate candidate/v1\.0\.1 on origin was NOT deleted (.*) -- delete it by hand: git push origin :refs/heads/candidate/v1\.0\.1" <<<"$output" ||
    fail "no line ending with the command that deletes the candidate: $output"
  remote_holds refs/heads/candidate/v1.0.1 || fail "the candidate is gone, so this arm did not reach a delete that fails"
}

@test "a stop whose candidate will not be deleted names it on a line of its own, ending with the command that deletes it (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\trun 42')"
  # A deletion's new sha is all zeros.
  remote_refuses 'refs/heads/candidate/*" "0000000000000000000000000000000000000000*' "candidate refs are never deleted here"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  assert_output_contains "candidate refs are never deleted here"
  assert_output_contains "This run pushed the candidate candidate/v1.0.1 to origin. Fix what the row names, then run again."
  grep -qx -- "release: the candidate candidate/v1\.0\.1 on origin was NOT deleted (.*) -- delete it by hand: git push origin :refs/heads/candidate/v1\.0\.1" <<<"$output" ||
    fail "no line of its own ending with the command that deletes the candidate: $output"
  remote_holds refs/heads/candidate/v1.0.1 || fail "the candidate is gone, so this arm did not reach a delete that fails"
}

@test "a red candidate stops the local gates' whole run: a gate still running, and its children, run on nowhere once the cut has stopped, and the seal's local line says the stop ended it (ST0011 WP02b)" {
  local nap=4 out
  proj="$(ci_project "$(ci_query_decl 20m)")"
  # The gate marks its start, then sleeps in a child of its own, as a test
  # runner's children do, and would mark its waking.
  gate_does "touch '$DEVBIN_TEST_TMPDIR/gate.started'; sleep $nap; touch '$DEVBIN_TEST_TMPDIR/gate.woke'"
  # The candidate reads red once the gate runs, so the stop comes while it sleeps.
  printf 'if [ -e "%s/gate.started" ]; then printf "failed\\trun 42\\n"; else printf "none\\tno run yet\\n"; fi\nexit 0\n' \
    "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"candidate is red: run 42"* ]] || fail "the legs row does not name the red run: $(row_of legs)"
  assert_output_contains "release: legs: the local gates were stopped, their whole process group, and their output follows"
  # The seal names the run the stop ended, never the loop's last read of it
  # as running.
  out="$(readlink -f "$proj/tmp/release/LATEST_RELEASE.out")" && [ -f "$out" ] ||
    fail "the cut left no RELEASE seal under tmp/release/"
  grep -qE "^devbin\| leg: local none [0-9a-f]+ [0-9]+s release\.gates were stopped by the cut at [0-9a-f]+ before they ended\$" "$out" ||
    fail "the seal's local line does not say the stop ended the run: $(grep -F 'leg:' "$out" || echo '(none)')"
  # Past the gate's own sleep: nothing of the run woke to go on in the tree.
  sleep "$((nap + 1))"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gate.woke" ] || fail "the gate ran on after the cut stopped it"
  assert_nothing_public "$proj"
}

@test "a cut ended by a signal to its whole group while its local gates run, its tee among them, stops their whole run and removes its scratch: nothing of it runs on or is left once the cut has gone (ST0011 WP02b)" {
  local nap=4 pid rc=0 n=0 tmp="$DEVBIN_TEST_TMPDIR/cut-tmp"
  local -a scratch
  proj="$(cut_project)"
  mkdir -p "$tmp"
  gate_does "touch '$DEVBIN_TEST_TMPDIR/gate.started'; sleep $nap; touch '$DEVBIN_TEST_TMPDIR/gate.woke'"
  # The cut in a process group of its own, as a job is, so the signal reaches
  # its group and not the gates' own; bats's descriptor closed, so a run left
  # behind cannot hold the arm. Its scratch goes under the TMPDIR it is given.
  set -m
  TMPDIR="$tmp" release_in "$proj" v1.0.1 --yes >"$DEVBIN_TEST_TMPDIR/cut.out" 2>&1 3>&- &
  pid=$!
  set +m
  while [ ! -e "$DEVBIN_TEST_TMPDIR/gate.started" ] && [ "$n" -lt 30 ]; do
    sleep 1
    n=$((n + 1))
  done
  [ -e "$DEVBIN_TEST_TMPDIR/gate.started" ] || fail "the gate never started: $(cat "$DEVBIN_TEST_TMPDIR/cut.out")"
  scratch=("$tmp"/devbin-release.*)
  [ -d "${scratch[0]}" ] || fail "no scratch of the cut's under its TMPDIR while its gates run: $(ls -A "$tmp")"
  # TERM to the cut's whole group, the tee its output runs through included,
  # as a Ctrl-C or a hangup at a terminal reaches it.
  kill -TERM -- "-$pid"
  wait "$pid" || rc=$?
  [ "$rc" -ne 0 ] || fail "the cut ended by TERM exited 0: $(cat "$DEVBIN_TEST_TMPDIR/cut.out")"
  # Past the gate's own sleep: nothing of the run woke to go on in the tree.
  sleep "$((nap + 1))"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gate.woke" ] || fail "the gate ran on after the cut was ended: $(cat "$DEVBIN_TEST_TMPDIR/cut.out")"
  [ ! -e "${scratch[0]}" ] || fail "the cut ended by a signal left its scratch behind: ${scratch[0]}"
}

@test "a cut run again after its local gates went red runs them again and decides on that run: the earlier run's red record does not stop it (ST0011 WP02b)" {
  proj="$(cut_project)"
  gate_does "exit 1"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  # The gate is fixed, and takes a moment, as a suite does.
  gate_does "sleep 2"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  assert_released "$proj"
}

@test "a cut run again after a red candidate does not stop on that earlier run's red: it waits for the run of its own push, whose green tags (ST0011 WP02b)" {
  local -a answers
  proj="$(ci_project "$(ci_query_decl 30s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\trun 42')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  # The stop deleted the candidate, and CI answers with the earlier run's red
  # until it has registered the run of the next push.
  answers=("$(printf 'failed\trun 42')" "$(printf 'failed\trun 42')" "$(printf 'pending\trun 43')" "$(printf 'green\trun 43')")
  ci_answers "${answers[@]}"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 43"* ]] || fail "the legs row does not name this push's run: $(row_of legs)"
  [ "$(wc -l <"$DEVBIN_TEST_TMPDIR/ci.calls")" -ge "${#answers[@]}" ] ||
    fail "want an ask for each of the ${#answers[@]} answers: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  assert_released "$proj"
}

@test "a cut run again where a killed run left its red candidate holding the release commit deletes that candidate and pushes it again, so CI runs this push's own run, whose green tags (ST0011 WP02b)" {
  local -a answers ev
  local r z
  proj="$(ci_project "$(ci_query_decl 30s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\trun 42')"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  # As a run killed before its delete leaves it: the candidate on the remote,
  # holding the release commit, its run red.
  r="$(git -C "$proj" rev-parse HEAD)"
  git -C "$proj" push -q origin "$r:refs/heads/candidate/v1.0.1"
  z="$(printf '%s' "$r" | tr '0-9a-f' '0')"
  # From here the remote records each ref it takes: the same commit pushed to
  # a ref already holding it is no change, and records nothing.
  printf '#!/bin/sh\ncat >>"%s/remote.events"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  chmod +x "$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  answers=("$(printf 'failed\trun 42')" "$(printf 'failed\trun 42')" "$(printf 'pending\trun 43')" "$(printf 'green\trun 43')")
  ci_answers "${answers[@]}"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 an earlier run left on origin, holding ${r:0:12} and read red, was deleted, so this push makes a run of its own"
  mapfile -t ev < <(grep ' refs/heads/candidate/v1.0.1$' "$DEVBIN_TEST_TMPDIR/remote.events")
  [ "${#ev[@]}" -ge 2 ] || fail "want the left candidate's delete, then this push: $(cat "$DEVBIN_TEST_TMPDIR/remote.events" 2>&1)"
  [ "${ev[0]}" = "$r $z refs/heads/candidate/v1.0.1" ] || fail "the first event is not the left candidate's delete: ${ev[*]}"
  [ "${ev[1]}" = "$z $r refs/heads/candidate/v1.0.1" ] || fail "the second event is not this push of the release commit: ${ev[*]}"
  [[ "$(row_of legs)" == *"candidate: run 43"* ]] || fail "the legs row does not name this push's run: $(row_of legs)"
  assert_released "$proj"
}

@test "a candidate's green stands while the local gates run on past ci.wait: a query that stops answering after it cannot time the cut out (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 1s)")"
  # The local gates outlast ci.wait.
  gate_does "sleep 4"
  # One green, then no verdict at all, every ask after it.
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')" "no verdict here"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 7"* ]] || fail "the legs row does not name the candidate's green: $(row_of legs)"
  assert_released "$proj"
}

@test "the candidate's remote is found by OWNER/NAME where its url goes through an ssh host alias and release.repo names the repository (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  repo: t/demo")"
  # origin by a host alias, as ~/.ssh/config gives one, reaching the same bare
  # remote.
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf git@gh-alias:t/demo.git
  git -C "$proj" remote set-url origin git@gh-alias:t/demo.git
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "pushed to candidate/v1.0.1 on origin"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
  if remote_holds refs/heads/candidate/v1.0.1; then fail "the candidate is still on the remote after the tag was pushed"; fi
  assert_released "$proj"
}

@test "the candidate's remote is the first, in release.remotes' order, of two that push to the repository's OWNER/NAME on one host not its own, an ssh host alias written in two cases (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  repo: t/demo
  remotes:
    - origin
    - backup")"
  # Both by one ssh host alias, backup's url in other cases, and each reaching
  # the fixture's bare remote. git's own order would put backup first.
  origin_at "$proj" git@gh-alias:t/demo.git
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf git@GH-Alias:T/Demo.git
  git -C "$proj" remote add backup git@GH-Alias:T/Demo.git
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "pushed to candidate/v1.0.1 on origin"
  assert_output_contains "release: legs: the candidate candidate/v1.0.1 was deleted from origin"
  assert_released "$proj"
}

@test "release_candidate_remote judges each remote by where a push to it goes, its pushurls where it has any, else every url, git's leading-slash forms read on their own host (ST0011 WP02b)" {
  # pushes_to <key> <value>... -- a repository holding only the remotes those
  # remote.<name>.url and remote.<name>.pushurl pairs give, and
  # release_candidate_remote's answer there for O/N, with no remote declared,
  # so the search runs in git's order.
  pushes_to() {
    local d
    d="$(mktemp -d "$DEVBIN_TEST_TMPDIR/remotes.XXXXXX")"
    git init -q -b main "$d"
    while [ "$#" -gt 0 ]; do
      git -C "$d" config --add "$1" "$2"
      shift 2
    done
    run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; rc=0; release_candidate_remote O/N "" || rc=$?; printf "rc=%s\n" "$rc"' _ "$DEVBIN_LIB_DIR" "$d"
    assert_success
  }
  # A pushurl is where a push goes, and the url then is not: origin's url names
  # O/N on its own host, but it pushes to O/N on gitlab.com, so with z-berg on
  # codeberg.org two other hosts are refused, where reading its url as well
  # would take origin at once.
  pushes_to remote.origin.url https://github.com/O/N remote.origin.pushurl https://gitlab.com/O/N remote.z-berg.url https://codeberg.org/O/N
  assert_output $'origin\tgitlab.com\nz-berg\tcodeberg.org\nrc=3'
  # git's scp form host:/OWNER/NAME, and a doubled slash after the host, each
  # push to O/N on its own host, ahead of a mirror first in git's order.
  pushes_to remote.origin.url git@github.com:/O/N.git remote.mirror.url git@gitlab.com:O/N.git
  assert_output $'origin\nrc=0'
  pushes_to remote.origin.url https://github.com//O/N remote.mirror.url https://gitlab.com/O/N
  assert_output $'origin\nrc=0'
  # A remote with two urls pushes to both, so the one on O/N's own host takes it.
  pushes_to remote.multi.url https://github.com/O/N remote.multi.url https://gitlab.com/O/N remote.z-berg.url https://codeberg.org/O/N
  assert_output $'multi\nrc=0'
  # A pushurl is where the push goes, whatever the url names: z-fork pushes to
  # O/N at gh-alias, and a-mirror to O/N on gitlab.com, two hosts.
  pushes_to remote.a-mirror.url https://gitlab.com/O/N remote.z-fork.url https://gitlab.com/O/Other remote.z-fork.pushurl git@gh-alias:O/N.git
  assert_output $'a-mirror\tgitlab.com\nz-fork\tgh-alias\nrc=3'
  # Two remotes with a pushurl and no url, on two hosts.
  pushes_to remote.a-lab.pushurl git@gitlab.com:O/N.git remote.b-berg.pushurl git@codeberg.org:O/N.git
  assert_output $'a-lab\tgitlab.com\nb-berg\tcodeberg.org\nrc=3'
}

@test "pre-flight refuses a cut where remotes on two hosts push to the repository's OWNER/NAME and none to its own host, naming each remote with its host and the own host to point a push url at, before anything is stamped or asked (ST0011 WP02b)" {
  local before
  proj="$(ci_project "$(ci_query_decl 0s)
  repo: t/demo")"
  # origin by an ssh host alias and a mirror on another host, neither on
  # github.com, each reaching the fixture's bare remote so both answer.
  origin_at "$proj" git@gh-alias:t/demo.git
  git -C "$proj" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf https://gitlab.example.com/t/demo.git
  git -C "$proj" remote add mirror https://gitlab.example.com/t/demo.git
  ci_answers "$(printf 'green\trun 7')"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at pre-flight
  assert_output_contains "no remote pushes to t/demo on github.com, the repository's own host, and remotes push to t/demo on more than one other host"
  assert_output_contains "origin on gh-alias"
  assert_output_contains "mirror on gitlab.example.com"
  assert_output_contains "point a remote's push url at t/demo on github.com: a cut takes that remote before any other"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "the query was asked before pre-flight refused: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a refused pre-flight wrote something"
}

# AT-2.2
@test "a declared publish.candidate names a cut's candidate ref without publish.url, the confirm naming its push before the tag (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  publish:
    candidate: rc/{tag}")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  [[ "$(row_of confirm)" == *"--yes given: push the release commit the commit step makes to origin as rc/v1.0.1, for CI, deleted once v1.0.1 is pushed; tag v1.0.1 at"* ]] ||
    fail "the confirm row does not name the candidate's push before the tag: $(row_of confirm)"
  assert_output_contains "pushed to rc/v1.0.1 on origin"
  assert_output_contains "release: legs: the candidate rc/v1.0.1 was deleted from origin"
  if remote_holds refs/heads/rc/v1.0.1; then fail "the candidate is still on the remote after the tag was pushed"; fi
  assert_released "$proj"
}

# ============================================================================
# ST0011 WP-05 AND WP-06: THE REMOTE LEGS AND THE macOS STAGE IN THE LOOP. Each
# host release.legs names is reached at pre-flight and runs the project's gates
# at the release commit as a leg, its seal copied back from a fake host
# (release_fixtures.bash's fake_ssh and fake_scp: nothing leaves this machine,
# kovacs included); the macOS stage, where the built-in macos is enabled, runs
# app-sign then app-notarize at the release commit as a leg of its own, here
# through the project's own macos handler under a uname that says Darwin, so
# no arm needs an Apple tool and every arm runs on every host.
# ============================================================================

# legs_env -- the fake hosts, near a host and far none, so ssh cannot reach
# it; the stub cargo; a uname answering -s from UNAME_STUB_OS, this host's own
# answer until an arm sets it; and the cache under the test's tmpdir. Called in
# the arm itself, never in a command substitution, so what it sets and exports
# holds there.
legs_env() {
  HOSTS="$DEVBIN_TEST_TMPDIR/hosts"
  mkdir -p "$HOSTS/near" "$DEVBIN_TEST_TMPDIR/stubs"
  fake_ssh
  fake_scp
  stub_cargo
  UNAME_STUB_OS="$(uname -s)"
  export UNAME_STUB_OS
  stub_uname -s UNAME_STUB_OS
  export DEVBIN_CACHE_HOME="$DEVBIN_TEST_TMPDIR/cache"
}

# legs_project -- after legs_env, cut_project with release.legs naming near and
# far; the built-in macos enabled, answered by the project's own handler, which
# records each call with the commit it stood on in macos.calls and exits 0, or
# 3, saying so, where macos.fail stands beside macos.calls; and
# its app, out/Demo.app, built by macos.build and the build: block's artefact
# `app`, keyed by the stub cargo over src, so the cut names its key in the seal.
# The handler stands in for app-sign, so it never runs macos.build (./mkapp) and
# caches nothing: the arm holds the cut's answer, not a cache entry.
# Committed and pushed.
legs_project() {
  local proj
  proj="$(cut_project "  gates:
    - probe
  legs:
    - near
    - far")"
  perl -0pi -e 's/\ncommands:\n  release:\n    enabled: true\n/\ncommands:\n  release:\n    enabled: true\n  macos:\n    enabled: true\n/' \
    "$proj/bin/.devbin/config.yaml"
  printf '%s\n' 'macos:' '  app: out/Demo.app' '  build: ./mkapp' 'build:' '  inputs:' '    - src' '  artefacts:' '    app:' \
    '      tool: cargo' '      path: out/Demo.app' >>"$proj/bin/.devbin/config.yaml"
  grep -q '^  macos:$' "$proj/bin/.devbin/config.yaml" || fail "the fixture's config does not enable macos"
  mkdir -p "$proj/src"
  printf 'fn main() {}\n' >"$proj/src/main.rs"
  printf 'out/\n' >>"$proj/.gitignore"
  create_test_command "$proj" macos "$(printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$1" "$(git rev-parse HEAD)" >>"%s/macos.calls"\n[ ! -e "%s/macos.fail" ] || { printf "the stub fails %%s\\n" "$1"; exit 3; }\n' "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR")" >/dev/null
  git -C "$proj" add -A
  git -C "$proj" commit -qm "remote legs and the macOS stage"
  git -C "$proj" push -q origin main
  printf '%s\n' "$proj"
}

# leg_line <leg> <word> -- true when the loop said <leg>'s answer was <word>,
# with the clock, on a line of the last `run`: `<clock> <leg> <word>: <detail>`.
leg_line() { grep -qE "^release: legs: [0-9]{2}:[0-9]{2}:[0-9]{2}Z $(sed 's/\./\\./g' <<<"$1") $2: " <<<"$output"; }

# AT-2.7, AT-3.3, AT-3.6
@test "each reached host release.legs names and the macOS stage start with the local gates at the release commit and are read by the one loop, each sealed and named in the RELEASE seal; a host ssh cannot reach is named at pre-flight, recorded as not run, never waited for; and the seal names the stage's artefact's key; and run again after a stop, every leg is green already and none starts (AC-2.2, AC-3.2, AC-3.3, ST0011 WP-05, WP-06)" {
  local rel out key leg sends calls pairs=()
  legs_env
  proj="$(legs_project)"
  export UNAME_STUB_OS=Darwin
  # Stopped at the tag step as cut_to_tag_stop stops a cut, asserted here, since
  # this cut's stop names acts of the legs' (near sent R, the stage started),
  # never "pushed nothing".
  DEVBIN_RELEASE_POLL_SECONDS=1 PATH="$(tag_refused_path)" run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want exit 1 at the tag step, got $status:
$output"
  assert_state tag FAILED
  assert_output_contains "the fixture refuses git tag -a"
  [ "$(state_of legs)" = done ] || fail "the legs row is '$(state_of legs)', want done:
$output"
  [ -z "$(git -C "$proj" tag -l v1.0.1)" ] || fail "the stopped cut tagged v1.0.1"
  rel="$(git -C "$proj" rev-parse HEAD)"
  [[ "$(git -C "$proj" log -1 --format=%s)" == "release: "* ]] || fail "HEAD is not the release commit: $(git -C "$proj" log --oneline -3)"
  [[ "$(row_of pre-flight)" == *"legs.far absent, not run: ssh could not reach far"* ]] ||
    fail "pre-flight does not name far as absent: $(row_of pre-flight)"
  for leg in legs.near macos; do
    leg_line "$leg" pending || fail "the loop never said $leg pending:
$output"
    leg_line "$leg" green || fail "the loop never read $leg green:
$output"
  done
  if grep -qE '^release: legs: .* legs\.far ' <<<"$output"; then fail "far was started or read:
$output"; fi
  out="$(readlink -f "$proj/tmp/release/LATEST_RELEASE.out")" && [ -f "$out" ] || fail "the cut left no RELEASE seal under tmp/release/"
  for leg in local legs.near macos; do
    grep -qE "^devbin\| leg: $(sed 's/\./\\./g' <<<"$leg") green $rel [0-9]+s " "$out" ||
      fail "no green leg line for $leg at $rel: $(grep -F 'leg:' "$out" || echo '(none)')"
  done
  grep -qxF "devbin| leg: legs.far none $rel 0s absent at pre-flight, not run: ssh could not reach far: ssh: Could not resolve hostname far: nodename nor servname provided, or not known" "$out" ||
    fail "no line recording far as not run: $(grep -F 'leg:' "$out" || echo '(none)')"
  # near's pair, copied back from the host it ran on.
  pairs=("$proj"/tmp/release/legs/near/*.GATES.errors)
  [ -f "${pairs[0]}" ] || fail "near's seal was not copied back under tmp/release/legs/near/"
  # The stage, app-sign then app-notarize, each at the release commit.
  [ "$(cat "$DEVBIN_TEST_TMPDIR/macos.calls")" = "$(printf 'app-sign %s\napp-notarize %s' "$rel" "$rel")" ] ||
    fail "the stage did not run app-sign then app-notarize at $rel: $(cat "$DEVBIN_TEST_TMPDIR/macos.calls")"
  # The artefact the stage used, keyed at the release commit by the cache itself.
  key="$(devbin_run "$proj" cache key app --commit "$rel")" || fail "the arm cannot key app at $rel: $key"
  grep -qxF "devbin| cache"$'\t'"app"$'\t'"$key" "$out" || fail "the seal names no cache line for app $key: $(grep -F 'cache' "$out" || echo '(none)')"
  assert_output_contains "release: cache: app $key"
  # The confirm named what other machines see, R sent to near and the app
  # submitted to Apple, and the stop's sentence names both as done.
  [[ "$(row_of confirm)" == *"to near and run the gates there (release.legs)"* ]] ||
    fail "the confirm does not name the send to near: $(row_of confirm)"
  [[ "$(row_of confirm)" == *"and submit it to Apple's notary service (the macOS stage)"* ]] ||
    fail "the confirm does not name the submission to Apple: $(row_of confirm)"
  assert_output_contains "sent ${rel:0:12} to near to run its leg"
  assert_output_contains "started the macOS stage, which submits the app to Apple's notary service"
  # Run again after the stop at the tag: every leg is green at its start, as a
  # dry run reads it, so none runs again. near's kept pair answers its start,
  # so R is not sent to it again (a start sends it by send-pack, which the fake
  # ssh logs as git-receive-pack); the stage's green stands.
  sends="$(grep -c 'git-receive-pack' "$DEVBIN_TEST_TMPDIR/ssh.calls")" || sends=0
  [ "$sends" -gt 0 ] || fail "the first cut never sent R to near: $(cat "$DEVBIN_TEST_TMPDIR/ssh.calls")"
  calls="$(cat "$DEVBIN_TEST_TMPDIR/macos.calls")"
  DEVBIN_RELEASE_POLL_SECONDS=1 PATH="$(tag_refused_path)" run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want exit 1 at the tag step again, got $status:
$output"
  [ "$(state_of legs)" = already ] || fail "the legs row is '$(state_of legs)' on the cut run again, want already:
$output"
  [ "$(grep -c 'git-receive-pack' "$DEVBIN_TEST_TMPDIR/ssh.calls")" = "$sends" ] ||
    fail "R was sent to near again though its kept pair reads green: $(grep -F 'git-receive-pack' "$DEVBIN_TEST_TMPDIR/ssh.calls")"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/macos.calls")" = "$calls" ] || fail "the stage ran again though its seal reads green: $(cat "$DEVBIN_TEST_TMPDIR/macos.calls")"
  # Devbin's own config declares its remote leg, kovacs.
  [ "$(. "$DEVBIN_LIB_DIR/helpers" && . "$DEVBIN_LIB_DIR/config" && cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml" && cfg_release_list legs)" = kovacs ] ||
    fail "Devbin's own config does not declare kovacs as its one remote leg"
}

@test "pre-flight refuses the macOS stage on a host whose platform word is not macos, naming the stage and the word, a remote host that answers and cannot be read, and a project name no host's repository can take, before anything is stamped (ST0011 WP-05, WP-06)" {
  local head
  legs_env
  proj="$(legs_project)"
  : >"$HOSTS/near/.broken"
  # A project name no host's bare repository can take.
  perl -0pi -e 's/^project:\n  name: demo\n/project:\n  name: _demo\n/m' "$proj/bin/.devbin/config.yaml"
  grep -qx '  name: _demo' "$proj/bin/.devbin/config.yaml" || fail "the fixture's config does not name the project _demo"
  git -C "$proj" commit -qam "a project name no host can take"
  head="$(git -C "$proj" rev-parse HEAD)"
  export UNAME_STUB_OS=Linux
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at pre-flight
  [[ "$(row_of pre-flight)" == *"the macOS stage is declared (commands.macos.enabled), and this host is linux"* ]] ||
    fail "pre-flight does not refuse the stage on linux: $(row_of pre-flight)"
  [[ "$(row_of pre-flight)" == *"release.legs: near cannot be read as a leg: near answered, and uname -s failed there"* ]] ||
    fail "pre-flight does not refuse near, which answered and could not be read: $(row_of pre-flight)"
  [[ "$(row_of pre-flight)" == *"release.legs: the project's name '_demo' cannot name a repository on a host"* ]] ||
    fail "pre-flight does not refuse a project name no host can take: $(row_of pre-flight)"
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "the refused cut committed: $(git -C "$proj" log --oneline -3)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/macos.calls" ] || fail "the stage ran: $(cat "$DEVBIN_TEST_TMPDIR/macos.calls")"
}

@test "a remote leg whose start fails stops the cut at once, naming the leg and why, never a wait to ci.wait for a leg no read could turn green (ST0011 WP-05)" {
  legs_env
  proj="$(legs_project)"
  # near answers, so pre-flight reaches it, and refuses to start anything.
  : >"$HOSTS/near/.fail-start"
  export UNAME_STUB_OS=Darwin
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"the legs.near leg did not start: "*"the host refused to start anything"* ]] ||
    fail "the cut did not stop at near's failed start, naming why: $(row_of legs)"
  refute_output_contains "(ci.wait)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/macos.calls" ] || fail "the stage started after near's start failed: $(cat "$DEVBIN_TEST_TMPDIR/macos.calls")"
}

@test "a macOS stage whose run fails is red with its exit, the newest record's word and its last line, and the cut stops at the legs step with nothing tagged (ST0011 WP-06)" {
  legs_env
  proj="$(legs_project)"
  : >"$DEVBIN_TEST_TMPDIR/macos.fail"
  export UNAME_STUB_OS=Darwin
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"macos is red: the macOS stage ended (exit "*") at "*" -- its last line: "* ]] ||
    fail "the stage's failure is not named with its exit and last line: $(row_of legs)"
  grep -qx "app-sign $(git -C "$proj" rev-parse HEAD)" "$DEVBIN_TEST_TMPDIR/macos.calls" ||
    fail "the stage did not run app-sign at the release commit: $(cat "$DEVBIN_TEST_TMPDIR/macos.calls" 2>&1)"
  [ -z "$(git -C "$proj" tag -l v1.0.1)" ] || fail "the failed cut tagged v1.0.1"
}

# ============================================================================
# WP-06: after:
# ============================================================================

@test "an after: line keeps the flag the cut's gate saw: a person at a terminal is still there (0158)" {
  # Inside the gate stdin is /dev/null, so a flag read again there said nobody
  # was there; through gate_exec the line keeps what the gate saw.
  require_pty
  require_expect
  printf '#!/bin/sh\nprintf %%s "${DEVBIN_GATE_TTY-unset}" >"%s/after.flag"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/flag.sh"
  proj="$(ci_project "  after:
    - sh $DEVBIN_TEST_TMPDIR/flag.sh")"
  run run_tty_answer y env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" sh -c "cd '$proj' && ./bin/devbin release v1.0.1"
  assert_success
  [ "$(cat "$DEVBIN_TEST_TMPDIR/after.flag" 2>&1)" = 1 ] || fail "the after: line saw: $(cat "$DEVBIN_TEST_TMPDIR/after.flag" 2>&1)"
}

@test "after: commands run in order and are reported, the after row done" {
  proj="$(ci_project "  after:
    - touch $DEVBIN_TEST_TMPDIR/after.one
    - touch $DEVBIN_TEST_TMPDIR/after.two")"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state after done
  [ -e "$DEVBIN_TEST_TMPDIR/after.one" ] && [ -e "$DEVBIN_TEST_TMPDIR/after.two" ] || fail "after: did not run: $output"
  assert_output_contains "v1.0.1 is released"
}

@test "a failing after: command leaves the release published, does not stop the next, and exits 1 saying so" {
  proj="$(ci_project "  after:
    - false
    - touch $DEVBIN_TEST_TMPDIR/after.two")"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state after FAILED
  [ -e "$DEVBIN_TEST_TMPDIR/after.two" ] || fail "one failing after: stopped the next"
  assert_output_contains "after: false failed"
  assert_output_contains "published"
  assert_released "$proj"
}

# THE SEAL CLOSES ON EVERY PATH A CUT ENDS ON (issue 0297): an after: command
# run to the end, one that fails, and a signal one of them sends to the cut's
# whole group, as a Ctrl-C or a kill of the job reaches it. Each arm reads the
# RELEASE seal through lib/runlog's own classifier and the verdict line naming
# it (assert_release_seal), never the cut's wording alone.

@test "a cut whose after: command runs to the end closes its RELEASE seal green, its verdict line naming it, and exits 0, the command's marker file made (0297, ST0011 WP02b-2)" {
  local seal
  proj="$(ci_project "  after:
    - touch $DEVBIN_TEST_TMPDIR/after.ran")"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  [ -e "$DEVBIN_TEST_TMPDIR/after.ran" ] || fail "the after: command did not run: $output"
  seal="$(release_seal "$proj")" || fail "$output"
  assert_release_seal "$seal" green "$output"
}

@test "a cut whose after: command fails closes its RELEASE seal red, naming the command, its verdict line naming it, and exits 1, the command's marker file made (0297, ST0011 WP02b-2)" {
  local seal
  printf 'touch "%s/after.ran"\nexit 1\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/after.sh"
  proj="$(ci_project "  after:
    - sh $DEVBIN_TEST_TMPDIR/after.sh")"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want exit 1, got $status: $output"
  [ -e "$DEVBIN_TEST_TMPDIR/after.ran" ] || fail "the after: command did not run: $output"
  seal="$(release_seal "$proj")" || fail "$output"
  assert_release_seal "$seal" failed "$output"
  grep -qF "after: sh $DEVBIN_TEST_TMPDIR/after.sh failed" "$seal" ||
    fail "the seal does not name the after: command that failed: $(cat "$seal")"
}

@test "a cut whose after: command signals the cut's whole group still closes its RELEASE seal, red and naming the signal, its verdict line naming it, and ends with 128 plus the signal's number (0297, ST0011 WP02b-2)" {
  local sig=TERM pid rc=0 n=0 bound=30 seal out="$DEVBIN_TEST_TMPDIR/cut.out"
  printf 'kill -s %s 0\n' "$sig" >"$DEVBIN_TEST_TMPDIR/signal.sh"
  proj="$(ci_project "  after:
    - sh $DEVBIN_TEST_TMPDIR/signal.sh")"
  # The cut in a process group of its own, as a job is, so the after:
  # command's signal reaches the cut's whole group and not bats; bats's
  # descriptor closed, so a process left behind cannot hold the arm.
  set -m
  release_in "$proj" v1.0.1 --yes >"$out" 2>&1 3>&- &
  pid=$!
  set +m
  wait "$pid" || rc=$?
  # The job's own process ends with the signal, and the cut's seal comes after
  # it, so the seal is read once nothing of the group is left to write it,
  # waiting at most <bound> seconds.
  while kill -0 -- "-$pid" 2>/dev/null && [ "$n" -lt "$bound" ]; do
    sleep 1
    n=$((n + 1))
  done
  if kill -0 -- "-$pid" 2>/dev/null; then fail "the cut's group still runs ${bound}s after its job ended: $(cat "$out")"; fi
  [ "$rc" -eq "$((128 + $(kill -l "$sig")))" ] || fail "want exit 128 plus SIG$sig's number, got $rc: $(cat "$out")"
  seal="$(release_seal "$proj")" || fail "$(cat "$out")"
  assert_release_seal "$seal" failed "$(cat "$out")"
  grep -qF "SIG$sig" "$seal" || fail "the seal does not name SIG$sig: $(cat "$seal")"
}

@test "a dry run with after: and ci.query declared runs neither, asks the query nothing while the release commit is still to be made, and says what it would do (ST0011 WP02b)" {
  proj="$(ci_project "  after:
    - touch $DEVBIN_TEST_TMPDIR/after.one
$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state after would
  assert_state legs would
  [[ "$(row_of legs)" == *"start candidate local together on the release commit the commit step makes, then tag only when every one is green"* ]] ||
    fail "the legs row does not say what would start: $(row_of legs)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/after.one" ] || fail "a dry run ran after:"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "a dry run asked the CI query: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

# devbin_after -- the after: lines THIS REPOSITORY's config declares, one a
# line, read by the reader the cut reads them with.
devbin_after() {
  (
    . "$DEVBIN_LIB_DIR/helpers" &&
      . "$DEVBIN_LIB_DIR/config" &&
      cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml" >/dev/null &&
      cfg_release_list after
  )
}

# publish_project -- $proj, a cut_project whose after: is the list THIS
# REPOSITORY's config declares, with the built-in formula enabled (issue 0227)
# and devbin's template as the project's own, committed and pushed; the tap at
# $TAP (formula_tap), whose pre-receive hook writes to tap.saw the v1.0.1 the
# release's remote held when the formula reached the tap, or `none`.
#
# THE TAP IS REACHED BY ITS DEFAULT URL, since devbin's after: line names no
# --tap and the project declares no formula.tap: homebrew-demo under the release
# repository's owner, t. publish_cut's git config sends that url to $TAP, and
# its ssh command is `false`, so a url the config does not catch fails rather
# than reaches a real tap.
publish_project() {
  local lines cfg
  lines="$(devbin_after)" || fail "devbin's own after: list could not be read"
  proj="$(ci_project "  after:
$(sed 's/^/    - /' <<<"$lines")")"
  cfg="$proj/bin/.devbin/config.yaml"
  awk '{ print } /^  release:$/ { r = 1 } r && /^    enabled: true$/ { print "  formula:"; print "    enabled: true"; r = 0 }' \
    "$cfg" >"$cfg.new" && mv "$cfg.new" "$cfg"
  grep -qx '  formula:' "$cfg" || fail "the fixture's config does not enable formula: $(cat "$cfg")"
  mkdir -p "$proj/packaging/homebrew"
  cp "$DEVBIN_HOME/packaging/homebrew/devbin.rb" "$proj/packaging/homebrew/demo.rb"
  git -C "$proj" add -A
  git -C "$proj" commit -qm "the formula"
  git -C "$proj" push -q origin main
  formula_tap
  printf '#!/bin/sh\nenv -u GIT_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_QUARANTINE_PATH \\\n  git --git-dir="%s" rev-parse -q --verify refs/tags/v1.0.1 >"%s/tap.saw" || echo none >"%s/tap.saw"\n' \
    "$DEVBIN_TEST_TMPDIR/remote.git" "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR" >"$TAP/hooks/pre-receive"
  chmod +x "$TAP/hooks/pre-receive"
  printf '[user]\n\tname = t\n\temail = t@t\n[url "%s"]\n\tinsteadOf = ssh://git@github.com/t/homebrew-demo.git\n' \
    "$TAP" >"$DEVBIN_TEST_TMPDIR/tap.gitconfig"
}

# publish_cut <proj> -- the cut of v1.0.1 with --yes, the tap's url sent to
# $TAP and ssh refused (publish_project), with nobody at a terminal.
publish_cut() {
  GIT_CONFIG_GLOBAL="$DEVBIN_TEST_TMPDIR/tap.gitconfig" GIT_SSH_COMMAND=false \
    release_in "$1" v1.0.1 --yes
}

# publish_cut_answered <proj> <answer> [--yes] -- the cut of v1.0.1 on a pty,
# the tap's url sent to $TAP and ssh refused (publish_project), <answer> typed
# at the first prompt (run_tty_answer): the confirm step's, unless --yes is
# given, which answers that step and leaves no prompt. A yes at that prompt is
# the yes for the formula's push the cut lists (issue 0227). Its output's
# carriage returns are dropped, so a row reads as it does off a pipe. Skipped
# where expect is not installed.
publish_cut_answered() {
  local w="$DEVBIN_TEST_TMPDIR/cut.sh"
  require_expect
  {
    printf '#!/bin/sh\n'
    printf 'cd %s || exit 2\n' "$1"
    printf 'GIT_CONFIG_GLOBAL=%s GIT_SSH_COMMAND=false PATH=%s:"$PATH" exec ./bin/devbin release v1.0.1 %s\n' \
      "$DEVBIN_TEST_TMPDIR/tap.gitconfig" "$DEVBIN_TEST_TMPDIR/stubs" "${3:-}"
  } >"$w"
  chmod +x "$w"
  run run_tty_answer "$2" "$w"
  output="${output//$'\r'/}"
}

# AT-1.2
@test "devbin's own after: line publishes the formula past the push step's push, on the yes given at the cut's prompt: the tap gets the release just cut, the after row done (ST0009 AC-1.2, 0227)" {
  local lines tag
  lines="$(devbin_after)"
  grep -qxF 'bin/devbin formula publish' <<<"$lines" ||
    fail "devbin's config declares no after: running bin/devbin formula publish: '$lines'"
  publish_project
  publish_cut_answered "$proj" y
  assert_success
  assert_state confirm done
  assert_state push done
  assert_state after done
  assert_output_contains "formula: confirmed at the cut of v1.0.1, so it is pushed without a second question"
  tag="$(git -C "$proj" rev-parse refs/tags/v1.0.1)"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/tap.saw")" = "$tag" ] ||
    fail "the release's remote did not hold v1.0.1 when the formula reached the tap: $(cat "$DEVBIN_TEST_TMPDIR/tap.saw")"
  run git -C "$TAP" show main:Formula/demo.rb
  assert_success
  assert_output_contains 'tag:      "v1.0.1",'
  assert_output_contains "revision: \"$(release_sha "$proj")\""
}

# AT-1.2
@test "a formula publish that fails at the after step is reported, not swallowed: the after row FAILED, exit 1, the release standing (ST0009 AC-1.2)" {
  publish_project
  printf '#!/bin/sh\necho "tap refused by hook" >&2\nexit 1\n' >"$TAP/hooks/pre-receive"
  publish_cut_answered "$proj" y
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state after FAILED
  assert_output_contains "cannot push the formula to the tap"
  assert_output_contains "after: bin/devbin formula publish failed"
  assert_output_contains "published"
  assert_released "$proj"
  [ "$(git -C "$TAP" rev-list --count main)" = 1 ] || fail "the tap's main moved"
}

# AT-1.2, AT-2.1
@test "a cut under --yes publishes the formula with no second question, with nobody at a terminal: --yes is the yes for the tap, and the after: commands run under it (0227, ST0011 WP02)" {
  local tag
  publish_project
  run publish_cut "$proj"
  assert_success
  assert_state confirm done
  assert_state after done
  assert_output_contains "then, under this yes, after: bin/devbin formula publish"
  assert_output_contains "formula: confirmed at the cut of v1.0.1, so it is pushed without a second question"
  tag="$(git -C "$proj" rev-parse refs/tags/v1.0.1)"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/tap.saw")" = "$tag" ] ||
    fail "the release's remote did not hold v1.0.1 when the formula reached the tap: $(cat "$DEVBIN_TEST_TMPDIR/tap.saw")"
  run git -C "$TAP" show main:Formula/demo.rb
  assert_success
  assert_output_contains 'tag:      "v1.0.1",'
}

# AT-1.2, AT-2.1
@test "with nobody at a terminal and no --yes, a cut stops at its confirm step, whose question names the after: commands that would run under the yes, and the tap is untouched (0227, ST0011 WP02)" {
  publish_project
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_output_contains "  - then, under this yes, after: bin/devbin formula publish"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
  [ "$(git -C "$TAP" rev-list --count main)" = 1 ] || fail "the tap's main moved"
}

# AT-2.4
@test "a re-run of a released version, HEAD moved on, asks ci.query nothing: the tag exists, so the legs are not re-run (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  printf 'later\n' >"$proj/later.txt"
  git -C "$proj" add later.txt
  git -C "$proj" commit -qm "later work"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs "not re-run"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "a re-run of a released version asked ci.query: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "a zero ci.wait still gives a query that takes a moment its answer (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 7')"
  printf 'sleep 2\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
}

@test "release_seconds reads s, m and h, and refuses anything else by name" {
  run bash -c '. "$1/helpers" && . "$1/release.notes" && . "$1/release.steps" && release_seconds 7s && release_seconds 2m && release_seconds 1h && release_seconds 08s' _ "$DEVBIN_LIB_DIR"
  assert_success
  [ "$output" = "$(printf '7\n120\n3600\n8')" ] || fail "got: $output"
  run bash -c '. "$1/helpers" && . "$1/release.notes" && . "$1/release.steps" && release_seconds 20' _ "$DEVBIN_LIB_DIR"
  assert_failure
  assert_output_contains '"20" is not a duration'
}

# ============================================================================
# WP-06: every call to another machine from the push step on is bounded, and a bound
# kills the whole call, not one level of it
# ============================================================================

# git_hangs_on <verb> <marker> -- a git on PATH that sleeps on <verb> once
# <marker> exists, and is the real git otherwise.
git_hangs_on() {
  local real
  real="$(command -v git)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/git" <<SH
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "$1" ] && [ -f "$2" ]; then sleep 60; fi
done
exec "$real" "\$@"
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/git"
}

# release_scratch_count <dir> -- how many of the release code's scratch
# directories (devbin-release.*, devbin-wait.*, devbin-ci.*) stand in <dir> now.
release_scratch_count() {
  find "$1" -maxdepth 1 \( -name 'devbin-release.*' -o -name 'devbin-wait.*' -o -name 'devbin-ci.*' \) | wc -l | tr -d ' '
}

@test "a hung query's whole process group is killed: its own sleep is gone, and no scratch is left (ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 1s)")"
  # A TMPDIR OF ITS OWN. Counted in the machine's shared TMPDIR, this arm failed
  # "1 before, 2 after" whenever another run of the suite made release scratch
  # at the same moment: measured with two runs of this file overlapping. The
  # query lists that directory while it hangs, and that is the control: the
  # scratch really lands where this arm counts, so a clean count after it is the
  # release code tidying up, not the arm watching a directory nothing writes to.
  local scratch="$DEVBIN_TEST_TMPDIR/release-tmp"
  mkdir -p "$scratch"
  printf 'ls "$TMPDIR" >"%s/during.ls"\nsleep 60 &\necho $! >"%s/sleep.pid"\nwait\n' \
    "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  local before after start=$SECONDS
  # EVERY SCRATCH NAME THE RELEASE CODE MAKES, not only the query's own: since
  # RELEASE_WAIT_DIR the verdict's scratch is the wait's (devbin-wait.*), so an
  # arm counting devbin-ci.* alone stayed green with the wait's rm deleted.
  before="$(release_scratch_count "$scratch")"
  TMPDIR="$scratch" DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung query held the run for $((SECONDS - start))s"
  ! kill -0 "$(cat "$DEVBIN_TEST_TMPDIR/sleep.pid")" 2>/dev/null || fail "the query's own sleep outlived the bound"
  grep -q -E '^devbin-(wait|ci)\.' "$DEVBIN_TEST_TMPDIR/during.ls" ||
    fail "the hung query saw no release scratch in its TMPDIR, so the count below watches a directory the release code does not write to: $(cat "$DEVBIN_TEST_TMPDIR/during.ls" 2>&1)"
  after="$(release_scratch_count "$scratch")"
  [ "$after" -le "$before" ] || fail "a scratch directory was left: $before before, $after after"
}

@test "a gh release create that hangs fails the object step within its bound, naming it" {
  proj="$(cut_project)"
  : >"$DEVBIN_TEST_TMPDIR/gh.hang.create"
  local start=$SECONDS
  DEVBIN_RELEASE_CALL_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state object FAILED
  assert_output_contains "did not finish within 2s"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung create held the cut for $((SECONDS - start))s"
}

@test "a remote that stops answering after the push fails the push step's read-back within its bound, as a read that could not tell (0194)" {
  proj="$(cut_project)"
  git_hangs_on ls-remote "$DEVBIN_TEST_TMPDIR/pushed"
  printf '#!/bin/sh\ntouch "%s/pushed"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/.git/hooks/pre-push"
  chmod +x "$proj/.git/hooks/pre-push"
  local start=$SECONDS
  DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 DEVBIN_RELEASE_READBACK_SECONDS=4 DEVBIN_RELEASE_POLL_SECONDS=1 \
    run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state push FAILED
  assert_output_contains "could not read back whether origin holds the release after the push, in the 4s a read-back waits"
  assert_output_contains "did not answer within"
  refute_output_contains "origin does not hold the release"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung read-back held the cut for $((SECONDS - start))s"
}

@test "a remote that answers with a head this checkout does not hold fails the push step at once, as a read that could not tell (0194)" {
  proj="$(cut_project)"
  # After taking the push, the remote moves main on to a commit made there.
  printf '#!/bin/sh\nexport GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t\nc=$(git commit-tree "refs/heads/main^{tree}" -p refs/heads/main -m later) && git update-ref refs/heads/main "$c"\nexit 0\n' \
    >"$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  chmod +x "$DEVBIN_TEST_TMPDIR/remote.git/hooks/post-receive"
  local start=$SECONDS
  run release_in "$proj" v1.0.1 --yes
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" log -1 --format=%s refs/heads/main)" = later ] ||
    fail "the remote's hook made no commit, so its head is one this checkout holds and this arm tests nothing"
  assert_stopped_at push
  assert_output_contains "could not read back whether origin holds the release after the push: origin's main is at"
  refute_output_contains "a read-back waits"
  refute_output_contains "origin does not hold the release"
  # Not waited through: no ask can clear it, since the read-back never fetches.
  [ $((SECONDS - start)) -lt 60 ] || fail "the push step waited $((SECONDS - start))s on a remote that answered"
}

# git_fails_once_on <word> <marker> -- a git on PATH that, once <marker>
# exists, fails the first call carrying <word> as an unreachable remote does,
# at once, and runs every other call as the real git.
git_fails_once_on() {
  local real
  real="$(command -v git)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/git" <<SH
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "$1" ] && [ -f "$2" ] && [ ! -f "$2.failed" ]; then
    : >"$2.failed"
    echo "fatal: unable to access the remote: Operation timed out" >&2
    exit 128
  fi
done
exec "$real" "\$@"
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/git"
}

@test "a remote that does not answer once after the push and then holds the release passes the push step, and nothing is pushed twice (0194)" {
  proj="$(cut_project)"
  git_fails_once_on ls-remote "$DEVBIN_TEST_TMPDIR/pushed"
  # Every ref each push sends, one line per ref, so a second push of either
  # half is counted.
  printf '#!/bin/sh\ntouch "%s/pushed"\nwhile read -r l _ r _; do echo "$r" >>"%s/pushes"; done\n' \
    "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR" >"$proj/.git/hooks/pre-push"
  chmod +x "$proj/.git/hooks/pre-push"
  DEVBIN_RELEASE_POLL_SECONDS=1 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state push done
  [ -f "$DEVBIN_TEST_TMPDIR/pushed.failed" ] || fail "no read-back failed, so this arm waited through nothing"
  [ "$(sort "$DEVBIN_TEST_TMPDIR/pushes")" = $'refs/heads/main\nrefs/tags/v1.0.1' ] ||
    fail "the pushes were not one of each: $(cat "$DEVBIN_TEST_TMPDIR/pushes")"
}

@test "a push that hangs fails the push step within its bound, naming it" {
  proj="$(cut_project)"
  git_hangs_on push "$DEVBIN_TEST_TMPDIR/hang.push"
  : >"$DEVBIN_TEST_TMPDIR/hang.push"
  local start=$SECONDS
  DEVBIN_RELEASE_CALL_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state push FAILED
  assert_output_contains "did not finish within 2s"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung push held the cut for $((SECONDS - start))s"
}

# AT-6.1
@test "under object: ci the dry run's one look is bounded too" {
  proj="$(ci_project '  object: ci
  object_wait: 20m')"
  : >"$DEVBIN_TEST_TMPDIR/gh.hang.view"
  local start=$SECONDS
  DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state object would
  [ $((SECONDS - start)) -lt 30 ] || fail "the dry run's look held it for $((SECONDS - start))s"
}

# AT-6.1
@test "under object: ci a cut-off look at the object is UNREADABLE, never read as absent" {
  proj="$(ci_project '  object: ci
  object_wait: 1s')"
  : >"$DEVBIN_TEST_TMPDIR/gh.hang.view"
  local start=$SECONDS
  DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state object FAILED
  assert_output_contains "UNREADABLE, did not answer within"
  [ $((SECONDS - start)) -lt 60 ] || fail "the hung look held the cut for $((SECONDS - start))s"
}

# ============================================================================
# 0149: THE VERDICT IS THE CANDIDATE'S RUNS, NOT EVERY RUN ON THE COMMIT
# ============================================================================

# ci_runs_query -- a ci.query shaped as one consumer's tools/ci-state: it refuses any
# argument but the sha, usage at exit 2, as that consumer's and Utilz's do; it reads CI
# runs from ci.runs, one `<headBranch> <status> <id>` a line; and it ranks them
# as that consumer's does, failure over a run still going over success, so one run
# still going makes the answer pending. It counts only runs whose headBranch is
# the ref in DEVBIN_RELEASE_TAG, `none` until one exists, and none on a
# candidate ref the remote does not hold, since nothing runs on a ref nobody
# has pushed; with no ref there, or when ci.shaonly exists, it reads every run
# on the sha, as a query that does not read the ref does. status is success,
# failure or in_progress.
ci_runs_query() {
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
shaonly="$DEVBIN_TEST_TMPDIR/ci.shaonly"
runs="$DEVBIN_TEST_TMPDIR/ci.runs"
remote="$DEVBIN_TEST_TMPDIR/remote.git"
SH
  cat >>"$DEVBIN_TEST_TMPDIR/ciq.sh" <<'SH'
if [ "$#" -ne 1 ]; then
  echo "usage: tools/ci-state <sha>" >&2
  exit 2
fi
tag="${DEVBIN_RELEASE_TAG:-}"
[ ! -e "$shaonly" ] || tag=""
case "$tag" in
  candidate/*)
    if ! git --git-dir="$remote" rev-parse -q --verify "refs/heads/$tag" >/dev/null; then
      printf 'none\tno run for %s yet\n' "$tag"
      exit 0
    fi
    ;;
esac
rank=-1 best="" id="" r=0 v=""
while read -r ref st rid; do
  [ -n "$ref" ] || continue
  [ -z "$tag" ] || [ "$ref" = "$tag" ] || continue
  case "$st" in
    failure) r=3 v=failed ;;
    in_progress) r=2 v=pending ;;
    success) r=0 v=green ;;
    *) r=4 v=unknown ;;
  esac
  if [ "$r" -gt "$rank" ]; then rank="$r" best="$v" id="$rid"; fi
done <"$runs"
if [ -z "$best" ]; then printf 'none\tno run for %s yet\n' "${tag:-the sha}"; else printf '%s\trun %s\n' "$best" "$id"; fi
exit 0
SH
}

@test "the query is asked about the sha alone with the candidate ref in its environment, and a green branch run with no candidate run yet is no verdict, never green (0149, ST0011 WP02b)" {
  local rel
  # One consumer's v0.4.0: the branch push's run (36155136723, headBranch main, macOS
  # skipped) was green before the tag's run (36156500018) existed, and the
  # sha-only query ended the release green on it.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'main success 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"candidate (none: no run for candidate/v1.0.1 yet)"* ]] ||
    fail "the legs row does not name the candidate's last answer: $(row_of legs)"
  refute_output_contains "run 36155136723"
  rel="$(git -C "$proj" rev-parse HEAD)"
  [ "$(sort -u "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$rel tag=candidate/v1.0.1" ] ||
    fail "the query was not asked about the sha alone with the candidate ref in its environment: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the candidate's own green run is the verdict: the legs row names what ci.query answered for the candidate ref, and its run (0149, ST0011 WP02b)" {
  # The branch run comes LAST, so a query that read every run on the sha would
  # name it: the run named is the candidate's only because its ref was read.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'candidate/v1.0.1 success 36156500018\nmain failure 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 36156500018"* ]] || fail "the legs row does not name the candidate's run: $(row_of legs)"
  [ "$(sort -u "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$(release_sha "$proj") tag=candidate/v1.0.1" ] ||
    fail "the query was not asked with the candidate ref in its environment: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the candidate's run still in progress answers pending, and a failed branch run does not stand in for it (0149, ST0011 WP02b)" {
  # The branch run failed: a query reading every run on the sha answers
  # failed, and one reading the candidate's runs answers pending.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'main failure 36155136723\ncandidate/v1.0.1 success 36156500001\ncandidate/v1.0.1 in_progress 36156500018\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  [[ "$(row_of legs)" == *"candidate (pending: run 36156500018)"* ]] ||
    fail "the legs row does not name the run still going: $(row_of legs)"
  refute_output_contains "is red"
}

@test "a query that refuses any argument but the sha, as real ones do, runs green through the candidate leg (0149, ST0011 WP02b)" {
  # One consumer's and Utilz's tools/ci-state exit 2 on a second argument; handed the
  # ref as one, every cut of theirs would fail. The stub's arity check is
  # theirs; this is the shape the carrier was chosen for.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'candidate/v1.0.1 success 36156500018\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  refute_output_contains "usage: tools/ci-state"
}

@test "a {version} tag template with no v names the candidate candidate/1.0.1, as Utilz's tag does (0149, ST0011 WP02b)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  tag: \"{version}\"")"
  ci_runs_query
  printf 'main success 22\ncandidate/1.0.1 success 23\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" 1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 23"* ]] || fail "the legs row does not name the candidate's run: $(row_of legs)"
  grep -q -- " tag=candidate/1.0.1\$" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not run with the candidate ref candidate/1.0.1: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "LIMIT, NOT FIXED: a query that does not read DEVBIN_RELEASE_TAG still reads the branch run as the release's verdict, which is why projects must update theirs (0149, ST0011 WP02b)" {
  # Documents what 0149 cannot do. The core puts the candidate's ref in the
  # query's environment, but a query that does not read it reads every run on
  # the sha as before, so the branch push's green is read at the candidate's
  # start, before its push, and stands for it. Nothing in the core can tell
  # such a query from one that keeps the contract; the 0.1.8 release notes ask
  # one consumer and Utilz to read DEVBIN_RELEASE_TAG in their tools/ci-state.
  # The row says what the query answered, not what CI did.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  : >"$DEVBIN_TEST_TMPDIR/ci.shaonly"
  printf 'main success 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [[ "$(row_of legs)" == *"candidate: run 36155136723"* ]] || fail "the legs row does not name the branch run: $(row_of legs)"
  grep -qx -- "$(release_sha "$proj") tag=candidate/v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the core did not set the candidate ref, so this arm would not show the query's limit: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the candidate ref reaches ci.query alone: no gate or after: command sees DEVBIN_RELEASE_TAG, one exported from outside included (0149, ST0011 WP02b)" {
  # The core sets it for the query's run only, and unsets one the cut
  # inherited, so a gate exercising the query never reads a stale ref.
  printf 'printf "%%s\\n" "${DEVBIN_RELEASE_TAG-<unset>}" >>"%s/after.tag"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/rec.sh"
  proj="$(ci_project "$(ci_query_decl 0s)
  after:
    - bash $DEVBIN_TEST_TMPDIR/rec.sh")"
  gate_does 'printf "%s\n" "${DEVBIN_RELEASE_TAG-<unset>}" >>"'"$DEVBIN_TEST_TMPDIR"'/gate.tag"'
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'green\trun 5')"
  DEVBIN_RELEASE_TAG=v0.0.9 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state legs done
  [ "$(cat "$DEVBIN_TEST_TMPDIR/gate.tag")" = "<unset>" ] || fail "the gate saw $(cat "$DEVBIN_TEST_TMPDIR/gate.tag")"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/after.tag")" = "<unset>" ] || fail "after: saw $(cat "$DEVBIN_TEST_TMPDIR/after.tag")"
  [ "$(sort -u "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$(release_sha "$proj") tag=candidate/v1.0.1" ] ||
    fail "the query was not run with this cut's candidate ref: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "release_scratch refuses a TMPDIR inside the project however the root is spelled, a leading // included, and writes nothing (0162)" {
  # Its own copy of the physical step kept a leading //, so a root entered that
  # way was not a prefix of the TMPDIR beneath it, and the scratch landed inside.
  local proj="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$proj/tmp"
  run env TMPDIR="$proj/tmp" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash -c '. "$DEVBIN_LIB/helpers" && . "$DEVBIN_LIB/release.notes" && . "$DEVBIN_LIB/release.steps" && release_scratch "/$1"' _ "$proj"
  assert_failure
  assert_output_contains "is inside the project"
  [ -z "$(ls -A "$proj/tmp")" ] || fail "a scratch directory was made inside the project: $(ls -A "$proj/tmp")"
}

# with_formula <proj> [<name>] -- <proj> enables the formula built-in, naming
# the formula <name> when one is given, committed and pushed so the cut's
# pre-flight reads a clean tree level with its remote.
with_formula() {
  local cfg="$1/bin/.devbin/config.yaml"
  awk -v name="${2:-}" '
    { print }
    /^commands:$/ { print "  formula:"; print "    enabled: true" }
    END { if (name != "") { print "formula:"; print "  name: " name } }
  ' "$cfg" >"$cfg.new" && mv "$cfg.new" "$cfg" || fail "the fixture's formula block failed"
  git -C "$1" commit -qam "formula" && git -C "$1" push -q origin main || fail "the fixture's formula commit failed"
}

@test "a cut that publishes a formula ends on the note back to brew, naming it and the release commit; its dry run does not (0228)" {
  proj="$(cut_project)"
  with_formula "$proj"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  refute_output_contains "the switch rests at brew"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  commit="$(git -C "$proj" rev-parse 'refs/tags/v1.0.1^{commit}')"
  # The report's last line: only the seal's verdict trailer follows it, which is
  # the LAST `verdict:` line, since the gates' own sealed run prints one mid-way.
  report_last="$(awk '/^verdict: / { before = last; next } NF { last = $0 } END { print before }' <<<"$output")"
  [ "$report_last" = "release: NOTE: the switch rests at brew -- once the tap has v1.0.1: brew upgrade demo, then demo use brew, and demo --version reads demo 1.0.1 (brew, ${commit:0:12})" ] ||
    fail "the report's last line is: $report_last"
}

@test "the note back to brew names the formula by formula.name where one is declared (0228)" {
  proj="$(cut_project)"
  with_formula "$proj" demo-tool
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "brew upgrade demo-tool, then demo-tool use brew, and demo-tool --version reads demo-tool 1.0.1 (brew, "
}

@test "a cut with no formula prints no note back to brew (0228)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  refute_output_contains "the switch rests at brew"
}

@test "a project's own formula handler gets the note back to brew too (0228)" {
  proj="$(cut_project)"
  create_test_command "$proj" formula "$(printf '#!/usr/bin/env bash\nexit 0\n')" >/dev/null
  git -C "$proj" add -A && git -C "$proj" commit -qm "own formula" && git -C "$proj" push -q origin main ||
    fail "the fixture's handler commit failed"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_output_contains "release: NOTE: the switch rests at brew -- once the tap has v1.0.1: brew upgrade demo, then demo use brew"
}

# ============================================================================
# THE CANDIDATE'S TRIGGER, AND A GATE ACTIVE ON NO LEG (ST0011 WP-02c)
# ============================================================================

# fires_workflow <proj> <branches> [<paths>] -- <proj>'s workflow, its push
# trigger taking <branches> and, given <paths>, filtered on them
# (write_tests_workflow), committed and pushed.
fires_workflow() {
  write_tests_workflow "$1" "$2" "${3:-}"
  git -C "$1" add -A
  git -C "$1" commit -qm "the workflow on $2${3:+, paths $3}"
  git -C "$1" push -q origin main
}

# AT-3.15
@test "the cut's pre-flight and release check ask ci-state --fires whether a push of the candidate's branch starts the workflow, with the release commit's files, under the built-in query: one that fires passes, one that does not is refused naming the reader's reason and the ways out, and a query of the project's own is not asked (ST0011 WP-02c)" {
  # No ci.query declared: the built-in reads the candidate, the cut's default.
  proj="$(cut_project "  gates:
    - probe
  ci:
    wait: 10m")"
  fires_workflow "$proj" "main, 'candidate/**'"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state pre-flight done
  run release_in "$proj" check
  assert_success
  assert_output_contains "release: a push of candidate/v1.0.0 at"
  assert_output_contains "starts release.ci.workflow"
  # A paths: filter the release commit's own files meet, VERSION among the
  # stamp's: the files are passed and read, so it fires. One they all miss
  # starts no run, so the files decide it, not the branches alone.
  fires_workflow "$proj" "main, 'candidate/**'" "VERSION"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state pre-flight done
  fires_workflow "$proj" "main, 'candidate/**'" "'src/**'"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  [[ "$(row_of pre-flight)" == *"a push of candidate/v1.0.1 at "*"starts no run the cut could read"* ]] ||
    fail "pre-flight passed a candidate whose paths: filter the release commit's files all miss: $(row_of pre-flight)"
  # A trigger the candidate's branch never starts.
  fires_workflow "$proj" "main"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  [[ "$(row_of pre-flight)" == *"a push of candidate/v1.0.1 at "*"starts no run the cut could read: ci-state --fires answers quiet"* ]] ||
    fail "pre-flight does not refuse a candidate whose push starts no run, with the reader's word: $(row_of pre-flight)"
  [[ "$(row_of pre-flight)" == *"declare release.ci.query: - to cut with no candidate"* ]] ||
    fail "the refusal does not name the opt-out: $(row_of pre-flight)"
  run release_in "$proj" check
  assert_failure
  assert_output_contains "ci-state --fires answers quiet"
  # A query of the project's own reads its own trigger: neither asks it.
  ci_query_decl 10s >/dev/null
  perl -0pi -e "s{\n  ci:\n    wait: 10m\n}{\n  ci:\n    query: $DEVBIN_TEST_TMPDIR/ciq\n    wait: 10m\n}" "$proj/bin/.devbin/config.yaml"
  grep -qF "query: $DEVBIN_TEST_TMPDIR/ciq" "$proj/bin/.devbin/config.yaml" || fail "the fixture's query was not declared"
  git -C "$proj" commit -qam "a query of the project's own"
  git -C "$proj" push -q origin main
  ci_answers "$(printf 'none\tno run yet')"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state pre-flight done
  run release_in "$proj" check
  assert_success
  assert_output_contains "trigger not asked: release.ci.query is '$DEVBIN_TEST_TMPDIR/ciq', a query of the project's own"
}

# A guard of the suite, not a red-to-green arm, so no unit's filter picks it: at
# the base it is red for another reason, since validation there refuses ci.wait
# beside no ci.query. What it holds: read with its stderr, the list of what a
# release owns carried notes.run's warning to ci-state --fires as a file, and
# --fires refuses a path holding //, which the warning's URL does, so the cut
# was refused for a line that names no file; release check, which reads stdout
# alone, passed.
@test "the pre-flight reads the paths a release owns from stdout alone: a notes.run that writes a line to stderr as it lists them passes nothing of it to the trigger check, so the cut and release check agree" {
  proj="$(cut_project "  gates:
    - probe
  notes:
    kind: command
    run: bin/notes
  ci:
    wait: 10m")"
  # notes.run answers what a dry run and release check ask; listing the paths,
  # it also warns on stderr, as a command with a deprecated flag would.
  cat >"$proj/bin/notes" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'open\n' ;;
  paths)
    printf 'notes: a deprecated flag, see https://example.com/notes\n' >&2
    printf 'CHANGELOG.md\n'
    ;;
  body) printf -- '- second\n' ;;
  views | views-check) printf 'none\n' ;;
  date) printf 'CHANGELOG.md\n' ;;
esac
STUB
  chmod +x "$proj/bin/notes"
  git -C "$proj" add -A
  git -C "$proj" commit -qm "notes.run"
  git -C "$proj" push -q origin main
  # A paths: filter the stamp's own files meet: only the files decide it.
  fires_workflow "$proj" "main, 'candidate/**'" "VERSION"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state pre-flight done
  run release_in "$proj" check
  assert_success
  assert_output_contains "starts release.ci.workflow"
}

@test "a notes.run that cannot list the paths a release owns stops the cut at pre-flight once, naming the list, and the trigger is not asked without it (ST0011 WP-02c)" {
  proj="$(cut_project "  gates:
    - probe
  notes:
    kind: command
    run: bin/notes
  ci:
    wait: 10m")"
  cat >"$proj/bin/notes" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'open\n' ;;
  paths)
    printf 'notes: the paths cannot be listed here\n' >&2
    exit 1
    ;;
  body) printf -- '- second\n' ;;
  views | views-check) printf 'none\n' ;;
  date) printf 'CHANGELOG.md\n' ;;
esac
STUB
  chmod +x "$proj/bin/notes"
  git -C "$proj" add -A
  git -C "$proj" commit -qm "notes.run"
  git -C "$proj" push -q origin main
  # A paths: filter, which only the files decide: asked with none, the reader
  # could answer only unknown, and its ways out would fix nothing here.
  fires_workflow "$proj" "main, 'candidate/**'" "VERSION"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  [[ "$(row_of pre-flight)" == *"the paths this release owns cannot be listed (above)"* ]] ||
    fail "the pre-flight row does not name the list it could not read: $(row_of pre-flight)"
  [[ "$(row_of pre-flight)" != *"ci-state --fires"* ]] ||
    fail "the trigger was asked without the list: $(row_of pre-flight)"
}

# AT-6.3
@test "pre-flight refuses a gate in all whose option its platforms: hold back on every leg the cut will run, naming the gate, the option and its platforms, and a host absent at pre-flight as not counted; a reached host on a platform the option names covers it (ST0011 WP-02c, AC-6.3)" {
  legs_env
  proj="$(cut_project "  gates:
    - test all
  legs:
    - far")"
  perl -0pi -e 's/\ncommands:\n  release:\n    enabled: true\n/\ncommands:\n  release:\n    enabled: true\n  test:\n    options:\n      app:\n        run: "true"\n        platforms:\n          - macos\n/' \
    "$proj/bin/.devbin/config.yaml"
  grep -q '^      app:$' "$proj/bin/.devbin/config.yaml" || fail "the fixture's option was not declared"
  git -C "$proj" commit -qam "an option that runs on macos alone"
  git -C "$proj" push -q origin main
  export UNAME_STUB_OS=Linux
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at pre-flight
  [[ "$(row_of pre-flight)" == *"the gate test all (release.gates) runs its option app only on macos, and no leg this cut runs is one: this host is linux; absent at pre-flight, and not counted: far"* ]] ||
    fail "pre-flight does not refuse the gate active on no leg: $(row_of pre-flight)"
  # near, a host whose own uname says Darwin, covers the option.
  mkdir -p "$HOSTS/near/.bin"
  printf '#!/bin/sh\necho Darwin\n' >"$HOSTS/near/.bin/uname"
  chmod +x "$HOSTS/near/.bin/uname"
  perl -pi -e 's/^    - far$/    - near/' "$proj/bin/.devbin/config.yaml"
  grep -q '^    - near$' "$proj/bin/.devbin/config.yaml" || fail "the fixture's leg was not renamed"
  git -C "$proj" commit -qam "a leg on macos"
  git -C "$proj" push -q origin main
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state pre-flight done
}

# A guard of the suite, not one of a unit's red-to-green arms: the line it holds
# reached each place before it was written, so it holds that the line keeps
# reaching them as ci-state words it.
@test "a red candidate's failed line, its run and the jobs that failed, reaches the loop's line, the stop's row and the RELEASE seal verbatim" {
  local want out
  want='run 42 (failure; failed jobs: test-linux, test-macos)'
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')" "$(printf 'failed\t%s' "$want")"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at legs
  grep -qF "candidate failed: $want" <<<"$output" || fail "the loop's line does not carry the failed line whole: $output"
  [[ "$(row_of legs)" == *"candidate is red: $want"* ]] || fail "the legs row does not carry the failed line whole: $(row_of legs)"
  out="$(readlink -f "$proj/tmp/release/LATEST_RELEASE.out")" && [ -f "$out" ] || fail "the cut left no RELEASE seal under tmp/release/"
  grep -qF "s $want" <<<"$(grep -F 'leg: candidate failed ' "$out")" ||
    fail "the RELEASE seal's candidate line does not carry the failed line whole: $(grep -F 'leg:' "$out" || echo '(none)')"
}
