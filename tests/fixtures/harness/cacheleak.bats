#!/usr/bin/env bats
# cacheleak.bats -- two tests, run in order: the first edits, deletes and adds
# in its own fixture's install, and the second holds that the fixture it is
# given is the fresh install's, file for file (issue 0192). Not under
# tests/unit, so the suite never runs it by itself. harness.bats runs it with
# no --jobs, so bats runs the second after the first.

load "../../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

@test "the first test changes its own fixture's install" {
  local proj
  proj="$(create_test_project one)"
  install_devbin "$proj"
  printf '# edited\n' >>"$proj/bin/.devbin/lib/helpers"
  rm "$proj/bin/.devbin/lib/config"
  printf 'added\n' >"$proj/bin/.devbin/lib/added"
  printf 'x\n' >>"$proj/bin/.devbin/manifest.sha256"
}

@test "the next test's fixture is the fresh install's, file for file" {
  local proj
  proj="$(create_test_project two)"
  install_devbin "$proj"
  diff -r "$DEVBIN_FIXTURE_CACHE/bin" "$proj/bin" -x config.yaml -x cmd -x help ||
    fail "the second fixture differs from the cache"
  [ ! -e "$proj/bin/.devbin/lib/added" ] || fail "a file the first test added reached the second"
  run devbin_run "$proj" doctor
  assert_output_contains "vendored files intact"
  refute_output_contains "edited"
}
