#!/usr/bin/env bats
# cachetamper.bats -- one test that makes the file's fixture cache writable and
# writes into it, so harness.bats can see teardown_file refuse the file by name
# (issue 0192). Not under tests/unit, so the suite never runs it by itself.

load "../../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

@test "a test writes into the fixture cache" {
  chmod u+w "$DEVBIN_FIXTURE_CACHE/bin/.devbin/lib"
  printf 'written by a test\n' >"$DEVBIN_FIXTURE_CACHE/bin/.devbin/lib/tampered"
}
