---
node: vc
name: Validation Claude
role: validation
session_id: 37214cfb-198a-4b48-980d-d4ab03e852d6
heartbeat_at: 2026-08-29 13:20Z
status: active
focus: "Folded 2026-08-29 13:20Z. Nothing in flight, tree clean, both inboxes at sentinel. NEXT INSTRUCTION COMES FROM intent-vc per hv. FLEET IS TWELVE ESTATES AND SPLIT 7/5, not eleven and uniform -- Utilz was added today and five are one seam commit behind. One item still needs an hv RULING: cc's BSD-only clock-guard defect, surfaced"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT.** **hv has handed the next instruction to `intent-vc`.** Take direction from them; hv remains the authority above them.
- **STATUS IS DELIBERATELY `active`** -- a fold, not a release.

## Re-measured at this fold, not carried

| claim | measured |
| --- | --- |
| open issues | **0034, 0035, 0036, 0039, 0040, 0042** |
| fleet | **TWELVE estates, split 7/5** -- see below. The previous board said eleven and uniform; both halves were true when written and both are now false |
| suite | **728/728**, 0 failures, 2 self-declaring skips, rc 0 |
| tree | clean |

## The fleet is twelve now, and it is not uniform

**`Utilz` is a twelfth estate**, installed 2026-08-29 13:31 -- after the census that produced the eleven, so that count was correct when taken and expired within a day. **A census is a photograph, and an estate can be created between the shutter and the reading.**

| stamp | estates |
| --- | --- |
| `eecf4c0` (current HEAD) | Baize, Conflab, Intent, Laksa, Lamplight, Prolix, **Utilz** |
| `96fb408` | Intentv2, MicroGPTEx, Riffle, arca_cli, arca_config |

**The five are exactly ONE seam commit behind** -- `95b2645`, the 0039 message fix, which touches `bin/devbin`. Measured with a pathspec array in bash and both controls taken: `HEAD..HEAD` returns 0, and **a bogus pathspec returns the same 0**, which is the whole reason the control is not optional.

**A re-vendor of the five needs hv's go**, as before. Utilz is currently the only estate carrying the 0039 fix.

**`bin/devbin version` printing `utilz 2.4.0` is CORRECT and was worth checking.** `version` is *"show, set and bump the project version"*; `devbin` is *"about devbin itself... not this project's"*. Conflab prints `conflab 0.6.2` / `devbin 0.1.0`; Utilz prints `utilz 2.4.0` / `devbin 0.1.0`. Its launcher is byte-identical to source. **The output shape is the one the standing constraint warns about** -- a plausible version under devbin's name -- **and the mechanism is not**, which is exactly why it had to be measured rather than reasoned about.

## AWAITING AN hv RULING -- surfaced, not chased

**devbin-cc's BSD-only defect in Intent's `whiteboard-clock-guard.sh`, and whether to file it as an Intent issue.** cc will not file unprompted: `intent#0105` went in on hv's explicit instruction and they do not read that as standing authority. In `hv/inbox.vc.md` at 2026-08-29 11:46Z.

**Verified here, not relayed.** `to_epoch`'s BSD arm parses `'%Y-%m-%d %H:%M'` (`:209`), naming no seconds; `TOLERANCE_SECONDS=0` (`:180`) against `-gt` (`:368`); `now_epoch` read once before the loop. **My measurement: the same stamp parsed twice two seconds apart returns epochs 2 apart and 52s off true; a seconds-explicit control returns the identical epoch.** GNU does not fill, so **the broken arm is the one no Linux CI runs.** Fails CLOSED -- nothing bad lands, the cost is refused commits and a retry that "fixes" it.

## TODO

**Mine, ready to start:**

- **0040 is the one I would take next.** Wire `updatenotice.bats`'s firing test with `require_pty`, which `clean.bats` already proves works. New coverage for a path nothing has exercised, so it wants care.
- **THE FLEET RE-VENDOR: five estates are one seam commit behind (`95b2645`).** Needs hv's go. **The 2026-08-28 sweep took three commits because it waited**, which argues for the next one being sooner.

**hv's or intent-vc's to sequence, none started:**

- **0039 is PARTLY fixed and deliberately still OPEN.** `95b2645` applied the cheapest of its three remedies -- the refusal now names the argument, so hv's `init` case reads correctly. **Its title is still literally true**: the diagnosis is still made by where the caller stands, the message still says *"every command would act on <root>"* about something that may not be a command, and the exit-code question is untouched. **Closing it would claim more than was done.**
- **0035 is not a fix** -- four instances each ending *"state whether this is a convention"*. **0034 is real code** but **Lamplight-originated, hv's track**. **0036 is upstream with no local fix**; cc's verified sharpening is that `bin/.devbin/config.yaml:40` already declares `run: bats tests/unit`, so **the repo holds the right answer and the generated file contradicts it**. **0042** is filed to be decided, not implemented as written.
- **The `st attach` ruling is owed** -- the only thing that closes the 54. `organize` reads `54 unclaimed, 0 to remove`: a report category. **Do not close that number by moving anything.**
- **v2 issues residue: 34 markdown directories.** v3 writes none. Flagged, untouched.
- **`intent issues` has no edit verb** -- surfaced. 0036's body asks a question I have since answered.

**Blocked, not merely unsequenced:** **`use` as a devbin builtin is BLOCKED and not to be designed around.** **STILL EXPLICITLY DO NOT START: `--ivault`.**

## Watch-outs

General forms are in `intent/llm/LESSONS.md`.

- **TWO FLAVOURS AGREEING IS WHAT A DEAD INSTRUMENT AND A CORRECT ONE BOTH LOOK LIKE.** cc's: their first clock-guard harness pinned a stamp already aged into the past, so nothing could refuse under EITHER flavour -- 0/120 for both, symmetric and meaningless. **Only a positive control separated them.**
- **A CORRECT FIX WITH A WRONG STATED REASON IS WORSE THAN AN UNEXPLAINED ONE**, because the wrong reason reads as a class-level guarantee and nobody looks again.
- **A BOARD READ AT EVERY PICKUP BUT WRITTEN BY EXCEPTION DRIFTS BY CONSTRUCTION.** `hv/wip.md`'s `focus:` went stale twice in four days. **A node that reads a stale directive complies with it.**
- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD.** Paid twice, once inside the control written to catch that class (`pipefail` handing it bats's rc -- issue 0031's shape).
- **A BROKEN EXTRACTOR MAKES A SET-CONTAINMENT TEST PASS VACUOUSLY** -- every element of the empty set is named; only the floor caught it. **AN EXTRACTOR THAT READS COMMENTS IS READING THE WRONG DOCUMENT.**
- **A ZERO MEANING "MATCHED NOTHING" IS INDISTINGUISHABLE FROM ONE MEANING "NOTHING CHANGED."** A bogus pathspec returns the same zero.
- **COUNTING A PROXY COUNTS THE PROXY** -- three `source_commit` stamps read as three-way divergence; the bytes said two. **Digest the vendored `lib/`.**
- **A HEARTBEAT IS EVIDENCE ABOUT THE LAST WRITE, NOT ABOUT THE NODE.**
- **A CLAIM THAT NAMES A COUNT OR A STATE HAS AN EXPIRY DATE.** **Anything a fold keeps needs re-measuring or an explicit carried-forward-unverified mark** (cc's rule, applied above).
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE.** **A RELAY IS NOT AN INSTRUCTION.** **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION.**

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here. **I hold that pen under hv's explicit grant; corrections factual only, directives byte-verified every time.**
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc`.** Lamplight is hv's separate track.
- **Rule 2 (no builds in the Intent tree) is LIFTED**; rules 3 (`git add` + `commit --only` by path) and 4 (timestamps read from `date -u` in the writing command) stand. **Rule 3 is what made the fleet sweep safe in three estates with live sessions.**
- **`bin/devbin` is the invocation everywhere** (supersedes D6). **Delivery while in development is the DEV TREE.**
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`.**
