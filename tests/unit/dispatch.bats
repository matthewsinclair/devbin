#!/usr/bin/env bats
# dispatch.bats - bin/devbin and lib/resolve (WP-04)
#
# Covers the rules that ARE the framework: the resolution order, the
# synthesised `all`, and language-scoped activation with exclusion in both
# directions.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# A fixture project with devbin installed and a config written from stdin.
# Prints the project path.

# ============================================================================
# DISPATCH BASICS
# ============================================================================

@test "no arguments prints help" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj"
  assert_success
  assert_output_contains "demo -- dev launcher"
  assert_output_contains "Usage:"
}

@test "identity comes from config, not from the invoked filename" {
  proj="$(mkproj demo <<'YAML'
project:
  name: myapp
  alias: cf
YAML
  )"
  echo "9.9.9" >"$proj/VERSION"
  ln -s devbin "$proj/bin/cf"
  # cd rather than devbin_run: this arm is about the launcher NAME, which the
  # helper cannot express -- it invokes ./bin/devbin by definition.
  cd "$proj"
  run ./bin/cf -v
  assert_success
  # Still exact about the half this test is FOR -- the name comes from config,
  # not from the launcher's filename -- while allowing the identity suffix. The
  # fixture is not a checkout, so the honest identity there is `unknown`.
  assert_output_matches '^myapp 9\.9\.9 \((([0-9a-f]{40})|unknown)( \+dirty)?, runtime [0-9a-f]{12}\)$'
}

@test "dispatches through a symlink and from any working directory" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" greet >/dev/null
  ln -s devbin "$proj/bin/db"
  mkdir -p "$proj/deep/nested"
  cd "$proj/deep/nested"
  run "$proj/bin/db" greet alpha
  assert_success
  assert_output "ran:greet args:alpha"
}

@test "bin/devbin run by its relative path finds its own runtime, never one through an exported CDPATH holding a bin/, through a relative launcher link too (0267)" {
  # The bootstrap's cd read a bare relative dirname through CDPATH before the
  # current directory: `bin/devbin` typed at the root resolved into the
  # CDPATH entry's bin/ and found no runtime there.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  echo "9.9.9" >"$proj/VERSION"
  ln -s devbin "$proj/bin/db"
  mkdir -p "$DEVBIN_TEST_TMPDIR/decoy/bin"
  cd "$proj"
  local launcher
  for launcher in bin/devbin bin/db; do
    CDPATH="$DEVBIN_TEST_TMPDIR/decoy" run "$launcher" --version
    assert_success
    assert_output_matches '^demo 9\.9\.9 '
    refute_output_contains "$DEVBIN_TEST_TMPDIR/decoy"
  done
}

# ---------------------------------------------------------------------------
# THE TREE A RUN IS ABOUT
# ---------------------------------------------------------------------------

@test "a foreign working directory is REFUSED, and the refusal names both trees" {
  # The reported case, reduced: a devbin reached from outside its own project ran
  # against ITS OWN tree and printed that project's catalogue at rc 0. The
  # invocation below is EXACTLY what 365 sites in this suite used to do, which
  # is why nothing here ever caught it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # cwd is $DEVBIN_TEST_TMPDIR -- the PARENT of the project, so: foreign.
  run "$proj/bin/devbin" doctor
  assert_failure
  assert_output_contains "not your current project"
  assert_output_contains "$proj"
  # It must name where you ARE as well as what it belongs to; one without the
  # other leaves the reader unable to see which of the two surprised them.
  assert_output_contains "$DEVBIN_TEST_TMPDIR"
}

@test "the wrong-tree refusal NAMES THE ARGUMENT it was given" {
  # Issue 0039. The guard runs BEFORE command resolution, so it cannot know
  # whether the argument is a command at all -- and it was asserting "every
  # command would act on <root>" about things that are not commands. A person
  # typed `init`, which devbin does not have, and was told their LOCATION was wrong
  # when their VERB was. Naming what was typed lets the reader see their own
  # typo without the guard having to resolve it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run "$proj/bin/devbin" doctor
  assert_exit_code 4
  assert_output_contains "doctor"
}

@test "it names an argument that is NOT a command, which is the case 0039 was filed for" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # `init` does not exist. Inside the tree this is exit 2 "unknown command";
  # outside it the guard fires first, so the only thing that can help the
  # reader is seeing the word they typed echoed back.
  run "$proj/bin/devbin" init
  assert_exit_code 4
  assert_output_contains "init"
}

@test "a BARE invocation says so rather than printing an empty field" {
  # The guard fires for a bare devbin too -- "" matches the catch-all in the
  # exemption case. Without this arm the new line renders as a dangling label
  # with nothing after it, which reads as a bug in the refusal itself.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run "$proj/bin/devbin"
  assert_exit_code 4
  assert_output_contains "(no command)"
}

@test "the wrong-tree refusal does NOT share an exit code with a usage refusal" {
  # Arms in this suite assert exit 2 for a usage-class refusal. A guard
  # sharing that code would let any of them be satisfied by a wrong-tree
  # refusal instead, which is a green that no longer names its own cause.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run "$proj/bin/devbin" doctor
  assert_exit_code 4
  run devbin_run "$proj" nosuchthing
  assert_exit_code 2
}

@test "standing INSIDE the project is permitted, subdirectories included" {
  # The negative control for the arm above: if this failed, the guard would be
  # refusing everything and the red arm would prove nothing.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" doctor
  assert_success
  mkdir -p "$proj/deep/nested"
  cd "$proj/deep/nested"
  run "$proj/bin/devbin" doctor
  assert_success
}

@test "install is EXEMPT, because its target is --into and defaults to the cwd" {
  # The one command whose job is acting outside its own tree. If the guard ever
  # catches it, devbin loses the ability to install itself anywhere.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  target="$DEVBIN_TEST_TMPDIR/installed-from-afar"
  mkdir -p "$target"
  # Standing in neither project.
  run "$proj/bin/devbin" install --into "$target" --name faraway
  assert_success
  assert_file_exists "$target/bin/devbin"
}

@test "version's WRITING forms are guarded like any writing verb, and the version file is untouched (0124)" {
  # From a foreign cwd, `version bump patch` moved a project's VERSION from
  # 1.2.3 to 1.2.4 at rc 0: the exemption meant for REPORTING a version took
  # every sub-command. dvb's DEVBIN_SOURCE fallback reaches exactly this path.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  run "$proj/bin/devbin" version bump patch
  assert_exit_code 4
  assert_output_contains "not your current project"
  run "$proj/bin/devbin" version set 9.9.9
  assert_exit_code 4
  run "$proj/bin/devbin" version sync
  assert_exit_code 4
  [ "$(cat "$proj/VERSION")" = 1.2.3 ] || fail "a writing version verb from a foreign cwd rewrote VERSION to: $(cat "$proj/VERSION")"
}

@test "version's REPORTING forms still run from a foreign cwd, and bump still works inside -- the controls (0124)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  run "$proj/bin/devbin" version show
  assert_success
  assert_output_contains "1.2.3"
  run "$proj/bin/devbin" version
  assert_success
  run "$proj/bin/devbin" version check
  assert_success
  run "$proj/bin/devbin" --version
  assert_success
  run "$proj/bin/devbin" devbin version
  assert_success
  # Inside the tree the same verb works, so the refusal above is the guard and
  # not a broken verb.
  run devbin_run "$proj" version bump patch
  assert_success
  [ "$(cat "$proj/VERSION")" = 1.2.4 ] || fail "version bump inside the tree left VERSION at: $(cat "$proj/VERSION")"
}

@test "an unknown command exits 2 and says so" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" nosuchthing
  assert_exit_code 2
  assert_output_contains "unknown command: nosuchthing"
}

@test "a missing config is refused rather than defaulted" {
  proj="$(create_test_project bare)"
  install_devbin "$proj"
  rm "$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" help
  assert_failure
  assert_output_contains "no config at"
}

# ============================================================================
# RESOLUTION ORDER
# ============================================================================

@test "a project handler is auto-discovered with no config entry" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" deploy >/dev/null
  run devbin_run "$proj" deploy now
  assert_success
  assert_output "ran:deploy args:now"
}

@test "a project handler shadows a built-in of the same name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  create_test_command "$proj" check >/dev/null
  run devbin_run "$proj" check
  assert_success
  assert_output "ran:check args:"
}

@test "config maps a differently-named file to a command" {
  # The contrived `ls` case from the original brief: bin/.devbin/cmd/myls
  # provides `devbin ls`.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  ls:
    handler: myls
    summary: List things
YAML
  )"
  create_test_command "$proj" myls >/dev/null
  run devbin_run "$proj" ls here
  assert_success
  assert_output "ran:myls args:here"
}

@test "a mapped handler that is not executable is refused by name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  ls:
    handler: myls
    summary: List things
YAML
  )"
  echo '#!/usr/bin/env bash' >"$proj/bin/.devbin/cmd/myls"
  run devbin_run "$proj" ls
  assert_failure
  assert_output_contains "not executable"
}

@test "an unbuilt built-in exits 3, never a quiet success" {
  # CONSTRUCTS the condition rather than borrowing whichever built-in happens
  # to be unimplemented -- it pointed at `server`, then `docs`, needing a
  # rewrite each time one shipped. Removing the handler from the fixture's
  # copied lib reproduces it exactly, and covers a partial install besides.
  #
  # The command must have NO options, or a bare invocation correctly prints
  # them instead (AC-04.13). `version` is the one whose sub-commands are
  # deliberately not catalogue options -- `version all` would be nonsense.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  version:
    summary: Version
YAML
  )"
  rm -f "$proj/bin/.devbin/lib/cmd/version"
  run devbin_run "$proj" version
  assert_exit_code 3
  # Named for what is actually wrong since issue 0111: the handler is missing
  # from this install. It said "not built yet" and cited a closed thread.
  assert_output_contains "handler for 'version' is missing from this install"
  refute_output_contains "not built yet"
}

# ============================================================================
# SYNTHESISED `all`
# ============================================================================

@test "all runs every option in declared order" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      first:
        summary: one
      second:
        summary: two
      third:
        summary: three
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" gate all
  assert_success
  assert_output_contains "ran:first"
  assert_output_contains "ran:second"
  assert_output_contains "ran:third"
  # Order matters: the summary must follow the declaration sequence.
  assert_output_matches 'ran:first(.|
)*ran:second(.|
)*ran:third'
}

@test "all does not stop at the first breach and names every failure" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      good:
        summary: passes
      bad:
        summary: fails
      alsobad:
        summary: fails too
      last:
        summary: still runs
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"
case "$1" in bad|alsobad) exit 1 ;; esac'
  run devbin_run "$proj" gate all
  assert_failure
  # The gate after the failures still ran: one pass surfaces everything.
  assert_output_contains "ran:last"
  assert_output_contains "FAILED: bad alsobad"
}

@test "all reports in_all false options as skipped rather than dropping them" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      normal:
        summary: runs
      local_only:
        summary: excluded
        in_all: false
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" gate all
  assert_success
  assert_output_contains "ran:normal"
  refute_output_contains "ran:local_only"
  # Silently dropping it would make a partial run read as a full green.
  assert_output_contains "skipped (in_all: false): local_only"
}

# ZERO EXECUTED IS A REFUSAL, and it is the same false green run_all already
# refuses at the top, reached from the other end. The top guard fires when a
# command has no active OPTIONS; it cannot fire when the options are all
# EXCLUDED, because command_options is non-empty and the filtering happens in
# the loop. Before this, such a run printed "all gate options passed" and
# returned 0 -- and `devbin gate all && deploy` deploys on that.
@test "all REFUSES when every option it offers is excluded -- it ran nothing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      local_only:
        summary: excluded
        in_all: false
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'

  run devbin_run "$proj" gate all

  assert_failure
  refute_output_contains "ran:local_only"
  assert_output_contains "executed nothing"
  # THE LOAD-BEARING REFUTATION. A run that examined nothing must not claim a
  # pass, and the old tail said exactly that while returning 0.
  refute_output_contains "all gate options passed"
}

# ============================================================================
# THE PARTITION (issue 0063)
# ============================================================================
#
# `all` counted only the options that spoke. An option deactivated before the
# loop -- by language scope, by `enabled: false`, by a filter nobody has written
# yet -- appeared nowhere, and "all check options passed" at rc 0 read as a full
# pass. run_all now prints ONE count line on every path, and refuses a verdict
# unless every candidate is accounted for exactly once as ran, skipped or
# inactive. Too wide fails loudly on its own; only a partition that must sum
# catches too narrow, which is the direction that fails green.

# stub_command_options <proj> <filter> -- wrap the fixture's vendored
# command_options in a filter, the stand-in for a future defect that removes
# (or repeats) an active option before run_all's loop ever sees it.
stub_command_options() {
  cat >>"$1/bin/.devbin/lib/resolve" <<STUB

eval "\$(declare -f command_options | sed '1s/^command_options/_unstubbed_command_options/')"
command_options() {
  _unstubbed_command_options "\$@" | $2
  return 0
}
STUB
}

@test "all prints one count line on the passing path: ran, inactive and skipped against every candidate" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      normal:
        summary: runs
      local_only:
        summary: excluded
        in_all: false
      off:
        summary: disabled
        enabled: false
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'

  run devbin_run "$proj" gate all

  assert_success
  assert_output_contains "ran:normal"
  refute_output_contains "ran:off"
  assert_output_contains "1 of 3 gate options ran; 1 inactive here (bin/devbin help --why names them), 1 skipped (in_all: false)"
  # The passing path names no inactive member: reciting them on every run is
  # the noise that teaches a reader to skim the line.
  refute_output_contains "inactive: off"
  assert_output_contains "all gate options passed"
}

@test "all counts a fully active run with nothing inactive and nothing skipped" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      one:
        summary: runs
      two:
        summary: runs
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'

  run devbin_run "$proj" gate all

  assert_success
  assert_output_contains "2 of 2 gate options ran; 0 inactive here, 0 skipped (in_all: false)"
}

# AT-6.1
@test "an option whose platforms: leave this host out is inactive here: all runs the rest and counts it, help --why names it with its reason, and by name it is refused with that reason; one naming this host, or declaring no platforms:, runs (ST0011 WP-17, AC-6.1)" {
  # The host's word is the arm's own: uname -s answers Linux, whatever runs it.
  local o opts=(here there anywhere) ran=(here anywhere) inactive=(there) skipped=()
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      here:
        summary: runs on linux
        platforms:
          - linux
      there:
        summary: runs on macos
        platforms:
          - macos
      anywhere:
        summary: runs everywhere
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  stub_uname -s UNAME_STUB_OS

  UNAME_STUB_OS=Linux run devbin_run "$proj" gate all
  assert_success
  for o in "${ran[@]}"; do assert_output_contains "ran:$o"; done
  for o in "${inactive[@]}"; do refute_output_contains "ran:$o"; done
  assert_output_contains "${#ran[@]} of ${#opts[@]} gate options ran; ${#inactive[@]} inactive here (bin/devbin help --why names them), ${#skipped[@]} skipped (in_all: false)"

  UNAME_STUB_OS=Linux run devbin_run "$proj" help --why
  assert_success
  grep -qE '^  gate there +it runs on macos, and this host is linux$' <<<"$output" ||
    fail "help --why does not name gate there with its reason:
$output"

  UNAME_STUB_OS=Linux run devbin_run "$proj" gate there
  [ "$status" -eq 2 ] || fail "gate there ran by name on linux: exit $status, want 2: $output"
  assert_output_contains "'bin/devbin gate there' is not available here: it runs on macos, and this host is linux"
  refute_output_contains "ran:there"
}

@test "on a host with no platform word an option that declares platforms: runs nowhere, and a command whose every option is inactive, one by its platforms, is refused by name naming each with its reason (ST0011 WP-17)" {
  # uname -s answers FreeBSD, which has no platform word.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      both:
        summary: runs on macos and linux
        platforms:
          - macos
          - linux
      anywhere:
        summary: runs everywhere
  app:
    summary: the app
    options:
      build:
        summary: builds it
        run: echo ran:build
        platforms:
          - macos
      check:
        summary: checks it
        run: echo ran:check
        enabled: false
YAML
  )"
  # No handler for app: a command the project owns stays active whatever its
  # options say, so app is offered here only through its options.
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  stub_uname -s UNAME_STUB_OS

  UNAME_STUB_OS=FreeBSD run devbin_run "$proj" gate both
  [ "$status" -eq 2 ] || fail "gate both ran by name on a host with no platform word: exit $status, want 2: $output"
  assert_output_contains "'bin/devbin gate both' is not available here: it runs on macos and linux, and this host has no platform word"
  UNAME_STUB_OS=FreeBSD run devbin_run "$proj" gate anywhere
  assert_success
  assert_output_contains "ran:anywhere"

  UNAME_STUB_OS=FreeBSD run devbin_run "$proj" app build
  [ "$status" -eq 2 ] || fail "app build ran on a host with no platform word: exit $status, want 2: $output"
  assert_output_contains "'bin/devbin app' is not available here: every option it offers is inactive here: build: it runs on macos, and this host has no platform word; check: it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "ran:build"
}

@test "a platforms: list holding a value that is not a platform word reads as absent, so the option runs on every host, and doctor refuses the value, naming the key and the value (ST0011 WP-17)" {
  # Linux is uname's spelling, not a platform word. Read as another platform it
  # would make the gate never run and never fail, on every host.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      spelt:
        summary: names uname's spelling
        platforms:
          - Linux
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" doctor
  assert_output_contains "commands.gate.options.spelt.platforms.0: \"Linux\" is not a platform word"
  stub_uname -s UNAME_STUB_OS
  local os
  for os in Linux Darwin; do
    UNAME_STUB_OS="$os" run devbin_run "$proj" gate spelt
    assert_success
    assert_output_contains "ran:spelt"
  done
}

@test "a built-in command whose last active option is held back by its platforms: names it with its reason, never a language the project already declares (ST0011 WP-17)" {
  # test.shell is active by the declared language until its platforms: leave
  # this host out; every other test option is held back by its language.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      shell:
        platforms:
          - macos
YAML
  )"
  stub_uname -s UNAME_STUB_OS
  UNAME_STUB_OS=Linux run devbin_run "$proj" test
  [ "$status" -eq 2 ] || fail "test ran on linux with its one active option declared for macos: exit $status, want 2: $output"
  assert_output_contains "'bin/devbin test' is not available here: every option it offers is inactive here: shell: it runs on macos, and this host is linux"
  refute_output_contains "declare project.languages"
  UNAME_STUB_OS=Linux run devbin_run "$proj" help --why
  assert_success
  grep -qE '^  test +every option it offers is inactive here: shell: it runs on macos, and this host is linux' <<<"$output" ||
    fail "help --why does not name test's shell option with its reason:
$output"
}

@test "run_all's count line reaches its no-options refusal, with the shipped options counted inactive" {
  # The dispatcher sends one shape here with zero options, a command-level
  # `run:` with no option to run (issue 0128, its option (b)), and a `run:`
  # displaces the shipped options, so through the dispatcher only options the
  # project declares are counted, never the shipped ones this arm counts as
  # inactive. So the guard is asked directly -- run_all itself -- over `test` in
  # a project declaring no languages, where every option devbin ships is
  # language-scoped and none is active. Until 0128 a `run:` kept the command
  # alive to get here through the dispatcher with the shipped options still
  # counted. The count comes from the catalogue itself, never a typed number.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  local n
  n="$(fixture_catalogue_count "$proj" test)"
  [ "$n" -gt 0 ] || fail "the catalogue ships no test options -- this arm has no population to count"

  run fixture_ask "$proj" run_all test

  # 1 is run_all's refusal code but not its alone, so the text below is what
  # says the refusal answered (fixture_run's own failures exit 8 and 9).
  assert_exit_code 1
  assert_output_contains "no options to run"
  # With no run: here, the refusal must not point at one.
  refute_output_contains "owns test here"
  assert_output_contains "0 of $n test options ran; $n inactive here (bin/devbin help --why names them), 0 skipped (in_all: false)"
}

@test "all under a project handler counts only the config-declared options, since the handler displaces the catalogue" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  check:
    summary: gates
    options:
      mine:
        summary: runs
      yours:
        summary: runs
YAML
  )"
  create_test_command "$proj" check '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  # The control: the catalogue DOES ship language-agnostic check options that
  # would be active here without the handler, so a denominator read from the
  # catalogue would be visibly wrong rather than accidentally equal.
  [ "$(fixture_catalogue_count "$proj" check)" -gt 0 ] || fail "the catalogue ships no check options -- the displacement is not being tested"

  run devbin_run "$proj" check all

  assert_success
  assert_output_contains "2 of 2 check options ran; 0 inactive here, 0 skipped (in_all: false)"
}

@test "all counts an option both config-declared and catalogued as ONE candidate, and runs it once" {
  # The denominator is the DEDUPLICATED union. Counting config and catalogue
  # separately would over-count every override, and the partition would refuse
  # a correct run -- the gate that is red in the ordinary case.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  check:
    options:
      toolchain:
        run: echo ran-toolchain
      format:
        enabled: false
      critic:
        enabled: false
YAML
  )"
  local n opts
  n="$(fixture_catalogue_count "$proj" check)"
  opts="$(fixture_run "$proj" 'builtin_options_for check')" && grep -qx toolchain <<<"$opts" \
    || fail "toolchain is no longer catalogued for check -- this arm no longer overlaps config and catalogue"

  run devbin_run "$proj" check all

  assert_success
  [ "$(grep -c '^ran-toolchain$' <<<"$output")" -eq 1 ] || fail "toolchain did not run exactly once: $output"
  assert_output_contains "1 of $n check options ran; $((n - 1)) inactive here (bin/devbin help --why names them), 0 skipped (in_all: false)"
}

@test "all REFUSES a verdict when an active option vanishes before the loop -- the partition does not sum" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      first:
        summary: runs
      second:
        summary: dropped by the stub
      third:
        summary: runs
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  stub_command_options "$proj" "grep -vx second"

  run devbin_run "$proj" gate all

  assert_failure
  assert_output_contains "ran:first"
  assert_output_contains "ran:third"
  refute_output_contains "ran:second"
  assert_output_contains "2 of 3 gate options ran; 0 inactive here, 0 skipped (in_all: false)"
  assert_output_contains "REFUSING A VERDICT"
  # Named only on refusal, and named by what went missing.
  assert_output_contains "unaccounted for: second"
  # THE LOAD-BEARING REFUTATION: every option that ran passed, and that is
  # exactly the run the old tail called a full pass.
  refute_output_contains "all gate options passed"
}

@test "the partition names an option that ran but was never a candidate" {
  # Pure, so no dispatch: a part member absent from the candidates is the
  # direction a stub cannot reach, because a non-candidate reaching run_option
  # already fails as unrunnable (0063).
  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/resolve'; option_partition_gap 'a b' ' a b c' '' ''"
  assert_success
  assert_output_contains "not an option here: c"
  refute_output_contains "unaccounted for"
  refute_output_contains "counted twice"

  run bash -c ". '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/resolve'; option_partition_gap 'a b' ' a' ' b' ''"
  assert_success
  [ -z "$output" ] || fail "an exact partition reported a gap: $output"
}

@test "all REFUSES a verdict when an option is counted twice -- the wide direction" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      first:
        summary: runs
      second:
        summary: runs
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  stub_command_options "$proj" "sed 'p'"

  run devbin_run "$proj" gate all

  assert_failure
  assert_output_contains "REFUSING A VERDICT"
  assert_output_contains "counted twice: first second"
  refute_output_contains "all gate options passed"
}

@test "an in_all false option still runs when asked for by name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      local_only:
        summary: excluded from all
        in_all: false
YAML
  )"
  create_test_command "$proj" gate '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" gate local_only
  assert_success
  assert_output_contains "ran:local_only"
}

@test "help lists all for a command with options" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gate:
    summary: gates
    options:
      one:
        summary: first
      two:
        summary: second
YAML
  )"
  create_test_command "$proj" gate >/dev/null
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "all"
  assert_output_contains "every option above, one pass"
}

# ============================================================================
# LANGUAGE SCOPING AND EXCLUSION
# ============================================================================

@test "a built-in option is inactive when its language is not declared" {
  # NO project handler here, deliberately. This is about a BUILT-IN option's
  # language scoping, and a project handler owns its whole option set (AC-04.4)
  # -- so adding one would route `test mix` straight to it and test the
  # shadowing rule instead of the rule named above. An earlier version of this
  # test did exactly that and passed for the wrong reason.
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" test mix
  assert_exit_code 2
  assert_output_contains "not available here"
  assert_output_contains "does not declare the 'elixir' language"
}

@test "an Intent-driven built-in is INACTIVE in a project with no intent/, says why, and check all passes over it (0156)" {
  # check critic and docs agents drive Intent, and ran in every project: a
  # project that is not an Intent project failed check all on a gate it never
  # chose, naming Intent's config as the remedy.
  proj="$(mkproj plain <<'YAML'
project:
  name: plain
YAML
  )"
  run devbin_run "$proj" check critic
  assert_exit_code 2
  assert_output_contains "this project has no intent/, which devbin's own check critic needs"
  run devbin_run "$proj" docs agents
  assert_exit_code 2
  assert_output_contains "agents needs intent/"
  refute_output_contains "declare project.languages"
  local n
  n="$(fixture_catalogue_count "$proj" check)"
  run devbin_run "$proj" check all
  assert_success
  refute_output_contains "FAILED: critic"
  # Counted inactive, so the partition still sums: the options that ran are the
  # ones active here, critic not among them.
  assert_output_contains "check options ran; "
  [[ "$output" =~ ([0-9]+)\ of\ $n\ check\ options\ ran\;\ ([0-9]+)\ inactive\ here ]] || fail "no count over $n options: $output"
  [ "$((BASH_REMATCH[1] + BASH_REMATCH[2]))" -eq "$n" ] || fail "the counts do not sum to $n: $output"
  run devbin_run "$proj" help --why check critic
  assert_output_contains "declaring commands.check.options.critic in bin/.devbin/config.yaml runs it anyway"
}

@test "with intent/ there, check critic still runs and fails loudly when Intent's config is missing (0156)" {
  # Keyed on the directory, never on the config: an Intent project that lost
  # its config must keep today's loud diagnosis, not go quietly inactive.
  proj="$(mkproj intentish <<'YAML'
project:
  name: intentish
YAML
  )"
  mkdir -p "$proj/intent" "$proj/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$proj/fakebin/intent"
  chmod +x "$proj/fakebin/intent"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_exit_code 1
  refute_output_contains "has no intent/"
  assert_output_contains "no config at"
  assert_output_contains "intent/.config/config.json"
}

@test "intent/ counts as a directory or a link: a file named intent does not, and a link to nothing does (0156)" {
  # A FILE of that name is not the directory, so critic stays inactive; a link to
  # nothing is an Intent project's tree gone wrong, so critic runs and says so.
  proj="$(mkproj odd <<'YAML'
project:
  name: odd
YAML
  )"
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$proj/fakebin/intent"
  chmod +x "$proj/fakebin/intent"
  : >"$proj/intent"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_exit_code 2
  assert_output_contains "has no intent/"
  rm "$proj/intent"
  ln -s "$proj/nothing-here" "$proj/intent"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_exit_code 1
  refute_output_contains "has no intent/"
  assert_output_contains "no config at"
}

@test "what an option needs is asked of the project root, from any directory in it (0156)" {
  proj="$(mkproj deep <<'YAML'
project:
  name: deep
YAML
  )"
  mkdir -p "$proj/intent" "$proj/sub/dir" "$proj/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$proj/fakebin/intent"
  chmod +x "$proj/fakebin/intent"
  run env PATH="$proj/fakebin:$PATH" sh -c 'cd "$1/sub/dir" && "$1/bin/devbin" check critic' _ "$proj"
  assert_exit_code 1
  refute_output_contains "has no intent/"
  assert_output_contains "no config at"
}

@test "a command whose options are switched off or held back names each held-back option with what it needs (0156)" {
  # Off as a command, check names nothing per option anywhere else, so a
  # pointer to "their own reasons" led nowhere: the intent/ that check critic
  # needs is said here.
  proj="$(mkproj half <<'YAML'
project:
  name: half
commands:
  check:
    options:
      format:
        enabled: false
      toolchain:
        enabled: false
YAML
  )"
  run devbin_run "$proj" help --why check
  assert_output_contains "format, toolchain switched off"
  assert_output_contains "critic needs intent/"
}

@test "a project that declares check critic runs it, whatever its tree holds (0156)" {
  proj="$(mkproj declared <<'YAML'
project:
  name: declared
commands:
  check:
    options:
      critic:
        summary: the project's own word that it wants the critic
YAML
  )"
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$proj/fakebin/intent"
  chmod +x "$proj/fakebin/intent"
  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check critic
  assert_exit_code 1
  refute_output_contains "has no intent/"
  # It ran: the refusal of check critic itself, about Intent's config, is what
  # failed it.
  assert_output_contains "no config at"
}

@test "the language refusal names the list it read and the file that list lives in" {
  # Issue 0062. project.languages in bin/.devbin/config.yaml is GATE SCOPE, and
  # the list in intent/.config/config.json is PROJECT COMPOSITION: different
  # facts by design (lib/config.reference.yaml). A refusal naming neither sent
  # Utilz toward "fixing" a correct declaration -- it read "does not declare
  # the 'rust' language" about a project whose Intent config declared rust.
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" test mix
  assert_exit_code 2
  assert_output_contains "does not declare the 'elixir' language in project.languages ("
  assert_output_contains "/config.yaml)"
}

@test "a COMMAND refused for its language names the same list and file" {
  # One sentence for both levels. The command-level twin printed its own copy,
  # and two spellings of one refusal are two things to keep in step.
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" iex
  assert_failure
  assert_output_contains "does not declare the 'elixir' language in project.languages ("
}

@test "a project handler is asked about its own options, not vetted against the catalogue" {
  # The other side of the same rule: `test mix` against a PROJECT handler is the
  # handler's business even though `mix` is a built-in option name devbin scopes
  # to Elixir. Refusing it with "does not declare the 'elixir' language" -- in a
  # project that never asked devbin for the built-in -- is a wrong answer to a
  # question devbin should not be answering.
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
YAML
  )"
  create_test_command "$proj" test >/dev/null
  run devbin_run "$proj" test mix
  assert_success
  assert_output "ran:test args:mix"
}

@test "a built-in option is active when its language is declared" {
  proj="$(mkproj exproj <<'YAML'
project:
  name: exproj
  languages:
    - elixir
commands:
  test:
    summary: gates
YAML
  )"
  create_builtin_command "$proj" test >/dev/null
  run devbin_run "$proj" test mix
  assert_success
  assert_output_contains "ran:mix"
}

@test "option-level enabled false drops one gate and keeps the command" {
  proj="$(mkproj exproj <<'YAML'
project:
  name: exproj
  languages:
    - elixir
commands:
  test:
    summary: gates
    options:
      mix:
        enabled: false
YAML
  )"
  create_builtin_command "$proj" test >/dev/null
  run devbin_run "$proj" test mix
  assert_exit_code 2
  assert_output_contains "it is disabled in"
  # The command itself survives -- credo is still an active elixir gate.
  run devbin_run "$proj" test credo
  assert_success
  assert_output_contains "ran:credo"
}

@test "a project handler displaces the built-in option set entirely" {
  # Shadowing is total, not partial. A project replacing `test` is saying its
  # gates are different, so inheriting mix/credo would synthesise an `all` that
  # calls the project's handler with options it has never heard of.
  proj="$(mkproj exproj <<'YAML'
project:
  name: exproj
  languages:
    - elixir
commands:
  test:
    summary: gates
    options:
      bespoke:
        summary: the only gate here
YAML
  )"
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" test all
  assert_success
  assert_output_contains "ran:bespoke"
  refute_output_contains "ran:mix"
  refute_output_contains "ran:credo"
}

@test "an explicitly declared option is active whatever the languages say" {
  # Language scoping's third route: this is how a shell project adds a bats
  # gate that devbin
  # never shipped.
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
commands:
  test:
    summary: gates
    options:
      bats:
        summary: BATS suite
YAML
  )"
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "ran:%s\n" "$1"'
  run devbin_run "$proj" test bats
  assert_success
  assert_output_contains "ran:bats"
}

@test "command-level enabled false deactivates the whole command" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  publish:
    summary: publish things
    enabled: false
YAML
  )"
  run devbin_run "$proj" publish
  assert_exit_code 2
  # The claim is that deactivation is VISIBLE, so what matters is that the
  # refusal points at the config rather than reading as a typo. The wording
  # tightened in WP-14 to name the file, matching option_unavailable_reason.
  assert_output_contains "config.yaml"
  refute_output_contains "unknown command"
}

@test "a deactivated command does not appear in help" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  visible:
    summary: shown
    run: true
  publish:
    summary: hidden
    enabled: false
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "visible"
  # Anchored on the rendered command column, not a bare substring: `publish` is
  # a perfectly ordinary word to find in another command's summary prose, and
  # the claim here is that it is not LISTED.
  refute_output_matches '(^|'$'\n'')  publish '
}

@test "a project handler switched off with enabled: false is neither listed nor answered by help" {
  # enabled: false wins over everything, a project handler of the same name
  # included (configuration.md). The dispatcher honoured that and help did not:
  # known_commands' handler pass listed every cmd/<name> without asking
  # command_active, so `help` offered a command `bin/devbin <name>` refused.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  visible:
    summary: shown
    run: true
  gone:
    enabled: false
YAML
  )"
  printf '#!/usr/bin/env bash\necho ran:gone\n' >"$proj/bin/.devbin/cmd/gone"
  chmod +x "$proj/bin/.devbin/cmd/gone"
  run devbin_run "$proj" gone
  assert_exit_code 2
  refute_output_contains "ran:gone"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "visible"
  # A handler with no summary renders as a bare name, so the row is matched to
  # the end of its line as well as to a following summary.
  refute_output_matches '(^|'$'\n'')  gone( |$|'$'\n'')'
  run devbin_run "$proj" help gone
  assert_exit_code 2
  assert_output_contains "config.yaml"
}

@test "language scoping filters what help offers" {
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
commands:
  test:
    summary: gates
YAML
  )"
  create_test_command "$proj" test >/dev/null
  run devbin_run "$proj" help
  assert_success
  # `shell` is the only declared language, so the elixir and rust gates must not
  # be offered -- this is the whole point of language scoping.
  assert_output_contains "shell"
  refute_output_contains "mix"
  refute_output_contains "credo"
  refute_output_contains "clippy"
}

@test "all runs only the options the declared languages activate" {
  proj="$(mkproj shellproj <<'YAML'
project:
  name: shellproj
  languages:
    - shell
commands:
  test:
    summary: gates
YAML
  )"
  create_builtin_command "$proj" test >/dev/null
  run devbin_run "$proj" test all
  assert_success
  assert_output_contains "ran:shell"
  refute_output_contains "ran:mix"
  refute_output_contains "ran:rust"
}

# ============================================================================
# DOGFOODING: DEVBIN USES DEVBIN
# ============================================================================

@test "Devbin's own dispatcher reports its identity and version" {
  run devbin_run "$DEVBIN_HOME" -v
  assert_success
  # devbin's own checkout answers with the tree line (0213): which tree, and
  # which commit, with +dirty while the runtime set has uncommitted changes, or
  # unknown when git cannot read the checkout.
  assert_output_matches '^devbin [0-9]+\.[0-9]+\.[0-9]+ \(dev, (([0-9a-f]{12})(\+dirty)?|unknown)\)$'
}

# ============================================================================
# WHICH BYTES ARE RUNNING -- the framework's provenance vs the project's tree
# ============================================================================

# THE ONE THAT MATTERS. In a consumer, devbin's bytes came from a DIFFERENT
# repository, so the consumer's own HEAD is not an approximation of devbin's
# provenance -- it names unrelated software. The manifest records where the
# bytes came from and that is the only honest answer.
@test "devbin --version in a consumer reports the MANIFEST's commit, never the consumer's own HEAD" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  alias: dm
YAML
)"
  git -C "$proj" init -q
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m consumer
  local consumer_head
  consumer_head="$(git -C "$proj" rev-parse HEAD)"

  # A distinctive recorded provenance, so the two can never be confused.
  sed -i.bak 's|^# source_commit: .*|# source_commit: aaaaaaaabbbbbbbbccccccccdddddddd11112222|' \
    "$proj/bin/.devbin/manifest.sha256"

  run devbin_run "$proj" devbin --version

  assert_success
  assert_output_contains "aaaaaaaabbbbbbbbccccccccdddddddd11112222"
  refute_output_contains "$consumer_head"
}

# ISSUE 0043 WAS A READER THAT KEPT THE SHA AND THREW THE SENTENCE AWAY, so
# provenance saying "no commit matches this" rendered as an ordinary clean row.
# This is a new reader of the same field.
@test "the manifest's dirty provenance survives WHOLE -- the sentence is not trimmed off" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  alias: dm
YAML
)"
  sed -i.bak 's|^# source_commit: .*|# source_commit: deadbeef1234 +dirty -- THESE BYTES MATCH NO COMMIT|' \
    "$proj/bin/.devbin/manifest.sha256"

  run devbin_run "$proj" devbin --version

  assert_success
  assert_output_contains "deadbeef1234"
  assert_output_contains "THESE BYTES MATCH NO COMMIT"
}

# A manifest recording no provenance must SAY so. Falling back to the local HEAD
# here would print the consumer's commit as devbin's -- 0043's defect in a hat.
@test "a manifest with no recorded provenance says unrecorded, and does not substitute the local HEAD" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  alias: dm
YAML
)"
  git -C "$proj" init -q
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m consumer
  local consumer_head
  consumer_head="$(git -C "$proj" rev-parse HEAD)"

  sed -i.bak '/^# source_commit:/d' "$proj/bin/.devbin/manifest.sha256"

  run devbin_run "$proj" devbin --version

  assert_success
  assert_output_contains "unrecorded"
  refute_output_contains "$consumer_head"
}

@test "Devbin's own help offers no Elixir gate" {
  run devbin_run "$DEVBIN_HOME" help
  assert_success
  assert_output_contains "bats"
  refute_output_contains "mix"
  refute_output_contains "credo"
}

# ============================================================================
# SHARED OPTIONS THROUGH THE DISPATCHER (WP-05)
# ============================================================================

@test "a shared option is consumed by the dispatcher and reaches the handler as environment" {
  # The payoff of the WP-05 fold. In the corpus every command script called
  # parse_common_opts itself; here the dispatcher parses once and the handler --
  # a separate process -- inherits the result without knowing the option exists.
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
  greet:
    summary: greet
YAML
  )"
  create_test_command "$proj" greet '#!/usr/bin/env bash
set -euo pipefail
printf "MIX_ENV=%s args=%s\n" "${MIX_ENV:-unset}" "$*"' >/dev/null
  run_in_project "$proj" greet --env test loudly
  assert_success
  assert_output_contains "MIX_ENV=test"
  assert_output_contains "args=loudly"
}

@test "an undeclared option passes straight through to the handler" {
  # `devbin test mix --trace` has to reach mix. Devbin only consumes what the
  # project declared as shared.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - test
    export: MIX_ENV
commands:
  greet:
    summary: greet
YAML
  )"
  create_test_command "$proj" greet >/dev/null
  run_in_project "$proj" greet --trace --seed 42
  assert_success
  assert_output_contains "args:--trace --seed 42"
}

@test "a bad shared-option value is refused before the handler runs" {
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
  greet:
    summary: greet
YAML
  )"
  create_test_command "$proj" greet '#!/usr/bin/env bash
printf "HANDLER RAN\n"' >/dev/null
  run_in_project "$proj" greet --env staging
  assert_exit_code 1
  assert_output_contains "unknown --env 'staging'"
  refute_output_contains "HANDLER RAN"
}

@test "a command still dispatches when the shared options consume every argument" {
  # The bash 3.2 empty-array case, end to end: DEVBIN_ARGS is emptied and the
  # guarded expansion must yield zero words rather than abort under `set -u`.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  env:
    values:
      - test
    export: MIX_ENV
commands:
  greet:
    summary: greet
YAML
  )"
  create_test_command "$proj" greet >/dev/null
  run_in_project "$proj" greet --env test
  assert_success
  assert_output_contains "ran:greet args:"
}

@test "the dispatcher refuses a bash below the >= 5 floor" {
  # Issue 0022 reversed the old floor: devbin REQUIRES bash >= 5 and refuses older
  # with remediation, instead of targeting 3.2. /bin/bash on macOS is 3.2.57
  # permanently, which makes it the one real old bash a Mac always carries --
  # the refusal is proven against it rather than simulated. On a platform whose
  # /bin/bash is already >= 5 there is no old bash to prove against.
  [ -x /bin/bash ] || skip "no /bin/bash on this platform"
  v="$(/bin/bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')"
  [ "$v" -lt 5 ] || skip "/bin/bash is major $v; no old bash to prove the refusal against"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run_under "$proj" /bin/bash --version
  assert_failure
  assert_output_contains "bash >= 5"
  assert_output_contains "brew install bash"
}

# THE FLOOR REACHES THE HANDLERS (issue 0076). The check above is on the bash
# running the DISPATCHER. Handlers are separate processes reached through
# `#!/usr/bin/env bash`, so they run on whatever bash PATH resolves -- and a
# dispatcher started by an explicit bash 5 under a PATH that finds 3.2 ran every
# handler on 3.2 with no refusal. The dispatcher now asks the PATH's bash too.

# probe_proj -- a fixture whose one project handler reports the bash it ran on.
probe_proj() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" probe '#!/usr/bin/env bash
printf "handler bash: %s\n" "$BASH_VERSION"' >/dev/null
  printf '%s\n' "$proj"
}

@test "the dispatcher refuses when PATH resolves bash below the floor, before any handler runs on it" {
  proj="$(probe_proj)"
  local stub="$DEVBIN_TEST_TMPDIR/oldbash"
  mkdir -p "$stub"
  # A stand-in for an old bash that answers the version question the way 3.2
  # would. Portable where a real 3.2 is not: Linux runners carry none.
  printf '#!/bin/sh\nprintf "3 3.2.57(1)-release"\n' >"$stub/bash"
  chmod +x "$stub/bash"

  run bash -c "cd '$proj' && PATH='$stub':\"\$PATH\" '$BASH' ./bin/devbin probe </dev/null"

  assert_failure
  assert_output_contains "bash >= 5"
  assert_output_contains "$stub/bash"
  assert_output_contains "brew install bash"
  refute_output_contains "handler bash:"
}

@test "the dispatcher's refusal of an old PATH bash names Homebrew's bash 5, to go ahead of that old bash's own directory (0253)" {
  # The PATH remedy names where the refusing bash is, not /bin: here it is a
  # stand-in for an old bash earlier on PATH, and the test's own Homebrew bin,
  # the one place looked in while HOMEBREW_PREFIX is set, holds a stand-in bash
  # that answers 5.
  proj="$(probe_proj)"
  local stub="$DEVBIN_TEST_TMPDIR/oldbash"
  mkdir -p "$stub" "$HOMEBREW_PREFIX/bin"
  printf '#!/bin/sh\nprintf "3 3.2.57(1)-release"\n' >"$stub/bash"
  printf '#!/bin/sh\nprintf 5\n' >"$HOMEBREW_PREFIX/bin/bash"
  chmod +x "$stub/bash" "$HOMEBREW_PREFIX/bin/bash"

  run bash -c "cd '$proj' && PATH='$stub':\"\$PATH\" '$BASH' ./bin/devbin probe </dev/null"

  assert_failure
  assert_output_contains "a bash >= 5 is at $HOMEBREW_PREFIX/bin/bash -- put $HOMEBREW_PREFIX/bin ahead of $stub on PATH"
  refute_output_contains "brew install bash"
  refute_output_contains "handler bash:"
}

@test "the dispatcher refuses a PATH bash that cannot answer its version, before any handler runs on it" {
  # Every `env bash` handler would run on it, so the dispatcher is the earliest
  # loud point (issue 0076).
  proj="$(probe_proj)"
  local stub="$DEVBIN_TEST_TMPDIR/brokenbash"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 1\n' >"$stub/bash"
  chmod +x "$stub/bash"

  run bash -c "cd '$proj' && PATH='$stub':\"\$PATH\" '$BASH' ./bin/devbin probe </dev/null"

  assert_failure
  assert_output_contains "could not ask $stub/bash its version"
  refute_output_contains "handler bash:"
}

@test "the dispatcher refuses a PATH bash whose version answer is not a number, by name rather than by accident" {
  # Without the check, `[ "not" -ge 5 ]` errors and control falls through to
  # the floor refusal, which then reads "this is bash bash".
  proj="$(probe_proj)"
  local stub="$DEVBIN_TEST_TMPDIR/notbash"
  mkdir -p "$stub"
  printf '#!/bin/sh\nprintf "not bash"\n' >"$stub/bash"
  chmod +x "$stub/bash"

  run bash -c "cd '$proj' && PATH='$stub':\"\$PATH\" '$BASH' ./bin/devbin probe </dev/null"

  assert_failure
  assert_output_contains "answered its version as 'not bash', which is not a bash version"
  refute_output_contains "this is bash bash"
  refute_output_contains "handler bash:"
}

@test "the dispatcher runs handlers when PATH resolves a DIFFERENT bash that meets the floor" {
  # The over-refusal control: a PATH bash that is not the dispatcher's own file
  # but IS >= 5 must pass, or the check refuses every machine with two bashes.
  proj="$(probe_proj)"
  local other="$DEVBIN_TEST_TMPDIR/otherbash"
  mkdir -p "$other"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$BASH" >"$other/bash"
  chmod +x "$other/bash"

  run bash -c "cd '$proj' && PATH='$other':\"\$PATH\" '$BASH' ./bin/devbin probe </dev/null"

  assert_success
  assert_output_contains "handler bash: ${BASH_VERSION}"
}

@test "issue 0076's measured case: a bash-5 dispatcher under a PATH finding macOS's 3.2 refuses" {
  [ -x /bin/bash ] || skip "no /bin/bash on this platform"
  v="$(/bin/bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')"
  [ "$v" -lt 5 ] || skip "/bin/bash is major $v; no old bash to prove the refusal against"
  proj="$(probe_proj)"

  run bash -c "cd '$proj' && env PATH=/usr/bin:/bin '$BASH' ./bin/devbin probe </dev/null"

  assert_failure
  assert_output_contains "bash >= 5"
  assert_output_contains "/bin/bash"
  refute_output_contains "handler bash: 3."
}

@test "the whole stack runs under a floor-compliant bash" {
  # The positive half of the floor, carrying the coverage the old 3.2 test
  # held: config load, activation, `all` synthesis and shared-option parsing
  # driven full-stack -- now under `bash` from PATH, the runtime projects
  # actually use. A project-specific command name, not a built-in: this test is
  # about the shell the stack runs under, so it must not depend on which
  # built-in gates have shipped.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
options:
  env:
    values:
      - test
    export: MIX_ENV
commands:
  gates:
    summary: project gates
    options:
      one:
        summary: first
        run: echo ran-one
      two:
        summary: second
        run: echo ran-two
YAML
  )"
  run devbin_run_under "$proj" bash gates all --env test
  assert_success
  assert_output_contains "ran-one"
  assert_output_contains "ran-two"
  assert_output_contains "all gates options passed"
}

@test "an unbuilt built-in option reports not-yet and does not abandon the rest of all" {
  # Two things at once, because they were one defect. A built-in option devbin
  # ships but has not implemented must say so with exit 3 rather than "no
  # handler and no run:", AND `all` must keep going past it -- run_option is
  # called in the dispatcher's own process, so an exit there would silently
  # violate AC-04.6.
  #
  # This CONSTRUCTS the condition rather than borrowing whichever built-in
  # happens to be unimplemented. It used to point at `check`, then `fmt`, then
  # `db`, needing a rewrite each time one shipped -- and once the library is
  # complete there would be nothing left to point at, so the test would have
  # been deleted for the worst possible reason.
  #
  # Removing the handler from the fixture's copied lib reproduces it exactly,
  # and covers a real case besides: a partial or damaged install, where the
  # catalogue offers an option whose implementation is not packaged.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  db:
    summary: database
    options:
      later:
        summary: a declared one
        run: echo ran-later
YAML
  )"
  rm -f "$proj/bin/.devbin/lib/cmd/db"
  run_in_project "$proj" db all
  assert_failure
  # db.setup's catalogue row carries a real command line, and it still needs
  # devbin's db handler -- so the refusal names the handler, not a bare name
  # (issue 0111; this arm is the one that caught the first cut saying otherwise).
  assert_output_contains "handler for 'db' is missing from this install"
  refute_output_contains "ships the name only"
  refute_output_contains "not built yet"
  refute_output_contains "no handler and no run"
  # The configured option still ran, after the unbuilt ones failed.
  assert_output_contains "ran-later"
  assert_output_contains "FAILED:"
}

@test "a config-declared option is not swallowed by the built-in that owns its command" {
  # run_option consults config's `run:` BEFORE the built-in library. Without
  # that order lib/cmd/check takes the option, does not find it in the
  # catalogue, and reports it as unknown -- while config plainly declares it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    summary: gates
    options:
      bespoke:
        summary: ours alone
        run: echo ran-bespoke
YAML
  )"
  run_in_project "$proj" check bespoke
  assert_success
  assert_output_contains "ran-bespoke"
  refute_output_contains "unknown check option"
}

@test "all points at the seal of every gate that failed" {
  # The seal ledger (WP-06). Each gate already prints its own `verdict:` line,
  # but across a multi-option `all` those have scrolled away by the time the
  # summary prints -- so the summary re-states them, from the ledger the gates
  # appended to. Not from a LATEST_* pointer, which a peer's run can re-point.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gates:
    summary: project gates
    options:
      good:
        summary: passes
      bad:
        summary: fails
YAML
  )"
  create_test_command "$proj" gates '#!/usr/bin/env bash
set -euo pipefail
. "${DEVBIN_LIB}/helpers"
. "${DEVBIN_LIB}/runlog"
cd "$PROJECT_ROOT"
case "$1" in
  good) run_gate --label "gate good" --suffix good --out-dir tmp/g -- true ;;
  bad)  run_gate --label "gate bad"  --suffix bad  --out-dir tmp/g -- bash -c "echo Error: broke; exit 1" ;;
esac' >/dev/null
  run_in_project "$proj" gates all
  assert_failure
  assert_output_contains "FAILED:"
  assert_output_contains "gate bad"
  # The summary names the failing gate's seal. `.good.errors` still appears
  # earlier in the run -- the passing gate prints its own verdict line, which is
  # the point of the mechanism -- so the discriminating assertion is that the
  # FAILED list names bad and not good.
  assert_output_contains "$proj/tmp/g/"
  assert_output_contains ".bad.errors"
  assert_output_contains "FAILED: bad"
  refute_output_contains "FAILED: good"
  # And the seals themselves carry the invariant: green empty, red not.
  assert_file_empty "$proj/tmp/g/LATEST_GOOD.errors"
  [ -s "$proj/tmp/g/LATEST_BAD.errors" ]
}

# ============================================================================
# CONFIG SITS AHEAD OF THE CATALOGUE, AT THE ACTIVATION LEVEL TOO
# ============================================================================
#
# Both tests below pin defects that WP-07's help tests surfaced in WP-04 code.
# They live here rather than in help.bats because neither is about help: help
# was only the first caller to ask the question in this shape.

@test "a config-declared run: activates a command whose built-in options are all scoped out" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  write_config "$proj" <<'YAML'
project:
  name: demo
commands:
  test:
    summary: The project's own idea of testing
    run: /bin/echo ran-the-declared-command
YAML
  # `test` HAS built-in options -- mix, credo, rust, swift, lua, shell -- and
  # this project declares no languages, so none of them is active. The option
  # branch of command_active used to answer first and return 1, so devbin said
  # "unknown command: test" about a command config plainly declares.
  run devbin_run "$proj" test
  assert_success
  assert_output_contains "ran-the-declared-command"

  run devbin_run "$proj" help
  assert_success
  assert_output_contains "The project's own idea of testing"
}

@test "all over a command-level run: with no options is refused, names the bare command, and runs nothing (0128)" {
  # 0128's option (b): devbin synthesises `all` where there are
  # options to sweep, and a command-level `run:` with none refuses it, exit 1,
  # as before 0128. devbin runs that line, so `all` added to it would be a new
  # command the project never wrote. A handler with no options is handed `all`
  # (contract.bats, the resolution order's totality), and the option-less
  # built-ins answer for
  # themselves (surfaces.bats's table).
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  write_config "$proj" <<'YAML'
project:
  name: demo
commands:
  media:
    summary: Media
    run: scripts/media
YAML
  mkdir -p "$proj/scripts"
  printf '#!/bin/sh\necho "ran:media args=$*"\n' >"$proj/scripts/media"
  chmod +x "$proj/scripts/media"

  run devbin_run "$proj" media all --fast
  assert_exit_code 1
  assert_output_contains "'bin/devbin media all' has no options to run: commands.media.run in bin/.devbin/config.yaml owns media here, and 'bin/devbin media' runs it"
  assert_output_contains "0 of 0 media options ran"
  refute_output_contains "ran:media"

  # The control, and the refusal's pointer held true: the bare command runs the
  # line, with the words it was given, so the stub above could have printed.
  run devbin_run "$proj" media --fast
  assert_success
  assert_output_contains "ran:media args=--fast"
}

@test "test all over a test run: that reads its first word as a filter runs no test and does not pass (0128)" {
  # THE FALSE GREEN option (b) closes. cargo reads a word after `cargo test`
  # as a test-name filter, so a first draft handed `all` to
  # `commands.test.run: cargo test`, cargo ran 0 tests, and `test all` exited
  # 0 over a failing suite. The stub below behaves as cargo does: handed a
  # word, it filters everything out and passes; handed none, it runs the
  # failing test. Each run is logged, so an absence here is measured.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  test:
    run: scripts/filtered
YAML
  )"
  mkdir -p "$proj/scripts"
  cat >"$proj/scripts/filtered" <<'STUB'
#!/bin/sh
echo "filtered $*" >>ran.log
if [ $# -gt 0 ]; then
  echo "running 0 tests; 1 filtered out"
  exit 0
fi
echo "test broken ... FAILED"
exit 101
STUB
  chmod +x "$proj/scripts/filtered"

  run devbin_run "$proj" test all
  assert_exit_code 1
  assert_output_contains "'bin/devbin test all' has no options to run: commands.test.run in bin/.devbin/config.yaml owns test here, and 'bin/devbin test' runs it"
  refute_output_contains "0 tests"
  [ ! -e "$proj/ran.log" ] || fail "the runner ran under test all:
$(cat "$proj/ran.log")"

  # The control: the bare command runs the runner, which fails as the suite
  # does, and its log shows the run -- so the log above could have been written.
  run devbin_run "$proj" test
  assert_exit_code 101
  assert_output_contains "FAILED"
  grep -qx 'filtered ' "$proj/ran.log" || fail "the bare run was not logged:
$(cat "$proj/ran.log" 2>&1)"
}

@test "a word typed after devbin's gate flags over a run: line is the same word: all refused with no options and swept with some, an option run as its own (0128)" {
  # `test --purge all` over a command-level run: handed the line
  # `all` by word order -- unsealed, as `--purge all`, passed on and said
  # (0122); sealed, as `all` alone, once run_command lifted the flag. Under a
  # run: line, arg_route reads past the gate flags for the word it asks.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  test:
    run: scripts/filtered
  sealed:
    run: scripts/filtered
    log: SEALED
  media:
    run: scripts/media
    options:
      fast:
        summary: the fast media pass
  rq:
    run: scripts/media
    options:
      one:
        run: ./tool
        grammar: generic
        log: ONE
      off:
        run: ./tool
        enabled: false
      two:
        summary: goes to the command's line
  fr:
    run: scripts/media
    options:
      --allow-empty:
        run: ./tool
  fq:
    options:
      --purge:
        run: ./tool
  qa:
    options:
      one:
        run: ./tool
        grammar: generic
        log: ONE
YAML
  )"
  mkdir -p "$proj/scripts"
  printf '#!/bin/sh\necho "filtered $*" >>ran.log\n[ $# -gt 0 ] && exit 0\nexit 101\n' >"$proj/scripts/filtered"
  printf '#!/bin/sh\necho "ran:media args=$*"\n' >"$proj/scripts/media"
  printf '#!/bin/sh\necho "tool args: $*" >>tool.log\n' >"$proj/tool"
  chmod +x "$proj/scripts/filtered" "$proj/scripts/media" "$proj/tool"

  # No options: refused with the bare command's pointer, the line never run --
  # unsealed and sealed, one flag or two, and with a word after the `all`.
  local cmd flags
  for cmd in test sealed; do
    for flags in "--purge all" "--allow-empty --purge all" "--purge all unit"; do
      # shellcheck disable=SC2086 # the words are split on purpose, one each
      run devbin_run "$proj" "$cmd" $flags
      assert_exit_code 1
      assert_output_contains "'bin/devbin $cmd all' has no options to run: commands.$cmd.run in bin/.devbin/config.yaml owns $cmd here, and 'bin/devbin $cmd' runs it"
      [ ! -e "$proj/ran.log" ] || fail "the line ran under $cmd $flags:
$(cat "$proj/ran.log")"
    done
  done

  # With options, the same word order sweeps them, and the line is handed the
  # option, never `all`.
  run devbin_run "$proj" media --allow-empty all
  assert_success
  grep -qx 'ran:media args=fast' <<<"$output" ||
    fail "the line was not handed the option alone:
$output"
  assert_output_contains "1 of 1 media options ran"

  # And the flags typed before `all` reach run_all: a sealed option purges its
  # old pair, as `all --purge` does.
  mkdir -p "$proj/tmp/rq"
  touch "$proj/tmp/rq/20200101-0000.ONE.out" "$proj/tmp/rq/20200101-0000.ONE.errors"
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" rq --purge all
  assert_success
  [ ! -e "$proj/tmp/rq/20200101-0000.ONE.out" ] || fail "--purge before all did not reach the sealed option:
$output"
  grep -qx 'tool args: ' "$proj/tool.log" || fail "the option's own run: was not run bare:
$(cat "$proj/tool.log" 2>&1)"

  # A declared option typed after the flags is that option, as it is typed
  # first: its own run:, sealed, the flag acted on -- never the command's line
  # handed `--purge one`. And a switched-off one is refused as named first.
  touch "$proj/tmp/rq/20200101-0000.ONE.out" "$proj/tmp/rq/20200101-0000.ONE.errors"
  rm -f "$proj/tool.log"
  run devbin_run "$proj" rq --purge one
  assert_success
  refute_output_contains "ran:media"
  [ ! -e "$proj/tmp/rq/20200101-0000.ONE.out" ] || fail "--purge before one did not reach its seal:
$output"
  grep -qx 'tool args: ' "$proj/tool.log" || fail "the option's own run: was not run bare:
$(cat "$proj/tool.log" 2>&1)"
  run devbin_run "$proj" rq --allow-empty off
  assert_exit_code 2
  assert_output_contains "'bin/devbin rq off' is not available here: it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "ran:media"

  # The words around the option keep their order: an option with no run: of
  # its own goes to the line with the flags and the rest, exactly as when the
  # option is typed first.
  run devbin_run "$proj" rq --purge two x
  assert_success
  grep -qx 'ran:media args=two --purge x' <<<"$output" || fail "rq --purge two x did not hand the line its words in order:
$output"
  run devbin_run "$proj" rq two --purge x
  assert_success
  grep -qx 'ran:media args=two --purge x' <<<"$output" || fail "rq two --purge x, the control:
$output"

  # An option config names like a gate flag is that option wherever it is
  # typed, over a run: line and over options alone, as before this change --
  # and never an empty word handed to the line.
  rm -f "$proj/tool.log"
  run devbin_run "$proj" fr --allow-empty
  assert_success
  refute_output_contains "ran:media"
  grep -qx 'tool args: ' "$proj/tool.log" || fail "fr --allow-empty did not run its option:
$output"
  rm -f "$proj/tool.log"
  run devbin_run "$proj" fq --purge
  assert_success
  grep -qx 'tool args: ' "$proj/tool.log" || fail "fq --purge did not run its option:
$output"

  # Only under a run: line: an options-only command still reads its first word,
  # so a flag before `all` is refused as it always was, and nothing runs.
  rm -f "$proj/tool.log"
  run devbin_run "$proj" qa --purge all
  assert_exit_code 1
  [ ! -e "$proj/tool.log" ] || fail "qa --purge all ran an option:
$(cat "$proj/tool.log")"

  # route_word_at's own answer, the one reading both sides ask: a position
  # from 1, and 0 when a run: line is handed only bare gate flags -- no word
  # to route on, where pointing at the last flag would be read by nothing.
  local q
  for q in "0:test --purge" "0:test --purge --allow-empty" "2:test --purge unit" \
    "1:test all" "1:qa --purge all" "2:fr --purge --allow-empty"; do
    # shellcheck disable=SC2086 # the words are split on purpose, one each
    [ "$(fixture_ask "$proj" route_word_at ${q#*:})" = "${q%%:*}" ] ||
      fail "route_word_at ${q#*:} did not answer ${q%%:*}"
  done

  # The controls: gate flags alone still run the line, unsealed here, so the
  # flag is passed on and said (0122), and a word after them that is not `all`
  # still reaches it, so the log above could have been written.
  run devbin_run "$proj" test --purge
  assert_success
  assert_output_contains "devbin did not act on --purge"
  run devbin_run "$proj" test --purge unit
  assert_success
  grep -qx 'filtered --purge' "$proj/ran.log" && grep -qx 'filtered --purge unit' "$proj/ran.log" ||
    fail "the controls were not both logged:
$(cat "$proj/ran.log" 2>&1)"
}

# ============================================================================
# ONE ORDER, ASKED BY EVERY READER (issue 0128)
# ============================================================================
#
# Who runs `bin/devbin <cmd> [<word>]` was decided in six places -- the
# dispatcher's own branches, run_option, run_command, help's two origin
# functions, doctor and dormancy (which asks option_leaf since 0135) -- each
# spelling the tiers out for itself, with nothing keeping them in step.
# arg_route now states the dispatch order, option_run_tier run_option's and
# command_tier run_command's, and each of those acts on its own answer;
# option_leaf follows a route to what runs at its end, the one answer help and
# check's fmt arms read, and dormancy's since 0135. These
# arms hold the names to what the dispatcher actually runs, shape by shape.

# _order_proj -- one fixture holding every tier 0128 names, on stdout. Every
# stub prints who it is and the words it was handed, so a run names its runner.
_order_proj() {
  local proj f
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
    - elixir
commands:
  hand:
    summary: a project handler
    options:
      decl:
        summary: declared, with no run of its own, beside a .d/ sub-handler of its name
  mapd:
    summary: a mapped handler
    handler: mapped-one
  both:
    summary: a cmd/ handler and a mapped one, where the file wins
    handler: mapped-one
  line:
    summary: a command-level run
    run: scripts/line
    options:
      own:
        summary: a line of its own
        run: scripts/own
      bare:
        summary: declared, with no run of its own
  seal:
    summary: a sealed command-level run
    run: scripts/line
    log: SEAL
    options:
      bare:
        summary: declared, with no run of its own
  solo:
    summary: a command-level run with no options
    run: scripts/line
  lineoff:
    summary: a command-level run whose one declared option is switched off
    run: scripts/line
    options:
      off:
        summary: switched off
        enabled: false
  twin:
    summary: a cmd/ handler beside a command-level run, where the handler wins
    run: scripts/line
  offh:
    summary: a project handler whose one declared option is switched off
    options:
      off:
        summary: switched off
        enabled: false
  grp:
    summary: options and nothing else
    options:
      one:
        summary: one
        run: scripts/own
      two:
        summary: declared, and nothing runs it
  badmap:
    summary: a mapped handler that is not there
    handler: not-there
  fmt:
    options:
      md:
        summary: declared, served by devbin's handler, which this fixture removes
  which:
    enabled: true
YAML
  )"
  mkdir -p "$proj/scripts" "$proj/bin/.devbin/cmd/hand.d"
  printf '#!/bin/sh\necho "line:line args=$*"\n' >"$proj/scripts/line"
  printf '#!/bin/sh\necho "line:own args=$*"\n' >"$proj/scripts/own"
  printf '#!/bin/sh\necho "ran:hand args=$*"\n' >"$proj/bin/.devbin/cmd/hand"
  printf '#!/bin/sh\necho "ran:hand.d/sub args=$*"\n' >"$proj/bin/.devbin/cmd/hand.d/sub"
  printf '#!/bin/sh\necho "ran:hand.d/decl args=$*"\n' >"$proj/bin/.devbin/cmd/hand.d/decl"
  printf '#!/bin/sh\necho "ran:mapped-one args=$*"\n' >"$proj/bin/.devbin/cmd/mapped-one"
  printf '#!/bin/sh\necho "ran:both args=$*"\n' >"$proj/bin/.devbin/cmd/both"
  printf '#!/bin/sh\necho "ran:twin args=$*"\n' >"$proj/bin/.devbin/cmd/twin"
  printf '#!/bin/sh\necho "ran:offh args=$*"\n' >"$proj/bin/.devbin/cmd/offh"
  for f in scripts/line scripts/own bin/.devbin/cmd/hand bin/.devbin/cmd/hand.d/sub \
    bin/.devbin/cmd/hand.d/decl bin/.devbin/cmd/mapped-one bin/.devbin/cmd/both \
    bin/.devbin/cmd/twin bin/.devbin/cmd/offh; do
    chmod +x "$proj/$f"
  done
  # A .d/ entry that is not executable is not a sub-handler (is_handler), so
  # its word goes to the handler itself.
  printf '#!/bin/sh\necho "ran:hand.d/noexec"\n' >"$proj/bin/.devbin/cmd/hand.d/noexec"
  # devbin's own `test`, the real handler, with a sub-handler of devbin's own
  # beneath it. A catalogue option runs its catalogue line through the fake bats
  # below, and any other word meets devbin's own refusal, so the catalogue and
  # devbin leaves are two different runs rather than two names for one stub.
  mkdir -p "$proj/bin/.devbin/lib/cmd/test.d"
  printf '#!/bin/sh\necho "ran:test.d/sub args=$*"\n' >"$proj/bin/.devbin/lib/cmd/test.d/sub"
  chmod +x "$proj/bin/.devbin/lib/cmd/test.d/sub"
  # devbin's fmt handler gone, so a declared catalogue option has nothing to run it.
  rm -f "$proj/bin/.devbin/lib/cmd/fmt"
  # A fake iex and a fake bats, so the catalogue's own lines run something harmless.
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\necho "ran:iex args=$*"\n' >"$proj/fakebin/iex"
  printf '#!/bin/sh\necho "ran:bats args=$*"\n' >"$proj/fakebin/bats"
  chmod +x "$proj/fakebin/iex" "$proj/fakebin/bats"
  echo "$proj"
}

@test "project_tier and command_tier name each command's tier from one order (0128)" {
  proj="$(_order_proj)"
  local row cmd want got bad=""
  for row in hand:handler mapd:mapped both:handler badmap:mapped line:run seal:run solo:run grp:none test:none which:none iex:none; do
    cmd="${row%%:*}" want="${row#*:}"
    got="$(fixture_ask "$proj" project_tier "$cmd")" || fail "project_tier $cmd exited $?"
    [ "$got" = "$want" ] || bad="$bad [project_tier $cmd: $got, want $want]"
  done
  # iex is inactive here, and command_tier does not ask: it names what WOULD run
  # a bare command, which is devbin's catalogue line for iex -- no lib/cmd/iex.
  for row in hand:handler mapd:mapped both:handler line:run seal:run solo:run grp:options test:devbin which:none iex:catalogue; do
    cmd="${row%%:*}" want="${row#*:}"
    got="$(fixture_ask "$proj" command_tier "$cmd")" || fail "command_tier $cmd exited $?"
    [ "$got" = "$want" ] || bad="$bad [command_tier $cmd: $got, want $want]"
  done
  [ -z "$bad" ] || fail "tiers named wrongly:$bad"
}

@test "what option_leaf names is what bin/devbin runs, for every tier (0128)" {
  # The one answer every reader of what runs asks, held to the run itself:
  # each row asks option_leaf, then runs the same words through the dispatcher
  # and requires the exit code and the runner's own words. A row whose name and
  # run disagree is the defect 0128 exists to close. A name that cannot be
  # asked is recorded and the run is still compared, so the run half counts at
  # a base that has no option_leaf.
  #
  # Some rows are there for the ROUTE, not the leaf, since two routes can end
  # at one runner: `hand decl` passes decl to the handler itself, where the
  # handler route would descend into hand.d/decl; `seal bare` is sealed under
  # the option's label, where run_command would seal it under the command's;
  # `hand noexec` meets a .d/ entry that is not executable, which is not a
  # sub-handler; and `both x` has a mapped handler and a cmd/ file, where the
  # file wins. `all` has three rows of its own where the route turns on what
  # the project owns: a run: whose one declared option is switched off is
  # refused as one with none (lineoff), a cmd/ handler beside a run: is handed
  # `all` (twin), and so is a handler whose declared options are all switched
  # off (offh).
  proj="$(_order_proj)"
  local cmd word want code expect got bad="" rows=0 table all
  # The table is read into a variable first, so the loop's population can be
  # held to the table's own rows: a command in the loop that read stdin would
  # eat the rows after it, and the loop would end having checked fewer.
  table="$(cat <<'ROWS'
hand|decl|handler|0|ran:hand args=decl
hand|sub|sub-handler|0|ran:hand.d/sub args=
hand|noexec|handler|0|ran:hand args=noexec
hand|other|handler|0|ran:hand args=other
hand|all|all|0|ran:hand args=decl
mapd|x|mapped|0|ran:mapped-one args=x
mapd|all|mapped|0|ran:mapped-one args=all
both|x|handler|0|ran:both args=x
line|own|option-run|0|line:own args=
line|bare|run|0|line:line args=bare
line|zzz|run|0|line:line args=zzz
line|all|all|0|line:line args=bare
seal|bare|run|0|==> seal bare
solo|all|all|1|'bin/devbin solo all' has no options to run: commands.solo.run in bin/.devbin/config.yaml owns solo here, and 'bin/devbin solo' runs it
lineoff|all|all|1|'bin/devbin lineoff all' has no options to run: commands.lineoff.run in bin/.devbin/config.yaml owns lineoff here, and 'bin/devbin lineoff' runs it
twin|all|handler|0|ran:twin args=all
offh|all|handler|0|ran:offh args=all
test|shell|catalogue|0|ran:bats args=tests
test|zzz|devbin|1|unknown test option: zzz
grp|one|option-run|0|line:own args=
grp|zzz|options|1|usage: bin/devbin grp <one|two|all>
grp|two|declared-unrunnable|1|is declared but has no run: and no handler
which|x|none|3|resolves, but nothing here runs it
test|rust|inactive|2|'bin/devbin test rust' is not available here
precommit|x|inactive|2|'bin/devbin precommit' is not available here
fmt|md|unrunnable|3|resolves, but nothing here runs it
badmap|x|unrunnable|1|is not executable
iex|x|catalogue-line|0|ran:iex args=-S mix x
test|sub|devbin-sub-handler|0|ran:test.d/sub args=
ROWS
  )"
  all="$(grep -c . <<<"$table")" || fail "the table holds no row"
  while IFS='|' read -r cmd word want code expect; do
    [ -n "$cmd" ] || continue
    rows=$((rows + 1))
    if got="$(fixture_ask "$proj" option_leaf "$cmd" "$word")"; then
      [ "$got" = "$want" ] || bad="$bad [$cmd $word: named $got, want $want]"
    else
      bad="$bad [$cmd $word: option_leaf exited $?]"
    fi
    PATH="$proj/fakebin:$PATH" run devbin_run "$proj" "$cmd" "$word"
    [ "$status" = "$code" ] || bad="$bad [$cmd $word: exit $status, want $code]"
    case "$output" in
      *"$expect"*) ;;
      *) bad="$bad [$cmd $word: output lacks '$expect']" ;;
    esac
  done <<<"$table"
  [ "$rows" -eq "$all" ] || fail "the loop read $rows of the table's $all rows -- it measured a different population"
  [ -z "$bad" ] || fail "option_leaf and the dispatcher disagree:$bad"
}

@test "a declared option reaches the same runner named directly and inside all (0128)" {
  # run_all calls run_option for each option and never asks arg_route, while a
  # word named directly is routed. The two must meet at one runner, or `all`
  # runs something other than what a person runs by name. The funnel above
  # holds option_leaf to the direct run; this holds the direct run to the sweep.
  proj="$(_order_proj)"
  local pair cmd opt direct line bad="" n=0
  local -a pairs=(hand:decl line:own line:bare seal:bare grp:one)
  for pair in "${pairs[@]}"; do
    cmd="${pair%%:*}" opt="${pair#*:}"
    run devbin_run "$proj" "$cmd" "$opt"
    [ "$status" -eq 0 ] || {
      bad="$bad [$cmd $opt: exit $status named directly]"
      continue
    }
    direct="$(grep -E '^(ran:|line:|==> )' <<<"$output" || true)"
    [ -n "$direct" ] || {
      bad="$bad [$cmd $opt: no runner line named directly]"
      continue
    }
    run devbin_run "$proj" "$cmd" all
    while IFS= read -r line; do
      n=$((n + 1))
      grep -qxF -- "$line" <<<"$output" || bad="$bad [$cmd $opt: '$line' named directly, absent inside all]"
    done <<<"$direct"
  done
  [ "$n" -ge "${#pairs[@]}" ] || fail "only $n runner lines were compared -- fewer than the ${#pairs[@]} options this arm names"
  [ -z "$bad" ] || fail "a declared option ran differently named directly and inside all:$bad"
}

@test "clean all under a command-level run: runs no arm of devbin's, and with no options declared is refused (0128)" {
  # The live site 0128 names: a project whose `commands.clean.run` decides what
  # is removed had `clean all` sweep devbin's own rust arm instead, because the
  # built-in options were displaced by a handler and never by a `run:`. With
  # the arms displaced and none declared, `all` has nothing to sweep, and a
  # `run:` line is refused it (0128's option (b)): the line decides what goes.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  clean:
    run: scripts/myclean
YAML
  )"
  mkdir -p "$proj/scripts" "$proj/target/debug"
  printf '[package]\nname = "demo"\n' >"$proj/Cargo.toml"
  printf '#!/bin/sh\necho "ran:myclean args=$*"\n' >"$proj/scripts/myclean"
  chmod +x "$proj/scripts/myclean"

  run devbin_run "$proj" clean all --dry-run
  assert_exit_code 1
  assert_output_contains "'bin/devbin clean all' has no options to run: commands.clean.run in bin/.devbin/config.yaml owns clean here, and 'bin/devbin clean' runs it"
  assert_output_contains "0 of 0 clean options ran"
  refute_output_contains "ran:myclean"
  refute_output_contains "$proj/target"

  # A built-in option's own name is an ordinary word here: displaced, so
  # neither inactive nor devbin's.
  run devbin_run "$proj" clean rust --dry-run
  assert_success
  assert_output_contains "ran:myclean args=rust --dry-run"

  # And help says the same thing: the command is the project's, with no option
  # of devbin's listed under it, and the page to write is the project's own.
  run devbin_run "$proj" help clean
  assert_success
  assert_output_contains "Resolves from: config commands.clean.run"
  refute_output_contains "Options:"
  assert_output_contains "Write it at bin/.devbin/help/clean.md"

  # THE CONTROLS, one per absence above, so neither holds by a spelling. Help's
  # answer for the project's clean lists an option the project declares under
  # "Options:", and devbin's rust arm still not; and with clean devbin's own,
  # `clean all` sweeps the rust arm, which names the tree.
  write_config "$proj" <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  clean:
    run: scripts/myclean
    options:
      mine:
        summary: the project's own
        run: scripts/myclean
YAML
  run devbin_run "$proj" help clean
  assert_success
  assert_output_contains "Options:"
  assert_output_contains "the project's own"
  refute_output_contains "Remove cargo target/ trees"
  write_config "$proj" <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  run devbin_run "$proj" clean all --dry-run
  assert_output_contains "$proj/target"
  refute_output_contains "ran:myclean"
}

@test "a built-in option is not active under a command the project owns, whichever way it owns it (0128)" {
  # option_active's own answer, pinned: every current caller also meets the
  # displacement in builtin_options or option_unavailable_reason, so only a
  # direct question can see this line, and the next direct caller will ask it.
  # The ways to own a command, one predicate for all of them
  # (project_owns_command): a command-level run:, a handler in cmd/, and a
  # mapped handler.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  )"
  # The control first: with the command devbin's own, the option IS active.
  run fixture_ask "$proj" option_active clean rust
  assert_success

  local way bad=""
  for way in run handler mapped; do
    rm -f "$proj/bin/.devbin/cmd/clean" "$proj/bin/.devbin/cmd/myclean"
    case "$way" in
      run)
        printf 'project:\n  name: demo\n  languages:\n    - rust\ncommands:\n  clean:\n    run: scripts/myclean\n' | write_config "$proj"
        ;;
      handler)
        printf 'project:\n  name: demo\n  languages:\n    - rust\n' | write_config "$proj"
        create_test_command "$proj" clean >/dev/null
        ;;
      mapped)
        printf 'project:\n  name: demo\n  languages:\n    - rust\ncommands:\n  clean:\n    handler: myclean\n' | write_config "$proj"
        create_test_command "$proj" myclean >/dev/null
        ;;
    esac
    # 1 is option_active's "not active" but not its alone; the control above,
    # asked through the same helper of the same project, is what says the 1
    # here is the function's answer (fixture_run's own failures exit 8 and 9).
    run fixture_ask "$proj" option_active clean rust
    [ "$status" -eq 1 ] || bad="$bad [$way: exit $status, want 1]"
  done
  [ -z "$bad" ] || fail "a built-in option stayed active under a command the project owns:$bad"
}

@test "a declared option with no run: of its own goes to the command's run: line, directly and inside all (0128)" {
  # Declaring an option -- here only for its summary -- must not move what runs
  # it. Under a command the project owns by its `run:`, run_option handed a
  # declared built-in name to devbin's own gate.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  clean:
    run: scripts/myclean
    options:
      rust:
        summary: the project's rust clean
YAML
  )"
  mkdir -p "$proj/scripts"
  printf '#!/bin/sh\necho "ran:myclean args=$*"\n' >"$proj/scripts/myclean"
  chmod +x "$proj/scripts/myclean"

  run devbin_run "$proj" clean rust --dry-run
  assert_success
  assert_output_contains "ran:myclean args=rust --dry-run"

  run devbin_run "$proj" clean all
  assert_success
  assert_output_contains "ran:myclean args=rust"
  assert_output_contains "1 of 1 clean options ran"

  # --why names the same runner for the option as for the command: the line
  # under the command's row and the line under its rust option's row, read inside
  # clean's own block, since other commands list a rust option too. And no row
  # but these names that runner.
  run devbin_run "$proj" help --why
  assert_success
  local row block
  local -a rows=('  clean' '    rust')
  block="$(awk '/^  clean( |$)/ { on = 1; print; next } on && /^  [^ ]/ { on = 0 } on { print }' <<<"$output")"
  [ -n "$block" ] || fail "--why lists no clean row:\n$output"
  for row in "${rows[@]}"; do
    grep -q 'from: config commands.clean.run' <<<"$(grep -A1 -E "^${row}( |\$)" <<<"$block")" ||
      fail "expected the row '${row##* }' from config commands.clean.run:\n$output"
  done
  [ "$(grep -c 'from: config commands.clean.run' <<<"$output")" -eq "${#rows[@]}" ] ||
    fail "config commands.clean.run is named for a row other than clean and its rust option:\n$output"
}

@test "a refusal names the config file relative to the project root, not by its absolute path (0128)" {
  # Five of the sentences that name the file: an option switched off, a
  # language not declared, a command whose options are some switched off and
  # the rest without a language, a command whose every option is switched off,
  # and a command switched off itself. `own` keeps `test` alive for the first
  # two, so the OPTION-level refusal is the one that answers.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      shell:
        enabled: false
      own:
        run: printf own
YAML
  )"
  run devbin_run "$proj" test shell
  assert_exit_code 2
  assert_output_contains "it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "$proj/bin/.devbin/config.yaml"

  run devbin_run "$proj" test mix
  assert_exit_code 2
  assert_output_contains "in project.languages (bin/.devbin/config.yaml)"
  refute_output_contains "$proj/bin/.devbin/config.yaml"

  write_config "$proj" <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      shell:
        enabled: false
YAML
  run devbin_run "$proj" test
  assert_exit_code 2
  assert_output_contains "shell switched off (enabled: false in bin/.devbin/config.yaml), and the rest need a language"
  refute_output_contains "$proj/bin/.devbin/config.yaml"

  # Every option switched off: docs ships one, for any language.
  write_config "$proj" <<'YAML'
project:
  name: demo
commands:
  docs:
    options:
      agents:
        enabled: false
YAML
  run devbin_run "$proj" docs
  assert_exit_code 2
  assert_output_contains "every option it offers is switched off (enabled: false in bin/.devbin/config.yaml): agents"
  refute_output_contains "$proj/bin/.devbin/config.yaml"

  # The command itself switched off.
  write_config "$proj" <<'YAML'
project:
  name: demo
commands:
  docs:
    enabled: false
YAML
  run devbin_run "$proj" docs
  assert_exit_code 2
  assert_output_contains "'bin/devbin docs' is not available here: it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "$proj/bin/.devbin/config.yaml"

  # A command whose every option needs a language the project does not declare.
  write_config "$proj" <<'YAML'
project:
  name: demo
YAML
  run devbin_run "$proj" test
  assert_exit_code 2
  assert_output_contains "(declare project.languages in bin/.devbin/config.yaml, or commands.test.run)"
  refute_output_contains "$proj/bin/.devbin"

  # And help with no command active at all: every built-in switched off, the
  # list taken from the catalogue so none is missed.
  local c
  {
    printf 'project:\n  name: demo\ncommands:\n'
    for c in $(fixture_run "$proj" 'builtin_commands'); do
      printf '  %s:\n    enabled: false\n' "$c"
    done
  } | write_config "$proj"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "No commands are active in this project."
  assert_output_contains "Declare one in bin/.devbin/config.yaml, or drop a handler into bin/.devbin/cmd/."
  refute_output_contains "$proj/bin/.devbin"
}

@test "fmt_arm_state names each fmt arm by who runs it: a switch config set is disabled, a run of the project's is overridden (0128)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  )"
  local want got bad="" shape
  # One answer per shape. fmt_arm_state maps every word option_leaf can give by
  # name, so an arm read wrongly here would be a check format passes or refuses
  # on a false reason.
  _state_of() { fixture_ask "$proj" fmt_arm_state "$1"; }
  got="$(_state_of rust)" || fail "fmt_arm_state rust exited $?"
  [ "$got" = builtin ] || bad="$bad [devbin's catalogue arm: $got, want builtin]"

  # With devbin's own fmt handler missing, nothing of the project's runs fmt
  # either, so the gate still derives the check from the catalogue: the arm is
  # not the project's to be called overridden (a first draft of 0128 had check
  # format saying the project ran its own formatter here).
  mv "$proj/bin/.devbin/lib/cmd/fmt" "$proj/fmt.away"
  got="$(_state_of rust)" || fail "fmt_arm_state rust exited $? with devbin's fmt handler missing"
  [ "$got" = builtin ] || bad="$bad [devbin's fmt handler missing: $got, want builtin]"
  mv "$proj/fmt.away" "$proj/bin/.devbin/lib/cmd/fmt"

  write_config "$proj" <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  fmt:
    options:
      rust:
        enabled: false
      lua:
        summary: an arm the catalogue has no row for
YAML
  got="$(_state_of rust)" || fail "fmt_arm_state rust exited $?"
  [ "$got" = disabled ] || bad="$bad [switched off: $got, want disabled]"
  got="$(_state_of lua)" || fail "fmt_arm_state lua exited $?"
  [ "$got" = builtin ] || bad="$bad [declared with nothing to run it: $got, want builtin]"

  for shape in option-run command-run handler; do
    case "$shape" in
      option-run) printf 'project:\n  name: demo\n  languages:\n    - rust\ncommands:\n  fmt:\n    options:\n      rust:\n        run: scripts/myfmt\n' | write_config "$proj" ;;
      command-run) printf 'project:\n  name: demo\n  languages:\n    - rust\ncommands:\n  fmt:\n    run: scripts/myfmt\n' | write_config "$proj" ;;
      handler)
        printf 'project:\n  name: demo\n  languages:\n    - rust\n' | write_config "$proj"
        create_test_command "$proj" fmt >/dev/null
        ;;
    esac
    got="$(_state_of rust)" || fail "fmt_arm_state rust exited $? for $shape"
    [ "$got" = overridden ] || bad="$bad [$shape: $got, want overridden]"
  done
  [ -z "$bad" ] || fail "fmt arms named wrongly:$bad"
}

@test "a switched-off option is named switched off, whoever owns the command (0128)" {
  # Under a command the project owned, the refusal said only "is not active in
  # this project", since ownership returned before the switch was read.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  clean:
    run: scripts/myclean
    options:
      rust:
        enabled: false
YAML
  )"
  run devbin_run "$proj" clean rust
  assert_exit_code 2
  assert_output_contains "it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "is not active in this project"
}

@test "a declared option named directly replaces the dispatcher as a launcher must, and inside all it returns (0128)" {
  # The line prints its words and its parent's command line. Named directly it
  # is exec'd, so its parent is whatever ran bin/devbin; inside all it runs
  # beneath the dispatcher, so bin/devbin is its parent -- the loop has to go on.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  clean:
    run: scripts/line
    options:
      rust:
        summary: declared, with no run of its own
YAML
  )"
  mkdir -p "$proj/scripts"
  printf '#!/bin/sh\nprintf "args=%%s\\n" "$*"\nprintf "parent=%%s\\n" "$(ps -o args= -p "$PPID")"\n' >"$proj/scripts/line"
  chmod +x "$proj/scripts/line"
  run devbin_run "$proj" clean rust
  assert_success
  assert_output_contains "parent="
  # The dispatcher as parent reads `.../bin/devbin clean ...`; a bare
  # "bin/devbin" also matched a CI checkout at .../devbin/devbin/tests/...,
  # the bats runner's own path, and went red on every Ubuntu run.
  refute_output_contains "bin/devbin clean"

  run devbin_run "$proj" clean all
  assert_success
  assert_output_contains "parent="
  assert_output_contains "bin/devbin clean"

  # A WRAPPER FLAG FOLLOWS THE SAME SPLIT (issue 0122). Named directly, the
  # line may read --purge as its own, so it is passed on; inside all it was
  # typed for the sealed options beside this one, so this unsealed line does
  # not get it. Either way devbin says which.
  run devbin_run "$proj" clean rust --purge
  assert_success
  grep -qx 'args=rust --purge' <<<"$output" || fail "named directly, the line was not handed --purge:
$output"
  assert_output_contains "--purge -- it was passed to the tool as the tool's own"

  run devbin_run "$proj" clean all --purge
  assert_success
  grep -qx 'args=rust' <<<"$output" || fail "inside all, the line was not handed exactly its option:
$output"
  assert_output_contains "so --purge had no seal to act on, and inside all it was not passed to it"
}

@test "inside all, an option whose command's log: cannot be resolved is refused and the loop goes on (0128)" {
  # run_option's run tier RETURNS on a log: it cannot resolve, where
  # run_command dies, because inside `all` an exit would abandon every option
  # after this one. gate_log_suffix cannot fail on any value config holds
  # today, so the fixture's copy is made to fail, as stub_command_options
  # stands in for a defect above.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  clean:
    run: scripts/line
    log: true
    options:
      first:
        summary: declared, with no run of its own
      second:
        summary: declared, with no run of its own
YAML
  )"
  mkdir -p "$proj/scripts"
  printf '#!/bin/sh\necho "line:line args=$*"\n' >"$proj/scripts/line"
  chmod +x "$proj/scripts/line"
  printf '\ngate_log_suffix() { return 1; }\n' >>"$proj/bin/.devbin/lib/runlog"

  run devbin_run "$proj" clean all
  assert_exit_code 1
  assert_output_contains "cannot resolve commands.clean.log -- not running 'clean first' unsealed"
  assert_output_contains "cannot resolve commands.clean.log -- not running 'clean second' unsealed"
  refute_output_contains "line:line"
  assert_output_contains "2 of 2 clean options ran"
}

# ============================================================================
# GATE WRAPPER FLAGS (`test all --purge`, corpus semantics)
# ============================================================================
#
# Built-in gates put user args after `--`, so a run_gate wrapper flag typed at
# the command line arrived as a TOOL argument -- mix was asked to run a file
# called --purge. gate_split_args partitions the argv at every gate call
# site, so the wrapper flags -- --purge, --purge-only, and --allow-empty
# (added at the same time) -- reach run_gate and everything else reaches the
# tool, on the config-declared option, the catalogue and (since issue 0087)
# the command-level path.

@test "a declared gate's --purge purges prior pairs and never reaches the tool" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    options:
      go:
        run: ./tool
        grammar: generic
        log: GO
YAML
  )"
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$proj/tool"
  chmod +x "$proj/tool"
  mkdir -p "$proj/tmp/qa"
  touch "$proj/tmp/qa/20200101-0000.GO.out" "$proj/tmp/qa/20200101-0000.GO.errors"

  # RUNLOG_KEEP_RUNS IS PINNED, NOT INHERITED -- the same reason runlog.bats
  # pins it. This test's subject is that --purge reaches run_gate instead of the
  # TOOL; the retention window is incidental to it, so tracking the default
  # would couple an argv-partitioning test to a policy value it says nothing
  # about. It went red when retention landed, for exactly that reason:
  # the sweep that pinned runlog.bats did not reach this file.
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa go --purge
  assert_success
  refute_output_contains "tool args: --purge"
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.out" ]
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.errors" ]
  # This run's pair was kept -- purge deletes "everything but this run".
  run bash -c "ls '$proj/tmp/qa/' | grep -c '\.GO\.out$'"
  assert_output "1"
}

@test "all --purge fans the flag out to every gate, each keeping its own pair" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    options:
      one:
        run: ./tool
        grammar: generic
        log: ONE
      two:
        run: ./tool
        grammar: generic
        log: TWO
YAML
  )"
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$proj/tool"
  chmod +x "$proj/tool"
  mkdir -p "$proj/tmp/qa"
  touch "$proj/tmp/qa/20200101-0000.ONE.out" "$proj/tmp/qa/20200101-0000.ONE.errors"
  touch "$proj/tmp/qa/20200101-0000.TWO.out" "$proj/tmp/qa/20200101-0000.TWO.errors"

  # RUNLOG_KEEP_RUNS IS PINNED, NOT INHERITED -- the same reason runlog.bats
  # pins it. This test's subject is that --purge reaches run_gate instead of the
  # TOOL; the retention window is incidental to it, so tracking the default
  # would couple an argv-partitioning test to a policy value it says nothing
  # about. It went red when retention landed, for exactly that reason:
  # the sweep that pinned runlog.bats did not reach this file.
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa all --purge
  assert_success
  refute_output_contains "tool args: --purge"
  [ ! -e "$proj/tmp/qa/20200101-0000.ONE.out" ]
  [ ! -e "$proj/tmp/qa/20200101-0000.TWO.out" ]
  # One stamped pair per suffix survives (anchored so LATEST_* pointers,
  # which end in .out too, are not counted as kept runs).
  run bash -c "ls '$proj/tmp/qa/' | grep -c '\.ONE\.out$'"
  assert_output "1"
  run bash -c "ls '$proj/tmp/qa/' | grep -c '\.TWO\.out$'"
  assert_output "1"
}

@test "a CATALOGUE gate's --purge takes the same path as a declared one" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  mkdir -p "$proj/tests" "$proj/tmp/test"
  printf '@test "trivially green" { true; }\n' >"$proj/tests/smoke.bats"
  touch "$proj/tmp/test/20200101-0000.SHELL.out" "$proj/tmp/test/20200101-0000.SHELL.errors"

  # RUNLOG_KEEP_RUNS IS PINNED, NOT INHERITED -- the same reason runlog.bats
  # pins it. This test's subject is that --purge reaches run_gate instead of the
  # TOOL; the retention window is incidental to it, so tracking the default
  # would couple an argv-partitioning test to a policy value it says nothing
  # about. It went red when retention landed, for exactly that reason:
  # the sweep that pinned runlog.bats did not reach this file.
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" test shell --purge
  assert_success
  [ ! -e "$proj/tmp/test/20200101-0000.SHELL.out" ]
  run bash -c "ls '$proj/tmp/test/' | grep -c '\.SHELL\.out$'"
  assert_output "1"
}

@test "--purge-only purges without running the tool at all" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    options:
      go:
        run: ./tool
        grammar: generic
        log: GO
YAML
  )"
  printf '#!/bin/sh\ntouch ran.marker\necho ran\n' >"$proj/tool"
  chmod +x "$proj/tool"
  mkdir -p "$proj/tmp/qa"
  # Explicit -t stamps: the purge-only anchor is newest-by-mtime (bash [ -nt ]),
  # and bash 3.2's -nt compares whole seconds -- two bare touches land in the
  # same second there, the tie falls to glob order, and the OLDER pair anchors.
  # Green under brew bash's nanosecond -nt, red on the 3.2 target: the seeds
  # must make the mtimes say what the filenames say.
  touch -t 202001010000 "$proj/tmp/qa/20200101-0000.GO.out" "$proj/tmp/qa/20200101-0000.GO.errors"
  touch -t 202001020000 "$proj/tmp/qa/20200102-0000.GO.out" "$proj/tmp/qa/20200102-0000.GO.errors"

  # RUNLOG_KEEP_RUNS IS PINNED, NOT INHERITED -- the same reason runlog.bats
  # pins it. This test's subject is that --purge reaches run_gate instead of the
  # TOOL; the retention window is incidental to it, so tracking the default
  # would couple an argv-partitioning test to a policy value it says nothing
  # about. It went red when retention landed, for exactly that reason:
  # the sweep that pinned runlog.bats did not reach this file.
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa go --purge-only
  assert_success
  [ ! -e "$proj/ran.marker" ]
  # The newest existing pair is the keep anchor; the older pair purges.
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.out" ]
  [ -e "$proj/tmp/qa/20200102-0000.GO.out" ]
}

@test "--allow-empty reaches run_gate from a gate's argv, and the default stays red" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    options:
      go:
        run: ./tool
        grammar: shell
        log: GO
YAML
  )"
  cat >"$proj/tool" <<'SH'
#!/bin/sh
echo "tool args: $*"
printf '1..0\n'
SH
  chmod +x "$proj/tool"

  # Without the flag, the zero-count promotion fires -- plumbing the override
  # must not weaken the default (the promotion stays).
  run devbin_run "$proj" qa go
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"

  # With it, the emptiness is declared intended -- and the flag is split to
  # run_gate, never handed to the tool as an unknown argument.
  run devbin_run "$proj" qa go --allow-empty
  assert_success
  assert_output_contains "no tests ran (--allow-empty)"
  refute_output_contains "tool args: --allow-empty"
}

# ----------------------------------------------------------------------------
# THE COMMAND-LEVEL GATE TAKES THE SAME WRAPPER FLAGS (issue 0087)
# ----------------------------------------------------------------------------
#
# The arms above cover the two sites gate_split_args was written for. A
# command-level `run:` with a `log:` is a THIRD gate site, added later (WP-14),
# and it forwarded its raw argv: `devbin sealed --purge` ran `echo hello
# --purge` and purged nothing, with no warning. So each flag is driven here at
# the command level, and the arm saying no gate forwards a raw argv holds the
# class rather than the sites.

@test "a command-level gate's --purge purges prior pairs and never reaches the tool (0087)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    run: ./tool
    grammar: generic
    log: GO
YAML
  )"
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$proj/tool"
  chmod +x "$proj/tool"
  mkdir -p "$proj/tmp/qa"
  touch "$proj/tmp/qa/20200101-0000.GO.out" "$proj/tmp/qa/20200101-0000.GO.errors"

  # Pinned for the reason the option-level arm gives.
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa --purge
  assert_success
  refute_output_contains "tool args: --purge"
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.out" ] ||
    fail "--purge reached the command-level gate and purged nothing: $output"
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.errors" ]
  run bash -c "ls '$proj/tmp/qa/' | grep -c '\.GO\.out$'"
  assert_output "1"
}

@test "a command-level gate's ordinary arguments still reach the tool, beside a wrapper flag (0087)" {
  # The split must take the flags OUT, not the arguments with them.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    run: ./tool
    grammar: generic
    log: GO
YAML
  )"
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$proj/tool"
  chmod +x "$proj/tool"
  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa one --purge two
  assert_success
  assert_output_contains "tool args: one two"
}

@test "a command-level gate's --purge-only purges without running the tool (0087)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    run: ./tool
    grammar: generic
    log: GO
YAML
  )"
  printf '#!/bin/sh\ntouch ran.marker\necho ran\n' >"$proj/tool"
  chmod +x "$proj/tool"
  mkdir -p "$proj/tmp/qa"
  # Explicit -t stamps, for the reason the option-level arm gives.
  touch -t 202001010000 "$proj/tmp/qa/20200101-0000.GO.out" "$proj/tmp/qa/20200101-0000.GO.errors"
  touch -t 202001020000 "$proj/tmp/qa/20200102-0000.GO.out" "$proj/tmp/qa/20200102-0000.GO.errors"

  export RUNLOG_KEEP_RUNS=1
  run devbin_run "$proj" qa --purge-only
  assert_success
  [ ! -e "$proj/ran.marker" ] || fail "--purge-only ran the tool at a command-level gate: $output"
  [ ! -e "$proj/tmp/qa/20200101-0000.GO.out" ]
  [ -e "$proj/tmp/qa/20200102-0000.GO.out" ]
}

@test "a command-level gate's --allow-empty reaches run_gate, and the default stays red (0087)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  qa:
    run: ./tool
    grammar: shell
    log: GO
YAML
  )"
  cat >"$proj/tool" <<'SH'
#!/bin/sh
echo "tool args: $*"
printf '1..0\n'
SH
  chmod +x "$proj/tool"

  run devbin_run "$proj" qa
  assert_failure
  assert_output_contains "PROMOTED TO FAILED"

  run devbin_run "$proj" qa --allow-empty
  assert_success
  assert_output_contains "no tests ran (--allow-empty)"
  refute_output_contains "tool args: --allow-empty"
}

# THE TWO CATALOGUE SITES, DRIVEN (0087). Every arm
# above drives a config-declared gate, so the catalogue's @builtin opener and
# its command-line opener were held by the class arm alone -- and an argv
# laundered through a local array (`local -a raw=("$@")`, then `"${raw[@]}"`)
# is outside what a lexical reader can see, so it passed every suite. These run
# the real run_builtin_gate and the real run_gate in-process, with only the
# catalogue readers stubbed: the tool reports its argv, and a prior pair
# exists for --purge to take.

# catalogue_gate <run-line> <args>... -- run_builtin_gate check probe <args>
# against a stubbed catalogue row whose run is <run-line>, in a scratch root
# holding one prior PROBE pair. Prints the gate's output, then `pair: kept` or
# `pair: purged`.
catalogue_gate() {
  local d="$DEVBIN_TEST_TMPDIR/catgate" run_line="$1"
  shift
  mkdir -p "$d/tmp/check"
  touch "$d/tmp/check/20200101-0000.PROBE.out" "$d/tmp/check/20200101-0000.PROBE.errors"
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$d/tool"
  chmod +x "$d/tool"
  RUNLOG_KEEP_RUNS=1 PROJECT_ROOT="$d" DEVBIN_NAME=devbin RUN_LINE="$run_line" bash -c '
    . "$DEVBIN_LIB/gatecmd"
    builtin_option_run() { printf "%s\n" "$RUN_LINE"; }
    builtin_option_suffix() { printf "PROBE\n"; }
    builtin_option_grammar() { printf "generic\n"; }
    builtin_check_probe() { echo "tool args: $*"; }
    run_builtin_gate check probe "$@"
  ' _ "$@" 2>&1
  if [ -e "$d/tmp/check/20200101-0000.PROBE.out" ]; then echo "pair: kept"; else echo "pair: purged"; fi
}

@test "an @builtin gate's --purge purges prior pairs, and only the ordinary argument reaches the function (0087)" {
  run catalogue_gate @builtin --purge one
  assert_output_contains "tool args: one"
  # The EXACT line: an argument appended after the right one (`"${@:2}"` adds a
  # second `one`) still contains the substring (0087).
  grep -qx 'tool args: one' <<<"$output" || fail "the tool did not get exactly one: $output"
  refute_output_contains "tool args: --purge"
  assert_output_contains "pair: purged"
}

@test "a catalogue command line's --purge purges prior pairs, and only the ordinary argument reaches the tool (0087)" {
  run catalogue_gate ./tool --purge one
  assert_output_contains "tool args: one"
  # The EXACT line: an argument appended after the right one (`"${@:2}"` adds a
  # second `one`) still contains the substring (0087).
  grep -qx 'tool args: one' <<<"$output" || fail "the tool did not get exactly one: $output"
  refute_output_contains "tool args: --purge"
  assert_output_contains "pair: purged"
}

@test "no gate forwards a raw argv: every run_gate call passes the split flags and the split args (0087)" {
  # THE CLASS. Over every run_gate call (gate_spans, the one reader the 0085
  # arm uses too), which hands over a call's flags and its argv as separate
  # fields, the argv read to the call's last line, this arm refuses an
  # argv that forwards the raw positional list in any spelling -- "$@", $*,
  # "${@}", "${@:1}" -- which is how a wrapper flag becomes a tool argument; and
  # a call that forwards DEVBIN_GATE_ARGS without DEVBIN_GATE_FLAGS, which drops
  # the flags instead. A call that forwards neither -- fullcycle's, the test
  # handler's -- takes no user argv and is not a finding.
  #
  # THE RAW FORMS AND THE CONTINUATION LINE WERE MISSED AT FIRST (0087).
  # This arm first matched only the unbraced "$@", and the reader stopped at the
  # `--` line, so ARGS kept with "${@}" appended -- on that line or the next --
  # passed here and passed every suite, while --purge reached the tool.
  local spans found="" split=0 loc flags argv
  spans="$(gate_spans)"
  while IFS=$'\t' read -r loc flags argv; do
    case "$loc" in
      UNTERMINATED) found+="$flags: a run_gate with no bare --, so its argv was never read"$'\n' ;;
      *)
        if [[ "$argv" =~ \$\{?[@*] ]]; then
          found+="$loc: raw argv"$'\n'
        elif [[ "$argv" == *DEVBIN_GATE_ARGS* && "$flags" != *DEVBIN_GATE_FLAGS* ]]; then
          found+="$loc: split args without the split flags"$'\n'
        elif [[ "$argv" == *DEVBIN_GATE_ARGS* ]]; then
          split=$((split + 1))
        fi
        ;;
    esac
  done <<<"$spans"
  # NOT VACUOUS: the scan must have read every split site it exists to hold --
  # option, builtin fn, catalogue and command -- each a run_gate whose `--` line
  # forwards DEVBIN_GATE_ARGS, counted here by a second route over the files
  # gate_spans reads. A reader that silently stopped matching run_gate would
  # otherwise report nothing and pass.
  local sites
  sites="$(grep -rhE --exclude='*.md' --exclude='*.yaml' -- '^[[:space:]]*-- .*DEVBIN_GATE_ARGS' "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin" | grep -c .)" || sites=0
  [ "$sites" -gt 0 ] && [ "$split" -eq "$sites" ] || fail "the scan read $split gate call(s) forwarding split args, where $sites forward them:
$spans"
  [ -z "$found" ] || fail "a gate forwards user argv without gate_split_args, so a wrapper flag reaches the tool:
$found"
}

@test "gate_spans reads a call to its last line, splits it at the bare -- outside quotes, and names an unterminated one" {
  # The reader's own contract, driven on a tree built for it rather than
  # inferred from the runtime's own calls: every property the class arms
  # rest on is a row here.
  local home="$DEVBIN_TEST_TMPDIR/spans"
  mkdir -p "$home/lib" "$home/bin"
  cat >"$home/lib/fake" <<'SH'
# run_gate --in-a-comment -- ignored
run_gate --source "a -- inside quotes" --x 1 \
  -- tool "a" \
  "${@}"
run_gate --source 'single -- quoted' -- one-line "$@"
run_gate --no-terminator \
  --still-flags
run_gate --after-unterminated -- ok
run_gate --source "x" -- tool --source not-a-flag
SH
  local out calls
  out="$(DEVBIN_HOME="$home" gate_spans)"
  local -a rows
  mapfile -t rows <<<"$out"
  # One row a call: every line of the fixture that opens a run_gate call.
  calls="$(grep -c '^run_gate ' "$home/lib/fake")" || fail "the fixture holds no run_gate call"
  [ "${#rows[@]}" -eq "$calls" ] || fail "want $calls rows, got ${#rows[@]}:
$out"
  local loc flags argv
  IFS=$'\t' read -r loc flags argv <<<"${rows[0]}"
  [ "$loc" = "lib/fake:2" ] || fail "row 1 loc: $loc"
  [[ "$flags" == *'"a -- inside quotes"'*'--x 1'* ]] || fail "row 1 flags stopped at the quoted --: [$flags]"
  [[ "$argv" == *'tool "a"'*'"${@}"'* ]] || fail "row 1 argv did not reach the call's last line: [$argv]"
  IFS=$'\t' read -r loc flags argv <<<"${rows[1]}"
  [[ "$flags" == *"'single -- quoted'"* && "$argv" == *'one-line "$@"'* ]] || fail "row 2 split wrong: [$flags] [$argv]"
  [ "${rows[2]}" = $'UNTERMINATED\tlib/fake:6' ] || fail "row 3 is not the unterminated call: [${rows[2]}]"
  IFS=$'\t' read -r loc flags argv <<<"${rows[3]}"
  [ "$loc" = "lib/fake:8" ] || fail "the call after an unterminated one was not read on its own: [${rows[3]}]"
  IFS=$'\t' read -r loc flags argv <<<"${rows[4]}"
  [[ "$flags" != *not-a-flag* && "$argv" == *'--source not-a-flag'* ]] ||
    fail "a tool argument spelled --source landed in the flags: [$flags] [$argv]"
}

# ----------------------------------------------------------------------------
# THE UNSEALED SITES SAY WHAT BECAME OF devbin's FLAGS (issue 0122)
# ----------------------------------------------------------------------------
#
# An option or command with a run: and no log: runs unsealed, and devbin's
# wrapper flags reached its tool as arguments with no word: `check bare --purge`
# printed `bare-ran --purge`. devbin cannot act on them without a seal. Inside
# `all` they were typed for the sealed options beside this one, so they are
# dropped there; named directly they may be the tool's own -- --allow-empty is
# git commit's -- so they pass through. Either way the person is told.

_unsealed_proj() {
  mkproj demo <<'YAML'
project:
  name: demo
commands:
  check:
    options:
      bare:
        run: ./tool
  qa:
    run: ./tool
  multi:
    options:
      bare:
        run: ./tool
YAML
}

_unsealed_tool() {
  printf '#!/bin/sh\necho "tool args: $*"\n' >"$1/tool"
  chmod +x "$1/tool"
}

@test "an unsealed option named directly hands its tool the whole argv, and says devbin did not act on the flags (0122)" {
  proj="$(_unsealed_proj)"
  _unsealed_tool "$proj"
  run bash -c "cd '$proj' && bin/devbin check bare one --purge two --allow-empty 2>'$DEVBIN_TEST_TMPDIR/err'"
  assert_success
  grep -qx 'tool args: one --purge two --allow-empty' <<<"$output" || fail "the tool did not get its whole argv, in order: $output"
  grep -q -- 'devbin did not act on --purge --allow-empty -- they were passed to the tool' "$DEVBIN_TEST_TMPDIR/err" ||
    fail "the pass-through of two flags was not said on stderr, in the plural: $(cat "$DEVBIN_TEST_TMPDIR/err")"
}

@test "an unsealed COMMAND hands its tool the whole argv too, so git commit's --allow-empty survives (0122)" {
  proj="$(_unsealed_proj)"
  _unsealed_tool "$proj"
  run bash -c "cd '$proj' && bin/devbin qa -m wip --allow-empty 2>'$DEVBIN_TEST_TMPDIR/err'"
  assert_success
  grep -qx 'tool args: -m wip --allow-empty' <<<"$output" || fail "the tool did not get its whole argv: $output"
  grep -q -- 'devbin did not act on --allow-empty -- it was passed to the tool' "$DEVBIN_TEST_TMPDIR/err" ||
    fail "the pass-through of one flag was not said on stderr, in the singular: $(cat "$DEVBIN_TEST_TMPDIR/err")"
}

@test "inside all, an unsealed option drops the flag it could not act on, and says so (0122)" {
  proj="$(_unsealed_proj)"
  _unsealed_tool "$proj"
  run bash -c "cd '$proj' && bin/devbin multi all one --purge 2>'$DEVBIN_TEST_TMPDIR/err'"
  assert_success
  grep -qx 'tool args: one' <<<"$output" || fail "inside all the tool should get the argv without the flag: $output"
  grep -q -- '--purge had no seal to act on, and inside all it was not passed to it' "$DEVBIN_TEST_TMPDIR/err" ||
    fail "the drop was not said on stderr: $(cat "$DEVBIN_TEST_TMPDIR/err")"
  # Two flags, in the plural.
  run bash -c "cd '$proj' && bin/devbin multi all one --purge --allow-empty 2>'$DEVBIN_TEST_TMPDIR/err'"
  assert_success
  grep -qx 'tool args: one' <<<"$output" || fail "inside all the tool should get the argv without either flag: $output"
  grep -q -- '--purge --allow-empty had no seal to act on, and inside all they were not passed to it' "$DEVBIN_TEST_TMPDIR/err" ||
    fail "the drop of two flags was not said on stderr, in the plural: $(cat "$DEVBIN_TEST_TMPDIR/err")"
}

@test "an unsealed run given no wrapper flag passes its arguments and says nothing -- the control (0122)" {
  proj="$(_unsealed_proj)"
  _unsealed_tool "$proj"
  run bash -c "cd '$proj' && bin/devbin check bare one two 2>'$DEVBIN_TEST_TMPDIR/err'"
  assert_success
  grep -qx 'tool args: one two' <<<"$output" || fail "the tool did not get 'one two': $output"
  [ ! -s "$DEVBIN_TEST_TMPDIR/err" ] || fail "a run with no wrapper flag wrote to stderr: $(cat "$DEVBIN_TEST_TMPDIR/err")"
}

@test "every function in lib/resolve that hands a tool the raw argv also says what became of devbin's flags (0122)" {
  # THE CLASS at the sites the run_gate arm above cannot see, because they call
  # no run_gate: a word list from run_words run with the raw positional list,
  # in a function that never calls gate_flags_unsealed, lets a wrapper flag
  # pass in silence. It holds the `words` spelling, which is what run_words
  # fills at every site in lib/resolve; a list under another name would pass.
  local report n untold
  report="$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn) }
    /"\$\{words\[@\]\}" +"\$@"/ { raw[fn]++; n++ }
    /gate_flags_unsealed / { told[fn] = 1 }
    END { printf "raw %d\n", n; for (f in raw) if (!(f in told)) printf "untold %s\n", f }
  ' "$DEVBIN_LIB_DIR/resolve")"
  n="$(awk '$1 == "raw" { print $2 }' <<<"$report")"
  # NOT VACUOUS: the scan's pattern finds every line that runs an array with the
  # positional list -- the array under any name, the list in any spelling --
  # counted here by a second route, and there is one to find: the option and
  # command sites are among them.
  local all
  all="$(grep -cE -- '"[$][{][A-Za-z_][A-Za-z0-9_]*[[]@[]][}]"[[:space:]]+("[$]@"|"[$][{]@[^}]*[}]"|[$]@|"?[$][*]"?)' "$DEVBIN_LIB_DIR/resolve")" || all=0
  [ "${n:-0}" -gt 0 ] && [ "${n:-0}" -eq "$all" ] || fail "found ${n:-0} raw word-list runs in lib/resolve, where $all lines run a word list with the positional list:
$report"
  untold="$(awk '$1 == "untold" { print $2 }' <<<"$report")"
  [ -z "$untold" ] || fail "a function hands its tool the raw argv without saying what became of devbin's flags: $untold"
}

# ============================================================================
# THE `devbin` COMMAND (the framework's own help surface)
# ============================================================================
#
# install/upgrade/doctor/new already sit in every project's Devbin group; this
# is the missing row -- help about DEVBIN ITSELF (the seam, the templates, the
# reference config, where upgrades come from), as opposed to `help`, which is
# about this project's command surface.

@test "devbin: the framework's own help names the seam, identity and reference" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" devbin
  assert_success
  assert_output_contains "replaced wholesale"
  assert_output_contains "answers as 'demo'"
  assert_output_contains "config.reference.yaml"
}

# _overview_paths_exist <root> -- every lib path `devbin devbin` and
# `devbin devbin templates` name must exist under <root>. Collects the output of
# both, pulls each path ending in config.reference.yaml or tmpl/, and fails
# naming any that is absent. Each kind of path is asserted found as well: an
# extractor that finds nothing, or loses half its pattern, would pass every tree.
_overview_paths_exist() {
  local root="$1" out p ref=0 tmpl=0
  out="$(cd "$root" && bin/devbin devbin 2>&1; cd "$root" && bin/devbin devbin templates 2>&1)"
  for p in $(printf '%s\n' "$out" | grep -oE '[A-Za-z0-9_./-]*(config\.reference\.yaml|/tmpl/)'); do
    case "$p" in
      *config.reference.yaml) ref=1 ;;
      */tmpl/*) tmpl=1 ;;
    esac
    [ -e "$root/$p" ] || fail "devbin devbin names $p, which does not exist under $root"
  done
  [ "$ref" = 1 ] || fail "found no config.reference.yaml path in the overview -- the extractor would compare nothing of it"
  [ "$tmpl" = 1 ] || fail "found no tmpl/ path in the overview -- the extractor would compare nothing of it"
}

@test "devbin: every lib path the overview names EXISTS, in an install (0112)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  _overview_paths_exist "$proj"
}

@test "devbin: every lib path the overview names EXISTS, in the devbin checkout too (0112)" {
  # Found while writing the authored page for `devbin` (issue 0112): in this
  # checkout the overview pointed at bin/.devbin/lib/config.reference.yaml and
  # bin/.devbin/lib/tmpl/, which do not exist here -- the devbin source
  # checkout runs lib/ in place --
  # while the same output said "This IS the devbin checkout". It knew, and
  # printed the vendored paths anyway.
  _overview_paths_exist "$DEVBIN_HOME"
}

@test "devbin: the overview's seam line says which tree it is -- the source here, vendored in a project (0117)" {
  # An earlier fix gave the checkout its own wording, and the arm above
  # checks only
  # that the paths exist, so the checkout printing the install's wording passed
  # it (issue 0117). Both trees, both directions.
  run bash -c "cd '$DEVBIN_HOME' && bin/devbin devbin"
  assert_success
  assert_output_contains "devbin's source -- this tree; nothing vendored"
  refute_output_contains "replaced wholesale by upgrade"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" devbin
  assert_success
  assert_output_contains "replaced wholesale by upgrade"
  refute_output_contains "nothing vendored"
}

@test "devbin: a project whose recorded source this machine cannot place is still vendored, and the overview says why (0153)" {
  # The overview decided vendored-versus-checkout on whether the recorded source
  # resolved. A manifest records a kind now and the machine says where it is, so
  # a project vendored from a checkout, on a machine whose switch names none,
  # was told it was the devbin checkout.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  [ "$(sed -n 's/^# source: //p' "$proj/bin/.devbin/manifest.sha256")" = checkout ] ||
    fail "the fixture is not a project vendored from a checkout"
  run devbin_run "$proj" devbin
  assert_success
  assert_output_contains "replaced wholesale by upgrade"
  refute_output_contains "This IS the devbin checkout"
  assert_output_contains "Upgrades come from: nowhere this machine can place -- this machine names no devbin install"
  switch_to "$DEVBIN_HOME"
  run devbin_run "$proj" devbin
  assert_success
  assert_output_contains "Upgrades come from: $(cd -P "$DEVBIN_HOME" && pwd -P)"
}

@test "devbin: in the devbin checkout the overview names the checkout's own docs/, and every guide it lists is there (0254)" {
  run bash -c "cd '$DEVBIN_HOME' && bin/devbin devbin"
  assert_success
  assert_output_contains "This IS the devbin checkout"
  assert_guides_at "$(cd -P "$DEVBIN_HOME" && pwd -P)/docs"
}

@test "devbin: a project whose source this machine cannot place says why its guides are not placed, and once the switch names the checkout, names the checkout's docs/ (0254)" {
  # The guides of a project are those of the install its upgrades read, so
  # where that is not placed, neither are they, and the line says why with the
  # source's own clause rather than naming a docs/ under the project.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" devbin
  assert_success
  assert_output_contains "are not here: this machine names no devbin install"
  refute_output_contains "source checkout"
  switch_to "$DEVBIN_HOME"
  run devbin_run "$proj" devbin
  assert_success
  assert_guides_at "$(cd -P "$DEVBIN_HOME" && pwd -P)/docs"
}

@test "devbin --version answers with DEVBIN's version, not the project's" {
  # Reported from a consumer project: `<project> devbin --version` printed a usage
  # line and exited 1. The datum was already there -- `runtime_version` reads it
  # out of the manifest and the bare overview prints it -- but --version fell
  # through to the catch-all. Asking a framework its version is not a usage
  # error.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  printf 'defmodule Demo do\n  version: "9.9.9"\nend\n' >"$proj/mix.exs"
  run devbin_run "$proj" devbin --version
  assert_success
  assert_output_contains "devbin"
  # 9.9.9 is the PROJECT's version. It must not be able to appear here.
  refute_output_contains "9.9.9"
}

@test "devbin --version and -v and version all answer, none is a usage error" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  for form in --version -v version; do
    run devbin_run "$proj" devbin "$form"
    assert_success
  done
}

@test "a manifest that names no devbin_version is REFUSED, never answered from the project" {
  # The severe half of the same report, and the one nothing would have caught.
  # `runtime_version` fell back to `read_version`, which reads the PROJECT's
  # version file -- so an install whose manifest lost its version stamp would
  # print the CONSUMER's version wearing devbin's label. A confident false
  # statement beats an error every time it is not tested for.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  printf 'defmodule Demo do\n  version: "9.9.9"\nend\n' >"$proj/mix.exs"
  # A manifest that exists but carries no `# devbin_version:` line.
  grep -v '^# devbin_version:' "$proj/bin/.devbin/manifest.sha256" >"$proj/mf.tmp"
  mv "$proj/mf.tmp" "$proj/bin/.devbin/manifest.sha256"
  run devbin_run "$proj" devbin --version
  assert_failure
  refute_output_contains "9.9.9"
  assert_output_contains "manifest"
}

@test "devbin templates lists what new scaffolds from" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" devbin templates
  assert_success
  assert_output_contains "handler"
  assert_output_contains "help.md"
  assert_output_contains "test.bats"
}

@test "devbin refuses an unknown sub-topic with its usage" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run ! devbin_run "$proj" devbin nope
  assert_failure
  assert_output_contains "usage:"
}

# ===========================================================================
# THE REMEDIATION MUST RESOLVE FROM WHERE THE READER IS STANDING (ST0005)
# ===========================================================================
#
# `bin/devbin` is a RELATIVE path, and the operator drives devbin through `dvb`
# -- a shell function that walks UP from $PWD to find bin/devbin and runs it
# WITHOUT changing directory. Its whole purpose is being used from a
# subdirectory, and from there every `run: bin/devbin ...` devbin printed named
# a path that does not exist.
#
# This is the defect already recorded in updatenotice.bats -- "the
# remediation names a command that EXISTS" -- in the one direction that fix did
# not cover: it exists at the project root, and not where the reader is.

# AT-1.11
@test "at the project root the invocation stays the short bin/devbin" {
  proj="$(create_test_project)"
  install_devbin "$proj"
  run devbin_run "$proj" nosuchcommand
  assert_failure
  assert_output_contains "bin/devbin help"
  refute_output_contains "$proj/bin/devbin help"
}

# AT-1.11
@test "from a SUBDIRECTORY the invocation becomes a path that resolves" {
  proj="$(create_test_project)"
  install_devbin "$proj"
  mkdir -p "$proj/deep/nested"
  run bash -c 'cd "$1/deep/nested" && "$1/bin/devbin" nosuchcommand' _ "$proj"
  assert_failure
  assert_output_contains "$proj/bin/devbin help"
}

# AT-1.11
@test "and the command that remediation names is really there and executable" {
  # The assertion that makes the arm above mean something: a longer string is
  # not the point, a WORKING one is. Without this, printing any absolute-looking
  # path would satisfy it.
  proj="$(create_test_project)"
  install_devbin "$proj"
  mkdir -p "$proj/deep/nested"
  run bash -c 'cd "$1/deep/nested" && "$1/bin/devbin" nosuchcommand 2>&1 | sed -n "s/.*(try: \\(.*\\) help)/\\1/p"' _ "$proj"
  named="$output"
  [ -n "$named" ]
  [ -x "$named" ]
  run bash -c 'cd "$1/deep/nested" && "$2" --version' _ "$proj" "$named"
  assert_success
}

@test "test with its only declared-language option switched off names that, not project.languages (0136)" {
  # rust declared and test.rust switched off: the refusal said "declare
  # project.languages", though the language was declared.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        enabled: false
YAML
  )"
  run devbin_run "$proj" test
  assert_exit_code 2
  assert_output_contains "rust switched off"
  refute_output_contains "(declare project.languages"
}

@test "a command whose own language is undeclared says so first, even with one of its options switched off (0136)" {
  # The switched-off reason is asked only where the command's language is
  # spoken: db in a project without elixir is off for that reason before any
  # other, and naming the switched-off option would send the reader to the
  # wrong key.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  db:
    options:
      reset:
        enabled: false
YAML
  )"
  run devbin_run "$proj" db
  assert_exit_code 2
  assert_output_contains "does not declare the 'elixir' language"
  refute_output_contains "switched off"
}

@test "all over a command-level run: with no words says so, and never points at a bare command that cannot run it (0160)" {
  local line
  for line in '""' '"   "'; do
    proj="$(mkproj probe <<YAML
project:
  name: probe
commands:
  probe:
    run: $line
YAML
    )"
    run devbin_run "$proj" probe all
    assert_exit_code 1
    assert_output_contains "commands.probe.run holds no words, so there is no command to run"
    refute_output_contains "runs it"
    rm -rf "$proj"
  done
  # A line with words keeps its pointer.
  proj="$(mkproj probe <<'YAML'
project:
  name: probe
commands:
  probe:
    run: echo probed
YAML
  )"
  run devbin_run "$proj" probe all
  assert_exit_code 1
  assert_output_contains "'bin/devbin probe' runs it"
}
