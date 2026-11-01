#!/usr/bin/env bats
# runlog.bats - lib/runlog, the sealed-gate subsystem (WP-06)
#
# The invariant under test, everywhere below: THE SEAL IS EMPTY EXACTLY WHEN A
# COMPLETED RUN WAS GREEN. Every other property here exists to protect that one
# -- the in-flight marker (so an aborted run is not green), the never-empty-red
# enforcement (so a red run cannot read as green), the purge keepset (so a
# dangling pointer cannot read as green), and the per-run verdict path (so a
# concurrent peer's run cannot be mistaken for yours).
#
# A false green is the only defect class this subsystem cannot recover from
# afterwards, so the negative tests carry the weight.

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

# `seal_of` is in tests/lib/test_helper.bash -- other suites read seals too.

# ============================================================================
# THE SEAL INVARIANT
# ============================================================================

@test "a green run seals EMPTY" {
  run_gate --suffix demo --out-dir logs -- true
  assert_file_empty logs/LATEST_DEMO.errors
}

@test "a red run seals NON-EMPTY" {
  run run_gate --suffix demo --out-dir logs -- false
  assert_failure
  [ -s logs/LATEST_DEMO.errors ]
}

@test "the seal opens with an in-flight marker, so an aborted run is not green" {
  # The whole reason the companion is created at OPEN rather than at seal time.
  # A run killed between the two leaves this marker, and a reader testing
  # `[ -s seal ]` correctly sees not-green.
  open_run_log 1 logs demo >/dev/null
  [ -s "$errors" ]
  assert_file_contains "$errors" "run in flight"
  assert_file_contains "$errors" "no completed verdict"
}

@test "a red run with nothing parseable falls back to the log tail" {
  run run_gate --suffix demo --grammar mix --out-dir logs -- \
    bash -c 'printf "total gibberish no grammar matches this\n"; exit 7'
  assert_failure
  seal="$(seal_of logs demo)"
  assert_file_contains "$seal" "run FAILED (exit 7)"
  assert_file_contains "$seal" "log tail"
  assert_file_contains "$seal" "total gibberish"
}

@test "a red run whose log has vanished still seals non-empty" {
  # RED IS NEVER EMPTY, enforced rather than reasoned about: an empty companion
  # means "completed green run" to every reader of this seal.
  mkdir -p logs
  printf 'x\n' >logs/gone.out
  : >logs/gone.errors
  rm -f logs/gone.out
  write_errors_file 3 logs/gone.out logs/gone.errors "$(grammar_for generic)"
  [ -s logs/gone.errors ]
  assert_file_contains logs/gone.errors "run FAILED (exit 3)"
}

@test "a red run's seal reads in flight to every reader until its red text replaces it whole, from the failure blocks and from the log tail alike, and no temporary is left beside it (0306)" {
  # seal_state reads an EMPTY seal as a completed green run, and a seal written
  # in place was emptied by its redirect before the red text reached it. Each
  # pipeline that makes the red text ends in strip_ansi, run as a process of
  # its own, so redefined here it reads the seal as any reader would while the
  # text is made: by the time its body runs, a redirect onto the seal has
  # already emptied it.
  strip_ansi() {
    seal_state logs/run.errors >>logs/states
    cat
  }
  local line state left
  mkdir -p logs
  for line in 'Error: it broke' 'total gibberish no grammar matches this'; do
    printf '%s\n' "$line" >logs/run.out
    inflight_marker >logs/run.errors
    : >logs/states
    write_errors_file 1 logs/run.out logs/run.errors "$(grammar_for generic)"
    [ -s logs/states ] || fail "nothing read the seal while the red text was made from '$line'"
    while IFS= read -r state; do
      case "$state" in
        inflight | failed) ;;
        *) fail "a reader read the seal as $state while the red text was made from '$line'" ;;
      esac
    done <logs/states
    [ "$(seal_state logs/run.errors)" = failed ] || fail "the red run from '$line' sealed $(seal_state logs/run.errors)"
    left="$(compgen -G 'logs/run.errors.*')" || true
    [ -z "$left" ] || fail "a temporary was left beside the seal: $left"
  done
}

@test "a red seal that cannot be staged beside the seal is left unsealed, says so, and is never written in place, whether it held the in-flight marker or was empty (0306)" {
  # Written in place, the seal reads green until the red text lands, so that is
  # no fallback: where no temporary can be made beside it, the seal keeps the
  # in-flight marker, which no reader takes for green. An EMPTY seal reads
  # green already, so it takes the marker first.
  local start
  mkdir -p logs
  printf 'Error: it broke\n' >logs/run.out
  for start in marker empty; do
    if [ "$start" = marker ]; then inflight_marker >logs/run.errors; else : >logs/run.errors; fi
    chmod a-w logs
    if [ -w logs ]; then
      chmod u+w logs
      [[ -z "${CI:-}" ]] || fail "this CI runner writes a directory without its write bits (logs), so the seal that cannot be staged cannot be built: run the job as a user that cannot"
      skip "running with permissions that write a read-only directory: the seal that cannot be staged was NOT checked"
    fi
    run write_errors_file 1 logs/run.out logs/run.errors "$(grammar_for generic)"
    chmod u+w logs
    assert_success
    assert_output_contains "cannot seal logs/run.errors -- the run was RED"
    assert_output_contains "so it is left unsealed"
    [ "$(seal_state logs/run.errors)" = inflight ] || fail "the seal that started $start reads $(seal_state logs/run.errors), not in flight"
  done
}

@test "write_errors_file is a no-op when no companion is kept" {
  # The --no-out case: errors is empty, so there is nothing to seal.
  run write_errors_file 1 /dev/null "" "$(grammar_for generic)"
  assert_success
}

@test "a seal whose directory has vanished warns rather than failing silently" {
  # One source project's hardening, and the one the fold exists for: three of the four source
  # projects never grew it. A suite that sweeps a fixture directory sharing a
  # parent with the log dir takes the log dir with it.
  mkdir -p logs
  printf 'x\n' >logs/run.out
  run write_errors_file 0 logs/run.out logs/deeper/gone/run.errors "$(grammar_for generic)"
  assert_success
  refute_output_contains "cannot seal"
  # Now make the parent un-creatable: a FILE where the directory must be.
  printf 'not a dir\n' >logs/blocker
  run write_errors_file 0 logs/run.out logs/blocker/run.errors "$(grammar_for generic)"
  assert_success
  assert_output_contains "cannot seal"
  assert_output_contains "no verdict recorded"
}

# ============================================================================
# ANSI: THE LOG KEEPS ESCAPES, THE SEAL IS STRIPPED
# ============================================================================

@test "the run log keeps its escapes and the seal is stripped" {
  # .out is the raw record of what the tool emitted; .errors is the thing a
  # human greps and pastes. Stripping the seal is why RED IS NEVER EMPTY has to
  # be enforced separately -- an extraction that was all escapes strips to
  # nothing.
  run run_gate --suffix demo --out-dir logs -- \
    bash -c 'printf "\033[31mError: it broke\033[0m\n"; exit 1'
  assert_failure
  esc="$(printf '\033')"
  log="$(readlink -f logs/LATEST_DEMO.out)"
  seal="$(seal_of logs demo)"
  grep -q "$esc" "$log"
  ! grep -q "$esc" "$seal"
  assert_file_contains "$seal" "Error: it broke"
}

# ============================================================================
# PROMOTION
# ============================================================================

@test "note_promotion appends to the log as well as printing" {
  # The log half is the point: a promotion is decided after tee has closed, so
  # printing alone leaves the judgement in NEITHER artifact.
  mkdir -p logs
  : >logs/run.out
  run note_promotion logs/run.out "test mix" "no tests ran"
  assert_success
  assert_output_contains "PROMOTED TO FAILED (test mix): no tests ran"
  assert_file_contains logs/run.out "PROMOTED TO FAILED (test mix): no tests ran"
}

@test "a promoted run's reason reaches the seal" {
  # By construction rather than by luck: a promotion fires only when the tool
  # exited 0, so the grammar finds no failure blocks and write_errors_file falls
  # to the log tail -- which the promotion text landed in, last.
  mkdir -p logs
  printf 'all green here\n' >logs/run.out
  : >logs/run.errors
  note_promotion logs/run.out "test mix" "no tests ran -- check the path filter" >/dev/null
  write_errors_file 1 logs/run.out logs/run.errors "$(grammar_for mix)"
  assert_file_contains logs/run.errors "no tests ran -- check the path filter"
}

@test "a promotion that cannot be recorded warns" {
  run note_promotion /nonexistent/dir/run.out "gate" "reason"
  assert_success
  assert_output_contains "could not record the promotion reason"
}

# ============================================================================
# LATEST_* POINTERS
# ============================================================================

@test "LATEST pointers are created and resolve to this run's pair" {
  run_gate --suffix demo --out-dir logs -- true
  assert_symlink_exists logs/LATEST_DEMO.out
  assert_symlink_exists logs/LATEST_DEMO.errors
  # Relative targets, so `tail -f` follows from anywhere.
  [ "$(readlink logs/LATEST_DEMO.out)" = "$(basename "$(readlink -f logs/LATEST_DEMO.out)")" ]
}

@test "the verdict line names this run's own seal, never the LATEST pointer" {
  # The dangerous direction is the silent one: your run seals RED, a peer's
  # green run relinks a second later, and [ -s LATEST_*.errors ] reads GREEN.
  run run_gate --suffix demo --out-dir logs -- true
  assert_success
  assert_output_contains "verdict: $PROJECT_ROOT/logs/"
  assert_output_contains ".demo.errors"
  refute_output_contains "verdict: $PROJECT_ROOT/logs/LATEST"
}

# ============================================================================
# PURGE
# ============================================================================

@test "purge at a window of one deletes prior runs and keeps this run's pair" {
  # RUNLOG_KEEP_RUNS IS PINNED, NOT INHERITED. This test asserts deletion, so it
  # depends on the retention window being exactly one -- and until retention
  # existed that dependency was unstated, which meant the test would have gone
  # on passing while measuring something else the moment the default moved.
  export RUNLOG_KEEP_RUNS=1
  mkdir -p logs
  for stamp in 20200101-0101 20200102-0202; do
    printf 'old\n' >"logs/$stamp.demo.out"
    printf 'old\n' >"logs/$stamp.demo.errors"
  done
  run_gate --suffix demo --out-dir logs --purge -- true
  current="$(readlink -f logs/LATEST_DEMO.out)"
  assert_file_exists "$current"
  assert_file_not_exists logs/20200101-0101.demo.out
  assert_file_not_exists logs/20200102-0202.demo.errors
}

@test "purge never deletes a file a LATEST pointer still resolves to" {
  # THE HOLE THIS GUARDS: the pointer itself was always spared, so purging its
  # target leaves a DANGLING link -- and a dangling .errors reads GREEN to
  # [ -s ], so a run that FAILED reports success. Undetectable afterwards.
  mkdir -p logs
  printf 'peer run\n' >logs/20200101-0101.demo.out
  printf 'peer FAILED\n' >logs/20200101-0101.demo.errors
  ln -sfn 20200101-0101.demo.out logs/LATEST_DEMO.out
  ln -sfn 20200101-0101.demo.errors logs/LATEST_DEMO.errors
  local -a pointed=(logs/20200101-0101.demo.*)
  run purge_run_logs logs demo logs/some-other-run.demo.out
  assert_success
  assert_output_contains "retained ${#pointed[@]} file(s)"
  assert_file_exists logs/20200101-0101.demo.out
  assert_file_exists logs/20200101-0101.demo.errors
  # And the pointer still resolves -- no dangling link was created.
  [ -e logs/LATEST_DEMO.errors ]
}

@test "the keepset covers BOTH members of a pointed-at pair" {
  # Keeping LATEST.out's target while purging its .errors sibling recreates the
  # same hole: a run whose verdict file is gone reads green.
  mkdir -p logs
  printf 'x\n' >logs/20200101-0101.demo.out
  printf 'y\n' >logs/20200101-0101.demo.errors
  ln -sfn 20200101-0101.demo.out logs/LATEST_DEMO.out
  run latest_pointer_keepset logs demo
  assert_success
  assert_output_contains "logs/20200101-0101.demo.out"
  assert_output_contains "logs/20200101-0101.demo.errors"
}

@test "in_keepset does exact whole-line matching and tolerates a leading dash" {
  # A read loop rather than grep -Fx, which reads a leading `-` as options.
  set="alpha
-beta
gamma"
  in_keepset "alpha" "$set"
  in_keepset "-beta" "$set"
  run in_keepset "alph" "$set"
  assert_failure
  run in_keepset "" "$set"
  assert_failure
}

@test "purge-only keeps the newest kept run by mtime, not by name" {
  # Stamp names lie about order: a same-minute -SS collision file sorts
  # lexically BEFORE the plain stamp while being newer.
  # Window pinned to one for the same reason as the purge test above: this
  # asserts a deletion, so it must state the policy that permits it.
  export RUNLOG_KEEP_RUNS=1
  mkdir -p logs
  printf 'older\n' >logs/20200101-0101.demo.out
  printf 'older\n' >logs/20200101-0101.demo.errors
  printf 'newer\n' >logs/20200101-0101-1.demo.out
  printf 'newer\n' >logs/20200101-0101-1.demo.errors
  touch -t 202001010101 logs/20200101-0101.demo.out logs/20200101-0101.demo.errors
  run purge_only_run_logs logs demo
  assert_success
  assert_output_contains "keeping logs/20200101-0101-1.demo.out"
  assert_file_exists logs/20200101-0101-1.demo.out
  assert_file_not_exists logs/20200101-0101.demo.out
}

@test "purge with no kept log is refused rather than guessed at" {
  run refuse_purge_without_log 1 0
  assert_exit_code 1
  assert_output_contains "no kept run to purge against"
  run refuse_purge_without_log 1 1
  assert_success
  run refuse_purge_without_log 0 0
  assert_success
}

@test "run_gate refuses --purge with --no-out" {
  run run_gate --suffix demo --out-dir logs --no-out --purge -- true
  assert_exit_code 1
  assert_output_contains "no kept run to purge against"
}

# ============================================================================
# RETENTION
# ============================================================================
#
# WHAT THESE PROTECT: an intermittent failure is diagnosed by DIFFING a red run
# against the green one before it. Keeping one run destroys that differential at
# the moment it becomes interesting, and nothing downstream can recover it.
# The negative tests carry the weight here too -- a retention setting that fails
# OPEN deletes more than no retention at all.

@test "the retention window keeps the newest N runs and purges beyond it" {
  export RUNLOG_KEEP_RUNS=3
  mkdir -p logs
  # Five prior runs, mtimes strictly increasing so newest-3 is unambiguous.
  for i in 1 2 3 4 5; do
    printf 'run %s\n' "$i" >"logs/2020010$i-010$i.demo.out"
    printf 'run %s\n' "$i" >"logs/2020010$i-010$i.demo.errors"
    touch -t "2020010${i}010${i}" "logs/2020010$i-010$i.demo.out" "logs/2020010$i-010$i.demo.errors"
  done
  run purge_only_run_logs logs demo
  assert_success
  # Newest three survive.
  assert_file_exists logs/20200105-0105.demo.out
  assert_file_exists logs/20200104-0104.demo.out
  assert_file_exists logs/20200103-0103.demo.out
  # The two beyond the window do not.
  assert_file_not_exists logs/20200102-0102.demo.out
  assert_file_not_exists logs/20200101-0101.demo.out
}

@test "retention keeps BOTH members of a retained run, never a lone .out" {
  # THE HOLE THIS GUARDS is the one the LATEST keepset guards one level up: a
  # retained .out whose .errors was purged is a run with no seal, and an absent
  # .errors reads GREEN. Retention must keep pairs or it manufactures the exact
  # false green the rest of this file exists to prevent.
  export RUNLOG_KEEP_RUNS=2
  mkdir -p logs
  for i in 1 2 3; do
    printf 'run %s\n' "$i" >"logs/2020010$i-010$i.demo.out"
    printf 'FAILED %s\n' "$i" >"logs/2020010$i-010$i.demo.errors"
    touch -t "2020010${i}010${i}" "logs/2020010$i-010$i.demo.out" "logs/2020010$i-010$i.demo.errors"
  done
  run purge_only_run_logs logs demo
  assert_success
  assert_file_exists logs/20200103-0103.demo.out
  assert_file_exists logs/20200103-0103.demo.errors
  assert_file_exists logs/20200102-0102.demo.out
  assert_file_exists logs/20200102-0102.demo.errors
}

@test "retention orders by MTIME, not by name" {
  # Same trap purge_only_run_logs documents: a -SS collision file sorts
  # lexically BEFORE the plain stamp while being newer. A name-ordered
  # retention would keep the older file and purge the newer one.
  mkdir -p logs
  printf 'older\n' >logs/20200101-0101.demo.out
  printf 'older\n' >logs/20200101-0101.demo.errors
  printf 'newer\n' >logs/20200101-0101-1.demo.out
  printf 'newer\n' >logs/20200101-0101-1.demo.errors
  touch -t 202001010101 logs/20200101-0101.demo.out logs/20200101-0101.demo.errors
  run newest_run_stems logs demo 1
  assert_success
  assert_output_contains "20200101-0101-1.demo"
  refute_output_contains "logs/20200101-0101.demo"
}

@test "RUNLOG_KEEP_RUNS=0 is REFUSED and purges NOTHING" {
  # THE MEASURED BUG, and the reason the validator is a separate call from the
  # read. As one validating reader used `want="$(runlog_keep_runs)"`, `die`
  # killed only the substitution's subshell: the refusal printed, `want` was
  # left EMPTY, and the purge then ran with no retention at all -- DELETING MORE
  # ON A BAD SETTING THAN ON A GOOD ONE. Refusing is only half the contract;
  # the files still being there is the other half.
  export RUNLOG_KEEP_RUNS=0
  mkdir -p logs
  for i in 1 2 3; do
    printf 'run %s\n' "$i" >"logs/2020010$i-010$i.demo.out"
    printf 'run %s\n' "$i" >"logs/2020010$i-010$i.demo.errors"
  done
  run purge_only_run_logs logs demo
  assert_failure
  assert_output_contains "RUNLOG_KEEP_RUNS=0"
  # THE HALF THAT ACTUALLY MATTERS.
  assert_file_exists logs/20200101-0101.demo.out
  assert_file_exists logs/20200102-0102.demo.errors
  assert_file_exists logs/20200103-0103.demo.out
}

@test "a non-numeric RUNLOG_KEEP_RUNS is refused and purges nothing" {
  export RUNLOG_KEEP_RUNS=lots
  mkdir -p logs
  printf 'run\n' >logs/20200101-0101.demo.out
  printf 'run\n' >logs/20200101-0101.demo.errors
  run purge_only_run_logs logs demo
  assert_failure
  assert_output_contains "must be a whole number"
  assert_file_exists logs/20200101-0101.demo.out
}

@test "the purge line SAYS what the window kept, so a no-op purge is legible" {
  # A purge that deletes nothing because everything is inside the window looks
  # identical to a purge that found nothing, unless it says so.
  export RUNLOG_KEEP_RUNS=5
  mkdir -p logs
  printf 'run\n' >logs/20200101-0101.demo.out
  printf 'run\n' >logs/20200101-0101.demo.errors
  run purge_only_run_logs logs demo
  assert_success
  assert_output_contains "keeping the newest $RUNLOG_KEEP_RUNS run(s)"
}

# ============================================================================
# THE EXTRACTION GRAMMARS
# ============================================================================

@test "grammar_names lists every grammar devbin ships" {
  run grammar_names
  assert_success
  for g in mix credo cargo xcodebuild lua shell generic; do
    assert_output_contains "$g"
  done
}

@test "the mix grammar extracts failure blocks and their app header" {
  cat >log <<'OUT'
==> my_app
Compiling 3 files (.ex)
  1) test the thing (MyApp.ThingTest)
     test/thing_test.exs:12
     Assertion with == failed
Finished in 0.4 seconds
Result: 0/1 passed
OUT
  run log_awk "$(grammar_for mix)" log
  assert_success
  assert_output_contains "==> my_app"
  assert_output_contains "1) test the thing"
  assert_output_contains "Assertion with == failed"
  refute_output_contains "Compiling 3 files"
  refute_output_contains "Finished in"
}

@test "the credo grammar anchors on the ASCII severity tag" {
  cat >log <<'OUT'
Checking 42 source files ...

  Software Design
  [D] ↗ Nested modules could be aliased.
      lib/thing.ex:3:11
Analysis took 0.4 seconds
OUT
  run log_awk "$(grammar_for credo)" log
  assert_success
  assert_output_contains "Software Design"
  assert_output_contains "[D]"
  refute_output_contains "Checking 42 source files"
  refute_output_contains "Analysis took"
}

@test "the cargo grammar captures the failures roster and rustc diagnostics" {
  cat >log <<'OUT'
     Running unittests src/lib.rs (target/debug/deps/x-1)
failures:
    tests::it_adds
test result: FAILED. 1 passed; 1 failed
error[E0433]: failed to resolve: use of undeclared crate
OUT
  run log_awk "$(grammar_for cargo)" log
  assert_success
  assert_output_contains "failures:"
  assert_output_contains "tests::it_adds"
  assert_output_contains "test result: FAILED"
  assert_output_contains "error[E0433]"
}

@test "the xcodebuild grammar captures a swift-testing issue block" {
  # The grammar whose absence once INVERTED the seal: an assertion failure
  # sealed as 18 bytes while a codesign failure sealed 4.5KB of log tail.
  {
    printf '\342\227\207 Test "adds" started\n'
    printf '\342\234\230 Test "adds" recorded an issue at MathTests.swift:12\n'
    printf '    Expectation failed: 1 == 2\n'
    printf '\342\234\224 Test "subtracts" passed\n'
    printf '** TEST FAILED **\n'
  } >log
  run log_awk "$(grammar_for xcodebuild)" log
  assert_success
  assert_output_contains "recorded an issue at MathTests.swift:12"
  assert_output_contains "Expectation failed: 1 == 2"
  assert_output_contains "** TEST FAILED **"
  refute_output_contains "subtracts"
}

@test "the xcodebuild grammar truncates a runaway issue block and SAYS so" {
  # A truncated seal that does not say it truncated is the same silent-cap
  # failure in miniature.
  {
    printf '\342\234\230 Test "x" recorded an issue at A.swift:1\n'
    for i in $(seq 1 60); do printf '    detail line %s\n' "$i"; done
  } >log
  run log_awk "$(grammar_for xcodebuild)" log
  assert_success
  assert_output_contains "issue detail truncated at 40 lines"
  refute_output_contains "detail line 60"
}

@test "the lua grammar captures FAIL and ERROR blocks" {
  cat >log <<'OUT'
  PASS  spec/ok_spec.lua
  FAIL  spec/bad_spec.lua
        expected 1 to equal 2
3 test(s), 1 failure(s)
OUT
  run log_awk "$(grammar_for lua)" log
  assert_success
  assert_output_contains "FAIL  spec/bad_spec.lua"
  assert_output_contains "expected 1 to equal 2"
  refute_output_contains "PASS"
}

@test "the shell grammar captures bats failures and shellcheck findings" {
  cat >log <<'OUT'
1..3
ok 1 fine
not ok 2 broken
# (from function `assert_success')
#   `[ -s file ]' failed
ok 3 also fine

In lib/thing line 12:
  echo $unquoted
       ^-- SC2086: Double quote to prevent globbing.

OUT
  run log_awk "$(grammar_for shell)" log
  assert_success
  assert_output_contains "not ok 2 broken"
  assert_output_contains "assert_success"
  assert_output_contains "In lib/thing line 12"
  assert_output_contains "SC2086"
  refute_output_contains "ok 1 fine"
  refute_output_contains "ok 3 also fine"
}

@test "the generic grammar catches error-shaped lines without over-reaching" {
  cat >log <<'OUT'
building the thing
src/main.c:12:4: error: expected ';'
Error: could not link
everything is fine and this line mentions error in passing
FAILED: the build
OUT
  run log_awk "$(grammar_for generic)" log
  assert_success
  assert_output_contains "src/main.c:12:4: error"
  assert_output_contains "Error: could not link"
  assert_output_contains "FAILED: the build"
  # Anchored at line start, so a passing line merely CONTAINING "error" is not
  # swept in -- over-capture is recoverable, but not free.
  refute_output_contains "in passing"
}

@test "an unknown grammar falls back to generic and says so" {
  # Never an empty extraction: that would make every red run seal its log tail
  # and look identical.
  run grammar_for no-such-grammar
  assert_success
  assert_output_contains "unknown grammar 'no-such-grammar'"
  [ -n "$(grammar_for no-such-grammar 2>/dev/null)" ]
}

@test "grammar aliases resolve to the same source" {
  [ "$(grammar_for cargo)" = "$(grammar_for rust)" ]
  [ "$(grammar_for xcodebuild)" = "$(grammar_for swift)" ]
  [ "$(grammar_for shell)" = "$(grammar_for bats)" ]
}

# ============================================================================
# run_gate
# ============================================================================

@test "run_gate propagates the gate's own exit code" {
  run run_gate --suffix demo --out-dir logs -- bash -c 'exit 42'
  assert_exit_code 42
}

# ----------------------------------------------------------------------------
# The zero-count promotion (issue 0006). A tool that exits 0 having executed
# NOTHING is the false green this whole subsystem exists to refuse, and it is
# the one shape a tool's own exit code cannot carry.
# ----------------------------------------------------------------------------

@test "a gate that exits 0 having run no tests is promoted to failed" {
  # TAP with a zero plan and no results: what bats-shaped output looks like when
  # a filter matches nothing. The tool is happy; the run examined nothing.
  run run_gate --suffix demo --grammar shell --out-dir logs -- \
    bash -c 'printf "1..0\n"; exit 0'
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
}

@test "the promotion reason reaches the seal, not just the terminal" {
  # A terminal is not an artifact. The seal is what a later reader has.
  run_gate --suffix demo --grammar shell --out-dir logs -- \
    bash -c 'printf "1..0\n"; exit 0' || true
  assert_file_contains logs/LATEST_DEMO.errors "PROMOTED TO FAILED"
}

@test "a gate that actually ran tests is not promoted" {
  # The assertion that stops the fix from being "fail everything": a real run
  # with real results stays green.
  run run_gate --suffix demo --grammar shell --out-dir logs -- \
    bash -c 'printf "1..2\nok 1 alpha\nok 2 beta\n"; exit 0'
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "--allow-empty says the emptiness was intended" {
  run run_gate --suffix demo --grammar shell --out-dir logs --allow-empty -- \
    bash -c 'printf "1..0\n"; exit 0'
  assert_success
  assert_output_contains "no tests ran"
}

@test "a grammar with no counter never promotes" {
  # `generic` cannot count, so it must not guess. Promoting on "no countable
  # output" would fail every gate whose tool devbin does not have a reader for.
  run run_gate --suffix demo --grammar generic --out-dir logs -- \
    bash -c 'printf "some chatter\n"; exit 0'
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "a gate that is not a test run is not promoted for having no tests" {
  # THE ONE THAT NEARLY SHIPPED A REGRESSION. `check compile` declares the MIX
  # grammar -- it needs mix's failure reader -- but it is a compile, not a test
  # run, and it emits no trailer at all. `check clippy` is the same with cargo.
  # Counting off the grammar alone failed every successful compile.
  #
  # So a counter must separate "no trailer, this was not a test run" from
  # "trailer present and it says zero".
  run run_gate --suffix demo --grammar mix --out-dir logs -- \
    bash -c 'printf "Compiling 12 files (.ex)\n"; exit 0'
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "a cargo gate that is not a test run is not promoted either" {
  run run_gate --suffix demo --grammar cargo --out-dir logs -- \
    bash -c 'printf "    Checking devbin v0.1.0\n    Finished dev profile\n"; exit 0'
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "a test run whose trailer says zero IS promoted, trailer present" {
  # The other side of the same line: mix DID run tests and reported none
  # executed. Everything was excluded, which is an empty run.
  run run_gate --suffix demo --grammar mix --out-dir logs -- \
    bash -c 'printf "Result: 0 passed, 9 excluded\n"; exit 0'
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
}

@test "a green swift-testing run is counted, not promoted -- the glyphs are literals, not a byte class" {
  # The pass glyph is three bytes. Spliced into a bracket expression they
  # became a class of BYTES demanding a space-Test after the FIRST byte of a
  # glyph, which matches nothing: every green swift-testing suite counted 0
  # and was promoted to FAILED. Measured before fixing: the bracket form
  # counted 1 of 3 real lines.
  pass="$(printf '\342\234\224')"
  printf '%s Test "alpha" passed after 0.001 seconds.\n%s Test "beta" passed after 0.001 seconds.\n%s Test run with 2 tests passed after 0.010 seconds.\n' \
    "$pass" "$pass" "$pass" >st.log
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat st.log
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "an xcodebuild gate that is not a test run is not promoted" {
  # `** BUILD SUCCEEDED **`, no test system engaged -- the `check compile`
  # shape under this grammar. The counter's END printed unconditionally (no
  # seen gate, unlike every sibling), so a build-only run was promoted.
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- \
    bash -c 'printf "** BUILD SUCCEEDED **\n"; exit 0'
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "an xcodebuild run whose trailer says zero IS promoted, in either test system" {
  printf 'Executed 0 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds\n' >xc.log
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat xc.log
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"

  pass="$(printf '\342\234\224')"
  printf '%s Test run with 0 tests passed after 0.001 seconds.\n' "$pass" >st.log
  run run_gate --suffix demo2 --grammar xcodebuild --out-dir logs -- cat st.log
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
}

@test "a started-but-never-finished case is not an executed test" {
  # XCTest prints `started.` and `passed (...)` for the SAME case. Counting
  # every `Test Case ` line counted each test twice -- and counted a
  # started-then-crashed case as executed. Completions only.
  printf "Test Case '-[Suite thing]' started.\nExecuted 0 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds\n" >xc.log
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat xc.log
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
}

# The fixtures below are real xcodebuild output, captured by another estate and
# scrubbed to neutral names and placeholder paths, so no xcodebuild runs here.
# Each arm names the shape it reads (issue 0229).
XC_FIXTURES="$BATS_TEST_DIRNAME/../fixtures/xcodebuild"

@test "XCTest's indented Executed summary is a trailer, and its completions are the count (0229)" {
  # xcodebuild indents the summary with a tab and a space. Anchored at column 0
  # the rule never matched, so every XCTest-only run counted EMPTY.
  run log_awk "$(count_for xcodebuild)" "$XC_FIXTURES/xctest-one-test.txt"
  assert_success
  [ "$output" = 1 ] || fail "an XCTest run of one test counted '$output'"
}

@test "a swift-testing line led by U+200B is counted: a parameterized test is one test (0229)" {
  # A real run of 7 tests, one parameterized with 5 cases, whose result line
  # starts with a zero width space before the glyph. Without the strip it
  # counted 6.
  run log_awk "$(count_for xcodebuild)" "$XC_FIXTURES/swift-testing-parameterized.txt"
  assert_success
  [ "$output" = 7 ] || fail "a real 7-test run counted '$output'"
}

@test "a test action whose selection matched nothing counts zero, and its gate is promoted (0229)" {
  # The real empty selection: XCTest's indented zero summaries, no
  # swift-testing trailer, and ** TEST SUCCEEDED ** with exit 0. It sealed
  # passed, having run nothing.
  run log_awk "$(count_for xcodebuild)" "$XC_FIXTURES/empty-selection.txt"
  assert_success
  [ "$output" = 0 ] || fail "an empty selection counted '$output'"
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat "$XC_FIXTURES/empty-selection.txt"
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
  # And with no framework output at all, the TEST action's own trailer is
  # enough to make it a counted run of zero.
  local action
  for action in "TEST SUCCEEDED" "TEST FAILED" "TEST EXECUTE SUCCEEDED" "TEST EXECUTE FAILED"; do
    printf "** %s **\n" "$action" >xc.log
    run log_awk "$(count_for xcodebuild)" xc.log
    assert_success
    [ "$output" = 0 ] || fail "a bare $action counted '$output'"
  done
  # build-for-testing builds and reaches no test system.
  printf "** TEST BUILD SUCCEEDED **\n" >xc.log
  run log_awk "$(count_for xcodebuild)" xc.log
  assert_success
  [ -z "$output" ] || fail "build-for-testing counted '$output'"
  run run_gate --suffix demo2 --grammar xcodebuild --out-dir logs --allow-empty -- cat "$XC_FIXTURES/empty-selection.txt"
  assert_success
  assert_output_contains "no tests ran"
}

@test "a build-only run and a test action whose build failed stay uncounted (0229)" {
  # Neither reached a test system: the build-only shape is check compile's,
  # and the failed build fails on its exit code. Counting either as zero would
  # blame a compile on the filter.
  run log_awk "$(count_for xcodebuild)" "$XC_FIXTURES/build-only.txt"
  assert_success
  [ -z "$output" ] || fail "a build-only run counted '$output'"
  run log_awk "$(count_for xcodebuild)" "$XC_FIXTURES/test-action-build-failed.txt"
  assert_success
  [ -z "$output" ] || fail "a test action whose build failed counted '$output'"
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat "$XC_FIXTURES/build-only.txt"
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "a parallel XCTest run is counted, so its green is not promoted (0229)" {
  # Parallel testing writes each completion with a lower-case `case` and the
  # clone it ran on. SYNTHETIC, shaped on that form: no real parallel log was
  # captured. Missed, a green parallel run named no completion, and its
  # completed test action then promoted it as zero.
  {
    printf "Test case '-[DemoTests.WidgetTests testOne()]' passed on 'My Mac - Demo (1000)' (0.001 seconds)\n"
    printf "Test case '-[DemoTests.WidgetTests testTwo()]' passed on 'My Mac - Demo (1001)' (0.002 seconds)\n"
    printf '** TEST SUCCEEDED **\n'
  } >xc.log
  run log_awk "$(count_for xcodebuild)" xc.log
  assert_success
  [ "$output" = 2 ] || fail "a parallel run of two counted '$output'"
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat xc.log
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "a swift-testing issue line is not a completion: a failing test counts once (0229)" {
  # The issue line opens with the same glyph and `Test ` as the result line,
  # and a parameterized case's may carry the zero width space too.
  {
    printf '\342\234\230 Test "adds" recorded an issue at MathTests.swift:12:5: Expectation failed: 1 == 2\n'
    printf '\342\200\213\342\234\230 Test "adds" recorded an issue at MathTests.swift:14:5: Expectation failed: 2 == 3\n'
    printf '\342\234\230 Test "adds" failed after 0.001 seconds with 2 issues.\n'
    printf '\342\234\230 Test run with 1 test in 1 suite failed after 0.002 seconds with 2 issues.\n'
  } >st.log
  run log_awk "$(count_for xcodebuild)" st.log
  assert_success
  [ "$output" = 1 ] || fail "one failing test with two issues counted '$output'"
}

@test "the xcodebuild grammar seals a failure line led by U+200B (0229)" {
  # The same zero width space leads a parameterized test's result line, so a
  # failing one was dropped from the seal as well as from the count.
  {
    printf '\342\227\207 Test "adds" started.\n'
    printf '\342\200\213\342\234\230 Test "adds" with 3 test cases failed after 0.001 seconds with 1 issue.\n'
  } >log
  run log_awk "$(grammar_for xcodebuild)" log
  assert_success
  assert_output_contains 'Test "adds" with 3 test cases failed'
}

# A log byte that is not valid UTF-8, in a UTF-8 locale (issue 0231). macOS awk
# exits 2 at the first such byte on any regex, so the counter read the log as
# uncounted and an empty run sealed green. Each arm exports a UTF-8 LC_ALL, as
# a person's terminal has, and the log carries a latin1 0xE9.

@test "an empty run whose log holds a latin1 byte is promoted under a UTF-8 locale (0231)" {
  loc="$(utf8_locale)" || skip "no UTF-8 locale on this runner: the latin1 byte was NOT read under one"
  export LC_ALL="$loc"
  printf '1..0\n# caf\351, from a test\n' >tap.log
  run run_gate --suffix demo --grammar shell --out-dir logs -- cat tap.log
  assert_failure
  assert_output_contains "0 tests executed"
  assert_file_contains "$(seal_of logs demo)" "0 tests executed"
}

@test "a swift-testing log with a latin1 byte is counted by its glyphs as bytes, and promoted at zero (0231)" {
  loc="$(utf8_locale)" || skip "no UTF-8 locale on this runner: the latin1 byte was NOT read under one"
  export LC_ALL="$loc"
  { cat "$XC_FIXTURES/empty-selection.txt"; printf 'caf\351\n'; } >empty.log
  run run_gate --suffix demo --grammar xcodebuild --out-dir logs -- cat empty.log
  assert_failure
  assert_output_contains "0 tests executed"

  # The U+200B and glyph rules still match with the log read as bytes.
  { cat "$XC_FIXTURES/swift-testing-parameterized.txt"; printf 'caf\351\n'; } >st.log
  run log_awk "$(count_for xcodebuild)" st.log
  assert_success
  [ "$output" = 7 ] || fail "a 7-test run with a latin1 byte counted '$output'"
}

@test "a counter that fails is named in the output and the seal, never read as no trailer (0231)" {
  # A stand-in for an awk that fails all the same: the shell counter alone
  # exits 2. The run is green and ran a test, so only the counting is wrong.
  stand_in="$(count_for shell)"
  log_awk() {
    if [ "$1" = "$stand_in" ]; then
      printf 'awk: a stand-in failure\n' >&2
      return 2
    fi
    LC_ALL=C awk "$@" # log_awk's own body, lib/helpers
  }
  printf '1..1\nok 1 alpha\n' >tap.log
  run run_gate --suffix demo --grammar shell --out-dir logs -- cat tap.log
  assert_failure
  assert_output_contains "count could not be read (awk exited 2"
  assert_file_contains "$(seal_of logs demo)" "count could not be read"
  assert_file_contains "$(seal_of logs demo)" "awk: a stand-in failure"

  # --allow-empty accepts a count of zero, not one devbin could not read.
  run run_gate --suffix demo2 --grammar shell --out-dir logs --allow-empty -- cat tap.log
  assert_failure
  assert_output_contains "count could not be read"
}

@test "the promotion reason names escapes every caller can actually reach" {
  # Both routes are real now: gate_split_args carries --allow-empty from any
  # gate's command line, and `grammar: generic` is the per-gate declaration.
  # The reason once advised only --allow-empty at a time no built-in gate could
  # forward it -- following the advice handed the flag to mix/cargo as an
  # unknown argument.
  printf '1..0\n' >tap.log
  run run_gate --suffix demo --grammar shell --out-dir logs -- cat tap.log
  assert_failure
  assert_output_contains "grammar: generic"
  assert_output_contains "pass --allow-empty"
}

@test "a gate that FAILED is left alone -- the promotion is only for zero exits" {
  # rc is already red and write_errors_file tails the log. Promoting here would
  # overwrite a compile failure's evidence with a misleading "no tests ran".
  run run_gate --suffix demo --grammar shell --out-dir logs -- \
    bash -c 'printf "compile error\n"; exit 1'
  assert_exit_code 1
  refute_output_contains "PROMOTED TO FAILED"
}

@test "run_gate does not change the caller's errexit" {
  # A library function must not switch errexit on for a caller that turned it
  # off -- the first red gate would then kill a loop written to run every gate.
  run bash -c "
    set -uo pipefail
    set +e
    export DEVBIN_LIB='$DEVBIN_LIB_DIR' PROJECT_ROOT='$DEVBIN_TEST_TMPDIR'
    cd '$DEVBIN_TEST_TMPDIR'
    . '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/runlog'
    run_gate --suffix demo --out-dir logs -- false >/dev/null 2>&1
    case \"\$-\" in *e*) printf 'LEAKED errexit on\n' ;; *) printf 'errexit preserved off\n' ;; esac
    printf 'reached the end\n'"
  assert_success
  assert_output_contains "errexit preserved off"
  assert_output_contains "reached the end"
}

@test "run_gate keeps errexit ON for a caller that had it on" {
  run bash -c "
    set -euo pipefail
    export DEVBIN_LIB='$DEVBIN_LIB_DIR' PROJECT_ROOT='$DEVBIN_TEST_TMPDIR'
    cd '$DEVBIN_TEST_TMPDIR'
    . '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/runlog'
    set +e; run_gate --suffix demo --out-dir logs -- true >/dev/null 2>&1; set -e
    case \"\$-\" in *e*) printf 'errexit still on\n' ;; *) printf 'LOST errexit\n' ;; esac"
  assert_success
  assert_output_contains "errexit still on"
}

@test "run_gate keeps no companion with --no-out" {
  run run_gate --suffix demo --out-dir logs --no-out -- true
  assert_success
  assert_directory_not_exists logs
  refute_output_contains "verdict:"
}

@test "run_gate requires a suffix and a command" {
  run run_gate --out-dir logs -- true
  assert_exit_code 1
  assert_output_contains "--suffix is required"
  run run_gate --suffix demo --out-dir logs --
  assert_exit_code 1
  assert_output_contains "no command given"
}

@test "run_gate rejects an unknown option rather than treating it as the command" {
  run run_gate --suffix demo --bogus -- true
  assert_exit_code 1
  assert_output_contains "unknown option '--bogus'"
}

@test "run_gate accepts both --opt value and --opt=value" {
  run run_gate --suffix=demo --out-dir=logs --grammar=shell --label=spelled -- true
  assert_success
  assert_output_contains "spelled"
  assert_file_empty logs/LATEST_DEMO.errors
}

@test "run_gate runs a shell function as readily as an external command" {
  # How the check gates are written: they are functions in the handler, not
  # separate executables.
  my_gate() {
    printf 'gate ran\n'
    return 3
  }
  run run_gate --suffix demo --out-dir logs -- my_gate
  assert_exit_code 3
  assert_output_contains "gate ran"
}

# ============================================================================
# CONCURRENCY
# ============================================================================

@test "concurrent runs of one gate do not share or truncate a log" {
  # The corpus checked `[ -e ]` then truncated, which two runs starting in the
  # same minute both pass. Creation is O_EXCL now, so exactly one racer wins a
  # name and the losers walk to the next.
  run bash -c "
    set -uo pipefail
    export DEVBIN_LIB='$DEVBIN_LIB_DIR' PROJECT_ROOT='$DEVBIN_TEST_TMPDIR'
    cd '$DEVBIN_TEST_TMPDIR'
    for i in 1 2 3 4 5 6 7 8; do
      ( . '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/runlog'
        run_gate --suffix demo --out-dir logs -- printf \"run-\$i\\n\" ) >/dev/null 2>&1 &
    done
    wait
    printf 'logs=%s\n' \"\$(ls logs/*.demo.out | wc -l | tr -d ' ')\"
    printf 'distinct=%s\n' \"\$(cat logs/*.demo.out | grep -v '^devbin| ' | sort -u | wc -l | tr -d ' ')\"
    printf 'redseals=%s\n' \"\$(find logs -name '*.demo.errors' -size +0 | wc -l | tr -d ' ')\""
  assert_success
  # Eight runs, eight logs, eight distinct contents: none overwrote another.
  #
  # The distinct count reads the TOOL's lines only. Each log also carries
  # devbin's own invocation record, whose header and argv[0] are identical
  # across all eight -- counting those made this read 19 for eight
  # non-overlapping runs. The filter keeps the proxy measuring what the test
  # actually claims.
  assert_output_contains "logs=8"
  assert_output_contains "distinct=8"
  # And every one sealed green -- no run picked up a peer's log.
  assert_output_contains "redseals=0"
}

# ============================================================================
# THE SEAL LEDGER
# ============================================================================

@test "record_seal is a no-op with no ledger set, and records EVERY gate with its rc" {
  # THE CONTRACT CHANGED WITH issue 0016 AND THIS TEST IS THE OTHER END OF IT.
  # It used to assert that only FAILURES were recorded. That made the ledger
  # blind to the one disagreement that matters most: a gate that returned 0
  # while its seal records a failure. A ledger holding only the runs that already
  # said they failed cannot surface a green that should not be one -- so
  # record_seal now records every gate, and carries the rc as the first column
  # so seal_disagreements can compare the two.
  #
  # Left un-updated when the behaviour changed, it made the branch carry two
  # directly contradictory tests: this one, and seal_disagreement.bats asserting
  # the green gate IS recorded.
  mkdir -p logs
  : >logs/run.errors
  unset DEVBIN_SEAL_LEDGER
  run record_seal 1 "gate" logs/run.errors
  assert_success
  export DEVBIN_SEAL_LEDGER="$DEVBIN_TEST_TMPDIR/ledger"
  : >"$DEVBIN_SEAL_LEDGER"
  record_seal 0 "green gate" logs/run.errors
  assert_file_contains "$DEVBIN_SEAL_LEDGER" "green gate"
  record_seal 1 "red gate" logs/run.errors
  assert_file_contains "$DEVBIN_SEAL_LEDGER" "red gate"
  assert_file_contains "$DEVBIN_SEAL_LEDGER" "$PROJECT_ROOT/logs/run.errors"
  # THE RC IS THE FIRST COLUMN, and it is the whole reason greens are recorded.
  run awk -F'\t' '{print $1}' "$DEVBIN_SEAL_LEDGER"
  assert_output_contains "0"
  assert_output_contains "1"
}

@test "a row from ANOTHER run writes nothing into a ledger; a row from its owner's run does" {
  # PORTED FROM A SOURCE PROJECT.
  # run_all EXPORTS its ledger, so a nested devbin inherits it, and a witness run
  # failing on purpose put its red row into the PARENT's ledger -- the summary
  # then named a seal the parent's gate never produced. The ledger records the
  # run that owns it, and a witness child is a different run (bin/devbin).
  #
  # ONE LABEL FOR BOTH CALLS, and exactly one row: a nested `test rust` and the
  # parent's own carry the same label in life, so a label filter must not pass.
  mkdir -p logs
  : >logs/run.errors
  export DEVBIN_SEAL_LEDGER="$DEVBIN_TEST_TMPDIR/ledger"
  export DEVBIN_SEAL_LEDGER_RUN=aaaa0000
  : >"$DEVBIN_SEAL_LEDGER"
  DEVBIN_RUN_ID=bbbb0000 record_seal 101 "test rust" logs/run.errors
  DEVBIN_RUN_ID=aaaa0000 record_seal 0 "test rust" logs/run.errors
  run awk -F'\t' '{print $1 "|" $2}' "$DEVBIN_SEAL_LEDGER"
  assert_success
  [ "$output" = "0|test rust" ] || fail "expected only the owner's row, got:
$output"
}

@test "a WITNESS gate of the owner's own run still writes its row" {
  # THE FIRST CUT OF THE PORT DROPPED THESE: it keyed on the
  # witness flag, which every gate of a witness `all` inherits, so that run's own
  # ledger came back empty -- no FAILED seal lines, and no disagreement check. The
  # rule reads the run, not the flag.
  mkdir -p logs
  : >logs/run.errors
  export DEVBIN_SEAL_LEDGER="$DEVBIN_TEST_TMPDIR/ledger"
  export DEVBIN_SEAL_LEDGER_RUN=aaaa0000
  : >"$DEVBIN_SEAL_LEDGER"
  DEVBIN_RUN_ID=aaaa0000 RUNLOG_WITNESS_RUN=1 record_seal 101 "test rust" logs/run.errors
  assert_file_contains "$DEVBIN_SEAL_LEDGER" "test rust"
}

# ============================================================================
# THE INVOCATION RECORD
# ============================================================================
#
# WHAT THIS PROTECTS: a gate that died on its own ARGUMENTS sealed the tool's
# complaint about them and nothing about what produced them. Measured in one consumer
# -- a config `run:` read mid-edit word-split `variant=Designed for iPad` into
# three arguments and the seal read `Unknown build action 'for'`, which names
# nothing searchable.
#
# THE UNANCHORED-GRAMMAR TEST CARRIES THE WEIGHT. Recording the command line
# puts arbitrary config text where the extraction grammars can see it, and some
# print on UNANCHORED patterns. If the record ever reaches a grammar, the seal
# is built from devbin's own output -- a WRONG verdict, which is the one failure
# this subsystem cannot detect afterwards.

@test "run_gate records the invocation in the .out scope half, one argv per line" {
  run_gate --suffix demo --out-dir logs -- echo hello world
  assert_file_contains logs/LATEST_DEMO.out "argv[0]: echo"
  assert_file_contains logs/LATEST_DEMO.out "argv[1]: hello"
  assert_file_contains logs/LATEST_DEMO.out "argv[2]: world"
}

@test "the invocation record splits a spaced argument into SEPARATE argv lines" {
  # The measured shape, reproduced: this is what a word-split looks like once it
  # is indexed, and it is the whole reason the record is per-argument. On one
  # line `variant=Designed for iPad` and a correctly quoted value render
  # identically, which is how the defect stayed invisible.
  # shellcheck disable=SC2086
  local spaced='variant=Designed for iPad'
  run_gate --suffix demo --out-dir logs -- echo $spaced
  assert_file_contains logs/LATEST_DEMO.out "argv[1]: variant=Designed"
  assert_file_contains logs/LATEST_DEMO.out "argv[2]: for"
  assert_file_contains logs/LATEST_DEMO.out "argv[3]: iPad"
}

@test "the invocation record names its source when --source is given" {
  run_gate --suffix demo --out-dir logs --source "config key commands.test.options.swift.run" -- true
  assert_file_contains logs/LATEST_DEMO.out "from: config key commands.test.options.swift.run"
}

@test "a recorded argument matching an UNANCHORED grammar pattern never reaches the verdict" {
  # credo's grammar prints on `\[[A-Z]\] ` ANYWHERE in a line and also sets
  # inblock, so an unfiltered record containing it would seal itself AND drag
  # every following line into .errors. The gate is red so extraction really runs
  # -- on a green run the seal is truncated and this would pass vacuously.
  run run_gate --suffix demo --grammar credo --out-dir logs -- \
    bash -c 'echo "[W] a finding the tool really reported"; exit 1'
  assert_exit_code 1
  # The record is in the scope half...
  assert_file_contains logs/LATEST_DEMO.out "argv[0]: bash"
  # ...and NOT in the verdict half, though the tool's own finding is.
  refute_file_contains logs/LATEST_DEMO.errors "argv[0]"
  refute_file_contains logs/LATEST_DEMO.errors "devbin|"
  assert_file_contains logs/LATEST_DEMO.errors "a finding the tool really reported"
}

@test "the invocation record does not make a GREEN run seal non-empty" {
  # The seal invariant is the thing this whole file protects: adding anything to
  # the log must not change what EMPTY means.
  run_gate --suffix demo --out-dir logs -- true
  assert_file_empty logs/LATEST_DEMO.errors
}

# ============================================================================
# EVERY GATE OPENER SAYS WHERE ITS COMMAND LINE CAME FROM (issue 0085)
# ============================================================================
#
# `--source` is what puts the `from:` line in a seal, and note_invocation prints
# it only when it is non-empty. Measured once: of the five calls that
# open a gate, ONE passed it. So a reader of a seal for a command-level `run:`
# saw the argv devbin ran and nothing about where that line was declared -- and
# since issue 0082 the argv holds the RESULT of the glob matching, the declared
# line cannot be recovered by reading it. 0082 widened the gap rather than
# creating it, by making the one source line that existed say more.
#
# THE CLASS ARM, "every call that opens a gate says where its command line came
# from", IS THE ONE THAT KEEPS THIS FIXED. The others are instances; a new
# opener added without a source line fails the class arm, which is the
# only thing that stops a class like this decaying one call at a time.

@test "a command-level run: seals the key it came from, on the same terms as an option-level one (0085)" {
  # lib/resolve's comment above the command-level gate says it "seals on exactly
  # the terms an option-level one does". It did not: the option passed
  # --source and the command passed nothing. The same command line is declared
  # twice here so the two seals can be compared sentence for sentence.
  local proj
  proj="$(mkproj seals <<'YAML'
project:
  name: seals
commands:
  probe:
    summary: an option-level gate
    options:
      gated:
        summary: a gated option
        run: echo hello
        log: OPT
  sealed:
    summary: a command-level gate
    run: echo hello
    log: CMD
YAML
  )"
  run devbin_run "$proj" probe gated
  assert_success
  run devbin_run "$proj" sealed
  assert_success

  local opt cmd
  opt="$(sed -n 's/^devbin|[[:space:]]*from: //p' "$proj/tmp/probe/LATEST_OPT.out")"
  cmd="$(sed -n 's/^devbin|[[:space:]]*from: //p' "$proj/tmp/sealed/LATEST_CMD.out")"
  [ -n "$opt" ] || fail "the option-level seal carries no from: line:
$(cat "$proj/tmp/probe/LATEST_OPT.out")"
  [ -n "$cmd" ] || fail "the command-level seal carries no from: line:
$(cat "$proj/tmp/sealed/LATEST_CMD.out")"
  case "$opt" in *commands.probe.options.gated.run*) : ;;
    *) fail "the option seal does not name its key: $opt" ;; esac
  case "$cmd" in *commands.sealed.run*) : ;;
    *) fail "the command seal does not name its key: $cmd" ;; esac
  # The terms themselves: with each key replaced, the two sentences are one.
  local o="${opt/commands.probe.options.gated.run/<KEY>}"
  local c="${cmd/commands.sealed.run/<KEY>}"
  [ "$o" = "$c" ] || fail "the two gates do not seal on the same terms:
option:  $o
command: $c"
}

@test "a catalogue command line's gate names the catalogue, not a config key (0085)" {
  # The catalogue is devbin's own data, so there is no config key to name and
  # the honest answer is the phrase run_words is already given for its refusal.
  # Stubbed at the catalogue reader and at run_gate, which is how the 0082 arm
  # one file over drives this same site: no cargo, no mix, and the real
  # run_builtin_gate code path in between.
  local d="$DEVBIN_TEST_TMPDIR/cat"
  mkdir -p "$d"
  local got
  got="$(PROJECT_ROOT="$d" DEVBIN_NAME=devbin bash -c '
    . "$DEVBIN_LIB/gatecmd"
    builtin_option_run() { printf "%s\n" "echo hi"; }
    builtin_option_suffix() { printf "PROBE\n"; }
    builtin_option_grammar() { printf "generic\n"; }
    run_gate() {
      local s="(no --source passed)"
      while [ "$1" != -- ]; do
        if [ "$1" = --source ]; then s="$2"; fi
        shift
      done
      printf "%s\n" "$s"
    }
    run_builtin_gate check probe
  ')" || fail "run_builtin_gate failed: $got"
  case "$got" in
    *catalogue*"check probe"*) : ;;
    *) fail "the catalogue gate's source line is: $got" ;;
  esac
}

@test "a catalogue option that IS a devbin function names the function (0085)" {
  # The @builtin path opens a gate over a function in this process. There is no
  # command line at all, which is itself the thing worth recording: a reader of
  # this seal should not go looking for a config key that cannot exist.
  local d="$DEVBIN_TEST_TMPDIR/fn"
  mkdir -p "$d"
  local got
  got="$(PROJECT_ROOT="$d" DEVBIN_NAME=devbin bash -c '
    . "$DEVBIN_LIB/gatecmd"
    builtin_option_run() { printf "@builtin\n"; }
    builtin_option_suffix() { printf "PROBE\n"; }
    builtin_option_grammar() { printf "generic\n"; }
    builtin_check_probe() { :; }
    run_gate() {
      local s="(no --source passed)"
      while [ "$1" != -- ]; do
        if [ "$1" = --source ]; then s="$2"; fi
        shift
      done
      printf "%s\n" "$s"
    }
    run_builtin_gate check probe
  ')" || fail "run_builtin_gate failed: $got"
  case "$got" in
    *builtin_check_probe*) : ;;
    *) fail "the @builtin gate's source line is: $got" ;;
  esac
}

# Devbin's full cycle and test handler, whole scripts rather than functions, run
# for real through a DEVBIN_LIB shim whose runlog replaces run_gate with a stub
# that prints the --source VALUE it was handed. Nothing is cleaned, built or
# tested: the gated body never runs. The shim's helpers and config are the real
# ones, so every line up to the gate is the line a user's run executes.
#
# THE VALUE, NOT THE FLAG. Driven on the landed class arm: `--source
# ""` at either site passes it, because it reads the flag, and so does either
# site given the OTHER site's sentence, which is non-empty and names the wrong
# place. So each arm asserts that the value names its own site.
gate_source_of() {
  local site="$1" root="$2"
  shift 2
  local shim="$DEVBIN_TEST_TMPDIR/shim"
  mkdir -p "$shim" "$root"
  printf '. "%s/helpers"\n' "$DEVBIN_LIB" >"$shim/helpers"
  printf '. "%s/config"\n' "$DEVBIN_LIB" >"$shim/config"
  printf '. "%s/builtins"\n' "$DEVBIN_LIB" >"$shim/builtins"
  printf '. "%s/resolve"\n' "$DEVBIN_LIB" >"$shim/resolve"
  # devbin's own handlers, as a real install has them: fullcycle asks whether
  # each catalogue option it would run has its handler (issue 0134), and a
  # shim with no cmd/ reads test.rust as unrunnable and refuses the cycle.
  ln -sfn "$DEVBIN_LIB/cmd" "$shim/cmd"
  cat >"$shim/runlog" <<EOF
. "$DEVBIN_LIB/runlog"
run_gate() {
  local s="(no --source passed)"
  while [ "\$1" != -- ]; do
    if [ "\$1" = --source ]; then s="\$2"; fi
    shift
  done
  printf 'SOURCE=%s\n' "\$s"
}
EOF
  (cd "$root" && DEVBIN_LIB="$shim" PROJECT_ROOT="$root" bash "$DEVBIN_HOME/$site" "$@" </dev/null)
}

@test "devbin's own full cycle names itself as the source of its gate (0085)" {
  # fullcycle asks the config what its build and test phases are (issue 0134),
  # so a config declaring rust and a build line, and a two-line launcher, are
  # the whole fixture. The launcher is also what every phase would reach if
  # the stub ever stopped standing in for run_gate: nothing real.
  local root="$DEVBIN_TEST_TMPDIR/fcproj"
  mkdir -p "$root/bin/.devbin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/devbin"
  chmod +x "$root/bin/devbin"
  printf 'project:\n  name: fcproj\n  languages:\n    - rust\ncommands:\n  build:\n    run: "true"\n' \
    >"$root/bin/.devbin/config.yaml"
  local got
  # --force, because since 0096 fullcycle asks its one question BEFORE the gate
  # opens, and with no tty here that ask refuses before the gate is reached --
  # correctly. --force is how a run with nobody at the terminal gets there.
  got="$(DEVBIN_DIR="$root/bin/.devbin" gate_source_of lib/cmd/fullcycle "$root" --force)" ||
    fail "fullcycle did not reach its gate: $got"
  local src
  src="$(sed -n 's/^SOURCE=//p' <<<"$got")"
  [ -n "$src" ] || fail "fullcycle's gate was handed an empty --source:
$got"
  case "$src" in
    *"full cycle"*_fullcycle_run*) : ;;
    *) fail "fullcycle's gate does not name the full cycle as its source: $src" ;;
  esac
}

@test "devbin's own test handler names itself as the source of its gate (0085)" {
  local got
  got="$(gate_source_of bin/.devbin/cmd/test "$DEVBIN_TEST_TMPDIR/tproj" bats)" ||
    fail "the test handler did not reach its gate: $got"
  local src
  src="$(sed -n 's/^SOURCE=//p' <<<"$got")"
  [ -n "$src" ] || fail "the test handler's gate was handed an empty --source:
$got"
  case "$src" in
    *"test handler"*bin/.devbin/cmd/test*) : ;;
    *) fail "the test handler's gate does not name the handler as its source: $src" ;;
  esac
}

@test "every call that opens a gate says where its command line came from (0085)" {
  # THE CLASS, not the instances. Over every run_gate span (gate_spans, the one
  # reader 0087's arm uses too), a call is named here if it has no --source, if
  # its --source is literally empty or has no value, or if gate_spans could not
  # find the bare `--` that ends its flags.
  #
  # WHAT THIS ARM IS FOR: FINDING NEW SITES. It found the sixth opener,
  # bin/.devbin/cmd/test, the first time it ran, after a census by reading had
  # stopped at lib/ and bin/devbin. It is the only arm that sees a seventh.
  #
  # WHAT IT CANNOT SEE, WHICH IS WHY THE SITE ARMS ABOVE EXIST. Its value check
  # is a SUPPLEMENT: it reads the text of the call, so a --source whose value is
  # empty only at run time passes it, and so does a site handed ANOTHER site's
  # sentence -- non-empty, and naming the wrong place. Driven at the two
  # devbin-owned scripts: the line deleted dies here and at the site arm;
  # `--source ""` and the other site's sentence die at the site arm alone.
  local spans findings
  spans="$(gate_spans)"
  grep -qv '^UNTERMINATED' <<<"$spans" ||
    fail "the scan read NO run_gate call in lib/ or bin/ -- it is not reading the tree"
  findings="$(awk -v sq="'" '
    /^UNTERMINATED\t/ { sub(/^UNTERMINATED\t/, ""); print $0 "  no bare -- before the call ends, so its flags could not be read"; next }
    {
      # The FLAGS field alone (gate_spans prints loc, flags, argv), so a tool
      # argument spelled --source cannot stand in for the flag.
      n = split($0, f, "\t"); loc = f[1]; span = f[2]
      gsub(/\\[[:space:]]/, " ", span)
      if (span !~ /--source[=[:space:]]/) print loc "  no --source"
      else if (span ~ ("--source([[:space:]]+|=)(\"\"|" sq sq ")") ||
               span ~ /--source=([[:space:]]|$)/ ||
               span ~ /--source[[:space:]]+(-|$)/) print loc "  --source with an empty or missing value"
    }
  ' <<<"$spans")"
  [ -z "$findings" ] || fail "a gate is opened without a readable, non-empty --source, so its seal may say nothing true about where its argv came from:
$findings"
}

# ============================================================================
# THE PLATFORM -- WHICH MACHINE PRODUCED THIS (issue 0052)
#
# The narrowing that cost the 0.1.0 release. A local `test all` runs on one
# machine; its seal is a TRUE record of a macOS run, and nothing in the pair
# named a platform -- so `824 tests, 0 failures` read as a fact about devbin
# when it was a fact about one OS. CI had been red on Ubuntu for six days and
# three pushes, one of them the release, and the release note's Verified
# section was assembled from those local seals.
#
# THE SEAL ITSELF CANNOT CARRY IT AND THAT IS NOT AN OVERSIGHT. `.errors` is
# EMPTY exactly when a completed run was green, and that invariant is what
# every reader downstream depends on; writing a platform line into a green seal
# would destroy it. So the platform goes in the `.out`, which is the copy that
# travels, and reaches `.errors` only through the red tail fallback.
# ============================================================================

@test "the run log names the platform it ran on" {
  run_gate --suffix demo --out-dir logs -- true
  assert_file_contains "$(readlink -f logs/LATEST_DEMO.out)" "platform:"
}

@test "the platform line names the OS AND the bash, because both are axes" {
  # bash >= 5 is this project's floor and macOS ships 3.2.57 at /bin/bash, so
  # "which bash" is a real axis on which two runs of the same code differ.
  # Matched by shape: pinning the values would red this on every other machine,
  # which is the opposite of what the line is for.
  run_gate --suffix demo --out-dir logs -- true
  local log; log="$(readlink -f logs/LATEST_DEMO.out)"
  grep -qE '^devbin\|[[:space:]]+platform: .+ / bash .+$' "$log" ||
    fail "the platform line is not the expected shape:
$(grep platform "$log" || echo '(no platform line at all)')"
}

@test "a GREEN run still seals EMPTY -- the platform must not reach the seal" {
  # The invariant the whole subsystem rests on, re-asserted at the one change
  # most likely to break it. A platform line written into `.errors` would make
  # every green run read as red to every downstream reader.
  run_gate --suffix demo --out-dir logs -- true
  assert_file_empty logs/LATEST_DEMO.errors
}

@test "the platform line is TAGGED, so no grammar can seal a verdict out of it" {
  # Same reason as the referent: written on EVERY run, and a machine string is
  # arbitrary text. `Darwin 25.6.0 arm64` is harmless; a runner whose uname
  # carried a bracket or a `: error: ` would not be.
  run_gate --suffix demo --grammar credo --out-dir logs -- true
  assert_file_empty logs/LATEST_DEMO.errors
  grep -q "^devbin| *platform:" "$(readlink -f logs/LATEST_DEMO.out)"
}

# ============================================================================
# THE COMMIT A SEAL STANDS ON (ST0011 WP01)
#
# A green is remembered for (commit, platform) only when the seal names the
# commit at open and again at close, both clean and the same; seal_verdict is
# the one reader, answering ci-state's words: green, failed, pending, none,
# unknown.
# ============================================================================

# commit_repo -- a committed repository at $DEVBIN_TEST_TMPDIR/repo with logs/
# ignored, entered and set as PROJECT_ROOT, so a gate run here stands on a
# clean commit.
commit_repo() {
  local repo="$DEVBIN_TEST_TMPDIR/repo"
  mkdir -p "$repo" || return 1
  git -C "$repo" init -q -b main || return 1
  printf 'logs/\n' >"$repo/.gitignore"
  printf 'one\n' >"$repo/file"
  git -C "$repo" add -A || return 1
  git -C "$repo" -c user.name=t -c user.email=t@t commit -qm one || return 1
  export PROJECT_ROOT="$repo"
  cd "$repo" || return 1
}

# seal_commits <out> -- the seal's commit at open, then its commit at close.
seal_commits() {
  sed -n -e 's/^devbin|   commit: //p' -e 's/^devbin| commit at close: //p' "$1"
}

# verdict_word -- the word of the last `run seal_verdict`.
verdict_word() { printf '%s' "${output%%$'\t'*}"; }

# AT-1.1
@test "a seal names the commit it ran on at open and again at close: the bare sha on a clean tree, +dirty on a dirty one, unknown outside a checkout (ST0011)" {
  commit_repo
  local sha
  sha="$(git rev-parse HEAD)"
  run_gate --suffix demo --out-dir logs -- true
  [ "$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")" = "$sha"$'\n'"$sha" ] ||
    fail "on a clean tree: '$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")'"
  printf 'two\n' >file
  run_gate --suffix demo --out-dir logs -- true
  [ "$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")" = "$sha +dirty"$'\n'"$sha +dirty" ] ||
    fail "on a dirty tree: '$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")'"
  mkdir -p "$DEVBIN_TEST_TMPDIR/plain"
  cd "$DEVBIN_TEST_TMPDIR/plain"
  export PROJECT_ROOT="$PWD"
  run_gate --suffix demo --out-dir logs -- true
  [ "$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")" = "unknown"$'\n'"unknown" ] ||
    fail "outside a checkout: '$(seal_commits "$(readlink -f logs/LATEST_DEMO.out)")'"
}

# AT-1.4
@test "seal_verdict reads a sealed green as green for its own commit and platform, naming the seal, and as none for another commit or another platform (ST0011)" {
  commit_repo
  local sha plat
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  run_gate --suffix demo --out-dir logs -- true
  run seal_verdict logs demo "$sha" "$plat"
  assert_success
  [ "$(verdict_word)" = green ] || fail "its own commit: $output"
  assert_output_contains "$(basename "$(readlink -f logs/LATEST_DEMO.errors)")"
  run seal_verdict logs demo "$(printf '%040d' 0)" "$plat"
  [ "$(verdict_word)" = none ] || fail "another commit: $output"
  run seal_verdict logs demo "$sha" "Plan9 4 mips / bash 9.9"
  [ "$(verdict_word)" = none ] || fail "another platform: $output"
}

# AT-3.2
@test "seal_verdict with an empty platform reads the newest record's own, as a remote leg's pairs need, and a platform left out stops it (ST0011 WP05)" {
  commit_repo
  local sha plat other green red
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  other="Plan9 4 mips / bash 9.9"
  run_gate --suffix demo --out-dir logs -- true
  green="$(readlink -f logs/LATEST_DEMO.out)"
  run seal_verdict logs demo "$sha" ""
  [ "$(verdict_word)" = green ] || fail "one green run, no platform named: $output"
  # Left out, the platform is a caller's slip, never read as empty.
  run seal_verdict logs demo "$sha"
  assert_failure
  assert_output_contains "<platform> is required"
  # A newer red, its pair written on another platform: named, this platform
  # reads its own older green; unnamed, the newest record's platform decides.
  run run_gate --suffix demo --out-dir logs -- false
  red="$(readlink -f logs/LATEST_DEMO.out)"
  [ "$green" != "$red" ] || fail "the two runs share one pair"
  sed "s#^devbin|   platform: .*#devbin|   platform: $other#" "$red" >"$red.new" && mv "$red.new" "$red"
  grep -qxF "devbin|   platform: $other" "$red" || fail "the red pair's platform line was not rewritten: $(grep 'platform:' "$red")"
  touch -t 202601010000.00 "$green"
  touch -t 202601010001.00 "$red"
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = green ] || fail "this platform named: $output"
  run seal_verdict logs demo "$sha" ""
  [ "$(verdict_word)" = failed ] || fail "no platform named, the newest record's own: $output"
  # The two in one instant: the platform the newest names is fixed first, so
  # the other platform's record is passed over and no tie is read. Read with
  # no platform at all, the two would tie, unknown.
  touch -t 202601010002.00 "$green" "$red"
  run seal_verdict logs demo "$sha" ""
  [ "$(verdict_word)" = green ] || [ "$(verdict_word)" = failed ] ||
    fail "two records in one instant on two platforms, no platform named: $output"
  # No record at all names no platform to read.
  run seal_verdict logs demo "$(printf '%040d' 0)" ""
  [ "$(verdict_word)" = none ] || fail "another commit, no platform named: $output"
  assert_output_contains "on any platform"
}

# AT-1.4
@test "seal_verdict reads a sha that is not whole as unknown, naming it, never as none (ST0011)" {
  commit_repo
  local sha plat
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  run_gate --suffix demo --out-dir logs -- true
  # THE CONTROL: the whole sha reads the green that stands for it.
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = green ] || fail "the whole sha: $output"
  run seal_verdict logs demo "${sha:0:12}" "$plat"
  assert_success
  [ "$(verdict_word)" = unknown ] || fail "an abbreviated sha: $output"
  assert_output_contains "${sha:0:12} is not a whole commit sha"
  run seal_verdict logs demo "" "$plat"
  [ "$(verdict_word)" = unknown ] || fail "an empty sha: $output"
}

# AT-1.4
@test "seal_verdict never reads a dirty seal as green, nor one whose tree moved during the run, which stands for no commit and reads none, naming why, and a newer red whose tree moved outranks an older green (ST0011 WP02)" {
  commit_repo
  local sha plat
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  printf 'two\n' >file
  run_gate --suffix demo --out-dir logs -- true
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = none ] || fail "dirty at open, the only run: $output"
  git checkout -q -- file
  run_gate --suffix demo --out-dir logs -- bash -c 'printf "moved\n" >file'
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = none ] || fail "a green whose tree was dirtied during the run: $output"
  assert_output_contains "stands for no commit"
  git checkout -q -- file
  run_gate --suffix demo --out-dir logs -- true
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = green ] || fail "the same commit, left alone: $output"
  run run_gate --suffix demo --out-dir logs -- bash -c 'printf "moved\n" >file; exit 1'
  git checkout -q -- file
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = failed ] || fail "a newer red whose tree moved, over an older green: $output"
}

# AT-1.4
@test "seal_verdict reads a red seal as failed and one in flight as pending, the newest run deciding, and two runs of one commit in the same instant as none, since neither stands for it (ST0011 WP02)" {
  commit_repo
  local sha plat green red
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  run_gate --suffix demo --out-dir logs -- true
  green="$(readlink -f logs/LATEST_DEMO.out)"
  run run_gate --suffix demo --out-dir logs -- false
  red="$(readlink -f logs/LATEST_DEMO.out)"
  [ "$green" != "$red" ] || fail "the two runs share one pair"
  touch -t 202601010000.00 "$green"
  touch -t 202601010001.00 "$red"
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = failed ] || fail "a red newer than a green: $output"
  touch -t 202601010002.00 "$green"
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = green ] || fail "a green newer than a red: $output"
  touch -t 202601010002.00 "$red"
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = none ] || fail "two runs in the same instant: $output"
  assert_output_contains "neither is the newer"
  # An opened pair that was never sealed, newer than both: a run killed mid-way.
  (open_run_log 1 logs demo >/dev/null && note_invocation "$log" "" true)
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = pending ] || fail "in flight: $output"
}

@test "seal_verdict reads nothing strictly older than the record that decided it: an older log it cannot read does not unmake a newer green (ST0011 WP02)" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a file whatever its mode, so no unreadable log can be made"
  commit_repo
  local sha plat old new
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  run_gate --suffix demo --out-dir logs -- true
  old="$(readlink -f logs/LATEST_DEMO.out)"
  run_gate --suffix demo --out-dir logs -- true
  new="$(readlink -f logs/LATEST_DEMO.out)"
  [ "$old" != "$new" ] || fail "the two runs share one pair"
  touch -t 202601010000.00 "$old"
  touch -t 202601010001.00 "$new"
  chmod 000 "$old"
  run seal_verdict logs demo "$sha" "$plat"
  chmod 644 "$old"
  [ "$(verdict_word)" = green ] || fail "an older log it cannot read unmade a newer green: $output"
  assert_output_contains "$(basename "${new%.out}").errors"
}

# AT-1.4
@test "seal_verdict reads a seal it cannot read, or a log with no seal beside it, as unknown, naming it, never as none (ST0011)" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a file whatever its mode, so no unreadable seal can be made"
  commit_repo
  local sha plat out
  sha="$(git rev-parse HEAD)"
  plat="$(platform_identity)"
  run_gate --suffix demo --out-dir logs -- true
  out="$(readlink -f logs/LATEST_DEMO.out)"
  chmod 000 "$out"
  run seal_verdict logs demo "$sha" "$plat"
  chmod 644 "$out"
  [ "$(verdict_word)" = unknown ] || fail "an unreadable log: $output"
  assert_output_contains "$(basename "$out")"
  rm -f "${out%.out}.errors"
  run seal_verdict logs demo "$sha" "$plat"
  [ "$(verdict_word)" = unknown ] || fail "a log with no seal beside it: $output"
  assert_output_contains "$(basename "$out")"
}

# ============================================================================
# ONE INVOCATION, ONE IDENTITY (issue 0045)
#
# The minute stamp was being read as a run key because it is the only candidate
# present, and it is not one. A `check all` beginning at 18:34:58 wrote
# `1834.{SYNTAX,LINT}` and then `1835.{CRITIC,FORMAT,TOOLCHAIN}` -- one run
# across two stamps -- while `1835` ALSO held the next run's LINT and SYNTAX.
# Grouping by prefix then paired a failing run's three gates with a passing
# run's two and produced a GREEN verdict out of five entirely honest files.
#
# THESE RUN THROUGH DISPATCH AND THEY HAVE TO. The id is minted in bin/devbin,
# because every option of a synthesised `all` is a SEPARATE PROCESS and nothing
# memoised in this library can be shared between two of them. A unit test that
# called the library directly would be green over a mechanism that does not
# exist -- which is what the first two attempts at this fix actually were.
# ============================================================================

gates_project() {
  mkproj gatesdemo <<'YAML'
project:
  name: gatesdemo
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        log: one
        run: echo ran-one
      two:
        summary: second
        log: two
        run: echo ran-two
      three:
        summary: third
        log: three
        run: echo ran-three
YAML
}

@test "every gate of ONE all-run carries ONE run id" {
  # WHAT THIS ONE DOES AND DOES NOT PROVE, measured rather than assumed.
  # Declared-`run:` options execute in a SUBSHELL of the dispatcher, so they
  # would inherit an unexported variable too -- removing DEVBIN_RUN_ID from the
  # export list leaves this test GREEN. It holds the property; the test below
  # holds the mechanism.
  proj="$(gates_project)"
  run devbin_run "$proj" gates all
  assert_success
  local ids
  ids="$(grep -h 'run:' "$proj"/tmp/gates/*.out | sort -u | wc -l | tr -d ' ')"
  [ "$ids" = 1 ] || fail "one invocation wrote $ids distinct run ids:
$(grep -h 'run:' "$proj"/tmp/gates/*.out | sort -u)"
}

@test "the run id reaches a SEPARATE PROCESS, which is why it is exported" {
  # THE MECHANISM, and the reason the id could not live in lib/runlog. A project
  # handler is a separate process -- run_all says so where it explains why the
  # seal ledger is a file rather than a variable -- and a variable memoised in
  # the library, or merely set in the dispatcher, reaches nothing there.
  proj="$(mkproj iddemo <<'YAML'
project:
  name: iddemo
  languages:
    - shell
commands:
  showid:
    summary: print the run id this process was handed
YAML
  )"
  create_test_command "$proj" showid \
    "$(printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "HANDLER-SAW: %%s\\n" "${DEVBIN_RUN_ID:-NOTHING}"\n')" >/dev/null

  run devbin_run "$proj" showid
  assert_success
  refute_output_contains "HANDLER-SAW: NOTHING"
  assert_output_matches 'HANDLER-SAW: [0-9a-f]{8}'
}

@test "two invocations carry DIFFERENT run ids" {
  # Without this the test above passes against a constant, which would be an
  # identifier that identifies nothing -- and would silently re-create the
  # cross-run pairing this issue is about, one layer down.
  #
  # COUNTED ACROSS THE WHOLE SET, not read off the newest file, and the first
  # draft of this test got that wrong. Two runs in the same minute produce
  # `<stamp>.one.out` and `<stamp>-<SS>.one.out`, and the shell sorts the second
  # BEFORE the first because `-` precedes `.` -- so `tail -1` returned run one's
  # log both times and the test reported a shared id that did not exist.
  proj="$(gates_project)"
  local ids n runs=0
  run devbin_run "$proj" gates one
  assert_success
  runs=$((runs + 1))
  run devbin_run "$proj" gates one
  assert_success
  runs=$((runs + 1))
  ids="$(grep -h 'run:' "$proj"/tmp/gates/*.one.out | sort -u)"
  n="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  [ "$n" = "$runs" ] || fail "$runs invocations produced $n distinct run id(s):
$ids"
}

@test "every gate of ONE all-run shares ONE stamp prefix" {
  # The readable half. It is not the key -- two runs in one minute still contend
  # for a prefix and each gate resolves that on its own clock -- but a run that
  # straddles a minute boundary must not scatter itself, which is the direction
  # that produced the filed miscount.
  #
  # DRIVEN FROM AN INJECTED STAMP, because the obvious form cannot fail. Three
  # gates that all start inside one minute produce one prefix whether the stamp
  # is shared or re-read per gate, so asserting "they agree" is green against
  # the defect. Handing the invocation a stamp no clock would produce makes the
  # question answerable: every artefact must carry THAT value, which is only
  # true if the gates read the invocation's stamp instead of the clock.
  proj="$(gates_project)"
  DEVBIN_RUN_STAMP=20200101-0101 run devbin_run "$proj" gates all
  assert_success
  local n
  n="$(cd "$proj/tmp/gates" && find . -maxdepth 1 -type f -name '20200101-0101.*.out' | wc -l | tr -d ' ')"
  [ "$n" = 3 ] || fail "expected all three gates on the injected stamp, got $n:
$(cd "$proj/tmp/gates" && find . -maxdepth 1 -type f -name '*.out')"
  #
  # THE LATEST_* POINTERS ARE EXCLUDED AND THAT IS NOT BOOKKEEPING. They are
  # symlinks named after the GATE rather than the run, so counting them makes
  # any run look like three, and the first draft of this test duly reported six
  # stamps for one invocation. `-type f` is the whole fix.
  local prefixes
  prefixes="$(cd "$proj/tmp/gates" &&
    find . -maxdepth 1 -type f -name '*.out' |
    sed -e 's|^\./||' -e 's/\.[^.]*\.out$//' | sort -u | wc -l | tr -d ' ')"
  [ "$prefixes" = 1 ] || fail "one invocation wrote $prefixes distinct stamps:
$(cd "$proj/tmp/gates" && find . -maxdepth 1 -type f -name '*.out')"
}

@test "a CHILD devbin inherits the run id, so a cycle is one run" {
  # fullcycle spawns clean, build and test as separate devbin processes. The id
  # is exported for exactly this: the operator asked for one thing.
  proj="$(gates_project)"
  DEVBIN_RUN_ID=feedface run devbin_run "$proj" gates all
  assert_success
  local ids
  ids="$(grep -h 'run:' "$proj"/tmp/gates/*.out | sort -u)"
  [ "$ids" = "devbin|   run: feedface" ] ||
    fail "an inherited id did not reach the artefacts: [$ids]"
}

@test "a witness ALL still names its failed gate's seal in the summary" {
  # End to end, through run_all's own ledger: the regression the first cut of the
  # ledger port introduced, driven the way it would be met.
  proj="$(mkproj witnessall <<'YAML'
project:
  name: witnessall
  languages:
    - shell
commands:
  gates:
    summary: project gates
    options:
      good:
        summary: passes
        log: good
        run: echo ran-good
      bad:
        summary: fails
        log: bad
        run: exit 3
YAML
  )"
  RUNLOG_WITNESS_RUN=1 run devbin_run "$proj" gates all
  assert_failure
  assert_output_matches 'gates bad +[^ ]*\.errors'
}

# A parent `all` with one option that re-invokes devbin on a failing gate, the
# shape of a suite that drives its own crate gate. $1 is the nested run's
# RUNLOG_WITNESS_RUN value. `env`, because a declared `run:` is not handed to a
# shell, so an assignment prefix would be run as the command. The drive option
# fails with the nested gate; the parent's own row for it is `gates drive`.
nested_gate_project() {
  mkproj nestedgate <<YAML
project:
  name: nestedgate
  languages:
    - shell
commands:
  inner:
    summary: the gate the suite drives
    options:
      bad:
        summary: fails on purpose
        log: bad
        run: exit 3
  gates:
    summary: project gates
    options:
      drive:
        summary: drives inner bad, expecting it to fail
        log: drive
        run: env RUNLOG_WITNESS_RUN=$1 ./bin/devbin inner bad
YAML
}

@test "a NESTED witness gate's red row does not reach the parent's summary" {
  proj="$(nested_gate_project 1)"
  run devbin_run "$proj" gates all
  assert_output_contains "FAILED: drive"
  refute_output_matches 'inner bad +[^ ]*\.errors'
}

@test "CONTROL: the same nested gate WITHOUT the flag does reach the parent's ledger" {
  # Without this the arm above passes against a ledger nothing can reach.
  proj="$(nested_gate_project 0)"
  run devbin_run "$proj" gates all
  assert_output_contains "FAILED: drive"
  assert_output_matches 'inner bad +[^ ]*\.errors'
}

@test "a WITNESS child mints its OWN run id instead of inheriting its parent's" {
  # THE RULE: KEEP INHERITANCE, and except the witness. A child devbin is part
  # of the run that spawned it -- the arm above -- unless it says it is not the
  # gate's verdict. Measured in one consumer: one id across a real gate and three
  # nested witness runs, so `grep -l "run: <id>"` enumerated four runs for one
  # gate.
  #
  # The inherited id is injected, so "not feedface" cannot pass by accident, and
  # the count holds that the witness run's OWN gates still share the id it minted.
  proj="$(gates_project)"
  DEVBIN_RUN_ID=feedface RUNLOG_WITNESS_RUN=1 run devbin_run "$proj" gates all
  assert_success
  local ids
  ids="$(grep -h 'run:' "$proj"/tmp/gates/*.out | sort -u)"
  [ "$(printf '%s\n' "$ids" | wc -l | tr -d ' ')" = 1 ] ||
    fail "one witness invocation wrote several run ids: [$ids]"
  [ "$ids" != "devbin|   run: feedface" ] ||
    fail "a witness child inherited its parent's run id"
  grep -Eq '^devbin\|   run: [0-9a-f]{8}$' <<<"$ids" ||
    fail "a witness child did not mint an id of its own: [$ids]"
}

@test "a child of a WITNESS run inherits its id: only the witness BOUNDARY mints" {
  # The flag is inherited, so keying the mint on the flag alone gave every
  # child devbin of a witness run its own id -- a witness `fullcycle` became
  # 1 + N runs, the split inheritance was chosen to prevent.
  # DEVBIN_RUN_WITNESS=1 says the parent was already a witness.
  proj="$(gates_project)"
  DEVBIN_RUN_ID=feedface DEVBIN_RUN_WITNESS=1 RUNLOG_WITNESS_RUN=1 run devbin_run "$proj" gates all
  assert_success
  local ids
  ids="$(grep -h 'run:' "$proj"/tmp/gates/*.out | sort -u)"
  [ "$ids" = "devbin|   run: feedface" ] ||
    fail "a child of a witness run did not inherit its id: [$ids]"
}

@test "a witness run's CHILD DEVBIN carries the witness run's id, end to end" {
  proj="$(mkproj witnesschild <<'YAML'
project:
  name: witnesschild
  languages:
    - shell
commands:
  inner:
    summary: the child's gate
    options:
      good:
        summary: passes
        log: good
        run: echo ran-inner
  gates:
    summary: project gates
    options:
      drive:
        summary: spawns a child devbin
        log: drive
        run: ./bin/devbin inner good
YAML
  )"
  RUNLOG_WITNESS_RUN=1 run devbin_run "$proj" gates all
  assert_success
  local ids
  # Anchored: a witness run also prints "witness run: LATEST_... not re-pointed".
  ids="$(grep -h '^devbin|   run:' "$proj"/tmp/gates/*.out "$proj"/tmp/inner/*.out | sort -u)"
  [ "$(printf '%s\n' "$ids" | wc -l | tr -d ' ')" = 1 ] ||
    fail "a witness run and its child devbin carry different ids:
$ids"
}

@test "DECLARED LIMIT: a witness child of a witness run is part of that run, row and id" {
  # Inside a witness run, a child that inherited the flag and one started as a
  # witness on purpose are the same environment, so nothing can tell them apart.
  # One definition answers both questions -- same run id, so the row is kept --
  # rather than two rules answering them oppositely. Pinned so a
  # change to it is a decision, not a drift.
  proj="$(nested_gate_project 1)"
  RUNLOG_WITNESS_RUN=1 run devbin_run "$proj" gates all
  assert_output_contains "FAILED: drive"
  assert_output_matches 'inner bad +[^ ]*\.errors'
}

@test "the run-log stamp is read from UTC, not the local clock" {
  # Issue 0055. The stamp is read side by side with `fleet audit`, which renders
  # UTC with a trailing `Z`; an unmarked LOCAL stamp compared against one of
  # those is wrong by the local offset for half the year and exactly right for
  # the other half. Correct-in-winter is the worst available shape, because the
  # instrument agrees with itself for six months at a time.
  #
  # THE OBVIOUS FORM CANNOT FAIL AND THAT IS WHY THIS ONE INJECTS A ZONE. Run
  # under the ambient TZ and a local stamp and a UTC stamp are the SAME STRING
  # wherever the machine sits at UTC+0 -- and this machine is at +0 for half the
  # year, so the test would pass against the defect every winter and nobody
  # would learn which half it was measuring. TZ=Pacific/Kiritimati is UTC+14, so
  # the two readings differ by fourteen hours and no minute boundary can blur
  # them.
  #
  # BOTH HALVES ARE ASSERTED. Matching UTC alone is satisfied by any clock that
  # happens to agree; the second assertion -- that the stamp is NOT the local
  # reading -- is the one that goes red if `date -u` is reverted to `date`.
  proj="$(gates_project)"
  local before after local_stamp stamp
  before="$(date -u +%Y%m%d-%H%M)"
  TZ=Pacific/Kiritimati local_stamp="$(TZ=Pacific/Kiritimati date +%Y%m%d-%H%M)"
  unset DEVBIN_RUN_STAMP
  TZ=Pacific/Kiritimati run devbin_run "$proj" gates one
  after="$(date -u +%Y%m%d-%H%M)"
  assert_success

  stamp="$(cd "$proj/tmp/gates" &&
    find . -maxdepth 1 -type f -name '*.one.out' |
    sed -e 's|^\./||' -e 's/\.[^.]*\.out$//' -e 's/-[0-9][0-9]$//' | sort -u)"
  [ -n "$stamp" ] || fail "no gate artefact was written, so nothing was measured"

  # Positive: the stamp is the UTC minute, allowing for a boundary roll between
  # the code's read and the test's two.
  [ "$stamp" = "$before" ] || [ "$stamp" = "$after" ] ||
    fail "stamp [$stamp] is neither UTC minute [$before] nor [$after]"

  # Negative, and this is the assertion that carries the issue: under UTC+14 a
  # local read differs by fourteen hours, so a stamp equal to it means the
  # clock came off `date` rather than `date -u`.
  [ "$stamp" != "$local_stamp" ] ||
    fail "stamp [$stamp] equals the LOCAL reading under TZ=Pacific/Kiritimati -- the clock is not UTC"
}

# ============================================================================
# A GATED TOOL NEVER READS INPUT (issue 0088, row 2)
# ============================================================================
#
# run_gate ran the tool with the caller's stdin, so a tool run from a terminal
# was handed the person's keyboard. Measured (0088): a gated probe asking
# `Shall I install Hex? [Yn]` BLOCKED on a pty, while every agent and CI run
# read EOF and took the tool's no-answer path. The two runs measured different
# things and nothing said so. The rule: the tool gets </dev/null, no override,
# until a real gate needs one.
#
# AMENDED TWICE. First: a function in devbin's own process kept stdin, because
# the first cut starved every gate and clean.bats caught it -- `clean` asks
# before removing, and a person could no longer answer. That was then measured
# to hand the terminal to every tool such a function STARTS (mix under `check
# format`, the formatters, fullcycle's phases): the split looked only at the
# gate's first word. Second: every gate is fed </dev/null again, and run_gate
# tells the function whether its own stdin was a terminal through
# DEVBIN_GATE_TTY, which is what `clean` asks on. The arms below hold both
# halves at the one site: nothing under a gate reads input, and the fact of a
# terminal still reaches devbin's code.
#
# A bats run has no tty, so the arms hand devbin a PIPE with an answer in it --
# the stand-in for a person at the keyboard. devbin_run is not used because it
# feeds </dev/null itself, which would make the arms pass on any code.

# stdin_project -- one option-level gate and one command-level gate, both
# running a tool that reports whether it could read a line.
stdin_project() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    options:
      go:
        run: ./asks
        grammar: generic
        log: GO
  ask:
    run: ./asks
    grammar: generic
    log: ASK
YAML
  )"
  printf '#!/bin/sh\nif IFS= read -r a; then echo "tool read: $a"; else echo "tool read EOF"; fi\n' >"$proj/asks"
  chmod +x "$proj/asks"
  printf '%s\n' "$proj"
}

@test "an option-level gate hands its tool no input, so a terminal run takes the path CI takes (0088)" {
  proj="$(stdin_project)"
  run bash -c "cd '$proj' && printf 'y\n' | ./bin/devbin qa go"
  assert_success
  refute_output_contains "tool read: y"
  assert_output_contains "tool read EOF"
}

@test "a command-level gate hands its tool no input either (0088)" {
  proj="$(stdin_project)"
  run bash -c "cd '$proj' && printf 'y\n' | ./bin/devbin ask"
  assert_success
  refute_output_contains "tool read: y"
  assert_output_contains "tool read EOF"
}

# gate_probe <run-line> -- write a script that runs run_builtin_gate check
# probe in-process, the catalogue row stubbed to <run-line>. The @builtin
# function reports DEVBIN_GATE_TTY, whether IT could read a line, and then
# starts ./asks -- the shape of `check format` starting mix. Prints the
# script's path.
gate_probe() {
  local d="$DEVBIN_TEST_TMPDIR/asks"
  mkdir -p "$d"
  # BOTH READS ARE BOUNDED, with a label of their own: on a pty nothing ever
  # arrives, so an unbounded read would HANG the arm on the very regression it
  # is there to catch (measured) rather than fail it.
  printf '#!/usr/bin/env bash\nIFS= read -r -t 5 a; rc=$?\nif [ "$rc" -eq 0 ]; then echo "tool read: $a"; elif [ "$rc" -gt 128 ]; then echo "tool read TIMEOUT"; else echo "tool read EOF"; fi\n' >"$d/asks"
  chmod +x "$d/asks"
  cat >"$d/probe.sh" <<'SH'
. "$DEVBIN_LIB/gatecmd"
builtin_option_run() { printf "%s\n" "$RUN_LINE"; }
builtin_option_suffix() { printf "PROBE\n"; }
builtin_option_grammar() { printf "generic\n"; }
builtin_check_probe() {
  echo "flag=${DEVBIN_GATE_TTY-unset}"
  local a rc=0
  IFS= read -r -t 5 a || rc=$?
  if [ "$rc" -eq 0 ]; then echo "fn read: $a"; elif [ "$rc" -gt 128 ]; then echo "fn read TIMEOUT"; else echo "fn read EOF"; fi
  ./asks
}
run_builtin_gate check probe
SH
  printf '%s\n' "$d"
}

# asks_through_catalogue <run-line> -- gate_probe with TWO lines of `y` piped
# in, so the function reading one cannot hide the tool reading the other, and a
# stale DEVBIN_GATE_TTY=1 in the environment that the gate must overwrite.
asks_through_catalogue() {
  local d
  d="$(gate_probe "$1")"
  printf 'y\ny\n' | PROJECT_ROOT="$d" DEVBIN_NAME=devbin RUN_LINE="$1" DEVBIN_GATE_TTY=1 \
    bash "$d/probe.sh" 2>&1
}

@test "a gate over a devbin function hands neither the function nor the tools it starts any input (0088, second amendment)" {
  run asks_through_catalogue @builtin
  refute_output_contains "read: y"
  assert_output_contains "fn read EOF"
  assert_output_contains "tool read EOF"
}

@test "a gate over a catalogue command line hands the tool no input, at the same site (0088)" {
  run asks_through_catalogue ./asks
  refute_output_contains "tool read: y"
  assert_output_contains "tool read EOF"
}

@test "a gate whose stdin is NOT a terminal tells the function so, over a stale flag in the environment (0088, second amendment)" {
  run asks_through_catalogue @builtin
  assert_output_contains "flag=0"
}

@test "a gate whose stdin IS a terminal tells the function so, and still hands it no input (0088, second amendment)" {
  require_pty
  d="$(gate_probe @builtin)"
  run run_tty_eof env PROJECT_ROOT="$d" DEVBIN_NAME=devbin RUN_LINE=@builtin DEVBIN_LIB="$DEVBIN_LIB" \
    bash "$d/probe.sh"
  assert_output_contains "flag=1"
  assert_output_contains "fn read EOF"
  assert_output_contains "tool read EOF"
}

@test "the flag reads the gate's STDIN, not its output: a terminal in and a pipe out is still a person (0088)" {
  # The arm above puts all three fds on the terminal, so `[ -t 1 ]` or
  # `[ -t 2 ]` in run_gate passed it. `devbin check | tee` is
  # this shape: stdin on the terminal, output piped.
  require_pty
  d="$(gate_probe @builtin)"
  run run_tty_eof env PROJECT_ROOT="$d" DEVBIN_NAME=devbin RUN_LINE=@builtin DEVBIN_LIB="$DEVBIN_LIB" \
    bash -c 'bash "$1" 2>&1 | cat' _ "$d/probe.sh"
  assert_output_contains "flag=1"
  assert_output_contains "tool read EOF"
}

# ============================================================================
# THE OVERHEAD METER'S SUITE COUNT (issue 0095)
# ============================================================================
#
# cargo prints a `finished in` line for every test binary and doc-test pass,
# empty ones included, so a count of those lines reads as more testing than
# happened. It cannot simply skip the 0.00s lines either: cargo rounds to two
# places, so a binary running a few fast tests reads 0.00s too. The line keeps
# the count and says how many of them read zero -- a fact, not a judgement.

@test "the suite count names how many suites reported zero time" {
  printf '%s\n' \
    'test result: ok. 0 passed; finished in 0.00s' \
    'test result: ok. 0 passed; finished in 0.00s' \
    'test result: ok. 40 passed; finished in 11.04s' \
    'test result: ok. 0 passed; finished in 0.00s' >run.log
  DEVBIN_RUN_T0=$(($(date +%s) - 15))

  run print_run_overhead run.log

  assert_success
  # Every planted line is a suite's, and those ending 0.00s are the zero ones.
  assert_output_contains "across $(awk 'END { print NR }' run.log) suite(s), $(grep -c 'finished in 0\.00s$' run.log) of them reporting zero time."
}

@test "with no zero-time suite the line is unchanged" {
  printf '%s\n' \
    'test result: ok. 3 passed; finished in 1.20s' \
    'Finished in 3.5 seconds' >run.log
  DEVBIN_RUN_T0=$(($(date +%s) - 15))

  run print_run_overhead run.log

  assert_success
  assert_output_contains "across $(awk 'END { print NR }' run.log) suite(s). The wall covers everything this gate ran"
  refute_output_contains "reporting zero time"
}

# --- a run-log directory ignores itself (issue 0157) ------------------------

# git_fixture <proj> -- make <proj> a repository with everything committed, so
# `git status` says exactly what a gate run added.
git_fixture() {
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m fixture
}

@test "a gate's log directory ignores itself, so a first gate leaves the tree clean and --version clean (0157)" {
  # With no .gitignore covering tmp/, the first gate left `?? tmp/` and every
  # later --version said +dirty.
  proj="$(gates_project)"
  [ ! -e "$proj/.gitignore" ] || fail "the fixture carries a .gitignore, so this would prove nothing"
  git_fixture "$proj"
  run devbin_run "$proj" gates one
  assert_success
  [ "$(cat "$proj/tmp/gates/.gitignore")" = "*" ] || fail "tmp/gates/.gitignore holds: $(cat "$proj/tmp/gates/.gitignore" 2>&1)"
  [ -z "$(git -C "$proj" status --porcelain --untracked-files=all)" ] ||
    fail "the tree reads dirty after a gate:
$(git -C "$proj" status --porcelain --untracked-files=all)"
  run devbin_run "$proj" --version
  assert_success
  refute_output_contains "+dirty"
}

@test "a .gitignore the project made in a log directory is left exactly as it was (0157)" {
  proj="$(gates_project)"
  mkdir -p "$proj/tmp/gates"
  printf '!keep-me\n' >"$proj/tmp/gates/.gitignore"
  run devbin_run "$proj" gates one
  assert_success
  [ "$(cat "$proj/tmp/gates/.gitignore")" = '!keep-me' ] || fail "the project's own file now holds: $(cat "$proj/tmp/gates/.gitignore")"
}

@test "tmp/ itself, the project root and a directory outside it are never given a .gitignore (0157)" {
  local outside="$DEVBIN_TEST_TMPDIR/outside"
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$PROJECT_ROOT/tmp/inside" "$outside"
  gate_out_ignore "$PROJECT_ROOT/tmp"
  gate_out_ignore "$PROJECT_ROOT"
  gate_out_ignore "$outside"
  [ ! -e "$PROJECT_ROOT/tmp/.gitignore" ] || fail "tmp/ itself was given a .gitignore"
  [ ! -e "$PROJECT_ROOT/.gitignore" ] || fail "the project root was given a .gitignore"
  [ ! -e "$outside/.gitignore" ] || fail "a directory outside the project was given one"
  # The control: strictly inside tmp/ it is written.
  gate_out_ignore "$PROJECT_ROOT/tmp/inside"
  [ "$(cat "$PROJECT_ROOT/tmp/inside/.gitignore")" = "*" ] || fail "a directory inside tmp/ was not given one"
}

@test "a .gitignore that cannot be written is said, and the run goes on (0157)" {
  mkdir -p "$PROJECT_ROOT/tmp/locked"
  chmod 500 "$PROJECT_ROOT/tmp/locked"
  if : 2>/dev/null >"$PROJECT_ROOT/tmp/locked/probe"; then
    chmod 700 "$PROJECT_ROOT/tmp/locked"
    skip "running with permissions that write a mode-500 directory"
  fi
  run gate_out_ignore "$PROJECT_ROOT/tmp/locked"
  chmod 700 "$PROJECT_ROOT/tmp/locked"
  assert_success
  assert_output_contains "could not write $PROJECT_ROOT/tmp/locked/.gitignore"
}

@test "a tmp/ directory that is a link out of the tree is never given a .gitignore (0157)" {
  # Resolved physically, so a link leading outside is not inside tmp/, and
  # nothing is written where the link leads.
  local outside="$DEVBIN_TEST_TMPDIR/elsewhere"
  mkdir -p "$PROJECT_ROOT/tmp" "$outside/target"
  ln -s "$outside/target" "$PROJECT_ROOT/tmp/linked"
  gate_out_ignore "$PROJECT_ROOT/tmp/linked"
  [ ! -e "$outside/target/.gitignore" ] || fail "a .gitignore was written through the link, outside the tree"
}

@test "a directory under tmp/ the project tracks is never given a .gitignore (0157)" {
  # It is the project's, and `*` there would hide its next file.
  mkdir -p "$PROJECT_ROOT/tmp/reports"
  printf 'kept\n' >"$PROJECT_ROOT/tmp/reports/summary.txt"
  git -C "$PROJECT_ROOT" init -q
  git -C "$PROJECT_ROOT" add -f tmp/reports/summary.txt
  git -C "$PROJECT_ROOT" -c user.email=t@t -c user.name=t commit -q -m kept
  gate_out_ignore "$PROJECT_ROOT/tmp/reports"
  [ ! -e "$PROJECT_ROOT/tmp/reports/.gitignore" ] || fail "a tracked directory was given a .gitignore"
  # The control: an untracked one beside it is given one.
  mkdir -p "$PROJECT_ROOT/tmp/gates"
  gate_out_ignore "$PROJECT_ROOT/tmp/gates"
  [ "$(cat "$PROJECT_ROOT/tmp/gates/.gitignore")" = "*" ] || fail "an untracked log directory was not given one"
}

@test "gate_out_ignored answers what a run would make of a directory, and writes nothing (0157)" {
  # The release pre-flight asks this before any log is open, so a dry run and a
  # cut read the same tree the same way.
  git -C "$PROJECT_ROOT" init -q
  run gate_out_ignored tmp/release
  assert_success
  [ ! -e "$PROJECT_ROOT/tmp" ] || fail "the question wrote: $(find "$PROJECT_ROOT/tmp")"
  # A .gitignore the project put there stays, and decides: here it ignores
  # nothing, and no root .gitignore does.
  mkdir -p "$PROJECT_ROOT/tmp/release"
  printf '!keep\n' >"$PROJECT_ROOT/tmp/release/.gitignore"
  run gate_out_ignored tmp/release
  assert_failure
  # And a project whose own .gitignore covers tmp/ is ignored already.
  printf 'tmp/\n' >"$PROJECT_ROOT/.gitignore"
  run gate_out_ignored tmp/release
  assert_success
}

@test "over an index git cannot read, gate_out_ignored says git could not say, unless the writer's rule answers without git (0186)" {
  # check-ignore fails at 128 over such an index, and the fall to the writer's
  # rule, which writes no file where the project's is already, read the failure
  # as not ignored. rc 2 is git not answering, with git's own line on stdout.
  git -C "$PROJECT_ROOT" init -q
  printf 'x\n' >"$PROJECT_ROOT/a.txt"
  git -C "$PROJECT_ROOT" add a.txt
  git -C "$PROJECT_ROOT" -c user.email=t@t -c user.name=t commit -q -m one
  mkdir -p "$PROJECT_ROOT/tmp/release" "$PROJECT_ROOT/tmp/kept"
  printf '*\n' >"$PROJECT_ROOT/tmp/release/.gitignore"
  printf '!keep\n' >"$PROJECT_ROOT/tmp/kept/.gitignore"
  # THE CONTROLS: with the index readable, git answers ignored and not ignored.
  run gate_out_ignored tmp/release
  [ "$status" -eq 0 ] || fail "readable and ignored: want 0, got $status: $output"
  run gate_out_ignored tmp/kept
  [ "$status" -eq 1 ] || fail "readable and not ignored: want 1, got $status: $output"
  break_git_index "$PROJECT_ROOT"
  local d
  for d in tmp/release tmp/kept; do
    run gate_out_ignored "$d"
    [ "$status" -eq 2 ] || fail "$d over the cut index: want 2, got $status: $output"
    assert_output "fatal: .git/index: index file smaller than expected"
  done
  # A directory that does not exist yet is given its own `*` before the first
  # log, whatever git can say, so the writer's rule answers without git.
  run gate_out_ignored tmp/fresh
  [ "$status" -eq 0 ] || fail "a new log directory over the cut index: want 0, got $status: $output"
  [ ! -e "$PROJECT_ROOT/tmp/fresh" ] || fail "the question wrote: $(find "$PROJECT_ROOT/tmp/fresh")"
  # With no repository there is no git to ask, and the writer's rule answers.
  rm -rf "$PROJECT_ROOT/.git"
  run gate_out_ignored tmp/kept
  [ "$status" -eq 1 ] || fail "no repository, the project's own .gitignore: want 1, got $status: $output"
  run gate_out_ignored tmp/fresh
  [ "$status" -eq 0 ] || fail "no repository, a new log directory: want 0, got $status: $output"
}

@test "with no git to run, gate_out_ignored says git could not say, where a repository is present (0186)" {
  # git_readonly answers 1 when it cannot run git at all, which is check-ignore's
  # own "not ignored", so the pre-flight offered its remedy for a git that never
  # ran.
  local stub="$DEVBIN_TEST_TMPDIR/nogit"
  git -C "$PROJECT_ROOT" init -q
  mkdir -p "$PROJECT_ROOT/tmp/kept" "$stub"
  printf '!keep\n' >"$PROJECT_ROOT/tmp/kept/.gitignore"
  # A git that exits 127, as a missing one does, so every git call fails.
  printf '#!/bin/sh\nexit 127\n' >"$stub/git"
  chmod +x "$stub/git"
  # THE CONTROL: with git, it answers not ignored.
  run gate_out_ignored tmp/kept
  [ "$status" -eq 1 ] || fail "with git: want 1, got $status: $output"
  # git_readonly's primed answer is cleared, so the stub is asked as a fresh
  # process asks it.
  _DEVBIN_GIT_LOCAL_VARS=""
  PATH="$stub:$PATH" run gate_out_ignored tmp/kept
  [ "$status" -eq 2 ] || fail "with no git to run: want 2, got $status: $output"
  # With no repository there is no git to ask, and the writer's rule answers.
  rm -rf "$PROJECT_ROOT/.git"
  PATH="$stub:$PATH" run gate_out_ignored tmp/kept
  [ "$status" -eq 1 ] || fail "no repository and no git to run: want 1, got $status: $output"
}

@test "a git that cannot say whether a directory is tracked gives it no .gitignore, and says so (0157)" {
  # A repository git reads, but whose ls-files fails -- eg a corrupt index --
  # was read as nothing tracked, and let `*` into a directory the project keeps.
  # One git refuses to read outright, as another user's, is the 0179 arms'.
  mkdir -p "$PROJECT_ROOT/tmp/reports"
  git -C "$PROJECT_ROOT" init -q
  mkdir -p "$DEVBIN_TEST_TMPDIR/fakegit"
  printf '#!/bin/sh\ncase " $* " in *" ls-files "*) exit 128 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" >"$DEVBIN_TEST_TMPDIR/fakegit/git"
  chmod +x "$DEVBIN_TEST_TMPDIR/fakegit/git"
  PATH="$DEVBIN_TEST_TMPDIR/fakegit:$PATH" run gate_out_ignore "$PROJECT_ROOT/tmp/reports"
  assert_success
  assert_output_contains "git could not say whether"
  [ ! -e "$PROJECT_ROOT/tmp/reports/.gitignore" ] || fail "a .gitignore was written where git could not say what is tracked"
}

@test "a repository git refuses to read gives a gate's log directory no .gitignore, a tracked one included, and says so (0179)" {
  # Asked of git, a refusal was a tree with no repository: rev-parse fails as
  # ls-files does, and `*` landed unannounced in a directory the project
  # tracks, hiding the next file it adds there. GIT_TEST_ASSUME_DIFFERENT_OWNER
  # is git's own switch for a repository owned by another user.
  mkdir -p "$PROJECT_ROOT/tmp/reports" "$PROJECT_ROOT/tmp/gates"
  printf 'kept\n' >"$PROJECT_ROOT/tmp/reports/summary.txt"
  git -C "$PROJECT_ROOT" init -q
  git -C "$PROJECT_ROOT" add -f tmp/reports/summary.txt
  git -C "$PROJECT_ROOT" -c user.email=t@t -c user.name=t commit -q -m kept
  require_git_refusal "$PROJECT_ROOT"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run gate_out_ignore "$PROJECT_ROOT/tmp/reports"
  assert_success
  assert_output_contains "git could not say whether $PROJECT_ROOT/tmp/reports is tracked"
  # git's own first line rides on it, naming why.
  assert_output_contains "is tracked, so it is given no .gitignore -- fatal: "
  [ ! -e "$PROJECT_ROOT/tmp/reports/.gitignore" ] || fail "a tracked directory was given a .gitignore in a repository git refused to read"
  # Untracked, it is still a directory git could not answer for.
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run gate_out_ignore "$PROJECT_ROOT/tmp/gates"
  assert_success
  assert_output_contains "git could not say whether $PROJECT_ROOT/tmp/gates is tracked"
  [ ! -e "$PROJECT_ROOT/tmp/gates/.gitignore" ] || fail "a log directory was given a .gitignore in a repository git refused to read"
}

@test "a .git above the project root, or a gitfile at it, is a repository git refused to read, never none (0179)" {
  # Where git's own discovery looks: a project in a subdirectory of a
  # repository, and a linked worktree, whose .git is a file.
  local mono="$DEVBIN_TEST_TMPDIR/mono" wt="$DEVBIN_TEST_TMPDIR/wt"
  mkdir -p "$mono/app/tmp/gates"
  git -C "$mono" init -q
  git -C "$mono" -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
  require_git_refusal "$mono"
  PROJECT_ROOT="$mono/app" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run gate_out_ignore "$mono/app/tmp/gates"
  assert_success
  assert_output_contains "git could not say whether $mono/app/tmp/gates is tracked"
  [ ! -e "$mono/app/tmp/gates/.gitignore" ] || fail "a .git above the project root was read as no repository"
  git -C "$mono" worktree add -q "$wt"
  [ -f "$wt/.git" ] || fail "the fixture's worktree has no gitfile, so this would prove nothing"
  mkdir -p "$wt/tmp/gates"
  PROJECT_ROOT="$wt" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run gate_out_ignore "$wt/tmp/gates"
  assert_success
  assert_output_contains "git could not say whether $wt/tmp/gates is tracked"
  [ ! -e "$wt/tmp/gates/.gitignore" ] || fail "a worktree's gitfile was read as no repository"
}

@test "a devbin started inside a gate reads the person from its own stdin, not the outer gate's flag (0158)" {
  # gate_exec marks what it runs as inside a gate, and a tool there keeps the
  # flag; a devbin started there is a new invocation, so 0088's rule holds for
  # its own gates: a stale or outer 1 cannot stand over a stdin that is not a
  # terminal.
  proj="$(mkproj inner <<'YAML'
project:
  name: inner
commands:
  check:
    options:
      flag:
        run: sh ./flag.sh
        log: true
YAML
  )"
  printf 'echo "inner-flag=$DEVBIN_GATE_TTY"\n' >"$proj/flag.sh"
  run env DEVBIN_IN_GATE=1 DEVBIN_GATE_TTY=1 sh -c 'cd "$1" && ./bin/devbin check flag </dev/null' _ "$proj"
  assert_success
  assert_output_contains "inner-flag=0"
}
