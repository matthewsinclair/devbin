---
node: vc
name: Validation Claude
role: validation
session_id: 37214cfb-198a-4b48-980d-d4ab03e852d6
heartbeat_at: 2026-08-29 11:54Z
status: active
focus: "Folded 2026-08-29 11:47Z, aggressively, first fold of 2026-08-29. Nothing in flight, nothing claimed. Waiting for hv. One thing needs a RULING and is surfaced: devbin-cc's BSD-only clock-guard defect in Intent, verified independently here, and cc will not file it unprompted"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT.** Waiting for hv's instructions.
- **STATUS IS DELIBERATELY `active`** -- a fold, not a release. `/in-finish`'s release step and protocol invariant 6 disagree about a pre-compact fold; cc measured the cost at 3.5 hours off every peer's roster. Upstream's to settle.

## Re-measured at this fold, not carried

**Re-verified 2026-08-29 11:54Z on a session resume: every row below unchanged, nothing folded, no commit churned.** The suite row is the one that cannot be re-run cheaply, so it is corroborated instead: `git log 73b45bf..HEAD -- lib/ bin/ tests/` is **empty**, so no code has moved since it was measured.

| claim | measured |
| --- | --- |
| open issues | **0034, 0035, 0036, 0039, 0040, 0042** (`intent issues list`) |
| fleet | **11 estates, one stamp `96fb408`** -- uniform since the 2026-08-28 sweep |
| suite | **725/725**, 0 failures, 2 self-declaring skips, rc 0, unpiped |
| tree | clean but for hv's board and inbox, written this fold |

## AWAITING A RULING FROM hv -- the only live item

**devbin-cc found a BSD-only defect in Intent's `whiteboard-clock-guard.sh` and is asking whether to file it as an Intent issue.** They will not file unprompted: `intent#0105` went in on hv's explicit instruction and they do not treat that as standing authority. **Surfaced to `hv/inbox.vc.md` at 2026-08-29 11:47Z.**

**Verified here rather than relayed** -- cc had corrected their own mechanism once inside four minutes in that thread. `to_epoch`'s BSD arm parses `'%Y-%m-%d %H:%M'` (`:209`), naming no seconds; `TOLERANCE_SECONDS=0` (`:180`) compared with `-gt` (`:368`); `now_epoch` read once before the loop. **My measurement: the same stamp parsed twice, two seconds apart, returns epochs 2 apart and 52s off true; a seconds-explicit control returns the identical epoch both times.** GNU does not fill, so **the broken arm is the one no Linux CI runs.** On macOS it is a coin-flip weighted by sub-second timing, which is why a retry clears it. **It fails CLOSED, so nothing bad lands** -- the cost is refused commits.

## TODO -- hv's to sequence, none started

- **0035 is not a fix**: four instances each ending *"state whether this is a convention"*. **0034 is real code** but **Lamplight-originated and hv runs that track**. **0036 is upstream with no local fix** -- `bats tests/` is hardcoded at Intent's `_AGENTS.md:91`; cc's verified sharpening is that `bin/.devbin/config.yaml:40` already declares `run: bats tests/unit`, so **the repo holds the right answer and the generated file contradicts it**.
- **0040 is the one I would take next and it is mine**: wire `updatenotice.bats`'s firing test with `require_pty`, which `clean.bats` already proves works. Stopped short deliberately -- new coverage for a path nothing has exercised wants care, not speed.
- **0039 and 0042 are filed to be DECIDED, not implemented as written.** Both name candidate fixes of different blast radius.
- **The `st attach` ruling is owed** -- the only thing that closes the 54. `organize` reads `54 unclaimed, 0 to remove`: a report category. **Do not close that number by moving anything.**
- **v2 issues residue: 34 markdown directories.** v3 writes none. Flagged, untouched; the last tidy-up of a document set here was reversed.
- **`intent issues` has no edit verb** -- surfaced. 0036's body asks a question I have since answered.

**Blocked, not merely unsequenced:** **`use` as a devbin builtin is BLOCKED and not to be designed around.** **STILL EXPLICITLY DO NOT START: `--ivault`.**

## Watch-outs

General forms are in `intent/llm/LESSONS.md`. These are live, and the top three are the day's.

- **TWO FLAVOURS AGREEING IS WHAT A DEAD INSTRUMENT AND A CORRECT ONE BOTH LOOK LIKE.** cc's, and the sharpest of the day: their first clock-guard harness pinned a stamp already aged into the past, so nothing could refuse under EITHER flavour -- 0/120 for both, a clean symmetric result meaning nothing. **Only a positive control separated them.**
- **A CORRECT FIX WITH A WRONG STATED REASON IS WORSE THAN AN UNEXPLAINED ONE**, because the wrong reason reads as a class-level guarantee and nobody looks again. The clock guard's author fixed the date-only instance and left the `HH:MM` one three lines away, under a comment claiming normalisation *pins* a field it does not pin.
- **A BOARD THAT IS READ AT EVERY PICKUP BUT WRITTEN BY EXCEPTION DRIFTS BY CONSTRUCTION.** `hv/wip.md`'s `focus:` has now gone stale twice in four days -- the file every node reads for standing directives. **A node that reads a stale directive complies with it.**
- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD.** Paid twice: a directive guard that printed `*** STOP ***` and committed anyway on a FALSE alarm, and a red-drive harness that printed `*** NOTHING WENT RED ***` three times while all three drives WERE red -- `pipefail` handing it bats's rc, **issue 0031's shape inside the control written to catch it.** Settle by extraction and `cmp` with a negative control.
- **A BROKEN EXTRACTOR MAKES A SET-CONTAINMENT TEST PASS VACUOUSLY** -- every element of the empty set is named; only the floor caught it. **AN EXTRACTOR THAT READS COMMENTS IS READING THE WRONG DOCUMENT** -- mine reported a code 126 this source has never exited, one step from entering the contract.
- **A ZERO MEANING "MATCHED NOTHING" IS INDISTINGUISHABLE FROM ONE MEANING "NOTHING CHANGED."** A bogus pathspec returns the same zero, which is why the control is not optional.
- **COUNTING A PROXY COUNTS THE PROXY** -- three `source_commit` stamps read as three-way divergence; the bytes said two. **Digest the vendored `lib/`.**
- **A HEARTBEAT IS EVIDENCE ABOUT THE LAST WRITE, NOT ABOUT THE NODE** -- cc read three hours stale while mid-fold.
- **A CLAIM THAT NAMES A COUNT OR A STATE HAS AN EXPIRY DATE.** Three times in one day from my own work. **Anything a fold keeps needs re-measuring or an explicit carried-forward-unverified mark** (cc's rule, applied above).
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE** -- `-maxdepth 3` reproduced the `Arca/` decoy in the session that had read the warning. **A RELAY IS NOT AN INSTRUCTION.** **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION.**

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here. **I hold that pen under hv's explicit grant; corrections are factual only and the directives are byte-verified every time.**
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc`.** Lamplight is hv's separate track.
- **Rule 2 (no builds in the Intent tree) is LIFTED**; rules 3 (`git add` + `commit --only` by path) and 4 (timestamps read from `date -u` in the writing command) stand. **Rule 3 is what made the fleet sweep safe in three estates with live sessions.**
- **`bin/devbin` is the invocation everywhere** (supersedes D6). **Delivery while in development is the DEV TREE.**
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`.**
