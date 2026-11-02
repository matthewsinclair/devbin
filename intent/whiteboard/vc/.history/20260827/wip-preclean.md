---
node: vc
name: Validation Claude
role: validation
session_id: 15122d15-b44f-488e-afff-32e432b5c8fc
heartbeat_at: 2026-08-27 11:38Z
status: paused
focus: "PAUSED AND HOLDING while Intent runs the v3 rollout. intent-vc reversed the 26 Aug move at 54526ca and left the citations behind; repaired at d45775e on hv approval -- 9 pointers repointed, 4 statements rewritten not swapped, intent/history/ removed, 0 dangling with a negative control. organize reads 54 unclaimed and that is honest, not a regression: it closes on the ingest, which is hv to rule. Devbin has NO gate that would have caught any of this -- documentation.bats checks markdown links and every citation here is backticked code"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT. PAUSED AND HOLDING** while Intent runs the v3 rollout. No claim, no thread; the next one is hv's to set -- read `hv/wip.md` first.
- **DEVBIN'S PORT IS CLOSED OUT** at `a2cd632` on pair `f7240814`: `.gitignore` gained `intent/.backup/`, config re-stamped with the backup-schedule block. **AND IT WAS REVERSED FROM OUTSIDE THIS ESTATE ON 2026-08-27, THEN REPAIRED HERE.** intent-vc moved all 54 files back to `intent/st/COMPLETED/` at `54526ca` and left every citation behind. **Repaired at `d45775e` on hv's approval**: 9 pointer occurrences repointed, 4 statements rewritten rather than swapped, `intent/history/` removed. `organize` reads **54 unclaimed** again (digest `2f8c52144602`, `0 to remove`) and that is the honest state -- **not to be closed by moving anything.** It closes when the 24 non-modelled files reach canon via `st attach`, which is hv's ruling and still stopped.
- **`bin/devbin check all` IS GREEN AGAIN AND MY BOARD SAID RED UNTIL THIS FOLD.** rc 0 on 2026-08-27; **critic arms 2 of 6 shell rules across 28 files** and names the other 4 as declared-unanswerable. **Nothing in this estate was fixed and 3.0.1 has not shipped** -- the brew keg was UNLINKED, so PATH now resolves a build that serves rules. **I predicted the mechanism as well as the outcome and only the outcome was right**, which is the cheaper half to get right. The red was correct while it stood; a gate that armed no rules had abstained, not passed.

## STATE

| | |
| --- | --- |
| **Devbin** | v3.0.0, clean, PAUSED, **0 unclaimed**. ST0001 218/218. `CLAUDE.md` user block 914 b `4fe8e34c...` |
| the v2 record | **BACK AT `intent/st/COMPLETED/`**, citations repaired `d45775e`. **Location changed, RISK did not**: 22 of 54 are still the only copy and still absent from canon -- neither `ST0001.json` nor `ST0002.json` carries an `attachments` key. The ingest is the fix and it is hv's |
| Arca x3 | **all v3.0.0 and clean.** `arca_config` on `03470c5a` with `AT-05.3` recovered by id; `arca_cli` re-converted (superseded `33e3c2d` unreverted -- hv's call); `arca_notionex` clean |
| the fleet | 22 estates audited, 13 clean. **[Intent issue 0098](../../../../Intent/intent/.canon/issues/0098.json)**, high. **Conflab NEVER migrated**; Lamplight 3740 unclaimed / 10 losses; Laksa 831 / 2 |
| the instrument | [`at-accounting.sh`](at-accounting.sh), **three arms, self-test 22/22**. Source ALWAYS from a git ref. **Joiner-agnostic** -- specified against `+`, all 26 of Devbin's multi-rows use a COMMA. **No unclaimed arm** |

## TODO

- **CONFLAB IS THE ONE NOBODY OWNS.** Not migrated, not held, not worked. hv's to assign; this node is not starting it.
- **THE INSTRUMENT NEEDS AN UNCLAIMED ARM.** It answers *did the rows survive* and never *were files left stranded* -- which is how it called Laksa `rc=1 short=2` while saying nothing about 1047 stranded files. Mine to build, on hv's word.
- **THE CROSS-SESSION STAMP GAP WANTS ITS OWN ISSUE, NOT A SECTION IN 0098.** Folding it in would be the thing 0098 complains about. Intent's machinery; routing is hv's.
- **0034 IS STILL OPEN AND IT IS cc's.** Third instance landed `3ee5b47` (R9 added, R4 intact) after cc confirmed the lift with hv directly. **Open because R8's `lib/runlog` primitive is unbuilt.**
- **STILL EXPLICITLY DO NOT START: `--ivault`.** devbin must NEVER parse an `intent://` reference -- literal prefix test only. `intent/st/ST0060/` is ABSENT BY DESIGN; `intent3 st hydrate ST0060` restores it.
- **Two Lamplight AT collisions NOT sent as renumbers** (`ST0298` `AT-02.3`, `ST0198` `AT-16.1`): a superseded row and its successor sharing an id, so a renumber would MINT AN ID FOR A ROW MEANT TO BE REPLACED. With Lamplight's nodes.
- **Read `intent/llm/LESSONS.md` and `usage-rules.md` at the start of real work**, not this board.

## Watch-outs

**THESE ARE LEAD CLAIMS ONLY. The evidence, the measurements and the reasoning behind every one of them are in [`.history/20260827/wip-morning.md`](.history/20260827/wip-morning.md), archived verbatim at 24162 bytes before this fold** -- and in the day records under `.history/20260826/`. A lead claim is enough to recognise the situation; it is not enough to act on one, so open the archive before citing any of these as evidence.

**PROMOTED TO [`intent/llm/LESSONS.md`]( ../../llm/LESSONS.md ) AT THE 2026-08-27 08:45Z GLOBALFOLD AND REMOVED FROM HERE:** the cross-session stamp gap, a loss that reconstructs into the correct shape, a fix is a change to everything that reads it, a migration that refuses vs one that corrupted, display-format vs parsing, verify a peer per-claim, and the line-addressed edit. **Removed rather than cross-referenced: two copies of a lesson is the defect this project names first, and a board is archived when its work closes while the lesson outlasts it.** What remains below is node-specific -- about what THIS node does -- and stays.

**THE GENERAL RULE IS `IN-AG-RED-CONTROL-001` AND IT IS NOT RESTATED HERE.** Read it with `intent claude rules show IN-AG-RED-CONTROL-001`. It carries the step (*name what would make this control go red, then make it go red*), the two questions behind it (**WOULD** it have failed -- stash the fix; **COULD** it have failed -- break the control first), the evidence, and the mirror image. **This board keeps only the instances it measured, because a board is archived when its work closes and the rule is not.** Six on 2026-08-26: a `| tail` removing the exit status from a run; an unbound variable removing the assertion from a script; a `pgrep -f` matching its own command line; an `INTENT_HOME` lever that never reached v3's resolver; `intent st show | grep -c` read as a finding when the command prints no AC text at all; and the four in `at-accounting.sh` below. **The catalogue that stood here stopped none of the first four, which is why the remedy became a step and then a rule rather than a fifth entry.**

Standing, and specific to what this node does. The general defect classes moved to `intent/llm/LESSONS.md` on 2026-08-24; the day's full pre-lean board is at `.history/20260824/wip-preleanboard.md`.

- **I PUT A LOCAL TIME WITH A `Z` ON IT INTO A MESSAGE TODAY -- THE +1h CLASS, CAUGHT BY intent/vc AND NOT BY ME.**
- **A restart brief is a snapshot, not a record. Verify its open-set against disk before planning from it.**
- **A write with no named reader is a queue, not a channel.**
- **A SENDER'S WRITE INTO A PEER'S FILE DOES NOT MAKE THAT FILE PART OF THE SENDER'S CHANGE SET.**
- **A FLEET SWEEP ANNOUNCES BEFORE IT RUNS, AND THE ANNOUNCEMENT NAMES THE HELD ESTATES.**
- **THIS NODE REPORTS GATE STATE, SO IT MUST CHECK THE GATE IS WIRED, NOT JUST THAT IT PASSED.**
- **THIS NODE'S OUTPUT IS A MEASUREMENT, SO THE PREDICATE IS PART OF THE RESULT.**


- **A COLUMN OF ZEROES IS THE FINDING WHEN THE COLUMN IS "CLEAN".**

- **THE TWO-QUESTIONS FORMULATION NOW LIVES IN `IN-AG-RED-CONTROL-001`, NOT HERE.**

## Decisions

- hv's standing directives and ratified rulings live on `hv/wip.md`. Nothing is duplicated here -- a second copy of a ruling drifts, and this node has now watch ...
