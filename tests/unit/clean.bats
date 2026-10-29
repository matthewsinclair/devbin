#!/usr/bin/env bats
# clean.bats - the built-in `clean` and every refusal it ships
#
# Each arm below was paid for by a real failure, and each one is asserted in
# BOTH directions: the condition present must refuse, and the condition absent
# must proceed. A refusal test with no negative control passes against a command
# that refuses everything, which is a worse outage than the one it prevents.
#
# WHAT THIS SUITE IS GREEN OVER, STATED RATHER THAN LEFT TO BE ASSUMED. Every
# fixture here is built with mkdir and touch, so what is proven is that the
# classifier matches a directory SHAPED like a build tree. It is not proven that
# real cargo still writes those markers -- nothing here runs cargo. The last
# test in this file makes that gap PRINT rather than leaving it to be inferred
# from the absence of a test, which is the whole lesson of a suite that was
# green at 12/12 while structurally blind to the class it was meant to cover.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  init_colors off
}
teardown() { devbin_teardown; }


rustproj() {
  mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
}

# A cargo target tree, complete with the markers cargo writes and the manifest
# that proves it can be rebuilt.
mktarget() {
  local at="$1"
  mkdir -p "$at/target/debug/.fingerprint" "$at/target/release"
  cargo_tag "$at/target"
  : >"$at/Cargo.toml"
}

runclean() {
  local proj="$1"
  shift
  run env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$proj/bin/.devbin/lib/cmd/clean" "$@"
}

# The same, with PATH overridden FOR THE CHILD ONLY. Setting PATH in the test
# process and then invoking `env` cannot work -- the shell can no longer find
# `env`, and the resulting "command not found" reads exactly like the refusal
# the test is asserting. Caught by the test failing for the wrong reason.
runclean_path() {
  local proj="$1" newpath="$2" bash_bin
  shift 2
  # The interpreter is resolved from the REAL PATH first. `#!/usr/bin/env bash`
  # cannot start under a broken PATH -- env fails to find bash and the script
  # never runs, which produces "No such file or directory" and reads exactly
  # like the refusal being asserted. Found by the test failing for the wrong
  # reason, which is the only thing that separates the two.
  bash_bin="$(command -v bash)"
  run env PATH="$newpath" DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$bash_bin" "$proj/bin/.devbin/lib/cmd/clean" "$@"
}

# ---------------------------------------------------------------------------
# ARM -- a live PATH dependency is a refusal, not a warning
# ---------------------------------------------------------------------------

@test "clean REFUSES when a PATH symlink resolves into the tree it would remove" {
  proj="$(rustproj)"
  mktarget "$proj"
  # The measured shape: a consumer's daemon resolved through target/debug, so a
  # comprehensive clean would have darkened the live binary machine-wide.
  : >"$proj/target/debug/myappd"
  chmod +x "$proj/target/debug/myappd"
  mkdir -p "$proj/fakebin"
  ln -s "$proj/target/debug/myappd" "$proj/fakebin/myappd"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust
  assert_failure
  assert_output_contains "myappd"
  assert_output_contains "refusing"
  # THE REFUSAL MUST NOT HAVE REMOVED ANYTHING FIRST.
  assert_directory_exists "$proj/target"
}

# THE MISCOUNT. A cargo tree ordinarily carries the same binary in BOTH debug/
# and release/, and the scan keyed on the basename before resolving through
# PATH -- so one at-risk binary was listed once per location holding its name.
# Measured in Intent: `intent` and `intentd` reported four lines for two
# binaries. The line claims "one binary that goes dark", so a doubled list
# overstates the risk an operator is weighing when they decide about --force.
@test "a binary present in BOTH debug/ and release/ is listed ONCE, not once per copy" {
  proj="$(rustproj)"
  mktarget "$proj"
  for sub in debug release; do
    : >"$proj/target/$sub/twicely"
    chmod +x "$proj/target/$sub/twicely"
  done
  outside="$DEVBIN_TEST_TMPDIR/dupbin"
  mkdir -p "$outside"
  ln -s "$proj/target/release/twicely" "$outside/twicely"

  PATH="$outside:$PATH" runclean "$proj" rust

  assert_failure
  assert_output_contains "twicely"
  # ONE line naming it, not two. Counting the lines is the assertion: asserting
  # only that the name appears passes just as well against the doubled output.
  local n
  n="$(printf '%s\n' "$output" | grep -c "twicely ->" || true)"
  [ "$n" -eq 1 ] || fail "expected the binary listed once, got $n line(s):
$output"
}

# THE ORDER IS PART OF THE REPORT, and until this arm existed the scan's comment
# claimed a rationale nothing enforced -- swapping the in-order dedupe for
# `sort -u` deduped correctly and passed every other test here. The two branches
# answer different questions (a PATH element sitting INSIDE the tree, versus a
# binary the tree PROVIDES to a PATH element outside it), so interleaving them
# alphabetically buries the distinction an operator is reading for.
@test "the kinds of live-PATH finding stay grouped, not interleaved" {
  proj="$(rustproj)"
  mktarget "$proj"
  # (a) a PATH element that is itself inside the tree
  mkdir -p "$proj/target/debug/bin"
  # (b) a binary the tree provides to a PATH element outside it
  : >"$proj/target/release/zzprovided"
  chmod +x "$proj/target/release/zzprovided"
  # NAMED TO SORT FIRST. The previous fixture used a name that sorted AFTER the
  # project's own path, so a sorted dedupe happened to emit the same order and
  # the arm passed against both implementations -- proving nothing. Driving the
  # break is what exposed it; the assertion had looked fine.
  outside="$DEVBIN_TEST_TMPDIR/aaa_outside"
  mkdir -p "$outside"
  ln -s "$proj/target/release/zzprovided" "$outside/zzprovided"

  PATH="$proj/target/debug/bin:$outside:$PATH" runclean "$proj" rust

  assert_failure
  local a b
  a="$(grep -n -m1 '(PATH entry)' <<<"$output" | cut -d: -f1)"
  b="$(grep -n -m1 'zzprovided ->' <<<"$output" | cut -d: -f1)"
  [ -n "$a" ] || fail "branch (a) produced no line:
$output"
  [ -n "$b" ] || fail "branch (b) produced no line:
$output"
  # Alphabetically the provided binary would sort first, so this fails under a
  # sorted dedupe and holds under an in-order one.
  [ "$a" -lt "$b" ] || fail "branches interleaved: (a) at $a, (b) at $b
$output"
}

# The shape above is the one that was MEASURED, and it differs from an
# installed tool's on three axes at once: its PATH entry sits inside the
# project, it resolves through debug/, and the target is at <proj>/target.
# Intent's is none of those -- ~/.local/bin is outside the tree, the artefact is
# in release/, and the target is nested at native/rust/target. All three are in
# arm (b)'s reach, and a test that exercises none of them is not evidence that
# they are. Measured when a cargo rebuild in that tree dangled both PATH
# symlinks and opened a ~4 minute ungated window across every project carrying
# its hooks; a `clean rust --force` there makes the same window permanent.
@test "the INSTALLED-TOOL shape: PATH entry OUTSIDE the tree, release/, nested target" {
  proj="$(rustproj)"
  mkdir -p "$proj/native/rust/target/debug/.fingerprint" "$proj/native/rust/target/release"
  cargo_tag "$proj/native/rust/target"
  : >"$proj/native/rust/Cargo.toml"
  : >"$proj/native/rust/target/release/intentish"
  chmod +x "$proj/native/rust/target/release/intentish"
  outside="$DEVBIN_TEST_TMPDIR/outside/bin"
  mkdir -p "$outside"
  ln -s "$proj/native/rust/target/release/intentish" "$outside/intentish"

  PATH="$outside:$PATH" runclean "$proj" rust
  assert_failure
  assert_output_contains "intentish"
  assert_output_contains "refusing"
  assert_directory_exists "$proj/native/rust/target"
}

# THE COST OF --force, STATED AS AN ASSERTION RATHER THAN A CAUTION. The last
# line is the ungated window in miniature: a link that still exists and no
# longer resolves. --force is allowed to do this; it is not allowed to do it
# quietly, which is what the name assertion above pins.
@test "the INSTALLED-TOOL shape under --force: proceeds, NAMES it, and leaves the link dangling" {
  proj="$(rustproj)"
  mkdir -p "$proj/native/rust/target/debug/.fingerprint" "$proj/native/rust/target/release"
  cargo_tag "$proj/native/rust/target"
  : >"$proj/native/rust/Cargo.toml"
  : >"$proj/native/rust/target/release/intentish"
  chmod +x "$proj/native/rust/target/release/intentish"
  outside="$DEVBIN_TEST_TMPDIR/outside/bin"
  mkdir -p "$outside"
  ln -s "$proj/native/rust/target/release/intentish" "$outside/intentish"

  PATH="$outside:$PATH" runclean "$proj" rust --force
  assert_success
  assert_output_contains "intentish"
  assert_directory_not_exists "$proj/native/rust/target"
  [ -L "$outside/intentish" ] && [ ! -e "$outside/intentish" ]
}

@test "clean PROCEEDS when no PATH entry resolves into the tree -- the arm's negative control" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/fakebin"
  : >"$proj/fakebin/unrelated"
  chmod +x "$proj/fakebin/unrelated"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust --force
  assert_success
  assert_directory_not_exists "$proj/target"
}

# THE WINDOWS PATH (ST0008 AC-4.1). Under WSL, PATH ends in entries whose
# names carry spaces and parentheses. The scan splits on colons alone, so an
# entry inside the tree with such a name is still the one entry, named whole;
# a split on blanks would make it pieces that name nothing. Both arms held when
# written: they keep the scan as it is.
# AT-4.1
@test "with the Windows PATH appended, a PATH entry inside the tree whose name carries spaces and parentheses is named whole and refused (ST0008 AC-4.1)" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/target/release/In Tree (x86)"
  wp="$(windows_path)"

  PATH="$wp:$proj/target/release/In Tree (x86)" runclean "$proj" rust
  assert_failure
  assert_output_contains "In Tree (x86) (PATH entry)"
  assert_directory_exists "$proj/target"
  refute_windows_exe_ran
}

# AT-4.1
@test "with the Windows PATH appended and nothing of the tree on it, clean proceeds and runs no .exe (ST0008 AC-4.1)" {
  proj="$(rustproj)"
  mktarget "$proj"
  wp="$(windows_path)"

  PATH="$wp" runclean "$proj" rust --force
  assert_success
  assert_directory_not_exists "$proj/target"
  refute_windows_exe_ran
}

@test "--force overrides the refusal and NAMES what goes dark" {
  proj="$(rustproj)"
  mktarget "$proj"
  : >"$proj/target/debug/myappd"
  chmod +x "$proj/target/debug/myappd"
  mkdir -p "$proj/fakebin"
  ln -s "$proj/target/debug/myappd" "$proj/fakebin/myappd"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust --force
  assert_success
  assert_output_contains "myappd"
  assert_output_contains "WILL STOP RESOLVING"
  assert_directory_not_exists "$proj/target"
}

# ---------------------------------------------------------------------------
# ARM -- the PATH scan's own positive control
# ---------------------------------------------------------------------------

@test "a BROKEN PATH SPLITTER is caught by the two-instrument control" {
  proj="$(rustproj)"
  mktarget "$proj"

  # BREAK THE CONTROL AND WATCH IT GO RED. This is the second of the two
  # questions IN-AG-RED-CONTROL-001 asks -- not "would it have failed" but
  # "COULD it" -- and the only way to answer it is to break the thing.
  #
  # The substitution reproduces the measured defect exactly: a scan in Intent
  # used `${PATH//:/$'\n'}`, which under zsh does not expand, so the loop
  # received ONE unparseable element and ran zero times while `command -v`
  # resolved into a target dir one line later. `split=("$PATH")` is that same
  # one-element state, arrived at deterministically, in place of clean's call
  # to colon_split, the one splitter (0248).
  local f="$proj/bin/.devbin/lib/cmd/clean"
  sed 's#colon_split "$PATH" split#split=("$PATH")#' "$f" >"$f.broken"
  mv "$f.broken" "$f"
  chmod +x "$f"
  grep -q 'split=("$PATH")' "$f" || fail "the fixture did not actually break the splitter"

  runclean "$proj" rust --force
  assert_failure
  assert_output_contains "PATH scan is unreliable"
  # AND IT REFUSED BEFORE REMOVING ANYTHING.
  assert_directory_exists "$proj/target"
}

@test "the unbroken splitter agrees with its second instrument -- the control's negative arm" {
  proj="$(rustproj)"
  mktarget "$proj"
  # Same fixture, same command, splitter untouched. A control that fires on a
  # healthy input is an outage of its own, and refusing every clean would be a
  # worse one than the defect it guards.
  runclean "$proj" rust --force
  assert_success
  refute_output_contains "PATH scan is unreliable"
  assert_directory_not_exists "$proj/target"
}

@test "clean reads a PATH holding an entry with a newline in it, and names each entry after it inside the tree, one with a newline in its name named whole (0248)" {
  # A shell reads such a PATH at its colons alone. The split stopped at the
  # newline and the line count beside it did not, so clean refused it as
  # unreliable, and the entries after the newline went unread. The scan for a
  # PATH entry inside the tree reads the split itself, its records ended by a
  # NUL, so a directory in the tree whose name holds a newline is one entry,
  # named whole, quoted as clean quotes such a name.
  local odd nl shown
  proj="$(rustproj)"
  mktarget "$proj"
  odd="$DEVBIN_TEST_TMPDIR/odd"$'\n'"dir"
  nl="$proj/target/debug/nl"$'\n'"bin"
  mkdir -p "$odd" "$nl"
  shown="$(printf '%q' "$nl")"

  PATH="$odd:$proj/target/debug:$nl:$PATH" runclean "$proj" rust
  refute_output_contains "PATH scan is unreliable"
  assert_failure
  assert_output_contains "$proj/target/debug (PATH entry)"
  assert_output_contains "$shown (PATH entry)"
  assert_output_contains "refusing"
  assert_directory_exists "$proj/target"
}

@test "the no-existing-directory branch declares that no test can reach it" {
  # The other half of the arm-2 control fires when PATH parses correctly but
  # holds no directory that exists. It cannot be tested by setting such a PATH:
  # `lib/builtins` calls awk, `env` resolves the interpreter, and the whole
  # runtime is upstream of the scan -- so breaking PATH kills the command long
  # before the control is reached. Measured, not assumed: the first version of
  # this test failed with "awk: command not found".
  #
  # Declared rather than deleted, because a branch with no test and no note
  # reads as a branch that was tested.
  grep -q "the scan is blind, not clean" "$DEVBIN_LIB_DIR/cmd/clean" ||
    fail "the no-existing-directory refusal is gone from lib/cmd/clean"
  echo "# the PATH scan's no-existing-dir branch is UNREACHABLE from a" >&3
  echo "# test: the runtime itself resolves through PATH. Asserted by inspection." >&3
}

# ---------------------------------------------------------------------------
# ARM -- unbounded enumeration, classified by content
# ---------------------------------------------------------------------------

@test "a target tree five levels deep is found -- no maxdepth" {
  proj="$(rustproj)"
  mkdir -p "$proj/a/b/c/d/e"
  mktarget "$proj/a/b/c/d/e"
  runclean "$proj" rust --force
  assert_success
  assert_directory_not_exists "$proj/a/b/c/d/e/target"
}

@test "a directory NAMED target with no build markers is NOT removed, and says so" {
  proj="$(rustproj)"
  # Xcode's PIF caches under *.noindex are the measured case: named target,
  # carrying no cargo output whatever.
  mkdir -p "$proj/Build.noindex/target"
  : >"$proj/Build.noindex/target/some-pif-file"
  : >"$proj/Build.noindex/Cargo.toml"

  runclean "$proj" rust --force
  assert_success
  assert_directory_exists "$proj/Build.noindex/target"
  assert_output_contains "ignored"
}

@test "a nested target inside a target is not reported as a second root" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/target/debug/build/inner/target/debug/.fingerprint"
  : >"$proj/target/debug/build/inner/Cargo.toml"
  runclean "$proj" rust --force
  assert_success
  # One tree removed, not two -- and no error from removing a path its parent
  # already took.
  assert_output_contains "1 target tree(s) removed"
}

# ---------------------------------------------------------------------------
# ARM -- the Spotlight marker goes on during the same walk
# ---------------------------------------------------------------------------

@test "an unmarked build tree that is SKIPPED gets .metadata_never_index" {
  proj="$(rustproj)"
  # No sibling manifest, so it is skipped -- and skipped is exactly when the
  # marker matters, because the directory survives the run.
  mkdir -p "$proj/redirected/debug/.fingerprint"
  cargo_tag "$proj/redirected"

  runclean "$proj" rust --force
  assert_success
  assert_file_exists "$proj/redirected/.metadata_never_index"
}

# ---------------------------------------------------------------------------
# ARM -- rebuildability, and the rejection is PRINTED
# ---------------------------------------------------------------------------

@test "a build tree with no sibling manifest is SKIPPED and REPORTED, never silent" {
  proj="$(rustproj)"
  mktarget "$proj"
  # The measured shape: CARGO_TARGET_DIR points a build tree somewhere with no
  # manifest beside it. 33 GB and 534,337 files on one machine. A name-keyed
  # scan never enumerates it at all.
  mkdir -p "$proj/scratch/n1/debug/.fingerprint"
  cargo_tag "$proj/scratch/n1"

  runclean "$proj" rust --force
  assert_success
  assert_output_contains "scratch/n1"
  assert_output_contains "skipped"
  assert_output_contains "no sibling Cargo.toml"
  # Skipped means SKIPPED.
  assert_directory_exists "$proj/scratch/n1"
  # ...and the removable one still went.
  assert_directory_not_exists "$proj/target"
}

@test "a redirected build dir is found by MARKER even though it is not named target" {
  proj="$(rustproj)"
  mkdir -p "$proj/buildcache/release/.fingerprint"
  cargo_tag "$proj/buildcache"
  : >"$proj/Cargo.toml"

  runclean "$proj" rust --force
  assert_success
  # It has a sibling Cargo.toml at the project root, so it is removable -- and
  # the point of the test is that a name-keyed scan would never have seen it.
  assert_output_contains "buildcache"
}

# ---------------------------------------------------------------------------
# Peer discipline, the tty rule, and the determinate zero
# ---------------------------------------------------------------------------

@test "per-node build dirs are NAMED before anything is removed" {
  proj="$(rustproj)"
  mktarget "$proj"
  # A per-node dir is a cargo target dir of its own, which cargo marks with a
  # .rustc_info.json at its root (0131).
  mkdir -p "$proj/target/n1" "$proj/target/n2"
  : >"$proj/target/n1/.rustc_info.json"
  : >"$proj/target/n2/.rustc_info.json"
  runclean "$proj" rust --force
  assert_success
  assert_output_contains "per-node"
  assert_output_contains "target/n1"
  assert_output_contains "target/n2"
  assert_output_contains "SHARED"
}

@test "an unanswered prompt removes NOTHING and says so" {
  # THIS ARM RAN UNDER A TTY IT DID NOT OWN AND HUNG THE SUITE FOR 54 MINUTES.
  # It used to redirect stdin with `</dev/null`, which answers nothing:
  # _clean_confirm READS /dev/tty AND NOT STDIN, deliberately and by its own
  # comment. So /dev/tty stayed pointed at whatever terminal the runner had.
  # With no live terminal the read fails, the command declines, and the arm
  # passed. With one -- a person typing `bin/devbin test` -- the read BLOCKS ON
  # THAT PERSON. Measured: the run stopped after test 82, sat 54 minutes, and
  # was killed by hand at exit 141 with a log it called untrustworthy.
  #
  # THE OUTCOME DEPENDED ON WHETHER A HUMAN WAS SITTING AT THE TERMINAL, which
  # is the one variable a suite must never be sensitive to. run_tty_eof gives
  # the child its OWN pty, already at EOF, so the unanswered state is produced
  # rather than inherited -- identically with a terminal and without one.
  require_pty
  proj="$(rustproj)"
  mktarget "$proj"
  run run_tty_eof env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  # Declining is not a failure -- nothing went wrong, the answer was no.
  assert_success
  assert_output_contains "left alone"
  assert_directory_exists "$proj/target"
}

@test "a person at the terminal can still answer y, under a gate whose tool reads no input (0088, second amendment)" {
  # run_gate feeds every gated tool </dev/null (0088 row 2), so clean's own
  # stdin is never the terminal; it asks because the gate says its caller's
  # stdin was one (DEVBIN_GATE_TTY). The arm above holds the unanswered half.
  # This one holds the answered half: the prompt is reached, `y` is read from
  # the terminal, and the tree goes. Under the first cut of 0088 clean refused
  # here with "no tty".
  require_pty
  require_expect
  proj="$(rustproj)"
  mktarget "$proj"
  run run_tty_answer y env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  assert_success
  refute_output_contains "no tty"
  assert_output_contains "proceed? [y/N]"
  [ ! -e "$proj/target" ] || fail "target survived a y answer"
}

@test "a yes is a yes at clean's prompt, and a near-miss is not (0134)" {
  # ONE ANSWER SET: clean took y or Y, and the upgrade offer took yes and YES
  # as well. The near-miss is the control that the answer is still read.
  require_pty
  require_expect
  proj="$(rustproj)"
  mktarget "$proj"
  run run_tty_answer ye env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  assert_output_contains "left alone."
  [ -e "$proj/target" ] || fail "a ye answer removed the target tree"
  run run_tty_answer yes env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  assert_success
  assert_output_contains "proceed? [y/N]"
  [ ! -e "$proj/target" ] || fail "target survived a yes answer:
$output"
}

@test "a terminal present but a PIPE into the gate is refused, and a y on the terminal removes nothing (0088)" {
  # The other half of the flag: the gate's caller piped its input, so nobody at
  # the terminal asked for this run, and clean refuses even though /dev/tty can
  # be opened. With the flag term forced false, clean asked on the terminal
  # and the y removed the tree.
  require_pty
  require_expect
  proj="$(rustproj)"
  mktarget "$proj"
  run run_tty_answer y env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    bash -c 'printf "y\n" | "$1" rust' _ "$proj/bin/.devbin/lib/cmd/clean"
  assert_failure
  assert_output_contains "no tty"
  refute_output_contains "proceed? [y/N]"
  [ -e "$proj/target" ] || fail "target was removed through a pipe"
}

# run_tty_answer's STATUS IS THE COMMAND'S ON BOTH PATHS (issue 0090). With no
# prompt, its first `expect` took `eof` and the second `expect eof` then ran on
# a closed spawn, so the status an arm saw was expect's error, not the
# command's -- and a refusal that exits 0 is the failure these arms exist for.

@test "run_tty_answer reports the command's status when no prompt appears (0090)" {
  require_pty
  require_expect
  run run_tty_answer y sh -c 'echo no question here; exit 3'
  [ "$status" -eq 3 ] || fail "want the command's 3, got $status:
$output"
  refute_output_contains "not open"
}

@test "run_tty_answer reports the command's status after it answers, too -- 0090's control" {
  require_pty
  require_expect
  run run_tty_answer y sh -c 'printf "go? [y/N] "; read -r r </dev/tty; [ "$r" = y ] && exit 4; exit 5'
  [ "$status" -eq 4 ] || fail "want 4 (the y reached the command), got $status:
$output"
}

# run_tty_answer's WAITS ARE BOUNDED (issue 0091). Each arm shrinks one bound to
# 1s and gives the command 8s of silence, so the old helper, which ignored the
# knobs and waited 30s and then without limit, ends at 8s with the command's 0
# instead of hanging -- red, not a stall -- and the bounded helper ends near 1s
# with 124 naming the wait that ran out.

@test "run_tty_answer fails, naming it, when no prompt comes within its wait (0091)" {
  require_pty
  require_expect
  SECONDS=0
  DEVBIN_TEST_TTY_PROMPT_WAIT=1 run run_tty_answer y sh -c 'sleep 8'
  took=$SECONDS
  [ "$status" -eq 124 ] || fail "want 124 (the prompt wait ran out), got $status after ${took}s:
$output"
  assert_output_contains "no [y/N] prompt within 1s"
  [ "$took" -lt 6 ] || fail "the missing prompt took ${took}s to report, not about 1s"
}

@test "run_tty_answer fails, naming it, when the command outlives its wait after the answer (0091)" {
  require_pty
  require_expect
  SECONDS=0
  DEVBIN_TEST_TTY_FINISH_WAIT=1 run run_tty_answer y \
    sh -c 'printf "go? [y/N] "; read -r r </dev/tty; sleep 8'
  took=$SECONDS
  [ "$status" -eq 124 ] || fail "want 124 (the finish wait ran out), got $status after ${took}s:
$output"
  assert_output_contains "the command did not finish within 1s of the answer"
  [ "$took" -lt 6 ] || fail "the stalled command took ${took}s to report, not about 1s"
}

@test "the no-tty REFUSAL branch declares whether this runner could reach it" {
  # The contract is: no readable /dev/tty and no --force is a REFUSAL, following
  # `intent organize --force`. Whether that branch executes depends on the
  # runner, and a runner with a controlling terminal takes the prompt path
  # instead -- so asserting a green here would be a green over code that never
  # ran. The state is declared instead.
  if [ -r /dev/tty ]; then
    echo "# /dev/tty IS readable on this runner: the no-tty refusal branch was" >&3
    echo "# NOT exercised. The prompt-decline path above covers the reachable half." >&3
    skip "no controlling-terminal-free runner available; branch declared unexercised"
  fi
  proj="$(rustproj)"
  mktarget "$proj"
  run env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust </dev/null
  assert_failure
  assert_output_contains "no tty"
  assert_directory_exists "$proj/target"
}

@test "no removable trees REPORTS and PASSES -- a determinate zero is not a failure" {
  proj="$(rustproj)"
  runclean "$proj" rust --force
  assert_success
  assert_output_contains "no removable target/ trees"
}

@test "clean with no option exits non-zero -- a bare destructive verb is a usage error" {
  proj="$(rustproj)"
  runclean "$proj"
  assert_failure
  assert_output_contains "usage:"
}

@test "the elixir arm leaves the sources under deps/ and removes a dependency's own _build (0131)" {
  # What the catalogue's summary says, driven: "the sources under deps/ stay".
  # It used to say "deps/ is left alone", and this arm held no more than that
  # deps/ still existed, so it could not see the _build removed beside a
  # dependency's mix.exs (0131).
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  mkdir -p "$proj/_build/dev" "$proj/deps/jason/lib" "$proj/deps/jason/_build/dev"
  : >"$proj/mix.exs"
  : >"$proj/deps/jason/mix.exs"
  : >"$proj/deps/jason/lib/jason.ex"
  runclean "$proj" elixir --force
  assert_success
  assert_directory_not_exists "$proj/_build"
  assert_directory_not_exists "$proj/deps/jason/_build"
  assert_file_exists "$proj/deps/jason/lib/jason.ex"
  assert_file_exists "$proj/deps/jason/mix.exs"
}

# ---------------------------------------------------------------------------
# ARM -- cargo's markers are cargo's (issue 0131)
#
# Each arm here was driven before it was written: the defect's shape went red
# against the unfixed file, and each carries its own positive control, so a
# classifier that found nothing at all could not pass it.
# ---------------------------------------------------------------------------

# pytest_tag <dir> -- pytest's own tag, the same signature line with another
# tool's name on it. One copy, as test_helper keeps cargo's (the text once sat
# in this file twice).
pytest_tag() {
  printf 'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by pytest.\n' >"$1/CACHEDIR.TAG"
}

# pytest_cache <dir> -- a pytest cache, tagged as pytest tags it.
pytest_cache() {
  mkdir -p "$1/.pytest_cache/v/cache"
  pytest_tag "$1/.pytest_cache"
}

@test "a CACHEDIR.TAG another tool wrote is not a cargo tree: pytest's cache survives clean rust (0131)" {
  proj="$(rustproj)"
  mktarget "$proj"
  pytest_cache "$proj"
  # And a directory NAMED target whose only marker is another tool's tag: found
  # by its name, so the tag's writer is what classifies it.
  mkdir -p "$proj/other/target"
  cp "$proj/.pytest_cache/CACHEDIR.TAG" "$proj/other/target/CACHEDIR.TAG"
  : >"$proj/other/Cargo.toml"
  # And a tag whose writer's name only BEGINS with cargo is not cargo's: the
  # whole line is matched, not a substring of it.
  mkdir -p "$proj/lookalike/cache"
  printf 'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo-xtask.\n' >"$proj/lookalike/CACHEDIR.TAG"
  runclean "$proj" rust --force
  assert_success
  # The control: the cargo tree beside them was found and removed.
  assert_directory_not_exists "$proj/target"
  assert_directory_exists "$proj/.pytest_cache"
  assert_output_contains "1 target tree(s) removed"
  refute_output_contains ".pytest_cache"
  assert_directory_exists "$proj/other/target"
  assert_output_contains "ignored"
  assert_directory_exists "$proj/lookalike"
  refute_output_contains "lookalike"
}

@test "the elixir and swift arms do not search for cargo's markers (0131)" {
  local arm
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/_build/dev" "$proj/.build/debug"
  : >"$proj/mix.exs"
  : >"$proj/Package.swift"
  # The control: the rust arm does list the cargo tree.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$proj/target"
  for arm in elixir:_build swift:.build; do
    runclean "$proj" "${arm%%:*}" --dry-run
    assert_success
    # Each arm found its own tree, so the refusals below are not an empty run.
    assert_output_contains "1 ${arm#*:} tree(s)"
    refute_output_contains "$proj/target"
    refute_output_contains "named like a build tree"
  done
}

@test "cargo's release/ note is printed by the rust arm alone (0131)" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/_build/dev" "$proj/.build/debug"
  : >"$proj/mix.exs"
  : >"$proj/Package.swift"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "This takes release/ as well as debug/"
  local arm
  for arm in elixir:_build swift:.build; do
    runclean "$proj" "${arm%%:*}" --dry-run
    assert_success
    assert_output_contains "1 ${arm#*:} tree(s)"
    refute_output_contains "release/"
  done
}

# snapshot <dir> -- every path under <dir> except tmp/clean/, with each file's
# checksum and each symlink named, so a run that created, removed or rewrote
# anything outside tmp/clean/ shows as a difference. tmp/ itself is walked but
# not listed: it is where tmp/clean/ is made.
snapshot() {
  (cd "$1" && find . -path ./tmp/clean -prune -o -path ./tmp -o -type f -exec cksum {} + \
    -o -type l -print -o -type d -print | LC_ALL=C sort)
}

@test "--dry-run writes no Spotlight marker, says a real run would, and changes nothing outside tmp/clean/ (0131)" {
  proj="$(rustproj)"
  mkdir -p "$proj/redirected/debug/.fingerprint"
  cargo_tag "$proj/redirected"
  local before after
  before="$(snapshot "$proj")"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "would mark $proj/redirected/.metadata_never_index"
  after="$(snapshot "$proj")"
  [ "$before" = "$after" ] || fail "the dry run changed the project outside tmp/clean/:
$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
  # The control: the real run on the same tree does place it, and the snapshot
  # sees that -- so the equality above is the dry run writing nothing, not an
  # instrument that could not see a write.
  runclean "$proj" rust --force
  assert_success
  assert_file_exists "$proj/redirected/.metadata_never_index"
  [ "$after" != "$(snapshot "$proj")" ] || fail "the snapshot did not see the marker the real run wrote"
}

@test "one ignored directory is a directory, two are directories (0131)" {
  proj="$(rustproj)"
  mkdir -p "$proj/a/target" "$proj/b/target"
  : >"$proj/a/Cargo.toml"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "2 directories named like a build tree"
  rm -r "$proj/b"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 directory named like a build tree"
  refute_output_contains "director(y|ies)"
}

@test "an ordinary layout is not a shared tree: Mix envs, SwiftPM and cargo triples are not per-node (0131)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
    - elixir
    - swift
YAML
  )"
  mktarget "$proj"
  # cargo --target <triple> lays out target/<triple> with a CACHEDIR.TAG and
  # debug/.fingerprint and no .rustc_info.json (cargo 1.98.1, measured).
  mkdir -p "$proj/target/aarch64-apple-darwin/debug/.fingerprint" "$proj/target/criterion"
  cargo_tag "$proj/target/aarch64-apple-darwin"
  mkdir -p "$proj/_build/dev" "$proj/_build/test" "$proj/.build/arm64-apple-macosx" "$proj/.build/checkouts"
  : >"$proj/mix.exs"
  : >"$proj/Package.swift"
  local arm
  for arm in rust:target elixir:_build swift:.build; do
    runclean "$proj" "${arm%%:*}" --dry-run
    assert_success
    assert_output_contains "1 ${arm#*:} tree(s)"
    refute_output_contains "per-node"
    refute_output_contains "SHARED"
  done
  # The control: a nested target dir of its own, beside the same triple, is.
  mkdir -p "$proj/target/n1"
  : >"$proj/target/n1/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "per-node: $proj/target/n1"
  refute_output_contains "per-node: $proj/target/aarch64-apple-darwin"
  assert_output_contains "SHARED"
}

@test "the elixir option's summary claims no more than the arm does (0131)" {
  # Read from the catalogue, not through `help clean`: clean's page says the
  # same words, so an assertion on help's output could be satisfied by the page.
  run builtin_option_summary clean elixir
  assert_success
  assert_output "Remove _build/ trees; the sources under deps/ stay"
}

@test "a target whose only marker is cargo's tag is a cargo tree (0131)" {
  # The twin of other/target above, whose only marker is pytest's tag: this one
  # is cargo's, and it is removable. Every other cargo tag in this file sits
  # beside a .fingerprint, so without this arm the tag test could be deleted
  # and nothing here would notice. It cannot tell reading the tag's writer from
  # reading its presence -- its pytest twin does -- and its title once said it
  # could.
  proj="$(rustproj)"
  mkdir -p "$proj/target"
  cargo_tag "$proj/target"
  : >"$proj/Cargo.toml"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  refute_output_contains "named like a build tree"
}

@test "a tree whose only cargo marker is .rustc_info.json is found, with no tag or beside another tool's (0131)" {
  # WITH NO TAG AT ALL, as a target from a cargo that wrote none has it, the
  # search for .rustc_info.json is the only thing that finds it: beside a tag,
  # any tag, the walk adds the tree at the tag, since the marker says it is
  # cargo's before the tag is read, and this arm was green over a walk that
  # never searched for the marker. Skipped both times, for want of a Cargo.toml
  # beside it.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/sub/stale"
  : >"$proj/sub/stale/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$proj/sub/stale (no sibling Cargo.toml)"
  # Beside pytest's tag, found all the same: another tool's tag does not make
  # a cargo tree another tool's cache.
  pytest_tag "$proj/sub/stale"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$proj/sub/stale (no sibling Cargo.toml)"
}

@test "a Spotlight marker that cannot be written is said, not swallowed (0131)" {
  proj="$(rustproj)"
  mkdir -p "$proj/redirected/debug/.fingerprint"
  cargo_tag "$proj/redirected"
  chmod 555 "$proj/redirected"
  if [ -w "$proj/redirected" ]; then
    chmod 755 "$proj/redirected"
    skip "running with permissions that write into a mode-555 directory"
  fi
  runclean "$proj" rust --force
  chmod 755 "$proj/redirected"
  assert_success
  assert_output_contains "could not mark $proj/redirected"
  assert_file_not_exists "$proj/redirected/.metadata_never_index"
}

# --- a scan that cannot read everything (issue 0131, point 7) ----------------
#
# find's errors went to /dev/null and its status was lost in a process
# substitution, so a tree beneath an unreadable directory was never listed and
# the run exited 0 over it. Each arm restores the mode BEFORE it asserts, so a
# failing assertion leaves nothing the teardown cannot remove.


@test "a directory the scan cannot read is named, the scan says it is PARTIAL, and each arm exits 1 (0131)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
    - elixir
    - swift
YAML
  )"
  mktarget "$proj"
  mkdir -p "$proj/_build/dev" "$proj/.build/debug"
  : >"$proj/mix.exs"
  : >"$proj/Package.swift"
  mkdir -p "$proj/locked/sub/_build/dev" "$proj/locked/sub/.build/debug"
  mktarget "$proj/locked/sub"
  : >"$proj/locked/sub/mix.exs"
  : >"$proj/locked/sub/Package.swift"
  local arm i
  # THE CONTROL: readable, each arm finds both of its trees and exits 0.
  for arm in rust:target elixir:_build swift:.build; do
    runclean "$proj" "${arm%%:*}" --dry-run
    assert_success
    assert_output_contains "2 ${arm#*:} tree(s)"
    refute_output_contains "PARTIAL"
  done
  lock "$proj/locked"
  local -a st=() out=()
  for arm in rust elixir swift; do
    runclean "$proj" "$arm" --dry-run
    st+=("$status")
    out+=("$output")
  done
  chmod 755 "$proj/locked"
  i=0
  for arm in rust:target elixir:_build swift:.build; do
    output="${out[$i]}"
    [ "${st[$i]}" -eq 1 ] || fail "clean ${arm%%:*} --dry-run over an unreadable directory exited ${st[$i]}, not 1: $output"
    assert_output_contains "$proj/locked"
    assert_output_contains "THE SCAN WAS PARTIAL"
    assert_output_contains "1 ${arm#*:} tree(s)"
    refute_output_contains "$proj/locked/sub/${arm#*:}"
    i=$((i + 1))
  done
}

@test "a partial scan still removes what it found as asked, and exits 1 (0131)" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/locked/sub"
  mktarget "$proj/locked/sub"
  lock "$proj/locked"
  runclean "$proj" rust --force
  chmod 755 "$proj/locked"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_directory_not_exists "$proj/target"
  assert_directory_exists "$proj/locked/sub/target"
  assert_output_contains "1 target tree(s) removed"
  assert_output_contains "THE SCAN WAS PARTIAL"
}

@test "a partial scan that finds nothing to remove exits 1, not the determinate zero (0131)" {
  # The control is "no removable trees REPORTS and PASSES", above.
  proj="$(rustproj)"
  mkdir -p "$proj/locked/sub"
  mktarget "$proj/locked/sub"
  lock "$proj/locked"
  runclean "$proj" rust --force
  chmod 755 "$proj/locked"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "no removable target/ trees"
  assert_output_contains "THE SCAN WAS PARTIAL"
}

@test "a cargo tag the scan cannot read is named and makes the scan PARTIAL, never read as another tool's (0131)" {
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/sub/relocated"
  cargo_tag "$proj/sub/relocated"
  # THE CONTROL: readable, the tag alone finds the tree, skipped for want of a
  # Cargo.toml beside it.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$proj/sub/relocated (no sibling Cargo.toml)"
  lock "$proj/sub/relocated/CACHEDIR.TAG"
  runclean "$proj" rust --dry-run
  chmod 644 "$proj/sub/relocated/CACHEDIR.TAG"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "$proj/sub/relocated/CACHEDIR.TAG"
  assert_output_contains "THE SCAN WAS PARTIAL"
  refute_output_contains "no sibling Cargo.toml"
}

@test "an unreadable directory inside a tree found by NAME does not make the scan partial; inside one found by its marker, it does (0131)" {
  # The walk prunes at every tree it finds BY NAME, and never reads inside one:
  # the churn of a build running beside it made 156 of 161 dry runs partial when
  # two marker passes walked there. A tree inside a tree found by name is part
  # of it, so nothing is lost. This arm's name once said "a found tree": a tree
  # found by its marker has no name to prune at and is walked in full, so the
  # second half below holds the other side of the same line.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/target/debug/locked"
  lock "$proj/target/debug/locked"
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/target/debug/locked"
  assert_success
  refute_output_contains "PARTIAL"
  assert_output_contains "1 target tree(s)"
  # FOUND BY ITS MARKER: the same unreadable directory inside it is walked into,
  # and the scan is partial.
  rm -rf "$proj/target"
  mkdir -p "$proj/out/debug/.fingerprint" "$proj/out/debug/locked"
  cargo_tag "$proj/out"
  chmod 000 "$proj/out/debug/locked"
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/out/debug/locked"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "$proj/out/debug/locked"
  assert_output_contains "THE SCAN WAS PARTIAL"
}

@test "a tree found by name whose only marker is a tag grep cannot read is listed as unread, and the scan is partial (0131)" {
  # The walk prunes at the tree, so its tag is read in classification alone,
  # and there a tag that cannot be read has to count. Not read, it says neither
  # "tree" nor "not a tree", so it is listed apart from the unmarked, and grep's
  # own error names the tag.
  proj="$(rustproj)"
  mkdir -p "$proj/target"
  cargo_tag "$proj/target"
  : >"$proj/Cargo.toml"
  lock "$proj/target/CACHEDIR.TAG"
  runclean "$proj" rust --dry-run
  chmod 644 "$proj/target/CACHEDIR.TAG"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "$proj/target/CACHEDIR.TAG"
  assert_output_contains "THE SCAN WAS PARTIAL"
  assert_output_contains "1 candidate directory could not be read"
  refute_output_contains "named like a build tree"
}

@test "a symlinked CACHEDIR.TAG is no marker: it is not followed, as find's -type f never offers it (0131)" {
  # Followed, a tag the scan never read was read, and one that could not be
  # made no partial scan. The link here points at cargo's own tag, so following
  # it would take the tree as cargo's.
  proj="$(rustproj)"
  mkdir -p "$proj/target" "$proj/tags"
  # cargo's own words from the one fixture (test_helper's cargo_tag), under
  # another name, so the tags directory is not a tree of its own.
  cargo_tag "$proj/tags"
  mv "$proj/tags/CACHEDIR.TAG" "$proj/tags/cargo-tag"
  ln -s "$proj/tags/cargo-tag" "$proj/target/CACHEDIR.TAG"
  : >"$proj/Cargo.toml"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 directory named like a build tree"
  refute_output_contains "1 target tree(s)"
}

@test "--refuse-partial refuses a partial scan before anything is removed or marked, and a dry run says a real run would (0131)" {
  # fullcycle passes it: a cycle that removed some trees and then stopped at a
  # failed clean left them unbuilt.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/redirected/debug/.fingerprint" "$proj/locked/sub"
  cargo_tag "$proj/redirected"
  mktarget "$proj/locked/sub"
  lock "$proj/locked"
  runclean "$proj" rust --force --refuse-partial
  local st="$status" out="$output"
  runclean "$proj" rust --dry-run --force --refuse-partial
  chmod 755 "$proj/locked"
  [ "$st" -eq 1 ] || fail "exited $st, not 1: $out"
  [[ "$out" == *"refusing, as --refuse-partial asks"* ]] || fail "no refusal: $out"
  # A refusal does not say, above itself, that what was found is handled as
  # asked.
  [[ "$out" != *"handled as asked"* ]] || fail "the refusal says what was found is handled as asked: $out"
  assert_directory_exists "$proj/target"
  assert_file_not_exists "$proj/redirected/.metadata_never_index"
  # THE DRY RUN SAYS SO AT ONCE, AND STOPS, as the real run does: before, it
  # printed the mark it would place and "handled as asked", and said last of all
  # that a real run would refuse.
  [ "$status" -eq 1 ] || fail "the dry run exited $status, not 1: $output"
  assert_output_contains "A real run would REFUSE: the scan is partial, and --refuse-partial was given"
  refute_output_contains "would mark"
  refute_output_contains "handled as asked"
  refute_output_contains "target tree(s)"
  # THE CONTROL: over a scan that read everything, the flag changes nothing.
  runclean "$proj" rust --force --refuse-partial
  assert_success
  assert_directory_not_exists "$proj/target"
}

@test "a dry run says a skipped tree it cannot write to will not be marked, as the real run finds (0131)" {
  proj="$(rustproj)"
  mkdir -p "$proj/redirected/debug/.fingerprint"
  cargo_tag "$proj/redirected"
  chmod 555 "$proj/redirected"
  if [ -w "$proj/redirected" ]; then
    chmod 755 "$proj/redirected"
    skip "running with permissions that write into a mode-555 directory"
  fi
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/redirected"
  assert_success
  assert_output_contains "could not mark $proj/redirected -- it is not writable"
  refute_output_contains "would mark $proj/redirected"
}

@test "a partial scan declined at the prompt removes nothing and still exits 1 (0131)" {
  require_pty
  require_expect
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/locked/sub"
  mktarget "$proj/locked/sub"
  lock "$proj/locked"
  run run_tty_answer n env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  chmod 755 "$proj/locked"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "proceed? [y/N]"
  assert_output_contains "left alone"
  assert_output_contains "THE SCAN WAS PARTIAL"
  assert_directory_exists "$proj/target"
}

@test "a candidate found by name that cannot be read is named, listed apart as unread, and makes the scan partial (0131)" {
  # The marker tests are file tests, false on "permission denied", so a
  # mode-000 target/ holding every marker cargo writes was listed as unmarked
  # at exit 0 with no word at all.
  proj="$(rustproj)"
  mkdir -p "$proj/crate"
  mktarget "$proj/crate"
  # THE CONTROL: readable, it is a tree.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  lock "$proj/crate/target"
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/crate/target"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "cannot read $proj/crate/target"
  assert_output_contains "1 candidate directory could not be read"
  assert_output_contains "THE SCAN WAS PARTIAL"
  refute_output_contains "named like a build tree with no build markers"
}

@test "a target holding only per-node target dirs is a build tree, and each is named (0131)" {
  # After `CARGO_TARGET_DIR=target/n1 cargo build`, target/ holds n1/ and nothing
  # of cargo's at its own root, so it was listed as unmarked and nothing inside
  # it was listed at all (cargo 1.98.1).
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/target/n1/debug/.fingerprint"
  cargo_tag "$proj/target/n1"
  : >"$proj/target/n1/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  assert_output_contains "per-node: $proj/target/n1"
  assert_output_contains "SHARED"
  refute_output_contains "named like a build tree"
  # THE CONTROL: without its .rustc_info.json, n1/ is a triple-like directory,
  # not a target dir of its own, and target/ is unmarked, as before.
  rm "$proj/target/n1/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 directory named like a build tree"
  refute_output_contains "target tree(s)"
}

@test "a project checked out as target is walked, not pruned at its root (0131)" {
  # The name test applied to the start directory too, so a root named target was
  # pruned at depth 0 and nothing beneath it was examined (driven). -mindepth 1.
  proj="$(mkproj target <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  )"
  [ "${proj##*/}" = target ] || fail "the fixture's root is not named target: $proj"
  mkdir -p "$proj/crate"
  mktarget "$proj/crate"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  assert_output_contains "$proj/crate/target"
  refute_output_contains "named like a build tree"
}

@test "a tag grep cannot read beside .rustc_info.json is not read: one verdict however the tree is found (0131)" {
  # Found by its tag, such a tree read as PARTIAL; found by its name, it passed
  # with grep's error printed over the result. .rustc_info.json says the tree is
  # cargo's without a read.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/target" "$proj/out"
  local d
  local -a trees=(target out)
  for d in "${trees[@]}"; do
    : >"$proj/$d/.rustc_info.json"
    cargo_tag "$proj/$d"
  done
  # THE CONTROL: readable, every one is a tree.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "${#trees[@]} target tree(s)"
  lock "$proj/target/CACHEDIR.TAG"
  chmod 000 "$proj/out/CACHEDIR.TAG"
  runclean "$proj" rust --dry-run
  chmod 644 "$proj/target/CACHEDIR.TAG" "$proj/out/CACHEDIR.TAG"
  assert_success
  assert_output_contains "${#trees[@]} target tree(s)"
  refute_output_contains "PARTIAL"
  refute_output_contains "CACHEDIR.TAG"
}

@test "a tag carrying cargo's sentence inside other text is not cargo's: the whole line is matched (0131)" {
  # Green on the code it pins, by construction: the mutant that matches a
  # substring instead of the whole line is what this arm exists to kill: no arm
  # told -x from a substring.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/padded" "$proj/genuine"
  printf 'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo. And kept by another tool.\n' >"$proj/padded/CACHEDIR.TAG"
  cargo_tag "$proj/genuine"
  runclean "$proj" rust --dry-run
  assert_success
  # THE CONTROL: cargo's own tag, alone, is a tree.
  assert_output_contains "1 target tree(s)"
  assert_output_contains "$proj/genuine"
  refute_output_contains "$proj/padded"
}

@test "a refusal over PATH says the scan was partial, and not that what was found is handled as asked (0131)" {
  # Printed directly above the refusal, "handled as asked" said the opposite of
  # the line under it.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$BATS_TEST_TMPDIR/pathbin"
  : >"$proj/target/release/toolish"
  chmod +x "$proj/target/release/toolish"
  ln -s "$proj/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin/toolish"
  mkdir -p "$proj/locked/sub"
  mktarget "$proj/locked/sub"
  lock "$proj/locked"
  runclean_path "$proj" "$BATS_TEST_TMPDIR/pathbin:$PATH" rust
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "refusing: removing these trees would darken"
  assert_output_contains "THE SCAN WAS PARTIAL"
  assert_output_contains "This run exits 1, whatever it does with what it found."
  refute_output_contains "handled as asked"
  assert_directory_exists "$proj/target"
}

@test "a crate whose directory is named target is walked, and its own build tree found (0131)" {
  # The name test pruned at it, so its build tree was never listed, and it was
  # then set aside as built in place with no build output in it at all. A
  # directory named like a tree that holds its own manifest is a crate, and is
  # walked like any other directory.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/crates/target/src"
  : >"$proj/crates/target/src/lib.rs"
  # THE CONTROL: a crate built the same way, under an ordinary name.
  local d
  local -a built=("$proj/crates/target" "$proj/crates/other")
  for d in "${built[@]}"; do mktarget "$d"; done
  runclean "$proj" rust --force
  assert_success
  assert_output_contains "${#built[@]} target tree(s) removed"
  assert_directory_not_exists "$proj/crates/target/target"
  assert_directory_not_exists "$proj/crates/other/target"
  assert_file_exists "$proj/crates/target/src/lib.rs"
  assert_file_exists "$proj/crates/target/Cargo.toml"
  refute_output_contains "in place"
}

@test "a candidate the elixir or swift arm cannot read is listed as unread, the scan is partial, and nothing of it is removed (0131)" {
  # The readability test sat in cargo's arm alone: a mode-000 _build/ was listed
  # as removable at size ?, and --force died on it after removing whatever
  # sorted before it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - swift
YAML
  )"
  mkdir -p "$proj/_build/dev" "$proj/sub/_build/dev" "$proj/.build/debug" "$proj/sub/.build/debug"
  : >"$proj/mix.exs"
  : >"$proj/sub/mix.exs"
  : >"$proj/Package.swift"
  : >"$proj/sub/Package.swift"
  lock "$proj/_build"
  chmod 000 "$proj/.build"
  runclean "$proj" elixir --force
  local est="$status" eout="$output"
  runclean "$proj" swift --force
  chmod 755 "$proj/_build" "$proj/.build"
  [ "$est" -eq 1 ] || fail "clean elixir exited $est, not 1: $eout"
  [[ "$eout" == *"cannot read $proj/_build"* ]] || fail "clean elixir did not name the unreadable _build: $eout"
  [[ "$eout" == *"1 candidate directory could not be read"* ]] || fail "clean elixir did not list it apart: $eout"
  [[ "$eout" != *"could not remove"* ]] || fail "clean elixir tried to remove what it could not read: $eout"
  [ "$status" -eq 1 ] || fail "clean swift exited $status, not 1: $output"
  assert_output_contains "cannot read $proj/.build"
  refute_output_contains "could not remove"
  assert_directory_exists "$proj/_build"
  assert_directory_exists "$proj/.build"
  assert_directory_not_exists "$proj/sub/_build"
  assert_directory_not_exists "$proj/sub/.build"
}

@test "a tree marked without a read is one tree however it is found: an unreadable tag beside a .fingerprint, and a tag beside a linked .rustc_info.json (0131)" {
  # The walk and the classification each decided which markers need no read,
  # and disagreed: a tag grep could not read, beside debug/.fingerprint, was a
  # tree found by name and PARTIAL found by its tag; and the walk's [ -f ]
  # followed a linked .rustc_info.json that find's -type f never prints, so the
  # tag beside it was skipped for a candidate no line added.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/target/debug/.fingerprint" "$proj/out/debug/.fingerprint"
  local d
  local -a trees=(target out)
  for d in "${trees[@]}"; do cargo_tag "$proj/$d"; done
  lock "$proj/target/CACHEDIR.TAG"
  chmod 000 "$proj/out/CACHEDIR.TAG"
  runclean "$proj" rust --dry-run
  chmod 644 "$proj/target/CACHEDIR.TAG" "$proj/out/CACHEDIR.TAG"
  assert_success
  assert_output_contains "${#trees[@]} target tree(s)"
  refute_output_contains "PARTIAL"
  refute_output_contains "CACHEDIR.TAG"
  # A LINKED .rustc_info.json IS NO MARKER, as find says, so the tag beside it
  # is read, and it is cargo's.
  rm -rf "$proj/target" "$proj/out"
  mkdir -p "$proj/linked" "$proj/elsewhere"
  cargo_tag "$proj/linked"
  : >"$proj/elsewhere/info.json"
  ln -s "$proj/elsewhere/info.json" "$proj/linked/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  assert_output_contains "$proj/linked"
  # And beside ANOTHER tool's tag, a linked .rustc_info.json marks nothing: find
  # never offers the link, so the tag is read, and it is not cargo's. Counted as
  # a marker, the link would have pytest's cache listed for removal.
  rm -rf "$proj/linked"
  mkdir -p "$proj/pycache"
  pytest_tag "$proj/pycache"
  ln -s "$proj/elsewhere/info.json" "$proj/pycache/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  refute_output_contains "$proj/pycache"
  assert_output_contains "no removable target/ trees"
}

@test "a target whose only marker sits under a directory the scan cannot search is listed as unread, not as unmarked (0131)" {
  # Each marker test is false on "permission denied", so with debug/ unsearchable
  # a target/ whose only marker is debug/.fingerprint read as unmarked at exit 0.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/target/debug/.fingerprint"
  # THE CONTROL: searchable, it is a tree.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  lock "$proj/target/debug"
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/target/debug"
  [ "$status" -eq 1 ] || fail "exited $status, not 1: $output"
  assert_output_contains "cannot search $proj/target/debug"
  assert_output_contains "1 candidate directory could not be read"
  refute_output_contains "named like a build tree"
}

@test "the verdict is one pure decision: refuse over PATH, ask, or remove (0131)" {
  # It was tested at three sites, and fullcycle's header warns against one
  # predicate in two places. Read from the source and called with literals, so
  # the table below is the decision itself.
  local fn
  fn="$(awk '/^_clean_verdict\(\) \{/,/^}/' "$DEVBIN_LIB_DIR/cmd/clean")"
  [ -n "$fn" ] || fail "no _clean_verdict in lib/cmd/clean"
  eval "$fn"
  [ "$(_clean_verdict 0 0 0)" = ask ] || fail "nothing blocked, no --force: $(_clean_verdict 0 0 0)"
  [ "$(_clean_verdict 0 1 1)" = remove ] || fail "nothing blocked, --force: $(_clean_verdict 0 1 1)"
  [ "$(_clean_verdict 1 0 0)" = refuse-path ] || fail "blocked, no consent: $(_clean_verdict 1 0 0)"
  [ "$(_clean_verdict 2 0 0)" = refuse-path ] || fail "two blocked, no consent: $(_clean_verdict 2 0 0)"
  [ "$(_clean_verdict 1 1 0)" = ask ] || fail "blocked, --force-blocked: $(_clean_verdict 1 1 0)"
  [ "$(_clean_verdict 1 1 1)" = remove ] || fail "blocked, --force: $(_clean_verdict 1 1 1)"
}

@test "a project root given as a link is walked through it (0131)" {
  # Under find's default -P a linked root was not descended at all: the scan
  # examined nothing and said so at exit 0. The dispatcher makes the root
  # physical; a caller setting it directly may not.
  proj="$(rustproj)"
  mktarget "$proj"
  ln -s "$proj" "$BATS_TEST_TMPDIR/linkedroot"
  run env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$BATS_TEST_TMPDIR/linkedroot" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$proj/bin/.devbin/lib/cmd/clean" rust --dry-run
  assert_success
  assert_output_contains "1 target tree(s)"
  assert_output_contains "$BATS_TEST_TMPDIR/linkedroot/target"
}

@test "a project's own test on PATH is never run by the walk, and decides nothing it finds (0131)" {
  # find looks -exec's utility up through PATH, and a project's bin/test first
  # on PATH -- direnv's PATH_add bin puts it there -- was run by the dry run
  # once per directory named like the tree, and decided the prune: exiting 0 it
  # pruned the crate named target again, exiting 1 it pruned nothing, and find
  # exited 0 either way. The walk runs /bin/sh, named whole.
  proj="$(rustproj)"
  mkdir -p "$proj/crates/target/src"
  local st d
  local -a built=("$proj/crates/target" "$proj")
  for d in "${built[@]}"; do mktarget "$d"; done
  for st in 0 1; do
    rm -f "$BATS_TEST_TMPDIR/test.ran"
    printf '#!/bin/sh\n: >"%s/test.ran"\nexit %s\n' "$BATS_TEST_TMPDIR" "$st" >"$proj/bin/test"
    chmod +x "$proj/bin/test"
    runclean_path "$proj" "$proj/bin:$PATH" rust --dry-run
    [ ! -e "$BATS_TEST_TMPDIR/test.ran" ] || fail "the walk ran the project's test, which exits $st: $output"
    assert_success
    assert_output_contains "${#built[@]} target tree(s)"
    refute_output_contains "in place"
  done
}

@test "a PATH link through a symlinked directory and .. is followed as the kernel follows it (0131)" {
  # bash's plain cd tidies a/../b as text, where the kernel reads the .. after
  # following a, so with a directory at the tidied spelling the guard read the
  # wrong one, and a live PATH link into the tree went unlisted and unrefused.
  # The guard's cd is physical.
  proj="$(rustproj)"
  mktarget "$proj"
  printf '#!/bin/sh\n' >"$proj/target/release/devbinprobezz"
  chmod +x "$proj/target/release/devbinprobezz"
  local pb="$BATS_TEST_TMPDIR/pb"
  # pb/release is the tidied spelling of pb/lnk/../release, and it exists, empty.
  mkdir -p "$pb/release"
  ln -s "$proj/target/debug" "$pb/lnk"
  ln -s "lnk/../release/devbinprobezz" "$pb/devbinprobezz"
  [ "$pb/devbinprobezz" -ef "$proj/target/release/devbinprobezz" ] || fail "the fixture's link does not reach the tree"
  runclean_path "$proj" "$pb:$PATH" rust --dry-run
  assert_success
  assert_output_contains "PATH resolves into $proj/target"
  assert_output_contains "A real run would REFUSE: PATH resolves into the tree(s) above."
}

@test "a relative PATH entry is read from the project root, never through CDPATH or as the previous directory (0131)" {
  # cd reads a bare relative operand through an exported CDPATH before the
  # current directory, and a lone - as the directory it last left, so the guard
  # read a relative PATH entry as a directory it does not name: release through
  # a CDPATH into the tree was blamed on the tree, and a - linked into the tree
  # went unlisted. A relative entry is spelled from ./.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/release"
  local bash_bin
  bash_bin="$(command -v bash)"
  run env CDPATH="$proj/target" PATH="release:$PATH" DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$bash_bin" "$proj/bin/.devbin/lib/cmd/clean" rust --dry-run
  assert_success
  refute_output_contains "PATH resolves into"
  assert_output_contains "A real run would ask on the tty"
  # AND - IS THE DIRECTORY OF THAT NAME: one linked into the tree is listed.
  ln -s "$proj/target/release" "$proj/-"
  runclean_path "$proj" "-:$PATH" rust --dry-run
  assert_success
  assert_output_contains "PATH resolves into $proj/target"
  assert_output_contains "- (PATH entry) -> "
}

@test "a directory the scan can search but not list is looked in, not called unsearchable (0131)" {
  # Every marker test inside a directory needs search permission only, and a
  # search-only directory, mode 100, was reported as one a marker in it could
  # not be looked for in, with the scan PARTIAL.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/target/x"
  chmod 100 "$proj/target/x"
  if [ -r "$proj/target/x" ]; then
    chmod 755 "$proj/target/x"
    skip "running with permissions that read a mode-100 directory"
  fi
  runclean "$proj" rust --dry-run
  local st="$status" out="$output"
  chmod 755 "$proj/target/x"
  [ "$st" -eq 0 ] || fail "a search-only directory made the scan partial: $out"
  [[ "$out" == *"1 directory named like a build tree"* ]] || fail "the unmarked target is not listed as ignored: $out"
  [[ "$out" != *"cannot search"* ]] || fail "a search-only directory was called unsearchable: $out"
  # AND A MARKER IN ONE IS FOUND: a per-node dir at mode 100.
  rm -rf "$proj/target/x"
  mkdir -p "$proj/target/n1"
  : >"$proj/target/n1/.rustc_info.json"
  chmod 100 "$proj/target/n1"
  runclean "$proj" rust --dry-run
  chmod 755 "$proj/target/n1"
  assert_success
  assert_output_contains "1 target tree(s)"
}

@test "a tag that vanished before grep read it is no tag, not an unreadable one (0131)" {
  # Another run's clean can remove a tag between _clean_cargo_tag's test and
  # grep's read of it, and grep's failure then read as a tag it could not read:
  # the scan PARTIAL, so fullcycle refused. A grep stubbed on PATH removes a tag
  # as it is asked to read one, which is the race held still, and hands every
  # other call to the grep this suite finds. No tag is not cargo's tag either:
  # read as one, the directory was listed.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/out" "$BATS_TEST_TMPDIR/fakebin"
  cargo_tag "$proj/out"
  local real_grep
  real_grep="$(command -v grep)"
  [[ "$real_grep" == /* ]] || fail "grep is not a program here: $real_grep"
  printf '#!/usr/bin/env bash\nlast="${!#}"\ncase "$last" in\n  */CACHEDIR.TAG) : >"%s/grep.ran"; rm -f -- "$last"; exit 2 ;;\nesac\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR" "$real_grep" >"$BATS_TEST_TMPDIR/fakebin/grep"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/grep"
  runclean_path "$proj" "$BATS_TEST_TMPDIR/fakebin:$PATH" rust --dry-run
  assert_file_exists "$BATS_TEST_TMPDIR/grep.ran"
  assert_success
  refute_output_contains "PARTIAL"
  refute_output_contains "$proj/out"
  assert_output_contains "no removable target/ trees"
}

@test "a PATH link into a per-node tree, a target triple, or a triple inside a per-node tree is refused (0131)" {
  # A target whose only output is per-node is a tree (the per-node arm above),
  # and the guard looked for binaries in the tree's own debug/ and release/
  # alone, so a link into target/n1/debug went dark under --force unsaid, where
  # the base ignored the tree. A triple's release/, per-node or not, was missed
  # before 0131 too.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  local bin="$BATS_TEST_TMPDIR/pathbin" at
  mkdir -p "$bin"
  for at in n1/debug aarch64-apple-darwin/release n1/aarch64-apple-darwin/release; do
    rm -rf "$proj/target" "$bin/devbinnodezz"
    mkdir -p "$proj/target/n1/debug/.fingerprint" "$proj/target/$at"
    : >"$proj/target/n1/.rustc_info.json"
    cargo_tag "$proj/target/n1"
    printf '#!/bin/sh\n' >"$proj/target/$at/devbinnodezz"
    chmod +x "$proj/target/$at/devbinnodezz"
    ln -s "$proj/target/$at/devbinnodezz" "$bin/devbinnodezz"
    runclean_path "$proj" "$bin:$PATH" rust --dry-run
    assert_success
    [[ "$output" == *"PATH resolves into $proj/target"* ]] || fail "a link into target/$at is not listed: $output"
    assert_output_contains "A real run would REFUSE: PATH resolves into the tree(s) above."
  done
}

@test "a project root or a PATH entry spelled from // is read as the path it names (0131)" {
  # pwd -P keeps a leading //, which names / here, so a tree and a PATH entry
  # compared as prefixes disagreed whenever one of them was spelled from //: a
  # shell that entered the project as //... hands bin/devbin that root, and
  # every link into its trees went unrefused.
  proj="$(rustproj)"
  mktarget "$proj"
  printf '#!/bin/sh\n' >"$proj/target/release/devbinslashzz"
  chmod +x "$proj/target/release/devbinslashzz"
  local bin="$BATS_TEST_TMPDIR/pathbin" bash_bin
  mkdir -p "$bin"
  ln -s "$proj/target/release/devbinslashzz" "$bin/devbinslashzz"
  bash_bin="$(command -v bash)"
  run env PATH="$bin:$PATH" DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="/$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$bash_bin" "$proj/bin/.devbin/lib/cmd/clean" rust --dry-run
  assert_success
  assert_output_contains "A real run would REFUSE: PATH resolves into the tree(s) above."
  # And a PATH entry spelled from // into the tree, under an ordinary root.
  rm "$bin/devbinslashzz"
  runclean_path "$proj" "/$proj/target/release:$PATH" rust --dry-run
  assert_success
  assert_output_contains "(PATH entry)"
  assert_output_contains "A real run would REFUSE: PATH resolves into the tree(s) above."
}

@test "a relative PATH entry holding a link into the tree is refused, however it is spelled (0131)" {
  # command -v answers a relative path for a command found through a relative
  # PATH entry, and the guard skipped every answer that was not absolute, so a
  # link in ./tools or tools, the Rails ./bin idiom, went unrefused. The answer
  # is read from the project root, as the lookup was.
  proj="$(rustproj)"
  mktarget "$proj"
  printf '#!/bin/sh\n' >"$proj/target/release/devbinrelzz"
  chmod +x "$proj/target/release/devbinrelzz"
  mkdir -p "$proj/tools"
  ln -s ../target/release/devbinrelzz "$proj/tools/devbinrelzz"
  local entry
  for entry in tools ./tools; do
    runclean_path "$proj" "$entry:$PATH" rust --dry-run
    assert_success
    [[ "$output" == *"A real run would REFUSE: PATH resolves into the tree(s) above."* ]] ||
      fail "a link through the relative PATH entry $entry is not refused: $output"
  done
}

@test "a directory the walk can read but not search is named, and makes the scan partial (0131, 0145)" {
  # macOS's find passes over a directory it can read but not search, mode r--,
  # printing nothing beneath it, no error, and exiting 0, so a tree beneath it
  # went unseen and the scan read as whole. GNU find names it in its own words,
  # so the option's own naming is what this arm holds on both. The directory is
  # no candidate, and is not listed as one.
  proj="$(rustproj)"
  mkdir -p "$proj/vendor/crate"
  mktarget "$proj/vendor/crate"
  chmod 644 "$proj/vendor"
  if [ -x "$proj/vendor" ]; then
    chmod 755 "$proj/vendor"
    skip "running with permissions that search a mode-644 directory"
  fi
  runclean "$proj" rust --dry-run
  local st="$status" out="$output"
  chmod 755 "$proj/vendor"
  [ "$st" -eq 1 ] || fail "exited $st, not 1: $out"
  # The shared sentence since issue 0145, find_walk's, for every walk.
  [[ "$out" == *"cannot search $proj/vendor -- nothing beneath it was looked at"* ]] ||
    fail "the directory is not named: $out"
  [[ "$out" == *"THE SCAN WAS PARTIAL"* ]] || fail "the scan is not called partial: $out"
  [[ "$out" != *"could not be read -- not classified"* ]] || fail "the directory is listed as a candidate: $out"
}

@test "a directory the walk prunes, .git at 0644, is not examined, and the scan is whole (0145)" {
  # find_walk's clause ran before the walk's own prune, so a .git it can list
  # but not search made the scan partial, and fullcycle's clean refused the
  # cycle. clean's own clause sat after its prune.
  proj="$(rustproj)"
  mkdir -p "$proj/.git/objects"
  mktarget "$proj"
  chmod 644 "$proj/.git"
  if [ -x "$proj/.git" ]; then
    chmod 755 "$proj/.git"
    skip "running with permissions that search a mode-644 directory"
  fi
  runclean "$proj" rust --dry-run
  local st="$status" out="$output"
  chmod 755 "$proj/.git"
  [ "$st" -eq 0 ] || fail "exited $st, not 0: $out"
  [[ "$out" != *"cannot search"* ]] || fail "a pruned directory was examined: $out"
  [[ "$out" != *"THE SCAN WAS PARTIAL"* ]] || fail "the scan is called partial: $out"
}

# ---------------------------------------------------------------------------
# ARM -- a sibling cannot split a tree (issue 0137)
# ---------------------------------------------------------------------------

@test "a sibling that sorts between a tree and its children does not split it: target.bak, target-old, and a tree found by its tag (0137)" {
  # `.` and `-` sort below `/`, so target.bak and target-old sort between target
  # and target/n1, and nesting was tested against the last root kept only:
  # target/n1 was listed as a tree of its own, skipped and marked, and then
  # removed with target.
  #
  # THE WALK NO LONGER LOOKS INSIDE A TREE FOUND BY NAME, so target/n1 is never
  # listed and that shape is held by the prune, not by the nesting test. A tree
  # found by its tag is walked into, and the second half below is the shape
  # that still reaches the nesting test: a mutant testing the last root kept
  # survived the first half alone.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$proj/target/n1/debug/.fingerprint"
  cargo_tag "$proj/target/n1"
  : >"$proj/target/n1/.rustc_info.json"
  # THE CONTROL: alone, target/n1 is target's per-node directory, and nothing
  # is skipped.
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "per-node: $proj/target/n1"
  refute_output_contains "SKIPPED"
  cp -R "$proj/target" "$proj/target.bak"
  cp -R "$proj/target" "$proj/target-old"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "3 target tree(s)"
  assert_output_contains "per-node: $proj/target/n1"
  refute_output_contains "SKIPPED"
  refute_output_contains "would mark $proj/target/n1"
  # A TREE FOUND BY ITS TAG: a CARGO_TARGET_DIR named out, a per-node target
  # dir inside it, and then a copy of it beside it.
  rm -rf "$proj/target" "$proj/target.bak" "$proj/target-old"
  mkdir -p "$proj/out/debug/.fingerprint" "$proj/out/n1/debug/.fingerprint"
  cargo_tag "$proj/out"
  cargo_tag "$proj/out/n1"
  : >"$proj/out/n1/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "per-node: $proj/out/n1"
  refute_output_contains "SKIPPED"
  cp -R "$proj/out" "$proj/out.bak"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "2 target tree(s)"
  assert_output_contains "per-node: $proj/out/n1"
  refute_output_contains "SKIPPED"
  refute_output_contains "would mark $proj/out/n1"
}

# ---------------------------------------------------------------------------
# ARM -- every path whole, nothing outside the project, and a crate is no
# tree (issue 0141)
#
# Each shape was driven with a dry run beside a control: a newline
# in a name listed a tree OUTSIDE the project, a trailing TAB listed the source
# directory beside the tree, a crate built with --target-dir . listed its own
# source, and the same at the project root hid every real tree. These arms run
# for real, with --force, because what they guard is the removal.
# ---------------------------------------------------------------------------

@test "a name holding a newline does not reach a tree outside the project, and a real run leaves it (0141)" {
  proj="$(rustproj)"
  # THE CONTROL: a real tree in the project, which the same run removes.
  mktarget "$proj"
  # The victim, OUTSIDE the project: a real build tree with its manifest.
  local victim="$BATS_TEST_TMPDIR/outside/victim"
  mkdir -p "$victim"
  mktarget "$victim"
  # Inside the project, a directory named x<newline> whose subtree spells the
  # victim's absolute path down to its target/.
  mkdir -p "$proj/x"$'\n'"$victim/target"
  runclean "$proj" rust --force
  assert_success
  assert_directory_exists "$victim/target"
  assert_directory_not_exists "$proj/target"
  assert_output_contains "1 target tree(s) removed"
  # The crafted directory is one path, and printed as one, quoted.
  assert_output_contains "$(printf '%q' "$proj/x"$'\n'"$victim/target")"
}

@test "a name ending in a TAB lists that tree, not the source directory beside it, and a real run removes only it (0141)" {
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/out/src" "$proj/out"$'\t'"/debug/.fingerprint"
  : >"$proj/out/src/keep.rs"
  cargo_tag "$proj/out"$'\t'
  runclean "$proj" rust --force
  assert_success
  assert_file_exists "$proj/out/src/keep.rs"
  assert_directory_not_exists "$proj/out"$'\t'
  assert_output_contains "removed  $(printf '%q' "$proj/out"$'\t')"
  assert_output_contains "1 target tree(s) removed"
}

@test "a crate built with --target-dir . is built in place and never removed; the trees beneath and beside it still are (0141)" {
  proj="$(rustproj)"
  # THE CONTROL: a real tree beside it, removed. Each tree the arm makes is one of
  # these, so the trees removed are counted off them.
  local d
  local -a made=("$proj" "$proj/member")
  mktarget "${made[0]}"
  # A workspace member cargo built into itself: its markers in its own root.
  mkdir -p "$proj/member/src" "$proj/member/debug/.fingerprint"
  : >"$proj/member/src/lib.rs"
  : >"$proj/member/.rustc_info.json"
  cargo_tag "$proj/member"
  # And an ordinary tree beneath it, which a candidate at member/ hid as nested.
  mktarget "${made[1]}"
  runclean "$proj" rust --force
  assert_success
  assert_file_exists "$proj/member/src/lib.rs"
  assert_file_exists "$proj/member/Cargo.toml"
  assert_output_contains "in place $proj/member (holds its own Cargo.toml)"
  # The trees removed are the ones mktarget made, and the in-place build is not.
  for d in "${made[@]}"; do assert_directory_not_exists "$d/target"; done
  assert_output_contains "${#made[@]} target tree(s) removed"
}

@test "the project root holding cargo's markers hides no tree beneath it, and nothing is written into it (0141)" {
  proj="$(rustproj)"
  mktarget "$proj"
  : >"$proj/.rustc_info.json"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "in place $proj (the project root)"
  assert_output_contains "1 target tree(s)"
  refute_output_contains "SKIPPED"
  refute_output_contains "would mark"
  runclean "$proj" rust --force
  assert_success
  assert_directory_not_exists "$proj/target"
  assert_file_not_exists "$proj/.metadata_never_index"
  assert_file_exists "$proj/.rustc_info.json"
  # A ROOT HOLDING NO MANIFEST OF ITS OWN is set aside all the same: it is the
  # project, not a tree, so the manifest test alone cannot be what keeps it out
  # of the nesting test.
  rm "$proj/Cargo.toml"
  mkdir -p "$proj/crate"
  mktarget "$proj/crate"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "in place $proj (the project root)"
  assert_output_contains "1 target tree(s)"
}

@test "a candidate outside the project root is a devbin defect, and the run acts on none of the scan (0141)" {
  # Unreachable through a real find, which is the point: the guarantee does not
  # rest on parsing alone. A find that answers with a path outside the project,
  # as a broken reader would produce, stops the run before anything is removed.
  proj="$(rustproj)"
  mktarget "$proj"
  local victim="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$victim" "$BATS_TEST_TMPDIR/fakebin"
  mktarget "$victim"
  printf '#!/usr/bin/env bash\nprintf "%%s\\0" "%s/target" "%s/target"\n' "$proj" "$victim" >"$BATS_TEST_TMPDIR/fakebin/find"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/find"
  runclean_path "$proj" "$BATS_TEST_TMPDIR/fakebin:$PATH" rust --force
  assert_failure
  assert_output_contains "is not beneath $proj"
  assert_output_contains "nothing was removed"
  assert_directory_exists "$victim/target"
  assert_directory_exists "$proj/target"
}

@test "a tree whose name ends in a newline gets its own PATH check, not its neighbour's (0141)" {
  # The PATH guard re-spelled a tree through $(...), which strips a trailing
  # newline: out<LF> was compared as out/, so a link into it went unlisted and
  # unrefused, and a PATH entry in the source directory out/ was blamed on it.
  # The removal itself was exact; the refusal was not.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  local t="$proj/out"$'\n' bin="$BATS_TEST_TMPDIR/pathbin"
  mkdir -p "$t/release/.fingerprint" "$bin"
  cargo_tag "$t"
  printf '#!/bin/sh\n' >"$t/release/devbintoolzz"
  chmod +x "$t/release/devbintoolzz"
  ln -s "$t/release/devbintoolzz" "$bin/devbintoolzz"
  runclean_path "$proj" "$bin:$PATH" rust --dry-run
  assert_success
  assert_output_contains "PATH resolves into $(printf '%q' "$t")"
  assert_output_contains "A real run would REFUSE: PATH resolves into the tree(s) above."
  # And a PATH entry in the source directory out/ is not blamed on it.
  rm "$bin/devbintoolzz"
  mkdir -p "$proj/out/bin"
  printf '#!/bin/sh\n' >"$proj/out/bin/devbinsrczz"
  chmod +x "$proj/out/bin/devbinsrczz"
  runclean_path "$proj" "$proj/out/bin:$PATH" rust --dry-run
  assert_success
  refute_output_contains "PATH resolves into"
  assert_output_contains "A real run would ask on the tty"
}

@test "a name holding a format character such as U+202E is printed quoted, byte by byte (0141)" {
  # [[:cntrl:]] does not match U+202E, the right-to-left override, so a crafted
  # name could display as another path in the list read before a y. Any byte
  # that is not printable ASCII quotes the name.
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  local d="$proj/evil"$'\xe2\x80\xae'"txt" shown
  mkdir -p "$d/debug/.fingerprint"
  cargo_tag "$d"
  shown="$(export LC_ALL=C; printf '%q' "$d")"
  [[ "$shown" == *'\342\200\256'* ]] || fail "the expected form is not byte-quoted: $shown"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$shown"
}

@test "a candidate that vanished since the walk is not there to classify, and is no partial scan (0141)" {
  # Another run's clean, or cargo's, can remove a candidate between the walk and
  # the reading of it; unguarded, it read as "cannot read" and the scan as
  # PARTIAL, so fullcycle refused. A find stubbed on PATH names one that is not
  # there, which is the race held still.
  proj="$(rustproj)"
  mktarget "$proj"
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/usr/bin/env bash\n: >"%s/find.ran"\nprintf "%%s\\0" "%s/target" "%s/ghost/target"\n' "$BATS_TEST_TMPDIR" "$proj" "$proj" >"$BATS_TEST_TMPDIR/fakebin/find"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/find"
  runclean_path "$proj" "$BATS_TEST_TMPDIR/fakebin:$PATH" rust --dry-run
  # THE STUB RAN: every assertion after this one is an absence, or a count the
  # real find gives too, so without it the arm is green with the stub never
  # reached.
  assert_file_exists "$BATS_TEST_TMPDIR/find.ran"
  assert_success
  assert_output_contains "1 target tree(s)"
  refute_output_contains "PARTIAL"
  refute_output_contains "cannot read"
}

@test "a name that is not ASCII is quoted under a UTF-8 locale too, byte by byte (0141)" {
  # Under a UTF-8 locale an e-acute is printable, so the rule is read over
  # bytes, in the C locale _clean_shown sets for itself. The U+202E arm above
  # cannot see that line, since this platform's UTF-8 locale already calls
  # U+202E unprintable, and a suite may run in C. The child runs under an
  # explicit UTF-8 locale here, and one that calls the e-acute printable: a
  # locale bash cannot load falls back to C on 5.0 and 5.2, where this arm could
  # not see the rule.
  local loc e shown
  loc="$(locale -a 2>/dev/null)" && loc="$(grep -m 1 -ixE '(en_US|C)\.utf-?8' <<<"$loc")" || loc=""
  [ -n "$loc" ] || skip "no UTF-8 locale on this runner: the UTF-8 case was NOT checked"
  LC_ALL="$loc" bash -c '[[ $1 != *[![:print:]]* ]]' _ "caf"$'\xc3\xa9' ||
    skip "$loc does not call an e-acute printable here: the UTF-8 case was NOT checked"
  proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  e="$proj/caf"$'\xc3\xa9'
  mkdir -p "$e/debug/.fingerprint"
  cargo_tag "$e"
  shown="$(export LC_ALL=C; printf '%q' "$e")"
  [[ "$shown" == *'\303\251'* ]] || fail "the expected form is not byte-quoted: $shown"
  export LC_ALL="$loc"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$shown"
}

@test "a project root is printed quoted too, in the stop for a candidate outside it (0141)" {
  # The outside-root stop printed the root raw, so a root whose name holds a
  # format character displayed as another path in the line naming the defect.
  # The root's other raw print, clean's own "cannot enter", is never reached:
  # the gate enters the same root first, in the words every devbin command uses
  # for it.
  proj="$(rustproj)"
  local odd="$BATS_TEST_TMPDIR/demo"$'\xe2\x80\xae'"x" shown
  shown="$(export LC_ALL=C; printf '%q' "$odd")"
  [[ "$shown" == *'\342\200\256'* ]] || fail "the expected form is not byte-quoted: $shown"
  mv "$proj" "$odd"
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/fakebin"
  mktarget "$BATS_TEST_TMPDIR/elsewhere"
  printf '#!/usr/bin/env bash\nprintf "%%s\\0" "%s/target"\n' "$BATS_TEST_TMPDIR/elsewhere" >"$BATS_TEST_TMPDIR/fakebin/find"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/find"
  runclean_path "$odd" "$BATS_TEST_TMPDIR/fakebin:$PATH" rust --dry-run
  assert_failure
  assert_output_contains "is not beneath $shown"
}

# ---------------------------------------------------------------------------
# ARM -- what this suite is green over
# ---------------------------------------------------------------------------

# _marker_in_fn <declare-f-text> <function> <marker> -- 0 when <function>'s
# body, as declare -f prints it, without comments, holds <marker> as a fixed
# string (issue 0170). The body ends at the first line that is exactly `}`,
# which declare -f gives only the function's own close, a nested function's
# being indented; a heredoc in the body holding such a line would end it
# early, and a marker after it would read as absent: red, never green.
_marker_in_fn() {
  local body
  body="$(awk -v f="$2" '$1 == f && $2 == "()" { on = 1; next } on && /^}$/ { on = 0 } on' <<<"$1")" || return 1
  grep -qF -- "$3" <<<"$body"
}

@test "the suite DECLARES whether it validated the markers against real cargo, and pins each marker in the code that tests it (0170)" {
  # Every fixture above is hand-built, so the classifier is proven against a
  # directory SHAPED like a cargo target and not against cargo's actual output.
  # That gap is real and this test does not close it; it makes it PRINT, so the
  # denominator is declared rather than inferred from a test nobody wrote.
  #
  # The one thing it does assert is that the marker set the code tests for is
  # the marker set this file builds -- so if someone edits one and not the
  # other, the suite stops being green over even the shaped case.
  # The classifier lives in lib/helpers since issue 0148, moved unchanged so
  # fullcycle asks the same question the clean does.
  #
  # CODE, NEVER A COMMENT, AND EACH IN THE FUNCTION THAT TESTS IT (issue 0170).
  # This grepped the whole of lib/helpers, and comment lines alone satisfied
  # most of the markers, so deleting their code left it green. `declare
  # -f` prints a function without its comments, and each marker is looked for,
  # as a fixed string, in the function that tests it. The per-node test
  # (cargo_target_root, issue 0168) and the walk's own markers (_clean_roots in
  # lib/cmd/clean, unpinned since 0148 moved the classifier) are held the same
  # way; lib/cmd/clean is sourced over a gatecmd that runs nothing.
  local fns walk stub pair
  fns="$(bash -c '. "$1/helpers" && declare -f _clean_marked_without_read _clean_has_markers _clean_peer_dirs cargo_target_root' _ "$DEVBIN_LIB_DIR")" ||
    fail "lib/helpers' marker functions could not be read"
  stub="$BATS_TEST_TMPDIR/stublib"
  mkdir -p "$stub"
  printf 'run_builtin_gate() { :; }\n' >"$stub/gatecmd"
  walk="$(DEVBIN_LIB="$stub" bash -c '. "$1/helpers" && . "$1/cmd/clean" && declare -f _clean_roots' _ "$DEVBIN_LIB_DIR")" ||
    fail "clean's walk, _clean_roots, could not be read"
  # Each is pinned by its test, not only its name: a half-deleted test, its
  # `-f` gone and the link test left, still names the marker.
  for pair in '_clean_has_markers|"$d/CACHEDIR.TAG"' '_clean_marked_without_read|[ -f "$1/.rustc_info.json" ]' \
    '_clean_marked_without_read|[ ! -L "$1/.rustc_info.json" ]' \
    '_clean_marked_without_read|[ -d "$1/debug/.fingerprint" ]' '_clean_marked_without_read|[ -d "$1/release/.fingerprint" ]' \
    'cargo_target_root|[ -f "$1/.rustc_info.json" ]'; do
    _marker_in_fn "$fns" "${pair%%|*}" "${pair#*|}" || fail "${pair%%|*} no longer tests for ${pair#*|} in its code"
  done
  for pair in "-name CACHEDIR.TAG" "-name .rustc_info.json" "CACHEDIR.TAG)" ".rustc_info.json)"; do
    grep -qF -- "$pair" <<<"$walk" || fail "clean's walk, _clean_roots, no longer has $pair in its code"
  done

  # MEASURED ONCE, OFF THE SUITE (issue 0131): cargo 1.98.1 writes the three
  # markers at a target dir's root, and a --target triple directory carries
  # CACHEDIR.TAG and debug/.fingerprint but no .rustc_info.json -- the fact the
  # per-node test rests on. That is a record, not a test; nothing here re-reads it.
  if command -v cargo >/dev/null 2>&1; then
    echo "# cargo IS present on this runner -- but no test here builds with it." >&3
    echo "# The markers remain validated by construction only." >&3
  else
    echo "# cargo is ABSENT on this runner: the marker set is unvalidated against" >&3
    echo "# real cargo output, by construction. Fixtures are hand-built." >&3
  fi
}

# ============================================================================
# --dry-run -- THE READ-ONLY HALF, REACHABLE WITHOUT A TERMINAL (issue 0042)
#
# Before this flag, `clean` could tell you what it would remove or it could
# remove it, and the first was reachable only from a tty: the confirmation
# prompt WAS the preview. In CI, a script, or any non-interactive context the
# only two states were REFUSE and DELETE. The scan is the valuable half and it
# was gated entirely behind a question.
#
# The properties that matter here are the ones a preview can quietly lose:
# it must CHANGE NOTHING, and it must reach its answer without a terminal. A
# test that only asserted the output text would pass against a `--dry-run` that
# printed the preview and then deleted the trees.
# ============================================================================

@test "--dry-run removes NOTHING and exits 0" {
  # THE WEAKEST TEST IN THIS SECTION AND IT SAYS SO. Driven against a --dry-run
  # that falls through to the removal path, this one stayed GREEN: the fall-
  # through reaches _clean_confirm, which on a runner with a readable /dev/tty
  # declines, so the trees survive for a reason that has nothing to do with the
  # flag. It is kept because the property is the one that matters; it is the
  # differential and preview tests below that actually hold it.
  proj="$(rustproj)"
  mktarget "$proj"
  runclean "$proj" rust --dry-run
  assert_success
  assert_directory_exists "$proj/target"
  assert_directory_exists "$proj/target/debug"
  assert_directory_exists "$proj/target/release"
}

@test "--dry-run still prints the scan -- the sizes and the trees" {
  proj="$(rustproj)"
  mktarget "$proj"
  runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "$proj/target"
  assert_output_contains "--dry-run: nothing was removed."
}

@test "--dry-run never CONSULTS the tty -- the differential against the prompt path" {
  # WHAT THIS RUNNER CAN AND CANNOT PROVE, said rather than assumed. It cannot
  # produce a process with no controlling terminal, so "works with no tty at
  # all" is NOT what is measured here; the test below declares that branch the
  # way the no-tty refusal test above already does.
  #
  # What IS measured is the difference that matters: under one pty at EOF, the
  # ordinary run reaches the prompt, gets nothing, and declines -- printing
  # `left alone`. The dry run prints its preview and never reaches the prompt
  # at all. Same fixture, same terminal, one flag apart. Asserting the preview
  # alone would pass equally against a --dry-run that asked first.
  require_pty
  proj="$(rustproj)"
  mktarget "$proj"

  run run_tty_eof env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$proj/bin/.devbin/lib/cmd/clean" rust
  assert_success
  assert_output_contains "left alone"

  run run_tty_eof env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$proj/bin/.devbin/lib/cmd/clean" rust --dry-run
  assert_success
  assert_output_contains "--dry-run: nothing was removed."
  refute_output_contains "left alone"
  assert_directory_exists "$proj/target"
}

@test "--dry-run on a runner with NO tty: asserted where reachable, declared where not" {
  # The state issue 0042 was actually filed about -- CI, a script, a cron -- and
  # this runner may not be able to enter it. Same declaration discipline as the
  # no-tty REFUSAL test above: a green over a branch that never ran is worse
  # than an admitted gap, because nothing afterwards says which one you have.
  if [ -r /dev/tty ]; then
    echo "# /dev/tty IS readable on this runner: the genuinely-tty-free path was" >&3
    echo "# NOT exercised. The pty-at-EOF differential above covers the reachable half." >&3
    skip "no controlling-terminal-free runner available; branch declared unexercised"
  fi
  proj="$(rustproj)"
  mktarget "$proj"
  run env DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" \
    DEVBIN_NAME=demo DEVBIN_ACTIVE_CLEAN="rust elixir swift" \
    "$proj/bin/.devbin/lib/cmd/clean" rust --dry-run </dev/null
  assert_success
  assert_output_contains "--dry-run: nothing was removed."
  refute_output_contains "no tty"
  assert_directory_exists "$proj/target"
}

@test "--dry-run NAMES which state a real run would reach" {
  # "Nothing was removed" answers the easy half. The asked half is "would this
  # have worked", and a preview that leaves it out sends the reader to try it.
  proj="$(rustproj)"
  mktarget "$proj"

  runclean "$proj" rust --dry-run
  assert_output_contains "would ask on the tty"

  runclean "$proj" rust --dry-run --force
  assert_output_contains "without asking"
}

@test "--dry-run REPORTS the blocked-binaries refusal instead of performing it" {
  # The arm that would otherwise make the flag useless exactly where it matters
  # most: a `die` here exits non-zero, and a caller reads that as "the scan
  # failed" rather than as "the scan found something".
  proj="$(rustproj)"
  mktarget "$proj"
  : >"$proj/target/debug/blockedbin"
  chmod +x "$proj/target/debug/blockedbin"
  mkdir -p "$proj/fakebin"
  ln -s "$proj/target/debug/blockedbin" "$proj/fakebin/blockedbin"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust --dry-run
  assert_success
  assert_output_contains "blockedbin"
  assert_output_contains "a real run would REFUSE"
  assert_output_contains "A real run would REFUSE"
  assert_directory_exists "$proj/target"
}

@test "the blocked refusal is UNCHANGED without --dry-run -- the control" {
  # Orthogonal to the test above and needed: a --dry-run that reported the
  # refusal by REMOVING the refusal would pass that test and lose the guard.
  proj="$(rustproj)"
  mktarget "$proj"
  : >"$proj/target/debug/blockedbin"
  chmod +x "$proj/target/debug/blockedbin"
  mkdir -p "$proj/fakebin"
  ln -s "$proj/target/debug/blockedbin" "$proj/fakebin/blockedbin"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust
  assert_failure
  assert_output_contains "refusing"
  assert_directory_exists "$proj/target"
}

@test "--dry-run with --force-blocked says a real run would PROCEED, and still removes nothing" {
  proj="$(rustproj)"
  mktarget "$proj"
  : >"$proj/target/debug/blockedbin"
  chmod +x "$proj/target/debug/blockedbin"
  mkdir -p "$proj/fakebin"
  ln -s "$proj/target/debug/blockedbin" "$proj/fakebin/blockedbin"

  PATH="$proj/fakebin:$PATH" runclean "$proj" rust --dry-run --force-blocked
  assert_success
  assert_output_contains "a real run would PROCEED"
  assert_directory_exists "$proj/target"
}

@test "a near-miss of --dry-run REFUSES rather than running for real" {
  # The same discipline fullcycle's parser has, for the same reason: for a verb
  # that deletes build trees the lethal failure is not a dry run that does
  # something, it is `--dryrun` falling through to a REAL run.
  proj="$(rustproj)"
  mktarget "$proj"

  runclean "$proj" rust --dryrun
  assert_failure
  assert_output_contains "unknown argument"

  runclean "$proj" rust --dry_run
  assert_failure
  assert_output_contains "unknown argument"

  runclean "$proj" rust -n
  assert_failure
  assert_output_contains "unknown argument"

  assert_directory_exists "$proj/target"
}

@test "the refusal names every flag, so it is actionable" {
  proj="$(rustproj)"
  mktarget "$proj"
  runclean "$proj" rust --yolo
  assert_failure
  assert_output_contains "only --dry-run, --force, --force-blocked and --refuse-partial are accepted"
}
