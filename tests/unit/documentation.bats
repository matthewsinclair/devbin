#!/usr/bin/env bats
# documentation.bats - the documentation cannot drift from the thing it documents (WP-12)
#
# Prose rots differently from code: nothing fails when it goes stale, so it goes
# stale quietly and is then believed. Every test here ties a document to a
# machine-readable source that the suite already trusts.
#
#   docs/configuration.md   <- the schema in lib/config
#   config.reference.yaml   <- the schema in lib/config, and the validator
#   README.md               <- the built-in catalogue
#   every relative link     <- the filesystem
#
# The schema is a case statement rather than a list, so the configuration
# document and the reference config need it EXTRACTED. That is the fragile part,
# and a broken extractor would return an empty set and let every test over it
# pass having checked nothing -- the exact false green this project treats as
# the cardinal sin. So the extractor has a test of its own, held to a referent,
# and it runs first.

load "../lib/test_helper"
load "../lib/vendored_set"

setup() {
  devbin_setup
}

teardown() {
  devbin_teardown
}

# schema_keys -- every key name the config validator accepts, one per line.
#
# Read out of `_cfg_path_known` in lib/config, which is the ONE place the schema
# is stated. Every shape that appears in that function is read here:
#
#   project)                                    a top-level branch label
#   case "${p[1]}" in name | alias) return 0    an alternation of leaf keys
#   [ "${p[1]}" = languages ]                   an equality test on one key
#
# Scoped to that function's body so an unrelated case statement elsewhere in the
# file cannot contribute a key that is not part of the schema.
schema_keys() {
  {
  awk '
    /^_cfg_path_known\(\)/ { inf = 1 }
    inf && /^}/            { inf = 0 }
    !inf                   { next }

    /^    [a-z_]+\)$/ {
      t = $0; sub(/^ +/, "", t); sub(/\)$/, "", t); print t; next
    }

    /case "\$\{p\[[0-9]\]\}" in .*\) return 0/ {
      t = $0; sub(/^.* in /, "", t); sub(/\).*$/, "", t)
      n = split(t, a, /\|/)
      for (i = 1; i <= n; i++) { gsub(/ /, "", a[i]); if (a[i] != "") print a[i] }
      next
    }

    {
      s = $0
      while (match(s, /\$\{p\[[0-9]\]\}" = [a-z_]+/)) {
        t = substr(s, RSTART, RLENGTH); sub(/^.* = /, "", t); print t
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$DEVBIN_LIB_DIR/config"
  # The release:, macos: and formula: keys are TABLES, _DEVBIN_RELEASE_SCHEMA,
  # _DEVBIN_MACOS_SCHEMA (issue 0226) and _DEVBIN_FORMULA_SCHEMA (issue 0227),
  # which their branches of _cfg_path_known
  # read rather than restating, so every segment of every key in each is a
  # schema key too.
  awk '
    /^_DEVBIN_(RELEASE|MACOS|FORMULA)_SCHEMA="/ { inr = 1; next }
    inr && /^"/                 { inr = 0 }
    inr && NF >= 2              { n = split($2, a, "."); for (i = 1; i <= n; i++) print a[i] }
  ' "$DEVBIN_LIB_DIR/config"
  } | LC_ALL=C sort -u
}

# documented_keys -- every key SEGMENT docs/configuration.md actually documents,
# read from the backticked dotted paths in its table rows and its section
# headings, one per line.
#
# Not a bare grep for the key name. The first version of this test did that and
# stayed GREEN when `options.<name>.flag` was renamed out of the page, because
# the word "flag" still occurred in the surrounding prose -- it was asserting
# that the page mentions a word, which any page about config inevitably does.
# Reading the documented PATHS is what makes the assertion mean what it says.
documented_keys() {
  {
    grep -oE '^\| `[a-z_]+(\.[a-z_<>]+)*`' "$DEVBIN_HOME/docs/configuration.md" || true
    grep -oE '^## `[a-z_]+`' "$DEVBIN_HOME/docs/configuration.md" || true
  } | tr -d '|#` ' | tr '.' '\n' | grep -vE '^<|^$' | LC_ALL=C sort -u
}

# documented_paths -- every dotted path a table row of docs/configuration.md
# documents, its placeholders kept, one per line. The page's paths are held to
# the validator by "the configuration reference names no key the schema
# rejects", and the schema key extractor is held to them.
documented_paths() {
  grep -oE '^\| `[a-z_]+(\.[a-z_<>]+)+`' "$DEVBIN_HOME/docs/configuration.md" | tr -d '|` '
}

# reference_comment_keys [file] -- every key the annotated reference config
# documents only in a comment, as the dotted path its nesting gives it, with the
# line it is on: `<path><TAB><line>`, one per line. Leaves only: a commented key
# with keys commented beneath it, as `ci:` has `query:` and `wait:`, is named by
# their paths, because only a leaf is a schema path. A parent is one where it
# stands, so the same path written elsewhere as a leaf is read there.
#
# A KEY IN A COMMENT NESTS WHERE UNCOMMENTING IT WOULD PUT IT. Dropping the `# `
# from `  # remotes:` leaves `  remotes:` under the live `release:`, and keys
# commented out with it nest beneath it by their own indent, as `  #   query:`
# does under `  # ci:`. A run of commented keys that opens further right than
# that, as the example in the `iex` option's comment opens with `#   options:`,
# is an EXAMPLE, and is read from its own first line as the top of a config.
#
# PROSE CAN OPEN A LINE WITH A WORD AND A COLON, and lines of the
# reference do, so a key-shaped line is a key only in a run of keys and list
# items set apart from prose by a blank line, a bare `#` or a live line. One
# with prose directly above and below it is a line of that prose. Each of these
# is printed as `?<key>`, which the check refuses rather than leaving unread:
# one at the edge of a paragraph of prose, which could be either; one indented
# past any key it could nest under, which has no path; and, outside prose, one
# spelled as no key in the schema is -- a capital, a hyphen, or no space after
# the `#` -- which is a key written wrong.
#
# DECLARED LIMIT: a key commented out with prose directly above AND below it is
# read as prose, so nothing here holds it to the schema. Every commented key in
# the reference is set apart from prose.
#
# awk's status is this function's, deliberately, with no `return 0` after it:
# an extraction that failed must fail the arm, not read as no keys.
reference_comment_keys() {
  awk '
    # Each line is B (blank, or a bare #), L (live), K (a key in a comment),
    # I (a list item in a comment), S (shaped like a key in a comment, but
    # spelled as none in the schema is) or P (prose).
    function kind(s) {
      if (s ~ /^ *#? *$/) return "B"
      if (s !~ /^ *#/) return "L"
      if (s ~ /^ *# +[a-z_][a-z0-9_]*:( |$)/) return "K"
      if (s ~ /^ *# +- /) return "I"
      if (s ~ /^ *# *[A-Za-z0-9_-]+:( |$)/) return "S"
      return "P"
    }
    function prose(x) { return x == "P" || x == "S" }
    function lead(s) { match(s, /^ */); return RLENGTH }
    function keyname(s) { sub(/^ *#? */, "", s); sub(/:.*$/, "", s); return s }
    # Forget every entry deeper than d. The doomed keys are collected first,
    # because deleting inside a for-in loop is not portable across awks.
    function prune(stack, d,   x, n, q, gone) {
      n = 0
      for (x in stack) if (x + 0 > d) gone[++n] = x
      for (q = 1; q <= n; q++) delete stack[gone[q]]
    }
    function put(p, at) { np++; path[np] = p; line_of[np] = at }
    { text[NR] = $0; k[NR] = kind($0) }
    END {
      for (i = 1; i <= NR; i++) {
        if (k[i] == "B") continue
        if (k[i] == "L") {
          # Every key the config reader takes, hyphens and capitals included,
          # so a live key keeps its own place under it.
          if (text[i] ~ /^ *[A-Za-z0-9_-]+:( |$)/) {
            d = lead(text[i])
            live[d] = (d ? live[d - 2] "." : "") keyname(text[i])
            prune(live, d)
          }
          continue
        }
        # A paragraph of comment lines, up to the next blank or live line.
        a = i; inprose = 0
        while (i <= NR && k[i] != "B" && k[i] != "L") { if (k[i] == "P") inprose = 1; i++ }
        b = i - 1; i = b
        if (inprose) {
          for (j = a; j <= b; j++)
            if (k[j] == "K" && !(prose(k[j - 1]) && prose(k[j + 1]))) put("?" keyname(text[j]), j)
          continue
        }
        # chain[r] is the path open at indent r, and at[r] the place in the
        # output of the commented key that opened it, so a parent is marked
        # where it stands, never by its path.
        split("", chain); split("", at); top = -1
        for (j = a; j <= b; j++) {
          if (k[j] == "S") { put("?" keyname(text[j]), j); continue }
          if (k[j] != "K") continue
          # The indent the line has once its "# " is dropped.
          c = lead(text[j]); d = c + lead(substr(text[j], c + 2)) - 1
          if (top < 0) {
            top = d; example = (d > c)
            if (!example) for (x in live) chain[x] = live[x]
          }
          r = example ? d - top : d
          if (r == 0) p = keyname(text[j])
          else if ((r - 2) in chain) {
            p = chain[r - 2] "." keyname(text[j])
            if ((r - 2) in at) parent[at[r - 2]] = 1
          } else p = "?" keyname(text[j])
          put(p, j)
          chain[r] = p; at[r] = np; prune(chain, r); prune(at, r)
        }
      }
      for (q = 1; q <= np; q++) if (!(q in parent)) printf "%s\t%d\n", path[q], line_of[q]
    }
  ' "${1:-$DEVBIN_LIB_DIR/config.reference.yaml}"
}

# schema_path_known <path> -- true when the validator accepts <path>. A
# list-valued key is a schema path only WITH an index -- `project.languages` is
# documented as one key and validates as `project.languages.0` -- so either
# form is accepted: that is what the schema itself means by a sequence, not a
# loosening. One statement for both checks that hold a document's keys to the
# schema. Needs lib/helpers and lib/config.
schema_path_known() {
  _cfg_path_known "$1" || _cfg_path_known "$1.0"
}

# unknown_comment_keys -- read reference_comment_keys lines on stdin and print,
# as `line <N>: <path>`, each path the schema does not know, and each `?` row,
# which no key can be, with why.
unknown_comment_keys() {
  local row path
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    path="${row%%$'\t'*}"
    case "$path" in
      '?'*) printf 'line %s: %s -- placed nowhere: beside prose, indented past any key, or spelled as no key is\n' "${row#*$'\t'}" "$path" ;;
      *) schema_path_known "$path" || printf 'line %s: %s\n' "${row#*$'\t'}" "$path" ;;
    esac
  done
  return 0
}

# readme_surface_commands -- the command names named in the README's command
# surface section, read from the first backticked cell of each table row.
readme_surface_commands() {
  awk '
    /^## The command surface/ { inside = 1; next }
    inside && /^## /          { inside = 0 }
    !inside                   { next }
    # [a-z-]+ rather than [a-z]+: the first hyphenated built-in (shell-init)
    # was INVISIBLE to this extractor, so the check reported it missing from a
    # README row that was present and correct. A pattern narrower than the
    # namespace it scans reads as coverage right up until the namespace grows.
    /^\| `[a-z][a-z-]*`/ {
      t = $0; sub(/^\| `/, "", t); sub(/`.*$/, "", t); print t
    }
  ' "$DEVBIN_HOME/README.md" | LC_ALL=C sort -u
}

# user_docs -- set USER_DOCS to every doc a user reads: the README, docs/, the
# shipped pages, the template a new project's help starts from, devbin's own
# help and the formula. Release notes and the changelog are left out: they
# record what a release said, and a note may quote what a later one changed.
user_docs() {
  USER_DOCS=("$DEVBIN_HOME/README.md" "$DEVBIN_HOME"/docs/*.md "$DEVBIN_LIB_DIR"/pages/*.md
    "$DEVBIN_LIB_DIR/tmpl/help.md" "$DEVBIN_HOME"/bin/.devbin/help/*.md
    "$DEVBIN_HOME"/bin/.devbin/help/*.d/*.md "$DEVBIN_HOME/packaging/homebrew/devbin.rb")
}

# readme_section <heading> -- the README's lines under `## <heading>`, up to the
# next `## ` heading; nothing when there is no such heading.
readme_section() {
  awk -v h="## $1" '
    $0 == h          { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside           { print }
  ' "$DEVBIN_HOME/README.md"
}

# source_exit_codes -- every status devbin's own half can actually exit with,
# read from the `exit N` statements in the dispatcher and the library.
#
# COMMENTS ARE STRIPPED FIRST AND THAT IS NOT TIDINESS. The first version of
# this extractor grepped the files raw and reported a code 126 that this source
# has never exited: `lib/helpers` describes issue 0005's failure mode in prose,
# and a bare grep counts a sentence ABOUT a bug as a statement that causes one.
# An extractor that reads comments is reading the wrong document, and it would
# have put a fabricated code into the contract this test exists to protect.
# lib's pages (*.md) are prose for the same reason, and are not read: a page
# saying a command "refuses with exit 6" is not a statement that does it.
#
# Stripping can only remove text, never invent an `exit N`, so it risks a false
# NEGATIVE rather than a false positive -- which the contract pair below sees,
# since it compares the source's codes with the prose's both ways.
source_exit_codes() {
  {
    sed 's/#.*//' "$DEVBIN_HOME/bin/devbin"
    find "$DEVBIN_LIB_DIR" -type f ! -name '*.md' -exec sed 's/#.*//' {} +
  } | grep -oE '\bexit [0-9]+' | awk '{print $2}' | LC_ALL=C sort -un
}

# contract_table -- the rows of the table under "Exit codes are a contract" in
# docs/authoring-commands.md, which is the ONE place the contract is stated,
# and which ships (issue 0241; the workroom's own contract file points at it).
# The read is total: a row below the separator whose first cell is not a bare
# code is named on stderr and fails the read, rather than read as no row, so a
# stale row in another shape cannot pass the arms that compare the sets.
#
# No other document restates the list. Two documents once carried it in almost
# the same words, so when a fourth code shipped both went stale in the same
# instant and neither could go red.
contract_table() {
  awk '
    /^## Exit codes are a contract$/ { on = 1; next }
    on && /^## / { exit }
    on && /^\|/ {
      if (!sep) { sep = /^\|[-:| ]+\|$/; next }
      if (/^\| [0-9]+ +\|/) { print; next }
      print "the exit-code table has a row whose code is not a bare number: " $0 >"/dev/stderr"
      bad = 1
    }
    END { exit bad }' "$DEVBIN_HOME/docs/authoring-commands.md"
}

# contract_exit_codes -- every status the contract's table enumerates.
contract_exit_codes() {
  contract_table | awk '{ print $2 }' | LC_ALL=C sort -un
}

# ============================================================================
# THE EXTRACTOR ITSELF
# ============================================================================

@test "the schema key extractor reads the whole schema, not a fragment" {
  local keys segs lost
  keys="$(schema_keys)"

  # A REFERENT, NOT A COUNT: every segment of every dotted path the
  # configuration reference documents, placeholders dropped, is a key the
  # extractor finds. Adding a key is normal and breaks nothing; a reformat that
  # loses a documented key is named, and an empty set cannot pass.
  segs="$(documented_paths | tr '.' '\n' | grep -v -E '^<[a-z]+>$|^$' | LC_ALL=C sort -u)"
  [ -n "$segs" ] || fail "no dotted path read out of docs/configuration.md -- nothing to hold the extractor to"
  lost="$(LC_ALL=C comm -23 <(printf '%s\n' "$segs") <(LC_ALL=C sort -u <<<"$keys"))"
  [ -z "$lost" ] || fail "docs/configuration.md documents keys the schema key extractor does not find:\n$lost"

  # Spot-check a key of each shape the extractor parses,
  # so a partial extractor that finds only one shape is caught too.
  grep -qx "project" <<<"$keys"     # a branch label
  grep -qx "summary" <<<"$keys"     # an alternation member
  grep -qx "languages" <<<"$keys"   # an equality test
  # And one key only the release TABLE supplies (ST0007). Emptying the table's
  # extractor was measured to drop every release key while the count that stood
  # above then stayed green, taking them out of both "every schema key appears"
  # tests.
  grep -qx "object_wait" <<<"$keys" # a row of _DEVBIN_RELEASE_SCHEMA
}

@test "the exit-code extractors read code and prose, and neither returns an empty set" {
  local src con codes
  # The table's read is total (contract_table): a row it cannot read fails
  # here, where the arms comparing the sets would read it as no row.
  contract_table >/dev/null || fail "the exit-code table in docs/authoring-commands.md has a row whose code is not a bare number (above)"
  src="$(source_exit_codes | wc -l | tr -d ' ')"
  con="$(contract_exit_codes | wc -l | tr -d ' ')"

  # Neither may be empty: an extractor broken by a reformat returns nothing, and
  # the contract tests below then pass having compared two empty sets -- the
  # exact false green this file was written to refuse. A code lost from one side
  # only is theirs to see, since they compare the two sets both ways.
  [ "$src" -gt 0 ]
  [ "$con" -gt 0 ]

  # Spot-check a common code and a rare one, so an extractor that finds only the
  # common codes is caught. 0 is the most frequent; 4 is the one whose
  # absence from the prose is what this pair of tests exists to catch.
  codes="$(source_exit_codes)"
  grep -qx 0 <<<"$codes"
  grep -qx 4 <<<"$codes"
}

@test "the extractor finds no key the validator rejects" {
  # The other direction: everything extracted must really be schema. A key here
  # that the validator does not know would silently demand documentation for
  # something that does not exist.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"

  local k
  for k in $(schema_keys); do
    case "$k" in
      # The section names are paths in their own right only as parents;
      # every other extracted token is a leaf under one of them.
      project | help | docs | options | commands | devbin_version) continue ;;
    esac
    # Every leaf must appear somewhere in the validator's own source.
    grep -q "$k" "$DEVBIN_LIB_DIR/config"
  done
}

@test "the commented-key extractor reads each key the reference documents in a comment, at the path its nesting gives it (0173)" {
  local keys n want rules got expect
  keys="$(reference_comment_keys | cut -f1)"

  # An extractor broken by a reformat returns nothing, so it must return
  # something; the keys it must find, one for each way the reference builds a
  # path, are named below. grep -c exits 1 on a count of 0, which this reports.
  n="$(printf '%s\n' "$keys" | grep -c .)" || true
  [ "$n" -gt 0 ] || fail "the extractor read no commented key out of lib/config.reference.yaml"

  # One key for each way the reference builds a path, so an extractor that
  # builds only some of them is caught there too: a list under a live block, a
  # key under a live parent two levels down, a key under a commented parent, a
  # key after a commented sibling, and the example in the iex comment.
  for want in release.remotes release.notes.run release.publish.url release.object_wait options.iex.commands; do
    grep -qxF "$want" <<<"$keys" || fail "the extractor did not read $want"
  done
  # A commented parent is named by its children's paths, never on its own.
  if grep -qxF release.publish <<<"$keys"; then
    fail "the extractor read the parent release.publish as a key"
  fi

  # THE RULES, ON A FIXTURE OF THEIR OWN AND COMPARED WHOLE, line numbers and
  # all. Beside the reference's own shapes it holds what the reference does not:
  # a key indented past any key it could nest under, once where a deeper
  # commented key went before it (foo) and once where a deeper live key did
  # (bar), so neither may borrow a parent that is no longer open; ci written
  # again as a leaf, read there though it is a parent above; two keys spelled as
  # none in the schema is (dry-run, Dry_run), which come back unplaced rather
  # than read as prose; a line of prose that opens with a word and a colon
  # (parsed), which is no key; a key straight under prose (tag), which cannot
  # be told from prose and so must come back unplaced rather than unread; and a
  # live key spelled with a hyphen, as the config reader takes one (my-cmd),
  # under which a commented key keeps its own place.
  rules="$DEVBIN_TEST_TMPDIR/rules.yaml"
  cat >"$rules" <<'YAML'
release:
  # remotes:
  #   - origin
  notes:
    kind: command
    # run: x
  # ci:
  #   query: x
  # repo: x
  #     foo: x
  branch: main
      # bar: x
  tag: v
  # ci: x
  object: local
  # dry-run: x
  #Dry_run: x

# A paragraph of prose, in which a line
# parsed: opens with a word and a colon, as
# sentences do.
# tag: x
options:
  iex:
    flag: true
    #
    #   options:
    #     iex:
    #       commands:
    #         - web
    #
my-cmd:
  # run: x
YAML
  got="$(reference_comment_keys "$rules")"
  expect="$(printf '%s\t%s\n' release.remotes 2 release.notes.run 6 release.ci.query 8 release.repo 9 \
    '?foo' 10 '?bar' 12 release.ci 14 '?dry-run' 16 '?Dry_run' 17 '?tag' 22 options.iex.commands 29 \
    my-cmd.run 33)"
  [ "$got" = "$expect" ] || fail "the extractor read the rules fixture as:\n$got\nwhere its rules give:\n$expect"
}

# ============================================================================
# THE ANNOTATED REFERENCE CONFIG
# ============================================================================

@test "the annotated reference config parses and validates" {
  # Not run in a subshell: the config cache is a shell variable, so `run
  # cfg_load` reads back as an absent config and this would pass on nothing.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"

  cfg_load "$DEVBIN_LIB_DIR/config.reference.yaml"
  cfg_validate
}

@test "the configuration reference names the boolean words lib/helpers reads (0080)" {
  # The page states the words by hand, so it is held to the lists the validator
  # and every boolean reader use.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  local w line
  line="$(grep -F '**A boolean key takes' "$DEVBIN_HOME/docs/configuration.md")"
  [ -n "$line" ]
  for w in $_DEVBIN_TRUE_WORDS $_DEVBIN_FALSE_WORDS; do
    grep -qF "\`$w\`" <<<"$line" || {
      echo "docs/configuration.md does not name the boolean word: $w" >&2
      return 1
    }
  done
  [ "$(printf '%s' "$line" | grep -oE '`(true|yes|1|false|no|0|[a-z0-9]+)`' | sed -n '1,6p' | tr -d '`' | tr '\n' ' ')" = "$_DEVBIN_TRUE_WORDS $_DEVBIN_FALSE_WORDS " ]
}

@test "every schema key appears in the annotated reference config" {
  local k missing=""
  for k in $(schema_keys); do
    grep -qE "^ *#? *-? *${k}:" "$DEVBIN_LIB_DIR/config.reference.yaml" || missing="$missing $k"
  done
  [ -z "$missing" ] || {
    echo "undocumented in lib/config.reference.yaml:$missing" >&2
    return 1
  }
}

@test "every key the annotated reference config documents in a comment is one the schema knows (0173)" {
  # THE OTHER DIRECTION, FOR THE KEYS ONLY A COMMENT SHOWS. Validating the
  # reference reads its live keys alone, and "every schema key appears" runs
  # from the schema to this file, so a commented key the schema does not know --
  # a misspelling, or one a rename left behind -- passed both. The release:
  # block documents keys only this way, because declaring them would
  # change what a project does.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"

  local keys n bad copy plant
  keys="$(reference_comment_keys)"
  # grep -c exits 1 on a count of 0, which the check below reports.
  n="$(printf '%s\n' "$keys" | grep -c .)" || true
  [ "$n" -gt 0 ] || fail "the extractor read no commented key out of lib/config.reference.yaml"
  bad="$(unknown_comment_keys <<<"$keys")"
  [ -z "$bad" ] || fail "commented in lib/config.reference.yaml, and not a key the schema knows:\n$bad"

  # THE PLANTED CONTROL, in a copy, beside the release: block's own commented
  # keys: one the schema does not know; one it knows only as ci:'s, at the
  # release: level; and one indented past any key it could nest under. The check
  # must name all three and nothing else, which it can do only by asking about
  # the PATH -- a check of the name alone passes `wait` -- and by refusing a row
  # the extractor could not place. A blank line closes the plants, so a comment
  # later written under release: cannot join them. Each plant is counted first,
  # so one that missed its anchor cannot pass.
  copy="$DEVBIN_TEST_TMPDIR/config.reference.yaml"
  awk '{ print } /^release:/ { print "  # bump: patch"; print "  # wait: 20m"; print "  #     deep: x"; print "" }' \
    "$DEVBIN_LIB_DIR/config.reference.yaml" >"$copy"
  for plant in '  # bump: patch' '  # wait: 20m' '  #     deep: x'; do
    [ "$(grep -cxF "$plant" "$copy")" -eq 1 ] || fail "the plant did not apply: $plant"
  done
  bad="$(unknown_comment_keys <<<"$(reference_comment_keys "$copy")")"
  [ "$(printf '%s\n' "$bad" | awk '{ print $3 }' | tr '\n' ' ')" = "release.bump release.wait ?deep " ] ||
    fail "the check named:\n$bad"
}

# ============================================================================
# THE CONFIGURATION REFERENCE PAGE
# ============================================================================

@test "every schema key appears in the configuration reference" {
  local documented k missing=""
  documented="$(documented_keys)"

  # Guard the extractor before comparing with it, for the reason stated at the
  # top of this file: an empty set here would compare nothing and pass.
  [ -n "$documented" ] || fail "documented_keys read nothing out of docs/configuration.md"

  for k in $(schema_keys); do
    grep -qx "$k" <<<"$documented" || missing="$missing $k"
  done
  [ -z "$missing" ] || {
    echo "undocumented in docs/configuration.md:$missing" >&2
    return 1
  }
}

@test "the configuration reference names no key the schema rejects" {
  # Every dotted path in a table row of that page must be one the validator
  # accepts. This is what catches a key that was renamed in the schema and left
  # behind in the prose -- the drift that reads as correct.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"

  local path probe bad=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # `<cmd>`, `<opt>` and `<name>` are placeholders for a user-chosen segment;
    # the validator takes any name there, so substitute a concrete one.
    probe="$(printf '%s' "$path" | sed -e 's/<cmd>/x/g' -e 's/<opt>/y/g' -e 's/<name>/z/g')"
    # A list-valued key is a schema path with an index (schema_path_known).
    schema_path_known "$probe" || bad="$bad $path"
  done <<EOF
$(documented_paths)
EOF

  [ -z "$bad" ] || {
    echo "documented but not in the schema:$bad" >&2
    return 1
  }
}

# ============================================================================
# THE README COMMAND SURFACE
# ============================================================================

@test "every built-in command appears in the README command surface" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"

  local documented cmd missing=""
  documented="$(readme_surface_commands)"

  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    grep -qx "$cmd" <<<"$documented" || missing="$missing $cmd"
  done <<EOF
$(builtin_commands)
EOF

  [ -z "$missing" ] || {
    echo "shipped but not in the README surface:$missing" >&2
    return 1
  }
}

@test "the README command surface names no command devbin does not ship" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"

  local cmd bad=""
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    is_builtin_command "$cmd" || bad="$bad $cmd"
  done <<EOF
$(readme_surface_commands)
EOF

  [ -z "$bad" ] || {
    echo "in the README surface but not shipped:$bad" >&2
    return 1
  }
}

@test "the README surface extractor finds a plausible number of commands" {
  # The guard on the second README test above, which iterates over this: an
  # extractor returning nothing would make it pass having compared nothing. A
  # fragment is the first README test's to see, since it holds every built-in
  # to the surface.
  local count
  count="$(readme_surface_commands | wc -l | tr -d ' ')"
  [ "$count" -gt 0 ] || fail "readme_surface_commands read no command out of the README"
}

# readme_table <intro> -- the rows of the command-surface table that follows the
# paragraph opening with <intro>, one per line: the command from its first
# cell, then a tab and its second cell as written. The section is read first and
# handed to awk whole, since awk stops at the table's end (contract.bats AT-7.1).
readme_table() {
  local section
  section="$(readme_section "The command surface")" || return 1
  awk -v intro="$1" '
    index($0, intro) == 1 { inside = 1; next }
    inside && /^\| `/ {
      split($0, c, "|")
      cmd = c[2]; gsub(/[ `]/, "", cmd)
      second = c[3]; sub(/^ +/, "", second); sub(/ +$/, "", second)
      print cmd "\t" second
      rows = 1
      next
    }
    inside && rows && !/^\|/ { exit }
  ' <<<"$section"
}

# help_offered <proj> -- the commands <proj>'s help lists, one per line and
# sorted, help's Usage and Global blocks aside, failing when help does. A
# command row is two spaces and a name as devbin's names are spelled, an option
# row is indented further, and a heading ends in a colon.
help_offered() {
  local out
  out="$(devbin_run "$1" help)" || {
    fail "help exited non-zero in $1:
$out"
    return 1
  }
  awk '
    /^[A-Z][A-Za-z ]*:$/ { group = $0; next }
    group != "" && group != "Global:" && group != "Usage:" && /^  [a-z][a-z0-9_-]*( |$)/ { print $1 }
  ' <<<"$out" | LC_ALL=C sort
}

# seeded <dir> [--lang <l>] -- a project at <dir> as `devbin install --into`
# seeds one, its starter config included, with what each built-in needs in its
# tree made (_DEVBIN_BUILTIN_NEEDS), so the commands that need it are offered.
seeded() {
  local dir="$1" need
  shift
  mkdir -p "$dir"
  "$DEVBIN_BIN_DIR/devbin" install --into "$dir" "$@" >/dev/null || fail "devbin install --into $dir $* failed"
  while read -r _ need; do
    [ -z "$need" ] || mkdir -p "$dir/$need"
  done <<<"$_DEVBIN_BUILTIN_NEEDS"
}

@test "the README's offered tables are what a freshly seeded project's help lists, and its language table what each language adds (0256)" {
  # A fresh install declares no language, and the README listed test and clean
  # as always offered, which its help offered neither of. The tables are held
  # to help, not to the catalogue: help is what a reader meets.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/builtins
  . "$DEVBIN_LIB_DIR/builtins"
  local intro="Offered when the project declares the language." only="Offered only in devbin's own trees"
  local always table owntree fresh="$DEVBIN_TEST_TMPDIR/fresh" lang proj got want langs cmd
  seeded "$fresh"
  # The always-offered table and devbin's own lifecycle, which help lists under
  # its Devbin heading.
  always="$({
    readme_table "Always offered:"
    readme_table "Devbin's own lifecycle, always offered:"
  } | cut -f1 | LC_ALL=C sort)"
  [ -n "$always" ] || fail "no always-offered table was read out of the README"
  got="$(help_offered "$fresh")"
  [ "$got" = "$always" ] || fail "a freshly seeded project's help offers:
$got
and the README's always-offered tables list:
$always"
  # And what only devbin's own trees offer, no project does.
  owntree="$(readme_table "$only" | cut -f1)"
  [ -n "$owntree" ] || fail "no table of what only devbin's own trees offer was read out of the README"
  while IFS= read -r cmd; do
    ! grep -qx "$cmd" <<<"$got" || fail "a freshly seeded project offers $cmd, which the README says only devbin's own trees do"
  done <<<"$owntree"
  table="$(readme_table "$intro")"
  [ -n "$table" ] || fail "no language table was read out of the README"
  # Every language the catalogue scopes a row by, and every one the README's
  # table names, so a language either side forgets is still asked.
  langs="$({
    awk 'NF && $2 != "any" && $2 != "opt-in" { print $2 }' <<<"$_DEVBIN_BUILTIN_CATALOGUE"
    awk -F'\t' '{ n = split($2, ls, /, */); for (i = 1; i <= n; i++) print ls[i] }' <<<"$table"
  } | LC_ALL=C sort -u)"
  for lang in $langs; do
    proj="$DEVBIN_TEST_TMPDIR/p$lang"
    seeded "$proj" --lang "$lang"
    got="$(help_offered "$proj")"
    # The whole listing: the always-offered commands, and the rows the
    # language table gives this language, nothing more and nothing less.
    want="$({
      printf '%s\n' "$always"
      awk -F'\t' -v l="$lang" '{ n = split($2, ls, /, */); for (i = 1; i <= n; i++) if (ls[i] == l) print $1 }' <<<"$table"
    } | LC_ALL=C sort -u)"
    [ "$got" = "$want" ] || fail "a project declaring $lang offers:
$got
and the README's tables give it:
$want"
  done
}

# ============================================================================
# THE HOMEBREW INSTALL LINE
#
# Homebrew refuses a short name from a tap it does not trust yet, so a reader
# who has only tapped devbin cannot follow `brew install devbin`: it stops at
# "Refusing to load formula ... from untrusted tap". The full name installs the
# formula and trusts it, after which `brew upgrade devbin` loads, so only an
# install line has to carry it. Every doc a user reads is scanned (user_docs).
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - devbin after another formula on one line, as in brew install bash devbin;
#   - a quoted name, a line split with a backslash, a tab or a second space
#     between brew and install, and an option that takes a value;
#   - brew reinstall, which needs the formula installed, and so trusted.
# And a doc may not quote the short form even to warn against it: the scan
# cannot tell a warning from an instruction.
# ============================================================================

@test "the docs install devbin by the formula's full name, never the short name Homebrew refuses from a tap it does not trust (0203)" {
  local USER_DOCS
  user_docs
  local hits="$DEVBIN_TEST_TMPDIR/brew.short" floor="$DEVBIN_TEST_TMPDIR/brew.full" short
  : >"$hits" || fail "cannot write $hits"
  : >"$floor" || fail "cannot write $floor"
  # Read through vendored_scan, the one home of the rule that no NUL or invalid
  # byte may hide a line (issue 0205).
  vendored_scan "$hits" s 'brew install( +-[^ ]+)* +devbin([^-/[:alnum:]_]|$)' "${USER_DOCS[@]}" ||
    fail "grep could not read every doc it was given"
  short="$(<"$hits")"
  [ -z "$short" ] || fail "a doc installs devbin by its short name, which Homebrew refuses from a tap it does not trust:
${short//"$DEVBIN_HOME/"/}"
  # The floor: the README's own install line, in the form the scan protects,
  # so a scan that read nothing cannot pass.
  vendored_scan "$floor" s 'brew install matthewsinclair/devbin/devbin' "$DEVBIN_HOME/README.md" ||
    fail "grep could not read the README"
  [ -s "$floor" ] || fail "the README does not install devbin as brew install matthewsinclair/devbin/devbin"
}

@test "the README's install example, run as written after its brew lines, seeds the project it names in a fresh home (0258)" {
  # Its devbin line was `devbin install --into ~/some/new/project`, which refuses
  # a directory that is not there, and nothing said to make one. The brew lines
  # are not run: a keg published as the formula publishes one stands in for
  # theirs, and the lines run as a reader runs them (reader_seeds). The example
  # is held in `example`, never `lines`, which bats' `run` fills with each run's
  # output.
  local src section example into
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  section="$(readme_section "Install")" || fail "the README's Install section could not be read"
  example="$(awk '/^```zsh$/ { inside = 1; next } inside && /^```$/ { exit } inside && !/^brew / { print }' <<<"$section")"
  [ -n "$example" ] || fail "nothing was read out of the README's install example"
  into="$(sed -n 's/^devbin install --into \([^ ]*\).*/\1/p' <<<"$example")"
  reader_seeds "$DEVBIN_TEST_TMPDIR/readerhome" "$into" "$example"
  refute_output_contains "names no devbin install"
}

# as_reader <home> <path> <command...> -- <command> run as a brew user's shell
# runs it: a scrubbed environment, <home> as its home and data directory, the
# test's HOMEBREW_PREFIX, <path>, and no system or global git configuration, as
# the suite reads none (tests/lib/test_helper.bash). The README arms run their
# examples so.
as_reader() {
  local home="$1" path="$2"
  shift 2
  env -i HOME="$home" XDG_DATA_HOME="$home/.local/share" HOMEBREW_PREFIX="$HOMEBREW_PREFIX" PATH="$path" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$@"
}

# reader_seeds <home> <into> <script> -- <script>, an example as the docs ship
# it, run by a brew user in <home> (as_reader), seeds the project at <into>, a
# path under ~/ (issue 0258, and 0269's dvb examples). Homebrew's bin, which
# links the keg's devbin, comes first on a PATH holding no other devbin, and
# the arm says that link is the devbin the example meets before it runs it.
# The script runs under bash -eu with no input; on return `output` is its run's.
reader_seeds() {
  local home="$1" into="$2" script="$3" path
  case "$into" in
    '~/'?*) ;;
    *) fail "the example seeds '$into', and this arm reads a path under ~/: $script" ;;
  esac
  path="$HOMEBREW_PREFIX/bin:$(path_without devbin)" || fail "PATH could not be cleared of devbin"
  mkdir -p "$home" || fail "no home could be made at $home"
  run as_reader "$home" "$path" bash -c 'command -v devbin' </dev/null
  [ "$output" = "$HOMEBREW_PREFIX/bin/devbin" ] || fail "the example's devbin would be '$output', not Homebrew's link"
  run as_reader "$home" "$path" bash -euc "$script" </dev/null
  assert_success
  [ -x "$home/${into#\~/}/bin/devbin" ] || fail "the example ran, and its project holds no bin/devbin: $script
$output"
}

# dvb_seeds <file> -- every example in <file> that seeds a project with
# `dvb install`, run as written by a brew user, each in a fresh home, seeds the
# project it names (issue 0269).
#
# The examples ran `cd ~/some/new/project && dvb install`, which stops at cd
# when the directory is not there, and nothing said to make it. Each line ending
# ` dvb install` is read out of <file>, its indent stripped, so the arm runs the
# shipped text; a file holding none fails. A keg published as the formula
# publishes one (brew_keg) stands in for the brew install, and `dvb` is what the
# devbin on the reader's PATH, Homebrew's link, emits from shell-init, as the
# docs say to emit it (reader_seeds). The examples are held in `examples`, never
# `lines`, which bats' `run` fills.
#
# THE EXAMPLES RUN UNDER BASH, `shell-init bash`, although the README fences
# them as zsh: the defect, a cd into a directory nothing made, is the same in
# either shell.
#
# WHAT THIS DOES NOT CATCH: only a line ending exactly in ` dvb install` is
# read, so `dvb install` with arguments, a bare `dvb install` line, a line
# ending in CRLF, and a two-line form with the mkdir on the line above are each
# passed over, seeded or not.
dvb_seeds() {
  local file="$1" src example into home out fn
  local -a examples
  [ -r "$file" ] || fail "$file cannot be read"
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  out="$(awk '/^ *[^ ].* dvb install$/ { sub(/^ +/, ""); print }' "$file")" ||
    fail "the dvb examples could not be read out of $file"
  [ -n "$out" ] || fail "no example in $file seeds a project with dvb install"
  mapfile -t examples <<<"$out"
  for example in "${examples[@]}"; do
    into="$(sed -n 's/.*cd \(~\/[^ ]*\).*/\1/p' <<<"$example")"
    home="$(mktemp -d "$DEVBIN_TEST_TMPDIR/readerhome.XXXXXX")" || fail "no home could be made for: $example"
    # The dvb the example runs is kept, in the reader's home, outside the
    # project it seeds, so what it falls back to is read from that very dvb.
    reader_seeds "$home" "$into" 'eval "$(devbin shell-init bash)"; declare -f dvb >"$HOME/dvb.fn"; '"$example"
    refute_output_contains "no machine install"
    fn="$(<"$home/dvb.fn")" || fail "the dvb $file's example ran with was not kept"
    # A text check of the default shell-init emitted, that dvb falls back to the
    # keg's opt link: it does not show the fallback ran, which the seeded
    # project above does.
    [[ "$fn" == *"\${DEVBIN_INSTALL_PREFIX:-'$HOMEBREW_PREFIX/opt/devbin'}"* ]] ||
      fail "the dvb $file's example ran with does not fall back to $HOMEBREW_PREFIX/opt/devbin: $fn"
  done
}

@test "the README's dvb example, run as written with the dvb Homebrew's devbin emits, seeds the project it names in a fresh home (0269)" {
  dvb_seeds "$DEVBIN_HOME/README.md"
}

@test "shell-init's usage's dvb example, run as written with the dvb Homebrew's devbin emits, seeds the project it names in a fresh home (0269)" {
  dvb_seeds "$DEVBIN_LIB_DIR/cmd/shell-init"
}

@test "shell-init's page's dvb example, run as written with the dvb Homebrew's devbin emits, seeds the project it names in a fresh home (0269)" {
  dvb_seeds "$DEVBIN_LIB_DIR/pages/shell-init.md"
}

# ============================================================================
# THE USER'S INSTALL IS BREW, AND DEV AND OPT ARE THE MAINTAINER'S
#
# Anything devbin releases through Homebrew reaches a machine in tiers,
# dev, opt and brew: the dev checkout, a working copy published from it to opt,
# and the formula, the one publish to prod. A user installs from brew and seeds
# projects from the brew install; dev and opt are documented once, in the
# README's section for the maintainer of a dev checkout, and every other doc
# points there. Until 0210 the README seeded a project from one maintainer's opt
# path and called it preferred.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a checkout or an opt publish offered as the way to install in words that
#     name neither a home directory's Devel tree, install.prefix nor
#     DEVBIN_SOURCE, which only review can see;
#   - outside the README, a doc that explains the tiers again without the
#     maintainer heading: only a second heading is refused there;
#   - a home directory written other than as ~ or $HOME, which neutral.bats's
#     paths arm reads in the vendored set and nothing reads in the README.
# ============================================================================

@test "no doc a user reads seeds a project from one machine's Devel tree (0210)" {
  local USER_DOCS
  user_docs
  local hits="$DEVBIN_TEST_TMPDIR/devel.paths" found
  : >"$hits" || fail "cannot write $hits"
  vendored_scan "$hits" s '(~|\$HOME|\$\{HOME\})/Devel/' "${USER_DOCS[@]}" ||
    fail "grep could not read every doc it was given"
  found="$(<"$hits")"
  [ -z "$found" ] || fail "a doc names one machine's Devel tree, a maintainer's layout, where a user installs from brew:
${found//"$DEVBIN_HOME/"/}"
}

@test "the README installs from brew first, and documents dev and opt once, for the maintainer of a dev checkout (0210)" {
  local USER_DOCS
  user_docs
  local install first maint outside heads="$DEVBIN_TEST_TMPDIR/maint.heads"
  install="$(readme_section Install)"
  [ -n "$install" ] || fail "the README has no ## Install section"
  # The first fenced block under Install is the route a reader follows.
  first="$(awk '/^```/ { if (inb) exit; inb = 1; next } inb { print }' <<<"$install")"
  grep -qx 'brew install matthewsinclair/devbin/devbin' <<<"$first" ||
    fail "the first block under ## Install does not install devbin from brew:
$first"
  maint="$(readme_section 'For the maintainer of a dev checkout')"
  [ -n "$maint" ] || fail "the README has no ## For the maintainer of a dev checkout section"
  # The floor for the refusal below: the section names both, so a reader that
  # read nothing cannot pass it.
  grep -q 'install\.prefix' <<<"$maint" || fail "the maintainer's section does not name install.prefix"
  grep -q 'DEVBIN_SOURCE' <<<"$maint" || fail "the maintainer's section does not name DEVBIN_SOURCE"
  outside="$(awk '
    $0 == "## For the maintainer of a dev checkout" { inside = 1; next }
    inside && /^## /                                { inside = 0 }
    !inside && /install\.prefix|DEVBIN_SOURCE/      { print FNR ": " $0 }
  ' "$DEVBIN_HOME/README.md")"
  [ -z "$outside" ] || fail "the README names the maintainer's install.prefix or DEVBIN_SOURCE outside the maintainer's section:
$outside"
  # Documented once: the README's heading is the only one, across every doc a
  # user reads.
  : >"$heads" || fail "cannot write $heads"
  vendored_scan "$heads" i '^#+ .*maintainer of a dev checkout' "${USER_DOCS[@]}" ||
    fail "grep could not read every doc it was given"
  [ "$(wc -l <"$heads" | tr -d ' ')" -eq 1 ] || fail "the maintainer's section is not documented once:
$(<"$heads")"
}

# The tiers' contract is shared by every tool released through Homebrew, and
# devbin's docs are its home, so the README's documentation table has to lead
# to it. Every doc under docs/ is held to a row, so a doc added later is too;
# the contract is named because the arm exists for it, and a docs/ the glob
# read nothing from cannot pass.
@test "the README's documentation table links every doc under docs/, the dev, opt and brew contract among them" {
  local table doc name missing=""
  [ -f "$DEVBIN_HOME/docs/dev-opt-brew.md" ] || fail "docs/dev-opt-brew.md, the dev, opt and brew contract, is not there"
  table="$(readme_section Documentation)"
  [ -n "$table" ] || fail "the README has no ## Documentation section"
  for doc in "$DEVBIN_HOME"/docs/*.md; do
    name="docs/${doc##*/}"
    grep -qF "| [$name]($name) " <<<"$table" || missing="$missing $name"
  done
  [ -z "$missing" ] || fail "the README's documentation table has no row for:$missing"
}

# T4's doctor sentence (issue 0246): a doctor prints the version line
# unchanged, so the exception that let a failing check put a path on it is
# gone, and the paragraph ends on that sentence.
@test "the contract's T4 ends its version-line paragraph on the doctor sentence: doctor prints the same line, unchanged (0246)" {
  local doc="$DEVBIN_HOME/docs/dev-opt-brew.md" para
  para="$(grep -F -- '`<tool> --version` and `<tool> version` print one line' "$doc" || true)"
  [ -n "$para" ] || fail "docs/dev-opt-brew.md has no T4 version-line paragraph"
  [[ "$para" == *" Doctor prints the same line, unchanged." ]] ||
    fail "T4's version-line paragraph does not end with the doctor sentence: $para"
  [[ "$para" != *"names a path only where a check that fails is about one"* ]] ||
    fail "T4 still carries the exception issue 0246 removed: $para"
}

# The published tree carries the product and not the workroom under intent/,
# so a row naming a file there would lead a reader to nothing.
@test "the README's documentation table names no file under intent/, which the published tree does not carry" {
  local table rows
  table="$(readme_section Documentation)"
  [ -n "$table" ] || fail "the README has no ## Documentation section"
  rows="$(grep -E '^\| .*intent/' <<<"$table" || true)"
  [ -z "$rows" ] || fail "the README's documentation table names a file under intent/:
$rows"
}

# ============================================================================
# THE EXIT-CODE CONTRACT
# ============================================================================

@test "every exit code the source can return is named in the contract (0241)" {
  local missing=""
  local code named
  named="$(contract_exit_codes)"
  for code in $(source_exit_codes); do
    grep -qx "$code" <<<"$named" || missing="$missing $code"
  done

  # The contract is prose and prose cannot go red on its own. One change shipped
  # `exit 4` and edited the contract's own document in the same commit -- a
  # different line, two dozen lines from the contract it was invalidating.
  # Proximity is not a prompt, so this test is the prompt.
  [ -z "$missing" ] || fail "exit code(s)$missing are reachable in the source and named nowhere in the contract, docs/authoring-commands.md's table:
$(contract_table)"
}

@test "the contract names no exit code the source cannot return (0241)" {
  local stale=""
  local code returned
  returned="$(source_exit_codes)"
  for code in $(contract_exit_codes); do
    grep -qx "$code" <<<"$returned" || stale="$stale $code"
  done

  # The other direction, and it is not symmetric with the one above: a contract
  # promising a code nothing returns is a reader following a branch that does
  # not exist. Retiring a code is exactly as much a documentation change as
  # adding one, and only this direction catches it.
  [ -z "$stale" ] || fail "the contract names exit code(s)$stale that no 'exit' statement in the source can produce"
}

# ============================================================================
# THE VERSION -- ONE SOURCE, ONE DELIBERATE COPY
# ============================================================================
#
# `VERSION` is devbin's only statement of its own version, and every runtime
# path already reads it live: `devbin_version_of` takes the manifest header (or
# the tree's own VERSION in a source checkout), `runtime_version` does the same
# for the vendored half, and `install` stamps the manifest from it. Those live
# reads are pinned elsewhere -- doctor.bats asserts doctor reports the contents
# of VERSION, install.bats asserts the manifest is stamped from it.
#
# What was NOT pinned is the other direction: nothing stopped a second literal
# copy of the version appearing somewhere, and nothing checked that devbin's own
# declared constraint still admits its own VERSION. The second is the one that
# bites at a release, because the bump and the constraint live in different
# files and only one of them is obviously the version.
#
# EXACTLY ONE literal copy is legal, and it is a CONSTRAINT rather than a
# statement of fact -- `devbin_version: "^0.1.0"` in devbin's own config, the
# same declaration any consumer makes. It must stay hand-written: a constraint
# derived from the current version can never fail, and `doctor`'s
# check_devbin_version would pass vacuously forever. That is the false green
# this project treats as the cardinal sin, so the fix here would be the defect.

# devbin_own_version -- the one source of truth, read the way the runtime reads it.
devbin_own_version() { tr -d '[:space:]' < "$DEVBIN_HOME/VERSION"; }

# version_literal_sites [<version>] -- every file in the authored corpus carrying
# <version> as a literal string, repo-relative and sorted. <version> defaults to
# devbin's CURRENT version, which is the question the tests below ask.
#
# Comments are deliberately NOT stripped, unlike the exit-code extractor. There
# the question was "what can this code return", and a comment cannot return
# anything. Here the question is "what claims a version", and a comment claims
# one exactly as loudly as a config value does -- three caret-semantics examples
# used `^0.1.0` purely as an illustration, which read as a claim about the
# current version and are now written with a version devbin is not.
#
# The vendored half is excluded: `bin/.devbin/lib/` is a copy of `lib/` and
# would double every hit.
#
# `RELEASES/`, `CHANGELOG.md` and `RELEASES.md` are excluded on a different and
# stronger ground: a release note for 0.1.0 must name 0.1.0. Those are
# HISTORICAL records, like closed issues, and a version in them is the subject
# rather than a claim about the present. Adding them would make the test demand
# that the project's own history stop mentioning versions.
#
# The top level's Markdown is read whole, the release notes apart, rather than
# file by file: the public tree carries README.md alone there, and the
# workroom's own contracts, which do not ship, are read without a shipped file
# naming them (issue 0241).
version_literal_sites() {
  local v="${1:-$(devbin_own_version)}" f
  local -a top=()
  for f in "$DEVBIN_HOME"/*.md; do
    case "${f##*/}" in CHANGELOG.md | RELEASES.md) continue ;; esac
    top+=("$f")
  done
  grep -rlF "$v" \
    "$DEVBIN_HOME/lib" \
    "$DEVBIN_HOME/bin/devbin" \
    "$DEVBIN_HOME/bin/.devbin/config.yaml" \
    "$DEVBIN_HOME/docs" \
    ${top[@]+"${top[@]}"} \
    | grep -v "/bin/\.devbin/lib/" \
    | sed "s|^$DEVBIN_HOME/||" | LC_ALL=C sort -u
}

@test "the version extractor reads a real version and finds a real site" {
  local v count
  v="$(devbin_own_version)"

  # A version that is not semver-shaped means VERSION moved or the read broke,
  # and every test below would then search for the wrong string and find
  # nothing -- passing over an empty set, which is the failure this floor is
  # here to make impossible.
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION is not semver-shaped: '$v'"

  # THE FLOOR. The next test asserts the site list equals a one-entry allowlist,
  # and a broken grep returning nothing would satisfy "no unexpected sites"
  # while checking nothing at all. So the extractor is run on a version one
  # known site MUST carry: the constraint's own, which is written in the config.
  #
  # NOT ON VERSION. The floor searched for devbin's current version until the
  # 0.1.2 cut, which made it pass only while the constraint's literal happened
  # to name the current version. The constraint is moved when a release outgrows
  # it (docs/releasing.md), and ^0.1.1 admits 0.1.2, so VERSION found no site --
  # the clean tree the next test wants -- and the floor called it broken. The
  # release core's gate on the release commit is what caught it.
  local floor
  floor="$(grep -m1 '^devbin_version:' "$DEVBIN_HOME/bin/.devbin/config.yaml" | sed 's/^devbin_version: *//; s/"//g; s/^[^0-9]*//')"
  [[ "$floor" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "devbin_version's version is not semver-shaped: '$floor'"
  count="$(version_literal_sites "$floor" | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ] || fail "the version extractor found NO file carrying '$floor' -- it is broken, not the tree clean"
  local sites
  sites="$(version_literal_sites "$floor")"
  grep -qx "bin/.devbin/config.yaml" <<<"$sites" || fail "the extractor did not find '$floor' in bin/.devbin/config.yaml, which declares it"
}

@test "devbin's own version is a literal in no file but bin/.devbin/config.yaml, which declares a constraint" {
  local unexpected="" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      # THE ONLY ALLOWED SITE. Devbin declares a devbin_version constraint the
      # same way every consumer does, and a constraint is hand-set on purpose:
      # see the note above on why deriving it from VERSION would make doctor's
      # check unfailable.
      bin/.devbin/config.yaml) ;;
      *) unexpected="$unexpected $f" ;;
    esac
  done < <(version_literal_sites)

  [ -z "$unexpected" ] || fail "file(s)$unexpected hardcode devbin's current version. There is one source of truth (VERSION) and one deliberate constraint (bin/.devbin/config.yaml). If the string is an EXAMPLE, write a version devbin is not; if it is a reference, read VERSION."
}

@test "devbin's own declared constraint still admits devbin's own VERSION" {
  # THE RELEASE TRIPWIRE. The bump and the constraint live in different files
  # and only one of them looks like the version, so a release that edits VERSION
  # and forgets config.yaml leaves devbin failing its own doctor check. Nothing
  # caught that before this test: `bin/devbin doctor` would report it, but only
  # if somebody ran doctor against devbin itself.
  #
  # NOT VACUOUS: the two sides are read from two different files. Deriving the
  # constraint from VERSION is exactly what makes this check worthless.
  local v want
  v="$(devbin_own_version)"
  want="$(grep -m1 '^devbin_version:' "$DEVBIN_HOME/bin/.devbin/config.yaml" | sed 's/^devbin_version: *//; s/"//g')"

  [ -n "$want" ] || fail "devbin's own config declares no devbin_version constraint"

  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  version_satisfies "$v" "$want" ||
    fail "VERSION is $v but devbin's own config asks for $want -- bump the constraint in bin/.devbin/config.yaml"
}

# ============================================================================
# CROSS-LINKS
# ============================================================================

@test "every relative link in the docs resolves to a file that exists" {
  local doc dir target broken=""

  for doc in "$DEVBIN_HOME/README.md" "$DEVBIN_HOME"/docs/*.md; do
    [ -f "$doc" ] || continue
    dir="$(dirname "$doc")"
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      case "$target" in
        http* | '#'* | mailto:*) continue ;;
      esac
      target="${target%%#*}"
      [ -n "$target" ] || continue
      [ -e "$dir/$target" ] || broken="$broken ${doc#"$DEVBIN_HOME"/}->$target"
    done <<EOF
$(grep -oE '\]\([^)]+\)' "$doc" | sed -e 's/^](//' -e 's/)$//')
EOF
  done

  [ -z "$broken" ] || {
    echo "broken links:$broken" >&2
    return 1
  }
}

# ============================================================================
# AUTHORED HELP FOR DEVBIN'S OWN LIFECYCLE COMMANDS
# ============================================================================

@test "EVERY command devbin offers in its own tree has authored help, not the generated fallback (0112)" {
  # THE LIST IS DERIVED, NOT KEPT. This arm named five commands by hand --
  # install upgrade vendor doctor new -- and passed for weeks while seven other
  # verbs, release among them, fell through to the stub. A hand list is a census
  # someone stopped taking; it cannot fail on the verb nobody thought to add.
  # So the set is read from the listing a user actually sees, every top-level
  # row above its Global section, and a new verb without a page goes red here.
  local cmd n=0 missing=""
  local listed handler
  run devbin_run "$DEVBIN_HOME" help
  assert_success
  listed="$(printf '%s\n' "$output" | sed '/^Global:/,$d' | sed -n 's/^  \([a-z][a-z-]*\) .*/\1/p')"
  for cmd in $listed; do
    n=$((n + 1))
    run devbin_run "$DEVBIN_HOME" help "$cmd"
    assert_success
    # The fallback is correct behaviour and says where to write the file. Here
    # the file should exist, so seeing that sentence means it does not.
    case "$output" in *"No authored detail yet"*) missing="$missing $cmd" ;; esac
  done
  # Presence is what makes a clean result mean something: an extractor that
  # matched nothing would report no missing page for every tree there is.
  [ "$n" -gt 0 ] || fail "read no command from the listing -- the extractor would compare nothing"
  # And the listing holds devbin's own handlers, read off bin/.devbin/cmd, so one
  # dropped from a listing read short is named. The built-ins are help.bats's,
  # held against builtin_commands.
  for handler in "$DEVBIN_HOME"/bin/.devbin/cmd/*; do
    [ -f "$handler" ] && [ -x "$handler" ] || continue
    grep -qx "${handler##*/}" <<<"$listed" || fail "devbin's own ${handler##*/} is not in the listing the arm read:\n$listed"
  done
  # Since issue 0113 a built-in's page ships at lib/pages/<cmd>.md,
  # and devbin's own commands (its formula, test and check) keep theirs
  # at bin/.devbin/help/<cmd>.md. The shipped-pages arm in help.bats holds the first
  # in an INSTALLED fixture, which this tree cannot stand in for.
  [ -z "$missing" ] || fail "no authored help for:$missing -- a built-in's page goes in lib/pages/<cmd>.md, devbin's own in bin/.devbin/help/<cmd>.md"
}

@test "a project's own page replaces the generated answer rather than appending to it" {
  # check.md is devbin's OWN page, for the gates devbin declares for itself, so
  # it is a project page here. It read doctor.md until issue 0113 moved doctor's
  # page into lib/pages/ -- a SHIPPED page, which the trailer follows by design.
  run devbin_run "$DEVBIN_HOME" help check
  assert_success
  assert_output_contains "The read-only gates"
  # `Resolves from:` is the generated block's provenance line, and `In this
  # project:` heads the trailer after a shipped page. A project's own page is
  # the whole answer, so neither may be underneath it.
  refute_output_contains "Resolves from:"
  refute_output_contains "In this project:"
}
