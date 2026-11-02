**vc's review of ST0007 WP-02 at `5f4d898`: NOT OK YET. Four code defects and thirteen surviving mutants to fold; everything else verified.** Each finding below was measured by vc, including the two critic-shell passes' claims: the test critic traced its "stays green" by reading, so every one was run as a mutation before it went in here.

## What holds (verified by vc)

- **Full suite at 5f4d898**: 1309/1309, rc 0, the 3 standing skips, no non-TAP line, 12:25Z to 12:41Z, in a detached worktree (dirty 0 before, clean after apart from ignored tmp/); all 20 added or modified paths cmp-equal to the commit.
- **shellcheck 0.11.0** clean on lib/release.notes, lib/cmd/release, lib/helpers, bin/devbin and lib/infra.
- **Parity, re-measured independently**: the old generator run in a git-archive export of f34753f against the views committed at 5f4d898 (RELEASES/ unchanged between them): RELEASES.md identical (1155 bytes), CHANGELOG.md one line, the ruled clause. `bin/devbin release check` at HEAD: rc 0, 2 of 2 views current, the note for 0.1.1 dated.
- **Read against the code and holding**: no config read and no die or exit in lib/release.notes; every refusal checked where it happens (critic-shell confirmed); the command environment re-pointed by name after `cd -P`, OLDPWD unset, DEVBIN_LIB and DEVBIN_NAME untouched; `export "$DEVBIN_ROOT_VAR=$PWD" || return 1` and its arm; the header's WHOLE-tree and owned-set-versus-read-set wording; the releasecore.bats text-pin comment; docs/configuration.md's notes kinds and command paragraph; bin/devbin's DEVBIN_ROOT_VAR export and its reservation.
- **The nine points on vc's board**: (1) body against release.yml's awk, held (V04); (2) views_check on a view stale by one line, held (V08, V05); (3) mktemp_beside's modes, held for the bases tested (V02, V03) but see T2 and K3; (4) the command environment, held except DEVBIN_INVOKE (T1); (5) the export guard, held; (6) the header, held; (7) the decoy arm, held (V06); (8) the six ported arms, see L2; (9) the text-pin comment, held.

## Mutations (vc's, in a git-archive export of 5f4d898, each applied exactly once with its diff shown, every restore cmp-proved)

| Mutation | What it changes                                                     | At 5f4d898                                             |
| -------- | ------------------------------------------------------------------- | ------------------------------------------------------ |
| V01      | `DEVBIN_INVOKE=bin/devbin` dropped from `_notes_command_env`        | **survives**, release 66/66                            |
| V02      | a new file's mode hard-coded `chmod 644`                            | killed: helpers new-file arm, release first-render arm |
| V03      | `cp -p` -> `cp` in `mktemp_beside`                                  | killed: helpers x2, release x2 (views, dating), gendoc |
| V04      | the releases body printed with an extra `\n`                        | killed: the workflow-awk arm (cmp EOF)                 |
| V05      | views_check returns 1 on a STALE view                               | killed: the views_check status arm, check x3           |
| V06      | the changelog body read from the cwd                                | killed: the decoy arm (changelog), the body arm        |
| V07      | check_notes does not count STALE                                    | killed: check FAILS x3                                 |
| V08      | views_check compares line counts, not bytes                         | killed: STALE for a view one line off                  |
| V09      | `0666` -> `0644` in the new-file mode                               | **survives**, helpers 3/3, release 66/66               |
| V10      | the render-failure branch's `rm -f "$tmp_log" "$tmp_index"` removed | **survives**, release 66/66                            |
| V11      | `notes_views_check`'s `_notes_args` call removed                    | **survives**, release 66/66                            |
| V12      | `notes_where`'s no-provider check removed                           | **survives**, release 66/66                            |
| V12b     | `notes_where`'s version check removed                               | **survives**, release 66/66                            |
| V13      | RELEASES.md replaced in place (`cat >` then `rm`), not renamed      | **survives**, release 66/66                            |
| V14      | views_check moves the fresh render into place for a MISSING view    | **survives**, release 66/66                            |
| V15      | `_notes_command_paths_ok date` removed                              | **survives**, release 66/66                            |
| V16      | views-check's no-path refusal removed                               | **survives**, release 66/66                            |
| V17      | paths' printed-nothing refusal removed                              | **survives**, release 66/66                            |
| V18      | the surrounding-space path refusal removed                          | **survives**, release 66/66                            |
| V19      | check_notes' `elif ! state=` made a separate `if`                   | **survives**, release 66/66                            |

V09 to V19 are the test critic's claimed gaps, confirmed. The mutation scripts are `wp02/mutate.py` and `wp02/mutate2.py` in vc's scratchpad; the exact replacements are those rows.

## Code: fold before the OK

- **K1 (medium) -- an empty `date: ` line in an open releases note is read as no date, and dating it can refuse after writing.** `_notes_releases_field` prints an empty value for `date: `, and `_notes_releases_header` treats it as absent, so the note reads `open`. Measured: with the empty line AFTER `version:`, `notes_date` exits 0 and leaves two date lines (`date: 2026-09-17` under version, `date: ` still below); with it BEFORE `version:`, `notes_date` rewrites the note to `status: released` with the date under version, then refuses on its read-back ("released but carries no `date:`"), and the note is left unreadable. A refusal must not have written. Fix: tell a present-but-empty `date:` from an absent one and refuse an unreleased note carrying any `date:` line, empty included, so state refuses before date writes; arm both positions, with the note cmp-unchanged after the refusal.
- **K2 (medium) -- under notes.kind command, `views` and `views-check` accept an empty answer, so a notes.run with no such arm passes `release check`.** Measured at the library: a notes.run answering only `state` gives views_check rc 0 with no output and views rc 0 with no output; through the dispatcher (critic-shell) check prints "generates no views, so none were compared" and exits 0 over a hand-edited view. Every other verb refuses an empty answer or reads back. It is the handler's own rule: an unbuilt step that exited 0 reads as a step that ran. Fix: a command with no views answers an explicit `none`; empty output is refused naming the verb. The changelog kind keeps its silent no-op, since there the library itself knows.
- **K3 (low, a behaviour change) -- `mktemp_beside` puts a read-only target's mode on the temporary BEFORE the write, so the writer's `>` fails.** Measured: `sed_inplace` on a 0444 file: at 5f4d898^ rc 0, the content changed, the file left 0600; at 5f4d898 rc 1, "Permission denied" on the temporary's name, content unchanged, no temporary left; a 0644 control rc 0 and mode kept. The comment's "a writer's `>` into it truncates and keeps that mode" is false for such a file, and "THE ONE HOME" covers only creating the temporary: the write, the checked `mv` and the cleanup are still repeated in five writers (lib/helpers x2, lib/release.notes x3). Fix: apply the mode after the write and before the rename, in one helper that owns the whole replace; or refuse a read-only target by its own name. In WP-02 or as an issue is dc's call; if an issue, the behaviour change goes in WP-02's as-built.
- **K4 (low, unreachable today) -- a relative root under an exported CDPATH makes a command provider answer from somewhere else.** `cd -P "$root"` searches CDPATH first and prints the directory it chose, which the capture keeps. Measured: `notes_body root 1.0.0` with root/ in the cwd and CDPATH naming a decoy: rc 0, body "<decoy path>" then "the cdp body"; without CDPATH, "the cwd body". Today's caller passes an absolute PROJECT_ROOT, and WP-03's roots will be absolute. Fix: `_notes_args` refuses a root not starting with `/` (a relative root depends on the cwd for every kind, which the header rules out), and `cd -P -- "$root" >/dev/null`.

## Tests: fold before the OK (each a surviving mutant above)

- **T1 (V01) -- DEVBIN_INVOKE's re-point is unarmed.** Both env-dump runs stand at the project root, where bin/devbin already exports `bin/devbin`. Fix, measured by vc: a third run from a subdirectory, `bash -c 'cd "$1" && ../bin/devbin probe "$2"' _ "$PROJ/sub" "$copy"`, asserting the handler got `DEVBIN_INVOKE=$PROJ/bin/devbin` (the control) and the command got `bin/devbin`: green at 5f4d898, red under V01 on "the command's DEVBIN_INVOKE=<proj>/bin/devbin".
- **T2 (V09) -- the new-file mode arms run under umask 027, where every base from 0640 to 0666 gives -rw-r-----.** Fix: a row under umask 000 (expect -rw-rw-rw-) or 002 (-rw-rw-r--), in helpers.bats and release.bats.
- **T3 (V10) -- a render that fails part way can leave CHANGELOG.md.XXXXXX and RELEASES.md.XXXXXX in the root.** The part-way arm hashes the two views only. Fix: tree_sum around the failing run, or the leftover-temporary `find` the success arm already has.
- **T4 (V11, V12, V12b) -- the refusal arm asks only notes_state, notes_body and notes_paths.** Fix: every verb that takes a root or a version, notes_views_check under changelog included, plus notes_where with no provider selected and with `v1.0`.
- **T5 (V13) -- only CHANGELOG.md's kept mode and changed inode are asserted.** An in-place write of RELEASES.md keeps both. Fix: give RELEASES.md a mode no umask gives (eg 604) and assert it kept and the inode changed.
- **T6 (V14) -- "writing nothing" is asserted only for the stale-by-a-line case.** A views_check that restores a MISSING view while printing STALE passes. Fix: assert the missing view is still missing after the check.
- **T7 (V15 to V18) -- four command-output refusals have no arm**: date's path check, views-check with no path, paths printing nothing, and a path with surrounding space; and the stub's `date) exit 4` row is never reached. Fix: one failing row per branch, each asserting its message; use or remove that stub row.
- **T8 (V19) -- "rather than looking up a note" cannot fail.** A separate `if` still exits 1 with the guard's message. Fix: `refute_output_contains "the note for unknown"`.

## Tests: low, verified by reading (dc's call, recommended)

- **L1** release.bats:169 `[[ "$output" == *"--dry-run"* ]]` cannot fail: refuse() prints usage first and usage carries `[--dry-run]`. Search the refusal line only, as releasecore.bats does.
- **L2** Three ported arms duplicate releasecore.bats's AT-1.3 arms: "bare release exits 1", "release --help exits 0" and "an unknown release word is refused" (the same is_semver branch as `v1.2`). The other three reach a real write only because notes exist (notes --help against a hand edit, check --help against stale views, notes --dry-run against a hand edit) and are worth keeping, with a line saying so.
- **L3** `run_release` repeats test_helper's `run_in_project`.
- **L4** `mode_of` and `inode_of` live only in release.bats while helpers.bats and gendoc.bats inline `ls -ld | cut -c1-10`: one home in test_helper.
- **L5** gendoc.bats:299 and helpers.bats:851 use 644, which is also a new file's mode under umask 022, so a writer that dropped the kept mode for the umask's default passes: use 640 or 604.
- **L6** The env-dump arm's probe fixture hand-writes what write_config and create_test_command do.
- **L7** releasecore.bats:600 re-asserts the changelog "generates no views" line release.bats:1400 holds, and the VERSION and CHANGELOG setup is copied five times.

## Recommendations (not blocking)

- The command state's date pattern (lib/release.notes:949) repeats `_notes_is_date`.
- RELEASES.md's column widths come from awk `length` and `%-*s`, which can differ between awk implementations and locales for a non-ASCII headline (inherited from the generator; every current headline is ASCII).

## What happens next

dc folds K1 to K4 (K3's scope dc's call) and T1 to T8, and L1 to L7 as dc sees fit. vc then re-runs V01 to V19 at the fold's sha, expecting every one killed on the arm meant for it, re-measures K1 to K4, and runs a full suite; the OK follows that. The two critic reports are summarised here, not attached: the code critic found 0 critical, 3 warning (K2, K3, K4), 4 recommendations (K1 and the two above, plus check_notes deciding what zero verdicts mean in the handler, which vc does not ask to change); the test critic found 8 critical (T1 to T8, all confirmed by mutation) and 7 warning (L1, L3 to L7, and L5's two files).
