#!/usr/bin/env bats
# vendoredmd.bats - the vendored half ships no prettier-unstable Markdown
# (issue 0008's close condition).
#
# A consumer's pre-commit prettier hook rewrote lib/tmpl/help.md INSIDE the
# install commit, and doctor failed the manifest one command later: a
# project's formatting hook runs on the install commit, and the vendored half
# is in its blast radius. The stable form is unwrapped prose -- one line per
# paragraph -- because it is byte-stable under BOTH proseWrap modes: preserve
# never splits a single-line paragraph, and `never` has nothing to join.
#
# The invariant is checked structurally, with no dependency on prettier being
# installed: a paragraph spanning two adjacent prose lines is exactly the
# shape proseWrap rewrites. Literal blocks (4-space), headings, tables, list
# items and blockquotes are not paragraphs and may stack freely.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# Prints "<line>: <text>" for every second line of a hard-wrapped paragraph:
# two consecutive lines that are both prose.
wrapped_paragraph_lines() {
  awk '
    function is_prose(l) {
      if (l == "") return 0
      if (l ~ /^#/) return 0
      if (l ~ /^    /) return 0
      if (l ~ /^\|/) return 0
      if (l ~ /^[-*] /) return 0
      if (l ~ /^[0-9]+\. /) return 0
      if (l ~ /^> /) return 0
      return 1
    }
    # Fenced code blocks are byte-stable under prettier: the fence lines and
    # everything between them are not paragraphs.
    /^```/ { infence = !infence; prev = ""; next }
    infence { next }
    { if (is_prose(prev) && is_prose($0)) print NR ": " $0; prev = $0 }
  ' "$1"
}

@test "every vendored markdown file is prettier-stable: no hard-wrapped paragraphs" {
  local found=0 f out
  while IFS= read -r f; do
    found=1
    out="$(wrapped_paragraph_lines "$f")"
    if [ -n "$out" ]; then
      echo "hard-wrapped paragraph(s) in $f -- a project's prettier hook would rewrite this inside the install commit (issue 0008):"
      echo "$out"
      return 1
    fi
  done < <(find "$DEVBIN_LIB_DIR" -name '*.md' | sort)
  # Fail loudly if the sweep one day matches nothing: a check that silently
  # examined no files is a false green, not a pass.
  [ "$found" -eq 1 ]
}

@test "the wrap detector detects a wrap (its own red check)" {
  local f="$DEVBIN_TEST_TMPDIR/wrapped.md"
  printf '# t\n\nThis paragraph was hand-wrapped\nacross two lines.\n' >"$f"
  [ -n "$(wrapped_paragraph_lines "$f")" ]
  printf '# t\n\nOne line per paragraph.\n\n    a literal\n    block\n\n- a list\n- stacks\n' >"$f"
  [ -z "$(wrapped_paragraph_lines "$f")" ]
}

# _prettier_diff <file> -- what prettier's default config would change in
# <file>. --check names a file and not what is wrong with it.
_prettier_diff() {
  local formatted
  formatted="$(prettier --no-config --ignore-path /dev/null "$1" 2>&1)" || {
    printf 'prettier could not format it: %s\n' "$formatted"
    return 0
  }
  diff "$1" <(printf '%s\n' "$formatted") || [ $? -eq 1 ]
}

@test "every vendored markdown file is prettier-stable under the default config (0113)" {
  # NOT ON CI, BY RULE: CI does not install prettier. There this arm skips and
  # says so, and on a machine without prettier it skips as any arm needing an
  # absent tool does; either way the skip names what was not checked.
  require_command prettier "prettier is not installed -- the vendored markdown was NOT checked against prettier" \
    "CI does not install prettier"
  local f n=0 unstable="" version probe="$DEVBIN_TEST_TMPDIR/unstable.md"
  # A green holds for the prettier that ran, and a consumer's guard may run
  # another, so the run records which.
  version="$(prettier --version)" || fail "prettier --version failed"
  echo "# checked with prettier $version" >&3
  # The wrap arm above holds proseWrap, with no prettier needed. This holds the
  # rest of what prettier's default normalises -- emphasis and list markers,
  # escapes, table padding -- which is what a consumer's staged-format guard
  # runs on a sweep commit: Intent declares markdown to it, and nearly every
  # devbin page once failed it (issue 0113).
  #
  # WHAT THESE ARMS COVER, AND WHAT THEY DO NOT. One line per paragraph plus
  # the default config is stable under proseWrap preserve and never, and no
  # layout is stable under `always` as well, which re-wraps a long line. The
  # population, read from the prettier config of every project that vendors
  # devbin: `never` at some, every one of which also fences .devbin in
  # .prettierignore; the default, preserve, at Intent and at every project with
  # no config; `always` nowhere. A consumer on `always` is therefore a NEW
  # case, not one these arms already cover.
  #
  # POSITIVE CONTROL: the exact invocation below goes red on a file prettier
  # rewrites, so a clean run means each file was checked and passed, not that
  # the invocation cannot fail.
  printf '# t\n\n*emphasis* prettier rewrites\n' >"$probe"
  ! prettier --no-config --ignore-path /dev/null --check "$probe" >/dev/null 2>&1 ||
    fail "prettier $version passed a file it rewrites -- the check below could not go red"
  while IFS= read -r f; do
    n=$((n + 1))
    prettier --no-config --ignore-path /dev/null --check "$f" >/dev/null 2>&1 ||
      unstable="$unstable\n${f#"$DEVBIN_LIB_DIR"/}:\n$(_prettier_diff "$f")"
  done < <(find "$DEVBIN_LIB_DIR" -name '*.md' | sort)
  # THE DENOMINATOR: every vendored .md, one prettier run each, with no ignore
  # file in play (--ignore-path /dev/null replaces both .gitignore and
  # .prettierignore), so no ignore line can let this pass having checked
  # nothing. Its referent is the pages devbin ships and lib/tmpl/help.md, every
  # one of which the find above lists.
  local -a shipped=("$DEVBIN_LIB_DIR"/pages/*.md "$DEVBIN_LIB_DIR/tmpl/help.md")
  [ "$n" -ge "${#shipped[@]}" ] || fail "prettier $version checked $n vendored markdown files -- fewer than the ${#shipped[@]} pages and template devbin ships"
  [ -z "$unstable" ] || fail "not stable under prettier $version, so a consumer's staged-format guard refuses the sweep commit:$unstable"
}
