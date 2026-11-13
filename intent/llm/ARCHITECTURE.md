# ARCHITECTURE.md

**The architecture of this project is documented in [ARCHITECTURE-shell.md](ARCHITECTURE-shell.md).** Read that file.

This one is the language-agnostic scaffold Intent generates for every project. Devbin declares exactly one language, `shell`, so the per-language file is the real as-built and this would only ever be a second, thinner copy of it. Two documents describing one architecture is the drift this project spends most of its rules preventing, and a reader picking the wrong one of two near-identically named files is not a hypothetical.

It is kept as a pointer rather than deleted because the Intent tooling generates and expects it.

## Where to look

| Question                                                | File                                                                    |
| ------------------------------------------------------- | ----------------------------------------------------------------------- |
| How is the runtime layered? What may depend on what?    | [ARCHITECTURE-shell.md](ARCHITECTURE-shell.md)                          |
| Which module owns this concern? Does one already exist? | [MODULES.md](MODULES.md)                                                |
| How does this project go wrong?                         | [LESSONS.md](LESSONS.md)                                                |
| Why is it built this way?                               | the threads' `design.md`: ST0001 D1-D25, ST0005 D26-D34, ST0007 D35-D43 |
| How do I use it?                                        | `README.md` and `docs/` at the project root                             |

**The design record is not on disk.** It left the tree at `355e5e9`, when completed threads stopped being realised, and it lives in the store as each thread's `design.md` attachment. Read it with `intent st show ST0001 design` (and `ST0005`, `ST0007` for the later decisions). For ST0001 that prints the same bytes as the file the tree held before `355e5e9`, which that commit proved by rebuilding the file from the store alone.
