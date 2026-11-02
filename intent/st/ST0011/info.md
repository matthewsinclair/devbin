---
st_id: ST0011
title: Build, test, assemble, release cycle performance and optimisation remediation
status: WIP
created: 2026-10-31
completed:
---

# ST0011: Build, test, assemble, release cycle performance and optimisation remediation

## Objective

Cut the wall-clock of a release, from the decision to cut to a brew-installable artefact with no hand on the process in between, to the floor set by one honest run per platform, run once, in parallel, and nothing run twice anywhere: locally on this Mac, on kovacs, in CI, and through the assembly, notarisation and packaging stages that follow.

The thread is diagnosis first (hv, 2026-10-31): a root-and-branch review of the release cycle devbin's core gives every project that vendors it, read as built in Devbin, Utilz, Gtools, Intent, Laksa and Conflab, and measured from the record that already exists (CI run history, local seals and run logs, kovacs's logs); no new runs, no code. It records the full Socrates (CTO review) dialog, the measured baseline per project, the places the same work runs more than once, and a remediation plan with options ranked by minutes saved against confidence lost, for hv to choose from. Issue 0295 (a cut with no publish.url tags a commit nothing has tested and re-runs the suite on it) is the first measured instance and is subsumed here.

Fixed points hv named, each of which still has to earn its place on evidence of what it uniquely catches: the kovacs (Ubuntu) run stays, the full CI matrix is green on the exact commit that ships, and a full suite runs on this Mac before the cut asks to confirm. Notarisation happens on this Mac and is a stage of its own. Thorough testing is not the thing being cut; repetition is.

Two criteria every change must meet (hv, 2026-10-31): (a) a general overall reduction in both complexity and time, so a mechanism added to save minutes fails on its face, and a step removed counts twice; and (b) general applicability to all of hv's current and future dev projects, so the answer lands in devbin's core, reaches every project at its next vendor update with nothing per-project to set up, and carries no special case for any one project's shape.

Reach (hv, 2026-10-31): where a project does something bespoke, slow or redundant around the core (its own release driver, pre-push builds, post-cut scripts, derived builds, deploy gates), this thread has the authority to name its remediation, and those remediations are done in the fix phase that follows this diagnosis. The direction follows criterion (b): bespoke machinery retires into the core wherever the core can carry it, and a project keeps only what a config key cannot say.

## Context

**Measured baseline, 2026-10-29 to 2026-10-31 (evidence A to E, attached to this thread).** Six projects vendor one release core, byte-identical to Devbin HEAD in all six (0.1.18, source_commit a9b8cd7c). Wall-clock per release, over the release shas: Devbin v0.1.18, 78 min from the last code commit to the public tag (local cut 14.6, publish 56.3 waiting on a candidate matrix whose Ubuntu leg takes 32 to 42 min for the suite this Mac runs in 13 on 8 lanes, macOS 55 to 66, WSL 59; 818 billed-equivalent minutes per candidate, against 126 to 316 for any consumer's release). Gtools v0.8.3, 82 min from candidate to release (the cut 24, of which 9 the suite and 14 holding the terminal for the tag's macOS leg). Utilz 2.14.8, 56 min from candidate to tap, the cut itself under 3 min with notarisation inside it. Intent v3.2.8, 62 min from candidate to tap (kovacs green to release commit 26 to 34 min; post-tag 11 to 19 min of hand-sequenced halves). Conflab v0.6.2, about 5 min from bump to tap, on this Mac, with the bump and the tag pushed before any gate ran. Laksa has no release; its CI job takes 13 to 17 min for a suite that runs locally in 88 s, and its deploy compiles the prod release twice.

**Where the time is.** Not in the core's own steps, which take seconds, and not in runner queues, which are nil across the 95 runs read. It is repetition, in six forms. (1) The suite runs on a candidate and again on its stamped twin, four files and four lines apart, because the gates run after the stamp (ST0007 D38, chosen to avoid a cold rebuild in a worktree) and keep no record ("never already", so a dry run, a stopped cut and the real cut each run the whole suite). (2) Every tag push starts the same workflow twice on one sha, once for the push to main and once for the tag, in two concurrency groups; nine of nine releases in the record. (3) Each leg is serial behind the last by step order rather than data: the snapshot waits for gates, confirm, tag and push though it needs only the tag's commit; formula publish waits for the object step though it needs only the public tag; the ci wait follows the after step; the candidate matrix cannot start until the local suite ends, with a person in between. (4) Devbin's own candidate matrix is an order of magnitude dearer and three times slower than the same suite on this Mac. (5) After the tag, halves that do not depend on each other are sequenced by hand: Intent's macOS assets, Linux assets and tap; Devbin's formula publish, FAILED by construction under --yes, then brew upgrade and the switch. (6) Bespoke project machinery re-runs what it just required or just did: Intent's driver re-runs the five cargo steps and bats after requiring a green kovacs run of the same tree, and its pre-push hook clones and cold-builds the workspace once per remote; Gtools builds gtools-rs in release profile 12 times per release, 10 cold on runners with no cache; Laksa's deploy re-runs credo and the suite CI ran on the same commit, and reads no CI verdict; Conflab runs clippy at the commit and again in pre-flight, keeps three formula writers and calls the oldest. On 2026-10-29 the Devbin suite executed 13 times to ship three patch releases; Gtools's suite 12 times for three.

**What each run has caught (E, the ruling history).** CI Ubuntu: Linux-only reds 0151, 0180, 0223 (v0.1.14's RUSTUP_HOME), 0233 to 0238. kovacs: Intent 3.2.5 and 3.2.6 tags went red on GitHub for Linux-only faults a kovacs run would have found first; since the preflight was made mandatory, 17 runs in a week, 12 green, 5 red, two of them Linux-only cargo-test failures caught before a push; Devbin's K0116 red before the 0.1.16 cut. CI macOS: 0293 (the snapshot's check critic on the macOS job), and the bash 3.2 refusal proof runs nowhere else. WSL: blocks nothing by ruling (ST0008 D50). The local Mac suite: the operator's own pre-cut red runs (2026-10-29 at 06:14, 07:27, 13:04 and 13:14, each before a green cut). No record keyed on a sha exists anywhere in the core; the seal carries platform and run id, never the commit; GitHub's run list, read by ci-state, is the one sha-keyed verdict there is, and the core does not know kovacs exists.

**Constraints the design must respect.** The version lives in the tree (VERSION and sidecars) and is compiled into binaries; release.yml refuses a tag whose name is not VERSION's; the formula's own test asserts the version; a tag is never moved or deleted; the note's date and the generated views are committed; under publish.url the public snapshot is a third sha that no workroom run can stand for; notarisation needs the login keychain on this Mac; kovacs holds no clone and has 2 CPUs (30 min for Devbin's suite against 13 here); the workroom has no GitHub Actions; every project takes the core by vendor update, so the fix is one core change plus each project retiring what the core now carries.

## Work Packages

| WP    | Title                                                                                                                       | Size | Status      |
| ----- | --------------------------------------------------------------------------------------------------------------------------- | ---- | ----------- |
| WP-01 | Seal records its commit; gates remember a sealed green for (commit, platform)                                               | S    | Done        |
| WP-02 | The cut reorders and absorbs publish: confirm first, stamp, commit, candidate in every shape, one wait loop, tag on green   | S    | Done        |
| WP-03 | The core ships ci-state; release check refuses a test workflow whose matrix does not fire on candidate/                     | S    | Done        |
| WP-04 | Devbin's own workflow: tag trigger and Candidate verdict job removed, lanes from the runner's CPUs, WSL on the candidate    | S    | Done        |
| WP-05 | Remote legs: the release.legs key and runner; kovacs declared in Devbin's config                                            | S    | Done        |
| WP-06 | The macOS stage at the release commit, as a leg                                                                             | S    | Done        |
| WP-07 | Attach reads the candidate run: assets keyed on the release commit's sha                                                    | S    | Done        |
| WP-08 | Formula under the yes; assets mode with the cask verified                                                                   | S    | Done        |
| WP-09 | A Devbin release through the new shape, then the vendor sweep into the five consumers                                       | S    | Done        |
| WP-10 | Utilz retires tools/ci-state, post-cut and formula; estate as a recorded gate; macOS legs on candidate/                     | S    | Not Started |
| WP-11 | Gtools retires tools/ci-state and ci.wait; macOS job on candidate/; release.legs kovacs                                     | S    | Not Started |
| WP-12 | Intent retires its release driver, preflight scripts and hook build path into the core                                      | M    | Not Started |
| WP-13 | Conflab adopts the core's release: gates before any push, one confirm, one formula writer                                   | L    | Not Started |
| WP-14 | Laksa's deploy reads CI; the suite and the prod compile run once                                                            | S    | Not Started |
| WP-15 | Measure and re-read: RELEASE seal clock lines against the expected column; kovacs, lanes, the consumers' macOS legs         | S    | WIP         |
| WP-16 | Build artefacts cached by the hash of their inputs: nothing rebuilt that a recorded input hash already built (D67)          | S    | WIP         |
| WP-17 | A gate declares the platforms it runs on: inactive elsewhere, never failed (D69)                                            | S    | Done        |
| WP-18 | docs/assembly-and-the-build-cache.md: Devbin's Build Cache for Optimised Release Assembly, design and tech note plus how-to | S    | Not Started |

## Acceptance

Acceptance Criteria and Acceptance Tests are RENDERED into `acceptance.md`, which is a GENERATED VIEW -- a row authored there is discarded by the next sync. The contract is canon in this thread's model, and the verbs write it: `intent ac new` and `intent at new` mint a row, `intent ac edit` and `intent at edit` reword or re-cite one, and `intent ac satisfy|unsatisfy|descope|rescope|withdraw|reinstate` and `intent at green|red|na` move its state. This cover never restates them.

---

_Generated by Intent v3 from the thread canon. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
