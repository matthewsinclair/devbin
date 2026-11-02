---
node: vc
name: Validation Claude
role: validation
session_id: 37214cfb-198a-4b48-980d-d4ab03e852d6
heartbeat_at: 2026-08-28 16:03Z
status: active
focus: "FLEET SWEPT ON hv's GO -- all 11 estates on one stamp 96fb408 and one digest a4c6c9a8, doctor green in every one, sweep pathspec committed in each. Convergence measured by digest, not by upgrade's rc. Live session work in Conflab, Intent and Lamplight verified untouched"
claims: []
---

# Validation Claude (vc)

## DOING

- **`dvb` CAN BOOTSTRAP NOW (`4d59c39`), and the design point is what the fallback does NOT do.** The walk finds devbin THROUGH a project that already has one, so hv could not install into a fresh directory -- it returned 127 with a candidate list, a correct report of the wrong thing. `DEVBIN_SOURCE` names a checkout and is reached only after the walk fails entirely, so it can never shadow a project's own launcher. **It runs a devbin that is NOT above `$PWD` -- exactly what the cwd guard exists to catch -- so it hands the command over and lets the guard rule.** Verified end to end rather than asserted: `dvb install` returns 0 and installs; `dvb doctor` and `dvb nosuchcmd` are refused at exit 4. **Reimplementing the exemption list in the emitted function would have put a second copy in the one place nobody would update.**
- **THE HEADER COMMENT'S OLD INVARIANT WAS TRUE AND IS NOW FALSE, so it was rewritten rather than left standing.** It said the function *"only ever invokes a devbin found at or ABOVE \$PWD"*. Prose next to code that contradicts it is the staleness class, and this one would have read as a guarantee.
- **0039 FILED (low).** The wrong-tree guard runs before command resolution, so `devbin init` OUTSIDE the tree gets rc 4 *"this is not your current project"* while INSIDE it gets rc 2 *"unknown command"*. Same typo, two diagnoses, and the refusal asserts *"every command would act on X"* about a command that does not exist. **This project's cardinal shape pointed the other way: not a green that examined nothing, but a refusal naming a cause it never established.**
- **THE FLEET IS NOW THREE SEAM COMMITS BEHIND, NOT TWO.** `lib/cmd/shell-init` is a seam file, so `4d59c39` joins `9538f4e` and `fc794aa`. **The re-vendor got bigger while it waited**, which is the argument for sequencing it rather than the argument against.
- **NOTHING IN FLIGHT.** Tree clean, everything committed. Re-measured at fold time rather than carried: `intent issues list` returns **0034, 0035, 0036**; both steel threads Completed; `git status` empty.
- **STATUS IS DELIBERATELY `active`.** `/in-finish`'s release step and protocol invariant 6 disagree about a pre-compact fold. cc measured the cost -- 3.5 hours live under a board reading `paused`, the state that drops a node off every peer's roster -- and has now independently made the same call. **Upstream's to settle; not settled locally.**
- **THIS FOLD RE-MEASURED WHAT IT KEPT.** cc's rule, from `inbox.cc` at 12:53Z and archived with this board: *a fold rewrites a claim more tightly without re-testing it, so the survivor reads as freshly reviewed.* Anything below that could be re-measured in one command was; anything that could not is marked.

## The record -- pointers, not restatements

Everything is in `.history/20260828/`. **A record nothing points to is a record nobody finds**, and a summary here is how the copies drift.

| artefact | what it is |
| --- | --- |
| `devbin-guard-red-drive.md` | the four guards driven red: 6 arms, 1 green control, and the residue they do NOT cover |
| `conflab-phase4-report.md` | Conflab Phase 4: the verdict, its limits, the addendum that upgraded the gate finding |
| `conflab-phase4-preregistration.md` | ten predictions sealed BEFORE the hop; **P6 wrong**, the rest confirmed |
| `conflab-prehop-*` | the 1365-row census and the state it was taken against |
| `barrier-vs-propagation-joint.md` | the protocol escalation, co-signed with devbin-cc |
| `wip-prefold.md`, `wip-prefold-1420Z.md` | this board at each of the day's two folds |
| `inbox.cc-archived*.md` | cc's inbox entries, both batches, verbatim |

**Headlines, so a reader need not open anything.** Conflab **IS** on v3, **nothing was lost** (`vanished=0` of 1365), and `doctor`'s `gate-not-running` on a shim is a **false red by measurement** -- conflab-ic's two-arm control refused arm 1 naming check B and committed arm 2. Filed upstream as `intent#0105`. **Devbin's four commit guards CATCH** -- clock A/B/C, header, append-only, canon-ignore, all six arms rc 1 with HEAD unmoved, against a green control that landed. **What they still miss is written down with the result.** **Nobody ran a functional suite against Conflab post-hop**; that was never in my unit.

## TODO -- all hv's to sequence, none started

- **THE FLEET RE-VENDOR IS DONE (2026-08-28, hv's go).** All 11 estates on one stamp `96fb408` and one seam digest `a4c6c9a8`. hv had already upgraded the four they had open; I swept the remaining seven. **Convergence measured by digesting each vendored `lib/`, never by `upgrade`'s exit status** -- all seven returned rc 0 with zero refusal lines, which per issue 0021 answers *did I complete* and not *did I converge*. `doctor` rc 0, 0 failed, in all eleven after. **Sweep pathspec committed in every tree per hv's standing directive, seam paths only** -- and verified rather than assumed: Conflab's five live board files, Intent's nine Rust files and Lamplight's two boards were still dirty and untouched afterwards.
- **0036 IS UPSTREAM AND SHARPER THAN I FILED IT.** cc's finding, verified here: `bin/.devbin/config.yaml:40` declares `run: bats tests/unit` -- **the repo already holds the right answer and the generated `AGENTS.md` contradicts it.** Two candidate fixes and they are not the same size: change the template default to `bats -r tests/` (no cross-tool coupling), or give Intent a project-level way to declare a test command. **Note the honest limit on cc's framing:** `agents sync` reading `bin/.devbin/config.yaml` would mean Intent depending on devbin, so it is a proposal rather than a bug of omission.
- **THE `st attach` RULING IS OWED** and is the only thing that closes the 54. 22 of those files exist nowhere else; `organize` reads `54 unclaimed, 0 to remove` -- a report category. **Do not close that number by moving anything.**
- **v2 ISSUES RESIDUE: 34 markdown directories.** v3 files to canon and writes none. Flagged, untouched, same precedent.
- **0034 and 0035 are open and deliberately NOT started.** 0035 is four instances each ending in *"state whether this is a convention"* -- only hv can rule. 0034 is real code (every gate leg should write `SCOPE:`; only `lua` does) but **Lamplight-originated, and hv runs that track**.
- **`intent issues` HAS NO EDIT VERB.** Surfaced to hv. 0036's body asks a question I have since answered and there is nowhere in the issue to put it.
- Smaller, unfiled: `updatenotice.bats:9-12` claims a PTY mechanism absent from that file; `mkproj` in 13 test files against `MODULES.md:67`; `clean` has no `--report`.

**Blocked or explicitly not to start:** **`use` as a devbin builtin is BLOCKED** and **not to be designed around** -- a builtin making the brew-vs-dev-local switch frictionless would silently resolve a policy question hv holds open. **STILL EXPLICITLY DO NOT START: `--ivault`.**

**Suite baseline 725/725**, 0 failures, 2 self-declaring skips, rc 0, captured unpiped. 717 -> 720 (0037's contract tests) -> 725 (the DEVBIN_SOURCE arms).

## Watch-outs

General forms live in `intent/llm/LESSONS.md` and are not restated. These are live and mostly earned today.

- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD: the record then contains a line saying it fired.** Paid twice. My directive guard printed `*** STOP ***` and committed anyway (`grep && echo || echo` exits 0 either way) on a **false** alarm -- it matched my own sentence *claiming* the directives were untouched, because a grep cannot tell a claim from a citation of one. Then my red-drive harness printed `*** NOTHING WENT RED ***` three times while all three drives **were** red: under `pipefail` the pipeline takes bats's rc, not grep's. **That is issue 0031's shape inside the control written to catch it.** Settle these by extraction and `cmp` with a negative control, never by a compound whose status is not the thing you are asserting.
- **AN EXTRACTOR THAT READS COMMENTS IS READING THE WRONG DOCUMENT.** My first exit-code extractor reported a code **126 this source has never exited** -- `lib/helpers:432` describes issue 0005's failure mode in prose, and a bare grep counts a sentence ABOUT a bug as a statement causing one. **One step from a fabricated code entering the contract the test protects.**
- **A BROKEN EXTRACTOR MAKES A SET-CONTAINMENT TEST PASS VACUOUSLY.** Demonstrated: breaking `source_exit_codes` left *"every code the source can return is named"* GREEN, because every element of the empty set is named. **Only the floor caught it. A test over an extracted set is worth its extractor's floor and no more.**
- **A ZERO MEANING "THE PATHSPEC MATCHED NOTHING" IS INDISTINGUISHABLE FROM ONE MEANING "NOTHING CHANGED".** `git log A..HEAD -- $SEAM` under zsh passes ONE pathspec -- **zsh does not word-split** -- and returned `0 seam commits` for all three fleet stamps, minutes from `restart.md`. **A bogus pathspec returns the same zero**, which is why the control is not optional.
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE.** `wip.md` has recorded since sweep #6 that a depth-limited fleet scan returns TEN because `Arca/` is an umbrella over two sub-projects. My census ran `-maxdepth 3` and returned exactly ten -- **in the session that read the warning that morning.**
- **COUNTING A PROXY COUNTS THE PROXY.** Three `source_commit` stamps read as three-way divergence; the bytes say two states, one of them a single estate that is AHEAD. **My own board reported it as "not uniform, spread unbounded" -- wrong in the direction that sounds careful.**
- **A CORRECT RULE FILED UNDER THE WRONG CONCERN IS INVISIBLE TO THE PERSON WHO NEEDS IT.** 0037's whole shape: the BW01 mechanism was already reasoned in `buildfmt.bats:846`, for a different test, in a different file. Same as the heredoc rule that sat under Tests.
- **A CLAIM THAT NAMES A LOCATION, A COUNT OR A FILE'S CONTENTS HAS AN EXPIRY DATE, AND NOTHING ON A BOARD RENDERS IT.** cc's, and sharpest of the day. My own globalfold said "717" and "three findings unfiled" and both were false ninety minutes later **because of my own afternoon.**
- **A RELAY IS NOT AN INSTRUCTION**, and **a blinded witness can only make claims scoped to itself.** Both paid today.
- **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION.**

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here.
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc` exists.** Lamplight is a **separate track hv runs directly**.
- **Rule 2 (no builds in the Intent tree) is LIFTED estate-wide**; rules 3 (`git add` + `commit --only` by path) and 4 (every timestamp read from `date -u` in the writing command) stand.
- **`bin/devbin` is the invocation everywhere** (supersedes D6). `DEVBIN_INVOKE` is a CONSTANT; `DEVBIN_NAME` is which project this is.
- **Delivery while in development is the DEV TREE** (hv, `cf49d116`).
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`.**
