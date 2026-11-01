#!/usr/bin/env bats
# releaseattach.bats - `release attach`, and the object step of a cut under object: local
# through the same function, and the object row of `release status` (ST0008 WP-08)
#
# The core attaches the assets the EARLIEST SUCCESSFUL run of
# release.assets.workflow at the tag built, and writes one SHA256SUMS over every
# asset on the release object. gh is release_fixtures.bash's stub: its runs,
# artifacts and assets are files under the test's tmpdir, and nothing here
# reaches the network.
#
# EVERY WAIT IS SHORT: the poll is a second, and a project's assets.wait is a
# few seconds unless an arm says otherwise, so a call the stub refuses, which
# the attach waits through as UNREADABLE, fails its arm in seconds rather than
# at the 30m default.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  export DEVBIN_RELEASE_POLL_SECONDS=1
  # For sha256_of: lib/helpers is the one place devbin knows which sha256 tool
  # exists (issue 0052), here as in release.bats and fleet.bats.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# attach_project [wait] [workflow] [release-yaml] -- a project whose
# release.assets.workflow is <workflow> (default linux-release.yml), waiting
# <wait> (default 5s), <release-yaml> as further release: lines when given,
# with .github/workflows/linux-release.yml committed, its v1.0.0 tagged
# (annotated) and pushed, and a release object for it. Its release: lines go
# through no_candidate_body, as every release fixture's do, so a project whose
# <release-yaml> declares no ci: opts out of the candidate, and one that
# declares a ci: block keeps its own.
attach_project() {
  local proj body
  body="$(no_candidate_body "  assets:
    workflow: ${2:-linux-release.yml}
    wait: ${1:-5s}${3:+
$3}")"
  proj="$(mkproj demo <<YAML
project:
  name: demo
commands:
  release:
    enabled: true
release:
$body
YAML
  )"
  with_dated_note "$proj"
  mkdir -p "$proj/.github/workflows"
  printf 'on: push\n' >"$proj/.github/workflows/linux-release.yml"
  git_project "$proj"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a v1.0.0 -m "- first" --cleanup=whitespace
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 "- first"
  printf '%s\n' "$proj"
}

# tag_commit <proj> [tag] -- the commit the tag (default v1.0.0) names.
tag_commit() { git -C "$1" rev-parse "${2:-v1.0.0}^{commit}"; }

# asset <tag> <name> -- the bytes the release object holds as <name>.
asset() { cat "$DEVBIN_TEST_TMPDIR/gh.assets/$1/$2"; }

# sums_of <tag> <name>... -- SHA256SUMS as it must read over those assets, each
# hashed from its bytes, named here in sorted order.
sums_of() {
  local tag="$1" n
  shift
  for n in "$@"; do printf '%s  %s\n' "$(sha256_of "$DEVBIN_TEST_TMPDIR/gh.assets/$tag/$n")" "$n"; done
}

# uploads -- every recorded `gh release upload`, one a line.
uploads() { grep '^gh release upload' "$DEVBIN_TEST_TMPDIR/gh.calls" || [ $? -eq 1 ]; }

# run_files <id> -- how many files the fixture's run <id> built: each file of
# each of its artifacts, as gh_artifact writes them. An arm counts from the
# fixture, never from a number written beside it.
run_files() {
  local f n=0
  for f in "$DEVBIN_TEST_TMPDIR/gh.artifacts/$1"/*/*; do
    if [ -f "$f" ]; then n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

# assets_held <tag> -- how many assets the stub's release object for <tag>
# holds now.
assets_held() {
  local f n=0
  for f in "$DEVBIN_TEST_TMPDIR/gh.assets/$1"/*; do
    if [ -f "$f" ]; then n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

# zeros -- a sha256 digest no bytes have, as GitHub would list one that disagrees.
zeros() { printf 'sha256:%064d' 0; }

# one_run_ships <proj> -- run 101, the one success at v1.0.0, built
# demo-x86.tar.gz and demo-arm.tar.gz.
one_run_ships() {
  gh_run 101 "$(tag_commit "$1")" v1.0.0 completed success 2026-10-22T20:47:40Z
  gh_artifact 101 linux-x86 demo-x86.tar.gz "x86 from 101"
  gh_artifact 101 linux-arm demo-arm.tar.gz "arm from 101"
}

# snapshot <n> <json> -- the nth answer `gh run list` gives (gh.runs.next).
snapshot() {
  printf '%s\n' "$2" >"$DEVBIN_TEST_TMPDIR/runs.$1.json"
  printf '%s\n' "$DEVBIN_TEST_TMPDIR/runs.$1.json" >>"$DEVBIN_TEST_TMPDIR/gh.runs.next"
}

# run_json <id> <sha> <status> <conclusion> -- one run at v1.0.0, as JSON.
run_json() {
  printf '{"databaseId": %s, "headSha": "%s", "headBranch": "v1.0.0", "status": "%s", "conclusion": "%s", "createdAt": "2026-10-22T20:47:40Z", "workflow": "linux-release.yml"}' "$@"
}

# ============================================================================
# THE ATTACH (AC-8.2)
# ============================================================================

# AT-8.2
@test "release attach uploads the files of the earliest successful run at the tag, writes SHA256SUMS over every asset from their bytes, and reads each upload back" {
  proj="$(attach_project)"
  sha="$(tag_commit "$proj")"
  one_run_ships "$proj"
  # A later success at the tag built other bytes, and never ships.
  gh_run 102 "$sha" v1.0.0 completed success 2026-10-22T21:06:43Z
  gh_artifact 102 linux-x86 demo-x86.tar.gz "x86 from 102"
  # Older successes that are not the tag's: one on main at the same commit, one
  # under the tag's name at another commit.
  gh_run 100 "$sha" main completed success 2026-10-22T20:39:10Z
  gh_artifact 100 linux-x86 demo-x86.tar.gz "x86 from main"
  gh_run 99 0000000000000000000000000000000000000000 v1.0.0 completed success 2026-10-22T20:00:00Z
  gh_artifact 99 linux-x86 demo-x86.tar.gz "x86 from another commit"
  # An asset the project uploaded itself, as a hand-built macOS one is, whose
  # GitHub digest disagrees with its bytes: SHA256SUMS is written from the bytes.
  gh_asset v1.0.0 demo-mac.zip "mac"
  zeros >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.0.demo-mac.zip"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'run +already +run 101, the earliest successful linux-release\.yml run at v1\.0\.0'
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "x86 from 101" ] || fail "demo-x86.tar.gz is not run 101's: $(asset v1.0.0 demo-x86.tar.gz)"
  [ "$(asset v1.0.0 demo-arm.tar.gz)" = "arm from 101" ] || fail "demo-arm.tar.gz is not run 101's"
  # ONE SHA256SUMS over EVERY other asset, the project's own included, sorted,
  # each line the sha256 of the bytes, demo-mac.zip's read off the release.
  [ "$(asset v1.0.0 SHA256SUMS)" = "$(sums_of v1.0.0 demo-arm.tar.gz demo-mac.zip demo-x86.tar.gz)" ] ||
    fail "SHA256SUMS reads: $(asset v1.0.0 SHA256SUMS)"
  [ "$(gh_calls '^gh release download --repo t/demo v1.0.0 --pattern demo-mac.zip ')" -eq 1 ] ||
    fail "demo-mac.zip's bytes were not read: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  # What the attach writes: each of run 101's files, then the one SHA256SUMS.
  local writes=$(($(run_files 101) + 1))
  assert_output_matches "readback +done +$writes upload\\(s\\) read back at their sha256"
  # Every upload names the repository and its file bare, none carries
  # --clobber; run 101's artifacts were listed and downloaded, no other run's;
  # and no run was dispatched.
  [ "$(uploads | grep -c -- ' --repo t/demo v1\.0\.0 [A-Za-z0-9.-]*$')" -eq "$writes" ] || fail "uploads: $(uploads)"
  [ "$(uploads | grep -c -- '--clobber')" -eq 0 ] || fail "an upload carries --clobber: $(uploads)"
  [ "$(gh_calls '^gh api repos/t/demo/actions/runs/101/artifacts --paginate ')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(gh_calls '^gh run download --repo t/demo 101 ')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(gh_calls '^gh run download')" -eq 1 ] || fail "another run was downloaded: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(gh_calls '^gh workflow')" -eq 0 ] || fail "the attach dispatched a run"
}

# AT-3.8
@test "release attach reads the run CI made on the candidate's branch at the release commit: the earliest success there or at the tag ships, and a run of that commit on main never does (ST0011 WP07)" {
  proj="$(attach_project 5s linux-release.yml "$(ci_query_decl 0s)")"
  sha="$(tag_commit "$proj")"
  # The candidate's run, on candidate/v1.0.0 at the release commit.
  gh_run 101 "$sha" candidate/v1.0.0 completed success 2026-10-22T20:47:40Z
  gh_artifact 101 linux-x86 demo-x86.tar.gz "x86 from the candidate"
  # A later success at the tag, and an earlier one on main at the same commit:
  # neither ships.
  gh_run 102 "$sha" v1.0.0 completed success 2026-10-22T21:06:43Z
  gh_artifact 102 linux-x86 demo-x86.tar.gz "x86 from the tag"
  gh_run 100 "$sha" main completed success 2026-10-22T20:39:10Z
  gh_artifact 100 linux-x86 demo-x86.tar.gz "x86 from main"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'run +already +run 101, the earliest successful linux-release\.yml run on candidate/v1\.0\.0'
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "x86 from the candidate" ] || fail "demo-x86.tar.gz is not the candidate run's: $(asset v1.0.0 demo-x86.tar.gz)"
  [ "$(gh_calls "^gh run list .*--commit $sha")" -ge 1 ] || fail "the run list was not asked by the release commit: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "a green run of the release commit on main is never the attach's: with none on the candidate's branch or at the tag, the attach waits out assets.wait and uploads nothing (ST0011 WP07)" {
  proj="$(attach_project 2s linux-release.yml "$(ci_query_decl 0s)")"
  sha="$(tag_commit "$proj")"
  gh_run 100 "$sha" main completed success 2026-10-22T20:39:10Z
  gh_artifact 100 linux-x86 demo-x86.tar.gz "x86 from main"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'run +FAILED +no successful run within 2s \(assets\.wait\): pending, no run of linux-release\.yml on candidate/v1\.0\.0 or at v1\.0\.0'
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
}

@test "with a candidate in effect, a success at the tag earlier than any on the candidate's branch is the one that ships (ST0011 WP07)" {
  proj="$(attach_project 5s linux-release.yml "$(ci_query_decl 0s)")"
  sha="$(tag_commit "$proj")"
  gh_run 101 "$sha" v1.0.0 completed success 2026-10-22T20:39:10Z
  gh_artifact 101 linux-x86 demo-x86.tar.gz "x86 from the tag"
  gh_run 102 "$sha" candidate/v1.0.0 completed success 2026-10-22T20:47:40Z
  gh_artifact 102 linux-x86 demo-x86.tar.gz "x86 from the candidate"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'run +already +run 101, the earliest successful linux-release\.yml run at v1\.0\.0'
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "x86 from the tag" ] || fail "demo-x86.tar.gz is not the tag run's: $(asset v1.0.0 demo-x86.tar.gz)"
}

@test "release attach under release.publish.url reads the run on the commit the public tag names, the release commit's snapshot, never the run on the workroom's commit (ST0011 WP07)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" other="$DEVBIN_TEST_TMPDIR/other" snap
  git init -q --bare -b main "$pub"
  # release.publish.url is read only where the snapshot's keys are declared;
  # the attach makes no snapshot, so they are never used.
  proj="$(attach_project 5s linux-release.yml "  repo: t/public
  snapshot:
    list: shipped.paths
    author: \"Snap Shot <snap@example.com>\"
  publish:
    url: $pub")"
  sha="$(tag_commit "$proj")"
  # The public tag, at a commit of its own, as a publishing cut tags its snapshot.
  git init -q -b main "$other"
  git -C "$other" -c user.name=o -c user.email=o@o -c maintenance.auto=false commit -q --allow-empty -m snapshot
  snap="$(git -C "$other" rev-parse HEAD)"
  git -C "$other" push -q "$pub" "$snap:refs/tags/v1.0.0"
  gh_run 101 "$snap" v1.0.0 completed success 2026-10-22T20:47:40Z
  gh_artifact 101 linux-x86 demo-x86.tar.gz "x86 from the snapshot"
  # An earlier run at the tag on the workroom's commit, which never ships here.
  gh_run 100 "$sha" v1.0.0 completed success 2026-10-22T20:39:10Z
  gh_artifact 100 linux-x86 demo-x86.tar.gz "x86 from the workroom"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches "run +already +run 101, the earliest successful linux-release\\.yml run at v1\\.0\\.0 \\(${snap:0:12}\\)"
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "x86 from the snapshot" ] || fail "demo-x86.tar.gz is not the snapshot run's: $(asset v1.0.0 demo-x86.tar.gz)"
  # Asked of the public repository release.repo names, by the snapshot's commit.
  [ "$(gh_calls "^gh run list --repo t/public .*--commit $snap")" -ge 1 ] || fail "the run list did not ask t/public by the snapshot: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# calls_since <n> <pattern> -- how many recorded gh calls after the first <n>
# match <pattern>: what one run asked, read off the log the arm shares.
calls_since() {
  awk -v n="$1" -v p="$2" 'NR > n && $0 ~ p { c++ } END { print c + 0 }' "$DEVBIN_TEST_TMPDIR/gh.calls"
}

# AT-8.2
@test "a re-run of release attach on a finished release stops at its own postcondition: no run is read, and nothing is uploaded" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  run release_in "$proj" attach v1.0.0
  assert_success
  local before calls
  before="$(uploads | wc -l | tr -d ' ')"
  [ "$before" -eq $(($(run_files 101) + 1)) ] || fail "the first run made $before upload(s), not run 101's files and SHA256SUMS: $(uploads)"
  calls="$(grep -c '' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches "assets +already +SHA256SUMS names the object.s $(run_files 101) other asset\\(s\\), each at its GitHub digest"
  assert_output_contains "release: attach v1.0.0: finished already, so no run was read"
  [ "$(calls_since "$calls" '^gh run ')" -eq 0 ] || fail "the re-run read a run: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(uploads | wc -l | tr -d ' ')" -eq "$before" ] || fail "the re-run uploaded: $(uploads)"
}

# AT-8.2
@test "release attach on a finished release whose run's artifacts have expired exits 0: no gh run or artifacts call, no download, no upload" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  run release_in "$proj" attach v1.0.0
  assert_success
  # Every one of run 101's artifacts expires, as GitHub's retention has them do.
  local a calls
  for a in "$DEVBIN_TEST_TMPDIR/gh.artifacts/101"/*; do
    : >"$DEVBIN_TEST_TMPDIR/gh.expired.101.${a##*/}"
  done
  calls="$(grep -c '' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'assets +already '
  [ "$(calls_since "$calls" '^gh run ')" -eq 0 ] || fail "the attach read a run: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(calls_since "$calls" '^gh api ')" -eq 0 ] || fail "the attach listed a run's artifacts: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(calls_since "$calls" '^gh release upload')" -eq 0 ] || fail "the attach uploaded: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  # Its one download is SHA256SUMS' own small read.
  [ "$(calls_since "$calls" '^gh release download')" -eq "$(calls_since "$calls" '^gh release download .*--pattern SHA256SUMS ')" ] ||
    fail "the attach downloaded more than SHA256SUMS: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-8.2
@test "a file of the run already on the object at its sha256 is already, one with no GitHub digest is read to compare, and only the rest are uploaded" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  gh_asset v1.0.0 demo-x86.tar.gz "x86 from 101"
  printf 'none\n' >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.0.demo-x86.tar.gz"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'upload +done +1 uploaded and read back \(demo-arm\.tar\.gz\), 1 already'
  [ "$(uploads | grep -c 'demo-x86')" -eq 0 ] || fail "demo-x86.tar.gz was uploaded again: $(uploads)"
  [ "$(gh_calls '^gh release download --repo t/demo v1.0.0 --pattern demo-x86.tar.gz ')" -ge 1 ] ||
    fail "the asset with no digest was not read: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-8.2
@test "a file of the run on the object with other bytes is refused, never replaced, and nothing is uploaded" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  gh_asset v1.0.0 demo-x86.tar.gz "someone else's x86"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'upload +FAILED +the release object already holds demo-x86\.tar\.gz at '
  assert_output_contains "the attach never replaces an asset"
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "someone else's x86" ] || fail "the asset was replaced"
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/SHA256SUMS" ] || fail "SHA256SUMS was written"
}

# AT-8.2
@test "an asset of the project's own that SHA256SUMS could not be written over is refused before any upload" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  gh_asset v1.0.0 'notes[1].txt' "picked out by no pattern but itself"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'upload +FAILED +SHA256SUMS could not be written over every asset on the release object: notes\[1\]\.txt: '
  assert_output_contains "nothing was uploaded"
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
}

# AT-8.2
@test "SHA256SUMS is the one asset the attach replaces, with --clobber, and only when its text differs" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  gh_asset v1.0.0 SHA256SUMS "a stale sums file"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'sums +done +SHA256SUMS written over'
  [ "$(asset v1.0.0 SHA256SUMS)" = "$(sums_of v1.0.0 demo-arm.tar.gz demo-x86.tar.gz)" ] || fail "SHA256SUMS: $(asset v1.0.0 SHA256SUMS)"
  # --clobber on SHA256SUMS alone.
  [ "$(uploads | grep -c -- '--clobber')" -eq 1 ] || fail "uploads: $(uploads)"
  grep -q ' SHA256SUMS --clobber$' <<<"$(uploads)" || fail "the --clobber upload is not SHA256SUMS: $(uploads)"
  # A second run reaches the sums stage only while the assets stage reads
  # pending: with no GitHub digest for one asset to check SHA256SUMS against,
  # the stages run, and SHA256SUMS, its text unchanged, is not replaced.
  printf 'none\n' >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.0.demo-x86.tar.gz"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'assets +pending +.*demo-x86\.tar\.gz has no GitHub digest'
  assert_output_matches 'sums +already '
  [ "$(uploads | grep -c -- '--clobber')" -eq 1 ] || fail "SHA256SUMS was replaced with the same text"
}

# AT-8.2
@test "an upload that does not read back at its sha256 is FAILED, and SHA256SUMS is not written" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  zeros >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.0.demo-arm.tar.gz"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_contains "uploaded demo-arm.tar.gz, and it does not read back at its sha256 $(sha256_of "$DEVBIN_TEST_TMPDIR/gh.artifacts/101/linux-arm/demo-arm.tar.gz"): GitHub lists $(zeros) -- SHA256SUMS is not written"
  assert_output_matches 'upload +FAILED +'
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/SHA256SUMS" ] || fail "SHA256SUMS was written over an upload that did not read back"
}

# AT-8.2
@test "SHA256SUMS that does not read back at its sha256 fails the readback stage, after it was written" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  zeros >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.0.SHA256SUMS"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'sums +done +SHA256SUMS written over'
  assert_output_matches 'readback +FAILED +uploaded SHA256SUMS, and it does not read back at its sha256 [0-9a-f]{64}: GitHub lists sha256:0{64}'
}

# AT-8.2
@test "an upload that fails part way stops the attach, naming what it uploaded before it, and SHA256SUMS is not written" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  : >"$DEVBIN_TEST_TMPDIR/gh.fail.upload.demo-x86.tar.gz"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'upload +FAILED +gh release upload demo-x86\.tar\.gz failed \(exit 1\): HTTP 502: uploading demo-x86\.tar\.gz failed; uploaded before it: demo-arm\.tar\.gz'
  assert_output_contains "This run uploaded $(assets_held v1.0.0) asset(s) to the release object for v1.0.0."
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/SHA256SUMS" ] || fail "SHA256SUMS was written"
}

# AT-8.2
@test "an upload cut off at its bound stops the attach, and its stop line names the upload as one that may have happened, never as nothing uploaded" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  : >"$DEVBIN_TEST_TMPDIR/gh.hang.upload"
  local start=$SECONDS
  DEVBIN_RELEASE_CALL_SECONDS=2 run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'upload +FAILED +gh release upload demo-arm\.tar\.gz did not finish within 2s and was stopped -- whether it took effect is unknown'
  assert_output_contains "This run may have uploaded demo-arm.tar.gz, whose upload was cut off at its bound."
  refute_output_contains "uploaded nothing"
  [ $((SECONDS - start)) -lt 30 ] || fail "the hung upload held the attach for $((SECONDS - start))s"
}

# AT-8.2
@test "a SHA256SUMS replacement that fails stops the attach, and its stop line names SHA256SUMS as one --clobber may have deleted" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  gh_asset v1.0.0 SHA256SUMS "a stale sums file"
  : >"$DEVBIN_TEST_TMPDIR/gh.fail.upload.SHA256SUMS"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'sums +FAILED +gh release upload SHA256SUMS --clobber failed \(exit 1\): HTTP 502: uploading SHA256SUMS failed -- '
  assert_output_contains "This run uploaded $(run_files 101) asset(s) to the release object for v1.0.0, and may have deleted or replaced the release object's SHA256SUMS, which --clobber deletes before it uploads."
}

# AT-8.2
@test "the release object must exist: the attach makes none, and reads no run" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  : >"$DEVBIN_TEST_TMPDIR/gh.releases"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'object +FAILED +no release object for v1\.0\.0, and the attach makes none'
  [ "$(gh_calls '^gh release create')" -eq 0 ] || fail "the attach made the object"
  [ "$(gh_calls '^gh run ')" -eq 0 ] || fail "the attach read a run with no object to attach to"
}

# AT-8.2
@test "while no run is listed, and while the run is in progress, the attach waits within assets.wait, then attaches" {
  proj="$(attach_project 30s)"
  sha="$(tag_commit "$proj")"
  snapshot 1 '[]'
  snapshot 2 "[$(run_json 101 "$sha" in_progress "")]"
  snapshot 3 "[$(run_json 101 "$sha" completed success)]"
  gh_artifact 101 linux-x86 demo-x86.tar.gz "x86 from 101"
  local answers
  answers="$(grep -c '' "$DEVBIN_TEST_TMPDIR/gh.runs.next")"
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_matches 'run +already +run 101'
  [ "$(gh_calls '^gh run list')" -eq "$answers" ] || fail "want one ask of the run list per scripted answer, $answers: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(asset v1.0.0 demo-x86.tar.gz)" = "x86 from 101" ]
}

# AT-8.2
@test "no successful run within assets.wait is FAILED, naming how to start one, and the attach never dispatches" {
  proj="$(attach_project)"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'run +FAILED +no successful run within 5s \(assets\.wait\): pending, no run of linux-release\.yml at v1\.0\.0'
  assert_output_contains "gh workflow run linux-release.yml --ref v1.0.0"
  [ "$(gh_calls '^gh run list')" -gt 1 ] || fail "the run list was asked once, so nothing was waited for"
  [ "$(gh_calls '^gh workflow')" -eq 0 ] || fail "the attach dispatched a run"
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
}

# AT-8.2
@test "an earlier run still going holds the answer: the attach waits for it, never taking a later success" {
  proj="$(attach_project)"
  sha="$(tag_commit "$proj")"
  gh_run 101 "$sha" v1.0.0 in_progress "" 2026-10-22T20:47:40Z
  gh_run 102 "$sha" v1.0.0 completed success 2026-10-22T21:06:43Z
  gh_artifact 102 linux-x86 demo-x86.tar.gz "x86 from 102"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_contains "run 101 of linux-release.yml at v1.0.0 is in_progress, and may yet be the earliest to succeed"
  [ "$(gh_calls '^gh run list')" -gt 1 ] || fail "the run list was asked once, so nothing was waited for"
  [ "$(gh_calls '^gh run download')" -eq 0 ] || fail "a later run's artifacts were downloaded"
}

# AT-8.2
@test "every run at the tag failed: FAILED at once, the cause read from the newest one's jobs, never its conclusion alone" {
  # A wait of 30s that a failed run must not spend: one ask per call.
  proj="$(attach_project 30s)"
  sha="$(tag_commit "$proj")"
  gh_run 101 "$sha" v1.0.0 completed failure 2026-10-22T20:47:40Z
  gh_run 102 "$sha" v1.0.0 completed failure 2026-10-22T21:06:43Z
  printf '{"jobs": [{"name": "package (x86_64)", "status": "completed", "conclusion": "failure"}, {"name": "package (aarch64)", "status": "completed", "conclusion": "success"}]}\n' \
    >"$DEVBIN_TEST_TMPDIR/gh.jobs.102.json"
  run release_in "$proj" attach v1.0.0
  assert_failure
  [ "$(gh_calls '^gh run list')" -eq 1 ] || fail "a failed run was waited for: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  assert_output_contains "no run of linux-release.yml at v1.0.0"
  local failed asked
  failed="$(jq '[.[] | select(.conclusion == "failure")] | length' "$DEVBIN_TEST_TMPDIR/gh.runs.json")"
  assert_output_contains "the newest, run 102, job package (x86_64) failure; $failed runs failed"
  refute_output_contains "package (aarch64)"
  assert_output_contains "gh run rerun 102"
  # A run whose jobs say nothing failed is a refusal before any job ran, and says
  # so rather than read its conclusion as a failed build.
  printf '{"jobs": []}\n' >"$DEVBIN_TEST_TMPDIR/gh.jobs.102.json"
  asked="$(gh_calls '^gh run list')"
  run release_in "$proj" attach v1.0.0
  assert_failure
  [ "$(gh_calls '^gh run list')" -eq $((asked + 1)) ] || fail "a failed run was waited for: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  assert_output_contains "no job of it failed, so nothing says why it concluded failure"
}

# AT-8.2
@test "a run list as long as gh was asked for is refused at once: its earliest run may not be in it" {
  proj="$(attach_project 30s)"
  sha="$(tag_commit "$proj")"
  # More runs at the tag than the attach asks gh for, which the stub cuts to the
  # --limit asked, as gh does. The arm reads that limit off the call, so no
  # count of runs is written here to agree with the code's; were the limit ever
  # past this fixture, no refusal would come and the arm would fail.
  jq -n --arg sha "$sha" '[range(0; 1000) | {databaseId: (1000 + .), headSha: $sha, headBranch: "v1.0.0", status: "completed", conclusion: "success", createdAt: "2026-10-22T20:00:00Z", workflow: "linux-release.yml"}]' \
    >"$DEVBIN_TEST_TMPDIR/gh.runs.json"
  run release_in "$proj" attach v1.0.0
  assert_failure
  # Asked once: never, and the limit cannot be read; again, and a list that
  # cannot shorten was waited through.
  [ "$(gh_calls '^gh run list ')" -eq 1 ] || fail "want the run list asked once: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls" 2>&1)"
  local limit
  limit="$(awk '/^gh run list / { for (i = 1; i < NF; i++) if ($i == "--limit") { print $(i + 1); exit } }' "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ -n "$limit" ] || fail "the run list was asked with no --limit: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  assert_output_matches "run +FAILED +gh lists $limit runs of linux-release\\.yml on ${sha:0:12}, as many as it was asked for, so the earliest cannot be told"
}

# AT-8.2
@test "the run's artifacts are held to GitHub's list: one expired, or one the download did not write, is refused, and nothing is uploaded" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  : >"$DEVBIN_TEST_TMPDIR/gh.expired.101.linux-arm"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'download +FAILED +run 101, the earliest successful run, has expired artifacts \(linux-arm\), and the attach ships that run.s files alone -- a rerun of it \(gh run rerun 101\) is the one way that might give them back, and whether it does is not measured'
  # A run dispatched now is never the earliest, so it is not offered.
  refute_output_contains "gh workflow run"
  [ "$(gh_calls '^gh run download')" -eq 0 ] || fail "an expired run was downloaded"
  rm "$DEVBIN_TEST_TMPDIR/gh.expired.101.linux-arm"
  : >"$DEVBIN_TEST_TMPDIR/gh.skip.101.linux-arm"
  run release_in "$proj" attach v1.0.0
  assert_failure
  assert_output_matches 'download +FAILED +run 101 lists the artifact linux-arm, and gh run download wrote no linux-arm under '
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
}

# AT-8.2
@test "artifacts holding a file named twice, a file named SHA256SUMS, a name GitHub would rename, or no file, or a run with no artifact, are refused, and nothing is uploaded" {
  proj="$(attach_project)"
  sha="$(tag_commit "$proj")"
  gh_run 101 "$sha" v1.0.0 completed success 2026-10-22T20:47:40Z
  local dir="$DEVBIN_TEST_TMPDIR/gh.artifacts/101" why
  while IFS= read -r why; do
    [ -n "$why" ] || continue
    rm -rf "$dir"
    case "$why" in
      twice) gh_artifact 101 a demo.tar.gz x; gh_artifact 101 b demo.tar.gz y ;;
      sums) gh_artifact 101 a SHA256SUMS x ;;
      glob) gh_artifact 101 a 'demo[1].tar.gz' x ;;
      space) gh_artifact 101 a 'demo 1.tar.gz' x ;;
      hash) gh_artifact 101 a 'demo#1.tar.gz' x ;;
      dot) gh_artifact 101 a '.demo.tar.gz' x ;;
      empty) mkdir -p "$dir/a" ;;
      none) ;;
    esac
    run release_in "$proj" attach v1.0.0
    assert_failure
    case "$why" in
      twice) assert_output_contains "two files in run 101's artifacts are named demo.tar.gz" ;;
      sums) assert_output_contains "SHA256SUMS is the name the attach writes its sums under" ;;
      glob | space | hash) assert_output_contains "holds a character other than a letter, a digit, a period, a hyphen or an underscore" ;;
      dot) assert_output_contains "it begins or ends with a period, which GitHub renames" ;;
      empty) assert_output_contains "run 101's artifacts hold no file, so there is nothing to attach" ;;
      none) assert_output_contains "run 101 lists no artifact, so there is nothing to attach" ;;
    esac
    assert_output_matches 'download +FAILED +'
  done <<<$'twice\nsums\nglob\nspace\nhash\ndot\nempty\nnone'
  [ -z "$(uploads)" ] || fail "something was uploaded: $(uploads)"
}

# ============================================================================
# THE ATTACH OF FILES BUILT HERE: release attach --from (issue 0226)
# ============================================================================

# from_project -- attach_project with no assets.workflow: a project whose
# assets are built on this machine and attached with --from alone.
from_project() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
YAML
  )"
  with_dated_note "$proj"
  git_project "$proj"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a v1.0.0 -m "- first" --cleanup=whitespace
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 "- first"
  printf '%s\n' "$proj"
}

# built <name> <bytes> -- a file built on this machine, in the --from dir.
built() {
  mkdir -p "$BATS_TEST_TMPDIR/out"
  printf '%s' "$2" >"$BATS_TEST_TMPDIR/out/$1"
}

@test "release attach --from attaches the files under the directory through the core's stages, with no assets.workflow and no run read" {
  proj="$(from_project)"
  built demo-mac.zip "mac built here"
  gh_asset v1.0.0 demo-notes.txt "notes"
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/out"
  assert_success
  assert_output_matches 'assets +none +release\.assets\.workflow is not declared'
  assert_output_matches 'files +done +1 file\(s\) under .*: demo-mac\.zip'
  [ "$(asset v1.0.0 demo-mac.zip)" = "mac built here" ] || fail "demo-mac.zip: $(asset v1.0.0 demo-mac.zip)"
  # ONE SHA256SUMS over every asset, the one already there included.
  [ "$(asset v1.0.0 SHA256SUMS)" = "$(sums_of v1.0.0 demo-mac.zip demo-notes.txt)" ] ||
    fail "SHA256SUMS reads: $(asset v1.0.0 SHA256SUMS)"
  assert_output_matches 'readback +done +2 upload\(s\) read back at their sha256'
  [ "$(gh_calls '^gh run ')" -eq 0 ] || fail "--from read a run: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  [ "$(uploads | grep -c -- '--clobber')" -eq 0 ] || fail "an upload carries --clobber: $(uploads)"
  # The same file again is already, and other bytes under its name are refused.
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/out"
  assert_success
  assert_output_matches "upload +already +every file of .*/out is on the release object"
  built demo-mac.zip "mac built again"
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/out"
  assert_failure
  assert_output_contains "the attach never replaces an asset"
  [ "$(asset v1.0.0 demo-mac.zip)" = "mac built here" ] || fail "the asset was replaced"
}

@test "with assets.workflow declared, release attach --from refuses until the run's attach has finished, then attaches beside it" {
  proj="$(attach_project)"
  one_run_ships "$proj"
  built demo-mac.zip "mac built here"
  # Before the run's attach: an attach --from now would leave SHA256SUMS
  # agreeing with the object, and the run's attach would read finished.
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/out"
  assert_failure
  assert_output_contains "release.assets.workflow is linux-release.yml, and its run's attach comes first"
  [ "$(uploads | wc -l | tr -d ' ')" -eq 0 ] || fail "a refused --from uploaded: $(uploads)"
  [ "$(gh_calls '^gh run ')" -eq 0 ] || fail "--from read a run: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  run release_in "$proj" attach v1.0.0
  assert_success
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/out"
  assert_success
  assert_output_matches "assets +already +the run's attach has finished"
  [ "$(asset v1.0.0 SHA256SUMS)" = "$(sums_of v1.0.0 demo-arm.tar.gz demo-mac.zip demo-x86.tar.gz)" ] ||
    fail "SHA256SUMS reads: $(asset v1.0.0 SHA256SUMS)"
  # And the run's attach, asked again, is finished with every asset named.
  run release_in "$proj" attach v1.0.0
  assert_success
  assert_output_contains "finished already, so no run was read"
}

@test "release attach --from a relative name reads it from the project root, never through an exported CDPATH (0267)" {
  proj="$(from_project)"
  # The files under a bare name at the project root, and other files under the
  # same name where CDPATH points.
  mkdir -p "$proj/out" "$BATS_TEST_TMPDIR/decoy/out"
  printf '%s' "mac built here" >"$proj/out/demo-mac.zip"
  printf '%s' "not these" >"$BATS_TEST_TMPDIR/decoy/out/demo-decoy.zip"
  CDPATH="$BATS_TEST_TMPDIR/decoy" run release_in "$proj" attach v1.0.0 --from out
  assert_success
  [ "$(asset v1.0.0 demo-mac.zip)" = "mac built here" ] || fail "demo-mac.zip: $(asset v1.0.0 demo-mac.zip)"
  refute_output_contains "demo-decoy.zip"
  refute_output_contains "$BATS_TEST_TMPDIR/decoy"
  ! grep -q -F demo-decoy.zip <<<"$(uploads)" || fail "the decoy was uploaded: $(uploads)"
}

@test "--from is refused on another verb, without a directory, and for one that is not there, before gh is called" {
  proj="$(from_project)"
  run release_in "$proj" status v1.0.0 --from "$BATS_TEST_TMPDIR"
  assert_failure
  assert_output_contains "--from applies to release attach, not to release status"
  run release_in "$proj" attach v1.0.0 --from
  assert_failure
  assert_output_contains "--from needs a directory"
  run release_in "$proj" attach v1.0.0 --from "$BATS_TEST_TMPDIR/absent"
  assert_failure
  assert_output_contains "is not a directory"
  [ "$(gh_calls '^gh ')" -eq 0 ] || fail "a refused --from called gh: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-8.2
@test "release attach is refused outside object: local, with no assets.workflow, for a tag this checkout lacks, and for a workflow its commit does not hold, each named, exit 1" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  object: ci
YAML
  )"
  run devbin_run "$proj" release attach v1.0.0
  [ "$status" -eq 1 ] || fail "exit $status: $output"
  assert_output_contains "object is ci, and the core attaches assets under object: local alone"
  printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\n' >"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" release attach v1.0.0
  [ "$status" -eq 1 ] || fail "exit $status: $output"
  assert_output_contains "release.assets.workflow is not declared"
  proj="$(attach_project)"
  run release_in "$proj" attach v9.9.9
  [ "$status" -eq 1 ] || fail "exit $status: $output"
  assert_output_contains "there is no tag v9.9.9 here"
  # The same project, its declaration naming a workflow v1.0.0's commit lacks:
  # one fixture per arm, since a second would share the first one's remote.
  printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\nrelease:\n  assets:\n    workflow: other.yml\n' \
    >"$proj/bin/.devbin/config.yaml"
  run release_in "$proj" attach v1.0.0
  [ "$status" -eq 1 ] || fail "exit $status: $output"
  assert_output_contains "release.assets.workflow is other.yml, and v1.0.0's commit"
  assert_output_contains "holds no .github/workflows/other.yml"
  [ "$(gh_calls '^gh ')" -eq 0 ] || fail "a refused attach called gh: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-8.2
@test "the assets keys are refused outside object: local, and assets.wait without assets.workflow, by name" {
  proj="$(enabled_project)"
  with_dated_note "$proj"
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\nrelease:\n%b\n' "$block" >"$proj/bin/.devbin/config.yaml"
    run devbin_run "$proj" release check
    [ "$status" -eq 1 ] || fail "accepted: $block"
    assert_output_contains "$want"
  done <<'EOF'
  object: ci\n  assets:\n    workflow: linux-release.yml|release.assets.workflow is read only under object: local, and object is ci
  object: none\n  assets:\n    workflow: linux-release.yml|release.assets.workflow is read only under object: local, and object is none
  object: ci\n  assets:\n    wait: 5m|release.assets.wait is read only under object: local, and object is ci
  assets:\n    wait: 5m|release.assets.wait is read only when release.assets.workflow is declared
  assets:\n    workflow: .github/workflows/linux-release.yml|must be the file name of a workflow in .github/workflows
  assets:\n    workflow: linux-release.yml\n    wait: soon|release.assets.wait: "soon" must be a whole number of s, m or h
EOF
  # THE CONTROL: the same keys under object: local validate.
  printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\nrelease:\n  assets:\n    workflow: linux-release.yml\n    wait: 5m\n' >"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" release check
  assert_success
  assert_output_matches 'assets\.workflow +linux-release\.yml +declared'
}

# ============================================================================
# THE OBJECT STEP OF A CUT, THROUGH THE SAME FUNCTION (AC-8.2)
# ============================================================================

# ci_builds_tag <tag> <id> -- the fixture's CI: a push of <tag> to the remote
# makes run <id> of linux-release.yml at the tag's commit, finished and green, as
# a tag trigger would. Its artifacts are the arm's (gh_artifact <id> ...).
ci_builds_tag() {
  local hooks="$DEVBIN_TEST_TMPDIR/remote.git/hooks"
  mkdir -p "$hooks"
  cat >"$hooks/post-receive" <<SH
#!/bin/sh
while read -r old new ref; do
  [ "\$ref" = "refs/tags/$1" ] || continue
  sha="\$(git rev-parse "\$ref^{commit}")"
  printf '[{"databaseId": $2, "headSha": "%s", "headBranch": "$1", "status": "completed", "conclusion": "success", "createdAt": "2026-10-23T10:00:00Z", "workflow": "linux-release.yml"}]\n' "\$sha" >"$DEVBIN_TEST_TMPDIR/gh.runs.json"
done
SH
  chmod +x "$hooks/post-receive"
}

# assets_cut_project [wait] [workflow] [release-yaml] -- cut_project with
# release.assets.workflow declared as <workflow> (default linux-release.yml),
# waiting <wait> (default 30s), <release-yaml> as further release: lines when
# given, and .github/workflows/linux-release.yml committed and pushed.
assets_cut_project() {
  local proj
  proj="$(cut_project "  gates:
    - probe
  assets:
    workflow: ${2:-linux-release.yml}
    wait: ${1:-30s}${3:+
$3}")"
  mkdir -p "$proj/.github/workflows"
  printf 'on: push\n' >"$proj/.github/workflows/linux-release.yml"
  git -C "$proj" add .github/workflows/linux-release.yml
  git -C "$proj" commit -qm "the assets' workflow"
  git -C "$proj" push -q origin main
  printf '%s\n' "$proj"
}

# AT-8.2
@test "a cut under object: local attaches at the object step through the function release attach runs: the confirm step names the attach, the object row names the run" {
  proj="$(assets_cut_project)"
  ci_builds_tag v1.0.1 301
  gh_artifact 301 linux-x86 demo-x86.tar.gz "x86 for 1.0.1"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state object done
  grep -qF "attach the assets linux-release.yml's run at v1.0.1 built, and SHA256SUMS" <<<"$(row_of confirm)" || fail "the confirm row: $(row_of confirm)"
  grep -qF "made the release object \"v1.0.1\"; attached run 301's $(run_files 301) file(s): $(run_files 301) uploaded, 0 already; SHA256SUMS written over $(run_files 301) asset(s)" <<<"$(row_of object)" ||
    fail "the object row: $(row_of object)"
  [ "$(asset v1.0.1 demo-x86.tar.gz)" = "x86 for 1.0.1" ] || fail "the run's file is not on the object"
  [ "$(asset v1.0.1 SHA256SUMS)" = "$(sums_of v1.0.1 demo-x86.tar.gz)" ] || fail "SHA256SUMS: $(asset v1.0.1 SHA256SUMS)"
  [ "$(gh_calls '^gh workflow')" -eq 0 ] || fail "the cut dispatched a run"
}

# AT-8.2
@test "a re-run of a finished cut with assets asks nothing: the confirm step reads SHA256SUMS agreeing with the object, and the object row is already" {
  proj="$(assets_cut_project)"
  ci_builds_tag v1.0.1 301
  gh_artifact 301 linux-x86 demo-x86.tar.gz "x86 for 1.0.1"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  local before
  before="$(uploads | wc -l | tr -d ' ')"
  [ "$before" -eq $(($(run_files 301) + 1)) ] || fail "the cut made $before upload(s), not run 301's files and SHA256SUMS: $(uploads)"
  # No terminal and no --yes: a re-run with work left would stop at the confirm step.
  run release_in "$proj" v1.0.1
  assert_success
  assert_state confirm "not re-run"
  assert_state object already
  grep -qF "SHA256SUMS names the object's $(run_files 301) other asset(s), each at its GitHub digest" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  [ "$(uploads | wc -l | tr -d ' ')" -eq "$before" ] || fail "the re-run uploaded: $(uploads)"
  [ "$(gh_calls '^gh run download')" -eq 1 ] || fail "the re-run downloaded the run's artifacts again"
}

# AT-8.2
@test "a dry run says the object step would attach, waits for no run, and names the attach among what it did not reach" {
  proj="$(assets_cut_project)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state object would
  grep -qF "then attach the assets linux-release.yml's run at v1.0.1 built, and SHA256SUMS, waiting up to 30s (assets.wait) for the run" <<<"$(row_of object)" ||
    fail "the object row: $(row_of object)"
  assert_output_contains "the object step's attach: a dry run reads no run's files and attaches nothing"
  [ "$(gh_calls '^gh run ')" -eq 0 ] || fail "a dry run read a run: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# AT-8.2
@test "pre-flight refuses a cut whose assets.workflow the release commit does not hold, before any gate: no run at the tag could build the assets" {
  proj="$(assets_cut_project 30s other.yml)"
  run release_in "$proj" v1.0.1 --yes
  assert_failure
  assert_state pre-flight FAILED
  grep -qF "release.assets.workflow is other.yml, and" <<<"$(row_of pre-flight)" || fail "the pre-flight row: $(row_of pre-flight)"
  grep -qF "holds no .github/workflows/other.yml, so no run at the tag could build the assets" <<<"$(row_of pre-flight)" || fail "the pre-flight row: $(row_of pre-flight)"
  [ ! -s "$DEVBIN_TEST_TMPDIR/gate.calls" ] || fail "a gate ran after a refused pre-flight"
}

# AT-8.2
@test "an attach that fails at the object step stops the cut there, exit 1, naming its stage, the release object made" {
  proj="$(assets_cut_project 2s)"
  run release_in "$proj" v1.0.1 --yes
  assert_failure
  assert_state object FAILED
  assert_output_contains "stopped at the object step"
  grep -qF "made the release object \"v1.0.1\"; the attach stopped at run: no successful run within 2s (assets.wait)" <<<"$(row_of object)" ||
    fail "the object row: $(row_of object)"
  assert_output_contains "made the release object for v1.0.1"
  grep -qxF v1.0.1 "$DEVBIN_TEST_TMPDIR/gh.releases" || fail "the release object was not made"
}

# AT-8.2
@test "an upload that fails part way at the object step stops the cut, and its stop names the asset it uploaded" {
  proj="$(assets_cut_project)"
  ci_builds_tag v1.0.1 301
  gh_artifact 301 linux-arm demo-arm.tar.gz "arm for 1.0.1"
  gh_artifact 301 linux-x86 demo-x86.tar.gz "x86 for 1.0.1"
  : >"$DEVBIN_TEST_TMPDIR/gh.fail.upload.demo-x86.tar.gz"
  run release_in "$proj" v1.0.1 --yes
  assert_failure
  assert_state object FAILED
  assert_output_contains "made the release object for v1.0.1, uploaded $(assets_held v1.0.1) asset(s) to the release object for v1.0.1."
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.1/SHA256SUMS" ] || fail "SHA256SUMS was written"
}

@test "an attach whose upload fails ends the cut red: exit 1, its RELEASE seal closed red, its verdict line naming it, and no after: command run (0297, ST0011 WP02b-2)" {
  local seal
  proj="$(assets_cut_project 30s linux-release.yml "  after:
    - touch $DEVBIN_TEST_TMPDIR/after.ran")"
  ci_builds_tag v1.0.1 301
  gh_artifact 301 linux-x86 demo-x86.tar.gz "x86 for 1.0.1"
  : >"$DEVBIN_TEST_TMPDIR/gh.fail.upload"
  run release_in "$proj" v1.0.1 --yes
  [ "$status" -eq 1 ] || fail "want exit 1, got $status: $output"
  # Stopped by the attach's upload, at the object step, and by nothing earlier.
  assert_state object FAILED
  [[ "$(row_of object)" == *"the attach stopped at upload"* ]] || fail "the object row: $(row_of object)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/after.ran" ] || fail "an after: command ran after the attach failed: $output"
  seal="$(release_seal "$proj")" || fail "$output"
  assert_release_seal "$seal" failed "$output"
}

# ============================================================================
# THE OBJECT ROW OF release status: WHAT THE ATTACH'S LAST WRITE SAYS
# ============================================================================

# AT-8.2
@test "status the object row is already only when SHA256SUMS names exactly the object's other assets at their GitHub digests, pending naming why, UNREADABLE when a read fails" {
  proj="$(assets_cut_project)"
  ci_builds_tag v1.0.1 301
  gh_artifact 301 linux-x86 demo-x86.tar.gz "x86 for 1.0.1"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  local assets="$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.1" calls writes
  calls="$(gh_calls '^gh run download')"
  writes="$(gh_calls '^gh release \(upload\|create\|edit\|delete\)')"
  [ "$writes" -ge 1 ] || fail "the cut wrote nothing to the object, so the count below compares nothing"
  run release_in "$proj" status v1.0.1
  assert_success
  assert_state object already
  grep -qF "SHA256SUMS names the object's $(run_files 301) other asset(s), each at its GitHub digest" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  assert_state confirm "not re-run"
  # SHA256SUMS gone: work left, and the confirmation is held open.
  mv "$assets/SHA256SUMS" "$DEVBIN_TEST_TMPDIR/sums.kept"
  run release_in "$proj" status v1.0.1
  assert_state object pending
  grep -qF "the release object for v1.0.1 carries no SHA256SUMS" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  assert_state confirm pending
  mv "$DEVBIN_TEST_TMPDIR/sums.kept" "$assets/SHA256SUMS"
  # An asset SHA256SUMS does not name.
  gh_asset v1.0.1 extra.txt "added by hand"
  run release_in "$proj" status v1.0.1
  assert_state object pending
  grep -qF "it does not name extra.txt" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  rm "$assets/extra.txt"
  # A GitHub digest that disagrees with SHA256SUMS, and one that is missing.
  zeros >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.1.demo-x86.tar.gz"
  run release_in "$proj" status v1.0.1
  assert_state object pending
  grep -qF "demo-x86.tar.gz's GitHub digest is $(printf '%064d' 0), and SHA256SUMS says $(sha256_of "$assets/demo-x86.tar.gz")" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  printf 'none\n' >"$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.1.demo-x86.tar.gz"
  run release_in "$proj" status v1.0.1
  assert_state object pending
  grep -qF "demo-x86.tar.gz has no GitHub digest to compare with" <<<"$(row_of object)" || fail "the object row: $(row_of object)"
  rm "$DEVBIN_TEST_TMPDIR/gh.digest.v1.0.1.demo-x86.tar.gz"
  # A read that fails is UNREADABLE, never pending and never already.
  : >"$DEVBIN_TEST_TMPDIR/gh.fail.assets"
  run release_in "$proj" status v1.0.1
  [ "$status" -eq 1 ] || fail "status exit $status with an unreadable the object row"
  assert_state object UNREADABLE
  rm "$DEVBIN_TEST_TMPDIR/gh.fail.assets"
  # Status downloaded no artifact and wrote nothing to the object.
  [ "$(gh_calls '^gh run download')" -eq "$calls" ] || fail "status downloaded the run's artifacts"
  [ "$(gh_calls '^gh release \(upload\|create\|edit\|delete\)')" -eq "$writes" ] || fail "status wrote to the release object"
  run release_in "$proj" status v1.0.1
  assert_state object already
}
