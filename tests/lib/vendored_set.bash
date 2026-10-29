#!/usr/bin/env bash
# vendored_set.bash -- reading the vendored set the way its users see it.
#
# The tree scans that read every file vendored_paths lists share one lister and
# one rule for which lines a user is shown, so no scan can disagree with another
# about either: neutral.bats, for traces of where devbin was made or used, and
# installhints.bats, for install hints that name Homebrew alone. Each caller
# loads lib/helpers and lib/install first, for vendored_paths and
# vendor_source_path. vendored_scan and vendored_drop need neither, so
# documentation.bats's Homebrew arm reads its docs through vendored_scan too,
# and every scan and filter of what a user reads has one rule for reading it.

# vendored_set_files -- the source path of every file vendored_paths lists,
# one a line. A path it cannot place fails the listing rather than shortening it.
vendored_set_files() {
  local rels rel src
  rels="$(vendored_paths "$DEVBIN_HOME")" || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$(vendor_source_path "$DEVBIN_HOME" "$rel")" || return 1
    printf '%s\n' "$src"
  done <<<"$rels"
  return 0
}

# vendored_scan <out> <i|s> <pattern> <file>... -- append grep's matches to
# <out> as path:line:text, case-insensitive for `i`, which under C folds ASCII
# letters only. Status 2 when <out> cannot be written, when no file is given
# (grep would read stdin), or when grep could not read one, so a scan that saw
# nothing is never read as a clean tree: a redirection that fails exits 1,
# which is grep's "no match".
#
# `-a` under `LC_ALL=C`, ALWAYS, and vendored_drop reads the same way. Without
# `-a`, GNU grep answers a file holding a NUL, or under a UTF-8 locale an
# invalid byte, with "binary file matches" on stderr and NOTHING on stdout, so
# CI's Ubuntu grep would read such a file as clean while macOS's flagged it.
# And under a UTF-8 locale an invalid byte can keep a line from matching even
# with `-a`: BSD grep drops a matching line when the byte comes before the
# match, and either grep misses one whose pattern has to read the byte, so a
# scan run from a UTF-8 terminal could pass a line a run under C flags (issue
# 0205).
vendored_scan() {
  local out="$1" fold="$2" pat="$3" rc=0
  shift 3
  [ "$#" -gt 0 ] || return 2
  : >>"$out" || return 2
  if [ "$fold" = i ]; then
    LC_ALL=C grep -a -H -n -E -i -- "$pat" "$@" >>"$out" || rc=$?
  else
    LC_ALL=C grep -a -H -n -E -- "$pat" "$@" >>"$out" || rc=$?
  fi
  [ "$rc" -le 1 ] || return 2
  return 0
}

# vendored_drop <out> <pattern> <in> -- append to <out> every line of <in> that
# does not match <pattern>, an ERE, read as vendored_scan reads: `-a` under C.
# The filters over a scan's hits go through it, so no filter reads a hit
# another way than the scan that found it. Status 2 when <in> cannot be read or
# <out> written.
vendored_drop() {
  local out="$1" pat="$2" in="$3"
  : >>"$out" || return 2
  LC_ALL=C grep -a -v -E -- "$pat" "$in" >>"$out" || [ "$?" -eq 1 ] || return 2
  return 0
}

# vendored_shown <out> <pattern> <file>... -- append, as path:line:text, every
# line a user reads that matches <pattern>, an ERE: every line of a .md, a
# .yaml or a file under tmpl/, and every line of any other file that is not a
# comment. vendored_scan finds the candidates, as every arm here does -- `-a`
# under C, so neither a NUL nor an invalid byte hides a line, and ERE
# intervals, which mawk misreads inside an alternation -- and vendored_drop
# drops a code file's comment lines. Status 2 when anything could not read, or
# when no file is given.
vendored_shown() {
  local out="$1" pat="$2" f code="$1.code"
  local -a whole=() rest=()
  shift 2
  [ "$#" -gt 0 ] || return 2
  for f in "$@"; do
    case "$f" in
      *.md | *.yaml | */tmpl/*) whole+=("$f") ;;
      *) rest+=("$f") ;;
    esac
  done
  if [ "${#whole[@]}" -gt 0 ]; then
    vendored_scan "$out" s "$pat" "${whole[@]}" || return 2
  fi
  if [ "${#rest[@]}" -gt 0 ]; then
    : >"$code" || return 2
    vendored_scan "$code" s "$pat" "${rest[@]}" || return 2
    # grep -v of a code file's comment lines, NOT awk: BSD awk ends a line at a
    # NUL, so the text after one would be lost from the hit it belongs to.
    vendored_drop "$out" '^[^:]*:[0-9]+:[[:space:]]*#' "$code" || return 2
  fi
  return 0
}
