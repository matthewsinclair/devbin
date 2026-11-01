# Devbin

Devbin is a dev launcher you **declare** rather than write.

Most projects grow a `bin/devbin` script: a dispatcher, a helpers library beside it, and a help text that has to be updated by hand every time either changes. Devbin is that script, extracted once. A project gets the dispatcher, a runtime library and a `config.yaml`, and the commands it offers follow from what it declared.

It came out of four real projects whose launchers had independently converged on the same shape -- and then drifted. Between them they carried four copies of one helpers library (50-80% identical), four hand-maintained help heredocs totalling roughly 95 KB, and eight hand-written `test_all` / `check_all` functions. A hardening learned in one of them had reached none of the others, and could not, while there were four copies. Devbin is the one copy. All four projects now run on it -- and so does devbin itself, whose own build breaks first if the dispatcher regresses.

```
$ cd ~/code/myproject
$ devbin install --into . --name myproject --alias mp --lang elixir
$ bin/devbin test all
```

## What you get

- **A dispatcher** at `bin/devbin`. No launcher named after your project -- that convention was retired because it shadowed the binaries these projects build; see below.
- **Built-in commands** -- `test`, `check`, `fmt`, `clean`, `build`, `version`, `docs`, and the surfaces (`server`, `iex`, `cli`, `repl`) -- scoped to the languages your project declares, so an Elixir project never sees `cargo` gates and a shell project never sees `mix`.
- **Sealed gates.** A gate's verdict is a **file**, not terminal output: `test all` writes `tmp/test/<stamp>.<SUFFIX>.{out,errors}` per option, and the `.errors` companion is empty exactly when a completed run was green. CI reads the file; you read the scroll.
- **A toolchain gate that reads the deploy image.** `check toolchain` proves the running versions match the `.tool-versions` pin -- and, when a Dockerfile builds the deploy image, that the image's pinned `ARG` versions agree with the same file. A project with a `fly.toml` and no Dockerfile fails rather than passes, because a deploy nobody can check is a breach, not a gap.
- **A free `all`.** Any command with at least one option gets `all` synthesised from the option list. Add an option to config and it is in `all` in the same edit.
- **Generated help.** `devbin help` is derived from what actually resolves, so it can neither list a command that does not exist nor omit one that does.
- **Your own commands**, first class. Drop an executable in `bin/.devbin/cmd/` and it is registered -- no config edit, no help edit.

## Install

Install devbin with Homebrew, on macOS or Linux, and seed each project from that install:

```zsh
brew tap matthewsinclair/devbin
brew install matthewsinclair/devbin/devbin
mkdir -p ~/some/new/project
devbin install --into ~/some/new/project
```

`install --into` makes no directory: a path that is not there is refused rather than made into a project, so make the directory first, as above.

The tap is `matthewsinclair/homebrew-devbin`, and Homebrew fetches it and the formula's url over https, with no credential. Install the formula by its **full name**, as above: Homebrew refuses a short name from a tap it does not trust yet, and installing by the full name trusts the formula, so the short name works after it.

The formula fetches the release tag by git and runs devbin's own publish into the keg, so **the brew install is a machine install**, and the `devbin` on your PATH is it. A project finds it at `$HOMEBREW_PREFIX/opt/devbin/libexec`, the path Homebrew keeps across upgrades, and `bin/devbin doctor` in a project names the install it resolves to and what chose it. `brew upgrade devbin` moves the install to the next release, and `bin/devbin upgrade` in a project then takes it (see [Keeping it current](#keeping-it-current)). devbin's own `install` and `upgrade` refuse to write into the keg. `bin/devbin help install`, in a project, has the whole of it.

### `devbin install`

Devbin installs itself into a project. The devbin doing the installing is whatever you are running, and it records itself as the new project's source, so seed from the brew install and never from another project: seeded from another project, the bytes are right, and the recorded `source_commit` is that project's own git HEAD, a hash that does not exist in devbin's history at all.

```
devbin install [--into <dir>] [--name <n>] [--alias <a>] [--lang <l>] [--force]
```

| Flag      | Meaning                                                        |
| --------- | -------------------------------------------------------------- |
| `--into`  | the project to install into (default: the current directory)   |
| `--name`  | the project name (default: the target directory's name)        |
| `--alias` | a short project alias recorded in config, `mp` for myproject   |
| `--lang`  | a language the project declares; repeatable or comma-separated |
| `--force` | re-vendor over an existing install                             |

It writes `bin/devbin` and `bin/.devbin/lib/`, scaffolds `bin/.devbin/{cmd,help}/`, and writes a starter `config.yaml` **only if there is none**. Your config, your handlers and your authored help are never overwritten, with or without `--force`.

### `bin/devbin` is the invocation, in every project

**It writes no launcher named after your project, and that is deliberate.** Install once also created `bin/<project>` and `bin/<alias>` as symlinks to `bin/devbin`, so you typed `bin/myproject test`. That convention collided with the binaries these projects *build* -- one ships a binary under its own name, Intent ships an `intent` -- and a launcher that shadows the product is the wrong default. Intent had already routed around it by calling its shim `int`.

`bin/devbin` was always the real dispatcher and those names were always aliases to it, so this is a **deletion, not a new convention**. It also means one thing you can rely on in any devbin project, without knowing what the project is called:

```
bin/devbin test all
bin/devbin check all
bin/devbin clean rust
```

`doctor` notes a surviving `bin/<project> -> devbin` as a retired alias, says whether to remove it is the project's call, and names any link that points at it -- it is not broken, it is standing where your own binary wants to live. A **real** file at that name is silent, because that is now the expected state.

If you want a short command from anywhere, devbin emits one -- it walks up from `$PWD` to the nearest `bin/devbin`, so it needs nothing vendored and nothing configured:

```zsh
eval "$(devbin shell-init zsh)"     # in ~/.zshrc
eval "$(devbin shell-init bash)"    # in ~/.bashrc
```

Put the line for your shell in its rc. The function is called `dvb`.

**`dvb` cannot bootstrap through a project, by construction.** It finds devbin by walking up from `$PWD`, so it locates one THROUGH a project that already has it, and in a project that has none the walk finds nothing. So it falls back to the machine install, last, and a `dvb` emitted by the brew install, as above, falls back to the brew install: Homebrew's `opt` path is written into it, the one `brew upgrade` keeps. In a new project, then:

```zsh
mkdir -p ~/some/new/project && cd ~/some/new/project && dvb install
```

A `dvb` emitted by a consumer project's own `bin/devbin` has no machine install written into it, so it falls back only when `DEVBIN_INSTALL_PREFIX` names one.

The fallback runs whatever you typed against that devbin and lets its cwd guard rule on it, so `install` and `shell-init` work and everything else is refused by name rather than acting on the wrong tree. `bin/devbin shell-init --help` is the full statement; this is a pointer to it.

It used to be a snippet printed here, and that is the reason it is a command now. The snippet carried two defects, the serious one being that a `bin/devbin` which existed but was not executable got stepped over -- so the walk continued into the parent and ran **another project's** launcher, at exit 0. Within an hour of a third copy existing, the three had already diverged: the landed copy was fixed and this file's was not. **A copy-paste snippet has no install step, no version, and no way to reach anyone who already pasted it.** `shell-init` has one source, a test, and a route to every project on the next re-vendor.

### On Windows: WSL 2, and nothing native

devbin runs on Windows inside WSL 2, as the Linux program it is there. There is no native port: no `.cmd`, `.bat` or `.ps1`, no Git Bash or MSYS2, and no `C:\` path handling. WSL 1 is not a developer platform. Before anything else:

1. **WSL 2 with Ubuntu 24.04 or 26.04 LTS.**
2. **Clone and work inside WSL's own filesystem** (`~/...`), never under `/mnt/<drive>`. A repository a Windows-side tool cloned onto a Windows drive -- an IDE's own git, a Windows git -- is cloned again inside WSL rather than used through `/mnt`: under `/mnt` it is slow, its exec bits come from the mount options, and its names are case-insensitive.
3. **WSL's own git** (`sudo apt-get install git`), so `core.autocrlf` takes Linux's default rather than Windows'. An editor works on the WSL side through its WSL integration, so its git runs inside WSL too.
4. **The packages.** Ubuntu's bash already meets the bash >= 5 floor. Then `sudo apt-get install git jq shellcheck parallel`: `jq` and `shellcheck` because the critic gate calls them (below), `parallel` for `test all`'s lanes, and each project's own toolchains beside them. devbin itself is installed with Homebrew, as [Install](#install) says, which runs under WSL 2 as on any Linux. Intent is installed by [Intent's own install page](https://github.com/matthewsinclair/intent/blob/main/docs/install.md#linux), which this README points at rather than copies.
5. **Advice, not a requirement:** `appendWindowsPath = false` under `[interop]` in `/etc/wsl.conf` keeps the Windows PATH out of WSL altogether. devbin works without it.
6. **Behind a VPN**, WSL 2 often does not inherit the VPN's DNS and routes unless its mirrored networking or its DNS tunnelling is on: `networkingMode=mirrored`, or `dnsTunneling=true`, under `[wsl2]` in the Windows-side `.wslconfig`, both on Windows 11 22H2 or later. This is WSL's documented behaviour and has not yet been measured on a real machine here.

**`check all` refuses at the critic gate in a project that carries `intent/`** until Intent's Linux binary is on PATH, which Intent's install page above provides. The gate needs `intent`, and runs a weaker critic without `shellcheck` and `jq`, so install all of them. A rules check that cannot run fails loudly by design. A project that has to run `check all` before then can turn the gate off in its own `bin/.devbin/config.yaml`, which devbin never does by default:

```yaml
commands:
  check:
    options:
      critic:
        enabled: false
```

## The 60-second config

`bin/.devbin/config.yaml`, in full, for a project that wants the Elixir gates:

```yaml
project:
  name: myproject
  alias: mp
  languages:
    - elixir

help:
  tagline: "everything you need to work on myproject"

commands:
  server:
    enabled: true
    summary: Phoenix dev server
    group: Surfaces
    args: "[--iex]"
    run: mix phx.server
```

That is a working launcher. `test`, `check`, `fmt`, `version` and `docs` are already there with their Elixir options, because `languages: [elixir]` is what activates them. `test all` runs ExUnit and Credo and seals both.

Only `project.name` is required. Every key is documented in **[docs/configuration.md](docs/configuration.md)**, and a fully annotated example is vendored into your own project at `bin/.devbin/lib/config.reference.yaml`.

## The command surface

Built-ins are **offered** by language or on request. A language-scoped command appears when your project declares that language; an opt-in one appears only when you ask for it. Everything else is always there, except that `docs` needs an `intent/` directory: its one option drives Intent. A project seeded without `--lang` declares no language, so it offers the table below and devbin's own lifecycle, as its `bin/devbin help` lists them.

Always offered:

| Command     | What it does                                                                       |
| ----------- | ---------------------------------------------------------------------------------- |
| `check`     | Read-only gates; each exits non-zero on a breach                                   |
| `fmt`       | Format sources in place                                                            |
| `build`     | Build this project's targets, which it declares itself                             |
| `cache`     | Reuse a built artefact while its inputs are unchanged: key, get, put, list, rm, gc |
| `worktrees` | Report linked worktrees, landed, held or unknown, and remove the landed ones       |
| `docs`      | Regenerate generated documentation (AGENTS.md); needs intent/                      |
| `version`   | Show, set, bump, sync and check the project version                                |
| `ci-state`  | Read CI's verdict on a commit: green, failed, pending, none or unknown             |
| `infra`     | Profile and check this estate's DNS and mail configuration                         |

`build` is listed in every project and runs nothing until the project says what it builds: `commands.build.run`, options under `commands.build.options`, or a handler, at `bin/.devbin/cmd/build` or mapped with `commands.build.handler`. devbin ships the name only, and doctor notes it as offered with nothing to run until then. A declared language also gives `check` options for elixir and rust, and `fmt` options for elixir, rust and swift.

`cache` keeps what a project's build handler builds under a key made from the inputs its `build:` block declares ([configuration](docs/configuration.md)), so a handler that runs `bin/devbin cache get` before it builds and `cache put` after pulls an artefact whose inputs have not changed instead of building it again; `bin/devbin cache --help` gives its answers.

`ci-state` reads CI's verdict on one commit through `gh`, in the release core's own words, so it is the query a release names as `release.ci.query`: `bin/devbin ci-state <sha>` prints `<verdict><TAB><detail>`, and `release.ci.workflow` and `release.ci.summary` say which workflow's runs count and whose verdict a run's is ([configuration](docs/configuration.md#release), `bin/devbin help ci-state`).

Offered when the project declares the language. `test` and `clean` have an option for each language they serve, so each appears once the project declares any one of those:

| Command     | Language                        | What it does                                                     |
| ----------- | ------------------------------- | ---------------------------------------------------------------- |
| `test`      | elixir, rust, swift, lua, shell | Run this project's test gates                                    |
| `clean`     | elixir, rust, swift             | Remove build artefacts this project can regenerate               |
| `server`    | elixir                          | Development server                                               |
| `iex`       | elixir                          | Interactive Elixir shell with the project loaded                 |
| `cli`       | elixir                          | Run this project's own command-line interface                    |
| `repl`      | elixir                          | Interactive REPL, with readline history                          |
| `db`        | elixir                          | Database lifecycle                                               |
| `fullcycle` | rust                            | From a total clean: remove the trees, rebuild, test. DESTRUCTIVE |
| `dormancy`  | rust                            | How many tests this project does NOT run, against --all-features |

Shipped as names, absent until the project asks for them -- `enabled: true`, or a `run:`, options or a handler of its own. Devbin ships no command line for any of these -- each was one or two of the four source projects and encoded that project's shape, so enabling one means supplying what it runs:

| Command     | What it does                                    |
| ----------- | ----------------------------------------------- |
| `precommit` | The pre-commit gate                             |
| `publish`   | Publish a release artifact                      |
| `content`   | Content pipeline tasks                          |
| `which`     | Report which binary or build a name resolves to |

`release` is opt-in the same way, and devbin implements it itself: one release sequence shared by every project that releases, declared in a `release:` block ([configuration](docs/configuration.md#release)). It was built under ST0007. `release check` validates and prints the declaration and then checks the notes -- the generated views match their source, and the project's version has a note -- `release notes` regenerates the generated views, and `release status <version>` reads every step of the sequence from the repository, its remotes and the release object and prints where a release stands, writing nothing. A cut resolves the version, pre-flights, asks once (or takes `--yes`), stamps and commits, then starts every leg together on the release commit under one wait -- the gates in place and, unless `ci.query` is `-`, CI on that commit pushed to its candidate ref -- and only when every leg is green tags, pushes, deletes the candidate and makes the release object; a red leg or a timeout leaves no tag and nothing public. It seals its own run as `tmp/release/<stamp>.RELEASE.{out,errors}`; `--dry-run` does the same reads, runs no gate and writes nothing, printing every write as `would`. Under `object: ci` it waits for the project's workflow to make the release object, and makes none itself. It then runs `after:`: the release stands whatever they do, and one that fails exits 1, naming it.

| Command   | What it does                                                                                                    |
| --------- | --------------------------------------------------------------------------------------------------------------- |
| `release` | Cut a release: confirm once, then stamp, commit, legs under one wait, tag, push, the release object and after:  |

`macos` is opt-in the same way, and devbin implements it too: a macOS app's release, on macOS only. It signs a staged copy of the project's `.app` with the Developer ID and the hardened runtime, notarises and staples it, checks it as a download meets it, and attaches it zipped to the release at its tag through `release attach --from`, the core's one way an asset reaches a release. The notary credentials live in the login keychain and nowhere else, and nothing prints a value. It is declared in a `macos:` block ([configuration](docs/configuration.md#macos)), and a project's own `macos` handler or `run:` still wins.

| Command | What it does                                                                   |
| ------- | ------------------------------------------------------------------------------ |
| `macos` | Sign, notarise and verify a macOS app, and attach it to the release at its tag |

`formula` is opt-in the same way: the project's Homebrew formula, rendered from a template in the project and a release, never typed, and published to its tap. In source mode brew builds from the release tag's checkout; in assets mode the formula installs the release's assets, each sha256 read from the release's sums file, and devbin generates the install body that sets the executable bit, writes the install's manifest and links the executables. publish names the tap and asks before it pushes; as a cut's `after:` step it takes the yes given at the cut's confirm prompt. It is declared in a `formula:` block ([configuration](docs/configuration.md#formula)), and a project's own `formula` handler or `run:` still wins.

| Command   | What it does                                                          |
| --------- | --------------------------------------------------------------------- |
| `formula` | Render the Homebrew formula from a release, and publish it to the tap |

Devbin's own lifecycle, always offered:

| Command      | What it does                                                                      |
| ------------ | --------------------------------------------------------------------------------- |
| `install`    | Vendor devbin into a project, or in a dev checkout publish its opt install        |
| `upgrade`    | Re-sync the vendored runtime from the install this machine's switch names         |
| `vendor`     | Compare the vendored runtime against the devbin it came from                      |
| `doctor`     | Check this install and report what is wrong with it                               |
| `new`        | Scaffold a new project command, ready to run                                      |
| `shell-init` | Emit the shell function that finds the nearest bin/devbin                         |
| `devbin`     | About devbin itself: the framework's help, not this project's                     |

Offered only in devbin's own trees -- the dev checkout, an opt install and the keg -- and never by a project's `bin/devbin`, since it chooses which devbin the whole machine runs:

| Command | What it does                                            |
| ------- | ------------------------------------------------------- |
| `use`   | Choose which devbin this machine runs: dev, opt or brew |

`devbin help` lists what **your** project actually offers. `devbin help --why` lists that plus everything devbin ships that is not offered here, each with the reason -- because a command scoped out by language is otherwise indistinguishable from a command that is broken.

## What lands in your project

```
bin/devbin                       the dispatcher
bin/.devbin/config.yaml          YOURS
bin/.devbin/cmd/<name>           YOURS -- project commands, auto-discovered
bin/.devbin/cmd/<name>.d/<sub>   YOURS -- sub-commands, same rule at any depth
bin/.devbin/help/<name>.md       YOURS -- authored long-form help, read before devbin's
bin/.devbin/lib/                 devbin's runtime, its pages for its built-ins among it
bin/.devbin/manifest.sha256      checksums of everything devbin owns
```

**This split is the seam, and it is the only rule you need to remember.** `bin/devbin` and everything under `bin/.devbin/lib/` belongs to devbin and is replaced wholesale on upgrade. `config.yaml`, `cmd/` and `help/` belong to you and are never written by install or upgrade.

`manifest.sha256` is what keeps the seam honest. It records a checksum for every file devbin owns, and it lives beside `lib/` rather than inside it so it survives the wholesale replacement of the thing it describes. A vendored file whose checksum has moved was edited in place: `upgrade` reports it, refuses it, and leaves it alone. **The refusal is the feature** -- an upgrade that always wins is one people stop running. Pass `--force` when the edit was a mistake.

The seam has a second face, learned live: the vendored half is not yours to **format** either. If your project runs a Markdown formatter on commit, fence `bin/.devbin/lib/` in `.prettierignore` -- a hook that rewrites vendored files breaks the manifest checksums, and `doctor` will say so on its next run.

## Adding your own command

```
$ bin/devbin new deploy --summary "Ship it" --group Ship
  wrote  bin/.devbin/cmd/deploy
  wrote  bin/.devbin/help/deploy.md
  wrote  tests/deploy.bats

bin/devbin deploy resolves now. Try:
  bin/devbin help deploy
  bin/devbin deploy
```

The handler is executable, carries its own `# devbin: summary = Ship it` header, and appears under `Ship:` in `bin/devbin help` immediately. Nothing else needs editing -- a script in `cmd/` **is** the registration. The test stub is written only where the project already has a bats suite; without one, `new` says it skipped it. The handler exits 3 until you write it, because a command that resolves and returns 0 having done nothing is exactly the false green the rest of this framework is built to prevent.

The full protocol, including sub-commands, sub-options, the free `all`, and where help text comes from, is in **[docs/authoring-commands.md](docs/authoring-commands.md)**.

## Keeping it current

```
$ brew upgrade devbin           # move the brew install to the next release
$ bin/devbin upgrade            # re-sync the runtime from where it came from
$ bin/devbin doctor             # is this install sound?
```

`doctor` checks the dispatcher, the runtime, the config, the declared languages, the vendored checksums, the declared `devbin_version` constraint, every declared command's resolution, orphaned handlers, any project name standing where devbin ships its own, the `bin/devbin` launcher, a retired `bin/<project>` alias and a `bin/<alias>` shortcut, whether the devbin you vendored from has moved, and the bash floor -- then runs every executable in `bin/.devbin/cmd/doctor.d/` as a project check, counted into the same summary (`doctor <check>` runs one alone). It reports three outcomes rather than two -- a **failure** is broken, a **note** is true and worth saying -- and **it prints how many checks it ran**, because a checker that examines nothing and exits 0 is the most expensive bug a tool like this can have.

**It tells you, rather than waiting to be asked.** When the devbin your project vendored has moved on, the launcher says so -- once a day, on a terminal only, on stderr:

```
UPDATE: devbin has moved on since this project vendored it.
        vendored 4dc899de522b, source now 0af216018b59
        run: bin/devbin upgrade      (silence: DEVBIN_NO_UPDATE_NOTICE=1)
```

The comparison is the one `vendor` and `upgrade` already make -- the manifest records which commit the bytes came from, and devbin asks which way the source has moved since -- so what is new is the moment it is made, not the answer. **Only a source that moved forward is called an update, and only when a vendored file changed**: a devbin commit that touched nothing a project vendors, such as coordination state, says nothing (issue 0224). A source BEHIND the project -- a rewound install, a checkout on an older branch -- is reported as behind, and upgrading from it is never suggested, because that upgrade could revert the runtime. A source that differs in no known direction is reported as a difference and not as an update. `doctor` says the same, and the interactive offer to upgrade is made only for the forward case (issue 0079). **Terminal-only is the load-bearing part**: CI logs and sealed gate output are pipes, and devbin parses its own run logs with its extraction grammars, so a version line on stdout would become input to a verdict. A consumer without devbin's source tree on disk sees nothing at all, which is the ordinary case rather than an error.

## Cleaning the build surface

```
$ bin/devbin clean rust         # cargo target/ trees, release included
$ bin/devbin clean all          # every language the project declares
```

**It takes `release/`, which is what makes it a release verb rather than a cache sweep** -- run it before a release build and the shipped artefact is provably new. It discovers build trees rather than carrying a path list, so a workspace conversion that moves the output directory cannot make it silently do nothing.

It refuses more than it removes. A tree that PATH resolves a live binary through is a **refusal**, not a warning, until you accept that risk by name: `--force-blocked` accepts it alone and still asks, `--force` accepts it and skips the asking (`fullcycle` passes both) -- and the refusal keys on what PATH actually resolves, never on a directory name, because the binaries are in `debug/` on one project and `release/` on another. A tree with no manifest beside it to rebuild from is skipped and **reported with its size**: it is not a cache, it may be the only copy. Everything it declined to touch is printed, because a report that lists only its hits cannot be told from one that found nothing.

**Where the built-in ends and a project's own clean begins** (issue 0035). The built-in owns the language artefact trees it names -- cargo `target/`, Elixir `_build/`, Swift `.build/` -- wherever it finds them. A project's own clean scopes to what that project's own build produced and never re-sweeps the built-in's trees. So a project clean that runs an unscoped `cargo clean` is outside its boundary, and that can be seen as a violation, not missed as an omission. Measured in one consuming project: unscoped, that one command took 71090 files and 31.9GiB, against 11146 files and 1001MiB scoped.

## Constraints, stated up front

- **On Windows, WSL 2 is the prerequisite, and there is no native port** ([On Windows](#on-windows-wsl-2-and-nothing-native)). In a project that carries `intent/`, `check all` refuses at the critic gate there until Intent's Linux binary is installed.
- **bash >= 5.** `lib/helpers` checks the interpreter of every process that loads it -- the dispatcher and every built-in handler -- and the dispatcher also checks the bash PATH resolves, since that is the one `#!/usr/bin/env bash` handlers run on. Anything older is refused with a `brew install bash, or apt-get install bash` remediation. macOS ships `/bin/bash` 3.2.57, so on a stock Mac you need Homebrew's bash -- that refusal is deliberate. Devbin once targeted 3.2, and the floor was inverted to point at the bash its projects actually run (issue 0022).
- **No dependencies beyond bash and awk.** In particular **no `yq`**: the config reader is a single awk pass over a restricted YAML subset, so devbin needs nothing else installed. An optional YAML backend was designed and then rejected -- two implementations of "read the config" is a Highlander breach, and the second one was unreachable anyway, because the validator rejects everything the first could not parse.
- **The YAML subset is enforced, not merely expected.** Two-space indent, nested maps, scalar sequences, comments, quoted scalars. No tabs, no anchors, no block scalars, no flow collections, no sequences of maps. A file outside the subset is refused with the file and line, rather than half-read.
- **`run:` is split into words and never `eval`'d, and every word is a glob pattern.** Word splitting is wanted, and so is matching `bats opt/*/test` against the directory the command runs from; re-interpreting quotes and redirections out of a config file is not. A command line that needs real quoting needs a handler -- and that is the declarative boundary in one sentence.

## For the maintainer of a dev checkout

**This section is for whoever works on devbin itself, in a dev checkout of its repository.** A user installs from brew ([Install](#install)) and needs none of it.

devbin reaches a machine in the tiers dev, opt and brew, which are dev, stage and prod, as [the dev, opt and brew contract](docs/dev-opt-brew.md) has them for every tool released through Homebrew:

```
<checkout>                    dev    the dev checkout: edited, committed
<install.prefix>              opt    published from the checkout, only from a CLEAN tree
$HOMEBREW_PREFIX/opt/devbin   brew   the formula, published from a release tag
```

The dev checkout is the bleeding edge. The opt publish is a working copy of it, which keeps what works apart from what is mid-development, and the maintainer's own projects can vendor from it to try a build before it is released. The brew formula is the one publish to prod: what users install, and what every project seeds from. ("opt" names the tier; Homebrew's own `opt/` path, on the brew line, is a different thing.)

A project once vendored straight out of the working tree devbin is edited in. That tree can be dirty, and five of thirteen projects were running bytes stamped `+dirty -- THESE BYTES MATCH NO COMMIT` -- two of them vendored ten minutes apart from the same dirty tree, carrying byte-identical provenance over three differing files. That is why the opt tier exists, and why a publish refuses a dirty tree.

**The opt location is configuration, not devbin's.** It comes from `install.prefix` in devbin's own `bin/.devbin/config.yaml`, and there is no built-in default: `install` and `use opt` refuse by name when the key is unset rather than guess a directory under `$HOME`. `install` takes `--prefix <dir>` for a single run, but only in its PUBLISH mode -- inside devbin's own source tree. Passing it to a vendoring run is refused by name rather than ignored, because silently discarding it would publish to the configured location while the operator believed they had redirected it. See `docs/configuration.md`.

```zsh
cd <checkout>
bin/devbin install          # publish to opt -- refuses on a dirty tree
bin/devbin install --force  # replace the opt install, the one way to re-publish
bin/devbin use opt          # this machine runs opt (or: use dev, use brew)
```

An install is a project-shaped tree with the **project half missing** -- no `config.yaml`, no `cmd/`, no `help/` -- so `bin/devbin` refuses to start in it and it can only be vendored FROM. That refusal is structural rather than a check anyone can disable.

**Which tree the machine runs is `devbin use`'s alone** (`bin/devbin help use`). It keeps one link, `~/.local/bin/devbin`: `use dev` and `use opt` point it at the checkout or its opt install, and `use brew` removes it, so no link means brew. Every project on the machine reads the same switch for its next upgrade -- `DEVBIN_INSTALL_PREFIX`, else the tree the link leads to, else the brew install -- so a publish to opt moves nothing until `use opt` says so, and installing the formula moves nothing while the link names another tree. `use dev` and `use opt` run in the checkout, which knows where it is and its `install.prefix`. A project's own `bin/devbin` does not offer `use` at all: the switch is thrown from devbin itself, so a project's copy refuses it, naming `devbin use`. A bare `use`, and `doctor`, fail when `~/.local/bin` is not ahead of Homebrew's bin on PATH.

**Do not point the switch at the dev checkout unless you mean to.** `use dev` makes every project's next `upgrade` vendor whatever that tree is mid-development, and the project records `checkout`, with `+dirty` when the tree is dirty, so its manifest says so. `DEVBIN_SOURCE` places no project's source: it names a checkout that `dvb` falls back to when its walk finds nothing (`bin/devbin help shell-init`). Installing into a devbin source tree is refused outright: it runs `lib/` in place, so a vendored copy would sit ahead of the working tree in the search order and every edit would stop taking effect with the suite still green against the copy.

**The brew tier is published by a release.** The formula is a template in this tree, `packaging/homebrew/devbin.rb`, filled from git by `bin/devbin formula` (`bin/devbin help formula`), so no tag or commit in it is ever typed, and a cut publishes it to the tap once the tag is pushed: [docs/releasing.md](docs/releasing.md).

## Documentation

| Document                                                 | What is in it                                              |
| -------------------------------------------------------- | ---------------------------------------------------------- |
| [docs/configuration.md](docs/configuration.md)           | every `config.yaml` key, its type and its default          |
| [docs/authoring-commands.md](docs/authoring-commands.md) | adding a command end to end, and where its help comes from |
| [docs/migration.md](docs/migration.md)                   | taking an existing `bin/devbin` launcher onto devbin       |
| [docs/releasing.md](docs/releasing.md)                   | cutting a release, and the tripwires that have caught one  |
| [docs/dev-opt-brew.md](docs/dev-opt-brew.md)             | the dev, opt and brew contract every Homebrew tool follows |
| [CHANGELOG.md](CHANGELOG.md)                             | what changed in each release (generated)                   |
| [RELEASES.md](RELEASES.md)                               | the release index (generated)                              |
| `bin/.devbin/lib/config.reference.yaml`                  | the annotated worked example, vendored into your project   |
| `bin/.devbin/lib/infra.reference.yaml`                   | the annotated `infra` profile, vendored into your project  |

## Licence

devbin is released under the MIT licence: see [LICENSE](LICENSE).
