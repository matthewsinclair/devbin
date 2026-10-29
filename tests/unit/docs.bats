#!/usr/bin/env bats
# docs.bats - the docs command (WP-17)
#
# One option ships. `agents` is identical across the projects that have it;
# `completions`, `index` and `publish` are one or two of four and encode where a
# project keeps its output, so they stay project handlers.
#
# `treeindex` once shipped here. `intent treeindex` was retired from Intent v3
# with no replacement, so devbin was shipping -- to itself and to every project
# that vendors the runtime -- a command that lists cleanly, resolves cleanly and
# can never succeed once a project moves. The treeindex tests below are
# what keep it gone: a removal nothing asserts is a removal that comes back.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }


# A fake `intent` so these tests do not depend on the real one being installed
# or on what it would do to the fixture.
fake_intent() {
  local proj="$1"
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\necho "intent $*"\n' >"$proj/fakebin/intent"
  chmod +x "$proj/fakebin/intent"
  echo "$proj/fakebin"
}

# demo_project -- a project with an intent/ directory: docs agents drives
# Intent, and is inactive in a tree without one (issue 0156).
demo_project() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  mkdir -p "$proj/intent"
  printf '%s\n' "$proj"
}

@test "docs agents regenerates AGENTS.md and warns that hand edits are lost" {
  proj="$(demo_project)"
  local bin
  bin="$(fake_intent "$proj")"
  PATH="$bin:$PATH" run devbin_run "$proj" docs agents
  assert_success
  assert_output_contains "intent agents sync"
  # Not decoration: AGENTS.md looks like an ordinary Markdown file and this
  # destroys a hand edit without comment.
  assert_output_contains "AGENTS.md is generated"
}

@test "docs all runs the shipped option" {
  proj="$(demo_project)"
  local bin
  bin="$(fake_intent "$proj")"
  PATH="$bin:$PATH" run devbin_run "$proj" docs all
  assert_success
  assert_output_contains "intent agents sync"
}

@test "docs agents reports a failing indexer rather than returning 0 over it" {
  # Issue 0016: the status of the tool that does the work has to reach the
  # caller. Its sibling defect lived in `docs treeindex`, which discarded a
  # non-zero `intent` entirely and returned 0 with an empty verdict artefact
  # recording success. That function is gone; this is the surviving half of the
  # same claim, and the reason it is tested here rather than assumed.
  proj="$(demo_project)"
  local bin
  bin="$(fake_intent "$proj")"
  printf '#!/bin/sh\nexit 3\n' >"$bin/intent"
  chmod +x "$bin/intent"
  PATH="$bin:$PATH" run devbin_run "$proj" docs agents
  assert_failure
  assert_output_contains "AGENTS.md NOT regenerated"
}

@test "docs treeindex is GONE -- not offered, not resolvable, not in help" {
  # A removal nothing asserts is a removal that comes back. `intent treeindex`
  # was retired from Intent v3 with no replacement, so an offered
  # `docs treeindex` would be a row that can never succeed -- the exact
  # shape `check_commands` refuses, pointed at devbin itself.
  proj="$(demo_project)"
  local bin
  bin="$(fake_intent "$proj")"

  PATH="$bin:$PATH" run devbin_run "$proj" docs treeindex
  assert_failure
  refute_output_contains "intent treeindex"

  # And it is absent from what devbin OFFERS, not merely broken when called.
  PATH="$bin:$PATH" run devbin_run "$proj" docs
  refute_output_contains "treeindex"
}

@test "docs.treeindex_dirs is no longer a config key the schema knows" {
  # The config half of the same removal. A key the runtime no longer reads but
  # the schema still accepts is how a consumer keeps a dead setting for a year
  # and is told nothing.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
docs:
  treeindex_dirs:
    - lib
YAML
  )"
  run devbin_run "$proj" doctor
  assert_output_contains "docs.treeindex_dirs"
}
