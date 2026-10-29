#!/usr/bin/env bats
# gitident.bats - the build's git identity (issue 0014)
#
# Devbin owns the version-number axis completely and owned nothing of the git
# one, so every project resolved "what commit is this build" for itself. The
# READ is trivial and all six sites in one consumer agreed on it. THE INVALIDATION IS
# WHERE FOUR OUT OF FOUR WENT WRONG, each by naming git's internal paths
# literally:
#
#     ../../.git/HEAD
#     ../../.git/refs/heads/
#
# In a LINKED WORKTREE neither exists. `.git` is a 59-byte FILE reading
# `gitdir: <path>`. The same unresolved path produced OPPOSITE symptoms decided
# only by whether the toolchain fails open or closed: Elixir's @external_resource
# over an empty list registered no dependency and froze a stale sha for a working
# day, while cargo treated an unstattable rerun-if-changed as permanently dirty
# and rebuilt forever. One is a version string that lies and the other is a cache
# that never hits, and only the first ever gets reported.
#
# SO EVERY TEST HERE THAT MATTERS RUNS IN A REAL LINKED WORKTREE, and the
# control comes FIRST: a test written in a normal checkout passes against the
# broken literal paths, which is exactly how this survived. Asserting the sha is
# fresh proves nothing either -- under cargo the sha stayed correct while the
# mechanism was entirely broken -- so the assertions are on the resolved path
# SET.
#
load "../lib/test_helper"

setup() {
  devbin_setup
  # Deliberately the only thing sourced: this is a lib/helpers capability, and
  # handlers source that file alone.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# mkrepo [name] -- a checkout with one commit on a branch.
mkrepo() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-repo}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email dev@test
  git -C "$dir" config user.name dev
  printf 'one\n' >"$dir/file.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "first"
  echo "$dir"
}

# mkworktree <repo> [name] -- a LINKED worktree of <repo>, where `.git` is a file.
mkworktree() {
  local repo="$1" dir="$DEVBIN_TEST_TMPDIR/${2:-wt}"
  git -C "$repo" worktree add -q -b wtbranch "$dir" >/dev/null 2>&1
  echo "$dir"
}

# ============================================================================
# THE CONTROL, FIRST -- without it nothing below means anything
# ============================================================================

@test "the worktree fixture really does exhibit the trap it exists to catch" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  # If these ever become true, every test in this file silently starts passing
  # against the broken implementation, because the literal paths would resolve.
  [ -f "$wt/.git" ]
  [ ! -d "$wt/.git" ]
  [ ! -e "$wt/.git/HEAD" ]
  [ ! -d "$wt/.git/refs/heads" ]
}

# ============================================================================
# THE READ HALF -- the part nobody got wrong
# ============================================================================

@test "the sha reads in a normal checkout and in a linked worktree alike" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  run git_head_sha "$repo"
  assert_success
  assert_output_matches '^[0-9a-f]+$'

  run git_head_sha "$wt"
  assert_success
  assert_output_matches '^[0-9a-f]+$'
}

# ============================================================================
# THE IDENTITY FORM -- what a --version line says about WHICH bytes are running
# ============================================================================

@test "git_head_sha still defaults to SHORT -- the form is opt-in, callers unchanged" {
  repo="$(mkrepo)"
  local short full
  short="$(git_head_sha "$repo")"
  full="$(git_head_sha "$repo" full)"
  [ "${#short}" -lt 40 ] || fail "the default stopped being short: $short"
  [ "${#full}" -eq 40 ] || fail "full form is not a 40-char sha: $full"
  case "$full" in "$short"*) ;; *) fail "short is not a prefix of full: $short / $full" ;; esac
}

@test "the identity is the FULL sha in a checkout and in a linked worktree alike" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  run git_head_identity "$repo"
  assert_success
  assert_output_matches '^[0-9a-f]{40}$'

  run git_head_identity "$wt"
  assert_success
  assert_output_matches '^[0-9a-f]{40}$'
}

# A BARE SHA ON A DIRTY TREE IS A CONFIDENT FALSE STATEMENT: the bytes running
# are not that commit. This arm and the one above it are a pair -- either alone
# passes against an implementation that always says one thing.
@test "a dirty working tree is marked, and a clean one is not" {
  repo="$(mkrepo)"

  run git_head_identity "$repo"
  assert_success
  refute_output_contains "+dirty"

  echo "uncommitted" > "$repo/scratch.txt"
  run git_head_identity "$repo"
  assert_success
  assert_output_matches '^[0-9a-f]{40} \+dirty$'
}

# A FAILED STATUS IS NO CLEAN TREE (issue 0186). Over an index git cannot read,
# rev-parse still names the commit and status fails, and the failure read as
# empty output: the bare sha, over a tree whose state nobody read.
@test "over an index git cannot read, the identity says the tree's state could not be read, never the bare sha (0186)" {
  repo="$(mkrepo)"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf 'edited\n' >>"$repo/file.txt"
  # THE CONTROL: with the index readable, the same tree is marked dirty.
  run git_head_identity "$repo"
  assert_success
  assert_output "$sha +dirty"
  break_git_index "$repo"
  run git_head_identity "$repo"
  assert_success
  assert_output "$sha +unreadable"
}

# IT SAYS +dirty AND NOT "THESE BYTES MATCH NO COMMIT". That sentence is
# lib/install's, and it makes a narrower claim about a VENDORED FILE SET which a
# consumer later reads out of a manifest (issue 0033). Borrowing it here would
# put a provenance claim on a checkout that never made one.
@test "the working-tree marker does NOT borrow the manifest's provenance sentence" {
  repo="$(mkrepo)"
  echo "uncommitted" > "$repo/scratch.txt"
  run git_head_identity "$repo"
  assert_success
  refute_output_contains "THESE BYTES MATCH NO COMMIT"
}

@test "a directory that is not a checkout has identity unknown, not an empty pair of brackets" {
  d="$DEVBIN_TEST_TMPDIR/plainident"
  mkdir -p "$d"
  run git_head_identity "$d"
  assert_success
  assert_output "unknown"
}

@test "a directory that is not a checkout reads as unknown rather than empty" {
  d="$DEVBIN_TEST_TMPDIR/plain"
  mkdir -p "$d"
  run git_head_sha "$d"
  assert_success
  assert_output "unknown"
}

# ============================================================================
# THE INVALIDATION HALF -- where four of four implementations were wrong
# ============================================================================

@test "every watch path resolved in a linked worktree actually exists" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  run git_head_watch_paths "$wt"
  assert_success

  # THE ASSERTION IS ON THE PATH SET, not on the sha. A watch set naming a file
  # that does not exist is the whole defect: Elixir registers no dependency and
  # freezes, cargo cannot stat it and rebuilds forever.
  [ -n "$output" ]
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || {
      echo "watch path does not exist: $p" >&2
      return 1
    }
  done <<<"$output"
}

@test "the branch ref is watched, and it is NOT under the worktree's own gitdir" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  run git_head_watch_paths "$wt"
  assert_success
  # A worktree's own HEAD holds `ref: refs/heads/<branch>`, which does not change
  # on a commit. The ref that MOVES lives in the COMMON directory, and a watch
  # set built only from the worktree's gitdir misses every commit.
  assert_output_contains "refs/heads/wtbranch"
}

@test "committing in the worktree changes something the watch set names" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  before=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    before="$before$(cat "$p" 2>/dev/null)"
  done <<<"$(git_head_watch_paths "$wt")"

  printf 'two\n' >"$wt/file.txt"
  git -C "$wt" commit -qam "second"

  after=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    after="$after$(cat "$p" 2>/dev/null)"
  done <<<"$(git_head_watch_paths "$wt")"
  # THE PROPERTY THE WHOLE THING EXISTS FOR: a build watching this set is told
  # that the sha moved. If the contents are identical after a commit, the watch
  # is decorative and the baked sha will never refresh.
  [ "$before" != "$after" ]
}

@test "a packed branch stays watchable after pack-refs deletes the loose file" {
  repo="$(mkrepo)"
  wt="$(mkworktree "$repo")"

  loose="$(git -C "$wt" rev-parse --git-path refs/heads/wtbranch)"
  [ -f "$loose" ]
  git -C "$repo" pack-refs --all
  # `git pack-refs` DELETES the loose ref file. A watch set built from loose
  # paths silently loses the branch it was watching, and nothing announces it.
  [ ! -f "$loose" ]

  run git_head_watch_paths "$wt"
  assert_success
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || {
      echo "watch path does not exist after pack-refs: $p" >&2
      return 1
    }
  done <<<"$output"
  assert_output_contains "packed-refs"
}

@test "a normal checkout resolves a watch set too" {
  repo="$(mkrepo)"
  run git_head_watch_paths "$repo"
  assert_success
  [ -n "$output" ]
}

# ============================================================================
# THE EMPTY SET IS THE FAILURE THAT MATTERS, AND IT MUST BE LOUD
# ============================================================================

@test "a directory that is not a checkout refuses loudly rather than emitting nothing" {
  d="$DEVBIN_TEST_TMPDIR/plain2"
  mkdir -p "$d"

  # THIS STATE IS CREATED BY THE FIX. Before it, a broken watch meant "always
  # rebuild", which hides as a cost. After it, a working watch restores caching
  # -- so an enumeration that silently returns nothing turns a slow-but-correct
  # build into a fast-and-possibly-wrong one. Same rule as a gate that examines
  # nothing: returning empty and succeeding is the unacceptable answer.
  run git_head_watch_paths "$d"
  assert_failure
  assert_output_contains "NO files"
}
