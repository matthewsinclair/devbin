# 2026-08-26 PM -- the live Intent3 cutover, as devbin/vc ran it

Written 2026-08-26 13:55Z. The afternoon's HELD state is at [`intent3-cutover.md`](intent3-cutover.md); this is what happened when hv lifted the stop and intent/vc said GO. Pair for every hop below, read from `intent3 --version` in the same invocation as the act: `intent 3.0.0 (80d8b2ca4d897dd15ecc051e7b5b682eed7c8a95)`.

## Where the four estates stand

| estate | state |
| --- | --- |
| **Devbin** | **v3.0.0, committed `5895df6`.** Verifier 0 failed. User block preserved BYTE-FOR-BYTE: 914 bytes, `4fe8e34c93359b03e0fa076c6dbce2ed52998ca1f4fb6fcbee2956e6558c7ef5`, measured full-length before and after each hop-3 pass and compared with `cmp` against a saved copy. Hop 3 pass 2 wrote 0 of 4. |
| **arca_notionex** | **v3.0.0, committed `5fb1311`.** Verifier 0 failed. Hop 1 2.10.0 -> 2.19.0, hop 2 11 threads / 39 files. |
| **arca_cli** | **HOPS 1+2 DONE, HELD UNCOMMITTED** on intent/vc's ruling. 7 modified, 13 untracked. Rollback `.backup/backup-20260826-144753`. |
| **arca_config** | UNTOUCHED at 2.18.0, clean. |

## Three findings, and the third stopped the run

**1. A BLOCKED verdict that looks like corruption and is the new tool declining to carry a false green.** `intent3 ac status ST0001` on Devbin: `217/218 -- BLOCKED`. AC-10.5 reads `satisfied: yes` in the v2 source and `satisfied: no` in the v3 view, and **the first thing this node called it was an ingest inversion. It is not.** Cross-tabbing all 79 non-test criteria on whether their line carries an `evidence:` field discriminates **79 of 79**: the 78 citing evidence carried, the one citing none was refused. v3 will not represent a non-test criterion satisfied by nothing (`facade.rs:333`, `doctor.rs:657`); v2 let a hand-typed sign-off stand and nothing checked it. **So a false green that had sat in a CLOSED thread since 2026-08-10 became visible at migration.** Two hypotheses died on the way and both are the ones a reader reaches for first: an embedded ` -- ` in the body is not the cause (AC-11.11 carries EIGHT and survived), and neither is a second leading parenthetical (a perfect correlation at n=1 that dissolved the moment the evidence field was tested against all 79). Completing AC-10.5 is an authored act on hv's closed thread -- **with hv, not this node.**

**2. The `languages` back-fill names a language off a file Intent itself installed.** `arca_notionex` hop 1 wrote `["shell"]` into a 29-file Elixir project (`mix.exs` MixProject, 29 `.ex`, 9 `.exs`). Read from source, `Intentv2/bin/intent_migrations`, `step_languages_field_run`: it reads `intent/llm/RULES-<lang>.md` -- Intent's OWN prior artefacts -- and when there are none falls back to `("shell")` **on the bare presence of `.git/hooks/pre-commit`**, which Intent also installs. Both conditions held. **No source file is consulted at any point**, so the answer for any estate that never carried language packs is `["shell"]` with a hook and `[]` without, and never what the project is written in. The verifier could not see it: its arm asks whether `languages` is PRESENT. Fixed with the judgement-free half only -- `intent lang init elixir`, making it `["shell","elixir"]`. **`shell` was left in place and is spurious** (the only `.sh` outside `deps/`/`_build/` are Intent's own `.claude/scripts/*.sh`); removing a declared language is a standing configuration decision and is hv's.

**3. THE INGEST WRITES A BROKEN `file` INTO `.canon/`, AND `file-clean` IS ZERO EVERYWHERE.** `arca_cli` `ac status ST0011` returned 18 findings of the form "cites a file that does not exist". Every one of those files exists. From `.canon/st/ST0011.json` directly, not from a rendered view: `'AT-01.4' -> 'test/arca_cli/display_regression_test.exs (6 tests)'`. The `file` field holds the path AND the trailing ` (N tests)` as one string; strip it and **18 of 18 resolve on disk**. The checker is right and the stored data is wrong.

    Devbin     tests=436  file-absent=436  file-with-paren=  0  file-clean=  0
    arca_cli   tests= 29  file-absent= 11  file-with-paren= 18  file-clean=  0

**Read the `file-clean` column.** Wherever the ingest sets that field it sets it wrong; the only survivors are rows where it declines to set one -- the `(legacy)` `path::"describe"` dialect, 11 in arca_cli and all 436 in Devbin. **DEVBIN CAME THROUGH CLEAN BY LUCK OF DIALECT, NOT BY ANY PROPERTY OF DEVBIN**, and its committed canon was checked before that was said out loud. intent/vc's fleet count: 7 of the same already in COMMITTED canon (Cdsync 1, Prolix 2, Riffle 4).

## The reset recipe, corrected before it was needed rather than after

intent/vc ruled: delete the uncommitted `.canon/` and `.cache/` and re-run hop 2, because dc measured that a re-run over committed canon RE-EMITS rather than re-converts. **The mechanism confirms dc and is worth having as a rule:** `Project::migration()` returns `Done` when the declared version is v3 AND `legacy_thread_ids()` is empty, and that function ends `retain(|id| !self.thread_json(id).is_file())` against `intent/.canon/st/{id}.json`. With canon present there are no pending ids, so the tool does not consider itself unmigrated.

**But deleting canon alone re-arms the converter over TWO qualifying sources for the same id.** `collect_legacy` emits any directory holding an `info.md` with no `thread.json` beside it, descending one level -- so after the delete, hop 2's own generated `intent/st/ST0011/` qualifies exactly as `intent/st/COMPLETED/ST0011/` does. They dedupe to one id and **`collect_legacy` returns ids, not paths**. The generated view carries 15 citations in the polluted backticked form, so a fixed parser could re-ingest the damage out of a file rendered from the bad canon and the result would look like a successful reconversion. **The certain reset needs none of that question answered, because nothing on arca_cli is committed**: `git checkout -- .`, `git clean -fd`, then `rm -rf intent/.cache` -- the third line being the one a git-based reset silently misses, since `.cache/` is gitignored.

## Errors this node made, both self-caught

- **A line-addressed edit ate the line it had just written.** An `awk NR==39{insert}` shifted the file by one and the next edit in the same minute still used pre-insertion numbering, so `NR==40` overwrote the new content. The verification printed line 40 and line 40 was correct -- **true, and blind.** Found by grepping for the vanished text by name. Standing watch-out on the live board.
- **Two predicates that returned zero because nothing was searched.** `satisfied:` extraction conflated "field absent" with a value (139 rows read as `-`, the bullet); and an Arca pre-flight reported "0 non-test ACs without evidence" for `arca_notionex`, which has no `acceptance.md` at all. Both were caught by asking the count question -- **a zero is only informative once you have shown the search had a subject.**

## Carried for the rebuild

- `## Migration Notes`, 237 bytes, sha256 `58ca21040208232fa35341c5ea0a876d697568a6cfbed1543634c5a5c7e75a08`, **identical on `arca_cli` and `arca_config`** -- their whole `CLAUDE.md` files are the same 1131 bytes, so one verified carry serves both. Goes into the user block verbatim, heading demoted one level, HAND-FINISHED.
- `project_name`/`author` = the directory name and **`matts`**, written before hop 2. intent/vc's `git log --format=%an` heuristic was withdrawn: it records the COMMITTER identity, returns `Matthew Sinclair` on all seventeen estates including the fourteen whose config reads `matts`, and **a check that returns the same string everywhere has no discriminating power.** Proved against four estates whose answer was already known.
- `intent/events.jsonl` wants ignoring on `arca_cli` and `arca_config` (per-machine, `intent export` produces the file form; Intent's own tree has it at `.gitignore:149`). **Hop 2 adds `intent/.cache/` to an estate's `.gitignore` and does not add the event log** -- it ignores one per-machine artefact it creates and not the other.

## The Cellar positive control, run post-flip -- and the negative half had to be rebuilt first

The flip landed 2026-08-26 14:00:46Z and was verified here rather than taken: `/opt/homebrew/bin/intent` -> `../Cellar/intent/3.0.0_1/bin/intent` -> `libexec/bin/intent`, a real `Mach-O 64-bit executable arm64`, answering `intent 3.0.0 (80d8b2ca4d897dd15ecc051e7b5b682eed7c8a95)`. Three older `intent` remain on PATH, all shadowed.

**`intent info` under the keg resolves `INTENT_HOME: /opt/homebrew/Cellar/intent/3.0.0_1/libexec`, rc 0, and that directory really does hold `lib/templates`.** This closes the case `pre-commit.intent` records against itself in its own comments -- *"Measured on a brew-shaped install (a binary sitting outside its own tree): exit 1, resolution `<not set>`"*. That was the state before; it is not the state now.

**THE SPECIFIED NEGATIVE CONTROL IS INERT IN v3 AND WOULD HAVE PASSED FOR THE WRONG REASON.** The brief was to point `INTENT_HOME` at a directory with no `lib/templates/` and watch the gate refuse. `INTENT_HOME` no longer steers anything:

    unset                              -> /opt/homebrew/Cellar/intent/3.0.0_1/libexec
    pointed at a dir with no templates -> /opt/homebrew/Cellar/intent/3.0.0_1/libexec
    pointed at Intentv2                -> /opt/homebrew/Cellar/intent/3.0.0_1/libexec

The hook does not read the variable: it runs `intent info` and parses the `INTENT_HOME:` line out of it, so the resolution comes from the TOOL, not the environment. Setting the variable changes nothing, the guards run, and **the run reads as a passing control while having tested nothing at all.** A negative control that cannot fail is not a control; this one had to be rebuilt around a lever that actually moves the resolver -- a stub `intent` on PATH that reports `INTENT_HOME: <not set>` and exits 1, which is the exact signature the hook has a dedicated arm for.

Both halves, verbatim, run against the real `.git/hooks/pre-commit`:

    POSITIVE (keg-resolved):
      guards: 4 ran, 0 skipped (not applicable)
      rc=0

    NEGATIVE (resolver cannot locate an install):
      intent gate: NO guard ran for this commit -- not one is missing, ALL are.
        no usable INTENT_HOME (`intent info` exit 1, resolved to '<not set>'), so the guard runner could not be located.
        which guards were owed is unknown -- the roster lives in the install this could not find.
        the guards are fine; the tool that finds them is what did not answer.
        check `intent info` -- a binary running outside its own install tree, or a v3 binary shadowing a v2 install on PATH, are the known causes (issues 0036/0043).
      rc=1

**The negative BLOCKS rather than warns**, which is the half that matters: an unguarded commit is refused, not quietly permitted. That is the property the whole guard estate exists for, and it is now shown rather than assumed on a brew install.

**One operational hazard falls out of it.** The shell still carries `INTENT_HOME=/Users/matts/Devel/prj/Intentv2`, which v3 ignores entirely -- but `Intentv2/bin/intent` is still the tool that runs hop 1, and `arca_cli` and `arca_config` both still owe one. **Tidying the now-inert variable out of the environment would break the two hop 1s that remain.** It is Intent's to own via Molt and not this estate's to touch; it is named here so nobody reads "inert" as "removable" while a v2 hop is still queued.

## Re-verifying cc's `gate_critic` fix from the second node, on the terms agreed

cc landed `455d3f0` (663/663, EXIT=0, read off full TAP with a matching plan line rather than off `| tail`). Verified here on the agreed terms: **read the ARMED COUNT, not the verdict**, because the whole reason the defect was invisible is that the gate printed the same six words armed and disarmed.

**PATH 1, `devbin check critic` -- the path cc fixed. Refuses, rc 1, verbatim:**

    devbin: critic: 0 rules armed -- the rule library answered EMPTY, so this run examined 28 file(s) against nothing
    critic: a gate that armed no rules has not passed, it has abstained; refusing rather than sealing ok over an empty denominator

**PATH 2, the pre-commit hook -- NOT fixed, and it cannot be by that fix.** cc flagged this before I measured, which is the right order, and the mechanism is worth stating exactly because it is not "they missed a call site". `pre-commit.intent:290` calls `intent critic "$lang" --staged --severity-min "$SEVERITY" --format text` DIRECTLY -- `gate_critic` is never on that path. It then branches on rc alone:

    0)  pass, silently
    1)  findings            -> block
    3)  refused             -> block
    *)  UNENFORCED          -> "the commit is NOT blocked by this -- the gate fails open on its own breakage by design"

**Measured, not read: the hook's exact call returns rc=0.**

    critic: shell -- 0 of 0 rule(s) ASKED of this run; 0 armed in total.
    ok: no shell findings at severity >= warning across 0 file(s)
    rc=0
    ...and `--format json` on the SAME run: {'armed': 0, 'asked': 0, 'findings': [0 items], ...}

**So the empty library takes the `0)` branch and passes in silence.** The sharp part is not that the hook lacks a fail-open warning -- it HAS one, with a comment saying "nothing else reports this, so if it persists the gate is not protecting what you think it is". **That branch never fires for the failure that actually happened**, because a 0-armed run is not an odd exit code; it is exit 0, byte-identical at the rc level to a genuine clean pass. **The gate anticipated "the critic broke" and "the critic refused" and not "the critic ran perfectly and had nothing to run."** The only discriminator is the armed count, and this call site asks for `--format text`.

**That is a SECOND display-text parse in this one hook.** cc's fix took `--format json` on the stated grounds that `pre-commit.intent` already recovers `INTENT_HOME` by `sed`-ing display text and one of those is one more than the repository needs. There are two: the `INTENT_HOME` sed, and this `--format text` critic call. The count was one low.

**The window with real commits in it is therefore still open, and is wider than "before the fix".** Every commit through this hook is un-gated for the empty-library case, including `455d3f0` which carries the fix, and including this one. Not a fault of the fix -- it closes the CI and manual path, which is what it was asked to close.

**PATH 2 CONFIRMED BY A LIVE COMMIT: the commit carrying this section succeeded.** A gate that was working would have refused it.
