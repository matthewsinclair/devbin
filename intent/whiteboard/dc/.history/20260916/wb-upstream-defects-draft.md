# Whiteboard store migration: defects for Intent -- DRAFT, devbin, 2026-09-16 09:14Z

**Drafted by devbin-dc; reviewed by devbin-vc, whose corrections are applied here. hv ruled on 2026-09-16 that it goes to Intent through intent-vc, sent by devbin-vc and citing the commit that carries this file.**

Build: Intent 3.0.3, `d24487079`. Migration: devbin `5f0460e`. The measurement records are beside the boards and are not restated here:

- `vc/.history/20260916/wb-migration-uncarried.md` -- migrate's own stderr, verbatim.
- `vc/.history/20260916/wb-migration-uncarried-addendum.md` -- the silent classes A to D, counted from the pre-migration snapshots.
- `dc/.history/20260916/carry-map.sh` -- a second, independent instrument over the same snapshots. For every non-bullet line of each pre-migration board it reports where that line's text landed in the rendered board, and how many lines matched; it reads 44 lines. **It has been watched red twice**: vc deleted `## Watch-outs` from a copy of hv's rendered board and exactly that row flipped to `ABSENT`; dc appended an empty sub-heading to a copy of cc's snapshot and it refused with rc 1, naming the line. That refusal is a guard inside the script, so it travels with the instrument, because an empty search string matches every line and is the one false green this instrument has actually produced. Rendered line numbers go stale at the next write to a board; the classes do not.

**Provenance is on every defect, because two nodes produced this and not every claim was re-measured by both.** `dc`: measured in the dc session. `vc`: reported by vc and NOT re-measured by dc. `both`: measured by one and confirmed by the other.

## Summary

| ID  | Defect                                                                                       | Where        | Proposed | Source |
| --- | -------------------------------------------------------------------------------------------- | ------------ | -------- | ------ |
| L   | doctor names remedies that cannot clear what it reports, and the commit gate refuses on them | doctor       | high     | vc     |
| H   | `register` with arguments has the node's own board in hand and never reads its header        | wb register  | high     | both   |
| A   | sub-headings become items carrying a literal `###`                                           | wb migrate   | medium   | both   |
| B   | section prose becomes items, unreported                                                      | wb migrate   | medium   | both   |
| D   | a table becomes one multi-line item                                                          | wb migrate   | medium   | both   |
| M   | the launcher's remedy invites `register` with arguments and shows neither value              | claude start | medium   | vc     |
| J   | whiteboard writes are absent from `event_log`                                                | store        | medium   | both   |
| I   | no verb corrects a node's name or role                                                       | wb register  | medium   | both   |
| E   | a section heading's qualifier is dropped, unreported                                         | wb migrate   | low      | both   |
| C   | the render adds a section the source never had, and reorders sections                        | wb render    | low      | both   |
| F   | board lead paragraphs are dropped, and migrate still exits 0                                 | wb migrate   | low      | both   |
| G   | `uncarried:` reads the same for a file left in place as for a loss                           | wb migrate   | low      | both   |
| N   | `sync --to-store` reports nothing overwritten while it changes a node row                    | sync         | low      | vc     |

Severities are proposals. Intent sets them. **There is no K**: the first draft's K claimed a destructive doctor remedy that does not exist on this build, and what is true of it is now the second instance of L. The letters are kept stable so that messages citing them still point at the same defects.

## The model gap under A, B, D, E and F

`wb_item` is `id, node, kind, seq, text, state, archived_at, recorded_at, authored_at, updated_at` (dc, read from the table's schema rather than from one board's JSON). **There is no field for a board's lead paragraph, a section's lead paragraph, a sub-heading, a group of items, a table, or a heading's qualifier, and the section a line renders under is derived from `kind`.** So no migrator can carry them, and no edit to `board.json` or to the store can restore them.

Each carry defect below is where the migrator met that gap and did something other than say so: **A, B and D coerce the content into items; E and F drop it; only F reports it.** Whether the answer is a richer model or a louder migrator is the question for Intent, and it is the same question as devbin's RESTORE-versus-CONFORM, which hv ruled on 2026-09-16: CONFORM.

## Carry -- `intent wb migrate`

### A -- sub-headings become items carrying a literal `###` (both)

Six, listed in the addendum; carry-map reads the same six (`SUBHEAD -> bullet 6`). Not reported, because nothing was dropped. **The groups recorded whose work each item was, and they now survive only as order within a kind**: `seq` carries no group, so the first `archive` or `add` that moves an item makes the grouping unrecoverable.

A fix must carry the group, or report the sub-heading as uncarried. It must not turn the sub-heading into an item.

### B -- section prose becomes items, unreported (both)

Ten, listed in the addendum; carry-map reads the same ten (`SECTIONPROSE -> bullet 10`). **The same kind of paragraph ABOVE the first section is reported and dropped (F); inside a section it is kept as the wrong kind of thing and nothing is said.** vc judges seven of the ten to be framing; that split is a reading, and the ten is the measurement.

What the counts now say: vc's DOING held one sentence, "Nothing. Paused at hv's word, 2026-09-09.", and the model now counts it as one item in flight when the truth is none. The addendum classes that sentence as content that is correct as an item; vc has since agreed it is not, because of the count.

A fix must give section prose the same treatment as a board lead -- a field that holds it, or a report -- and never count a sentence as an item.

### D -- a table becomes one multi-line item (both)

hv's six rulings of 2026-08-24 were a table. They are now decision `seq 2`: **one item whose text is eight lines**, rendered as a bullet whose first line is the header row, with the other seven as continuation lines, so the table no longer renders. Its caption and its trailer became decision items `seq 1` and `seq 3`. Found by vc; confirmed by dc in the store, `jq` over `hv/board.json`, not only in the rendered view.

A fix must not put multi-line structured content into a one-line list item. If it cannot carry the structure, it must report it.

### E -- a section heading's qualifier is dropped, unreported (both)

hv's `## TODO -- one upstream, the rest downstream, none of it devbin's own code` renders as `## TODO`. carry-map reads that heading `ABSENT` and every other section heading carried (`SECTIONHEAD -> heading 14`, `-> ABSENT 1`). vc attributes it to `kind_of` matching the leading word only.

### C -- the render adds a section the source never had, and reorders sections (both)

hv's board now renders `## Holds` / `_(none)_`, and the pre-migration board had no Holds section. `## Standing directives` moved from the first section to the fourth, and devbin's roster tells every peer to read that section at pickup.

A fix could leave an empty section unrendered when the source never had one. The order may be an intended renderer choice.

### F -- board lead paragraphs are dropped, and migrate still exits 0 (both; exit status vc)

Five, reported on stderr as `uncarried:` with the reason "the model has no field for it". carry-map independently reads all five `ABSENT` (`BOARDLEAD -> ABSENT 5`). vc reports that migrate exits 0 regardless, so a scripted migration cannot tell anything went. The bytes survive in the `.history/20260916/` snapshots and in git at `24429c2`, the migration's parent: dc compared all three boards' blobs there against the snapshots with `cmp`, found them byte-identical, and a cross-node comparison as the red control differed.

### G -- `uncarried:` reads the same for a file left in place as for a loss (both)

Eighteen non-markdown `.history/` files were reported `uncarried:`, cc 9 and vc 9, counted from migrate's stderr. **All eighteen are still on disk and still tracked.** dc checked each path with `test -f` and `git ls-files --error-unmatch`, with a nonexistent path as a red control on both checks, and vc confirmed. Among them are the two patches that cc's board names as the held work on two open devbin issues. Counted, the report reads as eighteen losses where there are none.

## Identity -- `intent wb register` and the launcher

### H -- `register` with arguments has the node's own board in hand and never reads its header (both)

At 06:45:39.360Z devbin's `vc` row was written as `gtools-vc` / `vc` while `intent/whiteboard/vc/wip.md` sat on disk with a hand-authored header reading `Validation Claude` / `validation`. dc saw both states at 06:47Z. Neither value appears in any devbin header.

**`wb_register` does look at that file, and only to decide whether to render.** At `facade.rs:5747` it tests whether `<whiteboard>/<moniker>/wip.md` is a file, and passes the answer to `register_nodes` as the render flag. It never reads the header inside it (dc, read from the source). The comment above it records that intent#0379 once rendered every registration, which erased the board the migrate reads; this build does not. **So the verb holds the evidence of a conflict and does not compare against it** -- which is sharper than not looking at all.

**Both devbin rows were written by `intent wb register <ws>` with arguments, established by elimination** (vc, each path ruled out by a read or a test rather than a search):

- `store.rs:1663` is a schema rung that rebuilds `wb_node` with `INSERT ... SELECT FROM wb_node`: it copies rows and cannot create a moniker.
- The launcher executes no whiteboard command.
- `hook()` at `render.rs:11310` only execs the shell bodies, and none of the six under `lib/templates/.claude/scripts` runs a `wb` command or reads a session name.
- iTerm's `cc-status` is a signed iTerm2 binary, and `strings` finds no Intent reference in it.
- MCP `wb touch` is an `UPDATE` only (`store.rs:4465`), and runs only when an agent calls it.
- `replace_boards` (`store.rs:4688`) needs a `board.json` holding the row, and none existed.

The vc row's values are in no header, so the arg-less form cannot have written it; the dc row's node never had a header, so the arg-less form had nothing to read. **Who ran each command, and where `gtools` came from, are NOT established, and J is why.**

A fix must stop and name the conflict when a registration's arguments disagree with the header in a board the verb has just found on disk.

### M -- the launcher's remedy invites `register` with arguments and shows neither value (vc)

When `intent claude start <ws>` finds no `intent/whiteboard/<ws>/` directory, `intent/plugins/claude/bin/intent_claude_cwi:193` tells the operator to run `intent wb register <ws> --name <display name> --role <role>`. The launcher names the session `<project>-<ws>`, so the natural fill-in for a display name is the session name.

**devbin's `dc` row fits that path.** It reads `devbin-dc` / `dc`: the session name and the moniker, where every other node on the board reads like `Control Claude` / `control`. It was written at 06:30:43.396Z, with `recorded_at` equal to `migrated_at` to the millisecond (vc) -- **5.6s before the dc session's first transcript record at 06:30:48.965Z** (dc, read from the transcript), so the dc session cannot have written it. The vc row was written 5.7s before its own session's first record (vc). Both offsets fit a register command run just before each launch. The remedy text cannot account for the vc row, because `intent/whiteboard/vc/` existed.

A fix must show what a display name and a role look like in the remedy, or read them from somewhere, rather than leave the operator to guess.

### I -- no verb corrects a node's name or role (both)

`register` refuses a re-register with different values -- `WbRegisteredDifferently`, at `facade.rs:5732` (dc, read from the source) -- and there is no unregister verb (dc: `intent wb --help` lists none, and `register --help` offers no update or force option). What remains is hand-editing `intent/whiteboard/<node>/board.json`, a generated file, and running `intent sync --to-store`, or editing `wb_node` in the store directly. dc read the carrier declared at `store.rs:644`, `:659` and `:678` and read back at `ingest.rs:296`, and vc rehearsed the `board.json` route on a scratch copy. **vc's own fix for the foreign `vc` row on 2026-09-16 needed a `DELETE` on `wb_node`, because no verb could do it.** A mistake made through the verbs can be undone only by hand-editing a generated file or the store.

### N -- `sync --to-store` reports nothing overwritten while it changes a node row (vc)

In vc's scratch rehearsal of I's `board.json` route, `intent sync --to-store` printed "nothing the store already held was overwritten" while it changed dc's row from `devbin-dc` / `dc` to `DevX Claude` / `devx`. Either the message is false or it means something narrower than it says. Measured by vc; not re-measured by dc.

## Audit and doctor

### J -- whiteboard writes are absent from `event_log` (both)

`event_log` holds 298 rows across 25 distinct ops -- `issues.*`, `ac.*`, `at.*`, `st.*`, `wp.*`, `attachment.put`, `disk.*` -- counted with no display limit, and **not one whiteboard op**.

**The control is positive, not an inference from the other ops.** The log's only row since 06:00Z on 2026-09-16 is a `disk.sync_to_disk` at 07:02:41.791Z. Whiteboard writes at known times fall on both sides of it and none is recorded: before it, the `dc` registration at 06:30:43Z, dc's pickups at 06:32:21Z and 06:47:09Z, the foreign `vc` registration at 06:45:39Z, the arg-less re-registration at 06:59:44Z and the three migrates at 07:01:28Z; after it, dc's three adds at 08:57:03Z, and the archive, add and pickup at 09:00:52Z. The item and node times come from their own rows' `recorded_at`, `migrated_at` and `archived_at` (dc).

This is why H stops where it does: the store can say what a row holds, but not who wrote it, from which session, or with which arguments.

### L -- doctor names remedies that cannot clear what it reports, and the commit gate refuses on them (vc)

Two instances, both driven by vc; together they wedged devbin's commit gate on 2026-09-16 with no supported way out.

1. **A closed issue's leftover view.** Recorded in devbin `5f0460e`: `intent/issues/0065.md` was a closed issue's view no longer declared in `.intentfiles`, so `sync --to-disk` skipped it while doctor kept counting it, and organize refused to guess. vc removed the file by hand.
2. **A board awaiting migration.** While `vc` was registered but not migrated, doctor called `vc/wip.md` "a generated view that differs from the model" -- 7546 bytes on disk against the 422 the empty row renders -- named `sync --to-disk` as the remedy, and warned that the remedy would discard a hand edit. **It does not.** vc rebuilt that exact state in a scratch copy and ran the remedy: rc 0, and `vc/wip.md` was 7546 bytes with the same hash afterwards, byte-identical, and doctor reported the same finding again. The code says so at `facade.rs:7332`: "THE MARKDOWN BESIDE IT IS NOT TOUCHED" (dc, read from the source). Board writes refuse on an unmigrated node, and sync writes only `board.json`. vc reports this finding was among the 24 that refused the commit.

**The first draft of this document called instance 2 destructive, as a standalone high-severity K.** It was an untested prediction, first written into `5f0460e`'s message and relayed from there. The false warning is the defect; the destruction never existed on this build.

A fix must not name a remedy that cannot clear the finding, and must not warn that a remedy discards what it leaves untouched.

## What this draft does not cover

- **Message bodies.** Inbox carry is 1:1 by count on all four pre-migration inboxes -- hv from vc 6/6, hv from cc 1/1, cc from vc 2/2, vc from cc 1/1 -- and no body was compared.
- **L's two instances and N**, which vc drove. dc read `facade.rs:7332` but did not re-drive either instance, and did not re-run the rehearsal behind N.
- **The elimination in H**, which is vc's. dc read `facade.rs:5747` and `:5732`, not the six paths ruled out.
- **hv's eleven standing directives**, which vc counted: 11 in the model, 11 rendered, 11 in the snapshot.
- **intent#0384** (inbox heading prose) and **intent#0375** (`directive` as an item kind), which vc reports fixed in `d24487079` and confirmed at `wbmigrate.rs:120`. cc's 2026-09-14 findings predate that build.

## Appended 2026-09-16 11:26Z -- N is wider than N says (vc)

Appended after `1915cd7` rather than edited into it. vc's message to intent-vc carried this.

vc rehearsed I's `board.json` route on a scratch copy before using it for dc's row, with a column diff of all three `wb_*` tables. `intent sync --to-store` renumbered the `id` of all 89 items and of 9 of the 11 messages, and rewrote `updated_at` on all 104 rows -- while printing that nothing the store already held was overwritten. Row order held.

**So I's first remaining route is not a clean correction: to change one node's name and role it rewrites every whiteboard row.** vc did not use it. dc's row was corrected with one `UPDATE` pinned to the old values and required to change exactly one row, then `sync --to-disk`, and a diff against a `sqlite3 .backup` showed only `name` and `role` changed. Measured by vc; not re-measured by dc.

## Appended 2026-09-16 11:29Z -- O: `updated_at` is kept by no writer (both, low)

Not in the message vc sent intent-vc. It pairs with J: the store keeps no log of whiteboard writes, and the one column that looks like it could stand in for one is not maintained.

**No whiteboard write moves `updated_at`, on nodes or on items.** On `wb_node` it trails `heartbeat_at` on all four devbin rows: cc, hv and vc read the 06:59:44Z re-registration although all three were migrated at 07:01:28Z and vc was picked up again at 11:28:22Z, and dc reads its 06:30:43Z registration although `pickup --focus --session` changed its focus and session at 11:27:03Z (vc found this; dc confirmed it on all four rows). On `wb_item`, archiving three dc items at 09:00:52Z and 11:27:03Z left each one's `updated_at` equal to its `recorded_at` (dc). The schema declares `updated_at` with a default and no trigger -- the store has none -- so it is stamped once at insert and never again.

**A column whose name promises "last changed" and whose value means "created" is read wrong by anyone who trusts the name**, and with J it is the nearest thing the store has to a record of when a row changed. A fix must either maintain it on every write or drop it.

## Appended 2026-09-16 13:12Z -- where each defect went in Intent

Intent filed the report at Intent `aa80e6917`, and hv ruled the defects fixed in Intent's current release. **This table is the one record of which letter became which issue**; hv's board points here (`16fb001`). dc read each issue's number, status, severity and title from Intent's own tracker with `intent issues show`, rather than from the relay, and all fifteen match.

| Letter | Intent issue | Severity | Status | Note                                                                                                                                   |
| ------ | ------------ | -------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| A      | intent#0403  | medium   | open   |                                                                                                                                        |
| B      | intent#0404  | medium   | open   |                                                                                                                                        |
| C      | intent#0405  | low      | closed | closed as intended; the harm it points at is intent#0416, and hv may reopen it                                                         |
| D      | intent#0406  | medium   | open   |                                                                                                                                        |
| E      | intent#0407  | low      | open   |                                                                                                                                        |
| F      | intent#0408  | low      | open   |                                                                                                                                        |
| G      | intent#0409  | low      | open   |                                                                                                                                        |
| H      | intent#0410  | high     | open   |                                                                                                                                        |
| I      | intent#0417  | medium   | open   | out of sequence: its first filing hit the store lock                                                                                   |
| J      | intent#0411  | medium   | open   |                                                                                                                                        |
| L      | intent#0412  | high     | open   |                                                                                                                                        |
| M      | intent#0413  | medium   | open   |                                                                                                                                        |
| N      | intent#0414  | medium   | open   | raised from this list's low, as a recurrence of intent#0111, which was high                                                            |
| O      | intent#0415  | low      | open   |                                                                                                                                        |
| --     | intent#0416  | high     | open   | filed alongside, not in this list: `wb pickup` renders peers as headers only, so no node sees another board's standing content at boot |

**What Intent says it will do** (vc's relay; not re-read by dc): a migrator that refuses uncarried content without an explicit drop flag and reports `coerced:` lines for what it reshapes; one store door that logs every whiteboard write; and `intent wb register <moniker> --name --role --correct` for a mistaken row.
