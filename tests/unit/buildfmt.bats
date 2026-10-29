#!/usr/bin/env bats
# buildfmt.bats - the Build and Format family (WP-15)
#
# Two commands that between them demonstrate the whole declarative boundary.
#
# `fmt` has defaults worth shipping, so devbin ships them. `build` deliberately
# has none -- the four corpus projects have four disjoint target lists (the
# catalogue's tier 4) -- so devbin ships the rig and the project supplies the
# targets. Proving `build` still works END TO END from declared targets alone
# is the positive half of that decision; AC-08.4 already holds the negative
# half.
#
# The asymmetry between `fmt` and `check format` is the other claim here.
# A missing formatter makes `fmt` skip and `check format` fail, and that is not
# an inconsistency: a gate that examines nothing and exits 0 is a false green
# because it asserts a verdict it never reached. `fmt` asserts none.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  init_colors off
}
teardown() { devbin_teardown; }


fakebin() {
  local proj="$1" name="$2"
  mkdir -p "$proj/fakebin"
  printf '#!/bin/sh\necho "ran:%s args=$*"\n' "$name" >"$proj/fakebin/$name"
  chmod +x "$proj/fakebin/$name"
  echo "$proj/fakebin"
}

# A PATH with the standard tools but deliberately none of the formatters.
# It must still carry a bash >= 5: under a bare /usr/bin:/bin, `env bash`
# resolves to /bin/bash 3.2 and the dispatcher's floor guard (issue 0022)
# refuses before the property under test is reached. One symlink in a private
# dir, nothing else, so the no-formatters premise holds.
barebones_path() {
  local d="$DEVBIN_TEST_TMPDIR/floor-bash"
  if [ ! -x "$d/bash" ]; then
    mkdir -p "$d"
    ln -s "$(command -v bash)" "$d/bash"
  fi
  echo "$d:/usr/bin:/bin"
}

# ============================================================================
# BUILD -- THE RIG WITHOUT THE TARGETS (AC-15.5)
# ============================================================================

@test "build works end to end from targets the project declares alone" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build the things
    options:
      cli:
        summary: The CLI
        run: echo built-cli
        log: CLI
      daemon:
        summary: The daemon
        run: echo built-daemon
        log: DAEMON
YAML
  )"
  run devbin_run "$proj" build cli
  assert_success
  assert_output_contains "built-cli"
  assert_output_contains "verdict:"
}

@test "build all runs the declared targets in declared order" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build the things
    options:
      cli:
        summary: The CLI
        run: echo built-cli
        log: CLI
      daemon:
        summary: The daemon
        run: echo built-daemon
        log: DAEMON
YAML
  )"
  run devbin_run "$proj" build all
  assert_success
  # Declared order, not alphabetical and not catalogue order -- the project
  # controls the sequence its `all` runs in.
  assert_output_matches 'built-cli(.|'$'\n'')*built-daemon'
}

@test "build lists its declared targets in help though devbin ships none" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  build:
    summary: Build the things
    options:
      cli:
        summary: The CLI
        run: echo built-cli
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  assert_output_contains "The CLI"
  assert_output_contains "every option above, one pass"
}

# ============================================================================
# FMT (AC-15.1, AC-15.2, AC-15.3)
# ============================================================================

@test "fmt runs a catalogued option through the shared gate body" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" fmt elixir
  assert_success
  assert_output_contains "ran:mix args=format"
  assert_output_contains "verdict:"
}

@test "fmt all is synthesised from the ACTIVE option set" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" npx >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" fmt all
  assert_success
  # elixir is declared so fmt.elixir is active; fmt.md is `any` so it always is.
  # fmt.rust and fmt.swift are NOT, because rust and swift are not declared.
  assert_output_contains "ran:mix args=format"
  refute_output_contains "cargo"
  refute_output_contains "swift-format"
}

@test "a missing formatter skips loudly rather than failing the run" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  # No swift-format anywhere on PATH. The run must succeed AND say what it
  # skipped -- silence would be indistinguishable from having formatted.
  PATH="$(barebones_path)" run devbin_run "$proj" fmt swift
  assert_success
  assert_output_contains "swift-format not found"
  assert_output_contains "skipping"
}

@test "fmt md formats root Markdown only, and says why" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  local bin
  bin="$(fakebin "$proj" npx)"
  printf '# hi\n' >"$proj/README.md"
  PATH="$bin:$PATH" run devbin_run "$proj" fmt md
  assert_success
  # The restraint is the feature: prettier strips table column alignment, and
  # intent/ and docs/ are exactly where the tables live.
  assert_output_contains "root Markdown only"
  assert_output_contains "table column alignment"
  assert_output_contains "README.md"
}

@test "fmt md formats explicit paths when given them" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  local bin
  bin="$(fakebin "$proj" npx)"
  mkdir -p "$proj/docs"
  printf '# doc\n' >"$proj/docs/guide.md"
  PATH="$bin:$PATH" run devbin_run "$proj" fmt md docs/guide.md
  assert_success
  assert_output_contains "docs/guide.md"
  # Named paths are deliberate, so the root-only warning does not apply.
  refute_output_contains "root Markdown only"
}

# ============================================================================
# THE FMT / CHECK FORMAT PAIRING -- AC-15.4, AC-15.6
# ============================================================================

@test "the formatting gate verifies EVERY arm the formatter applies" {
  # This test used to bind `check format` to `fmt elixir` alone and was called
  # "the gate and the formatter agree by construction". It was true of the arm
  # it checked and silent about the others, and reading it is what made the
  # gap look already policed: `fmt` formats several languages and `check format`
  # verified one (issue 0003).
  #
  # The relationship asserted now is coverage, not one command line: every fmt
  # arm with a language must have a check arm in the gate.
  local arm
  for arm in $(builtin_options_for fmt); do
    case "$arm" in all | md) continue ;; esac
    builtin_fmt_check_run "$arm" >/dev/null ||
      fail "fmt has an arm '$arm' that check format cannot verify -- the gate covers less than the formatter"
  done
}

@test "each check arm is the fmt arm it verifies, plus that tool's check flag" {
  # The per-arm form of the old assertion, kept because it is the thing that
  # actually drifts: someone edits `fmt rust` and the gate keeps checking the
  # old command line. Derived from the catalogue rather than restated, so there
  # is nothing to keep in step by hand.
  [ "$(builtin_fmt_check_run elixir)" = "$(builtin_option_run fmt elixir) --check-formatted" ]
  [ "$(builtin_fmt_check_run rust)" = "$(builtin_option_run fmt rust) --check" ]
}

@test "check format examines EVERY declared language, not just the first" {
  # The end-to-end form of the coverage claim. One consumer's shape: elixir + rust.
  # Before this, declaring both ran mix and never touched cargo -- and passed.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - rust
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" cargo >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "ran:mix args=format --check-formatted"
  assert_output_contains "ran:cargo args=fmt --check"
}

@test "check format offers nothing it was not asked for" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" cargo >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "ran:mix"
  # rust is not declared, so the rust arm must not run even though cargo exists.
  refute_output_contains "ran:cargo"
}

@test "a project with no formattable language says so and passes" {
  # Devbin itself is this case. A determinate fact about the project, not a run
  # that examined nothing it was asked to.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  run devbin_run "$proj" check format
  assert_success
  assert_output_contains "no formattable language declared"
}

@test "check format refuses to say 'nothing to check' when it was never told what to check" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # The dispatcher is the only thing that exports DEVBIN_LANGUAGES. Stripping it
  # is what a stray invocation looks like -- and the gate then reported "no
  # formattable language declared" and PASSED, for a project declaring elixir.
  #
  # That message is a claim about the PROJECT. Not knowing is a fact about the
  # INVOCATION. A gate that cannot tell them apart passes when it should fail,
  # and `builtin_check_critic` in lib/cmd/check already dies in exactly this
  # situation -- two adjacent gates giving opposite answers to one failure.
  run env -u DEVBIN_LANGUAGES \
    DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/check" format
  assert_failure
  refute_output_contains "no formattable language declared"
}

@test "the swift arm says how many files it examined, and does not pass in silence" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin
  bin="$(fakebin "$proj" swift-format)"
  # No .swift files anywhere. `find | xargs` runs nothing on macOS when the
  # input is empty, so the arm printed its step header and exited 0 having
  # examined nothing -- the doctrine's own target, in a gate written today.
  #
  # Zero files is a legitimate outcome and still passes, per the same reasoning
  # that lets "no formattable language" pass. What it may not do is be SILENT
  # about it: `doctor` reports how many checks ran for exactly this reason.
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "0 file"
}

@test "a disabled fmt arm is skipped by the gate, visibly" {
  # `enabled: false` is the project switching the arm OFF; the gate verifying
  # it anyway answered config with the catalogue.
  # The skip PASSES -- a determinate config fact -- but may not be silent.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - rust
commands:
  fmt:
    options:
      rust:
        enabled: false
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" cargo >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "ran:mix"
  assert_output_contains "rust -- fmt arm disabled in config"
  refute_output_contains "ran:cargo"
}

@test "an overridden fmt arm refuses to derive -- the fmt / check format pairing must not hold in name only" {
  # Config replaces what `fmt rust` runs; the catalogue-derived check would
  # verify a DIFFERENT command line and PASS doing it. No silent desync and no
  # check flag guessed onto a command devbin does not know: the gate stops and
  # names the key that states the check side.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
    - rust
commands:
  fmt:
    options:
      rust:
        run: cargo fmt --manifest-path native/Cargo.toml
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  fakebin "$proj" cargo >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_failure
  assert_output_contains "commands.check.options.format.run"
  refute_output_contains "ran:cargo args=fmt --check"
}

@test "check format refuses to derive a check for a language whose fmt the project owns, by a handler or a run: (0128)" {
  # Owning `fmt` whole is the overridden case, not the disabled one: `fmt rust`
  # runs the project's code, so the catalogue's check would verify a command
  # line nothing runs. Until 0128 a handler read `disabled` -- the gate passed,
  # saying the arm was disabled in config, which it was not -- and a command-level
  # `run:` read `builtin`, so the gate ran cargo's check for a formatter the
  # project had replaced.
  # Rust alone, because owning `fmt` whole overrides every language's arm and
  # the gate stops at the first; a second language would name itself instead.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - rust
commands:
  fmt:
    run: scripts/myfmt
YAML
  )"
  local bin
  bin="$(fakebin "$proj" cargo)"
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_failure
  assert_output_contains "cannot verify rust formatting -- 'fmt rust' runs the project's own formatter here"
  assert_output_contains "commands.check.options.format.run"
  refute_output_contains "fmt arm disabled in config"
  refute_output_contains "ran:cargo args=fmt --check"

  write_config "$proj" <<'YAML'
project:
  name: demo
  languages:
    - rust
YAML
  create_test_command "$proj" fmt >/dev/null
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_failure
  assert_output_contains "cannot verify rust formatting"
  refute_output_contains "fmt arm disabled in config"
}

@test "check format refuses arguments rather than silently dropping them" {
  # As a catalogue command line the arguments reached mix, so `check format
  # lib/foo.ex` scoped the check; as a builtin they vanished, and the same
  # invocation read as a scoped check that never happened.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  PATH="$bin:$PATH" run devbin_run "$proj" check format lib/foo.ex
  assert_failure
  assert_output_contains "takes no arguments"
  refute_output_contains "ran:mix"
}

@test "check toolchain refuses arguments too" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  printf 'elixir 1.18.0\n' >"$proj/.tool-versions"
  run devbin_run "$proj" check toolchain lib/foo.ex
  assert_failure
  assert_output_contains "takes no arguments"
}

# --- the Dockerfile arm (AC-11.11: promoted from two consumers' config
# scripts at WP-11 close). A deploy image restates the pins as literal ARG
# defaults -- FROM needs the value before any RUN could read a file -- so a
# bump to .tool-versions moves CI while leaving production on the old
# compiler, with every other gate green. One of them lagged that way twice.
#
# The stubs: a fake elixir prints the pinned version; a fake erl answers
# code:root_dir with a fixture root (whose releases/*/OTP_VERSION carries the
# full version) and system_info(otp_release) with the major.

toolchain_stub_bin() {
  # $1 = proj; prints the PATH prefix. Green live arms: 1.20.3 / 29.0.5.
  # This file's fakebin writes only the ran:-echo default, so the two stubs
  # are written directly: elixir prints the pinned version, erl answers
  # code:root_dir with the fixture root and otp_release with the major.
  local proj="$1"
  printf 'elixir 1.20.3-otp-29\nerlang 29.0.5\n' >"$proj/.tool-versions"
  mkdir -p "$proj/fakeroot/releases/29" "$proj/fakebin"
  printf '29.0.5\n' >"$proj/fakeroot/releases/29/OTP_VERSION"
  printf '#!/bin/sh\necho "Elixir 1.20.3 (compiled with Erlang/OTP 29)"\n' \
    >"$proj/fakebin/elixir"
  cat >"$proj/fakebin/erl" <<ERL
#!/bin/sh
case "\$*" in
  *root_dir*) printf '%s' '$proj/fakeroot' ;;
  *otp_release*) printf '29' ;;
esac
ERL
  chmod +x "$proj/fakebin/elixir" "$proj/fakebin/erl"
  echo "$proj/fakebin"
}

@test "check toolchain compares the Dockerfile ARGs when an image exists" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  printf 'ARG ELIXIR_VERSION=1.20.3\nARG OTP_VERSION=29.0.5\nFROM x\n' >"$proj/Dockerfile"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_success
  assert_output_contains "image"
}

@test "a Dockerfile lagging the pin is a red, not a footnote" {
  # The measured shape: pins moved, image stayed, every gate green.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  printf 'ARG ELIXIR_VERSION=1.20.1\nARG OTP_VERSION=29.0.5\nFROM x\n' >"$proj/Dockerfile"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_failure
  assert_output_contains "1.20.1"
}

@test "fly.toml with no Dockerfile fails: a comparison that cannot run is not a pass" {
  # Two consumers' authored strictness, derived from the repo instead of
  # config: a deploy marker with no image definition is a broken pipeline.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  printf 'app = "demo"\n' >"$proj/fly.toml"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_failure
  assert_output_contains "fly.toml"
}

@test "no Dockerfile and no fly.toml is informative, not a failure" {
  # Another consumer's shape: no deploy image exists, and that is a determinate fact
  # the gate reports (the two-shapes doctrine: informative, not vacuous).
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_success
  assert_output_contains "no deploy image"
}

@test "a Dockerfile whose ARGs cannot be read is a red, not a skip" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  printf 'FROM some-image:tag\n' >"$proj/Dockerfile"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_failure
  assert_output_contains "UNCHECKED"
}

# --- the gate usage line (issue 0007): the ACTIVE set, not the catalogue.
# One project's line advertised three arms that refuse; another's advertised four
# DISABLED arms and omitted ldn, the only one that runs. The dispatcher
# already derives the active set (command_options -- the list `all` fans over
# and help renders); the fix exports it per gate command and the usage line
# prints that, catalogue only as a fallback outside the dispatcher.

@test "a gate's bare usage line names the ACTIVE set, not the catalogue (issue 0007)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  fmt:
    options:
      md:
        enabled: false
      ldn:
        summary: The one real arm
        run: echo ran-ldn
YAML
  )"
  run devbin_run "$proj" fmt
  assert_failure
  assert_output_contains "ldn"
  refute_output_contains "rust"
  refute_output_contains "swift"
  refute_output_contains "md"
}

@test "the -h usage line is the same active set (issue 0007)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
commands:
  fmt:
    options:
      ldn:
        summary: The one real arm
        run: echo ran-ldn
YAML
  )"
  run devbin_run "$proj" fmt -h
  assert_success
  assert_output_contains "ldn"
  refute_output_contains "rust"
}

@test "check's usage drops arms whose language the project does not declare (issue 0007)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  run devbin_run "$proj" check
  assert_failure
  assert_output_contains "toolchain"
  refute_output_contains "clippy"
}

@test "the image comparison uses the FULL erlang pin even when the active one fell coarse" {
  # The strongest-copy nuance (one consumer's): the coarse fallback truncates the pin
  # for the ACTIVE comparison, but the image tag is exact -- 29.0.4 vs 29.0.5
  # is a different image and must be caught even when OTP_VERSION is
  # unreadable locally.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  rm -r "$proj/fakeroot/releases"
  printf 'ARG ELIXIR_VERSION=1.20.3\nARG OTP_VERSION=29.0.4\nFROM x\n' >"$proj/Dockerfile"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_failure
  assert_output_contains "29.0.4"
  assert_output_contains "COARSE"
}

# THE COARSE FALLBACK SAYS WHY (issue 0139). find's error went to /dev/null, so
# a releases/ it could not read fell back to the major with nothing to say it
# was unreadable rather than absent. An absent releases/ is not searched at
# all, so no find error stands in for that reason.
@test "an OTP_VERSION the lookup cannot read falls back coarse with find's error shown, and an absent releases/ with none (0139, 0145)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(toolchain_stub_bin "$proj")"
  # THE CONTROL: readable, the full version, and not coarse.
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_success
  refute_output_contains "COARSE"
  chmod 000 "$proj/fakeroot/releases"
  if [ -r "$proj/fakeroot/releases" ]; then
    chmod 755 "$proj/fakeroot/releases"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  chmod 755 "$proj/fakeroot/releases"
  assert_output_contains "COARSE"
  assert_find_denied "releases"
  # AND ONE BELOW IT THAT IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145):
  # coarse, with the reason on the line above it. The start point itself is
  # not the case: BSD find reports a start point it cannot search on its own,
  # and passes silently over one beneath it.
  chmod 644 "$proj/fakeroot/releases/29"
  if [ -x "$proj/fakeroot/releases/29" ]; then
    chmod 755 "$proj/fakeroot/releases/29"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  chmod 755 "$proj/fakeroot/releases/29"
  assert_output_contains "COARSE"
  assert_output_contains "cannot search $proj/fakeroot/releases/29 -- nothing beneath it was looked at"
  rm -r "$proj/fakeroot/releases"
  PATH="$bin:$PATH" run devbin_run "$proj" check toolchain
  assert_output_contains "COARSE"
  refute_output_contains "No such file"
}

@test "the gate needs the arm-state export too, not just the language list" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # DEVBIN_LANGUAGES present, DEVBIN_FMT_ARMS not: half an invocation. The
  # gate must not fall back to "the catalogue governs" -- that guess is the
  # overridden-arm and disabled-arm defects above, one layer down.
  #
  # `-u` because this suite itself runs under `devbin test all`, whose
  # dispatcher EXPORTS the variable: without stripping it, the invocation
  # inherits the outer project's arm state and the guard rightly stays quiet
  # -- green under bare bats, red under the gate. Same trap, same fix as the
  # sibling test above stripping DEVBIN_LANGUAGES.
  run env -u DEVBIN_FMT_ARMS DEVBIN_LANGUAGES=elixir \
    DEVBIN_LIB="$proj/bin/.devbin/lib" PROJECT_ROOT="$proj" DEVBIN_NAME=demo \
    "$proj/bin/.devbin/lib/cmd/check" format
  assert_failure
  assert_output_contains "DEVBIN_FMT_ARMS"
  refute_output_contains "no formattable language declared"
}

@test "the swift arm's file set is NUL-delimited end to end, like its twin" {
  # A path containing a newline was re-split by the tr bridge into two bogus
  # arguments and counted twice, so the twins disagreed about the file set the
  # whole fmt / check format pairing is about.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin
  bin="$(fakebin "$proj" swift-format)"
  printf '// swift\n' >"$proj/Thing.swift"
  printf '// swift\n' >"$proj/$(printf 'we\nird').swift"
  local -a made=("$proj"/*.swift)
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "${#made[@]} file(s)"
}

@test "the swift arm examines the files that are there" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin
  bin="$(fakebin "$proj" swift-format)"
  mkdir -p "$proj/Sources"
  printf 'let x = 1\n' >"$proj/Sources/A.swift"
  printf 'let y = 2\n' >"$proj/Sources/B.swift"
  local -a made=("$proj"/Sources/*.swift)
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "${#made[@]} file"
  assert_output_contains "ran:swift-format"
}

@test "the swift twins call swift-format the way swift-format is called" {
  # The fmt / check format pair asserted at the ARGUMENT level rather than at
  # "was it called".
  #
  # swift-format takes SUBCOMMANDS -- `lint`, and `format` as the default -- so
  # `--lint` is not a flag it has ever had. The gate shipped as
  # `swift-format --lint` and every test above it passed, because `fakebin`
  # accepts any argument at all. Proving the binary RAN is not proving it was
  # called CORRECTLY, and the file-set half of this pair had by then been
  # reviewed twice while the command line had never been executed once.
  #
  # It stayed invisible because devbin's own repository has no .swift files, so
  # the gate returned green on the determinate-zero path and never reached the
  # command. ST0002 WP-08 armed swift on a real project and it failed on the
  # first line. This fake refuses what the real tool refuses.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  mkdir -p "$proj/fakebin"
  cat >"$proj/fakebin/swift-format" <<'SH'
#!/bin/sh
case "$1" in
  lint) echo "ran:swift-format sub=lint" ;;
  format) echo "ran:swift-format sub=format" ;;
  *) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
esac
SH
  chmod +x "$proj/fakebin/swift-format"
  printf 'let x = 1\n' >"$proj/A.swift"

  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "ran:swift-format sub=lint"

  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" fmt swift
  assert_success
  assert_output_contains "ran:swift-format sub=format"
}

@test "the swift gate FAILS on findings instead of printing them and passing" {
  # `swift-format lint` exits 0 when it has findings. Only --strict promotes
  # them to errors. Without it the arm examines every file, prints every
  # finding, and seals GREEN -- the cardinal false green, and the gate would
  # have been incapable of ever going red.
  #
  # This is the trap the FIRST fix walked into. Correcting the subcommand took
  # the arm from an obvious hard error to a silent pass, which looks like
  # success and is worse. It was caught by reading the sealed .errors file --
  # empty -- against 633 findings on the terminal, which is the whole reason
  # the verdict is a file and not an exit code.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  mkdir -p "$proj/fakebin"
  cat >"$proj/fakebin/swift-format" <<'SH'
#!/bin/sh
strict=no
for a in "$@"; do
  [ "$a" = "--strict" ] && strict=yes
done
echo "A.swift:1:1: warning: [Indentation] indent by 2 spaces"
[ "$strict" = yes ] && exit 1
exit 0
SH
  chmod +x "$proj/fakebin/swift-format"
  printf 'let x = 1\n' >"$proj/A.swift"

  PATH="$proj/fakebin:$PATH" run devbin_run "$proj" check format
  assert_failure
  assert_output_contains "[Indentation]"
}

# A LISTING WITH A HOLE IN IT FAILS THE GATE (issue 0139). find's error reached
# the screen, and its status was lost in a process substitution, so a Swift
# file beneath a directory it could not read went unlinted and the gate passed.
@test "the swift gate fails when find cannot list every Swift file, and lints none of them (0139, 0145)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin tmpd="$DEVBIN_TEST_TMPDIR/tmpd"
  bin="$(fakebin "$proj" swift-format)"
  mkdir -p "$proj/locked" "$tmpd"
  printf 'let x = 1\n' >"$proj/A.swift"
  printf 'let y = 2\n' >"$proj/locked/B.swift"
  local -a made=("$proj"/*.swift "$proj"/locked/*.swift)
  # THE CONTROL: readable, every file is linted.
  PATH="$bin:$PATH" TMPDIR="$tmpd" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "${#made[@]} file(s)"
  chmod 000 "$proj/locked"
  if [ -r "$proj/locked" ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  PATH="$bin:$PATH" TMPDIR="$tmpd" run devbin_run "$proj" check format
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "could not list every Swift file"
  refute_output_contains "ran:swift-format"
  # find's own error names the directory, in any form find prints it.
  assert_find_denied "locked"
  # And nothing is left in TMPDIR, after the refusal as after the lint. The list
  # needs no file of its own (find_list), and a check bound to one name would
  # pass over any other file left behind.
  [ -z "$(ls -A "$tmpd")" ] || fail "a temporary file was left behind: $(ls -A "$tmpd")"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and the gate linted the one file it saw, green.
  chmod 644 "$proj/locked"
  if [ -x "$proj/locked" ]; then
    chmod 755 "$proj/locked"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  PATH="$bin:$PATH" TMPDIR="$tmpd" run devbin_run "$proj" check format
  chmod 755 "$proj/locked"
  assert_failure
  assert_output_contains "cannot search ./locked -- nothing beneath it was looked at"
  assert_output_contains "could not list every Swift file"
  refute_output_contains "ran:swift-format"
}

@test "an unreadable directory inside a build directory fails neither Swift twin: build directories are pruned, not walked (0139)" {
  # `-not -path` kept build/, .build/ and Carthage/ out of the list and walked
  # into them all the same, so a directory in one that could not be read failed
  # the gate -- and a build running beside it failed the walk in 2 of 20 runs.
  # Pruned, they are not entered at all.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin d
  bin="$(fakebin "$proj" swift-format)"
  printf 'let x = 1\n' >"$proj/A.swift"
  for d in build .build Carthage; do
    mkdir -p "$proj/$d/locked"
    printf 'let y = 2\n' >"$proj/$d/B.swift"
  done
  # THE CONTROL: readable, the build directories' files are not linted.
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  assert_success
  assert_output_contains "1 file(s)"
  for d in build .build Carthage; do chmod 000 "$proj/$d/locked"; done
  if [ -r "$proj/.build/locked" ]; then
    for d in build .build Carthage; do chmod 755 "$proj/$d/locked"; done
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  PATH="$bin:$PATH" run devbin_run "$proj" check format
  local cst="$status" cout="$output"
  PATH="$bin:$PATH" run devbin_run "$proj" fmt swift
  for d in build .build Carthage; do chmod 755 "$proj/$d/locked"; done
  [ "$cst" -eq 0 ] || fail "check format walked into a build directory: $cout"
  [[ "$cout" == *"1 file(s)"* ]] || fail "check format listed a build directory's file: $cout"
  [[ "$cout" != *"Permission denied"* ]] || fail "check format read inside a build directory: $cout"
  assert_success
  refute_output_contains "Permission denied"
  # fmt ran its formatter on the one file outside the build directories, so a
  # fmt that skipped cannot pass this half.
  assert_output_contains "ran:swift-format"
  assert_output_contains "A.swift"
  refute_output_contains "B.swift"
}

@test "fmt swift over a directory it can list but not search names it and fails, formatting what it saw (0145)" {
  # fmt's walk is the gate's twin: a verb that acts may act on what it found,
  # and says the walk was partial. macOS's find passed over a directory it could
  # list but not search, mode 0644, at rc 0, and fmt exited 0.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  local bin
  bin="$(fakebin "$proj" swift-format)"
  mkdir -p "$proj/shut"
  printf 'let x = 1\n' >"$proj/A.swift"
  printf 'let y = 2\n' >"$proj/shut/B.swift"
  chmod 644 "$proj/shut"
  if [ -x "$proj/shut" ]; then
    chmod 755 "$proj/shut"
    skip "running with permissions that search a mode-644 directory: NOT checked"
  fi
  PATH="$bin:$PATH" run devbin_run "$proj" fmt swift
  chmod 755 "$proj/shut"
  assert_failure
  assert_output_contains "cannot search ./shut -- nothing beneath it was looked at"
  assert_output_contains "A.swift"
}

@test "a missing formatter FAILS the gate, where fmt only skips" {
  # The fmt / check format asymmetry, asserted end to end. `fmt swift` skips and
  # exits 0 (asserted above); the gate cannot, because it asserts a verdict.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - swift
YAML
  )"
  PATH="$(barebones_path)" run devbin_run "$proj" check format
  assert_failure
  assert_output_contains "swift-format not found"
}

@test "markdown is deliberately NOT in the formatting gate" {
  # `fmt md` mutates root Markdown; `check format` must not assert a verdict on
  # it. prettier re-pads tables, and this project hand-aligns them -- measured,
  # not assumed: prettier --check fails on this repo's own README.md. A gate
  # that goes red on files the project deliberately keeps in a non-prettier
  # shape is a gate that is wrong on purpose.
  run builtin_fmt_check_run md
  assert_failure
}

@test "fmt --check does not exist: the gate is check format" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  local bin
  bin="$(fakebin "$proj" mix)"
  # Two consumers both grew `fmt --check`. It is not a devbin spelling: an
  # undeclared flag passes THROUGH to the tool rather than being interpreted,
  # so devbin never silently reinterprets it as a gate.
  PATH="$bin:$PATH" run devbin_run "$proj" fmt elixir --check
  assert_success
  assert_output_contains "ran:mix args=format --check"
}

@test "the formatting GATE does not skip when its tool is missing" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - elixir
YAML
  )"
  # The asymmetry with the skip test above, and the reason for it: `check
  # format` asserts a verdict, so it must go red rather than report a pass it
  # never established.
  #
  # `run !` rather than a bare `run`: the code that arrives here is the TOOL's,
  # and a missing tool exits 127. A gate propagates what it ran (AC-06.12), so
  # 127 is correct and must not be clamped to 1. Bare `run` makes bats warn that
  # 127 usually means the test's own command path is wrong -- true in general,
  # not here, where the missing `mix` IS the condition under test. `run !` says
  # "non-zero, deliberately" without pinning the number, which is what the AC
  # claims; `run -127` would over-specify it.
  PATH="$(barebones_path)" run ! devbin_run "$proj" check format
  assert_failure
  refute_output_contains "skipping"
}
