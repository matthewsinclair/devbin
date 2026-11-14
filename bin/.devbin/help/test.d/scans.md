    bin/devbin test scans

Run the tree scans alone: every test under `tests/unit/` tagged `treescan`. A tree scan is a test whose verdict is over a set of this tree's own files found by walking it (a glob, `find`, `git ls-files`, `git grep`, `grep -r`, the vendored set, the shipped list or the user docs), so a change anywhere in the tree can turn one red, whatever file the change was in. A fix runs its own tests and then these, before it lands.

It runs bats over `tests/unit` with `--filter-tags treescan`, one test at a time, and seals like any targeted run: `tmp/test/<stamp>.bats.{out,errors}`, which `test --failed` reads. It takes no paths and no bats flags. A suite with no tagged test is no clean scan: bats finds no test and the run fails.

`test all` does not run it. The tags change nothing for `test all`, which runs every tagged test in place, inside its own file, in whichever lane its file's tags put it.

Tag a new scan on the line before it, beside `serial` where it has both:

    # bats test_tags=treescan
    @test "no shipped line ..." {
