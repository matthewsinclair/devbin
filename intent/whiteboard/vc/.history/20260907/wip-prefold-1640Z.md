---
node: vc
name: Validation Claude
role: validation
session_id: 0e264898-52d8-46db-8d2b-aa5edf99757e
heartbeat_at: 2026-09-07 14:08Z
status: active
focus: "BOTH TASKS hv NAMED ARE DONE AND COMMITTED -- 6877dc0 takes the install prefix out of lib/install and moves the infra schema to lib/infra.reference.yaml, VENDORED, with docs/infrastructure.md deleted. Suite 1008/1008, check all rc 0, delivery walked cold into a fresh project. Molt CI GREEN at 34f5409, all four jobs, first since 09-04 -- two arms were reading the author's machine. 36 commits unpushed here and the tag still names e22d9a3; both hv's. NEXT: ST0003 WP-02"
claims: [ST0003, ST0005]
---

# Validation Claude (vc)

**Board cut 2026-09-07 12:41Z. Pre-fold archived at `.history/20260907/wip-prefold-1241Z.md`, 6838 b, cmp-verified against BOTH the working file and the committed version before this was written.** Six general forms were promoted to `intent/llm/LESSONS.md` FIRST (306 -> 338 across today's two folds, each entry verified present by grep), because an aggressive fold is when they get lost.

## DOING

- **CI WENT RED ON THE PUSH AND IS FIXED, NOT YET CONFIRMED GREEN.** 11 Ubuntu arms, 0 macOS: `xmllint` (9 DMARC parse arms) and `zsh` (2 dvb arms), neither installed on that runner. **FIRST EXPOSURE, NOT REGRESSION** -- last CI was 2026-09-03 at `d620bb7`; both files landed after it while nothing was being pushed. **One arm went GREEN for the wrong reason**: `a malformed report FAILS LOUDLY` matched `parse|malformed|xml` against `xmllint not found`, so it could not tell a rejected input from an uninstalled parser -- measured both ways. hv ruled install-plus-CI-aware-guard: `require_command` now SKIPS off CI and **FAILS under CI**, so deleting the apt line goes red rather than reverting to silent skips. Nine hand-rolled `command -v zsh || skip` folded into the registered owner. **Confirm the Ubuntu job green after the push.**
- **ST0003 WP-02 IS NEXT AND UNBLOCKED.** The DNS and mail legs of `infra check`. The blocker was that no `infra.yaml` existed anywhere; Prodinfra now carries three real ones. dc's constraint for the DMARC store: **key on `report_id`, never the reporter's filename** -- two real reports share reporter, domain AND window.
- **WP-03 CARRIES AN OPEN DEPENDENCY I CREATED TODAY AND DID NOT CLOSE.** `design.md:163` names the STANDARD as `infra init`'s primary proposal source at N=1, and the document it read from is deleted. **Recorded as a dependency, NOT repointed at `lib/infra.reference.yaml`** -- a schema determines shape and never values, so the pointer would have looked like a fix and delivered none. Two candidates, neither chosen: a dated table in the vendored half whose age `check` reports every run, or no shipped standard at all with every vendor-derived field going to `unreviewed:`.
- **THE FIXTURE SET DC ASKED FOR, AND THE MOVE MAKES IT SHARPER.** My guard proves the reference PARSES; it does not prove `lib/config` still REFUSES the three bad forms. Four fixtures in red/green pairs, each wrong-form arm asserting the SPECIFIC message from `design.md:93` -- a refusal firing for the wrong reason is still green.

## TODO

**`intent/wip.md` is the authority for project work.** Only my own queue follows.

### With hv

- **THE PUSH HAPPENED, AND THIS LINE WAS WRONG UNTIL 14:08Z.** It read _36 commits unpushed; both remotes at `d620bb7`_. hv pushed: **both remotes are at `3430009`**, measured with `git ls-remote` against the REAL names -- `local` and `upstream`, never `origin`. Local is 1 ahead (the localfold, whiteboard-only). **The board was stale on the one fact a peer would have acted on**, and nothing reported it -- a count carried forward across a compact is a guess wearing a measurement's clothes.
- **WHETHER TO TAG.** `v0.1.0` is annotated, PUSHED to both remotes, and names `e22d9a3` -- **70 commits and 18 vendored files behind what the fleet runs, with no `infra` in it at all**, while `RELEASES/0.1.0.md` dates 0.1.0 to 2026-09-06 and describes the machine install.
- **THE FLEET SWEEP.** 14 estates on 0.1.0, opt/ on 0.1.1 and now behind the dev tree again. Deliberate; the sweep is hv's go.
- **THE INTENT BACKUP IS 68h OLD against a 24h schedule** -- `intent doctor`'s only remaining finding here. Something that was supposed to run is not.

### Mine, unsequenced

- **`0060`** -- a `die` at command-substitution depth 2 is swallowed. The class NOT fixed fleet-wide, because `shopt -s inherit_errexit` in `bin/devbin` is in force across 14 estates the moment it lands.
- **`0059`** BEHIND-you cannot fire against an install. **`0056`** census reads disk, never git. **Seven open, read live 12:38Z**: `0034` `0035`(parked) `0036` `0039` `0056` `0059` `0060`.
- **THE GUARD RED-DRIVE HAS EXPIRED.** hv's board states six red arms as settled; four have had bodies REPLACED since and resolve live out of `INTENT_HOME`. Not a regression claim -- the evidence no longer covers the code in force. ~40 min.
- **THE CARRIER HOLE.** `.git/hooks/pre-commit.intent` is byte-identical to Intentv2's FROZEN template. Devbin cannot fix it from here.

## Holds

- **`use` as a devbin builtin -- BLOCKED.** **Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START.** **Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`, and that was made TRUE at both of today's folds -- 306 -> 338, each entry verified by grep rather than asserted.** The rule that keeps it true: **promote before cutting, never after.**

**The one that explains today, and it is mine: verification performed where the thing already works.** ST0005 shipped 19/19 AC and 973 green arms with the distribution path never walked; the afternoon then produced the same shape twice more -- a schema documented where no consumer could read it, and a Molt test that read the author's home directory and so was green in the only place it could not fail. Three costumes, one class.

## Decisions

### The ruling of 2026-09-07, and it was applied twice in one commit

**NOTHING MACHINE- OR ESTATE-SPECIFIC BELONGS IN A TOOL OTHER ESTATES VENDOR** -- the install prefix, and `docs/infrastructure.md`. Same ruling as `fleet:47-63`, 2026-08-29. **D32 is now true in code**: the baked `$HOME/Devel/opt/devbin` is gone, unset returns rc 1, three verbs refuse through one shared message. **rc rather than an empty string** -- a caller that forgets an empty check writes to `/bin`, one that forgets an rc dies at the assignment, and only one of those is silent.

**D1-D25 are in `intent/st/COMPLETED/ST0001/design.md`; D26-D34 in `intent/st/ST0005/design.md`.** Not restated here -- this board carried a six-bullet paraphrase of them until this fold, which is a second copy of a decision record in the file that tells peers to read the first.

### Standing

- hv's standing directives live on `hv/wip.md`; nothing duplicated here. **I hold that pen under hv's explicit grant.**
- **A peer's recommendation is never authorisation** -- exercised twice on 2026-09-07: dc relayed a deletion ruling and I held until hv gave it to me directly.
- **`bin/devbin` is the invocation everywhere** (supersedes D6). **`devbin_version` in devbin's own config MUST stay a hand-written literal** -- deriving it makes doctor's check unfailable.
- **`devbin-users.md` is a snapshot; a stale stamp goes to hv, never to a rebuild.**
