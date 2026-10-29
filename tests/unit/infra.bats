#!/usr/bin/env bats
#
# `devbin infra mail dmarc parse` -- DMARC aggregate reports to normalised rows.
#
# THE POINT OF THESE TESTS IS ONE FIELD, and it is worth saying why before the
# first assertion. A DMARC report does not tell you a message was forged. What
# separates a forgery from a legitimate message that was forwarded is the
# ABSENCE OF ANY DKIM AUTH RESULT -- DKIM signatures survive relay and SPF
# results do not, so an SPF softfail on its own is what ordinary mailing-list
# forwarding produces and discriminates nothing.
#
# Measured on six real reports: ten records, every authenticated one carrying
# `dkim=pass`, every forged one carrying NO `dkim` element at all, no middle
# case. SPF across the forged set read softfail four times and none once.
#
# So the parser's contract is that ABSENT and EMPTY stay distinguishable. That
# is fragile in exactly one way, and it is the reason these tests exist:
#
#   xmllint --xpath 'string(...//auth_results/dkim/domain)'
#
# returns the empty string for an ABSENT dkim element AND for a present-but-
# empty one. A parser written with string extraction collapses the two and
# destroys the only field that separates a forgery from a clean send, before any
# reporting logic ever sees it. `count()` is the discriminator: 0 versus 1.
#
# The contract therefore carries the distinction in the TYPE rather than in a
# sentinel value: `dkim_auth` is an ARRAY whose LENGTH is `count()`. Absent is
# `[]`; present-but-empty is `[{...}]` with empty strings inside. No sentinel
# string can be mistaken for data, and multi-signature messages are handled by
# the same shape rather than by a special case.
#
set -euo pipefail

load "../lib/test_helper"

FIXTURES="$BATS_TEST_DIRNAME/../fixtures/dmarc"

# THE TOOLS ARE GUARDED AT FILE LEVEL because the whole file drives the parser,
# and the parser refuses to start without them by design (there is deliberately
# no text-extraction fallback -- one would report every message as unsigned,
# which is what a forgery looks like).
#
# `require_command` SKIPS on a developer's machine and FAILS under CI, which is
# the half that matters here: these nine arms once went red on Ubuntu
# because the runner had no xmllint, and a plain skip would have turned that
# into a green run with nine arms silently gone from the population.
#
# Some arms (the missing-file and malformed-report refusals among them) do not
# strictly need xmllint and are skipped with the rest on a machine lacking it.
# That is deliberate: this file's subject is the parser, and one guard stating
# that beats a guard in every arm restating it.
setup() {
  devbin_setup
  require_command xmllint
  require_command jq
  PARSE="$DEVBIN_HOME/lib/cmd/infra.d/mail.d/dmarc"
}
teardown() { devbin_teardown; }

# --- the discriminator -------------------------------------------------------

# AT-5.2
@test "parse: an absent dkim auth result is an EMPTY ARRAY, never an empty string" {
  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success

  # Record 2 (198.51.100.23) carries spf softfail and NO dkim element.
  row=$(echo "$output" | jq -c 'select(.source_ip == "198.51.100.23")')
  [ -n "$row" ]

  # The array is empty ...
  [ "$(echo "$row" | jq '.dkim_auth | length')" -eq 0 ]
  # ... and it is an ARRAY, not a string, not null. A parser that emitted "" or
  # null here would pass a length check on some implementations and still have
  # thrown the distinction away.
  [ "$(echo "$row" | jq -r '.dkim_auth | type')" = "array" ]
}

# AT-5.2
@test "parse: a PRESENT dkim auth result is a populated array, so absent and present differ in LENGTH" {
  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success

  row=$(echo "$output" | jq -c 'select(.source_ip == "192.0.2.10")')
  [ "$(echo "$row" | jq '.dkim_auth | length')" -eq 1 ]
  [ "$(echo "$row" | jq -r '.dkim_auth[0].result')" = "pass" ]
  [ "$(echo "$row" | jq -r '.dkim_auth[0].selector')" = "google" ]
}

@test "parse: an ABSENT dkim selector is null, and report prints it as s=absent (0147)" {
  # report names an absent selector `absent` and an empty one `none`; that
  # holds only while parse keeps the two apart, so it is driven from the XML.
  local xml="$DEVBIN_TEST_TMPDIR/nosel.xml"
  grep -v '<selector>google</selector>' "$FIXTURES/google-shape.xml" >"$xml"
  run "$PARSE" parse "$xml"
  assert_success
  [ "$(echo "$output" | jq -c 'select(.source_ip == "192.0.2.10") | .dkim_auth[0].selector')" = null ] ||
    fail "an absent selector did not parse as null:\n$output"
  run bash -c '"$1" parse "$2" | "$1" report' _ "$PARSE" "$xml"
  assert_success
  grep -q '192\.0\.2\.10 .*dkim=pass d=[^ ]* s=absent ' <<<"$output" ||
    fail "report does not print the absent selector as absent:\n$output"
}

# AT-5.2
@test "parse: a present-but-EMPTY dkim element is length 1, NOT length 0" {
  # The control that makes the test above mean something. Without it, a parser
  # that emitted [] for every record would pass the absent case and be wrong.
  empty="$BATS_TEST_TMPDIR/empty-dkim.xml"
  cat >"$empty" <<'XML'
<?xml version="1.0" encoding="UTF-8" ?>
<feedback>
  <report_metadata><org_name>t</org_name><report_id>1</report_id>
    <date_range><begin>1</begin><end>2</end></date_range></report_metadata>
  <policy_published><domain>example.com</domain><p>none</p></policy_published>
  <record>
    <row><source_ip>192.0.2.1</source_ip><count>1</count>
      <policy_evaluated><disposition>none</disposition><dkim>fail</dkim><spf>fail</spf></policy_evaluated></row>
    <identifiers><header_from>example.com</header_from></identifiers>
    <auth_results><dkim><domain></domain><result></result></dkim></auth_results>
  </record>
</feedback>
XML

  run "$PARSE" parse "$empty"
  assert_success
  [ "$(echo "$output" | jq '.dkim_auth | length')" -eq 1 ]
  [ "$(echo "$output" | jq -r '.dkim_auth[0].result')" = "" ]
}

# --- disposition is not auth_results -----------------------------------------

@test "parse: disposition and the auth results are carried SEPARATELY" {
  # Under p=none every record reads disposition=none, forged ones included. A
  # summary keyed on disposition reports all-clear on an estate under active
  # spoofing, so both must survive parsing as distinct fields.
  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success

  [ "$(echo "$output" | jq -s '[.[] | select(.disposition == "none")] | length')" -eq 3 ]
  [ "$(echo "$output" | jq -s '[.[] | select(.dkim_auth | length == 0)] | length')" -eq 2 ]
}

# --- both schema shapes ------------------------------------------------------

@test "parse: the Mail.Ru shape parses -- single line, no trailing newline" {
  run "$PARSE" parse "$FIXTURES/mailru-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -s 'length')" -eq 2 ]
  [ "$(echo "$output" | jq -sr '.[0].org')" = "Mail.Ru" ]
}

@test "parse: np is null where the reporter omits it, and a STRING where present" {
  # Mail.Ru omits <np> and includes <sp>; Google sends both. A parser that
  # defaulted a missing np to "none" would invent a published policy.
  run "$PARSE" parse "$FIXTURES/mailru-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -sr '.[0].np | type')" = "null" ]
  [ "$(echo "$output" | jq -sr '.[0].sp')" = "none" ]

  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -sr '.[0].np')" = "none" ]
}

@test "parse: the spf scope is carried where present and null where absent" {
  run "$PARSE" parse "$FIXTURES/mailru-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -sr '.[0].spf_auth[0].scope')" = "mfrom" ]

  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -sr '.[0].spf_auth[0].scope | type')" = "null" ]
}

# --- the local_policy reason -------------------------------------------------

@test "parse: a policy_evaluated reason is carried, and is null where absent" {
  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success

  row=$(echo "$output" | jq -c 'select(.source_ip == "203.0.113.77")')
  [ "$(echo "$row" | jq -r '.reason_type')" = "local_policy" ]

  clean=$(echo "$output" | jq -c 'select(.source_ip == "192.0.2.10")')
  [ "$(echo "$clean" | jq -r '.reason_type | type')" = "null" ]
}

# --- purity and failure ------------------------------------------------------

# AT-5.2
@test "parse: is PURE -- it reads no profile and makes no network call" {
  # `report` and `check` are tested against parser output with no profile in
  # existence, so parse must never reach for one.
  run env DEVBIN_INFRA_PROFILE=/nonexistent/profile.yaml "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success
  [ "$(echo "$output" | jq -s 'length')" -eq 3 ]
}

# AT-5.2
@test "parse: a malformed report FAILS LOUDLY rather than emitting zero rows" {
  # Zero rows is what a clean report and an unreadable one both look like.
  bad="$BATS_TEST_TMPDIR/bad.xml"
  printf '%s' '<feedback><record><row>' >"$bad"

  run "$PARSE" parse "$bad"
  assert_failure
  # THE ASSERTION IS THE SPECIFIC MESSAGE, and the loose one is why.
  # This once read `grep -qiE 'parse|malformed|xml'`, and on the
  # Ubuntu runner it passed while its nine siblings failed -- because the
  # refusal it actually matched was `xmllint not found. Install libxml2`, whose
  # third word contains `xml`. Measured both ways: with xmllint absent and with
  # it present, status and regex were identical, so the arm could not tell
  # "the parser rejected bad input" from "the parser was never installed".
  # That is verbatim the trap this project already wrote down in `help test`:
  # a non-zero exit read as "devbin declined" when it meant "the thing devbin
  # should not have run broke".
  assert_output_contains "malformed XML"
}

# AT-5.2
@test "parse: a missing file FAILS, naming the path" {
  run "$PARSE" parse "$BATS_TEST_TMPDIR/no-such-report.xml"
  assert_failure
  assert_output_contains "no-such-report.xml"
}

# --- CONTAINERS: what reporters actually send --------------------------------
#
# MEASURED, NOT ASSUMED. Across a collection of 17 real aggregate reports from
# three reporters, Google and Outlook ship `.zip` and mail.ru ships `.xml.gz`.
# NOT ONE arrived as bare XML. Before containers were read, `parse` took
# `<report.xml>` only, so it could read none of them -- and it failed with
# "malformed XML ... Start tag expected, '<' not found PK", a complaint about
# the CONTENT when the fault was the WRAPPER.


# AT-5.6
@test "parse reads a ZIP, and the rows are identical to the same report bare" {
  require_command zip
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/r.xml"
  ( cd "$BATS_TEST_TMPDIR" && zip -q r.zip r.xml )
  run "$PARSE" parse "$BATS_TEST_TMPDIR/r.zip"
  assert_success
  local from_zip="$output"
  run "$PARSE" parse "$FIXTURES/google-shape.xml"
  assert_success
  # THE CONTAINER MUST BE TRANSPARENT. Asserting only "it parsed" would pass for
  # a decoder that dropped or reordered records.
  [ "$from_zip" = "$output" ]
}

# AT-5.6
@test "parse reads an xml.gz, which is the shape mail.ru sends" {
  # THIS ARM IS NOT EVIDENCE ABOUT DEVBIN'S UNPACKER, and saying so is the
  # point of the comment. Measured: libxml2 INFLATES GZIP
  # TRANSPARENTLY, so `xmllint --noout r.xml.gz` exits 0 with no help from
  # anything here -- this arm was green before the unpacker existed and stayed
  # green when the unpack call was deleted. It is kept because the BEHAVIOUR is
  # part of the contract, not because it discriminates.
  #
  # The arms that actually hold the unpacker are the ones that went red under
  # mutation: the zip named `.xml` (magic bytes, not extension), the member
  # count, and the ZERO-bytes refusal -- and the last of those is what covers
  # this path, since libxml2 gives an empty gz no special treatment.
  require_command gzip
  cp "$FIXTURES/mailru-shape.xml" "$BATS_TEST_TMPDIR/r.xml"
  gzip -c "$BATS_TEST_TMPDIR/r.xml" > "$BATS_TEST_TMPDIR/r.xml.gz"
  run "$PARSE" parse "$BATS_TEST_TMPDIR/r.xml.gz"
  assert_success
  [ "$(echo "$output" | jq -s 'length')" -ge 1 ]
}

# AT-5.6
@test "the kind is read from the BYTES, so a zip named .xml still parses" {
  # THE ARM THAT MAKES THE RULE REAL. Reporters name files by convention and
  # nothing enforces it; this project already refuses to classify a build tree
  # by its NAME. If detection keyed on the extension this arm would report
  # malformed XML, naming the content when the fault is the wrapper.
  require_command zip
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/r.xml"
  ( cd "$BATS_TEST_TMPDIR" && zip -q lying.zip r.xml && mv lying.zip lying.xml )
  run "$PARSE" parse "$BATS_TEST_TMPDIR/lying.xml"
  assert_success
  [ "$(echo "$output" | jq -s 'length')" -eq 3 ]
}

# AT-5.7
@test "a zip holding more than one member is REFUSED, naming the count and each member" {
  require_command zip
  local -a members=(a.xml b.xml)
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/a.xml"
  cp "$FIXTURES/mailru-shape.xml" "$BATS_TEST_TMPDIR/b.xml"
  ( cd "$BATS_TEST_TMPDIR" && zip -q two.zip "${members[@]}" )
  run "$PARSE" parse "$BATS_TEST_TMPDIR/two.zip"
  assert_failure
  assert_output_contains "${#members[@]} member(s), not 1"
  assert_output_contains "a.xml"
  assert_output_contains "b.xml"
}

# AT-5.7
@test "a zip holding NO members is refused rather than read as an empty report" {
  require_command zip
  ( cd "$BATS_TEST_TMPDIR" && : > empty.txt && zip -q empty.zip empty.txt && zip -qd empty.zip empty.txt )
  run "$PARSE" parse "$BATS_TEST_TMPDIR/empty.zip"
  assert_failure
  assert_output_contains "0 member(s), not 1"
}

# AT-5.7
@test "a gzip unpacking to ZERO bytes is refused -- an empty unpack is not an empty report" {
  require_command gzip
  : > "$BATS_TEST_TMPDIR/nothing"
  gzip -c "$BATS_TEST_TMPDIR/nothing" > "$BATS_TEST_TMPDIR/nothing.gz"
  run "$PARSE" parse "$BATS_TEST_TMPDIR/nothing.gz"
  assert_failure
  assert_output_contains "unpacked to ZERO bytes"
}

# --- A DIRECTORY OF REPORTS, WHICH IS HOW THEY ARRIVE ------------------------
#
# Measured on a real collection of 17: dated subdirectories, and a
# `.DS_Store` sitting beside them. `parse` took ONE file, so every consumer had
# to write the walk AND the "is this a report" rule themselves -- a second
# implementation of the classification in each of them, none tested, and the
# obvious `for f in dir/*` dies on the first Mac that touches the folder.

# AT-5.8
@test "parse walks a DIRECTORY, and its rows equal parsing each file by hand" {
  require_command zip
  mkdir -p "$BATS_TEST_TMPDIR/d/sub"
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d/a.xml"
  cp "$FIXTURES/mailru-shape.xml" "$BATS_TEST_TMPDIR/d/sub/b.xml"
  # STDERR IS REDIRECTED RATHER THAN CAPTURED. bats merges both streams into
  # $output, so comparing rows through `run` would compare the accounting too
  # and fail for a reason that has nothing to do with the rows.
  "$PARSE" parse "$BATS_TEST_TMPDIR/d" 2>/dev/null | LC_ALL=C sort > "$BATS_TEST_TMPDIR/walked"
  {
    "$PARSE" parse "$BATS_TEST_TMPDIR/d/a.xml" 2>/dev/null
    "$PARSE" parse "$BATS_TEST_TMPDIR/d/sub/b.xml" 2>/dev/null
  } | LC_ALL=C sort > "$BATS_TEST_TMPDIR/byhand"
  # The walk must be TRANSPARENT: same rows, nothing dropped or invented.
  run diff "$BATS_TEST_TMPDIR/walked" "$BATS_TEST_TMPDIR/byhand"
  assert_success
}

# AT-5.8
@test "a file that is NOT a report is NAMED, never silently stepped over" {
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d2/r.xml" 2>/dev/null || \
    { mkdir -p "$BATS_TEST_TMPDIR/d2"; cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d2/r.xml"; }
  printf '\000\000\000junk' > "$BATS_TEST_TMPDIR/d2/.DS_Store"
  run "$PARSE" parse "$BATS_TEST_TMPDIR/d2"
  assert_success
  assert_output_contains "1 parsed, 1 not a report, 0 failed"
  assert_output_contains ".DS_Store"
}

# AT-5.8
@test "a BROKEN report is FAILED and fatal, which is not the same as not a report" {
  # THE DISCRIMINATING ARM. A walk with one bucket would let a truncated
  # archive leave through the same door as a .DS_Store -- a run that still
  # printed rows and still exited 0, with a report silently missing from it.
  mkdir -p "$BATS_TEST_TMPDIR/d3"
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d3/good.xml"
  printf '<feedback><truncated' > "$BATS_TEST_TMPDIR/d3/broken.xml"
  run "$PARSE" parse "$BATS_TEST_TMPDIR/d3"
  assert_failure
  assert_output_contains "1 failed"
  assert_output_contains "FAILED"
  assert_output_contains "broken.xml"
}

# AT-5.8
@test "a directory holding NO reports is an ERROR, never an empty success" {
  mkdir -p "$BATS_TEST_TMPDIR/d4"
  printf 'nothing here' > "$BATS_TEST_TMPDIR/d4/readme.txt"
  run "$PARSE" parse "$BATS_TEST_TMPDIR/d4"
  assert_failure
  assert_output_contains "no DMARC reports found"
  assert_output_contains "wrong path"
}

# AT-5.8
@test "the accounting goes to STDERR, so stdout stays pure JSON Lines" {
  mkdir -p "$BATS_TEST_TMPDIR/d5"
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d5/r.xml"
  printf '\000\000junk' > "$BATS_TEST_TMPDIR/d5/.DS_Store"
  "$PARSE" parse "$BATS_TEST_TMPDIR/d5" > "$BATS_TEST_TMPDIR/out.jsonl" 2>"$BATS_TEST_TMPDIR/acct.txt"
  # Every stdout line must be a JSON object -- one non-row and the pipeline breaks.
  run jq -e -s 'length == 3 and all(type == "object")' "$BATS_TEST_TMPDIR/out.jsonl"
  assert_success
  grep -q "not a report" "$BATS_TEST_TMPDIR/acct.txt"
}

# A WALK THAT CANNOT READ EVERYTHING IS REFUSED (issue 0139). The walk ran in a
# process substitution with find's errors sent to /dev/null, so a report
# beneath a directory find could not read was never parsed, and the counts said
# "1 parsed" over the part as if it were the whole.
@test "parse refuses a directory find cannot read wholly, and parses nothing, never a count over part of it (0139, 0145)" {
  mkdir -p "$BATS_TEST_TMPDIR/d6/locked" "$BATS_TEST_TMPDIR/tmpd"
  cp "$FIXTURES/google-shape.xml" "$BATS_TEST_TMPDIR/d6/a.xml"
  cp "$FIXTURES/mailru-shape.xml" "$BATS_TEST_TMPDIR/d6/locked/b.xml"
  # THE CONTROL: readable, both reports are parsed.
  TMPDIR="$BATS_TEST_TMPDIR/tmpd" run "$PARSE" parse "$BATS_TEST_TMPDIR/d6"
  assert_success
  assert_output_contains "2 parsed, 0 not a report, 0 failed"
  chmod 000 "$BATS_TEST_TMPDIR/d6/locked"
  if [ -r "$BATS_TEST_TMPDIR/d6/locked" ]; then
    chmod 755 "$BATS_TEST_TMPDIR/d6/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  TMPDIR="$BATS_TEST_TMPDIR/tmpd" run "$PARSE" parse "$BATS_TEST_TMPDIR/d6"
  chmod 755 "$BATS_TEST_TMPDIR/d6/locked"
  assert_failure
  assert_output_contains "could not list every file under $BATS_TEST_TMPDIR/d6"
  refute_output_contains "parsed,"
  refute_output_contains '"source_ip"'
  # find's own error names the directory, in any form find prints it.
  assert_find_denied "d6/locked"
  # And nothing is left in TMPDIR, after the refusal as after the parse.
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmpd")" ] || fail "a temporary file was left behind: $(ls -A "$BATS_TEST_TMPDIR/tmpd")"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and parse counted the one report it saw.
  chmod 644 "$BATS_TEST_TMPDIR/d6/locked"
  if [ -x "$BATS_TEST_TMPDIR/d6/locked" ]; then
    chmod 755 "$BATS_TEST_TMPDIR/d6/locked"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  TMPDIR="$BATS_TEST_TMPDIR/tmpd" run "$PARSE" parse "$BATS_TEST_TMPDIR/d6"
  chmod 755 "$BATS_TEST_TMPDIR/d6/locked"
  assert_failure
  assert_output_contains "cannot search $BATS_TEST_TMPDIR/d6/locked -- nothing beneath it was looked at"
  assert_output_contains "could not list every file under $BATS_TEST_TMPDIR/d6"
  refute_output_contains "parsed,"
}
