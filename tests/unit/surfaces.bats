#!/usr/bin/env bats
# surfaces.bats - the command-level rig and the surface commands (WP-14)
#
# The thing under test here is a level of the rig that was missing rather than
# wrong. The rig wired config's declarative `run:` for OPTIONS and left the
# command-level `run:` unwired: `command_active` counted it as making a command
# active, help listed it, and asking for it printed "not built yet". That is the
# exact shape config.reference.yaml documents, so a project following the
# reference got a command that resolved and refused to run.
#
# Surfaces (`iex`, `server`, `cli`, `repl`) are the commands that have a command
# line and no options, which is why the gap surfaced with them and not earlier.
#
# The other claim held down here is EXEC. A launcher has to be the process the
# terminal is talking to, not a process under a wrapper, and the difference is
# invisible until someone hits Ctrl-C.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  init_colors off
}
teardown() { devbin_teardown; }


# Put a fake executable on PATH so a surface can be proven to run without the
# real toolchain being present. Prints the bin dir to prepend.
fakebin() {
  local proj="$1" name="$2" body="${3:-}"
  mkdir -p "$proj/fakebin"
  if [ -n "$body" ]; then
    printf '%s\n' "$body" >"$proj/fakebin/$name"
  else
    printf '#!/bin/sh\necho "ran:%s args=$*"\n' "$name" >"$proj/fakebin/$name"
  fi
  chmod +x "$proj/fakebin/$name"
  echo "$proj/fakebin"
}

# ============================================================================
# THE COMMAND-LEVEL RIG (AC-14.1, AC-14.4, AC-14.5)
# ============================================================================

@test "a command-level run: declared in config actually runs" {
  # The regression that started WP-14. Before run_command existed this printed
  # "not built yet" and exited 3, for config the reference file documents.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  greet:
    summary: Say hello
    run: echo hello-from-declared-run
YAML
  )"
  run devbin_run "$proj" greet
  assert_success
  assert_output_contains "hello-from-declared-run"
}

@test "a command with neither run: nor handler nor catalogue default refuses with exit 3, not a lie" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # `build` is a built-in NAME that deliberately ships no command line. It
  # must resolve and refuse rather than succeed -- and since issue
  # 0111 it says what makes it run instead of calling itself "not built yet",
  # which it never was: the project declares build, devbin does not.
  run devbin_run "$proj" build
  assert_exit_code 3
  assert_output_contains "resolves, but nothing here runs it"
  assert_output_contains "commands.build.run"
  refute_output_contains "not built yet"
}

@test "config's own run: beats the catalogue default for the same command" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  iex:
    run: echo project-iex
YAML
  )"
  # The catalogue ships `iex -S mix`. A project that says otherwise wins: config
  # is more specific than anything devbin ships (the run_option order, one
  # level up).
  run devbin_run "$proj" iex
  assert_success
  assert_output_contains "project-iex"
  refute_output_contains "-S mix"
}

@test "a project handler beats a command-level run:" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  greet:
    summary: Say hello
    run: echo from-config
YAML
  )"
  create_test_command "$proj" greet >/dev/null
  run devbin_run "$proj" greet
  assert_success
  assert_output_contains "ran:greet"
  refute_output_contains "from-config"
}

@test "a command declaring log: seals through the same runner a gate uses" {
  # The options rule, one level up: `log:` is what makes something a sealed gate,
  # whether it is declared on an option or on the command itself.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  audit:
    summary: A command-level gate
    run: echo audit-ran
    log: AUDIT
    grammar: generic
YAML
  )"
  run devbin_run "$proj" audit
  assert_success
  assert_output_contains "verdict:"
  # The seal is a FILE, and its .errors companion is empty exactly when the run
  # was green.
  local errors
  errors="$(find "$proj/tmp/audit" -name '*.AUDIT.errors')" || fail "could not list $proj/tmp/audit"
  errors="${errors%%$'\n'*}"
  [ -n "$errors" ] || fail "no sealed companion was written"
  assert_file_empty "$errors"
}

@test "a command with no log: runs bare, so a launcher is never teed" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  launch:
    summary: A launcher
    run: echo launched
YAML
  )"
  run devbin_run "$proj" launch
  assert_success
  assert_output_contains "launched"
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp/launch"
}

# ============================================================================
# EXEC: A LAUNCHER IS THE PROCESS (AC-14.6)
# ============================================================================

@test "a launcher replaces the dispatcher process rather than running beneath it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  launch:
    summary: A launcher
    run: ./launcher
YAML
  )"
  # Writes its OWN pid. A fresh process, so $$ is genuinely its own -- unlike a
  # subshell, which inherits its parent's $$ and would prove nothing (the same
  # trap that made the first fix for the concurrent-log hazard wrong).
  cat >"$proj/launcher" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >"./launched.pid"
SH
  chmod +x "$proj/launcher"

  # NOT devbin_run here: this arm compares PIDS, and the helper's subshell adds a
  # process level -- which is the very trap the comment above names. The test
  # stands in the project itself so the dispatcher is a direct child.
  cd "$proj"
  ./bin/devbin launch &
  dispatcher=$!
  wait "$dispatcher"

  # exec means the launcher IS the process the dispatcher was. Run it beneath
  # the dispatcher instead and these differ -- which is the difference between
  # the terminal talking to the REPL and talking to a wrapper around it.
  [ -f "$proj/launched.pid" ] || fail "the launcher did not run at the project root"
  [ "$(cat "$proj/launched.pid")" = "$dispatcher" ] ||
    fail "launcher pid $(cat "$proj/launched.pid") != dispatcher pid $dispatcher -- it ran beneath the dispatcher rather than replacing it"
}

# ============================================================================
# COMMAND ROWS LIVE IN THE ONE CATALOGUE (AC-14.2, AC-14.3)
# ============================================================================

@test "the catalogue answers a dotless COMMAND row" {
  [ "$(builtin_command_lang iex)" = "elixir" ]
  [ "$(builtin_command_run iex)" = "iex -S mix" ]
  [ "$(builtin_command_summary iex)" = "Interactive Elixir shell with the project loaded" ]
}

@test "a command row is never reported as an option" {
  # builtin_options_for filters on `<cmd>.`, so the dotless rows must not leak
  # into any option list. `iex` has only a command row; `check` has both kinds.
  run builtin_options_for iex
  assert_success
  [ -z "$output" ]

  run builtin_options_for check
  assert_success
  assert_output_contains "compile"
  refute_output_matches '(^|'$'\n'')check$'
}

@test "a catalogue row is a gate or it is not, never half of one" {
  # grammar and suffix are both real or both `-`. Half a seal is a row that
  # would name an .errors companion it never writes, or write one under a name
  # nothing looks for.
  local bad="" name lang grammar suffix rest
  while read -r name lang grammar suffix rest; do
    [ -n "$name" ] || continue
    if [ "$grammar" = "-" ] && [ "$suffix" != "-" ]; then bad="$bad $name"; fi
    if [ "$grammar" != "-" ] && [ "$suffix" = "-" ]; then bad="$bad $name"; fi
  done <<EOF
$_DEVBIN_BUILTIN_CATALOGUE
EOF
  [ -z "$bad" ] || fail "catalogue rows carrying half a seal:$bad"
}

@test "builtin_has_default_run distinguishes a shipped command line from a tier-4 dash" {
  builtin_has_default_run iex || fail "iex ships a command line"
  ! builtin_has_default_run build || fail "build deliberately ships none"
  ! builtin_has_default_run nosuchcommand || fail "an absent row ships none either"
}

# ============================================================================
# THE SURFACES THEMSELVES (AC-14.7, AC-14.12)
# ============================================================================

@test "iex runs from the catalogue alone, with nothing declared in config" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" iex)"
  PATH="$bin:$PATH" run devbin_run "$proj" iex
  assert_success
  # Byte-identical across all four corpus projects: `exec iex -S mix "$@"`.
  assert_output_contains "ran:iex args=-S mix"
}

@test "iex passes its arguments through to the shell" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" iex)"
  PATH="$bin:$PATH" run devbin_run "$proj" iex --name node@host
  assert_success
  assert_output_contains "args=-S mix --name node@host"
}

@test "a surface is not offered to a project whose language does not declare it" {
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
YAML
  )"
  # `iex` is an elixir row. In a shell project it must not run at all.
  #
  # The fake `iex` on PATH is the point of this test rather than a convenience.
  # Without it the first version of this test passed while the scoping was
  # BROKEN: the real `iex` ran, failed with a mix error about a missing mix.exs,
  # and the non-zero exit read as a refusal. Put something on PATH that succeeds
  # loudly and the test can tell "devbin declined" from "the thing devbin should
  # not have run happened to fail".
  local bin
  bin="$(fakebin "$proj" iex)"
  PATH="$bin:$PATH" run devbin_run "$proj" iex
  assert_failure
  refute_output_contains "ran:iex"
  # And the refusal SAYS why. Language scoping's whole point is that
  # deactivation is visible: "unknown command: iex" reads as a typo when the
  # truth is that iex is Elixir's and this project is not.
  assert_output_contains "does not declare the 'elixir' language"
}

@test "built-in commands carry a summary in help rather than a blank column" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Every built-in showed an empty description column before the generated
  # listing consulted the catalogue for command rows the way it already did for
  # option rows.
  assert_output_contains "Interactive Elixir shell with the project loaded"
  assert_output_contains "Build this project's targets"
  refute_output_matches '(^|'$'\n'')  iex +$'
}

# ============================================================================
# FRAMEWORK-OWNED OPTIONS -- AC-14.10, AC-14.11
# ============================================================================

@test "a framework option exports DEVBIN_OPT_ with nothing declared in config" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  create_test_command "$proj" server '#!/usr/bin/env bash
printf "IEX=%s\n" "${DEVBIN_OPT_IEX:-unset}"' >/dev/null

  # The project declares no `options:` block at all. `--iex` still parses, and
  # the command that consumes it reads it -- which is the whole of the
  # framework-option rule. Here that is a project handler standing in for
  # devbin's server, as below.
  #
  # `languages: [elixir]` is about a DIFFERENT axis and is load-bearing: a
  # framework option is offered where the commands consuming it are (AC-14.16,
  # issue 0001). What this test asserts is that no `options:` ENTRY is needed,
  # which is the claim the rule actually makes.
  #
  # The command is `server` rather than an arbitrary handler because issue 0009
  # scoped the flag to the commands that read it, and `server` is devbin's own
  # consumer. A project handler stands in for devbin's server and reads the
  # canonical name as devbin's does, which keeps the claim under test
  # exactly what it says -- no `options:` entry. It was a command-level `run:`
  # until 0128, which stopped counting such a line as devbin's consumer: devbin
  # execs it as written and cannot know that it reads the flag. So this arm is
  # also the control for the run:-owned --iex arms (0128), in the shape real
  # projects use: they run `server` from a handler.
  run devbin_run "$proj" server --iex
  assert_success
  assert_output_contains "IEX=true"

  run devbin_run "$proj" server
  assert_success
  assert_output_contains "IEX=unset"
}

@test "a project's own export still fires, alongside devbin's canonical name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    flag: true
    export: MYAPP_IEX
commands:
  show:
    summary: Report both names
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'project=%s devbin=%s\n' "${MYAPP_IEX:-unset}" "${DEVBIN_OPT_IEX:-unset}"
SH
  chmod +x "$proj/show"

  # One parse, one value, two names out. This is what lets a migrated project's
  # existing handlers go on reading the name they already expect -- nothing has
  # to be renamed for devbin's own built-ins to work.
  run devbin_run "$proj" show --iex
  assert_success
  assert_output_contains "project=true devbin=true"
}

@test "a framework option is not passed through to the handler as an argument" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  create_test_command "$proj" server '#!/usr/bin/env bash
printf "args=[%s]\n" "$*"' >/dev/null

  # It is consumed like any declared shared option: the handler gets what devbin
  # did not recognise, so an undeclared flag still reaches the tool. `server`
  # because issue 0009 scoped the flag to its consumers, from a project handler
  # because a command-level `run:` is not one since 0128.
  run devbin_run "$proj" server --iex --trace
  assert_success
  assert_output_contains "args=[--trace]"
}

@test "an undeclared shared option is still refused a value it does not have" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - dev
      - test
    export: MIX_ENV
commands:
  show:
    summary: Report
    run: ./show
YAML
  )"
  printf '#!/usr/bin/env bash\ntrue\n' >"$proj/show"
  chmod +x "$proj/show"
  # Framework options must not have loosened validation for ordinary declared
  # options.
  run devbin_run "$proj" show --env nope
  assert_failure
  assert_output_contains "expected"
}

# ============================================================================
# SERVER (AC-14.10)
# ============================================================================

@test "server runs the plain command line, and the iex one under --iex" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" iex >/dev/null

  PATH="$bin:$PATH" run devbin_run "$proj" server
  assert_success
  assert_output_contains "ran:mix args=phx.server"

  PATH="$bin:$PATH" run devbin_run "$proj" server --iex
  assert_success
  # The iex form, not the plain form with something prepended: a framework
  # option SELECTS a command line.
  assert_output_contains "ran:iex args=-S mix phx.server"
}

@test "0066: server reads an iex value of yes or 1 as true, like every other flag" {
  # lib/cmd/server compared to the literal `true`, so a project declaring
  # `options.iex.value: yes` got the plain command line under --iex, silently.
  local v bin
  for v in yes 1; do
    proj="$(printf 'project:\n  name: demo%s\n  languages:\n    - elixir\noptions:\n  iex:\n    flag: true\n    value: %s\n' "$v" "$v" | mkproj "demo$v")"
    bin="$(fakebin "$proj" mix)"
    fakebin "$proj" iex >/dev/null
    PATH="$bin:$PATH" run devbin_run "$proj" server --iex
    assert_success
    assert_output_contains "ran:iex args=-S mix phx.server"
  done
}

@test "a project's declared run: beats devbin's own lib/cmd handler" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  server:
    summary: Ours
    run: echo our-own-server
YAML
  )"
  # The ordering that bit run_option at the option level: devbin's own handler
  # must not swallow something config plainly declares. lib/cmd/server exists,
  # and config still wins.
  run devbin_run "$proj" server
  assert_success
  assert_output_contains "our-own-server"
  refute_output_contains "phx.server"
}

@test "a project handler still shadows devbin's own lib/cmd handler" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  create_test_command "$proj" server >/dev/null
  run devbin_run "$proj" server
  assert_success
  assert_output_contains "ran:server"
  refute_output_contains "phx.server"
}

# ============================================================================
# CLI AND REPL (AC-14.8, AC-14.9)
# ============================================================================

@test "cli composes its command line from the project name" {
  proj="$(mkproj chatapp <<'YAML'
project:
  name: chatapp
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" cli join --room 4
  assert_success
  # `mix chatapp.cli`, exactly as the corpus does it -- and composed from
  # project.name rather than the catalogue gaining template substitution.
  assert_output_contains "ran:mix args=chatapp.cli join --room 4"
}

@test "cli follows the project name rather than the directory or the file" {
  proj="$(mkproj somedir <<'YAML'
project:
  name: webapp
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" cli
  assert_success
  # Identity comes from config, never from $0 or the directory.
  assert_output_contains "ran:mix args=webapp.cli"
}

@test "every built-in devbin ships with no options answers all for itself, and none writes anything (0128)" {
  # devbin synthesises `all` only where there are options to sweep, and a
  # built-in devbin ships with none answers the word for itself.
  # Its program is handed it (server, iex, cli, repl); a name devbin ships with
  # nothing behind it refuses it as it refuses a bare run, exit 3; and devbin's
  # own handlers refuse it in their own words, exit 1. (A command-level `run:`
  # with no options is refused by devbin, exit 1 -- dispatch.bats.) The
  # population is the catalogue's, so a built-in added without a row here
  # fails this arm, and a row for a built-in that went fails it too.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - rust
commands:
  content:
    enabled: true
  macos:
    enabled: true
  formula:
    enabled: true
  precommit:
    enabled: true
  publish:
    enabled: true
  which:
    enabled: true
  release:
    enabled: true
YAML
  )"
  local bin cmds c code text rows="" bad="" written
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" iex >/dev/null
  fakebin "$proj" rlwrap >/dev/null
  cmds="$(fixture_run "$proj" 'for c in $(builtin_commands); do [ -n "$(builtin_options_for "$c")" ] || echo "$c"; done')" ||
    fail "the catalogue could not be listed"
  [ -n "$cmds" ] || fail "the catalogue lists no option-less built-in -- this arm has no population"
  touch "$BATS_TEST_TMPDIR/before"
  sleep 1
  # THE INSTRUMENT, proven: a directory made, a file renamed and a link made
  # after the marker, in a canary beside the project, are each seen. A file's
  # own mtime alone would miss all three (its ctime or its parent's moves).
  mkdir -p "$BATS_TEST_TMPDIR/canary"
  : >"$BATS_TEST_TMPDIR/canary/f"
  mv "$BATS_TEST_TMPDIR/canary/f" "$BATS_TEST_TMPDIR/canary/g"
  ln -s g "$BATS_TEST_TMPDIR/canary/h"
  [ -n "$(find "$BATS_TEST_TMPDIR/canary" \( -newer "$BATS_TEST_TMPDIR/before" -o -cnewer "$BATS_TEST_TMPDIR/before" \) -print)" ] ||
    fail "find cannot see a write made after the marker -- the nothing-written check below would be vacuous"
  while IFS='|' read -r c code text; do
    [ -n "$c" ] || continue
    rows="$rows $c"
    grep -qx -- "$c" <<<"$cmds" || {
      bad="$bad [$c: a row for a built-in the catalogue does not ship with no options]"
      continue
    }
    PATH="$bin:$PATH" run devbin_run "$proj" "$c" all
    [ "$status" = "$code" ] || bad="$bad [$c all: exit $status, want $code]"
    case "$output" in
      *"$text"*) ;;
      *) bad="$bad [$c all: output lacks '$text']" ;;
    esac
  done <<'ROWS'
server|0|ran:mix args=phx.server all
iex|0|ran:iex args=-S mix all
cli|0|ran:mix args=demo.cli all
repl|0|mix demo.cli repl all
build|3|resolves, but nothing here runs it
worktrees|2|is not a git checkout, so it has no linked worktrees to report
precommit|3|resolves, but nothing here runs it
content|3|resolves, but nothing here runs it
publish|3|resolves, but nothing here runs it
macos|1|macos: unknown subcommand 'all'
formula|1|formula has no verb 'all'
ci-state|1|'all' is not a full commit sha
cache|7|'all' is not a cache verb
which|3|resolves, but nothing here runs it
fullcycle|1|fullcycle: unknown argument 'all'
dormancy|1|dormancy: unknown argument 'all'
version|1|unknown version sub-command: all
release|1|usage: bin/devbin release
infra|1|infra: unknown verb `all`
install|1|unexpected argument 'all'
upgrade|1|unexpected argument 'all'
vendor|1|unexpected argument 'all'
doctor|1|unknown argument 'all'
new|1|'all' is reserved
devbin|1|usage: bin/devbin devbin
shell-init|1|shell-init: no body for 'all'
use|6|devbin use chooses which devbin this machine runs
ROWS
  for c in $cmds; do
    case " $rows " in
      *" $c "*) ;;
      *) bad="$bad [$c: an option-less built-in with no row here]" ;;
    esac
  done
  # Anything made, changed, renamed, removed from or linked under the project,
  # directories included: -cnewer sees what -newer on a file's own mtime cannot.
  written="$(find "$proj" \( -newer "$BATS_TEST_TMPDIR/before" -o -cnewer "$BATS_TEST_TMPDIR/before" \) -print)"
  [ -z "$written" ] || bad="$bad [files written: $written]"
  [ -z "$bad" ] || fail "an option-less built-in answered all wrongly:$bad"
}

@test "repl wraps the cli repl task in rlwrap when rlwrap is present" {
  proj="$(mkproj webapp <<'YAML'
project:
  name: webapp
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" rlwrap)"
  fakebin "$proj" mix >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" repl
  assert_success
  assert_output_contains "ran:rlwrap"
  assert_output_contains "mix webapp.cli repl"
  # History defaults under $HOME, named for the project.
  assert_output_contains ".webapp_repl_history"
}

@test "repl still starts when rlwrap is absent, and says what was lost" {
  proj="$(mkproj webapp <<'YAML'
project:
  name: webapp
  languages:
    - elixir
YAML
  )"
  # A PATH with mix but deliberately no rlwrap. Refusing to start a REPL
  # because history is unavailable would be an outage in place of an
  # inconvenience.
  local bin
  bin="$(fakebin "$proj" mix)"
  # The narrowed PATH must still carry a bash >= 5, or `env bash` resolves to
  # /bin/bash 3.2 and the dispatcher's floor guard (issue 0022) refuses before
  # repl runs -- which is the guard working, not the property under test.
  ln -s "$(command -v bash)" "$bin/bash"
  PATH="$bin:/usr/bin:/bin" run devbin_run "$proj" repl
  assert_success
  assert_output_contains "rlwrap not found"
  assert_output_contains "ran:mix args=webapp.cli repl"
}

@test "repl honours a project-specific history override" {
  proj="$(mkproj webapp <<'YAML'
project:
  name: webapp
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" rlwrap)"
  fakebin "$proj" mix >/dev/null
  WEBAPP_REPL_HISTORY="/tmp/custom-history" PATH="$bin:$PATH" \
    run devbin_run "$proj" repl
  assert_success
  assert_output_contains "/tmp/custom-history"
  refute_output_contains ".webapp_repl_history"
}

@test "config's own summary still overrides the catalogue's wording" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  iex:
    summary: Our shell, our words
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Our shell, our words"
  refute_output_contains "Interactive Elixir shell with the project loaded"
}

# ============================================================================
# FRAMEWORK OPTION CONSUMERS (issue 0009)
# ============================================================================
#
# `--iex` selects a server's IEx form. It is NOT a general "run this in IEx"
# modifier: running `cli` or `repl` under it makes no sense, and offering it
# where nothing reads it is the false green at the flag level.
#
# Issue 0001 wired the OFFER to the declared language, because at the time
# every elixir project in the corpus enabled `server`, so "speaks elixir" and
# "has something that reads the flag" picked the same set. lib/resolve said so
# in as many words. A library has no server, and that is where the two came
# apart.

@test "a framework option is NOT offered when its consuming command is disabled" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  server:
    enabled: false
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Two consumers' shape: elixir is spoken, so the language
  # test passes, and `server` -- the only thing in devbin that reads
  # DEVBIN_OPT_IEX -- is switched off. Language is a PROXY for the consumer set
  # and this is where the proxy fails.
  refute_output_contains "--iex"
}

@test "a framework option IS offered when its consuming command is active" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "--iex"
}

@test "a framework option given to a command that cannot read it is REFUSED" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # The heart of issue 0009. This was accepted, exported and ignored -- which
  # is how ST0002 WP-02 recorded `cli --iex` as the replacement for a script it
  # then deleted. Silence is what let a wrong disposition look like a working
  # one, so the flag has to say no.
  run ! devbin_run "$proj" cli --iex
  assert_exit_code 2
  assert_output_contains "--iex"
  assert_output_contains "server"
}

@test "the refusal names the consumers, so the message is actionable" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  run ! devbin_run "$proj" repl --iex
  assert_exit_code 2
  # A remediation string is a code path with a user's trust attached: telling
  # the reader WHICH command takes the flag is the difference between a refusal
  # and a dead end.
  assert_output_contains "applies to"
}

@test "a project extends the consumer set for its own handler" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    commands:
      - show
commands:
  show:
    summary: Report the flag
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'IEX=%s\n' "${DEVBIN_OPT_IEX:-unset}"
SH
  chmod +x "$proj/show"

  # A consumer's own handler is the real case: a PROJECT handler that reads
  # DEVBIN_OPT_IEX and picks a different command line for it. Devbin cannot
  # know that by looking, so the project says so -- the name-only discipline,
  # ship the rig and let the project name its own target.
  run devbin_run "$proj" show --iex
  assert_success
  assert_output_contains "IEX=true"
}

@test "declaring consumers does not turn the flag into a valued option" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    commands:
      - show
commands:
  show:
    summary: Report the flag
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'IEX=%s args=%s\n' "${DEVBIN_OPT_IEX:-unset}" "$*"
SH
  chmod +x "$proj/show"

  # `commands:` extends the CONSUMER SET and says nothing about SHAPE. Config
  # wins on shape only where it declares shape -- otherwise the mere presence
  # of an `options.iex:` entry would flip a framework flag into an option that
  # demands a value, and `--iex` would start eating the next argument.
  run devbin_run "$proj" show --iex keep-me
  assert_success
  assert_output_contains "IEX=true args=keep-me"
}

@test "an explicit consumer list scopes even when config also declares shape" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    flag: true
    export: DEMO_IEX
    commands:
      - show
commands:
  show:
    summary: Report the flag
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'IEX=%s\n' "${DEVBIN_OPT_IEX:-unset}"
SH
  chmod +x "$proj/show"

  # Declaring shape normally hands devbin's hands-off rule the option: the
  # project owns it, so devbin does not police which commands see it. `commands:`
  # is an explicit request to be scoped, and it has to win over that -- otherwise
  # the one config that asks for both gets a key that silently does nothing,
  # which is the failure this issue exists to remove.
  run devbin_run "$proj" show --iex
  assert_success
  assert_output_contains "IEX=true"

  run ! devbin_run "$proj" cli --iex
  assert_exit_code 2
  assert_output_contains "applies to"
}

@test "--iex over a server the project's run: owns is not devbin's: the line gets it as an argument, and help does not offer it (0128)" {
  # devbin's consumer reads the flag through devbin's implementation, or
  # through a project HANDLER, which may read DEVBIN_OPT_IEX. A run: line
  # is exec'd as written and reads nothing devbin knows of, so until 0128 the
  # flag was accepted, exported and dropped here at exit 0.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  server:
    run: ./srv
YAML
  )"
  printf '#!/usr/bin/env bash\nprintf "args=%%s IEX=%%s\\n" "$*" "${DEVBIN_OPT_IEX:-unset}"\n' >"$proj/srv"
  chmod +x "$proj/srv"

  run devbin_run "$proj" server --iex
  assert_success
  assert_output_contains "args=--iex IEX=unset"

  run devbin_run "$proj" help
  assert_success
  refute_output_contains "--iex"
}

@test "--iex over a run:-owned server is refused as for any non-reader when another command reads the flag (0128)" {
  # Not counted as a reader, server is treated as cli is under --iex: with
  # nothing else reading the flag it reaches the line as an argument (the arm
  # above), and with something else reading it, it is refused, exit 2.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    commands:
      - show
commands:
  show:
    run: ./show
  server:
    run: ./srv
YAML
  )"
  printf '#!/usr/bin/env bash\nprintf "IEX=%%s\\n" "${DEVBIN_OPT_IEX:-unset}"\n' >"$proj/show"
  printf '#!/usr/bin/env bash\nprintf "args=%%s\\n" "$*"\n' >"$proj/srv"
  chmod +x "$proj/show" "$proj/srv"
  run devbin_run "$proj" server --iex
  assert_exit_code 2
  assert_output_contains "--iex applies to: show"
  refute_output_contains "args="

  # The control: the command the project named takes it.
  run devbin_run "$proj" show --iex
  assert_success
  assert_output_contains "IEX=true"
}

@test "listing server under options.iex.commands says its run: line reads the flag, and devbin takes it again (0128)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    commands:
      - server
commands:
  server:
    run: ./srv
YAML
  )"
  printf '#!/usr/bin/env bash\nprintf "args=%%s IEX=%%s\\n" "$*" "${DEVBIN_OPT_IEX:-unset}"\n' >"$proj/srv"
  chmod +x "$proj/srv"

  run devbin_run "$proj" server --iex
  assert_success
  assert_output_contains "args= IEX=true"
}

# ============================================================================
# THE CLI TASK NAME (ST0002 WP-03) -- when it is not <name>.cli
# ============================================================================
#
# `cli` and `repl` both compose `mix <name>.cli`, which held for every early
# corpus project because each one's mix task was named after it. A package
# pair breaks it: <family>_config's task is `<family>.config` and <family>_cli's is
# `<family>.cli`, neither of which is `<name>.cli`.
#
# For `cli` a project can declare `run:` and be done -- <family>_config did. `repl`
# cannot: its built-in carries the rlwrap wiring (history, completions, the
# degrade-with-a-warning path), and a `run:` override throws all of that away to
# change one word. So the TASK becomes config, and both built-ins read it.

@test "the cli task defaults to <name>.cli when config says nothing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" cli
  assert_success
  # Every project whose task is named after it rides this default and must keep
  # riding it.
  assert_output_contains "ran:mix args=demo.cli"
}

@test "a project whose mix task is not <name>.cli names it in config" {
  proj="$(mkproj acme_cli <<'YAML'
project:
  name: acme_cli
  cli_task: acme.cli
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" cli status
  assert_success
  # NOT acme_cli.cli, which is what the derivation would have produced and
  # which is not a task in that project at all.
  assert_output_contains "ran:mix args=acme.cli status"
}

@test "repl uses the declared cli task, and keeps rlwrap" {
  proj="$(mkproj acme_cli <<'YAML'
project:
  name: acme_cli
  cli_task: acme.cli
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" rlwrap)"
  fakebin "$proj" mix >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" repl
  assert_success
  # The point of the config key rather than a `run:` override: the task name
  # changes and the rlwrap wiring survives.
  assert_output_contains "ran:rlwrap"
  assert_output_contains "mix acme.cli repl"
  assert_output_contains ".acme_cli_repl_history"
}

@test "the cli task is exported, because handlers never read config" {
  proj="$(mkproj acme_cli <<'YAML'
project:
  name: acme_cli
  cli_task: acme.cli
  languages:
    - elixir
commands:
  show:
    summary: Report the task
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'TASK=%s\n' "${DEVBIN_CLI_TASK:-unset}"
SH
  chmod +x "$proj/show"
  run devbin_run "$proj" show
  assert_success
  # lib/helpers has no config dependency by rule and a handler is a
  # separate process, so the dispatcher exports the resolved value the way it
  # already exports DEVBIN_NAME.
  assert_output_contains "TASK=acme.cli"
}
