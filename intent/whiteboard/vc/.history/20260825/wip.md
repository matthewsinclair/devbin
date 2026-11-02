# Validation Claude (vc) -- archived DOING, 2026-08-25

Archived at the localfold. Live board keeps the header, TODO, Watch-outs and Decisions.

## DOING (closed this session)

- **Issue 0031 -- the overnight CI red.** Run 32787816443, one test of 649, macOS only, on a commit that changed a single whiteboard file. `doctor` reported a vendored file unowned on the line after certifying all 28 intact. Cause: `printf '%s\n' "$states" | grep -q` under `set -euo pipefail` -- grep returns on the match, printf takes SIGPIPE on a write that has not landed, pipefail promotes 141 to the pipeline, the `&&` does not fire. Three real sites (`doctor:196`, `new:131`, `check:402`) plus one CI step. Landed `0bf263e`, CI green.
- **A fourth site was REFUTED and reverted.** devbin/cc showed `head -n1 "$f" | grep -qE` cannot fail -- head writes one line, grep is line-oriented, so its decision point is at or after the writer's last byte. Driven: ONE 200KB line lost 0/200, MANY lines totalling 216KB lost 200/200. The rule is "the reader can decide before consuming everything the writer will write", not "a reader that exits early". `cmd/.lib/shell-gate:58` was found by cc looking for a fifth site; it is sound and was left alone with the measurement on the line.
- **Issue 0032 -- `docs treeindex` removed in full**, on hv's instruction, after intent/vc relayed hv's ruling that `intent treeindex` is retired in Intent v3 with no replacement. devbin shipped it as a catalogue row whose body was `intent treeindex "$d"`, vendored to every estate carrying the runtime. Ten files; two tests ADDED so the removal is asserted. Landed `57ecd5b`, CI green.
- **The guards were armed by devbin/cc during this session**, and `57ecd5b` is the first commit in this repository's history the whiteboard guards have ever checked: `guards: 3 ran, 1 skipped`. That closes the exposure 0030 named, for commits from here on.

## Cross-estate, this session

- Found the two shipped whiteboard guards carried the same pipefail defect, in the fail-open direction, at `whiteboard-clock-guard.sh:246` and `whiteboard-header-guard.sh:201`, with `canon-ignore-guard.sh:133` latent (safe only because it sets `set -u` not `set -uo pipefail`). Routed to intent/vc, ruled by hv as BOTH TREES / LOCAL ONLY / no v2 push, fixed and verified by intent/dc: identical by object id in both trees, 5/5 blocked against the fixture that was 0/5, negative control silent-not-mute.
- **Warned that guard bodies resolve live from `$INTENT_HOME`, so a fix changes every consumer's commit path with no consumer action -- then found the window twice inside an hour.** dc's guards and cc's marker repair, both live to every consumer and recorded nowhere. Discovered by three of five guard hashes disagreeing with values measured an hour earlier.

## Three corrections against myself, all one family

- **Published a repro I had not run.** Narrowed the line width from 17 bytes to 6 while writing it up for intent/vc, never re-executed; it produced 22892 bytes, returned lost=0/20, and read to them as a REFUTATION of the finding it was sent to support.
- **Asserted a "sharp cliff at 64K"** that was true at one line width and false as a statement. Holding bytes constant at 60000 and varying only width: 7/20 at width 6, 0/20 at width 60.
- **Filed the collector row that cc refuted**, then wrote a false explanatory comment above the replacement -- worse than the line it explained.

Each was caught by a peer driving rather than relaying, never by me. The general forms are in `intent/llm/LESSONS.md`.
