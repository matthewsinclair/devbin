# Authoring commands

How to add a command to your project's launcher, end to end.

The short version: **put an executable in `bin/.devbin/cmd/` and you are done.** Everything below is what you get for free once you have, and what to reach for when the default is not what you want.

## The fast path

```
$ bin/devbin new deploy --summary "Ship it" --group Ship
  wrote  bin/.devbin/cmd/deploy
  wrote  bin/.devbin/help/deploy.md
  wrote  tests/deploy.bats

bin/devbin deploy resolves now. Try:
  bin/devbin help deploy
  bin/devbin deploy
```

The files are all yours, none of them touched by `devbin upgrade` ever again. The handler is executable, carries its header, prints "not implemented yet" naming the file to edit, and **exits 3** -- "resolves but is not built yet" -- until you replace the placeholder. Its usage block prints on `-h`. Returning 0 from an unbuilt command is the false green the rest of this framework exists to prevent, so the scaffold refuses to do it for you.

The test stub is written only if the project already has a bats suite. `new` will not invent a test directory for you.

## How a command is found

One resolution order, applied at every level and at any depth:

| Order | Source                                        | For                                                                                |
| ----- | --------------------------------------------- | ---------------------------------------------------------------------------------- |
| 1     | `bin/.devbin/cmd/<name>`                      | your handler; **shadows a built-in of the same name**                              |
| 2     | `commands.<name>.handler` in config           | a file whose name differs from the command                                         |
| 3     | `commands.<name>.run` in config               | a declarative one-liner                                                            |
| 4     | `bin/.devbin/lib/cmd/<name>`                  | the built-in devbin ships                                                          |
| 5     | the catalogue's command line (`lib/builtins`) | a built-in with one command line and no handler                                    |
| 6     | -                                             | a command with options prints its usage, exit 1; otherwise exit 3, not implemented |

A name that is not an active command here never reaches this table: the dispatcher refuses it first, exit 2, with a `help` hint. A config `handler:` counts as your handler, as a file in `cmd/` does, so it outranks a `run:` for the same command. A config `handler:` and a `run:` sit **above** the built-in devbin ships deliberately. Putting devbin's own handler first means a built-in silently swallows something your config plainly declared, which is a defect that has been fixed twice here already.

**Shadowing is total.** When your handler, or a command-level `run:`, takes over a built-in's name, the built-in's *option set* stops applying too -- only config-declared options remain. A project replacing `test` is saying its gates are different, so inheriting `mix|credo|rust` would synthesise an `all` that calls your handler with options it has never heard of. A `run:` line shadows the same way since issue 0128: until then `clean all` in a project whose `commands.clean.run` decided what was removed swept devbin's own arms. A config-declared option with no `run:` of its own is handed to the command's line as its first word, exactly as an undeclared word is.

## Naming: when the file and the command differ

The contrived case from the original brief, and the reason `handler:` exists. You have `bin/.devbin/cmd/myls` and you want to type `devbin ls`:

```yaml
commands:
  ls:
    handler: myls
    summary: List things (contrived example)
    group: Surfaces
```

Without that entry the file registers as `myls` and `devbin ls` does not exist. With it, `devbin ls` runs `cmd/myls`, appears under `Surfaces` in help as `ls`, and `devbin help ls` reads `help/ls.md` -- the **command** name, not the file name, is what everything else keys on.

## Each field, one source

Help shows a command's `summary`, `group` and `args`. Each is read from exactly one place, in this order:

| Order | Source                               | Applies to                         |
| ----- | ------------------------------------ | ---------------------------------- |
| 1     | `commands.<cmd>.<field>` in config   | anything; your wording always wins |
| 2     | the handler's own `# devbin:` header | commands **you** ship              |
| 3     | the built-in catalogue               | commands **devbin** ships          |

The load-bearing part is that the handler's header and the catalogue never both answer. A command devbin ships is declared by its catalogue row; a command you ship is declared by your handler file. The two sets are disjoint by construction, so there is no precedence question between them to get wrong later.

That is why `lib/cmd/*` carries no header, and a test enforces it. They used to: every shipped handler had a `# devbin: summary = ...` line that nothing read, duplicating the sentence in its catalogue row -- and two copies written at the same time had already drifted by a word before anything came to read one.

### The header block

```bash
#!/usr/bin/env bash
#
# devbin: summary = Ship it
# devbin: group = Ship
#
```

The recognised fields are `summary`, `group` and `args` (the usage hint in help's left column). Delete a line to drop that field. The header is what makes a script dropped into `cmd/` self-describing: it appears in help, in its right group, with no config edit at all.

## What a handler receives

**A handler is a separate process.** It is `exec`'d, not sourced, so it never reads config and nothing it sets comes back. What crosses is the environment:

| Variable                  | What it is                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `DEVBIN_NAME`             | the project name, for messages                                                                                           |
| `DEVBIN_INVOKE`           | how to invoke this devbin from where you were called, for hints                                                          |
| `PROJECT_ROOT`            | the project root, whichever directory you were called from                                                               |
| `BIN_DIR`                 | the project's `bin/`                                                                                                     |
| `DEVBIN_DIR`              | the project's `bin/.devbin/`                                                                                             |
| `<NAME>_ROOT`             | the same path under your `project.root_var` name                                                                         |
| `DEVBIN_ROOT_VAR`         | that variable's name, `<NAME>_ROOT`                                                                                      |
| `DEVBIN_LIB`              | the runtime, for sourcing helpers                                                                                        |
| `DEVBIN_COMMAND`          | the name this was invoked as                                                                                             |
| `DEVBIN_VERSION_FILE`     | where the project version lives                                                                                          |
| `DEVBIN_VERSION_SIDECARS` | the files that mirror the version (`project.version_sidecars`), one per line                                             |
| `DEVBIN_CLI_TASK`         | the mix task `cli` and `repl` call (`project.cli_task`)                                                                  |
| `DEVBIN_LANGUAGES`        | the declared `project.languages`, one per line                                                                           |
| `DEVBIN_FMT_ARMS`         | how `check format` treats each declared language's fmt arm: space-separated `<lang>=builtin`, `overridden` or `disabled` |
| `DEVBIN_ACTIVE_<CMD>`     | when running `check`, `clean`, `db`, `docs`, `fmt` or `test`: its active options                                         |
| `DEVBIN_RUN_ID`           | this invocation's identity, inherited by a child devbin unless the child starts a witness run                            |
| `DEVBIN_RUN_WITNESS`      | `1` when this invocation is a witness run, which takes an id of its own rather than its parent's; else `0`               |
| `DEVBIN_RUN_STAMP`        | the UTC stamp (`YYYYMMDD-HHMM`) this invocation's sealed logs are named from                                             |
| `DEVBIN_RUN_REFERENT`     | what `project.referent` printed, when declared; a `REFERENT UNAVAILABLE` line if it printed nothing                      |
| `DEVBIN_GATE_TTY`         | set by `gate_exec` for what it runs: `1` when a person was at the terminal, else `0`                                     |
| `DEVBIN_IN_GATE`          | `1` for what a gate runs, which keeps the gate's flag; a devbin started there drops it                                   |
| your shared options       | each under the `export:` name you declared                                                                               |
| `DEVBIN_OPT_<NAME>`       | framework-owned options, under devbin's canonical name                                                                   |

**Shared options are parsed once**, in the dispatcher, and exported. Your handler inherits them without knowing they exist. What reaches your command line is only what devbin did not recognise, which is what lets `devbin test mix --trace` pass `--trace` through to `mix` untouched.

Devbin owns a small set of options itself so that the built-ins it ships can read them under a canonical name -- currently just `--iex`, for `server`. **A framework-owned option is offered where the commands that CONSUME it are active**, so `--iex` appears in an Elixir project that runs a server and not in a library that has switched `server` off. If your project wants one anyway, declare it in `options:` like any other: config always wins on shape.

`--iex` selects a server's IEx form. It is not a general "run this in IEx" modifier, and passing it to a command that does not read it is refused rather than ignored:

    $ bin/devbin cli --iex
    demo: 'bin/devbin cli --iex' is not available here: --iex applies to: server

If one of **your** handlers reads `DEVBIN_OPT_IEX` -- picking a different command line under the flag, the way the shipped `server` does -- devbin cannot know that by looking, so name it:

    options:
      iex:
        commands:
          - web

That extends devbin's own consumer set; it never replaces it. `commands:` says who READS the option and nothing about its shape, so declaring it alone leaves `--iex` a flag.

Source `helpers`:

```bash
: "${DEVBIN_LIB:?run me through the devbin dispatcher}"
. "$DEVBIN_LIB/helpers"
```

`lib/helpers` has no dependencies by rule, so this costs you nothing. It gives you `die`, `warn`, `abs_path`, `read_version`, colours, and the rest of the primitives, among them:

| Helper                            | What it does                                                                                                                                                                              |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ask_person <question>`           | asks `<question> [y/N]` on `/dev/tty`: 0 for y or yes in any case, 1 for anything else, 2 when nobody can be asked -- no readable `/dev/tty`, or `DEVBIN_GATE_TTY` is not `1`             |
| `run_words <array> <key> <value>` | fills `<array>` with the words a declared command line runs as: split on space, tab and newline, each word a glob pattern, never eval'd; a value with no words is refused, naming `<key>` |
| `semver_gt <a> <b>`               | true when X.Y.Z `<a>` is greater than `<b>`, part by part and numerically; 2 when either is not X.Y.Z                                                                                     |
| `follow_links <path>`             | the file at the end of `<path>`'s chain of links; a link that leads to no file is refused                                                                                                 |
| `replace_file <file> <cmd>...`    | replaces `<file>` with what `<cmd>` prints, staged beside it and renamed over it; its mode is kept, and a link to it stays a link                                                         |
| `stage_beside`, `rename_staged`   | the two halves of `replace_file`, for a caller that renames the staged file itself                                                                                                        |
| `git_readonly <git-args>...`      | git as a read: no optional locks, no fsmonitor, and git's repository-local environment cleared                                                                                            |
| `generated_doc_write`             | a document section regenerated from your own probes -- see below                                                                                                                          |
| `gate_exec <cmd>...`              | runs `<cmd>` as a gated tool runs: stdin from /dev/null, and `DEVBIN_GATE_TTY` saying whether a person is there (read from stdin, or kept inside a gate)                                  |

A handler that runs a gate tool directly -- a formatter, a test runner, anything that might prompt -- runs it through `gate_exec`, so the tool reads EOF rather than blocking on a terminal while `DEVBIN_GATE_TTY` still says whether a person is there; it is in `helpers`, so a scaffolded handler reaches it. A handler that drives a sealed gate itself sources `runlog` as well, which brings `helpers` if it is not loaded yet. That is where `run_gate` lives, which runs its tool through `gate_exec`. `stdin_tty_flag`, in `helpers`, prints `1` when stdin is a terminal and `0` otherwise -- the one rule `DEVBIN_GATE_TTY` is set by. A handler that must ask a person before any gate opens sets the flag from its own stdin for that one call, as `fullcycle` does: `DEVBIN_GATE_TTY="$(stdin_tty_flag)" ask_person "Proceed?"`.

### The build's git identity

Devbin owns the version NUMBER completely -- `version_from`, the sidecars, `version sync`. Of the git identity it owns exactly the shared half:

```bash
. "$DEVBIN_LIB/helpers"

sha="$(git_head_sha)"        # the short sha, or `unknown`
git_head_watch_paths         # the files whose mtime tracks HEAD, one per line
```

The first is the half nobody gets wrong. The second is the half four independent implementations got wrong the same way, by naming git's internals literally:

    .git/HEAD        .git/refs/heads/

**In a linked worktree neither exists.** `.git` is a file reading `gitdir: <path>`; the ref that actually moves on a commit lives in the COMMON directory, because a worktree's own `HEAD` holds `ref: refs/heads/<branch>` and that string never changes; and `git pack-refs` deletes the loose ref file outright, so a branch living only in `packed-refs` drops out of any watch set built from loose paths. These are the layout rules. `git_head_watch_paths` asks git, which already knows them all.

**It emits file paths and declares nothing**, which is what lets one function serve every toolchain -- you state the dependency in your own vocabulary:

| Toolchain | What you write with each path              |
| --------- | ------------------------------------------ |
| cargo     | `println!("cargo:rerun-if-changed={}", p)` |
| Elixir    | `@external_resource p`                     |
| make      | list them as prerequisites                 |
| Docker    | `COPY` them into the build context         |

**An empty watch set is a failure and it refuses loudly.** A build that bakes the sha with nothing watched can never refresh it. Before a working watch existed the failure mode was "always rebuild", which hides as a cost rather than a defect; restoring the watch restores caching, so a silently empty list would turn a slow-but-correct build into a fast and possibly wrong one.

If you test your own use of this, **the fixture has to be a real `git worktree add`** -- a test written in a normal checkout passes against the broken literal paths, which is how the defect survived a working day. Assert on the resolved path SET rather than on the sha: under cargo the sha stays correct while the mechanism is entirely broken.

## Exit codes are a contract

This table is the one place devbin's exit codes are listed.

| Code | Means                                                                           |
| ---- | ------------------------------------------------------------------------------- |
| 0    | it worked                                                                       |
| 1    | the command's own failure, **or a usage error**                                 |
| 2    | unknown command, or one scoped out of this project                              |
| 3    | resolves, but nothing here implements it                                        |
| 4    | wrong tree: the dispatcher refusing to act on a project you are not standing in |
| 5    | install tree: the dispatcher refusing to run from a machine install             |
| 6    | devbin's own trees only: `use` refused in a project that vendors devbin         |

The one worth spelling out: **a bare command that needs an option exits 1, not 0.** It prints its usage either way, but naming no option is a usage error, and `devbin test && deploy` reads a 0 as permission to deploy. An explicit `-h` or `--help` still exits 0 -- that request succeeded.

**A new refusal takes a new code, never a spare one.** Many assertions turn on the 2, so a wrong-tree guard sharing it would let a test that asserts an unknown-command refusal be satisfied by a wrong-tree refusal instead, and a green would stop naming its own cause. Two documents once restated this list, and both went stale in the same instant when the 4 shipped. `tests/unit/documentation.bats` holds this table to the `exit` statements in the source in both directions, so a code shipped without a row here fails the suite, and so does a row naming a code the source cannot return.

## Sub-commands

Drop an executable at `cmd/<name>.d/<word>` and `devbin <name> <word>` routes to it. The same rule, at any depth:

```
bin/.devbin/cmd/db                 devbin db
bin/.devbin/cmd/db.d/sql           devbin db sql
bin/.devbin/cmd/db.d/sql.d/dump    devbin db sql dump
```

A word with **no** handler behind it stops the descent and arrives at the enclosing handler as an ordinary argument. That is what keeps `devbin db sql "select 1"` working: `select 1` is not a sub-handler, so `sql` runs and receives it.

### Checks of your own in `doctor`

`doctor` is the one built-in that reads a `.d` directory of yours: **every executable in `cmd/doctor.d/` runs after devbin's own checks**, counted into the same summary, and `devbin doctor <check>` runs one alone. So a project's preconditions -- tools on PATH, config present, a host reachable, a credential available -- go in `doctor` without replacing it. A handler at `cmd/doctor` still replaces devbin's doctor outright, for a project that wants that.

A check runs from the project root with no input. A line whose first word is `ok`, `FAIL` or `note` counts as devbin's own do, and anything else is shown under it:

```bash
#!/usr/bin/env bash
# bin/.devbin/cmd/doctor.d/tools
for t in rg jq op; do
  if command -v "$t" >/dev/null; then echo "ok    $t on PATH"; else echo "FAIL  $t is not on PATH"; fi
done
```

Its exit status counts too, and neither hides the other: a non-zero exit with no `FAIL` line fails, naming the exit, and a `FAIL` line fails even if the check exits 0. A check that exits 0 and prints nothing is one pass. A file there that is not executable is reported and not run. A check is not time-limited, so one that reaches another machine should bound itself -- `ssh -o BatchMode=yes -o ConnectTimeout=5`, say.

## Sub-options, and the free `all`

Sub-options are the *declarative* alternative to sub-commands, and they are what gates are built from. Declare them in config:

```yaml
commands:
  check:
    group: Check
    summary: Read-only gates; each exits non-zero on a breach
    options:
      compile:
        summary: Compile with warnings as errors
        run: mix compile --warnings-as-errors --force
        grammar: mix
        log: COMPILE
      format:
        summary: Formatting is up to date
        run: mix format --check-formatted
        grammar: generic
        log: FORMAT
```

You now have `check compile`, `check format`, and -- without writing it -- **`check all`**.

`all` is synthesised from the option list for any command with at least one option, and it:

- runs **every** option in declared order and does not stop at the first breach, because one pass that surfaces all failures beats N round trips
- lets each option seal its own verdict; the aggregate summary is a convenience, never the record
- exits non-zero if any option failed, naming all of them
- reports options marked `in_all: false` as **skipped**, never dropping them silently
- prints one count line on every path -- `5 of 10 check options ran; 5 inactive here (bin/devbin help --why names them), 0 skipped (in_all: false)` -- so an option deactivated by language scope or `enabled: false` is counted rather than invisible, and `help --why` names each one with its reason
- **refuses a verdict** unless every option the command could offer is accounted for exactly once as ran, skipped or inactive: a summary that covers fewer options than it counts is a false green, so a run that cannot account for one names it and exits non-zero

Adding an option to config puts it in `all` in the same edit. The two cannot disagree, because there is only one list.

`all` is devbin's wherever the command has options to sweep -- config-declared ones compose with a project handler, so the sweep survives the shadow -- and a sub-handler named `all` can never replace it. `devbin help <cmd>` always lists it last. Where there are no options, what happens depends on what runs the command. A full project handler with **no** declared options shadows totally and is handed `all` like any other argument, and a built-in devbin ships with no options answers for itself: `server`, `iex`, `cli` and `repl` hand it to the program they run, and the rest refuse it. A command-level `run:` with no option to run, none declared or every declared one switched off, is refused, exit 1, and the refusal names the bare command: devbin runs that line, and `all` added to it would be a new command. `commands.test.run: cargo test` would run `cargo test all`, a name filter that matches nothing, and pass.

## Making your command a sealed gate

**A gate's verdict is a file, not terminal output.** Add `log:` to an option, or to a command declared with a `run:` of its own, and it runs through the sealed runner:

```
tmp/<command>/<stamp>.<SUFFIX>.out       everything the run printed
tmp/<command>/<stamp>.<SUFFIX>.errors    the extracted failures
```

The `.errors` companion is **empty exactly when a completed run was green**. That is the contract CI reads. A run that was killed halfway leaves a non-empty `.errors`, so an interrupted gate can never read as a pass.

`log:` is read where devbin runs the command line itself: a `run:` in your config. A catalogue option seals on its own row, and a `run:` that overrides one inherits the row's `log:` and `grammar:` unless it declares its own. **Under a project handler `log:` is not read.** A declared option of a command you have a handler for dispatches into that handler with the option's name as its first argument, unsealed, so a handler that wants a seal calls `run_gate` itself. A `log:` that nothing reads, in any of these places, fails `bin/devbin doctor`, which names what runs instead (issue 0133).

**`--purge` keeps the newest five runs of a gate family, not only the current one.** An intermittent failure is diagnosed by diffing a red run against the green one before it, so purging the previous run destroys the differential at the moment it becomes interesting. `RUNLOG_KEEP_RUNS` sets the window and `1` restores the older keep-current-only behaviour. **`0` is refused rather than read as "keep everything"** -- a zero meaning unlimited is not how a variable named KEEP reads, and the refusal is tested to purge *nothing*, because a validator that fails open deletes more than no validator at all.

**These flags belong to the gate, not to the tool: `--purge`, `--purge-only` and `--allow-empty`.** Typed anywhere on a gate's command line they are taken out of the tool's arguments and given to the runner, at every gate devbin runs -- an option's, a catalogue one, and a command-level `run:` with `log:`, which handed them to the tool until issue `0087`. `--purge-only` purges against the newest kept run without running anything. `--allow-empty` says this run executing no tests is intended, so it is not promoted to a failure; declaring `grammar: generic` says the gate is never a counted run at all. Everything else reaches the tool.

`grammar:` names the extractor that turns the tool's output into that file: `mix`, `credo`, `cargo`, `xcodebuild`, `lua`, `shell`, `bats`, `critic`, `generic`. Declare `log:` and `grammar:` together -- a thing is a sealed gate or it is not, never half of one. Devbin's own catalogue holds to that. For an option of your own it is not enforced: a `grammar:` with no `log:` runs unsealed, and the grammar is never read.

**Omit `log:` for anything long-running or interactive.** A server or a REPL never exits, so teeing it would buffer the output you are watching and seal nothing.

**A gated tool reads no input: its stdin is `/dev/null`, from a terminal as from CI.** That covers a sealed `run:` in your config, a catalogue command line, devbin's own built-in verbs, and every tool one of them starts. A gate that handed its tool the terminal measured something different for a person than for an agent or CI: a tool that asks (`Shall I install Hex? [Yn]`) waited at a person's keyboard and read end-of-input everywhere else (issue `0088`). Now every run takes the end-of-input path, so a tool that needs an answer fails the same way everywhere. There is no key to hand such a gate the terminal; a command that needs one runs bare. **The gate still says whether a person is there**: it sets `DEVBIN_GATE_TTY` to `1` when its own stdin is a terminal and `0` otherwise, and `clean`, `fullcycle` and a release cut ask on that flag through `ask_person`, reading the answer from `/dev/tty`. A tool the gate runs keeps that answer, through `DEVBIN_IN_GATE`, so a release's `after:` line can still ask the person who started the cut, while a devbin started inside the gate is a new invocation and reads its own stdin again. A tool that opens `/dev/tty` itself is outside this.

A gate that examines nothing and exits 0 is a false green, which is why `check format` **fails** when its formatter is missing while `fmt` merely skips. The gate asserts a verdict; the formatter does not.

## Where help text comes from

Different mechanisms, deliberately:

**`devbin help`** -- the global listing -- is **generated** from what actually resolves. There is no list to maintain, and it cannot drift: it can neither show a command that does not resolve nor omit one that does.

**`devbin help <cmd>`** -- the detail -- is **authored** markdown, looked for in two places, yours first. Your own page is `bin/.devbin/help/<cmd>.md`. For one of devbin's built-ins that your project has not taken over -- no handler of yours at that name, mapped or not, and no command-level `run:` -- the page devbin ships for it comes next, from inside the vendored runtime, so every project has it without writing it. Sub-topics live at `<cmd>.d/<sub>.md` in either place and resolve by the same descent handlers use, at any depth:

```
bin/.devbin/help/test.md           devbin help test
bin/.devbin/help/test.d/mix.md     devbin help test mix
```

**Your page replaces the generated answer; it never appends.** Your file is the answer, in full, and it answers before devbin's for the same command; for a built-in not offered here, it answers beneath the line that says so. Devbin's own page is generic -- it describes the built-in, not your project -- so, where the command is offered here, it is followed by an `In this project:` block: the command's origin, each active option with its own, and each option not offered here, with the reason.

**A built-in your project does not offer still has its page.** For a built-in devbin ships that your project does not offer -- an opt-in not enabled, a language not declared, every option it offers inactive, switched off or held back, or the command switched off with `enabled: false` -- help prints the page, yours first, beneath a line saying why it is not offered here and what would offer it, with no `In this project:` block, at exit 0, so you can read `devbin help release` before you enable `release`. Help refuses instead, exit 2, with no page: for a command devbin does not ship; for a built-in your project owns with no page of its own, since devbin's would describe code that is not yours; for one whose `bin/.devbin/cmd/<cmd>` is there but not executable, since the `chmod +x` its line names makes it yours; and for devbin's `use`, which is the machine's, run as `devbin use`. A command not offered here answers its own `--help` and `-h`, wherever they stand among its arguments, as `devbin help <cmd>` does, page or refusal, with help's exit code; the rest of its arguments are not read, so a bad shared-option value beside them cannot turn the answer into a refusal. Running it is still refused, exit 2 (6 for `use`), and where help prints its page the refusal names `devbin help <cmd>`.

With no page at all, help does **not** print a blank page or a bare summary. It prints what devbin already knows -- the summary, the usage hint, the active option list, where the command resolved from, and, for a command that is yours, where to write the file:

```
$ bin/devbin help deploy
bin/devbin deploy

Ship it somewhere

Resolves from: config commands.deploy.run

No authored detail yet. Write it at bin/.devbin/help/deploy.md
```

For one of devbin's built-ins that ships no page, the last line says so instead of asking you to write devbin's documentation.

An empty page would be the framework declining to say what it plainly knows.

## When a command is missing, ask why

```
$ bin/devbin help --why
```

This prints the listing with each command annotated by where it resolved from, and then names every command and option devbin ships that is **not** offered here, with the reason -- a language not declared, an opt-in not enabled, or switched off with `enabled: false`. A handler shadowing a built-in is not one of those: it shows in the listing itself, on that command's `from:` line.

It exists because resolution order and language scoping were computed and never displayed, so a command scoped out of your project showed nothing at all, and absence is indistinguishable from a defect.

## A worked example, start to finish

The contrived `ls`, built the way you would actually build it.

```
$ bin/devbin new myls --summary "List things (contrived example)" --group Surfaces
  wrote  bin/.devbin/cmd/myls
  wrote  bin/.devbin/help/myls.md
  wrote  tests/myls.bats
```

Write the body:

```bash
main() {
  case "${1:-}" in
    -h | --help)
      usage
      return 0
      ;;
  esac
  ls -la "${1:-$PROJECT_ROOT}"
}
```

At this point `devbin myls` works and appears under `Surfaces`. To call it `ls` instead, name it in config:

```yaml
commands:
  ls:
    handler: myls
    summary: List things (contrived example)
    group: Surfaces
```

Now rename the help file. **Help is keyed on the command, not the file**, so it has to become `ls.md` -- and its *contents* are yours to update, since `new` wrote them for a command called `myls`:

```
$ mv bin/.devbin/help/myls.md bin/.devbin/help/ls.md
```

Check the result:

```
$ bin/devbin help --why | grep -A1 '^  ls '
  ls                    List things (contrived example)
                        from: project handler myls (mapped)
```

`(mapped)` is help telling you the command name and the file name differ here -- which is the one thing about this arrangement that is easy to forget six months later.

## Testing your command

`devbin new` writes a stub whose first test asserts the command **resolves** -- the one thing a scaffold can know is true. Some hard-won cautions for the rest:

- **bats evaluates every test description.** Backticks or `$(...)` in a test *name* execute. There is a structural test in this repo refusing that shape, because one such name ran the entire suite from inside a test title and every TAP line still said `ok`.
- **Do not read a run by grepping `^ok` / `^not ok`.** Read the non-TAP lines: `grep -vE "^(ok |not ok |1\.\.|#)"` should print nothing.
- **Ask what else would make your test green.** Tests here have passed for the wrong reason -- one used a project handler to test built-in scoping and so exercised the shadowing path instead of the path under test.

## Rules of thumb

| If you are...                                       | Reach for                                     |
| --------------------------------------------------- | --------------------------------------------- |
| running one fixed command line                      | `run:` in config                              |
| running one command line **with a quoted argument** | a handler -- `run:` cannot express it         |
| branching on anything                               | a handler; the YAML never grows control flow  |
| adding a gate to an existing command                | an option with `log:` and `grammar:`          |
| adding a verb under a command                       | `cmd/<name>.d/<word>`                         |
| adding a check to `doctor`                          | `cmd/doctor.d/<check>`                        |
| renaming what a file is called                      | `commands.<cmd>.handler`                      |
| writing more than a paragraph of help               | `help/<cmd>.md`                               |
| naming infrastructure -- a host, cluster, org, id   | a config key, never a constant in the handler |

## Do not inline infrastructure identity

A handler that hardcodes a cluster id, a hostname, an org or a bucket is holding a fact that something outside your repository is free to change, and the failure is usually silent rather than loud: the old name keeps resolving to something.

Measured: a `db proxy` handler carried a Fly cluster hostname inline. The provider re-identified the cluster during a migration, the legacy alias went on routing, and the handler resolved a dead identity for five days without a single error. Nothing was broken enough to notice.

Name it in `config.yaml` and read it in the handler. Devbin already draws this line for itself -- `project.version_from` names the file and the library holds the recipe -- and it is the same rule one layer out: **config names FACTS, code holds RECIPES.** A fact that lives in someone else's control panel is exactly the kind that must be nameable without editing a script.

## Generating a document from live measurements

A handler that regenerates part of a document from probes -- a database runbook, an inventory, a topology -- gets the writing discipline from devbin and keeps the probing entirely to itself:

```bash
. "$DEVBIN_LIB/helpers"

fly_facts() {                       # YOUR producer. Devbin never reads it.
  fly status --json --app "$APP" || return 1
  psql "$DSN" -c '\dx' || return 1
}

generated_doc_write \
  --target config/.fly/database.md \
  --begin  'FACTS-BEGIN' --end 'FACTS-END' \
  --deny-env PGPASSWORD --deny-env FLY_API_TOKEN \
  --expect-lines 8 --expect-contains 'extensions:' \
  -- fly_facts
```

**Devbin does not learn what you are measuring.** Not what a cluster is, not what a pooler is, not that `--json` exists on anything, and not that your document is Markdown -- the markers are opaque delimiters, which is why they are required rather than defaulted. A project on a different provider writes a different producer and none of the above changes.

That split is deliberate and it is the whole rule. The provider verbs are cheap to write and trivial to verify, because you can just run them. What is expensive, and what four projects were each about to reinvent, is the discipline of writing the result down safely.

### The refusals, and what each one is for

| Refusal  | What it does                                                          |
| -------- | --------------------------------------------------------------------- |
| producer | a non-zero exit or empty output leaves the target untouched           |
| secret   | `--deny-env VAR` refuses if VAR's VALUE appears in the produced block |
| artefact | `--expect-lines` / `--expect-contains` refuse insufficient output     |
| markers  | prose outside the markers is copied through; both must appear once    |
| atomic   | assembled in a temp beside the target and renamed, never written open |

**The producer refusal is the determinate-zero doctrine in prose.** A document assembled from failed probes is worse than a stale one, because it looks freshly generated. Measured: a project captured `psql` error text into a runbook and then reported grant counts off it -- a refuted inference wearing the format of a measurement. So your producer must exit non-zero when a measurement failed; that exit status is the only thing standing between a failed probe and a confident-looking document.

**The secret refusal wants env indirection, not omission.** Emit `postgresql://user:$PGPASSWORD@host/db` -- the shape is documented and the value is not. `--deny-env` then proves you did, mechanically, on every run rather than at review time. Naming a variable that is unset or empty is itself a refusal: a guard that cannot see its secret must not pass silently.

**The artefact refusal exists because a producer exiting 0 says it RAN.** It does not say it produced the document. Declare what sufficient output looks like and let devbin refuse the rest; there is no built-in threshold, because a framework guessing at one would guess wrong for everybody.

### The half this cannot check

Everything outside the markers is hand-authored and stays that way, which is the point -- a probe can report a pooler's port and can never report that changing it needs the owner's say-so. **Nothing here proof-reads that half.** You cannot check a generator against a document nobody has read, so the manual audit of the authored prose is a separate job and remains one.
