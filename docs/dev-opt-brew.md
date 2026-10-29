# Dev, opt and brew: one contract for every tool released through Homebrew

Every tool released through Homebrew reaches a machine in the same tiers: **dev**, the maintainer's checkout; **opt**, a working copy the maintainer publishes from it, which keeps what works apart from what is mid-development; and **brew**, the formula, the one publish to prod. They are dev, stage and prod. A user installs from brew; dev and opt are the maintainer's.

This is the contract each such tool follows, so that the tools behave alike: Molt, Utilz, Intent and devbin. Each tool's own design cites it. `<tool>` below is `molt`, `utilz`, `intent` or `devbin`.

## T1. The trees

| Tree | Where                                 | Written by                                       | Who uses it    |
| ---- | ------------------------------------- | ------------------------------------------------ | -------------- |
| dev  | the git checkout                      | git                                              | the maintainer |
| opt  | a prefix the maintainer configures    | `<tool> install`, run in dev                     | the maintainer |
| brew | `$(brew --prefix)/opt/<tool>/libexec` | the formula, running `<tool> install` in the keg | every user     |

- A **tree** is the tool's runtime set, and it finds its own root from its resolved path. No environment variable names the running tree.
- **The runtime set** is what git names under the tool's runtime paths, plus the build products the tool declares (eg Utilz's Rust binaries, which its install builds), and nothing else (no tests, docs or project records such as `intent/`). One function lists it, build products included, and both install and doctor read that function. **For a compiled tool** (Intent), the runtime set is the support paths git names plus the binaries built from that same commit, and its `source_commit` is the commit the binaries were BUILT from, which in dev can lag HEAD.
- **The opt prefix has no default.** It comes from `--prefix`, else the tool's one configured place (its config key or its variable, named once in the tool's docs). When neither is set, install refuses by name.
- **brew is always named by its opt link**, never by a `Cellar/<tool>/<version>` path, which `brew upgrade` deletes.
- **A user's docs name brew alone.** dev and opt appear only in a section for the maintainer of a dev checkout.

## T2. Publish: `<tool> install [--prefix <dir>] [--force] [--managed-by brew]`

- It runs only in a dev tree. From opt or brew it is refused by name. A tool whose `install` has other modes says which mode is the publish; eg devbin's `install --into <project>` vendors devbin into a project from any tree, which is not a publish.
- **A dirty runtime set is refused**, with no override. Only the runtime set counts, so live project records do not block a publish.
- **An existing prefix** is replaced only with `--force`, and only when its manifest says this tool wrote it. A prefix holding anything else is refused. `--force` is the one re-publish route; no other verb publishes.
- **`--managed-by brew`** is the formula's. An install it writes refuses `install` and `use` writes into it, and says to use brew.
- **A formula that installs signed release assets** instead of building from a checkout (Intent: Developer ID signed and notarised binaries on macOS, static packages on Linux) lays the assets out in the brew tree itself and writes the manifest in T3's exact form with `managed_by: brew`. It conforms: T3 fixes the manifest, not who writes it.

## T3. The manifest

- **Path:** each tool's own, named once in its docs (Molt `<root>/.molt-install`; Intent `<root>/.intent-install`; devbin `<root>/bin/.devbin/manifest.sha256`, which vendored projects carry too). The keys and the body form below are fixed.
- **Header**, one `key: value` per line, each line starting `# `, carrying at least these keys, under these names, beside any of the tool's own:
  - `tool`
  - `version`
  - `source_commit`, the full sha
  - `managed_by`: `<tool>` or `brew`
- **Body:** one line per runtime file in `shasum -a 256 -c` form, path relative to `<root>`, sorted by `LC_ALL=C sort`.
- Doctor in opt and brew checks the body and names every file that drifted.
- **An install in a tool's older manifest form** (written before this contract) is not read as a second format. The tree function and doctor name it as an old manifest, with its remedy. An opt install fails doctor until it is republished with `install --force`. A brew keg is a note naming `brew upgrade <tool>`, never a failure: only a release that writes the new form fixes it, and that release's own cut runs doctor on a machine still holding the old keg. The tree function still answers `brew` for such a keg when its old manifest says `managed_by: brew`, so `use`, upgrade and the shadow check keep working on it, and only doctor's line about its manifest is a note. In brew, an old manifest includes no manifest at all: a keg from before the contract with none, recognised by its root resolving under the tool's brew opt link (`$(brew --prefix)/opt/<tool>/libexec`), answers `brew` and gets the same note. In opt it stays strict: a prefix with no manifest is not this tool's, so `use opt` refuses it.

## T4. Tree identity and the version line

One function names the running tree, read in this order:

1. **brew** when the manifest says `managed_by: brew`.
2. **opt** when the manifest's `tool` is this tool.
3. **dev** when the root is a git work tree with no manifest.
4. **unknown** otherwise, and doctor fails on it.

Every caller asks that one function.

`<tool> --version` and `<tool> version` print one line, `<tool> <version> (<tree>, <sha12>[+dirty])`. The sha is the manifest's `source_commit` in opt and brew. In dev it is the commit the running code came from: HEAD for a script tool, and for a compiled tool the commit its binary was built from, read from the binary, never HEAD at run time (doctor says when HEAD has moved past the build). `+dirty` follows it in dev while the runtime set differs from the commit the line names, or, for a compiled tool, when the binary was built from a tree whose BUILD INPUTS were dirty. The tool declares its input set and derives the build inputs from the build system's own dependency record where one exists (eg cargo's dep-info), never a hand list alone, and the runtime set it declares counts beside them, so a whiteboard or docs write never marks a build dirty and a missed input never reads clean. Never in opt or brew. A compiled tool may append one build-provenance word after the closing parenthesis (eg `release` or `dev`, saying how the binary was stamped). The line names no path: where the running copy lives is `command -v <tool>`'s answer. Doctor prints the same line, unchanged.

**A reader of the line reads up to the closing parenthesis and ignores anything after it.** So a line in the old shape, with ` at <root>` and any provenance word after the parenthesis, still reads correctly, and no reader needs a second format during the change.

When a dev tree's git cannot be read (eg git refuses it as an unsafe directory, or the repository is broken), the line keeps its one shape with `unknown` in the sha field, `<tool> <version> (dev, unknown)`, and doctor fails, saying why.

## T5. The switch: `<tool> use [dev|opt|brew]`

- **The switch rests at brew.** The maintainer moves a tool to dev or opt only while working on that tool, and moves it back with `use brew` once the work is released and `brew upgrade <tool>` has taken it. Each tool's release checklist ends there, with the version line reading brew at the released version.
- **The link set.** The tool's per-user link set lives in `~/.local/bin`, and the tool declares it in one function. The set may be one link (`molt`, `devbin`) or many (Utilz's utilities). Intent's set is `intent` and `intentd`, moved as one: its CLI finds the daemon only beside its own executable, so a split set is a real failure. The links are the only record of the choice, and nothing else stores it.
- **`use` with no argument** reports the tree each link serves, and changes nothing.
- **`use dev|opt`** points every link in the set at that tree's own copy. **`use brew` removes the whole link set** (every link into one of this tool's trees, and nothing else), so Homebrew's own bin links answer. `use brew` refuses, removing nothing, when no brew-managed copy would answer once the links are gone (the formula is not installed, its keg is not linked, or another copy comes first on PATH): it names each link it would have removed and the tree that link serves, why no Homebrew copy would answer, and the tool's own remedy (install or link the formula, or stay on dev or opt). **No link means brew**: it is the one rule, and the state a brew-only user is in without ever running `use`. A bare `use` reports brew when no link is left and the first hit on PATH resolves into the keg. Each of `use dev` and `use opt` refuses a tree that is not there, naming the step that makes it, then prints the version line.
- **PATH: your links first.** `~/.local/bin` comes before Homebrew's bin, and the machine's shell configuration owns that. It must come before the FIRST Homebrew bin entry: `brew shellenv` can put Homebrew's bin on PATH more than once, one of them ahead of the system directories, so the shell configuration prepends rather than appends. Formulae keep linking into Homebrew's bin, so a brew-only user who never runs `use` still gets a working `brew install`.
- **Shadow check.** Doctor, and `use` with no argument, fail when a link in the set exists but is not the first hit on PATH (a stale link a brew link shadows is named as one), or when the set is split across trees, and name what shadows or splits it. The comparison is of resolved directories, never path strings, since a directory on PATH can be a link to another (eg a `~/bin` that links to `~/.local/bin`).
- **`use` is the one verb that points links.** A tool retires any other user-facing verb that repoints them (eg Utilz's `relink`), keeping its logic inside `use`. A tool may keep an option naming the link directory, for tests only, defaulting to `~/.local/bin`.
- **A tool with a long-lived process** (Intent's `intentd`, one per user) restarts it as the last step of `use`, so the old tree's binary does not keep serving.
- **What the shadow check cannot see.** A process started without the login PATH (a launchd-spawned app, cron, a GUI app's helper) may have Homebrew's bin and not `~/.local/bin`, and then runs brew's copy while the maintainer is on dev or opt: eg Claude Code's hooks and an MCP server that name a tool by its bare name. Doctor runs in a login shell and cannot speak for those processes. **The switch governs login shells only.** launchd's PATH is the machine's own configuration, outside this contract.
- **Nothing else repoints.** Machine setup, relinking, sweeps across projects and upgrades never repoint a healthy link to any tree, and never remove one. They create a missing or broken link only when the running tree is dev or opt, pointing it at that tree; when the running tree is brew they create nothing, since no link means brew and a link into the keg would undo `use brew` at the next setup.

## T6. Upgrading the tool itself, by tree

The mechanism is fixed; the verb is each tool's own, and a tool may have none and document the steps instead (Intent: `intent upgrade` already means upgrading a project, so it is not repurposed).

- **dev:** `git pull`, with the tool's dirty-tree check, then the tool's build where it has one (Intent: `bin/devbin build all`).
- **opt:** no pull. It says opt is upgraded from dev with `<tool> install --force`, and names dev's commit when it is ahead of the manifest. It never publishes on its own.
- **brew:** `brew upgrade <tool>`, with `HOMEBREW_NO_AUTO_UPDATE=1` set wherever a script runs brew. A tool may run an explicit `brew update` first, as a counted step of its own, so that `brew outdated` sees a new release.

## T7. Tests and lint run in dev only

In opt and brew, the tool's test and lint verbs are refused by name, naming the dev tree.

## T8. The formula

- The formula is **rendered, never typed**: from a template in the repo (`packaging/homebrew/<tool>.rb`, never installed from) with exactly one placeholder each for the tag and the revision, or, for a formula that installs release assets, from the release's version and its sha256 per asset (Intent's `bin/int brew formula`). Nobody types a tag, a commit or a checksum.
- The repo's formula tool, a verb of the tool (devbin's `bin/devbin formula`) or a script in the repo (Molt's `tools/formula`), offers `render <tag> <out>` and `publish`, which renders the newest release into the tap `matthewsinclair/homebrew-<tool>` and pushes it.
- `install` runs `system "bin/<tool>", "install", "--prefix", libexec, "--managed-by", "brew"` (or, for release assets, lays them out and writes the manifest, T2), then links the tool's link set into `bin`.
- The caveats name `<tool> use` for a maintainer with a dev or opt tree.
- `test do` runs the version line.

## T9. devbin's extra: which install vendored projects read

devbin is also vendored, as `bin/devbin`, into every project that uses it, and a project's `bin/devbin upgrade` re-vendors from the machine's devbin install. That reader follows the switch:

- `DEVBIN_INSTALL_PREFIX`, when set, as an explicit override.
- Otherwise, when `~/.local/bin/devbin` is there, the tree it resolves to, read by the link's path rather than through PATH, so cron and hooks with no login PATH still find it.
- Otherwise `$HOMEBREW_PREFIX/opt/devbin/libexec`.

devbin's machine pointer file (`$XDG_DATA_HOME/devbin/home`) is retired. `devbin use` is then the one switch, for the command line and for every vendored project alike, and a brew machine keeps brew until `use` says otherwise.

## T10. The proof, per tool and per tree

For each tool, on the maintainer's macOS machine, and with brew alone on a Linux machine:

- `use dev`, `use opt`, `use brew` in turn, each followed by the version line and doctor, and the shadow check passing.

For devbin's switch, in each tree, in a checkout of Molt, Utilz, Intent and devbin:

- `bin/devbin doctor` names the install the switch chose, and why.
- `bin/devbin upgrade` reads that install.

Prefix every brew probe with `HOMEBREW_NO_AUTO_UPDATE=1`.
