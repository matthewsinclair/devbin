#!/usr/bin/env bats
# harness.bats - the test harness tests itself
#
# Every later WP writes its tests against test_helper.bash, so a silent defect
# here -- a fixture that is not created, a teardown that does not clean, an
# assertion that passes on anything -- would make every downstream suite report
# green for the wrong reason. These tests exist so the harness cannot be the
# thing that lies.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# ============================================================================
# ENVIRONMENT
# ============================================================================

@test "assert_find_denied reads each form find prints its error in: BSD's, GNU's in the C locale, and GNU's under UTF-8 (0139)" {
  # GNU find quotes the path by locale, and under UTF-8 -- CI's -- with U+2018
  # and U+2019, which the two-form check this helper replaced could not match
  # (measured with GNU findutils 4.11.0). No find on this machine may print the
  # third form, so the forms are given here, not produced.
  local lq=$'\xe2\x80\x98' rq=$'\xe2\x80\x99'
  local form
  for form in "find: /x/y/locked: Permission denied" \
    "find: '/x/y/locked': Permission denied" \
    "find: ${lq}/x/y/locked${rq}: Permission denied"; do
    output="$form"
    assert_find_denied "/x/y/locked"
    assert_find_denied "locked"
  done
  # THE NEGATIVE: another path, and another error, are not this one.
  output="find: ${lq}/x/y/other${rq}: Permission denied"
  run assert_find_denied "/x/y/locked"
  [ "$status" -ne 0 ] || fail "assert_find_denied matched a different path"
  output="find: ${lq}/x/y/locked${rq}: No such file or directory"
  run assert_find_denied "/x/y/locked"
  [ "$status" -ne 0 ] || fail "assert_find_denied matched a different error"
  # And a trailing part names only its own path: locked is not unlocked.
  for form in "find: /x/y/unlocked: Permission denied" "find: ${lq}/x/y/unlocked${rq}: Permission denied"; do
    output="$form"
    run assert_find_denied "locked"
    [ "$status" -ne 0 ] || fail "assert_find_denied took unlocked for locked: $form"
  done
  # Nor is a space inside a name a separator: dir/locked is not "my dir/locked".
  output="find: /x/my dir/locked: Permission denied"
  run assert_find_denied "dir/locked"
  [ "$status" -ne 0 ] || fail "assert_find_denied took a space inside a name for a separator"
}

@test "assert_find_denied reads the error GNU find itself prints under a UTF-8 locale (0139)" {
  # The arm above GIVES GNU's UTF-8 form, since BSD find cannot print it. Where
  # GNU find is on the runner -- find on Linux, gfind from Homebrew on macOS --
  # the form is PRODUCED, so the fold is held against the tool and not only
  # against text.
  local gnu="" f loc d="$DEVBIN_TEST_TMPDIR/g" ver
  for f in gfind find; do
    if command -v "$f" >/dev/null 2>&1 && ver="$("$f" --version 2>/dev/null)" && grep -q 'GNU findutils' <<<"$ver"; then
      gnu="$f"
      break
    fi
  done
  [ -n "$gnu" ] || skip "no GNU find on this runner: its UTF-8 error was NOT produced"
  loc="$(utf8_locale)" || skip "no UTF-8 locale on this runner: GNU's UTF-8 error was NOT produced"
  mkdir -p "$d/locked"
  chmod 000 "$d/locked"
  if [ -r "$d/locked" ]; then
    chmod 755 "$d/locked"
    skip "running with permissions that read a mode-000 directory: the error was NOT produced"
  fi
  if output="$(LC_ALL="$loc" "$gnu" "$d" 2>&1 >/dev/null)"; then
    chmod 755 "$d/locked"
    fail "GNU find exited 0 over a mode-000 directory: $output"
  fi
  chmod 755 "$d/locked"
  # THE CONTROL: the produced text carries the quote the fold exists for.
  [[ "$output" == *$'\xe2\x80\x98'* ]] || skip "$gnu under $loc printed no U+2018: the fold was NOT exercised ($output)"
  assert_find_denied "$d/locked"
}

@test "refute_digest_line refuses a line of twelve hex digits, and passes a digest inside a line (0139)" {
  # A check for absence needs a positive control, or a pattern that can never
  # match passes every arm that uses it.
  run refute_digest_line $'x\n0123456789ab\ny'
  [ "$status" -ne 0 ] || fail "refute_digest_line passed over a digest line"
  run refute_digest_line "0123456789ab" "when given alone"
  [ "$status" -ne 0 ] || fail "refute_digest_line passed over a digest given alone"
  assert_output_contains "a runtime digest was printed when given alone"
  run refute_digest_line $'runtime 0123456789ab\n0123456789abc\n0123456789a'
  [ "$status" -eq 0 ] || fail "refute_digest_line took a digest inside a line, or 13 or 11 digits, for a digest line: $output"
}

@test "DEVBIN_HOME points at the checkout under test" {
  assert_file_exists "$DEVBIN_HOME/tests/lib/test_helper.bash"
  assert_file_exists "$DEVBIN_HOME/lib/helpers"
}

@test "colour and terminal formatting are disabled for determinism" {
  [ "$NO_COLOR" = 1 ]
  [ "$TERM" = dumb ]
}

@test "the suite reads no global or system git config, as CI's runner has none" {
  [ "$GIT_CONFIG_GLOBAL" = /dev/null ] || fail "GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-unset}'"
  [ "$GIT_CONFIG_NOSYSTEM" = 1 ] || fail "GIT_CONFIG_NOSYSTEM is '${GIT_CONFIG_NOSYSTEM:-unset}'"
  run git config --get init.defaultBranch
  [ -z "$output" ] || fail "init.defaultBranch reaches the suite as '$output' -- the operator's config covers for a fixture CI would catch"
}

@test "a TMPDIR inside a git checkout is refused by name, and one outside is not -- the control" {
  local repo="$DEVBIN_TEST_TMPDIR/repo" plain="$DEVBIN_TEST_TMPDIR/plain"
  git init -q "$repo"
  mkdir -p "$plain"
  run env -u DEVBIN_HOME TMPDIR="$repo" bats "$DEVBIN_HOME/tests/fixtures/harness/probe.bats"
  assert_failure
  assert_output_contains "TMPDIR is inside a git checkout"
  run env -u DEVBIN_HOME TMPDIR="$plain" bats "$DEVBIN_HOME/tests/fixtures/harness/probe.bats"
  assert_success
}

@test "a file whose test writes into the fixture cache fails at teardown_file, by name (0192)" {
  run bats "$DEVBIN_HOME/tests/fixtures/harness/cachetamper.bats"
  assert_failure
  assert_output_contains "changed while this file ran"
}

@test "a file whose test removes the fixture cache fails at teardown_file, by name (0192)" {
  run bats "$DEVBIN_HOME/tests/fixtures/harness/cachegone.bats"
  assert_failure
  assert_output_contains "the fixture cache at"
  assert_output_contains "is gone"
}

@test "a plain write into the fixture cache is refused where it is made (0192)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which writes past a missing write bit: only teardown_file's sum guards the cache there"
  run sh -c 'printf x >"$1/bin/.devbin/lib/written"' _ "$DEVBIN_FIXTURE_CACHE"
  assert_failure
  assert_file_not_exists "$DEVBIN_FIXTURE_CACHE/bin/.devbin/lib/written"
}

@test "a copied fixture is a real install of the same source, path, byte and mode, under umask 022 and 002 (0192)" {
  local m
  for m in 022 002; do
    run bash -c 'umask "$1" && bats "$2"' _ "$m" "$DEVBIN_HOME/tests/fixtures/harness/cachemodes.bats"
    [ "$status" -eq 0 ] || fail "under umask $m:
$output"
  done
}

@test "a test that changes its fixture's install leaves the next test's fixture the fresh install's (0192)" {
  local fx="$DEVBIN_HOME/tests/fixtures/harness/cacheleak.bats" name pos
  name="the next test's fixture is the fresh install's, file for file"
  # Its place in the fixture, read off the fixture's own @test lines.
  pos="$(grep '^@test ' "$fx" | grep -n -F "$name" | cut -d: -f1)"
  [ -n "$pos" ] || fail "the fixture holds no test named: $name"
  run bats "$fx"
  assert_success
  assert_output_contains "ok $pos $name"
}

@test "break_git_index cuts the repository's own index, whatever GIT_INDEX_FILE names (0186)" {
  # A commit hook exports GIT_INDEX_FILE. Read through it, the guard's two halves
  # asked another index than the one cut, and every arm built on the cut would
  # fail by name though the cut was made.
  local repo="$DEVBIN_TEST_TMPDIR/repo" other="$DEVBIN_TEST_TMPDIR/other.index"
  git init -q "$repo"
  printf 'x\n' >"$repo/a.txt"
  git -C "$repo" add a.txt
  cp "$repo/.git/index" "$other"
  GIT_INDEX_FILE="$other" run break_git_index "$repo"
  assert_success
  [ ! -s "$repo/.git/index" ] || fail "the repository's own index was not cut"
  [ -s "$other" ] || fail "the index GIT_INDEX_FILE names was cut"
}

# ============================================================================
# ISOLATION
# ============================================================================

@test "devbin_setup creates a private temp dir and cds into it" {
  [ -n "$DEVBIN_TEST_TMPDIR" ]
  assert_directory_exists "$DEVBIN_TEST_TMPDIR"
  [ "$PWD" = "$DEVBIN_TEST_TMPDIR" ]
}

@test "the temp dir is outside the checkout" {
  case "$DEVBIN_TEST_TMPDIR" in
    "$DEVBIN_HOME"*) fail "temp dir ($DEVBIN_TEST_TMPDIR) is inside the repo -- would pollute git status" ;;
  esac
}

@test "devbin_teardown refuses an unexpected temp path" {
  mkdir -p "$DEVBIN_TEST_TMPDIR/keepme"
  saved="$DEVBIN_TEST_TMPDIR"
  DEVBIN_TEST_TMPDIR="$saved/keepme"
  run devbin_teardown
  assert_success
  assert_output_contains "refusing to remove unexpected"
  assert_directory_exists "$saved/keepme"
  DEVBIN_TEST_TMPDIR="$saved"
}

# ============================================================================
# FIXTURES
# ============================================================================

@test "create_test_project builds the devbin install layout" {
  proj="$(create_test_project demo)"
  assert_file_exists "$proj/bin/.devbin/config.yaml"
  assert_directory_exists "$proj/bin/.devbin/cmd"
  assert_directory_exists "$proj/bin/.devbin/help"
  assert_file_contains "$proj/bin/.devbin/config.yaml" "name: demo"
}

@test "fixture projects are independent of each other" {
  a="$(create_test_project one)"
  b="$(create_test_project two)"
  [ "$a" != "$b" ]
  assert_file_contains "$a/bin/.devbin/config.yaml" "name: one"
  assert_file_contains "$b/bin/.devbin/config.yaml" "name: two"
  refute_file_contains "$b/bin/.devbin/config.yaml" "name: one"
}

@test "create_test_command writes an executable handler reporting name and args" {
  proj="$(create_test_project demo)"
  path="$(create_test_command "$proj" greet)"
  assert_executable "$path"
  run "$path" alpha beta
  assert_success
  assert_output "ran:greet args:alpha beta"
}

@test "create_test_command honours a custom body" {
  proj="$(create_test_project demo)"
  path="$(create_test_command "$proj" custom '#!/usr/bin/env bash
printf "bespoke\n"')"
  run "$path"
  assert_success
  assert_output "bespoke"
}

@test "write_config replaces the fixture config from stdin" {
  proj="$(create_test_project demo)"
  write_config "$proj" <<'YAML'
project:
  name: replaced
  alias: rp
YAML
  assert_file_contains "$proj/bin/.devbin/config.yaml" "name: replaced"
  refute_file_contains "$proj/bin/.devbin/config.yaml" "name: demo"
}

@test "install_devbin is a no-op while the dispatcher does not exist" {
  proj="$(create_test_project demo)"
  run install_devbin "$proj"
  assert_success
  if [ ! -x "$DEVBIN_BIN_DIR/devbin" ]; then
    assert_file_not_exists "$proj/bin/devbin"
  fi
}

# ============================================================================
# ASSERTIONS
# ============================================================================

@test "assert_success and assert_failure read the exit code" {
  run true
  assert_success
  run bash -c 'exit 1'
  assert_failure
}

@test "assert_exit_code discriminates between failure codes" {
  run bash -c 'exit 3'
  assert_exit_code 3
  refute_assertion assert_exit_code 2
}

@test "output assertions discriminate" {
  run printf 'hello world'
  assert_output_contains "lo wo"
  assert_output "hello world"
  assert_output_matches "^hello"
  refute_output_contains "goodbye"
  refute_assertion assert_output_contains "goodbye"
  refute_assertion assert_output "wrong"
}

@test "file assertions discriminate" {
  : >empty.errors
  printf 'boom\n' >full.errors
  assert_file_exists empty.errors
  assert_file_not_exists nope.errors
  assert_file_empty empty.errors
  refute_assertion assert_file_empty full.errors
  assert_file_contains full.errors "boom"
  refute_file_contains full.errors "quiet"
  refute_assertion assert_file_exists nope.errors
  refute_assertion assert_file_contains full.errors "quiet"
}

@test "assert_symlink_exists checks the target when given one" {
  printf 'x\n' >target
  ln -s target link
  assert_symlink_exists link
  assert_symlink_exists link target
  refute_assertion assert_symlink_exists link elsewhere
  refute_assertion assert_symlink_exists target
}

@test "refute_assertion fails when the assertion actually passes" {
  : >real.file
  run refute_assertion assert_file_exists real.file
  assert_failure
  assert_output_contains "Expected assertion to FAIL but it passed"
}

# ============================================================================
# UTILITIES
# ============================================================================

@test "command_exists finds a real command and rejects a fake one" {
  command_exists bash
  ! command_exists definitely-not-a-real-command-xyz
}

@test "require_command skips rather than fails when a tool is absent OFF a CI runner" {
  # A developer's laptop is not the project's to provision, so an arm that
  # cannot run there declares itself rather than failing on noise they cannot
  # act on. CI is unset explicitly: this arm asserts the DEVELOPER branch, and
  # inheriting a set CI from the environment would silently test the other one.
  unset CI
  require_command definitely-not-a-real-command-xyz "expected skip"
  fail "should have skipped before reaching here"
}

@test "require_command FAILS under CI, because a skip there is a coverage hole" {
  # THE ARM THAT MAKES A PAST CI BREAK UNREPEATABLE. A batch of arms went red
  # on Ubuntu for uninstalled tools; a skip would have made that run GREEN with
  # those arms silently removed from the population. On a runner the
  # project controls, an absent tool is a missing apt line and never a fact
  # about the world.
  #
  # This is also what stops the fix rotting: delete the apt line from the
  # workflow and CI goes red naming the tool, instead of quietly reverting to
  # skips that read as passes.
  CI=true run require_command definitely-not-a-real-command-xyz
  assert_failure
  assert_output_contains "not installed on this CI runner"
  assert_output_contains "tests.yml"
}

@test "require_command skips under CI only when the call names the rule that keeps the tool off CI" {
  # THE EXEMPTION IS A RULE THE CALL CARRIES, never an absence: the arm above
  # proves a call without one fails under CI. A tool the project decided not to
  # install there (prettier) would otherwise turn every CI run red on a decision
  # rather than a defect.
  CI=true require_command definitely-not-a-real-command-xyz "expected skip" "a rule"
  fail "should have skipped before reaching here"
}

@test "no test name contains a backtick or a command substitution" {
  # bats EVALS every test description to resolve variable references in it
  # (bats_test_function, test_functions.bash), which makes a name containing
  # backticks or $(...) executable. `the exit code of a failing option survives
  # \`all\`` therefore ran `all` on every test in its file and printed
  # "all: command not found" to stderr, once per test, indefinitely.
  #
  # It survived a long time because the noise goes to stderr while the TAP line
  # still reads `ok`, so any summary that greps for ^ok / ^not ok -- which is
  # the natural way to read a full run -- shows a clean suite.
  #
  # Structural rather than behavioural: the claim is about how the names are
  # written, and no behavioural test can catch a name that has not been written
  # yet. Same shape as the lib/cmd header test and the thin-dispatcher one.
  run grep -rn '^@test .*[`$]' "$DEVBIN_HOME/tests/unit"
  if [[ "$status" -eq 0 ]]; then
    fail "test names must not contain backticks or \$: bats evals them.\n$output"
    return 1
  fi
}

@test "no output assertion is passed a bare end-of-options marker" {
  # The output helpers read $1 DIRECTLY -- they take a substring or a regex, not
  # option-style arguments -- so a defensive `--` before a pattern beginning with
  # a dash does not protect it. It BECOMES the pattern.
  #
  # A contains-assertion written with that marker ahead of "--iex" therefore
  # asserted that the output contains the marker itself, which every listing
  # does: the first line is `demo -- dev launcher`. (The example is described
  # rather than written out, because this test greps the tree it lives in and
  # would otherwise match its own comment -- the same trap as a prose line
  # beginning with the word shellcheck.) Three assertions were disarmed, including
  # the test that was supposed to prove a framework option gets listed, and all
  # three passed for a long time while checking nothing. Two of them
  # were found only because a fourth, written the same way, refuted `--` and
  # failed for a reason that had nothing to do with what it asserted.
  #
  # Structural for the same reason as the test above: no behavioural test can
  # catch the next one, because the assertion still passes.
  run grep -rn -E '(assert|refute)_output_(contains|matches|equals)[[:space:]]+--[[:space:]]' \
    "$DEVBIN_HOME/tests/unit"
  if [[ "$status" -eq 0 ]]; then
    fail "output helpers read \$1 directly; a bare -- becomes the pattern.\n$output"
    return 1
  fi
}

@test "no test file builds a Homebrew keg except through brew_keg, the one keg builder (0270)" {
  # Four files each built a keg their own way, so a change to the formula's
  # layout had to be followed in each, and a builder that missed one tested a
  # layout no formula writes: 0266's keg bin/devbin left env_script_keg writing
  # its script through that link, over libexec's launcher. Every keg now comes
  # from brew_keg (tests/lib/test_helper.bash), and this holds it there.
  #
  # A KEG WRITE, read on each line that is not a comment or a test's name, with
  # each $name and ${name} replaced by the value the line's own test or function
  # assigns it, or the file's setup does, so a write through $keg or $KEG is
  # read by the path it holds: a mkdir, ln, cp, mv, install or tee, a --prefix,
  # or a redirection, naming Cellar/devbin or HOMEBREW_PREFIX's opt, bin/devbin
  # or Cellar, however HOMEBREW_PREFIX is spelt; a link to ../libexec/bin/devbin,
  # the keg's own bin/devbin, wherever it is made; and a publish marked
  # --managed-by brew, unless the prefix it names is under the test's own
  # DEVBIN_TEST_TMPDIR, as localinstall.bats' arms that test the mark itself
  # publish into $DEVBIN_TEST_TMPDIR/keg, which no reader takes for a keg.
  #
  # The allowed hits are brew_keg's own lines, read from its definition, and
  # some must be found, so the scan is known to see the builder it protects.
  # WHAT THIS DOES NOT CATCH: a path held in a variable assigned anywhere but
  # the line's own test or function or the file's setup, a function argument
  # ($1) or a command substitution among them; a write by a command not named
  # above, or by a helper of another name that takes the keg's path as an
  # argument; and a keg laid out under a prefix other than HOMEBREW_PREFIX.
  local helper="$DEVBIN_HOME/tests/lib/test_helper.bash" span hit file rest n own=0 others=""
  span="$(awk '/^brew_keg(_env_script)?\(\) \{$/ { on = 1 } on { print NR } on && /^}$/ { on = 0 }' "$helper")"
  run awk '
    function expand(s, pass, out, m, nm) {
      for (pass = 0; pass < 2; pass++) {
        out = ""
        while (match(s, /[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?/)) {
          m = substr(s, RSTART, RLENGTH)
          nm = m
          gsub(/[^A-Za-z0-9_]/, "", nm)
          out = out substr(s, 1, RSTART - 1)
          if (nm in blk) out = out blk[nm]
          else if (nm in top) out = out top[nm]
          else out = out substr(m, 2)
          s = substr(s, RSTART + RLENGTH)
        }
        s = out s
      }
      return s
    }
    function assigns(s, nm) {
      while (match(s, /[A-Za-z_][A-Za-z0-9_]*="[^"]*"/)) {
        nm = substr(s, RSTART, RLENGTH)
        sub(/=.*/, "", nm)
        if (insetup) top[nm] = substr(s, RSTART + length(nm) + 2, RLENGTH - length(nm) - 3)
        else blk[nm] = substr(s, RSTART + length(nm) + 2, RLENGTH - length(nm) - 3)
        s = substr(s, RSTART + RLENGTH)
      }
    }
    BEGIN {
      kp = "(Cellar/devbin|HOMEBREW_PREFIX[}\"]*/(opt|bin/devbin|Cellar))"
      verb = "(^|[;&|({]|then|do)[[:space:]]*(mkdir|ln|cp|mv|install|tee)[[:space:]].*" kp
      prefix = "--prefix[= ]+\"?[^ ]*" kp
      redir = ">[[:space:]]*\"?[^ ]*" kp
      ownprefix = "--prefix[= ]+\"?[$]?[{]?DEVBIN_TEST_TMPDIR[}]?/"
    }
    FNR == 1 { split("", top); split("", blk); insetup = 0 }
    /^[[:space:]]*#/ || /^@test / { if (/^@test /) { split("", blk); insetup = 0 } next }
    /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { split("", blk); insetup = /^setup(_file)?\(\)/ }
    {
      assigns($0)
      x = expand($0)
      if (x ~ verb || x ~ prefix || x ~ redir || x ~ /ln -s[fn]* [^ ]*\.\.\/libexec\/bin\/devbin/ ||
        (x ~ /--managed-by[ ]brew/ && x ~ /--prefix/ && x !~ ownprefix))
        print FILENAME ":" FNR ":" $0
    }
  ' "$DEVBIN_HOME"/tests/unit/*.bats "$DEVBIN_HOME"/tests/lib/*.bash
  [ "$status" -eq 0 ] || fail "the scan could not read the tests: $output"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}" rest="${hit#*:}"
    n="${rest%%:*}"
    if [ "$file" = "$helper" ] && grep -qxF "$n" <<<"$span"; then
      own=$((own + 1))
    else
      printf -v hit "%s\n" "$hit"
      others+="$hit"
    fi
  done <<<"$output"
  if [ -n "$others" ]; then
    # Printed as it was read: fail reads its message through %b, and a test line
    # carries backslashes of its own.
    printf "FAILURE: a keg built outside brew_keg:\n%s" "$others" >&2
    return 1
  fi
  [ "$own" -gt 0 ] || fail "the scan read none of brew_keg's own lines, so it sees no keg being built: $output"
}
