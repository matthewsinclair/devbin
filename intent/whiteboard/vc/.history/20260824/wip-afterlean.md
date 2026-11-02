---
node: vc
name: Validation Claude
role: validation
session_id: a334a88e-3db4-4b55-8213-abc63a106cc8
heartbeat_at: 2026-08-24 17:08Z
status: paused
focus: "line drawn 2026-08-24: queue empty, boards cut to a resting state, watch-outs promoted to intent/llm/LESSONS.md. The next thread is hv's to set"
claims: []
---

# Validation Claude (vc)

## DOING

- Nothing in flight, nothing open in the tracker, no claim held.

## TODO

- **The next thread is hv's to set.** Read `hv/wip.md` for the standing directives before starting anything.
- **Read `intent/llm/LESSONS.md` and `usage-rules.md` at the start of real work**, not this board. That is now where the durable material lives.

## Watch-outs

Standing, and specific to what this node does. The general defect classes moved to `intent/llm/LESSONS.md` on 2026-08-24; the day's full pre-lean board is at `.history/20260824/wip-preleanboard.md`.

- **A restart brief is a snapshot, not a record. Verify its open-set against disk before planning from it.** Measured twice on this node: the first boot's brief listed a closed issue as open and omitted an open HIGH entirely, and the brief still in force at the 2026-08-24 fold named three issues open that were all closed. This node's own no-tallies rule is what predicts the class, and the brief is the document least likely to be re-read critically because it arrives first.
- **A write with no named reader is a queue, not a channel.** vc is the named reader of `hv/inbox.*`; an escalation is not delivered until vc has surfaced it to the human. The write always succeeds, which is exactly why nothing reports the gap.
- **Verify a peer's claim against disk, not against their report.** This node's whole role is that the instrument and the thing measured must not be the same session.

## Decisions

- hv's standing directives and ratified rulings live on `hv/wip.md`. Nothing is duplicated here -- a second copy of a ruling drifts, and this node has now watched that happen to an issue list twice.
