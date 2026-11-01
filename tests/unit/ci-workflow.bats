#!/usr/bin/env bats
#
# The CI workflow's gate lists, held against what `check` actually offers.
#
# Issues 0077 and 0293. `check critic` reads an Intent project, and CI runs on
# the public snapshot, which carries no intent/, so neither the Ubuntu job nor
# the macOS job runs `check all`: each runs every other gate BY NAME, but for
# lint, which its `test all` runs (0191). A list of names is how a gate added
# later goes missing from one runner with every run still green: nothing fails,
# the population just shrinks. These arms make that shrink a red suite on both
# runners instead.
#
set -euo pipefail

load "../lib/test_helper"

setup() {
  devbin_setup
  WORKFLOW="$DEVBIN_ORIGINAL_PWD/.github/workflows/tests.yml"
  RELEASE_WORKFLOW="$DEVBIN_ORIGINAL_PWD/.github/workflows/release.yml"
}

teardown() {
  devbin_teardown
}

# check_options_here -- the ACTIVE `check` options of this repository, one per
# line, from the same resolver `check all` iterates.
check_options_here() {
  # lib/helpers first: lib/resolve loads lib/builtins, which refuses to load
  # without it (issue 0066).
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  # shellcheck source=lib/resolve
  . "$DEVBIN_LIB_DIR/resolve"
  export DEVBIN_DIR="$DEVBIN_ORIGINAL_PWD/bin/.devbin"
  cfg_load "$DEVBIN_DIR/config.yaml"
  command_options check
}

# job_gates <linux|macos> -- the options that job's gate loop names, one per
# line, read from the line after its ci-<job>-gates marker.
job_gates() {
  local line
  line="$(sed -n "/# ci-$1-gates:/{n;p;}" "$WORKFLOW")"
  case "$line" in
    *"for opt in "*"; do") ;;
    *) return 1 ;;
  esac
  line="${line#*for opt in }"
  local -a opts
  read -ra opts <<<"${line%; do}"
  printf '%s\n' "${opts[@]}"
}

# job_block <job id> -- the workflow text from that job's key to the next job's.
job_block() {
  awk -v job="  $1:" '
    $0 == job { on = 1; print; next }
    on && /^  [a-z][a-z-]*:$/ { exit }
    on { print }
  ' "$WORKFLOW"
}

# --- 0108's extractors ------------------------------------------------------

# top_block <key> -- a top-level mapping's body, to the next top-level key.
top_block() {
  awk -v key="$1:" '
    $0 == key { on = 1; next }
    on && /^[a-z]/ { exit }
    on { print }
  ' "$WORKFLOW"
}

# job_gate <job id> -- the `if:` expression guarding that job, and empty when it
# carries none.
#
# ONE definition, because several arms ask this question and one of them
# asserts the answer is EMPTY. A second copy that broke -- a mistyped pattern, a
# change of indentation in the workflow -- would answer empty for every job, so
# the arms that need an answer would go red and the one asserting none would
# pass on exactly the defect it exists to catch (IN-AG-RED-CONTROL-001 and
# Highlander).
job_gate() { job_block "$1" | sed -n 's/^    if: //p'; }

# summary_required_expr -- test-summary's MACOS_REQUIRED, which must be the
# same expression as the job's own condition.
summary_required_expr() { job_block test-summary | sed -n 's/^      MACOS_REQUIRED: //p'; }

# summary_script -- the Test Summary step's shell, dedented to column 0.
#
# The script is the last thing in the file, so this takes everything after its
# `run: |` that is still indented under it. Every arm over it carries a floor,
# because an extractor returning nothing would make each of them compare two
# empty strings and pass.
summary_script() {
  local block
  block="$(job_block test-summary)" || return 1
  awk '
    /^        run: \|$/ { on = 1; next }
    on && $0 != "" && $0 !~ /^          / { exit }
    on { sub(/^          /, ""); print }
  ' <<<"$block"
}

# run_summary <linux> <macos> <shellcheck> <required> -- the REAL summary
# script, executed on one combination of job results.
#
# This is why 0108 moved the decision out of ${{ }} and into env: an inline
# expression can only ever be text-matched, and the case that matters -- a
# candidate whose macOS leg was skipped -- is the one a text match cannot catch.
run_summary() {
  local script tmp
  script="$(summary_script)"
  [ -n "$script" ] || fail "the summary script extractor returned nothing"
  tmp="$DEVBIN_TEST_TMPDIR/summary.sh"
  printf '%s\n' "$script" >"$tmp"
  LINUX="$1" MACOS="$2" SHELLCHECK="$3" MACOS_REQUIRED="$4" bash "$tmp"
}

@test "the Ubuntu and macOS gate lists are each exactly check's active options minus critic and lint (0293)" {
  # Each is left out for its own reason. critic: it reads an Intent project,
  # and the public snapshot CI runs on carries no intent/ (0293). lint: each
  # job's `test all` runs the suite's full-tree lint test, which runs the gate
  # `check lint` runs (0155), so the list running it too linted the tree twice
  # in a row (0191). Every other option is in each list.
  local want got job
  want="$(check_options_here | grep -vx -e critic -e lint | sort)"
  # A non-empty control: an empty resolver answer would make two empty lists
  # agree, and this arm would hold a list of nothing equal to nothing.
  [ -n "$want" ] || fail "command_options check answered nothing -- the resolver, not the workflow, is broken"
  for job in linux macos; do
    got="$(job_gates "$job" | sort)" || fail "no 'for opt in ...; do' line after the ci-$job-gates marker in $WORKFLOW"
    [ "$want" = "$got" ] || fail "the $job job runs [$(tr '\n' ' ' <<<"$got")] but check offers [$(tr '\n' ' ' <<<"$want")] besides critic and lint"
  done
}

@test "critic is still one of check's options, so leaving it out of CI still leaves something out" {
  # If critic ever left `check`, the lists above would still pass while the
  # workflow's comments described a gate that is gone.
  # CAPTURED, NOT PIPED: `| grep -q` under pipefail takes SIGPIPE when grep
  # matches before the writer is done, and the arm went red on a match (issue
  # 0031's class, met again writing this file).
  local opts
  opts="$(check_options_here)"
  grep -qx critic <<<"$opts"
}

@test "the macOS job does not run check all, which would refuse on the public snapshot with no intent/ (0293)" {
  local mac
  mac="$(job_block test-macos)"
  [ -n "$mac" ] || fail "no test-macos job in $WORKFLOW"
  ! grep -q 'bin/devbin check all' <<<"$mac" || fail "the macOS job runs check all, and critic refuses there"
}

@test "the Ubuntu and macOS jobs run test all, which is where lint runs on each (0191) (0293)" {
  # The gate lists above leave lint out because this step's suite runs it.
  # Without the step, nothing in the job would lint.
  local block job
  for job in test-linux test-macos; do
    block="$(job_block "$job")"
    [ -n "$block" ] || fail "no $job job in $WORKFLOW"
    # The whole line, so a step commented out, or given `|| true` or a filter,
    # does not count.
    grep -qxE '[[:space:]]+run: bin/devbin test all' <<<"$block" ||
      fail "the $job job no longer runs test all as a step of its own, so nothing in it lints"
  done
}

# step_lines <job id> <step name> -- that step's lines in that job, from its
# `- name:` to the next step's, whatever key opens it, so what is read is the
# step's own and never a neighbour's. The block is read whole first: an awk
# that stops early on a pipe would take its writer down with SIGPIPE.
step_lines() {
  local block
  block="$(job_block "$1")" || return 1
  awk -v want="      - name: $2" '
    $0 == want { on = 1; print; next }
    on && /^      - / { exit }
    on { print }
  ' <<<"$block"
}

# suite_jobs -- every job whose steps run devbin's suite, `bin/devbin test all`
# as a step's run line or a line of its script, read from the workflow and
# never listed by hand.
suite_jobs() {
  local job block ids
  ids="$(awk '/^jobs:/ { on = 1; next } on && /^[^ #]/ { exit } on && /^  [a-z][a-z0-9-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$WORKFLOW")" || return 1
  while IFS= read -r job; do
    [ -n "$job" ] || continue
    # Read whole, its status kept: a block that could not be read is no job
    # quietly left out of the set.
    block="$(job_block "$job")" || return 1
    if grep -qE '^[[:space:]]+(run: )?bin/devbin test all$' <<<"$block"; then
      printf '%s\n' "$job"
    fi
  done <<<"$ids"
  return 0
}

@test "every job that runs the suite runs it on every CPU its runner has, DEVBIN_TEST_JOBS all, and no line writes a number for it (WP04)" {
  local job jobs lines wslenv rc out
  jobs="$(suite_jobs)" || fail "the jobs of $WORKFLOW could not be read"
  [ -n "$jobs" ] || fail "no job in $WORKFLOW runs bin/devbin test all -- the suite's jobs could not be read"
  # WSL's crossing is held below, so the derived set must hold it.
  grep -qx test-wsl <<<"$jobs" || fail "the jobs read as running the suite do not include test-wsl: $jobs"
  for job in $jobs; do
    lines="$(step_lines "$job" "Run tests")"
    [ -n "$lines" ] || fail "the $job job has no Run tests step"
    grep -qxF '          DEVBIN_TEST_JOBS: all' <<<"$lines" ||
      fail "the $job job's Run tests step does not set DEVBIN_TEST_JOBS to all:
$lines"
  done
  # WSL sees only what WSLENV names.
  wslenv="$(job_block test-wsl | sed -n 's/^      WSLENV: //p')"
  [ -n "$wslenv" ] || fail "the test-wsl job carries no WSLENV"
  [[ ":$wslenv:" == *:DEVBIN_TEST_JOBS:* ]] || fail "WSLENV does not carry DEVBIN_TEST_JOBS into WSL: $wslenv"
  # NO NUMBER, IN ANY QUOTING. grep's status is read: 1 is no line found, and
  # an error is no pass.
  rc=0
  out="$(grep -nE "DEVBIN_TEST_JOBS[[:space:]]*[:=][[:space:]]*[\"']?[0-9]" "$WORKFLOW")" || rc=$?
  [ "$rc" -eq 1 ] || fail "grep found a number written for DEVBIN_TEST_JOBS, or could not read $WORKFLOW (status $rc): $out"
}

@test "the Ubuntu job does not run check all, which would refuse on a runner with no intent" {
  local linux
  linux="$(job_block test-linux)"
  [ -n "$linux" ] || fail "no test-linux job in $WORKFLOW"
  ! grep -q 'bin/devbin check all' <<<"$linux" || fail "the Ubuntu job runs check all, and critic refuses there"
}

# ============================================================================
# 0108 -- macOS on a candidate and on demand, and superseded runs cancelled
# ============================================================================
#
# WHAT THESE ARMS DO NOT COVER, said here so a green cannot read wider than it
# is: they hold what this workflow SAYS. What GitHub does with it rests on its
# documentation plus the first candidate pushed under this spec, and that
# observation does not exist yet. These arms catch the file drifting away from
# 0108. They say nothing about how a runner behaves.

@test "the workflow runs on a candidate branch and on demand, as well as on a push to main (0108) (0240)" {
  local on_block
  on_block="$(top_block on)"
  [ -n "$on_block" ] || fail "no on: block in $WORKFLOW"
  # main, and a release's candidate, which a cut pushes before anything is
  # tagged (0240).
  grep -qF "    branches: [main, 'candidate/**']" <<<"$on_block" || fail "on.push does not carry branches: [main, 'candidate/**']"
  grep -q '^  workflow_dispatch:$' <<<"$on_block" || fail "no workflow_dispatch trigger -- macOS could not be run on demand"
}

@test "no tag starts a run: on.push holds no tag filter, and no line of the workflow names the candidate-verdict job (ST0011 WP-04)" {
  # The tag is pushed only once every leg is green, the candidate's run among
  # them, on the commit it names, so a run of its own would give that verdict
  # again, and a job asking the candidate for it has nothing left to skip.
  # on.push is read and held present first, so a block that could not be read
  # is no absence of a filter.
  local on_block rc out
  on_block="$(top_block on)"
  [ -n "$on_block" ] || fail "no on: block in $WORKFLOW"
  grep -q '^  push:$' <<<"$on_block" || fail "could not read on.push in $WORKFLOW"
  # tags-ignore is a tag filter too: every tag it does not name starts a run.
  ! grep -qE '^    tags(-ignore)?:' <<<"$on_block" ||
    fail "on.push carries a tag filter, so a release tag starts a run:
$(grep -E '^    tags' <<<"$on_block")"
  # grep's status is read: 1 is no line found, and an error is no pass.
  rc=0
  out="$(grep -nF 'candidate-verdict' "$WORKFLOW")" || rc=$?
  [ "$rc" -eq 1 ] || fail "the workflow still names the candidate-verdict job, or could not be read (status $rc): $out"
}

@test "the macOS job is gated on a candidate branch and on demand, never on a push to main (0108) (0240)" {
  local cond
  cond="$(job_gate test-macos)"
  [ -n "$cond" ] || fail "the macOS job has no if: -- it runs on every push, which is the defect 0108 closed"
  [ "$cond" = "\${{ github.event_name == 'workflow_dispatch' || startsWith(github.ref, 'refs/heads/candidate/') }}" ] \
    || fail "the macOS condition is not the one 0108 and 0240 set: $cond"
}

@test "Test Summary requires macOS on exactly the expression the job runs it on (0108)" {
  local cond req
  cond="$(job_gate test-macos)"
  req="$(summary_required_expr)"
  [ -n "$cond" ] || fail "the macOS job has no if:"
  [ -n "$req" ] || fail "test-summary declares no MACOS_REQUIRED"
  # Equality alone would be satisfied by two copies of a WRONG expression, and
  # then macOS would skip on a candidate and the summary would accept the skip
  # -- a guard failing in the same direction as the bug it guards. The arm
  # above pins what the expression says; this one holds the second copy to it.
  [ "$cond" = "$req" ] || fail "the job runs macOS on [$cond] and the summary requires it on [$req]"
}

@test "a release's candidate runs the whole matrix: the push filter and the macOS, WSL and summary conditions name the branch release.publish.candidate's default makes (0240)" {
  # A cut pushes its candidate, under release.publish.url the snapshot, to the
  # candidate branch and tags nothing until CI is green there, so the
  # candidate's run is the release's whole matrix, and the tag starts none. The
  # prefix is read from the config's own default, so a default renamed without
  # the workflow, or the other way round, goes red.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  local tpl prefix on_block job cond
  tpl="$(_cfg_release_default publish.candidate)" || fail "the release schema has no publish.candidate"
  prefix="${tpl%%"{tag}"*}"
  [ -n "$prefix" ] && [ "$prefix" != "$tpl" ] || fail "publish.candidate's default [$tpl] opens with no fixed prefix before {tag}"
  on_block="$(top_block on)"
  [ -n "$on_block" ] || fail "no on: block in $WORKFLOW"
  grep -qF "'$prefix**'" <<<"$on_block" || fail "on.push does not run on '$prefix**', where a cut pushes its candidate"
  for job in test-macos test-wsl; do
    cond="$(job_gate "$job")"
    [[ "$cond" == *"startsWith(github.ref, 'refs/heads/$prefix')"* ]] || fail "$job does not run on a candidate: [$cond]"
  done
  [[ "$(summary_required_expr)" == *"startsWith(github.ref, 'refs/heads/$prefix')"* ]] ||
    fail "Test Summary does not require macOS on a candidate: [$(summary_required_expr)]"
  # And on a candidate a skipped macOS leg is no pass.
  _expect_summary fail " test-macos" success skipped success true
}

@test "the Ubuntu and ShellCheck jobs are ungated, so every push still runs them (0108)" {
  # THE OTHER HALF OF THE RULE -- "Ubuntu stays on push" -- and the likeliest
  # copy error once this file is the shape other projects start from: pasting
  # the macOS condition onto a Linux job. A push would then run nothing at all,
  # and Test Summary would pass on two skips it was never asked about. The next
  # reader of this file is every project that copies it.
  local job gate
  # THE EXTRACTOR IS EXERCISED BEFORE ITS SILENCE IS READ. Everything below
  # asserts an ABSENCE, so a job_gate that had stopped matching -- a mistyped
  # pattern, a change of indentation in the workflow -- would answer empty for
  # every job and pass this arm on a gated one. The macOS job is the positive
  # control: it is gated, and the same extractor must say so here
  # (IN-AG-RED-CONTROL-001: an absence asserted with no proof the probe can hit).
  [ -n "$(job_gate test-macos)" ] \
    || fail "job_gate found no condition on test-macos, so its silence on the jobs below means nothing"
  for job in test-linux shellcheck; do
    [ -n "$(job_block "$job")" ] || fail "no $job job in $WORKFLOW"
    gate="$(job_gate "$job")"
    [ -z "$gate" ] || fail "$job is gated on [$gate], so a push to main would not run it"
  done
}

@test "Test Summary reports a failed leg and stays quiet on a superseded run (0108)" {
  local gate
  gate="$(job_gate test-summary)"
  [ -n "$gate" ] || fail "test-summary has no if:, so a failed leg would skip the summary entirely"
  # Deliberately not always(). Cancelling superseded runs makes a cancelled run
  # ordinary, and always() puts a FAILED line in the log of every push that
  # overtook another -- a verdict red in normal operation, which is the thing
  # people stop reading. cancelled() asks about the RUN, so a cancelled LEG in a
  # live run still reports.
  [ "$gate" = "\${{ !cancelled() }}" ] || fail "test-summary's gate is not the one 0108 settled on: $gate"
}

@test "the summary's script carries no workflow interpolation, so the arms below run what GitHub runs (0108)" {
  local script
  script="$(summary_script)"
  [ -n "$script" ] || fail "the summary script extractor returned nothing"
  grep -q 'FAILED:' <<<"$script" || fail "the extracted script carries no verdict line -- the extractor stopped short"
  ! grep -qF '${{' <<<"$script" \
    || fail "the summary script interpolates workflow expressions, which the arms below cannot execute"
}

@test "Test Summary reads every job's result from env, one name per job (0108)" {
  local env_block script name block
  block="$(job_block test-summary)"
  env_block="$(awk '/^    env:$/ { on = 1; next } on && /^    [a-z]/ { exit } on { print }' <<<"$block")"
  [ -n "$env_block" ] || fail "test-summary declares no env block"
  script="$(summary_script)"
  [ -n "$script" ] || fail "the summary script extractor returned nothing"
  for name in LINUX MACOS SHELLCHECK MACOS_REQUIRED; do
    grep -q "^      $name: " <<<"$env_block" || fail "test-summary's env does not declare $name"
    # THE NAME MUST END WHERE THE NAME ENDS. `grep "\$MACOS"` is satisfied by
    # $MACOS_REQUIRED, so this loop reported all four names as read even with
    # every $MACOS replaced by something else -- measured by rewriting the reads
    # and watching the arm stay green. The trailing class is what stops one name
    # standing in for a longer one.
    grep -qE "[\$]$name([^A-Z0-9_]|$)" <<<"$script" || fail "the summary script never reads $name"
  done
}

# _expect_summary <pass|fail> <expected legs> <linux> <macos> <shellcheck> <required>
#
# THE VERDICT LINE IS ASSERTED, NOT ONLY THE STATUS, because a script that dies
# before it decides also exits non-zero, and a `fail` case would then take its
# own breakage as evidence. Measured while writing these arms: run against the
# old summary, whose script interpolated ${{ }} the shell cannot parse, every
# `fail` case passed on "bad substitution" -- a red arm failing for the wrong
# reason, which is the version nobody re-examines.
#
# AND THE LINE IS MATCHED WHOLE, NAMING THE LEGS. Asserting the "FAILED:" prefix
# alone holds that a refusal fired and nothing about what it says: with
# test-linux and shellcheck swapped in the extracted script, every refusal named
# the wrong job, and every case below stayed green. The step's whole claim is
# that a refusal names the inputs it refused on, and only the exact line holds
# that claim.
_expect_summary() {
  local want="$1" legs="$2"
  shift 2
  run run_summary "$@"
  case "$want" in
    pass)
      assert_success
      assert_output_contains "All required checks passed."
      ;;
    fail)
      assert_failure
      grep -qxF "FAILED:$legs" <<<"$output" \
        || fail "expected the verdict line [FAILED:$legs], got: $output"
      ;;
    *) fail "_expect_summary takes pass or fail, not $want" ;;
  esac
}

@test "the summary requires macOS exactly where the workflow asked for it (0108)" {
  # A push to main: the leg was not asked for, and its skip is the design.
  _expect_summary pass "" success skipped success false
  # A CANDIDATE WHOSE macOS LEG DID NOT RUN. This is the one false green 0108
  # could ship: a missing verdict wearing a pass, on the only run that carries
  # the bash 3.2 refusal proof and the critic gate.
  _expect_summary fail " test-macos" success skipped success true
  _expect_summary pass "" success success success true
  _expect_summary pass "" success success success false
}

@test "the summary refuses a job that never started, and any red leg, naming it (0108)" {
  # An EMPTY result is a job GitHub never started, which is what a billing
  # refusal looks like from here: every test job green and the summary never
  # started. It is not a skip and must never read as one.
  _expect_summary fail " test-macos" success "" success false
  _expect_summary fail " test-linux" "" skipped success false
  _expect_summary fail " shellcheck" success skipped failure false
  _expect_summary fail " test-linux" failure success success true
  _expect_summary fail " test-macos" success cancelled success true
  # AND THE SAME TWO WHERE macOS WAS NOT REQUIRED. Only `success` or `skipped`
  # is ever acceptable there, on any event. Added because a mutation widening
  # the accepted list to include `cancelled` survived every case above: each of
  # them asked about a candidate, where the requirement branch refuses anyway, so
  # nothing here had ever exercised the branch the mutation changed.
  _expect_summary fail " test-macos" success cancelled success false
  _expect_summary fail " test-macos" success failure success false
  # Two legs at once, so the verdict is held to naming BOTH rather than the
  # first it met.
  _expect_summary fail " test-linux shellcheck" failure skipped failure false
}

@test "the summary names a leg GitHub abandoned as NOT RUN, never as FAILED, and still refuses (0238)" {
  # `abandoned` is what `needs` gives a job no runner took: run 40373607694's
  # macOS leg on the v0.1.15 tag ran no step and printed FAILED, as a failing
  # test does.
  local notrun="NOT RUN: test-macos -- GitHub acquired no runner, so no step ran and no test failed; re-run the failed jobs once a runner is free"
  run run_summary success abandoned success true
  assert_failure
  grep -qxF "$notrun" <<<"$output" || fail "expected the line [$notrun], got: $output"
  refute_output_contains "FAILED:"
  # Where macOS was not asked for, an abandoned leg is still no pass.
  run run_summary success abandoned success false
  assert_failure
  grep -qxF "$notrun" <<<"$output" || fail "expected the line [$notrun], got: $output"
  refute_output_contains "FAILED:"
  # Beside a leg that ran and failed, each is named on its own line.
  run run_summary failure abandoned success true
  assert_failure
  grep -qxF "$notrun" <<<"$output" || fail "expected the line [$notrun], got: $output"
  grep -qxF "FAILED: test-linux" <<<"$output" || fail "expected the line [FAILED: test-linux], got: $output"
}

@test "the summary refuses a macOS requirement that is neither true nor false (0108)" {
  # The permissive branch is the one an unrecognised value must NOT reach: a
  # renamed env key, or an expression that failed to evaluate, would otherwise
  # be read as "macOS was not asked for" and a missing leg would pass on a
  # release's candidate. Both shapes are driven -- empty, and a word.
  run run_summary success skipped success ""
  assert_failure
  assert_output_contains "neither true nor false"
  run run_summary success skipped success maybe
  assert_failure
  assert_output_contains "neither true nor false"
}

# checkout_versions <workflow> -- the major version of every actions/checkout
# use in that file, one per line.
checkout_versions() {
  sed -n 's|^ *- uses: actions/checkout@v\([0-9][0-9]*\).*|\1|p' "$1"
}

@test "every actions/checkout runs on a Node 24 major, in both workflows (0110)" {
  local file v
  # THE FLOOR IS HELD HERE AND THE ADOPTED VERSION IS NOT, because the floor IS
  # the property. What matters is that an action runs on Node 24; v5 is the
  # first major that does, checked in each ref's own action.yml. Which major is
  # pinned is an incidental of the latest-deps rule -- a later bump to v8 is not
  # something this arm should have an opinion about, and the drift arm below
  # still catches a bump that reached one file and not the other.
  #
  # An earlier version of this comment justified it differently: that pinning
  # the newest would go red the day GitHub shipped the next major. That is
  # false -- nothing in this repository changes when they ship, so such an arm
  # reddens only when somebody edits this file, which is exactly when a test
  # should speak. The decision was right and the reason was wrong, which is the
  # combination that reads as settled and is not.
  # THE READ IS CHECKED PER FILE, AND SO IS PRESENCE. A command substitution
  # inside a here-document discards its status, so a sed that could not read
  # release.yml contributed nothing, and the aggregate floor that stood after the
  # loop was satisfied by tests.yml's three uses alone: "release.yml could not be
  # read" and "release.yml is clean" produced the same green (IN-SH-CODE-005,
  # and the same class the 0109 arm was written to avoid).
  local list per_file
  for file in "$WORKFLOW" "$RELEASE_WORKFLOW"; do
    list="$(checkout_versions "$file")" || fail "could not read $file to extract its actions/checkout uses"
    per_file=0
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      per_file=$((per_file + 1))
      [ "$v" -ge 5 ] || fail "$file uses actions/checkout@v$v, which runs on Node 20"
    done <<<"$list"
    [ "$per_file" -ge 1 ] || fail "no actions/checkout use found in $file at all"
  done
}

@test "both workflows check out at the same version, so the two cannot drift apart (0110)" {
  local tests_v release_v
  tests_v="$(checkout_versions "$WORKFLOW" | sort -u)"
  release_v="$(checkout_versions "$RELEASE_WORKFLOW" | sort -u)"
  [ -n "$tests_v" ] || fail "no actions/checkout found in $WORKFLOW"
  [ -n "$release_v" ] || fail "no actions/checkout found in $RELEASE_WORKFLOW"
  # One version per file, as well as the same one in both: a file carrying two
  # would satisfy an equality test on sorted sets while still disagreeing.
  [ "$(printf '%s\n' "$tests_v" | grep -c .)" = 1 ] || fail "tests.yml checks out at more than one version: $tests_v"
  [ "$tests_v" = "$release_v" ] || fail "tests.yml is at v$tests_v and release.yml at v$release_v"
}

# NAMED FOR WHAT IT ASSERTS, not for what the repository does. This arm read
# "a push that moves only a board starts no run" once, which is a claim about
# GitHub's behaviour that nothing here tests -- and which the repository
# contradicted while every assertion below stayed green. An arm's title is what
# a later reader carries away; it does not get to outrun the assertions under
# it.
@test "on.push ignores the board AND the canon store (0110)" {
  local on_block
  on_block="$(top_block on)"
  [ -n "$on_block" ] || fail "no on: block in $WORKFLOW"
  grep -q '^    paths-ignore:$' <<<"$on_block" || fail "on.push declares no paths-ignore, so a board-only push runs the suite"
  grep -q "^      - 'intent/whiteboard/\*\*'$" <<<"$on_block" \
    || fail "the board path is not under paths-ignore"
  # BOTH PATHS, OR THE FILTER DOES NOTHING. GitHub skips a push only when
  # EVERY changed path matches, and `intent wb` writes a canon event beside
  # the board view it renders -- so a board write touches both trees and the
  # board line ALONE cannot suppress any board write. Measured using tests.yml
  # run head SHAs as the real boundaries (which is GitHub's own two-dot diff):
  # the board line alone suppressed no push, and with this one beside it some
  # were. The workflow itself justifies the pair by what no job READS, because a
  # hit rate in a comment decays and does not transfer between projects.
  grep -q "^      - 'intent/\.canon/\*\*'$" <<<"$on_block" \
    || fail "the canon store is not under paths-ignore, so every board write still starts a run"
}

@test "superseded runs are cancelled, and the group separates events that share a ref (0108)" {
  local block group part
  block="$(top_block concurrency)"
  [ -n "$block" ] || fail "no concurrency: block -- a superseded run is never cancelled"
  group="$(sed -n 's/^  group: //p' <<<"$block")"
  [ -n "$group" ] || fail "the concurrency block names no group"
  # THE EVENT IS IN THE KEY because a push to main and a workflow_dispatch on
  # main share a ref: without it, a push would cancel an on-demand macOS run
  # after its ten-times minutes were spent, and a dispatch would cancel a push's.
  # EACH PART IS MATCHED TO ITS CLOSING BRACES, because `github.ref` on its own
  # is a prefix of `github.ref_name`, which names a branch or tag WITHOUT the
  # refs/heads or refs/tags that keeps a branch and a tag of the same name in
  # different groups. A substring test would accept the one form that loses the
  # distinction this arm's comment depends on.
  for part in github.workflow github.event_name github.ref; do
    case "$group" in *"$part }}"*) ;; *) fail "the concurrency group does not carry $part: $group" ;; esac
  done
  # The default already replaces a PENDING run in the group. This is what adds
  # the one that is RUNNING, so the line is the whole of the saving.
  grep -q '^  cancel-in-progress: true$' <<<"$block" \
    || fail "cancel-in-progress is not true, so a running superseded job is left to finish"
}

# ============================================================================
# ST0008 -- the WSL leg, on a candidate and on demand, blocking nothing
# ============================================================================
#
# As with 0108's arms, these hold what the workflow SAYS. Whether a Windows
# runner does it is the job's first run, read job by job (AC-6.3).

@test "the WSL job runs on exactly the macOS leg's expression (ST0008)" {
  local wsl mac
  wsl="$(job_gate test-wsl)"
  mac="$(job_gate test-macos)"
  [ -n "$mac" ] || fail "the macOS job has no if:, so there is nothing to hold the WSL job to"
  [ -n "$wsl" ] || fail "the WSL job has no if: -- it runs on every push, at twice Linux's minutes"
  [ "$wsl" = "$mac" ] || fail "the WSL job runs on [$wsl] and the macOS job on [$mac]"
}

@test "Test Summary does not need the WSL job, so it blocks nothing (ST0008)" {
  local needs
  needs="$(job_block test-summary | sed -n 's/^    needs: //p')"
  # The positive control: the line is read, and names the jobs that do block.
  case "$needs" in *test-linux*) ;; *) fail "could not read Test Summary's needs, or it no longer needs test-linux: [$needs]" ;; esac
  case "$needs" in *test-wsl*) fail "Test Summary needs test-wsl, so a red WSL run would block a release: [$needs]" ;; esac
}

@test "the WSL job's name carries the version it asked for, and the kernel is asserted to agree (ST0008)" {
  local wsl
  wsl="$(job_block test-wsl)"
  [ -n "$wsl" ] || fail "no test-wsl job in $WORKFLOW"
  # shellcheck disable=SC2016
  {
    grep -qF 'name: Test in WSL ${{ matrix.wsl }}' <<<"$wsl" || fail "the WSL job's name does not carry the matrix's WSL version"
    grep -qF 'wsl-version: ${{ matrix.wsl }}' <<<"$wsl" || fail "setup-wsl is not asked for the version the name carries"
    grep -qF 'WSL_WANT: ${{ matrix.wsl }}' <<<"$wsl" || fail "the version the name carries does not reach the assertion step"
    grep -qF 'if [ "$got" != "$WSL_WANT" ]; then' <<<"$wsl" || fail "no step compares the kernel's WSL version with the one asked for"
  }
}

@test "inside WSL the job clones into WSL's filesystem, then runs test all and the smoke list (ST0008)" {
  local wsl
  wsl="$(job_block test-wsl)"
  [ -n "$wsl" ] || fail "no test-wsl job in $WORKFLOW"
  # shellcheck disable=SC2016
  {
    grep -qF 'git clone -q "$GITHUB_WORKSPACE" "$HOME/devbin"' <<<"$wsl" || fail "the job does not clone into WSL's own filesystem"
    grep -qxE '[[:space:]]+bin/devbin test all' <<<"$wsl" || fail "the job does not run test all inside WSL"
    grep -qF '.github/wsl-smoke.sh" "$HOME/devbin" "$HOME/smoke"' <<<"$wsl" || fail "the job does not run the smoke list"
  }
  # Every step that runs a script runs it inside WSL: a `run:` under the
  # runner's own shell would test Windows' Git Bash or PowerShell instead.
  # Every `run:` is counted, whatever its form, and the count must not be
  # nothing, so two counts of nothing cannot agree. The steps the job must hold
  # are named above.
  # grep -c prints its count and exits 1 on a count of 0, which the check
  # below then reports.
  local runs shells
  runs="$(grep -cE '^[[:space:]]+run:' <<<"$wsl")" || true
  shells="$(grep -cxE '[[:space:]]+shell: wsl-bash( -u root)? \{0\}' <<<"$wsl")" || true
  [ "$runs" -gt 0 ] || fail "found no run: step in the WSL job; the extractor or the job has lost its steps"
  [ "$runs" = "$shells" ] || fail "the WSL job has $runs run: step(s) and $shells inside WSL"
}

@test "the WSL job installs Intent from a pinned tag and sha256, before the smoke list (ST0008 AC-6.5)" {
  local wsl install smoke step tag
  wsl="$(job_block test-wsl)"
  [ -n "$wsl" ] || fail "no test-wsl job in $WORKFLOW"
  # grep exits 1 on no match; an empty line number is reported just below.
  install="$(grep -n '^      - name: Install Intent$' <<<"$wsl" | cut -d: -f1)" || true
  smoke="$(grep -n '^      - name: Run the smoke list$' <<<"$wsl" | cut -d: -f1)" || true
  [ -n "$smoke" ] || fail "the WSL job has no smoke-list step to install Intent before"
  [ -n "$install" ] || fail "the WSL job does not install Intent, so the smoke list asserts the critic gate's refusal rather than its run"
  [ "$install" -lt "$smoke" ] || fail "Intent is installed at line $install of the job, after the smoke list at line $smoke"
  # The install step alone, so a pin elsewhere in the job cannot stand in.
  step="$(sed -n "${install},$((smoke - 1))p" <<<"$wsl")"
  # A TAG, NEVER latest: the run is read against the Intent it names.
  tag="$(sed -n 's/^          INTENT_TAG: //p' <<<"$step")"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "INTENT_TAG is not a pinned release tag: [$tag]"
  grep -qE '^          INTENT_SHA256: [0-9a-f]{64}$' <<<"$step" || fail "the asset's sha256 is not pinned"
  grep -qE '^      WSLENV: .*:INTENT_TAG:INTENT_ASSET:INTENT_SHA256(:|$)' <<<"$wsl" || fail "WSLENV does not carry the Intent pins into WSL"
  # shellcheck disable=SC2016
  {
    grep -qF 'releases/download/$INTENT_TAG/$INTENT_ASSET"' <<<"$step" || fail "the download is not built from the pinned tag"
    # The comparison, and the exit its mismatch takes, within the next lines.
    # Captured, not piped into grep -q (0031's class, contract.bats AC-7.1).
    # grep exits 1 on no match; the empty value then fails the check below.
    local after
    after="$(grep -A2 -F 'if [ "$got" != "$INTENT_SHA256" ]; then' <<<"$step")" || true
    grep -qxE '[[:space:]]+exit 1' <<<"$after" || fail "a sha256 mismatch does not fail the step"
  }
}

@test "the WSL job's steps run as dev, set in its one setup-wsl call, and root only where a step says so (ST0008 AC-6.3)" {
  # The first run (39039832569) ran every step as root: a second setup-wsl
  # call carried wsl-shell-user, and a second call does not rewrite the
  # wrapper the first one wrote. Arms failed on files root can read.
  local wsl calls first setup sudoers root_steps refuse tests after
  wsl="$(job_block test-wsl)"
  [ -n "$wsl" ] || fail "no test-wsl job in $WORKFLOW"
  # Every grep below exits 1 on no match; each result is checked after it.
  # A call counts whether `uses:` opens its step or follows a `name:`.
  calls="$(grep -cE '^[[:space:]]+(- )?uses: Vampire/setup-wsl@' <<<"$wsl")" || true
  [ "$calls" = 1 ] || fail "the WSL job calls setup-wsl $calls time(s); a second call does not move the wrapper's user"
  # The user is read inside that one call's step, to the next step.
  first="$(grep -nE '^[[:space:]]+(- )?uses: Vampire/setup-wsl@' <<<"$wsl" | cut -d: -f1)" || true
  setup="$(awk -v from="$first" 'NR == from { print; next } NR > from && /^      - / { exit } NR > from { print }' <<<"$wsl")"
  grep -qxE '[[:space:]]+wsl-shell-user: dev' <<<"$setup" || fail "the setup-wsl call is not given wsl-shell-user: dev, so every step runs as root"
  # Root in exactly one step, and that step is the sudoers one.
  root_steps="$(grep -cxE '[[:space:]]+shell: wsl-bash -u root \{0\}' <<<"$wsl")" || true
  [ "$root_steps" = 1 ] || fail "the WSL job has $root_steps step(s) running as root; only the sudoers step should"
  sudoers="$(grep -A1 -xF '      - name: Let the non-root user sudo' <<<"$wsl")" || true
  grep -qxF '        shell: wsl-bash -u root {0}' <<<"$sudoers" || fail "the step running as root is not the sudoers step"
  # A root run is refused, with an exit, before the suite's step.
  # shellcheck disable=SC2016
  refuse="$(grep -nF 'if [ "$(id -u)" -eq 0 ]; then' <<<"$wsl" | cut -d: -f1)" || true
  tests="$(grep -nxF '      - name: Run tests' <<<"$wsl" | cut -d: -f1)" || true
  [ -n "$refuse" ] || fail "no step refuses a root run"
  [ -n "$tests" ] || fail "the WSL job has no Run tests step to refuse a root run before"
  [ "$refuse" -lt "$tests" ] || fail "the root refusal at line $refuse comes after the suite's step at line $tests"
  after="$(sed -n "$refuse,$((refuse + 3))p" <<<"$wsl")"
  grep -qxE '[[:space:]]+exit 1' <<<"$after" || fail "the root refusal does not exit"
}
