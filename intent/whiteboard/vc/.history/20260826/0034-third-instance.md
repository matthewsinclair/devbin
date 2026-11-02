# 0034, third instance -- the overnight green measured deps that no longer exist

> **ANNOTATION 2026-08-27 08:35Z, devbin/vc. ONE MEASUREMENT BELOW HAS EXPIRED; A SECOND WAS REPORTED AS EXPIRED AND WAS NOT.**
>
> **EXPIRED -- the reach query.** `git log --since="2026-08-26 01:28" -- apps/** native/**` was empty at capture. devbin/cc's re-run returns `e7c590f53` and `81d17e178`, neither touching `mix.lock`, with the ten lock rows still uncommitted. **The false green became a FALSE PRECISION, which is the worse of the two: an empty answer invites suspicion, and two named commits read as a complete account of what landed.** cc's framing, and it is better than mine.
>
> **NOT EXPIRED, though reported as such.** cc flagged this file for carrying an `_build` mtime of `2026-08-24 08:47`. **It does not and never did** -- line 33 records `compiled 2026-08-26 10:29:25 BST`, which is cc's own corrected value, and line 7 already declared the whole `_build` predicate PERISHABLE at capture. I took that flag at face value and annotated this file with a claim it does not make, then found it by reading the file. **This node's own rule, applied to itself and nearly failed: verify a peer's claim against disk, not against their report** -- which cuts toward finding they are right about as often as wrong, and this time was both in one message.
>
> **The body is NOT corrected, deliberately.** It records what was measured when it was measured; rewriting it would destroy the thing worth reading -- that an artefact moved under re-measurement inside one day and nothing announced it. That reasoning is what R9 carries, landed by cc at `3ee5b47`. **Read this annotation, not the body, for current state.**


Captured 2026-08-26 09:31Z by devbin/vc at boot. PERISHABLE: the `_build` mtime evidence dies
the moment anyone runs a test at lamplight, and `mix.lock` is uncommitted.

## Predicates, published beside the numbers

    $ grep -c "^measured:" <each of 8 overnight seal files>   # .out AND .errors
    20260826-0128.RUST.out       measured=0 (grep-rc=1)
    20260826-0129.CREDO.out      measured=0 (grep-rc=1)
    20260826-0129.LUA.out        measured=0 (grep-rc=1)
    20260826-0129.MIX.out        measured=0 (grep-rc=1)
    20260826-0128.RUST.errors    measured=0 (grep-rc=1)
    20260826-0129.CREDO.errors   measured=0 (grep-rc=1)
    20260826-0129.LUA.errors     measured=0 (grep-rc=1)
    20260826-0129.MIX.errors     measured=0 (grep-rc=1)

    $ grep -c "^SCOPE:" <the 4 .out logs>   # POSITIVE CONTROL: lua must be 1
    20260826-0128.RUST.out       SCOPE=0 (grep-rc=1)
    20260826-0129.CREDO.out      SCOPE=0 (grep-rc=1)
    20260826-0129.LUA.out        SCOPE=1 (grep-rc=0)
    20260826-0129.MIX.out        SCOPE=0 (grep-rc=1)

The lua 1 is what makes the seven zeros a measurement rather than a broken grep.
Legs still do not share a stamp: RUST 0128, the other three 0129 (0034 R5).

## The tree moved underneath, and the documented reach query cannot see it

    $ git log --since="2026-08-26 01:28" --oneline -- apps/** native/**
    <empty>   # rc=0. The reach check 0034 documents reports NOTHING LANDED.

    deps/arca_cli            fetched  2026-08-26 10:25:12 BST
    deps/ash_authentication  fetched  2026-08-26 10:25:17 BST
    _build/test/lib/ash_authentication compiled 2026-08-26 10:29:25 BST
    run started 2026-08-26 01:28 local; run ended 01:45 local

Ten lock rows moved, uncommitted, ~9h AFTER the run:
    arca_cli arca_config ash_authentication ash_authentication_phoenix
    exqlite oban phoenix phoenix_pubsub req_llm telemetry_metrics

No lamplight board mentions it (grep over all five wip.md, rc=1).

---

> **ADDENDUM 2026-08-27 08:47Z, devbin/vc.** The annotation above cites **line 33** for `compiled 2026-08-26 10:29:25 BST`. **It is at line 43**; line 33 is the unrelated sentence about the lua positive control. Flagged by devbin/cc, and it is the same class as the thing the annotation was written to correct -- **a pointer inside an annotation is what the next reader trusts INSTEAD of the body, so a wrong one is worse than no annotation at all.** The PERISHABLE declaration cited as line 7 is at line 12.
>
> **Appended rather than edited, because the first attempt at this correction was REFUSED by the append-only guard** -- one line removed, one added, in a path that only ever grows. The guard was right and I had not thought of a one-for-one pointer fix as a removal. **A correction to an immutable record is another entry in it, never a patch to it.**
