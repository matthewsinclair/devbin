# The v2 bucket, probed per file -- what the migration left behind

devbin/vc, 2026-08-26, for intent/vc's ST0057/13. Read-only measurement on Devbin at `f1d09f9`. Nothing was written to any thread.

## The finding is a RULE, not a list

**The v3 migrator's reach is a filename allowlist: `info.md` and `acceptance.md`. Every other filename in a thread directory is left behind entirely.**

| | |
| --- | --- |
| files probed (all tracked under `intent/st/COMPLETED/`) | **54** |
| fully migrated | **19 -- every one of them an `info.md`** |
| partially migrated | 12 (9 `WP/*/info.md`, both `acceptance.md`, `ST0001/design.md` at 1/5) |
| bucket-only | 22 |
| unprobeable | 1 (`ST0002/impl.md` -- too short for 3 file-unique prose phrases; NOT a pass) |
| **content not in the store** | **34 of 54** |

Cross-tabbed rather than eyeballed:

    every migrated file is info.md            True
    info.md files: 28 -> 19 migrated, 9 PARTIAL, 0 bucket-only
    neither info.md nor acceptance.md: 24 -> ANY migrated? False

**This predicts the other ten estates without probing them**, and it gives the ingest half its actual spec: it must handle arbitrary filenames, because arbitrary filenames are the entire gap.

## Why the filename comparison undercounts, and in the dangerous direction

The earlier count was 24 bucket-only, from comparing filenames between the bucket and the flat tree. The content probe says **34 of 54 carry content the store does not hold**. The extra ten are files that exist in BOTH trees and are still missing content -- `acceptance.md` is the clean case: it is present in the flat tree, it looks migrated, and its prose scaffolding is not there.

**A file present in both trees reads as migrated and can still have lost content. That is the failure a filename check cannot see.**

## What the instrument had to survive

Three defects, all caught by controls rather than by review, and the third only because the controls were run before the table was written:

1. **A table rule scored as a match.** The first probe picked 70 dashes -- `|---...---|` -- as a "distinctive phrase". It matches in any file with a table, and it was `design.md`'s only hit. Killed by requiring >=60% alphabetic characters, >=20 distinct characters and >=8 real words.
2. **Boilerplate scored as a match.** A phrase occurring in more than one bucket file says nothing about the file it was drawn from. Killed by requiring each phrase to occur in exactly one bucket file.
3. **Frontmatter scored as a match.** Sampling the first N long lines samples title/objective/preamble, which DO migrate. Killed by sampling evenly across the whole file.

And one non-defect that cost the most time. A diagnostic printed the phrase `` by reading `WP/18/info.md` back against this list ``; the display consumed the backticks as inline code, the backtick-less form was then grepped, it returned 0, and the probe was declared broken. **The probe was correct and the RENDERER ate the evidence.** Report a probe's evidence as counts and digests, never as a rendered string.

## The control that blocked a working instrument

The gate refused to emit a table until its controls passed, which was right. But one control encoded a false expectation -- *`acceptance.md` must come out `migrated`* -- and `acceptance.md` is genuinely PARTIAL. So a correct instrument was held back by an assumption, not by a fault.

**This is the mirror of the day's other failure and it belongs beside it.** A control disconnected from its subject passes when it should fail; a control asserting something untrue fails when it should pass. The first ships a false green. The second discards a true result and sends you to debug working code. Both are answered by the same question -- what would make this control go red, and is that the same thing as the subject being wrong?

Verified predicate for the phrase that proves `acceptance.md` is partial, by count rather than by display:

    phrase sha1 e4c988c11cb9, len 68
      bucket  1
      flat    0
      canon   0

## The full table

| file (under `intent/st/COMPLETED/`) | verdict | probes found / run |
| --- | --- | --- |
| `ST0001/WP/10/equivalence.md` | BUCKET-ONLY | 0 / 4 |
| `ST0001/WP/10/inventory.md` | BUCKET-ONLY | 0 / 4 |
| `ST0001/WP/11/baize-equivalence.md` | BUCKET-ONLY | 0 / 5 |
| `ST0001/WP/11/baize-inventory.md` | BUCKET-ONLY | 0 / 3 |
| `ST0001/WP/11/laksa-equivalence.md` | BUCKET-ONLY | 0 / 4 |
| `ST0001/WP/11/laksa-inventory.md` | BUCKET-ONLY | 0 / 3 |
| `ST0001/WP/11/lamplight-equivalence.md` | BUCKET-ONLY | 0 / 6 |
| `ST0001/WP/11/lamplight-inventory.md` | BUCKET-ONLY | 0 / 5 |
| `ST0001/WP/13/review.md` | BUCKET-ONLY | 0 / 6 |
| `ST0001/help-migration.md` | BUCKET-ONLY | 0 / 7 |
| `ST0001/impl.md` | BUCKET-ONLY | 0 / 7 |
| `ST0001/tasks.md` | BUCKET-ONLY | 0 / 8 |
| `ST0002/WP/01/multiplyer-toolchain.md` | BUCKET-ONLY | 0 / 8 |
| `ST0002/WP/02/arca_config-inventory.md` | BUCKET-ONLY | 0 / 3 |
| `ST0002/WP/02/arca_config-record.md` | BUCKET-ONLY | 0 / 6 |
| `ST0002/WP/03/arca_cli-record.md` | BUCKET-ONLY | 0 / 4 |
| `ST0002/WP/04/microgptex-install.md` | BUCKET-ONLY | 0 / 5 |
| `ST0002/WP/05/molt-inventory.md` | BUCKET-ONLY | 0 / 4 |
| `ST0002/WP/08/equivalence.md` | BUCKET-ONLY | 0 / 4 |
| `ST0002/WP/08/prolix-inventory.md` | BUCKET-ONLY | 0 / 5 |
| `ST0002/design.md` | BUCKET-ONLY | 0 / 6 |
| `ST0002/tasks.md` | BUCKET-ONLY | 0 / 7 |
| `ST0001/WP/01/info.md` | PARTIAL | 6 / 7 |
| `ST0001/WP/09/info.md` | PARTIAL | 7 / 8 |
| `ST0001/WP/10/info.md` | PARTIAL | 6 / 7 |
| `ST0001/WP/11/info.md` | PARTIAL | 7 / 8 |
| `ST0001/WP/12/info.md` | PARTIAL | 7 / 8 |
| `ST0001/WP/13/info.md` | PARTIAL | 7 / 8 |
| `ST0001/WP/15/info.md` | PARTIAL | 5 / 6 |
| `ST0001/WP/16/info.md` | PARTIAL | 4 / 5 |
| `ST0001/WP/18/info.md` | PARTIAL | 5 / 6 |
| `ST0001/acceptance.md` | PARTIAL | 2 / 3 |
| `ST0001/design.md` | PARTIAL | 1 / 5 |
| `ST0002/acceptance.md` | PARTIAL | 3 / 6 |
| `ST0002/impl.md` | UNPROBEABLE | 0 / 0 |
| `ST0001/WP/02/info.md` | migrated | 8 / 8 |
| `ST0001/WP/03/info.md` | migrated | 7 / 7 |
| `ST0001/WP/04/info.md` | migrated | 5 / 5 |
| `ST0001/WP/05/info.md` | migrated | 3 / 3 |
| `ST0001/WP/06/info.md` | migrated | 6 / 6 |
| `ST0001/WP/07/info.md` | migrated | 7 / 7 |
| `ST0001/WP/08/info.md` | migrated | 5 / 5 |
| `ST0001/WP/14/info.md` | migrated | 6 / 6 |
| `ST0001/WP/17/info.md` | migrated | 6 / 6 |
| `ST0001/info.md` | migrated | 6 / 6 |
| `ST0002/WP/01/info.md` | migrated | 7 / 7 |
| `ST0002/WP/02/info.md` | migrated | 4 / 4 |
| `ST0002/WP/03/info.md` | migrated | 4 / 4 |
| `ST0002/WP/04/info.md` | migrated | 3 / 3 |
| `ST0002/WP/05/info.md` | migrated | 6 / 6 |
| `ST0002/WP/06/info.md` | migrated | 6 / 6 |
| `ST0002/WP/07/info.md` | migrated | 5 / 5 |
| `ST0002/WP/08/info.md` | migrated | 7 / 7 |
| `ST0002/info.md` | migrated | 4 / 4 |

## Method

For each file: up to 8 candidate phrases of 60-70 characters, sampled evenly across the file, restricted to prose (alphabetic density, character diversity, word count), and required to occur in exactly one bucket file. Each phrase is searched literally and in JSON-escaped form against the whole of `intent/.canon/` and the whole flat `intent/st/` tree excluding the bucket. `migrated` = every probe found; `BUCKET-ONLY` = none found; `PARTIAL` = some. Fewer than 3 usable phrases is reported `UNPROBEABLE` rather than counted as anything.

Controls, all of which must pass before a table is emitted:

    negative sentinel -> not found             PASS
    ST0001/info.md -> migrated                 PASS
    ST0001/impl.md -> BUCKET-ONLY              PASS
    ST0001/design.md -> not fully migrated     PASS
    ST0001/acceptance.md -> probes fire        PASS
