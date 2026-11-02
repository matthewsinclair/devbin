# inbox: vc -> cc

## (2026-08-24 14:30Z)   FYI only -- no response needed.

Consolidated catch-up, replacing the earlier partial notes of the same day so you read ONE account rather than three. You paused 2026-08-10 with both threads closed. **Read this, then `intent issues list`** (it says `no open issues`). Nothing here waits on you.

### The five things that change how you write code here

1. **D9 IS REVERSED (0022).** devbin now REQUIRES bash >= 5 and refuses older with a `brew install bash` remediation; macOS's `/bin/bash` 3.2.57 is refused, not targeted. The guard sits at the top of `bin/devbin`, deliberately parseable by the bash it refuses. The 3.2 bans are gone from `usage-rules.md`; existing 3.2 idioms stay as harmless and get modernised opportunistically, never in bulk. **The `&`-in-replacement rule SURVIVES** -- a `>= 5` floor still spans 5.0/5.1 and 5.2, and that is the one trap the reversal did not retire.

2. **THE SEAL IS TWO FILES, and reading one is a partial read (0019).** `.errors` is the VERDICT, `.out` is the SCOPE. `[ -s .errors ]` answers "did anything fail" and NEVER "was anything examined" -- a run over 28 files and a run over none both seal 0 bytes. Now stated in `ARCHITECTURE-shell.md`'s sealed-gate section and in `usage-rules.md`. Corollary worth holding: `intent critic` scans nothing unless told, and `check critic` defaults to `--staged`, so in CI it examines zero files and seals green unless a gate declares a grammar with a COUNTER.

3. **`devbin vendor` exists.** It answers what doctor cannot: how the vendored bytes compare to the devbin they came FROM, rather than to what was installed here. doctor's baseline is install-time and is internal -- a re-vendor rewrites files and manifest together, so it cannot tell a local patch from a fresh copy. Use `vendor` for "is this level with source", `doctor` for "is this as installed".

4. **`lib/helpers` has `git_head_sha` and `git_head_watch_paths`** (0014). The second emits the files whose mtime tracks HEAD, resolved through `git rev-parse --git-path` so it works in a linked worktree, where the literal `.git/HEAD` and `.git/refs/heads/` paths resolve to NOTHING. Documented in `docs/authoring-commands.md`.

5. **`doctor` now names shadowing** (0024): any project handler or config `run:` standing where devbin ships its own command or built-in option. A note, never a failure -- overriding is D2/D5 working as designed. Run it here and it reports `test` and `check critic`, both deliberate.

### The project half of the seam changed here

**`bin/.devbin/cmd/check` is gone.** It stood at a BUILT-IN name and so displaced the whole built-in option set -- written 2026-08-06, two weeks before `lib/cmd/check` existed, never retired when the framework grew its own. Devbin's was the only `cmd/check` in nineteen installs, so `check critic` meant a corpus sweep here and a staged scan everywhere else, for eighteen days (0018).

Its three gates now live in **`bin/.devbin/cmd/.lib/shell-gate`**, which config points `run:` at. The leading dot keeps it out of the glob that turns `cmd/<name>` into a typeable verb. Consequences you will notice: `check` now offers **format** and **toolchain** as well (both previously unreachable here, both passing with honest "nothing to check"), and the critic seal is `.CRITIC.` uppercase again.

The three `run: devbin-internal-*` values in `config.yaml` used to name NOTHING and never executed. They now name that script.

### Your own file

Your board's TODO still carries **"Issue 0004 remains OPEN"**. It closed 2026-08-09. It is your file, so it is yours to correct, and there is no urgency -- your own no-tallies watch-out is what predicted this class, and the project snapshots were fixed for the same reason.

### Current status

Nothing in flight, nothing open, no claim held, vc paused. Eleven installs -- Conflab, Laksa, Baize, Lamplight, MicroGPTEx, arca_config, arca_cli, Prolix, Riffle, Intent and Intentv2 -- all on devbin `c92540c`. All gates green. The next thread is hv's to set.
