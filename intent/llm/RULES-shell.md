# RULES-shell.md

Mandatory shell (bash + zsh) coding rules for this project. Concretises the four agnostic principles for shell idioms.

## Canon Concretisations

- **Highlander** (`IN-AG-HIGHLANDER-001`) -- one canonical implementation per concern. No divergent helper scripts. Source shared functions from `lib/` or a `helpers` script. Concretised by `IN-SH-CODE-006`.
- **PFIC** (`IN-AG-PFIC-001`) -- prefer `case` for branching, pipelines for composition, parameter expansion over awk/sed when possible. No rule in the shell pack concretises it.
- **Thin Coordinator** (`IN-AG-THIN-COORD-001`) -- top-level scripts parse to call to render; business logic in sourced functions. No rule in the shell pack concretises it.
- **No Silent Errors** (`IN-AG-NO-SILENT-001`) -- always `set -euo pipefail` (or document why not). Check exit codes; never `cmd || true` to suppress failures unless the failure is genuinely benign. Concretised by `IN-SH-CODE-003` (bash) and `IN-SH-CODE-004` (zsh) for the options, `IN-SH-CODE-005` for exit codes, and `IN-SH-CODE-001` and `IN-SH-CODE-002`, quoting and `ls` parsing.

Read the full shell rule pack via the installed Intent tool: `intent claude rules list --lang shell` to enumerate, `intent claude rules show <id>` to read one.

## NEVER DO

- NEVER omit `set -euo pipefail` at the top of a script without a documented reason.
- NEVER use unquoted `$var` expansions where word splitting matters (filenames, user input).
- NEVER use `eval` on user input.
- NEVER assume bash 3.2. This project REQUIRES bash >= 5 (issue 0022, reversing D9) and refuses older with a `brew install bash` remediation, so macOS's `/bin/bash` 3.2.57 is refused rather than targeted. The floor block at the top of `lib/helpers`, and everything in `bin/devbin` before it sources `lib/helpers`, must stay parseable by 3.2.
- NEVER duplicate helper functions across scripts; source from a shared library.
- NEVER manually wrap lines in markdown files.

## Project-Specific Rules

<!-- Add shell-specific rules unique to this project below this line. Cite IN-SH-* IDs where applicable. -->
