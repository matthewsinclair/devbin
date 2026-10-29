#!/usr/bin/env bats
# help.bats - the help subsystem (WP-07)
#
# What is actually under test here is the claim that help CANNOT drift from what
# resolves. The corpus made the opposite bet: four launchers each carried a
# 20-25 KB hand-maintained heredoc listing the commands its own dispatcher
# happened to implement, and keeping the two in step was a person's job forever.
# ~92 KB of it. Nothing in this file is interesting unless the listing is
# derived, which is why the DRIFT, BOTH DIRECTIONS tests are the point and the
# rest is detail.
#
# The other half is the split: generated at the top, AUTHORED at the leaf. No
# generator was going to produce the corpus's "prod HERE MEANS THE INSTALLED
# BINARIES, NOT THE PROD SERVER" warning, so `help <cmd>` reads markdown a human
# wrote and falls back to a generated answer rather than to an empty page.

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


# Write an authored help topic into a fixture.
authored() {
  local proj="$1" topic="$2"
  mkdir -p "$(dirname "$proj/bin/.devbin/help/$topic")"
  cat >"$proj/bin/.devbin/help/$topic.md"
}

# ============================================================================
# THE GENERATED LISTING (AC-07.1)
# ============================================================================

@test "the listing is generated from what resolves, not from a hand-written list" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  deploy:
    summary: Ship it somewhere
    group: Ship
    run: /bin/echo deploying
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # A command config declared and devbin never heard of.
  assert_output_contains "deploy"
  assert_output_contains "Ship it somewhere"
  # And a built-in the project never mentioned, active because it declared shell.
  assert_output_contains "test"
  assert_output_contains "BATS suites"
}

@test "a project with only a name still gets a surface, and help says so" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # `any`-language built-ins are offered with no config at all. Help printing
  # nothing here was the bug that made known_commands scan the catalogue.
  assert_output_contains "build"
  assert_output_contains "version"
}

@test "the listing names the project in the tagline and the INVOCATION in the usage line" {
  proj="$(mkproj widget <<'YAML'
project:
  name: widget
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Two questions, and they used to have one answer because the launcher was
  # symlinked to the project's name. WHICH PROJECT IS THIS -> the tagline.
  assert_output_contains "widget --"
  # WHAT DO I TYPE -> bin/devbin, in every project, since the per-project
  # symlink was retired.
  assert_output_contains "bin/devbin <command>"
  refute_output_contains "bin/widget <command>"
}

@test "an empty surface says so rather than printing an empty page" {
  # The disable list is GENERATED from the catalogue, not typed out. It WAS
  # typed out -- six names, every `any` command that existed when this was
  # written -- so WP-09 adding four more turned a test about empty surfaces into
  # a test about which built-ins shipped in WP-07, and it failed for a reason
  # that had nothing to do with what it was asserting. A test's vehicle must not
  # be borrowed from the shipping schedule.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  {
    printf 'project:\n  name: demo\ncommands:\n'
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      printf '  %s:\n    enabled: false\n' "$c"
    done <<EOF
$(builtin_commands)
EOF
  } >"$proj/bin/.devbin/config.yaml"

  run devbin_run "$proj" help
  assert_success
  assert_output_contains "No commands are active"
  assert_output_contains "config.yaml"
}

# ============================================================================
# GROUPING (AC-07.2)
# ============================================================================

@test "groups print in the order config declares" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
help:
  groups:
    - Ship
    - Build
commands:
  release:
    summary: Cut a release
    group: Ship
    run: true
  compile:
    summary: Compile it
    group: Build
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Ship's heading must precede Build's, which is the whole claim.
  local ship build
  ship="$(printf '%s\n' "$output" | grep -n '^Ship:' | cut -d: -f1)"
  build="$(printf '%s\n' "$output" | grep -n '^Build:' | cut -d: -f1)"
  [ -n "$ship" ] || {
    fail "no Ship heading in:\n$output"
    return 1
  }
  [ "$ship" -lt "$build" ] || {
    fail "Ship ($ship) should precede Build ($build):\n$output"
    return 1
  }
}

@test "a declared group with nothing in it gets no heading" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
help:
  groups:
    - Ship
    - Nobody
commands:
  release:
    summary: Cut a release
    group: Ship
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Ship:"
  refute_output_matches '^Nobody:'
}

@test "a group config never named still prints, after the declared ones" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
help:
  groups:
    - Ship
commands:
  release:
    summary: Cut a release
    group: Ship
    run: true
  weird:
    summary: Something else
    group: Surprise
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  local ship surprise
  ship="$(printf '%s\n' "$output" | grep -n '^Ship:' | cut -d: -f1)"
  surprise="$(printf '%s\n' "$output" | grep -n '^Surprise:' | cut -d: -f1)"
  [ -n "$surprise" ] || {
    fail "undeclared group vanished:\n$output"
    return 1
  }
  [ "$ship" -lt "$surprise" ] || {
    fail "declared Ship should precede undeclared Surprise:\n$output"
    return 1
  }
}

@test "a command with no group anywhere lands in Other rather than vanishing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  orphan:
    summary: No group anywhere
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # The regression this pins: the ungrouped set was emitted as a trailing empty
  # line and `$(...)` strips trailing newlines, so Other vanished exactly when
  # it was the last thing to print.
  assert_output_contains "Other:"
  assert_output_contains "orphan"
}

@test "a group entry may carry an annotation, and the command still matches" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
help:
  groups:
    - Test (SEALED gates -- the verdict is a FILE)
commands:
  suite:
    summary: Run it
    group: Test
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # The heading prints verbatim; the command matches on the name before ` (`.
  assert_output_contains "Test (SEALED gates -- the verdict is a FILE):"
  assert_output_contains "suite"
  refute_output_matches '^Other:'
}

# ============================================================================
# ONE SOURCE PER FACT (AC-07.3)
# ============================================================================

@test "config's summary beats the handler header and the catalogue" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    summary: Config wins
YAML
  )"
  create_test_command "$proj" test '#!/usr/bin/env bash
# devbin: summary = Header loses
set -euo pipefail
printf "ran\n"'
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Config wins"
  refute_output_contains "Header loses"
}

@test "a handler header describes a command config never mentions" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" deploy '#!/usr/bin/env bash
# devbin: summary = Ship it to the cluster
# devbin: group   = Ship
set -euo pipefail
printf "ran\n"'
  run devbin_run "$proj" help
  assert_success
  # No config edit at all -- the file being there is the whole declaration.
  assert_output_contains "Ship it to the cluster"
  assert_output_contains "Ship:"
}

@test "the catalogue describes a built-in nobody mentioned" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "BATS suites"
}

@test "a header is read only from the leading comment block" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" deploy '#!/usr/bin/env bash
# devbin: summary = The real one
set -euo pipefail

# A handler that TALKS about the convention is not declaring one:
# devbin: summary = Not this
printf "ran\n"'
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "The real one"
  refute_output_contains "Not this"
}

@test "no lib/cmd handler carries a summary its catalogue row already owns" {
  # Structural, and it holds down one source per fact rather than a rendering
  # detail. Every
  # lib/cmd handler DID carry a `# devbin: summary =` header that nothing read,
  # duplicating its catalogue row -- and by the time WP-07 came to read one they
  # had already drifted a word apart ("the project's" vs "this project's").
  # A command devbin ships is declared by its row; the header is for handlers
  # devbin does not ship.
  run grep -rn '^# devbin: ' "$DEVBIN_LIB_DIR/cmd"
  assert_failure
}

# ============================================================================
# PROJECT COMMANDS ARE FIRST-CLASS (AC-07.4)
# ============================================================================

@test "a dropped-in handler gets a group, options and a synthesised all" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  media:
    group: Assets
    summary: Media pipeline
    options:
      covers:
        summary: Rebuild covers
      thumbs:
        summary: Rebuild thumbnails
YAML
  )"
  create_test_command "$proj" media
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Assets:"
  assert_output_contains "Media pipeline"
  assert_output_contains "covers"
  assert_output_contains "thumbs"
  assert_output_contains "every option above, one pass"
}

@test "a usage hint rides in the left column when declared" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  server:
    summary: Dev server
    args: "[--iex]"
    run: true
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_matches 'server \[--iex\]'
}

# ============================================================================
# AUTHORED DETAIL (AC-07.5, AC-07.6)
# ============================================================================

@test "help <cmd> prints the authored file when there is one" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  deploy:
    summary: Ship it
    run: true
YAML
  )"
  authored "$proj" deploy <<'MD'
demo deploy [--dry-run]

The long-form prose a generator was never going to write.
MD
  run devbin_run "$proj" help deploy
  assert_success
  assert_output_contains "The long-form prose a generator was never going to write."
  # Authored REPLACES the generated answer rather than being appended to it.
  refute_output_contains "No authored detail yet"
}

@test "a sub-topic resolves by the same rule, at depth" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  test:
    summary: Gates
    options:
      mix:
        summary: ExUnit
        run: true
YAML
  )"
  authored "$proj" test <<'MD'
the parent topic
MD
  authored "$proj" test.d/mix <<'MD'
the mix sub-topic
MD
  run devbin_run "$proj" help test mix
  assert_success
  assert_output_contains "the mix sub-topic"
  refute_output_contains "the parent topic"
}

@test "a word with no topic behind it stops the descent and the parent answers" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  test:
    summary: Gates
    run: true
YAML
  )"
  authored "$proj" test <<'MD'
the parent topic
MD
  run devbin_run "$proj" help test nosuchthing
  assert_success
  assert_output_contains "the parent topic"
}

@test "with no authored file help <cmd> still answers" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  media:
    summary: Media pipeline
    options:
      covers:
        summary: Rebuild covers
        run: true
YAML
  )"
  run devbin_run "$proj" help media
  assert_success
  # Summary, options and provenance -- never a blank page (AC-07.6).
  assert_output_contains "Media pipeline"
  assert_output_contains "covers"
  assert_output_contains "Rebuild covers"
  assert_output_contains "Resolves from:"
  # A command the PROJECT declared is the project's to document, so the stub
  # says where its page goes. Devbin's no-page sentence is for a built-in, and
  # would be false here: media is no command devbin ships (0113; dropping the
  # built-in half of that test once passed every arm).
  assert_output_contains "No authored detail yet. Write it at bin/.devbin/help/media.md"
  refute_output_contains "devbin ships no page"
}

# ============================================================================
# UNKNOWN vs INACTIVE (AC-07.7)
# ============================================================================

@test "help <unknown> fails, says how to see what exists, and prints no page (0255)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # A command devbin does not ship has no page to print, so help refuses with
  # nothing on stdout (issue 0255).
  run --separate-stderr devbin_run "$proj" help nosuchcommand
  assert_exit_code 2
  [ -z "$output" ] || fail "help printed on stdout for an unknown command: $output"
  [[ "$stderr" == *"unknown command: nosuchcommand (try: bin/devbin help)"* ]] ||
    fail "the refusal does not name the command and how to see what exists: $stderr"
}

# _assert_unoffered_page <proj> <cmd> <reason> -- `help <cmd>` in <proj> exits
# 0 with nothing on stderr, and prints the not-offered line, starting with
# <reason>, then a blank line and devbin's vendored page whole, with nothing
# after it (issue 0255). The last check pins the order, the stream, the page and
# the absent trailer at once; no substring refute of "In this project:" would
# do, since test.md itself holds the words.
_assert_unoffered_page() {
  local page
  page="$(cat "$1/bin/.devbin/lib/pages/$2.md")" || fail "the fixture holds no page for $2"
  [ -n "$page" ] || fail "the fixture's page for $2 is empty, so any output would hold it"
  run --separate-stderr devbin_run "$1" help "$2"
  assert_success
  [ -z "$stderr" ] || fail "help $2 wrote to stderr: $stderr"
  [[ "${output%%$'\n'*}" == "'bin/devbin $2' is not offered here: $3"* ]] ||
    fail "the first line is not the not-offered line: $output"
  [ "${output#*$'\n'}" = $'\n'"$page" ] ||
    fail "the page does not follow that line whole, or something follows it: $output"
}

@test "help on an INACTIVE command explains rather than denying it exists, and prints devbin's page for it under the line saying why (0255)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  # `iex` is an elixir row. In a shell project it is not unknown, it is Elixir's,
  # and the activation rule exists so that the difference is visible. Its page
  # is vendored, so it is printed beneath that (issue 0255).
  _assert_unoffered_page "$proj" iex "this project does not declare the 'elixir' language"
  # And test, whose every option a language scopes, in a project declaring
  # none, where it is not offered at all.
  proj="$(mkproj bare <<'YAML'
project:
  name: bare
YAML
  )"
  _assert_unoffered_page "$proj" test "every option it offers is inactive here"
}

@test "help on an opt-in command prints devbin's page for it under the line naming the key that enables it (0255)" {
  # A reader learns release's release: block before enabling it.
  local cmd
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  for cmd in release publish; do
    _assert_unoffered_page "$proj" "$cmd" "devbin ships it but this project has not enabled it (set commands.$cmd.enabled: true)"
  done
}

@test "help on an opt-in whose cmd/ handler is not executable keeps its refusal, since the chmod it names makes the project own the command (0255)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # The line's own fix, chmod +x, makes release the project's, and help_file
  # withholds devbin's page from a command the project owns: the page would
  # describe code that does not run once the reader acts on it.
  mkdir -p "$proj/bin/.devbin/cmd"
  printf '#!/usr/bin/env bash\n' >"$proj/bin/.devbin/cmd/release"
  chmod 644 "$proj/bin/.devbin/cmd/release"
  run --separate-stderr devbin_run "$proj" help release
  assert_exit_code 2
  [ -z "$output" ] || fail "help printed a page for a handler its fix would make the project's: $output"
  [[ "$stderr" == *"'bin/devbin release' is not available here: bin/.devbin/cmd/release is there but not executable"* ]] ||
    fail "the refusal does not name the handler that is not executable: $stderr"
}

# _assert_flags_answer_as_help <proj> <cmd> [<words>...] -- in <proj>, `<cmd>`
# followed by each <words>, split on spaces, answers exactly as `help <cmd>`
# does: the same stdout, the same stderr and the same exit status, each compared
# whole (issue 0271). With no <words>, they are `--help` and `-h`. Help's
# answer is read first, so the expected bytes are the help verb's own.
_assert_flags_answer_as_help() {
  local proj="$1" cmd="$2" words want_out want_err want_status
  local -a argv
  shift 2
  [ $# -gt 0 ] || set -- --help -h
  run --separate-stderr devbin_run "$proj" help "$cmd"
  want_out="$output" want_err="$stderr" want_status="$status"
  for words in "$@"; do
    read -r -a argv <<<"$words"
    run --separate-stderr devbin_run "$proj" "$cmd" "${argv[@]}"
    [ "$status" -eq "$want_status" ] ||
      fail "$cmd $words exited $status where help $cmd exited $want_status: $stderr"
    [ "$output" = "$want_out" ] ||
      fail "$cmd $words printed on stdout what help $cmd does not: $output"
    [ "$stderr" = "$want_err" ] ||
      fail "$cmd $words wrote to stderr what help $cmd does not: $stderr"
  done
}

@test "a built-in not offered here answers its own --help and -h exactly as help does: the not-offered line and its page, at exit 0 (0271)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # What help prints is 0255's, held by _assert_unoffered_page; the flags must
  # print that answer, not a refusal of their own, in any position, as an
  # offered release and help both read them.
  _assert_unoffered_page "$proj" release "devbin ships it but this project has not enabled it (set commands.release.enabled: true)"
  _assert_flags_answer_as_help "$proj" release --help -h "sub --help" "sub -h"
  # And beside a shared option help discards: a value the option refuses, and
  # a framework option that does not reach release. Help must not fail on
  # either, so neither may the flag.
  proj="$(mkproj shared <<'YAML'
project:
  name: shared
  languages:
    - elixir
options:
  env:
    export: MIX_ENV
    values:
      - dev
      - prod
YAML
  )"
  _assert_unoffered_page "$proj" release "devbin ships it but this project has not enabled it (set commands.release.enabled: true)"
  _assert_flags_answer_as_help "$proj" release "--help --env nope" "--env nope -h" "--iex --help"
}

@test "running a built-in not offered here still refuses at exit 2, and the refusal's one line names help <cmd>, which prints its page (0271)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run --separate-stderr devbin_run "$proj" release
  assert_exit_code 2
  [ -z "$output" ] || fail "release ran in a project that has not enabled it: $output"
  [ "$stderr" = "demo: 'bin/devbin release' is not available here: devbin ships it but this project has not enabled it (set commands.release.enabled: true) (its page: bin/devbin help release)" ] ||
    fail "the refusal is not the one line naming why and help release: $stderr"
}

@test "where help refuses a command not offered here, its --help and -h refuse as help does, and the run's refusal names no page (0271)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # devbin's `use`, which is the machine's: help refuses it with no page, and so
  # do its flags, at help's code rather than the run's.
  run --separate-stderr devbin_run "$proj" help use
  assert_exit_code 2
  _assert_flags_answer_as_help "$proj" use
  # A cmd/ handler that is not executable: help withholds devbin's page, since
  # the chmod +x the line names makes the command the project's.
  mkdir -p "$proj/bin/.devbin/cmd"
  printf '#!/usr/bin/env bash\n' >"$proj/bin/.devbin/cmd/release"
  chmod 644 "$proj/bin/.devbin/cmd/release"
  run --separate-stderr devbin_run "$proj" help release
  assert_exit_code 2
  _assert_flags_answer_as_help "$proj" release
  # And the run names no page there, since help prints none.
  run --separate-stderr devbin_run "$proj" release
  assert_exit_code 2
  [[ "$stderr" != *"(its page:"* ]] ||
    fail "the refusal names a page help does not print: $stderr"
}

@test "an unknown help flag is refused rather than treated as a topic" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run ! devbin_run "$proj" help --bogus
  assert_exit_code 2
  assert_output_contains "unknown help option"
}

@test "help still answers when a shared option value is wrong" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  env:
    export: MIX_ENV
    values:
      - dev
      - prod
YAML
  )"
  # Help is answered BEFORE parse_common_opts on purpose: help is what a person
  # reaches for when they got the value wrong, so it must not fail on one.
  run devbin_run "$proj" help --env nope
  assert_success
  assert_output_contains "Usage:"
}

# ============================================================================
# PREAMBLE AND SHARED OPTIONS (AC-07.8)
# ============================================================================

@test "the preamble renders above the listing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
help:
  tagline: "unified dev launcher for the Demo project"
  preamble: "NOT the product. `demo` is what users install; this drives development of it."
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "unified dev launcher for the Demo project"
  assert_output_contains "NOT the product"
}

@test "declared shared options render with their values and summary" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  env:
    export: MIX_ENV
    summary: set MIX_ENV for this invocation
    values:
      - dev
      - test
      - prod
  json:
    export: DEMO_STYLE
    flag: true
    value: json
    summary: machine-readable output
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Shared options"
  assert_output_matches '--env <dev\|test\|prod>'
  assert_output_contains "set MIX_ENV for this invocation"
  # A flag renders without a value placeholder.
  assert_output_matches '--json  *machine-readable output'
}

@test "a framework option is listed even when config never declares it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # devbin owns --iex and parses it without a config entry. A flag that
  # works and is documented nowhere is the same discoverability failure as a
  # command that runs and is not listed.
  #
  # `languages: [elixir]` is load-bearing and was added when issue 0001 was
  # fixed. A framework option is offered on the same activation axis as the
  # commands that consume it, so this fixture has to speak the language whose
  # surfaces read the flag. Without it the test asserted that framework options
  # ignore activation, which is the defect rather than the contract.
  assert_output_contains "--iex"
}

@test "a framework option is NOT offered where nothing could consume it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Issue 0001. `--iex` selects the IEx variant of a surface, and every surface
  # is elixir-scoped -- so this same output listed all four as not offered here
  # while still advertising the flag that drives them.
  refute_output_contains "--iex"
  refute_output_contains "Shared options"
}

@test "an unoffered framework option is treated like any other unowned flag" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  # Not a special case: devbin does not own `--iex` here, so it is exactly as
  # unknown as any other flag. Parsing and the listing agree because both ask
  # ONE predicate -- an option accepted but never advertised would be the same
  # discoverability failure in the opposite direction.
  run ! devbin_run "$proj" --iex version
  assert_exit_code 2
  assert_output_contains "unknown command"
}

@test "a project may still declare a framework option its languages do not offer" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
options:
  iex:
    flag: true
    export: DEMO_IEX
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # The escape hatch, and the reason scoping the framework default is safe:
  # config declares the option and config always wins on shape. A shell project
  # whose own handler reads the flag says so in one line.
  assert_output_contains "--iex"
}

@test "the alias line appears only when config declares an alias" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  refute_output_contains "short alias"
}

# ============================================================================
# --why (AC-07.9)
# ============================================================================

@test "--why names where each command resolved from" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  fromconfig:
    summary: Declared
    run: true
YAML
  )"
  create_test_command "$proj" fromhandler
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "config commands.fromconfig.run"
  assert_output_contains "project handler"
}

@test "--why explains a command devbin ships and does not offer here" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "Not offered here"
  assert_output_contains "does not declare the 'elixir' language"
}

@test "--why explains an inactive OPTION, not just an inactive command" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
    - elixir
YAML
  )"
  run devbin_run "$proj" help --why
  assert_success
  # `test` is active (shell + elixir), but test.rust is not. Before --why a
  # project where an option was scoped out showed NOTHING at all, which reads
  # as devbin being broken rather than as configuration working.
  assert_output_contains "test rust"
  assert_output_contains "does not declare the 'rust' language"
}

@test "--why names an option the project declared and switched off, not only devbin's own" {
  # `all`'s count line says "help --why names them" for every inactive option,
  # and _print_unavailable walked only the catalogue, so an option declared in
  # config and switched off with enabled: false was counted and never named.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  lint:
    options:
      fast:
        run: "true"
      slow:
        run: "true"
        enabled: false
YAML
  )"
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "lint slow"
  assert_output_contains "disabled in"
  refute_output_contains "lint fast"
}

# _topic_in_an_if <proj> <topic...> -- print_topic asked from inside an `if`,
# where errexit is off, as any caller that tests its answer asks it; the status
# it returned is printed as `topic-rc=<n>`. Through bin/devbin errexit is on, so
# a failing cat already ends the run there and that path cannot show the defect.
_topic_in_an_if() {
  local proj="$1"
  shift
  fixture_run "$proj" 'if print_topic "$@"; then echo "topic-rc=0"; else echo "topic-rc=$?"; fi' "$@"
}

@test "an unreadable shipped page ends print_topic with a failure, and no trailer follows it (0128)" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file, so the fault cannot be staged"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  local page="$proj/bin/.devbin/lib/pages/version.md"
  [ -f "$page" ] || fail "the fixture ships no version page -- the fault would not be staged"

  # The control, with the page readable: the answer and its trailer, rc 0.
  run _topic_in_an_if "$proj" version
  assert_output_contains "topic-rc=0"
  assert_output_contains "In this project:"

  chmod 000 "$page"
  run _topic_in_an_if "$proj" version
  chmod 644 "$page"
  # cat's failure was dropped: the page printed nothing, the whole trailer
  # followed it, and print_topic returned 0 to the `if`.
  assert_output_contains "topic-rc="
  refute_output_contains "topic-rc=0"
  refute_output_contains "In this project:"
}

@test "a command withheld for having nothing to run is ACCOUNTED FOR, not dropped" {
  # A project that declares NO languages. `test` is an `any` row, so it is not
  # language-withheld -- but every gate it ships is language-scoped, so none is
  # active, and command_active withholds it deliberately: an offered `test all`
  # would seal success having run zero gates.
  #
  # Correct to withhold. Wrong to withhold silently, which is what happened:
  # `test` appeared in NEITHER list. Not in the offering, and not under "Not
  # offered here", in the one command whose entire contract is "the listing,
  # plus what is not here and why". `command_unavailable_reason` had no branch
  # for it, because its language is `any` and `project_speaks any` is true.
  #
  # Found in a consumer on a fresh install with `languages:` still commented out.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "Not offered here"
  assert_output_contains "would run nothing"
}

@test "the dispatcher says why, rather than calling a real command unknown" {
  # Same defect, other caller, and the one a person actually hits. `bin/<p> test
  # all` reported "unknown command: test" -- which says devbin has no such
  # command, when it ships one and cannot run it here. Both callers read
  # command_unavailable_reason, so one branch fixes both.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" test all
  assert_failure
  assert_output_contains "would run nothing"
  refute_output_contains "unknown command"
}

@test "--why says so plainly when everything ships" {
  # "EVERYTHING" IS READ FROM THE CATALOGUE, NOT TYPED. The fixture listed the
  # opt-in commands and the languages by hand, so every new opt-in row made the
  # fixture stop enabling everything and turned this test red for a reason that
  # had nothing to do with --why -- ST0007's `release` row did exactly that. An
  # empty read would enable nothing and fail the assertion below, so the floors
  # only make that failure say why.
  local c o lang langs="" enable=""
  for c in $(builtin_commands); do
    [ "$(builtin_command_lang "$c")" = opt-in ] && enable="$enable  $c:
    enabled: true
"
    for o in "" $(builtin_options_for "$c"); do
      lang="$(builtin_option_lang "$c" "$o")"
      case "$lang" in any | opt-in | "") continue ;; esac
      case "$langs" in *"    - $lang"$'\n'*) ;; *) langs="$langs    - $lang
" ;; esac
    done
  done
  [ -n "$enable" ] || fail "the catalogue yielded no opt-in command, so the fixture enables nothing"
  [ -n "$langs" ] || fail "the catalogue yielded no language, so the fixture declares none"
  proj="$(mkproj demo <<YAML
project:
  name: demo
  languages:
$langs
commands:
$enable
YAML
  )"
  # What any option needs in the tree is read from the table, as the languages
  # are read from the catalogue (issue 0156).
  local key need
  while read -r key need; do
    [ -n "$need" ] && mkdir -p "$proj/$need"
  done <<<"$_DEVBIN_BUILTIN_NEEDS"
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "Everything devbin ships is offered here."
}

@test "--why does not change the listing it annotates" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  local plain="$output"
  run devbin_run "$proj" help --why
  assert_success
  # Every line of the plain listing must still be present, in order.
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$output" in
      *"$line"*) ;;
      *)
        fail "--why dropped a line from the plain listing: $line"
        return 1
        ;;
    esac
  done <<<"$plain"
}

# ============================================================================
# DRIFT, BOTH DIRECTIONS (AC-07.10)
# ============================================================================
#
# The reason the generated listing is worth building at all. The corpus bet the
# other way and paid for it in four places at once.

@test "every command the listing names actually resolves" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  deploy:
    summary: Ship it
    group: Ship
    run: true
YAML
  )"
  create_test_command "$proj" media

  # Harvest the command column out of the rendered listing: two-space indent,
  # a name, then the description gutter. Option lines are indented four.
  run devbin_run "$proj" help
  assert_success
  local listed
  listed="$(printf '%s\n' "$output" | sed -n 's/^  \([a-z][a-z0-9_-]*\)\( .*\)\{0,1\}$/\1/p' | sort -u)"
  [ -n "$listed" ] || {
    fail "harvested no commands from:\n$output"
    return 1
  }

  local cmd
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in help | all) continue ;; esac
    run devbin_run "$proj" "$cmd" --devbin-nonexistent-probe
    # Anything but "unknown command" / "not active": the command must RESOLVE.
    # Exit 2 is what the dispatcher returns for unknown or inactive, so it is
    # the exact failure this test exists to catch.
    case "$output" in
      *"unknown command"* | *"is not active"* | *"not available here"*)
        fail "help lists '$cmd' but it does not resolve: $output"
        return 1
        ;;
    esac
  done <<<"$listed"
}

@test "every command that resolves is named in the listing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
    - elixir
commands:
  deploy:
    summary: Ship it
    group: Ship
    run: true
YAML
  )"
  create_test_command "$proj" media

  # known_commands IS the resolution answer, so ask it directly and require the
  # listing to account for every line.
  local resolved
  resolved="$(fixture_ask "$proj" known_commands)" || fail "known_commands exited $?"
  [ -n "$resolved" ] || {
    fail "known_commands produced nothing"
    return 1
  }

  run devbin_run "$proj" help
  assert_success
  local cmd
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$output" in
      *"  $cmd "* | *"  $cmd"$'\n'*)
        ;;
      *)
        fail "'$cmd' resolves but help does not list it:\n$output"
        return 1
        ;;
    esac
  done <<<"$resolved"
}

@test "adding a command to config puts it in help with no second edit" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  refute_output_contains "lateaddition"

  write_config "$proj" <<'YAML'
project:
  name: demo
commands:
  lateaddition:
    summary: Added after the fact
    run: true
YAML
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "lateaddition"
  assert_output_contains "Added after the fact"
}

# ============================================================================
# THE DISPATCHER STAYS THIN (AC-07.12)
# ============================================================================

@test "the dispatcher renders nothing itself" {
  # IN-AG-THIN-COORD-001. Help was 56 lines of printf in bin/devbin, which is
  # the coordinator doing the work instead of calling it.
  run grep -c 'print_help\|_print_row\|print_options' "$DEVBIN_BIN_DIR/devbin"
  assert_output "0"
}

# ============================================================================
# DEVBIN'S SHIPPED PAGES (issue 0113)
# ============================================================================
#
# Devbin's pages for its own built-ins ship under lib/pages/, so every project
# that vendors devbin carries them. Until 0113 they lived in devbin's own
# bin/.devbin/help/, which no install writes, and every vendoring project
# answered `help <built-in>` with the stub: 203 of 272 probes, measured.
#
# EVERY ARM THAT RUNS HELP STANDS IN AN INSTALLED FIXTURE. mkproj installs
# through the real installer, so a fixture holds exactly what vendored_paths
# ships -- and devbin's own checkout, the one tree where a page under
# bin/.devbin/help/ answered, is never the subject. The arm that closed 0112 ran
# only there. Some arms also read devbin's source, each for one thing: the
# catalogue arm compares the fixture's pages with the ones the source ships, the
# trailer arm reads the catalogue to hold its premise, and the arm holding a
# shipped page to no docs/ or intent/ path reads the pages' text.
#
# AN ASSERTION ON A WORD A SHIPPED PAGE CAN SAY IS SATISFIED BY THE PAGE, NOT BY
# THE CODE UNDER TEST. check.md's prose quotes "In this project:" and says an
# option is "disabled", so both substring assertions passed with the trailer's
# header, or its reason, gone.
# What the trailer prints is matched as whole lines.

# _output_line <ERE> -- some whole line of $output matches <ERE>.
_output_line() {
  grep -qxE -e "$1" <<<"$output"
}

# _all_builtins_config -- config that activates every built-in: both
# languages a built-in is scoped to, and every opt-in enabled.
_all_builtins_config() {
  cat <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - rust
commands:
  precommit:
    enabled: true
  content:
    enabled: true
  release:
    enabled: true
  macos:
    enabled: true
  formula:
    enabled: true
  publish:
    enabled: true
  which:
    enabled: true
YAML
}

@test "every built-in answers with devbin's shipped page or an honest stub, and the two cover the catalogue (0113)" {
  local cmd page names shipped differ pages=0 total=0 inactive="" wrong=""
  local src="$DEVBIN_LIB_DIR/pages"
  proj="$(_all_builtins_config | mkproj demo)"
  # Everything active means what the options need is there too (issue 0156).
  local key need
  while read -r key need; do
    [ -n "$need" ] && mkdir -p "$proj/$need"
  done <<<"$_DEVBIN_BUILTIN_NEEDS"
  local dst="$proj/bin/.devbin/lib/pages" devsrc where wdst
  devsrc="$(mkdevsrc)"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    total=$((total + 1))
    # `use` IS ASKED OF A CHECKOUT: a project does not offer it (issue 0213),
    # so its page answers in devbin's own tree, from the same shipped pages.
    where="$proj" wdst="$dst"
    if [ "$cmd" = use ]; then where="$devsrc" wdst="$devsrc/lib/pages"; fi
    # STDOUT, AND ONLY STDOUT: `help build | less` has to carry the page. A
    # plain `run` merges stderr into $output, so a page or a stub sent to
    # stderr passed every arm.
    run --separate-stderr devbin_run "$where" help "$cmd"
    if [ "$status" -ne 0 ]; then
      inactive="$inactive $cmd:$status"
      continue
    fi
    # A built-in the fixture does not offer answers too, at exit 0, with its
    # page under the line saying why (issue 0255), so that line is the
    # fixture's failure to activate it, named as such.
    case "$output" in "'bin/devbin $cmd' is not offered here: "*)
      inactive="$inactive $cmd:not-offered"
      continue
      ;;
    esac
    [ -z "$stderr" ] || wrong="$wrong $cmd:stderr"
    page="$wdst/$cmd.md"
    if [ -f "$page" ]; then
      pages=$((pages + 1))
      # The page whole, then the trailer, and never the stub. An empty page
      # would pass the whole-page match, since it matches every output, so a
      # placeholder page is refused by name.
      [ -s "$page" ] || wrong="$wrong $cmd:empty-page"
      case "$output" in "$(cat "$page")"*) ;; *) wrong="$wrong $cmd:not-the-page" ;; esac
      _output_line 'In this project:' || wrong="$wrong $cmd:no-trailer"
      case "$output" in *"No authored detail yet"*) wrong="$wrong $cmd:stub" ;; esac
    else
      # Honest: devbin says it ships no page, and never tells the project to
      # write devbin's -- which is what every one of these said until 0113.
      case "$output" in *"devbin ships no page for $cmd"*) ;; *) wrong="$wrong $cmd:not-honest" ;; esac
      case "$output" in *"Write it at"*) wrong="$wrong $cmd:write-it-at" ;; esac
    fi
  done <<EOF
$(builtin_commands)
EOF
  [ -z "$inactive" ] || fail "the fixture does not activate (command:status or not-offered):$inactive -- a built-in it cannot reach is one this arm never checked"
  [ -z "$wrong" ] || fail "wrong answers:$wrong"
  # THE DENOMINATORS. Every built-in was asked and none was refused or
  # answered as not offered, which is the inactive check above, and the
  # catalogue is not empty.
  # And the fixture holds EXACTLY the pages devbin's source ships, names and
  # bytes, compared with the source rather than with a count: a floor alone is
  # how 0112 closed on 16 of 28, and an installer that dropped one page while
  # 0115 added another passed every arm on counts.
  [ "$total" -gt 0 ] || fail "builtin_commands listed nothing -- the arm would check nothing"
  [ -d "$src" ] || fail "devbin's source has no $src"
  [ -d "$dst" ] || fail "the fixture has no lib/pages/ -- the installer vendored no page"
  differ="$(diff -r "$src" "$dst" 2>&1)" ||
    fail "the fixture's pages are not the pages devbin ships:\n$differ"
  names="$(find "$src" -maxdepth 1 -type f -name '*.md')" || fail "could not list $src"
  # grep -c exits 1 on a count of zero, which the every-built-in check below
  # reports; any other failure leaves $shipped empty and fails here.
  shipped="$(printf '%s\n' "$names" | grep -c .)" || [ "$shipped" = 0 ]
  # Every page devbin ships answered as some built-in's page, and none is
  # left over for a command the catalogue does not have.
  [ "$pages" -eq "$shipped" ] || fail "$pages built-ins answered with a page, and devbin ships $shipped"
  # A PAGE DELETED FROM THE SOURCE, which the comparison above cannot see since
  # both sides lose it, leaves its built-in answering with the stub, which the
  # check below sees.
  # AND EVERY BUILT-IN HAS ONE (0115). A built-in added without a page answers
  # with the stub, which is honest and still a gap: the one arm that can see
  # it is this one, since the stub's own arm deletes a page to reach it.
  [ "$pages" -eq "$total" ] || fail "$((total - pages)) of $total built-ins answered with the stub -- every built-in ships a page"
}

@test "a project's own page wins over devbin's, printed whole with no trailer (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  authored "$proj" upgrade <<'MD'
demo's own upgrade page.
MD
  run devbin_run "$proj" help upgrade
  assert_success
  [ "$output" = "demo's own upgrade page." ] || fail "expected the project's page alone, got: $output"
}

# A built-in the project OWNS runs the project's code, so devbin's page for it
# would describe something that does not run there. Measured: Intent's
# `vendor` is its own handler, another consumer's and Intent's `build` are, and a third
# declares commands.build.run. Each of the facts that make a command the
# project's is driven, so a predicate that dropped one would go red.
_owned_help() {
  local proj="$1" cmd="$2"
  run devbin_run "$proj" help "$cmd"
  assert_success
  assert_output_contains "No authored detail yet. Write it at"
  refute_output_contains "In this project:"
  refute_output_contains "devbin ships no page"
}

@test "a built-in the project owns by a handler answers with the generated page, not devbin's (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" vendor >/dev/null
  _owned_help "$proj" vendor
  assert_output_contains "Resolves from: project handler bin/.devbin/cmd/vendor"
}

@test "a built-in the project owns by a mapped handler answers with the generated page, not devbin's (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  vendor:
    handler: myvendor
YAML
  )"
  create_test_command "$proj" myvendor >/dev/null
  _owned_help "$proj" vendor
  assert_output_contains "(mapped)"
}

@test "a built-in the project owns by a command-level run: answers with the generated page, not devbin's (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    run: "true"
YAML
  )"
  _owned_help "$proj" build
  assert_output_contains "Resolves from: config commands.build.run"
}

@test "a built-in devbin ships no page for gets the honest stub, on stdout, never an instruction to write devbin's (0113)" {
  # ITS OWN ARM, because the catalogue arm reaches the stub only through the
  # built-ins that have no page: since 0115 gave all 28 one, that branch
  # runs zero times and stays green. Deleting one page from the fixture makes
  # the case whatever devbin ships.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  rm "$proj/bin/.devbin/lib/pages/version.md"
  run --separate-stderr devbin_run "$proj" help version
  assert_success
  [ -z "$stderr" ] || fail "help version wrote to stderr: $stderr"
  assert_output_contains "Resolves from: devbin lib/cmd/version"
  assert_output_contains "No authored detail yet: devbin ships no page for version."
  refute_output_contains "Write it at"
  refute_output_contains "In this project:"
}

@test "the project's page answers a sub-topic even where devbin ships a deeper one (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  authored "$proj" test <<'MD'
demo's own test page.
MD
  # PLANTED, not shipped: devbin ships no test sub-page today. The
  # rule under test is the order of the two roots -- the first whose walk ends
  # on a file answers, the project's first -- and it needs a deeper devbin page
  # to have something to lose to.
  mkdir -p "$proj/bin/.devbin/lib/pages/test.d"
  printf 'a planted devbin sub-page\n' >"$proj/bin/.devbin/lib/pages/test.d/mix.md"
  run devbin_run "$proj" help test mix
  assert_success
  [ "$output" = "demo's own test page." ] || fail "expected the project's page alone, got: $output"
}

@test "with no project page, devbin's own sub-page answers its sub-topic, followed by the trailer (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # PLANTED, as in the arm above. Devbin's walk descends as the project's does,
  # so `help test mix` answers from test.d/mix.md, not from test.md -- and the
  # sub-page is devbin's, so the trailer follows it.
  mkdir -p "$proj/bin/.devbin/lib/pages/test.d"
  printf 'a planted devbin sub-page\n' >"$proj/bin/.devbin/lib/pages/test.d/mix.md"
  run devbin_run "$proj" help test mix
  assert_success
  case "$output" in
    'a planted devbin sub-page'$'\n\n''In this project:'$'\n'*) ;;
    *) fail "expected the planted sub-page, then the trailer, got: $output" ;;
  esac
}

@test "the trailer names what this project added, overrode and switched off, with each origin (0113)" {
  local shipped
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    options:
      compile:
        summary: The project's own gate
        run: "true"
      format:
        run: "true"
      bats:
        summary: The project's own suite
        run: "true"
      deps:
        enabled: false
YAML
  )"
  # THE PREMISE, HELD: bats is no option devbin ships for check, so here it is
  # ADDED, while compile and format are devbin's, so here they are OVERRIDDEN.
  shipped=" $(builtin_options_for check | tr '\n' ' ') "
  case "$shipped" in *" bats "*) fail "devbin now ships check bats -- add an option it does not ship" ;; esac
  case "$shipped" in *" compile "*) ;; *) fail "devbin no longer ships check compile -- nothing here is overridden" ;; esac
  case "$shipped" in *" format "*) ;; *) fail "devbin no longer ships check format -- nothing here is overridden" ;; esac
  run devbin_run "$proj" help check
  assert_success
  _output_line 'In this project:' || fail "no trailer after check's page"
  # Added, and overridden: the page above describes devbin's gates, so only
  # the trailer can say these run the project's command lines.
  _output_line ' +from: config commands\.check\.options\.bats\.run' || fail "the added option's origin is missing"
  _output_line ' +from: config commands\.check\.options\.compile\.run' || fail "compile's origin is missing"
  _output_line ' +from: config commands\.check\.options\.format\.run' || fail "format's origin is missing"
  # Switched off: NAMED WITH ITS REASON, not merely absent. An option
  # missing from a list reads exactly like one that never existed. The whole
  # row, because the word alone is in check.md's prose.
  _output_line '  check deps +it is disabled in .+' || fail "check deps is not named with its reason"
}

@test "the trailer is narrowed to its own command, and makes no claim about the catalogue (0113)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    options:
      deps:
        enabled: false
  test:
    options:
      credo:
        enabled: false
YAML
  )"
  # THE CONTROL: the walk the trailer narrows does name test credo here, so the
  # refusals below are the narrowing at work, not a fixture with nothing to leak.
  run devbin_run "$proj" help --why
  assert_success
  assert_output_contains "test credo"
  # A command's own switched-off options, and only its own: test credo belongs
  # to test's page and to --why, never to check's.
  run devbin_run "$proj" help check
  assert_success
  _output_line '  check deps +it is disabled in .+' || fail "check deps is not named with its reason"
  refute_output_contains "test credo"
  # A narrowed walk that finds nothing says nothing -- in particular not --why's
  # closing line, which is a claim about the whole catalogue and false here.
  # THE PREMISE IS HELD, NOT ASSUMED: upgrade has nothing
  # switched off in this project, the one case that line could print in. If
  # upgrade gains an option not offered here, this goes red on the premise
  # rather than passing vacuously; move it to a command that still has none.
  # fmt never qualifies in an elixir project: its walk always names fmt rust
  # and fmt swift.
  run devbin_run "$proj" help upgrade
  assert_success
  _output_line 'In this project:' || fail "no trailer after upgrade's page"
  refute_output_contains "Not offered here:"
  refute_output_contains "test credo"
  refute_output_contains "Everything devbin ships is offered here."
}

# _page_breaches <file> -- what a SHIPPED page may not say, one line per
# breach. A shipped page answers in every vendored project, so a path into
# devbin's source, devbin's own config, or an issue number without its tracker
# is false or unfindable wherever it is read. The shapes:
#   - a docs/, intent/ or tests/ path: devbin's source, absent in a vendored
#     project. tests/ is broad on purpose. It also catches a Rust project's
#     tests/*.rs, which a page words around, because a false alarm is seen and
#     reworded and a miss is silent;
#   - a bare lib/ path: devbin's source layout. A vendored project carries it
#     under bin/.devbin/lib/, and that spelling, with a slash before lib/, is
#     not a breach;
#   - .lib/ and shell-gate: devbin's own handler library and its gate script;
#   - an issue number, either case, with or without #: a page cites
#     devbin#NNNN, which names the tracker.
# grep's status 1 means no breach. Its status 2 means it could not read the page,
# and is returned, so an unreadable page is never reported clean.
_page_breaches() {
  grep -nE '(^|[^A-Za-z0-9_.-])(docs|intent|tests)/|(^|[^A-Za-z0-9_./-])lib/|\.lib/|shell-gate|(^|[^#A-Za-z])[Ii]ssues? #?[0-9]{4}' "$1" ||
    [ $? -eq 1 ]
}

@test "a shipped page names no docs/, intent/, tests/, lib/ or .lib/ path, no shell-gate and no unqualified issue number (0113)" {
  local f n=0 all hits="" probe line
  # POSITIVE CONTROL: each forbidden shape, planted, is found -- so a clean
  # result below is the checker finding nothing, not the checker unable to.
  probe="$DEVBIN_TEST_TMPDIR/probe.md"
  for line in 'see docs/releasing.md' 'written under intent''/st/' 'tests/unit/help.bats' \
    'see lib/cmd/fmt' '(`lib/pages/`)' 'the shell-gate script' 'bin/.devbin/cmd/.lib/x' \
    'fixed in issue 0112' 'Issue 0112 is fixed' 'fixed in issue #0113' 'see issues 0112 and 0113'; do
    printf '%s\n' "$line" >"$probe"
    [ -n "$(_page_breaches "$probe")" ] || fail "the checker missed a planted breach: $line"
  done
  # And what a page may say is not flagged: a qualified citation, and the
  # vendored runtime's own path in a vendored project.
  for line in 'fixed in devbin#0112, see bin/devbin devbin' 'writes bin/.devbin/lib/ and the manifest'; do
    printf '%s\n' "$line" >"$probe"
    [ -z "$(_page_breaches "$probe")" ] || fail "the checker flags what a page may say: $line"
  done
  # And a page grep cannot read fails, rather than reading as clean.
  ! _page_breaches "$DEVBIN_TEST_TMPDIR/no-such-page.md" 2>/dev/null ||
    fail "the checker reads a page it cannot open as clean"
  for f in "$DEVBIN_LIB_DIR"/pages/*.md "$DEVBIN_LIB_DIR"/pages/*.d/*.md; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    probe="$(_page_breaches "$f")" || fail "could not read $f"
    [ -z "$probe" ] || hits="$hits\n${f#"$DEVBIN_LIB_DIR"/}: $probe"
  done
  # A REFERENT, since this arm reads the source and has no fixture to compare it
  # with: every page a find sees under lib/pages/ was read by the glob above. A
  # page deleted from the source is the shipped-pages arm's, which requires
  # every built-in's page (0115).
  all="$(find "$DEVBIN_LIB_DIR/pages" -type f -name '*.md' | grep -c .)" || all=0
  [ "$n" -gt 0 ] && [ "$n" -eq "$all" ] ||
    fail "read $n pages under lib/pages/, where a find lists $all -- the glob above no longer finds them all"
  [ -z "$hits" ] || fail "a shipped page names something only devbin's tree has:$hits"
}

@test "a declared --iex with no summary of its own keeps devbin's, and a project's own option borrows nothing (0136)" {
  # Declaring options.iex.commands, which is how a project handler becomes a
  # reader, printed --iex with nothing beside it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
options:
  iex:
    commands:
      - server
  fidelity:
    values:
      - low
      - high
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_matches '--iex +Start the server in IEx rather than plain'
  # THE CONTROL: an option devbin does not own has no summary to fall back to.
  local line re='^ +--fidelity <low[|]high> *$'
  line="$(printf '%s\n' "$output" | grep -E '^ +--fidelity ')" || fail "help has no --fidelity row: $output"
  [[ "$line" =~ $re ]] || fail "--fidelity borrowed a summary: $line"
}
