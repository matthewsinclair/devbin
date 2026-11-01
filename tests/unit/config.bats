#!/usr/bin/env bats
# config.bats - lib/config, the devbin configuration reader (WP-03)
#
# Covers the accepted subset, every rejection the grammar promises, the
# accessors, and schema validation. The rejection tests carry the weight: a
# reader that silently misreads a malformed config is worse than one that
# refuses it, so each malformed input must fail AND name what was wrong.

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
}
teardown() { devbin_teardown; }

# Parse from a heredoc. Returns the reader's exit status so rejection tests can
# assert on it.
parse() {
  cfg_load_string
}

# ============================================================================
# ACCEPTED GRAMMAR
# ============================================================================

@test "reads a flat scalar map" {
  parse <<'YAML'
project:
  name: myapp
  alias: cf
YAML
  [ "$(cfg_get project.name)" = "myapp" ]
  [ "$(cfg_get project.alias)" = "cf" ]
}

@test "reads arbitrarily nested maps" {
  parse <<'YAML'
commands:
  test:
    options:
      mix:
        run: mix test
        grammar: mix
YAML
  [ "$(cfg_get commands.test.options.mix.run)" = "mix test" ]
  [ "$(cfg_get commands.test.options.mix.grammar)" = "mix" ]
}

@test "reads scalar sequences as numbered paths" {
  parse <<'YAML'
help:
  groups:
    - Surfaces
    - Build
    - Test
YAML
  [ "$(cfg_get help.groups.0)" = "Surfaces" ]
  [ "$(cfg_get help.groups.1)" = "Build" ]
  [ "$(cfg_get help.groups.2)" = "Test" ]
}

@test "values keep their internal spacing and punctuation" {
  parse <<'YAML'
commands:
  check:
    run: mix compile --warnings-as-errors --force
YAML
  [ "$(cfg_get commands.check.run)" = "mix compile --warnings-as-errors --force" ]
}

@test "strips surrounding single and double quotes" {
  parse <<'YAML'
project:
  name: "myapp"
  alias: 'cf'
YAML
  [ "$(cfg_get project.name)" = "myapp" ]
  [ "$(cfg_get project.alias)" = "cf" ]
}

@test "a value may contain a colon" {
  parse <<'YAML'
help:
  preamble: "NOT the product: this drives development of it"
YAML
  [ "$(cfg_get help.preamble)" = "NOT the product: this drives development of it" ]
}

@test "strips comments but keeps a # inside a quoted value" {
  parse <<'YAML'
# leading comment
project:
  name: myapp    # trailing comment
  alias: "cf#1"
YAML
  [ "$(cfg_get project.name)" = "myapp" ]
  [ "$(cfg_get project.alias)" = "cf#1" ]
}

@test "skips blank lines and the document marker" {
  parse <<'YAML'
---

project:

  name: myapp
YAML
  [ "$(cfg_get project.name)" = "myapp" ]
}

@test "dedent resumes the correct parent path" {
  parse <<'YAML'
commands:
  test:
    options:
      mix:
        run: mix test
  check:
    run: mix compile
project:
  name: myapp
YAML
  [ "$(cfg_get commands.test.options.mix.run)" = "mix test" ]
  [ "$(cfg_get commands.check.run)" = "mix compile" ]
  [ "$(cfg_get project.name)" = "myapp" ]
}

@test "parses the shipped reference config" {
  # Called directly, NOT through `run`: `run` executes in a subshell, so the
  # cache cfg_load populates would die with it and every cfg_get below would
  # read empty. The same trap applies to piping into cfg_load_string.
  cfg_load "$DEVBIN_LIB_DIR/config.reference.yaml"
  [ "$(cfg_get project.name)" = "demo" ]
  [ "$(cfg_get commands.test.options.swift.in_all)" = "false" ]
  [ "$(cfg_get commands.ls.handler)" = "myls" ]
  # Both directions of `enabled`, since the reference now demonstrates both: a
  # built-in switched OFF, and an opt-in one switched ON.
  [ "$(cfg_get commands.precommit.enabled)" = "false" ]
  [ "$(cfg_get commands.publish.enabled)" = "true" ]
  [ "$(cfg_get project.version_sidecars.0)" = "native/cli/Cargo.toml" ]
}

@test "the shipped reference config passes schema validation" {
  cfg_load "$DEVBIN_LIB_DIR/config.reference.yaml"
  run cfg_validate
  assert_success
}

# ============================================================================
# REJECTED GRAMMAR
#
# Each must fail AND say why. A refusal with no reason is a support ticket.
# ============================================================================

@test "rejects tabs" {
  run parse <<'YAML'
project:
	name: myapp
YAML
  assert_failure
  assert_output_contains "tabs are not permitted"
}

@test "rejects odd indent" {
  run parse <<'YAML'
project:
   name: myapp
YAML
  assert_failure
  assert_output_contains "multiple of 2 spaces"
}

@test "rejects a jumped indent level" {
  run parse <<'YAML'
project:
      name: myapp
YAML
  assert_failure
  assert_output_contains "indent jumps"
}

@test "rejects duplicate keys" {
  run parse <<'YAML'
project:
  name: myapp
  name: shop
YAML
  assert_failure
  assert_output_contains "duplicate key"
}

@test "rejects anchors and aliases" {
  run parse <<'YAML'
defaults:
  run: &base mix test
YAML
  assert_failure
  assert_output_contains "anchors and aliases"
}

@test "rejects block scalars" {
  run parse <<'YAML'
help:
  preamble: |
    a long
    preamble
YAML
  assert_failure
  assert_output_contains "block scalars"
}

@test "rejects flow collections" {
  run parse <<'YAML'
help:
  groups: [Surfaces, Build]
YAML
  assert_failure
  assert_output_contains "flow collections"
}

@test "rejects sequences of maps" {
  run parse <<'YAML'
commands:
  - name: server
    run: mix phx.server
YAML
  assert_failure
  assert_output_contains "sequences of maps"
}

@test "rejects a key nested under a key that already has a value (0143)" {
  # It parsed to BOTH rows. The reader's first answer at the path is the value,
  # so the nested key reached the cache and nothing read it -- in an infra
  # profile, `dmarc: none` with a policy indented under it named the domain as
  # opted out and never compared the policy.
  run parse <<'YAML'
project:
  name: myapp
    alias: cf
YAML
  assert_failure
  assert_output_contains ":3: \`project.name\` already has a value, so nothing can be nested under it"
}

@test "rejects a key nested under a sequence item (0143)" {
  # It parsed to a path with an EMPTY segment, `project.languages..foo`, which
  # no accessor can reach.
  run parse <<'YAML'
project:
  languages:
    - elixir
      foo: bar
YAML
  assert_failure
  assert_output_contains ":4: \`project.languages.0\` already has a value, so nothing can be nested under it"
}

@test "rejects a sequence nested under a sequence item (0143)" {
  # The sequence branch was exempt from the nesting refusal, and under a KEY
  # the duplicate-key refusal covers it. Under an ITEM nothing did: the path
  # lost its segment and flattened to `project.languages..0`.
  run parse <<'YAML'
project:
  languages:
    - elixir
      - rust
YAML
  assert_failure
  assert_output_contains ":4: \`project.languages.0\` already has a value, so nothing can be nested under it"
}

@test "rejects a line that is neither key-value nor sequence item" {
  run parse <<'YAML'
project
  name: myapp
YAML
  assert_failure
  assert_output_contains "expected"
}

@test "rejects a key with illegal characters" {
  run parse <<'YAML'
project:
  my name: myapp
YAML
  assert_failure
  assert_output_contains "may contain only"
}

@test "errors name the line number" {
  run parse <<'YAML'
project:
  name: myapp
  alias:	cf
YAML
  assert_failure
  assert_output_contains ":3:"
}

@test "rejects a missing config file by path" {
  run cfg_load "$DEVBIN_TEST_TMPDIR/nope.yaml"
  assert_failure
  assert_output_contains "no such config file"
}

# ============================================================================
# ACCESSORS
# ============================================================================

@test "cfg_get returns the default for an absent path" {
  parse <<'YAML'
project:
  name: myapp
YAML
  [ "$(cfg_get project.alias)" = "" ]
  [ "$(cfg_get project.alias cf)" = "cf" ]
  [ "$(cfg_get totally.absent fallback)" = "fallback" ]
}

@test "cfg_get does not prefix-match a longer path" {
  parse <<'YAML'
commands:
  test:
    run: mix test
YAML
  [ "$(cfg_get commands.te)" = "" ]
  [ "$(cfg_get commands.test)" = "" ]
  [ "$(cfg_get commands.test.run)" = "mix test" ]
}

@test "cfg_has distinguishes a set value from an absent one" {
  parse <<'YAML'
project:
  name: myapp
YAML
  cfg_has project.name
  ! cfg_has project.alias
}

@test "cfg_list gives immediate children in document order" {
  parse <<'YAML'
commands:
  server:
    run: mix phx.server
  test:
    options:
      mix:
        run: mix test
      credo:
        run: mix credo
  check:
    run: mix compile
YAML
  run cfg_list commands
  assert_success
  assert_output "server
test
check"
}

# No backticks in a @test name: BATS evaluates the name, so backticks become
# command substitution and the shell tries to run whatever is inside them.
@test "cfg_list on a nested path gives the option list that all is built from" {
  parse <<'YAML'
commands:
  test:
    options:
      mix:
        run: mix test
      credo:
        run: mix credo
      rust:
        run: cargo test
YAML
  run cfg_list commands.test.options
  assert_success
  assert_output "mix
credo
rust"
}

@test "cfg_list de-duplicates children with several leaves each" {
  parse <<'YAML'
commands:
  test:
    summary: gates
    group: Test
    run: mix test
YAML
  run cfg_list commands
  assert_success
  assert_output "test"
}

@test "cfg_list with an empty prefix gives the top-level keys" {
  parse <<'YAML'
project:
  name: myapp
devbin_version: "^1.0.0"
commands:
  test:
    run: mix test
YAML
  run cfg_list ""
  assert_success
  assert_output "project
devbin_version
commands"
}

@test "cfg_list returns nothing for an absent path" {
  parse <<'YAML'
project:
  name: myapp
YAML
  run cfg_list commands
  assert_success
  assert_output ""
}

# ============================================================================
# SCHEMA VALIDATION
# ============================================================================

@test "validation requires project.name" {
  parse <<'YAML'
project:
  alias: cf
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "required key missing: project.name"
}

@test "validation rejects an unknown key" {
  parse <<'YAML'
project:
  name: myapp
  nmae: typo
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: project.nmae"
}

@test "validation rejects a misspelled command key" {
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    sumary: typo
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: commands.test.sumary"
}

@test "validation rejects a key nested deeper than the schema allows" {
  # The regression test for the glob-matching bug: with `commands.*.summary` as
  # a case pattern this validated clean, because `*` spans dots.
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    options:
      mix:
        extra:
          summary: too deep
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: commands.test.options.mix.extra.summary"
}

@test "validation rejects an option-level key used at command level" {
  # `in_all` describes one option's membership of a synthesised `all`, so it is
  # meaningless on the command that owns the `all`.
  #
  # This used to assert on `grammar`, which WP-14 made legal at command level: a
  # command-level `run:` seals on exactly the terms an option-level one does
  # (one level up), so it needs a grammar of its own. The RULE being held
  # down is that levels do not blur, not that any particular key stays put.
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    in_all: false
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: commands.test.in_all"
}

@test "validation rejects a command-level key used at option level" {
  # The other direction. `group` places a COMMAND in the help listing; an option
  # is listed under its command and has no group of its own.
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    options:
      mix:
        group: Test
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: commands.test.options.mix.group"
}

# AT-6.2
@test "validation refuses a platforms: value that is not a platform word, naming the key and the value, accepts the words, and reads a single word not written as a list as an unknown key (ST0011 WP-17, AC-6.2)" {
  local w yaml words=()
  read -r -a words <<<"$_DEVBIN_PLATFORM_WORDS"
  [ "${#words[@]}" -gt 0 ] || fail "lib/helpers states no platform words"
  # Not piped: parse loads a shell variable, which a pipeline's subshell drops.
  yaml="$(printf '%s\n' 'project:' '  name: myapp' 'commands:' '  test:' '    options:' '      app:' '        platforms:'
    for w in "${words[@]}"; do printf '          - %s\n' "$w"; done)"
  parse <<<"$yaml"
  run cfg_validate
  assert_success
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    options:
      app:
        platforms:
          - macos
          - windows
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "commands.test.options.app.platforms.1: \"windows\" is not a platform word -- use one of: $_DEVBIN_PLATFORM_WORDS"
  # Every word in one item, spaced, is none of them: read as a platform, it
  # would hold the option back on every host.
  [ "${#words[@]}" -gt 1 ] || fail "lib/helpers states one platform word, so no item can hold two"
  yaml="$(printf '%s\n' 'project:' '  name: myapp' 'commands:' '  test:' '    options:' '      app:' '        platforms:' "          - ${words[*]}")"
  parse <<<"$yaml"
  run cfg_validate
  assert_failure
  assert_output_contains "commands.test.options.app.platforms.0: \"${words[*]}\" is not a platform word"
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    options:
      app:
        platforms: macos
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: commands.test.options.app.platforms"
}

@test "validation requires sequence indices to be numeric" {
  parse <<'YAML'
project:
  name: myapp
help:
  groups:
    surfaces: yes
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "unknown key: help.groups.surfaces"
}

@test "validation accepts project.languages as a sequence" {
  parse <<'YAML'
project:
  name: devbin
  languages:
    - shell
    - lua
YAML
  run cfg_validate
  assert_success
  [ "$(cfg_get project.languages.0)" = "shell" ]
  [ "$(cfg_get project.languages.1)" = "lua" ]
}

@test "validation accepts enabled at option level" {
  parse <<'YAML'
project:
  name: myapp
commands:
  test:
    options:
      lua:
        enabled: false
YAML
  run cfg_validate
  assert_success
  [ "$(cfg_get commands.test.options.lua.enabled)" = "false" ]
}

# ============================================================================
# BOOLEAN VALUES (issue 0080)
#
# A key devbin reads as a yes or a no takes the words lib/helpers owns and
# nothing else. `enabled: off` is neither word: a built-in stayed active and an
# opt-in stayed off, and nothing said so. The validator refuses it by name.
# ============================================================================

# One config with a single boolean key set to a value, validated.
bool_config() {
  local path="$1" value="$2"
  case "$path" in
    commands.enabled)
      parse <<YAML
project:
  name: demo
commands:
  test:
    enabled: $value
YAML
      ;;
    commands.options.enabled | commands.options.in_all)
      parse <<YAML
project:
  name: demo
commands:
  test:
    options:
      bats:
        ${path##*.}: $value
YAML
      ;;
    options.flag)
      parse <<YAML
project:
  name: demo
options:
  iex:
    flag: $value
YAML
      ;;
  esac
}

@test "0080: enabled: off on a built-in is refused, naming the key, the value and the words" {
  parse <<'YAML'
project:
  name: demo
commands:
  test:
    enabled: off
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "commands.test.enabled"
  assert_output_contains "off"
  assert_output_contains "$_DEVBIN_TRUE_WORDS"
  assert_output_contains "$_DEVBIN_FALSE_WORDS"
}

@test "0080: enabled: off on an opt-in command is refused" {
  parse <<'YAML'
project:
  name: demo
commands:
  publish:
    enabled: off
YAML
  run cfg_validate
  assert_failure
  assert_output_contains "commands.publish.enabled"
}

@test "0080: every boolean key refuses a word outside the lists" {
  local path value
  for path in commands.enabled commands.options.enabled commands.options.in_all options.flag; do
    for value in off on True YES enable '""'; do
      bool_config "$path" "$value"
      if cfg_validate 2>/dev/null; then
        echo "accepted $path: $value" >&2
        return 1
      fi
    done
  done
}

@test "0080: every boolean key accepts every word in both lists" {
  local path value
  for path in commands.enabled commands.options.enabled commands.options.in_all options.flag; do
    for value in $_DEVBIN_TRUE_WORDS $_DEVBIN_FALSE_WORDS; do
      bool_config "$path" "$value"
      cfg_validate || {
        echo "refused $path: $value" >&2
        return 1
      }
    done
  done
}

@test "0080 CONTROL: log: takes a suffix word, at command and option level" {
  # `log:` reads the true and false words but takes any other word as a log
  # suffix (gate_log_suffix), so it is not a boolean key.
  parse <<'YAML'
project:
  name: demo
commands:
  test:
    run: bats tests
    log: MYSUFFIX
    options:
      bats:
        run: bats tests
        log: OTHER
YAML
  run cfg_validate
  assert_success
}

@test "0080 CONTROL: options.<name>.value is free text" {
  # server's --iex reads its value as a boolean, but other options export any
  # value, so the key is not a boolean key.
  parse <<'YAML'
project:
  name: demo
options:
  style:
    flag: true
    value: compact
    export: DEMO_STYLE
YAML
  run cfg_validate
  assert_success
}

@test "0080: every config key the runtime reads as a boolean is a boolean key to the validator" {
  # The readers and the validator hold one key set between them only if a new
  # reader cannot land without the validator knowing its key. Each reader is
  # `is_true_word "$(cfg_get "<path>" ...` or the false form; the path's
  # variable segments become concrete names.
  local found=0 path probe bad=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    found=$((found + 1))
    probe="$(printf '%s' "$path" | sed -E 's/\$\{?[A-Za-z0-9_]+\}?/x/g')"
    _cfg_path_boolean "$probe" || bad="$bad $path"
  done <<EOF
$(grep -rhoE 'is_(true|false)_word "\$\(cfg_get "[^"]+"' "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin/devbin" | sed -E 's/.*cfg_get "//; s/"$//' | sort -u)
EOF
  # Guard the extractor: an empty set would compare nothing and pass.
  [ "$found" -gt 0 ] || fail "found no boolean reader under lib/ or bin/devbin -- the arm would compare nothing"
  # AND IT MISSES NO READER: every code line under lib/ and bin/devbin that
  # reads a boolean word through cfg_get, found by a looser second route, is one
  # the extractor's pattern matches, so a reader written another way is named.
  local readers unmatched
  readers="$(grep -rhE 'is_(true|false)_word.*cfg_get' "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin/devbin" | grep -vE '^[[:space:]]*#')" || true
  unmatched="$(grep -vE 'is_(true|false)_word "\$\(cfg_get "[^"]+"' <<<"$readers")" || true
  [ -z "$unmatched" ] || fail "a boolean reader the extractor does not match:\n$unmatched"
  [ -z "$bad" ] || {
    echo "read as a boolean, unknown to _cfg_path_boolean:$bad" >&2
    return 1
  }
}

@test "0080: validation without lib/helpers refuses rather than reading every value as wrong" {
  run bash -c '
    . "'"$DEVBIN_LIB_DIR"'/config"
    cfg_load_string <<YAML
project:
  name: demo
commands:
  test:
    enabled: true
YAML
    cfg_validate
  '
  assert_failure
  assert_output_contains "lib/helpers"
  refute_output_contains "commands.test.enabled"
}

@test "parses Devbin's own config, the dogfooding case" {
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  [ "$(cfg_get project.name)" = "devbin" ]
  [ "$(cfg_get project.languages.0)" = "shell" ]
  # A scalar four levels deep. It read options.bats.run until 0092 deleted that
  # key as dead: the handler owns the option, so the summary is what remains.
  [ "$(cfg_get commands.test.options.bats.summary)" = "BATS unit suite" ]
}

@test "Devbin's own config passes schema validation" {
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  run cfg_validate
  assert_success
}

@test "Devbin declares no Elixir language, so no Elixir gate is configured" {
  # The live check on the activation rule's language scoping. Devbin's language
  # is not Elixir, so nothing mix-shaped may be configured here, or `test all`
  # would try to run a toolchain this project does not have.
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  run cfg_list commands.test.options
  assert_success
  refute_output_contains "mix"
  refute_output_contains "credo"
  assert_output_contains "bats"
}

@test "validation accepts the full documented key set" {
  parse <<'YAML'
project:
  name: myapp
  alias: cf
  root_var: MYAPP_ROOT
devbin_version: "^1.0.0"
help:
  preamble: "not the product"
  groups:
    - Surfaces
options:
  env:
    values:
      - dev
    export: MIX_ENV
commands:
  server:
    enabled: true
    summary: Phoenix dev server
    group: Surfaces
    run: mix phx.server
  ls:
    handler: myls
  test:
    options:
      mix:
        summary: ExUnit
        run: mix test
        grammar: mix
        log: MIX
        in_all: false
YAML
  run cfg_validate
  assert_success
}

# ============================================================================
# NO yq DEPENDENCY
# ============================================================================

@test "the reader never invokes yq" {
  # Comment lines are stripped before the search: the file discusses yq at
  # length in the header explaining why it does not use one, and a test that
  # forbade the word would forbid the explanation.
  run bash -c "grep -vE '^[[:space:]]*#' '$DEVBIN_LIB_DIR/config' | grep -nE '\\byq\\b'"
  assert_failure
}

@test "the reader parses without ever invoking yq" {
  # The first version demanded yq be ABSENT from /usr/bin:/bin, which is a fact
  # about the machine, not the reader -- GitHub's runners ship yq in /usr/bin
  # and the test failed there while the reader was innocent. So: a poisoned yq
  # FIRST on PATH instead. Any invocation dies loudly into the captured output,
  # which proves non-invocation on every machine, including ones where a real
  # yq sits behind it.
  # Heredoc, not a pipe -- a pipe would put cfg_load_string in a subshell and
  # lose the cache, which is the trap the function's own comment warns about.
  poison="$DEVBIN_TEST_TMPDIR/poison-bin"
  mkdir -p "$poison"
  printf '#!/bin/sh\necho "the reader invoked yq" >&2\nexit 97\n' >"$poison/yq"
  chmod +x "$poison/yq"
  run bash -c '
    export PATH="'"$poison"':/usr/bin:/bin"
    . "'"$DEVBIN_LIB_DIR"'/config"
    cfg_load_string <<YAML
project:
  name: myapp
YAML
    cfg_get project.name
  '
  assert_success
  assert_output "myapp"
}

# ============================================================================
# THE TORN READ
# ============================================================================
#
# WHAT THIS PROTECTS: a config rewritten IN PLACE while the reader parses it
# yields a value that is valid YAML and wrong, which is then word-split into a
# command line and executed. Measured in one consumer -- `test all` ran while
# config.yaml was being edited, and the swift arm's destination read
# `variant=Designed for iPad`.
#
# The race is staged by stubbing `_cfg_parse` rather than by timing. A timing
# test for this would be flaky, and a flaky concurrency guard teaches people to
# re-run rather than to look.

@test "CONTROL: a config nobody is writing loads cleanly and the torn-read guard stays quiet" {
  # Without this, every test below would pass against a reader that refuses
  # EVERY load. A refusal is not evidence until the accepting path is proven.
  printf 'project:\n  name: demo\n' >"$DEVBIN_TEST_TMPDIR/c.yaml"
  cfg_load "$DEVBIN_TEST_TMPDIR/c.yaml"
  [ "$(cfg_get project.name)" = demo ]
}

@test "a config rewritten mid-read is REFUSED rather than half-parsed" {
  printf 'project:\n  name: demo\n' >"$DEVBIN_TEST_TMPDIR/c.yaml"
  # A racing writer, using the REAL parser on both passes: read what is there,
  # then change the file -- which is exactly what a concurrent in-place edit
  # does between devbin's two reads.
  #
  # A call counter would NOT work here and the reason is worth keeping: each
  # pass runs inside a command substitution, so an incremented variable dies
  # with that subshell and both passes return the same value. The first version
  # of this test did that and passed against a guard that never fired. The file
  # is what survives a subshell, which is also what makes this faithful.
  _cfg_parse() {
    awk "$_DEVBIN_CFG_AWK" "$1"
    printf 'project:\n  name: torn\n' >"$1"
  }
  run cfg_load "$DEVBIN_TEST_TMPDIR/c.yaml"
  assert_failure
  assert_output_contains "changed while it was being read"
  assert_output_contains "c.yaml"
}

@test "a REFUSED torn read caches nothing -- a half-parse must not become the config" {
  # The refusal is only worth having if the wrong value cannot be read anyway.
  # Called directly, never through `run`: the cache is a shell variable and a
  # subshell would lose it, which would make this assertion pass vacuously.
  printf 'project:\n  name: demo\n' >"$DEVBIN_TEST_TMPDIR/c.yaml"
  # A racing writer, using the REAL parser on both passes: read what is there,
  # then change the file -- which is exactly what a concurrent in-place edit
  # does between devbin's two reads.
  #
  # A call counter would NOT work here and the reason is worth keeping: each
  # pass runs inside a command substitution, so an incremented variable dies
  # with that subshell and both passes return the same value. The first version
  # of this test did that and passed against a guard that never fired. The file
  # is what survives a subshell, which is also what makes this faithful.
  _cfg_parse() {
    awk "$_DEVBIN_CFG_AWK" "$1"
    printf 'project:\n  name: torn\n' >"$1"
  }
  cfg_load "$DEVBIN_TEST_TMPDIR/c.yaml" 2>/dev/null || true
  [ -z "${_DEVBIN_CFG:-}" ]
}

@test "two identical reads of a quiet file agree, so the guard costs a correct config nothing" {
  # The detector's other arm: agreement must mean acceptance. A guard that
  # refused a consistent read would be caught here rather than in the field.
  printf 'project:\n  name: demo\n  alias: d\n' >"$DEVBIN_TEST_TMPDIR/c.yaml"
  cfg_load "$DEVBIN_TEST_TMPDIR/c.yaml"
  [ "$(cfg_get project.name)" = demo ]
  [ "$(cfg_get project.alias)" = d ]
}

# ============================================================================
# A DECLARED COMMAND LINE WITH NO WORDS IN IT (issue 0082)
# ============================================================================

@test "validation refuses a command line with no words in it, naming the key (0082)" {
  # `doctor` is not on the dispatch path and the sites are not on doctor's, so
  # the refusal is stated at both ends. These are keys devbin splits into words
  # and runs; the arm below holds the release core's.
  parse <<'YAML'
project:
  name: demo
commands:
  fullcycle:
    restore: "   "
  greet:
    run: ""
    options:
      one:
        run: "  "
release:
  notes:
    kind: command
    run: "  "
YAML
  run cfg_validate
  assert_failure
  assert_output_contains 'commands.fullcycle.restore: "   " holds no words'
  assert_output_contains 'commands.greet.run: "" holds no words'
  assert_output_contains 'commands.greet.options.one.run: "  " holds no words'
  assert_output_contains 'release.notes.run: "  " holds no words'
}

@test "validation refuses a release command line or gate with no words in it (0104)" {
  # The release core splits and runs these too: ci.query, and each derived:,
  # after: and gates: item. They were validated as ordinary text, so a
  # whitespace-only one passed doctor and failed only at the cut.
  parse <<'YAML'
project:
  name: demo
release:
  ci:
    query: "  "
  gates:
    - "  "
  derived:
    - " "
  after:
    - "   "
YAML
  run cfg_validate
  assert_failure
  assert_output_contains 'release.ci.query: "  " holds no words'
  assert_output_contains 'release.gates.0: "  " holds no words'
  assert_output_contains 'release.derived.0: " " holds no words'
  assert_output_contains 'release.after.0: "   " holds no words'
}

@test "validation takes a command line that holds a word, glob characters and all (0082)" {
  parse <<'YAML'
project:
  name: demo
commands:
  fullcycle:
    restore: cargo build --release
  greet:
    run: bats opt/*/test
    options:
      one:
        run: "  mix   test  "
release:
  notes:
    kind: command
    run: bin/notes
YAML
  run cfg_validate
  assert_success
  assert_output ""
}
