#!/usr/bin/env bats
# tool.bats - the dev/opt/brew functions for any tool (docs/dev-opt-brew.md;
# issue 0326).
#
# devbin's own switch, tree and keg functions are the tool_ functions in
# lib/helpers called with devbin's names, so every arm here runs a second tool
# through them: its formula `demo` and its link `demo-cli`, two names, so an arm
# fails where one is read for the other. use.bats, machinepointer.bats and the
# switch rows in doctor.bats hold devbin's own answers.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a project's declaration of its tool, its install, its use and its doctor
#     rows, which later units of the issue add and test;
#   - the keg layout on macOS, where devbin's formula writes an env script: the
#     arms here build the Linux layout, a link into libexec.

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
teardown() { devbin_teardown; }

# demo_keg <version> -- the formula demo's keg for <version> as Homebrew places
# one, at the test's $HOMEBREW_PREFIX/Cellar/demo/<version>: libexec holding the
# link demo-cli's file, executable, no manifest, the keg's own bin/demo-cli a
# link into libexec, and opt/demo linked to the keg.
demo_keg() {
  local keg="$HOMEBREW_PREFIX/Cellar/demo/$1"
  mkdir -p "$keg/libexec/bin" "$keg/bin" "$HOMEBREW_PREFIX/opt" || return 1
  printf '#!/bin/sh\necho demo\n' >"$keg/libexec/bin/demo-cli" || return 1
  chmod 0755 "$keg/libexec/bin/demo-cli" || return 1
  ln -sfn ../libexec/bin/demo-cli "$keg/bin/demo-cli" || return 1
  ln -sfn "../Cellar/demo/$1" "$HOMEBREW_PREFIX/opt/demo"
}

# demo_bin_link <version> -- Homebrew's bin link for demo-cli, as `brew link
# demo` makes it, into the keg's own bin.
demo_bin_link() {
  mkdir -p "$HOMEBREW_PREFIX/bin" || return 1
  ln -sfn "../Cellar/demo/$1/bin/demo-cli" "$HOMEBREW_PREFIX/bin/demo-cli"
}

# demo_tree <dir> -- a tree at <dir> whose bin/demo-cli is an executable file.
demo_tree() {
  mkdir -p "$1/bin" || return 1
  printf '#!/bin/sh\necho demo\n' >"$1/bin/demo-cli" || return 1
  chmod 0755 "$1/bin/demo-cli"
}

@test "0326-1: a tool's keg, opt link, Homebrew bin link and switch link are spelled from its formula and its link, and devbin's from its own" {
  [ "$(tool_brew_opt_link /p/ demo)" = /p/opt/demo ] || fail "the opt link: $(tool_brew_opt_link /p/ demo)"
  [ "$(tool_brew_opt_root /p demo)" = /p/opt/demo/libexec ] || fail "the opt root: $(tool_brew_opt_root /p demo)"
  [ "$(tool_brew_bin_link /p/ demo-cli)" = /p/bin/demo-cli ] || fail "the bin link: $(tool_brew_bin_link /p/ demo-cli)"
  [ "$(tool_brew_keg_prefix /p/Cellar/demo/1.2.3/libexec demo)" = /p ] || fail "demo's keg is not read as one"
  if tool_brew_keg_prefix /p/Cellar/devbin/1.2.3/libexec demo >/dev/null; then
    fail "devbin's keg read as demo's"
  fi
  [ "$(tool_install_named_root /p/Cellar/demo/1.2.3/libexec demo)" = /p/opt/demo/libexec ] ||
    fail "demo's keg is not named by its opt link: $(tool_install_named_root /p/Cellar/demo/1.2.3/libexec demo)"
  [ "$(tool_install_launcher_root /p/Cellar/demo/1.2.3/libexec demo)" = /p/opt/demo ] ||
    fail "demo's keg's launcher root: $(tool_install_launcher_root /p/Cellar/demo/1.2.3/libexec demo)"
  [ "$(tool_link_path demo-cli)" = "$HOME/.local/bin/demo-cli" ] || fail "the switch link: $(tool_link_path demo-cli)"
  [ "$(brew_opt_link /p)" = /p/opt/devbin ] || fail "devbin's opt link: $(brew_opt_link /p)"
  [ "$(devbin_link_path)" = "$HOME/.local/bin/devbin" ] || fail "devbin's link: $(devbin_link_path)"
}

@test "0326-1: one formatter builds every tool's line from its parts: its name, version and tree, twelve hex digits, and the mark" {
  local sha=0123456789abcdef0123456789abcdef01234567
  [ "$(tool_line demo 1.2.3 opt "$sha")" = "demo 1.2.3 (opt, 0123456789ab)" ] ||
    fail "a clean line: $(tool_line demo 1.2.3 opt "$sha")"
  [ "$(tool_line demo 1.2.3 dev "$sha" +dirty)" = "demo 1.2.3 (dev, 0123456789ab+dirty)" ] ||
    fail "a marked line: $(tool_line demo 1.2.3 dev "$sha" +dirty)"
  [ "$(tool_line demo 1.2.3 dev 0123456789a +dirty)" = "demo 1.2.3 (dev, unknown)" ] ||
    fail "a commit short of twelve digits: $(tool_line demo 1.2.3 dev 0123456789a +dirty)"
  [ "$(tool_line demo "" brew unknown)" = "demo unknown (brew, unknown)" ] ||
    fail "no version and no commit: $(tool_line demo "" brew unknown)"
}

@test "0326-1: a tool's install manifest names its tree by T4's first two rules: brew by managed_by, opt by its own tool, unknown for another's" {
  local r="$DEVBIN_TEST_TMPDIR/demo-root"
  mkdir -p "$r"
  printf '# tool: demo\n# version: 1.2.3\n# managed_by: demo\n' >"$r/.demo-install"
  [ "$(tool_install_tree_word "$r" demo .demo-install)" = opt ] || fail "demo's own install: $(tool_install_tree_word "$r" demo .demo-install)"
  [ "$(tool_manifest_field "$r" .demo-install version)" = 1.2.3 ] || fail "its version: $(tool_manifest_field "$r" .demo-install version)"
  printf '# tool: demo\n# managed_by: brew\n' >"$r/.demo-install"
  [ "$(tool_install_tree_word "$r" demo .demo-install)" = brew ] || fail "the keg's: $(tool_install_tree_word "$r" demo .demo-install)"
  printf '# tool: other\n# managed_by: other\n' >"$r/.demo-install"
  [ "$(tool_install_tree_word "$r" demo .demo-install)" = unknown ] ||
    fail "another tool's install read as demo's: $(tool_install_tree_word "$r" demo .demo-install)"
  rm "$r/.demo-install"
  [ "$(tool_install_tree_word "$r" demo .demo-install)" = unknown ] ||
    fail "no manifest read as a tree: $(tool_install_tree_word "$r" demo .demo-install)"
  run tool_manifest_field "$r" .demo-install tool
  assert_exit_code 1
}

@test "0326-1: a keg with no manifest is a tool's brew tree only where it resolves to that tool's own opt link" {
  local keg="$HOMEBREW_PREFIX/Cellar/demo/1.0.0/libexec"
  demo_keg 1.0.0 || fail "the fixture's keg could not be made"
  tool_unmanifested_keg "$keg" demo .demo-install || fail "demo's keg, by its Cellar path, is not demo's brew tree"
  tool_unmanifested_keg "$HOMEBREW_PREFIX/opt/demo/libexec" demo .demo-install ||
    fail "demo's keg, by its opt link, is not demo's brew tree"
  if tool_unmanifested_keg "$keg" other .other-install; then
    fail "demo's keg read as another formula's"
  fi
  printf '# tool: demo\n' >"$keg/.demo-install"
  if tool_unmanifested_keg "$keg" demo .demo-install; then
    fail "a keg with a manifest read as one without"
  fi
}

@test "0326-1: a tool's link state follows its own link to its tree, names the tool's switch for a file where the link belongs, and leaves devbin's switch alone" {
  local t="$DEVBIN_TEST_TMPDIR/opt-demo" link="$HOME/.local/bin/demo-cli" want got
  demo_tree "$t" || fail "the fixture's tree could not be made"
  mkdir -p "$HOME/.local/bin"
  [ "$(tool_link_state demo demo-cli "bin/devbin use")" = none ] || fail "no link reads: $(tool_link_state demo demo-cli "bin/devbin use")"
  ln -s "$t/bin/demo-cli" "$link"
  want="at $(cd -P "$t" && pwd -P)"
  got="$(tool_link_state demo demo-cli "bin/devbin use")"
  [ "$got" = "$want" ] || fail "the link to demo's tree reads: $got"
  [ "$(machine_link_state)" = none ] || fail "devbin's switch read demo's link: $(machine_link_state)"
  rm "$link"
  printf 'not a link\n' >"$link"
  got="$(tool_link_state demo demo-cli "bin/devbin use")"
  [ "$got" = "bad $link is not a link, so it is no choice bin/devbin use made -- remove it, or run bin/devbin use brew" ] ||
    fail "a file where the link belongs reads: $got"
  rm "$link"
  mkdir -p "$DEVBIN_TEST_TMPDIR/else/bin"
  printf 'x\n' >"$DEVBIN_TEST_TMPDIR/else/bin/other"
  ln -s "$DEVBIN_TEST_TMPDIR/else/bin/other" "$link"
  got="$(tool_link_state demo demo-cli "bin/devbin use")"
  [[ "$got" == "bad the link $link leads to "*", which is no demo tree's bin/demo-cli" ]] ||
    fail "a link to another file reads: $got"
}

@test "0326-1: a tool's shadow check asks PATH for its own link's name, and devbin's check does not read it" {
  local t="$DEVBIN_TEST_TMPDIR/opt-demo" first="$DEVBIN_TEST_TMPDIR/first" link="$HOME/.local/bin/demo-cli" got
  demo_tree "$t" || fail "the fixture's tree could not be made"
  mkdir -p "$first" "$HOME/.local/bin"
  printf '#!/bin/sh\n' >"$first/demo-cli"
  chmod 0755 "$first/demo-cli"
  ln -s "$t/bin/demo-cli" "$link"
  got="$(PATH="$HOME/.local/bin:$first:/usr/bin:/bin" tool_link_shadow demo demo-cli)"
  [ -z "$got" ] || fail "the link first on PATH reads as shadowed: $got"
  got="$(PATH="$first:$HOME/.local/bin:/usr/bin:/bin" tool_link_shadow demo demo-cli)"
  [ "$got" = "the link $link is shadowed: the first demo-cli on PATH is $first/demo-cli -- put $HOME/.local/bin ahead of $first on PATH" ] ||
    fail "a shadowed link reads: $got"
  got="$(PATH="$first:$HOME/.local/bin:/usr/bin:/bin" devbin_link_shadow)"
  [ -z "$got" ] || fail "devbin's shadow check read demo's link: $got"
}

@test "0326-1: a tool's Homebrew answer finds its own keg, and its wording names the formula in brew's commands and the link on PATH" {
  local root="$HOMEBREW_PREFIX/opt/demo/libexec" got
  demo_keg 1.0.0 || fail "the fixture's keg could not be made"
  got="$(PATH="/usr/bin:/bin" tool_brew_answer_state demo demo-cli)"
  [ "$got" = "unlinked $root" ] || fail "an unlinked keg reads: $got"
  got="$(tool_brew_path_why demo demo-cli "$got")"
  [ "$got" = "Homebrew's demo-cli at $root is not linked: no demo-cli in $HOMEBREW_PREFIX/bin leads into it
link it (brew link demo)" ] || fail "an unlinked keg is said: $got"
  demo_bin_link 1.0.0 || fail "the fixture's bin link could not be made"
  got="$(PATH="$HOMEBREW_PREFIX/bin:/usr/bin:/bin" tool_brew_answer_state demo demo-cli)"
  [ "$got" = "brew $root" ] || fail "a linked keg on PATH reads: $got"
  got="$(tool_brew_path_why demo demo-cli "noexec $root/bin/demo-cli")"
  [[ "$got" == *$'\n'"reinstall demo with Homebrew (brew reinstall demo)" ]] || fail "a keg that would not run is said: $got"
  rm -f "$HOMEBREW_PREFIX/opt/demo"
  [ "$(tool_brew_answer_state demo demo-cli)" = absent ] || fail "no keg reads: $(tool_brew_answer_state demo demo-cli)"
  [ "$(tool_brew_none_why demo)" = "Homebrew has no demo here (no demo at $root, under HOMEBREW_PREFIX)" ] ||
    fail "no keg is said: $(tool_brew_none_why demo)"
  [ "$(tool_brew_unplaced_fix demo)" = "install demo with Homebrew" ] || fail "its remedy: $(tool_brew_unplaced_fix demo)"
}
