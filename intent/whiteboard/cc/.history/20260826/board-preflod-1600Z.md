# cc board -- FULL COPY taken 2026-08-26 16:0xZ, immediately before the localfold trim

**This is the verbatim board as it stood at the end of the Intent3 cutover day**, archived BEFORE anything was removed from the live file, and committed before the trim in a separate commit. That order is this board's own lesson: an entry on it existed in NO GIT COMMIT AT ANY POINT, going from uncommitted working tree straight to deleted, with the only surviving copy an untracked file in `.history/`.

The durable record of the day's measurements is `../../fleet-baseline-20260826.md`, which is NOT archived here and is not summarised there or here -- summarising it is what went wrong twice on the day.

---

---
node: cc
name: Control Claude
role: control
session_id: 90be8efe-9868-472a-ac07-f8ed1bb7e306
heartbeat_at: 2026-08-26 14:27Z
status: active
focus: "gate_critic FIXED and suite green 663/663: the gate now reads an armed count BEFORE a verdict and refuses on an empty denominator. Predicate is --format json, never the census line. v2 and v3 have DIFFERENT JSON contracts so the frozen v2 reads its stderr census -- the one case where display-parsing is not a bet. Three false signals today, all in MY instruments: a control is only a control if you can say what would make it FAIL"
claims: []
---

# Control Claude (cc)

## DOING

- **`gate_critic` FIXED, SUITE GREEN 663/663 (2026-08-26 14:27Z).** It reads an armed count BEFORE it reads a verdict and refuses on an empty denominator. Real v3 rc=1 (`0 rules armed -- the rule library answered EMPTY`), real v2 rc=0 with 2 armed. 7 new tests; stashing the fix confirmed **4 of 7 discriminate**, 3 are controls green both ways. Green read off full TAP with a matching plan line, not a tail.
- **TWO SCOPE LIMITS, neither obvious from the diff.** It covers `devbin check critic` ONLY -- Devbin's pre-commit calls `intent critic <lang> --staged` directly and never reaches `gate_critic`, so **the hook path stays un-gated until 3.0.1**, including for the commit carrying this fix. And it is one estate; the other ten fail loudly at `lib/cmd/check:118` and return on re-vendor.
- **v2 AND v3 HAVE DIFFERENT JSON CONTRACTS** -- v3 an object with `armed`, v2 a bare `[]` with the census on stderr. The first fix hard-failed a v2 that arms 2 of 6 rules fine; **refusing a healthy gate is its own outage**. The v2 path reads its stderr census, justified by the only argument that makes display-parsing not a bet: a renderer that can never change again.
- **THREE FALSE SIGNALS TODAY, ALL IN MY OWN INSTRUMENTS** -- a bats harness that died before running (and whose assert-failure and assert-absence tests passed anyway), a `pgrep -f` liveness check matching its own command line, and a `bats | tail -6` whose exit code was the trailing `echo`'s. **A control is only a control if you can say what would make it FAIL.** With devbin/vc's pair: none was a broken test; each was a test removed from the causal path and still reporting.
- **TWO WRONG MECHANISMS TODAY FROM ONE HABIT** -- blamed v3 for the Laksa block loss without reading the commit body; blamed v3 for a missing `--languages` without running `--help`. Both corrected in place. Inferring a mechanism from a symptom when the thing itself is one command away.

- **THE BLOCK HAS TWO HALVES AND ONLY ONE IS THE PROJECT'S (2026-08-26 13:47Z).** v3 3.0.0 regenerates the marker COMMENT from `config.json` and carries the BODY byte-for-byte. Laksa `7ae7f5bea` proves both in one commit: comment rewritten (`Matthew Sinclair` -> `matts`, -11 b), body `2e5bb699...` identical across 4568 bytes. Devbin corroborates -- 914-byte block identical through hop 3. Upstream fix is `Intent 8ba6c026 fix(0056/06)`.
- **FALSIFIABLE PREDICTION ON THE RECORD: the next regeneration of Baize or Riffle drops `, created <date>` again.** Both blocks are pure comment with an EMPTY body (`sha256("")`), so neither ever lost project content; the hand restorations wrote into the one line the tool composes and rewrites. Untested so far -- the re-stamps did not touch `CLAUDE.md` on either. **Fix: provenance belongs in the body, where preservation is proven.**
- **MY OWN SWEEP HAD A FALSE NEGATIVE, ON MY OWN ESTATE.** `git log --grep='migrate to v3 canonical'` called Devbin not-landed; Devbin landed at `5895df6` under different wording. Widening the pattern only added noise. **A message sweep reads the narration; `jq -r '.intent_version'` reads the state.** Third time today for that shape.
- **DEVBIN ROWED, `5895df6`:** 914-byte block byte-identical `ced80f6` -> `5895df6`. The note warning that hand edits get eaten survived the thing it warns about.
- **RIFFLE'S OWED RESTORATION IS DONE AND VERIFIED** -- `37c5dab`, block back to the before-digest `c07e405f...` at 132 b. Outstanding item from this morning, closed.
- **MicroGPTEx is migrated but NOT COMMITTED** (8 modified, 6 untracked). Before-state safe at `HEAD:CLAUDE.md` 687 b `4fe43b3a0d25...`. **Lamplight un-landed with 17988 b of body -- the largest in the fleet; sequence it deliberately.**

- **LAKSA ROWED, ONE REAL LOSS FOUND AND RESTORED BYTE-EXACT (2026-08-26 12:26Z).** The authored `intent --version` sentence was dropped at `2bf06a276` and is back verbatim at `f5133dc87` -- dropped and restored line share sha `cd192b42...`, block 4529 -> 4692 b, the 163-byte delta fully accounted. It hid because it sits in the slot the v2 template uses for its own version line: **template by position, authored by content.** Prolix's same slot genuinely was template and dropping it was a repair. Only a line-by-line diff against a pre-cut baseline separates them.
- **I PUBLISHED THE WRONG MECHANISM AND HAVE CORRECTED IT IN PLACE, NOT DELETED IT.** I called this a v3 loss mode. It is not: neither before-file had the generated footer, so hop 3 HELD both, and intent/vc carried the content across a `--force` by hand -- **named line by line in the commit body of the very landing I was rowing.** I inferred a tool behaviour from the shape of a diff while the commit that produced it stood there explaining itself. `git show --format=%B <sha>` is one command. The rule I keep citing has a second half I skipped: **the commit message IS disk.** Both accounts reconcile exactly -- vc's "every line present" covers the 123 project lines, my 25 absent are 23 boilerplate + author + the one real line.
- **The `nothing to lose` correction SURVIVES the mechanism correction.** That column asked whether a block existed, not whether content did, and it was wrong about content regardless of who moved it.
- **ARCA x2 HOLD THE ONLY COPY OF THEIR STP-TO-INTENT MIGRATION HISTORY (2025-07-20) AND HAVE NOT LANDED YET.** Cheap to preserve before, recoverable only from git after. Routed to intent/vc.
- **PROLIX `bc620d4` LANDED UNANNOUNCED** -- found by sweeping, not by being told. `git log --grep='migrate to v3 canonical'` answers "what has landed" fleet-wide without needing an announcement to be correct. Run the sweep before opening rows.
- **A PREDICTION OF MINE FAILED AND IS RECORDED AS A RESULT.** The hooksPath false-green is NOT live at Laksa: `pre-commit.intent` is executable in both locations at 20159 b and Laksa's chain block resolves via `git rev-parse --git-path hooks`. Structural hazard stands (identical-today is what hides tomorrow's divergence); the failure mode does not.

- **HOLDING for intent/vc's next instruction, by hv's order.** hv called a full STOP at ~11:45Z; it was relayed to intent/vc and devbin/vc and propagated fleet-wide to cc/dc/ic. hv then scoped a cleanup, check, localfold and compact -- **which is this. The hold resumes on the bounce.** hv lifts it, not intent/vc.

- **DEVBIN ITSELF IS MID-CUTOVER AND COHERENT.** hop 1 committed by devbin/vc at `75bb005` -- "recorded rather than left floating" -- so the estate is v2 2.19.0 with `intent_version=2.19.0` declared and no half-applied tree. Rollback point `.backup/backup-20260826-124753`. hop 2 was blocked on dc's rebuild when the stop landed; hop 3 never ran, so **Devbin's own 914-byte user block is still intact.**

- **FLEET VERIFICATION, ASSIGNED BY intent/vc 2026-08-26.** This node owns the devbin-side verification for the Intent3 cutover. Rows, protocol, live hazards and the pre-cut capture are in [`fleet-baseline-20260826.md`](fleet-baseline-20260826.md) -- **that file is the record, and it is not summarised here**, because summarising it is precisely what went wrong twice today.

- **THE TWO CORRECTIONS, KEPT BECAUSE THEY ARE ONE DEFECT.** Both were reported to intent/vc and both were caught by a peer rather than by me.
  - **Riffle was called a clean landing and had not landed.** What moved was hop 1 of 3, from the frozen v2 tool. Rule taken from intent/vc: **a change observed is not a landing** -- the landing signal is vc naming the project WITH A COMMIT SHA.
  - **"Laksa is the only estate setting `core.hooksPath` -- I checked all of them."** It is three: Intent and Intentv2 set `.githooks`, Laksa sets `bin/hooks`. I had measured `Intent .githooks` myself an hour before saying it.
  - **THE COMMON DEFECT, AND IT IS NOT CARELESSNESS: BOTH TIMES THE CORRECT VALUE WAS ALREADY ON DISK IN MY OWN OUTPUT.** Riffle's refutation was three rows up in my own table -- a supposedly-migrated estate showing a hook BYTE-IDENTICAL to v2's 20899. I reported a conclusion I had formed instead of the measurement I had taken. **Having the control in hand is not the same as running it**, and a summary is where a measurement goes to become an assertion.

- **UNACTIONED ASSIGNMENT, SURFACED TO hv 2026-08-26 10:49Z, NOT STARTED.** vc appended `## (2026-08-26 10:01Z)` to `inbox.vc.md`: **hv has ruled that cc lands 0034's third instance** -- re-verifying the measurements independently first, with the requirement landing as a NEW R9 and R4 left intact. hv separately told this node to localfold and hold at ~10:20Z, which is LATER, so the two may or may not conflict. **That is hv's call and this node has not assumed either way.** Nothing started, nothing claimed.

- **THE NEAR-MISS THAT FOUND IT, AND IT IS THE MOST IMPORTANT THING ON THIS BOARD.** That entry existed in NO GIT COMMIT AT ANY POINT. It went from uncommitted-working-tree straight to deleted, and the only surviving copy was an UNTRACKED file in `.history/`. Two independent protocol slips composed:
  - **Mine: a pickup reads the inbox ONCE, at the start, and an inbox is append-only and LIVE.** So "no opening assignment" was a statement about 09:26Z, not about the session -- and I reported it to hv as though it were the latter. Then at 10:45Z I cut the inbox to its sentinel without re-reading it.
  - **vc's: `b9d9d7d` committed `cc/inbox.vc.md`, a file vc does not own**, sweeping up my working-tree cut with a broad pathspec. The protocol's `git commit --only <you>/...` rule exists for exactly this.
  - **THE RULE THIS YIELDS: RE-READ AN INBOX IMMEDIATELY BEFORE CUTTING IT.** A cut is the one operation that makes an unread entry unrecoverable, so it is the one operation that must be preceded by a fresh read. Archiving first is necessary and was NOT sufficient here -- the archive was untracked at the moment the cut got committed by someone else.
  - **AND THE COMPOSITION IS THE REAL LESSON: single-owner and archive-before-cut are not independent safety nets.** Each is written down as if it stands alone. Breaking both in the same minute removed every copy but one, and nothing anywhere reported it -- the cut succeeded, the commit succeeded, and the inbox read as legitimately empty. Found only because a `cmp` I ran for an unrelated reason returned EOF instead of matching.
  - Recovered by cross-checking against vc's own independent archive (`vc/.history/20260826/0034-third-instance.md`, committed in `b9d9d7d`); all five load-bearing predicates verified present in the restored copy. **The handled 12:42Z entry stays archived; the unhandled 10:01Z entry is restored to the live inbox where it belongs.**

- Nothing in flight, no claim held. **DEVBIN IS PAUSED while Intent3 is completed (hv, 2026-08-25) -- parked, not finished.** The tracker is NOT empty: **issue 0034 is OPEN** (a seal states its verdict and not its reach; confirmed on a live full run at `4505a0f`). 0029 to 0033 all closed 2026-08-25. This line said `Tracker empty` until 2026-08-26, which was true when written and false by the next boot -- a count on a board is the thing that drifts, so it names the issue rather than a tally.

## TODO

- **THE v3 CUTOVER, and this is the live item on this node (2026-08-26 09:52Z).** intent/vc instructed this node under hv's sanction -- hv's quoted words: *the devbin Claudes are up and running now and can be instructed*. **hv CONFIRMED the sanction directly at 2026-08-26 10:13Z** ("Yes, confirmed"), so this ran on hv's authority and not on a peer's say-so -- which is the order the peer themselves asked for. Findings sent back to intent-vc the same minute, after being recorded here rather than before. **There is no durable channel between the Intent and Devbin estates -- no inbox either direction -- so this entry IS the record.** Two asks, both answered below from disk rather than from their framing.

#### ON WAKE, READ THIS BEFORE CITING ANY NUMBER BELOW

**Everything below was measured on 2026-08-26 morning against a PRE-CUTOVER world** -- `INTENT_HOME` pointed at `Intentv2` and `intent --version` said 2.19.0. **The cutover is precisely the event that invalidates it.** A number below is a READING, not a property, and this node has twice watched a snapshot get read as a record. Folded with the volatility attached rather than left for a future session to discover.

**VOLATILE -- re-measure, do not cite:**

| what was measured                                                       | what re-measures it                                                      |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `INTENT_HOME` = `Intentv2`, version 2.19.0                              | `intent info`, `intent --version`                                        |
| 11 estates uniform at `4dc899de`, 10 behind HEAD `79bfaec`              | `find . -maxdepth 4 -type d -name .devbin`, then each `# source_commit:` |
| devbin's frozen hook byte-identical to v2 canon, 86 lines from v3       | `cmp .git/hooks/pre-commit.intent <resolved>/lib/templates/hooks/pre-commit.sh` |
| guard bodies: 4 identical, `canon-ignore` 28B, `pre-commit.sh` 86 lines | re-diff -- Intent's tree is being edited TODAY                           |
| the dispatch-table exit-code contradiction                              | **its ABSENCE is the desired outcome, not a missing finding.**           |

**STRUCTURAL -- survives the cutover, cite freely:**

- **Guards are the runner's SIBLINGS by construction** (`GUARD_HOME` from `${BASH_SOURCE[0]}`). A design property, not a version fact -- it is why a v3 runner cannot pair with v2 bodies, and it does not depend on which version is installed.
- **The three-layer propagation asymmetry**: bodies and roster resolve live, the HOOK is copied. Structural until the hook stops being copied, which is not on anyone's list.
- **Devbin's shipped intent surface is 3 call sites in 2 files**, and `lib/cmd/check:118` fails CLOSED.
- **Devbin reads `$INTENT_HOME` NOWHERE** -- zero references across `bin/`, `lib/`, `cmd/`. The entire coupling is those three commands and their exit codes.

**THE MISREAD THIS ENTRY EXISTS TO PREVENT.** The likely wrong move on wake is to re-run the analysis, get different numbers, and read the difference as a devbin regression. **It will not be one.** Devbin is paused and cannot have changed; what changed is the thing it measures against. Diff the world, not this node.

**The one check worth running FIRST on wake, because it is the only one that is a real finding rather than a reading:** `intent critic --languages` must still exit 0. If it does not, `lib/cmd/check:118` calls `die` in all 11 estates at once -- it fails closed, it does not degrade. Everything else in this entry can be stale without anything breaking.

**SENT 2026-08-26 10:13Z to intent-vc** (cross-session, hv confirmed): both asks plus the dispatch-table escalation. **That send is not a durable channel** -- there is no inbox either direction between these estates, so if the answer matters after their compact, this board is the only copy.

### Ask 1 -- do the guards still resolve and run when `$INTENT_HOME` becomes a v3 install?

**The bodies and the roster do, by construction. The hook that FINDS them does not, because it is copied.** Three layers with three different propagation properties, and the middle one is the one everybody assumes:

| layer                                                          | lives                                                | propagates at cutover |
| -------------------------------------------------------------- | ---------------------------------------------------- | --------------------- |
| guard bodies (clock, header, canon-ignore, append-only)        | `$INTENT_HOME/lib/templates/hooks/*.sh`, read live   | YES, automatically    |
| the roster (`GUARDS=` array)                                   | `.../pre-commit-guards.sh`, read live                | YES                   |
| `pre-commit.intent` -- the hook that resolves both             | COPIED into `.git/hooks/` by `claude upgrade`        | **NO -- FROZEN**      |

- **v3 carries the full set.** `/Users/matts/Devel/prj/Intent/lib/templates/hooks/` has all seven files. Roster identical. Bodies: `pre-commit-guards.sh`, both whiteboard guards and `append-only-guard.sh` are BYTE-IDENTICAL v2 to v3; `canon-ignore-guard.sh` differs by 28 bytes; `pre-commit.sh` by 86 diff lines.
- **The strong guarantee, and it is stronger than "the files happen to exist":** `pre-commit-guards.sh` sets `GUARD_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. **Guards are the runner's SIBLINGS by construction**, so a v3 runner can never pair with v2 bodies. The comment says why: asking `intent info` a second time invites the two answers to differ.
- **The gap: devbin's frozen `.git/hooks/pre-commit.intent` is byte-identical to v2 canon and 86 diff lines from v3 canon.** It still functions under v3 (it needs only an `INTENT_HOME:` line out of `intent info` plus the runner at that path), but every estate needs `intent claude upgrade --apply` to pick up v3's added self-hosting branch: if the repo being committed IS an Intent source tree (`lib/templates/hooks/pre-commit-guards.sh` + `VERSION` both present), guards come from the repo, not `$INTENT_HOME`. Inert for the nine non-Intent estates; live for `Intent` and `Intentv2`.
- **`intent info` rc REPORTS, it does not GATE** -- deliberate, and it is what keeps the cutover safe. v3's `Facade::open` migration refusal returns 1, so during cutover every unmigrated project prints one line per commit and the guards still run.

### Ask 2 -- what devbin ships that the fleet commits through

**Their figure was 16 projects. The number that matters here is 11**, and the two are answering different questions -- 16 is Intent projects, 11 is estates carrying a vendored devbin payload.

- **PUBLISH THE PREDICATE: my first one returned 9 and was wrong.** `*/bin/.devbin/manifest.sha256` from `prj/` is depth-3 and misses `Arca/arca_cli` and `Arca/arca_config`, which sit one level deeper. `find . -maxdepth 4 -type d -name .devbin` gives **11 with manifest+lib**, plus Devbin's own partial self-vendor (config + cmd + help, no `lib`, no manifest). The 9 was my glob's depth, not the fleet's size.
- **All 11 uniform at `# source_commit: 4dc899de5...`, 10 commits behind devbin HEAD `79bfaec`.** NOT `0257f7a` as vc's 2026-08-25 12:42Z inbox message reported -- `4dc899de` (`devbin --version`) is two commits LATER, so a re-vendor followed that message. No drift; the message is stale.
- **The shipped intent-CLI surface is exactly THREE call sites in TWO files** of the 34 shipped per estate:

| shipped file        | call                        | behaviour on a bad exit                    |
| ------------------- | --------------------------- | ------------------------------------------ |
| `lib/cmd/check:118` | `intent critic --languages` | **FAILS CLOSED -- `die`.** Hardest edge.   |
| `lib/cmd/check:141` | `intent critic <lang> ...`  | any non-zero -> rc=1                       |
| `lib/cmd/docs:37`   | `intent agents sync`        | warns, propagates rc                       |

  `intent treeindex` was already REMOVED from `lib/cmd/docs` on 2026-08-25 for exactly this reason -- v3 retired it with no replacement. v3's dispatch table keeps `critic --languages` at `disposition: keep`, noted *consumed by the pre-commit gate so the gate and the runner cannot drift*. So the hard edge is declared safe.

### The finding to escalate, and it is NOT in devbin

**v3's `surface/dispatch-table.json` contradicts itself on `critic`'s exit codes, in the direction that inverts a gate.** `observed.exit` still carries `code 2 -- findings present at or above --severity-min -- THE MEANINGFUL ONE (INV-04)`, while its own `defects[0]` records that as WITHDRAWN: *Findings-present is `exit 1` at `bin/intent_critic:348`. It was never in the set.*

**Measured against the binary, not the table:** `bin/intent_critic:348` is `exit 1` (findings), `:334`/`:347` are `exit 3` (refused), `:89`/`:95` are `exit 2` (usage). **The withdrawal note is right; the `observed.exit` rows are wrong and are the rows a builder reads first.**

Why it is devbin's problem: the frozen `pre-commit.intent` legend is `0 clean / 1 findings BLOCKS / 3 refused BLOCKS / * fails open LOUDLY`, and deliberately does not name 2 -- because v2 and v3 disagree about what 2 means. That is correct against the as-built. **If v3's critic is built to `observed.exit` instead, findings become exit 2 and the gate fails OPEN on every finding in all 11 estates, silently.** The table's own `target.question` already says this in those words -- *the gate inverted, in this repo and in every consumer* -- so the hazard is that the correction is filed one field away from the rows that carry the error.

Adjacent and UNRULED, recorded not raised: `wp07_owes` has `intent critic` with no language exiting **2 in v2, 1 in v3**, `target.state: pending-hv`. Devbin never invokes critic without a language, so it does not bite here.


- **Read `intent/llm/LESSONS.md` and `usage-rules.md` before starting anything.** That is where this board's watch-outs went, and where 0033's went today.

## Watch-outs

- **This section is deliberately short.** The ~90 entries that stood here were promoted to `intent/llm/LESSONS.md`, `usage-rules.md` and the owning projects on 2026-08-24. A board is the wrong home for a lesson: boards are archived when their work closes, and the lesson outlasts the work.
- **The fold's archive step runs BEFORE the cut.** Reversed on this node on 2026-08-25 morning: the board was cut to a summary and then archived, so the archive captured the summary while reading as a full record. It fails silently -- the archive exists, is non-empty, and is wrong. Caught by size, not by any gate. This afternoon's fold asserted the archived inbox was byte-for-byte identical to the live one before cutting it.

## Decisions

- Design decisions D1 to D24 are permanent in `intent/st/COMPLETED/ST0001/design.md`. hv's standing rulings are on `hv/wip.md`.
- **2026-08-25's rulings are NOT carried here.** They are in the resolutions of `intent/issues/CLOSED/0029`, `0030` and `0033`, which is where a ruling about an issue belongs. A second copy on a board drifts, and the board is archived when its work closes while the issue is not.
