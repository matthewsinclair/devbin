#!/usr/bin/env bats
# testscans.bats - `test scans`, devbin's own tree scans alone (0357)
#
# A tree scan is an arm whose verdict is over a set of this tree's own files
# found by walking it, so a change anywhere can turn one red, whatever file the
# change was in. Each carries the tag `treescan`, and `bin/devbin test scans`
# runs them alone, through devbin's own test handler, bin/.devbin/cmd/test. The
# arms run the handler for real over a fixture suite of their own; `all` keeps
# the option out, since `test all` runs every tagged arm in place.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# scans_root <line>... -- a fixture root whose tests/unit/a.bats holds these
# lines, built with printf, since bats reads a heredoc's lines as its own.
scans_root() {
  local root="$DEVBIN_TEST_TMPDIR/root"
  mkdir -p "$root/tests/unit"
  printf '%s\n' '#!/usr/bin/env bats' "$@" >"$root/tests/unit/a.bats"
  printf '%s\n' "$root"
}

# scans_run <root> [<arg>...] -- devbin's test handler, `test scans`, run for
# real at <root>.
scans_run() {
  local root="$1"
  shift
  (cd "$root" && DEVBIN_LIB="$DEVBIN_LIB_DIR" PROJECT_ROOT="$root" bash "$DEVBIN_HOME/bin/.devbin/cmd/test" scans "$@" </dev/null)
}

# scans_seal <root> -- the run's .errors companion, the verdict a sealed gate
# writes, empty only for a completed green run.
scans_seal() {
  local -a seals
  shopt -s nullglob
  seals=("$1"/tmp/test/2*.bats.errors)
  shopt -u nullglob
  [ "${#seals[@]}" -eq 1 ] || fail "the run left ${#seals[@]} bats seal(s) under tmp/test, not one"
  printf '%s\n' "${seals[0]}"
}

@test "test scans runs every test tagged treescan, a serial one among them, and no other, and seals the run green (0357)" {
  local root tagged seal
  root="$(scans_root '# bats test_tags=treescan' '@test "scan one" { true; }' \
    '@test "plain one" { true; }' \
    '# bats test_tags=serial,treescan' '@test "scan two, serial" { true; }')"
  tagged="$(grep -c 'test_tags=.*treescan' "$root/tests/unit/a.bats")"
  run scans_run "$root"
  assert_success
  assert_output_contains "1..$tagged"
  assert_output_contains "ok 1 scan one"
  assert_output_contains "ok 2 scan two, serial"
  refute_output_contains "plain one"
  [ "$(grep -c '^ok ' <<<"$output")" -eq "$tagged" ] || fail "ran other than the $tagged tagged test(s): $output"
  seal="$(scans_seal "$root")"
  [ ! -s "$seal" ] || fail "a green scan run left its seal red: $(cat "$seal")"
}

@test "a tagged test that fails fails test scans, and its seal names it (0357)" {
  local root seal
  root="$(scans_root '# bats test_tags=treescan' '@test "scan that fails" { false; }' \
    '@test "plain one" { true; }')"
  run scans_run "$root"
  assert_failure
  assert_output_contains "not ok 1 scan that fails"
  seal="$(scans_seal "$root")"
  grep -q 'not ok 1 scan that fails' "$seal" || fail "the seal does not name the failed scan: $(cat "$seal")"
}

@test "a suite with no test tagged treescan is no clean scan: test scans fails and its seal is not green (0357)" {
  local root seal
  root="$(scans_root '@test "plain one" { true; }')"
  run scans_run "$root"
  assert_failure
  seal="$(scans_seal "$root")"
  [ -s "$seal" ] || fail "a scan run that ran no test left its seal green"
}

@test "test scans takes no path and no bats flag, naming what it was handed, and runs nothing (0357)" {
  local root a
  root="$(scans_root '# bats test_tags=treescan' '@test "scan one" { true; }')"
  for a in tests/unit/a.bats --jobs; do
    run scans_run "$root" "$a"
    assert_failure
    assert_output_contains "test scans takes no paths or bats flags"
    assert_output_contains "$a"
    [ ! -e "$root/tmp/test" ] || fail "a refused scan run ($a) still wrote under tmp/test"
  done
}

@test "devbin's own test all runs bats and keeps scans out, so no tagged arm runs twice (0357)" {
  local run_opts skipped
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  # shellcheck source=lib/resolve
  . "$DEVBIN_LIB_DIR/resolve"
  DEVBIN_DIR="$DEVBIN_HOME/bin/.devbin" PROJECT_ROOT="$DEVBIN_HOME"
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml" >/dev/null
  all_partition test run_opts skipped
  [ "$run_opts" = " bats" ] || fail "devbin's test all runs [$run_opts], not bats alone"
  [ "$skipped" = " scans" ] || fail "devbin's test all keeps out [$skipped], not scans"
}
