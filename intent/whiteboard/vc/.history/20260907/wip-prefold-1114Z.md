---
node: vc
name: Validation Claude
role: validation
session_id: 0e264898-52d8-46db-8d2b-aa5edf99757e
heartbeat_at: 2026-09-07 10:36Z
status: active
focus: "ST0005 COMPLETE AND ROLLED OUT. The fleet vendors from ~/Devel/opt/devbin: 14 estates on ONE seam, zero +dirty, committed in every tree; Intentv2 frozen and untouched. AC 19/19, suite 973/973 rc 0, docs at as-built. NEXT, AND hv HAS NAMED IT: test across the estate, starting with `devbin infra` INSIDE LAMPLIGHT. ST0003 WP-02 -- the DNS and mail legs of `infra check` -- is still claimed and unbuilt. 28 commits unpushed and the tag still names e22d9a3; both hv's"
claims: [ST0003, ST0005]
---

# Validation Claude (vc)

**Board cut 2026-09-07 07:32Z, aggressively. Pre-fold archived VERBATIM at `.history/20260907/wip-prefold-0732Z.md`, cmp-verified at 29611 b before this file was touched.** Everything below is what a cold reader needs; the working detail is in the archive and in the commits.

## DOING

- **0.1.1 IS CUT AND READY TO PUBLISH. hv RULED IT: cut 0.1.1 rather than mod 0.1.0 in place** -- which would have been the "two things called one version" defect I had flagged that same morning.
- **THE MACHINE INSTALL COULD NOT SEED A PROJECT, WHICH IS THE ONE JOB IT EXISTS FOR.** My D27 refusal exempted nothing, so `install` from opt/ was blocked. **Both surviving routes were wrong in different directions and I measured both**: from the dev tree you get mid-release bytes and the project records a WORKING TREE as its `source`; from another consumer you get right bytes and a `source_commit` that is THAT consumer's git HEAD -- `10449e2b`, which does not exist in devbin's repo. `install` is now exempt, matching the exemption the wrong-tree guard always had for the same verb.
- **AND THE REFUSAL NAMED A COMMAND ITS READER COULD NOT RUN** -- `cd <your project> && bin/devbin upgrade`, told to someone whose project has no `bin/devbin`. This repo's own "the remediation names a command that EXISTS" defect, in the message read by people with nothing installed.
- **I BROKE THE DEV TREE WHILE TESTING THAT, AND IT EXPOSED AN OLDER GUARD HOLE.** A bare `install` from an install defaults `--into` to the cwd; I ran it standing in the dev tree and vendored `bin/.devbin/lib/` into it -- the frozen copy D12 exists to prevent. `lib/cmd/install` guarded only `dstroot = srcroot`, so a different source walked straight past. Cleaned up (both untracked, verified). The guard now refuses **any** devbin source tree as target. **My first fix required `--into` and was WRONG** -- that default is correct for the documented `DEVBIN_SOURCE` bootstrap, which runs `install` from inside the new project on purpose. Guard the harm, not one route to it.
- **`dvb` OUTSIDE EVERY PROJECT NOW WORKS, hv's REPORT.** All four version spellings failed from `$HOME`. The function falls back to the machine install, LAST in the order so a project launcher and `DEVBIN_SOURCE` both still outrank it. **The prefix is a placeholder substituted after generation, NOT an unquoted heredoc** -- unquoting would expand `$PWD`, `$@` and `${^tried[@]}` at generation and emit a `dvb` frozen to one directory, silently. Same trap `lib/cmd/infra` fell into hours earlier; there is an arm on it now.
- **AN INSTALL ANSWERS ABOUT DEVBIN, NEVER ABOUT A PROJECT**, and the wrong-tree guard no longer fires inside one -- it was naming the install as "your current project", which is confusing and false.
- **TWO EXISTING ARMS BROKE BY READING THIS MACHINE.** The `dvb` fallback made them reach the REAL install at `~/Devel/opt/devbin`. Pinned to a nonexistent prefix. **A suite that passes or fails on machine state is the one thing a test must never do.**
- **lamplight-dc's FINDINGS: THREE ACTED ON, ONE RECORDED.** The flagship profile example in `docs/infrastructure.md` **did not parse** -- flow collections, flow sequences, and a `domains:` map keyed by FQDN instead of handle, in the first thing a new reader copies. Fixed, genericised off the live estate, and **now extracted and PARSED by the suite every run** -- the only assertion that cannot rot. Cross-profile uniqueness had no owner: **`infra profiles <dir>`**, built, red-driven, empty population is an ERROR. WP-02 guidance recorded (key the DMARC store on `report_id`, never the filename). **A peer report is not authorisation -- hv ruled these in.**

## TODO

- **`intent/wip.md` is the authority for project work** and is not copied here. My own queue is only what follows.

### With hv, and neither is mine to take

- **THE PUSH.** 30 commits unpushed, both remotes at `d620bb7`, measured with `git ls-remote` against the REAL remote names -- `local` and `upstream`, never `origin`. **`check all` is now rc 0, so the push no longer takes CI red with it.**
- **WHETHER TO TAG, AND IT IS NOW SHARPER THAN BEFORE.** `v0.1.0` is an annotated tag naming `e22d9a3` and it is PUSHED TO BOTH REMOTES including GitHub, so moving it is outward-facing. **Three different things are called 0.1.0**: the tag (`e22d9a3`, 2026-09-01), `RELEASES/0.1.0.md` (`date: 2026-09-06`, describing the machine install, which is NOT in that commit), and the distributed artifact (opt/ + 14 estates at `8ec60f7`). `git checkout v0.1.0` gives a devbin the 0.1.0 notes do not describe.

### Mine, unsequenced

- **`0059`** -- the BEHIND-you warning cannot fire against an install, which is now every estate. Documented in three places, NOT fixed. Fix shape: a publish SEQUENCE the install carries, since ancestry cannot be recovered from either end.
- **`0056`** -- the census reads disk and never asks git. Still open; the sweep now commits, which narrows it without closing it.
- **THE GUARD RED-DRIVE HAS EXPIRED AND NOTHING SAYS SO.** hv's board states six red arms (2026-08-28) as settled. Four have had their bodies REPLACED since and resolve LIVE out of `INTENT_HOME`. **Not a regression claim: the evidence no longer covers the code in force.** ~40 min, harness in hand.
- **THE CARRIER HOLE.** `.git/hooks/pre-commit.intent` is byte-identical to Intentv2's FROZEN template and differs from v3's. Devbin cannot fix it from here.

### Estate remediation is with lamplight-dc, not me

Packaged and sent. **One thing still needs hv and only hv: which SPF include MailerSend issues today** -- dashboard only, and the fix direction inverts on the answer.

## Holds

- **`use` as a devbin builtin -- BLOCKED, and not to be designed around.** Released only by hv lifting it. **Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START.** Released only by hv saying so. **Checked at this fold: not lifted.**

## Watch-outs

**General forms are in `intent/llm/LESSONS.md`, and at this fold that is TRUE for the first time.** The caption had asserted it since before 2026-09-06 while zero of sixteen entries were actually there -- a record claiming a state it did not have, in the section about exactly that. **All sixteen were promoted at this fold, plus six earned building ST0005**, and each was verified present by grep afterwards rather than assumed. `LESSONS.md` went 257 -> 305 lines.

**Why it happened here and not on the boards that caption was written for: a board is ARCHIVED when its work closes, and an AGGRESSIVE fold is the moment the loss becomes real.** Deferred twice before this one. The rule that survives: **promote before cutting, never after.**

## Decisions

### ST0005 -- the local install. RULED by hv 2026-09-06, BUILT, and ROLLED OUT

- **Brew dropped.** Private repo on one machine -- and the stronger reason, hv's: **brew is a distribution answer to a provenance problem.** A tap would have made devbin easier to obtain while leaving untouched what the source could be.
- **`install`/`upgrade` are CONTEXT-AWARE, not new verbs** (D26). hv rejected `release` twice over: it reads as *release to the outside world*, and `bin/.devbin/cmd/release` already exists. **The mode is ANNOUNCED before it acts.**
- **The install is a DISTRIBUTION POINT, consumer-shaped, with the project half missing** (D27, D33). No `config.yaml`, so `bin/devbin` refuses to run there BY CONSTRUCTION. Chosen from three options; the two runnable variants both needed a discriminator that the files-only one does not.
- **A dirty tree STOPS both verbs, and there is no `--force`** (D28). This is the whole fix -- the directory is only where its output goes.
- **The sweep is a DEV-TREE verb distributing the INSTALL's bytes** (D29), dry-run by default. **No registry** (D31): discovery is derived by scan, because a maintained list lies the first time a project moves.
- **The location is configuration** (D32), never a path in code.
- **THE ROLLOUT, 2026-09-06 20:07Z, on hv's explicit go:** 14 estates upgraded, **all 14 needing the second pass to converge provenance -- exactly the number predicted by measuring one estate first** -- 0 failed. Four byte-states behind six stamps became **ONE**, with **zero `+dirty`**. Committed path-scoped in all 14 trees; other work-in-progress untouched. **Intentv2 skipped**, and its dirt predates the sweep by five days.

### Carried, because they record hv overruling me or a correction owed

- **`dvb` IS THE REAL INVOCATION.** hv's zsh function walks up from `$PWD` and runs `bin/devbin` WITHOUT cd-ing, so a subdirectory is the ORDINARY case -- and from there every `run: bin/devbin ...` named a path that does not resolve. `dvb` itself needed no change.
- **DORMANCY: hv overruled my park.** The design is settled and conceded, so the speculative objection was already paid off.
- **`0052`: hv did NOT take the tag-as-CI-trigger fix.** Recorded as declined, not as pending.
- **SYNC: the rule is dropped and my framing was wrong.** `cc` asked for a rule about WORKING TREES; I widened it to REMOTES so it would reach something here. Owed to `cc`.

### Standing

- hv's standing directives live on `hv/wip.md`. Nothing duplicated here. **I hold that pen under hv's explicit grant; corrections factual only, standing directives byte-verified every time.**
- **Authority chain (hv, 2026-08-28):** my branch is one node -- only `devbin-cc`. **A peer's recommendation is never authorisation.**
- **`bin/devbin` is the invocation everywhere** (supersedes D6). Delivery while in development is the DEV TREE.
- **`devbin_version` in devbin's own config is a CONSTRAINT and MUST stay a literal.** Deriving it from `VERSION` makes `doctor`'s check unfailable.
- **`devbin-users.md` is a snapshot, not a standing fact.** A stale stamp goes to hv, not to a rebuild. Regenerated 2026-09-06 20:12Z on hv's word.
- **ONE RENDERER FOR THE IDENTITY LINE** (hv, 2026-09-01). `version_identity` is the single home.
- **A machine posture belongs in a file that can be re-measured, never in a commit message that cannot.**
- **D1 to D25 are permanent in `intent/st/COMPLETED/ST0001/design.md`; D26 to D34 are in `intent/st/ST0005/design.md`.**
