---
node: cc
name: Control Claude
role: control
session_id: 1e86191f-1ce1-405b-8a8c-827819fc7836
heartbeat_at: 2026-08-28 12:53Z
status: active
focus: "Booted after compact, gate released, pickup done. Idle -- nothing in flight, nothing claimed, both inboxes empty. Holding for instructions per hv. Devbin still PAUSED; Conflab Phase 4 closed BY MEASUREMENT. Status stays ACTIVE -- a compact is not a release"
claims: []
---

# Control Claude (cc)

**Board cut 2026-08-28 12:36Z. The pre-fold state is archived VERBATIM at [`.history/20260828/wip-prefold-1236Z.md`](.history/20260828/wip-prefold-1236Z.md), cmp-verified at 51383 b before this file was touched.** Every compressed entry below has its full text there. Phase 4's runner, before-state, pre-registration and result are in the same directory.

## DOING

- **IDLE, HOLDING FOR INSTRUCTIONS. Nothing in flight, nothing claimed, both inboxes empty.**
- **Authority chain (hv, 2026-08-28): hv -> intent-vc -> devbin-vc -> me.** devbin-vc is my authority; I do not take assignments from intent-vc directly and do not message them across the chain.
- **Conflab is on Intent v3 and my Phase 4 unit is CLOSED. 8 of 8 pre-registered predictions confirmed, zero divergence.** Carrier replaced byte-exact with the shim template read in the same command, executable, `--where` reporting `state: OK` against the right root; all 20 shadow files unchanged; daemon still pid 7438; both tracked lockfiles unchanged; Intent binary unchanged, so the no-build bar held. **Nothing in Conflab was ever written by this node.**
- **Intent issue 0105 (HIGH) filed at hv's direct instruction and corrected once.** `doctor`'s gate check tests the CARRIER for a guard-runner string the shim never names, so every v3 estate reports `GateNotRunning` while its guards run. Second defect under it: doctor compares against the GATE template while canon installs the SHIM, so a shim estate reports `BehindTheTemplate` permanently and a partial fix leaves the fleet red. **Intent's code, routed through devbin-vc, not mine to fix.** **UPGRADED TO MEASUREMENT-BACKED after my fold:** conflab-ic drove a two-arm control -- arm 1, a stamp without `Z`, **REFUSED with check B named, rc 1, HEAD unmoved**; arm 2, a `date -u` stamp, **COMMITTED at Conflab `2b770740`** (verified here: exists, and `merge-base --is-ancestor` of HEAD). **That is INVOCATION, not resolution.** My path trace and devbin-vc's source reading both stopped at *the chain resolves*; a refusal that names its own check and leaves HEAD unmoved proves the carrier EXECUTES and a guard FIRES. **And one arm could not have shown it: a refusal leaves no artefact, so arm 1 alone is unfalsifiable and a gate that refuses everything looks identical to one that discriminates.** **My 2026-08-28 08:44Z ungated-commits finding is therefore closed BY MEASUREMENT, superseding the closed-by-path-tracing record I asked for while tracing was all we had.**

- **TWO FILES ARE DIRTY IN THIS TREE AFTER THE FOLD AND NEITHER IS MINE TO COMMIT. Recorded so the next reader does not have to guess, and does not read them as devbin work.** **Devbin is PAUSED and nobody did devbin work today**, so both are side effects of v3 tooling running here while I worked in other estates.
  - `M intent/st/steel_threads.md` -- **REGENERATED, not edited.** The index's column changed from `Slug` to `Title` and the values changed with it (`rationalise-5-bin-prj-scripts-into-a-reusable` -> `Rationalise 5 ./bin/{{prj}} scripts into a reusable framework`). A generated file whose FORMAT moved under a paused project. **I did not write it and will not commit it:** committing a format change to a generated index is a real change to a paused project, and it is hv's to sequence.
  - `?? intent/.canon/project.json` -- 37 bytes, `{"schema": "intent/project@3.0"}`, mtime 12:25Z, appeared during this session. `intent/.canon/` already has history here, so this is a new file in an existing store rather than a new store.
  **The general point, and the reason this is a board entry rather than a shrug: a tool that regenerates on read makes a PAUSED project drift without anyone touching it**, and the drift arrives looking exactly like someone's uncommitted work. Yesterday this board had to explain 18 dirty files as vc's; today it is two, and they are nobody's.

- **RULE 2 IS LIFTED ESTATE-WIDE** (intent-vc, relayed by devbin-vc): no-builds-in-the-Intent-tree is over; **rules 3 and 4 stand** -- explicit pathspec commits, and every stamp read from `date -u` in the writing command. Conditions: ordinary build ceremony, announce first, never into a shared artefact path from a dirty `native/rust`. **I am NOT exercising it.** A lift is a GRANT, and my own asymmetry rule says a grant needs first-hand confirmation before it is acted on -- **but I have nothing to build, so the question stays moot rather than escalated.** **Driving `gate_state`'s arms is intent-dc's to schedule, not mine.** I proposed that test in 0105 and was right not to run it; it stays theirs to call.
- **hv's board is corrected and now records 0030 and 0029 as closed on the 25th** after standing stale four days on the one board every node is told to trust. Two facts from it I did not have: **the open issues are 0034 AND 0035**, and **the fleet is NOT uniform** (2 seam commits behind, three source commits across five estates sampled) -- which is why my board carried the uniformity reading as *vc's, 2026-08-27, not re-measured here* rather than as mine.

## TODO -- PARKED BY hv, NOT DROPPED

**hv's ruling, 2026-08-28, in their words: earlier plans *are not gone, they're just superseded*. This stack must NOT be archived at a fold -- archiving is what this node does with SETTLED work and none of it settled.** A parked item and a dropped item are indistinguishable on a board, which is why this paragraph exists rather than a silent reliance on the entries still being here. Full text of each is in the pre-fold archive.

- `unclaimed_digest()` hashes raw absolute paths while the renderer relativises only what it displays. **Historical until re-run** -- the three reproductions were taken on a build no longer on PATH.
- **F2 to F7 of `organize --default` remain untested against a real run.** The blocker is gone; starting is hv's call.
- **PATH 2: the vector is closed, the defect is not.** The hook still has no notion of `armed`, so rc 0 from a disarmed library is indistinguishable from a clean pass. Upstream's.
- **The clock guard's 120s tolerance buys a two-minute always-open door**, and its stated justification does not exercise it. With intent/vc; hv ruled tolerance 0 and reserved the SCOPE read separately.
- **The `claims:` field is empty by construction** for maintenance work, so the one field that answers "is anyone else on this" is silent exactly where collisions happen. With intent/vc.
- **ARCA x2 have not landed** and hold the only copy of their STP-to-Intent migration history. Two independent captures held; diff both after they land.
- **The v2 binary exists and is NOT on PATH** (`Intentv2/bin/intent`, 2.19.0). hv's prune decision.
- **0034 stays open** -- R8's `lib/runlog` primitive unbuilt. Reasoning is in the issue.
- **Untested prediction:** the next regeneration of Baize or Riffle drops `, created <date>` again.

## Owed elsewhere, not to a board

- **`intent/llm/LESSONS.md` is owed the day's general forms** -- devbin/vc carried the last batch at `7a9ee05` and the promotion pattern is theirs. **Not done unilaterally: devbin is PAUSED and this is hv's to sequence.**
- ~~`usage-rules.md:98` heredoc mis-filing~~ **CLOSED BY hv, AND THE ENTRY ABOVE WAS FALSE WHEN I WROTE IT.** `9218523` at **11:47Z** added a `NEVER` under `## Shell` naming both instances (`e5bf283`, `fe6ef87`) -- **one insertion, not a move**, which is right: the Tests rule at line 99 was never wrong, only filed for PIPESTATUS. vc flagged it 11:37Z, I recorded it 11:39Z, hv fixed it 11:47Z. **I then carried the entry through the 12:36Z fold saying it was still a candidate and that vc had left it alone -- 49 minutes after it was fixed.**
- **`AGENTS.md` DOCUMENTS A TEST COMMAND THAT FINDS ZERO TESTS, AND THE PROJECT ALREADY DECLARES THE RIGHT ONE.** vc's unfiled boot finding, re-measured here and SHARPENED: `bats tests/` returns **rc=1, `ERROR: Found no tests.`** -- honest, not a false green. But `bin/.devbin/config.yaml:40` declares `run: bats tests/unit`, which is correct, so **the generator is not reading the project's declaration; it renders a default over the top of it.** That moves the fix from devbin's config to `intent agents sync` upstream, and `AGENTS.md` is generated so it must not be hand-corrected here. Handed to vc, who holds the finding.
- **The joint protocol-gap escalation** (information barriers vs propagating structures) is drafted, co-signed by devbin-vc, and sent up. Posted nowhere else.

## Watch-outs

**The day's general forms, compressed. Full narratives in the pre-fold archive.**

- **A FOLD COMPRESSES A CLAIM WITHOUT RE-TESTING IT, AND THE SURVIVOR INHERITS THE FOLD'S AUTHORITY.** New today, and NOT the expiry class below -- that one is true-when-written. This one was **false when written**: the heredoc mis-filing had been fixed 49 minutes before I rewrote its entry at the fold. **A fold reads like a review and is not one.** Rewriting an entry more tightly makes it look freshly checked, so compression is the one edit that raises a claim's apparent freshness while verifying nothing. **Anything a fold KEEPS must be re-measured or explicitly marked as carried-forward-unverified.**
- **A CLAIM THAT OUTLIVED ITS BASIS. Four instances today across three nodes, and not one had anything on it that could go red.** A fact about a location, a link target, or a file's contents is a claim with an expiry date, and no board, commit or message renders that date -- it reaches its next reader in the same voice as a fresh measurement. Mine: `intent/history/ST0001` recorded permanent the day before it was reversed; the v2 binary reported on PATH; two README defects reported present after they were fixed.
- **AN ALTERNATION PATTERN CANNOT PRODUCE A PER-ITEM COUNT, AND I MADE THIS ERROR TWICE IN FIFTEEN MINUTES.** `grep -cE 'A|B'` counts lines matching EITHER. Found it in my own Phase 4 check, disclosed it, wrote it up -- then committed the identical error into a HIGH issue in another estate. **Fixing the instance did not prevent the habit.** One literal per column, never an alternation, predicate printed beside the number.
- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD, BECAUSE THE RECORD THEN CONTAINS A LINE SAYING IT FIRED.** devbin-vc's, in their own fold, and the fourth instance of the stream class today. Their guard printed *A DIRECTIVE LINE MOVED -- STOP* **and committed anyway**: `grep && echo || echo` exits 0 whichever branch runs, so the refusal was text with no power behind it. **And the alarm was false as well** -- it grepped the diff for `standing directive` and matched their own added sentence promising the directives were untouched, which is the claim-versus-citation class **inside the guard written to be careful**. Settled the only way it could be: extract the block from both revisions and `cmp`, with a negative control. 14 lines, 1351 bytes, identical.
- **A WRONG NUMBER UNDERNEATH A RIGHT ANSWER HAS NO TRIGGER FOR RE-INSPECTION**, because the answer goes on looking correct. Caught only because devbin-vc could not reproduce a cell and said so.
- **A RELAY THAT WITHDRAWS AUTHORITY IS SAFE TO ACT ON AT ONCE; A RELAY THAT GRANTS IT IS NOT.** The asymmetry is about what happens if the relay is wrong. A wrong grant meant an unauthorised five-language build into a fenced tree; a wrong withdrawal costs a pause.
- **THE CONTROL FIRED AND I WAS LOOKING SOMEWHERE ELSE** -- a shape the catalogue did not have, arrived at independently by two nodes the same day. Nine `command not found` lines scrolled past under the commit output I was watching. **The fix is not "look harder": check the status, do not read the stream.**
- **EVERY COORDINATION MECHANISM IS A PROPAGATION MECHANISM.** An information barrier is a negative constraint laid over a system engineered for positive delivery, so correct operation breaches it -- pickup, `git show`, and the authority chain each did. **A breach-by-compliance produces no error, no warning and no log line.**
- **VERIFY A PEER'S CLAIM AGAINST THE ARTEFACT IT NAMES**, in both directions. `intent issues show` renders COMMITTED state, so my correction read as absent while the file on disk was already right. The instrument disagreed with the artefact and the artefact was right.
- **A NEGATIVE CONTROL HAS A SHAPE AS WELL AS A POLARITY.** A green that is trivially true proves the instrument RAN, not that it can SEE. Phase 4's branches were driven red synthetically before use for exactly this reason.
- **PRE-REGISTRATION BOUNDS THE ANSWERS AND NOT THE REASONING.** P3 was confirmed on a premise that was wrong, and a confirmed prediction is precisely where nobody re-reads the reasoning.
- **NEVER `head`/`tail` WHEN THE SIZE OF THE OUTPUT IS THE QUESTION** (hv's ruling). **The fold's archive step runs BEFORE the cut** -- reversed, it fails silently, the archive reading as a full record while holding a summary.
- **`in-finish`'s release step and protocol invariant 6 disagree about a PRE-COMPACT fold.** Releasing to `paused` before a compact dropped this node off every peer's active roster for 3.5 hours. **This fold deliberately keeps `status: active`.** Upstream's to settle.

## Decisions

- **Design decisions D1 to D24 are in `intent/st/COMPLETED/ST0001/design.md`** (74393 b, measured 2026-08-28). `5435007` moved the record out on the 26th; `54526ca` moved it back on the 27th as 54 pure `R100` renames. **`intent/history/` does not exist in this tree.**
- **The Conflab v3 hoist supersedes this board, and superseded is not finished** (hv, 2026-08-28). See the TODO preamble.
- hv's standing directives live on `hv/wip.md`, not here, and **that board was CORRECTED at 2026-08-28 12:39Z by devbin-vc, who holds that pen**: 0029 and 0030 both read CLOSED on the 25th, and the open issues are **0034 AND 0035**. **The entry this replaces said hv's board was last written 2026-08-24 and still listed them open. That was true when I wrote it and false by the time anyone read it** -- caught at this boot only because pickup re-READ the board instead of trusting the line asserting its state. Fifth instance of the expiry class, and the first one to bite a line whose whole subject was another board being stale.
- **0018 stays CLOSED with an addendum.** A closed issue's verdict is scoped to the world it was measured in -- and 0105 is that same principle arriving as live code rather than as a closed issue.
