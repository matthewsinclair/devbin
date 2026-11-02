#!/usr/bin/env bash
# devbin-cc Phase 4: carrier verdict + shadow verdict. READ-ONLY.
# NEVER invokes .git/hooks/pre-commit (project dispatcher: prettier --write,
# git add, mix format, git add, bin/precommit-rust -> writes + index + build).
set -uo pipefail
C=/Users/matts/Devel/prj/Conflab
T=/Users/matts/Devel/prj/Intent/lib/templates/hooks/pre-commit-shim.sh
BEFORE="$(dirname "$0")/conflab-before.txt"

echo "# devbin-cc Phase 4, read at $(date -u +'%Y-%m-%d %H:%MZ')"
echo

echo "## CHECK 1 -- carrier, and the template read in the SAME command"
CAR=$(shasum -a 256 "$C/.git/hooks/pre-commit.intent" | awk '{print $1}')
TPL=$(shasum -a 256 "$T" | awk '{print $1}')
echo "  cmd: shasum -a 256 \$CONFLAB/.git/hooks/pre-commit.intent  AND  \$INTENT/lib/templates/hooks/pre-commit-shim.sh"
echo "  carrier  sha256 $CAR"
echo "  template sha256 $TPL   <- re-read now, not carried forward"
echo "  carrier  bytes  $(stat -f '%z' "$C/.git/hooks/pre-commit.intent")"
echo "  carrier  mode   $(stat -f '%Sp' "$C/.git/hooks/pre-commit.intent")   (cmd: stat -f '%Sp')"
echo "  guard refs      $(grep -cE 'GUARD_RUNNER|pre-commit-guards\.sh|intent/home' "$C/.git/hooks/pre-commit.intent")   (cmd: grep -cE 'GUARD_RUNNER|pre-commit-guards.sh|intent/home')"
WHERE_N=$(grep -cE -- '--where' "$C/.git/hooks/pre-commit.intent")
echo "  --where hits    $WHERE_N"
if [ "$CAR" = "814d055e9e45422223947e213897981f1f8cbfcf0eaeee2f674368d7ecc3360b" ]; then
  V="NOT REPLACED -- carrier is byte-identical to the pre-hop v2 gate. FINDING."
elif [ "$CAR" = "$TPL" ]; then
  V="PASS -- carrier is byte-identical to this install's shim template, read in the same command."
else
  V="REPLACED WITH SOMETHING THAT IS NOT CANON'S CURRENT TEMPLATE. FINDING, and the interesting one."
fi
echo "  VERDICT: $V"
case "$(stat -f '%Sp' "$C/.git/hooks/pre-commit.intent")" in
  *x*) echo "  MODE: executable -- the chain block's [ -x ] will fire." ;;
  *)   echo "  MODE: NOT EXECUTABLE -- FINDING. [ -x ] has no else, so every commit passes at rc=0 with the gate reported as wired." ;;
esac
echo

echo "## CHECK 2 -- --where on the CARRIER, guarded"
if [ "$CAR" != "814d055e9e45422223947e213897981f1f8cbfcf0eaeee2f674368d7ecc3360b" ] && [ "$WHERE_N" -gt 0 ]; then
  echo "  guard passed (sha moved AND --where present); running: bash .git/hooks/pre-commit.intent --where"
  ( cd "$C" && bash .git/hooks/pre-commit.intent --where 2>&1 | sed 's/^/    /' )
else
  echo "  NOT INVOKED. Guard: sha moved = $([ "$CAR" != 814d055e9e45422223947e213897981f1f8cbfcf0eaeee2f674368d7ecc3360b ] && echo yes || echo no), --where present = $([ "$WHERE_N" -gt 0 ] && echo yes || echo no)."
  echo "  Not invoking is the correct action here, not a skipped check."
fi
echo

echo "## CHECK 3 -- shadows: 20 files (git ls-files, NOT a glob)"
cd "$C"
echo "  population: $(git ls-files bin/.devbin/cmd/ | wc -l | tr -d ' ')  (cmd: git ls-files bin/.devbin/cmd/)"
echo "  git verdict (cmd: git status --porcelain -- bin/.devbin/cmd/):"
GS=$(git status --porcelain -- bin/.devbin/cmd/)
if [ -z "$GS" ]; then echo "    clean -- the hop touched nothing under cmd/"; else printf '%s\n' "$GS" | sed 's/^/    /'; fi
echo "  hash control vs 09:10Z before-state:"
git ls-files bin/.devbin/cmd/ | while IFS= read -r f; do shasum -a 256 "$f"; done > /tmp/cc-p4-after.txt
if grep -q 'cmd/' "$BEFORE" 2>/dev/null; then
  DIFF=$(diff <(grep -oE '^[0-9a-f]{64}  bin/\.devbin/cmd/.*' "$BEFORE" | sort) <(sort /tmp/cc-p4-after.txt) || true)
  if [ -z "$DIFF" ]; then echo "    all 20 hashes identical to before"; else printf '%s\n' "$DIFF" | sed 's/^/    /'; fi
fi
echo "  named explicitly: use=$(shasum -a 256 bin/.devbin/cmd/use | awk '{print $1}')"
echo "                    precommit=$(shasum -a 256 bin/.devbin/cmd/precommit | awk '{print $1}')"
echo

echo "## CHECK 3b -- live service + tracked lockfiles (intent-vc, 11:26Z)"
PID_NOW=$(pgrep -f 'conflabd start' | head -1)
echo "  cmd: pgrep -f 'conflabd start'"
echo "  conflabd pid now: ${PID_NOW:-<none>}   before: 7438"
if [ "$PID_NOW" = "7438" ]; then echo "    same pid -- daemon not restarted"
elif [ -z "$PID_NOW" ]; then echo "    *** DAEMON IS GONE. FINDING -- it was serving before the hop. ***"
else echo "    *** PID CHANGED ($PID_NOW). FINDING -- the daemon restarted across the hop. ***"; fi
for b in conflab conflabd; do
  t=$(readlink "$(command -v $b 2>/dev/null)" 2>/dev/null)
  [ -n "$t" ] && echo "  $b sha256 $(shasum -a 256 "$t" | awk '{print $1}')  (cmd: shasum -a 256 \$(readlink \$(command -v $b)))"
done
echo "  before: conflab  897c99f509ae08b0f144a39e79ee69e2ed5a1272504a1e4f03cfcdde605d06fa"
echo "  before: conflabd ff16e479ebfb754934311b11ed457960b0f4b1c4adcdfa48574997abdf4a5f35"
for f in mix.lock native/Cargo.lock; do
  echo "  $f sha256 $(shasum -a 256 "$C/$f" | awk '{print $1}')"
done
echo "  before: mix.lock          fc9c66b0a67f82c90e2342f4e3afa90170e755f6bedcf8d66f6fa145a6d9efe4"
echo "  before: native/Cargo.lock e2f0f1f5c69439313d9f469eec5e20725709471d92c193085bc6be1494a4d17c"
echo "  NOTE: a moved lockfile is TRACKED, so it is attributable to the hop rather than to build artefacts."

echo "## CHECK 4 -- hop binary identity at read time"
B=$(readlink "$(command -v intent)" 2>/dev/null || command -v intent)
echo "  cmd: shasum -a 256 \$(readlink \$(command -v intent))"
echo "  resolved $B"
echo "  sha256   $(shasum -a 256 "$B" | awk '{print $1}')"
echo "  expected 1dd65db8b49363b1d2ad0b454179e9db67b6e406e10389e6a2f7d6e9ca98ae26  (captured 08:52Z; a change means rule 2 was broken)"
echo "  version  $(intent --version 2>&1)"
