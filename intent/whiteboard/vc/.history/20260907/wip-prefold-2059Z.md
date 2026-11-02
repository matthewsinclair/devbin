---
node: vc
name: Validation Claude
role: validation
session_id: 0e264898-52d8-46db-8d2b-aa5edf99757e
heartbeat_at: 2026-09-07 16:39Z
status: active
focus: "ST0003 WP-02 IS BUILT, PUSHED AND CI-GREEN at 355e5e9 -- infra check reads authoritative DNS in four channels and finds real drift on the live estate. The 54 unclaimed were a v2 archive at an address v3 cannot name; deleted after proving all 54 rebuild from the store. I filed a high-severity Intent bug that was WRONG and intent-vc refuted it: git show on .canon/** restores a PROJECTION, not the store. NEXT: dc's finding 1 is hv's, and ST0003 still has no intent wp records"
claims: [ST0003, ST0005]
---

# Validation Claude (vc)

**Board cut 2026-09-07 16:39Z. Pre-fold at `.history/20260907/wip-prefold-1640Z.md`, 7383 b, cmp-verified against BOTH the working file and HEAD.** Ten forms promoted to `intent/llm/LESSONS.md` FIRST (338 -> 348), each verified by grep.

## DOING

- **ST0003 WP-02 IS DONE, PUSHED, CI GREEN ON FOUR JOBS.** `infra check` reads AUTHORITATIVE DNS in four channels -- ok / drift / COULD NOT MEASURE / blind. `mail: google` asserts NO MX value: intra-estate consistency replaces the deleted STANDARD, so the leg ships zero confidently-wrong assertions and **WP-03's dependency stays genuinely open rather than answered by accident**. At N=1 it reports NOT COMPARABLE instead of passing.
- **WP-03's OPEN DEPENDENCY IS UNCHANGED AND DELIBERATELY SO.** Where a vendor assertion lives such that it can go stale VISIBLY. Two candidates, neither chosen.
- **ST0003 HAS NO `intent wp` RECORDS.** WP-01..07 exist only as a table in `design.md`, so `intent todo` cannot see any of this. Put to hv twice, unanswered.

## TODO

**`intent/wip.md` is the authority for project work.** Only my own queue follows.

### With hv

- **dc's FINDING 1: `--profile <name>` does not resolve.** `--profile geodica` dies; only the literal path works. ~4 lines, backwards-compatible. **Held because a peer relaying an hv ask is not hv asking** -- exercised deliberately, and dc agreed the distinction was mine to enforce.
- **THE PRODINFRA RE-VENDOR.** WP-02 is not in the estate's vendored tree, so nothing there can reproduce my findings. dc refused to re-vendor mid-flight; correct. hv's call.
- **WHETHER TO TAG.** `v0.1.0` names `e22d9a3`, far behind, with no `infra` in it at all.
- **THE FLEET SWEEP.** hv's go.

### Mine, unsequenced

- **`0060`** a `die` at command-substitution depth 2 is swallowed; the class NOT fixed fleet-wide. **`0059`** BEHIND-you cannot fire against an install. **`0056`** census reads disk, never git.
- **THE GUARD RED-DRIVE HAS EXPIRED** -- four bodies replaced since the evidence was taken.

## Holds

- **`use` as a devbin builtin -- BLOCKED.** **Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START.** **Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md` and that was made TRUE at this fold (338 -> 348, verified by grep). Promote before cutting, never after.**

**THE ONE THAT COST THE AFTERNOON, and it is the mirror of a rule I already had and was applying to everyone else: A POSITIVE RESULT IS EVIDENCE ONLY IF IT COULD HAVE COME OUT DIFFERENTLY.** I filed a high-severity Intent bug on evidence that could not discriminate between two hypotheses, having built the test on a premise **I had falsified myself two hours earlier** by attaching 24 files to the store. intent-vc refuted it with one query. `git show <rev>:intent/.canon/**` restores a PROJECTION; `organise` reads the sqlite store, which still held everything.

**A GUARD THAT SHARES A FAILURE DIRECTION WITH ITS BUG CANNOT FIRE.** My backtick arm grepped the OUTPUT for a character that an unquoted heredoc CONSUMES BY EXECUTION. Unfalsifiable. And the mutation I used to prove it left `mail dmarc` running for 1h42m with eight processes hung behind it -- found only because hv asked what the shells were.

## Decisions

### 2026-09-07, and the ruling held twice under pressure

**NOTHING MACHINE- OR ESTATE-SPECIFIC BELONGS IN A TOOL OTHER ESTATES VENDOR.** Applied to the install prefix, to `docs/infrastructure.md`, and now to `mail: google` -- which asserts no vendor MX value precisely because the artefact that could carry one honestly does not exist yet.

**COMPLETED THREADS ARE NOT REALISED ON DISK**, per `intent/.intentfiles` on hv's 2026-08-26 order. `intent/st/COMPLETED/` was a v2 archive at an address the v3 model cannot name -- deleted at `355e5e9` after proving all 54 files rebuild from the store, `design.md` byte-identical by sha with no disk copy anywhere.

**D1-D25 in `intent/st/COMPLETED/ST0001/design.md` -- NOW STORE-ONLY, read via `intent st show ST0001`. D26-D34 in `intent/st/ST0005/design.md`.**

### Standing

- hv's standing directives live on `hv/wip.md`; nothing duplicated here. **I hold that pen under hv's explicit grant.**
- **A peer's recommendation is never authorisation.** Exercised three times on 2026-09-07, most recently on dc's finding 1.
- **`bin/devbin` is the invocation everywhere.** **`devbin_version` stays a hand-written literal.**
- **NEVER `git add -A` in the same command as the commit** -- it re-added a `.intentfiles` line I had correctly removed, unseen, at `f1b2822`.
