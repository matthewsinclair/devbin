devbin test bats [paths...] [bats flags...]
devbin test --failed
devbin test all

Run the Devbin suite. One option, because Devbin has one kind of test: BATS unit
files under `tests/unit/`, one file per concern.

  bin/devbin test bats            the whole suite
  bin/devbin test bats tests/unit/help.bats
  bin/devbin test all             the same thing, via the synthesised `all`
  bin/devbin test --failed        only the tests the last run failed

## The whole suite runs in two lanes

Handed nothing for bats, `test bats` and `test all` run the whole suite in two
lanes when GNU parallel is installed:

  1. every test not tagged `serial`, N at a time, under `bats --jobs N`;
  2. then the tests tagged `serial`, one at a time.

The run's first line names N and the GNU parallel it found. N is half the CPUs
and never fewer than two, so another project's run on the same machine keeps the
other half. `DEVBIN_TEST_JOBS` sets it:

  DEVBIN_TEST_JOBS=4 bin/devbin test all

The two lanes write one seal and give one verdict. The run fails when either
lane fails, and when the lanes did not run every test `bats --count` counts,
each exactly once; its last line says how many ran in each.

Without GNU parallel, or with `DEVBIN_TEST_JOBS=1`, the suite runs in one lane,
one test at a time, and the first line says why. A run handed paths or bats
flags is a targeted run: bats gets exactly what it was handed, in one lane, and
its own `--jobs` works there.

A test belongs in the serial lane when contention can eat its wall-clock
margins. Tag it on the line before it, and say why:

    # Waits out a 0.25 s heartbeat, which a loaded machine can delay.
    # bats test_tags=serial
    @test "a fractional interval beats ..." {

## Rerunning what failed

`test --failed` reruns only the tests the last bats run failed, as `mix test --failed` does. It reads the newest seal under `tmp/test/`, takes each failed test's name and file from it, and runs bats on those files with a `--filter` matching those names exactly. That run seals like any other, so the next `--failed` reruns what is still failing, and once it is green it says so and runs nothing. Then run the whole suite once more: `test all`.

## The verdict is a file

`test bats` is a SEALED gate: it writes `tmp/test/<stamp>.bats.out` and a
`.errors` companion beside it, and the companion is empty exactly when a
COMPLETED run was green. A gate that examines nothing and exits 0 is a false
green, which is the failure the seal exists to prevent -- so the `.errors`
companion starts as an in-flight marker and a run that never finished leaves
it there, never empty, and a completed run that executed no test is promoted
to failed.

Read the seal, not the scroll-back. Across a multi-option `all` the per-gate
verdict lines have scrolled away by the time the summary prints, which is why
`all` ends by naming the seal of every gate that failed.

## Writing tests

Every test runs in its own temp directory outside the checkout, and teardown
refuses to remove anything that is not one. Load the shared helper first:

    load "../lib/test_helper"

Three habits this suite learned the hard way, each from a test that passed for
the wrong reason:

- **Ask what ELSE would make this green.** One test asserted a refusal while the
  real tool was running and failing underneath it; the non-zero exit read as
  "devbin declined" when it meant "the thing devbin should not have run broke".
- **Do not borrow the shipping schedule.** A test that points at whichever
  built-in happens to be unimplemented needs rewriting every time one ships, and
  once the library is complete it gets deleted for the worst possible reason.
  Construct the condition instead -- remove the handler from the fixture.
- **The config cache is a shell variable.** `cfg_load` in a subshell reads as an
  absent config, silently. No `run cfg_load`, no piping into `cfg_load_string`.

## See also

  bin/devbin help check           the read-only gates
  bin/devbin check all            what CI runs, and what a commit should pass
