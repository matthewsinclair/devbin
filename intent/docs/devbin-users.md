# Devbin users -- every install on this machine

> ## GENERATED AT: 2026-09-22 20:57Z
>
> **DO NOT RELY ON ANYTHING BELOW IF THAT TIMESTAMP IS NOT FROM RIGHT NOW.** Not "recent", not "today", not "this morning". Every row here is a claim with an expiry date -- which devbin a project runs, and when it was last vendored -- and any of them is falsified by one `install` or one `upgrade` in another window. This document was true at the moment above and makes no claim about any other moment.
>
> **IF IT IS OUT OF DATE, DO NOT REGENERATE IT SILENTLY -- ASK hv FIRST.** An agent that finds this stamp stale should surface that to hv and wait for confirmation, not rebuild. Two reasons: the scan walks every root on the machine and takes about two minutes, and a document quietly refreshed mid-task changes the numbers someone is reasoning about without anyone having decided they should change.
>
> Once hv confirms: `cd ~/Devel/prj/Devbin && bin/devbin fleet doc`
>
> **Do not hand-edit.** The tables below are rendered; an edit is overwritten by the next run and lost without trace.

Generated rather than written because this census was written by hand five times and was wrong five times -- eleven estates when there were twelve, uniform when it was split, three-way divergent when the bytes said two, and twelve when the thirteenth had never been looked for. **A row that has gone stale looks exactly like a row that has not.**

## What counts as an install

A directory carrying `bin/.devbin/manifest.sha256`. The manifest is written by `devbin install` and rewritten by `devbin upgrade`, so its presence means devbin was actually vendored there and its mtime is when that last happened.

Roots scanned (override with `DEVBIN_FLEET_ROOTS`):

- `~/Devel/prj`

Pruned from the scan, and **this list is part of the definition rather than an optimisation**: `.git node_modules _build .history .backup .elixir_ls target .venv`. Change it and the answer changes: pruning `deps/` reports 17 copies, keeping it reports 29. **Never bound the depth either.** `Arca/arca_cli` and `Arca/arca_config` sit one level deeper than every other estate, so ANY `-maxdepth` is wrong here rather than only the `-maxdepth 3` that first missed them. That number used to be the whole warning, and the next reader defended against the number: `-maxdepth 4`, eleven of thirteen, the same two projects lost, thirteen minutes after reading this file.

## Estates -- 17

A project someone works in. Sorted by path.

| Project                     | devbin | Seam digest  | Source commit | Seam committed       | Last vendored (UTC) |
|-----------------------------|--------|--------------|---------------|----------------------|---------------------|
| Devel/prj/_Archive/Intentv2 | 0.1.0  | 6576010e4ac1 | 08f51b754902  | DIRTY                | 2026-09-01 17:07Z   |
| Devel/prj/Arca/arca_cli     | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Arca/arca_config  | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Baize             | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Cards/Design      | 0.1.7  | 4428e1d3cf41 | 142763dba160  | not its own checkout | 2026-09-22 19:27Z   |
| Devel/prj/Cdtempl           | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Conflab           | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Gtools            | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Intent            | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Laksa             | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 20:49Z   |
| Devel/prj/Lamplight         | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/MicroGPTEx        | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Molt              | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Prodinfra         | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Prolix            | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Riffle            | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |
| Devel/prj/Utilz             | 0.1.7  | 4428e1d3cf41 | 142763dba160  | committed            | 2026-09-22 19:27Z   |

## Seam states -- 2 distinct across the estates

Grouped by the digest of the vendored runtime (`bin/devbin` plus `bin/.devbin/lib/`), **not by the recorded `source_commit`**. The stamp records which commit a re-vendor was run from; the digest records what the bytes actually are. They disagree whenever a re-vendor pulls a later commit that changed nothing under the seam, and on this fleet they have.

| Seam digest  | Estates | Projects                                                                                                                                                                                                                                                                                                                     |
|--------------|---------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 4428e1d3cf41 | 16      | Devel/prj/Arca/arca_cli, Devel/prj/Arca/arca_config, Devel/prj/Baize, Devel/prj/Cards/Design, Devel/prj/Cdtempl, Devel/prj/Conflab, Devel/prj/Gtools, Devel/prj/Intent, Devel/prj/Laksa, Devel/prj/Lamplight, Devel/prj/MicroGPTEx, Devel/prj/Molt, Devel/prj/Prodinfra, Devel/prj/Prolix, Devel/prj/Riffle, Devel/prj/Utilz |
| 6576010e4ac1 | 1       | Devel/prj/_Archive/Intentv2                                                                                                                                                                                                                                                                                                  |

## Other on-disk copies -- 12

Real vendored runtimes that are **not** estates. They are listed because they can drift and because an audit that silently dropped them would under-report what is on the disk -- and listed separately because folding them into the estate count over-reports it.

- **worktree** -- a git worktree of an estate, carrying whatever devbin its branch has.
- **dep** -- a dependency checkout (Mix `deps/`), which is a copy of some other project's repository that happens to ship devbin. Not tracked by the consuming project and rebuilt by its package manager.

| Kind | Path                                     | devbin | Seam digest  | Source commit | Seam committed | Last vendored (UTC) |
|------|------------------------------------------|--------|--------------|---------------|----------------|---------------------|
| dep  | Devel/prj/Anvil/deps/arca_cli            | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-09-06 11:14Z   |
| dep  | Devel/prj/Anvil/deps/arca_config         | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-09-06 11:14Z   |
| dep  | Devel/prj/Arca/arca_cli/deps/arca_config | 0.1.0  | 58973306b271 | UNRECORDED    | committed      | 2026-08-10 16:15Z   |
| dep  | Devel/prj/Baize/deps/arca_cli            | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-08-27 12:21Z   |
| dep  | Devel/prj/Baize/deps/arca_config         | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-08-27 12:21Z   |
| dep  | Devel/prj/Laksa/deps/arca_cli            | 0.1.1  | 1481fa737576 | 87a0d47234d3  | committed      | 2026-09-19 12:15Z   |
| dep  | Devel/prj/Laksa/deps/arca_config         | 0.1.1  | 1481fa737576 | 87a0d47234d3  | committed      | 2026-09-19 12:15Z   |
| dep  | Devel/prj/Lamplight/deps/arca_cli        | 0.1.1  | 1481fa737576 | 87a0d47234d3  | committed      | 2026-09-19 12:15Z   |
| dep  | Devel/prj/Lamplight/deps/arca_config     | 0.1.1  | 1481fa737576 | 87a0d47234d3  | committed      | 2026-09-19 12:15Z   |
| dep  | Devel/prj/Prolix/deps/arca_cli           | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-08-26 20:12Z   |
| dep  | Devel/prj/Prolix/deps/arca_config        | 0.1.0  | 9b0e1983e2d1 | 4dc899de522b  | committed      | 2026-08-26 20:12Z   |
| dep  | Devel/prj/Riffle/deps/arca_config        | 0.1.0  | 58973306b271 | UNRECORDED    | committed      | 2026-08-11 06:19Z   |

## What this document cannot tell you

- **The `devbin` column is the version stamped into each manifest, not a fact about its bytes.** Two installs of one release carry the same number whether or not their files match; the seam digest is the column that tells them apart.
- **`Last vendored` is the manifest's mtime, not a git fact.** It says when devbin last wrote that file. A copy restored from backup, or synced by Dropbox, carries a stamp that is true about the file and misleading about the estate.
- **`Seam committed` is the one git fact in these tables, read from each estate's own repository at scan time (issue 0056).** `committed` means the seam matches this checkout's HEAD -- and says nothing about whether that commit is pushed, or is on the branch a clone would get. `DIRTY` means it does not, and every other column in that row then describes this checkout only. `not a checkout`, `not its own checkout`, `not tracked` (a seam file git ignores -- a stray ignored file under the lib counts, because the digest does -- or a symlink, whose target git never reads) and `not watched` (a seam file marked assume-unchanged or skip-worktree) each mean git could not vouch for the bytes, and none of them is a clean result. A cell git could not answer at all is `UNREADABLE`, and this document is refused rather than published with one. The column reports and never judges: a frozen estate can be DIRTY by ruling.
- **An `UNRECORDED` source commit means the manifest predates the `source_commit` field**, not that the install is broken. Those manifests are from before the field existed.
- **This is one machine.** Nothing here can see a clone on any other.
- **The scan is taken twice and this document is refused if the two disagree** about which installs exist. That control exists because one pass once reported twelve estates and the next reported thirteen, the missing one being the only root under Dropbox. Agreement here means the two passes saw the same set, not that the set is complete.
