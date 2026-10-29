#!/usr/bin/env bats
# doctor.bats - the install checker (WP-09)
#
# Doctor is the easiest place in this framework to write a false green, and that
# shapes what is tested here. A checker that examines nothing and prints "all
# clear" is indistinguishable from a correct one until the day it matters, so
# the count of checks RUN is part of doctor's output and there is a test on it.
#
# The rest is the failures nothing else in devbin can see: a vendored file
# edited underneath the project, and a handler in cmd/ that no command reaches.
# Everything else -- an unparseable config, a broken symlink -- announces itself
# the moment someone runs the thing. These are silent until they are not.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }

# A project installed the real way, ready to be broken in one specific place.
#
# mkinstalled [name] [languages] -- languages defaults to shell. An EMPTY second
# argument installs declaring none, which is the shape a fresh install gets when
# nobody names a language (issue 0062). One builder with a switch rather than a
# near-identical sibling that drifts from it.
mkinstalled() {
  local name="${1:-demo}" dir="$DEVBIN_TEST_TMPDIR/${1:-demo}" langs="${2-shell}"
  # The default shape is the file's starter install, copied (issue 0192); any
  # other runs the real installer, here and now.
  if [ "$name" = demo ] && [ "$langs" = shell ]; then
    install_devbin_starter "$dir" || return 1
    echo "$dir"
    return 0
  fi
  mkdir -p "$dir"
  if [ -n "$langs" ]; then
    "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name "$name" --lang "$langs" >/dev/null
  else
    "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name "$name" >/dev/null
  fi
  echo "$dir"
}

# note_detail <label> -- the detail line printed under doctor's note for <label>,
# so an assertion reads THAT note's remedy rather than the whole output.
note_detail() {
  awk -v l="$1" 'index($0, "  note  " l ": ") == 1 { getline; print; exit }' <<<"$output"
}

# ============================================================================
# THE CLEAN CASE, AND THE COUNT (AC-09.10, AC-09.11)
# ============================================================================

@test "doctor passes a fresh install and reports every check by name" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains dispatcher
  assert_output_contains runtime
  assert_output_contains config
  assert_output_contains devbin_version
  assert_output_contains manifest
  assert_output_contains commands
  assert_output_contains handlers
  assert_output_contains shadowing
  assert_output_contains launcher
  assert_output_contains bash
  assert_output_contains languages
}

@test "doctor states which languages this project arms devbin's built-ins for" {
  # Issue 0062. project.languages is GATE SCOPE and Intent's own list is PROJECT
  # COMPOSITION (lib/config.reference.yaml): different facts, not meant to
  # match. Saying which list doctor read, and what it holds, is what lets a
  # reader tell the two apart without guessing.
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  local line
  line="$(printf '%s\n' "$output" | grep -E '^  ok +languages: ' || true)"
  [ -n "$line" ] || fail "no languages result in: $output"
  [[ "$line" == *shell* ]] || fail "the languages result does not name the declared language: $line"
}

@test "a project declaring no languages gets a NOTE naming the file and what it switches off" {
  # The fresh-install shape: install writes the languages block commented out,
  # every built-in scoped by language is then inactive, and nothing said so.
  # One project met it at ST0002 close; Utilz met it with rust in
  # intent/.config/config.json, and was told its project did not declare rust.
  # A note rather than a failure, because declaring no languages is legitimate.
  proj="$(mkinstalled demo "")"
  run devbin_run "$proj" doctor
  local line detail
  line="$(printf '%s\n' "$output" | grep -E '^  note +languages: ' || true)"
  [ -n "$line" ] || fail "no languages note in: $output"
  [[ "$line" == *"declares none"* ]] || fail "the note does not say none are declared: $line"
  detail="$(note_detail languages)"
  [[ "$detail" == *"bin/.devbin/config.yaml"* ]] || fail "the remedy does not name devbin's config: $detail"
  [[ "$detail" == *"intent/.config/config.json"* ]] || fail "the remedy does not say Intent's list is a different one: $detail"
  refute_output_contains "ok    languages:"
}

@test "a project whose version cannot be read gets a NOTE naming project.version_from, and one that reads passes (0259)" {
  # version show and version check refuse while the version cannot be read, so
  # doctor says so first. A note, not a failure: a fresh install starts with no
  # version file.
  proj="$(mkinstalled)"
  [ ! -e "$proj/VERSION" ] || fail "the fixture holds a VERSION, so the arm would test nothing"
  run devbin_run "$proj" doctor
  assert_success
  local line detail
  line="$(printf '%s\n' "$output" | grep -E '^  note +version: ' || true)"
  [ -n "$line" ] || fail "no version note in: $output"
  [[ "$line" == *"VERSION, the file project.version_from names, does not exist"* ]] ||
    fail "the note does not say why, naming the key: $line"
  detail="$(note_detail version)"
  [[ "$detail" == *"start it with: bin/devbin version set 0.1.0"* ]] || fail "the remedy does not name version set: $detail"
  printf '1.2.3\n' >"$proj/VERSION"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "ok    version: 1.2.3, from VERSION (project.version_from)"
  refute_output_contains "note  version:"
}

@test "a config that does not load is never reported as declaring no languages" {
  # The dispatcher refuses an unparseable config before doctor can run, so this
  # arm starts doctor's handler directly -- the one way to reach a doctor whose
  # own load fails. An empty cache there would read as "declares none", which is
  # a verdict about a declaration nobody could read.
  proj="$(mkinstalled)"
  printf 'broken:\n\tindent: tab\n' >>"$proj/bin/.devbin/config.yaml"
  run env PROJECT_ROOT="$proj" DEVBIN_DIR="$proj/bin/.devbin" DEVBIN_LIB="$proj/bin/.devbin/lib" \
    DEVBIN_INVOKE=bin/devbin bash "$proj/bin/.devbin/lib/cmd/doctor"
  assert_failure
  assert_output_contains "does not parse"
  refute_output_contains "declares none"
  assert_output_contains "languages: not checked"
}

@test "a config that does not load is never reported as declaring no devbin_version" {
  # THE SIBLING OF THE ARM ABOVE, AND THE SAME HAZARD ONE CHECK LATER.
  # check_languages re-reads the config and refuses to speak when the load
  # fails -- that guard was 0062's fix. check_devbin_version, four lines
  # below it in the same file, read `not declared -- any runtime satisfies
  # this project` straight off the empty cache, which is a verdict about a
  # declaration nobody could read, printed into a report that had already
  # FAILED by name on the same file. One hazard, two adjacent checks, one
  # guarded: the fix that does not reach its neighbour is the shape here.
  proj="$(mkinstalled)"
  printf 'broken:\n\tindent: tab\n' >>"$proj/bin/.devbin/config.yaml"
  run env PROJECT_ROOT="$proj" DEVBIN_DIR="$proj/bin/.devbin" DEVBIN_LIB="$proj/bin/.devbin/lib" \
    DEVBIN_INVOKE=bin/devbin bash "$proj/bin/.devbin/lib/cmd/doctor"
  assert_failure
  assert_output_contains "does not parse"
  refute_output_contains "any runtime satisfies"
  assert_output_contains "devbin_version: not checked"
}

@test "a config that does not load is never reported as a version that reads or does not (0259)" {
  # The third check of the shape above: project.version_from is read from the
  # config doctor loads, so with none loaded there is no version file anyone
  # read, and a verdict on it would be about a key nobody could read.
  proj="$(mkinstalled)"
  printf '1.2.3\n' >"$proj/VERSION"
  printf 'broken:\n\tindent: tab\n' >>"$proj/bin/.devbin/config.yaml"
  run env PROJECT_ROOT="$proj" DEVBIN_DIR="$proj/bin/.devbin" DEVBIN_LIB="$proj/bin/.devbin/lib" \
    DEVBIN_INVOKE=bin/devbin bash "$proj/bin/.devbin/lib/cmd/doctor"
  assert_failure
  assert_output_contains "does not parse"
  # Anchored on its own note: devbin_version's line ends in the same words.
  grep -qE '^  note +version: not checked -- the config did not load' <<<"$output" ||
    fail "no version note saying it was not checked in: $output"
  refute_output_contains "ok    version:"
}

# ============================================================================
# SHADOWING -- a project name standing where a built-in one is (issue 0024)
# ============================================================================
#
# Overriding is LEGAL and load-bearing: a project must be able to put its own
# thing at any name devbin ships. What was missing is anyone SAYING SO. Two
# measured instances in one day, in opposite directions:
#
#   0018  devbin's own cmd/check stood at a built-in name for eighteen days, so
#         `check critic` swept a corpus here and scanned staged files everywhere
#         else, and the seals were the only thing that knew.
#   0024  devbin shipped `vendor` at a name two consumers already had, and their
#         handler answers tree-vs-MANIFEST where the built-in answers
#         tree-vs-SOURCE -- nearly banked as a sweep's convergence check.
#
# So this is a NOTE, never a failure. Nothing is broken; something is true and
# worth saying.

@test "a handler standing at a built-in command name is reported" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/bin/.devbin/cmd"
  # NOT `doctor` itself, which the first draft used: shadowing doctor means the
  # handler runs INSTEAD of doctor, so the check can never report on it and the
  # test compares two empty strings. The shadowing being real is exactly what
  # made that test unable to observe it.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$proj/bin/.devbin/cmd/upgrade"
  chmod +x "$proj/bin/.devbin/cmd/upgrade"

  run devbin_run "$proj" doctor
  # A NOTE, NOT A FAILURE. Overriding is supported, so a doctor that went red
  # here would be red on every project exercising a documented feature.
  assert_success
  assert_output_contains "shadowing"
  assert_output_contains "upgrade shadows the built-in"
  assert_output_contains "the project's own answers first, and devbin's is NOT reached"
}

@test "a config run: at a built-in OPTION devbin implements is reported" {
  proj="$(mkinstalled)"
  write_config "$proj" <<'EOF'
project:
  name: demo
  languages:
    - shell
commands:
  check:
    options:
      critic:
        summary: our own critic
        run: echo mine
        grammar: generic
        log: CRITIC
EOF

  # The 0018 shape exactly: `check critic` is @builtin in the catalogue, and a
  # config run: displaces it for this project alone.
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "shadowing"
  assert_output_contains "check critic"
}

@test "a config run: at a built-in COMMAND is reported (0113)" {
  proj="$(mkinstalled)"
  write_config "$proj" <<'EOF'
project:
  name: demo
commands:
  docs:
    run: echo mine
EOF

  # One consumer's shape (it declares commands.build.run), at a name devbin
  # implements. Since issue 0113 project_owns_command is ONE predicate with two
  # readers, and help.bats drives this fact on help's side; this arm is
  # doctor's, which spelled the predicate inline until then and had no arm for
  # a command-level run: at all.
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "docs shadows the built-in"
}

@test "a project that overrides nothing says so rather than staying silent" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  # THE CHECK MUST BE VISIBLE WHEN IT FINDS NOTHING. A row that only appears on
  # a hit is indistinguishable from a row that never ran -- which is the whole
  # defect class this project keeps meeting.
  assert_output_contains "shadowing"
  refute_output_contains "shadows the built-in"
}

@test "a handler at a name devbin does NOT ship is not reported as shadowing" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/bin/.devbin/cmd"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$proj/bin/.devbin/cmd/deploy"
  chmod +x "$proj/bin/.devbin/cmd/deploy"

  # The negative control. Most handlers in a real project are like this, and a
  # check that flagged them would be noise nobody reads.
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "deploy"
}

@test "doctor states how many checks it ran" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_matches '[0-9]+ checks, [0-9]+ failed'
}

@test "the number of checks reported is the number of results printed" {
  # The guard against a clean bill from a doctor that skipped everything. A
  # summary line can say "9 checks" while nine checks were never attempted;
  # counting the ok/FAIL lines is what makes the claim answerable.
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  claimed="$(printf '%s\n' "$output" | sed -n 's/^\([0-9]*\) checks.*/\1/p')"
  printed="$(printf '%s\n' "$output" | grep -cE '^  (ok|FAIL) ' || true)"
  [ -n "$claimed" ] || {
    echo "no summary line in: $output"
    return 1
  }
  [ "$claimed" -eq "$printed" ] || {
    echo "doctor claims $claimed checks but printed $printed results"
    return 1
  }
  [ "$printed" -gt 0 ]
}

@test "doctor --help succeeds and doctor refuses an argument it does not know" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor --help
  assert_success
  run devbin_run "$proj" doctor --nonsense
  assert_failure
}

# ============================================================================
# THE SILENT FAILURES (AC-09.12)
# ============================================================================

@test "doctor fails on a vendored file edited in place, and names it" {
  proj="$(mkinstalled)"
  printf '\n# edited underneath the project\n' >>"$proj/bin/.devbin/lib/helpers"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "edited in place"
  assert_output_contains "bin/.devbin/lib/helpers"
}

@test "doctor fails on a vendored file that has gone missing" {
  proj="$(mkinstalled)"
  rm "$proj/bin/.devbin/lib/gatecmd"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "missing: bin/.devbin/lib/gatecmd"
}

@test "doctor FAILS when it cannot list bin/.devbin/lib, rather than finding nothing unowned there (0127, 0145)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  proj="$(mkinstalled)"
  chmod 000 "$proj/bin/.devbin/lib/pages"
  run devbin_run "$proj" doctor
  chmod 755 "$proj/bin/.devbin/lib/pages"
  assert_failure
  assert_output_contains "unowned: could not list all of bin/.devbin/lib"
  assert_output_contains "Permission denied"
  # AND A DIRECTORY IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's
  # find passed over it at rc 0, and a file there went unchecked and unsaid.
  chmod 644 "$proj/bin/.devbin/lib/pages"
  run devbin_run "$proj" doctor
  chmod 755 "$proj/bin/.devbin/lib/pages"
  assert_failure
  assert_output_contains "cannot search $proj/bin/.devbin/lib/pages -- nothing beneath it was looked at"
  assert_output_contains "unowned: could not list all of bin/.devbin/lib"
  # And doctor finished its list: the failure is one check's, not the run's.
  assert_output_matches '[0-9]+ checks, [0-9]+ failed'
}

@test "doctor FAILS a vendored file it cannot read by name, and still runs every check and counts them (0144)" {
  local n
  proj="$(mkinstalled)"
  # THE CONTROL: all readable, the manifest passes, and the count it prints.
  run devbin_run "$proj" doctor
  assert_success
  assert_output_matches 'ok +manifest: [0-9]+ vendored files intact'
  n="$(printf '%s\n' "$output" | sed -n 's/^\([0-9][0-9]*\) checks, 0 failed.*/\1/p')"
  [ -n "$n" ] || fail "the control printed no count:\n$output"
  # It named no fault of its own: the file read as edited, or doctor ended
  # at this check with the checksum tool's line the only word.
  make_unreadable "$proj/bin/.devbin/lib/gatecmd"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  manifest: vendored files cannot be read"
  assert_output_contains "unreadable: bin/.devbin/lib/gatecmd"
  refute_output_contains "edited:  bin/.devbin/lib/gatecmd"
  refute_output_contains "have been edited in place"
  # Its own remedy, and not the edit's.
  assert_output_contains "make each readable, eg chmod u+r <file>"
  refute_output_contains "an edit here is lost"
  # The manifest owns "cannot read": line endings notes the file as unchecked
  # and does not fail it a second time (ST0008).
  assert_output_contains "unread:  bin/.devbin/lib/gatecmd"
  refute_output_contains "FAIL  line endings"
  # And doctor finished its list: the checks after the manifest's ran, and
  # every one was counted, with this the one failure.
  assert_output_contains "handlers: every file in cmd/ is reachable"
  assert_output_contains "$n checks, 1 failed"
}

# _manifest_control <proj> -- THE CONTROL for the manifest arms below: doctor
# passes <proj> with its manifest readable and present, and sets n (the count
# it prints), srcpass (1 when the source row passed) and v (the devbin_version
# it passed on). Then a project VERSION that satisfies devbin_version, still a
# pass: the header read fell through to it, and passed runtime and
# devbin_version on the project's own number.
#
# srcpass IS WHY n IS NOT PINNED ACROSS THE ARM. From a clean checkout the
# source row passes, level with the source the manifest recorded, and over a
# manifest that cannot be read or is not there it is CANNOT TELL, a note, so
# the count is one fewer; from a dirty tree the control notes it too (0144).
_manifest_control() {
  run devbin_run "$1" doctor
  assert_success
  assert_output_contains "vendored files intact"
  v="$(printf '%s\n' "$output" | sed -n 's/^  ok    devbin_version: \([^ ]*\) satisfies.*/\1/p')"
  [ -n "$v" ] || fail "the control printed no devbin_version pass:\n$output"
  printf '%s\n' "$v" >"$1/VERSION"
  run devbin_run "$1" doctor
  assert_success
  # The count is read with the version file in place, as every run after the
  # control has it: doctor's version row is a note while there is no version
  # file and a counted check once there is one (issue 0259), so a count read
  # before VERSION was written was one short of every run it was held to.
  n="$(printf '%s\n' "$output" | sed -n 's/^\([0-9][0-9]*\) checks, 0 failed.*/\1/p')"
  [ -n "$n" ] || fail "the control printed no count:\n$output"
  srcpass=0
  if grep -q '^  ok    source: ' <<<"$output"; then srcpass=1; fi
}

@test "doctor FAILS a manifest it cannot read by name, and still runs every check and counts them (0144)" {
  local n v srcpass
  proj="$(mkinstalled)"
  _manifest_control "$proj"
  # It read as a manifest of no entries: `0 vendored files intact`, a pass.
  make_unreadable "$proj/bin/.devbin/manifest.sha256"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  manifest: bin/.devbin/manifest.sha256 cannot be read"
  assert_output_contains "cannot read the manifest $proj/bin/.devbin/manifest.sha256"
  refute_output_contains "vendored files intact"
  refute_output_contains "devbin_version: $v satisfies"
  refute_output_contains "runtime: devbin $v,"
  # And doctor finished its list: the checks after the manifest's ran, and
  # every one was counted -- the unowned check it feeds is a note, never
  # counted. The one row that moves is the source's: from a clean checkout the
  # control passes it, level with the source it recorded, and the source is
  # read from the manifest's header, so here it CANNOT TELL, a note, and the
  # count is one fewer. From a dirty tree the control notes it too. Not pinned
  # at one failure: the runtime's version is read from the header as well, so
  # devbin_version fails beside it, as `unknown`, over the same unreadable file.
  assert_output_contains "handlers: every file in cmd/ is reachable"
  assert_output_contains "note  source: CANNOT TELL whether this project is current"
  [ "$srcpass" = 0 ] || n=$((n - 1))
  assert_output_matches $'\n'"$n checks, [0-9]+ failed"
  # And devbin_version's fix is the manifest's, never `upgrade`, which refuses
  # a manifest it cannot read (0159).
  assert_output_contains "fix: see manifest below -- the runtime's version is read from the manifest, which cannot be read"
  refute_output_contains "fix: bin/devbin upgrade"
}

@test "doctor FAILS an install with no manifest as unchecked, names a remedy upgrade takes, and still runs every check and counts them (0146)" {
  local n v srcpass
  proj="$(mkinstalled)"
  _manifest_control "$proj"
  # It failed the manifest and named `upgrade --from <dir>` as the fix, which
  # overwrote an edit at exit 0 over no manifest; and runtime and
  # devbin_version passed on the project's own VERSION beside that failure.
  rm "$proj/bin/.devbin/manifest.sha256"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  manifest: bin/.devbin/manifest.sha256 is missing, so no vendored file can be checked"
  assert_output_contains "upgrade refuses to run until there is a manifest"
  assert_output_contains "upgrade --from <dir> --force, or <path-to-devbin>/bin/devbin install --into $proj --force"
  assert_output_contains "each replaces every vendored file, an edit included"
  # And devbin_version's own fix is that one, never a plain upgrade, which refuses.
  assert_output_contains "fix: see manifest below"
  refute_output_contains "fix: bin/devbin upgrade    or relax"
  refute_output_contains "re-install to write one, or upgrade --from <dir>"
  refute_output_contains "vendored files intact"
  refute_output_contains "devbin_version: $v satisfies"
  refute_output_contains "runtime: devbin $v,"
  assert_output_contains "FAIL  devbin_version: running unknown"
  # And doctor finished its list, every check counted: the two failures, and
  # the source row a note here, as over an unreadable manifest.
  assert_output_contains "handlers: every file in cmd/ is reachable"
  assert_output_contains "note  source: CANNOT TELL whether this project is current"
  [ "$srcpass" = 0 ] || n=$((n - 1))
  assert_output_contains $'\n'"$n checks, 2 failed"
}

@test "doctor FAILS a manifest that records no files, by name, and never counts it intact or its files unowned (0159)" {
  local m
  proj="$(mkinstalled)"
  _manifest_control "$proj"
  # Cut to its header it passed "0 vendored files intact", named every vendored
  # file unowned with the advice to delete them, and ended "0 failed".
  m="$proj/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  manifest: bin/.devbin/manifest.sha256 records no files, so no vendored file can be checked"
  refute_output_contains "vendored files intact"
  refute_output_contains "unowned"
}

# _install_rows_unknown <version> -- each row of doctor's output that names the
# install's own version, runtime and devbin_version, says unknown, and neither
# holds the project's <version>; only the project's version row names it, as
# it must, since that row is about the project (0259).
_install_rows_unknown() {
  local key row
  for key in "runtime: devbin " "devbin_version: "; do
    row="$(grep -F -- "$key" <<<"$output")" || fail "doctor printed no '$key' row:\n$output"
    [[ "$row" == *unknown* ]] || fail "the install's '$key' row does not say unknown: $row"
    [[ "$row" != *"$1"* ]] || fail "the install's '$key' row reads the project's $1: $row"
  done
  assert_output_contains "ok    version: $1, from VERSION (project.version_from)"
}

@test "an install whose manifest names no version runs unknown, never the project's own VERSION (0159)" {
  local m entries
  proj="$(mkinstalled)"
  m="$proj/bin/.devbin/manifest.sha256"
  entries="$(grep -v '^#' "$m")"
  # The project's own number, which must never answer for devbin's.
  printf '7.7.7\n' >"$proj/VERSION"
  # Cut to nothing, as an interrupted rewrite leaves it.
  : >"$m"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "devbin_version: running unknown"
  _install_rows_unknown 7.7.7
  # Its fix is the manifest's: a plain upgrade refuses a manifest that records
  # no files, as it refuses a missing one.
  assert_output_contains "fix: see manifest below -- the manifest at bin/.devbin/manifest.sha256 records no files, and a plain upgrade refuses until it does"
  # Recording its files, with the header's version line gone.
  printf '%s\n' "$entries" >"$m"
  run devbin_run "$proj" doctor
  assert_output_contains "devbin_version: running unknown"
  _install_rows_unknown 7.7.7
}

@test "doctor FAILS by name when devbin's own catalogue cannot be read, and never passes shadowing (0159)" {
  proj="$(mkinstalled)"
  # One row devbin cannot read, as a damaged catalogue would leave it. The
  # read's status was thrown away, the row's shadow dropped, and doctor passed
  # "no project name stands where devbin ships its own".
  cat >>"$proj/bin/.devbin/lib/builtins" <<'EOF'
eval "_planted_$(declare -f builtin_option_run)"
builtin_option_run() { [ "$1 $2" != "fmt elixir" ] || return 1; _planted_builtin_option_run "$@"; }
EOF
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "cannot read devbin's catalogue row for fmt elixir"
  assert_output_contains "FAIL  shadowing: devbin's own catalogue could not be read"
  refute_output_contains "no project name stands where devbin ships its own"
}

@test "doctor catches a handler that is not executable" {
  proj="$(mkinstalled)"
  # It resolves to nothing: known_commands requires -x, so the command simply
  # is not there and nothing anywhere says why.
  printf '#!/usr/bin/env bash\necho hi\n' >"$proj/bin/.devbin/cmd/greet"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "not executable"
  assert_output_contains greet
}

@test "doctor catches a sub-handler directory with no parent beside it" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/bin/.devbin/cmd/ghost.d"
  printf '#!/usr/bin/env bash\n' >"$proj/bin/.devbin/cmd/ghost.d/sub"
  chmod +x "$proj/bin/.devbin/cmd/ghost.d/sub"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "ghost.d"
}

@test "an executable handler and its .d directory are both fine" {
  proj="$(mkinstalled)"
  printf '#!/usr/bin/env bash\necho hi\n' >"$proj/bin/.devbin/cmd/greet"
  chmod +x "$proj/bin/.devbin/cmd/greet"
  mkdir -p "$proj/bin/.devbin/cmd/greet.d"
  printf '#!/usr/bin/env bash\n' >"$proj/bin/.devbin/cmd/greet.d/loudly"
  chmod +x "$proj/bin/.devbin/cmd/greet.d/loudly"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "every file in cmd/ is reachable"
}

# ============================================================================
# THE VERSION CONSTRAINT (AC-09.13)
# ============================================================================

@test "doctor enforces the devbin_version the project declared" {
  proj="$(mkinstalled)"
  sed 's/devbin_version.*/devbin_version: "^9.0.0"/' "$proj/bin/.devbin/config.yaml" \
    >"$proj/c" && mv "$proj/c" "$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "devbin_version"
  # Both versions, because "does not satisfy" without them sends the reader off
  # to find out which two numbers disagreed.
  assert_output_contains "^9.0.0"
  assert_output_contains "$(cat "$DEVBIN_HOME/VERSION")"
}

@test "a satisfied constraint passes and says which two versions matched" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "satisfies"
}

@test "an undeclared constraint is a note, not a pass and not a failure" {
  proj="$(mkinstalled)"
  grep -v devbin_version "$proj/bin/.devbin/config.yaml" >"$proj/c" &&
    mv "$proj/c" "$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "not declared"
}

# ============================================================================
# CONFIG AND LAUNCHERS (AC-09.10)
# ============================================================================

@test "doctor fails on a config key the schema does not know" {
  proj="$(mkinstalled)"
  printf '\nnonsense_key: true\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "schema does not know"
  assert_output_contains nonsense_key
}

@test "doctor fails on a boolean key holding a word it cannot read, naming the value (0080)" {
  proj="$(mkinstalled)"
  printf '\ncommands:\n  test:\n    enabled: off\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "keys or values the schema does not know"
  assert_output_contains 'commands.test.enabled: "off" is not a yes or a no'
}

@test "a config that fails validation is one FAIL, and doctor still runs and counts every other check (0120)" {
  # Until 0120 the validation report's own pipeline ended doctor at the config
  # check: under pipefail it took cfg_validate's status, 1 on the very failure
  # being reported, and errexit stopped the run there -- exit 1, the later
  # checks never reached, and no count line. A config error is the likeliest
  # reason to run doctor, and that was the case where it hid everything else.
  # THE CONTROL is the same project with its config valid: its count is the
  # number the failing run must reach.
  local base
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  base="$(sed -n 's/^\([0-9]*\) checks, .*/\1/p' <<<"$output")"
  [ -n "$base" ] || fail "no count line with the config valid: $output"
  printf '\nnonsense_key: true\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "keys or values the schema does not know"
  assert_output_contains nonsense_key
  assert_output_contains "$base checks, 1 failed"
}

# AT-1.4
@test "doctor reports a release: block in a project that has not enabled release as declared and inert (ST0007 AC-1.2)" {
  proj="$(mkinstalled)"
  printf '\nrelease:\n  object: none\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "release: a release: block is declared and inert"
  assert_output_contains "commands.release.enabled: true"
}

# AT-1.4
@test "doctor says nothing about release when the block is absent, or when release is enabled (ST0007 AC-1.2)" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "declared and inert"
  printf '\ncommands:\n  release:\n    enabled: true\nrelease:\n  object: none\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "declared and inert"
  # THE CONTROLS, because a refutation also passes over a block nobody read:
  # release is offered, so the enable was read, and release check shows the
  # block's own value as declared.
  run devbin_run "$proj" help
  assert_output_matches '(^|'$'\n'')  release '
  run devbin_run "$proj" release check
  assert_output_matches 'object +none +declared'
}

@test "doctor PASSES on bin/devbin, which is the launcher now" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "launcher: bin/devbin"
}

@test "doctor FAILS when bin/devbin itself is missing" {
  proj="$(mkinstalled)"
  # A vendored file that lost its exec bit is the reachable form of this: the
  # dispatcher cannot report its own total absence, but it can be driven through
  # `bash` while failing its own executability check -- which is a state install
  # can actually produce.
  chmod -x "$proj/bin/devbin"
  run devbin_run_under "$proj" bash doctor
  assert_failure
  assert_output_contains "not executable"
}

@test "a SURVIVING per-project symlink is a note that names the CONDITION, not a command" {
  proj="$(mkinstalled)"
  ln -s devbin "$proj/bin/demo"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "retired alias"
  assert_output_contains "this project's call"
  # NO PASTEABLE DESTRUCTIVE COMMAND. It offered `rm bin/demo` briefly, and a
  # reader said it would have been run: a specific remedy is read as advice
  # regardless of the severity word in front of it.
  refute_output_contains "rm bin/"
}

@test "the note COMPUTES who else would break, rather than cautioning in general" {
  proj="$(mkinstalled)"
  ln -s devbin "$proj/bin/demo"
  # The measured shape: a consumer's bin/<alias> -> <project> -> devbin. Removing the
  # project-named link kills the short one, and that second consumer is
  # invisible to anything that only resolves one hop.
  ln -s demo "$proj/bin/dm"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "WOULD ALSO BREAK"
  assert_output_contains "dm"
}

@test "a retired alias with nothing pointing at it says so by staying quiet" {
  proj="$(mkinstalled)"
  ln -s devbin "$proj/bin/demo"
  run devbin_run "$proj" doctor
  assert_success
  # The negative control: the breakage line must not appear when there is no
  # breakage, or it means nothing when it does.
  refute_output_contains "WOULD ALSO BREAK"
}

# THE TWO NAMES ARE DIFFERENT THINGS: bin/{project} is retired because it
# shadows the binary the project BUILDS; a 2-3 char shortcut pointing DIRECT at
# bin/devbin is a PERMITTED per-project convention. doctor conflated them -- it
# iterated `project.name project.alias` in one loop and called both retired --
# and told projects whose shortcut was correct that it was superseded. Driven in
# Intent, where `int` IS project.alias.
@test "a project.alias shortcut pointing direct at devbin is correct, not retired" {
  proj="$(mkinstalled)"
  awk '/^  name: demo$/{print; print "  alias: dm"; next} {print}' "$proj/bin/.devbin/config.yaml" >"$proj/bin/.devbin/config.new" && mv "$proj/bin/.devbin/config.new" "$proj/bin/.devbin/config.yaml"
  ln -s devbin "$proj/bin/dm"
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "retired alias"
  assert_output_contains "dm"
}

# The chained form is the one that IS a problem, and it is the only alias shape
# the retirement can break: bin/<alias> -> <project> -> devbin dies when the
# project-named link goes.
@test "an alias CHAINED through the project name is reported -- it dies with that link" {
  proj="$(mkinstalled)"
  awk '/^  name: demo$/{print; print "  alias: dm"; next} {print}' "$proj/bin/.devbin/config.yaml" >"$proj/bin/.devbin/config.new" && mv "$proj/bin/.devbin/config.new" "$proj/bin/.devbin/config.yaml"
  ln -s devbin "$proj/bin/demo"
  ln -s demo "$proj/bin/dm"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "chained"
  assert_output_contains "dm"
}

@test "a REAL file at the project name is silent -- that is the expected state now" {
  proj="$(mkinstalled)"
  printf '#!/usr/bin/env bash\necho the project binary\n' >"$proj/bin/demo"
  chmod +x "$proj/bin/demo"
  run devbin_run "$proj" doctor
  assert_success
  # Reporting the correct state as a finding is how a checker stops being read.
  refute_output_contains "RETIRED alias"
  refute_output_contains "bin/demo"
}

@test "doctor names a command that is offered with nothing behind it" {
  proj="$(mkinstalled)"
  # By design the catalogue ships `build` as a NAME with no command line, so
  # it lists, resolves and exits 3. A note rather than a failure -- it is the
  # designed state -- but silence here would leave a command that looks real.
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "offered with nothing to run"
  assert_output_contains build
}

@test "doctor gives each command with nothing to run its own remedy, in the refusal's words (0128)" {
  proj="$(mkinstalled)"
  # `build` is a name devbin ships for the project to fill, so
  # its remedy is the project's to apply. One generic line for the whole list
  # said the same to every name, whatever was actually missing.
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "build: devbin ships the name only -- declare commands.build.run or add bin/.devbin/cmd/build"
  refute_output_contains "each needs commands.<name>.run"
}

@test "doctor's remedy for a built-in whose devbin handler is missing is not to declare a run: (0128)" {
  proj="$(mkinstalled)"
  rm -f "$proj/bin/.devbin/lib/cmd/version"
  run devbin_run "$proj" doctor
  # The missing file fails the manifest check as well, so the run is red; the
  # note is what this arm reads. Declaring a run: would replace devbin's
  # version, when what is wrong is the install (issue 0117).
  assert_output_contains "version: devbin's handler for 'version' is missing from this install"
  refute_output_contains "version: devbin ships the name only"
}

@test "doctor fails a log: that nothing reads, naming each and what runs instead (0133)" {
  # Three dead shapes: a catalogue option with a log: and no run: of its own,
  # which devbin's handler seals under the catalogue's suffix whatever it says;
  # a command devbin implements, whose handler execs; and an option of a command
  # the project's handler owns. check.md and test.md said the first ran unsealed.
  # One live key beside them, so the count of dead keys is not also the total.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      shell:
        log: false
      own:
        run: printf own
        log: OWN
  version:
    log: VERSIONLOG
  hand:
    options:
      one:
        run: printf one
        log: ONE
YAML
  )"
  create_test_command "$proj" hand >/dev/null
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "log: 3 of 4 key(s) read by nothing"
  refute_output_contains "commands.test.options.own.log"
  assert_output_contains "commands.test.options.shell.log: devbin's own test shell seals under SHELL whatever this says"
  assert_output_contains "commands.version.log: devbin's own version runs, from lib/cmd/version"
  assert_output_contains "commands.hand.options.one.log: the project's handler runs hand one"
}

@test "doctor passes every log: a run reads: beside an option's own run:, and on a command's own line (0133)" {
  # The live shapes, and the control for the arm above: the same keys where
  # run_option or run_command reads them. `iex` has no handler of devbin's, so
  # its own line is the catalogue's, and a log: on it seals.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
  languages:
    - shell
commands:
  test:
    options:
      own:
        run: printf own
        log: OWN
  media:
    run: printf media
    log: MEDIA
  iex:
    log: IEXLOG
YAML
  )"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "log: 3 key(s), each where a run reads it"
  refute_output_contains "read by nothing"

  write_config "$proj" <<'YAML'
project:
  name: demo
YAML
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "log: no log: key declared"
}

@test "doctor reports the runtime it is actually using" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "vendored at bin/.devbin/lib"
  # And the other case: this checkout runs from its own lib/, which is a
  # different answer to "which devbin is this" and worth saying out loud.
  run devbin_run "$DEVBIN_HOME" doctor
  assert_output_contains "not installed"
}

# ============================================================================
# THE VERSION LINE, UNCHANGED (docs/dev-opt-brew.md T4; issue 0246)
# ============================================================================

# version_line_alone <line> -- the last run's output holds <line> as a line of
# its own, exactly once, and no line holds it with anything added: no label,
# no path, no indent.
version_line_alone() {
  local whole held
  [ -n "$1" ] || fail "no version line to look for"
  whole="$(grep -xF -- "$1" <<<"$output" || true)"
  held="$(grep -F -- "$1" <<<"$output" || true)"
  [ "$whole" = "$1" ] || fail "doctor did not print exactly one line equal to: $1
$output"
  [ "$held" = "$whole" ] || fail "a doctor line carries the version line with more:
$held"
}

# install_row_holds <proj> <install root> <by> -- doctor in <proj> prints the
# version line <install root>'s own --version prints, alone, and beneath it the
# row saying what chose that install.
install_row_holds() {
  local want row
  run devbin_run "$2" --version
  assert_success
  want="$output"
  run devbin_run "$1" doctor
  version_line_alone "$want"
  row="$(awk -v l="$want" '$0 == l { getline; print; exit }' <<<"$output")"
  [ "$row" = "        install: the line above, named by $3" ] ||
    fail "under the install's version line doctor printed: $row
$output"
}

@test "in devbin's dev tree, doctor's first line is the version line as --version prints it, and no row repeats it, git unreadable included (0246)" {
  local src want
  src="$(mkdevsrc)"
  run devbin_run "$src" --version
  assert_success
  want="$output"
  run devbin_run "$src" doctor
  [ "${lines[0]}" = "$want" ] || fail "doctor's first line is '${lines[0]}', and --version prints '$want'"
  version_line_alone "$want"
  assert_output_contains "ok    tree: the version line above names this checkout's commit"
  # A checkout git cannot read is still the dev tree, its line says unknown
  # for the commit, and the row that fails on it does not repeat the line.
  mv "$src/.git" "$src/.git-moved"
  printf 'gitdir: %s/nowhere\n' "$DEVBIN_TEST_TMPDIR" >"$src/.git"
  run devbin_run "$src" --version
  assert_success
  want="$output"
  [[ "$want" == *"(dev, unknown)" ]] || fail "the fixture's git still reads: $want"
  run devbin_run "$src" doctor
  assert_failure
  [ "${lines[0]}" = "$want" ] || fail "doctor's first line is '${lines[0]}', and --version prints '$want'"
  version_line_alone "$want"
  assert_output_contains "FAIL  tree: git cannot read this checkout, so the version line above names no commit"
}

@test "in a consuming project, doctor prints its install's version line as that tree's --version does, alone, with what chose it on its own row, for opt, dev and brew (0246)" {
  local src proj="$DEVBIN_TEST_TMPDIR/proj" prefix="$DEVBIN_TEST_TMPDIR/opt/devbin"
  local opt="$HOMEBREW_PREFIX/opt/devbin/libexec" link="$HOME/.local/bin/devbin"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  mkdir -p "$proj"
  run devbin_run "$prefix" install --into "$proj" --name demo
  assert_success
  # opt, chosen by the link.
  switch_to "$prefix"
  install_row_holds "$proj" "$prefix" "the link $link"
  # opt, chosen by DEVBIN_INSTALL_PREFIX, with no link.
  rm -f "$link"
  export DEVBIN_INSTALL_PREFIX="$prefix"
  install_row_holds "$proj" "$prefix" DEVBIN_INSTALL_PREFIX
  unset DEVBIN_INSTALL_PREFIX
  # dev, the checkout `use dev` names, chosen by the link.
  switch_to "$src"
  install_row_holds "$proj" "$src" "the link $link"
  # brew, chosen by Homebrew's opt link when nothing else names one: the keg
  # linked, as brew links it, and no link of devbin's.
  brew_keg --from "$src" --linked 0.1.0
  rm -f "$link"
  install_row_holds "$proj" "$opt" "HOMEBREW_PREFIX's opt/devbin, since no DEVBIN_INSTALL_PREFIX or link names one"
}

# ============================================================================
# PROJECT CHECKS: bin/.devbin/cmd/doctor.d/ (issue 0093)
# ============================================================================

# doctor_check <proj> <name> <body> -- an executable project check.
doctor_check() {
  mkdir -p "$1/bin/.devbin/cmd/doctor.d"
  printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/bin/.devbin/cmd/doctor.d/$2"
  chmod +x "$1/bin/.devbin/cmd/doctor.d/$2"
}

@test "a project's checks run after devbin's own, counted into one summary (0093)" {
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  local base line body=""
  base="$(sed -n 's/^\([0-9]*\) checks, .*/\1/p' <<<"$output")"
  # The project check's lines, each one check it reports.
  local -a reports=("ok    rg on PATH" "ok    jq on PATH")
  for line in "${reports[@]}"; do printf -v body '%s echo %q;' "$body" "$line"; done
  doctor_check "$proj" tools "$body"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains dispatcher
  assert_output_contains "tools: rg on PATH"
  assert_output_contains "tools: jq on PATH"
  assert_output_contains "$((base + ${#reports[@]})) checks, 0 failed"
}

@test "a project check's FAIL line fails doctor, and the output around it is kept as detail (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" ssh 'echo "FAIL  host1 unreachable"; echo "      Connection refused"; exit 1'
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "ssh: host1 unreachable"
  assert_output_contains "Connection refused"
  assert_output_contains ", 1 failed"
}

@test "a project check that exits non-zero having printed no FAIL line fails, naming the exit (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" silent 'exit 3'
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "silent: exited 3"
}

@test "a FAIL line fails doctor even when the check exits 0 (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" liar 'echo "FAIL  config missing"; exit 0'
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "liar: config missing"
}

@test "a project check that exits 0 and prints no verdict line counts as one pass, by its name (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" quiet 'true'
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "quiet"
}

@test "doctor <check> runs only that project check, and devbin's own do not run (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" tools 'echo "ok    rg on PATH"'
  doctor_check "$proj" ssh 'echo "FAIL  host1 unreachable"; exit 1'
  run devbin_run "$proj" doctor tools
  assert_success
  assert_output_contains "tools: rg on PATH"
  refute_output_contains "dispatcher"
  refute_output_contains "host1"
  assert_output_contains "1 checks, 0 failed"
  run devbin_run "$proj" doctor nosuch
  assert_failure
  assert_output_contains "unknown argument 'nosuch'"
}

@test "a file in doctor.d that is not executable is a note, not run and not silent (0093)" {
  proj="$(mkinstalled)"
  mkdir -p "$proj/bin/.devbin/cmd/doctor.d"
  printf '#!/usr/bin/env bash\necho "ok    ran"\n' >"$proj/bin/.devbin/cmd/doctor.d/draft"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "draft is not executable"
  refute_output_contains "draft: ran"
}

@test "doctor.d is reachable -- it is doctor's -- so the handlers check does not call it an orphan (0093)" {
  proj="$(mkinstalled)"
  doctor_check "$proj" tools 'echo "ok    fine"'
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "doctor.d/ has no executable"
  assert_output_contains "handlers: every file in cmd/ is reachable"
}

@test "a filled name-only built-in is not reported as shadowing anything; a command devbin ships options for is (0136)" {
  # devbin ships precommit as a name with nothing behind it, so a project's
  # commands.precommit.run fills it; doctor said it shadowed the built-in.
  proj="$(mkinstalled)"
  printf 'commands:\n  precommit:\n    run: echo pre\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  refute_output_contains "precommit shadows the built-in"
  assert_output_contains "shadowing: no project name stands where devbin ships its own"
  # THE CONTROL: test ships options, so a project line for it does take something over.
  printf '  test:\n    run: echo t\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_output_contains "test shadows the built-in"
}

# ============================================================================
# WHERE THE PROJECT SITS UNDER WSL (ST0008, AC-4.2)
# ============================================================================
#
# DEVBIN_WSL drives the probe, and DEVBIN_WSL_MOUNT_ROOT points the drives at a
# directory of the test's own, so each arm runs on any machine. The probe
# itself is asked of a fixture's /proc, never the host's, so it holds on a WSL
# runner as on any other.

# AT-4.2
@test "the WSL probe reads WSL's own marks, and a Linux /proc without them is not WSL (AC-4.2)" {
  fx="$DEVBIN_TEST_TMPDIR/proc"
  mkdir -p "$fx/sys/fs/binfmt_misc" "$fx/sys/kernel"
  printf '6.8.0-45-generic\n' >"$fx/sys/kernel/osrelease"
  run _wsl_probe "$fx"
  assert_failure
  : >"$fx/sys/fs/binfmt_misc/WSLInterop"
  run _wsl_probe "$fx"
  assert_success
  rm "$fx/sys/fs/binfmt_misc/WSLInterop"
  : >"$fx/sys/fs/binfmt_misc/WSLInterop-late"
  run _wsl_probe "$fx"
  assert_success
  rm "$fx/sys/fs/binfmt_misc/WSLInterop-late"
  printf '5.15.153.1-microsoft-standard-WSL2' >"$fx/sys/kernel/osrelease"
  run _wsl_probe "$fx"
  assert_success
}

# AT-4.2
@test "under WSL, a project on a Windows drive is a note naming the drive, the cause and the fix, and doctor does not fail on it (AC-4.2)" {
  export DEVBIN_WSL=1 DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/mnt"
  proj="$DEVBIN_TEST_TMPDIR/mnt/c/work/demo"
  install_devbin_starter "$proj"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "note  location: $proj is on the Windows drive at $DEVBIN_TEST_TMPDIR/mnt/c, under WSL"
  assert_output_contains "cause: WSL reaches $DEVBIN_TEST_TMPDIR/mnt/c through its bridge to Windows"
  assert_output_contains "fix: clone the project again inside WSL's own filesystem"
  assert_output_contains ", 0 failed"
}

# AT-4.2
@test "under WSL, a mount root written with trailing slashes, or reached through a link, still finds the drive (AC-4.2)" {
  export DEVBIN_WSL=1
  proj="$DEVBIN_TEST_TMPDIR/mnt/e/demo"
  install_devbin_starter "$proj"
  DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/mnt//" run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "on the Windows drive at $DEVBIN_TEST_TMPDIR/mnt/e, under WSL"
  ln -s "$DEVBIN_TEST_TMPDIR/mnt" "$DEVBIN_TEST_TMPDIR/win"
  DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/win" run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "on the Windows drive at $DEVBIN_TEST_TMPDIR/mnt/e, under WSL"
}

# AT-4.2
@test "under WSL, a link from WSL's own filesystem to a project on a drive is read as the drive (AC-4.2)" {
  export DEVBIN_WSL=1 DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/mnt"
  proj="$DEVBIN_TEST_TMPDIR/mnt/d/demo"
  install_devbin_starter "$proj"
  ln -s "$proj" "$DEVBIN_TEST_TMPDIR/linked"
  run devbin_run "$DEVBIN_TEST_TMPDIR/linked" doctor
  assert_success
  assert_output_contains "on the Windows drive at $DEVBIN_TEST_TMPDIR/mnt/d, under WSL"
}

# AT-4.2
@test "under WSL, a project in WSL's own filesystem passes the location check, and a name of more than one letter under the mount root is no drive (AC-4.2)" {
  export DEVBIN_WSL=1 DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/mnt"
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_success
  assert_output_contains "ok    location: $proj is inside WSL's own filesystem"
  near="$DEVBIN_TEST_TMPDIR/mnt/cd/demo"
  install_devbin_starter "$near"
  run devbin_run "$near" doctor
  assert_success
  assert_output_contains "ok    location: $near is inside WSL's own filesystem"
}

# AT-4.2
@test "off WSL, doctor says nothing of where the project sits, a path like a drive's included (AC-4.2)" {
  export DEVBIN_WSL=0 DEVBIN_WSL_MOUNT_ROOT="$DEVBIN_TEST_TMPDIR/mnt"
  proj="$DEVBIN_TEST_TMPDIR/mnt/c/demo"
  install_devbin_starter "$proj"
  run devbin_run "$proj" doctor
  assert_success
  refute_output_contains "location:"
}

# AT-4.2
@test "a DEVBIN_WSL that is neither 1 nor 0 is refused by name before any row, never read as either (AC-4.2)" {
  export DEVBIN_WSL=yes
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "DEVBIN_WSL must be 1 or 0, not 'yes'"
  refute_output_contains "dispatcher:"
}

@test "doctor's switch check says nothing of a shadow when ~/.local/bin is first on PATH in another case, where the disk folds case (0247)" {
  require_folded_local_bin "doctor's shadow check past ~/.LOCAL/bin"
  proj="$(mkinstalled)"
  switch_to "$(mkdevsrc)"
  PATH="$HOME/.LOCAL/bin:$PATH" run devbin_run "$proj" doctor
  refute_output_contains "is shadowed"
  refute_output_contains "FAIL  switch"
  assert_output_contains "switch: the link names"
}

@test "doctor's switch check says nothing of a shadow when the first devbin on PATH is a link through the link, which runs the link's tree (0285)" {
  proj="$(mkinstalled)"
  switch_to "$(mkdevsrc)"
  mkdir -p "$HOME/bin" && ln -s ../.local/bin/devbin "$HOME/bin/devbin" || fail "the fixture's ~/bin/devbin failed"
  PATH="$HOME/bin:$HOME/.local/bin:$PATH" run devbin_run "$proj" doctor
  refute_output_contains "is shadowed"
  refute_output_contains "FAIL  switch"
  assert_output_contains "switch: the link names"
}

# ============================================================================
# THE SWITCH ROW WITH NO LINK AND NO HOMEBREW DEVBIN (issue 0250)
# ============================================================================

@test "with no link and no Homebrew devbin, doctor's switch row notes what is missing, why in brew_unplaced_why's words, and the remedy for that cause, never passing as brew (0250)" {
  local export_fix="export HOMEBREW_PREFIX in the profile this process reads, as brew shellenv exports it"
  proj="$(mkinstalled)"
  run devbin_run "$proj" doctor
  assert_output_contains "note  switch: no link, and Homebrew has no devbin here (no devbin at $HOMEBREW_PREFIX/opt/devbin/libexec, under HOMEBREW_PREFIX)"
  assert_output_contains $'\n'"        install devbin with Homebrew"$'\n'
  refute_output_contains "switch: no link, so brew"
  refute_output_contains "export HOMEBREW_PREFIX"
  HOMEBREW_PREFIX=relative/brew run devbin_run "$proj" doctor
  assert_output_contains "note  switch: no link, and Homebrew has no devbin here (HOMEBREW_PREFIX, 'relative/brew', is not an absolute path)"
  assert_output_contains $'\n'"        $export_fix"$'\n'
  refute_output_contains "switch: no link, so brew"
  refute_output_contains "install devbin"
  unset HOMEBREW_PREFIX
  run devbin_run "$proj" doctor
  assert_output_contains "note  switch: no link, and Homebrew has no devbin here (HOMEBREW_PREFIX is not set)"
  assert_output_contains $'\n'"        $export_fix"$'\n'
  refute_output_contains "switch: no link, so brew"
  refute_output_contains "install devbin"
}

@test "with no link, no Homebrew devbin and DEVBIN_INSTALL_PREFIX set, doctor's switch row names the variable's install and gives no Homebrew remedy (0250)" {
  local install="$DEVBIN_TEST_TMPDIR/elsewhere/devbin"
  proj="$(mkinstalled)"
  mkdir -p "$install"
  DEVBIN_INSTALL_PREFIX="$install" run devbin_run "$proj" doctor
  assert_output_contains "note  switch: no link, and Homebrew has no devbin here (no devbin at $HOMEBREW_PREFIX/opt/devbin/libexec, under HOMEBREW_PREFIX); DEVBIN_INSTALL_PREFIX names $install as this machine's install"$'\n'
  refute_output_contains "install devbin with Homebrew"
  refute_output_contains "export HOMEBREW_PREFIX"
}
