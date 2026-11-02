---
node: cc
name: Control Claude
role: control
session_id: dc68b304-b9a7-4ea8-87ad-f37a6678e499
heartbeat_at: 2026-09-14 22:11Z
status: paused
focus: "EOD, released at hv's wrap and holding. Nothing in flight, nothing claimed. Open from today: 0062's message half and 0056's census column, both built and held with their work archived as patches; 0063 designed, not started; 0060 measured for hv's ruling; the release-core thread approved, not minted; the whiteboard migration held, because on Intent 3.0.3 it drops hv's standing directives."
claims: []
---

# Control Claude (cc)

**Board cut 2026-09-14 at hv's wrap, released to `paused`.** The pre-fold board is archived verbatim at [`.history/20260914/wip-prefold-2158Z.md`](.history/20260914/wip-prefold-2158Z.md), in its own commit `492d1f1`, before this cut. Finished work lives in its commits and closed issues and is not restated here.

## DOING

- **Nothing in flight, nothing claimed.** Released at hv's wrap of 2026-09-14; the session ended. ST0003 and WP-03 stay vc's.

## TODO

- **0063, the partition in `run_all` -- designed, not started.** `command_option_candidates` becomes the one enumeration and `command_options` filters it by `option_active`. `run_all` refuses a verdict unless ran + skipped + inactive equals the candidates, and prints one count line on every path, naming members only on refusal. **Compute inactive from `option_active` on each candidate, never from `command_options`,** or a filter that drops an option counts it inactive and the sum still holds. Vehicles: a custom command with `enabled: false`; `test` in a project declaring no languages, whose shipped options are all language-scoped (count them from the catalogue, never type the number); a project handler, where the denominator is config-declared only; a unit stub dropping an active option. My `||`-fallback form is decided here, as vc ruled.
- **0059** (a publish sequence in the install manifest) and **0034** (re-measure against R1 to R9: `note_invocation` and `note_referent` in `lib/runlog` now cover part of it) -- unstarted.
- **0066** (the true and false words, and `-`, written out at thirteen sites) and **0067** (`release notes --help` writes) -- filed 2026-09-14, unstarted.
- **Not filed, a candidate:** doctor's `check_devbin_version` reports `not declared` when the config did not load -- a verdict about a declaration nobody could read. Seen in 0062's direct-invocation arm; reachable only past the dispatcher.
- **`tests/unit/dispatch.bats` carries one `@test` declaration doubled on its line**, since `48d486d`. Cosmetic -- bats reads the name up to the last `" {` and the body runs -- but it garbles the TAP name. A one-line fix.

### Parked by hv, not dropped (hv, 2026-08-28) -- carried unverified

- `unclaimed_digest()` hashes raw absolute paths while the renderer relativises only what it displays.
- F2 to F7 of `organize --default` untested against a real run.
- PATH 2: the hook has no notion of `armed`, so rc 0 from a disarmed library reads as a clean pass. Upstream's.
- `claims:` is empty by construction for maintenance work, so it is silent exactly where collisions happen.
- ARCA x2 have not landed and hold the only copy of their STP-to-Intent migration history.

## Holds

- **0062, the message half -- until 0062 is next picked up.** Its four tests were watched red and are archived as `.history/20260914/0062-message-half-tests.patch`, which applies to HEAD. Apply it; add one sentence in `lib/resolve` for both refusals, naming `project.languages` and its file; make `option_unavailable_reason` test `project_speaks` itself; mutate, run the full suite, close 0062.
- **0056, the census column -- until the review's four findings on the change are fixed.** Built, tested and mutation-checked, then held: its critic-shell review found it can still read `committed` over a seam git never looked at. The work is `.history/20260914/0056-census-column-work.patch` and the review is `0056-critic-findings.md` beside it. Build the pathspec from `vendored_scope`, ask status with untracked and ignored files shown, say only that the seam matches this checkout's HEAD, add the two missing arms, and watch them fail first.
- **Whiteboard migration -- until hv re-rules with the loss list in hand.** hv approved register-and-migrate on 2026-09-14 before this was known: on Intent 3.0.3 `wb migrate` drops hv's eleven standing directives, cc's non-standard sections and every lead paragraph, and silently drops inbox heading summaries. No undo. `.history/20260914/wb-migrate-3.0.3-findings.md`. hv's board is vc's pen.
- **The release-core steel thread (0064) -- until hv's next session.** hv approved a thread, design first; the wrap came before it was minted. The research is `.history/20260914/0064-release-orchestrator-research.md`.
- **0060 -- until hv rules.** Measured and recorded in the issue: `inherit_errexit` in `lib/helpers` passes 1057 of 1058, the one failure a handler reached on bash 3.2 through a narrow PATH.

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`.** The pre-fold board carried eighteen and they are in its archive; only what this node hit on 2026-09-14 stays here.

- **A PREFIX CHECK AT EXACTLY THE SHORTER FILE'S LENGTH CANNOT SAY "INTACT".** BSD `cmp -n <bytes of the shorter file>` hits end of file and exits 1 even when every compared byte matches, so my check on two appended issue bodies said CHANGED. Its control used a shorter limit and never reached the end. `diff` was the evidence. A control has a shape as well as a polarity, and that watch-out was already mine.
- **zsh does not word-split an unquoted `$var`, and the lesson was already written.** A path list in a variable reached git as one pathspec and the patch came out empty; only the refusal on an empty patch stopped a suite running over nothing. Script any list in bash, with an array.
- **A peer's relayed state can lag the tree by minutes.** Twice in an hour a peer described a state already overtaken. Re-read `git log` before acting on it.
- **A review of the uncommitted diff is worth the wait.** Both of 2026-09-14's critic-shell reviews found a real defect after the arms, the mutations and the full suite were all green -- one of them a false clean in the very column built to prevent one.

## Decisions

- **hv approved, 2026-09-14, in this session:** 0062 keeps the ST0002 WP-04 ruling that `project.languages` (gate scope) and Intent's list (project composition) are different facts; `log:` declines on `-`, `false`, `no` and `0`; 0060 is measured before it is ruled; the release core gets a steel thread, design first. They belong on hv's board, which is vc's pen, and vc has them in its inbox.
- **The status rule splits by occasion.** Across a compact, `active`; at the end of a session, `paused`. A rule stated without its occasion collapses the two.
- **D1 to D25 are in the store as ST0001's `design.md`.** Read them with `git show 355e5e9^:intent/st/COMPLETED/ST0001/design.md`; `intent st show` prints only a thread's cover.
- hv's standing directives live on `hv/wip.md`; vc holds that pen.
