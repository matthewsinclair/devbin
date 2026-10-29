#!/usr/bin/env bats
# windowspath.bats - the commands in scope with the Windows PATH appended
# (ST0008, AC-4.1)
#
# Under WSL with appendWindowsPath on, PATH ends in Windows directories whose
# names carry spaces and parentheses, full of *.exe. Every command a developer
# uses there behaves as it does without them, and no .exe runs in place of a
# Linux tool. windows_path builds such a PATH from stubs that record any run,
# so this runs on any machine.
#
# WHAT IT PROVES, STATED: the runtime finds its tools by exact name and splits
# PATH on colons alone, so neither the stubs nor the names move a command's
# output or status. These arms hold behaviour the runtime already had when they
# were written; nothing here runs a real Windows binary. clean's own PATH scan
# is held in clean.bats, beside its other PATH arms.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# unstamped <text> -- <text> with each run's log stamp blanked, since two runs
# a second apart name different logs. A stamp is the minute, then the second
# when another log already holds the minute, then a counter when one holds both.
unstamped() { sed -E 's/[0-9]{8}-[0-9]{4}(-[0-9]{2})?(-[0-9]+)?/STAMP/g' <<<"$1"; }

# THE STARTER GIVEN WORK TO DO: one passing bats suite, so `test all` runs
# bats over a real test rather than stopping at a missing directory, and a
# check.lint that runs shellcheck over a script, as the ST0008 fixtures
# declare one, so `check all` looks a tool up on PATH. Every command must
# succeed without the Windows PATH first, so the comparison is of two runs that
# did something.
# AT-4.1
@test "every command in scope prints and exits as it does without the Windows PATH, and runs no .exe (AC-4.1)" {
  require_command shellcheck
  proj="$DEVBIN_TEST_TMPDIR/demo"
  install_devbin_starter "$proj"
  mkdir -p "$proj/tests" "$proj/scripts"
  printf '#!/usr/bin/env bats\n\n@test "runs" {\n  [ 1 -eq 1 ]\n}\n' >"$proj/tests/smoke.bats"
  printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "%%s\\n" "hello"\n' >"$proj/scripts/hello"
  printf 'commands:\n  check:\n    options:\n      lint:\n        run: shellcheck scripts/hello\n        grammar: generic\n' >>"$proj/bin/.devbin/config.yaml"
  wp="$(windows_path)"
  local c a b ra rb
  for c in help "help --why" version -v doctor "check all" "test all" "shell-init bash"; do
    ra=0
    rb=0
    # shellcheck disable=SC2086 # each command is its words
    a="$(devbin_run "$proj" $c 2>&1)" || ra=$?
    # shellcheck disable=SC2086
    b="$(PATH="$wp" devbin_run "$proj" $c 2>&1)" || rb=$?
    [ "$ra" = 0 ] || fail "'$c' failed without the Windows PATH ($ra), so there is nothing to compare:
$a"
    a="$(unstamped "$a")"
    b="$(unstamped "$b")"
    [ "$ra" = "$rb" ] || fail "'$c' exited $ra without the Windows PATH and $rb with it"
    [ "$a" = "$b" ] || fail "'$c' printed differently with the Windows PATH:
$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"
  done
  refute_windows_exe_ran
}

# AT-4.1
@test "dvb from shell-init bash finds the project and runs it with the Windows PATH appended (AC-4.1)" {
  proj="$DEVBIN_TEST_TMPDIR/demo"
  install_devbin_starter "$proj"
  mkdir -p "$proj/src/deep"
  devbin_run "$proj" shell-init bash >"$DEVBIN_TEST_TMPDIR/dvb.bash"
  wp="$(windows_path)"
  run bash --norc --noprofile -c "set -u; source '$DEVBIN_TEST_TMPDIR/dvb.bash'; cd '$proj/src/deep' && dvb version"
  assert_success
  local without="$output"
  PATH="$wp" run bash --norc --noprofile -c "set -u; source '$DEVBIN_TEST_TMPDIR/dvb.bash'; cd '$proj/src/deep' && dvb version"
  assert_success
  [ "$output" = "$without" ] || fail "dvb version printed differently with the Windows PATH:
$output
-- without it --
$without"
  refute_windows_exe_ran
}
