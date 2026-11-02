# inbox: vc -> hv

## (2026-08-24 14:30Z)

Session close, second sitting. The morning's account was delivered earlier and is folded into `vc/.history/20260824/`; this is the afternoon, which emptied the queue. Every ruling below was yours, made live in session -- recorded here so the record survives the session rather than because you have not seen it.

### The queue is empty

`intent issues list` says **no open issues**, for the first time since this node existed. Eight closed today:

| Issue | What closed it |
| ----- | -------------------------------------------------------------------------------- |
| 0017 | `devbin vendor` -- the tree-vs-SOURCE comparison doctor and upgrade could not make |
| 0021 | converged-healing, the direction guard, and the exit-status question RULED         |
| 0014 | `git_head_sha` / `git_head_watch_paths`, your option B                            |
| 0018 | devbin's own `cmd/check` handler retired -- it was the only one in nineteen installs |
| 0019 | the seal's reading order in the contract, plus one word in devbin's own config     |
| 0015 | reproduced on demand; closed on the reproduction, NOT on an explanation            |
| 0023 | closed by EXECUTION -- its fix was the sweep procedure                             |
| 0024 | doctor names any project name standing where devbin ships its own, your option A   |

### The fleet

**Eleven installs on devbin `c92540c`**, across two sweeps. Sweep #3 was the substance; sweep #4 delivered 0024's check so that fix stopped being half-delivered. Both enumerated FROM DISK: nineteen installs found, eleven swept, eight excluded with their reasons on the record (six mix-managed `deps/arca_config` copies, two Lamplight worktrees). **Intentv2** -- live, committed the same day, never given the bash floor -- was the miss your fleet question surfaced, and it is now level with the rest.

### The pattern worth keeping, because it held four times

**When a finding looks fleet-wide, check whether it is devbin-only first.** 0018's `check critic` divergence, its three dead `run:` targets, and 0019's uncountable critic gate were all devbin's own tree -- all in `bin/.devbin/`, the config the documentation points at as the worked example, and every one found by READING before proposing rather than by a gate going red. Twice the issue's own stated hypothesis was wrong and the reading refuted it; twice the machinery the issue asked for already existed and only devbin was not using it.

### The three things that went wrong, because that is the useful part

**`check lint` had been red on committed code for a week** and nobody was blocked, which is how it stopped being read. A permanently-red gate is the mirror of a false green: both end with nobody trusting the verdict. Fixed in its own commit.

**I left D9's reversal half-done this morning.** `ARCHITECTURE-shell.md` still headed a section "Bash 3.2 is a hard target" and `help/doctor.md` still said "against the 3.2 target" -- and the architecture file is the one the restart brief points at for exactly that question. I updated design.md, usage-rules, doctor, CI and the tests and missed the as-built document. Both corrected.

**Sweep #3's commit loop reported `git log -1`**, so two blocked commits at Intent and Intentv2 read as successes with their changes left staged. Caught only by verifying stamps afterwards. Sweep #4 checked exit status. On the board as a watch-out.

### Two decisions I made that you can reverse in one line each

**0021: upgrade's exit status stays 0 when files were refused.** Its status answers "did I complete"; `vendor`'s answers "is this level". If you would rather have a distinct completed-with-skips code, it is one branch.

**0018: devbin still sweeps a whole corpus where the fleet checks staged files.** That is now a declared `run:` line in config with the reason beside it, rather than an accident. If you would rather this tree matched the fleet, delete the line -- but its CI critic gate becomes vacuous, because `intent critic` scans nothing unless told and CI stages nothing.

### Current status

Nothing in flight, nothing open, no claim held, vc paused. Eleven installs uniform at `c92540c`, all gates green, suite 619. cc has a catch-up in its inbox covering everything since it paused on 08-10.

**The next thread is yours to set.**
