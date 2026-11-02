# cc archive -- 2026-08-07

Rolled out of the live board at the 2026-08-07 globalfold. Append-only; never reloaded at pickup.

## What closed today

**WP-12 -- documentation.** `README.md`, `docs/configuration.md`, `docs/authoring-commands.md`, `docs/migration.md`, authored help for devbin's own four lifecycle commands, and `tests/unit/documentation.bats`. Gate PASS. Committed as `c675da6`.

The organising idea: prose rots differently from code, because nothing fails when it goes stale. Every document is tied to something the suite already trusts -- the config reference and the annotated example both held to the schema in `lib/config`, in both directions; the README's command surface held to the catalogue the same way. That upgraded AC-01.4 and AC-03.7 from asserted evidence to tests, both of which had claimed the reference documents the schema while nothing checked it.

**Issue 0001 -- raised, ruled and closed the same day.** hv ruled "do the sensible thing". Framework options now carry the language whose commands consume them and are offered on exactly that D11 axis, with parsing and the listing going through one predicate. The ruling landed in `design.md` D20 as well as the issue. Committed as `79d9d0b`.

## Resolved, archived from TODO

- **`intent/llm/ARCHITECTURE.md` was the unfilled Intent template**, sitting beside the 163-line `ARCHITECTURE-shell.md` under a nearly identical name. Now a pointer plus a where-to-look table. Kept rather than deleted because the Intent tooling generates it.
- **Issue 0001 needed an hv ruling.** It got one, was implemented, and is CLOSED. AC-14.16, AC-14.17, AT-14.32 to AT-14.36.

## Decisions archived -- settled, and the next work does not need them in front of it

- (2026-08-06) **For hv, a cost bought deliberately**: the test harness installs fixtures through the real `devbin install` (D24), making the whole suite the installer's integration test, at roughly 45s. hv has seen the trade and it stands. Reversible in one function.
- (2026-08-07) **The documentation split is a Highlander boundary**, registered permanently in `intent/llm/MODULES.md`. Seven places could carry prose about a command and each answers one question. Registered there, so it does not need to live on the board.
- (2026-08-07) **Where a framework command's own narrative lives is answered, not implemented.** `help_file` reads `bin/.devbin/help/<cmd>.md`, on the PROJECT's side of the seam, so an installed project gets only the generated answer for `install`, `upgrade`, `doctor` and `new`. WP-12's answer: `docs/` carries the narrative and devbin's own authored help demonstrates the path. A `lib/help/<cmd>.md` fallback shipped with the runtime is the right shape if hv wants it -- small, on devbin's side of the seam. Recorded in `impl.md` and `tasks.md`; not a blocker for anything.

## The two failures worth remembering from this session

**Seven tests were destroyed by a filename collision, and two green gates did not notice.** The documentation tests were written to `tests/unit/docs.bats`, which already existed as WP-17's suite for the `docs` COMMAND. The only evidence was arithmetic: the suite's total was exactly consistent with what had been added and inconsistent with the total carried in the session notes, and that gap was explained away as a stale note. It was not stale. Restored from git; the new file is `documentation.bats`.

The durable form is now a watch-out and a rule: **never record a test count in a tracking doc.** It is stale the moment it is written and it is a second source for a fact the gate already owns -- D23 applied to a number, and it drifted exactly as D23 predicts. hv ruled the same, independently, the same day.

**Three output assertions had been silently disarmed.** Writing `--` ahead of a pattern does not protect it: the helpers read `$1` directly, so the end-of-options marker BECOMES the pattern, and every listing contains `--` because the first line is `<name> -- <tagline>`. Three assertions passed while checking nothing, including the only one covering the framework-option behaviour issue 0001 fixed. Found only because a fourth, written the same way, refuted the marker and failed for an unrelated reason. `harness.bats` refuses the shape structurally now.

The general form is the part worth keeping: **a habit adopted for safety silently disabled the thing it was protecting.**
