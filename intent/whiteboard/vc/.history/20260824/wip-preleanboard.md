---
node: vc
name: Validation Claude
role: validation
session_id: a334a88e-3db4-4b55-8213-abc63a106cc8
heartbeat_at: 2026-08-24 16:58Z
status: active
focus: "resumed after compact, bootstrapped, holding. Nothing open, no claim held. The next thread is hv's to set"
claims: []
---

# Validation Claude (vc)

## DOING

- Nothing in flight, nothing open in the tracker, no claim held. Day one archived to `.history/20260824/` in two halves: the morning (boot, upgrade audit, the source_commit sweep, devbin#0022's bash floor) and the afternoon (the whole queue emptied, sweeps #3 and #4).

## TODO

- **The next thread is hv's to set.** `intent issues list` says `no open issues` for the first time since this node existed. Do not start one uninvited.
- **Read a work item against what has landed since.** Six of today's eight closes changed their own issue's framing while being worked -- 0018 refuted its own hypothesis, 0019's second half turned out already built, 0015 reshaped around a detector added a week after it was filed. The issue is the question, not the answer.

## Watch-outs

- A restart brief is a snapshot, not a record. Verify its open-set and claims against disk before planning from it -- on this node's first boot the brief listed a closed issue (0004) as open and omitted an open HIGH (0016) entirely.
- **WHEN A FINDING LOOKS FLEET-WIDE, CHECK WHETHER IT IS DEVBIN-ONLY FIRST.** Four times in one day the outlier was this tree, and its own `bin/.devbin/` config was where it showed: a `cmd/check` handler standing at a built-in name (0018), three `run: devbin-internal-*` targets naming nothing and never executing (0018), and `grammar: generic` on the critic gate leaving it structurally unable to fail on an empty examination while every other install carried the counter (0019). All in the config the documentation points at as the WORKED EXAMPLE, and every one found by reading before proposing rather than by a gate going red.
- AN INSTRUMENT GREEN OVER THE WRONG BASELINE OR THE WRONG SCOPE certifies nothing about the difference that matters. Measured repeatedly: vendor-green (tree-vs-SOURCE) says nothing about manifest state (tree-vs-INSTALL-TIME); a skills-sync green scoped to SKILL.md stood over unpropagated scripts; and at Intent `bin/devbin vendor` resolves to THEIR handler answering tree-vs-MANIFEST, which nearly went into sweep #3 as a convergence check (devbin#0024). Name an instrument's baseline AND scope before trusting its green.
- A RELEASED TAG IS EVIDENCE ABOUT A RELEASE, NEVER ABOUT A DEPLOYMENT. Intent's estate ran a symlink resolved into a working tree, so the fleet had never run the tag it appeared to be running. Same class as devbin's source_commit rationale: a version string cannot separate two installs from one release (intent/vc, 2026-08-24).
- AN IDENTICAL OBSERVATION CAN SUPPORT OPPOSITE INFERENCES, AND THE OUTPUT CANNOT SEPARATE THEM. An empty issue list reads as "different tracking convention" or as "the feature post-dates the project"; "not found" reads as "does not exist" or as "the resolver never looked". The output is honest and complete in BOTH states; only something outside it separates them.
- A PRECISION FIGURE IS A CLAIM ABOUT THE CORPUS AS MUCH AS ABOUT THE INSTRUMENT. "100% precision over 112 identifiers" was arithmetically true and evidentially worthless: the measuring corpus contained no negation sentences, so it could not exhibit the failure mode. A clean score over a sample that cannot contain the failure is the same nothing as a green over zero examined files.
- MEASURE A CONSUMER-FACING INSTRUMENT'S PRECISION IN A CONSUMER ESTATE. The upstream contains everything the downstreams only reference, so a check about project-local existence run in the upstream reports clean BY POSITION, not by health. D12 is the same trap here: the source checkout runs lib/ in place, so anything validating vendored-path existence must stand in a scratch INSTALL (D24). `devbin vendor` was built under this rule and only measured for real once the fleet carried it.
- CONTROL FIRST, AND VERIFY BOTH ARMS OF A GUARD. Run the positive control BEFORE trusting any zero, and prove a guard fires AND that the normal path stays clean. Today: the 0014 test file opens with a control asserting its worktree fixture really exhibits the trap, without which every later test would silently pass against a broken implementation; the empty-corpus guards were driven red and green; and the promotion was driven under both grammars.
- A NEW TEST PROVES NOTHING UNTIL IT HAS GONE RED FOR THE RIGHT REASON. Three of today's caught their own author: one passed on exit 127 (command not found) rather than a refusal; one could not tell "wrote nothing" from "does not exist"; and one shadowed `doctor` itself, so the handler ran INSTEAD of doctor and the assertion compared two empty strings.
- A COMMIT LOOP THAT REPORTS `git log -1` CANNOT TELL A COMMIT FROM A BLOCKED ONE. Sweep #3's first pass printed a hash for all eleven trees and TWO had not committed -- Intent and Intentv2, both carrying substantial pre-commit gates -- with their changes staged while the loop reported their PRE-EXISTING HEAD. Read the commit's exit status, or verify state after.
- A SWEEP'S COMPLETENESS IS A CLAIM ABOUT ITS ENUMERATION. Both earlier sweeps covered ten installs taken from the roster of estates with vc nodes; the filesystem holds NINETEEN. Enumerate from disk, then exclude deliberately and say why -- "not visited" and "visited and excluded" must not be the same silence (devbin#0023).
- DOCTOR GREEN MEASURES THE FRAMEWORK'S HEALTH, NOT WHETHER THE CONSUMER STILL WORKS. Sweep #1's report was accurate on every claim it made and Baize's suite was red from the moment it landed: a vendored contract change broke a NON-vendored consumer test, which no per-file replace could update and no skip-list could flag. A behaviour-changing sweep brackets the coupled consumer suite where one exists, and probes the delivered behaviour per install.
- A PERMANENTLY-RED GATE IS THE MIRROR OF A FALSE GREEN. `check lint` had been failing on committed code for a week and nobody was blocked by it, which is how it stopped being read. Both end with nobody trusting the verdict.
- **NEVER READ A TEST RUN BY GREPPING `^not ok`.** It cannot see a failure that emits no such line. `grep -vE "^(ok |not ok |1\.\.|#)"` must print nothing -- `usage-rules.md` says so and this node had to be caught by the rule rather than by a defect.

## Decisions

- (2026-08-24) **hv: whiteboard matter reaches hv only through vc.** The hv node is scaffolded for durable escalation; vc is the named reader of `hv/inbox.*` -- a write there is the record, vc's surfacing is the delivery.
- (2026-08-24) **hv: vc commits the sweep pathspec in every tree.** Executed for all four sweeps.
- (2026-08-24) **hv: issues, never new steel threads, for this class of work.** And a project with no `intent/issues/` dir yet still manages issues that way; the absence dates the project against the feature.
- (2026-08-24) **hv: D9 REVERSED (0022).** bash >= 5 required, older refused with a brew remediation. The `&`-in-replacement rule SURVIVES -- the floor spans 5.0/5.1 and 5.2.
- (2026-08-24) **hv: the 0020 citation convention is adopted** -- `<project>#NNNN`, `<project>/<node>`, LOWERCASE by definition, unqualified legal same-repo.
- (2026-08-24) **hv: Intent's devbin use is transitional**, dissolving at Intentv3's native Rust CLI. No durable machinery for its divergence.
- (2026-08-24) **hv: dc is the DevX Claude sessions at the other projects.**
- (2026-08-24) **hv: 0014 resolves as option B** -- devbin owns the git axis's SHARED half; the read half alone was refused as solving the part nobody gets wrong.
- (2026-08-24) **hv: 0018 resolves by RETIRING devbin's own `cmd/check` handler**, not by documenting the divergence. The corpus sweep was kept and became a declaration in config rather than an accident of tree shape.
- (2026-08-24) **hv: 0019's verdict channel is fixed by EXTENDING THE PROMOTION, not by a sentinel in `.errors`.** A sentinel would have inverted every `[ -s ]` reader in the fleet at once -- a semantic change, not a migration.
- (2026-08-24) **hv: 0015 closes with rc unchanged.** `print_run_verdict` annotates and never suppresses; a guard that quietly changes a verdict is a bypass wearing a safety label.
- (2026-08-24) **hv: 0024 resolves as option A** -- devbin ANNOUNCES the shadowing via doctor. Not a rename, and not a demand that consumers retire anything: A is the only option that closes the class.
