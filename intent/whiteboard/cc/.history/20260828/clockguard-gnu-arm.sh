#!/usr/bin/env bash
# Does GNU `date -u -d` fill an unspecified SECONDS field from the current clock,
# the way BSD `date -u -j -f` does? Two independent arms, no sleep.
set -u

STAMP='2026-08-28 16:29'
GDATE=/opt/homebrew/bin/gdate

echo "=== is gdate GNU coreutils? ==="
"$GDATE" --version | sed -n '1p'

echo
echo "=== ARM 1: differential against ground truth (seconds stated explicitly) ==="
# Ground truth: the same instant with SECONDS named as 00. Computed by BOTH flavours
# so neither is trusted as the reference.
truth_bsd=$(date  -u -j -f '%Y-%m-%d %H:%M:%S' "$STAMP:00" '+%s')
truth_gnu=$("$GDATE" -u -d "$STAMP:00"                     '+%s')
echo "truth (bsd, :00 explicit) = $truth_bsd"
echo "truth (gnu, :00 explicit) = $truth_gnu"
[ "$truth_bsd" = "$truth_gnu" ] && echo "  flavours AGREE on ground truth" || echo "  *** flavours DISAGREE on ground truth ***"

sec_before=$(date -u '+%S')
bsd_noseconds=$(date  -u -j -f '%Y-%m-%d %H:%M' "$STAMP" '+%s')   # the guard's BSD path, verbatim
gnu_noseconds=$("$GDATE" -u -d "$STAMP"          '+%s')           # the guard's GNU path, verbatim
sec_after=$(date -u '+%S')

echo "clock second before = $sec_before, after = $sec_after"
if [ "$sec_before" != "$sec_after" ]; then
  echo "  *** the minute rolled mid-measurement; ARM 1 is INCONCLUSIVE, read ARM 2 ***"
fi
echo "bsd no-seconds = $bsd_noseconds   delta vs truth = $(( bsd_noseconds - truth_bsd ))"
echo "gnu no-seconds = $gnu_noseconds   delta vs truth = $(( gnu_noseconds - truth_gnu ))"

echo
echo "=== ARM 2: does the SAME stamp parse to a DIFFERENT value as the clock moves? ==="
# Busy-wait for the wall-clock second to tick, then re-parse the identical string.
b1=$(date  -u -j -f '%Y-%m-%d %H:%M' "$STAMP" '+%s')
g1=$("$GDATE" -u -d "$STAMP"          '+%s')
t0=$(date -u '+%s')
while [ "$(date -u '+%s')" -lt "$((t0 + 3))" ]; do :; done
b2=$(date  -u -j -f '%Y-%m-%d %H:%M' "$STAMP" '+%s')
g2=$("$GDATE" -u -d "$STAMP"          '+%s')
echo "bsd: $b1 -> $b2   moved by $(( b2 - b1 ))s across a 3s wait"
echo "gnu: $g1 -> $g2   moved by $(( g2 - g1 ))s across a 3s wait"

echo
echo "=== NEGATIVE CONTROL: a stamp WITH seconds must not move under either flavour ==="
bc1=$(date  -u -j -f '%Y-%m-%d %H:%M:%S' "$STAMP:00" '+%s')
gc1=$("$GDATE" -u -d "$STAMP:00"                     '+%s')
t0=$(date -u '+%s')
while [ "$(date -u '+%s')" -lt "$((t0 + 3))" ]; do :; done
bc2=$(date  -u -j -f '%Y-%m-%d %H:%M:%S' "$STAMP:00" '+%s')
gc2=$("$GDATE" -u -d "$STAMP:00"                     '+%s')
echo "bsd control moved by $(( bc2 - bc1 ))s   (MUST be 0)"
echo "gnu control moved by $(( gc2 - gc1 ))s   (MUST be 0)"
