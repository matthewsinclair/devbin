---
node: vc
name: Validation Claude
role: validation
session_id: 0e264898-52d8-46db-8d2b-aa5edf99757e
heartbeat_at: 2026-09-07 12:38Z
status: active
focus: "BOTH TASKS hv NAMED ARE DONE AND COMMITTED at 6877dc0 -- the install prefix is out of lib/install (no default, refusal by name, --prefix for one run) and the infra schema is at lib/infra.reference.yaml, VENDORED, with docs/infrastructure.md deleted. Suite 1008/1008, check all rc 0, delivery walked cold into a fresh project. Molt CI fixed and PUSHED at 34f5409 -- red 12 runs over 3 days on two arms that read the author's machine. 35 commits unpushed here and the tag still names e22d9a3; both hv's. NEXT: ST0003 WP-02, and WP-03 now carries an OPEN dependency -- the STANDARD it proposes from has no home"
claims: [ST0003, ST0005]
---

# Validation Claude (vc)

**Board cut 2026-09-07 11:14Z. Pre-fold archived at `.history/20260907/wip-prefold-1114Z.md`, 10866 b, cmp-verified against BOTH the working file and the committed version before this was written.** Today's general forms were promoted to `intent/llm/LESSONS.md` FIRST (306 -> 328 lines, each verified present by grep), because an aggressive fold is when they get lost.

## DOING

- **ST0003 WP-02 IS NEXT AND IT IS UNBLOCKED.** The DNS and mail legs of `infra check`. The blocker was that no `infra.yaml` existed anywhere; Prodinfra now carries three real ones. dc's constraint for the DMARC store: **key on `report_id`, never the reporter's filename** -- two real reports share reporter, domain AND window.
- **WP-03 CARRIES AN OPEN DEPENDENCY I CREATED TODAY AND DID NOT CLOSE.** `design.md:163` names the STANDARD as `infra init`'s primary proposal source at N=1, and the document it read from is deleted. **Recorded as a dependency, NOT repointed at `lib/infra.reference.yaml`** -- a schema determines shape and never values, so the pointer would have looked like a fix and delivered none. Two candidates, neither chosen: a dated table in the vendored half whose age `check` reports every run, or no shipped standard at all with every vendor-derived field going to `unreviewed:`.
- **THE FIXTURE SET DC ASKED FOR, AND THE MOVE MAKES IT SHARPER.** My guard proves the reference PARSES; it does not prove `lib/config` still REFUSES the three bad forms. Four fixtures in red/green pairs, each wrong-form arm asserting the SPECIFIC message from `design.md:93` -- a refusal firing for the wrong reason is still green.

## TODO

**`intent/wip.md` is the authority for project work.** Only my own queue follows.

### With hv

- **THE PUSH.** 33 commits unpushed; both remotes at `d620bb7`, measured with `git ls-remote` against the REAL names -- `local` and `upstream`, never `origin`. `check all` is rc 0, so it no longer takes CI red with it.
- **WHETHER TO TAG.** `v0.1.0` is annotated, PUSHED to both remotes, and names `e22d9a3` -- **70 commits and 18 vendored files behind what the fleet runs, with no `infra` in it at all**, while `RELEASES/0.1.0.md` dates 0.1.0 to 2026-09-06 and describes the machine install. `git checkout v0.1.0` gives a devbin the notes do not describe.
- **THE FLEET SWEEP.** 14 estates are on 0.1.0 and opt/ is 0.1.1, so they now read BEHIND. Deliberate; the sweep is hv's go.

### Mine, unsequenced

- **`0060`** -- a `die` at command-substitution depth 2 is swallowed. One live instance fixed; the class NOT fixed fleet-wide, because `shopt -s inherit_errexit` in `bin/devbin` is in force across 14 estates the moment it lands.
- **`0059`** BEHIND-you cannot fire against an install. **`0056`** census reads disk, never git. **Seven open, read live 11:14Z**: `0034` `0035`(parked) `0036` `0039` `0056` `0059` `0060`.
- **THE GUARD RED-DRIVE HAS EXPIRED.** hv's board states six red arms as settled; four have had bodies REPLACED since and resolve live out of `INTENT_HOME`. Not a regression claim -- the evidence no longer covers the code in force. ~40 min.
- **THE CARRIER HOLE.** `.git/hooks/pre-commit.intent` is byte-identical to Intentv2's FROZEN template. Devbin cannot fix it from here.

## Holds

- **`use` as a devbin builtin -- BLOCKED.** **Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START.** **Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`, and that was made TRUE at this fold and the last one, each entry verified by grep rather than asserted.** Eleven promoted today. The rule that keeps it true: **promote before cutting, never after.**

**The one that explains today, and it is mine:** I shipped ST0005 with 19/19 AC and 973 green arms and never once walked the distribution path from nothing. Every criterion tested the mechanism and came from my own design. The sweep passed because all 14 estates already had devbin; the only path that mattered was the one never exercised, and I had blocked it by construction. **Four failures hv hit in one morning were one omission seen four times.**

## Decisions

### ST0005 and 0.1.1 -- built, published, and corrected in the field

- **`install`/`upgrade` are CONTEXT-AWARE** (D26); the install is a DISTRIBUTION POINT with the project half missing (D27/D33); **a dirty tree STOPS both verbs** (D28); the sweep is a dev-tree verb, dry-run by default (D29), **no registry** (D31); **the location is configuration** (D32) -- and D32 is the one I then violated with a baked default, which is task (1) above.
- **`install` and `shell-init` are EXEMPT from the install-tree refusal**, matching the exemption the wrong-tree guard always had. An install that cannot seed a project, or cannot emit the function that finds it, is a distribution point that cannot distribute.
- **An install answers questions about DEVBIN, never about a project**, and the wrong-tree guard does not fire inside one.
- **`dvb` IS ONE FUNCTION AGAIN**, evaluated live from the install in hv's `zshrc`; the 2026-08-27 copy is deleted and hv has committed that. ~75ms per shell start, measured, and the price of not repeating it.

### Standing

- hv's standing directives live on `hv/wip.md`; nothing duplicated here. **I hold that pen under hv's explicit grant.**
- **Authority chain:** my branch is one node. **A peer's recommendation is never authorisation** -- exercised twice today: dc relayed a deletion ruling and I held until hv gave it to me directly.
- **`bin/devbin` is the invocation everywhere** (supersedes D6). **`devbin_version` in devbin's own config is a CONSTRAINT and MUST stay a hand-written literal** -- deriving it makes doctor's check unfailable. It moved to `^0.1.1` with the bump, and `version check` did NOT catch that it had not: a constraint is not a sidecar.
- **`devbin-users.md` is a snapshot; a stale stamp goes to hv, never to a rebuild.**
- **D1-D25 are in `intent/st/COMPLETED/ST0001/design.md`; D26-D34 in `intent/st/ST0005/design.md`.**
