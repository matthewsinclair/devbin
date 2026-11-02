---
generator: intent todo
---

# TODO

A DOING / TODO / DONE view, projected from steel-thread and work-package status: one row per steel thread, with its work packages nested beneath it. Generated -- change a status with the CLI, never by editing this file.

## DOING

- [-] ST0011: Build, test, assemble, release cycle performance and optimisation remediation
  - [x] 01: Seal records its commit; gates remember a sealed green for (commit, platform)
  - [x] 02: The cut reorders and absorbs publish: confirm first, stamp, commit, candidate in every shape, one wait loop, tag on green
  - [x] 03: The core ships ci-state; release check refuses a test workflow whose matrix does not fire on candidate/
  - [x] 04: Devbin's own workflow: tag trigger and Candidate verdict job removed, lanes from the runner's CPUs, WSL on the candidate
  - [x] 05: Remote legs: the release.legs key and runner; kovacs declared in Devbin's config
  - [x] 06: The macOS stage at the release commit, as a leg
  - [x] 07: Attach reads the candidate run: assets keyed on the release commit's sha
  - [x] 08: Formula under the yes; assets mode with the cask verified
  - [x] 09: A Devbin release through the new shape, then the vendor sweep into the five consumers
  - [ ] 10: Utilz retires tools/ci-state, post-cut and formula; estate as a recorded gate; macOS legs on candidate/
  - [ ] 11: Gtools retires tools/ci-state and ci.wait; macOS job on candidate/; release.legs kovacs
  - [ ] 12: Intent retires its release driver, preflight scripts and hook build path into the core
  - [ ] 13: Conflab adopts the core's release: gates before any push, one confirm, one formula writer
  - [ ] 14: Laksa's deploy reads CI; the suite and the prod compile run once
  - [-] 15: Measure and re-read: RELEASE seal clock lines against the expected column; kovacs, lanes, the consumers' macOS legs
  - [-] 16: Build artefacts cached by the hash of their inputs: nothing rebuilt that a recorded input hash already built (D67)
  - [x] 17: A gate declares the platforms it runs on: inactive elsewhere, never failed (D69)
  - [ ] 18: docs/assembly-and-the-build-cache.md: Devbin's Build Cache for Optimised Release Assembly, design and tech note plus how-to

## TODO

- [?] ST0006: devbin infra: apply, the Fly runtime leg, dmarc check, and the known-sender library
  - [ ] 01: infra apply: Fly end-to-end, DNS and Workspace emit an ordered record list
  - [ ] 02: infra mail dmarc check: the assertion leg, red on a silently missing domain
  - [ ] 03: Known-sender INVARIANT library, profile-overridable
  - [ ] 04: Fly runtime leg of check: certs, address agreement, release_command, staged secrets

## DONE

- [x] ST0001: Rationalise 5 ./bin/{{prj}} scripts into a reusable framework
  - [x] 01: Corpus analysis and framework specification
  - [x] 02: Project skeleton and BATS harness
  - [x] 03: Config schema and reader
  - [x] 04: Dispatcher and command resolution
  - [x] 05: Runtime library: the universal helpers fold
  - [x] 06: Sealed-gate subsystem
  - [x] 07: Help system: generated listing, authored detail
  - [x] 08: Built-ins: Gates (check, test)
  - [x] 09: Install, upgrade, doctor
  - [x] 10: Reference migration: Conflab
  - [x] 11: Fleet migration: Laksa, Baize, Lamplight
  - [x] 12: Documentation: README, help authoring, command-author guide
  - [x] 13: Pre-rollout end-to-end review gate (Fable)
  - [x] 14: Built-ins: Surfaces (server, iex, cli, repl)
  - [x] 15: Built-ins: Build and format
  - [x] 16: Built-ins: Data (db)
  - [x] 17: Built-ins: Docs and version
  - [x] 18: Built-ins: Shared, off by default
- [x] ST0002: Roll devbin out to the second fleet: eight more projects
  - [ ] 01: CANCELLED -- Multiplyer: fresh install, and the deps-drift protocol proven
  - [x] 02: Arca/arca_config: migrate scripts/, upstream of arca_cli
  - [x] 03: Arca/arca_cli: migrate scripts/, config's downstream
  - [x] 04: MicroGPTEx: fresh install, docs wired
  - [~] 05: CANCELLED -- Molt: install beside the product (was: migrate the 179-line launcher)
  - [ ] 06: PARKED -- Utilz: install beside the product dispatcher
  - [ ] 07: PARKED -- Pplr: migrate the twenty-script fleet
  - [x] 08: Prolix: MIGRATION -- elixir plus swift, the deploy image, last
- [x] ST0003: Add 'devbin infra' to help with prod estate configuration
  - [x] 01: Profile schema, parser, parse-time validation, and the unreviewed block
  - [x] 02: infra check: DNS and mail legs, authoritative reads, errors separated from drift
  - [x] 03: infra init: propose by standard then majority, deviations into unreviewed
  - [~] 04: infra apply: Fly end-to-end, DNS and Workspace emit an ordered record list
  - [x] 05: infra mail dmarc: parse, report, fetch, check
  - [~] 06: Known-sender INVARIANT library, profile-overridable
  - [~] 07: Fly runtime leg of check: certs, address agreement, release_command, staged secrets
- [~] ST0004: devbin infra: profile schema and estate verification
- [x] ST0005: Fix devbin install/upgrade and make use of Devel/opt/devbin
  - [x] 01: install/upgrade context-awareness, the dirty gate, and the install manifest
  - [x] 02: the staleness notice and the tty-gated upgrade prompt
  - [x] 03: fleet upgrade: dry-run default, install bytes, source rewrite
- [x] ST0007: devbin release core: one shared release sequence for every project that releases, devbin its first user
  - [x] 01: The release schema, opt-in activation, release check's declaration half, and the argument loop
  - [x] 02: Notes providers: releases (devbin's generator moved into lib/), changelog, command
  - [x] 03: release status: every step's postcondition, read-only -- the resume map
  - [x] 04: Steps 1 to 5 with --dry-run: resolve, pre-flight, stamp, commit, gates on the release commit
  - [x] 05: Steps 6 to 9 for object local and none: confirm, annotated tag, per-remote push, release object
  - [x] 06: object ci with object_wait, and step 11's CI verdict after the release
  - [x] 07: devbin adopts the core and cuts its next release with it
  - [x] 08: Utilz, then Conflab, then Intent last, adopt the core
- [x] ST0008: devbin on Windows through WSL 2: the prerequisite stated, LF held by the repository, shell-init for bash, proven inside WSL; no native port
  - [x] 01: Line endings: devbin's .gitattributes, the vendored copy's LF rule, and doctor naming CR bytes
  - [x] 02: The prerequisite stated in the README, and install hints naming apt
  - [x] 03: shell-init bash, both bodies from one source
  - [x] 04: The runtime against WSL's edges: the Windows PATH, and a checkout on a Windows drive
  - [x] 05: The suite under uutils coreutils
  - [x] 06: The Windows CI leg running the suite inside WSL, and the fixture smoke list
  - [x] 07: No pipeline broken by design: 0031's class fixed everywhere, and a scan that keeps it out
  - [x] 08: CI-built release assets attached by the core with one SHA256SUMS, release.verbs for a project's own cut, and a writers check that sees every writer
- [x] ST0009: devbin from Homebrew on macOS and Linux, with no source checkout: the formula, the tap, and projects vendoring from the brew install
  - [x] 01: The formula published to the tap, and each cut publishing it
  - [x] 02: Installed from the tap on this Mac (rhad)
  - [x] 03: Installed from the tap on kovacs (Ubuntu 26.04.1, aarch64)
  - [x] 04: Projects vendor from the brew install, and find it again
- [x] ST0010: devbin public: a new public repository from one audited commit of the product, under an open-source licence

---

_Generated by Intent v3 from the thread canon. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
