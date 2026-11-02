# cc archive -- 2026-08-06

Session that closed the whole built-in command library. Archived from the live board at the localfold.

## DONE this session

- **The WP-08 split, hv-ratified.** WP-08 narrowed to Gates and closed at 14/14; WP-14 to WP-18 minted with its deliverables MOVED, not copied. Numbers run past WP-13 because `intent wp new` counts sequentially -- the ID is not a schedule.
- **WP-14 Surfaces (15/15).** Found that the COMMAND-level rig did not exist at all: D19 wired the declarative `run:` for options and stopped, so a project declaring a command exactly as the reference config documents got it listed in help and then told "not built yet". Also found D11 language scoping never reached commands -- `iex` ran the real iex in a shell project. D20 ratified and wired.
- **WP-15 Build and format (6/6).** D21: `fmt --check` does not ship; `check format` is the gate. The asymmetry that follows -- fmt skips a missing formatter, check format fails -- is what "a gate claims a verdict" means.
- **WP-16 Data (6/6).** `db` refuses MIX_ENV=prod, ported from the one project that guarded it. Recursive sub-dispatch discharges AC-04.12. Two dispatcher defects found: a config option declaring `run:` but no `summary:` was silently ignored, and fixing that exposed two different answers to "why is this option inactive".
- **WP-17 Docs and version (9/9).** The riskiest family. Both sidecar invariants ported and tested; one reader, after the first draft grew extractors that disagreed with `read_version` within the hour.
- **WP-18 Shared, off by default (5/5).** D22: the second activation axis, reusing the language column rather than adding a list beside it.
- **WP-04 closed (14/14)** -- the reserved `all` and the exit-code contract, the two deliverables its original AC set never covered.
- **WP-02 closed (6/6)** -- `ARCHITECTURE-shell.md` rewritten from the generic template to the as-built.

## Decisions taken this session

- (2026-08-06) hv ratified splitting WP-08 into six family WPs.
- (2026-08-06) hv ratified D20: framework-owned options exported as `DEVBIN_OPT_<NAME>`.
- (2026-08-06) hv resolved Lamplight's `server all` collision: umbrella targets become a comma-separated ARGUMENT. Needs no framework change.
- (2026-08-06) hv ratified folding the `devbin list` idea into WP-07 as `devbin help --why` rather than minting a command.
- (2026-08-06) D21 and D22 written during WP-15 and WP-18.

---

# cc archive -- 2026-08-06 (second fold: WP-07)

Session that closed the help system. Archived from the live board at the localfold.

## DONE this session

- **WP-07 Help (12/12).** `lib/help`: the generated grouped listing, authored topics from `help/<cmd>.md` with `.d/` sub-topic descent, and `devbin help --why`. 38 tests. The dispatcher lost 56 lines of rendering it should never have held.
- **D23 minted.** One source per fact -- catalogue for what devbin ships, handler header for what a project ships, config over either. The two lower sources are disjoint by construction, so there is no precedence question between them.
- **Four defects found in OTHER WPs' code**, none in help. Help was only the first caller to ask those questions in that shape: config losing to the catalogue at activation (fourth sighting of one rule), `all` reporting a pass for zero options, a bare command exiting 0 having run nothing at four sites, and two copies of one summary already drifted.
- **AC-04.13 corrected**, and the correction came from the corpus rather than from reading devbin: Laksa's authored help had already ruled on the bare-command exit code, in the words of someone bitten by `test && deploy`.
- **`help-migration.md` written.** 70 authored topics, 1,769 lines across 95 KB of launcher, counted rather than recalled, five dispositions ruled. The ten universal topics become FORTY files, not ten -- checked on the largest pair.
- **Three environment traps found and recorded**: TAB is an IFS whitespace character; `/bin/true` does not exist on macOS; bats EVALS test descriptions, so backticks in a name execute.

## Decisions settled here, now permanent in design.md

- (2026-08-05) ST0001 claimed by cc. Sole node on the board; no peers, no roster yet.
- (2026-08-05) hv directives: `all` is synthesised never hand-written (D8); no git branches (D10); `../Utilz` is the prior-art reference; defects in other projects are raised there via `intent issues add`.
- (2026-08-05) D7 reversed during WP-03: one awk-based config reader, no yq. D11 added on hv's observation. D12: devbin uses devbin. D2 extended: shadowing is total.
- (2026-08-05) D13/D14/D15 from WP-05; D16/D17 from WP-06.
- (2026-08-05) D18: built-ins tier by BEHAVIOUR, not name. Corrected twice.
- (2026-08-05) D19, from hv's challenge to D18: one rig, a declared option with `log:` seals through the same runner a built-in uses.
- (2026-08-06) hv ratified splitting WP-08 into six family WPs. All six Done.
- (2026-08-06) hv ratified D20: `DEVBIN_OPT_<NAME>` alongside any project-chosen name. One member, `--iex`.
- (2026-08-06) hv resolved the Lamplight `server all` collision: umbrella targets become a comma-separated ARGUMENT. Needs no framework change; the work is Lamplight-side, in WP-11.
- (2026-08-06) hv ratified folding `devbin list` into WP-07 as `devbin help --why`.
- (2026-08-06) D21: `fmt --check` does not ship; the gate is `check format`.
- (2026-08-06) D22: the second activation axis reuses the language column.
- (2026-08-06) D23: one source per fact, two disjoint lower sources.
- (2026-08-06) D4 as-built: authored help REPLACES generated; the no-file fallback answers; sub-topics descend by D3.
- (2026-08-06) AC-04.13 corrected: bare exits 1, `-h`/`--help` exits 0.

---

# cc archive -- 2026-08-06, second fold

Session that built WP-09. Archived from the live board at the localfold.

## DONE this session

- **WP-09 install, upgrade, doctor (18/18).** `lib/install` plus four commands -- `install`, `upgrade`, `doctor`, `new` -- and `lib/tmpl/`. 75 new tests, 414 total, both gates green, acceptance 150/150 PASS.
- **THE SEAM stated and tested.** `bin/devbin` plus everything under `bin/.devbin/lib/` is devbin's and is replaced wholesale; `config.yaml`, `cmd/` and `help/` are the project's and are never written. `vendored_paths` is the only enumeration of the first half. Kept on the live board because WP-10 and WP-11 depend on it.
- **The manifest laundering defect.** Upgrade refused to overwrite an edited vendored file and then re-checksummed it into the manifest, so doctor called it intact one line later and the next upgrade found nothing to refuse. Two correct-looking steps composing into a false green. Refused paths now carry their install-time checksum forward; a test upgrades twice to hold it.
- **bash 5.2 vs 3.2 on `${var//pat/repl}`.** `&` in the replacement is the matched text on 5.2, literal on 3.2. Confirmed on both. First D9 trap that runs new-bash-breaks rather than old-bash-lacks.
- **Four findings in existing code**, none of them in install: the harness's own second implementation of install; a test hand-listing the `any` built-ins that broke when a fifth shipped; a refutation matching its own documentation; and a `config.reference.yaml` comment promising a doctor check nothing had built.
- **Suite runtime.** 414 tests in about 5.5 minutes. Roughly 45s of that is D24's real-installer fixtures, bought deliberately; the rest of the WP-09 cost is its own 75 install-heavy tests. `manifest_write` and `copy_vendored` were cut from ~104 forks per install to ~30 after the first measurement.

## Decisions settled here, now permanent in design.md

- (2026-08-06) **D24**: `list` and `new`'s config sidecar are not built; the harness installs through the real installer.
- (2026-08-06) **D5 as-built**: the seam; the source is whatever devbin is RUNNING, so an installed devbin seeds the next project; `devbin_version` is a constraint doctor enforces, with the framework version stamped in the manifest header and read from `VERSION` in a checkout.
- (2026-08-06) **A ratified decision has to land in the document it changes.** hv folded `devbin list` into WP-07 on 2026-08-06 and `WP/09/info.md` still listed it as a deliverable, so WP-09 re-derived a settled question. D23's rule -- one home per fact -- applies to process, not only to code.
