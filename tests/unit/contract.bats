#!/usr/bin/env bats
# contract.bats - the reserved `all` and the exit-code contract (WP-04)
#
# The two deliverables WP-04's original AC set did not cover. They were found by
# reading the work package back against the contract: its ACs were green while
# named deliverables had no AC at all, which is an incomplete contract rather
# than finished work.
#
# AC-04.12 (recursive sub-dispatch) is discharged in data.bats, alongside its
# first real user. These are the other two.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }


two_option_project() {
  mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build things
    options:
      cli:
        summary: The CLI
        run: echo built-cli
      daemon:
        summary: The daemon
        run: echo built-daemon
YAML
}

# ============================================================================
# `all` IS RESERVED (AC-04.13)
# ============================================================================

@test "all is synthesised, and a sub-handler named all cannot shadow it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  media:
    summary: Media
    options:
      covers:
        summary: Covers
        run: echo made-covers
YAML
  )"
  create_test_command "$proj" media >/dev/null
  # A handler beside the command, named `all`, is exactly what the descent in
  # exec_handler would otherwise pick up. The command HAS a declared option,
  # so the dispatcher claims `all` for the sweep ahead of resolution and the
  # synthesised one wins -- the sub-handler can never thin a sweep out. (An
  # option-LESS full handler is the one shape that receives `all` itself; the
  # next test holds that.)
  mkdir -p "$proj/bin/.devbin/cmd/media.d"
  cat >"$proj/bin/.devbin/cmd/media.d/all" <<'EOF'
#!/usr/bin/env bash
printf 'ran:shadowed-all\n'
EOF
  chmod +x "$proj/bin/.devbin/cmd/media.d/all"

  run devbin_run "$proj" media all
  refute_output_contains "ran:shadowed-all"
}

@test "a full project handler receives all verbatim -- handler totality over option synthesis" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # The corpus is why: `which all` and `docs all` are real invocations of
  # one consumer's full handlers (WP-10), and a handler shadows TOTALLY -- its
  # argument list, `all` included, is its own. The sweep is only devbin's to
  # synthesise where devbin serves the options.
  cat > "$proj/bin/.devbin/cmd/media" <<'EOF'
#!/usr/bin/env bash
printf 'media-args:%s\n' "$*"
EOF
  chmod +x "$proj/bin/.devbin/cmd/media"

  run devbin_run "$proj" media all extra
  assert_success
  assert_output_contains "media-args:all extra"
  refute_output_contains "no options to run"
}

# THE TWO SURFACES RENDER DIFFERENT THINGS AND NOTHING ASSERTED WHICH.
# DEVBIN_INVOKE ("bin/devbin", a constant: what you TYPE) appears across
# devbin's OWN RUNTIME, under lib/ and in bin/devbin, and, until these arms, in
# ZERO test files. A commit message once counted "lib files" with bin/devbin
# among them: a correct count over a population the sentence never named, which
# is the class these very arms exist to close. A commit message is immutable,
# so this comment is where the population gets named. Several sites asserted
# `assert_output_contains "usage:"`, which passes whether the line goes on to
# say `<project>`, `bin/devbin`, or nothing at all. The hole was measured after a
# project reported the rendering change.
#
# BOTH ARMS ASSERT ON THE EXTRACTED LINE, NOT ON THE WHOLE OUTPUT, AND THAT IS
# LOAD-BEARING. The first version of these tests used assert_output_contains and
# BOTH PASSED WITH THE CODE DELIBERATELY BROKEN: the fixture's directory is
# named after the project, so every absolute path in the output contains the
# project name, and "bin/devbin" appears in any invocation path. The assertions
# were satisfied by the fixture's own filesystem layout. That is the exact
# defect these arms exist to close, reproduced inside them.
usage_line() { grep -m1 '^usage:' <<<"$output"; }

# A project whose config name differs from nothing in devbin's own vocabulary.
# two_option_project hardcodes `demo`, which collides with nothing but also
# proves nothing: the topology that matters is a project whose NAME is not the
# path you invoke, which is every project that vendors devbin.
named_option_project() {
  mkproj "$1" <<YAML
project:
  name: $1
commands:
  build:
    summary: Build things
    options:
      cli:
        summary: The CLI
        run: echo built-cli
YAML
}

@test "a usage line renders the INVOCATION, never the project name" {
  proj="$(named_option_project widget)"
  run ! devbin_run "$proj" build
  assert_exit_code 1
  line="$(usage_line)"
  [ -n "$line" ] || fail "no usage: line in output -- the arm would be vacuous"
  grep -q 'bin/devbin' <<<"$line" ||
    fail "usage line does not name the invocation: $line"
  # The failure this pins: a usage line telling a widget developer to run
  # `widget build`, a command that exists in no project.
  grep -q 'widget build' <<<"$line" &&
    fail "usage line names the PROJECT, not the invocation: $line"
  return 0
}

@test "the IDENTITY line renders the project NAME, never the invocation" {
  # The other direction, and the one that has already gone wrong once:
  # over-converting lib/cmd/devbin's identity line to DEVBIN_INVOKE made it
  # answer as "bin/devbin" instead of as the project. Without this pair, the arm
  # above is satisfied by converting EVERYTHING, which is the opposite defect.
  proj="$(named_option_project widget)"
  run devbin_run "$proj" --version
  assert_success
  # FIRST FIELD, not "contains" -- the version string and any path would both
  # satisfy a substring test.
  [ "$(printf '%s' "$output" | awk 'NR==1{print $1}')" = widget ] ||
    fail "identity is not the project name: $output"
  return 0
}

@test "a bare command that HAS options prints them rather than running everything" {
  proj="$(two_option_project)"
  run ! devbin_run "$proj" build
  assert_exit_code 1
  # Not `all`. A bare command running every option would be a destructive
  # reading of an ambiguous request.
  assert_output_contains "usage:"
  assert_output_contains "cli"
  assert_output_contains "daemon"
  refute_output_contains "built-cli"
}

@test "a bare command with options is not reported as unbuilt" {
  proj="$(two_option_project)"
  # It resolves and it has options; "not built yet" would be simply wrong, and
  # was what this printed before AC-04.13 was covered.
  #
  # It exits 1, though, not 0. Naming no option is a USAGE ERROR: the command
  # did not do what was asked, and reporting success for it is a false green
  # that `devbin test && deploy` reads as permission to deploy. One consumer's authored
  # help carried this rule from having been bitten by it, and WP-07's
  # migration audit is what surfaced it.
  run ! devbin_run "$proj" build
  assert_exit_code 1
  assert_output_contains "usage:"
  refute_output_contains "not built yet"
}

@test "asking for usage explicitly SUCCEEDS, unlike naming no option at all" {
  proj="$(two_option_project)"
  # The discriminating pair. Same output, different exit code, because they are
  # different requests: `-h` asked for the usage line and got it; bare asked to
  # run the command and could not.
  run devbin_run "$proj" build --help
  assert_success
  assert_output_contains "usage:"
}

@test "a bare SURFACE runs, because it has a command line and no options" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  serve:
    summary: A launcher
    run: echo launched
YAML
  )"
  # The other half of AC-04.13, and the half its original wording contradicted:
  # printing help here would make every launcher unusable.
  run devbin_run "$proj" serve
  assert_success
  assert_output_contains "launched"
  refute_output_contains "usage:"
}

# ============================================================================
# THE EXIT-CODE CONTRACT (AC-04.14)
# ============================================================================

@test "0 -- a command that succeeds" {
  proj="$(two_option_project)"
  run devbin_run "$proj" build cli
  assert_exit_code 0
}

@test "1 -- a command that fails carries its own exit code, not a rewritten one" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  boom:
    summary: Fails
    run: ./boom
YAML
  )"
  printf '#!/bin/sh\nexit 1\n' >"$proj/boom"
  chmod +x "$proj/boom"
  run devbin_run "$proj" boom
  assert_exit_code 1
}

@test "1 -- die reports a usage error" {
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
  build:
    summary: Build
    options:
      cli:
        run: echo built
YAML
  )"
  # Through a real command, not `help`: help is answered before shared options
  # are parsed at all, which is deliberate -- asking for help should never be
  # refused because of how the rest of the line was spelled.
  run devbin_run "$proj" build cli --env nope
  assert_exit_code 1
  assert_output_contains "expected"
}

@test "2 -- an unknown command" {
  proj="$(two_option_project)"
  run devbin_run "$proj" nosuchthing
  assert_exit_code 2
  assert_output_contains "unknown command"
}

@test "2 -- a command that exists but is not active here" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    enabled: false
YAML
  )"
  # Distinct from unknown, and deliberately the same code: from the caller's
  # side both mean "this is not a thing you can run here", and the MESSAGE is
  # what tells them apart.
  run devbin_run "$proj" build
  assert_exit_code 2
}

@test "2 -- an option that exists but is not active here" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build
    options:
      cli:
        run: echo built
      daemon:
        enabled: false
        run: echo daemon
YAML
  )"
  run devbin_run "$proj" build daemon
  assert_exit_code 2
}

@test "3 -- a built-in that resolves but is not implemented" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # Constructed rather than borrowed: remove the handler from the fixture's
  # copied lib, which is also what a partial install looks like.
  rm -f "$proj/bin/.devbin/lib/cmd/version"
  run devbin_run "$proj" version
  assert_exit_code 3
  # WHAT IS MISSING, NOT A STUB (issue 0111). This once asserted "not built
  # yet", and the message behind it said the command was "gated on" ST0001 -- a
  # thread long closed. Nothing here is unbuilt: devbin's own handler is absent
  # from this install, and the refusal has to say that and name the command that
  # finds it.
  assert_output_contains "handler for 'version' is missing from this install"
  assert_output_contains "doctor"
  refute_output_contains "not built yet"
  refute_output_contains "ST0001"
}

@test "3 -- a name-only built-in says what makes it run, never that it is unbuilt (0111)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # `build` is name-only BY DESIGN: devbin ships the name and the project
  # declares what it runs. The refusal told the reader to wait for ST0001/WP-14
  # -- closed, and the wrong work package besides -- while `help --why` said
  # the true thing about the same command. The user meets the refusal, not
  # --why, at exactly the moment they are blocked.
  run devbin_run "$proj" build
  assert_exit_code 3
  assert_output_contains "ships the name only"
  assert_output_contains "commands.build.run"
  refute_output_contains "not built yet"
  refute_output_contains "ST0001"
}

@test "the refusal and help --why give ONE answer for a name-only built-in (0111)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # Two surfaces answering one question drifted once; this holds them to a
  # single source. Taken from --why and required verbatim in the refusal.
  run devbin_run "$proj" help --why
  assert_success
  why="$(sed -n 's/.*\(devbin ships the name only.*\)$/\1/p' <<<"$output")"
  why="${why%%$'\n'*}"
  [ -n "$why" ] || fail "help --why printed no name-only line for build -- the arm would compare nothing"
  run devbin_run "$proj" build
  assert_exit_code 3
  assert_output_contains "$why"
}

@test "3 -- a catalogue OPTION whose devbin handler is missing names the handler, not a thread (0111)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    options:
      format:
        summary: Formatting, declared so the project can name it
YAML
  )"
  # The OPTION-path site, measured to have no consumer in any project that
  # vendors devbin -- which is why it is driven here by construction rather than
  # found in the wild. It is reached only when a project DECLARES a built-in
  # option without a run: of its own (to rename or re-log it) and devbin's
  # handler for the command is then absent -- an undeclared built-in option
  # never reaches run_option at all, it goes to the handler. check.format is an
  # @builtin catalogue option; removing lib/cmd/check is the partial install.
  rm -f "$proj/bin/.devbin/lib/cmd/check"
  run devbin_run "$proj" check format
  assert_exit_code 3
  assert_output_contains "handler for 'check' is missing from this install"
  refute_output_contains "not built yet"
  refute_output_contains "ST0001"
}

# ----------------------------------------------------------------------------
# ONE ANSWER WHEN devbin's HANDLER IS MISSING, TOO (issue 0117)
# ----------------------------------------------------------------------------
#
# 0111 held the refusal and `help --why` to one sentence for a name-only
# built-in, and the note said they "cannot drift again". They still disagreed
# for a partial install: --why said `devbin catalogue`, because
# builtin_has_default_run counted `@builtin` as a command line, and for an
# option it named the catalogue whatever the handler's state. Each arm takes the
# sentence from --why and requires it verbatim in the refusal, as 0111's does.

# _why_from <output> <row> -- the `from:` text printed under a --why row.
_why_from() {
  awk -v row="$2" '
    found && /^ +from: / { sub(/^ +from: /, ""); print; exit }
    { line = $0; sub(/^ +/, "", line); split(line, w, / {2,}/) }
    w[1] == row { found = 1 }
  ' <<<"$1"
}

@test "help --why and the refusal give ONE answer when devbin's handler for a COMMAND is missing (0117)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  rm -f "$proj/bin/.devbin/lib/cmd/version"
  run devbin_run "$proj" help --why
  assert_success
  why="$(_why_from "$output" version)"
  [ -n "$why" ] || fail "help --why printed no from: line under version -- the arm would compare nothing: $output"
  [ "$why" != "devbin catalogue" ] || fail "help --why says version comes from the catalogue, which runs nothing here"
  run devbin_run "$proj" version
  assert_exit_code 3
  assert_output_contains "$why"
}

@test "help --why and the refusal give ONE answer for a catalogue OPTION whose handler is missing (0117)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    options:
      format:
        summary: Formatting, declared so the project can name it
YAML
  )"
  rm -f "$proj/bin/.devbin/lib/cmd/check"
  run devbin_run "$proj" help --why
  assert_success
  why="$(_why_from "$output" format)"
  [ -n "$why" ] || fail "help --why printed no from: line under check's format -- the arm would compare nothing: $output"
  [ "$why" != "devbin catalogue" ] || fail "help --why says check format comes from the catalogue, which runs nothing here"
  run devbin_run "$proj" check format
  assert_exit_code 3
  assert_output_contains "$why"
}

@test "the same option says devbin catalogue while its handler is there -- the control (0117)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  check:
    options:
      format:
        summary: Formatting, declared so the project can name it
YAML
  )"
  run devbin_run "$proj" help --why
  assert_success
  [ "$(_why_from "$output" format)" = "devbin catalogue" ] ||
    fail "with devbin's handler present, check format should come from the catalogue: $(_why_from "$output" format)"
  [ "$(_why_from "$output" version)" = "devbin lib/cmd/version" ] ||
    fail "with devbin's handler present, version should come from it: $(_why_from "$output" version)"
}

@test "doctor no longer counts a command whose devbin handler is missing as runnable (0117)" {
  # _command_runnable says it asks run_command's sources in run_command's order;
  # it counted `@builtin` as a command line too, so doctor blessed a command the
  # dispatcher refuses.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  rm -f "$proj/bin/.devbin/lib/cmd/version"
  run devbin_run "$proj" doctor
  grep -E 'offered with nothing to run:.* version( |$)' <<<"$output" ||
    fail "doctor did not list version among the commands with nothing to run: $output"
}

@test "the refusal goes to stderr, and stdout carries nothing (0117)" {
  # The helper 0111 moved these sites off, not_yet, has held its stream since
  # the start (helpers.bats); the new one was not held, and bats' run merges
  # the two streams, so nothing here could see a refusal printed to stdout.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run bash -c "cd '$proj' && bin/devbin build 2>/dev/null"
  assert_exit_code 3
  [ -z "$output" ] || fail "the refusal wrote to stdout: $output"
  run bash -c "cd '$proj' && bin/devbin build 2>&1 1>/dev/null"
  assert_exit_code 3
  assert_output_contains "resolves, but nothing here runs it"
}

@test "declaring the key the refusal names makes the command run (0117)" {
  # The strong form of checking a remedy. The arms above match the key as a
  # substring, and commands.build.runs contains commands.build.run, so a remedy
  # naming a key the validator refuses passed every arm. Here the key is taken
  # from the refusal and declared.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" build
  assert_exit_code 3
  key="$(sed -n 's/.*declare \(commands\.[A-Za-z0-9_.-]*\) or add.*/\1/p' <<<"$output")"
  key="${key%%$'\n'*}"
  [ -n "$key" ] || fail "the refusal named no declarable key: $output"
  # The key AS NAMED, written out as nested YAML -- never a hand-written copy of
  # what it ought to say, or the arm checks its own spelling instead.
  printf '%s\n' "$key" | awk -F. '{
    for (i = 1; i < NF; i++) printf "%*s%s:\n", (i - 1) * 2, "", $i
    printf "%*s%s: echo built-by-the-named-key\n", (NF - 1) * 2, "", $NF
  }' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" build
  assert_success
  assert_output_contains "built-by-the-named-key"
}

# _why_direct <args> -- unrunnable_why called directly, under the errexit every
# handler runs with, and a line after it that prints only if the call returned.
_why_direct() {
  run bash -c "set -euo pipefail; . '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/config'
    . '$DEVBIN_LIB_DIR/resolve'; DEVBIN_INVOKE=bin/devbin; unrunnable_why $*; echo returned"
}

@test "unrunnable_why asked about a name the catalogue lacks says devbin defect, and returns (0117)" {
  # No caller passes such a name, so no dispatch reaches this; the function is
  # called directly. With no branch for it, the failed lookup ended the caller
  # under errexit with no word.
  _why_direct nosuchcommand
  assert_success
  assert_output_contains "devbin defect: devbin's catalogue has no row for 'nosuchcommand'"
  assert_output_contains "returned"
  refute_output_contains "ships the name only"
  refute_output_contains "handler for"
  # A catalogued command with an option the catalogue lacks is the same defect.
  _why_direct version nosuchoption
  assert_success
  assert_output_contains "no row for 'version nosuchoption'"
  assert_output_contains "returned"
  refute_output_contains "handler for"
  # THE CONTROL: a catalogued name gets its reason, never the defect line.
  _why_direct version
  assert_success
  assert_output_contains "devbin's handler for 'version' is missing"
  refute_output_contains "devbin defect"
}

# ----------------------------------------------------------------------------
# 2 IS THE DISPATCHER'S (issues 0119 and 0126)
# ----------------------------------------------------------------------------
#
# documentation.bats holds the SET of codes the source can return to the
# contract's line, in both directions, and 2 is in both sets -- so a 2 used for
# another meaning passed it twice: bare shell-init's usage error (0119) and
# infra's "could not be measured" (0126). A handler runs only once the
# dispatcher has found its command known and active, so a handler has ONE reason
# to answer 2, and this arm holds that MEANING rather than the set: a verb of
# its own that the project has switched off, which is the dispatcher's "not
# available here" one level down (ST0008 WP-08: release.verbs). Such a site says
# so on the comment lines just above it, a comment line that opens
# `# code-2: <why>`, its reason saying the site is "not available here", the
# dispatcher's words: a marker with no reason or another one exempts nothing,
# nor does a marker quoted inside a comment's prose, nor one a blank line
# separates from the site.
#
# WHAT IT CANNOT SEE, stated because it has already happened: a 2 that reaches
# `exit` through a variable or an argument. Release's confirm step passed 2 to
# cut_fail, which ended `exit "${3:-1}"`, and it answered 2 while this arm, then
# titled "no handler under lib/cmd exits or returns 2", was green (issue 0130).
# Every such site under lib/ and bin/ was read by hand, and that was the only
# one; 0130 moved it to 1, and cut_fail takes no code any more.
# The title says LITERAL because that is what the scan reads.

# _code2_sites <dir> -- every non-comment line under <dir> that exits or returns
# a literal 2, as `<file>:<line>:<text>`, but one whose comment lines just above
# it open with `# code-2:` and say "not available here": that marker covers the
# one site after it. A grep or an awk that cannot read the tree fails the
# caller, rather than reading as a tree with nothing in it.
_code2_sites() {
  local raw
  local -a files
  raw="$(grep -rlE '(^|[^A-Za-z0-9_])(exit|return) 2([^0-9]|$)' "$1")" || [ $? -eq 1 ] ||
    { fail "grep could not read $1"; return 1; }
  [ -n "$raw" ] || return 0
  mapfile -t files <<<"$raw"
  awk '
    FNR == 1 { marked = 0; block = "" }
    /^[ \t]*#/ {
      c = $0
      sub(/^[ \t]*#[ \t]*/, "", c)
      if ($0 ~ /^[ \t]*#[ \t]*code-2:/) { marked = 1; block = c } else if (marked) block = block " " c
      next
    }
    /(^|[^A-Za-z0-9_])(exit|return) 2([^0-9]|$)/ && !(marked && block ~ /not available here/) { print FILENAME ":" FNR ":" $0 }
    { marked = 0; block = "" }
  ' "${files[@]}" || { fail "awk could not read the files under $1"; return 1; }
}

@test "no handler under lib/cmd exits or returns a literal 2 unless it says it is the dispatcher's meaning: that code is the dispatcher's (0119, 0126, ST0008 WP-08)" {
  # POSITIVE CONTROL first: a planted 2 is found, and a 2 in a comment is not,
  # so a clean result below is the scan finding nothing rather than unable to.
  # So is a 2 under a `# code-2:` marker with no reason, one whose reason is not
  # the dispatcher's, one quoting the marker inside prose, and one a blank line
  # parts from its marker; a 2 whose marker says "not available here", over one
  # comment line or two, is the one not found.
  mkdir -p "$DEVBIN_TEST_TMPDIR/plant"
  printf '%s\n' '#!/usr/bin/env bash' '# exit 2 in a comment is prose' '[ -n "$1" ] || return 2' \
    '# code-2: a verb switched off is not available' '# here, the meaning the dispatcher gives 2' 'exit 2 # marked' \
    '# code-2:' 'exit 2 # marker with no reason' \
    '# code-2: could not be measured' 'exit 2 # another meaning' \
    '# prose that quotes `# code-2: not available here`' 'exit 2 # quoted marker' \
    '# code-2: not available here, but parted from its site' '' 'exit 2 # after a blank line' >"$DEVBIN_TEST_TMPDIR/plant/h"
  run _code2_sites "$DEVBIN_TEST_TMPDIR/plant"
  assert_output_contains "return 2"
  refute_output_contains "in a comment"
  refute_output_contains "# marked"
  assert_output_contains "# marker with no reason"
  assert_output_contains "# another meaning"
  assert_output_contains "# quoted marker"
  assert_output_contains "# after a blank line"
  local n
  n="$(find "$DEVBIN_LIB_DIR/cmd" -type f | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || fail "found no handler file under lib/cmd -- the scan would read nothing"
  run _code2_sites "$DEVBIN_LIB_DIR/cmd"
  [ -z "$output" ] || fail "a handler answers 2, the dispatcher's code for an unknown or inactive command:
$output"
}

# ----------------------------------------------------------------------------
# A find THAT CANNOT READ EVERYTHING IS NEVER READ AS COMPLETE (issue 0139)
# ----------------------------------------------------------------------------
#
# A find with its errors sent to /dev/null, or whose status nobody reads, reads
# a directory it could not open as a directory with nothing in it, and its
# caller reports a complete answer over part of the tree: infra profiles said
# no domain was claimed twice, and devbin's own syntax gate passed 47 files and
# 0 breaches over a planted breach it could not list. So every find under lib/
# and bin/ keeps its error on stderr and reads its status -- `if ! find`, or a
# `||` that handles the failure -- or the line before it says where its status
# goes and why: `# find-status: <why>`.

# _unchecked_finds <dir> -- every find under <dir> that discards its errors or
# reads no status, as `<file>:<line>: <the command>`. Continued lines are joined
# first, so a find spread over several lines is read whole, and so is a line
# ending in `||` with the line after it. A find COMMAND is the word, any options
# (-H, -L, ...), then a path -- a quote, `$`, `.`, `/`, or `bin`, `lib` or
# `tests` -- so prose saying "cannot find it" is not one; a call of find_list,
# whose status is find's, is one too. Its status is judged by what comes AFTER
# it, so a `||` belonging to an earlier command on the line is not its handler;
# an `if !` directly before it is. A find inside a test bracket, a process
# substitution, or a `local`, `declare`, `export`, `readonly` or `typeset`
# assignment has no status its line can read, whatever follows. `|| :`,
# `|| true`, `|| return 0`, `|| exit 0`, `|| continue`, `|| break`, `|| echo`,
# `|| printf`, `|| { :; }` and `|| <name>=0` or `=""` read a status only to drop
# it, and `2>>/dev/null`, `2>&-`, `&>/dev/null` and `>/dev/null 2>&1` lose the
# error as `2>` does. A grep that cannot read the tree fails the caller rather
# than reading as a tree with nothing in it.
#
# WHAT IT STILL CANNOT SEE, stated because reviews of 0139 found each: a
# redirection on an enclosing group or an `exec` (`} 2>/dev/null`,
# `exec 2>/dev/null`); a `||` inside a string or a comment on the find's line,
# or one belonging to a later command on it; a find whose own substitution ends
# in `; true`; a comment ending in a backslash (awk joins it; bash does not); a
# find reached through a variable such as "${FIND:-find}"; a path given as `--`,
# `~`, a single-quoted word or a bare word other than bin, lib and tests; and
# the wrappers other than find_list that return find's status --
# cargo_target_dirs, cargo_walk, cargo_build_dirs, runtime_digest,
# vendored_paths -- whose callers it does not follow. Nor, from a later review:
# a handler reading another command's status (`cmd "$(find ...)" || die`); an
# assignment prefix such as `LC_ALL=C find` inside a substitution, a process
# substitution, a `local` or a test bracket; a second find on a line whose first
# is handled; `local a b="$(find ...)"` and `local -- x=`; `|| { true; }` and
# `|| { return 0; }`; `|| [ $? -eq 1 ]`, this scan's own grep idiom, which drops
# find's errors; and `2>"/dev/null"` and `>&/dev/null`. And it FLAGS, though the
# status is read, a later command's `>/dev/null 2>&1` on the find's line, a bare
# `if find ...; then`, and `if ! x="$(LC_ALL=C find ...)"`. Every find under
# lib/ and bin/, find_list calls included, was read by hand, and none takes any
# of those shapes.
_unchecked_finds() {
  local files f
  files="$(grep -rlE '(^|[^A-Za-z0-9_.-])find(_list|_walk)?[[:space:]]' "$1")" || [ $? -eq 1 ] ||
    fail "grep could not read $1"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    awk -v file="$f" '
      function flush(   hit, pre, post, checked, dropped, lost) {
        hit = (buf !~ /^[ \t]*#/) && (match(buf, /(^|[^A-Za-z0-9_.-])find(_walk)?([ \t]+-[A-Za-z]+)*[ \t]+("|\$|\.|\/|(bin|lib|tests)[ \t])/) ||
          match(buf, /(^|[^A-Za-z0-9_.-])find_list[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]/))
        if (hit) {
          # What comes BEFORE the find decides only whether it is an `if !`
          # test or sits inside a test bracket or a process substitution; what
          # comes AFTER it is where its own handler can be.
          pre = substr(buf, 1, RSTART)
          post = substr(buf, RSTART + 1)
          dropped = (post ~ /\|\|[ \t]*(:|true|return[ \t]+0|exit[ \t]+0|continue|break|echo|printf|[A-Za-z_][A-Za-z0-9_]*=(0|"")?|\{[ \t]*:[ \t]*;[ \t]*\})([ \t;)]|$)/)
          checked = (pre ~ /(if|elif|while|until)[ \t]+![ \t]*([A-Za-z_][A-Za-z0-9_]*="?\$\([ \t]*)?$/) ||
            (post ~ /\|\|[ \t]*[^ \t]/ && !dropped)
          lost = (post ~ /2>>?[ \t]*\/dev\/null|2>&-|&>>?[ \t]*\/dev\/null|>[ \t]*\/dev\/null[ \t]+2>&1/) || !checked ||
            (pre ~ /<\([ \t]*$/) || (pre ~ /\[\[?[ \t][^]]*\$\([ \t]*$/) ||
            (pre ~ /(local|declare|export|readonly|typeset)([ \t]+-[A-Za-z]+)*[ \t]+[A-Za-z_][A-Za-z0-9_]*="?\$\([ \t]*$/)
          if (lost && before !~ /#[ \t]*find-status:/) print file ":" start ": " buf
        }
        buf = ""
      }
      {
        if (buf == "") { start = FNR; before = last }
        line = $0
        # A continued line, or one ending in `||` whose handler is on the next,
        # is read with the line after it.
        cont = (line ~ /\\$/) || (line ~ /\|\|[ \t]*$/)
        sub(/\\$/, "", line)
        buf = buf line " "
        if (!cont) flush()
        last = $0
      }
      END { if (buf != "") flush() }
    ' "$f" || fail "awk could not read $f"
  done <<<"$files"
}

@test "the two statements of a run id's format are one format: bin/devbin's and lib/runlog's run_id_mint (0135)" {
  # bin/devbin mints before lib/ is found, under bash 3.2, so it cannot call
  # run_id_mint; the copy is legitimate only while this holds them together,
  # as the drift test holds CLAUDE.md and AGENTS.md.
  local dev lib
  dev="$(grep -E "^[[:space:]]*DEVBIN_RUN_ID=\"\\\$\(printf '%04x%04x'" "$DEVBIN_HOME/bin/devbin" | sed 's/^[[:space:]]*DEVBIN_RUN_ID="\$(//; s/)"[[:space:]]*$//')"
  lib="$(sed -n '/^run_id_mint() {/,/^}/p' "$DEVBIN_LIB_DIR/runlog" | grep -E "^[[:space:]]*printf '%04x%04x'" | sed 's/^[[:space:]]*//')"
  [ -n "$dev" ] && [ -n "$lib" ] || fail "could not extract both lines -- the checks below would be vacuous: dev=[$dev] lib=[$lib]"
  [ "${dev//\$\$/\$BASHPID}" = "$lib" ] || fail "the two mint lines differ beyond \$\$ and \$BASHPID:
bin/devbin:  $dev
lib/runlog:  $lib"
  # And both, run, mint eight lowercase hex digits.
  local a b
  a="$(bash -c "$dev")"
  b="$(bash -c ". '$DEVBIN_LIB_DIR/helpers'; . '$DEVBIN_LIB_DIR/runlog'; run_id_mint")"
  [[ "$a" =~ ^[0-9a-f]{8}$ ]] || fail "bin/devbin's mint gives '$a'"
  [[ "$b" =~ ^[0-9a-f]{8}$ ]] || fail "run_id_mint gives '$b'"
}

# _unwalked_finds <dir> -- every plain find command under <dir> with no
# `# find-walk: <why>` mark, a non-empty reason, in the comment lines just above
# it, as `file:line: text`. find_walk and find_list calls are not plain finds.
_unwalked_finds() {
  local files f
  files="$(grep -rlE '(^|[^A-Za-z0-9_.-])find[[:space:]]' "$1")" || [ $? -eq 1 ] ||
    fail "grep could not read $1"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    awk -v file="$f" '
      /^[ \t]*#/ { block = block "\n" $0; next }
      {
        if (match($0, /(^|[^A-Za-z0-9_.-])find([ \t]+-[A-Za-z]+)*[ \t]+("|\$|\.|\/|(bin|lib|tests)[ \t])/) &&
          block !~ /#[ \t]*find-walk:[ \t]*[^ \t]/)
          print file ":" FNR ": " $0
        block = ""
      }
    ' "$f" || fail "awk could not read $f"
  done <<<"$files"
}

@test "every find under lib/ and bin/ that can descend is find_walk, or says why not (0145)" {
  local probe="$DEVBIN_TEST_TMPDIR/walkprobe" out
  # POSITIVE CONTROL: a plain find that descends is flagged, marked or not with
  # a reason; one whose mark is empty is flagged too.
  mkdir -p "$probe"
  printf 'x="$(find "$d" -type f -print)" || rc=1\n' >"$probe/plain"
  printf '# find-walk:\nx="$(find "$d" -type f -print)" || rc=1\n' >"$probe/emptymark"
  printf '# find-walk:   \nx="$(find "$d" -type f -print)" || rc=1\n' >"$probe/blankmark"
  printf '# find-status: read below\nx="$(find -H "$d" -type f -print)" || rc=1\n' >"$probe/otherkind"
  out="$(_unwalked_finds "$probe")"
  local -a plants=("$probe"/*)
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq "${#plants[@]}" ] || fail "the scan missed a planted plain find:
$out"
  # NEGATIVE CONTROL: find_walk and find_list calls, a bounded find marked with
  # its reason (the mark above another mark counts), and prose.
  rm "$probe"/*
  printf 'x="$(find_walk "$d" -type f -print)" || rc=1\n' >"$probe/walk"
  printf 'find_list files "$d" -type f -print0 || rc=1\n' >"$probe/list"
  printf '# find-walk: -maxdepth 1 -- it never enters one\nx="$(find "$d" -maxdepth 1 -print)" || rc=1\n' >"$probe/marked"
  printf '# find-walk: -maxdepth 1 -- one file\n# find-status: dropped -- a repeat\ny="$(find "$d" -maxdepth 1 2>/dev/null)"\n' >"$probe/twomarks"
  printf 'die "cannot find it"\n' >"$probe/prose"
  out="$(_unwalked_finds "$probe")"
  [ -z "$out" ] || fail "the scan flags a find_walk, a marked find, or prose:
$out"
  # THE TREE: every plain find under lib/ and bin/ is marked.
  out="$(_unwalked_finds "$DEVBIN_LIB_DIR")$(_unwalked_finds "$DEVBIN_HOME/bin")"
  [ -z "$out" ] || fail "a find that can descend is not find_walk and says no reason:
$out"
  # PRESENCE: find_walk is called where the walks are, so the tree read is not empty.
  local n
  n="$(grep -rhE '(^|[^A-Za-z0-9_.-])find_walk[[:space:]]' "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin" | grep -vcE '^[[:space:]]*#')" || n=0
  [ "$n" -gt 0 ] || fail "found no find_walk call under lib/ and bin/ -- the scan would read nothing"
}

@test "every find under lib/ and bin/ reads its status or says why not (0139)" {
  local probe="$DEVBIN_TEST_TMPDIR/findprobe" out n
  # POSITIVE CONTROL: each shape that loses find's errors or its status is found
  # -- stderr to /dev/null on one line and across a continuation, and with a
  # status read beside it; a process substitution; a heredoc's command
  # substitution; `|| :`; `|| true`; a find inside a test; a find piped on with
  # no status read. And the shapes a review of 0139 found passing: options
  # before the path; a process substitution with a `||` after it; a `||`
  # belonging to an earlier command; a test bracket with a `||` after it;
  # `|| return 0`; `true` on the line after a `||`; `2>>/dev/null`; `2>&-`; and
  # `lib` as the path. And those of a second review: a find_list call with no
  # handler, and one with `|| true`; a `local` assignment; `&>/dev/null`;
  # `>/dev/null 2>&1`; and `|| exit 0`, `|| break`, `|| { :; }`, `|| rc=0` and
  # `|| printf`.
  mkdir -p "$probe"
  printf 'x="$(find "$d" -type f 2>/dev/null)"\n' >"$probe/devnull"
  printf 'find "$d" \\\n  -type f -print 2>/dev/null | sort\n' >"$probe/continued"
  printf 'x="$(find "$d" -type l 2>/dev/null)" || return 1\n' >"$probe/devnullread"
  printf 'done < <(find "$d" -type f)\n' >"$probe/procsub"
  printf 'done <<EOF\n$(find "$d" -type f | sort)\nEOF\n' >"$probe/heredoc"
  printf 'x="$(find "$d" -type f)" || :\n' >"$probe/colon"
  printf 'x="$(find "$d" -type f)" || true\n' >"$probe/true"
  printf 'if [ -n "$(find "$d" -name z -print -quit)" ]; then :; fi\n' >"$probe/test"
  printf 'n="$(find "$d" -type f | wc -l)"\n' >"$probe/piped"
  printf 'x="$(find -H "$d" -type f 2>/dev/null)"\n' >"$probe/optfirst"
  printf 'done < <(find "$d" -type f) || rc=1\n' >"$probe/procsubor"
  # Its handler a real one: `|| return 0` is itself a dropping handler, so a
  # scan that took the earlier `||` for the find's flagged it all the same
  # (mutant S13).
  printf '[ -d "$d" ] || die "no dir"; x="$(find "$d" -type f)"\n' >"$probe/otheror"
  printf '[ -z "$(find "$d" -type f)" ] || die "x"\n' >"$probe/testor"
  printf 'x="$(find "$d" -type f)" || return 0\n' >"$probe/return0"
  printf 'x="$(find "$d" -type f)" ||\n  true\n' >"$probe/nexttrue"
  printf 'x="$(find "$d" -type f 2>>/dev/null)" || rc=1\n' >"$probe/append"
  printf 'x="$(find "$d" -type f 2>&-)" || rc=1\n' >"$probe/closed"
  printf 'find lib bin -type f 2>/dev/null | sort\n' >"$probe/libword"
  printf 'find_list files "$d" -type f -print0\n' >"$probe/findlist"
  printf 'find_list files "$d" -type f -print0 || true\n' >"$probe/findlisttrue"
  printf 'local x="$(find "$d" -type f)" || die "x"\n' >"$probe/localassign"
  printf 'x="$(find "$d" -type f &>/dev/null)" || rc=1\n' >"$probe/ampdevnull"
  printf 'find "$d" -type f >/dev/null 2>&1 || rc=1\n' >"$probe/devnull21"
  printf 'x="$(find "$d" -type f)" || exit 0\n' >"$probe/exit0"
  printf 'x="$(find "$d" -type f)" || break\n' >"$probe/break"
  printf 'x="$(find "$d" -type f)" || { :; }\n' >"$probe/bracecolon"
  printf 'x="$(find "$d" -type f)" || rc=0\n' >"$probe/rc0"
  printf 'x="$(find "$d" -type f)" || printf none\n' >"$probe/printf"
  out="$(_unchecked_finds "$probe")"
  local -a plants=("$probe"/*)
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq "${#plants[@]}" ] || fail "the scan missed a planted unchecked find:
$out"
  # NEGATIVE CONTROL: a find that reads its status, on one line, under `if !`,
  # continued, or handled on the next line; one marked with its reason; prose
  # that says find; a find in a comment; and options before the path, `lib` as
  # the path, and a marked process substitution; a find_list call under `if !`,
  # and find_list's own definition; and a `local` declared on a line of its own
  # before the assignment that reads the status. None is flagged.
  rm "$probe"/*
  printf 'x="$(find "$d" -type f)" || rc=1\n' >"$probe/checked"
  printf 'if ! find "$d" -type f -print0 >"$l"; then exit 1; fi\n' >"$probe/ifnot"
  printf 'if ! part="$(find "$d" \\\n  -type f)"; then exit 1; fi\n' >"$probe/ifnotcontinued"
  printf 'x="$(find "$d" \\\n  -type f)" || rc=1\n' >"$probe/continuedchecked"
  printf 'listing="$(find "$d" -type f)" ||\n  die "no"\n' >"$probe/nextline"
  printf '# find-status: dropped -- a failure only repeats a check\ny="$(find "$d" -name z 2>/dev/null)"\n' >"$probe/marked"
  printf 'die "cannot find it" 2>/dev/null\n' >"$probe/prose"
  printf '# find "$d" -type f 2>/dev/null, in a comment\n' >"$probe/comment"
  printf 'if ! find -H "$d" -type f -print0 >"$l"; then exit 1; fi\n' >"$probe/optfirstchecked"
  printf 'if ! find lib bin -type f >"$l"; then exit 1; fi\n' >"$probe/libchecked"
  printf '    # find-status: read by the wait on its process substitution, below\n  done < <(find "$d" -type f)\n' >"$probe/procsubmarked"
  printf 'if ! find_list files "$d" -type f -print0; then exit 1; fi\n' >"$probe/findlistchecked"
  printf 'find_list() {\n  :\n}\n' >"$probe/findlistdef"
  printf 'local x\nx="$(find "$d" -type f)" || die "x"\n' >"$probe/localthenassign"
  out="$(_unchecked_finds "$probe")"
  [ -z "$out" ] || fail "the scan flags a find that reads its status, one marked with its reason, prose, or a comment:
$out"
  # PRESENCE: the finds that exist, so a scan matching nothing is not a pass.
  n="$(grep -rhE '(^|[^A-Za-z0-9_.-])find(_walk)?([[:space:]]+-[A-Za-z]+)*[[:space:]]+("|\$|\.|/|(bin|lib|tests)[[:space:]])' "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin" | grep -vcE '^[[:space:]]*#')" || n=0
  [ "$n" -gt 0 ] || fail "found no find or find_walk command under lib/ and bin/ -- the scan would read nothing"
  out="$(_unchecked_finds "$DEVBIN_LIB_DIR")$(_unchecked_finds "$DEVBIN_HOME/bin")"
  [ -z "$out" ] || fail "a find loses its errors or its status:
$out"
}

@test "the walks a build runs beside ignore an entry that vanishes mid-walk (0139)" {
  # Measured with a writer beside the walk: 20 of 300 plain walks exited 1 and 0
  # of 300 with -ignore_readdir_race, and `check format` went red in 2 of 20
  # runs. A race is not a test a suite can hold, so the flag is held where it is
  # needed: each walk that reads its status over a tree a build may be writing.
  # check's Swift walk goes through find_list, whose arguments are find's own,
  # so find_list's line is read as a find's (I4), and since issue 0145 the
  # others through find_walk, read the same way.
  local f fn flagged=$'find(_list|_walk)?[ \t][^\n]*-ignore_readdir_race'
  for f in "lib/cmd/check:_check_format_swift" "lib/cmd/fmt:builtin_fmt_swift" \
    "lib/helpers:cargo_walk" "lib/cmd/new:test_dir" "lib/cmd/clean:_clean_roots"; do
    # COMMENT LINES ARE DROPPED, AND THE FLAG MUST STAND ON A find's OWN LINE:
    # matched over the whole text, the pin held with the flag deleted from
    # cargo_target_dirs' find, since its comment names the flag (mutant W2c).
    fn="$(awk -v fn="${f#*:}" '$0 ~ "^" fn "\\(\\) \\{" {p=1} p && $0 !~ /^[ \t]*#/ {print} p && /^}/ {exit}' "$DEVBIN_HOME/${f%%:*}")"
    [ -n "$fn" ] || fail "no function ${f#*:} in ${f%%:*}: the pin reads nothing"
    [[ "$fn" =~ find(_list|_walk)?[[:space:]] ]] || fail "${f#*:} in ${f%%:*} holds no find"
    [[ "$fn" =~ $flagged ]] || fail "${f#*:} in ${f%%:*} walks without -ignore_readdir_race"
  done
}

# NO BACKTICKS IN A TEST NAME. bats EVALS the description to resolve variable
# references in it (bats_test_function, test_functions.bash), so a name
# containing backticks or $(...) is command substitution: this one read
# "survives `all`" and bats dutifully tried to run `all`, printing
# "all: command not found" once per test in the file, forever, on stderr.
@test "the exit code of a failing option survives an all run" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  gates:
    summary: Gates
    options:
      good:
        run: echo fine
      bad:
        run: ./boom
YAML
  )"
  printf '#!/bin/sh\nexit 1\n' >"$proj/boom"
  chmod +x "$proj/boom"
  run devbin_run "$proj" gates all
  assert_failure
  # And it ran BOTH -- `all` does not stop at the first breach (AC-04.6).
  assert_output_contains "fine"
  assert_output_contains "FAILED:"
}

# ----------------------------------------------------------------------------
# EVERY devbin_setup HAS ITS devbin_teardown (issue 0142)
# ----------------------------------------------------------------------------
#
# devbin_setup makes a devbin-test.* directory under $TMPDIR for each arm, and
# devbin_teardown is the only thing that removes it. infra.bats and
# infra-dmarc-report.bats called the one from setup() and never the other, so
# every arm in them left its directory behind, green, on every run. Nothing
# fails when a directory leaks, which is why a scan holds it rather than an arm
# in the suite that leaks.

# _setup_without_teardown <dir> -- the .bats files in <dir> that call
# devbin_setup on a non-comment line and whose teardown() does not call
# devbin_teardown. The teardown half reads the teardown() BODY, one-line or
# not, as commands: the name in a test's title, a string or a comment is not a
# call, and the file that defines this scan carries all three. A file that
# cannot be read fails the caller and stops the scan (status 2), rather than
# reading as a file with no calls.
_setup_without_teardown() {
  local f rc
  for f in "$1"/*.bats; do
    rc=0; grep -q '^[^#]*devbin_setup' "$f" || rc=$?
    case "$rc" in 0) ;; 1) continue ;; *) fail "grep could not read $f"; return 2 ;; esac
    rc=0
    awk '
      function calls(l) { sub(/#.*/, "", l); return l ~ /(^|[;{[:space:]])devbin_teardown([;}[:space:]]|$)/ }
      /^teardown\(\)[[:space:]]*\{/ {
        l = $0; sub(/^teardown\(\)[[:space:]]*\{/, "", l)
        if (calls(l)) ok = 1
        if (l !~ /\}[[:space:]]*$/) body = 1
        next
      }
      body && /^\}/ { body = 0; next }
      body && calls($0) { ok = 1 }
      END { exit (ok ? 0 : 1) }' "$f" || rc=$?
    case "$rc" in 0) ;; 1) printf '%s\n' "${f##*/}" ;; *) fail "awk could not read $f"; return 2 ;; esac
  done
}

@test "every suite that calls devbin_setup also calls devbin_teardown, so no arm leaks its temp dir (0142)" {
  # POSITIVE CONTROL first: a planted suite with setup and no teardown is
  # named; so are suites naming devbin_teardown only in a comment (outside
  # teardown() or inside it), only in a test's title or a string, or calling
  # it from one arm rather than teardown(); one with a teardown() calling it, on
  # one line or several, is not; a setup named only in a comment is not a
  # setup. So a clean result below is the scan finding nothing rather than
  # unable to.
  local plant="$DEVBIN_TEST_TMPDIR/plant"
  mkdir -p "$plant"
  printf 'setup() {\n  devbin_setup\n}\n' >"$plant/leaks.bats"
  printf 'setup() {\n  devbin_setup\n}\n# teardown() { devbin_teardown; }\n' >"$plant/comment.bats"
  printf 'setup() {\n  devbin_setup\n}\nteardown() {\n  # devbin_teardown here one day\n  rm -f x\n}\n' >"$plant/incomment.bats"
  printf 'setup() {\n  devbin_setup\n}\n@test "one arm cleans up" {\n  devbin_teardown\n}\n' >"$plant/inarm.bats"
  printf 'setup() {\n  devbin_setup\n}\n@test "devbin_teardown runs" {\n  printf "devbin_teardown\\n"\n}\n' >"$plant/string.bats"
  printf 'setup() {\n  devbin_setup\n}\nteardown() { devbin_teardown; }\n' >"$plant/oneline.bats"
  printf 'setup() {\n  devbin_setup\n}\nteardown() {\n  chmod -R u+w x || true\n  devbin_teardown\n}\n' >"$plant/block.bats"
  printf '# no devbin_setup here, only prose\n' >"$plant/prose.bats"
  run _setup_without_teardown "$plant"
  assert_success
  [ "$output" = "$(printf 'comment.bats\ninarm.bats\nincomment.bats\nleaks.bats\nstring.bats')" ] ||
    fail "the scan did not name exactly the five planted leaks:\n$output"
  # And a suite it cannot read stops it with a failure, not a clean pass.
  printf 'setup() {\n  devbin_setup\n}\n' >"$plant/unreadable.bats"
  chmod 000 "$plant/unreadable.bats"
  run _setup_without_teardown "$plant"
  chmod 644 "$plant/unreadable.bats"
  [ "$status" -ne 0 ] || fail "an unreadable suite passed the scan:\n$output"
  local n
  n="$(find "$DEVBIN_HOME/tests/unit" -name '*.bats' -type f | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || fail "found no suite under tests/unit -- the scan would read nothing"
  run _setup_without_teardown "$DEVBIN_HOME/tests/unit"
  assert_success
  [ -z "$output" ] || fail "these suites call devbin_setup and never devbin_teardown, so each arm leaks a devbin-test.* directory:
$output"
}

# ----------------------------------------------------------------------------
# NO READER STOPS BEFORE ITS WRITER HAS FINISHED (ST0008 AC-7.1, issue 0031)
# ----------------------------------------------------------------------------
#
# Under pipefail a pipeline answers with its writer's status as well as its
# reader's. A reader that can stop reading before its writer has finished --
# grep -q at its first match, head after its lines, awk at an exit -- leaves
# the writer holding output nobody will read: the writer takes SIGPIPE, and
# the pipeline answers 141 where the reader answered yes. It is a race, so the
# code passes almost every time: 0031 fixed four sites, and a fifth failed the
# v0.1.10 tag's Ubuntu run on an arm that had been green for months. So an
# early reader takes its input captured, never piped: the writer's output goes
# into a variable whose status is read, and the reader reads the variable from
# a here-string, `grep -q x <<<"$out"`. A pipe into an early reader stays only
# where the reader cannot decide before the writer's last byte, and the
# comment lines just above it say why: `# pipe-sound: <why>`.
#
# It reads every file under bin/, lib/, tests/ and .github/ but the .md and
# .yaml documents, and not only the files that set pipefail: a function runs
# under its caller's options and a script a test writes sets its own, so
# whether pipefail is in force cannot be read from the line.
#
# WHAT IT CANNOT SEE: a reader that is a function, a script or an interpreter
# (section in infra-dmarc-report.bats is an awk that exits, and its callers were
# found by reading); a piped while-read loop that breaks out early (the piped
# loops in the tree were read, and none does); an awk program or sed script held
# in a variable or a file, written in double quotes over several lines, or
# holding a quote of its own such as '\''; a reader reached through a variable,
# or behind a wrapper it does not strip, such as sudo with a user; and a reader
# it does not name. A bar needs no blank beside it to be a pipe, so cmd|head is
# read; the cost is that an alternation in a regular expression whose next
# branch is a reader's name, such as (tail|head), reads as a pipe and fails this
# arm, loudly, where a missed pipe would have passed it in silence. Spell such a
# pattern another way.

# _early_reader_pipes <dir>... -- every pipe under <dir> whose reader can stop
# reading before its writer has finished, as `<file>:<line>: <text>`, then
# `pipes: <n>`, the number of pipes it read. The readers that can: a grep with
# -q, -m, -l or -L or their long forms; head; a sed script holding q; an awk
# program holding exit; cmp; tar; read; and mapfile or readarray with -n --
# each by its name or its path, GNU's g-prefixed names too, after any
# NAME=value words, a `!`, and the wrappers command, builtin, exec, env, nice,
# time, sudo, stdbuf and timeout with their options. Continued lines (a
# trailing backslash, |, || or &&) are joined across blank and comment lines,
# so a pipeline over several lines is read whole, and a sed or awk program in
# single quotes is read to its closing quote on the lines below. A pipe in a
# string counts, so a script a test writes out is read too, and so does a bar
# with no blank beside it; in a .yml file a block's `run: |` is not a pipe. A
# `# pipe-sound:` mark covers the first early pipe after it, and no other. A
# <dir> that is not a readable directory, or a grep or an awk that fails,
# fails the caller and returns 1, so a tree it could not read is never a pass.
_early_reader_pipes() {
  local listing d
  local -a files
  for d in "$@"; do
    [ -d "$d" ] && [ -r "$d" ] || { fail "$d is not a directory the scan can read"; return 1; }
  done
  listing="$(grep -rlI --exclude='*.md' --exclude='*.yaml' -e '|' "$@")" || [ $? -eq 1 ] ||
    { fail "grep could not read $*"; return 1; }
  mapfile -t files <<<"$listing"
  [ -n "${files[0]}" ] || { printf 'pipes: 0\n'; return 0; }
  awk -v root="$DEVBIN_HOME/" '
    # prog <text> <line> -- what a sed or awk reader runs. Its own words end
    # at the first blank-flanked pipe, `;` or `&&`, so a quote further on
    # belongs to another command. Within them: its single-quoted text, read on
    # over the lines from <line> while a quote is left open; or else its first
    # double-quoted text; or else the words themselves.
    function prog(r, j,   f, g, t, own) {
      own = r
      if (match(own, /[ \t]\|[ \t]|;|&&/)) own = substr(own, 1, RSTART - 1)
      if ((f = index(own, "\047")) > 0) {
        t = substr(r, f + 1)
        if (gsub(/\047/, "\047", t) % 2 == 0) {
          for (; j <= nl; j++) { t = t "\n" L[j]; if (index(L[j], "\047")) break }
          return t
        }
        sub(/\047[^\047]*$/, "", t)
        return t
      }
      if ((g = index(own, "\"")) > 0) {
        t = substr(own, g + 1)
        if (index(t, "\"")) t = substr(t, 1, index(t, "\"") - 1)
        return t
      }
      t = own; sub(/[|;&)].*/, "", t)
      return t
    }
    # early <text> <line> -- whether the command in <text>, which follows a
    # pipe, is a reader that can stop before its input ends.
    function early(r, j,   o, a, n, i, w, again) {
      sub(/^&?[ \t]*/, "", r)
      do {
        again = 0
        if (match(r, /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) || match(r, /^[!{(][ \t]*/) ||
          match(r, /^(command|builtin|exec|env|nice|time|sudo|stdbuf|timeout)([ \t]+(-[^ \t]*|[0-9.]+[smhd]?))*[ \t]+/)) {
          r = substr(r, RLENGTH + 1)
          again = 1
        }
      } while (again)
      o = r; sub(/[|;&)].*/, "", o)
      n = split(o, a, /[ \t]+/); w = a[1]
      sub(/^\\/, "", w); sub(/^.*\//, "", w)
      if (w == "head" || w == "ghead" || w == "cmp" || w == "read") return 1
      if (w == "tar" || w == "gtar" || w == "bsdtar") return 1
      if (w == "mapfile" || w == "readarray") {
        for (i = 2; i <= n; i++) if (a[i] ~ /^-[A-Za-z]*n/) return 1
        return 0
      }
      if (w ~ /^[efg]?grep$/) {
        for (i = 2; i <= n && a[i] != "--"; i++)
          if (a[i] ~ /^-[A-Za-z0-9]*[qmlL]/ || a[i] ~ /^--(quiet|silent|max-count|files-with)/) return 1
        return 0
      }
      if (w == "sed" || w == "gsed") return prog(r, j) ~ /(^|[;{}[:space:]0-9$\/!])[qQ]([;}[:space:]0-9]|$)/
      if (w ~ /^[gmn]?awk$/) return prog(r, j) ~ /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/
      return 0
    }
    function scan(f,   i, s, c, cont, start, k, x, p, yml, m) {
      yml = (f ~ /\.ya?ml$/)
      if (index(f, root) == 1) f = substr(f, length(root) + 1)
      for (i = 1; i <= nl; i++) {
        if (L[i] ~ /^[ \t]*#/) { blk = blk "\n" L[i]; continue }
        start = i; s = ""
        for (;;) {
          c = L[i]
          cont = (c ~ /\\$/) || (c ~ /(\|\||&&)[ \t]*$/) ||
            (c ~ /(^|[^|>])\|[ \t]*$/ && !(yml && c ~ /:[ \t]*\|[ \t]*$/))
          sub(/\\$/, "", c); s = s c " "
          if (!cont || i == nl) break
          for (i++; i < nl && L[i] ~ /^[ \t]*(#.*)?$/; i++) ;
        }
        m = (blk ~ /#[ \t]*pipe-sound:[ \t]*[^ \t]/)
        k = 0
        while ((x = index(substr(s, k + 1), "|")) > 0) {
          k += x
          p = (k > 1) ? substr(s, k - 1, 1) : ""
          if (p == "|" || p == ">" || substr(s, k + 1, 1) == "|") continue
          if (yml && substr(s, 1, k - 1) ~ /:[ \t]*$/) continue
          pipes++
          if (early(substr(s, k + 1), i + 1)) {
            if (m) { m = 0; continue }
            print f ":" start ": " s
            break
          }
        }
        blk = ""
      }
    }
    FNR == 1 && NR > 1 { scan(file); delete L; blk = "" }
    { L[FNR] = $0; nl = FNR; file = FILENAME }
    END { if (nl) scan(file); print "pipes: " pipes + 0 }
  ' "${files[@]}" || { fail "awk could not read the tree"; return 1; }
}

# AT-7.1
@test "no reader in a pipe can stop before its writer has finished, unless the comment above it says why (ST0008 AC-7.1, 0031)" {
  # EACH TREE IS READ, AND HAS ITS FLOOR, ON ITS OWN. One floor over all four
  # was cleared by tests/ alone, so a lib/ the scan could not read passed it.
  # The floors are about half of what each tree held when they were set.
  local d out n min found=""
  for d in bin lib tests .github; do
    case "$d" in
      bin) min=50 ;;
      lib) min=300 ;;
      tests) min=600 ;;
      .github) min=3 ;;
    esac
    out="$(_early_reader_pipes "$DEVBIN_HOME/$d")" || fail "the scan could not read $d"
    n="${out##*pipes: }"
    [ "$n" -ge "$min" ] || fail "the scan read $n pipes in $d, fewer than $min -- it would read almost nothing there"
    found="$found${out%pipes: *}"
  done
  [ -z "$found" ] || fail "a reader can stop before its writer has finished, and the comment lines above it say no reason:
$found"
}

@test "doctor throws away no count's status and no catalogue read's status (0159)" {
  # `grep -c . || true` and `$(builtin_option_... 2>/dev/null || true)` threw
  # away the status that says the answer was never read: a manifest recording
  # nothing passed doctor as intact, and a row devbin could not read dropped a
  # shadow. Counts go through nonempty_lines, and reads are checked by name.
  #
  # THE SHAPES, NOT THE TWO SPELLINGS THAT WERE FOUND: a count by any grep -c or
  # --count, and a read through any catalogue reader, ended with `|| true` or
  # `|| :`. A comment that quotes one is not code, and is not counted. The
  # catalogue arm in doctor.bats holds the behaviour; this holds the spellings.
  local pat='grep (-[A-Za-z]*c[A-Za-z]*|--count)[^|]*[|][|] *(true|:)|(builtin_[a-z_]+|option_run_tier) [^)|]*[|][|] *(true|:)'
  local f="$DEVBIN_LIB_DIR/cmd/doctor" code='^[0-9]+:[[:space:]]*#' ctl hits
  # POSITIVE CONTROL: every shape found, and the quoting comment not.
  local -a shapes=(
    'n="$(printf x | grep -c . || true)"'
    'n="$(grep -cE x f || :)"'
    'n="$(grep --count x f || true)"'
    'r="$(builtin_option_run a b 2>/dev/null || true)"'
    'builtin_has_default_run x || :'
    't="$(option_run_tier a b || true)"'
  )
  [ "${#shapes[@]}" -gt 0 ] || fail "no shape planted -- the control would compare nothing"
  ctl="$(printf '%s\n' "${shapes[@]}" \
    '  # r="$(builtin_option_run a b || true)", quoted' |
    grep -n -E "$pat" | grep -v -E "$code" | awk 'END { print NR }')"
  [ "$ctl" -eq "${#shapes[@]}" ] || fail "the scan's pattern finds $ctl of the ${#shapes[@]} shapes it refuses, or counts a comment"
  hits="$(grep -n -E "$pat" "$f")" || [ $? -eq 1 ] || fail "could not read $f"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code" || true)"
  [ -z "$hits" ] || fail "doctor throws a status away:\n$hits"
}

@test "the gated-tool stdin rule has one definition: gate_exec, in lib/helpers (0158)" {
  # run_gate wrote `DEVBIN_GATE_TTY=... "$@" </dev/null` inline and the release
  # cut copied the redirect twice, so a project's handler had no name to call
  # and each copy could drift from the rule. Now gate_exec is the one line that
  # sets the flag and takes stdin from /dev/null together. The scan reads code,
  # never a comment, takes the redirect with or without a space, and the
  # release sites that inlined only the redirect are held by name.
  local pat='DEVBIN_GATE_TTY=[^ ]* .*< ?/dev/null' code='^[^:]+:[0-9]+:[[:space:]]*#' ctl hits n
  # POSITIVE CONTROL: the inline shape, spaced or not, is found; a comment
  # quoting it is not.
  local -a shapes=(
    'f:1:  DEVBIN_GATE_TTY="$gate_tty" "$@" </dev/null 2>&1 | tee -a "$log"'
    'f:2:  DEVBIN_GATE_TTY=1 "$@" < /dev/null'
  )
  [ "${#shapes[@]}" -gt 0 ] || fail "no shape planted -- the control would compare nothing"
  ctl="$(printf '%s\n' "${shapes[@]}" \
    'f:3:  # DEVBIN_GATE_TTY="$x" "$@" </dev/null, quoted' |
    grep -E "$pat" | grep -v -E "$code" | awk 'END { print NR }')"
  [ "$ctl" -eq "${#shapes[@]}" ] || fail "the scan's pattern finds $ctl of the ${#shapes[@]} inline shapes, or counts a comment"
  hits="$(grep -rn -E "$pat" "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin/devbin")" || [ $? -eq 1 ] || fail "could not read lib/"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code" || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [ "$n" -eq 1 ] || fail "the rule is written $n times, not once:\n$hits"
  [[ "$hits" == "$DEVBIN_LIB_DIR/helpers:"* ]] || fail "the one definition is not in lib/helpers: $hits"
  # The release cut's sites run through it, by name.
  grep -q -E '^[[:space:]]*gate_exec "\$launcher" version set ' "$DEVBIN_LIB_DIR/cmd/release" ||
    fail "release's version set does not run through gate_exec"
  grep -q -E '^[[:space:]]*gate_exec "\$\{aw\[@\]\}"' "$DEVBIN_LIB_DIR/cmd/release" ||
    fail "release's after: lines do not run through gate_exec"
  # And stdin_tty_flag is defined once, in lib/helpers, beside it.
  hits="$(grep -rn -E '^stdin_tty_flag\(\)' "$DEVBIN_LIB_DIR")" || fail "stdin_tty_flag is defined nowhere"
  [ "$(printf '%s\n' "$hits" | grep -c .)" -eq 1 ] && [[ "$hits" == "$DEVBIN_LIB_DIR/helpers:"* ]] ||
    fail "stdin_tty_flag is not defined exactly once, in lib/helpers: $hits"
}

@test "the lint gate check lint runs is clean over the tree, and a planted breach turns it red (0155)" {
  # Lint ran only at the cut and on CI, after landing, so two breaches reached a
  # release commit. This runs the gate `check lint` runs, from the suite.
  # It is also the only lint the Ubuntu job runs (0191), so under CI a
  # missing shellcheck FAILS here, as `check lint` would, rather than skipping.
  require_command shellcheck "shellcheck is not installed -- the lint gate was NOT run"
  local gate="$DEVBIN_HOME/bin/.devbin/cmd/.lib/shell-gate" probe="$DEVBIN_TEST_TMPDIR/lintprobe" n
  # POSITIVE CONTROL: a tree holding one clean file and one with an unused
  # variable (SC2034) is red, and names the breach.
  mkdir -p "$probe/lib" "$probe/bin" "$probe/tests"
  printf '#!/usr/bin/env bash\nprintf ok\n' >"$probe/lib/clean"
  printf '#!/usr/bin/env bash\nunused=1\n' >"$probe/lib/planted"
  run env PROJECT_ROOT="$probe" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$gate" lint
  assert_failure
  assert_output_contains "SC2034"
  assert_output_contains "lint: $(_lint_files) file(s), 1 breach(es)"
  # And the tree itself is clean, over its whole corpus.
  run env PROJECT_ROOT="$DEVBIN_HOME" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$gate" lint
  assert_success
  [[ "$output" =~ lint:\ ([0-9]+)\ file\(s\),\ 0\ breach\(es\) ]] || fail "no clean verdict: $output"
  n="${BASH_REMATCH[1]}"
  # THE CORPUS BY A SECOND ROUTE: every tracked file under bin/, lib/ and tests/
  # that the gates' rule calls shell -- *.bash, or a shell shebang, and never
  # *.bats -- listed by git rather than walked, so a corpus read short is named.
  local f control=0
  while IFS= read -r f; do
    [ -f "$DEVBIN_HOME/$f" ] && [ ! -L "$DEVBIN_HOME/$f" ] || continue
    case "$f" in
      *.bats) continue ;;
      *.bash)
        control=$((control + 1))
        continue
        ;;
    esac
    if grep -qE '^#!.*(bash|sh)([^A-Za-z0-9_]|$)' <<<"$(head -n1 "$DEVBIN_HOME/$f")"; then
      control=$((control + 1))
    fi
  done <<<"$(git -C "$DEVBIN_HOME" ls-files bin lib tests)"
  [ "$control" -gt 0 ] && [ "$n" -eq "$control" ] ||
    fail "the gate linted $n file(s), where git tracks $control shell file(s) under bin/, lib/ and tests/"
  echo "# lint: $n file(s), 0 breaches" >&3
}

@test "a directory is turned into a path only by physical_dir and logical_dir in lib/, the scan 0162 kept for cd -P widened to every cd (0267)" {
  # A copy of the step, `$(cd <dir> && pwd)`, physical or logical, read a
  # relative path through CDPATH and a lone `-` as $OLDPWD, printing either
  # into the capture, kept a leading // and dropped a trailing newline from a
  # name: install wrote a project under a path holding a newline, at exit 0
  # (0267). Any `cd ... && pwd` counts, `env pwd` and nested substitutions
  # included, and a comment quoting one is not one. The lines allowed are those
  # of physical_dir's and logical_dir's bodies that hold the step, read from
  # lib/helpers itself.
  #
  # OUTSIDE IT, BY DESIGN: bin/devbin's own bootstrap, which resolves its
  # directory before helpers is sourced and so cannot call either reader; its
  # two cds are fixed by hand instead, a relative dirname spelled from ./
  # (0267). And lib/tmpl/, which is no runtime code: its test.bats is a
  # template a project's own suite runs, before any devbin is loaded to call a
  # reader.
  #
  # WHAT IT STILL CANNOT SEE, stated because the review of 0267 found each: a
  # cd and its pwd on one line but not joined by `&&` (`cd x; pwd`, `cd x ||
  # exit; pwd`); a capture split over lines, the pwd on a continuation line;
  # pushd and popd; pwd reached by path or as a builtin (`/bin/pwd`, `builtin
  # pwd`); and a path read from $PWD after the cd (`cd x && printf %s "$PWD"`),
  # on its line or in a function called after it. Every cd under lib/ outside
  # lib/tmpl/ was read by hand, and none takes any of those shapes to turn a
  # directory argument into a path: the one $PWD read after a cd,
  # release.notes' _notes_command_env, exports the root its caller entered to
  # run notes.run there, and never returns it as an answer.
  local pat='(^|[^[:alnum:]_])cd[[:space:]].*&&[[:space:]]*(env[[:space:]]+|command[[:space:]]+)?pwd'
  local code='^[^:]+:[0-9]+:[[:space:]]*#' f body allowed="" hits h outside=""
  for f in physical_dir logical_dir; do
    body="$(awk -v fn="$f" -v pat="$pat" '$0 == fn "() {" { on = 1 } on && $0 ~ pat { print FILENAME ":" FNR ":" $0 } on && /^}$/ { exit }' "$DEVBIN_LIB_DIR/helpers")"
    [ -n "$body" ] || fail "lib/helpers has no $f() { holding the step -- the scan would allow nothing for it"
    allowed+="$body"$'\n'
  done
  hits="$(grep -rn -E "$pat" "$DEVBIN_LIB_DIR")" || [ $? -eq 1 ] || fail "could not read lib/"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    case "$h" in "$DEVBIN_LIB_DIR/tmpl/"*) continue ;; esac
    if grep -q -E "$code" <<<"$h" || grep -q -x -F -- "$h" <<<"$allowed"; then
      continue
    fi
    outside+="$h"$'\n'
  done <<<"$hits"
  [ -z "$outside" ] || fail "a directory is turned into a path outside physical_dir and logical_dir:\n$outside"
}

@test "a tree's kind is read as an install in one place, is_install_tree, and by no other reader (0262)" {
  # Each reader compared manifest_field's kind with `install` inline, and the
  # dispatcher's own guard spelled the read's failure its own way. bin/ is
  # scanned with lib/, since the dispatcher's guards and fleet's census and
  # sweep are readers too. The field may be quoted, and a comment quoting the
  # read is not one. The one read allowed is is_install_tree's body, the line
  # after its definition, so the hit expected is read from lib/helpers itself.
  local pat="manifest_field[[:space:]].*[[:space:]][\"']?kind[\"']?([^a-z_]|\$)" code='^[^:]+:[0-9]+:[[:space:]]*#' body hits
  body="$(awk '/^is_install_tree\(\) \{$/ { getline; print FILENAME ":" NR ":" $0; exit }' "$DEVBIN_LIB_DIR/helpers")"
  [ -n "$body" ] || fail "lib/helpers has no is_install_tree() { line -- the scan would allow nothing"
  hits="$(grep -rn -E "$pat" "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin")" || [ $? -eq 1 ] || fail "could not read lib/ or bin/"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code" || true)"
  [ "$hits" = "$body" ] || fail "the manifest's kind is read outside is_install_tree's body ($body):\n$hits"
}

@test "a manifest's devbin_version is read in one place, manifest_version through manifest_field, and by no other reader (0283)" {
  # runtime_version read the field with an awk of its own, which read past
  # the header and kept the spacing manifest_field trims. bin/ is scanned with
  # lib/. A reader is manifest_field asked for the field, or a tool's
  # pattern matching its header line; a comment is neither. The one read
  # allowed is manifest_version's line, read from lib/helpers itself.
  local field="manifest_field[[:space:]].*[[:space:]][\"']?devbin_version[\"']?([^a-z_]|\$)"
  local tool="(awk|grep|sed|cut)[^|]*devbin_version:" code='^[^:]+:[0-9]+:[[:space:]]*#' body hits
  body="$(grep -n -E '^manifest_version\(\) \{' "$DEVBIN_LIB_DIR/helpers" | sed "s|^|$DEVBIN_LIB_DIR/helpers:|")"
  [ -n "$body" ] || fail "lib/helpers has no manifest_version() { line -- the scan would allow nothing"
  hits="$(grep -rn -E "$field" "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin")" || [ $? -eq 1 ] || fail "could not read lib/ or bin/"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code" || true)"
  [ "$hits" = "$body" ] || fail "the manifest's devbin_version is read through manifest_field outside manifest_version ($body):\n$hits"
  hits="$(grep -rn -E "$tool" "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin")" || [ $? -eq 1 ] || fail "could not read lib/ or bin/"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code" || true)"
  [ -z "$hits" ] || fail "the manifest's devbin_version is read by a tool of its own, not manifest_field:\n$hits"
}

@test "a colon list is split by colon_split alone: no line in bin, lib or tests sets IFS to a colon but in the one join shape (0248)" {
  # Each site that split PATH or GIT_CEILING_DIRECTORIES wrote out its own
  # `read -r -a`, which read one line and dropped a trailing empty field. The
  # one use left is the join, IFS set to a colon inside a substitution that
  # prints "${name[*]}" and splits nothing; each such join is struck from its
  # line, and any IFS set to a colon still on a line that is not a comment is
  # a split, printed as struck. bin/ is scanned with its .devbin, and tests/
  # with lib/.
  local pat="IFS=[\"']?:" code='^[^:]+:[0-9]+:[[:space:]]*#' join hits struck
  join="\\(IFS=[:]; printf '%s' \"\\\$\\{[A-Za-z_][A-Za-z0-9_]*\\[\\*\\]\\}\"\\)"
  hits="$(grep -rn -E "$pat" "$DEVBIN_HOME/bin" "$DEVBIN_LIB_DIR" "$DEVBIN_HOME/tests")" || [ $? -eq 1 ] || fail "could not read bin/, lib/ or tests/"
  hits="$(printf '%s\n' "$hits" | grep -v -E "$code")" || [ $? -eq 1 ] || fail "could not drop the comment lines"
  struck="$(printf '%s\n' "$hits" | sed -E "s/$join//g")" || fail "could not strike the joins"
  hits="$(grep -E "$pat" <<<"$struck")" || [ $? -eq 1 ] || fail "could not read the struck lines"
  [ -z "$hits" ] || fail "a colon list is split outside colon_split:\n$hits"
}

# Runs the lint gate over a probe holding lib/<name> for each name after $1,
# with a fake nproc and a fake shellcheck, then checks that the gate made its
# scratch under $LINT_TMP and removed it. The gate takes nproc's 2 as its job
# count whatever the host's CPUs. The fake notes the gate's scratch when it sees
# it, appends the base name of the file it is asked to check to
# $LINT_FAKE/calls, runs the sh case branches in $1 on that name, and exits 0
# unless a branch ends it first; DEVBIN_FAKESC names that directory to it. Both
# paths are set here, for the arms to read.
_lint_with_fake() {
  local branches="$1" probe="$DEVBIN_TEST_TMPDIR/lintprobe" name
  shift
  LINT_FAKE="$DEVBIN_TEST_TMPDIR/fakesc" LINT_TMP="$DEVBIN_TEST_TMPDIR/linttmp"
  mkdir -p "$probe/lib" "$probe/bin" "$probe/tests" "$LINT_TMP" "$LINT_FAKE"
  for name in "$@"; do
    printf '#!/usr/bin/env bash\nprintf %s\n' "$name" >"$probe/lib/$name"
  done
  printf '#!/bin/sh\necho 2\n' >"$LINT_FAKE/nproc"
  # shellcheck disable=SC2016 # the fake expands these, not this shell
  printf '#!/bin/sh\nfor d in "$TMPDIR"/devbin-lint.*; do [ ! -d "$d" ] || : >"$DEVBIN_FAKESC/scratch-seen"; done\nf="${2##*/}"\necho "$f" >>"$DEVBIN_FAKESC/calls"\ncase "$f" in\n%s\nesac\nexit 0\n' "$branches" >"$LINT_FAKE/shellcheck"
  chmod +x "$LINT_FAKE/nproc" "$LINT_FAKE/shellcheck"
  run env PATH="$LINT_FAKE:$PATH" DEVBIN_FAKESC="$LINT_FAKE" TMPDIR="$LINT_TMP" PROJECT_ROOT="$probe" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$DEVBIN_HOME/bin/.devbin/cmd/.lib/shell-gate" lint
  [ -e "$LINT_FAKE/scratch-seen" ] || fail "the gate's scratch was never under $LINT_TMP, so its removal shows nothing"
  [ -d "$LINT_TMP" ] && [ -z "$(ls -A "$LINT_TMP")" ] || fail "the gate left its scratch behind: $(ls -A "$LINT_TMP" 2>&1)"
}

# _lint_rechecked_are [<name>...] -- the gate checked alone exactly these files
# of the probe, lib/<name>, each said on its own line, and no other. It reads
# the line's fixed end, "the parallel run; checked", whatever it said the
# parallel run gave the file.
_lint_rechecked_are() {
  local got want=""
  got="$(sed -n 's/^.*lint: lib\/\([^ ]*\) .*the parallel run; checked .*$/\1/p' <<<"$output" | LC_ALL=C sort | tr '\n' ' ')"
  [ "$#" -eq 0 ] || want="$(printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' ')"
  [ "$got" = "$want" ] || fail "the files checked alone were [${got% }], not [${want% }]"
}

# _lint_files -- how many files the lint probe holds, which is how many the gate
# lints: every file a lint arm plants under it is a shell script.
_lint_files() { find "$DEVBIN_TEST_TMPDIR/lintprobe" -type f | grep -c .; }

# _lint_calls_are <name>:<count>... -- the fake was asked to check lib/<name>
# exactly <count> times, for each pair.
_lint_calls_are() {
  local pair
  for pair in "$@"; do
    [ "$(grep -cxF "${pair%%:*}" "$LINT_FAKE/calls")" = "${pair#*:}" ] ||
      fail "lib/${pair%%:*} was not checked ${pair#*:} time(s): $(tr '\n' ' ' <"$LINT_FAKE/calls")"
  done
}

# Runs the lint gate through _lint_with_fake over lib/clean, lib/dies and any
# names after $1. EVERY ARM THAT USES IT RESTS ON THE TWO CHECKS OVERLAPPING, so
# the overlap is made and then checked (at one job neither arm could see a gate
# stop waiting). Every check of lib/dies pulls the lever, $1, then marks it
# pulled and exits 1. lib/clean's check waits for that mark, for up to a hundred
# tenth-of-a-second polls, and a second more before the real shellcheck runs, so
# it is still going when the lever has fired. A mark that never came leaves a
# file the helper fails on, which holds however the gate prints a passing file's
# output, and a line in that output saying why; the mark itself must be there,
# so that check can never pass by reading nothing. run returns only once
# lib/clean's worker has exited, since it holds run's capture as its stderr.
_lint_with_lever() {
  local lever="$1" real branches
  shift
  require_command shellcheck "shellcheck is not installed -- the lint gate was NOT run"
  real="$(command -v shellcheck)"
  # shellcheck disable=SC2016 # the fake expands these, not this shell
  printf -v branches 'dies) %s; : >"$DEVBIN_FAKESC/lever-pulled"; exit 1 ;;\nclean)\n  i=0\n  while [ ! -e "$DEVBIN_FAKESC/lever-pulled" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done\n  [ -e "$DEVBIN_FAKESC/lever-pulled" ] || { : >"$DEVBIN_FAKESC/no-overlap"; echo "fake shellcheck: lib/clean was not being checked when the lever was pulled"; }\n  sleep 1\n  exec "%s" "$@"\n  ;;' "$lever" "$real"
  _lint_with_fake "$branches" clean dies "$@"
  [ -e "$LINT_FAKE/lever-pulled" ] || fail "the lever never fired: no check of lib/dies pulled it"
  [ ! -e "$LINT_FAKE/no-overlap" ] || fail "the two checks did not overlap: lib/clean was not being checked when the lever was pulled"
}

@test "a lint worker that dies is named as a file with no verdict once its second run gives it none either, the summary still prints, every file still being checked keeps its verdict whatever the xargs, and nothing is left behind (0155, 0180, 0184)" {
  # xargs aborts when a worker dies, and under errexit that ended the gate before
  # it read a verdict back: breaches went unnamed and the scratch stayed.
  #
  # AND THE OTHER FILES' VERDICTS DEPENDED ON THE RUNNER'S XARGS (issue 0180).
  # GNU xargs 4.9.0 exits at a worker killed by a signal without waiting for the
  # workers still running, so on the Ubuntu runner lib/clean lost its verdict
  # and its worker wrote after the gate had finished. BSD xargs and GNU 4.11.0
  # wait, so this arm cannot go red on them; the next arm takes xargs away
  # itself, and goes red wherever the gate stops waiting when xargs does, macOS
  # included. The lever is the fake's parent, the worker xargs started.
  #
  # AND A FILE LEFT WITH NO VERDICT IS CHECKED AGAIN ALONE (issue 0184). The
  # lever fires on every check of lib/dies, so its second run dies as well, and
  # the arm reads that result: still no verdict, a breach. lib/clean is never
  # checked again, which is what shows it kept the verdict the parallel run gave
  # it: a gate that stopped waiting would check it again and pass it. The files
  # checked alone and the call count turn this arm red for such a gate whatever
  # the timing; the refute of a status written after the gate fires only when
  # lib/clean's late worker outlives the gate's second runs, which is a race.
  # shellcheck disable=SC2016 # the fake expands $PPID, not this shell
  _lint_with_lever 'kill -9 $PPID'
  assert_failure
  assert_output_contains "lint: lib/dies had no verdict from the parallel run; checked again alone: no verdict"
  _lint_rechecked_are dies
  assert_output_contains "lint: $(_lint_files) file(s), 1 breach(es)"
  # The worker died, not some other process: xargs says so in its own words,
  # BSD's "terminated with signal 9" and GNU's "terminated by signal 9", and the
  # gate says each run exited non-zero. And nothing wrote after the gate had
  # finished: a status file written into a scratch already gone fails in dash's
  # words or bash's.
  assert_output_matches 'terminated (by|with) signal 9'
  assert_output_matches 'the parallel run exited [1-9]'
  assert_output_matches 'the run of lib/dies alone exited [1-9]'
  refute_output_matches '\.rc: (Directory nonexistent|No such file or directory)'
  _lint_calls_are clean:1 dies:2
}

@test "a lint run whose xargs is gone before its workers finish still waits for every worker's verdict, and nothing writes after the gate (0180, 0184)" {
  # An xargs that exits without waiting for its workers is what GNU xargs 4.9.0
  # does at a worker killed by a signal, and the gate read back before they had
  # finished (issue 0180). Killing xargs itself does the same on every
  # platform, so this arm goes red wherever the gate stops waiting when xargs
  # does, macOS included. The lever is the fake's parent's parent, xargs, found
  # with ps. lib/clean's verdict is what shows the wait: its check is still
  # going when xargs goes, and a gate that stopped waiting would check it alone
  # and pass it (issue 0184), so the arm asserts that no file was checked
  # alone. lib/dies's worker outlives xargs and records the fake's exit, 1,
  # within moments of the lever, so its lines show only that the lever took
  # xargs and nothing else; a check that fails on its own terms is never run
  # again.
  require_command ps "ps is not installed -- the gate was NOT run without its xargs"
  # shellcheck disable=SC2016 # the fake expands $PPID, not this shell, and splits ps's padded pid on purpose
  _lint_with_lever 'kill -9 $(ps -o ppid= -p $PPID)'
  assert_failure
  # bash's status for an xargs killed by signal 9: the lever reached xargs.
  assert_output_matches 'the parallel run exited 137'
  _lint_rechecked_are
  assert_output_contains "lint: lib/dies exited 1 with no output"
  assert_output_contains "lint: $(_lint_files) file(s), 1 breach(es)"
  refute_output_matches '\.rc: (Directory nonexistent|No such file or directory)'
  _lint_calls_are clean:1 dies:1
}

@test "a file the parallel run never started, once a worker dies, is checked alone, and a pass then is no breach (0155, 0184)" {
  # A worker killed by a signal stops xargs starting anything more: BSD xargs
  # aborts and GNU stops starting work. At two jobs, with lib/clean's check
  # waiting and lib/dies's worker killed by the lever, lib/third is never
  # started, so it had no verdict and was a breach with nothing behind it.
  # Now it is checked alone, and said as a file the parallel run never checked.
  # shellcheck disable=SC2016 # the fake expands $PPID, not this shell
  _lint_with_lever 'kill -9 $PPID' third
  assert_failure
  assert_output_contains "lint: lib/third was not checked in the parallel run; checked alone: ok"
  assert_output_contains "lint: lib/dies had no verdict from the parallel run; checked again alone: no verdict"
  _lint_rechecked_are dies third
  assert_output_contains "lint: $(_lint_files) file(s), 1 breach(es)"
  # xargs stopped at the dead worker, in its own words, which is why lib/third
  # never started, and the gate said the parallel run failed.
  assert_output_matches 'terminated (by|with) signal 9'
  assert_output_matches 'the parallel run exited [1-9]'
  _lint_calls_are clean:1 dies:2 third:1
}

@test "a lint check killed in the parallel run is checked again alone once every other check is done, and a pass then is no breach, said with both runs' results (0184)" {
  # The parallel run is sized by CPUs and never by memory, so a host short of
  # memory has checks killed, and each was a breach with no defect behind it
  # (issue 0184). Two checks are killed here while lib/clean's is running, which
  # the fake makes so and checks: lib/killed1's by SIGKILL, as the kernel kills,
  # and lib/killed2's by SIGTERM, since any status above 128 counts. Each second
  # run passes. It marks itself busy for half a second, looking for any other
  # busy check as it starts and as it ends, and every check that marks itself
  # busy lasts at least that long (lib/clean's a second, a second run's half a
  # second), so any overlap is seen from one side. What a killed check printed
  # is never shown, and what its second run printed is.
  # shellcheck disable=SC2016 # the fake expands these, not this shell
  _lint_with_fake '
clean)
  : >"$DEVBIN_FAKESC/busy.clean"
  i=0
  while { [ ! -e "$DEVBIN_FAKESC/once.killed1" ] || [ ! -e "$DEVBIN_FAKESC/once.killed2" ]; } && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 1
  rm -f "$DEVBIN_FAKESC/busy.clean"
  ;;
killed1 | killed2)
  if [ ! -e "$DEVBIN_FAKESC/once.$f" ]; then
    i=0
    while [ ! -e "$DEVBIN_FAKESC/busy.clean" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    [ -e "$DEVBIN_FAKESC/busy.clean" ] || : >"$DEVBIN_FAKESC/no-overlap"
    : >"$DEVBIN_FAKESC/once.$f"
    echo "first run of $f"
    case "$f" in killed1) kill -9 $$ ;; *) kill -15 $$ ;; esac
  fi
  for b in "$DEVBIN_FAKESC"/busy.*; do [ ! -e "$b" ] || : >"$DEVBIN_FAKESC/not-alone"; done
  : >"$DEVBIN_FAKESC/busy.$f"
  sleep 0.5
  for b in "$DEVBIN_FAKESC"/busy.*; do [ "$b" = "$DEVBIN_FAKESC/busy.$f" ] || : >"$DEVBIN_FAKESC/not-alone"; done
  rm -f "$DEVBIN_FAKESC/busy.$f"
  echo "second run of $f"
  ;;' clean killed1 killed2
  [ ! -e "$LINT_FAKE/no-overlap" ] || fail "the killed checks did not overlap lib/clean's in the parallel run"
  [ ! -e "$LINT_FAKE/not-alone" ] || fail "a second run was not alone: another check was running beside it"
  assert_success
  assert_output_contains "lint: lib/killed1 exited 137 in the parallel run; checked again alone: ok"
  assert_output_contains "lint: lib/killed2 exited 143 in the parallel run; checked again alone: ok"
  assert_output_contains "lint: $(_lint_files) file(s), 0 breach(es)"
  refute_output_contains "first run of"
  assert_output_contains "second run of killed1"
  assert_output_contains "second run of killed2"
  _lint_rechecked_are killed1 killed2
  # Each killed file was checked twice and lib/clean once. Only the checks were
  # killed, never a worker, so xargs did not fail.
  _lint_calls_are clean:1 killed1:2 killed2:2
  refute_output_contains "the parallel run exited"
}

@test "a lint check killed again when checked alone is a breach, and one that fails on its own terms is never checked again (0184)" {
  # lib/killed is killed in the parallel run, by SIGKILL, and again in its second
  # run, by SIGTERM: a breach, and the line gives both statuses, so the second is
  # read from the second run. lib/bad fails on its own terms, status 1, which no
  # second run could change: it is checked once and its finding printed once.
  # The plants a breach is expected of, beside lib/clean, which passes.
  local -a breaching=(bad killed)
  # shellcheck disable=SC2016 # the fake expands these, not this shell
  _lint_with_fake '
bad)
  echo "lib/bad:2:1: a finding the fake planted"
  exit 1
  ;;
killed)
  [ -e "$DEVBIN_FAKESC/once.killed" ] || { : >"$DEVBIN_FAKESC/once.killed"; kill -9 $$; }
  kill -15 $$
  ;;' "${breaching[@]}" clean
  assert_failure
  assert_output_contains "lint: lib/killed exited 137 in the parallel run; checked again alone: exited 143"
  _lint_rechecked_are killed
  [ "$(grep -cF 'a finding the fake planted' <<<"$output")" = 1 ] || fail "lib/bad's finding was not printed exactly once"
  assert_output_contains "lint: $(_lint_files) file(s), ${#breaching[@]} breach(es)"
  _lint_calls_are bad:1 clean:1 killed:2
}
