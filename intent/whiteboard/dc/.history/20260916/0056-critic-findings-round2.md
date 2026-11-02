# critic-shell review of the rebuilt 0056 census column -- 2026-09-16, round 2

Archived by devbin-dc before a compact so the findings outlive the session. It reviewed the UNCOMMITTED diff to `bin/.devbin/cmd/fleet`, `tests/unit/fleet.bats` and 0056's entry in `RELEASES/0.1.2.md`, with probes under the session scratchpad. Line numbers refer to the uncommitted working tree.

## Critical (to fold before commit)

1. **The prune list filters, it does not prune** (fleet:137,143). `-not -path "*/$p/*"` still walks `.git`, `_build`, `node_modules`, `target`; now that find's rc means "incomplete", any error inside a pruned tree fails the scan. Measured: 154 of 366 audits refused under a mkdir/rm churn in `_build`; a real `-prune` expression failed 0 of 1437. Fix: `\( -name P1 -o ... \) -prune -o -name manifest.sha256 -path '*/bin/.devbin/*' -print`.
2. **`snap="$(scan)" || die` disables errexit inside scan** (fleet:724,726). A seam_digest failure mid-scan (estate with `bin/.devbin/lib` removed) published a row at exit 0 whose digest covers the launcher only; HEAD refused. `audit` exits 1 with no rows and no message. Fix: check each step inside scan explicitly (`dg="$(seam_digest ...)" || { warn; dg=UNREADABLE; rc=1; }`), no outer `||`.
3. **vendored_scope falls back to `$root/lib`** when `bin/.devbin/lib` is not a directory, so an Elixir estate with its own `lib/` reads `committed` over a deleted or symlink-replaced vendored lib (fleet:338). Fix: use `$root/bin/.devbin/lib` directly; not a real directory -> UNREADABLE.
4. **Submodule ignore settings hide seam edits** (`ignore = all|dirty`, `diff.ignoreSubmodules=all`). Fix: `--ignore-submodules=none`.
5. **The estate's `core.fsmonitor` is trusted, and runs its hook.** Fix: `-c core.fsmonitor=false -c core.untrackedCache=false` in `_estate_git`.
6. **A tracked symlink in the seam reads `committed`** (git compares link text). Fix: a scope member that is a symlink -> `not tracked` or UNREADABLE.
7. **A git failure is labelled `not a checkout`** (garbage `.git/HEAD`; no git on PATH gives every estate `not a checkout` at exit 0; dubious ownership). Fix: failures -> UNREADABLE; `not a checkout` only for git's "not a git repository".
8. **Regression: an unreadable manifest reads UNRECORDED at exit 0** (`manifest_field ... || true`); HEAD failed loudly. Fix: `[ -r ]` first, UNREADABLE with rc=1; only an absent field is UNRECORDED.
9. **Highlander: two "is devbin's half committed" implementations that already disagree.** `source_commit_of` (lib/install) still runs an unhardened status, so `install` can stamp a clean sha over bytes the census calls DIRTY or not watched. Fix: one hardened query in lib/install beside vendored_scope, used by both. (lib/install is 0059's file, committed at da1a075 and under vc's review.)
10. **RELEASES/0.1.2.md overclaims** ("whatever the repository or caller has configured"; "an incomplete scan fails rather than shrinking"). Correct with the code.
11. **Red-control: the "is NAMED" arm cannot go red** -- stdout rows already contain `$r1`. Assert `could not read all of $r1`.
12. **Red-control: three case patterns have no arm** -- an ignored file on a later line, skip-worktree, assume-unchanged on a later line (every fixture's hit sorts first). Add the three fixtures.
13. **Red-control: the doc-refusal arm does not pin the refusal** -- add a scan-fails-partway (`libgone`) arm asserting doc refuses and leaves the file, and the message.
14. **Red-control: the caller `git -c` arm pins nothing alone.** Use a setting the flags do not override, eg `core.excludesFile` ignoring `*` (DIRTY would become `not tracked`).

## Recommendations

- Compute `--local-env-vars` once per run (audit 0.73s -> 1.82s on 27 installs).
- Make porcelain/ls-files -> state a pure function tested on strings.
- A root typed in the wrong case gives `not its own checkout` everywhere; `rev-parse --show-prefix` empty avoids path comparison.
- `.DS_Store` (global gitignore) turns a DIRTY estate into `not tracked`, since `!!` wins; consider DIRTY first, or both.
- Case-only renames on macOS read `committed`; worth a caveat line.

## Checked sound

Porcelain first-line and quoted paths; status.* configs and pathspec env vars; glob characters in paths; sparse index; nested clones; symlinked roots; the find_installs idioms; CI runs as `runner`, so the chmod-000 arms run.
