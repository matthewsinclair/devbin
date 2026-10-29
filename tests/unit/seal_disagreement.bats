#!/usr/bin/env bats
# seal_disagreement.bats -- a return code and its seal are TWO claims about one
# run, and this is what happens when they contradict each other (issue 0016).
#
# The invariant the seal subsystem holds is "EMPTY means exactly a completed
# green run". This file tests the case where a gate says green and its own seal
# says otherwise. That case is not supposed to exist -- write_errors_file
# truncates on rc==0 -- which is precisely why it needs testing: an
# unconstructible state gets a check nobody can exercise, and a branch that can
# only be reasoned about is a branch that is wrong.
#
# THE CONTROLS CARRY THE WEIGHT HERE, more than usual. A predicate that fired on
# everything would pass every positive test in this file while making the runner
# useless, so the silent cases are asserted first and deliberately outnumber the
# loud ones.

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
}
teardown() {
  chmod -R u+w "$DEVBIN_TEST_TMPDIR" 2>/dev/null || true
  devbin_teardown
}

# ============================================================================
# CONTROLS -- the states that MUST stay silent
# ============================================================================

@test "a green run with an EMPTY seal is not a disagreement" {
  : >"$SEAL"
  run seal_disagreement_reason 0 "$SEAL"
  assert_success
  assert_output ""
}

@test "a RED run with a non-empty seal is not a disagreement" {
  # Red is SUPPOSED to seal non-empty -- write_errors_file enforces it. Reporting
  # that as a contradiction would fire on every genuine failure, which is the
  # single most likely way to get this check switched off.
  printf 'test foo FAILED\n' >"$SEAL"
  run seal_disagreement_reason 1 "$SEAL"
  assert_success
  assert_output ""
}

@test "a red run whose seal is still the in-flight marker is not a disagreement" {
  # A killed RED run. Both claims already say "not green", so there is nothing
  # to contradict -- and the rc is the one that reaches the caller.
  inflight_marker >"$SEAL"
  run seal_disagreement_reason 1 "$SEAL"
  assert_success
  assert_output ""
}

@test "an EMPTY errors path is not a disagreement (the keep_log=0 spool path)" {
  # open_run_log documents that keep_log=0 leaves `errors` empty and keeps no
  # companion. Without this guard every --no-out run would be refused.
  run seal_disagreement_reason 0 ""
  assert_success
  assert_output ""
}

@test "an ABSENT seal is not a disagreement" {
  run seal_disagreement_reason 0 "$DEVBIN_TEST_TMPDIR/never-created.errors"
  assert_success
  assert_output ""
}

# ============================================================================
# THE POSITIVE ARMS, AND THEY MUST BE DISTINGUISHABLE
# ============================================================================

@test "rc=0 beside an IN-FLIGHT seal is refused as an unsealed run" {
  inflight_marker >"$SEAL"
  run seal_disagreement_reason 0 "$SEAL"
  assert_success
  assert_output_contains "WITHOUT SEALING A VERDICT"
}

@test "rc=0 beside a seal RECORDING A FAILURE is refused as a false green" {
  printf 'test foo FAILED\n' >"$SEAL"
  run seal_disagreement_reason 0 "$SEAL"
  assert_success
  assert_output_contains "RECORDS A FAILURE"
}

@test "the positive arms say DIFFERENT things -- they send a reader to different places" {
  # One means "find the killed run"; the other means "find the failing test".
  # A single message for both would send someone hunting for a failure that does
  # not exist, so this asserts they do not collapse into each other.
  inflight_marker >"$SEAL"
  unsealed="$(seal_disagreement_reason 0 "$SEAL")"
  printf 'test foo FAILED\n' >"$SEAL"
  failed="$(seal_disagreement_reason 0 "$SEAL")"
  [ -n "$unsealed" ] || fail "the unsealed arm produced nothing"
  [ -n "$failed" ] || fail "the sealed-failure arm produced nothing"
  [ "$unsealed" != "$failed" ] || fail "both arms produced the same message: $unsealed"
}

# ============================================================================
# REACHABILITY -- driven through the REAL sealer, not a hand-built fixture
# ============================================================================
#
# Everything above builds the state by hand, which proves the predicate reads
# what it is given and proves nothing about whether real code ever produces it.
# write_errors_file truncates on rc==0, so the state looks unconstructible. It is
# not: when the truncation FAILS the function warns and returns 0, leaving the
# marker in place.

@test "CONTROL: the real sealer on a normal green run leaves a state that is NOT refused" {
  inflight_marker >"$SEAL"
  write_errors_file 0 "$LOG" "$SEAL" "$(grammar_for generic)"
  assert_file_empty "$SEAL"
  run seal_disagreement_reason 0 "$SEAL"
  assert_output ""
}

@test "REACHABLE: the real sealer that CANNOT write leaves a state that IS refused" {
  if [ "$(id -u)" = "0" ]; then
    skip "running as root -- chmod cannot make a file unwritable, so the state cannot be built"
  fi
  inflight_marker >"$SEAL"
  chmod 0444 "$SEAL"

  # The real function, unmodified, with a seal it cannot truncate.
  local rc=0
  write_errors_file 0 "$LOG" "$SEAL" "$(grammar_for generic)" >/dev/null 2>&1 || rc=$?

  # It returns 0 and warns. The warn is the entire defence today, and a note
  # cannot notice.
  [ "$rc" -eq 0 ] || fail "write_errors_file returned $rc -- the premise of this test has changed"
  [ -s "$SEAL" ] || fail "the seal was truncated after all -- this route is no longer reachable"

  run seal_disagreement_reason 0 "$SEAL"
  assert_output_contains "WITHOUT SEALING A VERDICT"
}

# ============================================================================
# print_run_verdict -- THE POINT OF THE CHANGE
# ============================================================================

@test "print_run_verdict REFUSES a verdict when the run contradicts its own seal" {
  inflight_marker >"$SEAL"
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "REFUSING A VERDICT"
}

@test "print_run_verdict says NOTHING extra on an ordinary green run" {
  # The overwhelmingly common case. If this ever fails, every green run in every
  # consuming project grew a scary line, and the check gets removed rather than
  # fixed.
  : >"$SEAL"
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "verdict:"
  refute_output_contains "REFUSING A VERDICT"
}

@test "print_run_verdict says NOTHING extra on an ordinary red run" {
  printf 'test foo FAILED\n' >"$SEAL"
  run print_run_verdict 1 1 "$LOG" "$SEAL"
  assert_success
  assert_output_contains "full log:"
  refute_output_contains "REFUSING A VERDICT"
}

@test "THE SINGLE-GATE PATH: the refusal needs NO ledger -- this is what the aggregate check could not reach" {
  # DEVBIN_SEAL_LEDGER is exported by run_all and by nothing else, so the
  # ledger-based block only ever sees `<cmd> all`. The one instance of this class
  # on record (issue 0015) was a single gate. This asserts the check survives
  # with no ledger in the environment at all.
  unset DEVBIN_SEAL_LEDGER
  inflight_marker >"$SEAL"
  run print_run_verdict 0 1 "$LOG" "$SEAL"
  assert_output_contains "REFUSING A VERDICT"
}

@test "ANNOTATE, NEVER SUPPRESS: a red that also disagrees still reports as red" {
  # A guard that quietly downgraded a failure would be a bypass wearing a safety
  # label. This drives the red path and asserts the red survives.
  printf 'test foo FAILED\n' >"$SEAL"
  run print_run_verdict 1 1 "$LOG" "$SEAL"
  assert_output_contains "full log:"
  assert_output_contains "exit 1"
}

@test "print_run_verdict returns 0 regardless -- it reports, it does not decide" {
  inflight_marker >"$SEAL"
  print_run_verdict 0 1 "$LOG" "$SEAL" >/dev/null 2>&1
  # A reporter that changed a run's exit status would make the seal subsystem's
  # verdict depend on whether anyone printed it.
  [ "$?" -eq 0 ] || fail "print_run_verdict altered the run's status"
}

# ============================================================================
# THE AGGREGATE FACE still works, and classifies NOTHING itself
# ============================================================================

@test "seal_disagreements finds a disagreeing row in a ledger" {
  inflight_marker >"$SEAL"
  ledger="$DEVBIN_TEST_TMPDIR/ledger"
  printf '0\ttest rust\t%s\n' "$SEAL" >"$ledger"
  run seal_disagreements "$ledger"
  assert_output_contains "test rust"
  assert_output_contains "WITHOUT SEALING A VERDICT"
}

@test "seal_disagreements is silent on a ledger of honest rows" {
  : >"$SEAL"
  local red="$DEVBIN_TEST_TMPDIR/red.errors"
  printf 'test foo FAILED\n' >"$red"
  ledger="$DEVBIN_TEST_TMPDIR/ledger"
  {
    printf '0\ttest rust\t%s\n' "$SEAL"
    printf '1\ttest bats\t%s\n' "$red"
  } >"$ledger"
  run seal_disagreements "$ledger"
  assert_output ""
}

@test "seal_failures names ONLY the failed rows, now that green rows are recorded too" {
  # record_seal stopped early-returning on rc==0, so the ledger holds green rows.
  # If seal_failures had not learned to filter, every green gate would be
  # reported as a failure -- the loudest possible regression, which is why it
  # gets its own arm rather than being assumed from the disagreement tests.
  : >"$SEAL"
  local red="$DEVBIN_TEST_TMPDIR/red.errors"
  printf 'boom\n' >"$red"
  ledger="$DEVBIN_TEST_TMPDIR/ledger"
  {
    printf '0\tgreen gate\t%s\n' "$SEAL"
    printf '1\tred gate\t%s\n' "$red"
  } >"$ledger"
  run seal_failures "$ledger"
  assert_output_contains "red gate"
  refute_output_contains "green gate"
}

@test "record_seal writes rc as the FIRST field, and writes green gates too" {
  export DEVBIN_SEAL_LEDGER="$DEVBIN_TEST_TMPDIR/ledger"
  : >"$DEVBIN_SEAL_LEDGER"
  : >"$SEAL"
  record_seal 0 "green gate" "$SEAL"
  # A green row must EXIST -- its absence is what made a false green
  # unrepresentable before this change.
  assert_file_contains "$DEVBIN_SEAL_LEDGER" "green gate"
  run head -c 2 "$DEVBIN_SEAL_LEDGER"
  assert_output_matches '^0'
}

# ============================================================================
# STRUCTURE -- one home, or the two faces drift apart again
# ============================================================================

@test "the two-state classification has exactly ONE home in the source" {
  # It used to live only inside the ledger loop, which is exactly why the
  # single-gate path had no classification available to it. If a second copy
  # appears, that is the same defect returning.
  local n
  n="$(grep -c 'WITHOUT SEALING A VERDICT' "$DEVBIN_LIB_DIR/runlog")"
  [ "$n" -eq 1 ] || fail "expected 1 home for the unsealed-run message, found $n"
}

@test "the in-flight marker still has exactly one home" {
  local n
  n="$(grep -c 'run in flight (or aborted before sealing)' "$DEVBIN_LIB_DIR/runlog")"
  [ "$n" -eq 1 ] || fail "expected 1 home for the in-flight marker, found $n"
}
