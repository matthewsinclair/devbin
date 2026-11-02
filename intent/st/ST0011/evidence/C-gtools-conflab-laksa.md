# Evidence C: the build, test, assemble and release cycle in Gtools, Conflab and Laksa

Read-only anatomy, taken 2026-10-31 (clock read 07:27Z). Nothing was run that builds, tests, signs, notarises, writes a repository, a remote or a keychain. Every claim cites `Project: path:line`; log lines are quoted from the seals devbin left under each project's `tmp/`. The three projects vendor the same devbin core: manifest `devbin_version: 0.1.18`, `source_commit: a9b8cd7c...` in all three (`Gtools: bin/.devbin/manifest.sha256:4-6`, `Conflab: bin/.devbin/manifest.sha256:4-6`, `Laksa: bin/.devbin/manifest.sha256:4-6`), and in all three every file under `bin/.devbin/lib/` and `bin/devbin` itself is byte-identical to Devbin's working tree at `7ab68c95` (a `cmp` over every vendored file found no difference in any of the three). So section 6 of each project is short: there is no local divergence of the core anywhere; the differences are entirely in each project's own `bin/.devbin/cmd/` handlers and `config.yaml`.

Shared core facts the three sections lean on:

- The cut's step order is fixed: `Devbin: lib/release.steps:94` `_RELEASE_STEP_NAMES=(resolve pre-flight stamp commit gates confirm tag push snapshot candidate publish object after ci)`.
- Default gates are `check all` then `test all` (`Devbin: lib/config.reference.yaml:580-582`), run on the release commit after it is made (`Devbin: lib/cmd/release:1029-1031`: "In place, on the release commit ... Never `already`: the gates leave no postcondition the repository can show"), which is why a resumed cut re-runs them in full.
- The stamp step runs `version set`, then every `derived:` command, then dates the note (`Devbin: lib/cmd/release:944-958`); the commit step commits exactly the dirty owned paths as `release: <tag>` (`:1004-1008`).
- The `ci` step asks `ci.query` about the release commit with `DEVBIN_RELEASE_TAG` set, keeps waiting on `pending` or `none` up to `ci.wait`, polling every 15 s (`Devbin: lib/release.steps:1524-1525` `RELEASE_POLL_SECONDS ... :-15`), each ask bounded at the time left and never below 15 s (`:1495`), and only `green` exits 0 (`Devbin: lib/cmd/release:1520-1543`).
- Two switches exist in this core that none of the three projects declares: `ci.base` (pre-flight refuses unless CI is green on the base commit, default false) and `ci.tag` (false: do not wait for the tag's run) (`Devbin: lib/config.reference.yaml:584-585`; implementation `Devbin: lib/cmd/release:845-905` and `:1512-1515`).
- A project handler in `bin/.devbin/cmd/<name>` displaces the built-in of the same name (`Devbin: lib/resolve:669` "project handler, auto-discovered -- shadows a built-in of the same name"; `Devbin: lib/cmd/macos:5-6` "A project's own `macos` handler or `run:` still wins, as for any built-in"), and the built-ins `release`, `macos` and `formula` are opt-in besides (`Devbin: lib/cmd/release:3-6`, `lib/cmd/macos:3-6`, `lib/cmd/formula:1-5`).

---

## Gtools

### 1. The release, end to end

What a person does (`Gtools: docs/releasing.md:7-17`): a node writes the CHANGELOG section `## [X.Y.Z] - unreleased`; optionally `bin/devbin release --minor --dry-run`; vc runs `tools/install-proof` on the candidate as a booked proof; the fleet is held with a clean tree; hv runs `bin/devbin release --patch|--minor|vX.Y.Z` at his own terminal and answers the confirm prompt; after the cut, `bin/gtools app install` from a checkout at the tag, and `brew upgrade gtools` on each brew machine. Before the cut, on 0.8.3, the candidate commit was also tested on GitHub by `workflow_dispatch` (run 41127185022, macOS leg included), on kovacs and on gyges (`Devbin: intent issues show 0295`, "Measured" section).

The cut (`bin/devbin release`, devbin's core, enabled at `Gtools: bin/.devbin/config.yaml:228-229`; declaration `:272-282`):

1. resolve, pre-flight (core): branch main, two remotes (`local`, a bare mirror, and `upstream`, GitHub: `Gtools: docs/maintaining.md:27`), CHANGELOG section present, `gh` signed in, `tmp/` ignored. `ci.base` is not declared, so CI on the base is not asked.
2. stamp (core + project `derived:`): `version set` writes `VERSION` and the one sidecar `native/rust/Cargo.toml` (`Gtools: bin/.devbin/config.yaml:26-27`); then the three `derived:` commands in order (`:274-277`):
   - `tools/lock-sync`: `cargo metadata --format-version 1` rewrites `native/rust/Cargo.lock` (`Gtools: tools/lock-sync:73`), the diff is refused beyond the members' version lines (`:78-83`), prints the lock path.
   - `bin/devbin build` (project handler `Gtools: bin/.devbin/cmd/build`): the stamp mismatch is detected (`build: gtools-rs does not match its source: native/rust/Cargo.lock, native/rust/Cargo.toml changed since it was stamped`, `Gtools: tmp/release/20261030-2154.RELEASE.out:8`), inputs are touched, `cargo build --release` runs (`Gtools: bin/.devbin/cmd/build:214`); 0.8.3 took `Finished \`release\` profile [optimized] target(s) in 13.95s` (`...RELEASE.out:12`), then the content stamp is written (`cmd/build:228-230`).
   - `bin/devbin build cms`: `mix deps.get --only prod`, then `mix compile --force --warnings-as-errors` under `MIX_ENV=prod`, then the CMS stamp (`Gtools: bin/.devbin/cmd/build:262-271`); `Compiling 45 files (.ex)` (`...RELEASE.out:43`).
   - The CHANGELOG heading is dated.
3. commit (core): `release: v0.8.3`, 4 paths (`CHANGELOG.md`, `VERSION`, `native/rust/Cargo.lock`, `native/rust/Cargo.toml`; `git show --stat v0.8.3`). The pre-commit hook runs here: Intent's chain (its guards, the critic gate, doctor) plus Gtools' five project guards declared at `Gtools: intent/.config/config.json:10-46`: `bin/.devbin/cmd/build --check`, `bin/gtools engagement check`, `bin/gtools risks check`, `bin/gtools scrub --staged`, `bin/gtools design theme --check` (`Gtools: docs/maintaining.md:7`). The log shows them: `staged-format-guard: ok`, the register, the risk registers, the client-name scrub ("nothing in 4 added line(s) ... names a client"), no-Python, the theme, `guards: 6 ran ... project: 5 ran`, four critics, `intent doctor gate: estate clean` (`...RELEASE.out:46-62`).
4. gates (core, defaults): `bin/devbin check all` then `bin/devbin test all`, on the release commit.
   - `check all` = 13 of 15 options (two inactive: `compile` and `deps`, elixir not being a declared language): health (`bin/gtools doctor`), md and deadlinks (each via `cmd/.lib/after-build`, which runs `bin/devbin build` again first: `Gtools: bin/.devbin/cmd/.lib/after-build:27-28`; a no-op at `0.00s`, `...RELEASE.out:185,195`), register, risks, theme, shell (shellcheck), clippy (`cargo clippy --workspace --all-targets --manifest-path native/rust/Cargo.toml -- -D warnings`, `Gtools: bin/.devbin/config.yaml:192`; `Checking gtools-rs ... Finished \`dev\` profile ... in 1.34s`, `...RELEASE.out:230-231`), format, autotests, targetdir, toolchain, critic (`...RELEASE.out:283` "13 of 15 check options ran"). Wall: 21:55:16Z to 21:55:32Z by the seals' mtimes under `Gtools: tmp/check/20261030-2154.*` (local mtimes 01:55:16 to 01:55:32 at UTC+4).
   - `test all` = `suite` (`bin/gtools test --strict`, `Gtools: bin/.devbin/config.yaml:108`) and `app` (`bin/gtools app test --unsigned`, `:122`); `rust` is `in_all: false` because the suite already runs the crate's tests (`:124-135`). The suite copies `native/rust` without `target/` into `$TMPDIR/gtools-test-native/`, checks the lock with `cargo build --locked`, builds `gtools-rs` through `bin/devbin build`, runs `cargo test --locked` (`Gtools: docs/testing.md:43`), builds a copy of the CMS, then ExUnit `max_cases: 16`: `built: ... gtools-rs from native/rust (sha256 ee539cadeec7, 43 files) ... its Rust suite passed 260`, `built: the CMS from native/cms and bin/`, `Finished in 470.4 seconds (279.6s async, 190.8s sync)`, `Result: 868 passed`, `overhead: 1.09x -- 515s of GATE wall against 470.40s of reported test time` (`...RELEASE.out:293-304`). Then `xcodebuild test -scheme Gtools` (Debug, locally signed with `-allowProvisioningUpdates`: `Gtools: bin/gtools_app:241,330-333`): `Test run with 123 tests in 19 suites passed after 0.453 seconds`, `GtoolsTests passed in 18.5s` (`...RELEASE.out:310-311`). Wall for `test all`: 21:55:33Z to 22:04:27Z.
5. confirm (core): the prompt lists tag, two pushes and the release object (`...RELEASE.out:322-327`).
6. tag (core): annotated `v0.8.3` at the release commit, message the CHANGELOG section.
7. push (core): the release commit to `main` then the tag, to `local` then `upstream`, each read back (`...RELEASE.out:342`). The push to `upstream` is what starts CI: two runs on the same sha two seconds apart, 41135646272 (push to main, 22:04:45Z) and 41135649951 (push of the tag, 22:04:47Z) (`gh run list`, read-only).
8. snapshot, candidate, publish (core): skipped, no `publish.url` (`...RELEASE.out:343-345`).
9. object (core, `object: local`): `gh release create v0.8.3 --verify-tag --title ... --notes-file ...` (`Devbin: lib/cmd/release:1393-1394`); no assets, no `release.assets.workflow` declared ("No binaries", `Gtools: bin/.devbin/config.yaml:270-271`; `Gtools: docs/releasing.md:35`).
10. after (core runs the project's one `after:` line): `bin/devbin formula publish`, devbin's formula built-in in `source` mode (`Gtools: bin/.devbin/config.yaml:291-293`): renders `packaging/homebrew/gtools.rb` filling `@@TAG@@` and `@@REVISION@@` (`Gtools: packaging/homebrew/gtools.rb:20-22`), clones the private tap into a temporary directory, commits and pushes, taking the confirm step's yes through `DEVBIN_RELEASE_CONFIRMED` (`...RELEASE.out:330-332` "confirmed at the cut of v0.8.3, so it is pushed without a second question"). No cask: Gtools ships no app through brew; brew builds from the tag's checkout on each machine (`gtools.rb:50` `system "bin/gtools", "install", "--prefix", libexec, "--managed-by", "brew"`), which compiles gtools-rs and the CMS again per brew machine.
11. ci (core + project `ci.query`): `tools/ci-state <sha>` with `DEVBIN_RELEASE_TAG=v0.8.3` reads only the tag's runs of `ci.yml` (`Gtools: tools/ci-state:67-69,97-99`), each `gh` call bounded at 15 s (`:43`), waited up to `ci.wait: 45m` (`Gtools: bin/.devbin/config.yaml:278-280`, chosen as the macOS job's own `timeout-minutes`: `:257-260`). 0.8.3: `ci.query answers green for v0.8.3 (79c9233d1e08): run 41135649951` (`...RELEASE.out:348`); the run went 22:04:47Z to 22:18:29Z; the cut's log closed at 22:18:37Z.

Signing, notarisation, packaging: none. The app is "built where it runs (no Developer ID)" (`Gtools: docs/releasing.md:35`); CI builds it `--unsigned` (`Gtools: .github/workflows/ci.yml:232,235`); the local `app test` signs with the Apple Development identity only (`Gtools: bin/gtools_app:236-241`). No `.pkg`, no `.zip`, no attach. The macos built-in is not enabled.

After the cut: `brew update && brew upgrade gtools` on each brew machine, `gtools cms restart --all` (`Gtools: docs/maintaining.md:43`); `bin/gtools app install` from a checkout at the tag in a GUI session (`Gtools: docs/releasing.md:14`). The export to the public repository, `tools/publish-public`, is a separate by-hand step and not part of the cut (`Gtools: docs/maintaining.md:69`).

Measured wall for 0.8.3 (UTC): candidate `41c283a8` committed 20:51Z; its push run 41127163812 (Linux, 20:56:31Z to 20:57:49Z) and the dispatch run 41127185022 (macOS included, 20:56:41Z to 21:11:16Z, macOS job 14m30s); kovacs and gyges runs in the same window (not measurable from this machine); localfold and compact commits 21:31Z to 21:43Z; cut: stamp 21:54Z, release commit 21:55Z, gates 21:55Z to 22:04:27Z, push 22:04Z, CI green 22:18:29Z, done 22:18:37Z. Candidate landing to release done: about 87 minutes; the cut itself 24.5 minutes, of which gates 9.2 minutes and the CI wait 13.7 minutes. The release commit differs from the candidate by the four stamp lines (`git show --stat v0.8.3`), and from the commit it sits on, `b4232187`, by the same four; between `41c283a8` and `b4232187` sit nine whiteboard or canon commits and one `intent/wip.md` commit (`git log --stat 41c283a8..v0.8.3`), none of which any job reads.

The day before (seals under `Gtools: tmp/release/`): 0.8.0's first cut stopped at gates (`gates FAILED gate 'check all' failed (exit 1)`, `20261029-1455.RELEASE.out:360`) and the resumed cut re-ran `check all` and `test all` whole (`427.2 seconds ... 843 passed`, `20261029-1458.RELEASE.out:241-243`; stamp and commit rows `already`, `:279-280`); 0.8.1's first cut stopped inside `test all` (`20261029-1702.RELEASE.errors`, 84 bytes) and the resumed cut re-ran the suite (`547.2 seconds ... 845 passed`, `20261029-1711.RELEASE.out:242-244`); 0.8.2 ran once (`501.7 seconds`, `20261029-1908.RELEASE.out:298`). Each resumed cut costs the whole gates step again because the step records no postcondition.

### 2. Every point the gates or a build or test executes, in sequence, for one release

On the candidate commit (before the cut; by procedure, not by the core):

1. GitHub push run on the candidate (Linux: `gates` job builds gtools-rs release, md, deadlinks, shellcheck; `rust` job builds gtools-rs release, fmt, clippy, `test rust`) (`Gtools: .github/workflows/ci.yml:72-138`).
2. GitHub `workflow_dispatch` run on the candidate: the same two Linux jobs again plus `macos` (brew install of 9 formulae and 2 font casks, Utilz clone, `build cms`, `cms serve --status`, the suite `--strict` which builds its own gtools-rs and runs `cargo test --locked` then 868 ExUnit tests, `app build --unsigned`, `app test --unsigned`) (`ci.yml:140-235`).
3. kovacs and gyges: `check all` and `test all` by procedure (`Devbin: intent issues show 0295`).
4. Optional `bin/devbin release --dry-run`, which runs `check all` and `test all` again (`Gtools: docs/releasing.md:10,21`).

On the release commit (the cut):

5. stamp: `cargo build --release` of gtools-rs (14 s) and `mix compile --force` of the CMS.
6. commit: the pre-commit chain: Intent guards, critics, doctor, `build --check` (no build), `engagement check`, `risks check`, `scrub --staged`, `design theme --check`.
7. gates `check all`: doctor; `bin/devbin build` twice more as no-ops (md, deadlinks); clippy (dev-profile check of the crate); fmt check; shellcheck; the rest read files.
8. gates `test all`: the suite's own release build of gtools-rs from a source copy, `cargo build --locked`, `cargo test --locked` (260), a CMS build from a copy, 868 ExUnit tests, then `xcodebuild test` (123 Swift tests, a Debug build of the app).
9. push: GitHub run on the push to main at the release sha (Linux `gates` and `rust` jobs: two more release builds of gtools-rs, clippy, `cargo test`).
10. push: GitHub run on the tag at the same sha (the same two Linux jobs again, plus the macOS job: `build cms`, the suite's gtools-rs build and `cargo test --locked`, 868 tests, `app build --unsigned`, `app test --unsigned`).
11. after: `formula publish` runs no build; later, each `brew upgrade gtools` compiles gtools-rs and the CMS on the installing machine.

Count for 0.8.3, on this Mac and GitHub alone (kovacs and gyges add their own): release-profile builds of gtools-rs: 2 local (stamp, suite) + 2 + 3 + 2 + 3 in the four GitHub runs = 12, of which 10 cold on runners; debug or test-profile compiles for `cargo test`: 1 local + 4 (Linux rust jobs) + 2 (macOS suites) = 7; clippy checks: 1 local + 4 CI; CMS builds: 2 local (stamp, suite copy) + 2 per macOS run x 2 = 6; xcodebuild runs: 1 local + 2 per macOS run x 2 = 5. The ExUnit suite of 868 tests ran 5 times on two commits that differ by four lines (dispatch, kovacs, gyges, the cut's gates, the tag's run), matching the issue's count.

### 3. CI trigger matrix

Workflow: `Gtools: .github/workflows/ci.yml`. Concurrency group `${{ github.workflow }}-${{ github.event_name }}-${{ github.ref }}`, `cancel-in-progress: true` (`:50-52`), so a push to main and a tag push are separate groups and both run.

| event | runs? | jobs |
| --- | --- | --- |
| push to main, any path outside `intent/whiteboard/**` and `intent/.canon/**` (`:33-43`) | yes | gates (linux, 15 min cap), rust (linux, 20 min cap); macos skipped (`if: ref_type == 'tag' || event == workflow_dispatch`, `:144`) |
| push to main touching only whiteboard and canon paths | no run | |
| push of a tag `v[0-9]*` or `[0-9]*` (`:35`) | yes | gates, rust, macos (xcode-27 image, 45 min cap, `:148-151`) |
| pull_request (`:44`) | yes | gates, rust; macos skipped |
| workflow_dispatch (`:45`) | yes | gates, rust, macos |

Duplicates on one sha: every cut pushes main and the tag at the same commit, so two runs start seconds apart and the two Linux jobs run twice: 0.8.1 (40920687896 at 17:22:22Z and 40920695516 at 17:22:25Z), 0.8.2 (40939198152 at 19:20:28Z and 40939207690 at 19:20:32Z), 0.8.3 (41135646272 at 22:04:45Z and 41135649951 at 22:04:47Z). The candidate `41c283a8` likewise had its push run (41127163812, 20:56:31Z) and its dispatch run (41127185022, 20:56:41Z). The Linux jobs take 60 to 75 s each; the macOS job took 13m39s on the 0.8.3 tag and 14m30s on the dispatch.

### 4. Caching and build reuse

- CI caches: no cargo cache in any job (no `actions/cache` for `~/.cargo` or `native/rust/target`, no rust-cache action); one Mix and hex cache on the macOS job keyed on `native/cms/mix.lock` and `bin/gtools_*` (`Gtools: .github/workflows/ci.yml:199-207`). Every Linux job rebuilds gtools-rs from a cold registry; the `gates` and `rust` jobs each build the same release binary independently (`:99-100`, `:128-129`). brew installs 9 formulae and 2 casks and clones Utilz on every macOS run (`:171-172,193`).
- Local: the stamp step's build is incremental on the tree's `native/rust/target` (14 s because only the version changed); md and deadlinks re-run `bin/devbin build` as 0.00 s no-ops; clippy builds a dev-profile check tree; the suite builds its own copy of the crate in a separate target under `$TMPDIR` so "nothing built in the tree reaches a running suite" (`Gtools: bin/.devbin/cmd/build:35-37`, `docs/testing.md:43`), and runs `cargo test --locked` there (a test-profile compile of the same source); the CMS is compiled with `--force` at the stamp and again as a copy by the suite.
- Nothing built locally reaches CI or the release: the release object carries no assets, brew builds from source per machine, and the app is installed from a checkout. Nothing built in CI reaches anything either; the macOS job's artefacts are discarded.

### 5. Serial that need not be

- The whole cut is one process and every step waits on the previous: `check all` (13 serial options, ~17 s) then the suite (8.6 min, one lock: `Gtools: docs/testing.md:37`) then the app tests (19 s) then the prompt, then the pushes, then the object, then formula publish, then a 13.7 minute wait on a run whose Linux half finished in 75 s.
- The CI wait cannot start until the tag is pushed, and the tag cannot be pushed until the local suite has passed on the release commit; the tag's macOS job then repeats that suite. The dispatch run on the candidate ran the same macOS job 65 minutes earlier on code that differs by a version string and a date.
- Within the macOS job: brew install, the Utilz clone, the CMS build and the suite's own crate build run one after another before the first test; the Linux jobs finish in a minute and then idle-wait for nothing, the run's verdict being the macOS job's.
- `md` and `deadlinks` each invoke `bin/devbin build` before running (both no-ops here, but serial).

### 6. Provenance and divergence

Manifest: `devbin_version: 0.1.18`, `source: install`, `source_commit: a9b8cd7c11a9e1e0a25ae56b45b9504eee51971e` (`Gtools: bin/.devbin/manifest.sha256:4-6`); every vendored file and `bin/devbin` identical to Devbin's tree at `7ab68c95`. Project-owned: `cmd/build` (342 lines) and `cmd/.lib/after-build`; `tools/lock-sync`, `tools/ci-state`, `tools/install-proof`, `tools/publish-public`; `packaging/homebrew/gtools.rb`. The release, formula and version handling are the core's.

### 7. Observations

1. The suite ran five times for one release on two commits that differ by four lines; the duplicate is structural (gates after stamp, tag run after gates), not accidental, and the core already carries `ci.base` and `ci.tag: false`, neither declared here (`Devbin: lib/config.reference.yaml:584-585`).
2. A failed or stopped cut costs the whole gates step again on resume (0.8.0 and 0.8.1 each ran the 7 to 9 minute suite twice on one commit), because the gates step keeps no record of a green it already gave (`Devbin: lib/cmd/release:1029-1031`).
3. Every cut starts two GitHub runs on the same sha (main push and tag push), and the Linux jobs run twice for nothing; the concurrency key's event and ref components keep them apart by design (`ci.yml:47-52`).
4. CI has no cargo cache, and two Linux jobs build the same release binary cold; the macOS job installs 11 brew packages and clones Utilz every run before any test.
5. The 45 minute `ci.wait` is the macOS job's timeout; the cut holds hv's terminal for the whole of that job on every release (13.7 min on 0.8.3, 31m55s on 0.7.0 per `Gtools: bin/.devbin/config.yaml:258-260`).
6. The gtools-rs binary is built from the same source in four separate target directories per release on this Mac alone (tree, suite copy, clippy's dev tree, and the app's Debug test does not count); none shares artefacts.
7. The after step and the CI verdict come after the formula is public: a red verdict leaves the tap pointing at the release by design ("fail forward", `Devbin: lib/cmd/release:1503-1506`).

---

## Conflab

### 1. The release, end to end

Conflab declares no `release:`, `macos:`, `cask:` or `formula:` block and does not enable the `release`, `macos` or `formula` built-ins (`Conflab: bin/.devbin/config.yaml`, whole file: the only `commands.*` rows are repl, cli, docs, fmt, test, check, fullcycle). Its own `cmd/release`, `cmd/macos`, `cmd/formula` and `cmd/cask` handlers are what `bin/devbin release|macos|formula|cask` run, by the resolver's rule that a project handler shadows a built-in of the same name (`Devbin: lib/resolve:669`), and `cmd/cask` has no built-in at all (the built-in formula renders a cask only as `formula.cask` in assets mode, `Devbin: lib/config.reference.yaml:657`). `Conflab: bin/.devbin/config.yaml:70-73` says so: "Every other handler under cmd/ is a project command or a shadow of a devbin built-in, and `bin/devbin doctor` names each shadow."

What a person does: writes `release-notes/<tag>.md`, `release-notes/<tag>-dist.md`, updates `dist/conflab-dist/CHANGELOG.md` and creates `dist/conflab-dist/releases/<tag>/RELEASE_NOTES.md` (all four refused if missing before anything is tagged: `Conflab: bin/.devbin/cmd/release:264-283`); then runs `bin/devbin release --local vX.Y.Z` (or `bin/release --local`, the shim at `Conflab: bin/release`). "RELEASING IS AN OWNER-AUTHORISED ACTION" (`cmd/release:20-21`). The CI path (`--patch` without `--local`) waits for `release.yml`, whose two jobs are gated on the repository variable `MACOS_RELEASE_CI == 'on'` (`Conflab: .github/workflows/release.yml:24,156`); that variable reads `off` (set 2026-04-16, `gh variable list`, read-only), and every tag's `release.yml` run since v0.5.7 shows `skipped` (`gh run list --workflow release.yml`: v0.5.7, v0.5.8, v0.6.0, v0.6.1, v0.6.2 all skipped). So every Conflab release has been built, signed, notarised and published on this Mac. `Conflab: docs/notes/tn001-macos-release-local-path.md:7` records why: the macOS runner job "burns through the ... included 2,000 Actions minutes at 10x the Linux rate", and `:69` "the full CI release chain consumes 80-120 billable minutes per run".

The cut (`Conflab: bin/.devbin/cmd/release`, project handler, 399 lines; everything below is the project's own, not the core's):

1. `run_release` tees the whole run to `dist/macos/logs/release-<tag>-<stamp>.log` (`:369-380`). No such directory exists on disk now (`dist/macos` holds only `Conflab-0.6.2-arm64.pkg`), so no local release log from v0.6.2 is retained.
2. The four notes files are checked (`:264-283`).
3. `bin/devbin version set <version>` writes `VERSION` and the three sidecars `native/cli/Cargo.toml`, `native/daemon/Cargo.toml`, `native/macos/Conflab/Conflab/Info.plist` (`Conflab: bin/.devbin/config.yaml:30-33`); `sync_locks` rewrites the `conflab` and `conflabd` entries of `native/Cargo.lock` by awk (`cmd/release:63-67`, `.lib/conflab:286-293`). The handler commits `Bump version to X` and runs `git push origin main` at once (`cmd/release:294-303`), before any gate. The pre-commit hook runs on that commit: Intent's chain, then `bin/precommit-rust` which is `bin/devbin precommit` (`Conflab: .githooks/pre-commit`, last line; `Conflab: bin/precommit-rust:10`), clippy on each crate the commit touches, and the version bump touches `native/cli/Cargo.toml` and `native/daemon/Cargo.toml`, so clippy runs on cli and daemon at the commit (`Conflab: bin/.devbin/cmd/precommit:49-70`; `crate_clippy` is `cargo clippy --manifest-path ... --all-targets [--features test-fakes] -- -D warnings`, `.lib/conflab:112-116`). That push starts `ci.yml` on GitHub.
4. Dirty-tree check (`:305`).
5. `preflight` (`:233-242`): `check format`, `check compile`, `check clippy`, `test mix`, `test credo`, `test rust`, each through devbin's sealed gate runner:
   - `check format` = `mix format --check-formatted` and `cargo fmt --all --manifest-path native/Cargo.toml --check` (`Conflab: bin/.devbin/cmd/.lib/check-format:25-28`).
   - `check compile` = the catalogue row `mix compile --warnings-as-errors --force` (`Devbin: lib/builtins:111`).
   - `check clippy` = clippy over every workspace member (cli, daemon, stamp), `--all-targets`, daemon with `--features test-fakes` (`.lib/check-clippy:26-32`), the same invocation the commit gate just ran on two of them.
   - `test mix` = the catalogue row `mix test` (`Devbin: lib/builtins:119`), with no exclude list; CI's line is `mix test --exclude integration --exclude todo --exclude spike --exclude external --exclude flaky` (`Conflab: .github/workflows/ci.yml:149`). 2340 ExUnit tests in 194 files.
   - `test credo` = `mix credo --strict` (`Devbin: lib/builtins:120`).
   - `test rust` = `cargo test --manifest-path <crate> --no-fail-fast` per member, daemon with `--features test-fakes`, `CONFLAB_DISABLE_KEYCHAIN=1` exported (`.lib/test-rust:74-88`); 1780 `#[test]` and `#[tokio::test]` functions in 127 files.
   - Not run: `test swift` (467 Swift test functions in 42 files under `native/macos/Conflab/ConflabTests`). "This gate has NO CI counterpart: CI runs Elixir and both Rust crates and stops there" (`.lib/test-swift:4-6`). The only Swift compile in a release is the Release build inside `build-pkg`.
6. Tag and push: `git tag <tag>`, `git push origin <tag>`; a tag that exists elsewhere is moved with `git tag -f` and `git push --force` (`cmd/release:313-323`). The tag is pushed before anything is built or notarised; `Conflab: bin/.devbin/help/release.md:10` says it: "an expired agreement fails at notarise, AFTER the tag has been pushed." The tag push starts `release.yml`, which skips.
7. `--local` branch, `build_and_publish_local` (`:151-224`):
   - `bin/devbin macos build-pkg --sign` (`:157`) runs `Conflab: bin/macos.d/build-pkg.sh` (through `cmd/macos:82-87`, which first sources `load-apple-creds.sh`, reading the three notary values from the login keychain under `conflab.apple.<field>` and deriving the two Developer ID identity names from the team id: `Conflab: bin/macos.d/load-apple-creds.sh:17-30`; PRESENT by code, values never printed here). build-pkg: the stamp via `cargo run --release -p stamp --bin conflab-stamp` (`Conflab: bin/macos.d/stamp.sh:23-24`); `cargo build --release` in `native/cli` and in `native/daemon` (`build-pkg.sh:74,77`; one workspace target, `native/target/release`, `.lib/conflab:142-150`); seed `BuildInfo.swift`; `xcodegen generate` (`:101`); `xcodebuild build -configuration Release -derivedDataPath native/macos/Conflab/build` with Apple Development automatic signing (`:110-119`); `codesign --force --options runtime --timestamp` on the two binaries and `codesign --verify --strict` (`:136-138`); re-sign nested frameworks deepest-first and the app bundle with the entitlements and the Developer ID Application identity, then `codesign --verify --strict --deep` (`:151-167`); stage `/Applications/Conflab.app`, `/usr/local/bin/conflab`, `/usr/local/bin/conflabd` and a `postinstall` (`:177-189`); `pkgbuild` (`:199-205`); `productbuild --sign` with the Developer ID Installer identity (`:223-233`); `pkgutil --check-signature` (`:245`). Output `dist/macos/Conflab-<version>-arm64.pkg`.
   - `bin/devbin macos notarize <pkg>` (`:164`) runs `Conflab: bin/macos.d/notarize.sh`: `xcrun notarytool submit ... --wait` (`:40-44`; the script's own estimate: "(This typically takes 1-5 minutes. notarytool will wait.)", `:37`), on anything but `Accepted` fetch the notary log and exit 1 (`:57-69`), `xcrun stapler staple` (`:73`), `spctl --assess --type install -v` (`:77`). This is the one wait on Apple, and it happens during the cut, after the tag is public.
   - Stage artefacts: the two release binaries, a tarball of `Conflab.app`, the pkg under its versioned and its stable name, `SHA256SUMS.txt` (`cmd/release:166-181`).
   - `gh release delete <tag> --yes` then `gh release create <tag> --notes-file release-notes/<tag>.md <artefacts>` on the source repository (`:184-186`): the object is deleted and remade on a re-run (the CI workflow instead uploads over it with `--clobber`, `release.yml:177-182`).
   - Clone the distribution repository, copy `priv/static/install.sh`, `priv/docs/`, `dist/dist-docs/`, `dist/conflab-dist/CHANGELOG.md` and `releases/`, commit and push if changed, then delete and recreate the tag's release there with the same artefacts and the `-dist` notes (`:188-223`).
8. `update_formula` (`:99-147`), in both modes: downloads `SHA256SUMS.txt` from the distribution release, `sed`s `version` and `RELEASE_VERSION` and `awk`s the two `sha256` lines in `Formula/conflab.rb`, `sed`s `version` and `sha256` in `Casks/conflab.rb`, in the tracked tap checkout at `dist/homebrew-conflab`, commits `Update conflab to <version>` and pushes. That checkout's log confirms this writer was used: `a326a83 2026-08-25 13:10Z Update conflab to 0.6.2` (local time; 09:10Z). The newer rendered path, `cmd/formula publish` and `cmd/cask publish` through `.lib/brew` (templates `brew_formula_template` and `brew_cask_template`, `Conflab: bin/.devbin/cmd/.lib/brew:106-234`; fresh clone, confirm or `DEVBIN_RELEASE_CONFIRMED`, `:312-363`), is not called by `cmd/release`: two formula writers coexist, and `.lib/brew:27-32` names itself "THE INTERIM" pending devbin's built-in.
9. Done: the two release URLs are printed (`:333-335`). There is no CI verdict step, no resume map, no dry run, no confirm prompt.

What CI does: on the `Bump version` push to main, `ci.yml` runs its five Linux jobs (3 to 5 minutes end to end: 41142812782 ran 23:10:14Z to 23:13:28Z; 40899802616 15:16:02Z to 15:21:06Z). On the tag push, `ci.yml` does not run ("No tag trigger is added here, deliberately", `ci.yml:39-41`) and `release.yml` starts and skips both jobs. So in the local path CI never sees the built artefacts and never gates the release; it tests the bump commit in parallel with the local pre-flight.

Measured: v0.6.2, 2026-08-25: `Bump version to 0.6.2` committed 09:05Z (`git log v0.6.2`; the handler commits at the start of the cut), the stapled pkg's mtime 09:10:09Z (`dist/macos/Conflab-0.6.2-arm64.pkg`, local 13:10:09), the tap commit 09:10Z. About five minutes from bump to published formula, pre-flight, three cargo builds, xcodebuild, signing, notarisation and two releases included. v0.6.1 the same morning: bump 07:59Z, tap commit 08:06Z. 641 commits have landed on main since v0.6.2 (`git rev-list --count v0.6.2..HEAD`); the next release carries the devbin 0.1.18 vendor, the workspace conversion and the stamp crate, none of which has been through this path yet.

Server deploy (separate from release): `bin/devbin build deploy` runs git-clean, the same six gates, then `fly deploy --build-arg GIT_SHA=...` (`Conflab: bin/.devbin/cmd/build:151-200`); "Deploy is SERVER-ONLY. It does NOT tag, does NOT touch the Homebrew tap, and does NOT build the macOS artefacts" (`:35-38`).

### 2. Every point the gates or a build or test executes, in sequence, for one release

1. Commit of the version bump: Intent's chain (staged-format guard over markdown, elixir and rust: `Conflab: bin/.devbin/cmd/precommit:9-13`), critic, doctor, then clippy on `native/cli` and `native/daemon` (the two Cargo.toml the bump touches), dev-profile check builds.
2. `git push origin main` starts `ci.yml`: elixir job (deps.get, deps.compile, `mix compile --warnings-as-errors --force`, format, credo, `mix ash.setup`, `mix test` with five excludes); rust-cli, rust-stamp, rust-daemon jobs (each fmt, clippy `--all-targets`, `cargo test --no-fail-fast`, daemon with `test-fakes`); build-context probe (`ci.yml:50-372`). In parallel with step 3.
3. Local pre-flight on the same commit: `mix format --check-formatted` + `cargo fmt --check`; `mix compile --warnings-as-errors --force`; clippy on all three crates (a repeat of step 1 for two of them); `mix test` (2340 tests, no excludes); `mix credo --strict`; `cargo test` on all three crates.
4. Tag pushed; `release.yml` starts and skips.
5. `build-pkg --sign`: `cargo run --release -p stamp` (compiles the stamp crate in release), `cargo build --release` of cli and daemon (the third cargo profile of the release after clippy's check and test's test profile), `xcodegen`, `xcodebuild build` Release (the only Swift compile; no Swift tests), codesign x4+, pkgbuild, productbuild.
6. `notarize`: notarytool submit and wait (Apple), staple, spctl.
7. Publish: two `gh release create`, one docs sync commit, one tap commit. No gate runs after step 3.

Not executed anywhere in a release: `test swift` (467 tests), the 53 bats tests under `tests/` (shell is not a declared language, so `test shell` is not offered; `Conflab: bin/.devbin/config.yaml:18-21`), `check contract` and `check parity` (declared check options but not in pre-flight's list, and `check all` is not what pre-flight calls).

### 3. CI trigger matrix

`Conflab: .github/workflows/ci.yml` (name `conflab`), concurrency `workflow-event-ref`, `cancel-in-progress: true` (`:42-44`). `Conflab: .github/workflows/release.yml` (name `Release`), no concurrency block.

| workflow x event | runs? | jobs |
| --- | --- | --- |
| ci.yml, push to main outside whiteboard and canon paths (`ci.yml:7-19`) | yes | elixir (ubuntu, postgres 17, 20 min cap), rust-cli (20), rust-stamp (10), rust-daemon (20), build-context (5) |
| ci.yml, push to main touching only whiteboard and canon | no run | |
| ci.yml, pull_request to main (`:4-6`) | yes | the same five |
| ci.yml, tag push | no (no tag trigger, `:39-41`) | |
| release.yml, push of tag `v*` (`release.yml:14-16`) | starts | build (xcode-27) and release (ubuntu, `needs: build`) both `if: vars.MACOS_RELEASE_CI == 'on'`; variable is `off`; both skipped on every tag since v0.5.7 |
| release.yml, anything else | no | |

Duplicates on one sha: none inside GitHub (the bump commit gets one ci.yml run; the tag gets one skipped release.yml run). The duplicate is local-versus-CI: the pre-flight runs the same compile, format, credo, clippy, `mix test` and `cargo test` on the bump commit that ci.yml runs at the same moment, the local one without CI's five excludes.

### 4. Caching and build reuse

- CI: `deps` and `_build` caches keyed on `mix.lock` (`ci.yml:109-123`); one cargo cache per Rust job, each keyed `cargo-<job>-v1-<hash of native/Cargo.lock>` over `~/.cargo/registry`, `~/.cargo/git` and `native/target` (`:167-176`, `:216-225`, `:257-266`). A version bump rewrites `native/Cargo.lock` (the two member entries), so the exact key misses on every release commit and the `restore-keys` prefix restores the previous target; the three jobs keep three separate caches of one workspace target.
- Local, one release: the workspace is compiled in three profiles on this Mac, check (clippy, twice for two crates: commit gate and pre-flight), test (`cargo test`), and release (`build-pkg`), plus `cargo run --release -p stamp`; `mix compile --force` under `check compile` recompiles the project from scratch each time by flag; `mix test` compiles the test env. All share the tree's `native/target` and `_build`, so the release-profile binaries built by `build-pkg` are the ones packaged (no rebuild between sign and package), and the `.app` built by `xcodebuild` is re-signed in place and copied into the pkg (`build-pkg.sh:124,180`).
- The pkg built locally is the one notarised, stapled, published to both releases and named by the cask; the two loose binaries in the release are the same files the pkg carries. Nothing is built twice for the artefacts themselves. The formula's and cask's checksums are read from the published `SHA256SUMS.txt`, never recomputed (`cmd/release:110-116`; `.lib/brew:7-9`).
- `fullcycle.restore` is `bin/devbin build native --release`, measured at 57 s of real compilation (`Conflab: bin/.devbin/config.yaml:206,214-215`), which bounds the release-profile workspace build on this machine.

### 5. Serial that need not be

- Pre-flight's six gates run one after another in one process (`cmd/release:235-240`); clippy over three crates and `cargo test` over three crates are each serial loops (`.lib/check-clippy:29-32`, `.lib/test-rust:77-88`).
- `build-pkg` builds cli, then daemon, then the app, serially, and the notarisation wait follows the whole build; the two `gh release create` calls, the dist clone and the tap push are serial network calls after it.
- The Elixir suite and the Rust suites are independent and run in sequence locally while ci.yml runs them as five parallel jobs on GitHub at the same time.

### 6. Provenance and divergence; what Conflab's handlers do that the built-ins do not

Manifest: 0.1.18, `source_commit: a9b8cd7c...` (`Conflab: bin/.devbin/manifest.sha256:4-6`); vendored lib and `bin/devbin` identical to Devbin at `7ab68c95`. Project-owned handlers: app, build, cask, daemon, db (+ db.d), formula, iex, macos, precommit, release, server, use (2682 lines with `.lib/`: brew, conflab, check-clippy, check-contract, check-format, check-parity, fmt-rust, test-rust, test-swift). The macOS implementation is outside `cmd/`: `bin/macos.d/{build-pkg.sh,notarize.sh,load-apple-creds.sh,store-apple-creds.sh,doctor.sh,verify-wp01.sh,stamp.sh}` (622 lines), reached through `cmd/macos` (`Conflab: bin/.devbin/cmd/macos:54-92`).

`cmd/release` versus the built-in `release`:
- Order: Conflab commits and pushes the version bump first and gates afterwards (`cmd/release:288-307`); the core stamps, commits, gates, then asks before anything is pushed (step order above). Conflab pushes the tag before building or notarising (`:313-323`); the core pushes after the gates and makes the object after the push. Conflab moves an existing tag with `-f` (`:317-320`); the core never moves one (`Devbin: lib/cmd/release:1098-1100` "A tag found is reused and reported, never rewritten").
- Missing in Conflab's: a confirm prompt, `--dry-run`, `--yes`, a resume map (`release status`), postconditions read before each step, bounded remote calls, the CI verdict wait, `after:` commands, the owned-set tree rule, the notes check against a CHANGELOG section. Present in Conflab's and absent from the core: a second distribution repository with a docs sync and its own release object, a `--local` build-sign-notarise-publish chain, a `-dist` notes file, `release list`, `release sync` (sidecars plus the lock), `--next-tag`.
- Locks: Conflab rewrites the two member entries by awk (`.lib/conflab:286-293`); Gtools has cargo rewrite the lock and bounds the diff (`Gtools: tools/lock-sync:73-83`); the core refuses lockfiles as sidecars (`Conflab: bin/.devbin/config.yaml:23-29`).

`cmd/macos` versus the built-in `macos` (`Devbin: lib/cmd/macos:8-15, 95-125`):
- Conflab produces a signed installer pkg carrying the app, the CLI and the daemon into `/Applications` and `/usr/local/bin` with a `postinstall`, signed by a Developer ID Installer identity, and notarises the pkg. The built-in signs a staged copy of the `.app` alone with the Developer ID Application identity, notarises and staples that copy, zips it and attaches it to the release through `release attach --from` (no pkg, no installer identity, no CLI binaries, no second repository).
- Conflab builds the app inside `build-pkg` every time (`build-pkg.sh:72-120`); the built-in runs `macos.build` only when declared and refuses unless HEAD is the release tag in a clean tree (`Devbin: lib/cmd/macos:104-112`).
- Conflab reads credentials under `conflab.apple.*` (`load-apple-creds.sh:18`); the built-in under `macos.keychain`'s prefix, default `devbin.apple` (`Devbin: lib/config.reference.yaml:633`). Both keep them in the login keychain and nowhere in the tree; CI's copies are GitHub secrets named at `release.yml:52-55,102-104,198` (presence in GitHub not checked here).
- Conflab checks the pkg with `spctl --assess --type install`; the built-in checks a quarantined copy of the app (`Devbin: lib/cmd/macos:114-115`).

`cmd/formula` and `cmd/cask` versus the built-in `formula`: Conflab's `.lib/brew` renders a formula and a cask from heredoc templates with `{{field}}` slots, reading the distribution release's `SHA256SUMS.txt` (`.lib/brew:239-257`); the built-in renders from a template file in the tree (`packaging/homebrew/<name>.rb`) in `source` or `assets` mode, with the cask as `formula.cask` in assets mode (`Devbin: lib/cmd/formula:15-33`). The publish contract is the same (fresh clone, `DEVBIN_RELEASE_CONFIRMED` or a prompt, no `--yes`). And `cmd/release`'s `update_formula` is a third, older writer that `sed`s the tracked tap checkout (`cmd/release:122-146`), the one the last release used.

### 7. Observations

1. Every Conflab release since at least v0.5.7 was built, signed and notarised on this Mac; `release.yml` has skipped on every tag because `MACOS_RELEASE_CI` is `off`. The CI path exists on paper (`tn001`) and has not run.
2. The version bump is committed and pushed, and the tag is pushed, before a single gate or build runs; a red pre-flight or a failed notarisation leaves a published tag and a bump on main.
3. Clippy on the touched crates runs at the commit and again in pre-flight; the Elixir suite runs locally without CI's five excludes while CI runs it with them on the same commit at the same time.
4. The Swift suite (467 tests) is in no release and no CI path; the only Swift compile is the Release build packaged.
5. Three formula writers exist (`update_formula`, `.lib/brew`, devbin's built-in), and the one the release calls is the sed-based one; `.lib/brew` calls itself interim.
6. Measured, the local release of v0.6.2 took about five minutes from bump to tap. The next release carries 641 commits, the workspace conversion and the stamp crate through a handler last changed 2026-08-27 (`cmd/release` mtime).
7. Release objects are deleted and recreated on a re-run (`cmd/release:184,213`), which the project's own CI workflow explicitly refuses to do (`release.yml:177-179`).

---

## Laksa

### 1. The build, test and deploy cycle, end to end

There is no release: no `release:` block, no `commands.release`, no tags in the repository (`git tag` lists none), and `mix.exs` is the one version home at `0.1.0` (`Laksa: bin/.devbin/config.yaml:22-26`; `Laksa: mix.exs:7`). The product ships as a Fly machine built from `Dockerfile`; the Rust CLI at `native/cli` "does not ship in the production image" (`Laksa: bin/.devbin/cmd/build:64-73`).

1. Commit: `core.hooksPath` points at the tracked `bin/hooks` (`Laksa: bin/.devbin/cmd/precommit:14-21`). `bin/hooks/pre-commit` runs Intent's chain first (`pre-commit.intent`: its guards, the staged-format guard over `markdown` and `rust` per `Laksa: intent/.config/config.json:6-9`, the critics, doctor; no project `guards` block is declared) and then `exec bin/devbin precommit` (`Laksa: bin/hooks/pre-commit`, last line): `mix format --check-formatted` per staged Elixir file, `mix credo --strict` over the staged `.ex`/`.exs`, and the guard roster in `bin/hooks/guards` (append-only, canon-ignore, hv-attribution, whiteboard clock, header and inbox) (`cmd/precommit:23-37`). Checks only; nothing writes (`:41-56`).
2. Push to main: `ci_cd.yml` runs one job, `Test and Quality Checks`, on `ubuntu-26.04` with a 25 minute cap and a postgres 18 service (`Laksa: .github/workflows/ci_cd.yml:70-88`): setup-beam from `.tool-versions` (`:99-121`), `deps` and `_build` caches keyed on `mix.lock` (`:123-139`), `mix deps.get`, `mix deps.compile`, `mix compile --warnings-as-errors --force`, `mix format --check-formatted`, `mix credo --strict`, ImageMagick, `mix tailwind.install --if-missing`, the Rust toolchain pinned from `.tool-versions` (1.98.1) because `test/cli/crate_gate_test.exs` drives `bin/devbin test rust` from inside the suite (`:192-211`; `Laksa: test/cli/crate_gate_test.exs:92,109`), then `mix test` (`:213-214`). Recent runs take 13 to 17 minutes (40949844924: 20:31:51Z to 20:45:24Z; 41141787027: 23:00:42Z to 23:17:32Z); the two most recent on 30 Oct are red (41113839695, 41141787027; not investigated here). A superseded push is cancelled (40949764888 cancelled 33 s after 40949844924 started; `:43-45`). `fly-deploy.yml.disabled` (push to main, `flyctl deploy --remote-only`) is off, so CI deploys nothing.
3. Local gates, by hand: `check all` runs the declared options first, in order, toolchain, codegen (`mix ash.codegen --check`), format (mix + cargo fmt with `--manifest-path native/cli/Cargo.toml`), clippy, guards (proves the commit gate still dispatches), vendor (the vendored devbin is current, not merely intact), remote (`git ls-remote` on every push destination), context (`build-context-sha --gitignored-in-context`), compile (`MIX_ENV=test mix compile --warnings-as-errors --force`), then the catalogue's deps, autotests, targetdir and critic (`Laksa: bin/.devbin/config.yaml:85-217`; `Devbin: lib/builtins:113-118`). `test all` is mix (the authored runner, parallel, `max_cases` 32, sealed by the runner itself, `log: "-"`), credo, rust (`cargo test --manifest-path native/cli/Cargo.toml --no-fail-fast`); integration, local and guards are `in_all: false` (`config.yaml:290-342`). 5295 ExUnit tests in 546 files; 51 `#[test]` in 18 Rust files (four cargo test targets, `config.yaml:306-312`).
4. Deploy, human-run ("hv owns deploys", `Laksa: bin/.devbin/cmd/build:317-318`): `bin/devbin build deploy` (`cmd/build:152-311`, the order restated at `Laksa: bin/.devbin/help/build.md`, "build deploy" section):
   1. git tree clean (fly deploys the working tree, not HEAD: `:184-194`);
   2. `test-credo --out-dir tmp/deploy` (`:208`);
   3. `test-mix --no-trace --out-dir tmp/deploy` (parallel, `:211`);
   4. `check codegen` (`:215`);
   5. `check context` (`:232`), outside the `--force` and `--skip-checks` arms;
   6. `MIX_ENV=prod mix release --overwrite` (`cmd_release`, `:44-55`, "the duplicate-OTP-module gate"), never skipped by any flag (`:234-244`); its artefact is not what ships;
   7. the build-context stamp, `build-context-sha`, the same recipe the image runs (`:271-277`);
   8. `--dry-run` stops here (`:279-289`); otherwise `fly deploy` (`:298`), whose remote builder runs the Dockerfile: `mix deps.get --only prod`, `mix deps.compile`, `mix assets.setup`, `npm ci`, `COPY priv lib`, `mix compile`, the stamp `RUN sh ./build-context-sha > /app/BUILD_CONTEXT_SHA`, `mix assets.deploy`, `mix release` (`Laksa: Dockerfile:85-166`), then the runner image copies the release and the stamp (`:194-208`); Fly runs `/app/bin/migrate` as the release command (`Laksa: fly.toml:12-13`).
   Nothing waits on CI, nothing is tagged, no GitHub release is made. The deploy's own gate seals live under `tmp/deploy` (`:197-207`).

Measured deploy legs (`Laksa: tmp/deploy/`): four runs, three on 2026-10-08 and one on 2026-10-17; the latest: credo `Analysis took 5.5 seconds (1.1s to load, 4.4s running 68 checks on 1134 files)` (`tmp/deploy/LATEST_CREDO.out:13`); suite `Running ExUnit with seed: 610435, max_cases: 32`, `Finished in 88.1 seconds (66.0s async, 22.1s sync)`, `Result: 4685 passed (57 doctests, 4628 tests), 198 excluded`, `MODE: PARALLEL, max_cases 32, whole suite` (`tmp/deploy/LATEST_MIX.out:10-19`). The credo seal is at 13:42Z and the mix seal at 13:43Z (local 17:42 and 17:43), so credo plus the suite is about 90 seconds locally against 13 to 17 minutes for the same suite on the GitHub runner. The local `mix release` and the Fly remote build leave no seal; their durations are not on this machine. `Laksa: intent issues show 0022` (OPEN) owes a `check all` and a `build deploy --dry-run` sealed green on a clean tree before the next deploy, and records that the one attempt on 2026-10-08 06:35Z "went red under another project's load".

### 2. Every point a gate, build or test executes, in sequence, for one push-and-deploy

1. Commit: Intent guards, staged-format (markdown, rust), critics, doctor; `mix format --check-formatted` on staged files; `mix credo --strict` on staged files; six guard scripts.
2. Push to main: CI compiles deps and the app (`--force`), format, credo, `mix test` (5295 tests, which inside itself compiles and tests the Rust crate through `bin/devbin test rust`).
3. Deploy, locally: credo (whole project); `mix test` whole suite, parallel (which again builds and tests the crate inside `crate_gate_test`); `mix ash.codegen --check` (a dev-env compile); `build-context-sha` twice (once as the context check, once as the stamp); `MIX_ENV=prod mix release` (a full prod compile, discarded).
4. Deploy, on Fly's builder: `deps.compile`, `mix compile`, `assets.deploy`, `mix release` from scratch inside Docker; the stamp again.
5. Nothing after: no CI on the deployed commit beyond step 2, no tag, no object.

A `test all` by hand runs the crate's 51 tests twice: once directly as `test rust` and once inside `test mix` via `crate_gate_test.exs` (`Laksa: test/cli/crate_gate_test.exs:35-37` says it deliberately does not run `test all`, and `:109` runs `test rust`).

### 3. CI trigger matrix

`Laksa: .github/workflows/ci_cd.yml` (name `laksa`), concurrency `workflow-event-ref`, `cancel-in-progress: true` (`:43-45`).

| workflow x event | runs? | jobs |
| --- | --- | --- |
| ci_cd.yml, push to main outside `intent/whiteboard/**` and `intent/.canon/**` (`:7-21`) | yes | `test` (ubuntu-26.04, 25 min cap) |
| ci_cd.yml, push to main touching only those paths | no run | |
| ci_cd.yml, pull_request to main (`:4-6`) | yes | `test` |
| ci_cd.yml, tag push | no (no tag trigger) | |
| fly-deploy.yml.disabled, any | never (disabled by filename) | |

Duplicates on one sha: none in GitHub. The duplicate is CI versus the deploy's local legs: the suite that CI ran on the pushed commit (13 to 17 minutes) runs again locally in the deploy (88 s) on the same tree, and the prod compile runs twice (local `mix release` as a gate, then Fly's builder for the image).

### 4. Caching and build reuse

- CI: `deps` and `_build` caches keyed on `mix.lock` with a prefix fallback (`ci_cd.yml:123-139`); no cargo cache, so `crate_gate_test`'s `bin/devbin test rust` compiles the crate cold inside every run; ImageMagick is apt-installed every run (`:177-182`).
- Local deploy: `_build/test` is warm for the suite; `_build/prod` for `mix release --overwrite`; the crate's `native/cli/target` is warm for the nested `test rust`.
- Fly: the builder compiles the whole release from the Dockerfile; what it may cache is Docker layers up to the first changed COPY (the `mix.exs mix.lock` layer and `deps.compile` survive a code-only change, `Dockerfile:85-93`); nothing built locally is reused, by design ("Assets are deliberately NOT built here. The image builds its own", `cmd/build:239-243`), and the local `mix release` artefact is a gate only.
- The one artefact reused across the two sides is the stamp: computed locally and in the image from the same script so the two can be compared later (`Laksa: bin/.devbin/cmd/.lib/build-context-sha:5-8`).

### 5. Serial that need not be

- The deploy's legs run in one process in sequence: credo, the suite, codegen, context, release build, stamp, deploy; credo and the suite are independent, and the context check and stamp read the same tree twice.
- `check all` runs 13 options serially; `remote` and `vendor` leave the machine (`ls-remote`, a source read) while the rest are local.
- The prod release is compiled locally and then compiled again remotely in series; the local build's only purpose is to fail before Fly's builder would (`cmd/build:234-237`).

### 6. Provenance and divergence

Manifest: 0.1.18, `source_commit: a9b8cd7c...` (`Laksa: bin/.devbin/manifest.sha256:4-6`); vendored lib and `bin/devbin` identical to Devbin at `7ab68c95`. Project-owned handlers: build, cli, console, content, db (+ db.d), iex, log, precommit (1430 lines), products, repl, server, sites, verdict, and `.lib/` build-context-sha (1067), check-compile, check-format, check-guards (566), check-remote (414), check-toolchain (358), check-vendor, fmt-md, formatter-read.exs, laksa (1296), test-credo, test-guards, test-mix (482): 8369 lines, the heaviest project layer of the three. The commit gate and the test runners are the project's own on top of devbin's `runlog` primitives (`config.yaml:271-289`).

### 7. Observations

1. There is no release cycle to shorten here: no tag, no object, no asset. The cost centres are a 13 to 17 minute CI job for a suite that runs in 88 s locally (cold Hex deps compile, apt, Tailwind, a cold Rust toolchain and crate build inside the suite), and a deploy that compiles the prod release twice.
2. The crate's tests run twice in a `test all` (directly and inside the suite's `crate_gate_test`), and CI builds the Rust toolchain and crate only to serve that one nested test.
3. The deploy does not read CI: nothing stops `build deploy` on a commit whose CI run is red, and the two most recent CI runs are red.
4. Issue 0022 (open since 2026-10-18) still owes the first sealed `check all` and `build deploy --dry-run` on the current devbin; the last deploy legs sealed are from 2026-10-17.
5. Nine of the thirteen `check all` options are project scripts rather than catalogue rows; several measure the gate and the machine (guards, vendor, remote, toolchain, context) rather than the code, each with a long header explaining a past silent failure.
