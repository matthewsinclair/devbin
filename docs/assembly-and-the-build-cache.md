# Devbin's Build Cache for Optimised Release Assembly

devbin keeps a registry of built artefacts on each machine, keyed on the inputs a build reads. A build whose inputs have not changed pulls what it built before instead of building again. This note describes the cache as it is built: why it exists, how a key is made, where the registry lives, what each verb answers, how a release cut uses it, and what it refuses to do. A how-to for a project's maintainer follows.

`bin/devbin help cache` is the reference for the verbs' answers, and [the configuration guide](configuration.md#build) is the reference for the `build:` block's keys. This note explains them together.

## Why

A release builds the same thing more than once. A cut that goes red on one leg is run again after the fix, and the fix usually leaves the build's inputs as they were, so the second cut builds the same bytes again. A pre-push hook that clones the tree cold and builds it rebuilds what the working tree has already built. A deploy that compiles a production release twice compiles the same inputs twice.

When the cache was designed, the release records showed these repeats:

| Project                         | What repeats                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------ |
| a Rust command-line tool        | twelve release-profile builds per release, ten of them cold on CI runners      |
| Intent                          | its pair of binaries built at the tag, then again in its pre-push hook's clone |
| an Elixir application           | its production release compiled twice per deploy                               |
| a macOS app with a Rust backend | three cargo builds and one `xcodebuild` per cut                                |

The cache's answer is the one that CI, CD and assembly tools use: record each artefact against the hash of what it was built from, and when that hash comes round again, pull the artefact by its hash instead of rebuilding it.

devbin itself builds nothing. Its suite is a gate, and the gates' seal (`tmp/release/<stamp>.GATES.{out,errors}`) is that gate's cache: a sealed green that stands for the release commit is not run again.

## The key

An artefact's key is the sha256 of a set of lines, sorted:

- one line `<path><TAB><object id>` for each of the artefact's input paths at the commit, the id being git's own for that path: a tree id for a directory, a blob id for a file;
- `toolchain<TAB><id>`, the tool's own version line;
- `platform<TAB><word>`, this host's platform word, `macos` or `linux`;
- `arch<TAB><word>`, the CPU architecture as `uname -m` names it, eg `arm64`, `aarch64` or `x86_64`.

**Git's tree and blob ids, not the commit.** A commit that changes only docs, the whiteboard or anything else outside the inputs leaves every input's id as it was, so the key stands and the artefact is pulled. This is the whole of the saving on a re-cut after a red leg. Git has already hashed the files, and `git rev-parse <commit>:<path>` reads an object without a checkout, so a commit's key exists before any worktree is made for it, and the key is the same in every clone.

**The toolchain**, because the same inputs under another compiler make another artefact. The core reads the version from a built-in table keyed on the artefact's `tool` word, so no project writes a version anywhere:

| `tool`       | Asked                 | The line the key takes                                      |
| ------------ | --------------------- | ----------------------------------------------------------- |
| `cargo`      | `cargo --version`     | its first line                                              |
| `swift`      | `swift --version`     | its first line                                              |
| `xcodebuild` | `xcodebuild -version` | its lines, joined                                           |
| `elixir`     | `elixir --version`    | the Erlang/OTP release and its erts, then Elixir's own line |

Elixir's first line also carries the emulator's flags (eg `[smp:8:8]`, `[jit]`), which follow the host's CPU count and `ERL_FLAGS`, not what a build makes, so the key leaves them out. cargo is asked in `project.cargo_root`, where rustup reads a `rust-toolchain` file; every other tool is asked at the project root. So the key never depends on the directory a command was run from.

**The platform and the architecture**, because a built artefact is for one platform and one CPU. Without the `arch` line, an x86_64 runner and an arm64 runner would share a key, and the arm64 job would pull the x86_64 binary.

**A dirty input has no key.** At HEAD, an input path with uncommitted or untracked changes is no commit's object, so `key` and `put` refuse it with a line naming the path. The build then runs and nothing is recorded. A key is held to its form, 64 lowercase hex digits, before any path is made from it, and it is always printed whole, never cut.

What the key is durable against, then: any commit outside the inputs, a different clone, a different working directory, and the emulator's flags. What changes it: any change to an input path's content, a different toolchain version, another platform, another CPU architecture.

## The declaration

A project declares its artefacts once, in a `build:` block in `bin/.devbin/config.yaml`:

```yaml
build:
  inputs:
    - Cargo.toml
    - Cargo.lock
    - src
  artefacts:
    app:
      tool: cargo
      path: target/release/app
```

- `build.inputs` lists the input paths every artefact reads. An artefact's own `inputs` list narrows it where that artefact reads fewer.
- `tool` is one of the toolchain table's words: `cargo`, `elixir`, `swift` or `xcodebuild`.
- `path` is what the build writes. `put` records it and `get` writes it back.

The block is written in block form, since devbin's config parser refuses YAML's flow collections (`[...]` and `{...}`). Every path is relative to the project root and written once, as git names it.

Because a pull replaces whatever is at the artefact's path, config validation refuses, when the config is read:

- a key the block does not know, and a tool word outside the table;
- an artefact name that does not start with a letter or a digit, so none reads as an option;
- a path that is empty, absolute, holds an empty, `.` or `..` segment, or lies in `.git` in any case of its letters;
- an artefact's `path` that is, holds or lies in any input path the block declares, compared in any case of its letters, since a case-folding filesystem such as macOS's reads `readme` and `README` as one file.

`get` also refuses a `path` the repository tracks files at, in any case of its letters, before it reads or removes anything. So a pull never writes outside the project, over it, or over an input's working tree, and one path never makes two keys.

Two rules apply to a macOS app, where an artefact's `path` is `macos.app`'s:

- With `macos.commit_stamp` declared, the artefact is refused. The app carries the commit it was built at, and the key holds no commit, so a copy pulled at a later commit would be another commit's build, which `macos app-sign` refuses.
- When the artefact's inputs hold no file the app's version is read from (`macos.version_from` where declared, else the project's version file), the artefact is refused. A release that moved only the version would keep the key, and the pulled copy would carry the old version. Name that file among the artefact's inputs.

Two artefacts at `macos.app`'s path are refused too, so the macOS stage never has to guess which one to pull.

## The registry

The registry's root is the environment variable `DEVBIN_CACHE_HOME`, an absolute path. Unset or empty, it is `devbin` under the XDG cache directory: `$XDG_CACHE_HOME/devbin` where that is an absolute path, else `~/.cache/devbin`. No shipped file names any other root, so each machine puts its cache wherever it likes.

Under the root there is one directory per project, one per artefact under that, and one per key under that:

```
<root>/<project>/<artefact>/<key>/
  artefact        the file, or artefact.tar for a directory's contents
  manifest.yaml   the entry's provenance
  SHA256SUMS      over the artefact and the manifest
```

`manifest.yaml` records the project, the artefact, the key and each of the lines it was made from, the commit the build ran at, whether the tree was clean outside the inputs, the host, the clock in UTC, the artefact's size and its sha256. It is YAML because the core already reads YAML, and a person can read it too.

**What an entry keeps.**

- A file is copied with its mode and times (and on macOS whatever extended attributes or ACL it holds), with no file flags.
- A directory is recorded as a tar of its own contents: its files and their mode bits, with no owner, no extended attributes, no ACLs and no file flags. A pull writes them back at the path the declaration names then.

File flags are dropped because a flag such as `uchg` or `uappnd` on the registry's copy would leave an entry that nothing could replace or remove.

There is one registry per machine, since an artefact is for its platform. A remote leg's host keeps its own registry, and the remote-leg runner copies seals back to the cutting machine, never artefacts. Nothing is fetched from anywhere else: a pull reads this machine's registry, written by the same user.

## The verbs

```
bin/devbin cache key <artefact> [--commit <sha>]
bin/devbin cache get <artefact> [--commit <sha>]
bin/devbin cache put <artefact>
bin/devbin cache list [<artefact>]
bin/devbin cache rm <key>
bin/devbin cache gc [--keep <n>]
```

| Verb   | What it does                                                        | What it prints                                                           |
| ------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `key`  | the artefact's key at the commit, HEAD by default                   | the key, one line                                                        |
| `get`  | writes the artefact to its path from the registry                   | `pulled <artefact> <key>` at exit 0; `absent <artefact> <key>` at exit 1 |
| `put`  | records the artefact at its path under HEAD's key                   | `put <artefact> <key>`                                                   |
| `list` | the registry's entries for this project, or for one artefact        | `<artefact> <key>` for each                                              |
| `rm`   | removes the entries under one whole key                             | `removed <artefact> <key>` for each, or `absent <key>`                   |
| `gc`   | keeps the newest entries per artefact and every key a release names | `removed <artefact> <key>` for each, then `freed <n> bytes`              |

`--commit` takes a full commit sha. With it, `key` and `get` read the inputs at that commit, so a dirty working tree does not stop them.

**Exit codes.** `get` exits 0 when it pulled and 1 when the registry holds no entry under the key. Whatever a verb cannot do is a refusal, exit 7, with the reason on stderr: an undeclared artefact, a dirty input, a commit it cannot read, a root it cannot use, an argument it cannot read (followed by the usage), a write it cannot finish. 7 is the cache's own code in devbin's exit-code contract ([authoring commands](authoring-commands.md)), apart from `get`'s 1 and the dispatcher's 2 and 3, so a build handler never reads a failure as a miss. `-h` or `--help`, wherever it stands, is the usage at 0, and a bare `bin/devbin cache` is the contract's usage error, 1.

**put.** `put` records the artefact only when every input path is committed. It writes the entry into a temporary directory under the artefact's directory and renames it into place. A `put` that stops at any step, refused or killed, leaves no temporary entry behind it, as far as its exit trap can reach; a `put` killed outright can leave one, which `gc` names.

**gc.** `gc` keeps the newest 3 entries per artefact, by each entry's own time, unless `--keep <n>` says otherwise. It also keeps every key that the newest release seal names on a `cache<TAB><artefact><TAB><key>` line, whatever its age. When no seal names a key, it says `no release seal names a key: keeping the newest <n> per artefact alone`. It refuses, removing nothing, when the newest seal cannot be read or the directory the release's runs are kept in cannot be listed. It names any temporary entry a `put` left behind (`left <artefact> <name>: ...`) and removes none of them, since one that a `put` is still writing looks the same: remove it yourself once no `put` is running.

`list`, `rm` and `gc` refuse, removing nothing, a registry directory they cannot list. They never read it as empty.

The verb stays devbin's own. A project command named `cache` would answer in its place, so config validation refuses `commands.cache.handler` and `commands.cache.run`, and `bin/devbin doctor` fails a handler file at that name.

## How a release uses the cache

**A project's build handler** calls `get` before it builds and `put` after (see [the how-to](#write-the-build-handler)). The core's own `build` command does not change: a handler that never calls the cache builds every time, as before.

**The macOS stage** calls the cache itself. Where the app is the `build:` artefact whose `path` is `macos.app`'s, `app-sign` pulls it from the cache at the release commit and runs no `macos.build`; on a miss it builds the app and puts it. Its output reads:

```
pulling app from the artefact cache at <sha12>
  pulled, so macos.build is not run
```

A stage whose app is no `build:` artefact builds it uncached, as it did before the cache, and `bin/devbin doctor` notes that.

**The RELEASE seal names the keys.** Once every leg is green, the cut writes one `cache<TAB><artefact><TAB><key>` line into its RELEASE seal for each artefact the `build:` block declares: its key at the release commit, read through `cache key --commit`. The cut prints one line for each:

```
release: cache: app <key> at <sha12>
```

A key that cannot be read is said with why, and the seal names no key for that artefact. These lines are what `gc` reads to keep every key the newest release used.

**Where it saves a build.** A `put` records under HEAD's key only when every input is committed, so a build made before a release's stamp is committed records nothing. The first build a cut can record is the one at the release commit. A build at the tag reads the release commit's tree, so it pulls. A re-cut after a red leg whose fix touched no input pulls. A second leg on the same inputs, on the same machine, pulls.

**Where it never saves one.** An artefact whose inputs carry a per-cut stamp, such as a version file the release writes into every artefact's inputs, never hits across cuts, by design: its inputs change every cut. Its saving, if any, is inside one cut and in the development loop.

**What it never pulls.** A doubtful entry. A pull checks that `SHA256SUMS` lists exactly the artefact and the manifest, that both match their sums, and that the manifest names the key asked. An entry that fails any of these is removed with a line, `get` answers absent, and the build runs.

## An absent cache is a miss, never a failure

Nothing has to be set for a build to run.

- `DEVBIN_CACHE_HOME` unset or empty: the root is the XDG default.
- A root that does not exist yet is an empty registry. `get` answers absent, the build runs, and `put` makes the root and the entry, so the first build on a machine fills the cache.
- A root that cannot be used: a relative path, a file, a link to nothing (itself or above it), a directory this user cannot write, or one that cannot be made because the nearest path above it that exists is not a directory this user can write. `get` and `put` each say so in one line on stderr, naming the root and why, before the key asks the toolchain anything, and exit 7. The build handler goes on and builds.
- A `put` that fails after a green build never changes the build's own exit.

The registry is a cache: its absence costs a build and nothing else, and the line is how No Silent Errors is kept.

**What doctor reports**, in a project with a `build:` block:

- the root it resolves, marked `declared` or `default`, and whether it is writable or will be made at the first `put`;
- a note when the root cannot be used, naming why, since every build then runs and none is recorded;
- a failure for each input path the block declares that HEAD does not hold, since no key can read it;
- for the macOS stage, a pass naming the artefact it pulls and puts, or a note that it builds its app uncached.

So a wrong root or a mistyped input is read before a cut, not in one.

## Integrity

What an entry keeps is under [the registry](#the-registry), and what a pull verifies under [what it never pulls](#how-a-release-uses-the-cache). Two more guarantees:

- A `get` that cannot write the artefact at its path refuses, removing what it wrote of it, rather than answer absent.
- The registry is the user's own, never shared between users or machines.

## What it has removed so far

No project has adopted the cache yet. Each project's adoption, and the count of builds per release before and after it, is that project's own work.

One project was measured before the cache was built: the macOS app with a Rust backend in the table above. Its three cargo builds are three distinct artefacts, plus the app, each built once per cut after the legs are green, and its release stamp writes the version into every one's inputs. So no cut could pull an earlier cut's artefact, and the one repeat on the same key inside a cut is already a cargo no-op. The cache removes no build from that project's cut. What it could still save there is the development loop's cold restore.

## Limits

- **The architecture is the shell's.** The `arch` line is `uname -m` as the shell runs it, so a build run from an emulated shell, eg an x86_64 bash under Rosetta on an arm64 Mac, is keyed with the shell's architecture whatever the toolchain builds for. On one machine that is a second key and a miss, never a wrong pull.
- **A toolchain pinned below the project root is not the one named.** Every tool but cargo is asked its version at the project root, so a pin in a subdirectory (eg a `.swift-version` or `.tool-versions` there) is not read. Keep pins at the repository's root.
- Not done: no remote or shared registry, no transfer between platforms, no cache for a test suite (the gates' seal is that), and no claim that two machines build identical bytes. Nothing in devbin wires a CI runner's cache to the key.

## How-to

### Declare the inputs

List every path the build reads, and nothing it does not: a path left out is a change the key cannot see, and a path put in that the build never reads only makes misses.

1. Add a `build:` block to `bin/.devbin/config.yaml` with `inputs` and one entry under `artefacts` for each thing the build writes.
2. Give each artefact its `tool` and `path`. Make sure git ignores the `path`: `get` refuses a path the repository tracks files at.
3. Run `bin/devbin doctor`. It fails any declared input HEAD does not hold, and names the root.
4. Run `bin/devbin cache key <artefact>` on a clean tree. It prints the key, or refuses with the reason.

### Write the build handler

```bash
#!/usr/bin/env bash
set -euo pipefail
rc=0
bin/devbin cache get app || rc=$?
case "$rc" in
  0) exit 0 ;;
  1) ;;
  *) echo "build: the cache refused (exit $rc), so app builds uncached" >&2 ;;
esac
cargo build --release
bin/devbin cache put app || echo "build: the cache did not record app (above), and the build stands" >&2
```

`get`'s 0 is a pull, so nothing is built. Its 1 is a miss, so the build runs. Any other exit is a refusal, which costs a build and nothing else. A `put` that fails leaves the build standing.

### Read a hit

- From the handler: `pulled app <key>` on stdout and exit 0. A miss prints `absent app <key>`.
- From a cut: the `release: cache: app <key> at <sha12>` line, and the seal's `cache` line.
- From the macOS stage: `pulled, so macos.build is not run`.
- To see what an entry was built from: `<root>/<project>/<artefact>/<key>/manifest.yaml` has the commit, the host, the clock and each line of the key.

### Clear an entry

```bash
bin/devbin cache list app
bin/devbin cache rm <key>
```

`rm` takes a whole key, as `list` prints it, and removes the entries under it. The next build at that key builds and records again.

### Run gc

```bash
bin/devbin cache gc
bin/devbin cache gc --keep 1
```

The first keeps the newest 3 per artefact, the second the newest one, and both keep every key the newest release seal names. Read any `left` line: it names a temporary entry from a `put` that did not finish, which you remove once no `put` is running.

### Move the root

Set `DEVBIN_CACHE_HOME` to an absolute directory this user can write, in the environment every build and cut runs in (eg the shell's profile), then run `bin/devbin doctor` to read the root it resolves. Nothing in an entry names its root, so the old entries can be moved across as they are, `<old root>/<project>` to `<new root>/<project>`. Or leave them, and the first build at each key fills the new root.

### Adopt the cache in a new project

1. Declare the `build:` block and check it with `doctor` and `cache key`, as above.
2. Make the project's `build` handler call `get` before it builds and `put` after.
3. For a macOS app, declare the artefact at `macos.app`'s path, name the version file among its inputs, and leave `macos.commit_stamp` undeclared. The macOS stage then pulls and puts the app itself.
4. Build twice on a clean tree. The second build should print `pulled`.
5. At the next cut, read the `release: cache:` lines, and the seal's `cache` lines, which `gc` keeps.
6. Count the builds per release before and after, so the saving is measured rather than assumed.
