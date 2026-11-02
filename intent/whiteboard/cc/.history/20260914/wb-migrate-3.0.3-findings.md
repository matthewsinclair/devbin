# What `intent wb migrate` keeps and drops on Intent 3.0.3 -- read before migrating devbin's boards

Archived by devbin-cc on 2026-09-14 so the finding survives the session that produced it. It is a read of Intent's source and of other estates' git history by a read-only agent; nothing was migrated, registered or run. Citations are to Intent at the 3.0.3 build commit `46599d145`, under `native/rust/crates/`, because the installed binary was built there and Intent's checkout had since moved 79 commits ahead. **Every claim here is dated to that build; re-read the source before relying on it against a newer Intent.**

## Why it was asked

`intent wb pickup --node cc` refused on 2026-09-14: the store's roster is empty, because this project's boards were never registered or migrated. hv approved "register cc, vc and hv in the store and migrate their boards" knowing migrate is one-way. This read found content loss, so the migration was HELD for hv to re-rule with the list below in hand.

## What migrate carries

- It reads `<node>/wip.md`, every `<node>/inbox.<sender>.md`, and every file under `.history/` at any depth, and writes nothing until all are read (`intentsvcs/src/facade.rs:5556-5616`).
- From the header it carries `name`, `role`, `focus`, `session_id`, `status` and `claims`. `heartbeat_at` survives only as `authored_at`; the stored heartbeat and `migrated_at` become the migration time (`wbmigrate.rs:157-179`, `store.rs:4474-4477`). `node:` is not read; the command's argument names the node.
- Items come only from `## ` headings whose first word maps to a kind: doing, todo, decision(s), watch-out(s), hold(s) (`wbmigrate.rs:107-122`). A bullet list yields one item per top-level bullet; any other block (prose, a table, a `###` line) becomes one item verbatim (`wbmigrate.rs:181-189`, `268-293`).
- Inbox entries become unhandled messages; `.history/*.md` files become whole snapshot documents (`facade.rs:5643-5660`).

## What it loses

**Reported but not carried** -- listed on stderr as `uncarried: <file>:<line>`, exit 0 anyway (`render.rs:4270-4304`): everything under a heading that maps to no kind, and every lead paragraph between the title and the first `## ` (`wbmigrate.rs:216-235`).

**Lost with no report at all:**

- the text after the first word of a mapped heading -- `## TODO -- PARKED BY hv, NOT DROPPED` is carried as TODO and "PARKED BY hv, NOT DROPPED" vanishes (`wbmigrate.rs:112-114`, `240-243`)
- `###` grouping: a `### ...` line becomes a literal item and its bullets become plain items (`wbmigrate.rs:240`, `249`)
- layout: items render as `- {text}` with no indentation on continuation lines, so a table becomes one garbled bullet (`views.rs:1776-1778`)
- **on 3.0.3, the heading text of every inbox entry other than `Re:` and `FYI only`** (`wbmigrate.rs:330`, `354-361`) -- Intent issue 0384, fixed after 3.0.3 at `e0a359eed`. Eight of devbin's nine inbox entries at the time kept their summary in that heading.
- original stamps on rendered inbox headings, which show the migration time (`views.rs:1825`)

## What that would have meant for devbin's boards, predicted from the code and not run

| Board | Carried                                                     | Reported uncarried                                          | Lost silently                     |
| ----- | ----------------------------------------------------------- | ----------------------------------------------------------- | --------------------------------- |
| cc    | 32 items                                                    | 7 lines: lead; "Waiting on vc, not on me"; "Owed elsewhere" | the "PARKED BY hv" heading text   |
| vc    | 32 items, four of them literal `###` lines                  | 2 lines: lead                                               | the `###` grouping                |
| hv    | 16 items                                                    | 13 lines: lead; **all eleven standing directives**          | the TODO heading text             |

## No undo

- Migrate refuses a node that already has items or messages, so there is no second run (`facade.rs:5547-5558`).
- The file on disk is not rewritten by migrate itself; the next board write from ANY migrated node re-renders every migrated board and overwrites the hand-authored files (`facade.rs:5251-5288`).
- `intent wb register` with NO arguments is safe: it reads each header, inserts rows not marked migrated, and renders nothing (`facade.rs:5116-5164`). **The form with arguments marks the node migrated and renders at once, writing empty boards over hand-authored ones** (`store.rs:4327-4344`, `facade.rs:5207-5214`) -- Gtools hit this and restored from HEAD (`6224a21`, `c930daf`).

## Estates that already migrated

- **Utilz** (cc/vc/hv, the same shape as devbin), `1b0049c`: hv's whole `## Standing directives` section, eleven bullets, was reported uncarried and dropped at first render; they now exist only in git history and a hand-moved copy in `restart.md`.
- **Laksa**, `4a629219b`: hv shrank from 3992 to 1360 bytes; eight standing directives and a READ-THIS section went. They survive only because Laksa's vc copied every board and inbox to `.history/20260914/*-premigration.md` first. Intent issue 0375 (standing directives) was still open on 3.0.3.
- **Courses** and **Gtools** lost nothing or only lead paragraphs, because their boards used only the five mapped sections; Courses snapshotted every board first (`3e059c2`).

## What a safe migration here would need

Copy every board and non-empty inbox into `<node>/.history/<date>/` and commit it before anything else; move hv's standing directives and cc's non-standard sections into mapped kinds, or into a document that survives; keep migrate's stderr as the list of what went; and prefer a build carrying the 0384 fix, or accept losing the inbox headings. hv's board is maintained by vc, so its preparation is vc's pen.
