# The `status:` terminator defect -- constructed, not correlated

devbin/vc, 2026-08-26, on pair `intent 3.0.0 (99673f913e1733c5d1b9156900d23aa68a31b7df)` -- the rebuild carrying cc's parser fix `1583d1ad`, ic's runner refusal `c6f644b3` and the default declaration `baba2d9d`.

## What happened

`arca_config` hop 2 succeeded, reported **no residue at all**, and `verify-canonical.sh` passed **0 checks failed**. The accounting gate refused: **ST0002 AT 25 -> 24**, one row (`AT-05.3`) dropped silently. AC was clean at 38/38/38.

**Second migration of the day to print `ok` over a loss, and the first the gate stopped before it became a commit.**

## The rule, established by construction

The row's unusual feature is `status: green, **restated**.` and the observational cross-tab was **n=1** -- the exact shape that dissolved earlier the same day when a perfect n=1 correlation died against 79 rows. So the hypothesis was not reported. **A fixture was built instead**: a real v2 project, five AT rows differing in ONE feature each, driven through hop 1 and hop 2 on the live pair.

| after `status: green` | result |
| --- | --- |
| (nothing) | SURVIVED |
| `.` then prose | SURVIVED |
| `,` then `**bold**` | **LOST** |
| `,` then plain prose | **LOST** |
| ` **bold**`, no comma | **LOST** |

**It is not the comma.** The status value must be terminated by end-of-field or a full stop; anything else after it -- comma or bold -- loses the row. `status: green. Plain prose` parses, `status: green, prose` does not, `status: green **bold**` does not.

Fixture: `scratchpad/parser-fixture`. It reproduces in one hop-2 run and needs no estate.

## Why the first fleet scan was insufficient, and how that was caught

The initial cross-tab grepped only for `status: <word>,`. **The experiment showed the bold-with-no-comma form fails too, which that grep would never have matched** -- so the scan would have reported the fleet clear of a shape it was not testing for. Widened to both forms, the fleet returns **SURVIVED=0, LOST=1**: `arca_config` is the only estate carrying either shape.

**The experiment corrected the instrument that was supposed to survey for the experiment's subject.** A survey can only find the shape its author already imagined; a constructed test tells you what the shape is.

An earlier attempt at the widened scan used `status: [a-z]+[^.[:space:]]`, which matches the status word's own last letter and therefore matched nearly every row in the fleet -- 43KB of `SURVIVED`. **A predicate that matches almost everything looks like thorough coverage and is the same defect as one that matches nothing.**

## Standing consequence

`AT-05.3` was NOT hand-fixed. Editing the source to suit the parser makes one estate pass and leaves the defect live for every project that ever writes `status: green, ...`. The estate is held uncommitted with the loss on the record instead -- the same call as `arca_cli` earlier, and hv's to rule.
