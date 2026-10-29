#!/usr/bin/env bats
# dormancy.bats -- the `dormancy` verb: how many tests this project does NOT run
#
# WHAT IS UNDER TEST, and it is not "does it print a number". Every arm here is
# about the verb REFUSING to produce a number it has not earned. The delta is
# arithmetic and arithmetic always succeeds; the value of the verb is entirely
# in the states where it declines to do the subtraction:
#
#   - a declared invocation that is not a cargo line  -- no maximum exists
#   - a declared invocation already at the maximum    -- delta zero by construction
#   - a leg that did not reach a test binary          -- no count, not a zero
#   - a leg that ran RED                              -- a different suite, not a smaller one
#
# A verb that reported `0 dormant` in any of those would be making a confident
# false statement out of an honest subtraction.
#
# THE CARGO STUB IS THE WHOLE FIXTURE and its output shape is the contract:
# `test result: ok. N passed; 0 failed;` is what the cargo counter in lib/runlog
# reads. Nothing here runs real cargo, and the arm "the suite DECLARES that no
# arm of it ran real cargo" says so rather than leaving it to be inferred from
# the absence of one.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

rustproj() {
  mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
YAML
}

# A cargo that reports <declared> tests bare and <max> tests under
# --all-features, in the exact trailer shape the counter reads.
cargo_counting() {
  local declared="$1" max="$2" rc="${3:-0}" dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  cat >"$dir/cargo" <<EOF
#!/usr/bin/env bash
n=$declared
for a in "\$@"; do [ "\$a" = --all-features ] && n=$max; done
printf 'running %s tests\n' "\$n"
printf 'test result: ok. %s passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n' "\$n"
exit $rc
EOF
  chmod +x "$dir/cargo"
  printf '%s' "$dir"
}

rundorm() {
  local proj="$1" bin="$2"
  shift 2
  run env PATH="$bin:$PATH" bash -c "cd '$proj' && ./bin/devbin dormancy $*"
}

# ============================================================================
# THE MEASUREMENT
# ============================================================================

@test "a project with dormant tests reports the DELTA, not the totals alone" {
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "declared  12 test(s)"
  assert_output_contains "maximum   19 test(s)"
  assert_output_contains "DORMANT: 7 test(s) run ONLY under --all-features"
}

@test "a leg whose output holds a latin1 byte is still counted under a UTF-8 locale (0231)" {
  # Under a UTF-8 locale macOS awk exited 2 at the byte, and the swallowed
  # failure read as a leg that reached no test binary.
  loc="$(utf8_locale)" || skip "no UTF-8 locale on this runner: the latin1 byte was NOT read under one"
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  mv "$bin/cargo" "$bin/cargo-counting"
  printf '#!/usr/bin/env bash\nprintf '"'"'caf\\351, from a test\\n'"'"'\nexec "%s" "$@"\n' "$bin/cargo-counting" >"$bin/cargo"
  chmod +x "$bin/cargo"
  export LC_ALL="$loc"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "declared  12 test(s)"
  assert_output_contains "maximum   19 test(s)"
}

@test "a DETERMINATE ZERO is reported as measured, never as silence" {
  # "Nothing found" and "nothing to find" print identically unless one of them
  # says so. This project has already been bitten by that shape twice.
  proj="$(rustproj)"
  bin="$(cargo_counting 12 12)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "NO DORMANCY: both invocations execute the same 12 test(s)"
  assert_output_contains "determinate zero"
  refute_output_contains "DORMANT:"
}

@test "a SMALLER maximum is not negative dormancy -- it is a different suite" {
  # A feature that REPLACES an implementation does this. Reporting `-3 dormant`
  # would be arithmetic standing in for a finding.
  proj="$(rustproj)"
  bin="$(cargo_counting 19 12)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "NOT NESTED"
  assert_output_contains "7 FEWER"
  refute_output_contains "DORMANT:"
}

# ============================================================================
# THE REFUSALS -- the whole value of the verb
# ============================================================================

@test "a RED leg is INCONCLUSIVE, not a delta between two suites" {
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19 101)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "DORMANCY INCONCLUSIVE"
  refute_output_contains "DORMANT:"
  refute_output_contains "NO DORMANCY"
}

@test "a leg that reached NO test binary is INCONCLUSIVE, never zero" {
  # The direction that matters: a feature that does not compile produces a leg
  # with no `test result:` trailer at all. Calling that zero would report the
  # entire suite as dormant -- a maximally alarming number from a build error.
  proj="$(rustproj)"
  dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  cat >"$dir/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = --all-features ]; then
    echo "error[E0432]: unresolved import" >&2
    exit 101
  fi
done
printf 'running 12 tests\n'
printf 'test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n'
EOF
  chmod +x "$dir/cargo"
  rundorm "$proj" "$dir"
  assert_failure
  assert_output_contains "DORMANCY INCONCLUSIVE"
  assert_output_contains "no test trailer at all"
  refute_output_contains "DORMANT:"
}

@test "a declared invocation ALREADY at the maximum says so and measures nothing" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        summary: Cargo suites
        log: rust
        grammar: cargo
        run: cargo test --all-features
YAML
  )"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "ALREADY passes --all-features"
  assert_output_contains "BY CONSTRUCTION"
  refute_output_contains "DORMANT:"
}

@test "a declared invocation that is NOT cargo is an UNDEFINED comparison, and refuses" {
  # Appending --all-features to a project's own script produces a command
  # nobody wrote. The delta against it would be a number about an invocation
  # that does not exist, which is worse than no number because it is a number.
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        summary: Cargo suites
        log: rust
        grammar: cargo
        run: ./scripts/run-tests.sh
YAML
  )"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "not a cargo test line"
  assert_output_contains "the comparison is simply undefined"
  refute_output_contains "DORMANT:"
}

@test "a project that does not declare rust never reaches the verb at all" {
  # LANGUAGE SCOPING REFUSES FIRST, and the assertion says so rather than pinning
  # the handler's own message -- which is unreachable through dispatch. A test
  # asserting the handler's wording here would be green over a branch the
  # dispatcher makes unreachable, which is the shape this project keeps finding.
  proj="$(mkproj shelldemo <<'YAML'
project:
  name: shelldemo
  languages:
    - shell
YAML
  )"
  run env bash -c "cd '$proj' && ./bin/devbin dormancy"
  assert_failure
  assert_output_contains "is not available here"
  assert_output_contains "does not declare the 'rust' language"
}

@test "the handler's OWN language guard still refuses a direct invocation" {
  # The branch above is unreachable through dispatch and is not dead: the
  # handler is executable on its own path, and a verb that ran two cargo builds
  # in a project with no cargo would be a worse answer than a refusal.
  proj="$(mkproj shelldemo2 <<'YAML'
project:
  name: shelldemo2
  languages:
    - shell
YAML
  )"
  run env DEVBIN_LIB="$proj/bin/.devbin/lib" DEVBIN_DIR="$proj/bin/.devbin" \
    PROJECT_ROOT="$proj" DEVBIN_NAME=shelldemo2 DEVBIN_LANGUAGES="shell" \
    "$proj/bin/.devbin/lib/cmd/dormancy"
  assert_failure
  assert_output_contains "does not declare rust"
}

@test "an unknown argument REFUSES rather than being ignored" {
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin" --force
  assert_failure
  assert_output_contains "unknown argument"
}

# ============================================================================
# 0135: A ZERO IS A COUNT, THE FLAG GOES WHERE CARGO READS IT, AND THE LINE
# PRINTED IS THE LINE THAT RUNS
# ============================================================================

# cargo_logging <declared> <max> -- cargo_counting, logging each run's argv to
# cargo.log beside the stub, so an arm can say cargo never ran.
cargo_logging() {
  local declared="$1" max="$2" dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  cat >"$dir/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$dir/cargo.log"
n=$declared
for a in "\$@"; do [ "\$a" = --all-features ] && n=$max; done
printf 'test result: ok. %s passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n' "\$n"
EOF
  chmod +x "$dir/cargo"
  printf '%s' "$dir"
}

@test "a suite wholly behind features is DORMANT, counted, not INCONCLUSIVE (0135)" {
  # The case the verb exists to find. The legs ran `test rust`, a gate, which
  # promotes a run that executed nothing to FAILED, so the declared leg exited
  # 1 and dormancy read INCONCLUSIVE. A measurement counts a zero.
  proj="$(rustproj)"
  bin="$(cargo_counting 0 4)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "declared  0 test(s)"
  assert_output_contains "maximum   4 test(s)"
  assert_output_contains "DORMANT: 4 test(s) run ONLY under --all-features"
  refute_output_contains "INCONCLUSIVE"
  refute_output_contains "PROMOTED TO FAILED"
}

@test "--all-features goes before a --, where cargo reads it (0135)" {
  # Appended to `cargo test -- --test-threads=1`, the flag went to the test
  # binaries, which reject it as libtest does, and the leg had no trailer.
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test -- --test-threads=1
YAML
)"
  dir="$BATS_TEST_TMPDIR/cargobin"
  mkdir -p "$dir"
  cat >"$dir/cargo" <<'EOF'
#!/usr/bin/env bash
n=3 seen=0
for a in "$@"; do
  [ "$a" = -- ] && seen=1
  if [ "$a" = --all-features ]; then
    if [ "$seen" = 1 ]; then echo "error: Unrecognized option: 'all-features'" >&2; exit 101; fi
    n=5
  fi
done
printf 'test result: ok. %s passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n' "$n"
EOF
  chmod +x "$dir/cargo"
  rundorm "$proj" "$dir"
  assert_success
  assert_output_contains "maximum   cargo test --all-features -- --test-threads=1"
  assert_output_contains "DORMANT: 2 test(s) run ONLY under --all-features"
}

@test "a test handler of the project's own is refused before either leg, and no cargo runs (0135)" {
  # dormancy printed `cargo test` and the handler ran both legs.
  proj="$(rustproj)"
  create_test_command "$proj" test '#!/usr/bin/env bash
printf "HANDLER-RAN %s\n" "$*"' >/dev/null
  bin="$(cargo_logging 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: a test handler of this project's own runs 'test rust'"
  refute_output_contains "HANDLER-RAN"
  refute_output_contains "--- leg"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran:
$(cat "$bin/cargo.log")"
}

@test "test rust switched off is refused before either leg, in option_unavailable_reason's words (0135)" {
  # shell is declared too, so test stays active with its rust option off: the
  # option's own reason, where test off as a whole is named as test (below).
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
    - shell
commands:
  test:
    options:
      rust:
        enabled: false
YAML
)"
  bin="$(cargo_logging 12 19)"
  local why
  why="$(fixture_ask "$proj" option_unavailable_reason test rust)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: 'test rust' does not run here: $why"
  refute_output_contains "not available here"
  refute_output_contains "--- leg"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "a declared rust line with no words is refused, naming the key, not read as undeclared (0135)" {
  # `[ -n ]` read `run: ""` as undeclared and printed the catalogue's line;
  # 0082's rule is cfg_has.
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: ""
YAML
)"
  bin="$(cargo_logging 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "commands.test.options.rust.run holds no words"
  refute_output_contains "declared  cargo test"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "a command-level test run: is refused as not a cargo test line of test rust's own (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    run: cargo test
YAML
)"
  bin="$(cargo_logging 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: commands.test.run runs 'test rust'"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "test rust whose devbin handler is missing from the install is refused before either leg, in unrunnable_why's words (0135)" {
  proj="$(rustproj)"
  rm "$proj/bin/.devbin/lib/cmd/test"
  bin="$(cargo_logging 12 19)"
  local why
  why="$(fixture_ask "$proj" unrunnable_why test rust)"
  [ -n "$why" ] || fail "the reason is empty -- the check below would be vacuous"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: 'test rust' does not run here: $why"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
  # The dispatcher refuses test rust here too, and runs nothing. Its words are
  # not asserted: it prints only its usage line for this case, which 0135's
  # message states is left unchanged.
  run env PATH="$bin:$PATH" bash -c "cd '$proj' && ./bin/devbin test rust"
  assert_failure
  [ ! -e "$bin/cargo.log" ] || fail "the dispatcher ran cargo"
  [ -z "$(find "$proj/tmp/test" -name '*.RUST.out' 2>/dev/null)" ] || fail "the dispatcher sealed a leg"
}

@test "each leg carries a run id of its own, never an inherited parent's (0135)" {
  # The legs ran as child devbins, which cross bin/devbin's witness boundary
  # and mint an id; run in dormancy's own process they kept a parent's, and a
  # parent `all` named a leg's seal as one of its failed gates.
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  run env DEVBIN_RUN_ID=deadbeef DEVBIN_RUN_WITNESS=0 PATH="$bin:$PATH" bash -c "cd '$proj' && ./bin/devbin dormancy"
  assert_success
  local ids n
  ids="$(sed -n 's/^devbin| *run: //p' "$proj"/tmp/test/*.RUST.out | sort -u)"
  n="$(printf '%s\n' "$ids" | grep -c .)" || n=0
  [ "$n" -eq 2 ] || fail "expected two leg ids, got $n: $ids"
  ! grep -qx deadbeef <<<"$ids" || fail "a leg carries the parent's id: $ids"
  # AND EACH IS MINTED BY ITS OWN PROCESS: the first four hex digits are the
  # minting pid's ($BASHPID). Two ids that differ only in the clock's half
  # would pass the count above whenever the legs straddled a second, which is
  # how a mint reading dormancy's own $$ survived one batch and not another.
  n="$(printf '%s\n' "$ids" | cut -c1-4 | sort -u | grep -c .)" || n=0
  [ "$n" -eq 2 ] || fail "the two leg ids share their pid half, so one process minted both: $ids"
}

@test "each leg's seal says what it ran: the declared line as split, and only the maximum with --all-features (0135)" {
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  local dec max
  dec="$(grep -h "from: dormancy's declared leg" "$proj"/tmp/test/*.RUST.out)" || fail "no declared leg's source line"
  max="$(grep -h "from: dormancy's maximum leg" "$proj"/tmp/test/*.RUST.out)" || fail "no maximum leg's source line"
  [[ "$dec" == *"split into words by run_words"* ]] || fail "the declared leg does not say how it was split: $dec"
  [[ "$dec" != *"--all-features"* ]] || fail "the declared leg claims --all-features: $dec"
  [[ "$max" == *"with --all-features placed where cargo reads it"* ]] || fail "the maximum leg does not say where the flag went: $max"
}

@test "test switched off as a command is refused naming test, as the dispatcher does (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    enabled: false
YAML
)"
  bin="$(cargo_logging 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: 'bin/devbin test' is not available here: it is disabled in bin/.devbin/config.yaml"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "--all-features after -- is not the maximum: only the words cargo reads count (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test -- --all-features
YAML
)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  refute_output_contains "ALREADY passes --all-features"
  assert_output_contains "maximum   cargo test --all-features -- --all-features"
}

@test "a config line is printed with its key as its source (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test
YAML
)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "declared  cargo test    (commands.test.options.rust.run in bin/.devbin/config.yaml)"
}

@test "the declared line's words are matched at the project root, wherever dormancy is run from (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test --manifest-path Cargo.to?l
YAML
)"
  : >"$proj/Cargo.toml"
  mkdir -p "$proj/sub"
  bin="$(cargo_logging 12 19)"
  run env PATH="$bin:$PATH" bash -c "cd '$proj/sub' && ../bin/devbin dormancy"
  assert_success
  grep -q -- '--manifest-path Cargo.toml' "$bin/cargo.log" ||
    fail "the glob was not matched at the root: $(cat "$bin/cargo.log")"
}

@test "a project declaring rust and another language is measured, never told it does not declare rust (0135)" {
  # The dispatcher exports the languages one a line, and dormancy's own guard
  # read them between spaces, so rust beside shell was refused as undeclared.
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - shell
    - rust
YAML
)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  refute_output_contains "does not declare rust"
  assert_output_contains "DORMANT: 7 test(s) run ONLY under --all-features"
}

@test "a test.rust line of its own seals the legs with its own log: and grammar:, as test rust is (0135)" {
  # option_seal is the one statement of the seal: a fixed RUST and cargo
  # sealed dormancy's legs apart from `test rust` wherever config said
  # otherwise. The grammar here is one run_gate does not know, so its warning
  # is how the arm sees the legs carry it.
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test
        log: rustunit
        grammar: bespoke
YAML
)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  local n
  n="$(find "$proj/tmp/test" -name '*.rustunit.out' | grep -c .)" || n=0
  [ "$n" -eq 2 ] || fail "expected both legs sealed as rustunit, found $n: $(ls "$proj/tmp/test")"
  [ -z "$(find "$proj/tmp/test" -name '*.RUST.out')" ] || fail "a leg was sealed as RUST: $(ls "$proj/tmp/test")"
  n="$(printf '%s\n' "$output" | grep -c "unknown grammar 'bespoke'")" || n=0
  [ "$n" -eq 2 ] || fail "expected both legs read in the declared grammar, saw $n:
$output"
}

@test "a catalogue test rust keeps RUST and cargo whatever a dead log: in config says, as test rust does (0135)" {
  # With no run: of its own, test rust is the catalogue's, and config's log:
  # and grammar: beside no run: are read by nothing (0133).
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        log: rustunit
        grammar: bespoke
YAML
)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  local n
  n="$(find "$proj/tmp/test" -name '*.RUST.out' | grep -c .)" || n=0
  [ "$n" -eq 2 ] || fail "expected both legs sealed as RUST, found $n: $(ls "$proj/tmp/test")"
  refute_output_contains "unknown grammar"
}

@test "a test.rust line declared unsealed is refused before either leg, naming the key (0135)" {
  proj="$(mkproj rustdemo <<'YAML'
project:
  name: rustdemo
  languages:
    - rust
commands:
  test:
    options:
      rust:
        run: cargo test
        log: "-"
YAML
)"
  bin="$(cargo_logging 12 19)"
  rundorm "$proj" "$bin"
  assert_failure
  assert_output_contains "dormancy: commands.test.options.rust.log declares 'test rust' unsealed, and dormancy seals each leg as test rust is sealed -- no leg was run"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "a direct invocation with no language list is refused by the guard, never a crash on an unset variable (0135)" {
  # The guard exists for a direct invocation, and under set -u the newline fix
  # read DEVBIN_LANGUAGES with no default, so it died "unbound variable".
  proj="$(rustproj)"
  run env -u DEVBIN_LANGUAGES DEVBIN_LIB="$proj/bin/.devbin/lib" DEVBIN_DIR="$proj/bin/.devbin" \
    PROJECT_ROOT="$proj" DEVBIN_NAME=rustdemo "$proj/bin/.devbin/lib/cmd/dormancy"
  assert_failure
  assert_output_contains "does not declare rust"
  refute_output_contains "unbound variable"
}

@test "inside a witness run the legs keep that run's id, as a child of one does (0135)" {
  # The other half of bin/devbin's boundary: a witness run's children are part
  # of it, so a leg minted apart would drop out of that run's own ledger.
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  run env DEVBIN_RUN_ID=deadbeef DEVBIN_RUN_WITNESS=1 RUNLOG_WITNESS_RUN=1 PATH="$bin:$PATH" \
    bash -c "cd '$proj' && ./bin/devbin dormancy"
  assert_success
  local ids
  ids="$(sed -n 's/^devbin| *run: //p' "$proj"/tmp/test/*.RUST.out | sort -u)"
  [ "$ids" = deadbeef ] || fail "the legs left the witness run: $ids"
}

@test "a config that will not load is refused by name before either leg, never blamed on project.languages (0135)" {
  # _dormancy_load_config swallowed a failed load and returned 0: the empty
  # cache made option_leaf answer inactive, and dormancy refused blaming
  # project.languages, when the config was what could not be read. The message
  # assertions are what redden this against that code, not the cargo.log check.
  # Run directly: through the dispatcher bin/devbin loads the same file first
  # and stops.
  proj="$(rustproj)"
  printf 'project:\n\tname: tab\n' >"$proj/bin/.devbin/config.yaml"
  bin="$(cargo_logging 12 19)"
  run env PATH="$bin:$PATH" DEVBIN_LIB="$proj/bin/.devbin/lib" DEVBIN_DIR="$proj/bin/.devbin" \
    PROJECT_ROOT="$proj" DEVBIN_NAME=rustdemo DEVBIN_LANGUAGES=rust "$proj/bin/.devbin/lib/cmd/dormancy"
  assert_failure
  assert_output_contains "tabs are not permitted"
  assert_output_contains "dormancy: could not load bin/.devbin/config.yaml (the error above says why) -- nothing was measured"
  refute_output_contains "--- leg"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "no config at all is refused as the dispatcher refuses it, never blamed on project.languages (0135)" {
  proj="$(rustproj)"
  rm "$proj/bin/.devbin/config.yaml"
  bin="$(cargo_logging 12 19)"
  run env PATH="$bin:$PATH" DEVBIN_LIB="$proj/bin/.devbin/lib" DEVBIN_DIR="$proj/bin/.devbin" \
    PROJECT_ROOT="$proj" DEVBIN_NAME=rustdemo DEVBIN_LANGUAGES=rust "$proj/bin/.devbin/lib/cmd/dormancy"
  assert_failure
  assert_output_contains "dormancy: no config at bin/.devbin/config.yaml (try: bin/devbin install) -- nothing was measured"
  [ ! -e "$bin/cargo.log" ] || fail "cargo ran"
}

@test "the declared line is printed with where it came from (0135)" {
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  assert_output_contains "declared  cargo test    (devbin's catalogue)"
  assert_output_contains "maximum   cargo test --all-features"
}

# ============================================================================
# IT MUST NOT CLAIM THE GATE'S VERDICT
# ============================================================================

@test "neither leg re-points LATEST_RUST -- a probe is not the gate's verdict" {
  # LATEST_RUST means "the newest DELIBERATE full run of this gate". A dormancy
  # probe is not one, and letting it claim the pointer would make the project's
  # current test verdict a question about feature flags. The dated pairs are
  # still written, so either leg stays quotable by name.
  proj="$(rustproj)"
  bin="$(cargo_counting 12 19)"
  rundorm "$proj" "$bin"
  assert_success
  assert_file_not_exists "$proj/tmp/test/LATEST_RUST.out"
  # AND THE RECORDS ARE STILL THERE. Withholding the pointer must not mean
  # withholding the evidence -- that would make the verb unauditable.
  local n
  n="$(find "$proj/tmp/test" -maxdepth 1 -type f -name '*.RUST.out' | wc -l | tr -d ' ')"
  [ "$n" = 2 ] || fail "expected both legs' logs on disk, found $n:
$(find "$proj/tmp/test" -maxdepth 1 -type f)"
}

# ============================================================================
# WHAT THIS SUITE IS GREEN OVER
# ============================================================================

@test "the suite DECLARES that no arm of it ran real cargo" {
  # Every fixture above is a shell script named cargo. What is proven is that
  # the verb reads the trailer shape correctly and refuses the states it
  # should. It is NOT proven that real cargo still prints that trailer, or that
  # --all-features still means what it means here. Stated rather than left to
  # be inferred from the absence of a test -- which is the whole lesson of a
  # suite that was green while structurally blind to its own class.
  if command -v cargo >/dev/null 2>&1; then
    echo "# cargo IS present on this runner -- and no test here invokes it." >&3
  else
    echo "# cargo is absent on this runner, which changes nothing: no test" >&3
    echo "# here would have used it." >&3
  fi
  echo "# The trailer shape 'test result: ok. N passed; M failed' is validated" >&3
  echo "# by construction only, against lib/runlog's cargo counter." >&3
}
