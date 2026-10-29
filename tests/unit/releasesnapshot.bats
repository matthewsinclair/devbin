#!/usr/bin/env bats
# releasesnapshot.bats - `release snapshot`, the public snapshot's builder (issue 0239, ST0010)
#
# One commit, in a new repository, whose tree is exactly a workroom commit's
# tracked files over release.snapshot.list: held here to git's own reading of
# the same pathspecs, never to the builder's. Its parent is the publish branch's
# tip at release.publish.url, whose history must be snapshots; the same inputs
# give the same commit; and a refusal writes nothing, read through the release
# fixtures' fingerprint and a TMPDIR of the test's own, which the run's scratch
# must leave empty.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  init_colors off
}
teardown() { devbin_teardown; }

SNAP_AUTHOR="Snap Shot <snap@example.com>"
SNAP_LIST='# what ships
.gitattributes
bin/
docs/
tests/
VERSION
README.md

:(exclude)docs/private.md'
# The tagged commit's dates: old, the author's apart from the committer's, and
# at an offset that is not UTC, so a snapshot dated now, by the author date or
# at the source's own offset is told apart from one dated as the builder must.
SNAP_AT='2001-02-03T04:05:06+0530'
SNAP_CT='2001-02-04T05:06:07+0530'
# The lines under project:, for an arm that names the project otherwise.
SNAP_NAME_YAML='  name: demo'

# snap_block [publish-url] -- the snapshot block under release:, and a
# publish: block naming <publish-url> when one is given.
snap_block() {
  printf '  snapshot:\n    list: tests/shipped.paths\n    author: "%s"\n' "$SNAP_AUTHOR"
  [ -z "${1:-}" ] || printf '  publish:\n    url: %s\n' "$1"
}

# snap_project [release-yaml] [list] -- a project whose v1.0.0 tag, annotated
# as a cut makes it, is on a commit made as t <t@t> at SNAP_AT and SNAP_CT. The
# commit carries the shipped list (<list>, else SNAP_LIST), files it ships, an
# executable and a link among them, a file it excludes, and a workroom file it
# never names. <release-yaml> is the release: block's body.
snap_project() {
  local proj block="${1:-$(snap_block)}"
  proj="$(
    mkproj demo <<YAML
project:
$SNAP_NAME_YAML
commands:
  release:
    enabled: true
release:
$block
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '# demo\n' >"$proj/README.md"
  mkdir -p "$proj/tests" "$proj/docs" "$proj/intent"
  printf '%s\n' "${2:-$SNAP_LIST}" >"$proj/tests/shipped.paths"
  printf 'guide\n' >"$proj/docs/guide.md"
  printf 'private\n' >"$proj/docs/private.md"
  printf '#!/bin/sh\necho tool\n' >"$proj/docs/tool.sh"
  chmod +x "$proj/docs/tool.sh"
  ln -s guide.md "$proj/docs/link.md"
  printf 'workroom\n' >"$proj/intent/notes.md"
  GIT_AUTHOR_DATE="$SNAP_AT" GIT_COMMITTER_DATE="$SNAP_CT" git_project "$proj"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a -m v1.0.0 v1.0.0
  printf '%s\n' "$proj"
}

# next_release <proj> <version> -- a further commit, made as t <t@t>, with
# VERSION at <version> and the guide changed, tagged v<version> as a cut tags.
next_release() {
  printf '%s\n' "$2" >"$1/VERSION"
  printf 'guide %s\n' "$2" >"$1/docs/guide.md"
  git -C "$1" -c user.name=t -c user.email=t@t commit -qam "release $2"
  git -C "$1" -c user.name=t -c user.email=t@t tag -a -m "v$2" "v$2"
}

# snap_in <proj> <args>... -- release_in, under a TMPDIR of the test's own.
snap_in() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/tmp"
  TMPDIR="$DEVBIN_TEST_TMPDIR/tmp" release_in "$@"
}

# snap_tmp_empty -- fails, naming what is there, when a run left anything in
# snap_in's TMPDIR: the build's scratch, a publish branch's history among it,
# is the release core's to remove at exit.
snap_tmp_empty() {
  local left
  left="$(ls -A "$DEVBIN_TEST_TMPDIR/tmp")"
  [ -z "$left" ] || fail "the run left its scratch in TMPDIR: $left"
}

# want_entries <proj> <rev> -- `<mode> <sha><TAB><path>` for every file the
# list in <rev>'s own tree selects there, read by git: <rev>'s tree in an index
# of its own, and ls-files over the list's lines.
want_entries() {
  local proj="$1" rev="$2" idx list
  local -a specs=()
  idx="$(mktemp "$DEVBIN_TEST_TMPDIR/want.XXXXXX")"
  rm -f "$idx"
  # The list's lines through its one reader (pathlist_specs), handed to git
  # whole: git classifies them, so this oracle reads none itself.
  list="$(git -C "$proj" show "$rev:tests/shipped.paths")" || return 1
  mapfile -t specs < <(pathlist_specs "$list")
  GIT_INDEX_FILE="$idx" git -C "$proj" read-tree "$rev"
  GIT_INDEX_FILE="$idx" git -C "$proj" ls-files -s -- "${specs[@]}" | awk -F'\t' '{ split($1, m, " "); print m[1] " " m[2] "\t" $2 }'
  rm -f "$idx"
}

# got_entries <repo> <rev> -- the same, read off a snapshot's commit.
got_entries() {
  git -C "$1" ls-tree -r "$2" | awk -F'\t' '{ split($1, m, " "); print m[1] " " m[3] "\t" $2 }'
}

# snap_field <label> -- the value on the verb's `  <label>  ...` line.
snap_field() {
  sed -n "s/^  $1  *//p" <<<"$output"
}

# a_snapshot_commit <repo> <tree> <message> [parent...] -- a commit made there
# by release.snapshot.author with <tree>, as the builder makes one.
a_snapshot_commit() {
  local repo="$1" tree="$2" msg="$3" p
  local -a ps=()
  shift 3
  for p in "$@"; do ps+=(-p "$p"); done
  GIT_AUTHOR_NAME="Snap Shot" GIT_AUTHOR_EMAIL=snap@example.com \
    GIT_COMMITTER_NAME="Snap Shot" GIT_COMMITTER_EMAIL=snap@example.com \
    git -C "$repo" commit-tree "$tree" ${ps[@]+"${ps[@]}"} -m "$msg"
}

@test "release snapshot makes one commit whose tree is the tag's tracked files over the list, in paths, modes and blobs (0239)" {
  proj="$(snap_project)"
  [ "$(git -C "$proj" cat-file -t v1.0.0)" = tag ] || fail "the fixture's tag is not annotated, as a cut's is"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/snap"
  assert_success
  snap_tmp_empty
  local snap want got
  snap="$(snap_field commit)"
  [ -n "$snap" ] || fail "release snapshot printed no commit: $output"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/snap" rev-parse HEAD)" = "$snap" ] || fail "the new repository's HEAD is not the snapshot it printed"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/snap" rev-list --parents -n1 "$snap")" = "$snap" ] || fail "with no publish.url the snapshot has a parent"
  assert_output_contains "  parent  none"
  assert_output_contains "  from    $(git -C "$proj" rev-parse 'v1.0.0^{commit}') (v1.0.0)"
  want="$(want_entries "$proj" v1.0.0)"
  got="$(got_entries "$DEVBIN_TEST_TMPDIR/snap" "$snap")"
  [ -n "$want" ] || fail "git selected nothing from the fixture"
  [ "$got" = "$want" ] || fail "the snapshot's tree is not the tag's files over the list:
--- want
$want
--- got
$got"
  # What the list's own lines did, named, so a selection that agreed with a
  # wrong reading of the list could not pass for one that read it right.
  [[ "$got" != *$'\tdocs/private.md'* ]] || fail "the :(exclude) line left docs/private.md in"
  [[ "$got" != *$'\tintent/notes.md'* ]] || fail "intent/notes.md, which the list never names, is in"
  grep -qE "^120000 [0-9a-f]+"$'\t'"docs/link.md$" <<<"$got" || fail "docs/link.md is not the link it was committed as"
  grep -qE "^100755 [0-9a-f]+"$'\t'"docs/tool.sh$" <<<"$got" || fail "docs/tool.sh is not executable, as it was committed"
  [ -f "$DEVBIN_TEST_TMPDIR/snap/docs/guide.md" ] || fail "the snapshot is not checked out for a reader"
}

@test "--commit makes the snapshot of any commit from that commit alone, never the index or the working tree (0239)" {
  proj="$(snap_project)"
  printf 'guide, edited\n' >"$proj/docs/guide.md"
  printf 'bin/\ndocs/\ntests/\nVERSION\n' >"$proj/tests/shipped.paths"
  git -C "$proj" -c user.name=t -c user.email=t@t commit -qam "an audit's commit"
  # THE CHECKOUT DIFFERS FROM THE COMMIT, three ways: the guide staged
  # otherwise, the list changed and not staged, and a file git does not track.
  printf 'guide, staged\n' >"$proj/docs/guide.md"
  git -C "$proj" add docs/guide.md
  printf 'README.md\n.gitattributes\n' >>"$proj/tests/shipped.paths"
  printf 'extra\n' >"$proj/docs/extra.md"
  run snap_in "$proj" snapshot --commit HEAD "$DEVBIN_TEST_TMPDIR/snap"
  assert_success
  local snap want got
  snap="$(snap_field commit)"
  want="$(want_entries "$proj" HEAD)"
  got="$(got_entries "$DEVBIN_TEST_TMPDIR/snap" "$snap")"
  [ "$got" = "$want" ] || fail "the snapshot of HEAD is not HEAD's files over HEAD's list:
--- want
$want
--- got
$got"
  [[ "$got" != *$'\tREADME.md'* ]] || fail "README.md, which HEAD's list no longer names, is in"
  [[ "$got" != *$'\tdocs/extra.md'* ]] || fail "docs/extra.md, which git does not track, is in"
  assert_output_contains "  from    $(git -C "$proj" rev-parse HEAD) (HEAD)"
}

@test "the same inputs give the same commit, under release.snapshot.author at the source's committer date in UTC, with the template's message, unsigned (0239)" {
  proj="$(snap_project)"
  # AN ENCODING A CONFIG WOULD ADD: commit-tree writes an encoding header, and
  # so another sha, under i18n.commitEncoding, unless the build pins it.
  printf '[i18n]\n\tcommitEncoding = ISO-8859-1\n' >"$DEVBIN_TEST_TMPDIR/encoding.gitconfig"
  GIT_CONFIG_GLOBAL="$DEVBIN_TEST_TMPDIR/encoding.gitconfig" run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/a"
  assert_success
  local a b raw date
  a="$(snap_field commit)"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/b"
  assert_success
  b="$(snap_field commit)"
  [ -n "$a" ] && [ "$a" = "$b" ] || fail "the same inputs gave $a and then $b"
  raw="$(git -C "$DEVBIN_TEST_TMPDIR/a" cat-file commit "$a")"
  [[ "$raw" != *gpgsig* ]] || fail "the snapshot is signed: $raw"
  [[ "$raw" != *$'\nencoding '* ]] || fail "the snapshot carries an encoding header: $raw"
  date="$(git -C "$proj" show -s --format=%ct 'v1.0.0^{commit}')"
  [ "$(git -C "$proj" show -s --format=%at 'v1.0.0^{commit}')" != "$date" ] || fail "the fixture's author date is its committer date"
  [[ "$(git -C "$proj" show -s --format=%ci 'v1.0.0^{commit}')" == *' +0530' ]] || fail "the fixture's commit is not at +0530"
  grep -qxF "author $SNAP_AUTHOR $date +0000" <<<"$raw" || fail "the author is not release.snapshot.author at the source's committer date in UTC: $raw"
  grep -qxF "committer $SNAP_AUTHOR $date +0000" <<<"$raw" || fail "the committer is not release.snapshot.author at the source's committer date in UTC: $raw"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/a" log -1 --format=%B "$a")" = "demo 1.0.0" ] || fail "the message is not {name} {version}: $raw"
  [[ "$raw" != *"t@t"* ]] || fail "the workroom's identity reached the snapshot: $raw"
}

@test "the message is filled as data: a project name holding & is written as it is (0239)" {
  SNAP_NAME_YAML=$'  name: "R&D"\n  root_var: RD_ROOT'
  proj="$(snap_project)"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/snap"
  assert_success
  local snap
  snap="$(snap_field commit)"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/snap" log -1 --format=%B "$snap")" = "R&D 1.0.0" ] ||
    fail "the message is not the name as written: $(git -C "$DEVBIN_TEST_TMPDIR/snap" log -1 --format=%B "$snap")"
}

@test "the parent is the publish branch's tip, and there is none while the branch is not there or under --no-parent (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" first second third
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$pub")")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s1"
  assert_success
  first="$(snap_field commit)"
  assert_output_contains "  parent  none"
  # Published as the publish flow will publish it: the snapshot's branch to
  # the public main.
  git -C "$DEVBIN_TEST_TMPDIR/s1" push -q "$pub" main
  next_release "$proj" 1.0.1
  run snap_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/s2"
  assert_success
  snap_tmp_empty
  second="$(snap_field commit)"
  assert_output_contains "  parent  $first"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/s2" rev-parse "$second^")" = "$first" ] || fail "the second snapshot is not made on the first"
  run snap_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/s3" --no-parent
  assert_success
  third="$(snap_field commit)"
  [ "$(git -C "$DEVBIN_TEST_TMPDIR/s3" rev-list --parents -n1 "$third")" = "$third" ] || fail "--no-parent made a snapshot with a parent"
}

@test "a publish branch holding a commit release.snapshot.author did not make is refused, naming the commit and who made it (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git"
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$pub")")"
  # THE PRIVATE COPY'S CASE: the workroom's own main, made as t <t@t>, where the
  # public repository will be.
  git -C "$proj" push -q "$pub" main
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "the publish branch's history holds $(git -C "$proj" rev-parse --short=12 main), made by t <t@t> and committed by t <t@t>, not by release.snapshot.author ($SNAP_AUTHOR)"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal left $DEVBIN_TEST_TMPDIR/s behind"
  snap_tmp_empty
}

@test "a commit under release.snapshot.author's own identity is refused for a path outside the list its tree carries, naming the commit and who made it (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" tip
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$pub")")"
  # The workroom's tree, under the snapshot identity: only its paths tell it
  # from a snapshot.
  tip="$(a_snapshot_commit "$proj" "$(git -C "$proj" rev-parse 'v1.0.0^{tree}')" "looks like a snapshot")"
  git -C "$proj" push -q "$pub" "$tip:refs/heads/main"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "the publish branch's history holds ${tip:0:12}, made by $SNAP_AUTHOR and committed by $SNAP_AUTHOR, which carries docs/private.md outside the list its own tree carries"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal left $DEVBIN_TEST_TMPDIR/s behind"
  snap_tmp_empty
}

@test "an older snapshot made under a longer list still passes after a path leaves the list (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" first second got
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$pub")" "$(printf '.gitattributes\nbin/\ndocs/\ntests/\nVERSION\nREADME.md')")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s1"
  assert_success
  first="$(snap_field commit)"
  git -C "$DEVBIN_TEST_TMPDIR/s1" cat-file -e "$first:docs/private.md" || fail "the longer list did not ship docs/private.md"
  git -C "$DEVBIN_TEST_TMPDIR/s1" push -q "$pub" main
  # The list loses docs/private.md, and the first snapshot, which carries it,
  # stays good: it is read against the list its own tree carries.
  printf '%s\n' "$SNAP_LIST" >"$proj/tests/shipped.paths"
  next_release "$proj" 1.0.1
  run snap_in "$proj" snapshot v1.0.1 "$DEVBIN_TEST_TMPDIR/s2"
  assert_success
  second="$(snap_field commit)"
  assert_output_contains "  parent  $first"
  got="$(got_entries "$DEVBIN_TEST_TMPDIR/s2" "$second")"
  [[ "$got" != *$'\tdocs/private.md'* ]] || fail "the shortened list still shipped docs/private.md"
}

@test "a publish branch whose history holds a merge is refused, naming it and who made it: a snapshot has one parent at most (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" tree a b merge
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$pub")")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s1" --no-parent
  assert_success
  a="$(snap_field commit)"
  tree="$(git -C "$DEVBIN_TEST_TMPDIR/s1" rev-parse "$a^{tree}")"
  b="$(a_snapshot_commit "$DEVBIN_TEST_TMPDIR/s1" "$tree" "another root")"
  merge="$(a_snapshot_commit "$DEVBIN_TEST_TMPDIR/s1" "$tree" "a merge" "$a" "$b")"
  git -C "$DEVBIN_TEST_TMPDIR/s1" push -q "$pub" "$merge:refs/heads/main"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s2"
  assert_failure
  assert_output_contains "the publish branch's history holds ${merge:0:12}, a merge, made by $SNAP_AUTHOR and committed by $SNAP_AUTHOR, and a snapshot has one parent at most"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s2" ] || fail "the refusal left $DEVBIN_TEST_TMPDIR/s2 behind"
  snap_tmp_empty
}

@test "a publish.url naming the repository one of the project's remotes names, on another host's spelling, is refused before anything is fetched, naming the remote, and --no-parent builds (0239)" {
  # The fixture's origin is https://github.com/t/demo.git. This url names t/demo
  # through an ssh host alias and in another case, which GitHub reads as one
  # repository, and nothing answers at it: a refusal made after a fetch would
  # fail on the fetch instead.
  proj="$(snap_project "$(snap_block "git@gh-alias:T/Demo.git")")"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "release.publish.url names t/demo, the repository this project's remote origin names"
  assert_output_contains "a first snapshot is made with --no-parent"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s" --no-parent
  assert_success
  assert_output_contains "  parent  none"
}

@test "a publish branch whose history is cut short, as a shallow repository's is, ending in no parentless root, is refused, and nothing is written (0239)" {
  local pub="$DEVBIN_TEST_TMPDIR/public.git" shallow="$DEVBIN_TEST_TMPDIR/shallow.git" tree a b
  git init -q --bare -b main "$pub"
  proj="$(snap_project "$(snap_block "$shallow")")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s1" --no-parent
  assert_success
  a="$(snap_field commit)"
  tree="$(git -C "$DEVBIN_TEST_TMPDIR/s1" rev-parse "$a^{tree}")"
  b="$(a_snapshot_commit "$DEVBIN_TEST_TMPDIR/s1" "$tree" "a second snapshot" "$a")"
  git -C "$DEVBIN_TEST_TMPDIR/s1" push -q "$pub" "$b:refs/heads/main"
  # The public history with its first snapshot cut away: b's parent is not
  # there, so the history git holds ends in no root of its own.
  git clone -q --bare --depth 1 "file://$pub" "$shallow"
  [ -s "$shallow/shallow" ] || fail "the fixture's clone is not shallow"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s2"
  assert_failure
  assert_output_contains "git wrote no ref for the publish branch's tip ${b:0:12}"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s2" ] || fail "the refusal left $DEVBIN_TEST_TMPDIR/s2 behind"
  snap_tmp_empty
}

@test "every refusal of the source or the directory names why and writes nothing (0239)" {
  proj="$(snap_project)"
  mkdir "$DEVBIN_TEST_TMPDIR/exists"
  # A LINK OUT OF THE PROJECT'S WAY THAT LEADS BACK INTO IT: `..` after it is the
  # project's directory, wherever the link's own text says it is.
  ln -s "$proj/docs" "$DEVBIN_TEST_TMPDIR/l"
  local before args want
  before="$(fingerprint "$proj")"
  while IFS='|' read -r args want; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086  # each line is an argument list
    run snap_in "$proj" snapshot $args
    assert_failure
    assert_output_contains "$want"
    snap_tmp_empty
  done <<EOF2
v1.0.0 $DEVBIN_TEST_TMPDIR/exists|$DEVBIN_TEST_TMPDIR/exists already exists: a snapshot is made in a new directory, never rebuilt in place
--commit nosuchrev $DEVBIN_TEST_TMPDIR/n1|nosuchrev is not a commit here
--commit HEAD^{tree} $DEVBIN_TEST_TMPDIR/n1|HEAD^{tree} is not a commit here
--commit v1.0.0:VERSION $DEVBIN_TEST_TMPDIR/n1|v1.0.0:VERSION is not a commit here
v9.9.9 $DEVBIN_TEST_TMPDIR/n2|there is no tag v9.9.9 here
v1.0.0 $proj/inside|is inside the project
v1.0.0 /$proj/inside|is inside the project
v1.0.0 $DEVBIN_TEST_TMPDIR/l/../inside|is inside the project
v1.0.0 $DEVBIN_TEST_TMPDIR/no/such/n3|does not exist, so $DEVBIN_TEST_TMPDIR/no/such/n3 cannot be made there
EOF2
  [ -z "$(ls -A "$DEVBIN_TEST_TMPDIR/exists")" ] || fail "a refusal wrote into the existing directory"
  local d
  for d in "$DEVBIN_TEST_TMPDIR/n1" "$DEVBIN_TEST_TMPDIR/n2" "$DEVBIN_TEST_TMPDIR/no" "$proj/inside"; do
    [ ! -e "$d" ] || fail "a refusal made $d"
  done
  [ "$(fingerprint "$proj")" = "$before" ] || fail "a refusal wrote to the project, its refs, its config or its remote"
}

# ONE PROJECT A TEST: every fixture is $DEVBIN_TEST_TMPDIR/demo, and its bare
# remote is shared, so each refusal of the list has a test of its own.

@test "a list that is not declared is refused, naming the key, and nothing is written (0239)" {
  proj="$(snap_project "  object: local")"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "release.snapshot.list is not declared"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
}

@test "a list the commit does not hold is refused, naming it, and nothing is written (0239)" {
  proj="$(snap_project "$(snap_block | sed 's#tests/shipped.paths#tests/missing.paths#')")"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "release.snapshot.list is tests/missing.paths, and $(git -C "$proj" rev-parse --short=12 'v1.0.0^{commit}') holds no such file to read"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
}

@test "a line of the list that matches no file is refused, naming the line, and nothing is written (0239)" {
  proj="$(snap_project "" "$(printf 'bin/\nnosuch/\n')")"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "the list tests/shipped.paths holds 'nosuch/', which matches no file at"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
}

@test "a gitlink in what the list selects is refused, naming it, and nothing is written (0239)" {
  proj="$(snap_project)"
  # The gitlink goes in through the index, and the list alone is staged beside
  # it: `commit -a` would read the missing directory as a deletion.
  git -C "$proj" update-index --add --cacheinfo "160000,$(git -C "$proj" rev-parse HEAD),docs/sub"
  git -C "$proj" -c user.name=t -c user.email=t@t commit -qm "a gitlink under docs"
  git -C "$proj" cat-file -e HEAD:docs/sub || fail "the fixture commit carries no gitlink"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot --commit HEAD "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "the list selects docs/sub, a gitlink"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
}

@test "a branch git would not take is refused before anything is made (0239)" {
  proj="$(snap_project "$(snap_block)"$'\n  branch: a..b')"
  local before
  before="$(fingerprint "$proj")"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/s"
  assert_failure
  assert_output_contains "a..b is not a name git takes for a branch"
  [ ! -e "$DEVBIN_TEST_TMPDIR/s" ] || fail "the refusal made $DEVBIN_TEST_TMPDIR/s"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the refusal wrote to the project"
  snap_tmp_empty
}

@test "the new repository holds no object but the snapshot's own (0239)" {
  proj="$(snap_project)"
  run snap_in "$proj" snapshot v1.0.0 "$DEVBIN_TEST_TMPDIR/snap"
  assert_success
  local snap all reachable
  snap="$(snap_field commit)"
  all="$(git -C "$DEVBIN_TEST_TMPDIR/snap" cat-file --batch-all-objects --batch-check='%(objectname)' | LC_ALL=C sort)"
  reachable="$(git -C "$DEVBIN_TEST_TMPDIR/snap" rev-list --objects "$snap" | cut -d' ' -f1 | LC_ALL=C sort)"
  [ -n "$all" ] || fail "read no object out of the new repository"
  [ "$all" = "$reachable" ] || fail "the new repository holds objects the snapshot does not reach:
$(LC_ALL=C comm -23 <(printf '%s\n' "$all") <(printf '%s\n' "$reachable"))"
  ! git -C "$DEVBIN_TEST_TMPDIR/snap" cat-file -e "$(git -C "$proj" rev-parse 'v1.0.0^{commit}')" 2>/dev/null ||
    fail "the workroom's commit reached the new repository"
}

@test "the snapshot's keys are validated, each refusal naming the key (0239)" {
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    cfg_load_string <<YAML
project:
  name: demo
release:
$(printf '%b' "$block")
YAML
    run cfg_validate
    [ "$status" -ne 0 ] || fail "accepted: $block"
    assert_output_contains "$want"
  done <<'EOF2'
  snapshot:\n    list: tests/shipped.paths|release.snapshot.author is required beside release.snapshot.list
  snapshot:\n    author: "A B <a@b>"|release.snapshot.author is read only when release.snapshot.list is declared
  publish:\n    url: https://example.com/o/n.git|release.publish.url is read only when release.snapshot.list is declared
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    branch: main|release.publish.branch is read only when release.publish.url is declared
  snapshot:\n    list: x\n    author: nobody|release.snapshot.author: "nobody" must be Name <email>
  snapshot:\n    list: x\n    author: "A B, <a@b>"|release.snapshot.author: "A B, <a@b>" must be Name <email> as git writes an identity
  snapshot:\n    list: x\n    author: "A B  <a@b>"|release.snapshot.author: "A B  <a@b>" must be Name <email> as git writes an identity
  snapshot:\n    list: x\n    author: " A B <a@b>"|release.snapshot.author: " A B <a@b>" must be Name <email> as git writes an identity
  snapshot:\n    list: x\n    author: "A B <a@b>"\n    message: "{name} {tag}"|release.snapshot.message: "{name} {tag}" must be one line, with no placeholder but {name} and {version}
  snapshot:\n    list: /etc/shipped\n    author: "A B <a@b>"|release.snapshot.list: "/etc/shipped" must be a path in the project, from its root
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: ../public.git|release.publish.url: "../public.git" must be the url of the public repository, an scp-style host:path or an absolute path
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: "-upload-pack=x"|release.publish.url: "-upload-pack=x" must be the url of the public repository
  snapshot:\n    list: x\n    author: "A B <a@b>"\n  publish:\n    url: /srv/public.git\n    branch: "-b"|release.publish.branch: "-b" must be a branch name
EOF2
  # THE CONTROL: the whole block, each key declared, validates.
  cfg_load_string <<'YAML'
project:
  name: demo
release:
  snapshot:
    list: tests/shipped.paths
    author: "A B <a@b>"
    message: "{name} {version}"
  publish:
    url: https://example.com/o/n.git
    branch: main
YAML
  run cfg_validate
  [ "$status" -eq 0 ] || fail "the whole snapshot block was refused: $output"
}

@test "release snapshot's arguments are read before anything acts, and usage names the verb (0239)" {
  proj="$(snap_project)"
  local before args want
  before="$(fingerprint "$proj")"
  while IFS='|' read -r args want; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086  # each line is an argument list
    run release_in "$proj" $args
    assert_failure
    assert_output_contains "$want"
  done <<'EOF2'
snapshot v1.0.0|release snapshot takes a version and a new directory, or --commit <rev> and a new directory
snapshot --commit HEAD a b|release snapshot --commit <rev> takes the new directory alone
snapshot notaversion dir|not a version: notaversion
status v1.0.0 --no-parent|--no-parent applies to release snapshot, not to release status
check --commit HEAD|--commit applies to release snapshot, not to release check
EOF2
  [ "$(fingerprint "$proj")" = "$before" ] || fail "a refused argument list wrote something"
  run release_in "$proj" --help
  assert_success
  assert_output_contains "release snapshot <vX.Y.Z | --commit <rev>> <new-dir> [--no-parent]"
}
