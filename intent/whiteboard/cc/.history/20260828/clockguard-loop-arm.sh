#!/usr/bin/env bash
# v2. The v1 harness used a FIXED stamp that had aged into the past, so every
# drift was about -60 and nothing could refuse under either flavour: a green
# that was trivially true. The stamp must be in the CURRENT minute for the race
# to exist at all, so read it from the clock at loop time.
set -u
to_epoch_bsd() { date -u -j -f '%Y-%m-%d %H:%M' "$1" '+%s'; }
to_epoch_gnu() { /opt/homebrew/bin/gdate -u -d "$1" '+%s'; }

run() {  # $1 = flavour fn, $2 = stamp count
  local fn="$1" n="$2" stamp now i drift max=-9999 refused=0
  stamp="$(date -u +'%Y-%m-%d %H:%M')"   # a heartbeat written THIS minute, as a node writes it
  now="$(date -u '+%s')"                 # the guard's :214 -- once, before the loop
  for ((i = 0; i < n; i++)); do
    drift=$(( $($fn "$stamp") - now ))
    [ "$drift" -gt "$max" ] && max="$drift"
    [ "$drift" -gt 0 ] && refused=$(( refused + 1 ))
  done
  printf '  %-3s stamps=%-4s max drift=%-4ss  would REFUSE: %s/%s\n' \
         "${fn#to_epoch_}" "$n" "$max" "$refused" "$n"
}

echo "=== BSD: a stamp written in the CURRENT minute ==="
for n in 1 5 20 60 120; do run to_epoch_bsd "$n"; done
echo
echo "=== GNU: identical loop. If this also refuses, the harness is measuring elapsed time, not a flavour defect ==="
for n in 1 5 20 60 120; do run to_epoch_gnu "$n"; done
echo
echo "=== POSITIVE CONTROL: a stamp 5 minutes in the FUTURE must refuse under BOTH ==="
fut_b=$(date -u -v+5M +'%Y-%m-%d %H:%M'); now=$(date -u '+%s')
echo "  bsd drift on a +5min stamp = $(( $(to_epoch_bsd "$fut_b") - now ))s  (must be ~+300, i.e. REFUSE)"
echo "  gnu drift on a +5min stamp = $(( $(to_epoch_gnu "$fut_b") - now ))s  (must be ~+300, i.e. REFUSE)"
