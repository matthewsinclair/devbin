#!/usr/bin/env bats
# cache.bats - the built-in cache (ST0011 WP-16): this machine's registry of
# built artefacts, keyed on the git objects of the inputs a build reads, so a
# build whose inputs did not change pulls what it built before.
#
# Each arm stands in a fixture project with devbin installed, a build: block
# declaring one artefact, app (tool cargo, path out/app, its input src), a git
# history holding src/a.rs and a README, and the project's own build handler,
# which runs `cache get app` and, on anything but a pull, builds out/app and
# runs `cache put app`, printing each verb's exit and exiting 0 whatever the
# cache says, as a project's build does. A stub cargo first on PATH says its
# version, so the key's toolchain line is the arm's own. The registry's root
# is the test's own directory unless an arm says otherwise.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a real toolchain's answer: each row's line is read off a literal of that
#     tool's own output, and only the stub cargo is ever asked, so elixir,
#     swift and xcodebuild are asked only by a build on a machine that has them.
#   - two builds putting one key at once: the later rename finds the earlier's
#     entry and removes its own copy from inside it, and no arm runs two
#     together.
#   - a directory artefact's extended attributes and ACLs, which tar is told
#     neither to record nor to restore: setting one is the platform's own
#     business (xattr on macOS, setfattr where installed), so no arm plants one.
#   - file flags on Linux: the arm that plants them sets macOS's uchg and
#     uappnd with chflags, and skips, saying so, where there is none, since
#     chattr +i is root's alone.
#   - a tracked path that differs from a declared one in a non-ASCII letter's
#     case or its Unicode form: git's icase folds the ASCII letters alone, so no
#     arm declares one.

load "../lib/test_helper"

setup() {
  devbin_setup
  export DEVBIN_CACHE_HOME="$DEVBIN_TEST_TMPDIR/cache"
  export XDG_CACHE_HOME="$DEVBIN_TEST_TMPDIR/xdg-cache"
  export BUILD_LOG="$DEVBIN_TEST_TMPDIR/build.log"
  export BUILD_APP="$DEVBIN_TEST_TMPDIR/build-app"
  unset CARGO_STUB_VERSION CARGO_STUB_FAIL CARGO_STUB_CHATTER
  stub_cargo
  write_build_app
  PROJ="$(mkproj demo </dev/null)"
  use_config
  write_build_handler
  git init -q -b main "$PROJ"
  git -C "$PROJ" config user.name t
  git -C "$PROJ" config user.email t@t
  git -C "$PROJ" config maintenance.auto false
  git -C "$PROJ" config gc.auto 0
  mkdir -p "$PROJ/src"
  printf 'fn main() {}\n' >"$PROJ/src/a.rs"
  printf 'demo\n' >"$PROJ/README"
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
}

teardown() {
  # The unwritable root's own write bit, and the read bit of a run-logs
  # directory an arm took away, given back whatever the arm's outcome, so the
  # temp dir can go.
  if [ -n "${RO_ROOT:-}" ] && [ -d "$RO_ROOT" ]; then chmod u+w "$RO_ROOT"; fi
  if [ -n "${LOCKED_DIR:-}" ] && [ -d "$LOCKED_DIR" ]; then chmod u+rwx "$LOCKED_DIR"; fi
  # Where an arm set a file flag, every copy of it under the temp dir is cleared
  # too, one the code under test made in the registry included, or the temp
  # dir could not go.
  if [ -n "${IMMUTABLE_ARM:-}" ] && command -v chflags >/dev/null 2>&1; then
    chflags -R nouchg,nouappnd "$DEVBIN_TEST_TMPDIR" 2>/dev/null || true
  fi
  devbin_teardown
}

# use_config [<artefact> <path> [<input>...]] -- PROJ's config: the project
# PROJECT_NAME (demo unless set), with CARGO_ROOT as its cargo_root where set,
# and a build: block declaring one artefact, built by TOOL (cargo unless set)
# to <path> from the inputs; app, out/app and src unless given. Each path is
# written quoted, so an empty one is written too.
use_config() {
  local art=app path=out/app i
  if [ "$#" -ge 2 ]; then
    art="$1"
    path="$2"
    shift 2
  fi
  [ "$#" -gt 0 ] || set -- src
  {
    printf '%s\n' 'project:'
    printf '  name: %s\n' "${PROJECT_NAME:-demo}"
    if [ -n "${CARGO_ROOT:-}" ]; then printf '  cargo_root: %s\n' "$CARGO_ROOT"; fi
    printf '%s\n' 'build:' '  inputs:'
    for i in "$@"; do printf '    - "%s"\n' "$i"; done
    printf '%s\n' '  artefacts:' "    $art:"
    printf '      tool: %s\n' "${TOOL:-cargo}"
    printf '      path: "%s"\n' "$path"
  } >"$PROJ/bin/.devbin/config.yaml"
}

# other_arch -- an architecture this runner's uname does not name.
other_arch() {
  if [ "$(uname -m)" = x86_64 ]; then
    printf 'arm64\n'
  else
    printf 'x86_64\n'
  fi
}

# set_flags <flags> <file> -- chflags <flags> on <file>, macOS's file flags,
# cleared by this file's teardown; skipped, and said, where this runner has no
# chflags or cannot set them, as make_immutable skips.
set_flags() {
  command -v chflags >/dev/null 2>&1 || skip "chflags is not on this runner, so the file-flag cases were NOT checked"
  IMMUTABLE_ARM=1
  chflags "$1" "$2" 2>/dev/null || skip "this runner cannot set $1 on $2, so the file-flag cases were NOT checked"
}

# file_flags <file> -- <file>'s flags in hex, as macOS's own stat reads them;
# asked only after set_flags, which skips where there are none to read.
file_flags() { /usr/bin/stat -f %Xf -- "$1"; }

# locked_dir <dir> -- <dir> left searchable but not listable, given back by this
# file's teardown; skipped, and said, where this user lists it all the same,
# and FAILED under CI, where a skip is a coverage hole reported as a pass.
locked_dir() {
  LOCKED_DIR="$1"
  chmod 300 "$LOCKED_DIR"
  if [ -r "$LOCKED_DIR" ]; then
    [[ -z "${CI:-}" ]] || fail "this CI runner lists a directory without its read bit ($LOCKED_DIR), so the unlistable case cannot be built: run the job as a user that cannot"
    skip "running with permissions that list a directory without its read bit: the unlistable case was NOT checked"
  fi
}

# fail_sha256 -- a stub first on PATH for each tool lib/helpers's sha256_run
# asks for, each failing whatever it is asked, so no sha256 can be taken; the
# dispatcher takes none of its own. The tools are read off sha256_run, the one
# place that spells them, so a tool it learns is shadowed too.
fail_sha256() {
  local t tools d="$DEVBIN_TEST_TMPDIR/sha-stubs"
  tools="$(sed -n '/^sha256_run() {/,/^}/p' "$DEVBIN_LIB_DIR/helpers" | grep -oE 'command -v [[:alnum:]_]+' | awk '{ print $3 }')"
  if [ -z "$tools" ]; then
    fail "lib/helpers's sha256_run asks for no tool, so none can be shadowed"
    return 1
  fi
  mkdir -p "$d"
  for t in $tools; do
    printf '%s\n' '#!/usr/bin/env bash' "echo 'stub $t: no sha256 here' >&2" 'exit 1' >"$d/$t"
    chmod +x "$d/$t"
  done
  export PATH="$d:$PATH"
}

# write_build_app -- the fixture's build, the one writer for the handler and
# the arms: out/app from src/a.rs and the build's own number, so no two builds
# write the same bytes, and a line in BUILD_LOG for each build. Run in PROJ.
write_build_app() {
  # shellcheck disable=SC2016 # expanded when the build runs
  printf '%s\n' '#!/usr/bin/env bash' \
    'n=0' \
    '[ ! -f "$BUILD_LOG" ] || n="$(grep -c . "$BUILD_LOG")"' \
    'mkdir -p out || exit 1' \
    '{ cat src/a.rs; printf "build %s\n" "$((n + 1))"; } >out/app || exit 1' \
    'printf "built\n" >>"$BUILD_LOG"' >"$BUILD_APP"
  chmod +x "$BUILD_APP"
}

# write_build_handler -- PROJ's own build: `cache get app`, and on anything but
# a pull the build and `cache put app`, each verb's exit printed; it exits 0
# whatever the cache says.
write_build_handler() {
  local body
  # shellcheck disable=SC2016 # expanded when the handler runs
  body="$(printf '%s\n' '#!/usr/bin/env bash' \
    'cd "$PROJECT_ROOT" || exit 1' \
    'got=0' \
    './bin/devbin cache get app || got=$?' \
    '[ "$got" -ne 0 ] || exit 0' \
    'echo "get exit $got"' \
    '"$BUILD_APP" || exit 1' \
    'put=0' \
    './bin/devbin cache put app || put=$?' \
    'echo "put exit $put"')"
  create_test_command "$PROJ" build "$body" >/dev/null
}

# build_app -- the fixture's build, run by hand in PROJ.
build_app() { (cd "$PROJ" && "$BUILD_APP"); }

# app_key -- app's key at HEAD, through the command under test.
app_key() { devbin_run "$PROJ" cache key app; }

# commit_change <path> -- a commit in PROJ changing <path> alone.
commit_change() {
  printf 'change %s\n' "$(git -C "$PROJ" rev-list --count HEAD)" >>"$PROJ/$1"
  git -C "$PROJ" add -- "$1"
  git -C "$PROJ" commit -q -m "change $1"
}

# cache_const <NAME> -- the value lib/cmd/cache gives <NAME>, so no arm writes
# it down.
cache_const() {
  local v
  v="$(sed -n "s/^$1=\([0-9][0-9]*\)\$/\1/p" "$DEVBIN_LIB_DIR/cmd/cache" 2>/dev/null)"
  if [ -z "$v" ]; then
    fail "lib/cmd/cache sets no $1"
    return 1
  fi
  printf '%s\n' "$v"
}

# lib_say <function> [<arg>...] -- the runtime's own answer, lib/helpers and
# lib/runlog sourced, so the release seal's place and its lines' form are the
# release's and a toolchain line is the table's. In a subshell, as lib/helpers
# sets the shell options it runs under; not followed by shellcheck, since both
# files are linted in their own right.
# shellcheck disable=SC1091
lib_say() { (. "$DEVBIN_LIB_DIR/helpers" && . "$DEVBIN_LIB_DIR/runlog" && "$@"); }

# sha256_text -- the sha256 of stdin, in hex, by lib/helpers's sha256_stdin,
# the one place the sha256 tool is spelled, which helpers.bats checks against
# the published vector and holds every other file to.
sha256_text() { lib_say sha256_stdin; }

# entries -- how many entries the registry holds for demo, counted off the
# filesystem rather than through the command under test.
entries() {
  local e n=0
  for e in "$DEVBIN_CACHE_HOME"/demo/*/*/; do
    if [ -d "$e" ]; then n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

# builds -- how many times the fixture's build has run.
builds() {
  if [ -f "$BUILD_LOG" ]; then
    grep -c . "$BUILD_LOG"
  else
    printf '0\n'
  fi
}

# manifest_lines <manifest> -- the key's lines a manifest records, one a line,
# each `\t` back to a tab.
manifest_lines() {
  local l
  while IFS= read -r l; do
    case "$l" in
      '  - "'*'"')
        l="${l#'  - "'}"
        l="${l%'"'}"
        printf '%s\n' "${l//\\t/$'\t'}"
        ;;
    esac
  done <"$1"
}

# put_generations <n> -- <n> entries for app, each from a commit changing
# src/a.rs, oldest first in KEYS, each entry's time set a minute after the one
# before, so gc's newest is the arm's order and never the clock's resolution.
put_generations() {
  local i
  KEYS=()
  for ((i = 1; i <= $1; i++)); do
    commit_change src/a.rs
    build_app || return 1
    devbin_run "$PROJ" cache put app >/dev/null || return 1
    KEYS+=("$(app_key)")
    touch -t "$(printf '20260101%04d' "$i")" "$DEVBIN_CACHE_HOME/demo/app/${KEYS[-1]}" || return 1
  done
}

# assert_kept <n> -- the registry holds the newest <n> of KEYS and none of the
# rest.
assert_kept() {
  local i first=$((${#KEYS[@]} - $1))
  for i in "${!KEYS[@]}"; do
    if [ "$i" -ge "$first" ]; then
      assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/${KEYS[$i]}"
    else
      assert_directory_not_exists "$DEVBIN_CACHE_HOME/demo/app/${KEYS[$i]}"
    fi
  done
}

# assert_refused <text> -- the last `run --separate-stderr` was the cache's
# refusal: exit 7, nothing on stdout, and <text> in what it said on stderr.
assert_refused() {
  assert_exit_code 7
  if [ -n "$output" ]; then
    fail "a refusal printed: $output"
    return 1
  fi
  if [[ "$stderr" != *"$1"* ]]; then
    fail "the refusal does not say '$1':\n$stderr"
    return 1
  fi
}

# refused_with_usage <reason> <argument>... -- `cache <argument>...` is the
# cache's refusal (assert_refused) saying <reason>, and the usage follows it on
# stderr, as every refusal of an argument the cache cannot read says it.
refused_with_usage() {
  local reason="$1"
  shift
  run --separate-stderr devbin_run "$PROJ" cache "$@"
  assert_refused "$reason"
  if [[ "$stderr" != *$'\n'"usage:"* ]]; then
    fail "no usage after the refusal of 'cache $*':\n$stderr"
    return 1
  fi
}

# unusable_root <root> <why> -- under DEVBIN_CACHE_HOME <root>, get and put
# each refuse with the cache's 7 in one line on stderr naming <root> and <why>,
# and the project's build still exits 0, its cache verbs refused.
unusable_root() {
  local verb
  for verb in get put; do
    DEVBIN_CACHE_HOME="$1" run --separate-stderr devbin_run "$PROJ" cache "$verb" app
    assert_refused "the cache root $1 $2"
    if [[ "$stderr" == *$'\n'* ]]; then
      fail "$verb said more than one line:\n$stderr"
      return 1
    fi
  done
  DEVBIN_CACHE_HOME="$1" run devbin_run "$PROJ" build
  assert_success
  assert_output_contains "get exit 7"
  assert_output_contains "put exit 7"
}

# AT-5.1
@test "the key is the sha256 of its sorted lines, each input path's object at the commit, the toolchain's version, the platform's word and the CPU architecture, and put records those lines and the tree's cleanliness in the entry's manifest (WP16, AC-5.1)" {
  local word want key entry
  case "$(uname -s)" in
    Darwin) word=macos ;;
    Linux) word=linux ;;
    *) fail "this suite runs on macOS or Linux, and $(uname -s) is neither" ;;
  esac
  want="$(printf 'src\t%s\ntoolchain\t%s\nplatform\t%s\narch\t%s' "$(git -C "$PROJ" rev-parse HEAD:src)" "$(cargo --version)" "$word" "$(uname -m)")"
  run devbin_run "$PROJ" cache key app
  assert_success
  key="$output"
  [ "$key" = "$(LC_ALL=C sort <<<"$want" | sha256_text)" ] || fail "the key $key is not the sha256 of its sorted lines:\n$want"
  build_app
  run devbin_run "$PROJ" cache put app
  assert_success
  assert_output "put app $key"
  entry="$DEVBIN_CACHE_HOME/demo/app/$key"
  assert_file_contains "$entry/manifest.yaml" "key: $key"
  [ "$(manifest_lines "$entry/manifest.yaml" | LC_ALL=C sort)" = "$(LC_ALL=C sort <<<"$want")" ] ||
    fail "the manifest records other lines than the key's:\n$(cat "$entry/manifest.yaml")"
  assert_file_contains "$entry/manifest.yaml" "tree: clean"
  printf 'edit\n' >>"$PROJ/README"
  run devbin_run "$PROJ" cache put app
  assert_success
  assert_output "put app $key"
  assert_file_contains "$entry/manifest.yaml" "tree: dirty outside the inputs"
}

# AT-5.1
@test "the key stands across a commit that changes only what the inputs do not hold, changes when an input's object does, and --commit reads an earlier commit's (WP16, AC-5.1)" {
  local first sha
  first="$(app_key)"
  sha="$(git -C "$PROJ" rev-parse HEAD)"
  commit_change README
  run devbin_run "$PROJ" cache key app
  assert_success
  assert_output "$first"
  commit_change src/a.rs
  run devbin_run "$PROJ" cache key app
  assert_success
  [ "$output" != "$first" ] || fail "the key stood though src/a.rs's object changed: $output"
  run devbin_run "$PROJ" cache key app --commit "$sha"
  assert_success
  assert_output "$first"
}

# AT-5.1
@test "another version of the toolchain is another key, and a toolchain that cannot say its version leaves the artefact no key (WP16, AC-5.1)" {
  local first
  first="$(app_key)"
  CARGO_STUB_VERSION=2.0.0 run devbin_run "$PROJ" cache key app
  assert_success
  [ -n "$output" ] && [ "$output" != "$first" ] || fail "another cargo kept the key: $output"
  CARGO_STUB_FAIL=1 run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "the cargo toolchain cannot say its version"
}

# AT-5.1
@test "cargo is asked its version where the workspace is, project.cargo_root, so a toolchain file there is another key (WP16, AC-5.1)" {
  local before
  mkdir -p "$PROJ/ws"
  printf '[workspace]\n' >"$PROJ/ws/Cargo.toml"
  CARGO_ROOT=ws use_config
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m "a workspace in ws"
  before="$(app_key)"
  printf '9.9.9\n' >"$PROJ/ws/.stub-toolchain"
  run devbin_run "$PROJ" cache key app
  assert_success
  [ -n "$output" ] && [ "$output" != "$before" ] || fail "a toolchain file where the workspace is kept the key: $output"
}

# AT-5.1
@test "the toolchain line is the tool's own: cargo's and swift's first line, xcodebuild's lines joined, and elixir's Erlang/OTP release and erts with Elixir's own line, whatever the emulator's flags; an answer its row cannot read is none (WP16, AC-5.1)" {
  local elixir_line='Erlang/OTP 29 [erts-17.1.1]; Elixir 1.20.5 (compiled with Erlang/OTP 29)'
  run lib_say cache_tool_line elixir "$(printf '%s\n' 'Erlang/OTP 29 [erts-17.1.1] [source] [64-bit] [smp:16:16] [ds:16:16:10] [async-threads:1] [jit] [dtrace]' '' 'Elixir 1.20.5 (compiled with Erlang/OTP 29)')"
  assert_success
  assert_output "$elixir_line"
  run lib_say cache_tool_line elixir "$(printf '%s\n' 'Erlang/OTP 29 [erts-17.1.1] [source] [64-bit] [smp:2:2] [ds:2:2:10] [async-threads:1] [jit]' '' 'Elixir 1.20.5 (compiled with Erlang/OTP 29)')"
  assert_success
  assert_output "$elixir_line"
  run lib_say cache_tool_line swift "$(printf '%s\n' 'swift-driver version: 1.168.6 Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)' 'Target: arm64-apple-macosx27.0.0')"
  assert_success
  assert_output 'swift-driver version: 1.168.6 Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)'
  run lib_say cache_tool_line xcodebuild "$(printf '%s\n' 'Xcode 27.2' 'Build version 27B52')"
  assert_success
  assert_output 'Xcode 27.2; Build version 27B52'
  run lib_say cache_tool_line cargo 'cargo 1.91.0 (ea2d97820 2025-10-10)'
  assert_success
  assert_output 'cargo 1.91.0 (ea2d97820 2025-10-10)'
  run lib_say cache_tool_line elixir 'Erlang/OTP 29 [erts-17.1.1]'
  assert_failure
  assert_output ''
  run lib_say cache_tool_line rustc 'rustc 1.91.0 (f8297e351 2025-10-28)'
  assert_failure
  assert_output ''
  run lib_say cache_tool_line cargo ''
  assert_failure
  assert_output ''
}

# AT-5.1
@test "another CPU architecture is another key, named in the entry's manifest, and a host whose architecture is not one word has no key (WP16, AC-5.1)" {
  local native other key
  native="$(app_key)"
  other="$(other_arch)"
  stub_uname -m UNAME_STUB_ARCH
  UNAME_STUB_ARCH="$other" run devbin_run "$PROJ" cache key app
  assert_success
  key="$output"
  [ -n "$key" ] && [ "$key" != "$native" ] || fail "the key stood on another architecture: $key"
  build_app
  UNAME_STUB_ARCH="$other" run devbin_run "$PROJ" cache put app
  assert_success
  assert_output "put app $key"
  grep -qxF "$(printf 'arch\t%s' "$other")" <<<"$(manifest_lines "$DEVBIN_CACHE_HOME/demo/app/$key/manifest.yaml")" ||
    fail "the manifest does not name the architecture $other:\n$(cat "$DEVBIN_CACHE_HOME/demo/app/$key/manifest.yaml")"
  UNAME_STUB_ARCH="" run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "CPU architecture cannot be named as one word"
}

# AT-5.1
@test "a key whose sha256 cannot be taken is no key: key and get refuse, and the entries the registry holds stay (WP16, AC-5.1)" {
  local key entry
  build_app
  devbin_run "$PROJ" cache put app >/dev/null
  key="$(app_key)"
  entry="$DEVBIN_CACHE_HOME/demo/app/$key"
  fail_sha256
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "the sha256 of the key's lines could not be taken"
  run --separate-stderr devbin_run "$PROJ" cache get app
  assert_refused "the sha256 of the key's lines could not be taken"
  assert_file_exists "$entry/artefact"
  assert_file_exists "$entry/SHA256SUMS"
}

# AT-5.1
@test "an input path with uncommitted or untracked changes has no key: key and put refuse with a line naming it, and nothing is recorded (WP16, AC-5.1)" {
  build_app
  printf 'edit\n' >>"$PROJ/src/a.rs"
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "uncommitted changes"
  [[ "$stderr" == *"uncommitted changes"*"src/a.rs" ]] || fail "the refusal does not name the input: $stderr"
  run --separate-stderr devbin_run "$PROJ" cache put app
  assert_refused "uncommitted changes"
  [[ "$stderr" == *"uncommitted changes"*"src/a.rs" ]] || fail "put's refusal does not name the input: $stderr"
  assert_directory_not_exists "$DEVBIN_CACHE_HOME/demo"
  git -C "$PROJ" checkout -q -- src/a.rs
  printf 'new\n' >"$PROJ/src/b.rs"
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "uncommitted changes"
  [[ "$stderr" == *"uncommitted changes"*"src/b.rs" ]] || fail "an untracked input is not named: $stderr"
}

@test "the declaration's refusals exit 7 naming the reason: a key the build: block does not know, a tool outside the table, an artefact's name that does not start with a letter or a digit, a path that is empty, absolute, outside the project or in its .git in any case of its letters, an artefact's path that is, holds or lies in an input path in any case of its letters, another artefact's own input among them, no build: block, an undeclared artefact (WP16)" {
  local spec name
  printf '      flavour: x\n' >>"$PROJ/bin/.devbin/config.yaml"
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "unknown key: build.artefacts.app.flavour"
  TOOL=rustc use_config
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused 'build.artefacts.app.tool: "rustc" is no row of the toolchain table'
  use_config app /
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused 'build.artefacts.app.path: "/" is absolute'
  use_config app ../demo
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused 'build.artefacts.app.path: "../demo" has an empty, . or .. segment'
  use_config app .git/app
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "build.artefacts.app.path: \".git/app\" names the repository's own .git"
  use_config app .GIT/app
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "build.artefacts.app.path: \".GIT/app\" names the repository's own .git"
  # <path> <input>: the path is the input, lies in it, holds it, and is it in
  # another case.
  for spec in "src src" "src/out src" "crates crates/core" "SRC src"; do
    # shellcheck disable=SC2086 # the path and the input, split on purpose
    use_config app $spec
    run --separate-stderr devbin_run "$PROJ" cache key app
    assert_refused "build.artefacts.app.path: \"${spec%% *}\" overlaps the input path \"${spec#* }\""
  done
  # b's path lies in a's own input, which only a reads.
  printf '%s\n' 'project:' '  name: demo' 'build:' '  inputs:' '    - "src"' '  artefacts:' \
    '    a:' '      tool: cargo' '      path: "out/a"' '      inputs:' '        - "gen"' \
    '    b:' '      tool: cargo' '      path: "gen/b"' >"$PROJ/bin/.devbin/config.yaml"
  run --separate-stderr devbin_run "$PROJ" cache key b
  assert_refused 'build.artefacts.b.path: "gen/b" overlaps the input path "gen"'
  # A name the cache's own words would read as an option.
  for name in -x --help; do
    use_config "$name" out/x
    run --separate-stderr devbin_run "$PROJ" cache key app
    assert_refused "build.artefacts.$name: \"$name\" is no artefact name"
  done
  use_config app out/app ./src
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused 'build.inputs.0: "./src" has an empty, . or .. segment'
  use_config app out/app src ""
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused 'build.inputs.1: "" is empty'
  printf '%s\n' 'project:' '  name: demo' >"$PROJ/bin/.devbin/config.yaml"
  run --separate-stderr devbin_run "$PROJ" cache key app
  assert_refused "this project declares no build: block"
  use_config
  run --separate-stderr devbin_run "$PROJ" cache key nope
  assert_refused "build.artefacts declares no artefact 'nope'"
}

@test "each argument the cache cannot read is refused at 7 with its reason and then the usage, a count past the shell's integers among them, a commit it cannot read is refused too, -h or --help wherever it stands is the usage at 0, and a bare cache is the contract's usage error, 1 (WP16)" {
  local unheld spec
  refused_with_usage "get cannot read 'extra'" get app extra
  refused_with_usage "'frob' is not a cache verb" frob
  refused_with_usage "key needs an artefact" key
  refused_with_usage "--commit takes a full commit sha, and 'abc' is not one" key app --commit abc
  refused_with_usage "'many' is not one" gc --keep many
  refused_with_usage "'99999999999999999999' is not one" gc --keep 99999999999999999999
  refused_with_usage "'abc' is not a whole key" rm abc
  refused_with_usage "'bad/name' is not an artefact name" get bad/name
  refused_with_usage "'-x' is not an artefact name" get -x
  # A whole sha this repository holds no object for: hashed, never written.
  unheld="$(printf 'never committed\n' | git -C "$PROJ" hash-object --stdin)"
  run --separate-stderr devbin_run "$PROJ" cache key app --commit "$unheld"
  assert_refused "the commit ${unheld:0:12} cannot be read in this repository"
  for spec in "get --help" "list -h" "gc --keep 2 -h" "-h"; do
    # shellcheck disable=SC2086 # the arguments, split on purpose
    run --separate-stderr devbin_run "$PROJ" cache $spec
    assert_success
    [[ "$output" == "usage:"* ]] || fail "'cache $spec' did not print the usage:\n$output"
  done
  run devbin_run "$PROJ" cache
  assert_exit_code 1
  assert_output_contains "usage:"
}

# AT-5.2
@test "the project's build pulls on its second run: pulled app <key>, nothing built, and the first build's bytes (WP16, AC-5.2)" {
  local key built
  run devbin_run "$PROJ" build
  assert_success
  key="$(app_key)"
  assert_output_contains "absent app $key"
  assert_output_contains "put app $key"
  mv "$PROJ/out/app" "$DEVBIN_TEST_TMPDIR/first-app"
  built="$(builds)"
  run devbin_run "$PROJ" build
  assert_success
  assert_output "pulled app $key"
  [ "$(builds)" -eq "$built" ] || fail "the second build built:\n$(cat "$BUILD_LOG")"
  cmp -s "$DEVBIN_TEST_TMPDIR/first-app" "$PROJ/out/app" || fail "the pulled bytes are not the first build's"
}

# AT-5.2
@test "a directory artefact is recorded as a tar and pulled back whole, over whatever is at its path and at the path the declaration names now, each file's bytes and its recorded mode bits whatever the umask (WP16, AC-5.2)" {
  local key run_mode=775 data_mode=640
  use_config tree out/tree
  mkdir -p "$PROJ/out/tree/bin"
  printf 'run\n' >"$PROJ/out/tree/bin/run"
  printf 'data\n' >"$PROJ/out/tree/data"
  chmod "$run_mode" "$PROJ/out/tree/bin/run"
  chmod "$data_mode" "$PROJ/out/tree/data"
  run devbin_run "$PROJ" cache put tree
  assert_success
  key="$(devbin_run "$PROJ" cache key tree)"
  assert_output "put tree $key"
  assert_file_exists "$DEVBIN_CACHE_HOME/demo/tree/$key/artefact.tar"
  mv "$PROJ/out/tree" "$DEVBIN_TEST_TMPDIR/first-tree"
  # A umask that would strip the run file's group write bit from an extract
  # that applied it, so only a restore of the recorded bits keeps them.
  umask 022
  run devbin_run "$PROJ" cache get tree
  assert_success
  assert_output "pulled tree $key"
  diff -r "$DEVBIN_TEST_TMPDIR/first-tree" "$PROJ/out/tree" || fail "the pulled tree is not the recorded one"
  [ -n "$(find "$PROJ/out/tree/bin/run" -perm "$run_mode")" ] || fail "bin/run came back without its mode $run_mode: $(ls -l "$PROJ/out/tree/bin/run")"
  [ -n "$(find "$PROJ/out/tree/data" -perm "$data_mode")" ] || fail "data came back without its mode $data_mode: $(ls -l "$PROJ/out/tree/data")"
  printf 'stray\n' >"$PROJ/out/tree/stray"
  printf 'changed\n' >"$PROJ/out/tree/data"
  run devbin_run "$PROJ" cache get tree
  assert_success
  diff -r "$DEVBIN_TEST_TMPDIR/first-tree" "$PROJ/out/tree" || fail "a pull over a changed tree did not leave the recorded one"
  use_config tree out/renamed
  run devbin_run "$PROJ" cache get tree
  assert_success
  assert_output "pulled tree $key"
  diff -r "$DEVBIN_TEST_TMPDIR/first-tree" "$PROJ/out/renamed" || fail "the tree was not pulled at the path the declaration names now"
}

@test "doctor passes a build: block whose every input path HEAD holds, and fails one that names paths HEAD does not hold, naming each (WP16)" {
  local p
  local -a absent=(crates native)
  run devbin_run "$PROJ" doctor
  assert_success
  assert_output_line "ok    cache: every declared input path is held at HEAD"
  use_config app out/app src "${absent[@]}"
  run devbin_run "$PROJ" doctor
  assert_failure
  assert_output_line "FAIL  cache: ${#absent[@]} declared input path(s) not held at HEAD, so every key that reads one is refused and the build runs uncached"
  for p in "${absent[@]}"; do
    assert_output_contains "not at HEAD: $p"
  done
  refute_output_contains "not at HEAD: src"
}

# macos_config <path>... -- PROJ's config with the built-in macos enabled, its
# app at out/Demo.app built by macos.build, and a build: block holding one
# artefact per <path>, named a, b and on, each built by cargo from src.
macos_config() {
  local names=(a b c) i=0 p
  {
    printf '%s\n' 'project:' '  name: demo' 'commands:' '  macos:' '    enabled: true' \
      'macos:' '  app: out/Demo.app' '  build: ./mkapp' 'build:' '  inputs:' '    - "src"' '  artefacts:'
    for p in "$@"; do
      printf '    %s:\n      tool: cargo\n      path: "%s"\n' "${names[$i]}" "$p"
      i=$((i + 1))
    done
  } >"$PROJ/bin/.devbin/config.yaml"
}

@test "two build: artefacts whose path is macos.app's, in any case of its letters, are refused at config read, naming both, so the macOS stage never guesses which to pull (ST0011 WP-06)" {
  macos_config out/Demo.app OUT/demo.APP
  run --separate-stderr devbin_run "$PROJ" cache key a
  assert_refused "build.artefacts a, b each have macos.app's path, so the macOS stage takes none of them"
  macos_config out/Demo.app out/other
  run --separate-stderr devbin_run "$PROJ" cache key a
  assert_success
}

@test "doctor notes a macOS stage that builds its app uncached, naming macos.app, and passes one whose app is a build: artefact (ST0011 WP-06)" {
  macos_config out/other
  run devbin_run "$PROJ" doctor
  assert_output_line "note  macos: the stage builds its app uncached -- no build.artefacts entry has macos.app's path (out/Demo.app)"
  macos_config out/Demo.app
  run devbin_run "$PROJ" doctor
  assert_output_line "ok    macos: the stage pulls and puts its app as the cache's build.artefacts.a"
  refute_output_contains "the stage builds its app uncached"
}

# AT-5.2
@test "with an input dirty the project's build runs, put refuses, and the registry's entry under HEAD's key is left as it was (WP16, AC-5.2)" {
  local held built key sums
  run devbin_run "$PROJ" build
  assert_success
  held="$(entries)"
  built="$(builds)"
  key="$(app_key)"
  sums="$(cat "$DEVBIN_CACHE_HOME/demo/app/$key/SHA256SUMS")"
  printf 'edit\n' >>"$PROJ/src/a.rs"
  run devbin_run "$PROJ" build
  assert_success
  assert_output_contains "get exit 7"
  assert_output_contains "put exit 7"
  [ "$(builds)" -gt "$built" ] || fail "with an input dirty the build did not run"
  [ "$(entries)" -eq "$held" ] || fail "a put from a dirty tree recorded an entry: $(entries) where $held were"
  [ "$(cat "$DEVBIN_CACHE_HOME/demo/app/$key/SHA256SUMS")" = "$sums" ] || fail "a put from a dirty tree replaced the entry under HEAD's key"
}

@test "a put that cannot record the artefact refuses at 7 naming the root, and leaves no temporary entry under it (WP16)" {
  local e
  build_app
  make_unreadable "$PROJ/out/app"
  run --separate-stderr devbin_run "$PROJ" cache put app
  assert_refused "the artefact at out/app could not be recorded under the cache root $DEVBIN_CACHE_HOME"
  for e in "$DEVBIN_CACHE_HOME"/demo/app/.put.* "$DEVBIN_CACHE_HOME"/demo/app/*; do
    [ ! -e "$e" ] || fail "a put that failed left $e under the root"
  done
}

@test "a get that cannot write the artefact at its path refuses at 7, never answering absent (WP16)" {
  local key
  build_app
  devbin_run "$PROJ" cache put app >/dev/null
  key="$(app_key)"
  rm -r "$PROJ/out"
  printf 'a file where the directory goes\n' >"$PROJ/out"
  run --separate-stderr devbin_run "$PROJ" cache get app
  assert_refused "the entry for app $key could not be written to out/app"
}

@test "get refuses at 7 an artefact path the repository tracks files at, a file or a directory, in any case of its letters, with an entry under the key, and leaves what is there, uncommitted edits and all, as it was (WP16)" {
  local spec before tree
  mkdir -p "$PROJ/docs"
  printf 'guide\n' >"$PROJ/docs/guide.md"
  git -C "$PROJ" add docs
  git -C "$PROJ" commit -q -m docs
  # An entry under app's key, which reads src alone and not the path, so a get
  # the check let through would pull over what each path names.
  build_app
  devbin_run "$PROJ" cache put app >/dev/null
  printf 'an edit\n' >>"$PROJ/README"
  printf 'an edit\n' >>"$PROJ/docs/guide.md"
  before="$(cat "$PROJ/README" "$PROJ/docs/guide.md")"
  tree="$(git -C "$PROJ" status --porcelain -- README docs)"
  # <path>|<what the refusal names>
  for spec in "README|README," "readme|README," "docs|files under docs (docs/guide.md among them)" \
    "Docs|files under Docs (docs/guide.md among them)"; do
    use_config app "${spec%%|*}"
    run --separate-stderr devbin_run "$PROJ" cache get app
    assert_refused "the repository tracks ${spec#*|}"
  done
  [ "$(cat "$PROJ/README" "$PROJ/docs/guide.md")" = "$before" ] || fail "a refused get changed a tracked file"
  [ "$(git -C "$PROJ" status --porcelain -- README docs)" = "$tree" ] || fail "a refused get changed the tracked paths:\n$(git -C "$PROJ" status --porcelain -- README docs)"
}

@test "a file artefact's copy in the registry keeps no file flags, uchg or uappnd, its own or a link's target's, so rm removes the entry, and a directory artefact is recorded and pulled without its files' flags (WP16)" {
  local key spec src read_back
  build_app
  key="$(app_key)"
  # <flags>|<the file that carries them>: out/app itself, or out/real through
  # out/app as a link to it.
  for spec in "uchg|out/app" "uappnd|out/app" "uchg|out/real"; do
    src="$PROJ/${spec#*|}"
    if [ "${spec#*|}" = out/real ]; then
      cp "$PROJ/out/app" "$src"
      rm "$PROJ/out/app"
      ln -s real "$PROJ/out/app"
    fi
    set_flags "${spec%%|*}" "$src"
    run devbin_run "$PROJ" cache put app
    assert_success
    assert_output "put app $key"
    [ "$(file_flags "$DEVBIN_CACHE_HOME/demo/app/$key/artefact")" = 0 ] || fail "the registry's copy of $spec carries flags $(file_flags "$DEVBIN_CACHE_HOME/demo/app/$key/artefact")"
    run devbin_run "$PROJ" cache rm "$key"
    assert_success
    assert_output "removed app $key"
    chflags 0 "$src"
  done
  use_config tree out/tree
  mkdir -p "$PROJ/out/tree"
  printf 'data\n' >"$PROJ/out/tree/data"
  set_flags uchg "$PROJ/out/tree/data"
  run devbin_run "$PROJ" cache put tree
  assert_success
  key="$(devbin_run "$PROJ" cache key tree)"
  assert_output "put tree $key"
  # The recording itself, read back by a plain tar that restores whatever
  # flags it holds, so a pull that drops them cannot hide a tar that kept them.
  read_back="$DEVBIN_TEST_TMPDIR/read-back"
  mkdir -p "$read_back"
  tar -xpf "$DEVBIN_CACHE_HOME/demo/tree/$key/artefact.tar" -C "$read_back"
  [ "$(file_flags "$read_back/data")" = 0 ] || fail "the registry's tar records flags $(file_flags "$read_back/data") on data"
  # Pulled at another path, since what stands at out/tree holds the flag.
  use_config tree out/renamed
  run devbin_run "$PROJ" cache get tree
  assert_success
  assert_output "pulled tree $key"
  cmp -s "$PROJ/out/tree/data" "$PROJ/out/renamed/data" || fail "the pulled data is not the recorded file's bytes"
  [ "$(file_flags "$PROJ/out/renamed/data")" = 0 ] || fail "the pulled data carries flags $(file_flags "$PROJ/out/renamed/data")"
}

# AT-5.3
@test "an entry whose artefact does not match its SHA256SUMS is removed with a line, get answers absent, and the build runs and records it again (WP16, AC-5.3)" {
  local key entry built
  run devbin_run "$PROJ" build
  assert_success
  key="$(app_key)"
  entry="$DEVBIN_CACHE_HOME/demo/app/$key"
  printf 'tampered\n' >>"$entry/artefact"
  built="$(builds)"
  run devbin_run "$PROJ" build
  assert_success
  assert_output_contains "the entry for app $key did not verify against its SHA256SUMS and key, and is removed"
  assert_output_contains "absent app $key"
  assert_output_contains "put app $key"
  [ "$(builds)" -gt "$built" ] || fail "the build did not run on a tampered entry"
  cmp -s "$entry/artefact" "$PROJ/out/app" || fail "the entry was not recorded again from the new build"
}

# AT-5.3
@test "an entry whose manifest names another key is removed with a line and answered absent, though its SHA256SUMS checks (WP16, AC-5.3)" {
  local key other entry m
  build_app
  run devbin_run "$PROJ" cache put app
  assert_success
  key="$(app_key)"
  entry="$DEVBIN_CACHE_HOME/demo/app/$key"
  other="$(printf 'another\n' | sha256_text)"
  m="$(cat "$entry/manifest.yaml")"
  printf '%s\n' "${m/"key: $key"/"key: $other"}" >"$entry/manifest.yaml"
  (cd "$entry" && lib_say sha256_files artefact manifest.yaml >SHA256SUMS)
  run --separate-stderr devbin_run "$PROJ" cache get app
  assert_exit_code 1
  assert_output "absent app $key"
  [[ "$stderr" == *"the entry for app $key did not verify"* ]] || fail "no line names the removed entry: $stderr"
  assert_directory_not_exists "$entry"
}

# AT-5.4
@test "with DEVBIN_CACHE_HOME unset or empty the root is the XDG cache directory's devbin: doctor names it as the default, get misses before put makes it, and an empty value reads it too (WP16, AC-5.5)" {
  local root="$XDG_CACHE_HOME/devbin" key
  unset DEVBIN_CACHE_HOME
  run devbin_run "$PROJ" doctor
  assert_output_contains "cache: root $root (default), made at the first put"
  key="$(app_key)"
  run devbin_run "$PROJ" cache get app
  assert_exit_code 1
  assert_output "absent app $key"
  assert_directory_not_exists "$root"
  build_app
  run devbin_run "$PROJ" cache put app
  assert_success
  assert_output "put app $key"
  assert_directory_exists "$root/demo/app/$key"
  run devbin_run "$PROJ" doctor
  assert_output_contains "cache: root $root (default), writable"
  DEVBIN_CACHE_HOME="" run devbin_run "$PROJ" cache get app
  assert_success
  assert_output "pulled app $key"
}

# AT-5.4
@test "a cache root that is relative, a file, or a link to nothing, itself or above it, is refused by get and by put in one line naming it and why, before the toolchain is asked anything, doctor notes the link, and the project's build still exits 0 (WP16, AC-5.5)" {
  local dangling="$DEVBIN_TEST_TMPDIR/dangling"
  printf 'a file\n' >"$DEVBIN_TEST_TMPDIR/afile"
  ln -s "$DEVBIN_TEST_TMPDIR/nowhere" "$dangling"
  build_app
  # A toolchain that says a line on stderr when asked: the refusal stays the
  # one line only when the root is read before the key asks it.
  export CARGO_STUB_CHATTER=1
  unusable_root "rel/cache" "is not an absolute path"
  unusable_root "$DEVBIN_TEST_TMPDIR/afile" "is not a directory"
  unusable_root "$dangling" "cannot be made: $dangling is a link to nothing"
  unusable_root "$dangling/cache" "cannot be made: $dangling is a link to nothing"
  DEVBIN_CACHE_HOME="$dangling/cache" run devbin_run "$PROJ" doctor
  assert_output_contains "cache: the root $dangling/cache (declared) cannot be made: $dangling is a link to nothing, so every build runs and none is recorded"
}

# AT-5.4
@test "a cache root this user cannot write, or cannot make where it would go, is refused by get and by put in one line naming it, doctor notes it, and the project's build still exits 0 (WP16, AC-5.5)" {
  RO_ROOT="$DEVBIN_TEST_TMPDIR/ro"
  mkdir -p "$RO_ROOT"
  chmod a-w "$RO_ROOT"
  if [ -w "$RO_ROOT" ]; then
    [[ -z "${CI:-}" ]] || fail "this CI runner writes a directory without its write bits ($RO_ROOT), so the unwritable root cannot be built: run the job as a user that cannot"
    skip "running with permissions that write a read-only directory: the unwritable root was NOT checked"
  fi
  build_app
  unusable_root "$RO_ROOT" "is not writable by this user"
  unusable_root "$RO_ROOT/sub/cache" "cannot be made: $RO_ROOT is not writable by this user"
  DEVBIN_CACHE_HOME="$RO_ROOT/sub/cache" run devbin_run "$PROJ" doctor
  assert_output_contains "cache: the root $RO_ROOT/sub/cache (declared) cannot be made: $RO_ROOT is not writable by this user, so every build runs and none is recorded"
}

@test "gc keeps the newest CACHE_GC_KEEP entries per artefact, counting keys alone, a newer name holding a newline before a key's name neither counted nor removed, saying no release seal names a key, and --keep sets the count (WP16)" {
  local keep fewer odd
  keep="$(cache_const CACHE_GC_KEEP)"
  put_generations "$((keep + 1))"
  # Newer than every entry, and read as two names by a reader that splits on
  # newlines, the second the newest key's: counted, it would push one of the
  # newest real entries out.
  odd="$DEVBIN_CACHE_HOME/demo/app/x"$'\n'"${KEYS[-1]}"
  mkdir -p "$odd"
  touch -t 203001010000 "$odd"
  run devbin_run "$PROJ" cache gc
  assert_success
  assert_output_contains "no release seal names a key: keeping the newest $keep per artefact alone"
  assert_output_contains "removed app ${KEYS[0]}"
  assert_output_matches "freed [1-9][0-9]* bytes"
  assert_kept "$keep"
  assert_directory_exists "$odd"
  fewer=$((keep - 1))
  run devbin_run "$PROJ" cache gc --keep "$fewer"
  assert_success
  assert_kept "$fewer"
}

@test "gc keeps every key the newest release seal names in a cache line, the newest by its time as the run logs are read, and a key only an older seal names goes (WP16)" {
  local keep dir older newer
  keep="$(cache_const CACHE_GC_KEEP)"
  put_generations "$((keep + 2))"
  dir="$PROJ/$(lib_say gate_out_dir release)"
  mkdir -p "$dir"
  # Two runs in one minute: the second's name carries its seconds, and sorts
  # before the first's, so only its time says it is the newer.
  older="$dir/20260101-0001.RELEASE.out"
  newer="$dir/20260101-0001-07.RELEASE.out"
  lib_say note_line "$(printf 'cache\tapp\t%s' "${KEYS[0]}")" >"$older"
  lib_say note_line "$(printf 'cache\tapp\t%s' "${KEYS[1]}")" >"$newer"
  touch -t 202601010001 "$older"
  touch -t 202601010002 "$newer"
  run devbin_run "$PROJ" cache gc
  assert_success
  refute_output_contains "no release seal names a key"
  assert_output_contains "removed app ${KEYS[0]}"
  refute_output_contains "removed app ${KEYS[1]}"
  assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/${KEYS[1]}"
  [ "$(entries)" -eq "$((keep + 1))" ] || fail "gc left $(entries) entries, where the newest $keep and the sealed one make $((keep + 1))"
}

@test "gc refuses, removing nothing, when the newest release seal cannot be read, or the directory the release's runs are kept in cannot be listed, a link to nothing among them (WP16)" {
  local keep rel dir seal held
  keep="$(cache_const CACHE_GC_KEEP)"
  put_generations "$((keep + 1))"
  rel="$(lib_say gate_out_dir release)"
  dir="$PROJ/$rel"
  mkdir -p "$dir"
  seal="$dir/20260101-0001.RELEASE.out"
  lib_say note_line "$(printf 'cache\tapp\t%s' "${KEYS[0]}")" >"$seal"
  make_unreadable "$seal"
  held="$(entries)"
  run --separate-stderr devbin_run "$PROJ" cache gc
  assert_refused "${seal##*/} cannot be read"
  [ "$(entries)" -eq "$held" ] || fail "gc removed entries though it could not read the seal: $(entries) of $held left"
  # A link to nothing where the run logs are kept, as an unmounted volume
  # leaves one: read as no seal at all, gc would remove what the seal keeps.
  mv "$dir" "$DEVBIN_TEST_TMPDIR/release-logs"
  ln -s "$DEVBIN_TEST_TMPDIR/nowhere" "$dir"
  run --separate-stderr devbin_run "$PROJ" cache gc
  assert_refused "$rel cannot be read, so gc cannot say which keys the newest release seal keeps, and removes nothing"
  [ "$(entries)" -eq "$held" ] || fail "gc removed entries though the run logs were a link to nothing: $(entries) of $held left"
  rm "$dir"
  mv "$DEVBIN_TEST_TMPDIR/release-logs" "$dir"
  # Searchable but not listable: a glob there finds no seal at all.
  locked_dir "$dir"
  run --separate-stderr devbin_run "$PROJ" cache gc
  assert_refused "$rel cannot be read, so gc cannot say which keys the newest release seal keeps, and removes nothing"
  [ "$(entries)" -eq "$held" ] || fail "gc removed entries though it could not list the run logs: $(entries) of $held left"
}

@test "list, rm and gc refuse, removing nothing, a directory of the registry they cannot list, an artefact's or the project's, never reading it as empty (WP16)" {
  local keep held verb d
  keep="$(cache_const CACHE_GC_KEEP)"
  put_generations "$((keep + 1))"
  held="$(entries)"
  for d in "$DEVBIN_CACHE_HOME/demo/app" "$DEVBIN_CACHE_HOME/demo"; do
    locked_dir "$d"
    for verb in gc list "list app" "rm ${KEYS[0]}"; do
      # shellcheck disable=SC2086 # the verb and its argument, split on purpose
      run --separate-stderr devbin_run "$PROJ" cache $verb
      assert_refused "the registry's directory $d cannot be listed"
    done
    chmod u+rwx "$d"
    [ "$(entries)" -eq "$held" ] || fail "a verb removed entries though it could not list $d: $(entries) of $held left"
  done
}

@test "list names each entry as <artefact> <key>, rm removes the entries under a whole key, and rm refuses what is not one (WP16)" {
  local key
  build_app
  devbin_run "$PROJ" cache put app >/dev/null
  key="$(app_key)"
  run devbin_run "$PROJ" cache list
  assert_success
  assert_output "app $key"
  run devbin_run "$PROJ" cache list app
  assert_success
  assert_output "app $key"
  run --separate-stderr devbin_run "$PROJ" cache rm "${key:0:12}"
  assert_refused "is not a whole key"
  assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/$key"
  run devbin_run "$PROJ" cache rm "$key"
  assert_success
  assert_output "removed app $key"
  assert_directory_not_exists "$DEVBIN_CACHE_HOME/demo/app/$key"
}

@test "list, rm and gc refuse an empty project name, which would make the registry's root the project's directory, list and gc leave a name under an artefact that is not a key, and gc names a temporary entry a put left behind, removing none (WP16)" {
  local key verb tmp=.put.AbC123
  build_app
  devbin_run "$PROJ" cache put app >/dev/null
  key="$(app_key)"
  mkdir -p "$DEVBIN_CACHE_HOME/demo/app/not-a-key"
  # A put's temporary entry, named as mktemp names one, as a put killed before
  # its rename leaves it.
  mkdir -p "$DEVBIN_CACHE_HOME/demo/app/$tmp"
  run devbin_run "$PROJ" cache list
  assert_success
  assert_output "app $key"
  run devbin_run "$PROJ" cache gc --keep 0
  assert_success
  assert_output_contains "removed app $key"
  refute_output_contains "not-a-key"
  assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/not-a-key"
  assert_output_contains "left app $tmp: a temporary entry from a put that did not finish"
  assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/$tmp"
  # A name the dispatcher cannot make its root variable of never reaches the
  # cache; an empty one does.
  PROJECT_NAME='""' use_config
  for verb in list gc "rm $key"; do
    # shellcheck disable=SC2086 # the verb and its argument, split on purpose
    run --separate-stderr devbin_run "$PROJ" cache $verb
    assert_refused "project.name '' is not one directory name"
  done
  assert_directory_exists "$DEVBIN_CACHE_HOME/demo/app/not-a-key"
}
