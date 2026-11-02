# vc DOING -- archived at the evening localfold, 2026-08-25

The morning half of this day is in `wip.md` beside this file (0031, 0032, and the localfold that closed them). This is everything after it. The board's live half keeps only the `--ivault` not-yet and the standing watch-outs.

## Sweep #6, in two halves

**Half one -- the runtime.** Eleven vendored installs from `37ce21f5` to `6ee2f845`: 8 files each, 0 refused, 0 edited-in-place. Three estates -- Laksa, MicroGPTEx, Arca/arca_config -- had no project `cmd/docs` and declared `docs.treeindex_dirs` in their own config, so 0032 was not a drop-in for them; hv ruled they be fixed in the same sweep, and they were. Proven rather than asserted before the change: the NEW `lib/config`'s `cfg_validate` run against each estate's existing config gave 8 clean and those three at rc=1 naming the exact key.

**Half two -- the divergence, and it is the finding of the day.** `docs` -- the command devbin exists to make identical everywhere -- had eight estates on the builtin and THREE carrying full shadows that reimplemented it. Every private copy of `agents` was worse than the one it replaced: Baize's never printed the generated-file warning, Conflab's rolled its own printf instead of `warn`, both predated 0016's exit-status capture, and Lamplight's offered no `agents` at all while its header asserted the surface did not apply there and its generated AGENTS.md went stale with nothing able to regenerate it. All three shadows removed; project verbs declared as additive `options:` rows; `agents` now one implementation for eleven estates. Zero `cmd/docs` shadows fleet-wide after, `doctor` rc=0 everywhere, and no `intent treeindex` CALL anywhere in any estate's `bin/`.

**The general form, which is why it went to LESSONS rather than staying here: a shared implementation is only shared if something MEASURES adoption.** The permissive-override mechanism was not the defect. The absence of any signal separating "the catalogue cannot express this" from "someone re-typed the shared thing" was -- and `doctor` reports both as SUPPORTED OVERRIDE. The proof it was avoidable is that MicroGPTEx and arca_config had been using the composable path the entire time the shadows existed.

## The re-sweep, and why there were two

0033 closed AFTER sweep #6 landed and changed `lib/install`, so all eleven were carrying a `source_commit` that nothing would later match -- the record the NEXT sweep reads. Re-vendored onto `0257f7a`, then again onto `4dc899d` for the `--version` fix. Every manifest now carries a BARE sha, which is 0033's fix visible in the field: a whiteboard edit outside the seam no longer stamps eleven estates `THESE BYTES MATCH NO COMMIT` over a surface matching HEAD exactly.

## `devbin --version`, reported by hv from a consumer estate

`conflab devbin --version` printed a usage line and exited 1. The dispatcher had no arm for it though the datum was already in the manifest. **The unreported half was worse:** `runtime_version` treated an ABSENT manifest and an INCOMPLETE one as the same fact and fell back to `read_version`, which reads the PROJECT's version file -- correct only in devbin's own checkout, where D12 makes the project version devbin's. Anywhere else an install whose manifest lost its stamp would print the consumer's version under devbin's name. A plausible version number is indistinguishable from a real one by inspection. Broken manifest now refused by name; fallback reachable only where it is true. Also fixed unprompted: `show_overview` inlined `$(runtime_version)` as a printf argument, and a refusal inside a command substitution does not abort the printf holding it -- an unanswerable version would have printed BLANK and read as an answer.

## CI

The morning red at `32831220146` had all three real jobs GREEN and only the 3-second `Test Summary` aggregation failing. Single attempt, `needs` keys matching the job ids exactly, logs expired -- **root cause unrecoverable, and left unexplained rather than rationalised.** What was fixed is the reason it is unanswerable: the gate now echoes all three `needs.*.result` values before deciding, quoted so an empty value shows as `''`. Confirmed firing on the next run. It did not recur, which is all that was learned.

## Instrument failures, four, none caught by an exit status

1. First fleet count was TEN -- a depth-1 glob missed `Arca/arca_cli` and `Arca/arca_config`. hv's board saying eleven is the only reason it was re-derived.
2. The announce heredoc was UNQUOTED, so a backticked phrase was command-substituted out of my own message.
3. A `sed` lazy quantifier BSD sed rejects, producing a full table of identical errors read past as data.
4. A zsh glob erroring on a no-match `*.yaml`, which aborted the count and returned `workflows=0` for eleven estates -- a complete-looking table of zeros.

**The sub-class worth naming: three of the four were the TOOL erroring rather than answering, and the loop's shape swallowed it.** Each produced a plausible, complete-looking table. Extended onto the standing watch-out rather than added beside it.

## Peer work

Corrected intent/vc's `--ivault` seam figure from one dispatch site to three, verified against disk, including that the sealed-gate path structurally cannot be exec-wrapped because it returns to write the seal. Landed upstream at `d2f98891` and became AC-00.19 -- *every terminal path or refused outright, no partial* -- after they reframed it from a sizing note to a silent-wrong-answer: a flag honoured on handlers and skipped on catalogue rows leaves an operator believing secret material was injected.

Confirmed intent/vc's skills retraction from the consumer position, and supplied what they did not have: `~/.claude/skills/` is upstream of eleven committed AGENTS.md files, so a `--force` from a v2 estate writes `treeindex` back into all of them on the next sync. Also observed it had already happened inside this session invisibly -- `/in-session` loaded the skill WITH the treeindex rules at bootstrap, and by regeneration time it had none.

## Closed out

Five issues (0029, 0030 by cc; 0031, 0032 by vc; 0033 by cc), sweep #6 in two halves, two re-sweeps, docs to as-built, twelve repos level across 27 remote refs, CI green twice, 656 tests. **Paused with 0034 OPEN** -- a consumer-reported seal-reach defect from Lamplight, parked deliberately rather than missed.
