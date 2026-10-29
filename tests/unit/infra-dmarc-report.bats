#!/usr/bin/env bats
#
# `devbin infra mail dmarc report` -- parse rows to a summary a human reads.
#
# THESE DISCIPLINES SHAPE EVERY ASSERTION HERE, all learned the same day.
#
# 1. ASSERT ON WHAT MAKES A MESSAGE *THAT* MESSAGE, NEVER ON THE SUBSTRINGS IT
#    HAPPENS TO CONTAIN. `report` emits one text blob in which every domain name
#    appears several times -- in the population line, in its classification
#    section, sometimes in two sections at once. `[[ $output == *example.com* ]]`
#    is therefore satisfied by almost any implementation, including one that
#    classified every record wrongly. Every assertion below extracts its SECTION
#    first and asserts inside it. (A uniqueness test once passed on strings
#    supplied by an unrelated warning firing on the same fixture -- it measured
#    the fixture, not the code.)
#
# 2. A TEST NAMED FOR A PROPERTY IS NOT EVIDENCE IT DETECTS THAT PROPERTY'S
#    ABSENCE. Assertions about an empty/absent/zero case are satisfied by an
#    implementation that produces that value always, so the controls that carry
#    weight here are the ones that must hold on the CLEAN fixture -- where a
#    lazy implementation is most likely to fall silent and most likely to be
#    believed.
#
set -euo pipefail

load "../lib/test_helper"

FIXTURES="$BATS_TEST_DIRNAME/../fixtures/dmarc"

setup() {
  devbin_setup
  REPORT="$DEVBIN_HOME/lib/cmd/infra.d/mail.d/dmarc"
  MIXED="$FIXTURES/rows-mixed.jsonl"
  CLEAN="$FIXTURES/rows-clean.jsonl"
}
teardown() { devbin_teardown; }

# section <heading> -- the body of one section, and NOTHING from any other.
# Sections are an ALL-CAPS heading at column 0 and indented lines beneath, ended
# by a blank line. Without this every assertion in the file would be a claim
# about the whole document.
section() {
  awk -v h="$1" '
    $0 ~ "^" h { inside = 1; next }
    inside && /^[[:space:]]*$/ { exit }
    inside { print }
  '
}

# --- the population, stated beside every claim -------------------------------

@test "report: states its own population -- records, messages, domains, reporters" {
  run bash -c "'$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]

  pop="$(section 'DMARC' <<<"$output")"
  # Exact numbers, not shape: 6 records carrying 18 messages, 3 domains, 2
  # reporters, 3 distinct report ids. A summary that cannot say how much it read
  # is the defect this whole command exists downstream of.
  [[ "$pop" == *"6 records"* ]]
  [[ "$pop" == *"18 messages"* ]]
  [[ "$pop" == *"3 domains"* ]]
  [[ "$pop" == *"2 reporters"* ]]
}

# --- classification --------------------------------------------------------

@test "report: the classes PARTITION the records -- they sum to the total" {
  # The strong invariant. A record is unauthenticated, or DKIM-present-failing,
  # or authenticated; never two, never none. Misclassification that preserves
  # the total is possible, but no DROPPED record survives this.
  run bash -c "'$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]

  u=$(section 'UNAUTHENTICATED' <<<"$output" | grep -c .)
  f=$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output" | grep -c .)
  a=$(section 'AUTHENTICATED' <<<"$output" | grep -c .)
  [ "$((u + f + a))" -eq 6 ]
}

@test "report: an unauthenticated source is listed UNDER the unauthenticated heading" {
  run bash -c "'$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]

  unauth="$(section 'UNAUTHENTICATED' <<<"$output")"
  [[ "$unauth" == *"198.51.100.23"* ]]
  [[ "$unauth" == *"203.0.113.77"* ]]
  # And the authenticated sources are NOT in it -- without this the assertion
  # above passes for an implementation that lists every source in every section.
  [[ "$unauth" != *"192.0.2.10"* ]]
  [[ "$unauth" != *"192.0.2.60"* ]]
}

@test "report: a domain in TWO classes appears in BOTH, not just its first" {
  # example.com has 2 unauthenticated records and 1 authenticated one. An
  # implementation that groups by domain and assigns one verdict per domain
  # passes every other test in this file and hides live forgery behind a
  # domain's own good mail.
  run bash -c "'$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]

  [[ "$(section 'UNAUTHENTICATED' <<<"$output")" == *"example.com"* ]]
  [[ "$(section 'AUTHENTICATED' <<<"$output")" == *"example.com"* ]]
}

@test "report: DKIM present-and-failing is its OWN class, not folded into either neighbour" {
  # A signature that is present and fails is own mail broken in transit or a
  # forged signature (0147), and neither reading is "no signature at all".
  # Folding it into unauthenticated loses the signer that tells the two apart;
  # folding it into authenticated hides it entirely.
  run bash -c "'$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]

  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  [[ "$failing" == *"192.0.2.50"* ]]
  [[ "$(section 'UNAUTHENTICATED' <<<"$output")" != *"192.0.2.50"* ]]
  [[ "$(section 'AUTHENTICATED' <<<"$output")" != *"192.0.2.50"* ]]
}

# --- the callouts that must fire when everything looks fine ------------------

# AT-5.5
@test "report: the disposition callout fires ON A CLEAN INPUT, where silence is most tempting" {
  # THE CONTROL THAT CARRIES THE MOST WEIGHT IN THIS FILE. Under p=none every
  # record reads disposition=none, forged ones included -- so a reader who sees
  # a clean run and stops reading is exactly the reader this callout is for. An
  # implementation that prints it only when something is wrong is silent in the
  # one case where the misreading is undetectable.
  run bash -c "'$REPORT' report <'$CLEAN'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISPOSITION IS NOT AUTHENTICATION"* ]]
}

@test "report: the blind-spot block fires on a clean input too" {
  run bash -c "'$REPORT' report <'$CLEAN'"
  [ "$status" -eq 0 ]

  blind="$(section 'WHAT THIS CANNOT SEE' <<<"$output")"
  [ -n "$blind" ]
  # It must name the specific blindness that matters, not merely exist: a domain
  # publishing no rua produces no reports and is silently absent from the input.
  [[ "$blind" == *"rua"* ]]
}

# AT-5.3
@test "report: names the domains it SAW and never claims an estate" {
  # The seam with `check`. `report` has no profile, so it cannot know which
  # domains SHOULD have reported -- and a summary phrased as an estate verdict
  # would be reporting on its own input while sounding like it reported on the
  # estate. That is absent-reporting-reads-as-clean-reporting, produced by the
  # tool built to detect it.
  run bash -c "'$REPORT' report <'$CLEAN'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"present in these reports"* ]]
  [[ "$output" != *"your estate"* ]]
  [[ "$output" != *"all domains"* ]]
}

@test "help: dmarc check does not dispatch, and every line naming it says planned (0121)" {
  # The help pointed the reader at `infra mail dmarc check` as the verb that
  # judges the estate, and the dispatch has only parse and report. The first
  # half is the premise: when ST0006 WP-02 builds the verb this goes red, and
  # the lines calling it planned change with it -- the help's, and since 0147
  # the report's own WHAT THIS CANNOT SEE line.
  run "$REPORT" check
  assert_failure
  assert_output_contains "unknown verb"
  local claims out named
  for out in help report; do
    if [ "$out" = help ]; then run "$REPORT" --help; else run bash -c '"$1" report <"$2"' _ "$REPORT" "$CLEAN"; fi
    assert_success
    # No match is the passing case, so grep's status 1 is not a failure here.
    claims="$(printf '%s\n' "$output" | grep 'dmarc check' | grep -v 'planned' || true)"
    [ -z "$claims" ] || fail "the $out names dmarc check without calling it planned: $claims"
  done
  named="$(grep 'dmarc check' <<<"$output")" && grep -q 'planned' <<<"$named" ||
    fail "the report does not name the planned check:\n$output"
}

# --- purity and failure ------------------------------------------------------

@test "report: is PURE -- reads stdin, no profile, no network" {
  run bash -c "DEVBIN_INFRA_PROFILE=/nonexistent/profile.yaml '$REPORT' report <'$MIXED'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"6 records"* ]]
}

@test "report: empty input FAILS LOUDLY rather than printing a clean empty summary" {
  # An empty summary and a clean estate render identically to a human at 9am.
  run bash -c "'$REPORT' report </dev/null"
  [ "$status" -ne 0 ]
  grep -qiE 'no rows|empty|no records' <<<"$output"
}

@test "report: a non-JSON line FAILS, naming the line" {
  bad="$DEVBIN_TEST_TMPDIR/bad.jsonl"
  printf '%s\n' '{"org":"x"}' 'this is not json' >"$bad"

  run bash -c "'$REPORT' report <'$bad'"
  [ "$status" -ne 0 ]
  grep -q '2' <<<"$output"
}

# AT-5.9
@test "report: an over-long field is MISALIGNED, never fused to its neighbour" {
  # FOUND ON REAL OUTPUT, not on a fixture. An IPv6 source address is 22
  # characters in an 18-wide column, and the pad helper returned the value
  # unchanged once it reached the width -- emitting ZERO separating spaces. The
  # row read `2001:db8:1234:567::8901 msg`, in which `::8901` is a perfectly
  # plausible address and the count has vanished into it. Misalignment is a
  # cosmetic fault; fusing two fields into one wrong-looking value is not.
  #
  # The column is deliberately NOT widened to IPv6's 39 characters: that would
  # spend 20 columns on every IPv4 row to tidy a rare one.
  local row
  row="$(jq -c '.source_ip = "2001:db8:1234:567::890"' "$CLEAN")"
  row="${row%%$'\n'*}"
  run bash -c "printf '%s\n' '$row' | '$REPORT' report"
  assert_success
  # The address and whatever follows it must be separated by whitespace.
  assert_output_contains "2001:db8:1234:567::890 "
  refute_output_contains "2001:db8:1234:567::8901"
}

# --- a failing signature is not proof of ownership (0147) --------------------
#
# FOUND IN one infra user's archive: every record the report headed
# "your own mail, failing" was a signature at a selector the domain publishes no
# key at, or one with no signing domain at all. rows-signers.jsonl carries both
# shapes as that archive held them -- alpha.example signed at `dkim` where its key
# is at `google`, and beta.example signed with an empty domain and selector --
# beside a foreign signer, a failing signature on each domain's own key, and a
# pass.

@test "report: the failing heading names both readings and claims neither (0147)" {
  run bash -c '"$1" report <"$2"' _ "$REPORT" "$FIXTURES/rows-signers.jsonl"
  assert_success
  local heading
  heading="$(printf '%s\n' "$output" | grep '^DKIM PRESENT BUT NOT PASSING')" || fail "no such heading:\n$output"
  [ "$heading" = "DKIM PRESENT BUT NOT PASSING -- own mail broken in transit, or a forged signature (6 records)" ] ||
    fail "the heading reads: $heading"
  refute_output_contains "your own mail, failing"
}

@test "report: each signed row prints its signing domain and selector (0147)" {
  run bash -c '"$1" report <"$2"' _ "$REPORT" "$FIXTURES/rows-signers.jsonl"
  assert_success
  local failing auth
  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  # The forged selector and the domain's own, told apart by what the row says.
  [ "$(printf '%s\n' "$failing" | grep -c '198\.51\.100\.217 .*dkim=fail d=alpha\.example s=dkim  spf=softfail$')" -eq 2 ] ||
    fail "the forged-selector rows do not name d= and s=:\n$failing"
  grep -q '203\.0\.113\.9 .*dkim=fail d=bulk\.example s=google  spf=softfail$' <<<"$failing" ||
    fail "the foreign signer's row does not name it:\n$failing"
  grep -q '192\.0\.2\.70 .*dkim=fail d=alpha\.example s=google  spf=pass$' <<<"$failing" ||
    fail "the domain's own selector's row does not name it:\n$failing"
  # A passing signature is printed the same way: the row's shape is one shape.
  auth="$(section 'AUTHENTICATED' <<<"$output")"
  grep -q '192\.0\.2\.10 .*dkim=pass d=alpha\.example s=google  spf=pass$' <<<"$auth" ||
    fail "the passing row does not name its signer:\n$auth"
}

@test "report: a record with two signatures prints each, in order (0147)" {
  local row failing
  row="$(jq -c 'select(.source_ip == "198.51.100.217" and .count == 35)
    | .dkim_auth += [{"domain":"alpha.example","result":"fail","selector":"google"}]' "$FIXTURES/rows-signers.jsonl")"
  run bash -c 'printf "%s\n" "$1" | "$2" report' _ "$row" "$REPORT"
  assert_success
  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  grep -q 'dkim=fail d=alpha\.example s=dkim, fail d=alpha\.example s=google  spf=softfail$' <<<"$failing" ||
    fail "both signatures are not printed:\n$output"
}

@test "report: an empty signing domain and selector are each named as none, an absent one as absent (0147)" {
  run bash -c '"$1" report <"$2"' _ "$REPORT" "$FIXTURES/rows-signers.jsonl"
  assert_success
  local failing signed row
  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  grep -q '203\.0\.113\.173 .*dkim=fail d=none s=none  spf=softfail$' <<<"$failing" ||
    fail "the row with an empty signer does not name it as none:\n$failing"
  # CONTROL: a row with a signer never reads none.
  signed="$(printf '%s\n' "$failing" | grep '198\.51\.100\.217')" || fail "no signed row to read:\n$failing"
  [[ "$signed" != *none* ]] || fail "a signed row reads none:\n$failing"
  # An ABSENT selector element is not an empty one, as the parser keeps them
  # (infra.bats drives parse over one, through to this line).
  row="$(jq -c 'select(.source_ip == "203.0.113.173") | .dkim_auth[0].selector = null' "$FIXTURES/rows-signers.jsonl")"
  run bash -c 'printf "%s\n" "$1" | "$2" report' _ "$row" "$REPORT"
  assert_success
  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  grep -q 'dkim=fail d=none s=absent  spf=softfail$' <<<"$failing" ||
    fail "an absent selector is not named absent:\n$output"
  # An empty RESULT is named too: it is the field that decides the class.
  row="$(jq -c 'select(.source_ip == "192.0.2.70") | .dkim_auth[0].result = ""' "$FIXTURES/rows-signers.jsonl")"
  run bash -c 'printf "%s\n" "$1" | "$2" report' _ "$row" "$REPORT"
  assert_success
  failing="$(section 'DKIM PRESENT BUT NOT PASSING' <<<"$output")"
  grep -q 'dkim=none d=alpha\.example s=google  spf=pass$' <<<"$failing" ||
    fail "an empty result is not named none:\n$output"
}

@test "report: WHAT THIS CANNOT SEE says it cannot tell own mail from forged, and how to (0147)" {
  run bash -c '"$1" report <"$2"' _ "$REPORT" "$CLEAN"
  assert_success
  local blind want
  blind="$(section 'WHAT THIS CANNOT SEE' <<<"$output")"
  want="  - whether a failing signature is your own mail broken in transit or a forged
    one. Compare its d= and s= with the selectors the domain publishes. A
    planned infra mail dmarc check is to compare them
    with the profile."
  [ "$(printf '%s\n' "$blind" | grep -A3 'whether a failing signature')" = "$want" ] ||
    fail "the blind spot is not named whole:\n$blind"
}

@test "report: a failing signature beside a passing one prints both signers, under AUTHENTICATED (0147)" {
  # Where d= and s= matter most: a forged selector riding beside the domain's
  # own key, on a record DMARC passes.
  local row auth
  row="$(jq -c 'select(.source_ip == "192.0.2.10")
    | .dkim_auth += [{"domain":"alpha.example","result":"fail","selector":"dkim"}]' "$FIXTURES/rows-signers.jsonl")"
  run bash -c 'printf "%s\n" "$1" | "$2" report' _ "$row" "$REPORT"
  assert_success
  auth="$(section 'AUTHENTICATED' <<<"$output")"
  grep -q '192\.0\.2\.10 .*dkim=pass d=alpha\.example s=google, fail d=alpha\.example s=dkim  spf=pass$' <<<"$auth" ||
    fail "the passing record does not print both signers:\n$output"
}

@test "report: a record with no signature reads dkim=absent and names no signer (0147)" {
  # "absent" now means two things in one row: no signature at all, and a
  # signature whose selector the report left out. The first keeps its form.
  local row unauth
  row="$(jq -c 'select(.source_ip == "203.0.113.173") | .dkim_auth = []' "$FIXTURES/rows-signers.jsonl")"
  run bash -c 'printf "%s\n" "$1" | "$2" report' _ "$row" "$REPORT"
  assert_success
  unauth="$(section 'UNAUTHENTICATED' <<<"$output")"
  grep -q '203\.0\.113\.173 .*dkim=absent  spf=softfail$' <<<"$unauth" ||
    fail "the unsigned record does not read dkim=absent:\n$output"
  [[ "$unauth" != *d=* ]] || fail "an unsigned record names a signer:\n$unauth"
}

# The fixtures are shaped from real reports, and a real report names real
# senders. A tree published with them would publish those addresses, so every
# address a fixture carries is from the documentation ranges (RFC 5737). The
# floor: a scan that read no address cannot pass. It reads IPv4 in the fixture
# files alone, so a public sender's published IPv6 address that an arm here
# builds inline is not read, and none is in a fixture.
@test "the dmarc fixtures carry addresses from the documentation ranges alone (RFC 5737)" {
  local found outside
  found="$(LC_ALL=C grep -a -h -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' "$FIXTURES"/*)" ||
    fail "no address read out of the dmarc fixtures"
  outside="$(LC_ALL=C grep -v -E '^(192\.0\.2|198\.51\.100|203\.0\.113)\.' <<<"$found" || true)"
  [ -z "$outside" ] || fail "a dmarc fixture carries an address outside the documentation ranges:
$outside"
}
