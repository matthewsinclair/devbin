# Devbin usage rules

The terse DO / NEVER contract for working in this repository. `AGENTS.md` is the full brief.

## Rules of the road

- **DO** keep one implementation per concern (`IN-AG-HIGHLANDER-001`); search for an existing one before creating anything.
- **DO** keep the core pure; put I/O, time and external calls in the boundary coordinators (`IN-AG-PFIC-001`).
- **DO** keep coordinators to parse -> call -> render (`IN-AG-THIN-COORD-001`): `bin/devbin` decides nothing, `lib/resolve` does.
- **DO** surface every failure (`IN-AG-NO-SILENT-001`); never rescue and swallow.

## Shell

- **DO** require bash >= 5; the dispatcher refuses older (macOS `/bin/bash` 3.2 included) with a `brew install bash` remediation. Keep the guard block itself parseable by bash 3.2.
- **DO** leave existing 3.2 idioms (guarded array expansion, case over associative array) alone; modernise opportunistically, never in bulk.
- **NEVER** use `${var//pat/repl}` when the replacement may contain `&` unless you mean the matched text: 5.2 reads `&` as the match, 5.0/5.1 literally. Split on the literal placeholder instead (`_subst` in `lib/cmd/new`).
- **NEVER** use an unquoted heredoc delimiter (`<<EOF`) when the body can contain backticks or `$(...)`; quote it (`<<'EOF'`). The unquoted form runs each span and silently substitutes its output.
- **DO** end every list-producing function with an explicit `return 0`; a trailing loop or conditional returns its own status.
- **DO** follow an `exec` at the end of a function with a `die`.
- **DO** split a possibly-empty leading field with `${line%%<TAB>*}`, never `IFS=$'\t' read` (TAB is IFS whitespace and is stripped).
- **NEVER** use `/bin/true` in a fixture (absent on macOS); use bare `true`.
- **NEVER** use `sed -i` (not portable) or `$$` for uniqueness (inherited by subshells).
- **NEVER** begin a comment line with the word `shellcheck`; it parses as a directive (SC1072/SC1073).
- **DO** put `set -euo pipefail` at the top of every executable script.

## Config and the declarative boundary

- **NEVER** `eval` anything from config. `run:` is split into words by `run_words`, each word a glob matched where the command runs.
- **NEVER** let the YAML grow control flow; a declaration that needs an `if` is a script.
- **DO** name FACTS in config and keep RECIPES in the library (`version_from` names a file; the library reads it). No project config contains a regular expression.
- **NEVER** add a second config reader or a `yq` dependency: one awk pass, no dependencies.
- **DO** put config AHEAD of anything devbin ships, at every level.
- **DO** add a schema path in `_cfg_path_known` for every key a reader consults; validation must never reject correct config.

## The seam

- **DO** treat `bin/devbin` plus everything under `bin/.devbin/lib/` as devbin's, replaced wholesale.
- **NEVER** write `config.yaml`, `cmd/` or `help/` from install or upgrade; they are the project's.
- **DO** enumerate devbin's half only through `vendored_paths`; there is no second list.
- **NEVER** name, in anything `vendored_paths` lists, a project that uses devbin, a person or session, another repository's issue or CI run, any commit, or a machine-local path. State lessons generically and use the placeholder project `demo`. devbin's own issue numbers and the owner's copyright line stay.
- **NEVER** keep a list of devbin's consumers, in its runtime or its tests. `tests/unit/neutral.bats` refuses by shape; a name in prose, the manifest, git history and a phrase split across two lines are review's to catch.
- **DO** ask `vendor` whether a tree is level with its SOURCE and `doctor` whether it is level with what was INSTALLED; a green from one says nothing about the other.
- **NEVER** read convergence from `upgrade`'s exit status (it stays 0 over refused files); `vendor`'s status answers "is this level".
- **DO** ask the dirty question of devbin's half, never of the whole tree; `source_commit_of` stamps the vendored bytes.
- **NEVER** shadow a built-in command when an `options:` row would express the difference; a shadow displaces the whole built-in option set. Declare the verb under `commands.<cmd>.options.<verb>` with `run:`, pointing at a project script for real logic.
- **DO** read `doctor`'s `SUPPORTED overrides` note as a question, not a clearance.
- **NEVER** build a `git status` pathspec from a `find`-derived file list (a deleted, uncommitted file drops out and reads clean); point it at the directory.
- **NEVER** `--no-verify` a consumer's safety gate to land a vendor sweep: revert that project's seam, fix devbin, re-sweep. A consumer guard that refuses a vendored documentation example is right.

## Gates and false greens

- **DO** treat a false green as worse than a failure.
- **DO** make a gate that examines nothing FAIL (`check format` fails without its tool; `fmt` skips).
- **DO** report how many checks ran when a command's job is checking; fail a run that checked nothing.
- **DO** ask of every success path what it actually verified; two correct steps can compose into a false green.
- **DO** exit 1 from a bare command that needs an option; `-h` still exits 0.
- **DO** honour the exit codes in the one table in `docs/authoring-commands.md` ("Exit codes are a contract"); a new refusal takes a NEW code. **NEVER** list them anywhere else.
- **DO** read BOTH halves of a seal: `.errors` is the VERDICT, `.out` is the SCOPE. `[ -s .errors ]` answers "did anything fail", never "was anything examined".
- **NEVER** read a non-empty `.errors` as a failure without `seal_is_inflight`; a seal holds the in-flight marker for the whole run.
- **NEVER** write devbin's own annotations into a run log untagged; prefix them with `_DEVBIN_INVOKE_TAG` so `write_errors_file` strips them.
- **NEVER** assume a green gate examined anything. `check critic` defaults to `--staged` and examines nothing where nothing is staged; `run_gate` promotes a zero-count run to FAILED only for a grammar with a COUNTER, and `grammar: generic` has none.

## The launcher

- **DO** invoke devbin as `bin/devbin` in every project.
- **NEVER** create `bin/<project>` as a symlink to devbin (retired; it shadows the project's own binary). A `bin/<alias>` pointing direct at `devbin` is a permitted project choice; devbin creates neither.
- **DO** use `DEVBIN_NAME` for the project's IDENTITY and `DEVBIN_INVOKE` for what you TYPE.
- **DO** set `DEVBIN_SOURCE` to a devbin checkout when bootstrapping a project that has no devbin yet; `dvb` otherwise walks up from `$PWD` and finally falls back to the machine install. Through the fallback only `install`, `shell-init` and the version queries run.
- **NEVER** reimplement the cwd guard's exemption list in the shell function.
- **DO** install the shortcut with `eval "$(bin/devbin shell-init zsh)"` (or `bash`) in your shell config, never in a project. **NEVER** hand-copy the function body.

## Development posture

- **DO** move every dependency, in every language, to its latest build and fix forward.
- **DO** consolidate: one mechanism per question, even when two both work.
- **DO** run `bin/devbin clean <lang>` before a release build.
- **DO** record what a dependency bump MOVED: diff `name@version` against the union of every prior lock (`comm -13`), read as a changelog, not a gate.
- **DO** look for what "latest" does not cover: DROPPED packages and major-version jumps.
- **DO** convert before you sweep: a workspace conversion moves build output to `<root>/target/`, which inherits no Spotlight exclusion marker.

## Destructive commands

- **DO** REFUSE when the action cannot be proved safe; "warn and proceed" is not cautious.
- **DO** classify a build tree by REBUILDABILITY (a sibling manifest), never by shape or name.
- **DO** print every rejection with its reason and size.
- **NEVER** protect a directory by NAME; key on what PATH actually resolves through.
- **NEVER** raise a refusal inside `< <(...)` or `$(...)`; validate once in the calling shell before scanning.
- **DO** read confirmation from `/dev/tty`, not stdin, and refuse outright when there is no tty.

## Tests

- **DO** ask what ELSE would make a test green, and what else would make it red.
- **DO** see a new test go red against a deliberately broken input before accepting it.
- **DO** prove a mutant APPLIED (print the changed line and neighbours), PARSES (`bash -n`) and that its target arm is among the reds before reading its result.
- **DO** add `helpers.bats` and `contract.bats` to every targeted run; their tree scans are picked up by no command selection.
- **NEVER** pass `--` to `assert_output_contains`, `refute_output_contains` or the `_matches` pair; it becomes the pattern.
- **NEVER** put backticks or `$(...)` in a test name; bats evaluates every description.
- **NEVER** read a test run by grepping `^ok` / `^not ok`; `grep -vE "^(ok |not ok |1\.\.|#)"` should print nothing.
- **NEVER** run `cfg_load` or `cfg_load_string` in a subshell (incl `run cfg_load`); it reads as an absent config.
- **DO** build a test's condition from the catalogue, never from whichever built-in is unimplemented today.
- **DO** check a `.bats` filename is free before creating one.
- **DO** install fixtures through the real installer.
- **DO** smoke-test these libraries with `bash <<'SH'`, never bare zsh.
- **NEVER** take the agent shell's `grep` (an embedded ugrep that honours `.gitignore` and refuses some patterns) as a census or a negative; use `/usr/bin/grep` or `git grep` and print the status beside every zero.

## Documentation

- **NEVER** put done work in the work-in-progress document; it is DOING and TODO only. Restart briefs carry what the next session needs to ACT.
- **DO** tie a document to something the suite trusts (`tests/unit/documentation.bats`).
- **DO** give every extractor in a docs test a floor; an empty parse makes every comparison pass.
- **NEVER** point `fmt md` at `docs/` or `intent/`; prettier strips table alignment.
- **DO** land a ratified decision in the document it changes.
- **DO** read a work package's deliverables against what has landed since before starting it.
- **NEVER** manually wrap `.md` files. Column-align every table. ASCII only: `--` and `->`, never em dashes or `e.g.`.

## Git

- **NEVER** use branches: quiesce, install alongside, prove equivalence, delete last.
- **NEVER** add AI attribution to a commit.
- **DO** end a commit message with `(C) hello@matthewsinclair.com`.
- **DO** qualify another project's issue as lowercase `<project>#NNNN` (eg `intent#0054`); a bare number is for same-repo references only.
