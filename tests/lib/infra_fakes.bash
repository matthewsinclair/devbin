#!/usr/bin/env bash
# infra_fakes.bash -- the fake `dig` and `sleep` the infra suites put on PATH,
# and the `zone` fixture they answer from.
#
# ONE HOME FOR THEM, loaded by infra-check.bats and infra-init.bats. Each suite
# carried its own copy of the fake dig until issue 0142 had to make one
# 30-line change to both, and two copies of a stub for an external tool's
# output are two different `dig`s the moment one is edited without the other:
# the suites would then hold two readers to two different worlds.
#
# The caller's setup() sets BIN (a directory it puts first on PATH) and FIX
# (the fixture file, empty to start), then calls mkdig and mksleep.

# mkdig -- a STRICT dig that answers from $DIG_FIXTURE instead of the world.
#
# STRICT BECAUSE A PERMISSIVE FAKE PASSES A BROKEN READER. It used to discard
# every `+` option but +short, and with `+answer` removed from lib/infra.dns
# every arm stayed green while a real dig would have returned the header
# alone -- every domain unmeasured in production (issue 0142 v2). So it
# accepts EXACTLY the argv lib/infra.dns sends, and anything else writes what
# it got to stderr and exits 64, a code no real dig uses:
#
#   +noall +comments +answer +time=N +tries=N <fqdn> NS          the authority
#       read: the machine's resolver, so no @server, and recursion wanted
#   +noall +comments +answer +time=N +tries=N +norecurse @<ns> <name> <T>
#       a record read, T one of MX TXT CNAME A AAAA, the types infra reads
#       (A and AAAA since issue 0143, for a zone's wildcard records), asked
#       without recursion since issue 0193; the interception probe is one
#
# and LEGACY forms, accepted ONLY when DIG_LEGACY=1, which nothing in the
# suite sets:
#
#   +short +time=N +tries=N NS <fqdn>                            the authority
#       read before 0142
#   +noall +comments +answer +time=N +tries=N @<ns> <name> <T>   a record read
#       before 0193, which asked with recursion
#
# A red-first run against an earlier reader exports it, so the arms fail there
# for their own reason, and a reader regressing to either form fails here
# with 64.
#
# A RECORD READ ANSWERS WITH THE NAME'S CNAME ROWS AS WELL AS ITS ROWS OF THE
# TYPE ASKED, as an authoritative server does (issue 0196): asked for a TXT at a
# name that is a CNAME, it answers with the CNAME row, and with the target's
# rows only when the target is in its own zone. A fixture serves that in-zone
# case by listing the target's rows at the asked name. That is all today's
# parser reads, since it matches rows by type and never by owner, and it is
# this fake's one blind spot: a real server lists the target's rows under the
# target's own name, so a reader that came to keep only rows owned by the
# asked name would drop them in the world while every arm here stayed green. A
# CNAME with no row of the type asked is the out-of-zone answer.
#
# EVERY REPLY CARRIES THE FLAGS LINE dig prints after its status line (issue
# 0193): `qr rd ra` from the machine's resolver, and `qr aa`, an authoritative
# answer's, from a record read unless !FLAGS gives others.
#
# An unset or empty DIG_FIXTURE, or a fixture file that is not there, exits 65
# rather than answering: it used to answer every NS lookup cleanly without one.
# A step !NSSEQ does not know, or a `!` directive the list below does not
# have, exits 66, so a typo in a fixture is not served as a status nobody
# meant.
#
# Every call is logged whole to DIG_ARGV_LOG, once its shape has been read, so
# an arm can assert the budget the knobs set is the budget dig was given.
#
# Fixture lines, one per line of $FIX:
#   <name> <TYPE> <ttl> <rdata...>    a record. An NS lookup answers the NS and
#                                     CNAME rows of its name, and when there
#                                     are none, `ns1.<name>.`. (A real alias
#                                     answer lists the CNAME and then the
#                                     TARGET's NS rows; the fake keeps both at
#                                     one name, which is all a parser sees.)
#   !ERROR <name> <TYPE>              that record read gets no reply (exit 9)
#   !STATUS <name> <TYPE> <STATUS>    that record read gets a reply with header
#                                     STATUS and no rows, at exit 0, as a real
#                                     SERVFAIL or REFUSED does
#   !NOAUTH <fqdn> [STATUS]           every NS lookup for <fqdn> gets a reply
#                                     with no NS record, under STATUS (NOERROR
#                                     when none is given)
#   !NSSEQ <fqdn> <step>...           each NS lookup for <fqdn> takes the next
#                                     step, and the last step repeats. A step
#                                     is a STATUS (a reply under it with no NS
#                                     record: SERVFAIL, NXDOMAIN, REFUSED,
#                                     NOERROR), `bare` (a reply with no header
#                                     at all), `noreply` (exit 9, as a dig that
#                                     heard nothing), `noreply:<n>` (exit <n>
#                                     with a line on stderr, as a dig that could
#                                     not run the query) or `fill` (the answer)
#   !FLAGS <name> <TYPE> <flag>...    that record read's reply carries these
#                                     flags in place of `qr aa`, with the
#                                     status !STATUS gives it or NOERROR and
#                                     the records; leaving out aa is how an arm
#                                     serves a reply WITHOUT AA (issue 0193)
#   !INTERCEPT [STATUS]               something on the path answers port 53
#                                     itself: a read addressed to TEST-NET-2
#                                     (198.51.100.0/24, RFC 5737), where no DNS
#                                     server is, gets a reply under STATUS
#                                     (NOERROR when none is given), flags qr
#                                     ra and no record, where without it, as
#                                     in the world, it gets none (exit 9).
#                                     `noreply:<n>` in place of STATUS exits
#                                     <n> with a line on stderr, as a dig that
#                                     could not run the query
#
# !NSSEQ counts lookups in a file beside the fixture, `$FIX.ns.<fqdn>`, so an
# arm that runs a command twice must call zone_rewind between the runs.
#
# Every NS lookup is logged to DIG_NS_LOG as `<fqdn> <server>`, `-` for none,
# once its flags have been read and BEFORE a server on it is refused, so an arm
# can assert that the authority read went to the machine's resolver rather
# than trusting that it did. Every record read
# is logged to DIG_LOG as `<name> <TYPE> <server>`, so an arm can assert that
# it was authoritative.
mkdig() {
  cat >"$BIN/dig" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
F="${DIG_FIXTURE:-}"
[ -n "$F" ] || { printf 'fake dig: DIG_FIXTURE is not set\n' >&2; exit 65; }
[ -f "$F" ] || { printf 'fake dig: no fixture at %s\n' "$F" >&2; exit 65; }
# A directive the fake does not know is a typo in a fixture, never a record:
# served, it would be a question answered as nobody meant (issue 0143).
bad="$(awk '$1 ~ /^!/ && $1 !~ /^!(ERROR|STATUS|NOAUTH|NSSEQ|FLAGS|INTERCEPT)$/ { print $1; exit }' "$F")"
[ -z "$bad" ] || { printf 'fake dig: the fixture has no directive %s\n' "$bad" >&2; exit 66; }

refuse() {
  printf 'fake dig: not an argv lib/infra.dns sends: %s\n' "$*" >&2
  exit 64
}
budget() { [[ "$1" =~ ^\+time=[0-9]+$ ]] && [[ "$2" =~ ^\+tries=[0-9]+$ ]]; }

short=0; server=""
case "$#:${1:-}" in
  5:+short)
    { [ "${DIG_LEGACY:-}" = 1 ] && budget "$2" "$3" && [ "$4" = NS ]; } || refuse "$@"
    short=1; name="$5"; type=NS ;;
  7:+noall | 8:+noall | 9:+noall)
    { [ "$2" = +comments ] && [ "$3" = +answer ] && budget "$4" "$5"; } || refuse "$@"
    case "$#" in
      7) name="$6"; type="$7" ;;
      8)
        [ "${DIG_LEGACY:-}" = 1 ] || refuse "$@"
        case "$6" in @?*) server="${6#@}" ;; *) refuse "$@" ;; esac
        name="$7"; type="$8" ;;
      *)
        [ "$6" = +norecurse ] || refuse "$@"
        case "$7" in @?*) server="${7#@}" ;; *) refuse "$@" ;; esac
        name="$8"; type="$9" ;;
    esac ;;
  *) refuse "$@" ;;
esac
case "$name" in '' | [+@]*) refuse "$@" ;; esac
printf '%s\n' "$*" >>"${DIG_ARGV_LOG:-/dev/null}"

# rows <name> <types-regex> -- the fixture's records, as dig's answer section.
rows() {
  awk -v n="$1" -v t="$2" '$1 == n && $2 ~ ("^(" t ")$") {
    typ = $2; ttl = $3; $1 = ""; $2 = ""; $3 = ""; sub(/^[ ]+/, "")
    printf "%s.\t\t%s\tIN\t%s\t%s\n", n, ttl, typ, $0 }' "$F"
}
# header <status> <flags> [answers] -- a reply's header as `dig +comments`
# prints it: the status line, then the flags line.
header() {
  printf ';; ->>HEADER<<- opcode: QUERY, status: %s, id: 1\n' "$1"
  printf ';; flags: %s; QUERY: 1, ANSWER: %s, AUTHORITY: 0, ADDITIONAL: 0\n' "$2" "${3:-0}"
}
# count <rows> -- how many records an answer holds, for the flags line.
count() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'; }

if [ "$type" = NS ]; then
  printf '%s %s\n' "$name" "${server:--}" >>"${DIG_NS_LOG:-/dev/null}"
  [ -z "$server" ] || refuse "$@"
  # How many NS lookups for this name came before this one.
  k=0
  [ ! -f "$F.ns.$name" ] || k="$(cat "$F.ns.$name")"
  echo $((k + 1)) >"$F.ns.$name"
  step="$(awk -v f="$name" -v k="$k" '
    $1 == "!NOAUTH" && $2 == f { print ($3 == "" ? "NOERROR" : $3); exit }
    $1 == "!NSSEQ" && $2 == f { i = k + 3; if (i > NF) i = NF; print $i; exit }' "$F")"
  step="${step:-fill}"
  case "$step" in
    noreply:*) case "${step#noreply:}" in '' | *[!0-9]*) step="?$step" ;; esac ;;
  esac
  case "$step" in
    fill) ;;
    bare) exit 0 ;;
    noreply)
      echo ";; connection timed out; no servers could be reached"
      exit 9 ;;
    noreply:*)
      printf 'dig: the fixture step %s\n' "$step" >&2
      exit "${step#noreply:}" ;;
    SERVFAIL | NXDOMAIN | REFUSED | NOERROR)
      [ "$short" -eq 1 ] || header "$step" "qr rd ra"
      exit 0 ;;
    *)
      printf 'fake dig: !NSSEQ has no step %s\n' "$step" >&2
      exit 66 ;;
  esac
  answer="$(rows "$name" 'NS|CNAME')"
  [ -n "$answer" ] || answer="$(printf '%s.\t\t300\tIN\tNS\tns1.%s.' "$name" "$name")"
  if [ "$short" -eq 1 ]; then
    printf '%s\n' "$answer" | awk -F'\t' '{ print $NF }'
  else
    header NOERROR "qr rd ra" "$(count "$answer")"
    printf '%s\n' "$answer"
  fi
  exit 0
fi

case "$type" in MX | TXT | CNAME | A | AAAA) ;; *) refuse "$@" ;; esac
[ -n "$server" ] || refuse "$@"
printf '%s %s %s\n' "$name" "$type" "$server" >>"${DIG_LOG:-/dev/null}"
# No DNS server is in TEST-NET-2, so a question put there gets no reply,
# unless the fixture says something on the path answers port 53 itself.
case "$server" in
  198.51.100.*)
    st="$(awk '$1 == "!INTERCEPT" { print ($2 == "" ? "NOERROR" : $2); exit }' "$F")"
    case "$st" in
      '')
        echo ";; connection timed out; no servers could be reached"
        exit 9 ;;
      noreply:*)
        case "${st#noreply:}" in
          '' | *[!0-9]*)
            printf 'fake dig: !INTERCEPT has no step %s\n' "$st" >&2
            exit 66 ;;
        esac
        printf 'dig: the fixture step %s\n' "$st" >&2
        exit "${st#noreply:}" ;;
    esac
    header "$st" "qr ra"
    exit 0 ;;
esac
if awk -v n="$name" -v t="$type" '$1 == "!ERROR" && $2 == n && $3 == t { f = 1 } END { exit !f }' "$F"; then
  echo ";; connection timed out; no servers could be reached"
  exit 9
fi
fl="$(awk -v n="$name" -v t="$type" '$1 == "!FLAGS" && $2 == n && $3 == t {
  $1 = ""; $2 = ""; $3 = ""; sub(/^ +/, ""); print; exit }' "$F")"
fl="${fl:-qr aa}"
st="$(awk -v n="$name" -v t="$type" '$1 == "!STATUS" && $2 == n && $3 == t { print $4; exit }' "$F")"
if [ -n "$st" ]; then
  header "$st" "$fl"
  exit 0
fi
answer="$(rows "$name" "CNAME|$type")"
header NOERROR "$fl" "$(count "$answer")"
[ -z "$answer" ] || printf '%s\n' "$answer"
exit 0
FAKE
  chmod +x "$BIN/dig"
}

# mksleep -- a sleep that records the pause it was asked for and returns at
# once, so the authority read's retry costs no arm any time, whatever the
# pause is set to, and an arm can assert the pause rather than time it. Like
# the real one it refuses, at 1, anything but one number of seconds, so a
# pause the reader could not have slept is not recorded as slept.
mksleep() {
  cat >"$BIN/sleep" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] || {
  printf 'usage: sleep seconds\n' >&2
  exit 1
}
printf '%s\n' "$1" >>"${SLEEP_LOG:-/dev/null}"
FAKE
  chmod +x "$BIN/sleep"
}

# zone <line> -- append one fixture line.
zone() { printf '%s\n' "$*" >>"$FIX"; }

# probes_sent -- how many questions DIG_LOG holds put to 198.51.100.1, the
# interception probe's address (issue 0193). It lives beside the log it reads,
# so both suites read one layout.
probes_sent() { awk '$3 == "198.51.100.1" { n++ } END { print n + 0 }' "$DIG_LOG"; }

# zone_rewind -- forget every NS lookup counted so far, so the next run of a
# command meets !NSSEQ from its first step, as the first run did.
zone_rewind() { rm -f "$FIX".ns.*; }
