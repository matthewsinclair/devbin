#!/usr/bin/env bats
# ci-state.bats - the built-in ci-state (ST0011 WP-03): CI's verdict on one
# commit, read through gh, in the release core's own words, and devbin's own
# config naming it as its release.ci.query.
#
# The release core runs a query as `<query> <sha>`, the release tag in
# DEVBIN_RELEASE_TAG, and reads its first line as `<verdict>[TAB<detail>]`.
# `bin/devbin ci-state <sha>` reads the runs of release.ci.workflow (default
# tests.yml) on the sha through gh; with release.ci.summary declared a run's
# verdict is that job's, else the run's own conclusion. With no ref, a sha with
# no run of its own is read on the commit before it while every commit between
# changes only what that workflow's paths-ignore names (issue 0110).
#
# Each arm stands in a fixture project with devbin installed, a release: block
# naming the repository acme/demo and the built-in as its query, and a git
# history holding the workflow with a paths-ignore. A `gh` first on PATH parses
# each call as the command makes it, refuses any other, and answers from
# $DEVBIN_TEST_TMPDIR/runs.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - gh's own reading of the --json fields and the --jq programs: the stub
#     answers in the lines those programs print, so a program gh would read
#     differently is held only by a run against GitHub.

load "../lib/test_helper"

setup() {
  devbin_setup
  PROJ="$(mkproj demo </dev/null)"
  use_config 'summary: Test Summary'
  git init -q -b main "$PROJ"
  git -C "$PROJ" config user.name t
  git -C "$PROJ" config user.email t@t
  write_workflow tests.yml
  commit_path lib/x >/dev/null
  stub_gh
}

teardown() { devbin_teardown; }

# use_config [<line>...] -- PROJ's config: the repository acme/demo, the
# built-in as its ci.query, and each <line> under release.ci. With NO_REPO
# set, release.repo is left out; REMOTES, words, is declared as release.remotes.
use_config() {
  local l
  {
    printf '%s\n' 'project:' '  name: demo' 'release:'
    [ -n "${NO_REPO:-}" ] || printf '%s\n' '  repo: acme/demo'
    if [ -n "${REMOTES:-}" ]; then
      printf '%s\n' '  remotes:'
      for l in $REMOTES; do printf '    - %s\n' "$l"; done
    fi
    printf '%s\n' '  ci:' '    query: bin/devbin ci-state'
    for l in "$@"; do printf '    %s\n' "$l"; done
  } >"$PROJ/bin/.devbin/config.yaml"
}

# write_workflow <file> -- a workflow at .github/workflows/<file> whose pushes
# ignore the coordination trees, as devbin's own does.
write_workflow() {
  mkdir -p "$PROJ/.github/workflows"
  printf '%s\n' 'on:' '  push:' '    branches: [main]' '    paths-ignore:' \
    "      - 'intent/whiteboard/**'" "      - 'intent/.canon/**'" '  workflow_dispatch:' \
    >"$PROJ/.github/workflows/$1"
}

# commit_path <path> -- a commit in PROJ changing <path> alone, the first one
# taking every file there is; prints its sha.
commit_path() {
  mkdir -p "$PROJ/$(dirname "$1")"
  printf '%s\n' "$RANDOM$RANDOM" >>"$PROJ/$1"
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m "change $1"
  git -C "$PROJ" rev-parse HEAD
}

# run_on <sha> <headBranch> <status> <conclusion> <id> [<summary-status>
# <summary-conclusion>] -- a run gh lists, its Test Summary job at the run's
# own status and conclusion unless given, and none when given as `absent`; a
# conclusion of - is none yet.
run_on() {
  printf '%s %s %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" "${6:-$3}" "${7:-$4}" >>"$DEVBIN_TEST_TMPDIR/runs"
}

# stub_gh -- a gh that takes `run list` with exactly --repo, --workflow,
# --commit, --limit, --json and --jq, and `run view <id>` with exactly --repo,
# --json jobs and --jq, each flag once and in any order, the id anywhere among
# them as gh takes it, and refuses anything else with exit 2. The workflow must be
# $WANT_WORKFLOW, default tests.yml. It prints as the command's --jq programs
# print: for a list each run on the sha, id, headBranch, status and
# conclusion; for a view each job's name, status and conclusion, a job named
# "Test on Ubuntu" at failure first and then the Test Summary job, which a run
# given `absent` lacks; tab-separated, a conclusion of - given as the empty one
# gh gives a job still going. A run given the head `null` stands for a run
# whose head branch GitHub holds as null, and is listed as gh's @tsv writes it:
# as `-` when the --jq program maps a null head to "-", and as an empty field
# when it does not. It records each call in gh.calls. GH_FAIL makes a list fail
# as gh does, and GH_VIEW_FAIL a view, words on stderr; FULL_PAGE makes a list
# answer with as many green runs as --limit asks for; NO_JOBS, a run's id, makes
# a view of that run list no job at all, and JOBS_GREEN, a run's id, lists that
# run's "Test on Ubuntu" at success.
stub_gh() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'runs=%q\ncalls=%q\n' "$DEVBIN_TEST_TMPDIR/runs" "$DEVBIN_TEST_TMPDIR/gh.calls"
    cat <<'SH'
printf '%s\n' "$*" >>"$calls"
verb="${1:-} ${2:-}"
case "$verb" in
  "run list") [ -z "${GH_FAIL:-}" ] || { echo "$GH_FAIL" >&2; exit 1; } ;;
  "run view") [ -z "${GH_VIEW_FAIL:-}" ] || { echo "$GH_VIEW_FAIL" >&2; exit 1; } ;;
  *) echo "stub gh: not run list or run view: $*" >&2; exit 2 ;;
esac
shift 2
view="" repo="" wf="" sha="" json="" jq="" limit=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ -z "$repo" ] && [ -n "${2:-}" ] || exit 2; repo="$2"; shift 2 ;;
    --workflow) [ -z "$wf" ] && [ -n "${2:-}" ] || exit 2; wf="$2"; shift 2 ;;
    --commit) [ -z "$sha" ] && [ -n "${2:-}" ] || exit 2; sha="$2"; shift 2 ;;
    --limit) [ -z "$limit" ] && [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || exit 2; limit="$2"; shift 2 ;;
    --json) [ -z "$json" ] && [ -n "${2:-}" ] || exit 2; json="$2"; shift 2 ;;
    --jq) [ -z "$jq" ] && [ -n "${2:-}" ] || exit 2; jq="$2"; shift 2 ;;
    -*) echo "stub gh: unknown flag $1" >&2; exit 2 ;;
    *)
      [ "$verb" = "run view" ] && [ -z "$view" ] || { echo "stub gh: unexpected argument $1" >&2; exit 2; }
      view="$1"
      shift
      ;;
  esac
done
[ -n "$repo" ] && [ -n "$json" ] && [ -n "$jq" ] || { echo "stub gh: a flag is missing" >&2; exit 2; }
if [ "$verb" = "run view" ]; then
  [ -n "$view" ] && [ "$json" = jobs ] && [ -z "$wf" ] && [ -z "$sha" ] && [ -z "$limit" ] || { echo "stub gh: not a run view" >&2; exit 2; }
else
  [ "$wf" = "${WANT_WORKFLOW:-tests.yml}" ] && [ -n "$sha" ] && [ -n "$limit" ] || { echo "stub gh: asked about workflow '$wf', or with no limit" >&2; exit 2; }
  if [ -n "${FULL_PAGE:-}" ]; then
    i=0
    while [ "$i" -lt "$limit" ]; do
      i=$((i + 1))
      printf '%s\t%s\t%s\t%s\n' "$((900000 + i))" main completed success
    done
    exit 0
  fi
fi
case "$jq" in
  *'.headBranch // "-"'*) nullhead=- ;;
  *) nullhead="" ;;
esac
[ -f "$runs" ] || exit 0
while read -r s ref st con id sst scon; do
  [ "$ref" != null ] || ref="$nullhead"
  [ "$con" != - ] || con=""
  [ "$scon" != - ] || scon=""
  if [ -n "$view" ]; then
    if [ "$id" = "$view" ] && [ "${NO_JOBS:-}" != "$id" ]; then
      ub=failure
      [ "${JOBS_GREEN:-}" != "$id" ] || ub=success
      printf '%s\t%s\t%s\n' "Test on Ubuntu" completed "$ub"
      [ "$sst" = absent ] || printf '%s\t%s\t%s\n' "Test Summary" "$sst" "$scon"
    fi
  else
    [ "$s" = "$sha" ] && printf '%s\t%s\t%s\t%s\n' "$id" "$ref" "$st" "$con"
  fi
done <"$runs"
exit 0
SH
  } >"$DEVBIN_TEST_TMPDIR/stubs/gh"
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/gh"
}

# ask <sha> [<ref>] -- the built-in, as the core runs it, from PROJ, with the
# stub gh first on PATH and <ref> in DEVBIN_RELEASE_TAG.
ask() {
  local ref="${2:-}"
  run bash -c 'cd "$1" && shift && exec "$@" </dev/null' _ "$PROJ" \
    env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" ${ref:+DEVBIN_RELEASE_TAG="$ref"} ./bin/devbin ci-state "$1"
}

# calls -- every call the stub gh recorded, for a failure message.
calls() { cat "$DEVBIN_TEST_TMPDIR/gh.calls" 2>/dev/null || printf '(no call)'; }

@test "a green run on the sha is green, naming the run, and gh is asked about release.repo's repository, the sha and tests.yml (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 101
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 101')" ] || fail "answered: $output"
  grep -qF -- "--repo acme/demo" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about acme/demo: $(calls)"
  grep -qF -- "--commit $sha" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about $sha: $(calls)"
  grep -qF -- "--workflow tests.yml" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about tests.yml: $(calls)"
}

@test "a failed run beside a green one on the sha is failed, naming the failed run and its failed jobs (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 102
  run_on "$sha" main completed failure 103
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 103 (Test Summary: failure; failed jobs: Test on Ubuntu, Test Summary)')" ] || fail "answered: $output"
}

@test "a run still going is pending, and a cancelled run alone is failed (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main in_progress - 104
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'pending\trun 104 (Test Summary: in_progress)')" ] || fail "answered: $output"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  run_on "$sha" main completed cancelled 105
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 105 (Test Summary: cancelled; failed jobs: Test on Ubuntu, Test Summary)')" ] || fail "answered: $output"
}

@test "with release.ci.summary, a run's verdict is that job's, found by its name: a red job the summary does not wait for leaves the run green (WP03)" {
  # The stub lists a red "Test on Ubuntu" job before the summary, so a reader
  # taking the first job, or the run's own conclusion, reads failed.
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" v9.9.9 completed failure 112 completed success
  ask "$sha" v9.9.9
  assert_success
  [ "$output" = "$(printf 'green\trun 112')" ] || fail "answered: $output"
  # The control for the arm below that holds no view is made: here one is.
  grep -q '^run view' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "the summary's job list was never asked for: $(calls)"
}

@test "with release.ci.summary, a finished run with no such job is failed, and a job list gh cannot give is unknown (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 113 absent
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 113 (no Test Summary job; failed jobs: Test on Ubuntu)')" ] || fail "answered: $output"
  GH_VIEW_FAIL="HTTP 404: Not Found" ask "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\tgh run view failed for %s: HTTP 404: Not Found' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a red summary is failed, naming the run and the summary, as 0.1.14's run was (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" v0.1.14 completed failure 40121933255 completed failure
  ask "$sha" v0.1.14
  [ "$output" = "$(printf 'failed\trun 40121933255 (Test Summary: failure; failed jobs: Test on Ubuntu, Test Summary)')" ] || fail "answered: $output"
}

@test "a skipped summary is not green, and a summary still going is pending though the run's other jobs are done (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 114 completed skipped
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 114 (Test Summary: skipped; failed jobs: Test on Ubuntu)')" ] || fail "answered: $output"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  run_on "$sha" main in_progress - 115 queued -
  ask "$sha"
  [ "$output" = "$(printf 'pending\trun 115 (Test Summary: queued)')" ] || fail "answered: $output"
}

@test "with no release.ci.summary, the run's own conclusion is its verdict, and a run's jobs are asked for only to name a failed one's (WP03)" {
  use_config
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 117 completed failure
  ask "$sha"
  [ "$output" = "$(printf 'green\trun 117')" ] || fail "answered: $output"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  run_on "$sha" main in_progress - 118
  ask "$sha"
  [ "$output" = "$(printf 'pending\trun 118 (in_progress)')" ] || fail "answered: $output"
  ! grep -q '^run view' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "a green or pending run's jobs were asked for with no summary declared: $(calls)"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  # The summary in the runs is green and the run red: the run decides, and its
  # red job is named.
  run_on "$sha" main completed failure 116 completed success
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 116 (failure; failed jobs: Test on Ubuntu)')" ] || fail "answered: $output"
  grep -qE '^run view( .*)? 116( |$)' "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "the failed run's jobs were never asked for: $(calls)"
}

@test "a failed run whose jobs list none says no job ran, and one whose jobs gh cannot give stays failed, saying so (WP03, AC-3.1)" {
  use_config
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed failure 120
  NO_JOBS=120 ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 120 (failure; no job ran)')" ] || fail "answered: $output"
  GH_VIEW_FAIL="HTTP 502: Bad Gateway" ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 120 (failure; its jobs could not be read: HTTP 502: Bad Gateway)')" ] || fail "answered: $output"
}

@test "release.ci.workflow names the workflow whose runs are read, and whose paths-ignore the walk reads (WP03)" {
  use_config 'workflow: ci.yml' 'summary: Test Summary'
  rm "$PROJ/.github/workflows/tests.yml"
  write_workflow ci.yml
  code="$(commit_path lib/y)"
  run_on "$code" main completed success 119
  sha="$(commit_path intent/whiteboard/node/board.json)"
  WANT_WORKFLOW=ci.yml ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 119, on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which ci.yml ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output -- calls: $(calls)"
  grep -qF -- "--workflow ci.yml" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about ci.yml: $(calls)"
}

@test "a commit with no run that changes what CI reads is none, naming it (WP03)" {
  sha="$(commit_path lib/y)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "with no ref, a sha with no run is read on the commit before it, through commits that change only paths-ignore's paths (WP03)" {
  code="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$code" main completed success 106
  commit_path intent/whiteboard/node/board.json >/dev/null
  sha="$(commit_path intent/.canon/events/e.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 106, on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which tests.yml ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "with no ref, a run on a coordination-only commit is that commit's verdict, and the walk stops there (WP03)" {
  code="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$code" main completed success 107
  sha="$(commit_path intent/whiteboard/node/board.json)"
  run_on "$sha" main completed failure 108
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 108 (Test Summary: failure; failed jobs: Test on Ubuntu, Test Summary)')" ] || fail "answered: $output"
}

@test "with no ref, the walk stops at a commit that changes what CI reads, and with no run there it is none (WP03)" {
  commit_path lib/y >/dev/null
  sha="$(commit_path intent/whiteboard/node/wip.md)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s, nor on the commits before it to %s, the last that changes what the workflow reads' "${sha:0:12}" "$(git -C "$PROJ" rev-parse --short=12 HEAD~1)")" ] ||
    fail "answered: $output"
}

@test "with DEVBIN_RELEASE_TAG a tag, only that tag's runs count: a green run on main is none until the tag's own exists (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 109
  ask "$sha" v9.9.9
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run for v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
  run_on "$sha" v9.9.9 completed success 110
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'green\trun 110')" ] || fail "answered: $output"
}

@test "with DEVBIN_RELEASE_TAG a candidate branch, only that branch's runs count, not main's or the tag's (WP03)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 120
  run_on "$sha" v9.9.9 completed failure 121
  ask "$sha" candidate/v9.9.9
  [ "$output" = "$(printf 'none\tno tests.yml run for candidate/v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
  run_on "$sha" candidate/v9.9.9 completed success 122
  ask "$sha" candidate/v9.9.9
  [ "$output" = "$(printf 'green\trun 122')" ] || fail "answered: $output"
}

@test "a run whose head branch GitHub holds as null is counted with no ref, and is no ref's run with one (WP03b)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" null completed success 130
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 130')" ] || fail "answered: $output"
  ask "$sha" v9.9.9
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run for v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "with DEVBIN_RELEASE_TAG, a sha with no run is not read on the commit before it (WP03)" {
  code="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$code" v9.9.9 completed success 111
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'none\tno tests.yml run for v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a gh that fails is unknown, carrying gh's words, and with no gh at all it is unknown, saying so (WP03)" {
  local nogh
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  GH_FAIL="HTTP 401: Bad credentials" ask "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\tgh run list failed for %s: HTTP 401: Bad credentials' "${sha:0:12}")" ] || fail "answered: $output"
  nogh="$(path_without gh)" || fail "path_without could not hide gh, as its line above says"
  run bash -c 'cd "$1" && shift && exec "$@" </dev/null' _ "$PROJ" env PATH="$nogh" ./bin/devbin ci-state "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\tgh is not installed, so no run on %s can be read' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a paths-ignore entry that is not a directory's whole tree is unknown, naming it, rather than read as something else (WP03)" {
  printf '%s\n' 'on:' '  push:' '    paths-ignore:' "      - 'intent/whiteboard/**'" "      - 'docs/*.md'" >"$PROJ/.github/workflows/tests.yml"
  git -C "$PROJ" commit -q -am "ignore docs"
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry 'docs/*.md' is not a directory's whole tree (<dir>/**), which is all this query reads")" ] ||
    fail "answered: $output"
}

@test "with no release.repo, the repository is the one the remote a release pushes to first names, and with none to read it is unknown, naming release.repo (WP03)" {
  NO_REPO=1 use_config 'summary: Test Summary'
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 123
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\trelease.repo is not declared and there is no remote to read it from (no remotes: declared, no origin, not exactly one remote) -- declare release.repo: OWNER/NAME')" ] ||
    fail "answered: $output"
  git -C "$PROJ" remote add origin https://github.com/acme/other.git
  ask "$sha"
  [ "$output" = "$(printf 'green\trun 123')" ] || fail "answered: $output"
  grep -qF -- "--repo acme/other" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about origin's acme/other: $(calls)"
}

@test "with release.remotes declared, the repository is the one its first entry names, not origin's (WP03)" {
  NO_REPO=1 REMOTES="second origin" use_config 'summary: Test Summary'
  git -C "$PROJ" remote add origin https://github.com/acme/first.git
  git -C "$PROJ" remote add second https://github.com/acme/second.git
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed success 124
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 124')" ] || fail "answered: $output"
  grep -qF -- "--repo acme/second" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about the first declared remote's acme/second: $(calls)"
  ! grep -qF -- "--repo acme/first" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was asked about origin's acme/first: $(calls)"
}

@test "a sha that is not a full one, a branch name or a short sha, is a usage error at exit 1, naming it, and gh is asked nothing (WP03)" {
  local short
  short="$(git -C "$PROJ" rev-parse --short=12 HEAD)"
  for arg in HEAD "$short"; do
    run devbin_run "$PROJ" ci-state "$arg"
    assert_exit_code 1
    assert_output_contains "'$arg' is not a full commit sha"
  done
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.calls" ] || fail "gh was asked: $(calls)"
}

@test "a list of runs as long as the limit gh was asked for is unknown, naming the count, since the worst could be one left out (WP03)" {
  local n
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  FULL_PAGE=1 ask "$sha"
  assert_success
  n="$(sed -n 's/.*--limit \([0-9][0-9]*\).*/\1/p' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ -n "$n" ] || fail "gh was asked with no --limit: $(calls)"
  [[ "$n" != *$'\n'* ]] || fail "gh was asked for a list more than once: $(calls)"
  [ "$output" = "$(printf 'unknown\tgh lists %s runs of tests.yml on %s, as many as it was asked for, so the worst of them cannot be told' "$n" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "the walk reads the push trigger's paths-ignore as committed at the asked sha, not the working tree's copy (WP03)" {
  code="$(commit_path lib/y)"
  run_on "$code" main completed success 125
  sha="$(commit_path intent/whiteboard/node/board.json)"
  # The working tree's copy ignores nothing; the committed one ignores the board.
  printf '%s\n' 'on:' '  push:' '    branches: [main]' >"$PROJ/.github/workflows/tests.yml"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 125, on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which tests.yml ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "a pull_request trigger's paths-ignore is not the push's, so a push ignoring nothing walks back nowhere (WP03)" {
  printf '%s\n' 'on:' '  push:' '    branches: [main]' '  pull_request:' '    paths-ignore:' "      - 'intent/whiteboard/**'" >"$PROJ/.github/workflows/tests.yml"
  code="$(commit_path lib/y)"
  run_on "$code" main completed success 126
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a push paths-ignore written inline is unknown, naming it, and a comment inside a block list ends nothing (WP03)" {
  printf '%s\n' 'on:' '  push:' "    paths-ignore: ['intent/whiteboard/**']" >"$PROJ/.github/workflows/tests.yml"
  code="$(commit_path lib/y)"
  run_on "$code" main completed success 127
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's push paths-ignore is written inline, which this query does not read -- write it as a block list, one entry a line")" ] ||
    fail "answered: $output"
  printf '%s\n' 'on:' '  push:' '    paths-ignore:' "      - 'intent/whiteboard/**'" '      # the canon events beside the boards' '' "      - 'intent/.canon/**'" >"$PROJ/.github/workflows/tests.yml"
  code="$(commit_path lib/z)"
  run_on "$code" main completed success 128
  sha="$(commit_path intent/.canon/events/e.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 128, on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which tests.yml ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "the walk ends none at the first commit, saying so, and a shallow clone with no commit before the one it reached is unknown (WP03)" {
  local first shallow
  first="$(git -C "$PROJ" rev-parse HEAD)"
  ask "$first"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s, the first commit' "${first:0:12}")" ] || fail "answered: $output"
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s, nor on the commits before it to %s, the first commit' "${sha:0:12}" "${first:0:12}")" ] ||
    fail "answered: $output"
  shallow="$DEVBIN_TEST_TMPDIR/shallow"
  git -c maintenance.auto=false clone -q --depth 1 "file://$PROJ" "$shallow"
  [ "$(git -C "$shallow" rev-parse --is-shallow-repository)" = true ] || fail "the clone at $shallow is not shallow"
  run bash -c 'cd "$1" && shift && exec "$@" </dev/null' _ "$shallow" \
    env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" ./bin/devbin ci-state "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\tno tests.yml run on %s, and this shallow clone holds no commit before %s, where the walk back stopped' "${sha:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "a commit this repository does not hold is none, as a publish's snapshot is, and one whose tree holds no workflow is none, naming it (WP03)" {
  local absent=0123456789abcdef0123456789abcdef01234567
  ask "$absent"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s, which this repository does not hold, so no commit before it is read' "${absent:0:12}")" ] ||
    fail "answered: $output"
  git -C "$PROJ" rm -q .github/workflows/tests.yml
  git -C "$PROJ" commit -q -m "no workflow"
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno tests.yml run on %s, whose tree holds no .github/workflows/tests.yml' "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "no sha, or more than one argument, is a usage error at exit 1, and -h prints the usage at 0 (WP03)" {
  run devbin_run "$PROJ" ci-state
  assert_exit_code 1
  assert_output_contains "bin/devbin ci-state <sha>"
  run devbin_run "$PROJ" ci-state one two
  assert_exit_code 1
  assert_output_contains "bin/devbin ci-state <sha>"
  run devbin_run "$PROJ" ci-state -h
  assert_success
  assert_output_contains "bin/devbin ci-state <sha>"
}

@test "devbin's ci.query is the built-in, and its summary is the name its workflow gives its test-summary job (WP03)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  local wf want
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  cfg_validate
  [ "$(cfg_release_get ci.query)" = "bin/devbin ci-state" ] || fail "devbin's ci.query is not the built-in: $(cfg_release_get ci.query)"
  wf="$DEVBIN_HOME/.github/workflows/$(cfg_release_get ci.workflow)"
  [ -f "$wf" ] || fail "devbin's release.ci.workflow names $wf, which is no file"
  want="$(awk '/^  test-summary:/ { f = 1; next } f && /^    name:/ { sub(/^    name: */, ""); print; exit }' "$wf")"
  [ -n "$want" ] || fail "$wf has no test-summary job with a name"
  [ "$(cfg_release_get ci.summary)" = "$want" ] ||
    fail "devbin's release.ci.summary is '$(cfg_release_get ci.summary)', and $wf names its test-summary job '$want'"
}

@test "devbin publishes through CI on its candidate: publish.url the public repository, its cut to local alone, the built-in asked about release.repo (0240, WP03)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  cfg_validate
  # A cut asks this query about the snapshot on its candidate before anything
  # is public.
  [ "$(cfg_release_get publish.url)" = "https://github.com/$(cfg_release_get repo).git" ] ||
    fail "devbin's release.publish.url is not the https url of release.repo: $(cfg_release_get publish.url)"
  [ "$(cfg_release_list remotes)" = local ] || fail "devbin's cut does not push to local alone: $(cfg_release_list remotes)"
  [ "$(cfg_release_get ci.query)" = "bin/devbin ci-state" ] ||
    fail "devbin's ci.query is not the built-in, which reads release.repo: $(cfg_release_get ci.query)"
  [ -x "$DEVBIN_HOME/lib/cmd/ci-state" ] || fail "the built-in ci-state is not executable"
}

# THE TRIGGER (--fires, ST0011 WP-03, AC-3.1): whether a push of a branch starts
# the workflow, read from it as committed at the sha. The release core asks it
# about the candidate ref a cut will push, and refuses on anything but fires.

# fires <ref> <sha> [<path>...] -- the built-in's trigger read from PROJ, as the core runs
# it, the stub gh first on PATH so that any call to it is recorded.
fires() {
  run bash -c 'cd "$1" && shift && exec "$@" </dev/null' _ "$PROJ" \
    env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" ./bin/devbin ci-state --fires "$@"
}

# trigger <line>... -- PROJ's tests.yml holding the lines, committed; prints
# the commit's sha.
trigger() {
  printf '%s\n' "$@" >"$PROJ/.github/workflows/tests.yml"
  git -C "$PROJ" add -A
  git -C "$PROJ" -c maintenance.auto=false -c gc.auto=0 commit -q -m "the workflow"
  git -C "$PROJ" rev-parse HEAD
}

# fires_line <word> <sha> <reason> -- the line --fires prints about tests.yml.
fires_line() {
  printf '%s\t.github/workflows/tests.yml at %s: %s' "$1" "${2:0:12}" "$3"
}

# AT-3.10
@test "--fires answers fires when a push trigger's branches entry matches the ref, naming it and the premise its paths-ignore rests on, reads the workflow as committed at the sha, and asks gh nothing (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches: [main, 'candidate/**']" "    tags: ['v[0-9]*']" \
    '    paths-ignore:' "      - 'intent/whiteboard/**'" '  workflow_dispatch:')"
  # The working tree's copy, uncommitted, would answer quiet: it is not read.
  printf '%s\n' 'on:' '  push:' '    branches: [main]' >"$PROJ/.github/workflows/tests.yml"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry 'candidate/**' matches candidate/v1.2.3; its paths-ignore (intent/whiteboard/) is taken to leave the files the release commit changes, which were not given, outside it")" ] ||
    fail "answered: $output"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.calls" ] || fail "gh was asked: $(calls)"
}

# AT-3.10
@test "--fires answers fires for a push trigger that filters no branch, however on: is written (WP03, AC-3.1)" {
  local shape sha
  for shape in 'on: push' 'on: [push, pull_request]' $'on:\n  - push\n  - pull_request' \
    $'on:\n  push:\n  pull_request:\n    branches: [main]'; do
    sha="$(trigger "$shape")"
    fires candidate/v1.2.3 "$sha"
    assert_success
    [ "$output" = "$(fires_line fires "$sha" "its push trigger filters no branch")" ] ||
      fail "for the on: written as: $shape -- answered: $output"
  done
}

# AT-3.11
@test "--fires answers quiet, naming why, for branches nothing of which matches, no push trigger, a branches-ignore entry that matches, and tags alone (WP03, AC-3.1)" {
  # setup's workflow pushes main alone.
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(fires_line quiet "$sha" "its push branches (main) match no candidate/v1.2.3 -- add 'candidate/**' to them")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  workflow_dispatch:')"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "it has no push trigger, so no push starts it")" ] || fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches-ignore: ['candidate/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches-ignore entry 'candidate/**' matches candidate/v1.2.3")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    tags: ['v*']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push trigger filters tags alone, so no branch push starts it -- add 'candidate/**' as a branches entry")" ] ||
    fail "answered: $output"
}

# AT-3.10, AT-3.11
@test "--fires matches as GitHub does: * stays within a path segment, a ! entry excludes what an entry before it matched, and . is literal (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches: ['*']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches (*) match no candidate/v1.2.3 -- add 'candidate/**' to them")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/*']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry 'candidate/*' matches candidate/v1.2.3")" ] || fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**', '!candidate/v1.*']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches entry '!candidate/v1.*' excludes candidate/v1.2.3")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/v1.2.3']")"
  fires candidate/v1x2x3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches (candidate/v1.2.3) match no candidate/v1x2x3 -- add 'candidate/**' to them")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "--fires answers unknown, naming it, for what it does not read: a paths: filter, branches beside branches-ignore, a push written on one line, a paths-ignore entry that is no whole directory (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths:' "      - 'lib/**'")"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(fires_line unknown "$sha" "its push trigger filters by paths:, so whether a push of candidate/v1.2.3 starts it turns on the files the release commit changes, which were not given -- pass them, or drop paths: from the push trigger")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' '    branches: [main]' "    branches-ignore: ['wip/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line unknown "$sha" "its push trigger gives both branches and branches-ignore, which GitHub refuses")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push: {branches: [main]}')"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line unknown "$sha" "its push: is written on one line ({branches: [main]}), which this does not read")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths-ignore:' "      - '*.md'")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry '*.md' is not a directory's whole tree (<dir>/**), which is all this query reads")" ] ||
    fail "answered: $output"
}

# AT-3.12
@test "--fires answers missing for a workflow the tree at the sha does not hold, naming release.ci.workflow or its default (WP03, AC-3.1)" {
  git -C "$PROJ" rm -q .github/workflows/tests.yml
  git -C "$PROJ" -c maintenance.auto=false -c gc.auto=0 commit -q -m "no workflow"
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(printf 'missing\trelease.ci.workflow is not declared, so its default tests.yml is read, and the tree at %s holds no .github/workflows/tests.yml' "${sha:0:12}")" ] ||
    fail "answered: $output"
  use_config 'summary: Test Summary' 'workflow: ci.yml'
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(printf 'missing\trelease.ci.workflow names ci.yml, and the tree at %s holds no .github/workflows/ci.yml' "${sha:0:12}")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "--fires with a ref that is no branch name, a sha that is not a full one, or an argument missing is a usage error at exit 1, and gh is asked nothing (WP03, AC-3.1)" {
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  fires 'candidate/v1..2' "$sha"
  assert_exit_code 1
  assert_output_contains "'candidate/v1..2' is not a branch name git takes"
  fires candidate/v1.2.3 "${sha:0:12}"
  assert_exit_code 1
  assert_output_contains "'${sha:0:12}' is not a full commit sha, and --fires reads the workflow as committed there"
  run devbin_run "$PROJ" ci-state --fires candidate/v1.2.3
  assert_exit_code 1
  assert_output_contains "bin/devbin ci-state --fires <ref> <sha>"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.calls" ] || fail "gh was asked: $(calls)"
}

# AT-3.10
@test "devbin's own workflow fires on the candidate branch its release pushes (WP03, AC-3.1)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  local wf cand ref
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  cfg_validate
  wf="$(cfg_release_get ci.workflow)"
  cand="$(cfg_release_get publish.candidate)"
  ref="${cand//\{tag\}/v0.0.0}"
  cp "$DEVBIN_HOME/.github/workflows/$wf" "$PROJ/.github/workflows/tests.yml"
  git -C "$PROJ" add -A
  git -C "$PROJ" -c maintenance.auto=false -c gc.auto=0 commit -q -m "devbin's workflow"
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  fires "$ref" "$sha"
  assert_success
  [ "${output%%$'\t'*}" = fires ] || fail "devbin's $wf does not fire on $ref: $output"
}

# AT-3.14
@test "--fires reads the push trigger once, so a paths-ignore entry is read however the file spells it: CR line ends, a quoted or spaced on:, a quoted push: or paths-ignore: (WP03, AC-3.1)" {
  local spelled sha want
  for spelled in "on:|push:|paths-ignore:|" "on:|push:|paths-ignore:|cr" "'on':|push:|paths-ignore:|" "on :|push:|paths-ignore:|" \
    'on:|"push":|"paths-ignore":|' "on:|push:|paths-ignore :|"; do
    IFS='|' read -r on push pi cr <<<"$spelled"
    if [ -n "$cr" ]; then
      printf '%s\r\n' "$on" "  $push" "    branches: ['candidate/**']" "    $pi" "      - 'VERSION'" >"$PROJ/.github/workflows/tests.yml"
    else
      printf '%s\n' "$on" "  $push" "    branches: ['candidate/**']" "    $pi" "      - 'VERSION'" >"$PROJ/.github/workflows/tests.yml"
    fi
    git -C "$PROJ" add -A
    git -C "$PROJ" -c maintenance.auto=false -c gc.auto=0 commit -q -m "spelled $spelled"
    sha="$(git -C "$PROJ" rev-parse HEAD)"
    fires candidate/v1.2.3 "$sha"
    assert_success
    want="$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry 'VERSION' is not a directory's whole tree (<dir>/**), which is all this query reads")"
    [ "$output" = "$want" ] || fail "spelled $spelled -- answered: $output"
    fires candidate/v1.2.3 "$sha" VERSION
    [ "$output" = "$(fires_line quiet "$sha" "its push paths-ignore ignores every file the release commit changes (VERSION by 'VERSION'), so its push starts no run")" ] ||
      fail "spelled $spelled, given VERSION -- answered: $output"
  done
}

# AT-3.10, AT-3.11
@test "--fires reads **/ as any number of directories, none included, so an exclusion written with it excludes the ref (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches-ignore: ['**/candidate/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches-ignore entry '**/candidate/**' matches candidate/v1.2.3")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['**', '!**/candidate/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line quiet "$sha" "its push branches entry '!**/candidate/**' excludes candidate/v1.2.3")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['**/candidate/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry '**/candidate/**' matches candidate/v1.2.3")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "--fires answers unknown for a push trigger written with YAML it does not read: an anchor or a tag on an entry, an explicit key, a tab after a dash, an escape inside quotes (WP03, AC-3.1)" {
  local shape sha
  for shape in $'    branches-ignore:\n      - &cand \'candidate/**\'' $'    branches-ignore: [&cand \'candidate/**\']' \
    $'    branches:\n      - \'**\'\n      - !!str \'!candidate/**\'' $'    ? branches-ignore\n    : [\'candidate/**\']' \
    $'    branches-ignore:\n    -\t\'candidate/**\'' $'    branches-ignore:\n      - \'can\'\'t\''; do
    sha="$(trigger 'on:' '  push:' "$shape")"
    fires candidate/v1.2.3 "$sha"
    assert_success
    [ "${output%%$'\t'*}" = unknown ] || fail "for the push block: $shape -- answered: $output"
    assert_output_contains "does not read"
  done
}

# AT-3.10, AT-3.13
@test "--fires holds a [] to GitHub's rule, letters, digits and ascending ranges of them, and answers unknown for any other (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/v[0-9]*']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry 'candidate/v[0-9]*' matches candidate/v1.2.3")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/[z-a]*']")"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(fires_line unknown "$sha" "its push branches entry 'candidate/[z-a]*' is a pattern this does not read")" ] ||
    fail "answered: $output"
}

# AT-3.14
@test "--fires, given the files the release commit changes, answers quiet when paths-ignore ignores every one or paths matches none, naming the rule, and fires when one is left in (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths-ignore:' "      - '**.md'" "      - 'VERSION'")"
  fires candidate/v1.2.3 "$sha" VERSION CHANGELOG.md
  assert_success
  [ "$output" = "$(fires_line quiet "$sha" "its push paths-ignore ignores every file the release commit changes (VERSION by 'VERSION', CHANGELOG.md by '**.md'), so its push starts no run")" ] ||
    fail "answered: $output"
  fires candidate/v1.2.3 "$sha" VERSION CHANGELOG.md lib/x
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry 'candidate/**' matches candidate/v1.2.3; lib/x is outside its paths-ignore")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths:' "      - 'lib/**'")"
  fires candidate/v1.2.3 "$sha" VERSION CHANGELOG.md
  [ "$output" = "$(fires_line quiet "$sha" "its push paths (lib/**) match none of the files the release commit changes (VERSION, CHANGELOG.md), so its push starts no run")" ] ||
    fail "answered: $output"
  fires candidate/v1.2.3 "$sha" VERSION lib/x
  [ "$output" = "$(fires_line fires "$sha" "its push branches entry 'candidate/**' matches candidate/v1.2.3; its push paths match lib/x by 'lib/**'")" ] ||
    fail "answered: $output"
  # With no files given, a paths-ignore entry naming its directory by a pattern
  # is no whole directory the walk can read, and is unknown.
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths-ignore:' "      - '**/**'")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry '**/**' is not a directory's whole tree (<dir>/**), which is all this query reads")" ] ||
    fail "answered: $output"
  # A backslash is GitHub's escape, never part of a directory's name here.
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths-ignore:' '      - a\b/**')"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry 'a\\\\b/**' is not a directory's whole tree (<dir>/**), which is all this query reads")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "--fires answers unknown for a commit this repository does not hold, and for a declared ci.query that is not the built-in, naming it (WP03, AC-3.1)" {
  local absent=0123456789abcdef0123456789abcdef01234567
  fires candidate/v1.2.3 "$absent"
  assert_success
  [ "$output" = "$(printf 'unknown\tthis repository does not hold %s, so .github/workflows/tests.yml there cannot be read' "${absent:0:12}")" ] ||
    fail "answered: $output"
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  printf '%s\n' 'project:' '  name: demo' 'release:' '  repo: acme/demo' '  ci:' '    query: tools/ci-state' \
    >"$PROJ/bin/.devbin/config.yaml"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(printf "unknown\trelease.ci.query is 'tools/ci-state', not the built-in bin/devbin ci-state, so the workflow its runs come from is not release.ci.workflow, and no trigger is read")" ] ||
    fail "answered: $output"
}

@test "a failed run whose jobs ran and none failed says so, and with a summary declared each run's jobs are read once (WP03, AC-3.1)" {
  use_config
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$sha" main completed failure 121 completed success
  JOBS_GREEN=121 ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 121 (failure; no job failed)')" ] || fail "answered: $output"
  use_config 'summary: Test Summary'
  rm "$DEVBIN_TEST_TMPDIR/runs" "$DEVBIN_TEST_TMPDIR/gh.calls"
  run_on "$sha" main completed failure 122 completed failure
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 122 (Test Summary: failure; failed jobs: Test on Ubuntu, Test Summary)')" ] || fail "answered: $output"
  views="$(grep -c '^run view' "$DEVBIN_TEST_TMPDIR/gh.calls")" || views=0
  runs="$(grep -c . "$DEVBIN_TEST_TMPDIR/runs")"
  [ "$views" = "$runs" ] || fail "$views job lists were asked for $runs runs: $(calls)"
}

@test "with no ref, a failed verdict the walk reaches keeps its jobs inside its parenthesis, and the walk's clause follows it (WP03, AC-3.1)" {
  code="$(git -C "$PROJ" rev-parse HEAD)"
  run_on "$code" main completed failure 123
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'failed\trun 123 (Test Summary: failure; failed jobs: Test on Ubuntu, Test Summary), on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which tests.yml ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "the walk reads a paths-ignore past a branches list --fires does not read, and --fires answers unknown for that list (WP03, AC-3.1)" {
  # An anchored branches list, shared with pull_request: the walk needs only
  # paths-ignore, so it walks back green; --fires cannot read the list.
  wfc="$(trigger 'on:' '  push:' "    branches: &br [main, 'candidate/**']" '    paths-ignore:' \
    "      - 'intent/whiteboard/**'" '  pull_request:' '    branches: *br')"
  run_on "$wfc" main completed success 124
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 124, on %s: the commits after it to %s change only intent/whiteboard/, which tests.yml ignores' "${wfc:0:12}" "${sha:0:12}")" ] ||
    fail "the walk answered: $output -- calls: $(calls)"
  fires candidate/v1.2.3 "$sha"
  assert_success
  [ "$output" = "$(fires_line unknown "$sha" "its branches entry &br [main, 'candidate/**'] is written in a form this does not read")" ] ||
    fail "--fires answered: $output"
}

# AT-3.10, AT-3.13
@test "--fires reads an on: list written at on:'s own column, and answers unknown for a push filter key GitHub does not read there or one given twice (WP03, AC-3.1)" {
  sha="$(trigger 'on:' '- push' '- pull_request')"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line fires "$sha" "its push trigger filters no branch")" ] || fail "answered: $output"
  sha="$(trigger 'on:' '  push:' '    branchez: [main]')"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line unknown "$sha" "its push trigger holds branchez:, which is none of the filters GitHub reads there")" ] ||
    fail "answered: $output"
  sha="$(trigger 'on:' '  push:' '    branches: [main]' "    branches: ['candidate/**']")"
  fires candidate/v1.2.3 "$sha"
  [ "$output" = "$(fires_line unknown "$sha" "its push trigger gives branches twice")" ] || fail "answered: $output"
}

# AT-3.13
@test "--fires answers unknown when given more files than GitHub reads a push path filter against (WP03, AC-3.1)" {
  # GitHub reads a push's path filters against its first 300 changed files
  # alone (its documented limit), so past it which files decide is not known.
  local limit=300 i
  local -a files=()
  for ((i = 0; i <= limit; i++)); do files+=("d/f$i"); done
  sha="$(trigger 'on:' '  push:' "    branches: ['candidate/**']" '    paths-ignore:' "      - 'intent/whiteboard/**'")"
  fires candidate/v1.2.3 "$sha" "${files[@]}"
  assert_success
  [ "$output" = "$(fires_line unknown "$sha" "it is given ${#files[@]} files the release commit changes, and GitHub reads a push path filter against the first $limit alone, so which of them decide cannot be told")" ] ||
    fail "answered: $output"
}

# AT-3.13
@test "--fires refuses, as a usage error at exit 1, a path git would not name that way (WP03, AC-3.1)" {
  local p
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  for p in ./VERSION /VERSION a//b a/../b a/ ''; do
    fires candidate/v1.2.3 "$sha" "$p"
    assert_exit_code 1
    assert_output_contains "is not a file's path as git names it"
  done
}
