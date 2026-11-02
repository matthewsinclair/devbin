## Tags

fleet, census, provenance, false-signal, uncommitted

## Summary

`fleet audit` and `fleet doc` read the manifest **off disk** and never ask git anything. Verified: `bin/.devbin/cmd/fleet` contains no git invocation at all -- the only occurrences of the word are the prune list and prose.

So an estate whose vendored seam has been changed but not committed **reads as level**, and nothing in the output distinguishes it from an estate that is genuinely level and committed. **The census answers "what bytes are on this machine" while every reader uses it to answer "what is the fleet running", and those diverge the moment a re-vendor is not committed.**

## Three instances, all found on 2026-09-03, none by the census

- **Prolix.** Swept to `e05bd64` on 2026-09-02 and never committed. HEAD sat at `367cd2d` while the working tree carried `e05bd64`. The census reported it level. Found only because a sweep printed a non-zero pre-existing dirty-seam count for that estate.
- **Utilz.** Re-vendored to `fca3c6b` at 12:46Z, outside any fleet sweep, and left uncommitted. Found only by re-reading every manifest by hand hours later, after the census had already been regenerated with the stale row in it.
- **Intentv2.** Thirteen seam files dirty since 2026-09-01 18:07 local, including an untracked `bin/.devbin/lib/cmd/fullcycle`. **Its census row therefore describes a half-applied upgrade rather than any commit.** Frozen by ruling on 2026-09-02, so this state is deliberate to leave and is recorded rather than repaired -- but the census does not say that is what it is showing.

**Two of the three are estates re-vendoring themselves outside a sweep.** That was first observed on 2026-08-29, when two estates did it in one afternoon. The standing line is that the sweep is the thing that moves the fleet; it is not, and the census cannot see the difference.

## Why the existing warning does not cover it

The generated document already carries: *`Last vendored` is the manifest's mtime, not a git fact.* That warning is about the **timestamp** -- it tells a reader not to trust the mtime as a git event. It says nothing about whether the row's `Source commit` and `Seam digest` describe committed content, which is the actual gap. **A warning sitting next to the hole, aimed at a different hole, is worse than no warning: it makes the section read as already caveated.**

## Impact

The document exists to answer "what devbin is each project running". For an uncommitted estate the honest answer is two answers -- what its checkout runs today, and what anyone else cloning it would get -- and the census silently reports only the first.

**It also makes a sweep unverifiable from its own output.** A sweep that re-vendors and commits, and one that re-vendors and fails to commit, produce identical census rows. That is exactly how "thirteen re-vendored" was true and "thirteen committed" was false on 2026-09-01.

## Proposed fix

Add a **committed-state column**, computed per estate, distinguishing at least three states: the seam is clean against its own HEAD; the seam is dirty; the estate is not a git checkout at all. `git -C <estate> status --porcelain -- <seam paths>` answers it in one call per estate, and the not-a-checkout case must be its own value rather than folding into clean -- absent must never read as empty, which is the correction this project already made once to the roots list.

Two constraints on the design:

1. **A dirty seam must not make `fleet doc` refuse.** Intentv2 is deliberately dirty and frozen; a census that will not publish while a ruled exception exists is a census nobody can run.
2. **The column reports; it does not judge.** Whether a dirty estate is a problem is context the tool does not have.

## Found

While answering hv's question "is `devbin-users.md` up to date". It was not, and the row that was wrong was wrong for this reason.



## Progress 2026-09-14 -- built, tested and reviewed, and NOT landed: the review found the column can still read committed over a seam git never looked at

A committed-state column was built in `bin/.devbin/cmd/fleet` -- `seam_committed`, wired into `scan` and both tables of `fleet doc` -- with seven arms watched red first, five mutations each turning exactly its arm red, and a full suite of 1073 of 1073 on a clone carrying it. **A critic-shell review of the uncommitted diff then found it breaks its own rule, confirmed with scratch probes, so it was held rather than committed.** The work is archived as `intent/whiteboard/cc/.history/20260914/0056-census-column-work.patch`, which applies cleanly to HEAD, and the review as `0056-critic-findings.md` beside it.

**What the review found in the change:**

- **It can still print `committed` for a seam git skipped.** An untracked file under `bin/.devbin/lib` reads `committed` once `status.showUntrackedFiles=no` is set in the estate's repo or inherited from a caller's `git -c`; and a `.gitignore` carrying `lib/` leaves `bin/devbin` and the manifest tracked and the lib never committed, which also reads `committed`, because the tracked check asked only about the manifest.
- **It is a second hand-written seam list.** `vendored_scope` in `lib/install` already owns devbin's half as git pathspecs; the census should build its question from that.
- **Its caveat promised more than it measures.** A comparison with the local HEAD cannot say what a clone gets: unpushed commits and other branches read `committed` too.
- **One arm could not tell "the seam is tracked" from "the manifest is tracked"**, and no arm put an untracked file under the seam.

**What it found beside the change, bearing on this issue's subject:** `scan` reads `find_installs` through an unchecked process substitution with `find`'s errors discarded, and a probe with one unreadable directory under the first root stopped the loop before the second root was scanned -- exit 0, one install of two listed, no message. That is a candidate explanation for the census once reporting 13 estates and then 12, not a proven one.

**A fourth instance, reported by gtools-vc on 2026-09-14.** Gtools-geodica's manifest sat modified and uncommitted from 2026-09-11 to 2026-09-14, after a sync that moved only its `source_commit` line and changed no file hash; per gtools-vc it was committed at Gtools-geodica `af57e48` on hv's ruling. The census had no column that could have shown it.


## Fixed 2026-09-16 -- a Seam committed column, one hardened seam question shared with install, and a scan that names what it could not read (dc), reviewed by vc

**Commits:**
- `fa93672`: the column and the incomplete-scan refusal, as first built. hv committed it for the release, before its second critic round.
- `527d461`: critic-shell round 2, 14 findings.
- `33abe6c`: vc's review. It hardens the publish gate and fixes where the git variable cache is kept.

**The column.** `fleet audit` and `fleet doc` carry `Seam committed` per install: `committed`, `DIRTY`, `not watched`, `not tracked`, `not a checkout`, `not its own checkout` or `UNREADABLE`. It reports and never judges, so a DIRTY estate does not stop `doc`. The scope is the installed seam itself: `bin/devbin`, `bin/.devbin/lib` and the manifest, with no fallback to a project's own `lib/`. `not a checkout` means git said there is no repository and the root has no `.git`. Any other git failure is `UNREADABLE`. Whether the install is a repository of its own is asked through git's prefix, not by comparing paths.

**One question, three callers.** lib/install holds the hardened answer to "is devbin's half committed":
- `git_readonly` clears git's local environment variables and turns off the repository's `core.fsmonitor` hook and untracked cache.
- `seam_git_verdict` is pure.
- `seam_git_state` lists untracked and ignored files, overrides submodule ignore settings, and reads assume-unchanged and skip-worktree marks. A symlink anywhere in the seam reads `not tracked`.
- `seam_state_of` adds vendored_scope.

The census asks it. So do the provenance stamp `install` writes (`source_commit_of`, where anything but committed is `+dirty`) and the D28 publish gate (`tree_dirty_paths`, which adds a `seam: <state>` line beside its whole-tree status). Before this, the stamp and the gate were separate unhardened copies. After round 2 hardened only the stamp, an ignored `lib/.DS_Store` passed the gate and the install was stamped `+dirty`. vc found that, and `33abe6c` closes it.

**An incomplete scan fails and names what it missed. BEHAVIOUR CHANGE:** an UNREADABLE cell now fails the scan, where the first build published it. Any of these is named on stderr, carried in its row as `UNREADABLE`, and makes `audit` exit non-zero; `doc` and `fleet upgrade` then refuse:
- a root `find` could not read in full;
- an unreadable manifest, which no longer reads UNRECORDED;
- a seam with no launcher or no lib to digest;
- an estate git cannot answer for.

`scan` checks each step itself, because `doc` runs it under `||`, which turns errexit off: a digest failure there had published a row at exit 0. The prune list is a real `-prune`, so churn under `_build` no longer fails a scan. The critic measured 154 of 366 scans failing under the filter, and 0 of 1437 under a real prune. git's local variable list is primed once per scan, in the calling shell.

**Arms:**
- `fleet.bats`, the 0056 section: committed, DIRTY and deleted; not a checkout, not its own checkout, not tracked, half-ignored lib; untracked under repo config and under a caller's `core.excludesfile`; inherited `GIT_DIR`.
- Also in `fleet.bats`: assume-unchanged, skip-worktree, and marks and ignored files on a later line; an ignored file beside an edit; own `lib/` beside a deleted vendored lib; a symlinked lib and a symlinked launcher; submodule `ignore=all`; the fsmonitor hook never runs; a corrupt HEAD; an unreadable manifest; a missing lib or launcher; doc refusing both a partway failure and an incomplete find; a mode-000 directory under `_build`; a root NAMED; one variable-list ask over three estates.
- `install.bats`: the stamp with an ignored file, an assume-unchanged edit, a symlink, and an inherited `GIT_DIR`; the pure verdict.
- `localinstall.bats`: an ignored file refuses publish; an assume-unchanged edit refuses publish-upgrade.

**Mutation checks.**
- dc ran 23 across rounds 2 and 3 and killed 21. Three of those were killed only once the arms they had first survived were added. The other 2 were not real misses: one was a malformed spelling of the filter mutation, and the other is equivalent behind a guard.
- vc ran four and killed all four:
  - dropping `--ignored=matching`;
  - a gate that refuses only on DIRTY;
  - a prime without its early return, which made 10 asks over three estates;
  - a real-tree check that devbin's own seam carries nothing the new gate refuses.

**Suite.** 1205/1205 at `527d461` (dc) and SUITE_33A at `33abe6c` (dc), each in a detached worktree.

**Residuals.**
- No git on PATH has no arm of its own; it takes the corrupt-HEAD branch.
- `source_commit_of` falls back to the whole tree when there is no seam to point at. That path now errs toward dirty and is unreachable from a devbin source.
- A single-machine census still cannot see another clone.
