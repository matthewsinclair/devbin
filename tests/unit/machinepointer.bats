#!/usr/bin/env bats
# machinepointer.bats - a manifest records the KIND of its source, and the
# machine records where the next upgrade reads (issues 0153, 0213).
#
# The manifest is tracked in every project that vendors devbin, and the path it
# recorded as its source named the operator's directory layout in each of them,
# deliveries to clients included. So a manifest says `install`, `checkout` or
# `project`, and the place comes from this machine's switch, for every kind:
# DEVBIN_INSTALL_PREFIX, else the tree the link ~/.local/bin/devbin leads to
# (`devbin use`), else Homebrew's install. A link that cannot be trusted is said
# to be so, never read as no link at all. The machine pointer this file was
# named for is retired: nothing reads it, and doctor names one left on disk
# (use.bats).

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  PREFIX="$DEVBIN_TEST_TMPDIR/opt/devbin"
}

teardown() { devbin_teardown; }

# fake_install <dir> -- a tree that declares itself an install, enough for the
# switch's own check; nothing here runs it.
fake_install() {
  # A launcher for the link to reach (0213): the switch follows the link to
  # <root>/bin/devbin. Nothing here runs it. Written by the one stub writer
  # (0288).
  stub_install "$1" checkout
}

# recording <dir> <source-line> -- a project manifest whose source line is this.
recording() {
  mkdir -p "$1/bin/.devbin"
  printf '# devbin_version: 0.1.0\n# source: %s\n# source_commit: aaaabbbbccccdddd\n' "$2" \
    >"$1/bin/.devbin/manifest.sha256"
}

@test "the suite's link and data directory are the test's own, and no source override leaks in (0153, 0213)" {
  # A `use` in an arm writes the link. Under the runner's own HOME that is the
  # link every project on the machine reads to find devbin. On a clean runner
  # nothing leaks, so the arm plants what a careless one would export and
  # watches the isolation take it away.
  #
  # devbin_setup has already run, so the machine is the test's own before
  # anything is planted: without this line the arm holds the function and
  # never the setup's call of it.
  [ "${XDG_DATA_HOME:-}" = "$DEVBIN_TEST_TMPDIR/.xdg-data" ] ||
    fail "devbin_setup left XDG_DATA_HOME as: ${XDG_DATA_HOME:-unset}"
  [ "${HOMEBREW_PREFIX:-}" = "$DEVBIN_TEST_TMPDIR/.homebrew" ] ||
    fail "devbin_setup left HOMEBREW_PREFIX as: ${HOMEBREW_PREFIX:-unset}"
  export XDG_DATA_HOME="$DEVBIN_TEST_TMPDIR/runner-data" DEVBIN_INSTALL_PREFIX=/leaked/prefix DEVBIN_SOURCE=/leaked/source \
    HOMEBREW_PREFIX=/leaked/homebrew
  devbin_isolate_machine
  [[ "$(devbin_home_pointer)" == "$DEVBIN_TEST_TMPDIR/.xdg-data/"* ]] ||
    fail "the retired pointer is not looked for in the test's own data: $(devbin_home_pointer)"
  [ "$(devbin_link_path)" = "$DEVBIN_TEST_TMPDIR/home/.local/bin/devbin" ] ||
    fail "the link is not the test's own: $(devbin_link_path)"
  [ -z "${DEVBIN_INSTALL_PREFIX:-}" ] || fail "DEVBIN_INSTALL_PREFIX leaked in: $DEVBIN_INSTALL_PREFIX"
  [ -z "${DEVBIN_SOURCE:-}" ] || fail "DEVBIN_SOURCE leaked in: $DEVBIN_SOURCE"
  # Homebrew's install is the default once nothing else names one (0195), so a
  # runner's real prefix must not reach an arm either.
  [ "$HOMEBREW_PREFIX" = "$DEVBIN_TEST_TMPDIR/.homebrew" ] || fail "HOMEBREW_PREFIX leaked in: $HOMEBREW_PREFIX"
}

@test "every scrubbed environment in the suite keeps the test's machine pointer (0153)" {
  # `env -i` drops XDG_DATA_HOME, so an arm that hands HOME through it and runs
  # devbin there reads, and could write, the runner's own pointer. Every such
  # call hands XDG_DATA_HOME through as well. A call continued with a backslash
  # is read whole, so HOME= on a later line of it is seen.
  local hits bad probe="$DEVBIN_TEST_TMPDIR/scanprobe"
  _scrubbed_calls() {
    find "$1" -type f ! -name machinepointer.bats -print0 | xargs -0 awk '
      FNR == 1 { buf = "" }
      {
        line = (buf == "" ? $0 : buf " " $0)
        if (line ~ /\\$/) { buf = substr(line, 1, length(line) - 1); next }
        buf = ""
        if (line ~ /env -i[^#]*HOME=/) print FILENAME ":" FNR ": " line
      }'
  }
  # POSITIVE CONTROL: a call whose HOME= is on its continued line is found.
  mkdir -p "$probe"
  printf 'run env -i PATH="$PATH" \\\n  HOME="$HOME" bash -c true\n' >"$probe/continued.bats"
  [ -n "$(_scrubbed_calls "$probe")" ] || fail "the scan missed an env -i whose HOME= is on a continued line"
  hits="$(_scrubbed_calls "$DEVBIN_HOME/tests")" || true
  [ -n "$hits" ] || fail "no env -i call in tests/ passes HOME, so this scan would check nothing"
  bad="$(printf '%s\n' "$hits" | grep -v -F 'XDG_DATA_HOME=')" || true
  [ -z "$bad" ] || fail "env -i passes HOME without XDG_DATA_HOME:
$bad"
}

@test "the retired pointer is looked for under an absolute XDG_DATA_HOME, else ~/.local/share, and an empty HOME locates none (0153)" {
  [ "$(XDG_DATA_HOME=/x/data devbin_home_pointer)" = /x/data/devbin/home ]
  [ "$(XDG_DATA_HOME=relative HOME="$DEVBIN_TEST_TMPDIR/h" devbin_home_pointer)" = "$DEVBIN_TEST_TMPDIR/h/.local/share/devbin/home" ]
  [ "$(XDG_DATA_HOME= HOME="$DEVBIN_TEST_TMPDIR/h/" devbin_home_pointer)" = "$DEVBIN_TEST_TMPDIR/h/.local/share/devbin/home" ]
  run env XDG_DATA_HOME= HOME= bash -c '. "$1/helpers" && devbin_home_pointer' _ "$DEVBIN_LIB_DIR"
  [ "$status" -eq 1 ] || fail "an empty HOME located a pointer: $output"
  [ -z "$output" ]
}

@test "a project records the KIND of its source, never a place (0153)" {
  local src proj
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  [ "$(header_of "$proj" source)" = checkout ] || fail "vendored from a checkout, it records: $(header_of "$proj" source)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$proj" upgrade --from "$PREFIX"
  assert_success
  [ "$(header_of "$proj" source)" = install ] || fail "vendored from an install, it records: $(header_of "$proj" source)"
  # No source line names a place: no slash, no tilde.
  ! grep -E '^# source: .*[/~]' "$(manifest_of "$proj")" || fail "the manifest records a place"
}

@test "the writer names each kind of tree it vendors from, and refuses one it cannot tell (0153)" {
  local src proj="$DEVBIN_TEST_TMPDIR/proj" bare="$DEVBIN_TEST_TMPDIR/bare"
  fake_install "$DEVBIN_TEST_TMPDIR/inst"
  src="$(mkdevsrc)"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  [ "$(manifest_source_token "$DEVBIN_TEST_TMPDIR/inst")" = install ]
  [ "$(manifest_source_token "$src")" = checkout ]
  [ "$(manifest_source_token "$proj")" = project ]
  # A vendored runtime with no manifest may be an install that lost it: a
  # project would be the wrong word, and every later upgrade would say why
  # wrongly.
  mkdir -p "$bare/bin/.devbin/lib"
  printf '#!/usr/bin/env bash\n' >"$bare/bin/devbin"
  run manifest_source_token "$bare"
  assert_failure
  assert_output_contains "cannot tell what kind of tree $bare is"
}

# lost_tree <dir> <src> -- a project vendored from <src> that has lost its
# manifest: a runtime that works, and no word for what kind of tree it is.
lost_tree() {
  mkdir -p "$1"
  devbin_run "$2" install --into "$1" --name lost >/dev/null 2>&1 || return 1
  rm "$1/bin/.devbin/manifest.sha256"
}

@test "install --into from a tree that cannot say what it is refuses before it writes (0153)" {
  local src lost="$DEVBIN_TEST_TMPDIR/lost" target="$DEVBIN_TEST_TMPDIR/target"
  src="$(mkdevsrc)"
  lost_tree "$lost" "$src" || fail "the fixture could not vendor $lost"
  mkdir -p "$target"
  # Its usage refusals come first, as upgrade's do: a flag this mode cannot use
  # is said as that, never as the source's kind.
  run devbin_run "$lost" install --into "$target" --prefix "$DEVBIN_TEST_TMPDIR/p"
  assert_failure
  assert_output_contains "--prefix applies only when publishing"
  refute_output_contains "cannot tell what kind of tree"
  run devbin_run "$lost" install --into "$target" --name demo
  assert_failure
  assert_output_contains "cannot tell what kind of tree $lost is"
  # Refused at the manifest's write, it left a runtime with no manifest here.
  [ -z "$(ls -A "$target")" ] || fail "the refused install wrote into the target: $(ls -A "$target")"
}

@test "upgrade --from a tree that cannot say what it is refuses before it writes (0153)" {
  local src lost="$DEVBIN_TEST_TMPDIR/lost" proj="$DEVBIN_TEST_TMPDIR/proj" kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  src="$(mkdevsrc)"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  lost_tree "$lost" "$src" || fail "the fixture could not vendor $lost"
  # Bytes the upgrade would copy, so a copy made before the refusal shows.
  printf '\n# moved on\n' >>"$lost/bin/.devbin/lib/builtins"
  cp "$proj/bin/.devbin/lib/builtins" "$kept"
  run devbin_run "$proj" upgrade --from "$lost"
  assert_failure
  assert_output_contains "cannot tell what kind of tree $lost is"
  # Refused at the manifest's write, it left new bytes under the old manifest,
  # which doctor then reads as edited in place.
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refused upgrade replaced builtins"
}

@test "every kind resolves through DEVBIN_INSTALL_PREFIX, else the link, else nothing (0153, 0213)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" kind
  fake_install "$PREFIX"
  for kind in install checkout project; do
    recording "$proj" "$kind"
    rm -f "$HOME/.local/bin/devbin"
    run manifest_source "$proj"
    [ "$status" -eq 1 ] || fail "$kind: with no link and no override it resolved: $output"
    [ -z "$output" ]
    mkdir -p "$HOME/.local/bin"
    ln -s "$PREFIX/bin/devbin" "$HOME/.local/bin/devbin"
    run manifest_source "$proj"
    assert_success
    [ "$output" = "$(cd -P "$PREFIX" && pwd -P)" ] || fail "$kind: the link gave: $output"
    DEVBIN_INSTALL_PREFIX="$DEVBIN_TEST_TMPDIR/elsewhere" run manifest_source "$proj"
    assert_success
    [ "$output" = "$DEVBIN_TEST_TMPDIR/elsewhere" ] || fail "$kind: the override did not win: $output"
  done
}

@test "a link that cannot be trusted is reported by name, never read as absent (0153, 0213)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" l="$HOME/.local/bin/devbin" state
  recording "$proj" install
  mkdir -p "$HOME/.local/bin" "$DEVBIN_TEST_TMPDIR/notaninstall/bin"
  # A link to nothing is there, and cannot be followed: bad, not absent.
  ln -s "$DEVBIN_TEST_TMPDIR/nothing-here/bin/devbin" "$l"
  run manifest_source "$proj"
  [ "$status" -eq 2 ] || fail "a dangling link returned $status: $output"
  assert_output_contains "the link $l leads to no file it can follow"
  rm "$l"
  # A file where the link belongs is no choice devbin use made.
  printf 'x\n' >"$l"
  run manifest_source "$proj"
  [ "$status" -eq 2 ] || fail "a file in the link's place returned $status: $output"
  assert_output_contains "$l is not a link"
  rm "$l"
  # A link to a file that is no tree's bin/devbin.
  printf 'x\n' >"$DEVBIN_TEST_TMPDIR/tool"
  ln -s "$DEVBIN_TEST_TMPDIR/tool" "$l"
  run manifest_source "$proj"
  [ "$status" -eq 2 ] || fail "a link to no bin/devbin returned $status: $output"
  assert_output_contains "which is no devbin tree's bin/devbin"
  rm "$l"
  # A link to a tree that is neither an install nor devbin's checkout.
  printf 'x\n' >"$DEVBIN_TEST_TMPDIR/notaninstall/bin/devbin"
  ln -s "$DEVBIN_TEST_TMPDIR/notaninstall/bin/devbin" "$l"
  run manifest_source "$proj"
  [ "$status" -eq 2 ] || fail "a link to no install returned $status: $output"
  assert_output_contains "which is not a devbin install or checkout"
  # And the notice, the offer and doctor read that reason, not "no source".
  state="$(devbin_source_state "$proj")"
  [[ "$state" == "unknown the link $l names $(cd -P "$DEVBIN_TEST_TMPDIR/notaninstall" && pwd -P), which is not a devbin install or checkout" ]] ||
    fail "devbin_source_state said: $state"
}

@test "an unplaced source says what this machine is missing, the same for every kind, and a recorded path still reads (0153, 0213)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" kind want
  want="unknown this machine names no devbin install: no link at $HOME/.local/bin/devbin, DEVBIN_INSTALL_PREFIX is not set, and"
  for kind in install checkout project; do
    recording "$proj" "$kind"
    [[ "$(devbin_source_state "$proj")" == "$want"* ]] || fail "$kind: $(devbin_source_state "$proj")"
  done
  # DEVBIN_SOURCE places no recorded source any more: it is dvb's fallback alone.
  recording "$proj" checkout
  DEVBIN_SOURCE="$DEVBIN_TEST_TMPDIR/src/bin/devbin" run manifest_source "$proj"
  [ "$status" -eq 1 ] || fail "DEVBIN_SOURCE placed a recorded checkout: $output"
  # A manifest written before 0153 still resolves, until an upgrade this
  # runtime runs writes the kind (0178).
  recording "$proj" "$DEVBIN_TEST_TMPDIR/old/devbin"
  [ "$(manifest_source "$proj")" = "$DEVBIN_TEST_TMPDIR/old/devbin" ]
  HOME="$DEVBIN_TEST_TMPDIR" recording "$proj" '~/opt/devbin'
  [ "$(HOME="$DEVBIN_TEST_TMPDIR" manifest_source "$proj")" = "$DEVBIN_TEST_TMPDIR/opt/devbin" ]
}

@test "a bare upgrade or vendor whose source this machine cannot place refuses, and says why (0153, 0213)" {
  # The case where nothing resolves: vendored from a checkout, on a machine
  # whose switch names nothing. Each verb refuses with what is missing here,
  # and asks for --from, rather than reading the record as absent.
  local src proj="$DEVBIN_TEST_TMPDIR/proj"
  src="$(mkdevsrc)"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "this machine names no devbin install: no link at $HOME/.local/bin/devbin"
  assert_output_contains "name one with --from <dir>"
  run devbin_run "$proj" vendor
  assert_failure
  assert_output_contains "this machine names no devbin install: no link at $HOME/.local/bin/devbin"
}

# THE REMEDY IS THE CAUSE'S (0250). With HOMEBREW_PREFIX unset or relative,
# devbin may be installed and only this process cannot see it, so the remedy
# is the export brew shellenv makes, never an install; under an absolute prefix
# holding no devbin, it is installing devbin with Homebrew. dev and opt are the
# maintainer's (issue 0250): only a dev or opt tree adds them, by the
# checkout's own bin/devbin.
EXPORT_FIX="export HOMEBREW_PREFIX in the profile this process reads, as brew shellenv exports it"
UNTIL_NAMED="so this project's next upgrade will ask for --from until one is named:"

@test "vendoring on a machine naming no install gives exporting HOMEBREW_PREFIX as the remedy when it is unset or relative, never installing devbin, and installing it under an absolute prefix holding none (0250)" {
  local src
  src="$(mkdevsrc)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/p-abs" "$DEVBIN_TEST_TMPDIR/p-unset" "$DEVBIN_TEST_TMPDIR/p-rel"
  run devbin_run "$src" install --into "$DEVBIN_TEST_TMPDIR/p-abs" --name demo
  assert_success
  assert_output_contains "(no devbin at $HOMEBREW_PREFIX/opt/devbin/libexec, under HOMEBREW_PREFIX), $UNTIL_NAMED install devbin with Homebrew"
  refute_output_contains "export HOMEBREW_PREFIX"
  unset HOMEBREW_PREFIX
  run devbin_run "$src" install --into "$DEVBIN_TEST_TMPDIR/p-unset" --name demo
  assert_success
  assert_output_contains "(HOMEBREW_PREFIX is not set), $UNTIL_NAMED $EXPORT_FIX"
  refute_output_contains "install devbin"
  HOMEBREW_PREFIX=relative/brew run devbin_run "$src" install --into "$DEVBIN_TEST_TMPDIR/p-rel" --name demo
  assert_success
  assert_output_contains "(HOMEBREW_PREFIX, 'relative/brew', is not an absolute path), $UNTIL_NAMED $EXPORT_FIX"
  refute_output_contains "install devbin"
}

@test "vendoring's note names the checkout's bin/devbin use dev or opt when a dev or an opt tree vendors, and from a keg names neither (0250)" {
  local src keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" checkout="or run bin/devbin use dev or opt in your devbin checkout"
  brew_keg 0.1.0
  src="$(mkdevsrc optsrc)"
  run devbin_run "$src" install
  assert_success
  mkdir -p "$DEVBIN_TEST_TMPDIR/p-dev" "$DEVBIN_TEST_TMPDIR/p-opt" "$DEVBIN_TEST_TMPDIR/p-keg"
  # The keg is there, and no HOMEBREW_PREFIX finds it: a process without the
  # login profile.
  unset HOMEBREW_PREFIX
  run devbin_run "$src" install --into "$DEVBIN_TEST_TMPDIR/p-dev" --name demo
  assert_success
  assert_output_contains "$UNTIL_NAMED $EXPORT_FIX, $checkout"
  refute_output_contains "run devbin use"
  run bash -c 'cd "$1" && "$2" install --into "$3" --name demo </dev/null' _ "$DEVBIN_TEST_TMPDIR" "$PREFIX/bin/devbin" "$DEVBIN_TEST_TMPDIR/p-opt"
  assert_success
  assert_output_contains "$UNTIL_NAMED $EXPORT_FIX, $checkout"
  refute_output_contains "run devbin use"
  refute_output_contains "$PREFIX/bin/devbin use"
  run "$keg/libexec/bin/devbin" install --into "$DEVBIN_TEST_TMPDIR/p-keg" --name demo
  assert_success
  assert_output_contains "$UNTIL_NAMED $EXPORT_FIX"
  refute_output_contains "use dev"
  refute_output_contains "use opt"
  refute_output_contains "dev or opt"
}

@test "with HOMEBREW_PREFIX unset or relative, a bare vendor and upgrade refuse giving the export beside --from, and under an absolute prefix holding none installing devbin (0250)" {
  local src verb proj="$DEVBIN_TEST_TMPDIR/proj"
  src="$(mkdevsrc)"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  for verb in upgrade vendor; do
    run devbin_run "$proj" "$verb"
    assert_failure
    assert_output_contains "under HOMEBREW_PREFIX -- install devbin with Homebrew, or name one with --from <dir>"
    HOMEBREW_PREFIX=relative/brew run devbin_run "$proj" "$verb"
    assert_failure
    assert_output_contains "HOMEBREW_PREFIX, 'relative/brew', is not an absolute path -- $EXPORT_FIX, or name one with --from <dir>"
    refute_output_contains "install devbin"
  done
  unset HOMEBREW_PREFIX
  for verb in upgrade vendor; do
    run devbin_run "$proj" "$verb"
    assert_failure
    assert_output_contains "HOMEBREW_PREFIX is not set -- $EXPORT_FIX, or name one with --from <dir>"
    refute_output_contains "install devbin"
  done
}

@test "a publish moves no project until use opt names it, and a bare upgrade then finds the install (0153, 0213)" {
  local src proj
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  [ ! -e "$XDG_DATA_HOME/devbin/home" ] || fail "the publish wrote a machine pointer"
  [ ! -e "$HOME/.local/bin/devbin" ] && [ ! -L "$HOME/.local/bin/devbin" ] || fail "the publish wrote the link"
  proj="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  run devbin_run "$proj" upgrade --from "$PREFIX"
  assert_success
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "this machine names no devbin install"
  run devbin_run "$src" use opt
  assert_success
  # No --from: the kind is read, and the switch places it.
  run devbin_run "$proj" upgrade
  assert_success
}

# A publish to any prefix writes no record of the machine's choice now (0213):
# what these arms held of the pointer -- a scratch publish repoints nothing, a
# record that cannot be written fails by name, a record that is a link is not
# written through -- use.bats holds of the link, the one record, which only
# `devbin use` writes.

@test "vendoring from a tree the switch does not name says where a bare upgrade will look (0153, 0213)" {
  local src proj="$DEVBIN_TEST_TMPDIR/proj" other="$DEVBIN_TEST_TMPDIR/other/devbin"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$src" use opt
  assert_success
  run devbin_run "$src" install --prefix "$other"
  assert_success
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  run devbin_run "$proj" upgrade --from "$other"
  assert_success
  assert_output_contains "$other is not the tree this machine's devbin link names"
  assert_output_contains "this project's next upgrade reads $(cd -P "$PREFIX" && pwd -P)"
  run devbin_run "$proj" upgrade --from "$PREFIX"
  assert_success
  refute_output_contains "is not the tree this machine's devbin link names"
  # The install named through a link is still the install: the two are
  # compared as files, not as spellings.
  ln -s "$PREFIX" "$DEVBIN_TEST_TMPDIR/via-link"
  run devbin_run "$proj" upgrade --from "$DEVBIN_TEST_TMPDIR/via-link"
  assert_success
  refute_output_contains "is not the tree this machine's devbin link names"
  rm "$HOME/.local/bin/devbin"
  run devbin_run "$proj" upgrade --from "$other"
  assert_success
  assert_output_contains "this machine names no devbin install"
  # A link it cannot trust is said with its reason, never as none.
  ln -s "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$HOME/.local/bin/devbin"
  run devbin_run "$proj" upgrade --from "$other"
  assert_success
  assert_output_contains "the link $HOME/.local/bin/devbin leads to no file it can follow"
  refute_output_contains "names no devbin install"
  # And an install DEVBIN_INSTALL_PREFIX names is said as the variable's, since
  # the link has no say while it is set.
  rm "$HOME/.local/bin/devbin"
  export DEVBIN_INSTALL_PREFIX="$PREFIX"
  run devbin_run "$proj" upgrade --from "$other"
  assert_success
  assert_output_contains "$other is not the tree DEVBIN_INSTALL_PREFIX names"
  unset DEVBIN_INSTALL_PREFIX
}

@test "a bare upgrade or vendor refused the source DEVBIN_INSTALL_PREFIX places says the variable named it (0153)" {
  # Taken as given, the variable's tree is asked only whether it is a source,
  # and the refusal is the one place that can say where it came from.
  local src proj="$DEVBIN_TEST_TMPDIR/proj" stray="$DEVBIN_TEST_TMPDIR/not-devbin"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  mkdir -p "$proj" "$stray"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  run devbin_run "$proj" upgrade --from "$PREFIX"
  assert_success
  [ "$(header_of "$proj" source)" = install ] || fail "the fixture records: $(header_of "$proj" source)"
  export DEVBIN_INSTALL_PREFIX="$stray"
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "not a devbin source: $stray"
  assert_output_contains "DEVBIN_INSTALL_PREFIX names it as this machine's devbin install"
  run devbin_run "$proj" vendor
  assert_failure
  assert_output_contains "not a devbin source: $stray"
  assert_output_contains "DEVBIN_INSTALL_PREFIX names it as this machine's devbin install"
  # --from names the source itself, so the variable has nothing to answer for.
  run devbin_run "$proj" upgrade --from "$stray"
  assert_failure
  assert_output_contains "not a devbin source: $stray"
  refute_output_contains "DEVBIN_INSTALL_PREFIX names it"
  unset DEVBIN_INSTALL_PREFIX
}

@test "a bare upgrade refusing a devbin with no manifest that DEVBIN_INSTALL_PREFIX places says the variable named it (0178)" {
  # The variable's tree is asked whether it is a source and then what kind of
  # tree it is. A devbin that has lost its manifest passes the first and was
  # refused at the second, and that refusal never named the variable.
  local src proj="$DEVBIN_TEST_TMPDIR/proj" bare="$DEVBIN_TEST_TMPDIR/bare"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name demo
  assert_success
  run devbin_run "$proj" upgrade --from "$PREFIX"
  assert_success
  [ "$(header_of "$proj" source)" = install ] || fail "the fixture records: $(header_of "$proj" source)"
  cp -R "$PREFIX" "$bare"
  rm "$bare/bin/.devbin/manifest.sha256"
  export DEVBIN_INSTALL_PREFIX="$bare"
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "cannot tell what kind of tree $bare is"
  assert_output_contains "DEVBIN_INSTALL_PREFIX names it as this machine's devbin install"
  # --from names the source itself, so the variable has nothing to answer for.
  run devbin_run "$proj" upgrade --from "$bare"
  assert_failure
  assert_output_contains "cannot tell what kind of tree $bare is"
  refute_output_contains "DEVBIN_INSTALL_PREFIX names it"
  # vendor refuses a tree that is no devbin through the same note, under the
  # same rule: a --from names the source, so the variable is not named.
  mkdir -p "$DEVBIN_TEST_TMPDIR/not-devbin"
  run devbin_run "$proj" vendor --from "$DEVBIN_TEST_TMPDIR/not-devbin"
  assert_failure
  assert_output_contains "not a devbin source: $DEVBIN_TEST_TMPDIR/not-devbin"
  refute_output_contains "DEVBIN_INSTALL_PREFIX names it"
  unset DEVBIN_INSTALL_PREFIX
}

@test "a tree whose manifest cannot be read is named as that, by the writer and by the switch (0153, 0213)" {
  # Read as a field it could not find, it was a tree with no manifest, or one
  # that is no install; elsewhere devbin refuses such a manifest by name (0144).
  local src m token_status token_output
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$src" use opt
  assert_success
  m="$PREFIX/bin/.devbin/manifest.sha256"
  chmod 000 "$m"
  if [ -r "$m" ]; then
    chmod 644 "$m"
    skip "running with permissions that read a mode-000 file"
  fi
  run manifest_source_token "$PREFIX"
  token_status="$status"
  token_output="$output"
  run machine_install_state
  chmod 644 "$m"
  [ "$token_status" -ne 0 ] || fail "a tree whose manifest cannot be read got a kind: $token_output"
  [[ "$token_output" == *"since its manifest cannot be read"* ]] || fail "the writer said: $token_output"
  [[ "$token_output" != *"no manifest"* ]] || fail "the writer called a manifest it cannot read missing: $token_output"
  [ "$output" = "bad the link $HOME/.local/bin/devbin names $(cd -P "$PREFIX" && pwd -P), whose manifest cannot be read" ] ||
    fail "machine_install_state said: $output"
}

# The pointer's relative-prefix arm is use.bats's now: `use opt` resolves a
# relative install.prefix where it is, never where CDPATH finds the same name.

# --- Homebrew's install, the default (issue 0195) ------------------------------
#
# With no DEVBIN_INSTALL_PREFIX and no link, the machine install is
# the devbin Homebrew installed, at $HOMEBREW_PREFIX/opt/devbin/libexec: the path
# brew keeps across upgrades, where the versioned keg under Cellar is deleted by
# them. devbin_isolate_machine points HOMEBREW_PREFIX at the test's own prefix,
# which holds no devbin; an arm that wants one builds it there, with brew_keg
# (tests/lib/test_helper.bash).

@test "with no DEVBIN_INSTALL_PREFIX and no link, Homebrew's install is the machine install, by its opt path (0195, 0213)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj"
  recording "$proj" install
  brew_keg --stub 0.1.0
  run manifest_source "$proj"
  assert_success
  [ "$output" = "$HOMEBREW_PREFIX/opt/devbin/libexec" ] || fail "Homebrew's install resolved as: $output"
  [ "$(machine_install_chooser)" = brew ] || fail "the chooser said: $(machine_install_chooser)"
  [ "$(machine_install_namer)" = HOMEBREW_PREFIX ] || fail "the namer said: $(machine_install_namer)"
}

@test "Homebrew's install is found again after a brew upgrade, whose new keg opt moves to while the old one goes (0195)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" before
  recording "$proj" install
  brew_keg --stub 0.1.0
  before="$(manifest_source "$proj")"
  brew_keg --stub 0.1.1
  rm -rf "$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  run manifest_source "$proj"
  assert_success
  [ "$output" = "$before" ] || fail "the root moved from $before to $output"
  [ "$(cd -P "$output" && pwd)" = "$(cd -P "$HOMEBREW_PREFIX/Cellar/devbin/0.1.1/libexec" && pwd)" ] ||
    fail "the root does not lead to the new keg: $(cd -P "$output" && pwd)"
}

@test "the link and DEVBIN_INSTALL_PREFIX each outrank Homebrew's install, and a link that cannot be followed is not passed over for it (0195, 0213)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" l="$HOME/.local/bin/devbin"
  recording "$proj" install
  brew_keg --stub 0.1.0
  fake_install "$PREFIX"
  mkdir -p "$HOME/.local/bin"
  ln -s "$PREFIX/bin/devbin" "$l"
  run manifest_source "$proj"
  assert_success
  [ "$output" = "$(cd -P "$PREFIX" && pwd -P)" ] || fail "the link did not outrank Homebrew's install: $output"
  DEVBIN_INSTALL_PREFIX="$DEVBIN_TEST_TMPDIR/elsewhere" run manifest_source "$proj"
  assert_success
  [ "$output" = "$DEVBIN_TEST_TMPDIR/elsewhere" ] || fail "the override did not outrank Homebrew's install: $output"
  # Broken is said as broken: a machine whose link went bad is never moved to
  # Homebrew's install in silence.
  rm "$l"
  ln -s "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$l"
  run manifest_source "$proj"
  [ "$status" -eq 2 ] || fail "a dangling link beside Homebrew's install returned $status: $output"
  assert_output_contains "the link $l leads to no file it can follow"
}

@test "Homebrew's opt/devbin that is not a devbin install is said to be that, by HOMEBREW_PREFIX (0195)" {
  local proj="$DEVBIN_TEST_TMPDIR/proj" state
  recording "$proj" install
  brew_keg --empty 0.1.0
  state="$(devbin_source_state "$proj")"
  [ "$state" = "unknown HOMEBREW_PREFIX's opt/devbin names $HOMEBREW_PREFIX/opt/devbin/libexec, which is not a devbin install or checkout" ] ||
    fail "devbin_source_state said: $state"
}

@test "with no install named anywhere, the sentence says what HOMEBREW_PREFIX showed: unset, holding no devbin, or not absolute (0195)" {
  # A process started without the login profile -- cron, a hook a GUI app
  # launched, a bare ssh command -- has no HOMEBREW_PREFIX, and there the default
  # is off. Named, so that reads as its cause rather than a bare "no install".
  local proj="$DEVBIN_TEST_TMPDIR/proj" want got
  recording "$proj" install
  want="unknown this machine names no devbin install: no link at $HOME/.local/bin/devbin, DEVBIN_INSTALL_PREFIX is not set, and"
  got="$(unset HOMEBREW_PREFIX; devbin_source_state "$proj")"
  [ "$got" = "$want HOMEBREW_PREFIX is not set" ] || fail "with HOMEBREW_PREFIX unset: $got"
  got="$(devbin_source_state "$proj")"
  [ "$got" = "$want no devbin at $HOMEBREW_PREFIX/opt/devbin/libexec, under HOMEBREW_PREFIX" ] ||
    fail "with HOMEBREW_PREFIX holding no devbin: $got"
  got="$(HOMEBREW_PREFIX=relative/brew devbin_source_state "$proj")"
  [ "$got" = "$want HOMEBREW_PREFIX, 'relative/brew', is not an absolute path" ] ||
    fail "with HOMEBREW_PREFIX relative: $got"
}

# AT-4.1
@test "a project vendored from Homebrew's install finds it with a bare upgrade, before and after a brew upgrade, and doctor names it and what chose it (0195)" {
  local src proj="$DEVBIN_TEST_TMPDIR/proj" opt="$HOMEBREW_PREFIX/opt/devbin/libexec"
  src="$(mkdevsrc)"
  # As the formula does: publish into the keg's libexec, marked as Homebrew's,
  # and brew links opt.
  brew_keg --from "$src" 0.1.0
  mkdir -p "$proj"
  run devbin_run "$opt" install --into "$proj" --name demo
  assert_success
  refute_output_contains "names no devbin install"
  # The project records the kind, never the versioned keg or any other place,
  # and no link is there to name the install for it (ST0009 AC-4.1).
  [ "$(header_of "$proj" source)" = install ] || fail "vendored from Homebrew's install, it records: $(header_of "$proj" source)"
  ! grep -E '^# source: .*[/~]' "$(manifest_of "$proj")" || fail "the manifest records a place"
  ! grep -qF Cellar "$(manifest_of "$proj")" || fail "the manifest names the keg"
  [ ! -e "$HOME/.local/bin/devbin" ] && [ ! -L "$HOME/.local/bin/devbin" ] || fail "a link is present: $(readlink "$HOME/.local/bin/devbin")"
  run devbin_run "$proj" upgrade
  assert_success
  assert_output_contains "$opt"
  refute_output_contains "Cellar/devbin"
  run devbin_run "$proj" doctor
  # The install by its version line alone, on a line of its own, and what
  # chose it on the row beneath (0246).
  assert_output_contains "install: the line above, named by HOMEBREW_PREFIX's opt/devbin, since no DEVBIN_INSTALL_PREFIX or link names one"
  refute_output_contains ") at "
  grep -qxE 'devbin [^ ]+ \(brew, [0-9a-f]{12}\)' <<<"$output" ||
    fail "doctor printed no brew version line of its own: $output"
  refute_output_contains "Cellar/devbin"
  # brew upgrade to a later commit: a new keg, opt moved to it, and the old keg
  # deleted. The new keg is a fresh publish, with no table carried from the old
  # one, so only the checkout's history can place this project's commit: read
  # as moved on and offered as an update, never as differing.
  commit_seam "$src" second
  brew_keg --from "$src" 0.1.1
  rm -rf "$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  run devbin_source_state "$proj"
  [[ "$output" == "behind "* ]] || fail "after a brew upgrade the project read: $output"
  run devbin_run "$proj" doctor
  assert_output_contains "source: the devbin this project came from has moved on"
  run devbin_run "$proj" upgrade
  assert_success
  assert_output_contains "$opt"
  refute_output_contains "cannot tell"
}

@test "run in Homebrew's install, the refusal's seed and upgrade lines name the opt link, never the keg brew upgrade deletes, whichever keg opt leads to (0195, 0251, 0252, 0266)" {
  # Found in the brew rehearsal: the launcher resolves its own links, so run
  # through opt it stands in Cellar/devbin/<version>, and a line copied from
  # the refusal named a keg the next brew upgrade and cleanup delete. The
  # machine's install is named elsewhere here, DEVBIN_INSTALL_PREFIX at another
  # directory, so the upgrade line carries --from (0251), and doctor reaches the
  # refusal, since help from an install answers (0251).
  local src opt="$HOMEBREW_PREFIX/opt/devbin/libexec" keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0/libexec"
  local other="$DEVBIN_TEST_TMPDIR/other"
  src="$(mkdevsrc)"
  brew_keg --from "$src" 0.1.0
  mkdir -p "$other"
  run env DEVBIN_INSTALL_PREFIX="$other" "$opt/bin/devbin" doctor
  [ "$status" -eq 5 ] || fail "expected the install refusal, exit 5, got $status: $output"
  assert_output_contains "  $HOMEBREW_PREFIX/opt/devbin/bin/devbin install --into <your project>"
  assert_output_contains "  cd <your project> && bin/devbin upgrade --from $opt"
  refute_output_contains "Cellar/devbin/0.1.0/libexec/bin/devbin install"
  refute_output_contains "upgrade --from $HOMEBREW_PREFIX/Cellar"
  # And with opt naming another keg, as while brew builds the next one, or when
  # an old keg is kept and run by its own path, both lines still name the opt
  # link: a hint is used later, and the keg it would name is the one a failed
  # build or cleanup removes (0252, which changes 0195's rule here).
  brew_keg --empty 0.1.1
  run env DEVBIN_INSTALL_PREFIX="$other" "$keg/bin/devbin" doctor
  [ "$status" -eq 5 ] || fail "expected the install refusal, exit 5, got $status: $output"
  assert_output_contains "  $HOMEBREW_PREFIX/opt/devbin/bin/devbin install --into <your project>"
  assert_output_contains "  cd <your project> && bin/devbin upgrade --from $opt"
  refute_output_contains "Cellar/devbin/0.1.0/libexec/bin/devbin install"
  refute_output_contains "upgrade --from $HOMEBREW_PREFIX/Cellar"
}

@test "run from Homebrew's keg, install's --force remedy and the refusal's seed line name devbin or the opt link, never the keg (0252, 0266)" {
  # A remedy is a line to copy. The launcher resolves its own links, so it runs
  # from Cellar/devbin/<version>, which the next brew upgrade deletes. Each half
  # runs the keg by that path, so the name the line carries is worked out, not
  # echoed.
  local src proj="$DEVBIN_TEST_TMPDIR/proj" keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  mkdir -p "$proj"
  run "$keg/libexec/bin/devbin" install --into "$proj"
  assert_success
  # Homebrew's bin link leads into the keg, but Homebrew's bin is not on PATH,
  # so the devbin on PATH is not this keg's, and the remedy names its opt link.
  run "$keg/libexec/bin/devbin" install --into "$proj"
  assert_exit_code 1
  assert_output_contains "to re-vendor the runtime:   $HOMEBREW_PREFIX/opt/devbin/bin/devbin install --into $proj --force"
  refute_output_contains "Cellar/devbin"
  # With Homebrew's bin on PATH, its link, through the keg's own bin/devbin,
  # makes the devbin there this keg's, so the remedy and the seed line name
  # devbin.
  run env PATH="$HOMEBREW_PREFIX/bin:$PATH" "$keg/libexec/bin/devbin" install --into "$proj"
  assert_exit_code 1
  assert_output_contains "to re-vendor the runtime:   devbin install --into $proj --force"
  refute_output_contains "Cellar/devbin"
  run env PATH="$HOMEBREW_PREFIX/bin:$PATH" "$keg/libexec/bin/devbin" doctor
  [ "$status" -eq 5 ] || fail "expected the install refusal, exit 5, got $status: $output"
  assert_output_contains "  devbin install --into <your project>"
  refute_output_contains "Cellar/devbin/0.1.0/libexec/bin/devbin install"
}

# assert_install_help <launcher> -- the last `run` printed an install's help
# (issue 0251): exit 0, the line saying what this tree is, and how to seed a
# project, naming <launcher>.
assert_install_help() {
  assert_success
  assert_output_contains "-- a machine install, not a project."
  assert_output_contains "In a project, bin/devbin help lists what that project offers. To seed one:"
  grep -qxF "  $1 install --into <your project>" <<<"$output" || fail "no seed line naming $1 in: $output"
}

@test "from Homebrew's keg outside a project, a bare devbin, -h, --help, help and help --why list what devbin ships, and exit 0 (0251, 0266)" {
  # A new user's first move is help, and each of these exited 5, so nobody could
  # read how to seed a project before seeding one.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" form
  brew_keg 0.1.0
  for form in "" -h --help help "help --why"; do
    # shellcheck disable=SC2086 # each form is its own words, and "" is none
    run "$keg/libexec/bin/devbin" $form
    assert_install_help "$HOMEBREW_PREFIX/opt/devbin/bin/devbin"
    assert_output_contains "What devbin ships, for a project to offer:"
    assert_output_contains "Devbin:"
    assert_output_contains "Vendor devbin into a project"
    assert_output_contains "Run: $HOMEBREW_PREFIX/opt/devbin/bin/devbin help <command>   for its page."
  done
  # The launcher the lines name runs, and is this keg's (0266).
  run "$HOMEBREW_PREFIX/opt/devbin/bin/devbin" --version
  assert_success
  assert_output_contains "(brew,"
}

@test "an install published at a path that only ends opt/devbin/libexec is no keg, so its help names its own launcher, which runs (0266)" {
  # Only a keg's Cellar path says Homebrew placed a tree. A plain opt install
  # at such a path was named by the directory above it, which holds no
  # bin/devbin, so the line it printed exited 127.
  local src root="$DEVBIN_TEST_TMPDIR/elsewhere/opt/devbin/libexec"
  src="$(mkdevsrc)"
  run devbin_run "$src" install --prefix "$root"
  assert_success
  run "$root/bin/devbin" help
  assert_install_help "$root/bin/devbin"
  assert_output_contains "Run: $root/bin/devbin help <command>   for its page."
  run "$root/bin/devbin" --version
  assert_success
}

@test "from Homebrew's keg, help install prints devbin's page for install under the install's line, and a page devbin does not ship, or a flag help does not take, exits 2 (0251, 0266)" {
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" page want
  brew_keg 0.1.0
  # The page as the install vendors it, read where the runtime lives
  # (bin/.devbin/lib), and read first: a page that could not be read would make
  # the assertion below match anything.
  page="$keg/libexec/bin/.devbin/lib/pages/install.md"
  want="$(cat "$page")" || fail "cannot read $page"
  [ -n "$want" ] || fail "$page is empty"
  run "$keg/libexec/bin/devbin" help install
  assert_install_help "$HOMEBREW_PREFIX/opt/devbin/bin/devbin"
  assert_output_contains "$want"
  run "$keg/libexec/bin/devbin" help frobnicate
  assert_exit_code 2
  assert_output_contains "devbin ships no page for 'frobnicate'"
  refute_output_contains "a machine install, not a project"
  # An install declares no shared option, so a flag help does not take is
  # refused, as a project's help refuses one it has not declared.
  run "$keg/libexec/bin/devbin" help --env x
  assert_exit_code 2
  assert_output_contains "unknown help option: --env"
}

@test "from Homebrew's keg, any other command, a typo included, still exits 5 with the install refusal (0251)" {
  # The guard on the other side, and unchanged behaviour: help and devbin devbin
  # answer from an install, and a command a project runs is still refused, as
  # are devbin's own forms that speak of a project's templates.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" form
  brew_keg 0.1.0
  for form in doctor frobnicate "check all" "devbin templates"; do
    # shellcheck disable=SC2086 # each form is its own words
    run "$keg/libexec/bin/devbin" $form
    [ "$status" -eq 5 ] || fail "$form: expected the install refusal, exit 5, got $status: $output"
    assert_output_contains "this is a devbin INSTALL, not a project"
  done
}

@test "with the devbin on PATH being Homebrew's keg and the machine naming it, the refusal's remedies read devbin install --into and cd <your project> && bin/devbin upgrade (0251)" {
  # Each a line as a user types it: no keg path, and no --from, which a
  # project's upgrade does not need when the machine names the install, since
  # upgrade reads the machine's install when it is given none. The line is then
  # RUN, as printed, in a project seeded from the keg: a string test would pass
  # the day every site agreed on a wrong line (0073).
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" consumer="$DEVBIN_TEST_TMPDIR/consumer" line
  local -a args
  brew_keg --linked 0.1.0
  mkdir -p "$consumer"
  run env PATH="$HOMEBREW_PREFIX/bin:$PATH" "$keg/libexec/bin/devbin" doctor
  [ "$status" -eq 5 ] || fail "expected the install refusal, exit 5, got $status: $output"
  assert_output_contains "  devbin install --into <your project>"
  grep -qxF '  cd <your project> && bin/devbin upgrade' <<<"$output" ||
    fail "the upgrade remedy is not the plain line: $output"
  refute_output_contains "upgrade --from"
  line="$(sed -n 's/^  cd <your project> && bin\/devbin \(.*\)$/\1/p' <<<"$output")"
  read -r -a args <<<"$line"
  run "$keg/libexec/bin/devbin" install --into "$consumer"
  assert_success
  run devbin_run "$consumer" "${args[@]}"
  assert_success
  [ "$(header_of "$consumer" source)" = install ] ||
    fail "the printed line ran, and the project does not record the install as its source:\n$output"
}

@test "devbin devbin from Homebrew's keg says what an install is, and how to seed and upgrade a project from it, at exit 0 (0251, 0266)" {
  # The framework's own help, the one thing an install can say about itself:
  # its overview describes a project's config and seam, which an install has
  # neither of.
  local opt="$HOMEBREW_PREFIX/opt/devbin/libexec" keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  brew_keg 0.1.0
  run "$keg/libexec/bin/devbin" devbin
  assert_success
  assert_output_contains "-- a machine install, not a project"
  assert_output_contains "  $HOMEBREW_PREFIX/opt/devbin/bin/devbin install --into <your project>"
  grep -qxF '  cd <your project> && bin/devbin upgrade' <<<"$output" ||
    fail "the upgrade line is not the plain one, though the machine names this install: $output"
  # The reference config by the path the runtime is at, and the file is there.
  assert_output_contains "Reference config, every key annotated: $opt/bin/.devbin/lib/config.reference.yaml"
  [ -f "$opt/bin/.devbin/lib/config.reference.yaml" ] || fail "the overview names a reference config that is not there"
  refute_output_contains "driven by"
  refute_output_contains "Cellar/devbin"
}

@test "devbin devbin from Homebrew's keg names the keg's docs/ by the opt link, and every guide it lists is there (0254)" {
  # It said the guides "are in docs/ of the devbin source checkout; an install
  # carries none", and a brew user has no checkout. The formula installs them
  # beside the keg's README, the parent of libexec.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  brew_keg 0.1.0
  run "$keg/libexec/bin/devbin" devbin
  assert_success
  assert_guides_at "$HOMEBREW_PREFIX/opt/devbin/docs"
  refute_output_contains "carries none"
  refute_output_contains "source checkout"
}

@test "devbin devbin from a keg with no docs/, as a formula before 0254 built, says Homebrew's devbin carries none and that brew upgrade devbin brings them (0254)" {
  # A docs/ that is not there is no place: the line names no directory the
  # reader cannot open.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  brew_keg 0.1.0
  rm -r "$keg/docs"
  run "$keg/libexec/bin/devbin" devbin
  assert_success
  assert_output_contains "are not here: Homebrew's devbin at $HOMEBREW_PREFIX/opt/devbin carries none, and a formula that installs them comes with brew upgrade devbin."
  refute_output_contains "are in "
}

@test "devbin devbin run from a keg by its Cellar path, with opt leading to another keg that has no docs/, names no docs/ that is not there (0254)" {
  # As while brew builds the next keg, or when an old keg is kept and run by
  # its own path (0252): the guides are named by the opt link's keg, so that
  # keg's docs/ is the one checked. The running keg's was, and the line named
  # opt/devbin/docs/, which was not there.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  brew_keg 0.1.0
  brew_keg --empty 0.1.1
  [ -d "$keg/docs" ] && [ ! -e "$HOMEBREW_PREFIX/opt/devbin/docs" ] ||
    fail "the fixture is not a running keg with docs/ and an opt keg without"
  run "$keg/libexec/bin/devbin" devbin
  assert_success
  assert_output_contains "are not here: Homebrew's devbin at $HOMEBREW_PREFIX/opt/devbin carries none, and a formula that installs them comes with brew upgrade devbin."
  refute_output_contains "are in "
}

@test "in a project seeded from Homebrew's keg, devbin devbin and release --help name the keg's guides, and the file release names is there (0254)" {
  # A project's guides are those of the install its upgrades read, which here
  # is Homebrew's: release's usage said "see docs/configuration.md", a path in
  # a checkout the project's user has not got.
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" proj="$DEVBIN_TEST_TMPDIR/proj"
  local docs="$HOMEBREW_PREFIX/opt/devbin/docs"
  brew_keg 0.1.0
  mkdir -p "$proj"
  run "$keg/libexec/bin/devbin" install --into "$proj"
  assert_success
  printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\n' >"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" devbin
  assert_success
  assert_guides_at "$docs"
  run devbin_run "$proj" release --help
  assert_success
  grep -qxF "  $docs/configuration.md." <<<"$output" || fail "release's usage does not name $docs/configuration.md: $output"
  [ -f "$docs/configuration.md" ] || fail "release's usage names $docs/configuration.md, which is not there"
}

@test "devbin devbin from an opt install says it carries no guides, and that they are in the checkout it was published from (0254)" {
  # opt is the maintainer's, who has the checkout: a publish copies the
  # runtime alone, so the line names no directory in the install.
  local src
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run "$PREFIX/bin/devbin" devbin
  assert_success
  assert_output_contains "are not here: an opt install carries none, and they are in docs/ of the devbin checkout it was published from."
  # No line names a directory for them, as `are in <dir>/` does where they are.
  ! grep -q '^are in ' <<<"$output" || fail "the opt install names a directory for its guides: $output"
}

@test "with the keg's bin/devbin a script of its own, as the formula writes it on macOS, use brew removes the link and reports brew, a bare use and doctor's switch read brew, and the hints name devbin (0253)" {
  # Every reader of "is this the keg's devbin" asks is_install_launcher, since
  # the script resolves to itself, not into libexec: compared by resolved path,
  # use brew read Homebrew's own devbin as another copy and refused.
  local src keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" proj="$DEVBIN_TEST_TMPDIR/proj"
  brew_keg --script --linked 0.1.0
  # A link into an opt install, for use brew to remove, published from a
  # checkout of its own: brew_keg's is devsrc.
  src="$(mkdevsrc optsrc)"
  run devbin_run "$src" install
  assert_success
  switch_to "$DEVBIN_TEST_TMPDIR/opt/devbin"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH" run "$keg/libexec/bin/devbin" use brew
  assert_success
  [ ! -e "$HOME/.local/bin/devbin" ] && [ ! -L "$HOME/.local/bin/devbin" ] || fail "use brew left the link: $output"
  assert_output_contains "no link, so brew"
  PATH="$HOMEBREW_PREFIX/bin:$PATH" run "$keg/libexec/bin/devbin" use
  assert_success
  assert_output_contains "use: no link, so brew"
  mkdir -p "$proj"
  run "$keg/libexec/bin/devbin" install --into "$proj"
  assert_success
  PATH="$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$proj" doctor
  assert_output_contains "ok    switch: no link, so brew"
  PATH="$HOMEBREW_PREFIX/bin:$PATH" run "$keg/libexec/bin/devbin" doctor
  [ "$status" -eq 5 ] || fail "expected the install refusal, exit 5, got $status: $output"
  assert_output_contains "  devbin install --into <your project>"
}

@test "with the keg's bin/devbin a script of its own and Homebrew's bin off PATH, use brew refuses, keeping the link, and names the directory to put on PATH (0253)" {
  # brew_answer_state's second reader: Homebrew's bin link when PATH does not
  # reach it. Compared by resolved path, the script read as no link into the
  # keg, and use brew said "is not linked ... link it" about a linked keg.
  local src before nodevbin keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  brew_keg --script --linked 0.1.0
  src="$(mkdevsrc optsrc)"
  run devbin_run "$src" install
  assert_success
  switch_to "$DEVBIN_TEST_TMPDIR/opt/devbin"
  before="$(readlink "$HOME/.local/bin/devbin")" || fail "the fixture made no link"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$nodevbin" run "$keg/libexec/bin/devbin" use brew
  assert_failure
  [ "$(readlink "$HOME/.local/bin/devbin")" = "$before" ] || fail "use brew changed the link: $output"
  assert_output_contains "Homebrew's devbin is linked at $HOMEBREW_PREFIX/bin/devbin, and $HOMEBREW_PREFIX/bin is not on PATH"
  refute_output_contains "is not linked"
}

# --- A checkout publish on a machine whose install is Homebrew's (issue 0197) ---
#
# The machine's install is chosen once, by machine_install_chooser. A publish
# from a checkout puts its files at the prefix and moves nothing; `devbin use`
# is the one verb that makes the published install the machine's (0213).

@test "a checkout publish on a machine whose install is Homebrew's moves nothing; use opt makes the checkout's install the machine's (0197, 0213)" {
  local src opt="$HOMEBREW_PREFIX/opt/devbin/libexec"
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  run devbin_run "$src" install
  assert_success
  [ "$(machine_install_chooser)" = brew ] || fail "the publish moved the machine's install: $(machine_install_chooser)"
  run devbin_run "$src" install --force
  assert_success
  [ "$(machine_install_chooser)" = brew ] || fail "the replace moved the machine's install: $(machine_install_chooser)"
  run devbin_run "$src" use opt
  assert_success
  [ "$(machine_install_chooser)" = link ] || fail "the chooser said: $(machine_install_chooser)"
  [ "$(machine_install_root)" = "$(cd -P "$PREFIX" && pwd -P)" ] || fail "the switch names $(machine_install_root)"
  # use brew removes the link only once Homebrew's devbin would answer in its
  # place (0235), so Homebrew's bin comes next on PATH, as a login shell has it.
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  assert_success
  [ "$(machine_install_root)" = "$opt" ] || fail "after use brew the switch names $(machine_install_root)"
}

@test "--point is gone: install and upgrade refuse it as an option they do not have, before writing (0197, 0213)" {
  local src proj="$DEVBIN_TEST_TMPDIR/proj"
  src="$(mkdevsrc)"
  run devbin_run "$src" install --point
  assert_failure
  assert_output_contains "unknown option '--point'"
  assert_file_not_exists "$PREFIX/bin/devbin"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj"
  assert_success
  run devbin_run "$proj" upgrade --point
  assert_failure
  assert_output_contains "unknown option '--point'"
}

@test "an opt link that names no devbin install is said so by the switch, never as an empty path (0197, 0213)" {
  # The chooser says brew wherever HOMEBREW_PREFIX's opt/devbin exists; a tree
  # there that is no install is named, with its reason (0197).
  local proj="$DEVBIN_TEST_TMPDIR/proj" state
  recording "$proj" install
  brew_keg --empty 0.1.0
  [ "$(machine_install_chooser)" = brew ] || fail "the chooser said: $(machine_install_chooser)"
  state="$(machine_install_state)"
  [ "$state" = "bad HOMEBREW_PREFIX's opt/devbin names $HOMEBREW_PREFIX/opt/devbin/libexec, which is not a devbin install or checkout" ] ||
    fail "machine_install_state said: $state"
}
