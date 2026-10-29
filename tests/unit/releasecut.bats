#!/usr/bin/env bats
# releasecut.bats - a cut, the steps from resolve to ci, with --dry-run and --yes (ST0007
# WP-04 to WP-06)
#
# Resolve, pre-flight, stamp, commit, gates, confirm, tag, push, object, after
# and ci. Each step reads its postcondition first, so a re-run of the same
# target continues; each failure is a non-zero exit naming the step, and
# --dry-run runs the gates and prints each other step as what it would do.

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

# assert_stopped_at_confirm -- with no terminal and no --yes the run stopped at
# the confirm step with exit 1, its row saying nobody was there to ask. Exit 1 since issue
# 0130 (2 is the dispatcher's), so the ROW is what tells this from a person
# declining, or from any other step failing, and every such check asserts it.
assert_stopped_at_confirm() {
  [ "$status" -eq 1 ] || fail "want exit 1 at the confirmation, got $status:
$output"
  assert_state confirm FAILED
  assert_output_contains "nobody to ask"
}

# assert_reached_confirm -- the steps from resolve to gates passed, and the run stopped at the
# confirmation (assert_stopped_at_confirm), tagging and pushing nothing.
assert_reached_confirm() {
  assert_stopped_at_confirm
  assert_state gates "${1:-done}"
  assert_output_contains "This run tagged nothing and pushed nothing"
}

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

# ============================================================================
# THE WHOLE RUN, AND A RE-RUN
# ============================================================================

# AT-5.3
@test "with no terminal and no --yes, a cut stamps, commits and gates, then stops at the confirm step with exit 1 (AC-5.3, 0130)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state resolve done
  assert_state pre-flight done
  assert_state stamp done
  assert_state commit done
  assert_state gates done
  [ "$(git -C "$proj" log -1 --format=%s)" = "release: v1.0.1" ]
  [ "$(git -C "$proj" show HEAD:VERSION)" = 1.0.1 ]
  local note
  note="$(git -C "$proj" show HEAD:CHANGELOG.md)" && grep -qF "## [1.0.1] - $(date +%F)" <<<"$note" ||
    fail "the release commit's note is not dated today"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree is not clean"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
}

@test "--patch bumps the newest matching tag, and the summary names the version to resume with" {
  proj="$(cut_project)"
  run release_in "$proj" --patch
  assert_reached_confirm
  assert_output_contains "1.0.1 from --patch, tag v1.0.1, new"
  assert_output_contains "resume with: bin/devbin release v1.0.1"
}

# AT-5.1
@test "a re-run continues: stamp and commit already, the gates run again, no second commit" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  head="$(git -C "$proj" rev-parse HEAD)"
  rm -f "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state stamp already
  assert_state commit already
  assert_state gates done
  gate_ran || fail "the gates did not run again: they are never already, leaving no postcondition the repository can show"
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "the re-run made another commit"
  [ "$(release_commits "$proj")" -eq 1 ]
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
  run release_in "$proj" v1.0.1
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
  run release_in "$proj" v1.0.1
  assert_stopped_at stamp
  assert_output_contains "the derived: command 'false' failed"
  if gate_ran; then fail "a gate ran after the stamp step failed"; fi
}

# AT-4.1
@test "the commit step fails, named: the commit is refused by a hook, and no release commit is made" {
  proj="$(cut_project)"
  printf '#!/bin/sh\necho hook says no >&2\nexit 1\n' >"$proj/.git/hooks/pre-commit"
  chmod +x "$proj/.git/hooks/pre-commit"
  run release_in "$proj" v1.0.1
  assert_stopped_at commit
  assert_output_contains "git commit failed"
  [ "$(release_commits "$proj")" -eq 0 ]
  if gate_ran; then fail "a gate ran after the commit step failed"; fi
}

# AT-4.1
@test "the gates step fails, named: a gate exits non-zero" {
  proj="$(cut_project)"
  gate_does 'exit 4'
  run release_in "$proj" v1.0.1
  assert_stopped_at gates
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state gates done
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
  run release_in "$proj" v1.0.1
  assert_stopped_at gates
  assert_output_contains "a gate changed the tree: README.md"
}

# AT-4.2
@test "a gate that creates a path fails the gates step, naming it" {
  proj="$(cut_project)"
  gate_does ': >made-by-gate.txt'
  run release_in "$proj" v1.0.1
  assert_stopped_at gates
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
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
  run release_in "$proj" v1.0.1
  assert_stopped_at commit
  rm "$proj/.git/hooks/pre-commit"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  git -C "$proj" push -q origin main
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  git -C "$proj" fetch -q origin
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state pre-flight done
  assert_state commit already
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

# AT-4.6
@test "--dry-run writes nothing, reports every write through the object step as would, and names what it could not reach" {
  proj="$(cut_project)"
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a dry run wrote something:
$output"
  assert_output_contains "DRY RUN"
  assert_state stamp would
  assert_state commit would
  assert_state gates done
  assert_state confirm would
  assert_state tag would
  assert_state push would
  assert_state object would
  assert_output_contains "predicts the gates"
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

# AT-4.6
@test "a dry run's verdict says when the cut would not stop to ask: given --yes, or with nothing left (0181)" {
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
  # The cut's own the confirm row says what the dry run's said, of the commit it made.
  sha="$(release_sha "$proj")"
  [[ "$(row_of confirm)" == *" --yes given: tag v1.0.1 at ${sha:0:12};"* ]] ||
    fail "the cut's confirm row does not say --yes answers it:
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
  gate_does 'exit 4'
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at gates
  refute_output_contains "no step failed"
  [[ "$(last_line)" == "release: stopped at the gates step. "* ]] || fail "the last line is not the stop:
$output"
  assert_output_contains " -- cut with: bin/devbin release v1.0.1"
}

# AT-4.6
@test "a dry run's header names the cut as the next command, and a stopped cut's still names the resume (0181)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_output_line "release: v1.0.1 (DRY RUN: no commit, tag, push or release object; the gates run) -- cut with: bin/devbin release v1.0.1"
  refute_output_contains "resume with"
  # THE CONTROL: a cut that stops at the confirm step is resumed, and says so.
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_output_line "release: v1.0.1 -- resume with: bin/devbin release v1.0.1"
  refute_output_contains "cut with"
}

# AT-4.6
@test "with the commit step at would, a dry run's confirm and tag rows name the commit the commit step makes, never HEAD (0181)" {
  proj="$(cut_project)"
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit would
  [[ "$(row_of gates)" == *"on HEAD ${head:0:12} in place"* ]] || fail "the gates row does not name HEAD, which the gates ran on:
$output"
  for n in 6 7; do
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
  # THE CONTROL FOR THE ARM ABOVE: a cut stopped at the confirm step has made the
  # release commit, at HEAD, and origin lacks it.
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  rel="$(git -C "$proj" rev-parse HEAD)"
  # The cut's own question names the commit its commit step made, never the HEAD it
  # started on.
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
@test "with the commit step at would, a dry run's ci row names the commit the commit step makes; once the release commit exists, its sha, HEAD moved on or not (0181)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  head="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [[ "$(row_of ci)" == *"ask ci.query about v1.0.1 (the release commit the commit step makes) for up to 0s (ci.wait)" ]] ||
    fail "the ci row does not name the commit the commit step makes:
$output"
  [[ "$(row_of ci)" != *"${head:0:12}"* ]] || fail "the ci row names HEAD's sha:
$output"
  # THE CONTROL: a cut stopped at the confirm step has made the release commit, at HEAD.
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  rel="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state commit already
  [[ "$(row_of ci)" == *"ask ci.query about v1.0.1 (${rel:0:12}) for up to 0s (ci.wait)" ]] ||
    fail "the ci row does not name the release commit's sha:
$output"
  # Released, and HEAD moved on: a dry run resumes the tag, and the ci row names
  # the tagged commit, never HEAD.
  run release_in "$proj" v1.0.1 --yes
  assert_success
  [ "$(release_sha "$proj")" = "$rel" ] || fail "v1.0.1 does not tag the release commit $rel"
  printf 'later\n' >"$proj/later.txt"
  git -C "$proj" add later.txt
  git -C "$proj" commit -qm "later work"
  later="$(git -C "$proj" rev-parse HEAD)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [[ "$(row_of ci)" == *"ask ci.query about v1.0.1 (${rel:0:12}) for up to 0s (ci.wait)" ]] ||
    fail "the ci row does not name the tagged commit once HEAD has moved on:
$output"
  [[ "$(row_of ci)" != *"${later:0:12}"* ]] || fail "the ci row names HEAD's sha:
$output"
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

# AT-4.6
@test "a remote that moves past HEAD while a dry run's gates run is refused at the confirm step, as pre-flight refuses one found there (0181)" {
  proj="$(cut_project)"
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  later="$(git -C "$other" rev-parse HEAD)"
  # Pre-flight reads origin at HEAD. The gate then pushes the later commit and
  # fetches it here, so the confirm step reads a remote that has moved past HEAD, which
  # the commit the commit step would make on HEAD could not fast-forward.
  gate_does "git -C '$other' push -q origin main && git -C '$proj' fetch -q origin"
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at confirm
  assert_output_contains "origin's main (${later:0:12}) has moved past HEAD"
  refute_output_contains "no step failed"
}

# ============================================================================
# ONE SCRATCH ROOT, ONE TRAP (WP-04's lift)
# ============================================================================

@test "while the gates run, everything the cut put in TMPDIR is under one root, and a kill leaves nothing" {
  proj="$(cut_project)"
  local tmp="$DEVBIN_TEST_TMPDIR/scratchtmp"
  mkdir -p "$tmp"
  gate_does "ls -A '$tmp' >'$DEVBIN_TEST_TMPDIR/during'; kill -TERM \$PPID"
  TMPDIR="$tmp" run release_in "$proj" v1.0.1
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state stamp done
  [ "$(git -C "$proj" show HEAD:gen.txt)" = generated ] || fail "gen.txt is not in the release commit"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] || fail "the tree is not clean"
}

@test "a path a derived: command writes and does not report is refused at the stamp step, naming it" {
  proj="$(derived_project 'echo generated >gen.txt')"
  run release_in "$proj" v1.0.1
  assert_stopped_at stamp
  assert_output_contains "dirty outside what this release owns: gen.txt"
}

@test "with derived: declared, dirt outside the known owned set is checked at the stamp step and refused there" {
  proj="$(derived_project 'true')"
  echo more >>"$proj/README.md"
  run release_in "$proj" v1.0.1
  assert_stopped_at stamp
  assert_output_contains "dirty outside what this release owns: README.md"
  [ "$(release_commits "$proj")" -eq 0 ]
  if gate_ran; then fail "a gate ran after the stamp step refused"; fi
}

# ============================================================================
# THE POST-GATE RE-READ SEES A REWRITE OF A FILE THAT WAS ALREADY DIRTY
# ============================================================================

# AT-4.2
@test "a gate that rewrites an already-dirty file fails the gates step, naming it (dry run, where the tree can be dirty)" {
  proj="$(cut_project)"
  printf '1.0.1\n' >"$proj/VERSION"
  gate_does 'echo 9.9.9 >VERSION'
  run release_in "$proj" v1.0.1 --dry-run
  assert_stopped_at gates
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
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  head="$(git -C "$proj" rev-parse HEAD)"
  gen="$(cat "$proj/gen.txt")"
  sleep 1
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  assert_state stamp already
  assert_state commit already
  [ "$(release_commits "$proj")" -eq 1 ] || fail "a second release commit: $(git -C "$proj" log --format=%s)"
  [ "$(git -C "$proj" rev-parse HEAD)" = "$head" ] || fail "HEAD moved"
  [ "$(cat "$proj/gen.txt")" = "$gen" ] || fail "derived: ran again on the release commit"
}

@test "a remote moved past the release commit, then a re-run whose derived: rewrites, is not left diverged" {
  proj="$(derived_project 'date +%s%N >gen.txt; echo gen.txt')"
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
  git -C "$proj" push -q origin main
  other="$(other_clone)"
  echo later >"$other/later.txt"
  git -C "$other" add later.txt
  git -C "$other" commit -qm later
  git -C "$other" push -q origin main
  git -C "$proj" fetch -q origin
  sleep 1
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
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
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
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
  assert_state ci skipped
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
  assert_state stamp already
  assert_state commit already
  assert_state gates "not re-run"
  assert_state confirm FAILED
  assert_output_contains "push commit tag to origin"
  assert_output_contains "make the release object"
  refute_output_contains "tag v1.0.1 at"
  [ "$(remote_refs)" = "$before" ] || fail "a run with nobody to ask pushed something"
  run release_in "$proj" v1.0.1 --yes
  assert_success
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
  assert_state gates "not re-run"
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
  run release_in "$proj" v1.0.1
  assert_reached_confirm
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
  assert_stopped_at gates
  assert_output_contains "a gate moved HEAD from"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a tag was made"; fi
}

# AT-4.1
@test "a remote that stops answering after pre-flight fails the confirm step, naming it, and nothing is tagged or pushed" {
  # Pre-flight refuses an unreadable remote; the confirm step re-reads each one after the
  # gates, and a remote can stop answering in between. The gate moves the bare
  # remote aside: it is outside the project, so the gates step's checks pass.
  proj="$(cut_project)"
  gate_does "mv '$DEVBIN_TEST_TMPDIR/remote.git' '$DEVBIN_TEST_TMPDIR/remote.gone'"
  run release_in "$proj" v1.0.1 --yes
  assert_stopped_at confirm
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
  run release_in "$proj" v1.0.1
  assert_stopped_at_confirm
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
# WP-06: object ci with object_wait, after:, and the ci step's CI verdict
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

# AT-4.1, AT-6.1
@test "under object: ci a green CI verdict does not stand in for the object: none appears, the object row FAILED, exit 1 (AC-6.1)" {
  proj="$(ci_project "  object: ci
  object_wait: 1s
$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state object FAILED
  assert_output_contains "no release object for v1.0.1"
  assert_released "$proj"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "the object step asked the CI query: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
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

# AT-6.2
@test "a green verdict on the release commit is the ci row done, naming the run, exit 0, asked about the tagged commit's sha" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  assert_output_contains "run 7"
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not asked about the release commit alone, with its tag in the environment: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

# AT-4.1, AT-6.2
@test "a red verdict exits 1, names the run and the fail-forward remedy, and leaves the tag and the release untouched (AC-6.2)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'failed\trun 42')"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
  assert_output_contains "run 42"
  assert_output_contains "ci.query answers failed for v1.0.1 ("
  assert_output_contains "cut the next patch"
  assert_output_contains "the tag and the release stand"
  assert_released "$proj"
  [ "$(gh_calls 'release create')" -eq 1 ] || fail "want the one release object"
  [ "$(gh_calls 'release delete')" -eq 0 ] || fail "the release was deleted"
  [ "$(gh_calls 'release edit')" -eq 0 ] || fail "the release was edited"
}

@test "pending is waited on: pending, then green, is done within ci.wait" {
  proj="$(ci_project "$(ci_query_decl 3s)")"
  # One ask for each answer the fake gives, the last of them green.
  local -a answers=("$(printf 'pending\trun 9')" "$(printf 'green\trun 9')")
  ci_answers "${answers[@]}"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  [ "$(wc -l <"$DEVBIN_TEST_TMPDIR/ci.calls")" -eq "${#answers[@]}" ] || fail "want ${#answers[@]} asks: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

# AT-6.2
@test "no verdict within ci.wait is FAILED, exit 1, naming the last answer -- never a quiet 0" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'none\tno run yet')"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
  assert_output_contains "no verdict within"
  assert_output_contains "no run yet"
  assert_released "$proj"
}

# AT-6.2
@test "an answer that is not a verdict is unknown and FAILED, naming what was said" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "success"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1 for a non-verdict, got $status: $output"
  assert_state ci FAILED
  assert_output_contains '"success", which is not a verdict'
  assert_released "$proj"
}

# AT-6.2
@test "a query that fails is unknown and FAILED, naming what it said on stderr" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  printf 'echo "gh: HTTP 502" >&2; exit 4\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1 for a failing query, got $status: $output"
  assert_state ci FAILED
  assert_output_contains "HTTP 502"
  assert_released "$proj"
}

# AT-6.2
@test "a query that hangs is cut off, FAILED as unknown, and the cut ends within seconds, not at the query's leisure" {
  proj="$(ci_project "$(ci_query_decl 1s)")"
  printf 'sleep 60\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  local start=$SECONDS
  DEVBIN_RELEASE_ASK_FLOOR_SECONDS=2 run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
  # 2s, the floor this arm sets, and not 15s, the default it would otherwise
  # wait out (0191).
  assert_output_contains "did not answer within 2s"
  # The cut-off answer is `unknown`, the verdict's cutoff state -- not `pending`,
  # which would be re-asked until the deadline.
  assert_output_contains "no verdict from ci.query for v1.0.1"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung query held the cut for $((SECONDS - start))s"
}

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

@test "a failing after: command leaves the release published, still reads the verdict, and exits 1 saying so" {
  proj="$(ci_project "  after:
    - false
    - touch $DEVBIN_TEST_TMPDIR/after.two
$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state after FAILED
  assert_state ci done
  [ -e "$DEVBIN_TEST_TMPDIR/after.two" ] || fail "one failing after: stopped the next"
  assert_output_contains "after: false failed"
  assert_output_contains "published"
  assert_released "$proj"
}

@test "a dry run with after: and ci.query declared runs neither, and says what it would do" {
  proj="$(ci_project "  after:
    - touch $DEVBIN_TEST_TMPDIR/after.one
$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state after would
  assert_state ci would
  [ ! -e "$DEVBIN_TEST_TMPDIR/after.one" ] || fail "a dry run ran after:"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "a dry run asked the CI query"
  assert_output_contains "ask ci.query about v1.0.1 ("
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

# AT-1.2
@test "a cut under --yes on a terminal publishes no formula: --yes is no yes for the tap, so publish has nobody to ask (0227)" {
  publish_project
  publish_cut_answered "$proj" y --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state after FAILED
  assert_output_contains "nobody to ask: no terminal, so nothing was published"
  refute_output_contains "confirmed at the cut"
  assert_released "$proj"
  [ "$(git -C "$TAP" rev-list --count main)" = 1 ] || fail "the tap's main moved"
}

# AT-1.2
@test "a cut with nobody at a terminal publishes no formula: publish names the tap, the after row FAILED, exit 1, the release standing (0227)" {
  publish_project
  run publish_cut "$proj"
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state after FAILED
  assert_output_contains "is ready to push to the tap at ssh://git@github.com/t/homebrew-demo.git"
  assert_output_contains "nobody to ask: no terminal, so nothing was published"
  assert_released "$proj"
  [ "$(git -C "$TAP" rev-list --count main)" = 1 ] || fail "the tap's main moved"
}

# AT-6.2
@test "a re-run after HEAD has moved on asks ci.query about the tagged commit, not HEAD" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  printf 'later\n' >"$proj/later.txt"
  git -C "$proj" add later.txt
  git -C "$proj" commit -qm "later work"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "asked about $(cat "$DEVBIN_TEST_TMPDIR/ci.calls"), want the release commit $(release_sha "$proj") with tag=v1.0.1, HEAD is $(git -C "$proj" rev-parse HEAD)"
}

@test "a zero ci.wait still gives a query that takes a moment its answer" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'green\trun 7')"
  printf 'sleep 2\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
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

@test "a hung query's whole process group is killed: its own sleep is gone, and no scratch is left" {
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
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
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
# 0149: THE CI VERDICT IS THE TAG'S RUNS, NOT EVERY RUN ON THE COMMIT
# ============================================================================

# ci_runs_query -- a ci.query shaped as one consumer's tools/ci-state: it refuses any
# argument but the sha, usage at exit 2, as that consumer's and Utilz's do; it reads CI
# runs from ci.runs, one `<headBranch> <status> <id>` a line; and it ranks them
# as that consumer's does, failure over a run still going over success, so one run
# still going makes the answer pending. It counts only runs whose headBranch is
# the tag in DEVBIN_RELEASE_TAG, `none` until one exists; with no tag there,
# or when ci.shaonly exists, it reads every run on the sha, as a query that
# does not read the tag does. status is success, failure or in_progress.
ci_runs_query() {
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
shaonly="$DEVBIN_TEST_TMPDIR/ci.shaonly"
runs="$DEVBIN_TEST_TMPDIR/ci.runs"
SH
  cat >>"$DEVBIN_TEST_TMPDIR/ciq.sh" <<'SH'
if [ "$#" -ne 1 ]; then
  echo "usage: tools/ci-state <sha>" >&2
  exit 2
fi
tag="${DEVBIN_RELEASE_TAG:-}"
[ ! -e "$shaonly" ] || tag=""
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

@test "the query is asked about the sha alone with the tag in its environment, and a green branch run with no tag run yet is no verdict, never green (0149)" {
  # One consumer's v0.4.0: the branch push's run (36155136723, headBranch main, macOS
  # skipped) was green before the tag's run (36156500018) existed, and the
  # sha-only query ended the release green on it.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'main success 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
  assert_output_contains "ci.query gave no verdict within 0s (ci.wait) for v1.0.1 ($(release_sha "$proj" | cut -c1-12))"
  assert_output_contains "last: none, no run for v1.0.1 yet"
  refute_output_contains "run 36155136723"
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not asked about the sha with the tag in its environment: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the tag's own green run is the verdict: the ci row names what ci.query answered for the tag, and its run (0149)" {
  # The branch run comes LAST, so a query that read every run on the sha would
  # name it: the run named is the tag's only because the tag was read (with
  # the tag's run last, the arm passed with the tag dropped).
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'v1.0.1 success 36156500018\nmain failure 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  assert_output_contains "ci.query answers green for v1.0.1 ($(release_sha "$proj" | cut -c1-12)): run 36156500018"
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not asked with the tag in its environment: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the tag's run still in progress answers pending, and a failed branch run does not stand in for it (0149)" {
  # The branch run failed: a query reading every run on the sha answers
  # failed, and one reading the tag's runs answers pending.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'main failure 36155136723\nv1.0.1 success 36156500001\nv1.0.1 in_progress 36156500018\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_state ci FAILED
  assert_output_contains "last: pending, run 36156500018"
}

@test "a query that refuses any argument but the sha, as real ones do, runs green through the ci step (0149)" {
  # One consumer's and Utilz's tools/ci-state exit 2 on a second argument; handed the
  # tag as one, every cut of theirs would fail at the ci step after the tag, the
  # push and the object. The stub's arity check is theirs; this is the shape the
  # carrier was chosen for.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  printf 'v1.0.1 success 36156500018\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  refute_output_contains "usage: tools/ci-state"
}

@test "a {version} tag template with no v hands that tag, as Utilz's does (0149)" {
  proj="$(ci_project "$(ci_query_decl 0s)
  tag: \"{version}\"")"
  ci_runs_query
  printf 'main success 22\n1.0.1 success 23\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" 1.0.1 --yes
  assert_success
  assert_state ci done
  assert_output_contains "ci.query answers green for 1.0.1 ("
  assert_output_contains "): run 23"
  grep -q -- " tag=1.0.1\$" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not run with the tag 1.0.1: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "LIMIT, NOT FIXED: a query that does not read DEVBIN_RELEASE_TAG still reads the branch run as the release's verdict, which is why projects must update theirs (0149)" {
  # Documents what 0149 cannot do. The core puts the tag in the query's
  # environment, but a query that does not read it reads every run on the sha
  # as before, so the branch push's green ends the release green before the
  # tag's run exists. Nothing in the core can tell such a query from one that
  # keeps the contract; the 0.1.8 release notes ask one consumer and Utilz to read
  # DEVBIN_RELEASE_TAG in their tools/ci-state. The row says what the query
  # answered, not what CI did.
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_runs_query
  : >"$DEVBIN_TEST_TMPDIR/ci.shaonly"
  printf 'main success 36155136723\n' >"$DEVBIN_TEST_TMPDIR/ci.runs"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  assert_output_contains "ci.query answers green for v1.0.1 ($(release_sha "$proj" | cut -c1-12)): run 36155136723"
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the core did not set the tag, so this arm would not show the query's limit: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
}

@test "the tag reaches ci.query alone: no gate or after: command sees it, one exported from outside included (0149)" {
  # The core sets it for the query's run only, and unsets one the cut
  # inherited, so a gate exercising the query never reads a stale tag.
  printf 'printf "%%s\\n" "${DEVBIN_RELEASE_TAG-<unset>}" >>"%s/after.tag"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/rec.sh"
  proj="$(ci_project "$(ci_query_decl 0s)
  after:
    - bash $DEVBIN_TEST_TMPDIR/rec.sh")"
  gate_does 'printf "%s\n" "${DEVBIN_RELEASE_TAG-<unset>}" >>"'"$DEVBIN_TEST_TMPDIR"'/gate.tag"'
  ci_answers "$(printf 'green\trun 5')"
  DEVBIN_RELEASE_TAG=v0.0.9 run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci done
  [ "$(cat "$DEVBIN_TEST_TMPDIR/gate.tag")" = "<unset>" ] || fail "the gate saw $(cat "$DEVBIN_TEST_TMPDIR/gate.tag")"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/after.tag")" = "<unset>" ] || fail "after: saw $(cat "$DEVBIN_TEST_TMPDIR/after.tag")"
  grep -qx -- "$(release_sha "$proj") tag=v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not run with this cut's tag: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
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

# ============================================================================
# 0223: CI GREEN ON THE BASE COMMIT BEFORE THE CUT (release.ci.base)
# ============================================================================

# base_project [<ci-lines>] -- ci_project with the fixture's ci.query declared
# at a wait of 0s and ci.base on, and <ci-lines> under ci: after them.
base_project() {
  ci_project "$(ci_query_decl 0s)
    base: true${1:+
$1}"
}

# base_asks -- the lines the fixture's ci.query recorded, or nothing.
base_asks() { cat "$DEVBIN_TEST_TMPDIR/ci.calls" 2>/dev/null || true; }

# assert_base_refused <proj> <want>... -- the cut of v1.0.1 stopped at
# pre-flight, its output carrying each <want>, after asking the query once; no
# gate ran and nothing was written but the cut's own log under the ignored tmp/.
assert_base_refused() {
  local proj="$1" before want
  shift
  before="$(fingerprint "$proj" --allow-gh-reads)"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  for want in "$@"; do assert_output_contains "$want"; done
  [ "$(base_asks | wc -l)" -eq 1 ] || fail "want one ask of the query: $(base_asks)"
  if gate_ran; then fail "a gate ran after pre-flight refused the base"; fi
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj" --allow-gh-reads)" = "$before" ] || fail "a refused pre-flight wrote something"
}

@test "with ci.base, pre-flight asks ci.query about HEAD, the base, with no tag, and a green answer passes it, naming the run (0223)" {
  proj="$(base_project)"
  base="$(git -C "$proj" rev-parse HEAD)"
  ci_answers "$(printf 'green\trun 11')"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state pre-flight done
  [[ "$(row_of pre-flight)" == *"CI is green on the base commit ${base:0:12}: run 11"* ]] ||
    fail "the pre-flight row does not name the base's green run: $(row_of pre-flight)"
  [ "$(base_asks)" = "$base tag=<unset>" ] || fail "want one ask about the base with no tag: $(base_asks)"
}

@test "with ci.base, a red run on the base refuses the cut at pre-flight, naming the run, and nothing is written (0223)" {
  proj="$(base_project)"
  ci_answers "$(printf 'failed\trun 12')"
  assert_base_refused "$proj" "ci.query answers failed for the base commit $(git -C "$proj" rev-parse --short=12 HEAD): run 12" "push main, wait for CI green on it, then cut"
}

@test "with ci.base, no run on the base refuses the cut at pre-flight, naming what the query said (0223)" {
  proj="$(base_project)"
  ci_answers "$(printf 'none\tno run on that sha')"
  assert_base_refused "$proj" "ci.query answers none for the base commit" "no run on that sha" "push main, wait for CI green on it, then cut"
}

@test "with ci.base, a run still going on the base refuses the cut, saying to wait and cut again, and is asked once, never waited for (0223)" {
  # ci.wait is the ci step's wait for the tag's verdict; pre-flight asks once.
  proj="$(ci_project "$(ci_query_decl 3s)
    base: true")"
  ci_answers "$(printf 'pending\trun 13')" "$(printf 'green\trun 13')"
  assert_base_refused "$proj" "CI is still running on the base commit $(git -C "$proj" rev-parse --short=12 HEAD): run 13" \
    "wait for it to finish, then cut again"
  # Still going is not a failure, and the refusal never reads as one.
  refute_output_contains "ci.query answers pending"
  refute_output_contains "answers failed"
}

@test "with ci.base, a query that fails or answers what is not a verdict refuses the cut, naming what it said (0223)" {
  proj="$(base_project)"
  printf 'echo "gh: HTTP 502" >&2; exit 4\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  assert_base_refused "$proj" "no verdict from ci.query for the base commit" "HTTP 502" "push main, wait for CI green on it, then cut"
  rm -f "$DEVBIN_TEST_TMPDIR/ciq.sh" "$DEVBIN_TEST_TMPDIR/ci.calls"
  ci_answers "success"
  assert_base_refused "$proj" "no verdict from ci.query for the base commit" '"success", which is not a verdict' "push main, wait for CI green on it, then cut"
}

@test "with ci.base, a cut resumed on its release commit asks about the commit before it, which the release commit changes only in what the release owns (0223)" {
  proj="$(base_project)"
  base="$(git -C "$proj" rev-parse HEAD)"
  ci_answers "$(printf 'green\trun 14')"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  rel="$(git -C "$proj" rev-parse HEAD)"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  assert_state commit already
  [ "$(base_asks)" = "$base tag=<unset>" ] || fail "want one ask about the release commit's parent: $(base_asks)"
  [[ "$(row_of pre-flight)" == *"CI is green on the base commit ${base:0:12}, which the release commit ${rel:0:12} changes only in what this release owns: run 14"* ]] ||
    fail "the pre-flight row does not say the green base stands for the release commit: $(row_of pre-flight)"
}

@test "with ci.base, a release commit that changes a path outside what the release owns is refused, so the base's green does not stand for it (0223)" {
  proj="$(base_project)"
  ci_answers "$(printf 'green\trun 15')"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  printf 'x\n' >"$proj/extra.txt"
  git -C "$proj" add extra.txt
  git -C "$proj" commit -q --amend --no-edit
  rel="$(git -C "$proj" rev-parse --short=12 HEAD)"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls" "$DEVBIN_TEST_TMPDIR/gate.calls"
  run release_in "$proj" v1.0.1
  assert_stopped_at pre-flight
  assert_output_contains "the release commit $rel changes extra.txt, outside what this release owns, so CI on the commit before it does not stand for it"
  [ -z "$(base_asks)" ] || fail "the query was asked about a base that cannot stand for the release commit: $(base_asks)"
  if gate_ran; then fail "a gate ran after pre-flight refused"; fi
}

@test "without ci.base, pre-flight never asks ci.query, which the ci step alone reads (0223)" {
  proj="$(ci_project "$(ci_query_decl 0s)")"
  ci_answers "$(printf 'failed\trun 16')"
  run release_in "$proj" v1.0.1
  assert_reached_confirm
  [ -z "$(base_asks)" ] || fail "pre-flight asked the query without ci.base: $(base_asks)"
}

@test "with ci.base, a cut resumed after its tag exists does not ask about the base again: the tag's commit is the release (0223)" {
  proj="$(base_project)"
  ci_answers "$(printf 'green\trun 17')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state resolve done
  [ "$(base_asks)" = "$(release_sha "$proj") tag=v1.0.1" ] || fail "want the ci step's one ask, about the tag: $(base_asks)"
}

@test "with ci.tag off, the ci step is skipped, naming it, and the query is asked only about the base; release status says the same (0223)" {
  proj="$(base_project "    tag: false")"
  ci_answers "$(printf 'green\trun 18')"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state ci skipped
  [[ "$(row_of ci)" == *"ci.tag is off: the cut does not wait for v1.0.1's CI run"* ]] || fail "the ci row does not name ci.tag: $(row_of ci)"
  [ "$(base_asks | wc -l)" -eq 1 ] || fail "want the base's one ask and no ask about the tag: $(base_asks)"
  [[ "$(base_asks)" == *"tag=<unset>" ]] || fail "the one ask was not the base's: $(base_asks)"
  run release_in "$proj" status v1.0.1
  assert_state ci skipped
  assert_output_contains "ci.tag is off"
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
  # The report's last line: only the seal's verdict trailer follows it.
  report_last="$(awk '/^verdict: / { exit } NF { last = $0 } END { print last }' <<<"$output")"
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
