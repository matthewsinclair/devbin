---
node: vc
name: Validation Claude
role: validation
session_id: e797f709-1a39-47e8-bb6b-74882ebcb428
heartbeat_at: 2026-09-09 08:09Z
status: active
focus: "Booted. Pickup done, 3 commits UNPUSHED at both remotes (upstream and local both 6e70788, HEAD 65493e8). Syncing with devbin-cc and assembling every open hv item across the board for hv review. WP-03 `infra init` is queued and NOT started -- hv to sequence."
claims: [ST0003]
---

# Validation Claude (vc)

**Board cut 2026-09-08 21:22Z. Pre-fold at `.history/20260908/wip-prefold-2124Z.md`, 4873 b, cmp-verified against BOTH the working file and HEAD.** Five forms promoted to `intent/llm/LESSONS.md` before the cut, each verified by grep. **The day is in the commits and the lessons; this board keeps only what is still open.**

## DOING

Nothing. Paused at hv's word, 2026-09-08.

## TODO

**`intent/wip.md` is the authority and it POINTS rather than restates.** It carries what `init` must and must not do. Only my own queue follows.

### First thing tomorrow

- **WP-03, `infra init`.** Unblocked -- AC-3.5 is ruled. **The two ways it can manufacture the false green this thread exists to catch, and both need an arm before anything else is built:** a value inferred from the estate must never be written OUTSIDE `unreviewed:`, and a domain that could not be read must land as an explicit gap rather than being omitted, because **an absent domain is invisible to `check` for ever after**.

### hv's, not mine

- **dc's FINDING 1: `--profile <name>` does not resolve.** ~4 lines. Held: a peer relaying an hv ask is not hv asking.
- **THE TAG.** `v0.1.0` names `e22d9a3`, **97 commits behind** the CI-green HEAD. Nothing shipped since is tagged, and the fleet runs from the install tree rather than a release, so the tag currently describes nothing anyone uses.
- **ST0006** is in Triage. Starting it is hv's.
- **WP-04 `infra apply` WRITES TO LIVE DNS AND FLY.** Building is ordinary; RUNNING it against any estate is under hv's standing rule.

### Mine, unsequenced

- **`0060`** a `die` at command-substitution depth 2 is swallowed; class NOT fixed fleet-wide -- and I relied on that exact mechanism deliberately in the dmarc directory walk, where the refusal is CAUGHT and counted rather than lost. **`0059`** BEHIND-you cannot fire against an install: hv hit this live today, twice, as `Already up to date` while 17 commits behind. **`0056`** census reads disk, never git -- hit today as two estates reading `level` while carrying uncommitted vendors.
- **THE GUARD RED-DRIVE HAS EXPIRED**, measured with git in the tree `pre-commit.intent --where` resolves: three of four guards moved since 2026-08-28, plus the RUNNER. The header guard and the roster have not. `intent/restart.md` still asserts PROVEN TO CATCH on that drive.

## Holds

- **`use` as a devbin builtin -- BLOCKED.** **Checked at this fold: not lifted.** Utilz moved on their own `use` today; not designed around here.
- **`--ivault` -- EXPLICITLY DO NOT START.** **Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`, made true at this fold. Promote before cutting, never after.** Nothing is restated here.

**The one that explains today, in one line: I twice reported a measurement of the wrong artefact -- validating devbin's SOURCE and calling it `devbin infra works`, when hv runs the VENDORED copy -- and my own board had carried the re-vendor as an open item all day.** The second time, the cause was one layer further up again and the estate was innocent both times.

## Decisions

**D1-D25 are STORE-ONLY since `355e5e9`.** Read them with `intent st show ST0001`. **D26-D34 in ST0005's design, now dehydrated -- `intent st show ST0005`.** ST0003's rulings, including AC-3.5 and the measurement behind it, are in `intent/st/ST0003/design.md`.

### Standing

- hv's standing directives live on `hv/wip.md`. **I hold that pen under hv's explicit grant.**
- **A peer's recommendation is never authorisation.** Exercised again today: intent/vc's report was verified before acting, and their open question was settled by measuring the fleet rather than by taking their suggestion.
- **NEVER `git add -A` in the same command as the commit.** And, added today: **scope a repair at least as narrowly as the check that triggered it** -- a reset with no pathspec discarded two peers' staged work.
- **`bin/devbin` is the invocation everywhere. `devbin_version` stays a hand-written literal.**
