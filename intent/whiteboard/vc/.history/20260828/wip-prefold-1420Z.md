---
node: vc
name: Validation Claude
role: validation
session_id: 37214cfb-198a-4b48-980d-d4ab03e852d6
heartbeat_at: 2026-08-28 14:13Z
status: active
focus: "0037 and 0038 CLOSED BY FIX -- the exit-code contract now has a test that can go red, driven red before and after. 0036 established as upstream-only (one word in Intent's template, no local override exists) and surfaced to hv. 0034 and 0035 deliberately not started: 0035 is four questions only hv can rule on, 0034 is Lamplight-originated and on hv's separate track. Suite 720/720"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT.** hv's second go is executed. **0037 and 0038 are CLOSED BY FIX** (`39f4e70`); **0036 is established as upstream-only** and surfaced; **0034 and 0035 are deliberately not started**, for stated reasons rather than by omission.
- **0037's real fix is the test, not the prose.** The contract was stated in two live documents in almost the same words, so `fc794aa`'s `exit 4` staled both at once and neither could fail. `usage-rules.md` is now the one enumeration; `ARCHITECTURE-shell.md` points at it. `documentation.bats` holds that line to the source's `exit` statements **in both directions** -- a code shipped without a line fails, and a line naming a code the source cannot return fails too. **Written before the fix and watched go red first** (`not ok 11` against the 0/1/2/3 prose), then green on the correction, then all three new tests driven red deliberately.
- **0038 was a bats advisory, not a `usage-rules` rule, and my own issue body said otherwise.** BW01 is bats-core's: it assumes a 127 means the test's own command path is broken -- true in general, false here where `dvb` resolving nowhere IS the condition under test. `run -127` pins it at the call site. **The asymmetry with `buildfmt.bats`'s `run !` was already reasoned in the tree**: pin the number when the test claims the number.
- **0036 HAS NO LOCAL FIX AND THAT IS THE FINDING.** `bats tests/` is hardcoded at Intent's `lib/templates/llm/_AGENTS.md:91` inside `[[#lang shell]]`; `intent/.config/` holds only `config.json` and it carries no test-command key. So no consuming project can fix it, and a hand edit to the generated `AGENTS.md` is overwritten by the next sync. **The fix is `bats -r tests/`** -- measured: recursive **720**, flat **0** -- and it is correct for a flat layout too, so it belongs in the template rather than as a devbin special case. **Intent's tree untouched**; hv sequenced that work jointly.
- **WHY 0034 AND 0035 ARE NOT STARTED.** **0035 is not a fix** -- it is four instances each ending in *"the ask: state whether this is a convention"*, and only hv can rule. **0034 is real code** (every gate leg should write a `SCOPE:` line; only `lua` does) but it is **Lamplight-originated, and hv said Lamplight+devbin is a separate track they manage.** Not mine to start uninvited.

## What today established

## What today established

| finding | where it landed |
| --- | --- |
| **The four commit guards CATCH, not merely run.** 6 red arms -- clock A/B/C, header, append-only, canon-ignore -- all rc 1, HEAD unmoved, each naming its own check, against a green control that landed at `27a19a0` | `.history/20260828/devbin-guard-red-drive.md` |
| **The fleet is 10-vs-1, not three-way.** 3 stamps but only 2 seam states, verified by digesting vendored `lib/`: Conflab/Baize/Riffle/Prolix all `ffeaa050`; Lamplight `4e789099`, identical to this checkout's `lib/` at HEAD | `intent/wip.md`, `intent/restart.md` |
| **A `source_commit` stamp is not a seam state** -- counting distinct stamps counts RE-VENDOR EVENTS. Baize reads as a third state carrying bytes identical to the nine | standing constraint in `intent/restart.md` |
| **v3 files issues to canon and writes NO directory.** `0035` was never missing anything; the 34 markdown directories are the v2 leftover. Confirmed live -- 0036/0037/0038 filed today, no directories | `intent/wip.md` |
| **Three boot findings filed as 0036, 0037, 0038**, each re-verified before filing rather than filed from the note | `intent issues list` |
| **The two orphan writes are Intent 3.0.0 output**, not abandoned work: `project.json` is the v3 project record, `steel_threads.md` a Slug->Title regeneration | `2063101` |

## Conflab Phase 4 -- the record, not restated here

Everything is in `.history/20260828/`, and summarising it is what the fold is avoiding. Pointers only, because **a record nothing points to is a record nobody finds**:

| artefact | what it is |
| --- | --- |
| `conflab-phase4-report.md` | the verdict, its limits, and the addendum that upgraded the gate finding |
| `conflab-phase4-preregistration.md` | ten predictions sealed BEFORE the hop; **P6 wrong**, the rest confirmed |
| `conflab-prehop-*` | the 1365-row census and the state it was taken against |
| `conflab-afterread.sh` | the instrument, committed before the measurement |
| `barrier-vs-propagation-joint.md` | the protocol escalation, co-signed with devbin-cc |
| `wip-prefold.md`, `inbox.cc-archived.md` | this board and inbox as they stood at the fold |

**CLOSED BY MEASUREMENT, 2026-08-28 12:39Z:** conflab-ic's two-arm control returned -- **arm 1 (no `Z`) REFUSED, check B named, rc 1, HEAD unmoved; arm 2 (`date -u`) COMMITTED at `2b770740`.** That is **invocation, not resolution** -- the thing neither devbin leg could show. So `doctor`'s `gate-not-running` on a shim is a false positive **by measurement**, and my report is superseded on that point exactly as it pre-stated. **Rule 2 (no builds in the Intent tree) is LIFTED estate-wide; rules 3 and 4 stand.**

**Headline, so a reader need not open anything: Conflab IS on v3, NOTHING was lost** (`vanished=0` of 1365; seam byte-untouched so the STOP condition never fired), **my P6 was WRONG** (the carrier was replaced, not preserved), and **`doctor`'s `gate-not-running` on a shim is CERTAIN to be a false red** -- filed as `intent#0105` HIGH by devbin-cc on hv's instruction. **Nobody established whether the hop broke anything functional; no suite was ever run.**

## TODO -- hv's to sequence

**Nothing below is started, and the first item is the only one with real weight.**

- **THE FLEET RE-VENDOR NEEDS hv's EXPLICIT GO.** Now precisely sized rather than feared: **10 of 11 estates carry byte-identical seam bytes exactly 2 commits behind** (`9538f4e`, `fc794aa`); **Lamplight is already current.** Eleven live projects, so it sits squarely under the standing directive on deploy-affecting change. The census is read-only and done; the roll is not.
- **THE `st attach` RULING IS STILL OWED** and it is the only thing that closes the 54. 22 of those files exist nowhere else, `ST0001.json` and `ST0002.json` carry no `attachments` key, and `organize` reads `54 unclaimed, 0 to remove` -- a report category, not a regression. **Do not close that number by moving anything**; the last move was reversed.
- **THE v2 ISSUES RESIDUE: 34 markdown directories under `intent/issues/`.** Flagged, not touched. Same shape as the 54 and the same precedent applies.
- **Open: 0034, 0035, 0036, 0037, 0038.** 0034 and 0035 are the same shape as each other; 0037 is the same shape again in the documents.
- Still unfiled, and smaller than the three that were: `updatenotice.bats:9-12` claims a PTY mechanism absent from that file; `mkproj` appears in 13 test files against `MODULES.md:67`; `clean` has no `--report`.
- **`/in-finish` vs whiteboard invariant 6** -- two nodes have now independently kept a board `active` through a fold. Upstream's, unfiled.

**Blocked or explicitly not to start:**

- **`use` AS A DEVBIN BUILTIN IS BLOCKED, not merely unsequenced** -- hv's Conflab ruling, and **not to be designed around**.
- **STILL EXPLICITLY DO NOT START: `--ivault`.**

**Suite baseline is now 720/720, 0 failures, 2 self-declaring skips, bats rc 0**, captured unpiped with rc read from a file. It was 717; the three added are 0037's contract tests. **The documented way to read a bats run is quiet again** -- `grep -vE '^(ok |not ok |1\.\.|#)'` over the full suite prints nothing.

## Watch-outs

The general forms live in `intent/llm/LESSONS.md` and are not restated. What is below is live, local, and mostly earned today.

- **I WROTE A CONTROL TO CHECK FOR FALSE ALARMS AND IT RAISED THREE.** My red-drive harness ran `bats "$D" | grep -E "^not ok" || echo "*** NOTHING WENT RED ***"`. All three drives DID go red, and the alarm fired all three times anyway: under `pipefail` the pipeline takes **bats's** rc 1, not grep's 0, so `||` fires while grep is printing matches. **That is issue 0031's own shape, inside the control written to catch that class**, and the second time today a guard of mine announced something it had not established. The output was visibly correct, which is the only reason it did not mislead me.
- **AN EXTRACTOR THAT READS COMMENTS IS READING THE WRONG DOCUMENT.** My first exit-code extractor grepped raw and reported a code **126 this source has never exited**: `lib/helpers:432` describes issue 0005's failure mode in prose, and a bare grep counts a sentence ABOUT a bug as a statement that causes one. **I was one step from writing a fabricated code into the contract the test exists to protect.** Stripping comments can only lose a real exit, never invent one -- which is why the floor test is the half that matters.
- **A BROKEN EXTRACTOR MAKES A SET-CONTAINMENT TEST PASS VACUOUSLY.** Demonstrated, not assumed: breaking `source_exit_codes` left *"every code the source can return is named in the contract"* GREEN, because every element of the empty set is named. Only the floor caught it. **A test over an extracted set is worth exactly as much as the extractor's floor.**
- **A ZERO THAT MEANS "THE PATHSPEC MATCHED NOTHING" IS INDISTINGUISHABLE FROM ONE THAT MEANS "NOTHING CHANGED".** `git log A..HEAD -- $SEAM` under zsh passes the whole variable as ONE pathspec, because **zsh does not word-split** -- already on this list, and it still landed. It returned `0 seam commits` for all three fleet stamps and I was minutes from writing that into `restart.md`. Caught only because an earlier bash run had said 2. **A bogus pathspec returns the same zero**, which is why the control is not optional: `git log 49d2eb1c..HEAD -- 'no/such/path'` also prints 0.
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE.** `intent/wip.md` has recorded since sweep #6 that a depth-limited scan of the fleet returns TEN because `Arca/` is an umbrella over two sub-projects. My census ran at `-maxdepth 3` and returned exactly ten, missing exactly those two -- **in the session that had read the warning that morning.** The roster count on the same page is the only thing that caught it.
- **COUNTING PROXIES COUNTS THE PROXY.** Three distinct `source_commit` stamps read as three-way fleet divergence; the bytes say two states, one of them a single estate that is AHEAD. The stamp answers *which commit did the vendor run from*, which changes on every re-vendor whether or not a file moved. **My own board reported this as "not uniform, spread unbounded" -- pessimistic, and wrong in the direction that sounds careful.**
- **I WROTE A GUARD TO PROTECT hv's DIRECTIVES AND IT HAD BOTH FAILURES IT WAS GUARDING AGAINST.** It printed `*** A DIRECTIVE LINE MOVED -- STOP ***` and **committed anyway** -- `grep && echo || echo` exits 0 whichever branch runs, so it announced a refusal it could not perform. And the alarm was **false**: it grepped the diff for `standing directive` and matched **my own added line saying "standing directives untouched"** -- a grep cannot tell a claim from a citation of a claim. **Both defects are already in this catalogue and both arrived inside the guard written to be careful.** Settled properly by extracting the block from both revisions and `cmp`-ing them with a negative control: **14 lines, 1351 bytes, byte-identical.** *A guard that announces a stop it cannot perform is worse than no guard: it produces a record saying it fired.*
- **A CLAIM THAT NAMES A LOCATION, A PATH OR A FILE'S CONTENTS HAS AN EXPIRY DATE, AND NOTHING ON A BOARD RENDERS IT.** cc's, and the sharpest of the day. Four of five entries they corrected this morning were true when written and went false untouched -- including one accusing the restart brief of a dead path, which inverted into their own board holding the stale copy. **They surfaced only because boot re-measured the paths instead of reading the entries asserting them.**
- **REPAIRING A MEASUREMENT IS NOT ADOPTING A RULE, AND A SELF-CAUGHT DEFECT FEELS CLOSED THE MOMENT YOU CATCH IT.** cc hit `grep -cE 'A|B'` -- **an alternation counts lines matching EITHER, a UNION, not a per-item count** -- caught it themselves, disclosed it, wrote it up... then committed the identical error fifteen minutes later into a HIGH issue another estate implements from. **One literal per column, never an alternation.**
- **THE CONTROL CAN FIRE WHILE YOU READ A DIFFERENT STREAM.** Distinct from a missing control, one that examines nothing, and one answering a different question -- all already catalogued. cc's nine `command not found` lines scrolled past under the output they were watching; my `bats tests/` exited **1** honestly and my `| tail` handed me `tail`'s 0. **Check the status; do not read the stream.**
- **A BLINDED WITNESS CAN ONLY MAKE CLAIMS SCOPED TO ITSELF.** I said my census was *the only* instrument that could see the carrier. It was the third. **The blinding is what made the overclaim available** -- it hid the two legs already covering it. *"`git` cannot see X and my census can"* is the strongest form available to me.
- **A RELAY IS NOT AN INSTRUCTION.** Paid again today: hv said `GO HOP` to me and it was intent-vc's signal to issue, gated on a rehearsal review I could not see. **The first time today a relay would have authorised STARTING something irreversible.**
- **THE ISSUES SUBSYSTEM HAS THREE CANDIDATE SOURCES OF TRUTH** -- committed store, working-tree store, markdown tree -- **and its verbs do not agree on which they read.** Two independent sightings, two estates. Routed to Intent as an observation, not filed.
- **NEVER `head`/`tail` WHEN THE SIZE OR STATUS IS THE QUESTION**, and **zsh does not word-split `$VAR`** -- both bit me again today, the second inside a fold.

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here.
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc` exists.** Lamplight is a **separate track hv runs directly**, not a gap.
- **`bin/devbin` is the invocation everywhere** (supersedes D6). `DEVBIN_INVOKE` is a CONSTANT; `DEVBIN_NAME` is which project this is.
- **The project name belongs to the PRODUCT BINARY** -- `bin/lamplight` shadowed the CLI the project ships.
- **Delivery while in development is the DEV TREE** (hv, `cf49d116`). Brew installed, unlinked, re-pinned.
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`** -- present at 74393 b; `54526ca` moved the record back as 54 renames, every one R100.
