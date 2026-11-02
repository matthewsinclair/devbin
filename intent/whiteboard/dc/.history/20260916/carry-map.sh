#!/usr/bin/env bash
# carry-map.sh -- for every NON-BULLET line in a pre-migration board body
# (board lead, section prose, sub-heading, table row, section heading), find
# where its text landed in the rendered board. Bullets are excluded: they are
# carried as items and are not the class under test.
#
# Output, tab-separated:
#   node  class  pre_line  section  rendered_line|ABSENT  as_bullet|-  first_60_chars
#
# The pre-migration snapshots are at <node>/.history/20260916/, so this reads
# the 2026-09-16 migration only. Rendered line numbers go stale at the next
# write to a board; the classes do not.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

for n in hv cc vc; do
  pre="intent/whiteboard/$n/.history/20260916/wip-premigration.md"
  now="intent/whiteboard/$n/wip.md"
  [ -f "$pre" ] || { echo "MISSING $pre" >&2; exit 1; }
  [ -f "$now" ] || { echo "MISSING $now" >&2; exit 1; }

  while IFS=$'\t' read -r class lineno section text; do
    # needle: the first 60 chars, minus any leading markdown marker we expect
    # the renderer to have rewritten
    needle="$text"
    case "$class" in
      SUBHEAD) needle="${needle#\#\#\# }" ;;
      SECTIONHEAD) needle="${needle#\#\# }" ;;
    esac
    needle="${needle:0:60}"

    # AN EMPTY NEEDLE MATCHES EVERY LINE, and it is this instrument's one
    # demonstrated false green: the first run read all five dropped board leads
    # as carried to line 1, with 57 to 69 hits each. Refuse rather than report.
    [ -n "$needle" ] || { echo "carry-map: empty needle at $n:$lineno ($class)" >&2; exit 1; }

    hits="$(grep -n -F -e "$needle" "$now" || true)"
    if [ -z "$hits" ]; then
      nhits=0; rline="ABSENT"; bullet="-"
    else
      nhits="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
      first="${hits%%$'\n'*}"
      rline="${first%%:*}"
      rtext="${first#*:}"
      case "$rtext" in
        "- "*) bullet="bullet" ;;
        "## "*) bullet="heading" ;;
        *) bullet="other" ;;
      esac
    fi
    printf '%s\t%s\t%s\t%s\t%s(x%s)\t%s\t%s\n' "$n" "$class" "$lineno" "$section" "$rline" "$nhits" "$bullet" "${text:0:60}"
  done < <(awk '
    BEGIN { fm = 0; sec = "" }
    NR == 1 && /^---$/ { fm = 1; next }
    fm == 1 { if ($0 ~ /^---$/) fm = 2; next }
    /^## / { sec = $0; print "SECTIONHEAD\t" NR "\t" sec "\t" $0; next }
    /^### / { print "SUBHEAD\t" NR "\t" sec "\t" $0; next }
    /^# / { next }
    /^[[:space:]]*$/ { next }
    /^\|/ { print "TABLEROW\t" NR "\t" sec "\t" $0; next }
    /^[[:space:]]*[-*] / { next }
    { cls = (sec == "" ? "BOARDLEAD" : "SECTIONPROSE"); print cls "\t" NR "\t" (sec == "" ? "(above-first-section)" : sec) "\t" $0 }
  ' "$pre")
done
