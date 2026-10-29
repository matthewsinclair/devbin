#!/usr/bin/env bats
# heartbeat.bats -- the run_gate heartbeat.
#
# It fixes no defect. It makes correct behaviour legible, and the reason that is
# worth code is measured: repeated "is this hung?" questions, every one about a
# correctly-working operation, and one of them a cargo build-lock wait -- the
# invisible wait that makes a caller fork CARGO_TARGET_DIR and costs 52G.
# `check targetdir` bans the fork; this makes the wait visible. Both halves or
# neither.
#
# THE LOAD-BEARING TESTS HERE ARE THE NEGATIVE ONES. A heartbeat that leaked
# into the captured stream could move a verdict (grammars COUNT lines in the
# log), and a heartbeat that clobbered $? would hand every gate the wrong
# answer. Those are what the rest of the file exists to protect.
#
# THE GATES HERE BEAT AT A FRACTION OF A SECOND (issue 0191). At whole seconds
# this file took 21 s on CI, nearly all of it waiting for beats.
#
# THE WHOLE FILE RUNS IN THE SERIAL LANE (issue 0190), by the file tag below.
# Several arms rest on a fraction of a second of scheduling: some need a beat
# inside a 1s gate, the fractional interval's arm reads its beats in windows of
# a second or less, and the chatty gate must see none, which a writer stalled
# for about 0.4s breaks. Tests running beside them could eat those margins, so
# the file runs after the parallel lane, one test at a time. The tag is the
# file's rather than each arm's, so an arm added here runs serially too.

# bats file_tags=serial

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  init_colors off
}
teardown() { devbin_teardown; }

# Drive a snippet under a REAL pty, with the libs loaded, and print its output.
# A pty is the whole point: the beat is gated on `[ -t 2 ]`, so a test without
# one proves only that it stays quiet.
under_pty() {
  local snippet="$1" f="$BATS_TEST_TMPDIR/drive.sh" ver
  {
    echo "export PROJECT_ROOT='$PROJECT_ROOT'"
    echo ". '$DEVBIN_LIB_DIR/helpers'"
    echo ". '$DEVBIN_LIB_DIR/runlog'"
    echo "init_colors off"
    echo "$snippet"
  } >"$f"
  # `< /dev/null` ON SCRIPT, AND IT IS NOT THE REDIRECT THAT HIDES HANGS.
  # Redirecting the TOOL's stdin is forbidden, because that hides terminal-only
  # hangs. Here it is `script`'s OWN stdin being redirected: script refuses to
  # start when it inherits a socket ("tcgetattr/ioctl: Operation not supported
  # on socket"), and without the redirect no pty could be had at all. The child
  # still receives the allocated pty -- `[ -t 2 ]` is true inside -- so nothing
  # is hidden from the code under test.
  #
  # TWO SPELLINGS, BECAUSE `script` IS ONE OF THE COMMANDS THAT DIFFERS MOST.
  # BSD takes the command as trailing operands after the file; util-linux takes
  # ONE file operand and wants the command in `-c`. The BSD form handed to GNU
  # is three operands where it accepts one, so it refuses and these tests
  # failed at THIS LINE in CI -- not in the code under test, which was never
  # reached on Linux at all. Recorded in devbin issue 0052.
  #
  # THEY FAILED RATHER THAN PASSING VACUOUSLY, WHICH IS THE ONLY REASON THIS WAS
  # RECOVERABLE. Had the helper degraded to running the snippet WITHOUT a pty,
  # every assertion here would have gone green while proving nothing -- the
  # header of this file says a test without a pty proves only that the beat
  # stays quiet. Keep it that way: no fallback to a non-pty run, ever. If no
  # spelling works, the test must break loudly.
  if ver="$(script --version 2>&1)" && grep -qi util-linux <<<"$ver"; then
    script -q -e -c "bash '$f'" /dev/null </dev/null 2>&1
  else
    script -q /dev/null bash "$f" </dev/null 2>&1
  fi
}

# ============================================================================
# THE TESTS THAT PROTECT THE VERDICT
# ============================================================================

@test "the gate's exit status survives a heartbeat running under a terminal" {
  under_pty '
    DEVBIN_HEARTBEAT_SECS=0.2 run_gate --suffix demo --out-dir logs -- sh -c "sleep 1; exit 7"
    echo "CAPTURED_RC=$?"
  ' >"$BATS_TEST_TMPDIR/out"

  # It must have beaten. The kill and wait that could overwrite $? run only for
  # a beat that started, and a beat line is the proof that one did: on main's
  # code, which turned 0.2 off, this arm passed with no beat at all.
  grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "no heartbeat fired, so the status assertion below would be vacuous"

  # 7, not 0 and not the heartbeat's own status. kill and wait both set $?, so
  # stopping the beat before PIPESTATUS is read would overwrite this.
  grep -q 'CAPTURED_RC=7' "$BATS_TEST_TMPDIR/out" ||
    fail "exit status did not survive: $(cat "$BATS_TEST_TMPDIR/out")"
}

@test "THE HEARTBEAT NEVER ENTERS THE CAPTURED LOG" {
  under_pty '
    DEVBIN_HEARTBEAT_SECS=0.2 run_gate --suffix demo --out-dir logs -- sleep 1
  ' >"$BATS_TEST_TMPDIR/out"

  # It must have beaten -- otherwise this test passes vacuously by testing a
  # heartbeat that never ran.
  grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "no heartbeat fired, so the log assertion below would be vacuous"

  # LATEST_DEMO.out is the stable pointer; the dated file is lowercase-suffixed.
  local log="$PROJECT_ROOT/logs/LATEST_DEMO.out"
  [ -e "$log" ] || fail "no log written"
  refute_file_contains "$log" "still running"
}

# ============================================================================
# IT BEATS ON SILENCE, NOT ON TIME
# ============================================================================

@test "a silent gate under a terminal announces that it is alive" {
  under_pty '
    DEVBIN_HEARTBEAT_SECS=0.2 run_gate --label "check demo" --suffix demo --out-dir logs -- sleep 1
  ' >"$BATS_TEST_TMPDIR/out"

  grep -q 'still running' "$BATS_TEST_TMPDIR/out" || fail "no heartbeat: $(cat "$BATS_TEST_TMPDIR/out")"
  grep -q 'check demo' "$BATS_TEST_TMPDIR/out" || fail "beat did not name the gate"
  grep -q 'quiet for' "$BATS_TEST_TMPDIR/out" || fail "beat did not report elapsed silence"
}

@test "a fractional interval beats in whole seconds, rounded down, and output restarts quiet but never elapsed (0191)" {
  # Beats every 0.25s over 1.6s of silence, one line, then 1s more. Before the
  # line, quiet is as long as the gate has run, so a beat from 1s on says
  # "quiet for 1s, 1s elapsed". After it, quiet starts again and elapsed runs
  # on: "quiet for 0s" with 1s or 2s elapsed, which no beat before the line can
  # say. Each window is wide enough for two beats or more, so one late beat
  # cannot empty it.
  #
  # WHAT IT CANNOT SEE: whether the times are read off the clock or summed from
  # the interval. Over these few beats the two differ by each beat's own work,
  # which stays well under a second.
  under_pty '
    DEVBIN_HEARTBEAT_SECS=0.25 run_gate --label "check demo" --suffix demo --out-dir logs -- \
      sh -c "sleep 1.6; echo one; sleep 1"
  ' >"$BATS_TEST_TMPDIR/out"

  grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "no heartbeat at a fractional interval: $(cat "$BATS_TEST_TMPDIR/out")"
  grep -q 'quiet for 1s, 1s elapsed' "$BATS_TEST_TMPDIR/out" ||
    fail "no beat counted the first second of silence: $(cat "$BATS_TEST_TMPDIR/out")"
  grep -q -E 'quiet for 0s, [12]s elapsed' "$BATS_TEST_TMPDIR/out" ||
    fail "quiet did not start again at the line, or elapsed started again with it: $(cat "$BATS_TEST_TMPDIR/out")"
}

@test "a CHATTY gate produces no heartbeat -- the operator can already see it is alive" {
  # A line every 0.1s against a 0.5s beat, never a line every 0.5s. The beat
  # samples the log's size once per interval, so a gate writing at the SAME
  # period is a race with the sampler: a write landing a hair late leaves one
  # window empty and the beat fires. That flaked on the macOS runner ("quiet for
  # 1s, 3s elapsed" between `working 3` and `working 4`, at a 1s beat and a line
  # every 1s), and the arm moved to a line every 0.2s. Five writes per window is
  # chatty by any clock drift. This beat stays slower than the rest of the
  # file's for the same reason: at 0.2s, five writes a window would be a line
  # every 0.04s. Its margin is a writer stalled for about 0.4s, half what it was
  # at 1s.
  under_pty '
    DEVBIN_HEARTBEAT_SECS=0.5 run_gate --suffix demo --out-dir logs -- \
      sh -c '"'"'i=1; while [ $i -le 12 ]; do echo working $i; i=$((i + 1)); sleep 0.1; done'"'"'
  ' >"$BATS_TEST_TMPDIR/out"

  grep -q 'working 12' "$BATS_TEST_TMPDIR/out" || fail "gate did not run to completion"
  ! grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "beat fired on a gate that was producing output: $(cat "$BATS_TEST_TMPDIR/out")"
}

# ============================================================================
# IT STAYS OUT OF THE WAY
# ============================================================================

@test "with no terminal attached there is no heartbeat at all" {
  DEVBIN_HEARTBEAT_SECS=0.2 run run_gate --suffix demo --out-dir logs -- sleep 0.5
  assert_success
  refute_output_contains "still running"
}

@test "DEVBIN_HEARTBEAT_SECS=0 disables it under a terminal, however the zero is written, and so does any interval under 0.1s" {
  # A zero, or an interval under 0.1s, that reached the loop would beat at
  # once or many times a second, so a short gate is enough to see it.
  # shellcheck disable=SC2016 # the driver script expands $v, not this shell
  under_pty '
    for v in 0 0.0 .0 0.09 0.001; do
      DEVBIN_HEARTBEAT_SECS="$v" run_gate --suffix demo --out-dir logs -- sleep 0.2
    done
  ' >"$BATS_TEST_TMPDIR/out"

  ! grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "beat fired while disabled: $(cat "$BATS_TEST_TMPDIR/out")"
}

@test "a malformed interval disables the beat rather than taking the gate down" {
  # The match refuses each of these before a beat starts. One that got past it
  # would reach sleep, which refuses it in turn and ends the beat (the arm
  # below holds that), so this arm holds the end state either way: the verdict
  # stands, no beat, and nothing said. No value here is one sleep would take:
  # 1e3 is a thousand seconds to both sleeps, and a match that let it through
  # would beat too late for any gate here to show.
  local values='banana 1.2.3 . -1'
  local -a each
  read -r -a each <<<"$values"
  # shellcheck disable=SC2016 # the driver script expands $v, not this shell
  under_pty '
    for v in '"$values"'; do
      DEVBIN_HEARTBEAT_SECS="$v" run_gate --suffix demo --out-dir logs -- sleep 0.2
      echo "CAPTURED_RC=$?"
    done
  ' >"$BATS_TEST_TMPDIR/out"

  [ "$(grep -c 'CAPTURED_RC=0' "$BATS_TEST_TMPDIR/out")" -eq "${#each[@]}" ] ||
    fail "a bad override changed a verdict: $(cat "$BATS_TEST_TMPDIR/out")"
  ! grep -q 'still running' "$BATS_TEST_TMPDIR/out" || fail "beat fired on a malformed interval"
  # AND IT MUST BE SILENT ABOUT IT. Before 0191 the guard's failure mode was a
  # beat that stayed off while a shell error ("integer expected", from
  # `[ "$interval" -gt 0 ]`) reached the operator's terminal: the behaviour
  # right, the noise not, and only this assertion told the two apart. The value
  # is now matched as text, and sleep's refusal is silenced, so the words a
  # test, an arithmetic expansion ("syntax error") or sleep ("invalid time
  # interval", or an illegal or invalid option for -1) would use are refused.
  ! grep -qiE 'integer expected|syntax error|invalid|illegal' "$BATS_TEST_TMPDIR/out" ||
    fail "a malformed interval leaked a complaint: $(cat "$BATS_TEST_TMPDIR/out")"
}

@test "an interval sleep refuses ends the beat, silently (0191)" {
  # The match reads how a value is written, not how big it is, and BSD's sleep
  # refuses anything above 2147483647, so such a value reaches the loop. A stub
  # sleep that refuses every interval stands in for it on every platform, and
  # the gate sleeps by its full path. The interval is whole, so main's guard
  # let it through as well, and there the loop spun: a beat and the stub's
  # complaint on every pass.
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  # shellcheck disable=SC2016 # the stub expands $1, not this shell
  printf '#!/bin/sh\necho "sleep: refused $1" >&2\nexit 1\n' >"$BATS_TEST_TMPDIR/stub/sleep"
  chmod +x "$BATS_TEST_TMPDIR/stub/sleep"
  under_pty "
    PATH='$BATS_TEST_TMPDIR/stub':\$PATH
    DEVBIN_HEARTBEAT_SECS=1 run_gate --suffix demo --out-dir logs -- /bin/sleep 0.5
    echo \"CAPTURED_RC=\$?\"
  " >"$BATS_TEST_TMPDIR/out"

  grep -q 'CAPTURED_RC=0' "$BATS_TEST_TMPDIR/out" ||
    fail "a refused interval changed the verdict: $(cat "$BATS_TEST_TMPDIR/out")"
  ! grep -q 'still running' "$BATS_TEST_TMPDIR/out" ||
    fail "the beat ran on after sleep refused its interval: $(cat "$BATS_TEST_TMPDIR/out")"
  ! grep -q 'refused' "$BATS_TEST_TMPDIR/out" ||
    fail "sleep's refusal reached the terminal: $(cat "$BATS_TEST_TMPDIR/out")"
}
