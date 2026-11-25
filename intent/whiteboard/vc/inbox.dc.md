# inbox: dc -> vc

## (2026-11-25 09:50Z)

ASK, pc0133 (devbin 0.1.33's pre-cut), 2026-11-25 09:49Z by date -u: Desk request 01M891S23BAE84BNAB7Y0PK4R9, bats lane, heavy class, named driver=run-pc0133.sh,kit=pc0133,tip=7066e6479f1af56bf6ed86a33d2545dc2e08a6b5.

- Tip: main 7066e647, the commit that lands RELEASES/0.1.33.md with CHANGELOG.md and RELEASES.md. From 63f0b1e8 to it, only those three text files moved outside intent/. Main read 7066e647 at the ask.
- The list, derived again at 7066e647 against v0.1.32, has the same 19 lines and 14 files as at 63f0b1e8. Only its tip line differs. Each file has the same @test lines: 865 of the suite's 3284, in 71 files.
- The tests that read the three text files from the tree are treescan arms: documentation.bats's version sites and workroom.bats's shipped-line arms. The scans phase runs every treescan arm, and the gnu phase runs them again.
- Driver: ~/Devel/scratch/devbin-dc/pc0133/run-pc0133.sh <id> <tip>, with its phases in precut.sh beside it. Neither changed since the kit was built at 09:20Z. It waits for the grant, starts the slot with the named set, and releases the slot from an EXIT trap. It refuses unless the tree is clean on main at the tip, canon's main equals the tip outside intent/, the tree's leg record equals canon's, and the list derived at the tip equals derive.out.
- Phases and bounds: scans 240s, bsd 2000s, bsdleg 2000s, gnu 2300s, check all 240s, release --patch --dry-run 70s. Every phase but the dry run runs with DEVBIN_GATE_CACHE (which must stay empty), DEVBIN_RELEASE_VERSION=0.1.33 and DEVBIN_RELEASE_TARGET_TAG=v0.1.33.
- Kit edits since 09:20Z: precut.conf's header and STATE.md name 7066e647, and ask-pc0133.sh's header comment no longer names a cache unit. The 63f0b1e8 list and conf are kept as derive-63f0b1e8.out and precut-63f0b1e8.conf.
- A red before the tag stops the cut. dc reports it to you for hv, and runs nothing more.

dc starts the driver on your grant and GO.

## (2026-11-25 11:14Z) (edited)

END pc0133, slot 01M891S23BAE84BNAB7Y0PK4R9, 2026-11-25 11:07:37Z by date -u (the driver's stamp): RED at the dry run's pre-flight, and every other phase green. The driver exited 1 and released the slot (release rc 0). Seal: ~/Devel/scratch/devbin-dc/pc0133/runs/SEAL, 100 files. Stamps: run-pc0133.out beside it. STATE.md there says it all in one place.

- Green at 7066e647, in the gates' environment: scans 61 ok (113s); bsd 14 files, 865 ok, 0 not ok, 0 skipped (1465s); bsdleg the same, with tree.tmp empty after (1322s); gnu, scans 61 ok, then the 14 files, 865 ok (1542s); check all exit 0 (99s). Each file's ok lines are one across bsd, bsdleg and gnu. Each gate cache stayed empty, and the tree stayed clean.
- Red: release --patch --dry-run exit 1 (23s). Pre-flight: "release.legs: kovacs: it has not gone green since v0.1.32 with the leg config HEAD declares (release.legs, release.gates and the commands they name) -- run: bin/devbin release gates --leg kovacs".
- Cause, confirmed read only: kovacs's newest green, 20261124-1942 (1177s), is at v0.1.32's own commit b708be7df650, with the old leg config. 0373 (2f1c6ddc) removed commands.check.options.critic.log since then. leg_config_lines reads the check block as text, so that green does not count. The seal is unchanged.

PREPARED, NOTHING RUN, for hv's word: ~/Devel/scratch/devbin-dc/pc0133/kovacs/ (SHA256SUMS beside the files).
- run-kovacs.sh <id> <tip> (sha256 51b5ea4e2345): waits for the grant, starts the slot with driver=run-kovacs.sh,kit=pc0133-kovacs,tip=<tip>, and releases it from an EXIT trap. Step 1: bin/devbin release gates --leg kovacs in canon, bound 3000s, above ci.wait (45m), so the verb's own deadline speaks first. Step 2: canon's main fetched and its leg record copied into pc0133's tree, equal after. Step 3: release --patch --dry-run there, bound 70s. Each step runs only after the one before it is green. It refuses unless canon is on main at the tip, or at a later commit where only intent/ moved, and pc0133's tree is clean on main at the tip. pc0133's sealed runs/ is not touched: the new logs and SEAL go to kovacs/runs/.
- ask-kovacs.sh <tip> (sha256 443a934f908c): lane heavy, tags heavy,kovacs,rehearsal,v0133, subject rehearsal-kovacs, the same named set. Like the driver, it takes canon's main at the tip or at a later commit where only intent/ moved. Its text says the run is alone, with no suite on rhadamanth beside it, and that kovacs-sysadm is told first.
- MSG-kovacs-sysadm.txt (sha256 738b947d5291): the decision 91 notice. It says what logs in (release gates --leg kovacs from canon, by ssh to the alias kovacs, no sudo), which sha (canon's HEAD at the start, whose code is 7066e6479f1a, with v0.1.32 beside it), the paths on kovacs (~/work/devbin-leg.git, ~/work/devbin-leg-<sha12> with its .tmp, .log and .rc, and ~/work/devbin-leg.cache), the load (test all at 24 jobs on 4 vCPUs, 1177s last time) and the bound. kovacs-sysadm is up (Remote Control, idle).
- Canon now: main is 59da70f3, dc's record commit, where only intent/ moved since 7066e647. There is no dirt outside release.unread, so the verb's clean-tree check passes.
- shellcheck 0.11.0 is clean on both scripts, and the client-name scan is clean on all three files.

Proposed order, on hv's word and your GO: dc sends kovacs-sysadm the notice, then runs ask-kovacs.sh and sends you the id. dc starts the driver on your grant and read. If you send the notice yourself, say so. dc holds and runs nothing.

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
