#!/usr/bin/env bats
#
# fullcycle -- from a total clean: remove the cargo trees, rebuild, test.
#
# THE SAFETY ARMS CARRY THIS FILE. This verb deletes the build tree and, on the
# project it was specified from, took `intent` off the machine for fifty minutes.
# The tests that matter are the ones proving it does NOT run: the strict parser,
# the dry run, and its exclusion from `build all`.

load ../lib/test_helper

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# A rust project that CAN rebuild. fullcycle refuses one that cannot, so this is
# the ordinary fixture and `rustproj_norebuild` below is the exceptional one.
rustproj() {
  local proj
  proj="$(mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
EOF
)"
  # `>/dev/null`: create_test_command PRINTS the path it created, and letting
  # that reach stdout makes this helper emit two lines, so every caller's $proj
  # becomes both paths joined. The symptom was rc 127 three tests away.
  create_test_command "$proj" build >/dev/null
  echo "$proj"
}

rustproj_norebuild() {
  local proj
  proj="$(mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
EOF
)"
  echo "$proj"
}

# ============================================================================
# THE PARSER -- the flag is only as safe as its neighbours
# ============================================================================

# A dry run that does something is not the lethal failure. `--dryrun` falling
# through to a REAL run because the parser ignored what it did not recognise is.
@test "a near-miss of --dry-run REFUSES rather than running for real" {
  local proj; proj="$(rustproj)"

  run devbin_run "$proj" fullcycle --dryrun
  assert_failure
  assert_output_contains "unknown argument"

  run devbin_run "$proj" fullcycle --dry_run
  assert_failure
  assert_output_contains "unknown argument"

  run devbin_run "$proj" fullcycle -n
  assert_failure
  assert_output_contains "unknown argument"
}

@test "an unknown argument names itself, so the refusal is actionable" {
  local proj; proj="$(rustproj)"
  run devbin_run "$proj" fullcycle --yolo
  assert_failure
  assert_output_contains "--yolo"
  assert_output_contains "only --dry-run and --force are accepted"
}

# ============================================================================
# THE DRY RUN
# ============================================================================

@test "--dry-run lists the phases and executes NOTHING" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target"
  : >"$proj/target/canary"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "DRY RUN"
  assert_output_contains "clean rust"
  # The test phase is `test all` (issue 0083): one definition of the tests
  # for this cycle and for `all`.
  assert_output_contains "bin/devbin test all"
  refute_output_contains "test rust"
  # THE PROOF IT RAN NOTHING. A dry run that deleted the tree would still have
  # printed everything above.
  assert_file_exists "$proj/target/canary"
}

@test "--dry-run says what it CANNOT know rather than quoting another project's numbers" {
  local proj; proj="$(rustproj)"
  run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_contains "Not shown"
  # 113G and ~35 minutes are Intent's measurements of Intent's tree. Printing
  # them here would report another project's numbers as though they described
  # this one.
  refute_output_contains "113G"
  refute_output_contains "35 minutes"
}

@test "--dry-run prints the command it would ACTUALLY run, flag for flag (issue 0054)" {
  # THIS TEST USED TO ASSERT `refute_output_contains "clean rust --force"` FOR
  # THE NO-FORCE CASE, AND THAT ASSERTION IS A PREFIX OF THE STRING IT MEANT TO
  # FORBID. When 0047 made this verb pass `--force-blocked` always, the preview
  # went on printing the pre-0047 flag list -- and the containment check was
  # satisfied by `--force-blocked` either way, so it stayed green over a preview
  # describing a strictly WEAKER command than the one that runs. Exact lines
  # now, in both directions -- WHOLE lines since 0131: the containment check
  # that replaced the old one was a prefix of the line again, and stayed green
  # over a preview that dropped --refuse-partial.
  local proj; proj="$(rustproj)"

  # Since 0089 the clean phase runs with --force either way:
  # given, or answered by a person's y to the one question fullcycle asks. So
  # the no-force preview names that question, and the --force preview does not.
  run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_contains "asks first"
  assert_output_line "bin/devbin clean rust --force-blocked --force --refuse-partial"

  run devbin_run "$proj" fullcycle --dry-run --force
  assert_success
  refute_output_contains "asks first"
  assert_output_line "bin/devbin clean rust --force-blocked --force --refuse-partial"
}

@test "the preview and the real invocation come from ONE decision" {
  # The property, not the string. Two homes for the flag list is what let the
  # two drift, so this reads what the preview prints and asserts the launcher
  # is handed exactly that -- with `clean` replaced by a recorder.
  local proj; proj="$(rustproj)"
  create_test_command "$proj" clean \
    "$(printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "CLEAN-GOT: %%s\\n" "$*"\n')" >/dev/null

  run devbin_run "$proj" fullcycle --dry-run --force
  assert_success
  assert_output_line "bin/devbin clean rust --force-blocked --force --refuse-partial"

  # --force, so the run reaches the phase with no one to ask here.
  run devbin_run "$proj" fullcycle --force
  assert_output_line "CLEAN-GOT: rust --force-blocked --force --refuse-partial"
  # The consent record is devbin's own line, tagged (issue 0100).
  grep -q "^devbin| --force given -- nothing was asked" "$proj"/tmp/fullcycle/*.FULLCYC.out ||
    fail "the log does not carry the tagged --force record:
$(cat "$proj"/tmp/fullcycle/*.FULLCYC.out)"
}

@test "--dry-run prints the consent notice, because the preview is where it is read" {
  # The half of 0054 that is not cosmetic. The dry branch returns before
  # _fullcycle_run, so this was the one surface saying a consent is being given
  # on the operator's behalf and it was missing from the preview.
  local proj; proj="$(rustproj)"

  run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_contains "No --force given"
  assert_output_contains "HAS answered clean's blocked-binaries refusal for you"
  assert_output_contains "has NOT answered the removal prompt"
}

@test "--dry-run with --force prints NO consent notice -- there is no consent to report" {
  local proj; proj="$(rustproj)"
  run devbin_run "$proj" fullcycle --dry-run --force
  assert_success
  refute_output_contains "No --force given"
}

# ============================================================================
# THE CYCLE MUST BE ABLE TO PUT BACK WHAT IT TAKES AWAY
# ============================================================================

# THE DEFECT THIS FILE SHIPPED ONCE. fullcycle ran `clean rust` then `test rust`
# and nothing else. `clean rust` removes target/ INCLUDING release/, and
# `cargo test` builds debug binaries only -- so on a project where something on
# PATH resolves through target/release/ (Intent's `intent` is a symlink into
# exactly that), the cycle deleted the binary every pre-commit guard resolves
# through and never put it back. Net-destructive, under a name promising a cycle.
@test "REFUSES outright when the project has no build command to rebuild through" {
  local proj; proj="$(rustproj_norebuild)"

  run devbin_run "$proj" fullcycle --dry-run

  assert_failure
  assert_output_contains "REFUSING"
  assert_output_contains "cannot rebuild what it deletes"
  # WHAT TO RUN INSTEAD IS THE CYCLE'S OWN PHASES, READ FROM ITS PHASE LIST
  # (issue 0083). The refusal named `test rust` in a sentence of its own, a
  # second copy of the list that would have gone on naming it after the
  # phase became `test all`.
  assert_output_contains "bin/devbin clean rust"
  assert_output_contains "bin/devbin test all"
  refute_output_contains "test rust"
  # Less its build: this project has no build command to run.
  refute_output_contains "bin/devbin build all"
  # Refusing is the SAFE direction and skipping is not, so an inconclusive probe
  # must land here rather than quietly running a two-phase cycle.
  refute_output_contains "DRY RUN"
}

@test "the rebuild phase IS the middle phase when the project can rebuild" {
  local proj; proj="$(rustproj)"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "clean rust"
  assert_output_contains "build all"
  assert_output_contains "test all"
}

# The rebuild must sit BEFORE the tests. After them, a failing test would stop
# the cycle under the loop's own break and leave the tree stripped -- the
# restoring step not running exactly when something went wrong.
@test "the rebuild is ordered BEFORE the tests, not after them" {
  local proj; proj="$(rustproj)"

  run devbin_run "$proj" fullcycle --dry-run
  assert_success

  local order
  order="$(printf '%s\n' "$output" | grep -nE 'clean rust|build all|test all' | cut -d: -f1 | tr '\n' ' ')"
  local c b t
  c=$(grep -n -m1 'clean rust' <<<"$output" | cut -d: -f1)
  b=$(grep -n -m1 'build all' <<<"$output" | cut -d: -f1)
  t=$(grep -n -m1 'test all' <<<"$output" | cut -d: -f1)
  [ "$c" -lt "$b" ] || fail "clean is not before build (order: $order)"
  [ "$b" -lt "$t" ] || fail "build is not before test (order: $order)"
}

# THE STATE A FAILED CYCLE LEAVES, NAMED. The restoring step not running is
# exactly the case where its absence looks like the ordinary path. If `build
# all` fails after `clean` succeeded, the tree has been stripped and nothing
# left in the cycle will put it back -- and the symptom an operator actually
# meets is not a missing binary, it is a pre-commit gate refusing to let them
# commit, with a remedy line naming the tool that is absent. Reporting
# "stopping" and letting them find that out is the silent half.
@test "a phase failing AFTER the clean says the trees are gone and not rebuilt" {
  local proj; proj="$(rustproj_norebuild)"
  create_test_command "$proj" build '#!/usr/bin/env bash
printf "build: deliberately failing\n"
exit 1' >/dev/null

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "THE BUILD TREES WERE ALREADY REMOVED"
  assert_output_contains "dangling"
  assert_output_contains "build all"
  # The control for the arm below: a build that FAILED must not be reported as
  # a rebuild, or the fix for 0068 has merely swapped which case lies.
  refute_output_contains "passed after the clean"
  refute_output_contains "A failed clean can have removed"
}

# THE SAME WARNING IS FALSE ONCE A BUILD HAS PASSED (issue 0068). Measured in
# Intent: clean rc=0, build all rc=0, test rust rc=101, and the
# run then told the operator the trees had not been rebuilt and everything on
# PATH was dangling -- two minutes after the build had put them back. A false
# alarm on this branch teaches the reader to discount it on the day it is true.
@test "a TEST phase failing after a passing build does not say the trees are gone (0068)" {
  local proj; proj="$(rustproj)"
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "test: deliberately failing\n"
exit 101' >/dev/null

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "STOPPING: test all failed"
  refute_output_contains "ALREADY REMOVED"
  refute_output_contains "HAVE NOT BEEN REBUILT"
  refute_output_contains "is now dangling"
  # SAY WHAT IS TRUE, rather than only deleting what was false: a silent stop
  # after a destructive phase is the shape the warning was added to end.
  assert_output_contains "build all passed after the clean; the failure is in test all"
  # AND NO MORE THAN WAS MEASURED. rc=0 from a build is not evidence that it
  # restored release/, and the artefact check does not run on a failed cycle --
  # so the first cut of this fix, which said the failure was "not in the
  # rebuild", overclaimed in the opposite direction.
  refute_output_contains "not in the rebuild"
  assert_output_contains "makes NO claim that it restored release/"
  refute_output_contains "A failed clean can have removed"
}

# One cargo tree whose release/ holds `toolish`, and a PATH directory with a live
# link into it: the watched link the dark-link arms darken.
# fixture_links <proj> <dir>... -- how many symbolic links in <dir>s lead into
# <proj>: the links a fixture made for the PATH watch to count, read from the
# fixture, so no arm compares the watch's count with one written by hand
# (0286). None is a fixture that made nothing to watch, and fails.
fixture_links() {
  local proj="$1" d f n=0
  shift
  for d in "$@"; do
    for f in "$d"/*; do
      [ -L "$f" ] || continue
      case "$(readlink "$f")" in "$proj"/*) n=$((n + 1)) ;; esac
    done
  done
  [ "$n" -gt 0 ] || fail "the fixture made no link into $proj to watch"
  printf '%s' "$n"
}

_darklink_fixture() {
  local proj="$1"
  mkdir -p "$proj/crate/target/debug/.fingerprint" "$proj/crate/target/release" "$BATS_TEST_TMPDIR/pathbin"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin/toolish"
}

# THE TWO REPORTS ON ONE SCREEN MUST NOT BLAME DIFFERENT PHASES. A build that
# exits 0 without repopulating release/, then a failing test: the loop's report
# names the test, and the after-half still names the dark link. The loop's line
# may state only the build's exit code, or the two contradict each other.
@test "a TEST failure after a build that darkened a watched link reports BOTH, without contradiction (0068)" {
  local proj; proj="$(rustproj)"
  _darklink_fixture "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
echo "build: dev profile only, release/ untouched"
exit 0' >/dev/null
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "test: deliberately failing\n"
exit 101' >/dev/null

  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "watching: $(fixture_links "$proj" "$BATS_TEST_TMPDIR/pathbin") PATH symlink"
  assert_output_contains "STOPPING: test all failed"
  assert_output_contains "build all passed after the clean; the failure is in test all"
  refute_output_contains "not in the rebuild"
  refute_output_contains "ALREADY REMOVED"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "toolish"
  refute_output_contains "A failed clean can have removed"
}

# ONE STATE, ONE CAUSE, ONE REMEDY (issue 0071). A build that FAILS after a
# passing clean, with a watched link dark: the loop already says the trees were
# not rebuilt and names `build all`. The link check used to add that a
# dev-profile build had not repopulated release/ and to prescribe a RELEASE
# profile -- a mechanism that did not happen, and a second remedy that differs
# from the first.
@test "a FAILED build with a dark watched link gives one cause and one remedy (0071)" {
  local proj; proj="$(rustproj)"
  _darklink_fixture "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
printf "build: deliberately failing\n"
exit 1' >/dev/null

  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "watching: $(fixture_links "$proj" "$BATS_TEST_TMPDIR/pathbin") PATH symlink"
  assert_output_contains "STOPPING: build all failed"
  assert_output_contains "THE BUILD TREES WERE ALREADY REMOVED"
  # The dark link is still NAMED -- the list is measured, only its cause was wrong.
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "toolish"
  refute_output_contains "dev-profile"
  refute_output_contains "RELEASE profile"
  refute_output_contains "A failed clean can have removed"
  local n
  # `|| true`: grep -c exits 1 on zero matches, and zero is a count the check
  # below must see rather than an abort.
  n="$(printf '%s\n' "$output" | grep -c 'before doing anything else' || true)"
  [ "$n" -eq 1 ] || fail "expected ONE remedy, found $n:
$output"
}

# A partial clean (issue 0072). `clean` removes trees one at a time and dies on
# the first it cannot remove, so a clean that FAILED may already have darkened
# a watched link. The stub stands in for that: a project handler shadows the
# built-in, removes the one tree and exits non-zero.
_partialclean_fixture() {
  local proj="$1" removes="$2"
  _darklink_fixture "$proj"
  local rm_line=""
  [ "$removes" = 1 ] && rm_line="rm -rf \"$proj/crate/target/release\""
  create_test_command "$proj" clean "#!/usr/bin/env bash
case \"\${1:-}\" in --help) exit 0 ;; esac
$rm_line
printf 'clean: deliberately failing\n'
exit 1" >/dev/null
}

@test "a clean that fails PARTWAY still reports the watched link it darkened (0072)" {
  local proj; proj="$(rustproj)"
  _partialclean_fixture "$proj" 1

  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "watching: $(fixture_links "$proj" "$BATS_TEST_TMPDIR/pathbin") PATH symlink"
  assert_output_contains "clean: deliberately failing"
  assert_output_contains "STOPPING: clean rust failed"
  assert_output_contains "A failed clean can have removed trees before it failed"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "toolish"
  assert_output_contains "The clean failed and may have removed what these resolved through"
  # Nothing here knows a build passed, or that a clean did.
  refute_output_contains "dev-profile"
  refute_output_contains "No build passed after the clean"
  refute_output_contains "HAVE NOT BEEN REBUILT"
  local n
  # `|| true`: grep -c exits 1 on zero matches, and zero is a count the check
  # below must see rather than an abort.
  n="$(printf '%s\n' "$output" | grep -c 'before doing anything else' || true)"
  [ "$n" -eq 1 ] || fail "expected ONE remedy, found $n:
$output"
}

@test "a clean that fails having removed NOTHING names no dark link and no remedy (0072)" {
  local proj; proj="$(rustproj)"
  _partialclean_fixture "$proj" 0

  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  # The fixture's link is watched, so the refutes below are not empty.
  assert_output_contains "watching: $(fixture_links "$proj" "$BATS_TEST_TMPDIR/pathbin") PATH symlink"
  assert_output_contains "clean: deliberately failing"
  assert_output_contains "STOPPING: clean rust failed"
  assert_output_contains "A failed clean can have removed trees before it failed"
  refute_output_contains "DARKENED BINARIES"
  refute_output_contains "before doing anything else"
  assert_output_contains "FULLCYCLE FINISHED -- rc=1"
}

# ============================================================================
# THE HEADER -- so a log can never be a verdict describing no commit
# ============================================================================

@test "the header records HEAD and the dirty count before anything runs" {
  local proj; proj="$(rustproj)"
  git -C "$proj" init -q
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "HEAD:"
  assert_output_contains "dirty:"
}

# `dirty: 0` on a directory that is not a checkout would claim the tree matches
# its commit when there is no commit to match -- the same false statement a bare
# sha makes on a dirty tree, pointing the other way.
@test "a fixture that is NOT a checkout says so rather than reporting zero dirty files" {
  local proj; proj="$(rustproj)"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "not a checkout"
  refute_output_contains "0 file(s)"
}

@test "a fixture git refuses to read says so in the header, never 'not a checkout' (0185)" {
  local proj; proj="$(rustproj)"
  git -C "$proj" init -q
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  require_git_refusal "$proj"

  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "dirty: a checkout git could not read"
  refute_output_contains "not a checkout"
}

@test "a fixture that is not a checkout says so under a GIT_DIR inherited from another repository (0185)" {
  # The header's probe asked a plain git, which took the inherited GIT_DIR's
  # repository for this one; the count, through git_readonly, did not, failed
  # under pipefail, and took the header down before its dirty line.
  local proj other; proj="$(rustproj)"
  other="$DEVBIN_TEST_TMPDIR/other"
  mkdir -p "$other"
  git -C "$other" init -q

  GIT_DIR="$other/.git" run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "dirty: not a checkout"
}

@test "over an index git cannot read, the header says so in devbin's words and the run goes on (0186)" {
  # The probe passed and the count's status failed into wc under pipefail, so
  # --dry-run exited with git's 128 after a bare sha, in no words of devbin's.
  local proj sha; proj="$(rustproj)"
  printf 'one\n' >"$proj/NOTES.txt"
  git -C "$proj" init -q
  git -C "$proj" add -A
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q -m base
  sha="$(git -C "$proj" rev-parse HEAD)"
  printf 'two\n' >>"$proj/NOTES.txt"
  # THE CONTROL: with the index readable, the one edited file is counted.
  run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_contains "HEAD:  $sha +dirty"
  assert_output_contains "dirty: 1 file(s)"
  break_git_index "$proj"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_line "HEAD:  $sha +unreadable"
  assert_output_line "dirty: a checkout git could not read -- these bytes are not compared to anything -- fatal: .git/index: index file smaller than expected"
  refute_output_contains " file(s)"
}

@test "a status that answers but warns, as of a directory it could not open, prints the warning beside the count (0186)" {
  # The status was read with its stderr dropped, so a warning git gave on its
  # way to an answer went with it, where the count's pipe had let it through.
  # The count is git's, and the warning is the only sign of what it missed.
  local proj; proj="$(rustproj)"
  printf 'one\n' >"$proj/NOTES.txt"
  git -C "$proj" init -q
  git -C "$proj" add -A
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q -m base
  mkdir -p "$proj/locked"
  printf 'x\n' >"$proj/locked/inside.txt"
  # THE CONTROL: readable, the untracked file is counted and git warns of nothing.
  LC_ALL=C run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_line "dirty: 1 file(s)"
  refute_output_contains "could not open directory"
  chmod 000 "$proj/locked"
  if [ -r "$proj/locked" ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  LC_ALL=C run devbin_run "$proj" fullcycle --dry-run
  chmod 755 "$proj/locked"
  assert_output_line "dirty: 0 file(s)"
  assert_output_line "warning: could not open directory 'locked/': Permission denied"
}

# ============================================================================
# A GREEN CYCLE THAT DARKENED THE TOOLCHAIN IS THE FALSE GREEN
# ============================================================================

# MEASURED IN THE FIELD BEFORE THIS ARM EXISTED. A cold cycle in one consumer:
# clean rust rc=0, build all rc=0, test rust rc=0, FULLCYCLE FINISHED rc=0 --
# and its CLI and daemon links in `~/.local/bin` were left dangling into a release/
# the clean had deleted, because `build all` there is a dev-profile build. The
# probe asked whether a build VERB exists; the property is whether release
# artefacts come back. That project satisfied the proxy and failed the property.
@test "a cycle that leaves a PATH symlink dangling REPORTS it and goes RED" {
  local proj; proj="$(rustproj)"
  # BESIDE THE CRATE'S Cargo.toml, WITH THE MARKERS. clean removes a target/
  # only when it sits alongside a manifest and carries cargo's own markers --
  # the first cut of this fixture put it at the project root, clean correctly
  # removed nothing, and the arm failed for a reason that was not the subject.
  _darklink_fixture "$proj"
  # A build that SUCCEEDS without repopulating release/ -- the field case's shape.
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
echo "build: dev profile only, release/ untouched"
exit 0' >/dev/null

  # A FAKE cargo SO EVERY PHASE IS GREEN. Without it `cargo test` fails and the
  # arm proves only that the check fires after a failure -- which the branch it
  # replaced already did. The defect measured in the field was rc=0 THROUGHOUT,
  # so the arm has to reproduce a wholly green cycle that still did damage.
  cat >"$BATS_TEST_TMPDIR/pathbin/cargo" <<'CARGO'
#!/usr/bin/env bash
echo "cargo: stub, $*"
exit 0
CARGO
  chmod +x "$BATS_TEST_TMPDIR/pathbin/cargo"

  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  # EVERY PHASE REPORTED rc=0 AND THE RUN IS STILL RED. That is the whole point:
  # a green cycle that darkened the toolchain is the false green this verb exists
  # to avoid, and it shipped that way.
  assert_output_contains "phase: clean rust"
  refute_output_contains "STOPPING"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "toolish"
  assert_output_contains "DANGLING"
  # The control for 0071: a build that PASSED keeps the dev-profile cause.
  assert_output_contains "a dev-profile build does not"
  assert_output_contains "Rebuild with a RELEASE profile"
}

@test "the PATH watch reads an entry written after an entry holding a newline, as a shell does (0248)" {
  # The watch split PATH with a `read -r -a`, which stopped at the newline,
  # so a link on an entry after it was never watched, and a cycle that darkened
  # it said nothing.
  local proj; proj="$(rustproj)"
  _darklink_fixture "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
echo "build: dev profile only, release/ untouched"
exit 0' >/dev/null
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BATS_TEST_TMPDIR/pathbin/cargo"
  chmod +x "$BATS_TEST_TMPDIR/pathbin/cargo"
  mkdir -p "$BATS_TEST_TMPDIR/odd"$'\n'"dir"

  PATH="$BATS_TEST_TMPDIR/odd"$'\n'"dir:$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "watching: $(fixture_links "$proj" "$BATS_TEST_TMPDIR/pathbin") PATH symlink"
  assert_failure
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "toolish"
}

# _partial_cycle_fixture <proj> -- a cycle over a partial scan: the dark-link
# fixture, a build that says it ran, a cargo on PATH, and a directory locked so
# the clean's scan cannot read it. The arms below share it.
_partial_cycle_fixture() {
  local proj="$1"
  _darklink_fixture "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
echo "the build ran"
exit 0' >/dev/null
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BATS_TEST_TMPDIR/pathbin/cargo"
  chmod +x "$BATS_TEST_TMPDIR/pathbin/cargo"
  mkdir -p "$proj/locked"
  lock "$proj/locked"
}

@test "a clean whose scan is partial refuses inside the cycle: nothing is removed, and nothing goes dark (0131)" {
  # Driven for 0131: a partial clean removed what it found
  # and exited 1, and the cycle, reading a failed clean, stopped before the
  # rebuild with the tree gone, so the watched link went dark -- where the clean
  # before 0131 exited 0 and the cycle rebuilt. The clean phase carries
  # --refuse-partial now, so a partial scan is refused before it removes anything.
  local proj; proj="$(rustproj)"
  _partial_cycle_fixture "$proj"
  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle --force
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "refusing, as --refuse-partial asks"
  refute_output_contains "the build ran"
  [ -d "$proj/crate/target/release" ] || fail "the clean removed the tree: $output"
  [ -e "$BATS_TEST_TMPDIR/pathbin/toolish" ] || fail "the watched link went dark: $output"
}

@test "without --force, a partial scan stops the cycle at its preview, which says a real clean would refuse; nothing is removed (0131)" {
  # Only the --force path over a partial scan was tested (0131). Without it,
  # the preview runs first: it is the clean phase's own command with --dry-run
  # added, and over a partial scan it says at once that the real clean would
  # refuse, exits 1, and the cycle stops there.
  #
  # UNDER A TERMINAL, ANSWERED y. Here a preview that failed to stop the cycle
  # would reach the question, and the refuted prompt below is what goes red
  # then; the absences after it hold even so, since the clean phase then
  # refuses on its own --refuse-partial. The tty-free twin below is the same
  # control wherever expect is missing.
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  _partial_cycle_fixture "$proj"
  run run_tty_answer y sh -c "cd '$proj' && PATH='$BATS_TEST_TMPDIR/pathbin':\"\$PATH\" ./bin/devbin fullcycle"
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "STOPPING: the preview of clean rust failed. Nothing was removed."
  assert_output_contains "A real run would REFUSE: the scan is partial, and --refuse-partial was given."
  refute_output_contains "Remove these and run the full cycle?"
  refute_output_contains "the build ran"
  [ -d "$proj/crate/target/release" ] || fail "the preview removed the tree: $output"
  [ -e "$BATS_TEST_TMPDIR/pathbin/toolish" ] || fail "the watched link went dark: $output"
}

@test "without --force or a terminal, a partial scan still stops at the preview, before a terminal is asked for (0131)" {
  # The tty-free twin of the arm above, live on every runner: a preview that
  # failed to stop the cycle would go on to ask, and say that nobody is here to
  # answer.
  local proj; proj="$(rustproj)"
  _partial_cycle_fixture "$proj"
  PATH="$BATS_TEST_TMPDIR/pathbin:$PATH" run devbin_run "$proj" fullcycle
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "STOPPING: the preview of clean rust failed. Nothing was removed."
  refute_output_contains "no tty:"
}

# THE HOLE IN THE BEFORE/AFTER CONTROL. Whether that consumer's `--version` worked
# before the cold cycle is not known, and it is probable the binaries were
# ALREADY dark, after a full clean earlier that day. If so, the run that
# reported rc=0 was the SECOND green report over the same damage -- and the
# before/after control would have said nothing, correctly, because it records
# only links that resolved at the start. A dangling symlink is invisible to a
# PATH resolver, so nothing else on the machine reports it either.
@test "links ALREADY dangling before the run are reported, and do not fail it" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$BATS_TEST_TMPDIR/darkbin"
  : >"$proj/crate/Cargo.toml"
  # A symlink into the tree whose target never existed: dark before we start.
  ln -s "$proj/crate/target/release/ghost" "$BATS_TEST_TMPDIR/darkbin/ghost"
  [ -L "$BATS_TEST_TMPDIR/darkbin/ghost" ] && [ ! -e "$BATS_TEST_TMPDIR/darkbin/ghost" ] ||
    fail "fixture is not actually dangling"

  PATH="$BATS_TEST_TMPDIR/darkbin:$PATH" run devbin_run "$proj" fullcycle --dry-run

  # REPORTED...
  assert_output_contains "ALREADY DANGLING BEFORE THIS RUN"
  assert_output_contains "ghost"
  # ...AND NOT BLAMED ON THE CYCLE. Failing here would make a project red for
  # somebody else's clean.
  assert_success
  refute_output_contains "DARKENED BINARIES IT DID NOT RESTORE"

  # AND ON THE REAL PATH TOO, WHICH IS WHERE IT COULD ACTUALLY BITE. The report
  # lives in the header, called from cmd_fullcycle on a dry run and from
  # _fullcycle_run on a real one -- and only in the second is `rc` a local of the
  # caller, so an assignment there reaches the verdict. Testing only the dry path
  # left a break that set rc=1 uncaught: ineffective on the path under test and
  # live on the path that was not.
  cat >"$BATS_TEST_TMPDIR/darkbin/cargo" <<'CARGO'
#!/usr/bin/env bash
exit 0
CARGO
  chmod +x "$BATS_TEST_TMPDIR/darkbin/cargo"
  create_test_command "$proj" build >/dev/null

  PATH="$BATS_TEST_TMPDIR/darkbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "ALREADY DANGLING BEFORE THIS RUN"
  assert_success
}

# THE POSITIVE CONTROL. Without it the arm above proves only that the report can
# print, not that it discriminates -- and a check that fires on every run is the
# same as one that fires on none.
@test "a cycle whose build DOES restore the artefact reports no damage" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug/.fingerprint" "$proj/crate/target/release" "$BATS_TEST_TMPDIR/pathbin2"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin2/toolish"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/release"
: >"$PWD/crate/target/release/toolish"
chmod +x "$PWD/crate/target/release/toolish"
echo "build: release artefact restored"
exit 0' >/dev/null

  PATH="$BATS_TEST_TMPDIR/pathbin2:$PATH" run devbin_run "$proj" fullcycle --force

  refute_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
}

# ============================================================================
# EXCLUSION FROM `all` -- the catalogue expressing what only a project could
# ============================================================================

# The whole reason the in-all column exists. Before it, `in_all` read through
# cfg_get's hardcoded `true` default, so a project could exclude an option and
# the framework shipping it could not -- and `build all` would have cleaned the
# cargo tree in every project declaring rust.
@test "fullcycle is a COMMAND, so build ships no options and build all cannot reach it" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target"
  : >"$proj/target/canary"

  # `all` sweeps a command's OPTIONS. fullcycle is not one, so there is nothing
  # for a flag to exclude and nothing a config can opt back in -- which is why
  # this is stronger than the catalogue column it replaced. Tier 4 also
  # survives: build still ships no option set at all.
  run devbin_run "$proj" build all

  # The project HAS a build command, so `build all` succeeds -- and still cannot
  # reach fullcycle, because `all` sweeps a command's OPTIONS and fullcycle is
  # not one. That is stronger than the earlier form, which asserted a failure
  # and so proved only that nothing ran at all.
  assert_success
  assert_file_exists "$proj/target/canary"
  refute_output_contains "FULLCYCLE STARTING"
  refute_output_contains "clean rust"
}

@test "fullcycle runs when asked for by name" {
  local proj; proj="$(rustproj)"
  run devbin_run "$proj" fullcycle --dry-run
  assert_success
  assert_output_contains "DRY RUN"
}

@test "a cycle that watched NOTHING says so instead of returning a silent green" {
  # The after-half iterates the PATH symlinks that resolved BEFORE the run.
  # On a project with none it walks an empty list,
  # fires nothing, and used to say nothing -- so a cycle that measured NOTHING
  # emitted the identical rc=0 and the identical silence as one that measured
  # everything and was satisfied.
  #
  # One consumer is exactly such a project, which is the point: another's
  # dev-profile defect was caught in that other project ONLY by its PATH
  # symlinks. Drop that tripwire and
  # the same defect lands as a clean green. This test does not close that gap
  # (issue 0048) -- it pins the refusal to let the empty-set green pass itself
  # off as a measured one.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug" "$proj/crate/target/release"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
exit 0' >/dev/null
  passing_test_cmd "$proj"

  # No symlink anywhere on PATH points into this tree, so atrisk is empty.
  run devbin_run "$proj" fullcycle --force

  assert_output_contains "watching: NOTHING"
  # The vacuity DECLARATION is gone, replaced by an actual measurement (0048).
  # What survives is the two-way watch report and the refusal to claim damage
  # that was never detected. With neither profile holding a binary there is
  # nothing to compare, and the run says THAT rather than passing over it.
  assert_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  refute_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
}

# ============================================================================
# 0048: THE ARTEFACT CHECK THAT NEEDS NO TRIPWIRE
#
# The acceptance condition, held hard and correctly: the test must FAIL
# against a dev-profile build. A check that cannot go red on the dev-profile
# signature is the previous instrument again with better wording, and 0048's
# entire history is a check that asserted nothing while reporting rc=0.
#
# So the pair below is the whole point. Identical fixtures, identical absence
# of PATH symlinks, differing ONLY in what the build phase leaves behind.
# ============================================================================

# passing_test_cmd -- a `test` handler that succeeds.
#
# WITHOUT THIS NO FIXTURE IN THIS FILE EVER REACHES A GREEN CYCLE. The test
# phase reaches `test rust`, which shells out to real cargo, and cargo cannot
# find a Cargo.toml at the project root in these nested fixtures, so every
# cycle here has always ended red at the final phase. Every older assertion in
# this file is a refutation or reads failure-path output, so nothing noticed --
# and the artefact verdict below fires only on a cycle that otherwise
# SUCCEEDED, which is the one state the fixtures could not produce.
#
# A test file that can only produce one outcome is a test file that cannot see
# the other one.
passing_test_cmd() {
  create_test_command "$1" test '#!/usr/bin/env bash
exit 0' >/dev/null
}

# devprofile_build -- a build stub that populates debug/ and never release/.
# This is exactly what one consumer's `build all` does.
devprofile_build() {
  create_test_command "$1" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug"
printf "Signature: 8a477f597d28d172789f06886806bc55\\n# This file is a cache directory tag created by cargo.\\n" > "$PWD/crate/target/CACHEDIR.TAG"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
chmod +x "$PWD/crate/target/debug/demo"
exit 0' >/dev/null
}

# releaseprofile_build -- the control. Same stub, both profiles populated.
releaseprofile_build() {
  create_test_command "$1" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release"
printf "Signature: 8a477f597d28d172789f06886806bc55\\n# This file is a cache directory tag created by cargo.\\n" > "$PWD/crate/target/CACHEDIR.TAG"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/debug/demo" "$PWD/crate/target/release/demo"
exit 0' >/dev/null
}

@test "a DEV-PROFILE build goes RED with no PATH symlink anywhere near it" {
  # THE ACCEPTANCE TEST. One consumer is a project with no PATH links into its tree,
  # so before 0048 this exact scenario finished rc=0 and said only that it had
  # measured nothing. The tripwire that caught it in another is simply absent
  # here, and the defect is identical.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  devprofile_build "$proj"
  passing_test_cmd "$proj"

  run devbin_run "$proj" fullcycle --force

  assert_output_contains "watching: NOTHING"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  # RED, and that is the half that makes it a gate rather than a remark.
  [ "$status" -ne 0 ] || fail "a dev-profile cycle finished GREEN -- the check asserted nothing:
$output"
}

@test "the same cycle with a RELEASE-profile build is green -- the control" {
  # Without this, the test above passes for a project that always goes red.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"

  run devbin_run "$proj" fullcycle --force

  assert_output_contains "watching: NOTHING"
  refute_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  [ "$status" -eq 0 ] || fail "a release-profile cycle went red -- the check fires on a correct build:
$output"
}

@test "the no---force notice describes the refusal the operator ACTUALLY reaches" {
  # THIS TEST HAS NOW BEEN WRONG TWICE, IN OPPOSITE DIRECTIONS, AND THAT IS THE
  # WHOLE LESSON ON THIS ROW.
  #
  # First shape: the notice read "clean will ask, or refuse if there is no
  # terminal", describing `_clean_confirm` -- while the refusal a real operator
  # hit was the blocked-binaries `die`, which fires first and consults no
  # terminal. An operator was refused WITH a terminal and sent hunting a tty
  # problem that did not exist.
  #
  # Second shape: the notice was corrected to name BOTH refusals and state the
  # outright one as terminal-independent -- correct on the day. Then 0047
  # landed, fullcycle began passing `--force-blocked` always, and the outright
  # arm became UNREACHABLE from this verb. The notice stayed literally true
  # about clean and turned false about THIS CALLER: the original defect, one
  # layer out, arriving through its own fix.
  #
  # That was predicted when the split was proposed, with re-reading this prose
  # named as part of the work. It was.
  #
  # So what is pinned is not a wording. It is that the notice names the arm the
  # caller reaches, and does not promise a refusal that has been pre-answered.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/release" "$BATS_TEST_TMPDIR/pathbin4"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin4/toolish"

  # A PATH binary inside the tree clean would remove -- the blocked-binaries
  # scenario. Before 0047 this died there. Now it must NOT: fullcycle answers
  # that one, and the run proceeds to the tty refusal instead. No hang, because
  # the gate runs without a tty and fullcycle's own question refuses rather
  # than prompts (0089).
  PATH="$BATS_TEST_TMPDIR/pathbin4:$PATH" run devbin_run "$proj" fullcycle

  # The consent given on the operator's behalf must be STATED, not silent.
  assert_output_contains "HAS answered clean"
  assert_output_contains "blocked-binaries refusal for you"
  # And the one that has NOT been given, which is the refusal they will meet.
  assert_output_contains "has NOT answered the removal prompt"
  assert_output_contains "refuses without one"

  # It must not promise a refusal this caller can no longer reach.
  refute_output_contains "--force is the only way through"
  # Nor regress to the original single-mechanism sentence.
  refute_output_contains "clean will ask, or refuse if there is no terminal"
}

# ============================================================================
# fullcycle ASKS, ONCE, AT THE TOP (issue 0089)
# ============================================================================
#
# Before this a person at a terminal was never asked: every phase got the phase
# list on stdin, and since 0088 a nested gate reports no person. fullcycle now
# asks where its own gate knows a person is there, after showing what clean
# would remove, and passes --force to the clean phase on a y.

@test "at a terminal, fullcycle without --force shows what goes, asks once, and a y runs the cycle (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  run run_tty_answer y sh -c "cd '$proj' && ./bin/devbin fullcycle"
  refute_output_contains "no tty"
  assert_output_contains "--dry-run: nothing was removed"
  assert_output_contains "[y/N]"
  assert_output_contains "phase: build all"
  [ ! -e "$proj/target" ] || fail "target survived a y answer:
$output"
}

@test "at a terminal, an n removes nothing and stops the cycle before the build (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  run run_tty_answer n sh -c "cd '$proj' && ./bin/devbin fullcycle"
  assert_failure
  assert_output_contains "[y/N]"
  assert_output_contains "left alone"
  refute_output_contains "--- phase: build all"
  [ -e "$proj/target" ] || fail "an n removed the target tree"
}

@test "with its stdin piped, fullcycle refuses with no question, although a y waits on the terminal (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  run run_tty_answer y sh -c "cd '$proj' && printf 'y\\n' | ./bin/devbin fullcycle"
  assert_failure
  assert_output_contains "no tty"
  refute_output_contains "[y/N]"
  refute_output_contains "--- phase: build all"
  [ -e "$proj/target" ] || fail "target was removed through a pipe"
}

# THE WAIT ON A PERSON IS RECORDED, AND IS NOT GATE WALL (issue 0096). The
# question is asked before fullcycle's gate opens its log, so a person's think
# time falls outside the overhead meter's wall by construction -- nothing is
# subtracted and nothing is parsed -- and the gated run's first line records the
# answer and the wait, so the log still carries the consent.
@test "a slow y is recorded with its wait, and the wait is not charged to the gate's wall (0096)" {
  require_pty
  require_expect
  local proj log wall t0 t1 total
  proj="$(rustproj)"
  create_test_command "$proj" test '#!/usr/bin/env bash
sleep 3
printf "test result: ok. 1 passed; finished in 3.00s\n"' >/dev/null
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  t0="${EPOCHREALTIME//[!0-9]/}"
  DEVBIN_TEST_TTY_ANSWER_DELAY=6 run run_tty_answer y sh -c "cd '$proj' && ./bin/devbin fullcycle"
  t1="${EPOCHREALTIME//[!0-9]/}"
  total=$(((t1 - t0) / 1000000))

  assert_success
  # Tagged as devbin's own line (issue 0100), so the seal's extraction never
  # reads it as tool output.
  assert_output_contains "devbin| confirmed y to clean rust"
  log="$(ls "$proj"/tmp/fullcycle/*.FULLCYC.out)"
  # WHAT was consented to, not only that a y was given: the notice and the
  # preview print before the log exists, so this line is the log's record.
  grep -q "^devbin| confirmed y to clean rust --force-blocked --force --refuse-partial at the prompt after [6-9]s" "$log" ||
    fail "the log does not record the consent with its wait:
$(cat "$log")"
  wall="$(printf '%s\n' "$output" | sed -n 's/.*overhead: [^ ]* -- \([0-9]*\)s of GATE wall.*/\1/p')"
  [ -n "$wall" ] || fail "no overhead line:
$output"
  # AGAINST THE RUN'S OWN LENGTH, NEVER AN ABSOLUTE (issue 0199). This bound was
  # `-lt 9`, reasoning that the phases take about 3s, and under the suite's
  # parallel lane they took 14s, so it read red with the wait left out. The
  # arm times the whole run itself: with the 6s wait left out the wall is at
  # most that run less the wait, plus a second for the wall's whole seconds; with
  # it charged, the wall is the run less only what came before the prompt and
  # after the gate. Half the wait apart from the run separates the two however
  # slow the phases are. Measured by the arm rather than from the gate's own
  # phase lines, whose whole-second readings can each be a second out, and
  # which leave out the gate's own time between phases.
  [ "$wall" -lt $((total - 3)) ] || fail "the wall ${wall}s still carries the 6s wait: the whole run took ${total}s
$output"
}

@test "an n, asked before the gate, removes nothing and leaves no gate log (0096)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run run_tty_answer n sh -c "cd '$proj' && ./bin/devbin fullcycle"

  assert_failure
  assert_output_contains "left alone"
  [ -e "$proj/target" ] || fail "an n removed the target tree"
  [ ! -e "$proj/tmp/fullcycle" ] || fail "an n opened fullcycle's gate log: $(ls "$proj/tmp/fullcycle")"
}

# MORE FOR 0089. Each kills a mutant the arms above let
# live: the question asked before the preview, a failed preview read as a y,
# and a capital Y read as a no.

@test "fullcycle shows what goes BEFORE it asks, not after (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  run run_tty_answer y sh -c "cd '$proj' && ./bin/devbin fullcycle"
  # No status assertion: this fixture's test phase fails on its empty
  # Cargo.toml, after the part this arm is about.
  local before="${output%%\[y/N\]*}"
  [ "$before" != "$output" ] || fail "no [y/N] prompt:
$output"
  case "$before" in
    *"--dry-run: nothing was removed"*) ;;
    *) fail "the question came before the preview:
$output" ;;
  esac
}

@test "a preview that fails stops fullcycle before it asks, and nothing runs (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  create_test_command "$proj" clean \
    "$(printf '#!/usr/bin/env bash\ncase " $* " in *" --dry-run "*) exit 1 ;; esac\nprintf "CLEAN-RAN: %%s\\n" "$*"\n')" >/dev/null
  run run_tty_answer y sh -c "cd '$proj' && ./bin/devbin fullcycle"
  assert_failure
  assert_output_contains "the preview of clean rust failed"
  refute_output_contains "[y/N]"
  refute_output_contains "CLEAN-RAN"
  refute_output_contains "--- phase: build all"
}

@test "a capital Y is a yes too (0089)" {
  require_pty
  require_expect
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  run run_tty_answer Y sh -c "cd '$proj' && ./bin/devbin fullcycle"
  assert_output_contains "[y/N]"
  assert_output_contains "phase: build all"
  [ ! -e "$proj/target" ] || fail "target survived a Y answer:
$output"
}

@test "fullcycle without --force gets PAST the blocked-binaries refusal" {
  # The behaviour half of 0047, and the reason the row existed: the verb's
  # default invocation was unusable on exactly the project class it serves -- a
  # dev tree whose PATH resolves into its own target/release/. That is the
  # normal shape here and precisely the tree someone reaches for fullcycle to
  # rebuild from clean.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/release" "$BATS_TEST_TMPDIR/pathbin5"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin5/toolish"

  PATH="$BATS_TEST_TMPDIR/pathbin5:$PATH" run devbin_run "$proj" fullcycle

  # It must NOT die at the blocked arm any more.
  refute_output_contains "refusing: removing these trees would darken"
  # It must still say the binaries are at risk -- suppressing the refusal is
  # not the same as suppressing the warning, and 0047 asked for the first only.
  # Since 0089 a no---force run with nobody to ask stops at fullcycle's own
  # question, after the preview, so the warning met here is the preview's
  # WOULD, not the real run's WILL; both end in these words.
  assert_output_contains "STOP RESOLVING until rebuilt"
}

@test "the phase list holds NO safety decision -- the guard is the only copy" {
  # Issue 0051. `_fullcycle_can_rebuild` is a refusal, and a refusal that exists
  # twice can disagree with itself about which way to fail. It did: the guard in
  # cmd_fullcycle fails CLOSED, and the copy that used to live in
  # _fullcycle_phases failed OPEN into the net-destructive cycle the guard
  # exists to refuse.
  #
  # Pinned as a source assertion rather than a behaviour test on purpose: the
  # fail-open copy was UNREACHABLE, so no behaviour test could ever have seen
  # it. What is being protected is the shape, and only the source shows it.
  local body
  body="$(awk '/^_fullcycle_phases\(\)/,/^}/' "$DEVBIN_HOME/lib/cmd/fullcycle")"

  # Non-vacuity: the extractor must actually have found the function.
  grep -q 'clean rust' <<<"$body" ||
    fail "could not extract _fullcycle_phases -- the assertion below would be vacuous"

  grep -q '_fullcycle_can_rebuild' <<<"$body" &&
    fail "_fullcycle_phases tests the rebuild predicate again. It fails OPEN here
and CLOSED in cmd_fullcycle, and only call order decides which one you get:
$body"

  # And the phase must be emitted unconditionally, which is the other half:
  # the list asks for the build phase on every run, and the guard in
  # cmd_fullcycle is what refuses a project where it is empty (issue 0134).
  grep -qx '  _fullcycle_phase_for build' <<<"$body" ||
    fail "the rebuild phase is missing from the phase list entirely"
}

@test "the guard that refuses a project with no build verb is still there" {
  # The counterpart. Deleting the fail-open copy must not have taken the
  # protection with it -- that would swap one direction of the 0051 defect for
  # the other, and this is the direction that deletes a build tree.
  run bash -c "grep -c '_fullcycle_can_rebuild' '$DEVBIN_HOME/lib/cmd/fullcycle'"
  [ "$status" -eq 0 ]

  run bash -c "
    awk '/^cmd_fullcycle\(\)/,/^}/' '$DEVBIN_HOME/lib/cmd/fullcycle' |
      grep -c 'if ! _fullcycle_can_rebuild'
  "
  assert_output "1"
}

# ============================================================================
# 0050: THE RESTORE HALF
#
# The cycle used to have no way to put back what the clean removed, so on a
# dev-profile project it was correctly and PERMANENTLY red, as measured in
# the field. These drive the restore itself, with a `cargo` stub on PATH -- the
# same device create_test_command uses for devbin's own verbs, and the only way
# to exercise the orchestration without a real crate.
# ============================================================================

# cargo_stub <proj> <mode> -- a `cargo` on PATH. `restores` puts the release
# artefact back; `useless` builds nothing, which is the control.
cargo_stub() {
  local proj="$1" mode="$2" dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  if [ "$mode" = restores ]; then
    cat >"$dir/cargo" <<EOF
#!/usr/bin/env bash
mkdir -p "$proj/crate/target/release"
: >"$proj/crate/target/release/toolish"
chmod +x "$proj/crate/target/release/toolish"
exit 0
EOF
  else
    printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/cargo"
  fi
  chmod +x "$dir/cargo"
  printf '%s' "$dir"
}

# declare_restore <proj> <command line> -- add commands.fullcycle.restore.
#
# Appended rather than templated into mkproj because the fixtures above are
# shared with tests that must NOT declare one: the undeclared case is the
# default every consumer is in, and it is the one with the safety property.
declare_restore() {
  local proj="$1" cmd="$2" f="$proj/bin/.devbin/config.yaml"
  # The `commands:` parent only when it is not already there. Appending a
  # second one would give the flattener two roots for one key, and the first
  # draft of this helper omitted it entirely -- so the block landed at two
  # spaces under nothing, read as absent, and three tests reported that devbin
  # ignores a declared restore. It does not; the fixture never declared one.
  grep -qE '^commands:' "$f" || printf 'commands:\n' >>"$f"
  {
    printf '  fullcycle:\n'
    printf '    restore: %s\n' "$cmd"
  } >>"$f"
}

# devprofile_project -- one consumer's shape: a watched PATH symlink into
# release/, and a build that only ever populates debug/.
devprofile_project() {
  local proj="$1"
  mkdir -p "$proj/crate/target/debug/.fingerprint" "$proj/crate/target/release" \
           "$BATS_TEST_TMPDIR/pathbin3"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$BATS_TEST_TMPDIR/pathbin3/toolish"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug"
: >"$PWD/crate/target/debug/toolish"
chmod +x "$PWD/crate/target/debug/toolish"
exit 0' >/dev/null
  passing_test_cmd "$proj"
}

@test "a dev-profile cycle RESTORES what it darkened and finishes green" {
  local proj cargodir; proj="$(rustproj)"
  devprofile_project "$proj"
  declare_restore "$proj" "cargo build --release"
  cargodir="$(cargo_stub "$proj" restores)"

  PATH="$cargodir:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "RESTORING"
  # The point of the whole issue: it no longer reports damage it could have undone.
  refute_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  refute_output_contains "NO RESTORE COMMAND DECLARED"
  [ "$status" -eq 0 ] || fail "restored cycle still went red:
$output"
}

@test "a restore that does NOT restore is still reported and still RED" {
  # The control, and the load-bearing one. Without it the test above passes for
  # a cycle that never checks anything after restoring -- which is how this verb
  # got into trouble the first time.
  local proj cargodir; proj="$(rustproj)"
  devprofile_project "$proj"
  declare_restore "$proj" "cargo build --release"
  cargodir="$(cargo_stub "$proj" useless)"

  PATH="$cargodir:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "RESTORING"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  [ "$status" -ne 0 ] || fail "a cycle that restored NOTHING finished green:
$output"
}

# ---- the restore after a failed TEST (issue 0070) ---------------------------
#
# The restore used to be gated on the whole cycle's rc, so a test failure after
# a passing build left the toolchain dark and said nothing about the restore it
# skipped -- in exactly the projects that declared one. A build passing since the
# clean is what makes a restore meaningful; the test's verdict is a different
# question, and stays the run's verdict.

failing_test_cmd() {
  create_test_command "$1" test '#!/usr/bin/env bash
printf "test: deliberately failing\n"
exit 101' >/dev/null
}

@test "a TEST failure after a passing build still runs the declared restore (0070)" {
  local proj cargodir; proj="$(rustproj)"
  devprofile_project "$proj"
  failing_test_cmd "$proj"
  declare_restore "$proj" "cargo build --release"
  cargodir="$(cargo_stub "$proj" restores)"

  PATH="$cargodir:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "STOPPING: test all failed"
  assert_output_contains "RESTORING"
  refute_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  # The restore put the toolchain back; it did not turn a failed test green.
  assert_output_contains "FULLCYCLE FINISHED -- rc=101"
}

@test "a restore that fails after a failed test keeps the TEST's rc as the verdict (0070)" {
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  failing_test_cmd "$proj"
  mkdir -p "$BATS_TEST_TMPDIR/probebin"
  printf '#!/usr/bin/env bash\nexit 7\n' >"$BATS_TEST_TMPDIR/probebin/restore-probe"
  chmod +x "$BATS_TEST_TMPDIR/probebin/restore-probe"
  declare_restore "$proj" "restore-probe"

  PATH="$BATS_TEST_TMPDIR/probebin:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "RESTORING"
  assert_output_contains "rc=7"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  assert_output_contains "FULLCYCLE FINISHED -- rc=101"
}

@test "with no restore declared, a failed test's cycle SAYS the restore could not run (0070)" {
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  failing_test_cmd "$proj"

  PATH="$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "NO RESTORE COMMAND DECLARED"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
}

@test "a FAILED build never runs the declared restore -- no build has passed to restore after (0070)" {
  # The other side of moving the gate off rc. With no passing build there is
  # nothing a restore could be putting back, and a release build run over a tree
  # whose build just failed is the unsafe direction; the loop's own remedy (0071)
  # is the one thing the operator should read.
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
echo "build: deliberately failing"
exit 3' >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/probebin"
  printf '#!/usr/bin/env bash\n: >"%s/restore-ran"\nexit 0\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/probebin/restore-probe"
  chmod +x "$BATS_TEST_TMPDIR/probebin/restore-probe"
  declare_restore "$proj" "restore-probe"

  PATH="$BATS_TEST_TMPDIR/probebin:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "STOPPING: build all failed"
  refute_output_contains "RESTORING"
  [ ! -e "$BATS_TEST_TMPDIR/restore-ran" ] || fail "the restore RAN after a failed build"
}

# ============================================================================
# devbin DOES NOT PERFORM A RELEASE BUILD IT CANNOT KNOW IS SAFE
#
# The restore phase shipped for ONE DAY doing `cargo build --release` at the
# project root, and the argument for it survived review: `build all` is what
# just failed to produce these artefacts, and fullcycle is already rust-
# specific. Both halves are true; the premise under them is not.
#
# Intent guards its release path because several consumers invoke the artefact
# and a build from a dirty tree poisons it for all of them. Vendored in, that
# line was a new unguarded entrance, and Intent's shared-artefact guard named it
# by file and line on the first commit that carried it. Other projects took the
# same bytes and have no such guard -- which is not the same as having no
# exposure.
#
# `build release` is not the portable spelling either: at Intent that arm is
# INTERACTIVE and pushes, so guessing a verb by name would turn a restore into
# a publish.
# ============================================================================

@test "an UNDECLARED restore does not run cargo, and says why" {
  # THE FAIL-CLOSED DIRECTION. A cargo that would have restored everything sits
  # right there on PATH; the cycle must not reach for it.
  local proj cargodir; proj="$(rustproj)"
  devprofile_project "$proj"
  cargodir="$(cargo_stub "$proj" restores)"

  PATH="$cargodir:$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_output_contains "NO RESTORE COMMAND DECLARED"
  assert_output_contains "commands.fullcycle.restore"
  # It still REPORTS the damage and still goes red -- the state 0050 found,
  # now with the reason and the remedy attached instead of silence.
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  [ "$status" -ne 0 ] || fail "an unrestored cycle finished green:
$output"
}

# cargo_cmd_lines -- from stdin, each line that runs cargo: `cargo`, bare,
# quoted or escaped, in a command position -- at the start of a line or after
# a separator, `$(`, a backtick or a brace -- behind any number of NAME=value
# environment prefixes and of the words that put a command in that position:
# if, then, elif, else, do, while, until, !, {, time, env, command, exec,
# nohup, nice and xargs (issue 0165: the pattern missed the prefixed form
# lib/helpers writes, and these). Comment lines, and lines
# whose command is printf or echo, are dropped first. A prefix value is a
# quoted string or unquoted text without quotes, so an assignment whose
# quoted value mentions cargo is not a command -- unless a separator comes
# before cargo inside the quotes, as in "run (cargo build) first", which is
# read as one: a false red, which fails safe. NOT SEEN: cargo reached through
# a variable, through a printf piped into a shell, or behind an option to a
# wrapper word (nice -n 10 cargo). Numbered as grep -n numbers them. A grep
# that fails, rather than matching nothing, fails the function: an error read
# as no hits is exactly the green this pin exists to refuse.
cargo_cmd_lines() {
  local s w
  w="[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|'[^']*'|[^[:space:]\"']*)|if|then|elif|else|do|while|until|!|[{]|time|env|command|exec|nohup|nice|xargs"
  grep -nvE '^[[:space:]]*#' |
    grep -vE '^[0-9]+:[[:space:]]*(printf|echo)[[:space:]]' |
    grep -E "^[0-9]+:(.*([;&|({\`]|&&))?[[:space:]]*(($w)[[:space:]]+)*[\\\\\"']?cargo[\"']?[[:space:]]"
  for s in "${PIPESTATUS[@]}"; do
    [ "$s" -le 1 ] || return 2
  done
  return 0
}

@test "lib/cmd/fullcycle runs no cargo command outside a comment, in any command position, so the cycle builds and tests only through its build and test commands (0165)" {
  # STRUCTURAL, and structural on purpose: a behavioural test passes just as
  # well against a devbin that reaches for cargo somewhere this suite's
  # fixtures never reach. What Intent's guard censuses is the FILE.
  #
  # THE FIRST DRAFT MATCHED THE WORDS AND NOT THE INVOCATION, and reported two
  # hits: `this REMOVES the cargo build trees` and `%d cargo build tree(s)
  # examined`, both inside printf format strings. An assertion so wide it
  # forbids the file from DESCRIBING what it must not do is the third instance
  # of that shape on this project's record.
  #
  # IT SAYS WHAT IT HOLDS (issue 0165). It was titled "the shipped fullcycle
  # contains NO cargo invocation", read this one file, and the cycle does run
  # cargo: lib/helpers asks `cargo metadata` where a crate builds, which the
  # arm below holds is all it asks, and a build or test command the cycle runs
  # may itself be cargo, devbin's shipped `cargo test` included. And it missed
  # a command behind an environment prefix, the very form lib/helpers writes.
  # What cargo_cmd_lines still does not see is stated beside it.
  #
  # AND IT DOES NOT CATCH INDIRECTION -- MEASURED, NOT SUPPOSED. Driven against
  # `restore_cmd="cargo build --release"`, this test stays GREEN: an assignment
  # is not a command position, and the invocation only happens later through
  # `$restore_cmd`. The two behavioural tests either side of it went red on
  # that same arm, which is the division of labour: this one holds the FORM
  # Intent's census reads, and they hold the BEHAVIOUR. Neither is sufficient
  # alone and this comment exists so nobody deletes one believing the other
  # covers it.
  local hits planted
  hits="$(cargo_cmd_lines <"$DEVBIN_HOME/lib/cmd/fullcycle")" || fail "the matcher failed over lib/cmd/fullcycle"
  [ -z "$hits" ] || fail "lib/cmd/fullcycle invokes cargo directly:
$hits"

  # NON-VACUITY: the same matcher must FIND each form when it is there, or this
  # test is green over a grep that matches nothing at all -- and must pass
  # over the lines that only mention cargo. The commands come first, so the
  # lines it must name are the commands' own.
  local i want=""
  local -a commands=('      ( cd "$PROJECT_ROOT" && cargo build --release ) || prc=$?'
    '      CARGO_TERM_COLOR=never cargo build --release || prc=$?'
    '      x=1 && FOO="a b" BAR=c cargo test || prc=$?'
    '      if cargo build --release; then :; fi'
    '      ! cargo build --release || return 1'
    '      env CARGO_TERM_COLOR=never cargo build --release'
    '      out="$(echo x)"; cargo build'
    '      { "cargo" build; } && \cargo test')
  local -a mentions=('      what="the cargo config found here"'
    '      printf "%d cargo build tree(s) examined\n" "$n"')
  [ "${#commands[@]}" -gt 0 ] || fail "no command planted -- the control would compare nothing"
  planted="$(printf '%s\n' "${commands[@]}" "${mentions[@]}" | cargo_cmd_lines)" || fail "the matcher failed over the planted lines"
  for ((i = 1; i <= ${#commands[@]}; i++)); do want+="$i "; done
  [ "$(printf '%s\n' "$planted" | cut -d: -f1 | tr '\n' ' ')" = "$want" ] ||
    fail "the matcher does not find exactly the planted commands: $planted"
}

@test "the only cargo command lib/helpers runs is metadata, offline and without deps (0165)" {
  # The cycle's own cargo is lib/helpers' question of where a crate builds; a
  # build or test there would be the cycle running cargo behind the project's
  # back. Each grep's no-match is told from its failure, as cargo_cmd_lines
  # tells them.
  local hits other planted
  hits="$(cargo_cmd_lines <"$DEVBIN_HOME/lib/helpers")" || fail "the matcher failed over lib/helpers"
  [ -n "$hits" ] || fail "no cargo command found in lib/helpers: the matcher reads nothing, or the metadata query moved"
  other="$(printf '%s\n' "$hits" | grep -vE 'cargo metadata --offline --no-deps( |$)')" || [ "$?" -eq 1 ] ||
    fail "grep failed reading lib/helpers' cargo commands"
  [ -z "$other" ] || fail "lib/helpers runs cargo other than metadata --offline --no-deps:
$other"
  # A planted build, prefixed as lib/helpers writes its commands, is found and
  # is not metadata.
  planted="$(printf '%s\n' '  cd -- "$d" && CARGO_TERM_COLOR=never cargo build --release' | cargo_cmd_lines)" ||
    fail "the matcher failed over the planted line"
  other="$(printf '%s\n' "$planted" | grep -vE 'cargo metadata --offline --no-deps( |$)')" || [ "$?" -eq 1 ] ||
    fail "grep failed reading the planted line"
  [ -n "$other" ] || fail "a planted cargo build in lib/helpers' form is not found as other than metadata: $planted"
}

@test "a declared restore is run VERBATIM, not interpreted" {
  # It is a project command line, word-split unquoted and never eval'd -- the
  # same rule a config `run:` gets, for the same reason.
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  declare_restore "$proj" "restore-probe one two"
  mkdir -p "$BATS_TEST_TMPDIR/probebin"
  printf '#!/usr/bin/env bash\nprintf "PROBE-GOT: %%s\\n" "$*"\nexit 0\n' \
    >"$BATS_TEST_TMPDIR/probebin/restore-probe"
  chmod +x "$BATS_TEST_TMPDIR/probebin/restore-probe"

  PATH="$BATS_TEST_TMPDIR/probebin:$BATS_TEST_TMPDIR/pathbin3:$PATH" \
    run devbin_run "$proj" fullcycle --force

  assert_output_contains "PROBE-GOT: one two"
}

@test "a dependency's build tree is OUT of the artefact population" {
  # A crate census: one Elixir consumer carries five Cargo.toml files
  # and exactly one is its own -- the other four are Elixir NIF crates under
  # deps/, built through mix by Rustler. `build all` never builds them, so
  # populated-debug-empty-release under deps/ says NOTHING about whether this
  # cycle restored anything. Somebody running a bare `cargo build` in a dep for
  # their own reasons would produce the signature with no cycle involved.
  #
  # A check that cries wolf on four trees out of five gets its output ignored,
  # which is the same end state as the vacuity it replaces reached from the
  # other direction.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"

  # A dependency carrying the exact failing signature: debug populated,
  # release empty. The project's own tree is fine.
  mkdir -p "$proj/deps/lumis/native/lumis_nif/target/debug" \
           "$proj/deps/lumis/native/lumis_nif/target/release"
  printf '#!/bin/sh\nexit 0\n' > "$proj/deps/lumis/native/lumis_nif/target/debug/nif"
  chmod +x "$proj/deps/lumis/native/lumis_nif/target/debug/nif"

  run devbin_run "$proj" fullcycle --force

  refute_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  # Exactly one tree in the population -- the project's own. Asserted on the
  # COUNT rather than on the absence of the string "lumis_nif", because `clean`
  # legitimately names that tree in its own output as one it ignored, and a
  # refutation broad enough to catch the artefact check also catches clean
  # reporting honestly. Scope the assertion to the instrument being tested.
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  [ "$status" -eq 0 ] || fail "a dependency's build tree failed the cycle:
$output"
}

@test "the artefact check names how many trees it examined, always" {
  # "compared one tree and it was fine" and "found no tree to compare" must not
  # render identically. That collapse IS issue 0048.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"

  run devbin_run "$proj" fullcycle --force

  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
}

# A WALK WITH A HOLE IN IT IS NOT AN ARTEFACT CHECK (issue 0139).
# cargo_target_dirs sent find's errors to /dev/null and the check read it
# through a process substitution, so a tree beneath a directory find could not
# read was never examined, and the cycle went green over the rest. The build
# below leaves such a directory behind after the clean has run, so the check's
# walk is the one that meets it.
@test "a build tree or profile the artefact check cannot list is named and fails the cycle, never read as empty (0139)" {
  # A mode-000 target/ read as a tree with no
  # binaries, so the cycle said INCONCLUSIVE at rc 0, and an unlistable release/
  # beside a readable debug/ was reported as release artefacts lost.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  # THE CONTROL: the same cycle, with everything readable, is green.
  run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  local what word
  for what in target:search target/release:list; do
    word="${what#*:}"
    what="${what%%:*}"
    create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
chmod +x "$PWD/crate/target/debug/demo"
chmod 000 "$PWD/crate/'"$what"'"
exit 0' >/dev/null
    run devbin_run "$proj" fullcycle --force
    [ ! -r "$proj/crate/$what" ] || readable=1
    chmod 755 "$proj/crate/$what" || fail "the build left no $what behind: $output"
    [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the unlistable case was NOT checked"
    assert_failure
    assert_output_contains "cannot $word $proj/crate/$what"
    assert_output_contains "ARTEFACT CHECK INCOMPLETE"
    refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
    refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
    # The tree is named as not examined and is not counted among those that
    # were.
    refute_output_contains "artefact check: 1 cargo build tree(s) examined"
    assert_output_contains "NO cargo build tree could be examined"
    assert_output_contains "so that tree was not examined"
    # Only the cause that holds is said: the walk here read everything.
    refute_output_contains "may not have been examined"
  done
}

@test "a build tree the check can search but not list still has its profiles compared (0139)" {
  # The tree is only passed through, to debug/ and
  # release/ by name, so it needs search alone. Refused for want of read, a
  # target/ at 0111 whose profiles could be read went INCOMPLETE at rc 1.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/debug/demo" "$PWD/crate/target/release/demo"
chmod 111 "$PWD/crate/target"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$proj/crate/target" ] || readable=1
  chmod 755 "$proj/crate/target" || fail "the build left no target/ behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-0111 directory: the case was NOT checked"
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "cannot search $proj/crate/target"
  refute_output_contains "cannot list $proj/crate/target"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
  # And compared, not passed over: both profiles hold a binary, so a
  # comparison ends at no verdict line at all.
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "a build tree named target that is a link is examined as the directory it names, once, and one naming nothing is named as absent (0139)" {
  # Under find's
  # default -P a link is never -type d, so a target/ reached through one was
  # never listed, and a debug/ without release/ behind it read as "NO cargo
  # build tree" and INCONCLUSIVE at rc 0.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/elsewhere/debug" "$PWD/crate/elsewhere/release"
ln -sfn elsewhere "$PWD/crate/target"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/elsewhere/debug/demo"
chmod +x "$PWD/crate/elsewhere/debug/demo"
mkdir -p "$PWD/crate3" "$PWD/other" "$PWD/other2"
ln -sfn ../crate/elsewhere "$PWD/crate3/target"
ln -sfn nowhere "$PWD/other/target"
: >"$PWD/afile"
ln -sfn ../afile "$PWD/other2/target"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "NO cargo build tree found"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  # A second link to the same directory is the same tree, examined and lost
  # once (it was counted, and lost, twice).
  [ "$(printf '%s\n' "$output" | grep -c 'debug/ has binaries, release/ has none')" -eq 1 ] ||
    fail "one tree was reported lost more than once: $output"
  # And a link named target that names nothing is named as absent, not dropped
  # unsaid, and is no hole in the walk.
  assert_output_contains "$proj/other/target does not exist"
  assert_output_contains "1 more not examined, each named above"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
  # And a link named target that names a file is no tree, and nothing is said
  # of it.
  refute_output_contains "$proj/other2/target"
}

@test "a build tree that does not exist is named, passed over, and makes no hole in the walk (0139)" {
  # A CARGO_TARGET_DIR the build never made is
  # named as absent, not examined, and not a hole: the directory that would
  # hold it can be searched, so the tree is gone, not out of reach.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  # Inside the project: one outside it is refused before the cycle since 0148,
  # and the check never reads it.
  CARGO_TARGET_DIR="$proj/never-built" run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "$proj/never-built does not exist"
  assert_output_contains "NO cargo build tree could be examined"
  assert_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  refute_output_contains "cannot reach"
  refute_output_contains "cannot search"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
  # AND ONE WHOSE PARENT WAS NEVER MADE IS GONE TOO: nothing on the way cannot
  # be searched, and it read as out of reach.
  CARGO_TARGET_DIR="$proj/never-made/t" run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "$proj/never-made/t does not exist"
  refute_output_contains "cannot reach"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
  # And one whose path runs through a file: no directory can hold it, and since
  # 0148 it is refused before the cycle, as a path that cannot be placed,
  # rather than read after it as gone.
  CARGO_TARGET_DIR="$proj/crate/Cargo.toml/t" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "CARGO_TARGET_DIR=$proj/crate/Cargo.toml/t cannot be placed: $proj/crate/Cargo.toml cannot be entered"
  refute_output_contains "--- phase:"
  # And one through a link naming a file with a trailing slash, which asks for
  # a directory: it was named as a link that cannot be followed. Refused
  # before the cycle too.
  ln -s crate/Cargo.toml/ "$proj/tlink"
  CARGO_TARGET_DIR="$proj/tlink" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "CARGO_TARGET_DIR=$proj/tlink cannot be placed: $proj/tlink cannot be entered"
  refute_output_contains "--- phase:"
}

@test "a build tree reached through a chain of links into a directory it cannot search is out of reach, not gone (0139)" {
  # The check followed one link to find
  # the directory holding a tree, so crate/target -> t1 and crate/t1 ->
  # .../locked/t, with locked/ at mode 000, read as a tree that does not exist,
  # INCONCLUSIVE at rc 0 over a debug/ with no release/. The path is resolved a
  # link at a time. locked/ is outside the project, so the walk for build trees
  # never meets it and the only hole is the tree's own.
  local proj readable=0 outside="$BATS_TEST_TMPDIR/outside"; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "'"$outside"'/locked/t/debug" "'"$outside"'/locked/t/release"
printf "#!/bin/sh\nexit 0\n" > "'"$outside"'/locked/t/debug/demo"
chmod +x "'"$outside"'/locked/t/debug/demo"
ln -sfn t1 "$PWD/crate/target"
ln -sfn "'"$outside"'/locked/t" "$PWD/crate/t1"
chmod 000 "'"$outside"'/locked"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$outside/locked" ] || readable=1
  chmod 755 "$outside/locked" || fail "the build left no locked/ behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot reach $proj/crate/target"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  refute_output_contains "does not exist"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "a build tree behind a link holding a newline, or a chain longer than the kernel follows, is named for what it is and fails the cycle, never read as gone (0139)" {
  # A link naming "$O/lk<LF>x/t", with lk<LF>x/ at mode 000, read as a tree that
  # does not exist, INCONCLUSIVE at rc 0 over a debug/ with no release/, since
  # the walk split the content at the newline; it is out of reach. A link loop
  # has the arm below.
  local proj readable=0 locked="$BATS_TEST_TMPDIR/outside/lk"$'\n'"x"; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$locked/t/debug" "$locked/t/release"
  : >"$proj/crate/Cargo.toml"
  printf '#!/bin/sh\nexit 0\n' >"$locked/t/debug/demo"
  chmod +x "$locked/t/debug/demo"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
ln -sfn '"$(printf '%q' "$locked/t")"' "$PWD/crate/target"
chmod 000 '"$(printf '%q' "$locked")"'
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$locked" ] || readable=1
  chmod 755 "$locked" || fail "the build left no locked directory behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot reach $proj/crate/target"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  refute_output_contains "does not exist"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  # And a chain of 35 links to a tree that is there: the walk reaches it, and
  # the kernel, which follows 32 on macOS, does not, so the tree is behind a
  # link the kernel cannot follow, not out of reach.
  # Reached by the walk, as crate/target: a CARGO_TARGET_DIR through it is
  # refused before the cycle since 0148, as a path that cannot be placed.
  local chain="$BATS_TEST_TMPDIR/chain" prev=real k
  mkdir -p "$chain/real/t"
  for k in $(seq 1 35); do
    ln -s "$prev" "$chain/c$k"
    prev="c$k"
  done
  [ ! -e "$chain/c35/t" ] || skip "this kernel follows 35 links: the chain longer than the kernel follows was NOT checked"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
ln -sfn '"$(printf '%q' "$chain/c35/t")"' "$PWD/crate/target"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "cannot tell where $proj/crate/target leads"
  refute_output_contains "cannot reach"
  CARGO_TARGET_DIR="$chain/c35/t" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "CARGO_TARGET_DIR=$chain/c35/t cannot be placed:"
}

@test "a build tree behind a link in a loop is named as one behind a link that cannot be followed, never as out of reach, fails the cycle, and the summary lists that cause (0139, 0177)" {
  # A link loop was named "a directory on
  # the way cannot be searched", which nothing was: it is a link that cannot be
  # followed. An arm of its own, so that neither the permission nor the
  # kernel's link limit the arm above rests on keeps it from running. The
  # summary lists this cause among the rest
  # (issue 0177): it had no line there, and the tree read as one that could not
  # be reached or searched.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
ln -sfn loop2 "$PWD/crate/target"
ln -sfn target "$PWD/crate/loop2"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "cannot tell where $proj/crate/target leads"
  refute_output_contains "cannot reach"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  assert_output_line "or it lay behind a link that could not be followed exactly,"
}

@test "a build tree out of reach is named and fails the cycle, never read as absent or passed over (0139)" {
  # A target link into
  # a directory at mode 000 was dropped unsaid (NO cargo build tree found), and
  # a CARGO_TARGET_DIR beneath one read as "does not exist" -- INCONCLUSIVE at
  # rc 0 both times, over a debug/ with no release/. `[ -e ]` fails for EACCES
  # as for ENOENT, so a tree is gone only when a directory that can be searched
  # says a name on its path is not there.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/locked/t/debug" "$PWD/locked/t/release"
printf "#!/bin/sh\nexit 0\n" > "$PWD/locked/t/debug/demo"
chmod +x "$PWD/locked/t/debug/demo"
ln -sfn ../locked/t "$PWD/crate/target"
chmod 000 "$PWD/locked"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$proj/locked" ] || readable=1
  chmod 755 "$proj/locked" || fail "the build left no locked/ behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot reach $proj/crate/target"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  refute_output_contains "NO cargo build tree found"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  # AND A CARGO_TARGET_DIR BENEATH A DIRECTORY AT MODE 000 is out of reach, not
  # absent.
  CARGO_TARGET_DIR="$proj/locked/t" run devbin_run "$proj" fullcycle --force
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "cannot reach $proj/locked/t"
  refute_output_contains "does not exist"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "one tree examined, one out of reach and a hole in the walk: each is said, and the cycle fails (0139, 0177)" {
  # A tree found and not examined is counted
  # apart, and INCOMPLETE says each of its causes.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release" "$PWD/crate2/target" "$PWD/locked"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/debug/demo" "$PWD/crate/target/release/demo"
chmod 000 "$PWD/crate2/target" "$PWD/locked"
exit 0' >/dev/null
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$proj/locked" ] || readable=1
  chmod 755 "$proj/crate2/target" "$proj/locked" || fail "the build left no directories behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  assert_output_contains "1 more not examined, each named above"
  assert_output_contains "cannot search $proj/crate2/target"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  assert_output_contains "may not have been examined"
  assert_output_contains "so that tree was not examined"
  assert_output_line "A build tree could not be reached or searched,"
  assert_find_denied "$proj/locked"
}

@test "an artefact check whose walk cannot read everything fails the cycle (0139, 0145)" {
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  # THE CONTROL: the same cycle, with everything readable, is green.
  run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release" "$PWD/locked"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/debug/demo" "$PWD/crate/target/release/demo"
chmod 000 "$PWD/locked"
exit 0' >/dev/null
  # Tagged as cargo tags its trees, so the clean removes it; the stub build
  # writes the tag too (0148), and this keeps the arm's own premise
  # stated where it runs.
  cargo_tag "$proj/crate/target"

  run devbin_run "$proj" fullcycle --force

  [ ! -r "$proj/locked" ] || readable=1
  chmod 755 "$proj/locked" || fail "the build left no directory behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  assert_failure
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  assert_output_contains "may not have been examined"
  # Only the cause that holds is said: every tree found was examined here.
  refute_output_contains "so that tree was not examined"
  # find's own error names the directory, in any form find prints it.
  assert_find_denied "$proj/locked"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and the check examined the trees it saw, green.
  create_test_command "$proj" build '#!/usr/bin/env bash
mkdir -p "$PWD/crate/target/debug" "$PWD/crate/target/release" "$PWD/locked"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/debug/demo"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/debug/demo" "$PWD/crate/target/release/demo"
chmod 755 "$PWD/locked"
chmod 644 "$PWD/locked"
exit 0' >/dev/null
  cargo_tag "$proj/crate/target"
  run devbin_run "$proj" fullcycle --force
  local searchable=0
  [ ! -x "$proj/locked" ] || searchable=1
  chmod 755 "$proj/locked"
  [ "$searchable" = 0 ] || skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  assert_failure
  assert_output_contains "cannot search $proj/locked -- nothing beneath it was looked at"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  assert_output_contains "may not have been examined"
}

# A PATH DIRECTORY THE WATCH CANNOT LIST (issue 0139). One that PATH can search
# and find cannot read, mode 0111, holds a live link into the tree: PATH
# resolves the link, and find, with its error sent to /dev/null, listed nothing,
# so the cycle said it watched NOTHING and went green with the link dark.
@test "a PATH directory the watch cannot list fails the cycle, and the watch names what it read (0139)" {
  local proj bin="$BATS_TEST_TMPDIR/hidebin"; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug/.fingerprint" "$proj/crate/target/release" "$bin"
  : >"$proj/crate/Cargo.toml"
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  ln -s "$proj/crate/target/release/toolish" "$bin/toolish"
  # A build that puts release/ back with another binary, so the artefact check
  # passes and only the watch can see that toolish went dark.
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$PWD/crate/target/debug/.fingerprint" "$PWD/crate/target/release"
printf "#!/bin/sh\nexit 0\n" > "$PWD/crate/target/release/demo"
chmod +x "$PWD/crate/target/release/demo"
exit 0' >/dev/null
  passing_test_cmd "$proj"
  # THE CONTROL: readable, the watch sees the link and names it dark. And a
  # PATH directory nobody can SEARCH resolves nothing, so it holds no live link
  # and leaves the watch complete: it is not a hole.
  mkdir -p "$BATS_TEST_TMPDIR/deadbin"
  chmod 000 "$BATS_TEST_TMPDIR/deadbin"
  PATH="$bin:$BATS_TEST_TMPDIR/deadbin:$PATH" run devbin_run "$proj" fullcycle --force
  chmod 755 "$BATS_TEST_TMPDIR/deadbin"
  assert_failure
  assert_output_contains "watching: $(fixture_links "$proj" "$bin") PATH symlink"
  assert_output_contains "DARKENED BINARIES IT DID NOT RESTORE"
  refute_output_contains "PATH WATCH INCOMPLETE"
  refute_output_contains "could not be read"
  # The link live again, in a directory PATH can search and nobody can list.
  : >"$proj/crate/target/release/toolish"
  chmod +x "$proj/crate/target/release/toolish"
  chmod 111 "$bin"
  if [ -r "$bin" ]; then
    chmod 755 "$bin"
    skip "running with permissions that list a mode-0111 directory: the unlistable case was NOT checked"
  fi
  [ -e "$bin/toolish" ] || {
    chmod 755 "$bin"
    fail "the link does not resolve through a mode-0111 directory, so the fixture proves nothing"
  }

  PATH="$bin:$PATH" run devbin_run "$proj" fullcycle --force

  chmod 755 "$bin"
  assert_failure
  assert_output_contains "PATH WATCH INCOMPLETE"
  assert_output_contains "in the PATH directories it could read"
  assert_output_contains "a link in it is NOT watched"
  assert_output_contains "a link already dangling there is not listed"
  refute_output_contains "watching: NOTHING"
  # find's own error names the directory. Not the bare path: the clean phase
  # names $bin/toolish when it lists what PATH resolves into the tree.
  assert_find_denied "$bin"
}

# ============================================================================
# 0083: THE TEST PHASE IS `test all`
#
# The cycle ran `test rust` and nothing else, so a project's other declared
# test options never ran in a full cycle, and nothing a project declared could
# change that without editing this vendored file. Intent's toolchain arms --
# tests that need a real toolchain and run by a second declared option -- are
# the case that found it. The phase is now `test all`: one definition of the
# tests for this cycle and for `all`, with `in_all: false` the one override for
# both.
#
# MOST OF THESE FIXTURES GIVE `test` NO HANDLER, and declare their test
# options in config. A handler owns every option, and a handler with none
# declared receives `all` itself, so run_all -- which the phase now reaches --
# would never run. One arm gives `test` a handler on purpose: that is the one
# shape `in_all: false` cannot reach.
# ============================================================================

# fc_recorder <name> <rc> -- an executable called <name> in fcbin/ that appends
# "<name> <args> [<cwd>]" to the run log and exits <rc>; prints its path. Every
# phase in these fixtures writes to the one log, so ORDER is read from the log
# rather than from output, where run_all's own summary repeats option names.
fc_recorder() {
  local dir="$BATS_TEST_TMPDIR/fcbin"
  mkdir -p "$dir"
  cat >"$dir/$1" <<EOF
#!/usr/bin/env bash
printf '%s %s [%s]\n' "$1" "\$*" "\$PWD" >>"$BATS_TEST_TMPDIR/ran.log"
exit $2
EOF
  chmod +x "$dir/$1"
  printf '%s' "$dir/$1"
}

# fc_build_recorder <proj> -- a build handler that passes and logs itself.
fc_build_recorder() {
  create_test_command "$1" build "#!/usr/bin/env bash
case \"\${1:-}\" in --help) exit 0 ;; esac
printf 'build %s\n' \"\$*\" >>\"$BATS_TEST_TMPDIR/ran.log\"
exit 0" >/dev/null
}

# rustproj_testopts <options-yaml> -- a rust project that can rebuild, whose
# `test` declares <options-yaml> beside the catalogue's own `rust`.
rustproj_testopts() {
  local proj
  proj="$(mkproj rustdemo <<EOF
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  test:
    options:
$1
EOF
)"
  fc_build_recorder "$proj"
  echo "$proj"
}

# fc_ran <name> -- the log lines <name> wrote, one per run; empty when none.
#
# `|| true` IS WIDER THAN IT LOOKS. grep exits 1 on no match, which is the
# answer an absence check wants, and 2 when the log was never written, which
# reads the same way from inside `$(...)`. So every arm asserting an absence
# also asserts, in the same run, that something else was logged.
fc_ran() {
  grep "^$1 " "$BATS_TEST_TMPDIR/ran.log" || true
}

@test "the test phase is test all, so a second declared test option runs after the build (0083)" {
  local proj order
  proj="$(rustproj_testopts "      toolchain:
        summary: needs a real toolchain
        run: $(fc_recorder toolchain 0)")"
  fc_recorder cargo 0 >/dev/null

  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_success
  assert_output_contains "phase: test all"
  assert_output_contains "all test options passed"
  # THE BUILD FIRST, THEN BOTH OPTIONS, EACH ONCE. `test rust` alone never
  # reached the second. The two options' own order is `all`'s declared order,
  # which is run_all's to hold, so either is accepted here.
  order="$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/ran.log" | tr '\n' ' ')"
  [ "$order" = "build cargo toolchain " ] || [ "$order" = "build toolchain cargo " ] ||
    fail "expected the build, then cargo and toolchain once each; the log reads: $order
$output"
}

@test "a test option marked in_all: false is kept out of the cycle and reported as skipped (0083)" {
  local proj
  proj="$(rustproj_testopts "      toolchain:
        summary: needs a real toolchain
        run: $(fc_recorder toolchain 0)
      slow:
        summary: kept out of every all
        in_all: false
        run: $(fc_recorder slow 0)")"
  fc_recorder cargo 0 >/dev/null

  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" fullcycle --force

  # THE LOAD-BEARING HALF FIRST: kept out of `all` is kept out of the cycle,
  # which is the one override this shape offers instead of a second list of
  # tests.
  [ -z "$(fc_ran slow)" ] || fail "an option marked in_all: false ran in the cycle:
$(fc_ran slow)
$output"
  [ -n "$(fc_ran toolchain)" ] || fail "the option beside it did not run -- the skip proves nothing:
$output"
  assert_output_contains "skipped (in_all: false): slow"
  assert_success
}

@test "a project declaring only rust runs exactly what test rust runs (0083)" {
  local proj direct cycle
  proj="$(rustproj)"
  fc_build_recorder "$proj"
  fc_recorder cargo 0 >/dev/null

  # WHAT `test rust` RUNS, read through the same recorder -- its arguments and
  # the directory it ran in -- so the comparison is to the command, not to a
  # string this test wrote.
  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" test rust
  assert_success
  direct="$(fc_ran cargo)"
  [ -n "$direct" ] || fail "test rust ran no cargo -- the comparison below would be vacuous:
$output"
  rm -f "$BATS_TEST_TMPDIR/ran.log"

  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_success
  cycle="$(fc_ran cargo)"
  [ "$cycle" = "$direct" ] || fail "the cycle's test phase ran something other than test rust:
test rust: $direct
the cycle: $cycle"
}

@test "a failing second test option stops the cycle rc=1 naming it, with the build-passed line (0083)" {
  # THE OPTION EXITS 3, NOT 1, so the rc=1 read below can only be `all`'s own
  # verdict and never the option's code passed through. The rc comment above
  # _fullcycle_phases and the 0.1.2 note both say a cycle whose tests fail
  # finishes rc=1, and until this arm nothing held it: with run_all's failure rc
  # set to 7, every arm stayed green.
  local proj
  proj="$(rustproj_testopts "      toolchain:
        summary: needs a real toolchain
        run: $(fc_recorder toolchain 3)")"
  fc_recorder cargo 0 >/dev/null

  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "FAILED: toolchain"
  assert_output_contains "STOPPING: test all failed"
  assert_output_contains "build all passed after the clean; the failure is in test all"
  refute_output_contains "HAVE NOT BEEN REBUILT"
  # Whole lines, so rc=10 cannot pass for rc=1.
  grep -qxE ' *phase: test all +[0-9hms]+  rc=1' <<<"$output" ||
    fail "the test phase did not finish rc=1, all's verdict for a failing option:
$output"
  grep -qxE ' *FULLCYCLE FINISHED -- rc=1' <<<"$output" ||
    fail "the cycle did not finish rc=1:
$output"
  # `all` DOES NOT STOP AT THE FIRST BREACH, AND THE ORDER IS WHAT SHOWS IT.
  # Config-declared options run before the catalogue's (lib/resolve's
  # command_option_candidates), so `toolchain` fails first and cargo runs
  # after it. With cargo first, its line would say nothing about the breach.
  local order
  order="$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/ran.log" | tr '\n' ' ')"
  [ "$order" = "build toolchain cargo " ] ||
    fail "expected the build, the failing toolchain, then cargo after it; the log reads: $order
$output"
}

@test "a cycle whose every test option is kept out of all is refused before anything is removed, as test all refuses it (0083, 0134)" {
  # THE OVERRIDE CAN EMPTY THE PHASE, AND AN EMPTY PHASE IS NOT A PASS. With
  # `rust`, the catalogue's only test option here, marked in_all: false, `test
  # all` refuses a verdict for having executed nothing. 0083 let the cycle
  # clean and build and then stop on that refusal; since 0134 the cycle asks
  # all_partition, run_all's own selection, first, and refuses before the
  # clean, in run_all's own sentence. Over a catalogue option, not a declared
  # one: arg_route answers `all` wherever there are options, whatever the tier.
  local proj
  proj="$(rustproj_testopts "      rust:
        in_all: false")"
  fc_recorder cargo 0 >/dev/null
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  PATH="$BATS_TEST_TMPDIR/fcbin:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "fullcycle: REFUSING -- nothing runs test in this project, so the cycle has no test phase. Nothing was removed."
  assert_output_line "test: every option it offers is excluded from all: rust"
  refute_output_contains "--- phase:"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree"
  [ -z "$(fc_ran build)" ] || fail "the build ran in a refused cycle:
$(fc_ran build)"
  [ -z "$(fc_ran cargo)" ] || fail "cargo ran although rust is kept out of all:
$(fc_ran cargo)"

  # The words are run_all's: test all refuses in the same sentence.
  run devbin_run "$proj" test all
  assert_failure
  assert_output_line "every option it offers is excluded from all: rust"
}

@test "a test handler that declares no options receives all from the cycle, as from test all (0083)" {
  # THE ONE SHAPE `in_all: false` CANNOT REACH. A handler that declares no
  # options owns its whole argument list, `all` included, so the cycle now
  # hands it `all` where it handed it `rust`, and the handler decides what that
  # runs. One consumer's `test` is this shape.
  local proj; proj="$(rustproj)"
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "TEST-HANDLER-GOT: %s\n" "$*"
exit 0' >/dev/null

  run devbin_run "$proj" fullcycle --force

  assert_success
  assert_output_contains "TEST-HANDLER-GOT: all"
  refute_output_contains "TEST-HANDLER-GOT: rust"
}

@test "a test run: line with no options is the test phase, run bare, and the cycle stops red on its own failure (0128, 0134)" {
  # THE COUNTERPART OF THE HANDLER ARM ABOVE. A line is
  # not a handler: devbin runs it with the words appended, and cargo reads a
  # word after `cargo test` as a test-name filter. So a `test` owned by
  # `commands.test.run` took `all` as a filter that matched nothing, ran no
  # test and passed, and the cycle finished rc=0 over a failing suite.
  # 0128 refused `test all` there, exit 1, and the
  # cycle stopped on the refusal, never running the suite. Since 0134 the
  # cycle never types `all` over a line: its test phase is `test`, the line
  # alone, so the suite runs and the cycle stops red on the suite's own
  # failure. The runner below behaves as cargo does, and logs each run.
  local proj; proj="$(rustproj)"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  test:
    run: scripts/filtered
YAML
  mkdir -p "$proj/scripts"
  cat >"$proj/scripts/filtered" <<'STUB'
#!/bin/sh
echo "filtered $*" >>ran.log
if [ $# -gt 0 ]; then
  echo "running 0 tests; 1 filtered out"
  exit 0
fi
echo "test broken ... FAILED"
exit 101
STUB
  chmod +x "$proj/scripts/filtered"

  run devbin_run "$proj" fullcycle --force

  assert_exit_code 101
  refute_output_contains "has no options to run"
  refute_output_contains "0 tests"
  assert_output_contains "test broken ... FAILED"
  assert_output_contains "STOPPING: test failed"
  grep -qE ' *phase: test +[^ ]+ +rc=101' <<<"$output" ||
    fail "the test phase did not stop on the suite's own failure:
$output"
  grep -qxE ' *FULLCYCLE FINISHED -- rc=101' <<<"$output" ||
    fail "the cycle did not finish rc=101:
$output"
  # The line ran once, bare: no `all`, and no other word, reached it.
  [ "$(cat "$proj/ran.log")" = "filtered " ] || fail "the test line was not run once and bare:
$(cat "$proj/ran.log" 2>/dev/null)"
}

@test "the no-build refusal reads its commands from the phase list, not from a copy of it (0083)" {
  # THE MECHANISM, NOT TODAY'S TEXT. The refusal arm pins what the list prints
  # today, and a literal sentence naming `clean rust` and `test all` prints the
  # same bytes -- the second copy this change removed, which went on naming
  # `test rust`. Pinned in the source for the reason the guard's own arm gives:
  # only the source shows the shape.
  local body
  body="$(awk '/if ! _fullcycle_can_rebuild/,/return 1/' "$DEVBIN_HOME/lib/cmd/fullcycle")"
  grep -q 'REFUSING' <<<"$body" ||
    fail "could not extract the refusal -- the assertion below would be vacuous"
  grep -q '< <(_fullcycle_phases)' <<<"$body" ||
    fail "the refusal no longer reads _fullcycle_phases:
$body"
}

@test "a declared restore's words are glob patterns matched at the project root (0082)" {
  # The same rule as every other declared command line, at the one site that is
  # neither an option nor a command: `commands.fullcycle.restore`.
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  : >"$proj/alpha.md"
  : >"$proj/beta.md"
  declare_restore "$proj" "restore-probe *.md"
  mkdir -p "$BATS_TEST_TMPDIR/probebin"
  printf '#!/usr/bin/env bash\nprintf "PROBE-GOT: %%s\\n" "$*"\nexit 0\n' \
    >"$BATS_TEST_TMPDIR/probebin/restore-probe"
  chmod +x "$BATS_TEST_TMPDIR/probebin/restore-probe"

  PATH="$BATS_TEST_TMPDIR/probebin:$BATS_TEST_TMPDIR/pathbin3:$PATH" \
    run devbin_run "$proj" fullcycle --force

  assert_output_contains "PROBE-GOT: alpha.md beta.md"
  refute_output_contains "PROBE-GOT: *.md"
}

@test "a restore with no words in it is refused naming the key, and the cycle goes red (0082)" {
  # Before this, `restore: "   "` expanded to nothing, which makes an EMPTY
  # COMMAND -- and an empty command exits 0. So the phase printed rc=0, the
  # cycle finished green, and nothing had been restored: the false green this
  # verb exists to avoid, reached through its own config.
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  declare_restore "$proj" '"   "'

  # The restore phase runs only when something on PATH resolves into the tree,
  # which is what devprofile_project sets up: without pathbin3 on PATH the
  # cycle has nothing to restore and never reaches the phase at all.
  PATH="$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "commands.fullcycle.restore holds no words"
  grep -qxE ' *phase: restore +[0-9hms]+  rc=1' <<<"$output" ||
    fail "the restore phase did not finish rc=1:
$output"
  refute_output_contains "NO RESTORE COMMAND DECLARED"
}

@test "a restore declared empty is refused rather than read as undeclared (0082)" {
  local proj; proj="$(rustproj)"
  devprofile_project "$proj"
  declare_restore "$proj" '""'

  # The restore phase runs only when something on PATH resolves into the tree,
  # which is what devprofile_project sets up: without pathbin3 on PATH the
  # cycle has nothing to restore and never reaches the phase at all.
  PATH="$BATS_TEST_TMPDIR/pathbin3:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "commands.fullcycle.restore holds no words"
  refute_output_contains "NO RESTORE COMMAND DECLARED"
}

# ============================================================================
# 0134: THE PHASES ARE WHAT THIS PROJECT RUNS, ASKED AND NEVER RUN
# ============================================================================

# rustproj_buildrun <proj-var-name> <script body> -- a rust project whose build
# is a lone commands.build.run line, scripts/build, with the body given. It
# records each run's arguments in build.log at the project root.
rustproj_buildrun() {
  local proj
  proj="$(mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    run: scripts/build
EOF
)"
  mkdir -p "$proj/scripts"
  {
    printf '#!/bin/sh\n'
    printf 'printf "build args=[%%s]\\n" "$*" >>build.log\n'
    printf '%s\n' "$1"
  } >"$proj/scripts/build"
  chmod +x "$proj/scripts/build"
  echo "$proj"
}

@test "--dry-run runs nothing behind build: a build run: line is never handed --help, and the preview names it bare (0134)" {
  # A DRY RUN THAT RAN THE BUILD. The rebuild probe ran `build --help` before
  # the dry-run branch, and a run: line takes --help as one more argument: a
  # script that ignores it built, under "DRY RUN -- nothing below is executed".
  local proj; proj="$(rustproj_buildrun 'exit 0')"

  run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "DRY RUN -- nothing below is executed."
  [ ! -e "$proj/build.log" ] || fail "the dry run ran the build line:
$(cat "$proj/build.log")"
  # The build phase is the line alone: `build all` is refused over it.
  assert_output_line "bin/devbin build"
  refute_output_contains "bin/devbin build all"

  # The control: the line is reachable and logs, so the absence is measured.
  run devbin_run "$proj" build
  assert_success
  [ -s "$proj/build.log" ] || fail "the bare build did not log -- the absence above proves nothing"
}

@test "a build whose tool refuses --help is a build, and the cycle runs it (0134)" {
  local proj; proj="$(rustproj_buildrun 'case "$1" in --help) echo "no such flag" >&2; exit 2 ;; esac
exit 0')"
  passing_test_cmd "$proj"

  run devbin_run "$proj" fullcycle --force

  refute_output_contains "REFUSING"
  assert_output_contains "--- phase: build ---"
  grep -qE ' *phase: build +[^ ]+ +rc=0' <<<"$output" ||
    fail "the build phase did not run and pass:
$output"
  grep -qx 'build args=\[\]' "$proj/build.log" ||
    fail "the build ran with arguments, or not at all:
$(cat "$proj/build.log" 2>/dev/null)"
}

@test "a lone build run: line is the build phase, run bare, and its failure's remedy names it (0134)" {
  # THE 0128 SEQUENCE. A lone commands.build.run
  # passed the probe; the cycle removed the trees, stopped at `build all`,
  # which has no options to run, and named that same command as the remedy.
  local proj; proj="$(rustproj_buildrun 'echo "build: deliberately failing"; exit 1')"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  assert_failure
  refute_output_contains "has no options to run"
  assert_output_contains "build: deliberately failing"
  assert_output_contains "STOPPING: build failed"
  assert_output_contains "THE BUILD TREES WERE ALREADY REMOVED"
  assert_output_line "Rebuild before doing anything else: bin/devbin build"
  refute_output_contains "bin/devbin build all"
  grep -qx 'build args=\[\]' "$proj/build.log" ||
    fail "the build line was handed arguments:
$(cat "$proj/build.log" 2>/dev/null)"
}

@test "a cycle whose test phase would run nothing is refused before anything is removed, in the dispatcher's words (0134)" {
  # IT REMOVED THE TREES, REBUILT, AND FAILED AT `test all`, which did not
  # resolve. Nothing runs test here: its one option is switched off.
  local proj; proj="$(rustproj)"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  test:
    options:
      rust:
        enabled: false
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "REFUSING -- nothing runs test in this project, so the cycle has no test phase. Nothing was removed."
  # command_unavailable_reason's own words, not a third wording.
  local why
  why="$(fixture_ask "$proj" command_unavailable_reason test)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"
  assert_output_line "test: $why"
  refute_output_contains "--- phase:"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree"

  # And a test line the project switched off runs nothing either, though a
  # run: line is declared: the command is inactive.
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  test:
    enabled: false
    run: scripts/never
YAML
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "REFUSING -- nothing runs test in this project"
  why="$(fixture_ask "$proj" command_unavailable_reason test)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"
  assert_output_line "test: $why"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree"

  # The control: with test running, the same project cycles.
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
YAML
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  refute_output_contains "REFUSING"
  assert_output_contains "--- phase: test all ---"
}

@test "the no-build refusal gives the dispatcher's reason for build (0134)" {
  local proj; proj="$(rustproj_norebuild)"

  run devbin_run "$proj" fullcycle --dry-run

  assert_failure
  local why
  why="$(fixture_ask "$proj" unrunnable_why build)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"
  assert_output_line "build: $why"
}

@test "the artefact check says what is true of release/, and claims no removal the clean never made (0134)" {
  # No target/ before the run: the clean removed nothing, and a dev build then
  # made debug/. The sentence claimed the clean had removed release/.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  devprofile_build "$proj"
  passing_test_cmd "$proj"

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "no removable target/ trees"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  assert_output_line "No release/ holds a binary after this cycle while a debug/ does,"
  refute_output_contains "The clean removed release/"
}

# _pathwatch_fixture <proj> -- one release binary, `tool`, and PATH links to
# it, each spelled a different way: physical and absolute; relative; through
# a linked directory that holds the project (alias/); physical, inside a PATH
# directory named by a link to it (pathlink -> pathreal); and relative, not
# naming the project, in a PATH directory inside it (localbin/). The
# PATH directories go first on PATH through the variable it sets, WATCH_PATH,
# and WATCH_LINKS names each PATH link it made, as PATH reaches it, under the
# test tmpdir.
_pathwatch_fixture() {
  local proj="$1" t="$DEVBIN_TEST_TMPDIR"
  WATCH_LINKS=()
  mkdir -p "$proj/crate/target/debug/.fingerprint" "$proj/crate/target/release" "$t/pathbin" "$t/pathreal"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  printf '#!/bin/sh\nexit 0\n' >"$proj/crate/target/release/tool"
  chmod +x "$proj/crate/target/release/tool"
  ln -s "$t" "$t/alias"
  ln -s "$t/pathreal" "$t/pathlink"
  ln -s "$proj/crate/target/release/tool" "$t/pathbin/physical" && WATCH_LINKS+=(pathbin/physical)
  ln -s "../${proj##*/}/crate/target/release/tool" "$t/pathbin/relative" && WATCH_LINKS+=(pathbin/relative)
  ln -s "$t/alias/${proj##*/}/crate/target/release/tool" "$t/pathbin/aliased" && WATCH_LINKS+=(pathbin/aliased)
  ln -s "$proj/crate/target/release/tool" "$t/pathreal/vialinkeddir" && WATCH_LINKS+=(pathlink/vialinkeddir)
  mkdir -p "$proj/localbin"
  ln -s ../crate/target/release/tool "$proj/localbin/local" && WATCH_LINKS+=("${proj##*/}/localbin/local")
  printf '#!/usr/bin/env bash\nexit 0\n' >"$t/pathbin/cargo"
  chmod +x "$t/pathbin/cargo"
  [ -e "$t/pathbin/relative" ] && [ -e "$t/pathbin/aliased" ] && [ -e "$t/pathlink/vialinkeddir" ] &&
    [ -e "$proj/localbin/local" ] || fail "the fixture's links do not resolve"
  WATCH_PATH="$t/pathbin:$t/pathlink:$proj/localbin"
}

@test "the PATH watch follows each link to where it resolves: relative, spelled through a link, and in a PATH entry that is a link (0134)" {
  # Driven before the fix: clean's own scan named every such link, fullcycle's
  # header said "watching: 1", and after the cycle it named only the physical
  # one dangling. A PATH entry that is a link to a directory was listed as one
  # link and never searched (0139).
  local proj; proj="$(rustproj)"
  _pathwatch_fixture "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
echo "build: dev profile only, release/ untouched"
exit 0' >/dev/null
  passing_test_cmd "$proj"

  PATH="$WATCH_PATH:$PATH" run devbin_run "$proj" fullcycle --force

  assert_failure
  # Every link the fixture made is watched, and the cycle darkens every one: the
  # links are the ones the fixture recorded as it made them.
  local l
  local -a links=("${WATCH_LINKS[@]}")
  [ "${#links[@]}" -gt 0 ] || fail "the fixture recorded no link -- the arm would check nothing"
  assert_output_contains "watching: ${#links[@]} PATH symlink(s) resolving into this tree"
  assert_output_contains "THIS CYCLE DARKENED BINARIES IT DID NOT RESTORE"
  for l in "${links[@]}"; do
    grep -qF "$DEVBIN_TEST_TMPDIR/$l -> " <<<"$output" ||
      fail "the darkened link $l is not named:
$output"
  done
  assert_output_contains "${#links[@]} link(s) resolved before this run and do not now."
}

@test "the PATH watch keeps out a link whose text names the project and resolves outside it (0134)" {
  # find narrows by the project's directory name; the decision is where the
  # link resolves. A sibling directory holding the same name in its path is
  # not this tree.
  local proj; proj="$(rustproj)"
  local t="$DEVBIN_TEST_TMPDIR"
  mkdir -p "$t/elsewhere/${proj##*/}" "$t/pathbin"
  printf '#!/bin/sh\nexit 0\n' >"$t/elsewhere/${proj##*/}/decoy"
  chmod +x "$t/elsewhere/${proj##*/}/decoy"
  ln -s "$t/elsewhere/${proj##*/}/decoy" "$t/pathbin/decoy"
  passing_test_cmd "$proj"

  # THE REAL RUN IS THE MEASUREMENT. A dry run
  # prints only links already dark, so a live decoy wrongly taken in never
  # shows there: this arm read only the dry run and stayed green with the
  # decision replaced by a bare yes. A real run counts what it watches.
  PATH="$t/pathbin:$PATH" run devbin_run "$proj" fullcycle --force
  assert_output_contains "watching: NOTHING -- no PATH symlink resolves into this tree."
  refute_output_contains "decoy"

  # And the dry run names nothing of it either.
  PATH="$t/pathbin:$PATH" run devbin_run "$proj" fullcycle --dry-run
  assert_success
  refute_output_contains "decoy"
  # The control: the same link, aimed into the project, is a candidate the
  # header reports once it dangles.
  mkdir -p "$proj/gone"
  ln -s "$proj/gone/tool" "$t/pathbin/intree"
  PATH="$t/pathbin:$PATH" run devbin_run "$proj" fullcycle --dry-run
  assert_output_contains "ALREADY DANGLING BEFORE THIS RUN"
  assert_output_contains "$t/pathbin/intree -> "
  refute_output_contains "decoy"
}

@test "every yes is a yes: fullcycle runs the cycle on yes, YES and Yes (0134)" {
  # ask_person took y or Y, and the upgrade offer took yes and YES too, so a
  # person who answered yes to fullcycle was told the cycle was declined.
  require_pty
  require_expect
  local proj a
  for a in yes YES Yes; do
    proj="$(rustproj)"
    mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
    run run_tty_answer "$a" sh -c "cd '$proj' && ./bin/devbin fullcycle"
    assert_output_contains "[y/N]"
    refute_output_contains "left alone"
    assert_output_contains "phase: build all"
    [ ! -e "$proj/target" ] || fail "target survived a $a answer:
$output"
    rm -rf "$proj"
  done
}

# THE PHASE IS ONE THAT WILL RUN, NOT ONE WHOSE TIER EXISTS (0134). Each shape
# below passed an earlier guard: the clean removed the trees and the build phase
# then refused, which the config alone could have said. The empty run: line
# and the unresolved handler were refused before that guard by the --help
# probe, so the guard made them regressions; the build kept out of all got
# past the --help probe as well.

# _refused_before_clean <proj> -- the cycle refused, nothing ran, and target/
# is still there.
_refused_before_clean() {
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- this project has no build phase the cycle can run"
  refute_output_contains "--- phase:"
  [ -e "$1/target" ] || fail "the refused cycle removed the target tree:
$output"
  [ ! -e "$1/build.log" ] || fail "the build ran:
$(cat "$1/build.log")"
}

@test "a build run: line with no words is refused before the clean, naming the key (0134)" {
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    run: ""
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: commands.build.run holds no words, so there is no command to run"
}

@test "a build handler that does not resolve is refused before the clean, as the dispatcher refuses it (0134)" {
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    handler: nosuch
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: handler for 'build' is not executable: $proj/bin/.devbin/cmd/nosuch"
  # The dispatcher's own refusal of the same build, for the words above.
  run devbin_run "$proj" build
  assert_output_contains "handler for 'build' is not executable: $proj/bin/.devbin/cmd/nosuch"
}

@test "a build whose every option is kept out of all is refused before the clean (0134)" {
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    options:
      release:
        run: scripts/build
        in_all: false
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: every option it offers is excluded from all: release"

  # The control: with the option in all, the same project cycles and builds.
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    options:
      release:
        run: scripts/build
YAML
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  refute_output_contains "REFUSING"
  assert_output_contains "--- phase: build all ---"
  [ -s "$proj/build.log" ] || fail "the build did not run in the control:
$output"
}

@test "a dangling link through a name that is not there, then .., is not placed in the tree by its text (0134)" {
  # The kernel reads a `..` after the name before it, which may be a link, so
  # gone/../../elsewhere/tool is not known to lead into the tree while gone/
  # is missing: read as text it did, and was reported as already dark in it.
  # The control, a dangling link that names the
  # tree plainly, is reported.
  local proj; proj="$(rustproj)"
  local t="$DEVBIN_TEST_TMPDIR"
  mkdir -p "$t/pathbin"
  ln -s "$proj/gone/../../elsewhere/tool" "$t/pathbin/escapes"
  ln -s "$proj/gone/tool" "$t/pathbin/intree"
  passing_test_cmd "$proj"

  PATH="$t/pathbin:$PATH" run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "$t/pathbin/intree -> "
  refute_output_contains "escapes"
}

@test "a build whose options are switched off or kept out of all is refused before the clean (0134)" {
  # The shape: an option in all but switched off, beside one active but kept
  # out of all. all_partition reads only active options, as run_all does, so
  # `build all` would run nothing, and the cycle says so before the clean.
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    options:
      debug:
        run: scripts/build
        enabled: false
      release:
        run: scripts/build
        in_all: false
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: every option it offers is excluded from all: release"
}

@test "every build option all would run that cannot run is named before the clean, a line each, in the dispatcher's words (0134)" {
  # An option declared with nothing to run it, and one
  # whose own run: holds no words, each refuse inside `build all`, after the
  # clean, so the cycle removed target/ and then failed. One is enough to
  # refuse, and both are named at once.
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    options:
      debug:
        run: scripts/build
      release:
        in_all: true
      docs:
        run: ""
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: 'build release' is declared but has no run: and no handler"
  assert_output_line "build: commands.build.options.docs.run holds no words, so there is no command to run"
  refute_output_contains "build: devbin ships the name only"

  # The dispatcher's own words for the same option.
  run devbin_run "$proj" build release
  assert_output_contains "'build release' is declared but has no run: and no handler"

  # And each alone is enough, beside an option that can run.
  local broken
  for broken in "      release:
        in_all: true" "      docs:
        run: \"\""; do
    printf 'project:\n  name: rustdemo\n  alias: rd\n  languages:\n    - rust\ncommands:\n  build:\n    options:\n      debug:\n        run: scripts/build\n%s\n' \
      "$broken" >"$proj/bin/.devbin/config.yaml"
    run devbin_run "$proj" fullcycle --force
    _refused_before_clean "$proj"
  done

}

@test "an option named all that config switched off, beside a handler, is refused in the dispatcher's words (0134)" {
  # arg_route answers `inactive`, and the check
  # printed "devbin ships the name only" beside a handler that exists.
  local proj; proj="$(rustproj)"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    options:
      all:
        enabled: false
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_line "build: it is disabled in bin/.devbin/config.yaml"
  refute_output_contains "ships the name only"
  refute_output_contains "--- phase:"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree"
}

@test "a dangling PATH link whose content cannot be read exactly is named, not dropped unsaid (0134)" {
  # A content ending in a newline cannot be read back exactly (link_step), so
  # where the link leads is unknown; it is named, as follow_links names a live
  # one, rather than left out of the report of links already dark.
  local proj; proj="$(rustproj)"
  local t="$DEVBIN_TEST_TMPDIR"
  mkdir -p "$t/pathbin"
  ln -s "$proj/gone/tool"$'\n' "$t/pathbin/newline"
  passing_test_cmd "$proj"

  PATH="$t/pathbin:$PATH" run devbin_run "$proj" fullcycle --dry-run

  assert_success
  assert_output_contains "cannot tell which file $t/pathbin/newline is a symbolic link to"
}

@test "a test option whose devbin handler is missing from the install is refused before the clean, in unrunnable_why's words (0134)" {
  # The catalogue's test.rust runs through devbin's own lib/cmd/test. With that
  # file gone from this install, option_run_tier answers `unrunnable`, and
  # `test all` would refuse it after the clean.
  local proj; proj="$(rustproj)"
  rm "$proj/bin/.devbin/lib/cmd/test"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  local why
  why="$(fixture_ask "$proj" unrunnable_why test rust)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"

  run devbin_run "$proj" fullcycle --force

  assert_failure
  assert_output_contains "fullcycle: REFUSING -- nothing runs test in this project"
  assert_output_line "test: $why"
  refute_output_contains "--- phase:"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree"
}

@test "options handed to a command-level run: with no words are refused before the clean, the line named once (0134)" {
  # An option with no run: of its own is handed to
  # commands.build.run, and with that line empty `build all` refused after the
  # clean. Two such options share the one line, so it is named once.
  local proj; proj="$(rustproj_buildrun 'exit 0')"
  write_config "$proj" <<'YAML'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
commands:
  build:
    run: ""
    options:
      debug:
        in_all: true
      release:
        in_all: true
YAML
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"

  run devbin_run "$proj" fullcycle --force

  _refused_before_clean "$proj"
  assert_output_line "build: commands.build.run holds no words, so there is no command to run"
  local n
  n="$(printf '%s\n' "$output" | grep -c 'commands.build.run holds no words')" || [ $? -eq 1 ]
  [ "$n" -eq 1 ] || fail "the line was named $n times:
$output"
}

# ============================================================================
# 0148: A CARGO_TARGET_DIR THE ARTEFACT CHECK CANNOT EXAMINE IS REFUSED FIRST
# ============================================================================

# _refused_for_target_dir <proj> -- refused naming CARGO_TARGET_DIR, nothing
# shown, asked or removed.
_refused_for_target_dir() {
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- CARGO_TARGET_DIR="
  assert_output_contains "so the artefact check could not judge the tree this cycle builds. Nothing was removed."
  assert_output_contains "bin/devbin check targetdir holds the wider rule"
  refute_output_contains "--- phase:"
  refute_output_contains "DRY RUN"
  [ -e "$1/target" ] || fail "the refused cycle removed the target tree:
$output"
}

@test "a relative CARGO_TARGET_DIR is refused before anything is removed, and so is ./target (0148)" {
  # cargo reads a relative value from the directory it runs in: a build run
  # from a crate's directory built a tree the check never looked at, and the
  # cycle passed at rc 0, INCONCLUSIVE, over release artefacts lost.
  local proj v; proj="$(rustproj)"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  for v in rel/t ./target target; do
    CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
    _refused_for_target_dir "$proj"
    assert_output_contains "CARGO_TARGET_DIR=$v is relative, and cargo reads it from the directory it runs in"
  done
  # The value is shown as printf %q quotes it, written out here rather than
  # computed, so a leading space or a tilde can be seen for what it is.
  # A tilde's quoting differs across bash 5 releases, so its expected text is
  # computed; the leading spaces below are written out.
  CARGO_TARGET_DIR='~/x' run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains "CARGO_TARGET_DIR=$(printf '%q' '~/x') is relative"
  CARGO_TARGET_DIR='  /abs' run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains 'CARGO_TARGET_DIR=\ \ /abs is relative'
  # The remedy asks for an absolute path inside the project.
  assert_output_contains "Set it to an absolute path inside the project, or unset it;"
  # And a dry run is refused the same way, before it shows anything.
  CARGO_TARGET_DIR=rel/t run devbin_run "$proj" fullcycle --dry-run
  _refused_for_target_dir "$proj"
  # And --help is still answered: the refusal comes after the arguments.
  CARGO_TARGET_DIR=rel/t run devbin_run "$proj" fullcycle --help
  assert_success
  refute_output_contains "REFUSING"
}

@test "a CARGO_TARGET_DIR holding a newline is refused before anything is removed, shell-quoted (0148)" {
  local proj v; proj="$(rustproj)"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  v="$proj/a"$'\n'"b"
  CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains "CARGO_TARGET_DIR=$(printf '%q' "$v") holds a newline"
}

@test "a CARGO_TARGET_DIR set but empty is refused before anything is removed (0148)" {
  # cargo refuses an empty value, but only when the build runs, after the clean
  # has removed the trees.
  local proj; proj="$(rustproj)"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  CARGO_TARGET_DIR= run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains "fullcycle: REFUSING -- CARGO_TARGET_DIR='' is empty, and cargo refuses an empty target directory,"
}

@test "a CARGO_TARGET_DIR of / is refused before anything is removed (0148)" {
  # ${v%/} emptied it, and the check read "NO cargo build tree found" at rc 0
  # without walking anything.
  local proj v; proj="$(rustproj)"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  for v in / //; do
    CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
    _refused_for_target_dir "$proj"
    assert_output_contains "CARGO_TARGET_DIR=$v is the filesystem root, which the artefact check cannot examine as a build tree,"
  done
}

# envtree_build <proj> -- a build line that makes only debug/, in
# $CARGO_TARGET_DIR: a rebuild that did not put the release artefacts back.
envtree_build() {
  create_test_command "$1" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$CARGO_TARGET_DIR/debug"
printf "#!/bin/sh\nexit 0\n" > "$CARGO_TARGET_DIR/debug/demo"
chmod +x "$CARGO_TARGET_DIR/debug/demo"
exit 0' >/dev/null
}

# stale_release <tree> -- a release binary a previous cycle left.
stale_release() {
  mkdir -p "$1/release"
  printf '#!/bin/sh\nexit 0\n' >"$1/release/demo"
  chmod +x "$1/release/demo"
}

@test "a CARGO_TARGET_DIR outside the project is refused before anything is removed, its last release left alone (0148)" {
  # The clean is project-scoped, so the last cycle's release binary stayed, a
  # debug-only build passed, and the check counted the stale one: rc 0 over
  # the signature it exists for. Older than 0148: cargo_target_dirs has
  # returned CARGO_TARGET_DIR since 0139.
  local proj out; proj="$(rustproj)"
  # Spelled physically, so it is reported as it is, not as what it resolves to.
  out="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/outside/t"
  passing_test_cmd "$proj"
  envtree_build "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  stale_release "$out"
  CARGO_TARGET_DIR="$out" run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains "CARGO_TARGET_DIR=$out is outside the project, which the clean does not reach, and the release artefacts left there would read as this cycle's,"
  assert_output_contains "Point it at a tree inside the project that clean rust removes (bin/devbin clean rust --dry-run lists them), or unset it;"
  [ ! -e "$out/debug" ] || fail "the build ran: $output"
}

@test "a CARGO_TARGET_DIR inside the project through a link to a directory outside it is refused (0148)" {
  # The clean's find does not follow the link, so the tree beneath it is not
  # removed, as one spelled outside is not.
  local proj out; proj="$(rustproj)"
  out="$DEVBIN_TEST_TMPDIR/outside2"
  passing_test_cmd "$proj"
  envtree_build "$proj"
  mkdir -p "$proj/target/debug" "$out" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  ln -s "$out" "$proj/lnk"
  stale_release "$out/t"
  CARGO_TARGET_DIR="$proj/lnk/t" run devbin_run "$proj" fullcycle --force
  _refused_for_target_dir "$proj"
  assert_output_contains "CARGO_TARGET_DIR=$proj/lnk/t resolves to "
  assert_output_contains "/outside2/t, outside the project, which the clean does not reach"
}

@test "a CARGO_TARGET_DIR at <root>/out beside the project's Cargo.toml is swept by the clean and examined: a debug-only build there fails the cycle (0148)" {
  # The clean finds a cargo tree by its marker, not its name, and removes it
  # when a Cargo.toml is beside it, as here: the release artefacts a previous
  # cycle left cannot stand in for this one's. Only beside one: the arms after
  # this hold what happens to a tree the clean does not remove.
  local proj v; proj="$(rustproj)"
  v="$proj/out"
  passing_test_cmd "$proj"
  envtree_build "$proj"
  : >"$proj/Cargo.toml"
  mkdir -p "$v/debug" && cargo_tag "$v"
  stale_release "$v"
  CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  refute_output_contains "REFUSING"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  assert_output_contains "$v -- debug/ has binaries, release/ has none"
}

# kept_release_cycle <proj> <tree> -- a cycle over <tree>, holding the last
# cycle's release binary and cargo's markers, whose build makes only debug/:
# the clean does not remove it, so the check must not count the stale binary.
kept_release_cycle() {
  passing_test_cmd "$1"
  envtree_build "$1"
  mkdir -p "$2/debug" && cargo_tag "$2"
  stale_release "$2"
  CARGO_TARGET_DIR="$2" run devbin_run "$1" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  refute_output_contains "REFUSING"
  assert_output_contains "$2 kept release artefacts through the clean, so they may be the last cycle's -- this tree's profiles were not compared."
  # The tree CARGO_TARGET_DIR names: unsetting it is the remedy both this cycle
  # and check targetdir accept.
  assert_output_contains "Unset CARGO_TARGET_DIR, so cargo builds beside its manifest, where the clean removes the tree, or remove it."
  # Its own sentence in the verdict, not the one for a tree out of reach.
  assert_output_contains "A build tree kept release artefacts through the clean, so they may be"
  refute_output_contains "A build tree could not be reached or searched"
  # Not counted examined, and not INCONCLUSIVE beside INCOMPLETE (`continue 2`
  # and the kept conditions were once held by no arm).
  assert_output_contains "NO cargo build tree could be examined (1, each named above)."
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
  [ -e "$2/release/demo" ] || fail "the stale release binary is gone, so this arm did not hold its case: $output"
}

@test "a tree the clean does not remove, with no Cargo.toml beside it, keeps its release binary and is not compared: the cycle fails (0148)" {
  # <root>/build/out beside no Cargo.toml was
  # skipped by the clean, and its stale release binary passed a debug-only
  # build at rc 0.
  local proj; proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  kept_release_cycle "$proj" "$proj/build/out"
}

@test "a <root>/target/<node> with the crate at native/cli, one consumer's shape, keeps its release binary and is not compared: the cycle fails (0148)" {
  # The value 0148's own remedy once recommended: the clean skipped
  # target/ with no Cargo.toml at the root.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/cli"
  : >"$proj/native/cli/Cargo.toml"
  kept_release_cycle "$proj" "$proj/target/n1"
}

@test "a tree under a directory the clean never walks, .direnv, keeps its release binary and is not compared: the cycle fails (0148)" {
  local proj; proj="$(rustproj)"
  : >"$proj/Cargo.toml"
  kept_release_cycle "$proj" "$proj/.direnv/t"
}

# noop_clean <proj> -- a project's own clean line that removes nothing and
# ignores --refuse-partial, as devbin's own clean rust does not.
noop_clean() {
  create_test_command "$1" clean '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
exit 0' >/dev/null
}

@test "a cargo tree a project's own clean line leaves with a release binary is not compared, and the remedy is to remove it or build where the clean removes (0148)" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  stale_release "$proj/crate/target"
  noop_clean "$proj"
  devprofile_build "$proj"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "$proj/crate/target kept release artefacts through the clean"
  assert_output_contains "Remove it, or build into a tree clean rust removes (bin/devbin clean rust --dry-run lists them)."
}

@test "a target/ the clean does not recognise as cargo's, with a release executable, is said to be one (0148)" {
  # tools/target/release/runme, which the clean
  # ignores as holding no cargo marker, failed the cycle with a remedy to
  # remove a build tree it is not. Named in its own words.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$proj/tools/target/release"
  : >"$proj/crate/Cargo.toml"
  printf '#!/bin/sh\nexit 0\n' >"$proj/tools/target/release/runme"
  chmod +x "$proj/tools/target/release/runme"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "$proj/tools/target kept release artefacts through the clean"
  assert_output_contains "It is not a tree the clean recognises as cargo's, carrying no cargo marker: remove it if it is a build tree, or move what it holds."
}

@test "a walk after the clean that cannot read everything fails the cycle, where a stale release beneath the hole was read green (0148)" {
  # A project's own clean line ignoring
  # --refuse-partial, a stale release under locked/ at mode 000, and a build
  # that opens locked/ and makes only debug/: the post-clean walk's status was
  # dropped, and the check compared the stale release at rc 0.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/locked/target/debug"
  : >"$proj/locked/Cargo.toml"
  cargo_tag "$proj/locked/target"
  stale_release "$proj/locked/target"
  noop_clean "$proj"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
chmod 755 "$PWD/locked"
printf "#!/bin/sh\nexit 0\n" > "$PWD/locked/target/debug/demo"
chmod +x "$PWD/locked/target/debug/demo"
exit 0' >/dev/null
  chmod 000 "$proj/locked"
  [ ! -r "$proj/locked" ] || readable=1
  if [ "$readable" = 1 ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: NOT checked"
  fi
  run devbin_run "$proj" fullcycle --force
  chmod 755 "$proj/locked"
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "The walk after the clean could not read everything, so a tree that kept"
  refute_output_contains "FULLCYCLE FINISHED -- rc=0"
}

@test "a hole the walk after the clean met, with nothing compared, is INCOMPLETE and never INCONCLUSIVE too (0148)" {
  # Dropping kept_partial from the INCONCLUSIVE
  # conditions printed both verdicts, and no arm went red.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$proj/locked"
  : >"$proj/crate/Cargo.toml"
  noop_clean "$proj"
  passing_test_cmd "$proj"
  create_test_command "$proj" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
chmod 755 "$PWD/locked"
exit 0' >/dev/null
  chmod 000 "$proj/locked"
  [ ! -r "$proj/locked" ] || readable=1
  if [ "$readable" = 1 ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: NOT checked"
  fi
  run devbin_run "$proj" fullcycle --force
  chmod 755 "$proj/locked"
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "The walk after the clean could not read everything"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "a kept tree the clean recognises as cargo's, by its .fingerprint, gets the cargo remedy, and one with another tool's CACHEDIR.TAG does not (0148)" {
  # A second answer to the clean's marker question
  # called a .fingerprint tree unrecognised, and gave a pytest tag the cargo
  # remedy. _clean_has_markers is now the one answer.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$proj/tools/target/release/.fingerprint"
  : >"$proj/crate/Cargo.toml"
  printf '#!/bin/sh\nexit 0\n' >"$proj/tools/target/release/runme"
  chmod +x "$proj/tools/target/release/runme"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "$proj/tools/target kept release artefacts through the clean"
  assert_output_contains "Remove it, or build into a tree clean rust removes"
  refute_output_contains "It is not a tree the clean recognises as cargo's"
  rm -rf "$proj/tools/target/release/.fingerprint"
  printf 'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by pytest.\n' >"$proj/tools/target/CACHEDIR.TAG"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  # Named for tools/target itself, not for another kept tree beside it.
  assert_output_contains "$proj/tools/target kept release artefacts through the clean, so they may be the last cycle's -- this tree's profiles were not compared.
       It is not a tree the clean recognises as cargo's"
  refute_output_contains "$proj/crate/target kept"
}

@test "a target reached through a link, beside the project's Cargo.toml as the clean reads it, is not told to unset CARGO_TARGET_DIR (0148)" {
  # "Beside" was resolved through the link, where
  # the clean reads the path as given, and the advice sent the user in a circle.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/build/tgt/debug"
  : >"$proj/Cargo.toml"
  ln -s build/tgt "$proj/target"
  cargo_tag "$proj/build/tgt"
  stale_release "$proj/build/tgt"
  noop_clean "$proj"
  envtree_build "$proj"
  passing_test_cmd "$proj"
  CARGO_TARGET_DIR="$proj/target" run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "kept release artefacts through the clean"
  refute_output_contains "Unset CARGO_TARGET_DIR"
}

@test "the tree CARGO_TARGET_DIR names beside its manifest, kept by a project's own clean line, is not told to unset it (0148)" {
  # Unsetting changes nothing for a tree already
  # beside its Cargo.toml.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  stale_release "$proj/crate/target"
  noop_clean "$proj"
  envtree_build "$proj"
  passing_test_cmd "$proj"
  CARGO_TARGET_DIR="$proj/crate/target" run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "$proj/crate/target kept release artefacts through the clean"
  refute_output_contains "Unset CARGO_TARGET_DIR"
  assert_output_contains "Remove it, or build into a tree clean rust removes"
}

@test "over a directory it cannot read, devbin's own clean refuses before removing anything, so the cycle stops with every tree in place (0148, 0150)" {
  # What makes a partial walk for crates safe to proceed over (0150): the
  # clean, run with --refuse-partial, decides at its scan.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate/target/debug" "$proj/locked/t"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/crate/target"
  stale_release "$proj/crate/target"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  chmod 000 "$proj/locked"
  [ ! -r "$proj/locked" ] || readable=1
  if [ "$readable" = 1 ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: NOT checked"
  fi
  run devbin_run "$proj" fullcycle --force
  chmod 755 "$proj/locked"
  [ "$status" -ne 0 ] || fail "the cycle passed over a directory the clean could not read: $output"
  assert_output_contains "refusing, as --refuse-partial asks: the scan is partial, and nothing was removed or marked"
  refute_output_contains "--- phase: build"
  [ -e "$proj/crate/target/release/demo" ] || fail "the clean removed a tree before it refused: $output"
}

@test "a CARGO_TARGET_DIR spelled through the other name of the project's directory is inside it (0148)" {
  # /var and /private/var name one directory on macOS: a value spelled either
  # way is the project's.
  local proj phys v; proj="$(rustproj)"
  phys="$(cd -P "$proj" && pwd -P)"
  if [ "$phys" = "$proj" ]; then
    case "$proj" in
      /private/*) v="${proj#/private}/crate/target" ;;
      *) skip "the project's directory has one name here: the other spelling was NOT checked" ;;
    esac
  else
    v="$phys/crate/target"
  fi
  [ -d "${v%/crate/target}" ] || skip "no other name for $proj here: NOT checked"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
  assert_success
  refute_output_contains "REFUSING"
}

@test "cargo_tree_outside_why answers nothing inside the project, and names each way out (0148)" {
  local proj why out; proj="$(rustproj)"
  out="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/away"
  mkdir -p "$out" "$proj/real"
  ln -s "$out" "$proj/lnk"
  for v in "$proj/target" "$proj/target/n1" "$proj/not/yet/made" "$proj//target/" "$proj/real/t"; do
    why="$(fixture_ask "$proj" cargo_tree_outside_why "$v" "$proj")"
    [ -z "$why" ] || fail "$v was refused: $why"
  done
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$out/t" "$proj")"
  [ "$why" = "is outside the project, which the clean does not reach, and the release artefacts left there would read as this cycle's" ] || fail "outside: $why"
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$proj/lnk/t" "$proj")"
  [[ "$why" == "resolves to "*"/away/t, outside the project, which the clean does not reach"* ]] || fail "link: $why"
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$proj" "$proj")"
  [[ "$why" == "is the project root, which the clean does not remove"* ]] || fail "root: $why"
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$proj/new/../../escape" "$proj")"
  [[ "$why" == "names . or .. beneath a directory that does not exist yet"* ]] || fail "dotdot: $why"
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$proj/../t" "$proj")"
  [[ "$why" == "resolves to "*", outside the project"* ]] || fail "an existing ..: $why"
  # A dangling link on the way cannot be placed.
  ln -s "$DEVBIN_TEST_TMPDIR/nonexistent/zz" "$proj/dl"
  why="$(fixture_ask "$proj" cargo_tree_outside_why "$proj/dl/t" "$proj")"
  [[ "$why" == "cannot be placed: "*"/dl cannot be entered, so where it resolves cannot be known" ]] || fail "dangling: $why"
  # And a spelling in another case names the same directory where the
  # filesystem ignores case, as APFS does by default.
  local upper; upper="$(printf '%s' "$proj" | tr '[:lower:]' '[:upper:]')"
  if [ "$upper" != "$proj" ] && [ -d "$upper" ] && [ "$upper" -ef "$proj" ]; then
    why="$(fixture_ask "$proj" cargo_tree_outside_why "$upper/target" "$proj")"
    [ -z "$why" ] || fail "a spelling in another case was refused: $why"
  else
    echo "# this filesystem does not ignore case: the other-case spelling was NOT checked" >&3
  fi
}

@test "cargo_tree_outside_why answers a relative path at once, and does not hang (0148, 0166)" {
  # With a relative value let through, the walk up once spun for 11
  # minutes. Bounded here at 10 seconds, so a return of the hang
  # is a red arm, never a stalled suite.
  local proj out; proj="$(rustproj)"
  out="$(fixture_run "$proj" 'cargo_tree_outside_why "$1" "$2" & p=$!; ( sleep 10; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & w=$!; rc=0; wait "$p" || rc=$?; kill "$w" 2>/dev/null; exit "$rc"' rel/t "$proj")" ||
    fail "it did not return within 10s, or failed: $out"
  # In cargo_target_dir_why's words, which it asks first (issue 0166).
  [ "$out" = "is relative, and cargo reads it from the directory it runs in, which fullcycle cannot know" ] || fail "relative: $out"
}

@test "cargo_tree_outside_why calls / the filesystem root, under any number of slashes, as cargo_target_dir_why does (0166)" {
  # It tidied / to an empty string, cargo_place answered with a 3 nothing read,
  # and the walk up called the root "outside the project". No caller met it,
  # since each asks cargo_target_dir_why first; asked directly, it was wrong.
  local proj why v; proj="$(rustproj)"
  for v in / // ///; do
    why="$(fixture_ask "$proj" cargo_tree_outside_why "$v" "$proj")"
    [ "$why" = "is the filesystem root, which the artefact check cannot examine as a build tree" ] || fail "$v: $why"
  done
}

@test "cargo_target_dir_why answers for each value, and nothing for an absolute one (0148)" {
  local proj why v; proj="$(rustproj)"
  for v in rel/t ./target '~/x'; do
    why="$(fixture_ask "$proj" cargo_target_dir_why "$v")"
    [ "$why" = "is relative, and cargo reads it from the directory it runs in, which fullcycle cannot know" ] ||
      fail "$v: $why"
  done
  why="$(fixture_ask "$proj" cargo_target_dir_why "/a"$'\n'"b")"
  [ "$why" = "holds a newline, and the artefact check reads build trees a line at a time" ] || fail "newline: $why"
  why="$(fixture_ask "$proj" cargo_target_dir_why "")"
  [ "$why" = "is empty, and cargo refuses an empty target directory" ] || fail "empty: $why"
  for v in / // ///; do
    why="$(fixture_ask "$proj" cargo_target_dir_why "$v")"
    [ "$why" = "is the filesystem root, which the artefact check cannot examine as a build tree" ] || fail "$v: $why"
  done
  for v in /abs/t /abs/t/ /a //a/; do
    why="$(fixture_ask "$proj" cargo_target_dir_why "$v")"
    [ -z "$why" ] || fail "$v was refused: $why"
  done
}

@test "an absolute CARGO_TARGET_DIR, a trailing slash included, is examined as before: the control (0148)" {
  local proj v; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  mkdir -p "$proj/crate/target/debug"
  for v in "$proj/crate/target" "$proj/crate/target/"; do
    # Tagged as cargo tags it, so the clean removes it each time round, as the
    # stub build's own tag does (0148); an untagged tree is not the
    # clean's, and a second round would read the first round's release/.
    cargo_tag "$proj/crate/target"
    CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
    assert_success
    refute_output_contains "REFUSING"
    assert_output_contains "--- phase: clean rust ---"
    assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  done
  # And it is the value that is examined, not a tree the walk would find: one
  # in the project that does not exist is named.
  v="$proj/nowhere/t"
  CARGO_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
  refute_output_contains "REFUSING"
  assert_output_contains "$v"
}

# ============================================================================
# 0150: CARGO_BUILD_TARGET_DIR AND A CARGO CONFIG'S build.target-dir
# ============================================================================

# buildenv_build <proj> -- a build line that makes only debug/, in
# $CARGO_BUILD_TARGET_DIR.
buildenv_build() {
  create_test_command "$1" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p "$CARGO_BUILD_TARGET_DIR/debug"
printf "#!/bin/sh\nexit 0\n" > "$CARGO_BUILD_TARGET_DIR/debug/demo"
chmod +x "$CARGO_BUILD_TARGET_DIR/debug/demo"
exit 0' >/dev/null
}

# outdir_build <proj> <tree> -- a build line that makes only debug/, in
# <tree>, where a cargo config told cargo to build.
outdir_build() {
  create_test_command "$1" build '#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
mkdir -p '"$(printf '%q' "$2")"'/debug
printf "#!/bin/sh\nexit 0\n" > '"$(printf '%q' "$2")"'/debug/demo
chmod +x '"$(printf '%q' "$2")"'/debug/demo
exit 0' >/dev/null
}

@test "a relative CARGO_BUILD_TARGET_DIR is refused before anything is removed, naming it (0150)" {
  local proj; proj="$(rustproj)"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  CARGO_BUILD_TARGET_DIR=rel/t run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- CARGO_BUILD_TARGET_DIR=rel/t is relative, and cargo reads it from the directory it runs in"
  refute_output_contains "--- phase:"
  [ -e "$proj/target" ] || fail "the refused cycle removed the target tree: $output"
}

@test "a CARGO_BUILD_TARGET_DIR outside the project is refused; CARGO_TARGET_DIR, which cargo puts first, is the one judged (0150)" {
  local proj out; proj="$(rustproj)"
  out="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/outside/b"
  passing_test_cmd "$proj"
  mkdir -p "$proj/target/debug" && cargo_tag "$proj/target" && : >"$proj/Cargo.toml"
  stale_release "$out"
  CARGO_BUILD_TARGET_DIR="$out" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- CARGO_BUILD_TARGET_DIR=$out is outside the project, which the clean does not reach"
  # CARGO_TARGET_DIR decides the tree over it (cargo 1.98.1), so an inside
  # CARGO_TARGET_DIR is judged, not the outside CARGO_BUILD_TARGET_DIR.
  CARGO_TARGET_DIR="$proj/crate/target" CARGO_BUILD_TARGET_DIR="$out" run devbin_run "$proj" fullcycle --dry-run
  refute_output_contains "REFUSING"
}

@test "a CARGO_BUILD_TARGET_DIR inside the project is the tree examined: a debug-only build there fails the cycle (0150)" {
  local proj v; proj="$(rustproj)"
  v="$proj/out"
  passing_test_cmd "$proj"
  buildenv_build "$proj"
  : >"$proj/Cargo.toml"
  mkdir -p "$v/debug" && cargo_tag "$v"
  CARGO_BUILD_TARGET_DIR="$v" run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  assert_output_contains "$v -- debug/ has binaries, release/ has none"
}

@test "a crate's .cargo/config.toml target-dir is asked of cargo, and the tree it names is examined: a debug-only build there fails the cycle (0150)" {
  # `target-dir = "out"` went unseen, and a
  # debug-only build read NO cargo build tree found, INCONCLUSIVE at rc 0.
  need_cargo
  local proj crate; proj="$(rustproj)"
  crate="$proj/crate"
  real_crate "$crate"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  passing_test_cmd "$proj"
  outdir_build "$proj" "$crate/out"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  assert_output_contains "$crate/out -- debug/ has binaries, release/ has none"
}

@test "a crate's config target-dir outside the project is refused before anything is removed, naming the crate and the tree (0150)" {
  need_cargo
  local proj crate out; proj="$(rustproj)"
  crate="$proj/crate"
  out="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/elsewhere"
  real_crate "$crate"
  mkdir -p "$crate/.cargo" "$crate/target/debug" && cargo_tag "$crate/target"
  printf '[build]\ntarget-dir = "%s"\n' "$out" >"$crate/.cargo/config.toml"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $out, which is outside the project, which the clean does not reach"
  assert_output_contains "Point its build.target-dir at a tree inside the project that clean rust removes"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

# _machine_fixture <proj> <home> -- a crate at <proj>/crate with a debug tree,
# a passing test command, and <home> made for a machine config.
_machine_fixture() {
  real_crate "$1/crate"
  mkdir -p "$2" "$1/crate/target/debug" && cargo_tag "$1/crate/target"
  passing_test_cmd "$1"
}

@test "a tree only the machine's cargo config sends outside the project is refused naming that config, with a config of the workspace's own as the remedy (0164)" {
  # The refusal said "Point its build.target-dir", naming no file, and sent the
  # reader to check targetdir, which reports a machine-wide fork and does not
  # fail it: the machine's config is not this project's to change.
  need_cargo
  local proj crate out home; proj="$(rustproj)"
  crate="$proj/crate"
  out="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/elsewhere"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  printf '[build]\ntarget-dir = "%s"\n' "$out" >"$home/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $out, as the machine's cargo config $home/config.toml sends every crate on this machine, which is outside the project"
  assert_output_contains "Set build.target-dir = \"target\" in the workspace's own cargo config, its .cargo/config beside its root Cargo.toml if it has one, else .cargo/config.toml there"
  assert_output_contains "check targetdir reports a machine-wide config, and does not fail it."
  # CARGO_TARGET_DIR was the remedy, and check targetdir fails every value of
  # it but the shared tree.
  refute_output_contains "CARGO_TARGET_DIR"
  refute_output_contains "Point its build.target-dir"
  refute_output_contains "check targetdir holds the wider rule"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "a crate config's own outside tree, while the machine's config names another, is refused as a config not named here, never the machine's (0164)" {
  # The machine's wording turns on the tree being the machine's: without that
  # comparison, every crate config's outside tree on a machine whose config
  # names a target-dir was blamed on the machine.
  need_cargo
  local proj crate base home; proj="$(rustproj)"
  crate="$proj/crate"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "%s/machine-elsewhere"\n' "$base" >"$home/config.toml"
  printf '[build]\ntarget-dir = "%s/crate-elsewhere"\n' "$base" >"$crate/.cargo/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $base/crate-elsewhere, which is outside the project"
  assert_output_contains "or remove it, in the cargo config that sets it, which is not named here;"
  assert_output_contains "check targetdir holds the wider rule."
  refute_output_contains "machine's cargo config"
  refute_output_contains "in the workspace's own cargo config"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "a tree the machine's cargo config names through a link is refused as the machine's, compared as it resolves (0164)" {
  # cargo names the tree as the config spells it; the refusal and the probe
  # each place theirs, and an arm with a physical tree held neither placement.
  need_cargo
  local proj crate base home; proj="$(rustproj)"
  crate="$proj/crate"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  mkdir -p "$base/real"
  ln -s "$base/real" "$base/lnk"
  printf '[build]\ntarget-dir = "%s/lnk/elsewhere"\n' "$base" >"$home/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $base/lnk/elsewhere, as the machine's cargo config $home/config.toml sends every crate on this machine, which "
  refute_output_contains "which is not named here"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "with both config and config.toml in CARGO_HOME, the refusal names config, the file cargo reads (0164)" {
  need_cargo
  local proj crate base home; proj="$(rustproj)"
  crate="$proj/crate"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  printf '[build]\ntarget-dir = "%s/from-bare"\n' "$base" >"$home/config"
  printf '[build]\ntarget-dir = "%s/from-toml"\n' "$base" >"$home/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $base/from-bare, as the machine's cargo config $home/config sends every crate on this machine"
  refute_output_contains "from-toml"
  refute_output_contains "$home/config.toml"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "a tree the project's config and the machine's both name is refused as the project's, as check targetdir fails it (0164)" {
  # fullcycle asked only for the machine's config, so this tree was "reported,
  # not failed" there while check targetdir failed it on .cargo/config.toml.
  # The project's value is relative, so the value named reads apart from the
  # tree it places.
  need_cargo
  local proj crate home; proj="$(rustproj)"
  crate="$proj/crate"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "%s/pfork"\n' "$(cd -P "$proj/.." && pwd -P)" >"$home/config.toml"
  printf '[build]\ntarget-dir = "../pfork"\n' >"$proj/.cargo/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "as the project's cargo config .cargo/config.toml sets build.target-dir = ../pfork, which resolves to "
  assert_output_contains "Point that file's build.target-dir at a tree inside the project that clean rust removes"
  refute_output_contains "machine's cargo config"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
  CARGO_HOME="$home" run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains ".cargo/config.toml sets build.target-dir = ../pfork, and cargo builds crate into "
}

@test "a refusal whose machine probe a config above TMPDIR clouds names no cause, and says the machine's could not be measured (0164)" {
  # The probe's status 2 ended fullcycle under errexit with no word, had it
  # not been caught; caught, it is said.
  need_cargo
  local proj crate base home; proj="$(rustproj)"
  crate="$proj/crate"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  mkdir -p "$proj/.tmp" "$proj/.cargo" "$crate/.cargo"
  printf 'include = []\n' >"$proj/.cargo/config.toml"
  printf '[build]\ntarget-dir = "%s/machine-elsewhere"\n' "$base" >"$home/config.toml"
  printf '[build]\ntarget-dir = "%s/crate-elsewhere"\n' "$base" >"$crate/.cargo/config.toml"
  CARGO_HOME="$home" TMPDIR="$proj/.tmp" run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "fullcycle: REFUSING -- cargo builds $crate into $base/crate-elsewhere, which is outside the project"
  assert_output_contains "which is not named here, and where the machine's config sends a build could not be measured: a cargo config at or above $proj/.tmp may apply too;"
  refute_output_contains "machine's cargo config"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "the machine refusal's remedy, a workspace config naming target, passes fullcycle's judgement of the tree and check targetdir (0164)" {
  # Offered only as measured: cargo puts the workspace's config before the
  # machine's, and its own target is one the clean removes and check targetdir
  # passes.
  need_cargo
  local proj crate home; proj="$(rustproj)"
  crate="$proj/crate"
  home="$DEVBIN_TEST_TMPDIR/machinecargo"
  _machine_fixture "$proj" "$home"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "%s/elsewhere"\n' "$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)" >"$home/config.toml"
  printf '[build]\ntarget-dir = "target"\n' >"$crate/.cargo/config.toml"
  CARGO_HOME="$home" run devbin_run "$proj" fullcycle --force
  refute_output_contains "REFUSING -- cargo builds"
  assert_output_contains "--- phase:"
  CARGO_HOME="$home" run devbin_run "$proj" check targetdir
  assert_success
  assert_output_contains "cargo    crate builds into its own target"
}

@test "a manifest cargo cannot read, where a config names target-dir, is refused before anything is removed, in cargo's words (0150)" {
  need_cargo
  local proj crate; proj="$(rustproj)"
  crate="$proj/crate"
  mkdir -p "$crate/.cargo" "$crate/target/debug" && cargo_tag "$crate/target"
  printf 'this is not toml [\n' >"$crate/Cargo.toml"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "cargo cannot say where $crate builds: error:"
  assert_output_contains "fullcycle: REFUSING -- where cargo builds could not be known (the error above says why)"
  refute_output_contains "--- phase:"
  [ -e "$crate/target" ] || fail "the refused cycle removed a tree: $output"
}

@test "with no carrier present cargo is not run, and the cycle is as it was: the control (0150)" {
  # A fixture crate whose Cargo.toml is empty, which cargo refuses to read, as
  # 51 of this file's are: nothing asks cargo about it, so nothing refuses it.
  local proj bin; proj="$(rustproj)"
  bin="$DEVBIN_TEST_TMPDIR/cargobin"
  mkdir -p "$bin" "$proj/crate"
  printf '#!/bin/sh\necho "cargo $*" >>"%s/cargo.calls"\nexit 101\n' "$DEVBIN_TEST_TMPDIR" >"$bin/cargo"
  chmod +x "$bin/cargo"
  : >"$proj/crate/Cargo.toml"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  mkdir -p "$proj/crate/target/debug" && cargo_tag "$proj/crate/target"
  PATH="$bin:$PATH" run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  [ ! -e "$DEVBIN_TEST_TMPDIR/cargo.calls" ] || fail "cargo was run: $(cat "$DEVBIN_TEST_TMPDIR/cargo.calls")"
}

@test "cargo_carrier_present opens for a config naming target-dir, in the crate, above it, or in CARGO_HOME, and for no other (0150)" {
  local proj crate why; proj="$(rustproj)"
  crate="$proj/a/crate"
  mkdir -p "$crate"
  ! fixture_ask "$proj" cargo_carrier_present "$crate" || fail "open with no config"
  mkdir -p "$crate/.cargo"
  printf '[registries]\nx = { index = "y" }\n' >"$crate/.cargo/config.toml"
  ! fixture_ask "$proj" cargo_carrier_present "$crate" || fail "open for a config that names no target-dir"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  fixture_ask "$proj" cargo_carrier_present "$crate" || fail "shut for the crate's own config"
  rm "$crate/.cargo/config.toml"
  mkdir -p "$proj/a/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$proj/a/.cargo/config"
  fixture_ask "$proj" cargo_carrier_present "$crate" || fail "shut for a config above the crate"
  rm "$proj/a/.cargo/config"
  # The test's own CARGO_HOME, empty in the shared setup: a config planted
  # there opens the gate, as a runner's home config would.
  printf '[build]\ntarget-dir = "/elsewhere"\n' >"$CARGO_HOME/config.toml"
  fixture_ask "$proj" cargo_carrier_present "$crate" || fail "shut for CARGO_HOME's config"
  rm "$CARGO_HOME/config.toml"
  # One that includes another config opens it: the included file may name the
  # key.
  printf 'include = ["other.toml"]\n' >"$crate/.cargo/config.toml"
  fixture_ask "$proj" cargo_carrier_present "$crate" || fail "shut for a config naming include"
  rm "$crate/.cargo/config.toml"
  # One that cannot be read is present, for cargo to answer.
  printf '[build]\n' >"$crate/.cargo/config.toml"
  chmod 000 "$crate/.cargo/config.toml"
  if [ -r "$crate/.cargo/config.toml" ]; then
    chmod 644 "$crate/.cargo/config.toml"
    echo "# running with permissions that read a mode-000 file: the unreadable half was NOT checked" >&3
  else
    fixture_ask "$proj" cargo_carrier_present "$crate" || { chmod 644 "$crate/.cargo/config.toml"; fail "shut for an unreadable config"; }
    chmod 644 "$crate/.cargo/config.toml"
  fi
}

@test "cargo_build_dir asks cargo from the crate's directory, offline, and leaves Cargo.lock as it was (0150)" {
  need_cargo
  local proj crate m1 m2 why; proj="$(rustproj)"
  crate="$proj/crate"
  real_crate "$crate"
  (cd "$crate" && cargo generate-lockfile --offline >/dev/null 2>&1) || skip "cargo could not write a lock offline here: NOT checked"
  cp -p "$crate/Cargo.lock" "$DEVBIN_TEST_TMPDIR/lock.before"
  # Each stat spelling captured alone, as cmd/fleet's mtime_epoch does: GNU's -f is
  # filesystem status, printed to stdout, so `a || b` inside one $() read that
  # block, free-block counts and all, and went red on every Ubuntu run.
  lock_mtime() { local o; o="$(stat -f %m "$1" 2>/dev/null)" && [[ "$o" =~ ^[0-9]+$ ]] || o="$(stat -c %Y "$1")"; printf '%s' "$o"; }
  m1="$(lock_mtime "$crate/Cargo.lock")"
  why="$(fixture_run "$proj" 'cargo_build_dir "$1" t r; printf "%s|%s" "$t" "$r"' "$crate")"
  [ "$why" = "$(cd -P "$crate" && pwd -P)/target|$(cd -P "$crate" && pwd -P)" ] || fail "no config: $why"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  why="$(fixture_run "$proj" 'cargo_build_dir "$1" t r; printf "%s|%s" "$t" "$r"' "$crate")"
  [ "$why" = "$(cd -P "$crate" && pwd -P)/out|$(cd -P "$crate" && pwd -P)" ] || fail "config: $why"
  m2="$(lock_mtime "$crate/Cargo.lock")"
  cmp -s "$DEVBIN_TEST_TMPDIR/lock.before" "$crate/Cargo.lock" || fail "Cargo.lock's bytes changed"
  [ "$m1" = "$m2" ] || fail "Cargo.lock's mtime changed: $m1 -> $m2"
}

@test "cargo_build_dirs refuses, naming it, when a config names target-dir and cargo is not on PATH (0150)" {
  local proj out; proj="$(rustproj)"
  mkdir -p "$proj/crate/.cargo"
  : >"$proj/crate/Cargo.toml"
  printf '[build]\ntarget-dir = "out"\n' >"$proj/crate/.cargo/config.toml"
  out="$(fixture_run "$proj" 'PATH=/usr/bin:/bin; command -v cargo >/dev/null && { echo HAS-CARGO; exit 0; }; rc=0; cargo_build_dirs a b c 2>&1 || rc=$?; echo "rc=$rc"')"
  [ "$out" != HAS-CARGO ] || skip "cargo is in /usr/bin or /bin on this runner: NOT checked"
  [[ "$out" == *"cargo is not on PATH, so where "*"/crate builds cannot be known: a cargo config there names target-dir"* ]] || fail "$out"
  [[ "$out" == *"rc=1" ]] || fail "$out"
}

@test "cargo_build_dirs named two arrays fills both, and an empty roots name drops the roots (0169)" {
  # fullcycle judges trees and never roots, so it names two arrays. The third
  # was required: a call naming two died on an unbound $3, which is why the
  # cycle carried a roots array it never read, held off the linter by a
  # disable, and an empty third name had bash refuse it on stderr while the
  # call ran on. stderr is part of what is compared, so that refusal is red.
  need_cargo
  local proj crate out frc; proj="$(rustproj)"
  crate="$proj/crate"
  real_crate "$crate"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  # The dropped roots fill a local of the call's own, so its name is asked for
  # after each call: without that local, the roots leaked into a global the
  # caller could see, and this arm stayed green. frc is
  # fixture_run's own status, so a fixture that failed (its 8 or 9) says so.
  frc=0
  out="$(fixture_run "$proj" 'rc=0; cargo_build_dirs c t || rc=$?; r=dropped; declare -p _cbds_noroots >/dev/null 2>&1 && r=kept; printf "rc=%s n=%s|%s|%s|roots %s" "$rc" "${#c[@]}" "${c[0]:-}" "${t[0]:-}" "$r"' 2>&1)" || frc=$?
  [ "$out" = "rc=0 n=1|$crate|$(cd -P "$crate" && pwd -P)/out|roots dropped" ] || fail "two names, fixture_run rc=$frc: $out"
  frc=0
  out="$(fixture_run "$proj" 'rc=0; cargo_build_dirs c t "" f || rc=$?; r=dropped; declare -p _cbds_noroots >/dev/null 2>&1 && r=kept; printf "rc=%s n=%s|%s|%s|roots %s" "$rc" "${#t[@]}" "${t[0]:-}" "${f[0]:-}" "$r"' 2>&1)" || frc=$?
  [ "$out" = "rc=0 n=1|$(cd -P "$crate" && pwd -P)/out|$crate/.cargo/config.toml|roots dropped" ] || fail "an empty roots name, with configs, fixture_run rc=$frc: $out"
}

@test "cargo_build_dirs with no crate asks no cargo, takes either call shape, and drops the roots (0169)" {
  # The arm above needs cargo, so a runner without it skips the only pin on an
  # empty roots name. With no crate here cargo is
  # never asked, so this holds both call shapes on every runner: an unbound
  # $3, an empty name refused on stderr, and roots left in a global are each
  # red, with cargo on PATH or not.
  local proj out frc; proj="$(rustproj)"
  frc=0
  out="$(fixture_run "$proj" 'rc=0; cargo_build_dirs c t || rc=$?; r=dropped; declare -p _cbds_noroots >/dev/null 2>&1 && r=kept; printf "rc=%s n=%s %s|roots %s" "$rc" "${#c[@]}" "${#t[@]}" "$r"' 2>&1)" || frc=$?
  [ "$out" = "rc=0 n=0 0|roots dropped" ] || fail "two names, fixture_run rc=$frc: $out"
  frc=0
  out="$(fixture_run "$proj" 'rc=0; cargo_build_dirs c t "" f || rc=$?; r=dropped; declare -p _cbds_noroots >/dev/null 2>&1 && r=kept; printf "rc=%s n=%s %s %s|roots %s" "$rc" "${#c[@]}" "${#t[@]}" "${#f[@]}" "$r"' 2>&1)" || frc=$?
  [ "$out" = "rc=0 n=0 0 0|roots dropped" ] || fail "an empty roots name, with configs, fixture_run rc=$frc: $out"
}

@test "a crate whose path holds a backslash is examined at the tree cargo names, byte for byte (0150)" {
  # jq's @tsv read a\b back as a\\b, so the check
  # looked at a tree that does not exist and read INCONCLUSIVE at rc 0.
  need_cargo
  local proj crate; proj="$(rustproj)"
  crate="$proj/a\\b"
  real_crate "$crate"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  passing_test_cmd "$proj"
  outdir_build "$proj" "$crate/out"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "cargo_build_dir names jq, not cargo, when jq is not on PATH (0150)" {
  need_cargo
  local proj out bin; proj="$(rustproj)"
  real_crate "$proj/crate"
  # A PATH of the tools it runs, less jq: macOS ships /usr/bin/jq, so a PATH
  # of the system directories would hold one.
  bin="$DEVBIN_TEST_TMPDIR/nojq"
  mkdir -p "$bin"
  local tool
  for tool in cargo mktemp grep rm; do ln -s "$(command -v "$tool")" "$bin/$tool"; done
  out="$(fixture_run "$proj" 'PATH="$2"; command -v jq >/dev/null && { echo HAS-JQ; exit 0; }; rc=0; cargo_build_dir "$1" t r 2>&1 || rc=$?; echo "rc=$rc"' "$proj/crate" "$bin")"
  [ "$out" != HAS-JQ ] || fail "jq was still found"
  [[ "$out" == *"jq is not on PATH, so cargo's answer for where "*"/crate builds cannot be read"* ]] || fail "$out"
  [[ "$out" == *"rc=1" ]] || fail "$out"
}

@test "a crate whose directory name ends in a newline is still asked about, and its answer judged (0150)" {
  # The walk for crates was read a line at a time,
  # the name split, the crate's config went unseen, and the cycle read
  # INCONCLUSIVE at rc 0.
  need_cargo
  local proj crate; proj="$(rustproj)"
  crate="$proj/c"$'\n'
  real_crate "$crate"
  mkdir -p "$crate/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$crate/.cargo/config.toml"
  passing_test_cmd "$proj"
  outdir_build "$proj" "$crate/out"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  # Asked, and its tree, which holds the newline, refused up front: read a line
  # at a time the crate was never asked.
  assert_output_contains "fullcycle: REFUSING -- cargo builds "
  assert_output_contains "holds a newline"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "cargo_place answers a relative path at once, status 3, and does not hang (0150)" {
  # The walk up never ends on a path with no leading / (it once spun for 11
  # minutes). Bounded at 10 seconds, so its return is a red arm.
  local proj out; proj="$(rustproj)"
  out="$(fixture_run "$proj" '{ c=0; cargo_place "$1" o || c=$?; printf "rc=%s o=%s" "$c" "$o"; } & p=$!; ( sleep 10; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & w=$!; rc=0; wait "$p" || rc=$?; kill "$w" 2>/dev/null; exit "$rc"' rel/t)" ||
    fail "it did not return within 10s: $out"
  [ "$out" = "rc=3 o=rel/t" ] || fail "relative: $out"
}

# triple_build <proj> <path>... -- a build command that writes each path as an
# executable under $PWD/crate/target, with cargo's .cargo-lock beside it and
# cargo's tag on the tree, so a cycle reads a target triple's profiles (0168).
triple_build() {
  local proj="$1" body l
  shift
  body='#!/usr/bin/env bash
case "${1:-}" in --help) exit 0 ;; esac
t="$PWD/crate/target"
mkdir -p "$t"
printf "Signature: 8a477f597d28d172789f06886806bc55\\n# This file is a cache directory tag created by cargo.\\n" > "$t/CACHEDIR.TAG"'
  for l in "$@"; do
    body+="
mkdir -p \"\$t/${l%/*}\" && : > \"\$t/${l%/*}/.cargo-lock\" && printf '#!/bin/sh\\nexit 0\\n' > \"\$t/$l\" && chmod +x \"\$t/$l\""
  done
  create_test_command "$proj" build "$body
exit 0" >/dev/null
}

@test "a release built only under a target triple, beside a host debug build, is read as built (0168)" {
  # Read from the tree's own release/ alone, --release --target <triple>
  # beside a plain cargo build came back WITHOUT ITS RELEASE ARTEFACTS, rc 1.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo aarch64-apple-darwin/release/demo
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "a debug build under a target triple whose release was lost fails as release artefacts lost (0168)" {
  # The triple's debug/ went unread, so the tree held no binary the check saw
  # and the cycle was INCONCLUSIVE at rc 0 over a lost release.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" aarch64-apple-darwin/debug/demo
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS."
  # The debug binary is the triple's, so the line does not say the tree's own
  # debug/ holds it.
  assert_output_contains "$proj/crate/target -- a debug/ has binaries, and neither its own release/ nor a target triple's has any"
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "a target triple's release kept through the clean is named, and the tree not compared (0168)" {
  # Only the tree's own release/ was asked whether it kept artefacts, so a
  # triple's release a previous cycle left in a tree the clean keeps was read
  # as this cycle's.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$proj/tools/target/aarch64-apple-darwin/release"
  : >"$proj/tools/target/aarch64-apple-darwin/release/.cargo-lock"
  : >"$proj/crate/Cargo.toml"
  cargo_tag "$proj/tools/target"
  printf '#!/bin/sh\nexit 0\n' >"$proj/tools/target/aarch64-apple-darwin/release/runme"
  chmod +x "$proj/tools/target/aarch64-apple-darwin/release/runme"
  releaseprofile_build "$proj"
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ "$status" -eq 1 ] || fail "want 1, got $status: $output"
  assert_output_contains "$proj/tools/target kept release artefacts through the clean, so they may be the last cycle's -- this tree's profiles were not compared."
  refute_output_contains "$proj/crate/target kept"
}

@test "a per-node target directory inside a tree is no target triple: its release does not stand for the tree's (0168)" {
  # A control: the directory carries .rustc_info.json, as a nested
  # CARGO_TARGET_DIR does, so it is a target dir of its own, not a profile of
  # this tree's.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo session-a/release/demo session-a/.rustc_info.json
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "$proj/crate/target -- debug/ has binaries, release/ has none"
}

@test "a build tree the check can search but not list is compared only where its own release settles it, and the summary lists that cause (0168, 0177)" {
  # Its triples cannot be listed, so with no binary in its own release/ a
  # triple's release may be what it cannot see: named, not read as lost.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo aarch64-apple-darwin/release/demo
  create_test_command "$proj" build "$(/usr/bin/sed '$d' "$proj/bin/.devbin/cmd/build")
chmod 111 \"\$t\"
exit 0" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ ! -r "$proj/crate/target" ] || readable=1
  chmod 755 "$proj/crate/target" || fail "the build left no target/ behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-0111 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot list $proj/crate/target -- a target triple's profiles in it cannot be read, and its own release/ holds no binary, so this tree's profiles were not compared"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  # The summary lists this cause too (issue 0177: it had no line for it, and a
  # tree that can be searched read as one that could not be).
  assert_output_line "or listed while its own release/ held no binary,"
  assert_output_line "so that tree was not examined (the lines above name each)."
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
}

@test "a directory in a build tree the check cannot search, which may be a triple's, is named, the tree not compared, and the summary lists that cause (0168, 0177)" {
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo aarch64-apple-darwin/release/demo
  create_test_command "$proj" build "$(/usr/bin/sed '$d' "$proj/bin/.devbin/cmd/build")
chmod 000 \"\$t/aarch64-apple-darwin\"
exit 0" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ ! -x "$proj/crate/target/aarch64-apple-darwin" ] || readable=1
  chmod 755 "$proj/crate/target/aarch64-apple-darwin" || fail "the build left no triple behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that search a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot search $proj/crate/target/aarch64-apple-darwin -- a target triple there would not be read, so this tree's profiles were not compared"
  assert_output_contains "ARTEFACT CHECK INCOMPLETE"
  assert_output_line "or a directory in it that may be a target triple's searched,"
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
}

@test "build_triple_dirs names a tree's target-triple directories by cargo's lock file, and neither a per-node directory, a link, the tree's own profiles nor one of another shape (0168)" {
  # tmp/release holding a test's executable and no lock file is no triple,
  # nor is a link to one. A triple built under
  # build.build-dir carries the lock file and no .fingerprint, so the lock file
  # is the marker. The tree's own release/ is never
  # a triple, even holding a release/ of its own. A per-node directory built
  # with CARGO_CACHE_RUSTC_INFO=0 carries no .rustc_info.json and IS read as a
  # triple: the declared limit, pinned so a change to it is seen.
  local proj out d; proj="$(rustproj)"
  mkdir -p "$proj/t/aarch64-apple-darwin/release" "$proj/t/x86_64-unknown-linux-gnu/debug" \
    "$proj/t/session-a/debug" "$proj/t/norustcinfo/debug" "$proj/t/doc" \
    "$proj/t/debug" "$proj/t/release/release" "$proj/t/tmp/release" "$proj/elsewhere/release"
  for d in aarch64-apple-darwin/release x86_64-unknown-linux-gnu/debug session-a/debug norustcinfo/debug debug release release/release; do
    : >"$proj/t/$d/.cargo-lock"
  done
  : >"$proj/elsewhere/release/.cargo-lock"
  : >"$proj/t/session-a/.rustc_info.json"
  printf '#!/bin/sh\nexit 0\n' >"$proj/t/tmp/release/testexe"
  chmod +x "$proj/t/tmp/release/testexe"
  ln -s ../elsewhere "$proj/t/linked"
  out="$(fixture_run "$proj" 'a=(); build_triple_dirs "$1/t" a; printf "%s|" "${a[@]}"' "$proj")"
  [ "$out" = "aarch64-apple-darwin|norustcinfo|x86_64-unknown-linux-gnu|" ] || fail "got: $out"
}

@test "real cargo: --release --target the host's triple beside a plain build passes the artefact check (0168)" {
  need_cargo
  local proj triple; proj="$(rustproj)"
  triple="$(rustc -vV 2>/dev/null | /usr/bin/sed -n 's/^host: //p')"
  [ -n "$triple" ] || skip "rustc names no host triple here: NOT checked"
  real_crate "$proj/crate"
  # The toolchain is proved before the cycle, so a cycle that fails is red,
  # never a skip.
  (cd "$proj/crate" && cargo build --offline -q --release --target "$triple" >/dev/null 2>&1) ||
    skip "cargo cannot build for $triple offline here: NOT checked"
  create_test_command "$proj" build "#!/usr/bin/env bash
case \"\${1:-}\" in --help) exit 0 ;; esac
cd \"\$PWD/crate\" && cargo build --offline -q && cargo build --offline -q --release --target $triple" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_success
  [ -e "$proj/crate/target/$triple/release/.cargo-lock" ] || fail "cargo wrote no lock file under $triple/release: $output"
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
}

@test "a profile under what may be a target triple that cannot be listed is named, the tree not compared, and the summary lists that cause (0168, 0177)" {
  # The release is the triple's only profile and cannot be searched, so not
  # even its lock file can be seen: still named, never read as lost.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo aarch64-apple-darwin/release/demo
  create_test_command "$proj" build "$(/usr/bin/sed '$d' "$proj/bin/.devbin/cmd/build")
chmod 000 \"\$t/aarch64-apple-darwin/release\"
exit 0" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ ! -x "$proj/crate/target/aarch64-apple-darwin/release" ] || readable=1
  chmod 755 "$proj/crate/target/aarch64-apple-darwin/release" || fail "the build left no triple release behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that search a mode-000 directory: the case was NOT checked"
  assert_failure
  assert_output_contains "cannot list $proj/crate/target/aarch64-apple-darwin/release -- this tree's profiles were not compared"
  # The summary lists every cause, whichever held, so this shows only that the
  # list names this one; the line above is what names the cause that held
  # (issue 0177: this asserted the clause for a directory that cannot be
  # searched, a cause it never had).
  assert_output_line "or a debug/ or release/ in it listed,"
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
}

@test "the tree's own release/ that cannot be listed is named once, as a profile and not as a triple (0168)" {
  local proj readable=0 n; proj="$(rustproj)"
  mkdir -p "$proj/crate"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo release/demo
  create_test_command "$proj" build "$(/usr/bin/sed '$d' "$proj/bin/.devbin/cmd/build")
chmod 000 \"\$t/release\"
exit 0" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  [ ! -x "$proj/crate/target/release" ] || readable=1
  chmod 755 "$proj/crate/target/release" || fail "the build left no release behind: $output"
  [ "$readable" = 0 ] || skip "running with permissions that search a mode-000 directory: the case was NOT checked"
  assert_failure
  n="$(printf '%s\n' "$output" | /usr/bin/grep -c "cannot list $proj/crate/target/release -- this tree's profiles were not compared")" || true
  [ "$n" = 1 ] || fail "named $n times: $output"
  refute_output_contains "cannot search $proj/crate/target/release"
}

@test "real cargo under build.build-dir: --release --target the host's triple beside a plain build passes, and a triple debug build alone fails as lost (0168)" {
  # cargo writes .fingerprint into the build-dir, so a triple read by it was
  # never seen: a false red, then INCONCLUSIVE at rc 0 over a lost release
  # (measured on cargo 1.99.0).
  need_cargo
  local proj triple; proj="$(rustproj)"
  triple="$(rustc -vV 2>/dev/null | /usr/bin/sed -n 's/^host: //p')"
  [ -n "$triple" ] || skip "rustc names no host triple here: NOT checked"
  real_crate "$proj/crate"
  (cd "$proj/crate" && CARGO_BUILD_BUILD_DIR="$proj/crate/bd" cargo build --offline -q --release --target "$triple" >/dev/null 2>&1) ||
    skip "cargo cannot build for $triple under a build-dir offline here: NOT checked"
  [ ! -e "$proj/crate/target/$triple/release/.fingerprint" ] || skip "this cargo writes .fingerprint into target/ under a build-dir: the case was NOT checked"
  create_test_command "$proj" build "#!/usr/bin/env bash
case \"\${1:-}\" in --help) exit 0 ;; esac
export CARGO_BUILD_BUILD_DIR=\"\$PWD/crate/bd\"
cd \"\$PWD/crate\" && cargo build --offline -q && cargo build --offline -q --release --target $triple" >/dev/null
  passing_test_cmd "$proj"
  run devbin_run "$proj" fullcycle --force
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "WITHOUT ITS RELEASE ARTEFACTS"
  create_test_command "$proj" build "#!/usr/bin/env bash
case \"\${1:-}\" in --help) exit 0 ;; esac
export CARGO_BUILD_BUILD_DIR=\"\$PWD/crate/bd\"
cd \"\$PWD/crate\" && cargo build --offline -q --target $triple" >/dev/null
  run devbin_run "$proj" fullcycle --force
  assert_failure
  assert_output_contains "THE BUILD TREE CAME BACK WITHOUT ITS RELEASE ARTEFACTS."
  refute_output_contains "ARTEFACT CHECK INCONCLUSIVE"
}

@test "what in a build tree is no profile of it is passed over: a link to a directory it cannot search, a per-node directory's release it cannot list, a file named release (0168)" {
  # Each would turn the cycle INCOMPLETE if read as a profile or a triple:
  # a link is no triple, a per-node directory is a
  # target dir of its own, and a profile is a directory.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/crate" "$BATS_TEST_TMPDIR/locked"
  : >"$proj/crate/Cargo.toml"
  triple_build "$proj" debug/demo release/demo session-a/release/demo session-a/.rustc_info.json notes/x
  create_test_command "$proj" build "$(/usr/bin/sed '$d' "$proj/bin/.devbin/cmd/build")
rm -f \"\$t/notes/x\" && printf 'not a profile\\n' > \"\$t/notes/release\"
ln -s \"$BATS_TEST_TMPDIR/locked\" \"\$t/linked\"
chmod 000 \"\$t/session-a/release\"
exit 0" >/dev/null
  passing_test_cmd "$proj"
  chmod 000 "$BATS_TEST_TMPDIR/locked"
  run devbin_run "$proj" fullcycle --force
  [ ! -x "$BATS_TEST_TMPDIR/locked" ] || readable=1
  chmod 755 "$BATS_TEST_TMPDIR/locked"
  [ ! -e "$proj/crate/target/session-a/release" ] || chmod 755 "$proj/crate/target/session-a/release"
  [ "$readable" = 0 ] || skip "running with permissions that search a mode-000 directory: the case was NOT checked"
  assert_success
  assert_output_contains "artefact check: 1 cargo build tree(s) examined"
  refute_output_contains "cannot list"
  refute_output_contains "cannot search"
  refute_output_contains "ARTEFACT CHECK INCOMPLETE"
}
