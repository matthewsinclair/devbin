# ARCHITECTURE-shell.md

The as-built shape of Devbin's shell code.

## The shape

Devbin is one dispatcher plus a runtime library, installed into a project beside the project's own configuration and handlers.

```
bin/devbin                    the dispatcher -- a thin coordinator
bin/<alias> -> devbin         optional per-project shortcut; devbin creates none; `doctor` checks where it points
bin/<project> -> devbin       retired; devbin creates none; `doctor` notes a survivor
bin/.devbin/config.yaml       the project's declaration
bin/.devbin/cmd/<name>        project handlers, auto-discovered
bin/.devbin/cmd/<name>.d/     sub-handlers, resolved by the same rule
bin/.devbin/cmd/doctor.d/     project checks `doctor` runs after its own
bin/.devbin/help/<cmd>.md     authored help, per project
bin/.devbin/lib/              the runtime, installed
lib/                          the runtime, in this repo
lib/cmd/<name>                built-in command handlers
lib/cmd/<name>.d/<word>       built-in sub-handlers (eg `infra.d/`)
lib/pages/<cmd>.md            devbin's help for its built-ins, shipped with the runtime
lib/tmpl/                     what `new` scaffolds
tests/unit/*.bats             one file per concern
tests/lib/*.bash              fixtures and assertions (`test_helper.bash` and companions)
```

## The runtime layers

Read it as a stack: nothing depends upwards.

| File            | Depends on                                          | Owns                                                                                                                                                                                                                                  |
| --------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `helpers`       | nothing                                             | primitives: `die`, `warn`, `abs_path`, `read_version`, `sha256_files`, `run_words`; the bash floor                                                                                                                                    |
| `builtins`      | `helpers`                                           | THE catalogue: data plus its readers, no side effects; refuses to load without `helpers`                                                                                                                                              |
| `runlog`        | `helpers`                                           | the sealed-gate subsystem and its extraction grammars                                                                                                                                                                                 |
| `config`        | `helpers`                                           | one awk pass over YAML, a cached flat table, schema validation                                                                                                                                                                        |
| `install`       | `helpers`; `config` for `install_prefix_configured` | the vendored file set, the checksum manifest, version constraints                                                                                                                                                                     |
| `resolve`       | `helpers` `builtins` `config` `runlog`              | resolution, activation, `all`, shared options                                                                                                                                                                                         |
| `help`          | `resolve` (and so all of the above)                 | the generated listing, authored topics, `--why`                                                                                                                                                                                       |
| `gatecmd`       | `helpers` `builtins` `runlog`                       | the shared body of every built-in gate command                                                                                                                                                                                        |
| `infra`         | `helpers` `config`                                  | the infra profile: search order, load, parse-time validation                                                                                                                                                                          |
| `infra.dns`     | `helpers`                                           | authoritative DNS reads for `infra check` and `infra init`                                                                                                                                                                            |
| `infra.check`   | `infra` `infra.dns` `config`                        | the DNS and mail legs of `infra check`                                                                                                                                                                                                |
| `infra.init`    | `helpers` `infra.dns`                               | `infra init`: measure a live estate and propose a profile                                                                                                                                                                             |
| `release.notes` | `helpers`                                           | the notes providers and their verbs; reads no config, is passed its facts                                                                                                                                                             |
| `release.steps` | `helpers` `release.notes`                           | the release core's postcondition readers and its remote and gh calls; reads no config                                                                                                                                                 |
| `release.legs`  | `helpers` `runlog`                                  | the release core's remote legs: R onto a test host by git send-pack, its gates run there detached, the seal pair copied back and read by `seal_verdict`; reads no config                                                              |
| `cmd/<name>`    | `helpers` or `gatecmd`, plus what its concern needs | one built-in command; eg `release` sources `config`, `runlog`, `resolve`, `release.notes` and `release.steps`; `infra` sources `config` and the `infra*` files; `install` sources `config` and `install`; `upgrade` sources `install` |
| `tmpl/*`        | nothing (data)                                      | what `new` scaffolds; `tmpl/handler` must itself parse as bash                                                                                                                                                                        |

- `lib/helpers` has no dependencies, by rule: handlers are separate processes that source it alone. Needs config, belongs in `resolve`; needs nothing, belongs in `helpers`.
- `lib/install` sits beside `config`, not on it: install, upgrade and doctor act on a project other than the one whose config is loaded, so everything it needs about a tree is passed in or read off that tree. The one exception is `install_prefix_configured`, which reads `install.prefix` (devbin's own config) with `cfg_get`; its callers (`install`, `shell-init`, `use`) source `lib/config` first.
- `lib/infra` sits ON `config`: it reads a profile through the one YAML reader and adds no parser. The profile schema follows `lib/config`'s limits (no dotted keys, flow collections or sequences of maps), so domains are keyed by a handle with the FQDN as a field.
- A key with no value produces no cache row, so `lib/infra` carries one raw scan that asks only "was this key written" of one block's child keys, and refuses anything invisible. It reads no types, values, nesting or merging.

## Handlers are separate processes

A handler is `exec`'d, not sourced, so:

- **The environment is what crosses**: `DEVBIN_NAME`, `DEVBIN_INVOKE`, `PROJECT_ROOT`, `<NAME>_ROOT`, `DEVBIN_LIB`, `DEVBIN_COMMAND`, `DEVBIN_VERSION_FILE`, `DEVBIN_LANGUAGES`, the run identity (`DEVBIN_RUN_ID`, `DEVBIN_RUN_STAMP`), the shared options, and `DEVBIN_OPT_*` for framework-owned ones. A project handler never needs to read config. A built-in whose concern is the config (eg `doctor`, `release`, `infra`, `install`, `fullcycle`, `dormancy`) sources `lib/config` and calls `cfg_load` in its own process.
- **Shared options are parsed once**, in the dispatcher, and exported.
- **The seal ledger is a file**, so `all` can collect failures across processes.

## Resolution order

The same order at command and option level, at every depth:

1. a **project handler** -- shadows totally, option set and all
2. config's own **`run:`** -- at command level it shadows totally too
3. devbin's own **`lib/cmd/<name>`**
4. the **catalogue's** default command line
5. otherwise the refusal, exit 3, naming what would run it (`unrunnable_why`)

Config's `run:` comes before devbin's handler so a built-in never swallows what config declared.

Each level's order is stated once, in `lib/resolve`, and the code that runs acts on it:

- `arg_route` -- the dispatcher's, for an argument list: `all` (over the options there are; refused over a command-level `run:` with none), a declared option, a deactivated one, the project's handler, then `run_command`.
- `option_run_tier` -- `run_option`'s; `command_tier` -- `run_command`'s.
- `option_leaf` -- follows a route to what runs at its end; `help` and `check`'s fmt arms read it, so neither can describe a run the dispatcher does not make.
- `_run_line` -- the one runner for every config and catalogue command line, sealed or bare.
- `project_owns_command` -- the one predicate for project ownership (a handler, mapped or not, or a command-level `run:`); ownership displaces the built-in option set.

**`all`**: devbin sweeps it where there are options. Over no options a project handler or built-in receives `all` as an ordinary word. Over a command-level `run:` with no options, `run_all` refuses, exit 1, naming the bare command, since appending `all` to the line would make a new command.

Sub-dispatch descends `<handler>.d/<word>` by the same test, at any depth. A word with no handler behind it stops the descent and becomes an argument (so `db sql "select 1"` works).

## Help

- `devbin help` is generated from `known_commands`, so it cannot list what does not resolve or omit what does; tests assert both directions.
- `devbin help <cmd>` is authored markdown from two roots, the project's first: `bin/.devbin/help/<cmd>.md`, then devbin's `lib/pages/<cmd>.md`. Devbin's page answers only where the project does not own the command (`project_owns_command`). Sub-topics sit at `<cmd>.d/<sub>.md` under either root, descending by the handler rule; the first root whose walk ends on a file answers. A shipped page is followed by the command's `--why` block and the options not offered here; a project's page stands alone. No page means a generated answer (summary, usage, options, provenance).
- Three description fields each have ONE source, read config -> the resolving handler's `# devbin: <field> =` header -> the catalogue. Devbin's commands are declared by catalogue rows, so `lib/cmd/*` carry no header; a test enforces it.
- `devbin help --why` annotates each command with where it resolved from and names everything devbin ships that is not offered here, with the reason.

## Install, the seam and the manifest

- `bin/devbin` plus everything under `bin/.devbin/lib/` is **devbin's**, replaced wholesale. `config.yaml`, `cmd/` and `help/` are the **project's**; no function in `lib/install` writes them.
- `vendored_paths` is the only enumeration of devbin's half; install, upgrade, doctor and the manifest all read it. `vendored_scope` names the same half as directories, for the one caller that needs a git pathspec (a pathspec built from the file list is read against disk and misses a deleted, uncommitted file).
- `manifest.sha256` checksums every vendored file and lives beside `lib/`, not inside it, so it survives the replacement. A file whose checksum moved was edited in place: upgrade reports it, refuses it and leaves it alone. Refused paths carry their install-time checksum forward into the rewritten manifest.
- `doctor` is the checker. Its output includes the count of checks run, and a run that checked nothing fails. Three outcomes: FAILURE (broken), NOTE (true and worth saying), pass.

## The machine install

Projects vendor from a **machine install**, not from devbin's working tree. Inside devbin's own tree `install` and `upgrade` act on the install; everywhere else they mean what they always did; each announces its mode before writing.

- The install is consumer-shaped with the project half missing: `bin/devbin`, `bin/.devbin/lib/` and the ordinary manifest, so `is_devbin_source`, `vendored_paths`, `copy_vendored`, `manifest_write` and `upgrade --from` apply unchanged. With no `config.yaml`, `bin/devbin` refuses to start there, so an install is only ever a `--from`. The manifest's `kind: install` header says so explicitly.
- Publishing refuses a dirty tree; there is no `--force`.
- `source_commit_of` forwards an install's own stamp, so provenance is transitive.
- Checks that would ask git of the source ask what the source is: the update notice reads `_devbin_source_head`; `source_direction` (the warning that upgrading would revert the runtime) uses `install_direction`, which looks a consumer's commit up in the `ancestry` lines a publish writes into the install's manifest. A commit the install never held stays `unknown`, and upgrade says so when bytes would change.

## Activation

A built-in is offered when the catalogue's language column says so:

- `any` -- always, unless the tree lacks what the option needs (`_DEVBIN_BUILTIN_NEEDS`; eg `check critic` and `docs agents` need `intent/`)
- a language name -- when `project.languages` declares it
- `opt-in` -- only when the project sets `enabled: true`

`enabled: false` wins over everything. A project handler activates a command by its presence alone.

## The declarative boundary

- `run:` is expanded by `run_words` (`lib/helpers`), never `eval`'d: word splitting and globbing, no quotes, substitutions or redirections. A command line needing an argument with spaces needs a handler.
- Config names **facts**; the library holds **recipes**. `version_from` and `version_sidecars` name files; the library knows how to read and rewrite each kind. No project config contains a regular expression.

## Sealed gates

- A gate writes `tmp/<command>/<stamp>.<SUFFIX>.{out,errors}`. `log:` is what makes an option or command a gate; without it, it runs bare (right for a launcher).
- Log creation is atomic (`set -o noclobber`).
- **`.errors` is the VERDICT**: empty exactly when a completed run was green.
- **`.out` is the SCOPE**: any determinate fact ("N file(s) examined", "nothing staged") plus the invocation devbin recorded before the tool started. A verdict read without its scope cannot tell "examined everything" from "examined nothing".
- `open_run_log` seeds `.errors` with the in-flight marker before the tool starts, so it is non-empty for the whole run; `seal_is_inflight` tells the two apart.
- `run_gate` promotes a counted run that executed nothing to FAILED unless `--allow-empty` is given. `grammar: generic` declares no counter, so a generic gate's scope lives only in its `.out`.
- Devbin's own annotations in a run log carry `_DEVBIN_INVOKE_TAG`, and `write_errors_file` strips them before extraction.
- A gate that examines nothing must fail: `check format` fails when its tool is missing, while `fmt` skips.

## The bash floor

- Devbin requires bash >= 5. The check sits at the top of `lib/helpers`, ahead of its load guard, so the dispatcher and every built-in handler refuse on their own interpreter with a `brew install bash` remediation. The dispatcher also checks the bash PATH resolves, since `#!/usr/bin/env bash` handlers run on that one. A project handler that sources nothing from devbin is covered only when dispatched.
- The guard block stays parseable by bash 3.2.
- `lib/helpers` sets `shopt -s inherit_errexit`, unguarded, below the floor check.
- `doctor` asserts the floor as a check; CI's macOS job proves the refusal against the real `/bin/bash` 3.2.
- 3.2-era idioms remain and are correct; they are modernised opportunistically, not in bulk. Under `set -u` 3.2 aborted on an empty `"${arr[@]}"`, hence guarded expansion:

```bash
set -- "${DEVBIN_ARGS[@]+"${DEVBIN_ARGS[@]}"}"
```

- TAB is IFS whitespace: `IFS=$'\t' read -r a b` strips a leading tab, so a possibly-empty first field is split with `${line%%<TAB>*}`.
- `/bin/true` does not exist on macOS; fixtures use bare `true`.
- The trap the floor does not retire: bash 5.2 made `&` in the replacement of `${var//pat/repl}` mean the matched text; 5.0 and 5.1 take it literally. Escaping fixes one and breaks the other, and `sed`/`awk` share the `&` problem. Split on the literal placeholder (`${text%%"$pat"*}`, `${text#*"$pat"}`), as `_subst` in `lib/cmd/new` does.

```
v="x {{N}} y";  echo "${v//\{\{N\}\}/a & b}"
  bash 5.0/5.1 ->  x a & b y
  bash 5.2     ->  x a {{N}} b y
```

## Error handling

- `set -euo pipefail` at the top of every executable script.
- `die` prints to stderr and exits; `warn` prints and returns. Nothing rescues and swallows.
- Every list-producing function ends with an explicit `return 0`: a trailing loop or conditional returns its own status, which kills an `errexit` caller.
- An `exec` at the end of a function is followed by a `die`.
- Exit codes are a contract, enumerated only in the "Exit codes are a contract" table in `docs/authoring-commands.md`, which `tests/unit/documentation.bats` holds to the source.
- A bare command that needs an option exits 1 after printing its usage; `-h`/`--help` exits 0.
- `|| true` only for genuinely benign failures, with a comment saying why.

## Testing

- BATS, one `.bats` file per concern under `tests/unit/`; shared fixtures and assertions under `tests/lib/`; every test runs in a temporary directory.
- The config cache is a shell variable, so `cfg_load` never runs in a subshell (`run cfg_load`, piping into `cfg_load_string`); both read as an absent config.
- The agent's shell tool is zsh, where `PIPESTATUS` reads empty; smoke-test these libraries with `bash <<'SH'`.

## Build / CI

- Devbin uses devbin: CI runs `bin/devbin test all`, so a defect in the dispatcher or the sealed-gate subsystem breaks Devbin's own build first.
- Ubuntu and macOS jobs each run `test all`, then the `check` options by name rather than `check all`: every active option except `critic` (runs Intent, which CI's Ubuntu and macOS runners do not install) and `lint` (already run by the suite's full-tree lint test). `tests/unit/ci-workflow.bats` holds each job's list equal to `check`'s active options minus those two. The critic runs in the commit gate instead.
- A comment line beginning with the word `shellcheck` is parsed as a directive; SC1072/SC1073 then fire on the prose.
