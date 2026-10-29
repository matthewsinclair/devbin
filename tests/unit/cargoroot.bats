#!/usr/bin/env bats
#
# project.cargo_root -- the cargo workspace root, for a project whose Cargo
# workspace sits below its root (issue 0225).
#
# devbin ran every catalogue line at the project root, so such a project had no
# Cargo.toml where fmt rust, check format's rust arm, check clippy and test rust
# ran, and each carried an override of its own. The setting names the root;
# cargo_root (lib/helpers) is its one owner, and every arm here reads where
# cargo really ran, from a cargo that prints its own directory.

load ../lib/test_helper

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# nestedproj [extra config lines] -- a rust project whose workspace is native/,
# named by project.cargo_root, with no Cargo.toml at its root.
nestedproj() {
  local proj
  proj="$(mkproj rustdemo <<EOF
project:
  name: rustdemo
  cargo_root: native
  languages:
    - rust
${1:-}
EOF
)"
  mkdir -p "$proj/native"
  : >"$proj/native/Cargo.toml"
  echo "$proj"
}

# flatproj -- the same project with the setting absent.
flatproj() {
  mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  languages:
    - rust
EOF
}

# cargo_here -- a cargo that says where it ran, physically, and reports a
# passing test, so the cargo grammar sees a run that executed something.
cargo_here() {
  local dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  cat >"$dir/cargo" <<'EOF'
#!/bin/sh
n=1
for a in "$@"; do [ "$a" = --all-features ] && n=2; done
printf 'ran:cargo args=%s pwd=%s\n' "$*" "$(pwd -P)"
printf 'running %s tests\n' "$n"
printf 'test result: ok. %s passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n' "$n"
EOF
  chmod +x "$dir/cargo"
  printf '%s' "$dir"
}

physical() { (cd "$1" && pwd -P); }

# seal_at <seal> -- the `at:` line of a seal's invocation block, or nothing.
seal_at() { grep -E '^devbin\| +at: ' "$1" || true; }

@test "fmt rust, check clippy and test rust run at project.cargo_root, and each seal says so (0225)" {
  local proj bin native line out
  proj="$(nestedproj)"
  bin="$(cargo_here)"
  native="$(physical "$proj/native")"
  for line in "fmt rust:fmt/LATEST_FMTRS.out" "check clippy:check/LATEST_CLIPPY.out" "test rust:test/LATEST_RUST.out"; do
    # shellcheck disable=SC2086 # the command's words, split on purpose
    PATH="$bin:$PATH" run devbin_run "$proj" ${line%%:*}
    assert_success
    assert_output_contains "pwd=$native"
    out="$proj/tmp/${line#*:}"
    [ "$(seal_at "$out")" = "devbin|   at: $proj/native" ] || fail "${line%%:*}: at: line in $out is '$(seal_at "$out")'"
  done
}

@test "check format's rust arm runs at project.cargo_root, and says so (0225)" {
  local proj bin
  proj="$(nestedproj)"
  bin="$(cargo_here)"
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "args=fmt --check pwd=$(physical "$proj/native")"
  assert_output_line "at $proj/native"
}

@test "dormancy's legs run test rust's catalogue line at project.cargo_root (0225)" {
  local proj bin native
  proj="$(nestedproj)"
  bin="$(cargo_here)"
  native="$(physical "$proj/native")"
  PATH="$bin:$PATH" run devbin_run "$proj" dormancy
  assert_success
  assert_output_contains "args=test pwd=$native"
  assert_output_contains "args=test --all-features pwd=$native"
}

@test "with the setting absent every cargo line runs at the project root, and no seal has an at: line (0225)" {
  # DEVBIN_CARGO_ROOT inherited from another project's devbin is not this
  # project's setting: the dispatcher unsets it unless config declares one.
  local proj bin root line out
  proj="$(flatproj)"
  mkdir -p "$proj/native"
  : >"$proj/native/Cargo.toml"
  bin="$(cargo_here)"
  root="$(physical "$proj")"
  for line in "fmt rust:fmt/LATEST_FMTRS.out" "check clippy:check/LATEST_CLIPPY.out" "test rust:test/LATEST_RUST.out" "check format:check/LATEST_FORMAT.out"; do
    # shellcheck disable=SC2086 # the command's words, split on purpose
    DEVBIN_CARGO_ROOT=native PATH="$bin:$PATH" run devbin_run "$proj" ${line%%:*}
    assert_success
    assert_output_contains "pwd=$root"
    refute_output_contains "pwd=$root/native"
    out="$proj/tmp/${line#*:}"
    [ -f "$out" ] || fail "${line%%:*}: no seal at $out"
    [ -z "$(seal_at "$out")" ] || fail "${line%%:*}: $(seal_at "$out")"
  done
}

@test "a project's own run: for test rust runs at the project root, with project.cargo_root set (0225)" {
  local proj bin
  proj="$(nestedproj "commands:
  test:
    options:
      rust:
        run: cargo test --manifest-path native/Cargo.toml")"
  bin="$(cargo_here)"
  PATH="$bin:$PATH" run devbin_run "$proj" test rust
  assert_success
  assert_output_contains "args=test --manifest-path native/Cargo.toml pwd=$(physical "$proj")"
}

@test "check targetdir takes the shared tree to be project.cargo_root's target (0225)" {
  local proj
  proj="$(nestedproj)"
  CARGO_TARGET_DIR="$proj/native/target" run devbin_run "$proj" check targetdir
  assert_success
  assert_output_contains "points at the shared tree"
}

@test "doctor accepts a project.cargo_root naming a directory with a Cargo.toml (0225)" {
  local proj
  proj="$(nestedproj)"
  run devbin_run "$proj" doctor
  refute_output_contains "project.cargo_root"
}

@test "a project.cargo_root with no Cargo.toml is refused by doctor and by test rust, naming the path, and cargo never runs (0225)" {
  local proj bin
  proj="$(nestedproj)"
  rm "$proj/native/Cargo.toml"
  bin="$(cargo_here)"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "project.cargo_root: \"native\" names $proj/native, which holds no Cargo.toml"
  PATH="$bin:$PATH" run devbin_run "$proj" test rust
  assert_failure
  assert_output_contains "project.cargo_root 'native' names $proj/native, which holds no Cargo.toml"
  refute_output_contains "ran:cargo"
}
