#!/usr/bin/env bats
# installhints.bats - an install hint names Linux beside Homebrew (ST0008)
#
# devbin runs on Linux, and under WSL 2 on Windows, as well as on macOS, so a
# hint that names Homebrew alone tells a Linux developer nothing they can run.
# Every hint in the vendored set -- exactly the files vendored_paths lists --
# that names `brew install` also names, on the same line, a way to install the
# tool on Linux that puts it on PATH. ONLY THE SPELLINGS DECLARED HERE are
# accepted, so any other reads red until it is declared:
#   - `apt-get install <tool>`, bats-lanes' spelling (`brew install parallel,
#     or apt-get install parallel`), for a tool Ubuntu's archive carries;
#   - `swift.org/install`, the Swift toolchain, on a swift-format hint alone:
#     no Ubuntu package puts swift-format on PATH (24.04 carries none, and
#     26.04's swiftlang installs it under /usr/libexec/swift/bin).
# One line serves every platform; there is no platform branch.
#
# The arm proves on every run that it can go red, as neutral.bats's arms do:
# a planted file it must flag line by line, an innocent one it must pass, and
# only then the tree.
#
# WHAT THIS DOES NOT READ, declared so a green is never read as covering it:
#   - a hint split across two lines, which no line-oriented arm can see;
#   - a comment line in a code file, which no user is shown (a .md page, a
#     .yaml and a file under tmpl/ are read whole, by vendored_shown's rule);
#   - whether the Linux route it names is right: the apt route must name the
#     same tool as the Homebrew one, but that Ubuntu's package exists under
#     that name and puts the tool on PATH is review's, not this arm's;
#   - a Homebrew hint that does not say `brew install`, such as `brew upgrade`.

load "../lib/test_helper"
load "../lib/vendored_set"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
}

teardown() { devbin_teardown; }

# A Homebrew install hint, and the Linux routes that may stand beside it.
# At a word's start: "a Homebrew install under HOMEBREW_PREFIX" is prose, not a
# hint. The apt route names the SAME tool, by back-reference, so a line that
# pairs `brew install jq` with `apt-get install bash` is still Homebrew alone.
_HINT_BREW='(^|[^A-Za-z0-9_])brew install [A-Za-z0-9]'
_HINT_APT='brew install ([A-Za-z0-9][A-Za-z0-9.+-]*).*apt-get install \1([^A-Za-z0-9.+-]|$)'
_HINT_SWIFT='brew install swift-format.*swift\.org/install'

# _hint_hits <out> <file>... -- write to <out>, as path:line:text, every line
# a user is shown (vendored_shown's rule) that names `brew install` and no
# accepted Linux route. Status 2 when anything could not read, so a scan that
# saw nothing is never read as clean. Each filter goes through a file, never a
# pipe: under pipefail a later grep's 1 on empty input would stand in for an
# earlier one's 2. Each is vendored_drop, which reads a hit as the scan that
# found it does (issue 0205), and appends, so each file starts empty.
_hint_hits() {
  local out="$1" cand="$1.cand" kept="$1.kept"
  shift
  : >"$cand" || return 2
  : >"$kept" || return 2
  : >"$out" || return 2
  vendored_shown "$cand" "$_HINT_BREW" "$@" || return 2
  vendored_drop "$kept" "$_HINT_APT" "$cand" || return 2
  vendored_drop "$out" "$_HINT_SWIFT" "$kept" || return 2
  return 0
}

# AT-2.2
@test "every install hint in the vendored set that names Homebrew also names a Linux route that puts the tool on PATH" {
  local pos="$DEVBIN_TEST_TMPDIR/hints.pos" page="$DEVBIN_TEST_TMPDIR/hints.pos.md"
  local neg="$DEVBIN_TEST_TMPDIR/hints.neg" out="$DEVBIN_TEST_TMPDIR/hints.out"
  local files n want
  local -a vf
  # POSITIVE CONTROL, every planted line: Homebrew alone, a third spelling,
  # apt naming another tool, the swift.org route on a hint that is not
  # swift-format's, and a page's line that opens with `#`, which a page shows.
  printf '%s\n' \
    'require_tool jq "brew install jq"' \
    'die "jq not found (brew install jq, or apt install jq)"' \
    'die "jq not found (brew install jq, or apt-get install bash)"' \
    'die "jq not found (brew install jq; on Linux see swift.org/install)"' >"$pos"
  printf '%s\n' '# brew install jq' >"$page"
  _hint_hits "$out" "$pos" "$page" || fail "the scan could not read its control"
  n="$(awk 'END { print NR }' "$out")"
  want="$(awk 'END { print NR }' "$pos" "$page")"
  [ "$want" -gt 0 ] || fail "nothing planted -- the control would compare nothing"
  [ "$n" -eq "$want" ] || fail "the scan flagged $n of the $want planted lines:
$(cat "$out")"
  # NEGATIVE CONTROL: the accepted spellings, prose naming Homebrew, and a
  # comment, which no user is shown.
  printf '%s\n' \
    'require_tool jq "brew install jq, or apt-get install jq"' \
    'die "swift-format not found (brew install swift-format; on Linux it ships with the Swift toolchain, swift.org/install)"' \
    'warn "no devbin install (or a Homebrew install under HOMEBREW_PREFIX)"' \
    '  # brew install bash' >"$neg"
  _hint_hits "$out" "$neg" || fail "the scan could not read its control"
  [ ! -s "$out" ] || fail "the scan flags an innocent line:
$(cat "$out")"
  # THE TREE.
  files="$(vendored_set_files)" || fail "the vendored set could not be listed"
  mapfile -t vf <<<"$files"
  [ -n "$files" ] || fail "the vendored set is empty -- the scan would read nothing"
  _hint_hits "$out" "${vf[@]}" || fail "the scan could not read the vendored set"
  [ ! -s "$out" ] || fail "a hint in the vendored runtime names Homebrew and no Linux route that puts the tool on PATH:
$(sed "s|^$DEVBIN_HOME/||" "$out")"
}
