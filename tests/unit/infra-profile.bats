#!/usr/bin/env bats
# infra-profile.bats -- profile resolution and PARSE-TIME validation for `infra`
#
# WHAT IS UNDER TEST, and it is not "does a valid profile load". Every arm here
# is about the profile layer REFUSING something before any network call happens.
# `infra check` reads live DNS; a malformed profile that reaches it produces a
# verdict about an estate from an expectation nobody wrote. So the split is
# deliberate: a malformed PROFILE and a wrong ESTATE are different problems with
# different fixes, and conflating them is what makes a red unreadable.
#
# THE UNIQUENESS ARM IS THE ONE THAT EXISTS BECAUSE OF A FORMAT CHANGE. The
# agreed schema keyed domains by FQDN, and YAML keys are unique by construction,
# so "one entry per domain" was enforced by the format and nobody wrote it down.
# devbin's only YAML reader refuses dotted keys, so the FQDN moved from the KEY
# to a FIELD -- and the guarantee vanished silently with it. Two handles naming
# one FQDN can carry contradictory expectations, `check` would evaluate both
# against the same live records, and which verdict an operator reads becomes a
# matter of ordering. A profile that cannot be self-consistent is worse than one
# that fails to parse.

load "../lib/test_helper"

setup() {
  devbin_setup
  PROFILE_DIR="$BATS_TEST_TMPDIR/prof"
  mkdir -p "$PROFILE_DIR"
  INFRA="$DEVBIN_HOME/lib/cmd/infra"
}
teardown() { devbin_teardown; }

# --- resolution -------------------------------------------------------------
# --- the shipped reference profile ------------------------------------------
#
# THE WORKED EXAMPLE MOVED OUT OF PROSE AND INTO THE VENDORED HALF, and the move
# is the point rather than the tidying. It lived in `docs/infrastructure.md`,
# which is devbin's own repository and reaches no project: the projects that
# actually RUN `infra` could not read it. `lib/infra.reference.yaml` vendors to
# `bin/.devbin/lib/infra.reference.yaml` in every one of them, exactly as
# `lib/config.reference.yaml` already does.

# AT-1.11
@test "the shipped profile reference PARSES -- it is the first thing a reader copies" {
  # IT DID NOT, AND NOTHING HERE NOTICED. The flagship example was once written
  # in three forms this parser rejects -- flow collections
  # (`dmarc: { policy: none }`), flow sequences, and a `domains:` map keyed by
  # FQDN rather than by handle. Reported by a consumer on the first real use of
  # `infra`, not by any test here.
  #
  # PARSING THE FILE IS THE ONLY ASSERTION THAT CANNOT ROT. A test grepping for
  # forbidden punctuation would pass the day somebody invented a fourth way to
  # write it wrong. And the reference is a profile outright, so there is no
  # extraction step left to be broken -- the arm it replaces awk'd a fence out
  # of markdown and needed its own floor check to prove the extractor had
  # produced anything at all.
  local ref="$DEVBIN_HOME/lib/infra.reference.yaml"
  # NO `|| skip`, DELIBERATELY. The arm this replaces guarded the document with
  # `[ -f "$doc" ] || skip`, so deleting that document would have retired the
  # guard SILENTLY -- the population changing with nothing reporting it. A
  # missing reference is a FAILURE: it is vendored, so its absence reaches every
  # project.
  [ -f "$ref" ] || fail "lib/infra.reference.yaml is missing -- it is VENDORED, so its absence reaches every project"

  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$ref"
  assert_success
  refute_output_contains "flow collections are not supported"
  refute_output_contains "has no"
  # HANDLE AND FQDN BOTH, because keying `domains:` by FQDN is the specific
  # shape that shipped broken. `show` renders handle then name, so a reference
  # that regressed to FQDN keys would print the FQDN in both columns.
  assert_output_contains "partner"
  assert_output_contains "partner.example"
}

# AT-1.11
@test "the profile reference is VENDORED -- a project gets it, not just this repo" {
  # THE WHOLE REASON IT IS NOT A DOCUMENT. `docs/` reaches nobody but devbin's
  # own tree; the projects that run `infra` see only the vendored half.
  # If `vendored_paths` ever narrows, this says so instead of the reference
  # quietly becoming repo-local again.
  run bash -c ". '$DEVBIN_HOME/lib/helpers' && . '$DEVBIN_HOME/lib/install' && vendored_paths '$DEVBIN_HOME'"
  assert_success
  assert_output_contains "bin/.devbin/lib/infra.reference.yaml"
}


# --- the name a project actually types ---------------------------------------
#
# THESE ARMS CANNOT PASS AGAINST A HARDCODED LITERAL, and that is the whole
# point: inside this repository $DEVBIN_NAME IS `devbin`, so a hardcoded
# `usage: devbin infra` and a rendered one are byte-identical and no assertion
# made here could separate them. Setting a name that is NOT devbin is the only
# way to ask the question. Found by running `infra --help` in a consumer, where
# the dispatcher is the project's own name and `devbin` resolves to nothing -- the top
# level told the reader to type a command the project does not have, while this
# command's own children already rendered the name correctly.

# AT-1.9
@test "usage names how to invoke the dispatcher, DEVBIN_INVOKE, not the project's name (issue 0107)" {
  # An earlier form printed $DEVBIN_NAME, which named the per-project launcher
  # a project no longer has. The rule: infra says bin/devbin, as every other
  # built-in does, so the name is DEVBIN_INVOKE.
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" DEVBIN_NAME=notdevbin DEVBIN_INVOKE=/x/bin/devbin \
    HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" --help
  assert_success
  assert_output_contains "usage: /x/bin/devbin infra"
  refute_output_contains "notdevbin infra"
}

# AT-1.9
@test "with no DEVBIN_INVOKE, usage says bin/devbin (issue 0107)" {
  run env -u DEVBIN_INVOKE DEVBIN_LIB="$DEVBIN_HOME/lib" DEVBIN_NAME=notdevbin \
    HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" --help
  assert_success
  assert_output_contains "usage: bin/devbin infra"
}

# AT-1.9
@test "the unknown-verb refusal names DEVBIN_INVOKE too (issue 0107)" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" DEVBIN_NAME=notdevbin DEVBIN_INVOKE=/x/bin/devbin \
    HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" nosuchverb
  assert_failure
  assert_output_contains "try: /x/bin/devbin infra --help"
}

# AT-1.9
@test "every infra.d child's usage and refusals name DEVBIN_INVOKE, never the project's name (issue 0107)" {
  local child args
  for row in "init|--help" "init|--nosuch" "mail|--help" "mail|nosuch" \
    "mail.d/dmarc|--help" "mail.d/dmarc|nosuch" "profiles|--help"; do
    child="${row%%|*}"
    args="${row#*|}"
    run env DEVBIN_LIB="$DEVBIN_HOME/lib" DEVBIN_NAME=notdevbin DEVBIN_INVOKE=/x/bin/devbin \
      HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" \
      "$DEVBIN_HOME/lib/cmd/infra.d/$child" "$args"
    assert_output_contains "/x/bin/devbin infra"
    refute_output_contains "notdevbin infra"
  done
}

# AT-1.2
@test "unquoting the usage heredoc must not eat the profile env var" {
  # THE SECOND DEFECT THE OBVIOUS FIX INTRODUCES. Making the heredoc expand
  # $DEVBIN_NAME also expands $DEVBIN_INFRA_PROFILE, which is unset, so the help
  # renders `--profile <path>, , ./infra.yaml` -- a resolution step silently
  # dropped from the text that documents resolution. Measured before the fix
  # landed. The escape is what keeps it literal, and this is what keeps the
  # escape.
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" DEVBIN_NAME=notdevbin \
    HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" --help
  assert_success
  assert_output_contains "\$DEVBIN_INFRA_PROFILE"
}

# _usage_reference_exists <project root> <devbin lib> -- every path to
# infra.reference.yaml that `infra --help` names must exist under the project
# root. The count is asserted as well: an extractor that finds nothing would
# pass every tree.
_usage_reference_exists() {
  local root="$1" lib="$2" p n=0
  run env DEVBIN_LIB="$lib" HOME="$BATS_TEST_TMPDIR/home" PROJECT_ROOT="$root" "$INFRA" --help
  assert_success
  for p in $(printf '%s\n' "$output" | grep -oE '[A-Za-z0-9_./-]*infra\.reference\.yaml'); do
    n=$((n + 1))
    [ -e "$root/$p" ] || fail "infra --help names $p, which does not exist under $root"
  done
  [ "$n" -ge 1 ] || fail "found $n reference paths in the usage -- the extractor would compare nothing"
}

@test "usage: the reference path it names EXISTS, in an install (0121)" {
  local proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/bin/.devbin"
  ln -s "$DEVBIN_HOME/lib" "$proj/bin/.devbin/lib"
  _usage_reference_exists "$proj" "$proj/bin/.devbin/lib"
}

@test "usage: the reference path it names EXISTS, in the devbin checkout too (0121)" {
  # It spelled bin/.devbin/lib/infra.reference.yaml, which names nothing in
  # devbin's own checkout, where lib/ runs in place -- the shape 0112 fixed in
  # `devbin devbin` with lib_rel.
  _usage_reference_exists "$DEVBIN_HOME" "$DEVBIN_HOME/lib"
}


# AT-1.2
# AT-1.3
@test "a missing profile names EVERY path it tried, not just the last" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show
  assert_failure
  assert_output_contains "DEVBIN_INFRA_PROFILE"
  assert_output_contains "infra.yaml"
  assert_output_contains ".config/devbin"
}

# _machine_profile <file> -- a valid profile named `the-machine` at <file>.
_machine_profile() {
  mkdir -p "${1%/*}"
  cat >"$1" <<'Y'
version: 1
name: the-machine
domains:
  a:
    name: a.example
Y
}

@test "the machine-wide profile is devbin/infra.yaml under an absolute XDG_CONFIG_HOME, found there and named in the search order (0272)" {
  local xdg="$BATS_TEST_TMPDIR/xdg"
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$xdg" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show
  assert_failure
  assert_output_contains "$xdg/devbin/infra.yaml"
  refute_output_contains "$BATS_TEST_TMPDIR/home/.config/devbin"
  _machine_profile "$xdg/devbin/infra.yaml"
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$xdg" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show
  assert_success
  assert_output_contains "$xdg/devbin/infra.yaml"
  assert_output_contains the-machine
}

@test "with XDG_CONFIG_HOME empty or relative, the machine-wide profile is ~/.config/devbin/infra.yaml, as before (0272)" {
  local home="$BATS_TEST_TMPDIR/home" x
  _machine_profile "$home/.config/devbin/infra.yaml"
  for x in "" relative/xdg; do
    run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$home" XDG_CONFIG_HOME="$x" \
      PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show
    assert_success
    assert_output_contains "$home/.config/devbin/infra.yaml"
    assert_output_contains the-machine
  done
}

# AT-1.2
@test "an explicit --profile that does not exist fails naming THAT path, not the search" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile /nope/absent.yaml
  assert_failure
  assert_output_contains "/nope/absent.yaml"
}

# AT-1.2
@test "--profile beats DEVBIN_INFRA_PROFILE" {
  cat > "$PROFILE_DIR/flag.yaml" <<'Y'
version: 1
name: from-flag
domains:
  a:
    name: a.example
Y
  cat > "$PROFILE_DIR/env.yaml" <<'Y'
version: 1
name: from-env
domains:
  a:
    name: a.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" \
    DEVBIN_INFRA_PROFILE="$PROFILE_DIR/env.yaml" \
    "$INFRA" show --profile "$PROFILE_DIR/flag.yaml"
  assert_success
  assert_output_contains "from-flag"
  refute_output_contains "from-env"
}

# _fallback_profile -- a valid <project root>/infra.yaml named `the-fallback`,
# so an arm can tell a profile that was passed over from one that was refused:
# with the fallback present, passing over SUCCEEDS on the wrong file.
_fallback_profile() {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cat > "$BATS_TEST_TMPDIR/proj/infra.yaml" <<'Y'
version: 1
name: the-fallback
domains:
  a:
    name: a.example
Y
}

# AT-1.2
@test "a DEVBIN_INFRA_PROFILE naming a missing file is refused on that file, never passed over (0121)" {
  # A typo in the variable fell through to <project root>/infra.yaml, so `check`
  # ran against a DIFFERENT profile and nothing said so -- while the same intent
  # spelled as --profile was refused by name.
  _fallback_profile
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" DEVBIN_INFRA_PROFILE=/nope/typo.yaml \
    "$INFRA" show
  assert_failure
  assert_output_contains "no profile at /nope/typo.yaml (named by DEVBIN_INFRA_PROFILE)"
  refute_output_contains "the-fallback"
}

# AT-1.2
@test "POSITIVE CONTROL: a DEVBIN_INFRA_PROFILE naming a real file is used ahead of the project's (0121)" {
  # Without it the arm above is satisfied by a variable that is never read.
  _fallback_profile
  cat > "$PROFILE_DIR/env.yaml" <<'Y'
version: 1
name: from-env
domains:
  a:
    name: a.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" DEVBIN_INFRA_PROFILE="$PROFILE_DIR/env.yaml" \
    "$INFRA" show
  assert_success
  assert_output_contains "profile: $PROFILE_DIR/env.yaml"
  assert_output_contains "from-env"
  refute_output_contains "the-fallback"
}

@test "a profile with no name: shows as (unnamed), as the reference promises (0121)" {
  # `cfg_get name 2>/dev/null || printf '(unnamed)'` could never fall back:
  # cfg_get prints its default and returns 0 for an absent key, so `name:`
  # printed blank.
  cat > "$PROFILE_DIR/anon.yaml" <<'Y'
version: 1
domains:
  a:
    name: a.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/anon.yaml"
  assert_success
  assert_output_contains "name:    (unnamed)"
}

# --- parse-time validation --------------------------------------------------

# AT-1.7
@test "two handles naming one FQDN is an ERROR, and it names both handles" {
  cat > "$PROFILE_DIR/dup.yaml" <<'Y'
version: 1
name: dup
domains:
  alpha:
    name: alpha.example
  shop:
    name: alpha.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/dup.yaml"
  assert_failure
  # ASSERT THE UNIQUENESS MESSAGE ITSELF, not merely the strings in it.
  # This arm previously asserted only that the output contained "alpha.example",
  # "alpha" and "shop" -- and a mutation that errored while naming NEITHER
  # handle SURVIVED it. The three strings were being supplied by the unrelated
  # handle-mismatch warning (`shop` does not look derived from `alpha.example`),
  # so a test named for uniqueness was passing on a different message entirely.
  # Found by running the mutation, not by reading the test.
  assert_output_contains "named by two handles"
  assert_output_contains "alpha.example"
  assert_output_contains "alpha"
  assert_output_contains "shop"
}

# AT-1.7
@test "POSITIVE CONTROL: two DIFFERENT FQDNs under two handles is fine" {
  cat > "$PROFILE_DIR/ok.yaml" <<'Y'
version: 1
name: ok
domains:
  alpha:
    name: alpha.example
  shop:
    name: shop.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/ok.yaml"
  assert_success
}

@test "a handle that is not a derivation of its name WARNS but does not fail" {
  cat > "$PROFILE_DIR/odd.yaml" <<'Y'
version: 1
name: odd
domains:
  gamma:
    name: shop.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/odd.yaml"
  assert_success
  assert_output_contains "gamma"
}

# AT-1.6
@test "a domain with no name field is an ERROR naming the handle" {
  cat > "$PROFILE_DIR/noname.yaml" <<'Y'
version: 1
name: noname
domains:
  orphan:
    mail: google
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/noname.yaml"
  assert_failure
  assert_output_contains "orphan"
}

# AT-1.4
# AT-1.5
@test "a non-empty unreviewed block makes CHECK refuse, while show still works" {
  cat > "$PROFILE_DIR/unrev.yaml" <<'Y'
version: 1
name: unrev
domains:
  a:
    name: a.example
unreviewed:
  a_spf_include: "_spf.mlsend.com against a majority of _spf.mailersend.net"
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$PROFILE_DIR/unrev.yaml"
  assert_failure
  assert_output_contains "unreviewed"

  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/unrev.yaml"
  assert_success
}

# AT-1.5
@test "POSITIVE CONTROL: an EMPTY unreviewed block does not block check" {
  cat > "$PROFILE_DIR/clean.yaml" <<'Y'
version: 1
name: clean
domains:
  a:
    name: a.example
Y
  # A dig that reaches nothing, so this arm is deterministic and makes NO
  # network call. The profile layer is what is under test here; the DNS legs
  # have their own file.
  mkdir -p "$BATS_TEST_TMPDIR/nb"
  printf '#!/bin/sh\nexit 9\n' > "$BATS_TEST_TMPDIR/nb/dig"
  chmod +x "$BATS_TEST_TMPDIR/nb/dig"

  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PATH="$BATS_TEST_TMPDIR/nb:$PATH" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$PROFILE_DIR/clean.yaml"
  # THIS ARM HAS BEEN WRONG TWICE, IN OPPOSITE DIRECTIONS, AND BOTH ARE THE
  # SAME DEFECT. First it asserted only `refute_output_contains`, which an empty
  # output satisfies -- so it passed against a handler that did not exist. Then
  # it asserted success, which is worse: a check that exits 0 having verified
  # nothing is indistinguishable from one that passed.
  #
  # IT WAS THEN PINNED TO `not_yet` (exit 3), AND WP-02 BUILT THE LEGS, so it
  # went red -- which is exactly what its own comment said it should do when the
  # legs changed shape. That is the arm working, not breaking, and it is
  # rewritten rather than relaxed.
  #
  # The control still asserts the SHAPE: check got past the unreviewed gate --
  # which is the only thing this arm tests -- and went on to run the legs,
  # where an unreachable resolver is COULD NOT MEASURE. It goes red if the gate
  # wrongly fires, red if the legs silently exit 0, and red if an unmeasurable
  # domain is ever reported as a clean one.
  #
  # THE CODE NO LONGER TELLS THE TWO APART, since issue 0126: the legs' unmeasured
  # verdict exits 1, which is also the gate's refusal. The code holds that the
  # run failed; the two text assertions below are what hold which way.
  assert_exit_code 1
  assert_output_contains "COULD NOT MEASURE"
  refute_output_contains "unreviewed"
}

# --- valueless keys: invisible to the reader, and pointed the wrong way -------
#
# `lib/config` emits a cache row only for a key carrying a SCALAR, so a key with
# no value produces NO ROW and is indistinguishable through `cfg_list` from a key
# nobody wrote. Both directions were measured before these arms existed: a
# profile carrying two authored deviations passed `check` with "valid and fully
# reviewed", and a declared domain vanished from `show` with rc 0.
#
# The blindness points the wrong way BY CONSTRUCTION: a deviation `init` could
# not confidently propose is precisely the one with nothing on the right-hand
# side, so the gate was blind in exactly the direction it was built to see.

# AT-1.6
@test "valueless unreviewed entries are REFUSED and named, not silently skipped" {
  cat > "$PROFILE_DIR/vl.yaml" <<'Y'
name: probe
unreviewed:
  mx_form:
  ttl_default:
domains:
  alpha:
    name: alpha.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$PROFILE_DIR/vl.yaml"
  assert_failure
  assert_output_contains "carry no value"
  assert_output_contains "mx_form"
  assert_output_contains "ttl_default"
  refute_output_contains "fully reviewed"
}

# AT-1.6
@test "a domain declared with NO fields at all is refused, not dropped" {
  cat > "$PROFILE_DIR/drop.yaml" <<'Y'
name: probe
domains:
  alpha:
    name: alpha.example
  snorkeltoast:
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$PROFILE_DIR/drop.yaml"
  assert_failure
  assert_output_contains "snorkeltoast"
  assert_output_contains "carry no value"
}

# AT-1.6
@test "the MIXED case names the valueless key rather than reporting a complete refusal" {
  cat > "$PROFILE_DIR/mix.yaml" <<'Y'
name: probe
unreviewed:
  mx_form:
  spf_all_qualifier: "estate is split 2-vs-1"
domains:
  alpha:
    name: alpha.example
Y
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$PROFILE_DIR/mix.yaml"
  assert_failure
  # Without the visibility scan this refused naming ONE of TWO deviations, and a
  # refusal that reads as complete is worse than the clean miss.
  assert_output_contains "mx_form"
}

# --- cross-profile uniqueness (infra profiles) -------------------------------

mkprofile() {
  local dir="$PROFILE_DIR/estate/$1"; shift
  mkdir -p "$dir"
  { printf 'version: 1\nname: %s\n\ndomains:\n' "$(basename "$dir")"
    while [ $# -gt 0 ]; do printf '  %s:\n    name: %s\n' "${1%%=*}" "${1#*=}"; shift; done
  } > "$dir/infra.yaml"
}
runprofiles() {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" bash "$DEVBIN_HOME/lib/cmd/infra.d/profiles" "$@"
}

@test "profiles over a directory find cannot read wholly refuses, never 'no domain claimed twice' over part of it (0139, 0145)" {
  # find's errors went to /dev/null in the loop's heredoc, so a profile beneath
  # a directory it could not read was never compared, and the run gave the one
  # verdict this verb exists for over part of the estate.
  local p
  local -a claimers=(alpha locked/beta)
  for p in "${claimers[@]}"; do mkprofile "$p" x=x.example; done
  # THE CONTROL: readable, the double claim is found.
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "claimed by ${#claimers[@]} profiles"
  chmod 000 "$PROFILE_DIR/estate/locked"
  # The mode is probed, as the other arms do, not the uid: what matters is
  # whether this runner can read a mode-000 directory.
  if [ -r "$PROFILE_DIR/estate/locked" ]; then
    chmod 755 "$PROFILE_DIR/estate/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  runprofiles "$PROFILE_DIR/estate"
  chmod 755 "$PROFILE_DIR/estate/locked"
  assert_failure
  assert_output_contains "could not read all of"
  assert_output_contains "$PROFILE_DIR/estate/locked"
  refute_output_contains "no domain claimed twice"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and the double claim beneath it went unseen.
  chmod 644 "$PROFILE_DIR/estate/locked"
  if [ -x "$PROFILE_DIR/estate/locked" ]; then
    chmod 755 "$PROFILE_DIR/estate/locked"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  runprofiles "$PROFILE_DIR/estate"
  chmod 755 "$PROFILE_DIR/estate/locked"
  assert_failure
  assert_output_contains "cannot search $PROFILE_DIR/estate/locked -- nothing beneath it was looked at"
  assert_output_contains "could not read all of"
  refute_output_contains "no domain claimed twice"
}

# AT-1.8
@test "a domain claimed by TWO profiles is refused, and both are named" {
  # WITHIN a file, one-entry-per-domain is enforced and the reason is stated:
  # two entries can carry contradictory expectations that `check` evaluates
  # against the same live records, so one goes green and one goes red on the
  # same domain and ordering decides which the operator reads. That reason does
  # not stop at the file boundary, and an estate laid out as
  # profiles/<name>/infra.yaml makes the cross-file case reachable with nothing
  # reporting it. Raised by a consumer from the first such estate.
  mkprofile alpha shared=shared.example alpha=alpha.example
  mkprofile beta  shared=shared.example beta=beta.example
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "shared.example"
  assert_output_contains "alpha/infra.yaml"
  assert_output_contains "beta/infra.yaml"
}

# AT-1.8
@test "distinct domains across profiles PASS -- the check is not refusing everything" {
  # The positive control. Without it the arm above is satisfied by a checker
  # that refuses unconditionally.
  mkprofile alpha alpha=alpha.example
  mkprofile beta  beta=beta.example
  runprofiles "$PROFILE_DIR/estate"
  assert_success
  assert_output_contains "no domain claimed twice"
}

# AT-1.8
@test "a directory holding NO profiles is an ERROR, never a clean report" {
  # "0 profiles, no collisions" is the shape of every false green this
  # repository has a name for. Finding nothing means the path was wrong.
  mkdir -p "$PROFILE_DIR/emptyestate"
  runprofiles "$PROFILE_DIR/emptyestate"
  assert_failure
  assert_output_contains "no infra.yaml found"
}

# AT-1.8
@test "a profile that does not LOAD stops the comparison rather than being skipped" {
  # A profile silently skipped for being unparseable is a domain that vanishes
  # from the population, so a real collision involving it reads as clean.
  mkprofile alpha alpha=alpha.example
  mkdir -p "$PROFILE_DIR/estate/broken"
  printf 'domains: { flow: not-supported }\n' > "$PROFILE_DIR/estate/broken/infra.yaml"
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "does not load"
}

# AT-1.8
@test "a profile that does not load prints the parser's own reason, above its name (0121)" {
  # The load's stderr went to /dev/null, so the refusal named the file and not
  # what was wrong with it, which `show` on the same file does say.
  mkdir -p "$PROFILE_DIR/estate/broken"
  printf 'domains: { flow: not-supported }\n' > "$PROFILE_DIR/estate/broken/infra.yaml"
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "flow collections are not supported"
  assert_output_contains "broken/infra.yaml does not load (above)"
}

# AT-1.8
@test "a profile that LOADS but does not VALIDATE stops the comparison, named (0121)" {
  # The usage always said "Validate every infra.yaml"; the loop only loaded
  # them. A domain with no name: is refused by `show`, and here it was dropped
  # from the population instead, so the run printed its clean line.
  mkprofile alpha alpha=alpha.example
  mkdir -p "$PROFILE_DIR/estate/broken"
  cat > "$PROFILE_DIR/estate/broken/infra.yaml" <<'Y'
version: 1
name: broken
domains:
  orphan:
    mail: google
Y
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "domain \`orphan\` has no \`name:\` field"
  assert_output_contains "broken/infra.yaml does not validate (above)"
  refute_output_contains "no domain claimed twice"
}

# AT-1.8
@test "POSITIVE CONTROL: a validation WARNING does not stop profiles, and prints under its file (0121)" {
  # A handle that does not look derived from its name warns and is not an
  # error, in `show` and here. Printed bare, a directory of profiles gets advice
  # naming a handle and no file, so the line above it is the file's path.
  mkprofile alpha alpha=alpha.example
  mkprofile beta gamma=shop.example
  runprofiles "$PROFILE_DIR/estate"
  assert_success
  assert_output_contains "no domain claimed twice"
  local at above
  at="$(printf '%s\n' "$output" | grep -n 'handles worth a second look' | cut -d: -f1)"
  [ -n "$at" ] || fail "no validation warning printed: $output"
  [ "$at" -gt 1 ] || fail "the warning is the first line, with no file above it: $output"
  above="$(sed -n "$((at - 1))p" <<<"$output")"
  grep -q '/estate/beta/infra.yaml:$' <<<"$above" ||
    fail "the line above the warning does not name beta's file: $output"
}

# --- asking for help vs forgetting the argument ------------------------------
#
# Found verifying `infra profiles` against a real multi-profile estate. Both
# verbs collapsed the two events into one `'' | -h | --help)` arm and exited 0,
# so a caller who left the argument out read success. In the verb whose whole
# argument is that an empty population is an ERROR, that is the same false green
# one level up.

# AT-1.10
@test "infra profiles with NO argument REFUSES rather than printing usage at exit 0" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" "$DEVBIN_HOME/lib/cmd/infra.d/profiles"
  assert_failure
  assert_output_contains "no directory given"
  assert_output_contains "Nothing was compared"
}

# AT-1.10
@test "POSITIVE CONTROL: infra profiles --help is a REQUEST, and still exits 0" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" "$DEVBIN_HOME/lib/cmd/infra.d/profiles" --help
  assert_success
  assert_output_contains "usage:"
}

# AT-1.10
# AT-5.1
@test "infra mail with NO family REFUSES rather than exiting 0" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" "$DEVBIN_HOME/lib/cmd/infra.d/mail"
  assert_failure
  assert_output_contains "no family given"
}

# AT-1.10
# AT-5.1
@test "POSITIVE CONTROL: infra mail --help still exits 0" {
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" "$DEVBIN_HOME/lib/cmd/infra.d/mail" --help
  assert_success
  assert_output_contains "usage:"
}

# AT-1.9
@test "the top-level infra usage names EVERY verb, including the .d/ children" {
  # `profiles` and `mail` are routed before lib/cmd/infra is reached, so no
  # dispatch test could ever have caught their absence from this list. Only a
  # reader needs it, which is exactly why it went unnoticed.
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" "$DEVBIN_HOME/lib/cmd/infra" --help
  assert_success
  for verb in show check profiles mail; do
    assert_output_contains "$verb"
  done
}

# AT-1.9
@test "the infra usage heredoc carries no backtick -- it is UNQUOTED" {
  # The heredoc is unquoted so $DEVBIN_NAME renders in a consuming project,
  # which makes any backtick inside it live command substitution. The first
  # draft of the verb-list change put `.d/` in the help text; shellcheck
  # refused it as a command ending in `/` (SC2287) before it ran anywhere.
  #
  # THIS ARM ASSERTS THE SOURCE, NOT THE OUTPUT, AND THE FIRST VERSION DID NOT
  # -- which made it unfalsifiable. A backtick in an unquoted heredoc is
  # CONSUMED BY EXECUTION: the shell runs it and substitutes the result, so the
  # backtick never reaches the output being grepped. Driven red by putting
  # `mail dmarc` back into the heredoc: the output arm stayed green while the
  # defect was live, because the command simply failed to empty. A test that
  # cannot fail is worse than no test, and it fails in the same direction as the
  # thing it guards.
  body="$(sed -n '/cat <<USAGE/,/^USAGE$/p' "$DEVBIN_HOME/lib/cmd/infra")"
  [ -n "$body" ] || fail "could not extract the usage heredoc at all"
  case "$body" in
    *'`'*) fail "the UNQUOTED usage heredoc contains a backtick, which the shell will EXECUTE:
$(printf '%s\n' "$body" | grep '`')" ;;
  esac
}

# --- THE UNIVERSAL SENDER INVARIANT (WP-06) ----------------------------------
#
# design.md settles the library as SHAPE and never contents: a shipped
# `mailersend: {spf: _spf.mailersend.net}` WOULD HAVE BEEN WRONG for a live
# domain on `_spf.mlsend.com`, and no one could establish whether that split is
# account-specific or generational -- so a value commits to an answer nobody
# has. The invariant needs no per-vendor table: a domain declaring a sender must
# carry a MATCHED SPF include and DKIM selector pair.
#
# THESE ARMS EXIST BECAUSE OF A MISCLASSIFICATION MEASURED ON A REAL ESTATE.
# Two live domains name `mailersend` in profiles that never define it, and
# `check` filed that under COULD NOT MEASURE -- a channel whose own header reads
# "gaps in the INSTRUMENT, not verdicts". Nothing about the instrument was
# missing. The profile was incomplete, which is the operator's to fix and is
# catchable with no network at all.

_sender_profile() { # _sender_profile <file> <sender-block>
  cat > "$1" <<Y
version: 1
name: t
$2
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
Y
}

_run_show() { run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" \
  PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" show --profile "$1"; }

# AT-6.3
@test "a domain naming an UNDEFINED sender is refused, naming the domain and the sender" {
  _sender_profile "$PROFILE_DIR/undef.yaml" ""
  _run_show "$PROFILE_DIR/undef.yaml"
  assert_failure
  assert_output_contains "alpha"
  assert_output_contains "acme"
  assert_output_contains "never defines"
}

# AT-6.3
@test "a sender with an SPF include and NO dkim selector is a HALF PAIR, refused" {
  _sender_profile "$PROFILE_DIR/half1.yaml" "senders:
  acme:
    spf_include: _spf.acme.example"
  _run_show "$PROFILE_DIR/half1.yaml"
  assert_failure
  assert_output_contains "HALF A PAIR"
  assert_output_contains "dkim.name"
}

# AT-6.3
@test "a sender with a dkim selector and NO SPF include is the OTHER half, also refused" {
  # Both directions, because a rule enforced on one side only is half a rule --
  # and this is the side that looks harmless: a DKIM record nothing authorises.
  _sender_profile "$PROFILE_DIR/half2.yaml" "senders:
  acme:
    dkim:
      name: sel._domainkey"
  _run_show "$PROFILE_DIR/half2.yaml"
  assert_failure
  assert_output_contains "HALF A PAIR"
  assert_output_contains "spf_include"
}

# AT-6.3
@test "POSITIVE CONTROL: a fully defined sender pair passes, so this is a gate not a wall" {
  _sender_profile "$PROFILE_DIR/full.yaml" "senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: sel._domainkey
      type: CNAME"
  _run_show "$PROFILE_DIR/full.yaml"
  assert_success
  assert_output_contains "alpha.example"
}

# AT-6.3
@test "POSITIVE CONTROL: a domain naming NO sender is untouched by the invariant" {
  cat > "$PROFILE_DIR/nosender.yaml" <<'Y'
version: 1
name: t
domains:
  alpha:
    name: alpha.example
Y
  _run_show "$PROFILE_DIR/nosender.yaml"
  assert_success
}

# ============================================================================
# ISSUE 0143: every key a profile carries is one something reads
# ============================================================================
#
# A key the profile had no field for parsed, validated and was never read, and
# that is how a profile declaring dmarc.sp, a second DKIM key and a wildcard
# checked green against a zone carrying none of them. These arms hold the
# refusals, the new fields' own shapes, and the controls that prove real
# profiles still load: measured before 0143, not one of them carried a key the
# key table refuses.

# _prof <name> -- a profile file of stdin, and its path on stdout.
_prof() { cat >"$PROFILE_DIR/$1.yaml"; printf '%s\n' "$PROFILE_DIR/$1.yaml"; }

# AT-1.6
@test "an unknown key is REFUSED naming the key and the file, and check asks nothing of any nameserver (0143)" {
  local p
  p="$(_prof unknown <<'Y'
version: 1
name: t
defaults:
  dmarc:
    policy: none
  dmarc_sp: reject
  mail:
    provider: google
domains:
  alpha:
    name: alpha.example
    wildcard:
      cname: elsewhere.example
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: $p: unknown key: defaults.dmarc_sp -- the profile has no such field, so nothing would read it"
  assert_output_contains "infra: $p: unknown key: domains.alpha.wildcard.cname -- the profile has no such field, so nothing would read it"
  # A key nested below one the table reads as a single value is not that key.
  assert_output_contains "infra: $p: unknown key: defaults.mail.provider -- the profile has no such field, so nothing would read it"
  # check refuses before any DNS question: a dig that logs every call is never run.
  mkdir -p "$BATS_TEST_TMPDIR/logbin"
  printf '#!/bin/sh\necho "$*" >>"%s"\nexit 9\n' "$BATS_TEST_TMPDIR/dig.log" >"$BATS_TEST_TMPDIR/logbin/dig"
  chmod +x "$BATS_TEST_TMPDIR/logbin/dig"
  : >"$BATS_TEST_TMPDIR/dig.log"
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/logbin:$PATH" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$p"
  assert_failure
  assert_output_contains "Nothing was checked against the live estate"
  assert_file_empty "$BATS_TEST_TMPDIR/dig.log"
  # CONTROL: the same dig on the same PATH IS reached by a profile that
  # validates, so the empty log above is the refusal and not a stub never run.
  run env DEVBIN_LIB="$DEVBIN_HOME/lib" HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/logbin:$PATH" \
    PROJECT_ROOT="$BATS_TEST_TMPDIR/proj" "$INFRA" check --profile "$DEVBIN_LIB_DIR/infra.reference.yaml"
  [ -s "$BATS_TEST_TMPDIR/dig.log" ] || fail "a valid profile's check never ran the logging dig:\n$output"
}

# AT-1.6
@test "a field written where nothing reads it is refused as such: dmarc none under defaults, senders there or as a word (0143)" {
  # `defaults.dmarc: none` was a SILENT opt-out: check reads `dmarc: none`
  # under a domain only, so every domain went unasserted and none was named.
  local p
  p="$(_prof misplaced <<'Y'
version: 1
name: t
defaults:
  dmarc: none
  senders:
    - acme
domains:
  alpha:
    name: alpha.example
    senders: acme
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "unknown key: defaults.dmarc -- the profile has a \`dmarc\` field, but nothing reads it here"
  assert_output_contains "unknown key: defaults.senders.0 -- the profile has a \`senders\` field, but nothing reads it here"
  assert_output_contains "unknown key: domains.alpha.senders -- the profile has a \`senders\` field, but nothing reads it here"
}

# AT-1.6
@test "a bare dmarc under a domain other than none is refused, and so are policy and sp words DMARC does not have (0143)" {
  # `dmarc: quarantine` reads like a policy and was ignored: only `none` was
  # ever compared. A misspelt policy drifted every run and read as the ESTATE's
  # fault.
  local p
  p="$(_prof words <<'Y'
version: 1
name: t
defaults:
  dmarc:
    policy: quarentine
    sp: rejected
domains:
  alpha:
    name: alpha.example
    dmarc: quarantine
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: $p: domains.alpha.dmarc: \"quarantine\" is not a value it takes (none)"
  assert_output_contains "infra: $p: defaults.dmarc.policy: \"quarentine\" is not a value it takes (none, quarantine, reject)"
  assert_output_contains "infra: $p: defaults.dmarc.sp: \"rejected\" is not a value it takes (none, quarantine, reject)"
}

# AT-1.6
@test "a wildcard a or aaaa holding more than one value is refused, and a txt holding spaces is not (0143)" {
  # The schema says ONE address or `none`, and the set compare can never hold
  # two addresses in one string: its drift line printed both sides alike.
  local p
  p="$(_prof twoaddr <<'Y'
version: 1
name: t
defaults:
  wildcard:
    a: "192.0.2.7 192.0.2.8"
    txt: "v=spf1 -all"
domains:
  alpha:
    name: alpha.example
    wildcard:
      aaaa: "2001:db8::7 2001:db8::8"
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: $p: defaults.wildcard.a: \"192.0.2.7 192.0.2.8\" is more than one value -- a wildcard a is ONE address or \`none\`"
  assert_output_contains "infra: $p: domains.alpha.wildcard.aaaa: \"2001:db8::7 2001:db8::8\" is more than one value -- a wildcard aaaa is ONE address or \`none\`"
  # CONTROL: a TXT record holds spaces of its own, and is not refused for them.
  refute_output_contains "wildcard.txt"
}

# AT-1.6
@test "dmarc.sp with no dmarc.policy in force is refused, since presence is asserted by the policy alone (0143)" {
  local p
  p="$(_prof sponly <<'Y'
version: 1
name: t
defaults:
  dmarc:
    sp: reject
domains:
  alpha:
    name: alpha.example
  legacy:
    name: legacy.example
    dmarc: none
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: domain \`alpha\` declares dmarc.sp with no dmarc.policy in force"
  # A domain that opted out of DMARC altogether is not asked for a policy.
  refute_output_contains "domain \`legacy\` declares dmarc.sp"
  # POSITIVE CONTROL: the same sp with a policy beside it is a profile.
  p="$(_prof spok <<'Y'
version: 1
name: t
defaults:
  dmarc:
    policy: none
    sp: reject
domains:
  alpha:
    name: alpha.example
Y
)"
  _run_show "$p"
  assert_success
}

# AT-1.6
@test "a key written under a key that already has a value is refused, naming the line (0143)" {
  # `dmarc: none` with a policy indented under it parsed to BOTH, and check
  # read the none and never the policy.
  local p
  p="$(_prof nested <<'Y'
version: 1
name: t
domains:
  alpha:
    name: alpha.example
    dmarc: none
      policy: reject
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "config: $p:7: \`domains.alpha.dmarc\` already has a value, so nothing can be nested under it"
}

# AT-1.6
@test "a key written with no value is refused wherever it is written, not only under domains (0143)" {
  local p
  p="$(_prof valueless <<'Y'
version: 1
name: t
defaults:
  manual:
domains:
  alpha:
    name: alpha.example
    wildcard:
Y
)"
  _run_show "$p"
  assert_failure
  # `defaults` is named too: its one key carries nothing, so nothing of it
  # reached the reader either.
  assert_output_contains "infra: these keys are written but carry no value, so nothing can read them: defaults defaults.manual domains.alpha.wildcard
"
}

# AT-1.6
@test "a profile the valueless-key scan cannot read is refused, never passed as having nothing to find (0143)" {
  # The scan's answer is a list of keys, and an empty list is the pass: a scan
  # that failed and printed nothing would pass every profile.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  # shellcheck source=lib/infra
  . "$DEVBIN_LIB_DIR/infra"
  cfg_load "$DEVBIN_LIB_DIR/infra.reference.yaml"
  # CONTROL: the shipped reference, readable, passes the scan.
  run infra_assert_written_keys_visible "$DEVBIN_LIB_DIR/infra.reference.yaml"
  assert_success
  run infra_assert_written_keys_visible "$BATS_TEST_TMPDIR/no-such-profile.yaml"
  assert_failure
  assert_output_contains "infra: $BATS_TEST_TMPDIR/no-such-profile.yaml: could not be scanned for keys written with no value, so no key in it is known to be visible"
}

# --- the DKIM record forms ------------------------------------------------------

# _ms_profile <dkim lines> -- one domain naming mailersend, whose dkim: block is $1.
_ms_profile() {
  _prof "$1" <<Y
version: 1
name: t
senders:
  mailersend:
    spf_include: _spf.mailersend.net
    dkim:
$2
domains:
  alpha:
    name: alpha.example
    senders:
      - mailersend
Y
}

# AT-6.3
# AT-2.12
@test "POSITIVE CONTROL: the labelled DKIM form, dmarc.sp and wildcards are a profile (0143)" {
  local p
  p="$(_prof newfields <<'Y'
version: 1
name: t
defaults:
  dmarc:
    policy: quarantine
    sp: reject
  wildcard:
    txt: "v=spf1 -all"
senders:
  mailersend:
    spf_include: _spf.mailersend.net
    dkim:
      ms1:
        name: ms1._domainkey
        type: CNAME
        value: ms1._domainkey.mailersend.net
      ms2:
        name: ms2._domainkey
domains:
  alpha:
    name: alpha.example
    senders:
      - mailersend
    wildcard:
      a: 192.0.2.7
      aaaa: 2001:db8::7
  beta:
    name: beta.example
    wildcard:
      a: none
      aaaa: none
      txt: none
Y
)"
  _run_show "$p"
  assert_success
  assert_output_contains "beta.example"
}

# AT-6.3
@test "a sender mixing the one-record form with labelled records is refused (0143)" {
  local p
  p="$(_ms_profile mixed '      name: mlsend2._domainkey
      ms1:
        name: ms1._domainkey')"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: sender \`mailersend\` mixes the one-record form (dkim.name) with labelled records (dkim.ms1) -- write every record under a label."
}

# AT-6.3
@test "a DKIM record labelled name, type or value is refused, whatever its fields (0143)" {
  local p l
  for l in name type value; do
    p="$(_ms_profile "reserved-$l" "      $l:
        name: ms1._domainkey")"
    _run_show "$p"
    assert_failure
    assert_output_contains "infra: sender \`mailersend\` has a DKIM record labelled \`$l\`, which is the name of a field -- choose another label."
  done
}

# AT-6.3
@test "two DKIM records naming one selector are refused (0143)" {
  local p
  p="$(_ms_profile twice '      ms1:
        name: ms1._domainkey
      ms1b:
        name: ms1._domainkey')"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: sender \`mailersend\` declares the selector \`ms1._domainkey\` twice. One record per selector."
}

# AT-1.6
@test "a DKIM label written with no fields is refused and named, never dropped (0143)" {
  # lib/config emits no row for a key with no value, so ms2 would vanish and
  # nothing would ever ask for it: half a sender, declared in full.
  local p
  p="$(_ms_profile bare '      ms1:
        name: ms1._domainkey
      ms2:')"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: these keys are written but carry no value, so nothing can read them: senders.mailersend.dkim.ms2
"
}

# AT-6.3
@test "a DKIM record with no name is refused, even for a sender no domain names (0143)" {
  # Nothing could ask for it. The rule runs over every defined sender, so it
  # does not wait for a domain to name one.
  local p
  p="$(_prof noname <<'Y'
version: 1
name: t
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      k1:
        name: k1._domainkey
      k2:
        type: CNAME
domains:
  alpha:
    name: alpha.example
Y
)"
  _run_show "$p"
  assert_failure
  assert_output_contains "infra: sender \`acme\` declares a DKIM record with no name, so nothing can ask for it: dkim.k2.name"
}

# --- the table, the reference, real profiles -----------------------------------

# AT-1.11
@test "the shipped reference carries a LIVE example of every key the profile may hold (0143)" {
  # The key table is the one statement of the keys; the reference is its
  # annotated form. unreviewed: is the one row shown commented out, because a
  # live entry makes check refuse.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  # shellcheck source=lib/infra
  . "$DEVBIN_LIB_DIR/infra"
  cfg_load "$DEVBIN_LIB_DIR/infra.reference.yaml"
  local pat pats rows=0 missing="" k hit
  pats="$(infra_profile_key_patterns)"
  while read -r pat; do
    [ -n "$pat" ] || continue
    [ "$pat" = "unreviewed.<key>" ] && continue
    rows=$((rows + 1))
    hit=0
    while IFS=$'\t' read -r k _; do
      if infra_key_matches "$pat" "$k"; then hit=1; break; fi
    done <<<"$_DEVBIN_CFG"
    [ "$hit" -eq 1 ] || missing="$missing $pat"
  done <<<"$pats"
  [ "$rows" -gt 0 ] || fail "the key table gave no row to check -- a reader that finds nothing would pass every reference"
  [ -z "$missing" ] || fail "lib/infra.reference.yaml carries no live example of:$missing"
}

# AT-1.6
# AT-2.12
@test "POSITIVE CONTROL: a profile of every key shape real profiles use validates (0143)" {
  # Measured before 0143 over one infra user's three profiles and every vendored
  # reference: these shapes, and not one key the table refuses.
  local p
  p="$(_prof fleet <<'Y'
version: 1
name: fleet
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: none
    rua: dmarc@fleet.example
  manual:
    catchall_group: "a Workspace group `email@<domain>` exists on the domain"
senders:
  mailersend:
    spf_include: _spf.mailersend.net
    dkim:
      name: mlsend2._domainkey
      type: CNAME
      value: mlsend2._domainkey.mailersend.net
domains:
  alpha:
    name: alpha.example
    dmarc:
      policy: quarantine
    manual:
      rua_external: "the group must accept mail from EXTERNAL senders"
  shop:
    name: shop.example
    senders:
      - mailersend
  delta:
    name: delta.example
    mail: other
    dmarc:
      policy: reject
  legacy:
    name: legacy.example
    dmarc: none
runtime:
  fly:
    shop-app:
      org: alpha
      hostnames:
        - alpha.example
        - "*.alpha.example"
Y
)"
  _run_show "$p"
  assert_success
  refute_output_contains "unknown key"
}

# AT-1.8
@test "infra profiles stops at a profile carrying an unknown key, naming the key and the file (0143)" {
  mkprofile alpha alpha=alpha.example
  mkprofile beta beta=beta.example
  printf '    wildcard_txt: "v=spf1 -all"\n' >>"$PROFILE_DIR/estate/beta/infra.yaml"
  runprofiles "$PROFILE_DIR/estate"
  assert_failure
  assert_output_contains "unknown key: domains.beta.wildcard_txt"
  assert_output_contains "beta/infra.yaml does not validate (above)"
  refute_output_contains "no domain claimed twice"
}
