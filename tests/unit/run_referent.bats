#!/usr/bin/env bats
# run_referent.bats -- the project hands devbin an opaque string; devbin prints
# it beside its verdicts and knows nothing about it (issue 0049, consumer-filed).
#
# WHAT IS ACTUALLY UNDER TEST HERE, and it is not "is there a line". A verdict
# is written as a claim about the project -- `FAILED: rust` -- while what it
# measured is one tree at one instant, and the run pair records neither which
# tree that was nor whether it still exists. The incident: a red leg escalated
# as a regression, about a tree that had ceased to exist 41 seconds after the
# leg finished.
#
# THE ACCEPTANCE CONDITION IS A NEGATIVE, so most of this file is negatives.
# devbin must never parse the string. A referent that devbin can interpret is a
# devbin that has learned what a commit is, which reverses the layering rule that
# put the composing half in the consumer -- and nothing in a diff would say so.
# So the verbatim cases below are the point, and the presence cases are the
# cheap half.
#
# The sites are tested by different routes on purpose: the per-gate line
# by driving `print_run_verdict` directly, and the summary by running a real
# project end to end through `bin/devbin`. The summary is the site the incident
# actually happened on -- a human read `FAILED:` in an aggregate block -- and it
# is reachable only through dispatch, so a unit test of it would be a test of
# something else wearing its name.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  init_colors off
  cd "$DEVBIN_TEST_TMPDIR" || return 1
  SEAL="$DEVBIN_TEST_TMPDIR/run.errors"
  LOG="$DEVBIN_TEST_TMPDIR/run.out"
  printf 'some gate output\n' >"$LOG"
  : >"$SEAL"
  unset DEVBIN_RUN_REFERENT
}
teardown() { devbin_teardown; }

# A fixture project with devbin installed and a config written from stdin.

# ============================================================================
# THE DEFAULT: A CONSUMER THAT SAYS NOTHING GETS EXACTLY TODAY'S BEHAVIOUR
#
# These come first because this is the case every
# other project in the corpus is in. A referent line appearing where no project
# asked for one is not a cosmetic problem: it is devbin inventing a claim about
# a tree, which is the failure the whole issue is about, arrived at from the
# opposite side.
# ============================================================================

@test "UNSET: print_run_referent prints nothing at all" {
  unset DEVBIN_RUN_REFERENT
  run print_run_referent
  assert_success
  [ -z "$output" ] || fail "printed something with no referent set: [$output]"
}

@test "EMPTY: an exported but empty referent prints nothing" {
  # Distinct from unset, and a real state: a project composing the string from a
  # command that failed exports an empty value rather than none. Printing a bare
  # `measured:` there would assert a referent exists and decline to name it.
  export DEVBIN_RUN_REFERENT=""
  run print_run_referent
  assert_success
  [ -z "$output" ] || fail "printed something for an empty referent: [$output]"
}

@test "UNSET: a whole green verdict block carries no referent line" {
  unset DEVBIN_RUN_REFERENT
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "verdict:"
  refute_output_contains "measured:"
}

# ============================================================================
# VERBATIM -- THE ACCEPTANCE CONDITION
#
# Every string below is chosen to break something if anything is reading it.
# They are asserted BYTE-EXACT rather than with `contains`, because a parser
# that trimmed, quoted or normalised would still satisfy a containment check on
# most of them.
# ============================================================================

@test "VERBATIM: the real consumer form survives byte for byte" {
  export DEVBIN_RUN_REFERENT="b2173b1b +9 dirty -- THIS VERDICT DESCRIBES NO COMMIT"
  run print_run_referent
  assert_success
  [ "$output" = "measured: b2173b1b +9 dirty -- THIS VERDICT DESCRIBES NO COMMIT" ] ||
    fail "not verbatim: [$output]"
}

@test "VERBATIM: a referent that is not a sha and never could be" {
  # devbin has no idea what a commit is and this asserts it stays that way. A
  # consumer that is not a checkout at all still gets gates, and its referent
  # might be a build id, a hostname, or a sentence.
  export DEVBIN_RUN_REFERENT="built on ci-worker-7 from artefact bundle 44"
  run print_run_referent
  assert_success
  [ "$output" = "measured: built on ci-worker-7 from artefact bundle 44" ] ||
    fail "not verbatim: [$output]"
}

@test "VERBATIM: brackets survive -- a credo grammar reads these as an issue tag" {
  # The consumer asserts its own string is safe before exporting, because it is
  # the one that knows which grammars its logs are scanned by. devbin's job is
  # to not be the thing that mangles it.
  export DEVBIN_RUN_REFERENT="[deadbeef] +2 dirty"
  run print_run_referent
  assert_success
  [ "$output" = "measured: [deadbeef] +2 dirty" ] || fail "not verbatim: [$output]"
}

@test "VERBATIM: a colon-error shape survives -- this is the xcodebuild grammar" {
  export DEVBIN_RUN_REFERENT="src/a.c: error: not really"
  run print_run_referent
  assert_success
  [ "$output" = "measured: src/a.c: error: not really" ] || fail "not verbatim: [$output]"
}

@test "VERBATIM: globs and dollar signs are NOT expanded" {
  # A quoting slip would turn this into a directory listing or an empty string,
  # and either would read as a referent rather than as a bug.
  export DEVBIN_RUN_REFERENT='* $HOME `date` $(pwd)'
  run print_run_referent
  assert_success
  [ "$output" = 'measured: * $HOME `date` $(pwd)' ] || fail "not verbatim: [$output]"
}

@test "VERBATIM: leading and trailing whitespace is NOT trimmed" {
  # Trimming is the most innocuous-looking form of parsing and it is still
  # parsing: it requires deciding that the edges are insignificant, which is a
  # claim about what the string means.
  export DEVBIN_RUN_REFERENT="  spaced  "
  run print_run_referent
  assert_success
  [ "$output" = "measured:   spaced  " ] || fail "trimmed: [$output]"
}

# ============================================================================
# IT PRINTS ON GREEN -- THE HALF THAT EARNS IT
#
# A red gets investigated and self-corrects. A green certifying a tree nobody
# has is believed and never revisited. The green path is therefore the one
# worth the most tests, and it is the one a reporter is always tempted to keep
# quiet about.
# ============================================================================

@test "GREEN: an ordinary passing run carries its referent" {
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  : >"$SEAL"
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "verdict:"
  assert_output_contains "measured: cafe1234 clean"
  refute_output_contains "REFUSING A VERDICT"
}

@test "RED: a failing run carries its referent too" {
  export DEVBIN_RUN_REFERENT="cafe1234 +3 dirty"
  printf 'test foo FAILED\n' >"$SEAL"
  run print_run_verdict 1 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "measured: cafe1234 +3 dirty"
  assert_output_contains "full log:"
}

@test "THE TWO LINES TRAVEL TOGETHER: keep=0 prints NEITHER" {
  # Tied deliberately. A referent with no verdict beside it is noise; a verdict
  # with no referent is the defect. Tying them means there is no third state for
  # a later reader to have to reason about.
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  run print_run_verdict 0 0 "$LOG" "$SEAL"
  assert_success
  refute_output_contains "verdict:"
  refute_output_contains "measured:"
}

@test "ANNOTATE, NEVER SUPPRESS: a referent does not quieten the seal refusal" {
  # The referent says WHICH TREE. The refusal says the run has no trustworthy
  # verdict. They are independent claims and adding the first must not soften
  # the second -- a guard that quietly demoted a failure would be a bypass
  # wearing a safety label.
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  inflight_marker >"$SEAL"
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_output_contains "measured: cafe1234 clean"
  assert_output_contains "REFUSING A VERDICT"
}

@test "print_run_verdict still returns 0 with a referent set -- it reports, it does not decide" {
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  print_run_verdict 0 1 "$LOG" "$SEAL" >/dev/null 2>&1
  [ "$?" -eq 0 ] || fail "the referent changed the run's status"
}

# ============================================================================
# THE SUMMARY -- THE SITE THE INCIDENT HAPPENED ON
#
# Driven end to end through real dispatch, because `run_all` is only reachable
# that way and because the claim being made is about what a human sees on a
# screen after a multi-gate run.
# ============================================================================

@test "SUMMARY GREEN: 'all options passed' carries the referent" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
      two:
        summary: second
        run: echo ran-two
YAML
  )"
  DEVBIN_RUN_REFERENT="feedface clean" run devbin_run "$proj" gates all
  assert_success
  assert_output_contains "all gates options passed"
  assert_output_contains "measured: feedface clean"
}

@test "SUMMARY RED: the FAILED block carries the referent -- THIS IS THE FILED INCIDENT" {
  # A human read `FAILED: rust` in this exact block and had no way to know the
  # tree had moved under it. If only this test survives, keep this one.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
      two:
        summary: second
        run: exit 1
YAML
  )"
  DEVBIN_RUN_REFERENT="feedface +9 dirty" run devbin_run "$proj" gates all
  assert_failure
  assert_output_contains "FAILED:"
  assert_output_contains "measured: feedface +9 dirty"
}

# ============================================================================
# THE DECLARED COMPOSER -- how a project actually supplies the string
#
# `project.referent` names a command the PROJECT owns. It exists because there
# is no earlier project-owned place to export a variable: bin/devbin is
# devbin's file, so a consumer setting one there has forked the dispatcher to
# add a feature. Issue 0049 came from a consumer that did exactly that, and
# its manifest check flagged the edit; this field is what makes the fork
# unnecessary.
# ============================================================================

@test "DECLARED: project.referent's stdout becomes the referent" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  referent: echo "abc1234 clean"
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
YAML
  )"
  run devbin_run "$proj" gates all
  assert_success
  assert_output_contains "measured: abc1234 clean"
}

@test "DECLARED BUT FAILING: the referent says so, LOUDLY, rather than going quiet" {
  # ABSENT IS NOT CLEAN. An empty referent is indistinguishable from a project
  # that never declared one, so a composer that breaks would silently restore
  # the unreferenced verdict this whole mechanism closes. The failure has to be
  # visible in the place the referent would have been.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  referent: exit 3
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
YAML
  )"
  run devbin_run "$proj" gates all
  assert_output_contains "REFERENT UNAVAILABLE"
}

@test "DECLARED BUT FAILING: a broken composer does NOT fail the gate" {
  # A referent is a label on a verdict. If it could turn a green run red it
  # would be a gate, and nobody would keep a gate that reports on the weather.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  referent: exit 3
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
YAML
  )"
  run devbin_run "$proj" gates all
  assert_success
  assert_output_contains "all gates options passed"
}

@test "SUMMARY, NO REFERENT: a project that says nothing gets no line" {
  # The corpus default. Asserted end to end rather than at the unit, because the
  # regression that would matter is every other consuming project growing a line
  # it never asked for.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
YAML
  )"
  run devbin_run "$proj" gates all
  assert_success
  assert_output_contains "all gates options passed"
  refute_output_contains "measured:"
}

# ============================================================================
# THE ARTEFACT -- issue 0046, and the half everything above was missing
#
# Every test above this line asserts the line reaches a STREAM. None of them
# could have caught the filed defect, because the defect was that the stream
# was the only place it reached: `print_run_verdict` fires after the tee has
# closed and after the seal is written, so a nested gate's referent landed in
# its PARENT's log and a top-level gate's landed nowhere at all. Measured on
# two real `fullcycle` runs -- clean's own `.out` had no `measured:` line and
# the parent's had clean's twice.
#
# So these drive `run_gate` end to end and then read the FILES. A suite that
# only ever inspects `$output` cannot distinguish "printed" from "kept", which
# is the distinction the whole issue turns on.
# ============================================================================

@test "ARTEFACT GREEN: the run's OWN .out log carries the referent" {
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  run_gate --suffix demo --out-dir logs -- true
  assert_file_contains "$(readlink -f logs/LATEST_DEMO.out)" "measured: cafe1234 clean"
}

@test "ARTEFACT RED: a failing run's own .out log carries it too" {
  export DEVBIN_RUN_REFERENT="cafe1234 +3 dirty"
  run run_gate --suffix demo --out-dir logs -- false
  assert_failure
  assert_file_contains "$(readlink -f logs/LATEST_DEMO.out)" "measured: cafe1234 +3 dirty"
}

@test "ARTEFACT: the referent reaches the SEAL, via the tail fallback" {
  # The position of the write is what buys this: appended LAST, so a red run
  # with nothing a grammar can parse tails the log into `.errors` and takes the
  # referent with it. Written at the top of the log beside note_invocation it
  # would reach the `.out` and never here.
  export DEVBIN_RUN_REFERENT="cafe1234 +3 dirty"
  run run_gate --suffix demo --out-dir logs -- bash -c 'echo nothing a grammar can read; exit 7'
  assert_failure
  assert_file_contains "$(seal_of logs demo)" "measured: cafe1234 +3 dirty"
}

@test "ARTEFACT: no referent means no line in the log -- the corpus default" {
  # The same guard as the stream-side default tests, on the new sink. A line
  # appearing in every consumer's kept logs because devbin invented one is the
  # failure this issue is about, arrived at from the other side.
  unset DEVBIN_RUN_REFERENT
  run_gate --suffix demo --out-dir logs -- true
  refute_file_contains "$(readlink -f logs/LATEST_DEMO.out)" "measured:"
}

@test "ARTEFACT: an EMPTY referent writes nothing -- not a bare 'measured:'" {
  export DEVBIN_RUN_REFERENT=""
  run_gate --suffix demo --out-dir logs -- true
  refute_file_contains "$(readlink -f logs/LATEST_DEMO.out)" "measured:"
}

@test "ARTEFACT: the referent is TAGGED, so no grammar can seal a verdict out of it" {
  # THE REASON THE WRITE IS TAGGED, driven rather than asserted in a comment.
  # `[deadbeef] +2 dirty` is a credo issue tag to the credo grammar, which
  # matches unanchored AND sets inblock -- so an untagged referent would drag
  # the rest of the log into `.errors` and seal a verdict assembled out of
  # devbin's own annotation. A green run seals empty, and that is the assertion.
  export DEVBIN_RUN_REFERENT="[deadbeef] +2 dirty"
  run_gate --suffix demo --grammar credo --out-dir logs -- true
  assert_file_empty logs/LATEST_DEMO.errors
}

@test "ARTEFACT: the tag keeps the referent out of a RED credo seal's extract" {
  # The green case above passes for a second reason -- rc 0 truncates the seal
  # -- so it cannot fail if the tag is removed. This one can: a red run runs
  # the grammar for real over a log that contains the referent.
  export DEVBIN_RUN_REFERENT="[deadbeef] +2 dirty"
  run run_gate --suffix demo --grammar credo --out-dir logs -- \
    bash -c 'echo "[W] real credo finding"; exit 1'
  assert_failure
  assert_file_contains "$(seal_of logs demo)" "real credo finding"
  refute_file_contains "$(seal_of logs demo)" "deadbeef"
}

@test "the referent does not change a gate's exit status -- it labels, it does not decide" {
  export DEVBIN_RUN_REFERENT="cafe1234 clean"
  run run_gate --suffix demo --out-dir logs -- true
  assert_success
}
