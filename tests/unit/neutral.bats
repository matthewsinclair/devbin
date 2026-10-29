#!/usr/bin/env bats
# neutral.bats - the vendored runtime carries no trace of where it was made or
# used (issue 0152).
#
# devbin is copied byte for byte into every project that uses it, and some of
# those projects are delivered to clients. So nothing in the vendored set --
# exactly the files vendored_paths lists, bin/devbin and everything under
# bin/.devbin/lib/ -- may carry a commit, another repository's issue or CI run,
# a path on one machine, or an attribution to a person or a session.
#
# NOR A URI THAT CARRIES A PASSWORD (issue 0187), whatever stands for the
# password: a secret scanner reads `scheme://user:password@` as a credential, so
# every project that vendors devbin and scans its tree would have to excuse a
# line of devbin's, and an excuse for a credential-shaped string can later hide
# a real one.
#
# NOR THE LANGUAGE OF HOW devbin WAS DECIDED (issue 0202), on any line, comments
# included: how a thing was decided is the maintainers' record, and a vendored
# line says what the code does. NOR A REAL DOMAIN IN A WORKED EXAMPLE: a reference yaml is the
# file a reader copies, so every name in one is a reserved example name (RFC
# 2606: example.com, .example, .test, .invalid), never a real vendor's.
#
# BY SHAPE, NEVER BY NAME. devbin keeps no list of the projects or the people
# that use it: such a list inside devbin is the inverted dependency this rule
# removes, moved from a comment into a test. Each arm below recognises what it
# refuses by its shape alone. A NAME in prose -- a project, a person, a session
# -- has no shape, so review holds it, and nothing here can.
#
# Every arm proves on every run that it can go red: a planted file it must flag
# line by line, an innocent one it must pass, and only then the tree.
#
# WHAT THIS DOES NOT READ, declared so a green is never read as covering it:
#   - a name in prose, as above;
#   - a commit in upper-case hex, in git-describe form (v1.2-3-gabc1234), or
#     abbreviated to digits alone, none of which the commit shape can tell from
#     an ordinary token;
#   - bin/.devbin/manifest.sha256, which install and upgrade write BESIDE the
#     vendored set (issue 0153 owns what it records);
#   - git history, here or in any consumer: upgrading cleans the tree, never
#     the history;
#   - a phrase split across two lines, which no line-oriented arm can see;
#     the tracker arm (0172) reads the commonest split, a line ending in
#     "issue" or one opening with a number shaped like 0172, and no other;
#   - for the tracker arm, a line that begins with `#` inside text a user is
#     shown -- a heredoc, or a quoted string that runs over several lines: in
#     code the arm reads only lines that are not comments, and it cannot tell
#     such a line from one. The pages, the reference yamls and lib/tmpl/ it
#     reads whole;
#   - for the tracker arm, a bare four-digit number with no "issue" or "(" in
#     front of it, which it cannot tell from a file mode such as 0644;
#   - for the estate arm, a count of machines, which it cannot tell from an
#     ordinary sentence about two machines;
#   - for the credential arm, a URI assembled from parts whose source is not
#     URI-shaped, such as "${scheme}://${user}:${pass}@${host}"; a password
#     holding a raw `/`, `?`, `#` or blank, which no URI parser reads as one
#     either; `user:password@host` with no scheme; and every other shape a
#     scanner reads as a secret (a key, a token), which no arm here looks for;
#   - for the decision arm, a synonym (a call, a verdict), which it cannot tell
#     from the ordinary word;
#   - for the example arm, a domain in a page or in code, one in a `.yml`
#     file (it reads `.yaml` alone, as the tracker arm does), one whose last
#     label is not among the public suffixes it names, and, under BSD awk, one
#     after a NUL on its line, which BSD awk ends the line at (the refs arm
#     shares the limit).

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

# The one line that names the owner: LICENSE.md's copyright line, and the same
# line as bin/devbin's header comment. The owner is devbin's own identity, so
# naming it is not a dependency on anyone who uses devbin.
_NEUTRAL_COPYRIGHT='Copyright (c) 2026 Geodica Ltd (geodica.com)'
_NEUTRAL_OWNER='geodica'

# A count, in digits or as a word: the estate arm's number.
_NEUTRAL_NUM='([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|dozen)'

# A citation of devbin's own tracker, or a date: the tracker arm's shape.
_NEUTRAL_TRACKER='([Ii][Ss][Ss][Uu][Ee][Ss]?[-: ]+#?[0-9]{3,4}|[Ii][Ss][Ss][Uu][Ee][Ss]?[[:space:]]*$|\(0[0-9]{3}([,)]| v[0-9])|^[#[:space:]]*0[0-9]{3}([^0-9]|$)|ST[0-9]{4}|(^|[^A-Za-z0-9_])[Ww][Pp][- ]?[0-9]{1,2}([^0-9]|$)|(^|[^A-Za-z0-9_])AC[- ]?[0-9]{1,2}([^0-9]|$)|(^|[^A-Za-z0-9_])D[0-9]{1,3}([^0-9A-Za-z_]|$)|[Dd]esign [Dd]ecision|DESIGN DECISION|[Ss]teel [Tt]hreads?|20[0-9]{2}[-/][0-9]{2}|20[0-9]{2}[01][0-9][0-3][0-9])'

# The noun and the past tense of deciding by rule, singular or plural, in any
# case, between non-letters: the decision arm's shape. A rule, a ruler and overruled are not one.
_NEUTRAL_DECIDED='(^|[^A-Za-z])rul(ed|ings?)([^A-Za-z]|$)'

# The public suffixes a real domain in a worked example ends in: the example
# arm's candidates. A reserved name (.example, .test, .invalid) ends in none of
# them, and example.com, .net and .org are let through by name.
_NEUTRAL_SUFFIX='com|net|org|io|dev|app|co|uk|de|eu|ai|me|info|biz|us|xyz|cloud|email'

# _neutral_hits <arm> <out> <file>... -- write to <out>, as path:line:text,
# every line of the files that <arm> refuses. 0 when every file was read,
# hits or not; 2 when a grep, a filter or the arm itself failed -- every
# step's status is read, because a filter that died leaves <out> empty, and
# empty reads as clean.
_neutral_hits() {
  local arm="$1" out="$2" raw="$2.raw"
  shift 2
  # Both scratch files start empty: the scans APPEND, so a second call that
  # inherited the first's candidates would report them as its own -- the
  # negative control caught exactly that on this arm's first run.
  : >"$raw" || return 2
  : >"$raw.sha" || return 2
  case "$arm" in
    refs)
      # Another repository's issue (`project#0032`, any case, one to five
      # digits), a CI run's address, and a run's id: GitHub's run ids are
      # eleven digits and more, where 2^32 is ten. A run's address names the
      # run by its number, so an API path holding the run in a variable, as
      # `actions/runs/$id/artifacts` does, cites no run (ST0008 WP-08).
      vendored_scan "$raw" s "[A-Za-z][A-Za-z0-9_]*#[0-9]{1,5}([^0-9]|\$)" "$@" || return 2
      vendored_scan "$raw" s "github\\.com/[^ ]*/(issues|pull|actions|commit)/|actions/runs/[0-9]" "$@" || return 2
      vendored_scan "$raw" s "(^|[^0-9])[0-9]{11,}([^0-9]|\$)" "$@" || return 2
      # A commit is a run of 7 to 40 hex digits between non-alphanumerics that
      # holds a digit AND a letter, so a number, a word made of a-f, and a name
      # such as sha256 are not one. grep finds the candidates, awk the runs,
      # under C as the scan reads: under a UTF-8 locale macOS awk exits 2 on a
      # hit that holds an invalid byte (issue 0205).
      vendored_scan "$raw.sha" s "(^|[^A-Za-z0-9])[0-9a-f]{7,40}([^A-Za-z0-9]|\$)" "$@" || return 2
      LC_ALL=C awk '{
        t = $0; sub(/^[^:]*:[0-9]+:/, "", t)
        n = split(t, w, /[^A-Za-z0-9]+/)
        for (i = 1; i <= n; i++)
          if (w[i] ~ /^[0-9a-f]+$/ && length(w[i]) >= 7 && length(w[i]) <= 40 && w[i] ~ /[0-9]/ && w[i] ~ /[a-f]/) {
            print; break
          }
      }' "$raw.sha" >>"$raw" || return 2
      ;;
    paths)
      # A machine's own layout: an absolute home (`/Users/x` or `/users/x`, or
      # `/home/x`), a mounted volume, macOS's per-user temporary tree, or a
      # home-relative path -- `~`, `~user`, `$HOME`, `${HOME}` or `"$HOME"` --
      # into a CAPITALISED directory, which is how a person's own folders are
      # named (Devel, Dropbox, Library). The lower-case dot directories a tool
      # documents (~/.local, ~/.config) are not one.
      vendored_scan "$raw" s "/[Uu]sers/[A-Za-z]|/home/[a-z]|/Volumes/|/(private/)?var/folders/|(~[a-z]*|\\\$\\{?HOME\\}?\"?)/[A-Z]" "$@" || return 2
      ;;
    credentials)
      # A URI that carries a password, `scheme://user:password@`, whatever
      # stands for the password, an env indirection such as $PGPASSWORD
      # included: a secret scanner cannot tell the two apart. A user with no
      # password, as in ssh://git@host, carries none. The user and the password
      # are read as RFC 3986 reads userinfo, ending at `/`, `?` or `#`, so an
      # `@` in a query or a fragment is not one. The cost, declared: an `@`
      # after a `;` in the host part (http://h:8080;x@y) and a credential
      # detector's own glob with a literal scheme (https://*:*@*) are refused
      # too, loudly, and rephrased.
      vendored_scan "$raw" s "[A-Za-z][A-Za-z0-9+.-]*://[^/?#[:space:]@]*:[^/?#[:space:]@]*@" "$@" || return 2
      ;;
    attribution)
      # Who said or did a thing, by the shapes it was written in: a dated
      # parenthesis naming a two- or three-letter handle, in either case,
      # qualified or not, comma or none -- (xy, 2026-01-02), (proj/xy, ...),
      # (xy probe, ...), (XY 2026-...) -- and a handle's decision noun, review
      # or finding. A hyphen may not precede the handle, so built-in's is not one.
      # The cost, declared: (eg, 2026-...) and "it's" before one of those nouns
      # are refused too, loudly, and rephrased.
      vendored_scan "$raw" s "\\(([A-Za-z][A-Za-z0-9_-]*/)?[A-Za-z]{2,3}( [a-z]+)?,? 20[0-9]{2}-[0-9]{2}-[0-9]{2}" "$@" || return 2
      vendored_scan "$raw" s "(^|[^A-Za-z-])[A-Za-z]{2}'s (ru""ling|ru""lings|review|finding|proposal|correction|point|option|decision|measurement)" "$@" || return 2
      ;;
    owner)
      # The owner's name anywhere but on its copyright line.
      vendored_scan "$raw" i "$_NEUTRAL_OWNER" "$@" || return 2
      awk -v c="$_NEUTRAL_COPYRIGHT" '{
        t = $0; sub(/^[^:]*:[0-9]+:/, "", t)
        if (t != c && t != "# " c) print
      }' "$raw" >"$raw.kept" || return 2
      mv "$raw.kept" "$raw" || return 2
      ;;
    estate)
      # The operator's own estate described in the runtime every consumer
      # carries: the word fleet, in any case, between non-letters (so fleet_x
      # and fleet-wide; a word with letters joined to it, such as fleetctl, is
      # not read), and a COUNT of estates, projects, consumers, repositories or
      # installs -- a number, in digits or as a word up to twenty, and any one
      # word before the noun ("N of M estates" holds "M estates"). A singular
      # ("one estate") and a vague quantity ("most projects") are not a count,
      # and stay; a count split across two lines is not read.
      vendored_scan "$raw" i "(^|[^A-Za-z])fleets?([^A-Za-z]|\$)" "$@" || return 2
      vendored_scan "$raw" i "(^|[^A-Za-z0-9_])$_NEUTRAL_NUM( [A-Za-z/-]+){0,2} (estates|projects|consumers|repositories|repos|installs|installations)([^A-Za-z]|\$)" "$@" || return 2
      ;;
    tracker)
      # devbin's own tracker cited in text a user reads: an issue, a thread, a
      # work package, an acceptance criterion, a numbered decision or a date
      # (how a thing was decided is the decisions arm's, on every line). The pages, the
      # reference yamls and lib/tmpl/ are read whole; in code, only lines that
      # are not comments, which is where what devbin prints is written. A
      # maintainer's comment citing an issue stays.
      vendored_shown "$raw" "$_NEUTRAL_TRACKER" "$@" || return 2
      ;;
    decisions)
      # How devbin was decided, on every line, comments included: the tracker
      # arm reads printed lines only, and a comment is shipped too.
      vendored_scan "$raw" i "$_NEUTRAL_DECIDED" "$@" || return 2
      ;;
    examples)
      # A domain in a reference yaml that is not a reserved example name. grep
      # finds the lines holding a name in one of the suffixes, awk the names:
      # each run of letters, digits, `_`, `-` and `.`, its root dot dropped,
      # whose last label is one of them, unless it is example.com, .net or
      # .org or a name under one. Only the yamls among <file>... are read: a
      # page or code may name the host it really talks to.
      local f
      local -a yamls=()
      for f in "$@"; do
        case "$f" in *.yaml) yamls+=("$f") ;; esac
      done
      [ "${#yamls[@]}" -gt 0 ] || return 2
      vendored_scan "$raw.sha" i "[A-Za-z0-9_-]\\.($_NEUTRAL_SUFFIX)\\.?([^A-Za-z0-9_-]|\$)" "${yamls[@]}" || return 2
      # Under C, as the scan reads, for the reason the refs arm gives.
      LC_ALL=C awk -v sfx="$_NEUTRAL_SUFFIX" '{
        t = $0; sub(/^[^:]*:[0-9]+:/, "", t)
        n = split(tolower(t), w, /[^a-z0-9_.-]+/)
        for (i = 1; i <= n; i++) {
          d = w[i]; sub(/\.+$/, "", d)
          if (d ~ ("[a-z0-9_-]\\.(" sfx ")$") && d !~ /(^|\.)example\.(com|net|org)$/) {
            print; break
          }
        }
      }' "$raw.sha" >>"$raw" || return 2
      ;;
    *) return 2 ;;
  esac
  LC_ALL=C sort -u "$raw" >"$out" || return 2
  return 0
}

# _neutral_plant <name> <line>... -- a file of exactly these lines, its path
# printed.
_neutral_plant() {
  local f="$DEVBIN_TEST_TMPDIR/$1"
  shift
  printf '%s\n' "$@" >"$f"
  printf '%s\n' "$f"
}

# _neutral_arm <arm> <remedy> <positive-file> <negative-file> -- the three
# readings every arm owes: each planted line flagged, no innocent line
# flagged, and no vendored line flagged.
_neutral_arm() {
  local arm="$1" remedy="$2" pos="$3" neg="$4" out="$DEVBIN_TEST_TMPDIR/$1.out"
  local rc=0 n want files
  local -a vf
  # POSITIVE CONTROL: every planted line, not merely some.
  _neutral_hits "$arm" "$out" "$pos" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read its control (status $rc)"
  n="$(awk 'END { print NR }' "$out")"
  want="$(awk 'END { print NR }' "$pos")"
  [ "$n" -eq "$want" ] || fail "the $arm scan flagged $n of the $want planted lines:\n$(cat "$out")"
  # NEGATIVE CONTROL: nothing innocent.
  _neutral_hits "$arm" "$out" "$neg" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read its control (status $rc)"
  [ ! -s "$out" ] || fail "the $arm scan flags an innocent line:\n$(cat "$out")"
  # THE TREE.
  files="$(vendored_set_files)" || fail "the vendored set could not be listed"
  mapfile -t vf <<<"$files"
  [ -n "$files" ] || fail "the vendored set is empty -- the scan would read nothing"
  _neutral_hits "$arm" "$out" "${vf[@]}" || rc=$?
  [ "$rc" -eq 0 ] || fail "the $arm scan could not read the vendored set (status $rc)"
  [ ! -s "$out" ] || fail "the vendored runtime $remedy:\n$(sed "s|^$DEVBIN_HOME/||" "$out")"
}

@test "every file vendored_paths lists is there to scan, and they are not an empty set (0152)" {
  # vendored_paths is the scan's population; that the list is the WHOLE seam
  # is install.bats's to hold, against an independent find of lib/, and is not
  # restated here.
  local files n f
  files="$(vendored_set_files)" || fail "the vendored set could not be listed"
  n="$(printf '%s\n' "$files" | awk 'NF { c++ } END { print c + 0 }')"
  [ "$n" -gt 0 ] || fail "vendored_paths lists no file -- the scan would read nothing"
  while IFS= read -r f; do
    [ -f "$f" ] || fail "vendored_paths names a file that is not there: $f"
  done <<<"$files"
}

@test "no vendored file cites a commit, another repository's issue, or a CI run (0152)" {
  local pos neg bin out="$DEVBIN_TEST_TMPDIR/refs.bin.out"
  pos="$(_neutral_plant refs.pos '# project#0032' '# ported from it, 25c431a00' '# installed from 49e8bb2' \
    '# 0123456789abcdef0123456789abcdef01234567' '# other#0518 says so' '# run 36258740223 went red' \
    '# see https://github.com/o/r/actions/runs/1' '# https://github.com/o/r/issues/12' \
    '# o/r/actions/runs/7 went red' '# INTENT#0518' '# other#29' '# other#12345')"
  neg="$(_neutral_plant refs.neg '# issue 0127, D''42, ST0007 WP-02, AC-6.1' \
    '# sha256, deadbeef, 12345678 and 0x1F' '# a digest of [0-9a-f]{12}' '# 4294967296 is 2^32' \
    '# gh api repos/$path/actions/runs/$id/artifacts')"
  # A FILE GREP CALLS BINARY IS STILL READ: a NUL beside a commit must not
  # turn the line into a "binary file matches" that nothing on stdout reports.
  bin="$DEVBIN_TEST_TMPDIR/refs.bin"
  printf '# commit 25c431a00\000 and a NUL\n' >"$bin"
  _neutral_hits refs "$out" "$bin" || fail "the refs scan could not read a NUL-bearing file"
  [ -s "$out" ] || fail "a NUL-bearing file read as clean -- grep treated it as binary and said nothing"
  _neutral_arm refs "cites a commit, another repository's issue or a CI run -- devbin's own issue numbers and decision numbers stay, and the rest belongs in git" "$pos" "$neg"
}

@test "no vendored file carries a path on one machine (0152)" {
  local pos neg
  pos="$(_neutral_plant paths.pos '# collected in ~/Devel/prj/x/dmarc' '# /Users/someone/x' \
    '# /home/someone/x' "# \$HOME/Devel/opt/devbin" "# \${HOME}/Devel/x" '# ~/Dropbox/x' \
    '# ~/Library/CloudStorage/x' '# /private/var/folders/ab/T/x' '# /var/folders/ab/T/x' \
    "# \"\$HOME\"/Devel/x" '# /Volumes/Work/x' '# ~someone/Devel' '# /users/someone')"
  neg="$(_neutral_plant paths.neg '# ~/.local/bin/demo' "# \$HOME/.cache" '# /usr/local/bin' \
    "# \${XDG_DATA_HOME:-\$HOME/.local/share}/devbin")"
  _neutral_arm paths "carries a path on one machine -- say what the path is, not where it was" "$pos" "$neg"
}

@test "no vendored file carries a URI with a password in it, an env indirection included (0187)" {
  local pos neg
  pos="$(_neutral_plant credentials.pos "  warn \"use (postgresql://user:\\\$\$v@host) instead\"" \
    '# postgresql://u:$PGPASSWORD@host/db' '# mysql://root:s3cr3t@db:3306/x' '# redis://:hunter2@cache:6379' \
    '# https://user:token@example.com/o/r.git' '# mongodb+srv://u:p@cluster.example.net/db' \
    '# postgres://app:${DB_PASSWORD}@db/app' '# amqp://guest:guest@localhost:5672/')"
  # The negatives hold each edge of the shape: no password, no `://`, a `/`, a
  # blank, a `?` and a `#` before the `@`.
  neg="$(_neutral_plant credentials.neg '# ssh://git@host/x' '# https://example.com/path?q=1' \
    '# mail someone@example.com' '# git@example.com:owner/repo.git' '# https://example.com:8443/x' \
    '# postgresql://localhost/db' '# a ratio of 3:4 @ noon' \
    '# docker://registry.example.com:5000/app@sha256:0123456789abcdef' \
    '# open http://localhost:8080 and mail ops@example.com' \
    '# http://localhost:8080?next=ops@example.com' '# https://example.com:443#ops@example.com')"
  _neutral_arm credentials "carries a URI with a password in it, which a secret scanner reads as a credential whatever stands for the password -- describe the URI's form in words instead" "$pos" "$neg"
}

@test "no vendored file attributes a decision, a review or a finding to anyone (0152)" {
  local pos neg
  pos="$(_neutral_plant attribution.pos '# (xy, 2026-09-16)' '# (proj/xy, 2026-09-01)' \
    '# (xy probe, 2026-08-09)' "# xy's ru""ling" "# as xy's review found" "# xy's finding" \
    '# (H''V, 2026-09-16)' '# (xy 2026-09-16)' '# (abc, 2026-09-16)' "# C""c's review found it" \
    "# per H""V's ru""ling")"
  neg="$(_neutral_plant attribution.neg "# the built-in's option set" '# issue 0127 (2026-09-16)' \
    '# (critic''-shell on 0135 v2c)' "# the ru""ling's own words" '# (D''42, the rule)')"
  _neutral_arm attribution "attributes a decision, a review or a finding to someone -- keep the lesson and drop who said it" "$pos" "$neg"
}

@test "the owner's licence is vendored and at the repository root, byte for byte, and names the owner only on its copyright line (0152)" {
  local rels pos neg
  rels="$(vendored_paths "$DEVBIN_HOME")" || fail "the vendored set could not be listed"
  grep -qxF 'bin/.devbin/lib/LICENSE.md' <<<"$rels" ||
    fail "LICENSE.md is not in the vendored set"
  grep -qxF -- "$_NEUTRAL_COPYRIGHT" "$DEVBIN_LIB_DIR/LICENSE.md" ||
    fail "lib/LICENSE.md does not carry the copyright line: $_NEUTRAL_COPYRIGHT"
  grep -qxF -- "# $_NEUTRAL_COPYRIGHT" "$DEVBIN_HOME/bin/devbin" ||
    fail "bin/devbin's header does not carry the copyright line"
  # ONE LICENCE, TWO PLACES, HELD BY THIS LINE RATHER THAN BY DISCIPLINE: the
  # repository's own LICENSE and the copy every vendored project receives.
  cmp -s "$DEVBIN_HOME/LICENSE" "$DEVBIN_LIB_DIR/LICENSE.md" ||
    fail "LICENSE at the repository root and lib/LICENSE.md differ -- devbin has one licence, so they are byte-identical"
  # The licence is MIT, and the formula template declares the same.
  [ "$(head -n 1 "$DEVBIN_HOME/LICENSE")" = "MIT License" ] || fail "LICENSE is not the MIT licence"
  grep -qxF '  license "MIT"' "$DEVBIN_HOME/packaging/homebrew/devbin.rb" ||
    fail "the formula template does not declare license \"MIT\""
  pos="$(_neutral_plant owner.pos '# measured on the geodica estate' '# geodica.com in a table' \
    "# $_NEUTRAL_COPYRIGHT and more")"
  neg="$(_neutral_plant owner.neg "# $_NEUTRAL_COPYRIGHT" "$_NEUTRAL_COPYRIGHT")"
  _neutral_arm owner "names its owner off the copyright line" "$pos" "$neg"
}

@test "no vendored file describes the operator's own fleet or counts its estates (0172)" {
  local pos neg
  pos="$(_neutral_plant estate.pos '# measured across the fleet' '# the Fleet sweep' \
    '# fleet_preview_hint prints it' '# 12 of 16 estates' '# in all four projects' \
    '# two of four projects' '# fourteen estates vendor this' '# Twelve other estates took it' \
    "# two consumers' tools" '# across 16 estates' '# in a tool four other estates vendor' \
    '# Two corpus projects run it' '# seven of the first nine installs' '# all six capitalised projects' \
    '# two of the four source projects' '# a fleet-wide sweep' '# 12 of the estates' '# 16 of our estates' \
    '# four other consumer projects' '# 16 Rust/Elixir projects' '# across six repos' '# eight installations' \
    '# thirty estates')"
  neg="$(_neutral_plant estate.neg '# measured on one estate' '# what most projects use' \
    '# each estate carries its own copy' '# fleeting' '# the reflection of it' '# 4 files' \
    '# one install of it' '# on 2026-09-06, estates were running it' \
    '# identical on two machines with different checkouts')"
  _neutral_arm estate "describes the operator's own estate -- keep the reasoning and drop who, where and how many" "$pos" "$neg"
}

@test "nothing a user reads cites devbin's tracker: printed lines, pages, the reference yamls, the templates (0172)" {
  local pos neg md yaml tmpl bin stub rc out="$DEVBIN_TEST_TMPDIR/tracker.md.out" rels n_whole n_code
  pos="$(_neutral_plant tracker.pos "  printf 'floor (issue 0022)\n'" '  die "reserved (D''8)"' \
    'TWO MODES (ST0005, D''26):' '  warn "runs lib/ in place (D''12)"' "  _note 'overrides (D""2/D""5)'" \
    '  echo "at WP-11 close"' '  echo "AC-11.11 holds"' \
    '  printf "a design'' decision"' '  echo "see ST0006"' '  echo "until 2026-09-07"' \
    '  die "reserved (0172)"' '  echo "ISSUE 0172"' '  echo "D''100 says"' '  echo "at WP 11"' '  echo "since 2026-09"' \
    '  echo "issue-0172 holds"' '  echo "issue: 0172"' '  echo "issue #172"' '  die "refused (issue' '    0172)"' \
    '  echo "(0168, 0170)"' '  echo "(0172 v2)"' '  echo "at wp-1"' '  echo "AC 11 holds"' '  echo "AC11"' \
    '  echo "a Design'' Decision"' '  echo "on 2026/10/06"' \
    '  echo "seal 20261006"' '  echo "the steel thread"')"
  # The comment a maintainer keeps, and the near misses of each shape: a D with
  # a letter before it or after its digits, a bare D, a mode in parentheses.
  neg="$(_neutral_plant tracker.neg '# issue 0022 is why the floor is five' '  # design D''12, for maintainers' \
    '  printf "%s\n" "$D"' '  printf "the floor is bash 5\n"' '  echo "ND12 and D12x"' '  local D1x=1' \
    '  chmod 0644 "$f"' '  echo "issues 22"' '  echo "at mode 0111, as 0644: it"' '  echo "the issue is open"' \
    '  echo "SWAP-12 and TACK-1 and MAC11"' '  echo "version 2026.10"')"
  # A PAGE, A REFERENCE YAML AND A TEMPLATE ARE READ WHOLE: a comment-shaped
  # line in any of them is text a user reads. Each plant's citing lines are its
  # own list, beside one plain line, so the count the scan must flag is theirs.
  local -a md_cite=('# Settled in ST0006' 'It is opt-in (devbin design D''22).')
  local -a yaml_cite=('# the default is none (issue 0143)') tmpl_cite=('# read by help (design D''23)')
  md="$(_neutral_plant tracker.plant.md "${md_cite[@]}" 'Plain prose.')"
  yaml="$(_neutral_plant tracker.plant.yaml "${yaml_cite[@]}" 'key: value')"
  mkdir -p "$DEVBIN_TEST_TMPDIR/tmpl"
  tmpl="$(_neutral_plant tmpl/handler "${tmpl_cite[@]}" 'set -eu')"
  _neutral_hits tracker "$out" "$md" "$yaml" "$tmpl" || fail "the tracker scan could not read a planted page, yaml or template"
  local want=$((${#md_cite[@]} + ${#yaml_cite[@]} + ${#tmpl_cite[@]}))
  [ "$want" -gt 0 ] && [ "${#md_cite[@]}" -gt 0 ] || fail "nothing planted -- the controls would compare nothing"
  [ "$(awk 'END { print NR }' "$out")" -eq "$want" ] || fail "the tracker scan did not flag exactly the $want citing lines of a page, a yaml and a template:\n$(cat "$out")"
  # EVERY FILE IS READ, NOT ONLY THE FIRST: the page's citing lines, read after a
  # file with none.
  _neutral_hits tracker "$out" "$neg" "$md" || fail "the tracker scan could not read two files"
  [ "$(awk 'END { print NR }' "$out")" -eq "${#md_cite[@]}" ] || fail "the tracker scan read only part of what it was given:\n$(cat "$out")"
  # A NUL HIDES NOTHING: a citation after one is still read.
  bin="$DEVBIN_TEST_TMPDIR/tracker.bin"
  printf '  printf "x\000 (issue 0022)"\n' >"$bin"
  _neutral_hits tracker "$out" "$bin" || fail "the tracker scan could not read a NUL-bearing file"
  grep -q 'issue 0022' "$out" || fail "a citation after a NUL was not read as its line -- grep treated the file as binary:\n$(cat "$out")"
  # A FILTER THAT DIES IS A FAILED SCAN, NEVER A CLEAN ONE: a grep that fails
  # only the comment filter's -v makes the scan answer 2.
  stub="$DEVBIN_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  printf '#!/bin/sh\ncase " $* " in *" -v "*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v grep)" >"$stub/grep"
  chmod +x "$stub/grep"
  rc=0
  PATH="$stub:$PATH" _neutral_hits tracker "$out" "$neg" || rc=$?
  [ "$rc" -eq 2 ] || fail "the tracker scan answered $rc when its comment filter failed -- a dead filter read as clean"
  # THE POPULATION: what it reads whole and the code it reads, each there to read.
  rels="$(vendored_paths "$DEVBIN_HOME")" || fail "the vendored set could not be listed"
  n_whole="$(printf '%s\n' "$rels" | awk '/\.md$|\.yaml$|\/tmpl\// { c++ } END { print c + 0 }')"
  n_code="$(printf '%s\n' "$rels" | awk 'NF && !/\.md$|\.yaml$|\/tmpl\// { c++ } END { print c + 0 }')"
  [ "$n_whole" -gt 0 ] || fail "no page, yaml or template in the vendored set -- the scan would read nothing whole"
  [ "$n_code" -gt 0 ] || fail "no code file in the vendored set -- the scan would read no printed line"
  grep -qxF 'bin/.devbin/lib/config.reference.yaml' <<<"$rels" || fail "config.reference.yaml is not in the vendored set"
  grep -qxF 'bin/.devbin/lib/tmpl/handler' <<<"$rels" || fail "tmpl/handler is not in the vendored set"
  _neutral_arm tracker "cites devbin's tracker in text a user reads -- say what the rule is, not which issue, thread or decision made it" "$pos" "$neg"
}

@test "no vendored line, comment or code, says how devbin was decided (0202)" {
  local pos neg
  pos="$(_neutral_plant decisions.pos '# launchd and cron were ru''led out' '# THE EXIT STATUS IS A RU''LING' \
    '# its parent'"'"'s id: two ru''lings' '  echo "as ru''led"' '  echo "RU''LED so"' '  echo "RU''LINGS"' \
    '# (issue 0060, Ru''led option A)' '# the_ru''ling_was B')"
  neg="$(_neutral_plant decisions.neg '# the rule is one function' '# the rules below' '# a ruler' \
    '# it was overruled' '# unruly input' '  echo "rule: --iex"')"
  _neutral_arm decisions "says how devbin was decided -- say what the code does, not who or what settled it" "$pos" "$neg"
}

@test "a reference yaml's worked example names only reserved example domains, never a real one (0202)" {
  local pos neg out="$DEVBIN_TEST_TMPDIR/examples.code.out" code rels rc
  pos="$(_neutral_plant examples.pos.yaml '    spf_include: _spf.vendor.com' \
    '        value: s1._domainkey.vendor.net' '    rua: dmarc@corp.io' '      - shop.co.uk' \
    '    name: www.acme.org.' '    mx: ASPMX.L.GOOGLE.COM' '    name: notexample.com' \
    '# a sender such as mail.provider.email')"
  neg="$(_neutral_plant examples.neg.yaml '    name: example.com' '    rua: dmarc@example.org' \
    '      - mail.example.net' '    spf_include: _spf.newsletter.example' '    name: host.test' \
    '    name: bad.invalid' '  file: config.yaml' '  run: commands.test' '# see example.com.' \
    '    value: tx1._domainkey.transactional.example')"
  # ONLY THE YAMLS ARE READ: code naming the host it really talks to is not a
  # worked example, and a scan given no yaml at all fails rather than passing.
  code="$(_neutral_plant examples.code 'host=github.com')"
  _neutral_hits examples "$out" "$code" "$neg" || fail "the examples scan could not read a yaml beside code"
  [ ! -s "$out" ] || fail "the examples scan read a file that is not a yaml:\n$(cat "$out")"
  rc=0
  _neutral_hits examples "$out" "$code" || rc=$?
  [ "$rc" -eq 2 ] || fail "the examples scan answered $rc for a population holding no yaml -- nothing read is not clean"
  rels="$(vendored_paths "$DEVBIN_HOME")" || fail "the vendored set could not be listed"
  grep -qxF 'bin/.devbin/lib/infra.reference.yaml' <<<"$rels" || fail "infra.reference.yaml is not in the vendored set"
  grep -qxF 'bin/.devbin/lib/config.reference.yaml' <<<"$rels" || fail "config.reference.yaml is not in the vendored set"
  _neutral_arm examples "names a real domain in a worked example -- use a reserved example name (example.com, .example, .test, .invalid)" "$pos" "$neg"
}
