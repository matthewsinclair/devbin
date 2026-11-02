# cc archive -- 2026-08-05

Rolled out of the live board at localfold. Append-only; never reloaded on pickup.

## DONE this day

- Picked up as `cc` on a greenfield Devbin scaffold (zero commits, no steel threads, no peers).
- ST0001 claimed. Corpus analysis of the four `bin/<prj>` dispatchers across Conflab, Lamplight, Baize and Laksa.
- `design.md` written: corpus findings, prior-art survey of `../Utilz`, decisions D1-D12, layer architecture.
- WP-01..13 elaborated. WP-12 (docs) and WP-13 (pre-rollout Fable review gate) added mid-session on hv direction.
- WP-02: repo skeleton, BATS harness, fixture generators, assertion vocabulary aligned to Utilz, CI matrix.
- WP-03 CLOSED, 7/7 acceptance criteria green: `lib/config` reader plus the annotated schema reference.
- WP-04: `bin/devbin`, `lib/resolve`, `lib/helpers`, Devbin's own config and handlers. 11/11 ACs green.
- `tests/gate` deleted -- superseded by `bin/devbin check all`, closing its Highlander watch-item.
- 91 tests green; gates green; four commits on `main`.

## Superseded decisions

- D7 originally specified two config backends (yq plus a pure-bash fallback) reconciled by a differential test. Reversed during WP-03: one awk-based reader, no yq. The differential test was the price of a Highlander breach rather than a justification for it.

---

## Archived at the second localfold (2026-08-05, evening)

### DONE this stretch

- **WP-05 closed** (16/16). The universal helpers fold: `lib/helpers` made dependency-free by rule (D15), the corpus's six option setters collapsed into one config-driven path (D14), five drift rulings recorded (D13). `parse_common_opts` wired into the dispatcher, closing a WP-04 remainder.
- **WP-06 closed** (16/16). The sealed-gate subsystem ported whole from Conflab with its rationale, plus `run_gate` (D17) and seven named grammars (D16).
- **WP-01 closed** (6/6). AC-01.5's behavioural inventory (D18) and AC-01.6's grammar catalogue (D16) were the last two.
- **WP-08 started.** `lib/builtins` is THE catalogue, moved out of `lib/resolve` rather than copied. Gates family shipped: `lib/gatecmd` + `lib/cmd/{check,test}`, with `check toolchain` and `check critic` ported as tier-1.
- **D19, from hv's challenge.** One rig: a config-declared option with `log:` seals through the same runner a built-in uses.

### Defects found and fixed this stretch

- `command_options` returned the status of its final loop iteration, so an inactive LAST option killed the dispatcher under errexit. Fourth sighting of this class.
- `run_gate` forced errexit ON for callers that had turned it off.
- Log creation was check-then-create; two runs in one minute could share a name. Now `O_EXCL`. The `$$` rung failed first -- a subshell inherits its parent's PID.
- `run_gate` wrote relative to CWD but reported relative to `PROJECT_ROOT`.
- `run_option` let a built-in swallow a config-declared option; `option_unavailable_reason` blamed the language for handler displacement.
- `known_commands` never listed built-ins, so help was empty where dispatch worked.
- A D11 test used a project handler to test built-in scoping and passed for the wrong reason.
