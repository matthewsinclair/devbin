# E: local timing, kovacs and gyges, and the ruling history

Read-only reconstruction from records on disk, written 2026-10-31T07:27Z (by `date -u`). Every time below is UTC with a trailing Z. File mtimes on rhadamanth were read in local time (+04:00) and converted; stamps in log names are already UTC. Where a figure is an upper bound or an inference it says so. Paths are repo-relative, prefixed by the project name; kovacs paths are relative to its home.

## 1. The record format (Devbin lib/runlog, lib/gatecmd, lib/cmd/release)

- **Every kept gate run is a pair of files** under `tmp/<command>/` (`gate_out_dir`): `<stamp>.<SUFFIX>.out` and `<stamp>.<SUFFIX>.errors`. The stamp is `date -u +%Y%m%d-%H%M`, UTC to the minute, minted once per devbin invocation and reused by every gate of that invocation (issue 0045), so one `check all` writes `20261029-1701.SYNTAX`, `.LINT`, `.CRITIC`, ... on one prefix. A second run in the same minute takes `<stamp>-SS`, then `<stamp>-SS-n` (noclobber, atomic). `LATEST_<SUFFIX>.{out,errors}` symlinks are re-pointed at each deliberate run (not at a witness run, `RUNLOG_WITNESS_RUN=1`).
- **The seal.** `.errors` is seeded with one line, `run in flight (or aborted before sealing) -- no completed verdict; see the .out log`, and `write_errors_file` rewrites it at run end: empty exactly when a completed run was green, the grammar's extracted failures or a log tail when red. A run that was killed keeps the marker. `[ -s <seal> ]` is the machine-readable red flag.
- **Header fields** (`note_invocation`), each line prefixed `devbin| ` so the grammars skip them: `invocation, one argument per line:`, `platform: <uname -sr -m> / bash <version>`, `run: <8 hex run id>` (the key to group one invocation's artefacts on), `from: <config key or catalogue row or "devbin's own ... in this process">`, optional `at: <cwd>` when not the project root, then `argv[i]: ...`.
- **No log carries a start or end timestamp.** `DEVBIN_RUN_T0` is held in memory; the only derived figure printed is the `overhead: N.NNx -- <wall>s of GATE wall against <runner-reported>s ...` line, and only when the runner prints a `Finished in` trailer (cargo, ExUnit); a bats log has none. So in every table below: start = the stamp (minute resolution, or the pair's birth time where it could be read), end = the `.out` mtime. Project-authored gates may add their own lines (Gtools prints `measured: <sha>` after each gate).
- **Retention**: `RUNLOG_KEEP_RUNS` defaults to 5 pairs per suffix per directory; the purge keeps whatever a `LATEST_*` pointer names.
- **The release itself is a sealed gate**: `lib/cmd/release` wraps `cut_run` in `run_gate --label release --suffix RELEASE --grammar generic` and `publish_run` in `--suffix PUBLISH`, so a cut writes `tmp/release/<stamp>.RELEASE.{out,errors}` and a publish `tmp/release/<stamp>.PUBLISH.{out,errors}`. The body holds, in order: any `derived:` command output, each `release: gate: <cmd>` line followed by that gate's own output (its own pair under `tmp/check/`, `tmp/test/` carries the same stamp), the confirm prompt, any `after:` output, then the row table: `resolve, pre-flight, stamp, commit, gates, confirm, tag, push, snapshot, candidate, publish, object, after, ci`, each `done | already | skipped | pending | not reached | FAILED`. When `ci.tag` is on, the `ci` row waits up to `ci.wait` for the tag's CI run, so the RELEASE.out mtime includes that wait. A dry run writes gate pairs but no RELEASE pair.
- **Counts the suites print**: bats `1..N` plus a `lanes: N test(s) ran in parallel and M serially, all K ...` trailer (Devbin's own runner), ExUnit `Finished in S seconds` and `Result: N passed`, cargo `test result: ok. N passed`, xcodebuild `Test run with N tests in M suites passed`.

## 2. Per-project local timelines

### Devbin (latest v0.1.18, cut 2026-10-29)

Release config: `gates: [check all, test all, doctor]`, `remotes: [local]`, `ci.tag: false`, `ci.wait: 90m`, `object: ci`, `publish.url` set (snapshot through a candidate branch), `after: [bin/devbin formula publish]`.

| when (UTC) | what | on | record |
| --- | --- | --- | --- |
| 06:14 to 06:45:30 | `test all`, full, 2777 tests, 9 not ok | rhadamanth | Devbin tmp/test/20261029-0614.bats.out |
| 07:27 to 07:41:50 | `test all`, full, 5 not ok ("hv's test all", commit 217adf65) | rhadamanth | tmp/test/20261029-0727.bats.out |
| 07:51:13 | fix-forward commit 217adf65 | | git log |
| 08:17 to 08:27:40 | `test all`, full, 2777 ok (10m40s) | rhadamanth | tmp/test/20261029-0817.bats.out |
| 08:32:34 to 09:02:27 | K0116: `bin/devbin test all` at 217adf65, 2768 tests, rc 1 (29m53s) | kovacs | kovacs work/devbin-vc/k0116.log, k0116.rc |
| 09:04:19 | fix-forward commit 4d1a76b0 "from K0116 on kovacs" | | git log |
| 09:09:50 to 09:41:36 | K0116b: `test all` at 4d1a76b0, 2777 ok, rc 0 (31m46s; 2 bats jobs on 2 CPUs) | kovacs | kovacs work/devbin-vc/k0116b.log |
| 11:32 to 11:44:01 | **cut v0.1.16**: check all 11:32:27 to 11:33:31; test all 11:33:31 to 11:43:39 (10m08s, 2777 ok); doctor; tag 11:44:00. Gates on release commit 6e193c60, which is 2 commits after 4d1a76b0 | rhadamanth | tmp/release/20261029-1132.RELEASE.out, tmp/test/20261029-1132.bats.out |
| 13:04 to 13:14 | two full `test all` runs, red (3 and 2 not ok, 2826 tests); two targeted runs between | rhadamanth | tmp/test/20261029-1304, -1314 |
| 13:44 to 13:58:49 | **cut v0.1.17**: check all 13:44:52 to 13:46:11; test all 13:46:11 to 13:58:11 (12m00s, 2826 ok); doctor; tag 13:58:48; pushed tag to local only | rhadamanth | tmp/release/20261029-1344.RELEASE.out |
| 15:40 to 15:41:10 | `release publish v0.1.17`: candidate pushed, ci.query 404 (no workflow on the new public default branch), FAILED | rhadamanth | tmp/release/20261029-1540.PUBLISH.out |
| 15:41 to 16:48:01 | `release publish v0.1.17` again: waited 67 min; candidate CI red at the macOS job's `check critic` (issue 0293); nothing moved | rhadamanth | tmp/release/20261029-1541.PUBLISH.out |
| 16:55:14 | fix f1173c13 (0293) | | git log |
| 17:01:41 to 17:16:19 | **cut v0.1.18**: check all 17:01:48 to 17:02:56 (68 s); test all 17:02:56 to 17:16:12 (13m16s, 2827 ok: 2818 parallel, 9 serial); doctor (15 checks); tag 17:16:18 at f084e101; push to local. **14m38s**, no dry run before it | rhadamanth | tmp/release/20261029-1701.RELEASE.out |
| 17:17 to 17:17:14 | `release publish v0.1.18`: FAILED at confirm (no terminal, no --yes) | rhadamanth | tmp/release/20261029-1717.PUBLISH.out |
| 17:17:30 to 18:13:50 | `release publish v0.1.18 --yes`: snapshot a9b8cd7c to candidate/v0.1.18; CI run 40919937412 green; main fast-forwarded, tag pushed, candidate deleted; release object "within 20m"; `after: formula publish` FAILED (nobody to ask), run by hand after. **56m20s, nearly all waiting on CI** | rhadamanth | tmp/release/20261029-1717-30.PUBLISH.out |
| 18:37:16 | brew devbin 0.1.18 installed | gyges | Cellar dir mtime |
| 19:36:01 | brew devbin 0.1.18 installed | kovacs | Cellar dir mtime |

Totals for v0.1.18: local cut 14m38s plus publish 56m20s = 71 minutes of pipeline wall, of which about 14 minutes is the local suite and about 55 minutes is waiting on the public repository's CI. For the day (three cuts, two publishes) the pipeline wall was about 2h50m. Earlier cuts for comparison: v0.1.15 on 2026-10-26 ran test all 17:24:14 to 17:45:06 (20m52s) and pushed to two remotes (tmp/release/20261026-1720.RELEASE.out); its pre-flight row records the `ci.base` read ("CI is green on the base commit ... run 40349359447"), the 0223 rule that `publish.url` later replaced.

How many times the Devbin suite ran on 2026-10-29: 8 full executions on rhadamanth (5 by hand, 3 inside cuts), 2 on kovacs, 3 in CI (two candidates and the v0.1.18 tag, whose whole-matrix repeat is what issue 0294 removed on 10-30): 13 full-suite executions to ship 0.1.16, 0.1.17 and 0.1.18, each 2768 to 2827 tests.

### Utilz (latest 2.14.8, cut 2026-10-30)

Release config: `gates: [check all]` only, `tag: "{version}"`, remotes undeclared (local and upstream), `after: [tools/post-cut]`, `ci.query: tools/ci-state`. Utilz docs/releasing.md: the gate is check all (hv, 28 Oct, ST0030); `test estate` runs before the cut and "not again in it".

| when (UTC) | what | record |
| --- | --- | --- |
| 20:05:54 | last code commit before the cut (878994e8) | git log |
| 18:25 | vc decision 74: "hv controls build and release and runs the full suite; no Claude test or build", "hv's suite run added" to wip.md. **No seal of that run exists**: Utilz tmp/test holds only six dangling `LATEST_*` symlinks (their targets, 20261028-1238.ESTATE and 20261029-1846.RUST/SHELL, are gone; retention keeps pointed-at pairs, so this was not the purge) | git log 6061218d; `ls tmp/test` |
| 20:59:05 | cut log opened | tmp/release/20261030-2059.RELEASE.out birth, LATEST_RELEASE pointer |
| 20:59:11 | release commit f2021ddc (committer date) | git log |
| 20:59:15 to 20:59:16 | check all: 6 options (clippy cached 0.16 s, format, autotests, targetdir, toolchain, critic with nothing staged). **About 1 second** | tmp/check/20261030-2059.*.out |
| 20:59:22 | tag 2.14.8 | taggerdate |
| after the tag | push, release object (URL printed), then `after: tools/post-cut`: app-sign (xcodebuild Release), app-notarize (Apple: Accepted), publish (Menuz.app.zip attached, SHA256SUMS), formula publish to the tap, tap clone pulled | RELEASE.out body |
| 21:02:02 | last write to the log. **The run never sealed**: `.errors` still holds the in-flight marker (84 bytes), there is no row table and no `ci` row. The cause is not on disk; the shape matches a run ended before its `ci` step returned | tmp/release/20261030-2059.RELEASE.errors |
| 21:12:29 | brew utilz 2.14.8 on gyges; 22:30:14 on kovacs | Cellar mtimes |

Local half of the 2.14.8 cut, bounded by mtimes: 2m57s (20:59:05 to 21:02:02), of which the gate is about 1 s and post-cut (build, sign, notarise, attach, tap) the rest. No `test all` ran in the cut by design, and no record of a pre-cut suite survives. 2.14.7 (10-29 18:57:30) has no release log on disk at all.

### Gtools (latest v0.8.3, cut 2026-10-30)

Release config: gates default (`check all`, `test all`), `derived: [tools/lock-sync, bin/devbin build, bin/devbin build cms]`, remotes local and upstream, `ci.query: tools/ci-state`, `ci.wait: 45m`, `after: [bin/devbin formula publish]`. The `ci` row waits for the tag's run because the macOS job starts on a tag (Gtools hv decision 30; issue 0149).

| when (UTC) | what | record |
| --- | --- | --- |
| 20:50:30 | last code commit 276f482b (issue 0123) | git log |
| 20:51:41 | 41c283a8, the candidate: hv pushed it; CI run 41127185022 by dispatch; a suite run on kovacs and one on gyges (issue 0295). **No artefact of the kovacs or gyges run survives**: gyges' Gtools clone has no tmp/, kovacs holds no Gtools clone and its /var/tmp/cc-* files were cleaned (Gtools intent/wip.md item 9) | issue 0295; vc commit 7048d65f "the green runs at 41c283a8" |
| by 21:31 | `tools/install-proof` 20 of 20 on the candidate | vc commit 1fafc878 |
| 21:54:47 | **cut** log opened; `derived:` ran: lock-sync, gtools-rs rebuilt (cargo 13.95 s), cms compiled; release commit 79c9233d at 21:55:12 | tmp/release/20261030-2154.RELEASE.out; LATEST_RELEASE mtime |
| 21:55:16 to 21:55:32 | check all: 13 options, 16 s | tmp/check/20261030-2154.*.out |
| 21:55:33 to 22:04:08 | test suite: `bin/gtools test --strict`, 868 ExUnit tests, `Finished in 470.4 seconds`, overhead line `515s of GATE wall`; the Rust suite (260) is built and run inside it | tmp/test/20261030-2154.SUITE.out |
| 22:04:08 to 22:04:27 | test app: xcodebuild, 123 tests, 18.5 s | tmp/test/20261030-2154.APP.out |
| 22:04:37 | tag v0.8.3; push local and upstream; object; `after: formula publish` (yes taken from the confirm) | taggerdate; RELEASE.out rows |
| 22:04:37 to 22:18:37 | `ci` row: waited for tag run 41135649951 green. **14 minutes** | RELEASE.out mtime |
| 22:21:10 | brew gtools 0.8.3 on gyges; 22:31:16 on kovacs | Cellar mtimes |

Cut total 23m50s: about 10 minutes of local work (29 s derived builds, 16 s check all, 515 s suite, 19 s app tests, seconds to tag and push) and about 14 minutes waiting for CI on the tag. The three cuts of 10-29 had the same shape: v0.8.0 (first attempt 14:55 FAILED at check all; 14:58 resumed: suite 453 s wall, tag 15:07:22, ci green 15:20:50 = 13.5 min wait), v0.8.1 (17:02 attempt failed in the suite; 17:11: suite 585 s, tag 17:22:15, closed 17:37:02 = 14.8 min wait), v0.8.2 (19:08: suite 527 s, tag 19:20:21, closed 19:32:59 = 12.6 min wait). On 10-29 the Gtools suite ran 12 times on rhadamanth (3 in cuts that tagged, 2 in cuts that stopped, 7 by hand or dry run, eg the check at 16:07 and suite at 16:08 with no RELEASE pair). The suite takes 427 to 585 s per run here; cargo and mix are warm.

### Intent (latest v3.2.8, cut 2026-10-30)

Intent does not use devbin's release core: `bin/devbin build release` (Intent bin/.devbin/cmd/build.d/release) runs its own order: pre-flight (tree, remotes, gh, canon spill, `int prepush --preflight-covers HEAD` which requires a green kovacs summary for HEAD, contract check, intentd not running, intent doctor, `tests/run_tests.sh`, the rust gate in a private worktree: build intentd, four check twins, `cargo test --workspace`), then sidecar sync, schema faces, lock, stamp, commit, tag (lightweight), build the pair at the tag, confirm, push both remotes, GitHub release, then the Linux assets from `linux-release.yml` (`assets.wait: 15m`). Gates therefore run BEFORE the stamp, on the candidate, and their logs go to `$TMPDIR/intent-release-gates.XXXXXX/`, removed on success, not to tmp/test. Its tags are lightweight (no tagger date; the commit date is the tag date).

| when (UTC) | what | record |
| --- | --- | --- |
| 19:52:33 | candidate bda94eb00 (ST0087 closed "so that kovacs can run 3.2.8's Linux preflight") | git log |
| by 20:06:26 | kovacs preflight-linux at bda94eb00: fmt, clippy, clippy-lib, doc, cargo test, release build, run_tests.sh: 847 ok, 0 not ok. At most 14 min after the commit; the run directory (with run.log and its start stamp) has been removed | kovacs work/intent-preflight/bda94eb0....summary; the copy under rhadamanth's `.local/share/intent/preflight/` |
| 20:31:27 to 20:39:46 | **the cut's pre-flight gates on rhadamanth**: gate dir `intent-release-gates.NnoSaf` born 20:31:27, bats fixture dirs born 20:33:33 to 20:37:38, last log removed 20:39:46. **8m19s** for doctor, 847 bats and the rust gate | `$TMPDIR` birth and modification times |
| 20:40:35 | release commit b14e27456, tagged v3.2.8 (49 s after the gates ended: the tagged commit differs from the tested one by the version stamp only) | git log |
| 21:11:51 | brew intent 3.2.8 on gyges; 22:29:18 on kovacs | Cellar mtimes |
| by 23:03:07 | a second kovacs preflight at f5db43f20 (a wip.md-only commit), 847 ok, for the final push | summary mtime |

3.2.7 on 10-29, for the pattern: `bin/devbin test all` at 19:09 (SHELL = run_tests.sh, 59879-byte log, ended 19:14:16; RUST = cargo test, ended 19:17:45), kovacs preflight at e3fc24de1 by 19:19:19 (commit 19:03:33, so at most 15m46s), a first release run (dry run by the documented procedure "ideally --dry-run first") born 19:25:45 and emptied 19:34:03 (8m18s), the cut born 19:36:12 and emptied 19:44:39 (8m27s), tag 19:45:17. The Intent suite ran three times on rhadamanth and once on kovacs inside 36 minutes for one patch release, after four earlier `test all` runs that day (15:19, 17:27, 17:33, 18:25, 18:50 under tmp/test) and four earlier kovacs preflights (17:35 red at clippy, 17:41 red at cargo test, 18:03 green, 18:57 red at cargo test). The kovacs preflight record: 17 summaries 10-23 to 10-30, 12 green, 5 red (two of them caught Linux-only cargo-test failures before a push).

### Laksa (no releases; build, test, deploy)

- `bin/devbin test all` = RUST (cargo test on native/cli, which re-drives its own crate gate four or five times as witness runs, the 662-byte red seals), MIX (test-mix), CREDO. The newest full green run, Laksa tmp/test/20261028-1957.*: 19:57 to 20:00:53 (about 4 minutes): MIX `Finished in 190.5 seconds`, `5219 passed (88 doctests, 5131 tests), 201 excluded`, max_cases 32; credo 7.2 s over 1154 files. Red runs 10-27 (6 failed, 123 KB log). 10-30 15:25 to 15:30: six narrowed MIX runs (eg `narrowed to: test/cli/fmt_md_paths_test.exs`).
- Deploy: Laksa tmp/deploy/20261017-1342.{CREDO,MIX}: a gate with out-dir `deploy` re-ran credo and the full mix suite (`Finished in 88.1 seconds`, `4685 passed`) at 13:42 to 13:44 on 10-17 before deploying. The command that wrote it is not in the current tree (no bin/deploy, no cmd/deploy; config.yaml only notes that `fly deploy` tars the working tree), and there is no deploy record after 10-17. So on Laksa the suite runs once in `test all` and once again inside the deploy.

### Conflab (latest v0.6.2, 2026-08-25)

- Conflab cuts with its own handler, Conflab bin/.devbin/cmd/release (bin/release is a shim to it; no `release:` block in config): pre-flight via `conflab check` and `conflab test`, version sidecars synced and committed, push main, tag, push tag; the macOS build, sign, notarise and publish run in `release.yml` on a macOS runner or, with `--local`, on this Mac (docs/notes/tn001).
- Timeline of the last release: v0.6.1 at 07:59:43, v0.6.2 at 09:05:15 ("Bump version to 0.6.2", 98 s after the previous commit), next commit 09:15:53. No gate seal from that day survives; Conflab tmp/test holds only 10-30's eleven SWIFT runs (14:31 to 14:34, `418 tests in 54 suites ... 2.641 seconds` each, five of them red), so the local half of a Conflab release cannot be timed from disk. 641 commits have landed since v0.6.2 without a release.
- tn001 is the one narrative of a release going long: during v0.2.0 the macOS runner job "burns through the ... included 2,000 Actions minutes at 10x the Linux rate", the quota hit 100% mid-release with the job queued, and the full CI release chain is "80-120 billable minutes per run". That is why `MACOS_RELEASE_CI` gates the CI path and `--local` exists.

## 3. kovacs and gyges

**kovacs** (read 07:11Z): Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic, aarch64, 2 CPUs, 3379 MB RAM (927 used, 2452 available), 3898 MB swap. It holds **no persistent clone of any project** (`Devel/prj` is empty), so "behind rhadamanth" does not arise; every run is a fresh clone. What is there:

- `work/preflight-linux.sh` (Intent's order, fetched from the commit under test) and `work/intent-preflight/`: 17 `<sha>.summary` files (10-23 to 10-30) and one shared cargo `target/` moved into each clone and back; the per-run directories with `run.log` are gone, so no kovacs start time survives. The leg is: clone over ssh from the Mac at a sha, `cargo fmt --check`, `clippy --all-targets`, the library clippy, `cargo doc`, `cargo test --workspace`, `cargo build --release -p intent-cli -p intentd` (jobs 1), `cd tests && ./run_tests.sh` under `LANG=C.UTF-8`, SIGPIPE ignored, XDG empty, a leg-only PATH; the summary's first line is what `int prepush --preflight-covers` reads on rhadamanth. Green summaries: 804 to 847 ok. Bound on wall: 14 to 16 minutes from the tested commit's date to the summary's mtime (eg bda94eb00 19:52:33 to 20:06:26; e3fc24de1 19:03:33 to 19:19:19).
- `work/devbin-vc/`: the Devbin orders K013/K013b (10-24, install proofs), K115 (10-26, main c4f52b8e, 2561 tests, 08:52:53 to 09:22:40, rc 1 on the 0234 arm), K0116 (10-29, 217adf65, 2768 tests, 08:32:34 to 09:02:27, rc 1) and K0116b (10-29, 4d1a76b0, 2777 tests, 09:09:50 to 09:41:36, rc 0). Each: a bundle copied from the Mac, verified by sha256, cloned, `bin/devbin test all` with `CARGO_BUILD_JOBS=1`, GNU parallel 2 jobs, verdict read from the clone's seal; 30 to 32 minutes per run against 10 to 13 on rhadamanth.
- `work/devbin-cc/legd.*` (10-26): a brew-keg install proof, not a suite.
- brew: devbin 0.1.18 (10-29 19:36:01), intent 3.2.8 (10-30 22:29:18), utilz 2.14.8 (22:30:14), gtools 0.8.3 (22:31:16). 300 `/tmp/intent-release-gates.*` directories, newest 10-29 19:18, are the Intent suite's own arms run during preflights, not releases.
- The kovacs leg of a release, from the evidence: for Intent a fresh-clone preflight of the candidate before every push to upstream and before the cut (two per release day is common: the candidate, then the final board-only push); for Devbin a full `test all` of main's head before a cut, run as a booked order and read by a node (two on 10-29, the first red); for Gtools a suite run on the candidate on 10-30 (attested, not preserved); for Utilz only `brew upgrade` and doctor after the tap is published (docs/releasing.md).

**gyges** (read 07:11Z): macOS Darwin 27.2.0 arm64 (T8112), 8 CPUs, 16 GiB. Clones: Gtools at 80d35ead, equal to rhadamanth's HEAD, last fetched 2026-10-31 07:04:58, with **no tmp/ directory** (no gate has run in that clone, or its logs were removed), and Pplr. brew: devbin 0.1.18 (10-29 18:37:16, 24 min after the publish finished), intent 3.2.8 (10-30 21:11:51), utilz 2.14.8 (21:12:29), gtools 0.8.3 (22:21:10, 2.5 min after the cut's ci row went green); Gtools.app 0.8.3 installed. Its role in the last releases is the brew-consumer and GUI app install (Gtools docs/releasing.md: `bin/gtools app install` from a checkout at the tag, in a GUI session; "On each brew machine: brew upgrade"); the suite run on candidate 41c283a8 that issue 0295 attributes to gyges left nothing on disk there.

## 4. The ruling history

| date | where | ruling and reason | cost or confidence |
| --- | --- | --- | --- |
| 2026-09-02 | Devbin issue 0052 | CI had been red on main since 08-27 through the 0.1.0 release, and the tagged commit never had a run (two commits pushed together, only the tip ran). Set the requirement that the verdict be read on the exact commit. | confidence |
| 2026-09-16 | ST0007 D40 (hv decision 26) | CI does not gate the release: "just do it and fail forward". The ci step reports the tagged commit's verdict after the push and the release stands; a red is fixed by the next patch. | throughput (hv's preference over waiting) |
| 2026-09-17 to 09-18 | ST0007 D38 v0.3 and v0.4 | Gates run on the release commit, after the stamp and the commit, so the tagged commit is the one examined; in place rather than in a detached worktree "because a compiled estate (a mix or cargo build) rebuilds from nothing there on every release", with pre-flight refusing dirt and the gates step failing on any path a gate wrote. This is the order issue 0295 now contests. | the in-place choice is cost (rebuild time); the order is confidence |
| 2026-09-19 | issue 0064 closed | The release core ships; three per-project orchestrators (2408 lines) retire into it. | |
| 2026-09-21 | issue 0108 (hv) | A macOS minute costs ten times a Linux one, so the macOS job runs only on release tags and on demand, never on a push to main; every repository cancels superseded runs; devbin to go public, which makes CI free. | cost |
| 2026-09-22 | issue 0110 (hv) | "Minimise warnings"; `paths-ignore` for board-only pushes so they start no run. | cost |
| 2026-09-25 to 09-26 | issue 0149 | Gtools v0.4.0's ci step read a branch run green and ended before the tag's macOS leg existed; the query now reads the tag's run (`DEVBIN_RELEASE_TAG`) and the cut waits for it. This is the 12 to 15 minute `ci` wait in every Gtools cut. | confidence |
| 2026-09-26 | issue 0151 | Two arms pass under BSD and fail on every Ubuntu run: v0.1.8's tag red on test-only defects; "every local run is macOS". | confidence (first Linux-only red) |
| 2026-10-03 to 10-06 | issue 0155 | shellcheck reached a change only at the cut (68 s serial); made parallel and put in the suite. | |
| 2026-10-07 to 10-08 | issue 0180 | 0.1.9's CI red on Ubuntu (xargs, expect); reproduced in a container. | confidence |
| 2026-10-08 | issue 0191 | CI linted the tree twice, a test waited out a 15 s floor, the heartbeat took whole seconds: waits trimmed. | time |
| 2026-10-12 | ST0008 "Proven on Linux before anything is pushed" (hv) | "I want to run the tests here in the Ubuntu VM, and not push to GH until we know it works properly." kovacs provisioned (2 CPUs, 3.3 GB), runs as booked orders, D1/D1b/D1c measured. The kovacs leg starts here. | confidence |
| 2026-10-14 to 10-17 | issue 0194 | The 0.1.10 cut stopped on a 15 s remote read-back with both remotes holding the release. | |
| 2026-10-16 | ST0008 D50, Q2, Q9 (hv) | The WSL leg runs on tags and dispatch only and blocks nothing, because "every Windows minute bills at twice Linux's" on a private repository; it lives in devbin's repository "on tags and dispatch alone it runs a handful of times". | cost |
| 2026-10-16 | ST0008 D55 (hv) | CI-built assets are attached by the release core (one writer). | |
| 2026-10-17, 10-24 | ST0009, issue 0201 | brew install on rhadamanth and kovacs; `brew upgrade devbin` proven at 0.1.13 on both. | |
| 2026-10-23 | Intent, hv ruling (preflight.lib, preflight-linux.sh header) | After 3.2.5's tag went red on GitHub for a Linux-only failure "that could have been found with a simple test run on Kovacs": a kovacs preflight before every push to upstream, enforced by `int prepush`. 3.2.6's tag then went red on a Linux-only clippy lint, so the preflight gained every rust.yml step. | confidence |
| 2026-10-24 | issue 0223 (hv ruling), 0222 | The pre-flight requires CI green on the base commit before a cut (`release.ci.base`), so a Linux-only defect (v0.1.14's RUSTUP_HOME red, invisible on a Mac) is caught before the tag. | confidence |
| 2026-10-26 | issues 0233, 0234, 0236, 0237, 0238 | Ubuntu reds from git background maintenance and a kovacs-only second cargo (K115); the 0.1.15 cut blocked by a CI red; `check critic` exit 4 made every cut with nothing staged red (hv: Intent returns to exit 0); an abandoned macOS job read as FAILED. | confidence |
| 2026-10-27 to 10-28 | issue 0274 (hv) | hv ran about ten projects' suites at once on rhadamanth (10-27 14:42Z) and every timeout that day came from the contention; a machine-wide lock was proposed; hv closed it as not doing. | time |
| 2026-10-27 to 10-29 | issues 0239, 0240, 0241, ST0010 | devbin publishes a product-only snapshot through `candidate/<tag>` in the public repository; the cut pushes to local only; publish waits for CI green on the candidate ("nothing becomes public before CI is green on the very commit that does"); `ci.base` is refused under `publish.url`. | confidence, and cost (public minutes are free) |
| 2026-10-28 | Utilz ST0030 (hv) | The Utilz cut's gate is `check all`; `test estate` runs before the cut and not in it; post-cut signs, notarises, attaches and publishes the tap inside the cut on the one yes. | time |
| 2026-10-29 | issue 0293 | v0.1.17's candidate red at the macOS job's `check critic` (the snapshot has no intent/); the macOS job runs named gates; 0.1.18 cut the same day to carry it. | confidence |
| 2026-10-29 to 10-30 | issue 0294 | `release publish` ran the whole matrix twice on one commit (candidate, then tag); a Candidate verdict job now skips every leg on a tag whose commit is green on its candidate. Landed 10-30 14:28; live proof awaits the next publish. | cost and time |
| 2026-10-30 | issue 0295 (open; hv in intent-vc's session while the Gtools ci row waited) | "I really don't get why this is done twice ... It feels like we run the same damn test suite four or fives times per release." Measured: Gtools 0.8.3's suite ran five times for two commits differing by a version string and a date; GitHub also ran CI twice on the release commit (main push and tag, two seconds apart). Ruling recorded in Intent wip.md: "stamp first, test once, tag what passed. The kovacs run stays (hv)." | time |
| 2026 (Conflab tn001) | Conflab docs/notes/tn001 | The CI release chain is 80 to 120 billable minutes at 10x; the quota hit 100% mid-release during v0.2.0; `MACOS_RELEASE_CI` gates it and `--local` builds, signs and notarises on a Mac. | cost |

## 5. Measured facts, with their evidence

1. A Devbin full suite takes 10m08s to 13m16s on rhadamanth (2777 to 2827 bats tests, 8 parallel jobs on 16 CPUs): Devbin tmp/test/20261029-1132.bats.out (11:33:31 to 11:43:39Z), 20261029-1344 (13:46:11 to 13:58:11Z), 20261029-1701 (17:02:56 to 17:16:12Z). On kovacs the same suite takes 29m53s to 31m46s (2 CPUs, 2 jobs): kovacs work/devbin-vc/k0116.log and k0116b.log (`start`/`end` lines).
2. A Devbin cut (check all, test all, doctor, tag, push to local) is 12 to 15 minutes of local wall, 85 to 90 percent of it the suite: tmp/release/20261029-{1132,1344,1701}.RELEASE.out against the tagger dates 11:44:00Z, 13:58:48Z, 17:16:18Z. check all is about one minute, doctor seconds.
3. A Devbin publish is 56 to 67 minutes, nearly all of it waiting on the public repository's CI and release workflow: tmp/release/20261029-1541.PUBLISH.out (15:41 to 16:48:01Z, candidate red) and 20261029-1717-30.PUBLISH.out (17:17:30 to 18:13:50Z, green). v0.1.18 cost 14m38s local plus 56m20s publish: about 71 minutes end to end, the "hour or more".
4. On 2026-10-29 the Devbin suite executed 13 times to ship three patch releases: 8 on rhadamanth (5 by hand, 3 in cuts), 2 on kovacs, 3 in CI (tmp/test listing; kovacs logs; the PUBLISH rows and the tag run named in the 0.1.18 notes).
5. A Gtools cut is about 24 minutes, 10 of them local and 14 waiting for the tag's CI: tmp/release/20261030-2154.RELEASE.out (opened 21:54:47Z, tag 22:04:37Z, closed 22:18:37Z); the suite alone is 427 to 585 s of wall per run (`overhead:` lines in tmp/test/2026102{9,30}-*.SUITE.out). Every cut on 10-29 waited 12.6 to 14.8 minutes at its ci row the same way.
6. Gtools 0.8.3's suite ran five times, four of them on commits that differ by the version stamp alone (issue 0295): dispatch CI, kovacs and gyges on the candidate 41c283a8; the cut's gates and the tag's CI run on 79c9233d; plus a sixth, the main-push run on the same commit. On rhadamanth only the cut's run is on disk (tmp/test/20261030-2154.SUITE.out); the kovacs and gyges runs left no artefact on either machine.
7. Intent's cut gates run BEFORE the stamp, on the candidate, and take about 8 minutes on rhadamanth: `$TMPDIR/intent-release-gates.NnoSaf` born 20:31:27Z, emptied 20:39:46Z, release commit b14e27456 at 20:40:35Z; for 3.2.7, a dry run (born 19:25:45Z, 8m18s) and the cut (born 19:36:12Z, 8m27s) back to back after a hand `test all` at 19:09Z and a kovacs preflight that ended 19:19:19Z: four full runs in 36 minutes. A kovacs Intent preflight is at most 14 to 16 minutes from commit to summary (summary mtimes against commit dates); its own duration is gone with its run directory.
8. Utilz runs no suite in the cut (config `gates: [check all]`); the 2.14.8 cut's gate took about one second and the whole local half, notarisation and tap included, 2m57s (tmp/release/20261030-2059.RELEASE.out, 20:59:05 to 21:02:02Z). That log never sealed (`.errors` carries the in-flight marker, no row table), and no 2.14.8 test seal exists on disk (tmp/test holds dangling pointers only), so the one pre-cut suite run hv made that day (vc decision 74) is unrecorded.
9. Laksa's `test all` is about 4 minutes (MIX 190.5 s for 5219 tests, cargo, credo 7 s: tmp/test/20261028-1957.*), and the deploy of 10-17 re-ran credo and the full mix suite (88 s, 4685 tests) under tmp/deploy/20261017-1342.* before deploying: the suite runs twice per deploy.
10. Conflab's last release is from 2026-08-25 (v0.6.1 07:59:43Z, v0.6.2 09:05:15Z, cut by its own handler, not the core); no gate record from it survives; its CI release chain is 80 to 120 billable minutes at the 10x macOS rate (docs/notes/tn001).
11. The same commit's suite runs again after the stamp wherever devbin's core cuts (Devbin, Gtools, Utilz-shaped projects with a test gate), because ST0007 D38 put the gates after the commit; Intent's own order tests first and stamps after, which is what issue 0295 asks the core to do.
12. Brew propagation after a cut: gyges within 2.5 to 31 minutes (Cellar mtimes 10-29 18:37:16Z, 10-30 21:11:51Z, 21:12:29Z, 22:21:10Z), kovacs within 21 to 126 minutes (19:36:01Z, 22:29:18Z, 22:30:14Z, 22:31:16Z).
13. Evidence absent, stated rather than estimated: start timestamps inside any gate log (none exist by design); Utilz's test seals and its 2.14.7 release log; the Gtools candidate runs on kovacs and gyges; the Intent kovacs run directories (durations); Conflab's August gate logs; Laksa's deploy command (not in the current tree); any dry run before Devbin's v0.1.18 cut (none on disk).

Provenance note (2026-10-31 21:06Z): the Intent tmp/check and tmp/test logs this document cites were removed from Intent's working tree at Intent's fifth-fold housekeeping of 2026-10-31 on hv's approval. Both directories are banked whole, mtimes included, in Intent's repository at refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar (blob 2c890aee2e59), with every file's blob, size and mtime listed at refs/bank/vc/housekeep-20261031/manifest.txt (blob 0794b39e959d); from Intent's repository root, `git cat-file blob refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar | tar -xpf -` restores them. Devbin's, Gtools's and Laksa's tmp logs cited here are untouched.
