#!/usr/bin/env bash
# release_fixtures.bash -- fixtures for the release core (ST0007): a project that
# has opted in, a committed repository with a bare remote, a `gh` stub, and the
# whole-repository fingerprint every "writes nothing" arm rests on.
#
# ONE HOME FOR THEM, loaded by releasecore.bats (WP-01, the declaration and the
# argument loop), releasestatus.bats (WP-03, the resume map) and releasecut.bats
# (the cut). They lived in
# releasecore.bats until WP-03 needed the same fixture, and a second copy of a
# fingerprint is exactly the instrument that drifts silently: an arm reading a
# copy that stopped seeing refs would go on passing.

# enabled_project -- a fixture project with `release` enabled and nothing else.
enabled_project() {
  mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
YAML
}

# cut_project [release-yaml] -- a project whose v1.0.0 is released (tagged and
# pushed), with 1.0.1 written and not stamped: VERSION 1.0.0 and a CHANGELOG.md
# whose [1.0.1] section is open, committed and pushed to one bare remote.
#
# Its one gate is `probe`, a project command that records each run in
# gate.calls and then sources $DEVBIN_TEST_TMPDIR/gate.sh when an arm writes
# one, so an arm decides what the gate reads, writes or answers. A
# <release-yaml> argument replaces the release: block's body, and a
# <project-yaml> argument adds lines under project:. HERE, not in
# releasecut.bats, since releaseattach.bats cuts it too (ST0008 WP-08).
cut_project() {
  local proj body
  body="${1:-  gates:
    - probe}"
  proj="$(
    mkproj demo <<YAML
project:
  name: demo
${2:-}
commands:
  release:
    enabled: true
release:
$body
YAML
  )"
  with_dated_note "$proj"
  printf '# demo\n' >"$proj/README.md"
  printf 'tmp/\n' >"$proj/.gitignore"
  create_test_command "$proj" probe "$(printf '#!/usr/bin/env bash\necho "probe $*" >>"%s/gate.calls"\nif [ -f "%s/gate.sh" ]; then . "%s/gate.sh"; fi\nexit 0\n' \
    "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR" "$DEVBIN_TEST_TMPDIR")" >/dev/null
  git_project "$proj"
  git -C "$proj" config user.name t
  git -C "$proj" config user.email t@t
  git -C "$proj" tag -a v1.0.0 -m "- first" --cleanup=whitespace
  git -C "$proj" push -q origin v1.0.0
  printf '# Changelog\n\n## [1.0.1] - Unreleased\n\n- second\n\n## [1.0.0] - 2026-01-01\n\n- first\n' >"$proj/CHANGELOG.md"
  git -C "$proj" commit -qam "notes for 1.0.1"
  git -C "$proj" push -q origin main
  printf '%s\n' "$proj"
}

# git_project <proj> -- a committed repository with a bare remote holding main,
# and a `gh` stub on PATH that records every call outside the project.
#
# AN OBJECT MADE BY A WORKFLOW (`object: ci`) is $DEVBIN_TEST_TMPDIR/gh.appear,
# "<tag> <n>": the tag joins the list on the nth `release view` of it, so an
# arm can make the object appear while a cut waits for it, or never.
#
# THE STUB ANSWERS `gh release view <tag>` FROM A LIST, because the release
# object is one of the facts `release status` reads. A tag named in
# $DEVBIN_TEST_TMPDIR/gh.releases has a release object; any other tag answers
# the way gh does, `release not found` on stderr and exit 1. `release create
# <tag>` adds <tag> to that list, as gh would make the object. Every call is
# recorded and exits 0.
git_project() {
  local proj="$1"
  git -C "$proj" init -q -b main
  git -C "$proj" add -A
  git -C "$proj" -c user.name=t -c user.email=t@t commit -qm init
  # -b main, as for the project: a clone takes the remote's HEAD, and a runner
  # with no init.defaultBranch (CI's) points it at master, so a clone had no main.
  git init -q --bare -b main "$DEVBIN_TEST_TMPDIR/remote.git"
  # origin NAMES a GitHub repository, as a real project's does, so release.repo
  # has something to be read from; insteadOf sends the bytes to the bare repo.
  git -C "$proj" config url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf https://github.com/t/demo.git
  git -C "$proj" remote add origin https://github.com/t/demo.git
  git -C "$proj" push -q origin main
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  cat >"$DEVBIN_TEST_TMPDIR/stubs/gh" <<SH
#!/bin/sh
echo "gh \$*" >>"$DEVBIN_TEST_TMPDIR/gh.calls"
echo "prompt=\${GH_PROMPT_DISABLED-unset} \$*" >>"$DEVBIN_TEST_TMPDIR/gh.env"
# A gh that HANGS on a verb: $DEVBIN_TEST_TMPDIR/gh.hang.<verb> (view, create,
# edit) makes that verb sleep, as a stalled network call does.
if [ "\$1" = release ] && [ -f "$DEVBIN_TEST_TMPDIR/gh.hang.\$2" ]; then sleep 60; fi
# RUNS, ARTIFACTS AND RELEASE ASSETS are gh-more's (ST0008 WP-08), beside this.
case "\$1 \$2" in
  "run list" | "run view" | "run download" | "release upload" | "release download")
    L="$DEVBIN_LIB_DIR" T="$DEVBIN_TEST_TMPDIR" exec bash "$DEVBIN_TEST_TMPDIR/stubs/gh-more" "\$@"
    ;;
  "release view")
    case " \$* " in *" --json assets "*) L="$DEVBIN_LIB_DIR" T="$DEVBIN_TEST_TMPDIR" exec bash "$DEVBIN_TEST_TMPDIR/stubs/gh-more" "\$@" ;; esac
    ;;
esac
[ "\$1" != api ] || L="$DEVBIN_LIB_DIR" T="$DEVBIN_TEST_TMPDIR" exec bash "$DEVBIN_TEST_TMPDIR/stubs/gh-more" "\$@"
if [ "\$1 \$2" = "release view" ]; then
  shift 2
  tag="" jq=""
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --repo) shift 2 ;;
      # The fields this branch answers; any other is gh's refusal.
      --json)
        case "\$2" in name | body) ;; *) echo "Unknown JSON field: \"\$2\"" >&2; exit 1 ;; esac
        shift 2
        ;;
      --jq) jq="\$2"; shift 2 ;;
      *) [ -n "\$tag" ] || tag="\$1"; shift ;;
    esac
  done
  # A WORKFLOW'S OBJECT, which appears on the Nth view (gh.appear: "<tag> <n>").
  if [ -f "$DEVBIN_TEST_TMPDIR/gh.appear" ]; then
    read -r atag acount <"$DEVBIN_TEST_TMPDIR/gh.appear"
    if [ "\$atag" = "\$tag" ]; then
      acount=\$((acount - 1))
      if [ "\$acount" -le 0 ]; then
        printf '%s\n' "\$tag" >>"$DEVBIN_TEST_TMPDIR/gh.releases"
        rm -f "$DEVBIN_TEST_TMPDIR/gh.appear"
      else
        printf '%s %s\n' "\$atag" "\$acount" >"$DEVBIN_TEST_TMPDIR/gh.appear"
      fi
    fi
  fi
  if grep -qxF -- "\$tag" "$DEVBIN_TEST_TMPDIR/gh.releases" 2>/dev/null; then
    case "\$jq" in
      .name) cat "$DEVBIN_TEST_TMPDIR/gh.obj.\$tag.name" 2>/dev/null ;;
      .body) cat "$DEVBIN_TEST_TMPDIR/gh.obj.\$tag.body" 2>/dev/null ;;
      *) echo "title:	\$tag" ;;
    esac
    exit 0
  fi
  echo "release not found" >&2
  exit 1
fi
# create and edit keep the object's title and notes, as view answers them.
if [ "\$1 \$2" = "release create" ] || [ "\$1 \$2" = "release edit" ]; then
  verb="\$2"
  shift 2
  tag="" title="" notes=""
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --repo) shift 2 ;;
      --title) title="\$2"; shift 2 ;;
      --notes-file) notes="\$2"; shift 2 ;;
      -*) shift ;;
      *) [ -n "\$tag" ] || tag="\$1"; shift ;;
    esac
  done
  [ "\$verb" = edit ] || printf '%s\n' "\$tag" >>"$DEVBIN_TEST_TMPDIR/gh.releases"
  printf '%s\n' "\$title" >"$DEVBIN_TEST_TMPDIR/gh.obj.\$tag.name"
  [ -z "\$notes" ] || cp "\$notes" "$DEVBIN_TEST_TMPDIR/gh.obj.\$tag.body"
fi
exit 0
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/gh"
  gh_stub_more
}

# gh_stub_more -- the gh stub's runs, artifacts and release assets (ST0008
# WP-08), which `gh` hands its calls to after recording them. Its state, every
# file under $DEVBIN_TEST_TMPDIR (T); each one absent means none:
#
#   gh.runs.json            a JSON array of runs: databaseId, headSha,
#                           headBranch, status, conclusion, createdAt, and
#                           `workflow`, the file name --workflow matches
#   gh.runs.next            paths of JSON files, one a line: each `run list`
#                           takes the first as gh.runs.json before answering,
#                           so a run can appear, or finish, while a wait asks
#   gh.jobs.<id>.json       `{"jobs": [...]}` for `run view <id> --json jobs`
#   gh.artifacts/<id>/<a>/  the files of run <id>'s artifact <a>; `run
#                           download` copies each <a> under --dir, as gh does
#                           with no --name (measured on gh 2.103.0), and `gh
#                           api repos/.../actions/runs/<id>/artifacts` lists them
#   gh.expired.<id>.<a>     artifact <a> has expired: listed so, and passed over
#                           by `run download`, which fails only when none is left,
#                           as gh's own does
#   gh.skip.<id>.<a>        `run download` writes no <a>, though it is listed and
#                           not expired: a download that came up short
#   gh.assets/<tag>/<name>  the release object's assets, by name
#   gh.digest.<tag>.<name>  the digest `release view --json assets` lists for
#                           that asset in place of its sha256, or `none` for
#                           none: GitHub's own record disagreeing, or missing
#   gh.fail.upload          every `release upload` fails, as a 502 does;
#                           gh.fail.upload.<name> fails that name's alone
#   gh.fail.assets          every `release view --json assets` fails so too
#
# IT REFUSES WHAT gh REFUSES, so a call gh would refuse cannot pass here: an
# unknown --json field; a flag the verb does not take, from each verb's own list
# as gh 2.103.0's --help gives it, cut to what the stub emulates; a call with no
# --repo, which would let gh choose, or `gh api` with one, which it does not
# take; a `#` in an upload's path, which gh reads as the start of a label; an
# upload over an asset of the same name without --clobber; an asset named twice
# in one upload; and a release that does not exist. --jq is run through jq over
# the JSON gh would print, as gh runs it, so the core's own programs are what
# the arms test. Every write and every jq is checked: a stub that failed to do
# a thing exits non-zero, as gh would, never 0.
gh_stub_more() {
  cat >"$DEVBIN_TEST_TMPDIR/stubs/gh-more" <<'SH'
set -euo pipefail
# devbin's sha256_of for the digests it lists: lib/helpers is the one place
# devbin knows which sha256 tool exists (issue 0052). Sourced first, so the die
# below is the one every function here, sha256_of's included, calls.
. "$L/helpers"
die() { printf '%s\n' "$*" >&2; exit 1; }
cmd="$1"
shift
if [ "$cmd" != api ]; then
  cmd="$cmd $1"
  shift
fi
case "$cmd" in
  "run list") allowed="--repo --json --jq --limit --workflow --branch --commit" ;;
  "run view") allowed="--repo --json --jq" ;;
  "run download") allowed="--repo --dir" ;;
  "release view") allowed="--repo --json --jq" ;;
  "release upload") allowed="--repo --clobber" ;;
  "release download") allowed="--repo --pattern --dir --output" ;;
  api) allowed="--hostname --paginate --jq" ;;
  *) die "stub: gh $cmd is not emulated" ;;
esac
repo="" json="" jq="" limit=20 wf="" branch="" commit="" dir="" pattern="" output="" clobber=no paginate=no
pos=()
while [ $# -gt 0 ]; do
  flag="$1"
  case "$flag" in
    -R) flag=--repo ;;
    -q) flag=--jq ;;
    -L) flag=--limit ;;
    -b) flag=--branch ;;
    -c) flag=--commit ;;
    -D) flag=--dir ;;
    -p) flag=--pattern ;;
    -O) flag=--output ;;
    -w) if [ "$cmd" = "run list" ]; then flag=--workflow; else flag=--web; fi ;;
  esac
  case "$flag" in
    -*) case " $allowed " in *" $flag "*) ;; *) die "stub: gh $cmd takes no $1 here" ;; esac ;;
  esac
  case "$flag" in
    --repo) repo="$2"; shift 2 ;;
    --json) json="$2"; shift 2 ;;
    --jq) jq="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --workflow) wf="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --pattern) [ -z "$pattern" ] || die "stub: one --pattern only"; pattern="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --hostname) shift 2 ;;
    --clobber) clobber=yes; shift ;;
    --paginate) paginate=yes; shift ;;
    *) pos+=("$1"); shift ;;
  esac
done
if [ "$cmd" = api ]; then
  [ -z "$repo" ] || die "stub: gh api takes no --repo"
else
  [ -n "$repo" ] || die "stub: gh $cmd without --repo would let gh choose the repository"
fi
# fields <allowed>... -- refuse a requested --json field gh does not have.
fields() {
  local allowed=" $* " f
  local -a want=()
  IFS=, read -r -a want <<<"$json"
  for f in ${want[@]+"${want[@]}"}; do
    case "$allowed" in *" $f "*) ;; *) die "Unknown JSON field: \"$f\"" ;; esac
  done
}
# emit <json> -- the JSON gh prints, or the --jq program's raw output over it.
emit() {
  if [ -n "$jq" ]; then
    jq -r "$jq" <<<"$1" || die "stub: the --jq program failed"
  else
    printf '%s\n' "$1"
  fi
}
# Absent means no release has been made.
release_exists() { [ -f "$T/gh.releases" ] && grep -qxF -- "$1" "$T/gh.releases"; }
case "$cmd" in
  "run list")
    fields attempt conclusion createdAt databaseId displayTitle event headBranch headSha name number startedAt status updatedAt url workflowDatabaseId workflowName
    if [ -s "$T/gh.runs.next" ]; then
      next="$(head -n 1 "$T/gh.runs.next")"
      tail -n +2 "$T/gh.runs.next" >"$T/gh.runs.next.tmp"
      mv "$T/gh.runs.next.tmp" "$T/gh.runs.next"
      cp "$next" "$T/gh.runs.json"
    fi
    runs='[]'
    [ ! -e "$T/gh.runs.json" ] || runs="$(cat "$T/gh.runs.json")"
    out="$(jq --arg wf "$wf" --arg b "$branch" --arg c "$commit" --argjson lim "$limit" --arg f "$json" '
      [.[] | select(($wf == "" or .workflow == $wf) and ($b == "" or .headBranch == $b) and ($c == "" or .headSha == $c))]
      | sort_by(.createdAt) | reverse | .[:$lim]
      | map(with_entries(select(.key as $k | ($f | split(",")) | index($k))))' <<<"$runs")" ||
      die "stub: gh.runs.json is not a JSON list of runs"
    emit "$out"
    ;;
  "run view")
    fields jobs
    [ "${#pos[@]}" -eq 1 ] || die "stub: gh run view takes one run id"
    jobs='{"jobs": []}'
    [ ! -e "$T/gh.jobs.${pos[0]}.json" ] || jobs="$(cat "$T/gh.jobs.${pos[0]}.json")"
    emit "$jobs"
    ;;
  "run download")
    [ "${#pos[@]}" -eq 1 ] || die "stub: gh run download takes one run id"
    [ -n "$dir" ] || die "stub: gh run download without --dir writes into the working directory"
    id="${pos[0]}" got=0
    for a in "$T/gh.artifacts/$id"/*/; do
      [ -d "$a" ] || continue
      a="${a%/}"
      a="${a##*/}"
      [ ! -e "$T/gh.expired.$id.$a" ] || continue
      [ ! -e "$T/gh.skip.$id.$a" ] || continue
      [ ! -e "$dir/$a" ] || die "error downloading $a: would overwrite $dir/$a"
      mkdir -p "$dir"
      cp -R "$T/gh.artifacts/$id/$a" "$dir/$a"
      got=$((got + 1))
    done
    [ "$got" -gt 0 ] || die "no valid artifacts found to download"
    ;;
  "release view")
    fields apiUrl assets author body createdAt databaseId id isDraft isImmutable isPrerelease name publishedAt tagName tarballUrl targetCommitish uploadUrl url zipballUrl
    tag="${pos[0]:-}"
    release_exists "$tag" || die "release not found"
    [ ! -e "$T/gh.fail.assets" ] || die "HTTP 502: the release could not be read"
    rows=""
    for f in "$T/gh.assets/$tag"/*; do
      [ -f "$f" ] || continue
      n="${f##*/}"
      d="sha256:$(sha256_of "$f")"
      [ ! -f "$T/gh.digest.$tag.$n" ] || d="$(cat "$T/gh.digest.$tag.$n")"
      row="$(jq -n -c --arg name "$n" --arg digest "$d" --argjson size "$(wc -c <"$f" | tr -d ' ')" \
        '{name: $name, state: "uploaded", digest: (if $digest == "none" then null else $digest end), size: $size}')" ||
        die "stub: jq could not describe $n"
      rows+="$row"$'\n'
    done
    out="$(jq -s -c '{assets: .}' <<<"$rows")" || die "stub: jq could not list the assets"
    emit "$out"
    ;;
  "release upload")
    tag="${pos[0]:-}"
    release_exists "$tag" || die "release not found"
    [ ! -e "$T/gh.fail.upload" ] || die "HTTP 502: upload failed"
    [ "${#pos[@]}" -ge 2 ] || die "stub: gh release upload names no file"
    seen=" "
    for f in "${pos[@]:1}"; do
      case "$f" in *'#'*) die "stub: gh release upload reads what follows the # in $f as a label" ;; esac
      n="${f##*/}"
      [ ! -e "$T/gh.fail.upload.$n" ] || die "HTTP 502: uploading $n failed"
      [ -f "$f" ] || die "stub: no file $f"
      case "$seen" in *" $n "*) die "stub: $n named twice" ;; esac
      seen+="$n "
      if [ -e "$T/gh.assets/$tag/$n" ] && [ "$clobber" = no ]; then die "asset under the same name already exists: [$n]"; fi
    done
    mkdir -p "$T/gh.assets/$tag"
    for f in "${pos[@]:1}"; do cp "$f" "$T/gh.assets/$tag/${f##*/}"; done
    ;;
  "release download")
    tag="${pos[0]:-}"
    release_exists "$tag" || die "release not found"
    [ -n "$pattern" ] || die "stub: gh release download without --pattern is not emulated"
    [ -n "$dir" ] || [ -n "$output" ] || die "stub: gh release download needs --dir or --output here"
    matched=()
    for f in "$T/gh.assets/$tag"/*; do
      [ -f "$f" ] || continue
      # A glob, as gh matches --pattern.
      case "${f##*/}" in $pattern) matched+=("$f") ;; esac
    done
    [ "${#matched[@]}" -gt 0 ] || die "no assets match the file pattern"
    if [ -n "$output" ]; then
      [ "${#matched[@]}" -eq 1 ] || die "multiple files match; use --dir"
      if [ "$output" = - ]; then cat "${matched[0]}"; else cp "${matched[0]}" "$output"; fi
    else
      mkdir -p "$dir"
      for f in "${matched[@]}"; do
        [ ! -e "$dir/${f##*/}" ] || die "$dir/${f##*/} already exists (use --clobber or --skip-existing)"
        cp "$f" "$dir/${f##*/}"
      done
    fi
    ;;
  api)
    path="${pos[0]:-}"
    case "$path" in
      repos/*/actions/runs/*/artifacts) ;;
      *) die "stub: gh api $path is not emulated" ;;
    esac
    [ "$paginate" = yes ] || die "stub: an artifacts listing without --paginate reads its first page only"
    id="${path%/artifacts}"
    id="${id##*/}"
    rows=""
    for a in "$T/gh.artifacts/$id"/*/; do
      [ -d "$a" ] || continue
      a="${a%/}"
      a="${a##*/}"
      expired=false
      [ ! -e "$T/gh.expired.$id.$a" ] || expired=true
      row="$(jq -n -c --arg name "$a" --argjson expired "$expired" '{name: $name, expired: $expired}')" ||
        die "stub: jq could not describe artifact $a"
      rows+="$row"$'\n'
    done
    out="$(jq -s -c '{total_count: length, artifacts: .}' <<<"$rows")" || die "stub: jq could not list the artifacts"
    emit "$out"
    ;;
esac
exit 0
SH
}

# gh_calls <pattern> -- how many recorded gh calls match <pattern>; grep's own
# failure, a log it could not read, fails the caller, never reads as none.
gh_calls() {
  [ -f "$DEVBIN_TEST_TMPDIR/gh.calls" ] || {
    echo 0
    return 0
  }
  grep -c -- "$1" "$DEVBIN_TEST_TMPDIR/gh.calls" || [ $? -eq 1 ]
}

# gh_run <id> <sha> <branch> <status> <conclusion> <created> [workflow] -- a run
# of <workflow> (default linux-release.yml) joins gh.runs.json.
gh_run() {
  local runs="$DEVBIN_TEST_TMPDIR/gh.runs.json"
  [ -f "$runs" ] || printf '[]\n' >"$runs"
  jq --argjson id "$1" --arg sha "$2" --arg b "$3" --arg s "$4" --arg c "$5" --arg t "$6" --arg wf "${7:-linux-release.yml}" \
    '. + [{databaseId: $id, headSha: $sha, headBranch: $b, status: $s, conclusion: $c, createdAt: $t, event: "push", attempt: 1, workflow: $wf}]' \
    "$runs" >"$runs.new"
  mv "$runs.new" "$runs"
}

# gh_artifact <id> <artifact> <file> <bytes> -- <file>, holding <bytes>, inside
# run <id>'s artifact <artifact>.
gh_artifact() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/gh.artifacts/$1/$2"
  printf '%s' "$4" >"$DEVBIN_TEST_TMPDIR/gh.artifacts/$1/$2/$3"
}

# gh_asset <tag> <name> <bytes> -- an asset <name>, holding <bytes>, on the
# release object for <tag>.
gh_asset() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/gh.assets/$1"
  printf '%s' "$3" >"$DEVBIN_TEST_TMPDIR/gh.assets/$1/$2"
}

# origin_at <proj> <url> -- origin's configured url becomes <url>, which is what
# release_repo reads, while insteadOf sends every git read of it to the bare
# remote, so nothing reaches the network. git_project names origin the same way
# when it adds it.
origin_at() {
  git -C "$1" config --add url."$DEVBIN_TEST_TMPDIR/remote.git".insteadOf "$2"
  git -C "$1" remote set-url origin "$2"
}

# gh_object <tag> <title> <notes> -- a release object for <tag> on the gh stub,
# carrying <title> and <notes>, as `gh release create` would leave it. Under
# object: local an object is `already` only when it carries this release's
# title and notes, so an arm making a finished one says what it holds.
gh_object() {
  printf '%s\n' "$1" >>"$DEVBIN_TEST_TMPDIR/gh.releases"
  printf '%s\n' "$2" >"$DEVBIN_TEST_TMPDIR/gh.obj.$1.name"
  printf '%s\n' "$3" >"$DEVBIN_TEST_TMPDIR/gh.obj.$1.body"
}

# fingerprint <proj> [--allow-gh-reads] -- every file's bytes, every ref, the
# local git config, the remote's refs, and every gh call. Anything a release
# could write changes this; releasecore.bats' control arm shows each of those
# changing it.
#
# --allow-gh-reads drops `gh release view` and `gh auth status` from the gh
# half, for the arms whose subject READS the release object: a read is not a
# write, and every other gh call still counts.
fingerprint() {
  local proj="$1" reads=keep
  [ "${2:-}" != --allow-gh-reads ] || reads=drop
  (
    cd "$proj" &&
      find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "$(cksum <"$f")" "$f"
      done
  )
  git -C "$proj" for-each-ref
  git -C "$proj" config --local --list
  git -C "$proj" status --porcelain --ignored --untracked-files=all
  git -C "$DEVBIN_TEST_TMPDIR/remote.git" for-each-ref
  if [ -e "$DEVBIN_TEST_TMPDIR/gh.calls" ]; then
    if [ "$reads" = drop ]; then
      grep -vE '^gh (release view|auth status)( |$)' "$DEVBIN_TEST_TMPDIR/gh.calls" || true
    else
      cat "$DEVBIN_TEST_TMPDIR/gh.calls"
    fi
  fi
}

# release_in <proj> <args...> -- devbin_run with the gh stub first on PATH, so
# the one place that knows how a fixture's devbin is invoked stays the one place.
release_in() {
  local proj="$1"
  shift
  PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" devbin_run "$proj" release "$@"
}

# ci_query_decl <wait> -- the release: lines declaring the fixture's ci.query:
# $DEVBIN_TEST_TMPDIR/ciq, which records the arguments it was given in ci.calls,
# with the DEVBIN_RELEASE_TAG it was run under as a last word `tag=<tag>`,
# and prints its answers from ci.answers one per call, the last one repeating,
# or runs $DEVBIN_TEST_TMPDIR/ciq.sh instead when an arm writes one. HERE, not
# in releasecut.bats, since releasepublish.bats asks it about a candidate (0240).
ci_query_decl() {
  cat >"$DEVBIN_TEST_TMPDIR/ciq" <<SH
#!/usr/bin/env bash
printf '%s tag=%s\n' "\$*" "\${DEVBIN_RELEASE_TAG-<unset>}" >>"$DEVBIN_TEST_TMPDIR/ci.calls"
if [ -f "$DEVBIN_TEST_TMPDIR/ciq.sh" ]; then . "$DEVBIN_TEST_TMPDIR/ciq.sh"; fi
a="$DEVBIN_TEST_TMPDIR/ci.answers"
head -n 1 "\$a"
if [ "\$(wc -l <"\$a")" -gt 1 ]; then tail -n +2 "\$a" >"\$a.next" && mv "\$a.next" "\$a"; fi
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/ciq"
  printf '  ci:\n    query: %s\n    wait: %s' "$DEVBIN_TEST_TMPDIR/ciq" "$1"
}

# ci_answers <line>... -- what the query answers, one line per call.
ci_answers() { printf '%s\n' "$@" >"$DEVBIN_TEST_TMPDIR/ci.answers"; }

# formula_tap -- a bare repository at $TAP standing in for devbin's Homebrew
# tap, its main holding one commit with a README, as a tap made on GitHub
# would. formula.bats publishes to it by --tap, and releasecut.bats through the
# default tap's url (ST0009).
formula_tap() {
  local seed="$DEVBIN_TEST_TMPDIR/seed"
  TAP="$DEVBIN_TEST_TMPDIR/tap.git"
  git init -q --bare -b main "$TAP"
  git init -q -b main "$seed"
  printf '# tap\n' >"$seed/README.md"
  git -C "$seed" add README.md
  git -C "$seed" -c user.name=t -c user.email=t@t commit -q -m seed
  git -C "$seed" push -q "$TAP" main
}

# with_dated_note <proj> -- VERSION 1.0.0 and a CHANGELOG.md whose [1.0.0] heading
# is dated, so the notes half of release check passes under the default kind
# (changelog) and an arm's exit status answers for its own subject alone.
with_dated_note() {
  printf '1.0.0\n' >"$1/VERSION"
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- first\n' >"$1/CHANGELOG.md"
}

# row_of <step> -- the <step> row of the last `run`'s output, whole, the step by
# its name: the LAST line that is a row as release_row prints it, two blanks,
# the name, then one of the states a row can be in. The last, because a cut
# prints its table when it stops, after every step's own output, and a step's
# own table can name a row the same way (the attach's `object` row). `release status` and a
# cut's summary share that table. A line of a step's own output that begins
# with a step's name is not a row, since a state word must follow it. THE ONE
# HOME OF THAT PREDICATE: state_of reads its state from this line, so an arm
# that reads a row's state and its detail reads them from the same line.
row_of() {
  # $output is bats's, set by the caller's `run`; this file never assigns it.
  # shellcheck disable=SC2154
  awk -v n="$1" '
    $0 ~ /^  [^ ]/ && $1 == n && $2 ~ /^(done|already|skipped|not|FAILED|would|pending|UNREADABLE)$/ { row = $0 }
    END { if (row != "") print row }
  ' <<<"$output"
}

# state_of <step> -- the state column of the <step> row (row_of), `(no row
# <step>)` when the table has none. A state of two words is read whole: `not
# re-run`, a publishing cut's `not reached` and status's `not read` (0240),
# which reading the first word alone would take for one another.
state_of() {
  local row
  row="$(row_of "$1")" || return
  if [ -z "$row" ]; then
    printf '(no row %s)\n' "$1"
    return 0
  fi
  awk '{ if ($2 == "not") print $2 " " $3; else print $2 }' <<<"$row"
}

# assert_state <step> <state> -- the <step> row is in <state>, or fail showing
# the table.
assert_state() {
  local got
  got="$(state_of "$1")"
  [ "$got" = "$2" ] || fail "the $1 row is '$got', want '$2':
$output"
}
