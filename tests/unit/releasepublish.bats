#!/usr/bin/env bats
# releasepublish.bats - a release made public as its snapshot, through CI on
# that very commit (issue 0240, ST0010)
#
# A project that declares release.publish.url cuts to release.remotes and stops
# after the push step, and `release publish <v>` makes the tag's snapshot
# public: pushed to candidate/<tag>, then, once ci.query reads green on its
# sha, the publish branch fast-forwarded and a lightweight tag pushed, each
# read back, and the candidate deleted. $PUB, an empty bare repository, stands
# in for the public repository, and the fixture's ci.query (ci_query_decl)
# answers what each arm says. Nothing here reaches a network: a url naming a
# GitHub repository is refused before it is read.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  PUB="$DEVBIN_TEST_TMPDIR/public.git"
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

# cut_v101 <proj> -- the cut of v1.0.1, with --yes, which must succeed.
cut_v101() {
  run release_in "$1" v1.0.1 --yes
  assert_success
}

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

# ============================================================================
# THE CUT, WITH AND WITHOUT release.publish.url
# ============================================================================

@test "a project without publish.url cuts as before: the snapshot, candidate and publish rows skipped, the release pushed and made (0240)" {
  proj="$(cut_project)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  local s rel
  for s in snapshot candidate publish; do
    assert_state "$s" skipped
    [[ "$(row_of "$s")" == *"no publish.url declared" ]] || fail "the $s row does not say why it is skipped: $(row_of "$s")"
  done
  assert_state push done
  assert_state object done
  assert_output_contains "v1.0.1 is released"
  rel="$(git -C "$proj" rev-parse 'refs/tags/v1.0.1^{commit}')"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" rev-parse refs/heads/main)" = "$rel" ] || fail "origin's main is not the release commit"
}

@test "a publishing project's dry-run cut plans its push to local alone, and its snapshot, candidate and publish rows wait on release publish (0240)" {
  proj="$(publish_project)"
  local before s
  before="$(pub_fingerprint)"
  run release_in "$proj" v1.0.1 --dry-run
  assert_success
  [[ "$(row_of push)" == *" local commit tag" ]] || fail "the push row does not plan the push to local: $(row_of push)"
  [[ "$(row_of push)" != *origin* ]] || fail "the push row plans a push to origin, which release.remotes leaves out: $(row_of push)"
  [[ "$(row_of confirm)" != *origin* ]] || fail "the confirm row plans a push to origin: $(row_of confirm)"
  for s in snapshot candidate publish; do
    assert_state "$s" pending
    [[ "$(row_of "$s")" == *"release publish v1.0.1" ]] || fail "the $s row does not name release publish: $(row_of "$s")"
  done
  for s in object after ci; do assert_state "$s" "not reached"; done
  [ "$(pub_fingerprint)" = "$before" ] || fail "a dry run wrote to the public repository"
}

@test "a publishing project's cut pushes to local alone and stops after the push, and the stand-in public repository receives nothing (0240)" {
  proj="$(publish_project)"
  # A ROUTE TO IT, which release.remotes leaves out: a cut that pushed to every
  # remote, as one did, would reach the public repository through it.
  git -C "$proj" remote add public "$PUB"
  local before origin_before s rel
  before="$(pub_fingerprint)"
  origin_before="$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)"
  run release_in "$proj" v1.0.1 --yes
  assert_success
  assert_state push done
  for s in snapshot candidate publish; do assert_state "$s" pending; done
  for s in object after ci; do assert_state "$s" "not reached"; done
  assert_output_contains "nothing of it is public yet: bin/devbin release publish v1.0.1 makes its snapshot public"
  refute_output_contains "v1.0.1 is released"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the cut wrote to the public repository"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref)" = "$origin_before" ] || fail "the cut pushed to origin, which release.remotes leaves out"
  rel="$(git -C "$proj" rev-parse 'refs/tags/v1.0.1^{commit}')"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/local.git" rev-parse refs/heads/main)" = "$rel" ] || fail "local's main is not the release commit"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/local.git" rev-parse refs/tags/v1.0.1)" = "$(git -C "$proj" rev-parse refs/tags/v1.0.1)" ] ||
    fail "local does not carry the release tag"
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

# ============================================================================
# release publish
# ============================================================================

@test "release publish pushes the snapshot, never a workroom commit, to candidate/<tag>, then on green moves main and pushes a lightweight tag, each read back, and deletes the candidate (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  # Each ask of the query records the public refs as they stood when asked.
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
printf 'ask %s\n' "\${DEVBIN_RELEASE_TAG-<unset>}" >>"$DEVBIN_TEST_TMPDIR/at.ci"
git -C "$PUB" for-each-ref --format='%(refname) %(objectname)' >>"$DEVBIN_TEST_TMPDIR/at.ci"
SH
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  assert_state snapshot done
  assert_state confirm done
  assert_state candidate done
  assert_state publish done
  local snap rel want got all reachable at_ci
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
  # CI WAS READ BEFORE ANYTHING MOVED: about the snapshot, with no tag, while the
  # candidate held it and neither main nor the tag was there.
  [ "$(head -n 1 "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$snap tag=<unset>" ] ||
    fail "the first ask was not about the snapshot with no tag: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls")"
  [ "$(head -n 1 "$DEVBIN_TEST_TMPDIR/at.ci")" = "ask <unset>" ] || fail "the candidate's ask was not the first: $(cat "$DEVBIN_TEST_TMPDIR/at.ci")"
  at_ci="$(awk '/^ask / { n++; next } n == 1' "$DEVBIN_TEST_TMPDIR/at.ci")"
  [ "$at_ci" = "refs/heads/candidate/v1.0.1 $snap" ] || fail "when CI was read the public repository held: $at_ci"
}

@test "a red candidate moves neither main nor the tag, says why, and stays as the record of it (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  ci_answers "$(printf 'failed\trun 42')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains "ci.query answers failed for"
  assert_output_contains "run 42"
  assert_output_contains "main and v1.0.1 did not move"
  no_publish_yet
  local cand
  cand="$(pub_at refs/heads/candidate/v1.0.1)"
  [ -n "$cand" ] || fail "the red candidate was not kept"
  [ "$(git -C "$PUB" log -1 --format='%an <%ae>' "$cand")" = "$SNAP_AUTHOR" ] || fail "the candidate is not the snapshot"
  [ "$(state_of publish)" = "(no row publish)" ] || fail "the publish step ran after a red candidate: $(row_of publish)"
}

@test "a candidate run still going past ci.wait moves neither main nor the tag, and the same command run again reads CI again and publishes that candidate (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  ci_answers "$(printf 'pending\trun 9')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains "ci.query gave no verdict within 0s (ci.wait)"
  assert_output_contains "run 9"
  no_publish_yet
  local cand
  cand="$(pub_at refs/heads/candidate/v1.0.1)"
  [ -n "$cand" ] || fail "the candidate is not there"
  ci_answers "$(printf 'green\trun 9')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  [[ "$(row_of candidate)" == *"candidate/v1.0.1 holds ${cand:0:12} already"* ]] || fail "the re-run pushed the candidate again: $(row_of candidate)"
  [ "$(pub_at refs/heads/main)" = "$cand" ] || fail "the re-run published another commit than the one CI read"
  [ "$(pub_at refs/tags/v1.0.1)" = "$cand" ] || fail "the tag is not at the candidate CI read"
}

@test "a verdict that cannot be read, from a query that fails or one that answers no verdict, moves neither main nor the tag (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  printf 'echo "gh: HTTP 502" >&2; exit 4\n' >"$DEVBIN_TEST_TMPDIR/ciq.sh"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains "no verdict from ci.query for"
  assert_output_contains "HTTP 502"
  no_publish_yet
  rm -f "$DEVBIN_TEST_TMPDIR/ciq.sh"
  ci_answers "success"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains '"success", which is not a verdict'
  no_publish_yet
}

@test "--expect refuses a snapshot of any other sha, pushing nothing, and publishes the one release snapshot printed (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local other before snap
  other="$(printf '%040d' 0)"
  before="$(pub_fingerprint)"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes --expect "$other"
  assert_failure
  assert_state snapshot FAILED
  assert_output_contains "and --expect names $other"
  assert_output_contains "nothing pushed"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refusal wrote to the public repository"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "CI was asked about a snapshot --expect refused"
  # The sha release snapshot prints is the sha the publish makes.
  run release_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/look"
  assert_success
  snap="$(sed -n 's/^  commit  //p' <<<"$output")"
  [ -n "$snap" ] || fail "release snapshot printed no commit: $output"
  run release_in "$proj" publish v1.0.1 --yes --expect "$snap"
  assert_success
  assert_state publish done
  [ "$(pub_at refs/heads/main)" = "$snap" ] || fail "the publish did not publish the sha --expect named"
}

@test "release publish refuses at pre-flight a remote that names the publish repository through an ssh host alias, naming it, reading nothing and writing nothing (0240)" {
  # origin names t/demo over https; this url names it through a host alias and
  # in another case, which GitHub reads as one repository.
  proj="$(publish_project 'git@gh-alias:T/Demo.git')"
  cut_v101 "$proj"
  rm -rf "$proj/tmp/release"
  local before
  before="$(fingerprint "$proj")"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "this project's remote origin names t/demo, the repository release.publish.url names"
  # Never read: a read would have tried the alias's host and said it did not answer.
  refute_output_contains "did not answer"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote something"
}

@test "release publish refuses at pre-flight a remote whose pushurl alone names the publish repository, naming it, and writes nothing (0240)" {
  proj="$(publish_project https://github.com/t/public.git)"
  git -C "$proj" remote add mirror "$DEVBIN_TEST_TMPDIR/mirror.git"
  git -C "$proj" config remote.mirror.pushurl ssh://git@github.com/t/public.git
  cut_v101 "$proj"
  rm -rf "$proj/tmp/release"
  local before
  before="$(fingerprint "$proj")"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state pre-flight FAILED
  assert_output_contains "this project's remote mirror names t/public, the repository release.publish.url names"
  refute_output_contains "did not answer"
  rm -rf "$proj/tmp/release"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote something"
}

@test "a public tag already at another commit is refused before anything is pushed, and CI is not asked (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local x before
  x="$(an_unrelated_commit)"
  git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/tags/v1.0.1"
  before="$(pub_fingerprint)"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state publish FAILED
  assert_output_contains "carries v1.0.1 at ${x:0:12}, and this release's snapshot is"
  assert_output_contains "a tag is never moved -- nothing pushed"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refusal wrote to the public repository"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "CI was asked about a snapshot that cannot be published"
}

@test "a candidate branch holding another commit is refused before anything is pushed (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local x before
  x="$(an_unrelated_commit)"
  git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/heads/candidate/v1.0.1"
  before="$(pub_fingerprint)"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains "candidate/v1.0.1 at $PUB holds ${x:0:12}, not this release's snapshot"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the refusal wrote to the public repository"
}

@test "a publish branch that moves while CI runs is never forced: the publish step stops and the tag is not pushed (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local x
  x="$(an_unrelated_commit)"
  # The candidate's ask, the one with no tag, moves the public main elsewhere.
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
[ -n "\${DEVBIN_RELEASE_TAG-}" ] || git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/heads/main"
SH
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate done
  assert_state publish FAILED
  assert_output_contains "is at ${x:0:12}, and the snapshot was made on no parent, so it cannot fast-forward, and nothing is forced"
  [ "$(pub_at refs/heads/main)" = "$x" ] || fail "main was moved over another commit"
  [ -z "$(pub_at refs/tags/v1.0.1)" ] || fail "the tag was pushed though main could not follow"
}

@test "a finished publish run again finds the snapshot published, asks nothing and pushes nothing (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  local snap before
  snap="$(pub_at refs/heads/main)"
  before="$(pub_fingerprint)"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  [[ "$(row_of snapshot)" == *"${snap:0:12}"*"the tip of main is this snapshot already"* ]] || fail "the snapshot was not found published: $(row_of snapshot)"
  assert_state confirm "not re-run"
  assert_state candidate already
  assert_state publish already
  [ "$(pub_fingerprint)" = "$before" ] || fail "a re-run of a finished publish wrote to the public repository"
}

@test "release publish --dry-run makes the snapshot, asks nothing, and pushes nothing (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local before
  before="$(pub_fingerprint)"
  run release_in "$proj" publish v1.0.1 --dry-run
  assert_success
  assert_state snapshot done
  assert_state confirm would
  assert_state candidate would
  assert_state publish would
  assert_output_contains "dry run of v1.0.1 -- no step failed; the publish stops to ask at the confirm step"
  [ "$(pub_fingerprint)" = "$before" ] || fail "a dry run wrote to the public repository"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ci.calls" ] || fail "a dry run asked the query"
}

@test "release publish in a project without publish.url is refused, naming the key (0240)" {
  proj="$(cut_project)"
  run release_in "$proj" publish v1.0.0 --yes
  assert_failure
  assert_output_contains "release.publish.url is not declared, so this project publishes no snapshot"
}

@test "release status reads the snapshot, candidate and publish rows as skipped without publish.url (0240)" {
  proj="$(cut_project)"
  run release_in "$proj" status v1.0.1
  assert_success
  local s
  for s in snapshot candidate publish; do
    assert_state "$s" skipped
    [[ "$(row_of "$s")" == *"no publish.url declared" ]] || fail "the $s row does not say why: $(row_of "$s")"
  done
}

@test "release status reads the snapshot, candidate and publish rows as not read, naming release publish, under publish.url (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  run release_in "$proj" status v1.0.1
  assert_success
  local s
  for s in snapshot candidate publish; do
    assert_state "$s" "not read"
    [[ "$(row_of "$s")" == *"release publish v1.0.1"* ]] || fail "the $s row does not name release publish: $(row_of "$s")"
  done
  assert_state push already
  assert_state confirm "not re-run"
}

@test "under publish.url validation refuses ci.base, and publish.candidate needs publish.url and must hold the tag and more (0240)" {
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
  ci:\n    query: q\n    base: false\n  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git|release.ci.base is refused under release.publish.url
  ci:\n    query: q\n    base: true\n  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git|release.ci.base is refused under release.publish.url
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    candidate: rc/{tag}|release.publish.candidate is read only when release.publish.url is declared
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git\n    candidate: rc|release.publish.candidate: "rc" must be a branch name holding {tag}
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git\n    candidate: "{tag}"|release.publish.candidate: "{tag}" must be a branch name holding {tag} and more
  verbs:\n    - cut\n    - status\n    - snapshot\n  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/p.git|release.publish.url is declared, and release.verbs leaves out publish
EOF2
  # ACCEPTED UNDER publish.url (Done when 5): a query with ci.tag off and no
  # ci.base is asked at the candidate, so it validates, as a candidate template
  # does.
  cfg_load_string <<'YAML'
project:
  name: demo
release:
  ci:
    query: q
    tag: false
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

@test "release publish's arguments are read before anything acts: one version, and --expect a whole sha, for release publish alone (0240)" {
  proj="$(publish_project)"
  local before args want
  before="$(fingerprint "$proj")"
  while IFS='|' read -r args want; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086  # each line is an argument list
    run release_in "$proj" $args </dev/null
    assert_failure
    assert_output_contains "$want"
  done <<'EOF2'
publish|release publish needs a version
publish v1.0.1 v1.0.2|release publish takes one version, got 1.0.1 and v1.0.2
publish v1.0.1 --expect abc123|--expect takes the snapshot's whole sha, as release snapshot prints it, not abc123
publish v1.0.1 --expect|--expect takes the snapshot's whole sha
status v1.0.1 --expect 0000000000000000000000000000000000000000|--expect applies to release publish, not to release status
EOF2
  [ "$(fingerprint "$proj")" = "$before" ] || fail "a refused argument list wrote something"
  run release_in "$proj" --help
  assert_success
  assert_output_contains "release publish <vX.Y.Z> [--expect <sha>] [--dry-run] [--yes]"
}

# ============================================================================
# WHAT NAMES THE PUBLISH REPOSITORY, AND THE RELEASES AFTER THE FIRST
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

@test "a public tag already at the snapshot does not stand for CI: with main still to move, a red candidate moves nothing (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local snap
  run release_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/look"
  assert_success
  snap="$(sed -n 's/^  commit  //p' <<<"$output")"
  [ -n "$snap" ] || fail "release snapshot printed no commit: $output"
  # Another hand pushed the tag; the branch has not moved.
  git -C "$DEVBIN_TEST_TMPDIR/look" push -q "$PUB" "$snap:refs/tags/v1.0.1"
  ci_answers "$(printf 'failed\trun 5')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate FAILED
  assert_output_contains "ci.query answers failed for ${snap:0:12}"
  [ -z "$(pub_at refs/heads/main)" ] || fail "main moved with CI red on the candidate"
  [ "$(head -n 1 "$DEVBIN_TEST_TMPDIR/ci.calls")" = "$snap tag=<unset>" ] || fail "CI was not asked about the candidate: $(cat "$DEVBIN_TEST_TMPDIR/ci.calls" 2>/dev/null)"
}

@test "a resume with main moved and no tag pushed reads CI on the candidate again, then pushes the tag at the same snapshot (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local snap
  run release_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/look"
  assert_success
  snap="$(sed -n 's/^  commit  //p' <<<"$output")"
  [ -n "$snap" ] || fail "release snapshot printed no commit: $output"
  # A publish that stopped after main moved: the candidate and main hold the
  # snapshot, and the tag is not there.
  git -C "$DEVBIN_TEST_TMPDIR/look" push -q "$PUB" "$snap:refs/heads/candidate/v1.0.1" "$snap:refs/heads/main"
  ci_answers "$(printf 'green\trun 8')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  [[ "$(row_of snapshot)" == *"the tip of main is this snapshot already"* ]] || fail "the snapshot on the moved main was made again: $(row_of snapshot)"
  [[ "$(row_of candidate)" == *"holds ${snap:0:12} already"*"answers green"* ]] || fail "CI was not read on the candidate: $(row_of candidate)"
  [[ "$(row_of publish)" == *"main was at ${snap:0:12} already"* ]] || fail "main was moved again: $(row_of publish)"
  [ "$(pub_at refs/tags/v1.0.1)" = "$snap" ] || fail "the tag is not at the snapshot"
  [ -z "$(pub_at refs/heads/candidate/v1.0.1)" ] || fail "the candidate was not deleted"
}

@test "a second release is made on the first: its snapshot's parent is the public tip, main fast-forwards, a re-run finds it, and the first release run again is refused as public already (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_success
  local first second before
  first="$(pub_at refs/heads/main)"
  awk 'done == 0 && /^## \[/ { print "## [1.0.2] - Unreleased"; print ""; print "- third"; print ""; done = 1 } { print }' \
    "$proj/CHANGELOG.md" >"$proj/CHANGELOG.md.new" && mv "$proj/CHANGELOG.md.new" "$proj/CHANGELOG.md"
  git -C "$proj" commit -qam "notes for 1.0.2"
  run release_in "$proj" v1.0.2 --yes
  assert_success
  run release_in "$proj" publish v1.0.2 --yes
  assert_success
  second="$(pub_at refs/heads/main)"
  [ -n "$second" ] && [ "$second" != "$first" ] || fail "main did not move to a second snapshot"
  [ "$(git -C "$PUB" rev-parse "$second^")" = "$first" ] || fail "the second snapshot is not made on the first"
  [ "$(pub_at refs/tags/v1.0.2)" = "$second" ] || fail "v1.0.2 is not at the second snapshot"
  [ "$(pub_at refs/tags/v1.0.1)" = "$first" ] || fail "v1.0.1 moved"
  # Found again on a tip that has a parent.
  before="$(pub_fingerprint)"
  run release_in "$proj" publish v1.0.2 --yes
  assert_success
  [[ "$(row_of snapshot)" == *"${second:0:12}"*"on ${first:0:12}; the tip of main is this snapshot already"* ]] ||
    fail "the second snapshot was not found on its own parent: $(row_of snapshot)"
  assert_state publish already
  [ "$(pub_fingerprint)" = "$before" ] || fail "a re-run of the second publish wrote to the public repository"
  # The first, run again, is public already, in main's history.
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_output_contains "v1.0.1 is public already, at ${first:0:12}, in the history of main"
  [ "$(pub_fingerprint)" = "$before" ] || fail "the first release run again wrote to the public repository"
}

@test "a tag another hand pushes while CI runs is refused at the publish step, and main does not move (0240)" {
  proj="$(publish_project)"
  cut_v101 "$proj"
  local x
  x="$(an_unrelated_commit)"
  cat >"$DEVBIN_TEST_TMPDIR/ciq.sh" <<SH
[ -n "\${DEVBIN_RELEASE_TAG-}" ] || git -C "$DEVBIN_TEST_TMPDIR/other" push -q "$PUB" "$x:refs/tags/v1.0.1"
SH
  ci_answers "$(printf 'green\trun 7')"
  run release_in "$proj" publish v1.0.1 --yes
  assert_failure
  assert_state candidate done
  assert_state publish FAILED
  assert_output_contains "carries v1.0.1 at ${x:0:12}, not at the snapshot"
  [ -z "$(pub_at refs/heads/main)" ] || fail "main moved for a tag that could not follow it"
}
