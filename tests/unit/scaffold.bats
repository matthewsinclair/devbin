#!/usr/bin/env bats
# scaffold.bats - `devbin new` (WP-09)
#
# WP-07 established that a handler dropped into cmd/ is first-class in help with
# no config edit (AC-07.4). This is that promise turned into one command: the
# claim under test is not that files appear, but that the command RESOLVES and
# is described correctly straight afterwards, with nothing else touched.
#
# So most of these tests run the scaffolded command rather than inspecting it.
# Asserting on the file's contents would pass just as well for a scaffold that
# produced something devbin could not reach.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }

mkinstalled() {
  local dir="$DEVBIN_TEST_TMPDIR/demo"
  # The file's starter install, copied (issue 0192).
  install_devbin_starter "$dir" || return 1
  echo "$dir"
}

# ============================================================================
# WHAT IT PRODUCES (AC-09.14)
# ============================================================================

@test "a scaffolded command resolves on the next invocation" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello to someone"
  assert_success
  # Not "the file exists" -- the file existing and the command resolving are
  # different claims, and only the resolving is the promise.
  run devbin_run "$proj" greet
  assert_exit_code 3
  assert_output_contains "not implemented yet"
}

@test "a scaffolded command appears in help with its summary, no config edit" {
  proj="$(mkinstalled)"
  before="$(cat "$proj/bin/.devbin/config.yaml")"
  run devbin_run "$proj" new greet --summary "Say hello to someone"
  assert_success
  run devbin_run "$proj" help
  assert_success
  assert_output_contains greet
  assert_output_contains "Say hello to someone"
  [ "$before" = "$(cat "$proj/bin/.devbin/config.yaml")" ] || {
    echo "new edited config.yaml, which is the thing it exists not to need"
    return 1
  }
}

@test "the group in the header becomes the heading it sits under" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello" --group Greetings
  assert_success
  run devbin_run "$proj" help
  assert_success
  assert_output_matches 'Greetings:'
}

@test "new run from a subdirectory writes bin/devbin into the files, never an absolute path (0105)" {
  # {{DEVBIN}} rendered DEVBIN_INVOKE, which is an absolute path when devbin is
  # called from below the root, so the scaffold baked this machine's path into
  # a tracked handler, its help and its test.
  proj="$(mkinstalled)"
  mkdir -p "$proj/tests/unit" "$proj/sub"
  run sh -c "cd '$proj/sub' && ../bin/devbin new greet --summary 'Say hello' </dev/null"
  assert_success
  for f in bin/.devbin/cmd/greet bin/.devbin/help/greet.md; do
    grep -q 'bin/devbin' "$proj/$f" || fail "$f names no bin/devbin"
    ! grep -q "$proj" "$proj/$f" || fail "$f carries the absolute path $proj:
$(grep -n "$proj" "$proj/$f")"
  done
}

@test "the scaffolded handler answers --help successfully" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  run devbin_run "$proj" greet --help
  assert_success
  assert_output_contains usage
}

@test "the scaffolded command exits 3, not 0, before anyone implements it" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  run devbin_run "$proj" greet
  # An unbuilt command returning 0 is a false green in every `&&` chain that
  # ever calls it -- the same rule the gates and AC-04.13 hold to.
  refute_assertion assert_exit_code 0
  assert_exit_code 3
}

@test "help <cmd> prints the authored stub the scaffold wrote" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  assert_file_exists "$proj/bin/.devbin/help/greet.md"
  run devbin_run "$proj" help greet
  assert_success
  # {{DEVBIN}} in the scaffolded stub is the INVOCATION, so an authored help
  # page shows what a reader should actually type rather than the project name.
  assert_output_contains "bin/devbin greet"
}

@test "a test stub lands beside the project's existing bats suite" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/tests/unit"
  printf '#!/usr/bin/env bats\n' >"$proj/tests/unit/existing.bats"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  assert_file_exists "$proj/tests/unit/greet.bats"
}

@test "with no bats suite the stub is skipped and said to be skipped" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  assert_output_contains "no bats suite"
}

# A SEARCH WITH A HOLE IN IT IS SAID (issue 0139). find's errors went to
# /dev/null, so a suite beneath a directory it could not read was a project
# with no suite, and nothing said the search had been partial. It picks where to
# scaffold rather than giving a verdict, so what it found is still used.
@test "a search for the suite that cannot read everything says so, and still uses what it found (0139, 0145)" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/tests/unit" "$proj/locked"
  printf '#!/usr/bin/env bats\n' >"$proj/tests/unit/existing.bats"
  # THE CONTROL: readable, nothing is said.
  run devbin_run "$proj" new hello --summary "Say hello"
  assert_success
  assert_file_exists "$proj/tests/unit/hello.bats"
  refute_output_contains "could not search all of"
  chmod 000 "$proj/locked"
  if [ -r "$proj/locked" ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  run devbin_run "$proj" new greet --summary "Say hello"
  chmod 755 "$proj/locked"
  assert_success
  assert_output_contains "could not search all of $proj for a bats suite"
  assert_output_contains "a suite beneath it was not seen"
  assert_find_denied "locked"
  assert_file_exists "$proj/tests/unit/greet.bats"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and a suite beneath it went unseen and unsaid.
  chmod 644 "$proj/locked"
  if [ -x "$proj/locked" ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  run devbin_run "$proj" new wave --summary "Say hello"
  chmod 755 "$proj/locked"
  assert_success
  assert_output_contains "cannot search $proj/locked -- nothing beneath it was looked at"
  assert_output_contains "a suite beneath it was not seen"
  assert_file_exists "$proj/tests/unit/wave.bats"
}

@test "the test stub never lands inside devbin's own runtime" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  # It did. The runtime ships tmpl/test.bats, so the search for "where does this
  # project keep its tests" found the TEMPLATE first and wrote the stub into the
  # vendored library -- a file upgrade does not manage and nothing ever runs.
  assert_file_not_exists "$proj/bin/.devbin/lib/tmpl/greet.bats"
  run bash -c "find '$proj/bin/.devbin/lib' -name 'greet*'"
  assert_output ""
}

@test "a scaffolded command does not disturb the commands already there" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" help
  assert_success
  before="$output"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  run devbin_run "$proj" help
  assert_success
  # Every line that was there before is still there. A scaffold that quietly
  # displaced a built-in would look identical to one that worked.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$output" in
      *"$line"*) : ;;
      *)
        echo "help lost a line after new: $line"
        return 1
        ;;
    esac
  done <<EOF
$before
EOF
}

# ============================================================================
# WHAT IT REFUSES (AC-09.15)
# ============================================================================

@test "new refuses to overwrite an existing handler" {
  proj="$(mkinstalled)"
  printf '#!/usr/bin/env bash\necho mine\n' >"$proj/bin/.devbin/cmd/greet"
  chmod +x "$proj/bin/.devbin/cmd/greet"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_failure
  assert_output_contains "already exists"
  assert_file_contains "$proj/bin/.devbin/cmd/greet" "echo mine"
}

@test "new refuses a name that is not a legal command name, and says which rule" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new "Bad Name"
  assert_failure
  assert_output_contains "lower-case letters"

  run devbin_run "$proj" new 9lives
  assert_failure
  assert_output_contains "must start with"
}

@test "bare new prints usage and exits 1, not 0" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" new
  assert_failure
  assert_output_contains usage
  run devbin_run "$proj" new --help
  assert_success
}

@test "an existing authored help topic is kept, not overwritten" {
  proj="$(mkinstalled)"
  printf '# greet\n\nWritten by a person.\n' >"$proj/bin/.devbin/help/greet.md"
  run devbin_run "$proj" new greet --summary "Say hello"
  assert_success
  assert_file_contains "$proj/bin/.devbin/help/greet.md" "Written by a person"
}

# ============================================================================
# THE TEMPLATES THEMSELVES
# ============================================================================

@test "the handler template is valid bash before anything is substituted" {
  # It lives under lib/ with a bash shebang, so `check syntax` already parses it
  # on every run -- this asserts the property directly rather than relying on a
  # gate in another file to notice. A template that does not parse scaffolds a
  # handler that does not parse, and the failure surfaces in the user's project.
  run bash -n "$DEVBIN_LIB_DIR/tmpl/handler"
  assert_success
}

@test "a summary containing punctuation survives substitution intact" {
  proj="$(mkinstalled)"
  # `&` is the matched text in an awk gsub and `/` ends a sed expression, which
  # is why the substitution is bash parameter expansion and not either of those.
  run devbin_run "$proj" new greet --summary "Fetch a/b & report 100% of it"
  assert_success
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "Fetch a/b & report 100% of it"
}

@test "no placeholder survives into a scaffolded file" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/tests/unit"
  printf '#!/usr/bin/env bats\n' >"$proj/tests/unit/existing.bats"
  run devbin_run "$proj" new greet --summary "Say hello" --group Greetings
  assert_success
  for f in "$proj/bin/.devbin/cmd/greet" "$proj/bin/.devbin/help/greet.md" \
    "$proj/tests/unit/greet.bats"; do
    refute_file_contains "$f" '{{'
  done
}
