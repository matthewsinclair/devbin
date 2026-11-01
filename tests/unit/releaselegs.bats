#!/usr/bin/env bats
# releaselegs.bats - lib/release.legs, the release core's remote legs (ST0011 WP-05)
#
# EVERY ARM RUNS AGAINST FAKE HOSTS. The stubs PATH holds an `ssh` and an `scp`
# that reach a host only when $HOSTS/<host> exists, and there run what they
# were handed on this machine, with that directory as HOME and git's exec path
# first, so the remote halves, send-pack's receive-pack and the copy back all
# run as they would on a host. Nothing leaves this machine: no real host is
# reached, kovacs included.
#
# The fixture project's bin/devbin answers `release gates` as R's runtime
# does: it opens its GATES pair in flight, as open_run_log opens one, then
# HOLDS until the arm makes <worktree>.go beside the run, then seals. So an arm
# sees a run going, as a real leg is seen, and releases it before it reads the
# verdict. Its pair names the platform `fake host / bash 5`, which is no
# platform this machine has, so a pair read as green on it was read on the
# host's own platform (seal_verdict's empty <platform>), never this machine's.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  # shellcheck source=lib/release.legs
  . "$DEVBIN_LIB_DIR/release.legs"
  init_colors off
  HOSTS="$DEVBIN_TEST_TMPDIR/hosts"
  mkdir -p "$HOSTS" "$DEVBIN_TEST_TMPDIR/stubs"
  fake_ssh
  fake_scp
  PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH"
}
teardown() { devbin_teardown; }

# LEG_WAIT_SECONDS bounds every wait here: await_file's, and the fixture
# gates' own hold, after which they end unsealed, so no arm can hang on a run
# it never released. A deadline, never a count anything is compared with.
LEG_WAIT_SECONDS=20

# leg_project -- a committed project at $DEVBIN_TEST_TMPDIR/proj whose
# bin/devbin answers `release gates` as R's runtime does: its GATES pair
# opened in flight under tmp/release, with inflight_marker's own words, held
# until <worktree>.go exists, then sealed, green unless the tree holds
# gates-red. gates-die in the tree ends it before the pair is opened,
# gates-crash with the pair still in flight, and gates-killed with its seal
# emptied, reading green, and status 137, as gates killed while their seal was
# written leave it. The project does not ignore tmp/, so dirt a read leaves
# there is seen. Prints the project's path.
leg_project() {
  local proj="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$proj/bin" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'inflight=%q\n' "$(inflight_marker)"
    printf 'deadline=%s\n' "$LEG_WAIT_SECONDS"
    cat <<'SH'
[ "$1 $2" = "release gates" ] || { echo "this fake devbin answers release gates alone" >&2; exit 1; }
if [ -e gates-die ]; then echo "bash 3.2.57 is below devbin's floor of 5"; exit 1; fi
sha="$(git rev-parse HEAD)" || exit 1
mkdir -p tmp/release || exit 1
stem=tmp/release/20260101-0000.GATES
{
  printf 'devbin| invocation, one argument per line:\n'
  printf 'devbin|   platform: fake host / bash 5\n'
  printf 'devbin|   commit: %s\n' "$sha"
  printf 'devbin| \n'
} >"$stem.out"
printf '%s\n' "$inflight" >"$stem.errors"
if [ -e gates-crash ]; then echo "the gates died with their seal unwritten"; exit 3; fi
waited=0
until [ -e "$PWD.go" ]; do
  [ "$waited" -lt "$((deadline * 10))" ] || { echo "nobody released the gates"; exit 4; }
  sleep 0.1
  waited=$((waited + 1))
done
printf 'devbin| commit at close: %s\n' "$sha" >>"$stem.out"
if [ -e gates-red ]; then
  printf 'a gate failed\n' >"$stem.errors"
  exit 1
fi
: >"$stem.errors"
if [ -e gates-killed ]; then echo "the gates were killed while their seal was written"; exit 137; fi
SH
  } >"$proj/bin/devbin" || return 1
  chmod +x "$proj/bin/devbin" || return 1
  git -C "$proj" init -q -b main || return 1
  leg_commit "$proj" "a project with sealed gates" || return 1
  printf '%s\n' "$proj"
}

# leg_commit <proj> <message> -- every change in <proj> committed.
leg_commit() {
  git -C "$1" add -A &&
    git -C "$1" -c maintenance.auto=false -c gc.auto=0 -c user.name=t -c user.email=t@t commit -qm "$2"
}

# await_file <path> -- wait for <path>, which a detached run writes; fail
# naming it when it has not come by the deadline.
await_file() {
  local deadline=$((SECONDS + LEG_WAIT_SECONDS))
  until [ -e "$1" ]; do
    [ "$SECONDS" -lt "$deadline" ] || fail "$1 never appeared within ${LEG_WAIT_SECONDS}s"
    sleep 0.1
  done
}

# leg_wt <host> <sha> -- where the run at <sha> lives on a fake host.
leg_wt() { printf '%s/%s/work/demo-leg-%s\n' "$HOSTS" "$1" "${2:0:12}"; }

# release_gates <wt> -- let the held gates at <wt> seal, and wait for them to
# end, their exit status written beside the run.
release_gates() {
  : >"$1.go"
  await_file "$1.rc"
}

# leg_word -- the word of the last `run`.
leg_word() { printf '%s' "${output%%$'\t'*}"; }

# every_call_batch -- every ssh and scp logged so far asked with no prompt, the
# connect bound and the bound on a host gone silent.
every_call_batch() {
  local line asked=0
  while IFS= read -r line; do
    asked=$((asked + 1))
    [[ "$line" == *"-o BatchMode=yes"* && "$line" == *"ConnectTimeout=$RELEASE_LEG_CONNECT_TIMEOUT"* ]] ||
      fail "a call asked without BatchMode or the connect bound: $line"
    [[ "$line" == *"-o ServerAliveInterval=${RELEASE_LEG_ALIVE_INTERVAL:-unset}"* &&
      "$line" == *"-o ServerAliveCountMax=${RELEASE_LEG_ALIVE_COUNT:-unset}"* ]] ||
      fail "a call asked with no bound on a host gone silent: $line"
  done <"$DEVBIN_TEST_TMPDIR/ssh.calls"
  [ "$asked" -gt 0 ] || fail "no ssh or scp was logged"
}

@test "an ssh to a leg's host asks with a bound on a host gone silent beside its bounded connect, the one set of options every ssh and scp there asks with, so a host that stops answering mid-read ends that read and never holds the cut's loop past its deadline (ST0011 WP-05)" {
  mkdir -p "$HOSTS/kov"
  run release_leg_reach kov </dev/null
  [ "$(leg_word)" = reached ] || fail "a host ssh reaches: $output"
  every_call_batch
}

# AT-3.1
@test "release_leg_reach reads a host ssh reaches as reached, one it cannot as absent, one whose shell fails as unknown, and a name that is no alias as absent (ST0011 WP05)" {
  local writer
  mkdir -p "$HOSTS/kov" "$HOSTS/down" "$HOSTS/odd"
  : >"$HOSTS/down/.unreachable"
  : >"$HOSTS/odd/.broken"
  # ssh -n: reach sends nothing on stdin and never reads its caller's, which
  # here stays open until its writer's deadline, so a reach that read it would
  # answer only once the writer had ended.
  mkfifo "$DEVBIN_TEST_TMPDIR/held"
  (
    exec 3>&- >"$DEVBIN_TEST_TMPDIR/held"
    exec sleep "$LEG_WAIT_SECONDS"
  ) &
  writer=$!
  run release_leg_reach kov <"$DEVBIN_TEST_TMPDIR/held"
  kill -0 "$writer" 2>/dev/null || fail "reach read its caller's stdin to the end, as an ssh without -n does"
  kill "$writer"
  assert_success
  [ "$(leg_word)" = reached ] || fail "a host ssh reaches: $output"
  run release_leg_reach down
  [ "$(leg_word)" = absent ] || fail "a host ssh cannot reach: $output"
  assert_output_contains "ssh could not reach down: ssh: connect to host down port 22: Operation timed out"
  run release_leg_reach nowhere
  [ "$(leg_word)" = absent ] || fail "a host ssh cannot resolve: $output"
  run release_leg_reach odd
  [ "$(leg_word)" = unknown ] || fail "a host reached whose shell fails: $output"
  assert_output_contains "odd answered, and uname -s failed there (exit 1)"
  run release_leg_reach "two words"
  [ "$(leg_word)" = absent ] || fail "a name that is no alias: $output"
  assert_output_contains "is no ssh host alias"
  every_call_batch
}

# AT-3.1
@test "release_leg_start sends R by send-pack, running no hook, removes a status an earlier run left there, and answers pending while the gates it started detached still run (ST0011 WP05)" {
  local proj sha wt
  proj="$(leg_project)"
  sha="$(git -C "$proj" rev-parse HEAD)"
  # A pre-push hook that would refuse, and say so: send-pack runs none.
  printf '#!/bin/sh\n: >"%s/hook-ran"\nexit 1\n' "$DEVBIN_TEST_TMPDIR" >"$proj/.git/hooks/pre-push"
  chmod +x "$proj/.git/hooks/pre-push"
  mkdir -p "$HOSTS/kov"
  wt="$(leg_wt kov "$sha")"
  # The status an earlier run at R left beside a worktree removed by hand,
  # which would read as this run's end at its first poll.
  mkdir -p "${wt%/*}"
  printf '0\n' >"$wt.rc"
  printf '0\n' >"$wt.rc.part"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  [ "$(leg_word)" = pending ] || fail "a leg started: $output"
  assert_output_contains "the gates at ${sha:0:12}"
  assert_output_contains "work/demo-leg-${sha:0:12}.log on kov"
  [ ! -e "$DEVBIN_TEST_TMPDIR/hook-ran" ] || fail "send-pack ran the project's pre-push hook"
  [ "$(git -C "$HOSTS/kov/work/demo-leg.git" rev-parse "refs/devbin/legs/$sha")" = "$sha" ] ||
    fail "R is not refs/devbin/legs/$sha in the host's bare repo"
  # Detached: the start has answered, and the gates it started still hold.
  await_file "$wt/tmp/release/20260101-0000.GATES.errors"
  [ ! -e "$wt.rc" ] && [ ! -e "$wt.rc.part" ] ||
    fail "the gates had ended, or an earlier run's status was left, by the time the start answered: $(cat "$wt.log")"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "a read while the gates run: $output"
  assert_output_contains "are running on kov"
  # A second start finds the run already there, and its seal is the record.
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "a leg started twice: $output"
  assert_output_contains "was started there before"
  release_gates "$wt"
  grep -qF "leg: demo at $sha" "$wt.log" || fail "the leg's log does not open naming the run: $(cat "$wt.log")"
  grep -qE '^git: /' "$wt.log" || fail "the leg's log does not say where git resolves: $(cat "$wt.log")"
}

# AT-3.1
@test "release_leg_read copies an ended run's pair back with its times, reads it on the host's own platform, and clears the run from the host, keeping the bare repo (ST0011 WP05)" {
  local proj sha wt dir
  proj="$(leg_project)"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start: $output"
  release_gates "$wt"
  touch -t 202601010000.00 "$wt"/tmp/release/*.GATES.*
  touch -t 202601010100.00 "$DEVBIN_TEST_TMPDIR/later"
  run release_leg_read "$proj" kov demo "$sha"
  assert_success
  [ "$(leg_word)" = green ] || fail "a green run on the host: $output"
  dir="$(release_leg_dir "$proj" kov)"
  assert_output_contains "$dir/"
  [ -f "$dir/20260101-0000.GATES.out" ] && [ -f "$dir/20260101-0000.GATES.errors" ] || fail "the pair was not copied back to $dir"
  [ "$DEVBIN_TEST_TMPDIR/later" -nt "$dir/20260101-0000.GATES.out" ] || fail "the copy did not keep the pair's times"
  [ -f "$dir/${sha:0:12}.log" ] || fail "the leg's log was not copied back"
  # The copies come back under run logs that ignore themselves, in a project
  # whose own .gitignore does not cover tmp/, so its tree stays clean.
  [ -z "$(git -C "$proj" status --porcelain)" ] || fail "the read left the project with changes: $(git -C "$proj" status --porcelain)"
  [ ! -e "$wt" ] && [ ! -e "$wt.log" ] && [ ! -e "$wt.rc" ] || fail "the ended run was not cleared from the host"
  if git -C "$HOSTS/kov/work/demo-leg.git" rev-parse -q --verify "refs/devbin/legs/$sha" >/dev/null; then
    fail "refs/devbin/legs/$sha was left on the host"
  fi
  [ -d "$HOSTS/kov/work/demo-leg.git" ] || fail "the bare repo was not kept for the next leg"
  # Cleared from the host, the run stays this machine's record.
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "a run read again after it was cleared: $output"
  every_call_batch
}

# AT-3.1
@test "release_leg_read reads a red run as failed; a run that ended unsealed, with its seal in flight, or with a green seal beside a status that is not 0, as unknown naming why, then and at every later read; keeps a run on the host while its log cannot be copied back; and reads a run never started as none (ST0011 WP05)" {
  local proj first sha wt dir out
  proj="$(leg_project)"
  first="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  dir="$(release_leg_dir "$proj" kov)"
  : >"$proj/gates-red"
  leg_commit "$proj" "a gate that fails"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the red start: $output"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = failed ] || fail "a red run on the host: $output"
  # Ended before its pair was opened: its exit status and its log's last line.
  rm -f "$proj/gates-red"
  : >"$proj/gates-die"
  leg_commit "$proj" "gates that cannot start"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start of gates that cannot start: $output"
  await_file "$wt.rc"
  # A log that cannot be copied back keeps the run on the host, its only copy,
  # and says so; the next read asks again.
  : >"$HOSTS/kov/.fail-scp"
  out="$(release_leg_read "$proj" kov demo "$sha" 2>"$DEVBIN_TEST_TMPDIR/warned")"
  [ "${out%%$'\t'*}" = unknown ] || fail "a run that ended with no seal, its log not copied back: $out"
  [[ "$out" == *"exited 1 with no seal: bash 3.2.57 is below devbin's floor of 5"* ]] || fail "the word does not name why: $out"
  grep -qF "could not be copied back" "$DEVBIN_TEST_TMPDIR/warned" || fail "no warning that the log was not copied back: $(cat "$DEVBIN_TEST_TMPDIR/warned")"
  [ -d "$wt" ] && [ -f "$wt.log" ] || fail "a run whose log was not copied back was cleared from the host"
  rm -f "$HOSTS/kov/.fail-scp"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a run that ended with no seal: $output"
  assert_output_contains "exited 1 with no seal: bash 3.2.57 is below devbin's floor of 5"
  [ ! -e "$wt" ] || fail "a run that ended with no seal was not cleared from the host"
  [ -f "$dir/${sha:0:12}.log" ] || fail "the log of a run that ended with no seal was not copied back"
  # Cleared from the host, it stays unknown here, read from its log, never none.
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a run that ended with no seal, read after it was cleared: $output"
  assert_output_contains "ends: bash 3.2.57 is below devbin's floor of 5"
  # Ended with its pair still in flight.
  rm -f "$proj/gates-die"
  : >"$proj/gates-crash"
  leg_commit "$proj" "gates that die mid-run"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start of gates that die: $output"
  await_file "$wt.rc"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a run that ended with its seal in flight: $output"
  assert_output_contains "exited 3 with their seal unwritten"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a run that ended with its seal in flight, read after it was cleared: $output"
  assert_output_contains "ends: the gates died with their seal unwritten"
  # Sealed green and then killed: gates killed while their seal was written
  # leave it emptied, reading green, beside a status that is not 0, which is
  # no verdict, then or at any later read.
  rm -f "$proj/gates-crash"
  : >"$proj/gates-killed"
  leg_commit "$proj" "gates killed at their seal"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start of gates killed at their seal: $output"
  release_gates "$wt"
  [ "$(cat "$wt.rc")" = 137 ] || fail "the fixture's gates did not end with status 137: $(cat "$wt.rc")"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a seal reading green beside status 137: $output"
  assert_output_contains "exited 137, and their seal reads green, so it is not their verdict and is not kept"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "gates killed at their seal, read after they were cleared: $output"
  assert_output_contains "ends: the gates were killed while their seal was written"
  # Never started, and no pair here for it.
  run release_leg_read "$proj" kov demo "$first"
  [ "$(leg_word)" = none ] || fail "a run never started: $output"
  assert_output_contains "no run of the gates at ${first:0:12} on kov"
}

# AT-3.1
@test "a leg's mechanism failures are unknown, naming the step and what was said, never a verdict (ST0011 WP05)" {
  local proj sha wt
  proj="$(leg_project)"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/down" "$HOSTS/nopack" "$HOSTS/nostart" "$HOSTS/nocopy"
  : >"$HOSTS/down/.unreachable"
  : >"$HOSTS/nopack/.fail-receive-pack"
  : >"$HOSTS/nostart/.fail-start"
  run release_leg_start "$proj" down demo "$sha"
  assert_success
  [ "$(leg_word)" = unknown ] || fail "a start on a host ssh cannot reach: $output"
  assert_output_contains "making the bare repo work/demo-leg.git, on down failed: ssh: connect to host down port 22"
  run release_leg_read "$proj" down demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a read on a host ssh cannot reach: $output"
  assert_output_contains "reading the run at ${sha:0:12}, on down failed"
  run release_leg_start "$proj" nopack demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a send-pack that fails: $output"
  assert_output_contains "git send-pack of ${sha:0:12} on nopack failed"
  run release_leg_start "$proj" nostart demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a start the host refuses: $output"
  assert_output_contains "starting the gates at ${sha:0:12}, on nostart failed: the host refused to start anything"
  # An ended run whose pair cannot be copied back.
  wt="$(leg_wt nocopy "$sha")"
  run release_leg_start "$proj" nocopy demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start on nocopy: $output"
  release_gates "$wt"
  : >"$HOSTS/nocopy/.fail-scp"
  run release_leg_read "$proj" nocopy demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "a copy that fails: $output"
  assert_output_contains "copying the seal at ${sha:0:12} back, on nocopy failed: scp:"
  [ -d "$wt" ] || fail "a run whose pair was never read was cleared from the host"
  run release_leg_start "$proj" down demo "${sha:0:12}"
  [ "$(leg_word)" = unknown ] || fail "a sha that is not whole: $output"
  assert_output_contains "is not a full commit sha"
  run release_leg_read "$proj" down "two words" "$sha"
  [ "$(leg_word)" = unknown ] || fail "a project name that is no plain word: $output"
  assert_output_contains "cannot name a repository on a host"
  every_call_batch
}
