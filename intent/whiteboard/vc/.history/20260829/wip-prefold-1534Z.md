---
node: vc
name: Validation Claude
role: validation
session_id: 37214cfb-198a-4b48-980d-d4ab03e852d6
heartbeat_at: 2026-08-29 15:22Z
status: active
focus: "Release plan DONE (four parts). Since: devbin-users.md leads with its stamp and a stale one goes to hv not to a rebuild, per hv's ruling. 0040 CLOSED by fix. 0036 ANSWERED -- upstream in Intent's template, three projects affected, surfaced to hv not filed. FIVE open: 0034 0035 0036 0039 0042, all needing hv. Suite 770/770"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT.** hv's four-part release plan is complete and committed.
- **STATUS IS DELIBERATELY `active`.**

## Re-measured at this fold, not carried

| claim | measured 2026-08-29 14:46Z |
| --- | --- |
| open issues | **0034, 0035, 0036, 0039, 0042** -- five. **0040 CLOSED by fix.** Every remaining one needs hv |
| fleet | **THIRTEEN estates, split 7/6 by bytes**, plus 14 non-estate copies. Generated: `intent/docs/devbin-users.md` |
| suite | **770/770**, 0 failures, 2 self-declaring skips, rc 0 (was 728 this morning -- 42 new) |
| gates | `syntax` 32/0, `lint` 32/0, `doctor` 0 failures, `release check` current |
| tree | clean |

## The version/devbin distinction, kept because it was worth measuring

**`bin/devbin version` printing `utilz 2.4.0` is CORRECT.** `version` is *"show, set and bump the project version"*; `devbin` is *"about devbin itself... not this project's"*. Conflab prints `conflab 0.6.2` / `devbin 0.1.0`. **The output shape is the one the standing constraint warns about** -- a plausible version under devbin's name -- **and the mechanism is not**, which is exactly why it had to be measured rather than reasoned about.

## hv's 0.1.0 RELEASE PLAN -- ALL FOUR PARTS DONE 2026-08-29 14:46Z

**1. `intent/docs/devbin-users.md` -- DONE, and GENERATED rather than written** (`1715656`). `bin/devbin fleet doc` produces it; the document carries that command and a UTC stamp. I raised before starting that a table of versions and last-updated times is a document of claims with expiry dates, and built it accordingly.

**What the audit found that no previous census could:**

| claim | previous | measured |
| --- | --- | --- |
| estates | 12 | **13** -- `~/Dropbox/Geodica/_tools` is a real install and no census ever looked outside `~/Devel/prj` |
| split | 7/5 | **7/6 by bytes** |
| `_tools` stamp | never counted | `617bb17`, a THIRD stamp whose vendored bytes are **identical** to the `96fb408` group |
| other copies | never counted | **14** -- 2 Lamplight worktrees on devbin from 2026-08-10, 12 Mix `deps/` checkouts |

**The prune list IS the definition and is printed into the document**: prune `deps/` and the answer is 15 copies, keep it and it is 27.

**THE SCAN IS TAKEN TWICE AND THE WRITE IS REFUSED IF THEY DISAGREE.** One pass reported 13 estates and the next reported 12, the missing one being the only root under Dropbox, and it never reproduced. **Driving that refusal deliberately found a defect in the refusal**: `render_doc > $DOC_REL` truncates before the renderer runs, so a refused run destroyed the good document it was declining to replace. Issue 0002's shape, in a command written the morning 0002 was re-read.

**2. NO HARDCODED VERSION STRINGS -- DONE, and the instruction had to be DECLINED at exactly one site** (`46d4756`). Measured before changing anything: every runtime path already resolves live (`devbin_version_of`, `runtime_version`, `install`'s stamp) and those reads were already pinned by `doctor.bats` and `install.bats`. Four files carried the literal; three used `^0.1.0` as a caret-semantics **example**, and now name a version devbin is not.

**`devbin_version: "^0.1.0"` in devbin's own config MUST stay literal.** It is a CONSTRAINT. Derive it from `VERSION` and `doctor`'s `check_devbin_version` compares the running version against itself and passes vacuously forever -- **applying the instruction there manufactures the false green the instruction exists to prevent.**

**3. `RELEASES/` + `CHANGELOG.md` + `RELEASES.md` -- DONE** (`505a9a5`). Three hand-written documents about the same events is a Highlander violation by construction, so **`RELEASES/<version>.md` is the only hand-written record and the other two are rendered from it** by `bin/devbin release notes`. `release check` is a predicate that writes nothing.

**4. Ready for the release -- DONE** (`ad27a30`). `docs/releasing.md`, README links, and `.github/workflows/release.yml` firing only on a `v*` tag. It refuses a tag not matching `VERSION`, a missing note, an empty body, or stale views.

### Two of my own tests were defective, and only red-driving found them

- **`fleet`'s "a failed render preserves the document" was pinning the WRONG GUARD.** It removed every note, so `require_notes` refused before the renderer was reached, and it stayed GREEN against a direct redirect while its name promised the opposite. Split into two, one of which makes the renderer die PART WAY through via an unreadable note.
- **`documentation.bats`'s "exactly one file" passed VACUOUSLY over an empty set** when I broke the extractor. Only the floor caught it. **My first attempt at that red arm did not break the extractor at all** -- I swapped a path that no longer carried the version, so the green was mine, not the test's.

### Also fixed on the way

**`bin/devbin check lint` was RED at HEAD on a clean tree** (`a5311d3`), on one wrong shellcheck source directive in `lib/cmd/shell-init` -- `../helpers` is right relative to the file and wrong relative to the gate, which runs from `PROJECT_ROOT`. A breach there is any file shellcheck exits non-zero on, so one unfollowable path made the gate exit 1. **A gate red on a clean tree is a gate people learn to skip.**

## Since the release plan landed

**hv ruled `devbin-users.md` is NOT a steel thread** -- a quick doc capturing what we know now. Its stamp is now the FIRST thing after the title, ahead of the prose and the regeneration command, because a generated-at line below the tables is read after they have already been believed. **"Out of date at all" is written as "not FROM RIGHT NOW. Not recent, not today, not this morning"**, and **a stale stamp routes to hv rather than to a rebuild**. Four tests, all driven red -- including a HARDCODED stamp substituted for the clock read, which is refused because the value must be within five minutes of now.

**0040 CLOSED by fix.** `updatenotice.bats` promised a firing test that did not exist; thirteen tests all asserted SILENCE, so every guard was covered and the arm they guard was not. Four new tests, three of which exist to stop the first meaning anything: the control (same fixture, terminal removed, silent), the kill switch ON a terminal, and the once-a-day limit. Four red arms against `lib/helpers`, byte-identical after. **The skip path measured, not assumed** -- re-run with a PATH mirroring the real one minus `script(1)`, all four declare themselves skipped.

**0036 ANSWERED and stays OPEN here.** `bats tests/` is **Intent's template default** (`lib/templates/llm/_AGENTS.md:93`), not devbin's config, so per 0036's own rule it is a report. **Blast radius measured, not counted: THREE projects** -- Devbin (31 nested .bats), **Intent (114)**, Intentv2 (110). Nineteen live projects declare `shell`; the rest are flat-layout, where `bats tests/` works. **Intent ships the instruction and is its own largest victim.** `bats -r tests/` verified both directions: rc 0 / 770 tests, against rc 1 / "found no tests". **Surfaced to hv, not filed upstream.**

**`bin/devbin check lint` was RED at HEAD on a clean tree**, on one wrong shellcheck source directive. Fixed.

## AWAITING hv -- surfaced, not chased

- **THE TAG AND THE PUSH ARE NOT DONE AND ARE DELIBERATELY hv's.** Everything is staged for `git tag -a v0.1.0`; nothing outward-facing has happened. **There are currently ZERO git tags in this repo.**
- **The re-vendor.** Re-measured against the MANIFEST'S OWN SCOPE, which is `bin/devbin` plus `bin/.devbin/lib` (30 files) and **NOT `bin/.devbin/cmd/`, which belongs to the project**: the 7 are **2 seam commits behind**, the 6 are **3**. My first count said 4 and 5 because the pathspec included `cmd/`. **Both of today's seam changes are comment-only** -- a shellcheck directive and two example versions. `fleet` and `release` are devbin's own project commands and do NOT ship to consumers.
- **cc's BSD-only clock-guard defect in Intent's `whiteboard-clock-guard.sh`**, and whether to file it. cc will not file unprompted: `intent#0105` went in on hv's explicit instruction and they do not read that as standing authority. In `hv/inbox.vc.md` at 2026-08-29 11:46Z. **Verified here, not relayed**: `to_epoch`'s BSD arm parses `'%Y-%m-%d %H:%M'` (`:209`) naming no seconds, `TOLERANCE_SECONDS=0` (`:180`) against `-gt` (`:368`). The same stamp parsed 2s apart returns epochs 2 apart and 52s off true; a seconds-explicit control returns the identical epoch. GNU does not fill, so **the broken arm is the one no Linux CI runs.** Fails CLOSED.
- **The `st attach` ruling** -- the only thing that closes the 54.

## TODO

**Mine, ready to start:**

- **0040 is the one I would take next.** Wire `updatenotice.bats`'s firing test with `require_pty`, which `clean.bats` already proves works. New coverage for a path nothing has exercised, so it wants care.
- **THE FLEET RE-VENDOR: five estates are one seam commit behind (`95b2645`).** Needs hv's go. **The 2026-08-28 sweep took three commits because it waited**, which argues for the next one being sooner.

**hv's or intent-vc's to sequence, none started:**

- **0039 is PARTLY fixed and deliberately still OPEN.** `95b2645` applied the cheapest of its three remedies -- the refusal now names the argument, so hv's `init` case reads correctly. **Its title is still literally true**: the diagnosis is still made by where the caller stands, the message still says *"every command would act on <root>"* about something that may not be a command, and the exit-code question is untouched. **Closing it would claim more than was done.**
- **0035 is not a fix** -- four instances each ending *"state whether this is a convention"*. **0034 is real code** but **Lamplight-originated, hv's track**. **0036 is upstream with no local fix**; cc's verified sharpening is that `bin/.devbin/config.yaml:40` already declares `run: bats tests/unit`, so **the repo holds the right answer and the generated file contradicts it**. **0042** is filed to be decided, not implemented as written.
- **The `st attach` ruling is owed** -- the only thing that closes the 54. `organize` reads `54 unclaimed, 0 to remove`: a report category. **Do not close that number by moving anything.**
- **v2 issues residue: 34 markdown directories.** v3 writes none. Flagged, untouched.
- **`intent issues` has no edit verb** -- surfaced. 0036's body asks a question I have since answered.

**Blocked, not merely unsequenced:** **`use` as a devbin builtin is BLOCKED and not to be designed around.** **STILL EXPLICITLY DO NOT START: `--ivault`.**

## Watch-outs

General forms are in `intent/llm/LESSONS.md`.

- **TWO FLAVOURS AGREEING IS WHAT A DEAD INSTRUMENT AND A CORRECT ONE BOTH LOOK LIKE.** cc's: their first clock-guard harness pinned a stamp already aged into the past, so nothing could refuse under EITHER flavour -- 0/120 for both, symmetric and meaningless. **Only a positive control separated them.**
- **A CORRECT FIX WITH A WRONG STATED REASON IS WORSE THAN AN UNEXPLAINED ONE**, because the wrong reason reads as a class-level guarantee and nobody looks again.
- **A BOARD READ AT EVERY PICKUP BUT WRITTEN BY EXCEPTION DRIFTS BY CONSTRUCTION.** `hv/wip.md`'s `focus:` went stale twice in four days. **A node that reads a stale directive complies with it.**
- **A GUARD THAT ANNOUNCES A STOP IT CANNOT PERFORM IS WORSE THAN NO GUARD.** Paid twice, once inside the control written to catch that class (`pipefail` handing it bats's rc -- issue 0031's shape).
- **A BROKEN EXTRACTOR MAKES A SET-CONTAINMENT TEST PASS VACUOUSLY** -- every element of the empty set is named; only the floor caught it. **AN EXTRACTOR THAT READS COMMENTS IS READING THE WRONG DOCUMENT.**
- **A ZERO MEANING "MATCHED NOTHING" IS INDISTINGUISHABLE FROM ONE MEANING "NOTHING CHANGED."** A bogus pathspec returns the same zero.
- **COUNTING A PROXY COUNTS THE PROXY** -- three `source_commit` stamps read as three-way divergence; the bytes said two. **Digest the vendored `lib/`.**
- **A HEARTBEAT IS EVIDENCE ABOUT THE LAST WRITE, NOT ABOUT THE NODE.**
- **A CLAIM THAT NAMES A COUNT OR A STATE HAS AN EXPIRY DATE.** **Anything a fold keeps needs re-measuring or an explicit carried-forward-unverified mark** (cc's rule, applied above).
- **AN UNQUOTED HEREDOC IS A COMMAND SUBSTITUTION ENGINE.** Writing to `hv/inbox.vc.md` with `<<ENTRY` rather than `<<'ENTRY'`, I escaped every backtick except one and the shell **ran `bats tests/` and substituted `1..0` into the headline of a message to hv**. It read as a plausible sentence; the only external sign was a stray `ERROR: Found no tests` in the commit output, which I nearly dismissed. **Quote the delimiter on any heredoc carrying prose.**
- **`PIPESTATUS` IS BASH AND THIS SHELL IS ZSH** (`$pipestatus`, 1-indexed). It expanded to the empty string and I nearly reported that as an exit status.
- **A DOCUMENTED TRAP IS NOT A DISARMED ONE.** **Third instance today**: `-maxdepth 3` returned ZERO shell projects, hours after I flagged that exact decoy in the fleet audit. **A RELAY IS NOT AN INSTRUCTION.** **NEVER `head`/`tail` WHEN SIZE OR STATUS IS THE QUESTION.**

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here. **I hold that pen under hv's explicit grant; corrections factual only, directives byte-verified every time.**
- **Authority chain (hv, 2026-08-28):** hv -> intent-vc -> {intent-`{dc,ic,cc}`, devbin-vc -> devbin-`{dc,ic,cc}`, conflab-vc -> conflab-`{dc,ic,cc}`}. **My branch is one node: only `devbin-cc`.** Lamplight is hv's separate track.
- **Rule 2 (no builds in the Intent tree) is LIFTED**; rules 3 (`git add` + `commit --only` by path) and 4 (timestamps read from `date -u` in the writing command) stand. **Rule 3 is what made the fleet sweep safe in three estates with live sessions.**
- **`bin/devbin` is the invocation everywhere** (supersedes D6). **Delivery while in development is the DEV TREE.**
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`.**
