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
# written leave it. gates-tmpdir in the tree makes them first write the TMPDIR
# they were given to <worktree>.seen-tmpdir and, when it is <worktree>.tmp,
# leave a read-only directory in it, as a bats run killed mid-file leaves its
# fixture cache. gates-gatecache makes them write the DEVBIN_GATE_CACHE they
# were given to <worktree>.seen-gatecache and, when it is the host's
# work/demo-leg.cache, add the commit they stand on to its `runs`.
# gates-tmplog makes them leave a step's log at the top of their TMPDIR, as a
# gate that keeps a step's output there does, and a file below a directory
# there, as a private build's target holds. gates-pids makes them write their
# runner's pid and their own, `<runner> <gates>`, to <worktree>.pids as they
# start, so an arm can kill the run as a host's reboot does (kill_run). The
# project does not ignore tmp/, so dirt a read leaves there is seen. Prints
# the project's path.
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
if [ -e gates-pids ]; then printf '%s %s\n' "$PPID" "$$" >"$PWD.pids" || exit 1; fi
if [ -e gates-tmpdir ]; then
  printf '%s\n' "${TMPDIR-unset}" >"$PWD.seen-tmpdir" || exit 1
  if [ "${TMPDIR-}" = "$PWD.tmp" ]; then
    mkdir -p "$TMPDIR/cache/entries" && : >"$TMPDIR/cache/entries/one" && chmod -R a-w "$TMPDIR/cache" || exit 1
  fi
fi
if [ -e gates-tmplog ]; then
  printf 'the failing step said this\n' >"$TMPDIR/gate-step.log" || exit 1
  mkdir -p "$TMPDIR/target" && printf 'a build product\n' >"$TMPDIR/target/product" || exit 1
fi
if [ -e gates-gatecache ]; then
  printf '%s\n' "${DEVBIN_GATE_CACHE-unset}" >"$PWD.seen-gatecache" || exit 1
  if [ "${DEVBIN_GATE_CACHE-}" = "$HOME/work/demo-leg.cache" ] && [ -d "$DEVBIN_GATE_CACHE" ]; then
    git rev-parse HEAD >>"$DEVBIN_GATE_CACHE/runs" || exit 1
  fi
fi
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

# kill_run <wt> -- the run at <wt> killed as a host's reboot or the
# out-of-memory killer ends one: its runner first, so it never writes the
# gates' exit status, then its gates, each waited for until it is gone. The
# project's tree must hold gates-pids.
kill_run() {
  local runner gates p deadline
  await_file "$1.pids"
  read -r runner gates <"$1.pids" || fail "no pids beside $1"
  for p in "$runner" "$gates"; do
    kill -KILL "$p" || fail "pid $p of the run at $1 could not be killed"
    deadline=$((SECONDS + LEG_WAIT_SECONDS))
    while kill -0 "$p" 2>/dev/null; do
      [ "$SECONDS" -lt "$deadline" ] || fail "pid $p of the run at $1 outlived its kill"
      sleep 0.1
    done
  done
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

@test "0333: release_leg_start sends the previous release's tag beside R, forced over the host's older copy of it, so a gate that reads the last release finds it in a fresh bare repo; a tag this repository does not hold is unknown, naming it, and nothing is sent" {
  local proj first sha wt bare
  proj="$(leg_project)"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a -m "the last release" v0.1.0
  first="$(git -C "$proj" rev-parse HEAD)"
  printf 'next\n' >"$proj/next"
  leg_commit "$proj" "after the last release"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  bare="$HOSTS/kov/work/demo-leg.git"
  run release_leg_start "$proj" kov demo "$first" v0.1.0
  [ "$(leg_word)" = pending ] || fail "a start sending the tag: $output"
  release_gates "$(leg_wt kov "$first")"
  [ "$(git -C "$bare" rev-parse refs/tags/v0.1.0)" = "$(git -C "$proj" rev-parse refs/tags/v0.1.0)" ] ||
    fail "the host's bare repo does not hold the tag this machine has"
  # The tag made again here: the host's copy is this machine's, so it is replaced.
  git -C "$proj" -c user.name=t -c user.email=t@t tag -f -a -m "the last release, made again" v0.1.0 "$first" >/dev/null
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha" v0.1.0
  [ "$(leg_word)" = pending ] || fail "a start over the host's older copy of the tag: $output"
  release_gates "$wt"
  [ "$(git -C "$bare" rev-parse refs/tags/v0.1.0)" = "$(git -C "$proj" rev-parse refs/tags/v0.1.0)" ] ||
    fail "the host kept its older copy of the tag"
  run release_leg_start "$proj" kov demo "$sha" v9.9.9
  [ "$(leg_word)" = unknown ] || fail "a tag this repository does not hold: $output"
  assert_output_contains "the previous release's tag 'v9.9.9' is no tag in $proj"
  every_call_batch
}

@test "0333: release_previous_tag names the newest release's tag other than the target's own, by version and not by spelling, and nothing when no other tag names a release" {
  local repo
  repo="$DEVBIN_TEST_TMPDIR/tags"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@t -c maintenance.auto=false -c gc.auto=0 commit -q --allow-empty -m one
  git -C "$repo" tag v0.2.0
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; printf "[%s]\n" "$(release_previous_tag "v{version}" v0.2.0)" "$(release_previous_tag "v{version}" "")"' _ "$DEVBIN_LIB_DIR" "$repo"
  assert_success
  [ "$output" = $'[]\n[v0.2.0]' ] || fail "with one release, the target's own and none: $output"
  git -C "$repo" tag v0.10.0
  git -C "$repo" tag v0.9.0
  git -C "$repo" tag v0.11.0-rc1
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; printf "[%s]\n" "$(release_previous_tag "v{version}" v0.11.0)" "$(release_previous_tag "v{version}" v0.10.0)"' _ "$DEVBIN_LIB_DIR" "$repo"
  assert_success
  [ "$output" = $'[v0.10.0]\n[v0.9.0]' ] || fail "the newest release other than the target's own: $output"
}

@test "0334: a remote leg's gates run with their own TMPDIR, <worktree>.tmp on the host's disk, over one the host's own startup set, made afresh over what an earlier run at R left there and named in the leg's log, and the run's clear removes it with a read-only directory the gates left in it" {
  local proj sha wt
  proj="$(leg_project)"
  : >"$proj/gates-tmpdir"
  leg_commit "$proj" "gates that say which TMPDIR they were given"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov/tmp"
  wt="$(leg_wt kov "$sha")"
  # What an earlier run at R left there, beside a worktree removed by hand.
  mkdir -p "$wt.tmp/left"
  : >"$wt.tmp/left/file"
  # A TMPDIR the host's own startup sets, as a shell's startup file can, which
  # the shell that starts the gates inherits.
  TMPDIR="$HOSTS/kov/tmp" run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "a leg started over an earlier run's TMPDIR: $output"
  await_file "$wt/tmp/release/20260101-0000.GATES.errors"
  [ "$(cat "$wt.seen-tmpdir")" = "$wt.tmp" ] ||
    fail "the gates were given TMPDIR '$(cat "$wt.seen-tmpdir")', not the run's own $wt.tmp"
  [ ! -e "$wt.tmp/left" ] || fail "what an earlier run at R left in the TMPDIR is still there"
  [ -f "$wt.tmp/cache/entries/one" ] || fail "the gates could not write in their TMPDIR"
  grep -qxF "TMPDIR: $wt.tmp" "$wt.log" || fail "the leg's log does not name the gates' TMPDIR: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run's read: $output"
  [ ! -e "$wt.tmp" ] || fail "the run was cleared from the host and its TMPDIR left there: $(ls -lR "$wt.tmp")"
  every_call_batch
}

@test "0335: a remote leg's gates are handed DEVBIN_GATE_CACHE, work/<project>-leg.cache beside the bare repo, over one the host's startup set, named in the leg's log, and kept when the run is cleared, so the next run finds what the last left there" {
  local proj first sha wt cache
  proj="$(leg_project)"
  : >"$proj/gates-gatecache"
  leg_commit "$proj" "gates that say which DEVBIN_GATE_CACHE they were given"
  first="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  cache="$HOSTS/kov/work/demo-leg.cache"
  wt="$(leg_wt kov "$first")"
  # A DEVBIN_GATE_CACHE the host's own startup sets, which the shell that
  # starts the gates inherits.
  DEVBIN_GATE_CACHE="$HOSTS/kov/elsewhere" run release_leg_start "$proj" kov demo "$first"
  [ "$(leg_word)" = pending ] || fail "the first start: $output"
  await_file "$wt/tmp/release/20260101-0000.GATES.errors"
  [ "$(cat "$wt.seen-gatecache")" = "$cache" ] ||
    fail "the gates were given DEVBIN_GATE_CACHE '$(cat "$wt.seen-gatecache")', not the project's $cache"
  grep -qxF "DEVBIN_GATE_CACHE: $cache" "$wt.log" || fail "the leg's log does not name the gates' cache: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$first"
  [ "$(leg_word)" = green ] || fail "the first run's read: $output"
  [ "$(cat "$cache/runs")" = "$first" ] || fail "the clear removed what the gates kept, or they kept nothing: $(cat "$cache/runs" 2>&1)"
  printf 'next\n' >"$proj/next"
  leg_commit "$proj" "the next commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the next start: $output"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the next run's read: $output"
  [ "$(cat "$cache/runs")" = "$first"$'\n'"$sha" ] || fail "the next run did not find the first run's line: $(cat "$cache/runs" 2>&1)"
  every_call_batch
}

# leg_kept_log <sha> -- the log of the run at <sha> on kov, as this machine
# keeps it once the run is read and cleared.
leg_kept_log() { printf '%s/%s.log\n' "$(release_leg_dir "$proj" kov)" "${1:0:12}"; }

@test "0361: a remote leg whose gates end red appends each file at the top of their TMPDIR to its log before the run is cleared, naming it, and not what lies in a directory there, then the log's last line again; a green run appends nothing" {
  local proj sha wt log before
  proj="$(leg_project)"
  : >"$proj/gates-tmplog"
  : >"$proj/gates-red"
  leg_commit "$proj" "red gates that keep a step's log in their TMPDIR"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the red run's start: $output"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = failed ] || fail "the red run's read: $output"
  [ ! -e "$wt.tmp" ] || fail "the red run was cleared and its TMPDIR left on the host"
  log="$(leg_kept_log "$sha")"
  [ -f "$log" ] || fail "this machine kept no log for the red run at $log"
  grep -qxF -- "--- the gates exited 1: $wt.tmp/gate-step.log, kept from their TMPDIR, which is removed with the run ---" "$log" ||
    fail "the kept log names no file kept from the TMPDIR: $(cat "$log")"
  grep -qxF "the failing step said this" "$log" || fail "the kept log does not hold the step's log: $(cat "$log")"
  ! grep -qF "a build product" "$log" || fail "a file below a directory in the TMPDIR was appended: $(cat "$log")"
  # The kept files open on an empty line, so the line before them is two up.
  before="$(awk '/^--- the gates exited /{print p2; exit} {p2 = p1; p1 = $0}' "$log")"
  [ -n "$before" ] && [ "$(tail -n 1 "$log")" = "$before" ] ||
    fail "the log's last line before the kept files, '$before', is not its last line again: $(cat "$log")"
  rm "$proj/gates-red"
  leg_commit "$proj" "green gates that keep a step's log in their TMPDIR"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the green run's start: $output"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the green run's read: $output"
  log="$(leg_kept_log "$sha")"
  [ -f "$log" ] || fail "this machine kept no log for the green run at $log"
  ! grep -qF -- "kept from their TMPDIR" "$log" || fail "a green run appended its TMPDIR to its log: $(cat "$log")"
  ! grep -qF "the failing step said this" "$log" || fail "a green run appended its TMPDIR to its log: $(cat "$log")"
  every_call_batch
}

@test "0361: a remote leg's start holds the host's gate cache to the bound it is handed: one over it is emptied, read-only directories and all, before the gates start, one within it kept, each named in the leg's log, and a bound that is no whole number of KiB is unknown with nothing sent" {
  local proj sha wt cache
  proj="$(leg_project)"
  : >"$proj/gates-gatecache"
  leg_commit "$proj" "gates that keep a line in their cache"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  cache="$HOSTS/kov/work/demo-leg.cache"
  wt="$(leg_wt kov "$sha")"
  # A cache an earlier build filled past the bound, a read-only directory in it.
  mkdir -p "$cache/target/deps"
  head -c 262144 /dev/zero >"$cache/target/deps/big"
  chmod -R a-w "$cache/target"
  run release_leg_start "$proj" kov demo "$sha" "" 64
  [ "$(leg_word)" = pending ] || fail "a start over a cache past its bound: $output"
  await_file "$wt/tmp/release/20260101-0000.GATES.errors"
  [ ! -e "$cache/target" ] || fail "the cache over its bound was not emptied: $(ls -lR "$cache")"
  grep -qE "^DEVBIN_GATE_CACHE emptied: $cache held [0-9]+ KiB, over its bound of 64 KiB, with [0-9]+ KiB free on its disk, so it is emptied and this run builds cold\$" "$wt.log" ||
    fail "the leg's log does not say the cache was emptied: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run after the cache was emptied: $output"
  [ "$(cat "$cache/runs")" = "$sha" ] || fail "the gates did not find their cache made afresh: $(cat "$cache/runs" 2>&1)"
  printf 'next\n' >"$proj/next"
  leg_commit "$proj" "the next commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha" "" 1048576
  [ "$(leg_word)" = pending ] || fail "a start over a cache within its bound: $output"
  grep -qE "^DEVBIN_GATE_CACHE kept: $cache holds [0-9]+ KiB, within its bound of 1048576 KiB, with [0-9]+ KiB free on its disk\$" "$wt.log" ||
    fail "the leg's log does not say the cache was kept: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run over a cache within its bound: $output"
  [ "$(sed -n 1p "$cache/runs")" = "$(git -C "$proj" rev-parse HEAD~1)" ] || fail "the cache within its bound was not kept: $(cat "$cache/runs" 2>&1)"
  printf 'more\n' >"$proj/more"
  leg_commit "$proj" "a commit no run is started at"
  sha="$(git -C "$proj" rev-parse HEAD)"
  run release_leg_start "$proj" kov demo "$sha" "" 12G
  [ "$(leg_word)" = unknown ] || fail "a bound that is no whole number of KiB: $output"
  assert_output_contains "the gate cache's bound '12G' is not a whole number of KiB"
  [ ! -e "$(leg_wt kov "$sha")" ] || fail "a start with a bound that is no number made a run"
  every_call_batch
}

@test "0361: a remote leg's start leaves the host's gate cache as it stands while another run of the project is going there, whose gates may be reading it, and names that run in the leg's log" {
  local proj first sha wt cache going
  proj="$(leg_project)"
  first="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov/work"
  cache="$HOSTS/kov/work/demo-leg.cache"
  # Another run of the project, its runner alive and its gates going, held.
  going="$(leg_wt kov "$first")"
  run release_leg_start "$proj" kov demo "$first"
  [ "$(leg_word)" = pending ] || fail "the start of the run going: $output"
  : >"$proj/second"
  leg_commit "$proj" "a second commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  mkdir -p "$cache/target"
  head -c 262144 /dev/zero >"$cache/target/big"
  # An ended run's directory, with its status, and a TMPDIR, neither of which
  # is one going.
  mkdir -p "$HOSTS/kov/work/demo-leg-ba9876543210" "$HOSTS/kov/work/demo-leg-ba9876543210.tmp"
  printf '0\n' >"$HOSTS/kov/work/demo-leg-ba9876543210.rc"
  run release_leg_start "$proj" kov demo "$sha" "" 64
  [ "$(leg_word)" = pending ] || fail "a start beside a run going: $output"
  [ -f "$cache/target/big" ] || fail "the cache was emptied while another run of the project was going"
  grep -qxF "DEVBIN_GATE_CACHE kept: a run of demo is going in $going, which may be reading $cache, so it is left as it stands" "$wt.log" ||
    fail "the leg's log does not name the run going: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run beside a run going: $output"
  release_gates "$going"
  every_call_batch
}

@test "I14a851d: a remote leg's start empties the host's gate cache within its bound while its disk has less than the bound free, naming the free size in the leg's log, so the run cannot fill the disk from a cache kept for it" {
  local proj sha wt cache huge
  proj="$(leg_project)"
  : >"$proj/gates-gatecache"
  leg_commit "$proj" "gates that keep a line in their cache"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  cache="$HOSTS/kov/work/demo-leg.cache"
  wt="$(leg_wt kov "$sha")"
  mkdir -p "$cache/target"
  head -c 262144 /dev/zero >"$cache/target/big"
  # A bound of 1 EiB: the cache is well within it, and no disk here has it free.
  huge=1125899906842624
  run release_leg_start "$proj" kov demo "$sha" "" "$huge"
  [ "$(leg_word)" = pending ] || fail "a start over a cache within its bound on a disk with less free: $output"
  await_file "$wt/tmp/release/20260101-0000.GATES.errors"
  [ ! -e "$cache/target" ] || fail "the cache within its bound, on a disk with less than the bound free, was kept: $(ls -lR "$cache")"
  grep -qE "^DEVBIN_GATE_CACHE emptied: $cache held [0-9]+ KiB, within its bound of $huge KiB, with [0-9]+ KiB free on its disk, under the bound, so it is emptied and this run builds cold\$" "$wt.log" ||
    fail "the leg's log does not say the cache was emptied for the disk's free space: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run after the cache was emptied: $output"
  [ "$(cat "$cache/runs")" = "$sha" ] || fail "the gates did not find their cache made afresh: $(cat "$cache/runs" 2>&1)"
  # A disk whose free space cannot be read: the size alone decides, so the
  # cache within its bound is left as it stands, and the line says why.
  mkdir -p "$HOSTS/kov/.bin"
  printf '#!/usr/bin/env bash\necho "df: the disk cannot be read" >&2\nexit 1\n' >"$HOSTS/kov/.bin/df"
  chmod +x "$HOSTS/kov/.bin/df"
  printf 'next\n' >"$proj/next"
  leg_commit "$proj" "the next commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha" "" "$huge"
  [ "$(leg_word)" = pending ] || fail "a start on a disk whose free space cannot be read: $output"
  grep -qE "^DEVBIN_GATE_CACHE refused: $cache holds [0-9]+ KiB, within its bound of $huge KiB, and the free space on its disk could not be read \(df: the disk cannot be read\), so it is left as it stands\$" "$wt.log" ||
    fail "the leg's log does not say why the cache was left as it stands: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run beside a cache left as it stands: $output"
  # Read only once the gates have ended: they add their own line as they
  # start, so a read before their end races them.
  [ "$(cat "$cache/runs")" = "$(git -C "$proj" rev-parse HEAD~1)"$'\n'"$sha" ] || fail "the cache was not left as it stands for this run: $(cat "$cache/runs" 2>&1)"
  every_call_batch
}

# ============================================================================
# A START CLEARS THE PROJECT'S ENDED RUNS (issue 0367)
# ============================================================================
# A cut that stops red leaves each remote leg's run to finish on its host, and
# a re-cut is at another commit, so no read of that run comes back for it.
# Each start on a host now finishes such runs first, as a read does: the log
# copied back, then the run cleared.

@test "0367: a leg's start clears each ended run of the project at another commit from the host, its log copied back first, and leaves a run still going and the start's own" {
  local proj first going sha wtf wtg wt dir
  proj="$(leg_project)"
  first="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wtf="$(leg_wt kov "$first")"
  run release_leg_start "$proj" kov demo "$first"
  [ "$(leg_word)" = pending ] || fail "the first start: $output"
  release_gates "$wtf"
  # The cut stopped there: nothing read the run at the first commit.
  : >"$proj/second"
  leg_commit "$proj" "a second commit"
  going="$(git -C "$proj" rev-parse HEAD)"
  wtg="$(leg_wt kov "$going")"
  run release_leg_start "$proj" kov demo "$going"
  [ "$(leg_word)" = pending ] || fail "the second start: $output"
  : >"$proj/third"
  leg_commit "$proj" "a third commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  [ "$(leg_word)" = pending ] || fail "the start beside an ended run and a run going: $output"
  dir="$(release_leg_dir "$proj" kov)"
  [ -f "$dir/${first:0:12}.log" ] || fail "the ended run's log was not copied back to $dir"
  [ ! -e "$wtf" ] && [ ! -e "$wtf.log" ] && [ ! -e "$wtf.rc" ] || fail "the ended run at ${first:0:12} was left on the host"
  if git -C "$HOSTS/kov/work/demo-leg.git" rev-parse -q --verify "refs/devbin/legs/$first" >/dev/null; then
    fail "refs/devbin/legs/$first was left on the host"
  fi
  [ -d "$wtg" ] && [ -e "$wtg.log" ] || fail "the run still going at ${going:0:12} was cleared"
  [ ! -e "$dir/${going:0:12}.log" ] || fail "the run still going had its log copied back"
  # Ended, the start's own run is left to its read, even by a start again at it.
  release_gates "$wt"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "a start again at its own commit: $output"
  [ -d "$wt" ] && [ -e "$wt.rc" ] || fail "a start cleared the run at its own commit"
  release_gates "$wtg"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the start's own run, read: $output"
  every_call_batch
}

@test "0367: an ended run whose log cannot be copied back stays on the host, warned of, and the start goes on" {
  local proj first sha wtf
  proj="$(leg_project)"
  first="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wtf="$(leg_wt kov "$first")"
  run release_leg_start "$proj" kov demo "$first"
  [ "$(leg_word)" = pending ] || fail "the first start: $output"
  release_gates "$wtf"
  : >"$proj/second"
  leg_commit "$proj" "a second commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  : >"$HOSTS/kov/.fail-scp"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  assert_output_contains "the leg's log on kov could not be copied back"
  assert_output_contains "so the run is left there for the next read"
  assert_output_matches $'(^|\n)pending\t'
  [ -d "$wtf" ] && [ -e "$wtf.rc" ] || fail "an ended run whose log could not be copied was cleared"
  rm -f "$HOSTS/kov/.fail-scp"
  release_gates "$(leg_wt kov "$sha")"
  every_call_batch
}

# ============================================================================
# A RUN WHOSE RUNNER IS GONE (issue I0a62f4a)
# ============================================================================
# A run killed with its host, by the out-of-memory killer or by a full disk
# never writes its exit status. It read as a run going at every later start,
# which then left the gate cache unbounded, and as running at every read, to
# the cut's deadline. A run with no status is going only while its runner is
# alive, found by its command line, and a gone run is cleared as an ended run
# is. A leg ref no run's worktree holds is deleted.

@test "I0a62f4a: a remote leg's start holds the host's gate cache to its bound beside a run of the project with no exit status and no runner, which is gone and reads no cache" {
  local proj sha wt cache dead
  proj="$(leg_project)"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov/work"
  cache="$HOSTS/kov/work/demo-leg.cache"
  wt="$(leg_wt kov "$sha")"
  mkdir -p "$cache/target"
  head -c 262144 /dev/zero >"$cache/target/big"
  # A run's directory with no exit status beside it and no runner alive.
  dead="$HOSTS/kov/work/demo-leg-0123456789ab"
  mkdir -p "$dead"
  run release_leg_start "$proj" kov demo "$sha" "" 64
  [ "$(leg_word)" = pending ] || fail "a start beside a run whose runner is gone: $output"
  [ ! -e "$cache/target" ] || fail "the cache was left over its bound beside a run whose runner is gone: $(ls -lR "$cache")"
  grep -qE "^DEVBIN_GATE_CACHE emptied: $cache held [0-9]+ KiB, over its bound of 64 KiB, with [0-9]+ KiB free on its disk, so it is emptied and this run builds cold\$" "$wt.log" ||
    fail "the leg's log does not say the cache was emptied: $(cat "$wt.log")"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run beside a run whose runner is gone: $output"
  every_call_batch
}

@test "I0a62f4a: a leg's start clears a run of the project at another commit whose runner is gone with no exit status as an ended run, warned of, its log copied back with a last line that says so, and its ref deleted" {
  local proj killed sha wtk wt dir
  proj="$(leg_project)"
  : >"$proj/gates-pids"
  leg_commit "$proj" "gates that say their pids"
  killed="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wtk="$(leg_wt kov "$killed")"
  run release_leg_start "$proj" kov demo "$killed"
  [ "$(leg_word)" = pending ] || fail "the start of the run then killed: $output"
  kill_run "$wtk"
  : >"$proj/second"
  leg_commit "$proj" "a second commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  assert_output_matches $'(^|\n)pending\t'
  dir="$(release_leg_dir "$proj" kov)"
  assert_output_contains "the run of demo at ${killed:0:12} on kov has no exit status, and its runner is gone, so it is cleared as an ended run is, its log copied back to $dir first"
  [ -f "$dir/${killed:0:12}.log" ] || fail "the gone run's log was not copied back to $dir"
  grep -qE "^--- no exit status, and its runner is gone: read at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z by this host's clock ---\$" <<<"$(tail -n 1 "$dir/${killed:0:12}.log")" ||
    fail "the gone run's log does not end with the line that says so: $(cat "$dir/${killed:0:12}.log")"
  [ ! -e "$wtk" ] && [ ! -e "$wtk.log" ] || fail "the gone run at ${killed:0:12} was left on the host"
  if git -C "$HOSTS/kov/work/demo-leg.git" rev-parse -q --verify "refs/devbin/legs/$killed" >/dev/null; then
    fail "refs/devbin/legs/$killed was left on the host"
  fi
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the start's own run: $output"
  every_call_batch
}

@test "I0a62f4a: a leg's start at the commit of a run whose runner is gone with no exit status clears that run and starts its own afresh, where it waited on the gone run to its deadline" {
  local proj sha wt dir
  proj="$(leg_project)"
  : >"$proj/gates-pids"
  leg_commit "$proj" "gates that say their pids"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the first start: $output"
  kill_run "$wt"
  rm -f "$wt.pids"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  assert_output_matches $'(^|\n)pending\t'
  dir="$(release_leg_dir "$proj" kov)"
  assert_output_contains "the run of demo at ${sha:0:12} on kov has no exit status, and its runner is gone, so it is cleared as an ended run is, its log copied back to $dir first"
  refute_output_contains "was started there before"
  # The gates of a run started afresh say their pids again.
  await_file "$wt.pids"
  release_gates "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = green ] || fail "the run started afresh at the gone run's commit: $output"
  every_call_batch
}

@test "I0a62f4a: release_leg_read reads a run whose runner is gone with no exit status as unknown, naming it, where it read running to the deadline, and clears it as an ended run, warned of, its log copied back with a last line that says so" {
  local proj sha wt log
  proj="$(leg_project)"
  : >"$proj/gates-pids"
  leg_commit "$proj" "gates that say their pids"
  sha="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  [ "$(leg_word)" = pending ] || fail "the start: $output"
  kill_run "$wt"
  run release_leg_read "$proj" kov demo "$sha"
  assert_success
  assert_output_matches $'(^|\n)unknown\tthe gates at '"${sha:0:12}"' on kov have no exit status, and their runner is gone: '
  assert_output_contains "the run of demo at ${sha:0:12} on kov has no exit status, and its runner is gone, so it is cleared as an ended run is"
  log="$(leg_kept_log "$sha")"
  [ -f "$log" ] || fail "the gone run's log was not copied back to $log"
  grep -qE "^--- no exit status, and its runner is gone: read at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z by this host's clock ---\$" <<<"$(tail -n 1 "$log")" ||
    fail "the gone run's log does not end with the line that says so: $(cat "$log")"
  [ ! -e "$wt" ] && [ ! -e "$wt.log" ] || fail "the gone run was left on the host"
  # Read again, the run is this machine's record, unknown from its log.
  run release_leg_read "$proj" kov demo "$sha"
  [ "$(leg_word)" = unknown ] || fail "the gone run, read again: $output"
  every_call_batch
}

@test "I0a62f4a: a leg's start deletes each leg ref of the project on the host that no run's worktree holds, a stopped start's and a worktree's whose directory is gone, and keeps the ref of a run that is there" {
  local proj going stopped pruned sha wtg wtp wt repo list
  proj="$(leg_project)"
  going="$(git -C "$proj" rev-parse HEAD)"
  mkdir -p "$HOSTS/kov"
  repo="$HOSTS/kov/work/demo-leg.git"
  wtg="$(leg_wt kov "$going")"
  run release_leg_start "$proj" kov demo "$going"
  [ "$(leg_word)" = pending ] || fail "the start of a run going: $output"
  # A start that stopped after its send-pack: the host refused to start it.
  : >"$proj/second"
  leg_commit "$proj" "a second commit"
  stopped="$(git -C "$proj" rev-parse HEAD)"
  : >"$HOSTS/kov/.fail-start"
  run release_leg_start "$proj" kov demo "$stopped"
  [ "$(leg_word)" = unknown ] || fail "a start the host refused: $output"
  rm -f "$HOSTS/kov/.fail-start"
  git -C "$repo" rev-parse -q --verify "refs/devbin/legs/$stopped" >/dev/null ||
    fail "the start the host refused left no ref behind"
  # An ended run whose worktree's directory is gone: git still lists it.
  : >"$proj/third"
  leg_commit "$proj" "a third commit"
  pruned="$(git -C "$proj" rev-parse HEAD)"
  wtp="$(leg_wt kov "$pruned")"
  run release_leg_start "$proj" kov demo "$pruned"
  [ "$(leg_word)" = pending ] || fail "the start of the run whose directory goes: $output"
  release_gates "$wtp"
  rm -rf "$wtp"
  : >"$proj/fourth"
  leg_commit "$proj" "a fourth commit"
  sha="$(git -C "$proj" rev-parse HEAD)"
  wt="$(leg_wt kov "$sha")"
  run release_leg_start "$proj" kov demo "$sha"
  assert_success
  assert_output_matches $'(^|\n)pending\t'
  if git -C "$repo" rev-parse -q --verify "refs/devbin/legs/$stopped" >/dev/null; then
    fail "the ref of the start that stopped after its send-pack was left on the host"
  fi
  if git -C "$repo" rev-parse -q --verify "refs/devbin/legs/$pruned" >/dev/null; then
    fail "the ref of the run whose worktree's directory is gone was left on the host"
  fi
  list="$(git -C "$repo" worktree list --porcelain)"
  ! grep -qF -- "demo-leg-${pruned:0:12}" <<<"$list" || fail "git still lists the worktree whose directory is gone: $list"
  refute_output_contains "${pruned:0:12}"
  git -C "$repo" rev-parse -q --verify "refs/devbin/legs/$going" >/dev/null || fail "the ref of the run going was deleted"
  release_gates "$wtg"
  release_gates "$wt"
  every_call_batch
}
