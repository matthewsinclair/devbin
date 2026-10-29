devbin test bats [paths...]

The BATS unit suite, sealed. With no paths it runs everything under
`tests/unit/`, in two lanes where GNU parallel is installed (`bin/devbin help
test` says how, and how to set the number of jobs); with paths it runs exactly
those, in one.

  bin/devbin test bats
  bin/devbin test bats tests/unit/help.bats
  bin/devbin test bats tests/unit/help.bats tests/unit/dispatch.bats

Flags devbin does not recognise pass straight through to bats, which is what
makes `--filter` and friends work without devbin knowing they exist:

  bin/devbin test bats --filter 'help lists'

Three flags are the gate's rather than bats's, as at every sealed gate: `--purge` removes older run files from `tmp/test/` after the run, `--purge-only` does that without running anything, and `--allow-empty` declares that a run examining nothing is intended. A flag's value is never taken for a path, so `--filter tests` still runs the whole suite.

## The bats floor

The suite declares `bats_require_minimum_version 1.5.0` once, in
`tests/lib/test_helper.bash`. That is what `run !` needs -- the spelling for
"this command must fail, and the exact code belongs to the tool being run, not
to devbin". A missing `mix` exits 127, a gate propagates what it ran, and a bare
`run` would have bats warn that 127 usually means the test's own path is wrong.

## This topic exists to be found

`bin/devbin help test bats` resolves `bats` against `help/test.d/bats.md` by
exactly the rule `bin/devbin test bats` uses to resolve a sub-handler against
`cmd/test.d/bats` -- one rule at every depth. A word with no file
behind it stops the descent and the nearest enclosing topic answers, so
`help test nosuchthing` prints this file's parent rather than an error.
