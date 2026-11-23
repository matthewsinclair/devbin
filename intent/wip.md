---
verblock: "23 Nov 2026:v3.104: Matthew Sinclair - fold for hv's second compact: 0.1.29 pre-cut"
---

# Work In Progress

DOING and TODO only, one line each. Done work lives in git, `intent issues list` and `RELEASES/`.

## DOING

- The Desk is HELD (17:26Z) for hv's estate-wide localfold+compact cycle: running slots finish; queued asks wait until hv continues: intent-cc's U4a rerun 01M84PZ64QP69YN0S6G767PM0M (P0, first after the hold), devbin-cc's Pplr 01M84M4MAS1FW1Q17CN3JWA2GN then Cldr 01M84M4QYATYPK5WGXKQWMAT40, utilz-dc's 01M84ATR7HKTS674ZCC9FF5TB4 and utilz-ic's 01M84CX8XF19H62JWJC61TDNX1 (Utilz waits on hv).
- devbin 0.1.29 (hv's pre-approval today, by AskUserQuestion: cut on green): dc's pc0129 pre-cut runs at main 534fd421 (slot 01M84PK2H0T8W36JJ7ZJ9XN6EK); on its green END, vc runs bin/devbin release --patch; a red before the tag stops for hv. Then hv's brew upgrade, then the sweep into Intent (on a slot clear of intent-vc's build all) and Molt.
- Intent 3.5.2 (P0): main pushed at e1e84abb8. Open: cc's U4a (rerun queued), U4b, the metadata strip, then a build all, dc's step 2 regenerations and the kovacs rehearsal; READY also waits for 0.1.29's sweep (Intent's assets formula fails brew 7.0.15's brew style until it has I514ea74). hv fires the cut.
- Molt 1.4.8 (Molt decisions 10 to 12): waits for 0.1.29's sweep into Molt, then molt-vc books its cut and a seat runs it with --yes. 1.4.7 stays released without a formula.

## TODO

- Issue I3ce05fa (high, devbin-cc): a pre-tag formula render check in release's plan; not held for 0.1.29.
- Issue 0326 (devbin-cc): Pplr and Cldr runs queued; then Gtools I7bd0048 and Utilz I59c806c (after Utilz ST0031/01; check with utilz-vc first). Molt adopted it itself (0c2cc5c). Resume note: ~/Devel/scratch/devbin-cc/i0326/RESUME.md.
- Utilz STca1b7f9's spike: M1 incomplete at 17:15Z (window read timed out), M2 not run; a narrower re-run needs new bytes and hv's hands.
- Notices for each estate's vc at its next session (vc todos 215 and 222): sweeps through 0.1.28, 0326's reader notice, Trellis, Prodinfra, Baize's unguarded db reset, Prolix's ST0028 state, release.unread's opt-in; Intent's and Molt's are sent.
- For hv (vc todo 213): the no-vendor mode (decision 64) and `--ivault` (hold 2) stay parked until hv schedules them.
- For hv: Webber's phone checks (ic's landing, then dc's fourth archive ced4bc2f), then one gyges run before 2026-12-01 11:08Z.
- Devbin's other-estate mirror remote is 5+ commits behind main; push it when hv says.
- Cards has no git remote, so its 0.1.28 sweep commit (8f6b347) is local only.
- Issue 0373 (six estates' log: lines) goes in the next fleet sweep.
