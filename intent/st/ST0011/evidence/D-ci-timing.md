# D. CI timing evidence: build, test and release cycle across six projects

Read-only evidence pulled on 2026-10-31 from the GitHub Actions record (`gh run list`, `gh run view --json jobs`, `gh api` GET) and from each project's local clone (`git log`, `git tag`, and the cut logs the release core leaves under `tmp/release/` and `tmp/check/`). All times are UTC. Durations are minutes with one decimal. Job duration is `completedAt - startedAt`; queue wait is the job's `startedAt` minus the run's `createdAt`; a run's wall-clock is `updatedAt - createdAt`. Runner OS comes from the job's labels (`ubuntu-latest`, `ubuntu-24.04-arm`, `ubuntu-26.04`, `macos-latest`, `xcode-27`, `windows-latest`), checked against the workflow files; `xcode-27` is a GitHub-hosted macOS runner and is counted as macOS. Billed-equivalent minutes weight macOS x10 and Windows x2. Skipped jobs count nothing.

Window per release: every run whose head sha is the tag's commit or the candidate commit, plus every run on `main`, the tag ref or a `candidate/**` ref created between 3 hours before and 2 hours after the release commit's time. Windows of releases cut within hours of each other overlap, so some runs appear under two releases; the per-release derivations therefore give two spans, one over the release shas alone and one over the whole window. In all, 95 runs and 334 job rows were examined (66 release-window rows, 60 baseline rows, overlapping).

## 1. Cross-project summary

Columns: runs in the window; runs on the release shas (tag commit plus candidate commit); duplicate sets (groups of 2+ runs on one sha) and the runs in them; ubuntu / macOS / windows machine-minutes on the release shas; billed-equivalent; wall-clock over the release shas (first run created to last run updated); the longest single job.

| project | release | runs in window | runs on release shas | dup sets | runs in dup sets | ubuntu min | macOS min | windows min | billed-eq min | wall-clock release shas | wall-clock whole window | longest job |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Devbin | v0.1.18 | 4 | 3 | 1 | 3 | 50.9 | 63.4 | 66.7 | 817.9 | 63.8 | 160.3 | Test in WSL 2 (Ubuntu 26.04) in run 40919937412, 59.1 min |
| Devbin | v0.1.17 | 1 | 1 | 0 | 0 | 47.1 | 66.3 | 60.2 | 830.1 | 66.5 | 66.5 | Test on macOS (bash >= 5 floor) in run 40904076298, 66.3 min |
| Devbin | v0.1.16 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | - | - | none |
| Utilz | 2.14.8 | 6 | 4 | 2 | 4 | 71.4 | 67.2 | 0 | 743.6 | 86.5 | 208.7 | Rust (macos-latest) [attempt 1, cancelled before the rerun] in run 41127538028, 22.9 min |
| Utilz | 2.14.7 | 3 | 2 | 1 | 2 | 28.9 | 28.7 | 0 | 316.2 | 14.8 | 73.3 | Test on macOS in run 40935690642, 14.6 min |
| Utilz | 2.14.6 | 3 | 2 | 1 | 2 | 33 | 27.3 | 0 | 305.6 | 14.8 | 53.3 | Test on macOS in run 40879031120, 14.5 min |
| Gtools | v0.8.3 | 6 | 4 | 2 | 4 | 8.9 | 28.2 | 0 | 290.4 | 82 | 223.8 | suite + app (macos) in run 41127185022, 14.5 min |
| Gtools | v0.8.2 | 4 | 2 | 1 | 2 | 4.3 | 12.2 | 0 | 126.3 | 12.4 | 164.2 | suite + app (macos) in run 40939207690, 12.2 min |
| Gtools | v0.8.1 | 3 | 2 | 1 | 2 | 4.2 | 14.2 | 0 | 146.2 | 14.4 | 149.3 | suite + app (macos) in run 40920695516, 14.2 min |
| Intent | v3.2.8 | 7 | 7 | 2 | 7 | 50.9 | 26.5 | 0 | 315.5 | 43.8 | 43.8 | rust (macos-latest) in run 41125436284, 13.3 min |
| Intent | v3.2.7 | 5 | 5 | 1 | 5 | 34.7 | 24.3 | 0 | 278.1 | 16.4 | 16.4 | Test on macOS in run 40943953013, 16.2 min |
| Intent | v3.2.6 | 5 | 5 | 1 | 5 | 25.4 | 19.1 | 0 | 216.3 | 23.4 | 23.4 | rust (macos-latest) in run 40093074766, 10.1 min |
| Conflab | v0.6.2 | 3 | 2 | 1 | 2 | 14.1 | 0 | 0 | 14.1 | 7.7 | 73.2 | Rust tests (daemon) in run 32830044144, 7.5 min |
| Conflab | v0.6.1 | 3 | 2 | 1 | 2 | 16.1 | 0 | 0 | 16.1 | 7.2 | 73.2 | Rust tests (daemon) in run 32824335720, 7.2 min |
| Conflab | v0.6.0 | 9 | 3 | 1 | 2 | 16.4 | 0 | 0 | 16.4 | 7.4 | 121.1 | Elixir tests + quality in run 29109115655, 3.5 min |
| Laksa | push-d299dda7 | 1 | 1 | 0 | 0 | 16.8 | 0 | 0 | 16.8 | 16.8 | 16.8 | Test and Quality Checks in run 41141787027, 16.8 min |
| Laksa | push-1f199145 | 1 | 1 | 0 | 0 | 13.5 | 0 | 0 | 13.5 | 13.6 | 13.6 | Test and Quality Checks in run 41113839695, 13.5 min |
| Laksa | push-725b5709 | 2 | 1 | 0 | 0 | 12.4 | 0 | 0 | 12.4 | 13.6 | 14.1 | Test and Quality Checks in run 40949844924, 12.4 min |

The local half, from the cut logs the release core writes (file birth to last write, UTC):

| project | release | cut log | cut start | cut end | cut wall min | local gates in the log | CI wait inside the cut |
|---|---|---|---|---|---:|---|---|
| Devbin | v0.1.16 | 20261029-1132.RELEASE | 11:32:20 | 11:44:01 | 11.7 | check all (syntax, lint, critic, format, toolchain), test all (bats, 8 lanes), doctor | none: the cut stops after the tag; publish is a separate run |
| Devbin | v0.1.17 | 20261029-1344.RELEASE | 13:44:44 | 13:58:48 | 14.1 | same three gates | none (publish separate; its candidate run went red, see below) |
| Devbin | v0.1.18 | 20261029-1701.RELEASE | 17:01:41 | 17:16:19 | 14.6 | same three gates (check all 17:01:48 to 17:02:56; test all to about 17:16) | none in the cut; the publish run 20261029-1717-30 waited 17:17:30 to 18:13:50 = 56.3 min on run 40919937412 |
| Gtools | v0.8.1 | 20261029-1711.RELEASE | 17:11:37 | 17:37:02 | 25.4 | check all; test all: 845 tests, 547 s test time, 585 s gate wall; app 123 tests | `ci` step waited for run 40920695516 (green 17:36:44) |
| Gtools | v0.8.2 | 20261029-1908.RELEASE | 19:08:00 | 19:32:59 | 25.0 | check all; test all: 845 tests, 502 s, 527 s gate wall; app 123 tests | waited for run 40939207690 (green 19:32:50) |
| Gtools | v0.8.3 | 20261030-2154.RELEASE | 21:54:47 | 22:18:37 | 23.8 | check all; test all: 868 tests, 470 s, 515 s gate wall; app 123 tests in 18.5 s | waited for run 41135649951 (green 22:18:29) |
| Utilz | 2.14.8 | 20261030-2059.RELEASE | 20:59:05 | 21:02:02 | 3.0 | check all only (clippy, format, autotests, targetdir, toolchain, critic); no `test all` in this log; then post-cut app sign, notarize, publish | none recorded; the errors file says "run in flight (or aborted before sealing)" |
| Utilz | 2.14.6, 2.14.7 | none in the clone | | | | | |
| Intent | v3.2.6 to v3.2.8 | none in the clone (no `tmp/release/`); `tmp/check/` holds one FORMAT verdict stamped 20261030-2031, written 20:32:39, which is the only local trace of the v3.2.8 cut's gates | | | | | |
| Conflab | v0.6.0 to v0.6.2 | none in the clone (cut in July and August; no `tmp/release/`) | | | | | |
| Laksa | n/a | no release; its `tmp/test/` holds no run from 29 or 30 October | | | | | |

## 2. Measured facts bearing on "the same work runs several times"

1. **Every tagged release in the record started the same workflow twice on the same sha, 2 to 10 seconds apart: once for the push to `main` and once for the tag push.** The concurrency group keys on workflow, event and ref, so neither run cancels the other. Utilz: 40879022805 + 40879031120 (2.14.6), 40935682929 + 40935690642 (2.14.7), 41127529723 + 41127538028 (2.14.8). Gtools: 40920687896 + 40920695516 (v0.8.1), 40939198152 + 40939207690 (v0.8.2), 41135646272 + 41135649951 (v0.8.3). Intent, two workflows each: 40093074921 + 40093074760 and 40093074970 + 40093074766 (v3.2.6); 40943952346 + 40943953013 and 40943952652 + 40943953015 (v3.2.7); 41125435240 + 41125436120 and 41125434812 + 41125436284 (v3.2.8). Conflab's pair is `conflab` on main plus `Release` on the tag, and `Release` skipped both its jobs every time (29109209862, 32824490103, 32830196383), so there the duplicate costs nothing.
2. **In each pair the Ubuntu legs are identical work done twice.** Utilz 2.14.8: Test on Ubuntu 9.4 + 9.4 min, Rust (ubuntu-latest) 7.2 + 6.2 min, Shell Script Analysis 2.2 + 1.7 min. Utilz 2.14.7: 6.0 + 6.3 and 6.0 + 6.0. Utilz 2.14.6: 6.6 + 6.7 and 8.4 + 7.1. Intent v3.2.8: Test on Ubuntu 7.4 + 7.5, rust (ubuntu-latest) 6.6 + 6.9. Intent v3.2.7: 5.3 + 6.3 and 6.5 + 6.0. Intent v3.2.6: 5.8 + 7.5 and 1.3 + 1.5 (both rust runs failed). Gtools: gates (linux) + rust (linux) 2.1 + 2.2 min (v0.8.3), 2.0 + 2.3 (v0.8.2), 2.2 + 1.9 (v0.8.1). The macOS legs are not doubled inside these pairs: they are conditioned on `ref_type == tag` or a dispatch, so only the tag run carries them.
3. **Where a candidate commit was tested before the cut, the macOS legs ran again on the release commit, which differs from the candidate only by version strings and a date.** Gtools v0.8.3: suite + app (macos) 14.5 min on 41c283a8 (dispatch 41127185022, created 20:56:41) and 13.7 min on 79c9233d (tag run 41135649951, created 22:04:47); `git show --stat 79c9233d` is 4 files, 4 lines. Utilz 2.14.8: dispatch 41120955230 on 878994e8 (20:08:57) ran Test on macOS 11.6, Rust (macos-latest) 6.5 and menuz app 2.5 min; the tag run 41127538028 on f2021ddc (20:59:32) ran them again: 10.8, 11.1 (after a 22.9 min cancelled first attempt, fact 6) and 1.9 min. Intent v3.2.8: the Ubuntu legs ran on the candidate bda94eb0 (41121428286, 41121428294) and twice more on b14e2745; the macOS legs ran once, on the tag.
4. **The local gates run the suite once more, on the release commit, between the commit and the tag; then the cut waits for CI to run it again on the same commit.** Gtools 0.8.3's cut log: release commit 79c9233d at 21:55:12, `test all` 868 tests in 470 s (515 s gate wall) plus the app's 123 tests, tag at 22:04:37, then its `ci` step held the cut until run 41135649951 went green at 22:18:29; the cut closed at 22:18:37. So the Elixir suite ran on CI (dispatch, 14.5 min macOS), locally in the gates (8.6 min), and on CI again on the tag (13.7 min macOS), in one release, plus the kovacs and gyges runs issue 0295 names, which no record on this machine times. Gtools 0.8.1 and 0.8.2 have the same shape (585 s and 527 s gate wall, then waits on 40920695516 and 40939207690). Devbin: each cut ran the bats suite locally (11.7, 14.1 and 14.6 min cut wall for v0.1.16, v0.1.17 and v0.1.18) and CI then ran the same suite on the snapshot: Test on Ubuntu 31.8 min, Test on macOS 55.3 min, Test in WSL 2 59.1 min (40919937412).
5. **Devbin v0.1.18: 56 minutes of waiting, then a full re-run on the identical sha that was cancelled by hand.** The publish pushed snapshot a9b8cd7c to `candidate/v0.1.18` at 17:17:30; run 40919937412 was created 17:17:42; its Test Summary passed at 18:13:13 (it does not wait for WSL, which finished at 18:16:52); the publish moved `main`, tagged, and closed at 18:13:50. The tag push created 40928750135 at 18:13:23, which started Test on Ubuntu, Test on macOS and Test in WSL 2 again on a9b8cd7c; it was cancelled at 18:21:31 after 7.8, 8.1 and 7.6 min, 29.4 machine-minutes (8.1 macOS) for nothing. The record names no actor; no other run shares its concurrency group, so the cancel was manual. Issue 0294 was filed locally at 18:22:03. End to end: last code commit 16:55:14 to public tag 18:13:13 is 78.0 min, of which the local cut was 14.6 and CI 55.5.
6. **Reruns re-spend macOS minutes.** Utilz 2.14.8's tag run 41127538028 is attempt 2. Attempt 1's Rust (macos-latest) ran 20:59:44 to 21:22:38 (22.9 min) and was cancelled with the attempt; attempt 2 (21:23:04) re-ran only that job, 21:23:10 to 21:34:17 (11.1 min, success). The leg cost 34.0 macOS minutes, the run's wall-clock became 34.9 min against 14.7 and 14.8 for 2.14.6 and 2.14.7, and `gh run view` shows only attempt 2's jobs (the 22.9 min was read from the attempt-1 jobs endpoint and added to the tables below).
7. **Queue wait is nil.** Every macOS job in the record (labels `macos-latest` and `xcode-27`) started 0.0 to 0.2 min after its run was created; ubuntu and windows jobs the same. The only gaps over a minute are Utilz's cancel-and-rerun (23.6 min from run creation to the attempt-2 job) and Laksa's 1.1 min while its superseded run 40949764888 was being cancelled.
8. **Devbin's CI is an order of magnitude dearer than the rest.** Each candidate run cost 47 to 51 ubuntu, 55 to 66 macOS and 59 to 67 windows minutes (40904076298, 40919937412): 818 to 830 billed-equivalent minutes per candidate, against 126 to 316 for a Utilz, Gtools or Intent tag release and 14 to 16 for Conflab. Its Ubuntu leg takes 31.8 to 41.7 min for a suite the cut log runs locally in about 13 min on 8 lanes.
9. **Wall-clock per release, over the release shas.** Conflab 7.2 to 7.7 min. Gtools 12.4 and 14.4 (v0.8.2, v0.8.1), 82.0 (v0.8.3, candidate dispatch to tag green). Utilz 14.8 and 14.8 (2.14.6, 2.14.7), 86.5 (2.14.8, candidate push to rerun green). Intent 16.4 (v3.2.7), 23.4 (v3.2.6, including a dispatched linux release), 43.8 (v3.2.8, candidate push to tag green). Devbin 63.8 (candidate run created to tag run cancelled) and 66.5 (v0.1.17's red candidate). Adding the local half: a Gtools release is 24 to 25 min of cut wall on top of the candidate's CI; a Devbin release is 14.6 min of cut plus 56.3 of publish. "An hour or more" is measured for Devbin (CI alone), Gtools v0.8.3 and Utilz 2.14.8 (candidate to release); a tag-only span in Utilz, Gtools, Intent or Conflab is 7 to 17 min of CI plus 9 to 15 of local gates.
10. **Baselines (last 10 push-to-main runs).** Ubuntu test legs: Utilz Test on Ubuntu median 8.7 min and Rust (ubuntu) 6.6; Intent Test on Ubuntu 6.3 and rust (ubuntu) 5.9; Gtools gates 1.1 and rust 1.1; Conflab Elixir 2.9 and Rust daemon 3.2; Laksa's single job 13.2 (failing in 5 of 10). macOS legs have no push baseline anywhere, by design (tag or dispatch only); their release-run durations are Utilz Test on macOS 10.8 to 14.6 and Rust (macos) 6.5 to 11.1, Intent Test on macOS 9.0 to 16.2 and rust (macos) 8.1 to 13.3, Gtools suite + app 12.2 to 14.5, Devbin 55.3 to 66.3. Devbin has no push-to-main baseline at all: its public repository holds 4 runs in total.
11. **Pushes that move only records still start full runs where the files sit outside the two ignored trees.** Gtools 41141599117 (80d35ead, 1.2 min) and 41113874651 (08586855, 2.7 min); Utilz 41140741047 (1434e764 wip.md, 8.2 min, red); Laksa 41141787027 (d299dda7 records, 16.8 min, red); Intent 41142294012 (aae13d74, 7.4 min); Conflab 41142812782 (66c11071, 3.2 min). These are in the baseline tables, not the release counts.

## 3. Data gaps, stated plainly

- Devbin's public repository holds exactly 4 workflow runs: 40904076298 (candidate/v0.1.17, red), 40919937412 (candidate/v0.1.18), 40928750135 and 40928750466 (tag v0.1.18). The workroom repository has no Actions. So v0.1.16 has no CI record anywhere; v0.1.17 has only its failed candidate; v0.1.18's local release commit f084e101 has no run (CI tests the snapshot a9b8cd7c, a parentless commit with the same timestamp). The candidate branches were deleted by the publish, so `gh api` finds them no more (HTTP 404); the runs remain.
- No local cut log exists in the clone for Intent (any release), Conflab (any release) or Utilz 2.14.6 and 2.14.7. For those the local half is the commit and tag times only.
- The kovacs and gyges runs issue 0295 names for Gtools 0.8.3 are not timed in any record readable here.
- Intent's and Conflab's tags are lightweight, so there is no tagger time; the tag push time is read from the runs it created.
- Job logs were not downloaded; every duration is from the jobs API timestamps. Only one run in the set has more than one attempt (Utilz 41127538028); the API returns the latest attempt's jobs, and attempt 1 was read through `attempts/1/jobs`.
- Laksa has no release tags; its workflow file `ci_cd.yml` declares one job, `Test and Quality Checks` on `ubuntu-26.04`, and no deploy job, so the three most recent pushes to `main` stand in for releases. Its runs are not one per commit: `paths-ignore` suppresses board-only pushes and the six commits of 22:44 to 23:00 on 30 October produced one run.
- All six repositories answered to the signed-in account; none was private to it.

## 4. Per project

### 4.1 Devbin

Workflows: `Devbin Tests` (push to `main` and `candidate/**`, tags `v[0-9]*` and `[0-9]*`, pull requests, dispatch; jobs Candidate verdict, Test on Ubuntu, Test on macOS (bash >= 5 floor) [macos-latest], Shell Script Analysis, Test in WSL 2 (Ubuntu 26.04) [windows-latest], Test Summary; macOS and WSL run on a tag, a dispatch or a candidate ref) and `Release` (tags `v*`, one ubuntu job that makes the release object). Concurrency group: workflow + event + ref, cancel-in-progress. The product is published as one snapshot commit per release to a public repository: the local tag's commit and the public commit differ.

Release record (local clone):

| release | tag type | tagged (UTC) | release commit | committed (UTC) | parent commit | parent committed (UTC) |
|---|---|---|---|---|---|---|
| v0.1.18 | annotated | 2026-10-29T17:16:18Z | f084e101 | 2026-10-29T17:01:45Z | f1173c13 | 2026-10-29T16:55:14Z |
| v0.1.17 | annotated | 2026-10-29T13:58:48Z | 420547e3 | 2026-10-29T13:44:48Z | fe9be3df | 2026-10-29T13:42:42Z |
| v0.1.16 | annotated | 2026-10-29T11:44:00Z | 6e193c60 | 2026-10-29T11:32:23Z | 25175386 | 2026-10-29T10:42:45Z |

Public repository refs (gh api): `main` = `v0.1.18` = a9b8cd7c (committed 2026-10-29T17:01:45Z, no parent, message "devbin 0.1.18"); no `v0.1.16` or `v0.1.17` ref exists there; `candidate/v0.1.17` and `candidate/v0.1.18` are gone.

The local publish logs (file birth to last write): 20261029-1540.PUBLISH 15:40:59 to 15:41:10, snapshot 2cde3ee6 of v0.1.17 pushed to candidate/v0.1.17, then FAILED reading CI ("workflow tests.yml not found on the default branch": the public repository had no main yet); 20261029-1541.PUBLISH 15:41:43 to 16:48:01 (66.3 min), candidate step FAILED on run 40904076298 (Test Summary: failure); 20261029-1717.PUBLISH 17:17:07 to 17:17:14, snapshot a9b8cd7c made, confirm FAILED (no terminal, no --yes); 20261029-1717-30.PUBLISH 17:17:30 to 18:13:50 (56.3 min), candidate done on run 40919937412, publish done, object done "within 20m", after FAILED (formula publish asks a person), ci skipped ("ci.tag is off").

#### Devbin v0.1.18: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40904076298 | push | candidate/v0.1.17 | 2cde3ee6 | Devbin Tests | 2026-10-29T15:41:14Z | 2026-10-29T16:47:42Z | 66.5 | failure | 5/5 | 47.1 | 66.3 | 60.2 | Test on macOS (bash >= 5 floor) 66.3 |
| 40919937412 | push | candidate/v0.1.18 | a9b8cd7c (tag commit) | Devbin Tests | 2026-10-29T17:17:42Z | 2026-10-29T18:16:53Z | 59.2 | success | 5/5 | 37.2 | 55.3 | 59.1 | Test in WSL 2 (Ubuntu 26.04) 59.1 |
| 40928750135 | push | v0.1.18 | a9b8cd7c (tag commit) | Devbin Tests | 2026-10-29T18:13:23Z | 2026-10-29T18:21:31Z | 8.1 | cancelled | 4/5 | 13.6 | 8.1 | 7.6 | Test on macOS (bash >= 5 floor) 8.1 |
| 40928750466 | push | v0.1.18 | a9b8cd7c (tag commit) | Release | 2026-10-29T18:13:23Z | 2026-10-29T18:13:35Z | 0.2 | success | 1/1 | 0.1 | 0 | 0 | Publish the GitHub Release 0.1 |

#### Devbin v0.1.18: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40904076298 | candidate/v0.1.17 | Test on Ubuntu | ubuntu | 2026-10-29T15:41:17Z | 2026-10-29T16:22:58Z | 41.7 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Shell Script Analysis | ubuntu | 2026-10-29T15:41:17Z | 2026-10-29T15:46:42Z | 5.4 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Test in WSL 2 (Ubuntu 26.04) | windows | 2026-10-29T15:41:19Z | 2026-10-29T16:41:28Z | 60.2 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Test on macOS (bash >= 5 floor) | macos | 2026-10-29T15:41:19Z | 2026-10-29T16:47:35Z | 66.3 | 0.1 | failure |
| 40904076298 | candidate/v0.1.17 | Test Summary | ubuntu | 2026-10-29T16:47:38Z | 2026-10-29T16:47:41Z | 0.1 | 66.4 | failure |
| 40919937412 | candidate/v0.1.18 | Test on macOS (bash >= 5 floor) | macos | 2026-10-29T17:17:48Z | 2026-10-29T18:13:06Z | 55.3 | 0.1 | success |
| 40919937412 | candidate/v0.1.18 | Test in WSL 2 (Ubuntu 26.04) | windows | 2026-10-29T17:17:46Z | 2026-10-29T18:16:52Z | 59.1 | 0.1 | success |
| 40919937412 | candidate/v0.1.18 | Shell Script Analysis | ubuntu | 2026-10-29T17:17:46Z | 2026-10-29T17:23:08Z | 5.4 | 0.1 | success |
| 40919937412 | candidate/v0.1.18 | Test on Ubuntu | ubuntu | 2026-10-29T17:17:46Z | 2026-10-29T17:49:31Z | 31.8 | 0.1 | success |
| 40919937412 | candidate/v0.1.18 | Test Summary | ubuntu | 2026-10-29T18:13:09Z | 2026-10-29T18:13:13Z | 0.1 | 55.5 | success |
| 40928750135 | v0.1.18 | Shell Script Analysis | ubuntu | 2026-10-29T18:13:27Z | 2026-10-29T18:19:19Z | 5.9 | 0.1 | success |
| 40928750135 | v0.1.18 | Test on Ubuntu | ubuntu | 2026-10-29T18:13:27Z | 2026-10-29T18:21:12Z | 7.8 | 0.1 | cancelled |
| 40928750135 | v0.1.18 | Test in WSL 2 (Ubuntu 26.04) | windows | 2026-10-29T18:13:27Z | 2026-10-29T18:21:05Z | 7.6 | 0.1 | cancelled |
| 40928750135 | v0.1.18 | Test on macOS (bash >= 5 floor) | macos | 2026-10-29T18:13:27Z | 2026-10-29T18:21:30Z | 8.1 | 0.1 | cancelled |
| 40928750135 | v0.1.18 | Test Summary | ubuntu | - | - | - | - | cancelled |
| 40928750466 | v0.1.18 | Publish the GitHub Release | ubuntu | 2026-10-29T18:13:26Z | 2026-10-29T18:13:34Z | 0.1 | 0.1 | success |

#### Devbin v0.1.18: derived

- Runs on the release shas (tag commit a9b8cd7c, candidate a9b8cd7c): 3 of the 4 runs in the window.
- Duplicate runs on the same sha: a9b8cd7c: 40919937412 (Devbin Tests, push candidate/v0.1.18) + 40928750135 (Devbin Tests, push v0.1.18) + 40928750466 (Release, push v0.1.18).
- CI machine-minutes on the release shas: ubuntu 50.9, macOS 63.4, windows 66.7; billed-equivalent (macOS x10, windows x2) 817.9. Over every run in the window: ubuntu 98.1, macOS 129.6, windows 126.9.
- Wall-clock, release shas: 2026-10-29T17:17:42Z to 2026-10-29T18:21:31Z = 63.8 min. Whole window (first run created to last run updated): 2026-10-29T15:41:14Z to 2026-10-29T18:21:31Z = 160.3 min.
- Critical path (longest single job on the release shas): Test in WSL 2 (Ubuntu 26.04) in run 40919937412, 59.1 min.
- macOS jobs on the release shas: Test on macOS (bash >= 5 floor) in 40919937412: queued 0.1 min, ran 55.3 min, success; Test on macOS (bash >= 5 floor) in 40928750135: queued 0.1 min, ran 8.1 min, cancelled.

#### Devbin v0.1.17: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40904076298 | push | candidate/v0.1.17 | 2cde3ee6 (tag commit) | Devbin Tests | 2026-10-29T15:41:14Z | 2026-10-29T16:47:42Z | 66.5 | failure | 5/5 | 47.1 | 66.3 | 60.2 | Test on macOS (bash >= 5 floor) 66.3 |

#### Devbin v0.1.17: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40904076298 | candidate/v0.1.17 | Test on Ubuntu | ubuntu | 2026-10-29T15:41:17Z | 2026-10-29T16:22:58Z | 41.7 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Shell Script Analysis | ubuntu | 2026-10-29T15:41:17Z | 2026-10-29T15:46:42Z | 5.4 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Test in WSL 2 (Ubuntu 26.04) | windows | 2026-10-29T15:41:19Z | 2026-10-29T16:41:28Z | 60.2 | 0.1 | success |
| 40904076298 | candidate/v0.1.17 | Test on macOS (bash >= 5 floor) | macos | 2026-10-29T15:41:19Z | 2026-10-29T16:47:35Z | 66.3 | 0.1 | failure |
| 40904076298 | candidate/v0.1.17 | Test Summary | ubuntu | 2026-10-29T16:47:38Z | 2026-10-29T16:47:41Z | 0.1 | 66.4 | failure |

#### Devbin v0.1.17: derived

- Runs on the release shas (tag commit 2cde3ee6, candidate 2cde3ee6): 1 of the 1 runs in the window.
- Duplicate runs on the same sha: none.
- CI machine-minutes on the release shas: ubuntu 47.1, macOS 66.3, windows 60.2; billed-equivalent (macOS x10, windows x2) 830.1. Over every run in the window: ubuntu 47.1, macOS 66.3, windows 60.2.
- Wall-clock, release shas: 2026-10-29T15:41:14Z to 2026-10-29T16:47:42Z = 66.5 min. Whole window (first run created to last run updated): 2026-10-29T15:41:14Z to 2026-10-29T16:47:42Z = 66.5 min.
- Critical path (longest single job on the release shas): Test on macOS (bash >= 5 floor) in run 40904076298, 66.3 min.
- macOS jobs on the release shas: Test on macOS (bash >= 5 floor) in 40904076298: queued 0.1 min, ran 66.3 min, failure.

#### Devbin v0.1.16: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|

#### Devbin v0.1.16: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|

#### Devbin v0.1.16: derived

- Runs on the release shas (tag commit -, candidate -): 0 of the 0 runs in the window.
- Duplicate runs on the same sha: none.
- CI machine-minutes on the release shas: ubuntu 0, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 0. Over every run in the window: ubuntu 0, macOS 0, windows 0.
- Wall-clock, release shas: - to - = - min. Whole window (first run created to last run updated): - to - = - min.
- Critical path (longest single job on the release shas): none.
- macOS jobs on the release shas: none ran.

Note on v0.1.18's window: run 40904076298 (candidate/v0.1.17) falls inside it by time; it belongs to v0.1.17 and is excluded from v0.1.18's release-sha figures above.

#### Devbin baseline (last 10 push-to-main runs)

No push-to-main runs exist in the record (see the project notes).

The public `main` only ever moves by the publish's fast-forward, which creates no run of its own (the record shows runs on the candidate ref and the tag ref only). The closest thing to a baseline is the two candidate runs: Test on Ubuntu 41.7 and 31.8 min, Shell Script Analysis 5.4 and 5.4, Test on macOS 66.3 and 55.3, Test in WSL 2 60.2 and 59.1.

#### Devbin v0.1.18 timeline (2026-10-29, UTC)

| event | time | delta from previous | what ran |
|---|---|---:|---|
| 0292 fix lands (bbb77cc5) | 16:07:38 | | nothing: the workroom has no CI |
| issue 0292 closed on a 13-file local run, 490 of 490 ok (ea127818) | 16:25:01 | 17.4 min | local bats, partial |
| 0293 fix, last code commit before the cut (f1173c13) | 16:55:14 | 30.2 min | nothing |
| cut starts (RELEASE log birth) | 17:01:41 | 6.5 min | resolve, pre-flight, stamp |
| release commit f084e101 "release: v0.1.18" | 17:01:45 | 0.1 min | commit of 4 files |
| gate `check all` | 17:01:48 to 17:02:56 | 1.1 min | syntax, lint, critic, format, toolchain (local) |
| gate `test all`, then `doctor`, then the go-ahead prompt | 17:02:56 to about 17:16 | about 13.3 min | the whole bats suite locally, 8 lanes then the serial lane |
| annotated tag v0.1.18 at f084e101; pushed to the local remote; cut log closes | 17:16:18 / 17:16:19 | | nothing public yet |
| publish attempt 1 | 17:17:07 to 17:17:14 | 0.8 min | snapshot a9b8cd7c made; confirm refused (no terminal) |
| publish attempt 2 starts, pushes candidate/v0.1.18 | 17:17:30 | 0.3 min | |
| run 40919937412 created (candidate/v0.1.18, a9b8cd7c) | 17:17:42 | 0.2 min | Shell Script Analysis 17:17:46 to 17:23:08 (5.4); Test on Ubuntu 17:17:46 to 17:49:31 (31.8); Test on macOS 17:17:48 to 18:13:06 (55.3); Test in WSL 2 17:17:46 to 18:16:52 (59.1) |
| Test Summary of 40919937412 passes | 18:13:13 | 55.5 min | summary job 0.1 min; it does not wait for WSL |
| publish fast-forwards main, tags v0.1.18 (lightweight) at a9b8cd7c, deletes the candidate ref | about 18:13:15 | | |
| tag push creates 40928750135 (Devbin Tests) and 40928750466 (Release) | 18:13:23 | 0.2 min | Release: Publish the GitHub Release 18:13:26 to 18:13:34 (0.1). Devbin Tests: Ubuntu, macOS, WSL and shellcheck all start 18:13:27 on the same a9b8cd7c |
| publish log closes: object done, after FAILED (formula publish asks a person), ci skipped | 18:13:50 | 0.5 min | publish wall 56.3 min |
| WSL leg of the candidate run finishes | 18:16:52 | 3.0 min | after the publish already read green |
| 40928750135 cancelled | 18:21:31 | 4.7 min | Ubuntu 7.8, macOS 8.1, WSL 7.6 min spent, shellcheck 5.9 done; no actor in the record |
| issue 0294 filed locally (7a4280f4) | 18:22:03 | 0.5 min | |

End to end: 16:55:14 to 18:13:13 = 78.0 min from the last code commit to the public tag; local cut 14.6 min; CI critical path Test on macOS 55.3 min (Test Summary needs it), WSL 59.1 min off the critical path.

### 4.2 Utilz

Workflow: `Utilz Tests` (push to `main` and tags `v[0-9]*` / `[0-9]*`, pull requests, dispatch; jobs Test on Ubuntu, Test on macOS [macos-latest, tag or dispatch only], Shell Script Analysis, Rust (ubuntu-latest) and Rust (macos-latest) [macOS leg added to the matrix on a tag or dispatch], Rust Lint (clippy), menuz app (macOS) [xcode-27, tag or dispatch only], Test Summary). `PR Checks` runs on pull requests only and does not appear. Tags are bare versions. No publish repository, so a cut tags the release commit and pushes it; `main` and the tag arrive in one push and start two runs.

Release record (local clone):

| release | tag type | tagged (UTC) | release commit | committed (UTC) | parent commit | parent committed (UTC) |
|---|---|---|---|---|---|---|
| 2.14.8 | annotated | 2026-10-30T20:59:22Z | f2021ddc | 2026-10-30T20:59:11Z | 878994e8 | 2026-10-30T20:05:54Z |
| 2.14.7 | annotated | 2026-10-29T18:57:39Z | 48bad89a | 2026-10-29T18:57:30Z | 2d02dc3d | 2026-10-29T18:44:25Z |
| 2.14.6 | annotated | 2026-10-29T13:06:58Z | 4790222a | 2026-10-29T13:06:44Z | 270ab952 | 2026-10-29T07:25:17Z |

#### Utilz 2.14.8: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 41115734657 | push | main | 05538ca3 | Utilz Tests | 2026-10-30T19:30:00Z | 2026-10-30T19:39:45Z | 9.8 | failure | 5/7 | 18.8 | 0 | 0 | Test on Ubuntu 9.6 |
| 41120827575 | push | main | 878994e8 (candidate) | Utilz Tests | 2026-10-30T20:07:54Z | 2026-10-30T20:20:41Z | 12.8 | success | 5/7 | 18.1 | 0 | 0 | Test on Ubuntu 8.7 |
| 41120955230 | workflow_dispatch | main | 878994e8 (candidate) | Utilz Tests | 2026-10-30T20:08:57Z | 2026-10-30T20:23:09Z | 14.2 | success | 8/8 | 16.4 | 20.5 | 0 | Test on macOS 11.6 |
| 41127529723 | push | main | f2021ddc (tag commit) | Utilz Tests | 2026-10-30T20:59:28Z | 2026-10-30T21:09:03Z | 9.6 | success | 5/7 | 19.2 | 0 | 0 | Test on Ubuntu 9.4 |
| 41127538028 | push | 2.14.8 | f2021ddc (tag commit) | Utilz Tests | 2026-10-30T20:59:32Z | 2026-10-30T21:34:23Z | 34.9 | success (attempt 2) | 9/9 | 17.7 | 46.7 | 0 | Rust (macos-latest) [attempt 1, cancelled before the rerun] 22.9 |
| 41140741047 | push | main | 1434e764 | Utilz Tests | 2026-10-30T22:50:29Z | 2026-10-30T22:58:42Z | 8.2 | failure | 5/7 | 16.2 | 0 | 0 | Test on Ubuntu 8 |

#### Utilz 2.14.8: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 41115734657 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-30T19:30:05Z | 2026-10-30T19:36:37Z | 6.5 | 0.1 | success |
| 41115734657 | main | Rust Lint (clippy) | ubuntu | 2026-10-30T19:30:04Z | 2026-10-30T19:30:27Z | 0.4 | 0.1 | success |
| 41115734657 | main | Shell Script Analysis | ubuntu | 2026-10-30T19:30:04Z | 2026-10-30T19:32:20Z | 2.3 | 0.1 | success |
| 41115734657 | main | Test on Ubuntu | ubuntu | 2026-10-30T19:30:04Z | 2026-10-30T19:39:40Z | 9.6 | 0.1 | failure |
| 41115734657 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41115734657 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 41115734657 | main | Test Summary | ubuntu | 2026-10-30T19:39:42Z | 2026-10-30T19:39:45Z | 0.1 | 9.7 | failure |
| 41120827575 | main | Shell Script Analysis | ubuntu | 2026-10-30T20:07:58Z | 2026-10-30T20:10:13Z | 2.3 | 0.1 | success |
| 41120827575 | main | Rust Lint (clippy) | ubuntu | 2026-10-30T20:07:58Z | 2026-10-30T20:08:21Z | 0.4 | 0.1 | success |
| 41120827575 | main | Test on Ubuntu | ubuntu | 2026-10-30T20:07:58Z | 2026-10-30T20:16:38Z | 8.7 | 0.1 | success |
| 41120827575 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-30T20:07:58Z | 2026-10-30T20:14:43Z | 6.8 | 0.1 | success |
| 41120827575 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41120827575 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 41120827575 | main | Test Summary | ubuntu | 2026-10-30T20:16:40Z | 2026-10-30T20:16:44Z | 0.1 | 8.8 | success |
| 41120955230 | main | Shell Script Analysis | ubuntu | 2026-10-30T20:09:02Z | 2026-10-30T20:11:20Z | 2.3 | 0.1 | success |
| 41120955230 | main | Test on Ubuntu | ubuntu | 2026-10-30T20:09:01Z | 2026-10-30T20:15:51Z | 6.8 | 0.1 | success |
| 41120955230 | main | menuz app (macOS) | macos | 2026-10-30T20:09:02Z | 2026-10-30T20:11:29Z | 2.5 | 0.1 | success |
| 41120955230 | main | Test on macOS | macos | 2026-10-30T20:09:04Z | 2026-10-30T20:20:40Z | 11.6 | 0.1 | success |
| 41120955230 | main | Rust (macos-latest) | macos | 2026-10-30T20:09:02Z | 2026-10-30T20:15:30Z | 6.5 | 0.1 | success |
| 41120955230 | main | Rust Lint (clippy) | ubuntu | 2026-10-30T20:09:02Z | 2026-10-30T20:09:21Z | 0.3 | 0.1 | success |
| 41120955230 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-30T20:09:02Z | 2026-10-30T20:15:57Z | 6.9 | 0.1 | success |
| 41120955230 | main | Test Summary | ubuntu | 2026-10-30T20:20:44Z | 2026-10-30T20:20:46Z | 0 | 11.8 | success |
| 41127529723 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-30T20:59:31Z | 2026-10-30T21:06:41Z | 7.2 | 0.1 | success |
| 41127529723 | main | Shell Script Analysis | ubuntu | 2026-10-30T20:59:31Z | 2026-10-30T21:01:45Z | 2.2 | 0.1 | success |
| 41127529723 | main | Rust Lint (clippy) | ubuntu | 2026-10-30T20:59:32Z | 2026-10-30T20:59:53Z | 0.4 | 0.1 | success |
| 41127529723 | main | Test on Ubuntu | ubuntu | 2026-10-30T20:59:32Z | 2026-10-30T21:08:56Z | 9.4 | 0.1 | success |
| 41127529723 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41127529723 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 41127529723 | main | Test Summary | ubuntu | 2026-10-30T21:08:59Z | 2026-10-30T21:09:03Z | 0.1 | 9.5 | success |
| 41127538028 | 2.14.8 | Rust (macos-latest) | macos | 2026-10-30T21:23:10Z | 2026-10-30T21:34:17Z | 11.1 | 23.6 | success |
| 41127538028 | 2.14.8 | Test on macOS | macos | 2026-10-30T20:59:37Z | 2026-10-30T21:10:24Z | 10.8 | 0.1 | success |
| 41127538028 | 2.14.8 | Rust Lint (clippy) | ubuntu | 2026-10-30T20:59:36Z | 2026-10-30T20:59:59Z | 0.4 | 0.1 | success |
| 41127538028 | 2.14.8 | Test on Ubuntu | ubuntu | 2026-10-30T20:59:35Z | 2026-10-30T21:09:01Z | 9.4 | 0.1 | success |
| 41127538028 | 2.14.8 | menuz app (macOS) | macos | 2026-10-30T20:59:36Z | 2026-10-30T21:01:30Z | 1.9 | 0.1 | success |
| 41127538028 | 2.14.8 | Shell Script Analysis | ubuntu | 2026-10-30T20:59:35Z | 2026-10-30T21:01:14Z | 1.7 | 0.1 | success |
| 41127538028 | 2.14.8 | Rust (ubuntu-latest) | ubuntu | 2026-10-30T20:59:36Z | 2026-10-30T21:05:46Z | 6.2 | 0.1 | success |
| 41127538028 | 2.14.8 | Test Summary | ubuntu | 2026-10-30T21:34:20Z | 2026-10-30T21:34:22Z | 0 | 34.8 | success |
| 41127538028 | 2.14.8 | Rust (macos-latest) [attempt 1, cancelled before the rerun] | macos | 2026-10-30T20:59:44Z | 2026-10-30T21:22:38Z | 22.9 | 0.2 | cancelled |
| 41140741047 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-30T22:50:32Z | 2026-10-30T22:56:04Z | 5.5 | 0.1 | failure |
| 41140741047 | main | Rust Lint (clippy) | ubuntu | 2026-10-30T22:50:32Z | 2026-10-30T22:50:52Z | 0.3 | 0.1 | success |
| 41140741047 | main | Test on Ubuntu | ubuntu | 2026-10-30T22:50:33Z | 2026-10-30T22:58:35Z | 8 | 0.1 | success |
| 41140741047 | main | Shell Script Analysis | ubuntu | 2026-10-30T22:50:33Z | 2026-10-30T22:52:50Z | 2.3 | 0.1 | success |
| 41140741047 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 41140741047 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41140741047 | main | Test Summary | ubuntu | 2026-10-30T22:58:38Z | 2026-10-30T22:58:42Z | 0.1 | 8.2 | failure |

#### Utilz 2.14.8: derived

- Runs on the release shas (tag commit f2021ddc, candidate 878994e8): 4 of the 6 runs in the window.
- Duplicate runs on the same sha: 878994e8: 41120827575 (Utilz Tests, push main) + 41120955230 (Utilz Tests, workflow_dispatch main); f2021ddc: 41127529723 (Utilz Tests, push main) + 41127538028 (Utilz Tests, push 2.14.8).
- CI machine-minutes on the release shas: ubuntu 71.4, macOS 67.2, windows 0; billed-equivalent (macOS x10, windows x2) 743.6. Over every run in the window: ubuntu 106.5, macOS 67.2, windows 0.
- Wall-clock, release shas: 2026-10-30T20:07:54Z to 2026-10-30T21:34:23Z = 86.5 min. Whole window (first run created to last run updated): 2026-10-30T19:30:00Z to 2026-10-30T22:58:42Z = 208.7 min.
- Critical path (longest single job on the release shas): Rust (macos-latest) [attempt 1, cancelled before the rerun] in run 41127538028, 22.9 min.
- macOS jobs on the release shas: menuz app (macOS) in 41120955230: queued 0.1 min, ran 2.5 min, success; Test on macOS in 41120955230: queued 0.1 min, ran 11.6 min, success; Rust (macos-latest) in 41120955230: queued 0.1 min, ran 6.5 min, success; Rust (macos-latest) in 41127538028: queued 23.6 min, ran 11.1 min, success; Test on macOS in 41127538028: queued 0.1 min, ran 10.8 min, success; menuz app (macOS) in 41127538028: queued 0.1 min, ran 1.9 min, success; Rust (macos-latest) [attempt 1, cancelled before the rerun] in 41127538028: queued 0.2 min, ran 22.9 min, cancelled.

Attempt detail for 41127538028 (gh api `attempts/1` and `attempts/2`): attempt 1 created 20:59:32, cancelled 21:22:40 with Rust (macos-latest) at 22.9 min and every other job already green; attempt 2 started 21:23:04, re-ran Rust (macos-latest) alone (21:23:10 to 21:34:17) and Test Summary, success 21:34:23. The "queue 23.6 min" against the attempt-2 job above is that cancel-and-rerun gap, not a runner queue. The row "[attempt 1, cancelled before the rerun]" was added from the attempt-1 jobs endpoint so the macOS minutes are complete.

The Utilz 2.14.8 cut log (20261030-2059.RELEASE, 20:59:05 to 21:02:02) shows `check all` as its only gate, no `test all`, then the post-cut app sign, notarize (Apple accepted) and publish of Menuz.app.zip onto the release object; its errors file reads "run in flight (or aborted before sealing)".

#### Utilz 2.14.7: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40935682929 | push | main | 48bad89a (tag commit) | Utilz Tests | 2026-10-29T18:57:47Z | 2026-10-29T19:03:59Z | 6.2 | success | 5/7 | 14.1 | 0 | 0 | Rust (ubuntu-latest) 6 |
| 40935690642 | push | 2.14.7 | 48bad89a (tag commit) | Utilz Tests | 2026-10-29T18:57:50Z | 2026-10-29T19:12:36Z | 14.8 | success | 8/8 | 14.9 | 28.7 | 0 | Test on macOS 14.6 |
| 40945413129 | push | main | 5f5ee378 | Utilz Tests | 2026-10-29T20:02:15Z | 2026-10-29T20:11:02Z | 8.8 | success | 5/7 | 17.2 | 0 | 0 | Test on Ubuntu 8.6 |

#### Utilz 2.14.7: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40935682929 | main | Test on Ubuntu | ubuntu | 2026-10-29T18:57:50Z | 2026-10-29T19:03:50Z | 6 | 0.1 | success |
| 40935682929 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-29T18:57:51Z | 2026-10-29T19:03:52Z | 6 | 0.1 | success |
| 40935682929 | main | Shell Script Analysis | ubuntu | 2026-10-29T18:57:51Z | 2026-10-29T18:59:26Z | 1.6 | 0.1 | success |
| 40935682929 | main | Rust Lint (clippy) | ubuntu | 2026-10-29T18:57:51Z | 2026-10-29T18:58:15Z | 0.4 | 0.1 | success |
| 40935682929 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 40935682929 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40935682929 | main | Test Summary | ubuntu | 2026-10-29T19:03:55Z | 2026-10-29T19:03:58Z | 0.1 | 6.1 | success |
| 40935690642 | 2.14.7 | Shell Script Analysis | ubuntu | 2026-10-29T18:57:54Z | 2026-10-29T19:00:14Z | 2.3 | 0.1 | success |
| 40935690642 | 2.14.7 | Rust (macos-latest) | macos | 2026-10-29T18:57:55Z | 2026-10-29T19:08:53Z | 11 | 0.1 | success |
| 40935690642 | 2.14.7 | Test on Ubuntu | ubuntu | 2026-10-29T18:57:54Z | 2026-10-29T19:04:09Z | 6.3 | 0.1 | success |
| 40935690642 | 2.14.7 | Test on macOS | macos | 2026-10-29T18:57:55Z | 2026-10-29T19:12:29Z | 14.6 | 0.1 | success |
| 40935690642 | 2.14.7 | Rust (ubuntu-latest) | ubuntu | 2026-10-29T18:57:54Z | 2026-10-29T19:03:51Z | 6 | 0.1 | success |
| 40935690642 | 2.14.7 | Rust Lint (clippy) | ubuntu | 2026-10-29T18:57:54Z | 2026-10-29T18:58:10Z | 0.3 | 0.1 | success |
| 40935690642 | 2.14.7 | menuz app (macOS) | macos | 2026-10-29T18:58:01Z | 2026-10-29T19:01:13Z | 3.2 | 0.2 | success |
| 40935690642 | 2.14.7 | Test Summary | ubuntu | 2026-10-29T19:12:33Z | 2026-10-29T19:12:36Z | 0.1 | 14.7 | success |
| 40945413129 | main | Test on Ubuntu | ubuntu | 2026-10-29T20:02:18Z | 2026-10-29T20:10:55Z | 8.6 | 0.1 | success |
| 40945413129 | main | Rust Lint (clippy) | ubuntu | 2026-10-29T20:02:19Z | 2026-10-29T20:02:50Z | 0.5 | 0.1 | success |
| 40945413129 | main | Shell Script Analysis | ubuntu | 2026-10-29T20:02:19Z | 2026-10-29T20:04:36Z | 2.3 | 0.1 | success |
| 40945413129 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-29T20:02:19Z | 2026-10-29T20:08:03Z | 5.7 | 0.1 | success |
| 40945413129 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40945413129 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 40945413129 | main | Test Summary | ubuntu | 2026-10-29T20:10:58Z | 2026-10-29T20:11:01Z | 0.1 | 8.7 | success |

#### Utilz 2.14.7: derived

- Runs on the release shas (tag commit 48bad89a, candidate 2d02dc3d): 2 of the 3 runs in the window.
- Duplicate runs on the same sha: 48bad89a: 40935682929 (Utilz Tests, push main) + 40935690642 (Utilz Tests, push 2.14.7).
- CI machine-minutes on the release shas: ubuntu 28.9, macOS 28.7, windows 0; billed-equivalent (macOS x10, windows x2) 316.2. Over every run in the window: ubuntu 46.1, macOS 28.7, windows 0.
- Wall-clock, release shas: 2026-10-29T18:57:47Z to 2026-10-29T19:12:36Z = 14.8 min. Whole window (first run created to last run updated): 2026-10-29T18:57:47Z to 2026-10-29T20:11:02Z = 73.3 min.
- Critical path (longest single job on the release shas): Test on macOS in run 40935690642, 14.6 min.
- macOS jobs on the release shas: Rust (macos-latest) in 40935690642: queued 0.1 min, ran 11 min, success; Test on macOS in 40935690642: queued 0.1 min, ran 14.6 min, success; menuz app (macOS) in 40935690642: queued 0.2 min, ran 3.2 min, success.

#### Utilz 2.14.6: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40879022805 | push | main | 4790222a (tag commit) | Utilz Tests | 2026-10-29T13:07:07Z | 2026-10-29T13:15:44Z | 8.6 | success | 5/7 | 17 | 0 | 0 | Rust (ubuntu-latest) 8.4 |
| 40879031120 | push | 2.14.6 | 4790222a (tag commit) | Utilz Tests | 2026-10-29T13:07:10Z | 2026-10-29T13:21:53Z | 14.7 | success | 8/8 | 16 | 27.3 | 0 | Test on macOS 14.5 |
| 40885686023 | push | main | 09588b6f | Utilz Tests | 2026-10-29T13:50:39Z | 2026-10-29T14:00:26Z | 9.8 | success | 5/7 | 19.4 | 0 | 0 | Test on Ubuntu 9.6 |

#### Utilz 2.14.6: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40879022805 | main | Shell Script Analysis | ubuntu | 2026-10-29T13:07:11Z | 2026-10-29T13:08:47Z | 1.6 | 0.1 | success |
| 40879022805 | main | Test on Ubuntu | ubuntu | 2026-10-29T13:07:11Z | 2026-10-29T13:13:47Z | 6.6 | 0.1 | success |
| 40879022805 | main | Rust Lint (clippy) | ubuntu | 2026-10-29T13:07:11Z | 2026-10-29T13:07:27Z | 0.3 | 0.1 | success |
| 40879022805 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-29T13:07:11Z | 2026-10-29T13:15:37Z | 8.4 | 0.1 | success |
| 40879022805 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 40879022805 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40879022805 | main | Test Summary | ubuntu | 2026-10-29T13:15:40Z | 2026-10-29T13:15:43Z | 0.1 | 8.6 | success |
| 40879031120 | 2.14.6 | Test on Ubuntu | ubuntu | 2026-10-29T13:07:14Z | 2026-10-29T13:13:55Z | 6.7 | 0.1 | success |
| 40879031120 | 2.14.6 | Rust (macos-latest) | macos | 2026-10-29T13:07:20Z | 2026-10-29T13:18:05Z | 10.8 | 0.2 | success |
| 40879031120 | 2.14.6 | Test on macOS | macos | 2026-10-29T13:07:15Z | 2026-10-29T13:21:46Z | 14.5 | 0.1 | success |
| 40879031120 | 2.14.6 | Rust (ubuntu-latest) | ubuntu | 2026-10-29T13:07:15Z | 2026-10-29T13:14:22Z | 7.1 | 0.1 | success |
| 40879031120 | 2.14.6 | menuz app (macOS) | macos | 2026-10-29T13:07:14Z | 2026-10-29T13:09:14Z | 2 | 0.1 | success |
| 40879031120 | 2.14.6 | Shell Script Analysis | ubuntu | 2026-10-29T13:07:14Z | 2026-10-29T13:09:08Z | 1.9 | 0.1 | success |
| 40879031120 | 2.14.6 | Rust Lint (clippy) | ubuntu | 2026-10-29T13:07:14Z | 2026-10-29T13:07:30Z | 0.3 | 0.1 | success |
| 40879031120 | 2.14.6 | Test Summary | ubuntu | 2026-10-29T13:21:49Z | 2026-10-29T13:21:52Z | 0.1 | 14.7 | success |
| 40885686023 | main | Rust Lint (clippy) | ubuntu | 2026-10-29T13:50:43Z | 2026-10-29T13:51:16Z | 0.6 | 0.1 | success |
| 40885686023 | main | Test on Ubuntu | ubuntu | 2026-10-29T13:50:43Z | 2026-10-29T14:00:20Z | 9.6 | 0.1 | success |
| 40885686023 | main | Shell Script Analysis | ubuntu | 2026-10-29T13:50:43Z | 2026-10-29T13:53:03Z | 2.3 | 0.1 | success |
| 40885686023 | main | Rust (ubuntu-latest) | ubuntu | 2026-10-29T13:50:43Z | 2026-10-29T13:57:35Z | 6.9 | 0.1 | success |
| 40885686023 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40885686023 | main | menuz app (macOS) | macos | - | - | - | - | skipped |
| 40885686023 | main | Test Summary | ubuntu | 2026-10-29T14:00:23Z | 2026-10-29T14:00:26Z | 0.1 | 9.7 | success |

#### Utilz 2.14.6: derived

- Runs on the release shas (tag commit 4790222a, candidate 270ab952): 2 of the 3 runs in the window.
- Duplicate runs on the same sha: 4790222a: 40879022805 (Utilz Tests, push main) + 40879031120 (Utilz Tests, push 2.14.6).
- CI machine-minutes on the release shas: ubuntu 33, macOS 27.3, windows 0; billed-equivalent (macOS x10, windows x2) 305.6. Over every run in the window: ubuntu 52.4, macOS 27.3, windows 0.
- Wall-clock, release shas: 2026-10-29T13:07:07Z to 2026-10-29T13:21:53Z = 14.8 min. Whole window (first run created to last run updated): 2026-10-29T13:07:07Z to 2026-10-29T14:00:26Z = 53.3 min.
- Critical path (longest single job on the release shas): Test on macOS in run 40879031120, 14.5 min.
- macOS jobs on the release shas: Rust (macos-latest) in 40879031120: queued 0.2 min, ran 10.8 min, success; Test on macOS in 40879031120: queued 0.1 min, ran 14.5 min, success; menuz app (macOS) in 40879031120: queued 0.1 min, ran 2 min, success.

#### Utilz baseline (last 10 push-to-main runs)

| run | sha | workflow | created (UTC) | wall min | conclusion | Rust (ubuntu-latest) min | Rust Lint (clippy) min | Shell Script Analysis min | Test Summary min | Test on Ubuntu min |
|---|---|---|---|---:|---|---:|---:|---:|---:|---:|
| 40691478978 | 4c1fa5f1 | Utilz Tests | 2026-10-28T12:52:46Z | 9 | success | 5.2 | 0.6 | 1.9 | 0.1 | 8.8 |
| 40879022805 | 4790222a | Utilz Tests | 2026-10-29T13:07:07Z | 8.6 | success | 8.4 | 0.3 | 1.6 | 0.1 | 6.6 |
| 40885686023 | 09588b6f | Utilz Tests | 2026-10-29T13:50:39Z | 9.8 | success | 6.9 | 0.6 | 2.3 | 0.1 | 9.6 |
| 40899684858 | d58befd5 | Utilz Tests | 2026-10-29T15:15:21Z | 9.3 | success | 7.3 | 0.4 | 2.1 | 0.1 | 9.2 |
| 40935682929 | 48bad89a | Utilz Tests | 2026-10-29T18:57:47Z | 6.2 | success | 6 | 0.4 | 1.6 | 0.1 | 6 |
| 40945413129 | 5f5ee378 | Utilz Tests | 2026-10-29T20:02:15Z | 8.8 | success | 5.7 | 0.5 | 2.3 | 0.1 | 8.6 |
| 41115734657 | 05538ca3 | Utilz Tests | 2026-10-30T19:30:00Z | 9.8 | failure | 6.5 | 0.4 | 2.3 | 0.1 | 9.6 |
| 41120827575 | 878994e8 | Utilz Tests | 2026-10-30T20:07:54Z | 12.8 | success | 6.8 | 0.4 | 2.3 | 0.1 | 8.7 |
| 41127529723 | f2021ddc | Utilz Tests | 2026-10-30T20:59:28Z | 9.6 | success | 7.2 | 0.4 | 2.2 | 0.1 | 9.4 |
| 41140741047 | 1434e764 | Utilz Tests | 2026-10-30T22:50:29Z | 8.2 | failure | 5.5 | 0.3 | 2.3 | 0.1 | 8 |

Per leg (n / min / median / max, minutes): Rust (ubuntu-latest) [ubuntu] 10 / 5.2 / 6.6 / 8.4; Rust Lint (clippy) [ubuntu] 10 / 0.3 / 0.4 / 0.6; Shell Script Analysis [ubuntu] 10 / 1.6 / 2.2 / 2.3; Test Summary [ubuntu] 10 / 0.1 / 0.1 / 0.1; Test on Ubuntu [ubuntu] 10 / 6 / 8.7 / 9.6. Run wall-clock min / median / max: 6.2 / 9.1 / 12.8 min over 10 runs.

### 4.3 Gtools

Workflow: `CI` (push to `main` and tags, pull requests, dispatch; jobs gates (linux) [ubuntu, 15 min cap], rust (linux) [ubuntu, 20 min cap], suite + app (macos) [xcode-27, 45 min cap, tag or dispatch only]). Issue 0295 in Devbin was measured on v0.8.3: candidate 41c283a8 (dispatch 41127185022, kovacs, gyges), release commit 79c9233d (local gates, then tag run 41135649951 and the main run 41135646272 two seconds apart).

Release record (local clone):

| release | tag type | tagged (UTC) | release commit | committed (UTC) | parent commit | parent committed (UTC) |
|---|---|---|---|---|---|---|
| v0.8.3 | annotated | 2026-10-30T22:04:37Z | 79c9233d | 2026-10-30T21:55:12Z | b4232187 | 2026-10-30T21:43:07Z |
| v0.8.2 | annotated | 2026-10-29T19:20:21Z | 72d289f9 | 2026-10-29T19:08:25Z | a11d3c30 | 2026-10-29T18:09:28Z |
| v0.8.1 | annotated | 2026-10-29T17:22:15Z | b56036e9 | 2026-10-29T17:10:40Z | d3c3e698 | 2026-10-29T17:03:03Z |

#### Gtools v0.8.3: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 41113874651 | push | main | 08586855 | CI | 2026-10-30T19:16:21Z | 2026-10-30T19:19:02Z | 2.7 | success | 2/3 | 3.6 | 0 | 0 | gates (linux) 2.3 |
| 41127163812 | push | main | 41c283a8 (candidate) | CI | 2026-10-30T20:56:31Z | 2026-10-30T20:57:49Z | 1.3 | success | 2/3 | 2.3 | 0 | 0 | rust (linux) 1.2 |
| 41127185022 | workflow_dispatch | main | 41c283a8 (candidate) | CI | 2026-10-30T20:56:41Z | 2026-10-30T21:11:16Z | 14.6 | success | 3/3 | 2.3 | 14.5 | 0 | suite + app (macos) 14.5 |
| 41135646272 | push | main | 79c9233d (tag commit) | CI | 2026-10-30T22:04:45Z | 2026-10-30T22:05:54Z | 1.2 | success | 2/3 | 2.1 | 0 | 0 | rust (linux) 1.1 |
| 41135649951 | push | v0.8.3 | 79c9233d (tag commit) | CI | 2026-10-30T22:04:47Z | 2026-10-30T22:18:29Z | 13.7 | success | 3/3 | 2.2 | 13.7 | 0 | suite + app (macos) 13.7 |
| 41141599117 | push | main | 80d35ead | CI | 2026-10-30T22:58:56Z | 2026-10-30T23:00:06Z | 1.2 | success | 2/3 | 2.2 | 0 | 0 | gates (linux) 1.1 |

#### Gtools v0.8.3: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 41113874651 | main | gates (linux) | ubuntu | 2026-10-30T19:16:24Z | 2026-10-30T19:18:39Z | 2.3 | 0.1 | success |
| 41113874651 | main | rust (linux) | ubuntu | 2026-10-30T19:16:24Z | 2026-10-30T19:17:43Z | 1.3 | 0.1 | success |
| 41113874651 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 41127163812 | main | gates (linux) | ubuntu | 2026-10-30T20:56:34Z | 2026-10-30T20:57:39Z | 1.1 | 0.1 | success |
| 41127163812 | main | rust (linux) | ubuntu | 2026-10-30T20:56:34Z | 2026-10-30T20:57:48Z | 1.2 | 0.1 | success |
| 41127163812 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 41127185022 | main | rust (linux) | ubuntu | 2026-10-30T20:56:45Z | 2026-10-30T20:57:56Z | 1.2 | 0.1 | success |
| 41127185022 | main | suite + app (macos) | macos | 2026-10-30T20:56:45Z | 2026-10-30T21:11:15Z | 14.5 | 0.1 | success |
| 41127185022 | main | gates (linux) | ubuntu | 2026-10-30T20:56:45Z | 2026-10-30T20:57:52Z | 1.1 | 0.1 | success |
| 41135646272 | main | rust (linux) | ubuntu | 2026-10-30T22:04:48Z | 2026-10-30T22:05:53Z | 1.1 | 0.1 | success |
| 41135646272 | main | gates (linux) | ubuntu | 2026-10-30T22:04:48Z | 2026-10-30T22:05:46Z | 1 | 0.1 | success |
| 41135646272 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 41135649951 | v0.8.3 | suite + app (macos) | macos | 2026-10-30T22:04:49Z | 2026-10-30T22:18:28Z | 13.7 | 0 | success |
| 41135649951 | v0.8.3 | rust (linux) | ubuntu | 2026-10-30T22:04:50Z | 2026-10-30T22:06:01Z | 1.2 | 0.1 | success |
| 41135649951 | v0.8.3 | gates (linux) | ubuntu | 2026-10-30T22:04:50Z | 2026-10-30T22:05:52Z | 1 | 0.1 | success |
| 41141599117 | main | gates (linux) | ubuntu | 2026-10-30T22:58:58Z | 2026-10-30T23:00:05Z | 1.1 | 0 | success |
| 41141599117 | main | rust (linux) | ubuntu | 2026-10-30T22:58:58Z | 2026-10-30T23:00:04Z | 1.1 | 0 | success |
| 41141599117 | main | suite + app (macos) | macos | - | - | - | - | skipped |

#### Gtools v0.8.3: derived

- Runs on the release shas (tag commit 79c9233d, candidate 41c283a8): 4 of the 6 runs in the window.
- Duplicate runs on the same sha: 41c283a8: 41127163812 (CI, push main) + 41127185022 (CI, workflow_dispatch main); 79c9233d: 41135646272 (CI, push main) + 41135649951 (CI, push v0.8.3).
- CI machine-minutes on the release shas: ubuntu 8.9, macOS 28.2, windows 0; billed-equivalent (macOS x10, windows x2) 290.4. Over every run in the window: ubuntu 14.7, macOS 28.2, windows 0.
- Wall-clock, release shas: 2026-10-30T20:56:31Z to 2026-10-30T22:18:29Z = 82 min. Whole window (first run created to last run updated): 2026-10-30T19:16:21Z to 2026-10-30T23:00:06Z = 223.8 min.
- Critical path (longest single job on the release shas): suite + app (macos) in run 41127185022, 14.5 min.
- macOS jobs on the release shas: suite + app (macos) in 41127185022: queued 0.1 min, ran 14.5 min, success; suite + app (macos) in 41135649951: queued 0 min, ran 13.7 min, success.

#### Gtools v0.8.2: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40920687896 | push | main | b56036e9 | CI | 2026-10-29T17:22:22Z | 2026-10-29T17:23:34Z | 1.2 | success | 2/3 | 2.2 | 0 | 0 | gates (linux) 1.1 |
| 40939198152 | push | main | 72d289f9 (tag commit) | CI | 2026-10-29T19:20:28Z | 2026-10-29T19:21:31Z | 1.1 | success | 2/3 | 2 | 0 | 0 | rust (linux) 1 |
| 40939207690 | push | v0.8.2 | 72d289f9 (tag commit) | CI | 2026-10-29T19:20:32Z | 2026-10-29T19:32:50Z | 12.3 | success | 3/3 | 2.3 | 12.2 | 0 | suite + app (macos) 12.2 |
| 40945897619 | push | main | 67342918 | CI | 2026-10-29T20:05:28Z | 2026-10-29T20:06:35Z | 1.1 | success | 2/3 | 1.9 | 0 | 0 | gates (linux) 1.1 |

#### Gtools v0.8.2: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40920687896 | main | rust (linux) | ubuntu | 2026-10-29T17:22:24Z | 2026-10-29T17:23:30Z | 1.1 | 0 | success |
| 40920687896 | main | gates (linux) | ubuntu | 2026-10-29T17:22:25Z | 2026-10-29T17:23:33Z | 1.1 | 0.1 | success |
| 40920687896 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 40939198152 | main | rust (linux) | ubuntu | 2026-10-29T19:20:31Z | 2026-10-29T19:21:31Z | 1 | 0.1 | success |
| 40939198152 | main | gates (linux) | ubuntu | 2026-10-29T19:20:31Z | 2026-10-29T19:21:30Z | 1 | 0.1 | success |
| 40939198152 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 40939207690 | v0.8.2 | suite + app (macos) | macos | 2026-10-29T19:20:37Z | 2026-10-29T19:32:49Z | 12.2 | 0.1 | success |
| 40939207690 | v0.8.2 | rust (linux) | ubuntu | 2026-10-29T19:20:34Z | 2026-10-29T19:21:43Z | 1.2 | 0 | success |
| 40939207690 | v0.8.2 | gates (linux) | ubuntu | 2026-10-29T19:20:35Z | 2026-10-29T19:21:43Z | 1.1 | 0.1 | success |
| 40945897619 | main | gates (linux) | ubuntu | 2026-10-29T20:05:30Z | 2026-10-29T20:06:34Z | 1.1 | 0 | success |
| 40945897619 | main | rust (linux) | ubuntu | 2026-10-29T20:05:30Z | 2026-10-29T20:06:22Z | 0.9 | 0 | success |
| 40945897619 | main | suite + app (macos) | macos | - | - | - | - | skipped |

#### Gtools v0.8.2: derived

- Runs on the release shas (tag commit 72d289f9, candidate a11d3c30): 2 of the 4 runs in the window.
- Duplicate runs on the same sha: 72d289f9: 40939198152 (CI, push main) + 40939207690 (CI, push v0.8.2).
- CI machine-minutes on the release shas: ubuntu 4.3, macOS 12.2, windows 0; billed-equivalent (macOS x10, windows x2) 126.3. Over every run in the window: ubuntu 8.4, macOS 12.2, windows 0.
- Wall-clock, release shas: 2026-10-29T19:20:28Z to 2026-10-29T19:32:50Z = 12.4 min. Whole window (first run created to last run updated): 2026-10-29T17:22:22Z to 2026-10-29T20:06:35Z = 164.2 min.
- Critical path (longest single job on the release shas): suite + app (macos) in run 40939207690, 12.2 min.
- macOS jobs on the release shas: suite + app (macos) in 40939207690: queued 0.1 min, ran 12.2 min, success.

#### Gtools v0.8.1: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40898348666 | push | main | c8f0e6a3 | CI | 2026-10-29T15:07:29Z | 2026-10-29T15:08:44Z | 1.3 | success | 2/3 | 2.2 | 0 | 0 | gates (linux) 1.2 |
| 40920687896 | push | main | b56036e9 (tag commit) | CI | 2026-10-29T17:22:22Z | 2026-10-29T17:23:34Z | 1.2 | success | 2/3 | 2.2 | 0 | 0 | gates (linux) 1.1 |
| 40920695516 | push | v0.8.1 | b56036e9 (tag commit) | CI | 2026-10-29T17:22:25Z | 2026-10-29T17:36:44Z | 14.3 | success | 3/3 | 1.9 | 14.2 | 0 | suite + app (macos) 14.2 |

#### Gtools v0.8.1: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40898348666 | main | gates (linux) | ubuntu | 2026-10-29T15:07:32Z | 2026-10-29T15:08:43Z | 1.2 | 0.1 | success |
| 40898348666 | main | rust (linux) | ubuntu | 2026-10-29T15:07:31Z | 2026-10-29T15:08:34Z | 1.1 | 0 | success |
| 40898348666 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 40920687896 | main | rust (linux) | ubuntu | 2026-10-29T17:22:24Z | 2026-10-29T17:23:30Z | 1.1 | 0 | success |
| 40920687896 | main | gates (linux) | ubuntu | 2026-10-29T17:22:25Z | 2026-10-29T17:23:33Z | 1.1 | 0.1 | success |
| 40920687896 | main | suite + app (macos) | macos | - | - | - | - | skipped |
| 40920695516 | v0.8.1 | suite + app (macos) | macos | 2026-10-29T17:22:31Z | 2026-10-29T17:36:43Z | 14.2 | 0.1 | success |
| 40920695516 | v0.8.1 | rust (linux) | ubuntu | 2026-10-29T17:22:27Z | 2026-10-29T17:23:22Z | 0.9 | 0 | success |
| 40920695516 | v0.8.1 | gates (linux) | ubuntu | 2026-10-29T17:22:27Z | 2026-10-29T17:23:27Z | 1 | 0 | success |

#### Gtools v0.8.1: derived

- Runs on the release shas (tag commit b56036e9, candidate d3c3e698): 2 of the 3 runs in the window.
- Duplicate runs on the same sha: b56036e9: 40920687896 (CI, push main) + 40920695516 (CI, push v0.8.1).
- CI machine-minutes on the release shas: ubuntu 4.2, macOS 14.2, windows 0; billed-equivalent (macOS x10, windows x2) 146.2. Over every run in the window: ubuntu 6.4, macOS 14.2, windows 0.
- Wall-clock, release shas: 2026-10-29T17:22:22Z to 2026-10-29T17:36:44Z = 14.4 min. Whole window (first run created to last run updated): 2026-10-29T15:07:29Z to 2026-10-29T17:36:44Z = 149.3 min.
- Critical path (longest single job on the release shas): suite + app (macos) in run 40920695516, 14.2 min.
- macOS jobs on the release shas: suite + app (macos) in 40920695516: queued 0.1 min, ran 14.2 min, success.

Note on overlap: run 40920687896 (b56036e9 on main) is v0.8.1's main-push run and also falls in v0.8.2's window by time; it is counted for v0.8.1 only in the summary.

#### Gtools baseline (last 10 push-to-main runs)

| run | sha | workflow | created (UTC) | wall min | conclusion | gates (linux) min | rust (linux) min |
|---|---|---|---|---:|---|---:|---:|
| 40920687896 | b56036e9 | CI | 2026-10-29T17:22:22Z | 1.2 | success | 1.1 | 1.1 |
| 40939198152 | 72d289f9 | CI | 2026-10-29T19:20:28Z | 1.1 | success | 1 | 1 |
| 40945897619 | 67342918 | CI | 2026-10-29T20:05:28Z | 1.1 | success | 1.1 | 0.9 |
| 41086385205 | 3895c95c | CI | 2026-10-30T16:03:29Z | 1.3 | success | 1.2 | 1.2 |
| 41088701918 | 875385c9 | CI | 2026-10-30T16:18:37Z | 1.2 | success | 1.1 | 1.1 |
| 41108538545 | 337657af | CI | 2026-10-30T18:37:40Z | 1.7 | success | 1.1 | 1.2 |
| 41113874651 | 08586855 | CI | 2026-10-30T19:16:21Z | 2.7 | success | 2.3 | 1.3 |
| 41127163812 | 41c283a8 | CI | 2026-10-30T20:56:31Z | 1.3 | success | 1.1 | 1.2 |
| 41135646272 | 79c9233d | CI | 2026-10-30T22:04:45Z | 1.2 | success | 1 | 1.1 |
| 41141599117 | 80d35ead | CI | 2026-10-30T22:58:56Z | 1.2 | success | 1.1 | 1.1 |

Per leg (n / min / median / max, minutes): gates (linux) [ubuntu] 10 / 1 / 1.1 / 2.3; rust (linux) [ubuntu] 10 / 0.9 / 1.1 / 1.3. Run wall-clock min / median / max: 1.1 / 1.2 / 2.7 min over 10 runs.

#### Gtools v0.8.3 timeline (2026-10-30, UTC)

| event | time | delta from previous | what ran |
|---|---|---:|---|
| 0123 fix, last code change (276f482b) | 20:50:30 | | nothing yet |
| board mark (41c283a8), the candidate | 20:51:41 | 1.2 min | |
| push; run 41127163812 created (push main, 41c283a8) | 20:56:31 | 4.8 min | gates (linux) 20:56:34 to 20:57:39 (1.1); rust (linux) 20:56:34 to 20:57:48 (1.2); macOS skipped |
| dispatch; run 41127185022 created (workflow_dispatch, 41c283a8) | 20:56:41 | 0.2 min | gates 1.1; rust 1.2; suite + app (macos) 20:56:45 to 21:11:15 (14.5) |
| kovacs (Ubuntu 26.04 aarch64) and gyges (macOS) runs on 41c283a8, per issue 0295 | not timed in any record here | | the full suite, twice more |
| dispatch green | 21:11:16 | 14.6 min | |
| pre-cut wip commit (7048d65f) | 21:15:55 | 4.7 min | nothing (board paths) |
| localfold and compact round, 9 board commits (1fafc878 to b4232187) | 21:31:38 to 21:43:07 | 15.7 min | nothing (paths-ignore) |
| cut starts (RELEASE log birth) | 21:54:47 | 11.7 min | resolve, pre-flight, stamp |
| release commit 79c9233d "release: v0.8.3" (VERSION, Cargo.toml, Cargo.lock, CHANGELOG date) | 21:55:12 | 0.4 min | |
| gate `check all` | from 21:55:12 | | rust rebuild 14 s, health, md, deadlinks, register, risks, theme, shell, clippy, format, autotests, targetdir, toolchain, critic (local) |
| gate `test all` | | | suite 868 tests, 470.4 s test time, 515 s gate wall (8.6 min); app 123 tests, 18.5 s (local) |
| go-ahead confirmed; annotated tag v0.8.3 at 79c9233d | 22:04:37 | 9.4 min from the commit | |
| push to local and upstream; run 41135646272 created (push main, 79c9233d) | 22:04:45 | 0.1 min | gates 1.0 (to 22:05:46); rust 1.1 (to 22:05:53); macOS skipped |
| run 41135649951 created (push v0.8.3, 79c9233d) | 22:04:47 | 0.0 min | gates 1.0; rust 1.2; suite + app (macos) 22:04:49 to 22:18:28 (13.7) |
| release object made; after: formula published to the tap | about 22:05 | | |
| `ci` step: 41135649951 green | 22:18:29 | 13.7 min | |
| cut log closes: "v0.8.3 is released" | 22:18:37 | 0.1 min | cut wall 23.8 min, 14 of them waiting on CI |
| EOD docs push; run 41141599117 (80d35ead) | 22:58:56 | 40.3 min | gates 1.1, rust 1.1 |

From the candidate's push to the release: 20:56:31 to 22:18:37 = 82.1 min. The Elixir suite ran on 41c283a8 in the dispatch's macOS job (14.5), on kovacs and on gyges (untimed), then on 79c9233d in the local gates (8.6) and in the tag run's macOS job (13.7). The Linux gates and rust jobs ran on 79c9233d twice, 2 seconds apart.

### 4.4 Intent

Workflows: `Intent Tests` (push to `main` and tags, pull requests, dispatch; jobs Test on Ubuntu, Test on macOS [macos-latest, tag or dispatch only], Shell Script Analysis, Test Summary), `rust` (push to `main` with path filters, tags, pull requests, dispatch; job rust (ubuntu-latest), plus rust (macos-latest) on a tag or dispatch), `linux release` (tags and dispatch; package (x86_64-unknown-linux-musl, ubuntu-latest) and package (aarch64-unknown-linux-musl, ubuntu-24.04-arm)). `PR Checks` runs on pull requests only. Tags are lightweight.

Release record (local clone):

| release | tag type | tagged (UTC) | release commit | committed (UTC) | parent commit | parent committed (UTC) |
|---|---|---|---|---|---|---|
| v3.2.8 | lightweight (no tagger time) | - | b14e2745 | 2026-10-30T20:40:35Z | bda94eb0 | 2026-10-30T19:52:33Z |
| v3.2.7 | lightweight (no tagger time) | - | 56de3a6e | 2026-10-29T19:45:17Z | e3fc24de | 2026-10-29T19:03:33Z |
| v3.2.6 | lightweight (no tagger time) | - | 88633fe9 | 2026-10-24T12:11:15Z | ebf64d09 | 2026-10-24T11:53:52Z |

#### Intent v3.2.8: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 41121428294 | push | main | bda94eb0 (candidate) | rust | 2026-10-30T20:12:56Z | 2026-10-30T20:22:53Z | 10 | success | 1/1 | 5.8 | 0 | 0 | rust (ubuntu-latest) 5.8 |
| 41121428286 | push | main | bda94eb0 (candidate) | Intent Tests | 2026-10-30T20:12:57Z | 2026-10-30T20:21:02Z | 8.1 | success | 3/4 | 6.7 | 0 | 0 | Test on Ubuntu 6.3 |
| 41125434812 | push | main | b14e2745 (tag commit) | rust | 2026-10-30T20:43:20Z | 2026-10-30T20:50:03Z | 6.7 | success | 1/1 | 6.6 | 0 | 0 | rust (ubuntu-latest) 6.6 |
| 41125435240 | push | main | b14e2745 (tag commit) | Intent Tests | 2026-10-30T20:43:20Z | 2026-10-30T20:50:54Z | 7.6 | success | 3/4 | 7.7 | 0 | 0 | Test on Ubuntu 7.4 |
| 41125436120 | push | v3.2.8 | b14e2745 (tag commit) | Intent Tests | 2026-10-30T20:43:20Z | 2026-10-30T20:56:43Z | 13.4 | success | 4/4 | 7.7 | 13.2 | 0 | Test on macOS 13.2 |
| 41125436150 | push | v3.2.8 | b14e2745 (tag commit) | linux release | 2026-10-30T20:43:20Z | 2026-10-30T20:48:22Z | 5 | success | 2/2 | 9.5 | 0 | 0 | package (x86_64-unknown-linux-musl, ubuntu-latest) 4.9 |
| 41125436284 | push | v3.2.8 | b14e2745 (tag commit) | rust | 2026-10-30T20:43:20Z | 2026-10-30T20:56:43Z | 13.4 | success | 2/2 | 6.9 | 13.3 | 0 | rust (macos-latest) 13.3 |

#### Intent v3.2.8: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 41121428294 | main | rust (ubuntu-latest) | ubuntu | 2026-10-30T20:13:00Z | 2026-10-30T20:18:47Z | 5.8 | 0.1 | success |
| 41121428286 | main | Test on Ubuntu | ubuntu | 2026-10-30T20:13:00Z | 2026-10-30T20:19:16Z | 6.3 | 0.1 | success |
| 41121428286 | main | Shell Script Analysis | ubuntu | 2026-10-30T20:13:00Z | 2026-10-30T20:13:20Z | 0.3 | 0.1 | success |
| 41121428286 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41121428286 | main | Test Summary | ubuntu | 2026-10-30T20:19:19Z | 2026-10-30T20:19:22Z | 0.1 | 6.4 | success |
| 41125434812 | main | rust (ubuntu-latest) | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:50:02Z | 6.6 | 0.1 | success |
| 41125435240 | main | Test on Ubuntu | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:50:46Z | 7.4 | 0.1 | success |
| 41125435240 | main | Shell Script Analysis | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:43:38Z | 0.2 | 0.1 | success |
| 41125435240 | main | Test on macOS | macos | - | - | - | - | skipped |
| 41125435240 | main | Test Summary | ubuntu | 2026-10-30T20:50:49Z | 2026-10-30T20:50:53Z | 0.1 | 7.5 | success |
| 41125436120 | v3.2.8 | Test on Ubuntu | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:50:51Z | 7.5 | 0.1 | success |
| 41125436120 | v3.2.8 | Test on macOS | macos | 2026-10-30T20:43:25Z | 2026-10-30T20:56:36Z | 13.2 | 0.1 | success |
| 41125436120 | v3.2.8 | Shell Script Analysis | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:43:38Z | 0.2 | 0.1 | success |
| 41125436120 | v3.2.8 | Test Summary | ubuntu | 2026-10-30T20:56:39Z | 2026-10-30T20:56:42Z | 0.1 | 13.3 | success |
| 41125436150 | v3.2.8 | package (aarch64-unknown-linux-musl, ubuntu-24.04-arm) | ubuntu | 2026-10-30T20:43:26Z | 2026-10-30T20:48:02Z | 4.6 | 0.1 | success |
| 41125436150 | v3.2.8 | package (x86_64-unknown-linux-musl, ubuntu-latest) | ubuntu | 2026-10-30T20:43:25Z | 2026-10-30T20:48:21Z | 4.9 | 0.1 | success |
| 41125436284 | v3.2.8 | rust (macos-latest) | macos | 2026-10-30T20:43:26Z | 2026-10-30T20:56:43Z | 13.3 | 0.1 | success |
| 41125436284 | v3.2.8 | rust (ubuntu-latest) | ubuntu | 2026-10-30T20:43:24Z | 2026-10-30T20:50:15Z | 6.9 | 0.1 | success |

#### Intent v3.2.8: derived

- Runs on the release shas (tag commit b14e2745, candidate bda94eb0): 7 of the 7 runs in the window.
- Duplicate runs on the same sha: b14e2745: 41125434812 (rust, push main) + 41125435240 (Intent Tests, push main) + 41125436120 (Intent Tests, push v3.2.8) + 41125436150 (linux release, push v3.2.8) + 41125436284 (rust, push v3.2.8); bda94eb0: 41121428286 (Intent Tests, push main) + 41121428294 (rust, push main).
- CI machine-minutes on the release shas: ubuntu 50.9, macOS 26.5, windows 0; billed-equivalent (macOS x10, windows x2) 315.5. Over every run in the window: ubuntu 50.9, macOS 26.5, windows 0.
- Wall-clock, release shas: 2026-10-30T20:12:56Z to 2026-10-30T20:56:43Z = 43.8 min. Whole window (first run created to last run updated): 2026-10-30T20:12:56Z to 2026-10-30T20:56:43Z = 43.8 min.
- Critical path (longest single job on the release shas): rust (macos-latest) in run 41125436284, 13.3 min.
- macOS jobs on the release shas: Test on macOS in 41125436120: queued 0.1 min, ran 13.2 min, success; rust (macos-latest) in 41125436284: queued 0.1 min, ran 13.3 min, success.

#### Intent v3.2.7: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40943952346 | push | main | 56de3a6e (tag commit) | Intent Tests | 2026-10-29T19:52:20Z | 2026-10-29T19:57:47Z | 5.5 | success | 3/4 | 5.6 | 0 | 0 | Test on Ubuntu 5.3 |
| 40943952652 | push | main | 56de3a6e (tag commit) | rust | 2026-10-29T19:52:20Z | 2026-10-29T19:58:52Z | 6.5 | success | 1/1 | 6.5 | 0 | 0 | rust (ubuntu-latest) 6.5 |
| 40943953013 | push | v3.2.7 | 56de3a6e (tag commit) | Intent Tests | 2026-10-29T19:52:20Z | 2026-10-29T20:08:44Z | 16.4 | success | 4/4 | 6.6 | 16.2 | 0 | Test on macOS 16.2 |
| 40943953015 | push | v3.2.7 | 56de3a6e (tag commit) | rust | 2026-10-29T19:52:20Z | 2026-10-29T20:00:32Z | 8.2 | success | 2/2 | 6 | 8.1 | 0 | rust (macos-latest) 8.1 |
| 40943953167 | push | v3.2.7 | 56de3a6e (tag commit) | linux release | 2026-10-29T19:52:20Z | 2026-10-29T19:57:42Z | 5.4 | success | 2/2 | 10.2 | 0 | 0 | package (x86_64-unknown-linux-musl, ubuntu-latest) 5.3 |

#### Intent v3.2.7: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40943952346 | main | Test on Ubuntu | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:57:41Z | 5.3 | 0.1 | success |
| 40943952346 | main | Shell Script Analysis | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:52:36Z | 0.2 | 0.1 | success |
| 40943952346 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40943952346 | main | Test Summary | ubuntu | 2026-10-29T19:57:44Z | 2026-10-29T19:57:47Z | 0.1 | 5.4 | success |
| 40943952652 | main | rust (ubuntu-latest) | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:58:51Z | 6.5 | 0.1 | success |
| 40943953013 | v3.2.7 | Test on macOS | macos | 2026-10-29T19:52:25Z | 2026-10-29T20:08:38Z | 16.2 | 0.1 | success |
| 40943953013 | v3.2.7 | Test on Ubuntu | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:58:39Z | 6.3 | 0.1 | success |
| 40943953013 | v3.2.7 | Shell Script Analysis | ubuntu | 2026-10-29T19:52:24Z | 2026-10-29T19:52:38Z | 0.2 | 0.1 | success |
| 40943953013 | v3.2.7 | Test Summary | ubuntu | 2026-10-29T20:08:41Z | 2026-10-29T20:08:44Z | 0.1 | 16.4 | success |
| 40943953015 | v3.2.7 | rust (ubuntu-latest) | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:58:20Z | 6 | 0.1 | success |
| 40943953015 | v3.2.7 | rust (macos-latest) | macos | 2026-10-29T19:52:24Z | 2026-10-29T20:00:31Z | 8.1 | 0.1 | success |
| 40943953167 | v3.2.7 | package (x86_64-unknown-linux-musl, ubuntu-latest) | ubuntu | 2026-10-29T19:52:23Z | 2026-10-29T19:57:41Z | 5.3 | 0.1 | success |
| 40943953167 | v3.2.7 | package (aarch64-unknown-linux-musl, ubuntu-24.04-arm) | ubuntu | 2026-10-29T19:52:26Z | 2026-10-29T19:57:20Z | 4.9 | 0.1 | success |

#### Intent v3.2.7: derived

- Runs on the release shas (tag commit 56de3a6e, candidate e3fc24de): 5 of the 5 runs in the window.
- Duplicate runs on the same sha: 56de3a6e: 40943952346 (Intent Tests, push main) + 40943952652 (rust, push main) + 40943953013 (Intent Tests, push v3.2.7) + 40943953015 (rust, push v3.2.7) + 40943953167 (linux release, push v3.2.7).
- CI machine-minutes on the release shas: ubuntu 34.7, macOS 24.3, windows 0; billed-equivalent (macOS x10, windows x2) 278.1. Over every run in the window: ubuntu 34.7, macOS 24.3, windows 0.
- Wall-clock, release shas: 2026-10-29T19:52:20Z to 2026-10-29T20:08:44Z = 16.4 min. Whole window (first run created to last run updated): 2026-10-29T19:52:20Z to 2026-10-29T20:08:44Z = 16.4 min.
- Critical path (longest single job on the release shas): Test on macOS in run 40943953013, 16.2 min.
- macOS jobs on the release shas: Test on macOS in 40943953013: queued 0.1 min, ran 16.2 min, success; rust (macos-latest) in 40943953015: queued 0.1 min, ran 8.1 min, success.

#### Intent v3.2.6: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40093074760 | push | v3.2.6 | 88633fe9 (tag commit) | Intent Tests | 2026-10-24T12:13:54Z | 2026-10-24T12:23:05Z | 9.2 | success | 4/4 | 7.8 | 9 | 0 | Test on macOS 9 |
| 40093074766 | push | v3.2.6 | 88633fe9 (tag commit) | rust | 2026-10-24T12:13:54Z | 2026-10-24T12:24:02Z | 10.1 | failure | 2/2 | 1.5 | 10.1 | 0 | rust (macos-latest) 10.1 |
| 40093074921 | push | main | 88633fe9 (tag commit) | Intent Tests | 2026-10-24T12:13:54Z | 2026-10-24T12:19:48Z | 5.9 | success | 3/4 | 6 | 0 | 0 | Test on Ubuntu 5.8 |
| 40093074970 | push | main | 88633fe9 (tag commit) | rust | 2026-10-24T12:13:54Z | 2026-10-24T12:15:14Z | 1.3 | failure | 1/1 | 1.3 | 0 | 0 | rust (ubuntu-latest) 1.3 |
| 40094353696 | workflow_dispatch | v3.2.6 | 88633fe9 (tag commit) | linux release | 2026-10-24T12:32:31Z | 2026-10-24T12:37:20Z | 4.8 | success | 2/2 | 9 | 0 | 0 | package (x86_64-unknown-linux-musl, ubuntu-latest) 4.7 |

#### Intent v3.2.6: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40093074760 | v3.2.6 | Test on macOS | macos | 2026-10-24T12:13:57Z | 2026-10-24T12:22:59Z | 9 | 0.1 | success |
| 40093074760 | v3.2.6 | Test on Ubuntu | ubuntu | 2026-10-24T12:13:57Z | 2026-10-24T12:21:25Z | 7.5 | 0.1 | success |
| 40093074760 | v3.2.6 | Shell Script Analysis | ubuntu | 2026-10-24T12:13:58Z | 2026-10-24T12:14:13Z | 0.3 | 0.1 | success |
| 40093074760 | v3.2.6 | Test Summary | ubuntu | 2026-10-24T12:23:02Z | 2026-10-24T12:23:04Z | 0 | 9.1 | success |
| 40093074766 | v3.2.6 | rust (ubuntu-latest) | ubuntu | 2026-10-24T12:13:57Z | 2026-10-24T12:15:27Z | 1.5 | 0.1 | failure |
| 40093074766 | v3.2.6 | rust (macos-latest) | macos | 2026-10-24T12:13:58Z | 2026-10-24T12:24:01Z | 10.1 | 0.1 | failure |
| 40093074921 | main | Test on Ubuntu | ubuntu | 2026-10-24T12:13:57Z | 2026-10-24T12:19:42Z | 5.8 | 0.1 | success |
| 40093074921 | main | Shell Script Analysis | ubuntu | 2026-10-24T12:13:57Z | 2026-10-24T12:14:08Z | 0.2 | 0.1 | success |
| 40093074921 | main | Test on macOS | macos | - | - | - | - | skipped |
| 40093074921 | main | Test Summary | ubuntu | 2026-10-24T12:19:45Z | 2026-10-24T12:19:47Z | 0 | 5.9 | success |
| 40093074970 | main | rust (ubuntu-latest) | ubuntu | 2026-10-24T12:13:58Z | 2026-10-24T12:15:13Z | 1.3 | 0.1 | failure |
| 40094353696 | v3.2.6 | package (x86_64-unknown-linux-musl, ubuntu-latest) | ubuntu | 2026-10-24T12:32:35Z | 2026-10-24T12:37:19Z | 4.7 | 0.1 | success |
| 40094353696 | v3.2.6 | package (aarch64-unknown-linux-musl, ubuntu-24.04-arm) | ubuntu | 2026-10-24T12:32:37Z | 2026-10-24T12:36:50Z | 4.2 | 0.1 | success |

#### Intent v3.2.6: derived

- Runs on the release shas (tag commit 88633fe9, candidate ebf64d09): 5 of the 5 runs in the window.
- Duplicate runs on the same sha: 88633fe9: 40093074760 (Intent Tests, push v3.2.6) + 40093074766 (rust, push v3.2.6) + 40093074921 (Intent Tests, push main) + 40093074970 (rust, push main) + 40094353696 (linux release, workflow_dispatch v3.2.6).
- CI machine-minutes on the release shas: ubuntu 25.4, macOS 19.1, windows 0; billed-equivalent (macOS x10, windows x2) 216.3. Over every run in the window: ubuntu 25.4, macOS 19.1, windows 0.
- Wall-clock, release shas: 2026-10-24T12:13:54Z to 2026-10-24T12:37:20Z = 23.4 min. Whole window (first run created to last run updated): 2026-10-24T12:13:54Z to 2026-10-24T12:37:20Z = 23.4 min.
- Critical path (longest single job on the release shas): rust (macos-latest) in run 40093074766, 10.1 min.
- macOS jobs on the release shas: Test on macOS in 40093074760: queued 0.1 min, ran 9 min, success; rust (macos-latest) in 40093074766: queued 0.1 min, ran 10.1 min, failure.

v3.2.6's `rust` runs (40093074766 on the tag, 40093074970 on main) both failed; the tag was left standing and `linux release` was dispatched by hand 18 minutes later (40094353696).

#### Intent baseline (last 10 push-to-main runs, both workflows)

| run | sha | workflow | created (UTC) | wall min | conclusion | Shell Script Analysis min | Test Summary min | Test on Ubuntu min | rust (ubuntu-latest) min |
|---|---|---|---|---:|---|---:|---:|---:|---:|
| 36257855375 | 701c4d98 | rust | 2026-09-26T17:06:46Z | 5.4 | success | - | - | - | 5.3 |
| 38948295539 | 7bfca4e7 | rust | 2026-10-16T18:33:47Z | 7 | success | - | - | - | 6.9 |
| 39031497040 | f89b8285 | rust | 2026-10-17T12:10:40Z | 5.7 | success | - | - | - | 5.6 |
| 39850701271 | 2e0e9215 | Intent Tests | 2026-10-22T20:39:10Z | 4.8 | success | 0.3 | 0.1 | 4.6 | - |
| 39850701363 | 2e0e9215 | rust | 2026-10-22T20:39:10Z | 5.4 | success | - | - | - | 5.3 |
| 39857791246 | bbd91e70 | Intent Tests | 2026-10-22T21:30:19Z | 5.7 | failure | 0.3 | 0.1 | 5.5 | - |
| 39859110923 | bea25312 | Intent Tests | 2026-10-22T21:40:10Z | 6.9 | failure | 0.2 | 0.1 | 6.7 | - |
| 40093074921 | 88633fe9 | Intent Tests | 2026-10-24T12:13:54Z | 5.9 | success | 0.2 | 0 | 5.8 | - |
| 40093074970 | 88633fe9 | rust | 2026-10-24T12:13:54Z | 1.3 | failure | - | - | - | 1.3 |
| 40333775926 | 8fb1351d | rust | 2026-10-26T13:48:02Z | 6.9 | success | - | - | - | 6.8 |
| 40333775962 | 8fb1351d | Intent Tests | 2026-10-26T13:48:02Z | 6.4 | success | 0.3 | 0.1 | 6.3 | - |
| 40391278700 | ddb749ca | rust | 2026-10-26T19:56:58Z | 6.1 | success | - | - | - | 6.1 |
| 40391278720 | ddb749ca | Intent Tests | 2026-10-26T19:56:58Z | 6.5 | success | 0.3 | 0.1 | 6.3 | - |
| 40943952346 | 56de3a6e | Intent Tests | 2026-10-29T19:52:20Z | 5.5 | success | 0.2 | 0.1 | 5.3 | - |
| 40943952652 | 56de3a6e | rust | 2026-10-29T19:52:20Z | 6.5 | success | - | - | - | 6.5 |
| 41121428294 | bda94eb0 | rust | 2026-10-30T20:12:56Z | 10 | success | - | - | - | 5.8 |
| 41121428286 | bda94eb0 | Intent Tests | 2026-10-30T20:12:57Z | 8.1 | success | 0.3 | 0.1 | 6.3 | - |
| 41125434812 | b14e2745 | rust | 2026-10-30T20:43:20Z | 6.7 | success | - | - | - | 6.6 |
| 41125435240 | b14e2745 | Intent Tests | 2026-10-30T20:43:20Z | 7.6 | success | 0.2 | 0.1 | 7.4 | - |
| 41142294012 | aae13d74 | Intent Tests | 2026-10-30T23:05:22Z | 7.4 | success | 0.2 | 0.1 | 7.2 | - |

Per leg (n / min / median / max, minutes): Shell Script Analysis [ubuntu] 10 / 0.2 / 0.2 / 0.3; Test Summary [ubuntu] 10 / 0 / 0.1 / 0.1; Test on Ubuntu [ubuntu] 10 / 4.6 / 6.3 / 7.4; rust (ubuntu-latest) [ubuntu] 10 / 1.3 / 5.9 / 6.9. Run wall-clock min / median / max: 1.3 / 6.5 / 10 min over 20 runs.

#### Intent v3.2.8 timeline (2026-10-30, UTC)

| event | time | delta from previous | what ran |
|---|---|---:|---|
| devbin upgraded to 0.1.18 (98ac14e07) | 19:15:07 | | (pushed later) |
| ST0087 done, last change before the cut (bda94eb0), the candidate | 19:52:33 | 37.4 min | |
| push; runs 41121428286 (Intent Tests) and 41121428294 (rust) created on bda94eb0 | 20:12:56 / 20:12:57 | 20.4 min | Test on Ubuntu 20:13:00 to 20:19:16 (6.3); Shell Script Analysis 0.3; Test Summary 20:19:19 to 20:19:22; rust (ubuntu-latest) 20:13:00 to 20:18:47 (5.8); macOS skipped |
| candidate green | 20:19:22 (tests), 20:22:53 (rust run updated) | 6.4 min | |
| local `check all` of the cut (FORMAT verdict 20261030-2031 written 20:32:39) | about 20:31 to 20:32:39 | about 9 min idle, then the gate | local checks; no local test log for this date exists in the clone |
| release commit b14e2745 "release: v3.2.8" (11 files: VERSION, Cargo.toml, Cargo.lock, config.json, CHANGELOG, six schema files) | 20:40:35 | 7.9 min | |
| lightweight tag v3.2.8 at b14e2745 | no time recorded | | |
| push of main and tag; five runs created in one second | 20:43:20 | 2.7 min | 41125434812 rust (main): rust (ubuntu-latest) 20:43:24 to 20:50:02 (6.6). 41125435240 Intent Tests (main): Test on Ubuntu 20:43:24 to 20:50:46 (7.4), shellcheck 0.2, summary 20:50:53. 41125436120 Intent Tests (tag): Test on Ubuntu 7.5, Test on macOS 20:43:25 to 20:56:36 (13.2), summary 20:56:42. 41125436150 linux release (tag): x86_64 4.9, aarch64 4.6, done 20:48:22. 41125436284 rust (tag): rust (ubuntu-latest) 6.9, rust (macos-latest) 20:43:26 to 20:56:43 (13.3) |
| linux release done | 20:48:22 | 5.0 min | |
| main runs done | 20:50:03 (rust), 20:50:54 (tests) | 2.5 min | |
| tag runs done, release green | 20:56:43 | 5.8 min | critical path rust (macos-latest) 13.3 min |
| next board commit, "localfold while we wait" (cb9ba5702) | 21:32:44 | 36.0 min | nothing (board paths) |

From the candidate's push to tag green: 20:12:56 to 20:56:43 = 43.8 min; from the release commit to green 16.1 min. Test on Ubuntu ran three times (6.3, 7.4, 7.5) and rust (ubuntu-latest) three times (5.8, 6.6, 6.9) across the candidate and the two release-sha runs; each macOS leg ran once.

### 4.5 Laksa

Workflow: `laksa` (`ci_cd.yml`; push to `main` with `paths-ignore` for the two board trees, pull requests; one job, Test and Quality Checks on `ubuntu-26.04`, 25 min cap; no deploy job is declared). No release tags, so the three most recent push-to-main runs stand in. Each run's head sha is the tip of a batch of commits pushed together.

| stand-in | head sha | committed (UTC) | run created (UTC) | commits in the batch (local log) |
|---|---|---|---|---|
| push-d299dda7 | d299dda7 | 2026-10-30T23:00:11Z | 2026-10-30T23:00:42Z | six close/records commits 22:44:33 to 23:00:11 (2727886c, b698e077, 4b079889, dc0391a1, 24972752, d299dda7); one run for the six |
| push-1f199145 | 1f199145 | 2026-10-30T19:15:58Z | 2026-10-30T19:16:06Z | "Upgrade devbin to 0.1.18" and the records commits before it (3653016a to 28cb107e); the pushes of 19:18 to 19:39 that followed produced no run (paths-ignore) |
| push-725b5709 | 725b5709 | 2026-10-29T20:31:44Z | 2026-10-29T20:31:51Z | "EOD"; the push 33 s earlier (49ca431c, run 40949764888) was superseded and cancelled by the concurrency group after 1.6 min |

#### Laksa push-d299dda7: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 41141787027 | push | main | d299dda7 (tag commit) | laksa | 2026-10-30T23:00:42Z | 2026-10-30T23:17:32Z | 16.8 | failure | 1/1 | 16.8 | 0 | 0 | Test and Quality Checks 16.8 |

#### Laksa push-d299dda7: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 41141787027 | main | Test and Quality Checks | ubuntu | 2026-10-30T23:00:46Z | 2026-10-30T23:17:31Z | 16.8 | 0.1 | failure |

#### Laksa push-d299dda7: derived

- Runs on the release shas (tag commit d299dda7, candidate -): 1 of the 1 runs in the window.
- Duplicate runs on the same sha: none.
- CI machine-minutes on the release shas: ubuntu 16.8, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 16.8. Over every run in the window: ubuntu 16.8, macOS 0, windows 0.
- Wall-clock, release shas: 2026-10-30T23:00:42Z to 2026-10-30T23:17:32Z = 16.8 min. Whole window (first run created to last run updated): 2026-10-30T23:00:42Z to 2026-10-30T23:17:32Z = 16.8 min.
- Critical path (longest single job on the release shas): Test and Quality Checks in run 41141787027, 16.8 min.
- macOS jobs on the release shas: none ran.

#### Laksa push-1f199145: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 41113839695 | push | main | 1f199145 (tag commit) | laksa | 2026-10-30T19:16:06Z | 2026-10-30T19:29:41Z | 13.6 | failure | 1/1 | 13.5 | 0 | 0 | Test and Quality Checks 13.5 |

#### Laksa push-1f199145: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 41113839695 | main | Test and Quality Checks | ubuntu | 2026-10-30T19:16:10Z | 2026-10-30T19:29:40Z | 13.5 | 0.1 | failure |

#### Laksa push-1f199145: derived

- Runs on the release shas (tag commit 1f199145, candidate -): 1 of the 1 runs in the window.
- Duplicate runs on the same sha: none.
- CI machine-minutes on the release shas: ubuntu 13.5, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 13.5. Over every run in the window: ubuntu 13.5, macOS 0, windows 0.
- Wall-clock, release shas: 2026-10-30T19:16:06Z to 2026-10-30T19:29:41Z = 13.6 min. Whole window (first run created to last run updated): 2026-10-30T19:16:06Z to 2026-10-30T19:29:41Z = 13.6 min.
- Critical path (longest single job on the release shas): Test and Quality Checks in run 41113839695, 13.5 min.
- macOS jobs on the release shas: none ran.

#### Laksa push-725b5709: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 40949764888 | push | main | 49ca431c | laksa | 2026-10-29T20:31:18Z | 2026-10-29T20:32:56Z | 1.6 | cancelled | 1/1 | 1.6 | 0 | 0 | Test and Quality Checks 1.6 |
| 40949844924 | push | main | 725b5709 (tag commit) | laksa | 2026-10-29T20:31:51Z | 2026-10-29T20:45:24Z | 13.6 | success | 1/1 | 12.4 | 0 | 0 | Test and Quality Checks 12.4 |

#### Laksa push-725b5709: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 40949764888 | main | Test and Quality Checks | ubuntu | 2026-10-29T20:31:22Z | 2026-10-29T20:32:55Z | 1.6 | 0.1 | cancelled |
| 40949844924 | main | Test and Quality Checks | ubuntu | 2026-10-29T20:32:58Z | 2026-10-29T20:45:23Z | 12.4 | 1.1 | success |

#### Laksa push-725b5709: derived

- Runs on the release shas (tag commit 725b5709, candidate -): 1 of the 2 runs in the window.
- Duplicate runs on the same sha: none.
- CI machine-minutes on the release shas: ubuntu 12.4, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 12.4. Over every run in the window: ubuntu 14, macOS 0, windows 0.
- Wall-clock, release shas: 2026-10-29T20:31:51Z to 2026-10-29T20:45:24Z = 13.6 min. Whole window (first run created to last run updated): 2026-10-29T20:31:18Z to 2026-10-29T20:45:24Z = 14.1 min.
- Critical path (longest single job on the release shas): Test and Quality Checks in run 40949844924, 12.4 min.
- macOS jobs on the release shas: none ran.

#### Laksa baseline (last 10 push-to-main runs)

| run | sha | workflow | created (UTC) | wall min | conclusion | Test and Quality Checks min |
|---|---|---|---|---:|---|---:|
| 37789756340 | a05a8c17 | laksa | 2026-10-08T14:06:29Z | 6.7 | success | 6.7 |
| 39037370955 | 76ccf99b | laksa | 2026-10-17T13:38:10Z | 15.7 | success | 15.6 |
| 39857612281 | 83b6cbbf | laksa | 2026-10-22T21:29:00Z | 21.5 | failure | 21.4 |
| 40222258213 | b12fb828 | laksa | 2026-10-25T18:39:09Z | 13.7 | failure | 13.7 |
| 40885652630 | 862602bd | laksa | 2026-10-29T13:50:26Z | 13 | failure | 12.9 |
| 40899756451 | e130e706 | laksa | 2026-10-29T15:15:45Z | 12.8 | success | 12.8 |
| 40949764888 | 49ca431c | laksa | 2026-10-29T20:31:18Z | 1.6 | cancelled | 1.6 |
| 40949844924 | 725b5709 | laksa | 2026-10-29T20:31:51Z | 13.6 | success | 12.4 |
| 41113839695 | 1f199145 | laksa | 2026-10-30T19:16:06Z | 13.6 | failure | 13.5 |
| 41141787027 | d299dda7 | laksa | 2026-10-30T23:00:42Z | 16.8 | failure | 16.8 |

Per leg (n / min / median / max, minutes): Test and Quality Checks [ubuntu] 10 / 1.6 / 13.2 / 21.4. Run wall-clock min / median / max: 1.6 / 13.6 / 21.5 min over 10 runs.

### 4.6 Conflab

Workflows: `conflab` (`ci.yml`; push to `main` with the board paths ignored, pull requests; jobs Elixir tests + quality, Rust tests (CLI), Rust tests (stamp), Rust tests (daemon), Build context (no local credentials), all ubuntu; the stamp and build-context jobs were added after August, so the v0.6.x runs have three jobs and the baseline five) and `Release` (tags `v*`; Build + sign + notarize macOS ARM on `xcode-27` and Create GitHub Releases, both behind `vars.MACOS_RELEASE_CI == 'on'`, which was off: every Release run skipped both jobs). No tag trigger on `conflab`, so a Conflab release's suite runs once, on the push of `main`. Tags are lightweight.

Release record (local clone):

| release | tag type | tagged (UTC) | release commit | committed (UTC) | parent commit | parent committed (UTC) |
|---|---|---|---|---|---|---|
| v0.6.2 | lightweight (no tagger time) | - | bba47348 | 2026-08-25T09:05:15Z | 198e5f65 | 2026-08-25T09:03:37Z |
| v0.6.1 | lightweight (no tagger time) | - | 2ff69e65 | 2026-08-25T07:59:43Z | 3e91ad30 | 2026-08-25T07:52:38Z |
| v0.6.0 | lightweight (no tagger time) | - | ee3a2b69 | 2026-07-10T16:55:01Z | c29dcc6a | 2026-07-10T16:51:07Z |

#### Conflab v0.6.2: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 32824335720 | push | main | 2ff69e65 | conflab | 2026-08-25T07:59:47Z | 2026-08-25T08:07:01Z | 7.2 | success | 3/3 | 16.1 | 0 | 0 | Rust tests (daemon) 7.2 |
| 32830044144 | push | main | bba47348 (tag commit) | conflab | 2026-08-25T09:05:19Z | 2026-08-25T09:12:59Z | 7.7 | success | 3/3 | 14.1 | 0 | 0 | Rust tests (daemon) 7.5 |
| 32830196383 | push | v0.6.2 | bba47348 (tag commit) | Release | 2026-08-25T09:07:01Z | 2026-08-25T09:07:12Z | 0.2 | skipped | 0/2 | 0 | 0 | 0 | - |

#### Conflab v0.6.2: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 32824335720 | main | Rust tests (CLI) | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:05:26Z | 5.6 | 0.1 | success |
| 32824335720 | main | Elixir tests + quality | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:03:10Z | 3.3 | 0.1 | success |
| 32824335720 | main | Rust tests (daemon) | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:07:00Z | 7.2 | 0.1 | success |
| 32830044144 | main | Elixir tests + quality | ubuntu | 2026-08-25T09:05:22Z | 2026-08-25T09:08:42Z | 3.3 | 0.1 | success |
| 32830044144 | main | Rust tests (daemon) | ubuntu | 2026-08-25T09:05:27Z | 2026-08-25T09:12:58Z | 7.5 | 0.1 | success |
| 32830044144 | main | Rust tests (CLI) | ubuntu | 2026-08-25T09:05:22Z | 2026-08-25T09:08:34Z | 3.2 | 0.1 | success |
| 32830196383 | v0.6.2 | Build + sign + notarize macOS ARM | macos | - | - | - | - | skipped |
| 32830196383 | v0.6.2 | Create GitHub Releases | ubuntu | - | - | - | - | skipped |

#### Conflab v0.6.2: derived

- Runs on the release shas (tag commit bba47348, candidate 198e5f65): 2 of the 3 runs in the window.
- Duplicate runs on the same sha: bba47348: 32830044144 (conflab, push main) + 32830196383 (Release, push v0.6.2).
- CI machine-minutes on the release shas: ubuntu 14.1, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 14.1. Over every run in the window: ubuntu 30.2, macOS 0, windows 0.
- Wall-clock, release shas: 2026-08-25T09:05:19Z to 2026-08-25T09:12:59Z = 7.7 min. Whole window (first run created to last run updated): 2026-08-25T07:59:47Z to 2026-08-25T09:12:59Z = 73.2 min.
- Critical path (longest single job on the release shas): Rust tests (daemon) in run 32830044144, 7.5 min.
- macOS jobs on the release shas: none ran.

#### Conflab v0.6.1: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 32824335720 | push | main | 2ff69e65 (tag commit) | conflab | 2026-08-25T07:59:47Z | 2026-08-25T08:07:01Z | 7.2 | success | 3/3 | 16.1 | 0 | 0 | Rust tests (daemon) 7.2 |
| 32824490103 | push | v0.6.1 | 2ff69e65 (tag commit) | Release | 2026-08-25T08:01:31Z | 2026-08-25T08:01:32Z | 0 | skipped | 0/2 | 0 | 0 | 0 | - |
| 32830044144 | push | main | bba47348 | conflab | 2026-08-25T09:05:19Z | 2026-08-25T09:12:59Z | 7.7 | success | 3/3 | 14.1 | 0 | 0 | Rust tests (daemon) 7.5 |

#### Conflab v0.6.1: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 32824335720 | main | Rust tests (CLI) | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:05:26Z | 5.6 | 0.1 | success |
| 32824335720 | main | Elixir tests + quality | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:03:10Z | 3.3 | 0.1 | success |
| 32824335720 | main | Rust tests (daemon) | ubuntu | 2026-08-25T07:59:50Z | 2026-08-25T08:07:00Z | 7.2 | 0.1 | success |
| 32824490103 | v0.6.1 | Build + sign + notarize macOS ARM | macos | - | - | - | - | skipped |
| 32824490103 | v0.6.1 | Create GitHub Releases | ubuntu | - | - | - | - | skipped |
| 32830044144 | main | Elixir tests + quality | ubuntu | 2026-08-25T09:05:22Z | 2026-08-25T09:08:42Z | 3.3 | 0.1 | success |
| 32830044144 | main | Rust tests (daemon) | ubuntu | 2026-08-25T09:05:27Z | 2026-08-25T09:12:58Z | 7.5 | 0.1 | success |
| 32830044144 | main | Rust tests (CLI) | ubuntu | 2026-08-25T09:05:22Z | 2026-08-25T09:08:34Z | 3.2 | 0.1 | success |

#### Conflab v0.6.1: derived

- Runs on the release shas (tag commit 2ff69e65, candidate 3e91ad30): 2 of the 3 runs in the window.
- Duplicate runs on the same sha: 2ff69e65: 32824335720 (conflab, push main) + 32824490103 (Release, push v0.6.1).
- CI machine-minutes on the release shas: ubuntu 16.1, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 16.1. Over every run in the window: ubuntu 30.2, macOS 0, windows 0.
- Wall-clock, release shas: 2026-08-25T07:59:47Z to 2026-08-25T08:07:01Z = 7.2 min. Whole window (first run created to last run updated): 2026-08-25T07:59:47Z to 2026-08-25T09:12:59Z = 73.2 min.
- Critical path (longest single job on the release shas): Rust tests (daemon) in run 32824335720, 7.2 min.
- macOS jobs on the release shas: none ran.

#### Conflab v0.6.0: runs in the window

| run | event | ref | sha | workflow | created (UTC) | updated (UTC) | wall min | conclusion | jobs ran/total | ubuntu min | macOS min | windows min | longest job |
|---|---|---|---|---|---|---|---:|---|---|---:|---:|---:|---|
| 29105492109 | push | main | c38d615c | conflab | 2026-07-10T15:55:37Z | 2026-07-10T16:04:54Z | 9.3 | failure | 3/3 | 14.8 | 0 | 0 | Elixir tests + quality 9.2 |
| 29106731643 | push | main | 6eedba4a | conflab | 2026-07-10T16:15:32Z | 2026-07-10T16:22:20Z | 6.8 | success | 3/3 | 11.8 | 0 | 0 | Rust tests (daemon) 6.7 |
| 29107297075 | push | main | 49428b4f | conflab | 2026-07-10T16:24:54Z | 2026-07-10T16:28:26Z | 3.5 | success | 3/3 | 7.7 | 0 | 0 | Elixir tests + quality 3.5 |
| 29108880330 | push | main | c29dcc6a (candidate) | conflab | 2026-07-10T16:51:14Z | 2026-07-10T16:54:38Z | 3.4 | success | 3/3 | 7.8 | 0 | 0 | Elixir tests + quality 3.4 |
| 29109115655 | push | main | ee3a2b69 (tag commit) | conflab | 2026-07-10T16:55:07Z | 2026-07-10T16:58:39Z | 3.5 | success | 3/3 | 8.7 | 0 | 0 | Elixir tests + quality 3.5 |
| 29109209862 | push | v0.6.0 | ee3a2b69 (tag commit) | Release | 2026-07-10T16:56:42Z | 2026-07-10T16:56:43Z | 0 | skipped | 0/2 | 0 | 0 | 0 | - |
| 29110653502 | push | main | 5026373f | conflab | 2026-07-10T17:21:00Z | 2026-07-10T17:24:36Z | 3.6 | success | 3/3 | 8.2 | 0 | 0 | Elixir tests + quality 3.6 |
| 29111462756 | push | main | 50559f6e | conflab | 2026-07-10T17:34:33Z | 2026-07-10T17:38:11Z | 3.6 | success | 3/3 | 8.5 | 0 | 0 | Elixir tests + quality 3.6 |
| 29112548223 | push | main | e62c8f40 | conflab | 2026-07-10T17:52:56Z | 2026-07-10T17:56:43Z | 3.8 | success | 3/3 | 8.3 | 0 | 0 | Elixir tests + quality 3.7 |

#### Conflab v0.6.0: jobs

| run | ref | job | runner | started (UTC) | completed (UTC) | duration min | queue min | conclusion |
|---|---|---|---|---|---|---:|---:|---|
| 29105492109 | main | Rust tests (CLI) | ubuntu | 2026-07-10T15:55:39Z | 2026-07-10T16:00:54Z | 5.3 | 0 | success |
| 29105492109 | main | Elixir tests + quality | ubuntu | 2026-07-10T15:55:40Z | 2026-07-10T16:04:53Z | 9.2 | 0.1 | success |
| 29105492109 | main | Rust tests (daemon) | ubuntu | 2026-07-10T15:55:41Z | 2026-07-10T15:56:02Z | 0.4 | 0.1 | failure |
| 29106731643 | main | Rust tests (daemon) | ubuntu | 2026-07-10T16:15:36Z | 2026-07-10T16:22:19Z | 6.7 | 0.1 | success |
| 29106731643 | main | Elixir tests + quality | ubuntu | 2026-07-10T16:15:35Z | 2026-07-10T16:19:10Z | 3.6 | 0.1 | success |
| 29106731643 | main | Rust tests (CLI) | ubuntu | 2026-07-10T16:15:35Z | 2026-07-10T16:17:06Z | 1.5 | 0.1 | success |
| 29107297075 | main | Elixir tests + quality | ubuntu | 2026-07-10T16:24:56Z | 2026-07-10T16:28:25Z | 3.5 | 0 | success |
| 29107297075 | main | Rust tests (daemon) | ubuntu | 2026-07-10T16:24:56Z | 2026-07-10T16:27:44Z | 2.8 | 0 | success |
| 29107297075 | main | Rust tests (CLI) | ubuntu | 2026-07-10T16:24:56Z | 2026-07-10T16:26:21Z | 1.4 | 0 | success |
| 29108880330 | main | Rust tests (CLI) | ubuntu | 2026-07-10T16:51:17Z | 2026-07-10T16:52:53Z | 1.6 | 0.1 | success |
| 29108880330 | main | Rust tests (daemon) | ubuntu | 2026-07-10T16:51:17Z | 2026-07-10T16:54:07Z | 2.8 | 0.1 | success |
| 29108880330 | main | Elixir tests + quality | ubuntu | 2026-07-10T16:51:17Z | 2026-07-10T16:54:38Z | 3.4 | 0.1 | success |
| 29109115655 | main | Elixir tests + quality | ubuntu | 2026-07-10T16:55:10Z | 2026-07-10T16:58:38Z | 3.5 | 0.1 | success |
| 29109115655 | main | Rust tests (CLI) | ubuntu | 2026-07-10T16:56:05Z | 2026-07-10T16:58:01Z | 1.9 | 1 | success |
| 29109115655 | main | Rust tests (daemon) | ubuntu | 2026-07-10T16:55:09Z | 2026-07-10T16:58:24Z | 3.3 | 0 | success |
| 29109209862 | v0.6.0 | Build + sign + notarize macOS ARM | macos | - | - | - | - | skipped |
| 29109209862 | v0.6.0 | Create GitHub Releases | ubuntu | - | - | - | - | skipped |
| 29110653502 | main | Rust tests (CLI) | ubuntu | 2026-07-10T17:21:03Z | 2026-07-10T17:22:43Z | 1.7 | 0.1 | success |
| 29110653502 | main | Elixir tests + quality | ubuntu | 2026-07-10T17:21:03Z | 2026-07-10T17:24:36Z | 3.6 | 0.1 | success |
| 29110653502 | main | Rust tests (daemon) | ubuntu | 2026-07-10T17:21:03Z | 2026-07-10T17:24:04Z | 3 | 0.1 | success |
| 29111462756 | main | Rust tests (CLI) | ubuntu | 2026-07-10T17:34:35Z | 2026-07-10T17:36:05Z | 1.5 | 0 | success |
| 29111462756 | main | Rust tests (daemon) | ubuntu | 2026-07-10T17:34:36Z | 2026-07-10T17:38:03Z | 3.5 | 0.1 | success |
| 29111462756 | main | Elixir tests + quality | ubuntu | 2026-07-10T17:34:36Z | 2026-07-10T17:38:10Z | 3.6 | 0.1 | success |
| 29112548223 | main | Rust tests (daemon) | ubuntu | 2026-07-10T17:52:58Z | 2026-07-10T17:55:58Z | 3 | 0 | success |
| 29112548223 | main | Rust tests (CLI) | ubuntu | 2026-07-10T17:52:59Z | 2026-07-10T17:54:34Z | 1.6 | 0.1 | success |
| 29112548223 | main | Elixir tests + quality | ubuntu | 2026-07-10T17:52:59Z | 2026-07-10T17:56:43Z | 3.7 | 0.1 | success |

#### Conflab v0.6.0: derived

- Runs on the release shas (tag commit ee3a2b69, candidate c29dcc6a): 3 of the 9 runs in the window.
- Duplicate runs on the same sha: ee3a2b69: 29109115655 (conflab, push main) + 29109209862 (Release, push v0.6.0).
- CI machine-minutes on the release shas: ubuntu 16.4, macOS 0, windows 0; billed-equivalent (macOS x10, windows x2) 16.4. Over every run in the window: ubuntu 75.8, macOS 0, windows 0.
- Wall-clock, release shas: 2026-07-10T16:51:14Z to 2026-07-10T16:58:39Z = 7.4 min. Whole window (first run created to last run updated): 2026-07-10T15:55:37Z to 2026-07-10T17:56:43Z = 121.1 min.
- Critical path (longest single job on the release shas): Elixir tests + quality in run 29109115655, 3.5 min.
- macOS jobs on the release shas: none ran.

Note on overlap: v0.6.1 and v0.6.2 were cut 65.5 min apart, so each window holds the other's runs; the summary counts each run for its own release. v0.6.0's window holds six other pushes of that afternoon.

#### Conflab baseline (last 10 push-to-main runs)

| run | sha | workflow | created (UTC) | wall min | conclusion | Build context (no local credentials) min | Elixir tests + quality min | Rust tests (CLI) min | Rust tests (daemon) min | Rust tests (stamp) min |
|---|---|---|---|---:|---|---:|---:|---:|---:|---:|
| 40212639575 | 1d18d3ef | conflab | 2026-10-25T16:38:23Z | 2.6 | success | 0.2 | 2.3 | 1.4 | 2.5 | 0.4 |
| 40218534179 | d3cc34f7 | conflab | 2026-10-25T17:52:10Z | 2.9 | success | 0.3 | 2.9 | 1.4 | 2.7 | 0.4 |
| 40223051691 | 852fedb2 | conflab | 2026-10-25T18:49:11Z | 2.6 | success | 0.2 | 2.6 | 1.5 | 2.5 | 0.5 |
| 40391834039 | fa82050c | conflab | 2026-10-26T20:00:46Z | 2.9 | success | 0.3 | 2.3 | 1.5 | 2.8 | 0.3 |
| 40523623323 | f457157a | conflab | 2026-10-27T14:41:59Z | 5 | success | 0.2 | 4.9 | 1.4 | 3.6 | 0.4 |
| 40885599139 | c8135f5f | conflab | 2026-10-29T13:50:06Z | 3.8 | failure | 0.2 | 3 | 1.7 | 3.8 | 0.5 |
| 40899802616 | 5432daa7 | conflab | 2026-10-29T15:16:02Z | 5.1 | success | 0.3 | 5 | 1.8 | 3.1 | 0.5 |
| 40950570282 | f267899a | conflab | 2026-10-29T20:36:42Z | 3.4 | success | 0.2 | 3 | 1.6 | 3.3 | 0.5 |
| 41113910742 | d8a163d4 | conflab | 2026-10-30T19:16:37Z | 3.9 | success | 0.2 | 3.8 | 1.7 | 3.2 | 0.5 |
| 41142812782 | 66c11071 | conflab | 2026-10-30T23:10:14Z | 3.2 | success | 0.2 | 2.1 | 1.6 | 3.2 | 0.5 |

Per leg (n / min / median / max, minutes): Build context (no local credentials) [ubuntu] 10 / 0.2 / 0.2 / 0.3; Elixir tests + quality [ubuntu] 10 / 2.1 / 2.9 / 5; Rust tests (CLI) [ubuntu] 10 / 1.4 / 1.5 / 1.8; Rust tests (daemon) [ubuntu] 10 / 2.5 / 3.2 / 3.8; Rust tests (stamp) [ubuntu] 10 / 0.3 / 0.5 / 0.5. Run wall-clock min / median / max: 2.6 / 3.3 / 5.1 min over 10 runs.

#### Conflab v0.6.2 timeline (2026-08-25, UTC)

| event | time | delta from previous | what ran |
|---|---|---:|---|
| docs(release) v0.6.1 notes (60b07132) | 07:45:12 | | |
| docs catch-up (3e91ad30) | 07:52:38 | 7.4 min | |
| "Bump version to 0.6.1" (2ff69e65) | 07:59:43 | 7.1 min | |
| push; run 32824335720 (main, 2ff69e65) | 07:59:47 | 0.1 min | Elixir tests + quality 07:59:50 to 08:03:10 (3.3); Rust tests (CLI) 5.6; Rust tests (daemon) 07:59:50 to 08:07:00 (7.2) |
| tag v0.6.1 push; Release run 32824490103 | 08:01:31 | 1.7 min | both jobs skipped (vars gate off) |
| v0.6.1 green | 08:07:01 | 5.5 min | |
| refactor(cli) to anyhow (198e5f65) | 09:03:37 | 56.6 min | no run of its own: pushed together with the bump |
| "Bump version to 0.6.2" (bba47348), the release commit | 09:05:15 | 1.6 min | |
| push; run 32830044144 (main, bba47348) | 09:05:19 | 0.1 min | Elixir tests + quality 09:05:22 to 09:08:42 (3.3); Rust tests (CLI) 09:05:22 to 09:08:34 (3.2); Rust tests (daemon) 09:05:27 to 09:12:58 (7.5) |
| tag v0.6.2 push; Release run 32830196383 | 09:07:01 | 1.7 min | both jobs skipped |
| v0.6.2 green | 09:12:59 | 6.0 min | critical path Rust tests (daemon) 7.5 min |
| docs(issues) 0009 (51d60b15) | 09:15:53 | 2.9 min | |

From the release commit to green: 7.7 min; two releases in 73.2 min. No local cut log for August exists in the clone. The suite ran once per release on CI; the tag added a skipped workflow run.

## 5. Provenance

Run lists: `gh run list --limit 100 --json ...` per repository, 2026-10-31 (Devbin returned 4, the rest 100; the oldest run returned predates every release examined). Job detail: one `gh run view --json jobs,...` per run (95 runs), plus `gh api` GET of the Utilz run's two attempts and of a few runs' job labels. Local: `git tag --sort=-creatordate`, `git log` with `TZ=UTC` and `--date=format-local`, and the files under each clone's `tmp/release/` and `tmp/check/` (birth and modification times via `stat`). No rerun, cancel, dispatch or write of any kind was made.

Provenance note (2026-10-31 21:06Z): the Intent tmp/check and tmp/test logs this document cites were removed from Intent's working tree at Intent's fifth-fold housekeeping of 2026-10-31 on hv's approval. Both directories are banked whole, mtimes included, in Intent's repository at refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar (blob 2c890aee2e59), with every file's blob, size and mtime listed at refs/bank/vc/housekeep-20261031/manifest.txt (blob 0794b39e959d); from Intent's repository root, `git cat-file blob refs/bank/vc/housekeep-20261031/intent-tmp-logs.tar | tar -xpf -` restores them. Devbin's, Gtools's and Laksa's tmp logs cited here are untouched.
