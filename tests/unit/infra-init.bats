#!/usr/bin/env bats
# infra-init.bats -- `infra init`, adopting an existing estate (ST0003 WP-03).
#
# WHAT IS UNDER TEST IS WHAT INIT REFUSES TO WRITE. Generating a profile is
# easy: transcribe the live records. That profile is also the defect this
# thread exists to catch -- it makes the estate's drift the target, and `check`
# then reports that estate green forever. So nearly every arm here asserts an
# ABSENCE in the generated target and a PRESENCE in `unreviewed:`, and the
# positive controls exist to prove init is a gate rather than a wall.
#
# THE DISCRIMINATING ARMS ARE THE N=2 / N=3 PAIR. The same agreeing values
# propose a target at three domains and propose nothing at two, because a
# majority of two is not a majority of anything. An init that ignored the
# provenance kind would pass every other arm in this file.
#
# The same fake `dig` as infra-check.bats, from tests/lib/infra_fakes.bash, for
# the same reason: the real one makes an arm depend on the internet, on
# somebody's estate and on the day.

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
  INIT="$DEVBIN_HOME/lib/cmd/infra.d/init"
  INFRA="$DEVBIN_HOME/lib/cmd/infra"
  GEN="$DEVBIN_TEST_TMPDIR/generated.yaml"
}
teardown() { devbin_teardown; }

# mail_domain <fqdn> <ttl> <policy|-> [rua] -- a Google-shaped mail domain. A
# policy of `-` publishes no _dmarc record at all.
mail_domain() {
  local f="$1" ttl="$2" p="$3" rua="${4:-dmarc@est.example}"
  zone "$f MX $ttl 1 smtp.google.com."
  zone "$f TXT $ttl \"v=spf1 include:_spf.google.com ~all\""
  [ "$p" = - ] || zone "_dmarc.$f TXT $ttl \"v=DMARC1; p=$p; rua=mailto:$rua\""
}

# init <args...> -- stdout is the profile, captured to $GEN as well.
#
# TWO RUNS OF ONE WORLD. The first is the one `run` observes, and the one whose
# lookups and pauses reach DIG_NS_LOG, DIG_LOG and SLEEP_LOG; the second exists
# only to capture stdout alone into $GEN, so its logs go nowhere. Between them
# the fixture's lookup counters are rewound: a stateful line such as !NSSEQ
# would otherwise meet the second run at the step the first run left it on,
# and $GEN would be the profile of a different estate from the one asserted on.
init() {
  DIG_FIXTURE="$FIX" DIG_LOG="${DIG_LOG:-/dev/null}" DIG_NS_LOG="${DIG_NS_LOG:-/dev/null}" \
    SLEEP_LOG="${SLEEP_LOG:-/dev/null}" PATH="$BIN:$PATH" run "$INIT" "$@"
  zone_rewind
  DIG_FIXTURE="$FIX" DIG_LOG=/dev/null DIG_NS_LOG=/dev/null SLEEP_LOG=/dev/null PATH="$BIN:$PATH" \
    "$INIT" "$@" >"$GEN" 2>/dev/null || true
}

# The generated profile's own `unreviewed:` block and nothing else, so an arm
# asserting a key is unreviewed cannot pass on the same words elsewhere.
unreviewed_block() { awk '/^unreviewed:/ {on=1; next} /^[^ ]/ {on=0} on' "$GEN"; }
# The target half: everything BEFORE `unreviewed:`.
target_block() { awk '/^unreviewed:/ {exit} {print}' "$GEN"; }

# --- AC-3.1: adopt WITHOUT laundering drift into the target -----------------

# AT-3.1
@test "an outlier is NOT written as its domain's target: majority to defaults, the outlier to unreviewed" {
  mail_domain a.example 300 none
  mail_domain b.example 300 none
  mail_domain c.example 900 none
  init a.example b.example c.example
  assert_success
  run target_block
  assert_output_contains "ttl: 300"
  refute_output_contains "900"
  run unreviewed_block
  assert_output_contains "c_ttl:"
  assert_output_contains "900"
  refute_output_contains "a_ttl:"
}

# AT-3.1
@test "the generated profile LOADS and VALIDATES, and check REFUSES it until reviewed" {
  mail_domain a.example 300 none
  mail_domain b.example 300 none
  mail_domain c.example 900 none
  init a.example b.example c.example
  assert_success
  DIG_FIXTURE="$FIX" PATH="$BIN:$PATH" run "$INFRA" show --profile "$GEN"
  assert_success
  assert_output_contains "c.example"
  DIG_FIXTURE="$FIX" PATH="$BIN:$PATH" run "$INFRA" check --profile "$GEN"
  assert_failure
  assert_output_contains "Refusing to check"
}

# AT-3.1
@test "an estate UNIFORMLY missing DMARC is not blessed by its own agreement: the standard proposes one" {
  mail_domain a.example 300 -
  mail_domain b.example 300 -
  mail_domain c.example 300 -
  init a.example b.example c.example
  assert_success
  run target_block
  assert_output_contains "policy: none"
  run unreviewed_block
  assert_output_contains "a_dmarc:"
  assert_output_contains "RFC 7489"
}

# --- AC-3.2: the standard leads at any N, majority only above N=2 ------------

# AT-3.2
@test "N=1: the standard still proposes -- a mail domain with no DMARC gets policy none" {
  mail_domain solo.example 300 -
  init solo.example
  assert_success
  run target_block
  assert_output_contains "policy: none"
  run unreviewed_block
  assert_output_contains "solo_dmarc:"
}

# AT-3.2
@test "N=2: two AGREEING domains propose NO estate value -- a majority of two is not one" {
  mail_domain a.example 300 quarantine
  mail_domain b.example 300 quarantine
  init a.example b.example
  assert_success
  run target_block
  refute_output_contains "ttl:"
  refute_output_contains "policy:"
  refute_output_contains "rua:"
  run unreviewed_block
  assert_output_contains "ttl:"
  assert_output_contains "above N=2"
}

# AT-3.2
@test "N=3: the SAME agreeing values DO propose -- the control for the N=2 arm" {
  mail_domain a.example 300 quarantine
  mail_domain b.example 300 quarantine
  mail_domain c.example 300 quarantine
  init a.example b.example c.example
  assert_success
  run target_block
  assert_output_contains "ttl: 300"
  assert_output_contains "policy: quarantine"
  assert_output_contains "rua: dmarc@est.example"
}

# AT-3.2
@test "an UNMEASURED domain abstains and still counts in N, so it cannot manufacture a majority" {
  mail_domain a.example 300 none
  mail_domain b.example 900 none
  zone '!NOAUTH c.example'
  mail_domain d.example 300 none
  # 2 of 4 say 300. Excluding c from N would make that 2 of 3, a majority.
  init a.example b.example c.example d.example
  assert_exit_code 1
  assert_output_contains "could not be measured"
  run target_block
  refute_output_contains "ttl:"
  run unreviewed_block
  assert_output_contains '  c: "could not be measured'
}

# --- the authority read, shared with check (issue 0142) ----------------------

@test "an NS answer empty once and then filled is MEASURED by init too, and nothing is recorded as unmeasured (0142)" {
  # The steps after the fill are never reached by one run of init. They are
  # what the helper's second run would meet if the counters were not rewound
  # between the two, and $GEN would then be the profile of an unmeasured
  # domain -- which the last assertion here reads.
  mail_domain a.example 300 none
  zone '!NSSEQ a.example NOERROR fill NOERROR NOERROR NOERROR'
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  init a.example
  assert_success
  refute_output_contains "could not be measured"
  # Its records were read: the live policy is what N=1 leaves unreviewed.
  assert_output_contains "live p=none"
  [ "$(cat "$DIG_NS_LOG")" = "$(printf 'a.example -\na.example -')" ] ||
    fail "the NS lookups were not exactly two, to the resolver, for a.example:\n$(cat "$DIG_NS_LOG")"
  # And the profile the helper's second run captured is of the same estate.
  run unreviewed_block
  assert_output_contains "live p=none"
  refute_output_contains "could not be measured"
}

@test "an NS answer empty on every attempt is recorded in unreviewed: in the sentence check prints, whole, and rc is 1 (0142)" {
  zone '!NOAUTH a.example'
  init a.example
  assert_exit_code 1
  # The rc is this domain's, not a refused profile's: the summary prints only
  # after the generated profile has loaded and validated.
  assert_output_contains "infra init: 1 read(s) could not be measured"
  refute_output_contains "no authoritative nameserver answered"
  # THE EXACT BYTES. check's arms compare after its report folds whitespace;
  # this one reads the profile as written, so it is the arm that holds them.
  local want="  a: \"could not be measured: no NS record for a.example came from the machine's resolver on 3 attempt(s) (NOERROR, NOERROR, NOERROR), so devbin asked no authoritative nameserver. Nothing about it was proposed, and it abstained from every majority\""
  [ "$(unreviewed_block | awk '/^  a: /')" = "$want" ] ||
    fail "the unreviewed entry is not the sentence, whole:\n  want: $want\n  got:  $(unreviewed_block | awk '/^  a: /')"
}

@test "a pause that is not a whole number is refused by init too, before any domain is asked about (0142)" {
  mail_domain a.example 300 none
  DIG_NS_LOG="$DEVBIN_TEST_TMPDIR/ns.log"
  : >"$DIG_NS_LOG"
  DEVBIN_INFRA_DNS_RETRY_PAUSE=1s init a.example
  assert_exit_code 1
  assert_output_contains "infra init: DEVBIN_INFRA_DNS_RETRY_PAUSE must be a whole number below 100000, got '1s'. Nothing was measured."
  assert_file_empty "$DIG_NS_LOG"
}

# --- AC-3.3: init READS the provenance kind ----------------------------------

# AT-3.3
@test "the kind reader: rfc proposes at any N, estate-inferred only above N=2, no source never" {
  run bash -c ". '$DEVBIN_HOME/lib/helpers'; . '$DEVBIN_HOME/lib/infra.init'
    for k in rfc:1 vendor-stated:1 estate-inferred:1 estate-inferred:2 estate-inferred:3 none:3; do
      if infra_init_may_propose \"\${k%%:*}\" \"\${k##*:}\"; then echo \"\$k yes\"; else echo \"\$k no\"; fi
    done"
  assert_success
  assert_output_contains "rfc:1 yes"
  assert_output_contains "vendor-stated:1 yes"
  assert_output_contains "estate-inferred:1 no"
  assert_output_contains "estate-inferred:2 no"
  assert_output_contains "estate-inferred:3 yes"
  assert_output_contains "none:3 no"
}

# AT-3.3
@test "an UNKNOWN kind is refused, never treated as either answer" {
  run bash -c ". '$DEVBIN_HOME/lib/helpers'; . '$DEVBIN_HOME/lib/infra.init'
    infra_init_may_propose vendor-guessed 5"
  assert_exit_code 2
  assert_output_contains "vendor-guessed"
}

# --- AC-3.4: where nothing determines a value, declare NOTHING ---------------

# AT-3.4
@test "a three-way split proposes no ttl at all, and names every live value in unreviewed" {
  mail_domain a.example 300 none
  mail_domain b.example 600 none
  mail_domain c.example 900 none
  init a.example b.example c.example
  assert_success
  run target_block
  refute_output_contains "ttl:"
  run unreviewed_block
  assert_output_contains "more than half"
  assert_output_contains "300"
  assert_output_contains "600"
  assert_output_contains "900"
}

# AT-3.4
@test "N=1 with a live policy declares no policy, and unreviewed carries the live one" {
  mail_domain solo.example 300 reject
  init solo.example
  assert_success
  run target_block
  refute_output_contains "policy:"
  run unreviewed_block
  assert_output_contains "solo_dmarc_policy:"
  assert_output_contains "p=reject"
}

# AT-3.4
@test "a domain with no MX and no DMARC gets nothing proposed, and is told dmarc: none must be spelled" {
  mail_domain a.example 300 none
  zone 'parked.example TXT 300 "v=spf1 -all"'
  init a.example parked.example
  assert_success
  run target_block
  refute_output_contains "dmarc: none"
  run unreviewed_block
  assert_output_contains "parked_dmarc:"
  assert_output_contains "dmarc: none"
}

# --- AC-3.5: nothing shipped that can go stale ------------------------------

# AT-3.5
@test "EVERY domain agreeing on MX and SPF still proposes no mail label and no sender" {
  zone 'a.example MX 300 1 smtp.google.com.'
  zone 'a.example TXT 300 "v=spf1 include:_spf.google.com include:_spf.mailersend.net ~all"'
  zone '_dmarc.a.example TXT 300 "v=DMARC1; p=none; rua=mailto:dmarc@est.example"'
  mail_domain b.example 300 none
  mail_domain c.example 300 none
  init a.example b.example c.example
  assert_success
  run target_block
  refute_output_contains "mail:"
  refute_output_contains "senders:"
  run unreviewed_block
  assert_output_contains "mail:"
  assert_output_contains "smtp.google.com"
  assert_output_contains "senders:"
  assert_output_contains "_spf.mailersend.net"
}

# --- the command's own refusals ----------------------------------------------

@test "no domains is an ERROR, never an empty profile" {
  init
  assert_failure
  assert_output_contains "no domains"
}

@test "a domain named twice is refused" {
  init a.example A.example
  assert_failure
  assert_output_contains "twice"
}

@test "two domains sharing a first label get distinct handles, and the profile still loads" {
  mail_domain twin.example 300 none
  mail_domain twin.test 300 none
  init twin.example twin.test
  assert_success
  DIG_FIXTURE="$FIX" PATH="$BIN:$PATH" run "$INFRA" show --profile "$GEN"
  assert_success
  assert_output_contains "twin.example"
  assert_output_contains "twin.test"
}

@test "a record that cannot be read abstains from that facet and rc is 1 (0126)" {
  mail_domain a.example 300 none
  zone '!ERROR a.example MX'
  init a.example
  assert_exit_code 1
  run unreviewed_block
  assert_output_contains "a_mx:"
}

# --- DMARC sp=, measured and never targeted (issue 0143) ---------------------
#
# sp= became a profile field in 0143, and init reads the record that carries
# it. "Every other live value goes under unreviewed:" would be false if init
# read a differing sp= and dropped it. No target is proposed: neither an RFC
# nor a vendor decides an estate's subdomain policy.

# AT-3.1
@test "a live sp= differing from its own p= goes to unreviewed, and no sp target is proposed (0143)" {
  zone 'a.example MX 300 1 smtp.google.com.'
  zone 'a.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.a.example TXT 300 "v=DMARC1; p=quarantine; sp=reject; rua=mailto:dmarc@est.example"'
  init a.example
  assert_success
  local want="  a_dmarc_sp: \"live sp=reject against its own p=quarantine; nothing proposed: a subdomain policy is this estate's decision. Declaring dmarc.sp is what makes check hold it\""
  [ "$(unreviewed_block | awk '/^  a_dmarc_sp: /')" = "$want" ] ||
    fail "the differing sp= is not recorded, whole:\n  want: $want\n  got:  $(unreviewed_block | awk '/^  a_dmarc_sp: /')"
  run target_block
  # The target block holds the domain's target -- one domain proposes no
  # policy, since a majority needs three -- so the absence below is read from
  # the block an sp target would be written in, not from an empty one.
  assert_output_contains "    name: a.example"
  refute_output_contains "sp:"
}

# AT-3.1
# AT-2.12
@test "CONTROL: an sp= equal to its p= adds no unreviewed entry (0143)" {
  zone 'a.example MX 300 1 smtp.google.com.'
  zone 'a.example TXT 300 "v=spf1 include:_spf.google.com ~all"'
  zone '_dmarc.a.example TXT 300 "v=DMARC1; p=reject; sp=reject; rua=mailto:dmarc@est.example"'
  init a.example
  assert_success
  run unreviewed_block
  refute_output_contains "_dmarc_sp"
}

# --- a reply without AA abstains (issue 0193) --------------------------------
#
# init reads through check's reader, so a record answered without AA is a read
# that failed here too: the domain abstains from that census and from the ttl
# vote, where a cache's values used to be proposed as the estate's target.

INTERCEPTION="  interception: \"198.51.100.1, an address in TEST-NET-2 (RFC 5737) where no DNS server is, answered REFUSED: something on this machine's network path answers port 53 itself, as a VPN tunnel can, so the replies without AA in this run most likely came from it rather than from the domains' own nameservers\""

@test "records answered without AA abstain and say what came back: an estate read through a cache proposes no ttl from it (0193)" {
  # Three domains read through a tunnel's cache, every record with 30 seconds
  # of 300 left: their majority proposed ttl 30 as the estate's target.
  local d
  for d in a b c; do
    mail_domain "$d.example" 30 none
    zone "!FLAGS $d.example MX qr ra"
    zone "!FLAGS $d.example TXT qr ra"
    zone "!FLAGS _dmarc.$d.example TXT qr ra"
  done
  init a.example b.example c.example
  [ -z "$(target_block | awk '/ttl:/')" ] ||
    fail "the cache's ttl was proposed as the target: $(target_block | awk '/ttl:/')"
  assert_exit_code 1
  local want='  a_mx: "MX could not be read (answered without AA: NOERROR, flags qr ra); this domain abstained from the MX census"'
  [ "$(unreviewed_block | awk '/^  a_mx: /')" = "$want" ] ||
    fail "the MX read without AA did not abstain, whole:\n  want: $want\n  got:  $(unreviewed_block | awk '/^  a_mx: /')"
}

@test "a _dmarc published as a CNAME to a name outside the zone abstains, says so under unreviewed:, and asks no probe (0196)" {
  mail_domain a.example 300 -
  zone '_dmarc.a.example CNAME 300 a.dmarc.provider.example.'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  init a.example
  assert_exit_code 1
  local want='  a_dmarc: "_dmarc could not be read (answered with a CNAME: _dmarc.a.example is a CNAME to a.dmarc.provider.example., and no TXT record came with it -- devbin follows no CNAME, so it was not measured); nothing about its DMARC was proposed"'
  [ "$(unreviewed_block | awk '/^  a_dmarc: /')" = "$want" ] ||
    fail "the CNAME answer did not abstain in check's words, whole:\n  want: $want\n  got:  $(unreviewed_block | awk '/^  a_dmarc: /')"
  [ "$(probes_sent)" -eq 0 ] || fail "a CNAME answer asked where no DNS server is:\n$(cat "$DIG_LOG")"
  [ -z "$(unreviewed_block | awk '/^  interception: /')" ] || fail "a CNAME answer named an interception cause"
}

@test "init records the cause under unreviewed:, in check's words, whole, and asks once (0193)" {
  mail_domain a.example 300 none
  zone '!FLAGS a.example MX qr ra'
  zone '!FLAGS a.example TXT qr ra'
  zone '!INTERCEPT REFUSED'
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  init a.example
  [ "$(unreviewed_block | awk '/^  interception: /')" = "$INTERCEPTION" ] ||
    fail "the cause is not recorded, whole:\n  want: $INTERCEPTION\n  got:  $(unreviewed_block | awk '/^  interception: /')"
  [ "$(probes_sent)" -eq 1 ] ||
    fail "the probe was not asked exactly once, for two replies without AA:\n$(cat "$DIG_LOG")"
  assert_exit_code 1
}

@test "an init whose every reply carries AA asks nothing where no DNS server is (0193)" {
  # Green on main by design: it holds the probe to runs that meet a reply
  # without AA.
  mail_domain a.example 300 none
  DIG_LOG="$DEVBIN_TEST_TMPDIR/dig.log"
  init a.example
  assert_success
  [ "$(probes_sent)" -eq 0 ] ||
    fail "a run with every reply authoritative asked the probe:\n$(cat "$DIG_LOG")"
}
