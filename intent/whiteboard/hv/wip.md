---
node: hv
name: Hypervisor
role: hypervisor
session_id: 13270b02-fc50-4d4e-9ce3-c73346487bcb
heartbeat_at: 2026-10-29 19:31Z
status: active
focus: "devbin 0.1.18 is published, devbin's first public release; the queue is intent/wip.md."
claims: []
---

# Hypervisor (hv)

## DOING

_(none)_

## TODO

- Deploy-build proofs, owner-run: Conflab, Laksa, Lamplight (carried from 2026-09-02, not re-verified). (edited)
- Prolix: ST0028's dependency half (AC-2.1 to 2.4) is unstarted while its lockfile moved outside it, and the cf06d8e Dockerfile change is unbuilt; prolix's node to settle. (edited)
- Six estates carry log: lines restating the builtin default; check no test or tool reads config.yaml as text before removing any. (edited)
- Baize's authored db reset drops with no confirmation or prod refusal, while its seed arm is prod-gated; baize's node to fix before its first deploy. (edited)
- hv to decide: whether devbin declares formatters, since no commit-time guard checks staged markdown here (check format covers it at run time). (edited)
- ST0006 is in triage with no objective or design; WP-01 (infra apply through flyctl) is its one live write. Starting it is hv's (directive 1), its first live drive too (directive 3). (edited)
- 0.1.6 residue for hv: Anvil and arca_notionex await hv's word; laksa/dc asks whether pristine reaches the Ubuntu 26 notice and Elixir dependency warnings; Utilz's bash 3.2 gap is utilz-vc's. (edited)

## Holds

_(none)_

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
- Intentv2 and Multiplyer are DEAD. Ignore them entirely -- no scans, no sweeps, no counts, no reports, no re-verification (hv, 2026-09-22: "Intentv2 and Multiplyer are dead. Ignore those entirely. I don't want a second of time wasted on them"). This extends directive 5, which stays as the record of Multiplyer's EOL. The census still lists _Archive/Intentv2; exclude it without discussion.
- Batch releases. A release is not cut for a minor thing on its own, and the next release carries everything open, so there is no per-issue scheduling question to put to hv. hv, 2026-09-23 09:20Z, on 0.1.8: "EVERYTHING is going into the next release. I don't want to be constantly making new releases for minor things. Just ship the lot in the next release. The end."
- A CLIENT's name, or the name of a client's project, never appears anywhere in devbin: the tree, issues, boards, canon events, commit messages or release notes (hv, 2026-10-05: "mentioning CLIENT names and projects is an UNFORGIVABLE FIRING SQUAD offence"). A session named after client work is a client name too; in devbin's record it is "another estate's session". hv's own projects may be named in docs and commits, but never by their local directories, never as a dependency, and never in shipped code (bin/devbin and lib/).
- Anything released through Homebrew follows dev, opt, brew as dev, stage, prod (hv, 2026-10-24): the maintainer works in a dev checkout, publishes a working copy to opt to keep the bleeding edge (dev) apart from what works (opt), and the brew formula is the one prod publish. A user installs from brew and seeds projects from the brew install; dev and opt are maintainer-only, named only where a doc speaks to the maintainer of a dev checkout, never as the way a user installs. Applies to devbin, Intent, Utilz and every other formula.

## Watch-outs

- **A ruling about one project is not a fleet ruling.** The same call was right for one project and wrong for another inside a day. The general form of this and every other lesson is in `intent/llm/LESSONS.md`.
- hv's TODO is an index; intent/wip.md is the queue. (edited)
- Re-drive guards only in a quiet tree: under live peers an arm aborts on their staged paths and the drive reports more coverage than it got. (edited)

## Decisions

- Rulings before 2026-08-24 are D1 to D25 in ST0001's design: intent st show ST0001 design. (edited)
- dc does devx work (hv, 2026-09-16); where the line with cc falls is hv's to draw. (edited)

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
