# Whiteboard -- Devbin

Live cross-session coordination for this project, under Protocol 3.0. Every file has exactly one writer; that is what keeps the board contention-free.

This file is the project's **node roster**. The protocol itself lives in the `in-whiteboard` skill and is not restated here.

## The roster

| Node | Name              | Role       | Driven by | Owns                                                                                                                                          |
| ---- | ----------------- | ---------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `cc` | Control Claude    | control    | a session | the framework, its tests, its docs, and the migrations                                                                                        |
| `vc` | Validation Claude | validation | a session | independent verification of landed and claimed work; the coordination record; surfacing `hv/inbox.*`                                          |
| `dc` | DevX Claude       | devx       | a session | the dev-x and build environment, in hv's framing of `dc` for Intent (2026-08-15); where its line with `cc` falls in this repo is hv's to draw |
| `hv` | Hypervisor        | hypervisor | the human | scope, sequencing, release policy, and every ratified decision                                                                                |

**`hv/wip.md` carries the standing directives.** Read it at pickup before starting anything. Until 2026-08-24 those rulings lived on whichever agent board happened to be in the room when hv made them, which made a ruling's home an accident of timing.

`hv` is scaffolded but human-driven: no session loop, `session_id: none`, heartbeat advisory. **hv reads nothing on this board unprompted. The named reader of `hv/inbox.*` is `vc`, and whiteboard matter reaches the human only by vc addressing it to them** (hv's ruling, 2026-08-24). An escalation is still written durably to `hv/inbox.<you>.md` -- the write is the record and vc's surfacing is the delivery, so a write there is not delivered until vc has surfaced it.

## Reading this board

- `<node>/wip.md` -- that node's live board: what is in flight, what is queued, the holds, the durable watch-outs, and the cross-node decisions. **Since 2026-09-16 it is rendered from the store**: change it with `intent wb`, never by hand, and `intent doctor` reports a hand edit as skew.
- `<node>/board.json` -- the committed record of that board, which the store is carried in.
- `<node>/.history/YYYYMMDD/` -- the archive of the hand-authored era, and the pre-migration snapshots of 2026-09-16. Append-only, never reloaded at pickup. An item archived since then stays in the store as a state and is listed by `intent wb show <node>`.

`intent/wip.md` at the project root is the **post-session snapshot**; this directory is the **live channel**. When they disagree, the board is more recent and the snapshot is more considered.

## Fold vocabulary

- **localfold** -- tidy this node before a compact: promote settled decisions to their durable homes, `archive` what is finished with, and `clear` what has been handled. **It does not `release`**: a compact is not the end of a session, so status stays `active`, and `release` belongs to the end of a session.
- **globalfold** -- the project-wide snapshot at end of day: `intent/wip.md`, `intent/restart.md`, and the shared tracking docs.

A node only ever touches its own directory. That single-owner rule is what makes archiving collision-free.

## Where the watch-outs went

They are in **`intent/llm/LESSONS.md`**, and a board's `## Watch-outs` section is now short by design.

Until 2026-08-24 `cc/wip.md` carried about ninety of them and this file explained, at length, why that was deliberate. The explanation was half right. Each entry genuinely is a defect class this project produced at least once, written in the general form because the specific one never recurs -- and that is exactly why a live board is the wrong home for them. **Watch-outs are standing and boards are not**: a board is archived when its work closes, so the most durable content in the project was sitting in the least durable place, on a node that had been paused for a fortnight, growing until nobody read it.

What each board keeps is the handful of cautions specific to what that node does. Everything general is promoted. Mechanical DO / NEVER rules were already in `usage-rules.md` and are not restated anywhere.
