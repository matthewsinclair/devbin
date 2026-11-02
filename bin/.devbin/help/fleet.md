devbin fleet <audit|doc|upgrade>

Every devbin install on this machine: which devbin each one vendors, and a way
to bring them all forward. Devbin's own project command -- it lives in devbin's
tree, not in the vendored runtime, so an install cannot enumerate anything.

  audit             print one row per install found: its kind (estate,
                    worktree or dep) and path, its devbin version, the commit
                    it was vendored from, the digest of its vendored runtime,
                    when it was last vendored, and whether that runtime is
                    committed in the estate
  doc               regenerate intent/docs/devbin-users.md from the same scan
  upgrade [--apply] upgrade every estate from the machine install. WITHOUT
                    --apply it prints the plan and writes nothing

## Where it looks

  bin/.devbin/fleet.roots  the roots to scan, one a line, `~` for the home
                           directory -- tracked, so changing the frame is a commit
  DEVBIN_FLEET_ROOTS       overrides the file for one run, space-separated
  DEVBIN_FLEET_HOME        the directory walked for installs OUTSIDE the roots
                           (default: $HOME)
  DEVBIN_FLEET_FROZEN      estates the sweep must not touch, space-separated,
                           each as the sweep's plan names it
                           (default: none, and the plan says so)

A missing roots file, or one naming no root, is refused, and so is a DEVBIN_FLEET_ROOTS naming none: a census over no roots would read as a machine with nothing on it. Every run also walks the rest of the home directory and names each install no root covers, so a frame the disk has outgrown says so (issue 0116): `audit` on stderr, `doc` in a section of its own, and `upgrade` in its not-swept table. That walk prunes .claude, whose installs are agent fixtures, and the list below, wherever they sit. It does not look in the home directory's own Library, which holds Library/CloudStorage, where Dropbox and Google Drive keep their folders, or its .Trash, or through a symlink, and every report of the walk says so. `upgrade` names a walk that could not read everything as a NOT KNOWN row and still exits 0, since an install outside the frame is never swept either way; `audit` exits 1 and `doc` refuses.

The walk has no depth limit, on purpose: estates do not all sit at the same
depth, and every limit tried so far lost some. It prunes .git, node_modules,
_build, target and the other trees named in the handler, and the document
prints that list, because a count means nothing without the list that produced
it. Worktrees and dependency checkouts that carry a runtime are listed apart
from the estates by `audit` and `doc`, not counted as estates and not dropped.
`upgrade` sweeps estates only: it names each worktree and dependency checkout in its not-swept table as `NOT AN ESTATE`, and counts them on its summary line.

An install is a directory carrying bin/.devbin/manifest.sha256, or, without one, bin/devbin beside a bin/.devbin/lib directory or a link to one (issue 0154). One that has lost its manifest is still listed: its version, commit and last-vendored cells read `NO MANIFEST`, its runtime is digested, and git is asked whether the removal is committed. It is reported, not judged, so it does not fail the audit. One whose manifest records no files (issue 0159) keeps its header's version and commit, and its last-vendored cell reads `NO FILES`, reported the same way.

A scan that could not read everything says so: a root not read in full, a manifest that cannot be read, a seam with nothing to digest or one it cannot read whole, and an estate with a `.git` of its own that git cannot answer for, are each named on stderr, a cell that could not be read shows `UNREADABLE`, and `audit` exits non-zero (issue 0056). Bare `fleet` prints its usage and exits 1.

## upgrade

It distributes the bytes of the install this machine's switch names, never this checkout's: `DEVBIN_INSTALL_PREFIX` when it is set, else the tree the link `~/.local/bin/devbin` leads to, else Homebrew's install by its opt path (issue 0213; `bin/devbin help use`). Every estate runs `bin/devbin upgrade --from` that install, and its next upgrade reads the same switch, so it finds the install again. There is no `--prefix` here. A switch that names nothing, or names devbin's checkout, is refused by name: a sweep distributes an install's bytes, so `devbin use opt` or `devbin use brew` comes first. A sweep that DEVBIN_INSTALL_PREFIX chose, where the switch without it names another tree, warns that a shell without the variable reads that one instead. The plan's `distributing:` line names the install and what chose it, in the words `doctor` uses.

The plan names every estate: `level`, `upgrade`, or `upgrade + repoint` for one
whose manifest does not yet record `install` -- a recorded path is one even where it names the install, since the upgrade replaces it. No estate is dropped silently. A frozen
estate, one with no executable bin/devbin, one that has lost its manifest, or whose manifest records no files (which `upgrade` refuses unless forced, so the row carries that command instead), one whose manifest cannot be read, one that failed, each worktree or dependency checkout, and each install outside the roots are each named,
with the reason. An estate that took the upgrade but held back files edited in
place is HELD, which is not level, and the files are named with the remedy.
With --apply, any HELD or FAILED estate makes the exit non-zero.

A scan that could not read a root in full is refused rather than swept, because
an estate under that root would leave the sweep without a row (issue 0056).

A frozen name is an estate's label as the sweep's plan prints it: its path below this run's roots, so `GroupA/Child` freezes that estate alone, and a bare `Child` freezes only an estate of that name at a root's top level. A label follows the run's roots, which DEVBIN_FLEET_ROOTS changes, so a name written for one frame can label nothing in another; and the same path under two roots gives two estates one label, which one name freezes together. A name that labels no estate the run could sweep is named in the plan as matching none, and --apply refuses while one is declared, before it writes anything: name the estate it was meant for as its row in the plan does, and drop a name only when what it was meant for is no estate under that run's roots. The incomplete-scan refusal comes first, since an estate the walk could not reach matches nothing for that reason.

## doc

The document is generated, and it says so. Every fact in it expires -- which
estate runs which devbin -- and a hand-written table of them is right on the day
and wrong afterwards, with nothing about a stale row looking stale. The scan is
taken twice, and the document is refused when the two passes disagree about
which installs exist, when any cell could not be read, or when the walk outside the roots could not read everything.

## See also

  bin/devbin help install         what gets vendored, and the machine install
  bin/devbin help upgrade         one estate's upgrade, which the sweep runs per estate
  intent/docs/devbin-users.md     the generated census
