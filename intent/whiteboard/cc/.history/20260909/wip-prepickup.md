---
node: cc
name: Control Claude
role: control
session_id: 1e86191f-1ce1-405b-8a8c-827819fc7836
heartbeat_at: 2026-08-29 18:03Z
status: paused
focus: "EOD, released to paused after an aggressive localfold with every kept claim re-measured. Nothing in flight, nothing claimed, devbin PAUSED. THREE QUESTIONS SIT WITH hv, relayed by devbin-vc, and none is mine to take: the sync-provider standing rule, whether gtools#0003 also needs an Intent issue, and the hardcoded fleet root"
claims: []
---

# Control Claude (cc)

**Board cut 2026-08-29 17:53Z. Pre-fold state archived VERBATIM at [`.history/20260829/wip-prefold-1751Z.md`](.history/20260829/wip-prefold-1751Z.md), cmp-verified at 23872 b BEFORE this file was touched.** Yesterday's two folds are at `.history/20260828/`.

## Re-measured at this fold, 2026-08-29 17:52Z

| claim                                  | verdict                                                                                                        |
|----------------------------------------|----------------------------------------------------------------------------------------------------------------|
| devbin open issues                     | **0034, 0035, 0036, 0039, 0042** -- five. **0040 CLOSED** since my last write                                  |
| `gtools#0003`                          | **HOLDS** -- OPEN, high                                                                                        |
| `intent#0089` (other clock-guard axis) | **HOLDS** -- OPEN                                                                                              |
| 13 estates, 0 under Dropbox            | **HOLDS** -- re-counted with no depth bound                                                                    |
| `design.md` holds D1-D24               | **HOLDS** -- 74393 b                                                                                           |
| tree clean, both inboxes at sentinel   | **HOLDS**                                                                                                      |
| `cmd/fleet:188` / `:48`                | **DEAD IN 30 MINUTES.** Now `:194` and `:54`. **This board no longer cites line numbers -- see the watch-out** |
| `devbin-users.md` GENERATED AT         | **2026-08-29 14:49Z** -- three hours old, and it says not to trust it if the stamp is not from right now       |

## DOING

- **NOTHING IN FLIGHT. Nothing claimed, both inboxes at sentinel, tree clean, devbin PAUSED.**
- **Authority chain: hv -> intent-vc -> devbin-vc -> me.**
- **THREE QUESTIONS ARE WITH hv, RELAYED BY devbin-vc, AND NONE IS MINE TO TAKE.**
  1. **A standing rule that no devbin estate lives inside a sync provider.** devbin-vc seconded it and pushed for the REASON to be recorded beside the rule, since the next person to do it will otherwise read a rule with no corpse attached.
  2. **Does `gtools#0003` also need an Intent issue?** The defect is in Intent's shipped template (`lib/templates/hooks/whiteboard-clock-guard.sh`), so every consumer estate inherits it and a Gtools-local issue cannot reach them. Gtools' rule is that nothing goes upstream, so their report stops at hv.
  3. **The hardcoded Dropbox fleet root**, and whether to run `bin/devbin fleet doc`. The registry's own rule is that a stale stamp goes to hv, never to a silent rebuild.
- **THE CLOCK-GUARD DEFECT IS FILED AS `gtools#0003` AND THEIR WRITE-UP IS BETTER THAN MINE.** Full mechanism, reproduction and fix live there; nothing is duplicated here. What I add and they do not have: **GNU verified correct against `gdate` 9.11 with a positive control**, so the defect is BSD-only; and **the bound on their "bigger boards make it likelier"** -- 120 stamps still complete inside one second, drift 0, so it is a step function on loop DURATION, not a ramp on stamp COUNT. Sent to them.
- **THE GUARD OUTAGE WAS 13 MINUTES AND NONE OF MY COMMITS WERE IN IT. My caution was over-broad; corrected by devbin-vc and verified here.** The window was 17:28:15Z to 17:31:36Z, and the only commit inside it is **theirs** (`d4dddff`), hand-checked afterwards and would have passed. **All eleven of mine sit outside** -- ten before 17:26:36Z, the fold at 17:53:52Z. **`guards: 4 ran, 0 skipped` on my commits meant what it says.**
- **AND `4 ran` NEVER WAS THE CLAIM I DISCLAIMED.** It is evidence the guards EXECUTED, never that they would CATCH -- the gap hv's board flagged, and it was **closed 2026-08-28 by six red arms, rc 1 and HEAD unmoved on each, against a green control**. So the green is verified; it simply was not verified by me. **The residue that stays genuinely unverified for any single commit is narrow and known: a fabricated stamp carrying `Z`, landing in the past, still monotonic, passes all three clock checks.**
## For tomorrow, before running `/in-finish` again

- **`/in-finish` STEP 3 INSTRUCTS THE THING hv FORBIDS, EVERY SESSION.** devbin-vc's finding; **corroborated first-hand here from both sides in one turn.** The installed skill says *Update `intent/wip.md` with: **What was accomplished this session***. `intent/wip.md:7` says ***DOING and TODO ONLY. NO DONE WORK, EVER.*** hv was blunt that the violation had recurred; it recurs because **the procedure meant to prevent drift is what produces it.** Intent-installed, so upstream, same shape as `0036`. Routed to hv by vc, not filed. **Until hv rules: follow hv, not step 3.**
- **AND I DID NOT VIOLATE IT TODAY FOR THE WRONG REASON.** I ran `/in-finish` and left `intent/wip.md` alone **because I scoped steps 3-4 as globalfold and vc's**, not because I knew the rule. **Had I been the coordinating node I would have written done-work in, exactly as instructed, and felt compliant doing it.** Compliance by scope is not compliance by knowledge and it evaporates the moment the scope changes -- **a near miss that reads as a clean pass leaves no trace that anything was near.**
- **devbin-vc is holding my three entries LIVE in their inbox rather than clearing them**, because hv has not ruled. **A fold that archives a peer's unresolved asks is how they get forgotten** -- their rule, and it is right: `clear` means handled, and routed-but-unanswered is not handled.

## TODO -- PARKED BY hv, NOT DROPPED

**hv, 2026-08-28: earlier plans *are not gone, they're just superseded*. Archiving this stack would make parked indistinguishable from dropped.** Full text in the pre-fold archives.

- `unclaimed_digest()` hashes raw absolute paths while the renderer relativises only what it displays. **CARRIED FORWARD UNVERIFIED.**
- **F2 to F7 of `organize --default` untested against a real run.** Blocker gone; starting is hv's call.
- **PATH 2: the vector is closed, the defect is not.** The hook has no notion of `armed`, so rc 0 from a disarmed library is indistinguishable from a clean pass. Upstream's.
- **`claims:` is empty by construction for maintenance work**, so the one field answering "is anyone else on this" is silent exactly where collisions happen.
- **ARCA x2 have not landed** and hold the only copy of their STP-to-Intent migration history. **CARRIED FORWARD UNVERIFIED.**
- **0034 stays open** -- R8's `lib/runlog` primitive unbuilt.

## Owed elsewhere

- **`intent/llm/LESSONS.md` is owed the day's general forms.** vc holds that promotion pattern and devbin is paused. **Candidates, all mine or co-found:** fold-compresses-without-testing; provenance-does-not-travel; wrong-stated-reason; **mitigation-consumes-the-signal** (which subsumes fail-closed-retry); unverified-qualifier-beats-none; line-numbers-expire.
- **The joint protocol-gap escalation** (information barriers vs propagating structures), co-signed with vc, is sent.

## Watch-outs

**Compressed. Full narratives in the pre-fold archives; nothing below was merely carried.**

- **A LINE NUMBER IS A CLAIM WITH AN EXPIRY MEASURED IN MINUTES.** I cited `cmd/fleet:176` to a peer and to hv. vc corrected it to `:188`; **thirty minutes later it was `:194`, and `:48` had become `:54`.** Two moves in one afternoon. **Nothing about a stale line number looks stale, and unlike a count nobody thinks to re-measure one.** Cite the symbol or quote the text. **This fold applies that rule to itself: every code reference above is a symbol or quoted text, and the only line numbers on this board are the dead ones, quoted as the evidence.**
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE.** `devbin-users.md` warns that a census using `-maxdepth 3` *silently missed the two Arca projects, which sit one level deeper*. I read that file in full and thirteen minutes later ran `-maxdepth 4`, returning 11 instead of 13 -- **the same two projects.** The warning named a number, so I defended against the number rather than the SHAPE. **A trap described by its instance gets defended against by its instance.**
- **A MITIGATED ANOMALY STOPS PRODUCING EVIDENCE, SO THE FILE THAT HANDLES IT BECOMES THE LAST PLACE ANYONE LOOKS.** From `_tools-cc`. We saw the Dropbox eviction, wrote it down correctly in `cmd/fleet`'s `scan`, and built a two-pass control. **The control is what made it stop being reportable.** Their tree had no control, so the same cause arrived as 117 files at zero bytes. **Same phenomenon, two surfaces, and the mitigated one stayed misfiled longer.** Keeper: **ask of every workaround what SIGNAL it consumes. A retry converts a defect into a latency cost, and latency costs are reported by nobody.** Its special case: **a fail-closed race clears itself on retry, and that is exactly what stops it being reported.**
- **A CORRECT FIX WITH A WRONG STATED REASON CLOSES THE INSTANCE AND LEAVES THE CLASS OPEN.** The clock guard's author diagnosed the BSD clock-fill correctly, fixed the date-only case, and wrote that the fix *pins the field* -- which it does not. **An unexplained fix would have been SAFER: it claims nothing, so the next reader still checks.** `gtools#0003` states the sharper version: it falsifies the guard's own *FALSE POSITIVES ARE ZERO BY CONSTRUCTION*, because that argument reasons about MINUTES while the code compares SECONDS BSD invents.
- **AN UNVERIFIED QUALIFIER IS WORSE THAN NO QUALIFIER: OMISSION READS AS LOCAL, A WRONG QUALIFIER READS AS CHECKED.** A bare `0003` was correct at home; a relay added *Intent*; I resolved that against Intent's tree and reported *filed nowhere*. **Three steps, each locally reasonable, and the unqualified number was the only honest link in the chain.**
- **`intent issues` IS PER-PROJECT, AND A NUMBER RESOLVES AGAINST WHERE YOU ARE STANDING.** It never errors -- it answers about somewhere else. **I read a scope miss as a tool bug** and had to withdraw it before hv acted.
- **A CROSS-PLATFORM SHIM ASSERTS ITS TWO ARMS ARE EQUIVALENT AND NOTHING TESTS THAT.** The defect lives only in the DIFFERENCE, which nothing in the file compares, and the broken arm is the one CI never runs.
- **A STATUS LINE IS INFORMATIVE ONLY IF ITS NEGATION IS ALSO EMITTED.** devbin-vc's point, and it is the red-control principle applied to a LOG LINE rather than to a test. `guards: 4 ran, 0 skipped` carries information only because **`NO guard ran -- not one is missing, ALL are` exists and was observed on this machine this afternoon.** A gate that fell silent instead would make the two states indistinguishable, and my caution would have been correct with **no way left to resolve it**. **Today supplied the natural experiment: the instrument was seen saying the other thing, three minutes before it said this one.** Ask of any reassuring line: what would it print if the thing were false, and has anyone ever seen that?
- **A NEGATIVE CONTROL HAS A SHAPE AS WELL AS A POLARITY.** A green that is trivially true proves the instrument RAN, not that it can SEE. **Paid twice today**: a harness whose fixed stamp had aged into the past could not refuse under either flavour, and a search with an invalid flag returned zero for every pattern while the match sat visible in the list.
- **A PROVENANCE MARK DOES NOT TRAVEL WITH A SPOKEN CLAIM.** A second-hand fact is safe while filed and dangerous the moment it is USED, and that transition has no checkpoint.
- **A FOLD COMPRESSES A CLAIM WITHOUT RE-TESTING IT, AND THE SURVIVOR INHERITS THE FOLD'S AUTHORITY.** A fold reads like a review and is not one.
- **A CLAIM THAT OUTLIVED ITS BASIS.** No board, commit or message renders a claim's expiry; it reaches its next reader in the voice of a fresh measurement. **FALSE WHEN WRITTEN is not the same as TRUE-THEN-EXPIRED**, and the second hides inside the first.
- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD.**
- **A RELAY THAT WITHDRAWS AUTHORITY IS SAFE TO ACT ON AT ONCE; A RELAY THAT GRANTS IT IS NOT.** A wrong grant authorises something irreversible; a wrong withdrawal costs a pause.
- **EVERY COORDINATION MECHANISM IS A PROPAGATION MECHANISM.** An information barrier is breached BY COMPLIANCE, with no error, warning or log line.
- **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION** (hv). **The archive step runs BEFORE the cut.**
- **A SUSPENDED SESSION IS INDISTINGUISHABLE FROM A LIVE ONE.** This node sat `status: active` on a day-old heartbeat for ~24h while 27 commits landed. Stamps were correct; the session simply was not running. **The 7-day reclaim rule cannot catch that**, and invariant 6 correctly forbids releasing on a compact. **If this heartbeat is hours old, assume suspended, not dead, and do not reclaim.**

## Decisions

- **D1 to D24 are in `intent/st/COMPLETED/ST0001/design.md`** -- 74393 b, re-measured 2026-08-29 17:52Z.
- **THE STATUS RULE SPLITS BY OCCASION, AND I HAD IT STATED TOO BROADLY.** Refined at EOD 2026-08-29.
  - **Across a COMPACT: stays `active`.** Invariant 6 is explicit that a compact does not end a session, and releasing before one once dropped this node off every peer's roster for 3.5 hours **while it went on working** -- paused-but-working, a lie in the direction that hides live activity.
  - **At EOD when genuinely idle: `paused`, per `in-finish` step 1.** That is the honest state and it is **the fix for the failure I hit yesterday**, when this node sat `active` on a day-old heartbeat for ~24h and read as live to every peer while it was suspended -- active-but-absent, the same lie in the other direction.
  - **So the two documents were never in conflict; my summary of them was.** `in-finish` describes EOD and invariant 6 describes a compact. **A rule stated without its occasion collapses two cases into whichever one the writer met first.**
- **The Conflab v3 hoist superseded this board, and superseded is not finished** (hv).
- hv's standing directives live on `hv/wip.md`; vc holds that pen.
- **0018 stays CLOSED with an addendum.** A closed issue's verdict is scoped to the world it was measured in.
