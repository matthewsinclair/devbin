#!/usr/bin/env bats
# workroom.bats - the shipped tree carries no workroom text (issue 0216).
#
# devbin is developed in a private repository and published from it: the paths
# tests/shipped.paths lists are what a public reader gets. Comments and test
# titles written for the people and tools working on devbin read as noise to
# that reader, and some of them point at files the public tree does not carry.
# So no shipped line may name a collaborator by handle, credit an automated
# review, say how a thing was ruled, or point into intent/, where the
# development record lives. A comment keeps its technical reason and drops who
# said it, which pass found it, and when; a test title says what it checks.
#
# BY SHAPE. Each arm but one knows what it refuses by its shape alone, and each
# of those proves on every run that it can go red: a planted file it must flag
# line by line, an innocent one it must pass, and only then the tree.
#
# BY NAME, THE ONE (issue 0242). A project's name has no shape, so the names
# arm refuses the names in the workroom's list of unshipped names,
# intent/llm/unshipped-names: one a line, in any case, as a whole word, and
# inside a session's name (`<name>-xy`) or an identifier (`<name>_cli`,
# `<NAME>_ROOT`) too. The list is under intent/, which tests/shipped.paths
# leaves out, so the public tree carries this arm and none of the names: there
# it reads no list, and skips saying so rather than pass. It carries no
# planted control, so this file names none of the names.
#
# The handles are refused as words in any case, so `CC` is refused too.
# No shipped file uses one as a word today; if a build fixture ever needs the
# compiler variable, the refusal names the line, and the arm is where to say
# so.
#
# WHAT IS READ is what ships: tests/shipped.paths, which includes and excludes
# (the fleet command's files are left out there, as the snapshot leaves them
# out). EXEMPT BY PATH: this file alone, whose controls plant every shape. The
# pointer arm also passes .gitignore, which lists the development tree's
# paths as configuration, and the citations arm passes the release notes.
#
# WHAT THIS DOES NOT READ, declared so a green is never read as covering it:
#   - a name in prose, which has no shape: a person, a session, a project
#     the names arm's list does not hold;
#   - for the names arm, a listed name run into a longer word, such as a
#     daemon's `<name>d`, and in a tree without the list, any name;
#   - the private sense of a common word (estate, fleet, session), which no
#     shape can tell from its product sense;
#   - a date or a commit cited in a comment, which neutral.bats refuses in the
#     vendored runtime and nothing refuses elsewhere;
#   - a phrase split across two lines;
#   - a file git does not track: the list is read through git ls-files;
#   - a file git reads as binary, such as the logo's PDF.

load "../lib/test_helper"
load "../lib/vendored_set"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# This file: never scanned.
_WORKROOM_EXEMPT=(':(exclude)tests/unit/workroom.bats')

# _workroom_files [pathspec...] -- every tracked file tests/shipped.paths lists,
# less the exempt ones and any further pathspecs given, as absolute paths one a
# line. A list that cannot be read, or that git cannot answer, fails the
# listing rather than shortening it.
_workroom_files() {
  local list="$DEVBIN_HOME/tests/shipped.paths" out rc=0
  local -a specs=()
  [ -f "$list" ] || return 1
  mapfile -t specs < <(pathlist_specs "$(<"$list")") || return 1
  [ "${#specs[@]}" -gt 0 ] || return 1
  out="$(git -C "$DEVBIN_HOME" ls-files --eol -- "${specs[@]}" "${_WORKROOM_EXEMPT[@]}" "$@")" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ -n "$out" ] || return 1
  # A file git itself reads as binary (`i/-text`, eg the logo's PDF) holds no
  # line to read, and grep -a would read its bytes as if it did.
  awk -F '\t' -v home="$DEVBIN_HOME" '{ split($1, eol, " ") } eol[1] != "i/-text" { print home "/" $2 }' <<<"$out" || return 1
  return 0
}

# The workroom's list of unshipped names: the projects no shipped line may
# name, one a line. It is under intent/, which tests/shipped.paths leaves out,
# so it never ships: the names in a shipped file would publish what the arm
# keeps out.
_WORKROOM_NAMES_LIST='intent/llm/unshipped-names'

# _workroom_names -- the names the list holds, one a line, read as
# tests/shipped.paths is read, through pathlist_specs: every line but a blank
# one or a `#` comment. 1 when the list is absent, as in the public tree; 2
# when it is not a file that reads, holds no name, or holds a line that is not
# one word of ASCII letters and digits, which the names arm's pattern could
# not hold as one name.
_workroom_names() {
  local list="$DEVBIN_HOME/$_WORKROOM_NAMES_LIST" text names
  [ -e "$list" ] || return 1
  [ -f "$list" ] || return 2
  text="$(<"$list")" || return 2
  names="$(pathlist_specs "$text")" || return 2
  [ -n "$names" ] || return 2
  local rc=0
  LC_ALL=C grep -q -v -x -E '[A-Za-z0-9]+' <<<"$names" || rc=$?
  [ "$rc" -eq 1 ] || return 2
  printf '%s\n' "$names"
}

# _workroom_hits <arm> <out> <file>... -- write to <out>, as path:line:text,
# every line of the files that <arm> refuses. 0 when every file was read, hits
# or not; 2 when a scan failed, because an empty <out> reads as clean.
_workroom_hits() {
  local arm="$1" out="$2" raw="$2.raw"
  shift 2
  : >"$raw" || return 2
  case "$arm" in
    handles)
      # A handle: hv, vc, cc or dc as a word, in any case, alone or qualified
      # (`proj/xy`, `proj-xy`), and as a fixture's committer (`xy@test`).
      vendored_scan "$raw" i "(^|[^A-Za-z0-9_])(hv|vc|cc|dc)([^A-Za-z0-9_]|\$)" "$@" || return 2
      ;;
    credits)
      # An automated review credited: a critic subagent by name, or a critic's
      # pass, review or finding. The critic gate, `check critic` and
      # `intent critic` are devbin's own and stay.
      vendored_scan "$raw" i "critic-(shell|prose|elixir|rust|lua|swift)|critic's" "$@" || return 2
      ;;
    rulings)
      # ruled, ruling or rulings, in any case, between non-letters: a rule, a
      # ruler and overruled are not one.
      vendored_scan "$raw" i "(^|[^A-Za-z])rul(ed|ings?)([^A-Za-z]|\$)" "$@" || return 2
      ;;
    pointers)
      # A pointer into intent/: a thread's or the LLM docs' directory, the
      # tracking files, the module registry and lessons, a design decision by
      # number (D12) or by name. Issue numbers and ST, WP and AC ids stay.
      vendored_scan "$raw" s "(^|[^A-Za-z0-9_.-])intent/(st|llm)([^A-Za-z0-9_]|\$)|intent/(wip|restart)\\.md|(MODULES|LESSONS|DECISION_TREE)\\.md|(^|[^A-Za-z0-9_])D[0-9]{1,3}([^0-9A-Za-z_]|\$)|[Dd]esign [Dd]ecision" "$@" || return 2
      ;;
    citations)
      # A citation a public reader cannot look up: a directive by number, a
      # contract amendment by number (amendment A5), or a bare A<N> on a line
      # with a T<N>. docs/dev-opt-brew.md names its sections T1 to T10 and no
      # amendment, so a comment cites the section and the issue.
      vendored_scan "$raw" s "(^|[^A-Za-z0-9_])([Dd]irective|DIRECTIVE)s? [0-9]|(^|[^A-Za-z0-9_])([Aa]mendment|AMENDMENT)s? A[0-9]|(^|[^A-Za-z0-9_])T[0-9]+[^A-Za-z0-9_](.*[^A-Za-z0-9_])?A[0-9]+([^A-Za-z0-9_]|\$)|(^|[^A-Za-z0-9_])A[0-9]+[^A-Za-z0-9_](.*[^A-Za-z0-9_])?T[0-9]+([^A-Za-z0-9_]|\$)" "$@" || return 2
      ;;
    names)
      # A name the workroom's list holds, in any case, between characters that
      # are not letters or digits: so a session's name (`<name>-xy`) and an
      # identifier (`<name>_cli`, `<NAME>_ROOT`) carry it, and a longer word
      # holding it does not.
      local alt
      alt="$(_workroom_names)" || return 2
      vendored_scan "$raw" i "(^|[^A-Za-z0-9])(${alt//$'\n'/|})([^A-Za-z0-9]|\$)" "$@" || return 2
      ;;
    *) return 2 ;;
  esac
  LC_ALL=C sort -u "$raw" >"$out" || return 2
  return 0
}

# _workroom_plant <name> <line>... -- a file of exactly these lines, its path
# printed.
_workroom_plant() {
  local f="$DEVBIN_TEST_TMPDIR/$1"
  shift
  printf '%s\n' "$@" >"$f"
  printf '%s\n' "$f"
}

# _workroom_arm <arm> <remedy> <positive-file> <negative-file> [pathspec...] --
# each planted line flagged, no innocent line flagged, and no shipped line
# flagged, every hit named by path and line.
_workroom_arm() {
  local arm="$1" remedy="$2" pos="$3" neg="$4" out="$DEVBIN_TEST_TMPDIR/$1.out"
  local rc=0 n want files
  local -a sf
  shift 4
  _workroom_hits "$arm" "$out" "$pos" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read its control (status $rc)"
  n="$(awk 'END { print NR }' "$out")"
  want="$(awk 'END { print NR }' "$pos")"
  [ "$n" -eq "$want" ] || fail "the $arm scan flagged $n of the $want planted lines:\n$(cat "$out")"
  _workroom_hits "$arm" "$out" "$neg" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read its control (status $rc)"
  [ ! -s "$out" ] || fail "the $arm scan flags an innocent line:\n$(cat "$out")"
  files="$(_workroom_files "$@")" || fail "the shipped paths could not be listed"
  mapfile -t sf <<<"$files"
  _workroom_hits "$arm" "$out" "${sf[@]}" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read the shipped tree (status $rc)"
  [ ! -s "$out" ] || fail "a shipped file $remedy:\n$(sed "s|^$DEVBIN_HOME/||" "$out")"
}

@test "tests/shipped.paths lists the shipped tree, and every entry it includes names a tracked file (0216)" {
  local list="$DEVBIN_HOME/tests/shipped.paths" spec files
  [ -f "$list" ] || fail "tests/shipped.paths is not there -- the scan would read nothing"
  # An entry the list INCLUDES names something tracked. An exclusion may name
  # nothing: it keeps a path out wherever the path exists, and in the public
  # tree, which this list builds, the paths it excludes are absent.
  while IFS= read -r spec; do
    pathspec_excludes "$spec" && continue
    files="$(git -C "$DEVBIN_HOME" ls-files -- "$spec" </dev/null)" || fail "git could not list $spec"
    [ -n "$files" ] || fail "tests/shipped.paths names $spec, which holds no tracked file"
  done < <(pathlist_specs "$(<"$list")")
  files="$(_workroom_files)" || fail "the shipped paths could not be listed"
  grep -qxF "$DEVBIN_HOME/bin/devbin" <<<"$files" || fail "bin/devbin is not among the shipped files"
  grep -qxF "$DEVBIN_HOME/tests/unit/neutral.bats" <<<"$files" || fail "the tests are not among the shipped files"
  if grep -q "/tests/unit/workroom\.bats\$" <<<"$files"; then fail "the scan reads its own controls"; fi
  # AND EVERY EXCLUSION EXCLUDES: no file under an excluded path is read.
  local n=0 ex kept
  while IFS= read -r spec; do
    pathspec_excludes "$spec" || continue
    n=$((n + 1))
    kept="$(git -C "$DEVBIN_HOME" ls-files -- "$(pathspec_kept_out "$spec")" </dev/null)" || fail "git could not list what $spec keeps out"
    while IFS= read -r ex; do
      [ -n "$ex" ] || continue
      if grep -qxF "$DEVBIN_HOME/$ex" <<<"$files"; then fail "tests/shipped.paths excludes $ex, and the scan reads it"; fi
    done <<<"$kept"
  done < <(pathlist_specs "$(<"$list")")
  [ "$n" -gt 0 ] || fail "tests/shipped.paths excludes nothing -- the fleet command's files would ship"
  grep -qxF "$DEVBIN_HOME/design/devbin-logo.svg" <<<"$files" || fail "a text file under design/ is not among the shipped files"
  if grep -q '/design/devbin-logo\.pdf$' <<<"$files"; then fail "the scan reads a binary file as lines"; fi
}

@test "a path list's every exclude spelling is read as one, by the one reader the snapshot builder reads with, and keeps out what git keeps out (0261)" {
  # A fixture list in every spelling git accepts for an exclusion, beside
  # includes that look like them, read through pathlist_specs as the shipped
  # list is. Each line is classified by pathspec_excludes, and held to git's
  # own answer: what `git ls-files -- :/ <spec>` leaves out is nothing for an
  # include, and for an exclusion what its pathspec_kept_out spec lists. A row
  # may name the directory git runs in, so a spec's `top` is read where it
  # changes the answer; the fixture's files make `glob` and `icase` change it
  # too, and a path that opens with `:`, or an empty one, stays the path.
  local repo="$DEVBIN_TEST_TMPDIR/listed" text spec kind dir at want got all sel kept checked=0 rows
  git init -q "$repo"
  mkdir -p "$repo/a" "$repo/b" "$repo/c/d"
  : >"$repo/a/1" && : >"$repo/a/Up" && : >"$repo/b/x" && : >"$repo/b/y" && : >"$repo/c/z" && : >"$repo/c/w" && : >"$repo/c/d/w" && : >"$repo/:q"
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@t -c maintenance.auto=false -c gc.auto=0 commit -qm files
  all="$(git -C "$repo" ls-files | LC_ALL=C sort)"
  # kind|spec|dir: every line but a blank one or a # comment is a spec; dir is
  # where git runs, the repository's top when empty.
  text='# a fixture list
exclude|:!b/x|
exclude|:^b/x|
exclude|:/!b/x|
exclude|:!/b/x|
exclude|:!:b/x|
exclude|:/^b/x|
exclude|:^:b/x|
exclude|:(exclude)b/x|
exclude|:(,exclude)b/x|
exclude|:(top,exclude)c/|c/d
exclude|:(exclude,glob)c/**/w|
exclude|:(icase,exclude)a/up|
exclude|:!::q|
exclude|:!|

include|b/x|
include|:/b/x|
include|:(top)b/|
include|:(glob)c/*|
include|:::q|'
  rows="$(pathlist_specs "$text")"
  while IFS="|" read -r kind spec dir; do
    if pathspec_excludes "$spec"; then got=exclude; else got=include; fi
    [ "$got" = "$kind" ] || fail "$spec read as $got, and git reads it as $kind"
    at="$repo${dir:+/$dir}"
    sel="$(git -C "$at" ls-files --full-name -- :/ "$spec" </dev/null)" || fail "git refused $spec beside :/"
    sel="$(LC_ALL=C sort <<<"$sel")"
    if [ "$kind" = include ]; then
      got="$(git -C "$at" ls-files --full-name -- "$spec" </dev/null)" || fail "git refused $spec"
      [ -n "$got" ] || fail "the fixture holds nothing $spec includes, so it cannot tell an include from an exclusion"
      [ "$sel" = "$all" ] || fail "$spec is an include, which keeps nothing out, and git lists it beside :/ as [${sel//$'\n'/ }]"
    else
      want="$(LC_ALL=C comm -23 <(printf '%s\n' "$all") <(printf '%s\n' "$sel"))"
      kept="$(pathspec_kept_out "$spec")"
      got="$(git -C "$at" ls-files --full-name -- "$kept" </dev/null)" || fail "git refused $kept, the kept-out spec of $spec"
      got="$(LC_ALL=C sort <<<"$got")"
      [ -n "$want" ] || fail "the fixture keeps nothing out for $spec"
      [ "$got" = "$want" ] || fail "$spec keeps out [${want//$'\n'/ }], and its kept-out spec $kept lists [${got//$'\n'/ }]"
    fi
    checked=$((checked + 1))
  done <<<"$rows"
  [ "$checked" -eq "$(grep -c "|" <<<"$text")" ] || fail "checked $checked of the fixture list's specs"
}

@test "no shipped line names a collaborator by handle, in any case, or as a fixture's committer (0216)" {
  local pos neg
  pos="$(_workroom_plant handles.pos '# (hv, 2026-09-16)' "# as dc's review found" '# measured by vc' \
    '# Found by cc while' '# raised by intent/dc' '# devbin-cc measured it' '# webapp-dc reported' \
    '  git -c user.email=dc@test commit' '# per HV' '# CC said so' '  mkdir -p "$proj/target/cc"')"
  neg="$(_workroom_plant handles.neg '# the hvac unit' '# a cc1plus process' '# vcs and dcs' \
    '# abc, xyz' '  printf "%s" "$hv_x"' '# 0xdc0c is a mode' '# docs/ and src/')"
  _workroom_arm handles "names a collaborator by handle -- keep the lesson and drop who" "$pos" "$neg"
}

@test "no shipped line credits an automated review: a critic by name, or a critic's pass (0216)" {
  local pos neg
  pos="$(_workroom_plant credits.pos '# (critic-shell on 0139 v2e)' "# the critic's fourth pass" \
    '# critic-prose flagged it' "# THE CRITIC'S REVIEW")"
  neg="$(_workroom_plant credits.neg '# the critic gate' '  intent critic "$lang"' '# check critic' \
    '  run_critic_gate' '# shell-gate-critic.bats' '# critics run per language')"
  _workroom_arm credits "credits an automated review -- keep the reason and drop which pass found it" "$pos" "$neg"
}

@test "no shipped line says how a thing was ruled: ruled, a ruling, rulings (0216)" {
  local pos neg
  pos="$(_workroom_plant rulings.pos '# hv ruled on 2026-09-17' '# THE RULING' '# two rulings' \
    '# was ruled out' "# the ruling's words")"
  neg="$(_workroom_plant rulings.neg '# the rule is one function' '# the rules below' '# a ruler' \
    '# it was overruled' '# unruly input')"
  _workroom_arm rulings "says how a thing was ruled -- state the rule, not who settled it" "$pos" "$neg"
}

@test "no shipped line points into intent/: a thread, the registry, a design decision (0216)" {
  local pos neg
  pos="$(_workroom_plant pointers.pos '# see intent/st/ST0005/design.md' '# intent/llm/MODULES.md' \
    '# MODULES.md registers it' '# LESSONS.md' '# per D38' '# (ST0008 WP-08, D55)' '# the D11 rule' \
    '# a design decision' '# put it in intent/wip.md')"
  neg="$(_workroom_plant pointers.neg '# issue 0127, ST0007 WP-02, AC-6.1' '# ND12 and D12x' \
    '  local D1x=1' '# intent/.config/config.json' '# see intent/docs at the Intent install' \
    '# a decision about it' '# lintent/stx')"
  _workroom_arm pointers "points into intent/, which the public tree does not carry -- say the reason in place" \
    "$pos" "$neg" ':!.gitignore'
}

@test "no shipped line cites a directive or a contract amendment by number, which a public reader cannot look up (0292)" {
  local pos neg
  pos="$(_workroom_plant citations.pos '# (directive 15; issue 0250)' '# DIRECTIVE 3 says' '# directives 14 and 15' \
    '# (T4, amendment A5; issue 0246)' '# AMENDMENT A4' '# (T5, A4)' '# A3 of T4' \
    '# (T5 A4)' '# A3 T4')"
  neg="$(_workroom_plant citations.neg '# (T4; issue 0246)' '# the directive' '# an amendment to the rule' \
    '# T5 (0235)' '# cell A4 of the sheet' '  printf "%s" "$a4"' '# 0xA4 and T4x')"
  # The release notes ship as the record of what each release did, so a past
  # release's notes keep the wording they shipped with.
  _workroom_arm citations "cites a directive or an amendment the public tree does not carry -- cite the contract's section and the issue" \
    "$pos" "$neg" ':!CHANGELOG.md' ':!RELEASES.md' ':!RELEASES/'
}

@test "no shipped line names a project on the workroom's list of unshipped names, in any case, inside a session's name or an identifier too, and the list does not ship (0242)" {
  local list rc=0 files out="$DEVBIN_TEST_TMPDIR/names.out"
  local -a sf
  list="$(_workroom_names)" || rc=$?
  # The public tree carries no list, and a scan with nothing to look for is
  # not a clean one: it says it read none, and is never counted as a pass. The
  # public tree is the one that tracks nothing under intent/; a workroom that
  # lost its list fails.
  if [ "$rc" -eq 1 ] && [ -n "$(git -C "$DEVBIN_HOME" ls-files -- intent </dev/null)" ]; then
    fail "$_WORKROOM_NAMES_LIST is not in this tree, which tracks intent/, so it is the workroom and has lost its list"
  fi
  [ "$rc" -ne 1 ] || skip "read no list of unshipped names: $_WORKROOM_NAMES_LIST is not in this tree, so no shipped line was checked for one"
  [ "$rc" -eq 0 ] || fail "$_WORKROOM_NAMES_LIST does not read as one name a line: it is not a file, holds no name, or holds a line that is not one word of letters and digits"
  # THE LIST DOES NOT SHIP: a selection that took its path in would publish
  # every name it holds.
  files="$(_workroom_files)" || fail "the shipped paths could not be listed"
  grep -qxF "$DEVBIN_HOME/bin/devbin" <<<"$files" || fail "bin/devbin is not among the shipped files, so the listing is not the shipped tree"
  if grep -qxF "$DEVBIN_HOME/$_WORKROOM_NAMES_LIST" <<<"$files"; then fail "tests/shipped.paths selects $_WORKROOM_NAMES_LIST, so the list would ship"; fi
  mapfile -t sf <<<"$files"
  _workroom_hits names "$out" "${sf[@]}" || rc=$?
  [ "$rc" -eq 0 ] || fail "the names scan could not read the shipped tree (status $rc)"
  [ ! -s "$out" ] || fail "a shipped file names a project the public tree does not -- say what kind of project it is:\n$(sed "s|^$DEVBIN_HOME/||" "$out")"
}
