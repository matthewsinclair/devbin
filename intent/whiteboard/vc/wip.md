---
node: vc
name: Validation Claude
role: validation
session_id: d252d54e-7ad5-4f31-9c5f-02ab8aca3f33
heartbeat_at: 2026-11-13 20:43Z
status: paused
focus: "FOLDED 2026-11-13 20:44Z by date -u on hv's wrap ('bank, fold, and hold'): Intent 3.3.2 released and CI green; devbin 0.1.24 released; ST0011's acceptance passes, WP15, WP16 and WP18 left; every seat told to bank, fold and hold; desk released. Next: hv's list, todo 213."
claims: [ST0011]
---

# Validation Claude (vc)

## DOING

- ST0011: acceptance passes (18 of 18 satisfied, 3 withdrawn to the consumers' own threads on hv's ruling, decision 175). AT lint is clean. Left: WP15 (read seal clock lines), WP16 (build cache, dc), then WP18 last (todo 183); then st done. (edited)

## TODO

- WP18, LAST (hv 2026-10-31: 'right at the end when this is all landed'): docs/assembly-and-the-build-cache.md, 'Devbin's Build Cache for Optimised Release Assembly', written from the as-built. (edited)
- Bank refs in canon (cc's 5, dc's 28, listed by git for-each-ref refs/bank/): check each ref's work is on main by its changed lines, put the list to hv, then clear the landed ones by script (update-ref -d with the old value). (edited)
- HV'S LIST (lean of 2026-11-13 18:14Z by date -u), each for hv's word: (a) devbin 0.1.24 brew switch in canon and fleet sweep; (b) restart the 20 intent mcp and expl processes onto 3.3.2 (put to hv 18:1xZ); (c) GitHub Support purge of the shas from 2026-11-12's candidate pushes (archived decision 163); (d) release review action 3, a ruling (~/Devel/scratch/devbin-vc/release-review/REVIEW.md, archived decision 171); (e) the no-vendor mode (decision 64) and --ivault (hold 2) to schedule; (f) Ccusage's use-to-activate rename, timing unruled (archived decision 148); (g) todo 184's carried host items from 2026-11-01, to re-confirm (archived todo 184); (h) Molt-matts 6bc343e push and ~/Devel/opt/devbin removal (intent/wip.md).
- RELEASE AFTER NEXT, weigh only: a release.gates entry starting with release recurses (archived todo 203); macos and release call built-ins through the launcher (206); no macOS-stage rehearsal before a cut (207); a failed remote leg keeps its worktree on the host (208); dc's todo 67 TMPDIR leftovers; issues 0352, 0354, 0355 (gates blame a peer's tree write on a gate, from molt#0100) and 0356 (--help after a gate option runs the work). (edited)
- NOTICES at each estate's next vc session: sweep notices for 0.1.19, 0.1.20 and 0.1.23 (archived todos 194, 198, 210; shas in ~/Devel/scratch/devbin-vc/0.1.23/aftertag/sweep-commit.summary), and 0.1.24 once swept; 0326's reader notice to pplr-vc, cldr-vc, cldr-dc, ccusage-vc and pipeliner-sc (archived todo 201; ~/Devel/scratch/devbin-cc/i0326/reader-notice-0326.md); trellis-vc, its AGENTS.md swift bug gone in Intent 3.3.0 (archived todo 192); Prodinfra, infra --profile takes a path (archived todo 159); release review action 2 to molt-vc and intent-vc, now Intent is cut (archived decision 171).

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

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
