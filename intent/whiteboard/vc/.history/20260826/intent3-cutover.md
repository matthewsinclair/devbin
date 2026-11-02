# 2026-08-26 PM -- the Intent3 cutover, as devbin/vc ran it

Written 2026-08-26 11:57Z at `75bb005`, folding the afternoon out of the live board. The morning's board is at [`wip.md`](wip.md) (27282 bytes); this is what happened after it.

**hv put this node at intent/vc's disposal for the fleet Intent3 migration, with intent/vc holding the pen as BOSS-VC over intent-{dc,ic,cc}.** Devbin's own pause was not lifted -- no thread opened, nothing claimed. Everything below is either a read-only measurement of someone else's estate, or a cleared write to this one.

## Where it stopped

**hv called a fleet-wide STOP AND HOLD**, relayed verbatim through devbin/cc. It supersedes the pen. **hv lifts it, not intent/vc and not this node.**

Devbin's state at the stop, committed at `75bb005` so it is recorded rather than floating:

| | |
| --- | --- |
| declared version | **2.19.0** (was 2.18.0 at session start) -- hop 1 applied and COMPLETE |
| `intent3` | **never completed here.** No `intent/.canon/`, no `intent/events.jsonl`, no flat `intent/st/ST####/` |
| hop 3 (`claude upgrade --apply`) | **never ran.** `AGENTS.md` is v2-generated; `CLAUDE.md` untouched |
| `CLAUDE.md` user block | INTACT, 914 bytes, sha256 `4fe8e34c93359b03e0fa076c6dbce2ed52998ca1f4fb6fcbee2956e6558c7ef5` |
| rollback point | `.backup/backup-20260826-124753` (carries `CLAUDE.md` + `intent/`) |
| Arca x3 | UNTOUCHED, all clean, no hops |
| gate | `bin/devbin check all` -- all check options passed |

**Hop 2 was refused by Intent's own currency guard**, not by anything wrong here: *"1 non-test file(s) under native/rust changed since 88b1c92ce94f -- this binary is behind HEAD"*. Waited on rather than worked around; falling through to the raw binary would have answered about a tree we are not on. hv's stop arrived before dc's rebuild did.

## What this node actually contributed

**1. Devbin's own migration blocker, found and fixed.** `intent3 upgrade` refused this tree at hop 2 with `sqlite: UNIQUE constraint failed: tests.thread_id, tests.id`. ST0001 declared **436 acceptance tests, 425 distinct** -- `AT-04.12`..`AT-04.22` each declared TWICE, and both sides real, distinct tests in different bats files covering different criteria. Cause is legible in the file: a later pass appended tests for AC-04.12/13/14 and restarted numbering at 04.12 instead of continuing past the high-water mark of 04.30. Second occurrences renumbered to `AT-04.31`..`AT-04.41`. Committed alone at `19579c3`, ruled by intent/vc, proven on a sandbox (hop 2 rc 0, *"migrated: 2 thread(s), 34 issue(s), 69 file(s) written"*) **before** the commit claimed it.

**2. The `CLAUDE.md` finding, and it is worse than the baseline recorded.** devbin/cc established that `claude upgrade --apply` rewrites `CLAUDE.md` on the two estates carrying the generated footer (Devbin and Riffle) and drops the user block. Run here red-first, with a sentinel INSIDE the markers and a second OUTSIDE:

    INSIDE-block sentinel   survived: 0
    OUTSIDE-block sentinel  survived: 0
    block sha after hop 3:  12bad4ea13449501
    (modified was 5cb2c84717eeb7e8; pristine 4fe8e34c93359b03)

**The block left behind is neither the estate's nor empty -- it is the TEMPLATE's own well-formed default block, author line and all.** There is no gap, no truncation, no empty markers. A reviewer scanning the file post-migration sees a normal user block and moves on. **Only a full-length before/after digest can see it.** intent/vc made before-and-after digest verification the fleet standard on the strength of this.

**3. The instrument that was withdrawn, and why that is the more useful outcome.** A fleet-wide AT-uniqueness sweep predicted 16 failing threads across 6 projects. intent/vc withdrew it as a gate after two false positives, and it was wrong in **three unrelated ways** -- cross-file summing, declaration-vs-citation, and a transient scratch file. Its one surviving use: after hop 2 refuses, it hints where else in that thread to look. **Hop 2's own refusal is the instrument that cannot be wrong.** A tool wrong in three unrelated ways is not one bug away from working.

## Errors this node made, all self-reported

Four, and the pattern across them is one thing.

- **An n=2 guard-gap claim, refuted by devbin/cc.** Matched Intent's commit SUBJECT line and inferred its mechanism. The body said the inverse: their `render.rs` has four legitimate writers, so it was a shared-source collision, not an ownership violation. An ownership guard closes devbin's instance and is a category error on theirs. Retracted to BOSS-VC before it was acted on.
- **Intent ST0056 "14 dupes" -- a false positive.** `acceptance.md` alone is 139/139 clean. The sweep grepped the thread **directory** and summed in `rows.txt`, a transient scratch file that had been deleted by the time it was inspected -- it vanished between two of this node's own commands. **A sweep's UNIT must be the artefact, not the directory that holds it.** intent/vc had proposed a different cause (prose bullets); re-deriving rather than accepting it is what found the real one, and BOSS took the correction.
- **The digest, relayed wrong by one character.** Measured correctly as `...b03e0fa...`, transcribed to two peers as `...b03a0fa...`. **The corruption sits at character 17 -- the first one past where both nodes truncate their tables.** Every short-form comparison made all day matched and always would have. Confirmed corrected by three independent computations across two nodes.
- **Committed a peer's file this morning** (`b9d9d7d` carried `cc/inbox.vc.md`). Not a glob that over-reached: the path was hand-typed into `git commit --only` because `git status` showed it dirty. Composed with cc's un-re-read inbox cut to destroy an entry that existed in no commit at any point.

## Two things that came back from peers and are worth more than what this node sent

**devbin/cc's detection, which needs no machinery and covers every instance above:**

    git show --stat HEAD    # compare the file count against the length of your pathspec

It tests neither ownership nor care nor intent, but **what the command DID against what it was TOLD to do**. Both of this session's commits since have been checked with it.

**intent/vc's pair-sha ruling, generalised:** a value read at the time of the act, in the same command as the act, is trustworthy; a value that travels through a message from one node to another has a transcription hop in it that nothing checks. That is the digest error stated as a rule, and it applies to digests exactly as it applies to shas.

## Queued, cleared but not run

All of it waits on hv, not on intent/vc.

- **Devbin hops 2 and 3**, then restore + hash-verify, `verify-canonical.sh` to 0 failed, one commit carrying the pair sha read from `intent3 --version` in the same invocation as hop 2.
- **Arca x3**, ruled hv's grant, deconflicted with ic (they had not started). Sequencing from BOSS: `arca_notionex` (0 exposure) first, then `arca_cli` (9) and `arca_config` (3) **only** on a pair built with ic's ingest fix -- those two carry hand-written `satisfied: yes (...)` sign-offs the current ingest inverts.
- **The Cellar positive control**: a commit through devbin's gate with `INTENT_HOME` resolved to the unlinked brew keg (guards run), and again pointed at a directory with no `lib/templates/` (the `NO guard ran` line). Both lines verbatim. Not started -- it drives a live write.

## Fleet facts measured from outside, still true at the stop

- `intent --version` was **2.19.0**, `INTENT_HOME` = Intentv2, and **three** `intent` on PATH (`~/.local/bin`, `~/bin`, both symlinks to `Intentv2/bin/intent`). The machine-wide flip is Intent's, via Molt, and is not this estate's to touch.
- The brew tap `matthewsinclair/intent` is tapped and **deliberately empty** -- one commit, `9aabafa` *"The tap, and why it is deliberately empty"*, README only. Its README commits the formula to ship two binaries, `intent` + `intentd`, macOS arm64 first. The release machinery is **not** in `.github/` (three workflows, all CI, no CD); it is `Intent/bin/.devbin/cmd/macos`, verbs `prepare` -> `formula` -> `publish`, dc's lane. `publish` is hv's alone.
- The dev/brew swap is **`int local use dev|prod`** in `Intent/bin/.devbin/cmd/local`. A name grep of `native/` was the right instrument aimed at the wrong tree.
- **21 real Intent projects** on this machine at any depth once `.backup/`, `deps/`, `_build/`, `.worktrees/` and `tmp/corpus/` copies are excluded. intent/vc drove the same predicate and got the same list; their earlier sixteen was a depth-limited walk.
