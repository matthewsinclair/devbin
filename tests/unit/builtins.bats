#!/usr/bin/env bats
# builtins.bats - lib/builtins and the built-in gate commands (WP-08)
#
# The CATALOGUE is one table. It replaced two placeholder tables in lib/resolve,
# and the value of having moved them is lost the moment a copy comes back, so
# there is a test that greps for one.
#
# The TIERS are a claim about the corpus, not a preference:
# `build` ships no option set because the four source projects have four
# disjoint target lists. A later edit adding `build cli|daemon|native` because
# one project has them would impose that project's shape on the rest, so that
# too is a test rather than a comment.

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


# ============================================================================
# THE CATALOGUE IS ONE TABLE
# ============================================================================

@test "lib/resolve keeps no copy of the built-in tables" {
  # They were moved here by WP-08, not copied. Two tables describing the same
  # built-ins drift the moment one gains an entry.
  run grep -nE '_DEVBIN_BUILTIN_(LANGS|COMMANDS|OPTIONS|CATALOGUE)=' "$DEVBIN_LIB_DIR/resolve"
  assert_failure
}

@test "the catalogue answers every field for a tier-2 option" {
  [ "$(builtin_option_lang check compile)" = "elixir" ]
  [ "$(builtin_option_grammar check compile)" = "mix" ]
  [ "$(builtin_option_suffix check compile)" = "COMPILE" ]
  [ "$(builtin_option_run check compile)" = "mix compile --warnings-as-errors --force" ]
  [ "$(builtin_option_summary check compile)" = "Compile with warnings as errors" ]
}

@test "a command line keeps its flags intact, including a bare --" {
  # The run field is everything between the suffix and the ` | `, so a command
  # containing `--` or multiple flags must survive whole.
  [ "$(builtin_option_run check clippy)" = "cargo clippy --all-targets -- -D warnings" ]
  [ "$(builtin_option_run db seed)" = "mix run priv/repo/seeds.exs" ]
}

@test "a tier-1 option reports @builtin rather than a command line" {
  [ "$(builtin_option_run check toolchain)" = "@builtin" ]
  [ "$(builtin_option_run check critic)" = "@builtin" ]
  # It still carries the rest of its metadata.
  [ "$(builtin_option_suffix check toolchain)" = "TOOLCHAIN" ]
  [ -n "$(builtin_option_summary check toolchain)" ]
}

@test "an option the catalogue does not have returns non-zero from every accessor" {
  run builtin_option_run check nosuch
  assert_failure
  run builtin_option_lang check nosuch
  assert_failure
  run builtin_option_summary nosuch nosuch
  assert_failure
}

@test "builtin_options_for lists a command's options in catalogue order" {
  run builtin_options_for check
  assert_success
  assert_output "compile
format
deps
clippy
autotests
targetdir
toolchain
critic"
}

@test "is_builtin_command and builtin_commands agree" {
  is_builtin_command check
  is_builtin_command server
  run is_builtin_command nosuchcommand
  assert_failure
  run builtin_commands
  assert_output_contains "check"
  assert_output_contains "version"
}

# ============================================================================
# THE TIERS
# ============================================================================

@test "build ships NO option set (tier 4)" {
  # Universal in name only: one project has cli|deploy|grammar, a second has
  # cli|daemon|native|app|assets, a third has release|assets|deploy|clean, a fourth
  # has none. The intersection is empty, so shipping any of them would impose
  # one project's shape on the other three.
  is_builtin_command build
  run builtin_options_for build
  assert_success
  assert_output ""
}

@test "check.parity is deliberately absent from the catalogue" {
  # Two of four projects, two bespoke implementations sharing only a name.
  run builtin_option_run check parity
  assert_failure
}

@test "every catalogue option names a grammar devbin actually ships" {
  # A typo here would seal every red run of that gate with the fallback grammar
  # and a warning nobody reads.
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  known="$(grammar_names)"
  for cmd in check test db fmt; do
    while IFS= read -r opt; do
      [ -n "$opt" ] || continue
      g="$(builtin_option_grammar "$cmd" "$opt")"
      case "
$known
" in
        *"
$g
"*) ;;
        *)
          fail "$cmd.$opt names grammar '$g', which devbin does not ship"
          return 1
          ;;
      esac
    done <<EOF
$(builtin_options_for "$cmd")
EOF
  done
}

@test "every @builtin row in the catalogue has something implementing it" {
  # A catalogue entry marked @builtin with nothing behind it is a devbin
  # packaging error that would only surface when someone ran it.
  #
  # This SCANS the table rather than checking a hard-coded pair, because the
  # hard-coded version could not catch the thing it exists to catch: a new
  # @builtin row added with no implementation. What @builtin resolves to depends
  # on the row kind -- an option row names a function, a command row names the
  # handler file itself.
  #
  # EVERY FIELD, AND A COUNT OF WHAT IT CHECKED (issue 0138). It read too few from
  # when the catalogue gained its group column until 0138: the group
  # landed in the command line, no row ever read as @builtin, and the arm checked
  # nothing -- a planted row with nothing behind it passed. The count below,
  # taken a second way, is what fails if a column moves again.
  local name lang grammar suffix group rest run bad="" cmd opt checked=0 expected
  while read -r name lang grammar suffix group rest; do
    [ -n "$name" ] || continue
    run="${rest%% | *}"
    [ "$run" = "@builtin" ] || continue
    checked=$((checked + 1))
    case "$name" in
      *.*)
        cmd="${name%%.*}"
        opt="${name#*.}"
        grep -q "^builtin_${cmd}_${opt}()" "$DEVBIN_LIB_DIR/cmd/$cmd" 2>/dev/null ||
          bad="$bad $name(no builtin_${cmd}_${opt} in lib/cmd/$cmd)"
        ;;
      *)
        [ -x "$DEVBIN_LIB_DIR/cmd/$name" ] ||
          bad="$bad $name(no executable lib/cmd/$name)"
        ;;
    esac
  done <<EOF
$_DEVBIN_BUILTIN_CATALOGUE
EOF
  # THE DENOMINATOR, counted without the column parse: every row whose command
  # line is the literal @builtin. grep -c exits 1 on a count of zero, which the
  # floor reports; any other failure leaves $expected empty and fails here.
  expected="$(printf '%s\n' "$_DEVBIN_BUILTIN_CATALOGUE" | grep -c ' @builtin | ')" || [ "$expected" = 0 ]
  [ "$expected" -gt 0 ] || fail "the catalogue holds no @builtin row -- the count is broken, not the catalogue"
  [ "$checked" -eq "$expected" ] ||
    fail "checked $checked @builtin rows, and the catalogue holds $expected -- the row parse no longer matches the table"
  [ -z "$bad" ] || fail "@builtin rows with nothing behind them:$bad"
}

@test "the catalogue's side tables name only what the catalogue has, and answer for it (0132, 0156)" {
  # They sit BESIDE the table, keyed by name, so a renamed row would leave an
  # entry naming nothing and the default or the refusal would silently stop
  # applying. Each entry is held to a real row here.
  local e name rest n=0 bad=""
  [ -n "$_DEVBIN_BUILTIN_NOT_IN_ALL" ] || fail "no option is outside all -- this arm would check nothing"
  for e in $_DEVBIN_BUILTIN_NOT_IN_ALL; do
    case "$e" in
      ?*.?*) builtin_option_run "${e%%.*}" "${e#*.}" >/dev/null || bad="$bad $e(no option row)" ;;
      *) bad="$bad $e(not <command>.<option>)" ;;
    esac
  done
  while read -r name rest; do
    [ -n "$name" ] || continue
    n=$((n + 1))
    is_builtin_command "$name" || bad="$bad $name(no command row)"
  done <<EOF
$_DEVBIN_BUILTIN_REFUSALS
EOF
  [ "$n" -gt 0 ] || fail "no command refuses an environment -- this arm would check nothing"
  # And the needs table (issue 0156): each entry is <command>.<option> <path>,
  # and names a real option row.
  local key need m=0
  while read -r key need; do
    [ -n "$key" ] || continue
    m=$((m + 1))
    [ -n "$need" ] || bad="$bad $key(needs nothing named)"
    case "$key" in
      ?*.?*) builtin_option_run "${key%%.*}" "${key#*.}" >/dev/null || bad="$bad $key(no option row)" ;;
      *) bad="$bad $key(not <command>.<option>)" ;;
    esac
  done <<EOF
$_DEVBIN_BUILTIN_NEEDS
EOF
  [ "$m" -gt 0 ] || fail "no option needs anything in the tree -- this arm would check nothing"
  [ -z "$bad" ] || fail "side-table entries naming nothing in the catalogue:$bad"
  [ "$(builtin_option_needs check critic)" = intent ] || fail "check critic needs '$(builtin_option_needs check critic)'"
  [ -z "$(builtin_option_needs check format)" ] || fail "check format needs '$(builtin_option_needs check format)'"
  # And the readers answer for them: reset outside all, its siblings and an
  # option devbin does not ship inside it; db's refusal row, and none for test.
  [ "$(builtin_option_in_all db reset)" = false ] || fail "db reset is not outside all"
  [ "$(builtin_option_in_all db setup)" = true ] || fail "db setup is outside all"
  [ "$(builtin_option_in_all build cli)" = true ] || fail "an option devbin does not ship is outside all"
  [ "$(builtin_env_refusal db | cut -f1,2)" = "$(printf 'MIX_ENV\tprod')" ] || fail "db's refusal row reads $(builtin_env_refusal db)"
  ! builtin_env_refusal test >/dev/null || fail "test refuses an environment it was never given"
}

# ============================================================================
# THE BUILT-IN GATES, END TO END
# ============================================================================

@test "a built-in gate runs its catalogue command line and seals" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  mkdir -p "$proj/tests"
  printf '@test "fine" { true; }\n' >"$proj/tests/demo.bats"
  run_in_project "$proj" test shell
  assert_success
  # It ran bats, from the catalogue, with nothing declared in config.
  assert_output_contains "ok 1 fine"
  assert_output_contains "verdict:"
  assert_file_empty "$proj/tmp/test/LATEST_SHELL.errors"
}

@test "a failing built-in gate seals red with the right grammar" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  mkdir -p "$proj/tests"
  printf '@test "broken" { false; }\n' >"$proj/tests/demo.bats"
  run_in_project "$proj" test shell
  assert_failure
  seal="$proj/tmp/test/LATEST_SHELL.errors"
  [ -s "$seal" ]
  # The shell grammar picked the TAP failure out, rather than falling to a tail.
  assert_file_contains "$seal" "not ok 1 broken"
  refute_file_contains "$seal" "log tail"
}

@test "config overrides a built-in option's command line" {
  # The tier-2 shape: devbin knows the option, the project says how to run
  # it here, and no script is written either way.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      shell:
        summary: our own runner
        run: echo ran-the-override
YAML
  )"
  run_in_project "$proj" test shell
  assert_success
  assert_output_contains "ran-the-override"
}

@test "an unknown option of a built-in command is refused by name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run_in_project "$proj" test nosuchgate
  assert_failure
  assert_output_contains "nosuchgate"
}

@test "a built-in gate command with no option prints its usage" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run_in_project "$proj" test
  # Exit 1, not 0: naming no gate is a usage error, and a gate command that
  # exits 0 having run nothing is a false green. Asking with `--help` succeeds.
  assert_exit_code 1
  assert_output_contains "usage:"
  assert_output_contains "shell"
}

@test "built-in commands are discoverable in help with an empty config" {
  # The gap this closed: `devbin test shell` worked while `devbin help` printed
  # nothing at all, because known_commands only ever looked at config and the
  # project's own cmd/ directory. Help disagreeing with what dispatches is the
  # drift this design exists to remove.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run_in_project "$proj" help
  assert_success
  assert_output_contains "check"
  assert_output_contains "test"
  assert_output_contains "shell"
  assert_output_contains "BATS suites"
}

@test "help scopes the built-in surface to the declared languages" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  )"
  run_in_project "$proj" help
  assert_success
  assert_output_contains "clippy"
  assert_output_contains "Cargo suites"
  # No Elixir gates, and no db/fmt-elixir surface, in a Rust-only project.
  refute_output_contains "ExUnit"
  refute_output_contains "credo"
  refute_output_contains "Run pending migrations"
}

@test "a project handler still displaces the whole built-in option set" {
  # AC-04.4 has to keep holding now that the built-ins are real.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  create_test_command "$proj" test >/dev/null
  run_in_project "$proj" test shell
  assert_success
  assert_output "ran:test args:shell"
  refute_output_contains "verdict:"
}

# ============================================================================
# ONE RIG: A DECLARED GATE SEALS LIKE A SHIPPED ONE
# ============================================================================

@test "a declared option with log: seals through the same runner as a built-in" {
  # The rig is generic; only the TARGETS are per-project. Before this, a shipped
  # option sealed and a declared one ran bare -- the same surface with different
  # guarantees, and no artifact from the half a project actually configures.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build targets
    options:
      cli:
        summary: the CLI crate
        run: echo building-cli
        log: true
      assets:
        summary: static assets
        run: echo building-assets
        log: ASSETS
YAML
  )"
  run_in_project "$proj" build all
  assert_success
  assert_output_contains "building-cli"
  assert_output_contains "building-assets"
  assert_output_contains "verdict:"
  # `log: true` names the pair after the option; an explicit value is taken as
  # given.
  assert_file_empty "$proj/tmp/build/LATEST_CLI.errors"
  assert_file_empty "$proj/tmp/build/LATEST_ASSETS.errors"
}

@test "a config run: override of a catalogue gate keeps its seal and its grammar" {
  # Overriding a catalogue option's COMMAND LINE does not change what the option
  # IS. `test.swift` is a catalogue gate -- suffix SWIFT, grammar xcodebuild --
  # and a project pointing it at its own .xcodeproj has not asked to stop
  # sealing. It used to: run_option read `log:` and `grammar:` from config
  # alone, with no fall back to the row, so an override silent about both
  # silently demoted a sealed gate to a bare exec.
  #
  # Found at ST0002 WP-08, on the first project to arm swift.
  # `test swift` ran, xcodebuild printed ** TEST FAILED **, and NO verdict file
  # was written -- not an empty .errors meaning green, but no seal to read at
  # all. Under "read the seal, never the exit code" that is the one failure the
  # doctrine cannot survive, and the exit code being right is what makes it
  # invisible.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
commands:
  test:
    options:
      swift:
        run: ./fake-xcodebuild
YAML
  )"
  printf '#!/bin/sh\necho "** TEST FAILED **"\nexit 1\n' >"$proj/fake-xcodebuild"
  chmod +x "$proj/fake-xcodebuild"

  run_in_project "$proj" test swift
  assert_failure
  assert_output_contains "verdict:"
  assert_file_exists "$proj/tmp/test/LATEST_SWIFT.errors"
  # WHAT THE SEAL HOLDS IS THE GRAMMAR'S EVIDENCE. Under the inherited
  # xcodebuild grammar `** TEST FAILED **` is extracted and is the whole seal;
  # under the generic default it matches nothing and the seal becomes the
  # log-tail fallback. This pair is what tells the two apart. It replaced
  # `refute_file_contains ... "^$"`, which grep -F reads as the literal
  # characters `^$`, so that line could never fail (0065).
  assert_file_contains "$proj/tmp/test/LATEST_SWIFT.errors" "** TEST FAILED **"
  refute_file_contains "$proj/tmp/test/LATEST_SWIFT.errors" "no parseable failure blocks"
}

# _swift_override_with_log <name> <log value> -- a project overriding the
# catalogue gate test.swift's command line, with `log:` written verbatim, and a
# stand-in tool that succeeds. Prints the project path. Every step returns on
# failure because callers run this inside `$(...)`, where errexit does not
# reach, and a half-built fixture would surface as a baffling assertion later.
_swift_override_with_log() {
  local proj
  proj="$(printf 'project:\n  name: %s\n  languages:\n    - swift\ncommands:\n  test:\n    options:\n      swift:\n        run: ./fake-xcodebuild\n        log: %s\n' "$1" "$2" | mkproj "$1")" || return 1
  printf '#!/bin/sh\necho "fake-xcodebuild ran"\n' >"$proj/fake-xcodebuild" || return 1
  chmod +x "$proj/fake-xcodebuild" || return 1
  printf '%s\n' "$proj"
}

@test "a project-side log: - declines the seal a catalogue gate would otherwise inherit" {
  # Issue 0065. The fallback above exists for an override that is SILENT about
  # `log:`. A project writing the sentinel is not silent, it is declining -- and
  # the `-` mapping sat inside the fallback, so it applied only to the
  # catalogue's own value. The project's `-` skipped the fallback and sealed the
  # gate under the suffix `-`. A four-value sweep in one consumer (absent, false, "",
  # "-") found every one wrapping, so the wrapper could not be declined at all.
  proj="$(_swift_override_with_log demo '"-"')"
  run_in_project "$proj" test swift
  assert_success
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
  assert_output "fake-xcodebuild ran"
}

@test "log: false, no and 0 decline a catalogue gate's seal exactly as - does" {
  # The spellings devbin already reads as false for `enabled:`. `true`, `yes`
  # and `1` already mean "seal it, named after the option" (gate_log_suffix), so
  # leaving their negations to seal under a suffix called `false` was the same
  # defect as `-` with a different word.
  # Each spelling is held to everything the `-` arm asserts, so "exactly as -
  # does" is a claim the test checks rather than a name it wears: a regression
  # that declined by not running the tool at all fails the last line.
  proj="$(_swift_override_with_log demofalse false)"
  run_in_project "$proj" test swift
  assert_success
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
  assert_output "fake-xcodebuild ran"

  proj="$(_swift_override_with_log demono no)"
  run_in_project "$proj" test swift
  assert_success
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
  assert_output "fake-xcodebuild ran"

  proj="$(_swift_override_with_log demozero 0)"
  run_in_project "$proj" test swift
  assert_success
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
  assert_output "fake-xcodebuild ran"
}

@test "an EMPTY log: is not a decline, so an override still inherits the catalogue's seal" {
  # The control for the arms above, and the half 0065 says is deliberate: a
  # project overriding a gate's run: without saying anything about sealing must
  # not silently stop sealing. An empty value says nothing.
  proj="$(_swift_override_with_log demoempty '""')"
  run_in_project "$proj" test swift
  assert_success
  assert_output_contains "verdict:"
  assert_file_exists "$proj/tmp/test/LATEST_SWIFT.errors"
  assert_file_empty "$proj/tmp/test/LATEST_SWIFT.errors"
}

@test "a command-level log: - runs the command bare rather than sealing it under the suffix -" {
  # The same sentinel one level up. A command-level `log:` has no catalogue
  # fallback, so here the defect was only the suffix: `-` sealed a gate named
  # `-`. One resolver answers what a declared `log:` means at both levels.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  greet:
    summary: say hello
    run: echo hello
    log: "-"
YAML
  )"
  run_in_project "$proj" greet
  assert_success
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
  assert_output "hello"
}

@test "0066: an option's declared grammar: - seals with the generic grammar, not a grammar named -" {
  # `-` means "no default" everywhere devbin reads it. Until 0066 run_option
  # honoured it only on the catalogue's value, so a project writing it got
  # `unknown grammar '-'` -- 0065's scoping mistake on the next key over.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      one:
        summary: a sealed gate
        run: echo ok
        log: true
        grammar: "-"
YAML
  )"
  run_in_project "$proj" gate one
  assert_success
  assert_output_contains "verdict:"
  refute_output_contains "unknown grammar"
}

@test "0066: a command-level grammar: - seals with the generic grammar too" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  greet:
    summary: say hello
    run: echo hello
    log: true
    grammar: "-"
YAML
  )"
  run_in_project "$proj" greet
  assert_success
  assert_output_contains "verdict:"
  refute_output_contains "unknown grammar"
}

@test "0066: gate_grammar reads empty and - as generic, and passes every name through" {
  # The one resolver, used by run_option, run_command and the catalogue gate
  # path alike. Pure, so the gatecmd path -- where no row carries `-` today --
  # is held here rather than by a fixture catalogue.
  # shellcheck source=lib/runlog
  . "$DEVBIN_LIB_DIR/runlog"
  [ "$(gate_grammar "")" = generic ] || fail "empty reads '$(gate_grammar "")'"
  [ "$(gate_grammar -)" = generic ] || fail "- reads '$(gate_grammar -)'"
  [ "$(gate_grammar mix)" = mix ] || fail "mix reads '$(gate_grammar mix)'"
  [ "$(gate_grammar --)" = -- ] || fail "-- reads '$(gate_grammar --)'"
}

@test "0066: lib/builtins REFUSES to load without lib/helpers, rather than misreading its own -" {
  # Without is_no_default, `! is_no_default` turns "command not found" into
  # success, and builtin_has_default_run claimed a command line for `build`,
  # whose row has none -- with no message.
  run bash -c ". '$DEVBIN_LIB_DIR/builtins' && builtin_has_default_run build"
  assert_failure
  assert_output_contains "source lib/helpers first"
  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/builtins' && builtin_has_default_run build"
  assert_failure
  refute_output_contains "source lib/helpers first"
  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/builtins' && builtin_has_default_run check compile"
  assert_success
}

@test "a command-level log: true seals under the command's own name" {
  # The positive path through run_command's resolver. No fixture sent a
  # `log: true` through it until work on 0065 found the seal call resolving
  # the value a second time.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  greet:
    summary: say hello
    run: echo hello
    log: true
YAML
  )"
  run_in_project "$proj" greet
  assert_success
  assert_output_contains "verdict:"
  assert_file_exists "$proj/tmp/greet/LATEST_GREET.errors"
  assert_file_empty "$proj/tmp/greet/LATEST_GREET.errors"
}

@test "an option with no log: runs bare, so an interactive command is not teed" {
  # Opt-in for a reason: `server` and `iex` are long-running and never exit, so
  # teeing them would buffer the output a developer is watching and seal nothing.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  server:
    summary: dev server
    options:
      web:
        summary: not a gate
        run: echo serving
YAML
  )"
  run_in_project "$proj" server web
  assert_success
  assert_output "serving"
  refute_output_contains "verdict:"
  assert_directory_not_exists "$proj/tmp"
}

@test "a declared gate seals RED and its grammar applies" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build targets
    options:
      cli:
        summary: the CLI crate
        run: ./failing-build
        log: true
        grammar: generic
YAML
  )"
  # A script rather than an inline `sh -c "..."`: the declarative `run:` is
  # word-split, never evalled, so quotes in it are literal. A
  # command line that needs real quoting needs a script, which is the boundary
  # working as intended.
  cat >"$proj/failing-build" <<'SH'
#!/usr/bin/env bash
echo "Error: link failed"
exit 2
SH
  chmod +x "$proj/failing-build"
  run_in_project "$proj" build cli
  assert_exit_code 2
  seal="$proj/tmp/build/LATEST_CLI.errors"
  [ -s "$seal" ]
  assert_file_contains "$seal" "Error: link failed"
  refute_file_contains "$seal" "log tail"
}

@test "all points at a declared gate's seal, exactly as it does a built-in's" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build targets
    options:
      good:
        summary: fine
        run: echo ok
        log: true
      bad:
        summary: breaks
        run: ./breaks
        log: true
YAML
  )"
  printf '#!/usr/bin/env bash\necho "Error: nope"\nexit 1\n' >"$proj/breaks"
  chmod +x "$proj/breaks"
  run_in_project "$proj" build all
  assert_failure
  assert_output_contains "FAILED: bad"
  assert_output_contains "$proj/tmp/build/"
  assert_output_contains ".BAD.errors"
}

@test "a declared option runs at the project root, not the caller's directory" {
  # `mix test` / `cargo build` are project commands. Every corpus runner cd'd to
  # the root first; devbin does it once, for shipped and declared options alike,
  # so `bin/devbin build cli` means the same thing from any directory.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build targets
    options:
      here:
        summary: reports its directory
        run: ./whereami
        log: true
YAML
  )"
  printf '#!/usr/bin/env bash\nprintf "cwd=%%s\\n" "$PWD"\n' >"$proj/whereami"
  chmod +x "$proj/whereami"
  mkdir -p "$proj/deep/nested"
  # NOT devbin_run, which cd's to the project itself before invoking: under it
  # the caller NEVER stands anywhere else, so the second half of this arm's own
  # title could not fail. The caller has to actually be in the nested directory
  # for the claim to have a way of going wrong (found vacuous under 0082).
  run bash -c 'cd "$1/deep/nested" && "$1/bin/devbin" build here </dev/null' _ "$proj"
  assert_success
  assert_output_contains "cwd=$proj"
  refute_output_contains "cwd=$proj/deep/nested"
  # And the seal landed under the project root too, matching the verdict line.
  assert_file_exists "$proj/tmp/build/LATEST_HERE.errors"
}

# ============================================================================
# THE EMPTY CRITIC RUN -- DECLARED, NOT SILENT
# ============================================================================
#
# `check critic` reads STAGED files, so its corpus is a SELECTION and not a
# suite, and run_gate's promotion counts and does nothing else. Giving this gate
# a counting grammar was right -- it had passed vacuously three times running --
# but on its own it made the ORDINARY case red, which is how a gate teaches
# people to ignore it.
#
# The split under test: a DEFAULT corpus that scans nothing is not applicable
# and says so; an EXPLICIT corpus that scans nothing is a failure. The first
# version of this keyed on `git diff --cached` being empty instead, and it FIRED
# ON MARKDOWN -- five staged .md files reddened a gate about source code. That
# is what "staging a doc does not redden a gate about source code" below
# exists to hold down.

# A project whose critic is a stub, so the only thing varying between the tests
# is the corpus. `scan` controls whether the stub reports work done.
critic_proj() {
  local proj scan="${1:-none}"
  proj="$(create_test_project criticdemo)"
  install_devbin "$proj" >/dev/null
  cat >"$proj/bin/.devbin/config.yaml" <<'YAML'
project:
  name: criticdemo
  languages:
    - elixir
YAML
  mkdir -p "$proj/intent/.config"
  printf '{"languages":["elixir"]}\n' >"$proj/intent/.config/config.json"
  mkdir -p "$proj/fakebin"
  cat >"$proj/fakebin/intent" <<SH
#!/bin/sh
if [ "\$1" = critic ] && [ "\$2" = --languages ]; then printf 'elixir\n'; exit 0; fi
if [ "\$1" = critic ]; then
  if [ "$scan" = some ]; then printf '1..2\nok 1 a\nok 2 b\n'; else printf 'ok: no staged %s files to scan\n' "\$2"; fi
  exit 0
fi
exit 0
SH
  chmod +x "$proj/fakebin/intent"
  git -C "$proj" init -q
  git -C "$proj" config user.email dev@test
  git -C "$proj" config user.name dev
  echo "$proj"
}

@test "check critic on a clean tree is NOT APPLICABLE, and SAYS so" {
  # Green, but never silently: the announcement is the half that was actually
  # complained about, three separate times.
  proj="$(critic_proj)"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  assert_output_contains "no tests ran"
  refute_output_contains "PROMOTED TO FAILED"
}

@test "staging a doc does not redden a gate about source code" {
  # THE REGRESSION THIS SECTION EXISTS FOR. Keying on "is anything staged" looks
  # right and is wrong: a staged .md is not a critic corpus, and treating it as
  # one puts the gate red for a reason unrelated to source code. Measured on
  # one consumer with five staged .md files before this test existed.
  proj="$(critic_proj)"
  printf '# notes\n' >"$proj/NOTES.md"
  git -C "$proj" add NOTES.md
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  refute_output_contains "PROMOTED TO FAILED"
}

@test "an explicit --files corpus that scans nothing FAILS" {
  # The negative that keeps the original false green closed. The caller named
  # files; examining none of them is never what was intended.
  proj="$(critic_proj)"
  printf 'defmodule X do\nend\n' >"$proj/thing.ex"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic --files thing.ex
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"
}

@test "a critic that actually scans is judged on its own merits, not waved through" {
  # --allow-empty must not become "this gate cannot fail". With real output the
  # counter is non-zero, so the emptiness escape never engages at all.
  proj="$(critic_proj some)"
  printf 'defmodule X do\nend\n' >"$proj/thing.ex"
  git -C "$proj" add thing.ex
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  refute_output_contains "no tests ran"
}

@test "over an index git cannot read, check critic says git could not say what is staged, never that nothing is (0186)" {
  # A failed `git diff --cached` read as nothing staged: the builtin warned that
  # the critic would examine no files, and Intent's critic then failed on the
  # same git call, under a diagnosis the warning had just contradicted.
  proj="$(critic_proj)"
  # THE CONTROLS: nothing staged says so, and a staged file says nothing of it.
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  assert_output_contains "nothing staged"
  printf 'defmodule X do\nend\n' >"$proj/thing.ex"
  git -C "$proj" add thing.ex
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  refute_output_contains "nothing staged"
  refute_output_contains "git could not say what is staged"
  break_git_index "$proj"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_failure
  assert_output_contains "git could not say what is staged"
  assert_output_contains "so the critic was not run -- fatal: .git/index: index file smaller than expected"
  refute_output_contains "nothing staged"
}

@test "in a project that is not a git checkout, check critic says so in devbin's words, never git's usage error (0186)" {
  # Outside a repository git takes `diff` for `diff --no-index`, which has no
  # --cached, so the stop carried a usage error as its reason.
  proj="$(critic_proj)"
  # THE CONTROL: in the checkout, nothing staged says so and passes.
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  assert_output_contains "nothing staged"
  rm -rf "$proj/.git"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_failure
  assert_output_contains "is not a git checkout, so nothing can be staged and the critic was not run"
  refute_output_contains "unknown option"
  refute_output_contains "nothing staged"
}

@test "over a commit's own index, which git cannot read, check critic gives that index's reason (0186)" {
  # A commit hook names the index it commits in GIT_INDEX_FILE, and the probe
  # reads it, as Intent's critic does. The reason was asked through
  # git_readonly, which clears it: it read the repository's own index, which
  # reads, and the stop gave no reason at all.
  proj="$(critic_proj)"
  : >"$DEVBIN_TEST_TMPDIR/cut.index"
  # THE CONTROL: with the repository's own index, nothing staged passes.
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_success
  GIT_INDEX_FILE="$DEVBIN_TEST_TMPDIR/cut.index" PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_failure
  assert_output_contains "so the critic was not run -- fatal: "
  assert_output_contains "index file smaller than expected"
}

@test "a builtin with no gateflags hook is dispatched exactly as before" {
  # The negative control for the MECHANISM: the hook is opt-in per builtin, and
  # every other built-in gate must be untouched by its existence.
  proj="$(critic_proj)"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check format
  refute_output_contains "no tests ran (--allow-empty)"
}
