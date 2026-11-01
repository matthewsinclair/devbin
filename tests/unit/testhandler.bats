#!/usr/bin/env bats
# testhandler.bats - devbin's own test handler, bin/.devbin/cmd/test (0092)
#
# `bin/devbin test bats [paths...] [bats flags...]` is the route help documents
# for a targeted run. Until 0092 the handler ran `bats tests/unit` whatever it
# was given, so every targeted run through it was a full suite, and the only
# working route was bats itself.
#
# The handler runs for real through a DEVBIN_LIB shim whose run_gate is a stub
# printing the argv it was handed, one word per line after `ARGV`, so nothing
# runs a suite.
#
# Handed nothing for bats, the handler runs the whole suite in two lanes
# through bin/.devbin/cmd/.lib/bats-lanes (0190). The lane arms at the end run
# that script for real, over a fixture suite of their own.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# handler_argv <arg>... -- what devbin's test handler hands its gate, in a fixture
# root holding tests/unit/one.bats and tests/unit/two.bats.
handler_argv() {
  local shim="$DEVBIN_TEST_TMPDIR/shim" root="$DEVBIN_TEST_TMPDIR/root"
  mkdir -p "$shim" "$root/tests/unit"
  : >"$root/tests/unit/one.bats"
  : >"$root/tests/unit/two.bats"
  printf '. "%s/helpers"\n' "$DEVBIN_LIB" >"$shim/helpers"
  cat >"$shim/runlog" <<SH
. "$DEVBIN_LIB/runlog"
run_gate() {
  while [ "\$1" != -- ]; do printf '%s\n' "\$1" >>"$DEVBIN_TEST_TMPDIR/gate.flags"; shift; done
  shift
  printf 'ARGV\n'
  printf '%s\n' "\$@"
}
SH
  (cd "$root" && DEVBIN_LIB="$shim" PROJECT_ROOT="$root" bash "$DEVBIN_HOME/bin/.devbin/cmd/test" "$@" </dev/null)
}

# want <word>... -- the argv the gate must have been handed, as handler_argv prints it.
want() { printf 'ARGV\n'; printf '%s\n' "$@"; }

@test "test bats with nothing after it runs the whole suite, tests/unit, in lanes (0190)" {
  run handler_argv bats
  assert_success
  [ "$output" = "$(want bin/.devbin/cmd/.lib/bats-lanes tests/unit)" ] || fail "got: $output"
}

@test "a wrapper flag alone still runs the whole suite in lanes (0190)" {
  run handler_argv bats --purge
  assert_success
  [ "$output" = "$(want bin/.devbin/cmd/.lib/bats-lanes tests/unit)" ] || fail "got: $output"
}

@test "test bats with paths runs exactly those paths (0092)" {
  run handler_argv bats tests/unit/one.bats tests/unit/two.bats
  assert_success
  [ "$output" = "$(want bats tests/unit/one.bats tests/unit/two.bats)" ] || fail "got: $output"
}

@test "test bats passes bats' own flags through, and adds tests/unit when no path is given (0092)" {
  run handler_argv bats --filter 'help lists'
  assert_success
  [ "$output" = "$(want bats --filter 'help lists' tests/unit)" ] || fail "got: $output"
}

@test "a flag's value is not read as a path, even when it names one (0092)" {
  run handler_argv bats --filter tests
  assert_success
  [ "$output" = "$(want bats --filter tests tests/unit)" ] || fail "got: $output"
}

@test "flags and paths together pass through as given, with nothing added (0092)" {
  run handler_argv bats --filter x -j 2 tests/unit/one.bats
  assert_success
  [ "$output" = "$(want bats --filter x -j 2 tests/unit/one.bats)" ] || fail "got: $output"
}

@test "a wrapper flag goes to the gate, not to bats, and purges as asked (0092, 0087)" {
  run handler_argv bats --purge tests/unit/one.bats
  assert_success
  [ "$output" = "$(want bats tests/unit/one.bats)" ] || fail "bats was handed: $output"
  grep -qx -- --purge "$DEVBIN_TEST_TMPDIR/gate.flags" || fail "the gate was not handed --purge: $(cat "$DEVBIN_TEST_TMPDIR/gate.flags")"
}

@test "every bats flag that takes a value is known to the handler, read from this bats's own --help (0092)" {
  # The handler's list of value-taking flags is a copy of bats's vocabulary,
  # and a copy drifts: it missed --negative-filter. So the list is held
  # against the bats that is installed. Every flag --help shows with a <value>,
  # plus those whose help shows none but which take one, is handed an
  # EXISTING PATH as its value; if the handler reads that value as a path, it
  # adds no tests/unit, and the flag is named.
  local flags f missing=""
  flags="$(bats --help 2>&1 | sed -nE 's/^[[:space:]]+(-[A-Za-z], )?(--[a-z-]+) <.*/\1\2/p' | tr ',' '\n' | tr -d ' ')"
  [ -n "$flags" ] || fail "read no flags from bats --help"
  flags+=$'\n--line-reference-format\n--parallel-binary-name'
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    run handler_argv bats "$f" tests/unit/one.bats
    [ "$output" = "$(want bats "$f" tests/unit/one.bats tests/unit)" ] || missing+=" $f"
  done <<<"$flags"
  [ -z "$missing" ] || fail "the handler reads these flags' values as paths:$missing"
}

# ============================================================================
# THE LANES (issue 0190): bin/.devbin/cmd/.lib/bats-lanes, run for real over a
# fixture suite, one of its tests tagged serial
# ============================================================================

# lanes_fixture [fail-where] -- a fixture root holding a suite of tests, and
# print its root. One test is tagged serial. <fail-where> is `serial` or
# `parallel` to make one test in that lane fail.
#
# The test lines are printf ARGUMENTS, never lines of their own: bats reads any
# line of THIS file that starts `@test` or `# bats`, heredocs included, as
# belonging to this file.
lanes_fixture() {
  local root="$DEVBIN_TEST_TMPDIR/lanes" plain=true serial=true
  case "${1:-}" in
    serial) serial=false ;;
    parallel) plain=false ;;
  esac
  mkdir -p "$root/tests/unit"
  printf '%s\n' '@test "a one" { true; }' '@test "a two" { true; }' >"$root/tests/unit/a.bats"
  printf '%s\n' "@test \"b plain\" { $plain; }" '# bats test_tags=serial' "@test \"b serial\" { $serial; }" >"$root/tests/unit/b.bats"
  printf '%s\n' "$root"
}

# lanes_tally <root> -- the fixture suite's tests as `<all> <serial>`, read off
# the files it holds: each `@test` line is a test, and each serial tag line tags
# the test after it. So an expectation moves with the fixture, rather than
# being a number written beside it.
lanes_tally() {
  local all serial
  all="$(cat "$1"/tests/unit/*.bats | grep -c '^@test ')" || return 1
  serial="$(cat "$1"/tests/unit/*.bats | grep -c '^# bats test_tags=serial$')" || serial=0
  printf '%s %s\n' "$all" "$serial"
}

# lanes_run <root> [NAME=value...] -- run the lane runner in <root> over its
# tests/unit, with the environment assignments given. The variables the
# runner and bats read for the lanes are cleared first, so an outer run's own,
# as in help's `DEVBIN_TEST_JOBS=4 bin/devbin test all`, cannot reach an arm;
# an assignment given here still wins.
lanes_run() {
  local root="$1"
  shift
  (cd "$root" && env -u DEVBIN_TEST_JOBS -u BATS_PARALLEL_BINARY_NAME -u BATS_NUMBER_OF_PARALLEL_JOBS \
    "$@" DEVBIN_LIB="$DEVBIN_LIB" PROJECT_ROOT="$root" \
    bash "$DEVBIN_HOME/bin/.devbin/cmd/.lib/bats-lanes" tests/unit </dev/null)
}

# bats_recorder -- put a bats first on PATH that appends each argv it is handed
# to $DEVBIN_TEST_TMPDIR/bats.argv, one line each, and runs the real bats; print
# the directory to put on PATH. How many jobs a lane asked for is not in its
# output: bats runs files under GNU parallel with --keep-order, so a two-job
# stream reads exactly as a one-job one.
bats_recorder() {
  local dir="$DEVBIN_TEST_TMPDIR/recbats" real
  real="$(command -v bats)"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/bats.argv"\nexec "%s" "$@"\n' \
    "$DEVBIN_TEST_TMPDIR" "$real" >"$dir/bats"
  chmod +x "$dir/bats"
  : >"$DEVBIN_TEST_TMPDIR/bats.argv"
  printf '%s\n' "$dir"
}

# handed <argv> -- succeed when the recorded bats was handed exactly <argv>.
handed() {
  grep -qxF -e "$1" "$DEVBIN_TEST_TMPDIR/bats.argv" ||
    fail "bats was never handed '$1'; it was handed:
$(cat "$DEVBIN_TEST_TMPDIR/bats.argv")"
}

@test "the whole suite runs in two lanes: the untagged tests N at a time, then the serial ones, each test once (0190)" {
  require_command parallel "no GNU parallel on this runner"
  local root rec all serial tally jobs=2
  root="$(lanes_fixture)"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  rec="$(bats_recorder)"
  run lanes_run "$root" DEVBIN_TEST_JOBS="$jobs" PATH="$rec:$PATH"
  assert_success
  assert_output_contains "lanes: two. First $jobs tests at a time under GNU parallel"
  assert_output_contains "lanes: the serial lane, $serial test(s), one at a time"
  assert_output_contains "lanes: $((all - serial)) test(s) ran in parallel and $serial serially, all $all that bats counts in tests/unit, each once"
  # What each lane asked bats for, where the asking lands: N for the parallel
  # lane, and one at a time over only the file that carries the tag for the
  # serial lane.
  handed "--jobs $jobs --filter-tags !serial tests/unit"
  handed '--jobs 1 --filter-tags serial tests/unit/b.bats'
  # The serial test ran in the serial lane, after the parallel one, and only there.
  [ "$(printf '%s\n' "$output" | grep -c 'b serial')" -eq 1 ] || fail "b serial did not run exactly once: $output"
  local lane
  lane="$(sed -n '/the serial lane/,$p' <<<"$output")" && grep -qx 'ok 1 b serial' <<<"$lane" ||
    fail "b serial did not run in the serial lane: $output"
}

@test "a failure in either lane fails the run (0190)" {
  require_command parallel "no GNU parallel on this runner"
  local root where all serial tally
  for where in serial parallel; do
    root="$(lanes_fixture "$where")"
    tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
    read -r all serial <<<"$tally"
    run lanes_run "$root" DEVBIN_TEST_JOBS=2
    [ "$status" -ne 0 ] || fail "a failing $where-lane test exited 0: $output"
    # The last line names the lane that failed and its status, since a lane can
    # fail with no `not ok` line, and the seal's log tail shows this line.
    assert_output_contains "lanes: $((all - serial)) test(s) ran in parallel and $serial serially, all $all that bats counts in tests/unit, each once; the $where lane exited 1"
  done
}

@test "the lanes refuse a run that does not account for every test bats counts (0190)" {
  # A bats whose serial selection comes back empty, as a tag read differently
  # by another bats would make it: the count stays honest, the lanes do not.
  require_command parallel "no GNU parallel on this runner"
  local root real all serial tally
  root="$(lanes_fixture)"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  real="$(command -v bats)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/fakebats"
  printf '#!/usr/bin/env bash\ncase " $* " in *" --filter-tags serial "*) printf "1..0\\n"; exit 0 ;; esac\nexec "%s" "$@"\n' "$real" >"$DEVBIN_TEST_TMPDIR/fakebats/bats"
  chmod +x "$DEVBIN_TEST_TMPDIR/fakebats/bats"
  run lanes_run "$root" DEVBIN_TEST_JOBS=2 PATH="$DEVBIN_TEST_TMPDIR/fakebats:$PATH"
  [ "$status" -ne 0 ] || fail "a serial lane that ran nothing passed: $output"
  assert_output_contains "lanes: $((all - serial)) test(s) ran in parallel and 0 serially, $((all - serial)) in all, but bats counts $all in tests/unit: the lanes did not run every test exactly once"
}

@test "without GNU parallel the suite runs as before, one test at a time, and says why (0190)" {
  local root all serial tally pos
  root="$(lanes_fixture)"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  # One run in file order: b serial's place is its @test line's among the suite's.
  pos="$(cat "$root"/tests/unit/*.bats | grep '^@test ' | grep -n '"b serial"' | cut -d: -f1)"
  [ -n "$pos" ] || fail "the fixture holds no b serial test"
  run lanes_run "$root" BATS_PARALLEL_BINARY_NAME=devbin-no-such-parallel
  assert_success
  assert_output_contains "lanes: one, serial, because GNU parallel is not installed: there is no devbin-no-such-parallel on PATH"
  assert_output_contains "1..$all"
  assert_output_contains "ok $pos b serial"
}

@test "a parallel that is not GNU's is not used, and the run says so (0190)" {
  local root all serial tally
  root="$(lanes_fixture)"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  mkdir -p "$DEVBIN_TEST_TMPDIR/otherpar"
  printf '#!/bin/sh\necho "usage: parallel [OPTIONS] command -- arguments"\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/otherpar/parallel"
  chmod +x "$DEVBIN_TEST_TMPDIR/otherpar/parallel"
  run lanes_run "$root" PATH="$DEVBIN_TEST_TMPDIR/otherpar:$PATH"
  assert_success
  assert_output_contains "lanes: one, serial, because the parallel on PATH, $DEVBIN_TEST_TMPDIR/otherpar/parallel, is not GNU parallel"
  assert_output_contains "1..$all"
}

@test "DEVBIN_TEST_JOBS=1 runs the suite one test at a time, and says so (0190)" {
  local root all serial tally
  root="$(lanes_fixture)"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  run lanes_run "$root" DEVBIN_TEST_JOBS=1
  assert_success
  assert_output_contains "lanes: one, serial, because DEVBIN_TEST_JOBS is 1"
  assert_output_contains "1..$all"
}

@test "a DEVBIN_TEST_JOBS that is not a whole number of jobs is refused, naming it (0190)" {
  local root bad
  root="$(lanes_fixture)"
  for bad in 0 x 2.5 -3; do
    run lanes_run "$root" DEVBIN_TEST_JOBS="$bad"
    [ "$status" -ne 0 ] || fail "DEVBIN_TEST_JOBS=$bad was accepted: $output"
    assert_output_contains "DEVBIN_TEST_JOBS is '$bad', and it must be a whole number of jobs, 1 or more"
    # No bats ran: no plan line at all, whatever the fixture's size.
    ! grep -qE '^1\.\.[0-9]+$' <<<"$output" || fail "DEVBIN_TEST_JOBS=$bad was refused, and bats ran anyway:\n$output"
  done
}

@test "the jobs default to half the CPUs, and never fewer than two (0190)" {
  require_command parallel "no GNU parallel on this runner"
  local root cpus want rec
  root="$(lanes_fixture)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/cpus"
  for cpus in 6:3 3:2; do
    want="${cpus#*:}"
    printf '#!/bin/sh\necho %s\n' "${cpus%%:*}" >"$DEVBIN_TEST_TMPDIR/cpus/nproc"
    chmod +x "$DEVBIN_TEST_TMPDIR/cpus/nproc"
    rec="$(bats_recorder)"
    run lanes_run "$root" PATH="$rec:$DEVBIN_TEST_TMPDIR/cpus:$PATH"
    assert_success
    assert_output_contains "lanes: two. First $want tests at a time under GNU parallel"
    assert_output_contains "(${cpus%%:*} CPUs here; DEVBIN_TEST_JOBS sets the number)"
    handed "--jobs $want --filter-tags !serial tests/unit"
  done
  # Neither nproc nor getconf answering: 4 is taken, and said to be, rather
  # than printed as though it were counted.
  printf '#!/bin/sh\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/cpus/nproc"
  printf '#!/bin/sh\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/cpus/getconf"
  chmod +x "$DEVBIN_TEST_TMPDIR/cpus/nproc" "$DEVBIN_TEST_TMPDIR/cpus/getconf"
  rec="$(bats_recorder)"
  run lanes_run "$root" PATH="$rec:$DEVBIN_TEST_TMPDIR/cpus:$PATH"
  assert_success
  assert_output_contains "could not count this machine's CPUs (neither nproc nor getconf answered with a number), so taking 4"
  handed "--jobs 2 --filter-tags !serial tests/unit"
}

@test "DEVBIN_TEST_JOBS=all runs the parallel lane on every CPU the probe counts, one lane on one CPU, and is refused where nothing counts them (WP04)" {
  require_command parallel "no GNU parallel on this runner"
  local root rec counted
  root="$(lanes_fixture)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/cpus"
  # The probe's answer is the stub's, and every expectation is read from it.
  for counted in 6 1; do
    printf '#!/bin/sh\necho %s\n' "$counted" >"$DEVBIN_TEST_TMPDIR/cpus/nproc"
    chmod +x "$DEVBIN_TEST_TMPDIR/cpus/nproc"
    rec="$(bats_recorder)"
    run lanes_run "$root" DEVBIN_TEST_JOBS=all PATH="$rec:$DEVBIN_TEST_TMPDIR/cpus:$PATH"
    assert_success
    if [ "$counted" -gt 1 ]; then
      assert_output_contains "lanes: two. First $counted tests at a time under GNU parallel"
      handed "--jobs $counted --filter-tags !serial tests/unit"
    else
      assert_output_contains "lanes: one, serial, because DEVBIN_TEST_JOBS is all, and this machine has one CPU"
    fi
  done
  # Neither nproc nor getconf answering: refused, naming the setting, and no
  # bats ran -- never cpu_count's guess of 4 taken as every CPU.
  printf '#!/bin/sh\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/cpus/nproc"
  printf '#!/bin/sh\nexit 1\n' >"$DEVBIN_TEST_TMPDIR/cpus/getconf"
  chmod +x "$DEVBIN_TEST_TMPDIR/cpus/nproc" "$DEVBIN_TEST_TMPDIR/cpus/getconf"
  run lanes_run "$root" DEVBIN_TEST_JOBS=all PATH="$DEVBIN_TEST_TMPDIR/cpus:$PATH"
  [ "$status" -ne 0 ] || fail "DEVBIN_TEST_JOBS=all was taken where nothing counts the CPUs: $output"
  assert_output_contains "DEVBIN_TEST_JOBS is 'all', and neither nproc nor getconf could count this machine's CPUs"
  ! grep -qE '^1\.\.[0-9]+$' <<<"$output" || fail "DEVBIN_TEST_JOBS=all was refused, and bats ran anyway:\n$output"
}

@test "with no test tagged serial there is no serial lane, and the run says so (0190)" {
  require_command parallel "no GNU parallel on this runner"
  local root all serial tally
  root="$(lanes_fixture)"
  printf '%s\n' '@test "b plain" { true; }' '@test "b once serial" { true; }' >"$root/tests/unit/b.bats"
  tally="$(lanes_tally "$root")" || fail "the fixture's tests could not be counted"
  read -r all serial <<<"$tally"
  run lanes_run "$root" DEVBIN_TEST_JOBS=2
  assert_success
  assert_output_contains "lanes: no test is tagged serial, so there is no serial lane"
  assert_output_contains "lanes: $all test(s) ran in parallel and $serial serially, all $all that bats counts in tests/unit, each once"
}
