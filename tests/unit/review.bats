#!/usr/bin/env bats
# review.bats - the WP-13 pre-rollout review findings (R1-R10)
#
# One file for the whole review because the findings share nothing but their
# provenance: they were found by reading the base end to end before it touched a
# live project, and each is here so it cannot come back.
#
# Every test below was verified to go RED against the code as it stood at the
# review, which is the only reason to believe any of them.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  init_colors off
}
teardown() { devbin_teardown; }


# ============================================================================
# R1 -- the scaffold's test stub must find the project root from ANY depth
# ============================================================================

@test "R1: a scaffolded test stub passes in a tests-at-root project" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  # The layout a migrated project actually has, and the one `new` supports:
  # tests/ directly under the root, not tests/unit/ like devbin's own.
  mkdir -p "$proj/tests"
  touch "$proj/tests/seed.bats"

  run devbin_run "$proj" new deploy --summary "Ship it"
  assert_success
  assert_file_exists "$proj/tests/deploy.bats"

  # The stub is a real bats file: run it. Before the fix both of its tests
  # failed here, because DEVBIN_HOME was derived as ../.. and landed above the
  # project. A scaffold whose own tests fail out of the box is the first thing a
  # migrated project would have seen.
  #
  # DEVBIN_HOME is UNSET for the run. The stub honours it as an override, and
  # this harness exports it pointing at the Devbin checkout -- so leaving it set
  # would test the override and never reach the derivation under test.
  run env -u DEVBIN_HOME bats "$proj/tests/deploy.bats"
  assert_success
}

@test "R1: the stub also passes from a nested test directory" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
YAML
  )"
  # devbin's own shape, and any project one level deeper. The walk has to handle
  # both, which a fixed count of `..` cannot.
  mkdir -p "$proj/tests/unit"
  touch "$proj/tests/unit/seed.bats"

  run devbin_run "$proj" new deploy --summary "Ship it"
  assert_success
  assert_file_exists "$proj/tests/unit/deploy.bats"

  run env -u DEVBIN_HOME bats "$proj/tests/unit/deploy.bats"
  assert_success
}

# ============================================================================
# R3 -- config values that become variable names are validated
# ============================================================================

@test "R3: a root_var that is not an identifier is refused, naming the key" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  root_var: "BAD NAME"
YAML
  )"
  run ! devbin_run "$proj" help
  # devbin's own located message, not bash's `not a valid identifier`.
  assert_output_contains "project.root_var"
  assert_output_contains "config.yaml"
}

@test "R3: a project name whose DERIVED root variable is illegal is refused" {
  proj="$(mkproj demo <<'YAML'
project:
  name: "my proj"
YAML
  )"
  run ! devbin_run "$proj" help
  # The input is legal-looking; `upper_snake` turns it into `MY PROJ_ROOT`.
  # Validating the input rather than the derived name would pass this.
  #
  # Asserting on the derived NAME alone was not enough, and the red-check caught
  # it: bash's own `export: 'MY PROJ_ROOT=...': not a valid identifier` contains
  # that string too, so the test passed with the guard removed. It has to assert
  # on what only devbin's message says, and refuse what only bash's says.
  assert_output_contains "project.name gives the root variable"
  refute_output_contains "not a valid identifier"
}

@test "R3: root_var may not be a variable the run itself depends on" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  root_var: PATH
YAML
  )"
  run ! devbin_run "$proj" help
  assert_output_contains "PATH"
  # Before this, the export SUCCEEDED and the failure surfaced later as
  # `env: bash: No such file or directory`, exit 127, pointing nowhere near
  # the config that caused it.
  refute_output_contains "No such file or directory"
}

@test "R3: root_var may not take a name devbin's own environment uses" {
  # DEVBIN_ROOT_VAR carries the root variable's own NAME (ST0007 WP-02), so a root
  # variable called that would be overwritten by its name as soon as it was set.
  # The names from DEVBIN_RUN_ID on were missing from the list, so root_var could
  # overwrite the run id, the stamp, the referent and the cli task with the
  # project root, rc 0 (issue 0081).
  local name
  for name in DEVBIN_LIB DEVBIN_ROOT_VAR DEVBIN_RUN_ID DEVBIN_RUN_STAMP DEVBIN_RUN_REFERENT DEVBIN_CLI_TASK \
    DEVBIN_LANGUAGES DEVBIN_FMT_ARMS DEVBIN_ACTIVE_CHECK; do
    proj="$(mkproj "demo-$name" <<YAML
project:
  name: demo
  root_var: $name
YAML
    )"
    run ! devbin_run "$proj" help
    assert_output_contains "'$name' -- that name belongs to devbin's own environment"
  done
}

@test "R3: a shared option may not export into a name devbin's own environment uses" {
  # The same list guards options.<name>.export, which is applied later than
  # root_var and so is never overwritten back (issue 0081).
  local name
  for name in DEVBIN_LIB DEVBIN_RUN_ID DEVBIN_RUN_STAMP DEVBIN_RUN_REFERENT DEVBIN_CLI_TASK DEVBIN_LANGUAGES \
    DEVBIN_FMT_ARMS DEVBIN_ACTIVE_TEST; do
    proj="$(mkproj "demo-$name" <<YAML
project:
  name: demo
options:
  style:
    flag: true
    export: $name
YAML
    )"
    run ! devbin_run "$proj" version --style
    assert_output_contains "options.style.export must not be '$name' -- that name belongs to devbin's own environment"
  done
}

@test "R3: every name the dispatcher exports to a handler is one a config value may not take" {
  # Issue 0081. assert_identifier's list is a hand-kept copy of what bin/devbin
  # and lib/resolve export, and it fell six names and a family behind with nothing
  # to report it. So this arm takes the population from runs instead: the
  # dispatcher starts from an environment holding only HOME and PATH, so every
  # other name a handler sees was added by devbin, and each must be refused. A
  # bats caller would hide DEVBIN_LIB, which the harness exports itself.
  #
  # Several paths, because exports are conditional: a project handler, with
  # project.referent declared; an option's run: through the gate, which adds
  # DEVBIN_ACTIVE_TEST; `test all`, which adds the seal ledger; and a notes.run
  # command under `release check`, whose environment lib/release.notes sets
  # itself, re-pointed at the root it was asked about. Not reached:
  # DEVBIN_OPT_<NAME>, exported for a framework option only where the project
  # speaks its language, and reserved as a family; and what devbin sets on one
  # child's command line rather than exporting.
  local caller added name not_refused="" want
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  referent: printf abc123
commands:
  release:
    enabled: true
  test:
    options:
      dump:
        run: ./dump-env
release:
  notes:
    kind: command
    run: bin/notes-env
YAML
  )"
  create_test_command "$proj" probe '#!/usr/bin/env bash
env >"$PROJECT_ROOT/env.probe"' >/dev/null
  printf '#!/usr/bin/env bash\nenv >env.option\n' >"$proj/dump-env"
  chmod +x "$proj/dump-env"
  printf '#!/usr/bin/env bash\nenv >>env.notes\ncase "$1" in views-check) echo none ;; state) echo open ;; esac\n' >"$proj/bin/notes-env"
  chmod +x "$proj/bin/notes-env"
  printf '1.0.0\n' >"$proj/VERSION"
  caller="$(env -i HOME="$HOME" XDG_DATA_HOME="$XDG_DATA_HOME" PATH="$PATH" bash -c 'env')"
  scrubbed() { env -i HOME="$HOME" XDG_DATA_HOME="$XDG_DATA_HOME" PATH="$PATH" bash -c 'cd "$1" && shift && ./bin/devbin "$@" </dev/null' _ "$proj" "$@"; }
  run scrubbed probe
  assert_success
  run scrubbed test dump
  assert_success
  mv "$proj/env.option" "$proj/env.dump"
  run scrubbed test all
  [ -f "$proj/env.option" ] || fail "test all did not run the dump option: $output"
  run scrubbed release check
  assert_success
  [ -f "$proj/env.notes" ] || fail "release check did not run notes.run: $output"
  added="$(
    cat "$proj/env.probe" "$proj/env.dump" "$proj/env.option" "$proj/env.notes" |
      sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | LC_ALL=C sort -u |
      LC_ALL=C comm -13 <(printf '%s\n' "$caller" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | LC_ALL=C sort -u) -
  )"
  # THE CONTROLS: each path was reached, so the population cannot shrink quietly.
  for want in DEVBIN_LIB DEVBIN_COMMAND DEVBIN_RUN_REFERENT DEVBIN_ACTIVE_TEST DEVBIN_SEAL_LEDGER DEMO_ROOT; do
    grep -qx "$want" <<<"$added" || fail "the runs did not add $want, so a path this arm counts on was not reached:
$added"
  done
  # And the probe refuses: DEMO_ROOT is the project's own root variable, which a
  # config value may name.
  (assert_identifier DEMO_ROOT probe) || fail "assert_identifier refused DEMO_ROOT, so a refusal below proves nothing"
  while IFS= read -r name; do
    [ "$name" = DEMO_ROOT ] && continue
    if (assert_identifier "$name" probe) >/dev/null 2>&1; then
      not_refused="$not_refused $name"
    fi
  done <<<"$added"
  [ -z "$not_refused" ] || fail "the dispatcher exports names a config value may still take:$not_refused"
}

@test "R3: a project legitimately named devbin still gets DEVBIN_ROOT" {
  # The overreach guard. `DEVBIN_*` as a wildcard refused this, and this is
  # Devbin's own case -- so the first version of the fix broke the framework's
  # own build. DEVBIN_ROOT is a derived project name, not a devbin internal.
  proj="$(mkproj devbin <<'YAML'
project:
  name: devbin
YAML
  )"
  run devbin_run "$proj" help
  assert_success
}

@test "R3: a shared option export that is not an identifier is refused" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  style:
    flag: true
    export: "A B"
YAML
  )"
  run ! devbin_run "$proj" version --style
  assert_output_contains "options.style.export"
}

# ============================================================================
# R4 -- DEVBIN_COMMAND reaches a handler on every path that reaches a handler
# ============================================================================

@test "R4: a mapped handler learns its command name on every path that reaches it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  ls:
    handler: myls
    summary: mapped
    options:
      long:
        summary: long listing
YAML
  )"
  cat >"$proj/bin/.devbin/cmd/myls" <<'SH'
#!/usr/bin/env bash
printf 'COMMAND=%s\n' "${DEVBIN_COMMAND:-UNSET}"
SH
  chmod +x "$proj/bin/.devbin/cmd/myls"

  # 1. the dispatcher's direct exec
  run devbin_run "$proj" ls
  assert_success
  assert_output_contains "COMMAND=ls"

  # 2. through a declared option -- run_option's handler path, which was the
  #    one that did not export it. `$0` is cmd/myls, so without this the
  #    handler cannot know it was called as `ls`.
  run devbin_run "$proj" ls long
  assert_success
  assert_output_contains "COMMAND=ls"

  # 3. through the synthesised all, which reaches the same path
  run devbin_run "$proj" ls all
  assert_success
  assert_output_contains "COMMAND=ls"
}

# ============================================================================
# R5 -- a stray file inside the vendored area is reported
# ============================================================================

@test "R5: doctor reports a file devbin does not own under lib" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf 'stray\n' >"$proj/bin/.devbin/lib/stray.txt"

  run devbin_run "$proj" doctor
  # A NOTE, not a failure: nothing is broken. What was wrong was the silence --
  # doctor said "N vendored files intact" with an untracked file beside them.
  assert_success
  assert_output_contains "unowned"
  assert_output_contains "stray.txt"
}

@test "R5: a clean install reports nothing unowned" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "unowned"
}

@test "R5: an OWNED file is never reported unowned, however large the manifest" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  # This pins a RACE, and the padding below is about determinism, not reach.
  #
  # The membership test in _check_unowned was a pipeline, and under pipefail a
  # pipeline whose reader exits early is unsound: `grep -q` returns the instant
  # it matches, `printf` takes SIGPIPE on the write still in flight, and pipefail
  # promotes the writer's 141 to the status of the whole pipeline -- so `&&
  # continue` does not fire and an OWNED file is reported unowned. The bug is on
  # the MATCH path; the miss path, where grep reads to EOF, always worked.
  #
  # With devbin's own manifest printf's write usually lands before grep can
  # exit, so the test above passed on Ubuntu and on nearly every macOS run, and
  # went red on exactly one (CI run 32787816443: `lib/cmd/install` unowned on a
  # clean install with every file present and intact). A test that is green
  # 99 times in 100 against broken code is not evidence, which is why the one
  # above is not this test.
  #
  # Padding the manifest past the pipe buffer makes printf BLOCK, so grep's early
  # exit is guaranteed to strand it and the failure becomes reliable. Long names
  # rather than many files: the byte count is what has to clear the buffer, and
  # the file count is what the membership scan pays for.
  #
  # The padding is genuinely OWNED -- real files, real checksums, appended to the
  # manifest -- so the correct answer is still "nothing unowned". The test
  # asserts the invariant, not the scaffolding.
  local pad="$proj/bin/.devbin/lib/_pad" i name bytes
  local -a rels=()
  mkdir -p "$pad"
  name="$(printf 'p%.0s' {1..240})"
  for i in $(seq 1 350); do
    printf 'pad\n' >"$pad/$i-$name"
    rels[${#rels[@]}]="bin/.devbin/lib/_pad/$i-$name"
  done
  (cd "$proj" && sha256_files "${rels[@]}") >>"$proj/bin/.devbin/manifest.sha256"

  # The predicate beside the number: assert the states block actually clears a
  # 64K pipe buffer, so a future change that shrinks the padding cannot quietly
  # turn this back into the coin-flip above.
  bytes=$((350 * (3 + ${#name} + 24)))
  [ "$bytes" -gt 65536 ] || fail "padding is $bytes bytes -- under a 64K pipe buffer, the race is not forced"

  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "unowned"
}

# ============================================================================
# R7 -- a flag given a value is refused rather than silently ignored
# ============================================================================

@test "R7: a flag spelled with a value is refused" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  style:
    flag: true
    value: json
    export: DEMO_STYLE
YAML
  )"
  run ! devbin_run "$proj" version --style=plain
  assert_output_contains "takes no value"
}

@test "R7: the flag still works in its own spelling" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
options:
  style:
    flag: true
    value: json
    export: DEMO_STYLE
commands:
  show:
    summary: report it
    run: ./show
YAML
  )"
  cat >"$proj/show" <<'SH'
#!/usr/bin/env bash
printf 'STYLE=%s\n' "${DEMO_STYLE:-unset}"
SH
  chmod +x "$proj/show"
  run devbin_run "$proj" show --style
  assert_success
  assert_output_contains "STYLE=json"
}

# ============================================================================
# R8 -- duplicate keys are caught by the PARSER, which knows the line
# ============================================================================

@test "R8: a key that opened a map cannot also carry a value" {
  run ! cfg_load_string <<'YAML'
project:
  name: x
project: 5
YAML
  assert_output_contains "duplicate key"
  # The parser knows the line; the schema check downstream only knew the key,
  # and reported it as `unknown key` -- which describes neither the mistake nor
  # where it is.
  assert_output_matches ':[0-9]+: duplicate key'
}

@test "R8: a key that carries a value cannot also take sequence items" {
  run ! cfg_load_string <<'YAML'
project:
  name: x
  languages: flat
    - elixir
YAML
  assert_output_contains "duplicate key"
  assert_output_contains "already has a value"
}

@test "R8: the annotated reference config still parses and validates" {
  # The other direction, and the reason this is not just a stricter parser: the
  # rules above must not reject anything legal.
  cfg_load "$DEVBIN_LIB_DIR/config.reference.yaml"
  cfg_validate
}

# ============================================================================
# R9 -- replacing a vendored file is atomic
# ============================================================================

@test "R9: replacing an existing file leaves no partial content" {
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  local src="$DEVBIN_TEST_TMPDIR/src" dst="$DEVBIN_TEST_TMPDIR/dst"
  printf 'new content\n' >"$src"
  printf 'old content\n' >"$dst"

  copy_vendored "$src" "$dst"
  run cat "$dst"
  assert_output "new content"

  # The temporary must not survive: a leftover .devbin-new file inside the
  # vendored area would be exactly the unowned stray R5 exists to report.
  run find "$DEVBIN_TEST_TMPDIR" -name '*.devbin-new.*'
  assert_output ""
}

@test "R9: replacing swaps the file rather than truncating it in place" {
  # THE test for this finding, and the arms above are not: content and mode come
  # out the same whether the copy is atomic or not, so they pass against plain
  # `cp` and say nothing about the property under test.
  #
  # What is observable is the inode. `cp` opens the destination and truncates
  # it, so a reader mid-write sees a half-file and the inode is unchanged.
  # write-then-rename gives the destination a NEW inode, which is exactly what
  # makes the swap atomic -- a reader holds the old file open, whole, or opens
  # the new one, whole.
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  local src="$DEVBIN_TEST_TMPDIR/src" dst="$DEVBIN_TEST_TMPDIR/dst" before after
  printf 'new\n' >"$src"
  printf 'old\n' >"$dst"

  before="$(ls -i "$dst" | awk '{print $1}')"
  copy_vendored "$src" "$dst"
  after="$(ls -i "$dst" | awk '{print $1}')"

  [ "$before" != "$after" ] || {
    fail "destination kept inode $before -- it was truncated in place, not swapped"
    return 1
  }
}

@test "R9: the executable bit still crosses on both the new and replace paths" {
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  local src="$DEVBIN_TEST_TMPDIR/src"
  printf '#!/bin/sh\n' >"$src"
  chmod +x "$src"

  # new-file path
  copy_vendored "$src" "$DEVBIN_TEST_TMPDIR/fresh"
  assert_executable "$DEVBIN_TEST_TMPDIR/fresh"

  # replace path, over a non-executable file
  printf 'old\n' >"$DEVBIN_TEST_TMPDIR/existing"
  chmod -x "$DEVBIN_TEST_TMPDIR/existing"
  copy_vendored "$src" "$DEVBIN_TEST_TMPDIR/existing"
  assert_executable "$DEVBIN_TEST_TMPDIR/existing"

  # and the bit is REMOVED when the source lost it
  chmod -x "$src"
  copy_vendored "$src" "$DEVBIN_TEST_TMPDIR/existing"
  run test -x "$DEVBIN_TEST_TMPDIR/existing"
  assert_failure
}

# ============================================================================
# R10 -- help answers its own -h, and a real command beats the flag spelling
# ============================================================================

@test "R10: help answers -h and --help rather than refusing them" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help -h
  assert_success
  assert_output_contains "Usage:"

  run devbin_run "$proj" help --help
  assert_success
  assert_output_contains "Usage:"
}

@test "R10: bare why still means the flag when no command owns the name" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help why
  assert_success
  assert_output_contains "Not offered here:"
}

@test "R10: a project command named why gets its own topic" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  cat >"$proj/bin/.devbin/cmd/why" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$proj/bin/.devbin/cmd/why"
  printf 'The reasons.\n' >"$proj/bin/.devbin/help/why.md"

  run devbin_run "$proj" help why
  assert_success
  assert_output_contains "The reasons."
  # The flag spelling must not swallow it: a command help cannot describe is
  # worse than a flag with one spelling instead of two.
  refute_output_contains "Not offered here:"
}
