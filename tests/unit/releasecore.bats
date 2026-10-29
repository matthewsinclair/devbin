#!/usr/bin/env bats
# releasecore.bats - the release core (ST0007)
#
# NOT release.bats: that name holds the arms of devbin's own notes generator,
# bin/.devbin/cmd/release, until WP-02 ports them. Writing this file under it
# once replaced all of them.
#
# WP-01: the opt-in row, the `release:` schema and its defaults, the
# declaration half of `release check`, and the argument loop. Every
# argument is parsed before anything acts, and `--help` anywhere never acts:
# issue 0064 recorded `macos prepare --help` rebuilding Intent.app.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  init_colors off
}
teardown() { devbin_teardown; }

@test "the fingerprint changes on a new file, an edited file, a tag, a git config write, a pushed ref and a gh call" {
  # THE POSITIVE CONTROL for every "writes nothing" arm below. WP-01's handler
  # writes nothing, so those arms cannot go red on today's code; this shows the
  # instrument they rest on can, one write at a time.
  proj="$(enabled_project)"
  git_project "$proj"
  local before
  before="$(fingerprint "$proj")"
  : >"$proj/new-file"
  [ "$(fingerprint "$proj")" != "$before" ] || fail "a new file did not change the fingerprint"
  rm "$proj/new-file"
  [ "$(fingerprint "$proj")" = "$before" ] || fail "removing the new file did not restore the fingerprint"
  printf 'x\n' >>"$proj/bin/.devbin/config.yaml"
  [ "$(fingerprint "$proj")" != "$before" ] || fail "an edited file did not change the fingerprint"
  git -C "$proj" checkout -q -- bin/.devbin/config.yaml
  git -C "$proj" tag v0.0.1
  [ "$(fingerprint "$proj")" != "$before" ] || fail "a tag did not change the fingerprint"
  git -C "$proj" tag -d v0.0.1 >/dev/null
  git -C "$proj" config --local release.test yes
  [ "$(fingerprint "$proj")" != "$before" ] || fail "a git config write did not change the fingerprint"
  git -C "$proj" config --local --unset release.test
  git -C "$proj" push -q origin main:refs/heads/elsewhere
  [ "$(fingerprint "$proj")" != "$before" ] || fail "a pushed ref did not change the fingerprint"
  git -C "$DEVBIN_TEST_TMPDIR/remote.git" update-ref -d refs/heads/elsewhere
  # The push also wrote the local remote-tracking ref for the new branch.
  git -C "$proj" update-ref -d refs/remotes/origin/elsewhere 2>/dev/null || true
  [ "$(fingerprint "$proj")" = "$before" ] || fail "the fixture did not return to its first fingerprint"
  # The stub answers `release view` for an unknown tag with exit 1, as gh does;
  # the call is what this line is about, not its answer.
  PATH="$DEVBIN_TEST_TMPDIR/stubs:$PATH" gh release view v0.0.1 2>/dev/null || true
  [ "$(fingerprint "$proj")" != "$before" ] || fail "a gh call did not change the fingerprint"
}

# ============================================================================
# OPT-IN (AC-1.2)
# ============================================================================

# _release_help_prints_page <proj> -- in <proj>, which has not enabled release,
# `release --help` prints what `help release` does, whole and at exit 0: the
# not-offered line, then devbin's vendored page (issues 0255 and 0271). Help's
# answer is read first, so the expected bytes are the help verb's own.
_release_help_prints_page() {
  local page want
  page="$(cat "$1/bin/.devbin/lib/pages/release.md")" || fail "the fixture holds no page for release"
  [ -n "$page" ] || fail "the fixture's page for release is empty, so any output would hold it"
  run devbin_run "$1" help release
  assert_success
  [[ "${output%%$'\n'*}" == "'bin/devbin release' is not offered here: devbin ships it but this project has not enabled it"* ]] ||
    fail "help release does not open with the not-offered line: $output"
  [ "${output#*$'\n'}" = $'\n'"$page" ] || fail "help release does not print the page whole after that line: $output"
  want="$output"
  run devbin_run "$1" release --help
  assert_success
  [ "$output" = "$want" ] || fail "release --help does not print what help release does: $output"
}

# AT-1.2
@test "release is absent, and refused as not enabled, in a project that has not asked for it" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
YAML
  )"
  run devbin_run "$proj" help
  assert_success
  refute_output_matches '(^|'$'\n'')  release '
  # A run is refused at exit 2, naming why; asking for its help is not refused:
  # `release --help` prints the page, as `help release` does (issue 0271).
  run devbin_run "$proj" release
  assert_exit_code 2
  assert_output_contains "devbin ships it"
  assert_output_contains "commands.release.enabled: true"
  _release_help_prints_page "$proj"
}

# AT-1.2
@test "a release: block does not enable release by being present" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
release:
  object: none
YAML
  )"
  # Refused at exit 2 when run, and its page printed when asked for with
  # --help, as in a project with no release: block (issue 0271).
  run devbin_run "$proj" release
  assert_exit_code 2
  assert_output_contains "commands.release.enabled: true"
  _release_help_prints_page "$proj"
}

# AT-1.2
@test "enabled: true offers release, and runs devbin's handler" {
  proj="$(enabled_project)"
  run devbin_run "$proj" help
  assert_success
  assert_output_matches '(^|'$'\n'')  release '
  run devbin_run "$proj" release --help
  assert_success
  assert_output_contains "usage:"
}

@test "release's usage names configuration.md in the docs/ of the install the project reads, and the file is there, or says why no install places it (0254)" {
  # It said "see docs/configuration.md", a path in a checkout a brew user has
  # not got. Homebrew's keg here, with the guides the formula installs beside
  # its README (brew_keg), is the install the project's upgrades read.
  local docs="$HOMEBREW_PREFIX/opt/devbin/docs"
  proj="$(enabled_project)"
  run devbin_run "$proj" release --help
  assert_success
  assert_output_contains "  configuration.md among devbin's guides, which are not here: this machine names no devbin install"
  refute_output_contains "docs/configuration.md"
  brew_keg --linked 0.1.0
  run devbin_run "$proj" release --help
  assert_success
  grep -qxF "  $docs/configuration.md." <<<"$output" || fail "release's usage does not name $docs/configuration.md: $output"
  [ -f "$docs/configuration.md" ] || fail "release's usage names $docs/configuration.md, which is not there"
}

@test "in the devbin checkout, release's usage names the checkout's own docs/configuration.md (0254)" {
  local docs
  docs="$(cd -P "$DEVBIN_HOME" && pwd -P)/docs"
  run bash -c "cd '$DEVBIN_HOME' && bin/devbin release --help"
  assert_success
  grep -qxF "  $docs/configuration.md." <<<"$output" || fail "release's usage does not name $docs/configuration.md: $output"
}

# ============================================================================
# THE ARGUMENT LOOP (AC-1.3)
# ============================================================================

# AT-1.3
@test "a bare release prints usage and exits 1" {
  proj="$(enabled_project)"
  run devbin_run "$proj" release
  [ "$status" -eq 1 ]
  assert_output_contains "usage:"
}

# AT-1.3
@test "--help or -h anywhere in any release invocation prints usage and changes no file, ref, remote or release object" {
  proj="$(enabled_project)"
  git_project "$proj"
  before="$(fingerprint "$proj")"
  local inv
  while IFS= read -r inv; do
    [ -n "$inv" ] || continue
    # shellcheck disable=SC2086  # each line is an argument list
    run release_in "$proj" $inv
    [ "$status" -eq 0 ] || {
      echo "release $inv exited $status: $output" >&2
      return 1
    }
    assert_output_contains "usage:"
    [ "$(fingerprint "$proj")" = "$before" ] || {
      echo "release $inv changed the repository, a remote or gh" >&2
      return 1
    }
  done <<'EOF'
--help
-h
--patch --help
--minor -h
--major --yes --help
v1.2.3 --help
1.2.3 -h
--dry-run --patch --help
--help --patch
status v1.0.0 --help
status --help
attach v1.0.0 --help
attach -h
notes -h
check --help
--bogus --help
v1.2.3 v1.2.4 -h
EOF
}

# AT-1.3
@test "--help is matched as a whole argument: --helpful is refused, not read as help" {
  proj="$(enabled_project)"
  run devbin_run "$proj" release status --helpful
  [ "$status" -eq 1 ]
  grep -qF -- 'demo: release: unknown argument: --helpful' <<<"$output" ||
    fail "the refusal did not name --helpful: $output"
}

# AT-1.3
@test "every refusal in the argument loop exits 1 naming the argument, before anything runs" {
  # THE REFUSAL LINE ALONE IS SEARCHED. refuse() prints usage first, and usage
  # itself contains --patch, --minor and `release notes`, so a search of the
  # whole output could not go red on those rows.
  #
  # AND ITS TEXT, NOT THE EXIT, IS WHAT HOLDS SOME ROWS, so this must never be
  # simplified to an exit check. Once `check` and `notes` are built (ST0007
  # WP-02), a broken --dry-run guard lets `release check --dry-run` run the
  # whole check, which exits 1 by itself because this fixture's version is
  # unreadable: only the missing refusal line fails that row. Measured on
  # WP-01 with WP-02 applied.
  proj="$(enabled_project)"
  git_project "$proj"
  before="$(fingerprint "$proj")"
  local args want refusal
  while IFS='|' read -r args want; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086
    run release_in "$proj" $args
    [ "$status" -eq 1 ] || {
      echo "release $args exited $status, want 1: $output" >&2
      return 1
    }
    refusal="$(printf '%s\n' "$output" | grep -F 'demo: release: ' || true)"
    [ -n "$refusal" ] || fail "release $args printed no refusal line: $output"
    grep -qF -- "$want" <<<"$refusal" ||
      fail "release $args refused with '$refusal', want: $want"
  done <<'EOF'
--bogus|unknown argument: --bogus
--patch --minor|one target only, got --patch and --minor
--patch v1.2.3|one target only, got --patch and v1.2.3
v1.2|not a version: v1.2
v1.2.3.4|not a version: v1.2.3.4
status|release status needs a version
status v1.0|not a version: v1.0
status v1.0.0 v1.0.1|release status takes one version, got 1.0.0 and v1.0.1
status --patch|--patch is a cut's target, and this is release status
check --patch|--patch is a cut's target, and this is release check
status v1.0.0 --dry-run|--dry-run applies to a cut, not to release status
check --dry-run|--dry-run applies to a cut, not to release check
notes --yes|--yes applies to a cut, not to release notes
notes v1.2.3|release notes takes no argument, got: v1.2.3
check notes|release check takes no argument, got: notes
attach|release attach needs a version
attach v1.0|not a version: v1.0
attach v1.0.0 v1.0.1|release attach takes one version, got 1.0.0 and v1.0.1
attach --patch|--patch is a cut's target, and this is release attach
attach v1.0.0 --dry-run|--dry-run applies to a cut, not to release attach
--dry-run|a cut needs a target
--yes|a cut needs a target
EOF
  [ "$(fingerprint "$proj")" = "$before" ]
}

# AT-1.3
# A well-formed cut ACTS since WP-04, so the "not built yet" row left this list;
# releasecut.bats holds the cut, the steps from resolve to gates.

# ============================================================================
# THE SCHEMA AND ITS DEFAULTS (AC-1.1)
# ============================================================================

# AT-1.1
@test "devbin's own declaration validates" {
  cfg_load_string <<'YAML'
project:
  name: devbin
commands:
  release:
    enabled: true
release:
  notes:
    kind: releases
  gates:
    - test all
    - check all
    - doctor
  object: ci
YAML
  run cfg_validate
  assert_success
}

# AT-1.1
@test "every release key validates at its documented default, each in a mode that reads it (0240)" {
  # A block for each mode that reads keys of its own, because the cross-key
  # rules refuse a key the declared mode never reads: notes.run needs
  # notes.kind: command, object_wait object: ci, and the snapshot's and the
  # publish keys snapshot.list (issue 0239). Between them the blocks name every
  # row of the table, and the loop after them holds that to the table's own rows
  # (ST0008 WP-08: repo was in none).
  local block shape key all="" declared
  local -a blocks=(
    '  tag: "v{version}"\n  remotes:\n    - origin\n  branch: main\n  notes:\n    kind: changelog\n  derived:\n    - cargo update --workspace\n  gates:\n    - check all\n    - test all\n  ci:\n    query: bin/ci-state\n    wait: 20m\n    tag: true\n    base: false\n  object: local\n  title: "{tag}"\n  repo: owner/name\n  after:\n    - bin/announce\n  verbs:\n    - cut\n    - status\n    - notes\n    - check\n    - attach\n  assets:\n    workflow: linux-release.yml\n    wait: 30m'
    '  notes:\n    kind: command\n    run: bin/release-notes'
    '  object: ci\n  object_wait: 20m'
    '  snapshot:\n    list: tests/shipped.paths\n    author: "A B <a@b>"\n    message: "{name} {version}"\n  publish:\n    url: https://example.com/o/n.git\n    branch: main\n    candidate: candidate/{tag}'
  )
  for block in "${blocks[@]}"; do
    cfg_load_string <<YAML
project:
  name: demo
release:
$(printf '%b' "$block")
YAML
    run cfg_validate
    [ "$status" -eq 0 ] || fail "refused: $(printf '%b' "$block") -- $output"
    # The keys this block declares, as their paths, list items by the list.
    declared="$(cfg_dump | awk -F'\t' '$1 ~ /^release\./ { k = substr($1, 9); sub(/\.[0-9]+$/, "", k); print k }')"
    all+="$declared"$'\n'
  done
  while read -r shape key _; do
    [ -n "$shape" ] || continue
    grep -qxF -- "$key" <<<"$all" || fail "no block declares release.$key, a row of the table"
  done <<<"$_DEVBIN_RELEASE_SCHEMA"
}

# AT-1.1
@test "with no release: block, every key reads its default (0240)" {
  cfg_load_string <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
YAML
  cfg_validate
  # EACH READ IS CAPTURED BEFORE IT IS COMPARED. `[ "$(reader)" = "" ]` passes
  # when the reader fails and prints nothing, because `[` never sees the
  # substitution's status; an assignment does, and errexit stops the test.
  local v
  v="$(cfg_release_get tag)"
  [ "$v" = "v{version}" ]
  v="$(cfg_release_get branch)"
  [ "$v" = main ]
  v="$(cfg_release_get notes.kind)"
  [ "$v" = changelog ]
  v="$(cfg_release_get notes.run)"
  [ -z "$v" ]
  v="$(cfg_release_get ci.query)"
  [ -z "$v" ]
  v="$(cfg_release_get ci.wait)"
  [ "$v" = 20m ]
  v="$(cfg_release_get object)"
  [ "$v" = local ]
  v="$(cfg_release_get title)"
  [ "$v" = "{tag}" ]
  v="$(cfg_release_get object_wait)"
  [ "$v" = 20m ]
  v="$(cfg_release_list gates)"
  [ "$v" = "check all
test all" ]
  v="$(cfg_release_list remotes)"
  [ -z "$v" ]
  v="$(cfg_release_list derived)"
  [ -z "$v" ]
  v="$(cfg_release_list after)"
  [ -z "$v" ]
  v="$(cfg_release_list verbs)"
  [ "$v" = "cut
status
notes
check
attach
snapshot
publish" ]
  v="$(cfg_release_get publish.candidate)"
  [ "$v" = "candidate/{tag}" ]
  v="$(cfg_release_get assets.workflow)"
  [ -z "$v" ]
  v="$(cfg_release_get assets.wait)"
  [ "$v" = 30m ]
}

# AT-1.1
@test "a declared key overrides its default, and a list declared as - is explicitly empty" {
  cfg_load_string <<'YAML'
project:
  name: demo
release:
  tag: "{version}"
  gates:
    - "-"
  remotes:
    - upstream
    - local
YAML
  cfg_validate
  local v
  v="$(cfg_release_get tag)"
  [ "$v" = "{version}" ]
  v="$(cfg_release_list gates)"
  [ -z "$v" ]
  v="$(cfg_release_list remotes)"
  [ "$v" = "upstream
local" ]
}

# AT-1.1
@test "the schema reads the same under a strict-mode IFS, or an empty one" {
  # A table split with read, and a list of indices split from cfg_list, both
  # take on the caller's IFS -- the hole _word_in had until issue 0066's review.
  # Two items, so a list that arrives as one index is visible. Each read goes to
  # a file because `$(...)` in the test would split nothing either way.
  #
  # THE EMPTY-IFS PASS IS THE ONE THAT HOLDS THE PINS in cfg_release_list and
  # _cfg_release_problems: under `$'\n\t'` the indices still split on newline.
  local ifs q out="$DEVBIN_TEST_TMPDIR/read"
  for ifs in $'\n\t' ''; do
    q="$(printf '%q' "$ifs")"
    cfg_load_string <<'YAML'
project:
  name: demo
release:
  object: none
  gates:
    - test all
    - check all
YAML
    IFS="$ifs" cfg_validate || fail "a valid block failed validation under IFS=$q"
    IFS="$ifs" cfg_release_get tag >"$out"
    [ "$(cat "$out")" = "v{version}" ] || fail "tag under IFS=$q: $(cat "$out")"
    IFS="$ifs" cfg_release_get object >"$out"
    [ "$(cat "$out")" = none ] || fail "object under IFS=$q: $(cat "$out")"
    IFS="$ifs" cfg_release_list gates >"$out"
    [ "$(cat "$out")" = "test all
check all" ] || fail "gates under IFS=$q: $(cat "$out")"

    cfg_load_string <<'YAML'
project:
  name: demo
release:
  after:
    - "-"
    - bin/announce
YAML
    if IFS="$ifs" cfg_validate 2>"$out"; then
      fail "a - beside another item in after: was accepted under IFS=$q"
    fi
    grep -qF 'release.after: "-" declares the list empty' "$out" ||
      fail "the refusal did not name release.after under IFS=$q: $(cat "$out")"
  done
}

# AT-1.1
@test "a - beside another item is refused under pipefail, however large the other item" {
  # The refusal read the items through a pipeline ending in `grep -q`. Under
  # pipefail, which every handler sets, a grep matching on the first line exits
  # before the writer finishes, the writer takes SIGPIPE, and the failed pipeline
  # skipped the refusal. An item larger than any pipe buffer makes that certain:
  # measured at 100 KB, accepted 3 of 3 with pipefail on and refused
  # 3 of 3 with it off, one variable apart.
  local big
  printf -v big '%*s' 100000 ''
  big="check ${big// /x}"
  cfg_load_string <<YAML
project:
  name: demo
release:
  gates:
    - "-"
    - $big
YAML
  set -o pipefail
  run cfg_validate
  set +o pipefail
  [ "$status" -ne 0 ] || fail "a - beside a ${#big}-byte gate was accepted under pipefail"
  assert_output_contains 'release.gates: "-" declares the list empty'
}

# AT-1.1
@test "the reader refuses a key the release schema does not have, and a key read in the wrong shape, saying which" {
  cfg_load_string <<'YAML'
project:
  name: demo
YAML
  run cfg_release_get bump
  assert_failure
  assert_output_contains "the release: schema has no key: bump"
  run cfg_release_get gates
  assert_failure
  assert_output_contains "release.gates is a list, not a scalar"
  run cfg_release_list tag
  assert_failure
  assert_output_contains "release.tag is a scalar, not a list"
}

# AT-1.1
@test "every value refusal in the release schema names the key and the reason" {
  # THE THREE DURATION ROWS ARE NOT REPEATS. "20 minutes" is refused as a word,
  # "20" holds the unit as required, and "1h20m" holds both anchors: without ^
  # the pattern finds 20m in it, and without $ it finds 1h.
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    cfg_load_string <<YAML
project:
  name: demo
release:
$(printf '%b' "$block")
YAML
    run cfg_validate
    [ "$status" -ne 0 ] || {
      echo "accepted: $block" >&2
      return 1
    }
    grep -qF -- "$want" <<<"$output" || {
      echo "for $block, want: $want -- got: $output" >&2
      return 1
    }
  done <<'EOF'
  bump: patch|unknown key: release.bump
  notes:\n    path: CHANGELOG.md|unknown key: release.notes.path
  tag: release-1|release.tag: "release-1" must contain {version}
  branch: ""|release.branch: "" is empty
  notes:\n    kind: markdown|release.notes.kind: "markdown" must be changelog, releases or command
  notes:\n    kind: command|release.notes.run is required under notes.kind: command
  notes:\n    run: bin/notes|release.notes.run is read only under notes.kind: command
  object: github|release.object: "github" must be local, ci or none
  object: ci\n  title: devbin {version}|release.title is read only under object: local
  object_wait: 5m|release.object_wait is read only under object: ci
  object: none\n  repo: acme/widgets|release.repo is read only under object: local or ci
  repo: widgets|release.repo: "widgets" must be OWNER/NAME or HOST/OWNER/NAME
  object: ci\n  object_wait: soon|release.object_wait: "soon" must be a whole number of s, m or h
  ci:\n    query: bin/ci\n    wait: 20 minutes|release.ci.wait: "20 minutes" must be a whole number of s, m or h
  ci:\n    query: bin/ci\n    wait: "20"|release.ci.wait: "20" must be a whole number of s, m or h
  ci:\n    query: bin/ci\n    wait: 1h20m|release.ci.wait: "1h20m" must be a whole number of s, m or h
  ci:\n    wait: 10m|release.ci.wait is read only when release.ci.query is declared
  ci:\n    query: ""|release.ci.query: "" is empty
  ci:\n    base: true|release.ci.base is read only when release.ci.query is declared
  ci:\n    query: bin/ci\n    base: maybe|release.ci.base: "maybe" is not a yes or a no
  ci:\n    tag: false|release.ci.tag is read only when release.ci.query is declared
  ci:\n    query: bin/ci\n    tag: later|release.ci.tag: "later" is not a yes or a no
  ci:\n    query: bin/ci\n    tag: false|release.ci.query is never asked: ci.tag is off and ci.base is off
  gates:\n    - ""|release.gates.0: "" is empty
  gates:\n    - "-"\n    - test all|release.gates: "-" declares the list empty, so it must be the only item
  after:\n    - ""|release.after.0: "" is empty
  gates:\n    first: check all|unknown key: release.gates.first
  tag:\n    0: x|unknown key: release.tag.0
  remotes:\n    - "-"|release.remotes: "-" would push the release to no remote
  remotes:\n    - "-"\n    - origin|release.remotes: "-" declares the list empty, so it must be the only item
EOF
}

# reference_values -- `<path><TAB><value>` for each key the reference config's
# release: block shows with a value, live or in a comment, its path under
# release:. A key in a comment nests where uncommenting it would put it, the
# `# ` dropped, as documentation.bats reads them: so `#   wait:` under `# ci:`
# is ci.wait and under `# assets:` is assets.wait. Read by PATH since ST0008
# WP-08, which added a second leaf named `wait` with another default: read by
# its leaf, each would have been compared with the other's line.
reference_values() {
  awk '
    /^release:/ { f = 1; next }
    f && /^[a-z]/ { exit }
    f {
      line = $0
      if (match(line, /^ *# /)) line = substr(line, 1, RLENGTH - 2) substr(line, RLENGTH + 1)
      if (line !~ /^ +[a-z_]+:/) next
      match(line, /^ +/)
      ind = RLENGTH
      k = line; sub(/^ +/, "", k); sub(/:.*$/, "", k)
      v = line; sub(/^ +[a-z_]+:[ \t]*/, "", v); sub(/^#.*$/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/"/, "", v)
      if (ind == 2) { parent = k; path = k } else if (ind == 4) path = parent "." k; else next
      if (v != "") print path "\t" v
    }
  ' "$DEVBIN_LIB_DIR/config.reference.yaml"
}

# AT-1.1
@test "the reference config's release block shows every scalar with a default at the default the reader uses" {
  # Keys the default mode never reads are shown commented out, since declaring
  # them is refused, so each value is read from the block's text either way.
  #
  # THE KEYS COME FROM THE TABLE, and the count they are held to comes from the
  # table's TEXT, read separately. A typed key list restated which keys have
  # defaults, and its `n -eq 7` could not fail. A row
  # is shape, key, readers and default (ST0008 WP-08), so one with a default
  # has every one of them.
  cfg_load "$DEVBIN_LIB_DIR/config.reference.yaml"
  cfg_validate
  local values shape key def v n=0 want
  values="$(reference_values)"
  want="$(awk '/^_DEVBIN_RELEASE_SCHEMA="/ { f = 1; next } f && /^"/ { f = 0 } f && $1 == "scalar" && NF >= 4 { c++ } END { print c + 0 }' "$DEVBIN_LIB_DIR/config")"
  [ "$want" -ge 1 ] || fail "the table's text shows no scalar with a default"
  while read -r shape key _ def; do
    [ "$shape" = scalar ] && [ -n "$def" ] || continue
    v="$(awk -F'\t' -v k="$key" '$1 == k { print $2; exit }' <<<"$values")"
    [ -n "$v" ] || fail "lib/config.reference.yaml does not show release.$key"
    [ "$v" = "$def" ] || fail "release.$key: the reference shows $v, the table defaults to $def"
    n=$((n + 1))
  done <<<"$_DEVBIN_RELEASE_SCHEMA"
  [ "$n" -eq "$want" ] || fail "compared $n scalar defaults; the table's text has $want"
  v="$(cfg_release_list gates)"
  [ "$v" = "$(_cfg_release_default gates | tr '|' '\n')" ]
  [ -n "$(cfg_list release.gates)" ]
}

# ============================================================================
# release check -- THE DECLARATION HALF
# ============================================================================

# AT-1.1
@test "release check prints every key with its value and whether it is declared or the default, then checks the notes" {
  # check is a predicate over the declaration AND the notes, so the notes
  # half runs after the table (WP-02) and the exit status answers for both.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  object: none
  gates:
    - "-"
YAML
  )"
  with_dated_note "$proj"
  run devbin_run "$proj" release check
  assert_success
  # One line per row of the table, the rows read from the table, not typed.
  local shape key n=0
  while read -r shape key _; do
    [ -n "$shape" ] || continue
    grep -qE "^  ${key//./\\.} " <<<"$output" || fail "release check printed no line for $key: $output"
    n=$((n + 1))
  done <<<"$_DEVBIN_RELEASE_SCHEMA"
  [ "$n" -ge 1 ] || fail "the table read no rows"
  assert_output_matches 'object +none +declared'
  assert_output_matches 'gates +\(none\) +declared'
  assert_output_matches 'tag +v\{version\} +default'
  assert_output_matches 'remotes +every remote git lists +default'
  assert_output_contains "the note for 1.0.0 is dated 2026-01-01"
  refute_output_contains "not built yet"
}

# AT-1.1
@test "release check fails on a malformed release: block, naming the key" {
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  object: github
YAML
  )"
  # A version and its note, so the declaration is the only thing here that can
  # fail: without them the notes half exits 1 too, and the status would pass
  # whether or not the bad declaration is what stopped check.
  with_dated_note "$proj"
  run devbin_run "$proj" release check
  [ "$status" -eq 1 ]
  assert_output_contains 'release.object: "github" must be local, ci or none'
  # And it stopped there: a declaration that does not validate is never read on
  # into the notes half as though it had.
  refute_output_contains "the note for 1.0.0"
}

# AT-1.1
@test "release check warns when a tag-triggered workflow calls gh release and object is local, and not under object: ci" {
  proj="$(enabled_project)"
  mkdir -p "$proj/.github/workflows"
  cat >"$proj/.github/workflows/release.yml" <<'YML'
on:
  push:
    tags: ["v*"]
jobs:
  release:
    steps:
      - run: gh release create "$GITHUB_REF_NAME"
YML
  # A version and its note, so the notes half passes and the exit status is the
  # declaration's: the WARNING is reported for the project to decide, not failed.
  with_dated_note "$proj"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "WARNING"
  assert_output_contains ".github/workflows/release.yml"
  printf 'release:\n  object: ci\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" release check
  assert_success
  assert_output_matches 'object +ci +declared'
  refute_output_contains "WARNING"
}

# AT-1.1
@test "release check names a workflow it could not read, rather than reading it as no second writer" {
  # grep exits 2 on a file it cannot read, and `|| continue` took that for "no
  # match", so the silence said there was no second writer when nobody had
  # looked.
  proj="$(enabled_project)"
  mkdir -p "$proj/.github/workflows"
  printf 'on:\n  push:\n    tags: ["v*"]\n' >"$proj/.github/workflows/release.yml"
  chmod 000 "$proj/.github/workflows/release.yml"
  if [ -r "$proj/.github/workflows/release.yml" ]; then
    chmod 644 "$proj/.github/workflows/release.yml"
    skip "this user can read a mode-000 file, so grep cannot fail to read one here"
  fi
  # A version and its note, so the notes half passes and the status is the
  # declaration's: an unread workflow is a WARNING, reported rather than failed.
  with_dated_note "$proj"
  run devbin_run "$proj" release check
  chmod 644 "$proj/.github/workflows/release.yml"
  assert_success
  assert_output_contains "could not read .github/workflows/release.yml"
}

# ============================================================================
# release.verbs -- THE VERBS A PROJECT OFFERS (ST0008 WP-08, AC-8.1)
# ============================================================================

# verbs_project <verb>... -- a project offering those verbs of release alone,
# whose release: block also declares `object: github`, which no verb could
# validate: so an arm that gets past the verb refusal fails on that instead.
verbs_project() {
  local v items=""
  for v in "$@"; do items+="    - $v"$'\n'; done
  mkproj demo <<YAML
project:
  name: demo
commands:
  release:
    enabled: true
release:
  object: github
  verbs:
$items
YAML
}

# AT-8.1
@test "a release.verbs that does not validate fails as config, exit 1, never as a verb switched off, exit 2 (0240)" {
  # A misspelt verb, and "-", each leave a verb out of the list; read as a
  # list, the verb would be refused as switched off, and a script passing over
  # what is switched off would pass over a broken config.
  local items want
  while IFS='|' read -r items want; do
    [ -n "$items" ] || continue
    proj="$(mkproj demo <<YAML
project:
  name: demo
commands:
  release:
    enabled: true
release:
  verbs:
$(printf '%b' "$items")
YAML
    )"
    run devbin_run "$proj" release attach v1.0.0
    [ "$status" -eq 1 ] || fail "verbs $items: release attach exited $status, want 1: $output"
    assert_output_contains "release.verbs in $proj/bin/.devbin/config.yaml does not validate (above)"
    assert_output_contains "$want"
    refute_output_contains "is not available here"
  done <<'EOF2'
    - check\n    - atach|release.verbs.1: "atach" must be one of cut, status, notes, check, attach, snapshot, publish
    - "-"|release.verbs: "-" would offer no verb
EOF2
}

# AT-8.1
@test "a verb release.verbs leaves out is refused at exit 2, before anything else is read, naming the verb and the list" {
  proj="$(verbs_project check attach)"
  git_project "$proj"
  before="$(fingerprint "$proj")"
  local args verb
  while IFS='|' read -r args verb; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086  # each line is an argument list
    run release_in "$proj" $args
    [ "$status" -eq 2 ] || fail "release $args exited $status, want 2: $output"
    assert_output_contains "demo: release: $verb is not available here: release.verbs offers check, attach"
    # Before validation, which refuses object: github, and before every read.
    refute_output_contains "does not validate"
  done <<'EOF2'
v1.2.3|cut
--patch --dry-run|cut
status v1.0.0|status
status|status
notes|notes
EOF2
  [ "$(fingerprint "$proj")" = "$before" ] || fail "a refused verb wrote or read through gh"
  [ ! -e "$DEVBIN_TEST_TMPDIR/gh.calls" ] || fail "a refused verb called gh: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  # THE CONTROL: an offered verb is not refused, and reaches the validation.
  run release_in "$proj" check
  [ "$status" -eq 1 ] || fail "release check exited $status: $output"
  assert_output_contains 'release.object: "github" must be local, ci or none'
}

# AT-8.1
@test "usage prints only the verbs release.verbs offers, and every verb when it is undeclared" {
  proj="$(verbs_project check attach)"
  run devbin_run "$proj" release --help
  assert_success
  assert_output_contains "release check"
  assert_output_contains "release attach <vX.Y.Z>"
  assert_output_contains "release.verbs offers check, attach"
  refute_output_contains "--patch"
  refute_output_contains "release status"
  refute_output_contains "release notes"
  refute_output_contains "Cut a release"
  proj="$(enabled_project)"
  run devbin_run "$proj" release --help
  assert_success
  assert_output_contains "release <--patch|--minor|--major|vX.Y.Z> [--dry-run] [--yes]"
  assert_output_contains "release status <vX.Y.Z>"
  assert_output_contains "release notes"
  assert_output_contains "release check"
  assert_output_contains "release attach <vX.Y.Z>"
  refute_output_contains "release.verbs offers"
}

# AT-8.1
@test "an item of release.verbs that is not one of the verbs, or the - that would offer none, is refused at validation, by name (0240)" {
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    cfg_load_string <<YAML
project:
  name: demo
release:
$(printf '%b' "$block")
YAML
    run cfg_validate </dev/null
    [ "$status" -ne 0 ] || fail "accepted: $block"
    assert_output_contains "$want"
  done <<'EOF2'
  verbs:\n    - cut\n    - ship|release.verbs.1: "ship" must be one of cut, status, notes, check, attach, snapshot, publish
  verbs:\n    - "-"|release.verbs: "-" would offer no verb -- a release with none is commands.release.enabled: false
  verbs:\n    - "-"\n    - check|release.verbs: "-" declares the list empty, so it must be the only item
EOF2
  # THE CONTROL: each verb alone validates.
  local v
  while IFS= read -r v; do
    cfg_load_string <<YAML
project:
  name: demo
release:
  verbs:
    - $v
YAML
    run cfg_validate </dev/null
    [ "$status" -eq 0 ] || fail "verbs: [$v] refused: $output"
  done <<<"$(cfg_release_verbs)"
}

# AT-8.1
@test "a release key no offered verb reads is refused as unread config, read from the table's readers column (0240)" {
  # With the cut and status off, the keys only they read are refused; the ones
  # check and attach read are not; remotes is read by attach only while repo is
  # undeclared, so with repo declared it is refused too.
  local block want
  while IFS='|' read -r block want; do
    [ -n "$block" ] || continue
    cfg_load_string <<YAML
project:
  name: demo
release:
  verbs:
    - check
    - attach
$(printf '%b' "$block")
YAML
    run cfg_validate </dev/null
    if [ -z "$want" ]; then
      [ "$status" -eq 0 ] || fail "refused: $block -- $output"
    else
      [ "$status" -ne 0 ] || fail "accepted: $block"
      assert_output_contains "$want, and release.verbs offers check, attach"
    fi
  done <<'EOF2'
  gates:\n    - check all|release.gates is read only by cut and status
  derived:\n    - x|release.derived is read only by cut
  after:\n    - y|release.after is read only by cut, status and publish
  ci:\n    query: q|release.ci.query is read only by cut, status and publish
  title: t|release.title is read only by cut, status and publish
  branch: main|release.branch is read only by cut, status, snapshot while release.publish.branch is not declared and publish while release.publish.branch is not declared
  object: ci\n  object_wait: 5m|release.object_wait is read only by cut and publish
  repo: a/b\n  remotes:\n    - origin|release.remotes is read only by cut, status and attach while release.repo is not declared
  remotes:\n    - origin|
  tag: "{version}"\n  notes:\n    kind: releases\n  object: local\n  repo: a/b\n  assets:\n    workflow: x.yml\n    wait: 5m|
EOF2
}

# AT-8.1
@test "every row of the release table names its readers, each a verb from release.verbs' own default, and each condition a key of the table" {
  local shape key readers r v n=0 verbs keys
  local -a rs
  verbs=" $(cfg_release_verbs | tr '\n' ' ') "
  keys=" $(awk '/^_DEVBIN_RELEASE_SCHEMA="/ { f = 1; next } f && /^"/ { f = 0 } f && NF >= 3 { printf "%s ", $2 }' "$DEVBIN_LIB_DIR/config") "
  [ "$verbs" != "  " ] || fail "cfg_release_verbs named no verb"
  while read -r shape key readers _; do
    [ -n "$shape" ] || continue
    n=$((n + 1))
    [ -n "$readers" ] || fail "release.$key names no reader"
    IFS=',' read -r -a rs <<<"$readers"
    for r in "${rs[@]}"; do
      v="${r%%!*}"
      [[ "$verbs" == *" $v "* ]] || fail "release.$key: $v, in its readers, is not a verb of release"
      [ "$r" = "$v" ] || [[ "$keys" == *" ${r#*!} "* ]] || fail "release.$key: ${r#*!}, in its readers, is not a key of the table"
    done
  done <<<"$_DEVBIN_RELEASE_SCHEMA"
  [ "$n" -ge 1 ] || fail "the table read no rows"
}

# ============================================================================
# release check -- THE WRITERS (ST0008 WP-08, AC-8.3)
# ============================================================================

# workflow_files <dir> -- how many workflow files an arm wrote into <dir>, each
# a *.yml or *.yaml, as release check reads them: the count its pass line names
# comes from the fixture, never from a number written beside it.
workflow_files() {
  local f n=0
  for f in "$1"/*.yml "$1"/*.yaml; do
    if [ -f "$f" ]; then n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

# AT-8.3
@test "release check names a release written by hub, by the releases API from a script step, or by goreleaser's action" {
  proj="$(enabled_project)"
  with_dated_note "$proj"
  local w="$proj/.github/workflows"
  mkdir -p "$w"
  printf '%s\n' 'on: push' 'jobs:' '  mk:' '    steps:' '      - run: hub release create -m v1 v1' >"$w/hub.yml"
  printf '%s\n' 'on: push' 'jobs:' '  mk:' '    steps:' '      - uses: actions/github-script@v7' '        with:' '          script: await github.rest.repos.createRelease({ owner, repo, tag_name })' >"$w/script.yml"
  printf '%s\n' 'on: push' 'jobs:' '  mk:' '    steps:' '      - uses: goreleaser/goreleaser-action@v6' '        with:' '          args: release --clean' >"$w/goreleaser.yml"
  run devbin_run "$proj" release check
  assert_success
  local n step
  local -a steps=(
    ".github/workflows/hub.yml:5 runs hub release create"
    ".github/workflows/script.yml:7 calls the releases API (createRelease)"
    ".github/workflows/goreleaser.yml:5 uses goreleaser/goreleaser-action"
  )
  for step in "${steps[@]}"; do assert_output_contains "WARNING: $step, and object is local"; done
  n="$(workflow_files "$w")"
  assert_output_contains "release: read $n of $n workflow file(s) in .github/workflows: ${#steps[@]} release-writing step(s), named above"
}

# AT-8.3
@test "release check names every release-writing step by file and line, whatever starts its workflow, and the warning leaves the exit alone" {
  proj="$(enabled_project)"
  with_dated_note "$proj"
  local w="$proj/.github/workflows"
  mkdir -p "$w"
  printf '%s\n' 'on:' '  release:' '    types: [published]' 'jobs:' '  up:' '    steps:' '      - uses: softprops/action-gh-release@v2' >"$w/onrelease.yml"
  printf '%s\n' 'on: {push: {tags: ["v*"]}}' 'jobs:' '  up:' '    steps:' '      - run: gh release upload "$GITHUB_REF_NAME" dist/x' >"$w/flow.yml"
  printf '%s\n' 'on:' '  workflow_dispatch:' 'jobs:' '  mk:' '    steps:' '      - run: |' '          gh api -X POST repos/o/r/releases \' '            -f tag_name=v1' >"$w/dispatch.yaml"
  printf '%s\n' 'on: push' 'jobs:' '  mk:' '    steps:' '      - run: gh release \' '          create v1' >"$w/continued.yml"
  printf '%s\n' 'on: push' 'jobs:' '  t:' '    steps:' '      - run: bin/devbin test all' '      # - run: gh release create v1, commented out' >"$w/tests.yml"
  run devbin_run "$proj" release check
  assert_success
  local n step
  local -a steps=(
    ".github/workflows/onrelease.yml:7 uses softprops/action-gh-release"
    ".github/workflows/flow.yml:5 runs gh release upload"
    ".github/workflows/dispatch.yaml:7 calls gh api on a releases endpoint"
    ".github/workflows/continued.yml:5 runs gh release create"
  )
  for step in "${steps[@]}"; do assert_output_contains "WARNING: $step, and object is local"; done
  refute_output_contains "tests.yml"
  n="$(workflow_files "$w")"
  assert_output_contains "release: read $n of $n workflow file(s) in .github/workflows: ${#steps[@]} release-writing step(s), named above"
}

# AT-8.3
@test "on a pass release check says how many workflow files it read and that none writes a release object, and says so in its own words for none, no directory, and object: ci" {
  proj="$(enabled_project)"
  with_dated_note "$proj"
  local w="$proj/.github/workflows"
  mkdir -p "$w"
  printf '%s\n' 'on: push' 'jobs:' '  t:' '    steps:' '      - run: bin/devbin test all' >"$w/tests.yml"
  printf '%s\n' 'on: pull_request' 'jobs:' '  l:' '    steps:' '      - run: bin/devbin check all' >"$w/checks.yaml"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "release: read $(workflow_files "$w") workflow file(s) in .github/workflows, and none writes a release object"
  refute_output_contains "WARNING"
  rm "$w/tests.yml" "$w/checks.yaml"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "release: .github/workflows holds no workflow file, so none writes a release object"
  rmdir "$w"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "release: there is no .github/workflows here, so no workflow writes a release object"
  printf 'release:\n  object: ci\n' >>"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" release check
  assert_success
  assert_output_contains "release: object is ci, so the core makes no release object, and no second writer of one is looked for"
}

# AT-8.3
@test "a workflow release check could not read keeps its pass line from saying none writes a release object" {
  proj="$(enabled_project)"
  with_dated_note "$proj"
  local w="$proj/.github/workflows"
  mkdir -p "$w"
  printf '%s\n' 'on: push' 'jobs:' '  t:' '    steps:' '      - run: bin/devbin test all' >"$w/tests.yml"
  printf 'on:\n  push:\n    tags: ["v*"]\n' >"$w/release.yml"
  chmod 000 "$w/release.yml"
  if [ -r "$w/release.yml" ]; then
    chmod 644 "$w/release.yml"
    skip "this user can read a mode-000 file, so awk cannot fail to read one here"
  fi
  run devbin_run "$proj" release check
  chmod 644 "$w/release.yml"
  assert_success
  assert_output_contains "could not read .github/workflows/release.yml"
  # Every file but the one it could not read, which names no writer.
  local n
  n="$(workflow_files "$w")"
  assert_output_contains "release: read $((n - 1)) of $n workflow file(s) in .github/workflows: 0 release-writing step(s), named above, and 1 that could not be read"
  refute_output_contains "none writes a release object"
}

@test "a row for a name that is no release step dies as a defect, naming the steps, and prints no row (0209)" {
  # The steps are named, never numbered, so a row is asked for by name; a name
  # misspelt in the core must stop it, never print a row for no step.
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; release_row objekt already "x"' _ "$DEVBIN_LIB_DIR"
  assert_failure
  assert_output_contains "devbin defect: release_row was given 'objekt', which is no release step"
  refute_output_contains "already"
}

@test "release check's table sizes each column from what it prints, so every row's source stands at one column (0207)" {
  # assets.workflow is wider than the key column was written, and this after:
  # command is wider than any value the column was written for.
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  release:
    enabled: true
release:
  object: local
  gates:
    - "-"
  after:
    - bin/devbin some-long-command --with-an-argument --and-another-one
  assets:
    workflow: a-workflow-with-a-name-longer-than-any-value-today.yml
YAML
  )"
  with_dated_note "$proj"
  run devbin_run "$proj" release check
  local cols
  cols="$(awk '/^release: declaration/ { on = 1; next } on && /^  [a-z]/ && ($NF == "declared" || $NF == "default") { print length($0) - length($NF) } on && !/^  / { on = 0 }' <<<"$output" | sort -u)"
  [ -n "$cols" ] || fail "no declaration row was read:
$output"
  [ "$(grep -c . <<<"$cols")" -eq 1 ] || fail "the rows' source words stand at more than one column ($(tr '\n' ' ' <<<"$cols")):
$output"
}
