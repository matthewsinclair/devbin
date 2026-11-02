# The fleet AT accounting -- what the v3 migration dropped, and what nothing was counting

devbin/vc, 2026-08-26. Read-only across 20 estates with [`at-accounting.sh`](../../at-accounting.sh) at `dd21aa9`. Every loss figure independently matches intent/vc's separate pass.

## Why this exists

arca_cli's hop 2 printed `residue: 0 blocking, 3 carried` and `ok: this project is now Intent v3.0.0`, and `verify-canonical.sh` reported **0 checks failed** over the top of it. It had dropped **26 of 55** acceptance tests. **`residue: N carried` reports rows the parser REACHED; rows it never reached are invisible to it**, and the AT count was in no tool's contract anywhere in the chain.

## The worklist -- 49 ATs across 4 projects

| project | thread | source | store | view | lost | WPs losing >=1 AT |
| --- | --- | --- | --- | --- | --- | --- |
| `arca_cli` | ST0011 | 55 | 29 | 29 | **-26** | 07 09 11 12 13 14 15 |
| `Utilz` | ST0009 | 13 | 0 | 0 | **-13** | ALL -- the thread stored zero tests |
| `Laksa` | ST0089 | 82 | 76 | 76 | -6 | |
| `Laksa` | ST0084 | 43 | 41 | 41 | -2 | |
| `Laksa` | ST0090 | 39 | 38 | 38 | -1 | |
| `Cdsync` | ST0001 | 15 | 14 | 14 | -1 | |

**Store and view agree on every row**, so the loss is upstream of rendering on all four projects, not only arca_cli. **Utilz ST0009 is the extreme: 13 declared, 0 stored** -- a whole thread, not a tranche -- and is cc's first fixture.

**Clean, measured:** Baize 13 threads / 162, Devbin 1 / 436, Intent 14 / 286, Intentv2 14 / 286, Riffle 5 / 52, Prolix 1 / 4.
**Nothing probeable** (no AT rows in source, reported as its own verdict and never as ok): Anvil 6 threads, arca_notionex 11, MicroGPTEx 3, Courses 2, Molt 2.
**Not migrated:** Conflab, Lamplight, Molt-flynn, Molt-matts, arca_config.

**Lamplight is absent on purpose.** It is back on v2 with no canon to compare against, so intent/vc's 25 across ten threads stands as the measurement of the tree they reverted. It is the only figure in their list this node could not independently reproduce, and it re-runs after Lamplight re-migrates.

## THE INSTRUMENT WAS WRONG TWICE AND BOTH DEFECTS READ AS CLEAN

This is worth more than the table. **The script written to catch a silent shortfall had two of its own, and its own controls passed throughout.**

- **Prolix** reported `nothing probeable` where intent/vc measured 4. Its `COMPLETED/` holds thread folders but the acceptance files live elsewhere, so the per-thread source came up empty and the code gave up rather than falling back to git. Now clean at 4 -> 4.
- **Baize** totalled 150 against intent/vc's 162. **Threads live in THREE places at the pre-migration commit -- `COMPLETED/`, `NOT-STARTED/` and the flat dir -- and this script looked in two.** ST0017 (2) + ST0024 (10) sit under `NOT-STARTED/`: exactly the missing 12.

Fixed by resolving each source path by LOCATING the file in the tree rather than assuming a directory name, and printing the path actually read on every row.

**The self-test passed the whole time, and it was not lying.** It asked one question -- *can this instrument see a known loss?* -- and the answer was always yes. **It never asked whether the instrument had looked at every thread, and a thread it never opened cannot fail a shortfall test.** That is a control that is true, useful, and scoped narrower than the claim it was being read to support.

**So the rule is not "write better controls". It is that a self-test is a claim about the cases it enumerates, and coverage of the SUBJECT is a second question that has to be asked out loud.** intent/vc's independent pass is what asked it. Two independent passes before one instrument is trusted -- then one instrument, because two implementations of one predicate is how ST0056's false positive happened.

## And the unit is the thread, not the directory -- for the third time

A cross-file `sort -u` collapsed Utilz's ST0008 and ST0009, which reuse AT ids, from 42 rows to 30 distinct, and nearly went out as *"we disagree, 30 vs 42"*. Per thread it is 29 + 13 = 42 and there was never a disagreement. **The script was per-thread and correct throughout; the ad-hoc check written to compare against a peer was the flawed one** -- which is its own small lesson about instruments built in a hurry to check instruments.

ST0056 was the first (a sweep summing across a thread DIRECTORY), the Devbin `manifest.sha256` depth-3 count was the second, this is the third, and intent/vc's note says there will be a fourth.

## Pass criterion after re-conversion

Ruled by intent/vc, this node's to state: **source == store == view, rc 0, with `--self-test` run in the SAME invocation.** A green from this script does not count unless the same run has just demonstrated it can still say SHORTFALL.
