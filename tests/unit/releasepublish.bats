#!/usr/bin/env bats
# releasepublish.bats - a release made public as its snapshot, by its cut,
# through CI on that very commit (issue 0240, ST0010, ST0011 WP02b-2)
#
# A project that declares release.publish.url publishes a snapshot, never its
# workroom, and its cut does it: the legs step makes S, the release commit's
# snapshot, and pushes it to candidate/<tag> at the url, where ci.query reads
# it by that ref; once every leg is green the push step pushes the release to
# release.remotes, then fast-forwards the publish branch at the url to S and
# tags S, lightweight, each read back, and the candidate is deleted. $PUB, an
# empty bare repository, stands in for the public repository, and the
# fixture's ci.query (ci_query_decl) answers what each arm says. Nothing here
# reaches a network: a url naming a GitHub repository is refused before it is
# read.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  PUB="$DEVBIN_TEST_TMPDIR/public.git"
  # The legs loop's rest, so a cut waiting on its local gates reads again
  # within a second of their end.
  export DEVBIN_RELEASE_POLL_SECONDS=1
}
teardown() { devbin_teardown; }

SNAP_AUTHOR="Snap Shot <snap@example.com>"

# publish_block <url> [all] -- a publishing demo's release: block: the probe
# gate, object: none, the fixture's ci.query at a wait of 0s, the snapshot keys
# over tests/shipped.paths, and release.publish.url <url>; and release.remotes
# naming `local`, unless the second word is `all`, which leaves it undeclared,
# so a cut pushes to every remote.
publish_block() {
  [ "${2:-}" = all ] || printf '  remotes:\n    - local\n'
  printf '  gates:\n    - probe\n  object: none\n%s\n' "$(ci_query_decl 0s)"
  printf '  snapshot:\n    list: tests/shipped.paths\n    author: "%s"\n' "$SNAP_AUTHOR"
  printf '  publish:\n    url: %s' "$1"
}

# publish_project [<url>] [all] -- cut_project's demo, publishing
# (publish_block) to <url>, by default $PUB, an empty bare repository standing
# in for the public one. Its shipped list names the version, the changelog and
# the README, committed before the cut so the release commit carries it, and
# `local`, a bare repository, holds main and v1.0.0, as origin does.
publish_project() {
  local proj
  git init -q --bare -b main "$PUB"
  proj="$(cut_project "$(publish_block "${1:-$PUB}" "${2:-}")")"
  mkdir -p "$proj/tests"
  printf 'VERSION\nCHANGELOG.md\nREADME.md\n' >"$proj/tests/shipped.paths"
  git -C "$proj" add tests/shipped.paths
  git -C "$proj" commit -qm "the shipped list"
  git -C "$proj" push -q origin main
  git init -q --bare -b main "$DEVBIN_TEST_TMPDIR/local.git"
  git -C "$proj" remote add local "$DEVBIN_TEST_TMPDIR/local.git"
  git -C "$proj" push -q local main v1.0.0
  printf '%s\n' "$proj"
}

# cut_v101 <proj> -- `run` the cut of v1.0.1, given --yes.
cut_v101() { run release_in "$1" v1.0.1 --yes; }

# ci_none_then <line> -- the query answers none on its first ask, as CI does
# for a commit it has no run of before the candidate is pushed, then <line> on
# every ask after it.
ci_none_then() { ci_answers "$(printf 'none\tno run yet')" "$1"; }

# asked_shas -- each sha the query was asked about, in order, one per line.
asked_shas() { awk '{ print $1 }' "$DEVBIN_TEST_TMPDIR/ci.calls"; }

# pub_at <ref> -- the sha $PUB's <ref> is at, or nothing when it has no such ref.
pub_at() { git -C "$PUB" rev-parse -q --verify "$1" 2>/dev/null || true; }

# pub_fingerprint -- every ref $PUB holds and every object in it: what any push
# there would change.
pub_fingerprint() {
  git -C "$PUB" for-each-ref --format='%(refname) %(objectname)' &&
    git -C "$PUB" cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype)'
}

# an_unrelated_commit -- a commit no release made, in a repository of its own at
# $DEVBIN_TEST_TMPDIR/other, its sha printed: what a public ref another hand
# moved holds.
an_unrelated_commit() {
  local other="$DEVBIN_TEST_TMPDIR/other"
  git init -q -b main "$other"
  git -C "$other" -c user.name=o -c user.email=o@o commit -q --allow-empty -m other
  git -C "$other" rev-parse HEAD
}

# no_publish_yet -- the public main and tag are not there.
no_publish_yet() {
  [ -z "$(pub_at refs/heads/main)" ] || fail "the public main moved: $(pub_at refs/heads/main)"
  [ -z "$(pub_at refs/tags/v1.0.1)" ] || fail "the public v1.0.1 was pushed: $(pub_at refs/tags/v1.0.1)"
}

# snapshot_of_head <proj> -- the sha of the snapshot release snapshot makes of
# <proj>'s HEAD, the release commit a cut made, in a new directory at
# $DEVBIN_TEST_TMPDIR/look: the commit the cut's own snapshot is, made on the
# same public tip.
snapshot_of_head() {
  local out
  out="$(PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" devbin_run "$1" release snapshot --commit HEAD "$DEVBIN_TEST_TMPDIR/look")" ||
    fail "release snapshot of HEAD failed: $out"
  sed -n 's/^  commit  //p' <<<"$out"
}

# ============================================================================
# THE CUT, WITH AND WITHOUT release.publish.url
# ============================================================================

@test "a project without publish.url cuts with no snapshot, candidate or publish step: no such row, and the release pushed and made (0240, ST0011 WP02b-2)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  local s rel
  for s in snapshot candidate publish; do
    [ "$(state_of "$s")" = "(no row $s)" ] || fail "a cut still prints a $s row: $(row_of "$s")"
  done
  assert_state push done
  assert_state object done
  assert_output_contains "v1.0.1 is released"
  rel="$(git -C "$proj" rev-parse 'refs/tags/v1.0.1^{commit}')"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" = "$rel" ] || fail "origin's main is not the release commit"
}

@test "a publishing cut's dry run plans the candidate's snapshot, the push to local alone and the public branch and tag, writes nothing public, and asks no query before the release commit exists (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local before
  before="$(pub_fingerprint)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state legs would
  assert_state push would
  [[ "$(row_of push)" == *"local commit tag; $PUB: fast-forward main to the snapshot of the release commit the commit step makes, and tag v1.0.1 at it, lightweight"* ]] ||
    fail "the push row does not plan local and the public repository: $(row_of push)"
  [[ "$(row_of push)" != *origin* ]] || fail "the push row plans a push to origin, which release.remotes leaves out: $(row_of push)"
  [[ "$(row_of confirm)" == *"push the snapshot of the release commit the commit step makes to candidate/v1.0.1 at $PUB, for CI"* ]] ||
    fail "the confirm row does not name the candidate's push: $(row_of confirm)"
  [[ "$(row_of confirm)" == *"make the snapshot public at $PUB"* ]] || fail "the confirm row does not name the public side: $(row_of confirm)"
  [[ "$(row_of confirm)" != *origin* ]] || fail "the confirm row plans a push to origin: $(row_of confirm)"
  [ "$(pub_fingerprint)" = "$before" ] || fail "a dry run wrote to the public repository"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "a dry run with no release commit asked the query"
}

# AT-2.8
@test "a publishing cut pushes the snapshot, never a workroom commit, to candidate/<tag> for CI read by that ref, then once every leg is green pushes the release to local alone, moves the public main, tags it lightweight, each read back, and deletes the candidate (0240, AC-2.3, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local origin_before
  origin_before="$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)"
  # Each ask of the query records the public refs as they stood when asked.
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
printf 'ask %s\n' "\${DEVBIN_RELEASE_TAG-<unset>}" >>"$DEVBIN_TEST_TMPDIR/at.ci"
git -C "$PUB" for-each-ref --format='%(refname) %(objectname)' >>"$DEVBIN_TEST_TMPDIR/at.ci"
SH
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_success
  assert_state legs done
  assert_state push done
  local snap rel want got all reachable at_green
  snap="$(pub_at refs/heads/main)"
  rel="$(git -C "$proj" rev-parse 'refs/tags/v1.0.1^{commit}')"
  [ -n "$snap" ] || fail "the public main is not there"
  [ "$(git -C "$PUB" cat-file -t refs/tags/v1.0.1)" = commit ] || fail "the public v1.0.1 is not lightweight"
  [ "$(pub_at refs/tags/v1.0.1)" = "$snap" ] || fail "the public v1.0.1 is not at the snapshot"
  [ -z "$(pub_at refs/heads/candidate/v1.0.1)" ] || fail "the candidate branch is still there"
  # THE SNAPSHOT, NEVER A WORKROOM COMMIT: made under the snapshot's identity,
  # its tree the release commit's files over the list, and no object in the
  # public repository but what it reaches.
  [ "$snap" != "$rel" ] || fail "the release commit itself went public"
  if git -C "$PUB" cat-file -e "$rel" 2>/dev/null; then fail "the workroom's release commit reached the public repository"; fi
  [ "$(git -C "$PUB" log -1 --format='%an <%ae>%n%cn <%ce>' "$snap")" = "$SNAP_AUTHOR"$'\n'"$SNAP_AUTHOR" ] ||
    fail "the public main is not made by the snapshot's identity"
  want="$(git -C "$proj" ls-tree -r "$rel" -- VERSION CHANGELOG.md README.md)"
  got="$(git -C "$PUB" ls-tree -r "$snap")"
  [ -n "$want" ] && [ "$got" = "$want" ] || fail "the snapshot's tree is not the release commit's files over the list:
--- want
$want
--- got
$got"
  all="$(git -C "$PUB" cat-file --batch-all-objects --batch-check='%(objectname)' | LC_ALL=C sort)"
  reachable="$(git -C "$PUB" rev-list --objects --all | cut -d' ' -f1 | LC_ALL=C sort)"
  [ -n "$all" ] && [ "$all" = "$reachable" ] || fail "the public repository holds objects the snapshot does not reach"
  # THE WORKROOM'S RELEASE WENT TO local ALONE, release.remotes leaving origin out.
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/local.git" rev-parse refs/heads/main)" = "$rel" ] || fail "local's main is not the release commit"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)" = "$origin_before" ] || fail "the cut pushed to origin, which release.remotes leaves out"
  # CI WAS READ ON THE SNAPSHOT, BY THE CANDIDATE'S REF, BEFORE ANYTHING PUBLIC
  # MOVED: every ask about the snapshot under that ref, and the green one while
  # the public repository held the candidate alone.
  [ -z "$(asked_shas | grep -v -x -F "$snap")" ] || fail "the query was asked about another commit than the snapshot: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  grep -q -x -F "$snap tag=candidate/v1.0.1" "$DEVBIN_TEST_TMPDIR/ci.calls" ||
    fail "the query was not asked about the snapshot by its candidate ref: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  at_green="$(awk '/^ask / { n++; next } n == 2' "$DEVBIN_TEST_TMPDIR/at.ci")"
  [ "$at_green" = "refs/heads/candidate/v1.0.1 $snap" ] || fail "when CI read green the public repository held: $at_green"
}

# AT-2.8
@test "a red candidate makes nothing public and tags nothing: the legs step stops naming the run, and the candidate is deleted (0240, AC-2.3, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local local_before
  local_before="$(git -C "$DEVBIN_TEST_TMPDIR/local.git" for-each-ref)"
  ci_none_then "$(printf 'failed\trun 42')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "candidate is red"
  assert_output_contains "run 42"
  no_publish_yet
  [ -z "$(pub_at refs/heads/candidate/v1.0.1)" ] || fail "the red candidate was not deleted"
  if git -C "$proj" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then fail "a red candidate's cut made the tag"; fi
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/local.git" for-each-ref)" = "$local_before" ] || fail "a red candidate's cut pushed to local"
}

@test "a candidate run still going past ci.wait makes nothing public, and the cut run again reads CI on the same snapshot again and publishes it (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  ci_none_then "$(printf 'pending\trun 9')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "not green within 0s (ci.wait)"
  assert_output_contains "run 9"
  no_publish_yet
  local first
  first="$(asked_shas | sed -n '$p')"
  [ -n "$first" ] || fail "the query was never asked"
  ci_none_then "$(printf 'green\trun 9')"
  cut_v101 "$proj"
  assert_success
  [ "$(asked_shas | sed -n '$p')" = "$first" ] || fail "the cut run again read CI on another commit"
  [ "$(pub_at refs/heads/main)" = "$first" ] || fail "the cut run again published another commit than the one CI read"
  [ "$(pub_at refs/tags/v1.0.1)" = "$first" ] || fail "the tag is not at the snapshot CI read"
}

@test "a verdict that cannot be read, from a query that fails or one that answers no verdict, makes nothing public (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  printf 'echo "gh: HTTP 502" >&2; exit 4\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "HTTP 502"
  no_publish_yet
  rm -f "$DEVBIN_TEST_TMPDIR/ciq.sh"
  ci_answers "success"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains '"success", which is not a verdict'
  no_publish_yet
}

@test "a publishing cut refuses at pre-flight to push to a remote that names the publish repository, naming it, and writes nothing (0240)" {
  # origin names t/demo, and release.remotes is left out, so a cut pushes to it.
  proj="$(publish_project https://github.com/t/demo.git all)"
  local before
  before="$(fingerprint "$proj")"
  run release_in "$proj" v1.0.1 --yes
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "remote origin names t/demo, the repository release.publish.url names"
  [ ! -s "$DEVBIN_TEST_TMPDIR/gate.calls" ] || fail "a gate ran after pre-flight refused"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refused cut wrote something"
}

@test "a publishing cut refuses at pre-flight to push to a remote whose url names a host and no OWNER/NAME that can be read, since whether it is the public repository cannot be told, and pushes nothing (0240)" {
  # release.remotes is left out, so the cut would push to every remote, mirror
  # among them: a url whose path is no OWNER/NAME could be the public repository.
  proj="$(publish_project "" all)"
  git -C "$proj" remote add mirror https://gitlab.com/a/b/c.git
  local before pub_before local_before origin_before
  before="$(fingerprint "$proj")"
  pub_before="$(pub_fingerprint)"
  local_before="$(git -C "$DEVBIN_TEST_TMPDIR/local.git" for-each-ref)"
  origin_before="$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)"
  run release_in "$proj" v1.0.1 --yes
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "whether remote mirror names the repository release.publish.url names cannot be told"
  assert_output_contains "a cut never pushes the workroom where that is not known"
  [ ! -s "$DEVBIN_TEST_TMPDIR/gate.calls" ] || fail "a gate ran after pre-flight refused"
  [ "$(pub_fingerprint)" = "$pub_before" ] || fail "the refused cut wrote to the public repository"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/local.git" for-each-ref)" = "$local_before" ] || fail "the refused cut pushed to local"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)" = "$origin_before" ] || fail "the refused cut pushed to origin"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refused cut wrote something"
}

@test "a publishing cut refuses at pre-flight any remote of the project that names the publish repository, one it does not push to and through an ssh host alias too, reading nothing and writing nothing, and release status does not read it either (0240, ST0011 WP02b-2)" {
  # origin names t/demo over https, and release.remotes leaves it out; this url
  # names it through a host alias and in another case, which GitHub reads as
  # one repository.
  proj="$(publish_project 'git@gh-alias:T/Demo.git')"
  local before
  before="$(fingerprint "$proj")"
  cut_v101 "$proj"
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "this project's remote origin names t/demo, the repository release.publish.url names"
  # Never read: a read would have tried the alias's host and said it did not answer.
  refute_output_contains "did not answer"
  [ ! -s "$DEVBIN_TEST_TMPDIR/gate.calls" ] || fail "a gate ran after pre-flight refused"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote something"
  # release status does not read it either: its push row cannot say.
  run release_in "$proj" status v1.0.1
  [ "$status" -eq 1 ] || fail "want exit 1, got $status: $output"
  assert_state push UNREADABLE
  assert_output_contains "is not read: this project's remote origin names t/demo"
  refute_output_contains "did not answer"
}

@test "a publishing cut refuses at pre-flight a remote whose pushurl alone names the publish repository, naming it, and writes nothing (0240, ST0011 WP02b-2)" {
  proj="$(publish_project https://github.com/t/public.git)"
  git -C "$proj" remote add mirror "$DEVBIN_TEST_TMPDIR/mirror.git"
  git -C "$proj" config remote.mirror.pushurl ssh://git@github.com/t/public.git
  local before
  before="$(fingerprint "$proj")"
  cut_v101 "$proj"
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "this project's remote mirror names t/public, the repository release.publish.url names"
  refute_output_contains "did not answer"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote something"
}

@test "a public tag already at another commit is refused at the legs step, before anything is pushed or the query asked, a tag being never moved (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local x before
  x="$(an_unrelated_commit)"
  git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/tags/v1.0.1"
  before="$(pub_fingerprint)"
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "carries v1.0.1 at ${x:0:12}, and this release's snapshot is"
  assert_output_contains "a tag is never moved -- nothing pushed"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refusal wrote to the public repository"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "CI was asked about a snapshot that cannot be published"
}

@test "a candidate ref at the public repository holding another commit stops the cut at the legs step, its push refused and nothing forced, and the ref is left as it is, named (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local x before
  x="$(an_unrelated_commit)"
  git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/heads/candidate/v1.0.1"
  before="$(pub_fingerprint)"
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "the candidate did not start"
  assert_output_contains "it holds ${x:0:12}, not this release's"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refused candidate changed the public repository"
}

@test "a publish branch that moves while CI runs is never forced: the push step stops at the public repository, and the public tag is not pushed (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local x
  x="$(an_unrelated_commit)"
  # The ask made once the candidate is at the public repository moves the
  # public main elsewhere.
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
if git -C "$PUB" rev-parse -q --verify refs/heads/candidate/v1.0.1 >/dev/null; then git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/heads/main"; fi
SH
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs done
  assert_state push FAILED
  assert_output_contains "is at ${x:0:12}, and the snapshot was made on no parent, so it cannot fast-forward, and nothing is forced"
  [ "$(pub_at refs/heads/main)" = "$x" ] || fail "main was moved over another commit"
  [ -z "$(pub_at refs/tags/v1.0.1)" ] || fail "the tag was pushed though main could not follow"
}

@test "a tag another hand pushes while CI runs is refused at the push step, and the public main does not move (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local x
  x="$(an_unrelated_commit)"
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
if git -C "$PUB" rev-parse -q --verify refs/heads/candidate/v1.0.1 >/dev/null; then git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/tags/v1.0.1"; fi
SH
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs done
  assert_state push FAILED
  assert_output_contains "carries v1.0.1 at ${x:0:12}, not at the snapshot"
  [ -z "$(pub_at refs/heads/main)" ] || fail "main moved for a tag that could not follow it"
}

@test "a finished publishing cut run again finds its snapshot public: nothing to ask about, no leg re-run, and nothing pushed (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_success
  local before snap
  snap="$(pub_at refs/heads/main)"
  [ -n "$snap" ] && [ "$(pub_at refs/tags/v1.0.1)" = "$snap" ] || fail "the first cut did not make its snapshot public"
  before="$(pub_fingerprint)"
  cut_v101 "$proj"
  assert_success
  assert_state confirm "not re-run"
  assert_state legs "not re-run"
  assert_state push already
  [[ "$(row_of push)" == *"main and v1.0.1 are at the snapshot ${snap:0:12}"* ]] || fail "the push row does not find the snapshot public: $(row_of push)"
  [ "$(pub_fingerprint)" = "$before" ] || fail "a finished cut run again wrote to the public repository"
}

@test "a cut resumed after the public repository refused its tag reads CI on the snapshot again, finds the public main at it, and pushes the tag at that snapshot (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  # THE PUBLIC REPOSITORY REFUSES TAGS for the first cut, which stops at the
  # push step with the public main at the snapshot and no public tag.
  # shellcheck disable=SC2016 # the hook's own $r, expanded when it runs
  printf '#!/bin/sh\nwhile read -r o n r; do case "$r" in refs/tags/*) echo "the fixture refuses tags" >&2; exit 1 ;; esac; done\n' >"$PUB/hooks/pre-receive"
  chmod +x "$PUB/hooks/pre-receive"
  ci_none_then "$(printf 'green\trun 8')"
  cut_v101 "$proj"
  assert_failure
  assert_state push FAILED
  assert_output_contains "the fixture refuses tags"
  local snap asks
  snap="$(pub_at refs/heads/main)"
  [ -n "$snap" ] || fail "the public main did not move before its tag was refused"
  [ -z "$(pub_at refs/tags/v1.0.1)" ] || fail "the refused tag is there"
  rm -f "$PUB/hooks/pre-receive"
  asks="$(grep -c . "$DEVBIN_TEST_TMPDIR/ci.calls")"
  ci_answers "$(printf 'green\trun 8')"
  cut_v101 "$proj"
  assert_success
  [ "$(grep -c . "$DEVBIN_TEST_TMPDIR/ci.calls")" -gt "$asks" ] || fail "the resumed cut did not read CI on the candidate again"
  [ "$(asked_shas | sed -n '$p')" = "$snap" ] || fail "the resumed cut read CI on another commit than the public main"
  [[ "$(row_of push)" == *"main was at ${snap:0:12} already"* ]] || fail "the public main was moved again: $(row_of push)"
  [ "$(pub_at refs/tags/v1.0.1)" = "$snap" ] || fail "the tag is not at the snapshot"
  [ -z "$(pub_at refs/heads/candidate/v1.0.1)" ] || fail "the candidate was not deleted"
}

@test "a second release is made on the first: its snapshot's parent is the public tip, main fast-forwards, a cut run again finds it, release status reads the first as public, and the first release cut again is refused as public already (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_success
  local first second before
  first="$(pub_at refs/heads/main)"
  awk 'done == 0 && /^## \[/ { print "## [1.0.2] - Unreleased"; print ""; print "- third"; print ""; done = 1 } { print }' \
    "$proj/CHANGELOG.md" >"$proj/CHANGELOG.md.new" && mv "$proj/CHANGELOG.md.new" "$proj/CHANGELOG.md"
  git -C "$proj" commit -qam "notes for 1.0.2"
  ci_none_then "$(printf 'green\trun 8')"
  run release_in "$proj" v1.0.2 --yes
  assert_success
  second="$(pub_at refs/heads/main)"
  [ -n "$second" ] && [ "$second" != "$first" ] || fail "main did not move to a second snapshot"
  [ "$(git -C "$PUB" rev-parse "$second^")" = "$first" ] || fail "the second snapshot is not made on the first"
  [ "$(pub_at refs/tags/v1.0.2)" = "$second" ] || fail "v1.0.2 is not at the second snapshot"
  [ "$(pub_at refs/tags/v1.0.1)" = "$first" ] || fail "v1.0.1 moved"
  # Found again on a tip that has a parent.
  before="$(pub_fingerprint)"
  run release_in "$proj" v1.0.2 --yes
  assert_success
  assert_state push already
  [ "$(pub_fingerprint)" = "$before" ] || fail "the second release cut again wrote to the public repository"
  # release status reads the first as public, its tag in main's history.
  run release_in "$proj" status v1.0.1
  assert_success
  assert_state push already
  [[ "$(row_of push)" == *"$PUB has v1.0.1 at ${first:0:12}, in the history of main, at ${second:0:12}: public already"* ]] ||
    fail "status does not read the first release as public: $(row_of push)"
  # The first, cut again, is public already, in main's history.
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "v1.0.1 is public already, at ${first:0:12}, in the history of main"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the first release cut again wrote to the public repository"
}

@test "a public tag already at the snapshot does not stand for CI: with main still to move, a red candidate moves nothing (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  # A first cut stops red at the legs step, so the release commit is there and
  # nothing is public.
  ci_none_then "$(printf 'failed\trun 4')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  local snap
  snap="$(snapshot_of_head "$proj")"
  [ -n "$snap" ] || fail "release snapshot printed no commit"
  # Another hand pushed the tag at it; the branch has not moved.
  git -C "$DEVBIN_TEST_TMPDIR/look" push -q "$PUB" "$snap:refs/tags/v1.0.1"
  ci_none_then "$(printf 'failed\trun 5')"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  assert_output_contains "run 5"
  [ -z "$(pub_at refs/heads/main)" ] || fail "main moved with CI red on the candidate"
  [ "$(asked_shas | sed -n '$p')" = "$snap" ] || fail "CI was not asked about the snapshot the public tag names"
}

@test "a publishing cut's dry run once the release commit exists makes the snapshot in its scratch, asks the query about it, and pushes nothing (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  ci_none_then "$(printf 'failed\trun 4')"
  cut_v101 "$proj"
  assert_failure
  local before snap
  before="$(pub_fingerprint)"
  rm -f "$DEVBIN_TEST_TMPDIR/ci.calls"
  ci_answers "$(printf 'none\tno run yet')"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  assert_state legs would
  [ "$(pub_fingerprint)" = "$before" ] || fail "a dry run wrote to the public repository"
  snap="$(snapshot_of_head "$proj")"
  [ -n "$snap" ] || fail "release snapshot printed no commit"
  [ "$(asked_shas | sed -n '$p')" = "$snap" ] || fail "the dry run did not ask the query about the snapshot: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls" 2>/dev/null)"
}

# ============================================================================
# release status, AND THE RETIRED VERB
# ============================================================================

@test "release status without publish.url prints no snapshot, candidate or publish row (0240, ST0011 WP02b-2)" {
  proj="$(cut_project)"
  run release_in "$proj" status v1.0.1
  assert_success
  local s
  for s in snapshot candidate publish; do
    [ "$(state_of "$s")" = "(no row $s)" ] || fail "status prints a $s row: $(row_of "$s")"
  done
}

@test "release status under publish.url names the public repository on its push row: pending while the snapshot is not public there, already once it is (0240, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  run release_in "$proj" status v1.0.1
  assert_success
  assert_state push pending
  [[ "$(row_of push)" == *"$PUB takes the release's snapshot, and has it not yet"* ]] ||
    fail "the push row does not name the public repository's work: $(row_of push)"
  ci_none_then "$(printf 'green\trun 7')"
  cut_v101 "$proj"
  assert_success
  run release_in "$proj" status v1.0.1
  assert_success
  assert_state push already
  assert_state confirm "not re-run"
  [[ "$(row_of push)" == *"$PUB has main and v1.0.1 at"* ]] || fail "the push row does not name the public repository: $(row_of push)"
  local s
  for s in snapshot candidate publish; do
    [ "$(state_of "$s")" = "(no row $s)" ] || fail "status prints a $s row: $(row_of "$s")"
  done
}

@test "release publish is retired: refused before anything acts, naming the cut that publishes now, and gone from the usage (AC-2.4, ST0011 WP02b-2)" {
  proj="$(publish_project)"
  local before
  before="$(fingerprint "$proj")"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_output_contains "release publish is retired: a cut under release.publish.url pushes the release commit's snapshot to its candidate branch, and makes it public once every leg is green"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refused verb wrote something"
  run release_in "$proj" --help
  assert_success
  refute_output_contains "release publish"
  refute_output_contains "--expect"
}

@test "publish.candidate needs ci.query, which a cut's candidate reads in either shape, and must hold the tag and more (0240, ST0011 WP02b)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    cfg_load_string <<YAML
project:
  name: demo
release:
$(printf '%b' "$block")
YAML
    run cfg_validate </dev/null
    [ "$status" -ne 0 ] || fail "accepted: $block"
    assert_output_contains "$want"
  done <<'EOF2'
  ci:\n    query: "-"\n  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    candidate: rc/{tag}|release.publish.candidate is read only where a cut has a candidate, and release.ci.query is -, the opt-out
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git\n    candidate: rc|release.publish.candidate: "rc" must be a branch name holding {tag}
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git\n    candidate: "{tag}"|release.publish.candidate: "{tag}" must be a branch name holding {tag} and more
EOF2
  # ACCEPTED UNDER publish.url (Done when 5): a query is asked at the
  # candidate, so it validates, as a candidate template does.
  cfg_load_string <<'YAML'
project:
  name: demo
release:
  ci:
    query: q
  snapshot:
    list: x
    author: "A B <a@b>"
  publish:
    url: /srv/p.git
    candidate: rc/{tag}
YAML
  run cfg_validate
  [ "$status" -eq 0 ] || fail "the publishing block was refused: $output"
}

# ============================================================================
# WHAT NAMES THE PUBLISH REPOSITORY
# ============================================================================

@test "a remote names the publish repository however its path is spelled, or as the same local path, and one whose url says too little to tell is refused as unknown (0240)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/release.notes
  . "$DEVBIN_LIB_DIR/release.notes"
  # shellcheck source=lib/release.steps
  . "$DEVBIN_LIB_DIR/release.steps"
  local w="$DEVBIN_TEST_TMPDIR/naming" url remote want rc out
  git init -q --bare -b main "$PUB"
  mkdir -p "$DEVBIN_TEST_TMPDIR/elsewhere"
  while IFS='|' read -r url remote want; do
    [ -n "$url" ] || continue
    rm -rf "$w"
    git init -q -b main "$w" </dev/null
    git -C "$w" remote add r "$remote" </dev/null
    rc=0
    out="$(cd "$w" && release_remote_naming "$url" </dev/null)" || rc=$?
    [ "$rc" = "${want%%:*}" ] || fail "release.publish.url $url, remote $remote: rc $rc, want ${want%%:*} ($out)"
    [[ "$out" == *"${want#*:}"* ]] || fail "release.publish.url $url, remote $remote: said [$out], want [${want#*:}]"
  done <<EOF2
https://github.com/t/pub.git|git@github.com:/t/pub.git|0:r	t/pub
https://github.com/t/pub.git|https://github.com//t/pub.git|0:r	t/pub
https://github.com/t/pub.git|https://gitlab.com/a/b/c.git|2:remote r's url https://gitlab.com/a/b/c.git names a host and no OWNER/NAME that can be read
$PUB|$DEVBIN_TEST_TMPDIR/elsewhere/../public.git|0:r	$PUB
EOF2
}

# ============================================================================
# THE SNAPSHOT'S TRIGGER, READ BEFORE ANYTHING IS PUSHED (ST0011 WP-02c)
# ============================================================================

# builtin_publish_project <shipped-list> <branches> [<paths>] --
# publish_project's demo with no ci.query declared, so the built-in query reads
# its candidate, the snapshot, and a .github/workflows/tests.yml whose push
# trigger takes <branches>, filtered on <paths> where given
# (write_tests_workflow); <shipped-list> is tests/shipped.paths' lines,
# \n-separated.
builtin_publish_project() {
  local proj
  git init -q --bare -b main "$PUB"
  proj="$(cut_project "$(printf '  remotes:\n    - local\n  gates:\n    - probe\n  object: none\n  ci:\n    wait: 0s\n  snapshot:\n    list: tests/shipped.paths\n    author: "%s"\n  publish:\n    url: %s' "$SNAP_AUTHOR" "$PUB")")"
  mkdir -p "$proj/tests"
  printf '%b\n' "$1" >"$proj/tests/shipped.paths"
  write_tests_workflow "$proj" "$2" "${3:-}"
  git -C "$proj" add -A
  git -C "$proj" commit -qm "the shipped list and the workflow"
  git -C "$proj" push -q origin main
  git init -q --bare -b main "$DEVBIN_TEST_TMPDIR/local.git"
  git -C "$proj" remote add local "$DEVBIN_TEST_TMPDIR/local.git"
  git -C "$proj" push -q local main v1.0.0
  printf '%s\n' "$proj"
}

@test "a publishing cut asks, once it has made the snapshot and before anything is pushed, whether the snapshot's push starts the workflow, read at the release commit with the files the snapshot changes: one that does not stops it at the legs step with nothing public (ST0011 WP-02c)" {
  local before
  proj="$(builtin_publish_project 'VERSION\nCHANGELOG.md\nREADME.md\n.github/workflows/tests.yml' "main")"
  before="$(pub_fingerprint)"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  [[ "$(row_of legs)" == *"the snapshot's push, read at the release commit "*"ci-state --fires answers quiet"*"nothing pushed"* ]] ||
    fail "the legs row does not refuse the snapshot whose push starts no run: $(row_of legs)"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refused cut wrote to the public repository"
}

@test "a publishing cut whose snapshot's push starts the workflow, its paths: filter met by the files the snapshot changes, VERSION among them, passes that check and pushes its candidate (ST0011 WP-02c)" {
  proj="$(builtin_publish_project 'VERSION\nCHANGELOG.md\nREADME.md\n.github/workflows/tests.yml' "main, 'candidate/**'" "VERSION")"
  cut_v101 "$proj"
  # Past the check, the candidate is pushed and then read, here within ci.wait
  # 0s, so the cut stops at the legs step for want of a verdict, never at the
  # check. Asked with no files, a paths: filter answers unknown, which is
  # refused, so the pass says the snapshot's files were passed and read.
  [[ "$(row_of legs)" != *"the snapshot's push, read at the release commit"* ]] ||
    fail "the check refused a snapshot whose push starts the workflow: $(row_of legs)"
  assert_output_contains "pushed the candidate candidate/v1.0.1"
}

@test "a publishing cut refuses, before anything is pushed, a snapshot that does not carry the release commit's workflow unchanged, since its push could not be read at the release commit (ST0011 WP-02c)" {
  local before
  proj="$(builtin_publish_project 'VERSION\nCHANGELOG.md\nREADME.md' "main, 'candidate/**'")"
  before="$(pub_fingerprint)"
  cut_v101 "$proj"
  assert_failure
  assert_state legs FAILED
  [[ "$(row_of legs)" == *"does not carry "*"'s .github/workflows/tests.yml unchanged"*"nothing pushed"* ]] ||
    fail "the legs row does not refuse the snapshot that leaves the workflow out: $(row_of legs)"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refused cut wrote to the public repository"
}
