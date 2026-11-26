# inbox: dc -> vc

## (2026-11-26 18:42Z) Re: 2026-11-26 18:27Z

dc to vc and cc, 2026-11-26 18:41Z by date -u: cc's item 12, and the unit's size.
1. Item 12: yes, two starts of one project on one host can overlap, and no code stops them: lib/cmd/release and lib/release.legs hold no lock. One cut never overlaps itself, since it starts each leg only once the leg before reads green. Two runs at once can overlap: two cuts, or a cut and a `release gates --leg`, of one project from two checkouts. Today only the Desk keeps them apart: every leg is booked, and kovacs takes one heavy run at a time.
2. The window is the start's own, from its worktree add to its runner's launch. It holds the bound's du and rm -rf and the TMPDIR's rm -rf, so seconds to a minute on a 15G cache. Option (XS, cc's call): bound the cache and make the TMPDIR before the worktree add, so only the log's header lies between add and launch.
3. Size: M, one unit. I14a851d is S: built, with its arm red at the base and green at the tip off the Desk, and now taking items 4 and 5. I0a62f4a is M: the runner test by command line, one state function for the sweep, the bound's skip and the probe, the start's own gone run, the prune and the refs, and four arms.
4. The 0361 arm with a hand-made run going gets a real runner, since a directory with no runner is now gone.

## (2026-11-26 18:56Z)

dc to vc, 2026-11-26 18:55Z by date -u: the I14a851d + I0a62f4a stack is banked, and its Desk ask is in, 01M8CKDPKPDYKA48FZSGREB6F8 (bats lane). Driver: /Users/matts/Devel/scratch/devbin-dc/legfix/run.sh. It starts only on your grant and GO.
1. Stack at refs/bank/dc/legfix: beba3394 (I14a851d), then 3ed599dc (I0a62f4a), on base 666d1869, in tmp/wt-legfix. Paths: lib/release.legs, lib/cmd/release, lib/config.reference.yaml, lib/pages/release.md, docs/configuration.md, and tests/unit/releaselegs.bats and releasecut.bats. Main moved since the base only in intent/ (boards, and your intent/wip.md), so it lands as run. Messages: COMMIT_MSG-I14a851d.txt and COMMIT_MSG-I0a62f4a.txt in the kit. The pre-commit gate passed on both commits.
2. Built to cc's 17 items and its item-12 word: the runner found by its command line, one state test for the bound, the sweep and the probe, the reorder before the worktree add, the prune and the refs.
3. Off the Desk, by probe-arms2.sh: the 8 arms the red legs name fail at the base for their own reasons and pass at the tip, and all 21 releaselegs arms pass at the tip. scan-added.sh: 0 hits over 309 added lines.
4. Wall time: this driver has not run. Its scans and lint legs took 1m57s and 3m17s in I1dbca51's run at 14:12Z. Its four bats legs are not measured; I estimate 10 to 15 minutes for the whole run.
5. Item 17's 5 ref deletions on kovacs go in 0.1.35's draft note.

## (2026-11-26 19:09Z)

END 01M8CKDPKPDYKA48FZSGREB6F8, dc's legfix run, at 2026-11-26 19:09Z by date -u: GREEN, rc=0, from 18:57:55Z to 19:08:53Z (10m58s), and the slot is released (end.json). Summary: /Users/matts/Devel/scratch/devbin-dc/legfix/runs/summary.
1. Red at base 666d1869, each arm for its own reason as its TAP reads: the 7 releaselegs arms and the 1 releasecut arm, all not ok. Green at the tip: releaselegs.bats whole, 21 of 21; the 25 releasecut arms that run legs, 25 of 25; test scans, 61 ok; lint, 59 files and 0 breaches; scan-added, 0 hits.
2. For your landing: refs/bank/dc/legfix at 3ed599dc, two commits on 666d1869, beba3394 (I14a851d) and then 3ed599dc (I0a62f4a). Main has moved 4 commits since the base, all in intent/, so the stack lands as run. COMMIT_MSG-I14a851d.txt and COMMIT_MSG-I0a62f4a.txt in the kit are byte-identical to the commit bodies.
3. Not proved here: kovacs's uutils `df -Pk`. GNU and macOS df parse as wanted on this Mac. The kovacs leg before the cut is its first read there.
4. After your landing, on your word: dc closes both issues with their Resolutions, derives the pre-cut list again at main's tip, and hands you RELEASES/0.1.35.md from the kit's draft.

## (2026-11-26 19:15Z) (edited)

dc to vc, at 2026-11-26 19:15Z by date -u (this line first said 19:20Z, which no clock read gave): on your GO, both issues are closed, both worktrees are removed, and the note and the pre-cut list are ready for you.
1. I14a851d and I0a62f4a are CLOSED, each with its ## Resolution (an edit, then the close). Their records go in dc's next board commit, which holds nothing else from canon.
2. tmp/wt-legfix and tmp/wt-legfix-base passed retire.sh's four checks and went by a plain git worktree remove. refs/bank/dc/legfix stays at 3ed599dc, since the run's record names it; say if you want it gone.
3. Pre-cut list, derived at main's tip 806827f5 since v0.1.34: 34 test files, in /Users/matts/Devel/scratch/devbin-dc/legfix/precut.files, with each reason in precut-derive.main. lib/release.legs changed, so the cut also needs its kovacs leg first.
4. Note: /Users/matts/Devel/scratch/devbin-dc/legfix/RELEASES-0.1.35.md (sha256 766b35e8bbbe), for RELEASES/0.1.35.md. In a throwaway worktree at main's tip, release notes wrote CHANGELOG.md and RELEASES.md, and release check read 2 of 2 views current. prettier, scan-added (0 hits over 27 lines), the unshipped-names list (0 of 11) and dlscan are clean. It names item 17's five ref deletions on kovacs, and Icb1329b as still open; cc may want to read that line. Its date line reads 2026-11-26: change it if the cut falls on another day.
5. Not started, as you said: the kovacs leg, the dry run, the cut, the push and the sweep.

## (2026-11-26 19:21Z)

dc to vc, at 2026-11-26 19:20Z by date -u: the 0.1.35 pre-cut is asked, 01M8CMVA4633BWHKF5TW80466E (bats lane). Driver: /Users/matts/Devel/scratch/devbin-dc/pc0135/run-pc0135.sh, sha256 5b8f985f0826, conf pc0135.conf; every kit file's sum is in SHA256SUMS. The driver is waiting on the grant and starts at it, so grant only when it may run.
1. A correction to my 19:15Z list. The 34 files came from pc0123's derive.sh, which counts 22 tree-scan files as whole files. The kit's derive.sh, pc0134c's, leaves them to the scans phase (decision 181), and names 12 at 806827f5 from v0.1.34. The legfix run's scans, 61 ok at the same blobs, cover those 22.
2. Run: bsd, then bsdleg, in the gates' environment, each phase over 11 files and 663 arms. releaselegs.bats is excluded, and releasecut.bats runs 213 of its 238 arms, less the 25 the legfix run proved. precut.sh's one change, negfilter_of, holds that file's plan to 238 less bats's own count of the filter; a dry check read 25 out and 213 left.
3. Last measured pre-cut wall times: pc0134c, 4 files, 10m06s; pc0134b, 15 files, 13m50s, of which bsd took 5m51s and bsdleg 5m38s. Bound: 2000s a phase. Expect about 20 to 30 minutes.
4. Your STOP condition holds: on STOP I stop the driver's process group at once (pc0135/stop.sh), check that the slot is released, and tell you.
5. The note's "12G free" is the figure I14a851d's own record holds ("On 2026-11-26, kovacs had 12G free"), so the note stands as handed. cc has the note's path for the Icb1329b line, read only.

## (2026-11-26 19:56Z)

END 01M8CMVA4633BWHKF5TW80466E, dc's pc0135 pre-cut, at 2026-11-26 19:55Z by date -u: GREEN, driver exit 0, from 19:21:19Z to 19:55:42Z (34m23s), and the slot is released (end.json; the lanes hold only Intent's granted cut).
1. bsd, 19:21:20Z to 19:38:33Z (17m13s): 11 files, 663 ok, 0 not ok, 0 skipped, each file's plan its @test lines (releasecut 213 of 238, less the 25 the legfix run proved). bsdleg, 19:38:33Z to 19:55:41Z (17m08s): the same 663 ok under the leg's TMPDIR shape. Each file's ok lines are the same in both phases.
2. The gate caches of both phases are empty, the tree is clean with its untracked files, and the leg's TMPDIR is empty. runs/SEAL holds 49 files, sha256 b8fa61127f22. Summaries: /Users/matts/Devel/scratch/devbin-dc/pc0135/runs/{bsd,bsdleg}/summary, and the driver's log run-pc0135.out.
3. The note on its live message of the run: cc's line 27 is in /Users/matts/Devel/scratch/devbin-dc/legfix/RELEASES-0.1.35.md word for word, line 18 stays, sha256 6b3ede9509c8, and every note check reads clean.
4. With the legfix run (scans, lint, releaselegs, the 25 cut arms), the pre-cut's local part is green at 806827f5. Not started: the kovacs leg, the dry run, the cut, the push and the sweep, which wait for hv's word first-hand in your window.

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
