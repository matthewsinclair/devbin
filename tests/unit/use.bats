#!/usr/bin/env bats
# use.bats - devbin's switch among dev, opt and brew (docs/dev-opt-brew.md, T2
# to T5 and T9; issues 0213 and 0235).
#
# The link $HOME/.local/bin/devbin is the one record of which tree this machine
# runs: `use dev` and `use opt` point it, `use brew` removes it, and no link
# means brew. Every project reads the same switch for its next upgrade, by the
# link's own path. devbin_isolate_machine gives every arm a HOME, an
# XDG_DATA_HOME and a HOMEBREW_PREFIX of its own, so no arm reads or writes the
# runner's link.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a process started without the login PATH running Homebrew's devbin while
#     the link names another tree, which the contract puts outside the switch;
#   - T10's proof on real machines and in other projects' checkouts, which is
#     run by hand and recorded in the issue.

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  PREFIX="$DEVBIN_TEST_TMPDIR/opt/devbin"
  # Homebrew's devbin by its opt path, through the opt link brew_keg makes.
  KEG="$HOMEBREW_PREFIX/opt/devbin/libexec"
  LINK="$HOME/.local/bin/devbin"
}
teardown() { devbin_teardown; }

# published <src> -- an opt install at PREFIX, published from <src>.
published() {
  devbin_run "$1" install >/dev/null 2>&1 || fail "the fixture's publish failed"
}

# refused <link before> -- the last `run` refused use brew, removing nothing:
# the link is there and still reads <link before>, checked first, so a run
# that removed it fails naming the removal; then the refusal names the link
# and the opt tree it serves, and leaves dev or opt open.
refused() {
  [ -L "$LINK" ] || fail "use brew removed the link"
  [ "$(readlink "$LINK")" = "$1" ] || fail "use brew moved the link from $1 to $(readlink "$LINK")"
  assert_failure
  assert_output_contains "use brew removes nothing: no Homebrew devbin would answer once the link is gone"
  assert_output_contains "the link $LINK stays, serving $(devbin_tree_line "$PREFIX")"
  assert_output_contains "or stay on dev or opt"
}

# The remedy for no Homebrew devbin is keyed by its cause (0250): with
# HOMEBREW_PREFIX unset or relative, export it as brew shellenv does, since
# devbin may be installed and only this process cannot see it; under an
# absolute prefix holding none, install devbin with Homebrew. dev and opt are
# the maintainer's (issue 0250), offered only from a dev or opt tree, and by
# the checkout's own bin/devbin.
EXPORT_FIX="export HOMEBREW_PREFIX in the profile this process reads, as brew shellenv exports it"
CHECKOUT_FIX="or run bin/devbin use dev or opt in your devbin checkout"

@test "with no link, a bare use gives exporting HOMEBREW_PREFIX as the remedy when it is unset or relative, never installing devbin, and installing it under an absolute prefix holding none (0250)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" use
  assert_failure
  assert_output_contains "Homebrew has no devbin here (no devbin at $KEG, under HOMEBREW_PREFIX)"
  assert_output_contains "  install devbin with Homebrew, $CHECKOUT_FIX"
  refute_output_contains "export HOMEBREW_PREFIX"
  unset HOMEBREW_PREFIX
  run devbin_run "$src" use
  assert_failure
  assert_output_contains "Homebrew has no devbin here (HOMEBREW_PREFIX is not set)"
  assert_output_contains "  $EXPORT_FIX, $CHECKOUT_FIX"
  refute_output_contains "install devbin"
  HOMEBREW_PREFIX=relative/brew run devbin_run "$src" use
  assert_failure
  assert_output_contains "Homebrew has no devbin here (HOMEBREW_PREFIX, 'relative/brew', is not an absolute path)"
  assert_output_contains "  $EXPORT_FIX, $CHECKOUT_FIX"
  refute_output_contains "install devbin"
}

@test "a bare use's remedy names the checkout's bin/devbin use dev or opt from a dev or an opt tree, and from a keg names neither (0250)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" 0.1.0
  # The keg is there, and no HOMEBREW_PREFIX finds it: a process without the
  # login profile.
  unset HOMEBREW_PREFIX
  run devbin_run "$src" use
  assert_failure
  assert_output_contains "  $EXPORT_FIX, $CHECKOUT_FIX"
  run bash -c 'cd "$1" && "$2" use </dev/null' _ "$DEVBIN_TEST_TMPDIR" "$PREFIX/bin/devbin"
  assert_failure
  assert_output_contains "  $EXPORT_FIX, $CHECKOUT_FIX"
  refute_output_contains "$PREFIX/bin/devbin use"
  run bash -c 'cd "$1" && "$2" use </dev/null' _ "$DEVBIN_TEST_TMPDIR" "$KEG/bin/devbin"
  assert_failure
  assert_output_contains "  $EXPORT_FIX"
  refute_output_contains "use dev"
  refute_output_contains "use opt"
  refute_output_contains "dev or opt"
}

@test "every remedy for no Homebrew devbin is brew_unplaced_fix's, and no shell site spells its own (0250)" {
  local hits rest
  local -a dirs=("$DEVBIN_HOME/lib")
  # Shell code alone: a page may describe the remedy in prose. shell-init's
  # line is another cause's (a dvb emitted with no install), and its own.
  # devbin's own project commands are read where the tree holds them; a tree
  # may carry none.
  [ ! -d "$DEVBIN_HOME/bin/.devbin/cmd" ] || dirs+=("$DEVBIN_HOME/bin/.devbin/cmd")
  # And the launcher itself, which says the first things a user reads.
  dirs+=("$DEVBIN_HOME/bin/devbin")
  hits="$(grep -rnF --exclude='*.md' --exclude='*.yaml' -e 'install devbin with Homebrew' -e 'export HOMEBREW_PREFIX' "${dirs[@]}")" || fail "no remedy is spelled anywhere, lib/helpers included"
  [[ "$hits" == *"/lib/helpers:"* ]] || fail "lib/helpers spells no remedy:
$hits"
  rest="$(grep -v -e '/lib/helpers:' -e 'emit dvb from that install' <<<"$hits" || true)"
  [ -z "$rest" ] || fail "a site spells its own remedy:
$rest"
}

@test "a bare use with no link and no Homebrew devbin says brew, names what is missing, and fails" {
  src="$(mkdevsrc)"
  run devbin_run "$src" use
  assert_failure
  assert_output_contains "no link, so brew, and Homebrew has no devbin here"
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "a bare use wrote the link"
}

@test "use opt points the link at the opt install and prints its tree line" {
  src="$(mkdevsrc)"
  published "$src"
  run devbin_run "$src" use opt
  assert_success
  physical_dir "$PREFIX" real
  [ "$(readlink "$LINK")" = "$real/bin/devbin" ] || fail "the link reads $(readlink "$LINK")"
  # The line names no path (0230): `command -v devbin` says where it lives.
  [[ "${lines[1]}" =~ ^\ \ devbin\ [^\ ]+\ \(opt,\ $(git -C "$src" rev-parse --short=12 HEAD)\)$ ]] ||
    fail "the tree line reads: ${lines[1]}"
}

@test "use dev points the link at the checkout, and devbin use opt then runs from it" {
  src="$(mkdevsrc)"
  published "$src"
  run devbin_run "$src" use dev
  assert_success
  physical_dir "$src" real
  [ "$(readlink "$LINK")" = "$real/bin/devbin" ] || fail "the link reads $(readlink "$LINK")"
  assert_output_contains "(dev, "
  run bash -c 'cd "$1" && "$2" use opt </dev/null' _ "$src" "$LINK"
  assert_success
  physical_dir "$PREFIX" real
  [ "$(readlink "$LINK")" = "$real/bin/devbin" ] || fail "use opt through the link left $(readlink "$LINK")"
}

@test "use dev and use opt are refused outside the checkout, naming the command to run" {
  src="$(mkdevsrc)"
  published "$src"
  run devbin_run "$PREFIX" use dev
  assert_failure
  assert_output_contains "devbin use dev runs in the devbin checkout"
  assert_output_contains "bin/devbin use dev"
  run devbin_run "$PREFIX" use opt
  assert_failure
  assert_output_contains "devbin use opt runs in the devbin checkout"
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "a refused use wrote the link"
}

@test "use opt with no opt install refuses, naming install" {
  src="$(mkdevsrc)"
  run devbin_run "$src" use opt
  assert_failure
  assert_output_contains "there is no opt install at $PREFIX"
  assert_output_contains "bin/devbin install"
}

@test "use brew removes a link into devbin's trees, from any tree, and reports the keg, once Homebrew's devbin would answer" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$KEG" use brew
  assert_success
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link"
  assert_output_contains "no link, so brew"
  assert_output_contains "(brew, "
}

# T5 (0235): use brew asks what would answer devbin on PATH once the link is
# gone, and removes nothing unless that is Homebrew's keg. An arm that needs
# nothing to answer hides every devbin on the runner's PATH (path_without): its
# Homebrew devbin, or a link in its own ~/.local/bin, would answer otherwise.

@test "use brew with no Homebrew devbin refuses, removing nothing, naming the link, the tree it serves, why and the remedy for that cause (0235, 0250)" {
  local export_fix="export HOMEBREW_PREFIX in the profile this process reads, as brew shellenv exports it"
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  # An absolute prefix holding no devbin: install it.
  run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "Homebrew has no devbin here (no devbin at $KEG, under HOMEBREW_PREFIX)"
  assert_output_contains "install devbin with Homebrew, then run bin/devbin use brew again"
  refute_output_contains "export HOMEBREW_PREFIX"
  # Unset, or relative: devbin may well be installed, and this process cannot
  # see it, so the remedy is the export, never an install (0250).
  unset HOMEBREW_PREFIX
  run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "Homebrew has no devbin here (HOMEBREW_PREFIX is not set)"
  assert_output_contains "$export_fix, then run bin/devbin use brew again"
  refute_output_contains "install devbin"
  HOMEBREW_PREFIX=relative/brew run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "Homebrew has no devbin here (HOMEBREW_PREFIX, 'relative/brew', is not an absolute path)"
  assert_output_contains "$export_fix, then run bin/devbin use brew again"
  refute_output_contains "install devbin"
}

@test "use brew with Homebrew's keg not linked refuses, removing nothing, naming brew link (0235)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "Homebrew's devbin at $KEG is not linked: no devbin in $HOMEBREW_PREFIX/bin leads into it"
  assert_output_contains "link it (brew link devbin)"
}

@test "use brew with Homebrew's bin off PATH refuses, removing nothing, naming the directory to put on PATH (0235)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$nodevbin" run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "Homebrew's devbin is linked at $HOMEBREW_PREFIX/bin/devbin, and $HOMEBREW_PREFIX/bin is not on PATH"
  assert_output_contains "put $HOMEBREW_PREFIX/bin on PATH, after $HOME/.local/bin"
}

@test "use brew with Homebrew's devbin not executable and its bin on PATH refuses, removing nothing, naming the file and reinstalling with Homebrew (0249)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  # bash's search, finding no executable devbin, prints this one and returns 0.
  chmod a-x "$KEG/bin/devbin" || fail "the fixture's chmod failed"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$src" use brew
  refused "$before"
  real_path "$KEG/bin/devbin" launcher
  assert_output_contains "Homebrew's devbin would not run: $launcher is not executable"
  assert_output_contains "reinstall devbin with Homebrew (brew reinstall devbin), then run"
}

@test "use brew with the keg's env script executable and the libexec launcher it runs not executable refuses, removing nothing, naming that launcher (0249)" {
  src="$(mkdevsrc)"
  published "$src"
  # The keg laid out as the formula lays it on macOS: its bin/devbin a script
  # of its own (write_env_script) that runs libexec's launcher, and Homebrew's
  # bin link to that script.
  brew_keg --from "$src" --script --linked 0.1.0
  keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  chmod a-x "$keg/libexec/bin/devbin" || fail "the fixture's chmod failed"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$src" use brew
  refused "$before"
  real_path "$keg/libexec/bin/devbin" launcher
  assert_output_contains "Homebrew's devbin would not run: $launcher is not executable"
  assert_output_contains "reinstall devbin with Homebrew (brew reinstall devbin), then run"
}

@test "use brew with Homebrew's bin link reaching the keg only through the link refuses, removing nothing, naming brew link --overwrite (0249)" {
  src="$(mkdevsrc)"
  # Homebrew's bin link made by hand to the link itself, which brew link never
  # makes.
  brew_keg --from "$src" --linked-to "$LINK" 0.1.0
  keg_linked_by_hand
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$src" use brew
  [ -L "$LINK" ] || fail "use brew removed the link, leaving Homebrew's bin link dangling"
  [ "$(readlink "$LINK")" = "$KEG/bin/devbin" ] || fail "use brew moved the link to $(readlink "$LINK")"
  assert_failure
  assert_output_contains "Homebrew's devbin is linked at $HOMEBREW_PREFIX/bin/devbin, and it reaches the keg only through the link $LINK, so it goes with it"
  assert_output_contains "point $HOMEBREW_PREFIX/bin/devbin at the keg itself (brew link --overwrite devbin), then run"
}

@test "use brew with another devbin first on PATH refuses, removing nothing, naming that copy to move aside (0235)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  mkdir -p "$DEVBIN_TEST_TMPDIR/other"
  ln -s "$PREFIX/bin/devbin" "$DEVBIN_TEST_TMPDIR/other/devbin"
  PATH="$HOME/.local/bin:$DEVBIN_TEST_TMPDIR/other:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  refused "$before"
  assert_output_contains "with $HOME/.local/bin left out, the first devbin on PATH would be $DEVBIN_TEST_TMPDIR/other/devbin, which is not Homebrew's devbin at $KEG"
  assert_output_contains "move $DEVBIN_TEST_TMPDIR/other/devbin aside"
}

@test "use brew leaves a relative PATH entry out, which answers from wherever a command is typed, so ./bin first still lets a linked keg answer (0235)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  # devbin_run runs from the checkout, whose ./bin/devbin a lookup through ./bin
  # would find first.
  PATH="./bin:$HOME/.local/bin:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link"
  assert_success
  assert_output_contains "(brew, "
}

@test "use brew reads PATH past an entry holding a newline, so a linked keg after it answers and the link goes (0248)" {
  # A shell reads PATH at its colons alone. The split stopped at the newline,
  # so Homebrew's bin after it read as off PATH, and use brew refused with
  # Homebrew's devbin answering.
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  mkdir -p "$DEVBIN_TEST_TMPDIR/odd"$'\n'"dir"
  PATH="$HOME/.local/bin:$DEVBIN_TEST_TMPDIR/odd"$'\n'"dir:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link: $output"
  assert_success
  assert_output_contains "(brew, "
}

# 0247: use brew's lookup is the one a shell makes once the link is gone, so it
# passes over a devbin linked through the link, which would dangle, and reads
# an entry naming ~/.local/bin in another case, on a disk that folds case, as
# the link's own directory. An arm about case makes that entry ~/.LOCAL/bin,
# and skips where the disk keeps the two spellings apart.

# keg_linked_by_hand -- the link made by hand into the keg at KEG, which devbin
# never makes, with Homebrew's bin link into the keg beside it. Written by
# switch_to, the one writer of the switch's link, so no line here builds into
# the keg (0270).
keg_linked_by_hand() {
  switch_to "$KEG" ||
    fail "the fixture's link into the keg failed"
}

# kept_into_keg -- the last `run` refused use brew, removing nothing, and the
# link made by hand into the keg is there, still reading what it read; checked
# first, so a run that removed it fails naming the removal.
kept_into_keg() {
  [ -L "$LINK" ] || fail "use brew removed the link, leaving no devbin on PATH"
  [ "$(readlink "$LINK")" = "$KEG/bin/devbin" ] || fail "use brew moved the link to $(readlink "$LINK")"
  assert_failure
  assert_output_contains "use brew removes nothing: no Homebrew devbin would answer once the link is gone"
  assert_output_contains "Homebrew's devbin is linked at $HOMEBREW_PREFIX/bin/devbin, and $HOMEBREW_PREFIX/bin is not on PATH"
}

@test "use brew passes over a devbin linked through the link, which would dangle once it is gone, so Homebrew's devbin after it answers (0247)" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  mkdir -p "$HOME/bin" && ln -s ../.local/bin/devbin "$HOME/bin/devbin" || fail "the fixture's ~/bin/devbin failed"
  PATH="$HOME/.local/bin:$HOME/bin:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  refute_output_contains "move $HOME/bin/devbin aside"
  assert_success
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link"
  assert_output_contains "(brew, "
}

@test "use brew reads a PATH entry naming ~/.local/bin in another case as the link's own directory, where the disk folds case (0247)" {
  require_folded_local_bin "use brew past ~/.LOCAL/bin"
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  folded="$HOME/.LOCAL/bin"
  PATH="$HOME/.local/bin:$folded:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  refute_output_contains "move $folded/devbin aside"
  assert_success
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link"
  assert_output_contains "(brew, "
}

@test "use brew reads Homebrew's bin typed in another case as the keg's own, where the disk folds case, so the link goes and brew answers (0284)" {
  require_folded_brew_prefix "use brew with Homebrew's bin in another case"
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" --script --linked 0.1.0
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  PATH="$HOME/.local/bin:$FOLDED_PREFIX/bin:$PATH" run devbin_run "$src" use brew
  refute_output_contains "move $FOLDED_PREFIX/bin/devbin aside"
  assert_success
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "use brew left the link"
  assert_output_contains "(brew, "
}

@test "use brew with a link made by hand into the keg and Homebrew's bin off PATH refuses when a devbin linked through the link would answer, leaving the link (0247)" {
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  keg_linked_by_hand
  mkdir -p "$HOME/bin" && ln -s ../.local/bin/devbin "$HOME/bin/devbin" || fail "the fixture's ~/bin/devbin failed"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$HOME/bin:$nodevbin" run devbin_run "$src" use brew
  kept_into_keg
}

@test "use brew with a link made by hand into the keg and Homebrew's bin off PATH refuses when ~/.local/bin is on PATH in another case, leaving the link, where the disk folds case (0247)" {
  require_folded_local_bin "use brew refusing past ~/.LOCAL/bin"
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  keg_linked_by_hand
  folded="$HOME/.LOCAL/bin"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  PATH="$HOME/.local/bin:$folded:$nodevbin" run devbin_run "$src" use brew
  kept_into_keg
}

@test "with the link into the keg through Homebrew's opt link, doctor's switch row and a bare use name the opt path, never the keg's Cellar path (0287)" {
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  keg_linked_by_hand
  PATH="$HOME/.local/bin:$PATH" run devbin_run "$src" doctor
  assert_output_contains "switch: the link names $KEG"
  refute_output_contains "Cellar/devbin"
  PATH="$HOME/.local/bin:$PATH" run devbin_run "$src" use
  assert_success
  assert_output_contains "use: the link $LINK names"
  refute_output_contains "Cellar/devbin"
}

# T5 (0273): with no link left, brew is reported only when the first devbin on
# PATH is the keg's, so a bare use and doctor's switch row ask what answers on
# PATH, as use brew does before it removes a link, and name the same causes.

@test "with no link and Homebrew's keg there, a bare use and doctor's switch row fail naming another devbin first on PATH, and report brew with the keg's first (0273)" {
  local stray="$DEVBIN_TEST_TMPDIR/other/devbin" proj
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  mkdir -p "${stray%/*}"
  printf '#!/bin/sh\nexit 0\n' >"$stray" && chmod +x "$stray" || fail "the fixture's stray devbin failed"
  PATH="${stray%/*}:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$src" use
  assert_failure
  assert_output_contains "no link means brew, but the first devbin on PATH is $stray, which is not Homebrew's devbin at $KEG -- move $stray aside"
  PATH="${stray%/*}:$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$proj" doctor
  assert_output_contains "FAIL  switch: no link means brew, but the first devbin on PATH is $stray"
  refute_output_contains "ok    switch: no link, so brew"
  PATH="$HOMEBREW_PREFIX/bin:${stray%/*}:$PATH" run devbin_run "$src" use
  assert_success
  assert_output_contains "use: no link, so brew"
  assert_output_contains "(brew, "
  PATH="$HOMEBREW_PREFIX/bin:${stray%/*}:$PATH" run devbin_run "$proj" doctor
  assert_output_contains "ok    switch: no link, so brew"
  refute_output_contains "FAIL  switch"
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "a bare use or doctor wrote the link"
}

@test "with no link and Homebrew's keg there, a bare use and doctor's switch row say no devbin is on PATH when none is, naming the cause (0273)" {
  local nodevbin proj offpath unlinked
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  offpath="no link means brew, but no devbin is on PATH (Homebrew's devbin is linked at $HOMEBREW_PREFIX/bin/devbin, and $HOMEBREW_PREFIX/bin is not on PATH) -- put $HOMEBREW_PREFIX/bin on PATH"
  unlinked="no link means brew, but no devbin is on PATH (Homebrew's devbin at $KEG is not linked: no devbin in $HOMEBREW_PREFIX/bin leads into it) -- link it (brew link devbin)"
  PATH="$nodevbin" run devbin_run "$src" use
  assert_failure
  assert_output_contains "$offpath"
  PATH="$nodevbin" run devbin_run "$proj" doctor
  assert_output_contains "FAIL  switch: $offpath"$'\n'
  rm "$HOMEBREW_PREFIX/bin/devbin"
  PATH="$nodevbin" run devbin_run "$src" use
  assert_failure
  assert_output_contains "$unlinked"
  PATH="$nodevbin" run devbin_run "$proj" doctor
  assert_output_contains "FAIL  switch: $unlinked"$'\n'
}

@test "with no link and Homebrew's devbin not executable, a bare use and doctor's switch row fail naming the file and reinstalling with Homebrew (0273)" {
  local nodevbin proj launcher noexec
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  nodevbin="$(path_without devbin)" || fail "path_without could not hide devbin, as its line above says"
  # bash's search, finding no executable devbin, prints this one and returns 0
  # (0249), so the keg's launcher would answer and fail with Permission denied.
  chmod a-x "$KEG/bin/devbin" || fail "the fixture's chmod failed"
  real_path "$KEG/bin/devbin" launcher
  noexec="no link means brew, but Homebrew's devbin would not run: $launcher is not executable -- reinstall devbin with Homebrew (brew reinstall devbin)"
  PATH="$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$src" use
  assert_failure
  assert_output_contains "$noexec"
  PATH="$HOMEBREW_PREFIX/bin:$nodevbin" run devbin_run "$proj" doctor
  assert_output_contains "FAIL  switch: $noexec"$'\n'
  refute_output_contains "ok    switch: no link, so brew"
}

@test "use brew leaves a link it did not make and a file where the link belongs, naming each" {
  src="$(mkdevsrc)"
  mkdir -p "${LINK%/*}"
  ln -s "$DEVBIN_TEST_TMPDIR/elsewhere/tool" "$LINK"
  run devbin_run "$src" use brew
  assert_failure
  [ -L "$LINK" ] || fail "use brew removed a link into no devbin tree"
  rm "$LINK"
  printf 'mine\n' >"$LINK"
  run devbin_run "$src" use brew
  assert_failure
  assert_output_contains "is not a link"
  [ "$(cat "$LINK")" = mine ] || fail "use brew touched a file it did not write"
}

@test "the switch reads the link by its own path, through a chain of links, with no ~/.local/bin on PATH" {
  src="$(mkdevsrc)"
  published "$src"
  mkdir -p "${LINK%/*}" "$DEVBIN_TEST_TMPDIR/hop"
  ln -s "$PREFIX/bin/devbin" "$DEVBIN_TEST_TMPDIR/hop/devbin"
  ln -s "$DEVBIN_TEST_TMPDIR/hop/devbin" "$LINK"
  run env PATH="${BASH%/*}:/usr/bin:/bin" "$BASH" -c '. "$1/helpers" && . "$1/install" && machine_install_root' _ "$DEVBIN_LIB_DIR"
  assert_success
  physical_dir "$PREFIX" real
  [ "$output" = "$real" ] || fail "the switch read: $output"
}

@test "a link that leads nowhere is bad, said as such, never read as no link" {
  mkdir -p "${LINK%/*}"
  ln -s "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$LINK"
  run machine_named_state
  [[ "$output" == "bad the link $LINK leads to no file"* ]] || fail "the state read: $output"
  [ "$(machine_install_chooser)" = link ] || fail "a dangling link was passed over"
}

@test "a link that leads nowhere is said with its remedy, removing it, and only from a dev or an opt tree with the checkout's use dev or opt, never from a keg (0250)" {
  local said="leads to no file it can follow -- remove it, so no link means brew" l ends=""
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" 0.1.0
  mkdir -p "${LINK%/*}"
  ln -s "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$LINK"
  run bash -c 'cd "$1" && "$2" use </dev/null' _ "$DEVBIN_TEST_TMPDIR" "$KEG/bin/devbin"
  assert_failure
  # Nothing follows the clause from a keg: a line ends with it, whether or not
  # that line is the last, which bats keeps without its newline.
  for l in "${lines[@]}"; do
    [[ "$l" != *"$said" ]] || ends=yes
  done
  [ -n "$ends" ] || fail "no line ends with '$said', so something follows it: $output"
  refute_output_contains "dev or opt"
  refute_output_contains "use dev"
  run devbin_run "$src" use
  assert_failure
  assert_output_contains "$said, $CHECKOUT_FIX"
  run bash -c 'cd "$1" && "$2" use </dev/null' _ "$DEVBIN_TEST_TMPDIR" "$PREFIX/bin/devbin"
  assert_failure
  assert_output_contains "$said, $CHECKOUT_FIX"
}

@test "DEVBIN_INSTALL_PREFIX outranks the link, the link outranks brew, and no link means brew" {
  src="$(mkdevsrc)"
  published "$src"
  brew_keg --from "$src" 0.1.0
  [ "$(machine_install_chooser)" = brew ] || fail "with no link, the chooser said $(machine_install_chooser)"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  [ "$(machine_install_chooser)" = link ] || fail "the link did not outrank brew"
  DEVBIN_INSTALL_PREFIX="$DEVBIN_TEST_TMPDIR/elsewhere"
  export DEVBIN_INSTALL_PREFIX
  [ "$(machine_install_chooser)" = prefix ] || fail "the override did not outrank the link"
}

@test "a machine pointer left from before the link is never read, and doctor names it as retired" {
  src="$(mkdevsrc)"
  brew_keg --from "$src" 0.1.0
  published "$src"
  mkdir -p "$XDG_DATA_HOME/devbin"
  printf '%s\n' "$PREFIX" >"$XDG_DATA_HOME/devbin/home"
  [ "$(machine_install_chooser)" = brew ] || fail "the retired pointer was read: $(machine_install_chooser)"
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  run devbin_run "$proj" doctor
  assert_output_contains "is the retired machine pointer, and nothing reads it"
  # From a project, any user's, the step is use brew alone (0250).
  assert_output_contains "the link devbin use writes is the record now: run devbin use brew, then remove $XDG_DATA_HOME/devbin/home"
  refute_output_contains "use opt"
}

@test "the shadow check fails a link another devbin on PATH shadows, and passes one reached through a linked directory" {
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  mkdir -p "$DEVBIN_TEST_TMPDIR/first"
  ln -s "$PREFIX/bin/devbin" "$DEVBIN_TEST_TMPDIR/first/devbin"
  run env PATH="$DEVBIN_TEST_TMPDIR/first:$HOME/.local/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use </dev/null' _ "$src"
  assert_failure
  assert_output_contains "is shadowed: the first devbin on PATH is $DEVBIN_TEST_TMPDIR/first/devbin"
  ln -s "$HOME/.local/bin" "$HOME/bin"
  run env PATH="$HOME/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use </dev/null' _ "$src"
  assert_success
}

@test "a bare use says nothing of a shadow when the first devbin on PATH is a link through the link, which runs the link's tree (0285)" {
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  mkdir -p "$HOME/bin" && ln -s ../.local/bin/devbin "$HOME/bin/devbin" || fail "the fixture's ~/bin/devbin failed"
  run env PATH="$HOME/bin:$HOME/.local/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use </dev/null' _ "$src"
  refute_output_contains "is shadowed"
  assert_success
}

@test "a bare use names no relative PATH entry as a shadow, which answers only from where a command is typed (0285)" {
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  # From the checkout, bin/devbin is its own launcher, a devbin that is not the
  # link's opt install, and the relative entry finds it first.
  run env PATH="bin:$HOME/.local/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use </dev/null' _ "$src"
  refute_output_contains "is shadowed"
  assert_success
}

@test "use dev and use opt under a PATH that shadows the link exit 1 with the link pointed, saying it was pointed and what shadows it (0275)" {
  local first="$DEVBIN_TEST_TMPDIR/first" word want
  src="$(mkdevsrc)"
  published "$src"
  mkdir -p "$first" && printf '#!/usr/bin/env bash\n' >"$first/devbin" && chmod +x "$first/devbin" ||
    fail "the fixture's shadowing devbin failed"
  for word in dev opt; do
    if [ "$word" = dev ]; then want="$src/bin/devbin"; else want="$PREFIX/bin/devbin"; fi
    run env PATH="$first:$HOME/.local/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use "$2" </dev/null' _ "$src" "$word"
    assert_failure
    [ "$status" -eq 1 ] || fail "use $word exited $status, not 1"
    [ "$(readlink "$LINK")" = "$want" ] || fail "use $word left the link at $(readlink "$LINK"), not $want"
    assert_output_contains "use $word pointed the link $LINK, and it stays pointed"
    assert_output_contains "is shadowed: the first devbin on PATH is $first/devbin"
  done
}

@test "a bare use says nothing of a shadow when ~/.local/bin is first on PATH in another case, where the disk folds case (0247)" {
  require_folded_local_bin "the shadow check past ~/.LOCAL/bin"
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  run env PATH="$HOME/.LOCAL/bin:$PATH" bash -c 'cd "$1" && ./bin/devbin use </dev/null' _ "$src"
  refute_output_contains "is shadowed"
  assert_success
}

@test "a project's upgrade reads the switch: from the checkout under use dev, recording checkout, and from opt under use opt" {
  src="$(mkdevsrc)"
  published "$src"
  proj="$(create_test_project demo)"
  devbin_run "$PREFIX" install --into "$proj" >/dev/null 2>&1 || fail "the fixture's vendor failed"
  devbin_run "$src" use dev >/dev/null || fail "the fixture's use dev failed"
  run devbin_run "$proj" upgrade
  assert_success
  [ "$(header_of "$proj" source)" = checkout ] || fail "under use dev the manifest records $(header_of "$proj" source)"
  devbin_run "$src" use opt >/dev/null || fail "the fixture's use opt failed"
  run devbin_run "$proj" upgrade
  assert_success
  [ "$(header_of "$proj" source)" = install ] || fail "under use opt the manifest records $(header_of "$proj" source)"
}

@test "nothing but use writes the link: not a publish, a replace, a vendor or an upgrade" {
  src="$(mkdevsrc)"
  published "$src"
  run devbin_run "$src" install --force
  assert_success
  proj="$(create_test_project demo)"
  devbin_run "$PREFIX" install --into "$proj" >/dev/null 2>&1 || fail "the fixture's vendor failed"
  DEVBIN_INSTALL_PREFIX="$PREFIX" devbin_run "$proj" upgrade >/dev/null 2>&1 || fail "the fixture's upgrade failed"
  [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || fail "something other than use wrote the link"
}

# aged <root> -- <root>'s install manifest in the form written before the
# contract: no `tool:` or `version:` line, and `managed_by` only on a keg.
aged() {
  local m
  m="$(manifest_of "$1")"
  awk '!/^# (tool|version): / && !/^# managed_by: devbin$/' "$m" >"$m.aged" && mv "$m.aged" "$m" ||
    fail "the fixture's aging failed"
}

@test "an old-form keg is still brew and a doctor note; an old-form opt install fails doctor, naming install --force" {
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  aged "$KEG"
  [ "$(devbin_tree "$KEG")" = brew ] || fail "an old-form keg reads $(devbin_tree "$KEG")"
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  # With no link, the switch row asks that the keg's devbin answers on PATH
  # (0273), so Homebrew's bin, which brew_keg linked, comes first.
  PATH="$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$proj" doctor
  assert_output_contains "note  switch: the install at $KEG has the manifest form written before"
  assert_output_contains "brew upgrade devbin"
  refute_output_contains "FAIL  switch"
  published "$src"
  aged "$PREFIX"
  [ "$(devbin_tree "$PREFIX")" = unknown ] || fail "an old-form opt install reads $(devbin_tree "$PREFIX")"
  mkdir -p "${LINK%/*}"
  ln -s "$PREFIX/bin/devbin" "$LINK"
  run devbin_run "$proj" doctor
  assert_output_contains "FAIL  switch: the install at"
  assert_output_contains "install --force"
}

@test "a keg with no manifest under Homebrew's opt link is still brew and an old manifest; an opt prefix with none is unknown" {
  src="$(mkdevsrc)"
  brew_keg --from "$src" 0.1.0
  rm "$(manifest_of "$KEG")"
  [ "$(devbin_tree "$KEG")" = brew ] || fail "a keg with no manifest reads $(devbin_tree "$KEG")"
  devbin_install_old "$KEG" || fail "a keg with no manifest is not named an old manifest"
  published "$src"
  rm "$(manifest_of "$PREFIX")"
  [ "$(devbin_tree "$PREFIX")" = unknown ] || fail "an opt prefix with no manifest reads $(devbin_tree "$PREFIX")"
  run devbin_run "$src" use opt
  assert_failure
}

@test "a link that cannot be written fails use by name, and a link that names a directory is replaced, never written through" {
  src="$(mkdevsrc)"
  published "$src"
  mkdir -p "${LINK%/*}"
  chmod 500 "${LINK%/*}"
  if : 2>/dev/null >"${LINK%/*}/probe"; then
    chmod 700 "${LINK%/*}"
    skip "running with permissions that write a mode-500 directory"
  fi
  run devbin_run "$src" use opt
  chmod 700 "${LINK%/*}"
  assert_failure
  assert_output_contains "cannot write the link $LINK"
  mkdir -p "$DEVBIN_TEST_TMPDIR/somedir"
  ln -s "$DEVBIN_TEST_TMPDIR/somedir" "$LINK"
  run devbin_run "$src" use opt
  assert_success
  physical_dir "$PREFIX" real
  [ "$(readlink "$LINK")" = "$real/bin/devbin" ] || fail "the link reads $(readlink "$LINK")"
  [ -z "$(ls -A "$DEVBIN_TEST_TMPDIR/somedir")" ] || fail "use wrote through the link into the directory it named"
}

@test "use opt resolves a relative install.prefix where it is, never where CDPATH finds the same name" {
  src="$(mkdevsrc)"
  # A relative prefix, read from the checkout's root, committed so the publish
  # sees a clean tree.
  printf 'project:\n  name: fixturesrc\ndevbin_version: "^0.1.0"\ninstall:\n  prefix: rel/devbin\n' >"$src/bin/.devbin/config.yaml"
  printf 'rel/\n' >"$src/.gitignore"
  git -C "$src" add -A && git -C "$src" -c user.email=t@t -c user.name=t commit -qm rel ||
    fail "the fixture's commit failed"
  devbin_run "$src" install >/dev/null 2>&1 || fail "the fixture's publish failed"
  mkdir -p "$DEVBIN_TEST_TMPDIR/decoy/rel/devbin"
  run env CDPATH="$DEVBIN_TEST_TMPDIR/decoy" bash -c 'cd "$1" && ./bin/devbin use opt </dev/null' _ "$src"
  assert_success
  physical_dir "$src/rel/devbin" real
  [ "$(readlink "$LINK")" = "$real/bin/devbin" ] || fail "the link reads $(readlink "$LINK")"
}

# consumer <src> -- a project with devbin vendored from <src>, as install --into
# seeds one, in a git repository with the vendored tree committed, as every
# real project is. THE .git IS THE POINT: without one devbin_tree answers
# unknown on the missing .git alone, so the arms would stay green even if the
# vendored manifest stopped telling a project from devbin's checkout.
consumer() {
  CONSUMER="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$CONSUMER"
  git -C "$CONSUMER" init -q || fail "the fixture's git init failed"
  devbin_run "$1" install --into "$CONSUMER" --name demo >/dev/null 2>&1 ||
    fail "the fixture's consumer failed"
  git -C "$CONSUMER" add -A && git -C "$CONSUMER" -c user.email=t@t -c user.name=t commit -q -m fixture ||
    fail "the fixture's commit failed"
  [ -d "$CONSUMER/.git" ] && is_devbin_source "$CONSUMER" ||
    fail "the consumer is not a git repository holding bin/devbin and lib"
}

@test "a project's bin/devbin refuses use with exit 6, naming devbin use, and leaves the link as it was" {
  src="$(mkdevsrc)"
  published "$src"
  devbin_run "$src" use opt >/dev/null 2>&1 || fail "the fixture's use opt failed"
  before="$(readlink "$LINK")"
  consumer "$src"
  for word in "" dev opt brew; do
    run devbin_run "$CONSUMER" use ${word:+"$word"}
    [ "$status" -eq 6 ] || fail "use $word in a project exited $status: $output"
    assert_output_contains "devbin use chooses which devbin this machine runs, so a project's bin/devbin does not offer it"
    assert_output_contains "run devbin use"
  done
  [ "$(readlink "$LINK")" = "$before" ] || fail "a refused use moved the link to $(readlink "$LINK")"
}

@test "a project's help leaves use out, --why included, and help use says why; the checkout's help lists it" {
  src="$(mkdevsrc)"
  published "$src"
  consumer "$src"
  run devbin_run "$CONSUMER" help
  assert_success
  refute_output_contains "Choose which devbin this machine runs"
  run devbin_run "$CONSUMER" help --why
  assert_success
  refute_output_contains "devbin use chooses which devbin this machine runs"
  run devbin_run "$CONSUMER" help use
  assert_failure
  assert_output_contains "'bin/devbin use' is not available here: devbin use chooses which devbin this machine runs, so a project's bin/devbin does not offer it"
  run devbin_run "$src" help
  assert_success
  assert_output_contains "Choose which devbin this machine runs"
}

# versioned <src> <X.Y.Z> -- <src>'s VERSION, committed, so its trees carry it.
versioned() {
  printf '%s\n' "$2" >"$1/VERSION"
  git -C "$1" add VERSION && git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "v$2" ||
    fail "the fixture's VERSION commit failed"
}

@test "doctor notes a switch left on dev or opt once brew is at its version, and says nothing on brew (0228)" {
  src="$(mkdevsrc)"
  versioned "$src" 0.4.0
  published "$src"
  brew_keg --from "$src" --linked 0.1.0
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  switch_to "$src"
  run devbin_run "$proj" doctor
  assert_output_contains "note  switch: on dev, and Homebrew's devbin is 0.4.0, at or past dev's 0.4.0 -- the switch rests at brew"
  assert_output_contains "once the work on dev is released: brew upgrade devbin, then devbin use brew"
  refute_output_contains "FAIL  switch"
  switch_to "$PREFIX"
  run devbin_run "$proj" doctor
  assert_output_contains "note  switch: on opt, and Homebrew's devbin is 0.4.0, at or past opt's 0.4.0 -- the switch rests at brew"
  refute_output_contains "FAIL  switch"
  switch_to "$KEG"
  run devbin_run "$proj" doctor
  assert_output_contains "switch: the link names"
  refute_output_contains "the switch rests at brew"
  rm "$LINK"
  # With no link, the switch row asks that the keg's devbin answers on PATH
  # (0273), so Homebrew's bin, which brew_keg linked, comes first.
  PATH="$HOMEBREW_PREFIX/bin:$PATH" run devbin_run "$proj" doctor
  assert_output_contains "switch: no link, so brew"
  refute_output_contains "the switch rests at brew"
}

@test "doctor says nothing of a dev tree past brew's version: the work is not released yet (0228)" {
  src="$(mkdevsrc)"
  versioned "$src" 0.4.0
  brew_keg --from "$src" 0.1.0
  versioned "$src" 0.4.1
  [[ "$(devbin_tree_line "$KEG")" == "devbin 0.4.0 (brew, "* ]] || fail "brew's devbin reads $(devbin_tree_line "$KEG")"
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  switch_to "$src"
  run devbin_run "$proj" doctor
  assert_output_contains "switch: the link names"
  refute_output_contains "the switch rests at brew"
}

@test "the contract says the switch rests at brew, and devbin's release ends back on it (0228)" {
  grep -qF -- '- **The switch rests at brew.**' "$DEVBIN_HOME/docs/dev-opt-brew.md" ||
    fail "T5 does not say the switch rests at brew"
  grep -qF -- 'put this machine back on brew' "$DEVBIN_HOME/docs/releasing.md" ||
    fail "docs/releasing.md does not end its checklist back on brew"
  grep -qF -- '`brew upgrade devbin`, then `devbin use brew`, then `devbin --version`' "$DEVBIN_HOME/docs/releasing.md" ||
    fail "docs/releasing.md does not name the steps back to brew"
}

@test "the contract says use brew refuses, removing nothing, when no brew-managed copy would answer (T5, 0235)" {
  local refusal="\`use brew\` refuses, removing nothing, when no brew-managed copy would answer once the links are gone (the formula is not installed, its keg is not linked, or another copy comes first on PATH): it names each link it would have removed and the tree that link serves, why no Homebrew copy would answer, and the tool's own remedy (install or link the formula, or stay on dev or opt)."
  grep -qF -- "$refusal" "$DEVBIN_HOME/docs/dev-opt-brew.md" || fail "T5 does not carry use brew's refusal (0235)"
}

@test "a version line is read to its closing parenthesis, so the shape before 0230 reads as the same identity" {
  # T4's reader rule (0230): the tail after the parenthesis, the old
  # ` at <root>` or a compiled tool's provenance word, is ignored.
  [ "$(tree_line_head "devbin 0.1.14 (opt, 0123456789ab) at $PREFIX")" = "devbin 0.1.14 (opt, 0123456789ab)" ] ||
    fail "the old shape reads: $(tree_line_head "devbin 0.1.14 (opt, 0123456789ab) at $PREFIX")"
  [ "$(tree_line_head "tool 1.2.3 (dev, 0123456789ab+dirty) release")" = "tool 1.2.3 (dev, 0123456789ab+dirty)" ] ||
    fail "a provenance word reads: $(tree_line_head "tool 1.2.3 (dev, 0123456789ab+dirty) release")"
  [ "$(tree_line_head "devbin 0.1.15 (dev, unknown)")" = "devbin 0.1.15 (dev, unknown)" ] ||
    fail "the new shape reads: $(tree_line_head "devbin 0.1.15 (dev, unknown)")"
}
