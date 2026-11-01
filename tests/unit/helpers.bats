#!/usr/bin/env bats
# helpers.bats - lib/helpers and the shared-option layer in lib/resolve (WP-05)
#
# The fold of the functions every source project carried its own copy of. Two
# things are being proved here beyond "the function works":
#
#   1. lib/helpers loads and works with NOTHING else sourced. Handlers are
#      separate processes that source it alone, so a dependency creeping into it
#      would break every handler in every project.
#   2. The corpus's four hand-written option setters really do collapse into one
#      config-driven function -- including the value validation and the refusal
#      message that made them worth having.

load "../lib/test_helper"

setup() {
  devbin_setup
  # Deliberately the ONLY thing sourced: see (1) above.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# Source the config reader and resolver on top, for the shared-option tests.
load_resolve() {
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  # shellcheck source=lib/resolve
  . "$DEVBIN_LIB_DIR/resolve"
  export DEVBIN_DIR="$DEVBIN_TEST_TMPDIR/.devbin"
  mkdir -p "$DEVBIN_DIR/cmd"
}

# ============================================================================
# THE FILE ITSELF
# ============================================================================

@test "lib/helpers loads with no other library sourced" {
  run bash -c "set -euo pipefail; . '$DEVBIN_LIB_DIR/helpers'; step loaded; ok"
  assert_success
  assert_output_contains "==> loaded"
  assert_output_contains "done."
}

@test "sourcing lib/helpers twice is free" {
  run bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    . '$DEVBIN_LIB_DIR/helpers'
    printf 'guard=%s\n' \"\$_DEVBIN_HELPERS_LOADED\""
  assert_success
  assert_output_contains "guard=1"
}

@test "lib/helpers reads no config" {
  # A grep, not a behaviour test, because the failure it guards is a LATER
  # edit adding a cfg_ call that happens to work in the dispatcher (where
  # config is loaded) and breaks only in a handler.
  run grep -nE '\bcfg_(get|has|list|load)\b' "$DEVBIN_LIB_DIR/helpers"
  assert_failure
}

# ============================================================================
# OUTPUT PRIMITIVES
# ============================================================================

@test "die prefixes with the project name, writes to stderr, and exits 1" {
  run bash -c "set -euo pipefail
    DEVBIN_NAME=myapp
    . '$DEVBIN_LIB_DIR/helpers'
    die 'it broke' 2>&1 1>/dev/null"
  assert_exit_code 1
  assert_output "myapp: it broke"
}

@test "warn prefixes and continues" {
  run bash -c "set -euo pipefail
    DEVBIN_NAME=shop
    . '$DEVBIN_LIB_DIR/helpers'
    warn 'careful' 2>&1 1>/dev/null
    printf 'still here\n'"
  assert_success
  assert_output_contains "shop: careful"
  assert_output_contains "still here"
}

@test "the name prefix defaults to devbin before config is loaded" {
  run bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    warn 'early' 2>&1 1>/dev/null"
  assert_success
  assert_output "devbin: early"
}

@test "not_yet names the gate and exits 3, never a quiet success" {
  run bash -c "set -euo pipefail
    DEVBIN_NAME=demo
    . '$DEVBIN_LIB_DIR/helpers'
    not_yet 'demo publish' 'WP-08' 2>&1 1>/dev/null"
  assert_exit_code 3
  assert_output_contains "demo publish is not built yet"
  assert_output_contains "gated on: WP-08"
}

@test "require_tool passes for a real tool and dies for an absent one" {
  require_tool sh
  run require_tool definitely-not-a-real-tool "install it first"
  assert_exit_code 1
  assert_output_contains "definitely-not-a-real-tool not found"
  assert_output_contains "install it first"
}

@test "init_colors sets nothing when off or when NO_COLOR is set" {
  init_colors off
  [ -z "$green" ] && [ -z "$red" ] && [ -z "$reset" ]
  NO_COLOR=1 init_colors auto
  [ -z "$green" ] && [ -z "$red" ] && [ -z "$reset" ]
}

# ============================================================================
# strip_ansi
# ============================================================================

@test "strip_ansi removes escape sequences and keeps the text" {
  result="$(printf '\033[31mFAILED\033[0m: 3 tests\n' | strip_ansi)"
  [ "$result" = "FAILED: 3 tests" ]
}

@test "strip_ansi leaves plain text untouched" {
  result="$(printf 'plain line\n' | strip_ansi)"
  [ "$result" = "plain line" ]
}

# ============================================================================
# abs_path
# ============================================================================

@test "abs_path leaves an absolute path alone" {
  [ "$(abs_path /var/log/run.out)" = "/var/log/run.out" ]
}

@test "abs_path absolutises a relative path against the project root" {
  PROJECT_ROOT=/srv/demo
  [ "$(abs_path bin/.logs/run.out)" = "/srv/demo/bin/.logs/run.out" ]
}

# ============================================================================
# read_version -- the drift: a VERSION file in three projects, mix.exs in one
# ============================================================================

@test "read_version reads a VERSION file" {
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  printf '1.4.2\n' >"$PROJECT_ROOT/VERSION"
  [ "$(read_version)" = "1.4.2" ]
}

@test "read_version reads the version out of mix.exs" {
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  cat >"$PROJECT_ROOT/mix.exs" <<'EX'
defmodule Shop.MixProject do
  use Mix.Project
  def project do
    [
      app: :shop,
      version: "0.2.7",
      elixir: "~> 1.16"
    ]
  end
end
EX
  [ "$(read_version mix.exs)" = "0.2.7" ]
}

@test "read_version reads Cargo.toml and package.json" {
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  printf '[package]\nname = "demo"\nversion = "3.1.0"\n' >"$PROJECT_ROOT/Cargo.toml"
  printf '{\n  "name": "demo",\n  "version": "9.9.1"\n}\n' >"$PROJECT_ROOT/package.json"
  [ "$(read_version Cargo.toml)" = "3.1.0" ]
  [ "$(read_version package.json)" = "9.9.1" ]
}

@test "read_version honours DEVBIN_VERSION_FILE" {
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  printf '5.0.0\n' >"$PROJECT_ROOT/VERSION"
  printf 'version: "6.0.0"\n' >"$PROJECT_ROOT/mix.exs"
  DEVBIN_VERSION_FILE=mix.exs
  [ "$(read_version)" = "6.0.0" ]
}

@test "read_version says unknown rather than failing when there is no version" {
  PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  [ "$(read_version)" = "unknown" ]
  printf '\n' >"$PROJECT_ROOT/VERSION"
  [ "$(read_version)" = "unknown" ]
}

# ============================================================================
# assert_semver
# ============================================================================

@test "assert_semver accepts X.Y.Z" {
  assert_semver 0.1.0
  assert_semver 10.20.30
}

@test "assert_semver refuses anything else, quoting what it got" {
  run assert_semver v1.2.3
  assert_exit_code 1
  assert_output_contains "got 'v1.2.3'"
  run assert_semver 1.2
  assert_exit_code 1
  run assert_semver ""
  assert_exit_code 1
}

# ============================================================================
# semver_gt
# ============================================================================

@test "semver_gt compares part by part, as numbers, never as text" {
  semver_gt 1.10.0 1.9.0
  semver_gt 2.0.0 1.99.99
  semver_gt 1.0.1 1.0.0
  semver_gt 1.0.10 1.0.9
  semver_gt 1.08.0 1.7.0
  run semver_gt 1.9.0 1.10.0
  assert_exit_code 1
  run semver_gt 1.0.0 1.0.0
  assert_exit_code 1
  run semver_gt 0.9.9 1.0.0
  assert_exit_code 1
}

@test "semver_gt answers 2, not 1, when either side is not X.Y.Z" {
  run semver_gt v1.2.3 1.0.0
  assert_exit_code 2
  run semver_gt 1.0.0 1.2
  assert_exit_code 2
  run semver_gt "" 1.0.0
  assert_exit_code 2
}

# ============================================================================
# rlwrap_exec
# ============================================================================

@test "rlwrap_exec runs the command under rlwrap when it is available" {
  stub="$DEVBIN_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  printf '#!/usr/bin/env bash\nprintf "rlwrap-called: %%s\\n" "$*"\n' >"$stub/rlwrap"
  chmod +x "$stub/rlwrap"
  run env PATH="$stub:$PATH" bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    rlwrap_exec '' /tmp/hist -- iex -S mix"
  assert_success
  assert_output_contains "rlwrap-called:"
  assert_output_contains "-H /tmp/hist"
  assert_output_contains "iex -S mix"
}

@test "rlwrap_exec passes a completions file when one exists" {
  stub="$DEVBIN_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  printf '#!/usr/bin/env bash\nprintf "args: %%s\\n" "$*"\n' >"$stub/rlwrap"
  chmod +x "$stub/rlwrap"
  comp="$DEVBIN_TEST_TMPDIR/completions.txt"
  printf 'foo\nbar\n' >"$comp"
  run env PATH="$stub:$PATH" bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    rlwrap_exec '$comp' /tmp/hist -- repl"
  assert_success
  assert_output_contains "-f $comp"
}

@test "a missing rlwrap warns and still starts the command" {
  # Losing history is an inconvenience; refusing to start a REPL is an outage.
  #
  # bash and echo are addressed absolutely because PATH is emptied to hide
  # rlwrap, and env would otherwise fail to find the shell itself.
  bash_bin="$(command -v bash)"
  run env PATH=/nonexistent "$bash_bin" --noprofile --norc -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    rlwrap_exec '' /tmp/hist -- /bin/echo started 2>&1"
  assert_success
  assert_output_contains "rlwrap not found"
  assert_output_contains "started"
}

# ============================================================================
# SHARED OPTIONS -- the fold of _set_env / _set_bin / _set_fidelity
# ============================================================================

@test "a valued shared option is validated and exported" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - dev
      - test
      - prod
    export: MIX_ENV
YAML
  apply_shared_option env test
  [ "$MIX_ENV" = "test" ]
}

@test "a value outside the declared set is refused, listing what was expected" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - dev
      - test
      - prod
    export: MIX_ENV
YAML
  run apply_shared_option env staging
  assert_exit_code 1
  assert_output_contains "unknown --env 'staging'"
  assert_output_contains "dev test prod"
}

@test "an option declaring no values accepts anything" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  tag:
    export: DEMO_TAG
YAML
  apply_shared_option tag anything-at-all
  [ "$DEMO_TAG" = "anything-at-all" ]
}

@test "a flag exports true, or the value the config names" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  iex:
    flag: true
    export: DEMO_IEX
  json:
    flag: true
    value: json
    export: ACME_STYLE
YAML
  apply_shared_option iex ""
  apply_shared_option json ""
  [ "$DEMO_IEX" = "true" ]
  [ "$ACME_STYLE" = "json" ]
}

@test "a shared option with no export target is a config error, not a silent no-op" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - dev
YAML
  run apply_shared_option env dev
  assert_exit_code 1
  assert_output_contains "declares no 'export' target"
}

# ============================================================================
# parse_common_opts
# ============================================================================
#
# THE FIRST ARGUMENT IS THE COMMAND (issue 0009). A framework option is scoped
# to the commands that read it, and it is consumed here -- before the dispatcher
# reaches its own not-available-here checks -- so this function has to be told
# which command is running. `test` below is an arbitrary stand-in: every option
# these fixtures declare is config-declared, and config-declared options are the
# project's to scope, so none of them is refused whatever the command is.

setup_parse() {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - dev
      - test
    export: MIX_ENV
  iex:
    flag: true
    export: DEMO_IEX
YAML
}

@test "parse_common_opts accepts both --opt value and --opt=value" {
  setup_parse
  parse_common_opts test --env test
  [ "$MIX_ENV" = "test" ]
  parse_common_opts test --env=dev
  [ "$MIX_ENV" = "dev" ]
}

@test "parse_common_opts leaves everything it does not recognise in DEVBIN_ARGS" {
  setup_parse
  parse_common_opts test mix --env test --trace --seed 42
  # Exactly these words, each whole and in order: what parse_common_opts left.
  local -a want=(mix --trace --seed 42)
  [ "${DEVBIN_ARGS[*]@Q}" = "${want[*]@Q}" ] || fail "DEVBIN_ARGS is (${DEVBIN_ARGS[*]@Q}), not (${want[*]@Q})"
  [ "$MIX_ENV" = "test" ]
}

@test "parse_common_opts keeps argument boundaries" {
  setup_parse
  parse_common_opts test --only "a b" --env test
  # Exactly these words, "a b" one of them, not two.
  local -a want=(--only "a b")
  [ "${DEVBIN_ARGS[*]@Q}" = "${want[*]@Q}" ] || fail "DEVBIN_ARGS is (${DEVBIN_ARGS[*]@Q}), not (${want[*]@Q})"
}

@test "a flag consumes no following word" {
  setup_parse
  parse_common_opts test --iex mix
  [ "$DEMO_IEX" = "true" ]
  [ "${#DEVBIN_ARGS[@]}" -eq 1 ]
  [ "${DEVBIN_ARGS[0]}" = "mix" ]
}

@test "a valued option with nothing after it is refused" {
  setup_parse
  run parse_common_opts test mix --env
  assert_exit_code 1
  assert_output_contains "--env needs a value"
}

# ============================================================================
# THE BASH 3.2 EMPTY-ARRAY TRAP (a guard reversed by issue 0022 -- the
# guarded idiom stays in the corpus as harmless, and these tests document what
# it protected against)
# ============================================================================

@test "an emptied DEVBIN_ARGS expands to zero words under set -u" {
  # The whole point of the guarded expansion. On bash 3.2 -- /bin/bash on every
  # Mac -- "${a[@]}" on an EMPTY array under `set -u` aborts as an unbound
  # variable. Bash 4.4 fixed it; the >= 5 floor (issue 0022) makes the guard
  # optional, and the idiom stays until modernised.
  run bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    . '$DEVBIN_LIB_DIR/config'
    . '$DEVBIN_LIB_DIR/resolve'
    export DEVBIN_DIR='$DEVBIN_TEST_TMPDIR/.devbin'
    mkdir -p \"\$DEVBIN_DIR/cmd\"
    cfg_load_string <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - test
    export: MIX_ENV
YAML
    parse_common_opts test --env test
    set -- \"\${DEVBIN_ARGS[@]+\"\${DEVBIN_ARGS[@]}\"}\"
    printf 'count=%s\n' \"\$#\""
  assert_success
  assert_output_contains "count=0"
}

# ============================================================================
# ERREXIT REACHES EVERY DEPTH (issue 0060) AND THE FLOOR EVERY PROCESS (0076)
# ============================================================================

@test "a die two command substitutions deep stops the caller, because lib/helpers sets inherit_errexit" {
  # Depth 1 always propagated: the assignment's own status fails the frame. At
  # depth 2 the inner die killed only its subshell, the middle function carried
  # on, and the outer caller read its output as success.
  run bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    inner() { die 'inner refused'; }
    middle() { local x; x=\"\$(inner)\"; printf 'middle carried on\n'; }
    got=\"\$(middle)\"
    printf 'caller read: %s\n' \"\$got\""
  assert_failure
  assert_output_contains "inner refused"
  refute_output_contains "middle carried on"
  refute_output_contains "caller read:"
}

@test "lib/helpers refuses to load on a bash below the floor, so a handler run directly on 3.2 stops" {
  [ -x /bin/bash ] || skip "no /bin/bash on this platform"
  v="$(/bin/bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')"
  [ "$v" -lt 5 ] || skip "/bin/bash is major $v; no old bash to prove the refusal against"
  run /bin/bash -c ". '$DEVBIN_LIB_DIR/helpers'; printf 'loaded on %s\n' \"\$BASH_VERSION\""
  assert_failure
  assert_output_contains "bash >= 5"
  assert_output_contains "brew install bash"
  refute_output_contains "loaded on"
}

@test "the floor refusal names a bash >= 5 Homebrew has, with the PATH that finds it, and tells no one to install one (0253)" {
  # cron and a hook a GUI app launched run with the system's PATH, where
  # /bin/bash 3.2 answers though Homebrew's bash is installed. The refusal is
  # asked directly, so the arm runs wherever bash 5 does, and the test's own
  # Homebrew bin, the one place looked in while HOMEBREW_PREFIX is set, holds a
  # stand-in bash that answers 5.
  mkdir -p "$HOMEBREW_PREFIX/bin"
  printf '#!/bin/sh\nprintf 5\n' >"$HOMEBREW_PREFIX/bin/bash"
  chmod 0755 "$HOMEBREW_PREFIX/bin/bash"
  run bash -c '. "$1/helpers"; bash_floor_refuse 3.2.57 /bin/bash' _ "$DEVBIN_LIB_DIR"
  assert_exit_code 1
  assert_output_contains "a bash >= 5 is at $HOMEBREW_PREFIX/bin/bash -- put $HOMEBREW_PREFIX/bin ahead of /bin on PATH"
  refute_output_contains "brew install bash"
}

# Print /bin/bash's version as MAJORMINOR (eg 302, 503), or nothing if absent.
# Deliberately NOT $BASH_VERSINFO: that is whichever bash is running bats, which
# on a Mac is usually a Homebrew bash 5. The version that matters is the system
# one devbin actually gets invoked under.
system_bash_version() {
  [ -x /bin/bash ] || return 1
  /bin/bash -c 'printf "%s%02d\n" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"'
}

@test "the unguarded expansion is what actually breaks on the bash 3.2 target" {
  # HISTORICAL MEASUREMENT: proves what the guarded idiom protected against,
  # on the REAL /bin/bash rather than whichever bash runs this suite. The >= 5
  # floor (issue 0022) has since made the idiom optional; this stays as the
  # recorded reason it existed, and skips wherever no old bash remains.
  v="$(system_bash_version)" || skip "no /bin/bash to test the system shell"
  [ "$v" -lt 404 ] || skip "/bin/bash is $v; empty-array expansion is safe from 4.4"
  run /bin/bash -c 'set -euo pipefail; a=(); set -- "${a[@]}"; printf "survived\n"'
  assert_failure
  refute_output_contains "survived"
}

@test "the guarded expansion survives on the system bash whatever its version" {
  # The other half: the idiom devbin actually uses must work on 3.2 AND on 5.x.
  # This one never skips on version, so a regression cannot hide behind a skip.
  [ -x /bin/bash ] || skip "no /bin/bash on this platform"
  run /bin/bash -c 'set -euo pipefail
    a=()
    set -- "${a[@]+"${a[@]}"}"
    printf "count=%s\n" "$#"
    a=(one "two three")
    set -- "${a[@]+"${a[@]}"}"
    printf "count=%s second=%s\n" "$#" "$2"'
  assert_success
  assert_output_contains "count=0"
  assert_output_contains "count=2 second=two three"
}

# ============================================================================
# is_command
# ============================================================================

@test "is_command answers from what actually resolves" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  greet:
    summary: say hello
    run: echo hello
  publish:
    enabled: false
YAML
  is_command greet
  run is_command publish
  assert_failure
  run is_command never-heard-of-it
  assert_failure
}

# ============================================================================
# option_unavailable_reason (issue 0062)
# ============================================================================

@test "an option refused for its language names project.languages and the file it lives in" {
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  run option_unavailable_reason check autotests
  assert_success
  assert_output_contains "does not declare the 'rust' language in project.languages ("
  assert_output_contains "$DEVBIN_DIR/config.yaml)"
}

@test "option_unavailable_reason never asserts a language absence it did not test" {
  # The command-level twin has always asked project_speaks before speaking. This
  # one relied on option_active having already failed for exactly that reason:
  # true of today's order, and a false sentence the day the order changes.
  # Driven by forcing option_active to refuse an option whose language IS
  # declared, which is a state no config can reach -- so no dispatch test can.
  load_resolve
  cfg_load_string <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  option_active() { return 1; }
  run option_unavailable_reason check autotests
  assert_success
  refute_output_contains "does not declare"
  assert_output_contains "devbin defect"
}

# ============================================================================
# PORTABILITY: ONE SPELLING PER TOOL, ASSERTED ACROSS THE WHOLE TREE
#
# These are cross-file greps rather than behaviour tests, and deliberately so.
# The defect they pin (issue 0052) was invisible to every behaviour test devbin
# has, because it only shows on a platform the local suite never runs on: two
# call sites reached for a BSD-only spelling of a tool whose portable wrapper
# already existed a few lines away, and macOS agreed with both of them for five
# days while CI did not.
#
# A behaviour test cannot catch this without a Linux runner. A grep can, from
# anywhere, and it fails at the moment the second copy is WRITTEN rather than
# the moment somebody reads a CI log.
# ============================================================================

# THE SCAN IS ANCHORED TO $DEVBIN_HOME, AND THE CONTROL BELOW IS WHY.
#
# The first draft of these two greps ran on the relative paths `bin lib tests`.
# `devbin_setup` cd's into a fixture directory, so they searched three
# directories that do not exist there, matched nothing, and PASSED -- against a
# tree where both defects had been deliberately reintroduced to prove the guard
# could go red. It could not. A control that cannot fail is worse than no
# control, because it is reported as a pass.
#
# So each of these asserts its own population before asserting its finding.
# COMMENTS ARE NOT CODE, AND SCANNING THEM MAKES DOCUMENTING THE DEFECT AN
# OFFENCE. `lib/install` and `lib/runlog` both DESCRIBE the shasum spelling in
# prose -- correctly, and one of them is the note explaining why the wrapper
# exists. The first draft of this guard failed on both. That is the same rule
# every header guard here carries: read what the code does, never what it says
# about itself.
scan_tree() {
  grep -rnE "$1" "$DEVBIN_HOME/bin" "$DEVBIN_HOME/lib" "$DEVBIN_HOME/tests" 2>/dev/null |
    sed "s|^$DEVBIN_HOME/||" |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}

@test "nothing outside lib/helpers reaches for a raw sha256 binary" {
  # NON-VACUITY FIRST: the scan must see the tree at all. `sha256_files` lives
  # in lib/helpers and always matches, so zero hits means the scan is broken,
  # not that the tree is clean.
  local seen
  seen="$(scan_tree '(^|[^_[:alnum:]])(shasum|sha256sum)[[:space:]]' | grep -c . || true)"
  [ "$seen" -gt 0 ] || fail "the scan found NOTHING at all -- it is not reading the tree"

  local hits
  hits="$(scan_tree '(^|[^_[:alnum:]])(shasum|sha256sum)[[:space:]]' |
    grep -v '^lib/helpers:' |
    grep -v '^tests/unit/helpers.bats:' || true)"
  [ -z "$hits" ] || fail "raw sha256 tool outside lib/helpers -- use sha256_files or sha256_stdin:
$hits"
}

@test "nothing reaches for the BSD-only date epoch form outside utc_from_epoch" {
  local seen
  seen="$(scan_tree 'date[[:space:]]+(-u[[:space:]]+)?-r[[:space:]]' | grep -c . || true)"
  [ "$seen" -gt 0 ] || fail "the scan found NOTHING at all -- it is not reading the tree"

  local hits
  hits="$(scan_tree 'date[[:space:]]+(-u[[:space:]]+)?-r[[:space:]]' |
    grep -v '^lib/helpers:' |
    grep -v '^tests/unit/helpers.bats:' || true)"
  [ -z "$hits" ] || fail "bare 'date -r' is BSD-only -- use utc_from_epoch:
$hits"
}

@test "the runtime's mv lines are exactly the known mv -f lines, so no replace can stop on a terminal prompt or quietly not replace" {
  # `bin/devbin test all` from a terminal printed its last `ok` line and then
  # nothing for 8h13m. The read-only replace_file arm below had reached
  # rename_staged, which called `mv` with no -f. POSIX mv PROMPTS when the
  # destination exists, permissions do not allow writing it, and stdin is a tty.
  #
  # WHICH FORMS ARE SAFE WAS DRIVEN, NOT READ (0086): each under a
  # real pty from python3's pty.fork, over a read-only destination, 2s budget,
  # against BSD /bin/mv and GNU coreutils 9.12 -- CI's Ubuntu job runs GNU.
  #
  #   form                  BSD mv             GNU mv
  #   mv a b                blocks             blocks
  #   mv -fi a b            blocks             blocks
  #   mv -f -i a b          blocks             blocks
  #   mv -f a b -i          rc 1, loud         blocks (GNU permutes argv)
  #   mv -f --interactive   rc 64, loud        blocks
  #   mv -fn a b            rc 0, NOT replaced rc 0, NOT replaced
  #   mv -f a b -n          rc 1, loud         rc 0, NOT replaced
  #   mv -f --no-clobber    rc 64, loud        rc 0, NOT replaced
  #   mv -f a b, -f -- a b  replaces           replaces
  #
  # WHY AN ALLOWLIST AND NOT A RULE ABOUT FLAGS. Two lexical rules in a row
  # were beaten by spellings they did not read: a second mv on the same line
  # after `;` or `&&`, an -i on a continuation line, a quoted '-n' that the
  # shell turns into -n. Each round closed the forms found and left the next.
  # So the claim is now about lines, not flags: the runtime has exactly these
  # mv lines, byte for byte, and any other line naming mv in lib/ or bin/ --
  # a new call, an edited one, a second command beside one -- is a finding by
  # construction. Adding an mv means adding its line here, with this table in
  # view. A known line that disappears fails too, so the list cannot rot.
  #
  # WHY MORE THAN ONE. lib/install's rename could go through rename_staged
  # only by staging with mktemp, and a mktemp file is 0600: `cp` into it keeps
  # that mode (measured), so every vendored file would land 0600.
  # And keep_case_twin's mv lines (issue 0140) MOVE the one copy of a file devbin
  # renamed only in case, where rename_staged removes what it was renaming when
  # the rename fails: the case rename in one step, then the two steps through a
  # mktemp name, the put-back beside the second on its line. And
  # lib/release.legs's rename of a leg's exit status, inside the `bash -c` that
  # runs a project's gates detached on a test host (ST0011 WP-05), renames the
  # status it just wrote, beside the run, so a reader never takes a half of it.
  #
  # WHAT THIS ARM CANNOT SEE: an mv behind a variable, an alias or a function
  # of another name; an mv spelled so its text does not read mv, "m""v" or
  # m\v (both measured live); a prompt reached by a DIFFERENT command; and any
  # tty-gated block outside these lines (issue 0088 censuses the rest). The
  # behavioural arm belongs on test_helper's run_tty_eof, where bare mv exits 0
  # WITHOUT replacing and mv -f replaces (0088).
  #
  # TESTS ARE EXCLUDED DELIBERATELY AND THE EXCLUSION IS NOT FREE. The bare mv
  # calls under tests/ each move a file the test just made and can write, so
  # none can prompt today. A test that moves over a read-only
  # fixture would hang the suite the same way and this arm would not see it.
  local known
  # The lines are compared as TEXT, so their `$1` and `$tmp` stay unexpanded;
  # release.legs's line holds single quotes, each closed, given as "'", and
  # reopened.
  # shellcheck disable=SC2016
  known="$(printf '%s\t%s\n' \
    lib/cmd/cache '  mv -f -- "$CACHE_TMP" "$entry" || refuse "the entry for $art $key could not be renamed into place under the cache root $root (above)"' \
    lib/helpers '  if ! mv -f "$1" "$file"; then' \
    lib/install '  mv -f "$tmp" "$dst" || {' \
    lib/install '  mv -f -- "$root/$rel" "$root/$to" 2>/dev/null || :' \
    lib/install '    if mv -f -- "$root/$rel" "$tmp"; then' \
    lib/install '      mv -f -- "$tmp" "$root/$to" || mv -f -- "$tmp" "$root/$rel" || warn "could not put $rel back: it is at $tmp"' \
    lib/release.legs '  set -- bash -c '"'"'bin/devbin release gates; printf "%s\n" "$?" >"$1.rc.part" && mv -f "$1.rc.part" "$1.rc"'"'"' release-leg "$wt"')"

  local found
  found="$(scan_tree '(^|[^_[:alnum:]])mv([[:space:]]|$)' |
    grep -E '^(lib|bin)/' |
    sed -E 's/^([^:]+):[0-9]+:/\1\t/' | LC_ALL=C sort)"
  [ -n "$found" ] || fail "the scan found NO mv at all in lib/ or bin/ -- it is not reading the tree"

  local extra missing
  extra="$(LC_ALL=C comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$known" | LC_ALL=C sort))"
  missing="$(LC_ALL=C comm -13 <(printf '%s\n' "$found") <(printf '%s\n' "$known" | LC_ALL=C sort))"
  [ -z "$extra" ] || fail "a line in the runtime names mv and is not one of the known mv -f lines -- it can block on a terminal prompt, or exit 0 without replacing, and nothing else here reads it:
$extra"
  [ -z "$missing" ] || fail "a known mv -f line is gone -- if the rename moved, move its line in this arm's list:
$missing"
}

@test "sha256_stdin agrees with the published vector for 'abc'" {
  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; printf abc | sha256_stdin"
  [ "$status" -eq 0 ]
  assert_output "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

@test "utc_from_epoch renders a known epoch, and REFUSES rather than guessing" {
  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; utc_from_epoch 1756000000"
  [ "$status" -eq 0 ]
  assert_output "2025-08-24 01:46Z"

  # The refusal half is the load-bearing one. A converter that emitted the
  # epoch, or today's date, or an empty string with rc=0 would put a
  # plausible-looking timestamp into a document whose whole subject is
  # provenance -- and nothing downstream could tell it from a real reading.
  for bad in "" "notanumber" "1756000000x"; do
    run bash -c ". '$DEVBIN_LIB_DIR/helpers'; utc_from_epoch '$bad'"
    [ "$status" -ne 0 ] || fail "utc_from_epoch accepted '$bad' and returned: $output"
  done
}

# ============================================================================
# THE TRUE AND FALSE WORDS, AND THE `-` SENTINEL (issue 0066)
# ============================================================================
#
# Small vocabularies (the true words, the false words, the `-` sentinel)
# were written out at many sites. Every copy
# agreed, and nothing would have said so on the day one learned a word the
# others did not -- 0065 was exactly that, for `-` on `log:`. One predicate per
# vocabulary, here, because lib/helpers needs no config and every handler loads it.

@test "0066: is_true_word, is_false_word and is_no_default each take their words and nothing else" {
  local w
  for w in true yes 1; do is_true_word "$w" || fail "'$w' is not a true word"; done
  for w in false no 0; do is_false_word "$w" || fail "'$w' is not a false word"; done
  is_no_default - || fail "'-' is not the no-default sentinel"
  # Near misses. `! cmd` never trips errexit, so each is asserted.
  for w in "" True YES on off enabled 2 "true " -; do
    if is_true_word "$w"; then fail "'$w' was read as true"; fi
  done
  for w in "" False NO off disabled -1 "no " -; do
    if is_false_word "$w"; then fail "'$w' was read as false"; fi
  done
  for w in "" -- "- " none false; do
    if is_no_default "$w"; then fail "'$w' was read as the no-default sentinel"; fi
  done
}

@test "0066: the predicates answer the same under a strict-mode IFS, or an empty one" {
  # The word lists are split inside the predicates, and a split reads IFS. A
  # caller's `IFS=$'\n\t'` made true, yes, 1 and no all read as not-a-word.
  local w ifs
  for ifs in $'\n\t' ''; do
    for w in true yes 1; do
      IFS="$ifs" is_true_word "$w" || fail "'$w' is not a true word under IFS=$(printf '%q' "$ifs")"
    done
    for w in false no 0; do
      IFS="$ifs" is_false_word "$w" || fail "'$w' is not a false word under IFS=$(printf '%q' "$ifs")"
    done
    IFS="$ifs" is_no_default - || fail "'-' is not the sentinel under IFS=$(printf '%q' "$ifs")"
    if IFS="$ifs" is_true_word "true yes"; then fail "a whole list was read as one true word under IFS=$(printf '%q' "$ifs")"; fi
  done
}

@test "0066: every statement of the log: decline spellings names exactly - and the false words" {
  # The documents that state the list are each held to the predicates' DATA --
  # not to the function's source, whose layout a second `return 0` line or an
  # `OFF)` arm slipped past.
  local want doc ref line w
  load_resolve
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  want="$(printf '%s\n' "$_DEVBIN_NO_DEFAULT" $_DEVBIN_FALSE_WORDS | sort | tr '\n' ' ')"

  # docs/configuration.md: the one sentence, not the paragraph, which names
  # `log:` itself too.
  line="$(sed -n 's/.*decline explicitly with \([^.]*\)\..*/\1/p' "$DEVBIN_HOME/docs/configuration.md")"
  [ -n "$line" ] || fail "docs/configuration.md no longer states the decline spellings"
  doc="$(printf '%s\n' "$line" | grep -o '`[^`]*`' | tr -d '`' | sed 's/^log: "\(.*\)"$/\1/' | sort | tr '\n' ' ')"
  [ "$doc" = "$want" ] || fail "docs/configuration.md declines on '$doc' but the predicates on '$want'"

  # lib/config.reference.yaml: a comment block, so joined before it is read.
  ref="$(awk '/DECLINING A SEAL/,/issue 0065/' "$DEVBIN_LIB_DIR/config.reference.yaml" |
    sed 's/^[[:space:]]*#[[:space:]]*//' | tr '\n' ' ' |
    sed -n 's/.*\(`log: "-"`.*\) declines explicitly.*/\1/p')"
  [ -n "$ref" ] || fail "lib/config.reference.yaml no longer states the decline spellings"
  ref="$(printf '%s\n' "$ref" | grep -o '`[^`]*`' | tr -d '`' | sed 's/^log: "\(.*\)"$/\1/' | sort | tr '\n' ' ')"
  [ "$ref" = "$want" ] || fail "config.reference.yaml declines on '$ref' but the predicates on '$want'"

  # Each word declines a seal through the one resolver.
  for w in $want; do
    [ -z "$(gate_log_suffix opt "$w")" ] || fail "the documented spelling '$w' does not decline a seal"
  done
}

# The vocabulary patterns, shared by the structural arm and its positive control
# so the control tests the pattern the arm uses. Any layout of two words from the
# lists joined by `|`, quoted or not; a `-` compared by `=`, `==` or `!=`; and a
# `-` as a case alternative.
vocab_patterns() {
  printf '%s\n' \
    '(^|[^[:alnum:]_.-])["'"'"']?(true|yes|false|no|1|0)["'"'"']? *\| *["'"'"']?(true|yes|false|no|1|0)["'"'"']?([^[:alnum:]_.-]|$)' \
    '[!=]=? *["'"'"']?-["'"'"']? *(\]|;|$)' \
    '(^|\|) *["'"'"']?-["'"'"']? *(\)|\|)'
}

vocab_grep() {
  local -a args=()
  local p
  while IFS= read -r p; do args+=(-e "$p"); done <<EOF
$(vocab_patterns)
EOF
  grep -rnE "${args[@]}" "$@"
}

@test "0066: the vocabulary pattern catches every layout it claims, and not a flag or a comparison" {
  local fx="$DEVBIN_TEST_TMPDIR/vocab" line
  mkdir -p "$fx"
  while IFS= read -r line; do
    printf '%s\n' "$line" >"$fx/hit"
    run vocab_grep "$fx/hit"
    [ "$status" -eq 0 ] || fail "the pattern misses: $line"
  done <<'EOF'
    false | no | 0) return 1 ;;
    false|no|0) return 1 ;;
    no | false | 0) ;;
    true | 1 | yes) ;;
    "false" | "no" | "0") ;;
    'yes'|'true') ;;
  [ "$g" = - ] && g=""
  [ "$g" = "-" ] && g=""
  [ "$g" = '-' ] && g=""
  [ "${g}" != "-" ]
  [[ $g == - ]]
  test "$g" = "-"; then
    - | @builtin) run="" ;;
    @builtin | -) run="" ;;
    -) run="" ;;
    "-") run="" ;;
EOF
  while IFS= read -r line; do
    printf '%s\n' "$line" >"$fx/miss"
    run vocab_grep "$fx/miss"
    [ "$status" -eq 1 ] || fail "the pattern hits an innocent line (status $status): $line"
  done <<'EOF'
    -h | --help) usage ;;
    --from) from="$2" ;;
    -*) die "unknown option" ;;
  [ "$n" -ge 1 ] || return 1
  [ "$a" = "--" ] && shift
  printf '%s | %s\n' "$a" "$b"
EOF
}

@test "0066: no file outside lib/helpers spells the word lists or the - sentinel test" {
  # Known limit, declared: a single-word comparison (`= true`, `!= no`) is not
  # searched for, because internal variables legitimately compare to `yes`.
  local root hits
  for root in "$DEVBIN_HOME/lib" "$DEVBIN_HOME/bin/devbin" "$DEVBIN_HOME/bin/.devbin/cmd"; do
    [ -e "$root" ] || fail "a search root is missing, so the search proves nothing: $root"
  done
  run vocab_grep "$DEVBIN_HOME/lib" "$DEVBIN_HOME/bin/devbin" "$DEVBIN_HOME/bin/.devbin/cmd"
  # 0 is hits and 1 is none; anything else is grep failing, never a clean tree.
  [ "$status" -le 1 ] || fail "grep failed (status $status): $output"
  hits="$(printf '%s\n' "$output" | awk -v h="$DEVBIN_HOME/lib/helpers:" '
    NF == 0 { next }
    index($0, h) == 1 { next }
    { l = $0; sub(/^[^:]+:[0-9]+:/, "", l); if (l !~ /^[[:space:]]*#/) print }')"
  [ -z "$hits" ] || fail "the vocabulary is spelled outside lib/helpers:
$hits"
}

# ---- stage_beside and replace_file: the one "replace a file through a temporary" -
#
# Every writer that renamed a temporary into place made it with mktemp, which
# creates 0600, and the rename carried that mode onto the file. The arms below
# use 604, a mode that is neither 0600 nor what any umask gives a new file, so
# neither the old behaviour nor a writer that fell back to the umask can pass.

@test "stage_beside writes the command's output into a temporary beside the file, with the file's mode, and leaves the file alone" {
  local f="$DEVBIN_TEST_TMPDIR/target.txt" tmp
  printf 'one\n' >"$f"
  chmod 604 "$f"
  tmp="$(stage_beside "$f" printf 'two\n')"
  [ "${tmp%/*}" = "$DEVBIN_TEST_TMPDIR" ] || fail "the temporary is not beside the file: $tmp"
  [ "$(cat "$tmp")" = "two" ] || fail "the temporary does not hold the command's output: $(cat "$tmp")"
  [ "$(mode_of "$tmp")" = "-rw----r--" ] || fail "the temporary's mode: $(mode_of "$tmp")"
  [ "$(cat "$f")" = "one" ] || fail "staging touched the file itself"
  rm -f "$tmp"
}

@test "stage_beside gives a file that does not exist yet the mode the umask gives a new file, under any umask" {
  # Three umasks, because under any one of them several bases give the same
  # answer: 027 cannot tell 0666 from 0644, which is how a new file's mode
  # computed from the wrong base stayed green (ST0007 WP-02).
  local row mask want tmp
  for row in "027 -rw-r-----" "002 -rw-rw-r--" "000 -rw-rw-rw-"; do
    mask="${row%% *}"
    want="${row#* }"
    tmp="$(umask "$mask" && stage_beside "$DEVBIN_TEST_TMPDIR/new.txt" printf 'x\n')"
    [ "$(mode_of "$tmp")" = "$want" ] || fail "under umask $mask the temporary is $(mode_of "$tmp"), want $want"
    rm -f "$tmp"
  done
}

@test "replace_file replaces a read-only file, and it stays read-only" {
  # Red at both ends of WP-02 (ST0007 WP-02): before it, the rename
  # left the file 0600; with the mode copied onto the temporary before the
  # write, the write into a 0444 temporary was refused, Permission denied.
  local f="$DEVBIN_TEST_TMPDIR/locked.txt"
  printf 'old\n' >"$f"
  chmod 444 "$f"
  run replace_file "$f" printf 'new\n'
  assert_success
  [ "$(cat "$f")" = "new" ] || fail "the read-only file was not replaced: $(cat "$f")"
  [ "$(mode_of "$f")" = "-r--r--r--" ] || fail "the read-only file came out $(mode_of "$f")"
  run find "$DEVBIN_TEST_TMPDIR" -maxdepth 1 -name 'locked.txt.*'
  assert_success
  assert_output ""
}

@test "replace_file replaces a read-only file with a TERMINAL for stdin, so mv cannot stop on its prompt (0086)" {
  # The arm above runs with no tty, which is exactly why it passed while a
  # terminal run of the same code sat for 8h13m: POSIX mv prompts only when
  # stdin is a terminal. run_tty_eof gives the child a fresh pty already at EOF,
  # so a prompting mv reads "no" at once instead of waiting -- measured
  # (0088): bare mv then exits 0 WITHOUT replacing and prints "not overwritten",
  # and mv -f replaces. So the content check below is the assertion that
  # carries the issue; the exit status alone would pass the defect.
  require_pty
  local f="$DEVBIN_TEST_TMPDIR/tty-locked.txt"
  printf 'old\n' >"$f"
  chmod 444 "$f"
  run run_tty_eof bash -c '. "$1"; replace_file "$2" printf "new\n"' _ "$DEVBIN_LIB_DIR/helpers" "$f"
  assert_success
  [ "$(cat "$f")" = "new" ] || fail "from a terminal the read-only file was not replaced: $(cat "$f")
$output"
  refute_output_contains "overwrite"
}

@test "replace_file leaves the file as it was, and no temporary behind, when the command fails" {
  local f="$DEVBIN_TEST_TMPDIR/keep.txt" sum
  printf 'keep\n' >"$f"
  chmod 604 "$f"
  sum="$(sha256_of "$f")"
  failing() { printf 'half a document\n'; return 1; }
  run replace_file "$f" failing
  assert_failure
  [ "$(sha256_of "$f")" = "$sum" ] || fail "a failed replace changed the file"
  [ "$(mode_of "$f")" = "-rw----r--" ] || fail "a failed replace changed the mode: $(mode_of "$f")"
  run find "$DEVBIN_TEST_TMPDIR" -maxdepth 1 -name 'keep.txt.*'
  assert_success
  assert_output ""
}

@test "sed_inplace edits a read-only file, and it stays read-only" {
  # The writer every version of lib/helpers has, so this arm runs at both ends of
  # the defect: before ST0007 WP-02 the edit left the file 0600, and at WP-02's
  # first cut it was refused, Permission denied on the temporary.
  local f="$DEVBIN_TEST_TMPDIR/pinned.toml"
  printf 'version = "1.0.0"\n' >"$f"
  chmod 444 "$f"
  run sed_inplace 's/1\.0\.0/1.0.1/' "$f"
  assert_success
  grep -qx 'version = "1.0.1"' "$f" || fail "the read-only file was not edited: $(cat "$f")"
  [ "$(mode_of "$f")" = "-r--r--r--" ] || fail "the read-only file came out $(mode_of "$f")"
}

@test "sed_inplace keeps the file's mode" {
  local f="$DEVBIN_TEST_TMPDIR/Cargo.toml"
  printf 'version = "1.0.0"\n' >"$f"
  chmod 604 "$f"
  sed_inplace 's/1\.0\.0/1.0.1/' "$f"
  grep -qx 'version = "1.0.1"' "$f" || fail "the edit did not land, so the mode below measures nothing"
  [ "$(mode_of "$f")" = "-rw----r--" ] || fail "sed_inplace left the file $(mode_of "$f")"
}

# ---- writing through a symbolic link (issue 0084, shape A) --------------------
#
# A path that is a link names the file at its end, and a writer replaces THAT
# file: staged beside it and renamed over it, so the link survives and the
# rename stays on the target's filesystem. Before this, the temporary was renamed
# over the link's own path, so the link became a regular file holding the edit,
# the file it named kept its old content, and the writer exited 0.

@test "replace_file writes through a link: the link survives, and the file it names is renamed over with its mode" {
  local d="$DEVBIN_TEST_TMPDIR" inode
  mkdir -p "$d/shared"
  printf 'old\n' >"$d/shared/doc.md"
  chmod 604 "$d/shared/doc.md"
  inode="$(inode_of "$d/shared/doc.md")"
  ln -s shared/doc.md "$d/doc.md"
  run replace_file "$d/doc.md" printf 'new\n'
  assert_success
  assert_symlink_exists "$d/doc.md" shared/doc.md
  [ "$(cat "$d/shared/doc.md")" = "new" ] || fail "the file the link names was not replaced: $(cat "$d/shared/doc.md")"
  [ "$(mode_of "$d/shared/doc.md")" = "-rw----r--" ] || fail "the file the link names came out $(mode_of "$d/shared/doc.md")"
  [ "$(inode_of "$d/shared/doc.md")" != "$inode" ] || fail "the file the link names was written in place, not renamed over"
  run find "$d" -name 'doc.md.*'
  assert_success
  assert_output ""
}

@test "stage_beside stages beside the file a link names, not beside the link" {
  local d="$DEVBIN_TEST_TMPDIR" tmp
  mkdir -p "$d/shared"
  printf 'one\n' >"$d/shared/doc.md"
  chmod 640 "$d/shared/doc.md"
  ln -s shared/doc.md "$d/doc.md"
  tmp="$(stage_beside "$d/doc.md" printf 'two\n')"
  [ "${tmp%/*}" = "$d/shared" ] || fail "the temporary is not beside the file the link names: $tmp"
  [ "$(mode_of "$tmp")" = "-rw-r-----" ] || fail "the temporary's mode is $(mode_of "$tmp"), not the linked file's"
  [ "$(cat "$d/shared/doc.md")" = "one" ] || fail "staging touched the file the link names"
  assert_symlink_exists "$d/doc.md" shared/doc.md
  rm -f "$tmp"
}

@test "a chain of links is followed to its end, each relative target read from its own link's directory" {
  # first -> alias/l, alias -> real/a/b, and real/a/b/l -> ../t. The kernel takes
  # alias/l's `..` after following alias, so the chain names real/a/t; a walk
  # that tidied alias/../t into t would name a file in the wrong directory.
  local d="$DEVBIN_TEST_TMPDIR"
  mkdir -p "$d/real/a/b"
  printf 'old\n' >"$d/real/a/t"
  ln -s ../t "$d/real/a/b/l"
  ln -s real/a/b "$d/alias"
  ln -s alias/l "$d/first"
  run replace_file "$d/first" printf 'new\n'
  assert_success
  assert_symlink_exists "$d/first" alias/l
  assert_symlink_exists "$d/real/a/b/l" ../t
  [ "$(cat "$d/real/a/t")" = "new" ] || fail "the file at the end of the chain was not replaced: $(cat "$d/real/a/t")"
  [ ! -e "$d/t" ] || fail "a file was written at $d/t, outside the chain"
}

@test "a link that leads to no file, dangling or in a loop, is refused naming it, and nothing is written" {
  local d="$DEVBIN_TEST_TMPDIR" link
  ln -s shared/missing.md "$d/dangling.md"
  ln -s loop-b "$d/loop-a"
  ln -s loop-a "$d/loop-b"
  for link in dangling.md loop-a; do
    run replace_file "$d/$link" printf 'new\n'
    assert_failure
    assert_output_contains "$d/$link is a symbolic link that leads to no file"
    [ -L "$d/$link" ] || fail "$link is no longer a link"
  done
  [ ! -e "$d/shared" ] || fail "writing through the dangling link created $d/shared"
  run find "$d" -mindepth 1 -name '*.??????'
  assert_success
  assert_output ""
}

@test "a link whose target cannot be read back exactly is refused, and the file its reading names is not written" {
  # MEASURED: plain readlink prints a target whose name ends in a
  # newline with one newline fewer on BSD than on GNU, and a command substitution
  # strips what is left, so the walk reads `doc` where the link names `doc` and a
  # newline. Here a file named `doc` exists too, and replacing it would report
  # success having written the wrong file.
  local d="$DEVBIN_TEST_TMPDIR"
  printf 'target\n' >"$d/doc"$'\n'
  printf 'decoy\n' >"$d/doc"
  ln -s "doc"$'\n' "$d/link"
  run replace_file "$d/link" printf 'new\n'
  assert_failure
  assert_output_contains "cannot tell which file $d/link is a symbolic link to"
  [ "$(cat "$d/doc")" = "decoy" ] || fail "the file the walk read, not the one the link names, was written: $(cat "$d/doc")"
  [ "$(cat "$d/doc"$'\n')" = "target" ] || fail "the file the link names was written despite the refusal"
  [ -L "$d/link" ] || fail "the link is no longer a link"
}

@test "a walk that a misread target turns into a loop is refused, not followed forever" {
  # link -> `x` and a newline, a regular file, so the link names a file; but the
  # walk reads `x` (see the arm above), and x -> link. Only a bound on the walk
  # returns. Run in the background under a watchdog, so a walk with no bound
  # fails this arm rather than hanging the suite.
  local d="$DEVBIN_TEST_TMPDIR" pid i
  printf 'target\n' >"$d/x"$'\n'
  ln -s "x"$'\n' "$d/link"
  ln -s link "$d/x"
  (
    rc=0
    replace_file "$d/link" printf 'new\n' >"$d/out" 2>&1 || rc=$?
    printf '%s\n' "$rc" >"$d/rc"
  ) 3>&- &
  pid=$!
  for i in $(seq 1 100); do
    [ -s "$d/rc" ] && break
    sleep 0.1
  done
  if [ ! -s "$d/rc" ]; then
    kill "$pid" 2>/dev/null
    fail "replace_file had not returned after 10s: the walk has no bound"
  fi
  [ "$(cat "$d/rc")" = 1 ] || fail "replace_file returned $(cat "$d/rc"), output: $(cat "$d/out")"
  grep -qF "cannot tell which file $d/link is a symbolic link to" "$d/out" || fail "the refusal: $(cat "$d/out")"
  [ "$(cat "$d/x"$'\n')" = "target" ] || fail "the file the link names was written"
}

@test "a write through the longest chain of links the kernel follows succeeds, so the walk's bound is not below the platform's" {
  # THE OTHER HALF OF THE BOUND. The arm above holds that the walk stops; this one
  # holds that it does not stop early. No other arm walks a long chain of links, so
  # a bound of 2 passed every file holding link arms and a bound of 31 passed
  # this one, and either refuses a chain the kernel follows. So the
  # chain is measured here, not assumed: l0 names the file, each l<k> names
  # l<k-1>, and the first l<n> that leads to no file puts the platform's limit at
  # n links -- 32 on macOS, and on Linux whatever its kernel follows.
  local d="$DEVBIN_TEST_TMPDIR" n=0
  printf 'old\n' >"$d/file"
  ln -s file "$d/l0"
  while [ -e "$d/l$n" ] && [ "$n" -le 100 ]; do
    n=$((n + 1))
    ln -s "l$((n - 1))" "$d/l$n"
  done
  [ ! -e "$d/l$n" ] || fail "the kernel followed more than 100 links, so this arm did not find its limit"
  [ "$n" -ge 8 ] || fail "the kernel followed only $n links, so this chain measured nothing"
  run replace_file "$d/l$((n - 1))" printf 'new\n'
  assert_success
  [ "$(cat "$d/file")" = "new" ] || fail "the file at the end of a chain of $n links was not replaced: $(cat "$d/file")"
  assert_symlink_exists "$d/l$((n - 1))" "l$((n - 2))"
}

@test "a file whose own name ends in a newline is the one replaced, and not the file named without it" {
  # Not a link at all. stage_beside now captures the path follow_links prints,
  # and a bare capture strips a trailing newline, so the temporary would be
  # staged for, and renamed over, `doc`. Green before issue 0084: this holds the
  # capture that the issue added.
  local d="$DEVBIN_TEST_TMPDIR"
  printf 'old\n' >"$d/doc"$'\n'
  printf 'decoy\n' >"$d/doc"
  run replace_file "$d/doc"$'\n' printf 'new\n'
  assert_success
  [ "$(cat "$d/doc"$'\n')" = "new" ] || fail "the file named with the newline was not replaced: $(cat "$d/doc"$'\n')"
  [ "$(cat "$d/doc")" = "decoy" ] || fail "the file named without the newline was written: $(cat "$d/doc")"
}

# ============================================================================
# ONE READING OF A COMMAND LINE -- run_words (issue 0082)
# ============================================================================
#
# `run:` was expanded unquoted at five sites and the catalogue's own command
# lines at two more, so how a declared command line becomes words was stated
# seven times. Each one split on the CALLER'S IFS and globbed under the caller's
# options, and a value of nothing but spaces split into no words at all, after
# which `$run "$@"` ran the arguments typed after the command AS the command, at
# exit 0. The globbing is kept and documented, and one helper holds the rule.

@test "run_words splits a command line on spaces, tabs and newlines, whatever the caller's IFS (0082)" {
  local -a words
  local value=$'  mix\ttest \n --only  fast  ' ifs got
  for ifs in $' \t\n' '' $'\n\t' ':'; do
    words=(stale)
    IFS="$ifs" run_words words commands.x.run "$value" ||
      fail "a line with four words was refused under IFS $(printf '%q' "$ifs")"
    got="$(printf '<%s>' "${words[@]}")"
    [ "$got" = '<mix><test><--only><fast>' ] ||
      fail "under IFS $(printf '%q' "$ifs") the words are $got"
  done
}

@test "every run_words word is a glob pattern matched where the caller stands, and a word that matches nothing is passed as written (0082)" {
  local -a words
  local got d="$DEVBIN_TEST_TMPDIR/globs"
  mkdir -p "$d/sub"
  : >"$d/alpha.md"
  : >"$d/beta.md"
  : >"$d/gamma.txt"
  : >"$d/sub/delta.md"
  cd "$d"
  run_words words commands.x.run 'printf [%s] *.md ?amma.txt [ab]eta.md sub/*.md *.nomatch'
  got="$(printf '<%s>' "${words[@]}")"
  [ "$got" = '<printf><[%s]><alpha.md><beta.md><gamma.txt><beta.md><sub/delta.md><*.nomatch>' ] ||
    fail "in $d the words are $got"
  # The SAME line one directory down matches what is there, which is what makes
  # the site's `cd` the thing that decides: Utilz's `bats opt/*/test` is read at
  # the project root, and a notes.run line at the root it answers for.
  cd "$d/sub"
  run_words words commands.x.run 'printf *.md'
  got="$(printf '<%s>' "${words[@]}")"
  [ "$got" = '<printf><delta.md>' ] || fail "in $d/sub the words are $got"
}

@test "run_words never evaluates: quotes, dollars, semicolons and redirections stay literal words (0082)" {
  local -a words
  local got
  cd "$DEVBIN_TEST_TMPDIR"
  run_words words commands.x.run 'echo "a b" $(touch pwned) ; >out $HOME'
  got="$(printf '<%s>' "${words[@]}")"
  [ "$got" = '<echo><"a><b"><$(touch><pwned)><;><>out><$HOME>' ] || fail "the words are $got"
  [ ! -e pwned ] || fail "a command substitution in the line was run"
  [ ! -e out ] || fail "a redirection in the line was performed"
}

@test "run_words refuses a line with no words, naming the key, and leaves no words behind (0082)" {
  local -a words
  local value
  cd "$DEVBIN_TEST_TMPDIR"
  for value in '' ' ' '   ' $'\t' $'\n' $'\t \n  '; do
    words=(stale)
    if run_words words commands.demo.options.blank.run "$value" 2>err; then
      fail "a line of $(printf '%q' "$value") was accepted as a command"
    fi
    [ "${#words[@]}" -eq 0 ] ||
      fail "words left behind for $(printf '%q' "$value"): $(printf '<%s>' "${words[@]}")"
    grep -q 'commands\.demo\.options\.blank\.run' err ||
      fail "the refusal of $(printf '%q' "$value") does not name the key: $(cat err)"
  done
}

@test "has_words answers exactly what run_words splits, for characters that are not IFS whitespace too (0082)" {
  # The two are one statement of "this line holds a command": has_words is what
  # cfg_validate asks, since validation may not glob, and run_words is what the
  # sites ask. A predicate reading [[:space:]] instead would part company with
  # the split at a carriage return, which bash does not split on.
  local -a words ref
  local value has split reference
  cd "$DEVBIN_TEST_TMPDIR"
  for value in '' ' ' $'\t' $'\n' $' \t\n' $'\r' $'\v' $'\f' 'x' ' x ' $'\n\nx' 'a b'; do
    has=no
    has_words "$value" && has=yes
    split=no
    run_words words commands.x.run "$value" 2>/dev/null && split=yes
    # The reference is bash's own split, spelled out here rather than asked of
    # the code under test.
    set -f
    IFS=$' \t\n' ref=($value)
    set +f
    reference=no
    [ "${#ref[@]}" -gt 0 ] && reference=yes
    [ "$has" = "$reference" ] ||
      fail "has_words says $has for $(printf '%q' "$value"), and bash splits it into ${#ref[@]} word(s)"
    [ "$split" = "$reference" ] ||
      fail "run_words says $split for $(printf '%q' "$value"), and bash splits it into ${#ref[@]} word(s)"
  done
}

@test "nonempty_lines counts the lines that hold anything, and has no status to lose (0159)" {
  [ "$(nonempty_lines "")" = 0 ]
  [ "$(nonempty_lines $'a\n\nb')" = 2 ]
  [ "$(nonempty_lines $'a\n')" = 1 ]
  [ "$(nonempty_lines ' ')" = 1 ]
  run nonempty_lines ""
  assert_success
  [ "$output" = 0 ]
}

@test "run_words holds its own reading against an inherited BASHOPTS or SHELLOPTS, and puts the caller's options back (0082)" {
  # Measured on bash 5.3: BASHOPTS in the environment turns its
  # options on in every bash devbin starts -- `nullglob` drops a word that
  # matches nothing, `dotglob` adds dotfiles to one that matches -- and
  # SHELLOPTS=noglob turns globbing off entirely. Either would change what a
  # declared `run:` runs, silently, on one developer's machine.
  local d="$DEVBIN_TEST_TMPDIR/envglob" got want='<printf><alpha.md><*.nomatch>'
  mkdir -p "$d"
  : >"$d/alpha.md"
  : >"$d/.hidden.md"
  local script='
    . "$DEVBIN_LIB/helpers"
    cd "$1" || exit 2
    declare -a w
    run_words w commands.x.run "printf *.md *.nomatch" || exit 1
    printf "<%s>" "${w[@]}"
  '
  got="$(bash -c "$script" _ "$d")" || fail "run_words refused under the default options"
  # Through `env`: both names are READONLY in this shell, so a prefix
  # assignment here is refused rather than passed on.
  [ "$got" = "$want" ] || fail "under the default options: $got"
  # failglob is in this list because it is the one that turns an
  # unpinned split into a raw bash error with no devbin message at all, rather
  # than into a quietly different command line.
  got="$(env BASHOPTS=nullglob:dotglob:extglob:failglob bash -c "$script" _ "$d")" ||
    fail "run_words refused under BASHOPTS=nullglob:dotglob:extglob:failglob"
  [ "$got" = "$want" ] || fail "under an inherited BASHOPTS: $got"
  got="$(env SHELLOPTS=noglob bash -c "$script" _ "$d")" ||
    fail "run_words refused under SHELLOPTS=noglob"
  [ "$got" = "$want" ] || fail "under an inherited SHELLOPTS=noglob: $got"
  # The pin is for the split alone: the caller's own options are what they were.
  got="$(env BASHOPTS=nullglob bash -c '
    . "$DEVBIN_LIB/helpers"
    cd "$1" || exit 2
    declare -a w
    run_words w commands.x.run "printf *.md" || exit 1
    printf "<%s>" *.nomatch
  ' _ "$d")" || fail "the second expansion refused"
  # With nullglob back on, the word that matches nothing disappears and printf
  # prints its format once with nothing in it; without it, `<*.nomatch>`.
  [ "$got" = '<>' ] || fail "the caller's nullglob was not put back: $got"
}

@test "devbin assigns neither GLOBIGNORE nor GLOBSORT, which is what keeps an inherited one inert (0082)" {
  # Measured on bash 5.3: both arrive from the environment WITHOUT
  # effect, because bash runs their hooks on assignment rather than on import --
  # so run_words does not pin them. The catch is the other way round: a `local
  # GLOBIGNORE` anywhere would activate the inherited value for the rest of the
  # process as the local went out of scope. Nothing in the runtime touches
  # either name, and that is the whole of why the limit is safe to state.
  local hits
  hits="$(cd "$DEVBIN_HOME" && grep -rnE '(GLOBIGNORE|GLOBSORT)=|local[[:space:]]+(GLOBIGNORE|GLOBSORT)' \
    bin/devbin lib bin/.devbin/cmd 2>/dev/null || true)"
  [ -z "$hits" ] || fail "the runtime assigns a glob variable run_words does not pin:
$hits"
  # The matcher finds the line it exists to forbid.
  printf 'local GLOBIGNORE\nGLOBSORT=-name\n' >"$DEVBIN_TEST_TMPDIR/planted"
  local forms
  forms="$(awk 'END { print NR }' "$DEVBIN_TEST_TMPDIR/planted")"
  [ "$forms" -gt 0 ] || fail "no form planted -- the control would compare nothing"
  [ "$(grep -cE '(GLOBIGNORE|GLOBSORT)=|local[[:space:]]+(GLOBIGNORE|GLOBSORT)' "$DEVBIN_TEST_TMPDIR/planted")" = "$forms" ] ||
    fail "the matcher does not find every form it forbids, one a planted line"
}

@test "run_words refuses an output array named after one of its own locals, rather than answering 0 with nothing set (0082)" {
  # `local -n _rw_out="$1"` binds BEFORE `local IFS _rw_o _rw_on` runs, so when
  # the caller's array carries one of those names the local shadows the
  # nameref's target: the words land in the local, the local dies at return, and
  # run_words hands back 0 with the caller's array never set. The caller then
  # runs `"${words[@]}" "$@"` -- an empty command line that executes the
  # arguments typed after the command, at exit 0. That is issue 0082 itself,
  # rebuilt inside the helper written to kill it. Measured on bash 5.3 before
  # the guard: rc=0 and an empty array for _rw_o, _rw_on and IFS.
  #
  # No site can reach it -- every caller passes `words` or `restore_words` --
  # so this holds a trap shut for the next caller. Status 2, not 1: a caller
  # naming the array wrongly is a programming error, and 1 already means the
  # config's command line held no words.
  local script='
    . "$DEVBIN_LIB/helpers"
    for n in _rw_out _rw_o _rw_on _rw_split IFS ""; do
      msg="$(run_words "$n" commands.x.run "echo hi" 2>&1 >/dev/null)"
      rc=$?
      printf "[%s|%s|%s]\n" "$n" "$rc" "$msg"
    done
    declare -a ok_name
    run_words ok_name commands.x.run "echo hi" || exit 9
    printf "[control|%s]\n" "${ok_name[*]}"
  '
  local got
  got="$(bash -c "$script" _)" || fail "the script itself failed: $got"
  local n
  for n in _rw_out _rw_o _rw_on _rw_split IFS; do
    grep -qF "[$n|2|" <<<"$got" ||
      fail "run_words did not refuse the name $n with status 2:
$got"
    grep -q "\[$n|2|.*cannot fill an array named" <<<"$got" ||
      fail "the refusal for $n does not name what is wrong:
$got"
  done
  # The empty name too: `local -n x=""` is an error bash reports in its own
  # words, which say nothing about devbin or about a command line.
  grep -qF "[|2|" <<<"$got" || fail "an empty array name was not refused: $got"
  # And a name that is nobody's local still works, so the guard refuses names
  # rather than refusing callers.
  grep -qF "[control|echo hi]" <<<"$got" || fail "the control call did not fill its array: $got"
}

@test "run_words puts the caller's glob options back even when it cannot write the array (0082)" {
  # The split is pinned between `shopt -u` and `shopt -s`, so an
  # assignment bash REFUSES inside that window -- a readonly target, or a
  # `declare -ia` one and a word that is not arithmetic -- used to leave the six
  # options unset in the caller's shell for the rest of its life. The split now
  # lands in a local and is copied out after the restore, so the window holds
  # nothing that can fail on the caller's behalf.
  local d="$DEVBIN_TEST_TMPDIR/rolock"
  mkdir -p "$d"
  : >"$d/alpha.md"
  local script='
    . "$DEVBIN_LIB/helpers"
    cd "$1" || exit 2
    shopt -s nullglob dotglob
    declare -ra ro=(untouchable)
    run_words ro commands.x.run "printf *.md" >/dev/null 2>&1
    printf "rc=%s nullglob=%s dotglob=%s failglob=%s\n" "$?" \
      "$(shopt -q nullglob && echo on || echo off)" \
      "$(shopt -q dotglob && echo on || echo off)" \
      "$(shopt -q failglob && echo on || echo off)"
  '
  local got
  got="$(bash -c "$script" _ "$d")"
  case "$got" in
    *"nullglob=on dotglob=on failglob=off"*) : ;;
    *) fail "the caller's glob options were not put back after a refused write: $got" ;;
  esac
}

@test "run_words refuses an output array name that is not a shell variable name, rather than returning 0 with nothing set (0082)" {
  # The guard this widens was a BLACKLIST of the helper's own locals, which
  # leaves 0082's own shape sitting next to it. When
  # `$1` is not a name at all, `local -n` fails with bash's own `invalid
  # variable name for name reference`, EXECUTION FALLS THROUGH, and run_words
  # returns 0 with the caller's array never set -- after which the site's
  # `"${words[@]}" "$@"` is an empty command line that runs the arguments typed
  # after the command, at exit 0. Measured on bash 5.3 before the fix, all at
  # rc=0: 2bad, "a b", a-b, -x, "a;b". `arr[0]` reached the copy and returned 1,
  # reporting a perfectly good name as "the config's line held no words".
  #
  # So the question is asked POSITIVELY, through is_identifier, which is the one
  # definition of a shell variable name in the runtime and is what
  # assert_identifier reaches for too.
  local script='
    . "$DEVBIN_LIB/helpers"
    for n in 2bad "a b" a-b -x "a;b" "arr[0]" ""; do
      msg="$(run_words "$n" commands.x.run "echo hello" 2>&1 >/dev/null)"
      printf "[%s|%s|%s]\n" "$n" "$?" "$msg"
    done
    declare -a fine
    run_words fine commands.x.run "echo hello" || exit 9
    printf "[control|%s]\n" "${fine[*]}"
  '
  local got n
  got="$(bash -c "$script" _)" || fail "the script itself failed: $got"
  for n in 2bad "a b" a-b -x "a;b" "arr[0]" ""; do
    grep -qF "[$n|2|" <<<"$got" ||
      fail "run_words did not refuse the name '$n' with status 2:
$got"
  done
  # And the refusal says what is wrong with it, rather than blaming the config.
  grep -qF "is not a shell variable name" <<<"$got" ||
    fail "the refusal does not say the name is the problem: $got"
  grep -q "2bad.*holds no words" <<<"$got" &&
    fail "a bad NAME was reported as a config line with no words: $got"
  grep -qF "[control|echo hello]" <<<"$got" ||
    fail "the control call did not fill its array: $got"
}

@test "is_identifier is the one definition of a shell variable name, and assert_identifier reaches for it (0082)" {
  # The charset lived only inside assert_identifier until run_words needed the
  # same question. Two spellings of "is a name" is the divergence Highlander is
  # about, so there is one predicate and a refusal POLICY per caller on top of it:
  # assert_identifier dies naming which rule broke, run_words warns and returns,
  # since nothing in the release library may die.
  local got
  got="$(bash -c '
    . "$DEVBIN_LIB/helpers"
    for v in good _ok a1 2bad "a b" a-b "" "arr[0]" __x9; do
      is_identifier "$v" && printf "[%s|yes]" "$v" || printf "[%s|no]" "$v"
    done
  ' _)"
  [ "$got" = '[good|yes][_ok|yes][a1|yes][2bad|no][a b|no][a-b|no][|no][arr[0]|no][__x9|yes]' ] ||
    fail "is_identifier does not answer bash's own rule: $got"
  # assert_identifier still dies, and still with the message naming the rule.
  run bash -c '. "$DEVBIN_LIB/helpers"; assert_identifier "2bad" "options.x.export"' _
  assert_failure
  assert_output_contains "must start with a letter or underscore"
  run bash -c '. "$DEVBIN_LIB/helpers"; assert_identifier "a-b" "options.x.export"' _
  assert_failure
  assert_output_contains "may contain only letters, digits and underscore"
  # And there is ONE charset in the runtime: every line of lib/helpers that
  # spells it lies inside is_identifier, so assert_identifier carries no rule
  # the predicate does not have, and a copy anywhere else is named.
  local outside
  outside="$(cd "$DEVBIN_HOME" && awk '
    /^is_identifier\(\) *\{/ { inside = 1 }
    /A-Za-z0-9_\]\*/ { seen = 1; if (!inside) print FNR ": " $0 }
    inside && /^}/ { inside = 0 }
    END { if (!seen) print "no line of lib/helpers spells it" }
  ' lib/helpers)" || fail "awk could not read lib/helpers"
  [ -z "$outside" ] || fail "the identifier charset is spelled outside is_identifier in lib/helpers:\n$outside"
}

# ============================================================================
# A LIST READ WHOLE (0139)
# ============================================================================

@test "link_step reads one link's content exactly, joined to the link's directory, or refuses it (0139)" {
  # A walk that split a link's content
  # itself stopped at a newline and looked up the wrong name. BSD's readlink
  # prints a content ending in a newline as the same name without it
  # (measured), so a content read back is checked against the link's own size.
  local d="$DEVBIN_TEST_TMPDIR/ls" got
  mkdir -p "$d/sub"
  : >"$d/f"
  : >"$d/a"
  ln -s f "$d/l1"
  ln -s ../f "$d/sub/up"
  ln -s /etc "$d/abs"
  ln -s $'a\nb' "$d/mid"
  ln -s $'a\n' "$d/end"
  # THE CONTROLS: a relative content is joined as written, an absolute one kept.
  got="$(link_step "$d/l1")" || fail "link_step refused a plain link"
  [ "$got" = "$d/f" ] || fail "expected $d/f, got $got"
  got="$(link_step "$d/sub/up")" || fail "link_step refused a link holding .."
  [ "$got" = "$d/sub/../f" ] || fail "expected $d/sub/../f untidied, got $got"
  got="$(link_step "$d/abs")" || fail "link_step refused an absolute link"
  [ "$got" = /etc ] || fail "expected /etc, got $got"
  # A content holding a newline is read whole; one ending in a newline, which
  # BSD's readlink prints as a, is refused.
  got="$(link_step "$d/mid")" || fail "link_step refused a content holding a newline"
  [ "$got" = "$d/a"$'\n'"b" ] || fail "the content holding a newline was not read whole: $got"
  run link_step "$d/end"
  assert_failure
  [ -z "$output" ] || fail "link_step printed a step for a content ending in a newline: $output"
  # A link named as find would read an option or an expression is still read
  # ("!" and "(" printed find's usage).
  ln -s f "$d/-x"
  ln -s f "$d/!"
  ln -s f "$d/("
  got="$(cd "$d" && link_step -x)" || fail "link_step refused a link named -x"
  [ "$got" = f ] || fail "expected f through -x, got $got"
  got="$(cd "$d" && link_step '!')" || fail "link_step refused a link named !"
  [ "$got" = f ] || fail "expected f through !, got $got"
  got="$(cd "$d" && link_step '(')" || fail "link_step refused a link named ("
  [ "$got" = f ] || fail "expected f through (, got $got"
}

@test "link_step counts a content's length in bytes, whatever the locale (0139)" {
  # The size find reads is in bytes; a count in characters refused a content
  # of multibyte characters under a UTF-8 locale.
  local d="$DEVBIN_TEST_TMPDIR/lsm" got loc
  loc="$(utf8_locale)" || skip "no UTF-8 locale on this runner: a multibyte content's length was NOT checked"
  mkdir -p "$d"
  ln -s $'caf\xc3\xa9' "$d/multi"
  got="$(LC_ALL="$loc" link_step "$d/multi")" || fail "link_step refused a content of multibyte characters under $loc"
  [ "$got" = "$d/caf"$'\xc3\xa9' ] || fail "expected the multibyte name, got $got"
}

@test "link_step refuses a content ending in a newline under GNU's readlink too (0139)" {
  # GNU's readlink prints such a content whole, where BSD's drops a newline;
  # a sentinel that kept what GNU's printed let the content through, and the
  # caller's own command substitution stripped it: a tree read as gone at rc 0.
  # The size check refuses it under either. Run under the first GNU readlink found, readlink or greadlink.
  local d="$DEVBIN_TEST_TMPDIR/lsg" r gnu="" got ver
  for r in readlink greadlink; do
    if command -v "$r" >/dev/null && ver="$("$r" --version 2>/dev/null)" && grep -q GNU <<<"$ver"; then
      gnu="$(command -v "$r")"
      break
    fi
  done
  [ -n "$gnu" ] || skip "no GNU readlink on this runner: its reading of a content ending in a newline was NOT checked"
  mkdir -p "$d/gnubin"
  : >"$d/f"
  ln -s f "$d/l1"
  ln -s $'a\n' "$d/end"
  ln -s "$gnu" "$d/gnubin/readlink"
  got="$(PATH="$d/gnubin:$PATH" link_step "$d/l1")" || fail "link_step under GNU's readlink refused a plain link"
  [ "$got" = "$d/f" ] || fail "under GNU's readlink, expected $d/f, got $got"
  run env PATH="$d/gnubin:$PATH" bash -c "$(declare -f link_step); link_step \"\$1\"" _ "$d/end"
  assert_failure
  [ -z "$output" ] || fail "under GNU's readlink, link_step printed a step for a content ending in a newline: $output"
}

@test "find_list reads every path whole into the array, and returns find's failure with find's error, keeping what it listed (0139)" {
  local d="$DEVBIN_TEST_TMPDIR/fl" st=0 f
  local -a got=() made=("$DEVBIN_TEST_TMPDIR/fl/a" "$DEVBIN_TEST_TMPDIR/fl/sub/b" "$DEVBIN_TEST_TMPDIR/fl/two"$'\n'"lines")
  mkdir -p "$d/sub" "$d/locked"
  for f in "${made[@]}"; do : >"$f"; done
  # THE CONTROL: readable, every file is listed, the name holding a newline as one.
  find_list got "$d" -type f -print0 || fail "find_list failed over a readable tree"
  [ "${#got[@]}" -eq "${#made[@]}" ] || fail "expected ${#made[@]} paths, got ${#got[@]}: ${got[*]}"
  [ "${got[2]}" = "$d/two"$'\n'"lines" ] || fail "the name holding a newline was not read whole: ${got[*]}"
  : >"$d/locked/c"
  chmod 000 "$d/locked"
  if [ -r "$d/locked" ]; then
    chmod 755 "$d/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  run find_list got "$d" -type f -print0
  local rst="$status" rout="$output"
  # What it could list is still listed, for a caller that acts on it.
  got=()
  find_list got "$d" -type f -print0 2>/dev/null || st=$?
  # The mode goes back before any assertion, so a red run leaves nothing that
  # teardown cannot remove.
  chmod 755 "$d/locked"
  [ "$rst" -ne 0 ] || fail "find_list returned 0 over a directory find could not read: $rout"
  assert_find_denied "$d/locked" "$rout"
  [ "$st" -ne 0 ] || fail "find_list returned 0 over a directory find could not read"
  [ "${#got[@]}" -eq "${#made[@]}" ] || fail "expected the ${#made[@]} readable paths beside the failure, got ${#got[@]}: ${got[*]}"
}

@test "find_list lists in the C locale's order under a locale that collates otherwise (0139)" {
  local loc d="$DEVBIN_TEST_TMPDIR/fo" sorted
  local -a got=()
  loc="$(utf8_locale en_US)" ||
    skip "no en_US UTF-8 locale on this runner: the order under another collation was NOT checked"
  # THE CONTROL: that locale really orders a before B, where C puts B first.
  sorted="$(printf 'B\na\n' | LC_ALL="$loc" sort)"
  [ "${sorted%%$'\n'*}" = a ] ||
    skip "$loc collates B and a as C does here: the order under another collation was NOT checked"
  mkdir -p "$d"
  local -a made=("$d/a" "$d/B")
  local f
  for f in "${made[@]}"; do : >"$f"; done
  LC_ALL="$loc" find_list got "$d" -type f -print0 || fail "find_list failed over a readable tree"
  [ "${#got[@]}" -eq "${#made[@]}" ] || fail "expected ${#made[@]} paths, got ${#got[@]}: ${got[*]}"
  [ "${got[0]}" = "$d/B" ] && [ "${got[1]}" = "$d/a" ] || fail "not in the C locale's order under $loc: ${got[*]}"
}

@test "find_list refuses, at status 2, a name it cannot fill and an expression that does not end in -print0 (0139)" {
  # Measured: each of these left the caller's array
  # empty at status 0, so a gate reading it passed over nothing.
  local bad
  : >"$DEVBIN_TEST_TMPDIR/a"
  for bad in 2bad 'a b' a-b '' _fl_out; do
    run find_list "$bad" "$DEVBIN_TEST_TMPDIR" -type f -print0
    [ "$status" -eq 2 ] || fail "find_list took '$bad' as an array to fill: status $status, $output"
  done
  run find_list got "$DEVBIN_TEST_TMPDIR" -type f
  [ "$status" -eq 2 ] || fail "find_list took an expression without -print0: status $status, $output"
  assert_output_contains "must end in -print0"
  run find_list got
  [ "$status" -eq 2 ] || fail "find_list took no expression at all: status $status, $output"
  # An array mapfile cannot fill is its own failure, not find's (it was refused
  # only by the writer's SIGPIPE, at 141).
  local -A assoc=()
  run find_list assoc "$DEVBIN_TEST_TMPDIR" -type f -print0
  [ "$status" -eq 2 ] || fail "find_list reported an array it could not fill as status $status: $output"
  assert_output_contains "could not fill 'assoc'"
  # And a readonly one, which mapfile refuses before it reads anything.
  local -a ro=()
  readonly ro
  run find_list ro "$DEVBIN_TEST_TMPDIR" -type f -print0
  [ "$status" -eq 2 ] || fail "find_list reported a readonly array as status $status: $output"
  assert_output_contains "could not fill 'ro'"
}

@test "cargo_target_dirs returns 1 when its sort fails, never an empty list at 0 (0139)" {
  # Driven with a failing sort, the list came back
  # empty at status 0, which the artefact check reads as no tree and
  # INCONCLUSIVE. THE CONTROL first: with the real sort, the tree is listed.
  local d="$DEVBIN_TEST_TMPDIR/cp" stub="$DEVBIN_TEST_TMPDIR/stub"
  mkdir -p "$d/crate/target" "$stub"
  run env PROJECT_ROOT="$d" bash -c '. "$1"; cargo_target_dirs' _ "$DEVBIN_LIB_DIR/helpers"
  assert_success
  assert_output_line "$d/crate/target"
  printf '#!/bin/sh\nexit 3\n' >"$stub/sort"
  chmod +x "$stub/sort"
  run env PROJECT_ROOT="$d" PATH="$stub:$PATH" bash -c '. "$1"; cargo_target_dirs' _ "$DEVBIN_LIB_DIR/helpers"
  [ "$status" -ne 0 ] || fail "cargo_target_dirs returned 0 over a failed sort: $output"
}

@test "is_yes_answer takes y and yes in any case, and nothing else (0134)" {
  local a
  for a in y Y yes YES Yes yEs; do
    is_yes_answer "$a" || fail "'$a' is not a yes"
  done
  for a in "" n no ye yess " y" "y " "yes please" 1; do
    ! is_yes_answer "$a" || fail "'$a' is a yes"
  done
}

@test "every question devbin asks a person reads its answer through is_yes_answer (0134)" {
  # ask_person took y or Y and devbin_offer_upgrade took y, Y, yes and YES: two
  # answer sets for one question. Each now asks the one helper and matches no
  # reply of its own.
  local f body
  for f in ask_person devbin_offer_upgrade; do
    body="$(awk "/^$f\\(\\) \\{/,/^}/" "$DEVBIN_LIB_DIR/helpers")"
    [ -n "$body" ] || fail "could not extract $f -- the checks below would be vacuous"
    grep -q 'is_yes_answer "$reply"' <<<"$body" || fail "$f does not ask is_yes_answer:
$body"
    ! grep -qE 'case "\$reply"' <<<"$body" || fail "$f matches the reply itself:
$body"
  done
}

# ---------------------------------------------------------------------------
# find_walk (issue 0145): a directory find can list but not search
# ---------------------------------------------------------------------------

# _fw_finds -- print one PATH prefix per find this runner has: "" for the
# native find, and a directory whose `find` is GNU's where gfind is present.
_fw_finds() {
  printf '\n'
  if command -v gfind >/dev/null 2>&1; then
    mkdir -p "$DEVBIN_TEST_TMPDIR/gnufind"
    ln -sf "$(command -v gfind)" "$DEVBIN_TEST_TMPDIR/gnufind/find"
    printf '%s\n' "$DEVBIN_TEST_TMPDIR/gnufind"
  else
    echo "# gfind is not on this runner: the GNU half was NOT checked" >&3
  fi
}

# _fw_locked <dir> -- mode 0644, or skip when this runner searches it anyway.
_fw_locked() {
  chmod 0644 "$1"
  if [ -x "$1" ]; then
    chmod 0755 "$1"
    skip "running with permissions that search a mode-0644 directory: NOT checked"
  fi
}

@test "find_walk names a directory it can list but not search, prunes it, lists the rest, and fails, under each find (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw" pre f
  local -a made=("$DEVBIN_TEST_TMPDIR/fw/open/a" "$DEVBIN_TEST_TMPDIR/fw/shut/deep/b")
  mkdir -p "$d/open" "$d/shut/deep"
  for f in "${made[@]}"; do : >"$f"; done
  # THE CONTROL: readable, it is find.
  run find_walk "$d" -type f -print
  assert_success
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq "${#made[@]}" ] || fail "the control did not list every file: $output"
  _fw_locked "$d/shut"
  while IFS= read -r pre; do
    PATH="${pre:+$pre:}$PATH" run find_walk "$d" -type f -print
    [ "$status" -eq 1 ] || { chmod 0755 "$d/shut"; fail "exited $status, not 1 (${pre:-native find}): $output"; }
    assert_output_line "devbin: cannot search $d/shut -- nothing beneath it was looked at"
    assert_output_line "$d/open/a"
    refute_output_contains "$d/shut/deep"
  done < <(_fw_finds)
  chmod 0755 "$d/shut"
}

@test "find_walk names each such directory once, one named with a newline shell-quoted (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw2" n
  local -a shut=("$DEVBIN_TEST_TMPDIR/fw2/one" "$DEVBIN_TEST_TMPDIR/fw2/two"$'\n'"x")
  mkdir -p "${shut[@]}"
  : >"$d/one/f"
  : >"$d/two"$'\n'"x/g"
  chmod 0644 "${shut[@]}"
  if [ -x "$d/one" ]; then chmod 0755 "${shut[@]}"; skip "searches a mode-0644 directory: NOT checked"; fi
  run find_walk "$d" -type f -print
  chmod 0755 "${shut[@]}"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  n="$(printf '%s\n' "$output" | grep -c 'cannot search')" || n=0
  [ "$n" -eq "${#shut[@]}" ] || fail "expected ${#shut[@]} directories named, got $n: $output"
  assert_output_contains "cannot search $(printf '%q' "$d/two"$'\n'"x") -- nothing beneath it was looked at"
}

@test "find_walk leaves a directory it cannot read to find's own error, named once (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw3"
  mkdir -p "$d/sealed"
  : >"$d/sealed/f"
  chmod 0111 "$d/sealed"
  run find_walk "$d" -type f -print
  chmod 0755 "$d/sealed"
  [ "$status" -ne 0 ] || fail "exited 0 over a directory find could not read: $output"
  assert_find_denied "$d/sealed" "$output"
  refute_output_contains "cannot search $d/sealed"
}

@test "find_walk's depth rule: a directory at -maxdepth is never entered, so it is not named; one above it is (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw4"
  mkdir -p "$d/sub/deep"
  : >"$d/sub/deep/f"
  _fw_locked "$d/sub"
  run find_walk "$d" -maxdepth 1 -print
  local st1="$status" out1="$output"
  run find_walk "$d" -maxdepth 2 -print
  local st2="$status" out2="$output"
  chmod 0755 "$d/sub"
  [ "$st1" -eq 0 ] || fail "a 0644 sub/ at -maxdepth 1 failed the walk: $out1"
  [[ "$out1" != *"cannot search"* ]] || fail "a directory the walk never enters was named: $out1"
  [ "$st2" -eq 1 ] || fail "a 0644 sub/ under -maxdepth 2 did not fail the walk: $out2"
  [[ "$out2" == *"cannot search $d/sub -- nothing beneath it was looked at"* ]] || fail "it was not named: $out2"
}

@test "find_walk counts depth from the start path a directory lies under, and names it once (0145)" {
  # Two start paths at different depths: shut is one level under $d/a and two
  # under $d, so both walks meet it.
  local d="$DEVBIN_TEST_TMPDIR/fw5" st out n
  mkdir -p "$d/a/shut/x"
  : >"$d/a/shut/x/f"
  _fw_locked "$d/a/shut"
  # -maxdepth 1: at depth 1 under $d/a, never entered, and beyond the walk
  # under $d. No hole.
  run find_walk "$d/a" "$d" -maxdepth 1 -print
  st="$status" out="$output"
  [ "$st" -eq 0 ] || { chmod 0755 "$d/a/shut"; fail "a directory no walk would enter failed it: $out"; }
  # -maxdepth 2: under $d it is at -maxdepth, never entered, but under $d/a the
  # walk meant to look beneath it. A hole, named once.
  run find_walk "$d/a" "$d" -maxdepth 2 -print
  st="$status" out="$output"
  [ "$st" -eq 1 ] || { chmod 0755 "$d/a/shut"; fail "a 0644 directory one start would have entered was not a hole: $out"; }
  n="$(printf '%s\n' "$out" | grep -c "cannot search $d/a/shut")" || n=0
  [ "$n" -eq 1 ] || { chmod 0755 "$d/a/shut"; fail "it was named $n times, not once: $out"; }
  # And the same with the start paths the other way round: the verdict does not
  # rest on the first start path it lies under.
  run find_walk "$d" "$d/a" -maxdepth 2 -print
  st="$status" out="$output"
  chmod 0755 "$d/a/shut"
  [ "$st" -eq 1 ] || fail "with the starts reversed, the hole was not one: $out"
  n="$(printf '%s\n' "$out" | grep -c "cannot search $d/a/shut")" || n=0
  [ "$n" -eq 1 ] || fail "with the starts reversed, it was named $n times, not once: $out"
}

@test "find_walk keeps a caller's own prune and -H, refuses an expression that prints nothing, and keeps a missing start point's status (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw6"
  mkdir -p "$d/real/skip" "$d/real/keep"
  : >"$d/real/skip/f"
  : >"$d/real/keep/g"
  ln -s "$d/real" "$d/link"
  run find_walk -H "$d/link" -name skip -prune -o -type f -print
  assert_success
  assert_output_line "$d/link/keep/g"
  refute_output_contains "skip/f"
  run find_walk "$d" -type f
  [ "$status" -eq 2 ] || fail "an expression with no -print or -print0 exited $status, not 2: $output"
  assert_output_contains "find_walk: the find expression names no -print or -print0"
  run find_walk "$d/nosuch" -type f -print
  [ "$status" -ne 0 ] || fail "a missing start point exited 0"
  assert_output_contains "$d/nosuch"
  refute_output_contains "cannot search"
}

@test "find_walk asks a caller's leading prune first, so a directory it prunes at 0644 is not examined, under each find (0145)" {
  # The clause ran before the caller's prune, and a .git at 0644 failed clean's
  # walk, and with it fullcycle's clean.
  local d="$DEVBIN_TEST_TMPDIR/fw8" pre
  mkdir -p "$d/.git/objects" "$d/src"
  : >"$d/.git/objects/o"
  : >"$d/src/f"
  _fw_locked "$d/.git"
  while IFS= read -r pre; do
    PATH="${pre:+$pre:}$PATH" run find_walk "$d" \( -name .git -o -name node_modules \) -prune -o -type f -print
    [ "$status" -eq 0 ] || { chmod 0755 "$d/.git"; fail "a pruned 0644 .git failed the walk (${pre:-native find}), exit $status: $output"; }
    assert_output_line "$d/src/f"
    refute_output_contains "cannot search"
  done < <(_fw_finds)
  chmod 0755 "$d/.git"
}

@test "find_walk still hands an unsearchable directory itself to the caller's expression (0145)" {
  # The clause is false either way: a walk for directories named target finds
  # one at 0644, and names it, rather than losing it.
  local d="$DEVBIN_TEST_TMPDIR/fw9"
  mkdir -p "$d/crate/target/debug"
  _fw_locked "$d/crate/target"
  run find_walk "$d" -type d -name target -print
  chmod 0755 "$d/crate/target"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_line "$d/crate/target"
  assert_output_contains "cannot search $d/crate/target -- nothing beneath it was looked at"
}

@test "find_walk names every unsearchable directory under errexit though find itself failed (0145)" {
  # find_walk read find's status with `wait "$!"` on a line of its own, and
  # under errexit a find that failed on one directory ended it there, before
  # a 0644 directory elsewhere was named.
  local d="$DEVBIN_TEST_TMPDIR/fw10" rc=0
  mkdir -p "$d/sealed" "$d/shut/x"
  : >"$d/sealed/f"
  : >"$d/shut/x/g"
  chmod 0000 "$d/sealed"
  _fw_locked "$d/shut"
  run bash -c 'set -e; . "$1"; DEVBIN_NAME=devbin; find_walk "$2" -type f -print' _ "$DEVBIN_HOME/lib/helpers" "$d"
  chmod 0755 "$d/sealed" "$d/shut"
  [ "$status" -ne 0 ] || fail "exited 0: $output"
  assert_find_denied "$d/sealed" "$output"
  assert_output_contains "cannot search $d/shut -- nothing beneath it was looked at"
}

@test "find_walk refuses a -mindepth above 1 at status 2, and names a directory reached by two spellings once (0145)" {
  local d="$DEVBIN_TEST_TMPDIR/fw11" n
  mkdir -p "$d/r/shut/x"
  : >"$d/r/shut/x/f"
  run find_walk "$d" -mindepth 2 -type f -print
  [ "$status" -eq 2 ] || fail "a -mindepth 2 exited $status, not 2: $output"
  assert_output_contains "find_walk: -mindepth 2 leaves the directories above depth 2 unexamined"
  run find_walk "$d" -mindepth 1 -type f -print
  assert_success
  _fw_locked "$d/r/shut"
  run find_walk "$d/r" "$d/r//" -type f -print
  chmod 0755 "$d/r/shut"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  n="$(printf '%s\n' "$output" | grep -c 'cannot search')" || n=0
  [ "$n" -eq 1 ] || fail "one directory reached by two spellings was named $n times: $output"
}

@test "find_walk refuses a -maxdepth or -mindepth that names no depth, at status 2 (0145)" {
  # shift 2 fails without shifting on a last word: the walk spun forever, or
  # under nounset died on an unbound $2.
  local d="$DEVBIN_TEST_TMPDIR/fw12" o
  mkdir -p "$d"
  for o in -maxdepth -mindepth; do
    # Under nounset, so a walk without the guard fails on $2 rather than spins.
    run bash -c 'set -u; . "$1"; DEVBIN_NAME=devbin; find_walk "$2" "$3"' _ "$DEVBIN_HOME/lib/helpers" "$d" "$o"
    [ "$status" -eq 2 ] || fail "$o with no depth exited $status, not 2: $output"
    assert_output_contains "find_walk: $o names no depth"
  done
}

@test "find_walk's pre-filter passes over only what the running user owns and can search, read from EUID (0145)" {
  # A SOURCE PIN, because no arm can build the case: a runner that is not root
  # cannot make a directory it does not own, and only such a directory shows
  # the owner half at work (a root-owned 0744 directory, named by the clause,
  # was passed over silently with the owner half dropped). And the owner is
  # $EUID, never an `id` found through PATH.
  local body
  body="$(declare -f find_walk)"
  [[ "$body" == *'! \( -user "$EUID" -perm -u+x \)'* ]] ||
    fail "find_walk's pre-filter is not the owner's own search bit read from EUID:
$body"
  [[ "$body" != *'id -u'* ]] || fail "find_walk asks id for the running user"
}

# _fw_holes <file> -- the records in a FIND_WALK_HOLES file, each NUL as |.
_fw_holes() {
  tr '\0' '|' <"$1"
}

@test "find_walk records a failure it cannot place as one empty record, beside a hole it did record, under each find (0163)" {
  # A start path that does not exist fails find with nothing recorded. Beside a
  # directory find cannot read, which is recorded, the empty record was
  # dropped (one 000 directory hid an ACL's hole).
  local d="$DEVBIN_TEST_TMPDIR/fwh" f="$DEVBIN_TEST_TMPDIR/fwh.holes" pre got
  mkdir -p "$d/sealed"
  chmod 000 "$d/sealed"
  if [ -r "$d/sealed" ]; then chmod 755 "$d/sealed"; skip "running with permissions that read a mode-000 directory: NOT checked"; fi
  while IFS= read -r pre; do
    : >"$f"
    PATH="${pre:+$pre:}$PATH" FIND_WALK_HOLES="$f" run find_walk "$d/nope" -print
    got="$(_fw_holes "$f")"
    [ "$status" -ne 0 ] && [ "$got" = "|" ] || { chmod 755 "$d/sealed"; fail "nonexistent (${pre:-native find}): status $status, records [$got]"; }
    # THE CONTROL: the hole alone is placed, so no empty record follows it.
    : >"$f"
    PATH="${pre:+$pre:}$PATH" FIND_WALK_HOLES="$f" run find_walk "$d" -print
    got="$(_fw_holes "$f")"
    [ "$got" = "$d/sealed|" ] || { chmod 755 "$d/sealed"; fail "the hole alone (${pre:-native find}): records [$got]"; }
    : >"$f"
    PATH="${pre:+$pre:}$PATH" FIND_WALK_HOLES="$f" run find_walk "$d" "$d/nope" -print
    got="$(_fw_holes "$f")"
    [ "$got" = "$d/sealed||" ] || { chmod 755 "$d/sealed"; fail "the hole and an unplaced failure (${pre:-native find}): records [$got]"; }
  done < <(_fw_finds)
  chmod 755 "$d/sealed"
}

@test "find_walk drops a FIND_WALK_QUIET it inherits, so a walk still prints (0163)" {
  local d="$DEVBIN_TEST_TMPDIR/fwq"
  mkdir -p "$d"
  : >"$d/x"
  run env FIND_WALK_QUIET=1 bash -c '. "$1"; DEVBIN_NAME=devbin; find_walk "$2" -type f -print' _ "$DEVBIN_HOME/lib/helpers" "$d"
  assert_success
  assert_output_line "$d/x"
}

@test "find_walk refuses an action beyond printing while FIND_WALK_HOLES is set, since the walk may run twice (0163)" {
  local d="$DEVBIN_TEST_TMPDIR/fwa" f="$DEVBIN_TEST_TMPDIR/fwa.holes" a
  mkdir -p "$d"
  : >"$d/x"
  for a in -delete "-exec true {} ;"; do
    # shellcheck disable=SC2086 # the action's words are split on purpose
    FIND_WALK_HOLES="$f" run find_walk "$d" -type f $a -print
    [ "$status" -eq 2 ] || fail "$a exited $status, not 2: $output"
    assert_output_contains "with FIND_WALK_HOLES set the expression may run twice, and ${a%% *} would act twice"
  done
  [ -e "$d/x" ] || fail "-delete ran"
  # In a leading prune group too, which is lifted ahead of the clause.
  FIND_WALK_HOLES="$f" run find_walk "$d" \( -name nope -exec true {} \; \) -prune -o -type f -print
  [ "$status" -eq 2 ] || fail "-exec in the prune group exited $status, not 2: $output"
  assert_output_contains "and -exec would act twice"
  # Unset, an action is the caller's own, as before.
  run find_walk "$d" -type f -exec true {} \; -print
  assert_success
}

@test "find_walk's depth verdict is the same for a start path spelled plain, with a trailing slash, and as ., under each find (0145)" {
  # Depth is counted from the start path as spelled: under a start `a//` both
  # finds print `a//x`, and under `.` they print `./x`. 0139 met this class
  # twice.
  local d="$DEVBIN_TEST_TMPDIR/fw7" pre sp m st
  mkdir -p "$d/sub/deep/x"
  : >"$d/sub/deep/x/f"
  _fw_locked "$d/sub/deep"
  while IFS= read -r pre; do
    for sp in "$d" "$d/" "$d//" .; do
      for m in 2 3; do
        st=0
        ( cd "$d" && PATH="${pre:+$pre:}$PATH" find_walk "$sp" -maxdepth "$m" -print >/dev/null 2>&1 ) || st=$?
        if [ "$m" = 2 ] && [ "$st" -ne 0 ]; then
          chmod 0755 "$d/sub/deep"
          fail "start '$sp' -maxdepth 2 (${pre:-native find}): exited $st over a directory it never enters"
        fi
        if [ "$m" = 3 ] && [ "$st" -ne 1 ]; then
          chmod 0755 "$d/sub/deep"
          fail "start '$sp' -maxdepth 3 (${pre:-native find}): exited $st, not 1, over a hole it meant to enter"
        fi
      done
    done
  done < <(_fw_finds)
  chmod 0755 "$d/sub/deep"
}

@test "gate_exec runs its command with stdin from /dev/null, the flag from its own stdin, and the command's status (0158, 0180)" {
  local out probe='read -r l; printf "read=%s flag=%s in=%s" "$?" "${DEVBIN_GATE_TTY-unset}" "${DEVBIN_IN_GATE-unset}"'
  # Not a terminal, outside a gate: the flag is read from stdin, 0, over a stale
  # one in the environment, and the tool reads EOF, not the caller's input.
  out="$(DEVBIN_GATE_TTY=1 gate_exec bash -c "$probe" <<<"typed")"
  [ "$out" = "read=1 flag=0 in=1" ] || fail "off a terminal, outside a gate, it gave: $out"
  # Inside a gate the flag it inherited is kept: the gate's stdin is /dev/null,
  # and the person the gate saw is still there.
  out="$(DEVBIN_IN_GATE=1 DEVBIN_GATE_TTY=1 gate_exec bash -c "$probe" <<<"typed")"
  [ "$out" = "read=1 flag=1 in=1" ] || fail "inside a gate it gave: $out"
  # Its own status, unchanged.
  run gate_exec sh -c 'exit 3'
  [ "$status" -eq 3 ] || fail "gate_exec returned $status for a command that exited 3"
  # And no command at all is refused, leaving nothing set in the caller.
  run gate_exec
  [ "$status" -eq 2 ] || fail "gate_exec with no command returned $status"
  assert_output_contains "gate_exec: no command to run"
  gate_exec 2>/dev/null || true
  [ -z "${DEVBIN_GATE_TTY+set}" ] || fail "gate_exec with no command left DEVBIN_GATE_TTY set in the caller"
  # A terminal: a handler that sources helpers ALONE reaches it, the flag is 1,
  # and the tool still reads EOF rather than the terminal. run_tty_eof runs
  # script(1), so require_pty guards it, as it does every run_tty_eof arm;
  # requiring expect, which only run_tty_answer runs, failed CI's Ubuntu
  # runner, which has none, before this half ever ran there (issue 0180).
  require_pty
  run run_tty_eof bash -c '. "$1/helpers" && gate_exec bash -c "read -r l; printf \"read=%s flag=%s\" \"\$?\" \"\$DEVBIN_GATE_TTY\""' _ "$DEVBIN_LIB_DIR"
  assert_output_contains "read=1 flag=1"
}

@test "git_marker_above finds a .git at or above an absolute directory, answers no where there is none, and refuses a relative path (0179)" {
  # Read from the filesystem, for a caller whose git did not answer: a
  # directory, a gitfile and a link, dangling or not, each count, in the
  # directory or above it. The harness refuses a TMPDIR with a .git above it,
  # so nothing above these fixtures holds one.
  local top="$DEVBIN_TEST_TMPDIR/top"
  mkdir -p "$top/a/b"
  run git_marker_above "$top/a/b"
  [ "$status" -eq 1 ] || fail "with no .git above it, it answered $status"
  mkdir "$top/.git"
  run git_marker_above "$top/a/b"
  [ "$status" -eq 0 ] || fail "a .git directory above it answered $status"
  run git_marker_above "$top"
  [ "$status" -eq 0 ] || fail "a .git directory in it answered $status"
  rmdir "$top/.git"
  printf 'gitdir: %s\n' "$DEVBIN_TEST_TMPDIR/elsewhere" >"$top/a/.git"
  run git_marker_above "$top/a/b"
  [ "$status" -eq 0 ] || fail "a gitfile above it answered $status"
  rm "$top/a/.git"
  ln -s "$DEVBIN_TEST_TMPDIR/nowhere" "$top/a/b/.git"
  run git_marker_above "$top/a/b"
  [ "$status" -eq 0 ] || fail "a dangling .git link in it answered $status"
  rm "$top/a/b/.git"
  run git_marker_above /
  [ "$status" -eq 1 ] || fail "/ answered $status"
  # A relative path has the working directory's ancestors, not its own.
  run git_marker_above a/b
  [ "$status" -eq 2 ] || fail "a relative path answered $status"
}

@test "git_repo_absent says a failed git call had no repository only where no .git sits at or above the directory (0185)" {
  local t="$DEVBIN_TEST_TMPDIR/absent"
  mkdir -p "$t/none/sub" "$t/repo/sub" "$t/link/sub"
  mkdir "$t/repo/.git"
  ln -s "$t/nowhere" "$t/link/.git"
  run git_repo_absent "$t/none/sub"
  [ "$status" -eq 0 ] || fail "no .git anywhere read as a repository (status $status)"
  run git_repo_absent "$t/repo"
  [ "$status" -eq 1 ] || fail "a .git at the directory read as no repository"
  run git_repo_absent "$t/repo/sub"
  [ "$status" -eq 1 ] || fail "a .git above the directory read as no repository"
  run git_repo_absent "$t/link/sub"
  [ "$status" -eq 1 ] || fail "a dangling .git link above read as no repository"
  run git_repo_absent "$t/no-such-dir"
  [ "$status" -eq 1 ] || fail "a directory that cannot be resolved read as no repository"
  (cd "$t/none" && git_repo_absent sub) || fail "a relative directory with no .git read as a repository"
  (cd "$t/repo/sub" && ! git_repo_absent ..) || fail "a relative path up to a repository read as none"
  # Resolved, never walked as written: each link's own parents say the opposite.
  ln -s "$t/repo/sub" "$t/none/intorepo"
  ln -s "$t/none/sub" "$t/repo/intonone"
  run git_repo_absent "$t/none/intorepo"
  [ "$status" -eq 1 ] || fail "a link from a tree with no .git into a repository read as no repository"
  run git_repo_absent "$t/repo/intonone"
  [ "$status" -eq 0 ] || fail "a link from a repository into a tree with no .git read as a repository"
}

@test "git_repo_absent agrees with git's own discovery at GIT_CEILING_DIRECTORIES, in each form git reads it (0185)" {
  # git stops below a ceiling and says there is no repository; the reading
  # walked past it and called the directory a checkout git could not read. Each
  # case asks git and the reading one question, so the oracle is git itself, and
  # both of git's answers must occur or the arm proved nothing.
  local t="$DEVBIN_TEST_TMPDIR/ceil" c g a none=0 repo=0
  mkdir -p "$t/top/a/b"
  git -C "$t/top" init -q
  ln -s "$t/top" "$t/toplink"
  # From $t, so the relative entry `top` names a real directory, which git
  # ignores all the same.
  cd "$t"
  local -a ceilings=(
    "" "$t/top" "$t/top/" "$t/top/a" "$t/top/a/b" "$t/toplink" ":$t/toplink"
    ":$t/top/" top "/nonexistent:$t/top" "$t:$t/top" "$t/top:$t" / // "$t/top::"
    "$t/to" "$t"
  )
  for c in "${ceilings[@]}"; do
    if GIT_CEILING_DIRECTORIES="$c" git -C "$t/top/a/b" rev-parse --git-dir >/dev/null 2>&1; then
      g=repo
      repo=$((repo + 1))
    else
      g=none
      none=$((none + 1))
    fi
    if GIT_CEILING_DIRECTORIES="$c" git_repo_absent "$t/top/a/b"; then a=none; else a=repo; fi
    [ "$g" = "$a" ] || fail "with GIT_CEILING_DIRECTORIES='$c' git says $g and the reading says $a"
  done
  [ "$none" -gt 0 ] && [ "$repo" -gt 0 ] ||
    fail "git said none $none times and repo $repo times, so the cases reach one answer only"
  # git always looks in the directory it starts in, a ceiling there or not.
  GIT_CEILING_DIRECTORIES="$t/top" git -C "$t/top" rev-parse --git-dir >/dev/null 2>&1 ||
    fail "the control: git did not read the repository from its own top under a ceiling there"
  ! GIT_CEILING_DIRECTORIES="$t/top" git_repo_absent "$t/top" ||
    fail "a ceiling at the directory itself hid its own .git"
  # A ceiling of `/` hides only the root's own .git, which no fixture can make,
  # so git_ceiling's answer for it is asked directly.
  local got
  GIT_CEILING_DIRECTORIES=/ git_ceiling "$t/top/a/b" got
  [ "$got" = / ] || fail "a ceiling of / came back as '$got'"
}

@test "colon_split keeps every entry of a colon list: an empty one, a trailing one, and one holding a newline (0248)" {
  # A `read -r -a` with IFS a colon read one line and dropped a trailing empty
  # field, so a list held a newline only by losing everything after it. Each
  # list's entries are one more than its colons, none holds a colon, and joined
  # at `:` again they are the list.
  local l seps joined e
  local -a got
  local -a lists=("" a "a::b:" ":" "::" "/usr/bin:/odd"$'\n'"dir:/opt" $'a\n:\nb')
  for l in "${lists[@]}"; do
    colon_split "$l" got
    seps="${l//[!:]/}"
    [ "${#got[@]}" -eq "$((${#seps} + 1))" ] ||
      fail "colon_split '$l' gave ${#got[@]} entries for ${#seps} colons: $(printf '[%s]' "${got[@]}")"
    for e in "${got[@]}"; do
      [[ "$e" != *:* ]] || fail "colon_split '$l' gave an entry holding a colon: [$e]"
    done
    joined="$(IFS=:; printf '%s' "${got[*]}")"
    [ "$joined" = "$l" ] || fail "colon_split '$l' joins back as '$joined'"
  done
  colon_split "/usr/bin:/odd"$'\n'"dir:/opt" got
  [ "${got[1]}" = "/odd"$'\n'"dir" ] && [ "${got[2]}" = /opt ] ||
    fail "the entry holding a newline was not kept whole: $(printf '[%s]' "${got[@]}")"
  # An empty name, or one with its own locals' prefix, is refused, not set.
  for l in "" _csp_x _csp_res; do
    run colon_split a:b "$l"
    [ "$status" -eq 1 ] && [[ "$output" == "colon_split: cannot split into '$l'"* ]] ||
      fail "colon_split into '$l' gave status $status and [$output], want 1 and its refusal"
  done
}

@test "git_ceiling reads a ceiling written after an entry holding a newline, as git does (0248)" {
  # git parts GIT_CEILING_DIRECTORIES at `:` alone; the split stopped at the
  # newline, so the ceiling after it was never read, and git_repo_absent read a
  # directory below it as inside a repository, where git finds none.
  local t="$DEVBIN_TEST_TMPDIR/ceilnl" c d top got g a
  mkdir -p "$t/top/a/b"
  git -C "$t/top" init -q
  physical_dir "$t/top/a/b" d getcwd || fail "the fixture's directory cannot be resolved"
  physical_dir "$t/top" top getcwd || fail "the fixture's top cannot be resolved"
  c="$t/odd"$'\n'"dir:$t/top"
  GIT_CEILING_DIRECTORIES="$c" git_ceiling "$d" got
  [ "$got" = "$top" ] || fail "the ceiling after the entry holding a newline came back as '$got', not '$top'"
  if GIT_CEILING_DIRECTORIES="$c" git -C "$t/top/a/b" rev-parse --git-dir >/dev/null 2>&1; then g=repo; else g=none; fi
  if GIT_CEILING_DIRECTORIES="$c" git_repo_absent "$t/top/a/b"; then a=none; else a=repo; fi
  [ "$g" = "$a" ] || fail "with the ceiling after an entry holding a newline git says $g and git_repo_absent says $a"
}

@test "git_repo_absent spells the directory as git does, on a disk that folds case (0185)" {
  # git compares a ceiling, in the case it is typed in, with its working
  # directory as getcwd spells it, in the case it is stored in. bash's own
  # `pwd -P` keeps the typed case, so a ceiling and a directory both typed in
  # another case hid the repository from the reading and not from git, which
  # refuses it under the lever: a refused repository read as none.
  local t="$DEVBIN_TEST_TMPDIR/case" pair c d g a none=0 repo=0
  mkdir -p "$t/top/a/b"
  git -C "$t/top" init -q
  [ -d "$t/TOP" ] || skip "this disk keeps case, so a directory has one spelling"
  for pair in "$t/TOP|$t/TOP/a/b" "$t/top|$t/TOP/a/b" "$t/TOP|$t/top/a/b" "$t/top|$t/top/a/b" "$t/Top/a|$t/tOp/A/b"; do
    c="${pair%%|*}"
    d="${pair#*|}"
    if GIT_CEILING_DIRECTORIES="$c" git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
      g=repo
      repo=$((repo + 1))
    else
      g=none
      none=$((none + 1))
    fi
    if GIT_CEILING_DIRECTORIES="$c" git_repo_absent "$d"; then a=none; else a=repo; fi
    [ "$g" = "$a" ] || fail "ceiling '$c', directory '$d': git says $g and the reading says $a"
  done
  [ "$none" -gt 0 ] && [ "$repo" -gt 0 ] ||
    fail "git said none $none times and repo $repo times, so the cases reach one answer only"
}

@test "is_install_launcher answers the same for Homebrew's bin link typed in another case, in both of a keg's layouts, where the disk folds case (0284)" {
  # bash's `pwd -P` keeps the case a directory is typed in, so a hit under
  # Homebrew's prefix typed in another case resolved to a string that was not
  # the keg's, and its own launcher read as another copy.
  local keg="$HOMEBREW_PREFIX/opt/devbin/libexec" layout
  require_folded_brew_prefix "is_install_launcher with Homebrew's bin in another case"
  brew_keg --stub --linked 0.1.0
  for layout in link script; do
    if [ "$layout" = script ]; then
      brew_keg_env_script 0.1.0 || fail "the fixture's env script failed"
    fi
    is_install_launcher "$HOMEBREW_PREFIX/bin/devbin" "$keg" ||
      fail "the $layout layout: Homebrew's bin link is not the keg's launcher, typed as HOMEBREW_PREFIX"
    is_install_launcher "$FOLDED_PREFIX/bin/devbin" "$keg" ||
      fail "the $layout layout: Homebrew's bin link typed under $FOLDED_PREFIX is not the keg's launcher"
  done
}

@test "git_failure_line gives git's line, and nothing for a call git answers (0185)" {
  # git's own words, read here as the helper is to read them, so the arm holds
  # wherever git words them differently, as at a mount point.
  local t="$DEVBIN_TEST_TMPDIR/gfl" want
  mkdir -p "$t/none" "$t/repo"
  git -C "$t/repo" init -q
  want="$(LC_ALL=C git -C "$t/none" rev-parse --git-dir 2>&1)" || true
  want="${want%%$'\n'*}"
  [ -n "$want" ] || fail "the control: git said nothing of a directory with no repository"
  run git_failure_line "$t/none" rev-parse --git-dir
  assert_success
  [ "$output" = "$want" ] || fail "got: $output"
  run git_failure_line "$t/repo" rev-parse --git-dir
  assert_success
  [ -z "$output" ] || fail "a call git answered gave a line: $output"
}

@test "git_failure_line gives the first of the lines git writes, and only that (0185)" {
  # A refusal is several lines: the cause, then git's advice.
  local t="$DEVBIN_TEST_TMPDIR/gfl" want
  mkdir -p "$t/repo"
  git -C "$t/repo" init -q
  require_git_refusal "$t/repo"
  want="$(LC_ALL=C GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$t/repo" rev-parse --git-dir 2>&1)" || true
  [[ "$want" == *$'\n'* ]] || fail "the control: git's refusal was one line: $want"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run git_failure_line "$t/repo" rev-parse --git-dir
  assert_success
  [ "$output" = "${want%%$'\n'*}" ] || fail "got: $output"
}

@test "git_failure_line gives git's words untranslated where git would translate them (0185)" {
  # A message that matches or shows git's words must not depend on the locale
  # the operator runs in. The control finds a locale this git translates into.
  local t="$DEVBIN_TEST_TMPDIR/gfl" loc want
  mkdir -p "$t/none"
  want="$(LC_ALL=C git -C "$t/none" rev-parse --git-dir 2>&1)" || true
  want="${want%%$'\n'*}"
  for loc in de_DE.UTF-8 fr_FR.UTF-8; do
    [ "$(LC_ALL="$loc" git -C "$t/none" rev-parse --git-dir 2>&1)" != "$want" ] || continue
    LC_ALL="$loc" run git_failure_line "$t/none" rev-parse --git-dir
    [ "$output" = "$want" ] || fail "under $loc: $output"
    return 0
  done
  skip "this git translates its words into neither de_DE nor fr_FR, so the C locale was not shown to matter"
}

@test "git_failure_line --plain asks the index the caller's call read, where git_readonly asks the repository's own (0186)" {
  # git_readonly clears GIT_INDEX_FILE, which a commit hook sets to the index it
  # commits, so a reason asked through it is another index's: here the
  # repository's own, which reads, and so gives no line.
  local t="$DEVBIN_TEST_TMPDIR/gfl"
  mkdir -p "$t/repo"
  git -C "$t/repo" init -q
  : >"$t/cut.index"
  # THE CONTROL: the repository's own index reads.
  env -u GIT_INDEX_FILE git -C "$t/repo" diff --cached --name-only >/dev/null 2>&1 ||
    fail "the control: git could not read the repository's own index"
  GIT_INDEX_FILE="$t/cut.index" run git_failure_line --plain "$t/repo" diff --cached --name-only
  assert_success
  assert_output_contains "index file smaller than expected"
  GIT_INDEX_FILE="$t/cut.index" run git_failure_line "$t/repo" diff --cached --name-only
  assert_success
  [ -z "$output" ] || fail "through git_readonly the reason came from GIT_INDEX_FILE's index: $output"
}

@test "path_expand expands a leading tilde, HOME or XDG base-directory variable and nothing else, naming any other leading tilde or variable form, and xdg_dir reads each XDG variable, its own, only when it is absolute (0243)" {
  local spec home xdg want got rc w wrc wout
  # <xdg> sets all four XDG variables at once: `set` to four distinct absolute
  # directories, so a variable read for another's would show; `rel` to a
  # relative path, which the XDG spec ignores; `unset` to empty. A want of
  # `!<rc> <text>` is a refusal: path_expand's rc, and what it printed.
  while IFS='|' read -r spec home xdg want; do
    [ -n "$spec" ] || continue
    rc=0
    case "$xdg" in
      set) got="$(HOME="$home" XDG_STATE_HOME=/x/state XDG_DATA_HOME=/x/data XDG_CONFIG_HOME=/x/config XDG_CACHE_HOME=/x/cache path_expand "$spec")" || rc=$? ;;
      rel) got="$(HOME="$home" XDG_STATE_HOME=rel XDG_DATA_HOME=rel XDG_CONFIG_HOME=rel XDG_CACHE_HOME=rel path_expand "$spec")" || rc=$? ;;
      *) got="$(HOME="$home" XDG_STATE_HOME='' XDG_DATA_HOME='' XDG_CONFIG_HOME='' XDG_CACHE_HOME='' path_expand "$spec")" || rc=$? ;;
    esac
    case "$want" in
      '!'*)
        w="${want#!}"
        wrc="${w%% *}" wout="${w#* }"
        [ "$rc" -eq "$wrc" ] && [ "$got" = "$wout" ] || fail "$spec, HOME=$home, XDG $xdg: rc $rc and [$got], want rc $wrc naming [$wout]"
        ;;
      *)
        [ "$rc" -eq 0 ] && [ "$got" = "$want" ] || fail "$spec, HOME=$home, XDG $xdg: rc $rc and [$got], want [$want]"
        ;;
    esac
  done <<'EOF2'
~|/h/me|unset|/h/me
~/x|/h/me|unset|/h/me/x
$HOME|/h/me|unset|/h/me
$HOME/x|/h/me|unset|/h/me/x
${HOME}/x|/h/me/|unset|/h/me/x
${XDG_STATE_HOME}/m|/h/me|set|/x/state/m
${XDG_DATA_HOME}/m|/h/me|set|/x/data/m
${XDG_CONFIG_HOME}/m|/h/me|set|/x/config/m
$XDG_CACHE_HOME/m|/h/me|set|/x/cache/m
${XDG_STATE_HOME}/m|/h/me|rel|/h/me/.local/state/m
${XDG_DATA_HOME}/m|/h/me|unset|/h/me/.local/share/m
$XDG_CONFIG_HOME/c|/h/me|unset|/h/me/.config/c
${XDG_CACHE_HOME}/m|/h/me|unset|/h/me/.cache/m
opt/app/VERSION|/h/me|unset|opt/app/VERSION
/abs/x|/h/me|unset|/abs/x
x/$HOME|/h/me|unset|x/$HOME
~user/x|/h/me|unset|!2 ~user
~x|/h/me|unset|!2 ~x
$FOO/x|/h/me|unset|!2 $FOO
${FOO}/x|/h/me|unset|!2 ${FOO}
$HOMEX/x|/h/me|unset|!2 $HOMEX
$HOME.d/x|/h/me|unset|!2 $HOME.d
${HOME}x/y|/h/me|unset|!2 ${HOME}x
${XDG_STATE_HOME:-$HOME/.local/state}/m|/h/me|unset|!2 ${XDG_STATE_HOME:-$HOME/.local/state}
${X|/h/me|unset|!2 ${X
$1/x|/h/me|unset|!2 $1
~/x|rel|unset|!1 HOME
~|/|unset|!1 HOME
$HOME/x|/|unset|!1 HOME
${XDG_DATA_HOME}/d||unset|!1 HOME
EOF2
  local word var dflt
  local -a wvd
  for w in state:XDG_STATE_HOME:.local/state data:XDG_DATA_HOME:.local/share config:XDG_CONFIG_HOME:.config cache:XDG_CACHE_HOME:.cache; do
    colon_split "$w" wvd
    word="${wvd[0]}" var="${wvd[1]}" dflt="${wvd[2]}"
    got="$(HOME=/h/me XDG_STATE_HOME=/x/state XDG_DATA_HOME=/x/data XDG_CONFIG_HOME=/x/config XDG_CACHE_HOME=/x/cache xdg_dir "$word")" || fail "xdg_dir $word failed with every XDG variable set"
    [ "$got" = "/x/$word" ] || fail "xdg_dir $word with every XDG variable set: [$got], want /x/$word, $var's own"
    got="$(HOME=/h/me XDG_STATE_HOME=rel XDG_DATA_HOME=rel XDG_CONFIG_HOME=rel XDG_CACHE_HOME=rel xdg_dir "$word")" || fail "xdg_dir $word failed with each XDG variable relative"
    [ "$got" = "/h/me/$dflt" ] || fail "xdg_dir $word with $var relative: [$got], want its default /h/me/$dflt"
    rc=0
    got="$(HOME=rel XDG_STATE_HOME='' XDG_DATA_HOME='' XDG_CONFIG_HOME='' XDG_CACHE_HOME='' xdg_dir "$word")" || rc=$?
    [ "$rc" -eq 1 ] && [ -z "$got" ] || fail "xdg_dir $word with $var unset and no absolute HOME: rc $rc and [$got], want rc 1 and nothing"
  done
  rc=0
  xdg_dir bogus >/dev/null || rc=$?
  [ "$rc" -eq 2 ] || fail "xdg_dir took a word that names no XDG directory: rc $rc"
}

# ---------------------------------------------------------------------------
# ST0011 WP03: IS_COMMIT_SHA'S FULL FORM, THE ONE WHOLE-NAME CHECK
#
# The whole names are read off real repositories, one of each object format, so
# no length is written here: a near miss is a whole name one character short or
# one long, and the default form still takes the short one.

@test "is_commit_sha full takes a whole object name alone, sha1 or sha256, and the default form is unchanged (ST0011 WP03)" {
  local f w sha1 sha256
  for f in sha1 sha256; do
    git init -q --object-format="$f" "$DEVBIN_TEST_TMPDIR/$f"
  done
  sha1="$(git -C "$DEVBIN_TEST_TMPDIR/sha1" hash-object --stdin <<<x)"
  sha256="$(git -C "$DEVBIN_TEST_TMPDIR/sha256" hash-object --stdin <<<x)"
  # `! cmd` never trips errexit, so each refusal is asserted rather than negated.
  for w in "$sha1" "$sha256"; do
    is_commit_sha "$w" full || fail "the whole name $w was refused"
  done
  for w in "${sha1%?}" "${sha256%?}" "${sha1}0" "${sha256}0" "${sha1^^}" ""; do
    if is_commit_sha "$w" full; then fail "'$w' was taken as a whole name"; fi
  done
  is_commit_sha "${sha1%?}" || fail "the default form refused ${sha1%?}"
  # A form it does not know stops the caller rather than answering, whatever
  # the word: an empty one too, which the charset test would refuse first if
  # the form were read second. In a shell of its own, as the die arm runs, so a
  # stop and an answer read differently.
  run bash -c "set -euo pipefail
    . '$DEVBIN_LIB_DIR/helpers'
    is_commit_sha '' whole || echo answered"
  assert_exit_code 1
  assert_output_contains "is_commit_sha: no form 'whole'"
  refute_output_contains "answered"
}

@test "is_branch_name and is_tag_name pass back git's own word on a ref name, and platform_word_of maps an OS name to its platform word, the one map platform_word reads through (ST0011 WP-02c)" {
  local w
  # `! cmd` never trips errexit, so each refusal is asserted rather than negated.
  for w in main candidate/v1.0.1 release-1.2; do
    is_branch_name "$w" || fail "the branch name $w was refused"
    is_tag_name "$w" || fail "the tag name $w was refused"
  done
  for w in "two words" "a..b" "x[skip ci]" "trailing/" "a.lock"; do
    if is_branch_name "$w"; then fail "'$w' was taken as a branch name"; fi
    if is_tag_name "$w"; then fail "'$w' was taken as a tag name"; fi
  done
  # A name that opens with a dash, which check-ref-format takes as a ref, is one
  # git tag reads as an option.
  if is_tag_name -v1.0.1; then fail "'-v1.0.1' was taken as a tag name"; fi
  [ "$(platform_word_of Darwin)" = macos ] || fail "Darwin did not map to macos"
  [ "$(platform_word_of Linux)" = linux ] || fail "Linux did not map to linux"
  if platform_word_of FreeBSD >/dev/null; then fail "an OS with no word answered one"; fi
  # platform_word reads this host's OS name through the same map.
  [ "$(platform_word)" = "$(platform_word_of "$(uname -s)")" ] ||
    fail "platform_word and platform_word_of disagree about this host"
}
