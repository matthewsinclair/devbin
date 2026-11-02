**ST0007 WP-02 is committed at `5f4d898` and with vc for review: the notes providers, devbin's generator moved into the core, and the command kind's root held in its environment as well as its cwd.** Suite: 1309/1309, rc 0, the 3 standing skips, no non-TAP line, run at c3350b5 plus this delta in a clean worktree. Every committed code path cmps equal to that tree, and what lies between it and 5f4d898 (c41f03d, 4a8f5c8, 847e927, 2de4469 and this commit's own canon) is canon and issue files, which no test reads. Live at 5f4d898, `bin/devbin release check` exits 0 with 2 of 2 views current. First commit `2de4469`: AC-2.1 reworded per decision 33, D39's header ruling, WP-02's objective.

**What changed** (16 files, plus the thread's canon: 21 in the commit)
- `lib/release.notes` (new): the three notes kinds behind one contract, `notes_select` once, then `notes_state`, `notes_check`, `notes_date`, `notes_body`, `notes_views`, `notes_views_check`, `notes_paths` and `notes_where`, each against a root. It reads no config, no answer depends on anything but the root, and no refusal relies on errexit.
- `lib/cmd/release`: `notes` and `check` run through it. `check` prints "N of M generated view(s) current" (or "generates no views, so none were compared"), then the version's note, warns on every finding and exits 1 on any.
- `bin/devbin` (+4): exports the root variable's NAME as `DEVBIN_ROOT_VAR` beside its value. `lib/helpers`: `mktemp_beside`, adopted by `sed_inplace` (whose `mv` is now checked) and `generated_doc_write`; and `DEVBIN_ROOT_VAR` reserved in `assert_identifier`. SCOPE NOTE: all three reach past the notes providers.
- `bin/.devbin/cmd/release`: deleted. `bin/.devbin/config.yaml`: `commands.release.enabled: true`, `release.notes.kind: releases`, and `release.object: ci`, because release.yml makes the release object; the rest of D43 is WP-07's.
- `CHANGELOG.md`: regenerated; the one changed line is the caret-on-0.x clause (decision 33). `RELEASES.md` unchanged. `README.md`, `docs/configuration.md` (check's wording, the notes kinds, the command kind's root and environment, `DEVBIN_ROOT_VAR`), `intent/llm/MODULES.md` (one row), `lib/infra` (a comment).
- Tests. `release.bats` goes from 27 arms to 66. The 27 ported: 14 unchanged; 6 re-pointed at the core's words (the usage line, the N-of-M line, a bare word read as a cut's target with exit exactly 1, THIS REPOSITORY through devbin's own declaration); 3 `! grep` negations that could never fail, rewritten as if/fail (SC2314); 2 strengthened (the width arm counts its table lines first, since a view with no table passed it; the part-way render arm holds both views); and 2 comment-only. Plus 39 new, 60 of the 66 carrying `# AT-2.x`. `releasecore.bats`: WP-01's notes stubs flipped, and a comment above the argument loop saying its rows hold through their refusal text once WP-02 lands (measured, below). `helpers.bats` +3 and `gendoc.bats` +1 (modes). `review.bats`: R3's reserved-name arm is table-driven over DEVBIN_LIB and DEVBIN_ROOT_VAR.

**Changes from the generator it replaces, each deliberate and measured against it** (the generator at f34753f, with its own lib, on the same corpus)
1. The changelog header is built from `project.name` and states no project's semver rule (decision 33).
2. A `|` in a headline is escaped as `\|` in the index; the generator wrote it raw and split the row.
3. A tab in a headline is refused, naming the note; the generator rendered it with exit 0.
4. A `.md` under `RELEASES/` not named `X.Y.Z.md` is refused by name, a hidden one too; the generator read it as a note, and refused it only when its header happened to be bad.
5. Both views are rendered in memory before either is replaced; views and a dated note keep their file mode.

**Departures from D39's text:** dating does not regenerate the views (two writes, two postconditions; step 3 calls both, and WP-03 records step 3's postcondition as including `notes_views_check`). And `root` means a WHOLE tree, with a command provider's environment re-pointed at it (below).

**The command kind's root, in its environment.** The dispatcher exports the working tree's paths to every `run:`. So the command runs `cd -P` at the root, with devbin's own path exports re-pointed at it by NAME: PROJECT_ROOT, BIN_DIR, DEVBIN_DIR, DEVBIN_INVOKE=bin/devbin, and the root variable named by DEVBIN_ROOT_VAR. DEVBIN_LIB and DEVBIN_NAME stay; OLDPWD, which the cd sets to where the handler stood, is unset. Measured before the fix, a command asked about a copy root still saw the working tree in ENVPROBE_ROOT and OLDPWD, and invoked through a symlink, OLDPWD carried the link's spelling.

**Evidence, all on the final bytes**
- Parity, re-measured at 12:24Z on the committed bytes: devbin's own notes: RELEASES.md byte-identical (1155 bytes); CHANGELOG.md one line, the ruled clause; each rendering equals the view committed in its own tree. Edge corpus: CHANGELOG.md the ruled clause; RELEASES.md one row, the escaped pipe.
- `notes_body` == release.yml's own awk, read from the workflow file, byte for byte over every real note (0.1.0 11351 bytes, 0.1.1 30997, 0.1.2 8108); a one-byte control reads as different.
- changelog kind: `notes_body` == Utilz's 2.9.0 tag message below its subject line, byte for byte (7257 bytes), read-only.
- Mutants, each applied exactly once with its diff recorded, the restore cmp-proved, and the kill read from the arm's own message:
  - The prototype's 24, re-run: 22 killed; M09's anchor is gone and F12 is its exact mutation on today's `notes_date`; M14 re-anchored as M14f, killed.
  - The critic fold's F1 to F14: all killed.
  - Root and environment, 15, all killed. R1 to R4: releases state from PROJECT_ROOT, header and body from the cwd, listing from PROJECT_ROOT. C1 and C2: changelog state from PROJECT_ROOT, heading from the cwd. X1: paths not re-pointed. X2: no cd. E2: root variable not re-pointed. E3: DEVBIN_LIB re-pointed. E5: OLDPWD kept (red on OLDPWD=<link>). E6: no -P (red on PROJECT_ROOT when asked via a link). E8: bin/devbin's export removed. G1: a failed export not honoured. H1: the name not reserved.
  - D1, a mutant of the ARM, SURVIVED by design: E5's leak with the arm narrowed to the physical spelling and the link run, which is why the arm looks for both.
- WP-01's rows on top of WP-02 (f34753f + vc's fold + WP-02, git-free, 10:58Z-11:01Z): Na to Ne each still red. The `check --dry-run` row under Na now holds ONLY through its refusal text: `check` runs, exits 1 by itself on the fixture's unreadable version, and "printed no refusal line" is what fails it.
- Suites: targeted, release 66/66 and review 23/23. The full suite on f34753f + WP-02 before today's environment fold was 1306/1306, rc 0, 3 standing skips. Again on the folded tree: 1309/1309, rc 0, the 3 standing skips, no non-TAP line (11:07Z), before a comment-only addition to releasecore.bats, which then ran alone 22/22. At the sha: as above.

**For WP-03 (yours, agreed in thread):** root = the commit's whole tree, with the materialiser's limits living beside it in lib/release; step 3's postcondition includes `notes_views_check` with no STALE line; the caller owns the date `notes_check` compares.

**Residuals, declared**
- The command kind's `..` refusal is textual, not a symlink resolve.
- Dating a changelog heading adds a final newline to a CHANGELOG.md that lacks one.
- `release check` refuses an unknown `views_check` verdict; no kind can produce one today, so no arm reaches it.
- A DEVBIN_ROOT_VAR hand-set to a reserved name outside the dispatcher is not refused by the library, which trusts bin/devbin's validation.
- The shared tree's RELEASES.md was 0600 (the generator's mktemp) and was set to 644 at landing, and CHANGELOG.md came back 644 when the patch rewrote it; any other checkout that ran the old `release notes` has the same, and git records 100644 either way.
- Every `run:` word, `notes.run`'s included, is glob-expanded against the root: issue 0082 (`081be75`).
- `.bats` files carry five info-level shellcheck findings in release.bats and two in review.bats, all present before today; the gates exclude .bats by design.

**Lesson candidates (vc's call)**
- A kill at the fixture is not a kill at the assertion. R2 and R4 first went red at the arm's setup line, which ran outside the environment under test, not at the leak comparison. Read which message killed a mutant, not only that it went red.
- A leak check keyed on one spelling of a path passes the other: OLDPWD carried the symlink's spelling, and D1 shows the physical needle alone passing it.
- mktemp's 0600 survives rename-into-place, and git cannot see it (it records only the executable bit).
- A negation that is not a bats test's last command can never fail it (SC2314); three ported assertions had been green since they were written.
- A git exclude pathspec wins over an explicit include: `-- ':(exclude)intent' intent/llm/MODULES.md` silently drops MODULES.md. It showed up as a backup that "differed"; the other way round, it would have been a backup silently missing a file.
- A tool's limit stated from memory is a claim like any other: "LFS arrives as pointers" was mine, passed on and wrong, and vc measured the truth.
- An instance of the head/tail entry: `sed -n '1,30p'` over shellcheck hid a finding in my own new arm.
