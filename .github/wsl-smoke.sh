#!/usr/bin/env bash
#
# wsl-smoke.sh <devbin checkout> <work dir> -- the smoke list (ST0008),
# run on two fixture projects that declare their commands the way a consuming
# project does. The Windows CI leg runs it inside WSL; it runs on any machine
# that meets devbin's prerequisites, so it can be driven before a push.
#
# AT-6.2 (fixture without intent/) and AT-6.5 (fixture with intent/).
#
# NEVER ON ANYONE'S REPOSITORY: both projects are built here, under the work
# dir, from nothing. An adopting project's own run is its acceptance, not this
# script's.
#
# The fixture WITH intent/ meets the critic gate in `check all`. With no
# `intent` on PATH the gate must refuse and name the cause; with one, it
# must pass. Either way the expectation is asserted, so neither outcome is
# taken for the other.
#
# Every step runs whatever came before it, and the verdict lists each failed
# step by fixture and name: one pass that surfaces every breach.
set -euo pipefail

usage() {
  printf 'usage: %s <devbin checkout> <work dir>\n' "${0##*/}" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
# A relative argument is spelled from ./, so an exported CDPATH is never
# searched for it and cd prints nothing into the capture (issue 0267).
from_here() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf './%s\n' "$1" ;;
  esac
}
src="$(cd "$(from_here "$1")" && pwd -P)"
mkdir -p "$2"
work="$(cd "$(from_here "$2")" && pwd -P)"
[ -x "$src/bin/devbin" ] || {
  printf 'wsl-smoke: %s has no executable bin/devbin\n' "$src" >&2
  exit 2
}
# Asked of find, whose status is read: a work dir it cannot read must stop the
# run, not pass as empty.
entries="$(find "$work" -mindepth 1 -maxdepth 1 -print)" || {
  printf 'wsl-smoke: could not read %s (above)\n' "$work" >&2
  exit 2
}
[ -z "$entries" ] || {
  printf 'wsl-smoke: %s is not empty; the fixtures are built from nothing\n' "$work" >&2
  exit 2
}

failed=""
log="$work/smoke.log"
: >"$log"

# step <fixture> <name> <command...> -- run one item of the list in the
# fixture, its output to the log, and record a failure. A failed step's output
# is printed as well, since the log lives inside WSL on a runner that is thrown
# away.
#
# THE COMMAND RUNS UNDER `||`, WHERE BASH TURNS ERREXIT OFF FOR ALL OF IT, so
# every step function below chains its commands with && or returns explicitly:
# a failure mid-function would otherwise be lost to the function's last line.
step() {
  local fx="$1" name="$2" rc=0 out
  shift 2
  out="$work/step.out"
  printf '\n=== %s: %s\n' "$fx" "$name" | tee -a "$log"
  (cd "$work/$fx" && "$@") >"$out" 2>&1 || rc=$?
  cat "$out" >>"$log"
  if [ "$rc" -eq 0 ]; then
    printf 'PASS %s: %s\n' "$fx" "$name" | tee -a "$log"
  else
    cat "$out"
    printf 'FAIL %s: %s (exit %s)\n' "$fx" "$name" "$rc" | tee -a "$log"
    failed="$failed $fx:$name"
  fi
}

# write_stub <path> <body> -- an executable stub, its body one printf line.
write_stub() {
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" >"$1"
  chmod +x "$1"
}

# make_fixture <name> -- a project with devbin vendored by the real installer,
# then given its own config and commands, as a consuming project is. The stub
# bodies are scripts, so what they expand is expanded when they run.
# shellcheck disable=SC2016
make_fixture() {
  local fx="$work/$1"
  mkdir -p "$fx"
  git -C "$fx" init -q
  "$src/bin/devbin" install --into "$fx" >/dev/null
  mkdir -p "$fx/scripts"
  write_stub "$fx/scripts/lint" 'printf "lint: clean\n"'
  write_stub "$fx/scripts/analyse" 'printf "analyse: clean\n"'
  write_stub "$fx/scripts/unit" 'printf "unit: 1 passed\n"'
  # The server writes a marker once it is up, then stays up until stopped.
  write_stub "$fx/scripts/serve" 'printf "up\n" >"${0%/*}/../server.up"; exec sleep 600'
  write_stub "$fx/bin/.devbin/cmd/package" 'printf "packaged\n" >"$PROJECT_ROOT/package.out"'
  write_stub "$fx/bin/.devbin/cmd/contract" 'printf "contract: held\n"'
  write_stub "$fx/scripts/clean" 'rm -rf "${0%/*}/../build"'
  printf '0.1.0\n' >"$fx/VERSION"
  cat >"$fx/bin/.devbin/config.yaml" <<YAML
project:
  name: $1
  alias: fx

commands:
  check:
    options:
      lint:
        run: scripts/lint
      analyse:
        run: scripts/analyse
  test:
    options:
      unit:
        run: scripts/unit
  server:
    run: scripts/serve
  clean:
    run: scripts/clean
YAML
  printf 'server.up\npackage.out\nbuild/\ntmp/\n' >"$fx/.gitignore"
  git -C "$fx" add -A
  git -C "$fx" -c user.name=smoke -c user.email=smoke@example.invalid commit -qm fixture
}

# shell_init_dvb -- dvb, defined by shell-init bash, found from a subdirectory.
shell_init_dvb() {
  mkdir -p deep/er &&
    bash -c 'eval "$(bin/devbin shell-init bash)" && cd deep/er && dvb --version'
}

# server_start_stop -- the server comes up, is still up when stopped, and
# ends on the signal that stopped it. devbin execs the server, so $! is the
# server's own process.
server_start_stop() {
  local pid rc=0
  rm -f server.up || return
  bin/devbin server &
  pid=$!
  for _ in $(seq 1 50); do
    [ -e server.up ] && break
    sleep 0.2
  done
  if [ ! -e server.up ]; then
    kill "$pid" 2>/dev/null || true # it may never have started; either way this step fails
    printf 'the server did not come up within 10s\n'
    return 1
  fi
  # Asked BEFORE it is reaped: a server that came up and then died on its own
  # must fail here rather than pass as stopped.
  kill -0 "$pid" 2>/dev/null || {
    printf 'the server came up and then exited before it was stopped\n'
    return 1
  }
  kill -TERM "$pid" || return
  wait "$pid" || rc=$?
  [ "$rc" -eq 143 ] || {
    printf 'the server ended with %s, not on the SIGTERM that stopped it (143)\n' "$rc"
    return 1
  }
}

# clean_run -- the project's clean removes the build tree it regenerates.
clean_run() {
  mkdir -p build && : >build/artefact &&
    bin/devbin clean &&
    [ ! -e build ]
}

package_run() {
  bin/devbin package &&
    [ -e package.out ]
}

# check_all_critic -- in a project carrying intent/: refuse naming intent with
# no intent on PATH, pass with one.
check_all_critic() {
  local out rc=0
  out="$(bin/devbin check all 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if command -v intent >/dev/null 2>&1; then
    [ "$rc" -eq 0 ]
  else
    [ "$rc" -ne 0 ] || {
      printf 'check all passed with no intent on PATH\n'
      return 1
    }
    # The refusal must be the critic gate's alone and must name the cause. The
    # fixture's own name carries "intent", so the cause is matched whole.
    grep -qxF 'FAILED: critic' <<<"$out" || {
      printf 'check all did not fail on the critic gate alone\n'
      return 1
    }
    grep -qF 'intent not found' <<<"$out" || {
      printf 'the critic gate refused without naming intent as the cause\n'
      return 1
    }
  fi
}

smoke() {
  local fx="$1" check="$2"
  step "$fx" "shell-init bash and dvb" shell_init_dvb
  step "$fx" "check all" "$check"
  step "$fx" "test all" bin/devbin test all
  step "$fx" "server started and stopped" server_start_stop
  step "$fx" "package" package_run
  step "$fx" "contract" bin/devbin contract
  step "$fx" "version check" bin/devbin version check
  step "$fx" "clean" clean_run
  step "$fx" "help" bin/devbin help
}

check_all() { bin/devbin check all; }

make_fixture plain
smoke plain check_all

# An Intent project, as a consuming project may be. With intent on
# PATH it is made by intent itself, declaring shell, and a shell file is left
# staged so the critic examines something. Without, the directory alone is
# what makes the gate active (lib/builtins, _DEVBIN_BUILTIN_NEEDS).
make_fixture intented
if command -v intent >/dev/null 2>&1; then
  (cd "$work/intented" && intent init --lang shell intented >/dev/null)
  write_stub "$work/intented/scripts/staged" 'printf "staged\n"'
  git -C "$work/intented" add scripts/staged
else
  mkdir -p "$work/intented/intent"
fi
smoke intented check_all_critic

printf '\nlog: %s\n' "$log"
if [ -n "$failed" ]; then
  printf 'FAILED:%s\n' "$failed"
  exit 1
fi
echo "Smoke list passed on both fixtures."
