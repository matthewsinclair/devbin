#!/usr/bin/env bash
# at-accounting.sh -- does a v3 migration carry every AT and every AC the v2 source declared?
#
# TWO ARMS, because the defect has two halves. cc drove `legacy::scan` on arca_cli
# ST0011 and found the same loss on AC rows as on AT rows: 49 of 57 criteria before
# the parser fix, 57 of 57 after. A one-armed version of this script measured half
# the defect while reporting a total.
#
# Per thread, per arm, three surfaces:
#   source  distinct `- AT-x.y` / `- AC-x.y` ids in the v2 source
#   store   .tests[].id / .criteria[].id in intent/.canon/st/<ID>.json
#   view    distinct ids in the v3 flat intent/st/<ID>/acceptance.md
#
# THE SOURCE PATH IS LOCATED, NEVER ASSUMED. Threads live under COMPLETED/,
# NOT-STARTED/, CANCELLED/ and the flat dir; an earlier version assumed COMPLETED/
# and silently missed two Baize threads (12 ATs) -- a MISSING shortfall, which reads
# as clean. Working tree first, then the pre-migration commit (parent of the commit
# that first added .canon/), so the check survives a bucket prune.
#
# WHY AT ALL. arca_cli's hop 2 printed `residue: 0 blocking, 3 carried` and `ok:`
# while dropping 26 of 55 ATs, and verify-canonical.sh passed 0 failed over it.
# `residue: N carried` reports rows the parser REACHED. Rows it never reached are
# invisible to it, and the counts were in no tool's contract anywhere in the chain.
#
# ALSO, FROM cc, AND IT REWRITES EVERY PAST RESIDUE REPORT: a dropped AC manufactures
# a BrokenReference on every AT that covers it. The migrations have been accusing
# authors of links they DID write. Only residues that survive a re-conversion are real.
#
# Exit 1 on any shortfall in either arm, 0 clean, 2 usage.

set -uo pipefail

ids() { grep -o "^- $1-[0-9]\{1,\}\.[0-9]\{1,\}" 2>/dev/null | sed 's/^- //' | sort -u; }
count() { printf '%s\n' "$1" | grep -c . || true; }

# The pre-migration ref. Two cases, and picking the wrong one is a FALSE CLEAN:
#   committed migration   -> the parent of the commit that first added intent/.canon
#   UNCOMMITTED migration -> HEAD, because HEAD is still the v2 tree (Lamplight: the
#                            accounting runs before the commit, so no commit adds canon)
# CONTROL: the chosen ref must NOT contain intent/.canon. If it does it is not a
# pre-migration ref, and the flat acceptance.md there is the v3 VIEW -- comparing the
# output against itself returns clean for every thread. Refuse rather than guess.
#
# THIS GUARD IS UNFIRED AND SAYS SO. Two plausible triggers were built and neither
# reproduced it: a --depth 1 shallow clone (git still reports the grafted root as an
# add) and canon arriving by `git mv` (git counts a rename destination as an add for
# the path). Both cases behaved correctly WITHOUT the guard. It is kept because it can
# only ever REFUSE, never falsely pass, so its cost is three lines and its downside is
# nil -- but do not read it as tested protection. If you find the trigger, say so here.
premigration_ref() {
  local root="$1" mig ref
  mig="$(git -C "$root" log --diff-filter=A --format=%H -- intent/.canon 2>/dev/null | tail -1)"
  if [ -n "$mig" ]; then ref="$(git -C "$root" rev-parse "${mig}^" 2>/dev/null)"
  else ref="$(git -C "$root" rev-parse HEAD 2>/dev/null)"; fi
  [ -n "$ref" ] || return 1
  if git -C "$root" ls-tree -r --name-only "$ref" -- intent/.canon 2>/dev/null | grep -q .; then
    return 2   # not a pre-migration ref -- caller must not fall back to it
  fi
  printf '%s' "$ref"
}

# arm <root> <id> <kind AT|AC> <jq-path> <src-text-file> -> prints a row, returns 1 on shortfall
arm() {
  local root="$1" id="$2" kind="$3" jqp="$4" srctext="$5"
  local src store view ns nt nv short
  src="$(ids "$kind" < "$srctext")"
  ns=$(count "$src")
  [ "$ns" -eq 0 ] && { printf '  %-8s %s  NOT PROBEABLE (no %s rows in source)\n' "$id" "$kind" "$kind"; return 0; }
  view=""; [ -f "$root/intent/st/$id/acceptance.md" ] && view="$(ids "$kind" < "$root/intent/st/$id/acceptance.md")"
  store="$(jq -r "($jqp // [])[].id" "$root/intent/.canon/st/$id.json" 2>/dev/null | sort -u)"
  nv=$(count "$view"); nt=$(count "$store"); short=$(( ns - nt ))
  if [ "$short" -gt 0 ]; then
    printf '  %-8s %s  source %-5d store %-5d view %-5d  SHORTFALL %d\n' "$id" "$kind" "$ns" "$nt" "$nv" "$short"
    printf '           %s lost, by WP: ' "$kind"
    comm -23 <(printf '%s\n' "$src") <(printf '%s\n' "$store") | sed "s/$kind-\([0-9]\{1,\}\)\..*/\1/" | sort -u | tr '\n' ' '
    printf '\n'
    [ "$nt" -ne "$nv" ] && printf '           NOTE store and view DISAGREE (%d vs %d)\n' "$nt" "$nv"
    return 1
  fi
  printf '  %-8s %s  source %-5d store %-5d view %-5d  ok\n' "$id" "$kind" "$ns" "$nt" "$nv"
  return 0
}

# THE THIRD SURFACE: A ROW CAN ARRIVE COMPLETE AND STILL LOSE HALF ITS MEANING.
# Both arms above count IDS. A test row citing two criteria -- `-- covers AC-13.2 +
# AC-13.3 --` -- that migrates with covers:["AC-13.2"] arrives, is green, and counts
# match on every id. The second citation is simply gone, and where another AT covers
# the same criterion the coverage gap is masked too. Measured on Lamplight by intent/vc
# (13 rows, 7 masked); Devbin is clean at 436 rows / 26 multi.
#
# SEPARATOR-AGNOSTIC BY CONSTRUCTION, AND THAT IS THE LOAD-BEARING CHOICE. The defect
# was reported with a `+` joiner; Devbin's 26 multi-rows all use a COMMA. An arm keyed
# on the joiner it was first shown finds nothing here and reports the estate clean --
# the same defect as this morning's status:-comma survey. So this never parses the
# joiner: it takes the covers clause and counts DISTINCT AC ids in it, whatever sits
# between them.
covers_arm() {
  local root="$1" id="$2" srctext="$3"
  local json="$root/intent/.canon/st/$id.json" src canon bad n_rows n_multi n_bad
  [ -f "$json" ] || return 0
  src="$(awk '
    /^- AT-[0-9]+\.[0-9]+/ {
      id = $2; rest = $0
      if (match(rest, /--[ \t]*covers[ \t]+/)) {
        rest = substr(rest, RSTART + RLENGTH)
        if (match(rest, /[ \t]--/)) rest = substr(rest, 1, RSTART - 1)
        n = 0; split("", seen)
        while (match(rest, /AC-[0-9]+\.[0-9]+/)) {
          ac = substr(rest, RSTART, RLENGTH)
          if (!(ac in seen)) { seen[ac] = 1; n++ }
          rest = substr(rest, RSTART + RLENGTH)
        }
        if (n > 0) print id, n
      }
    }' "$srctext" | sort)"
  n_rows=$(printf '%s\n' "$src" | grep -c . || true)
  if [ "$n_rows" -eq 0 ]; then
    printf '  %-8s COVERS  NOT PROBEABLE (no AT row carries a covers clause)\n' "$id"; return 0
  fi
  n_multi=$(printf '%s\n' "$src" | awk '$2>1' | grep -c . || true)
  canon="$(jq -r '(.tests // [])[] | "\(.id) \((.covers // []) | length)"' "$json" 2>/dev/null | sort)"
  # A row absent from canon is the FIRST arm's finding, not this one -- do not double-report.
  bad="$(join -j1 <(printf '%s\n' "$src") <(printf '%s\n' "$canon") 2>/dev/null | awk '$2>$3')"
  n_bad=$(printf '%s\n' "$bad" | grep -c . || true)
  if [ "$n_bad" -gt 0 ]; then
    printf '  %-8s COVERS  rows %-5d multi %-4d SHORTFALL %d\n' "$id" "$n_rows" "$n_multi" "$n_bad"
    printf '           citations lost, by row: '
    printf '%s\n' "$bad" | awk '{printf "%s (%s->%s) ", $1, $2, $3}'
    printf '\n'
    return 1
  fi
  printf '  %-8s COVERS  rows %-5d multi %-4d ok\n' "$id" "$n_rows" "$n_multi"
  return 0
}

scan() {
  local root="$1" rc=0 pre="" wt git_paths="" git_threads threads tmp
  # A BAD PATH MUST NOT LOOK LIKE A CLEAN PROJECT. Callers write this verdict into
  # commit messages, so "nothing to account for" from a typo would read as a pass.
  if [ ! -d "$root" ]; then
    printf '  ERROR: no such directory -- nothing was measured\n'; return 3
  fi
  if [ ! -f "$root/intent/.config/config.json" ]; then
    printf '  ERROR: not an Intent project (no intent/.config/config.json) -- nothing was measured\n'; return 3
  fi
  command -v jq >/dev/null 2>&1 || { printf '  ERROR: jq not on PATH -- the store could not be read\n'; return 3; }
  [ -d "$root/intent/.canon" ] || { printf '  NOT MIGRATED -- no intent/.canon, nothing to account for\n'; return 0; }
  pre="$(premigration_ref "$root")" || {
    [ $? -eq 2 ] && printf '  ERROR: the pre-migration ref still contains intent/.canon -- refusing to compare the view against itself\n' && return 3
    pre=""
  }
  wt="$(find "$root/intent/st" -mindepth 2 -maxdepth 3 -name acceptance.md 2>/dev/null | sed 's|.*/\(ST[0-9]\{1,\}\)/acceptance\.md|\1|' | sort -u)"
  if [ -n "$pre" ]; then
    git_paths="$(git -C "$root" ls-tree -r --name-only "$pre" -- intent/st 2>/dev/null | grep '/acceptance\.md$')"
  fi
  git_threads="$(printf '%s\n' "$git_paths" | sed 's|.*/\(ST[0-9]\{1,\}\)/acceptance\.md|\1|' | grep '^ST' | sort -u)"
  threads="$(printf '%s\n%s\n' "$wt" "$git_threads" | grep . | sort -u)"
  [ -n "$threads" ] || { printf '  NO SOURCE SURFACE -- NOT PROBEABLE\n'; return 0; }

  tmp="$(mktemp)"; local id noac=0 unread=0 done_n=0
  for id in $threads; do
    local wtp gp; wtp=""; gp=""; : > "$tmp"
    # mindepth 3 = a status bucket. The FLAT working-tree file is the v3 VIEW, never the source.
    wtp="$(find "$root/intent/st" -mindepth 3 -maxdepth 3 -path "*/$id/acceptance.md" 2>/dev/null | head -1)"
    if [ -n "$wtp" ]; then cat "$wtp" > "$tmp"
    elif [ -n "$pre" ]; then
      gp="$(printf '%s\n' "$git_paths" | grep "/$id/acceptance\.md\$" | head -1)"
      [ -n "$gp" ] && git -C "$root" show "$pre:$gp" > "$tmp" 2>/dev/null
    fi
    if [ ! -s "$tmp" ]; then
      # TWO DIFFERENT STATEMENTS, AND ONLY ONE IS A GAP. "No acceptance file exists in
      # the source" means there was never anything to lose; "a file exists and the
      # resolver could not read it" is a real hole. Counting them together makes a
      # reader go to the source ref to find out which it was -- naming a blind spot
      # without sizing it, one level down.
      if [ -z "$wtp$gp" ]; then
        noac=$((noac+1))
        printf '  %-8s --  NOT PROBEABLE: no acceptance.md in the v2 source (nothing to lose)\n' "$id"
      else
        unread=$((unread+1))
        printf '  %-8s --  UNREADABLE SOURCE: %s exists but yielded nothing -- REAL GAP\n' "$id" "${wtp:-$gp}"
      fi
      continue
    fi
    done_n=$((done_n+1))
    arm "$root" "$id" AT '.tests'    "$tmp" || rc=1
    arm "$root" "$id" AC '.criteria' "$tmp" || rc=1
    covers_arm "$root" "$id" "$tmp" || rc=1
  done
  rm -f "$tmp"
  # ALWAYS emit a verdict for the project. A run that produced no rows at all is a
  # SILENT ZERO -- indistinguishable from clean at a glance, and it is not clean.
  if [ "$done_n" -eq 0 ]; then
    printf '  VERDICT: NOTHING WAS MEASURED -- %d enumerated, %d with no acceptance.md in source, %d UNREADABLE. NOT a pass.\n' "$((noac+unread))" "$noac" "$unread"
  else
    printf '  VERDICT: %d thread(s) measured; %d with no acceptance.md in source (nothing to lose); %d UNREADABLE (real gap)\n' "$done_n" "$noac" "$unread"
  fi
  [ "$unread" -gt 0 ] && rc=1
  return $rc
}

# Builds a throwaway repo: a FLAT thread whose only source is the pre-migration ref,
# with the migration UNCOMMITTED (no commit ever adds intent/.canon, so HEAD is v2).
# Self-contained on purpose -- this arm must work on any machine, not only where
# Devbin and arca_cli happen to live.
make_fixture() {   # $1 = dir, $2 = ATs/ACs the store keeps, $3 = flat|bucket
  local d="$1" keep="$2" layout="${3:-flat}" i sd
  if [ "$layout" = bucket ]; then sd="$d/intent/st/COMPLETED/ST0001"; else sd="$d/intent/st/ST0001"; fi
  mkdir -p "$d/intent/.config" "$sd" "$d/intent/st/ST0001"
  printf '{"intent_version":"3.0.0"}\n' > "$d/intent/.config/config.json"
  git -C "$d" init -q 2>/dev/null
  { for i in 1 2 3 4 5; do printf -- '- AT-01.%d some test citation covering AC-01.%d -- status: green\n' "$i" "$i"; done
    for i in 1 2 3 4 5; do printf -- '- AC-01.%d (non-test) a criterion -- satisfied: yes\n' "$i"; done
  } > "$sd/acceptance.md"
  git -C "$d" add -A 2>/dev/null
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm v2 2>/dev/null
  # now the "migration": canon written, flat view rewritten, NEITHER committed
  mkdir -p "$d/intent/.canon/st"
  { printf '{"tests":['; for i in $(seq 1 "$keep"); do [ "$i" -gt 1 ] && printf ','; printf '{"id":"AT-01.%d"}' "$i"; done
    printf '],"criteria":['; for i in $(seq 1 "$keep"); do [ "$i" -gt 1 ] && printf ','; printf '{"id":"AC-01.%d"}' "$i"; done
    printf ']}\n'; } > "$d/intent/.canon/st/ST0001.json"
  { for i in $(seq 1 "$keep"); do printf -- '- AT-01.%d some test citation covering AC-01.%d -- status: green\n' "$i" "$i"; done
    for i in $(seq 1 "$keep"); do printf -- '- AC-01.%d (non-test) a criterion -- satisfied: yes\n' "$i"; done
  } > "$d/intent/st/ST0001/acceptance.md"
  # bucket layout: commit the migration so premigration_ref takes the parent path
  if [ "$layout" = bucket ]; then
    git -C "$d" add -A 2>/dev/null
    git -C "$d" -c user.email=t@t -c user.name=t commit -qm v3 2>/dev/null
  fi
}

# A fixture for the covers arm ALONE. Both id-counting arms come out CLEAN on it by
# design -- 2 ATs in and 2 stored, 4 ACs in and 4 stored -- so if the covers arm is
# broken this fixture is indistinguishable from a healthy project. That is the whole
# point: it reproduces a defect that is structurally invisible to every arm that
# counts ids. BOTH JOINERS APPEAR, `+` and `,`, and the comma row is the one that
# must NOT be reported -- an arm that cries wolf on a joiner it does not recognise
# fails this fixture just as loudly as one that stays silent.
make_covers_fixture() {   # $1 = dir, $2 = keep|lose
  local d="$1" mode="$2" sd
  sd="$d/intent/st/ST0001"   # NOT in the `local` above: bash resolves $d there against the OUTER scope, which set -u makes fatal
  mkdir -p "$d/intent/.config" "$sd"
  printf '{"intent_version":"3.0.0"}\n' > "$d/intent/.config/config.json"
  git -C "$d" init -q 2>/dev/null
  { printf -- '- AT-01.1 t::"plus form" -- covers AC-01.1 + AC-01.2 -- status: green\n'
    printf -- '- AT-01.2 t::"comma form" -- covers AC-01.3, AC-01.4 -- status: green\n'
    printf -- '- AC-01.1 (non-test) a -- satisfied: yes\n'
    printf -- '- AC-01.2 (non-test) b -- satisfied: yes\n'
    printf -- '- AC-01.3 (non-test) c -- satisfied: yes\n'
    printf -- '- AC-01.4 (non-test) d -- satisfied: yes\n'
  } > "$sd/acceptance.md"
  git -C "$d" add -A 2>/dev/null
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm v2 2>/dev/null
  mkdir -p "$d/intent/.canon/st"
  # lose: the `+` row arrives with ONE of its two citations. keep: both survive.
  if [ "$mode" = lose ]; then
    printf '{"tests":[{"id":"AT-01.1","covers":["AC-01.1"]},{"id":"AT-01.2","covers":["AC-01.3","AC-01.4"]}],' > "$d/intent/.canon/st/ST0001.json"
  else
    printf '{"tests":[{"id":"AT-01.1","covers":["AC-01.1","AC-01.2"]},{"id":"AT-01.2","covers":["AC-01.3","AC-01.4"]}],' > "$d/intent/.canon/st/ST0001.json"
  fi
  printf '"criteria":[{"id":"AC-01.1"},{"id":"AC-01.2"},{"id":"AC-01.3"},{"id":"AC-01.4"}]}\n' >> "$d/intent/.canon/st/ST0001.json"
}

if [ "${1:-}" = "--self-test" ]; then
  # EACH ARM IS PROVEN SEPARATELY. A self-test that only exercises AT would pass
  # with a broken AC arm -- the exact hole that let this script miss NOT-STARTED/.
  D="$HOME/Devel/prj/Devbin"; A="$HOME/Devel/prj/Arca/arca_cli"
  dt="$(scan "$D" 2>/dev/null)"; drc=$?
  at="$(scan "$A" 2>/dev/null)"; arc=$?   # advisory only -- a real estate can be REPAIRED
  echo "SELF-TEST -- every arm must return BOTH answers, or it is not measuring."
  ok=1
  chk() { if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; ok=0; fi; }
  # Properties, not counts: a fixture gaining a thread must not wedge the instrument,
  # but an arm that goes silent or cries wolf must still fail.
  atleast() { [ "$2" -ge "$3" ] && printf '  PASS  %s (%s)\n' "$1" "$2" || { printf '  FAIL  %s (got %s, want >=%s)\n' "$1" "$2" "$3"; ok=0; }; }
  atleast "Devbin   AT arm reports a clean thread" "$(printf '%s\n' "$dt" | grep -c 'AT .*ok')" 1
  atleast "Devbin   AC arm reports a clean thread" "$(printf '%s\n' "$dt" | grep -c 'AC .*ok')" 1
  chk     "Devbin   AT arm cries no wolf"          "$(printf '%s\n' "$dt" | grep -c 'AT .*SHORTFALL')" "0"
  chk     "Devbin   AC arm cries no wolf"          "$(printf '%s\n' "$dt" | grep -c 'AC .*SHORTFALL')" "0"
  chk     "Devbin   rc 0"                          "$drc" "0"
  # THE LOSSY ARM MUST NOT DEPEND ON A REAL ESTATE STAYING BROKEN. arca_cli was this
  # fixture until intent/vc re-converted it, and the self-test failed because the
  # subject had been FIXED. A fixture that can be repaired out from under you is not a
  # fixture. arca_cli is reported below as advisory corroboration, never asserted on.
  bx="$(mktemp -d)"; make_fixture "$bx/lossy" 3 bucket
  bl="$(scan "$bx/lossy" 2>/dev/null)"; brc=$?
  atleast "bucket-layout AT arm sees the loss"     "$(printf '%s\n' "$bl" | grep -c 'AT .*SHORTFALL 2')" 1
  atleast "bucket-layout AC arm sees the loss"     "$(printf '%s\n' "$bl" | grep -c 'AC .*SHORTFALL 2')" 1
  chk     "bucket-layout rc 1"                     "$brc" "1"
  rm -rf "$bx"
  printf '  info  arca_cli (advisory, real estate): rc=%s\n' "$arc"

  # FLAT-ONLY, MIGRATION UNCOMMITTED -- Lamplight's shape. Before this arm existed the
  # instrument printed NO SOURCE FILE FOUND for every in-progress thread in that project
  # and said nothing about how large the unmeasured set was.
  fx="$(mktemp -d)"; fl=""; fc=""; fr=0
  make_fixture "$fx/lossy" 3 flat          # 5 declared, 3 stored
  fl="$(scan "$fx/lossy" 2>/dev/null)"; fr=$?
  chk     "flat-only thread is MEASURED, not NO SOURCE" "$(printf '%s\n' "$fl" | grep -c 'NO SOURCE FILE FOUND')" "0"
  atleast "flat-only AT arm sees the loss"              "$(printf '%s\n' "$fl" | grep -c 'AT .*SHORTFALL 2')" 1
  atleast "flat-only AC arm sees the loss"              "$(printf '%s\n' "$fl" | grep -c 'AC .*SHORTFALL 2')" 1
  chk     "flat-only rc 1"                              "$fr" "1"
  make_fixture "$fx/clean" 5 flat          # 5 declared, 5 stored
  fc="$(scan "$fx/clean" 2>/dev/null)"; fr=$?
  atleast "flat-only clean case measured"               "$(printf '%s\n' "$fc" | grep -c ' ok')" 2
  chk     "flat-only clean rc 0"                        "$fr" "0"
  rm -rf "$fx"
  # ---- THE COVERS ARM, DRIVEN BOTH WAYS ----
  cx="$(mktemp -d)"
  make_covers_fixture "$cx/lose" lose
  cl="$(scan "$cx/lose" 2>/dev/null)"; crc=$?
  chk     "covers  the two id arms see NOTHING (that is the point)" "$(printf '%s\n' "$cl" | grep -c 'SHORTFALL')" "1"
  atleast "covers  arm fires on the lost citation"                  "$(printf '%s\n' "$cl" | grep -c 'COVERS .*SHORTFALL 1')" 1
  atleast "covers  the losing row is NAMED"                         "$(printf '%s\n' "$cl" | grep -c 'AT-01.1 (2->1)')" 1
  chk     "covers  the COMMA row is not cried wolf on"              "$(printf '%s\n' "$cl" | grep -c 'AT-01.2')" "0"
  chk     "covers  lossy rc 1"                                      "$crc" "1"
  make_covers_fixture "$cx/keep" keep
  ck="$(scan "$cx/keep" 2>/dev/null)"; crc=$?
  atleast "covers  clean case is MEASURED, not skipped"             "$(printf '%s\n' "$ck" | grep -c 'COVERS .*multi 2 .*ok')" 1
  chk     "covers  clean case cries no wolf"                        "$(printf '%s\n' "$ck" | grep -c 'COVERS .*SHORTFALL')" "0"
  chk     "covers  clean rc 0"                                      "$crc" "0"
  rm -rf "$cx"
  atleast "Devbin  covers arm reports a clean thread"               "$(printf '%s\n' "$dt" | grep -c 'COVERS .*ok')" 1
  chk     "Devbin  covers arm cries no wolf"                        "$(printf '%s\n' "$dt" | grep -c 'COVERS .*SHORTFALL')" "0"
  [ "$ok" = 1 ] && { echo "SELF-TEST PASS -- all three arms, on bucket and flat-only layouts, see clean and lossy."; exit 0; }
  echo "SELF-TEST FAIL -- do not trust a green from this script."; exit 1
fi

[ $# -ge 1 ] || { echo "usage: at-accounting.sh <project-dir> | --self-test" >&2; exit 2; }
printf '=== %s ===\n' "$1"; scan "$1"
