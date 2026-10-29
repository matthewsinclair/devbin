# Configuration reference

Every key devbin reads from `bin/.devbin/config.yaml`, with its type and its default.

This page is the **index**: what exists, what it means, what happens if you leave it out. A fully annotated worked example, with the reasoning behind each choice, is vendored into your own project at `bin/.devbin/lib/config.reference.yaml` -- read that one when you want the argument, this one when you want the answer.

Only **`project.name`** is required. Everything else has a default or is simply absent.

A test holds this page to the schema: every key the validator accepts must appear here, and every key here must be one the validator accepts. The two cannot drift apart without the suite going red.

## The grammar

Config is YAML, but a **restricted subset**, and the restriction is enforced rather than assumed. A file outside the subset is refused with the file and the line, not half-read.

| Supported                           | Refused                         |
| ----------------------------------- | ------------------------------- |
| two-space indent                    | tabs, odd indent, jumped indent |
| nested maps, `key: value`           | duplicate keys                  |
| scalar sequences (`- item`)         | sequences of maps               |
| `#` comments, whole-line and inline | anchors and aliases (`&`, `*`)  |
| quoted scalars, blank lines, `---`  | block scalars                   |
|                                     | flow collections (`{`, `[`)     |

**Unknown keys are an error, not a warning.** A misspelled `sumary:` that is quietly ignored presents much later as "my help text does not appear", in a place that gives no hint about the typo.

**A boolean key takes `true`, `yes` or `1`, or `false`, `no` or `0`, and nothing else** (issue 0080). Those are the words devbin reads a yes or a no from, and `doctor` fails on any other value, naming the key and the value. **Run `doctor` after editing config: the command you run does not validate it** -- the `release` verbs are the one exception, and validate the whole file before they read their block. `enabled: off` is neither word, so a built-in stays active and an opt-in stays off, and only `doctor` says so -- the same as a misspelled key. `log:` and `options.<name>.value` are not boolean keys, and take other words.

The subset exists because there is exactly one reader -- a single awk pass, no `yq`, no dependency -- and because keeping every project's config in the same shape is worth more than admitting YAML nobody should be writing by hand.

## `project`

Who this project is. The only required section.

| Key                        | Type            | Default                    | What it is                                                                                     |
| -------------------------- | --------------- | -------------------------- | ---------------------------------------------------------------------------------------------- |
| `project.name`             | string          | **required**               | display name in help, prefix on `die` and `warn` output                                        |
| `project.alias`            | string          | none                       | a short project name, `dm` for demo; recorded only, no symlink is made                         |
| `project.cli_task`         | mix task name   | `<name>.cli`               | the task `cli` and `repl` call; set it where the task is not named after the project           |
| `project.root_var`         | env var name    | `<NAME>_ROOT`, upper-cased | variable carrying the project root, exported for handlers                                      |
| `project.version_from`     | path            | `VERSION`                  | the file the project version is read from                                                      |
| `project.referent`         | shell command   | none                       | run once per invocation; its stdout is printed verbatim as `measured: <answer>`                |
| `project.version_sidecars` | list of paths   | none                       | files that **mirror** the version; `version set`, `bump` and `sync` write each                 |
| `project.languages`        | list of strings | none                       | **gate scope**, the languages devbin offers gates for here; drives which built-ins are offered |
| `project.cargo_root`       | path            | the project root           | the directory holding the cargo workspace's `Cargo.toml`, where devbin runs its cargo lines    |

`root_var` is exported under the project's own name so handlers ported from elsewhere keep reading the variable they expect, and its name is exported beside it as `DEVBIN_ROOT_VAR`, so a reader that must point it somewhere else never re-derives the default. A root variable must be a shell variable name, and may not take a name the shell needs (`PATH`, `IFS`, `HOME` and the like) or one devbin's own environment uses, `DEVBIN_ROOT_VAR` included (issue 0081).

`cargo_root` is for a project whose cargo workspace sits below its root, eg `cargo_root: native` (issue 0225). devbin runs its catalogue's cargo lines there: `fmt rust`, the rust arm of `check format`, `check clippy`, `test rust`, and `dormancy`'s legs. Each seal's invocation block then names the directory in an `at:` line, which it writes only for a run away from the project root. `check targetdir` takes the shared tree to be the `target` beside that `Cargo.toml`. A project's own `run:` for any of these still runs at the project root, as every `run:` does. The value is relative to the project root, and one naming no directory, or a directory holding no `Cargo.toml`, is refused, naming the path: by `bin/devbin doctor`'s config check, and by each cargo line before cargo runs. With the key absent, every one of these runs at the project root.

`cli_task` exists because two projects broke the `<name>.cli` derivation the first projects all ride: `<family>_cli` declares `Mix.Tasks.<Family>.Cli` (`mix <family>.cli`) and `<family>_config` declares `mix <family>.config`. For `cli` alone a `commands.cli.run:` override would do. `repl` is why this is config instead: its built-in carries the rlwrap history and completions wiring, and overriding the command line to change one word throws all of that away. A difference of one **name** should not cost a project the handler.

`referent` names a **command**, and devbin never parses its answer. It is `eval`'d once per invocation from the project root, with its stderr discarded and `GIT_OPTIONAL_LOCKS=0` in its environment (issue 0094): a referent is a read, and a `git status` in one otherwise takes git's optional index lock on every devbin command. A referent that sets `GIT_OPTIONAL_LOCKS=1` itself gets the lock back, and the setting never reaches a gate. Whatever it prints is echoed verbatim beneath every verdict as `measured: <answer>`, and written into each sealed log. devbin cannot tell a commit sha from a hostname from a build number, and keeping it that way is the whole design: the project knows what identifies one of its runs, devbin knows only that a reader needs to see it. It exists because a human reading `FAILED: rust` in a summary had no way to know which tree it described. A declared referent that fails or prints nothing reports `REFERENT UNAVAILABLE` rather than falling silent -- an unlabelled verdict and a broken labeller must not look alike.

`version_from` and `version_sidecars` name **files only**, never how to parse or rewrite them. Devbin knows the recipe for a `VERSION`, a `mix.exs`, a `Cargo.toml`, a `package.json` and an `Info.plist`. That split is deliberate: the config states a fact about the project, the library holds the recipe, and no project's config ever contains a regular expression.

A sidecar of any other kind is treated as a **bare version file** -- one whose entire contents are the version -- and devbin checks that this is true before writing. A file holding anything else is refused by name, because the only way to write a version into a file you have no recipe for is to overwrite the whole thing. A `Cargo.lock` declared as a sidecar is refused for exactly this reason; sync it from the project's own command instead. Nothing is written when a sidecar is refused -- every declared file is checked before any file is touched, and the version file is written last -- so fixing the config and re-running is always clean.

An **empty** bare sidecar is legal: a freshly-created file has nothing to destroy, so `version sync` fills it, and `version check` reports it as ordinary drift healed by that sync rather than as unreadable. The bare-content check applies to **sidecars only** -- the file `version_from` names is read verbatim, because that declaration makes its whole content the version by definition.

`languages` is the activation axis. Every language-scoped built-in option declares the language it belongs to and is offered exactly when that language is declared here; one scoped to `any` is offered whatever this list says, unless the tree lacks what it needs: `check critic` and `docs agents` need an `intent/` directory. It is gate scope, not project composition: it need not match Intent's own `languages` in `intent/.config/config.json` (a project may have Swift source and arm no Swift gate), and the one gate that reads Intent's list instead is `check critic`, which reviews each language Intent declares. This is why `test mix` does not exist in a shell project and `test shell` does not exist in an Elixir one -- neither has to be switched off by hand, and a built-in added to devbin later cannot appear uninvited in a project whose language it does not match.

Recognised languages: `elixir`, `rust`, `swift`, `lua`, `shell`.

```yaml
project:
  name: demo
  alias: dm
  version_from: VERSION
  version_sidecars:
    - native/cli/Cargo.toml
    - native/macos/App/Info.plist
  languages:
    - elixir
    - rust
```

## `devbin_version`

| Key              | Type       | Default | What it is                                            |
| ---------------- | ---------- | ------- | ----------------------------------------------------- |
| `devbin_version` | constraint | none    | the devbin this project expects, enforced by `doctor` |

The forms:

| Form      | Means                      |
| --------- | -------------------------- |
| `^X.Y.Z`  | same major, at least X.Y.Z |
| `>=X.Y.Z` | at least X.Y.Z, any major  |
| `X.Y.Z`   | exactly                    |

Omit it and any runtime satisfies the project. The version compared against is the one stamped into `bin/.devbin/manifest.sha256` by install and rewritten by every upgrade, so it describes what is actually vendored rather than what someone meant to vendor.

Note that `^` on a `0.x` version admits `0.5.0` for a declared `^0.4.0`, which is not what semver's own text says. (The example names a version devbin is not, on purpose: devbin's own version lives in `VERSION` and nowhere else, and an example equal to it reads as a claim about it.) Pre-1.0 devbin makes no stability promise either way, and the strict reading pins every project to a patch series and makes `upgrade` a lie.

## `install`

| Key              | Type   | Default                     | What it is                                                    |
| ---------------- | ------ | --------------------------- | ------------------------------------------------------------- |
| `install.prefix` | string | none -- required to publish | where `devbin install` publishes to, inside devbin's OWN tree |

**There is no default, and that is deliberate.** `lib/install` once carried a path under `$HOME` -- one operator's directory layout, written into the runtime every project vendors. A publish from any of them would have gone to a path named after somebody else's home directory and would have SUCCEEDED, because a publish to the wrong place is indistinguishable from a publish to the right one. `install` and `devbin use opt` now refuse by name when the key is unset, and `install` takes `--prefix <dir>` for a single run.

**This key is the maintainer's: it names the opt tier of a dev checkout** (the README's [For the maintainer of a dev checkout](../README.md#for-the-maintainer-of-a-dev-checkout)). A user installs devbin from brew and never sets it. **Only devbin's own configuration has any use for this key.** Set it in a consuming project and the one thing that reads it there is `shell-init`, which writes it into `dvb` as the machine-install fallback -- that project is otherwise describing a publish it will never perform.

Inside devbin's source tree, `install` acts on the opt install rather than on a project (ST0005): it publishes a new one, replaces an existing one only with `--force`, the one re-publish route, and refuses outright when the source tree is dirty; `upgrade` there publishes nothing and names `install --force` (issue 0213). Consumers then vendor from that install rather than from the working tree devbin is edited in, which is what stops an uncommitted change reaching a project.

`--prefix <dir>` overrides the configured value for one run. A leading `~/` is expanded; without that, a config value being a literal string would create a directory actually named `~`.

## `help`

The wording around the generated listing. There is no command list here, or anywhere else -- `devbin help` is derived from what actually resolves.

| Key             | Type            | Default        | What it is                                      |
| --------------- | --------------- | -------------- | ----------------------------------------------- |
| `help.tagline`  | string          | `dev launcher` | completes the first line: `<name> -- <tagline>` |
| `help.preamble` | string          | none           | shown above the listing                         |
| `help.groups`   | list of strings | first-seen     | display order of group headings                 |

`preamble` exists for the disambiguation note the source projects all needed in one form or another -- the launcher is not the product:

```yaml
help:
  tagline: "unified dev launcher for the Demo project"
  preamble: "NOT the product. `demo` (native/cli) is what users install; this drives development of it."
  groups:
    - Surfaces
    - Build
    - Test (SEALED gates -- the verdict is a FILE, not a scroll-past)
    - Check
    - Ship
```

A group named in `groups` with nothing in it prints no heading, so listing a group you have not populated yet is harmless. Groups **not** named are appended in first-seen order.

An entry may carry a parenthetical annotation, as `Test (SEALED gates ...)` does above. It is printed as part of the heading, while commands still match on the name before the first ` (`. That is how an authored note doing real work survives into a generated listing, given that a sequence of maps -- the obvious way to carry a name and a note separately -- is outside the subset.

## `options`

Shared options: flags and values parsed **before** the handler runs, in both spellings (`--env test` and `--env=test`), and exported so the handler -- a separate process -- sees them.

An option **not** declared here passes straight through to the handler untouched, which is what lets `devbin test mix --trace` reach `mix`.

| Key                       | Type            | Default          | What it is                                                                                                          |
| ------------------------- | --------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| `options.<name>.export`   | env var name    | **required**     | the variable the parsed value is exported as; a framework-owned option (`iex`) has devbin's own name and needs none |
| `options.<name>.flag`     | boolean         | `false`          | takes no value                                                                                                      |
| `options.<name>.value`    | string          | `true`           | what a flag exports when given                                                                                      |
| `options.<name>.values`   | list of strings | anything allowed | the accepted values; anything else is refused                                                                       |
| `options.<name>.summary`  | string          | none             | the description in help's shared-options block                                                                      |
| `options.<name>.commands` | list of strings | none             | more commands that read a framework-owned option, added to devbin's own; never replaces them                        |

```yaml
options:
  env:
    values:
      - dev
      - test
      - prod
    export: MIX_ENV
    summary: set MIX_ENV for this invocation
  json:
    flag: true
    value: json
    export: DEMO_STYLE
```

A value outside `values:` is refused, naming what was expected. Omit `values:` to accept anything.

An `export` name is held to the rule `project.root_var` is: when the option is parsed, a name that is not a shell variable name, that the shell needs, or that devbin exports to handlers itself is refused by name (issue 0081).

This section replaces what the source projects wrote as `_set_env`, `_set_bin` and `_set_fidelity` -- three copies of one function differing only in the answers, whose accepted-value lists had already drifted apart. A project adds `--fidelity` by declaring it, not by writing bash.

## `commands`

Enables and parameterises built-ins, and registers project handlers that need something said about them.

**Most commands need no entry at all.** A script dropped into `bin/.devbin/cmd/<name>` is picked up with nothing here. An entry is needed only to override a built-in, to configure one, to map a differently-named file to a command name, or to override wording.

### Command level

| Key                      | Type             | Default                        | What it is                                                        |
| ------------------------ | ---------------- | ------------------------------ | ----------------------------------------------------------------- |
| `commands.<cmd>.enabled` | boolean          | see below                      | offer this command, or switch it off                              |
| `commands.<cmd>.summary` | string           | handler header, then catalogue | the one-line description in help                                  |
| `commands.<cmd>.group`   | string           | handler header, then catalogue | the help heading it sits under                                    |
| `commands.<cmd>.args`    | string           | handler header, then none      | usage hint in help's left column, `server [--iex]`                |
| `commands.<cmd>.run`     | command line     | catalogue                      | what to run when the command takes no option                      |
| `commands.<cmd>.handler` | file name        | the command name               | the file in `cmd/` that provides this command                     |
| `commands.<cmd>.log`     | string or `true` | none                           | seal the verdict; names the `.out`/`.errors` suffix               |
| `commands.<cmd>.grammar` | grammar name     | none                           | which extractor reads the run's output                            |
| `commands.<cmd>.restore` | command line     | none                           | `fullcycle` only: what puts back the release artefacts it deletes |

`restore` is read by `fullcycle` and by nothing else. That verb is destructive -- `clean rust` removes `target/` including `release/`, and `cargo test` builds debug binaries only -- so on a machine where something on PATH resolves through `target/release/`, the cycle darkens it. The verb watches for exactly that and reports what it could not put back; with `restore` declared it puts it back first.

**Devbin will not guess the command, and that is a measurement rather than caution.** It shipped for one day running `cargo build --release` at the project root, which is correct on most cargo projects and is a new unguarded entrance on at least one: a project whose release path is guarded because several processes invoke the artefact, and where a build from a dirty tree poisons it for all of them. That project's own guard named the line on the first commit that carried it. `build release` is not a portable spelling either -- on that same project the arm is interactive and pushes, so guessing a verb by name would turn a restore into a publish.

Undeclared, the restore phase does not run and the cycle says so. That is the fail-closed direction, and it is the rule `fullcycle` already applies when a project declares no build verb at all: it refuses rather than proceeding without one.

`enabled` defaults differ by what the command is: a language-scoped built-in is offered when its language is declared, an opt-in built-in (`precommit`, `publish`, `macos`, `content`, `which`, `release`) is absent until set to `true` -- or until config gives it a `run:` or options of its own, or `cmd/` a handler of its name -- and a project handler is offered by existing. **`enabled: false` wins over everything**, including a project handler of the same name.

### Option level

| Key                                    | Type             | Default                            | What it is                                   |
| -------------------------------------- | ---------------- | ---------------------------------- | -------------------------------------------- |
| `commands.<cmd>.options.<opt>.run`     | command line     | catalogue                          | what this option runs                        |
| `commands.<cmd>.options.<opt>.summary` | string           | sub-handler header, then catalogue | the description in help                      |
| `commands.<cmd>.options.<opt>.args`    | string           | sub-handler header, then none      | usage hint                                   |
| `commands.<cmd>.options.<opt>.grammar` | grammar name     | catalogue                          | which extractor reads the output             |
| `commands.<cmd>.options.<opt>.log`     | string or `true` | catalogue                          | seal the verdict; names the suffix           |
| `commands.<cmd>.options.<opt>.in_all`  | boolean          | `true`, but `false` for `db reset` | include this option in the synthesised `all` |
| `commands.<cmd>.options.<opt>.enabled` | boolean          | see above                          | offer this option                            |

**`log:` is what makes an option a gate.** With it, the option runs through the sealed runner and writes `tmp/<command>/<stamp>.<SUFFIX>.{out,errors}`, where the `.errors` companion is empty exactly when that completed run was green. `log: true` names the pair after the option instead of restating it in upper case.

Without `log:` the option runs **bare**, and that is the right choice for a launcher rather than a gate. `server` and `iex` never exit, so teeing them would buffer the output you are watching and seal nothing.

**Overriding a catalogue gate keeps its seal unless you decline it.** A project that replaces a shipped gate's `run:` and says nothing about `log:` inherits the row's suffix and grammar, because pointing a gate at your own build is not asking it to stop sealing -- and an empty `log:` counts as saying nothing. To run it bare, decline explicitly with `log: "-"`, `false`, `no` or `0`. The same spellings mean "no seal" on a command-level `log:`.

`grammar` names one of the shipped extractors: `mix`, `credo`, `cargo`, `xcodebuild`, `lua`, `shell`, `bats`, `critic`, `generic`. `"-"`, devbin's "no default" sentinel, means no grammar and seals with `generic`, whether a project or the catalogue wrote it. A catalogue row's suffix and grammar are both real or both `-` -- a row is a sealed gate or it is not, never half of one -- and in config a `grammar:` is read only where there is a seal: an option that runs bare ignores it.

**The grammar also decides whether an empty run is refused.** A tool that exits 0 having executed nothing -- `cargo test` with a filter matching no test, `mix test` with everything excluded -- prints a cheerful summary and returns success, and that is the shape that bites, because it looks exactly like a normal green run. For the grammars devbin can count (`mix`, `credo`, `cargo`, `xcodebuild`, `shell`, `bats`, `critic`) a run that reports **zero executed** is PROMOTED to failed, and the reason is written into the seal.

What this deliberately does not do. It does not promote a run whose tool emitted no trailer at all, because that is not a test run -- `check compile` declares `grammar: mix` for mix's failure reader without ever running a test. And it does not promote under `generic` or `lua`, which have no counter: guessing that unreadable output means nothing ran would fail every gate whose tool devbin cannot count.

Under `xcodebuild`, a completed test action (`** TEST SUCCEEDED **` or `** TEST FAILED **`) is a test run even when neither XCTest nor swift-testing printed a summary of its own, so a selection that matched nothing counts zero and is promoted. The usual cause is a swift-testing display name handed to `-only-testing`, which selects by type and function name, never by display name. A build-only run, and a test action whose build failed (`The following build commands failed:`), reached no test system and are not counted.

A gate whose suite may legitimately be empty declares `grammar: generic`, which keeps the seal and drops the counting. A one-off empty run says so at the command line instead: `--allow-empty` is a gate wrapper flag like `--purge`, split from the tool's arguments on any gate, and keeps the grammar for every other run. `fullcycle` does not take it: it accepts only `--dry-run` and `--force`.

**`all` is never declared.** Any command with at least one option gets it, synthesised from the option list in declared order, so an option added here is in `all` in the same edit. Options marked `in_all: false` are reported as **skipped** rather than dropped silently. `fullcycle`'s test phase is `test all`, so `in_all: false` on a test option keeps it out of a full cycle as well. Options inactive here -- a language the project does not declare, or `enabled: false` -- are counted on `all`'s count line, and `help --why` names them.

```yaml
commands:
  server:
    enabled: true
    summary: Phoenix dev server
    group: Surfaces
    args: "[--iex]"
    run: mix phx.server

  test:
    group: Test
    summary: Run the project gates
    options:
      mix:
        summary: ExUnit
        run: mix test
        grammar: mix
        log: MIX
      swift:
        summary: Swift suites (local only)
        run: xcodebuild test
        grammar: xcodebuild
        log: SWIFT
        in_all: false
      lua:
        enabled: false

  ls:
    handler: myls
    summary: List things (contrived example)
    group: Surfaces

  precommit:
    enabled: false
```

## `release`

The release core (ST0007): one release sequence shared by every project that releases, declared here as data. **`release` is opt-in, like `publish`**: enable it with `commands.release.enabled: true`. A `release:` block does not enable it by being present.

**Every key has a default, and a block names only what differs.** A project that enables `release` and declares no block releases with every default below. A duration is a whole number of `s`, `m` or `h`. **A list is declared empty as the single item `"-"`**, because the grammar has no `[]`; that is how a project declares no gates. **`remotes` refuses `"-"`**: undeclared already means every remote, so an empty list could only mean pushing nowhere.

| Key                         | Type                                   | Default                                       | Meaning                                                                                                                                                  |
| --------------------------- | -------------------------------------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `release.tag`               | string                                 | `v{version}`                                  | the tag name; must contain `{version}`                                                                                                                   |
| `release.remotes`           | list                                   | every remote, in `git remote` order           | the remotes pushed to, in order                                                                                                                          |
| `release.branch`            | string                                 | `main`                                        | the branch a release is cut from and pushed to                                                                                                           |
| `release.notes.kind`        | `changelog` \| `releases` \| `command` | `changelog`                                   | where the release notes live                                                                                                                             |
| `release.notes.run`         | command                                | none                                          | `notes.kind: command` only, and required there                                                                                                           |
| `release.derived`           | list of commands                       | none                                          | regenerate derived files, each printing the paths it wrote                                                                                               |
| `release.gates`             | list of devbin verbs                   | `check all`, `test all`                       | run in order on the release commit; each must exit 0                                                                                                     |
| `release.ci.query`          | command                                | none: CI is not consulted                     | run as `<query> <sha>`, the tag in `DEVBIN_RELEASE_TAG`; the tag's verdict                                                                               |
| `release.ci.wait`           | duration                               | `20m`                                         | how long that verdict is waited for; needs `ci.query`                                                                                                    |
| `release.ci.tag`            | boolean                                | `true`                                        | false: the ci step does not ask about the tag's run; needs `ci.query`                                                                                    |
| `release.ci.base`           | boolean                                | `false`                                       | true: pre-flight needs `ci.query` green on the base commit; needs `ci.query`; refused under `publish.url`                                                |
| `release.object`            | `local` \| `ci` \| `none`              | `local`                                       | who makes the release object                                                                                                                             |
| `release.title`             | string                                 | `{tag}`                                       | `object: local` only; `{tag}` and `{version}` expand                                                                                                     |
| `release.object_wait`       | duration                               | `20m`                                         | `object: ci` only; how long to wait for the workflow's object                                                                                            |
| `release.repo`              | `OWNER/NAME` or `HOST/OWNER/NAME`      | read off the remote a release pushes to first | `object: local` or `ci`; the repository every `gh` call is told about, and required by `release publish`                                                 |
| `release.after`             | list of commands                       | none                                          | run after the release object, reported, outside the core's guarantees                                                                                    |
| `release.verbs`             | list of verbs                          | every verb `release` has                      | the verbs of `release` this project offers; one left out is refused with exit 2                                                                          |
| `release.assets.workflow`   | workflow file name                     | none: nothing is attached                     | `object: local` only; the workflow whose earliest successful run at the tag built the assets                                                             |
| `release.assets.wait`       | duration                               | `30m`                                         | how long the attach waits for that run; needs `assets.workflow`                                                                                          |
| `release.snapshot.list`     | path from the root                     | none: no snapshot is made                     | the shipped list: one git pathspec a line, read in the tree of the commit snapshotted                                                                    |
| `release.snapshot.author`   | `Name <email>`                         | none; required beside `snapshot.list`         | the author and committer of every snapshot                                                                                                               |
| `release.snapshot.message`  | string                                 | `{name} {version}`                            | the snapshot's message; `{name}` and the version its tree declares expand                                                                                |
| `release.publish.url`       | url                                    | none: a snapshot has no parent                | the public repository: a snapshot is made on its publish branch's tip, a cut stops after its push, and `release publish` makes the snapshot public there |
| `release.publish.branch`    | string                                 | `release.branch`                              | the public branch each release's snapshot follows; needs `publish.url`                                                                                   |
| `release.publish.candidate` | string                                 | `candidate/{tag}`                             | the branch `release publish` pushes the snapshot to, and reads CI on; holds `{tag}`; needs `publish.url`                                                 |

**A key the declared mode never reads is refused, not ignored**: `title` and `assets.*` outside `object: local`, `repo` under `object: none`, `object_wait` outside `object: ci`, `ci.wait`, `ci.tag` and `ci.base` without `ci.query`, `ci.query` with `ci.tag` and `ci.base` both off and no `publish.url`, `assets.wait` without `assets.workflow`, `notes.run` outside `notes.kind: command`, `snapshot.author`, `snapshot.message` and `publish.url` without `snapshot.list`, `publish.branch` and `publish.candidate` without `publish.url`, and `ci.base` under `publish.url`, where `release publish` reads CI on the snapshot itself. **`publish.url` needs `publish` among the verbs `release.verbs` offers**, since its cut stops after the push. **`snapshot.list` needs `snapshot.author`**, which has no default: it is the identity every snapshot is made under.

**`release.verbs` says which verbs of `release` a project offers**: a cut (named `cut`, since it has no word on the command line), `status`, `notes`, `check`, `attach`, `snapshot` and `publish`, every one when undeclared. A project whose own command cuts its releases offers `check` and `attach` with the cut off. A verb the list leaves out is refused with exit 2, the code the dispatcher gives a command that is not available here, before anything else is read, naming the verb and the list; `--help` shows only the verbs offered. Each item must be one of those verbs, and `"-"` is refused, since a release with no verbs is `commands.release.enabled: false`; **a list that does not validate fails as config, exit 1, before the refusal reads it**, so a misspelt verb never reads as one switched off. **A key no offered verb reads is refused as unread config**, from one table in `lib/config` of which verbs read each key: with `cut`, `status` and `publish` off, that is `gates`, `derived`, `after`, `ci.query`, `ci.wait`, `ci.tag`, `ci.base`, `title` and `object_wait`, and `branch` too unless `snapshot` reads it, as it does while `publish.branch` is not declared. `remotes` is read by `cut` and `status`, and by `attach` only as `repo`'s fallback, so with `repo` declared and the cut off it is refused too. Printing a key, as `release check` prints every one, is not reading it.

`bin/devbin release check` prints every key with its value and whether it was declared or is the default, then checks the notes: every generated view matches its source, and the project's version has a note that the changelog can carry. It exits 1 if either half finds anything, and names all of it in one run. The one exception is a declaration that does not validate: check stops there, naming what is wrong, before it reads the notes. **Under `object: local` it also names every workflow step in `.github/workflows` that writes a release object, by file and line**, whatever starts the workflow, since the core and that step would both make it: `gh release create`, `upload`, `edit`, `delete` or `delete-asset`, and `hub release create` or `edit`; `gh api` on a line naming `releases`, whatever the method; a call of the releases API by its method name (`createRelease`, `updateRelease`, `deleteRelease`, `uploadReleaseAsset`, `deleteReleaseAsset`), as an `actions/github-script` step makes one; and the release actions `softprops/action-gh-release`, `ncipollo/release-action`, `actions/create-release`, `actions/upload-release-asset`, `svenstaro/upload-release-action`, `goreleaser/goreleaser-action`, `googleapis/release-please-action` and `marvinpinto/action-automatic-releases`. A command continued onto the next line by a backslash is read whole, and a comment is not read. It cannot see a writer reached through a script the step runs, a local or composite action, an action it does not name, or a command held in a variable. The warning does not change the exit. On a pass it says how many workflow files it read and that none writes a release object by a step it reads, naming what it reads; it says so in its own words when there is no workflow file or no `.github/workflows`, names a file it could not read, and under `object: ci` or `none` says it looks for no second writer. `bin/devbin release notes` regenerates the generated views. The annotated example is the `release:` block at the end of `bin/.devbin/lib/config.reference.yaml`.

```yaml
commands:
  release:
    enabled: true
release:
  notes:
    kind: releases
  gates:
    - check all
    - test all
    - doctor
  object: ci
  repo: matthewsinclair/devbin
```

That is the block for a project whose notes are `RELEASES/<version>.md`, whose gates add `doctor`, whose GitHub workflow makes the release object, and whose remotes (`local` and `upstream`, no `origin`) cannot name its repository, so it declares `repo:` -- devbin's shape (ST0007).

### The notes kinds

`release.notes.kind` names where a release's notes live. Every kind answers the same questions about a version -- is its note open or dated, what its body is, which paths a release of it owns -- so nothing else in the core reads a note.

| Kind        | A version's note                                                         | Open while                                  | Dated when                                | Generated views                  |
| ----------- | ------------------------------------------------------------------------ | ------------------------------------------- | ----------------------------------------- | -------------------------------- |
| `releases`  | `RELEASES/<version>.md`: a `key: value` header, then the body            | `status: unreleased`, with no `date:`       | `status: released` and `date: YYYY-MM-DD` | `CHANGELOG.md` and `RELEASES.md` |
| `changelog` | the `## [<version>] - <marker>` section of a hand-written `CHANGELOG.md` | the marker is `unreleased` or `in progress` | the marker is `YYYY-MM-DD`                | none                             |
| `command`   | whatever `release.notes.run` answers                                     | its `state` prints `open`                   | its `state` prints `dated YYYY-MM-DD`     | whatever its `views` writes      |

**`releases`** renders `CHANGELOG.md` from each note's Keep a Changelog sections and `RELEASES.md` as the index, and `release check` compares both with a fresh render without writing. A `## ` heading is a section's when its first word is the section's name, `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`: `## Fixed` and `## Fixed -- reaches every project` both go under `### Fixed`, in the note's order, and a heading's qualifier, after its `--`, `-` or `:`, is kept as a `#### ` line over its entries. Any other heading, such as `## Known limitations`, is narrative and stays in the note. **A note none of whose headings is a section's is refused**, by the cut's pre-flight and by `release check`, naming its headings, since its release would otherwise be missing from the changelog; a release with nothing for a changelog says so with `changelog: none` in its header, and that line over a note that does have a section is refused too. Only a file named `X.Y.Z.md` is a note: any other `.md` under `RELEASES/` is refused by name. Each header line is `key: value`, each key once: a line in any other shape, such as `status:released` or a bare `date:`, and a key given twice are refused naming the line, and an unreleased note carries no `date:` line at all, not even an empty one. A released note is never re-dated.

**`changelog`** reads only the heading of the version asked about, so a history of free-text headings is never parsed. A heading for that version with no marker, a marker that is none of these, or a second heading for it is refused. The body is the section up to the next `## ` heading, without its leading and trailing blank lines.

**`command`** runs `release.notes.run` with a verb, split into words and never `eval`'d as every `run:` is (below), at the root the core is asking about, which is not always the working tree. Its words are glob patterns matched at THAT root, not in the working tree. Its working directory is that root, and devbin's own path variables name it: `PROJECT_ROOT`, `BIN_DIR`, `DEVBIN_DIR`, `DEVBIN_INVOKE` and the project's root variable. So a command reads its notes through those or its working directory, never through a path it works out for itself. Some things still describe the working tree, and a command must not lean on them: a bare command name resolves through the caller's `PATH`, so name the script by a relative path such as `bin/notes`; the variables devbin derives from the config, such as `DEVBIN_VERSION_FILE` and `DEVBIN_LANGUAGES`, describe the working tree's declaration; and the root may not be a git checkout, so a command must not rely on git. `state <version>` prints `absent`, `open` or `dated YYYY-MM-DD`; `date <version> <YYYY-MM-DD>` dates the note and prints each path it wrote; `body <version>` prints the body; `views` regenerates any generated views and prints each path; `views-check` prints `current <path>` or `STALE <path>` for each view and writes nothing; both print `none` for a project that generates no views, `none` is the whole answer, and an empty answer is refused, since silence from a command with no such verb would read as no views; `paths <version>` prints every path a release of that version owns. Paths are relative to the project root, and an answer in any other shape is refused, naming what was printed.

### `release status`

`bin/devbin release status <version>` reads every step of the sequence from the repository, its remotes and the release object, never from a state file, and prints the table a cut's summary prints. It writes nothing: not the working tree, not a ref, not a remote and not the release object. It never fetches.

Each row is in one of these states:

| State        | Meaning                                                                                               |
| ------------ | ----------------------------------------------------------------------------------------------------- |
| `already`    | the step's postcondition holds, so a run would not redo it                                            |
| `pending`    | a run has work here -- including every step with no postcondition, which runs on every run            |
| `skipped`    | declared off: `object: none`, no `after:`, no `ci.query`, or `gates: "-"`                             |
| `not re-run` | the gates once the tag exists, and the confirmation once no push or object is left -- never a verdict |
| `UNREADABLE` | the fact could not be read, and the row says why; **it is never reported as `pending`**               |

The exit status is 0 when every row was read and 1 when any row is `UNREADABLE`.

**The snapshot, candidate and publish rows are `release publish`'s.** Without `release.publish.url` they are `skipped`. With it they are `not read`, naming `release publish <version>`, which reads each against the snapshot it makes: status makes none, so it reads the public repository against none, and says neither done nor to do. The object row then reads the release object of the repository `release.repo` names, the public one, and the confirm row does not count it, since `release publish` makes it.

**The release object, under `object: local`, is `already` only when it carries this release's title and notes**, read as a cut's confirm step reads them. One that exists and differs is `pending`, naming the difference, so status and a cut agree that the object step has work left. Under `object: ci` the row reads whether the object exists, since the workflow owns its title and notes.

**With `release.assets.workflow` declared, the row is `already` only when the object's `SHA256SUMS` agrees with it too**: it exists, names exactly the object's other assets, and each line is that asset's GitHub digest. Otherwise it is `pending`, naming which: no `SHA256SUMS`, an asset it does not name or one it names that the object lacks, a digest that disagrees, or an asset GitHub lists no digest for. It is `UNREADABLE` only when a read fails. Reading `SHA256SUMS`'s text is a small read of the release; status never downloads the run's artifacts. **That proves consistency, not completeness against the run**, since only a download of the artifacts lists the files the run built. It holds because the attach writes `SHA256SUMS` last, once every upload has read back.

**The release commit** is HEAD while no tag for the version exists and the tag's commit once it does, so a finished release read after development has moved on still reads the commit that was tagged. The commit step reads that commit's own tree, never the working tree: a stamp that is only in the working tree is `pending`. **The tree must be clean, and the generated views current, only while the tag is absent**, because nothing after the tag writes the tree. Past the tag a view that reads STALE under today's renderer is named on its row and does not unmake the stamp.

**Reading a commit's tree means writing it out**, from an index of devbin's own (`git read-tree` then `git checkout-index`), into a directory under `$TMPDIR` that is removed on every exit. A `$TMPDIR` inside the project is refused, because a tree written there is exactly the dirt the status reads. The bytes are the commit's: `export-ignore` and `export-subst` do not apply, as they would under `git archive`, so neither can make a correct release read as unstamped. Its limits:

- Smudge and eol filters do apply, as they would in a checkout, but under the commit's own `.gitattributes` (`--attr-source`, git 2.40 or later), so an attribute added after the tag cannot rewrite the release. A clone's own `.git/info/attributes` and `core.attributesFile` still apply. A required filter that fails makes the tree unreadable. On an LFS project the smudge writes `.git/lfs/objects`, so "writes nothing" covers the working tree, the refs, the remotes and the release object, not git's own storage.
- A submodule is written as an empty directory.

A `remotes` entry that names no configured remote is refused by pre-flight, and is `UNREADABLE` to `release status`, which does not hand it to git; both name it with its userinfo left out, since an entry can be a url carrying a token. A remote whose `branch` head this checkout does not hold is `UNREADABLE`, with `fetch` named as the remedy, because whether it contains the release commit cannot be answered without the commit. A remote carrying a different tag of the same name, a lightweight one where this checkout's is annotated included, is `UNREADABLE` too: the push can neither be skipped nor made. A remote that wants a password, a passphrase or a host key is `UNREADABLE` rather than a question at the terminal: every remote read runs through `git_remote` (lib/helpers), with git's terminal prompt off, every askpass program (`GIT_ASKPASS`, `core.askPass`, `SSH_ASKPASS`) emptied for the call, a credential helper told not to ask (`credential.interactive=never`, `GCM_INTERACTIVE=never`), and ssh in batch mode, `-o BatchMode=yes` appended to `GIT_SSH_COMMAND`, else `core.sshCommand`, else `ssh`. A project's own command that reaches a remote can call `git_remote` the same way. Under `GIT_SSH` with no `GIT_SSH_COMMAND` ssh is left as set. Under `object: local` or `ci` the release object is read with `gh release view`; without `gh` it is `UNREADABLE`. **Every `gh` call on the release object names its repository with `--repo`** (pre-flight's `gh auth status` names the host instead, with `--hostname`), from `release.repo`, or when that is undeclared from the configured url of the remote a release pushes to first: the first declared `remotes` entry, else `origin`, else the only remote. `gh` left to choose picks a repository itself, and with no terminal it chose another remote's without saying so. A repository that cannot be resolved makes the row `UNREADABLE`, naming the key; where the remote's url is why, the row names that url with its userinfo left out, since a url can carry a token, and a url holding more than one @ ahead of its host is refused, since where its userinfo ends cannot be told. In a url with a scheme, a raw `/` in a password is left out with the rest of its userinfo where a `:` ahead of it cannot be a port's; one in a url with no scheme, in a userinfo with no `:` ahead of it, in a password that runs only digits up to it, or after a raw @ is printed, since each reads as a host with an @ in its path. git's own words about a remote, which a remote's row, pre-flight and the push step's pushes print, have the same userinfo left out, every part of it: the userinfo whole, what git leaves of a password holding a raw @ as part of the host, what git hands ssh of a password holding a raw `/` as the host, and the user git names when it asks for a password. A url printed whole above is printed whole in git's words too. ssh's refusal still names its user, which is no credential.

### A cut

`bin/devbin release <--patch|--minor|--major|vX.Y.Z> [--dry-run] [--yes]` runs the sequence from its first step whose postcondition does not hold, so running the same target again continues a release that stopped. It runs every step under every `object:`. It prints the table `release status` prints, with a cut's own states: `done`, `already`, `skipped`, `not re-run`, `not reached`, `FAILED`, and under `--dry-run`, `would`. A step that fails stops the run at exit 1, naming the step and what failed. Nothing before the push is seen by another machine, so the remedy is always forward: fix it and run the same target again. A failure after the confirm step says what the run already did outward, such as tagging locally or pushing to a remote. **Past the push the release is published, so the after and ci steps report rather than stop**: a failed `after:` command or a CI verdict that is not green ends the cut at exit 1, saying the tag and the release stand and naming the remedy, which is forward -- the next release, never a moved tag.

1. **Resolve.** `--patch`, `--minor` and `--major` bump the newest tag matching `release.tag`, not VERSION. A version must be greater than that tag, unless its own tag exists, which is a resume. Once the tag exists, `--patch` names the next version, so the summary always prints the explicit command to resume with, and a dry run's the command to cut with.
2. **Pre-flight** writes nothing, and names every refusal it finds in one run:
   - HEAD must be on `branch`.
   - Every remote must answer, and its `branch` must be one the push can fast-forward. A remote that has diverged is refused. So is one that has moved past HEAD while the release commit is still to be made on HEAD. Once the release commit exists, a remote that has moved past it is fine.
   - While the tag is absent, the working tree may be dirty only inside what the release owns: the version file and its sidecars, the note and its generated views, and whatever the `derived:` commands report. Untracked files count, and anything else is refused, naming it. The note must also be open, or dated today.
   - Once the tag exists, its commit must carry the release, or it is refused. A tag is never moved or deleted.
   - Under `object: local` or `ci`, `gh` must be signed in to the repository's host, so the repository must resolve, as the release object's row reads it.
   - With `assets.workflow` declared, the release commit must hold `.github/workflows/<it>`: a run at the tag runs the workflow the tag's commit holds, and a name that names none would otherwise be found at the object step, with the release public.
   - With `ci.base` true, while the tag is absent, `ci.query` must answer `green` for the base commit, the commit the release commit is made on (issue 0223). The suite and the gates run on the maintainer's machine, so a defect only another platform shows reached CI after the tag; this proves CI green before anything is written. **The order is: push `branch`, wait for CI green on it, then cut.** The base is HEAD, or, once HEAD is the release commit, the commit before it, which stands for the release commit only while that commit changes nothing outside what the release owns: one that does is refused, naming the paths (a `derived:` path cannot be told apart there, since only running `derived:` says which paths it writes). The query is run as `<query> <sha>` with no `DEVBIN_RELEASE_TAG`, so it answers for every run on the sha, and it is asked once, bounded at `ci.wait`, never waited on: `failed`, `pending`, `none`, `unknown`, a query that fails, or an answer that is not a verdict, is refused, naming the commit and what the query said, and `pending` says CI is still running and to wait for it and cut again, never that it failed. Under `--dry-run` it is asked too, since asking writes nothing.
   - While the tag is absent, the run logs under `tmp/release/` must be ignored, under `--dry-run` too. A real cut runs behind a sealed gate of its own, `tmp/release/<stamp>.RELEASE.{out,errors}`, and each of its gates writes its log under `tmp/` too, so an unignored log would be dirt the tree rule refuses. Each such directory ignores itself, with a `*` in its own `.gitignore`, so this refuses only where it will not: a `.gitignore` the project put in `tmp/release/` that does not ignore them, or a `tmp/` that leads outside the tree. The remedy named is adding `tmp/` to `.gitignore`.
3. **Stamp**: `version set`, each `derived:` command, then the note dated today and its views regenerated. Once the release commit exists, the stamp is not redone and the `derived:` commands are not run again, so a command whose output changes on every run cannot make a second release commit.
4. **Commit** exactly those paths as `release: <tag>`. The project's commit hooks run.
5. **Gates**: each `gates:` verb, in order, on the release commit in place. **A gate that changes or creates a tracked path, or an untracked path git does not ignore, or makes a commit, fails the step, naming it** (the run logs every gate writes under the ignored `tmp/` are not seen), because the gates examine the commit and must not add to it. The gates run on every run until the tag exists, since nothing records that they passed.
6. **Confirm.** One question, naming the tag, the release commit, and everything still to do that other machines will see: each remote's missing commit or tag, and, under `object: local`, the release object to make or correct, and with `assets.workflow` declared the assets to attach, read through the reader `release status` reads the object row with, so a finished release with assets has nothing left here either. Under `release.publish.url` the release object is `release publish`'s, so the cut does not ask about it. At a terminal it asks `[y/N]`, and `y` or `yes`, in any case, is a yes; `--yes` answers it; with neither, the cut stops here with exit 1, its row saying nobody was there to ask, having tagged and pushed nothing. A resume asks again, naming only what is left, and a re-run with nothing left asks nothing.
7. **Tag**: annotated, at the release commit rather than HEAD, its message the note's body (`### ` lines kept). A tag found is reused and reported on this line when it is lightweight or its message differs; it is never rewritten.
8. **Push**: per remote, the release commit to `branch`, then the tag, each only if that remote lacks it, and never with `--force`. Under `release.publish.url`, a remote the push goes to that names the publish repository, by OWNER/NAME on any host or as the same local path, is refused at pre-flight, and so is one whose url names a host and no OWNER/NAME that can be read: a cut pushes the workroom, its whole history, and the public repository takes the snapshot alone. Each push, like the object step's `gh release create` and `edit`, is cut off at 120 seconds; one cut off fails its step, saying whether it took effect is unknown, and `release status` reads it.
9. **Snapshot, candidate and publish** are `release publish`'s (below). Without `release.publish.url` the three rows are `skipped`. With it, the cut stops here, at exit 0: the three rows are `pending`, naming `release publish <version>`, and the object, after and ci rows are `not reached`, since each reads the public repository, which holds nothing of the release until `release publish` makes it public, and then runs them as a cut would.
10. **Release object**: under `object: local`, `gh release create` titled from `title:` with the note's body. When one exists and its title or notes are not this release's, the confirm step names the difference, and only a confirmed run sets them with `gh release edit`; one is never made twice. With `assets.workflow` declared, the object step then attaches the assets, through the function `release attach` runs (below), where the confirm step named that as work left; an attach that fails stops the cut here, naming its stage, and a re-run continues it. **Under `object: ci`, the core makes none**: the project's workflow makes it from the pushed tag, and the object step reads whether it exists, through the same reader `release status` uses, waiting up to `object_wait`. An object already there is `already`; one that does not appear in time fails the step, naming it. It never reads a CI verdict, so another workflow's run on the release commit cannot stand in for the object. Under `object: none`, none.
11. **After**: each `after:` command, in order, from the project root with no input, each reported. One that fails does not stop the next, or the ci step. These run on every run that reaches them, since nothing records that they ran.
12. **CI verdict**, only when `ci.query` is declared and `ci.tag` is on, as it is by default. With `ci.tag: false` the step is skipped, saying so, and the tag's run is read after the cut: for a project whose tag run takes longer than a cut should wait, with `ci.base` proving the base before it. Otherwise: the query is run as `<query> <sha>` with the RELEASE COMMIT's sha, the tagged commit and never HEAD, with the release tag in its environment as `DEVBIN_RELEASE_TAG`, and its first line of output is `<verdict>[TAB<detail>]` -- `green`, `failed`, `pending`, `none` or `unknown`, the detail naming the run. **A query that reads `DEVBIN_RELEASE_TAG` answers for that tag's runs only, and `none` until one exists.** Read it as `${DEVBIN_RELEASE_TAG:-}`: it is unset when the query is run by hand or by a devbin from before issue 0149, and then the query reads every run on the sha, as before. A cut pushes the release commit to its branch and pushes the tag, and CI may run a workflow for each on that one commit; the branch push's run can finish first and cover less, so a query that reads every run on the sha can report green before the tag's run exists (issue 0149). The tag travels in the environment so that a query checking it was handed one argument keeps working. A query that does not read it keeps its old verdict, every run on the sha, and the core cannot tell the two apart: make yours read the tag. The row names what the query answered, `ci.query answers green for <tag> (<sha>)`, since the core cannot see which runs it read, and `no verdict from ci.query for <tag> (<sha>)` when it gave none: it exited non-zero, was cut off, printed nothing or no verdict, or answered `unknown`. The tag is in the query's environment alone: the cut unsets any `DEVBIN_RELEASE_TAG` it inherits, so no gate or `after:` command sees one. It is asked again every 15 seconds while it answers `pending` or `none`, up to `ci.wait`. `green` is exit 0. Anything else -- `failed`, `unknown`, no verdict within the wait, a query that exits non-zero, prints nothing or prints something that is not a verdict -- is exit 1, and never a quiet 0. Every ask is cut off at the time left, and never below 15 seconds, so a query that hangs cannot hold a published release open.

**`--dry-run`** runs every read and every gate and writes nothing tracked; its gates still write their run logs under the ignored `tmp/`, and it is not itself sealed. It runs the gates on HEAD as it stands, which is a prediction about a commit it did not make, and it says so. It runs no `derived:` command, only counts them, and lists the checks it could not reach, the owned-set check of what `derived:` writes among them. It never asks: the confirm step names what it would ask about, or, given `--yes`, that `--yes` answers it, and the steps from tag to ci what they would do: a dry run waits for no object, runs no `after:` and asks no query. Where the commit step would commit, the confirm, tag and ci rows name the release commit as the one the commit step makes, never HEAD's sha, and the confirm step plans that commit's push to every remote, one already at HEAD included, since the commit is new. When no step failed, its last line is its verdict, `release: dry run of <tag> -- no step failed;` and whether the cut stops to ask at the confirm step; a dry run that fails stops at its FAILED row instead, its last line saying where it stopped, exit 1.

### `release attach`

`bin/devbin release attach <version>` attaches the assets a project's CI built to the tag's release object, and writes one `SHA256SUMS` over every asset on it, so the cut stays the one writer of the object. Under `object: local` only, with `assets.workflow` naming the workflow, with the tag in this checkout, and with the workflow in the tag's commit. A project whose own command cuts its releases runs it once its release object is made; a cut runs the same function at the object step. **It never makes the release object and never dispatches a run.** Each stage reads its postcondition first, so running it again continues where it stopped:

1. **Object**: the release object for the tag exists.
2. **Assets**: the attach's own postcondition, read before any run: `SHA256SUMS` agrees with every other asset on the object, read as `release status` reads the object row and a cut's confirm step reads it. When it does, the attach is finished: it reads no run, downloads nothing but `SHA256SUMS`'s own text, and writes nothing, so running it again on a finished release is `already` however long ago its run's artifacts expired. A read that fails stops it, naming the read.
3. **Run**: the EARLIEST SUCCESSFUL run of `assets.workflow` whose head branch is the tag, at the tag's commit. A run on the tag's ref, pushed or dispatched, carries the tag's name as its branch, and a lookup by commit alone also finds main's run where main and the tag were pushed at one commit. Builds of one commit are not byte-identical, so the earliest is the one that ships and its row names it, and a later run never changes what ships. While no run is listed yet, and while an earlier run is queued or in progress, the attach keeps asking, both within the one bound `assets.wait`. A run that failed, or none by the deadline, fails the stage, naming how to start one (`gh workflow run <workflow> --ref <tag>`) or rerun it (`gh run rerun <id>`); a failed run's cause is read from its jobs, never from its conclusion alone. A run list as long as gh was asked for fails at once, since its earliest run may not be in it and asking again cannot shorten it.
4. **Download**: the run's artifacts as GitHub's API lists them, then `gh run download` into the run's scratch, one directory per artifact. `gh run download` passes over an expired artifact and succeeds while any other downloads, so an expired one is refused, and so is a listed one it did not write. Only the earliest successful run's files ship, so if its artifacts expire before an attach has finished, the attach cannot finish: a run dispatched later is never the earliest, and a rerun of that run (`gh run rerun <id>`) is the one way that might give them back, which is not measured. Every file inside them is an asset, and its name may hold only letters, digits, `.`, `-` and `_`, and not begin or end with `.`: GitHub renames an asset whose name holds anything else, so it would never read back under its own. A file named twice, one named `SHA256SUMS`, and no file or no artifact at all are refused.
5. **Upload**: first every check the object's listing can answer, so a refusal leaves the object as it was: a file the object holds at the same sha256 is `already`; one it holds with other bytes is refused, never replaced; and every other asset on the object, which `SHA256SUMS` names too, must be fully uploaded and have a name the attach can download it by. Then each file the object lacks, with `gh release upload`, from the file's own directory and never with `--clobber`. Every upload reads back at its sha256 before anything else is written.
6. **Sums**: `SHA256SUMS` over every other asset on the object, as `sha256sum -c` reads it (`<sha256>  <name>`, sorted by name). Every hash comes from bytes the attach holds: the run's files, and every other asset downloaded from the release and hashed, since GitHub's artifact digest is of the zip. It is the one asset the attach replaces, with `--clobber`, and only when its text differs; `--clobber` deletes the old one before it uploads the new, so a replacement that fails can leave none, and the next run writes it.
7. **Readback**: every asset this run wrote reads back at its sha256.

Every call to GitHub is cut off: the reads of the object, its `SHA256SUMS` and the run list at the time the wait has left, never below 15 seconds, and every other, each listing, download and upload, at 120 seconds. An asset bigger than one upload or download can move in that time is out of reach. Assets reach the release after it is published, which works while the repository's releases are not immutable. The exit status is 0 when every stage holds and 1 when one fails, naming it. A run that stops says what it wrote to the release object, and names as ones that may have happened an upload cut off at its bound and a `SHA256SUMS` replacement that failed, since `--clobber` deletes the old one first; a cut's stop line names them among what it did outward.

**`bin/devbin release attach <version> --from <dir>` attaches files built on this machine instead** (issue 0226), so there is one way an asset reaches a release: the same object, upload, sums and readback stages, with **Files** in place of run and download: every file under `<dir>`, held to download's rules for a name. `assets.workflow` is not needed, and the tag's commit need not hold one. Its **Assets** stage is not a finish line: where `assets.workflow` is declared, the run's attach must have finished first, and `--from` is refused, uploading nothing, until it has, since an attach `--from` before it would leave `SHA256SUMS` agreeing with the object and the run's attach would then read finished and attach nothing. A relative `<dir>` is read from the project root. The built-in `macos` attaches its zipped app this way.

### `release snapshot`

`bin/devbin release snapshot <version> <new-dir>` makes the public snapshot of the release tag's commit (issue 0239, ST0010): one commit, in a new git repository at `<new-dir>`, whose tree is exactly that commit's tracked files over `release.snapshot.list`. `--commit <rev>` makes it of any commit instead, for an audit ahead of a cut. A relative `<new-dir>` is read from the project root. It must not exist yet, and it must be outside the project, wherever its spelling says it is: a snapshot is never rebuilt in place, and never made inside the tree it comes from.

- **The list is read from the commit's own tree**, one git pathspec a line, with blank lines and `#` comments left out, so an `:(exclude)` line leaves paths out as git reads it. A line that matches no file at the commit is refused, so a list that drifted from the tree never ships a quietly smaller snapshot, and so is a gitlink in what it selects.
- **Plumbing throughout.** The commit's tree is read into an index of its own, exactly the selected blobs are copied into the new repository, and the snapshot's tree and commit are written there. No working tree is read, so every mode and every byte is the commit's, and the new repository holds no object of the project's but those blobs. The commit is read back against the selection before the verb succeeds.
- **The same inputs give the same commit.** Its author and committer are `release.snapshot.author`, both its dates the source commit's committer date in UTC, and its message `release.snapshot.message`, with `{name}` (`project.name`) and `{version}` (the version the commit's own tree declares) filled in as written. It is never signed, and no encoding header is written. So a snapshot is approved by its sha. **`snapshot.author` is written as git writes an identity**: one space before the `<`, and nothing git strips at either end of the name or the email (a space, `,`, `:`, `;`, a quote or `\`), so every snapshot carries it as declared and the next release reads them against it byte for byte.
- **Its parent is the tip of the publish branch at `release.publish.url`**, fetched with its history into the release core's scratch and checked there before the new directory exists, so each release's snapshot is a fast-forward of the last one published. It has none under `--no-parent`, without `publish.url`, or while the branch is not there. `publish.url` is a url, an scp-style `host:path` or an absolute path, never a relative one, since it is read from a repository of the build's own. **It is never made on a history that is not snapshots.** A `publish.url` that names the repository one of the project's own remotes names, by OWNER/NAME on any host and in any case, is refused before anything is fetched, naming the remote: until the public repository is one of its own, its history is the project's, and a first snapshot is made with `--no-parent`. Then every commit behind the tip must be made and committed by `snapshot.author`, have one parent at most, and hold exactly its own tree filtered by the list its own tree carries, or by this list when it carries none, and a history cut short, as a shallow repository's is, is refused too. Each of these refusals names the commit and who made it. A copy of the project's history under a name no remote carries fails the path test wherever the project's commits carry a path outside the list, as devbin's carry `intent/`.

It prints the directory, as it resolves, the source commit and what named it, the list, and the snapshot's tree, commit, parent and branch. It exits 0 once the snapshot reads back, its identity included, and 1 with the reason otherwise. A refusal writes nothing, and a failure after the directory was made removes it. What it reads on the way, the publish branch's history included, is under the release core's scratch, outside the project, which is removed when it exits.

### `release publish`

`bin/devbin release publish <version> [--expect <sha>] [--dry-run] [--yes]` makes a release public as its snapshot (issue 0240, ST0010), for a project that declares `release.publish.url`: its development repository is private, and the public repository holds one commit of the product a release, the commit `release snapshot` makes of the tag. The project's cut pushes to `release.remotes` and stops after its push step (step 9, above), and this runs the rest. Each step reads its postcondition first, so running it again continues where it stopped, and it prints the table a cut prints:

1. **Resolve**: the tag is in this checkout, and names the commit the snapshot is made of.
2. **Pre-flight** writes nothing, and names every refusal it finds in one run:
   - No remote of this project names the publish repository, by OWNER/NAME on any host, in any case, by its url or its pushurl, as configured or as git rewrites it: an ssh host alias for the same repository counts, and so does a path that opens with a `/`, as `host:/owner/name` does. A local path is compared by what it resolves to. One that does is refused, naming the remote, and the url is not read at all, and so is one whose url names a host and no OWNER/NAME that can be read, since then nobody can say.
   - The tag's commit carries the release, as a cut reads a tag it resumes, and holds `release.snapshot.list`.
   - `ci.query` is declared, since CI on the candidate is what lets anything become public.
   - Under `object: local` or `ci`, `release.repo` is declared, since the release object is the public repository's, which no remote of this project names, and `gh` is signed in to its host.
   - The url answers `git ls-remote`, and its publish branch, its candidate branch and the tag are read.
3. **Snapshot**: the commit `release snapshot` makes of the tag, made in the run's scratch, outside the project, on the publish branch's tip, whose history must be snapshots. A tip that is already this snapshot is found rather than built on: the commit made on the tip's own parent is the tip, so a release published reads as the one sha, and running the command again makes no second commit of it. **`--expect <sha>`** takes the snapshot's whole sha, as `release snapshot` prints it, and refuses a snapshot of any other, so what goes public is the commit a person approved; the same inputs give the same sha. A public tag at another commit is refused here, as is a candidate branch holding another commit, a release changed after its candidate was pushed, before anything is pushed.
4. **Confirm**, as a cut's: one question naming the snapshot and what others will see, `--yes` answering it.
5. **Candidate**: the snapshot pushed to its candidate branch, `release.publish.candidate` with `{tag}` filled in (default `candidate/{tag}`), unless it holds it already, and read back. Then `ci.query` is asked about the snapshot's sha, with no tag in its environment, while it answers `pending` or `none`, up to `ci.wait`. Only `green` goes on. `failed`, a run still going at `ci.wait`, or no verdict at all fails the step, naming the answer, and the publish branch and the tag do not move: a red candidate stays as the record of it, and the fix is the next version, while a run still going is read again by running the same command.
6. **Publish**: the publish branch fast-forwarded to the snapshot, then the tag pushed at it, lightweight, so it carries no tagger identity, each read back. A public tag at another commit is refused, since a tag is never moved, and the branch does not move first. A publish branch that has moved since the snapshot was made on it cannot fast-forward and is refused: running again makes the snapshot on the new tip, a new sha, which `--expect` refuses until it is approved. Then the candidate branch, its work done, is deleted, only while it still holds the snapshot (a lease, which forces nothing), and read back as gone; a branch that holds another commit is left as it is. A public tag already at the snapshot does not stand for CI: with the branch still to move, the candidate is read first, as for any publish. An older version run again after a later one was published is refused as public already, its tag being in the publish branch's history.
7. **Object**, **after** and **ci**, as a cut's, against the repository `release.repo` names, the public one, about the snapshot's sha: under `object: ci`, the project's workflow makes the release object from the public tag.

**Nothing is forced**, and a push the public repository refuses stops the run, naming what this run had already pushed. Every call to the public repository is made from a repository of the run's own, outside the project, so the url is read as the person's own git reads it and never through a remote or a url rewrite of this project's: a push can go through `url.<base>.pushInsteadOf` in the person's git config. Every push is cut off at 120 seconds, and every read back is asked again while it does not answer, as a cut's are.

**`release.ci.base` is refused under `release.publish.url`**: it reads CI on the workroom commit a cut is made on, which a publishing project pushes nowhere CI runs, and CI on the candidate is what stands before anything is public. The project's workflow must therefore run on a push of the candidate branch, the whole matrix its release tags run. The built-in `formula` reads its revision from the public repository's tag, which names the snapshot, and refuses a release that is not public yet.

`--dry-run` makes the snapshot in its scratch, reads the public repository, and pushes nothing: the confirm, candidate and publish steps are `would`, as are a cut's object, after and ci. A real run is a sealed gate, its log under `tmp/release/`, as a cut's is.

## `macos`

The built-in `macos` (issue 0226): a macOS app's release, on macOS only. It signs a staged copy of the app with the Developer ID and the hardened runtime, notarises and staples it, checks it as a download meets it, and attaches it zipped to the release at its tag through `release attach --from`. **`macos` is opt-in, like `release`**: enable it with `commands.macos.enabled: true`. A project's own `macos` handler or `run:` still wins. The notary credentials live in the login keychain under `keychain`'s prefix and nowhere else; no key here holds one.

| Key                  | Type        | Default                        | Meaning                                                                         |
| -------------------- | ----------- | ------------------------------ | ------------------------------------------------------------------------------- |
| `macos.app`          | path        | none: required to sign         | the `.app` bundle the build leaves, from the project root or absolute           |
| `macos.build`        | command     | none: the app is built already | run at the project root before `app-sign` stages the app                        |
| `macos.bundle_id`    | string      | none: required to sign         | the `CFBundleIdentifier` the app must carry, and the identifier it is signed as |
| `macos.entitlements` | path        | none: signed without           | the entitlements file signed into the app, from the project root or absolute    |
| `macos.keychain`     | string      | `devbin.apple`                 | the login keychain's service prefix: `<prefix>.APPLE_ID` and the others         |
| `macos.asset`        | asset name  | the app's name with `.zip`     | the name the zipped app is attached to the release under                        |
| `macos.version_from` | path        | `project.version_from`         | the file the app's own version is read from, for an app that versions apart     |
| `macos.commit_stamp` | plist key   | none: not checked              | the `Info.plist` key the build writes its commit into; required with the above  |
| `macos.kind_stamp`   | plist key   | none: not checked              | the `Info.plist` key the build writes its kind into                             |
| `macos.kind_value`   | string      | `release`                      | the value `kind_stamp` must carry; read only with `kind_stamp`                  |
| `macos.build_root`   | path        | the directory holding `app`    | where publish's last Launch Services drop looks for the build's own records     |

`bin/devbin macos app-sign` refuses unless HEAD is the release tag of the project's version (`release.tag` and `project.version_from`) in a clean tree, and refuses a staged copy whose bundle id is not `bundle_id`, whose version is not the app's, or whose declared stamps are not the tag's build's: the kind must be `kind_value`, and the commit 8 to 40 lowercase hex characters, a prefix of the tag's commit, with the tag in the tree. publish asks the same of the stapled copy and of the copy inside its zip. **An app may version apart from its project** (issue 0243): with `version_from` naming another file than `project.version_from`, its version is read from there, through the one reader, while the tag, the release and the attach stay the project's, and `commit_stamp` must be declared, since the app's version cannot show a copy is the tag's build. **A path key may open with `~`, `$HOME` or an XDG base-directory variable** (`$XDG_STATE_HOME`, `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME` or `$XDG_CACHE_HOME`, as `$X` or `${X}`), expanded as the XDG spec reads it, so an app built outside the project needs no machine's own path. Each stands alone as a whole leading component, and an XDG variable that is unset falls back to its XDG default, so `${XDG_STATE_HOME}/x` needs no `:-` fallback; any other leading `~` or `$` (`~user`, `$FOO`, `${XDG_STATE_HOME:-...}`), and a HOME that is not absolute, are refused, naming what the value opens with. The stage is under the XDG state directory, in `devbin/macos/`, one per checkout, and one at or under the project root or the app's directory is refused.

**Every copy a step makes is dropped from Launch Services on every path out**: the staged copy, the Gatekeeper check's quarantined copy and publish's proof copy, each with INT, TERM and HUP ignored through the drop and the record list read back. A record left on the staged copy is a warning naming the command that drops it, and the exit stands, since the next step drops it again, publish the last, and a failed step drops it too. One left on a copy that is gone fails the run; for publish's proof copy that is after the upload, and the failure says first that the asset is published. After the upload, publish drops every record at or under `build_root` as well, and one that stays is a warning, since a build can register its product again. A `build_root` that is `/`, or holds the home directory or a directory installed apps live in (`/Applications`, `~/Applications`), is refused before anything is built or uploaded, since the drop would take the installed app's records with it. `bin/devbin help macos` has every subcommand.

```yaml
commands:
  release:
    enabled: true
  macos:
    enabled: true
macos:
  app: build/Products/Release/Demo.app
  build: bin/build-app --release
  bundle_id: com.example.demo
  entitlements: native/macos/Demo/Demo.entitlements
```

## `formula`

The built-in `formula` (issue 0227): the project's Homebrew formula, rendered from a template and a release, and published to its tap. It is the dev/opt/brew contract's formula tool (`docs/dev-opt-brew.md`, T8), with `render <tag> <out>` and `publish`. **`formula` is opt-in, like `release`**: enable it with `commands.formula.enabled: true`. A project's own `formula` handler or `run:` still wins.

| Key                | Type          | Default                                                          | Meaning                                                                                   |
| ------------------ | ------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `formula.mode`     | word          | `source`                                                         | `source`: brew builds from the tag's checkout; `assets`: it installs the release's assets |
| `formula.name`     | string        | `project.name`                                                   | the formula's name, and its file in the tap, `Formula/<name>.rb`                          |
| `formula.template` | path          | `packaging/homebrew/<name>.rb`                                   | the formula template, from the project root                                               |
| `formula.tap`      | git url       | `homebrew-<name>` under the release repository's owner, over ssh | the tap publish clones, commits to and pushes                                             |
| `formula.repo`     | `OWNER/NAME`  | the release repository                                           | assets: the repository whose release carries the assets and the sums file                 |
| `formula.sums`     | asset name    | `SHA256SUMS`                                                     | assets: the sums file on that release, `<sha256>  <name>` a line                          |
| `formula.assets`   | list of names | none                                                             | assets: the assets the templates take a sha256 of; each may hold `{version}`              |
| `formula.bin`      | list of paths | none                                                             | assets: the keg's executables, from libexec, each set 0755 and linked into bin            |
| `formula.manifest` | path          | `.<name>-install`                                                | assets: the keg's T3 manifest, under libexec                                              |
| `formula.cask`     | path          | none: no cask                                                    | assets: a cask template, from the project root, pushed beside the formula                 |

The template is the project's own Ruby, so its desc, caveats, install layout and any service block stay its own, and devbin fills its placeholders from git and the release, never from a person. In source mode it holds exactly one `@@TAG@@` and one `@@REVISION@@`. In assets mode it holds `@@VERSION@@`, one `@@SHA256:<asset>@@` for each asset in `assets`, read from the release's sums file by its exact name, and exactly one of `@@INSTALL@@` and `@@FINISH@@`, the install body devbin generates: 0755 on each of `bin`, the manifest in T3's form, and the links. A key the mode does not read is refused, and so is a placeholder left after filling. `publish` names the tap and asks before it pushes, with no `--yes`; as a cut's `after:` step it takes the yes given at the cut's confirm prompt, and under the cut's `--yes` it publishes nothing. `bin/devbin help formula` has every refusal.

```yaml
commands:
  formula:
    enabled: true
formula:
  mode: assets
  cask: packaging/homebrew/demo-app.rb
  assets:
    - demo-aarch64-apple-darwin
    - "demo-{version}-x86_64-linux.tar.gz"
  bin:
    - bin/demo
```

## `worktrees`

The built-in `worktrees` (issue 0245): a read-only report of each linked worktree of the repository, landed, held or unknown, with its evidence, and `remove-landed <path>...`, which removes the named worktrees that read landed. It is offered in every project, and refuses with exit 2 where the project is not a git checkout. `bin/devbin help worktrees` has every check and verdict.

| Key                | Type                 | Default | Meaning                                                                          |
| ------------------ | -------------------- | ------- | -------------------------------------------------------------------------------- |
| `worktrees.branch` | branch name          | `main`  | the branch landed work reaches, read as `refs/heads/<branch>`                    |
| `worktrees.banks`  | list of ref patterns | none    | refs that are banks, as `git for-each-ref` reads its patterns; none: branch only |

A project whose main branch is not `main` sets `branch`. It is its own key, not `release.branch`: the branch work lands on and the branch a release is cut from differ wherever a project integrates on one and releases from another. A pattern in `banks` matches as `git for-each-ref` matches: `refs/bank` matches every ref beneath it, at any depth, and `refs/bank/*` one level only.

```yaml
worktrees:
  branch: main
  banks:
    - refs/bank
```

## What config deliberately cannot do

**The YAML never grows control flow.** If a declaration needs an `if`, it is a script. This is a review gate on every change to devbin, not an aspiration -- the moment config can branch, it is a bad programming language with no debugger.

**`run:` is split into words and never `eval`'d, and every word is a glob pattern.** The splitting is on spaces, tabs and newlines, whatever `IFS` the caller happens to have. Re-interpreting quotes, substitutions and redirections out of a config file is not wanted, so they stay literal characters. The cost is real and worth naming: a declarative `run:` **cannot express an argument containing spaces**. That is the boundary in practice -- a command line needing real quoting needs a handler, and writing one is a two-minute job (`devbin new`).

**Each word is then matched in the directory the command runs from** -- the project root, or for `release.notes.run` the root it is answering about. A word holding `*`, `?` or `[...]` becomes one word per file it matches, and a word matching nothing is passed through exactly as written. So `run: bats opt/*/test` hands `bats` one directory per match, and **what the command runs depends on the files that are there when it runs**. This is bash's own pathname expansion, and devbin pins the options it happens under, so an inherited `SHELLOPTS` or `BASHOPTS` cannot change what a declared line runs. A pattern matching a dotfile must name the dot, as in any shell.

**A `run:` with no words in it is refused, naming the key.** `run: "   "` and `run: ""` both hold no command, and before this they ran whatever was typed after the command as the command, at exit 0. `doctor` reports them, and the command refuses to run them. `doctor` holds these keys to this: `commands.<cmd>.run`, `commands.<cmd>.options.<opt>.run`, `commands.fullcycle.restore` and `release.notes.run`. The release block's other command lines -- each `derived:`, `gates:` and `after:` item, and `ci.query` -- are split and globbed the same way, and one with no words is refused by the cut at the step that runs it; `doctor` refuses them only when empty.

## Checking your config

```
$ bin/devbin doctor
```

`doctor` parses the config, validates it against the schema, resolves every declared command, reports orphaned handlers in `cmd/`, verifies the vendored checksums and the `bin/devbin` launcher (noting a retired `bin/<project>` alias and checking where a `bin/<alias>` shortcut points), and enforces `devbin_version`. It notes a `release:` block in a project that has not enabled `release`, and runs any project checks in `bin/.devbin/cmd/doctor.d/` after its own. It tells you how many checks it ran, and a run that checked nothing fails on that alone.
