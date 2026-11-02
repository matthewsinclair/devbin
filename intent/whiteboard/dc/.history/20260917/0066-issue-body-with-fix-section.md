Found by the critic-shell review of the 0065 fix on 2026-09-14, and verified by reading every site before filing.

## What is repeated

Three small vocabularies are written out wherever they are needed, rather than asked of one function. Thirteen lines in all, read on 2026-09-14 in the working tree carrying the 0065 fix, and cited here by function because a line number in a durable record rots:

- **false -- `false`, `no`, `0`:** `option_active`, `option_unavailable_reason`, `command_unavailable_reason`, `command_active` and `run_all` in `lib/resolve`; `gate_log_suffix` in `lib/runlog`.
- **true -- `true`, `yes`, `1`:** `command_active` and `_shared_option_is_flag` in `lib/resolve`; `gate_log_suffix` in `lib/runlog`.
- **no default -- `-`:** `run_option` and `run_command` in `lib/resolve`; `builtin_option_group` and `builtin_has_default_run` in `lib/builtins`; `gate_log_suffix` in `lib/runlog`.

## Why it matters

Every copy agrees today, and nothing would say so on the day one of them learns a word the others do not. The review's example: if `enabled:` came to accept `off`, a project writing `log: off` would still seal a gate NAMED `off`, silently, because the schema checks keys and not values. That is 0065's defect re-entering through a word list rather than through a branch.

**The `-` sentinel has already diverged once in exactly this way.** 0065 was a project's `-` for `log:` being honoured only on the catalogue's value. `grammar:` still has that shape: a project writing `grammar: "-"` gets `unknown grammar '-' -- sealing with the generic grammar`. That is loud rather than silent, but it is the same scoping mistake, and it lives in `run_option` beside the `log:` code 0065 just changed.

The documentation now makes a claim this issue would make checkable: `docs/configuration.md` and the vendored `lib/config.reference.yaml` say `log:` declines on the spellings `enabled:` reads as false. Nothing tests that the two lists are the same list.

## Shape of a fix, not a ruling

One predicate per vocabulary, in `lib/helpers` because it needs no config and every handler can load that file alone -- eg `is_false_word`, `is_true_word`, `is_no_default` -- with every site above asking it, and a test holding the documented spellings to the predicates.


## Fixed 2026-09-17 -- one predicate per vocabulary, over word lists that the docs are held to (dc), reviewed by vc

**Commits:**
- `fa93672`: the predicates and the 13 sites, as first built. hv committed it for the release before its critic report was in.
- `98df868`: the critic fold, 0 critical and 5 warnings.
- `315702a`: vc's review finding, IFS.
- `356ea8d`: the one test loader the load refusal broke.

**The predicates.** `is_true_word`, `is_false_word` and `is_no_default` in `lib/helpers` read three word lists, `_DEVBIN_TRUE_WORDS`, `_DEVBIN_FALSE_WORDS` and `_DEVBIN_NO_DEFAULT`, through `_word_in`. It splits with `read -a` under a local `IFS=' '`. Without the pin, a caller's strict-mode `IFS=$'\n\t'` made `true`, `yes`, `1` and `no` read as not-a-word, so `log: false` stopped declining. vc found that, and it was 0065 again. The 13 sites in `lib/resolve`, `lib/runlog` and `lib/builtins` call the predicates, and `lib/cmd/server` now reads the iex flag with `is_true_word`, so `options.iex.value: yes` or `1` runs the iex form.

**`-` as a grammar.** `gate_grammar` in `lib/runlog`, beside `gate_log_suffix`, is the one reading of an empty or `-` grammar as `generic`. `run_option`, `run_command` and `gatecmd` all use it. A project writing `grammar: "-"` had been told `unknown grammar '-'`.

**lib/builtins refuses to load without lib/helpers.** A missing predicate did not fail where it was used: `! is_no_default` turned "command not found" into success, and `builtin_has_default_run build` claimed a command line for a row that has none. Every production caller already loaded helpers first. Four test loaders did not, and three were found and fixed in `98df868`. The fourth, `ci-workflow.bats`, sent the full suite red at `33abe6c` (1211/1212) and is fixed at `356ea8d`.

**What holds it:**
- A structural test searches `lib/`, `bin/devbin` and `bin/.devbin/cmd`, and fails on a hit outside `lib/helpers`. It looks for:
  - any two vocabulary words joined by `|`, in any order or quoting;
  - `-` compared with `=`, `==` or `!=`;
  - `-` used as a case alternative.
- Its pattern carries its own control, 16 lines it must hit and 6 it must miss. The test fails if a search root is missing or grep itself fails. Declared limit: a single-word comparison such as `= true` is not searched for.
- A doc test holds the `log:` decline spellings stated in `docs/configuration.md` and in `lib/config.reference.yaml`, and the docs' count of them, to the word lists. It reads the lists as data, not the function's source.

**Arms:**
- `helpers.bats`: the predicates and near misses; the predicates under `IFS=$'\n\t'` and `IFS=`; the doc, reference and count; the pattern control; the structural search.
- `builtins.bats`: the option-level and command-level `grammar: "-"`; `gate_grammar` pure; the load refusal.
- `surfaces.bats`: `server --iex` with `value: yes` and `value: 1`.

**Mutation checks.**
- dc's first build killed 6.
- The fold ran 13 and killed 12:
  - `off` added to a list;
  - a side-door comparison in `is_false_word`;
  - re-spellings in `lib/resolve`, `lib/builtins` and `lib/runlog`;
  - the load check removed;
  - `gate_grammar` ignoring `-`;
  - `server` back to `= true`;
  - `run_option` and `run_command` passing the grammar raw;
  - the reference dropping `0`;
  - the docs miscounting.
- vc's review killed MV4, `on` added to the true words.
- vc's F3 fold killed MV5, dropping the IFS pin. MV6, pinning bash's default IFS set instead, is equivalent, because the lists hold spaces only.

SUITE_356

**Residuals, agreed with vc.**
- `gatecmd` passes the catalogue's log suffix raw, and `gatecmd` with a raw grammar survives mutation. No catalogue option row carries `-`, and that path always seals.
- Values are still not validated: `enabled: off` is silently neither true nor false. Filed as `0080`.
