#!/usr/bin/env bash
# devbin-vc -- Conflab Phase 4 after-read.
#
# EXECUTES ONLY THE METHOD COMMITTED AT 8d8b336. No check here is new. Written
# and committed BEFORE the measurement, for the same reason the predictions were:
# an instrument fixed after seeing the tree is not an instrument.
#
# READ-ONLY. Every git call uses --no-optional-locks so a status read cannot
# rewrite .git/index, which other nodes may be reading as evidence.
set -uo pipefail

C="${1:-/Users/matts/Devel/prj/Conflab}"
B="${2:-$(cd "$(dirname "$0")" && pwd)}"
BASE="$B/conflab-prehop-census.txt"
OUT="${3:-/tmp}"
cd "$C" || { echo "FATAL: cannot cd $C"; exit 1; }

echo "=== SCOPE: $(date -u +'%Y-%m-%d %H:%M:%SZ')  tree=$C  baseline=$BASE"

# --- binary identity: cite the sha AND the command that produced it ----------
R="$(command -v intent)"; T="$(readlink "$R" 2>/dev/null || echo "$R")"
echo "binary: $(shasum -a 256 "$T" | awk '{print $1}')  <- shasum -a 256 \$(readlink \$(command -v intent))"
echo "version: $(intent --version 2>&1)"

# --- Q1: is it on v3 ---------------------------------------------------------
echo "=== Q1"
echo "config: $(grep -o '\"intent_version\": \"[^\"]*\"' intent/.config/config.json)"
echo "canon:  $([ -d intent/.canon ] && echo PRESENT || echo ABSENT)"
read_verb() {                            # args passed as args, never word-split
  local o rc
  o="$(intent "$@" 2>&1)"; rc=$?         # rc captured BEFORE any pipe
  echo "intent $* -> rc=$rc  refuses=$(printf '%s' "$o" | grep -c 'has not been migrated' || true)"
}
read_verb st list
read_verb issues list
read_verb todo
read_verb doctor

# --- census + the three failure shapes ---------------------------------------
echo "=== Q2 census"
N="$OUT/conflab-posthop-census.txt"
find intent bin/.devbin .git/hooks -type f -print0 2>/dev/null | xargs -0 shasum -a 256 > "$N.raw" 2>/dev/null
for f in ./*.md; do [ -e "$f" ] || continue; shasum -a 256 "$f"; done >> "$N.raw"
sed -i.bak 's#  \./#  #' "$N.raw" && rm -f "$N.raw.bak"
sort -k2 "$N.raw" > "$N"
echo "rows: baseline=$(wc -l < "$BASE" | tr -d ' ')  after=$(wc -l < "$N" | tr -d ' ')"

van="$(comm -23 <(awk '{print $2}' "$BASE") <(awk '{print $2}' "$N"))"
app="$(comm -13 <(awk '{print $2}' "$BASE") <(awk '{print $2}' "$N"))"
chg="$(join -j2 -o 0,1.1,2.1 "$BASE" "$N" | awk '$2!=$3{print $1}')"
printf 'vanished=%s appeared=%s changed=%s\n' \
  "$(printf '%s' "$van" | grep -c . || true)" \
  "$(printf '%s' "$app" | grep -c . || true)" \
  "$(printf '%s' "$chg" | grep -c . || true)"

# NEGATIVE CONTROL, run every time: a zero above means nothing unless this fires.
cp "$BASE" "$OUT/.ctl"; sed -i.bak '5d' "$OUT/.ctl"; rm -f "$OUT/.ctl.bak"
ctl="$(comm -23 <(awk '{print $2}' "$BASE") <(awk '{print $2}' "$OUT/.ctl") | grep -c . || true)"
echo "NEGATIVE CONTROL (must be 1): $ctl"; rm -f "$OUT/.ctl"

# --- P7: the seam is OUTSIDE the declared changed set ------------------------
echo "=== P7 seam (any change here is the STOP condition)"
printf '%s\n' "$chg" "$van" "$app" | grep -c '^bin/\.devbin/' || true

# --- P6: the carrier. git can NEVER see this path ----------------------------
echo "=== P6 carrier"
for h in pre-commit pre-commit.intent; do
  f=".git/hooks/$h"
  [ -f "$f" ] && printf '%-18s %6s b  mode=%s  %s\n' "$h" "$(wc -c < "$f" | tr -d ' ')" \
    "$(stat -f '%Lp' "$f")" "$(shasum -a 256 "$f" | cut -c1-16)" || printf '%-18s ABSENT\n' "$h"
done

# --- P8 / P9: structure ------------------------------------------------------
echo "=== P8/P9 structure"
printf 'st dirs=%s info.md=%s WP=%s open=%s closed=%s docs=%s llm=%s\n' \
  "$(find intent/st -maxdepth 2 -type d -name 'ST*' 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/st -name info.md 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/st -type d -path '*/WP/*' 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/issues/OPEN -type f 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/issues/CLOSED -type f 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/docs -type f 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/llm -type f 2>/dev/null | wc -l | tr -d ' ')"
printf 'intent/history: %s files, non-YYYYMM-done entries=%s\n' \
  "$(find intent/history -type f 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find intent/history -mindepth 1 2>/dev/null | grep -vcE '[0-9]{6}-done\.md$' || true)"

# --- git view: whole repo, covers tracked paths my census does not -----------
echo "=== git view"
git --no-optional-locks log -1 --format='HEAD %h %s' | cat
git --no-optional-locks status --porcelain > "$OUT/posthop-porcelain.txt"
echo "porcelain rows: $(wc -l < "$OUT/posthop-porcelain.txt" | tr -d ' ')"

echo "=== lists written to $OUT ; vanished/appeared/changed below"
printf 'VANISHED:\n%s\nAPPEARED:\n%s\nCHANGED:\n%s\n' "$van" "$app" "$chg" > "$OUT/conflab-delta.txt"
echo "delta file: $OUT/conflab-delta.txt ($(wc -l < "$OUT/conflab-delta.txt" | tr -d ' ') lines)"
