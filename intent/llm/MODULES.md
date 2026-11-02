# Module Registry - Devbin

> **The Highlander Rule**: There can be only one module per concern.
> ALWAYS check this file before creating a new module. If a module already owns that concern, use it.
> When you must create a new module, register it here FIRST, then create the file.

## Registry

### Dispatch

| Concern                           | THE Module    | Notes                                                                                                                      |
| --------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Command dispatch, entry point     | `bin/devbin`  | Thin coordinator: resolve root, load config, resolve command, exec                                                         |
| Command resolution + discovery    | `lib/resolve` | Order: `cmd/<name>` -> config `run:` -> `lib/cmd/<name>` -> catalogue line -> refusal, exit 3. Unknown or inactive exits 2 |
| Built-in activation (D11)         | `lib/resolve` | Language scoping, what the tree must hold, `enabled: false`, explicit declaration                                          |
| Multi-option `all` synthesis (D8) | `lib/resolve` | `run_all` / `command_options`. Never hand-written per command                                                              |

### Runtime

| Concern                            | THE Module        | Notes                                                                                                                                                                              |
| ---------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config read + schema validation    | `lib/config`      | `cfg_get` / `cfg_list` / `cfg_validate`. One awk pass, no yq (D7)                                                                                                                  |
| The `release:` declaration         | `lib/config`      | `cfg_release_declared` / `cfg_release_get` / `cfg_release_list`: declared or default, one answer. `release check` asks it too                                                      |
| The built-in catalogue             | `lib/builtins`    | `_DEVBIN_BUILTIN_CATALOGUE` and its readers (`builtin_commands`, `builtin_options_for`, `builtin_option_run`). Data, no side effects; refuses to load without `lib/helpers` (0066) |
| Universal shell helpers            | `lib/helpers`     | Primitives the dispatcher and every handler share. Sourced, not run. No count here: it moves with every addition                                                                   |
| Manifest header reading            | `lib/helpers`     | `manifest_field` + wrappers. MOVED from `lib/install`: the dispatcher needs them and does not source install                                                                       |
| Vendored-runtime update notice     | `lib/helpers`     | `devbin_update_notice`. stderr, tty-only, once a day, never fatal                                                                                                                  |
| What commit a SOURCE holds         | `lib/helpers`     | `_devbin_source_head`. Manifest for an install, git for a checkout. rc 2 when it cannot be told -- never an empty success                                                          |
| Source currency, FIVE states       | `lib/helpers`     | `devbin_source_state`: level / behind / ahead / differs / unknown. The notice stays quiet on several; a CHECK keeps each apart                                                     |
| Interactive upgrade offer          | `lib/helpers`     | `devbin_offer_upgrade`. 0058's both-arm tty test, bare + doctor only, re-entry sentinel                                                                                            |
| Safe generated-doc writing         | `lib/helpers`     | `generated_doc_write`: five refusals around a project's own producer                                                                                                               |
| Replace a file through a temporary | `lib/helpers`     | `replace_file`; `stage_beside` then `rename_staged` for two files. Through a link, mode kept, read-only too                                                                        |
| Follow a chain of symbolic links   | `lib/helpers`     | `follow_links`: plain `readlink`, the end checked with `-ef`; refuses a link to no file                                                                                            |
| Read a find listing whole          | `lib/helpers`     | `find_list`: NUL-separated into an array, C-locale order, find's status by `wait` on the process substitution (0139)                                                               |
| Sealed-gate run logging + verdicts | `lib/runlog`      | Ported from `Conflab/bin/conflab_helpers`. The verdict is a file                                                                                                                   |
| Generic gate runner                | `lib/runlog`      | `run_gate`: run, seal, report. Replaces eight hand-written runner bodies                                                                                                           |
| Gate output extraction grammars    | `lib/runlog`      | mix, credo, cargo, xcodebuild, lua, shell (and `bats`), critic, generic -- beside the writer                                                                                       |
| Shared body of the gate commands   | `lib/gatecmd`     | `run_builtin_gate`. Sourced by the `check` and `test` shims; an `@builtin` option is the shim's `builtin_<command>_<option>`                                                       |
| Help rendering                     | `lib/help`        | Generated global listing; authored detail from the project's `.devbin/help/<cmd>.md`, else devbin's shipped `lib/pages/<cmd>.md` (0113)                                            |
| Install, upgrade, vendor, doctor   | `lib/install`     | Vendors the runtime, writes + verifies `manifest.sha256`                                                                                                                           |
| Writing the MACHINE INSTALL        | `lib/install`     | `publish_install`. ONE writer, shared by install's publish mode and upgrade's -- they differ only in precondition                                                                  |
| Is this devbin's own checkout      | `lib/install`     | `is_devbin_dev_tree`: vendorable FROM, with no vendored runtime of its own                                                                                                         |
| Where the install goes             | `lib/install`     | `install_prefix_configured`. Config, tilde-expanded; `--prefix` overrides for one run                                                                                              |
| Clean-tree gate for publishing     | `lib/install`     | `tree_dirty_paths`. Whole tree, no `--force`; rc 2 when not a git repo, so "cannot tell" is not "clean"                                                                            |
| Tree-vs-SOURCE comparison          | `lib/install`     | `vendor_states`. doctor's baseline is install-time. Which way a source moved is `source_direction`, in `lib/helpers` (0079)                                                        |
| Devbin's own half, enumerated      | `lib/install`     | `vendored_paths` is the roll-call, `vendored_scope` the git pathspec                                                                                                               |
| Build-artefact discovery           | `lib/cmd/clean`   | Unbounded walk classified by REBUILDABILITY: markers AND a sibling manifest                                                                                                        |
| Cargo build-tree classification    | `lib/helpers`     | `_clean_has_markers` and its four helpers. MOVED unchanged from `lib/cmd/clean`: fullcycle asks it too (0148)                                                                      |
| Cargo build-tree placement         | `lib/helpers`     | `cargo_target_dir_why` (a value), `cargo_tree_outside_why` (a place), for fullcycle and check targetdir (0148)                                                                     |
| Destructive-action refusals        | `lib/cmd/clean`   | Live-PATH, peer-node, no-manifest. Asks on a terminal through `ask_person`; refuses when nobody can be asked (0058, 0088)                                                          |
| Infra profile: resolve + validate  | `lib/infra`       | Search order, hard failure naming every path tried, the scan for keys written with no value, and `_INFRA_PROFILE_KEYS`, the one table of keys a profile may carry (0143)           |
| Infra: authoritative DNS reads     | `lib/infra.dns`   | The one reader of live DNS, for `infra check` and `infra init`                                                                                                                     |
| Infra: the DNS and mail checks     | `lib/infra.check` | `infra check`'s legs: the profile against what `lib/infra.dns` reads                                                                                                               |
| Infra: propose a profile           | `lib/infra.init`  | `infra init`: measure, propose, render. Only the measure stage touches the world                                                                                                   |
| Read-only git                      | `lib/helpers`     | `git_readonly` (+ `git_readonly_prime`): `--no-optional-locks`, fsmonitor and untracked cache off, git's repository-local variables cleared. MOVED from `lib/install` (0094)       |
| Split a declared command line      | `lib/helpers`     | `run_words`: word-split and glob, never `eval`'d; a value with no words refused naming its key (0082)                                                                              |
| Ask a person, inside a gate        | `lib/helpers`     | `ask_person`: reads `/dev/tty` only when the gate says a person is there (`DEVBIN_GATE_TTY`); 0 yes, 1 no, 2 nobody to ask                                                         |
| Read a yes/no/none word            | `lib/helpers`     | `is_true_word`, `is_false_word`, `is_no_default`. One spelling of each, for config and answers alike                                                                               |
| The bash floor                     | `lib/helpers`     | `bash_floor_refuse`: bash >= 5, refused by name below it (0022). Parseable by bash 3.2 up to the load guard                                                                        |
| Compare two versions               | `lib/helpers`     | `semver_gt`: part by part, base 10; 2 when either is not X.Y.Z                                                                                                                     |
| A command's option candidates      | `lib/resolve`     | `command_option_candidates`: config's and devbin's, deduplicated -- THE one enumeration (0063)                                                                                     |
| The grammar a gate seals with      | `lib/runlog`      | `gate_grammar`: the declared name, or `generic` for none or `-` (0066)                                                                                                             |

### Built-in commands

| Concern                                 | THE Module          | Notes                                                                                                                                                                                                          |
| --------------------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One built-in command each               | `lib/cmd/<name>`    | `check clean cli db docs dormancy fmt fullcycle infra repl server test version`, and the opt-in `release`. `build` and `iex` have no file: the catalogue gives `iex` its line and a project supplies `build`'s |
| Sub-command routing                     | `lib/cmd/<name>.d/` | An executable at `<name>.d/<word>` routes `devbin <name> <word>`, at any depth. `infra` is its first user                                                                                                      |
| Framework self-management               | `lib/cmd/<name>`    | `install upgrade vendor doctor new devbin shell-init` -- group `Devbin`, always offered                                                                                                                        |
| A project's own doctor checks           | `lib/cmd/doctor`    | `run_project_checks`: every executable in `bin/.devbin/cmd/doctor.d/`, counted into the one summary; `doctor <check>` runs one (0093)                                                                          |
| What `new` scaffolds                    | `lib/tmpl/`         | `handler`, `help.md`, `test.bats`. `tmpl/handler` must itself parse as bash                                                                                                                                    |
| Release notes providers                 | `lib/release.notes` | ST0007 D39: `notes_select` once, then every verb against a root. `releases`, `changelog`, `command`. The core's only reader of notes, and it reads no config                                                   |
| The release sequence                    | `lib/cmd/release`   | ST0007, opt-in (D35). A cut's steps 1 to 11 (`cut_run`), `release status` (`status_report`), `release check`, `release notes`. The one place the steps are ORDERED                                             |
| Release core: each step's postcondition | `lib/release.steps` | ST0007: the readers `release status` and a cut share, and every remote and gh call. Reads no config; the handler passes the facts in                                                                           |

### Documentation

Four places carry prose about the same commands, so the split between them is a Highlander boundary rather than a filing preference. Each answers a different question, and none may answer another's.

| Concern                             | THE Module                         | Answers                                                                                     |
| ----------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------- |
| What is devbin, and how do I start? | `README.md`                        | the front door, for someone who has never seen it                                           |
| Every config key, type and default  | `docs/configuration.md`            | the INDEX; drift-tested against the schema in `lib/config`                                  |
| The annotated worked config         | `lib/config.reference.yaml`        | the ARGUMENT -- why each key is shaped as it is. Vendored                                   |
| The annotated worked profile        | `lib/infra.reference.yaml`         | `infra`'s schema and the argument for each key. VENDORED, and PARSED by the suite every run |
| How do I add a command?             | `docs/authoring-commands.md`       | the author protocol, end to end                                                             |
| How do I move an existing launcher? | `docs/migration.md`                | D10's quiesce-and-inline sequence                                                           |
| How is devbin itself released?      | `docs/releasing.md`                | devbin's own use of `release`, and the tripwires of releasing itself                        |
| Detail for ONE command, at runtime  | `bin/.devbin/help/<cmd>.md`        | authored terminal help. Per-project, on the project's side of the seam, and read first      |
| Detail for ONE built-in, at runtime | `lib/pages/<cmd>.md`               | devbin's terminal help for its built-ins. Vendored, so it reaches every estate (0113)       |
| How is devbin built?                | `intent/llm/ARCHITECTURE-shell.md` | for people changing devbin itself, not using it                                             |

The one to watch is `docs/configuration.md` against `lib/config.reference.yaml`: they cover the same keys deliberately, one as a table and one as an annotated example, and `tests/unit/documentation.bats` holds BOTH to the schema so neither can drift from it or from each other. Do not add a third listing of the keys.

`infra` has the same two-document shape and it is DELIBERATELY not symmetric: `lib/infra.reference.yaml` is the SCHEMA -- vendored, and a valid profile in its own right -- and `lib/pages/infra.md` is the ARGUMENT for the command, which points at the reference and never restates it. There is no third document, and there was: `docs/infrastructure.md` held both until 2026-09-07 and reached no estate, because `docs/` is devbin's own repository and consumers vendor only `bin/devbin` and `lib/`. The same was true of `bin/.devbin/help/infra.md` itself until issue 0113 moved devbin's built-in pages into `lib/pages/`. **If a schema fact needs writing down, it goes in the vendored file or nowhere.** Since issue 0143 the machine statement of the keys is `_INFRA_PROFILE_KEYS` in `lib/infra`, which refuses any other key, and `tests/unit/infra-profile.bats` holds the reference to carry a live example of every row of it: the table is what is enforced, the reference is its argument, and a test keeps the two from drifting apart.

`intent/llm/ARCHITECTURE.md` is a pointer to `ARCHITECTURE-shell.md`, not a second architecture document. It exists because the Intent tooling generates it.

### Development

| Concern                            | THE Module                        | Notes                                                                                                                                                            |
| ---------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BATS shared test helpers           | `tests/lib/test_helper.bash`      | Temp-dir isolation, fixture projects, assertions. No external deps                                                                                               |
| Docs-cannot-drift tests            | `tests/unit/documentation.bats`   | Extracts the schema and the catalogue; each extractor has a floor                                                                                                |
| Devbin's own check gates           | `bin/.devbin/cmd/.lib/shell-gate` | Syntax, lint, critic. NOT a handler: config points `run:` at it                                                                                                  |
| Devbin's own test gate             | `bin/.devbin/cmd/test`            | Project handler. `bats`, declared in Devbin's own config                                                                                                         |
| Devbin's own suite, in two lanes   | `bin/.devbin/cmd/.lib/bats-lanes` | The whole suite: `bats --jobs N`, then the tests tagged `serial`, one verdict (0190). NOT a handler: the test handler runs it through `run_gate`                 |
| Who runs devbin, and sweeping them | `bin/.devbin/cmd/fleet`           | `audit`, `doc`, `upgrade`. Devbin's PROJECT half, not the vendored runtime -- which is why the sweep is a dev-tree verb and an install cannot enumerate anything |
| Estate discovery + exclusions      | `bin/.devbin/cmd/fleet`           | `fleet_roots` / `estate_roots` / `fleet_frozen`. DERIVED by scan, never a maintained registry -- a list lies the first time a project moves                      |

## How to Use This File

1. **Before creating a new module**: Search this table. If the concern is listed, use that module.
2. **When adding a new module**: Add a row here first, then create the file.
3. **When refactoring**: Update this table to reflect the new module ownership.
4. **When removing a module**: Remove its row from this table.

Violations of the Highlander Rule (duplicate modules for the same concern) are the #1 source of code quality debt.

## Standing Highlander watch-items

- ~~`tests/gate`~~ **RESOLVED (WP-04).** It was a deliberate, time-boxed second implementation of "run this project's checks", carried only because WP-02 predated the dispatcher. `bin/devbin check all` now does the job and `tests/gate` is deleted. Do not reintroduce a standalone gate script: Devbin runs its own gates through its own dispatcher (design D12), and a second entry point would be the breach this one was retired to avoid.
- `lib/config` was specced with two backends (yq plus a pure-bash fallback) behind one accessor, kept honest by a differential test. That was a Highlander breach with a test attached, and it was dropped in WP-03 for a single awk-based reader (design D7). Do not reintroduce a second parser: the restricted subset makes any second implementation unreachable by construction, and `tests/unit/config.bats` asserts the reader never invokes yq.

- **The staleness question has TWO readers and that is deliberate, not a breach.** `_devbin_update_line` prints or stays quiet; `devbin_source_state` returns five states. They look like duplicates and are not: a NOTICE must never nag, so quiet is its right answer for both "level" and "cannot tell", and a CHECK must never let those collapse, because absent is not clean. Both go through `_devbin_source_head`, which is the single answer to "what commit does the source hold". Add a third reader of that question and it must go through that function too.

- `lib/grammars` was planned as a module of its own and is NOT one. The extraction grammars live in `lib/runlog`, beside `write_errors_file`, because the writer and its grammars are one concern: a grammar that drifts from what the writer expects produces a seal that is WRONG rather than absent, and a wrong seal is the only failure this subsystem cannot detect after the fact. Splitting them would put a file boundary between two things that must change together.
- The multi-option `all` runner was listed twice, against `lib/resolve` and `lib/runlog`. It is `run_all` in `lib/resolve`: `all` is a question about which options are ACTIVE (D8 plus D11 activation), which is resolution. What it runs them through is `lib/runlog`'s business, and the two meet at the seal ledger rather than by sharing a home.
- The built-in catalogue is `lib/builtins` and ONLY there. `_DEVBIN_BUILTIN_LANGS` and `_DEVBIN_BUILTIN_COMMANDS` sat in `lib/resolve` through WP-04 as placeholders so D11 activation could be tested before any built-in existed; WP-08 moved them. `tests/unit/builtins.bats` greps `lib/resolve` for a reintroduced copy, because two tables describing the same built-ins drift the moment one gains an entry.
- `lib/cmd/check` and `lib/cmd/test` are shims. The shared body is `lib/gatecmd`: both commands take an option, find its command line, and run it through the sealed-gate runner, and writing that twice would be the duplication this project exists to remove. A built-in option with real logic rather than a command line is marked `@builtin` in the catalogue and resolves to a `builtin_<command>_<option>` function the shim defines.
