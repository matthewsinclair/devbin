---
node: vc
name: Validation Claude
role: validation
session_id: 64b942fd-acdf-4697-9bbf-a4b030b3c761
heartbeat_at: 2026-09-02 08:22Z
status: active
focus: "v0.1.0 RELEASED and tagged at e22d9a3, rolled to 11 estates. hv pushed main to both remotes; THE TAG REACHED NEITHER -- git push <branch> does not carry tags, verified by git ls-remote. Twelve issues open, two high (both fullcycle) and 0051 new from laksa/dc. An 18-item ruling docket is with hv. Nothing in flight; nothing to start until hv rules"
claims: []
---

# Validation Claude (vc)

## DOING

- **Nothing in flight.** Folded before a compact, not at session end -- `status` stays `active` per `/in-whiteboard` invariant 6.
- Working detail for 2026-09-01 is archived at `.history/20260901/wip-prefold-1709Z.md`. Not restated here.

## TODO -- all of it needs hv

- **THE DORMANCY VERB.** `intent/vc` adjudicated my proposed static gate down and replaced it: report the **test delta** between a project's declared invocation and `--all-features`. It adjudicates rather than proxies, produces the motivating number, and dissolves the undecidable third term by comparing against a MAXIMUM rather than an enumerated set of invocation sites. **Costs a build, so it is a verb someone runs, not a check arm.** Not started; hv's ruling outstanding, and D18's *never speculatively* cuts against it while *a stale test CERTIFIES rather than misinforms* cuts for it.
- **`conflab/vc`'s `--lib` finding is `intent/cc`'s, not mine.** Conflab's `test rust` runs `--lib` for the daemon without `--all-targets`, so the orphan guard they shipped does not run in the gate meant to catch things. In their inbox already.
- **THE TAG.** `v0.1.0` exists locally at `e22d9a3` and **on neither remote**. hv pushed `main` to both on 2026-09-01 and both carry `2456ac6`; `git push <remote> <branch>` does not carry tags, so the release workflow has never fired and the version is a local-only claim. `git push local v0.1.0 && git push upstream v0.1.0`. **This is the one blocking item.**
- ~~**The `st attach` ruling.**~~ **WITHDRAWN, and the withdrawal is the finding.** `intent st organize` was RETIRED in Intent v3, so the `54 unclaimed across 28 directories` I carried to hv for weeks came from a command that no longer exists and was never re-measured. There is no number here to rule on. Same class as the day's recurring defect, committed by me, in the docket built to hand it over.
- **Three upstream-template questions, one class**: `0036`, `gtools#0003`, and `/in-finish` step 3. Each is an Intent-shipped template with no per-project override, so every consumer inherits it and none can fix it locally.
- **The sync-provider standing rule** cc asked for and I seconded. Exposure is currently zero, which is a consequence of another estate's move rather than a decision.
- **Convention rulings on `0035` and `0042`.** `0034` is Lamplight-originated. `0039` is deliberately still open.
- **THE TWO `high` ISSUES ARE ONE PIECE OF WORK.** `0050` (no restore half, permanently red where PATH links exist) and `0048` (check vacuous where they do not) are the same weakness from opposite sides. Taking `0050`->A with `0048`->B is coherent; taking either alone is not. hv's, because `fullcycle` is destructive and this changes what it does on eleven estates.
- **`0047`'s relayed ruling is UNACTED ON, deliberately.** `intent/dc` relayed option 3. **A relay that GRANTS authority over a destructive verb is not safe to act on** -- a wrong grant is irreversible where a wrong pause costs a minute. Confirm or deny from hv directly.
- **v2 issues residue: 2 OPEN, 34 CLOSED** -- not the flat "34 markdown directories" this line carried until 2026-09-02. **The two under `OPEN` are the interesting part**; they may be issues that never migrated. v3 writes none. Flagged, untouched.

## Holds

- **`use` as a devbin builtin -- BLOCKED, and not to be designed around.** Released only by hv lifting it.
- **`--ivault` -- EXPLICITLY DO NOT START.** Released only by hv saying so.

## Watch-outs

General forms are in `intent/llm/LESSONS.md`.

- **A FINDING WHOSE TRUTH DEPENDS ON AN UNREAD MECHANISM IS A QUESTION, NOT A FINDING** (`laksa/dc`, 2026-09-02, on themselves). They sent a measured crate census plus a prescription -- *absent target must be SKIPPED, not judged* -- which presumed my discovery enumerated CRATES. It enumerates BUILD TREES, so the case was invisible by construction and there was nothing to skip. **The census was measured and correct; the prescription hung off it was a guess wearing the census's credibility.** Their own form of this, sent to me two days ago, is the same shape: a measured correction lends its authority to the un-run clause beside it. The honest shape when you cannot read the code is conditional -- *if it enumerates X then this follows; if Y, ignore this half* -- which costs the reader one line instead of a fixture.
- **AN ASSERTION CAN BE SO WIDE IT FORBIDS THE TRUTH.** My `refute_output_contains "lumis_nif"` would have gone red on `clean` correctly reporting a tree it IGNORED -- a neighbouring instrument behaving properly. **The mutant-survives problem in reverse.** Scope every assertion to the instrument under test, not to the whole output stream.
- **READING A FUNCTION IS NOT READING A CODE PATH** (`laksa/dc`, 2026-09-02). They read `_fullcycle_phases` correctly and drew a conclusion one function wider than what they had read -- in the same message where they named scope-restatement as the house failure mode. **The tell needed no knowledge of the answer: they never asked who calls it.** That is checkable BEFORE you know whether you are wrong, which is the only kind of tell worth having, and it is a stronger form than anything I had been carrying on this class (all of mine are after-the-fact). **Naming a pattern does not inoculate you against it** -- and the instance that lands on the namer is the most informative one, so it gets recorded rather than dropped out of politeness.
- **A DUPLICATED DECISION IS BENIGN UNTIL THE COPIES DISAGREE ABOUT THE SAFE DIRECTION.** `fullcycle` gates one predicate twice: the guard fails CLOSED and loudly, the phase list fails OPEN and silently into the net-destructive cycle the guard refuses. **Call order is the only thing holding it off, and call order is not a thing anyone edits deliberately.** Three ordinary tidy-ups arm it. Filed `0051`. The general form: when two copies of one decision differ, ask which one SURVIVES a deletion, not which one is correct.
- **`git commit --only` LEAVES INDEX RESIDUE, AND THE RESIDUE IS A SILENT REVERT** (`laksa/dc`). The index can retain the PRE-FORMATTER blob while HEAD and the worktree hold the formatted one, so the next bare `git commit` in a shared tree undoes the gate's own formatting with nothing said. **Not stale content -- armed content.** Checked in devbin 2026-09-02: `git diff --cached` and `git diff` both empty, no residue here. **And that clean tree is NOT evidence, in either direction** -- four commits with an empty index is equally consistent with the convention holding and with nothing having exercised it. `laksa/dc` refused to carry it as corroboration of theirs and named the reason: **"no residue observed" and "residue cannot occur" produce the identical reading.** That is fullcycle's empty watch list exactly -- the same shape as `0048`, met in git rather than in a gate. What prevents the residue is a convention, not a mechanism, and no observation of a clean tree can tell you which one you are looking at.
- **A SOUND INSTRUMENT, AIMED ONE UNIT WIDE, RETURNING CLEAN. Eight instances on 2026-09-01, most of them mine.** `[profile.dev]` read from a member manifest when cargo honours only the workspace root; `native/cli` given its sibling's status; `ci.yml:156` given the job next to it; Conflab's `--lib` asserted about Intent's `--workspace`; `tail -25` and `intent/vc`'s `head -10`; a probe for a build VERB standing in for the PROPERTY of restoring artefacts; a MESSAGE cited as a DOCUMENT. **The artefact boundary and the file boundary do not coincide, and nothing in the output says which one was measured.** `intent/vc`'s form is the sharpest: **a display limit is a population filter wearing no clothes at all** -- `-maxdepth` at least reads as scope, `head` reads as formatting.
- **A DANGLING SYMLINK IS INVISIBLE TO A PATH RESOLVER** (`conflab/vc`). `clean`'s at-risk detector resolves basenames through PATH, so **once anything darkens a binary, every later run is CORRECTLY silent about repeating the damage.** Worse than a control that cannot go red, because it used to work. Only a before/after control sees it, and it must scope its claim to links that resolved at the start.
- **AN ARTEFACT SET LOOKS LIKE A RUN AND IS NOT ONE.** Gates stamp per OPTION, so `20260901-1835` holds CRITIC/FORMAT/TOOLCHAIN from a run that FAILED lint and LINT/SYNTAX from the next run, which passed. **A false green assembles itself out of entirely honest files**, and the minute is the only run-key candidate present so it is the one a reader will use. Filed as `0045`. **`ls -t | head -1` returned the previous run's counter reading `33 file(s), 0 breach(es)` -- true, and about a different run.** Reconstructing the boundary took `stat` on mtimes.
- **A SUPPRESSION BELONGS TO ITS CALL SITE, NOT TO THE FILE IT WAS WRITTEN IN.** Moving a `printf` out of `bin/devbin` into `lib/helpers` left `# shellcheck disable=SC2119` behind. Lint reddened at the new site, and the orphan left at the old one **suppressed nothing while still reading as a considered decision** -- so it had to be deleted, not just duplicated forward.
- **ZSH DOES NOT WORD-SPLIT AN UNQUOTED `$var`, AND MY HARNESS MANUFACTURED A FALSE RED WITH IT.** A loop running `bin/devbin $c` passed `devbin --version` as ONE token and reported `unknown command` for two surfaces that work. Same root as **`PIPESTATUS` IS BASH AND THIS SHELL IS ZSH** below. **A false red is cheaper than a false green and it is not free: I nearly reported a working command broken to hv.**
- **A TRAP DOCUMENTED BY ITS SIGNATURE IS TRIPPED BY ANYTHING THAT REPRODUCES THE SIGNATURE.** hv's board says an extractor that drops the heading reports **12** lines and *reads like a lost directive*. At pickup today my extractor reported 12 -- by dropping the TRAILING BLANK instead. Same alarm, different cause, and the documented cause is the one a reader will believe. **Both readings are 12; only 1341 vs 1319 separates them, and nothing prompts anyone to look at the byte count once the line count has already matched a named failure.** Verify against the invariant with the most bits -- the bytes and the item COUNT -- never the one the warning happens to name. This is `devbin/cc`'s *a trap described by its instance gets defended against by its instance*, inverted: theirs under-fires, this one FALSE-fires, and a false-firing alarm sends you hunting for damage that was never done.
- **A CONTROL THAT DID NOT APPLY IS INDISTINGUISHABLE FROM ONE THAT PASSED**, and a red arm that fails for the WRONG REASON is worse, because a red arm is the one nobody re-examines (`conflab/vc`: a guard control that exited 101 on a compile error). Every break now asserts its own byte delta before its result is read.
- **A PRINTED NUMBER GETS READ INSTEAD OF RUN** (`intent/vc`, via `intent/dc`). Stating a figure beside its regenerating command buys auditability and nothing at all for currency -- TN001's cost table went stale under exactly that caption. **Live figure: print the command, delete the number. Historical figure: date it.**
- **A MESSAGE HAS NO REVISION, SO THE MESSAGE IS THE COPY THAT ROTS.** Citing one as a document upgrades its authority to something checkable while removing everything that would let anyone check it. Quote the channel as the channel.
- **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION**, and **every timestamp is READ FROM A CLOCK in the writing turn** -- a value off a tool's filename carries that tool's zone, and appending `Z` is an assertion.
- **A RELAY IS NOT AN INSTRUCTION.** **`PIPESTATUS` IS BASH AND THIS SHELL IS ZSH.** **A pipeline's rc is its LAST command's**, so `cmd | tail` reports `tail`.

## Decisions

### THE DOCKET IS RULED -- hv, 2026-09-02 15:55Z, all eighteen items

Taken interactively in terminal, item by item from the top. **hv overruled my recommendation on two rows and rejected the premise of a third**; those three are marked, because a docket that records only the agreements is a record of my own opinions.

| item        | ruling                                                                  |
| ----------- | ----------------------------------------------------------------------- |
| TAG         | DONE -- pushed to both remotes, `Release` workflow green in 19s         |
| INTENT      | vc sweeps it with the others                                            |
| INTENTV2    | **FULLY FROZEN.** Drift reporting STOPS; recorded as deliberate         |
| `0047`      | CONFIRMED -- option 3, the split                                        |
| `0050`      | Targeted restore phase after `build all`                                |
| `0048`      | Before/after on the build tree; composes with `0050`                    |
| `0045`      | Stamp once per invocation, low priority                                 |
| `0046`      | Move the write before the seal; settles the generalisation too          |
| `0049`      | CLOSE -- the label was the defect and it is fixed                       |
| VERSION     | Yes -- devbin's `--version` carries `(tree <sha>)`                      |
| DORMANCY    | **BUILD IT NOW** -- hv overruled my "park until a second estate asks"   |
| SYNC        | **DROPPED, and the premise was wrong.** See below                       |
| NOTICE      | File AND fix -- compare the seam digest, not the commit                 |
| ST ATTACH   | DROP -- a v2 question about a v2 layout                                 |
| V2 RESIDUE  | Delete, AFTER confirming all 36 are in the canon store                  |
| TEMPLATES   | ONE Intent issue naming the class                                       |
| `0042`      | Add a `--dry-run` needing no tty                                        |
| `0035`      | PARK deliberately -- it deserves its own session                        |
| `0051`      | Delete the inner conditional; emit `build all` unconditionally          |
| `0052`      | Footnote `0.1.0`'s Verified in place; MEASURE the 8 before fixing       |

- **SYNC: the rule is dropped and my framing of it was wrong.** hv: *"Those `~/Dropbox/Repositories` are all `--bare` git repos. No work happens over there at all."* Verified: `core.bare = true`, bare layout, and **no devbin estate is under Dropbox** -- all thirteen are under `Devel/prj/`. So the "live instance" I put on the docket was not an instance of anything. **`cc` asked for a rule about WORKING TREES; I widened it to REMOTES so it would reach something in this repo.** That is the day's own class, committed in the act of asking for a rule against carelessness. **The 117-files-at-zero-bytes corpse is also withdrawn from use until somebody establishes what it was** -- I inherited it from `cc` and never checked whether those files were in a git repo at all. Owed to `cc`.
- **DORMANCY: hv overruled the park.** My ground was D18's *never speculatively* plus one estate hitting it once. hv's is that the design is settled and conceded, so the speculative objection has already been paid off. Build it.
- **`0052`: hv did NOT take the tag-as-CI-trigger fix**, which is the gap that left `e22d9a3` untested. Two of three taken: the seal records its platform, and the two shellcheck thresholds get reconciled. Recorded as declined, not as pending.

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here. **I hold that pen under hv's explicit grant; corrections factual only, standing directives byte-verified every time.**
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc`.** Lamplight is hv's separate track.
- **Rule 2 (no builds in the Intent tree) is LIFTED**; rules 3 (`git add` + `commit --only` by path) and 4 (timestamps read from `date -u`) stand.
- **`bin/devbin` is the invocation everywhere** (supersedes D6). Delivery while in development is the DEV TREE.
- **`devbin_version` in devbin's own config is a CONSTRAINT and MUST stay a literal.** Deriving it from `VERSION` makes `doctor`'s check unfailable.
- **`devbin-users.md` is a snapshot, not a standing fact.** A stale stamp goes to hv, not to a rebuild.
- **The `fullcycle` criterion is silent growth, not arithmetic** (2026-09-01): declared `[[test]]` blocks pass at any count because a reviewer sees them; auto-discovery is what grows unannounced. Intent's own crates are why -- two keep a second target deliberately.
- **ONE RENDERER FOR THE IDENTITY LINE** (hv, 2026-09-01). `version_identity` in `lib/helpers` is the single home; `--version` and the bare `version` both call it and **no third site prints that line itself**. `version show` stays bare -- it is the machine arm. A project outside git renders `(unknown)` rather than dropping the field, because omitting it rebuilds the same defect: one command, two shapes, chosen by circumstance.
- **THE FLEET SWEEP IS COMMITTED, NOT JUST WRITTEN** (hv's go, 2026-09-01). Twelve estates at `e39fba7`, vendored paths clean in every one. **`fleet audit` reads DISK and says nothing about git**, which is how "thirteen re-vendored" was true and "thirteen committed" was false at the same time -- `intent/vc` and `laksa/dc` both found it before I did.
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`.**
