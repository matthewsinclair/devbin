#!/usr/bin/env bats
# version.bats - the version command and its sidecar sync (WP-17)
#
# The riskiest thing devbin does. `version set` and `version bump` mutate files
# other tooling reads, and a partial write leaves a project internally
# inconsistent in a way no gate catches -- one consumer shipped a wrong
# CFBundleShortVersionString at v0.3.2 exactly this way.
#
# These invariants carry the whole design, and each is tested rather than trusted
# because each was learned by getting it wrong:
#
#   - DERIVED FILES FIRST, THE VERSION FILE LAST. A partial failure then leaves
#     the version un-advanced, so a rerun recomputes the same target and
#     retries. The other order double-bumps on top of a half-synced tree.
#   - THE SYNC IS UNCONDITIONAL. A "only if it differs" gate skips healing
#     exactly when the version file is right and a sidecar is not, which is the
#     one case that needs healing.

load "../lib/test_helper"
load "../lib/source_fixtures"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }


# A project with a VERSION file and the given config.
versioned_project() {
  local proj
  proj="$(mkproj demo)"
  printf '1.2.3\n' >"$proj/VERSION"
  echo "$proj"
}

# ============================================================================
# READING (AC-17.1)
# ============================================================================

@test "bare version prints the project name and version" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version
  assert_success
  # `unknown` and not an omitted field. A project outside git has no commit
  # identity, and DROPPING the field there would rebuild the exact defect this
  # arm was changed to fix: one command rendering two shapes by circumstance,
  # each looking correct alone. Honest ignorance is a value.
  #
  # THE RUNTIME DIGEST IS PRESENT EVEN HERE, and that is the point of having it
  # beside the commit: `unknown` names no bytes, and this project still has
  # bytes. Matched by shape rather than by value -- pinning the literal would
  # make every edit under lib/ red this test.
  [[ "$output" =~ ^demo\ 1\.2\.3\ \(unknown,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "identity line is not the expected shape: $output"
}

@test "the --version flag and the bare version command render ONE identical line" {
  # THE REGRESSION THIS EXISTS FOR, found in devbin's own checkout: the flag
  # printed `devbin 0.1.0 (<sha>)` and the sub-command printed `devbin 0.1.0`.
  # Two renderings of one question, and because devbin's project IS devbin, that
  # tree is the only place the disagreement is visible side by side. Every
  # consumer saw one or the other and neither looked wrong.
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  git -C "$proj" init -q
  git -C "$proj" config user.email dev@test
  git -C "$proj" config user.name dev
  git -C "$proj" add -A
  git -C "$proj" commit -qm first

  run devbin_run "$proj" --version
  assert_success
  local flag="$output"

  run devbin_run "$proj" version
  assert_success
  [ "$output" = "$flag" ] ||
    fail "the two surfaces disagree:
  --version -> $flag
  version   -> $output"

  # NOT A VACUOUS EQUALITY. Two empty strings are equal, so a change that
  # emptied BOTH renderings would pass the assertion above while destroying the
  # command. Pin the shape as well: name, semver, and a real 40-char sha.
  [[ "$flag" =~ ^demo\ 1\.2\.3\ \([0-9a-f]{40},\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "identity line is not the expected shape: $flag"
}

@test "over an index git cannot read, --version never prints the bare commit (0186)" {
  # The identity read a failed status as a clean tree, so a dirty tree whose
  # index git could not read printed the bare sha at rc 0: a provenance line
  # naming a commit its bytes are not.
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  printf 'one\n' >"$proj/NOTES.txt"
  git -C "$proj" init -q
  git -C "$proj" config user.email dev@test
  git -C "$proj" config user.name dev
  git -C "$proj" add -A
  git -C "$proj" commit -qm first
  local sha
  sha="$(git -C "$proj" rev-parse HEAD)"
  printf 'two\n' >>"$proj/NOTES.txt"
  # THE CONTROL: with the index readable, the same tree says +dirty.
  run devbin_run "$proj" --version
  assert_success
  [[ "$output" =~ ^demo\ 1\.2\.3\ \($sha\ \+dirty,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "the control is not the dirty identity: $output"
  break_git_index "$proj"
  run devbin_run "$proj" --version
  assert_success
  [[ "$output" =~ ^demo\ 1\.2\.3\ \($sha\ \+unreadable,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "over an index git cannot read, --version says: $output"
}

@test "version show stays BARE while the human arms carry provenance" {
  # The fix above must not spread. `show` is the machine arm and a sha in it
  # breaks every line-oriented reader that consumes the number.
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version show
  assert_success
  assert_output "1.2.3"

  run devbin_run "$proj" version
  assert_success
  [[ "$output" =~ ^demo\ 1\.2\.3\ \(unknown,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "identity line is not the expected shape: $output"
}

@test "version show prints the bare number, for scripting -- and ends its line" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version show
  assert_success
  assert_output "1.2.3"
  # bats strips trailing newlines from $output, so the newline is counted
  # directly. A show with no terminator glues the number to the next prompt
  # and breaks every line-oriented reader; the corpus's own show printed it
  # (found with `od -c` on the real output).
  run bash -c "cd '$proj' && ./bin/devbin version show | wc -l | tr -d ' '"
  assert_output "1"
}

@test "with no version to read, version show prints nothing on stdout, exits 1 and names project.version_from (0259)" {
  # show is the machine arm: a script reads its line as the number, and the
  # word unknown read as one names a tag vunknown, at exit 0.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  [ ! -e "$proj/VERSION" ] || fail "the fixture holds a VERSION, so the arm would test nothing"
  run --separate-stderr devbin_run "$proj" version show
  assert_exit_code 1
  [ -z "$output" ] || fail "show printed on stdout with no version file: $output"
  grep -qF 'VERSION, the file project.version_from names, does not exist' <<<"$stderr" ||
    fail "the refusal does not say why, naming the key: $stderr"
  grep -qF 'start it with: bin/devbin version set 0.1.0' <<<"$stderr" || fail "the refusal does not name the remedy: $stderr"
  # A version file that holds nothing is no version either.
  : >"$proj/VERSION"
  run --separate-stderr devbin_run "$proj" version show
  assert_exit_code 1
  [ -z "$output" ] || fail "show printed on stdout from an empty version file: $output"
  grep -qF 'VERSION, the file project.version_from names, holds no version' <<<"$stderr" ||
    fail "the refusal does not say why: $stderr"
  grep -qF 'set one with: bin/devbin version set 0.1.0' <<<"$stderr" || fail "the refusal does not name the remedy: $stderr"
}

@test "with a structured version file missing, version show names it and says to put the version there, never version set (0259)" {
  # A mix.exs holds more than the version, and version set never starts one,
  # so a remedy naming set would send the reader to a second refusal.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  run --separate-stderr devbin_run "$proj" version show
  assert_exit_code 1
  [ -z "$output" ] || fail "show printed on stdout with no mix.exs: $output"
  grep -qF 'mix.exs, the file project.version_from names, does not exist' <<<"$stderr" ||
    fail "the refusal does not say why, naming the key: $stderr"
  grep -qF "create it with the project's version in it, or point project.version_from at the file that holds the version" <<<"$stderr" ||
    fail "the refusal does not give the structured remedy: $stderr"
  ! grep -qF 'version set' <<<"$stderr" || fail "the refusal names version set, which refuses a missing mix.exs: $stderr"
}

@test "with no version to read, version check does not pass, and names project.version_from (0259)" {
  # With no sidecar declared there is nothing to compare, and the line used to
  # say `version: unknown` at exit 0, so a gate read the project as clean.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version check
  assert_exit_code 1
  assert_output_contains "the version cannot be read: VERSION, the file project.version_from names, does not exist"
  assert_output_contains "start it with: bin/devbin version set 0.1.0"
  refute_output_contains "NO sidecars declared"
}

@test "with no version to read, version bump refuses once, naming the file, the key and the remedy, and writes nothing (0259)" {
  # bump raised the semver refusal inside its own argument, so it said it of
  # unknown and then again of the empty string, naming no file, key or remedy.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version bump patch
  assert_exit_code 1
  assert_output_contains "no version to bump: VERSION, the file project.version_from names, does not exist"
  assert_output_contains "start it with: bin/devbin version set 0.1.0"
  refute_output_contains "must be semver"
  [ ! -e "$proj/VERSION" ] || fail "the refusal wrote VERSION"
  # A version that reads but is not X.Y.Z is refused once too: the next version
  # is worked out in bump's own shell, so the refusal is not said again of ''.
  printf 'v1\n' >"$proj/VERSION"
  run devbin_run "$proj" version bump patch
  assert_exit_code 1
  assert_output_contains "got 'v1'"
  refute_output_contains "got ''"
}

@test "with no version to read, version sync refuses once, naming the file, the key and the remedy, and writes nothing (0259)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version sync
  assert_exit_code 1
  assert_output_contains "no version to sync: VERSION, the file project.version_from names, does not exist"
  assert_output_contains "start it with: bin/devbin version set 0.1.0"
  refute_output_contains "must be semver"
  [ ! -e "$proj/VERSION" ] || fail "the refusal wrote VERSION"
}

@test "with no version to read, the identity line keeps its one-line shape, unknown where the version stands (0259)" {
  # The guard on the other side: the refusal is show's and check's, and the
  # human arms still print their one line.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" --version
  assert_success
  [[ "$output" =~ ^demo\ unknown\ \(unknown,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "the identity line is not one line of the expected shape: $output"
  run devbin_run "$proj" version
  assert_success
  [[ "$output" =~ ^demo\ unknown\ \(unknown,\ runtime\ [0-9a-f]{12}\)$ ]] ||
    fail "the bare version line is not one line of the expected shape: $output"
}

@test "version set 0.1.0 starts a missing VERSION, the bare kind, and exits 0 (0259)" {
  # The remedy every refusal above names: refusing it left no command that
  # could begin a version file.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  [ ! -e "$proj/VERSION" ] || fail "the fixture holds a VERSION, so the arm would test nothing"
  run devbin_run "$proj" version set 0.1.0
  assert_success
  assert_output "0.1.0"
  [ "$(cat "$proj/VERSION")" = 0.1.0 ] || fail "VERSION holds: $(cat "$proj/VERSION" 2>&1)"
}

@test "version set starts a missing VERSION beside a declared sidecar, writing both (0259)" {
  # The ordinary way a project begins one: the sidecar passes the preflight,
  # the version file passes as one to start, and the writes take both.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.0.0\n' >"$proj/notes.txt"
  run devbin_run "$proj" version set 1.0.1
  assert_success
  assert_output "1.0.1"
  [ "$(cat "$proj/VERSION")" = 1.0.1 ] || fail "VERSION holds: $(cat "$proj/VERSION" 2>&1)"
  assert_file_contains "$proj/notes.txt" "1.0.1"
}

@test "version set refuses to start a version file in a directory that is not there, naming it, before writing any sidecar (0259)" {
  # Its write would fail after every sidecar had taken the new version, a
  # half-written set, so the preflight refuses it while the tree is as it was.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: meta/VERSION
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.0.0\n' >"$proj/notes.txt"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "meta/VERSION, the file project.version_from names, does not exist, and devbin cannot make a file in meta"
  assert_output_contains "make meta, or point project.version_from at the file that holds the version"
  assert_file_contains "$proj/notes.txt" "1.0.0"
  [ ! -e "$proj/meta" ] || fail "the refusal made $proj/meta"
}

# permission_case_built <case> <test>... -- rc 0 when the `[` test <test>
# holds, so the mode an arm just set took. Where this runner's permissions undo
# it, as root's do, the arm would build a state it only claims: skipped on a
# developer's machine and FAILED under CI, for require_command's reason, as
# make_unreadable's rule is (issue 0260).
permission_case_built() {
  local what="$1"
  shift
  [ "$@" ] && return 0
  [[ -z "${CI:-}" ]] || fail "this CI runner's permissions undo the mode the $what case sets, so it cannot be built: run the job as a user they bind"
  skip "running with permissions that undo the mode the $what case sets: it was NOT checked"
}

@test "version set refuses a version file of a structured kind with no version devbin reads, naming it and project.version_from, and changes no file (0260)" {
  # Its recipe rewrites the version read_version reads, and there is none, so
  # set changed nothing and printed unknown at exit 0.
  local before
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  printf '[workspace]\nmembers = ["a"]\n' >"$proj/Cargo.toml"
  before="$(cksum <"$proj/Cargo.toml")"
  run devbin_run "$proj" version set 0.1.0
  assert_exit_code 1
  assert_output_contains "cannot write the version: Cargo.toml, the file project.version_from names, holds no version devbin reads -- add the project's version to it"
  [ "$(cksum <"$proj/Cargo.toml")" = "$before" ] || fail "the refusal changed Cargo.toml"
  [ ! -e "$proj/VERSION" ] || fail "the refusal wrote VERSION"
}

@test "version set refuses a sidecar of a structured kind with no version devbin reads, naming it and project.version_sidecars, before writing anything (0260)" {
  # notes.txt, a bare sidecar listed first, is written first in the write pass,
  # so its holding 1.0.0 says the refusal came from the preflight.
  local before
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
    - Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '1.0.0\n' >"$proj/notes.txt"
  printf '[workspace]\nmembers = ["a"]\n' >"$proj/Cargo.toml"
  before="$(cksum <"$proj/Cargo.toml")"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: Cargo.toml, declared in project.version_sidecars, holds no version devbin reads -- add the project's version to it, or drop it from project.version_sidecars"
  assert_file_contains "$proj/VERSION" "1.0.0"
  assert_file_contains "$proj/notes.txt" "1.0.0"
  [ "$(cksum <"$proj/Cargo.toml")" = "$before" ] || fail "the refusal changed Cargo.toml"
}

@test "version set refuses a version file or a sidecar it cannot write, naming it, before writing anything (0260)" {
  # The preflight never asked whether a file can be written, so the sidecars
  # took the new version and the version file then failed with bash's own error.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '1.0.0\n' >"$proj/notes.txt"
  chmod 0444 "$proj/VERSION"
  permission_case_built read-only ! -w "$proj/VERSION"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: VERSION, the file project.version_from names, cannot be written -- let devbin write it"
  assert_file_contains "$proj/notes.txt" "1.0.0"
  assert_file_contains "$proj/VERSION" "1.0.0"
  # And a sidecar it cannot write, with the version file writable again.
  chmod 0644 "$proj/VERSION"
  chmod 0444 "$proj/notes.txt"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: notes.txt, declared in project.version_sidecars, cannot be written -- let devbin write it, or drop it from project.version_sidecars"
  assert_file_contains "$proj/VERSION" "1.0.0"
  assert_file_contains "$proj/notes.txt" "1.0.0"
}

@test "version set rewrites a read-only Cargo.toml, which keeps its mode, as replace_file does (0260)" {
  # A GUARD, green before 0260: the recipe writes a copy and renames it over
  # the file, so a read-only manifest is rewritten, and the first 0260 bank,
  # which asked the file's own write bit, refused it.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  printf '[package]\nname = "demo"\nversion = "1.0.0"\n' >"$proj/Cargo.toml"
  chmod 0444 "$proj/Cargo.toml"
  run devbin_run "$proj" version set 1.0.1
  assert_success
  assert_output "1.0.1"
  assert_file_contains "$proj/Cargo.toml" 'version = "1.0.1"'
  [ "$(mode_of "$proj/Cargo.toml")" = "-r--r--r--" ] || fail "the read-only Cargo.toml came out $(mode_of "$proj/Cargo.toml")"
}

@test "version set refuses a Cargo.toml sidecar in a directory that takes no new file, before writing the bare sidecar listed ahead of it (0260)" {
  # Its recipe makes a copy beside it and renames it over the file, so its
  # directory must take a new file: the write pass died in mktemp after
  # plain.txt had taken the new version, a half-written set.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - plain.txt
    - sub/Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '1.0.0\n' >"$proj/plain.txt"
  mkdir -p "$proj/sub"
  printf '[package]\nname = "demo"\nversion = "1.0.0"\n' >"$proj/sub/Cargo.toml"
  chmod 0555 "$proj/sub"
  permission_case_built "unwritable directory" ! -w "$proj/sub"
  run devbin_run "$proj" version set 1.0.1
  chmod 0755 "$proj/sub"
  assert_exit_code 1
  assert_output_contains "cannot write the version: sub/Cargo.toml, declared in project.version_sidecars, is in sub, where devbin cannot make the copy it writes and renames over the file -- let devbin write in sub, or drop it from project.version_sidecars"
  assert_file_contains "$proj/plain.txt" "1.0.0"
  assert_file_contains "$proj/VERSION" "1.0.0"
  assert_file_contains "$proj/sub/Cargo.toml" 'version = "1.0.0"'
}

@test "version set refuses an immutable Cargo.toml sidecar listed after a bare one, before writing anything, and leaves no temporary (0279)" {
  # The preflight asked what a rename-over write needs and not whether the
  # file can be replaced at all, so the write pass took plain.txt to the new
  # version and then failed on Cargo.toml: a half-written set, with BSD's
  # copy leaving an immutable temporary its own rm could not remove.
  local left
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - plain.txt
    - Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '1.0.0\n' >"$proj/plain.txt"
  printf '[package]\nname = "demo"\nversion = "1.0.0"\n' >"$proj/Cargo.toml"
  make_immutable "$proj/Cargo.toml"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: Cargo.toml, declared in project.version_sidecars, is immutable, so no write can replace it -- clear its immutable flag, or drop it from project.version_sidecars"
  assert_file_contains "$proj/plain.txt" "1.0.0"
  assert_file_contains "$proj/VERSION" "1.0.0"
  assert_file_contains "$proj/Cargo.toml" 'version = "1.0.0"'
  left="$(find "$proj" -maxdepth 1 -name 'Cargo.toml.??????')"
  [ -z "$left" ] || fail "a temporary was left in the project: $left"
}

@test "check calls an empty Cargo.toml sidecar one that holds no version devbin reads, and names no sync, which refuses it (0260)" {
  # An empty file of the bare kind is drift sync fills; a structured one holds
  # more than the version, so sync refuses it, and check sent the reader there.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  : >"$proj/Cargo.toml"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "not compared -- holds no version devbin reads"
  refute_output_contains "empty (expected"
  refute_output_contains "holds nothing (expected"
  refute_output_contains "heal with"
}

@test "set and check say a structured sidecar devbin cannot read cannot be read, and neither calls it empty (0260)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '[package]\nname = "demo"\nversion = "1.0.0"\n' >"$proj/Cargo.toml"
  make_unreadable "$proj/Cargo.toml"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: Cargo.toml, declared in project.version_sidecars, cannot be read -- let devbin read it"
  refute_output_contains "holds no version"
  assert_file_contains "$proj/VERSION" "1.0.0"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "not compared -- cannot be read"
  refute_output_contains "Permission denied"
  refute_output_contains "heal with"
}

@test "version set refuses a bare sidecar devbin cannot read before writing anything, and its text survives (0260, 0264)" {
  # A failed read counted as an empty file, which the bare-sidecar guard lets
  # be written, so a sidecar holding prose was overwritten at exit 0. It is
  # write-only, the mode that overwrite needs: one devbin could neither read
  # nor write would have failed the write anyway.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf 'prose, not a version\n' >"$proj/notes.txt"
  chmod 0200 "$proj/notes.txt"
  permission_case_built write-only ! -r "$proj/notes.txt"
  run devbin_run "$proj" version set 1.0.1
  chmod 0644 "$proj/notes.txt"
  assert_exit_code 1
  assert_output_contains "cannot write the version: notes.txt, declared in project.version_sidecars, cannot be read -- let devbin read it"
  assert_file_contains "$proj/notes.txt" "prose, not a version"
  assert_file_contains "$proj/VERSION" "1.0.0"
}

@test "version set refuses a version file devbin can write but not read, naming it, rather than print unknown at exit 0 (0260, 0264)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  chmod 0200 "$proj/VERSION"
  permission_case_built write-only ! -r "$proj/VERSION"
  run devbin_run "$proj" version set 1.0.1
  chmod 0644 "$proj/VERSION"
  assert_exit_code 1
  assert_output_contains "cannot write the version: VERSION, the file project.version_from names, cannot be read -- let devbin read it"
  refute_output_contains "unknown"
  assert_file_contains "$proj/VERSION" "1.0.0"
}

@test "version set refuses a read-only plist sidecar, and one with no version key, before writing anything (0260)" {
  # PlistBuddy exits 0 when it cannot write, so a read-only plist was left at
  # the old version under set's exit 0, and a plist with no key half-wrote the
  # set and was re-serialised.
  [ -x /usr/libexec/PlistBuddy ] || skip "PlistBuddy is macOS-only: this arm was NOT checked here"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - Info.plist
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$proj/Info.plist" >/dev/null
  chmod 0444 "$proj/Info.plist"
  permission_case_built "read-only plist" ! -w "$proj/Info.plist"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: Info.plist, declared in project.version_sidecars, cannot be written -- let devbin write it"
  assert_file_contains "$proj/VERSION" "1.0.0"
  # No version key at all, in a plist devbin can write.
  chmod 0644 "$proj/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleShortVersionString" -c "Add :CFBundleName string demo" "$proj/Info.plist" >/dev/null
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: Info.plist, declared in project.version_sidecars, holds no version devbin reads"
  assert_file_contains "$proj/VERSION" "1.0.0"
}

# --- the one line a recipe rewrites (issue 0263) -----------------------------
#
# Each recipe rewrites the line read_version reads, and no other: each sed,
# unaddressed, rewrote every line that looked like a version. So each arm sets
# a version, holds the whole file to what it was with that one line changed,
# and reads the version back through show, the line read being the line written.

# set_and_hold <proj> <file> <before> <after> -- version_from <file> in <proj>
# holds <before>; `version set 0.2.0` exits 0, the file then holds exactly
# <after>, and show reads 0.2.0 back.
set_and_hold() {
  printf '%s' "$3" >"$1/$2"
  run devbin_run "$1" version set 0.2.0
  assert_success
  assert_output "0.2.0"
  cmp -s <(printf '%s' "$4") "$1/$2" || fail "set changed more than the version line, or not it:
$(diff <(printf '%s' "$4") "$1/$2")"
  run devbin_run "$1" version show
  assert_success
  assert_output "0.2.0"
}

@test "version set rewrites a Cargo.toml's [package] version alone, and a dependency table's version stays byte for byte (0263)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  set_and_hold "$proj" Cargo.toml \
    $'[package]\nname = "demo"\nversion = "0.1.0"\n\n[dependencies.serde]\nversion = "1.0"\nfeatures = ["derive"]\n' \
    $'[package]\nname = "demo"\nversion = "0.2.0"\n\n[dependencies.serde]\nversion = "1.0"\nfeatures = ["derive"]\n'
}

@test "version set rewrites a workspace's [workspace.package] version (0263)" {
  # A GUARD: the table a workspace root states its version in is read and
  # written, as it was.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  set_and_hold "$proj" Cargo.toml \
    $'[workspace]\nmembers = ["a"]\n\n[workspace.package]\nversion = "0.1.0"\n' \
    $'[workspace]\nmembers = ["a"]\n\n[workspace.package]\nversion = "0.2.0"\n'
}

@test "version set refuses a Cargo.toml whose first version line is a dependency's, and changes no byte of it (0263)" {
  # read_version read the dependency's version as the project's, and the
  # recipe rewrote both lines.
  local before
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  printf '[dependencies.serde]\nversion = "1.0"\n\n[package]\nname = "demo"\nversion = "0.1.0"\n' >"$proj/Cargo.toml"
  before="$(cksum <"$proj/Cargo.toml")"
  run devbin_run "$proj" version set 0.2.0
  assert_exit_code 1
  assert_output_contains "cannot write the version: Cargo.toml, the file project.version_from names, holds no version devbin reads"
  [ "$(cksum <"$proj/Cargo.toml")" = "$before" ] || fail "the refusal changed Cargo.toml"
}

@test "version set rewrites a package.json's top-level version alone, and a nested version key stays byte for byte (0263)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: package.json
YAML
  )"
  set_and_hold "$proj" package.json \
    $'{\n  "name": "demo",\n  "version": "0.1.0",\n  "overrides": {\n    "foo": {\n      "version": "2.0.0"\n    }\n  }\n}\n' \
    $'{\n  "name": "demo",\n  "version": "0.2.0",\n  "overrides": {\n    "foo": {\n      "version": "2.0.0"\n    }\n  }\n}\n'
}

@test "a one-line package.json reads its version, and set rewrites it and reads it back at exit 0 (0280)" {
  # The npm reader took the line's fourth quoted field, so this read as
  # `demo`, the name, and set refused its own correct write on reading back.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: package.json
YAML
  )"
  set_and_hold "$proj" package.json \
    $'{"name":"demo","version":"0.1.0"}\n' \
    $'{"name":"demo","version":"0.2.0"}\n'
}

@test "a one-line package.json with a nested version ahead of the top-level one has the top-level one read and rewritten, and the nested one stays (0280)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: package.json
YAML
  )"
  set_and_hold "$proj" package.json \
    $'{"overrides":{"foo":{"version":"2.0.0"}},"version":"0.1.0"}\n' \
    $'{"overrides":{"foo":{"version":"2.0.0"}},"version":"0.2.0"}\n'
}

@test "a Cargo.toml whose multi-line array has element lines opening with [ reads its [package] version, and set rewrites that line alone (0281)" {
  # version_line read `  [1, 2],` as a table header, left [package], and so
  # read no version at all.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: Cargo.toml
YAML
  )"
  set_and_hold "$proj" Cargo.toml \
    $'[package]\nname = "demo"\nkeywords = [\n  [1, 2],\n  "[x]",\n]\nversion = "0.1.0"\n\n[dependencies.serde]\nversion = "1.0"\n' \
    $'[package]\nname = "demo"\nkeywords = [\n  [1, 2],\n  "[x]",\n]\nversion = "0.2.0"\n\n[dependencies.serde]\nversion = "1.0"\n'
}

@test "version set rewrites a mix.exs's first version line alone, and a second stays byte for byte (0263)" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  set_and_hold "$proj" mix.exs \
    $'defmodule Demo.MixProject do\n  def project do\n    [\n      app: :demo,\n      version: "0.1.0",\n      releases: [\n        demo: [\n          version: "9.9.9"\n        ]\n      ]\n    ]\n  end\nend\n' \
    $'defmodule Demo.MixProject do\n  def project do\n    [\n      app: :demo,\n      version: "0.2.0",\n      releases: [\n        demo: [\n          version: "9.9.9"\n        ]\n      ]\n    ]\n  end\nend\n'
}

@test "version set reads every file back, and refuses, naming it, a plist whose write did not take though PlistBuddy exited 0 (0264)" {
  # PlistBuddy exits 0 when it cannot write, so its status said nothing about
  # whether the plist took the version. The stand-in, first on PATH, reads
  # through the real one and takes no Set, at exit 0.
  [ "$(uname -s)" = Darwin ] || skip "PlistBuddy is macOS-only: this arm was NOT checked here"
  local fake="$DEVBIN_TEST_TMPDIR/fakepb"
  mkdir -p "$fake"
  printf '#!/bin/sh\ncase "$2" in Set*) exit 0 ;; esac\nexec /usr/libexec/PlistBuddy "$@"\n' >"$fake/PlistBuddy"
  chmod +x "$fake/PlistBuddy"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - Info.plist
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$proj/Info.plist" >/dev/null
  PATH="$fake:$PATH" run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "the write of 1.0.1 did not take in every sidecar it was written to"
  assert_output_contains "Info.plist reads 1.0.0"
  assert_output_contains "VERSION was not written, so it still holds the version it held"
  assert_output_contains "then run 'bin/devbin version set 1.0.1'"
  refute_output_contains "VERSION reads"
  # The sidecars are read back before the version file is written, so it has
  # not moved, and a rerun of bump computes the same target.
  assert_file_contains "$proj/VERSION" "1.0.0"
  refute_file_contains "$proj/VERSION" "1.0.1"
}

@test "version check names a drifted or empty sidecar that sync could not write for that, and prescribes no sync (0265)" {
  # check called both drift that sync heals, and sync then refused each: the
  # writer's question was asked by set alone.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - old.txt
    - empty.txt
YAML
  )"
  printf '1.0.1\n' >"$proj/VERSION"
  printf '1.0.0\n' >"$proj/old.txt"
  : >"$proj/empty.txt"
  chmod 0444 "$proj/old.txt" "$proj/empty.txt"
  permission_case_built read-only ! -w "$proj/old.txt"
  run devbin_run "$proj" version check
  chmod 0644 "$proj/old.txt" "$proj/empty.txt"
  assert_exit_code 1
  assert_output_contains "1.0.0 (expected 1.0.1) -- cannot be written"
  assert_output_contains "empty.txt"
  assert_output_contains "holds nothing (expected 1.0.1) -- cannot be written"
  refute_output_contains "empty (expected"
  assert_output_contains "a declared sidecar is one 'version sync' would refuse as well"
  refute_output_contains "heal with"
}

@test "version set refuses a missing structured version file, naming it and project.version_from, and writes nothing (0259)" {
  # A mix.exs holds more than the version, so one written holding only the
  # number would be wrong: only the bare kind is started.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  run devbin_run "$proj" version set 0.1.0
  assert_exit_code 1
  assert_output_contains "cannot write the version: mix.exs, the file project.version_from names, does not exist, and devbin never starts a mix.exs"
  refute_output_contains "version sidecar"
  [ ! -e "$proj/mix.exs" ] || fail "the refusal wrote mix.exs"
  [ ! -e "$proj/VERSION" ] || fail "the refusal wrote VERSION"
}

@test "version set refuses a missing sidecar, naming it and project.version_sidecars alone, before writing the version file, and check names no sync for it (0259, 0265)" {
  # The role keeps a missing sidecar refused while a missing version file is
  # started, since without it the bare recipe would create one. Its words are
  # version_unread's for the sidecar role (0265), and check, which called it
  # missing and prescribed the sync that refuses it, now says the same.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  run devbin_run "$proj" version set 1.0.1
  assert_exit_code 1
  assert_output_contains "cannot write the version: notes.txt, declared in project.version_sidecars, does not exist -- fix the path, or drop it from project.version_sidecars"
  refute_output_contains "project.version_from"
  assert_file_contains "$proj/VERSION" "1.0.0"
  [ ! -e "$proj/notes.txt" ] || fail "the refusal wrote the sidecar"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "not compared -- does not exist"
  refute_output_contains "heal with"
}

@test "a version file that is a link to no file is refused, never written through (0259)" {
  # Only a path with nothing at it is started: writing through a dangling link
  # would create the file it names, somewhere the project never put one. The
  # directory it names is there, so a write through the link would land.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  mkdir -p "$proj/shared"
  ln -s shared/VERSION "$proj/VERSION"
  run devbin_run "$proj" version set 0.1.0
  assert_exit_code 1
  assert_output_contains "cannot write the version: VERSION, the file project.version_from names, is a link to no file"
  [ -L "$proj/VERSION" ] || fail "VERSION is no longer a link"
  [ ! -e "$proj/shared/VERSION" ] || fail "writing through the dangling link created $proj/shared/VERSION"
}

# ============================================================================
# SET AND BUMP (AC-17.2)
# ============================================================================

@test "version set writes an explicit semver" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version set 2.0.0
  assert_success
  assert_file_contains "$proj/VERSION" "2.0.0"
}

@test "version set refuses something that is not a semver" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version set v2
  assert_failure
  # And it did NOT write. A rejected version that half-applied would be worse
  # than one that was accepted.
  assert_file_contains "$proj/VERSION" "1.2.3"
}

@test "version bump advances the named part and zeroes the rest" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version bump patch
  assert_success
  assert_output_contains "1.2.4"

  run devbin_run "$proj" version bump minor
  assert_success
  assert_output_contains "1.3.0"

  run devbin_run "$proj" version bump major
  assert_success
  assert_output_contains "2.0.0"
}

@test "version bump refuses an unknown part" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version bump sideways
  assert_failure
  assert_file_contains "$proj/VERSION" "1.2.3"
}

# ============================================================================
# SIDECARS -- THE RECIPE IS THE LIBRARY'S, THE LIST IS CONFIG'S (AC-17.3)
# ============================================================================

# The sidecars sidecar_project declares, one of each kind devbin rewrites on
# any platform, so every kind but a plist, which only PlistBuddy writes, and it
# is macOS-only: its config is written from this list, and an arm that counts
# them reads it, so no arm holds the number by hand. At file scope, since
# sidecar_project runs in a substitution.
SIDECAR_FILES=(native/cli/Cargo.toml mix.exs assets/package.json plain.txt)

# Build a project with one sidecar of each kind in SIDECAR_FILES.
sidecar_project() {
  local proj
  proj="$(mkproj demo <<YAML
project:
  name: demo
  version_sidecars:
$(printf '    - %s\n' "${SIDECAR_FILES[@]}")
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  mkdir -p "$proj/native/cli" "$proj/assets"
  printf '[package]\nname = "demo"\nversion = "1.2.3"\nedition = "2021"\n' \
    >"$proj/native/cli/Cargo.toml"
  printf 'defmodule Demo.MixProject do\n  def project do\n    [\n      app: :demo,\n      version: "1.2.3"\n    ]\n  end\nend\n' \
    >"$proj/mix.exs"
  printf '{\n  "name": "demo",\n  "version": "1.2.3"\n}\n' >"$proj/assets/package.json"
  printf '1.2.3\n' >"$proj/plain.txt"
  echo "$proj"
}

@test "version set fans out to every declared sidecar, by file kind" {
  proj="$(sidecar_project)"
  run devbin_run "$proj" version set 2.5.1
  assert_success
  # The config named the FILES; devbin knew the recipe for each kind. No
  # regular expressions anywhere in the project's config.
  assert_file_contains "$proj/VERSION" "2.5.1"
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "2.5.1"'
  assert_file_contains "$proj/mix.exs" 'version: "2.5.1"'
  assert_file_contains "$proj/assets/package.json" '"version": "2.5.1"'
  assert_file_contains "$proj/plain.txt" "2.5.1"
}

@test "version set writes through linked version files: every link survives and every file it names holds the version" {
  # Issue 0084, measured through this dispatcher: the bare VERSION recipe
  # followed its link, while each sed recipe replaced its link with a regular
  # file, left the file it named at the old version, and exited 0 -- after which
  # `version check` agreed with the copies. Cargo.toml's link is absolute.
  local f
  local -a sidecars=(Cargo.toml package.json mix.exs)
  proj="$(mkproj demo <<YAML
project:
  name: demo
  version_sidecars:
$(printf '    - %s\n' "${sidecars[@]}")
YAML
  )"
  mkdir -p "$proj/shared"
  printf '1.0.0\n' >"$proj/shared/VERSION"
  printf '[package]\nname = "demo"\nversion = "1.0.0"\n' >"$proj/shared/Cargo.toml"
  printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' >"$proj/shared/package.json"
  printf 'defmodule Demo.MixProject do\n  def project do\n    [\n      version: "1.0.0"\n    ]\n  end\nend\n' >"$proj/shared/mix.exs"
  ln -s shared/VERSION "$proj/VERSION"
  ln -s "$proj/shared/Cargo.toml" "$proj/Cargo.toml"
  ln -s shared/package.json "$proj/package.json"
  ln -s shared/mix.exs "$proj/mix.exs"
  run devbin_run "$proj" version set 1.0.1
  assert_success
  for f in VERSION "${sidecars[@]}"; do
    [ -L "$proj/$f" ] || fail "$f is no longer a link"
  done
  assert_file_contains "$proj/shared/VERSION" "1.0.1"
  assert_file_contains "$proj/shared/Cargo.toml" 'version = "1.0.1"'
  assert_file_contains "$proj/shared/package.json" '"version": "1.0.1"'
  assert_file_contains "$proj/shared/mix.exs" 'version: "1.0.1"'
  run devbin_run "$proj" version check
  assert_success
  assert_output_contains "${#sidecars[@]} sidecar(s) agree"
}

@test "a sidecar that is a link to no file is refused naming it as one before any file is written, and check says the same (0265)" {
  # The preflight refuses a dangling link, so writing through links must not
  # start creating the file a dangling link names, nor write the sidecar
  # declared before it. set called it a sidecar that does not exist and check
  # called it missing; each now says what version_file_state found (0265).
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - package.json
    - Cargo.toml
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' >"$proj/package.json"
  # The directory the link names is there, so a write through it would land.
  mkdir -p "$proj/shared"
  ln -s shared/Cargo.toml "$proj/Cargo.toml"
  run devbin_run "$proj" version set 1.0.1
  assert_failure
  assert_output_contains "cannot write the version: Cargo.toml, declared in project.version_sidecars, is a link to no file -- point the link at the sidecar, or drop it from project.version_sidecars"
  assert_file_contains "$proj/VERSION" "1.0.0"
  assert_file_contains "$proj/package.json" '"version": "1.0.0"'
  [ -L "$proj/Cargo.toml" ] || fail "Cargo.toml is no longer a link"
  [ ! -e "$proj/shared/Cargo.toml" ] || fail "writing through the dangling link created $proj/shared/Cargo.toml"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "not compared -- is a link to no file"
  refute_output_contains "heal with"
}

@test "a version file that is a link to no file is said alike by set, check and doctor (0265)" {
  # A GUARD: the version file's role was worded once already (0259); this holds
  # that the role argument left it so.
  local said="VERSION, the file project.version_from names, is a link to no file"
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  mkdir -p "$proj/shared"
  ln -s shared/VERSION "$proj/VERSION"
  run devbin_run "$proj" version set 0.1.0
  assert_exit_code 1
  assert_output_contains "$said"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "$said"
  run devbin_run "$proj" doctor
  assert_output_contains "version: $said"
}

# A project declaring a STRUCTURED sidecar devbin has no recipe for. One consumer
# declares two of these (issue 0002); before the guard, the bare-version default
# overwrote each lockfile with five bytes and `check` then called the tree clean.
#
# The bare-version default itself is NOT what these tests refuse. It is
# documented and correct for a file that really is a lone version string, and
# `sidecar_project`'s `plain.txt` is the case that proves it still works -- a
# guard written as "refuse any basename I do not recognise" passes every test
# below and goes RED there, which is the point of leaving that coverage where it
# already lives rather than restating it here.
lockfile_project() {
  local proj
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - native/cli/Cargo.lock
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  mkdir -p "$proj/native/cli"
  printf '# This file is automatically @generated by Cargo.\nversion = 3\n\n[[package]]\nname = "demo"\nversion = "1.2.3"\n' \
    >"$proj/native/cli/Cargo.lock"
  cp "$proj/native/cli/Cargo.lock" "$proj/lock.before"
  echo "$proj"
}

@test "a structured sidecar devbin has no recipe for is refused, not overwritten" {
  proj="$(lockfile_project)"
  run devbin_run "$proj" version set 2.5.1
  assert_failure
  assert_output_contains "Cargo.lock"

  # BOTH halves, because either alone passes for the wrong reason: a refusal
  # that never fired leaves the file identical too, and a command that dies for
  # some unrelated reason also exits non-zero.
  run cmp -s "$proj/lock.before" "$proj/native/cli/Cargo.lock"
  assert_success
}

@test "refusing a sidecar leaves the version file un-advanced, so a rerun is clean" {
  proj="$(lockfile_project)"
  run devbin_run "$proj" version set 2.5.1
  assert_failure
  # DERIVED FILES FIRST carries the refusal: sidecars first, version file last.
  assert_file_contains "$proj/VERSION" "1.2.3"
  refute_file_contains "$proj/VERSION" "2.5.1"
}

@test "the heal that check advertises cannot destroy the file check named" {
  proj="$(lockfile_project)"
  # The composition issue 0002 records: check reports drift, names `version
  # sync` as the cure, and sync then overwrote the file and exited 0 -- after
  # which check reported the tree clean. Each step was behaving as designed.
  run devbin_run "$proj" version sync
  assert_failure
  run cmp -s "$proj/lock.before" "$proj/native/cli/Cargo.lock"
  assert_success
}

@test "check names a sidecar it cannot read rather than inventing a version from it" {
  proj="$(lockfile_project)"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "Cargo.lock"
  # It used to print the whole lockfile, whitespace stripped, as the version it
  # found there.
  refute_output_contains "[[package]]"
}

@test "check calls an unreadable sidecar unreadable rather than drifted" {
  proj="$(lockfile_project)"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "no recipe"
  # "drifted" is a claim about a file devbin read and compared against the
  # version. It did neither, and the cure it names would refuse this file.
  refute_output_contains "have drifted"
}

@test "a refused sidecar refuses BEFORE any sidecar is written, not mid-loop" {
  # The guard used to fire per file INSIDE the write pass: with [Cargo.toml,
  # Cargo.lock] the .toml was already at the new version when the .lock was
  # refused, while the refusal said "Nothing has been written" -- the command
  # that reported writing nothing had introduced exactly the drift it polices,
  # and `version check` then flagged it. Every file is preflighted before any
  # file is touched.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - native/cli/Cargo.toml
    - native/cli/Cargo.lock
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  mkdir -p "$proj/native/cli"
  printf '[package]\nname = "demo"\nversion = "1.2.3"\nedition = "2021"\n' >"$proj/native/cli/Cargo.toml"
  printf '# This file is automatically @generated by Cargo.\nversion = 3\n' >"$proj/native/cli/Cargo.lock"

  run devbin_run "$proj" version set 2.5.1
  assert_failure
  # BOTH halves: the refusal still names the .lock (an unrelated die passes
  # the file check too), and the .toml LISTED BEFORE IT is untouched.
  assert_output_contains "Cargo.lock"
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "1.2.3"'
  refute_file_contains "$proj/native/cli/Cargo.toml" "2.5.1"
}

@test "an empty sidecar is drift sync can heal, not an unreadable file to un-declare" {
  # version_file_state calls the empty file empty -- freshly created, nothing
  # to destroy -- so `sync` legally fills it. `check` used to classify
  # the same file unreadable and advise dropping it from config: the two
  # halves disagreed, and check's advice deleted config that works.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - build/VERSION.txt
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  mkdir -p "$proj/build"
  : >"$proj/build/VERSION.txt"

  run devbin_run "$proj" version check
  assert_failure
  # The empty state in the table's words, the ones show and doctor print
  # (issue 0289), never in check's own.
  assert_output_contains "holds nothing (expected 1.2.3)"
  refute_output_contains "empty (expected"
  refute_output_contains "no recipe"
  refute_output_contains "Drop it from project.version_sidecars"
  assert_output_contains "version sync"

  run devbin_run "$proj" version sync
  assert_success
  assert_file_contains "$proj/build/VERSION.txt" "1.2.3"

  run devbin_run "$proj" version check
  assert_success
}

@test "a sidecar rewrite touches only the version, not its neighbours" {
  proj="$(sidecar_project)"
  run devbin_run "$proj" version set 2.5.1
  assert_success
  assert_file_contains "$proj/native/cli/Cargo.toml" 'name = "demo"'
  assert_file_contains "$proj/native/cli/Cargo.toml" 'edition = "2021"'
  assert_file_contains "$proj/assets/package.json" '"name": "demo"'
  assert_file_contains "$proj/mix.exs" "app: :demo"
}

@test "version bump fans out too, not just set" {
  proj="$(sidecar_project)"
  run devbin_run "$proj" version bump minor
  assert_success
  assert_file_contains "$proj/VERSION" "1.3.0"
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "1.3.0"'
  assert_file_contains "$proj/mix.exs" 'version: "1.3.0"'
}

# ============================================================================
# INVARIANT: DERIVED FIRST, VERSION LAST (AC-17.4)
# ============================================================================

@test "a failing sidecar leaves the version file un-advanced, so a rerun is clean" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - native/cli/Cargo.toml
    - does/not/exist/Cargo.toml
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  mkdir -p "$proj/native/cli"
  printf '[package]\nversion = "1.2.3"\n' >"$proj/native/cli/Cargo.toml"

  run devbin_run "$proj" version bump patch
  assert_failure

  # THE INVARIANT. VERSION still holds 1.2.3, so re-running `bump patch` after
  # fixing the path recomputes 1.2.4 rather than 1.2.5. Write VERSION first and
  # this is a double-bump on top of a half-synced tree.
  assert_file_contains "$proj/VERSION" "1.2.3"
  refute_file_contains "$proj/VERSION" "1.2.4"
}

@test "a missing sidecar is named rather than silently skipped" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - gone/Cargo.toml
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  run devbin_run "$proj" version set 2.0.0
  assert_failure
  assert_output_contains "gone/Cargo.toml"
  # Silently skipping is exactly how a tree drifts, so the message says so.
  assert_output_contains "silently skipped"
}

# ============================================================================
# INVARIANT: THE SYNC IS UNCONDITIONAL (AC-17.5)
# ============================================================================

@test "sync heals a lagging sidecar even when the version file is already right" {
  proj="$(sidecar_project)"
  # The exact shape that shipped a wrong CFBundleShortVersionString: VERSION
  # bumped in an earlier commit, a sidecar left behind. A "only if the current
  # version differs" gate skips precisely this case.
  printf '9.9.9\n' >"$proj/VERSION"
  printf '[package]\nname = "demo"\nversion = "1.2.3"\n' >"$proj/native/cli/Cargo.toml"

  run devbin_run "$proj" version sync
  assert_success
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "9.9.9"'
}

@test "sync is idempotent" {
  proj="$(sidecar_project)"
  run devbin_run "$proj" version sync
  assert_success
  run devbin_run "$proj" version sync
  assert_success
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "1.2.3"'
  assert_file_contains "$proj/VERSION" "1.2.3"
}

# ============================================================================
# CHECK -- REPORT DRIFT, WRITE NOTHING (AC-17.6)
# ============================================================================

@test "check passes and NAMES ITS DENOMINATOR when every sidecar agrees" {
  # The wording changed in issue 0061. It said `every sidecar agrees` -- a
  # universally quantified claim that is VACUOUSLY TRUE over an empty set, and
  # printed byte-identically whether four sidecars had been compared or none
  # had. The count is the denominator this repository requires of anything whose
  # job is checking.
  proj="$(sidecar_project)"
  run devbin_run "$proj" version check
  assert_success
  assert_output_contains "${#SIDECAR_FILES[@]} sidecar(s) agree"
}

# A project correctly configured with a single version file and NO sidecars.
# This is the ORDINARY case, not a broken one: measured as the common case
# among the projects that vendor devbin, devbin's own included, which is why
# zero stays exit 0.
nosidecar_project() {
  local proj
  proj="$(mkproj bare <<'YAML'
project:
  name: bare
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  echo "$proj"
}

@test "check over ZERO sidecars says NOTHING WAS COMPARED, and is not a pass" {
  # Found in Intent's own checkout: `version check` printed a pass over an empty
  # sidecar list. A reader could not tell "I compared every sidecar and none
  # disagreed" from "I compared nothing" -- and a fresh project adopting devbin
  # got that green before declaring anything, which is the worst moment for a
  # version check to be reassuring.
  proj="$(nosidecar_project)"
  run devbin_run "$proj" version check
  assert_success
  assert_output_contains "NO sidecars declared"
  assert_output_contains "nothing was compared"
  refute_output_contains "agree"
}

@test "the ZERO verdict and the PASS verdict are not the same string" {
  # THE ARM THAT PINS THE DEFECT ITSELF rather than either verdict. Both of the
  # arms above can be satisfied by an implementation that still renders the two
  # cases identically in some third wording; only comparing them catches that.
  # Before the fix these two runs produced byte-identical output at rc 0.
  local empty full
  empty="$(nosidecar_project)"; full="$(sidecar_project)"
  run devbin_run "$empty" version check
  assert_success
  local zero_out="$output"
  run devbin_run "$full" version check
  assert_success
  [ "$zero_out" != "$output" ]
}

@test "check reports drift, names the file, and writes nothing" {
  proj="$(sidecar_project)"
  printf '[package]\nname = "demo"\nversion = "0.0.1"\n' >"$proj/native/cli/Cargo.toml"

  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "native/cli/Cargo.toml"
  assert_output_contains "0.0.1"
  assert_output_contains "expected 1.2.3"
  # Read-only: the drift is still there afterwards.
  assert_file_contains "$proj/native/cli/Cargo.toml" 'version = "0.0.1"'
}

@test "check points at the command that heals what it found" {
  proj="$(sidecar_project)"
  printf '[package]\nversion = "0.0.1"\n' >"$proj/native/cli/Cargo.toml"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "version sync"
}

# ============================================================================
# THE VERSION FILE IS NAMED BY CONFIG
# ============================================================================

@test "version reads and writes the file project.version_from names" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_from: mix.exs
YAML
  )"
  printf 'defmodule Demo.MixProject do\n  def project do\n    [\n      app: :demo,\n      version: "4.5.6"\n    ]\n  end\nend\n' \
    >"$proj/mix.exs"
  # One consumer's case: the version genuinely lives in mix.exs and copying it into a
  # VERSION file to suit the launcher would create a second source of truth.
  run devbin_run "$proj" version show
  assert_success
  assert_output "4.5.6"

  run devbin_run "$proj" version bump patch
  assert_success
  assert_file_contains "$proj/mix.exs" 'version: "4.5.7"'
}

@test "the version file reads raw -- the bare-content guard is for sidecars" {
  # `version_from` DECLARES its file's whole content to be the version, so the
  # issue-0002 guard second-guessing that content turned a hand-authored
  # `v1.2.3` into `unknown` -- and `check` then reported every sidecar drifted
  # against a version that was right there. The guard's territory is the
  # bare-DEFAULT read of a SIDECAR devbin has no recipe for, and only that;
  # read_version carries the same roles the writer does.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  printf 'v1.2.3\n' >"$proj/VERSION"
  run devbin_run "$proj" version show
  assert_success
  assert_output "v1.2.3"
}

@test "a sidecar holding a non-bare string is still guarded -- the roles differ on purpose" {
  # The other half of the same line. Scoping the reader guard to sidecars must
  # not have removed it FROM sidecars: a declared bare sidecar holding more
  # than a version still reads unknown, never as a "version" to compare.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  version_sidecars:
    - notes.txt
YAML
  )"
  printf '1.2.3\n' >"$proj/VERSION"
  printf 'v1.2.3 -- see CHANGELOG\n' >"$proj/notes.txt"
  run devbin_run "$proj" version check
  assert_failure
  assert_output_contains "not compared -- holds more than a version"
}

@test "an unknown sub-command is refused with the usage line" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version frobnicate
  assert_failure
  assert_output_contains "usage:"
  assert_output_contains "unknown version sub-command"
}

@test "the usage line names how to invoke the dispatcher, not the project's name (issue 0107)" {
  proj="$(versioned_project <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" version frobnicate
  assert_failure
  assert_output_contains "usage: bin/devbin version"
  refute_output_contains "usage: demo version"
}

# ============================================================================
# THE RUNTIME DIGEST -- WHICH BYTES, not which commit
#
# `git_head_identity` answers "where did this checkout stand", and on a dirty
# tree it answers `<sha> +dirty` -- a value that names no bytes at all, at
# exactly the moment a reader most needs an identity. The digest answers the
# question someone comparing two installs actually has.
#
# The properties below are the whole contract, and the first is the one
# that dictated the implementation: paths fold relative to the LIB DIRECTORY,
# so a source checkout and an install of it agree. Folding against a project
# root would have made every install differ from its own source by
# construction, and that difference would have read as divergence.
# ============================================================================

@test "the runtime digest COLLIDES for a source and an install of it" {
  src="$(mksrc)"
  target="$(mkempty)"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success

  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local from_source from_install
  from_source="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  from_install="$(runtime_digest "$target/bin/devbin" "$target/bin/.devbin/lib")"

  [ -n "$from_source" ] || fail "the source digest is empty"
  [ "$from_source" = "$from_install" ] ||
    fail "a source and its own install disagree about their runtime:
  source  -> $from_source
  install -> $from_install"
}

@test "a runtime whose lib is a symlink digests as the directory it names, and one whose link names nothing has no digest, never its launcher alone (0139)" {
  # find's default -P read a symlinked lib as the link itself, listed nothing,
  # and the runtime digested as its launcher alone, at rc 0. -H follows the
  # start point, and only the start point.
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local real linked alone
  real="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  ln -s "$src/lib" "$BATS_TEST_TMPDIR/linkedlib"
  linked="$(runtime_digest "$src/bin/devbin" "$BATS_TEST_TMPDIR/linkedlib")" || fail "the runtime behind a link has no digest"
  # THE CONTROL: the launcher alone digests differently, so the equality below
  # is the lib read through the link, not two empty listings agreeing.
  mkdir -p "$BATS_TEST_TMPDIR/emptylib"
  alone="$(runtime_digest "$src/bin/devbin" "$BATS_TEST_TMPDIR/emptylib")"
  [ "$real" != "$alone" ] || fail "the control failed: the lib adds nothing to the digest"
  [ "$linked" = "$real" ] || fail "a symlinked lib digests differently: real $real, linked $linked, launcher alone $alone"
  # A LINK THAT NAMES NOTHING is no lib: it listed nothing and digested as the
  # launcher alone, at rc 0.
  ln -s "$BATS_TEST_TMPDIR/nowhere" "$BATS_TEST_TMPDIR/danglinglib"
  run runtime_digest "$src/bin/devbin" "$BATS_TEST_TMPDIR/danglinglib"
  assert_failure
  assert_output_contains "runtime digest: $BATS_TEST_TMPDIR/danglinglib is not a directory"
  refute_digest_line "$output" "for a lib naming nothing"
}

@test "a runtime file that cannot be read when it is digested gives no digest, wherever it falls (0139)" {
  # The readability test is a moment before the reads, and each cat's status was
  # dropped, so a file lost between the two digested as absent at rc 0 -- or, at
  # the last file, at rc 1 with a digest printed anyway. A cat that fails on one
  # file stands in for the race.
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local whole first last victim
  whole="$(runtime_digest "$src/bin/devbin" "$src/lib")" || fail "the control has no digest"
  first="$(find "$src/lib" -type f | sort | sed -n '1p')"
  last="$(find "$src/lib" -type f | sort | sed -n '$p')"
  [ -n "$first" ] && [ "$first" != "$last" ] || fail "the fixture's lib holds fewer than two files: $first / $last"
  cat() {
    if [ "${1:-}" = "$CAT_FAILS" ]; then
      printf 'cat: %s: Permission denied\n' "$1" >&2
      return 1
    fi
    command cat "$@"
  }
  for victim in "$first" "$src/bin/devbin" "$last"; do
    CAT_FAILS="$victim" run runtime_digest "$src/bin/devbin" "$src/lib"
    [ "$status" -ne 0 ] || fail "a runtime whose $victim could not be read was digested: $output"
    refute_digest_line "$output" "although $victim could not be read"
  done
  # THE STAND-IN IS TRANSPARENT: named for a path outside the runtime, it fails
  # no read, and the digest is the whole one (a stand-in failing every read
  # would keep this arm green).
  CAT_FAILS=/nonexistent/outside-the-runtime run runtime_digest "$src/bin/devbin" "$src/lib"
  assert_success
  assert_output_line "$whole"
  unset -f cat
  # THE CONTROL: with every read whole, the digest is the one above.
  run runtime_digest "$src/bin/devbin" "$src/lib"
  assert_success
  assert_output_line "$whole"
}

@test "the runtime digest MOVES when a runtime byte moves" {
  # Without this the test above passes against a function that returns a
  # constant, which would be a fingerprint that fingerprints nothing.
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local before after
  before="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  printf '\n# a byte\n' >>"$src/lib/helpers"
  after="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  [ "$before" != "$after" ] || fail "the digest did not move when lib/helpers did: $before"
}

@test "the runtime digest MOVES when a runtime file is RENAMED but not changed" {
  # Paths go in alongside contents for this: a concatenation of file bodies
  # alone cannot tell `cmd/clean` from `cmd/destroy` holding the same bytes.
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local before after
  before="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  mv "$src/lib/helpers" "$src/lib/helpers-renamed"
  after="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  [ "$before" != "$after" ] || fail "a rename did not move the digest: $before"
}

@test "the launcher is INSIDE the digest, not just the lib" {
  # bin/devbin is half the seam and it is the half a lib-only digest misses.
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local before after
  before="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  printf '\n# a byte\n' >>"$src/bin/devbin"
  after="$(runtime_digest "$src/bin/devbin" "$src/lib")"
  [ "$before" != "$after" ] || fail "the launcher is not in the digest: $before"
}

@test "one runtime has one digest whatever the reader's locale: C and a UTF-8 locale that orders its files apart agree (0204)" {
  # One runtime, one digest, under any collation (issue 0204): runtime_digest's
  # comment says why the order of its paths is pinned.
  local loc list by_c by_loc in_c in_loc
  loc="$(utf8_locale en_US)" ||
    skip "no en_US UTF-8 locale on this runner: the digest under another collation was NOT checked"
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # A name C sorts ahead of every lowercase one and en_US among the z's, so the
  # runtime's listing orders apart under the two whatever lib/ ships.
  : >"$src/lib/Zplanted"
  list="$(cd "$src/lib" && find . -type f)" || fail "cannot list the fixture's lib"
  by_c="$(LC_ALL=C sort <<<"$list")" || fail "sort failed under C"
  by_loc="$(LC_ALL="$loc" sort <<<"$list")" || fail "sort failed under $loc"
  # THE CONTROL: the same lines in another order, so a sort that printed less
  # cannot pass for a locale that reorders them, and one that falls back to C
  # says so rather than comparing C with C.
  [ "$(LC_ALL=C sort <<<"$by_loc")" = "$by_c" ] || fail "sort under $loc did not print the runtime's listing whole"
  [ "$by_loc" != "$by_c" ] ||
    skip "$loc orders the runtime's files as C does here: the digest under another collation was NOT checked"
  in_c="$(LC_ALL=C runtime_digest "$src/bin/devbin" "$src/lib")" || fail "the runtime has no digest under C"
  in_loc="$(LC_ALL="$loc" runtime_digest "$src/bin/devbin" "$src/lib")" || fail "the runtime has no digest under $loc"
  [ -n "$in_c" ] || fail "the digest under C is empty"
  [ "$in_c" = "$in_loc" ] || fail "one runtime has two digests: $in_c under C, $in_loc under $loc"
}

# A RUNTIME THE DIGEST CANNOT READ WHOLE HAS NO DIGEST (issue 0139). find's
# errors went to /dev/null and the launcher's with them, so a directory it could
# not read left its files out, and a file it could not read went in as its path
# alone: a different runtime's value, and nothing said why.
@test "a runtime the digest cannot read whole has no digest, and --version says UNREADABLE (0139, 0145)" {
  src="$(mksrc)"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local d dstatus doutput
  mkdir -p "$src/lib/locked"
  printf 'x\n' >"$src/lib/locked/f"
  # THE CONTROL: readable, a digest, and the version line carries it.
  d="$(runtime_digest "$src/bin/devbin" "$src/lib")" || fail "the readable runtime has no digest"
  [ -n "$d" ] || fail "the readable runtime's digest is empty"
  run devbin_run "$src" --version
  assert_success
  assert_output_contains "runtime $d"
  chmod 000 "$src/lib/locked"
  if [ -r "$src/lib/locked" ]; then
    chmod 755 "$src/lib/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  run runtime_digest "$src/bin/devbin" "$src/lib"
  dstatus="$status"
  doutput="$output"
  run devbin_run "$src" --version
  chmod 755 "$src/lib/locked"
  [ "$dstatus" -ne 0 ] || fail "a runtime with a directory find could not read was digested: $doutput"
  # It prints NO digest when it fails, which nothing held before.
  refute_digest_line "$doutput" "by a failing runtime_digest"
  assert_find_denied "locked" "$doutput"
  assert_output_contains "runtime UNREADABLE"
  refute_output_contains "runtime $d"
  # A DIRECTORY IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and the runtime was digested without it.
  chmod 644 "$src/lib/locked"
  if [ -x "$src/lib/locked" ]; then
    chmod 755 "$src/lib/locked"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  run runtime_digest "$src/bin/devbin" "$src/lib"
  dstatus="$status"
  doutput="$output"
  run devbin_run "$src" --version
  chmod 755 "$src/lib/locked"
  [ "$dstatus" -ne 0 ] || fail "a runtime with a directory find could not search was digested: $doutput"
  refute_digest_line "$doutput" "by a failing runtime_digest"
  [[ "$doutput" == *"cannot search $src/lib/locked -- nothing beneath it was looked at"* ]] ||
    fail "the directory is not named: $doutput"
  assert_output_contains "runtime UNREADABLE"
  # AN UNREADABLE FILE, likewise.
  rm -rf "$src/lib/locked"
  printf 'x\n' >"$src/lib/hidden"
  chmod 000 "$src/lib/hidden"
  run runtime_digest "$src/bin/devbin" "$src/lib"
  chmod 644 "$src/lib/hidden"
  assert_failure
  assert_output_contains "runtime digest: cannot read $src/lib/hidden"
  refute_digest_line "$output" "by a failing runtime_digest"
  # AND THE LAUNCHER.
  rm "$src/lib/hidden"
  chmod 000 "$src/bin/devbin"
  run runtime_digest "$src/bin/devbin" "$src/lib"
  chmod 755 "$src/bin/devbin"
  assert_failure
  assert_output_contains "runtime digest: cannot read $src/bin/devbin"
  refute_digest_line "$output" "by a failing runtime_digest"
}
