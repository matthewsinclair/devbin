#!/usr/bin/env bats
# runwords.bats - one reading of a declared command line, at every site that
# runs one (issue 0082)
#
# `run:` was expanded unquoted at four sites in lib/resolve, at fullcycle's
# `restore`, at `release.notes.run` and at the two that run the catalogue's own
# command lines -- eight statements of one rule. Two things followed, and both
# were measured through the real dispatcher before they were fixed:
#
#   - Every word was ALSO a glob pattern matched against the project root, which
#     no document said. A census of the installs found one word relying on it
#     and nothing else that would change, so the globbing is KEPT and
#     documented.
#   - A `run:` of only spaces is not empty to `[ -n "$run" ]` and splits into no
#     words at all, so `$run "$@"` ran the arguments typed after the command AS
#     the command, at exit 0, with no message.
#
# The sites now ask `run_words` (lib/helpers), and this file drives each one.
# The restore site is held in fullcycle.bats, `notes.run` in release.bats, and
# the helper itself in helpers.bats, each beside its own fixtures.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# A project whose every command line is `./args`, which prints one line per
# argument it was given -- so what the site ran is read from its own output
# rather than from a side effect.
globproj() {
  local proj
  proj="$(mkproj globs <<'YAML'
project:
  name: globs
commands:
  probe:
    summary: option-level command lines
    options:
      bare:
        summary: an option run bare
        run: ./args [%s] *.md
      gated:
        summary: an option run as a gate
        run: ./args [%s] *.md
        log: true
      blank:
        summary: an option whose run is only spaces
        run: "   "
      blankgated:
        summary: a gated option whose run is only spaces
        run: "   "
        log: true
      empty:
        summary: an option declaring an empty run
        run: ""
  launch:
    summary: a command-level line, exec'd
    run: ./args [%s] *.md
  sealed:
    summary: a command-level line, under a gate
    run: ./args [%s] *.md
    log: true
  blankcmd:
    summary: a command whose run is only spaces
    run: "   "
  blankcmdgated:
    summary: a gated command whose run is only spaces
    run: "   "
    log: true
  emptycmd:
    summary: a command declaring an empty run
    run: ""
YAML
  )"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "arg:%%s\\n" "$a"; done\n' >"$proj/args"
  chmod +x "$proj/args"
  : >"$proj/alpha.md"
  : >"$proj/beta.md"
  mkdir -p "$proj/deep"
  : >"$proj/deep/other.md"
  echo "$proj"
}

# ============================================================================
# THE WORDS ARE GLOB PATTERNS, MATCHED WHERE THE COMMAND RUNS
# ============================================================================

@test "an option's run: words are glob patterns matched at the project root, bare and under a gate (0082)" {
  local proj; proj="$(globproj)"

  run devbin_run "$proj" probe bare
  assert_success
  assert_output_contains "arg:alpha.md"
  assert_output_contains "arg:beta.md"
  # A word matching nothing is passed as written, which is what the documented
  # rule says and what the census of installs measured.
  assert_output_contains "arg:[%s]"
  refute_output_contains "arg:*.md"
  refute_output_contains "arg:other.md"

  run devbin_run "$proj" probe gated
  assert_success
  assert_output_contains "arg:alpha.md"
  assert_output_contains "arg:beta.md"
  assert_output_contains "arg:[%s]"
  refute_output_contains "arg:*.md"
  assert_file_exists "$proj/tmp/probe/LATEST_GATED.errors"
}

@test "a command's run: words are glob patterns too, exec'd and under a gate (0082)" {
  local proj; proj="$(globproj)"

  run devbin_run "$proj" launch
  assert_success
  assert_output_contains "arg:alpha.md"
  assert_output_contains "arg:beta.md"
  assert_output_contains "arg:[%s]"
  refute_output_contains "arg:*.md"

  run devbin_run "$proj" sealed
  assert_success
  assert_output_contains "arg:alpha.md"
  assert_output_contains "arg:beta.md"
  refute_output_contains "arg:*.md"
  assert_file_exists "$proj/tmp/sealed/LATEST_SEALED.errors"
}

@test "a bracket word that matches a file becomes that file, format string and all (0082)" {
  # Measured, and the rule's consequence in one line: `[%s]` is a
  # pattern for a single character `%` or `s`, so a file named `s` at the root
  # turns a printf FORMAT into a filename. Nothing in devbin can tell the two
  # apart, which is exactly why the rule is now written down.
  local proj; proj="$(globproj)"
  : >"$proj/s"

  run devbin_run "$proj" probe bare
  assert_success
  assert_output_contains "arg:s"
  refute_output_contains "arg:[%s]"
}

@test "the root is where a run: word is matched, not the directory the caller stands in (0082)" {
  # NOT devbin_run, which stands in the project itself: the whole question here
  # is what happens when the caller does not. `deep/` holds a .md of its own, so
  # a site globbing where the caller stands would hand over that one instead.
  local proj; proj="$(globproj)"

  run bash -c 'cd "$1/deep" && "$1/bin/devbin" probe bare </dev/null' _ "$proj"
  assert_success
  assert_output_contains "arg:alpha.md"
  assert_output_contains "arg:beta.md"
  refute_output_contains "arg:other.md"
}

# ============================================================================
# A COMMAND LINE WITH NO WORDS IN IT IS REFUSED, NAMING ITS KEY
# ============================================================================

@test "an option's run: of only spaces is refused naming the key, and the arguments after it never run (0082)" {
  local proj; proj="$(globproj)"

  run devbin_run "$proj" probe blank ./args EXECUTED-AS-THE-COMMAND
  assert_failure
  assert_output_contains "commands.probe.options.blank.run holds no words"
  refute_output_contains "arg:EXECUTED-AS-THE-COMMAND"

  # A marker as well as the output: what ran is a fact about the filesystem, and
  # an assertion about stdout alone would pass if the site swallowed it.
  run devbin_run "$proj" probe blank touch ./blank-marker
  assert_failure
  assert_file_not_exists "$proj/blank-marker"
}

@test "a gated option's run: of only spaces is refused before the gate opens (0082)" {
  local proj; proj="$(globproj)"

  run devbin_run "$proj" probe blankgated touch ./gated-marker
  assert_failure
  assert_output_contains "commands.probe.options.blankgated.run holds no words"
  assert_file_not_exists "$proj/gated-marker"
  # No seal, and no run log: a gate that refused is not a gate that ran.
  assert_directory_not_exists "$proj/tmp"
}

@test "a command's run: of only spaces is refused naming the key, exec'd and under a gate (0082)" {
  local proj; proj="$(globproj)"

  run devbin_run "$proj" blankcmd touch ./cmd-marker
  assert_failure
  assert_output_contains "commands.blankcmd.run holds no words"
  assert_file_not_exists "$proj/cmd-marker"

  run devbin_run "$proj" blankcmdgated touch ./cmdgate-marker
  assert_failure
  assert_output_contains "commands.blankcmdgated.run holds no words"
  assert_file_not_exists "$proj/cmdgate-marker"
  assert_directory_not_exists "$proj/tmp"
}

@test "a declared run: with nothing in it is refused rather than read as undeclared (0082)" {
  # `run: ""` carries no words either, and every other reader in devbin already
  # treats it as DECLARED: `command_active`, `doctor` and `help` all ask
  # `cfg_has`. Only the two run sites asked `[ -n ]`, so a project that declared
  # an empty line got the catalogue's default silently, or "no run: and no
  # handler", which is a fact about devbin and not about the config.
  local proj; proj="$(globproj)"

  run devbin_run "$proj" probe empty touch ./empty-marker
  assert_failure
  assert_output_contains "commands.probe.options.empty.run holds no words"
  assert_file_not_exists "$proj/empty-marker"

  run devbin_run "$proj" emptycmd touch ./emptycmd-marker
  assert_failure
  assert_output_contains "commands.emptycmd.run holds no words"
  assert_file_not_exists "$proj/emptycmd-marker"
}

@test "an empty run: over a catalogue option is refused, where it used to run the catalogue's line (0082)" {
  local proj
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: ""
YAML
  )"
  mkdir -p "$BATS_TEST_TMPDIR/catbin"
  printf '#!/usr/bin/env bash\nprintf "CATALOGUE-DEFAULT-RAN\\n"\n' >"$BATS_TEST_TMPDIR/catbin/cargo"
  chmod +x "$BATS_TEST_TMPDIR/catbin/cargo"

  PATH="$BATS_TEST_TMPDIR/catbin:$PATH" run devbin_run "$proj" test rust
  assert_failure
  assert_output_contains "commands.test.options.rust.run holds no words"
  refute_output_contains "CATALOGUE-DEFAULT-RAN"
}

# ============================================================================
# THE CATALOGUE'S OWN LINES READ THE SAME WAY
# ============================================================================

@test "a catalogue command line is split by run_words too, whatever the caller's IFS (lib/gatecmd, 0082)" {
  # The catalogue is devbin's own data rather than a project's, and lib/gatecmd
  # has always said the two paths behaving differently would be worse than
  # either behaviour on its own. A handler that sources lib/gatecmd under the
  # common strict-mode `IFS=$'\n\t'` is where that stops being theoretical: the
  # whole line stays one word and resolves to nothing.
  local d="$DEVBIN_TEST_TMPDIR/cat"
  mkdir -p "$d"
  : >"$d/alpha.md"
  : >"$d/beta.md"
  local got
  got="$(PROJECT_ROOT="$d" DEVBIN_NAME=devbin bash -c '
    . "$DEVBIN_LIB/gatecmd"
    # A stand-in row, because no catalogue line devbin ships carries a glob.
    builtin_option_run() { printf "%s\n" "printf [%s] *.md"; }
    builtin_option_suffix() { printf "PROBE\n"; }
    builtin_option_grammar() { printf "generic\n"; }
    run_gate() { while [ "$1" != -- ]; do shift; done; shift; printf "<%s>" "$@"; }
    IFS=$'"'"'\n\t'"'"'
    run_builtin_gate check probe
  ')" || fail "run_builtin_gate failed: $got"
  [ "$got" = '<printf><[%s]><alpha.md><beta.md>' ] ||
    fail "the catalogue line reached the runner as $got"
}

# ============================================================================
# THE RULE IS WRITTEN DOWN WHERE IT IS READ
# ============================================================================

@test "the documents that describe run: say its words are glob patterns (0082)" {
  # The globbing is kept BECAUSE it is documented; a fix that quietly kept
  # it and said nothing is the state the issue was filed about. These are the
  # surfaces that describe the expansion -- the reference document, the README
  # and the migration guide -- and the line each carried said word splitting and
  # nothing else.
  local f
  for f in docs/configuration.md README.md docs/migration.md; do
    grep -q 'glob pattern' "$DEVBIN_HOME/$f" ||
      fail "$f describes run:'s expansion and does not say its words are glob patterns"
  done
  grep -q 'matched in the directory the command runs from' "$DEVBIN_HOME/docs/configuration.md" ||
    fail "docs/configuration.md does not say where a run: word is matched"
  grep -q 'no words' "$DEVBIN_HOME/docs/configuration.md" ||
    fail "docs/configuration.md does not say that a run: with no words is refused"
}
