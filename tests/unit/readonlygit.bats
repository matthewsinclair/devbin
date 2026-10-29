#!/usr/bin/env bats
# readonlygit.bats - a read is not a write (issue 0094)
#
# A plain `git status` takes git's OPTIONAL index lock and, when the index's
# stat information is stale, rewrites `.git/index`. On a path that only means to
# READ, that is a write into a repository the caller does not own, and it can
# fail a peer's concurrent commit with `index.lock exists`. Found by a
# doctor sweep across several projects: doctor touched `.git` in two of them,
# reproducibly, where a no-op window did not. The writer there was each project's
# own `project.referent`, which the dispatcher evals on every command; devbin's
# own read paths below were found by the tests written to prove the fix.
#
# THE FIXTURE MUST BE STALE, OR NOTHING HERE CAN GO RED. A fresh index has
# nothing to refresh, so a plain `git status` on it writes nothing either -- the
# finding came and went for exactly that reason. The control comes first and
# proves the fixture makes plain `git status` write.
#
# NO SLEEPS. Everything under `.git` and the tracked file are backdated to 2000
# and the marker to 2001, so any write made by the code under test is newer
# than the marker whatever the clock's granularity.
load "../lib/test_helper"

setup() {
  devbin_setup
  # THE AMBIENT ENVIRONMENT MUST NOT DECIDE THIS FILE. GIT_OPTIONAL_LOCKS=0
  # exported in the shell that runs the suite stops plain `git status` writing
  # at all, so every arm below would pass vacuously -- which the control arm
  # caught on a real full-suite run (0094 follow-up). The repository-local
  # variables go too, since an inherited GIT_DIR or GIT_INDEX_FILE would point
  # every fixture at another repository. Arms that want one set it themselves.
  # shellcheck disable=SC2046
  unset GIT_OPTIONAL_LOCKS $(git rev-parse --local-env-vars)
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# stale <repo> <tracked-file> -- make <repo>'s index stat-stale and backdate
# everything under .git, then print a marker path older than any write to come.
stale() {
  local repo="$1" file="$2" marker="$DEVBIN_TEST_TMPDIR/marker.$RANDOM"
  touch -t 200001010000 "$repo/$file"
  find "$repo/.git" -exec touch -h -t 200001010000 {} +
  touch -t 200101010000 "$marker"
  echo "$marker"
}

# written <repo> <marker> -- every path under <repo>/.git newer than <marker>.
written() {
  find "$1/.git" -newer "$2"
}

# commit_fixture <repo> <commit args>... -- commit in a fixture repository,
# starting no background maintenance (issue 0233). A plain `git commit` starts
# `git maintenance run --auto --detach`, which runs on after the commit returns,
# and a repack it writes once stale() has backdated .git is read here as a write
# by the code under test. maintenance.auto=false keeps the commit from starting
# it, and gc.auto=0 does the same for a git that runs `gc --auto` there instead.
# Both go on the commit alone, never into the repository's config or the
# environment, so the code under test still runs git under git's defaults and
# anything it starts is still measured.
commit_fixture() {
  local repo="$1"
  shift
  git -C "$repo" -c user.email=dev@test -c user.name=dev -c maintenance.auto=false -c gc.auto=0 commit -q "$@"
}

# mkrepo [name] -- a checkout with one commit.
mkrepo() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-repo}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf 'one\n' >"$dir/file.txt"
  git -C "$dir" add -A
  commit_fixture "$dir" -m first
  echo "$dir"
}

# gitproj -- a fixture project with devbin installed, committed as a checkout.
gitproj() {
  local proj
  proj="$(mkproj demo <<'EOF'
project:
  name: demo
  alias: dm
EOF
)"
  printf 'tmp/\n' >"$proj/.gitignore"
  git -C "$proj" init -q
  git -C "$proj" add -A
  commit_fixture "$proj" -m first
  echo "$proj"
}

assert_unwritten() {
  local out
  out="$(written "$1" "$2")"
  [ -z "$out" ] || fail "wrote under .git: $out"
}

# ============================================================================
# THE CONTROL, FIRST
# ============================================================================

@test "the stale fixture makes plain git status write the index, and a no-op does not" {
  local repo marker out
  repo="$(mkrepo)"
  marker="$(stale "$repo" file.txt)"
  assert_unwritten "$repo" "$marker"

  git -C "$repo" status --porcelain >/dev/null
  out="$(written "$repo" "$marker")"

  [[ "$out" == *"/.git/index"* ]] || fail "plain git status did not write the index, so this fixture cannot catch a read that writes: '$out'"
}

# ============================================================================
# THE READ PATHS
# ============================================================================

@test "git_head_identity leaves .git untouched on a stale index" {
  local repo marker
  repo="$(mkrepo)"
  marker="$(stale "$repo" file.txt)"

  run git_head_identity "$repo"

  assert_success
  assert_unwritten "$repo" "$marker"
}

@test "release_dirt leaves .git untouched on a stale index" {
  local repo marker
  repo="$(mkrepo)"
  marker="$(stale "$repo" file.txt)"
  # shellcheck source=lib/release.notes
  . "$DEVBIN_LIB_DIR/release.notes"
  # shellcheck source=lib/release.steps
  . "$DEVBIN_LIB_DIR/release.steps"

  cd "$repo"
  run release_dirt

  assert_success
  assert_unwritten "$repo" "$marker"
}

@test "--version leaves .git untouched on a stale index" {
  local proj marker
  proj="$(gitproj)"
  marker="$(stale "$proj" bin/.devbin/config.yaml)"

  run devbin_run "$proj" --version

  assert_success
  assert_unwritten "$proj" "$marker"
}

@test "doctor leaves .git untouched on a stale index" {
  local proj marker
  proj="$(gitproj)"
  marker="$(stale "$proj" bin/.devbin/config.yaml)"

  run devbin_run "$proj" doctor

  assert_unwritten "$proj" "$marker"
}

@test "fullcycle's header leaves .git untouched on a stale index" {
  local proj marker
  proj="$(mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
EOF
)"
  create_test_command "$proj" build >/dev/null
  printf 'tmp/\n' >"$proj/.gitignore"
  git -C "$proj" init -q
  git -C "$proj" add -A
  commit_fixture "$proj" -m first
  marker="$(stale "$proj" bin/.devbin/config.yaml)"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "dirty: 0 file(s)"
  assert_unwritten "$proj" "$marker"
}

# ============================================================================
# A PROJECT'S REFERENT IS A READ TOO
# ============================================================================

# refproj <referent> -- a committed fixture project declaring project.referent.
# The dispatcher evals the referent on EVERY invocation, so this is where the
# writes came from: two consumers and Intent each declare one that runs a
# plain `git status` (issue 0094).
refproj() {
  local proj
  proj="$(mkproj refdemo <<EOF
project:
  name: refdemo
  alias: rf
  referent: '$1'
EOF
)"
  printf 'tmp/\n' >"$proj/.gitignore"
  git -C "$proj" init -q
  git -C "$proj" add -A
  commit_fixture "$proj" -m first
  echo "$proj"
}

@test "a referent running plain git status leaves .git untouched on a stale index" {
  local proj marker
  proj="$(refproj 'git status --porcelain | wc -l')"
  marker="$(stale "$proj" bin/.devbin/config.yaml)"

  run devbin_run "$proj" help

  assert_success
  assert_unwritten "$proj" "$marker"
}

# THE CONTROL AND THE OVERRIDE IN ONE: the same referent, opting back in to
# git's optional locks, does write -- so the arm above is not green by accident,
# and a project that wants the lock can still have it.
@test "a referent that sets GIT_OPTIONAL_LOCKS=1 itself does write: the override" {
  local proj marker out
  proj="$(refproj 'GIT_OPTIONAL_LOCKS=1 git status --porcelain | wc -l')"
  marker="$(stale "$proj" bin/.devbin/config.yaml)"

  run devbin_run "$proj" help

  assert_success
  out="$(written "$proj" "$marker")"
  [[ "$out" == *"/.git/index"* ]] || fail "the override did not reach git: '$out'"
}

# ============================================================================
# ONE IDENTITY LINE READS ONE REPOSITORY
# ============================================================================

# An inherited GIT_DIR outranks `-C`. If the sha honoured it and the dirt did
# not, the line would pair one repository's commit with another tree's `+dirty`.
@test "git_head_identity reads the repository at root, not one an inherited GIT_DIR names" {
  local a b sha_a
  a="$(mkrepo a)"
  b="$(mkrepo b)"
  printf 'two\n' >"$b/file.txt"
  commit_fixture "$b" -am second
  sha_a="$(git -C "$a" rev-parse HEAD)"

  GIT_DIR="$b/.git" run git_head_identity "$a"

  assert_success
  assert_output "$sha_a"
}

# release WRITES under whatever git environment it inherited -- `git add`, the
# commit, the tag -- so its dirt check must read under the same one. Clearing
# GIT_DIR for the read alone would check one repository and commit into another.
@test "release_dirt reads the repository release writes to, under an inherited GIT_DIR" {
  local a b writer
  a="$(mkrepo a)"
  b="$(mkrepo b)"
  printf 'two\n' >"$b/file.txt"
  commit_fixture "$b" -am second
  # shellcheck source=lib/release.notes
  . "$DEVBIN_LIB_DIR/release.notes"
  # shellcheck source=lib/release.steps
  . "$DEVBIN_LIB_DIR/release.steps"

  cd "$a"
  export GIT_DIR="$b/.git"
  writer="$(git status --porcelain=v1 --untracked-files=all)"
  run release_dirt
  unset GIT_DIR

  assert_success
  [ -n "$writer" ] || fail "control: the writer's view of this fixture is clean, so the arm proves nothing"
  assert_output_contains "file.txt"
}

# ============================================================================
# ONE HOME
# ============================================================================

@test "git_readonly is defined once, in lib/helpers" {
  local defs
  defs="$(grep -rlE '^git_readonly\(\)' "$DEVBIN_LIB_DIR")"
  [ "$defs" = "$DEVBIN_LIB_DIR/helpers" ] || fail "git_readonly is defined in: $defs"
}
