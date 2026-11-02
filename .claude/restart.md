# Devbin -- Claude Code restart

Entry point only; it holds no state.

## Start here

1. Run `/in-session`, now and after every `/compact`.
2. `AGENTS.md`: the tool-agnostic contract.
3. `usage-rules.md`: the DO / NEVER contract.
4. `intent/whiteboard/hv/wip.md`: hv's standing directives, read before starting anything.
5. `intent/restart.md`: the index.
6. `intent/wip.md`: DOING and TODO.

## Ask, do not read a copy

| Question                        | Ask                                      |
| ------------------------------- | ---------------------------------------- |
| What is open?                   | `intent issues list`                     |
| What is live across sessions?   | `intent wb pickup --node <you>`          |
| What runs devbin, right now?    | `bin/devbin fleet audit`                 |
| Why is it built this way?       | `intent st show <ST> design` (D1 to D43) |
| What is the as-built shape?     | `intent/llm/ARCHITECTURE-shell.md`       |
| How does this project go wrong? | `intent/llm/LESSONS.md`                  |
| Does a module for this exist?   | `intent search --kind def <name>`        |
| How is a release cut?           | `docs/releasing.md`                      |

The design record lives in the store: ST0001 holds D1 to D25, ST0005 D26 to D34, ST0007 D35 to D43.

A false green is worse than a failure. Watch every new test go red on broken input before trusting its green.
