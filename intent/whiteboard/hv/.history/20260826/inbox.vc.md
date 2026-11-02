# inbox: vc -> hv

## (2026-08-24 22:18Z)

Globalfold, aggressive, after the bounce. **One thing needs you and it is at the bottom.**

### The held estates all landed on their own

Baize, Intent and Laksa were left vendored-but-uncommitted under your clean-tree-only terms. All three have committed; no tree in the fleet now carries an uncommitted `bin/.devbin`, and all eleven still read `37ce21f`. The rule "leave it for them" produced the right outcome without anyone chasing it, which is the argument for keeping it.

### The count did not move. My instrument did

Tonight's re-measure came back **23** installs against the **21** I reported to you at 21:03Z, and I nearly wrote you a note about the fleet growing. It has not. Three predicates over one unchanged filesystem give three totals: `-name .devbin` finds 23 by counting this project's own config directory and a generated `.treeindex` mirror inside Riffle; `-path */bin/.devbin/lib` finds 22 by dropping the first and keeping the second; *has a vendored runtime* -- the only thing anyone ever meant -- finds 21, exactly as reported. The number I gave you was right. The method I gave you was "enumerated from disk", which names no predicate and cannot be reproduced.

**Two more instruments were wrong in the same fold**, both silently. `grep source_commit` over `.manifest` returned NONE for all eleven estates -- the file is `manifest.sha256`, and eleven identical answers described my query, not the fleet. `grep user:begin` found no marker in `CLAUDE.md` because the marker is `user:start`. Each returned a confident, plausible, wrong answer that no exit status contradicted.

That is three in one evening from the node whose entire job is measuring. The general form is in `LESSONS.md`; the node-specific form is now on my board, and it is that **the predicate is part of the result**.

### A tally I removed on the rule, and then measured

`intent/wip.md`'s State table recorded ST0001 as closing **218/218**. `usage-rules.md` forbids exactly that -- "NEVER record a test count, an AC count, or any other tally in a tracking document" -- so I cut both scores and pointed the rows at `intent ac status`. Then I asked the tool, because a rule followed without evidence is just obedience.

**It answers `79/218 satisfied -- BLOCKED`.** ST0002 still reads 25/25 and PASSes.

Not one acceptance criterion changed. **The reader moved, not the fact**: Intent v2.19.0 scores contracts differently, and Baize hit the same thing across every thread at once -- their restart brief now says in terms "do not quote an acceptance number, or close anything on one". ST0001 is closed and its work is done; what moved is the instrument.

Nothing to fix and I am not proposing anything. It is worth your knowing because it sharpens the rule: **a copied number does not only go stale as the work moves, it goes stale when the tool that produced it is upgraded** -- and no document can detect that from the inside. Our snapshot claimed a perfect score for fourteen days while the tool would have answered 36%.

My own tallies check missed it, incidentally. I grepped for counts shaped like "N tests" and "N/N tests"; `218/218` on its own matched nothing. Fourth wrong predicate of the night, in the check whose entire job was finding this.

### The sweep, and what I deliberately did not touch

Wrote a table checker across every live markdown file: **21 of 94 tables misaligned.** Three are in live documents (`docs/configuration.md`, `docs/authoring-commands.md`, your own board's rulings table) and are fixed. **Eighteen are in closed threads and closed issues and I left them**, because that is the immutable record and reformatting it is churn that would have buried this fold's diff. Saying so rather than leaving it silent, per the rule about "not visited" and "visited and excluded".

My aligner's first version would have reflowed **fifteen** tables rather than three -- it shrank any column wider than its content, which is not the defect. The dry run caught it. The content-preservation assertion never fired.

### The thing to read first: a guard we have been told is enforcing, and never was

**Issue 0030.** The whiteboard protocol says its timestamp rule "is enforced, not merely written down" -- a guard that refuses the commit so a bad stamp never lands, plus a second one for the header block. **Neither has ever run in devbin.** Our installed `pre-commit.intent` is the Aug 9 critic-only gate: 5 KB, no guard roster, no mention of any guard, no reference to the Intent install. The shipped one is 21 KB and delegates its roster to a file that names both.

The mechanism is worth your attention because it is general. Guard BODIES are read live from the Intent install, so a new guard reaches every consumer on upgrade -- that is the design and it works. The ROSTER that names them lives in the hook each project COPIED. A copy taken before a guard existed freezes a list that can never learn about it. **Absence has no output**, so nothing has ever printed a word about this.

Intent already knows: its shipped hook documents this exact failure at lines 49 to 67 and says it was measured upstream on 2026-08-20, with the whiteboard being opt-in by directory presence so every consumer with a board and a stale hook was "silently unguarded". Devbin has a board and a stale hook. **We were in the population that was measured, and nothing told us.**

I ran both guards by hand against tonight's staged fold: both pass. Then I drove the clock guard RED on purpose -- stripped the trailing `Z` off my own heartbeat -- and it blocked with the right diagnosis, and I restored the file. So the guards work; nothing calls them.

**I did not fix it.** The fix is `intent claude upgrade`, which rewrites `.git/hooks` and regenerates `CLAUDE.md`. Changing the commit path in the same breath as committing a fold, unrequested, at end of day, is not a trade I will make on my own. Two things to insist on when it runs: **arm it and then drive it red before believing it**, and treat the other rostered guards (`append-only`, `canon-ignore`) as decisions rather than side effects of arriving.

One question that is Intent's and not ours: should a consumer be able to DETECT a frozen roster, rather than finding out by reading its own hook fifteen days later?

### The second thing, which the same upgrade fixes

**Issue 0029, filed OPEN, and its remaining half is not devbin's to fix.**

This morning I corrected `CLAUDE.md` for pinning Intent v2.18.0 while the tool was on v2.19.0. Tonight I found that correction sits at line 3 -- **inside the region regeneration overwrites** -- and Intent's current template still interpolates a version into that same prose. So the fix was not a fix, it was a delay: the next `intent claude upgrade` restores the copied fact, and nothing would have announced it. The file's one "Preserved across regeneration" marker is attached to the region that IS preserved and says nothing about the much larger region that is not, so the absence of a warning read as safety.

Devbin's half has landed: the correction now lives inside the preserved `user:start` block, where it survives. **Intent's half is a one-line template change in Intentv2 and affects every Intent project**, since each one regenerates the same copied fact. I have not touched it -- sweep #5 was authorised, this is not, and Intent runs its own sessions. Route it or rule it as you prefer; nothing degrades while it waits.

### State

Both threads closed, two issues open and neither of them work -- both are your call on when to run one upgrade. Fleet uniform and fully committed, all five check options green, suite green. cc paused since 2026-08-10. vc paused at the end of this fold.

Worth saying plainly: I opened this fold reporting "nothing open" and I am closing it with two. Neither is new breakage. Both are things that were already true and that nothing was ever going to report, which is the only kind of finding a fold is actually for.

## (2026-08-24 21:03Z)

Fourth sitting. You ruled option A on the sweep; it ran, and it is done.

### Sweep #5

**Eleven estates on `37ce21f`, one distinct `source_commit` across the fleet.** Doctor green before and after everywhere, seam clean in all eleven -- nothing under `cmd/`, `help/`, `config.yaml` or `config/` touched, so the estates' database work collided with nothing.

Enumerated from disk: **twenty-one** installs found, eleven swept, ten excluded and named (eight mix-managed `deps/arca_config` copies, two Lamplight worktrees). The count has now moved twice -- ten by roster, nineteen, twenty-one.

Per your terms, only clean trees were committed. **Intent and Laksa are HELD** -- vendored, functional, uncommitted, for their own sessions to land. Baize was held on the same rule and its own session committed it within the hour, which is the mechanism working. Conflab had already upgraded itself earlier in the evening.

Commits: arca_cli `e2c2460`, arca_config `4c9941b`, Baize `1b507b3`, Conflab `513f27ba`, Intentv2 `a52c9e3c`, Lamplight `9fb7d6104`, MicroGPTEx `de54cd2`, Prolix `d6555c8`, Riffle `eeefc52`.

### 0028 shipped before it

`generated_doc_write` in `lib/helpers`. Conflab's three proposed shapes all assumed the FLY CODE was the shared thing; it is not, and their own withdrawal message said so better than I did. Devbin owns the discipline, every project keeps its producer. Four corrections to their spec, one of which -- an unset `--deny-env` variable reporting a credential leak that never happened -- I drove red before writing the branch.

### The part worth your time: I was corrected three times tonight and each correction was right

**intent/dc refused to run a commit I handed them.** Not from doubt about the bytes -- because a peer handing over a ready-made command is not their user's approval. That is the rule I have applied to relayed instructions all evening, applied to me. I gave them the line as a convenience and it arrived as something they were obliged to refuse. Their five paths stay dirty until their user says otherwise.

**intent/dc also improved my fix.** I had "pre-announce a sweep". Theirs: the announcement must NAME THE HELD ESTATES, because a committed change explains itself in the log and a held one explains itself nowhere -- which is exactly the state that made them start hunting an intruder. Now the procedure.

**lamplight/vc caught me publishing wrong data.** I named Lamplight's `.out` readers by taking a COUNT from one grep and NAMES from an earlier, broader one that a silent `head -4` had truncated. Two of the four named files matched neither query. Both greps were correct; the splice was not -- and I did it inside the message warning them to name an instrument's scope before trusting its output.

**And they had a better instrument than mine.** I ranked Lamplight as most exposed on a count of five `.out` readers. They measured the shape that actually breaks and found it absent from their tree entirely. Five files that READ a path are not more exposed than two that PARSE it. Ranking withdrawn.

All four lessons are in `intent/llm/LESSONS.md` at `c6c30f9`, including the strongest one of the night, which is intent/dc's: **a defect that returns the correct answer on the case in front of you is unfindable by any result-checking.** Two sightings in one evening in different languages -- my torn config read, and their bash 3.2 subscript degenerating to index 0 while index 0 held the right value. No exit code carries either.

### Nothing needs deciding

Nothing in flight, nothing open, no claim held, vc paused. Suite green, all five check options green. Intent and Laksa may commit their held vendor whenever their sessions choose; nothing degrades if they never do.

## (2026-08-24 19:24Z)   NEEDS A RULING FROM YOU

lamplight/vc, hub of tonight's ST0357 geodica DB consolidation, routing an architecture question from conflab/vc. Four estates need one generator for the factual half of `config/.fly/database.md`. Conflab has a working ~90-line implementation as a project handler and offers it as the lift-ready starting point. They ask three shapes: (a) builtin, (b) project handler x4, (c) an opt-in module that does not exist today. **Interim ruling already in effect at their end -- estates hand-audit now rather than wait, so nothing is blocked on you.**

I verified their factual claims before passing this on. Both are correct: `config.reference.yaml` has exactly six top-level keys (`project`, `devbin_version`, `help`, `docs`, `options`, `commands`) with no free-form project-settings block, and `lib/cmd/db:16` does rule provider-encoding project-local in the words they quote.

**Two things I would put in front of you before you rule.**

**1. Shape (c) is closer to existing than they think, and that cuts both ways.** The catalogue already carries two INDEPENDENT columns: a `language` column whose value may be `any`, a language, or `opt-in` (D22), and a `command` column that is either a command line or `@builtin` when devbin ships the logic in `lib/cmd/`. `lib/resolve` tests `opt-in` for activation without reference to how the command resolves. So "devbin ships code that is inert until the project asks for it" is an EXPRESSIBLE cell, not a new subsystem -- and it is currently EMPTY: every opt-in row (`precommit`, `content`, `publish`, `macos`, `which`) carries `-`, meaning devbin ships the name and the project supplies what runs.

The cut in the other direction is this project's own rule: **an unused cell is an untested cell.** `opt-in` x `@builtin` has never once run. That is the exact shape of four base defects here -- a path that looks supported because the table can express it, on input it has never seen. If you rule for (c), the first work is proving the cell, not writing the generator.

**2. There is a fourth shape they did not list, and I think it is the right one.** The two design rules conflab identified as worth keeping -- **no credential in the generated file** (env indirection) and **refuse to write from failed measurements** (a doc built from failures looks freshly generated) -- are not fly-specific in any way. They are general rules about generated documentation, and they are the same class as this framework's determinate-zero doctrine: a generator that writes from nothing has produced a false green in prose.

So the concern splits along devbin's actual seam rather than along the provider boundary. **What is duplicated four times is the DISCIPLINE, not the fly commands.** devbin could own the generic half -- write between markers, never embed a credential, abort rather than write from an empty probe, leave the file untouched on failure -- while `fly --json` and `psql` stay project-local exactly as `lib/cmd/db:16` requires. Four estates then share the part that is actually common and devbin acquires no opinion about fly.io.

That also answers the config-shape objection: a marker-and-refusal contract needs far less project-configured state than a fly generator does, which matters because devbin genuinely has nowhere to put free-form project settings today.

**My recommendation: the fourth shape**, with (b) as the honest fallback if you would rather devbin acquire nothing here at all -- four copies of ninety lines is a real cost but a known one, and it is what the standing rule prescribes.

**Not mine to rule and I have not.** lamplight/vc has been told it is with you and given both findings so their estates are not idle. They relay fleet-wide once you decide.

## (2026-08-24 18:29Z)

Third sitting, after the line was drawn. Two things you asked for and one that arrived on its own.

### The line, and then the boards

Pen-and-eraser fold done: cc 41668 -> 2127 bytes, vc 8566 -> 2004, hv 308 -> 4291. hv's GREW deliberately -- it was an empty scaffold while every ruling you had made lived on whichever agent board was in the room at the time, so a ruling's home was an accident of timing. It now carries the standing directives and indexes `intent/wip.md` rather than restating it.

The ~90 watch-outs became `intent/llm/LESSONS.md`. Nothing was erased before it was promoted, and 68KB is archived byte-for-byte under `.history/20260824/`.

**Three things were live wrong and none of them were the job.** `README.md` said bash 3.2 is "a hard target" -- the front door contradicting its own reversal. `intent/llm/RULES-shell.md` said "NEVER use bash 4+ features" while `usage-rules.md` three files away requires bash >= 5. And `.claude/restart.md`, the file the SessionStart hook injects, named 0004, 0014 and 0015 as the open issues; all three were closed. **The document that opens every session was the least accurate in the repository**, and it is the one read first and questioned last.

### prolix/vc reported three findings, all fixed -- 0025 to 0027

**0026 is the severe one and it was not the one they reported.** Their report was about a confusing error message. Underneath it, `cfg_load` made ONE awk pass over config.yaml, so a file rewritten in place mid-parse yielded a torn value -- valid YAML, wrong contents, then word-split into a command line and executed. It now reads twice and refuses a disagreement.

0025: `run_gate` teed the tool's output and recorded nothing about what it invoked, so a gate dying on its own arguments sealed the tool's complaint and nothing that explained it. The invocation now goes into the `.out` scope half, one argument per line and indexed.

0027 is documentation: a seal is non-empty for the entire run by design, and the contract carried that on the single word "completed". Their reporter misread the marker as a failure three times in one day, the third time after having already worked out what it was.

### The part you should see, because it nearly went the other way

**0025's fix nearly introduced a worse defect than the one it closed.** Recording a command line puts arbitrary config text where the extraction grammars can see it, and two of the six print on UNANCHORED patterns, one of which also opens a block. Driven red with the guard removed, the sealed VERDICT filled with devbin's own output followed by the tool's ordinary lines dragged in behind it -- the wrong-seal defect MODULES.md names as the one this subsystem cannot detect afterwards.

The untagged version would have passed every test anyone would think to write: the collision needs a byte sequence nobody puts in a fixture. It was caught by asking what else the change could touch, not by a gate.

**Two of my own tests were wrong first.** The torn-read test staged its race with a counter; each read runs in a command substitution, the increment died with its subshell, and it passed against a guard that never fired.

### One thing for you, no urgency

**Intent has moved to v2.19.0 and `CLAUDE.md` said v2.18.0.** Found by running `intent agents sync`, which moved nothing but its own stamp. The prose no longer pins a version. Whether the project wants anything else from 2.19.0 is yours.

### Decisions you can reverse in one line each

- **I filed the three findings as issues and closed them immediately**, rather than letting the commit be the only record. The tracker's CLOSED dir is where `intent/wip.md` says "what broke, and how" lives, and cross-estate citation needs numbers. If you would rather a fixed-on-arrival finding not get a number, say so.
- **`cfg_load` now costs one extra awk pass on every invocation.** Size-and-mtime via `stat` was rejected as less portable and less sensitive. If the cost ever matters, the check is one branch.

### Status

Nothing in flight, nothing open, no claim held, vc paused. Suite green, all five check options green. prolix/vc has been answered directly and accepted the corrections; their `dbproxy` item was entirely theirs, but the same `fly proxy` algorithm sits in Laksa's and Lamplight's own handlers, which they have routed to the hub.

## (2026-08-25 07:40Z)

Overnight CI red: diagnosed, fixed, verified, UNCOMMITTED pending your go. **The part that needs you is the last section.**

### What was actually wrong

Run 32787816443 failed on macOS only, one test of 649, on a commit that changed a single whiteboard file. `doctor` reported a vendored file unowned on the line after certifying all 28 intact.

Not doctor's logic. `lib/cmd/doctor:196` was `printf '%s\n' "$states" | grep -q "<TAB>$rel$" && continue`, and under `set -euo pipefail` that is unsound: grep -q returns the instant it matches, printf takes SIGPIPE on a write that has not landed, and pipefail promotes the writer's 141 to the status of the pipeline. The `&&` does not fire and an owned file is called unowned. **The bug is on the MATCH path** -- the miss path reads to EOF and always worked, so the code is correct whenever it finds nothing and wrong when it finds something.

Filed as issue 0031, high. **Three real sites, not the four I first reported** -- `lib/cmd/doctor`, `lib/cmd/new`, `lib/cmd/check`, plus one in the CI workflow where a gate step's last command could go red on a race rather than on what it tests.

**The fourth was refuted, by devbin/cc, and I have reverted my fix for it.** I had attributed "a file is silently dropped from the lint set" to `head -n1 "$s" | grep -qE` in our CI collector. That cannot happen: `head -n1` writes exactly one line and grep is line-oriented, so grep cannot decide until it holds the complete line -- its decision point is at or after the writer's last byte and there is nothing left to strand. Driven both ways at equal size: ONE 200KB line lost 0/200, MANY lines totalling 216KB lost 200/200. And under load with a positive control that fired in the same run, `head -n1 | grep -qE` lost 0 of 6000 where `printf` lost 1.

So the rule is not "a reader that exits early" but **"the reader can decide before consuming everything the writer will write"**. Those coincide in three of the four sites and come apart in exactly the fourth. cc found it by going looking for a fifth site I had missed -- `cmd/.lib/shell-gate:58`, the same shape, wired as three live gates here. It is sound, and as my table stood the next person would have "fixed" three working gates for no defect. Both are now recorded as visited-and-excluded rather than left in a silence indistinguishable from not having looked.

### Evidence, and the part of it I got wrong first

Regression test driven RED against the unfixed doctor, where it reported every vendored file as unowned; green after. Suite 650/650, `check all` exit 0, shellcheck clean.

My first analysis said the race needed a payload over the pipe buffer, which would have made it need ~3900 stamps and read as theoretical. **That was wrong, and the CI output already refuted it**: one file of 27 was flagged where blocking would have flagged all 27. There are two loss modes -- buffer-blocking, and scheduling, where the forked subshell is preempted between fork() and write() at ANY size. Measured the second at the 839 bytes devbin actually had: 1 in 6000 under load. **Payload size bounds neither.** I nearly filed a real defect as theoretical by measuring the mode that was easy to measure.

**Then I got the first mode wrong too, and intent/vc caught it.** I reported a "sharp cliff at 64K". Holding bytes constant at 60000 and varying only line width, loss runs 7/20 at width 6 and 0/20 at width 60 -- same bytes, different answer. Their onset was 40-60K where mine was 64.6K, and the disagreement was METHOD, not machine. There is no portable threshold, so "we are under the limit" is not a defence for a second, independent reason.

**And I sent them a repro I had not run.** Narrowed the line from 17 bytes to 6 while writing it up, never re-executed it; it produced 22892 bytes, returned lost=0/20, and read to them as a refutation of the finding it was sent to support. They drove it instead of relaying it, which is the only reason it was caught. My own board carries "the predicate is part of the result" and I broke it in the act of handing over a predicate.

Also caught in my own patch before it landed: `read -r x <"$f" || x=""` clears the variable for a file whose last line has no trailing newline, because read returns 1 *after* assigning. That would have dropped a valid `#!/bin/bash` from the lint set -- the same silent exclusion I was fixing, reintroduced by the fix. No test would have gone red on it.

### THE THING THAT NEEDS YOU

**The two guards 0030 is about both carry this defect.** `whiteboard-clock-guard.sh:246` and `whiteboard-header-guard.sh:201`, both `set -uo pipefail`, both using that exact pipeline as the "did THIS COMMIT add it" filter. A lost race makes the guard call a real violation inherited breakage and **pass the commit**. Byte-identical in Intentv2@a52c9e3c and Intent@67fc269a, so it is both-trees and shipped-surface.

Sent to intent/vc with their disposition fields, and to devbin/cc because it is about to arm these. I have touched neither Intent tree. **The v2 landing call and the routing are yours.**

Two things I would want you to hold when cc arms them:
- **"Armed" is not "sound."** The stripped-Z red-drive exercises check B, which is syntactic and has no pipeline -- it will go red and say nothing about :246.
- **`canon-ignore-guard.sh:133` is the same idiom for the same job**, safe only because that file sets `set -u` rather than `set -uo pipefail`. Anyone tidying that line arms the bug, and it would read as a tightening.

### Two smaller ones

cc's finding that `.claude/settings.json` names absolute paths into `~/Devel/prj/Intent` rather than INTENT_HOME (`~/Devel/prj/Intentv2`) compounds with 0030: it is a second way for the guard you think is running to be a different file from the guard that runs. Theirs, surfaced rather than re-derived.

intent/vc gave me v2 at `e5a8f158`; I read `a52c9e3c`, which is devbin's own sweep #5 commit. Their reading looks stale. Told them.

### Devbin's own exposure, measured -- the number for cc's arming trade

intent/vc split my one finding into two severities by measuring what I had not: the two guards' payloads differ by three orders of magnitude (clock guard sees deduped ~18-byte stamps, header guard sees every added line in full). Their estate's header-guard payload has reached 36.8K. So the header guard is the exposed one and the clock guard is effectively mode-2-only.

Devbin's, measured across all of its board history: worst real payload **13374 bytes, 70 lines, mean width 191**; driven verbatim at that exact shape, **lost=0/200**; the same payload at 5x, **lost=197/200**. So devbin has roughly 5x headroom and is exposed to the rare mode only.

**Arming remains net-positive and I am not arguing against it** -- an unsound guard beats the nothing we have. It should be a known trade rather than a surprise.

### State

0031 deliberately left OPEN. It closes on a green CI run, not on my local green -- this defect is environment-dependent and local green is weaker evidence than usual here. Nothing committed; awaiting your go on commit and push.

## (2026-08-25 09:17Z)

Localfold. **Both issues closed, both CI green, and the guards are armed.** Nothing needs you.

### What landed

| commit    | issue | CI    |
| --------- | ----- | ----- |
| `0bf263e` | 0031  | green |
| `57ecd5b` | 0032  | green |

**Two consecutive green macOS runs**, which matters more than usual here: 0031 was a race, and I said one green would not settle it. It is the repeat, not the first pass, that is the evidence.

**0031** -- `printf | grep -q` under `pipefail` promoting a SIGPIPE 141, so `doctor` called an OWNED file unowned. Three real sites. **A fourth was refuted by devbin/cc and reverted**: `head -n1 | grep -qE` cannot fail, because head writes one line and grep is line-oriented, so its decision point is at or after the writer's last byte. I had fixed a non-defect and written a false explanation above it.

**0032** -- `docs treeindex` removed in full on your instruction. Ten files, two tests ADDED so the removal is asserted. `AGENTS.md:75` still names treeindex and I left it deliberately: it is a verbatim copy of the in-essentials skill's `description:` field, so it is fixed upstream and not before.

### The thing worth your attention

**cc armed the guards mid-session, and `57ecd5b` is the first commit in this repository's history the whiteboard guards have ever checked** -- `guards: 3 ran, 1 skipped`. That is 0030's exposure closed for commits from here on, and it says nothing about anything committed before it.

**But armed is not pinned.** Guard BODIES resolve live from `$INTENT_HOME`; only the ROSTER is pinned in this repo's hook. So "which guard ran on my commit" has a time-dependent answer that nothing here records -- and the bodies changed under this node TWICE inside one hour (intent/dc's fix, then cc's marker repair), each live to every consumer and recorded nowhere. I found the first by three of five guard hashes disagreeing with values I had measured an hour earlier. It is with intent/vc as a property rather than as either instance, and it is a candidate issue I will raise once 0030 closes rather than open a third thread now.

### Three corrections against myself

A repro published without being run; a "sharp cliff at 64K" true at one line width and false as a statement; and the refuted row. Each caught by a peer driving rather than relaying, none by me. All three are in `LESSONS.md` and in 0031's own record rather than quietly absent -- including that I wrote the `cmd | head` lesson and then violated it twice more the same day, which is recorded as evidence that writing a lesson does not install it.

### State

vc paused. Nothing in flight, no claim held. `vc/inbox.cc.md` holds one handled FYI entry that I have NOT cleared, because cc has it staged mid-flight and clearing under a peer's staged change is the sweep-#5 hazard in miniature -- next fold. cc's own work (`.claude/**`, `CLAUDE.md`, `.intent_critic.yml`, its two board files) is untouched and still staged; I committed by explicit pathspec and verified after.

The next thread is yours to set.

## (2026-08-25 10:07Z)   FYI only -- no response needed.

FLEET SWEEP #6 STARTING -- devbin runtime 37ce21f5 -> f21d097 across ELEVEN vendored installs, on hv's explicit go this morning.

Estates: Baize, Conflab, Intent, Intentv2, Laksa, Lamplight, MicroGPTEx, Prolix, Riffle, Arca/arca_cli, Arca/arca_config. Devbin itself self-hosts and is not in the sweep.

HELD ESTATES, NAMED because a committed change explains itself in the log and a held one explains itself nowhere: **Intent** (14 dirty, live session mid-treeindex-removal -- 861fa66c is in that tree) and **Laksa** (5 dirty, whiteboard inboxes only). Neither dirty set touches bin/.devbin, so there is no collision, but both take my bytes into a tree someone is working in. hv ruled include-both.

Payload is 8 files, two commits: 0bf263e (0031, pipefail/SIGPIPE -- cmd/check, cmd/doctor, cmd/new, pure bug fix) and 57ecd5b (0032, treeindex removal -- bin/devbin, builtins, cmd/docs, config, config.reference.yaml, an INTERFACE REMOVAL).

Survey before writing: all 11 at 37ce21f5, 0 files locally edited, 0 missing, source recorded correctly in every manifest. upgrade will refuse nothing.

0032 IS NOT A DROP-IN FOR THREE OF THE ELEVEN. Laksa, MicroGPTEx and Arca/arca_config have no project cmd/docs, so they use the builtin, and all three declare docs.treeindex_dirs in their own config.yaml -- which upgrade never touches. Proven rather than asserted: I ran the NEW lib/config's cfg_validate against each estate's existing config; 8 clean at rc=0, those three at rc=1 naming docs.treeindex_dirs.N exactly. Blast radius is contained -- cfg_validate has exactly one caller, lib/cmd/doctor:111 -- so it is a doctor finding, not a runtime break. hv ruled: fix those three in the same sweep (config key removed, help/docs.md corrected at Laksa and MicroGPTEx).

One silent change worth naming: in those three, `docs all` stops running treeindex with no error.

Correction to my own instrument, since it is the kind this board keeps: my first estate count was TEN. The predicate globbed at depth 1 and missed Arca/arca_cli and Arca/arca_config. hv's board said eleven; the corrected predicate reconciles. A sweep that silently skips two estates is the failure, not the count.

And a naming trap for anyone reading these trees: **Intent is the v3 tree, Intentv2 is the frozen v2 tree that is INTENT_HOME.** Inverted from the obvious reading. intent treeindex is STILL LIVE on PATH today (v2.19.0 lists it); the retirement is executed only in Intent at 861fa66c. So this sweep removes a command that currently works, knowingly.

## (2026-08-25 10:26Z)   FYI only -- no response needed.

SWEEP #6 COMPLETE, BOTH HALVES. Eleven estates, all green, all committed.

HALF ONE -- runtime 37ce21f5 -> 6ee2f845. 8 files, 0 refused, 0 edited-in-place, every manifest re-stamped and clean (no +dirty: cc committed its board between my check and the write, which is the only reason the provenance line is clean rather than "THESE BYTES MATCH NO COMMIT"). Carries devbin#0031 (pipefail/SIGPIPE) and devbin#0032 (docs treeindex removed). Three estates -- Laksa, MicroGPTEx, Arca/arca_config -- needed their own config.yaml and help fixed in the same sweep, per hv, because they used the builtin AND declared docs.treeindex_dirs, which upgrade never touches.

HALF TWO, on hv's escalation mid-sweep: FIX THEM ALL AND MAKE IT CONSISTENT. The finding that provoked it is worth stating plainly, because it is the failure mode of the whole tool. devbin exists to normalise dev-x, and `docs` was where that had silently stopped being true: eight estates on the builtin, THREE carrying full shadows that reimplemented the entire command.

The shadows were not customisation, they were drift, and every copy was WORSE than the builtin it replaced:
- Baize's `agents` never printed the "AGENTS.md is generated" warning every other estate prints.
- Conflab's rolled its own dim printf instead of `warn`.
- Both predated the exit-status capture devbin#0016 added to the builtin, so both could return 0 over a failed sync.
- Lamplight's offered NO `agents` at all. Its shadow header asserted "this project has no intent agents surface under docs, and never did" -- and the generated AGENTS.md in its project root said otherwise. That estate's AGENTS.md could not be regenerated by its own tooling, and was stale.

What genuinely differed between these projects was one or two verbs each, and the catalogue could ALREADY express that: MicroGPTEx and Arca/arca_config had been declaring `publish` and `exdoc` as additive `options:` rows beside the builtin the whole time the shadows existed. The working pattern was in the fleet, in use, unadopted. All three shadows are gone; project verbs are rows; `agents` is one implementation for all eleven.

Result, measured not asserted: zero `cmd/docs` shadows fleet-wide, `doctor` rc=0 in all eleven, `agents` and `all` offered everywhere, and no `intent treeindex` CALL anywhere in any estate's bin/ -- only prose recording the removal.

AGENTS.md regenerated in all eleven: every one was still advertising `intent treeindex`. Riffle also gained a gitignore line the other ten already had, for the .bak that `intent agents sync` writes.

FOUR INSTRUMENT FAILURES OF MY OWN, all caught, none by an exit status:
1. First estate count was TEN. The predicate globbed at depth 1 and missed Arca/arca_cli and Arca/arca_config. hv's board said eleven, which is the only reason I looked again.
2. The announce heredoc was UNQUOTED, so a backticked `docs all` was command-substituted out of the message before I noticed -- the same class as the backtick that once ran intent treeindex.
3. I designed the Conflab fix as cmd/docs.d/completions. `devbin doctor` REFUSED it: a `.d/` directory is sub-handlers OF A SHADOW and needs an executable cmd/docs beside it. The tool caught my design error, which is the best outcome available and worth saying out loud.
4. My survey reported Intent dirty:9 when it was 13. The tree was moving under me -- intent-vc committed and started new work between two reads. A dirty count is a reading, not a fact.

AND ONE RACE THAT WAS NOT MINE: my commit in Intent failed rc=128, `cannot lock ref HEAD`. All four guards had passed; intent-vc committed my vendored bytes themselves as 7e45ff5c while my commit was mid-flight. Content landed, commit did not. Their message attributes the work to devbin-cc; 0031 and 0032 were devbin-vc's. Minor, and theirs to correct if they care.

A NAMING TRAP anyone reading these trees needs: Intent is the v3 tree, Intentv2 is the frozen v2 tree that is INTENT_HOME. Inverted from the obvious reading, and it decides which answer you get about treeindex -- still live on PATH under v2.19.0, retired only in Intent at 861fa66c.

## (2026-08-25 11:23Z)   FYI only -- no response needed.

A DEPENDENCY SWEEP #6 ACQUIRED AND DOES NOT RECORD -- surfacing per the hv-inbox obligation, and it is live.

The eleven AGENTS.md files I committed an hour ago are downstream of ONE MACHINE-GLOBAL MUTABLE FILE that no estate references and nothing pins:

  ~/.claude/skills/in-essentials/SKILL.md

`intent agents sync` derives the skill roster from that directory, so all eleven commits carry its CURRENT contents verbatim. Measured just now:

  ~/.claude/skills/in-essentials/SKILL.md   4017 bytes,  0 treeindex   <- what my commits captured
  Intent (v3) source                        4017 bytes,  0 treeindex   <- identical
  Intentv2 (v2) source                      5027 bytes, 13 treeindex   <- the other candidate

THE TARGET IS SHARED AND THE SOURCE IS PER-ESTATE. `intent claude skills sync --force` run from a v2 estate -- and devbin's own INTENT_HOME *is* Intentv2 -- pulls the 5027-byte file over the machine-global copy. That does not merely regress the skill. The NEXT `agents sync` in any estate then writes `treeindex` back into that estate's AGENTS.md as a committed file, silently reversing the sweep in a document whose entire contract is that it is generated and therefore never read critically. Eleven repositories, no error, no exit status.

Found by intent-vc, who had earlier recommended exactly that --force to devbin-cc and to me, then measured it and retracted. I never ran skills sync in any form, so there is no exposure from my side and nothing to undo. I am surfacing the RESIDUAL RISK, not an incident.

AND IT ALREADY HAPPENED ONCE INSIDE MY OWN SESSION, INVISIBLY. My /in-session bootstrap this morning loaded in-essentials WITH the treeindex rules -- I read rules 3 and 4 in the skill body and flagged them as stale on this board. By the time I ran the regeneration, the installed file was the 4017-byte version with none. intent-vc's force-sync landed between my bootstrap and my sweep. One session, one document, two versions, and nothing in either read said which one I had.

THIS IS "ARMED IS NOT PINNED" IN A SECOND PLACE. I wrote that watch-out about guard BODIES resolving live from $INTENT_HOME while only the roster is pinned in each consumer. Skills are the same shape -- a live-resolved shared body under a per-estate source -- and I had not counted them. The version of a document you loaded is not a property you can recover from the document afterwards. I would expect a third instance to exist.

hv's to time, not mine to fix, and it is not devbin's code: the fix is upstream in the Intent skills machinery (whether a per-estate target, a source-version guard on --force, or a refusal to sync a v3-retired rule from a v2 source). intent-vc has the measurement; devbin-cc holds the separate source_commit_of finding from earlier today. Neither has been filed -- both are waiting on you.

## (2026-08-25 12:42Z)   FYI only -- no response needed.

CLOSURE PASS COMPLETE, on hv's explicit go: docs to as-built, everything committed, pushing next.

TESTS, RUN THREE TIMES TODAY AND PRISTINE EACH TIME: 653 ok, 0 not ok, rc=0. The single `# skip` is `require_command skips rather than fails when a tool is absent` -- a test whose SUBJECT is skip behaviour, so it is a pass and not a gap. Stating the discriminator because "pristine" and "green" are not the same claim, and a skip count is exactly where they part.

DOCS TO AS-BUILT. `intent/wip.md` rewritten (it listed 0029 and 0030 as open when both had closed, pinned the fleet at 37ce21f, and described sweep #5 as the most recent); both restart briefs updated; LESSONS and usage-rules gained this session's material. **No sha is pinned in any of the three now** -- two documents have already carried a stale one, so the manifest is the authority. Same no-tallies rule those files already applied to the issue set, extended to the last fact they were still copying.

THE ONE SUBSTANTIVE DOC CHANGE, and it is a correction rather than an addition. `restart.md` said a project handler displacing a built-in option set is "the design working, not a fault". The MECHANISM is; sweep #6 showed the conclusion does not follow. A shadow is design only when the catalogue CANNOT express the difference, and `doctor` reports both cases identically as SUPPORTED OVERRIDE. That constraint had been read as a clearance.

RE-SWEEP. cc's 0033 fix moved lib/install AFTER sweep #6 landed, so all eleven estates were carrying a source_commit nothing would later match -- the record the next sweep reads. Re-vendored all eleven onto 0257f7a: 1 file updated each, 0 refused, and every manifest now carries a BARE SHA with no +dirty, which is the fix visible in the field. doctor rc=0 and vendor rc=0 in all eleven; both baselines checked, because a re-vendor rewrites files and manifest together and doctor cannot see divergence vendor can.

SCOPE I DID NOT TAKE, stated rather than left implied: I ran devbin's suite, not the estates'. Eleven downstream suites is not what "run all tests" asked for here, and hv's standing directive makes Lamplight's full mix leg hv-run and never agent-run. The estates were verified through doctor + vendor, which is the right check for a vendoring change and the wrong one to call a test run.

hv has bumped the CI budget. Pushing devbin to both remotes and all eleven estates next, then watching the run. The Test Summary gate now echoes its three `needs.*.result` values before it decides -- run 32831220146 failed there with all three real jobs green and the cause is unrecoverable, because the step printed nothing and the logs have since expired. If it recurs the next run names the input; if it does not, that is on the record too.

## (2026-08-25 16:28Z)   FYI only -- no response needed.

DAY CLOSED, DEVBIN PAUSED. Localfold and globalfold both done, everything committed and pushed, and the pause written as a state rather than left as an absence.

THE SUITE hv RAN INDEPENDENTLY: 656 ok, 0 not ok, seal 0 bytes. Confirmed here after the fold edits, same numbers. **The seal gave the verdict and the SCOPE had to be read out of the .out log by hand** -- which is issue 0034 demonstrating itself on the run used to close the day.

WHAT CLOSED TODAY: five issues (0029, 0030, 0033 by cc; 0031, 0032 by vc), fleet sweep #6 in two halves, two re-sweeps, the `devbin --version` fix hv reported from Conflab, the docs to as-built, and the CI Test Summary gate hardened. Twelve repos level across 27 remote refs. CI green twice.

WHAT PAUSES OPEN, and the reason it is stated rather than filed and forgotten:

**Issue 0034 -- a seal records the result and not the scope.** Reported by vc at LAMPLIGHT: a consumer estate reporting inward, the same route that gave us 0025 to 0027 from Prolix. Medium. It is in this project's cardinal class -- a gate stating a verdict without its reach is the false-green shape -- and it is now the only open item against devbin's own code. Pausing over it is defensible and is hv's call; it should not be a thing that happened quietly, which is why it is the first line of `intent/wip.md` and of both restart briefs.

**`--ivault` -- explicit DO NOT START, honoured.** No thread, no design, no spike. Trigger is stage 0 of Intent's ST0060 plus AC-00.19, upstream and not this node's to watch for. Two constraints recorded on the vc board so they survive whoever opens it: devbin must NEVER parse an `intent://` reference (literal prefix test only -- it can over-trigger, never under-trigger, at a cost of one process), and `intent/st/ST0060/` will VANISH from disk when hv de-realises it, which is not a deletion -- `intent3 st hydrate ST0060` restores it.

THREE THINGS hv SHOULD KNOW BEFORE TOMORROW:

1. **The eleven committed AGENTS.md files depend on one machine-global mutable file** -- `~/.claude/skills/in-essentials/SKILL.md`. A `--force` skills sync from a v2 estate, and devbin's own INTENT_HOME *is* Intentv2, writes `treeindex` back into all eleven on the next `agents sync`, with no error and no exit status. Found and retracted by intent/vc. The fix is upstream in Intent's skills machinery, not here.

2. **cc's board is dirty and cc has folded.** `intent/whiteboard/cc/wip.md` is modified-uncommitted. Untouched by me -- single-writer, it is theirs -- but it means the day closes with one node's board outstanding. Named rather than left to look like an oversight at tomorrow's pickup. cc's 0034 record was also unpushed and has been pushed.

3. **The morning CI red is hardened, NOT diagnosed.** All three real jobs were green and only the 3-second Test Summary aggregation failed; single attempt, `needs` keys correct, logs expired before anyone asked. No mechanism is claimed. The gate now echoes its three inputs before deciding, confirmed firing. It has not recurred, and that is the whole of what was learned.

INSTRUMENT FAILURES TODAY: seven, none caught by an exit status, every one caught by a peer or a re-read. The new sub-class is on the vc board: three of them were the TOOL erroring rather than answering, and each produced a COMPLETE-LOOKING table of wrong answers -- a partial table invites suspicion and a full one of zeros does not.
