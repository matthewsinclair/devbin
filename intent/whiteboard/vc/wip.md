---
node: vc
name: Validation Claude
role: validation
session_id: d252d54e-7ad5-4f31-9c5f-02ab8aca3f33
heartbeat_at: 2026-11-14 08:26Z
status: active
focus: "LOCALFOLDED 2026-11-14 08:24Z by date -u for hv's compact: desk held by devbin-vc (decision 176, Webber alone on rhadamanth and gyges); Webber's bundling rerun cc7808b9 running on gyges, rhadamanth's desk empty. On the bounce: /in-session, pickup, re-arm the desk waiter, then the plan (todo 213)."
claims: []
---

# Validation Claude (vc)

## DOING

_(none)_

## TODO

- Bank refs in canon: checked 2026-11-14 by changed lines (~/Devel/scratch/devbin-vc/bankrefs/check.out): 20 hold landed work (issues closed, or ST0011's WP02, WP07 and WP08 done; the five ST0011 refs predate the 2026-11-02 repo switch, so they share no merge-base with main); cc's 3 refs for 0326 are kept while 0326 is open. On hv's word, run ~/Devel/scratch/devbin-vc/bankrefs/clear.sh (update-ref -d with each recorded old value). (edited)
- HV'S LIST (as of 2026-11-14 09:04Z by date -u): (c) hv files the GitHub Support purge from vc's draft, ~/Devel/scratch/devbin-vc/0.1.24/github-support-purge.txt; (e) no-vendor (decision 64) and --ivault (hold 2) parked until hv schedules them; (g) kovacs's GNOME re-login (kovacs-sysadm offline) and the router's DHCP reservation, hv's to check; (j) the bank-ref clear on todo 200. Done since: intentd enrolled at login (com.matthewsinclair.intentd, pid 71443 carrying CLAUDE_CONFIG_DIR, every session listed by estate status at 09:04Z), (a), (b), (d), (f), (h), (i), the Intranet repo and the snapshot (decisions 177 to 179). (edited)
- RELEASE AFTER NEXT, weigh only: a release.gates entry starting with release recurses (archived todo 203); macos and release call built-ins through the launcher (206); no macOS-stage rehearsal before a cut (207); a failed remote leg keeps its worktree on the host (208); dc's todo 67 TMPDIR leftovers; issues 0352, 0354, 0355 (gates blame a peer's tree write on a gate, from molt#0100) and 0356 (--help after a gate option runs the work). (edited)
- NOTICES at each estate's next vc session: sweep notices for 0.1.19, 0.1.20 and 0.1.23 (archived todos 194, 198, 210; shas in ~/Devel/scratch/devbin-vc/0.1.23/aftertag/sweep-commit.summary), and 0.1.24 (swept 2026-11-14 08:47Z, shas in ~/Devel/scratch/devbin-vc/0.1.24/sweep/sweep-commit.summary); 0326's reader notice to pplr-vc, cldr-vc, cldr-dc, ccusage-vc and pipeliner-sc (archived todo 201; ~/Devel/scratch/devbin-cc/i0326/reader-notice-0326.md); trellis-vc, its AGENTS.md swift bug gone in Intent 3.3.0 (archived todo 192); Prodinfra, infra --profile takes a path (archived todo 159); release review action 2 to molt-vc and intent-vc, now Intent is cut (archived decision 171).; Ccusage's use-to-activate rename to ccusage-vc as ruled work (decision 178) (edited)
- NEXT DEVBIN RELEASE (decision 177): release review action 3 is issue 0357. Landed: 0357-2 lanes shards (608a0ef4); 0357-1 treescan tags and test scans (9971c5e1); 0357-5 the weights header's tracker citation that test scans caught on main (f0efa06e); 0357-3 CI's shard matrix, 4 macOS and 2 Ubuntu, lint into both gate lists on shard 1, 0155's clean-tree half gone (61 tagged arms), --weights merging several logs per system (26ae0a92). ci.wait stays 90m until a sharded candidate's seconds are sealed. Building: 0357-4's docs half (cc, the cut as the only whole suite in docs/releasing.md); its main-push Ubuntu rerun half waits for hv. At the next candidate: refresh the weights from every shard's log. For hv: the main-push rerun on or off (cc: off); 3 or 4 macOS shards (cc: 4); 0343 close as by design (dc, 07eee2d2; vc: close). (edited)

## Holds

- `--ivault`: not to be started until hv says start. (edited)

## Watch-outs

- Never run `fleet doc` while fleet lives in devbin: it writes a client's installs into a tracked doc. (edited)
- Watching a cut: fail on a "FAILED: " line, never the word "failed"; doctor's "N checks" line marks the gates done. (edited)
- `DEVBIN_FLEET_FROZEN` matches an estate's plan label; check for no "matches none" line before any --apply. (edited)
- Dev/opt/brew contract amendments go to molt-vc, utilz-vc, intent-vc and gtools-vc, agreed when all four answer. (edited)

## Decisions

- hv's standing directives live on hv/wip.md; vc holds that pen under hv's grant. (edited)
- A peer's recommendation is never authorisation: measure it, then adopt, correct or refuse it. (edited)
- Never `git add -A` in the same command as a commit; scope a repair as narrowly as its check. (edited)
- `bin/devbin` is the invocation everywhere; `devbin_version` stays a hand-written literal. (edited)
- hv 2026-09-21: macOS and WSL CI run only on release tags, their candidates (decision 81) and on demand; superseded runs are cancelled. (edited)
- hv 2026-10-03: devbin keeps no list of its users; one licence text at LICENSE and lib/LICENSE.md, held byte-identical by test; every open item is an issue; ignore intent/docs/devbin-users.md. (edited)
- hv 2026-10-25: tmp/ stays a real directory; the no-vendor mode waited for devbin public, which it now is. (edited)
- hv 2026-10-25: critic legs carry no known-positive sample; a leg that asked nothing covers nothing. (edited)
- hv 2026-10-26: vc pushes Intent's main, local then upstream, on intent-vc's word naming the HEAD its build all passed. (edited)
- hv 2026-10-27: release candidates run CI's whole matrix; snapshot commits carry Matthew Sinclair <hello@matthewsinclair.com>; brew changes are proven from a local scratch tap. (edited)
- Landing rule (vc 2026-10-27): a unit, stack or chain lands as run by land-stack.sh when none of its files moved on main since its base; units sharing files run one after another. (edited)
- hv 2026-10-31: devbin may log into kovacs on its own, the remote-leg runner included, but always announces each login to kovacs-sysadm by message (what runs, where). (edited)
- AT rule (2026-10-31): a landing records green ATs for what it proved and red ATs naming the unit that turns each green, so a criterion reads satisfied only when whole; ids AT-<AC group>.<n>, the next free. (edited)
- WP16's cache verbs (2026-10-31, dc's questions): refusals exit 3; gc keeps a named constant per artefact, --keep overrides; gc keeps every key the newest RELEASE seal names (cache<TAB><artefact><TAB><key>); a build handler calls get then put. (edited)
- hv 2026-11-05: nobody builds ccusage's ci-draft path; ccusage keeps its own finalize; dc's SPEC-cidraft.md stays if ever wanted. (edited)
- hv 2026-11-10: the estate desk is devbin-vc's ('I'm assigning The Desk to you'), re-taken on hv's word after each restart (latest 2026-11-13 15:01Z). (edited)
- Desk rulings 2026-11-10: 0326 stays open until pplr#0001, cldr#0001 and ccusage#0007 close; one layer of proof at the desk (no planted faults). (edited)
- hv in vc's window (read 07:31Z by date -u): Webber falls in BEHIND devbin and Intent until both are landed across the estate. devbin and Intent are P0/P1, Webber P3: a Webber ask gets rhadamanth's lanes only when nothing that ships devbin or Intent is waiting or about to ask; Webber work that can run on gyges runs there; nothing of Webber's already in train is stopped.
- hv in vc's window, read 2026-11-13 18:24Z by date -u, replacing decision 173's order: on rhadamanth AE is P1, another estate's Rust parser work P2, Webber P3; on gyges Webber is P1.
- hv's TUI answers in vc's window, read 2026-11-13 19:39Z by date -u, each the recommendation: (1) Intent's ST0093/WP-06 closes now on the 3.3.2 cut's records; (2) ST0011's WP10 to WP14 move out: WP12 done through Intent's ST0093/WP-06, WP10, WP11, WP13 and WP14 cancelled to each estate's own thread, AC-3.4, AC-4.3 and AC-5.4 descoped with them; ST0011 closes after the AT-3.5 fix, WP15, WP16 and WP18 (dc does the record work); (3) Intent's six Not Started threads stay parked.
- hv in vc's window, read 2026-11-14 04:32Z by date -u, after the night's hold: 'You still have the pen. But's it's just webber-* working here now, so you can use rhad and gyges for anything that webber-vc wants. You coordinate.' Desk re-taken; Webber is the only estate on rhadamanth and gyges, gyges one run at a time on webber-vc's GO; replaces decision 174 while it holds.
- hv's TUI answers in vc's window, read 2026-11-14 08:40Z by date -u: (1) the 0.1.24 fleet sweep runs over every estate, Webber included, in a quiet window webber-vc gives (Webber decision 84 confirms); (2) release review action 3 (shard CI by file, macOS first; the cut the only whole suite; tagged tree scans at every landing) goes into the NEXT devbin release; (3) WP16 closes as record work: vc's question to hv framed it as a build still to start, but the cache shipped in 0b5e4fa0 (v0.1.19) and its criteria are met or withdrawn, so dc closes it under decision 175, nothing booked; (4) the old 3.3.1 intent mcp and expl processes move to 3.3.2 at each seat's next restart, nobody kills them. (edited)
- hv's TUI answers in vc's window, read 2026-11-14 08:49Z by date -u: (1) the 0.1.24 sweep commits go to each estate's local remote, fast-forward only, no upstream push (done 08:50Z: 23 pushed, Cards has no local remote; Intent's local push is on this word, not intent-vc's under decision 76); (2) vc drafts the GitHub Support purge for decision 163's three shas and hv files it (~/Devel/scratch/devbin-vc/0.1.24/github-support-purge.txt); (3) Ccusage's use-to-activate rename is ruled work at Ccusage's next session, through todo 215's notice to ccusage-vc; (4) todo 184's host items are re-confirmed with each host's sysadm first, and only the ones still standing go to hv; no-vendor and --ivault stay parked.
- hv's TUI answers in vc's window, read 2026-11-14 09:03Z by date -u: (1) intentd's at-login enrolment on rhadamanth goes ahead now, by rhadamanth-sysadm on hv's word in its own window (stop then enrol, per 0666); vc held the desk for it, then released the hold when hv went AFK at 09:00Z with the word not yet given; (2) the Intranet repo on gyges re-vendors devbin 0.1.24 and pushes to local: done by gyges-sysadm on hv's yes in its window, commit f5b0228b (87 seam paths, 0.1.8 to 0.1.24 from brew, the uncommitted 0.1.11 copy archived first), local fast-forwarded 6756f7c..f5b0228 (55 commits). gyges's 2026-11-01 Time Machine snapshot has aged out. (edited)

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
