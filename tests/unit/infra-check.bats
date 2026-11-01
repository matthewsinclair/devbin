#!/usr/bin/env bats
# infra-check.bats -- the DNS and mail legs of `infra check` (ST0003 WP-02).
#
# EVERY ARM DRIVES A FAKE `dig` ON PATH. The real one would make these arms
# depend on the internet, on somebody's estate, and on the day -- so they would
# be green most mornings and unreadable the rest, which is not a test. The seam
# is PATH because `lib/infra.dns` resolves `dig` through it and the rest of this
# suite already shadows tools that way (buildfmt.bats, builtins.bats).
#
# THE ARM THAT MATTERS MOST IS `an unreachable nameserver is NOT drift`. Every
# failure this thread exists to catch is a control that could only report
# success, and the easiest way to build one here is to let a failed read return
# "no records" -- which makes an unreachable zone indistinguishable from an
# empty one. The channels (ok / drift / could-not-measure / blind) exist
# for that single distinction, and these arms are what hold them apart.

load "../lib/test_helper"
load "../lib/infra_fakes"

setup() {
  devbin_setup
  BIN="$DEVBIN_TEST_TMPDIR/fakebin"
  FIX="$DEVBIN_TEST_TMPDIR/zone"
  mkdir -p "$BIN"
  : >"$FIX"
  mkdig
  mksleep
  INFRA="$DEVBIN_HOME/lib/cmd/infra"
  PROF="$DEVBIN_TEST_TMPDIR/infra.yaml"
}
teardown() { devbin_teardown; }

# A one-domain profile that is CLEAN against the zone written below it.
mkprofile() {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: none
    rua: dmarc@t.example
domains:
  alpha:
    name: alpha.example
YAML
}

clean_zone() {
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@t.example"'
}

check() {
  DIG_FIXTURE="$FIX" DIG_LOG="${DIG_LOG:-/dev/null}" DIG_NS_LOG="${DIG_NS_LOG:-/dev/null}" \
    SLEEP_LOG="${SLEEP_LOG:-/dev/null}" PATH="$BIN:$PATH" \
    run "$INFRA" check --profile "$PROF"
}

# authority_detail <fqdn> -- the detail of <fqdn>'s COULD NOT MEASURE authority
# row, whole, so an arm compares the sentence rather than finding a word of it.
# Two such rows print two lines, which no single sentence equals.
#
# WHOLE IN ITS WORDS, NOT IN ITS BYTES. The report passes every detail through
# _ic_flat (lib/infra.check), which folds runs of whitespace, so a doubled
# space inside the sentence reads the same here. infra-init.bats's
# every-attempt arm reads the generated profile, where nothing folds, and it
# is the arm that holds the exact bytes: it is not a copy of these, and
# deleting it as one would leave the sentence's spacing unheld.
authority_detail() {
  printf '%s\n' "$output" | awk -v f="$1" '$1 == f && $2 == "authority" {
    sub(/^ *[^ ]+ +authority +/, ""); print }'
}

# records_read_only_from <server> -- DIG_LOG holds at least one record read,
# and every one was addressed to <server>.
records_read_only_from() {
  [ -s "$DIG_LOG" ] || fail "no record query was logged at all"
  run awk -v s="$1" '$3 != s { print; n++ } END { exit (n > 0) }' "$DIG_LOG"
  [ "$status" -eq 0 ] || fail "record reads addressed to a server other than $1:\n$output"
}

# --- the green control -------------------------------------------------------

# AT-2.12
@test "a profile matching the zone PASSES, and rc is 0" {
  mkprofile; clean_zone
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  SLEEP_LOG="$DEVBIN_TEST_TMPDIR/sleep.log"
  : >"$SLEEP_LOG"
  check
  assert_success
  assert_output_contains "0 drift"
  assert_output_contains "0 NOT MEASURED"
  # One question to the machine's resolver, answered, and so no pause: a pause
  # here would be paid by every measured domain on every run (0142).
  [ "$(cat "$DIG_NS_LOG")" = "alpha.example -" ] ||
    fail "the NS lookups were not one, to the resolver:\n$(cat "$DIG_NS_LOG")"
  assert_file_empty "$SLEEP_LOG"
}

# --- errors are NOT drift ----------------------------------------------------

# AT-2.3
@test "an unreachable nameserver is COULD NOT MEASURE, never drift, and rc is 1 (0126)" {
  # THE CARDINAL ARM. If a failed read returned "no records", this domain would
  # be reported as missing its MX, its SPF and its DMARC -- three confident
  # verdicts about a domain nothing ever read.
  mkprofile
  zone '!NOAUTH alpha.example'
  check
  assert_exit_code 1
  assert_output_contains "COULD NOT MEASURE"
  assert_output_contains "NOTHING about this domain was checked"
  refute_output_contains "carries NO MX record"
}

# AT-2.3
@test "a read that fails mid-domain is an ERROR for that facet, not an absence" {
  mkprofile; clean_zone
  zone '!ERROR alpha.example MX'
  check
  assert_exit_code 1
  assert_output_contains "MX could not be read"
  refute_output_contains "carries NO MX record"
}

@test "the budget dig is given is the one DEVBIN_INFRA_DNS_TIMEOUT and DEVBIN_INFRA_DNS_TRIES set, on every query (0142)" {
  # The fake reads the budget's shape, not its values, so this is the arm that
  # holds the knobs reaching dig at all.
  mkprofile; clean_zone
  DIG_ARGV_LOG="$DEVBIN_TEST_TMPDIR/argv.log"
  DEVBIN_INFRA_DNS_TIMEOUT=7 DEVBIN_INFRA_DNS_TRIES=4 DIG_ARGV_LOG="$DIG_ARGV_LOG" check
  assert_success
  [ -s "$DIG_ARGV_LOG" ] || fail "no dig call was logged at all"
  run awk '$4 != "+time=7" || $5 != "+tries=4" { print; n++ } END { exit (n > 0) }' "$DIG_ARGV_LOG"
  [ "$status" -eq 0 ] || fail "dig calls without the budget the knobs set:\n$output"
}

@test "a record read answered SERVFAIL is COULD NOT MEASURE for that facet, never drift (0142)" {
  # A SERVFAIL comes back at dig's exit 0, so only the header status tells it
  # from an empty answer. Read as one, this domain carries NO MX record -- a
  # confident verdict about a record nobody read. 0142 rewrote the line that
  # refuses it, and until then no arm sent a record read anything but NOERROR.
  mkprofile; clean_zone
  zone '!STATUS alpha.example MX SERVFAIL'
  check
  assert_exit_code 1
  assert_output_contains "MX could not be read"
  refute_output_contains "carries NO MX record"
}

# AT-2.3
@test "COULD NOT MEASURE outranks DRIFT in the report, and both exit 1 (0126)" {
  # Both present: the drift is visible AND actionable in the output, while an
  # unmeasured facet is the one a scripted caller would bank as covered. The
  # ranking was the exit code, 2 over 1, until issue 0126 gave 2 back to the
  # dispatcher; it is the REPORT now, which names the unmeasured first.
  mkprofile; clean_zone
  zone '!ERROR _dmarc.alpha.example TXT'
  sed -i.bak 's/  ttl: 300/  ttl: 900/' "$PROF"
  check
  assert_exit_code 1
  local cm dr
  cm="$(awk '/^COULD NOT MEASURE/ { print NR; exit }' <<<"$output")"
  dr="$(awk '/^DRIFT/ { print NR; exit }' <<<"$output")"
  [ -n "$cm" ] && [ -n "$dr" ] || fail "the report did not carry both blocks: $output"
  [ "$cm" -lt "$dr" ] || fail "DRIFT printed above COULD NOT MEASURE (lines $dr and $cm): $output"
}

# --- the authority read: the one question put to the machine's resolver ------
#
# Issue 0142. The read that finds a domain's nameserver asked the machine's
# resolver once, took an empty answer as final, and listed the domain as "no
# authoritative nameserver answered" -- when devbin had asked no authoritative
# nameserver anything. For one infra user six runs each listed one to three live
# domains that way, and every one of them answered a moment later. These arms
# hold the re-ask, its bound, its pause, the knobs, and the words both commands
# print. Every NS lookup is logged with its server, and `-` on each line is the
# lookup going to the machine's resolver, which is what the sentence says.

@test "the fake dig answers only the argv lib/infra.dns sends, and nothing without a fixture (0142)" {
  # THE FAKE'S OWN CONTROL. A fake that answered any argv let a reader asking
  # without +answer pass every arm here, so its refusals are held too.
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  export DIG_NS_LOG
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 alpha.example NS
  assert_success
  assert_output_contains "ns1.alpha.example."
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +time=3 +tries=2 alpha.example NS
  assert_exit_code 64
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +short +time=3 +tries=2 alpha.example NS
  assert_exit_code 64
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 +norecurse @9.9.9.9 alpha.example NS
  assert_exit_code 64
  # A type infra never reads. (It was A until issue 0143 made A and AAAA types
  # infra reads, at a zone's wildcard.)
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 +norecurse @ns1.alpha.example. alpha.example SOA
  assert_exit_code 64
  # A record read with no server is not a read lib/infra.dns makes.
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 alpha.example MX
  assert_exit_code 64
  # The pre-0142 +short form only where a red-first run asks for it.
  DIG_FIXTURE="$FIX" run "$BIN/dig" +short +time=3 +tries=2 NS alpha.example
  assert_exit_code 64
  DIG_LEGACY=1 DIG_FIXTURE="$FIX" run "$BIN/dig" +short +time=3 +tries=2 NS alpha.example
  assert_success
  # And the pre-0193 record read, which asked with recursion (0193).
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 @ns1.alpha.example. alpha.example MX
  assert_exit_code 64
  DIG_LEGACY=1 DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 @ns1.alpha.example. alpha.example MX
  assert_success
  DIG_FIXTURE="$DEVBIN_TEST_TMPDIR/no-such-zone" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 alpha.example NS
  assert_exit_code 65
  run env -u DIG_FIXTURE "$BIN/dig" +noall +comments +answer +time=3 +tries=2 alpha.example NS
  assert_exit_code 65
  # A step the fixture grammar does not have is refused, not served as a status.
  zone '!NSSEQ beta.example SERVFALE'
  DIG_FIXTURE="$FIX" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 beta.example NS
  assert_exit_code 66
  # Named, since 66 is also the unknown-directive refusal below (0143).
  assert_output_contains "fake dig: !NSSEQ has no step SERVFALE"
  # A lookup addressed to a server is logged with it before it is refused, so
  # an arm's NS log shows where the question went; flags the fake cannot read
  # are refused before any lookup is made of them.
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example 9.9.9.9\nalpha.example -\nbeta.example -')" ] ||
    fail "the NS log is not the lookups with their servers:\n$(cat "$DIG_NS_LOG")"
  # A directive the fixture grammar does not have is refused, not skipped as
  # a line that names no record (0143). Its own fixture, so the log above is
  # untouched.
  printf '!EROR alpha.example MX\n' >"$DEVBIN_TEST_TMPDIR/typo-zone"
  DIG_FIXTURE="$DEVBIN_TEST_TMPDIR/typo-zone" run "$BIN/dig" +noall +comments +answer +time=3 +tries=2 +norecurse @ns1.alpha.example. alpha.example MX
  assert_exit_code 66
  assert_output_contains "fake dig: the fixture has no directive !EROR"
}

@test "an NS answer empty once and then filled is MEASURED, not listed, and the second lookup is what measured it (0142)" {
  mkprofile; clean_zone
  zone '!NSSEQ alpha.example NOERROR fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  SLEEP_LOG="$DEVBIN_TEST_TMPDIR/sleep.log"
  : >"$SLEEP_LOG"
  check
  assert_success
  assert_output_contains "3 assertion(s) held, 0 drift, 0 NOT MEASURED"
  refute_output_contains "COULD NOT MEASURE"
  # Two lookups and not three, both to the resolver: an answer ends the asking.
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not exactly two, to the resolver, for alpha.example:\n$(cat "$DIG_NS_LOG")"
  # One pause, between the two, and none after the answer.
  [ "$(grep -c . "$SLEEP_LOG")" -eq 1 ] ||
    fail "the pauses were not exactly one:\n$(cat "$SLEEP_LOG")"
  # And every record was then read from the server that second answer named.
  records_read_only_from ns1.alpha.example.
}

@test "an NS answer that fills only on the third and last attempt is still MEASURED (0142)" {
  # The bound's own edge. One attempt fewer, and this domain is listed.
  mkprofile; clean_zone
  zone '!NSSEQ alpha.example NOERROR NOERROR fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  check
  assert_success
  assert_output_contains "3 assertion(s) held, 0 drift, 0 NOT MEASURED"
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not three, to the resolver:\n$(cat "$DIG_NS_LOG")"
}

@test "an NXDOMAIN is asked again like any empty answer, and a fill after it is MEASURED (0142)" {
  # A resolver's NXDOMAIN for a live name is as transient as its SERVFAIL, and
  # lib/infra.dns names it among the answers that get a second question.
  mkprofile; clean_zone
  zone '!NSSEQ alpha.example NXDOMAIN fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  check
  assert_success
  assert_output_contains "3 assertion(s) held, 0 drift, 0 NOT MEASURED"
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not two, to the resolver:\n$(cat "$DIG_NS_LOG")"
}

@test "an NS answer carrying a row of another type never takes that row for the nameserver (0142)" {
  # A resolver following an alias answers an NS question with the CNAME row
  # first (and then the target's NS rows; the fake keeps them at one name). The
  # alias sorts ahead of the nameserver, so a reader taking every row would
  # read this domain's records from alias.example.
  mkprofile; clean_zone
  zone 'alpha.example CNAME 300 alias.example.'
  zone 'alpha.example NS 300 ns1.alpha.example.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_success
  records_read_only_from ns1.alpha.example.
}

@test "of two nameservers the sorted first is asked, whatever order the resolver lists them in (0142)" {
  # So two runs of one estate read one server, and a reader that took the
  # first row would read this domain from ns2.
  mkprofile; clean_zone
  zone 'alpha.example NS 300 ns2.alpha.example.'
  zone 'alpha.example NS 300 ns1.alpha.example.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_success
  records_read_only_from ns1.alpha.example.
}

@test "an NS answer empty on EVERY attempt is COULD NOT MEASURE at rc 1, saying what the resolver returned and that devbin asked no authoritative server (0142)" {
  # SERVFAIL, not the fixture's default NOERROR, so the status in the sentence
  # can only have come from the reply.
  mkprofile; clean_zone
  zone '!NOAUTH alpha.example SERVFAIL'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  : >"$DIG_LOG"
  check
  assert_exit_code 1
  assert_output_contains "0 assertion(s) held, 0 drift, 1 NOT MEASURED"
  local want="no NS record for alpha.example came from the machine's resolver on 3 attempt(s) (SERVFAIL, SERVFAIL, SERVFAIL), so devbin asked no authoritative nameserver -- NOTHING about this domain was checked"
  [ "$(authority_detail alpha.example)" = "$want" ] ||
    fail "the authority row is not the sentence, whole:\n  want: $want\n  got:  $(authority_detail alpha.example)"
  refute_output_contains "no authoritative nameserver answered"
  # Three lookups, each to the resolver, and not one read addressed to any
  # server -- which is what the sentence says.
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not three, to the resolver:\n$(cat "$DIG_NS_LOG")"
  assert_file_empty "$DIG_LOG"
}

@test "each attempt says what it got, in order, and a dig that could not run the query ends the asking with its own words (0142)" {
  # A reply under a status, a reply with no header, and a dig that exits 10.
  # The sentence names each in the order they came, and the third is dig's own
  # first line of complaint, since it contacted no resolver at all.
  mkprofile; clean_zone
  zone '!NSSEQ alpha.example SERVFAIL bare noreply:10 fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  check
  assert_exit_code 1
  local want="no NS record for alpha.example came from the machine's resolver on 3 attempt(s) (SERVFAIL, no status, dig exit 10: dig: the fixture step noreply:10), so devbin asked no authoritative nameserver -- NOTHING about this domain was checked"
  [ "$(authority_detail alpha.example)" = "$want" ] ||
    fail "the authority row is not the sentence, whole:\n  want: $want\n  got:  $(authority_detail alpha.example)"
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not three, to the resolver:\n$(cat "$DIG_NS_LOG")"
}

@test "a no-reply after an answer keeps the answer in the sentence, and is not asked again (0142)" {
  mkprofile; clean_zone
  zone '!NSSEQ alpha.example REFUSED noreply fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  check
  assert_exit_code 1
  local want="no NS record for alpha.example came from the machine's resolver on 2 attempt(s) (REFUSED, no reply), so devbin asked no authoritative nameserver -- NOTHING about this domain was checked"
  [ "$(authority_detail alpha.example)" = "$want" ] ||
    fail "the authority row is not the sentence, whole:\n  want: $want\n  got:  $(authority_detail alpha.example)"
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'alpha.example -\nalpha.example -')" ] ||
    fail "the NS lookups were not two, to the resolver:\n$(cat "$DIG_NS_LOG")"
}

@test "the pause before each re-ask is DEVBIN_INFRA_DNS_RETRY_PAUSE, one second by default, and is taken only between attempts (0142)" {
  # The fake sleep records its argument and returns at once, so this asserts
  # the pause rather than timing it, and no arm here waits for one.
  mkprofile
  zone '!NOAUTH alpha.example'
  SLEEP_LOG="$DEVBIN_TEST_TMPDIR/sleep.log"
  : >"$SLEEP_LOG"
  unset DEVBIN_INFRA_DNS_RETRY_PAUSE
  check
  assert_exit_code 1
  [ "$(cat "$SLEEP_LOG")" = "$(printf '1\n1')" ] ||
    fail "unset, the pauses were not two of one second:\n$(cat "$SLEEP_LOG")"
  : >"$SLEEP_LOG"
  DEVBIN_INFRA_DNS_RETRY_PAUSE=0 check
  assert_exit_code 1
  [ "$(cat "$SLEEP_LOG")" = "$(printf '0\n0')" ] ||
    fail "set to 0, the pauses were not two of 0:\n$(cat "$SLEEP_LOG")"
}

@test "a resolver that gives no reply is asked once, since dig has already retried it, and the line says no reply (0142)" {
  # A re-ask here would multiply dig's own timeout for every domain on a
  # machine whose resolver is down.
  mkprofile
  zone '!NSSEQ alpha.example noreply fill'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  SLEEP_LOG="$DEVBIN_TEST_TMPDIR/sleep.log"
  : >"$SLEEP_LOG"
  check
  assert_exit_code 1
  local want="no NS record for alpha.example came from the machine's resolver on 1 attempt(s) (no reply), so devbin asked no authoritative nameserver -- NOTHING about this domain was checked"
  [ "$(authority_detail alpha.example)" = "$want" ] ||
    fail "the authority row is not the sentence, whole:\n  want: $want\n  got:  $(authority_detail alpha.example)"
  [ "$(cat "$DIG_NS_LOG")" = "alpha.example -" ] ||
    fail "the NS lookups were not one, to the resolver:\n$(cat "$DIG_NS_LOG")"
  assert_file_empty "$SLEEP_LOG"
}

@test "a budget or pause that is not a whole number is refused once, before any domain is asked about (0142)" {
  # A pause sleep cannot parse runs the retries back to back, and a budget dig
  # cannot parse makes it exit 10 on every query: each quietly makes the run
  # something other than what it reports.
  mkprofile; clean_zone
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  : >"$DIG_NS_LOG"
  DEVBIN_INFRA_DNS_RETRY_PAUSE=abc check
  assert_exit_code 1
  assert_output_contains "infra check: DEVBIN_INFRA_DNS_RETRY_PAUSE must be a whole number below 100000, got 'abc'. Nothing was measured."
  refute_output_contains "assertion(s) held"
  DEVBIN_INFRA_DNS_TIMEOUT=-1 check
  assert_exit_code 1
  assert_output_contains "infra check: DEVBIN_INFRA_DNS_TIMEOUT must be a whole number below 100000, got '-1'. Nothing was measured."
  refute_output_contains "assertion(s) held"
  DEVBIN_INFRA_DNS_TRIES=2x check
  assert_exit_code 1
  assert_output_contains "infra check: DEVBIN_INFRA_DNS_TRIES must be a whole number below 100000, got '2x'. Nothing was measured."
  refute_output_contains "assertion(s) held"
  # A whole number dig still cannot parse: 9.10.6 exits 10 on this one.
  DEVBIN_INFRA_DNS_TIMEOUT=4294967296 check
  assert_exit_code 1
  assert_output_contains "infra check: DEVBIN_INFRA_DNS_TIMEOUT must be a whole number below 100000, got '4294967296'. Nothing was measured."
  refute_output_contains "assertion(s) held"
  assert_file_empty "$DIG_NS_LOG"
}

# --- the assertions that go red ---------------------------------------------

# AT-2.1
@test "a TTL differing from the profile is drift, and names both values" {
  mkprofile
  zone 'alpha.example MX 900 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@t.example"'
  check
  assert_exit_code 1
  assert_output_contains "ttl is 900, profile declares 300"
}

# AT-2.1
@test "a domain declaring mail: with NO MX record is drift" {
  mkprofile
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@t.example"'
  check
  assert_exit_code 1
  assert_output_contains "carries NO MX record"
}

# AT-2.1
@test "two SPF records is drift with no profile field and no vendor knowledge" {
  # RFC 7208 permits exactly one. Two evaluates as none, so this is checkable
  # at every N and needs nothing shipped.
  mkprofile; clean_zone
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.mailersend.net ~all"'
  check
  assert_exit_code 1
  assert_output_contains "2 SPF records"
}

# AT-2.1
@test "a missing _dmarc record where the profile declares a policy is drift" {
  mkprofile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  assert_exit_code 1
  assert_output_contains "there is NO _dmarc record"
}

# AT-2.1
@test "a live DMARC policy differing from the profile is drift" {
  mkprofile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=quarantine; rua=mailto:dmarc@t.example"'
  check
  assert_exit_code 1
  assert_output_contains "live policy is p=quarantine"
}

# --- the half pair, which is the sharpest check in the leg -------------------

# AT-2.7
@test "SPF authorising a sender with NO DKIM record is a HALF PAIR, stated in full" {
  # A real domain's finding. It makes that domain's own legitimate mail
  # indistinguishable from a forgery of it and is silent until mail flows, so
  # the message says so rather than printing a field name.
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: acme1._domainkey
      type: CNAME
      value: acme1._domainkey.acme.example
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  check
  assert_exit_code 1
  assert_output_contains "HALF PAIR"
  assert_output_contains "indistinguishable from a forgery"
}

# AT-2.7
# AT-2.12
@test "POSITIVE CONTROL: the matched pair present is not drift" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: acme1._domainkey
      type: CNAME
      value: acme1._domainkey.acme.example
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example CNAME 300 acme1._domainkey.acme.example.'
  check
  refute_output_contains "HALF PAIR"
}

# AT-6.3
# AT-2.9
@test "a sender the profile never DEFINES stops CHECK before it reaches the network" {
  # THIS ARM ONCE CHANGED VERDICT AND IS KEPT RATHER THAN DELETED, because the
  # concern it guards -- an undefined sender must never be passed over -- is
  # still live; only the LAYER moved. It used to assert exit 2 and a COULD NOT
  # MEASURE row, a channel headed "gaps in the INSTRUMENT, not verdicts".
  # Nothing about the instrument was missing: the profile named a sender it
  # never described, which is an incomplete TARGET. It is now a parse-time
  # refusal (AC-6.3), and the old criterion is withdrawn on the record rather
  # than quietly reworded.
  #
  # It stays HERE, at check's entry point, because that is where the wrong
  # answer used to be produced -- and it proves the two layers compose: the
  # refusal beats check to the network rather than merely existing.
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
domains:
  alpha:
    name: alpha.example
    senders:
      - ghost
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  : >"$DIG_LOG"
  check
  assert_failure
  assert_output_contains "never defines"
  assert_output_contains "Nothing was checked against the live estate"
  assert_file_empty "$DIG_LOG"
}

# --- consistency replaces the deleted STANDARD -------------------------------

# AT-2.8
@test "at N=1 form consistency reports NOT COMPARABLE rather than passing" {
  # The degradation that makes this honest at the modal project size. A
  # comparison over a population of one is not a green.
  mkprofile; clean_zone
  check
  assert_success
  assert_output_contains "NOT COMPARABLE"
}

# AT-2.1
@test "two domains on one mail: value with DIFFERENT MX forms is drift" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone 'beta.example MX 300 10 aspmx.l.google.com.'
  zone 'beta.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  assert_exit_code 1
  assert_output_contains "2 DIFFERENT MX forms"
  # NO VENDOR VALUE IS ASSERTED ANYWHERE. The check fires on disagreement, so
  # it ships nothing that can be confidently wrong -- and needs no STANDARD,
  # which is what let this leg be built while WP-03's dependency stays open.
  refute_output_contains "should be"
}

# AT-2.12
@test "POSITIVE CONTROL: two domains AGREEING on a form is not drift" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone 'beta.example MX 300 1 smtp.google.com.'
  zone 'beta.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  refute_output_contains "DIFFERENT MX forms"
}

# --- what every run must say about itself, green or red ----------------------

# AT-2.4
# AT-7.2
@test "the blind-spot block prints on a GREEN run, where silence is most tempting" {
  mkprofile; clean_zone
  check
  assert_success
  assert_output_contains "blind spots in this run"
  assert_output_contains "not machine-checkable"
  # The unbuilt leg, named as the reference names it (issue 0121): this said
  # WP-07 while lib/infra.reference.yaml said ST0006, for the same leg. Neither
  # is printed now: a user reads what is not built, not which thread builds it
  # (0172).
  assert_output_contains "The Fly runtime, not built yet,"
  refute_output_contains "WP-07"
  refute_output_contains "ST0006"
}

@test "a profile with no name: reports as (unnamed), as the reference promises (0121)" {
  # `cfg_get name 2>/dev/null || printf '(unnamed)'` could never fall back:
  # cfg_get prints its default and returns 0 for an absent key, so the header
  # read `infra check:  (<path>)` with the name blank.
  # mkprofile's profile, less its name: line.
  cat >"$PROF" <<'YAML'
version: 1
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: none
    rua: dmarc@t.example
domains:
  alpha:
    name: alpha.example
YAML
  clean_zone
  check
  assert_success
  assert_output_contains "infra check: (unnamed) ($PROF)"
}

# AT-2.11
@test "p=none is named as enforcing nothing even when the record is CLEAN" {
  # Disposition is not authentication. A summary that goes quiet exactly when
  # it looks good is the thing this command is built against.
  mkprofile; clean_zone
  check
  assert_success
  assert_output_contains "enforces nothing"
}

# AT-2.10
@test "manual: items are NAMED on a green run and never checked" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  manual:
    catchall: "a group email@<domain> exists"
domains:
  alpha:
    name: alpha.example
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  assert_success
  assert_output_contains "a group email@<domain> exists"
  assert_output_contains "NEVER verified"
}

# AT-2.10
@test "a manual: item is named even when the domain could not be reached" {
  # It records intent and is not contingent on the network, so a domain that
  # drops out of every DNS assertion must not drop out of the checklist too.
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  manual:
    catchall: "a group email@<domain> exists"
domains:
  alpha:
    name: alpha.example
YAML
  zone '!NOAUTH alpha.example'
  check
  assert_exit_code 1
  assert_output_contains "a group email@<domain> exists"
}

# AT-2.11
@test "dmarc: none is a NAMED opt-out, not a check and not a silent pass" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: none
    rua: dmarc@t.example
domains:
  alpha:
    name: alpha.example
    dmarc: none
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  assert_success
  assert_output_contains "outside the reporting estate by declaration"
  refute_output_contains "NO _dmarc record"
}

# --- the instrument itself ---------------------------------------------------

# AT-2.2
@test "every record read is AUTHORITATIVE -- addressed to the zone's own server" {
  # A recursive read returns the REMAINING ttl, not the CONFIGURED one, so a
  # `ttl:` assertion read through a cache reports drift that is an artefact of
  # when the command ran. Measured on cloudflare.com: configured 1800, through
  # the resolver 780. Asserting the `@` is what keeps that true.
  mkprofile; clean_zone
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log" check
  assert_success
  [ -s "$DEVBIN_TEST_TMPDIR/dig.log" ] || fail "no record query was logged at all"
  run awk 'NF < 3 || $3 == "" { print; n++ } END { exit (n > 0) }' "$DEVBIN_TEST_TMPDIR/dig.log"
  assert_success
}

# AT-2.6
@test "the header count and the DRIFT listing agree" {
  # A count that disagrees with its own listing is a caught error; a count
  # alone is a silent one. This once read 14 against 3 rendered rows on a real
  # estate, because a multi-line detail inflated `grep -c` while rendering once.
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
YAML
  zone 'alpha.example MX 900 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone 'beta.example MX 300 10 aspmx.l.google.com.'
  zone 'beta.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  check
  said="$(printf '%s\n' "$output" | sed -n 's/.*held, \([0-9]*\) drift.*/\1/p')"
  shown="$(printf '%s\n' "$output" | sed -n '/^DRIFT/,/^$/p' | grep -c '^  ')"
  [ "$said" = "$shown" ] || fail "header says $said drift, listing shows $shown"
}

# --- THE ARMS THE ACCEPTANCE CONTRACT FOUND MISSING --------------------------
#
# These cover refusals that shipped with no test at all, and each was found by
# writing ST0003's acceptance criteria rather than by reading the code again.
# None is a new behaviour; what was missing was the arm that could go red if
# the behaviour were removed.

# AT-1.1
@test "a malformed PROFILE refuses before the estate is contacted, and says nothing was checked" {
  # THE ONE LINE SEPARATING A BAD PROFILE FROM A BAD ESTATE. `check` reads live
  # DNS, so a malformed profile reaching the network would produce a verdict
  # about an estate from an expectation nobody wrote -- and the operator would
  # read it as a statement about their zone. The refusal must say that nothing
  # was measured, and this arm proves the network was never touched rather than
  # trusting the order of statements in the source: DIG_LOG stays EMPTY.
  cat >"$PROF" <<'YAML'
version: 1
name: t
domains:
  orphan:
    mail: google
YAML
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  : >"$DIG_LOG"
  check
  assert_failure
  assert_output_contains "Nothing was checked against the live estate"
  assert_file_empty "$DIG_LOG"
}

# AT-2.5
@test "a missing resolver is ONE error naming the tool, not one row per domain" {
  # The fault is a single absent dependency. Reported per-domain it becomes
  # N rows of COULD NOT MEASURE -- each individually true -- and the one line
  # anybody can act on is buried under its own consequences. Two domains here
  # so that "one error" and "one per domain" are distinguishable at all.
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
YAML
  # dig OFF PATH entirely -- `infra_dns_have_tool` asks `command -v`, which only
  # finds an executable, so shadowing it cannot express absence. The link farm
  # carries everything else the script needs and omits exactly one name.
  NODIG="$DEVBIN_TEST_TMPDIR/nodig"
  mkdir -p "$NODIG"
  # bash comes from the bash running this suite, NOT from /bin: on macOS that is
  # 3.2, which lib/helpers refuses at load (issue 0076). Before the floor
  # reached handlers this arm ran the handler on 3.2 without anyone knowing.
  ln -s "$BASH" "$NODIG/bash"
  # Each name is linked once, where it is first found. The test is -L, not -e:
  # -e follows the link, and a system's /usr/bin can hold a dangling one, which
  # comes round again wherever /bin is /usr/bin, and ln -s then refuses it.
  for d in /usr/bin /bin; do
    for f in "$d"/*; do
      b="${f##*/}"
      [ "$b" = dig ] || [ -L "$NODIG/$b" ] || ln -s "$f" "$NODIG/$b"
    done
  done
  run env -i PATH="$NODIG" HOME="$HOME" XDG_DATA_HOME="$XDG_DATA_HOME" DEVBIN_LIB="$DEVBIN_HOME/lib" \
    "$INFRA" check --profile "$PROF"
  assert_failure
  assert_output_contains "dig not found"
  refute_output_contains "COULD NOT MEASURE"
  refute_output_contains "assertion(s) held"
}

# ============================================================================
# ISSUE 0143: the fields the profile could not hold, and a key it never read
# ============================================================================
#
# A profile could not declare a sender's second DKIM key, a DMARC sp=, or a
# zone's wildcard records, and a key written for any of them parsed, validated
# and was never read. One profile carrying all three, driven against a zone
# missing all three, read "4 assertion(s) held, 0 drift, 0 NOT MEASURED", rc 0.

# row_detail <fqdn> <facet> -- the detail of every report row for <fqdn> under
# <facet>, WHOLE, one per line, from whichever section printed it. An arm
# compares the sentence rather than finding a word of it.
row_detail() {
  printf '%s\n' "$output" | awk -v f="$1" -v c="$2" '$1 == f && $2 == c {
    line = $0; sub(/^ +/, "", line)
    line = substr(line, length($1) + 1); sub(/^ +/, "", line)
    line = substr(line, length($2) + 1); sub(/^ +/, "", line)
    print line }'
}

# --- a sender's several DKIM records ------------------------------------------

# One domain naming `mailersend`, whose `dkim:` block is $1.
mksender_profile() {
  cat >"$PROF" <<YAML
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  mailersend:
    spf_include: _spf.mailersend.net
    dkim:
$1
domains:
  alpha:
    name: alpha.example
    senders:
      - mailersend
YAML
}

# MailerSend's pair, in the labelled form.
LABELLED_MS='      ms1:
        name: ms1._domainkey
        type: CNAME
        value: ms1._domainkey.mailersend.net
      ms2:
        name: ms2._domainkey
        type: CNAME
        value: ms2._domainkey.mailersend.net'

# MX, and an SPF record authorising mailersend.
sender_zone() {
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com include:_spf.mailersend.net ~all"'
}

HALF_MS2="SPF authorises \`mailersend\` but there is NO DKIM record at ms2._domainkey.alpha.example -- HALF PAIR: this domain's own legitimate mail is indistinguishable from a forgery of it"

# AT-2.7
@test "a sender's SECOND DKIM record missing is a HALF PAIR naming that record, and both records are asked for (0143)" {
  mksender_profile "$LABELLED_MS"
  sender_zone
  zone 'ms1._domainkey.alpha.example CNAME 300 ms1._domainkey.mailersend.net.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example pair:mailersend)" = "$HALF_MS2" ] ||
    fail "the HALF PAIR row is not ms2's, whole:\n  want: $HALF_MS2\n  got:  $(row_detail alpha.example pair:mailersend)\n$output"
  grep -qxF 'ms1._domainkey.alpha.example CNAME ns1.alpha.example.' "$DIG_LOG" ||
    fail "ms1 was not asked for on the authoritative server:\n$(cat "$DIG_LOG" 2>/dev/null)"
  grep -qxF 'ms2._domainkey.alpha.example CNAME ns1.alpha.example.' "$DIG_LOG" ||
    fail "ms2 was not asked for on the authoritative server:\n$(cat "$DIG_LOG" 2>/dev/null)"
}

# AT-2.7
# AT-2.12
@test "POSITIVE CONTROL: both labelled records present hold, and each is counted (0143)" {
  mksender_profile "$LABELLED_MS"
  sender_zone
  zone 'ms1._domainkey.alpha.example CNAME 300 ms1._domainkey.mailersend.net.'
  zone 'ms2._domainkey.alpha.example CNAME 300 ms2._domainkey.mailersend.net.'
  check
  assert_success
  # MX, SPF, and one per DKIM record.
  assert_output_contains "4 assertion(s) held, 0 drift, 0 NOT MEASURED"
}

# AT-2.3
@test "one record unreadable and the other absent: NOT MEASURED for the one and HALF PAIR for the other (0143)" {
  # A read that failed withholds no verdict about a record that was read.
  mksender_profile "$LABELLED_MS"
  sender_zone
  zone '!ERROR ms1._domainkey.alpha.example CNAME'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:mailersend)" = "ms1._domainkey.alpha.example could not be read" ] ||
    fail "ms1 is not NOT MEASURED, whole: $(row_detail alpha.example dkim:mailersend)\n$output"
  [ "$(row_detail alpha.example pair:mailersend)" = "$HALF_MS2" ] ||
    fail "ms2 is not the HALF PAIR, whole: $(row_detail alpha.example pair:mailersend)\n$output"
}

# AT-2.1
@test "a labelled record's declared value is compared for that record (0143)" {
  mksender_profile "$LABELLED_MS"
  sender_zone
  zone 'ms1._domainkey.alpha.example CNAME 300 ms1._domainkey.mailersend.net.'
  zone 'ms2._domainkey.alpha.example CNAME 300 ms9._domainkey.mailersend.net.'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:mailersend)" = "DKIM at ms2._domainkey.alpha.example does not carry the declared value" ] ||
    fail "the value drift is not ms2's alone, whole: $(row_detail alpha.example dkim:mailersend)\n$output"
}

# The one-record sender every earlier arm uses, with its DKIM type as $1.
acme_profile() {
  cat >"$PROF" <<YAML
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: ${2:-acme1._domainkey}
      type: ${1:-CNAME}
      value: ${3:-acme1._domainkey.acme.example}
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
YAML
}

# AT-2.7
@test "CONTROL: the one-record form asks ONE DKIM question and prints the HALF PAIR line it always has (0143)" {
  # Byte for byte what it printed before the labelled form: that form is new,
  # and a profile written before it must read exactly as it did.
  acme_profile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_exit_code 1
  local want="SPF authorises \`acme\` but there is NO DKIM record at acme1._domainkey.alpha.example -- HALF PAIR: this domain's own legitimate mail is indistinguishable from a forgery of it"
  [ "$(row_detail alpha.example pair:acme)" = "$want" ] ||
    fail "the one-record HALF PAIR line changed:\n  want: $want\n  got:  $(row_detail alpha.example pair:acme)"
  [ "$(grep -c '_domainkey' "$DIG_LOG")" -eq 1 ] ||
    fail "the one-record form did not ask exactly one DKIM question:\n$(cat "$DIG_LOG")"
  grep -qxF 'acme1._domainkey.alpha.example CNAME ns1.alpha.example.' "$DIG_LOG" ||
    fail "the DKIM question was not the declared one:\n$(cat "$DIG_LOG")"
}

# AT-2.1
@test "a TXT DKIM key split across strings is compared JOINED, as a resolver sees it (0143)" {
  # Every 2048-bit key is published as several strings, and DNS defines the
  # value as their concatenation. Read raw, a correct key reported as drift.
  acme_profile TXT sel._domainkey '"v=DKIM1; k=rsa; p=AAAABBBBCCCC"'
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'sel._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=AAAA" "BBBBCCCC"'
  check
  assert_success
  assert_output_contains "3 assertion(s) held, 0 drift, 0 NOT MEASURED"
  refute_output_contains "does not carry the declared value"
  # THE RED TWIN: the same split record carrying another key is drift, so the
  # joined read compares the value rather than accepting any TXT there.
  : >"$FIX"
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'sel._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=AAAA" "BBBBDDDD"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "DKIM at sel._domainkey.alpha.example does not carry the declared value" ] ||
    fail "a joined key differing from the declared one is not drift, whole: $(row_detail alpha.example dkim:acme)\n$output"
}

# AT-2.1
@test "a DKIM name carrying two TXT records is compared as a SET: one declared value is drift whichever record it names (0143)" {
  # Only the FIRST record the server listed was compared, and the order is the
  # server's: a profile naming it held and one naming the other drifted, over
  # the same zone. RFC 6376 (section 3.6.2.2) lets a verifier pick either
  # record or fail, so a second record at a selector is a fault the profile's
  # one value does not describe, and it is drift naming the whole set.
  acme_profile TXT sel._domainkey '"v=DKIM1; k=rsa; p=FIRST"'
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'sel._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=FIRST"'
  zone 'sel._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=SECOND"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "DKIM at sel._domainkey.alpha.example carries 2 records, v=DKIM1; k=rsa; p=FIRST | v=DKIM1; k=rsa; p=SECOND, where the profile declares one: v=DKIM1; k=rsa; p=FIRST" ] ||
    fail "naming the first record listed, whole: $(row_detail alpha.example dkim:acme)\n$output"
  acme_profile TXT sel._domainkey '"v=DKIM1; k=rsa; p=SECOND"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "DKIM at sel._domainkey.alpha.example carries 2 records, v=DKIM1; k=rsa; p=FIRST | v=DKIM1; k=rsa; p=SECOND, where the profile declares one: v=DKIM1; k=rsa; p=SECOND" ] ||
    fail "naming the second record listed, whole: $(row_detail alpha.example dkim:acme)\n$output"
}

# AT-2.1
@test "a TXT value is compared as written: one differing only in case or a trailing dot is drift, where a CNAME name would not be (0143)" {
  # Only a NAME is compared as DNS compares names. A TXT record is bytes, and a
  # DKIM key or a wildcard SPF differing in case is another value.
  acme_profile TXT sel._domainkey '"v=DKIM1; k=rsa; p=abcd"'
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'sel._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=ABCD"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "DKIM at sel._domainkey.alpha.example does not carry the declared value" ] ||
    fail "a TXT key differing in case held, whole: $(row_detail alpha.example dkim:acme)\n$output"
  mkprofile
  cat >>"$PROF" <<'YAML'
    wildcard:
      txt: "v=spf1 -all"
YAML
  : >"$FIX"
  clean_zone
  zone '*.alpha.example TXT 300 "v=spf1 -all."'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.txt)" = "wildcard TXT at *.alpha.example is v=spf1 -all., profile declares v=spf1 -all" ] ||
    fail "a TXT differing by a trailing dot held, whole: $(row_detail alpha.example wildcard.txt)\n$output"
}

# AT-2.1
@test "a CNAME DKIM value is compared whole, as DNS compares a name: a longer target is drift, case and the root dot are not (0143)" {
  # It was a SUBSTRING match, so a declared target that was only the tail of
  # the live one held. A name's case and its trailing dot are not part of it.
  acme_profile CNAME acme1._domainkey acme1._domainkey.acme.example
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example CNAME 300 old.acme1._domainkey.acme.example.'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "DKIM at acme1._domainkey.alpha.example does not carry the declared value" ] ||
    fail "a target the declared one is only the tail of held, whole: $(row_detail alpha.example dkim:acme)\n$output"
  # CONTROL: the same name in another case, against the target with its root
  # dot, holds.
  acme_profile CNAME acme1._domainkey ACME1._domainkey.acme.example
  : >"$FIX"
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example CNAME 300 acme1._domainkey.acme.example.'
  check
  assert_success
  assert_output_contains "3 assertion(s) held, 0 drift, 0 NOT MEASURED"
}

# AT-2.1
@test "a wildcard TXT is compared as a SET of records: two strings that spell the declared value only when joined are drift (0143)" {
  # The live set was sorted, joined on a space and compared as one string, so
  # the two records `v=spf1` and `~all` read as the one record `v=spf1 ~all`.
  mkprofile
  cat >>"$PROF" <<'YAML'
    wildcard:
      txt: "v=spf1 ~all"
YAML
  clean_zone
  zone '*.alpha.example TXT 300 "~all"'
  zone '*.alpha.example TXT 300 "v=spf1"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.txt)" = "wildcard TXT at *.alpha.example is v=spf1 | ~all, profile declares v=spf1 ~all" ] ||
    fail "two records read as one, whole: $(row_detail alpha.example wildcard.txt)\n$output"
}

# AT-2.3
@test "an SPF record lacking the include is drift even when a DKIM read fails (0143)" {
  # The SPF record was read. A DKIM read failing after it makes that no less
  # measured, and it used to hide it.
  acme_profile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '!ERROR acme1._domainkey.alpha.example CNAME'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dkim:acme)" = "acme1._domainkey.alpha.example could not be read" ] ||
    fail "the DKIM read is not NOT MEASURED, whole: $(row_detail alpha.example dkim:acme)\n$output"
  [ "$(row_detail alpha.example spf:acme)" = "declares sender \`acme\` and its SPF does NOT include _spf.acme.example" ] ||
    fail "the SPF drift is missing, whole: $(row_detail alpha.example spf:acme)\n$output"
}

# --- DMARC sp=, and the p= that was never compared ---------------------------

# mkprofile_sp <sp> [policy] -- mkprofile's profile, with `dmarc.sp` under defaults.
mkprofile_sp() {
  cat >"$PROF" <<YAML
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: ${2:-none}
    rua: dmarc@t.example
    sp: $1
domains:
  alpha:
    name: alpha.example
YAML
}

# dmarc_zone <record> [fqdn] -- a clean MX and SPF, and a _dmarc record of <record>.
dmarc_zone() {
  local f="${2:-alpha.example}"
  zone "$f MX 300 1 smtp.google.com."
  zone "$f TXT 300 \"v=spf1 include:_spf.google.com ~all\""
  zone "_dmarc.$f TXT 300 \"$1\""
}

# AT-2.1
@test "dmarc.sp is compared with the live sp=: differing is drift naming both, agreeing holds whatever p= says (0143)" {
  mkprofile_sp reject
  dmarc_zone 'v=DMARC1; p=none; sp=none; rua=mailto:dmarc@t.example'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dmarc.sp)" = "live subdomain policy is sp=none, profile declares reject" ] ||
    fail "the sp drift is not whole: $(row_detail alpha.example dmarc.sp)\n$output"
  # An explicit sp= is the subdomain policy; p= is compared only in its absence.
  : >"$FIX"
  dmarc_zone 'v=DMARC1; p=none; sp=reject; rua=mailto:dmarc@t.example'
  check
  assert_success
  [ -z "$(row_detail alpha.example dmarc.sp)" ] ||
    fail "an sp= agreeing with the profile was compared with p= instead: $(row_detail alpha.example dmarc.sp)"
}

# AT-2.1
@test "dmarc.sp against a record with no sp= compares p=, and the line says so (0143)" {
  # RFC 7489 6.3: absent, the subdomain policy IS p=. The line names which
  # value it compared and where that value came from.
  mkprofile_sp reject
  dmarc_zone 'v=DMARC1; p=none; rua=mailto:dmarc@t.example'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dmarc.sp)" = "live subdomain policy is p=none -- the record carries no sp=, so p= applies -- profile declares reject" ] ||
    fail "the p= fallback is not whole: $(row_detail alpha.example dmarc.sp)\n$output"
}

# AT-2.1
@test "dmarc.sp under defaults applies to every domain, and a domain's own sp overrides it (0143)" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  dmarc:
    policy: none
    rua: dmarc@t.example
    sp: reject
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
    dmarc:
      sp: none
YAML
  dmarc_zone 'v=DMARC1; p=none; sp=none; rua=mailto:dmarc@t.example' alpha.example
  # beta's live sp=reject is what the defaults declare, so a row for beta can
  # only come from its own `sp: none` being the value compared.
  dmarc_zone 'v=DMARC1; p=none; sp=reject; rua=mailto:dmarc@t.example' beta.example
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dmarc.sp)" = "live subdomain policy is sp=none, profile declares reject" ] ||
    fail "alpha did not inherit the defaults' sp: $(row_detail alpha.example dmarc.sp)\n$output"
  [ "$(row_detail beta.example dmarc.sp)" = "live subdomain policy is sp=reject, profile declares none" ] ||
    fail "beta's own sp did not override the defaults', whole: $(row_detail beta.example dmarc.sp)\n$output"
}

# AT-2.11
@test "an explicit sp= that enforces nothing is a NAMED blind spot on a clean run (0143)" {
  # p=reject and sp=none: the domain enforces and every subdomain is delivered.
  # A summary that goes quiet exactly when it looks good is the thing this
  # command is built against.
  mkprofile
  sed -i.bak 's/policy: none/policy: reject/' "$PROF"
  dmarc_zone 'v=DMARC1; p=reject; sp=none; rua=mailto:dmarc@t.example'
  check
  assert_success
  [ "$(row_detail alpha.example dmarc.sp.enforce)" = "sp=none: forged mail from a SUBDOMAIN is delivered and merely reported" ] ||
    fail "the weak sp= is not named, whole: $(row_detail alpha.example dmarc.sp.enforce)\n$output"
  [ -z "$(row_detail alpha.example dmarc.enforcement)" ] || fail "p=reject was named as enforcing nothing"
}

# AT-2.1
@test "a declared policy against a record with NO p= tag is drift, not a clean pass (0143)" {
  # It printed "0 drift" at rc 0: the comparison ran only when the record
  # carried a p= to compare with.
  mkprofile
  dmarc_zone 'v=DMARC1; rua=mailto:dmarc@t.example'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example dmarc.p)" = "the record carries NO p= tag, profile declares none -- RFC 7489 requires one" ] ||
    fail "the missing p= is not drift, whole: $(row_detail alpha.example dmarc.p)\n$output"
}

# --- wildcards ------------------------------------------------------------------

# mkprofile_wild <lines> -- mkprofile's profile, with <lines> as alpha's wildcard: block.
mkprofile_wild() {
  mkprofile
  printf '    wildcard:\n%s\n' "$1" >>"$PROF"
}

WILD_NONE='      a: none
      aaaa: none
      txt: none'

# AT-2.1
# AT-2.2
@test "a declared wildcard TXT is read at the wildcard name on the authoritative server, and its absence is drift (0143)" {
  mkprofile_wild '      txt: "v=spf1 -all"'
  clean_zone
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.txt)" = "declares wildcard TXT v=spf1 -all and *.alpha.example carries NO TXT record" ] ||
    fail "the missing wildcard TXT is not drift, whole: $(row_detail alpha.example wildcard.txt)\n$output"
  grep -qxF '*.alpha.example TXT ns1.alpha.example.' "$DIG_LOG" ||
    fail "the wildcard was not asked for on the authoritative server:\n$(cat "$DIG_LOG")"
}

# AT-2.1
@test "a wildcard A that differs, or carries an extra address, is drift naming the live set (0143)" {
  # An extra address at the wildcard sends every name that does not exist
  # somewhere nobody declared.
  mkprofile_wild '      a: 192.0.2.7'
  clean_zone
  zone '*.alpha.example A 300 192.0.2.7'
  zone '*.alpha.example A 300 192.0.2.8'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.a)" = "wildcard A at *.alpha.example is 192.0.2.7 192.0.2.8, profile declares 192.0.2.7" ] ||
    fail "the extra address is not drift, whole: $(row_detail alpha.example wildcard.a)\n$output"
  : >"$FIX"
  clean_zone
  zone '*.alpha.example A 300 192.0.2.9'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.a)" = "wildcard A at *.alpha.example is 192.0.2.9, profile declares 192.0.2.7" ] ||
    fail "the differing address is not drift, whole: $(row_detail alpha.example wildcard.a)\n$output"
}

# AT-2.12
@test "POSITIVE CONTROL: wildcard A, AAAA and TXT matching the zone hold, and a wildcard ttl differing is drift (0143)" {
  mkprofile_wild '      a: 192.0.2.7
      aaaa: 2001:db8::7
      txt: "v=spf1 -all"'
  clean_zone
  zone '*.alpha.example A 300 192.0.2.7'
  zone '*.alpha.example AAAA 300 2001:db8::7'
  zone '*.alpha.example TXT 300 "v=spf1 -all"'
  check
  assert_success
  # MX, SPF and DMARC, and the three wildcard sets.
  assert_output_contains "6 assertion(s) held, 0 drift, 0 NOT MEASURED"
  : >"$FIX"
  clean_zone
  zone '*.alpha.example A 900 192.0.2.7'
  zone '*.alpha.example AAAA 300 2001:db8::7'
  zone '*.alpha.example TXT 300 "v=spf1 -all"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.a.ttl)" = "ttl is 900, profile declares 300" ] ||
    fail "the wildcard ttl is not checked, whole: $(row_detail alpha.example wildcard.a.ttl)\n$output"
}

# AT-2.1
# AT-2.12
@test "a declared wildcard ABSENCE holds on a zone with none and goes red on one (0143)" {
  # A real zone's case: no wildcard, and nothing but a manual: line recorded it.
  mkprofile_wild "$WILD_NONE"
  clean_zone
  check
  assert_success
  assert_output_contains "6 assertion(s) held, 0 drift, 0 NOT MEASURED"
  zone '*.alpha.example A 300 192.0.2.7'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.a)" = "declares NO wildcard A and *.alpha.example carries 192.0.2.7" ] ||
    fail "the declared absence did not go red, whole: $(row_detail alpha.example wildcard.a)\n$output"
}

# AT-2.1
@test "a wildcard CNAME contradicts a declared absence, since it answers for every type (0143)" {
  # It is no A, AAAA or TXT record itself, so a read of those types alone
  # would call this zone clean.
  mkprofile_wild "$WILD_NONE"
  clean_zone
  zone '*.alpha.example CNAME 300 elsewhere.example.'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard)" = "*.alpha.example is a CNAME to elsewhere.example., which answers for every type -- the profile declares no wildcard A AAAA TXT" ] ||
    fail "the wildcard CNAME is not drift, whole: $(row_detail alpha.example wildcard)\n$output"
}

# AT-2.3
@test "a wildcard read that fails is NOT MEASURED, never an absence (0143)" {
  # Staged with the fake's LITERAL !ERROR match: under a regex match the `*`
  # never matched, and the fake answered NOERROR with nothing in it.
  mkprofile_wild '      a: 192.0.2.7'
  clean_zone
  zone '!ERROR *.alpha.example A'
  check
  assert_exit_code 1
  assert_output_contains "3 assertion(s) held, 0 drift, 1 NOT MEASURED"
  [ "$(row_detail alpha.example wildcard.a)" = "*.alpha.example A could not be read from ns1.alpha.example." ] ||
    fail "the failed wildcard read is not NOT MEASURED, whole: $(row_detail alpha.example wildcard.a)\n$output"
}

# AT-2.2
@test "CONTROL: declaring wildcards leaves the apex reads exactly as they were (0143)" {
  # A wildcard answers only for names that do not exist, and the apex always
  # does. Every read not at the wildcard is the read it always was.
  mkprofile_wild "$WILD_NONE"
  clean_zone
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_success
  local want
  want="$(printf '%s\n' 'alpha.example MX ns1.alpha.example.' 'alpha.example TXT ns1.alpha.example.' '_dmarc.alpha.example TXT ns1.alpha.example.')"
  [ "$(grep -v '^\*\.' "$DIG_LOG")" = "$want" ] ||
    fail "the reads away from the wildcard changed:\n$(cat "$DIG_LOG")"
}

# AT-2.1
@test "a wildcard declared under defaults is inherited, and a domain's own none overrides it (0143)" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
  wildcard:
    txt: "v=spf1 -all"
domains:
  alpha:
    name: alpha.example
  beta:
    name: beta.example
    wildcard:
      txt: none
YAML
  local f
  for f in alpha.example beta.example; do
    zone "$f MX 300 1 smtp.google.com."
    zone "$f TXT 300 \"v=spf1 include:_spf.google.com ~all\""
  done
  # alpha's live wildcard DIFFERS from the defaults', so only an inherited
  # declaration can produce its row: a domain that declares nothing of its own
  # and inherits nothing is never read at all, and prints no row.
  zone '*.alpha.example TXT 300 "v=spf1 ?all"'
  zone '*.beta.example TXT 300 "v=spf1 -all"'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.txt)" = "wildcard TXT at *.alpha.example is v=spf1 ?all, profile declares v=spf1 -all" ] ||
    fail "alpha did not inherit the defaults' TXT, whole: $(row_detail alpha.example wildcard.txt)\n$output"
  [ "$(row_detail beta.example wildcard.txt)" = "declares NO wildcard TXT and *.beta.example carries v=spf1 -all" ] ||
    fail "beta's own none did not override the defaults', whole: $(row_detail beta.example wildcard.txt)\n$output"
}

@test "a dkim type that is not CNAME or TXT is refused by name when the profile is read, before any query (0161)" {
  # It took any value, and a lower-case cname matched no answer dig gives, so the
  # check read a HALF PAIR over a zone that held the record.
  local log="$DEVBIN_TEST_TMPDIR/dig.log"
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: acme1._domainkey
      type: cname
      value: acme1._domainkey.acme.example
  multi:
    spf_include: _spf.multi.example
    dkim:
      k1:
        name: k1._domainkey
        type: bogus
        value: k1._domainkey.multi.example
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
      - multi
YAML
  : >"$log"
  DIG_LOG="$log" check
  assert_failure
  assert_output_contains "senders.acme.dkim.type: \"cname\" is not a value it takes (CNAME, TXT)"
  assert_output_contains "senders.multi.dkim.k1.type: \"bogus\" is not a value it takes (CNAME, TXT)"
  [ ! -s "$log" ] || fail "a refused profile was queried: $(cat "$log")"
}

@test "POSITIVE CONTROL: dkim types CNAME and TXT each hold over a zone that carries them (0161)" {
  acme_profile CNAME
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example CNAME 300 acme1._domainkey.acme.example.'
  check
  assert_success
  refute_output_contains "HALF PAIR"
  refute_output_contains "is not a value it takes"
  acme_profile TXT acme1._domainkey "v=DKIM1; k=rsa; p=KEY"
  : >"$FIX"
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=KEY"'
  check
  assert_success
  refute_output_contains "HALF PAIR"
  refute_output_contains "is not a value it takes"
  refute_output_contains "does not carry the declared value"
  # And TXT in the labelled form, which is its own row.
  mksender_profile '      k1:
        name: k1._domainkey
        type: TXT
        value: "v=DKIM1; k=rsa; p=LKEY"'
  : >"$FIX"
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.mailersend.net ~all"'
  zone 'k1._domainkey.alpha.example TXT 300 "v=DKIM1; k=rsa; p=LKEY"'
  check
  assert_success
  refute_output_contains "HALF PAIR"
  refute_output_contains "is not a value it takes"
}

# --- a reply without AA is not the authority's answer (issue 0193) ----------
#
# Measured through a VPN tunnel that carried every port-53 query, to any
# address, and answered each one itself: every record read came back from the
# tunnel's cache, so each ttl read was the time left in that cache, and 37
# assertions drifted in one run. A cache whose values match the profile reads
# as held the same way. So a record is asked for without recursion, and is
# measured only when the reply carries AA. The fake serves `qr aa` unless
# !FLAGS gives other flags, and a question put to TEST-NET-2 gets no reply
# unless !INTERCEPT says something on the path answers port 53 itself.

# row_is <facet> <detail> -- alpha.example's row under <facet> is <detail>,
# whole.
row_is() {
  [ "$(row_detail alpha.example "$1")" = "$2" ] ||
    fail "the $1 row is not, whole:\n  want: $2\n  got:  $(row_detail alpha.example "$1")\n$output"
}

# the_cause -- the report's Cause: line, whole, or nothing.
the_cause() { printf '%s\n' "$output" | awk '/^Cause: /'; }

CAUSE_REFUSED="Cause: 198.51.100.1, an address in TEST-NET-2 (RFC 5737) where no DNS server is, answered REFUSED: something on this machine's network path answers port 53 itself, as a VPN tunnel can, so the replies without AA in this run most likely came from it rather than from the domains' own nameservers"

@test "a record read answered without AA is COULD NOT MEASURE, saying what came back: a cache's ttl is never drift (0193)" {
  # The reported run: the cache held 30 seconds of a 300-second record, and
  # that read as drift.
  mkprofile
  zone 'alpha.example MX 30 1 smtp.google.com.'
  zone '!FLAGS alpha.example MX qr ra'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@t.example"'
  check
  assert_exit_code 1
  assert_output_contains "2 assertion(s) held, 0 drift, 1 NOT MEASURED"
  row_is mx "MX could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
  refute_output_contains "ttl is 30"
}

@test "a record read answered without AA is not HELD when it matches the profile: a cache that agrees is still not the zone (0193)" {
  mkprofile; clean_zone
  zone '!FLAGS _dmarc.alpha.example TXT qr ra'
  check
  assert_exit_code 1
  assert_output_contains "2 assertion(s) held, 0 drift, 1 NOT MEASURED"
  row_is dmarc "_dmarc TXT could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
}

@test "every record check reads says what came back without AA, and a REFUSED to a question without recursion stays NOT MEASURED (0193)" {
  # One fixture reaching each place check reads a record but DKIM, which the
  # referral arm reaches: MX, the SPF TXT, the _dmarc TXT, a wildcard RRset,
  # and the wildcard CNAME, asked only once a declared none has read empty.
  # The SPF read is refused, as the reported tunnel refused every question
  # asked without recursion.
  mkprofile_wild '      a: none
      txt: none'
  clean_zone
  zone '!FLAGS alpha.example MX qr ra'
  zone '!STATUS alpha.example TXT REFUSED'
  zone '!FLAGS alpha.example TXT qr ra'
  zone '!FLAGS _dmarc.alpha.example TXT qr ra'
  zone '!FLAGS *.alpha.example TXT qr ra'
  zone '!FLAGS *.alpha.example CNAME qr ra'
  check
  assert_exit_code 1
  assert_output_contains "1 assertion(s) held, 0 drift, 5 NOT MEASURED"
  row_is mx "MX could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
  row_is spf "TXT could not be read from ns1.alpha.example. -- answered without AA: REFUSED, flags qr ra"
  row_is dmarc "_dmarc TXT could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
  row_is wildcard.txt "*.alpha.example TXT could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
  row_is wildcard "*.alpha.example CNAME could not be read from ns1.alpha.example. -- answered without AA: NOERROR, flags qr ra"
}

@test "a referral is NOT MEASURED, never a measured absence: a DKIM name delegated away from the domain is no HALF PAIR (0193)" {
  # A referral names other nameservers for a name the server asked does not
  # hold, so it carries no AA, and it came back NOERROR with no record: an
  # absence, and so a HALF PAIR. devbin reads each name from the domain's own
  # nameserver and does not follow a delegation, so the read says what came
  # back instead.
  acme_profile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com include:_spf.acme.example ~all"'
  zone '!FLAGS acme1._domainkey.alpha.example CNAME qr'
  check
  assert_exit_code 1
  row_is dkim:acme "acme1._domainkey.alpha.example could not be read -- answered without AA: NOERROR, flags qr"
  refute_output_contains "HALF PAIR"
}

@test "a run that meets a reply without AA asks once where no DNS server is, and names the cause once, whole, when something answers there (0193)" {
  # The reported tunnel answered every question, to any address, and refused
  # one asked without recursion: the probe is refused too, and a refusal from
  # an address where no DNS server is proves something on the path answered.
  mkprofile; clean_zone
  zone '!STATUS alpha.example MX REFUSED'
  zone '!FLAGS alpha.example MX qr ra'
  zone '!STATUS alpha.example TXT REFUSED'
  zone '!FLAGS alpha.example TXT qr ra'
  zone '!INTERCEPT REFUSED'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_exit_code 1
  [ "$(the_cause)" = "$CAUSE_REFUSED" ] ||
    fail "the cause is not named once, whole:\n  want: $CAUSE_REFUSED\n  got:  $(the_cause)\n$output"
  [ "$(probes_sent)" -eq 1 ] ||
    fail "the probe was not asked exactly once, for two replies without AA:\n$(cat "$DIG_LOG")"
}

@test "a reply without AA with nothing answering where no DNS server is names no cause: silence there proves nothing (0193)" {
  mkprofile; clean_zone
  zone '!FLAGS alpha.example MX qr ra'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  [ "$(probes_sent)" -eq 1 ] ||
    fail "the probe was not asked exactly once:\n$(cat "$DIG_LOG")"
  [ -z "$(the_cause)" ] || fail "a cause was named on silence: $(the_cause)"
  assert_exit_code 1
}

@test "a probe dig could not ask is said in place of a cause, never taken for silence (0193)" {
  # dig read every record and could not ask the probe's question: the line
  # says so in dig's own words, where silence would have said nothing.
  mkprofile; clean_zone
  zone '!FLAGS alpha.example MX qr ra'
  zone '!INTERCEPT noreply:10'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  local want="Cause: unknown: devbin could not ask 198.51.100.1, an address in TEST-NET-2 (RFC 5737) where no DNS server is, whether something on this machine's network path answers port 53 itself (dig exit 10: dig: the fixture step noreply:10)"
  [ "$(the_cause)" = "$want" ] ||
    fail "the probe dig could not ask is not said, whole:\n  want: $want\n  got:  $(the_cause)\n$output"
  [ "$(probes_sent)" -eq 1 ] ||
    fail "the probe was not asked exactly once:\n$(cat "$DIG_LOG")"
  assert_exit_code 1
}

@test "a run whose every reply carries AA asks nothing where no DNS server is, so it pays nothing for the probe (0193)" {
  # Green on main by design: it holds the probe to runs that meet a reply
  # without AA, so a run whose every reply carries AA pays nothing for it.
  mkprofile; clean_zone
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_success
  [ "$(probes_sent)" -eq 0 ] ||
    fail "a run with every reply authoritative asked the probe:\n$(cat "$DIG_LOG")"
}

# --- a record published as a CNAME to a name outside the zone (issue 0196) ---
#
# Asked for a type at a name that is a CNAME out of its zone, the domain's own
# nameserver answers with the CNAME alone, AA set. Rows of the type asked were
# all the reader kept, so that read as a measured absence: "NO _dmarc record",
# or a HALF PAIR. devbin follows no CNAME, so such a read is NOT MEASURED, and
# says so naming the asked name and the target.

CNAME_DMARC="_dmarc TXT could not be read from ns1.alpha.example. -- answered with a CNAME: _dmarc.alpha.example is a CNAME to alpha.dmarc.provider.example., and no TXT record came with it -- devbin follows no CNAME, so it was not measured"

@test "a _dmarc published as a CNAME to a name outside the zone is NOT MEASURED, naming the target, never NO _dmarc record, and asks no probe (0196)" {
  mkprofile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example CNAME 300 alpha.dmarc.provider.example.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  check
  assert_exit_code 1
  refute_output_contains "NO _dmarc record"
  [ "$(row_detail alpha.example dmarc)" = "$CNAME_DMARC" ] ||
    fail "the CNAME answer is not NOT MEASURED naming its target, whole:\n  want: $CNAME_DMARC\n  got:  $(row_detail alpha.example dmarc)\n$output"
  # A CNAME answer is no reply without AA: it sends no probe and names no cause.
  [ "$(probes_sent)" -eq 0 ] || fail "a CNAME answer asked where no DNS server is:\n$(cat "$DIG_LOG")"
  refute_output_contains "Cause:"
}

@test "a DKIM selector declared TXT and published as a CNAME is NOT MEASURED, never a HALF PAIR (0196)" {
  cat >"$PROF" <<'YAML'
version: 1
name: t
defaults:
  mail: google
  ttl: 300
senders:
  acme:
    spf_include: _spf.acme.example
    dkim:
      name: acme1._domainkey
      type: TXT
      value: v=DKIM1; k=rsa; p=AAAA
domains:
  alpha:
    name: alpha.example
    senders:
      - acme
YAML
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.acme.example ~all"'
  zone 'acme1._domainkey.alpha.example CNAME 300 acme1._domainkey.acme.example.'
  check
  assert_exit_code 1
  refute_output_contains "HALF PAIR"
  local want="acme1._domainkey.alpha.example could not be read -- answered with a CNAME: acme1._domainkey.alpha.example is a CNAME to acme1._domainkey.acme.example., and no TXT record came with it -- devbin follows no CNAME, so it was not measured"
  [ "$(row_detail alpha.example dkim:acme)" = "$want" ] ||
    fail "the CNAME answer is not NOT MEASURED naming its target, whole:\n  want: $want\n  got:  $(row_detail alpha.example dkim:acme)\n$output"
}

@test "a _dmarc published as a CNAME inside the zone, answered with its target's record, reads as any record does (0196)" {
  # The server holds the target, so its answer carries the target's TXT beside
  # the CNAME; the fake lists it at the asked name, which is all a parser reads.
  mkprofile
  zone 'alpha.example MX 300 1 smtp.google.com.'
  zone 'alpha.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.alpha.example CNAME 300 dmarc.alpha.example.'
  zone '_dmarc.alpha.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@t.example"'
  check
  assert_success
  assert_output_contains "0 drift, 0 NOT MEASURED"
}

@test "a wildcard declaring a value whose owner is a CNAME out of the zone is drift, carrying NO record of that type, as before (0196)" {
  # What the profile declares is the zone's own RRset at *.<fqdn>: a CNAME there
  # holds no A, so the declared address is not there, measured.
  mkprofile_wild '      a: 192.0.2.7'
  clean_zone
  zone '*.alpha.example CNAME 300 elsewhere.example.'
  check
  assert_exit_code 1
  [ "$(row_detail alpha.example wildcard.a)" = "declares wildcard A 192.0.2.7 and *.alpha.example carries NO A record" ] ||
    fail "the declared wildcard value behind a CNAME is not drift, whole: $(row_detail alpha.example wildcard.a)\n$output"
}
