#!/usr/bin/env bats
# worktrees.bats - the built-in worktrees: a read-only report of each linked
# worktree, landed, held or unknown, with its evidence, and remove-landed
# (issue 0245).
#
# Every fixture is a committed project on main, its linked worktrees under
# tmp/wt/, which .gitignore leaves out of the main worktree. Each arm builds the
# one state it reads, so a verdict is never another state's.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a process of another user standing in a worktree, which the process
#     check cannot read either;
#   - a repository larger than a fixture, whose branch window or bank set is
#     read the same way and only takes longer;
#   - the Linux /proc route of the process check where lsof is on PATH, since
#     lsof is asked first wherever it is.

load "../lib/test_helper"

setup() {
  devbin_setup
  WT_SLEEPS="$DEVBIN_TEST_TMPDIR/sleeps"
}

# teardown -- every sleep an arm started in a worktree is killed, whatever the
# arm's verdict, then the temp dir goes.
teardown() {
  local pid
  if [ -f "${WT_SLEEPS:-}" ]; then
    while IFS= read -r pid; do
      [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
    done <"$WT_SLEEPS"
  fi
  devbin_teardown
}

# wt_git <git-args>... -- git with a committer, starting no background
# maintenance from a fixture commit.
wt_git() {
  git -c user.email=dev@test -c user.name=dev -c maintenance.auto=false -c gc.auto=0 "$@"
}

# wt_project [<name>] [<config-lines>] -- a committed fixture project on main,
# holding a.txt and b.txt, with <config-lines> after its project: block.
wt_project() {
  local name="${1:-demo}" proj
  proj="$(mkproj "$name" <<EOF
project:
  name: $name
${2:-}
EOF
  )"
  printf 'tmp/\n' >"$proj/.gitignore"
  printf '%s\n' one two three >"$proj/a.txt"
  printf '%s\n' alpha beta >"$proj/b.txt"
  git -C "$proj" init -q -b main
  git -C "$proj" add -A
  wt_git -C "$proj" commit -q -m first
  printf '%s\n' "$proj"
}

# wt_add <proj> <name> [<branch>] -- a linked worktree at tmp/wt/<name> of main,
# detached, or on a new <branch>; its path printed.
wt_add() {
  if [ -n "${3:-}" ]; then
    wt_git -C "$1" worktree add -q -b "$3" "tmp/wt/$2" main
  else
    wt_git -C "$1" worktree add -q --detach "tmp/wt/$2" main
  fi
  printf '%s\n' "$1/tmp/wt/$2"
}

# wt_land <proj> <file> <line>... -- <file> holding these lines, committed on
# main in the main worktree.
wt_land() {
  local proj="$1" file="$2"
  shift 2
  printf '%s\n' "$@" >"$proj/$file"
  wt_git -C "$proj" commit -q -am "land $file"
}

# wt_verdict <name> -- the verdict the last report in $output gives tmp/wt/<name>.
wt_verdict() {
  awk -v h="tmp/wt/$1: " 'index($0, h) == 1 { print substr($0, length(h) + 1) }' <<<"$output"
}

# wt_block <name> -- the last report's block for tmp/wt/<name>, its header to
# the blank line after it.
wt_block() {
  awk -v h="tmp/wt/$1: " 'index($0, h) == 1 { on = 1 } on && $0 == "" { exit } on { print }' <<<"$output"
}

# wt_has <name> <text> -- tmp/wt/<name>'s block holds <text>, or the arm fails
# naming the block.
wt_has() {
  local block
  block="$(wt_block "$1")"
  grep -qF -- "$2" <<<"$block" || fail "tmp/wt/$1's block does not say '$2':
$block

the whole report:
$output"
}

# wt_is <name> <verdict> -- tmp/wt/<name> reads <verdict>, or the arm fails.
wt_is() {
  [ "$(wt_verdict "$1")" = "$2" ] || fail "tmp/wt/$1 reads '$(wt_verdict "$1")', not '$2':
$output"
}

# wt_listed <proj> <name> -- true when git still lists tmp/wt/<name> as a
# worktree of <proj>.
wt_listed() {
  local list
  list="$(git -C "$1" worktree list --porcelain)" || fail "git cannot list the worktrees of $1"
  grep -qx "worktree $1/tmp/wt/$2" <<<"$list"
}

# wt_need_process_check -- skip where neither lsof nor /proc can read a
# process's directory, since the report can then only say it cannot tell.
wt_need_process_check() {
  command -v lsof >/dev/null 2>&1 || [ -r /proc/self/stat ] ||
    skip "neither lsof nor /proc is on this runner: the process check was NOT checked"
}

# wt_sleep_in <dir> -- a sleep whose working directory is <dir> from the moment
# it is forked, its pid in WT_SLEEP_PID, killed by teardown. Started from this
# shell after a cd, so its directory is set before the report can look, with
# its descriptors closed so bats does not wait on it.
wt_sleep_in() {
  local here="$PWD"
  cd "$1" || fail "cannot enter $1"
  sleep 300 </dev/null >/dev/null 2>&1 3>&- &
  WT_SLEEP_PID="$!"
  printf '%s\n' "$WT_SLEEP_PID" >>"$WT_SLEEPS"
  cd "$here" || fail "cannot return to $here"
}

# ============================================================================
# THE VERDICTS
# ============================================================================

@test "a staged bank the branch holds reads landed, with both landed tests shown (0245)" {
  local proj wt sha
  proj="$(wt_project)"
  wt="$(wt_add "$proj" landed)"
  printf '%s\n' one TWO three >"$wt/a.txt"
  git -C "$wt" add a.txt
  wt_land "$proj" a.txt one TWO three
  sha="$(git -C "$proj" rev-parse HEAD)"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is landed landed
  wt_has landed "content: main holds its content"
  wt_has landed "main's commit ${sha:0:12} has the same change"
  wt_has landed "on main by ancestry"
}

@test "unlanded staged work that no commit and no bank carries reads held (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" held)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is held held
  wt_has held "held: unlanded staged work"
  wt_has held "content: main lacks its content"
}

@test "a staged diff of content main holds, that no commit and no bank carries, reads unknown (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" copied)"
  printf '%s\n' one two THREE >"$wt/a.txt"
  git -C "$wt" add a.txt
  wt_land "$proj" a.txt one two TWO-STEP
  wt_land "$proj" a.txt one two THREE
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is copied unknown
  wt_has copied "no commit of main since the base, and no bank has the same change"
  wt_has copied "content: main holds its content"
}

@test "a staged diff a bank has, whose content the branch holds, reads landed (0245)" {
  local proj wt blob
  proj="$(wt_project demo "worktrees:
  banks:
    - refs/bank")"
  wt="$(wt_add "$proj" banked)"
  printf '%s\n' one TWO three >"$wt/a.txt"
  git -C "$wt" add a.txt
  blob="$(git -C "$wt" diff --cached HEAD | git -C "$proj" hash-object -w --stdin)"
  wt_git -C "$proj" update-ref refs/bank/unit/one "$blob"
  # The content lands in two steps, so no commit of main is the bank's change.
  wt_land "$proj" a.txt one TWO-STEP three
  wt_land "$proj" a.txt one TWO three
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is banked landed
  wt_has banked "the bank refs/bank/unit/one has the same change"
  wt_has banked "content: main holds its content"
}

@test "a bank blob carrying two patches is read as two, each staged diff matched to it, and the banks line names its count (0290)" {
  local proj one two blob text n
  proj="$(wt_project demo "worktrees:
  banks:
    - refs/bank")"
  one="$(wt_add "$proj" one)"
  two="$(wt_add "$proj" two)"
  printf '%s\n' one TWO three >"$one/a.txt"
  git -C "$one" add a.txt
  printf '%s\n' alpha BETA >"$two/b.txt"
  git -C "$two" add b.txt
  # The bank as `git log -p` writes two commits: each patch opened by its
  # commit line, which is where git patch-id starts a patch.
  text="$(printf 'commit %s\n\n%s\ncommit %s\n\n%s\n' \
    "$(git -C "$proj" rev-parse HEAD)" "$(git -C "$one" diff --cached HEAD)" \
    "$(git -C "$proj" rev-parse HEAD)" "$(git -C "$two" diff --cached HEAD)")"
  blob="$(git -C "$proj" hash-object -w --stdin <<<"$text")"
  wt_git -C "$proj" update-ref refs/bank/unit/pair "$blob"
  n="$(grep -c '^commit ' <<<"$text")"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_has one "the bank refs/bank/unit/pair has the same change"
  wt_has two "the bank refs/bank/unit/pair has the same change"
  assert_output_contains "refs/bank/unit/pair holds $n patches, each read as this bank's"
  # The banks line counts what the fixture made: its one ref, and the patches
  # that ref carries.
  assert_output_contains "banks: refs/bank, $(git -C "$proj" for-each-ref refs/bank | grep -c .) read, holding $n patches"
}

@test "a bank pattern ending in a glob matches a bank one level down and not a deeper one, as git for-each-ref does (0245)" {
  local proj wt blob
  proj="$(wt_project demo "worktrees:
  banks:
    - refs/bank/*")"
  wt="$(wt_add "$proj" shallow)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  blob="$(git -C "$wt" diff --cached HEAD | git -C "$proj" hash-object -w --stdin)"
  wt_git -C "$proj" update-ref refs/bank/one "$blob"
  wt="$(wt_add "$proj" deep)"
  printf '%s\n' one two THREE >"$wt/a.txt"
  git -C "$wt" add a.txt
  blob="$(git -C "$wt" diff --cached HEAD | git -C "$proj" hash-object -w --stdin)"
  wt_git -C "$proj" update-ref refs/bank/unit/deep "$blob"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_has shallow "the bank refs/bank/one has the same change"
  wt_has deep "no commit of main since the base, and no bank has the same change"
}

@test "a diff is read as git's own whatever diff.external or GIT_EXTERNAL_DIFF names, so unlanded work never reads landed (0245)" {
  local proj wt cfg
  proj="$(wt_project)"
  wt="$(wt_add "$proj" held)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  cfg="$DEVBIN_TEST_TMPDIR/gitconfig"
  printf '[diff]\n\texternal = true\n' >"$cfg"
  GIT_CONFIG_GLOBAL="$cfg" run devbin_run "$proj" worktrees report
  assert_success
  wt_is held held
  wt_has held "1 file(s): b.txt"
  GIT_EXTERNAL_DIFF=true run devbin_run "$proj" worktrees report
  assert_success
  wt_is held held
  wt_has held "1 file(s): b.txt"
}

@test "a process check that cannot tell reads unknown, and remove-landed refuses it (0245)" {
  local proj wt shim
  proj="$(wt_project)"
  wt="$(wt_add "$proj" blind)"
  # An lsof that fails: asked first wherever it is on PATH, /proc on Linux
  # included, so this route is reached on every runner.
  shim="$DEVBIN_TEST_TMPDIR/blindshim"
  mkdir -p "$shim"
  printf '#!/bin/sh\necho "lsof: cannot read the process table" >&2\nexit 1\n' >"$shim/lsof"
  chmod +x "$shim/lsof"
  PATH="$shim:$PATH" run devbin_run "$proj" worktrees report
  assert_success
  wt_is blind unknown
  wt_has blind "the process check could not tell whether anything stands in it"
  PATH="$shim:$PATH" run devbin_run "$proj" worktrees remove-landed tmp/wt/blind
  assert_failure
  assert_output_contains "refused  tmp/wt/blind: unknown"
  wt_listed "$proj" blind || fail "a worktree the process check could not clear was removed"
  assert_directory_exists "$wt"
}

@test "untracked files read unknown, each named (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" untracked)"
  : >"$wt/notes.txt"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is untracked unknown
  wt_has untracked "unknown: untracked files, which may be real work: notes.txt"
}

@test "a stash entry naming a worktree reads held, naming the entry, after its HEAD has moved on (0245)" {
  local proj wt entry
  proj="$(wt_project)"
  wt="$(wt_add "$proj" stashed stashed)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  wt_git -C "$wt" stash -q
  entry="$(git -C "$proj" stash list --format=%gd)"
  [ -n "$entry" ] || fail "the fixture's stash holds no entry"
  # A commit in it moves its HEAD off the stash's first parent, so only the
  # branch the stash names can hold it.
  printf '%s\n' one two three four >"$wt/a.txt"
  wt_git -C "$wt" commit -q -am "moved on"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is stashed held
  wt_has stashed "held: a stash entry names it: $entry"
}

@test "a stash made detached names the detached worktrees at its first parent, each reading held (0245)" {
  local proj wt entry
  proj="$(wt_project)"
  wt="$(wt_add "$proj" detached)"
  wt_add "$proj" beside >/dev/null
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  wt_git -C "$wt" stash -q
  entry="$(git -C "$proj" stash list --format=%gd)"
  [ -n "$entry" ] || fail "the fixture's stash holds no entry"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is detached held
  wt_has detached "held: a stash entry names it: $entry"
  wt_is beside held
  wt_has beside "held: a stash entry names it: $entry"
}

@test "a process standing in a worktree reads unknown, naming its pid (0245)" {
  local proj wt
  wt_need_process_check
  proj="$(wt_project)"
  wt="$(wt_add "$proj" busy)"
  wt_sleep_in "$wt"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is busy unknown
  wt_has busy "pid $WT_SLEEP_PID"
  wt_has busy "unknown: a process stands in it"
}

@test "the report leaves out its own processes when it is run from inside a worktree (0245)" {
  local proj wt
  wt_need_process_check
  proj="$(wt_project)"
  wt="$(wt_add "$proj" inside)"
  run bash -c 'cd "$1" && exec "$2" worktrees report .' _ "$wt" "$proj/bin/devbin"
  assert_success
  wt_is inside landed
  wt_has inside "processes  none"
}

@test "a staged diff a bank has and the branch lacks reads unknown, naming the bank (0245)" {
  local proj wt blob
  proj="$(wt_project demo "worktrees:
  banks:
    - refs/bank")"
  wt="$(wt_add "$proj" banked)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  blob="$(git -C "$wt" diff --cached HEAD | git -C "$proj" hash-object -w --stdin)"
  wt_git -C "$proj" update-ref refs/bank/unit/one "$blob"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is banked unknown
  wt_has banked "the bank refs/bank/unit/one has the same change"
  wt_has banked "whether that bank is live or superseded"
  wt_has banked "content: main lacks its content"
}

@test "a staged diff no commit and no bank carries, landed with edits, reads unknown (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" edited)"
  printf '%s\n' one two THREE >"$wt/a.txt"
  git -C "$wt" add a.txt
  wt_land "$proj" a.txt one two "THREE, with an edit"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is edited unknown
  wt_has edited "no commit of main since the base, and no bank has the same change"
  wt_has edited "content: its content conflicts with main's"
}

@test "own commits that read not on main by patch-id, though main holds their content, read unknown with both tests shown (0245)" {
  local proj wt own
  proj="$(wt_project)"
  wt="$(wt_add "$proj" own own)"
  printf '%s\n' ONE two three >"$wt/a.txt"
  printf '%s\n' ALPHA beta >"$wt/b.txt"
  wt_git -C "$wt" commit -q -am both
  own="$(git -C "$wt" rev-parse HEAD)"
  # The same content, landed in two commits, so no one of them is its change.
  wt_land "$proj" a.txt ONE two three
  wt_land "$proj" b.txt ALPHA beta
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is own unknown
  wt_has own "+ ${own:0:12} both"
  wt_has own "content: main holds the content of base..HEAD"
  wt_has own "unknown: its own commits read not on main by patch-id, and main holds their content"
}

@test "landed content left unstaged reads unknown (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" unstaged)"
  printf '%s\n' one TWO three >"$wt/a.txt"
  wt_land "$proj" a.txt one TWO three
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is unstaged unknown
  wt_has unstaged "unknown: landed content left unstaged"
  wt_has unstaged "content: main holds its content"
}

@test "a build target linked in from another tree reads landed and is listed as a link (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" linked)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/shared"
  ln -s "$DEVBIN_TEST_TMPDIR/shared" "$wt/target"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is linked landed
  wt_has linked "target -> $DEVBIN_TEST_TMPDIR/shared"
  wt_has linked "untracked  none"
}

@test "a locked worktree shows its lock and reason, and remove-landed refuses it, removing nothing (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" kept)"
  git -C "$proj" worktree lock --reason "kept for later runs" "$wt"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_has kept "locked     yes: kept for later runs"
  run devbin_run "$proj" worktrees remove-landed tmp/wt/kept
  assert_failure
  assert_output_contains "refused  tmp/wt/kept: locked, kept on purpose: kept for later runs"
  wt_listed "$proj" kept || fail "the locked worktree is no longer listed"
  assert_directory_exists "$wt"
}

@test "a worktree whose directory is gone reads prunable, naming git worktree prune, and remove-landed refuses it as not a directory (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" gone)"
  rm -rf "$wt"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is gone prunable
  wt_has gone "remedy: git worktree prune"
  run devbin_run "$proj" worktrees remove-landed tmp/wt/gone
  assert_failure
  assert_output_contains "refused  tmp/wt/gone: not a directory"
  wt_listed "$proj" gone || fail "remove-landed pruned the record it refused"
}

# ============================================================================
# PLAIN DIRECTORIES
# ============================================================================

@test "plain directories beside the worktrees are reported with their size and no verdict (0245)" {
  local proj
  proj="$(wt_project)"
  wt_add "$proj" landed >/dev/null
  mkdir -p "$proj/tmp/wt/stray"
  printf 'left behind\n' >"$proj/tmp/wt/stray/file"
  run devbin_run "$proj" worktrees report
  assert_success
  assert_output_line "tmp/wt/stray: plain directory, no verdict -- git lists no worktree here"
  wt_has stray "size  "
  wt_has stray " KiB"
}

@test "a worktree made directly in the project root lists none of the project's own directories as plain (0245)" {
  local proj
  proj="$(wt_project)"
  wt_git -C "$proj" worktree add -q --detach "$proj/side" main
  run devbin_run "$proj" worktrees report
  assert_success
  assert_output_contains "side: "
  refute_output_contains "plain directory"
}

@test "the summary counts each verdict as the blocks give it (0245)" {
  local proj wt v want n
  proj="$(wt_project)"
  wt_add "$proj" clean >/dev/null
  wt="$(wt_add "$proj" held)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  wt="$(wt_add "$proj" untracked)"
  : >"$wt/notes.txt"
  wt="$(wt_add "$proj" gone)"
  rm -rf "$wt"
  mkdir -p "$proj/tmp/wt/stray"
  run devbin_run "$proj" worktrees report
  assert_success
  # The linked worktrees git lists: every one below the project, the main one aside.
  want="$(git -C "$proj" worktree list --porcelain | grep -c "^worktree $proj/")"
  want="worktrees: $want linked worktree(s) reported:"
  for v in landed held unknown prunable unread; do
    n="$(awk -v v="$v" '/^tmp\/wt\/[^ ]*: / { if ($2 == v) c++ } END { print c + 0 }' <<<"$output")"
    want="$want $n $v,"
  done
  n="$(grep -c ': plain directory, no verdict' <<<"$output")"
  want="${want%,}; $n plain director(ies)"
  assert_output_line "$want"
}

# ============================================================================
# REMOVE-LANDED
# ============================================================================

@test "remove-landed removes exactly the landed worktrees, by reset and a plain worktree remove, and refuses each other naming why (0245)" {
  local proj wt real log name n=0 removes
  local -a landed=(staged linked) other=(held untracked)
  proj="$(wt_project)"
  wt="$(wt_add "$proj" staged)"
  printf '%s\n' one TWO three >"$wt/a.txt"
  git -C "$wt" add a.txt
  wt="$(wt_add "$proj" linked)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/shared"
  printf 'kept\n' >"$DEVBIN_TEST_TMPDIR/shared/file"
  ln -s "$DEVBIN_TEST_TMPDIR/shared" "$wt/target"
  wt="$(wt_add "$proj" held)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  wt="$(wt_add "$proj" untracked)"
  : >"$wt/notes.txt"
  wt_land "$proj" a.txt one TWO three
  # Every git the run starts is logged, so a --force anywhere is seen.
  real="$(command -v git)"
  log="$DEVBIN_TEST_TMPDIR/git.log"
  mkdir -p "$DEVBIN_TEST_TMPDIR/shim"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexec "%s" "$@"\n' "$log" "$real" >"$DEVBIN_TEST_TMPDIR/shim/git"
  chmod +x "$DEVBIN_TEST_TMPDIR/shim/git"
  PATH="$DEVBIN_TEST_TMPDIR/shim:$PATH" run devbin_run "$proj" worktrees remove-landed \
    "${landed[@]/#/tmp/wt/}" "${other[@]/#/tmp/wt/}"
  assert_failure
  for name in "${landed[@]}"; do
    assert_output_line "removed  tmp/wt/$name"
    ! wt_listed "$proj" "$name" || fail "tmp/wt/$name is still listed"
    assert_directory_not_exists "$proj/tmp/wt/$name"
  done
  assert_output_contains "refused  tmp/wt/held: held"
  assert_output_contains "refused  tmp/wt/untracked: unknown"
  for name in "${other[@]}"; do
    wt_listed "$proj" "$name" || fail "tmp/wt/$name was removed"
    assert_directory_exists "$proj/tmp/wt/$name"
  done
  assert_file_exists "$DEVBIN_TEST_TMPDIR/shared/file"
  assert_output_line "unlinked tmp/wt/linked/target"
  grep -q -- ' reset --hard --quiet' "$log" || fail "the staged worktree was not reset: $(cat "$log")"
  ! grep -q -- '--force' "$log" || fail "a git call passed --force: $(grep -- '--force' "$log")"
  removes="$(grep -c ' worktree remove ' "$log")" || removes=0
  [ "$removes" -eq "${#landed[@]}" ] || fail "git worktree remove ran $removes time(s), for ${#landed[@]} landed worktree(s): $(cat "$log")"
  [ -z "$(git -C "$proj" stash list)" ] || fail "the stash moved"
}

@test "remove-landed refuses a worktree a stash names and one a process stands in, and git's state is as it was (0245)" {
  local proj wt stash_before stash_after list_before list_after
  wt_need_process_check
  proj="$(wt_project)"
  wt="$(wt_add "$proj" stashed stashed)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  wt_git -C "$wt" stash -q
  wt="$(wt_add "$proj" busy)"
  wt_sleep_in "$wt"
  stash_before="$(git -C "$proj" stash list --format='%gd %H')"
  list_before="$(git -C "$proj" worktree list --porcelain)"
  run devbin_run "$proj" worktrees remove-landed tmp/wt/stashed tmp/wt/busy
  assert_failure
  assert_output_contains "refused  tmp/wt/stashed: held"
  assert_output_contains "refused  tmp/wt/busy: unknown"
  assert_output_contains "pid $WT_SLEEP_PID"
  stash_after="$(git -C "$proj" stash list --format='%gd %H')"
  list_after="$(git -C "$proj" worktree list --porcelain)"
  [ "$stash_after" = "$stash_before" ] || fail "the stash moved:
$stash_before
now:
$stash_after"
  [ "$list_after" = "$list_before" ] || fail "the worktree list moved:
$list_before
now:
$list_after"
}

@test "remove-landed reports git's refusal of worktree remove as a finding, and forces nothing (0245)" {
  local proj wt real shim
  proj="$(wt_project)"
  wt="$(wt_add "$proj" late)"
  # A file appears in the worktree between the read and the remove, as work
  # landing late would, so git itself refuses the plain remove.
  real="$(command -v git)"
  shim="$DEVBIN_TEST_TMPDIR/lateshim"
  mkdir -p "$shim"
  printf '#!/bin/sh\ncase "$*" in *"worktree remove "*) for a in "$@"; do last="$a"; done; : >"$last/late.txt" ;; esac\nexec "%s" "$@"\n' "$real" >"$shim/git"
  chmod +x "$shim/git"
  PATH="$shim:$PATH" run devbin_run "$proj" worktrees remove-landed tmp/wt/late
  assert_failure
  assert_output_contains "refused  tmp/wt/late: git refused to remove it, which is a finding, not something to force"
  wt_listed "$proj" late || fail "the worktree git refused to remove is gone"
  assert_file_exists "$wt/late.txt"
}

@test "remove-landed refuses a worktree the run itself stands in, its devbin runtime inside it, and removes nothing (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" running)"
  [ -f "$wt/bin/.devbin/lib/cmd/worktrees" ] || fail "the fixture's worktree holds no devbin runtime to run from"
  # The handler run from the worktree's own runtime, the caller outside it.
  run env PROJECT_ROOT="$proj" DEVBIN_DIR="$proj/bin/.devbin" DEVBIN_LIB="$wt/bin/.devbin/lib" \
    bash -c 'cd "$1" && exec bash "$2" remove-landed "$3"' _ "$proj" "$wt/bin/.devbin/lib/cmd/worktrees" "$wt"
  assert_failure
  assert_output_contains "this run itself stands in it"
  wt_listed "$proj" running || fail "the run removed the tree it ran from"
  assert_directory_exists "$wt"
}

@test "remove-landed refuses a worktree the caller stands in, and removes nothing (0245)" {
  local proj wt
  proj="$(wt_project)"
  wt="$(wt_add "$proj" here)"
  run bash -c 'cd "$1" && exec "$2" worktrees remove-landed .' _ "$wt" "$proj/bin/devbin"
  assert_failure
  assert_output_contains "refused  .: you are standing in it"
  wt_listed "$proj" here || fail "the worktree the caller stands in was removed"
  assert_directory_exists "$wt"
}

@test "remove-landed refuses the main worktree and a path that is no linked worktree (0245)" {
  local proj
  proj="$(wt_project)"
  wt_add "$proj" landed >/dev/null
  mkdir -p "$proj/tmp/wt/stray"
  run devbin_run "$proj" worktrees remove-landed . tmp/wt/stray
  assert_failure
  assert_output_contains "refused  .: the main worktree, which is never removed"
  assert_output_contains "refused  tmp/wt/stray: not a linked worktree of $proj"
  assert_directory_exists "$proj/tmp/wt/stray"
  wt_listed "$proj" landed || fail "a worktree nobody named was removed"
}

# ============================================================================
# --repo, AND WHERE IT IS NOT AVAILABLE
# ============================================================================

@test "report --repo reads another repository as that repository's own report reads it (0245)" {
  local here there wt
  here="$(wt_project here)"
  there="$(wt_project there)"
  wt="$(wt_add "$there" held)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  wt_add "$there" landed >/dev/null
  run devbin_run "$there" worktrees report
  assert_success
  local own="$output"
  [ -n "$(wt_verdict held)" ] || fail "the other repository's own report names no worktree:
$own"
  run devbin_run "$here" worktrees report --repo "$there"
  assert_success
  [ "$output" = "$own" ] || fail "read through --repo:
$output

read in place:
$own"
}

@test "remove-landed refuses --repo, and removes nothing (0245)" {
  local here there
  here="$(wt_project here)"
  there="$(wt_project there)"
  wt_add "$there" landed >/dev/null
  run devbin_run "$here" worktrees remove-landed --repo "$there" "$there/tmp/wt/landed"
  assert_failure
  assert_output_contains "remove-landed takes no --repo"
  wt_listed "$there" landed || fail "a worktree of the other repository was removed"
}

@test "report --repo naming a directory that is no git checkout is refused, exit 1 (0245)" {
  local here plain
  here="$(wt_project here)"
  plain="$DEVBIN_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  run devbin_run "$here" worktrees report --repo "$plain"
  assert_exit_code 1
  assert_output_contains "is not a git checkout -- name the directory of a repository"
}

@test "worktrees outside a git checkout is not available here, exit 2 (0245)" {
  local proj
  proj="$(mkproj demo <<'EOF'
project:
  name: demo
EOF
  )"
  run devbin_run "$proj" worktrees report
  assert_exit_code 2
  assert_output_contains "is not a git checkout, so it has no linked worktrees to report"
}

@test "worktrees.branch names the branch landed work reaches, and one the repository lacks is refused naming the key (0245)" {
  local proj
  proj="$(wt_project demo "worktrees:
  branch: trunk")"
  wt_add "$proj" landed >/dev/null
  run devbin_run "$proj" worktrees report
  assert_failure
  assert_output_contains "trunk (worktrees.branch, default main) is no branch of the repository"
  wt_git -C "$proj" branch trunk main
  run devbin_run "$proj" worktrees report
  assert_success
  assert_output_contains "landing on trunk at"
  wt_has landed "on trunk by ancestry"
}

@test "a TMPDIR inside the main worktree is refused when the run is a linked worktree's own, and nothing is left there (0245)" {
  local proj wt scratch
  proj="$(wt_project)"
  wt="$(wt_add "$proj" linkedproj)"
  scratch="$proj/tmp/scratch"
  mkdir -p "$scratch"
  TMPDIR="$scratch" run bash -c 'cd "$1" && exec ./bin/devbin worktrees report' _ "$wt"
  assert_failure
  assert_output_contains "is inside the worktree $proj,"
  [ -z "$(ls -A "$scratch")" ] || fail "a scratch was left inside the main worktree: $(ls -A "$scratch")"
}

# ============================================================================
# READ-ONLY
# ============================================================================

@test "the report writes nothing under the repository's git directory, a stale index's included (0245)" {
  local proj wt marker written
  proj="$(wt_project)"
  wt="$(wt_add "$proj" stale)"
  printf '%s\n' alpha beta gamma >"$wt/b.txt"
  git -C "$wt" add b.txt
  # Stat-stale: the tracked file is older than its index entry says, and
  # everything under .git is older than the marker.
  touch -t 200001010000 "$wt/a.txt" "$proj/a.txt"
  find "$proj/.git" -exec touch -h -t 200001010000 {} +
  marker="$DEVBIN_TEST_TMPDIR/marker"
  touch -t 200101010000 "$marker"
  run devbin_run "$proj" worktrees report
  assert_success
  wt_is stale held
  written="$(find "$proj/.git" -newer "$marker")"
  [ -z "$written" ] || fail "the report wrote under .git: $written"
}
