#!/usr/bin/env bash
# Does appending ':00' + '%S' pin the seconds field under BSD, the way the guard's
# comment CLAIMS the '<date> 00:00' normalisation already does?
set -u
GDATE=/opt/homebrew/bin/gdate

probe() {  # $1 = label, $2 = shell fn name
  local label="$1" fn="$2" a b t0
  a=$($fn)
  t0=$(date -u '+%s'); while [ "$(date -u '+%s')" -lt "$((t0 + 3))" ]; do :; done
  b=$($fn)
  printf '%-46s %s -> %s   moved %ss\n' "$label" "$a" "$b" "$(( b - a ))"
}

# --- the guard AS SHIPPED, both paths ---
cur_bsd()  { date -u -j -f '%Y-%m-%d %H:%M' '2026-08-28 16:31' '+%s'; }
cur_norm() { date -u -j -f '%Y-%m-%d %H:%M' '2026-08-28 00:00' '+%s'; }   # the date-only "fix"
# --- the PROPOSED fix: seconds named in the value AND in the format ---
fix_bsd()  { date -u -j -f '%Y-%m-%d %H:%M:%S' '2026-08-28 16:31:00' '+%s'; }
fix_norm() { date -u -j -f '%Y-%m-%d %H:%M:%S' '2026-08-28 00:00:00' '+%s'; }
# --- GNU under the proposed fix must be unchanged ---
fix_gnu()  { "$GDATE" -u -d '2026-08-28 16:31:00' '+%s'; }
cur_gnu()  { "$GDATE" -u -d '2026-08-28 16:31'    '+%s'; }

echo "=== AS SHIPPED ==="
probe "bsd, HH:MM stamp (the unfixed path)"        cur_bsd
probe "bsd, date-only normalised to 00:00 (fixed?)" cur_norm
probe "gnu, HH:MM stamp"                            cur_gnu
echo
echo "=== PROPOSED FIX: append :00 to the value, %S to the format ==="
probe "bsd, HH:MM:SS stamp"                         fix_bsd
probe "bsd, midnight with :00 seconds"              fix_norm
probe "gnu, HH:MM:SS stamp"                         fix_gnu
echo
echo "=== do the two flavours AGREE under the fix? ==="
echo "bsd = $(fix_bsd)   gnu = $(fix_gnu)"
[ "$(fix_bsd)" = "$(fix_gnu)" ] && echo "  AGREE" || echo "  *** DISAGREE ***"
