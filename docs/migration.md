# Migrating an existing launcher

How to take a project that already has a hand-written `bin/<project>` dispatcher onto devbin without a flag day.

The shape of the problem is always the same. A working launcher, in daily use, with a helpers library beside it and a help text somebody wrote carefully. It cannot stop working for an afternoon, and the prose in that help text is worth more than the dispatcher around it.

The protocol below is therefore built on one idea: **the old launcher and devbin coexist, fully working, until the evidence says the new one is equivalent.** Deletion is the last step, not the first.

> **Status.** The protocol is ratified and is what devbin's own install path is built to support. It has been run on the four source launchers -- the first in ST0001's WP-10, then the other three in WP-11 -- and what bit in those migrations is written into the step it bit in.

## Before you start

**Quiesce the project.** No concurrent work in it while the migration runs. This is a working-tree operation with no branch, so a second person committing in the middle is the one thing that makes it hard to unwind.

**No git branches.** Deliberately. The rollback story lives in the sequencing, not in version control -- each step is independently safe, and the only irreversible one is a delete-only commit at the end that a single `git revert` undoes.

**One project at a time.** A half-migrated set of projects is the state this exists to remove, not a state to pass through.

## Install alongside

```
$ devbin install --into . --name myproject --lang elixir --lang rust
```

Note what is **not** passed: `--alias`. It is recorded in config and creates nothing -- devbin writes no symlinks, because a launcher named after the project shadowed the binary the project builds.

After this step the project has two working launchers:

| Path                      | Owner            | State                         |
| ------------------------- | ---------------- | ----------------------------- |
| `bin/myproject`           | the old launcher | untouched, still in daily use |
| `bin/myproject_helpers`   | the old launcher | untouched                     |
| `bin/myproject_test`, ... | the old launcher | untouched                     |
| `bin/devbin`              | devbin           | new, works immediately        |
| `bin/.devbin/`            | devbin + you     | new                           |

This holds by construction: `bin/devbin` and `bin/.devbin/` do not overlap the old launcher's `bin/myproject*` names at all. Nothing you already have is at risk in this step.

One thing belongs **before the install commit**: if the project runs a Markdown formatter in a pre-commit hook, fence the vendored runtime out of it first -- one line, `bin/.devbin/lib/`, in `.prettierignore`. Found live, not imagined: one migration's prettier hook rewrote a vendored help template inside the install commit, and `doctor` failed the manifest checksums one command later. The vendored half of the seam is devbin's to write and devbin's to format.

Verify before going on:

```
$ bin/devbin doctor
$ bin/devbin help --why
```

`--why` is the important one. It tells you what devbin is offering, where each command resolved from, and -- more usefully at this stage -- **everything it ships that your project is not getting, with the reason**. A command missing because you have not declared its language reads very differently from one missing because something is broken.

## Declare what the old launcher did

Work through the old dispatcher and express it in `bin/.devbin/config.yaml`. Most of it is declaration, not code:

| In the old launcher                           | In devbin                                               |
| --------------------------------------------- | ------------------------------------------------------- |
| `_set_env` / `_set_bin` / `_set_fidelity`     | `options:` entries                                      |
| `test_all`, `check_all`                       | nothing -- `all` is synthesised                         |
| a gate calling a tool and grepping its output | an option with `run:`, `grammar:` and `log:`            |
| `<prj>_<cmd>` handler scripts                 | `run:` if it is one command line, `cmd/<cmd>` otherwise |
| the `print_global` help heredoc               | nothing -- `devbin help` generates it                   |
| the `print_topic` heredocs                    | `help/<cmd>.md`, one file per topic                     |

The declarative/imperative boundary is the judgement call in this step, and it has a sharp edge: **`run:` is split into words, each of them a glob pattern, and never `eval`'d**, so a command line with a quoted argument in it cannot be declared. That is not a limitation to work around -- it is the signal that this one wants a handler. `devbin new <cmd>` scaffolds it in a second.

See [authoring-commands.md](authoring-commands.md) for the mechanics and [configuration.md](configuration.md) for every key.

## Move the authored help

This is the part worth slowing down for, because it is the part that is genuinely irreplaceable.

The global listing (`print_global`) is **deleted, not migrated**. `devbin help` generates it from what actually resolves, which is the whole point -- the hand-maintained listing is what drifts.

The per-topic prose (`print_topic`) is **migrated verbatim** into `bin/.devbin/help/<cmd>.md`, one file per topic, with sub-topics at `help/<cmd>.d/<sub>.md`.

**Read the prose for decisions before you rewrite it.** Authored help accumulates decisions that exist nowhere else in the project. The clearest example found so far: one launcher's help text states that a bare command must exit 1 rather than 0, with the reasoning, because somebody had been bitten by `test && deploy` treating a no-op as permission. That is a behavioural rule sitting in a heredoc. Four sites in devbin had it wrong until that paragraph was read.

So: extract the decisions first, apply them, and only then move the prose.

> **Done in WP-10/WP-11.** The four source launchers were inventoried in full -- 70 authored topics, 1,769 lines of prose, with a disposition for every one -- and the extraction was **specified in that inventory and performed during the per-project migrations**, because writing those files meant editing live projects.

## Prove equivalence

Do not proceed on the belief that it works. For every command the old launcher offered, run both and compare.

What "equivalent" has to mean:

- every command the old launcher had still exists, under the same name
- each produces the same effect, and the gates produce the same verdict on the same tree
- the sealed artefacts land where CI expects them, with the same suffixes
- exit codes match, particularly the non-zero ones -- a gate that now exits 0 where it used to exit 1 is the worst possible outcome of a migration and the easiest to miss

Keep the evidence. It is what authorises the delete, and it is the only thing standing between "we migrated it" and "we think we migrated it".

> **Done in WP-10/WP-11.** Each migration -- the first, then the other three -- kept its evidence as an examines table comparing what each gate examined on the old side and the new, citing the seal each side wrote.

## Delete, last, in its own commit

Only once the evidence is complete:

1. Switch the entry point to `bin/devbin`. **This is the collision point**, which is why it is here and not when installing alongside: until now the old launcher was still serving. From this moment `bin/devbin <cmd>` reaches devbin. No symlink is created -- the project-named launcher convention was retired.
2. Delete `bin/myproject_helpers`, `bin/myproject_help` and the `bin/myproject_*` handlers.
3. Commit **only the deletions and the entry-point switch**, nothing else.

Keeping this as a delete-only commit is what makes the rollback a single `git revert`. Mixing it with a config change or a fix means an unwind has to be surgical, at exactly the moment nobody wants to be surgical.

The bare shims a project keeps at the top level -- `bin/server`, `bin/deploy` and friends -- go on working unchanged, because devbin takes its identity from `config.yaml` rather than from `$0`.

One piece of housekeeping goes with the switch: the old runner's seal files (lowercase-suffix `tmp/test/*.mix.*` and friends) are invisible to devbin's purge, which is scoped to its own suffix family -- that is what preserved them as evidence during the steps before the delete, and it is also why nothing will ever purge them again. Delete them by hand, once, after the switch.

## What if it goes wrong

| When                       | Undo                                                                      |
| -------------------------- | ------------------------------------------------------------------------- |
| before the delete          | nothing to undo -- the old launcher is untouched and still the one in use |
| after the delete           | `git revert` the delete-only commit                                       |
| a vendored file was edited | `upgrade` refuses it and tells you; `upgrade --force` overwrites it       |

Every step before the delete is reversible by doing nothing, which is the property the whole sequence is arranged to have.

## Afterwards

```
$ bin/devbin doctor
```

Then keep the runtime current with `bin/devbin upgrade`, which upgrades from the tree this machine's switch names: `DEVBIN_INSTALL_PREFIX` when it is set, else the tree the link `~/.local/bin/devbin` leads to, which `devbin use` writes, else the brew install, at `$HOMEBREW_PREFIX/opt/devbin/libexec` (`bin/devbin help use`). The manifest records the KIND of tree the bytes came from (`install`, `checkout` or `project`) and never where it is, and the kind never decides where the next upgrade goes. Devbin installs from **whatever devbin is running**, and records that as the new project's source, so seed every project from the brew install, as the README's [Install](../README.md#install) says: seeded from another project, it records `project` and that project's own git HEAD as its `source_commit`, a hash devbin's history does not hold.
