# shellcheck shell=bash
# shellcheck disable=SC2154
#
# SC2154 (referenced but not assigned) is disabled file-wide for one reason:
# `status` and `output` are set by bats-core's own `run`, so shellcheck cannot
# see their assignment and flags every assertion below. The alternative -- the
# Utilz CI's `-not -path "*/test/*"` -- excludes the helper from static analysis
# ENTIRELY, and that project's own workflow comment records what that costs:
# fifteen findings accumulated unseen in the file every utility sources. A
# narrow, reasoned suppression beats an exclusion that hides everything else.
#
# test_helper.bash - Common test utilities for the Devbin framework tests
#
# Provides helper functions for BATS tests:
# - Setup/teardown for test isolation
# - Assertion functions for test validation
# - Execution helpers for running devbin commands
# - Fixture-project creation helpers
#
# Usage: load this file at the top of each .bats file:
#   load "../lib/test_helper"
#
# The assertion vocabulary is deliberately the SAME as Utilz
# (opt/utilz/test/test_helper.bash). Devbin and Utilz are the same architecture
# applied to two different problems -- dev-project scripts and generic scripts --
# and a person moving between the two suites should not have to relearn
# assert_output_contains as assert_output_equals. Where this file differs from
# Utilz it is noted inline with the reason.
#
# Depends on bats-core ALONE -- no bats-support, no bats-assert -- matching
# Utilz, so the suite runs on a fresh machine with one install.

# The suite's bats floor, declared ONCE here rather than per-file, because it is
# a property of the suite and not of whichever file happens to need it first.
#
# 1.5.0 is what `run` flags need. The suite uses `run !` where a NON-ZERO exit is
# the condition under test and the exact code belongs to the tool being run, not
# to devbin -- a missing `mix` exits 127, and a gate propagates what it ran
# (AC-06.12). Without this declaration bats warns that 127 usually means the
# test's own command path is wrong, which is true in general and wrong there.
#
# Safe to require: CI pins 1.12.0 on Ubuntu and installs current bats-core on
# macOS (.github/workflows/tests.yml), both above the floor.
bats_require_minimum_version 1.5.0

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

# Resolve the checkout under test from this file's own location, not from $PWD,
# so helpers work regardless of where BATS was invoked.
# This file is at: $DEVBIN_HOME/tests/lib/test_helper.bash
# A relative dirname is spelled from ./, so an exported CDPATH is never searched
# for it (issue 0267).
_th_dir="$(dirname "${BASH_SOURCE[0]}")"
case "$_th_dir" in /*) ;; *) _th_dir="./$_th_dir" ;; esac
DEVBIN_HOME="$(cd -P "$_th_dir/../.." >/dev/null 2>&1 && pwd)"
unset _th_dir
export DEVBIN_HOME
export DEVBIN_BIN_DIR="$DEVBIN_HOME/bin"
export DEVBIN_LIB_DIR="$DEVBIN_HOME/lib"

export PATH="$DEVBIN_BIN_DIR:$PATH"

# Deterministic output: colour and terminal-dependent formatting off, so
# assertions compare what the code emits rather than what the terminal does.
export NO_COLOR=1
export TERM=dumb

# THE SUITE DOES NOT READ THE OPERATOR'S GIT CONFIGURATION. A local run read
# the person's global config, whose init.defaultBranch=main covered for a
# fixture that made its bare remote without -b main: every local suite passed,
# and CI's runner, which sets no such thing, was red with nobody reporting it.
# An empty global file and no system file is what that runner has, so a local
# run now fails where CI would.
# No identity is lost: every fixture that commits passes its own.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# ============================================================================
# SETUP AND TEARDOWN
# ============================================================================

# Per-file setup - runs once before all tests in a file: the file's scratch
# directory, and the one real install its fixtures are copied from (issue
# 0192, install_devbin below). A cache a nested `bats` inherited from the file
# that ran it is not this file's, so its names are cleared first: this file's
# teardown would otherwise check and remove the outer file's cache.
setup_file() {
  unset DEVBIN_FIXTURE_CACHE DEVBIN_FIXTURE_STARTER DEVBIN_FIXTURE_SEALS DEVBIN_FIXTURE_CP_CLONE
  export DEVBIN_FILE_TMPDIR="${BATS_FILE_TMPDIR:-${TMPDIR:-/tmp}}/devbin-test-$$"
  mkdir -p "$DEVBIN_FILE_TMPDIR"
  devbin_fixture_cache_build
}

# Per-file teardown - runs once after all tests in a file. The fixture cache is
# checked before it is removed: a cache that moved while the file ran, or is
# gone, fails the file by name, and so does a sum that could not be taken.
teardown_file() {
  local why=""
  why="$(devbin_fixture_seals_broken)"
  if [[ -n "${DEVBIN_FILE_TMPDIR:-}" && -d "$DEVBIN_FILE_TMPDIR" ]]; then
    chmod -R u+w "$DEVBIN_FILE_TMPDIR"
    rm -rf "$DEVBIN_FILE_TMPDIR"
  fi
  if [ -n "$why" ]; then
    printf 'test_helper: %s, so a later test may have copied what an earlier one did to it (issue 0192)\n' "$why" >&2
    return 1
  fi
}

# --- the fixture cache (issue 0192) -----------------------------------------
#
# ONE REAL INSTALL PER FILE, AND A COPY PER TEST. Every fixture used to go
# through the real installer, 645 ms each on this Mac, hundreds a run (the rule
# that fixtures install through the real installer). Installing once per file
# and copying amends that rule without breaking it: there is still no second
# implementation of install, since every fixture is a copy of what the real
# installer wrote, and the installer still runs at least once per file and in
# every test whose subject is the install.
#
# WHAT IS COPIED IS WHAT AN INSTALL WRITES, and nothing else: bin/devbin,
# bin/.devbin/lib/ and bin/.devbin/manifest.sha256. Measured: two installs into
# two fixtures of different names are byte-identical outside config.yaml, which
# install leaves alone, the manifest names no path of the project's, and nothing
# is written outside the project. The one write install makes outside
# bin/.devbin/, devbin's line-ending block in the project's .gitattributes
# (ST0008 WP-01), is never copied: it merges into whatever the project's file
# holds, so install_devbin writes it through lf_block_write, the installer's
# own writer. So a copy is the tree a fresh install gives,
# modes included: the cache loses only its owner's write bit, a copy is made
# under the test's own umask, and the owner's bit is given back.
#
# WHAT GUARDS IT IS teardown_file. The cache is read-only to its owner, so a
# plain write into it fails where it is made; but a test that makes it writable
# first, or runs as root, gets past that, and only the sum taken when the cache
# is built and checked at teardown_file catches it. That fails the file by
# name, and does so after the file's later tests have copied what was done.
#
# BUILT IN setup_file, before any test of the file runs, so it holds under
# --jobs, across files and within one, and under devbin_isolate_run, the one
# list of what a test is isolated from.

# devbin_fixture_cache_sum <dir> -- one line that changes when any path or byte
# under <dir> does, or any of it is made writable to its owner. rc 1 when any
# listing or sum of it could not be taken.
devbin_fixture_cache_sum() {
  (
    set -o pipefail
    # The one place devbin knows which sha256 tool exists (issue 0052).
    # shellcheck source=lib/helpers
    . "$DEVBIN_LIB_DIR/helpers" || exit 1
    cd "$1" || exit 1
    local paths files writable
    paths="$(find . -print | LC_ALL=C sort)" || exit 1
    writable="$(find . -perm -u+w -print | LC_ALL=C sort)" || exit 1
    files="$(find . -type f -print | LC_ALL=C sort)" || exit 1
    local -a list
    mapfile -t list <<<"$files"
    # Every path, every file's bytes, and every path made writable to its
    # owner again: no ls is parsed, so the line reads the same under BSD and
    # GNU. The install holds no name with a newline in it.
    printf '%s\n%s\nwritable:\n%s\n' "$paths" "$(sha256_files "${list[@]}")" "$writable" | sha256_stdin
  )
}

# devbin_fixture_seal <dir> -- make <dir> read-only to its owner and record its
# sum in DEVBIN_FIXTURE_SEALS, one `<sum><TAB><dir>` line a cache. THE ONE WAY
# a cache is guarded, so every cache this file builds is checked by the same
# teardown.
devbin_fixture_seal() {
  local sum
  chmod -R u-w "$1" || return 1
  sum="$(devbin_fixture_cache_sum "$1")" || {
    echo "test_helper: the fixture cache at $1 could not be summed (above)" >&2
    return 1
  }
  DEVBIN_FIXTURE_SEALS="${DEVBIN_FIXTURE_SEALS:-}$sum	$1
"
  export DEVBIN_FIXTURE_SEALS
}

# devbin_fixture_seals_broken -- why the first sealed cache that moved, is gone,
# or cannot be summed fails the file, as one line, or nothing when all hold.
devbin_fixture_seals_broken() {
  local sum dir now
  while IFS=$'\t' read -r sum dir; do
    [ -n "$dir" ] || continue
    if [ ! -d "$dir" ]; then
      printf 'the fixture cache at %s is gone\n' "$dir"
      return 0
    fi
    if ! now="$(devbin_fixture_cache_sum "$dir")"; then
      printf 'the fixture cache at %s could not be summed (above), so whether it changed is not known\n' "$dir"
      return 0
    fi
    if [ "$now" != "$sum" ]; then
      printf 'the fixture cache at %s changed while this file ran\n' "$dir"
      return 0
    fi
  done <<<"${DEVBIN_FIXTURE_SEALS:-}"
}

# devbin_fixture_cache_build -- the file's one real install, into
# $DEVBIN_FILE_TMPDIR/fixture-cache, read-only to its owner, with its sum and
# the copy's flag recorded for install_devbin. A no-op while bin/devbin does
# not exist, as install_devbin is.
devbin_fixture_cache_build() {
  local d="$DEVBIN_FILE_TMPDIR/fixture-cache" probe="$DEVBIN_FILE_TMPDIR/cp-probe"
  [[ -x "$DEVBIN_BIN_DIR/devbin" ]] || return 0
  mkdir -p "$d/bin/.devbin/cmd" "$d/bin/.devbin/help" || return 1
  printf 'project:\n  name: fixture\n  alias: fx\n' >"$d/bin/.devbin/config.yaml" || return 1
  # Under the isolation a test runs under, with the file's scratch directory as
  # the test's, in a subshell so this file's own environment, which its tests
  # inherit, is left as it was.
  (
    DEVBIN_TEST_TMPDIR="$DEVBIN_FILE_TMPDIR"
    devbin_isolate_run || exit 1
    cd "$DEVBIN_FILE_TMPDIR" || exit 1
    "$DEVBIN_BIN_DIR/devbin" install --into "$d" --force >/dev/null
  ) || {
    echo "test_helper: the file's one real install failed, into $d (above), so no fixture can be made" >&2
    return 1
  }
  # The project's own, never part of what an install writes.
  rm -r "$d/bin/.devbin/config.yaml" "$d/bin/.devbin/cmd" "$d/bin/.devbin/help" || return 1
  # -c where this cp takes it: BSD cp clones on APFS and falls back to a byte
  # copy where it cannot, and GNU cp has no -c, so it copies bytes.
  : >"$probe.src" || return 1
  if cp -c "$probe.src" "$probe.dst" 2>/dev/null; then
    DEVBIN_FIXTURE_CP_CLONE=-c
  else
    DEVBIN_FIXTURE_CP_CLONE=""
  fi
  rm -f "$probe.src" "$probe.dst"
  export DEVBIN_FIXTURE_CP_CLONE
  devbin_fixture_seal "$d" || return 1
  export DEVBIN_FIXTURE_CACHE="$d"
  devbin_fixture_starter_build
}

# devbin_fixture_starter_build -- THE STARTER SHAPE: a fresh install into an
# empty project named demo declaring shell, starter config and scaffold
# included, built once per file through the real installer (issue 0192).
# doctor.bats and scaffold.bats need what install writes for a
# project with no config, and nearly all their fixtures are this one shape.
# Measured: installed into two roots, it is byte-identical, config included,
# and names no path of either.
devbin_fixture_starter_build() {
  local d="$DEVBIN_FILE_TMPDIR/fixture-starter/demo"
  mkdir -p "$d" || return 1
  (
    DEVBIN_TEST_TMPDIR="$DEVBIN_FILE_TMPDIR"
    devbin_isolate_run || exit 1
    cd "$DEVBIN_FILE_TMPDIR" || exit 1
    "$DEVBIN_BIN_DIR/devbin" install --into "$d" --name demo --lang shell >/dev/null
  ) || {
    echo "test_helper: the file's starter install failed, into $d (above), so no starter fixture can be made" >&2
    return 1
  }
  devbin_fixture_seal "$d" || return 1
  export DEVBIN_FIXTURE_STARTER="$d"
}

# install_devbin_starter <dir> -- <dir> made the starter shape: a copy of the
# file's starter install, as `devbin install --into <dir> --name demo --lang
# shell` into an empty <dir> writes it. <dir> must not exist yet, or be empty.
install_devbin_starter() {
  local dir="$1"
  if [ -z "${DEVBIN_FIXTURE_STARTER:-}" ] || [ ! -d "$DEVBIN_FIXTURE_STARTER" ]; then
    echo "install_devbin_starter: no starter fixture -- setup_file did not build one, or a test removed it -- so $dir has no install" >&2
    return 1
  fi
  if ! { mkdir -p "$dir" &&
    cp ${DEVBIN_FIXTURE_CP_CLONE:+"$DEVBIN_FIXTURE_CP_CLONE"} -R "$DEVBIN_FIXTURE_STARTER/." "$dir/" &&
    chmod -R u+w "$dir"; }; then
    echo "install_devbin_starter: copying the starter fixture into $dir failed (above)" >&2
    return 1
  fi
}

# Per-test setup - runs before each test.
#
# The temp dir is created OUTSIDE the Devbin checkout: a suite that writes
# inside its own repo pollutes `git status` and gets picked up by the gate's own
# file discovery on the next run.
#
# Differs from Utilz deliberately: Utilz exports BATS_TEST_TMPDIR, which is a
# variable bats-core 1.x sets and uses itself. Shadowing it works today but is a
# latent conflict with the harness, so this uses its own name.
devbin_setup() {
  # `pwd -P` after the cd, not the raw mktemp path: on macOS $TMPDIR lives under
  # /var, which is a symlink to /private/var, so the mktemp path and the $PWD a
  # test observes after cd'ing there are DIFFERENT STRINGS for the same
  # directory. Any later test comparing a resolved project root against the
  # fixture path would fail for a reason that has nothing to do with the code
  # under test. Resolve once, here, so every consumer sees one spelling.
  DEVBIN_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/devbin-test.XXXXXX")"
  DEVBIN_TEST_TMPDIR="$(cd -P "$DEVBIN_TEST_TMPDIR" >/dev/null 2>&1 && pwd -P)"
  export DEVBIN_TEST_TMPDIR
  # A FIXTURE MUST NOT SIT INSIDE A CHECKOUT. Every test that asks what a
  # directory that is NOT a git checkout does builds that directory here. With
  # $TMPDIR inside a repository, 51 of them failed at once for a reason no
  # failure message named, and it read like a regression (TMPDIR inside the
  # devbin checkout). Refused by name, so the cause is the message.
  if [ "$(git -C "$DEVBIN_TEST_TMPDIR" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    fail "TMPDIR is inside a git checkout ($(git -C "$DEVBIN_TEST_TMPDIR" rev-parse --show-toplevel)), so a fixture cannot be outside one. Run the suite with a TMPDIR outside any repository."
  fi
  # AND BY THE FILESYSTEM, AS THE GATE'S IGNORE FILE NOW ASKS IT (issue 0179). A
  # .git above TMPDIR that git does not read -- another user's, one beyond
  # GIT_CEILING_DIRECTORIES or a filesystem boundary, a dangling link -- passes
  # the check above, and every fixture would then read as inside a repository.
  # Walked here, not through git_marker_above, so the harness's precondition
  # does not rest on the code under test.
  local _dir="$DEVBIN_TEST_TMPDIR" _up
  until [ -e "$_dir/.git" ] || [ -L "$_dir/.git" ]; do
    _up="${_dir%/*}"
    [ "$_up" != "$_dir" ] || break
    _dir="$_up"
  done
  if [ -e "$_dir/.git" ] || [ -L "$_dir/.git" ]; then
    fail "$_dir/.git is above TMPDIR, so a fixture cannot be outside a repository. Run the suite with a TMPDIR outside it."
  fi
  DEVBIN_ORIGINAL_PWD="$(pwd)"
  export DEVBIN_ORIGINAL_PWD

  devbin_isolate_run || return 1

  cd "$DEVBIN_TEST_TMPDIR" || return 1
}

# devbin_isolate_run -- every variable a test must not inherit from whatever ran
# the suite, scrubbed, and every place a run writes outside its tree pointed
# under $DEVBIN_TEST_TMPDIR. THE ONE LIST: devbin_setup calls it for each test,
# and the fixture cache's one install (issue 0192) for each file, so a variable
# added here reaches both, where a second list kept for the cache would not.
devbin_isolate_run() {
  # ISOLATED FROM THE OUTER devbin RUN, and this was found the hard way.
  # The suite itself executes under `bin/devbin test bats`, which EXPORTS
  # DEVBIN_RUN_ID and DEVBIN_RUN_STAMP -- so without this every fixture devbin
  # inherits the harness's own run identity and two fixture invocations look
  # like one run. That inheritance is correct behaviour (it is what makes a
  # fullcycle one run) and it is exactly wrong as a test default: a suite that
  # cannot vary a value cannot ask a question about it. Tests that mean to
  # exercise inheritance set the variable themselves.
  unset DEVBIN_RUN_ID DEVBIN_RUN_STAMP DEVBIN_RUN_WITNESS

  # The runtime libraries source each other by DEVBIN_LIB, so a test that sources
  # one directly needs it set. Done here rather than per-file: every unit test
  # that touches the runtime needs the same value, and three copies of it would
  # drift the first time the layout changed.
  export DEVBIN_LIB="$DEVBIN_LIB_DIR"

  # CARGO IS ASKED WHERE IT BUILDS ONLY WHEN A CARRIER IS PRESENT (issue 0150):
  # CARGO_TARGET_DIR or CARGO_BUILD_TARGET_DIR set, or a .cargo/config naming
  # target-dir or include in a crate's directory or above it, or in
  # CARGO_HOME. So the suite does not depend on the runner's home or
  # environment: CARGO_HOME is an empty directory of the test's own, and both
  # variables are unset. An arm
  # that means a carrier sets it. DECLARED LIMIT: a .cargo/config in a directory
  # above $TMPDIR on the runner is still found by the walk up from a fixture's
  # crate, as cargo itself would find it; none is on this project's runners.
  export CARGO_HOME="$DEVBIN_TEST_TMPDIR/.cargo-home"
  mkdir -p "$CARGO_HOME"
  unset CARGO_TARGET_DIR CARGO_BUILD_TARGET_DIR

  # A gate run inside a test must never append to the seal ledger of the devbin
  # run that INVOKED the suite -- `bin/devbin test all` sets DEVBIN_SEAL_LEDGER,
  # and without this the fixtures' own run_gate calls report themselves as this
  # project's failed gates.
  unset DEVBIN_SEAL_LEDGER DEVBIN_SEAL_LEDGER_RUN
  # Nor inherit a WITNESS flag from whatever invoked the suite: it changes what
  # record_seal writes and which run id the dispatcher mints.
  unset RUNLOG_WITNESS_RUN
  # Nor a CARGO_TARGET_DIR: cargo_target_dirs takes it outright, so an exported
  # one points every fixture's artefact check at a directory the fixture never
  # built. An arm that wants one sets it per call.
  unset CARGO_TARGET_DIR

  devbin_isolate_machine || return 1
  # Run by `devbin test`, the suite itself is inside a gate, and every arm would
  # inherit its view of the person (issue 0158): each arm reads the person
  # from its own stdin unless it says otherwise.
  unset DEVBIN_GATE_TTY DEVBIN_IN_GATE
}

# devbin_isolate_machine -- THE MACHINE POINTER IS THE TEST'S OWN (issue 0153).
# A publish to install.prefix writes $XDG_DATA_HOME/devbin/home, and under the
# runner's own HOME that is the file every project on the machine reads to find
# its devbin: an arm that published a scratch install would repoint all of them
# at it. So every arm gets a data directory of its own, and neither override
# that places a source leaks in from whatever ran the suite. An arm that means a
# source is known sets one itself. A function of its own so an arm can plant
# what a careless runner exports and watch it go.
devbin_isolate_machine() {
  export XDG_DATA_HOME="$DEVBIN_TEST_TMPDIR/.xdg-data"
  mkdir -p "$XDG_DATA_HOME" || return 1
  unset DEVBIN_INSTALL_PREFIX DEVBIN_SOURCE
  # Homebrew's install is the machine install's default once nothing else names
  # one (issue 0195), found through HOMEBREW_PREFIX alone, so the test's own
  # prefix, which holds no devbin, keeps a real one off every arm. An arm that
  # wants one builds it under there.
  export HOMEBREW_PREFIX="$DEVBIN_TEST_TMPDIR/.homebrew"
  # Nor whether this is WSL (ST0008): every arm is off WSL, on a WSL
  # machine too, unless it says otherwise; the probe itself is asked of a
  # fixture's /proc.
  export DEVBIN_WSL=0
  unset DEVBIN_WSL_MOUNT_ROOT
  # NOR THE RUNNER'S HOME (issue 0213): `devbin use` keeps the machine's choice
  # of install as a link, $HOME/.local/bin/devbin, and every project on the
  # machine reads it, so an arm under the runner's HOME would read the runner's
  # choice and could rewrite it. Every arm gets a home of its own. The tools a
  # real arm runs that keep their own state under HOME are pinned to the
  # runner's first, so they still find it: mix, hex and rustup. rustup's cargo
  # proxy reads its toolchains from RUSTUP_HOME, so under an empty home it can
  # choose no cargo at all (issue 0222). cargo's own home is pinned in
  # devbin_isolate_run, and git reads no global config here.
  export MIX_HOME="${MIX_HOME:-$HOME/.mix}" HEX_HOME="${HEX_HOME:-$HOME/.hex}"
  export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
  export HOME="$DEVBIN_TEST_TMPDIR/home"
  # Nor the runner's XDG config directory (issue 0272): infra reads its
  # machine-wide profile under XDG_CONFIG_HOME, so an arm would read the
  # runner's own profile. Unset, it is the test home's ~/.config.
  unset XDG_CONFIG_HOME
  # Nor the runner's artefact registry (ST0011): the cache command writes under
  # DEVBIN_CACHE_HOME, or the XDG cache directory's devbin when that is unset,
  # and its gc removes from there, so an arm that reached either would change the
  # registry the runner's own builds pull from. Both unset, the registry is the
  # test home's ~/.cache/devbin. An arm that means a root sets one.
  unset DEVBIN_CACHE_HOME XDG_CACHE_HOME
  mkdir -p "$HOME" || return 1
  # And that home's ~/.local/bin first on PATH, the order the switch assumes of
  # a login shell (docs/dev-opt-brew.md, T5), so a link an arm points with
  # `devbin use` is the first devbin on PATH and passes the shadow check. An
  # arm that means a shadowed link builds its own PATH.
  export PATH="$HOME/.local/bin:$PATH"
}

# Per-test teardown - runs after each test.
#
# The rm is guarded on the mktemp prefix: an unset or surprising temp path must
# not turn this into an rm -rf of something else. Refusing loudly beats a tidy
# delete of the wrong tree.
devbin_teardown() {
  _restore_unreadable
  _restore_immutable
  if [[ -n "${DEVBIN_ORIGINAL_PWD:-}" && -d "$DEVBIN_ORIGINAL_PWD" ]]; then
    cd "$DEVBIN_ORIGINAL_PWD" || true
  fi
  # Order matters. `*/devbin-test.*` alone also matches every path UNDERNEATH a
  # temp dir, because a glob `*` spans slashes -- so a caller that pointed the
  # variable at a subdirectory would have it deleted by a guard written to
  # prevent exactly that. The subpath pattern is tested first and refused.
  case "${DEVBIN_TEST_TMPDIR:-}" in
    "") : ;;
    */devbin-test.*/*)
      echo "test_helper: refusing to remove unexpected DEVBIN_TEST_TMPDIR=$DEVBIN_TEST_TMPDIR" >&2
      ;;
    */devbin-test.*) rm -rf "$DEVBIN_TEST_TMPDIR" ;;
    *)
      echo "test_helper: refusing to remove unexpected DEVBIN_TEST_TMPDIR=$DEVBIN_TEST_TMPDIR" >&2
      ;;
  esac
}

# make_unreadable <file>... -- each file to mode 000, restored by devbin_teardown
# whatever the test's outcome (issue 0144).
#
# RESTORED IN TEARDOWN, NOT IN THE TEST BODY, because a body stops at its first
# failed assertion and a restore written after it never runs. A mode-000 file
# is still removable, but a tree left holding one is a trap for whatever reads
# it next. Where a mode-000 file is still readable -- root reads it -- the arm
# would build a state it only claims, so it is not run: skipped on a
# developer's machine, and FAILED under CI, for require_command's reason -- a
# skip there is a coverage hole reported as a pass.
make_unreadable() {
  local f
  for f in "$@"; do
    chmod 000 "$f" || fail "make_unreadable: cannot chmod $f"
    _DEVBIN_UNREADABLE+=("$f")
  done
  for f in "$@"; do
    [ -r "$f" ] || continue
    [[ -z "${CI:-}" ]] || fail "this CI runner reads a mode-000 file ($f), so the unreadable case cannot be built: run the job as a user that cannot"
    skip "running with permissions that read a mode-000 file: the unreadable case was NOT checked"
  done
}

# make_immutable <file>... -- each file given macOS's `uchg` flag, cleared by
# devbin_teardown whatever the test's outcome (issue 0279), since the temp
# dir's removal cannot remove a file that holds it. Skipped, and said, where
# the runner cannot set it: chflags is macOS's, and Linux's `chattr +i` is
# root's alone.
make_immutable() {
  local f
  command -v chflags >/dev/null 2>&1 || skip "chflags is not on this runner, so the immutable case was NOT checked"
  for f in "$@"; do
    chflags uchg "$f" 2>/dev/null || skip "this runner cannot set uchg on $f, so the immutable case was NOT checked"
    _DEVBIN_IMMUTABLE+=("$f")
  done
}

# _restore_immutable -- clear the flag make_immutable set on every file in this
# test, and every immutable temporary left beside it, so the temp dir can go.
_restore_immutable() {
  local f t
  for f in "${_DEVBIN_IMMUTABLE[@]+"${_DEVBIN_IMMUTABLE[@]}"}"; do
    for t in "$f" "$f".??????; do
      if [ -e "$t" ]; then chflags nouchg "$t" 2>/dev/null || true; fi
    done
  done
  _DEVBIN_IMMUTABLE=()
}

# _restore_unreadable -- give back the owner's read and write on every file
# make_unreadable took them from in this test.
_restore_unreadable() {
  local f
  for f in "${_DEVBIN_UNREADABLE[@]+"${_DEVBIN_UNREADABLE[@]}"}"; do
    if [ -e "$f" ]; then chmod u+rw "$f"; fi
  done
  _DEVBIN_UNREADABLE=()
}

# ============================================================================
# EXECUTION HELPERS
# ============================================================================

# Run the devbin dispatcher from the checkout under test.
# Usage: run_devbin help
run_devbin() {
  run "$DEVBIN_BIN_DIR/devbin" "$@"
}

# Run a fixture project's installed dispatcher.
# Usage: run_in_project "$proj" test all
run_in_project() {
  local project="$1"
  shift
  # Routed through devbin_run rather than invoking the path itself, so there is
  # ONE place in the suite that knows how a fixture's devbin is invoked. This
  # wrapper adds bats `run`; devbin_run owns standing in the project.
  run devbin_run "$project" "$@"
}

# ============================================================================
# FIXTURE CREATION
# ============================================================================

# Create a fixture project tree and print its path.
#
#   <name>/bin/.devbin/config.yaml   minimal valid config
#   <name>/bin/.devbin/cmd/          project handlers (empty)
#   <name>/bin/.devbin/help/         authored help (empty)
#
# Usage: proj="$(create_test_project demo)"
create_test_project() {
  local name="${1:-fixture}" dir
  dir="$DEVBIN_TEST_TMPDIR/$name"
  mkdir -p "$dir/bin/.devbin/cmd" "$dir/bin/.devbin/help"
  cat >"$dir/bin/.devbin/config.yaml" <<YAML
project:
  name: $name
  alias: fx
YAML
  echo "$dir"
}

# Install the dispatcher + runtime into a fixture project, THROUGH THE REAL
# INSTALLER.
#
# This was `cp` + `cp -R` from WP-02, when there was nothing to call. Keeping it
# that way once `devbin install` existed would have been a second implementation
# of install living in the harness -- free to drift from the real one, and
# drifting silently, because every test depending on a correctly installed
# fixture would go on passing while the shipped command was broken.
#
# Pointing it here makes the whole suite the installer's integration test: some
# hundreds of installs per run, each one asserted on by whatever the test was
# actually about. That is the strongest coverage available for a command whose
# failure mode is a project that will not start.
#
# Still a no-op while bin/devbin does not exist (WP-02 predates WP-04), so
# harness tests can use fixtures before there is anything to install.
#
# AMENDED BY ISSUE 0192: the real installer runs once per file, in setup_file,
# and each fixture is a COPY of what it wrote (the fixture cache above), where
# each used to run the installer itself at 645 ms. The reason stands: the
# copy is the real installer's output, never a second implementation of
# install. A test whose subject is the installer runs it itself, as
# install.bats and localinstall.bats do. The copy's write bit is given back to
# its owner, so its modes are a fresh install's.
#
# A DIRECTORY WITH NO CONFIG RUNS THE REAL INSTALLER, as every fixture did
# before. Into a bare directory install also writes the starter config.yaml,
# named after the directory, and cmd/ and help/; the copy brings the launcher,
# lib/ and the manifest only, so a bare directory came out with no config and
# shellinit.bats's machine-install-fallback arm failed on it in the landing
# suite. A starter copied from the cache would carry another directory's name.
# Every other caller builds its project, config included, first, and takes the
# copy, which also makes cmd/ and help/ as install does.
install_devbin() {
  local dir="$1"
  [[ -x "$DEVBIN_BIN_DIR/devbin" ]] || return 0
  if [ ! -e "$dir/bin/.devbin/config.yaml" ]; then
    "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --force >/dev/null || {
      echo "install_devbin: devbin install failed for $dir" >&2
      return 1
    }
    return 0
  fi
  if [ -z "${DEVBIN_FIXTURE_CACHE:-}" ]; then
    echo "install_devbin: no fixture cache -- setup_file did not build one, so $dir has no install" >&2
    return 1
  fi
  if [ ! -d "$DEVBIN_FIXTURE_CACHE" ]; then
    echo "install_devbin: the fixture cache at $DEVBIN_FIXTURE_CACHE is gone -- a test removed it -- so $dir has no install" >&2
    return 1
  fi
  # Over an install already there, the copy replaces each file the install
  # writes: from one source nothing it shipped is unshipped, so this is what
  # --force over it gave.
  if ! { mkdir -p "$dir/bin/.devbin/cmd" "$dir/bin/.devbin/help" &&
    cp ${DEVBIN_FIXTURE_CP_CLONE:+"$DEVBIN_FIXTURE_CP_CLONE"} -R "$DEVBIN_FIXTURE_CACHE/bin/devbin" "$dir/bin/devbin" &&
    cp ${DEVBIN_FIXTURE_CP_CLONE:+"$DEVBIN_FIXTURE_CP_CLONE"} -R "$DEVBIN_FIXTURE_CACHE/bin/.devbin/lib" "$DEVBIN_FIXTURE_CACHE/bin/.devbin/manifest.sha256" "$dir/bin/.devbin/" &&
    chmod -R u+w "$dir/bin/devbin" "$dir/bin/.devbin/lib" "$dir/bin/.devbin/manifest.sha256"; }; then
    echo "install_devbin: copying the fixture cache into $dir failed (above)" >&2
    return 1
  fi
  # DEVBIN'S LINE-ENDING BLOCK, through the installer's one writer and never as
  # a copied file (above): the block merges into the project's .gitattributes.
  # In a subshell, as lib/helpers sets the shell options it runs under. Not
  # followed by shellcheck: both files are linted in their own right, and
  # following them into this subshell reads their assignments as this file's.
  # shellcheck disable=SC1091
  if ! (. "$DEVBIN_LIB_DIR/helpers" && . "$DEVBIN_LIB_DIR/install" && lf_block_write "$dir" >/dev/null); then
    echo "install_devbin: devbin's line-ending block was not written into $dir/.gitattributes (above)" >&2
    return 1
  fi
}

# mkproj -- a fixture project with devbin installed and a config read from stdin.
#
# THE REGISTERED HOME FOR THIS IS HERE, and it was defined in thirteen test
# files instead (issue 0041). All thirteen bodies were byte-identical, which is
# the state Highlander describes as pre-drift rather than as harmless: a change
# to `create_test_project` needing a matching change here would have landed in
# one file and left twelve green until they were not.
#
# This file already REASONED about `mkproj` in two comment blocks before it
# defined it -- see the cwd-guard note below on why the subshell could not live
# inside this function -- so a reader who came here for the suite's shared test
# helpers found prose about a helper the file did not contain.
#
# `cat >` consumes stdin deliberately: callers pass the config as a heredoc and
# consume the result as `proj="$(mkproj demo <<'YAML' ... YAML)"`. Nothing about
# that changes by living here; a function is a function wherever it is defined.
mkproj() {
  local name="${1:-demo}" proj
  proj="$(create_test_project "$name")"
  install_devbin "$proj"
  cat >"$proj/bin/.devbin/config.yaml"
  echo "$proj"
}

# cargo_tag <dir> -- the CACHEDIR.TAG cargo writes, in cargo's own words.
#
# lib/cmd/clean counts a tag only when it names cargo as its writer (issue
# 0131): pytest, mypy and others write the same signature line. So a tag made
# with `: >` is no longer a cargo marker, and a fixture that means cargo says so
# the way cargo does. The text is cargo 1.98.1's, read off its own output. Here
# rather than in one suite because clean.bats and fullcycle.bats both build
# cargo trees, and two copies of one fixture drift.
cargo_tag() {
  printf 'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo.\n# For information about cache directory tags see https://bford.info/cachedir/\n' >"$1/CACHEDIR.TAG"
}

# need_cargo -- (issue 0150) skip, saying so, where cargo is not on this runner.
need_cargo() {
  command -v cargo >/dev/null 2>&1 || skip "cargo is not on this runner: NOT checked"
}

# real_crate <dir> -- a crate cargo reads: a package and a binary target.
real_crate() {
  mkdir -p "$1/src"
  printf '[package]\nname = "demo"\nversion = "0.1.0"\nedition = "2021"\n' >"$1/Cargo.toml"
  printf 'fn main() {}\n' >"$1/src/main.rs"
}

# Write an executable stub handler into a project's cmd/ dir and print its path.
# The default body reports its own name and arguments, which is what dispatch
# and resolution tests need to prove routing.
# Usage: create_test_command "$proj" greet
create_test_command() {
  local dir="$1" name="$2" body="${3:-}" path
  path="$dir/bin/.devbin/cmd/$name"
  if [[ -n "$body" ]]; then
    echo "$body" >"$path"
  else
    cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ran:%s args:%s\n' "$name" "\$*"
EOF
  fi
  chmod +x "$path"
  echo "$path"
}

# Write a stub BUILT-IN command into a fixture's vendored runtime.
#
# Distinct from create_test_command, which writes a PROJECT handler. The two
# take different paths through resolution: a project handler shadows a built-in
# totally and displaces its option set, so a test about built-in options must
# use this one or it will silently be testing the shadowing rule instead.
# Stands in for lib/cmd/<name> until WP-08 ships the real implementations.
create_builtin_command() {
  local dir="$1" name="$2" body="${3:-}" path
  mkdir -p "$dir/bin/.devbin/lib/cmd"
  path="$dir/bin/.devbin/lib/cmd/$name"
  if [[ -n "$body" ]]; then
    echo "$body" >"$path"
  else
    cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ran:%s\n' "\$1"
EOF
  fi
  chmod +x "$path"
  echo "$path"
}

# Replace a fixture's config.yaml from stdin.
#
#   write_config "$proj" <<'YAML'
#   project:
#     name: demo
#   YAML
write_config() {
  cat >"$1/bin/.devbin/config.yaml"
}

# `write_command_meta` lived here and is GONE. It scaffolded a
# `cmd/<name>.yaml` metadata sidecar in the Utilz shape, anticipated in WP-02
# and never built: one source per fact settled that a project's command
# declares its summary and group in its own handler header, and nothing in the
# runtime has ever read a sidecar. It was the last thing in the repo asserting
# the format exists, which
# made it a fixture-maker for a contract devbin does not honour -- a trap for
# whoever wrote the next handler and believed it.

# ============================================================================
# ASSERTION HELPERS
# ============================================================================

# EVERY `fail` call site below is followed by `return 1`, without exception.
#
# `fail` returns 1, but a function does not stop merely because a statement
# returned non-zero -- errexit is what stops it. In a multi-check assertion a
# `fail` that is not the LAST statement therefore depends on errexit being on:
# with it, the function exits there; without it, the failure is discarded and
# the function returns the status of whatever ran afterwards.
#
# Under BATS errexit is on, so the implicit form (as Utilz's helper uses) is
# correct in normal use. It stops being correct the moment a caller captures the
# exit code -- `( ... ) || rc=$?` suppresses errexit inside the subshell too --
# which is precisely what refute_assertion below must do to test a negative
# path. Left implicit, `assert_symlink_exists <regular-file>` returns 0 there.
#
# An assertion that silently passes is strictly worse than no assertion, so the
# `return 1` is explicit and the behaviour no longer depends on the caller's
# shell options.

# Assert command succeeded (exit code 0)
assert_success() {
  if [[ "$status" -ne 0 ]]; then
    fail "Expected success (exit 0) but got exit code: $status\nOutput: $output"
    return 1
  fi
}

# Assert command failed (non-zero exit)
assert_failure() {
  if [[ "$status" -eq 0 ]]; then
    fail "Expected failure (non-zero exit) but got exit code 0\nOutput: $output"
    return 1
  fi
}

# Assert command failed with a specific exit code
# Usage: assert_exit_code 2
assert_exit_code() {
  local expected_code="$1"
  if [[ "$status" -ne "$expected_code" ]]; then
    fail "Expected exit code $expected_code but got: $status\nOutput: $output"
    return 1
  fi
}

# Assert output contains a string
assert_output_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    fail "Expected output to contain: '$expected'\nActual output:\n$output"
    return 1
  fi
}

# Assert output does NOT contain a string
refute_output_contains() {
  local unexpected="$1"
  if [[ "$output" == *"$unexpected"* ]]; then
    fail "Expected output NOT to contain: '$unexpected'\nActual output:\n$output"
    return 1
  fi
}

# Assert exact output match
assert_output() {
  local expected="$1"
  if [[ "$output" != "$expected" ]]; then
    fail "Expected output:\n$expected\n\nActual output:\n$output"
    return 1
  fi
}

# Assert output matches a regex
assert_output_matches() {
  local pattern="$1"
  if [[ ! "$output" =~ $pattern ]]; then
    fail "Expected output to match pattern: '$pattern'\nActual output:\n$output"
    return 1
  fi
}

# Assert output does NOT match a regex.
#
# The precise counterpart to refute_output_contains, which is a SUBSTRING test
# and so cannot say "this command is not listed" without also forbidding the
# word anywhere else. That bit: a test refuted `publish` to prove the command
# was hidden, and started failing when an unrelated command's summary gained the
# word "publish" as prose. Anchoring on the rendered line says what was meant.
refute_output_matches() {
  local pattern="$1"
  if [[ "$output" =~ $pattern ]]; then
    fail "Expected output NOT to match pattern: '$pattern'\nActual output:\n$output"
    return 1
  fi
}

# lock <path> -- mode 000, or skip on a runner that reads it anyway, as root.
#
# Here, not in one suite: clean.bats and fullcycle.bats both lock a path, and
# fullcycle.bats had grown two inline copies of this beside clean.bats's own
# (issue 0131), each with its own skip message.
lock() {
  chmod 000 "$1"
  if [ -r "$1" ]; then
    chmod 755 "$1"
    skip "running with permissions that read a mode-000 path"
  fi
}

# require_git_refusal <dir> -- skip unless git refuses the repository at <dir>
# when GIT_TEST_ASSUME_DIFFERENT_OWNER=1 marks it another user's, which is how
# the arms for a repository git will not read drive one. Git must read it
# without the lever first, so a fixture whose `git init` failed fails here by
# name rather than passing as refused. Both halves ask with no inherited
# GIT_DIR, GIT_WORK_TREE or GIT_COMMON_DIR, which would answer for another
# repository and leave the lever inert.
require_git_refusal() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR git -C "$1" rev-parse --git-dir >/dev/null 2>&1 ||
    fail "git does not read $1 even without GIT_TEST_ASSUME_DIFFERENT_OWNER, so it is no repository to refuse"
  if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
    git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then
    skip "this git reads a repository GIT_TEST_ASSUME_DIFFERENT_OWNER marks as another user's"
  fi
}

# break_git_index <dir> -- leave the repository at <dir> with an index git
# cannot read, as a truncated .git/index is: every call that reads the index
# (status, diff --cached, ls-files, check-ignore) then fails at 128 with "index
# file smaller than expected", while rev-parse and tag still answer (issue
# 0186). Git must read the index before the cut and must not after it, so a
# fixture with no index, or a git that copes, fails here by name rather than
# passing as broken. Both halves ask with no inherited GIT_DIR, GIT_WORK_TREE
# or GIT_COMMON_DIR, as require_git_refusal does, and no GIT_INDEX_FILE, which
# names the index status reads -- a commit hook's own -- so the guard reads the
# index it cuts.
break_git_index() {
  [ -f "$1/.git/index" ] || fail "$1 has no .git/index to cut"
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "$1" status --porcelain >/dev/null 2>&1 ||
    fail "git cannot read $1's index before the cut, so the cut would prove nothing"
  : >"$1/.git/index"
  if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "$1" status --porcelain >/dev/null 2>&1; then
    fail "git still reads $1's index after the cut"
  fi
}

# Assert that one whole line of the output, less its leading blanks, is exactly
# the given text.
#
# THE WHOLE LINE, BECAUSE A COMMAND LINE CAN BE A PREFIX OF ANOTHER. fullcycle's
# preview prints the clean phase with its flags, and an arm asserting that it
# contained `clean rust --force-blocked --force` stayed green over a preview
# that dropped the `--refuse-partial` after it (issue 0131). Fixed text, not a
# pattern: nothing in the expected line is read as
# regex syntax.
assert_output_line() {
  local expected="$1" line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [ "$line" != "$expected" ] || return 0
  done <<<"$output"
  fail "Expected a whole output line: '$expected'\nActual output:\n$output"
  return 1
}

# assert_find_denied <path> [<text>] -- find's own error says it could not read
# <path>: "Permission denied" directly after the path, in each form find prints
# it. BSD's is bare, `find: <path>: Permission denied`. GNU's quotes the path by
# locale: 'path' in the C locale, and U+2018 and U+2019 around it under any UTF-8
# locale -- which is CI's -- measured with GNU findutils 4.11.0 (issue 0139:
# arms that accepted BSD's form and the C locale's only would all have failed
# on the Ubuntu leg). GNU's quotes are folded to ASCII first, so one test
# covers every form. <path> may be a trailing part of the path, taken from a
# slash, so locked names .../locked and never .../unlocked, or a whole path,
# taken from the quote or the ": " find puts before it -- never from a space
# inside a name. <text> defaults to $output.
assert_find_denied() {
  local path="$1" text="${2-$output}"
  text="${text//$'\xe2\x80\x98'/\'}"
  text="${text//$'\xe2\x80\x99'/\'}"
  # What comes before the path is a slash, a quote or the ": " after find's
  # name, never a letter of a longer name and never a space inside one.
  local sep
  for sep in / "'" ": "; do
    [[ "$text" == *"$sep$path: Permission denied"* || "$text" == *"$sep$path': Permission denied"* ]] && return 0
  done
  fail "find's error naming $path is not in the output: $text"
  return 1
}

# utf8_locale [en_US] -- a UTF-8 locale this runner has: en_US's if it is
# there, else C's, spelled UTF-8 or utf8 either way; with the argument en_US,
# en_US's only, for an arm that needs its collation. It prints the name, or
# returns 1 so the arm can skip saying so. One picker where three were spelled
# three ways.
utf8_locale() {
  local l
  if l="$(locale -a 2>/dev/null)" && l="$(grep -m1 -iE '^en_US\.utf-?8$' <<<"$l")"; then
    printf '%s\n' "$l"
    return 0
  fi
  [ "${1:-}" != en_US ] || return 1
  if l="$(locale -a 2>/dev/null)" && l="$(grep -m1 -iE '^C\.utf-?8$' <<<"$l")"; then
    printf '%s\n' "$l"
    return 0
  fi
  return 1
}

# refute_digest_line [<text> [<when>]] -- no line of <text>, which defaults to
# $output, is a runtime digest: twelve hex digits alone on a line. One spelling
# of the check that a failing runtime_digest printed none, where version.bats
# wrote the pattern out five times.
refute_digest_line() {
  local text="${1-$output}"
  [[ "$text" =~ (^|$'\n')[0-9a-f]{12}($|$'\n') ]] || return 0
  fail "a runtime digest was printed${2:+ $2}: $text"
  return 1
}

assert_file_exists() {
  local filepath="$1"
  if [[ ! -f "$filepath" ]]; then
    fail "Expected file to exist: $filepath"
    return 1
  fi
}

assert_file_not_exists() {
  local filepath="$1"
  if [[ -e "$filepath" ]]; then
    fail "Expected path NOT to exist: $filepath"
    return 1
  fi
}

assert_directory_exists() {
  local dirpath="$1"
  if [[ ! -d "$dirpath" ]]; then
    fail "Expected directory to exist: $dirpath"
    return 1
  fi
}

assert_directory_not_exists() {
  local dirpath="$1"
  if [[ -d "$dirpath" ]]; then
    fail "Expected directory NOT to exist: $dirpath"
    return 1
  fi
}

assert_executable() {
  local filepath="$1"
  if [[ ! -x "$filepath" ]]; then
    fail "Expected executable: $filepath"
    return 1
  fi
}

assert_file_contains() {
  local filepath="$1" expected="$2"
  if [[ ! -f "$filepath" ]]; then
    fail "Cannot check file contents - file does not exist: $filepath"
    return 1
  fi
  if ! grep -qF -- "$expected" "$filepath"; then
    fail "Expected file '$filepath' to contain: '$expected'\nActual contents:\n$(cat "$filepath")"
    return 1
  fi
}

refute_file_contains() {
  local filepath="$1" unexpected="$2"
  if [[ ! -f "$filepath" ]]; then
    fail "Cannot check file contents - file does not exist: $filepath"
    return 1
  fi
  if grep -qF -- "$unexpected" "$filepath"; then
    fail "Expected file '$filepath' NOT to contain: '$unexpected'\nActual contents:\n$(cat "$filepath")"
    return 1
  fi
}

# Assert a file is empty. This is the sealed-gate verdict assertion (WP-06): an
# .errors companion is green exactly when it is empty, so this reads as the
# domain concept rather than as a size check.
assert_file_empty() {
  local filepath="$1"
  if [[ ! -f "$filepath" ]]; then
    fail "Expected file to exist: $filepath"
    return 1
  fi
  if [[ -s "$filepath" ]]; then
    fail "Expected '$filepath' to be empty (green verdict)\nActual contents:\n$(cat "$filepath")"
    return 1
  fi
}

# mode_of <file> -- the permission string `ls` prints, eg -rw-r-----. stat's
# flags differ between BSD and GNU; ls's first ten columns do not. One home for
# the suites that assert a writer kept a file's mode.
mode_of() {
  # shellcheck disable=SC2012  # one named file, and ls is the portable mode reader
  ls -ld "$1" | cut -c1-10
}

# inode_of <file> -- the file's inode number. A rename puts a different file at
# the path, so the number changes; a write in place keeps it.
inode_of() {
  # shellcheck disable=SC2012  # one named file, and ls is the portable inode reader
  ls -i "$1" | awk '{ print $1 }'
}

# seal_of <dir> <suffix> -- the seal THIS run wrote, resolved through the
# LATEST_* pointer, for tests that then read the file.
#
# ONE HOME, because more than one file needs it. Tests resolve the pointer here where
# production code deliberately never does: `print_run_verdict` names the seal
# directly precisely so a peer's later run cannot relink under it. A test is
# single-writer inside its own tmpdir, so the pointer is safe to follow -- and
# that difference is the reason this belongs in the harness rather than being
# copied into each suite that wants it.
seal_of() {
  printf '%s' "$(readlink -f "$1/LATEST_$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]').errors" 2>/dev/null || true)"
}

assert_symlink_exists() {
  local link_path="$1" expected_target="${2:-}" actual_target
  if [[ ! -L "$link_path" ]]; then
    fail "Expected symlink to exist: $link_path"
    return 1
  fi
  if [[ -n "$expected_target" ]]; then
    actual_target="$(readlink "$link_path")"
    if [[ "$actual_target" != "$expected_target" ]]; then
      fail "Expected symlink '$link_path' to point to '$expected_target' but points to '$actual_target'"
      return 1
    fi
  fi
}

# Explicit test failure with message
#
# `%b` rather than interpolating the message into the FORMAT string. Messages
# embed the actual output under test, and the moment that output contains a `%`
# printf reads it as a conversion spec: the assertion then dies with "invalid
# format character" and prints nothing useful, so a real failure is reported as
# gibberish. %b keeps the `\n` expansion these messages rely on while treating
# the message strictly as data.
fail() {
  local message="$1"
  printf 'FAILURE: %b\n' "$message" >&2
  return 1
}

# refute_assertion <assertion> [args...] -- assert that an assertion FAILS.
#
# The obvious spelling, `! (assert_foo bad 2>/dev/null)`, does not work under
# BATS: the assertion's internal `fail` trips BATS's ERR trap inside the
# subshell, and the resulting stack trace is attributed to the PRECEDING line in
# the test body. The symptom is a *passing* assertion reported as the failure,
# which is worse than no negative test at all -- it sends you debugging correct
# code. Clearing the ERR trap is what makes the negative case reportable.
#
# Note that errexit cannot be preserved here even in principle: a subshell on
# the left of `||` has errexit suppressed inside it, and capturing the exit code
# requires exactly that form. This works only because every assertion above
# returns 1 EXPLICITLY rather than relying on errexit to stop it. If that
# discipline lapses, this helper silently starts reporting false passes.
#
# Only for assertions that do NOT read $status/$output. Testing those with `run`
# is circular, since `run` overwrites the very globals they inspect.
refute_assertion() {
  local rc=0
  ( trap - ERR; "$@" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "Expected assertion to FAIL but it passed: $*"
    return 1
  fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# require_command <cmd> [message] [rule] -- the tool a test needs, and what to
# do when it is absent. Skip on a developer's machine; FAIL under CI, unless the
# call names the rule that keeps the tool off CI.
#
# THE ASYMMETRY IS THE WHOLE POINT, and it was bought with a red CI run.
# The Ubuntu job once went red with DMARC `parse` arms needing `xmllint` and
# zsh arms needing `zsh`, neither tool installed on that runner. Both were
# FIRST EXPOSURE rather than regression -- the files landed
# while nothing was being pushed, so CI had never run them on Linux at all.
#
# A skip would have made that run green, and THAT is the failure this rule
# exists to refuse: on a runner the project controls, an absent tool is a
# missing apt line, never a fact about the world. A skip there converts a
# coverage hole into a passing run, silently, and the population shrinks with
# nothing reporting it -- the exact defect `infra check` is being built to catch,
# in the suite that checks it.
#
# On a developer's machine the opposite holds: their laptop is not the project's
# to provision, and an arm that fails because they have no zsh is noise they
# cannot act on. Same call, two environments, and the environment decides.
#
# So a guard removed from the workflow later cannot quietly revert to skips:
# delete the apt line and CI goes RED naming the tool, which is how this rule
# stays true rather than merely being written down here.
#
# THE ONE EXCEPTION IS A RULE, AND THE CALL CARRIES IT. A tool the project has
# DECIDED not to install on CI is not a missing apt line: prettier stays off
# CI. Failing there would turn every CI run red on a decision rather than a
# defect. The third argument names the rule, and CI then skips with the rule
# in the message, so the narrowing is stated on every run rather than
# discovered. A call without one still fails.
#
# Usage: require_command zsh
#        require_command yq "yq is required for this test"
#        require_command prettier "..." "CI does not install prettier"
require_command() {
  local cmd="$1" message="${2:-no $1 on this runner}" rule="${3:-}"
  command_exists "$cmd" && return 0
  if [[ -n "${CI:-}" ]]; then
    [[ -z "$rule" ]] || skip "$message -- not installed on CI, by rule: $rule"
    fail "$cmd is not installed on this CI runner.\n         A skip here would be a coverage hole reported as a pass -- install it\n         in .github/workflows/tests.yml rather than skipping the arm."
    return 1
  fi
  skip "$message"
}

debug() {
  if [[ "${DEVBIN_TEST_DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: $*" >&2
  fi
}

# ---------------------------------------------------------------------------
# A CONTROLLED TTY, because one command in this project deliberately ignores
# stdin
# ---------------------------------------------------------------------------

# require_pty -- skip the calling test unless the child's tty can be controlled.
#
# THE FALLBACK IS A SKIP AND NEVER THE UNGUARDED FORM. A test that hangs the
# suite is worse than one that declares it could not run, and the unguarded form
# does not fail on a developer's machine -- it waits on the developer.
require_pty() {
  command -v script >/dev/null 2>&1 ||
    skip "no script(1) on this runner: the child's controlling terminal cannot be controlled"
}

# run_tty_eof <cmd> [args...] -- run a command whose controlling terminal is a
# fresh pty already at EOF. Exit status and output are the child's, so this
# composes with bats `run` exactly as a bare command does.
#
# WHY IT EXISTS, AND IT IS NOT A CONVENIENCE. `_clean_confirm` (lib/cmd/clean)
# READS /dev/tty AND NOT STDIN. That is deliberate and documented there:
# run_gate puts the verb behind tee, so a prompt written and read through that
# plumbing is fragile. The consequence for a TEST is that redirecting stdin
# answers nothing -- `</dev/null` leaves /dev/tty pointing at whatever terminal
# the runner happens to have.
#
# SO THE ARM'S OUTCOME DEPENDED ON WHETHER A HUMAN WAS SITTING AT THE TERMINAL,
# which is the one variable a suite must never be sensitive to. With no live
# terminal the read fails and the command declines, and the arm passed. With one
# -- a person typing `bin/devbin test` -- the read BLOCKS ON THAT PERSON.
# Measured: the suite stopped partway and sat 54 minutes before it was killed
# by hand, reporting exit 141 and a log it declared untrustworthy.
#
# `script` allocates a NEW pty and makes it the child's controlling terminal,
# then copies its own stdin into it. With that stdin at /dev/null the child's
# read of /dev/tty returns EOF at once -- which IS the unanswered state the arm
# is about -- identically on a runner with a terminal and on one without.
#
# TWO FLAVOURS, AND THEY DISAGREE ON ARGV. BSD/macOS takes the command as
# argv after the file and already propagates the child's status. util-linux
# takes a single -c string and needs -e to return it at all; without -e a red
# child would read as green here, which is the failure this file exists to
# prevent.
#
# THE PTY TRANSLATES \n TO \r\n and script prefixes its own ^D. Substring
# assertions are unaffected; an assertion anchored to end-of-line is not, so
# match on content rather than on line ends.
# require_expect -- skip unless `expect` is on this machine.
#
# STATED AS A SKIP RATHER THAN HIDDEN, because a test that quietly does nothing
# on a platform is the "sound instrument aimed one unit wide" defect this
# project keeps catching. macOS ships /usr/bin/expect; a minimal Linux image
# does not, so the arms below run for the operator and are SKIPPED in CI --
# which is a real narrowing and is said out loud here rather than discovered.
require_expect() {
  command -v expect >/dev/null 2>&1 || skip "expect is not installed"
}

# run_tty_answer <answer> <cmd> [args...] -- run <cmd> on a pty and TYPE
# <answer> when it prompts.
#
# WHY NOT `script`, WHICH THE FILE ALREADY USES. Measured on this machine:
# BSD `script` does not deliver its own stdin into the pty in a way a child's
# `read </dev/tty` can see -- the read fails outright, with or without a delay
# before the answer. So `run_tty_eof` can prove a question was ASKED and that
# EOF declines safely, and it can NEVER prove that answering does the thing.
# A yes branch wired to nothing passes every arm built on `script`.
#
# `expect` waits for the prompt before sending, so there is no race to lose and
# no `sleep` to make the suite timing-dependent.
#
# THE STATUS IS THE COMMAND'S ON BOTH PATHS (issue 0090). When no prompt
# appears the first `expect` takes `eof`, and a bare second `expect eof` then
# errors on the closed spawn, so the caller saw expect's status. `catch` makes
# that second wait a no-op on a closed spawn, and `wait` still reaps the
# command's own exit code.
#
# EVERY WAIT IS BOUNDED, AND RUNNING OUT IS A NAMED FAILURE (issue 0091). The
# prompt wait used to take `timeout { }`, send nothing, and fall through to a
# `wait` with no limit on a child still sitting at its prompt -- so a prompt
# that was merely SLOW hung the whole suite silently, for about seven hours.
# Now a prompt that does not come within
# DEVBIN_TEST_TTY_PROMPT_WAIT seconds, or a command that does not finish within
# DEVBIN_TEST_TTY_FINISH_WAIT seconds of the answer, kills the command's
# process group and exits 124 saying which wait ran out. The defaults are wide,
# because a loaded machine is the case that hung, and the knobs exist so
# the arms that hold this can run in a second.
#
# ONE WAIT IS STILL UNBOUNDED, AND IT IS DECLARED RATHER THAN CLOSED (issue
# 0091): the final `wait`, after `eof`. A command that closes the pty
# and keeps running -- a daemon, say -- would block there. Nothing in the suite
# does that today; a caller that starts one owns stopping it.
#
# DEVBIN_TEST_TTY_ANSWER_DELAY holds the answer back that many seconds after the
# prompt appears (default 0, so no existing arm changes): a person thinking, for
# the arms that measure what a wait on a person is charged to (issue 0096).
run_tty_answer() {
  local answer="$1"
  shift
  local prompt_wait="${DEVBIN_TEST_TTY_PROMPT_WAIT:-120}"
  local finish_wait="${DEVBIN_TEST_TTY_FINISH_WAIT:-300}"
  local answer_delay="${DEVBIN_TEST_TTY_ANSWER_DELAY:-0}"
  local quoted="" a
  for a in "$@"; do quoted+="$(printf '%q ' "$a")"; done
  expect -c "
    proc give_up {why} {
      puts \"\nrun_tty_answer: \$why; the command was killed\"
      catch {exec kill -KILL -[exp_pid]}
      catch close
      catch wait
      exit 124
    }
    log_user 1
    spawn -noecho sh -c {$quoted}
    set timeout $prompt_wait
    expect {
      -re {\[y/N\]} { sleep $answer_delay; send \"$answer\r\" }
      timeout { give_up {no [y/N] prompt within ${prompt_wait}s} }
      eof { }
    }
    set timeout $finish_wait
    catch {
      expect {
        timeout { give_up {the command did not finish within ${finish_wait}s of the answer} }
        eof { }
      }
    }
    catch wait result
    exit [lindex \$result 3]
  " 2>&1
}

run_tty_eof() {
  if script --version >/dev/null 2>&1; then
    local quoted=""
    local a
    for a in "$@"; do quoted+="$(printf '%q ' "$a")"; done
    script -q -e -c "$quoted" /dev/null </dev/null
  else
    script -q /dev/null "$@" </dev/null
  fi
}

# ---------------------------------------------------------------------------
# Standing in the project, which is the only invocation the dispatcher permits
# ---------------------------------------------------------------------------

# devbin_run <proj> [args...] -- run a fixture project's devbin FROM INSIDE it.
#
# WHY EVERY CALL SITE CHANGED. The dispatcher refuses to run when the caller's
# directory is outside its own PROJECT_ROOT, because PROJECT_ROOT is derived
# from the script's location and a devbin reached through PATH otherwise acts
# on ITS OWN tree from wherever you are standing. Measured: a bare `devbin` in
# a project with no devbin installed printed a DIFFERENT project's catalogue at
# rc 0, and the same resolution would have pointed `clean --force` at that
# project's tree.
#
# THE SUITE WAS THE LARGEST PRODUCER OF THE BANNED SHAPE. `mkproj` builds under
# $DEVBIN_TEST_TMPDIR and the harness stands in that tmpdir, so PROJECT_ROOT was
# always a CHILD of the cwd -- 365 invocations a run, none of which any test
# asserted anything about. The suite had been exercising the defect rather than
# the supported path.
#
# A SUBSHELL RATHER THAN A BARE cd, and that is the load-bearing part: the cwd
# never leaks past the call, so a test holding two fixtures does not have to
# reason about which one it is standing in. That is also why this could not be
# fixed inside `mkproj` -- callers consume it as `proj="$(mkproj ...)"`, and a
# cd inside a command substitution dies with the subshell.
#
# NO ESCAPE HATCH EXISTS, deliberately. A variable that switches the guard off
# is a variable anything can set, so the suite complies with the rule instead of
# being excused from it. Environment prefixes still work: `VAR=x run devbin_run
# "$proj" ...` sets VAR for the call and the function inherits it.
# `</dev/null` IS NOT COSMETIC. A test that inherits the operator's stdin can be
# asked a question the operator cannot see: bats captures the prompt into
# `$output`, so a confirm reads as an indefinite hang rather than as a question.
# It is invisible on any runner without a real terminal, which is every runner
# that has ever measured this suite. Paired with `_clean_confirm`'s `-t 0` test
# -- neither half works alone, because `read </dev/tty` ignores stdin and only
# the product can decline to open the terminal. Issue 0058.
devbin_run() {
  local proj="$1"
  shift
  ( cd "$proj" && ./bin/devbin "$@" </dev/null )
}

# stub_uname <flag> <variable> -- a uname first on PATH that answers `uname
# <flag>` alone, with the value <variable> holds when it runs, and hands every
# other question to the uname that was first on PATH before it, so only that
# answer changes: the architecture a cache key reads (-m), or the OS name the
# platform word is read from (-s). Every devbin call after it sets <variable>.
stub_uname() {
  local flag="$1" var="$2" real dir="$DEVBIN_TEST_TMPDIR/uname-stub$1"
  real="$(command -v uname)" || {
    fail "there is no uname on PATH to hand the other questions to"
    return 1
  }
  mkdir -p "$dir"
  # <flag>, <variable> and the real uname's path are written in now; the
  # escaped expansions are the stub's own, read when it runs.
  printf '%s\n' '#!/usr/bin/env bash' \
    "if [ \"\$*\" = $flag ]; then printf \"%s\\n\" \"\${$var:-}\"; exit 0; fi" \
    "exec '$real' \"\$@\"" >"$dir/uname"
  chmod +x "$dir/uname"
  export PATH="$dir:$PATH"
}

# stub_cargo -- a cargo first on PATH that answers --version alone, as `cargo
# <version> (stub)`: the version in ./.stub-toolchain where it is run, else
# CARGO_STUB_VERSION, 1.0.0 unless set. It fails when CARGO_STUB_FAIL is set,
# and with CARGO_STUB_CHATTER set says a line on stderr first, as rustup can.
stub_cargo() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/stubs"
  # shellcheck disable=SC2016 # expanded when the stub runs
  printf '%s\n' '#!/usr/bin/env bash' \
    '[ -z "${CARGO_STUB_CHATTER:-}" ] || echo "info: syncing channel updates" >&2' \
    '[ -z "${CARGO_STUB_FAIL:-}" ] || exit 1' \
    'v="${CARGO_STUB_VERSION:-1.0.0}"' \
    '[ ! -f .stub-toolchain ] || v="$(cat .stub-toolchain)"' \
    'case "${1:-}" in' \
    '  --version) printf "cargo %s (stub)\n" "$v" ;;' \
    '  *) echo "stub cargo: only --version, not: $*" >&2; exit 64 ;;' \
    'esac' >"$DEVBIN_TEST_TMPDIR/stubs/cargo"
  chmod +x "$DEVBIN_TEST_TMPDIR/stubs/cargo"
  export PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH"
}

# windows_path -- print PATH with a Windows PATH appended, as WSL appends it
# while appendWindowsPath is on (ST0008): an entry under Program Files
# (x86), whose name carries spaces and parentheses, written with a trailing
# slash, then one standing for System32. Each holds a stub <tool>.exe for a
# sample of the tools the runtime runs, not every one: lookups are by exact
# name, so no <tool>.exe can answer for <tool>, and the sample shows that. A
# stub that runs appends its own path to $DEVBIN_TEST_TMPDIR/exe-ran and exits
# 97; refute_windows_exe_ran reads it.
windows_path() {
  local d t pf="$DEVBIN_TEST_TMPDIR/mnt/c/Program Files (x86)/Tool Kit/bin"
  local sys="$DEVBIN_TEST_TMPDIR/mnt/c/WINDOWS/system32"
  for d in "$pf" "$sys"; do
    mkdir -p "$d" || return 1
    for t in awk bash bats cargo date env find git grep jq mktemp parallel readlink sed sh shellcheck stat tr; do
      # shellcheck disable=SC2016 # $0 is the stub's own, expanded when it runs
      printf '#!/bin/sh\nprintf "%%s\\n" "$0" >>"%s/exe-ran"\nexit 97\n' "$DEVBIN_TEST_TMPDIR" >"$d/$t.exe" || return 1
      chmod +x "$d/$t.exe" || return 1
    done
  done
  printf '%s:%s/:%s\n' "$PATH" "$pf" "$sys"
}

refute_windows_exe_ran() {
  [ ! -e "$DEVBIN_TEST_TMPDIR/exe-ran" ] ||
    fail "a Windows executable ran in place of a Linux tool: $(cat "$DEVBIN_TEST_TMPDIR/exe-ran")"
}

# path_without <tool> -- PATH with <tool> gone from every entry that holds one,
# on stdout; rc 1, with a line on stderr naming which step failed, when an
# entry cannot be read or stood in for, or <tool> is still found.
#
# ENTRY BY ENTRY, NEVER AS TEXT (0234). A machine can carry more than one copy,
# eg Homebrew's cargo and then rustup's, or Homebrew's devbin and a link in the
# runner's ~/.local/bin, so each entry holding <tool> is swapped, in place, for
# a directory of links to everything in it but <tool>, and the rest stay as
# they are, in order. Editing PATH as text would also rewrite any entry that
# merely contains a swapped one. The links are made from the entry's physical
# path, so a relative entry's links do not resolve inside the stand-in.
#
# IN A SUBSHELL OF ITS OWN, as lib/helpers sets the shell options it runs
# under: PATH is split by lib/helpers' colon_split (0248), which not every
# suite that asks this has sourced.
path_without() (
  local tool="$1" e pe f i shadow found
  local -a entries
  # shellcheck source=lib/helpers
  if ! . "$DEVBIN_LIB_DIR/helpers"; then
    printf 'path_without: cannot source %s\n' "$DEVBIN_LIB_DIR/helpers" >&2
    return 1
  fi
  colon_split "$PATH" entries || return 1
  # An empty entry is the current directory, to a lookup and so here.
  for i in "${!entries[@]}"; do
    e="${entries[i]:-.}"
    [ -f "$e/$tool" ] && [ -x "$e/$tool" ] || continue
    if ! pe="$(cd -P -- "$e" && pwd -P)"; then
      printf 'path_without: cannot enter %s, which holds %s\n' "$e" "$tool" >&2
      return 1
    fi
    if ! shadow="$(mktemp -d "$DEVBIN_TEST_TMPDIR/no$tool.XXXXXX")"; then
      printf 'path_without: cannot make a directory to stand for %s\n' "$e" >&2
      return 1
    fi
    for f in "$pe"/*; do
      [ "${f##*/}" != "$tool" ] || continue
      if ! ln -s "$f" "$shadow/${f##*/}"; then
        printf 'path_without: cannot link %s into %s\n' "$f" "$shadow" >&2
        return 1
      fi
    done
    # shellcheck disable=SC2030 # the subshell is the point: the entries are this call's own, handed back on stdout
    entries[i]="$shadow"
  done
  e="$(IFS=:; printf '%s' "${entries[*]}")"
  if found="$(PATH="$e" command -v "$tool")"; then
    printf 'path_without: %s is still on PATH, at %s\n' "$tool" "$found" >&2
    return 1
  fi
  printf '%s\n' "$e"
)

# fixture_run <proj> <script> [args...] -- <script> run as bash, with the args
# as its "$@", inside <proj> the way bin/devbin sets up: from the project root,
# with the dispatcher's environment, the fixture's vendored libraries sourced,
# its config loaded, and bin/devbin's shell options (IN-SH-CODE-003).
# fixture_ask <proj> <function> [args...] -- one runtime function, asked so.
#
# ITS OWN FAILURES HAVE ITS OWN CODES: 8 when the project root cannot be
# entered or a library cannot be read, 9 when the config does not load, so an
# arm never reads a failed setup as an answer. 1 is not the asked function's
# alone -- strict mode also exits 1 on an unbound variable -- so an arm that
# asserts 1 needs its output, or a control asked the same way, to say it was
# the function's answer.
#
# AND IT IS NOT production's CALLING CONTEXT. The asked function runs as the
# script's last plain command, so errexit is ON inside it; production asks most
# of these inside `$(...) ||`, `if` or `&&`, where bash turns errexit off for
# the whole call. A function that leaned on errexit being off would fail here
# and not there.
#
# ONE HELPER FOR THE ARMS THAT ASK THE RUNTIME DIRECTLY (issue 0128).
# dispatch.bats and help.bats each carried a copy, and help.bats a third
# inline, and they had drifted: only one ran under the shell options production
# sets, so the others asked the code under a shell it never meets.
fixture_run() {
  local proj="$1" script="$2"
  shift 2
  (
    cd "$proj" || exit 8
    PROJECT_ROOT="$proj" DEVBIN_DIR="$proj/bin/.devbin" DEVBIN_LIB="$proj/bin/.devbin/lib" \
      DEVBIN_INVOKE=bin/devbin DEVBIN_NAME=demo bash -c '
        set -euo pipefail
        for _fx_lib in helpers config builtins runlog resolve help; do
          [ -r "$DEVBIN_LIB/$_fx_lib" ] || exit 8
        done
        unset _fx_lib
        . "$DEVBIN_LIB/helpers"; . "$DEVBIN_LIB/config"; . "$DEVBIN_LIB/builtins"
        . "$DEVBIN_LIB/runlog"; . "$DEVBIN_LIB/resolve"; . "$DEVBIN_LIB/help"
        cfg_load "$DEVBIN_DIR/config.yaml" >/dev/null || exit 9
        DEVBIN_NAME="$(cfg_get project.name 2>/dev/null || true)"
        DEVBIN_NAME="${DEVBIN_NAME:-demo}"
        '"$script" _ "$@"
  )
}
fixture_ask() {
  local proj="$1"
  shift
  fixture_run "$proj" '"$@"' "$@"
}

# fixture_catalogue_count <proj> <command> -- how many options devbin's catalogue
# ships for a command, read from the fixture's own vendored catalogue so no arm
# types the number. The count lines of dispatch.bats and data.bats are read
# against it. A catalogue that could not be read fails, never reads as empty.
fixture_catalogue_count() {
  local names
  # shellcheck disable=SC2016 # the script is fixture_run's, which expands $1
  names="$(fixture_run "$1" 'builtin_options_for "$1"' "$2")" || return 1
  awk 'NF { n++ } END { print n + 0 }' <<<"$names"
}

# mkdevsrc [name] -- a CLEAN fixture dev tree, on stdout.
#
# devbin's runtime plus a git repo of its own plus an `install.prefix` pointing
# INSIDE the test tmpdir. Shared, because both install.bats and localinstall.bats
# need one and a second copy would drift.
#
# WHY NOT JUST USE $DEVBIN_HOME. It is devbin's real source tree, so publish mode
# there resolves the real `install.prefix` and writes to the maintainer's own
# opt install -- the tree every project on the machine vendors from. And the
# DIRTY GATE could not be exercised
# against it in either direction: whether the operator's working tree happens to
# be clean is not a thing a test may set, so both arms would be flaky and one of
# them would be flaky in the direction that passes.
#
# `git init` is not decoration. `install`/`upgrade` in publish mode ask git what
# commit the bytes correspond to and refuse a tree that is not a repository at
# all -- "no changes" and "cannot tell" must never render as the same answer.
mkdevsrc() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-devsrc}"
  mkdir -p "$dir/bin/.devbin"
  cp "$DEVBIN_HOME/bin/devbin" "$dir/bin/devbin"
  cp -R "$DEVBIN_HOME/lib" "$dir/lib"
  {
    printf 'project:\n  name: fixturesrc\n'
    printf 'devbin_version: "^0.1.0"\n'
    printf 'install:\n  prefix: %s/opt/devbin\n' "$DEVBIN_TEST_TMPDIR"
  } >"$dir/bin/.devbin/config.yaml"
  git -C "$dir" init -q >/dev/null 2>&1
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m fixture >/dev/null 2>&1
  printf '%s\n' "$dir"
}

# switch_to <tree> -- this test's switch names <tree>, as `devbin use dev` or
# `use opt` leaves it: the link $HOME/.local/bin/devbin to <tree>/bin/devbin
# (issue 0213). For an arm whose subject is not `use` itself, so it need not run
# the verb from a checkout; use.bats drives the verb.
#
# NEVER OUTSIDE THE TEST'S OWN DIRECTORY: under HOME when HOME is inside it, as
# an arm that moves HOME within its tmp expects, and otherwise in the test's
# own home. An arm that points HOME at a real directory (the checkout's parent,
# to read a `~/` path) must never have a link written there.
switch_to() {
  local d
  case "${HOME:-}" in
    "$DEVBIN_TEST_TMPDIR" | "$DEVBIN_TEST_TMPDIR"/*) d="${HOME%/}/.local/bin" ;;
    *) d="$DEVBIN_TEST_TMPDIR/home/.local/bin" ;;
  esac
  mkdir -p "$d" || return 1
  ln -sfn "$1/bin/devbin" "$d/devbin"
}

# stub_install <root> <source> [<header line>...] -- a machine install at
# <root> written by hand, whose launcher nothing runs: bin/devbin, one file
# under bin/.devbin/lib/, and a manifest whose header records devbin 0.1.0,
# `kind: install`, `source: <source>` and a commit, then each <header line>
# (eg `managed_by: brew`) as one more `# ` line.
#
# THE ONE WRITER OF A STUB INSTALL (issue 0288). machinepointer.bats'
# fake_install, another suite's prefix helper and brew_keg --stub each wrote
# one by hand, differing only in their header lines, so a change to what an
# install's manifest carries had three places to be made. Every step returns
# its failure, as brew_keg's do.
stub_install() {
  local root="$1" source="$2" line
  shift 2
  mkdir -p "$root/bin/.devbin/lib" || return 1
  printf '#!/usr/bin/env bash\necho install\n' >"$root/bin/devbin" || return 1
  printf 'lib bytes\n' >"$root/bin/.devbin/lib/helpers" || return 1
  {
    printf '# devbin_version: 0.1.0\n# kind: install\n# source: %s\n# source_commit: aaaabbbbccccdddd\n' "$source"
    for line in "$@"; do
      printf '# %s\n' "$line"
    done
  } >"$root/bin/.devbin/manifest.sha256" || return 1
}

# brew_keg [--from <src> | --stub | --empty] [--script]
#   [--linked | --linked-to <path>] <version> --
# devbin's keg for <version> as Homebrew places one, at the test's
# $HOMEBREW_PREFIX/Cellar/devbin/<version>, with opt linked to it, as brew links
# the keg it has just installed, moving the link off any earlier one.
#
# THE ONE KEG BUILDER (issue 0270): every test file asks it, so a change to the
# formula's layout, as 0253's env script was, is followed here once, and no arm
# tests a layout no formula writes. Its libexec is one of:
#
#   published  the default: from <src>, or from a fresh dev source (mkdevsrc),
#              as the formula does, install --prefix <keg>/libexec --managed-by brew
#              and the guides it puts beside libexec (keg_guides, 0254)
#   --stub     an install written by hand (stub_install), marked as Homebrew's,
#              whose launcher nothing runs: for an arm that reads a keg and
#              never runs it
#   --empty    a directory holding no devbin: for an opt link that names no
#              install, so the keg has no bin/devbin either
#
# The keg's own bin/devbin is linked to libexec's launcher, as the formula
# writes it on Linux, or with --script is the formula's env script on macOS
# (brew_keg_env_script). --linked adds Homebrew's bin link to it, as `brew link`
# makes it. --linked-to makes that bin link lead to <path> instead, as a hand
# might make it and brew link never does: for an arm about a bin link that
# reaches the keg only through another link (issue 0249). The switch's link is
# the arm's own business, never the keg's.
#
# EVERY STEP RETURNS ITS FAILURE, as switch_to's do, rather than leaning on
# bats' errexit, which a caller in a condition or a subshell turns off.
brew_keg() {
  local from="" what="" script=0 linked=0 to="" keg
  while [ "$#" -gt 1 ]; do
    case "$1" in
      --from | --stub | --empty)
        [ -z "$what" ] || {
          fail "brew_keg: $1 is a second choice of libexec, after --$what"
          return 1
        }
        what="${1#--}"
        if [ "$1" = --from ]; then
          from="$2"
          shift
        fi
        ;;
      --script) script=1 ;;
      --linked) linked=1 ;;
      --linked-to)
        linked=1
        to="$2"
        shift
        ;;
      *)
        fail "brew_keg: unknown option '$1'"
        return 1
        ;;
    esac
    shift
  done
  case "${1:-}" in
    "" | -*)
      fail "brew_keg: no version, where the last word is '${1:-}'"
      return 1
      ;;
  esac
  keg="$HOMEBREW_PREFIX/Cellar/devbin/$1"
  case "${what:-from}" in
    from)
      [ -n "$from" ] || from="$(mkdevsrc)" || return 1
      run devbin_run "$from" install --prefix "$keg/libexec" --managed-by brew
      assert_success || return 1
      keg_guides "$keg" || {
        fail "brew_keg: the keg's guides could not be copied in"
        return 1
      }
      ;;
    stub)
      stub_install "$keg/libexec" checkout "managed_by: brew" || return 1
      ;;
    empty)
      [ "$script$linked" = 00 ] || {
        fail "brew_keg: an --empty keg has no bin/devbin to script or link"
        return 1
      }
      mkdir -p "$keg/libexec" || return 1
      ;;
  esac
  mkdir -p "$HOMEBREW_PREFIX/opt" || return 1
  ln -sfn "../Cellar/devbin/$1" "$HOMEBREW_PREFIX/opt/devbin" || return 1
  [ "$what" != empty ] || return 0
  if [ "$script" = 1 ]; then
    brew_keg_env_script "$1" || return 1
  else
    mkdir -p "$keg/bin" || return 1
    ln -sfn ../libexec/bin/devbin "$keg/bin/devbin" || return 1
  fi
  [ "$linked" = 1 ] || return 0
  mkdir -p "$HOMEBREW_PREFIX/bin" || return 1
  ln -sfn "${to:-../Cellar/devbin/$1/bin/devbin}" "$HOMEBREW_PREFIX/bin/devbin" || return 1
}

# brew_keg_env_script <version> -- the keg's bin/devbin made the script the
# formula writes on macOS (write_env_script, issue 0253): one of its own that
# puts a bash first on PATH and runs libexec's launcher, so it resolves to
# itself, never into libexec. The bash is the test's own, standing in for the
# formula's opt/bash, and the mode is 0555, as Homebrew leaves it. brew_keg's
# --script, and an arm that moves a keg it built from the Linux layout to this
# one: the link is removed first, so the script is never written through it.
brew_keg_env_script() {
  local keg="$HOMEBREW_PREFIX/Cellar/devbin/$1"
  mkdir -p "$keg/bin" || return 1
  rm -f "$keg/bin/devbin" || return 1
  # shellcheck disable=SC2016 # $PATH and $@ are the script's own, expanded when it runs
  printf '#!/bin/bash\nPATH="%s:$PATH" exec "%s" "$@"\n' "${BASH%/*}" "$keg/libexec/bin/devbin" >"$keg/bin/devbin" || return 1
  chmod 0555 "$keg/bin/devbin"
}

# formula_keg_names <formula> -- what <formula>'s install puts at the keg root
# by `prefix.install`, one name a line, in the order it names them (issue
# 0254). Read from the formula, never listed here, so a keg a test builds holds
# what the formula installs and nothing a test chose.
formula_keg_names() {
  awk '/^[[:space:]]*prefix\.install[[:space:]]/ { n = split($0, f, "\""); for (i = 2; i < n; i += 2) print f[i] }' "$1"
}

# keg_guides <keg> -- the guides the formula installs beside the keg's README,
# copied from devbin's own tree into <keg> by the names its template gives
# (formula_keg_names), as Homebrew's prefix.install moves them out of the
# tag's checkout (issue 0254). A formula that names nothing installs nothing
# beside the README, so nothing is copied; a formula that cannot be read, and a
# name the tree does not hold, each fail.
keg_guides() {
  local n names
  names="$(formula_keg_names "$DEVBIN_HOME/packaging/homebrew/devbin.rb")" || return 1
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    cp -R "$DEVBIN_HOME/$n" "$1/$n" || return 1
  done <<<"$names"
}

# assert_guides_at <dir> -- the last `run` printed devbin devbin's guides line
# naming <dir> (issue 0254), and every guide that line lists is a file there.
# Shared by machinepointer.bats and dispatch.bats.
assert_guides_at() {
  local listed g
  grep -qxF "are in $1/" <<<"$output" || fail "the guides line does not name $1/: $output"
  listed="$(sed -n 's/^The long-form guides (\(.*\))$/\1/p' <<<"$output")"
  [ -n "$listed" ] || fail "no guides were read out of: $output"
  # shellcheck disable=SC2086 # the list's words are the guides' names
  for g in ${listed//,/ }; do
    [ -f "$1/$g.md" ] || fail "the overview lists the guide $g, and $1/$g.md is not there"
  done
}

# --- installs and their consumers ---------------------------------------------
#
# Shared by localinstall.bats and upgradeoffer.bats (issue 0079): a consumer that
# is REALLY behind or ahead of an install needs a real publish history, and two
# copies of how to build one would drift.

# manifest_of <proj> -- the path of <proj>'s manifest.
# header_of <proj> <key> -- one header value of <proj>'s manifest.
manifest_of() { printf '%s/bin/.devbin/manifest.sha256\n' "$1"; }

# require_case_folding <dir> -- skip, naming what was not checked, unless the
# filesystem under <dir> folds case: a file created as CaseProbe is then found
# as caseprobe. macOS's APFS folds case as it is formatted; CI's Ubuntu leg
# does not, and there Foo and foo are two files (issue 0140).
require_case_folding() {
  local probe="$1/CaseProbe.$$"
  : >"$probe"
  if [ -e "$1/caseprobe.$$" ]; then
    rm -f "$probe"
    return 0
  fi
  rm -f "$probe"
  skip "this disk is case-sensitive, where Foo and foo are two files: the case-only rename was NOT checked"
}

# require_case_sensitive <dir> -- the other half: skip, naming what was not
# checked, when the filesystem under <dir> folds case.
require_case_sensitive() {
  local probe="$1/CaseProbe.$$"
  : >"$probe"
  if [ ! -e "$1/caseprobe.$$" ]; then
    rm -f "$probe"
    return 0
  fi
  rm -f "$probe"
  skip "this disk folds case, where Foo and foo cannot be two files: retiring the old spelling beside the new was NOT checked"
}

# require_folded_local_bin <what> -- skip, naming <what> as not checked, unless
# the disk folds case, so that ~/.LOCAL/bin is ~/.local/bin: the PATH entry
# naming the link's directory in another case (issue 0247), shared by use.bats
# and doctor.bats. Called without run or a command substitution, so the skip
# ends the arm.
require_folded_local_bin() {
  mkdir -p "$HOME/.local/bin" || fail "the fixture's ~/.local/bin failed"
  [ -d "$HOME/.LOCAL/bin" ] ||
    skip "this disk does not fold case, so ~/.LOCAL/bin is not ~/.local/bin: $1 was NOT checked"
}

# require_folded_brew_prefix <what> -- skip, naming <what> as not checked,
# unless the disk folds case, so that HOMEBREW_PREFIX with its last part in
# capitals is HOMEBREW_PREFIX; else set FOLDED_PREFIX to that spelling, for a
# PATH entry naming Homebrew's bin in another case (issue 0284), shared by
# use.bats and helpers.bats. Called without run or a command substitution, so
# the skip ends the arm and the variable reaches it.
require_folded_brew_prefix() {
  local last="${HOMEBREW_PREFIX##*/}"
  FOLDED_PREFIX="${HOMEBREW_PREFIX%/*}/${last^^}"
  [ "$FOLDED_PREFIX" != "$HOMEBREW_PREFIX" ] ||
    fail "HOMEBREW_PREFIX's last part, $last, has no letter to fold"
  mkdir -p "$HOMEBREW_PREFIX" || fail "the fixture's HOMEBREW_PREFIX failed"
  [ -d "$FOLDED_PREFIX" ] ||
    skip "this disk does not fold case, so $FOLDED_PREFIX is not HOMEBREW_PREFIX: $1 was NOT checked"
}

# rename_case_in_source <src> <dir> <from> <to> <content> -- rename a shipped
# file in a dev source by case alone, with new content, and commit it.
rename_case_in_source() {
  git -C "$1" mv "lib/$2/$3" "lib/$2/$4" >/dev/null 2>&1 || return 1
  printf '%s\n' "$5" >"$1/lib/$2/$4"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "rename $3 to $4" >/dev/null 2>&1
}

# ship_in_source <src> <dir> <name> <content> -- add a file to a dev source's
# lib/ and commit it.
ship_in_source() {
  mkdir -p "$1/lib/$2"
  printf '%s\n' "$4" >"$1/lib/$2/$3"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "ship $3" >/dev/null 2>&1
}
header_of() { sed -n "s/^# $2: //p" "$(manifest_of "$1")"; }

# commit_seam <src> <msg> -- a commit that moves a vendored byte.
commit_seam() {
  printf '\n# %s\n' "$2" >>"$1/lib/helpers"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$2" >/dev/null 2>&1
}

# consumer_of_install <src> -- a project vendored from $PREFIX, which the calling
# file's setup sets, so it records the install's commit and names an install as
# the kind of its source, which this machine places at $PREFIX.
#
# IT CHECKS WHAT IT BUILT. Without the source check every arm using it could pass
# against a consumer still pointed at the CHECKOUT, where git answers the
# direction directly and the install's table is never read -- measured:
# deleting the upgrade line left arms using it green. Since
# issue 0153 the manifest records the kind and the machine records the place,
# so both halves are checked: the word, and where the machine pointer takes it.
consumer_of_install() {
  local consumer_root="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$consumer_root"
  devbin_run "$1" install --into "$consumer_root" --name demo >/dev/null 2>&1 || return 1
  devbin_run "$consumer_root" upgrade --from "$PREFIX" >/dev/null 2>&1 || return 1
  [ "$(header_of "$consumer_root" source)" = install ] || return 1
  # The switch names the install, as `devbin use opt` makes it the machine's
  # (issue 0213): the link is the one record a bare upgrade reads.
  devbin_run "$1" use opt >/dev/null 2>&1 || return 1
  # shellcheck source=lib/helpers
  [ "$( . "$DEVBIN_LIB_DIR/helpers" && manifest_source "$consumer_root")" = "$PREFIX" ] || return 1
  printf '%s\n' "$consumer_root"
}

# set_recorded_commit <proj> <value> -- rewrite a manifest's source_commit line.
# sed to a temporary and back, because `sed -i` differs between BSD and GNU and
# CI runs both.
set_recorded_commit() {
  local m tmp
  m="$(manifest_of "$1")"
  tmp="$(mktemp "$m.XXXXXX")"
  sed -e "s|^# source_commit: .*|# source_commit: $2|" "$m" >"$tmp" && mv "$tmp" "$m"
}

# devbin_run_under <proj> <interpreter> [args...] -- as devbin_run, but hand the
# dispatcher to a NAMED interpreter rather than executing it.
#
# A SEPARATE CONCERN, not a second way to do the same thing. The arms that need
# it are not about ordinary invocation: the bash >= 5 floor is only observable by
# running under a bash BELOW it, and doctor's "not executable" arm has to reach a
# dispatcher whose executable bit it just removed -- a state install can really
# produce, and one `./bin/devbin` cannot reach by definition.
devbin_run_under() {
  local proj="$1" interp="$2"
  shift 2
  ( cd "$proj" && "$interp" ./bin/devbin "$@" )
}

# gate_spans -- print every run_gate call in the runtime (lib/ and bin/), one
# per line, as `<file>:<first line>` TAB `<its flags>` TAB `<its argv>`: the
# call's text before its bare `--`, and the text after it TO THE CALL'S LAST
# LINE. A call that ends with no bare `--` is printed as `UNTERMINATED` TAB
# `<file>:<first line>` instead, so it is a finding rather than a call the scan
# silently lost. Comment lines are skipped.
#
# A CALL ENDS AT ITS LAST LINE, the first without a trailing backslash, and one
# that gets there with no bare `--` is UNTERMINATED at once. That was once
# only noticed at the end of the FILE, so an unterminated call with a
# second call below it ran on into the second, closed at the second's `--`, and
# printed the pair as one span at the first's line -- the second call was never
# read on its own, and nothing said so.
#
# THE ARGV IS READ TO THE END OF THE CALL, NOT TO THE END OF THE `--` LINE, and
# it is a field of its own. The span once stopped at the `--` line,
# so `-- "$fn" ${ARGS...} \` with `"${@}"` on the next line forwarded a raw argv
# no arm could see (0087). And the flags are a field of their own
# so that a property of the flags -- 0085's --source -- cannot be satisfied by a
# TOOL argument that happens to be spelled `--source`.
#
# ONE READER FOR EVERY ARM THAT HOLDS A PROPERTY OF THE GATE OPENERS (0085's
# --source, 0087's argv split), because a property is only as complete as the
# calls it is checked over. It is here because two copies had already diverged
# from the thing they were reading: both ended a span at the first ` -- ` on a
# line, and `lib/gatecmd`'s builtin opener carries one INSIDE its --source
# string ("devbin's own builtin $fn -- a function ..."), so its span stopped a
# line early and never contained the argv an arm was there to inspect. The
# terminator is looked for with quoted text MASKED, same length, so the split
# lands at the right column of the original line.
gate_spans() {
  # shellcheck disable=SC2016 # an awk program: its $ is awk's, never the shell's
  (cd "$DEVBIN_HOME" && find lib bin -type f ! -name '*.md' ! -name '*.yaml' |
    LC_ALL=C sort | xargs awk '
      # mask(s) -- s with every character inside quotes, and every escaped
      # character, replaced by x, so a terminator is found only outside them.
      function mask(s,   out, i, c, q, esc) {
        out = ""; q = ""; esc = 0
        for (i = 1; i <= length(s); i++) {
          c = substr(s, i, 1)
          if (esc) { out = out "x"; esc = 0; continue }
          if (c == "\\" && q != "\047") { esc = 1; out = out "x"; continue }
          if (q == "") {
            if (c == "\"" || c == "\047") { q = c; out = out "x"; continue }
            out = out c
          } else {
            if (c == q) q = ""
            out = out "x"
          }
        }
        return out
      }
      function finish() {
        if (!inside) return
        if (seen) printf "%s:%d\t%s\t%s\n", file, start, flags, argv
        else printf "UNTERMINATED\t%s:%d\n", file, start
        inside = 0
      }
      FNR == 1 { finish(); file = FILENAME }
      /^[[:space:]]*#/ { next }
      /run_gate / && !inside { inside = 1; seen = 0; flags = ""; argv = ""; start = FNR }
      inside {
        line = $0
        cont = (line ~ /\\[[:space:]]*$/)
        if (cont) sub(/\\[[:space:]]*$/, "", line)
        if (seen) {
          argv = argv " " line
        } else {
          m = mask(line)
          if (match(m, /(^|[[:space:]])--([[:space:]]|$)/)) {
            at = RSTART + (substr(m, RSTART, 1) == "-" ? 0 : 1)
            flags = flags " " substr(line, 1, at - 1)
            argv = substr(line, at + 2)
            seen = 1
          } else {
            flags = flags " " line
          }
        }
        if (!cont) finish()
      }
      END { finish() }
    ')
}
