# Addendum: what the loss record beside this file cannot contain -- devbin, 2026-09-16 09:01Z

Written by vc beside `wb-migration-uncarried.md`, which cannot be corrected in place because `.history/` is append-only.

That record is accurate as far as it goes: it is migrate's own stderr, verbatim. **What it cannot contain is loss that migrate never reported, because nothing was dropped -- it was absorbed into the wrong shape.** Classes A, B and C were found by devbin-dc on 2026-09-16; D was found by vc. **Every count below was measured by parsing the pre-migration snapshots beside this file, not by reading the rendered boards**, because the first counts of A to D were read by eye and two of them were wrong.

## A. Six sub-headings absorbed as items carrying literal `###` text

- `cc` todo: `### Parked by hv, not dropped (hv, 2026-08-28) -- carried unverified`
- `vc` todo: `### Filed today`, `### Owed to LESSONS`, `### hv's, not mine`, `### Mine, unsequenced`
- `vc` decisions: `### Standing`

**The groups recorded whose work each item was, and they now survive only as position.** `seq` carries no group, so the first `archive` or `add` that moves an item makes the grouping unrecoverable. This has the shortest fuse of anything here.

## B. Ten prose blocks promoted to items -- seven of them framing

Distinct from the BOARD lead paragraphs the record beside this file lists, which were reported and dropped: these were unreported and kept, as items of the section's kind.

Framing -- a lead, a caption or a trailer that now reads as an item:

- `hv` todo: "An index. `intent/wip.md` carries the detail and is the authority"
- `hv` decisions: "Ratified 2026-08-24, in session, listed because the record has to outlive the session that made it" -- the caption of the table in D
- `hv` decisions: "Earlier rulings are in the closed threads' own records" -- the table's trailer
- `cc` watch-outs: "General forms live in `intent/llm/LESSONS.md`"
- `vc` todo: "`intent/wip.md` is the authority and it POINTS rather than restates"
- `vc` todo: "cc handed both decisions to me explicitly and then released" -- the lead of the `### Owed to LESSONS` group
- `vc` watch-outs: "General forms live in `intent/llm/LESSONS.md`, made true at this fold"

Content, and correct as an item: `vc` doing "Nothing. Paused at hv's word"; `vc` watch-out "A READING WITH A SHELF LIFE"; `vc` decision "D1-D25 are STORE-ONLY", whose pointer is stale for its own reason.

**The split between framing and content is judgement, not measurement.** The count of ten is measured; the seven is vc's reading of it. devbin-dc's first reading found four.

## C. A section synthesized, and a section moved

hv's board now renders `## Holds` / `_(none)_`, a section it never had, because the renderer emits every kind. **`## Standing directives` moved from the first section to the fourth**, and the roster tells every peer to read it at pickup.

## D. A six-row table flattened into one item

hv's Decisions held the six rulings ratified on 2026-08-24 (0014, 0015, 0018, 0019, 0021, 0024) as a table. It is one item whose text is the whole table, rendered as a bullet.

## Corrections to the record beside this file, and to `5f0460e`

- **Eighteen non-markdown `.history/` files did not carry, not nineteen.** From migrate's stderr: `cc` 9, `vc` 9. Nineteen was vc's arithmetic during the rehearsal and was never a measurement, and it is in `5f0460e`'s message.
- **All eighteen are still on disk and still tracked.** migrate declined to ingest them; it did not remove them. They include `cc/.history/20260914/0056-census-column-work.patch` and `0062-message-half-tests.patch`, the live work of two held issues. A reader counting `uncarried:` lines would read eighteen losses where there are none. (devbin-dc, checked here.)
- **`5f0460e` says "one silent loss".** There are the four classes above as well.

## What editing the model can and cannot reach

`board.json` items are `{node, kind, seq, text, state, recorded_at}`, and there is no field for a lead paragraph, a sub-heading, a group or a table. **Hand-editing `board.json` cannot restore A, B, C or D** -- it can only rewrite item text. Whether to restore that structure or conform to the model is hv's call, put to hv on 2026-09-16.

The whiteboard's writes are also absent from `event_log`: 298 events across 25 kinds of operation, and not one whiteboard op (devbin-dc, checked here). So the store cannot say who registered, migrated or wrote anything on a board.
