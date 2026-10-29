#!/usr/bin/env bats
#
# The release core's notes providers (ST0007 WP-02): lib/release.notes,
# and the `release notes` and `release check` verbs that drive them.
#
# THE FIRST HALF IS devbin's OWN SHAPE, `notes.kind: releases` -- one release
# note and the views generated from it -- and its arms are the ones that tested
# bin/.devbin/cmd/release until that handler moved into the core. They run
# through `bin/devbin release` now, on a fixture that enables it.
#
# THE DRIFT THIS PREVENTS. A release is conventionally described in three places
# -- a per-release note, a CHANGELOG, and an index -- all about the same events.
# Hand-written they agree on the day and drift afterwards, silently, because
# nothing fails when a changelog omits a release. So `RELEASES/<version>.md` is
# the only home and the other two are rendered from it.
#
# The tests that matter are therefore the ones asserting the views CANNOT
# disagree with their source: adding a note puts the release in both views, and
# `release check` goes red the moment a committed view stops matching.
#
set -euo pipefail

load "../lib/test_helper"

setup() {
  devbin_setup
  PROJ="$(mkproj proj <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  notes:
    kind: releases
YAML
  )"
  mkdir -p "$PROJ/RELEASES"
  # For sha256_of below. Six assertions here used to spell the tool by hand,
  # which is issue 0052's portability defect -- `shasum` is the name a minimal
  # Linux image does not carry -- reproduced in test code, where it takes a
  # GATE down rather than a product.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # The providers themselves, for the arms that ask them directly.
  # shellcheck source=lib/release.notes
  . "$DEVBIN_LIB_DIR/release.notes"
}

teardown() {
  devbin_teardown
}

# tree_sum <dir> -- every file's checksum and path under a directory, sorted: a
# fingerprint that changes if anything under it is written.
tree_sum() {
  (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort)
}

# workflow_body_awk -- the awk program .github/workflows/release.yml runs to cut
# a release note's body, read out of the workflow itself rather than copied, so
# the arm holding notes_body to it cannot drift from the workflow it describes.
workflow_body_awk() {
  sed -n "s/^ *awk '\\(BEGIN { body = 0 }[^']*\\)'.*/\\1/p" "$DEVBIN_HOME/.github/workflows/release.yml"
}

# mknote <version> [date] [headline] [status]
#
# Also writes $PROJ/VERSION, and that is not a convenience. `release check` now
# requires a note for the version the project CLAIMS to be, so a fixture whose
# VERSION named nothing would make every check arm below go red for a reason it
# does not name -- and the arms that assert FAILURE would have passed for the
# wrong reason and kept passing after the thing they test was broken.
#
# `status` defaults to released; an unreleased note is written WITHOUT a date,
# because carrying one is refused.
mknote() {
  local v="$1" date="${2:-2026-01-01}" headline="${3:-headline for $1}" status="${4:-released}"
  {
    printf 'version: %s\n' "$v"
    if [ "$status" = released ]; then printf 'date: %s\n' "$date"; fi
    printf 'headline: %s\n' "$headline"
    printf 'status: %s\n' "$status"
  } > "$PROJ/RELEASES/$v.md"
  printf '%s\n' "$v" > "$PROJ/VERSION"
  cat >> "$PROJ/RELEASES/$v.md" <<NOTE

# devbin $v

Narrative that belongs to the note and must NOT reach the changelog.

## Added

- something added in $v

## Fixed

- something fixed in $v
NOTE
}

# ---- --help after the verb (issue 0067) ------------------------------------
#
# The command read only its first argument, so `notes --help` RAN notes and
# `check --help` ran the check. Asserted on the views' BYTES, never on output:
# `notes` prints the same `wrote` line whether or not it was asked for help, and
# the loss 0067 names is a hand edit the regeneration discards.
#
# These arms stay beside releasecore.bats's argument-loop arms, which parse the
# same words, because only here do notes exist, so only here would a wrongly
# parsed verb reach a real write: notes --help and notes --dry-run against a
# hand edit, check --help against stale views (ST0007 WP-02).

@test "notes --help prints usage and writes neither view" {
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  printf 'MARKER-hand-edit\n' >>"$PROJ/CHANGELOG.md"
  local log index
  log="$(sha256_of "$PROJ/CHANGELOG.md")"
  index="$(sha256_of "$PROJ/RELEASES.md")"
  run_in_project "$PROJ" release notes --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: bin/devbin release"* ]]
  [[ "$output" != *"wrote"* ]]
  [ "$log" = "$(sha256_of "$PROJ/CHANGELOG.md")" ]
  [ "$index" = "$(sha256_of "$PROJ/RELEASES.md")" ]
}

@test "check --help prints usage instead of running the check" {
  # The views are made STALE first, so a check that ran would exit 1 and say so.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  mknote 0.2.0
  run_in_project "$PROJ" release check --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: bin/devbin release"* ]]
  [[ "$output" != *"STALE"* ]]
}

@test "a verb given an argument it does not take refuses, and writes nothing" {
  # The other half of reading only the first argument: `notes --dry-run` would
  # have regenerated both views, which is the opposite of what it asks.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  printf 'MARKER-hand-edit\n' >>"$PROJ/CHANGELOG.md"
  local log
  log="$(sha256_of "$PROJ/CHANGELOG.md")"
  run_in_project "$PROJ" release notes --dry-run
  [ "$status" -ne 0 ]
  # THE REFUSAL LINE ALONE IS SEARCHED: refuse() prints usage first, and usage
  # itself carries [--dry-run], so a search of the whole output cannot fail
  # (ST0007 WP-02).
  local refusal
  refusal="$(printf '%s\n' "$output" | grep -F 'demo: release: ' || true)"
  [[ "$refusal" == *"--dry-run applies to a cut, not to release notes"* ]] || fail "the refusal line: $refusal"
  [ "$log" = "$(sha256_of "$PROJ/CHANGELOG.md")" ]
}

# AT-2.1
@test "notes refuses to generate a view of an empty RELEASES/" {
  # A generator that cannot find its source has FAILED; it has not discovered
  # that the source is empty. Without this it would render two well-formed
  # files saying there are no releases, over two correct ones.
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to generate a view of nothing"* ]]
}

# AT-2.1
@test "notes renders both views from the notes" {
  mknote 0.1.0 2026-08-29 "the first one"
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  [ -s "$PROJ/CHANGELOG.md" ]
  [ -s "$PROJ/RELEASES.md" ]
  grep -q '^## \[0.1.0\] - 2026-08-29$' "$PROJ/CHANGELOG.md"
  grep -q 'the first one' "$PROJ/RELEASES.md"
}

# AT-2.1
@test "the narrative stays in the note and does not reach the changelog" {
  # The changelog carries the Keep a Changelog sections and nothing else. A
  # generator that dumped the whole note would make the changelog a second copy
  # of the note, which is the duplication this design exists to prevent.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  grep -q 'something added in 0.1.0' "$PROJ/CHANGELOG.md"
  # NOT `! grep`: in bats a negated command fails the test only when it is the
  # last one (SC2314), so an assertion written that way stops asserting the
  # moment a line is added below it.
  if grep -q 'must NOT reach the changelog' "$PROJ/CHANGELOG.md"; then
    fail "the note's narrative reached the changelog"
  fi
}

# AT-2.1
@test "a new release note appears in BOTH views without either being edited" {
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  # THIS PRECONDITION COULD NEVER FAIL while it was written `! grep`: a negated
  # command that is not a bats test's last line does not fail the test (SC2314).
  if grep -q '0.2.0' "$PROJ/CHANGELOG.md"; then
    fail "0.2.0 is in the changelog before its note exists"
  fi

  mknote 0.2.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  grep -q '^## \[0.2.0\]' "$PROJ/CHANGELOG.md"
  grep -q '0.2.0' "$PROJ/RELEASES.md"
  # And the older one is still there -- a view that loses history is worse than
  # one that is merely stale.
  grep -q '^## \[0.1.0\]' "$PROJ/CHANGELOG.md"
}

# AT-2.1
@test "releases sort by version, not lexically -- 0.10.0 is newer than 0.9.0" {
  # Lexical sort puts 0.10.0 BELOW 0.9.0 and the error first appears at the
  # tenth release, by which time the changelog has been wrong for a while.
  mknote 0.9.0
  mknote 0.10.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  local first second
  first="$(grep -m1 -oE '^## \[[0-9.]+\]' "$PROJ/CHANGELOG.md")"
  second="$(grep -oE '^## \[[0-9.]+\]' "$PROJ/CHANGELOG.md" | sed -n '2p')"
  [ "$first" = "## [0.10.0]" ]
  [ "$second" = "## [0.9.0]" ]
}

# AT-2.1
@test "a section the note does not use is omitted, not printed empty" {
  # A heading with nothing under it reads as "nothing changed here" when it
  # means "the note did not use this section".
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  grep -q '^### Added$' "$PROJ/CHANGELOG.md"
  if grep -q '^### Security$' "$PROJ/CHANGELOG.md"; then
    fail "an unused section was printed empty"
  fi
}

# AT-2.1
@test "check passes when the views match their source" {
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  run_in_project "$PROJ" release check
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 of 2 generated view(s) current"* ]]
  [[ "$output" == *"the note for 0.1.0 is dated 2026-01-01"* ]]
}

# AT-2.1
@test "check FAILS when a view has drifted from its source" {
  # THE TRIPWIRE. Adding a release note and forgetting to regenerate is the
  # whole failure mode; this is what notices.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  mknote 0.2.0
  run_in_project "$PROJ" release check
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE"* ]]
}

# AT-2.1
@test "check FAILS when a view has been hand-edited" {
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  printf '\nhand-written line nobody generated\n' >> "$PROJ/CHANGELOG.md"
  run_in_project "$PROJ" release check
  [ "$status" -ne 0 ]
  [[ "$output" == *"CHANGELOG.md is STALE"* ]]
}

# AT-2.1
@test "check writes nothing -- it is a predicate, not a repair" {
  # A checker that silently fixed what it found would make the failing state
  # unobservable, and the next run would report clean having hidden a drift.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  mknote 0.2.0
  local before
  before="$(sha256_of "$PROJ/CHANGELOG.md")"
  run_in_project "$PROJ" release check
  [ "$status" -ne 0 ]
  [ "$before" = "$(sha256_of "$PROJ/CHANGELOG.md")" ]
}

# AT-2.1
@test "a run that refuses before rendering touches nothing" {
  # This pins the refusal of an empty RELEASES/, NOT the write. Named for what it
  # actually covers: an earlier version of this test removed every note and
  # claimed to prove the write, but the refusal comes first, so the renderer was
  # never reached and the assertion held against a direct redirect too. A test
  # whose name promises a guarantee it does not check is worse than no test.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  local before
  before="$(sha256_of "$PROJ/CHANGELOG.md")"

  rm -f "$PROJ/RELEASES/"*.md
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [ "$before" = "$(sha256_of "$PROJ/CHANGELOG.md")" ]
}

# AT-2.1
@test "a render that fails part way writes nothing, and both previous views stay byte-identical" {
  # The render has to START and then fail, or this proves only the refusal
  # above. `render > path` truncates the target before the renderer runs, so a
  # renderer failing halfway would leave the previous good file truncated or
  # empty -- issue 0002's shape, and a defect another generator was caught by
  # for real. The views are rendered in memory before anything is written,
  # which is what this holds; that the write is a rename is held further down.
  #
  # An unreadable note is the lever: it is listed as a note, so rendering
  # begins, and then its header cannot be read.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  local log index
  log="$(sha256_of "$PROJ/CHANGELOG.md")"
  index="$(sha256_of "$PROJ/RELEASES.md")"

  mknote 0.2.0
  chmod 000 "$PROJ/RELEASES/0.2.0.md"
  run_in_project "$PROJ" release notes
  chmod 644 "$PROJ/RELEASES/0.2.0.md"

  [ "$status" -ne 0 ]
  [ "$log" = "$(sha256_of "$PROJ/CHANGELOG.md")" ]
  [ "$index" = "$(sha256_of "$PROJ/RELEASES.md")" ]
  # And no temporary is left in the root: the changelog's render failed after
  # its temporary existed (ST0007 WP-02).
  run find "$PROJ" -maxdepth 1 \( -name 'CHANGELOG.md.*' -o -name 'RELEASES.md.*' \)
  assert_success
  assert_output ""
}

# AT-2.1
@test "every row of the generated index table is the same width" {
  mknote 0.1.0 2026-08-29 "short"
  mknote 0.2.0 2026-09-30 "a very much longer headline than the other one"
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  # THE CONTROL FIRST: the header, its separator and one row per note. A view
  # with no table passed the check below, because no rows are never ragged.
  local lines want
  local -a notes=("$PROJ"/RELEASES/*.md)
  want=$((2 + ${#notes[@]})) # a table's header and separator, then a row per note
  lines="$(grep -c '^|' "$PROJ/RELEASES.md" || true)"
  [ "$lines" -eq "$want" ] || fail "want $want table lines in RELEASES.md, got $lines"
  run awk '/^\|/ { w[length($0)] = 1 } END { for (k in w) print k }' "$PROJ/RELEASES.md"
  assert_success
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || fail "the table's lines are not all one width: $output"
}

# AT-2.1
@test "a note with NO status: is refused, and NO view is written" {
  # THE SWALLOWED REFUSAL, and this arm exists because it actually happened. The
  # generator this core replaced refused an absent status with `die` inside
  # `$( )`, which kills only its own subshell unless errexit reaches it, and this
  # exact fixture once printed the refusal TWICE while `notes` wrote both views
  # and exited 0. The provider now checks every refusal where it happens rather
  # than trusting errexit to carry it (lib/release.notes). ASSERTING THE VIEWS ARE
  # ABSENT is the half that catches it: the message was already being printed,
  # so an arm checking only the output would have passed throughout.
  mknote 0.1.0
  grep -v '^status: ' "$PROJ/RELEASES/0.1.0.md" > "$PROJ/n" && mv "$PROJ/n" "$PROJ/RELEASES/0.1.0.md"
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [[ "$output" == *"0.1.0.md has no"* ]]
  [ ! -e "$PROJ/CHANGELOG.md" ]
  [ ! -e "$PROJ/RELEASES.md" ]
}

# AT-2.1
@test "a status: that is neither released nor unreleased is refused" {
  mknote 0.1.0 2026-01-01 "h" bogus
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [[ "$output" == *"has status: bogus"* ]]
}

# AT-2.1
@test "an unreleased note renders Unreleased in both views, never a date" {
  mknote 0.2.0 "" "the open one" unreleased
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  grep -q '^## \[0.2.0\] - Unreleased$' "$PROJ/CHANGELOG.md"
  grep -q 'Unreleased' "$PROJ/RELEASES.md"
}

# AT-2.1
@test "an unreleased note carrying a date: is REFUSED, not ignored" {
  # An ignored date survives the flip to `released` and ships as a claim nobody
  # re-checked. Refusing is what stops the two states sharing one file shape.
  cat > "$PROJ/RELEASES/0.2.0.md" <<'NOTE'
version: 0.2.0
date: 2026-01-01
headline: open but dated
status: unreleased

## Added

- x
NOTE
  printf '0.2.0\n' > "$PROJ/VERSION"
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [[ "$output" == *"is unreleased but carries date"* ]]
}

# AT-2.1
@test "a released note with no date: is refused" {
  # The mirror: without this the views carry an empty date column, which reads
  # as a formatting quirk rather than a missing fact.
  cat > "$PROJ/RELEASES/0.1.0.md" <<'NOTE'
version: 0.1.0
headline: no date here
status: released

## Added

- x
NOTE
  printf '0.1.0\n' > "$PROJ/VERSION"
  run_in_project "$PROJ" release notes
  [ "$status" -ne 0 ]
  [[ "$output" == *"is released but carries no"* ]]
}

# AT-2.1
@test "check FAILS when VERSION names a version with no note" {
  # THE GAP THIS CLOSES. Once VERSION was bumped to 0.1.1 while RELEASES/
  # held only 0.1.0.md, and `release check` said `release views are current`
  # and exited 0. That was TRUE and NARROW -- it compares two views against the
  # notes, and they did agree. Nothing in the command had ever read VERSION, so
  # NO state of the version file could turn any of the arms above red.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  printf '0.1.1\n' > "$PROJ/VERSION"
  run_in_project "$PROJ" release check
  [ "$status" -ne 0 ]
  [[ "$output" == *"there is no RELEASES/0.1.1.md"* ]]
}

# AT-2.1
@test "check reports a missing note AND a stale view in ONE run" {
  # Both halves warn and return rather than dying, so one run names everything
  # wrong. A checker that stops at the first fault makes the second cost a whole
  # extra cycle to find.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  [ "$status" -eq 0 ]
  printf 'hand-edited\n' >> "$PROJ/CHANGELOG.md"
  printf '0.1.1\n' > "$PROJ/VERSION"
  run_in_project "$PROJ" release check
  [ "$status" -ne 0 ]
  [[ "$output" == *"there is no RELEASES/0.1.1.md"* ]]
  [[ "$output" == *"CHANGELOG.md is STALE"* ]]
}

# AT-2.1
@test "THIS REPOSITORY's committed CHANGELOG and RELEASES.md match RELEASES/" {
  # The one test that looks at the real tree rather than a fixture. Everything
  # above proves the generator behaves; this proves somebody ran it -- through
  # devbin's own declaration, which is what a pushed tag's workflow runs too.
  run devbin_run "$DEVBIN_HOME" release check
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 of 2 generated view(s) current"* ]]
}

# AT-2.1
@test "devbin's release resolves to the core, and no project handler of devbin's shadows it" {
  # bin/.devbin/cmd/release was devbin's own notes generator. A project handler
  # shadows a builtin whole, so while it existed devbin's release was not
  # the core at all, and adopting the core meant deleting it.
  [ ! -e "$DEVBIN_HOME/bin/.devbin/cmd/release" ]
  # Provenance is read from `help --why`, not `help release`. This asserted the
  # generated page's "Resolves from:" line, which is the stub's -- and 0112 gave
  # release an authored page, which replaces the stub whole, taking the line
  # with it. --why states provenance for every command regardless of pages.
  run devbin_run "$DEVBIN_HOME" help --why
  assert_success
  local row
  row="$(grep -A1 '^  release ' <<<"$output")" && grep -q 'from: devbin lib/cmd/release' <<<"$row" ||
    fail "help --why does not say release resolves from devbin lib/cmd/release"
  run devbin_run "$DEVBIN_HOME" doctor
  # The positive control: doctor ran its shadow check, so the refutation below
  # is about that check's list and not about an empty or failed run.
  assert_output_contains "shadowing:"
  assert_output_contains "test shadows the built-in"
  refute_output_matches '(^|'$'\n'') +release shadows'
}

# ============================================================================
# THE PROVIDERS, ASKED DIRECTLY (lib/release.notes)
# ============================================================================

# AT-2.4
@test "notes_select refuses an unknown kind, notes.run beside releases or changelog, and command without notes.run" {
  run notes_select markdown "" demo
  assert_failure
  assert_output_contains "unknown notes.kind: markdown"
  run notes_select releases bin/notes demo
  assert_failure
  assert_output_contains "notes.run is read only under notes.kind: command"
  run notes_select changelog bin/notes demo
  assert_failure
  run notes_select command "" demo
  assert_failure
  assert_output_contains "needs notes.run"
  # Space alone splits into no words, and the verb would run as the command.
  # Declared-with-no-words is a different mistake from undeclared, and says so
  # in run_words's own words, naming the key (issue 0082).
  run notes_select command "   " demo
  assert_failure
  assert_output_contains "release.notes.run holds no words"
  run notes_select releases "" ""
  assert_failure
  assert_output_contains "no project name"
}

# AT-2.4
@test "a refused notes_select leaves nothing selected, so no verb answers for the provider chosen before it" {
  mknote 0.1.0
  notes_select releases "" demo
  run notes_state "$PROJ" 0.1.0
  assert_output "dated 2026-01-01"
  notes_select markdown "" demo 2>/dev/null || true
  run notes_state "$PROJ" 0.1.0
  assert_failure
  assert_output_contains "no notes provider is selected"
}

# AT-2.4
@test "every verb refuses a root that is not an absolute directory and a version that is not X.Y.Z, and notes_where refuses with no provider selected or no version" {
  # notes_where takes no root, so its refusals are its own, and the first is
  # asked before anything is selected (ST0007 WP-02).
  run notes_where 1.0.0
  assert_failure
  assert_output_contains "notes_where: no notes provider is selected"
  notes_select releases "" demo
  run notes_where v1.0
  assert_failure
  assert_output_contains "notes_where: not a version: v1.0"

  # Every verb that takes a root, under a kind with views and a kind without, so
  # a verb whose provider does nothing still refuses a bad root. A relative root
  # names wherever the caller stands, and a cd to one consults CDPATH.
  local kind spec
  local -a args
  for kind in releases changelog; do
    notes_select "$kind" "" demo
    for spec in "notes_state 1.0.0" "notes_check 1.0.0 2026-09-17" "notes_lint 1.0.0" "notes_date 1.0.0 2026-09-17" "notes_body 1.0.0" "notes_views" "notes_views_check" "notes_paths 1.0.0"; do
      read -r -a args <<<"$spec"
      run "${args[0]}" "$DEVBIN_TEST_TMPDIR/absent" "${args[@]:1}"
      assert_failure
      assert_output_contains "${args[0]}: the root is not a directory"
      run "${args[0]}" relative/root "${args[@]:1}"
      assert_failure
      assert_output_contains "${args[0]}: the root is not an absolute path: relative/root"
    done
    for spec in "notes_state" "notes_check 2026-09-17" "notes_lint" "notes_date 2026-09-17" "notes_body" "notes_paths"; do
      read -r -a args <<<"$spec"
      run "${args[0]}" "$PROJ" v1.0 "${args[@]:1}"
      assert_failure
      assert_output_contains "${args[0]}: not a version: v1.0"
    done
  done
  notes_select releases "" demo
  run notes_date "$PROJ" 1.0.0 17-09-2026
  assert_failure
  assert_output_contains "not a date: 17-09-2026"
  run notes_views
  assert_failure
  assert_output_contains "want <root>"
}

# AT-2.4
@test "a refusal holds when the caller tests the result, which is how the release sequence calls every step" {
  # MEASURED, NOT REASONED (bash 5.3). Under `if`, `||` or `&&` bash turns errexit
  # off for everything the call runs, so a refusal made by `die` at substitution
  # depth printed its message and rendering carried on. The generator this
  # replaced relied on errexit; these arms call the providers the way a caller
  # that tests them does.
  mknote 0.1.0
  grep -v '^status: ' "$PROJ/RELEASES/0.1.0.md" >"$PROJ/n" && mv "$PROJ/n" "$PROJ/RELEASES/0.1.0.md"
  notes_select releases "" demo
  if notes_views "$PROJ" 2>/dev/null; then
    fail "notes_views succeeded over a note with no status: under a condition"
  fi
  [ ! -e "$PROJ/CHANGELOG.md" ]
  [ ! -e "$PROJ/RELEASES.md" ]
  if notes_state "$PROJ" 0.1.0 >/dev/null 2>&1; then
    fail "notes_state answered for a note with no status: under a condition"
  fi
  local out rc=0
  out="$(notes_views_check "$PROJ" 2>/dev/null)" || rc=$?
  [ "$rc" -ne 0 ] || fail "notes_views_check compared views of a note with no status: under ||"
  [ -z "$out" ]
}

# notes_answers <root> <version> <today> -- every read-only verb's answer about
# <root>, each with its status, as one block. Called directly, never through
# `run`, so the verbs see the cwd and environment of the shell that calls it.
notes_answers() {
  local root="$1" v="$2" today="$3" verb out rc
  for verb in state check body views_check paths; do
    rc=0
    case "$verb" in
      state) out="$(notes_state "$root" "$v" 2>&1)" || rc=$? ;;
      check) out="$(notes_check "$root" "$v" "$today" 2>&1)" || rc=$? ;;
      body) out="$(notes_body "$root" "$v" 2>&1)" || rc=$? ;;
      views_check) out="$(notes_views_check "$root" 2>&1)" || rc=$? ;;
      paths) out="$(notes_paths "$root" "$v" 2>&1)" || rc=$? ;;
    esac
    printf '[%s rc=%s]\n%s\n' "$verb" "$rc" "$out"
  done
}

# in_tree <dir> <name> <command...> -- run a command standing in <dir>, with the
# path and name variables the dispatcher exports naming <dir> and <name>.
in_tree() {
  local dir="$1" name="$2"
  shift 2
  (cd "$dir" && export PROJECT_ROOT="$dir" BIN_DIR="$dir/bin" DEVBIN_DIR="$dir/bin/.devbin" DEVBIN_NAME="$name" && "$@")
}

# mkrootcmd <dir> <state> <body> <view> -- a notes.run at <dir>/bin/notes that
# answers ONLY through PROJECT_ROOT, BIN_DIR and DEVBIN_DIR, never through its
# cwd, from answer files under <dir>/notes.
mkrootcmd() {
  mkdir -p "$1/bin" "$1/notes"
  printf '%s\n' "$2" >"$1/notes/state"
  printf '%s\n' "$3" >"$1/notes/body"
  printf '%s\n' "$4" >"$1/notes/view"
  cat >"$1/bin/notes" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  state) cat "$PROJECT_ROOT/notes/state" ;;
  body) cat "$BIN_DIR/../notes/body" ;;
  views-check) printf 'current %s\n' "$(cat "$DEVBIN_DIR/../../notes/view")" ;;
  paths) printf 'notes/%s.md\n' "$2" ;;
  *) printf 'stub: unknown verb: %s\n' "$*" >&2; exit 2 ;;
esac
STUB
  chmod +x "$1/bin/notes"
}

# AT-2.4
@test "every verb answers from the root it is given alone: another cwd, and PROJECT_ROOT, BIN_DIR, DEVBIN_DIR and DEVBIN_NAME naming another tree, change no answer" {
  # A caller asks about a commit by materialising the commit's whole tree and
  # naming it as the root (ST0007 WP-03). An answer drawn from the cwd, or from
  # the environment the dispatcher exports, would describe some other tree and
  # read exactly like a right one. So the baseline stands in the root with that
  # environment naming it, as `release` itself runs, and the comparison stands
  # in a DECOY with the environment naming the decoy. The decoy holds VALID
  # notes with other answers -- dated where the root's are open, another body,
  # one more release -- so a leak reads a plausible wrong note rather than
  # failing to read one.
  local decoy want theirs got
  decoy="$(mkproj decoy <<'YAML'
project:
  name: decoy
YAML
  )"

  # releases: the root's 0.1.0 is open and its views current; the decoy's 0.1.0
  # is dated, beside a 0.0.9 the root does not have and two stale views.
  mknote 0.1.0 "" "open" unreleased
  notes_select releases "" demo
  # Rendered standing in the root, as `release notes` runs, so a verb that reads
  # the cwd or the environment gets past the fixture and meets the comparison.
  in_tree "$PROJ" demo notes_views "$PROJ" >/dev/null
  mkdir -p "$decoy/RELEASES"
  printf 'version: 0.1.0\ndate: 2020-01-01\nheadline: decoy\nstatus: released\n\n# decoy 0.1.0\n\n## Added\n\n- decoy\n' >"$decoy/RELEASES/0.1.0.md"
  printf 'version: 0.0.9\ndate: 2019-01-01\nheadline: decoy\nstatus: released\n\n# decoy 0.0.9\n\n## Added\n\n- decoy\n' >"$decoy/RELEASES/0.0.9.md"
  printf 'decoy\n' >"$decoy/CHANGELOG.md"
  printf 'decoy\n' >"$decoy/RELEASES.md"
  want="$(in_tree "$PROJ" demo notes_answers "$PROJ" 0.1.0 2026-02-03)"
  # THE CONTROLS: the root's answers are the fixture's, so the comparison below
  # cannot pass on two refusals; the decoy's differ in every verb that reads, so
  # a verb reading the decoy cannot pass it either.
  [[ "$want" == *"[state rc=0]"$'\n'"open"$'\n'* ]] || fail "releases, the root's own answers: $want"
  [[ "$want" == *"[check rc=0]"$'\n\n'* ]] || fail "releases, the root's own answers: $want"
  [[ "$want" == *"something added in 0.1.0"* ]] || fail "releases, the root's own answers: $want"
  [[ "$want" == *"[views_check rc=0]"$'\n'"current CHANGELOG.md"$'\n'"current RELEASES.md"$'\n'* ]] || fail "releases, the root's own answers: $want"
  theirs="$(in_tree "$decoy" decoy notes_answers "$decoy" 0.1.0 2026-02-03)"
  [[ "$theirs" == *"[state rc=0]"$'\n'"dated 2020-01-01"$'\n'* && "$theirs" == *"[check rc=1]"* && "$theirs" == *"- decoy"* && "$theirs" == *"STALE CHANGELOG.md"* ]] || fail "releases, the decoy does not differ where it must: $theirs"
  got="$(in_tree "$decoy" decoy notes_answers "$PROJ" 0.1.0 2026-02-03)"
  [ "$got" = "$want" ] || fail "releases: an answer about the root changed with the cwd and environment
want: $want
got:  $got"

  # changelog: the root's 2.0.0 is in progress; the decoy's is dated.
  mkchangelog
  notes_select changelog "" demo
  printf '# Changelog\n\n## [2.0.0] - 2025-06-01\n\n- decoy\n' >"$decoy/CHANGELOG.md"
  want="$(in_tree "$PROJ" demo notes_answers "$PROJ" 2.0.0 2026-02-03)"
  [[ "$want" == *"[state rc=0]"$'\n'"open"$'\n'* && "$want" == *"[check rc=0]"$'\n\n'* && "$want" == *"- a fix"* ]] || fail "changelog, the root's own answers: $want"
  theirs="$(in_tree "$decoy" decoy notes_answers "$decoy" 2.0.0 2026-02-03)"
  [[ "$theirs" == *"[state rc=0]"$'\n'"dated 2025-06-01"$'\n'* && "$theirs" == *"[check rc=1]"* && "$theirs" == *"- decoy"* ]] || fail "changelog, the decoy does not differ where it must: $theirs"
  got="$(in_tree "$decoy" decoy notes_answers "$PROJ" 2.0.0 2026-02-03)"
  [ "$got" = "$want" ] || fail "changelog: an answer about the root changed with the cwd and environment
want: $want
got:  $got"

  # command: the same notes.run in both trees, answering only through the
  # environment, so it is the environment the core hands it that is held.
  mkrootcmd "$PROJ" open "the root's body" docs/ROOT.md
  mkrootcmd "$decoy" "dated 2025-06-01" "the decoy's body" docs/DECOY.md
  notes_select command bin/notes demo
  want="$(in_tree "$PROJ" demo notes_answers "$PROJ" 2.0.0 2026-02-03)"
  [[ "$want" == *"[state rc=0]"$'\n'"open"$'\n'* && "$want" == *"[check rc=0]"$'\n\n'* && "$want" == *"the root's body"* && "$want" == *"current docs/ROOT.md"* ]] || fail "command, the root's own answers: $want"
  theirs="$(in_tree "$decoy" decoy notes_answers "$decoy" 2.0.0 2026-02-03)"
  [[ "$theirs" == *"[state rc=0]"$'\n'"dated 2025-06-01"$'\n'* && "$theirs" == *"[check rc=1]"* && "$theirs" == *"the decoy's body"* && "$theirs" == *"current docs/DECOY.md"* ]] || fail "command, the decoy does not differ where it must: $theirs"
  got="$(in_tree "$decoy" decoy notes_answers "$PROJ" 2.0.0 2026-02-03)"
  [ "$got" = "$want" ] || fail "command: an answer about the root changed with the cwd and environment
want: $want
got:  $got"
}

# AT-2.4
@test "a command provider runs with devbin's own path exports naming the root it answers for, and inherits nothing else naming the working tree but the running runtime" {
  # Through the real dispatcher, because the dispatcher is what exports the
  # working tree's paths. A project handler asks a command provider about a copy
  # of the tree, and the provider dumps the environment it was given. TMPDIR and
  # HOME sit outside the project here, so every value naming the working tree is
  # devbin's, and the next export that names the tree goes red here until it is
  # re-pointed or declared. The dispatcher is invoked through a symlink to the
  # project first: MEASURED, the handler then stands at the link's spelling, a cd
  # hands that spelling to the command as OLDPWD, and a search for the physical
  # path alone passes it. So the working tree is looked for in both spellings.
  local copy copylink link pair spelling root name leaks
  copy="$DEVBIN_TEST_TMPDIR/copy"
  copylink="$DEVBIN_TEST_TMPDIR/copylink"
  link="$DEVBIN_TEST_TMPDIR/link"
  ln -s "$PROJ" "$link"
  mkdir -p "$copy/bin" "$PROJ/bin/.devbin/cmd"
  ln -s "$copy" "$copylink"
  write_config "$PROJ" <<'YAML'
project:
  name: demo
commands:
  probe:
    summary: asks a command provider about another root
YAML
  create_test_command "$PROJ" probe "$(
    cat <<'HANDLER'
#!/usr/bin/env bash
set -uo pipefail
env | LC_ALL=C sort >"$1/handler.env"
. "$DEVBIN_LIB/helpers"
. "$DEVBIN_LIB/release.notes"
notes_select command bin/notes "$DEVBIN_NAME" || exit 1
notes_state "$1" 1.0.0
HANDLER
  )" >/dev/null
  cat >"$copy/bin/notes" <<'STUB'
#!/usr/bin/env bash
env | LC_ALL=C sort >command.env
printf 'open\n'
STUB
  chmod +x "$copy/bin/notes"

  # Each run pairs how the dispatcher is invoked with how the root is spelled:
  # through the link to the project, asking about the copy's physical path; then
  # directly, asking about a link to the copy, whose re-pointed values must still
  # be spelled physically, as the dispatcher spells PROJECT_ROOT.
  for pair in "$link|$copy" "$PROJ|$copylink"; do
    spelling="${pair%%|*}"
    root="${pair#*|}"
    rm -f "$copy/handler.env" "$copy/command.env"
    run devbin_run "$spelling" probe "$root"
    assert_success
    assert_output "open"
    # THE CONTROLS: the handler was given the working tree, so a command that
    # inherited its environment unchanged would be caught below; and the command
    # was given the copy under every name devbin re-points.
    grep -qxF "PROJECT_ROOT=$PROJ" "$copy/handler.env" || fail "invoked as $spelling about $root, the handler was not given the working tree's PROJECT_ROOT"
    grep -qxF "DEMO_ROOT=$PROJ" "$copy/handler.env" || fail "invoked as $spelling about $root, the handler was not given the working tree's DEMO_ROOT"
    grep -qxF "DEVBIN_ROOT_VAR=DEMO_ROOT" "$copy/handler.env" || fail "invoked as $spelling about $root, bin/devbin did not export the root variable's name"
    for name in "PROJECT_ROOT=$copy" "BIN_DIR=$copy/bin" "DEVBIN_DIR=$copy/bin/.devbin" "DEVBIN_INVOKE=bin/devbin" "DEMO_ROOT=$copy" "DEVBIN_LIB=$PROJ/bin/.devbin/lib"; do
      grep -qxF "$name" "$copy/command.env" || fail "invoked as $spelling about $root, the command's environment lacks $name"
    done
    leaks="$(grep -F -e "$PROJ" -e "$link" "$copy/command.env" | grep -v '^DEVBIN_LIB=' || true)"
    [ -z "$leaks" ] || fail "invoked as $spelling about $root, the command inherited values naming the working tree:
$leaks"
  done

  # From a subdirectory the dispatcher hands the handler an ABSOLUTE
  # DEVBIN_INVOKE, which names the working tree, where both runs above stand at
  # the root and get bin/devbin already; the command must still get bin/devbin
  # (ST0007 WP-02).
  mkdir -p "$PROJ/sub"
  rm -f "$copy/handler.env" "$copy/command.env"
  run bash -c 'cd "$1" && ../bin/devbin probe "$2" </dev/null' _ "$PROJ/sub" "$copy"
  assert_success
  assert_output "open"
  grep -qxF "DEVBIN_INVOKE=$PROJ/bin/devbin" "$copy/handler.env" || fail "from a subdirectory, the handler got $(grep '^DEVBIN_INVOKE=' "$copy/handler.env"), want the absolute form"
  grep -qxF "DEVBIN_INVOKE=bin/devbin" "$copy/command.env" || fail "from a subdirectory, the command's $(grep '^DEVBIN_INVOKE=' "$copy/command.env")"
}

# AT-2.4
@test "a root variable name that is not an identifier stops a command provider before it runs, with bash's own reason on stderr" {
  # DEVBIN_ROOT_VAR has one source, bin/devbin, which exports it only after
  # assert_identifier passed it, so the library does not check it again. What
  # stops a bad one is the export failing, and only because that failure is
  # honoured: otherwise the command would run with the working tree's root
  # variable still in place.
  mkdir -p "$PROJ/bin"
  cat >"$PROJ/bin/marker" <<'STUB'
#!/usr/bin/env bash
: >ran
printf 'open\n'
STUB
  chmod +x "$PROJ/bin/marker"
  notes_select command bin/marker demo
  # THE CONTROL: under a valid name the same command runs and answers.
  export DEVBIN_ROOT_VAR=DEMO_ROOT
  run notes_state "$PROJ" 1.0.0
  assert_success
  assert_output "open"
  [ -e "$PROJ/ran" ] || fail "the control's command did not run"
  rm "$PROJ/ran"
  export DEVBIN_ROOT_VAR=not-a-name
  run notes_state "$PROJ" 1.0.0
  unset DEVBIN_ROOT_VAR
  assert_failure
  assert_output_contains "not a valid identifier"
  assert_output_contains "notes.run failed"
  [ ! -e "$PROJ/ran" ] || fail "the command ran with its root variable not re-pointed"
}

# ---- releases ----------------------------------------------------------------

# AT-2.1
@test "releases: state is absent, open or dated, and a malformed header is refused rather than called absent" {
  mknote 0.1.0 2026-02-03
  mknote 0.2.0 "" "open" unreleased
  notes_select releases "" demo
  run notes_state "$PROJ" 0.1.0
  assert_output "dated 2026-02-03"
  run notes_state "$PROJ" 0.2.0
  assert_output "open"
  run notes_state "$PROJ" 0.3.0
  assert_success
  assert_output "absent"
  mknote 0.4.0 "3 February 2026"
  run notes_state "$PROJ" 0.4.0
  assert_failure
  assert_output_contains "0.4.0.md has date: 3 February 2026"
}

# AT-2.1
@test "releases: an unreleased note carrying an empty date: line is refused before dating writes, on either side of version:" {
  # Read as a bare value an empty `date: ` was no date at all, so the note read
  # as open. With the line after version:, dating left two date lines and exited
  # 0; before it, dating rewrote the note to released and then refused on the
  # read-back, leaving it unreadable. A refusal must not have written (ST0007
  # WP-02).
  notes_select releases "" demo
  local header sum
  for header in 'version: 0.2.0\ndate: \nheadline: h\nstatus: unreleased' 'date: \nversion: 0.2.0\nheadline: h\nstatus: unreleased'; do
    printf '%b\n\n## Added\n\n- x\n' "$header" >"$PROJ/RELEASES/0.2.0.md"
    sum="$(sha256_of "$PROJ/RELEASES/0.2.0.md")"
    run notes_state "$PROJ" 0.2.0
    assert_failure
    assert_output_contains "RELEASES/0.2.0.md is unreleased but carries date: (empty)"
    run notes_date "$PROJ" 0.2.0 2026-09-17
    assert_failure
    [ "$(sha256_of "$PROJ/RELEASES/0.2.0.md")" = "$sum" ] || fail "dating wrote to a note it refused:
$(cat "$PROJ/RELEASES/0.2.0.md")"
  done
}

# AT-2.1
@test "releases: a header line with no space after its colon, or a key given twice, is refused naming the line" {
  # Each was read wrongly rather than refused: `status:released` as no status, a
  # bare `date:` as no date, and a second key as whichever came first. Refused,
  # a header line keeps one spelling that every reader of it agrees on (ST0007
  # WP-02).
  notes_select releases "" demo
  local header want
  while IFS='|' read -r header want; do
    [ -n "$header" ] || continue
    printf '%b\n\n## Added\n\n- x\n' "$header" >"$PROJ/RELEASES/0.3.0.md"
    run notes_state "$PROJ" 0.3.0
    assert_failure
    assert_output_contains "$want"
  done <<'ROWS'
version: 0.3.0\nstatus:released\ndate: 2026-01-01|RELEASES/0.3.0.md line 2 reads 'status:released' -- a header line is 'key: value'
version: 0.3.0\ndate:\nstatus: unreleased|RELEASES/0.3.0.md line 2 reads 'date:' -- a header line is 'key: value'
version: 0.3.0\ndate:2026-01-01\nstatus: released|RELEASES/0.3.0.md line 2 reads 'date:2026-01-01' -- a header line is 'key: value'
version: 0.3.0\ndate: 2026-01-01\nstatus: released\ndate: 2026-02-02|RELEASES/0.3.0.md line 4 gives date: a second time -- a header carries each key once
ROWS
}

# AT-2.1
@test "releases: a .md under RELEASES/ that is not named for a version is refused by name, a hidden one too" {
  mknote 0.1.0
  notes_select releases "" demo
  printf 'version: none\n' >"$PROJ/RELEASES/README.md"
  run notes_views "$PROJ"
  assert_failure
  assert_output_contains "README.md"
  assert_output_contains "not release notes"
  [ ! -e "$PROJ/CHANGELOG.md" ]
  rm "$PROJ/RELEASES/README.md"
  printf 'draft\n' >"$PROJ/RELEASES/.draft.md"
  run notes_views_check "$PROJ"
  assert_failure
  assert_output_contains ".draft.md"
}

# AT-2.1
@test "releases: both views are rendered before either is replaced, so a failed second render leaves both as they were" {
  # The generator this replaced wrote the changelog before it rendered the index,
  # so a failure in the second left two views that disagreed.
  mknote 0.1.0
  notes_select releases "" demo
  notes_views "$PROJ" >/dev/null
  local log index
  log="$(sha256_of "$PROJ/CHANGELOG.md")"
  index="$(sha256_of "$PROJ/RELEASES.md")"
  mknote 0.2.0
  _notes_releases_index() { return 1; }
  run notes_views "$PROJ"
  assert_failure
  [ "$log" = "$(sha256_of "$PROJ/CHANGELOG.md")" ] || fail "CHANGELOG.md was replaced although RELEASES.md could not be rendered"
  [ "$index" = "$(sha256_of "$PROJ/RELEASES.md")" ]
  # The changelog was staged before the index failed, so its temporary is the one
  # this failure must remove (ST0007 WP-02).
  run find "$PROJ" -maxdepth 1 \( -name 'CHANGELOG.md.*' -o -name 'RELEASES.md.*' \)
  assert_success
  assert_output ""
}

# AT-2.1
@test "releases: views are replaced by a rename beside them, keep their mode, and leave no temporary behind" {
  mknote 0.1.0
  notes_select releases "" demo
  notes_views "$PROJ" >/dev/null
  # 604 for both views: no umask in use gives it, and each view is asserted on
  # its own, because an in-place write keeps a mode AND an inode, so holding one
  # view proves nothing of the other (ST0007 WP-02).
  chmod 604 "$PROJ/CHANGELOG.md" "$PROJ/RELEASES.md"
  local log_inode index_inode
  log_inode="$(inode_of "$PROJ/CHANGELOG.md")"
  index_inode="$(inode_of "$PROJ/RELEASES.md")"
  mknote 0.2.0
  notes_views "$PROJ" >/dev/null
  grep -q '^## \[0.2.0\]' "$PROJ/CHANGELOG.md" || fail "CHANGELOG.md was not regenerated, so nothing below measures a write"
  grep -qF '[0.2.0]' "$PROJ/RELEASES.md" || fail "RELEASES.md was not regenerated, so nothing below measures a write"
  [ "$(mode_of "$PROJ/CHANGELOG.md")" = "-rw----r--" ] || fail "CHANGELOG.md lost its mode: $(mode_of "$PROJ/CHANGELOG.md")"
  [ "$(inode_of "$PROJ/CHANGELOG.md")" != "$log_inode" ] || fail "CHANGELOG.md was written in place, not renamed over"
  [ "$(mode_of "$PROJ/RELEASES.md")" = "-rw----r--" ] || fail "RELEASES.md lost its mode: $(mode_of "$PROJ/RELEASES.md")"
  [ "$(inode_of "$PROJ/RELEASES.md")" != "$index_inode" ] || fail "RELEASES.md was written in place, not renamed over"
  run find "$PROJ" -maxdepth 1 \( -name 'CHANGELOG.md.*' -o -name 'RELEASES.md.*' \)
  assert_success
  assert_output ""
}

# AT-2.1
@test "releases: a view rendered for the first time takes the mode the umask gives a new file, not mktemp's 0600" {
  mknote 0.1.0
  notes_select releases "" demo
  # Three umasks: under any one of them several bases give the same answer, so
  # 027 alone could not tell 0666 from 0644 (ST0007 WP-02).
  local row mask want
  for row in "027 -rw-r-----" "002 -rw-rw-r--" "000 -rw-rw-rw-"; do
    mask="${row%% *}"
    want="${row#* }"
    rm -f "$PROJ/CHANGELOG.md" "$PROJ/RELEASES.md"
    (umask "$mask" && notes_views "$PROJ" >/dev/null) || fail "notes_views failed under umask $mask"
    [ "$(mode_of "$PROJ/CHANGELOG.md")" = "$want" ] || fail "under umask $mask CHANGELOG.md is $(mode_of "$PROJ/CHANGELOG.md"), want $want"
    [ "$(mode_of "$PROJ/RELEASES.md")" = "$want" ] || fail "under umask $mask RELEASES.md is $(mode_of "$PROJ/RELEASES.md"), want $want"
  done
}

# AT-2.1
@test "releases: dating a note replaces it by a rename and keeps its mode" {
  mknote 0.2.0 "" "open" unreleased
  chmod 640 "$PROJ/RELEASES/0.2.0.md"
  local inode
  inode="$(inode_of "$PROJ/RELEASES/0.2.0.md")"
  notes_select releases "" demo
  notes_date "$PROJ" 0.2.0 2026-09-17 >/dev/null
  run notes_state "$PROJ" 0.2.0
  assert_output "dated 2026-09-17"
  [ "$(mode_of "$PROJ/RELEASES/0.2.0.md")" = "-rw-r-----" ] || fail "the note lost its mode: $(mode_of "$PROJ/RELEASES/0.2.0.md")"
  [ "$(inode_of "$PROJ/RELEASES/0.2.0.md")" != "$inode" ] || fail "the note was written in place, not renamed over"
}

@test "releases: dating a linked note and regenerating linked views write the files the links name, and every link survives" {
  # Issue 0084. Before it, each write renamed its temporary over the LINK, so the
  # link became a regular file, the file it named kept its old content, and
  # views_check then agreed with the copy. One relative link, one absolute, and
  # one from a subdirectory, each into a directory outside the project.
  local shared="$DEVBIN_TEST_TMPDIR/shared" f log_inode
  mknote 0.1.0
  mknote 0.2.0 "" "open" unreleased
  notes_select releases "" demo
  notes_views "$PROJ" >/dev/null
  mkdir -p "$shared"
  mv "$PROJ/CHANGELOG.md" "$PROJ/RELEASES.md" "$PROJ/RELEASES/0.2.0.md" "$shared/"
  ln -s ../shared/CHANGELOG.md "$PROJ/CHANGELOG.md"
  ln -s "$shared/RELEASES.md" "$PROJ/RELEASES.md"
  ln -s ../../shared/0.2.0.md "$PROJ/RELEASES/0.2.0.md"
  chmod 604 "$shared/CHANGELOG.md" "$shared/RELEASES.md" "$shared/0.2.0.md"
  log_inode="$(inode_of "$shared/CHANGELOG.md")"
  run notes_date "$PROJ" 0.2.0 2026-09-17
  assert_success
  run notes_views "$PROJ"
  assert_success
  assert_symlink_exists "$PROJ/CHANGELOG.md" ../shared/CHANGELOG.md
  assert_symlink_exists "$PROJ/RELEASES.md" "$shared/RELEASES.md"
  assert_symlink_exists "$PROJ/RELEASES/0.2.0.md" ../../shared/0.2.0.md
  grep -qx 'date: 2026-09-17' "$shared/0.2.0.md" || fail "the note the link names was not dated:
$(cat "$shared/0.2.0.md")"
  grep -q '^## \[0.2.0\]' "$shared/CHANGELOG.md" || fail "the changelog the link names was not regenerated"
  grep -qF '[0.2.0]' "$shared/RELEASES.md" || fail "the index the link names was not regenerated"
  for f in CHANGELOG.md RELEASES.md 0.2.0.md; do
    [ "$(mode_of "$shared/$f")" = "-rw----r--" ] || fail "$f came out $(mode_of "$shared/$f")"
  done
  [ "$(inode_of "$shared/CHANGELOG.md")" != "$log_inode" ] || fail "the changelog the link names was written in place, not renamed over"
  run find "$PROJ" "$shared" -name '*.md.*'
  assert_success
  assert_output ""
  run notes_views_check "$PROJ"
  assert_success
  assert_output "current CHANGELOG.md
current RELEASES.md"
}

@test "releases: a view that is a link to no file is refused naming it, and neither view is written" {
  # Issue 0084. Before it, a dangling CHANGELOG.md read as a view not generated
  # yet: both were rendered and the link was replaced by a regular file, rc 0.
  # Each view in turn, so the second one's refusal also removes the first's
  # temporary.
  local view other sum
  mknote 0.1.0
  notes_select releases "" demo
  for view in CHANGELOG.md RELEASES.md; do
    rm -f "$PROJ/CHANGELOG.md" "$PROJ/RELEASES.md"
    other=RELEASES.md
    [ "$view" = RELEASES.md ] && other=CHANGELOG.md
    printf 'hand-made\n' >"$PROJ/$other"
    sum="$(sha256_of "$PROJ/$other")"
    ln -s "../shared/$view" "$PROJ/$view"
    run notes_views "$PROJ"
    assert_failure
    assert_output_contains "$PROJ/$view is a symbolic link that leads to no file"
    assert_output_contains "CHANGELOG.md and RELEASES.md are left as they were"
    assert_symlink_exists "$PROJ/$view" "../shared/$view"
    [ "$(sha256_of "$PROJ/$other")" = "$sum" ] || fail "with $view refused, $other was written"
    run find "$PROJ" -maxdepth 1 -name '*.md.*'
    assert_success
    assert_output ""
  done
}

# AT-2.1
@test "releases: a headline holding a tab is refused naming the note, and a | in one is escaped in the index" {
  mknote 0.1.0 2026-01-01 "$(printf 'a\ttab')"
  notes_select releases "" demo
  run notes_views "$PROJ"
  assert_failure
  assert_output_contains "the headline in RELEASES/0.1.0.md contains a tab"
  [ ! -e "$PROJ/RELEASES.md" ]
  mknote 0.1.0 2026-01-01 "one | two"
  run notes_views "$PROJ"
  assert_success
  grep -qF '| one \| two |' "$PROJ/RELEASES.md" || fail "the | was not escaped: $(grep -F 'one' "$PROJ/RELEASES.md")"
  run awk '/^\|/ { w[length($0)] = 1 } END { for (k in w) print k }' "$PROJ/RELEASES.md"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || fail "the escaped row is not the table's width: $output"
}

# AT-2.1
@test "releases: the changelog header names the project and states no project's own semver rule" {
  # The header is the core's (ST0007). devbin's own caret rule lives in
  # docs/configuration.md, not in every project's changelog.
  mknote 0.1.0
  notes_select releases "" widget
  notes_views "$PROJ" >/dev/null
  grep -qx 'All notable changes to widget are recorded here.' "$PROJ/CHANGELOG.md"
  grep -qF 'and widget aims at [Semantic Versioning](https://semver.org/spec/v2.0.0.html).' "$PROJ/CHANGELOG.md"
  if grep -qi 'caret' "$PROJ/CHANGELOG.md"; then
    fail "the changelog header states a semver rule"
  fi
  if grep -q 'devbin aims' "$PROJ/CHANGELOG.md"; then
    fail "the changelog header names devbin in another project"
  fi
}

# AT-2.1
@test "releases: views_check says current, and STALE for a view one line off or missing, writing nothing and returning 0 because it compared" {
  mknote 0.1.0
  notes_select releases "" demo
  notes_views "$PROJ" >/dev/null
  run notes_views_check "$PROJ"
  assert_success
  assert_output "current CHANGELOG.md
current RELEASES.md"

  sed_inplace 's/headline for 0\.1\.0/headline for 0.1.O/' "$PROJ/RELEASES.md"
  [ "$(grep -c 'headline for 0.1.O' "$PROJ/RELEASES.md")" -eq 1 ] || fail "the one-line edit did not land"
  local before
  before="$(tree_sum "$PROJ")"
  run notes_views_check "$PROJ"
  assert_success
  assert_output_contains "current CHANGELOG.md"
  assert_output_contains "STALE RELEASES.md"
  [ "$before" = "$(tree_sum "$PROJ")" ] || fail "views_check wrote under the root"

  rm "$PROJ/CHANGELOG.md"
  run notes_views_check "$PROJ"
  assert_success
  assert_output_contains "STALE CHANGELOG.md"
  # Writing nothing holds for a MISSING view too: a check that put its fresh
  # render in place would print the same STALE line (ST0007 WP-02).
  [ ! -e "$PROJ/CHANGELOG.md" ] || fail "views_check restored the missing CHANGELOG.md -- a predicate, not a repair"
}

# AT-2.1
@test "releases: the body is byte for byte what the release workflow publishes, blank lines at the end included" {
  local prog note v n=0
  prog="$(workflow_body_awk)"
  [ -n "$prog" ] || fail "no body awk found in .github/workflows/release.yml -- nothing to hold notes_body to"
  mknote 0.1.0
  printf '\n\n' >>"$PROJ/RELEASES/0.1.0.md"
  notes_select releases "" demo
  for note in "$PROJ/RELEASES/0.1.0.md" "$DEVBIN_HOME"/RELEASES/*.md; do
    v="${note##*/}"
    v="${v%.md}"
    notes_body "${note%/RELEASES/*}" "$v" >"$DEVBIN_TEST_TMPDIR/body.core"
    awk "$prog" "$note" >"$DEVBIN_TEST_TMPDIR/body.workflow"
    cmp "$DEVBIN_TEST_TMPDIR/body.core" "$DEVBIN_TEST_TMPDIR/body.workflow" ||
      fail "notes_body and the release workflow disagree about $note"
    n=$((n + 1))
  done
  # The fixture is one body; past it, this repository's notes must be there.
  [ "$n" -gt 1 ] || fail "compared only the fixture's body: none of this repository's notes"
}

# AT-2.1
@test "releases: a note with a header block and no body is refused" {
  printf 'version: 0.1.0\ndate: 2026-01-01\nheadline: h\nstatus: released\n' >"$PROJ/RELEASES/0.1.0.md"
  notes_select releases "" demo
  run notes_body "$PROJ" 0.1.0
  assert_failure
  assert_output_contains "has a header block and no body"
  run notes_body "$PROJ" 0.2.0
  assert_failure
  assert_output_contains "there is no RELEASES/0.2.0.md"
}

# AT-2.1
@test "releases: date writes status released and the date under version, moves no other byte, and reads back dated" {
  mknote 0.2.0 "" "the open one" unreleased
  cp "$PROJ/RELEASES/0.2.0.md" "$DEVBIN_TEST_TMPDIR/before.md"
  notes_select releases "" demo
  run notes_date "$PROJ" 0.2.0 2026-09-17
  assert_success
  assert_output "RELEASES/0.2.0.md"
  [ "$(sed -n '1,4p' "$PROJ/RELEASES/0.2.0.md")" = "version: 0.2.0
date: 2026-09-17
headline: the open one
status: released" ]
  [ -z "$(sed -n '5p' "$PROJ/RELEASES/0.2.0.md")" ] || fail "the header block no longer ends at line 5"
  awk 'f { print } /^$/ && !f { f = 1 }' "$DEVBIN_TEST_TMPDIR/before.md" >"$DEVBIN_TEST_TMPDIR/body.before"
  awk 'f { print } /^$/ && !f { f = 1 }' "$PROJ/RELEASES/0.2.0.md" >"$DEVBIN_TEST_TMPDIR/body.after"
  cmp "$DEVBIN_TEST_TMPDIR/body.before" "$DEVBIN_TEST_TMPDIR/body.after"
  run notes_state "$PROJ" 0.2.0
  assert_output "dated 2026-09-17"
}

# AT-2.1
@test "releases: dating a note already dated that day writes nothing, another day is refused, and an absent note is refused" {
  mknote 0.2.0 "" "open" unreleased
  notes_select releases "" demo
  notes_date "$PROJ" 0.2.0 2026-09-17 >/dev/null
  local sum
  sum="$(sha256_of "$PROJ/RELEASES/0.2.0.md")"
  run notes_date "$PROJ" 0.2.0 2026-09-17
  assert_success
  assert_output ""
  [ "$sum" = "$(sha256_of "$PROJ/RELEASES/0.2.0.md")" ]
  run notes_date "$PROJ" 0.2.0 2026-09-18
  assert_failure
  assert_output_contains "released on 2026-09-17"
  assert_output_contains "never re-dated"
  [ "$sum" = "$(sha256_of "$PROJ/RELEASES/0.2.0.md")" ]
  run notes_date "$PROJ" 0.3.0 2026-09-17
  assert_failure
  assert_output_contains "there is no RELEASES/0.3.0.md to date"
}

# AT-2.1
@test "releases: a header with no version line takes the date first" {
  printf 'headline: h\nstatus: unreleased\n\n## Added\n\n- x\n' >"$PROJ/RELEASES/0.5.0.md"
  notes_select releases "" demo
  notes_date "$PROJ" 0.5.0 2026-09-17 >/dev/null
  [ "$(sed -n '1,3p' "$PROJ/RELEASES/0.5.0.md")" = "date: 2026-09-17
headline: h
status: released" ]
}

# AT-2.1
@test "releases: notes_check is ready for an open note or one dated today, and refuses one dated another day or absent, naming why" {
  mknote 0.1.0 2026-09-16
  mknote 0.2.0 "" "open" unreleased
  notes_select releases "" demo
  run notes_check "$PROJ" 0.2.0 2026-09-17
  assert_success
  run notes_check "$PROJ" 0.1.0 2026-09-16
  assert_success
  run notes_check "$PROJ" 0.1.0 2026-09-17
  assert_failure
  assert_output_contains "released on 2026-09-16, not today (2026-09-17)"
  run notes_check "$PROJ" 0.3.0 2026-09-17
  assert_failure
  assert_output_contains "there is no RELEASES/0.3.0.md"
}

# mkbody <version> <header line>... -- a note for <version> whose header carries
# the given extra lines, open, with the body read from stdin; writes VERSION.
mkbody() {
  local v="$1"
  shift
  {
    printf 'version: %s\nheadline: h\nstatus: unreleased\n' "$v"
    [ $# -eq 0 ] || printf '%s\n' "$@"
    printf '\n'
    cat
  } >"$PROJ/RELEASES/$v.md"
  printf '%s\n' "$v" >"$PROJ/VERSION"
}

# changelog_entry <version> -- the version's entry in $PROJ/CHANGELOG.md, from
# its heading up to the line before the next.
changelog_entry() {
  awk -v h="## [$1] " 'index($0, h) == 1 { f = 1; print; next } f && /^## \[/ { exit } f { print }' "$PROJ/CHANGELOG.md"
}

@test "releases: a heading whose first word is a section's name is that section's, its qualifier kept as a subheading, in the note's order (0212)" {
  # Every note from 0.1.7 to 0.1.13 qualified its headings, `## Fixed -- <a
  # qualifier>`, and the reader matched them whole: seven empty entries.
  mkbody 0.3.0 <<'NOTE'
Narrative.

## Fixed -- reaches every estate

- fix one

- fix two

## Known limitations

- not a section

## Fixedness

- not Fixed's either

## Changed: a script may differ

- change one

## Fixed - devbin's own tree

- fix three

## Fixed

- fix four

## Security --

## Added -- empty below
NOTE
  run_in_project "$PROJ" release notes
  assert_success
  local want
  want="$(printf '%s\n' '## [0.3.0] - Unreleased' '' \
    '### Changed' '' '#### a script may differ' '' '- change one' '' \
    '### Fixed' '' '#### reaches every estate' '' '- fix one' '- fix two' '' \
    "#### devbin's own tree" '' '- fix three' '' '- fix four' '' \
    'Full note: [RELEASES/0.3.0.md](RELEASES/0.3.0.md)')"
  [ "$(changelog_entry 0.3.0)" = "$want" ] || fail "the entry:
$(changelog_entry 0.3.0)
want:
$want"
}

@test "releases: a note the changelog would render empty is refused by notes_check and release check, naming its headings, unless its header says changelog: none (0212)" {
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  assert_success
  mkbody 0.2.0 <<'NOTE'
## Fixes -- reaches every estate

- a fix the changelog cannot see

## Known limitations

- none
NOTE
  run_in_project "$PROJ" release notes
  assert_success
  notes_select releases "" demo
  local why="RELEASES/0.2.0.md has no section the changelog reads, so its release would be left out of CHANGELOG.md -- its headings are '## Fixes -- reaches every estate', '## Known limitations'; a section's heading begins with one of: Added, Changed, Deprecated, Removed, Fixed, Security, or the header says changelog: none"
  run notes_check "$PROJ" 0.2.0 2026-09-17
  assert_failure
  assert_output_contains "$why"
  run_in_project "$PROJ" release check
  assert_failure
  assert_output_contains "$why"

  # Said in the header, the empty entry is the note's choice and passes.
  mkbody 0.2.0 'changelog: none' <<'NOTE'
## Known limitations

- none
NOTE
  run notes_check "$PROJ" 0.2.0 2026-09-17
  assert_success
  run_in_project "$PROJ" release notes
  assert_success
  local entry
  entry="$(changelog_entry 0.2.0)"
  grep -qxF '_No changelog sections in this release note._' <<<"$entry" || fail "the entry: $entry"

  # A header saying none over a section the changelog reads says something false.
  mkbody 0.2.0 'changelog: none' <<'NOTE'
## Fixed -- reaches every estate

- a fix
NOTE
  run notes_check "$PROJ" 0.2.0 2026-09-17
  assert_failure
  assert_output_contains "RELEASES/0.2.0.md carries changelog: none, and the changelog reads its Fixed -- drop the line or the section"

  mkbody 0.2.0 'changelog: some' <<'NOTE'
## Fixed

- a fix
NOTE
  run notes_check "$PROJ" 0.2.0 2026-09-17
  assert_failure
  assert_output_contains "RELEASES/0.2.0.md has changelog: some -- the one value is none"
}

# AT-2.1
@test "releases: a release owns its note and both views" {
  notes_select releases "" demo
  run notes_paths "$PROJ" 1.2.3
  assert_success
  assert_output "RELEASES/1.2.3.md
CHANGELOG.md
RELEASES.md"
  run notes_where 1.2.3
  assert_output "RELEASES/1.2.3.md"
}

# ---- changelog ---------------------------------------------------------------

# mkchangelog -- a hand-written CHANGELOG.md in $PROJ, in Intent's and Utilz's
# shape, with the headings the changelog arms need.
mkchangelog() {
  cat >"$PROJ/CHANGELOG.md" <<'MD'
# Changelog

## [2.0.0] - in progress

### Added

- **a thing** with `code`

### Fixed

- a fix


## [1.5.0] - Unreleased

- five

## [1.2.30] - 2026-01-01

- thirty

## [1x2x3] - 2026-01-02

## [1.4.0] - never released; this work shipped elsewhere

## [1.0.0] - 2025-01-01

- first
MD
}

# AT-2.2
@test "changelog: state reads the asked-for heading only, as a string, with unreleased and in progress open in any case" {
  notes_select changelog "" demo
  run notes_state "$PROJ" 2.0.0
  assert_output "absent"
  mkchangelog
  run notes_state "$PROJ" 2.0.0
  assert_output "open"
  run notes_state "$PROJ" 1.5.0
  assert_output "open"
  run notes_state "$PROJ" 1.0.0
  assert_output "dated 2025-01-01"
  # 1.2.3 is neither 1.2.30 nor 1x2x3: compared as a string, never a pattern.
  run notes_state "$PROJ" 1.2.3
  assert_success
  assert_output "absent"
  # Another version's free-text heading is never parsed.
  run notes_state "$PROJ" 1.0.0
  assert_success
}

# AT-2.2
@test "changelog: the target's heading is refused when its marker is none of a date, unreleased or in progress, when it has none, and when it appears twice" {
  mkchangelog
  printf '\n## [3.0.0]\n\n## [3.1.0] - 2026-02-02\n\n## [3.1.0] - 2026-02-03\n' >>"$PROJ/CHANGELOG.md"
  notes_select changelog "" demo
  run notes_state "$PROJ" 1.4.0
  assert_failure
  assert_output_contains "reads '## [1.4.0] - never released; this work shipped elsewhere'"
  run notes_state "$PROJ" 3.0.0
  assert_failure
  assert_output_contains "reads '## [3.0.0]'"
  run notes_state "$PROJ" 3.1.0
  assert_failure
  assert_output_contains "2 headings for [3.1.0]"
}

# AT-2.2
@test "changelog: date rewrites the heading's marker and no other line" {
  mkchangelog
  cp "$PROJ/CHANGELOG.md" "$DEVBIN_TEST_TMPDIR/before.md"
  notes_select changelog "" demo
  run notes_date "$PROJ" 2.0.0 2026-09-17
  assert_success
  assert_output "CHANGELOG.md"
  run diff "$DEVBIN_TEST_TMPDIR/before.md" "$PROJ/CHANGELOG.md"
  assert_output "3c3
< ## [2.0.0] - in progress
---
> ## [2.0.0] - 2026-09-17"
  run notes_state "$PROJ" 2.0.0
  assert_output "dated 2026-09-17"
}

@test "changelog: dating a linked CHANGELOG.md writes the file the link names, and the link survives" {
  # Issue 0084: the second date writer, through the same replace_file.
  local shared="$DEVBIN_TEST_TMPDIR/shared"
  mkchangelog
  mkdir -p "$shared"
  mv "$PROJ/CHANGELOG.md" "$shared/CHANGELOG.md"
  ln -s ../shared/CHANGELOG.md "$PROJ/CHANGELOG.md"
  notes_select changelog "" demo
  run notes_date "$PROJ" 2.0.0 2026-09-17
  assert_success
  assert_symlink_exists "$PROJ/CHANGELOG.md" ../shared/CHANGELOG.md
  grep -qx '## \[2.0.0\] - 2026-09-17' "$shared/CHANGELOG.md" || fail "the changelog the link names was not dated:
$(cat "$shared/CHANGELOG.md")"
  run find "$PROJ" "$shared" -name 'CHANGELOG.md.*'
  assert_success
  assert_output ""
}

# AT-2.2
@test "changelog: the body is the section up to the next heading, without its leading and trailing blank lines, and an empty section is refused" {
  mkchangelog
  notes_select changelog "" demo
  notes_body "$PROJ" 2.0.0 >"$DEVBIN_TEST_TMPDIR/body"
  printf '### Added\n\n- **a thing** with `code`\n\n### Fixed\n\n- a fix\n' >"$DEVBIN_TEST_TMPDIR/want"
  cmp "$DEVBIN_TEST_TMPDIR/body" "$DEVBIN_TEST_TMPDIR/want"
  printf '\n## [4.0.0] - unreleased\n\n\n' >>"$PROJ/CHANGELOG.md"
  run notes_body "$PROJ" 4.0.0
  assert_failure
  assert_output_contains "the [4.0.0] section of CHANGELOG.md is empty"
}

# AT-2.2
@test "changelog: there are no views, so views and views_check print nothing and succeed, and a release owns CHANGELOG.md" {
  mkchangelog
  notes_select changelog "" demo
  local before
  before="$(tree_sum "$PROJ")"
  run notes_views "$PROJ"
  assert_success
  assert_output ""
  run notes_views_check "$PROJ"
  assert_success
  assert_output ""
  [ "$before" = "$(tree_sum "$PROJ")" ]
  run notes_paths "$PROJ" 2.0.0
  assert_output "CHANGELOG.md"
  run notes_where 2.0.0
  assert_output "## [2.0.0] heading in CHANGELOG.md"
}

# ---- command -----------------------------------------------------------------

# mknotescmd -- $PROJ/bin/notes, a notes.run that records where it ran and what it
# was asked, and REFUSES a verb it does not know: a stub accepting anything would
# prove only that something was called.
mknotescmd() {
  cat >"$PROJ/bin/notes" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$PWD" "$*" >>calls.log
case "${1:-}" in
  state) if [ -f dated ]; then printf 'dated %s\n' "$(cat dated)"; else printf 'open\n'; fi ;;
  date) [ $# -eq 3 ] || exit 9; printf '%s' "$3" >dated; printf 'notes/current.md\n' ;;
  body) printf 'the body for %s\n\n\n' "$2" ;;
  views) printf 'docs/NOTES.md\n' ;;
  views-check) printf 'current docs/NOTES.md\nSTALE docs/INDEX.md\n' ;;
  paths) printf 'notes/current.md\ndocs/NOTES.md\n' ;;
  *) printf 'stub: unknown verb: %s\n' "$*" >&2; exit 2 ;;
esac
STUB
  chmod +x "$PROJ/bin/notes"
}

# AT-2.3
@test "command: notes.run runs at the root with each verb and its arguments" {
  mknotescmd
  notes_select command bin/notes demo
  run notes_state "$PROJ" 1.0.0
  assert_output "open"
  run notes_date "$PROJ" 1.0.0 2026-09-17
  assert_success
  assert_output "notes/current.md"
  run notes_views "$PROJ"
  assert_output "docs/NOTES.md"
  run notes_views_check "$PROJ"
  assert_success
  assert_output "current docs/NOTES.md
STALE docs/INDEX.md"
  run notes_paths "$PROJ" 1.0.0
  assert_output "notes/current.md
docs/NOTES.md"
  local line
  for line in "state 1.0.0" "date 1.0.0 2026-09-17" "views" "views-check" "paths 1.0.0"; do
    grep -qxF "$PROJ|$line" "$PROJ/calls.log" || fail "notes.run was not called at the root as: $line"
  done
}

# AT-2.3
@test "command: the body keeps its trailing newlines" {
  mknotescmd
  notes_select command bin/notes demo
  notes_body "$PROJ" 1.0.0 >"$DEVBIN_TEST_TMPDIR/body"
  printf 'the body for 1.0.0\n\n\n' >"$DEVBIN_TEST_TMPDIR/want"
  cmp "$DEVBIN_TEST_TMPDIR/body" "$DEVBIN_TEST_TMPDIR/want"
}

# AT-2.3
@test "command: notes.run is split into words and never eval'd" {
  mknotescmd
  cd "$PROJ"
  notes_select command 'bin/notes; touch pwned' demo
  run notes_state "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "notes.run failed: bin/notes; touch pwned state 1.0.0"
  notes_select command 'bin/notes $(touch pwned)' demo
  run notes_state "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "stub: unknown verb: \$(touch pwned) state 1.0.0"
  [ ! -e "$PROJ/pwned" ] || fail "notes.run was evaluated by a shell"
  [ ! -e "$PROJ/state" ]
}

# AT-2.3
@test "command: an answer in any other shape is refused, naming what was printed" {
  mknotescmd
  cat >"$PROJ/bin/bad" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'released\n' ;;
  paths) printf '/etc/passwd\n' ;;
  views) printf 'docs/../../outside.md\n' ;;
  views-check) printf 'fresh docs/NOTES.md\n' ;;
  body) printf '   \n' ;;
esac
STUB
  chmod +x "$PROJ/bin/bad"
  notes_select command bin/bad demo
  run notes_state "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "printed 'released'"
  run notes_paths "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "absolute path: /etc/passwd"
  run notes_views "$PROJ"
  assert_failure
  assert_output_contains "leaves the project root: docs/../../outside.md"
  run notes_views_check "$PROJ"
  assert_failure
  assert_output_contains "printed 'fresh docs/NOTES.md'"
  run notes_body "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "printed nothing"

  # Four more shapes, each its own refusal, which no stub reached: date's path
  # check, views with a surrounding space, views-check with no path, and paths
  # printing nothing (ST0007 WP-02). state answers open here, so
  # dating gets as far as the command's answer.
  cat >"$PROJ/bin/worse" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'open\n' ;;
  date) printf '/etc/hosts\n' ;;
  views) printf ' docs/NOTES.md\n' ;;
  views-check) printf 'current\n' ;;
  paths) ;;
esac
STUB
  chmod +x "$PROJ/bin/worse"
  notes_select command bin/worse demo
  run notes_date "$PROJ" 1.0.0 2026-09-17
  assert_failure
  assert_output_contains "notes.run date printed an absolute path: /etc/hosts"
  run notes_views "$PROJ"
  assert_failure
  assert_output_contains "notes.run views printed a path with surrounding space: ' docs/NOTES.md'"
  run notes_views_check "$PROJ"
  assert_failure
  assert_output_contains "notes.run views-check printed 'current' with no path"
  run notes_paths "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "notes.run paths 1.0.0 printed nothing -- a release owns at least its note"

  # A state that says dated without a date is no answer either.
  cat >"$PROJ/bin/undated" <<'STUB'
#!/usr/bin/env bash
printf 'dated someday\n'
STUB
  chmod +x "$PROJ/bin/undated"
  notes_select command bin/undated demo
  run notes_state "$PROJ" 1.0.0
  assert_failure
  assert_output_contains "printed 'dated someday'"
}

# AT-2.3
@test "command: views and views-check answer none for no views, and silence, none beside a path, or none twice is refused naming the verb" {
  # A notes.run with no views arm printed nothing and exited 0, which read as
  # "generates no views", so release check passed over a view it never compared
  # (ST0007 WP-02).
  cat >"$PROJ/bin/views" <<'STUB'
#!/usr/bin/env bash
case "$ANSWER" in
  none) printf 'none\n' ;;
  silent) ;;
  beside) printf 'none\ndocs/NOTES.md\n' ;;
  twice) printf 'none\nnone\n' ;;
esac
STUB
  chmod +x "$PROJ/bin/views"
  notes_select command bin/views demo
  export ANSWER=none
  run notes_views "$PROJ"
  assert_success
  assert_output ""
  run notes_views_check "$PROJ"
  assert_success
  assert_output ""
  local row want verb
  for row in "silent|printed nothing -- a project with no views answers none" "beside|printed none beside other lines -- none is the whole answer" "twice|printed none beside other lines -- none is the whole answer"; do
    export ANSWER="${row%%|*}"
    want="${row#*|}"
    for verb in notes_views notes_views_check; do
      run "$verb" "$PROJ"
      assert_failure
      assert_output_contains "$want"
    done
  done
  unset ANSWER
}

# AT-2.3
@test "release check under notes.kind command refuses a notes.run that answers views-check with nothing, never calling it no views" {
  local proj
  proj="$(mkproj cmdproj <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  notes:
    kind: command
    run: bin/notes
YAML
  )"
  cat >"$proj/bin/notes" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'open\n' ;;
esac
STUB
  chmod +x "$proj/bin/notes"
  printf '1.0.0\n' >"$proj/VERSION"
  run devbin_run "$proj" release check
  [ "$status" -eq 1 ]
  assert_output_contains "notes.run views-check printed nothing -- a project with no views answers none"
  refute_output_contains "generates no views, so none were compared"
}

# AT-2.4
@test "dating an absent note is refused in the same words for every kind" {
  # The dating rules are stated once, in notes_date. While each kind carried its
  # own copy they drifted: the command kind's refusal alone never said what to do.
  cat >"$PROJ/bin/absent" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'absent\n' ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$PROJ/bin/absent"
  local kind notes_run where
  for kind in releases changelog command; do
    notes_run=""
    [ "$kind" != command ] || notes_run=bin/absent
    notes_select "$kind" "$notes_run" demo
    where="$(notes_where 1.0.0)"
    run notes_date "$PROJ" 1.0.0 2026-09-17
    assert_failure
    assert_output_contains "there is no $where to date -- write the note before the release"
  done
}

# AT-2.4
@test "a date that did not take is refused, not reported done" {
  # notes_date reads every write back through notes_state. A writer that says it
  # dated the note and changed nothing is the case the read-back exists for.
  cat >"$PROJ/bin/nodate" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) printf 'open\n' ;;
  date) printf 'notes/current.md\n' ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$PROJ/bin/nodate"
  notes_select command bin/nodate demo
  run notes_date "$PROJ" 1.0.0 2026-09-17
  assert_failure
  assert_output_contains "dating the note for 1.0.0 did not take -- it reads: open"
  refute_output_contains "notes/current.md"
}

# ============================================================================
# THE VERBS, THROUGH bin/devbin release, FOR THE KINDS WITHOUT VIEWS
# ============================================================================

# changelog_project -- a fixture enabling release with notes.kind: changelog.
changelog_project() {
  mkproj clproj <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  notes:
    kind: changelog
YAML
}

# AT-2.2
@test "release notes under notes.kind changelog says it generates no views and writes nothing" {
  local proj before
  proj="$(changelog_project)"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- first\n' >"$proj/CHANGELOG.md"
  before="$(tree_sum "$proj")"
  run devbin_run "$proj" release notes
  assert_success
  assert_output_contains "notes.kind changelog generates no views, so nothing was written"
  [ "$before" = "$(tree_sum "$proj")" ]
}

# AT-2.2
@test "release check under notes.kind changelog says no views were compared, never that they are current, and still checks the version's heading" {
  local proj
  proj="$(changelog_project)"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '# Changelog\n\n## [0.9.0] - 2026-01-01\n\n- older\n' >"$proj/CHANGELOG.md"
  run devbin_run "$proj" release check
  [ "$status" -eq 1 ]
  assert_output_contains "generates no views, so none were compared"
  refute_output_contains "view(s) current"
  assert_output_contains "there is no ## [1.0.0] heading in CHANGELOG.md"
  printf '\n## [1.0.0] - unreleased\n\n- new\n' >>"$proj/CHANGELOG.md"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "the note for 1.0.0 is open"
}

# AT-2.4
@test "release notes refuses a malformed release: block before writing anything" {
  # The bad key is one the provider does NOT read, with a kind it accepts, so
  # validation is the only thing that can stop this: a malformed block read as
  # its defaults would regenerate the views. A bad notes.kind would be refused by
  # notes_select as well, and could not tell the two apart.
  local proj
  proj="$(mkproj badproj <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  notes:
    kind: releases
  object: github
YAML
  )"
  mkdir -p "$proj/RELEASES"
  printf 'version: 0.1.0\ndate: 2026-01-01\nheadline: h\nstatus: released\n\n## Added\n\n- x\n' >"$proj/RELEASES/0.1.0.md"
  run devbin_run "$proj" release notes
  [ "$status" -eq 1 ]
  assert_output_contains 'release.object: "github" must be local, ci or none'
  [ ! -e "$proj/CHANGELOG.md" ]
  [ ! -e "$proj/RELEASES.md" ]
}

# AT-2.4
@test "release check names a version it cannot read rather than looking up a note for it" {
  # No VERSION at all: read_version answers `unknown`, which is no version.
  mknote 0.1.0
  run_in_project "$PROJ" release notes
  rm "$PROJ/VERSION"
  run_in_project "$PROJ" release check
  [ "$status" -eq 1 ]
  assert_output_contains "version reads 'unknown', which is not X.Y.Z"
  # RATHER THAN LOOKING IT UP: without this line a check that refused the version
  # and then asked for its note anyway still passed (ST0007 WP-02).
  refute_output_contains "the note for unknown"
}

# AT-2.3
@test "command: notes.run's words are glob patterns matched at the root it answers for (0082)" {
  # The pattern names bin/notes without spelling it, so it resolves only if the
  # match happened at the root being asked about. The test stands in the tmpdir
  # above it, which holds no bin/ at all -- so a site globbing where the caller
  # stands would hand the stub's own name to the shell as written and fail.
  mknotescmd
  notes_select command 'bin/n*tes' demo
  run notes_state "$PROJ" 1.0.0
  assert_success
  assert_output "open"
  grep -qxF "$PROJ|state 1.0.0" "$PROJ/calls.log" ||
    fail "notes.run was not called at the root: $(cat "$PROJ/calls.log" 2>/dev/null)"
}

# AT-2.3
@test "command: notes.run's words are matched under devbin's own glob state, not an inherited one (0082)" {
  # THIS ARM EXISTS BECAUSE A MUTANT SURVIVED, AND THE FIRST ARM WRITTEN FOR IT
  # WAS VACUOUS. Taking this site back to the old `$_notes_run "$verb"` killed
  # nothing: the old expansion globbed at the root too, since it sat inside the
  # same cd, so the glob arm above cannot separate the two readings. Nor can the
  # caller's IFS, which was the obvious next guess and is wrong --
  # _notes_command_out already pins IFS locally for its own `$*`, and has since
  # before 0082.
  #
  # What separates them is the glob state, which only run_words pins. A
  # developer with `SHELLOPTS=noglob` exported -- it is inherited by every child
  # bash -- made this site hand `bin/n*tes` to the shell as written, and every
  # release verb then failed on a machine that was the only one behaving that
  # way. The pattern here resolves ONLY if devbin turned globbing back on.
  mknotescmd
  local got
  got="$(env SHELLOPTS=noglob bash -c '
    . "$DEVBIN_LIB/helpers"
    . "$DEVBIN_LIB/release.notes"
    notes_select command "bin/n*tes" demo
    notes_state "$1" 1.0.0
  ' _ "$PROJ")" || fail "notes_state failed under an inherited SHELLOPTS=noglob: $got"
  [ "$got" = open ] || fail "notes_state answered '$got' under SHELLOPTS=noglob"
  grep -qxF "$PROJ|state 1.0.0" "$PROJ/calls.log" ||
    fail "notes.run did not reach the stub: $(cat "$PROJ/calls.log" 2>/dev/null)"
}
