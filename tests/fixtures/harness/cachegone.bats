#!/usr/bin/env bats
# cachegone.bats -- one test that removes the file's fixture cache, so
# harness.bats can see teardown_file refuse the file by name (issue 0192). Not
# under tests/unit, so the suite never runs it by itself.

load "../../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

@test "a test removes the fixture cache" {
  chmod -R u+w "$DEVBIN_FIXTURE_CACHE"
  rm -rf "$DEVBIN_FIXTURE_CACHE"
}
