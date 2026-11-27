#!/usr/bin/env bats
# howto.bats - the built-in howto: instructions written for an LLM, listed,
# searched and printed from two sources, devbin's own topics in the vendored
# library and the project's own under bin/.devbin/howto.
#
# Each arm stands in a fixture project with devbin installed. Its core topics
# are the ones devbin ships, plus any an arm writes into the fixture's own
# vendored library, so an arm can hold a core topic it controls. Project topics
# are written where the project keeps its own, under bin/.devbin/howto.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - the words of the topics devbin ships: only their headers are read here,
#     through the list, and the scans read their text;
#   - a topic folder whose name holds a space or a glob character: the arms use
#     plain names only;
#   - an answer on a terminal: the arms run with no tty, and the verb has no
#     colour code to switch on there.

load "../lib/test_helper"

setup() {
  devbin_setup
  PROJ="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  CORE="$PROJ/bin/.devbin/lib/howto"
}

teardown() {
  devbin_teardown
}

# topic <dir> <name> <summary> <keywords> <body line> -- a topic with a good
# header, its body one line.
topic() {
  mkdir -p "$1/$2"
  printf -- '---\nsummary: %s\nkeywords: %s\n---\n\n%s\n' "$3" "$4" "$5" >"$1/$2/index.md"
}

# runtime_version -- the devbin version the fixture runs, asked of the one
# reader the verb asks.
runtime_version() {
  # shellcheck disable=SC1091
  (. "$DEVBIN_LIB_DIR/helpers" && . "$DEVBIN_LIB_DIR/install" && devbin_version_of "$PROJ")
}

@test "with no word, howto lists every topic of both sources with its source and summary, and prints no topic" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy the demo service." "[deploy, ship]" "BODY-DEPLOY"
  local d name
  run devbin_run "$PROJ" howto
  assert_success
  assert_output_matches "deploy +\(project\)"
  assert_output_contains "Deploy the demo service."
  refute_output_contains "BODY-DEPLOY"
  # Every core topic the fixture vendors is listed, read from the folder.
  for d in "$CORE"/*/; do
    name="${d%/}"
    name="${name##*/}"
    assert_output_contains "$name"
  done
  [ -n "${name:-}" ] || fail "the fixture vendors no core topic, so this arm has no population"
}

@test "an exact project name prints the topic under a first line naming its source and path, without its header" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy the demo service." "[deploy]" "BODY-DEPLOY"
  run devbin_run "$PROJ" howto deploy
  assert_success
  [ "${lines[0]}" = "howto deploy: project (bin/.devbin/howto/deploy/index.md)" ] || fail "first line: ${lines[0]}"
  assert_output_contains "BODY-DEPLOY"
  refute_output_contains "summary:"
  refute_output_contains "keywords:"
}

@test "an exact core name prints the topic under a first line naming core, the devbin version and its path" {
  topic "$CORE" corething "A core topic." "[core]" "BODY-CORE"
  local v
  v="$(runtime_version)"
  [ -n "$v" ] || fail "the fixture's devbin version could not be read"
  run devbin_run "$PROJ" howto corething
  assert_success
  [ "${lines[0]}" = "howto corething: core, devbin $v (bin/.devbin/lib/howto/corething/index.md)" ] || fail "first line: ${lines[0]}"
  assert_output_contains "BODY-CORE"
}

@test "a glob lists the topics whose name, summary or a keyword match, in any case, and never prints a topic" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy the demo service." "[ship]" "BODY-DEPLOY"
  topic "$PROJ/bin/.devbin/howto" cutrel "Cut a Release of the demo." "[tag]" "BODY-CUT"
  topic "$PROJ/bin/.devbin/howto" notes "Write notes." "[Changelog, words]" "BODY-NOTES"
  # By name.
  run devbin_run "$PROJ" howto 'DEP*'
  assert_success
  assert_output_contains "deploy"
  refute_output_contains "cutrel"
  refute_output_contains "BODY-"
  # By summary.
  run devbin_run "$PROJ" howto '*release*'
  assert_success
  assert_output_contains "cutrel"
  refute_output_contains "deploy"
  refute_output_contains "BODY-"
  # By keyword.
  run devbin_run "$PROJ" howto 'change?og'
  assert_success
  assert_output_contains "notes"
  refute_output_contains "cutrel"
  refute_output_contains "BODY-"
}

@test "a word that names no topic lists every nearest name, ties included, and exits 1; a glob that matches none exits 1" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy." "[a]" "BODY"
  topic "$PROJ/bin/.devbin/howto" deplay "Deplay." "[a]" "BODY"
  topic "$PROJ/bin/.devbin/howto" zzzzzzzzzz "Far." "[a]" "BODY"
  run devbin_run "$PROJ" howto deplxy
  assert_failure
  assert_output_contains "no topic named 'deplxy'"
  assert_output_contains "deplay, deploy"
  refute_output_contains "zzzzzzzzzz"
  refute_output_contains "BODY"
  run devbin_run "$PROJ" howto 'qq*'
  assert_failure
  assert_output_contains "match 'qq*'"
}

@test "a project topic overrides a core one: both are listed, the core marked, and --core prints the core copy" {
  topic "$CORE" shared "Core summary." "[a]" "BODY-CORE"
  topic "$PROJ/bin/.devbin/howto" shared "Project summary." "[a]" "BODY-PROJECT"
  run devbin_run "$PROJ" howto
  assert_success
  assert_output_matches "shared +\(project\)"
  assert_output_contains "(core, overridden)"
  run devbin_run "$PROJ" howto shared
  assert_success
  assert_output_contains "BODY-PROJECT"
  refute_output_contains "BODY-CORE"
  run devbin_run "$PROJ" howto shared --core
  assert_success
  assert_output_contains "BODY-CORE"
  refute_output_contains "BODY-PROJECT"
  [[ "${lines[0]}" == "howto shared: core, devbin "* ]] || fail "first line: ${lines[0]}"
  # And --core lists the core topics alone.
  topic "$PROJ/bin/.devbin/howto" projonly "Project only." "[a]" "BODY"
  run devbin_run "$PROJ" howto --core
  assert_success
  refute_output_contains "projonly"
}

@test "forllms is core-only: a project copy is listed as ignored and never printed" {
  [ -f "$CORE/forllms/index.md" ] || fail "the fixture vendors no core forllms"
  topic "$PROJ/bin/.devbin/howto" forllms "A project forllms." "[a]" "BODY-PROJECT-FORLLMS"
  run devbin_run "$PROJ" howto
  assert_success
  assert_output_contains "(project, ignored: forllms is core-only)"
  run devbin_run "$PROJ" howto forllms
  assert_success
  [[ "${lines[0]}" == "howto forllms: core, devbin "* ]] || fail "first line: ${lines[0]}"
  refute_output_contains "BODY-PROJECT-FORLLMS"
}

@test "a malformed header is refused at exit 1, naming the file and what is wrong, and the list names it beside the rest" {
  local d="$PROJ/bin/.devbin/howto" case_="" name body want
  topic "$d" good "A good topic." "[a]" "BODY-GOOD"
  while IFS='|' read -r name want; do
    [ -n "$name" ] || continue
    case "$name" in
      noopen) body=$'summary: x\nkeywords: [a]\n---\nBODY' ;;
      nosummary) body=$'---\nkeywords: [a]\n---\nBODY' ;;
      notalist) body=$'---\nsummary: x\nkeywords: a, b\n---\nBODY' ;;
      unknownkey) body=$'---\nsummary: x\nkeywords: [a]\nowner: me\n---\nBODY' ;;
      noclose) body=$'---\nsummary: x\nkeywords: [a]' ;;
    esac
    mkdir -p "$d/$name"
    printf '%s\n' "$body" >"$d/$name/index.md"
    run devbin_run "$PROJ" howto "$name"
    [ "$status" -eq 1 ] || fail "$name: exit $status, want 1"
    assert_output_contains "bin/.devbin/howto/$name/index.md"
    assert_output_contains "$want"
    refute_output_contains "BODY"
    case_="$case_ $name"
  done <<'CASES'
noopen|no opening ---
nosummary|has no summary
notalist|not a list
unknownkey|names owner
noclose|no closing ---
CASES
  run devbin_run "$PROJ" howto
  [ "$status" -eq 1 ] || fail "the list over malformed headers: exit $status, want 1"
  assert_output_matches "good +\(project\)"
  for name in $case_; do
    assert_output_contains "bin/.devbin/howto/$name/index.md"
  done
}

@test "no answer carries an escape byte, with colour asked for by the environment" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy." "[a]" "BODY"
  local args out
  for args in "" "deploy" "*dep*" "nosuch" "--help"; do
    # shellcheck disable=SC2086
    out="$(cd "$PROJ" && TERM=xterm-256color CLICOLOR_FORCE=1 ./bin/devbin howto $args 2>&1 </dev/null)" || true
    [ -n "$out" ] || fail "howto $args printed nothing, so the escape check read nothing"
    ! grep -q $'\033' <<<"$out" || fail "howto $args printed an escape byte"
  done
}

@test "-h exits 0 with the usage, a second word and an unknown option are refused at exit 1" {
  run devbin_run "$PROJ" howto -h
  assert_success
  assert_output_contains "usage: bin/devbin howto"
  run devbin_run "$PROJ" howto one two
  [ "$status" -eq 1 ] || fail "a second word: exit $status, want 1"
  assert_output_contains "was given 'one' and 'two'"
  run devbin_run "$PROJ" howto --bogus
  [ "$status" -eq 1 ] || fail "an unknown option: exit $status, want 1"
  assert_output_contains "unknown option '--bogus'"
}

@test "a re-install over the project leaves its own topics as they are, as it leaves cmd/ and help/" {
  topic "$PROJ/bin/.devbin/howto" deploy "Deploy the demo service." "[a]" "BODY-KEPT"
  cp "$PROJ/bin/.devbin/howto/deploy/index.md" "$BATS_TEST_TMPDIR/before.md"
  run "$DEVBIN_BIN_DIR/devbin" install --into "$PROJ" --force
  assert_success
  cmp -s "$BATS_TEST_TMPDIR/before.md" "$PROJ/bin/.devbin/howto/deploy/index.md" || fail "the re-install changed the project's topic"
  run devbin_run "$PROJ" howto deploy
  assert_success
  assert_output_contains "BODY-KEPT"
}

@test "a project with no bin/.devbin/howto has no project topics, and the list and a core topic still answer" {
  [ ! -e "$PROJ/bin/.devbin/howto" ] || fail "the fixture already has a bin/.devbin/howto, so this arm reads nothing"
  run devbin_run "$PROJ" howto
  assert_success
  assert_output_contains "forllms"
  refute_output_contains "(project"
  run devbin_run "$PROJ" howto forllms
  assert_success
}

@test "a keywords list that Prettier wrapped over indented lines is read, and one left unclosed is refused" {
  local d="$PROJ/bin/.devbin/howto"
  mkdir -p "$d/wrapped" "$d/unclosed"
  printf -- '---\nsummary: A wrapped topic.\nkeywords:\n  [\n    alpha,\n    beta gamma,\n  ]\n---\n\nBODY-WRAPPED\n' >"$d/wrapped/index.md"
  run devbin_run "$PROJ" howto '*gamma*'
  assert_success
  assert_output_contains "wrapped"
  refute_output_contains "BODY-WRAPPED"
  run devbin_run "$PROJ" howto wrapped
  assert_success
  assert_output_contains "BODY-WRAPPED"
  printf -- '---\nsummary: An unclosed topic.\nkeywords:\n  [\n    alpha,\n---\n\nBODY-UNCLOSED\n' >"$d/unclosed/index.md"
  run devbin_run "$PROJ" howto unclosed
  [ "$status" -eq 1 ] || fail "an unclosed wrapped list: exit $status, want 1"
  assert_output_contains "bin/.devbin/howto/unclosed/index.md: its keywords list has no closing ]"
  refute_output_contains "BODY-UNCLOSED"
}
