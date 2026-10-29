#!/usr/bin/env bats
# ci-state.bats - devbin's own ci.query, bin/.devbin/cmd/.lib/ci-state (issue
# 0223), and devbin's config turning ci.base on with it.
#
# The release core asks the query `<query> <sha>`, the release tag in
# DEVBIN_RELEASE_TAG at the ci step and nothing there at pre-flight, and reads
# its first line as `<verdict>[TAB<detail>]`. This query reads devbin's Tests
# workflow runs on the sha through gh. With no tag, a sha with no run of its own
# is read on the commit before it while every commit between changes only what
# that workflow's paths-ignore names: a push of coordination state starts no run
# (issue 0110), so the release commit's base is often such a commit.
#
# Each arm stands in a fixture repository holding a tests.yml with a
# paths-ignore, and puts a `gh` first on PATH that parses the call as the query
# makes it and answers from $DEVBIN_TEST_TMPDIR/runs.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - gh's own reading of the --json fields and the --jq program: the stub
#     answers in the lines that program prints, so a program gh would read
#     differently is held only by a cut run against GitHub.

load "../lib/test_helper"

setup() {
  devbin_setup
  QUERY="$DEVBIN_HOME/bin/.devbin/cmd/.lib/ci-state"
  REPO="$DEVBIN_TEST_TMPDIR/repo"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@t
  mkdir -p "$REPO/.github/workflows"
  cat >"$REPO/.github/workflows/tests.yml" <<'YAML'
on:
  push:
    branches: [main]
    paths-ignore:
      - 'intent/whiteboard/**'
      - 'intent/.canon/**'
  workflow_dispatch:
YAML
  commit_path lib/x
  stub_gh
}

teardown() { devbin_teardown; }

# commit_path <path> -- a commit in REPO changing <path> alone; prints its sha.
commit_path() {
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s\n' "$RANDOM$RANDOM" >>"$REPO/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "change $1"
  git -C "$REPO" rev-parse HEAD
}

# run_on <sha> <headBranch> <status> <conclusion> <id> [<summary-status>
# <summary-conclusion>] -- a Tests run gh lists, its Test Summary job at the
# run's own status and conclusion unless given, and none when given as
# `absent`; a conclusion of - is none yet.
run_on() {
  printf '%s %s %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" "${6:-$3}" "${7:-$4}" >>"$DEVBIN_TEST_TMPDIR/runs"
}

# stub_gh -- a gh that takes `run list` with exactly --repo, --workflow
# tests.yml, --commit <sha>, --json and --jq, and `run view <id>` with exactly
# --repo, --json jobs and --jq, each flag once, and refuses anything else with
# exit 2. It prints as the query's --jq programs print: for a list each run on
# the sha, id, headBranch, status and conclusion; for a view the Test Summary
# job's status and conclusion, or nothing for a run without one; tab-separated,
# a conclusion of - given as the empty one gh gives a job still going. It
# records each call in gh.calls. GH_FAIL makes a list fail as gh does, and
# GH_VIEW_FAIL a view, words on stderr.
stub_gh() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/gh" <<SH
#!/usr/bin/env bash
runs="$DEVBIN_TEST_TMPDIR/runs"
printf '%s\n' "\$*" >>"$DEVBIN_TEST_TMPDIR/gh.calls"
SH
  cat >>"$DEVBIN_TEST_TMPDIR/stubs/gh" <<'SH'
verb="${1:-} ${2:-}"
case "$verb" in
  "run list") [ -z "${GH_FAIL:-}" ] || { echo "$GH_FAIL" >&2; exit 1; } ;;
  "run view") [ -z "${GH_VIEW_FAIL:-}" ] || { echo "$GH_VIEW_FAIL" >&2; exit 1; } ;;
  *) echo "stub gh: not run list or run view: $*" >&2; exit 2 ;;
esac
shift 2
view=""
if [ "$verb" = "run view" ]; then view="${1:-}"; [ -n "$view" ] || exit 2; shift; fi
repo="" wf="" sha="" json="" jq=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ -z "$repo" ] && [ -n "${2:-}" ] || exit 2; repo="$2" ;;
    --workflow) [ -z "$view" ] && [ -z "$wf" ] && [ "${2:-}" = tests.yml ] || exit 2; wf="$2" ;;
    --commit) [ -z "$view" ] && [ -z "$sha" ] && [ -n "${2:-}" ] || exit 2; sha="$2" ;;
    --json) [ -z "$json" ] && [ -n "${2:-}" ] || exit 2; json="$2" ;;
    --jq) [ -z "$jq" ] && [ -n "${2:-}" ] || exit 2; jq="$2" ;;
    *) echo "stub gh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift 2
done
[ -n "$repo" ] && [ -n "$json" ] && [ -n "$jq" ] || { echo "stub gh: a flag is missing" >&2; exit 2; }
if [ -n "$view" ]; then
  [ "$json" = jobs ] || exit 2
else
  [ -n "$wf" ] && [ -n "$sha" ] || { echo "stub gh: a flag is missing" >&2; exit 2; }
fi
[ -f "$runs" ] || exit 0
while read -r s ref st con id sst scon; do
  [ "$con" != - ] || con=""
  [ "$scon" != - ] || scon=""
  if [ -n "$view" ]; then
    [ "$id" = "$view" ] && [ "$sst" != absent ] && printf '%s\t%s\n' "$sst" "$scon"
  else
    [ "$s" = "$sha" ] && printf '%s\t%s\t%s\t%s\n' "$id" "$ref" "$st" "$con"
  fi
done <"$runs"
exit 0
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/gh"
}

# ask <sha> [<tag>] -- the query, as the core runs it, from REPO.
ask() {
  local tag="${2:-}"
  run bash -c 'cd "$1" && shift && exec "$@"' _ "$REPO" env PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" ${tag:+DEVBIN_RELEASE_TAG="$tag"} "$QUERY" acme/demo "$1"
}

@test "a green run on the sha is green, naming the run, and gh is asked about that repository and sha" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main completed success 101
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 101')" ] || fail "answered: $output"
  grep -qF -- "--repo acme/demo" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about acme/demo: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  grep -qF -- "--commit $sha" "$DEVBIN_TEST_TMPDIR/gh.calls" || fail "gh was not asked about $sha: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "a failed run beside a green one on the sha is failed, naming the failed run" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main completed success 102
  run_on "$sha" main completed failure 103
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 103 (Test Summary: failure)')" ] || fail "answered: $output"
}

@test "a run still going is pending, and a cancelled run alone is failed" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main in_progress - 104
  ask "$sha"
  [ "$output" = "$(printf 'pending\trun 104 (Test Summary: in_progress)')" ] || fail "answered: $output"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  run_on "$sha" main completed cancelled 105
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 105 (Test Summary: cancelled)')" ] || fail "answered: $output"
}

@test "a run's verdict is its Test Summary job's: a red job Summary does not wait for leaves the run green" {
  # The WSL leg blocks nothing: Test Summary does not need it, and a red WSL
  # job turns the run's own conclusion red.
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" v9.9.9 completed failure 112 completed success
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'green\trun 112')" ] || fail "answered: $output"
}

@test "a finished run with no Test Summary job is failed, and a job list gh cannot give is unknown" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main completed success 113 absent
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 113 (no Test Summary job)')" ] || fail "answered: $output"
  GH_VIEW_FAIL="HTTP 404: Not Found" ask "$sha"
  [ "$output" = "$(printf 'unknown\tgh run view failed for %s: HTTP 404: Not Found' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a red Ubuntu job with a red summary is failed, naming the run and the summary (0.1.14's shape)" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" v0.1.14 completed failure 40121933255 completed failure
  ask "$sha" v0.1.14
  [ "$output" = "$(printf 'failed\trun 40121933255 (Test Summary: failure)')" ] || fail "answered: $output"
}

@test "a skipped summary is not green, and a summary still going is pending though the run's other jobs are done" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main completed success 114 completed skipped
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 114 (Test Summary: skipped)')" ] || fail "answered: $output"
  rm "$DEVBIN_TEST_TMPDIR/runs"
  run_on "$sha" main in_progress - 115 queued -
  ask "$sha"
  [ "$output" = "$(printf 'pending\trun 115 (Test Summary: queued)')" ] || fail "answered: $output"
}

@test "the job read as the verdict is named as tests.yml names its test-summary job" {
  want="$(awk '/^  test-summary:/ { f = 1; next } f && /^    name:/ { sub(/^    name: */, ""); print; exit }' "$DEVBIN_HOME/.github/workflows/tests.yml")"
  [ -n "$want" ] || fail "tests.yml has no test-summary job with a name"
  grep -qxF "SUMMARY=\"$want\"" "$QUERY" || fail "ci-state does not read the job tests.yml names $want"
}

@test "a commit with no run that changes what CI reads is none, naming it" {
  sha="$(commit_path lib/y)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'none\tno Tests run on %s' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "with no tag, a sha with no run is read on the commit before it, through commits that change only paths-ignore's paths" {
  code="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$code" main completed success 106
  commit_path intent/whiteboard/node/board.json >/dev/null
  sha="$(commit_path intent/.canon/events/e.json)"
  ask "$sha"
  assert_success
  [ "$output" = "$(printf 'green\trun 106, on %s: the commits after it to %s change only intent/whiteboard/, intent/.canon/, which the Tests workflow ignores' "${code:0:12}" "${sha:0:12}")" ] ||
    fail "answered: $output"
}

@test "with no tag, a run on a coordination-only commit is that commit's verdict, and the walk stops there" {
  code="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$code" main completed success 107
  sha="$(commit_path intent/whiteboard/node/board.json)"
  run_on "$sha" main completed failure 108
  ask "$sha"
  [ "$output" = "$(printf 'failed\trun 108 (Test Summary: failure)')" ] || fail "answered: $output"
}

@test "with no tag, the walk stops at a commit that changes what CI reads, and with no run there it is none" {
  commit_path lib/y >/dev/null
  sha="$(commit_path intent/whiteboard/node/wip.md)"
  ask "$sha"
  [ "$output" = "$(printf 'none\tno Tests run on %s, nor on the commits before it to %s, the last that changes what the workflow reads' "${sha:0:12}" "$(git -C "$REPO" rev-parse --short=12 HEAD~1)")" ] ||
    fail "answered: $output"
}

@test "with DEVBIN_RELEASE_TAG, only that tag's runs count: a green run on the branch is none until the tag's own exists" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$sha" main completed success 109
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'none\tno Tests run for v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
  run_on "$sha" v9.9.9 completed success 110
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'green\trun 110')" ] || fail "answered: $output"
}

@test "with DEVBIN_RELEASE_TAG, a sha with no run is not read on the commit before it" {
  code="$(git -C "$REPO" rev-parse HEAD)"
  run_on "$code" v9.9.9 completed success 111
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha" v9.9.9
  [ "$output" = "$(printf 'none\tno Tests run for v9.9.9 on %s yet' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a gh that fails is unknown, carrying gh's words" {
  sha="$(git -C "$REPO" rev-parse HEAD)"
  GH_FAIL="HTTP 401: Bad credentials" ask "$sha"
  assert_success
  [ "$output" = "$(printf 'unknown\tgh run list failed for %s: HTTP 401: Bad credentials' "${sha:0:12}")" ] || fail "answered: $output"
}

@test "a paths-ignore entry that is not a directory's whole tree is unknown, naming it, rather than read as something else" {
  cat >"$REPO/.github/workflows/tests.yml" <<'YAML'
on:
  push:
    paths-ignore:
      - 'intent/whiteboard/**'
      - 'docs/*.md'
YAML
  git -C "$REPO" commit -q -am "ignore docs"
  sha="$(commit_path intent/whiteboard/node/board.json)"
  ask "$sha"
  [ "$output" = "$(printf "unknown\t.github/workflows/tests.yml's paths-ignore entry 'docs/*.md' is not a directory's whole tree (<dir>/**), which is all this query reads")" ] ||
    fail "answered: $output"
}

@test "any arguments but a repository and a sha are refused, usage at exit 2" {
  run bash -c 'cd "$1" && "$2" onlyone' _ "$REPO" "$QUERY"
  [ "$status" -eq 2 ] || fail "want 2, got $status: $output"
  assert_output_contains "usage: ci-state <OWNER/NAME> <sha>"
}

@test "devbin publishes through CI on its candidate: publish.url the public repository, its cut to local alone, ci.base left out, ci.tag off, this query asked about release.repo (0240)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml"
  cfg_validate
  # release publish asks this query about the snapshot on its candidate before
  # anything is public, so CI on a workroom commit, ci.base, is not declared.
  [ "$(cfg_release_get publish.url)" = "https://github.com/$(cfg_release_get repo).git" ] ||
    fail "devbin's release.publish.url is not the https url of release.repo: $(cfg_release_get publish.url)"
  [ "$(cfg_release_list remotes)" = local ] || fail "devbin's cut does not push to local alone: $(cfg_release_list remotes)"
  if cfg_release_declared ci.base; then fail "devbin declares release.ci.base, which publish.url refuses"; fi
  # The tag's run, of the snapshot the candidate's run read, is read after the
  # publish, not waited on.
  is_false_word "$(cfg_release_get ci.tag)" || fail "devbin's release.ci.tag is not off: $(cfg_release_get ci.tag)"
  [ "$(cfg_release_get ci.query)" = "bin/.devbin/cmd/.lib/ci-state $(cfg_release_get repo)" ] ||
    fail "devbin's ci.query is not this query asked about release.repo: $(cfg_release_get ci.query)"
  [ -x "$QUERY" ] || fail "$QUERY is not executable"
}
