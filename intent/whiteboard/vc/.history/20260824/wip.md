# vc archive -- 2026-08-24

This node's first day: boot, upgrade-path audit, two fleet sweeps, seven issues touched. Settled blocks folded out of the live board. Each block's live outcome is named at its head; the durable records are the tracker (`intent issues list`), the snapshots (`intent/wip.md` v0.8, `intent/restart.md` v0.7), and hv's inbox.

## MORNING -- settled TODO blocks

### Baize hole-2 thread (outcome: issues 0018 and 0019)

- SETTLED, both sides self-corrected: baize-vc WITHDREW "no seal at all" (the seal exists at Baize, warning at LINE 1 of the sealed .out -- they had globbed tmp/test/ for a check-family gate that seals to tmp/check/). This node RETRACTED its "witness run, LATEST unclaimed" claim symmetrically: LATEST_CRITIC here points at the probe's own stamped run -- the pointers WERE claimed, and a filename-set diff cannot observe a symlink retarget. Same instrument family both times, one hour apart: a filtered query cannot discover what the filter excludes. TWO findings survive: (1) TWO PATHS UNDER ONE NAME -- devbin's empty-staged `check critic` examined 27 files (corpus, no warning); Baize's examined ZERO (warning present); same command, same day, same vendored bytes. (2) PROTOCOL: the verdict (.errors) and the determinate fact (the warning, in .out) live in DIFFERENT FILES; estates wrote "read the seal = .errors" against the old one-file model. Fix shape per baize-vc: the reading order belongs in the SEAL CONTRACT.

### Landing question (outcome: hv ruled vc-commits-everywhere; executed twice)

- Lamplight had an explicit commit-when-you-can order; Laksa a PUSH ruling only ("any node pushes when its work is committed", 2026-08-21) which presupposes committing without ordering it; the other seven no recorded policy. hv ruled the gap closed: vc commits the sweep pathspec everywhere.

### 0049 trace (outcome: issue 0020, its evidence body)

- COMPLETE: no owning tracker among all eight candidate repos on this machine, each refutation by measurement -- Intent (canon-range gap), devbin (range 0001..0016), Lamplight (high-water 0004), Baize (0001), Conflab (0008), and Laksa, Prolix, Riffle (no issue yet raised via `intent issues`; hv's framing: the feature post-dates those projects, which DATES them and is not a convention choice). The citation in three landed commits points at a record that does not exist. "per vc" in 254f63e remains unattributed. Instrument trap from laksa-vc: a bare-number grep across estates false-positives (their ST0049 matches, sounds adjacent, is unrelated).

### Upgrade-audit candidate queue (outcome: issues 0017 and 0021; Icon fix landed)

- Converged-skip healing; `devbin vendor` builtin (three homes fleet-wide); rc 0 with skips; no direction guard; `Icon\r` untracked poisoning source_commit stamps -- fixed at its root (hv's ~/.gitignore_global line 26 lacked the two CRs) or filed.

## AFTERNOON -- completed DOING

### hv's four rulings, executed

1. LANDING: sweep #1 committed in all ten trees -- eight by this node's pathspec pass (Conflab 1579313, Laksa 6baa569, Baize c42d40a, MicroGPTEx eb3ad36, arca_config ae24818, arca_cli e2dcb57, Prolix 94dc169, Riffle 7aef369), Lamplight and Intent estate-side (Intent 300ff747).
2. dc = the DevX Claude sessions at other projects; provenance recorded in the snapshots.
3. PHASE 1: intent/wip.md v0.8 and intent/restart.md v0.7 now POINT AT the tracker instead of restating the open set -- the no-tallies rule applied to the documents that broke it; 0016 Resolutions written and CLOSED; cc inbox note sent.
4. ISSUES: 0017-0021 filed with evidence bodies. Sweep #1 independently confirmed by all five baseline-holding estates before landing.

### devbin#0022 -- D9 reversed, executed end to end

- hv reversed D9 on being shown doctor's "targets 3.2" note; floor major >= 5, hv's pick from the option set. Guard in the dispatcher (one home, parseable by the bash it refuses), RED-CHECKED against the real /bin/bash 3.2.57 before it existed (test failed, then passed). Doctor's note inverted to a check; usage-rules Shell section rewritten (the &-in-replacement rule SURVIVES -- a >= 5 floor still spans 5.1/5.2 semantics); D9 carries its dated reversal in design.md; CI's macOS leg now proves the refusal instead of exercising 3.2; three restricted-PATH fixture classes found BY the suite and fixed at their helpers. Suite 588 ok / 0 failed / bats rc 0 -- the first "baseline" was contaminated by this node's own mid-run edits, owned and re-run clean. Devbin commit 7213128.
- RE-SWEEP: all ten installs, 8 files each, zero skips, doctor green both sides, stamp 7213128 clean, refusal probe confirming the guard LIVE at every install; Baize's consumer shell suite bracketed green-to-green. Landed in all ten trees (24e2240a, cfe6709d2, 2585d21, a09620e4b, 0c373f3, 1d9e773, f157ca6, c3e2027, 556115a, ad0ba20d).
- Consumer-coupling check BEFORE the sweep, positive-controlled at Baize first: their purge test was the only instance (fixed by their own node at d1629da); Conflab and Lamplight carry no runlog-coupled tests; Laksa's are current-by-construction (08-22 fixtures, explicit RUNLOG_WITNESS_RUN=1).

### 0020 adopted and closed

- hv adopted the citation convention same-day; devbin's usage-rules line landed at 5a0e9ed, amended within the hour to LOWERCASE by definition (`devbin#0020`, `lamplight/vc`) after the hub ruled on a case split.

## AFTERNOON -- the queue, emptied

Day one's second half. Eight issues closed, two filed, two fleet sweeps, nine commits here and twenty-two across the estate. Durable records: the tracker, the commits, and `hv/inbox.vc.md`.

### The queue, in the order hv set it

- **0017 + 0021 as one pass** (7a1348d). `devbin vendor` ships: the tree-vs-SOURCE comparison neither doctor (tree-vs-install-time) nor upgrade (knows, only says so by doing) could make. Seven states as the CROSS PRODUCT of two comparisons, and the cell in the corner -- `converged` -- IS 0021's first finding, which is why one pass closed both. The issue asked for two baselines and called them one; resolved by comparing the working tree and naming all three facts in the header. 0021's rc question RULED rather than defaulted (upgrade answers "did I complete", vendor answers "is this level"), and the direction guard warns rather than refuses.
- **0014** (ee1a47c), hv's option B. `git_head_sha` + `git_head_watch_paths` in lib/helpers. Defect REPRODUCED before fixed: the naive literal-path form resolves ZERO watch paths in a real linked worktree and over-watches a normal checkout. Nine tests, the first a CONTROL asserting the fixture exhibits the trap.
- **0018** (bce3df1), hv ruled retire. The cause read before anything was proposed, and it refuted the issue's own hypothesis: not dispatch, not tree shape -- devbin's own `cmd/check` was the ONLY one in nineteen installs. Retired to `cmd/.lib/shell-gate`; the three dead `run: devbin-internal-*` targets now name a real script; `format` and `toolchain` reachable here for the first time in eighteen days; the seal suffix uppercase again, which was the issue's own guessed clue.
- **0019** (2ae8b4a), hv ruled extend-the-promotion over a sentinel. The reading order landed in the seal contract, and the promotion machinery ALREADY EXISTED -- the gap was one word in devbin's own config (`grammar: generic`, which carries no counter). Every other install was already protected.
- **0015** (fb237eb, bf26eb4). Reproduced on demand by the documented route; no longer silent (two announcements where the original had none); closed on the reproduction, NOT on an explanation -- the Prolix instance's own cause stays unexplained and the evidence argues against the route reproduced here.
- **0023** (47a91ce), closed by EXECUTION, because its fix is the sweep procedure.
- **0024** (c92540c), hv's option A. doctor names any project name standing where devbin ships its own. Verified against the thing it was built for: it finds `vendor` at Intent automatically, and would have caught 0018 eighteen days earlier.

### Two sweeps

- **#3 to bf26eb4**, eleven installs, enumerated FROM DISK rather than from a roster: nineteen found, eleven swept, eight excluded WITH REASONS. Intentv2 -- live, committed the same day, never given the bash floor -- was the miss that 0023 was filed about. First measurement of `devbin vendor` at live consumer installs, which was 0017's stated constraint.
- **#4 to c92540c**, the same eleven, delivering the shadowing check so the fix stops being half-delivered. Commit EXIT STATUS checked this time.

### Three things that went wrong, all mine, all caught

- **`check lint` had been red on committed code for a week** (80cdf90) and nobody was blocked, which is the mirror of a false green: a permanently-red gate stops being read. Found by running the gate while closing something else.
- **`ARCHITECTURE-shell.md` still headed a section "Bash 3.2 is a hard target"**, and `help/doctor.md` still said "against the 3.2 target". I reversed D9 in the morning across design.md, usage-rules, doctor, CI and the tests, and missed the as-built document the restart brief points at for exactly that question.
- **Sweep #3's commit loop reported `git log -1`**, so two blocked commits read as successes. Caught only by verifying stamps afterwards.

### Peer traffic

lamplight/vc: their `db proxy` finding correctly NOT a devbin defect; their advice on not inlining infrastructure identity adopted into `docs/authoring-commands.md` with the measured cost that earned it. Told them `vendor` is now a shipped name before they mint a handler at it; they checked, are clear, and have reserved it. They also corrected 0014's wording -- their sites are hardened already, so "untouched" meant undeduplicated, not still broken.
