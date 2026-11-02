---
node: cc
name: Control Claude
role: control
session_id: 4c075a4d-ee8c-42b1-93c5-cadffef6e36b
heartbeat_at: 2026-08-25 09:33Z
status: active
focus: "booted after compact 2026-08-25. Tracker verified empty against disk, both inboxes empty, no claim held. Holding for hv to set the next thread"
claims: []
---

# Control Claude (cc)

**This board was cut by vc on 2026-08-24, on hv's explicit authority, not by cc.** The pre-lean board is archived verbatim at `.history/20260824/wip-preleanboard.md`. cc woke on 2026-08-25 and now writes its own header again; the `heartbeat_at` vc preserved untouched through the lean was `2026-08-10T22:19Z`, and that is the reading this node last took before the pause.

## DOING

- Nothing in flight, no claim held. **0029 and 0030 closed 2026-08-25** (`ced80f6`); 0031 and 0032 were vc's and are closed. No open issues in the tracker.

## TODO

- **Read `intent/llm/LESSONS.md` before starting anything.** It is where this board's watch-outs went.

## Watch-outs

- **This section is deliberately short now.** The ~90 entries that stood here were promoted to `intent/llm/LESSONS.md` (the general ones), `usage-rules.md` (the mechanical ones, already there) and the owning project (the downstream ones). They were on a live board for three weeks because nothing else owned them; a board is the wrong home, because boards get archived when the work closes and the lesson outlasts the work.
- **What was ERASED rather than promoted, and why**: entries restating a rule already in `usage-rules.md`; entries about bash 3.2 as a target, which issue 0022 reversed; and entries recording facts about Prolix, arca_cli, Riffle and Laksa, which belong at those projects and are summarised for hv in `intent/wip.md`.

## Decisions

- Design decisions D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`. Thread-level rulings are in the closed threads' own records. hv's standing rulings are on `hv/wip.md`.
- **2026-08-25's four hv rulings are NOT carried here.** They are in the resolutions of `intent/issues/CLOSED/0029` and `0030`, which is where a ruling about an issue belongs. A second copy on a board drifts, and a board is archived when its work closes while the issue is not.
