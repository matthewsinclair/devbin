#!/usr/bin/env bats
# optin.bats - the second activation axis (WP-18)
#
# `which`, `macos`, `precommit`, `publish` and `content` are shipped names that
# most projects should never see. (`macos` has been devbin's own built-in since
# issue 0226, as `release` is, and stays opt-in.) The first axis scopes a built-in by LANGUAGE,
# which is the wrong test for these: they are language-agnostic and still
# should not appear uninvited -- `macos` on a Linux project and `publish` on a
# private one are noise at best.
#
# These commands themselves are thin, and devbin deliberately ships no
# command line for any of them: each is one or two of the four corpus projects
# and encodes that project's shape. What WP-18 actually delivers is the axis.
#
# Before this, all five resolved in every project and exited 3, so the gap was
# real and only latent because they were unbuilt.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }


plain_project() {
  mkproj demo <<'YAML'
project:
  name: demo
YAML
}

@test "an opt-in command is absent from a project that has not asked for it" {
  proj="$(plain_project)"
  run devbin_run "$proj" help
  assert_success
  # Anchored on the rendered command column: these words appear in other
  # summaries as ordinary prose.
  refute_output_matches '(^|'$'\n'')  which '
  refute_output_matches '(^|'$'\n'')  macos '
  refute_output_matches '(^|'$'\n'')  publish '
}

@test "asking for an unenabled opt-in command says it is shipped but not enabled" {
  proj="$(plain_project)"
  run devbin_run "$proj" macos
  assert_failure
  # Language scoping's rule, applied to the new axis: an absent command must be
  # distinguishable from a broken one and from a typo.
  assert_output_contains "devbin ships it"
  assert_output_contains "commands.macos.enabled: true"
  refute_output_contains "unknown command"
}

@test "enabled: true switches an opt-in command on" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  which:
    enabled: true
    summary: Which build this resolves to
    run: echo resolved-build
YAML
  )"
  run devbin_run "$proj" which
  assert_success
  assert_output_contains "resolved-build"
}

@test "an enabled opt-in command appears in help" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  publish:
    enabled: true
    run: echo published
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_matches '(^|'$'\n'')  publish '
  # With the catalogue's summary, since config declared none of its own.
  assert_output_contains "Publish a release artifact"
}

@test "the two axes compose without a project having to reason about them" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  precommit:
    enabled: true
    run: echo hooked
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  # Language scoping still applies to language-scoped built-ins ...
  assert_output_matches '(^|'$'\n'')  iex '
  # ... and enablement to opt-in ones, independently.
  assert_output_matches '(^|'$'\n'')  precommit '
  refute_output_matches '(^|'$'\n'')  macos '
}

@test "a project handler activates an opt-in command without an enabled flag" {
  proj="$(plain_project)"
  create_test_command "$proj" macos >/dev/null
  # Its presence IS the declaration, the same rule that applies to every
  # other command. An opt-in name must not need saying twice.
  run devbin_run "$proj" macos
  assert_success
  assert_output_contains "ran:macos"
}

@test "enabled: false still wins over everything" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  which:
    enabled: false
    run: echo should-not-run
YAML
  )"
  run devbin_run "$proj" which
  assert_failure
  refute_output_contains "should-not-run"
}

@test "devbin ships no command line for any opt-in command" {
  # Each is one or two of the four corpus projects and encodes that project's
  # shape -- tier 4, every one of them. Shipping a default for `publish` would
  # impose one project's release process on the rest.
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  local cmd
  for cmd in which precommit publish content; do
    [ "$(builtin_command_lang "$cmd")" = "opt-in" ] ||
      fail "$cmd should be opt-in, not $(builtin_command_lang "$cmd")"
    ! builtin_has_default_run "$cmd" ||
      fail "$cmd ships a default command line, which imposes one project's shape"
  done
}

@test "an opt-in whose options are all switched off says so, never that it was not enabled (0136)" {
  # command_active makes a command with options inactive once none survives,
  # and the refusal then explained it as the command being off: "this project
  # has not enabled it", to a project that had enabled it in config.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  precommit:
    enabled: true
    options:
      lint:
        run: echo linting
        enabled: false
YAML
  )"
  run devbin_run "$proj" precommit
  assert_exit_code 2
  assert_output_contains "every option it offers is switched off"
  assert_output_contains "lint"
  refute_output_contains "has not enabled it"
  # help --why gives the same reason on precommit's own line; the other opt-ins
  # there are genuinely not enabled, so the line is read alone.
  run devbin_run "$proj" help --why
  local line
  line="$(printf '%s\n' "$output" | grep -E '^ +precommit ')" || fail "help --why has no precommit line: $output"
  [[ "$line" == *"every option it offers is switched off"* ]] || fail "help --why gives precommit another reason: $line"
  [[ "$line" != *"has not enabled it"* ]] || fail "help --why still says precommit was not enabled: $line"
}

@test "a handler file without its executable bit is named as one, with the chmod, at both refusals (0136)" {
  # It is not a handler (is_handler), so the command read as unfilled: without
  # enabled: it was refused as not enabled, and with it the remedy named the
  # very file the project had already written.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf '#!/usr/bin/env bash\necho precommit-ran\n' >"$proj/bin/.devbin/cmd/precommit"
  chmod 644 "$proj/bin/.devbin/cmd/precommit"
  run devbin_run "$proj" precommit
  assert_exit_code 2
  assert_output_contains "bin/.devbin/cmd/precommit is there but not executable"
  assert_output_contains "chmod +x bin/.devbin/cmd/precommit"
  refute_output_contains "has not enabled it"
  printf 'commands:\n  precommit:\n    enabled: true\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" precommit
  assert_exit_code 3
  assert_output_contains "bin/.devbin/cmd/precommit is there but not executable"
  refute_output_contains "add bin/.devbin/cmd/precommit"
  # THE CONTROL: with its bit set, the same file runs.
  chmod +x "$proj/bin/.devbin/cmd/precommit"
  run devbin_run "$proj" precommit
  assert_success
  assert_output_contains "precommit-ran"
}
