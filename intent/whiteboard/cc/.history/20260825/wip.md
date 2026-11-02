# cc board -- the 2026-08-25 session

## What this file is, and what it is not

**It is not the working record, because that was lost during this fold and the loss is worth recording where it happened.**

The board accumulated roughly a dozen findings across the session. They were cut to a two-line summary when the board was updated to its closed state, and the archive step ran AFTER that -- so the first version of this file captured the summary and claimed to be the findings. A write where an append was meant, on the live board, during the fold that closed the issue about guards that catch exactly this. `append-only-guard` watches `.history/**`, not the board, so nothing fired.

Caught two ways, neither of them a gate: 580 bytes was too small for what the file claimed to hold, and the recovery script's own assertion refused to write a section it could not prove was the full one. The recovery then failed honestly -- `ced80f6` already held the summary, because the cut happened before the commit, and no earlier commit touched this board today.

**So the findings are not recoverable from git. They were never committed.**

## Where the content actually lives, verified rather than assumed

Nothing material was lost, because the board was the working copy and not the home:

| content                                                        | durable home                          |
| -------------------------------------------------------------- | ------------------------------------- |
| arming evidence, five mutations, guard hashes, the false green | `intent/issues/CLOSED/0030/`          |
| the detector defect, the idempotency misread, the unrun test   | `intent/issues/CLOSED/0029/`          |
| the decision-point rule, `shell-gate:58`, the placeholder entry | `intent/llm/LESSONS.md`               |
| the session's narrative                                        | `ced80f6`'s commit message            |

Each row was grep-verified present before this file was written.

## The lesson, which is the only thing here that is not a duplicate

**A fold's archive step must run before the cut, not after.** Reading the order the other way loses exactly the content the archive exists to preserve, and it does so silently -- the archive is created, it is non-empty, and it is wrong. The size is the only tell, and only if someone looks.

The general form is already catalogued in `LESSONS.md` as a fix landing in the blast radius of the defect it fixes. This is its cousin: a TIDY landing in the blast radius of the thing it was tidying.
