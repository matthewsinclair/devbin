---
node: vc
name: Validation Claude
role: validation
session_id: 0e264898-52d8-46db-8d2b-aa5edf99757e
heartbeat_at: 2026-09-08 14:37Z
status: active
focus: "THE HOLD IS LIFTED and the day went to ST0003 delivery. ST0005 closed on its own gate. ST0003 has a contract where it had none: 7 wp records, 44 criteria, 32 satisfied, 1 withdrawn. WP-05 gained container and directory support after MEASURING that not one of 17 real DMARC reports is bare XML; WP-06 gained the universal sender invariant. Four defects found by running against a live estate rather than fixtures. devbin#0061 filed, fixed and closed from intent/vc's report inside one session. FLEET SWEPT TWICE and committed: 15 estates at one seam 086fce6, Intentv2 frozen and named. hv pushed; both remotes level; CI in progress at the time of writing and NOT yet read"
claims: [ST0003]
---

# Validation Claude (vc)

**Board cut 2026-09-07 20:59Z, aggressively. Pre-fold at `.history/20260907/wip-prefold-2059Z.md`, 5274 b, cmp-verified against BOTH the working file and HEAD.** Twelve forms promoted to `intent/llm/LESSONS.md` across the day's three folds (306 -> 352), each verified by grep. **The day's narrative is in the commits and the lessons; this board keeps only what is still open.**

## DOING

Nothing in flight. Today's work is committed at `54deb19` and `894b41d`.

## TODO

**`intent/wip.md` is the authority for project work, and as of 2026-09-08 it POINTS rather than restates -- ask `intent todo` what is built and `intent ac status ST0003` whether it can close.** Only my own queue follows.

### hv's, not mine

**FOUR OF THE FIVE ITEMS THIS SECTION CARRIED THIS MORNING ARE DONE**, and they are deleted rather than ticked -- done work does not live on a board. The push, the fleet sweep, the Prodinfra re-vendor and the install-tree publish all landed 2026-09-08. What is left:

- **dc's FINDING 1: `--profile <name>` does not resolve.** Only a literal path works. ~4 lines, backwards-compatible. Held because a peer relaying an hv ask is not hv asking, and that has not changed.
- **THE TAG.** `v0.1.0` names `e22d9a3`, with no `infra` in it at all. Now further behind than it has ever been.
- **WP-04 `infra apply` WRITES TO LIVE DNS AND FLY.** Building it is ordinary work; RUNNING it against any estate sits under hv's standing rule on deploy-affecting changes.

### Mine, unsequenced

- **THE 14 UNSATISFIED ACs ARE THE MAP OF WHAT IS LEFT**, and they replace the prose queue this section used to carry. `intent ac status ST0003` is the count; `intent/st/ST0003/acceptance.md` is the text.
- **WP-03 IS BLOCKED ON AC-3.5, WHICH IS NOW A RECORD RATHER THAN A NOTE:** where a vendor assertion can live such that it goes stale VISIBLY. Two candidates, neither chosen. WP-02 shipped without needing it, which is what keeps it genuinely undecided.
- **`0060`** a `die` at command-substitution depth 2 is swallowed; class NOT fixed fleet-wide. **`0059`** BEHIND-you cannot fire against an install. **`0056`** census reads disk, never git. All three are one family: a check that cannot go red.
- **THE GUARD RED-DRIVE HAS EXPIRED, and the size of it is measured rather than guessed** -- git in the tree `pre-commit.intent --where` actually resolves. Three of four guards moved since 2026-08-28 (clock 08-31, canon-ignore and append-only 08-30) plus the RUNNER (09-05). The header guard and the roster have not, so one arm still stands and no guard has appeared unexercised. `intent/restart.md` still asserts PROVEN TO CATCH on that drive.

## Holds

- **`use` as a devbin builtin -- BLOCKED.** **Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START.** **Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`, made true at every fold today. Promote before cutting, never after.** Nothing is restated here.

**The one that explains my day, in one line: I applied "confirm the instrument could have produced the opposite" to everyone's work except my own confirming evidence, and filed a wrong high-severity Intent bug on it.** intent-vc refuted it with one query. The mirror is now in LESSONS.

## Decisions

**D1-D25 are STORE-ONLY since `355e5e9`** -- `intent/st/COMPLETED/` was a v2 archive at an address v3 cannot name, deleted after proving all 54 files rebuild from the store. Read them with `intent st show ST0001`. **D26-D34 in `intent/st/ST0005/design.md`.** Not restated here.

### Standing

- hv's standing directives live on `hv/wip.md`. **I hold that pen under hv's explicit grant.**
- **A peer's recommendation is never authorisation.** Exercised three times on 2026-09-07.
- **NEVER `git add -A` in the same command as the commit.** It re-added a `.intentfiles` line I had correctly removed, unseen, at `f1b2822`.
- **`bin/devbin` is the invocation everywhere. `devbin_version` stays a hand-written literal.**
