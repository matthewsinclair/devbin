# `intent organize --default` -- what was asked, what was NOT run, and the defect the asking found

**2026-08-26, devbin/cc.** hv asked for `intent organise --default` and `intent organise --default --force` to be tested here, then withdrew it minutes later ("hang on, it's not ready yet"), then asked that intent/cc be consulted anyway. **Nothing was ever run that writes.** No `--apply`, no `--force`, no tar, no backup taken, because none was needed for what actually happened. This file exists because the consultation produced a measured defect and a set of predicates, and both would otherwise have lived only in a conversation that is about to be compacted.

## The command does not exist yet, and that is a source fact rather than an inference

    intent --version          -> intent 3.0.0 (80d8b2ca4d897dd15ecc051e7b5b682eed7c8a95)
    command -v intent         -> /opt/homebrew/bin/intent
    intent organize --help    -> one option only: --apply
    intent organize --default -> error: unexpected argument '--default' found

**The error is the correct and current answer, not a stale keg**, which is the reading a reasonable person reaches for first and it is wrong here. Per intent/cc: ic landed the default-declaration FUNCTION today (`baba2d9d`, `intentfiles.rs` plus its tests, two paths) with **no CLI wiring**. The keg's tag is this morning's and predates it. So the verb is unbuilt rather than unreachable, and no amount of upgrading this estate would have surfaced it.

## The corpus, measured -- and hv's screenshot renders it misleadingly

The editor tree in hv's screenshot reads as though `NOT-STARTED/` contains `ST0001` and `ST0002`. It does not; they are its siblings.

| path | files | tracked | what it is |
| --- | --- | --- | --- |
| `intent/st/COMPLETED/{ST0001,ST0002}/` | 54 | 54 | legacy v2 status-directory layout -- **the 54 `unclaimed`** |
| `intent/st/NOT-STARTED/` | 0 | 0 | empty directory left behind |
| `intent/st/{ST0001,ST0002}/` | -- | -- | today's rendered views, created 14:35 and 16:20 -- **the 30 `unchanged`** |

**THE CORPUS ABOVE MOVED THE SAME EVENING AND THE TABLE IS LEFT AS MEASURED, not rewritten.** At `5435007` (20:52) the whole v2 thread record was renamed `intent/st/COMPLETED/` -> **`intent/history/`** on hv's order, preceded by `3ec43a7` writing `intent/.intentfiles` by hand to declare the open set. **Pure renames: `git show --diff-filter=D` returns 0 files**, and `design.md` carries blob `af8722d089` on both sides, so nothing was lost. That is what took `organize` from 54 unclaimed to a report of all zeros -- **the corpus left the scanned tree; it was not reconciled away.** Checked because a 54 -> 0 move and an all-zero line read the same on the page.

Both threads closed 2026-08-10, so **Devbin's OPEN set is empty.** That is what makes this estate the extreme case for `--default` rather than a vacuous one, and it is the opposite of the first read: a `.intentfiles` written here would be **present and declaring nothing**, and the file's own header states that *ABSENT is not EMPTY -- a missing file means nobody has said, and everything stays; a file present and declaring nothing means keep nothing.* Every one of the 30 generated views goes undeclared in one step.

## Which column is actually at risk, and the correction that got there

**The 54 are safe.** `organize.rs:565` maps `ThreadFile::Attachment -> Action::Unclaimed`, an arm whose own comment reads *"reaching here means disk holds a carryable file with no record -- which is an ingest question, not a realisation one. Reported, never removed: it is the only copy."* **That arm never consults the declaration**, so `ST0001/design.md` (D1 to D24) and the `WP/10` and `WP/11` equivalence records cannot become removal candidates by declaring anything.

**intent/cc had told hv the opposite earlier the same day and retracted it here.** Their diagnosis of their own error, worth keeping under its own name: they read what `Action::Unclaimed` and `is_destructive()` MEAN and inferred what assigns them, without tracing `plan()`. **Reading the vocabulary and calling it the grammar.** ic corrected them from source; they then verified it themselves rather than taking the correction.

Two independent things stop removal even so -- AC-11.4 (`--default` never removes) and `preconditions::check` returning `NoDeclaration` on every project that is not Intent, which refuses dehydration outright. **Neither is a reason to skip the tar**, and the reason is not "it is all tracked": `intent/.cache/`, `intent/.treeindex/` and `intent/events.jsonl` are gitignored here, so `git checkout` is not a complete rollback.

## THE DEFECT: `unclaimed_digest()` is a function of WHERE THE TREE SITS

Surfaced by asking what `2f8c52144602` was before relaying it -- an instinct this estate acquired on 2026-08-26 for a different and weaker reason (a digest relayed corrupted at character 17, where every short-form comparison still matched because both nodes truncate to 16).

`unclaimed_digest()` is sha256 over the sorted unclaimed set truncated to twelve hex characters, **deliberately** truncated: its doc calls it *a CHANGE DETECTOR for a human reading one line, not an identity anyone pins against*. It exists because a count cannot see a SWAP -- devbin/vc measured that exchanging one unclaimed file for another inside one directory leaves the summary byte-identical.

**But `render.rs:1673` relativises the DISPLAYED paths through `project.relative()`, while `unclaimed_digest()` hashes the report's raw `step.path`, which is absolute.** The display was fixed after an estate printed 199 paths each carrying 90 characters of temp-directory prefix; the digest was not.

### Reproduced from three locations, with the set proven identical

| tree | location | reported digest |
| --- | --- | --- |
| live Devbin | `~/Devel/prj/Devbin` | `2f8c52144602` |
| intent/cc's canary | their scratch, at commit `7935dc5` | `2d8f8684f147` |
| devbin/cc's copy | this session's scratchpad | `c753d0f0b980` |

**Predicates, published beside the numbers, because a differing digest proves nothing until the sets are proven equal:**

    rsync -a --exclude '.git' <live>/ <copy>/          # 1550 files, 12M
    diff <(live displayed rows) <(copy displayed rows) # EMPTY, 28 rows each
    diff <(find intent/st/COMPLETED -type f | sort | xargs shasum -a 256) <(same in copy)
                                                      # EMPTY, 54 lines -- all byte-identical

Two digests could be a copy artefact. **Three locations, three digests, over a set proven byte-identical by content sha256 rather than by trusting rsync, makes it a path function.**

### The corrected form, demonstrated rather than proposed

sha256 over the sorted **relativised** rows, truncated to 12:

    live: ce9da879a418
    copy: ce9da879a418

**Stated limit, because this is a demonstration and not a drop-in expected value:** that digest is over the **28 displayed directory rows**, which is all this node can reach from outside the tool. The tool hashes **54 raw file paths**. So it proves the principle -- relativise before hashing and the digest survives a move -- and it is NOT the number a fixed `unclaimed_digest()` should be expected to emit. Anyone citing `ce9da879a418` as the expected output has cited the wrong thing.

### Why it matters more than a cosmetic wrong number

**It silently breaks the throwaway-copy workflow this fleet uses for exactly this class of test.** A digest that changes when the project moves is not comparable across a copy, a worktree, another machine, or CI -- and it fails in the direction that reads as a real difference, so the natural response is to go hunting for a content change that is not there. **Do not relay it, and do not compare it against another tree's run.** Compare it only across runs of the same tree in the same location, and record the path list beside it. Filed by intent/cc with intent/vc as a 3.0.1 candidate.

## The predicate for the real test, for whoever runs it

**Above everything else: `--default` must change EXACTLY ONE PATH -- `intent/.intentfiles` -- and nothing else.** Full `shasum -a 256` manifest of everything under `intent/` before and after; anything but that single addition is a failure.

| id | failure |
| --- | --- |
| F1 | any of the 54 -- **now under `intent/history/`, see the note above** -- changes bytes or disappears |
| F2 | `.intentfiles` declares any thread whose status is Completed or Cancelled |
| F3 | `--default` writes when a file is already present, without `--force` |
| F4 | `--force` writes with no tty attached |
| F5 | the preview AFTER `--default` does not report the closed threads as **to remove and blocked** |
| F6 | `organise --default` and `organize --default` differ in bytes or output (AC-11.5 requires ONE code path) |
| F7 | the total file count under `intent/` decreases at all |

**F5 is the one to watch hardest on this corpus** (intent/cc's call, and correct). With an empty OPEN set the right output is `30 to remove, blocked`. **A `0 to remove` there would mean the declaration never took effect -- and would read exactly like a clean pass.** It is the day's own rule with a new instance: silence where a report is required is as much a failure as the wrong action, and it is the failure that looks like success.

Mechanics confirmed by intent/cc against ST0057/WP-11: `--default` and `--force` are siblings; **`--default` never implies `--apply`**; `--force` regenerates an already-present `.intentfiles` behind a y/N read from the tty, so **no tty, no write**; removal stays behind `organize --apply` plus the dehydration preconditions. **Declaring and dehydrating are two steps by design.**

## Parked on

Nothing writes on this estate until dc's rebuild lands and the pair is verified, and intent/cc runs the canary on their copy first. Their copy sits at `7935dc5`, which was this repo's HEAD when checked -- **so their baseline and this estate's agree**, and that was verified with `git cat-file -t` rather than assumed from the short sha matching something plausible.
