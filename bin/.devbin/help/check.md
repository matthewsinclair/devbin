bin/devbin check <syntax|lint|critic|format|toolchain|all>

The read-only gates. Nothing here mutates a file; each exits non-zero on a
breach and seals its verdict.

  syntax      bash -n over every shell file under bin/, lib/ and tests/: a
              bash or sh shebang, or .bash; .bats files excluded
  lint        shellcheck -x, following sourced libraries
  critic      intent critic shell -- the rules of the road, over the WHOLE corpus
  format      formatting is up to date, in every declared language
  toolchain   the .tool-versions pin matches what is running
  all         every gate above in one pass, without stopping at the first breach

syntax, lint and critic refuse a corpus they could not list whole: a directory `find` cannot read, named by its own error, or a file that cannot be read to tell whether it is a shell file. A gate over part of the corpus is not a pass (issue 0139).

`format` and `toolchain` come from the framework and are offered to any project.
They were once unreachable here: a handler at `bin/.devbin/cmd/check` stood at a
built-in name and so displaced the whole built-in option set, which is the
shadowing rule working exactly as designed. It was written two weeks before `lib/cmd/check`
existed and was never retired when the framework grew its own (issue 0018).

## Why `critic` reads everything here and reads what is staged elsewhere

`intent critic` scans nothing unless told what to scan, and the built-in
`check critic` tells it `--staged`. That is the right default for a pre-commit
gate and a vacuous one in CI, where nothing is ever staged.

Devbin is the framework's own source, so its gate reads every shell file it
ships. That divergence is DECLARED, in `bin/.devbin/config.yaml`, as a `run:`
line anybody can read -- not an emergent property of which tree you happen to be
standing in, which is what it was until 0018 was traced. The same command name
meant a corpus sweep here and a staged scan in every other project.

## Why `all` does not stop at the first failure

One pass that surfaces every breach beats N round trips. Each gate keeps its own
verdict; the summary at the end names which failed and points at each one's seal,
and it is a convenience rather than the record.

## check vs fmt

`check` asserts; `fmt` mutates. They are deliberately asymmetric when a tool is
missing:

  check format    FAILS -- a gate that examines nothing and exits 0 is a false
                  green, and reporting a pass it never established is the one
                  thing a gate must not do
  fmt swift       SKIP, loudly, when swift-format or Node is missing, and the
  fmt md          run passes -- a formatter that is not installed has not
                  found a problem. fmt elixir and fmt rust are their tools'
                  own command lines, and fail when mix or cargo is missing

That is why `fmt --check` does not exist. There is one formatting gate and it is
`check format`.

## Shellcheck

`lint` runs with `-x` so it follows `. "$DEVBIN_LIB/helpers"` into the library
rather than warning about it. Two traps this project keeps hitting:

- A comment line beginning with the word `shellcheck` is parsed as a DIRECTIVE,
  and SC1072/SC1073 then fire on ordinary prose. Reword the sentence.
- SC2154 fires on `status` and `output` in the test helper because bats assigns
  them invisibly. It is suppressed file-wide there, narrowly and with the reason
  written down -- excluding the whole test tree from analysis instead is how the
  reference project accumulated fifteen unseen findings.

## See also

  bin/devbin help test            the suite, and how its seals work
