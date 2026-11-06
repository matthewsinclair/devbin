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
# A project declares its tool in an install: block, and the 0326-2 arms hold
# the declaration's validation and its readers in lib/config.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a tool's install, its use and its doctor rows, which later units of the
#     issue add and test;
#   - the keg layout on macOS, where devbin's formula writes an env script: the
#     arms here build the Linux layout, a link into libexec.

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
}
teardown() { devbin_teardown; }

# tool_config <yaml> -- <yaml>, a project's config, loaded as the config the arm
# reads, from the file $DEVBIN_TEST_TMPDIR/config.yaml.
tool_config() {
  printf '%s\n' "$1" >"$DEVBIN_TEST_TMPDIR/config.yaml" || return 1
  cfg_load "$DEVBIN_TEST_TMPDIR/config.yaml"
}

# refused_with <yaml> <text> -- the arm: <yaml> loads, cfg_validate refuses it,
# and what it says holds <text>.
refused_with() {
  tool_config "$1" || fail "the fixture's config did not load"
  run --separate-stderr cfg_validate
  [ "$status" -ne 0 ] || fail "validated: $1"
  [[ "$stderr" == *"$2"* ]] || fail "refused without \"$2\": $stderr"
}

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

@test "0326-2: a tool's declaration validates: its prefix, its manifest, its links, and each file's path, dev file and platforms" {
  tool_config 'project:
  name: demo
install:
  prefix: ~/opt/demo
  manifest: .demo-install
  links:
    demo-cli: target/release/demo-cli
    demo-gui: target/release/demo-gui
  files:
    config:
      path: share/config.toml
      from: examples/config.toml
      platforms:
        - macos' || fail "the fixture's config did not load"
  run --separate-stderr cfg_validate
  [ "$status" -eq 0 ] || fail "refused: $stderr"
}

@test "0326-2: a link name a link cannot carry, a path outside its root, and two files at one place are each refused by name" {
  refused_with 'project:
  name: demo
install:
  links:
    _cli: bin/cli' 'install.links._cli: "_cli" is no link name'
  refused_with 'project:
  name: demo
install:
  links:
    demo: /abs/demo' 'install.links.demo: "/abs/demo" is absolute -- name a path relative to the project root'
  refused_with 'project:
  name: demo
install:
  manifest: ../demo-install' "install.manifest: \"../demo-install\" has an empty, . or .. segment -- write the path once, as git names it, below the tool's tree root"
  refused_with 'project:
  name: demo
install:
  files:
    config:
      path: bin/demo' "install.files.config.path: \"bin/demo\" is install.links.demo's place in the tree too"
  refused_with 'project:
  name: demo
install:
  files:
    config:
      from: examples/config.toml' 'install.files.config declares no path'
}

@test "0326-2: formula.manifest is refused as retired, naming install.manifest, the tool's own" {
  refused_with 'project:
  name: demo
formula:
  mode: assets
  manifest: .demo-install' "unknown key: formula.manifest -- retired: the manifest is the tool's own, install.manifest"
}

@test "0326-2: the tool's links, manifest and files are read from its declaration, and the formula's name gives what it leaves out" {
  local tab=$'\t'
  tool_config 'project:
  name: demo
install:
  prefix: ~/opt/demo' || fail "the fixture's config did not load"
  [ "$(cfg_tool_links)" = "demo${tab}bin/demo" ] || fail "the links left out read: $(cfg_tool_links)"
  [ "$(cfg_tool_manifest)" = .demo-install ] || fail "the manifest left out reads: $(cfg_tool_manifest)"
  [ -z "$(cfg_tool_files macos)" ] || fail "no files read as: $(cfg_tool_files macos)"
  tool_config 'project:
  name: demo
formula:
  name: other
install:
  prefix: ~/opt/other' || fail "the fixture's config did not load"
  [ "$(cfg_tool_links)" = "other${tab}bin/other" ] || fail "the formula's name gives the link: $(cfg_tool_links)"
  [ "$(cfg_tool_manifest)" = .other-install ] || fail "the formula's name gives the manifest: $(cfg_tool_manifest)"
  tool_config 'project:
  name: demo
install:
  manifest: var/demo.manifest
  links:
    demo-cli: target/release/demo-cli
    demo-gui: target/release/demo-gui
  files:
    config:
      path: share/config.toml
      from: examples/config.toml
      platforms:
        - macos
    readme:
      path: README.md' || fail "the fixture's config did not load"
  [ "$(cfg_tool_links)" = "demo-cli${tab}target/release/demo-cli
demo-gui${tab}target/release/demo-gui" ] || fail "the declared links read: $(cfg_tool_links)"
  [ "$(cfg_tool_manifest)" = var/demo.manifest ] || fail "the declared manifest reads: $(cfg_tool_manifest)"
  [ "$(cfg_tool_files macos)" = "config${tab}share/config.toml${tab}examples/config.toml
readme${tab}README.md${tab}README.md" ] || fail "macos's files read: $(cfg_tool_files macos)"
  [ "$(cfg_tool_files linux)" = "readme${tab}README.md${tab}README.md" ] || fail "linux's files read: $(cfg_tool_files linux)"
}

@test "0326-2: a project with an install: block declares a tool, and one without does not" {
  tool_config 'project:
  name: demo
install:
  prefix: ~/opt/demo' || fail "the fixture's config did not load"
  cfg_is_tool || fail "a project with an install: block is no tool"
  tool_config 'project:
  name: demo' || fail "the fixture's config did not load"
  if cfg_is_tool; then
    fail "a project with no install: block is a tool"
  fi
}

@test "0326-2: devbin's own checkout declares the manifest path its bootstrap reads" {
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml" || fail "devbin's own config did not load"
  [ "$(cfg_tool_manifest)" = "$DEVBIN_MANIFEST_REL" ] ||
    fail "devbin declares $(cfg_tool_manifest), and its bootstrap reads $DEVBIN_MANIFEST_REL"
}

# stamp_project [--no-tool] [<yaml>] -- a project, devbin installed and
# committed in git with target/ ignored, VERSION 1.2.3, whose declared build
# (tools/build.sh) writes target/release/demo-cli as a program that prints the
# DEVBIN_VERSION_LINE it was built with, writes that file's dependency record
# naming src/main.txt, and adds the line it carried to target/runs, one line a
# run. It declares the tool demo, with the link demo-cli at
# target/release/demo-cli, unless --no-tool; <yaml> is added at the config's
# top level.
stamp_project() {
  local tool=yes proj
  if [ "${1:-}" = --no-tool ]; then
    tool=""
    shift
  fi
  proj="$DEVBIN_TEST_TMPDIR/stamped"
  create_test_project stamped >/dev/null || return 1
  install_devbin "$proj" || return 1
  {
    printf 'project:\n  name: demo\n'
    if [ -n "$tool" ]; then
      printf 'install:\n  prefix: %s/opt-demo\n  links:\n    demo-cli: target/release/demo-cli\n' "$DEVBIN_TEST_TMPDIR"
    fi
    printf 'commands:\n  build:\n    run: sh tools/build.sh\n'
    [ -z "${1:-}" ] || printf '%s\n' "$1"
  } >"$proj/bin/.devbin/config.yaml" || return 1
  mkdir -p "$proj/tools" "$proj/src" "$proj/docs" || return 1
  printf '1.2.3\n' >"$proj/VERSION" || return 1
  printf 'source\n' >"$proj/src/main.txt" || return 1
  printf 'notes\n' >"$proj/docs/notes.md" || return 1
  printf 'target/\n' >"$proj/.gitignore" || return 1
  {
    printf '#!/bin/sh\nset -e\nmkdir -p target/release\n'
    printf '%s\n' "printf \"#!/bin/sh\\necho '%s'\\n\" \"\$DEVBIN_VERSION_LINE\" >target/release/demo-cli"
    printf 'chmod 755 target/release/demo-cli\n'
    printf '%s\n' "printf '%s/target/release/demo-cli: %s/src/main.txt\\n' \"\$PWD\" \"\$PWD\" >target/release/demo-cli.d"
    printf '%s\n' "printf '%s\\n' \"\$DEVBIN_VERSION_LINE\" >>target/runs"
  } >"$proj/tools/build.sh" || return 1
  git -C "$proj" init -q >/dev/null 2>&1 || return 1
  git -C "$proj" add -A >/dev/null 2>&1 || return 1
  git -C "$proj" -c user.email=t@t -c user.name=t -c maintenance.auto=false commit -q -m fixture >/dev/null 2>&1 || return 1
  printf '%s\n' "$proj"
}

@test "0326-3: a tool's build is handed its dev line: the tool's name, its version, and HEAD's twelve digits" {
  local proj sha
  proj="$(stamp_project)" || fail "the fixture's project could not be made"
  sha="$(git -C "$proj" rev-parse HEAD)"
  run devbin_run "$proj" build
  assert_success
  run "$proj/target/release/demo-cli"
  assert_success
  [ "$output" = "demo 1.2.3 (dev, ${sha:0:12})" ] || fail "the build carried: $output"
}

@test "0326-3: an input the build's record names, changed and uncommitted, marks the line +dirty, and a docs write does not" {
  local proj sha
  proj="$(stamp_project)" || fail "the fixture's project could not be made"
  sha="$(git -C "$proj" rev-parse HEAD)"
  run devbin_run "$proj" build
  assert_success
  printf 'more\n' >>"$proj/docs/notes.md"
  run devbin_run "$proj" build
  assert_success
  run "$proj/target/release/demo-cli"
  [ "$output" = "demo 1.2.3 (dev, ${sha:0:12})" ] || fail "a docs write marked the line: $output"
  printf 'changed\n' >>"$proj/src/main.txt"
  run devbin_run "$proj" build
  assert_success
  run "$proj/target/release/demo-cli"
  [ "$output" = "demo 1.2.3 (dev, ${sha:0:12}+dirty)" ] || fail "a changed input left the line: $output"
}

@test "0326-3: when the record a build writes names a changed input its line missed, the build runs once more to carry +dirty, and says so" {
  local proj sha clean marked
  proj="$(stamp_project 'build:
  inputs:
    - VERSION')" || fail "the fixture's project could not be made"
  sha="$(git -C "$proj" rev-parse HEAD)"
  clean="demo 1.2.3 (dev, ${sha:0:12})"
  marked="demo 1.2.3 (dev, ${sha:0:12}+dirty)"
  printf 'changed\n' >>"$proj/src/main.txt"
  run devbin_run "$proj" build
  assert_success
  assert_output_contains "the build read inputs its line did not count ($clean), so it runs once more to carry: $marked"
  [ "$(cat "$proj/target/runs")" = "$clean
$marked" ] || fail "the builds carried, in turn: $(cat "$proj/target/runs")"
  run "$proj/target/release/demo-cli"
  [ "$output" = "$marked" ] || fail "the program built last carries: $output"
}

@test "0326-3: a project that declares no tool hands its build no line" {
  local proj
  proj="$(stamp_project --no-tool)" || fail "the fixture's project could not be made"
  run devbin_run "$proj" build
  assert_success
  [ -z "$(cat "$proj/target/runs")" ] || fail "a project with no tool's build carried: $(cat "$proj/target/runs")"
}
