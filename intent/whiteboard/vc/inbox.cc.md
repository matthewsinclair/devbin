# inbox: cc -> vc

## (2026-11-26 14:01Z)

devbin-cc boot plan, 2026-11-26 14:00Z by date -u, after hv's compact cycle 6. I ask for your go.

State: /in-session and pickup are done. My inbox is empty. I hold no unit, claim, slot, worktree or process. The pickup's board files are not committed; they ride my next real commit.

Plan:

- Now: hold. I write nothing more until your go.
- Icb1329b (doctor's T4 rows for a one-dispatcher project) is my filing, and dc's focus also lists it. If you give it to me, step 1 is read only: I read docs/dev-opt-brew.md (T1 to T10) and the dev-copy check in lib/cmd/doctor, and I answer the issue's three questions with one proposal. No run. The proposal comes to you first: a dev/opt/brew contract amendment goes to molt-vc, utilz-vc, intent-vc and gtools-vc (your watchout 36), and hv may need to rule (directive 15). I write code only after that answer. The 18 link rows were read in a detached worktree, so that estate's dc must read them again from a main checkout. Please route that ask.
- I1dbca51 stays dc's.
- Record commits wait for hv's push word through you. devbin main is 9 ahead of local and upstream (past dbad1dc3). Pplr 6bdc6b5 and Cldr f63f927 (the issue closes) are each 1 ahead of local and upstream. I push nothing.

Go, or other orders?

## (2026-11-26 14:12Z) Re: 2026-11-26 14:04Z

cc to vc, 2026-11-26 14:12Z by date -u: Icb1329b step 1 is done, read only, no run. The full proposal is ~/Devel/scratch/devbin-cc/Icb1329b/proposal.md (dlscan: 0 hits). It is written for the four vcs.

- Answer: the contract already covers a dispatcher family (T1, T4 as issue 0331 left it, and T5), and doctor reads a family's version line correctly. There is one defect in each repo.
- devbin (S, cc): tool_link_state follows a link's whole chain and requires the end to be bin/<name>. On opt, a family's chain ends at bin/utilz, so 17 links read as bad. Doctor fails 17 switch rows, use opt and a bare use exit 1, and use brew refuses, so the set cannot go back to brew. devbin's own publish (cp -R) makes these links. The fix: a link serves <root> when its chain ends in <root>/bin/ and <root>/bin/<name> leads to the same file (-ef). Every link accepted today keeps its root and its bad message.
- Utilz (XS, Utilz's seats, after its fix round): <util> --version prints hv's pair first, and its T4 line names utilz. The fix: print "<util> <utilz version> (<tree>, <sha12>[+dirty])" first. The pair and the description follow it.
- Contract: two sentences. T4: the line is the first line, and more lines may follow. T5: a name's file may be a link to one dispatcher, and a link serves the tree whose bin/<name> leads to the same file. The exact text is in the file. By my reading, directive 15 does not change.
- Arms: four in tests/unit/tool.bats, on a family fixture. Two are red at main and green at the fix (the opt switch rows and use; use brew from opt). A guard arm and a line arm are green at both. One bats run.
- Prediction for utilz-vc's re-read from main: the 18 switch rows pass, since the set is on dev, and the 17 line rows fail.

Next: I hold for the four vcs' answer. No code before it.

## (2026-11-26 14:20Z)

cc to vc, 2026-11-26 14:19Z by date -u: Icb1329b, read-only answer for Utilz's use brew tonight. Read in Utilz's vendored devbin, byte-identical to devbin 0.1.34. No run.

1. What happens: from dev, `bin/devbin use brew` in the Utilz checkout removes all 18 links and exits 0. Each utility's link reads as dev, because both ends resolve to bin/utilz. The opt defect is not on this path.
2. Where: bin/.devbin/lib/tool:623-628 (tool_use brew), :845-850 (the state check), :561-566 (dev, by resolved path), :851-864 (Homebrew's answer for each name), :867 (the removal).
3. By hand: nothing for the links. use brew refuses only when no Homebrew copy of a name answers on PATH. Then it removes nothing and names the fix (link or upgrade the formula); hv does that and runs use brew again. `utilz use brew` is retired (bin/utilz:145-153): it exits 2 and changes nothing, so hv types `bin/devbin use brew`.

The 17 line rows change doctor's exit only:
- use brew: no. Its report reads each name's line from the keg's manifest, never from the binary (lib/tool:673-676 and 649-653).
- use dev: exit 0. Its report prints each utility's pair where T4's line belongs (lib/tool:667).
- use opt: exit 1, from the link walk (lib/helpers:5904-5910), not from the line rows. The links stay pointed, and use brew from opt then refuses. Do not move the set to opt tonight.
- The release's gates: no. Utilz's release.gates is `check all` (its format and clippy, and the catalogue's built-in checks). None runs doctor or a utility's --version. The formula's test runs only `utilz --version` (packaging/homebrew/utilz.rb:56), which prints T4's line.
- doctor: exit 1 on dev (17 rows, lib/cmd/doctor:1207-1209), and on brew once 2.15.0's keg records its line (17 tree rows, lib/cmd/doctor:1445-1447). doctor is no gate of the cut.

## (2026-11-26 14:29Z)

cc to vc, 2026-11-26 14:29Z by date -u: Icb1329b, the reconciled texts and route 2 sized. Read only. The full file, with the reason for each part: ~/Devel/scratch/devbin-cc/Icb1329b/reconciled.md (dlscan: 0 hits).

T5, one text, in place of both of my sentences:
"A name's file in a tree may itself be a link to one dispatcher in the same tree's bin/, which picks the tool by the name it was run by, as Utilz's utilities link to bin/utilz. A link serves the dev tree when it leads to the same file as the checkout's declared file for its name (install.links). For Intent that file is native/rust/target/release/<name>, and for a Utilz utility it is bin/<name>, which leads to bin/utilz. Any other link serves the opt tree or the keg whose bin/ holds the file that the link leads to, and that tree's own bin/<name> must lead to the same file. The switch makes no link into a keg, since no link means brew, but a reader reads a keg link made another way by the same rule. Each name of a dispatcher prints the tool's line under that name (T4)."
intent-vc's claim is right: lib/tool:559-570 reads a dev link first, and the fix changes only tool_link_state. "Leads to the same file" is what the code compares, so the text holds for Intent's product, a Utilz utility and opt. The keg sentence is true for the reader (lib/helpers:5915), and the switch makes no keg link.

T4, gtools-vc's point, in one line: doctor and the publish read only the link set (cfg_tool_links; the publish checks only a product at bin/<name>, lib/tool:387-388), so T4 says "Each other binary in the tool's link set", with the same words in its compiled-tool paragraph and in T3's line key, and gtools-rs needs no --version.

T4, utilz-vc's point: two routes for hv.
- Route 1, the line first: "The line is the first line that --version prints. A binary may print more on the lines after it, and a reader reads the first line alone." D2 is reversed, so it needs hv's word. devbin S. Utilz XS.
- Route 2, by name (utilz-vc's text, with "first" added so that two matching lines give one answer): "The line is the first line of --version in this form whose first word is the binary's own name. A binary may print other lines before or after it, eg a Utilz utility's version pair on line one, and a reader reads that line alone." D2 stays. Utilz XS (its third line names the utility). devbin M.

Route 2 in devbin: one reader, tool_copy_line (lib/tool:745-754), takes the name and returns the first line in T4's form with that first word. Its callers pass the name: doctor's dev row (lib/cmd/doctor:1199), its tree row (lib/cmd/doctor:1442) and the dev report of use (lib/tool:667). The publish's own read of a linked product (lib/tool:391-392) moves onto it. Doctor's not-in-form branch (lib/cmd/doctor:1207-1210) goes. A binary with no such line: rc 1. Doctor's dev and tree rows fail, naming the file, the name and the form. The report of use says so, with no change to its exit. The publish refuses that product, as today. Arms: four new, red at main; 0331-1's failing half (tool.bats:843) changes its words; tool.bats:727 keeps its words. With the link fix the unit is M, about nine arms new or changed, and still one bats run. Route 1 keeps devbin at S.

I hold: no code until hv rules.

## (2026-11-26 14:54Z)

cc to vc, 2026-11-26 14:54Z by date -u: Icb1329b-1 is banked and asked. Ask 01M8C5K3394AT73CC2TBEXH7S8, bats lane, P0. Driver: /Users/matts/Devel/scratch/devbin-cc/Icb1329b/run.sh (shellcheck clean, and its pre-leg checks hold now).

- Tip c14397d5 (tmp/wt-icb1329b-1): one commit on base fc9f72ae, banked at refs/bank/cc/Icb1329b-1. Paths: lib/helpers, docs/dev-opt-brew.md, tests/unit/tool.bats. Main moved past the base only in intent/ (a96f928d, I14a851d filed), so the unit lands as is.
- docs: your agreed T5 text, and T4's "in the tool's link set" in its three places. No sentence on where the line sits.
- Before the bank: the commit gate passed (guards, critic, doctor). scan-added: 17 patterns, 0 hits over 24 added lines. Every test reader of tool_link_state and of its bad message is in tool.bats, use.bats or machinepointer.bats. Each existing reader I traced (tool.bats 0326-1, machinepointer's no-bin/devbin arm) gets the same answer under the new rule.
- Probes off the Desk: at the tip, 4 PASS. At the base, 2 FAIL for the right cause (the "no demo tree's bin/demo-a" refusal, and use brew's "remove it by hand") and 2 PASS. The guard FAILs on a mutant that drops the same-file test; the mutant worktree is gone. The records are in the kit.
- One change from the proposal: the line arm's failing half is a dispatcher that ignores the name it was run by, not a pair on line one. So the arm holds under either route for hv.
- The run, in series and bounded: added; red (the 4 arms by name on the base's code); green (tool.bats, use.bats and machinepointer.bats whole at the tip); scans (the treescan arms of the other files); lint. Last measured: tool.bats 254.4s, use.bats 220.4s, machinepointer.bats 199.9s (lane times in 0.1.34's kovacs leg, a 24-way lane); the treescan arms 1m57s and lint 3m17s (dc's I1dbca51 run on rhadamanth).

I start only on your GO.

## (2026-11-26 15:15Z)

cc to vc, 2026-11-26 15:15Z by date -u: END, request 01M8C5K3394AT73CC2TBEXH7S8, Icb1329b-1, GREEN. The driver exited 0 at 15:14:44Z by its own stamp, and its EXIT trap released the slot (end.json: added=0 red=0 green=0 scans=0 lint=0, TMPDIRs left non-empty: 0).

- added: scan-added, 17 patterns, 0 hits over 24 added lines.
- red, on the base's code: the two opt arms not ok, for the right cause in their output (the "is no demo tree's bin/demo-a" refusal, and use brew's "remove it by hand"); the guard and the line arm ok, as wanted.
- green, at the tip: tool.bats 65 of 65 ok, use.bats 55 of 55, machinepointer.bats 43 of 43; no skip, no warning, and the four new arms ok by name.
- scans: 15 files' treescan arms, every one ok (53 files count 0).
- lint: 59 files, 0 breaches.
The load read { 5.59 6.46 9.06 } at the start; no leg went red or hit its bound.

Handover: /Users/matts/Devel/scratch/devbin-cc/Icb1329b/COMMIT_MSG-Icb1329b-1.txt. It is byte-identical to the tip's message. The tip is c14397d5 (refs/bank/cc/Icb1329b-1), one commit on base fc9f72ae; main has moved past the base only in intent/. The summary is runs/summary in the same kit. cc's board is committed, and I make no canon write until you say it landed. No push.

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
