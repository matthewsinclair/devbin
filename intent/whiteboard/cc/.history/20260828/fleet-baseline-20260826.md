# Fleet baseline -- Intent3 cutover (devbin side)

Owner: devbin/cc. Assigned by intent/vc 2026-08-26. **Pre-cut rows captured 11:05-11:06Z, BEFORE the fleet migration began.** That window is not recoverable; everything here is the "before" half of every later delta.

## Scope

**11 devbin installs, all of them Intent projects.** Fleet in scope for intent/vc is 21 (22 Intent projects minus Intentv2, excluded by hv). My intersection with their fleet is **10** -- my 11 minus Intentv2.

Predicate, filter load-bearing:

    find . -maxdepth 6 -type f -path '*/bin/.devbin/manifest.sha256' \
      | sed -E '/\.backup\/|\/deps\/|\.worktrees\/|_Archive\//d'

`manifest.sha256` is the authority, NOT `find -name .devbin`: Devbin itself has the directory and no manifest because it is the source. **The reason to trust the uniform `source_commit` column is that Devbin came back different** -- a uniform result from a predicate that has never returned anything else is not a measurement.

## Pre-cut rows (11:05-11:06Z)

All eleven at `source_commit 4dc899de522b0bcdbaca47e7726a53f1645c53a5`.

| Estate           | hook bytes | GUARD_RUNNER | guard state at cut                        |
| ---------------- | ---------- | ------------ | ----------------------------------------- |
| Arca/arca_cli    | 5090       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Arca/arca_config | 5090       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Baize            | 5090       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Conflab          | 5090       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Intent           | 25609      | 4            | delegated roster (hooksPath `.githooks`)  |
| Intentv2         | 20899      | 4            | delegated roster; NOT in vc's fleet       |
| Laksa            | 20159      | 0            | INLINE roster; hooksPath `bin/hooks`      |
| Lamplight        | 20899      | 4            | delegated roster                          |
| MicroGPTEx       | 4708       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Prolix           | 4708       | 0            | Aug-9 critic-only gate; 0030 open here    |
| Riffle           | --         | --           | NO pre-commit hook at all                 |
| _Devbin (source)_| 20899      | 4            | delegated roster, armed 2026-08-25        |

**ISSUE 0030 IS STILL OPEN IN 7 OF 11 ESTATES.** It was closed for Devbin on 2026-08-25 and has been read as fleet-wide since. It is not.

## Post-cut deltas

**Landings named with a sha: 2.** Baize (mine), A3/a3-content `f0c55ed` (not in my rows, recorded so the counts agree). Everything else in the fleet is still a hop.

### Baize -- LANDED `5bea21c49f4ff95aa564404f1616629027cd81d8`, 11:32Z

Verified as HEAD, tree clean. Measured PRE-FLIP: the `intent` on PATH is still v2 2.19.0, the keg is proven and unlinked, so `intent info` answers from the frozen v2. **This row re-runs after the flip.**

| surface | baseline 11:06Z | post-cut 11:32Z | |
| --- | --- | --- | --- |
| manifest source_commit / files | 4dc899de / 28 | 4dc899de / 28 | UNCHANGED |
| `pre-commit.intent` | 5090 b | 5090 b | UNCHANGED |
| GUARD_RUNNER | 0 | 0 | UNCHANGED |
| chain blocks | colon=1 | colon=1, angle=0 | single, not doubled |
| `critic --languages` | rc=0, 5 langs | rc=0, 5 langs | UNCHANGED |
| `devbin doctor` | 11 checks, 0 failed, 1 note | same | UNCHANGED |
| INTENT_HOME / runner | Intentv2 / present | Intentv2 / present | pre-flip |
| **user block** | **132 b `c344a704`** | **112 b `12bad4ea`** | **CHANGED** |

**THE MIGRATION LANDED AND BAIZE'S GUARD STATE DID NOT MOVE.** Byte-identical hook, GUARD_RUNNER still 0 -- the Aug-9 critic-only gate. 0030 is open at Baize AFTER its migration, measured rather than predicted, and a green commit there still says nothing about guards.

**THE USER BLOCK WAS NOT PRESERVED, AND THIS IS THE PROOF CASE FOR THE WHOLE FLEET.**

    BEFORE  <!-- Author: matts, created 2026-06-03. Add project-specific Claude directives below this line. Preserved across regeneration. -->
    AFTER   <!-- Author: matts. Add project-specific Claude directives below this line. Preserved across regeneration. -->

`, created 2026-06-03` is gone -- the regeneration wrote the template's current placeholder over whatever was between the markers. Twenty bytes, and they were provenance nothing else records. The mechanism is now demonstrated on a real landing rather than inferred from `canon.rs`. **The comment it wrote in place says, in its own words, `Preserved across regeneration.`**

**THE LABEL DISAGREEMENT IS THE LESSON.** intent/vc called Baize's block EMPTY, this node called it POPULATED at 132 bytes; both described the same template placeholder. **Adopting the more accurate-sounding label would have skipped the check and missed the loss.** The crude threshold (`> 1 byte`) is over-inclusive and over-inclusive is what caught it. Keep it.

Scaled against the before-state: Baize was cheap because its block was boilerplate. Devbin (914 b) and Riffle (132 b) carry the generated footer and are the two the tool will write; Lamplight (18121 b) and Intent (3092 b) are safe only by the accident of lacking one. **Sequence Devbin and Riffle after the preservation fix, not before.**

### THE RULE THIS SECTION EXISTS UNDER, learned by breaking it at 11:12Z

**A CHANGE OBSERVED IS NOT A LANDING.** The landing signal is intent/vc naming the project to this node WITH A COMMIT SHA. Until then an observed delta is a HOP, and the migration is three hops; hop 1 is something a frozen v2 2.19.0 `intent upgrade` produces on its own.

### Riffle -- RETRACTED, was never a landing

This node reported Riffle at 11:12Z as "CLEAN. first delta of the migration, a clean pass." **That was false and it was this instrument's first false green.** What changed under me at ~11:08Z was ic's HOP 1 only: the frozen v2 tool creating the hook and the settings file. Hops 2 and 3 had not run, nothing was committed, and the tree was held DIRTY on intent/vc's order -- deliberately, because a half-migrated project that looks clean must never exist.

The measurement itself was correct and the verdict on it was not:

| | before (11:05Z) | after (11:12Z) |
| --- | --- | --- |
| `pre-commit` | absent | 268 b shim |
| `pre-commit.intent` | absent | 20899 b |
| GUARD_RUNNER | -- | 4 |
| chain blocks | -- | 1 |

**That after-state is v2's hook -- the same shape nine other rows already carried.** The true row is "v2 hook created, migration not started". I read a delta as a verdict because I was watching for one, which is the shape of every false green: the observation was fine, the thing I concluded from it was invented.

Riffle remains the estate that will land WITHOUT double-block exposure, because hop 1 left it exactly one block to keep.

## Live hazards

- **LAKSA: `core.hooksPath = bin/hooks`.** Git ignores `.git/hooks/` there entirely. Laksa holds byte-identical copies in both places today, so a tool that writes `.git/hooks/` updates the inert copy, reports success, and leaves the executing hook stale. Identical-today is what makes the divergence invisible when it arrives. Detection is `git rev-parse --git-path hooks` BEFORE writing -- git's own answer, and the only one that counts. **THREE of the eleven set it, not one:** Intent `.githooks`, Intentv2 `.githooks`, Laksa `bin/hooks`. This node reported "Laksa is the only one, I checked all of them" at 11:1xZ having measured `Intent .githooks` itself an hour earlier -- a summary asserted over its own data, the same defect as the Riffle retraction and inside the same half hour. Both times the correct value was already on disk.
- **BREW `INTENT_HOME`.** Guard bodies resolve live from `$INTENT_HOME/lib/templates/hooks/`. Both absence branches fail OPEN by deliberate ruling. A brew install whose INTENT_HOME lacks that directory disarms four guards in every delegated-roster estate at once and every commit still succeeds. Canon's own words, written about itself: **a guard nothing dispatches is indistinguishable from a guard that passes.** Relayed to dc as an acceptance criterion on the brew leg, both directions, with a positive control.
- **9 of 10 rows carry a colon-form chain block** and are exposed to the double-block defect; Riffle was the exception and only because it was empty.

## Predicate errors made getting here, published because they will recur

- `-maxdepth 4` on `intent/.config/config.json` returned 17 and silently dropped both Arca estates, which sit at depth 5 -- **the identical depth error corrected on the devbin side that morning and reintroduced on the Intent side an hour later.**
- `-maxdepth 6` unfiltered returned 74: `.backup/` snapshots, `.worktrees/`, and `deps/` checkouts. arca_cli and arca_config are vendored as Elixir DEPS inside five other projects, so an unfiltered sweep counts them repeatedly and yields a fictional intersection of 19.
- `intent-chain-block-start` (dash form) returned zero everywhere **with no positive control**, so that zero distinguished nothing and was not reported as a finding. Stating the caveat was right and the reason was worse than assumed: **the spelling was invented.** v3's `825c48db` writes the ANGLE form, `# >>> intent-chain-block >>>` / `# <<< intent-chain-block <<<`; nothing anywhere writes the dash form. A zero from a pattern nothing emits is not evidence about the world, only about the pattern.
- The search for the `user:start` preservation logic **errored rather than answered**: zsh expanded an unquoted `--include=*.rs` into `no matches found` and aborted, returning an empty result that reads exactly like a clean negative. Same class as the guard census above, and the reason a uniform or empty column gets its tool's stderr checked before it gets believed.

## CLAUDE.md user block -- before-state, captured 11:2xZ

**v3 DOES NOT PRESERVE `<!-- user:start -->` / `<!-- user:end -->`.** Confirmed at the writer by intent/vc: the template carries the markers at `_CLAUDE.md:47-50`, `intentsvcs/src/canon.rs` contains no reference to them, and `--force` regenerates from template and drops the block. **The markers were never a contract in either tree** -- v2 protected the block by backing `CLAUDE.md` up (`bin/intent_upgrade:136`) and never forcing (`:196`), not by parsing anything. `grep -rl 'user:start' Intentv2/bin/` returns zero files against a pattern that returns 1 for both `Devbin/CLAUDE.md` and the template, so that zero discriminates.

This node's verification owns the before/after half, because intent/vc's verifier sees only after.

| Estate           | state      | bytes | sha256 (FULL -- see note)                                          |
| ---------------- | ---------- | ----- | ------------------------------------------------------------------ |
| Arca/arca_cli    | NO-MARKERS | --    | nothing to lose                                                    |
| Arca/arca_config | NO-MARKERS | --    | nothing to lose                                                    |
| Baize            | POPULATED  | 132   | `c344a70440d18c51e9be44242e57bbdcf6b88013ae5ac26b4863068d653d0199` |
| Conflab          | POPULATED  | 179   | `152e46ee536b65296086b238efb629900e2443ceb3ef213efd4ba5e24c46f6dc` |
| Intent           | POPULATED  | 3092  | `f849f85c9605c20ba2cdd9f3cb069f5e345878659ca42e5955418671e64cadb9` |
| Intentv2         | POPULATED  | 2612  | `71cbce31912f073b229301c894f914d12e811f2d67342b3f019fe88b42de8e2a` |
| Laksa            | NO-MARKERS | --    | nothing to lose                                                    |
| Lamplight        | POPULATED  | 18121 | `f28960510e3bc621eec728416e4d06c330cf6241ecd943d4d63827f39333b220` |
| MicroGPTEx       | NO-MARKERS | --    | nothing to lose                                                    |
| Prolix           | NO-MARKERS | --    | nothing to lose                                                    |
| Riffle           | POPULATED  | 132   | `c07e405fb6e9278767bd55035c997148654c8030b21c4bd6136112a640c54474` |
| _Devbin (source)_| POPULATED  | 914   | `4fe8e34c93359b03e0fa076c6dbce2ed52998ca1f4fb6fcbee2956e6558c7ef5` |

**FULL DIGESTS, AND THE TRUNCATION THEY REPLACE IS THE REASON.** This table carried 16-character prefixes until 12:0xZ. devbin/vc relayed Devbin's digest to this node and to intent/vc with **one corrupted character at position 17** -- the first character past where both of us stopped looking. intent/vc had already made before/after digest verification the fleet standard citing that value, so a CORRECT restore verified against it would have reported a failed splice. Confirmed by a third independent computation here: `...b03e0fa...`, not `...b03a0fa...`.

**Every short-form comparison made that day matched, and always would have.** The prefix could not see the corruption, so the check could not fail. That is the same shape as `AC-12.1` being blind to a resolution hazard because it was scoped on references -- **two instruments in one day, each blind in the region just past its own edge.** A digest exists to be compared in full.

No UNPAIRED cases: every file either has both markers or neither. **The first pass of this table labelled the five marker-less estates MALFORMED**, collapsing "no markers at all" into "markers that do not pair" -- two different absences with different remedies, which is issue 0016's distinction, enforced by devbin's own `cmd/check` and broken here by the node that maintains it.

**PROTECTION IS INVERTED FROM WHAT IT SHOULD BE.** The tool holds any `CLAUDE.md` lacking the generated footer, so the estates carrying the most hand-authored content are safe by accident (Lamplight 18121 bytes, Intent 3092 -- no footer, held). **Devbin and Riffle are the only two carrying the footer, so they are the two the tool will write** -- and Devbin's 914 bytes are the note recording that a correction once lived in the regenerated region and was eaten. It is the warning about being overwritten, and it is in the exposed set.

### The check, and its controls

    awk '/user:start/{f=1;next}/user:end/{f=0}f' CLAUDE.md | shasum -a 256

Run before accepting any post-cut row. Controls run 11:2xZ against a scratch copy, because a green proves nothing until it has been watched go red:

| control | change                                   | hash                | verdict            |
| ------- | ---------------------------------------- | ------------------- | ------------------ |
| A       | none                                     | `4fe8e34c93359b03`  | matches baseline   |
| B       | one character INSIDE the block           | `baaf472a5dee21b7`  | **goes red**       |
| C       | footer edited OUTSIDE the block          | `4fe8e34c93359b03`  | **stays green**    |

**C is the one that makes the check usable.** A v3 regeneration legitimately rewrites that footer, so a check keyed on whole-file bytes would fire on every migrated estate and be switched off by the third one. Scoping to the block is what keeps a red meaningful.

## Chain-block census -- corrected, BOTH marker forms

**The first census was blind and would have reported a doubled hook as healthy.** It matched only v2's colon form, so a hook carrying one colon block AND one v3 angle block returns `colon=1` and reads as single. That is the failure mode the census exists to detect, passing.

Two spellings exist and only these two:

    # intent-chain-block:start (generated by intent claude upgrade)   <- v2
    # >>> intent-chain-block >>>                                       <- v3, written by 825c48db

`intent-chain-block-start` (dash) was invented by this node and is written by nothing.

Census 11:3xZ, every estate resolved via `git rev-parse --git-path hooks` rather than an assumed `.git/hooks`:

| | colon | angle | total | verdict |
| --- | --- | --- | --- | --- |
| all 11 estates + Devbin | 1 | 0 | 1 | single, healthy |
| **CONTROL** -- intent/vc's Molt-flynn canary | 1 | 1 | **2** | **DOUBLED, detected** |

The control is what makes the twelve ones a measurement. A census that has never returned anything but 1 is not evidence that nothing is doubled.

Incidental, and it matters for the Laksa hazard: **v3's angle-form shim resolves its own path with `git rev-parse --git-path hooks`**, so the shim honours `core.hooksPath` correctly. The open question was never the shim -- it is where the TOOL writes the shim.

### Baize -- REMEDIATED `ab8172a`, verified byte-exact

`intent: restore the user block's provenance -- HAND-FINISHED`. The 20 bytes this node reported lost were put back, and the restore is exact rather than approximate:

    block now      132 b  c344a70440d18c51e9be44242e57bbdcf6b88013ae5ac26b4863068d653d0199
    baseline ef1d941 132 b  c344a70440d18c51e9be44242e57bbdcf6b88013ae5ac26b4863068d653d0199

Identical. **This is what the baseline was for** -- without a before-state captured while it still existed, "restored" would have been a claim rather than a comparison.

### Riffle -- LANDED `66b7fdd`, BLOCK LOST, NOT REMEDIATED

    BEFORE (08c072f)  132 b  c07e405fb6e9278767bd55035c997148654c8030b21c4bd6136112a640c54474
      <!-- Author: matts, created 2026-08-10. Add project-specific Claude directives ... -->
    NOW               112 b  12bad4ea13449501ede0f2f04996a730f701c8d68036c47cf6c326ed7226f480
      <!-- Author: matts. Add project-specific Claude directives ... -->

`, created 2026-08-10` gone. Same 20 bytes, same mechanism as Baize, **still outstanding.** Baize's fix is the template for it and the before-value above is what it must be restored to.

### A FLEET-WIDE DETECTOR FALLS OUT OF THE PAIR

Riffle's post-loss digest and Baize's post-loss digest are **identical**: `12bad4ea13449501ede0f2f04996a730f701c8d68036c47cf6c326ed7226f480`. Both estates' blocks were replaced by the same template default, so that one digest means **"this block is the template's, not the project's"** wherever it appears.

It is a cheap sweep across all 22 Intent projects and needs no per-project baseline -- which matters, because a baseline only exists for the eleven this node holds. **It is a detector and not a proof:** an estate whose block was genuinely still the untouched default returns the same digest, so a hit means "check this", not "this was robbed". The before/after comparison remains the only thing that distinguishes them, and it only works where a before was captured.

## OPERATOR-CARRIED BLOCKS (Laksa, Prolix -- measured 12:1xZ, MECHANISM CORRECTED 12:3xZ)

**This section was published as "A THIRD LOSS MODE: WRAP-AND-LOSE" and blamed v3. That was wrong, and the correction is recorded above the evidence rather than below it.** The measurements are unchanged and one real loss came out of them; the mechanism was mine to get right and I got it wrong. See "THE COMMIT THAT MADE THE DIFF EXPLAINED THE DIFF" below.

**The detector above is still scoped to the wrong half of the fleet.** It asks "is this block the template's", which is the Baize/Riffle mode: an estate that HAD a block and had it replaced. It is blind to the estates that had NO markers, because it assumes those had nothing to lose. **They had no BLOCK. They had a FILE, and the file had content.** That sentence is the correction to this document's own `nothing to lose` column, and it was written by the node that wrote the column. It survives the mechanism correction intact -- the column was wrong about content regardless of who moved it.

What happened to these two marker-less files is that the pre-existing content was carried into a fresh user block BY THE OPERATOR under `--force`, not by the tool. Two landings, measured independently, same shape:

| estate | landing      | old file | new file | old lines | demoted (+1 level) | GENUINELY ABSENT | new block | block sha256 |
| ------ | ------------ | -------- | -------- | --------- | ------------------ | ---------------- | --------- | ------------ |
| Laksa  | `2bf06a276`  | 5580 b   | 7932 b   | 112       | 13                 | **25**           | 4529 b    | `878efaabd8dcb07a0d455e5cd4226db4e56444a95909f81cf8a506e7cb1fb588` |
| Prolix | `bc620d4`    | 795 b    | 3576 b   | 21        | 1                  | **19**           | 172 b     | `47bb6d0069b1450fc1adf95861c6eb03c8e46a8cc9ac8045889864448d965846` |

Two transformations, both silent: every heading is demoted one level (`##` becomes `###`), and the file's `# Title` line is replaced by the marker comment. Those are structural and arguably correct. The 25 and the 19 are not structural.

**SEVERITY IS PROPORTIONAL TO WHAT SAT OUTSIDE THE MARKERS, AND IT IS NOT UNIFORM.** Prolix lost 19 of 21 lines and lost almost nothing worth keeping: `## Project Structure`, `## Steel Threads`, `## Commands`, `## Author` -- generic Intent boilerplate the v3 template supplies better, plus `This is an Intent v2.11.2 project.`, a hand-typed version with no writer at upgrade time. Losing that line is a repair. Laksa lost the same boilerplate AND this:

    This is an Intent project. Run `intent --version` for the version in use -- a hand-typed
    version here has no writer at upgrade time and is stale by construction.

Project-authored editorial, gone, `grep` confirms zero hits anywhere in the new file. It is the same sentence Devbin protects in its own 914-byte block and the same argument -- **the note warning that hand-typed versions get eaten was eaten.**

**So `innocent` is the wrong label and so is `robbed`.** intent/vc predicted Laksa would return the template digest and read as a benign false positive. It returned neither: `878efaab...` is Laksa's own content carried in by hand, the detector correctly did NOT fire, and one authored line went missing while nothing was watching -- because every instrument in play, this node's included, was pointed at the block.

### THE COMMIT THAT MADE THE DIFF EXPLAINED THE DIFF

**v3 never wraps a marker-less file. It regenerates from the template, and whatever ends up in the block is whatever the operator carried there.** Verified here, not accepted from the message:

- Neither before-file carries the generated footer (`grep -c 'Generated by Intent'` returns 0 at `2bf06a276^` and `bc620d4^`), so hop 3 HELD both. The only path to a changed file was `--force`.
- Both landing commits say so in their bodies, in detail, before this node measured anything. Laksa: *"--force on CLAUDE.md: the held file was v2 boilerplate plus 123 lines of real project instructions ... spliced verbatim from the pre-migration file into the user block ... headings demoted one level, every line checked present."* Prolix: *"the held file was v2.11.2 boilerplate plus ONE authored line ... carried into the user block."*

**I diffed the tree and inferred a tool behaviour from the shape of the diff, while the commit that produced it stood there explaining itself.** That is the defect, and it is not a subtle one: `git show --format=%B` on the sha I was handed would have cost one command and prevented a published mechanism claim. The rule the rest of this file already states -- verify the brief against disk -- has a second half I skipped: **the commit message IS disk, and it is the cheapest evidence available about intent.** A diff shows what changed; only the message shows whether it was meant.

The two accounts also reconcile exactly, which is the check that settles it. intent/vc's *"every line checked present"* and this node's *25 genuinely absent* are both true: 23 of the 25 are the v2 boilerplate the splice deliberately dropped (`## Directory Structure`, `## Steel Threads`, `## Commands`), one is `Matthew Sinclair`, preserved inside the marker comment, and **one is the authored sentence.** The 123 project-instruction lines are all present. Two instruments, no contradiction, one real finding.

### THE ONE REAL LOSS, RESTORED AND VERIFIED BYTE-EXACT

`f5133dc87` on Laksa, verified here at 12:3xZ:

    the dropped line  sha256  cd192b42ef70da91213cfb4fbde5fe04db795969cb84b3a8c3a7a8f61f8cb591
    the restored line sha256  cd192b42ef70da91213cfb4fbde5fe04db795969cb84b3a8c3a7a8f61f8cb591   IDENTICAL
    block  4529 b -> 4692 b   delta 163 b = the 162-byte line + its blank separator, fully accounted
    block sha256 now  764fc4f51a257cc42c12487ebfd9ebe1ab362e11c95564bd01952df86e43392e

**Why one authored line hid inside a boilerplate cull is worth keeping, because it will recur.** The sentence sits exactly where the v2 template puts `This is an Intent vX.Y.Z project.` -- so it reads as template by POSITION while being authored by CONTENT. Prolix's version of that slot genuinely WAS template (`This is an Intent v2.11.2 project.`) and dropping it was a repair. Same slot, opposite verdicts, and position cannot tell them apart. **The only thing that could was a line-by-line diff against a before-state captured before the cut** -- which is what this file is for.

### Residual exposure, and it is short

Landed: Laksa, Prolix -- both measured above, both irreversible except from git. Not yet landed, before-state captured from the working tree 12:1xZ:

| estate           | bytes | sha256 (full file)                                                 | content                                |
| ---------------- | ----- | ------------------------------------------------------------------ | -------------------------------------- |
| Arca/arca_cli    | 1131  | `0a3c4c00f4f3aeed75a9f46704370b0f7d3b1aaa4955d654bcbd8100dd0916b1` | boilerplate + **Migration Notes**      |
| Arca/arca_config | 1131  | `0a3c4c00f4f3aeed75a9f46704370b0f7d3b1aaa4955d654bcbd8100dd0916b1` | byte-identical to arca_cli             |
| MicroGPTEx       | 687   | `4fe43b3a0d2508bb7d30bda7048bd6bfd8fc282813d12158d8d95c1ad83927e4` | boilerplate only                       |

**One thing in that set is worth saving and it is cheap to name BEFORE the landing rather than recover after.** Both Arca estates carry a `## Migration Notes` section recording the STP-to-Intent v2.0.0 migration of 2025-07-20, with the old and new directory layouts. It is project history and it exists nowhere else. On the corrected mechanism it survives only if the OPERATOR carries it across the `--force`, which is why naming it in advance is the whole intervention -- routed to devbin/vc with the digest below, and the reason it is worth naming is Laksa: the one line that did not survive was the one the operator read as boilerplate. MicroGPTEx has nothing but boilerplate and can land unattended.

(Arca's title line is `# Project Project Guidelines` -- a template placeholder that was never substituted, in both estates. Cosmetic, but it dates the file and it is about to be deleted anyway.)

## AN UNANNOUNCED LANDING, AND WHY THAT IS THE PROCESS FINDING

**Prolix `bc620d4` landed and was never routed to this node.** It was found by sweeping, not by being told. This node holds the only before-state for eleven estates, that state is overwritten by the landing, and rows are opened on announcement -- so an unannounced landing spends its before-state silently. Prolix survived only because git had the parent.

Fleet landing state, swept 12:1xZ (predicate: `git log --grep='migrate to v3 canonical'`):

| landed | estate | announced to cc? |
| ------ | ------ | ---------------- |
| `5bea21c`   | Baize  | yes |
| `66b7fdd`   | Riffle | yes |
| `2bf06a276` | Laksa  | yes |
| `bc620d4`   | Prolix | **NO**          |

**The ask is not more discipline, it is a cheaper predicate.** That one `git log --grep` line answers "what has landed" across the fleet in a second and needs no announcement to be correct. Run it before opening rows, not after -- announcement is the notification, the sweep is the record, and this document confused the two for an hour.

## Laksa -- LANDED `2bf06a2768f268b3b75c5aef70774dd0e75ccb3e`, pre-flip row

Verified HEAD, tree clean, 623 files changed (65778+/330-) -- file count re-derived here, not taken from the message.

| surface                    | baseline 11:06Z | post-cut 12:1xZ | |
| -------------------------- | --------------- | --------------- | -------- |
| executing hook (`bin/hooks/pre-commit`) | 930 b | 930 b, mtime 2026-08-21 | UNCHANGED |
| `.git/hooks/pre-commit`    | 930 b           | 930 b, mtime 2026-08-05 | UNCHANGED |
| `pre-commit.intent`        | 20159 b         | 20159 b         | UNCHANGED |
| `GUARD_RUNNER`             | 0               | 0               | UNCHANGED -- **0030 still open here** |
| hook paths in the landing  | --              | none            | the landing touched no hook |

**THE hooksPath FALSE-GREEN DID NOT MATERIALISE HERE, AND THE REASON MATTERS.** This node predicted that an estate with `core.hooksPath` set would have a tool write the inert `.git/hooks/` copy and report success. At Laksa it does not, because `pre-commit.intent` exists and is executable in BOTH locations at 20159 bytes, and because Laksa's own chain block resolves its target through `git rev-parse --git-path hooks` -- git's own answer, the same predicate this node arrived at independently. The gate runs. **The hazard is structural and not live**: the two copies are identical today, which is precisely the condition under which a future divergence is invisible. Reported as not-live rather than quietly dropped, because a prediction that fails is a result.

The landing was committed `--no-verify` on hv's ruling (Laksa's attribution guard read 178 regenerated verbatim lines as new claims), so the hooks were not exercised by it either way.

## THE BLOCK HAS TWO HALVES AND ONLY ONE OF THEM IS YOURS (12:4xZ)

**This is the finding that reframes everything above it, and it makes a prediction that can be checked.**

The user block is not one thing. It is a **tool-owned placeholder comment** followed by a **body**, and v3 3.0.0 treats them oppositely: it regenerates the comment from `intent/.config/config.json` and it carries the body byte-for-byte.

**One commit proves both halves at once, which is why it is the control and not just an example.** Laksa `7ae7f5bea` regenerated `CLAUDE.md` on the 3.0.0 pair:

    marker comment   "Author: Matthew Sinclair" -> "Author: matts"     REWRITTEN (-11 b)
    block body       2e5bb6993676cfa5b0c015a32e53b9bd47e99544ad9bcb3d75fe3c5e130512de   IDENTICAL

Same file, same commit, 4568 bytes of project instructions untouched while the line above them was rewritten. Corroborated at Devbin: the 914-byte block is byte-identical (`4fe8e34c...`) across `ced80f6` -> `5895df6`, ie straight through hop 3. Upstream, Intent carries `8ba6c026 fix(0056/06): the user block the template promised to preserve`, so the preservation is a fix that landed, not an accident.

### WHICH MEANS THE BAIZE AND RIFFLE "LOSSES" WERE NEVER BODY LOSSES

Both blocks are **132 bytes of pure comment with an empty body** -- verified, `sha256("")` = `e3b0c442...` on both. What went missing at their migrations was `, created 2026-06-03` and `, created 2026-08-10`: a fragment **of the tool-generated line**. There was no user content in either file to preserve, and none was lost.

That does not make the remediations wrong -- the provenance is worth having. It makes them **fragile in a way nobody has said out loud:**

**PREDICTION, AND IT IS FALSIFIABLE: the next regeneration of Baize or Riffle drops `, created <date>` again.** Both hand-restorations (`ab8172a`, `37c5dab`) wrote a value into the one line the tool composes from config and rewrites wholesale -- demonstrated at Laksa, on a different field of the same line, hours later. Neither has been tested yet: the re-stamps `1681a36` and `fd189d7` did NOT touch `CLAUDE.md` on either estate (`--stat` shows zero hits), so the restorations are sitting in front of a regeneration that has not run.

**The fix is cheap and it follows from the measurement rather than from taste: put provenance in the BODY, where preservation is proven, not in the COMMENT, where non-preservation is proven.** One line below the marker survives byte-for-byte; the same words inside the comment do not. If the `created` date belongs to the project it belongs below the line; if it belongs to the tool then the tool should emit it and no hand restoration should exist at all. What it cannot be is hand-written into tool-owned space and called durable.

## THE SWEEP HAD A FALSE NEGATIVE ON MY OWN ESTATE

`git log --grep='migrate to v3 canonical'` -- published two hours ago in this file as the cheaper predicate -- **reported Devbin as not landed.** Devbin landed at `5895df6`, whose subject reads `Devbin is an Intent v3.0.0 project: hops 2 and 3, ...`. Different words, same event, and the grep could not see it. Widening the pattern only made it noisier: it then matched Baize's *restore* commit and an unrelated upstream `fix(0056/06)`.

**A commit-message sweep is still reading the narration.** The state is one command away and does not care how anyone worded anything:

    jq -r '.intent_version' <estate>/intent/.config/config.json     # 3.0.0 = landed
    test -d <estate>/intent/.canon                                  # corroborates

This is the third time today the same shape has cost me something: a predicate that answers one question, read as though it answered the question. It is also the second instrument I built this session and then had to correct, and both corrections came from pointing it at my own estate.

### Fleet state, by state and not by message (12:4xZ)

| estate           | `intent_version` | `.canon/` | block body     | note                                  |
| ---------------- | ---------------- | --------- | -------------- | ------------------------------------- |
| Arca/arca_cli    | 2.18.0           | no        | (no block)     | **not landed; holds STP history**     |
| Arca/arca_config | 2.18.0           | no        | (no block)     | **not landed; byte-identical twin**   |
| Baize            | 3.0.0            | yes       | 0 b            | comment-only; restoration untested    |
| Conflab          | 2.19.0           | no        | 46 b           | not landed                            |
| Intent           | 3.0.0            | yes       | 2886 b         | landed                                |
| Intentv2         | 2.19.0           | yes       | 2406 b         | out of vc's fleet by hv's exclusion   |
| Laksa            | 3.0.0            | yes       | 4568 b         | landed; body proven preserved         |
| Lamplight        | 2.19.0           | no        | **17988 b**    | **not landed; largest body in fleet** |
| MicroGPTEx       | 3.0.0            | yes       | 0 b            | **migrated, NOT COMMITTED**           |
| Prolix           | 3.0.0            | yes       | 59 b           | landed                                |
| Riffle           | 3.0.0            | yes       | 0 b            | comment-only; restoration untested    |
| Devbin           | 3.0.0            | yes       | 781 b          | landed `5895df6`, block intact        |

**MicroGPTEx is mid-migration with an uncommitted tree** (8 modified, 6 untracked including `intent/.canon/`). Its before-state is safe -- `HEAD:CLAUDE.md` is 687 b `4fe43b3a0d25...`, matching the 12:1xZ capture exactly -- but it is the one estate where the before-state lives only in git and in this file, with a dirty tree between them.

**Lamplight is the one to sequence carefully.** 17988 bytes of block body, un-landed, the largest in the fleet by two orders of magnitude over most rows. On the evidence above the body will be carried; that is a prediction to verify on the day, not a reassurance to bank.

## Devbin -- LANDED `5895df6`, pre-flip row

My own estate, and the one whose block is the note warning that hand edits get eaten.

    block  914 b  4fe8e34c93359b03e0fa076c6dbce2ed52998ca1f4fb6fcbee2956e6558c7ef5
    at ced80f6 (pre-migration)  914 b  4fe8e34c...  IDENTICAL
    at 5895df6 (post hop 3)     914 b  4fe8e34c...  IDENTICAL

Byte-identical through hop 3. The warning survived the thing it warns about.

### One transcription slip, recorded because it is the exact class I flagged in someone else this morning

Comparing MicroGPTEx against baseline I hand-typed `4fe43b3a2d05...` into the comparison; the true value is `4fe43b3a0d25...`, differing at character 9. It did not reach the record -- the committed table carries the computed value and both agree -- because the typed copy went into a throwaway `echo` and the file was written by `shasum`. **The `a0fa`/`e0fa` correction I gave intent/vc was "never a value a peer typed". The rule is narrower than it should have been: never a value ANYONE typed, this node included.** Compute it in the same command that compares it.

## PRE-FLIP SNAPSHOT -- captured 2026-08-26 13:50Z, MINUTES BEFORE THE LINK MOVES

The flip is "on intent/vc's word" and `v3.0.0` is published. **These are the three rows that could never be answered before the flip and become answerable the instant it happens.** Captured now because the before-half stops existing when the symlink moves, and unlike a landing there is no commit to recover it from.

| row                                  | pre-flip value                                                       |
| ------------------------------------ | -------------------------------------------------------------------- |
| `~/.local/bin/intent` symlink        | `-> /Users/matts/Devel/prj/Intentv2/bin/intent` (Aug 21 13:36)       |
| `intent --version`                   | `Intent version 2.19.0`                                              |
| `intent info` -> `INTENT_HOME`       | `/Users/matts/Devel/prj/Intentv2`                                    |
| guard runner at that INTENT_HOME     | PRESENT, 10942 b, mode `-rw-r--r--`                                  |
| `intent critic --languages`          | **rc=0**, 5 languages: elixir rust swift lua shell                   |
| `bin/devbin doctor`                  | **rc=0**, 9 checks, 0 failed, 3 notes                                |
| pre-commit guard count (Devbin)      | **`guards: 4 ran, 0 skipped`** (was `3 ran, 1 skipped` pre-migration) |

**Two of these are the fail-open exposure and they are worth stating as predicates rather than values.** `pre-commit.intent` resolves `INTENT_HOME` by parsing the DISPLAY TEXT of `intent info` with a `sed` on `/^ *INTENT_HOME:/`, then looks for `$INTENT_HOME/lib/templates/hooks/pre-commit-guards.sh`, and **fails OPEN when either is absent**. So after the flip the question is not "does the commit pass" -- it will pass either way -- but:

    intent info | sed -n '/^ *INTENT_HOME:/p'                          # does v3 still print this line, in this shape?
    test -f "$INTENT_HOME/lib/templates/hooks/pre-commit-guards.sh"    # does the keg carry the guards?

A v3 that renames the field, reformats the display, or ships without `lib/templates/hooks/` produces a clean green commit with **zero guards running**, and nothing at the terminal distinguishes it from today's `4 ran, 0 skipped`. **`guards: N ran` in the hook output is the only observable that separates them, which is why the count above is captured and not just the pass/fail.**

Third row, `intent critic --languages`: `lib/cmd/check:118` fails CLOSED on a non-zero rc, and v3 uses exit 2 for "known command, not implemented". So if v3 has not implemented `--languages`, `devbin check` **blocks** rather than false-greens. That one is safe by construction, and is recorded so the two failure directions stay visibly different.

### A shell slip while writing this section, kept because the control is the point

The first attempt at this append used an UNQUOTED heredoc, so every backtick in the prose above ran as command substitution -- `zsh: command not found: pre-commit.intent`, `command not found: INTENT_HOME` -- and the write timed out. **Nothing was corrupted: the file stayed at 36645 bytes and the tree stayed clean**, which is only knowable because the next command checked `git status` and the file's byte count instead of assuming a failed write leaves nothing behind. A partial heredoc write into an append-only record is exactly the kind of damage that is invisible if you only look at the error message.

## THE MODE-644 BINARY DOES NOT SHADOW. IT IS SKIPPED -- WHICH IS WORSE (14:5xZ)

dc's cold install from the tap produced `-rw-r--r--` binaries, and intent/vc held the flip on the stated premise that `brew link` would then *"put a non-executable `intent` at PATH position 1 and shadow the v2 every estate runs"*. **The hold is right. The mechanism is not, and the difference decides how the flip gets verified.**

**PATH lookup requires the execute bit.** A non-executable file in an earlier PATH directory is not preferred-and-broken; it is passed over as though it were not there. Measured here on this machine, with a control:

| case | first on PATH                        | `command -v intent` resolves to | `intent --version` |
| ---- | ------------------------------------ | ------------------------------- | ------------------ |
| A    | mode-644 plain file                  | `~/.local/bin/intent`           | 2.19.0             |
| B    | symlink -> mode-644 file (brew shape) | `~/.local/bin/intent`           | 2.19.0             |
| C    | **mode-755, same bytes** (control)   | **the shim**                    | --                 |
| D    | the hook's own resolver under B      | `INTENT_HOME=/Users/matts/Devel/prj/Intentv2`, guards **FOUND**, rc=0 | -- |

C is the control and it is what makes A and B measurements rather than a broken test: same file, same directory, same PATH position, **only the mode differs**, and the 755 copy shadows immediately. `/opt/homebrew/bin` is position 1 on this machine and `~/.local/bin` is position 17, so the brew link genuinely would come first -- and still loses to a later executable.

**So the failure is not that v3 breaks the fleet. It is that `brew link` succeeds, `brew list` shows intent installed, and NOTHING CHANGES.** Every estate keeps answering from Intentv2, every gate keeps passing, and row D says the pre-commit resolver never even notices: `rc=0`, `INTENT_HOME` still Intentv2, guards **FOUND**. A fleet-wide green that means the opposite of what it appears to mean.

**That is strictly more dangerous than shadowing, and the reason is the project's own cardinal rule.** A shadowing broken binary announces itself -- `permission denied`, loudly, once. A skipped one is silent, and **indistinguishable from "the flip has not run yet"**.

### WHICH CHANGES HOW THE FLIP IS VERIFIED, AND THIS IS THE OPERATIONAL POINT

`intent --version` returning `2.19.0` after the flip is **ambiguous**: it reads identically for *not flipped yet* and for *flipped, silently failed*. The version alone cannot separate them. The disambiguator is the link target, which is why it was captured as its own row in the pre-flip snapshot rather than folded into the version line:

    readlink -f "$(command -v intent)"     # WHERE it resolves -- unambiguous
    ls -l "$(command -v intent)"           # and whether the thing it lands on is executable
    intent --version                       # WHAT answered -- ambiguous on its own

**Read all three, in that order, and never the third alone.**

### Scope of this measurement, stated because it is narrower than the conclusion it supports

This tested **PATH resolution**, not Homebrew. `brew link` may refuse a non-executable file outright, and `brew test intent` should catch it if it invokes the binary -- neither was tested here and neither should be assumed. What is measured is what happens *if* a mode-644 `intent` does reach a PATH directory ahead of the v2: it is skipped, and every downstream check stays green.

## intent/vc's VERIFIER ARM IS SOUND, AND IT IS NOT AN ACCIDENT (15:0xZ)

intent/vc's post-flip arm runs `intent st list` per migrated project and demands `rc=0`, reasoning that a silently-skipped link leaves v2 answering and v2 refuses a v3 project. **Verified here rather than taken, because Devbin is currently that exact state -- a v3 project with the v2 tool on PATH -- and because this node lost an exit status off this same command earlier today by reading it through a `head`.**

| project   | project version | tool | `intent st list` rc |
| --------- | --------------- | ---- | ------------------- |
| Devbin    | 3.0.0           | 2.19.0 | **2**            |
| Laksa     | 3.0.0           | 2.19.0 | **2**            |
| Conflab   | 2.19.0          | 2.19.0 | **0**            |

Conflab is the control: without it, `rc=2` could be this tool's answer to everything. Status read directly, no pipe.

**The refusal is deliberate, and its own text says so:**

    error: this project declares Intent v3.0.0, and this is Intent v2.19.0
      'st' would write to a project built by a newer Intent than this one understands
      hint: use the Intent that matches the project, or check which 'intent' is on PATH

**That third line names the PATH question outright.** Someone wrote it for precisely this confusion, so the arm discriminates for a reason its author *did* intend -- it is a designed forward-compatibility guard, not a lucky side effect. intent/vc should hold it with more confidence than they offered, and their instinct to add the link-target read anyway remains right for the reason they gave.

### The one real limit: the arm's coverage is a moving target

It fires only on projects already at v3. Against a v2-era project it returns `rc=0` and says nothing -- Conflab above proves that directly. **7 of 12 estates are at 3.0.0 right now; the other 5 are blind to this arm.** So the arm must be pointed at a project *known* to be v3, not at whatever is convenient, and its power grows as the migration completes -- weakest at the moment the flip is riskiest. `jq -r '.intent_version'` picks a valid target in one command.

## POST-FLIP ROWS -- flip stamped 2026-08-26 14:00:46Z, measured here 14:0x-15:0xZ

Every pre-flip row above is historical as of that stamp. Re-derived here, not taken from intent/vc's message.

### The three reads, in order

    readlink -f "$(command -v intent)"  ->  /opt/homebrew/Cellar/intent/3.0.0_1/libexec/bin/intent
    ls -l                               ->  -rwxr-xr-x  9773808   EXECUTABLE, the mode fix landed (note `3.0.0_1`)
    intent --version                    ->  intent 3.0.0 (80d8b2ca4d897dd15ecc051e7b5b682eed7c8a95)

Matches intent/vc's report in every field. **The flip is real and it took.**

### FOUR intents are on PATH, and three of them are still v2

    /opt/homebrew/bin/intent                    intent 3.0.0 (80d8b2ca)
    /Users/matts/.local/bin/intent              Intent version 2.19.0
    /Users/matts/bin/intent                     Intent version 2.19.0     <- a third link nobody has mentioned
    /Users/matts/Devel/prj/Intentv2/bin/intent  Intent version 2.19.0

**Nothing was removed; the flip works by PATH ORDER alone.** `/opt/homebrew/bin` is position 1 and wins today. The two dangling symlinks (`~/.local/bin/intent` and `~/bin/intent`, both dated Aug 21 13:36, both pointing at `Intentv2/bin/intent`) mean the v2 is one PATH edit, one `brew unlink`, or one login-shell change away from answering again -- **silently**, by the mechanism measured at `159ed8a`. Not a defect today. A live hazard with no owner, and worth a decision rather than a discovery.

### Predicate 1: PASSES -- the INTENT_HOME line keeps its shape

    INTENT_HOME:     /opt/homebrew/Cellar/intent/3.0.0_1/libexec

Left-padded, one space after the colon, exactly the shape `pre-commit.intent`'s `sed` addresses. The hook resolves it correctly.

### Predicate 2: PASSES -- the keg carries the guards

`/opt/homebrew/Cellar/intent/3.0.0_1/libexec/lib/templates/hooks/pre-commit-guards.sh`, 10942 b -- present, and the same size as the v2 copy. **The fail-open hazard did not materialise.** Both predicates green, and green here means measured-green: the pre-flip snapshot named exactly what would have been indistinguishable from this, and it is not that.

## THE ONE THAT BROKE: `intent critic --languages` REFUSES IN v3 -- AND "DOES NOT EXIST" WAS MY WRONG DIAGNOSIS

**This section was published as `DOES NOT EXIST IN v3`. It does exist.** intent/vc corrected it and `--help` settles it -- the flag is listed, with exactly its v2 semantics:

          --languages   List languages with a headless code critic, one per line, and exit

The defect is narrower and the narrowness is the whole fix: **clap declares `<LANG>` a REQUIRED POSITIONAL, so the flag cannot be used alone.**

    intent critic --languages         ->  rc=1   error: the following required arguments were not provided: <LANG>
    intent critic shell --languages   ->  rc=0   elixir rust swift lua shell   <- identical to v2's output

The positional is ignored when the flag is present -- passing `shell` returns all five languages -- which confirms the flag's behaviour is already correct and only its argument requirement is wrong. ic's fix (positional optional when `--languages` is present) is therefore a one-line change, not a feature.

**The correction matters because the two diagnoses have different fixes**: "does not exist" means implement it; "the arity is wrong" means relax it. I published the first from a symptom without running `--help`, which was one command away.

**SECOND MECHANISM CLAIM I HAVE GOT WRONG TODAY FROM THE SAME DEFECT.** This morning I attributed the Laksa/Prolix block loss to v3 without reading the commit body that explained it. Now I attributed a flag's absence to v3 without reading `--help`. **Both times the cheapest possible source was one command away and I reasoned from a symptom instead.** It is not two slips; it is one habit, and the habit is inferring a mechanism from an observation when the thing itself is right there and answers.

**And the blast radius splits by estate, along exactly the fault line issue 0018 documented and closed.**

### Ten estates: the builtin path, and it FAILS LOUDLY AND CORRECTLY

Verified at Baize (rc=1) and Prolix (rc=1), both landed v3, neither carrying a project handler:

    baize: `intent critic --languages` failed (exit 1) -- cannot tell which languages have a
    headless critic. The tool did not answer; this is not an absence of critics. Check which
    `intent` is on PATH: a second install shadowing the expected one is the known cause.

`lib/cmd/check:118` fails CLOSED, the diagnosis names the real cause, and it names the PATH question outright. **This is the gate behaving exactly as designed under a condition its author anticipated in a comment** (`the known trigger is a v3 binary shadowing v2 on PATH`). `devbin check critic` is broken on ten estates as of the flip -- loudly, which is the good failure.

### Devbin: the project handler, and it PASSES GREEN OVER ZERO RULES

Devbin is the one tree in the fleet carrying `bin/.devbin/cmd/check` (issue 0018), so `check critic` routes to `gate_critic` and `intent critic shell --files ...` -- never reaching the `--languages` call that kills everyone else. It returns **rc=0**. Same 8 files, same command, same shell, only the tool differs:

    v2:  critic: shell -- 2 of 6 rule(s) ASKED of this run; 2 armed in total.
         critic: shell -- 4 rule(s) could not be armed at all: 4 declared unanswerable ...
         ok: no shell findings at severity >= warning across 8 file(s)          rc=0

    v3:  critic: shell -- 0 of 0 rule(s) ASKED of this run; 0 armed in total.
         ok: no shell findings at severity >= warning across 8 file(s)          rc=0

**Both end `ok: ... across 8 file(s)`. Both exit 0. The flip silently disarmed the shell critic and the verdict line did not change by one character.**

**And the accounting line vanishes exactly when it is most needed.** v2 prints a second line naming the 4 rules it could not arm. v3 prints no such line -- because `0 of 0` has nothing to account for. So the one output that would say "rules are missing" is absent precisely in the case where *all* of them are.

The seal is honest in the narrow sense 0018 credited: `A clean result covers what was ASKED and says nothing about the rest` is right there, and `0 of 0` is stated. **But a scope caveat carrying the entire difference between a comprehensive verdict and a vacuous one is exactly the weight 0019 says a one-line scope statement must not carry alone** -- and here it is carrying it under a green.

### THE SHADOW IS THE THING THAT LIED, AND THE BUILTIN IS THE THING THAT TOLD THE TRUTH

The restart brief's standing warning is that `doctor` reports a shadow as `SUPPORTED OVERRIDE` and **cannot tell design from drift**. This is that warning arriving with a measurement behind it. Under one upstream change, on identical vendored bytes:

| path                                   | estates | post-flip behaviour                       |
| -------------------------------------- | ------- | ----------------------------------------- |
| catalogue `@builtin` -> `lib/cmd/check` | 10      | **dies, names the cause, names PATH**     |
| project handler -> `gate_critic`        | 1 (Devbin) | **green, zero rules, no signal**       |

0018 closed with *"Neither is a false green -- both seals state their scope"*. That was true of v2 and it is **no longer true**: the divergence that was merely a reporting difference has become the difference between a dead gate and a lying one. **A closed issue's verdict is scoped to the world it was measured in.** This is 0034's own lesson -- a seal states its verdict and not its reach -- landing on a different issue, which is the argument for it being a rule rather than an issue.

Devbin's own gate is the one that cannot be trusted right now, in the repository whose purpose is making this command identical everywhere.

## THREE FALSE SIGNALS IN THE INSTRUMENTS, ON THE DAY SPENT HUNTING THEM IN THE SUBJECT

All three are this node's, all three on 2026-08-26, all three the same shape: **a check that could not have failed, reporting that it passed.**

| # | instrument                          | why it could not fail                                            | caught by                                   |
| - | ----------------------------------- | ---------------------------------------------------------------- | ------------------------------------------- |
| 1 | the `gate_critic` bats harness      | omitted `PROJECT_ROOT`; the gate died before running, and the assert-FAILURE and assert-ABSENCE tests are both satisfied by a script that produced no output | reading the failure text of the two that DID fail |
| 2 | `pgrep -f 'bats tests/unit'` liveness | the pattern matched the monitoring shell's OWN command line, so it reported "still running" indefinitely | `ps` on the pid, which was the monitor itself |
| 3 | (devbin/vc's, recorded for the pair) | a negative control that set `INTENT_HOME` to a directory without `lib/templates/` -- v3 ignores that variable entirely, so the lever never reached the resolver | asking what would make the negative arm go red |

**The general rule, which neither node had alone: a control is only a control if you can say what would make it FAIL.** Not a broken test in any of the three -- a test **removed from the causal path** and still reporting.

**And the sharp version, devbin/vc's: red-first discipline generates the two vulnerable shapes FIRST.** Assert-failure and assert-absence are exactly what gets written before a fix exists, and both are satisfied by a script that never ran. The practice that exists to prevent false greens emits, as its opening move, the two assertion shapes blind to the difference between *did the right thing* and *never started*. That is a hazard of doing it correctly, not of doing it badly, so it needs a step rather than care.

**Two questions, and each of us answered one and skipped the other:**

    would this have failed?   -- stash the fix, re-run, confirm WHICH tests go red   (4 of 7 here)
    COULD this have failed?   -- break the control deliberately and watch it go red BEFORE trusting the green

The first assumes the lever works and only the fix is in doubt. The second is the one to ask when the LEVER is in doubt, and it is the one both nodes skipped, three hours apart, in opposite directions.

## PATH 2 MEASURED, NOT SUSPECTED -- AND THE FAIL-OPEN WARNING CANNOT FIRE FOR THE FAILURE THAT HAPPENED

devbin/vc re-verified `455d3f0` from a second node and put a sha on the half it does not close: **live commit `0b4b70b` succeeded through the pre-commit critic arm.** A working gate would have refused it. Measured by committing, not by reading.

**The mechanism is sharper than "the hook does not call `gate_critic`", which is what this node said, and the sharper version is devbin/vc's.** `pre-commit.intent:290` branches on **rc alone**, and the taxonomy it implements is deliberate and carefully argued in place:

    0)  clean pass          -- silent
    1)  findings            -- BLOCK
    3)  rule refused        -- BLOCK
    *)  gate broke          -- FAIL OPEN, loudly

The `*)` arm is not an oversight. It carries a ruling (*"a gate should fail open on its own breakage and closed on yours"*), it was hardened on 2026-08-20 to stop claiming a cause it had not measured, and it prints *"nothing else reports this, so if it persists the gate is not protecting what you think it is."*

**It never fires, because a 0-armed run is exit 0.** Measured: the hook's exact invocation returns `0 of 0 rule(s) ASKED; 0 armed in total`, `ok: ... across 0 file(s)`, **rc=0** -- byte-identical at the rc level to a genuine clean pass. The gate anticipated *the critic broke* and *the critic refused*, and never *the critic ran perfectly and had nothing to run*. **The third is the one that came true, and it is the only one the taxonomy has no code for.** A warning built to make invisible breakage visible, sitting behind a condition the real breakage does not satisfy.

### The count in this file was one low, and the correction strengthens the argument it was supporting

`gate_critic` reads `--format json` on the stated grounds that `pre-commit.intent` already recovers `INTENT_HOME` by `sed`-ing display text and **one of those is one more than this repository needs**. devbin/vc: there are two. Verified, with the distinction stated because it changes the remedy:

| site                       | what it does                                    | remedy                                       |
| -------------------------- | ----------------------------------------------- | -------------------------------------------- |
| `INTENT_HOME` resolution   | **parses** a value out of `intent info`'s display | re-point at a machine field                  |
| `pre-commit.intent:290`    | **requests** `--format text` and branches on rc   | switch format AND add the branch rc cannot express |

Only the first is literally a parse. The second is the more consequential: **it asks for the format that cannot answer the question its own fail-open arm exists to catch.** `armed` is in the JSON of the same run. The gate's discriminator is guarded by a format choice that makes the discriminator impossible.

**Not fixed here. It is Intent's, upstream, and neither devbin node is starting it uninvited** -- recorded as measured with `0b4b70b` on it, so the next person reads a fact rather than a suspicion.

## THE FOUR ARE ONE SENTENCE, AND IT WAS ALREADY WRITTEN DOWN

This node wrote *"an observation removed from the thing it claims to observe"* for the piped tail, and *"a test removed from the causal path and still reporting"* for the control pair. devbin/vc: **those are one sentence.**

    | tail                     removed the EXIT STATUS      from the run
    unbound PROJECT_ROOT      removed the ASSERTION        from the script
    self-matching pgrep       removed the SUBJECT          from the liveness check
    INTENT_HOME as a lever    removed the NEGATIVE ARM     from the resolver

**Something still reporting after it stopped being connected to the thing it reports on.** Four instances, one day, two nodes.

**And the uncomfortable half is devbin/vc's:** their board already carried the `| head` version of this from an earlier fold. So this is not a class being discovered -- it is the fourth instance of a class already written down, which is the argument for a step in the procedure rather than another entry in a catalogue. The catalogue was there and did not stop any of the four.
