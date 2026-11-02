---
node: hv
name: Hypervisor
role: hypervisor
session_id: none
heartbeat_at: 2026-09-02 23:28Z
status: active
focus: "END OF DAY. TWELVE ESTATES SWEPT AND COMMITTED at 367cd2d; INTENT IS DELIBERATELY BEHIND AND CLEAN AT HEAD -- its shared-artefact guard refused a vendored devbin TWICE, on two different lines, and was right both times. Reverted rather than bypassed on both. UNPUSHED: EVERYTHING AFTER 367cd2d -- a boundary, because the two counts this line carried before were each falsified by the commit that corrected the previous one. intent#0220 filed for the templates class. wip.md and restart.md globally folded -- both said DEVBIN IS PAUSED, which had been false all day"
claims: []
---

# Hypervisor (hv)

Human-driven. No session loop, `session_id: none`, heartbeat advisory. Maintained on hv's behalf by vc under hv's explicit grant; **last written 2026-09-03 09:15Z, and this write ADDS A DIRECTIVE rather than correcting a fact -- the first time that has happened.** Standing directives were **1342 bytes, 10 bullets** and are now **2241 bytes, 11 bullets**, re-measured after the write rather than predicted before it; **the change is hv's ruling of 2026-09-03 09:15Z on the guard-sequencing escalation, taken interactively, and it is recorded here because a block whose invariant is _unchanged_ needs an explicit note on the one occasion it changes.** Two different extractors report 12 and 13 lines and neither has lost anything: dropping the HEADING gives one, dropping the TRAILING BLANK gives the other. **Verify against the BYTE COUNT and the bullet COUNT, never the line count alone** -- on 2026-09-01 the line-count alarm fired on a second, harmless cause and sent a reader hunting for a directive that was never missing.

**This board is where hv's standing directives live.** They were scattered across the cc and vc boards until 2026-08-24, which meant a ruling's home was whichever agent happened to be in the room when it was made. Peers read this section at pickup.

## Standing directives

- **The next thread is hv's to set. Do not start one uninvited.** ST0001 and ST0002 both closed 2026-08-10.
- **Issues, never new steel threads, for maintenance-class work.** A project with no `intent/issues/` directory yet still manages issues that way.
- **Every migrated project is live.** Switches, deletions, publishing and deploy-affecting changes stay behind hv's explicit go. Full suites on the second fleet are the agent's to run.
- **At Lamplight, `test all` and the full mix leg are hv-run, never agent-run** (2026-08-09). That prohibition does NOT extend to the second fleet.
- **Do not touch Multiplyer again.** EOL, moved to `_Archive`; the salvage became Riffle.
- **Whiteboard matter reaches hv only through vc.** A write to `hv/inbox.<node>.md` is the record; vc surfacing it is the delivery. Not delivered until surfaced.
- **bash >= 5 is the floor** (issue 0022, reversing D9). macOS's `/bin/bash` 3.2.57 is refused, not targeted.
- **Cross-estate citations are qualified**: `<project>#NNNN` for issues, `<project>/<node>` for monikers, lowercase by definition. Unqualified stays legal same-repo.
- **Intent's devbin use is transitional**, dissolving at Intentv3's native Rust CLI. No durable machinery for its divergence.
- **vc commits the sweep pathspec in every tree** when a fleet sweep runs.
- **A guard body resolved live out of `INTENT_HOME` is EXEMPT from the pre-notice reservation** (ruled 2026-09-03 09:15Z, on vc's escalation of 2026-08-27). The reservation on fleet-blast-radius changes stands for everything else. It cannot bind here because **the commit IS the rollout**: there is no window between landing such a change and it being in force across every consuming estate, so no announcement can precede it and _sequence it and tell hv first_ is not a thing anyone can do. The 120s-to-0 tolerance change is ratified after the fact. **Report such a change promptly; do not hold it for permission that cannot arrive in time.** Attached and NOT fixed by this: `pre-commit.intent` in every estate is byte-identical to Intentv2's template, no v3 verb writes that file, and Intentv2 is frozen -- so the guard BODIES move with no ceremony available while the CARRIER cannot move at all.

## DOING

- **THE PUSH of EVERYTHING AFTER `367cd2d`, then INTENT'S RE-SWEEP.** Twelve estates are level at `367cd2d`. **Intent is the one deliberately behind**, clean at HEAD, because its `shared_artefact_build_guard` arm 10 refused the sweep twice: first a `cargo build --release` in `fullcycle` (real code, vc's, from this morning's `0050`), then the documentation EXAMPLE of the config key that replaced it. **Both refusals were correct and neither was bypassed.** Retry, read arm 10, revert again if it names a third line.

## TODO -- one upstream, the rest downstream, none of it devbin's own code

An index. **`intent/wip.md` carries the detail and is the authority**; two copies of an item list is how the last one drifted.

- **THE GUARDS ARE NOW PROVEN TO CATCH, and this section's own caveat is what prompted it.** It read _`guards: 4 ran, 0 skipped` is evidence they EXECUTE, not evidence they would catch anything, since nobody has driven one red here._ Driven 2026-08-28: **six red arms -- clock A, B and C, header, append-only, canon-ignore -- every one refused with rc 1 and HEAD UNMOVED**, each naming its own check, against a **green control** that landed once its stamp came off `date -u`. **The residue is named with the result** (a fabricated stamp carrying `Z`, in the past, monotonic, still passes all three clock checks) at `vc/.history/20260828/devbin-guard-red-drive.md`.
- **FOUR ISSUES ARE OPEN AND NONE IS RULED WORK** -- read live from `intent issues list` at 2026-09-02 22:13Z, not carried: `0034` `0036` `0039`, plus `0035` which hv PARKED. **Nine closed today by fix**: `0042` `0045` `0046` `0047` `0048` `0049` `0050` `0051` `0052`, and `0053` `0054` were filed and fixed within the hour. `0055` is filed and NOT fixed: a run log is stamped from the LOCAL clock with no zone while `fleet audit` renders UTC with a `Z` -- one hour apart today, zero for half the year, so it is correct in winter and silently wrong in summer, in the repository where the whiteboard clock guard lives. **The old wording of this line follows, because its warning is still the right one.** It read: EIGHT ISSUES ARE OPEN, ONE OF THEM `high` -- read live from `intent issues list` at 2026-09-02 18:13Z, not carried: `0034` `0035` `0036` `0039` `0042` `0045` `0046` `0052`. **FIVE CLOSED TODAY BY FIX**: `0047` `0048` `0049` `0050` `0051`, the entire `fullcycle` block, on hv's rulings of 15:55Z. **`0052` is the high one and it is the reason to distrust this whole section's history**: CI had been red on `main` since 2026-08-27, unread through the entire 0.1.0 release, and the TAGGED commit had never run CI at all. Now green on all four jobs. **This line has now been wrong seven times in seven days**, always in the section peers are told to trust, which is why the enumeration is dated and the count is stated separately -- a list and a count that disagree is a caught error; a list alone is a silent one. **`0035` was never "missing a directory"** -- v3 files to the canon store; the residue under `intent/issues/` is v2 and is **2 OPEN / 34 CLOSED**, not the flat 34 this board carried until today.
- **DEVBIN'S PARKED WORK IS LARGELY DONE.** The globalfold landed at `2fc4e0d` across all three snapshot documents; the three boot findings are filed; the two orphan writes are explained as Intent 3.0.0 output and committed. **THE FLEET RE-VENDOR IS DONE.** Measured live 2026-09-01 17:15Z by `bin/devbin fleet audit`, not carried: **THIRTEEN estates at ONE seam** -- source `08f51b754902`, digest `2a49b1d03240` -- as at 2026-09-01 17:15Z. **SUPERSEDED**: v0.1.0 rolled to eleven estates at `e22d9a3` on 2026-09-01; Intent sits at `0b7b1b3`; Intentv2 is FULLY FROZEN by hv's ruling of 2026-09-02 and is no longer reported as drift. Six further commits are unpushed, so no estate carries today's fullcycle work. The four-way split this line used to carry (`54996d4` 1 behind; `eecf4c0` 3; `96fb408` 4; `4ac3925` Gtools 5) is HISTORY, kept only because the lesson below is attached to it. **The `dep` and `worktree` rows in that audit are NOT estates** -- the vendored `arca_*` copies sit at `4dc899de522b` and three read `UNRECORDED`, but they arrive through `mix deps` and Lamplight's worktrees, never through a re-vendor. Counting them as fleet drift would re-import the exact over-wide reading this board has already corrected twice. **The "split 7/6" I wrote on this board at 16:12Z was never true**: I mapped thirteen estates onto two groups when the generated table in front of me already showed four digests, and in doing so I put a coarse grouping into the section I had just corrected for being stale. The number was wrong, not expired. **THE NEWEST INSTALL IS THE FURTHEST BEHIND** -- Gtools was vendored at 15:47Z from a commit dated the previous afternoon, so a fresh install is five commits back while two estates re-vendored an hour later are one. The live table is `intent/docs/devbin-users.md`, which is GENERATED (`bin/devbin fleet doc`) and carries its own expiry stamp -- and a stale stamp goes to hv, never silently to a rebuild. **The `st attach` ruling is WITHDRAWN, and the withdrawal is the finding** (hv, 2026-09-02): `intent st organize` was RETIRED in Intent v3, so the `54 unclaimed` this board carried came from a command that no longer exists and was never re-measured. There is no number here to rule on.
- **THE FLEET WAS NEVER THREE-WAY, and both this board and vc's said worse than the truth.** Three distinct `source_commit` stamps, but only **two seam states** by digest. **Counting stamps counts re-vendor events, not divergence.**
- A Prolix deploy carrying two migrations, with an unbuilt Dockerfile change riding along.
- Two committed credentials at Prolix, outside the existing `flysql` ruling.
- Prolix ST0028, WIP and half done -- the dependency half has not started.
- arca_cli's credo, never sized.
- Deploy-build proofs pending, owner-run: Conflab, Laksa, Lamplight.
- Fleet housekeeping, no urgency: redundant `log:` restatements at five projects; Baize's `db reset`.

## Watch-outs

- **A ruling about one project is not a fleet ruling.** The same call was right for one project and wrong for another inside a day. The general form of this and every other lesson is in `intent/llm/LESSONS.md`.

## Decisions

Ratified 2026-08-24, in session, listed because the record has to outlive the session that made it:

| Ruling                                                                                         | Where it landed       |
| ---------------------------------------------------------------------------------------------- | --------------------- |
| 0014 resolves as option B -- devbin owns the git axis's shared half, not the read half alone   | `lib/helpers`         |
| 0015 closes with rc unchanged; a guard that quietly changes a verdict is a bypass              | `print_run_verdict`   |
| 0018 resolves by RETIRING devbin's own `cmd/check` handler, not by documenting the divergence  | `cmd/.lib/shell-gate` |
| 0019's verdict channel is fixed by EXTENDING the promotion, not by a sentinel in `.errors`     | `run_gate`            |
| 0021: upgrade's exit status stays 0 when files were refused -- it answers "did I complete"     | `lib/cmd/upgrade`     |
| 0024 resolves as option A -- doctor ANNOUNCES shadowing; the only option that closes the class | `lib/cmd/doctor`      |

Earlier rulings are in the closed threads' own records and in `design.md` (D1 to D24).
