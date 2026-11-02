---
node: cc
name: Control Claude
role: control
session_id: a2fb34d4-4b51-4815-a01a-3109433be3da
heartbeat_at: 2026-09-09 20:10Z
status: paused
focus: "EOD, released. Booted after eleven days paused, re-measured every claim this board carried and cut the three it led with -- all closed, none by me. Settled vc's LESSONS ask at four of six promoted, one substantially covered, one genuinely owed; two items now sit with vc for judgement. Claimed nothing: ST0003 and WP-03 are vc's. One new general form found by hitting it myself and it is owed to LESSONS"
claims: []
---

# Control Claude (cc)

**Board cut 2026-09-09 20:10Z. Pre-fold state archived VERBATIM at [`.history/20260909/wip-prefold-2010Z.md`](.history/20260909/wip-prefold-2010Z.md), 14321 b, cmp-verified against BOTH the working file and HEAD, in its own commit `b772a2e` BEFORE this cut.** The pickup narrative and its re-measure table are in that archive and are deliberately not carried: **every number in it will be stale tomorrow and must be re-read, and a carried table reaches its next reader in the voice of a fresh measurement.**

## DOING

- **NOTHING IN FLIGHT. Nothing claimed. Released to `paused` at hv's word: the session is ending, so this is a release and not a compact-time touch.**
- **ST0003 AND WP-03 ARE vc'S.** Unchanged, and not to be taken uninvited.

## Waiting on vc, not on me

**Both are judgement calls I put to them and neither is mine to decide.** They are live as of this cut -- vc had LESSONS.md, their board and two new issues (`0062`, `0063`) uncommitted while I folded, and I touched none of it.

- **`provenance-does-not-travel` -- GENUINELY STILL OWED to `intent/llm/LESSONS.md`.** Re-checked at this fold against vc's UNCOMMITTED working copy, not just HEAD: the file grew 365 -> 367 lines today and the one new entry is about a second source of truth, so my form is still absent. **The general form, so it survives without me:** a fact filed WITH its qualifier and then USED in speech without it, and the transition has no checkpoint. Its two nearest neighbours are different mechanisms and must not be mistaken for it -- one is a machine reader truncating a field, the other is what a stamp MEANS rather than the mark being dropped in the retelling.
- **`fold-compresses-without-testing` -- one clause, vc's call whether it earns an entry.** Its neighbour carries the mechanism and the archive-first remedy; what is missing is that the survivor inherits the fold's AUTHORITY, because a fold reads like a review and is not one. **A near-duplicate would be a Highlander breach in the catalogue**, which is why I flagged it rather than promoting it.

## TODO -- PARKED BY hv, NOT DROPPED

**hv, 2026-08-28: earlier plans *are not gone, they're just superseded*. Archiving this stack would make parked indistinguishable from dropped.** Full text in the pre-fold archives.

- `unclaimed_digest()` hashes raw absolute paths while the renderer relativises only what it displays. **CARRIED FORWARD UNVERIFIED.**
- **F2 to F7 of `organize --default` untested against a real run.** Blocker gone; starting is hv's call.
- **PATH 2: the vector is closed, the defect is not.** The hook has no notion of `armed`, so rc 0 from a disarmed library is indistinguishable from a clean pass. Upstream's.
- **`claims:` is empty by construction for maintenance work**, so the one field answering "is anyone else on this" is silent exactly where collisions happen.
- **ARCA x2 have not landed** and hold the only copy of their STP-to-Intent migration history. **CARRIED FORWARD UNVERIFIED.**
- **0034 stays open** -- R8's `lib/runlog` primitive unbuilt.
## Owed elsewhere

- **`intent/llm/LESSONS.md` -- four of my six are promoted and MUST NOT BE RE-PROMOTED.** `wrong-stated-reason`, `mitigation-consumes-the-signal` and `unverified-qualifier-beats-none` landed in my own words; `line-numbers-expire` landed as **A LINE NUMBER IN A DURABLE RECORD ROTS FASTER THAN THE RECORD**, carrying my evidence. **Two of the four read as ABSENT to an exact-phrase search on my own labels**, which is the trap to avoid next time this is asked.
- **A NEW GENERAL FORM, FOUND BY COMMITTING IT, AND IT IS OWED TO LESSONS.** **A FALLBACK KEYED ON EXIT STATUS CANNOT TELL "I LOOKED AND FOUND NOTHING" FROM "I COULD NOT LOOK".** Verifying that a hardcoded root was gone, I ran `grep -n Dropbox <fileA> <fileB> || echo "(no literal in either)"`. `<fileA>` does not exist, `grep` exited **2**, and my own `||` printed the reassuring sentence **directly beneath the real matches it had just printed**. Both halves were individually correct and the composition asserted the opposite of the output above it. **The absence of a SUBJECT is a failure, not a clean result** -- the same shape as a guard that skips when the thing it guards is missing, except this one speaks. **Check existence separately, or test for the specific exit status; never let one branch stand for both.** I caught it because the matches were still on screen, which is luck rather than method.
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
