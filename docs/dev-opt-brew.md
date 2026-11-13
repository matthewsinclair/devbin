# Dev, opt and brew: one contract for every tool released through Homebrew

Every tool released through Homebrew reaches a machine in the same tiers: **dev**, the maintainer's checkout; **opt**, a working copy the maintainer publishes from it, which keeps what works apart from what is mid-development; and **brew**, the formula, the one publish to prod. They are dev, stage and prod. A user installs from brew; dev and opt are the maintainer's.

This is the contract each such tool follows, so that the tools behave alike: Molt, Utilz, Intent and devbin. Each tool's own design cites it. `<tool>` below is the tool's name, such as `molt`, `utilz`, `intent` or `devbin`.

**The publish and the switch are devbin's verbs, never a tool's own.** For every project devbin drives, the publish is `bin/devbin install` (T2) and the switch is `bin/devbin use [dev|opt|brew]` (T5), both run in the tool's dev checkout, and devbin is its own case of the same. Any other tool's command line carries no `install`, `use` or `version` verb for this contract: its binary prints T4's line on `--version`, and that is the whole of the contract it carries. devbin's core is the one implementation of the publish, the tree, the line, the switch, doctor's rows and the formula's install, for every project that declares its binaries (devbin issue 0326): a tool declares its link set and its opt prefix in an `install:` block in `bin/.devbin/config.yaml`, and gives up its own copy of each.

## T1. The trees

| Tree | Where                                 | Written by                       | Who uses it    |
| ---- | ------------------------------------- | -------------------------------- | -------------- |
| dev  | the git checkout                      | git                              | the maintainer |
| opt  | a prefix the maintainer configures    | `bin/devbin install`, run in dev | the maintainer |
| brew | `$(brew --prefix)/opt/<tool>/libexec` | the formula (T8)                 | every user     |

- A **tree** is the tool's runtime set, and it finds its own root from its resolved path. No environment variable names the running tree.
- **The runtime set** is what git names under the tool's runtime paths, plus the build products the tool declares (eg Utilz's Rust binaries, which its install builds), and nothing else (no tests, docs or project records such as `intent/`). One function lists it, build products included, and both install and doctor read that function. **For a compiled tool** (Intent), the runtime set is the support paths git names plus the binaries built from that same commit, and its `source_commit` is the commit the binaries were BUILT from, which in dev can lag HEAD.
- **The opt prefix has no default.** It comes from `--prefix`, else the tool's one configured place (its config key or its variable, named once in the tool's docs). When neither is set, install refuses by name.
- **brew is always named by its opt link**, never by a `Cellar/<tool>/<version>` path, which `brew upgrade` deletes.
- **A user's docs name brew alone.** dev and opt appear only in a section for the maintainer of a dev checkout.

## T2. Publish: `bin/devbin install [--prefix <dir>] [--force] [--managed-by brew]`

- It runs only in the tool's dev checkout. From opt or brew it is refused by name. `bin/devbin install --into <project>` vendors devbin into a project from any tree, which is not a publish.
- **A dirty runtime set is refused**, with no override. Only the runtime set counts, so live project records do not block a publish.
- **An existing prefix** is replaced only with `--force`, and only when its manifest says this tool wrote it. A prefix holding anything else is refused. `--force` is the one re-publish route; no other verb publishes, unless the tool keeps its own (below).
- **`--managed-by brew`** is the formula's. An install it writes refuses `install` and `use` writes into it, and says to use brew.
- **A tool that keeps its own publish** names it in `install.publish`, the command that writes its opt tree in T3's form, with its `line`. devbin names that command and never runs it: in the tool's checkout `bin/devbin install` refuses its opt publish, naming it, and writes nothing. `--managed-by brew`, the formula's publish into a keg, and `--into`, the vendor, are not refused.
- **A formula that installs signed release assets** instead of building from a checkout (Intent: Developer ID signed and notarised binaries on macOS, static packages on Linux) lays the assets out in the brew tree itself and writes the manifest in T3's exact form with `managed_by: brew`. It conforms: T3 fixes the manifest, not who writes it.

## T3. The manifest

- **Path:** each tool's own, named once in its docs (Molt `<root>/.molt-install`; Intent `<root>/.intent-install`; devbin `<root>/bin/.devbin/manifest.sha256`, which vendored projects carry too). The keys and the body form below are fixed.
- **Header**, one `key: value` per line, each line starting `# `, carrying at least these keys, under these names, beside any of the tool's own:
  - `tool`
  - `version`
  - `source_commit`, the full sha
  - `managed_by`: `<tool>` or `brew`
  - `line`, the tree's version line (T4), naming the tool, which each of a compiled tool's binaries prints there under its own name; `bin/devbin install` writes it, and so does the formula's install for release assets (T8)
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

`<tool> --version` prints one line, `<tool> <version> (<tree>, <sha12>[+dirty])`, and a tool carries no `version` verb for it; devbin's own `devbin version` prints devbin's line too. Each other binary of a tool prints that line under its own name, `<name> <version> (<tree>, <sha12>[+dirty])`: its own name first, then the tool's version, tree and sha, so every binary of every tool reports its version the same way, and doctor reads each link's line under that link's name. The sha is the manifest's `source_commit` in opt and brew. In dev it is the commit the running code came from: HEAD for a script tool, and for a compiled tool the commit its binary was built from, read from the binary, never HEAD at run time (doctor says when HEAD has moved past the build). `+dirty` follows it in dev while the runtime set differs from the commit the line names, or, for a compiled tool, when the binary was built from a tree whose BUILD INPUTS were dirty. The tool declares its input set and derives the build inputs from the build system's own dependency record where one exists (eg cargo's dep-info), never a hand list alone, and the runtime set it declares counts beside them, so a whiteboard or docs write never marks a build dirty and a missed input never reads clean. Never in opt or brew. A compiled tool may append one build-provenance word after the closing parenthesis (eg `release` or `dev`, saying how the binary was stamped). The line names no path: where the running copy lives is `command -v <tool>`'s answer. Doctor prints the same line, unchanged.

**A reader of the line reads up to the closing parenthesis and ignores anything after it.** So a line in the old shape, with ` at <root>` and any provenance word after the parenthesis, still reads correctly, and no reader needs a second format during the change.

When a dev tree's git cannot be read (eg git refuses it as an unsafe directory, or the repository is broken), the line keeps its one shape with `unknown` in the sha field, `<tool> <version> (dev, unknown)`, and doctor fails, saying why.

**A compiled tool's line is the core's, and its binary only prints it.** `bin/devbin build` hands the project's declared build its dev line in `DEVBIN_VERSION_LINE`: HEAD's commit, and `+dirty` while the runtime set, the declared `build.inputs` or an input the build's dependency record names (`<binary>.d`, as cargo writes it) differs from HEAD. After the build it reads that record again, and builds once more, saying so, when the record names a changed input the line missed. In opt and brew the binary prints the `line` its tree's manifest records (T3). Each binary prints either under its own name. Every binary of every compiled tool reads its line with this one reader, word for word, its tool's name and manifest path its own, and its own name the bin target's, which Cargo hands every binary it builds (Rust):

```rust
// The version line, docs/dev-opt-brew.md's T4: in an opt or brew tree, the
// `line` its manifest records; otherwise the line bin/devbin build stamped;
// either under this binary's own name.
fn version_line() -> String {
    const TOOL: &str = "demo";
    const NAME: &str = env!("CARGO_BIN_NAME");
    const MANIFEST: &str = ".demo-install";
    let named = |line: &str| match line.split_once(' ') {
        Some((_, rest)) => format!("{NAME} {rest}"),
        None => line.to_string(),
    };
    let tree = std::env::current_exe().and_then(|p| p.canonicalize());
    let recorded = tree
        .ok()
        .as_deref()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .and_then(|root| std::fs::read_to_string(root.join(MANIFEST)).ok())
        .filter(|text| text.lines().any(|l| l == format!("# tool: {TOOL}")))
        .and_then(|text| text.lines().find_map(|l| l.strip_prefix("# line: ")).map(named));
    if let Some(line) = recorded {
        return line;
    }
    match option_env!("DEVBIN_VERSION_LINE") {
        Some(line) if !line.is_empty() => named(line),
        _ => format!("{NAME} {} (unknown, unknown)", env!("CARGO_PKG_VERSION")),
    }
}
```

The reader reads the manifest as one chain of `Option` steps, not nested `if let` blocks, so it builds clean under `cargo clippy -- -D warnings` in every edition: in edition 2024 Clippy asks for nested ones to be collapsed into a let chain, which no earlier edition can build. A reader kept in a library the binaries share takes NAME from each binary instead, since Cargo names no bin target while it builds a library. A binary built by plain `cargo build` carries no stamp and prints `<name> <version> (unknown, unknown)`, which doctor fails: build it with `bin/devbin build`. Cargo rebuilds when `DEVBIN_VERSION_LINE` changes, since it tracks the variables `option_env!` reads, so a tool needs no build script for it.

## T5. The switch: `bin/devbin use [dev|opt|brew]`

- **The switch rests at brew.** The maintainer moves a tool to dev or opt only while working on that tool, and moves it back with `bin/devbin use brew` once the work is released and `brew upgrade <tool>` has taken it. Each tool's release checklist ends there, with the version line reading brew at the released version.
- **The link set.** The tool's per-user link set lives in `~/.local/bin`, and the tool declares it in one place. The set may be one link (`molt`, `devbin`) or many (Utilz's utilities). Intent's set is `intent` and `intentd`, moved as one: its CLI finds the daemon only beside its own executable, so a split set is a real failure. The links are the only record of the choice, and nothing else stores it.
- **`use` with no argument** reports the tree each link serves, and changes nothing.
- **`use dev|opt`** points every link in the set at that tree's own copy. **`use brew` removes the whole link set** (every link into one of this tool's trees, and nothing else), so Homebrew's own bin links answer. `use brew` refuses, removing nothing, when no brew-managed copy would answer once the links are gone (the formula is not installed, its keg is not linked, or another copy comes first on PATH): it names each link it would have removed and the tree that link serves, why no Homebrew copy would answer, and the tool's own remedy (install or link the formula, or stay on dev or opt). **No link means brew**: it is the one rule, and the state a brew-only user is in without ever running `use`. A bare `use` reports brew when no link is left and the first hit on PATH resolves into the keg. Each of `use dev` and `use opt` refuses a tree that is not there, naming the step that makes it, then prints the version line.
- **PATH: your links first.** `~/.local/bin` comes before Homebrew's bin, and the machine's shell configuration owns that. It must come before the FIRST Homebrew bin entry: `brew shellenv` can put Homebrew's bin on PATH more than once, one of them ahead of the system directories, so the shell configuration prepends rather than appends. Formulae keep linking into Homebrew's bin, so a brew-only user who never runs `use` still gets a working `brew install`.
- **Shadow check.** Doctor, and `use` with no argument, fail when a link in the set exists but is not the first hit on PATH (a stale link a brew link shadows is named as one), or when the set is split across trees, and name what shadows or splits it. The comparison is of resolved directories, never path strings, since a directory on PATH can be a link to another (eg a `~/bin` that links to `~/.local/bin`).
- **Doctor's rows for a tool.** `bin/devbin doctor`, run in a tool's checkout, gives the tool rows under its name beside devbin's own: each link's copy in the checkout against the line a build there carries, a note when HEAD has moved past the build; each link's switch and the set as one, the shadow check and a split set failing; each opt or brew tree the set serves against its manifest (T3), every drifted file named with its tree's remedy, and each copy's `--version` against the manifest's `line` under that copy's own name; and a note when the set rests on dev or opt while Homebrew's copy is at that tree's version or past it, the same note devbin's own switch gives.
- **`bin/devbin use` is the one verb that points links**, unless the tool keeps its own switch and names it in `install.switch`. That command then points the links, where this contract puts them; in the tool's checkout `bin/devbin use` refuses, bare or with a tree, naming it; and doctor still reads the links and names it in its remedies. Otherwise a tool carries no verb of its own that points or removes them, a `use` or any other (eg Utilz's retired `relink`), and one that still has such a verb gives it up as it adopts the core. An option naming the link directory may exist for tests only, defaulting to `~/.local/bin`.
- **A tool with a long-lived process** (Intent's `intentd`, one per user) restarts it as the last step of `use`, so the old tree's binary does not keep serving.
- **What the shadow check cannot see.** A process started without the login PATH (a launchd-spawned app, cron, a GUI app's helper) may have Homebrew's bin and not `~/.local/bin`, and then runs brew's copy while the maintainer is on dev or opt: eg Claude Code's hooks and an MCP server that name a tool by its bare name. Doctor runs in a login shell and cannot speak for those processes. **The switch governs login shells only.** launchd's PATH is the machine's own configuration, outside this contract.
- **Nothing else repoints.** Machine setup, relinking, sweeps across projects and upgrades never repoint a healthy link to any tree, and never remove one. They create a missing or broken link only when the running tree is dev or opt, pointing it at that tree; when the running tree is brew they create nothing, since no link means brew and a link into the keg would undo `use brew` at the next setup.

## T6. Upgrading the tool itself, by tree

The steps are devbin's verbs, run in the tool's checkout, and a tool carries no upgrade verb of its own for them (Intent's `intent upgrade` upgrades a project, and stays so).

- **dev:** `git pull`, then `bin/devbin build`, which stamps the binary with its line (T4); doctor says when HEAD has moved past the build.
- **opt:** no pull. opt is upgraded from dev with `bin/devbin install --force`, which refuses inputs that differ from HEAD and builds before it publishes. Nothing publishes on its own.
- **brew:** `brew upgrade <tool>`, with `HOMEBREW_NO_AUTO_UPDATE=1` set wherever a script runs brew. A tool may run an explicit `brew update` first, as a counted step of its own, so that `brew outdated` sees a new release.

## T7. Tests and lint run in dev only

In opt and brew, the tool's test and lint verbs are refused by name, naming the dev tree.

## T8. The formula

- The formula is **rendered, never typed**: from a template in the repo (`packaging/homebrew/<tool>.rb`, never installed from) with exactly one placeholder each for the tag and the revision, or, for a formula that installs release assets, from the release's version and its sha256 per asset (Intent's `bin/int brew formula`). Nobody types a tag, a commit or a checksum.
- The repo's formula tool, a verb of the tool (devbin's `bin/devbin formula`) or a script in the repo (Molt's `tools/formula`), offers `render <tag> <out>` and `publish`, which renders the newest release into the tap `matthewsinclair/homebrew-<tool>` and pushes it.
- **The install is one form, which devbin generates**: the template's install holds `@@INSTALL@@` once, and render writes there the core's publish, `system "bin/devbin", "install", "--prefix", libexec, "--managed-by", "brew"`, from the tag's checkout; or, from the release's assets, each packed rooted at the install root, the stage laid out in libexec with 0755 on each link and the manifest in T3's form with its `line`; then the tool's link set into `bin`, each an env script under the formula's bash on macOS where `formula.bash` is true. A formula whose platforms differ, assets on one and the tag's checkout on another, takes both, by what the stage holds. Lines the template keeps in its install go after `@@INSTALL@@`; no template lays its assets out by hand, and render refuses one whose install runs anything before `@@INSTALL@@`, blank and comment lines aside, naming the line.
- The caveats name `bin/devbin use`, run in the tool's checkout, for a maintainer with a dev or opt tree.
- `test do` runs the version line.

## T9. devbin's extra: which install vendored projects read

devbin is also vendored, as `bin/devbin`, into every project that uses it, and a project's `bin/devbin upgrade` re-vendors from the machine's devbin install. That reader follows the switch:

- `DEVBIN_INSTALL_PREFIX`, when set, as an explicit override.
- Otherwise, when `~/.local/bin/devbin` is there, the tree it resolves to, read by the link's path rather than through PATH, so cron and hooks with no login PATH still find it.
- Otherwise `$HOMEBREW_PREFIX/opt/devbin/libexec`.

devbin's machine pointer file (`$XDG_DATA_HOME/devbin/home`) is retired. `devbin use` is then the one switch, for the command line and for every vendored project alike, and a brew machine keeps brew until `use` says otherwise.

## T10. The proof, per tool and per tree

For each tool, on the maintainer's macOS machine, and with brew alone on a Linux machine:

- `bin/devbin use dev`, `use opt` and `use brew` in turn, in the tool's checkout, each followed by the version line and `bin/devbin doctor`, and the shadow check passing.

For devbin's switch, in each tree, in a checkout of Molt, Utilz, Intent and devbin:

- `bin/devbin doctor` names the install the switch chose, and why.
- `bin/devbin upgrade` reads that install.

Prefix every brew probe with `HOMEBREW_NO_AUTO_UPDATE=1`.
