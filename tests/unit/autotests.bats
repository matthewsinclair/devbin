#!/usr/bin/env bats
#
# check autotests -- one test target per crate.
#
# EVERY ARM HERE ASSERTS CONTENT, NEVER `$?` ALONE, and that is TN001's own
# trap rather than a house style: `cargo test <filter>` exits 0 when the filter
# matches nothing, so a first proof of the equivalent guard reported it green
# having run zero tests. Exit 0 over nothing is byte-identical to exit 0 over a
# pass. The arms below name the crate, the count, or the phrase.

load ../lib/test_helper

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# rustproj <name> -- a project declaring rust, with one crate at <root>/crate.
rustproj() {
  local proj
  proj="$(mkproj "${1:-rustdemo}" <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
EOF
)"
  mkdir -p "$proj/crate/tests"
  printf '[package]\nname = "crate"\nversion = "0.1.0"\n' >"$proj/crate/Cargo.toml"
  echo "$proj"
}

@test "RED ARM: two auto-discovered test files in one crate is a breach, named and counted" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  : >"$proj/crate/tests/beta.rs"

  run devbin_run "$proj" check autotests

  assert_failure
  assert_output_contains "2 auto-discovered test targets"
  assert_output_contains "crate"
  assert_output_contains "1 in breach"
}

@test "a symlinked tests/ is counted through the link, in both branches, never read as empty (0139)" {
  # The crate walk never enters a symlinked tests/, and each count's own find
  # read the link as itself, so two .rs files behind it read as "0 auto target"
  # at status 0. Each count follows the link (-H).
  local proj; proj="$(rustproj)"
  rmdir "$proj/crate/tests"
  mkdir -p "$proj/shared-tests"
  : >"$proj/shared-tests/alpha.rs"
  : >"$proj/shared-tests/beta.rs"
  mkdir -p "$proj/shared-tests/multi"
  : >"$proj/shared-tests/multi/main.rs"
  ln -s ../shared-tests "$proj/crate/tests"
  run devbin_run "$proj" check autotests
  assert_failure
  # Two files and a directory target, each read through the link.
  assert_output_contains "3 auto-discovered test targets"
  # And under autotests = false with nothing declared: the files behind the
  # link are compiled by nobody, and that is said.
  printf '[package]\nname = "crate"\nversion = "0.1.0"\nautotests = false\n' >"$proj/crate/Cargo.toml"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "NO [[test]] declared, but tests/ holds .rs files"
}

@test "a tests/ the count cannot read refuses a verdict, never counts 0 (0139)" {
  # An unreadable tests/ inside the project is refused by the crate walk, which
  # reads it on the way. One reached only through a link -- which the count
  # follows (-H) and the walk never does -- is the count's own to refuse, and
  # before 0139 v2 it counted 0 at status 0.
  local proj readable=0 elsewhere="$BATS_TEST_TMPDIR/elsewhere-tests"; proj="$(rustproj)"
  rmdir "$proj/crate/tests"
  mkdir -p "$elsewhere"
  : >"$elsewhere/alpha.rs"
  : >"$elsewhere/beta.rs"
  ln -s "$elsewhere" "$proj/crate/tests"
  # THE CONTROL: readable through the link, both files are counted.
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "2 auto-discovered test targets"
  chmod 000 "$elsewhere"
  [ ! -r "$elsewhere" ] || readable=1
  run devbin_run "$proj" check autotests
  chmod 755 "$elsewhere"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  assert_failure
  assert_output_contains "could not read $proj/crate/tests"
  assert_find_denied "crate/tests"
  refute_output_contains "auto target"
  refute_output_contains "auto-discovered test targets"
  # And in the other branch, under autotests = false with nothing declared,
  # whose count is a find of its own, which no arm drove before.
  printf '[package]\nname = "crate"\nversion = "0.1.0"\nautotests = false\n' >"$proj/crate/Cargo.toml"
  chmod 000 "$elsewhere"
  run devbin_run "$proj" check autotests
  chmod 755 "$elsewhere"
  assert_failure
  assert_output_contains "could not read $proj/crate/tests"
  assert_find_denied "crate/tests"
  refute_output_contains "declared (autotests = false"
  # And a tests/ whose undotted subdirectory cannot be searched: whether it
  # holds a main.rs, a target of its own, is unknown, so the count refuses a
  # verdict and names it.
  mkdir -p "$elsewhere/locked"
  chmod 000 "$elsewhere/locked"
  run devbin_run "$proj" check autotests
  chmod 755 "$elsewhere/locked"
  assert_failure
  assert_output_contains "could not read $proj/crate/tests whole: cannot search $proj/crate/tests/locked"
  refute_output_contains "declared (autotests = false"
}

@test "a dotted or search-only subdirectory of tests/ is counted as cargo counts it, not refused (0139)" {
  # Driven with cargo metadata: cargo never reads a dotted entry, and needs only
  # search of a subdirectory to find its main.rs. The count read both, and
  # refused a verdict over a tests/.cache at mode 000 and over a multi/ at 0111
  # holding a main.rs, where cargo counts. Inside the project the crate walk
  # reads both first and refuses on its own terms, so the tests/ here is reached
  # through a link, which the walk never follows and the count does.
  local proj readable=0 elsewhere="$BATS_TEST_TMPDIR/elsewhere-tests"; proj="$(rustproj)"
  rmdir "$proj/crate/tests"
  mkdir -p "$elsewhere/.cache" "$elsewhere/multi"
  : >"$elsewhere/alpha.rs"
  : >"$elsewhere/multi/main.rs"
  ln -s "$elsewhere" "$proj/crate/tests"
  chmod 000 "$elsewhere/.cache"
  chmod 0111 "$elsewhere/multi"
  [ ! -r "$elsewhere/.cache" ] || readable=1
  run devbin_run "$proj" check autotests
  chmod 755 "$elsewhere/.cache" "$elsewhere/multi"
  [ "$readable" = 0 ] || skip "running with permissions that read a mode-000 directory: the case was NOT checked"
  assert_failure
  refute_output_contains "could not read"
  assert_output_contains "2 auto-discovered test targets"
}

@test "a capitalised Main.rs is a directory target where the disk folds case, as cargo reads it (0139)" {
  # Driven with cargo metadata and cargo test --no-run on a case-insensitive
  # disk: cargo asks the filesystem whether multi/main.rs exists, so
  # tests/multi/Main.rs is a target, which a byte-exact -name main.rs never saw
  # -- "1 auto target" at rc 0 beside cargo's two, and a lone one under
  # autotests = false passed.
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/probe"
  [ -e "$proj/crate/tests/PROBE" ] ||
    skip "this filesystem is case-sensitive, where cargo does not read Main.rs as main.rs: the case-folding case was NOT checked"
  rm "$proj/crate/tests/probe"
  : >"$proj/crate/tests/alpha.rs"
  mkdir -p "$proj/crate/tests/multi"
  : >"$proj/crate/tests/multi/Main.rs"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "2 auto-discovered test targets"
  rm "$proj/crate/tests/alpha.rs"
  printf '[package]\nname = "crate"\nversion = "0.1.0"\nautotests = false\n' >"$proj/crate/Cargo.toml"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "NO [[test]] declared, but tests/ holds .rs files"
}

@test "the counts take a crate's test targets as cargo discovers them (0139)" {
  # Driven with cargo metadata (cargo 1.98.1): cargo takes every undotted .rs
  # entry directly in tests/, whatever it is but a directory -- a file, a link
  # to one, a link naming nothing, a link naming a directory -- and every
  # undotted subdirectory, not a link, holding a main.rs; not a dotted .rs, a
  # dotted directory, a directory with no main.rs, or a linked one. Five here:
  # alpha, beta, dirlink, gamma, multi.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/shared/linkeddir" "$proj/crate/tests/multi" "$proj/crate/tests/.dotdir" "$proj/crate/tests/moddir"
  : >"$proj/crate/tests/alpha.rs"
  : >"$proj/shared/beta.rs"
  ln -s ../../shared/beta.rs "$proj/crate/tests/beta.rs"
  ln -s ../../shared/nowhere.rs "$proj/crate/tests/gamma.rs"
  ln -s ../../shared/linkeddir "$proj/crate/tests/dirlink.rs"
  : >"$proj/crate/tests/.hidden.rs"
  : >"$proj/crate/tests/multi/main.rs"
  : >"$proj/crate/tests/.dotdir/main.rs"
  : >"$proj/crate/tests/moddir/common.rs"
  : >"$proj/shared/linkeddir/main.rs"
  ln -s ../../shared/linkeddir "$proj/crate/tests/linkedsub"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "5 auto-discovered test targets"
  # A subdirectory whose main.rs is a link naming nothing is no target, since
  # cargo asks whether main.rs exists through the link; one whose main.rs is a
  # directory is, for the same reason (each driven against cargo metadata).
  mkdir -p "$proj/crate/tests/dangle" "$proj/crate/tests/dirmain/main.rs"
  ln -s ../../../shared/nowhere.rs "$proj/crate/tests/dangle/main.rs"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "6 auto-discovered test targets"
  rm -r "$proj/crate/tests/dirmain"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "5 auto-discovered test targets"
  rm -r "$proj/crate/tests/dangle"
  # And under autotests = false with nothing declared: a tests/ whose one
  # target is a directory of several files holds a target nothing compiles.
  rm "$proj/crate/tests/alpha.rs" "$proj/crate/tests/beta.rs" "$proj/crate/tests/gamma.rs" \
    "$proj/crate/tests/dirlink.rs" "$proj/crate/tests/.hidden.rs"
  printf '[package]\nname = "crate"\nversion = "0.1.0"\nautotests = false\n' >"$proj/crate/Cargo.toml"
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "NO [[test]] declared, but tests/ holds .rs files"
}

@test "each crate's targets are counted apart, never carried into the next (0139)" {
  # Without this arm nothing holds the count's reset, so a crate's targets
  # carried into the next one's count would survive every arm.
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  mkdir -p "$proj/crate2/tests"
  printf '[package]\nname = "crate2"\nversion = "0.1.0"\n' >"$proj/crate2/Cargo.toml"
  : >"$proj/crate2/tests/beta.rs"
  local -a with_tests=("$proj"/*/tests)
  run devbin_run "$proj" check autotests
  assert_success
  assert_output_contains "${#with_tests[@]} crate(s) with tests/, 0 in breach"
  refute_output_contains "auto-discovered test targets"
}

@test "autotests = false is COMPLIANT however many files sit in tests/" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  : >"$proj/crate/tests/beta.rs"
  : >"$proj/crate/tests/gamma.rs"
  printf 'autotests = false\n\n[[test]]\nname = "suite"\npath = "tests/suite.rs"\n' \
    >>"$proj/crate/Cargo.toml"

  run devbin_run "$proj" check autotests

  assert_success
  assert_output_contains "declared (autotests = false, 1 target(s))"
  assert_output_contains "0 in breach"
}

# DECLARED BLOCKS PASS AT ANY COUNT, AND THE AUTHORING PROJECT IS WHY. This
# branch counts nothing, so `autotests = false` with ten [[test]] blocks passes
# while cargo reports ten targets -- a real divergence from the rule's name, and
# `> 1` was briefly a breach on the strength of it. Intent's own crates refuted
# that: intent-cli and intentd each declare TWO deliberately, because
# dual_path_conformance mutates process cwd and daemon_subscriptions drives a
# per-process watch stream. The rule polices SILENT GROWTH -- a file appearing
# and telling nobody -- not arithmetic. A [[test]] block is a deliberate line a
# reviewer sees.
@test "autotests = false passes at ANY declared count, and reports the count" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  local t
  local -a targets=(a b)
  {
    printf 'autotests = false\n'
    for t in "${targets[@]}"; do printf '\n[[test]]\nname = "%s"\npath = "tests/%s.rs"\n' "$t" "$t"; done
  } >>"$proj/crate/Cargo.toml"

  run devbin_run "$proj" check autotests

  assert_success
  assert_output_contains "${#targets[@]} target(s)"
  assert_output_contains "0 in breach"
}

# THE QUIET HOLE IN ITS LOUDEST FORM. Discovery off, nothing declared, and files
# sitting in tests/ -- compiled by nobody, run in no suite. They pass by not
# existing, which is the failure mode consolidation INVERTS rather than removes.
@test "autotests = false with NOTHING declared, but files in tests/, is a breach" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/orphan.rs"
  printf 'autotests = false\n' >>"$proj/crate/Cargo.toml"

  run devbin_run "$proj" check autotests

  assert_failure
  assert_output_contains "NO [[test]] declared"
  assert_output_contains "nothing compiles them"
}

# THE testkit CASE. A single test file with no autotests key is auto-discovered,
# so cargo reports ONE target while `grep -c '^\[\[test\]\]'` reports ZERO. TN001
# records a project reading the grep alone, concluding the crate needed
# consolidating, and consolidating something already correct. One target is what
# this gate passes, and this arm is what proves it does.
@test "one auto-discovered file is one target and PASSES -- the grep says zero and is wrong" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/only.rs"
  run grep -c '^\[\[test\]\]' "$proj/crate/Cargo.toml"
  [ "$output" = "0" ]

  run devbin_run "$proj" check autotests

  assert_success
  assert_output_contains "1 auto target"
  assert_output_contains "0 in breach"
}

@test "a crate walk over a directory it can list but not search refuses a verdict, never counts the crates it saw (0145)" {
  # macOS's find passed over a directory it could list but not search, mode
  # 0644, at rc 0: a crate beneath it, in breach, went uncounted, and the gate
  # passed over the one it saw.
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  mkdir -p "$proj/shut/other/tests"
  printf '[package]\nname = "other"\nversion = "0.1.0"\n' >"$proj/shut/other/Cargo.toml"
  : >"$proj/shut/other/tests/a.rs"
  : >"$proj/shut/other/tests/b.rs"
  # THE CONTROL: readable, the crate in breach beneath shut/ is found.
  run devbin_run "$proj" check autotests
  assert_failure
  assert_output_contains "1 in breach"
  chmod 644 "$proj/shut"
  if [ -x "$proj/shut" ]; then
    chmod 755 "$proj/shut"
    skip "running with permissions that search a mode-644 directory: NOT checked"
  fi
  run devbin_run "$proj" check autotests
  chmod 755 "$proj/shut"
  assert_failure
  assert_output_contains "cannot search $proj/shut -- nothing beneath it was looked at"
  assert_output_contains "check autotests: the crate walk FAILED"
}

@test "a git worktree is the SAME crate seen twice and must not be counted again" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/alpha.rs"
  : >"$proj/crate/tests/beta.rs"
  mkdir -p "$proj/.worktrees/n1/crate/tests"
  cp "$proj/crate/Cargo.toml" "$proj/.worktrees/n1/crate/Cargo.toml"
  : >"$proj/.worktrees/n1/crate/tests/alpha.rs"
  : >"$proj/.worktrees/n1/crate/tests/beta.rs"

  run devbin_run "$proj" check autotests

  assert_failure
  # ONE breach, not two. TN001 records a census reporting 14 crates where there
  # were 4 by walking worktree copies.
  assert_output_contains "1 crate(s) with tests/, 1 in breach"
  # The prune LIST is printed deliberately (see the frame arm below), so the
  # refutation names the worktree CRATE PATH -- what a breach line would carry
  # if the walk had descended into it -- rather than the bare directory name.
  refute_output_contains ".worktrees/n1/crate:"
}

@test "a rust project with no crates REPORTS that it found none, rather than passing quietly" {
  local proj
  proj="$(mkproj nocrates <<'EOF'
project:
  name: nocrates
  alias: nc
  languages:
    - rust
EOF
)"

  run devbin_run "$proj" check autotests

  assert_success
  assert_output_contains "no Cargo.toml found"
  assert_output_contains "nothing to check"
}

@test "the verdict names the corpus it examined and the frame it pruned" {
  local proj; proj="$(rustproj)"
  : >"$proj/crate/tests/only.rs"

  run devbin_run "$proj" check autotests

  assert_success
  assert_output_contains "pruned:"
  assert_output_contains ".worktrees"
}
