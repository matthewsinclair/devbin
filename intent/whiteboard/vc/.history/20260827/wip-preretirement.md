---
node: vc
name: Validation Claude
role: validation
session_id: 15122d15-b44f-488e-afff-32e432b5c8fc
heartbeat_at: 2026-08-27 14:25Z
status: active
focus: "Shipped clean, the update notice and the launcher retirement -- 700/700, three commits, all re-vendored to eleven. PHASE C IS HELD AND IS hv's: 19 symlinks, five with zero consumers and eight real migrations, Laksa worst at 40 exec + 2 CI. Next: hv instructs each {proj}-vc estate-wide on the bounce"
claims: []
---

# Validation Claude (vc)

## DOING

- **NOTHING IN FLIGHT. Devbin's tree is clean, every estate's devbin half is committed.** The next thread is hv's; on the bounce hv instructs each `{proj}-vc` to do the per-estate work rather than this node reaching into eleven trees again.

## SHIPPED TODAY

| commit | what |
| --- | --- |
| `57076f7` | `clean [rust\|elixir\|swift\|all]` + the vendored-runtime update notice + a 6x dispatcher startup fix |
| `9ce1c88` | the per-project launcher symlink retired; `bin/devbin` is the invocation everywhere |
| `871cd9c` | doctor's retired-alias note carries the CONDITION, not a pasteable `rm` |

**700/700, 2 declared skips.** All three re-vendored to eleven estates, every commit scoped `--only bin/devbin bin/.devbin/lib bin/.devbin/manifest.sha256` -- Conflab, Laksa and Lamplight kept their in-flight work untouched.

## HELD, AND IT IS hv's CALL PER ESTATE

**PHASE C -- THE 19 EXISTING SYMLINKS.** Measured per link, exec / CI / total refs:

| | | |
| --- | --- | --- |
| **Laksa** `laksa` | 40 / 2 / 533 | worst on both live measures, and my plan called it trivial |
| Lamplight `lamplight` | 38 / 1 / 642 | **`ll` chains through it** |
| Conflab `conflab` | 24 / 0 / 190 | |
| Baize `baize` | 22 / 1 / 153 | **`bz` chains through it** |
| Intent / Intentv2 `int` | 9 / 0 / 212, 144 | |
| trivial: `microgptex` `arca_cli` `arca_config` `px` `lk` | 0 / 0 / <=1 | takeable on hv's word |

**Nothing forces the timing: every existing link still resolves** (verified after the re-vendor, `bin/ll` -> `lamplight 0.5.0`, `bin/bz` -> `baize 0.1.0`), and doctor's note is advisory and names exactly who would break.

## TODO -- BUILT NOTHING, PROPOSED AND WAITING

- **THE doctor PATH-DEPENDENCY ARM.** intent-vc's Q2. `clean`'s live-binary scan already derives *does PATH resolve any name back into this tree*; it just asks at clean time, so it covers clean-then-rebuild and not rebuild-in-place. Move the scan to a shared home and have `doctor` ask it too. **Not started; hv's word.**
- **THE MACHINE-LEVEL HALF IS NOT DEVBIN'S.** `~/.local/bin/intent` pointing into a build tree is a fact about hv's PATH. **devbin stands in one project at a time by construction** and can never say "your PATH points into eleven trees". Genuinely unowned; belongs beside `dvb` in hv's shell config.
- **CLOSED 2026-08-27 16:36Z, ON hv's WORD: the fleet's gate no longer resolves through a build tree.** `brew link intent` (the formula was **PINNED**, so it was unpinned first -- the pin is `use dev`'s durability mechanism and its presence means the dev flavour had been chosen deliberately). `intent` now resolves `/opt/homebrew/bin/intent` -> Cellar `3.0.0_1`, sha `80d8b2ca`, and **`INTENT_HOME` moved from `prj/Intent` to the Cellar's `libexec`**. **GUARD BEHAVIOUR IS UNCHANGED AND THAT WAS MEASURED, NOT ASSUMED:** all seven hook files compare identical between Cellar and dev tree except `pre-commit.sh` (59 lines, 25609 vs 27475 b), which is the TEMPLATE COPIED at install time and not the live path -- the guard BODIES that resolve out of `INTENT_HOME` are byte-identical. Dev symlinks left intact, so `brew unlink intent` reverses it.
- **THE INSTRUMENT WAS WRONG AND hv CAUGHT IT: `brew link` BY HAND IS `use prod` WITH THE SAFETY REMOVED.** `Conflab/bin/.devbin/cmd/use` is the real mechanism -- `prod` unpins then links, `dev` unlinks then **pins** so `brew upgrade` cannot silently re-link, and both **verify the switch took rather than reporting the intent**. Intent has no `use`; **porting it is hv's own ask from 2026-08-15**, and both blockers recorded then have cleared (the tap now exists at `3.0.0_1`; the v2 bash CLI that made the axis three-valued now lives in Intentv2). Conflab's daemon half does not apply -- `intent daemon` is unimplemented in this build and there is no LaunchAgent.
- **HISTORICAL, AND THE REASON THE ABOVE MATTERED: A REBUILD OF `intent` OPENED A SILENT UNGATED WINDOW, AND THAT ONE WAS ~4 MINUTES WIDE.** Measured 2026-08-27, by accident, because I committed on both sides of it: `15:06Z` guards ran 4, `15:09Z` **NO guard ran -- not one is missing, ALL are** (`intent info` exit 127, `INTENT_HOME` resolved to `''`), `15:12Z` guards ran 4 again. Cause: all three installed binaries were absent mid-reinstall; `intent` returned at a NEW sha `4999051765fb`, and `/opt/homebrew/bin/intent` remains unlinked. **15 estates carry `.git/hooks/pre-commit.intent`; total cost was ONE ungated commit** (`e9a4868`, mine, hand-checked clean: `Z` present, inbox stamps monotonic, 0 escaped quotes, pure ASCII). **NOTHING ANNOUNCES THE WINDOW'S START OR END.** Its only trace is the stderr of whatever happens to commit inside it, so its width is normally unknowable -- and a window nobody can see is one nobody can schedule around.
- **THE FAIL-OPEN IS NOT THE DEFECT AND MY EARLIER ENTRY HAD IT WRONG.** Both branches fail open BY DESIGN and the guard-runner one argues it correctly: blocking every commit the moment `intent` is shadowed is 0043 rebuilt on the git side, and an operator mid-upgrade must be able to commit the upgrade. **What differs is LEGIBILITY.** The guard block prints six diagnosed lines naming the cause and issues 0036/0043; the critic branch prints `skipping` and an install hint. **Identical non-enforcement, and only one announces itself as such.** `pre-commit.sh:283 fail-opens` was the wrong frame.
- **AND I PUBLISHED THE ABOVE AS `LIVE` THREE MINUTES BEFORE IT STOPPED BEING TRUE.** Board entry and two peer messages, all saying every estate is ungated NOW, written while the reinstall was already finishing. **A live-state claim starts expiring the moment it is written and this one took under 240 seconds** -- the same class this node spent the day catching in others. Record the WINDOW and its measured edges, never the state.
- **INTENT'S `pre-commit.sh:283` FAIL-OPENS** at `exit 0` on a missing CLI -- 12 commits across three estates landed with no critic gate. **Not a declaration problem and it will survive fixing one.** Intent's, one line, and `check format` already implements the right asymmetry.
- **`mkproj` IS DEFINED IN 13 TEST FILES AND `tests/lib/test_helper.bash` IS THE REGISTERED OWNER.** `MODULES.md:67` gives that file **"Temp-dir isolation, fixture projects, assertions"**, and `mkproj` builds a fixture project. So this is not 13 copies of an unowned convenience; it is **13 copies of a concern the registry already assigns**, in the same directory as the file that owns it. Highlander against the registry rather than against itself, which is the form that needs no arguing. **Not started; hv's word** -- it touches 13 files and consolidation is hv's standing principle, so it is a candidate rather than a fix.
- **`clean` HAS NO `--report` MODE.** intent-vc asked for generations-per-crate as a leading indicator (455 artefacts / 199 crates = 2.3x, visible without measuring a byte). Not built.
- **STILL EXPLICITLY DO NOT START: `--ivault`.** devbin must NEVER parse an `intent://` reference -- literal prefix test only.

## Watch-outs

**Everything below was earned today and the evidence is in the commit messages, not here.** The general classes went to `intent/llm/LESSONS.md` at the last globalfold; these are node-specific and stay.

- **A REFUSAL RAISED INSIDE `< <(...)` IS SWALLOWED.** `die` exits the subshell, the parent reads no input and carries on. My PATH control fired, was discarded, and produced the false clean it was written to prevent. Found by breaking the splitter and watching the test NOT go red.
- **A CHECK TOO SLOW TO RUN IS A CORRECTNESS PROBLEM.** The obvious PATH scan was O(entries x files) with a fork per test and hung the suite past two minutes. A check that slow gets switched off.
- **AN ABSENCE-ASSERTION IS SATISFIED BY A HARNESS THAT NEVER RAN.** `script` cannot always allocate a pty, and then emits nothing -- so every test asserting SILENCE passed. **Two did.** The remedy is a sentinel the harness must print if it ran at all; the better fix is not to need a pty.
- **A FIXTURE THAT CANNOT EXHIBIT THE FAILURE MAKES ITS GREEN WORTHLESS.** The notice's first suite used a CLEAN git repo, so it could not produce the `+dirty` stamp that broke it in Lamplight.
- **BOTH DIRECTIONS OF A BROKEN INSTRUMENT ARE AVAILABLE AND ONLY ONE LOOKS LIKE A DEFECT.** intent-vc's `git grep -E ... \b` returned a confident **0** (true answer: 1110). My `set -- $t` under zsh handed `cd` the whole string and returned a confident **rc=1 on every link**. Mine cost two minutes because it screamed; theirs would have shipped. **Nobody investigates a green.**
- **`git add -A <paths>` ABORTS THE WHOLE ADD ON ONE BAD PATHSPEC** -- and then the commit succeeded anyway, so `fatal` and a partial success arrived together. A command whose exit status and outcome disagree defeats both readers.
- **A TOOL NAMING A SPECIFIC REMEDY IS READ AS ADVICE REGARDLESS OF ITS SEVERITY LABEL.** doctor's note offered `rm bin/<n>`; laksa-vc said it would have run it. **Deleting the command is not the fix** -- compute the condition instead, which doctor can do because it is standing in `bin/`.
- **A CONSUMER AUDIT THAT RESOLVES ONE HOP FINDS ONE HOP'S CONSUMERS.** I reported 17 symlinks; there are 19. Filtering on `readlink == devbin` cannot by construction see a link pointing at another link. **Ask what points AT a thing, not only what it points to.**
- **A SOUND INSTRUMENT READ BY EYE IS NOT A MEASUREMENT.** I ran the right command (`--name-only`, never `--stat`), printed a 27-row table, and converted it to `24` in my head. True value 21. **No command in the transcript is wrong; there is simply no command where the number should have been.** The predicate discipline below does not cover this, because the failure is one step AFTER the predicate and does not look like measuring. Write the counter, not the table.
- **A DISPLAY IS A LOSSY PROJECTION WITH NO ERROR CHANNEL, AND I CONSUMED FOUR OF THEM AS DATA IN ONE AFTERNOON.** `24` read off a 27-row table by eye (true 21); `15` from a `for d in */` that cannot descend (true 20); `10` from `grep ... | head`, whose default limit **is** 10, so the truncation was plausible as a count (true 13); and `[ -e "$p" ]` on a dangling symlink reporting ABSENT, which turned a 4-minute rebuild into an invented uninstall-and-reinstall. **cc shipped the same `[ -e ]` and got a right answer from it, because their run landed after the build finished.** None of the four errored. `--stat` truncating a path, `head` capping at 10, `tail` holding until EOF, `-e` following a link: **four tools answering truthfully about something other than what was asked.**
- **THIS NODE'S OUTPUT IS A MEASUREMENT, SO THE PREDICATE IS PART OF THE RESULT.**

## Decisions

- hv's standing directives live on `hv/wip.md`. Nothing is duplicated here.
- **`bin/devbin` is the invocation in every project** (supersedes D6). `DEVBIN_INVOKE` is what you type and is a CONSTANT; `DEVBIN_NAME` is which project this is. They were one field only because the launcher was named after the project.
- **`clean` discovers build trees by NAME union MARKER and classifies by REBUILDABILITY** -- markers say something built there, only a sibling manifest says it can be rebuilt. All three outcomes print with sizes.
- **`int cache --clean` is not an Intent verb** and shares no engine with `clean`: it is a project handler in Intent's own tree, hardcoded to `native/rust/target`, and never touches `release/`.
