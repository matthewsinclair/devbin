# Evidence B: the release cycle of two devbin consumers, Utilz and Intent

Read-only survey, 2026-10-31 07:23Z. Every file was read in place; nothing was run that writes. CI timings come from `gh run list` and `gh run view` (reads), release-asset times from `gh release view` (reads), local timings from file mtimes under each project's `tmp/` and from the git log. Local mtimes are converted from the machine's UTC+4 to Z.

Both projects vendor the same devbin bytes: devbin 0.1.18, `source_commit a9b8cd7c11a9e1e0a25ae56b45b9504eee51971e` (section 6). The two differ entirely in what they put around the core.

---

## Part A: Utilz

### A1. The release, end to end

Who does what: hv runs the cut; any node may run the read-only steps (`Utilz: docs/releasing.md:5`). The cut is devbin's release core, switched on by `Utilz: bin/.devbin/config.yaml:89-90` (`release: enabled: true`), declared at `:137-145`:

```
release:
  tag: "{version}"
  repo: <owner>/utilz
  gates:
    - check all
  after:
    - tools/post-cut
  ci:
    query: tools/ci-state
```

Everything else is the core's default (`Utilz: bin/.devbin/lib/config:547-557`): `ci.wait 20m`, `ci.tag true`, `ci.base false`, `object: local`, `branch main`, `notes.kind changelog`, no `remotes` (so every remote `git remote` lists: `local` and `upstream`, `Utilz: docs/releasing.md:53`).

Sequence, with where each step runs and what it waits on:

1. **Before the cut, on the candidate (hv's machine).** `bin/devbin release check` (read-only; validates the declaration, reads every workflow for a second writer of the release object). Then `bin/devbin release --patch --dry-run`: the core's steps 1-5 with every write reported as `would`, but **the gates run for real** on HEAD in place (`Utilz: docs/releasing.md:23`). The gate is `check all` only (`config.yaml:140-141`); the suite is not a gate. The suite's hand run is `bin/devbin test estate` = `tools/test-estate`, which the docs say "runs before the cut, in the dry run and the twins, and not again in it" (`docs/releasing.md:16`). `tools/test-estate:68` is `exec env PATH="/bin:$PATH" "$UTILZ_HOME/bin/utilz" test "$@"`, after refusing unless `/bin/bash` reports 3.2 (`:45-66`). `bin/utilz test` with no argument walks every utility in order (`Utilz: opt/utilz/lib/common.sh:2373-2460`): for a utility with `crate/Cargo.toml` (prez only) it runs `cargo build --release --workspace` (`:2208`), then `cargo test --workspace --no-fail-fast` (`:2170`), then `bats ./*.bats` in `opt/<name>/test` (`:2224`), then every `crate/test/*.sh` with `--strict` (`:2435-2458`: `acceptance.sh`, `theme-addressing.sh`, `video.sh`, the last needing Chrome and ffmpeg per `config.yaml:44-45`); for the other 16 utilities, bats alone. Serial throughout; bats is invoked without `--jobs`. Candidate commit. No local record of an estate run exists for 2.14.6 through 2.14.8: `tmp/test/LATEST_ESTATE.*` are dangling symlinks to `20261028-1238.ESTATE.*`, whose targets are gone, and `tools/test-estate` run directly writes no `tmp/test` log (only `bin/devbin test estate` does).
2. **CI on the candidate.** The candidate is already on `main` and `upstream` (the cut pushes nothing new before it commits), so its push has run `tests.yml`'s push jobs. For 2.14.8 hv also started a `workflow_dispatch` run on the candidate (run 41120955230 at 2026-10-30 20:08:57Z, 14m12s), which is the full matrix including the macOS legs and `menuz-app`.
3. **The cut: `bin/devbin release --patch --yes`** (core; `--yes` answers the confirm step so nothing stops at the terminal, `docs/releasing.md:24`). Core steps, each reading its postcondition first (`Utilz: bin/.devbin/lib/release.steps:94`: `resolve pre-flight stamp commit gates confirm tag push snapshot candidate publish object after ci`; snapshot/candidate/publish are inert here, no `publish.url`):
   - 1 resolve: the version from the newest bare `X.Y.Z` tag (template `{version}`), the tag name, new or resume.
   - 2 pre-flight: branch, remotes, clean tree, notes section present.
   - 3 stamp: `VERSION` and the CHANGELOG date (`notes.kind changelog`).
   - 4 commit: the release commit, through the pre-commit hook (the shipped gate: guards, `intent critic`, `intent doctor`; `tmp/release/20261030-2059.RELEASE.out:7-14`).
   - 5 gates: `bin/devbin check all` **on the release commit**, then the tree and HEAD are re-read (`Utilz: bin/.devbin/lib/cmd/release:1044-1063`). Measured 2026-10-30: run dir opened 20:59:05Z, the six check seals written 20:59:15Z-20:59:16Z, so about 11 s (clippy was warm: `Finished dev profile in 0.16s`, `RELEASE.out:20`). What ran: clippy, format, autotests, targetdir, toolchain, critic; `6 of 8 check options ran; 2 inactive here` (`RELEASE.out:65`). The critic examined 0 files (`nothing staged`, `RELEASE.out:45`).
   - 6 confirm: answered by `--yes`.
   - 7 tag: bare, annotated (`git cat-file -t 2.14.8` = `tag`), the CHANGELOG section as message.
   - 8 push: `main` and the tag to `local` then `upstream`, each read back within `RELEASE_READBACK_SECONDS` (120 s default, `release.steps:1505-1506`).
   - 9 object: `gh release create` by the core (`object: local`), title and notes only, no assets. Measured: release created 20:59:22Z, published 20:59:36Z.
   - 10 after: `tools/post-cut` (project's own), see step 4 below. Runs with `--yes` passed as `DEVBIN_RELEASE_CONFIRMED` (`lib/cmd/release:1484`). The core runs every `after:` line even when one failed, which is why Utilz declares one line not four (`Utilz: tools/post-cut:10-14`).
   - 11 ci: `tools/ci-state <sha>` asked every 15 s (`RELEASE_POLL_SECONDS`, `release.steps:1526`) while it answers `pending` or `none`, up to `ci.wait` = 20m (`lib/cmd/release:1520-1526`). `tools/ci-state:42` calls `install_ci_state`, which runs `gh run list --commit <sha> --workflow tests.yml` with a 10 s deadline per ask (`Utilz: opt/utilz/lib/install.sh:477-478`) and answers the **worst of every run on the sha** (`:672-716`). It does not read `DEVBIN_RELEASE_TAG` (`git grep` finds no occurrence under `opt/` or `tools/`), so the branch run and the tag run both count (`docs/releasing.md:17`). Only green exits 0; anything else is "fail forward", the tag stands (`lib/cmd/release:1502-1504, 1551-1560`).
4. **After the cut, still inside the cut (step 10), `tools/post-cut`** (macOS only, `tools/post-cut:65-68`):
   - refuses unless the tag is the newest bare-semver tag (`:78-81`); reads the release's assets (`:83`); if `Menuz.app.zip` is already there the app steps are skipped (`:87-88`);
   - otherwise makes a detached worktree at the tag under the system temp dir (`:90-93`) and runs devbin's **built-in** `bin/devbin macos app-sign`, `app-notarize`, `publish` there (`:96-100`), each declared by the `macos:` block (`config.yaml:115-125`): `app-sign` builds with `bin/utilz menuz build --release` (xcodebuild, Release), stages a copy under XDG state, signs inside-out; `app-notarize` submits with `xcrun notarytool submit --wait` (`Utilz: bin/.devbin/lib/cmd/macos:1066-1070`), staples, checks a quarantined copy; `publish` zips, proves the zip, attaches through `release attach --from` which writes `SHA256SUMS` over every asset (`RELEASE.out:136-144`);
   - then `tools/formula publish` (`:104`): clones the tap fresh, renders `packaging/homebrew/utilz.rb` from the tag's own bytes with `@@TAG@@`/`@@REVISION@@` filled from git, commits, pushes (`Utilz: tools/formula:131-169`); a tap already carrying the release is left alone;
   - then pulls this machine's tap clone (`:119`).
   - Measured 2.14.8: release commit 20:59:11Z; `Menuz.app.zip` attached 21:01:23Z; `SHA256SUMS` 21:01:28Z; tap commit `utilz 2.14.8` 21:01:58Z. So the whole after step, xcodebuild and Apple's notarisation included, took about 2m40s. The run log's last write is 21:02:02Z; its seal says `run in flight (or aborted before sealing)`, so the ci step's end is not on the record.
5. **CI on the release commit, two runs on one sha** (both `tests.yml`): the push to `main` (run 41127529723, created 20:59:28Z, 9m35s) and the tag push (run 41127538028, created 20:59:32Z, 34m51s). The tag run adds `test-macos`, `menuz-app` and `Rust (macos-latest)`. Per job (tag run): `Test on Ubuntu` 9m25s; `Test on macOS` 10m47s (bats step 10m09s); `Rust (ubuntu)` 6m10s (build+test+accept 5m39s); `Rust (macos)` **queued 23m38s** (created 20:59:32Z, started 21:23:10Z), then 11m07s (build+test+accept 9m53s); `menuz-app` 1m54s (xcodebuild build 1m04s, test 34s); `shellcheck` 1m38s; `clippy` 23s. The branch run's `Rust (ubuntu)` and `Test on Ubuntu` ran concurrently with the tag run's on the same commit. The 2.14.7 tag run had no queue (14m46s end to end).
6. **The core's ci step against that.** The after step ended about 21:02Z; `ci.wait` is 20m; the tag run concluded 21:34:23Z. The query answers worst-of and the tag run was pending until 21:34, so the wait ran out around 21:22Z with `pending` and the cut's last row read FAILED (`lib/cmd/release:1529-1532`), unless hv interrupted it. Either way nothing after it depended on the verdict.
7. **After the cut, by hand** (`docs/releasing.md:101-119`): `brew audit --strict` on the tap, `brew upgrade utilz` on rhadamanth and on kovacs, `utilz version` and `utilz doctor` on each, then the dev/opt/brew switch proof (`utilz use dev|opt|brew`).

Timeline of the last two cuts (all Z):

| | 2.14.7 (2026-10-29) | 2.14.8 (2026-10-30) |
|---|---|---|
| last candidate commit | 18:44:25 | 20:05:54 |
| CI on candidate | push run at 18:44 (not listed above the window) | push 20:07:54-20:20:41; dispatch (full matrix) 20:08:57-20:23:09 |
| release commit | 18:57:30 (13 min after the candidate) | 20:59:11 (53 min after the candidate) |
| release object published | 18:57:54 | 20:59:36 |
| Menuz.app.zip attached | 18:59:32 | 21:01:23 |
| tap commit | 19:00:09 | 21:01:58 |
| CI branch run done | 19:03:59 | 21:09:03 |
| CI tag run done | 19:12:36 | 21:34:23 (macOS rust leg queued 23m38s) |
| candidate to tap | 15m44s | 56m04s |

The cut proper (commit to tap) is under three minutes on both days. The hour is spent before the cut (dry run, estate, watching CI on the candidate) and after it (the tag's CI and the 20m `ci.wait`).

### A2. Every gate execution in one release, in order

| # | What executes | Where | On which commit | Trigger |
|---|---|---|---|---|
| 1 | `check all` (clippy, fmt --check, autotests, targetdir, toolchain, critic) | hv's Mac, in place | candidate | `release --dry-run` (hv, by procedure) |
| 2 | `test estate`: prez `cargo build --release`, `cargo test --workspace`, bats, acceptance/theme/video `--strict`; bats for 16 other utilities; all under `/bin/bash` 3.2 | hv's Mac | candidate | by procedure (`docs/releasing.md:16`); not a gate of the cut |
| 3 | `tests.yml` push run: test-linux (bats, 17 utilities less prez, bash 5), shellcheck, rust ubuntu (cold `cargo build --release`, `cargo test --release`, acceptance suites under Xvfb), clippy (cold fmt+clippy) | GitHub ubuntu | candidate | the candidate's push to `main` |
| 4 | `tests.yml` dispatch run: all of 3 plus test-macos (bats under runner's bash 3.2), menuz-app (xcodebuild build+test), rust macos | GitHub ubuntu + macos + xcode-27 | candidate | hv's `workflow_dispatch` (2.14.8 only) |
| 5 | pre-commit hook: guards, `intent critic` (0 files), `intent doctor` | hv's Mac | release commit | core step 4 |
| 6 | `check all` again | hv's Mac | release commit | core step 5 (`gates`) |
| 7 | `tests.yml` push run (as 3) | GitHub | release commit | core step 8's push of `main` |
| 8 | `tests.yml` tag run (as 4) | GitHub | release commit | core step 8's push of the tag |
| 9 | xcodebuild Release of Menuz.app (signed) | hv's Mac, worktree at tag | release commit | `after:` via `macos app-sign` |
| 10 | xcodebuild of Menuz.app (unsigned) + `menuz test` | GitHub xcode-27 | release commit | row 8's `menuz-app` job |
| 11 | ci verdict read (no test; a wait) | hv's Mac | release commit | core step 11, up to 20m |

Rows 3, 7 and 8 each cold-build and test the prez crate: five cold prez builds on GitHub for one release commit (rust ubuntu x2, rust macos, clippy x2), plus three on the candidate's dispatch run. Rows 2, 3, 7, 8(ubuntu) and 8(macos) each run the whole bats estate: five bats passes over the same 1059 tests (`git grep -c '^@test'` over 35 `.bats` files), two of them on the candidate and three on the release commit.

### A3. CI trigger matrix

| workflow | push `main` | tag push (`v[0-9]*`, `[0-9]*`) | pull_request | workflow_dispatch | workflow_run | candidate branch push |
|---|---|---|---|---|---|---|
| `tests.yml` | test-linux, shellcheck, rust(ubuntu), clippy, test-summary; skipped when every changed path is under `intent/whiteboard/**` or `intent/.canon/**` (`:14-21`) | the same five plus test-macos (`:115`), menuz-app (`:535`), rust(macos) (`:285`); path filters do not apply to tags | the push-main set (`:22-23`, `branches: [main]`) | the tag set (`:24`; the three macOS gates test `workflow_dispatch` too) | none | none (`branches: [main]`) |
| `pr-checks.yml` | no | no | check-documentation, test-coverage, commit-message-check, pr-size-check, utility-metadata-check; all advisory `echo`s, none can fail except by a broken diff | no | no | no |

Concurrency: `tests.yml:30-32` groups on workflow + event + ref, cancel-in-progress; so a branch push and a tag push on the same sha are two groups and both run. `pr-checks.yml` has no concurrency block. **Duplicate on the release sha:** test-linux, shellcheck, rust(ubuntu), clippy and test-summary run twice, once per event (measured runs 41127529723 and 41127538028). Runners: `ubuntu-latest`, `macos-latest`, and the label `xcode-27` for menuz-app (`tests.yml:534`, with `DEVELOPER_DIR` pinned to Xcode 27.1 at `:537`).

`Utilz: .github/workflows/README.md` is stale on three points: it says `actions/checkout@v4` (`:91`; the file uses `@v7.0.1`), that tests run on macOS on every push (`:9-13`; `tests.yml:115` gates it to tags and dispatch), and it does not list the `rust`, `clippy` or `menuz-app` jobs.

### A4. Caching and build reuse

- **No cache action anywhere.** `grep -n cache .github/workflows/*.yml` matches nothing. Every rust job starts cold: `Rust (ubuntu)` 5m39s and `Rust (macos)` 9m53s of `cargo build --release --workspace` + `cargo test --release --workspace` + acceptance (`tests.yml:392-393`), `clippy` 14-17 s (prez is small; the clippy job's compile is a separate debug check pass).
- bats-core is installed from the source tarball on ubuntu each run (`tests.yml:47-51`) and from Homebrew on macOS (`:125`); the macOS legs `brew install` yq, fileicon, coreutils, unison, qpdf, poppler, lua and bash (`:135-141`), ffmpeg and poppler on the rust macOS leg (`:348, :363`), xcodegen and yq on menuz-app (`:545`). These are per-run downloads.
- **Locally**, `opt/prez/crate/target` persists across runs, so the estate's prez build is incremental; `check clippy` in the cut was warm (0.16 s).
- **Release binaries.** Utilz ships no binary: the formula builds from source at the tag (`formula.mode: source` default; `tools/formula:3-5`). The only built artefact is `Menuz.app`, built **twice per release**: signed by `app-sign` on hv's Mac (`RELEASE.out:77-80`) and unsigned by CI's `menuz-app` job on the same tag (`tests.yml:551-554`); neither output reaches the other.

### A5. Serial that need not be

1. The ci step (core step 11) holds the terminal for up to 20 minutes on a verdict nothing afterwards consumes; the tag run's macOS legs are what it waits for, and those can queue behind runner availability (23m38s on 2026-10-30). The query cannot answer green before the slowest macOS job finishes because it reads worst-of across both runs.
2. `tools/post-cut` runs formula publish after the app steps. The formula names only the tag and its commit, so it does not depend on the asset's bytes; the ordering is a product rule (a `menuz install` from a fresh keg fails until the asset exists, `docs/releasing.md:86`), not a data dependency.
3. `bin/utilz test` runs 17 utilities one after another and each `bats` without `--jobs` (`common.sh:2224`); CI runs the same suite once per leg, also serially (`tests.yml:103-106`, `:190-197`).
4. The ubuntu half of the tag run duplicates the branch run that started four seconds earlier on the same sha; concurrency groups keep both alive by design (`tests.yml:26-32`).
5. The macOS legs run on the tag only (`:115`), so a macOS-only regression is first seen after the tag is pushed, which is what `tools/test-estate` exists to pre-empt locally (`:4-12`); the local run and the CI macOS leg are the same suite on the same bash.

### A6. Provenance of the vendored core and divergence

- `Utilz: bin/.devbin/manifest.sha256:4-6`: `# devbin_version: 0.1.18`, `# source: install`, `# source_commit: a9b8cd7c11a9e1e0a25ae56b45b9504eee51971e`.
- `bin/devbin` and every file under `bin/.devbin/lib/` are byte-identical to Intent's copy (`diff -rq` of the two `lib/` trees and of `bin/devbin`: no output) and to Devbin's canonical tree at HEAD (`git diff --stat v0.1.18 HEAD -- lib bin/devbin` in Devbin: empty; 13 release-path files diffed individually: all `same`).
- Utilz declares no handler under `bin/.devbin/cmd/` (the directory holds nothing; its own `macos` handler was retired at 2.14.7 for devbin's built-in, `CHANGELOG.md` 2.14.7 and issue 0118). Its only release code outside the core is `tools/post-cut`, `tools/formula`, `tools/ci-state`, `tools/test-estate`.
- Divergence from the core's defaults is all in `config.yaml:137-145` (bare tag template, one gate, one `after:` line, a `ci.query`) and in the `macos:` block (`:115-125`), which binds the built-in to an app whose version comes from `opt/menuz/VERSION` rather than the project's.

### A7. Observations

1. The cut itself is about three minutes from release commit to tap; the hour is the candidate's pre-cut checking (dry run, estate, a full-matrix dispatch) and the tag's CI afterwards.
2. The same bats estate runs five times per release (local estate, CI candidate push, CI release push, CI tag ubuntu, CI tag macOS) and the prez crate is cold-built five times on GitHub for the release commit alone; nothing caches cargo in CI.
3. The branch push and the tag push of the release commit run the same ubuntu jobs twice within four seconds of each other, by the concurrency design.
4. `ci.wait` (20m default, undeclared) is shorter than a tag run with a queued macOS runner (34m51s on 2026-10-30), so the ci row fails on a release that is green.
5. `tools/ci-state` ignores `DEVBIN_RELEASE_TAG`, so the core's "tag's runs only" contract (`release.steps:1578-1592`) is not what Utilz gets; it gets worst-of across both runs, which is slower to turn green and reads a superseded-and-cancelled branch run as `failed`.
6. `Menuz.app` is built twice per release on two machines with two Xcodes' worth of setup, and the CI copy is discarded.
7. No local record shows the estate ran for 2.14.6 through 2.14.8; the release path does not require it, and the candidate's CI (including a hand dispatch) is doing that job.

---

## Part B: Intent

### B1. The release, end to end

Intent does **not** cut with devbin's core. `Intent: bin/.devbin/config.yaml:365-372`:

```
release:
  repo: <owner>/intent
  verbs:
    - check
    - attach
  assets:
    workflow: linux-release.yml
    wait: 15m
```

so `bin/devbin release` offers `check` and `attach` and refuses `cut`, `status` and `notes` (`:343-347`). The cut is the project's own `bin/devbin build release` = `Intent: bin/.devbin/cmd/build.d/release` (1524 lines), and the assets arrive through four more hand steps. Written procedure: `Intent: intent/docs/releasing.md:101-135`.

Sequence:

1. **Stop the daemon** (`releasing.md:103`); the driver refuses while intentd is live (`build.d/release:699-706`), because step 6 below replaces the binary it runs.
2. **Pre-cut commits** (`releasing.md:104-117`): `intent doctor` clean; `intent claude upgrade` (dry) must write nothing; regenerate `docs/reference` both halves at HEAD against `git describe --tags --abbrev=0` and commit; re-drive `docs/known-defects.md`; explorer screenshots; CHANGELOG section `## [X.Y.Z] - in progress`.
3. **The Linux preflight on kovacs, on the candidate** (`releasing.md:117`; `Intent: bin/.devbin/cmd/prepush:158-269`). `bin/int prepush --preflight-covers HEAD` prints two lines; hv runs them in a terminal on kovacs. `Intent: bin/.devbin/preflight-linux.sh` clones the checkout over ssh (`:96`), moves one kept target dir into the clone (`:30-39`, so registry deps stay built and the workspace crates rebuild), then runs, in order, with `CARGO_BUILD_JOBS="${PREFLIGHT_JOBS:-1}"` (`:183`, `:213`, one job by default): `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, the library clippy, `cargo doc` under `RUSTDOCFLAGS=-Dwarnings`, `cargo test --workspace --no-fail-fast` (`:205-209`), then `cargo build --release -p intent-cli -p intentd` (`:213`), then `tests/run_tests.sh` (`:222`), and copies a summary back to the Mac, under the user's `.local/share/intent/preflight/<sha>.summary` (`Intent: bin/.devbin/cmd/shared/preflight.lib:11`). Green = first line `run_tests.sh rc=0, N ok, 0 not ok` (`preflight.lib:37`). A green summary covers its commit plus later commits that touch only `intent/whiteboard/` and `intent/.canon/events/` or are the release stamp (`prepush:183-227`); any other landing needs a new run. Measured: summaries for the 3.2.8 candidate `bda94eb0` landed 20:06:26Z (candidate committed 19:52:33Z), for the 3.2.7 candidate `e3fc24de1` at 19:19:20Z (committed 19:03:33Z); five summaries were written on 2026-10-29 between 17:35Z and 19:19Z as landings kept moving HEAD. The latest summary: `preflight-linux at f5db43f2...: run_tests.sh rc=0, 847 ok, 0 not ok` / `steps: fmt clippy clippy-lib doc test run_tests.sh`.
4. **The candidate is pushed to upstream** (the pre-push hook needs the green summary: `prepush:470-482`), which starts `tests.yml` and `rust.yml` on it. For 3.2.8: push at 20:12:56Z; `Intent Tests` 8m05s, `rust` 9m57s.
5. **The cut: `bin/devbin build release --patch` (dry run first), hv's terminal** (`build.d/release`). `preflight()` (`:533-850`), on the candidate HEAD in place and in a worktree:
   - clean tree (`:538`); schema faces carry VERSION (`:549`); on `main` (`:560`); both remotes (`:567-572`); no frozen remote via `bin/int prepush --list-frozen` (`:594`); **a green kovacs preflight covers HEAD** via `bin/int prepush --preflight-covers HEAD` (`:622-627`); `contract_check.sh` (reported, not gating, `:638`); `reference_current_check.sh` (gating, regenerates into scratch and diffs, `:659`); `gh auth status` (`:684`); no live intentd (`:699-706`).
   - `--skip-tests` returns here (`:708-711`); otherwise: `intent doctor` with the built `target/release/intent` (`:716`); **`tests/run_tests.sh`** (the bats suite, 847 tests over 84 files under `tests/unit`, run by `xargs -0 bats` without `--jobs`, `Intent: tests/run_tests.sh:98`) (`:725`); **the rust gate in a private worktree at HEAD with its own target dir** (`:762-848`): `git worktree add --detach` (`:768`), `CARGO_TARGET_DIR="$gate_native/target"` (`:776`), then `cargo build -p intentd` (debug, `:808`), then `bin/int check format`, `clippy`, `panics`, `doc` one after another (`:809-817`; each is `measured --exec cargo ...`, `config.yaml:215-289`), then `cargo test --workspace --no-fail-fast` (`:822`), with one re-run of `cargo test -p intentd` when every red is in the daemon family (`:826-833`). The worktree is removed afterwards (`:837`), so this target dir is **cold on every cut**.
   - Sidecar sync, on the release tree: `intent claude upgrade` dry run for spill (`:987`); `bin/devbin version set` (VERSION + `native/rust/Cargo.toml`, `:1008`); CHANGELOG date (`:1022`); `intent/.config/config.json` stamp (`:1043`); **`INTENT_BLESS=1 cargo test -p intentsvcs schema_faces_drift`** (a debug compile of intentsvcs and its test target at the new version, `:1065-1066`); `cargo metadata` to refresh `Cargo.lock`, refusing any non-member change (`:1130-1170`); **`cargo build -p intent-cli --bin intent`** (debug, `:1188`) to get a stamp CLI reporting the target version; `agents sync` (`:1213`); `claude upgrade --apply` (`:1257`) then a spill check (`:1269`); `sync --to-disk` and a footer-only classification of every re-rendered view (`:1294-1316`).
   - Commit: `git commit --only -- $SIDECAR_FILES $VIEW_FILES` as `release: vX.Y.Z` (`:1368-1370`), which runs `.githooks/pre-commit` (the shipped gate `pre-commit.intent`: guards, critic, doctor; then `bin/int precommit`, `Intent: .githooks/pre-commit:19-20, 107-108`). Leftover check (`:1382`).
   - Tag: `git tag "$TAG"`, lightweight (`:1418`; `git cat-file -t v3.2.8` = `commit`).
   - **The pair at the tag: `bin/devbin build all`** (`pair_at_tag`, `:290-310`, called `:1431`) = `guarded_release_build` (`Intent: bin/.devbin/cmd/shared/releasebuild.lib:63-110`): `cargo clean -p intent-cli -p intentd --release` (`:96`), `cargo build --workspace --bins --release` into `target/staging` (`:98`), `verify_pair`, promote by two renames into `target/release` (`:109`, `:171-188`). Then the pre-push currency verdict over the promoted pair (`:304`).
   - Confirm at `/dev/tty` (`:1451`; a tool session cannot answer, `releasing.md:7`).
   - Push `main` + tag to `local`, then to `upstream` (`:1459-1461`). Each push runs `.githooks/pre-push` -> `bin/int prepush` (`Intent: .githooks/pre-push:21-22`; `core.hooksPath` is `.githooks` in this clone). The hook: currency verdict on `target/release` (`prepush:335`); for upstream, `preflight_covers` on every pushed commit (`:470-482`; the release commit is covered through `release_stamp_only`); then, because the push changes `native/rust/Cargo.toml` and carries a new tag ref (`:421-425` sets FORCE on a new ref; `:490` matches `^native/`), **`git clone --depth 1 file://` of HEAD and a cold `cargo build --workspace --bins`** (debug) in the clone (`:502-510`; `shared/clone.lib:38-43`), then each built binary is run with `--version` (`:516-525`). This happens once per push, so twice per cut. The hook's own comment still says "~16s clone-and-build" (`.githooks/pre-push:13-14`).
   - `gh release create vX.Y.Z --title 'Intent vX.Y.Z' --notes-file <CHANGELOG section>` (`:1505`). Title, notes, no assets.
   - Measured 3.2.8: release commit and tag 20:40:35Z; the pushes at about 20:43:20Z (five CI runs created then); release published 20:43:22Z. So build-all + two hook clone-and-builds + two pushes + read-backs fit in 2m45s on this Mac.
6. **CI on the release commit** (five runs created 20:43:20Z, all on `b14e2745`): `Intent Tests` push-main (test-linux: `cargo build --release -p intent-cli -p intentd` 3m04s with rust-cache, bats 3m44s; shellcheck 6 s; 7m34s total), `rust` push-main (ubuntu: fmt 3 s, clippy 29 s, lib clippy 12 s, doc 11 s, test 5m22s; 6m43s), `Intent Tests` tag (test-linux again 7m27s; test-macos build 6m08s + bats 5m44s = 13m11s), `rust` tag (ubuntu again 6m51s; macos: clippy 1m37s, lib clippy 39 s, doc 26 s, test 9m28s = 13m17s), `linux release` tag (x86_64 `linux build` 4m14s, aarch64 4m04s, package + two smokes about 10 s each; 5m02s). Last to finish: 20:56:43Z.
7. **macOS assets, by hand at the tag** (`releasing.md:119`): `bin/int macos prepare` = `app-sign` (xcodebuild Release of Intent.app), `app-notarize` (`notarytool submit --wait`, `Intent: bin/.devbin/cmd/macos:2173-2178`), `stage` (copies `target/release` into `target/dist`, archives the support tree from the tag's commit), `sign`, `notarize` (`:692-698`, then a `sleep 15` poll until the ticket is visible to Gatekeeper, `:735-743`), `checksum` (`cmd_prepare`, `:1192-1210`); then `bin/int macos publish`: refuses a dev version, an existing own asset, a stage not at the tag, dirty provenance; uploads `intent-aarch64-apple-darwin`, `intentd-aarch64-apple-darwin`, `intent-support.tar.gz`, `Intent.app.zip`; re-downloads and hashes against `SHA256SUMS.txt` (`:1245-1370`, usage `:2205-2260`). Measured: the four macOS assets created 20:47:50Z, 4m28s after the release was published, two Apple notarisations included. (3.2.7: 17m22s after publish.)
8. **Linux assets, by hand: `bin/devbin release attach v3.2.8`** (devbin core, `Intent: bin/.devbin/lib/cmd/release:1793-1900`): waits for the earliest successful `linux-release.yml` run at the tag within `assets.wait` 15m, polling every 15 s (`:1862-1866`), downloads the two artifacts, uploads them, writes `SHA256SUMS` over every asset last, reads everything back at its sha256. Measured: `linux release` finished 20:48:22Z; packages uploaded 20:52:11Z and 20:52:16Z; `SHA256SUMS` 20:52:55Z. (3.2.7: run done 19:57:42Z, packages 20:10:51Z, sums 20:11:14Z.)
9. **Tap: `bin/int brew publish`** (`Intent: bin/.devbin/cmd/brew:164-195`): renders `Formula/intent.rb` (macOS and Linux assets) and `Casks/<token>.rb` from the complete release's `SHA256SUMS`, asks at the terminal, pushes one tap commit. Measured: tap commit `intent 3.2.8` 20:54:17Z. Then `bin/int brew smoke --reinstall` (`brew install` from the tap, then the keg arms, `:265-560`), `intent use brew`, `intent --version`, `intent doctor` (`releasing.md:119`, "the cut ends on brew").
10. **After:** the app swap on this machine (`releasing.md:120-134`), the public site's `db/release.json` and a sites push from the Laksa checkout (`:135`).

Timeline of the last two cuts (all Z):

| | v3.2.7 (2026-10-29) | v3.2.8 (2026-10-30) |
|---|---|---|
| last candidate commit | 19:03:33 | 19:52:33 |
| kovacs preflight summary landed | 19:19:20 | 20:06:26 |
| candidate pushed to upstream (CI on it) | (its push run is not in the 50 listed) | 20:12:56 (tests 8m05s, rust 9m57s) |
| release commit + tag | 19:45:17 (26 min after the summary) | 20:40:35 (34 min after the summary, 27.5 after the push) |
| release object published (after build-all, two hook builds, pushes) | 19:52:22 (7m05s) | 20:43:22 (2m47s) |
| macOS assets attached | 20:09:44 | 20:47:50 |
| linux-release run done | 19:57:42 | 20:48:22 |
| Linux packages + SHA256SUMS | 20:10:51 to 20:11:14 | 20:52:11 to 20:52:55 |
| tap commit | 20:11:41 | 20:54:17 |
| slowest CI run on the release commit done | 20:08:44 (tests tag) | 20:56:43 (tests tag and rust tag) |
| candidate to tap | 68m08s | 61m44s |

The largest serial block on both days is between the kovacs summary and the release commit: 26 and 34 minutes, which is the driver's own preflight (doctor, bats about 5 min locally per `tmp/test/20261029-1909.SHELL.out` 19:09Z to 19:14:16Z, then the cold rust gate) plus the stamp steps. The second block is publish-to-tap: 19 min (3.2.7) and 11 min (3.2.8) of hand-sequenced steps.

### B2. Every gate execution in one release, in order

| # | What executes | Where | On which commit | Trigger |
|---|---|---|---|---|
| 1 | fmt, clippy (all targets), lib clippy, doc, `cargo test --workspace`, release pair build, bats suite; `CARGO_BUILD_JOBS=1` | kovacs, fresh clone, kept target moved in | candidate | hv runs the order the pre-push gate prints (`prepush:232-237`) |
| 2 | pre-push hook on the candidate's push to upstream: currency verdict, preflight cover check, clone + cold debug build if `native/` changed | hv's Mac | candidate | `git push upstream` |
| 3 | `tests.yml` test-linux (release pair build + bats), shellcheck; `rust.yml` ubuntu (fmt, clippy, lib clippy, doc, test) | GitHub ubuntu | candidate | that push |
| 4 | driver preflight: tree checks, reference regeneration diff, `intent doctor`, bats suite | hv's Mac, in place | candidate | `build release` |
| 5 | driver rust gate: `cargo build -p intentd`, `int check format`, `clippy`, `panics`, `doc`, `cargo test --workspace` | hv's Mac, cold worktree + cold target dir | candidate | `build release` |
| 6 | schema faces bless (`cargo test -p intentsvcs schema_faces_drift`), `cargo metadata`, `cargo build -p intent-cli` (debug) | hv's Mac, shared debug target | release tree, uncommitted | `build release` stamp |
| 7 | pre-commit hook: shipped gate (guards, `intent critic`, `intent doctor`) + `bin/int precommit` guards | hv's Mac | release commit | `git commit --only` |
| 8 | `bin/devbin build all`: `cargo clean -p intent-cli -p intentd --release`, `cargo build --workspace --bins --release`, verify, promote | hv's Mac, staging target | release commit (at the tag) | `pair_at_tag` |
| 9 | pre-push hook: currency verdict, clone + cold debug `cargo build --workspace --bins`, run binaries | hv's Mac | release commit | `git push local main vX` |
| 10 | pre-push hook again, plus `preflight_covers` per pushed commit | hv's Mac | release commit | `git push upstream main vX` |
| 11 | `tests.yml` push-main: test-linux (pair build + bats), shellcheck | GitHub ubuntu | release commit | push of `main` |
| 12 | `rust.yml` push-main: fmt, clippy, lib clippy, doc, test (the release commit touches `native/rust/Cargo.toml`, so the `paths:` filter admits it) | GitHub ubuntu | release commit | push of `main` |
| 13 | `tests.yml` tag: test-linux again + test-macos (pair build + bats) | GitHub ubuntu + macos | release commit | push of the tag |
| 14 | `rust.yml` tag: ubuntu again + macos (fmt, clippy, lib clippy, doc, test) | GitHub ubuntu + macos | release commit | push of the tag |
| 15 | `linux-release.yml`: `linux doctor`, `build` (`cargo build --release --locked --target <musl>`, `cmd/linux:127-129`), `package`, `smoke`, `smoke --in oraclelinux:7-slim` | GitHub ubuntu-latest + ubuntu-24.04-arm | release commit | push of the tag |
| 16 | xcodebuild Release of Intent.app; two notarisations; checksum proofs; publish re-download | hv's Mac | release commit (at the tag) | `macos prepare`, `macos publish` by hand |
| 17 | `release attach`: wait for row 15, upload, sums, read back | hv's Mac | release commit | by hand |
| 18 | `brew publish`, then `brew smoke --reinstall` (a `brew install` from the tap and the keg arms) | hv's Mac | release | by hand |

Count per release of the expensive repeats: `cargo test --workspace` runs 6 times (rows 1, 3, 5, 12, 14 ubuntu, 14 macos); the bats suite 6 times (rows 1, 3, 4, 11, 13 ubuntu, 13 macos); the release pair is compiled 7 times (rows 1, 3, 8, 11, 13 ubuntu, 13 macos, and 15 twice for musl), of which exactly three outputs ship (row 8's macOS pair, row 15's two Linux pairs); a cold debug workspace build happens 4 times on hv's Mac (rows 5, 9, 10, and 2 when the candidate push touched `native/`).

### B3. CI trigger matrix

| workflow | push `main` | tag push | pull_request | workflow_dispatch | workflow_run | candidate branch push |
|---|---|---|---|---|---|---|
| `tests.yml` | test-linux, shellcheck (non-blocking, `:534`), test-summary; skipped only when every path is under `intent/whiteboard/**` or `intent/.canon/**` (`:29-36`) | the same plus test-macos (`:292`) | push set (`:37-46`, `branches: [main]`, same paths-ignore) | all incl. macOS (`:47`, `:292`) | none | none |
| `rust.yml` | `rust (ubuntu)` only when a path under `native/rust/**`, `schema/**`, `surface/**` or the workflow changed (`:27-36`) | `rust (ubuntu)` + `rust (macos)` (`:31`, `:66`); no path filter on tags | `rust (ubuntu)` under the same `paths:` (`:37-42`) | ubuntu + macos (`:43`, `:66`) | none | none |
| `linux-release.yml` | no | `package` x2 on `v[0-9]*` (`:24-25`, `:37-45`) | no | `package` x2 (`:23`) | none | none |
| `pr-checks.yml` | no | no | validate-steel-thread (builds `intent-cli` release with rust-cache, `:18-23`), check-documentation, test-coverage, commit-message-check, pr-size-check, doctor-on-the-merge-result (builds `intent-cli` release again, `:210-215`) | no | no | no |

Concurrency: `tests.yml:61-63`, `rust.yml:53-55`, `linux-release.yml:28-30` all group on workflow + event + ref with cancel-in-progress; `pr-checks.yml` has none (`README.md:44`). **Duplicates on the release sha:** `tests.yml` test-linux and shellcheck run twice (push-main run 41125435240 and tag run 41125436120), `rust.yml` ubuntu runs twice (41125434812 and 41125436284); measured 2026-10-30 20:43:20Z, all five runs created in the same second. The same doubling is visible at v3.2.7, v3.2.5, v3.2.4 and v3.2.3 in the run list. `test-summary` needs only test-linux and test-macos (`tests.yml:542`), not shellcheck.

`Intent: .github/workflows/README.md:55-57` says `linux-release.yml` is `workflow_dispatch` only; `linux-release.yml:22-25` has carried `push: tags: ["v[0-9]*"]` since ST0081 WP-02 (its own header `:14-21`).

### B4. Caching and build reuse

- **CI cargo cache:** `Swatinem/rust-cache@v2` with `workspaces: native/rust` in `tests.yml` (both legs, `:189-192`, `:424-427`), `rust.yml` (`:86-91`) and both building jobs of `pr-checks.yml` (`:19-21`, `:211-213`). Effect measured: the release pair builds in 3m04s-3m25s on ubuntu and 6m08s on macOS with the cache; `rust.yml`'s test step 5m22s ubuntu, 9m28s macOS. **No cache in `linux-release.yml`**: each musl leg compiles cold, about 4m05s-4m15s (`linux build` step), every run.
- **Other per-run installs:** bats-core from the source tarball (`tests.yml:86-95`), three bats libraries cloned from GitHub with retries (`:140-156`), `erlef/setup-beam` OTP 29 + Elixir 1.20 (`:193-219`), prettier 3 via npm (`:264-268`), jq; on macOS also Homebrew bats-core, jq, shellcheck, bash (`:311-345`). `rust.yml` adds shellcheck (macOS) and prettier (`:117-154`); `linux-release.yml` adds `musl-tools` via apt (`:60-63`).
- **Locally:** one shared `native/rust/target` (debug and release profiles; `cmd/cache` exists because several sessions share it). The driver's rust gate deliberately does not use it (`build.d/release:750-752, 776`): a worktree with an empty target dir, removed afterwards, so every cut recompiles the whole dependency graph in debug plus clippy's check artefacts plus every test target. `bin/devbin build all` reuses the shared release deps but `cargo clean -p`s the two binaries first (`releasebuild.lib:96`). The pre-push hook builds in a temp clone, cold (`prepush:505`), twice per cut. kovacs keeps one target dir between runs but rebuilds the workspace crates each run because the path moves (`preflight-linux.sh:38-39`), and compiles with one job unless `PREFLIGHT_JOBS` is set (`:183`, `:213`).
- **Release binaries, built once and reused?** The macOS pair: built once at the tag by `build all` (row 8) and copied by `macos stage` into `target/dist`; yes. The Linux pairs: built once per leg by `linux-release.yml` and taken from the run's artifacts by `release attach`; yes. But the **same release pair at the same commit** is also built by `tests.yml` on three legs (push ubuntu, tag ubuntu, tag macos) and by kovacs, only to drive the bats suite, and those four pairs are discarded.

### B5. Serial that need not be

1. The kovacs preflight (14-16 min window), the driver's own rust gate and bats run (26-34 min window), and CI (13m17s longest leg) run the **same five cargo steps and the same bats suite on the same tree** one after another on the human's timeline; only the third is parallel across legs. The driver's gate repeats the preflight's work on the candidate it has just certified green (`preflight()` asks `--preflight-covers` at `:622` and then runs the suite anyway at `:725-822`).
2. Inside the driver's gate the five cargo steps run in series in one cold target dir (`:808-822`); CI's `rust.yml` does the same in series but with a warm cache.
3. The pre-push hook's clone-and-build runs once per remote, so the identical HEAD is cloned and cold-built twice back to back (`:1459`, `:1461`; `prepush:502-510`); the second has nothing the first did not prove.
4. `release attach` waits on `linux-release.yml` (done at 20:48:22Z) but was started after `macos prepare`/`publish` finished (20:47:50Z) and uploaded at 20:52:11Z; `prepare`, `publish` and `attach` touch disjoint assets and could overlap, and the tag run that builds the Linux packages started 2m45s after the tag existed.
5. `brew publish` genuinely needs `SHA256SUMS` over every asset, so it must follow `attach`; `brew smoke --reinstall` then re-downloads and reinstalls what `publish` just verified by re-download.
6. The kovacs preflight is single-job by default (`CARGO_BUILD_JOBS=1`), which makes the one leg nobody else runs the slowest by configuration.
7. The bats suite runs serially everywhere (`run_tests.sh:98`, no `--jobs`): about 3m26s-3m44s on CI ubuntu, 5m44s on CI macOS, about 5 min locally.

### B6. Provenance of the vendored core and divergence

- `Intent: bin/.devbin/manifest.sha256:4-6`: `# devbin_version: 0.1.18`, `# source: install`, `# source_commit: a9b8cd7c11a9e1e0a25ae56b45b9504eee51971e`, identical to Utilz's. The vendored `lib/` and `bin/devbin` are byte-identical to Utilz's and to Devbin HEAD (section A6). `bin/devbin vendor` would report no local patch; `cmd/vendor` shadows the built-in with a manifest-only comparison (`cmd/vendor:13-17`).
- About `a9b8cd7c`: in Devbin it is a parentless commit on `upstream/main` only (`git rev-list --parents -n1` lists no parent; `git branch -a --contains` names `remotes/upstream/main` alone), dated 2026-10-29 17:01Z, subject `devbin 0.1.18`, with `lib/` and `bin/devbin` byte-identical to the tag `v0.1.18` (`f084e101`, `release: v0.1.18`, 2026-10-29 17:01Z) and to Devbin's working HEAD (`7ab68c95`, 2026-10-31 07:05Z). So `source_commit` names the public snapshot of the 0.1.18 release, not a commit in Devbin's working history, and both consumers are on the current core: two days old at the time of writing, with nothing under `lib/` changed since (`git diff --stat a9b8cd7c HEAD -- lib` is empty; the only changes since are Devbin's own `bin/.devbin/cmd/fleet` and its config).
- Divergence from the core is by design and total for the cut: Intent uses the core's `release check` and `release attach` and the built-in `macos` is **not** used (Intent's `cmd/macos`, 2338 lines, shadows it, as does its `cmd/vendor`). Its own handlers on the release path: `build`, `build.d/{all,cli,daemon,release}`, `prepush`, `precommit`, `postcommit`, `hooks`, `macos`, `linux`, `brew`, `local`, `cli`, `measured`, `cache`, `canon`, `suite`, `hosting`, `vendor`, and the libraries under `cmd/shared/` (`artefact`, `brew`, `clone`, `currency`, `measure`, `preflight`, `releasebuild`, `releasestamp`, `runtime`, `rusthost`, `sharedtarget`, `support`). `suite` and `hosting` are clone-and-build instruments outside the cut (`cmd/suite:5-11`, `cmd/hosting:5-9`).
- Config divergence from the catalogue: every `run:` line is wrapped in `bin/.devbin/cmd/measured --exec` (`config.yaml:128-152`); `--manifest-path native/rust/Cargo.toml` on every cargo line because the workspace is not at the root (`:166-182`); `check panics` and `check doc` are project inventions kept flag-for-flag equal to `rust.yml` by `tests/unit/devbin_rust_gates.bats` (`:217-289`); `test toolchain` runs the `#[ignore]` arms with no CI twin (`:195-208`).

### B7. Observations

1. One release runs `cargo test --workspace` six times and the bats suite six times, on two commits that differ only by the version stamp, CHANGELOG date, lock lines and generated footers; three of each are on hv's side of the wall clock (kovacs, then the Mac gate), serially.
2. The driver's rust gate is the one cold compile of the whole dependency graph that happens on every cut, by design (a private worktree with an empty target dir), and it sits in the critical path after a green kovacs run of the same steps.
3. The release pair is compiled seven times per release; three outputs ship.
4. The pre-push clone-and-build runs twice per cut on one HEAD because there are two remotes; its comment's "~16s" predates the workspace it now builds.
5. CI doubles its ubuntu legs on every release sha (push and tag events, two concurrency groups), a cost the fleet's concurrency ruling creates rather than removes.
6. `linux-release.yml` is the only CI workflow without a cargo cache and the only one whose output ships; it is also the one `release attach` waits for.
7. The post-tag path (prepare, publish, attach, brew publish, smoke, use brew) is five hand-sequenced commands with three independent halves (macOS assets, Linux assets, tap); on 2026-10-29 it took 19 minutes and on 2026-10-30 11.
8. The workflows README describes `linux-release.yml` as dispatch-only and the Intent release path as ending at `macos publish`; both moved with ST0081.

Provenance note (2026-10-31 21:06Z): the Intent tmp/check and tmp/test logs this document cites were removed from Intent's working tree at Intent's fifth-fold housekeeping of 2026-10-31 on hv's approval. Both directories are banked whole, mtimes included, in Intent's repository at refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar (blob 2c890aee2e59), with every file's blob, size and mtime listed at refs/bank/vc/housekeep-20261031/manifest.txt (blob 0794b39e959d); from Intent's repository root, `git cat-file blob refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar | tar -xpf -` restores them. Devbin's, Gtools's and Laksa's tmp logs cited here are untouched.
