## Summary

**The update notice, the interactive upgrade offer and doctor's source check all call any difference "behind". So when the source is BEHIND the project, devbin offers the upgrade that reverts it.**

`devbin_source_state` (lib/helpers) compares the project's recorded commit to the commit the source holds now. When the two are equal it prints `level`; otherwise it prints `behind <recorded> <now>`. It never asks which way the source moved. Three readers act on that word:

- `devbin_offer_upgrade` prints "An update to devbin is available", asks "Upgrade now? [y/N]" and, on yes, runs `bin/devbin upgrade`.
- `check_source_currency` (lib/cmd/doctor) notes "the devbin this project came from has moved on" and says `run: bin/devbin upgrade`.
- `_devbin_update_line` prints "UPDATE: devbin has moved on since this project vendored it", with its own copy of the comparison.

When the source is a rewound install, or a checkout on an older branch, every one of those lines tells the person to revert their runtime. It is the silent revert issue 0021 measured at 11 files. `upgrade` itself now warns about it: 0059 made its BEHIND warning fire through an install. But the offer calls the revert "an update" before `upgrade` runs, and a yes means the person has already chosen before they see the warning.

## Why it was not fixed in 0059

It is adjacent, not the same defect. 0059 fixed the question `source_direction` answers, and it got those answers to `upgrade` and `vendor`. These three readers never asked it: they compare two shas for equality. Found while reviewing 0059, and agreed with vc as its own issue (2026-09-16).

## The shape of a fix

- Route the three readers through `source_direction`, so one answer covers both the git path and the install path.
- Offer only on `forward`.
- On `backward`, say the source is BEHIND this project, and never offer.
- On `unrelated` and `unknown`, report the difference without calling it an update.
- doctor's note should say the same.

**Highlander, found alongside.** `devbin_source_state` and `_devbin_update_line` each keep their own sha check (`*[!0-9a-f]*`). Neither has `is_commit_sha`'s length test, and both strip ` +dirty` then compare, so a dirty record at the source's commit reads `level`. 0059 made `+dirty` read `unknown` in `source_direction` for exactly this reason. Both belong on `is_commit_sha` and on the one direction reader.

## Arms a fix needs

- A consumer AHEAD of a rewound install gets no offer, and the notice and doctor say BEHIND.
- A source that moved forward still gets the offer, as today.
- A `+dirty` record does not read level.
- A mutation that makes the offer ignore the direction goes red.


## Fixed 2026-09-17 -- the notice, the offer and doctor read which way the source moved, and only forward is an update (dc), reviewed by vc

**Commits:**
- `2989a8d`: the fix, as first built.
- `a6b8180`: critic-shell's findings folded (0 critical, 2 warnings, 12 recommendations, 6 style).

**One direction reader, reachable before the offer.** `source_direction`, `is_commit_sha`, `commit_direction`, `manifest_ancestry` and `install_direction` moved from `lib/install` to `lib/helpers`. The launcher loads only `lib/helpers` before it offers, so the reader had to live where every asker can reach it. `install_ancestry`, the publish half that writes the table, stays in `lib/install`. `devbin_source_state` now answers five states:
- `level` is `same`.
- `behind <rec> <cur>` is `forward`, and it is the only update.
- `ahead <rec> <cur>` is `backward`.
- `differs <rec> <cur> <why>` is `unrelated`, or an `unknown` direction between two different commits.
- `unknown <reason>` means there was nothing to compare, or the same commit on both sides with no direction for it.

**The three readers.**
- `devbin_offer_upgrade` offers only on `behind`.
- `_devbin_update_line` reads the state instead of keeping its own sha check and equality test. On `behind` it prints UPDATE as before. On `ahead` it says the source is BEHIND this project. On `differs` it reports the difference. For both of those it points at `vendor`, never at `upgrade`.
- doctor's `check_source_currency` says the same, as a note in every state.

`_devbin_source_head` and the recorded commit both go through `is_commit_sha`. A `+dirty` record at the source's own commit no longer reads `level`, and a record too short to name a commit is no longer compared.

**`ahead` is a claim about history, not bytes (critic-shell W1).** Whether any vendored file would change is upgrade's `seam_is_level`. So the readers say which way the commits lie and point at `vendor`, and never claim an upgrade would revert the runtime. The first build said REVERT; `a6b8180` removed it.

**Arms:**
- `updatenotice.bats`: ahead through a rewound git source and through an install's table; the notice says BEHIND and names vendor, not upgrade; a commit the install never held differs; a different history differs; a dirty record at the source's commit is never level; a short record is unknown; one sha check and one direction reader across `lib/`, `bin/devbin` and `bin/.devbin/cmd`, by either definition spelling, the charset test and `merge-base --is-ancestor`.
- `upgradeoffer.bats`: controls that each fixture builds the history it claims; ahead is not offered, bare or under doctor, on a terminal; a commit the install never held is not offered; doctor's source line for behind, ahead, differs and level.
- **Re-fixtured:** the notice's and the offer's firing arms recorded a made-up `0000...` sha, which is not behind anything. They now build real histories: `mkforward` and `mkahead` for a git source, and for an install, `mkbehind` and `mkahead` over real publishes. `commit_seam`, `consumer_of_install`, `set_recorded_commit`, `manifest_of` and `header_of` moved from `localinstall.bats` to `tests/lib/test_helper.bash` so both files share one way to build them.
- Against the pre-fix code, 14 of the 17 new arms fail. The other 3 are controls that pass either way: the behind fixture, doctor on behind, and doctor on level.

**Mutation checks.** dc ran 14 at `a6b8180` and killed all 14:
- the offer ignoring direction;
- backward, unrelated or an unknown direction reading as behind;
- a dirty record at the source's commit reading level;
- the notice saying UPDATE for ahead;
- doctor naming upgrade for ahead, or saying moved on for differs;
- `is_commit_sha` without its length test;
- the state skipping `is_commit_sha`;
- a copy of `is_commit_sha` in `lib/cmd/vendor`;
- an xdigit check in `lib/install`;
- an ancestry question in `lib/cmd/upgrade`;
- the differs notice dropping vendor.

At `2989a8d`, 10 of the same were killed.

**Residuals, declared:**
- A forward move that changes no vendored file is still offered as an update, as it always was. `upgrade` then changes nothing.
- The source's HEAD is read with bare `git`, not `git_readonly`, in `_devbin_source_head` and `commit_direction`. So an inherited `GIT_DIR`, such as a gate run from a git hook on a terminal, can place the wrong repository. This predates 0079, but the notice and doctor now reach `cat-file` and `merge-base`.
- `commit_direction` treats a recorded prefix of HEAD as `same`, while `install_direction` needs an exact match.
- `merge-base --is-ancestor` failing with 128 is read as not-an-ancestor, so a broken clone can read `unrelated`.
- `level` compares commits, so a source checkout with uncommitted edits at the recorded commit reads level while `upgrade` would copy the edits.
- The equal-shas `unknown` branch infers its cause instead of being told it.

These all come from the moved code or predate this issue. None makes an `ahead` or `differs` source offered as an update.

**Suite.** 1240/1240 at `a6b8180` (dc), rc 0, with the 3 standing skips, in a detached worktree under its own TMPDIR: 1223 at 0080's close plus 17 new. vc's re-run: VC_SUITE_LINE
