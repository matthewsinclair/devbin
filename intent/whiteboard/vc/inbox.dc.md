# inbox: dc -> vc

## (2026-11-12 05:34Z)

PLAN, issue 0339, on your brief (decision 160). Base: main at ca3da903, code at 329c2f33 (v0.1.22). Scratch clone ~/Devel/scratch/devbin-dc/i0339/tree. Nothing written beyond my pickup commit e5a68580; on your go I claim ISSUE:0339 first.

Shape:
1. bin/.devbin/cmd/.lib/bats-lanes moves to lib/bats-lanes by git mv, mode 755 kept, so every project gets it vendored at bin/.devbin/lib/bats-lanes. lanes_jobs, the GNU parallel probe, the count check and every line it prints are unchanged. One code change: its `cd "$PROJECT_ROOT"` goes, so it runs where it is called. Intent's runner unsets PROJECT_ROOT and would die there under set -u; both devbin callers already stand in the project root. Its header comment is rewritten for the new home, in project-neutral words.
2. Ask 1, devbin's own test: bin/.devbin/cmd/test hands its gate "$DEVBIN_LIB/bats-lanes" tests/unit, which in devbin's checkout is lib/bats-lanes.
3. Ask 1, the catalogue: lib/builtins's test.shell row goes from `bats tests` to `@builtin`, summary kept, and lib/cmd/test defines builtin_test_shell. Handed nothing (wrapper flags apart), it runs "$DEVBIN_LIB/bats-lanes" tests. Handed paths or bats flags, it runs `bats tests <args>`, exactly what the row ran before. The seal is unchanged (SHELL, shell grammar). A project whose config declares test.shell's run: (Intent) is untouched until it adopts.
4. Ask 2, the one call: `"$DEVBIN_LIB/bats-lanes" <dir>`. bin/devbin exports DEVBIN_LIB to everything it runs, so a runner started by an option's run: line has it, and every variable the runner exports reaches both lanes' bats. Intent's change is then one line, `"$DEVBIN_LIB/bats-lanes" "$SCRIPT_DIR/unit"` in place of its find | xargs -0 bats (all 91 of its suites are in tests/unit).
5. Ask 3: no code. Without GNU parallel the runner's first line already says so, with the brew and apt routes, and it runs one lane; through test shell that line is in the gate's output and seal, which is what a leg's log carries.

Files: lib/bats-lanes (moved), bin/.devbin/cmd/test, lib/builtins (the one row), lib/cmd/test, tests/unit/testhandler.bats, tests/unit/installhints.bats (its comment names lib/bats-lanes, whose hint the scan now reads). Two beyond your list, both so the record stays true: lib/pages/test.md, the shipped help page, whose table says shell runs `bats tests` (the row, and a short section on the lanes, the serial tag, the two settings and the call); and tests/unit/builtins.bats, where the two new arms sit beside the end-to-end gate arms and one arm's title, 'a built-in gate runs its catalogue command line and seals', is retitled, since test shell is no longer a command line. cc's bank (7d6d3c49) touches lib/cmd/release, lib/release.legs, lib/release.steps and releaselegs.bats, none of these. Tell me if 0335 to 0338 reach lib/pages/test.md or builtins.bats.

Arms:
- Changed, testhandler.bats: the two handler arms want "$DEVBIN_LIB/bats-lanes" tests/unit, and the eleven lanes arms run lib/bats-lanes. Red at the base: its handler hands the old path, and it has no lib/bats-lanes.
- New, builtins.bats: (a) test shell runs a shell project's tests/ in two lanes, the serial test in the serial lane and the count line whole (needs GNU parallel); (b) a project's own runner, with PROJECT_ROOT unset as Intent's is, exports a variable and calls "$DEVBIN_LIB/bats-lanes" tests/unit through a run: line, and a test in each lane reads the variable. Each is red at the base: no lanes line there, and no lib/bats-lanes.
- Green at the base by construction, run at the fix only, with their claims: builtins.bats 'every @builtin row in the catalogue has something implementing it' (test.shell is not @builtin at the base; at the fix it must find builtin_test_shell), and the three existing arms that run test shell and now go through the lanes: builtins.bats's retitled end-to-end arm and 'a failing built-in gate seals red with the right grammar', and dispatch.bats 'a CATALOGUE gate's --purge takes the same path as a declared one'.

Before the ask: the arms probed with probe-arms2.sh, the tree scans' patterns (neutral, workroom, contract's code-2 and cd scans, installhints) grepped over the added lines, and the kit sent for you to read. One light booking: the red leg at a red clone (base code, the unit's tests), then the green leg at the fix, BSD on rhadamanth, START on your grant. Then a bank by fetch and CAS to refs/bank/dc/0339, COMMIT_MSG-0339.txt sealed, and word to you; you land. Nothing pushed.

The note (your 05:3xZ message): RELEASES/0.1.23.md does not exist yet and every unit shares it, so 0339's entry comes to you as text with the handover, written for a consumer: from 0.1.23 a project on the default test shell runs its tests/ in two lanes, the untagged tests under bats --jobs and --filter-tags where GNU parallel is installed, so a test file that cannot share a host takes bats's serial tag (`# bats test_tags=serial` on the line before the test, or `# bats file_tags=serial` for the whole file), and DEVBIN_TEST_JOBS, else DEVBIN_JOBS, sets how many run at once. Anything else the as-built leaves a consumer to do comes to you before the bank.

Go?

---

_Generated by Intent v3 from the whiteboard model. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
