#!/usr/bin/env bats
# probe.bats -- one test that does nothing but take the suite's own setup, so
# harness.bats can run it under a chosen TMPDIR and read what devbin_setup did.
# Not under tests/unit, so the suite never runs it by itself.

load "../../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

@test "the setup ran" {
  [ -d "$DEVBIN_TEST_TMPDIR" ]
}
