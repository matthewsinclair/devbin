# The release orchestrators compared -- research feeding devbin issue 0064's design

Archived by devbin-cc on 2026-09-14 so it survives the session. Produced by a read-only research agent: reads, `grep`, `diff`, `cmp` and read-only git only -- no gh, release, build, macos or version command was run anywhere. **Every file:line below is pinned to the HEAD named in the first table; line numbers rot, so re-read before citing any of them.** hv approved a steel thread for the release core with design first; the thread was NOT minted before hv's wrap of 2026-09-14.

## Repositories read

| Repo     | HEAD                                       | Release file                                                                 |
| -------- | ------------------------------------------ | ---------------------------------------------------------------------------- |
| Intent   | `5c4380ce4ad2d2e924e2117f9daea94d923cbb14` | `bin/.devbin/cmd/build.d/release`, last changed `0e06c0a80`, 1,285 lines     |
| Intentv2 | `1842842c409828ed27d69e020b6468282f2ac1f4` | `bin/.devbin/cmd/build.d/release`, last changed `4ef953db`, 839 lines        |
| Conflab  | `f4e38ebbd955252fae77816c891ba47badb57b64` | `bin/.devbin/cmd/release`, last changed `f9875541`, 399 lines                |
| Devbin   | `416a2e2adee488acf0759eba6a86bf1010bed498` | `bin/.devbin/cmd/release` (notes half), `docs/releasing.md`, release workflow |
| Utilz    | `be20938730b1c5af466b8af80192307d4a2152a9` | none -- 2.9.0 was cut by hand                                                |

The issue's Intent line numbers match an older 1,170-line blob (`2239998e3`); at the HEAD above the file is 1,285 lines, so the three orchestrators total 2,523 lines, not 2,408.

## A. The sequence each runs

**Intent** (`set -u`, no errexit; a refusal prints `error:` and exits 1):

1. Parses every argument before any action, so `--help` anywhere prints usage.
2. Target = a bump or an explicit version, which must exceed VERSION.
3. Notes gate: CHANGELOG.md needs a `## [TARGET]` section headed `- in progress`, `- unreleased`, today, or another date with `--allow-stale-date`.
4. Pre-flight: clean tree; schema faces carry the current version; on `main`; remotes `local` and `upstream` exist and neither is frozen; then (unless `--skip-tests`) `intent doctor`, `tests/run_tests.sh`, `cargo build -p intentd` and `cargo test --workspace` in a detached worktree at HEAD with an isolated HOME, and `gh auth status`.
5. Stamping, each step checked: an early canon-spill check; `bin/devbin version set TARGET` (sidecar `native/rust/Cargo.toml`, VERSION last); the CHANGELOG placeholder dated by `sed` and verified; `intent_version` in config.json by `jq`; schema faces regenerated; `Cargo.lock` refreshed by `cargo metadata`, refusing a non-member change; a debug CLI built and version-checked; `agents sync`; `claude upgrade --apply` with a spill refusal; `sync --to-disk` refusing a non-footer view change.
6. Commit: `git commit --only -m "release: vTARGET" -- <sidecar list>` -- **exit status unchecked**, caught only indirectly by a later dirty-tree check.
7. Tag `vTARGET`: reused if already at HEAD, refused if elsewhere, otherwise a **lightweight** `git tag` -- no message, no `--cleanup`, **unchecked**.
8. Push: one tty confirmation, then `git push local main vTARGET` and `git push upstream main vTARGET` -- **both unchecked**.
9. GitHub release: notes = the CHANGELOG section re-extracted after dating; `gh release edit` if one exists, else `gh release create --title --notes-file` -- no `--verify-tag`, no assets, **unchecked**, and "release published" is logged regardless.
10. Artefacts: none; the comment delegates them to `int macos prepare` and `publish`.

**Intentv2**: the same skeleton in an earlier form -- sources `bin/intent_helpers`; writes VERSION with `printf`; does not verify the CHANGELOG rewrite; stamps the native manifest by `sed` only for 3.x; `claude upgrade --apply --skip-settings`; commits the whole index after `git add`. Tag, push and release steps are identical to Intent.

**Conflab** (`set -euo pipefail`):

1. `--help` is honoured in the FIRST position only.
2. Tag shape must match `^v[0-9]+\.[0-9]+\.[0-9]+$`; the current version is printed and never compared.
3. Four notes files must exist (`release-notes/<tag>.md`, a `-dist` variant, and two conflab-dist files); no content or date check.
4. `bin/devbin version set`, then an `awk` rewrite of the `conflab` and `conflabd` lock entries.
5. **Commit and push BEFORE any gate**: a whole-index commit ("Bump version to X") and `git push origin main`.
6. Dirty-tree refusal -- which comes after that commit and push.
7. Gates: `bin/devbin check format|compile|clippy` and `test mix|credo|rust`.
8. Tag, lightweight: create and push; if it exists elsewhere, **force-move and force-push**; if at HEAD, reuse.
9. Release: by default waits on the `release.yml` run for the tag with `gh run watch`; that workflow signs, notarises, staples, writes SHA256SUMS, deletes and recreates the release in two repositories, and syncs conflab-dist. `--local` does the same on the owner's machine.
10. Updates the Homebrew tap (formula and cask), then commits and pushes it.

Two comment-versus-code gaps: the header says nothing runs without an explicit ask, and nothing prompts; and the release workflow calls the `bin/release` and `bin/macos` shims, which exec `bin/conflab`, deleted at `21fb4ed2` -- read, not run, but that CI build step would fail at exec. **Both are Conflab's, not devbin's.**

**Devbin**: `release notes` regenerates CHANGELOG.md and RELEASES.md from `RELEASES/*.md`; `release check` compares them and warns when VERSION has no note; no git, gh, tag or push call. The manual procedure (`docs/releasing.md`) bumps VERSION and the constraint, runs `test all` and `check all`, commits, makes an annotated tag with a short message, and pushes it; a tag-triggered workflow refuses a tag that differs from VERSION or has no note, runs `release check`, and does `gh release create --notes-file --verify-tag`. `docs/releasing.md` refuses to automate the version bump: it is the human's decision. Observed: `v0.1.0` is annotated with a short message rather than the note, and the note was re-dated after tagging (`date: 2026-09-01` at the tag, `2026-09-06` at HEAD).

**The `version` builtin** preflights every file, writes sidecars first and VERSION last, has recipes for Cargo.toml, mix.exs, package.json, `*.plist` and bare version files, refuses `Cargo.lock` by design, and has no git or notes logic.

## B. Cross-cutting behaviour

| Behaviour           | Intent                                                                                         | Intentv2                                            | Conflab                                                                                          | Devbin                                          |
| ------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `--help`            | any position; all args parsed first                                                            | same                                                | first position only: `release --patch --help` and `release vX.Y.Z --help` cut a full release     | first position only: `release notes --help` writes (devbin 0067) |
| `--dry-run`         | runs every gate and the pre-flight, prints each write; several refusals reachable only for real | same, with the preview silently cut at 30 lines     | none                                                                                             | `release check` is a predicate                  |
| Dirty tree          | refused before any write, and again after stamping                                             | same                                                | refused only after the commit and push                                                           | none                                            |
| Branch              | must be `main`                                                                                 | same                                                | not checked; pushes `main` by name                                                               | none                                            |
| Tag exists          | reuse at HEAD, refuse elsewhere                                                                | same                                                | reuse at HEAD, force-move elsewhere                                                              | workflow does not handle it                     |
| Version order       | target must exceed VERSION                                                                     | same                                                | shape only                                                                                       | workflow: tag must equal VERSION                |
| CI status           | never queried                                                                                  | never                                               | only after tagging, to wait on the release workflow                                              | not consulted                                   |
| Unchecked failures  | commit, tag, pushes and gh all unchecked; can exit 0 over a failed release                     | same                                                | errexit, but a `--local` failure inside the `tee` pipeline loses its log line                    | n/a                                             |
| Confirmation        | one tty prompt before the push; no tty exits 2                                                  | same                                                | none                                                                                             | none                                            |

**Re-running after a partial failure.** Intent and Intentv2 cannot resume once the release commit exists: VERSION already equals the target, so the next run refuses before doing anything, and the script's own advice to "re-run when ready" leads to that refusal. A failed gh step is undetected and the run exits 0. `--skip-tests` also skips the gh auth gate, which its help text does not say. Conflab re-runs an explicit tag cleanly up to the tag, but in CI mode a reused tag starts no new workflow and the wait picks up the old run; `--patch` bumps again; an already-updated tap fails the commit under errexit. Devbin's workflow has no path for a release object that already exists.

## C. Where the two Intent copies diverged

Both were last changed together at `4ef953db` (2026-08-18); Intent has 13 later commits to its copy. Intent added: argument help for `- unreleased`, `-h` and exit codes; a log directory for gate diagnostics; a schema-faces gate; cargo in a private worktree with one retry; verified CHANGELOG dating; `devbin version set` for stamping; faces, stamp-CLI and view checks; an unconditional lock refresh; a spill refusal after `claude upgrade --apply`; and `git commit --only` over a declared path list. Identical in both: the argument loop, semver helpers, section extraction, the clean, branch, remote, frozen and gh gates, the config.json stamp, and the tag, push, release and summary steps. Two comment passages are word for word the same, including "A FROZEN REMOTE IS A PRE-FLIGHT FAILURE, NOT A PUSH FAILURE ... a release that is half-published, with a tag on one remote, no GitHub release, and a confusing refusal".

## D. What Utilz's hand-cut 2.9.0 did, checked against Utilz itself

1. **Annotated tag -- confirmed.** `2.9.0` is a tag object on the release commit `ebd0243`, unsigned.
2. **The tag message is the CHANGELOG entry -- confirmed.** Its body is byte-identical to that entry minus its heading, `### Added`, `### Changed` and `### Fixed` included.
3. **`--cleanup=whitespace` -- partly confirmed.** The `###` lines survive, so a non-stripping cleanup was used; the object alone cannot tell `whitespace` from `verbatim`, and the flag name is recorded only in Utilz's restart notes and ST0019.
4. **`gh release create 2.9.0 --verify-tag --title 2.9.0 --notes-from-tag` -- not independently confirmable**; recorded only in ST0019. GitHub was not queried.
5. **A CI-green pre-flight -- not what happened, and the repository points the other way.** The tag was made at 17:02:40, the release commit was first pushed at 17:02:54, and CI green was recorded afterwards. Utilz's tests workflow runs only on pushes to main and on PRs, so CI ran on the push head, a descendant of the tagged commit. **A core that requires CI green on the tagged commit must push that commit as a head and wait for its verdict before tagging**, and Utilz's `install_ci_state` would answer `none` for a commit that was never a head.
6. Also: no `v` in Utilz's tag names; the tag goes on the release commit while `main` moves on; per-utility VERSION files move on their own schedule.

`install_ci_state` runs `gh run list --commit <sha> --workflow tests.yml` under a 10-second watchdog, prints a conclusion, `pending`, `none` or `unknown`, and **always exits 0** -- so a core consuming it has to decide what each non-green answer means.

## E. The smallest set of project-supplied inputs, each justified by an observed difference

1. **Tag name template** -- `vX` for Intent, Conflab and devbin; `X` for Utilz.
2. **Notes provider** (version -> body) -- a CHANGELOG section; `release-notes/<tag>.md` plus a dist variant; a `RELEASES/<v>.md` body; a CHANGELOG entry carried into the tag. Once the core holds a body, annotated tags with `--cleanup=whitespace` can be the core's, not an input.
3. **Dating mode** -- stamp a placeholder at cut; verify a hand-typed date; generate from note fields. Devbin's note re-dated after its tag argues for one source of truth for the date.
4. **Bump policy** -- computed from a flag, or the committed VERSION taken as given (devbin's documented rule, and Utilz's practice).
5. **Version files plus a derived-file hook** that reports which paths it wrote -- lockfiles by `cargo metadata` or `awk`, config.json, schema faces, canon, views. Today the release commit's path list lives in two hand-kept places.
6. **Gate commands** -- doctor, bats and cargo; `devbin check` and `test`; `test all` plus `check all`; Utilz's suites.
7. **CI-state query** -- none; wait on a release workflow; or `install_ci_state`, with the core defining what `none`, `pending` and `unknown` mean and pushing the release commit as a head before asking.
8. **Remotes, in order** -- `local` then `upstream`; `origin`; both, for Utilz. Where two remotes point at GitHub, gh refuses to choose (Utilz issue 0016).
9. **Where the release object is created, and its title** -- locally, from a CI tag push, or either.
10. **Post-tag hooks** -- artefacts, a second repository, a tap: in the command for Conflab, delegated for Intent, ST0019's for Utilz.

**Not inputs:** the branch (every project uses `main`, so a default suffices); the tag target (the core tags the SHA it committed, which also covers Utilz's "release commit, not HEAD"); and confirmation, checked exit statuses and a real resume path, which are core policy precisely because each is missing or broken in at least one project today.
