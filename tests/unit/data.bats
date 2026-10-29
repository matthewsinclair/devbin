#!/usr/bin/env bats
# data.bats - the Data family and recursive sub-dispatch (WP-16)
#
# `db` is the widest-varying command in the corpus: the option names agree
# three ways out of four and the commands behind them do not. So the shipped
# core is deliberately small, and the interesting content here is not the four
# ecto lines -- it is the guard and the descent.
#
# THE GUARD. `db reset` drops the database. Exactly one of the four projects
# refused MIX_ENV=prod, and shipping the command to the other three without that
# refusal would be handing them a footgun they do not currently have.
#
# THE DESCENT discharges AC-04.12: one resolution rule applied at
# every level, so a third level routes by the same test as the second.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }


fakebin() {
  local proj="$1" name="$2"
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\necho "ran:%s args=$*"\n' "$name" >"$proj/fakebin/$name"
  chmod +x "$proj/fakebin/$name"
  echo "$proj/fakebin"
}

# Write an executable sub-handler at an arbitrary depth beneath cmd/.
# Usage: mksub "$proj" media.d/covers
mksub() {
  local proj="$1" relpath="$2" path="$proj/bin/.devbin/cmd/$2"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
printf 'ran:%s args=[%s]\n' "$relpath" "\$*"
EOF
  chmod +x "$path"
}

elixir_project() {
  mkproj "${1:-demo}" <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
}

# ============================================================================
# THE DECLARATIVE CORE (AC-16.1)
# ============================================================================

@test "db runs its catalogued core through the shared gate body" {
  proj="$(elixir_project)"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" db setup
  assert_success
  assert_output_contains "ran:mix args=ecto.setup"
  assert_output_contains "verdict:"
}

@test "a project overrides a catalogued db option in one line" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  db:
    options:
      setup:
        run: mix ash.setup
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  # The tiers' finding in miniature: the NAME agrees across the corpus, the
  # command does not. One line, and no shell.
  PATH="$bin:$PATH" run devbin_run "$proj" db setup
  assert_success
  assert_output_contains "ran:mix args=ash.setup"
  refute_output_contains "ecto.setup"
}

# ============================================================================
# THE PROD GUARD (AC-16.2)
# ============================================================================

@test "db refuses MIX_ENV=prod and says what it is protecting" {
  proj="$(elixir_project)"
  local bin
  bin="$(fakebin "$proj" mix)"
  MIX_ENV=prod PATH="$bin:$PATH" run devbin_run "$proj" db reset
  assert_failure
  assert_output_contains "refuses MIX_ENV=prod"
  # Naming the consequence is the point -- "refused" alone invites a retry with
  # whatever flag makes it stop refusing.
  assert_output_contains "drops the database"
  assert_output_contains "project handler"
  # And it did not run.
  refute_output_contains "ran:mix"
}

@test "db runs normally in the default environment" {
  proj="$(elixir_project)"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" db migrate
  assert_success
  assert_output_contains "ran:mix args=ecto.migrate"
}

@test "a project handler is the way past the guard, and shadows totally" {
  proj="$(elixir_project)"
  create_test_command "$proj" db >/dev/null
  # The documented escape hatch. Deliberately a bigger and more visible step
  # than passing a flag would be.
  MIX_ENV=prod run devbin_run "$proj" db reset
  assert_success
  assert_output_contains "ran:db"
  refute_output_contains "refuses MIX_ENV=prod"
}

@test "MIX_ENV=prod is refused before any db path runs, whoever supplies the line (0132)" {
  # The guard lived in lib/cmd/db, which only devbin's own lines reach, so an
  # override -- `setup.run: mix ash.setup`, the shape the tiers expect -- ran
  # under prod, sealed, exit 0. It is asked in the dispatcher now, before `all`,
  # any option or the command line.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  db:
    options:
      setup:
        run: mix ash.setup
      rollback:
        run: mix ecto.rollback
YAML
  )"
  local bin a
  bin="$(fakebin "$proj" mix)"
  for a in setup rollback all; do
    MIX_ENV=prod PATH="$bin:$PATH" run devbin_run "$proj" db "$a"
    assert_exit_code 1
    assert_output_contains "refuses MIX_ENV=prod"
    refute_output_contains "ran:mix"
  done
  [ ! -d "$proj/tmp/db" ] || fail "a refused run left a seal: $(ls "$proj/tmp/db")"
  # A command-level line is the project's too, and refused the same way.
  proj2="$(mkproj demo2 <<'YAML'
project:
  name: demo2
  languages:
    - elixir
commands:
  db:
    run: mix custom.db
YAML
  )"
  MIX_ENV=prod PATH="$bin:$PATH" run devbin_run "$proj2" db
  assert_exit_code 1
  assert_output_contains "refuses MIX_ENV=prod"
  refute_output_contains "ran:mix"
  # THE CONTROL: the same lines run outside prod.
  PATH="$bin:$PATH" run devbin_run "$proj" db setup
  assert_success
  assert_output_contains "ran:mix args=ash.setup"
  PATH="$bin:$PATH" run devbin_run "$proj2" db
  assert_success
  assert_output_contains "ran:mix args=custom.db"
}

@test "a handler mapped with commands.db.handler passes the refusal too, as a file there does (0132)" {
  # db.md says a project handler is the one thing the refusal lets past, and a
  # handler can be a file at bin/.devbin/cmd/db or one mapped by name. Both are
  # has_project_handler, so both pass; this holds the mapped one.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  db:
    handler: mydb
YAML
  )"
  create_test_command "$proj" mydb >/dev/null
  MIX_ENV=prod run devbin_run "$proj" db reset
  assert_success
  assert_output_contains "ran:mydb"
  refute_output_contains "refuses MIX_ENV=prod"
}

# ============================================================================
# `all` AND A MISTYPED OPTION (issue 0132)
# ============================================================================

@test "db all leaves reset out unless config brings it back, and reset still runs by name (0132)" {
  # `db all` ran setup, migrate, reset and seed -- and reset is mix ecto.reset:
  # drop, create, migrate, seed -- then said all db options passed.
  proj="$(elixir_project)"
  local bin total
  bin="$(fakebin "$proj" mix)"
  # The db options devbin ships, read from the fixture's own vendored catalogue,
  # not typed: elixir_project declares none of its own.
  total="$(fixture_catalogue_count "$proj" db)"
  [ "$total" -gt 0 ] || fail "the catalogue ships no db option -- the count line would be checked against nothing"
  PATH="$bin:$PATH" run devbin_run "$proj" db all
  assert_success
  assert_output_contains "ran:mix args=ecto.setup"
  assert_output_contains "ran:mix args=ecto.migrate"
  assert_output_contains "ran:mix args=run priv/repo/seeds.exs"
  refute_output_contains "ecto.reset"
  assert_output_contains "skipped (in_all: false): reset"
  # Every one runs but reset, the one skipped above.
  assert_output_contains "$((total - 1)) of $total db options ran; 0 inactive here, 1 skipped (in_all: false)"
  # By name it still runs: devbin's default takes it out of the sweep, no more.
  PATH="$bin:$PATH" run devbin_run "$proj" db reset
  assert_success
  assert_output_contains "ran:mix args=ecto.reset"
  # And config wins over the default.
  printf 'commands:\n  db:\n    options:\n      reset:\n        in_all: true\n' >>"$proj/bin/.devbin/config.yaml"
  PATH="$bin:$PATH" run devbin_run "$proj" db all
  assert_success
  assert_output_contains "ran:mix args=ecto.reset"
  refute_output_contains "skipped (in_all: false): reset"
  assert_output_contains "$total of $total db options ran; 0 inactive here, 0 skipped (in_all: false)"
}

@test "a mistyped gate option is told the options and help, never <cmd> all (0132)" {
  # The one remedy offered for `db migrat` was `db all`, which ran reset. The
  # line is every built-in gate command's, so check is held to it as well.
  proj="$(elixir_project)"
  run devbin_run "$proj" db migrat
  assert_exit_code 1
  assert_output_contains "unknown db option: migrat"
  assert_output_contains "setup, migrate, reset, seed"
  assert_output_contains "help db"
  refute_output_contains "db all"
  run devbin_run "$proj" check nosuch
  assert_exit_code 1
  assert_output_contains "unknown check option: nosuch"
  assert_output_contains "help check"
  refute_output_contains "check all"
}

# ============================================================================
# RECURSIVE SUB-DISPATCH -- discharging AC-04.12 (AC-16.3 to AC-16.5)
# ============================================================================

@test "a second level resolves against the handler's .d directory" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" media >/dev/null
  mksub "$proj" media.d/covers
  run devbin_run "$proj" media covers
  assert_success
  assert_output_contains "ran:media.d/covers"
  # Anchored: `ran:media` is a substring of `ran:media.d/covers`, so the bare
  # refute would fail against the very output that proves the descent worked.
  refute_output_matches 'ran:media args='
}

@test "a third level resolves by the same rule as the second" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" media >/dev/null
  mksub "$proj" media.d/covers
  mksub "$proj" media.d/covers.d/thumbs
  # One rule applied at each level, not a special case per depth.
  run devbin_run "$proj" media covers thumbs
  assert_success
  assert_output_contains "ran:media.d/covers.d/thumbs"
}

@test "arguments survive the descent" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" media >/dev/null
  mksub "$proj" media.d/covers
  run devbin_run "$proj" media covers --force out.png
  assert_success
  assert_output_contains "ran:media.d/covers args=[--force out.png]"
}

@test "a word that names no sub-handler is an argument, not an error" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" db >/dev/null
  # This is what keeps `db sql "select 1"` working. The descent stops at the
  # first word with no handler behind it and the rest is the handler's business.
  run devbin_run "$proj" db sql "select 1"
  assert_success
  assert_output_contains "ran:db"
  assert_output_contains "sql select 1"
}

@test "the descent stops at the first word without a handler, mid-chain" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" media >/dev/null
  mksub "$proj" media.d/covers
  # `covers` descends; `nope` does not, so it and everything after it are
  # arguments to covers rather than a resolution failure.
  run devbin_run "$proj" media covers nope thumbs
  assert_success
  assert_output_contains "ran:media.d/covers args=[nope thumbs]"
}

@test "a DIRECTORY in the descent path is not mistaken for a sub-handler" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" macos >/dev/null
  # The corpus already has this shape: one consumer's `<project>_macos.d/pkg` is a
  # directory of packaging resources sitting beside the real sub-handlers. `-x`
  # is TRUE for a directory, so the descent took it and tried to exec it.
  mkdir -p "$proj/bin/.devbin/cmd/macos.d/pkg"
  printf 'a resource, not a command\n' >"$proj/bin/.devbin/cmd/macos.d/pkg/Distribution.xml"

  run devbin_run "$proj" macos pkg
  assert_success
  # `pkg` is an ARGUMENT to macos, exactly as any other word with no handler
  # behind it would be.
  assert_output_contains "ran:macos args:pkg"
}

@test "a directory under cmd is not a command" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  create_test_command "$proj" macos >/dev/null
  mkdir -p "$proj/bin/.devbin/cmd/macos.d/pkg"

  # Typing the directory's own name resolved it as a handler and died trying to
  # exec it: a raw bash "Is a directory" naming an internal library path, and
  # exit 126, which is not one of the documented codes.
  run devbin_run "$proj" macos.d
  assert_exit_code 2
  refute_output_contains "Is a directory"
}

@test "the descent applies to devbin's own handlers too" {
  proj="$(elixir_project)"
  # One resolution rule, whoever supplied the handler. lib/cmd/db is devbin's,
  # and a sub-handler beside it resolves exactly as a project's would.
  mkdir -p "$proj/bin/.devbin/lib/cmd/db.d"
  cat >"$proj/bin/.devbin/lib/cmd/db.d/dump" <<'EOF'
#!/usr/bin/env bash
printf 'ran:builtin-db-dump args=[%s]\n' "$*"
EOF
  chmod +x "$proj/bin/.devbin/lib/cmd/db.d/dump"
  run devbin_run "$proj" db dump --schema
  assert_success
  assert_output_contains "ran:builtin-db-dump args=[--schema]"
}
