# A. Release core anatomy (Devbin)

Evidence for the root-and-branch review of Devbin's build, test, assemble and release cycle. Anatomy only: what the core does, in what order, where, and what it waits on. Read-only; nothing was run. Every citation is repo-relative `path:line` in the Devbin repository at its current main (HEAD 7ab68c95).

Files read whole: `lib/cmd/release` (3352 lines), `lib/release.steps`, `lib/runlog`, `lib/gatecmd`, `lib/cmd/test`, `bin/.devbin/cmd/test`, `bin/.devbin/cmd/.lib/ci-state`, `bin/.devbin/config.yaml`, `.github/workflows/tests.yml`, `.github/workflows/release.yml`, `docs/releasing.md`, `lib/config.reference.yaml`, the `release`, `macos` and `formula` sections of `docs/configuration.md`, and issues 0295, 0294, 0240, 0223, 0108, 0052, 0293. Read in part: `lib/release.notes` (the verbs and the `releases` kind), `lib/cmd/check`, `lib/cmd/doctor`, `lib/cmd/macos`, `lib/cmd/formula`, `lib/cmd/vendor`, `lib/cmd/upgrade`, `lib/cmd/use`, `lib/resolve` (`run_all`), `lib/helpers` (`gate_exec`, `ask_person`), `lib/config` (the release schema), `bin/.devbin/cmd/.lib/bats-lanes`, `packaging/homebrew/devbin.rb`, and the kept run logs under `tmp/release`, `tmp/test` and `tmp/check` (listed and read, not written).

## 0. The measured shape of the last release (v0.1.18, 2026-10-29)

Reconstructed from file modification times under `tmp/` (UTC) and the git log. The core writes no clock into its logs (section 8), so mtimes are the only timeline it leaves.

| When (UTC) | What | Evidence |
| --- | --- | --- |
| 17:01:45 | release commit `f084e101` ("release: v0.1.18", 4 paths) made by the cut's commit step | `git log` on VERSION |
| 17:01:49 | gate `check syntax` sealed | `tmp/check/20261029-1701.SYNTAX.out` mtime |
| 17:02:56 | `check all` done (syntax, lint, critic, format, toolchain) | `tmp/check/20261029-1701.*.out` mtimes |
| 17:16:12 | `test all` done: 2818 tests in the parallel lane (8 jobs), 9 serial, 2827 in all | `tmp/test/20261029-1701.bats.out` tail |
| 17:16:19 | doctor, confirm (answered at the prompt), annotated tag, push to `local`, cut exits 0 with snapshot, candidate and publish `pending` | `tmp/release/20261029-1701.RELEASE.out` |
| 17:17:14 | `release publish v0.1.18` run 1: confirm FAILED, "nobody to ask: no terminal, and --yes was not given" | `tmp/release/20261029-1717.PUBLISH.out` |
| 17:17:30 to 18:13:50 | `release publish v0.1.18 --yes --expect <sha>` run 2: snapshot `a9b8cd7c` pushed to `candidate/v0.1.18`, waited for CI green (run 40919937412), fast-forwarded public `main`, pushed lightweight tag, deleted the candidate, waited for `release.yml`'s release object, then `after: bin/devbin formula publish` FAILED ("nobody to ask: no terminal", because `--yes` is no person's yes for the tap), ci `skipped` (`ci.tag: false`) | `tmp/release/20261029-1717-30.PUBLISH.out` and `.errors` |

So the cut took about 15 minutes, of which `test all` was about 13m16s, and the publish took 56m20s, nearly all of it waiting for the candidate's whole-matrix run. After that the formula publish and the brew switch were still to do by hand. Total wall from release commit to public tag with object: about 72 minutes, with no overlap anywhere: each phase waited for the last.

The same day's v0.1.17 shows the cost of a red candidate: cut 13:44 to 13:58 UTC (`tmp/release/20261029-1344.RELEASE.out`), publish at 15:40 pushed the candidate and got `unknown` from `ci-state` (HTTP 404: the public repository had no default branch yet, `tmp/release/20261029-1540.PUBLISH.out`), publish at 15:41 then read the candidate red at 16:48 (`run 40904076298 (Test Summary: failure)`, the 0293 defect), and the remedy was the next version: v0.1.18, a whole new cut and a whole new matrix.

## 1. The step graph

### 1.1 The one sequence, and who runs it

The step names, in order, are written once: `lib/release.steps:94`:

```
_RELEASE_STEP_NAMES=(resolve pre-flight stamp commit gates confirm tag push snapshot candidate publish object after ci)
```

A cut (`bin/devbin release <target>`) runs resolve through push, then either stops (publish.url declared) or runs object, after and ci itself (`lib/cmd/release:674` `cut_run`, `:1183-1206`). `release publish` runs resolve, pre-flight, snapshot, confirm, candidate, publish, then the same object, after and ci through `cut_tail` (`lib/cmd/release:2776` `publish_run`, `:3046-3049`). The real cut and the real publish each run inside one sealed gate of their own: `run_gate --label release --suffix RELEASE ... -- cut_run` (`lib/cmd/release:3346`) and `run_gate --label "release publish" --suffix PUBLISH ... -- publish_run` (`:3326`). A dry run of either is not sealed.

Every step with a postcondition reads it first; the readers live in `lib/release.steps` and `release status` prints the same table through the same readers (`lib/cmd/release:3106` `status_report`). Three steps have no postcondition and run on every run that reaches them: gates ("never already: the gates run on every run until the tag exists", `lib/cmd/release:3175`), after (`:3274`) and ci (`:3281`).

### 1.2 The cut, every shape (resolve to push)

Where: this Mac, in the project root, inside the RELEASE gate. Nothing before the push is seen by another machine; pre-flight and the ci.base read touch remotes and GitHub read-only.

| Step | What it does | Waits on | Timeout | Reads postcondition first (resume) | Short-circuits on a recorded result |
| --- | --- | --- | --- | --- | --- |
| resolve | `release_resolve`: bump the newest matching tag or take X.Y.Z; `release_commit`: the tag's commit if the tag exists, else HEAD (`lib/cmd/release:707-727`, `lib/release.steps:191,227`) | git, local | none | yes: an existing tag means `resume` | n/a |
| pre-flight | on `branch`; every remote answers `ls-remote` and can fast-forward (`release_read_remote`, mode `preflight` or `preflight-new`); tree dirty only inside the owned set (version file, sidecars, note, views; `derived:` deferred to stamp); note open or dated today (`notes_check`); version readable; `tmp/release` ignored; gh signed in (object local or ci); assets workflow present in the commit; under publish.url no remote names the public repository; under `ci.base` one ask of `ci.query` about the base (`:729-923`) | each remote (ls-remote, through `git_remote` with prompts off); gh `auth status`; under ci.base the query once | ci.base's one ask is bounded at `ci.wait` (`release_wait "$ci_secs" "" unknown ...`, `:903`: keep is empty, so one ask whose bound is max(ci.wait, 15s)) | reads only; prints every refusal in one run | n/a |
| stamp | `version set <v>` through `gate_exec` (`:947`), each `derived:` command (`:949-955`), `notes_date` today (`:956`), `notes_views` (`:959`), then the owned-set check and a re-read of the stamp (`:970-980`) | local | none | yes: `release_read_stamp` on the working tree (`:933`); once HEAD is the release commit, `already` and `derived:` is not re-run (`:927-931`) | yes, by the tree's own state |
| commit | `git add` the dirty paths, `git commit -q --only -m "release: <tag>"` (`:1008`); project hooks run; re-read the stamp on the new HEAD | local | none | yes: HEAD carries the stamp and the tree is clean (`head_is_release`, `:741-748`) | yes |
| gates | each `gates:` verb in order through the project's own launcher (`"$launcher" "${gw[@]}"`, `:1053`); tree state hashed before and after, HEAD compared (`:1046-1065`); a gate that writes or commits fails the step | each gate's own tools, serially | none from the core (each gate is its own sealed gate; no deadline) | NO: "Never already: the gates leave no postcondition the repository can show" (`:1034-1038`); once the tag exists they are `not re-run`, which "says nothing about a verdict" (`:1042`) | NO |
| confirm | the work left: each remote lacking commit or tag (`release_read_remote`, mode `push`/`push-new`), and under `object: local` with no publish.url the release object and assets (`cut_object_left`, `:1209`); one question through `ask_person` (`:1288`) or `--yes` (`cut_confirm`, `:1266`) | a person at `/dev/tty`, or `--yes`; each remote again (ls-remote); gh for the object read | none | `not re-run` when nothing is left (`:1271`) | yes |
| tag | `git tag -a <tag> <commit> -F <notes body>` (`:1121`), message read from the release commit's materialised tree (`cut_notes_body`, `:650`) | local | none | yes: a found tag is reused, reported, never rewritten (`release_read_tag`) | yes |
| push | per remote in order: the release commit to `branch` (`:1155`), then the tag (`:1162`), each only if lacking, never forced, each through `cut_call` (bounded); then read back through `release_wait` (`:1170`) | each remote | each push `RELEASE_CALL_SECONDS` = 120s (`lib/release.steps:1490`); read-back retried up to `RELEASE_READBACK_SECONDS` = 120s (`:1505`), each ask at least the 15s floor (`:1486`), polled every `RELEASE_POLL_SECONDS` = 15s (`:1526`) | yes: `already` when every remote holds both (`:1144`) | yes |

Shape deltas on the cut:

| Shape | Effect on the cut |
| --- | --- |
| `publish.url` absent | snapshot, candidate, publish rows `skipped` ("no publish.url declared", `:1193-1195`); the cut goes on to `cut_tail` (object, after, ci) in the same process |
| `publish.url` present (Devbin today, `bin/.devbin/config.yaml:89`) | pre-flight refuses any pushed-to remote that names the public repository (`:760-779`); after the push the cut stops at exit 0: snapshot, candidate, publish `pending` on `release publish`, object, after, ci `not reached` (`cut_publish_stop`, `:1307-1321`); `ci.base` is refused by validation (`docs/configuration.md:301`) |
| `ci.base: true` (no publish.url) | pre-flight asks `ci.query` once about the base commit with no tag; green goes on; pending, none, failed, unknown refuse (`:876-917`). Once HEAD is the release commit, the base is its parent and stands only while the release commit changes nothing outside the owned set (`:880-897`) |
| `derived:` declared | stamp runs each command and takes the paths they print into the owned set (`:949-969`); pre-flight defers the outside-dirt check to stamp (`:802-806`); a resumed cut on the release commit never re-runs them (`:928-931`); a dry run does not run them and says so |
| `release.verbs` | a verb left out is refused with exit 2 before anything is read (`:177-185`); a project whose own command cuts offers `check` and `attach` with `cut` off (`:24-29`) |
| `--dry-run` | same reads; the gates run for real on HEAD in place "as a prediction" (`:1066`); no stamp, commit, tag, push; never asks; runs no derived or after; the verdict is the last line (`cut_dry_verdict`, `:1328`). `docs/releasing.md:22`: "so it takes as long as `test all`" |

### 1.3 The tail (object, after, ci), run by the cut without publish.url, or by `release publish` with it

Where: this Mac, inside the same gate; the waits are on GitHub and on the project's `ci.query`.

| Step | What it does | Waits on | Timeout | Reads postcondition first | Short-circuits |
| --- | --- | --- | --- | --- | --- |
| object: `none` | `skipped` (`:1347`) | | | | |
| object: `ci` (Devbin: `config.yaml:73`) | reads the release object through `gh release view` first (`release_wait 0 ...`, `:1369`); absent, waits for the project's workflow to make it (`release_wait "$secs" "pending UNREADABLE" ...`, `:1373`). Never reads a CI verdict | GitHub, `release.yml` | `object_wait`, default 20m (`lib/config:553`), polled every 15s | yes: `already` when it exists | yes |
| object: `local` | `gh release create <tag> --verify-tag --title ... --notes-file ...` through `cut_call` (`:1395-1404`), or `gh release edit` when confirm named a difference; then, with `assets.workflow` declared, `attach_assets` (`:1433`) | GitHub; with assets, the earliest successful run of `assets.workflow` at the tag (`release_read_assets_run`, `lib/release.steps:1110`) | each gh call 120s; the run waited for up to `assets.wait`, default 30m (`lib/config:557`), polled every 15s | yes: object read whole (title and notes); assets `already` when SHA256SUMS agrees with every other asset | yes |
| after | each `after:` command in order through `gate_exec`, with `DEVBIN_RELEASE_CONFIRMED=<tag>` only when a person said yes at the prompt (`:1484`), nothing under `--yes` (`:1486`); a failure is reported and the next still runs (`:1447-1499`) | whatever the commands wait on (Devbin: `formula publish`, section 7) | none from the core | NO: "This step has no postcondition, so a re-run of a finished release runs them again" (`:1450-1451`) | NO |
| ci | only with `ci.query` declared and `ci.tag` true: `ci.query <release-commit-sha>` with `DEVBIN_RELEASE_TAG=<tag>`, while it answers pending or none (`:1526`). Under `ci.tag: false` (Devbin, `config.yaml:68`) `skipped` (`:1515-1516`) | the tag's CI run | `ci.wait`, default 20m (`lib/config:547`), Devbin 90m (`config.yaml:72`); each ask bounded at the time left, never below 15s; polled every 15s | NO | NO |
| end | `cut_back_to_brew` prints the brew switch note only on a fully green run (`:535-544`, called at `:1564`); any after or ci failure exits 1 with the release standing (`:1548-1562`) | | | | |

### 1.4 `release publish` (publish.url present; Devbin's shape)

Where: this Mac, inside the PUBLISH gate; every remote call made from a repository of the run's own under its scratch (`_snapshot_remote`), never through the workroom's remotes.

| Step | What it does | Waits on | Timeout | Reads postcondition first | Short-circuits |
| --- | --- | --- | --- | --- | --- |
| resolve | the tag is here; its commit is the one snapshotted (`:2819-2822`) | git | none | yes | n/a |
| pre-flight | no remote names the public repository; the tag's commit carries the release and the list; `ci.query` declared; `repo` declared under object local or ci; gh signed in; the public url answers one `ls-remote` for the publish branch, the candidate and the tag (`publish_read`, `:2824-2880`) | the public repository (ls-remote), gh | the ls-remote asked once through `release_wait 0` (15s floor) | reads only | n/a |
| snapshot | `snapshot_build` (`:2370`): the tag's tree over `release.snapshot.list`, deterministic identity, date and message, on the public tip, whose whole history is fetched into scratch and checked to be snapshots (`:2519-2587`); a tip that is already this snapshot is found (`:2569-2586`); `--expect` refuses any other sha (`:2888-2890`) | the public repository (ls-remote, fetch of the publish branch and its history) | none | yes, by construction (same inputs, same sha) | yes |
| confirm | as a cut's: `cut_confirm` (`:2919-2933`); under object local also the object read | a person or `--yes` | none | `not re-run` when nothing left | yes |
| candidate | push the snapshot to `candidate/{tag}` unless it holds it (`:2948`), read back (`:2950`), then `ci.query <snapshot-sha>` with NO tag, while pending or none (`:2958`). Only green goes on; red stops with the candidate left as the record (`:2959-2970`) | the public repository; the candidate's CI run (whole matrix) | push 120s; the wait `ci.wait` = 90m for Devbin, asked every 15s | yes: `already` when the tag and branch are both at the snapshot (`:2936`) | yes |
| publish | re-read the public refs (`:2986`); fast-forward the publish branch (`:2997`), push the tag lightweight (`:3011`), read back (`:3017`); delete the candidate with a lease (`:3030`), read back (`:3032`) | the public repository | each push 120s; each read-back up to 120s | yes | yes |
| object, after, ci | `cut_tail` with `commit=$snap` (`:3048`), against `release.repo` (the public repository): for Devbin object ci waits for `release.yml`, after runs `formula publish`, ci is skipped | as 1.3 | as 1.3 | as 1.3 | as 1.3 |

### 1.5 The per-step map in one line, Devbin's current shape

cut: resolve, pre-flight, stamp, commit, [gates: check all; test all; doctor], confirm (prompt), tag, push to `local`, stop. By hand: `release snapshot` to read the sha (optional), then `release publish --expect <sha> --yes`. publish: resolve, pre-flight (public ls-remote), snapshot (fetch public history), confirm, candidate push, wait up to 90m for the matrix, ff main, push tag, delete candidate, wait up to 20m for `release.yml`'s object, run `formula publish` (which cannot ask under `--yes`, so FAILED, exit 1), ci skipped. By hand: `formula publish` at a terminal, `brew upgrade devbin`, `devbin use brew`.

## 2. Every point at which the suite, check gates or doctor execute during one release

In sequence. "RC" is the release commit (the stamped commit the cut makes); "cand" is the candidate the cut starts from (HEAD before the stamp); "snap" is the public snapshot, a different sha again (the tag's tree filtered over `tests/shipped.paths`, with its own identity and no history).

| # | Where | What runs | Condition | On which commit |
| --- | --- | --- | --- | --- |
| 1 | this Mac, by convention | the commit gate at every commit: Intent's guards, `intent critic <lang>` on staged files, `intent doctor` (`AGENTS.md`, "Testing Instructions" 5; `.git/hooks/pre-commit` chains `pre-commit.intent`) | every commit, the release commit included (`docs/configuration.md:386`: "The project's commit hooks run") | each commit, RC included |
| 2 | this Mac, by convention | the full `test all` by hand before a cut (and, in the estate's practice, the suite on a Linux VM) | hv's practice, not the core's; the core never reads these seals | cand |
| 3 | this Mac, by convention | `bin/devbin release v<x> --dry-run`: "runs the gates for real in place on HEAD as a prediction (so it takes as long as test all)" (`docs/releasing.md:22`; `lib/cmd/release:1066`) | when a person dry-runs first, as `docs/releasing.md:15-16` lists | cand (HEAD, unstamped) |
| 4 | GitHub, by convention | `gh workflow run tests.yml --ref main`: the whole matrix on demand, macOS included (`docs/releasing.md:59`) | "When that side has been quiet, ask for it before cutting" | cand (or whatever main is) |
| 5 | GitHub, read by the core | `ci.base`: pre-flight reads CI on the base (`lib/cmd/release:876-917`); the run itself was the push-to-main run (Ubuntu and ShellCheck only, `tests.yml:128,343`) | `ci.base: true` and no publish.url (refused under publish.url). Devbin had this between 0223 and 0240; Devbin does not today | cand (the base) |
| 6 | this Mac, the core | the gates step: `check all` (syntax, lint, critic, format, toolchain; each a separate process through `run_all`, `lib/resolve:1147-1152`), then `test all` (`bats-lanes`: parallel lane at half the CPUs, then the serial lane, `bin/.devbin/cmd/test:139-152`), then `doctor` (`config.yaml:54-57`) | every cut until the tag exists; no record is read, none is written that a later run reads | RC |
| 7 | inside #6 | the suite itself runs the lint gate again (`tests/unit/contract.bats:1271`, issue 0155) and `release check` (views compared) against the repository (`docs/releasing.md:71`) | every `test all` | RC |
| 8 | GitHub, Linux | the push-to-main run: on a project without publish.url the push step pushes RC to `branch` and the tag within seconds (`lib/cmd/release:1155,1162`), so `tests.yml` starts two runs on RC, one per ref (0295: "two seconds apart"; the concurrency group is keyed on the ref, `tests.yml:66`, so neither cancels the other). On Devbin the push goes to `local`, a directory, so nothing starts | no publish.url, remote is GitHub | RC |
| 9 | GitHub, the whole matrix | the tag's run: Ubuntu, macOS, ShellCheck, WSL (`tests.yml:17` tag filter; macOS and WSL on `github.ref_type == 'tag'`, `:259,:423`). Since 0294 the Candidate verdict job runs first and skips every leg when `candidate/<tag>` is green on the same sha (`:82-122`); without a candidate (no publish.url) `none` runs the whole matrix | every tag push; read by the ci step when `ci.tag` is true | RC (no publish.url) or snap (publish.url) |
| 10 | GitHub, Ubuntu | `release.yml` on the tag: asserts tag == VERSION, extracts the note body, runs `bin/devbin release check` (`release.yml:25-61`), `gh release create` | every `v*` tag (`release.yml:7`) | RC or snap |
| 11 | GitHub, the whole matrix | the candidate's run: a push to `candidate/**` carries macOS and WSL (`tests.yml:11,259,423`); Ubuntu runs `test all` then `check syntax format toolchain` (`:187,:208-219`); macOS the same plus the bash 3.2 refusal proof (`:286-336`); WSL the suite plus the smoke list (`:520-583`, blocks nothing); the verdict is Test Summary's (`ci-state:45`) | publish.url: the candidate step waits for it (`lib/cmd/release:2958`) | snap |
| 12 | GitHub, Linux | the push of the public `main` (fast-forward at the publish step) starts a push-to-main run, Ubuntu and ShellCheck, "where GitHub starts one at all" (`docs/releasing.md:56`; 0294: "CI holds no run from the fast-forward of main" for v0.1.18) | publish.url | snap |
| 13 | GitHub, the whole matrix unless skipped | the public tag's run: Candidate verdict reads `ci-state <repo> <snap-sha>` with `DEVBIN_RELEASE_TAG=candidate/<tag>` (`tests.yml:100,111`); green skips every leg, Test Summary passes on the verdict (`:676-681,722-724`) | publish.url, after the tag push | snap |
| 14 | this Mac, by convention | `brew upgrade devbin` builds from the public tag's checkout; the formula's `test do` asserts `devbin --version` prints the formula's version (`packaging/homebrew/devbin.rb:87-88`) | step 5 of `docs/releasing.md:11`, by hand | snap, as brew checks it out |
| 15 | this Mac, by convention | `bin/devbin doctor` after the switch (`check_switch`, `lib/cmd/doctor:972`) | by hand | n/a |

For Devbin's own shape today the suite therefore runs: #6 locally on RC, #11 on snap (the whole matrix, about 47 minutes per `config.yaml:70-72`), and nothing again on the tag (#13 skips). For the no-publish shape (Gtools, Utilz, Intent, Laksa, Conflab per 0295) it runs: #6 on RC locally, #8 on RC (push), #9 on RC (tag, whole matrix), plus whatever ran on cand by hand (#2, #3, #4, #5).

## 3. The stamp problem, precisely

### 3.1 What the stamp changes

The stamp step (`lib/cmd/release:924-982`) writes exactly the owned set (`release_owned`, `lib/release.steps:384-394`):

1. the version file, `project.version_from` (default `VERSION`), through `version set <v>` (`:947`), and every `project.version_sidecars` entry (Cargo.toml, mix.exs, package.json, Info.plist recipes; `lib/cmd/version:13,51`). Devbin declares no sidecars; Gtools' 0.8.3 release commit changed `VERSION`, `native/rust/Cargo.toml` and `Cargo.lock` (0295);
2. every path a `derived:` command prints (Devbin declares none);
3. the note's header: `status: released` and `date: <today>` written into `RELEASES/<v>.md` (`notes_date`, `lib/release.notes:243-272`; the writer `_notes_releases_write_date`, `:809-831`); `today` is read once from the local clock, `date +%F` (`lib/cmd/release:699`);
4. the generated views `CHANGELOG.md` and `RELEASES.md`, re-rendered from every note (`notes_views`, `lib/release.notes:283-286`, `:702-734`).

Then the commit step commits exactly those paths as `release: <tag>` (`:1008`). For v0.1.18 that was 4 paths (`tmp/release/20261029-1701.RELEASE.out`, commit row). So RC differs from cand by a version string, a date and two regenerated markdown files, and the tree the suite tested at #2, #3 or #5 is never the tree that ships.

### 3.2 Why the tested commit cannot be tagged as it stands

Everything below reads the version from the tree, not from the tag:

- `release.yml:25-38` refuses a tag whose name is not `VERSION`'s content: "tag v$tag does not match VERSION ($file) -- refusing to publish".
- `doctor`'s `check_devbin_version` compares the running version with the config's constraint (`lib/cmd/doctor:304-341`); the running version is read from `VERSION` in a checkout. It is one of Devbin's gates precisely so a stamp that outgrows the constraint fails before the tag (`docs/releasing.md:65`).
- the snapshot's message reads `{version}` from the commit's own version file (`lib/cmd/release:2447-2456`) and refuses a commit that declares none.
- the formula in source mode fills only `@@TAG@@` and `@@REVISION@@` (`packaging/homebrew/devbin.rb:20-22`), so brew's version is the tag's, and its `test do` asserts `devbin --version` prints it (`:87-88`): a tag on an unstamped tree installs and then fails its own test.
- `release_read_stamp` is the stamp and commit steps' postcondition, the pre-flight tag-sanity refusal ("a tag is never moved or deleted; release a later version", `:848`) and `release publish`'s pre-flight refusal (`:2840-2842`): a tag whose commit's VERSION is not the target is refused everywhere.
- Devbin's suite is version-sensitive by design: `documentation.bats` asserts that no authored file but the config names the current version and that the config carries the constraint (`docs/releasing.md:67-69`; `tests/unit/documentation.bats:1061-1141`), so for Devbin the suite's verdict on cand and on RC are not even the same question.
- 0295 adds Gtools' case: the version is compiled into the binary and the formula's test asserts `gtools version` prints it.

### 3.3 What would have to be recorded to prove "this sha is green on platform X" without running again

The core has no record keyed on a sha. What exists:

- A gate seal (section 8) records the platform and a run id but not the commit: `devbin|   platform: Darwin 27.0.0 arm64 / bash 5.3.20(1)-release` and `devbin|   run: 29fb7bf5` (`lib/runlog:402,406`). The one hook that could carry a sha into a seal is `project.referent` (`measured: <opaque>`, `lib/runlog:1103-1163`), which Devbin's config does not declare and which devbin "NEVER PARSES ... AND MUST NEVER LEARN TO" (`lib/runlog:1127`). So a seal cannot answer "green on sha S" by itself.
- The RELEASE seal's own table names the sha in prose: `gates       done         3 gate(s) passed on f084e101c611, and none wrote to the tree`. Nothing reads it back; `release status` prints the gates row as `pending` on every run (`lib/cmd/release:3175`).
- The ci-state answer is sha-keyed, because GitHub's run list is: `gh run list ... --commit <sha>` (`bin/.devbin/cmd/.lib/ci-state:61`), verdict `green\trun <id>` from the Test Summary job (`:76-105`). That is the one existing "sha S is green" record, and it is GitHub's, not the core's. Its platform coverage is implicit in which legs the run carried (a push-to-main run has no macOS leg; a tag or candidate run has). ci-state does not report which legs ran.
- `release status` records nothing: it reads the repository, the remotes and the release object live (`docs/configuration.md:340-344`).

To prove green without re-running, the core would need, per platform, a record of (sha of the tree tested, platform identity, the gate or workflow, the verdict, when), and a reader of it at the gates step and at the ci step. Today the closest reader is the Candidate verdict job (section 4), which trusts GitHub's own record for one branch name.

## 4. The 0294 mechanism

`tests.yml:82-122`, job `candidate-verdict`, runs first in every run of the Tests workflow (`needs: candidate-verdict` on every leg, `:127,258,342,422`). Only on a tag (`REF_TYPE == tag`, `:107`) does it ask anything; every other event prints "not a tag" and `green=false`. On a tag it runs the project's own query:

```
line="$(DEVBIN_RELEASE_TAG="$CANDIDATE" bin/.devbin/cmd/.lib/ci-state "$REPO" "$SHA" </dev/null)" || rc=$?
```

(`tests.yml:111`), with `CANDIDATE: candidate/${{ github.ref_name }}` (`:100`) and `SHA: ${{ github.sha }}`. ci-state, given a tag in `DEVBIN_RELEASE_TAG`, counts only runs whose head branch equals that name (`ci-state:80`: `[ -z "$tag" ] || [ "$ref" = "$tag" ] || continue`), and answers for the Test Summary job of the worst such run (`:76-105`). Exactly `green` sets `green=true` (`:115-117`); none, failed, pending, unknown or a failing query leave `false` and the whole matrix runs. Each leg's `if:` reads `needs.candidate-verdict.outputs.green != 'true'` (`:128,259,343,423`), and Test Summary accepts the skips only when `ON_CANDIDATE` is `true`, refusing an unrecognised value (`:676-681,709-712`), and prints "No leg ran again: this commit is green on its candidate" (`:722-724`).

What it reads: GitHub's own run list for the exact sha, filtered to the branch name `candidate/<tag>`; nothing of devbin's seals, nothing of the core's. It is honest about the sha because a candidate push and the tag name the same commit (the snapshot) by construction of `release publish`.

Could it generalise?

- To the no-publish shape (a plain tag on a workroom commit): the job only ever asks about `candidate/<ref_name>`. A project without publish.url has no such branch, so it answers `none` and the matrix runs, as the comments say. Generalising means asking ci-state about a different ref: the branch the commit was pushed on (`main`), ie `DEVBIN_RELEASE_TAG=main` or unset. Two things then stand in the way. The push-to-main run does not carry macOS or WSL (`tests.yml:259,423` gate those on tag, dispatch or candidate), so its green is narrower than the tag's run and Test Summary's `MACOS_REQUIRED` (`:611`) would be refusing a skipped macOS leg on a tag. And a push-to-main run can be cancelled by the next push (`concurrency`, `:65-67`) or never start (paths-ignore, `:43-45`), which ci-state handles by walking to the parent only when the diff is wholly ignored (`ci-state:133-160`).
- To a "test-first commit" shape (push RC to main first, wait for green, then tag it): the mechanism works unchanged if the branch run carries the whole matrix, ie the macOS and WSL conditions gain the release branch, or a release-candidate branch name is pushed (the candidate mechanism itself, pointed at the workroom's remote rather than a public snapshot). The query already answers for any head-branch name it is given. The one assumption to change is in `tests.yml:100`: the branch to read is hard-wired to `candidate/<tag>`.

## 5. Serial-by-construction points

Each wait, and what it actually depends on.

1. **Stamp before gates.** Gates run on RC in place (`:1034-1038`). The data dependency is real for Devbin (doctor's constraint check and the suite's version arms read VERSION) and for Gtools (the binary and the formula test), so the gates cannot simply run on cand. But nothing in the gates reads the date or the views except `release check` inside the suite, and the views are a deterministic function of the notes.
2. **Gates before confirm before tag.** Policy: nothing irreversible before the gates pass and a person says yes. The tag depends on the commit alone; the confirm depends on the gates' verdict by design, not by data.
3. **Tag before push, commit before tag, per remote in order, commit then tag per remote** (`:1150-1178`). Data: the tag names the commit. The per-remote loop is serial; each push is a bounded call followed by a read-back loop of up to 120s. Devbin has one remote.
4. **The cut ends, and a person starts `release publish`.** Under publish.url the core stops at exit 0 (`cut_publish_stop`), and the publish is another command, run by hand, with its own pre-flight, its own confirm and its own gate. Nothing depends on that gap; it is where the operator reads the snapshot sha (`docs/releasing.md:10`) and types `--expect`.
5. **Snapshot after the local gates.** The snapshot is a pure function of the tag's commit and the public tip (`snapshot_build`); it could be made and pushed as a candidate the moment RC exists. Today it is made only after gates, confirm, tag and push, so the 47-minute matrix cannot start until the 15-minute local run has finished.
6. **Candidate CI before the publish branch and tag move** (`:2958-2970`). Data: the design's safety rule (0240: "nothing becomes public before CI is green on the very commit that does"). This is the one wait that must precede the public tag. It does not need to follow the local gates.
7. **Object after the tag** (`cut_tail`, object ci waits for `release.yml`). Data: `release.yml` fires on the tag push. Up to 20m of polling, though the workflow itself is seconds (0294: "Release succeeded in 19s" for v0.1.0 in 0052).
8. **after after object.** `formula publish` depends only on the public tag (it reads the tag by ls-remote, `lib/cmd/formula:241`) and the tap. It waits for the object step because the step order says so, not because it reads the object. A project's `after:` that uploads to the object would need it.
9. **ci after after** (no publish.url, `ci.tag` true). The tag's CI run is polled only after every `after:` command has run, so an `after:` such as a tap push happens before CI has reported green on the tag. The ordering is the step list's, not a dependency.
10. **ci.base pre-flight** (no publish.url, `ci.base` true): asked once, never waited on (`:903`, "pending" refuses with "wait for it to finish, then cut again"). The person waits by hand for the push-to-main run, then types the cut.
11. **Inside the gates**: `check all` runs its options one after another in separate processes (`lib/resolve:1147-1152`), `test all` runs the parallel lane then the serial lane (`bats-lanes`), `doctor` runs after both; the three gates are strictly serial through the `gates:` loop (`:1048-1054`). The 2026-10-29 cut spent 1m07s in `check all`, 13m16s in `test all`.
12. **Every GitHub wait polls at a fixed 15s** (`RELEASE_POLL_SECONDS`), each ask bounded at the time left and never under 15s (`release_wait`, `lib/release.steps:1533-1563`). There is no webhook, no `gh run watch`, and no overlap between two waits.
13. **macos** (section 6): requires HEAD at the tag in a clean tree, so it cannot start until the tag step; its publish requires the release object, so not before the object step; `app-notarize` blocks on Apple with `notarytool --wait`.
14. **formula** (section 7): refuses until the public tag exists (`lib/cmd/formula:245`).

## 6. The macos built-in

`lib/cmd/macos`, opt-in (`commands.macos.enabled`). Subcommands and sequence (`:81-110` usage):

| Subcommand | What it does | Builds or stages | Waits on |
| --- | --- | --- | --- |
| `doctor` (`:886`) | platform, declaration, tools (codesign, xcrun, spctl, ditto, plutil, xattr, security, gh), the Developer ID identity counted with a test-sign, the notary credentials PRESENT or MISSING | nothing | the login keychain |
| `store-creds` (`:983`) | the notary credentials into the login keychain, interactive | nothing | a terminal |
| `app-sign` (`:1002-1041`) | `require_tag_head`: HEAD must be the release tag's commit in a clean tree, else it names `git worktree add --detach <dir> <tag>` (`:827-855`); runs `macos.build` when declared (`:1014-1015`, "building: ..."), so this is a second build of the app, after whatever the suite built; stages a copy of `macos.app` under XDG state, outside the build tree; refuses a copy whose bundle id, version or stamps are not the tag's (`app_ship_blockers`, `:781-816`); signs nested code then the bundle with the hardened runtime and a timestamp (`:1036`); reads the signature back | BUILDS (if `macos.build`) and STAGES | the timestamp server (codesign `--timestamp`) |
| `app-notarize` (`:1046-1088`) | zips the staged copy with `ditto --sequesterRsrc` (`:1062`), `xcrun notarytool submit ... --wait` (`:1068-1070`, "usually minutes"), anything but `Accepted` prints Apple's log and stops; `xcrun stapler staple` (`:1082`); then `app_verify_notarised`: `stapler validate` and a quarantined copy through `spctl -a -t exec -vv` expecting `source=Notarized Developer ID` (`:660-697`) | stages a submission zip | Apple's notary service, unbounded (`--wait` has no deadline here); stapler; spctl |
| `app-verify` (`:1090`) | the staged copy's signature, ticket and Gatekeeper verdict; changes nothing | nothing | spctl |
| `publish` (`:1112-1155`) | requires the tag here and the staged copy to be the release's; zips the stapled copy as `macos.asset` (`:1134`); unpacks the zip and re-runs the blockers and the Gatekeeper check on the copy inside (`:1136-1141`); then `bin/devbin release attach <version> --from <dir>` (`:1144`), the core's one way an asset reaches a release (object, assets, files, upload, sums, readback stages, `lib/cmd/release:1793-2075`); last, drops every Launch Services record under `build_root` | stages the asset | GitHub (each gh call bounded at 120s); and, with `release.assets.workflow` declared, the run's attach must have finished first: `--from` is refused until SHA256SUMS agrees ("attach without --from first, then with it", `lib/cmd/release:1823-1836`) |

Sequencing relative to the core: by hand, after the cut. The usage says it in terms: "On the maintainer's machine, after the release core has made the release object, in a tree whose HEAD is the tag (once main has moved past it, a worktree)" (`lib/cmd/macos:85-89`). `app-sign` cannot run before the tag step (HEAD must equal the tag's commit), `publish` cannot run before the object step (the attach's object stage refuses "no release object for <tag>, and the attach makes none", `lib/cmd/release:1803-1806`). Devbin does not enable it; it exists for the app-shipping consumers (issue 0226, 0243). It could be declared as an `after:` command only for `publish`, since `app-sign` and `app-notarize` need the keychain and a tree at the tag; nothing in Devbin's docs does that.

What forces it serial with the suite: the tag-at-HEAD precondition means it starts after gates, confirm, tag and push; `macos.build` rebuilds the app on the same machine after the suite has finished; `notarytool --wait` is a synchronous wait on Apple that nothing else overlaps; and `publish` goes through the attach, which under `assets.workflow` waits for the CI asset run's attach to have finished.

## 7. The formula publish flow and the dev/opt/brew switch

`lib/cmd/formula`, opt-in; Devbin enables it in source mode (`config.yaml:97`). `cmd_publish` (`:686-772`):

1. `formula_settings`; the tap is `formula.tap`, else `default_tap`: `ssh://git@<host>/<owner>/homebrew-<name>.git` under the release repository's owner (`:663-676`).
2. `newest_release_tag` (`:654-660`): the newest tag matching `release.tag` in THIS checkout, the rule `--patch` reads; publish is handed no tag because the core runs `after:` commands with no input and no tag in the environment (`:45-52`).
3. `committed`: refuses a template with changes no commit holds (`:678-684`).
4. `git clone` of the tap into a temporary, through `release_git_remote` (`:716`).
5. `render_source` fills `@@TAG@@` and `@@REVISION@@`; the revision is `formula_revision` (`:232-249`): under publish.url, `git ls-remote <public url> refs/tags/<tag> refs/tags/<tag>^{}` (`:241`), read by `release_listed_tag`; a public repository that carries no such tag dies with "make the release public first: release publish <tag>" (`:245`). So the formula waits, by refusal, for the public tag, which `release publish` pushes at its publish step, two steps before `after:` runs.
6. If the clone's `git status` on the formula path is clean, "the tap ... already carries ... so nothing was published" (`:738`): idempotent, asks nothing.
7. The yes: `DEVBIN_RELEASE_CONFIRMED == tag` pushes without a question (`:751-752`); otherwise `ask_person "formula: push it?"` with `DEVBIN_GATE_TTY` read through `gate_tty_flag` (`:754-760`). The core sets `DEVBIN_RELEASE_CONFIRMED` only when a person answered at the confirm prompt (`lib/cmd/release:1484`, `prompted` set at `:1292`), and never under `--yes` (`:1486`). So a `release publish --yes` always ends with the after step FAILED, "nobody to ask: no terminal" (measured in `tmp/release/20261029-1717-30.PUBLISH.out`; documented at `docs/releasing.md:48`), and the formula is pushed by hand afterwards.
8. `git add`, `git commit -q -m "<name> <version>"`, `git push -q origin HEAD` through `release_git_remote` (`:762-770`).

The switch at the end of `docs/releasing.md:11`: once the tap has the release, `brew upgrade devbin` (brew fetches the public repository at the tag's revision and builds from the checkout; the formula's `test do` asserts `devbin --version` prints the version, `packaging/homebrew/devbin.rb:87-88`), then `devbin use brew`, which removes the `~/.local/bin/devbin` link so Homebrew's answers (`lib/cmd/use:6-8`), then `devbin --version` must read `devbin <version> (brew, <sha12>)`. The core prints this as a NOTE at the end of a fully green cut only (`cut_back_to_brew`, `lib/cmd/release:535-544`, called at `:1564` after the after and ci checks), and `doctor`'s `check_switch` (`lib/cmd/doctor:972`) notes a switch left on dev or opt once brew has caught up. Nothing runs any of it.

Consumers take a new core through `bin/devbin upgrade` in their own tree: the source is `--from <dir>`, else the install the manifest records, ie the tree the machine's switch names (`lib/cmd/upgrade:197-201`, `:21-27`); `vendor` reports the difference without writing (`lib/cmd/vendor:1-23`). So "every estate takes the fix with its next vendor update" (0295) means: brew has the release, the machine is on brew, each project runs `upgrade`.

## 8. What the core records, and where

### 8.1 The sealed run logs (`lib/runlog`)

Every gate, the cut (`RELEASE`), the publish (`PUBLISH`), each `check` option and `test bats` writes a pair under `tmp/<command>/` (`gate_out_dir`, `lib/runlog:1474`):

- name: `<stamp>.<SUFFIX>.out` and `.errors`, stamp `date -u +%Y%m%d-%H%M` taken once per invocation and inherited by every nested gate (`DEVBIN_RUN_STAMP`, `lib/runlog:238`; minted by the dispatcher, `bin/devbin:505`); a collision appends `-SS` then `-SS-n` (`:263-277`). The 2026-10-29 cut's five check seals, its bats seal and its RELEASE seal all share `20261029-1701`.
- `LATEST_<SUFFIX>.{out,errors}` symlinks re-pointed by every non-witness run (`:294-333`).
- `.out` opens with the invocation block (`note_invocation`, `:392-424`), quoted from the real file:

```
devbin| invocation, one argument per line:
devbin|   platform: Darwin 27.0.0 arm64 / bash 5.3.20(1)-release
devbin|   run: 29fb7bf5
devbin|   from: devbin's own release sequence -- cut_run in this process, not a command line
devbin|   argv[0]: cut_run
devbin| 
```

  then the tool's output as it came (`gate_exec "$@" 2>&1 | tee -a "$log"`, `:2019`); an optional `at: <dir>` line when not at the root; a `PROMOTED TO FAILED (...)` line when a counted run executed nothing (`:356-366`); and, only when `project.referent` is declared, `devbin| measured: <opaque>` appended last (`note_referent`, `:1196-1203`). Devbin declares no referent.
- `.errors` opens with the in-flight marker `run in flight (or aborted before sealing) -- no completed verdict; see the .out log` (`:143-145`) and is sealed at the end (`write_errors_file`, `:439-491`): EMPTY exactly when a completed run exited 0; on red, the grammar's extracted failure blocks, else `run FAILED (exit N) with no parseable failure blocks -- log tail:` and the last 50 lines. The PUBLISH seals of 2026-10-29 are all of the second form (generic grammar, nothing parseable).
- the terminal (and so a parent's log) gets `verdict: <absolute .errors path>`, the referent, and the overhead ratio when a runner printed `finished in` (`print_run_verdict`, `:1325-1365`); bats prints none, so no overhead line appears in a Devbin run.
- `record_seal` appends `<rc>\t<label>\t<errors path>` to the `all` ledger, a temporary file that `run_all` removes (`:1396-1413`, `lib/resolve:1136-1145`); not kept.

Timestamps: the filename stamp (start minute, UTC), `DEVBIN_RUN_T0` (epoch seconds, kept in memory for the overhead line only, `:227,:1265`), and the files' own mtimes. No step of the release table carries a time; `grep` for `HH:MM:SS` in the latest RELEASE.out finds nothing. A timeline is reconstructable only from the stamp, the mtimes of each nested seal, and the git dates of the release commit and tag.

Fields a later agent can read from a RELEASE or PUBLISH `.out`: platform, run id, the nested gates' `verdict:` paths (which name their seals), the gate banner lines `release: gate: bin/devbin <gate>`, the confirm question (`Still to do, and seen by other machines once done:`), the table (step, state, detail; the detail carries sha12s, remote names, run ids and the snapshot sha), and the last line (`is cut`, `is published`, `is released`, or `stopped at the <step> step`).

### 8.2 The release table

One renderer, `release_row` (`lib/release.steps:132-142`): `  <step padded>  <state padded>  <detail>`, states from `_RELEASE_ROW_STATES` (`:102`): `done already skipped "not re-run" "not reached" "not read" FAILED would pending UNREADABLE`. Printed by a cut's summary, by a publish's, and by `release status <v>`, which reads every row live and records nothing (`:3106-3290`). Exit 1 from status when any row is UNREADABLE.

### 8.3 What is recorded elsewhere

- The repository: the release commit, the annotated tag (message = the note body), the note's `date:`, the views. Under publish.url the public repository holds the snapshot commit, the lightweight tag and (transiently) the candidate branch.
- GitHub: the Tests runs per sha and head branch (what ci-state reads), the Release workflow's run, the release object.
- The tap: one commit per formula publish, `<name> <version>`.
- Nothing records a gate verdict against a sha, and nothing records when a step started or ended.

## 9. Observations

1. **The same suite runs twice per release by construction, on two shas that cannot share a record.** Under publish.url: `test all` locally on RC (15 min, `tmp/test/20261029-1701.bats.out`) and the whole matrix on snap (56 min of publish wall, `tmp/release/20261029-1717-30.PUBLISH.out`). The snapshot is a different commit (filtered tree, new identity, no parent in the workroom), so no CI record on RC can ever stand for snap, and the local gates on RC are a verdict about a tree that is not the one made public. Without publish.url (0295): local gates on RC, then two GitHub runs on RC two seconds apart (push and tag refs, distinct concurrency groups, `tests.yml:66`), and the tag's run is the whole matrix.
2. **The two long phases never overlap.** The candidate is pushed only after gates, confirm, tag and push have finished (section 5, points 4 and 5), although `snapshot_build` needs only the tag's commit and the public tip. The 13-minute local suite and the 47-minute matrix are strictly sequential, with a human in between.
3. **The gates step has no memory.** "Never already" (`lib/cmd/release:1034-1038`, `:3175`): a cut that stops at confirm, tag or push, and any `--dry-run` before it, re-runs `check all`, `test all` and `doctor` in full. The dry run doubles the local suite by design (`docs/releasing.md:22`).
4. **Every GitHub wait is a 15-second poll of `gh`, one wait at a time** (`release_wait`), and `object_wait` polls for a workflow that takes seconds. There is no overlap between the candidate wait, the object wait and the after step; `formula publish` needs only the public tag and could run the moment the tag is pushed.
5. **The after step under `--yes` is FAILED by construction for Devbin** (`formula publish` needs a person; `DEVBIN_RELEASE_CONFIRMED` is unset under `--yes`), so the documented non-interactive publish always exits 1 and the tap is pushed by hand afterwards. Measured on v0.1.18.
6. **The suite re-runs its own gates inside itself**: `check lint` through `contract.bats:1271` and `release check` (0155, `docs/releasing.md:71`); CI's Ubuntu and macOS jobs run `test all` and then `check syntax format toolchain` by name, having removed the second lint for exactly this reason (0191, `tests.yml:189-197`).
7. **A red candidate costs a whole release**: the fix is the next version (`:2968`), which means a new note, a new cut (local gates again) and a new matrix. v0.1.17 to v0.1.18 on 2026-10-29 is the measured instance (0293).
8. **Assumptions that "stamp first, test once, tag what passed" (0295) would have to change:**
   - the gates step and the ci step need a sha-keyed green record to read; today the only one is GitHub's run list through `ci.query`, and the core's own seals carry platform and run id but no sha (`lib/runlog:402,406`), with the referent hook forbidden from being parsed (`:1127`);
   - the push step sends commit and tag together after confirm (`:1150-1178`); stamp-first pushes RC before the tag and waits for CI on it, a new wait between commit and tag, and the confirm question moves or splits;
   - the branch run must carry the whole matrix or Test Summary refuses the tag's skipped macOS leg (`tests.yml:611,696-699`); the Candidate verdict job reads `candidate/<tag>` only (`:100`);
   - a push to main can be cancelled by the next push (`concurrency`, `:65-67`) or start no run (paths-ignore), so "wait for green on RC" needs either a ref of its own (a candidate branch in the workroom's remote) or ci-state's parent walk;
   - `ci.base` is the existing approximation (green base plus owned-only diff, `:883-897`) and is refused under publish.url; the no-publish shape could extend it to "green on RC itself" with no new mechanism beyond waiting;
   - for Devbin itself the suite and doctor read the stamp, so the commit under test must already be stamped: stamp first is a precondition, not a cost.
9. **Assumptions the more radical shape (tag the tested sha; derive the version from the tag at build time) would have to change:** `release.yml:25-38` (tag must equal VERSION), `project.version_from` and `read_version` as the one source everywhere (doctor, snapshot message `:2447-2456`, `release_read_stamp` as the tag-sanity rule at `:845-848` and `:2840-2842`), the formula's `test do` (`packaging/homebrew/devbin.rb:87-88`), Devbin's `documentation.bats` version arms, and the notes model: `notes_date` writes the date into the tree and the views are generated and committed (`lib/release.notes:243-272,702-734`), so even a tag-derived version leaves a date and two markdown files to write somewhere other than the tested commit, or to accept as a tree change after the test. Under publish.url the snapshot would still be a distinct sha from the workroom commit, so the public candidate run remains a second run unless the workroom's tests run on a snapshot-shaped tree or the candidate is pushed at the cut's push step so the matrix and the local gates run side by side.
10. **Nothing in the core knows about the second machine.** The Linux VM runs 0295 and hv's rulings name are by hand, booked and read outside devbin; the core's only external verdict is `ci.query`, and ci-state reads GitHub alone.
