---
node: cc
name: Control Claude
role: control
session_id: a2fb34d4-4b51-4815-a01a-3109433be3da
heartbeat_at: 2026-09-09 08:20Z
status: active
focus: "Booted after 11 days paused. EVERY CARRIED CLAIM RE-MEASURED AND THE THREE THIS BOARD LED WITH WERE ALL DEAD -- the sync-provider rule was DROPPED on a premise that was vc's and wrong, gtools#0003 is filed as intent#0220 instance 2, and the hardcoded fleet root is fixed in code, verified here by symbol rather than taken from the relay. Nothing claimed: ST0003 and WP-03 are vc's. Awaiting vc's instructions"
claims: []
---

# Control Claude (cc)

**Board picked up 2026-09-09 08:20Z after ELEVEN DAYS PAUSED. Pre-pickup state archived VERBATIM at [`.history/20260909/wip-prepickup.md`](.history/20260909/wip-prepickup.md), cmp-verified at 14794 b BEFORE this file was touched.** Only the header, the re-measure table and the two lead sections were cut; TODO, watch-outs and decisions are untouched.

## Re-measured at pickup, 2026-09-09 08:20Z

**Everything below is read live in this session. Nothing is carried from the 2026-08-29 table, which is in the archive.**

| claim                                     | verdict                                                                                                                    |
|-------------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| my three questions to hv                  | **ALL THREE CLOSED.** None was closed by me and this board asserted all three as live for eleven days                       |
| the hardcoded fleet root                  | **FIXED.** `bin/.devbin/cmd/fleet` carries zero non-comment Dropbox literals; `DEVBIN_FLEET_ROOTS` is the override          |
| `lib/cmd/fleet`                           | **DOES NOT EXIST.** My first check grepped it, exited 2, and my own `\|\|` printed a "no literal" claim over real matches    |
| devbin open issues                        | **SEVEN: 0034 0035 0036 0039 0056 0059 0060.** My board carried FIVE. `0035` is parked by hv                               |
| ST0003                                    | **32/37 satisfied, 7 descoped, 1 withdrawn -- BLOCKED.** WP-03 `infra init` is the whole remainder                          |
| HEAD / remotes                            | HEAD `65493e8`; `upstream` and `local` both `6e70788`; **three unpushed**; tree clean                                       |
| full suite                                | **GREEN, run here at 08:08Z** -- 1058 arms, `all test options passed`                                                       |
| `gtools#0003`, `intent#0089`              | **NOT RE-MEASURED.** Both live in other trees; my board asserted them as HOLDS and I have not resolved either from here     |

## DOING

- **NOTHING IN FLIGHT. Nothing claimed. Awaiting vc's instructions, on hv's word relayed through vc.**
- **ST0003 IS vc'S AND SO IS WP-03.** They claim it, the design questions are ruled, and I am not taking it uninvited.
- **THE THREE QUESTIONS THIS BOARD LED WITH ARE ALL CLOSED, AND NOT ONE WAS CLOSED BY ME.**
  1. **The sync-provider standing rule -- DROPPED**, and the premise was vc's and wrong: those `~/Dropbox/Repositories` paths are `--bare` git repos and no devbin estate lives under a sync provider. Confirmed incidentally here -- this repo's `local` remote IS one of those bare paths.
  2. **`gtools#0003` -- YES, and it is filed** as `intent#0220` instance 2.
  3. **The hardcoded fleet root -- FIXED IN CODE**, and I verified it here rather than carrying the relay.
- **THE LESSONS DEBT IS SETTLED AT FOUR OF SIX, AND MY LABELS WERE NOT WHAT TO SEARCH ON.** vc asked which of my six owed general forms are already in `intent/llm/LESSONS.md`. Answer below; the method is the part worth keeping.
  - **Promoted, verbatim mine:** wrong-stated-reason, mitigation-consumes-the-signal, unverified-qualifier-beats-none.
  - **Promoted under DIFFERENT WORDING, which an exact-phrase search called absent:** line-numbers-expire, landed as **A LINE NUMBER IN A DURABLE RECORD ROTS FASTER THAN THE RECORD**, carrying my `:176`->`:188`->`:194` and `:48`->`:54` evidence.
  - **Substantially covered, residue is one clause:** fold-compresses-without-testing. **A LEAD CLAIM IS ENOUGH TO RECOGNISE A SITUATION AND NOT ENOUGH TO ACT ON ONE** carries the mechanism and the archive-first remedy. What is NOT there is that the survivor inherits the fold's AUTHORITY -- a fold reads like a review and is not one. One clause, and a near-duplicate entry would be a Highlander breach in the catalogue, so it is vc's call whether it earns its own.
  - **STILL OWED, genuinely:** provenance-does-not-travel -- a fact filed WITH its qualifier, then USED in speech without it, with no checkpoint at the transition. Its two neighbours are different mechanisms: **A MARKER PROVEN AT THE WRITER IS NOT PROVEN AT THE READER** is a machine reader truncating a field, and **a provenance stamp and a live claim are indistinguishable in prose** is about what a stamp MEANS, not about the mark being dropped in the retelling.
- **AND THE SEARCH IS THE FINDING.** Exact-phrase grep on my own six labels returned 3 of 6. Concept search returned 4, and reclassified a fifth. **A label is a mnemonic for the person who coined it and a false negative for everyone else** -- had I answered vc off the first grep, two promoted forms would have been re-promoted as duplicates into the file whose whole purpose is that there is one of each. The grep ran under a positive and a negative control, which is the only reason I trusted its zeroes at all.

## TODO -- PARKED BY hv, NOT DROPPED

**hv, 2026-08-28: earlier plans *are not gone, they're just superseded*. Archiving this stack would make parked indistinguishable from dropped.** Full text in the pre-fold archives.

- `unclaimed_digest()` hashes raw absolute paths while the renderer relativises only what it displays. **CARRIED FORWARD UNVERIFIED.**
- **F2 to F7 of `organize --default` untested against a real run.** Blocker gone; starting is hv's call.
- **PATH 2: the vector is closed, the defect is not.** The hook has no notion of `armed`, so rc 0 from a disarmed library is indistinguishable from a clean pass. Upstream's.
- **`claims:` is empty by construction for maintenance work**, so the one field answering "is anyone else on this" is silent exactly where collisions happen.
- **ARCA x2 have not landed** and hold the only copy of their STP-to-Intent migration history. **CARRIED FORWARD UNVERIFIED.**
- **0034 stays open** -- R8's `lib/runlog` primitive unbuilt.

## Owed elsewhere

- **`intent/llm/LESSONS.md` -- SETTLED AT PICKUP, 2026-09-09. Four of the six are in.** Details in DOING. What is still owed is **provenance-does-not-travel** (genuinely absent) and, at vc's discretion, the one clause of **fold-compresses-without-testing** that its neighbour does not carry. The other four are promoted and **must not be re-promoted** -- two of them read as absent to an exact-phrase search on my own labels.
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
