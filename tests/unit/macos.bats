#!/usr/bin/env bats
# macos.bats - the built-in `macos`: a macOS app's release (issue 0226)
#
# Everything here runs without Apple's services. security(1), codesign,
# xcrun (notarytool and stapler), spctl and lsregister are stubs under the
# test's tmpdir, first on PATH, each recording its calls; ditto, xattr, plutil
# and file are the system's, so the arms run on macOS alone and skip
# elsewhere. The one arm that runs everywhere is the refusal off macOS, with a
# stub uname on macOS and the real one elsewhere. Real signing and
# notarisation are proven by hand, at the first release that uses the built-in.
#
# The stub keychain is $DEVBIN_TEST_TMPDIR/kc: one file per service, holding the
# value, and kc/identities for what find-identity lists. Every value is a
# word no output should hold, so an arm can look for each in what it printed.

load "../lib/test_helper"
load "../lib/release_fixtures"

setup() {
  devbin_setup
  export DEVBIN_RELEASE_POLL_SECONDS=1
  export XDG_STATE_HOME="$DEVBIN_TEST_TMPDIR/state"
  APPLE="$BATS_TEST_TMPDIR/apple"
  mkdir -p "$DEVBIN_TEST_TMPDIR/tmp"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
}
# A dir the lsregister fake made unwritable (ls.lockdir) is made writable again
# and its staging dir removed, since a dir that cannot be written stops the
# test dir's own removal.
teardown() {
  local d
  if [ -f "$DEVBIN_TEST_TMPDIR/ls.locked" ]; then
    while IFS= read -r d; do
      case "$d" in */unpacked) ;; *) continue ;; esac
      chmod -R u+w "${d%/unpacked}" 2>/dev/null || true
      rm -rf "${d%/unpacked}"
    done <"$DEVBIN_TEST_TMPDIR/ls.locked"
  fi
  devbin_teardown
}

# on_macos -- skip off macOS, naming what was not checked.
on_macos() {
  [ "$(uname -s)" = Darwin ] || skip "macos runs on macOS only: this arm was NOT checked here"
}

# The credentials and the identity the stub keychain holds. Values no output
# may carry, and an identity whose holder's name may never be printed whole.
SECRET_ID="appleid-not-for-output"
SECRET_PW="password-not-for-output"
TEAM="TEAMID1234"
HOLDER="Holder Not For Output"

# apple_stubs -- the stub tools, first on PATH through $APPLE.
apple_stubs() {
  local T="$DEVBIN_TEST_TMPDIR"
  mkdir -p "$APPLE" "$T/kc"
  cat >"$APPLE/security" <<SH
#!/bin/sh
echo "security \$*" >>"$T/apple.calls"
case "\$1" in
  find-generic-password)
    while [ \$# -gt 0 ]; do [ "\$1" = -s ] && svc="\$2"; shift; done
    [ -f "$T/kc/\$svc" ] || exit 44
    cat "$T/kc/\$svc"
    ;;
  find-identity)
    [ ! -f "$T/kc/identities" ] || cat "$T/kc/identities"
    echo "     0 valid identities found" ;;
  add-generic-password) ;;
  *) exit 1 ;;
esac
SH
  # codesign: --sign marks a bundle signed (its _CodeSignature, holding the
  # team the identity names); -d prints what the bytes say, as codesign
  # does on stderr: the build's identifier and no team until a Developer ID
  # signature is on it.
  cat >"$APPLE/codesign" <<SH
#!/bin/sh
echo "codesign \$*" >>"$T/apple.calls"
for a in "\$@"; do last="\$a"; done
[ ! -f "$T/codesign.fails" ] || exit 1
case " \$* " in
  *" -d "*)
    if [ -f "\$last/Contents/_CodeSignature/CodeResources" ]; then
      id="\$(plutil -extract CFBundleIdentifier raw -o - "\$last/Contents/Info.plist")"
      echo "Identifier=\$id" >&2
      echo "CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1" >&2
      echo "TeamIdentifier=\$(cat "\$last/Contents/_CodeSignature/CodeResources")" >&2
    else
      echo "Identifier=Demo" >&2
      echo "CodeDirectory v=20400 size=1 flags=0x20002(adhoc,linker-signed) hashes=1" >&2
      echo "TeamIdentifier=not set" >&2
    fi ;;
  *" --verify "*)
    [ ! -d "\$last" ] || [ -f "\$last/Contents/_CodeSignature/CodeResources" ] ;;
  *" --sign "*)
    if [ -d "\$last" ]; then
      while [ \$# -gt 0 ]; do [ "\$1" = --sign ] && who="\$2"; shift; done
      team="\${who##*(}"
      mkdir -p "\$last/Contents/_CodeSignature"
      printf '%s' "\${team%)}" >"\$last/Contents/_CodeSignature/CodeResources"
      case "\$last" in *.app) (cd "\$last" && pwd -P) >>"$T/ls.records" ;; esac
    fi ;;
esac
SH
  # xcrun: stapler staples a bundle (Contents/stapled) and validates one that
  # has it; notarytool answers Accepted with a submission id, or what
  # notary.status holds.
  cat >"$APPLE/xcrun" <<SH
#!/bin/sh
echo "xcrun \$*" >>"$T/apple.calls"
for a in "\$@"; do last="\$a"; done
case "\$1 \$2" in
  "stapler validate")
    [ ! -d "\$last" ] || (cd "\$last" && pwd -P) >>"$T/ls.records"
    [ -f "\$last/Contents/stapled" ] ;;
  "stapler staple")
    (cd "\$last" && pwd -P) >>"$T/ls.records"
    : >"\$last/Contents/stapled" ;;
  "notarytool submit")
    echo "  id: 0f0e0d0c-0b0a-0908-0706-050403020100"
    echo "  status: \$(cat "$T/notary.status" 2>/dev/null || echo Accepted)" ;;
  "notarytool log") echo "the log" ;;
  *) exit 1 ;;
esac
SH
  # term_macos <pid>: TERM to the macos process, the top of the run of
  # ancestors from <pid> up whose command line is the handler's own. bin/devbin
  # execs the handler, so the macos process and its subshells run that line,
  # and the first ancestor that does not ends the walk: nothing above the run,
  # a launcher whose own command text names the handler included, can be taken
  # for it. Logs the pid signalled, its command line and its parent's.
  sed "s#@T@#$T#g" >"$APPLE/term_macos" <<'SH'
#!/bin/sh
p="$1"
top=""
while [ "${p:-1}" -gt 1 ]; do
  case "$(ps -o args= -p "$p" 2>/dev/null)" in
    */lib/cmd/macos" "*) top="$p" ;;
    *) break ;;
  esac
  p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
done
if [ -z "$top" ]; then
  echo "term_macos found no macos process above $1" >>"@T@/apple.calls"
  exit 0
fi
parent="$(ps -o ppid= -p "$top" | tr -d ' ')"
echo "term_macos signalled $top, running: $(ps -o args= -p "$top"); its parent runs: $(ps -o args= -p "$parent")" >>"@T@/apple.calls"
kill -TERM "$top"
SH
  # spctl: a stapled bundle is notarised, any other is not. With spctl.signal
  # present it sends the macos process TERM first (term_macos).
  cat >"$APPLE/spctl" <<SH
#!/bin/sh
echo "spctl \$*" >>"$T/apple.calls"
for a in "\$@"; do last="\$a"; done
[ ! -d "\$last" ] || (cd "\$last" && pwd -P) >>"$T/ls.records"
[ ! -f "$T/spctl.signal" ] || term_macos "\$PPID"
if [ -f "\$last/Contents/stapled" ]; then echo "source=Notarized Developer ID" >&2; else echo "source=Unnotarized Developer ID" >&2; exit 3; fi
SH
  # lsregister: Launch Services' records as a file, ls.records, one resolved
  # path a line, after a system app the real list always holds. codesign,
  # stapler and spctl register the bundle they are given, as the real ones can.
  #   -u <path>  drops its record, or exits 1, as the real one does, when it
  #              holds none; a path holding the text in ls.stuck keeps its
  #              record and exits 0. For a path holding the text in ls.signal
  #              it first sends the macos process TERM (term_macos), and for
  #              one holding the text in ls.lockdir it makes the dir holding
  #              the path unwritable, so it cannot be removed, and records it
  #              in ls.locked for teardown.
  #   -dump      each record in the real dump's shape; it fails once the path
  #              dump.fail names exists.
  sed "s#@T@#$T#g" >"$APPLE/lsregister" <<'SH'
#!/bin/sh
echo "lsregister $*" >>"@T@/apple.calls"
records="@T@/ls.records"
touch "$records"
case "$1" in
  -u)
    if [ -f "@T@/ls.signal" ]; then
      case "$2" in *"$(cat "@T@/ls.signal")"*) term_macos "$PPID" ;; esac
    fi
    if [ -f "@T@/ls.lockdir" ]; then
      case "$2" in
        *"$(cat "@T@/ls.lockdir")"*)
          d="$(dirname "$2")"
          echo "$d" >>"@T@/ls.locked"
          chmod 555 "$d"
          ;;
      esac
    fi
    grep -qxF -- "$2" "$records" || { echo "failed to scan $2: -10814 from spotlight" >&2; exit 1; }
    if [ -f "@T@/ls.stuck" ]; then
      case "$2" in *"$(cat "@T@/ls.stuck")"*) exit 0 ;; esac
    fi
    # grep's 1 is "no line left", which is a list; anything else is grep
    # failing, and the list must not be replaced by an empty one.
    grep -vxF -- "$2" "$records" >"$records.new"
    rc=$?
    [ "$rc" -le 1 ] || { echo "fake lsregister: grep failed (exit $rc)" >&2; exit 2; }
    mv -f "$records.new" "$records"
    ;;
  -dump)
    if [ -f "@T@/dump.fail" ] && [ -e "$(cat "@T@/dump.fail")" ]; then
      echo "lsregister: dump failed" >&2
      exit 1
    fi
    printf 'path:                       /System/Applications/Calculator.app (0x4e000)\nidentifier:                 com.apple.calculator\n--------\n'
    while IFS= read -r p; do
      printf 'path:                       %s (0x4ed01)\nidentifier:                 com.example.demo\n--------\n' "$p"
    done <"$records"
    ;;
esac
SH
  printf '#!/bin/sh\necho Linux\n' >"$APPLE/uname.linux"
  chmod +x "$APPLE"/*
}

# store <name> <value> -- a credential in the stub keychain, under devbin.apple.
store() { printf '%s' "$2" >"$DEVBIN_TEST_TMPDIR/kc/devbin.apple.$1"; }

# keychain_full -- every credential stored, and one Developer ID identity.
keychain_full() {
  store APPLE_ID "$SECRET_ID"
  store APPLE_APP_PASSWORD "$SECRET_PW"
  store APPLE_TEAM_ID "$TEAM"
  printf '  1) 0123456789ABCDEF "Developer ID Application: %s (%s)"\n' "$HOLDER" "$TEAM" >"$DEVBIN_TEST_TMPDIR/kc/identities"
}

# macos_in <proj> <args...> -- the built-in with the stubs first on PATH (gh's
# too, from git_project), through the project's own launcher, with TMPDIR in the
# test's dir: a staging or check dir a red run leaves goes with the test.
macos_in() {
  local proj="$1"
  shift
  TMPDIR="$DEVBIN_TEST_TMPDIR/tmp" PATH="$APPLE:$DEVBIN_TEST_TMPDIR/stubs:$PATH" devbin_run "$proj" macos "$@"
}

# calls <pattern> -- how many recorded stub calls match <pattern>.
calls() {
  [ -f "$DEVBIN_TEST_TMPDIR/apple.calls" ] || {
    echo 0
    return 0
  }
  grep -c -- "$1" "$DEVBIN_TEST_TMPDIR/apple.calls" || [ $? -eq 1 ]
}

# make_app <dir> [id] [version] -- a Demo.app under <dir>: its Info.plist, a
# main executable, and a nested Mach-O helper (a copy of /usr/bin/true), so
# the inside-out walk has something to sign.
make_app() {
  local app="$1/Demo.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "${2:-com.example.demo}" "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string "${3:-1.0.0}" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string Demo "$app/Contents/Info.plist"
  printf '#!/bin/sh\n' >"$app/Contents/MacOS/Demo"
  chmod +x "$app/Contents/MacOS/Demo"
  cp /usr/bin/true "$app/Contents/Helpers/helper"
}

# app_project [extra-macos-yaml] [app-version] [extra-project-yaml] -- a project
# at VERSION 1.0.0, release and macos enabled, its app declared at
# build/Products/Release/Demo.app (which the tree ignores, as a build product
# is), committed, tagged v1.0.0 at HEAD and pushed, with a release object for
# v1.0.0. With <app-version>, the app is built at that version and app/VERSION
# holds it, for an app that versions apart. <extra-project-yaml> goes under
# project:, eg an absolute version_from.
app_project() {
  local proj
  proj="$(mkproj demo <<YAML
project:
  name: demo
${3:-}
commands:
  release:
    enabled: true
  macos:
    enabled: true
macos:
  app: build/Products/Release/Demo.app
  bundle_id: com.example.demo
${1:-}
YAML
  )"
  printf '1.0.0\n' >"$proj/VERSION"
  printf 'build/\ntmp/\n' >"$proj/.gitignore"
  if [ -n "${2:-}" ]; then
    mkdir -p "$proj/app"
    printf '%s\n' "$2" >"$proj/app/VERSION"
  fi
  make_app "$proj/build/Products/Release" com.example.demo "${2:-1.0.0}"
  with_dated_note "$proj"
  git_project "$proj"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -a v1.0.0 -m "- first" --cleanup=whitespace
  git -C "$proj" push -q origin v1.0.0
  gh_object v1.0.0 v1.0.0 "- first"
  printf '%s\n' "$proj"
}

# product_sum <proj> -- every byte of the build product, as one line.
product_sum() {
  (cd "$1/build/Products/Release" && find Demo.app -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum <"$f")" "$f"; done)
}

# stage_of <proj> -- the staged Demo.app app-sign signs, found under the stage.
stage_of() { find "$XDG_STATE_HOME/devbin/macos" -maxdepth 2 -name Demo.app -type d; }

# no_secret -- the output holds no credential value and no whole identity.
no_secret() {
  refute_output_contains "$SECRET_ID"
  refute_output_contains "$SECRET_PW"
  refute_output_contains "$HOLDER"
}

# ============================================================================
# THE PLATFORM, AND THE WORD (Done when 5)
# ============================================================================

@test "off macOS every subcommand refuses with exit 2, naming macOS, before any tool or credential is read" {
  apple_stubs
  local stub="$APPLE"
  if [ "$(uname -s)" = Darwin ]; then
    mkdir -p "$BATS_TEST_TMPDIR/linux"
    cp "$APPLE/uname.linux" "$BATS_TEST_TMPDIR/linux/uname"
    stub="$BATS_TEST_TMPDIR/linux:$APPLE"
  fi
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  macos:
    enabled: true
macos:
  app: Demo.app
  bundle_id: com.example.demo
YAML
  )"
  for sub in doctor store-creds app-sign app-notarize app-verify publish; do
    PATH="$stub:$PATH" run devbin_run "$proj" macos "$sub"
    [ "$status" -eq 2 ] || fail "macos $sub off macOS: exit $status, want 2: $output"
    assert_output_contains "macos: $sub runs on macOS only"
  done
  [ "$(calls .)" -eq 0 ] || fail "a refusal off macOS called a tool: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  PATH="$stub:$PATH" run devbin_run "$proj" macos --help
  assert_success
  assert_output_contains "on macOS only"
}

@test "an unknown subcommand, or an argument after one, is a usage error on every platform, exit 1, reading nothing" {
  apple_stubs
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  macos:
    enabled: true
YAML
  )"
  PATH="$APPLE:$PATH" run devbin_run "$proj" macos all
  assert_exit_code 1
  assert_output_contains "macos: unknown subcommand 'all'"
  PATH="$APPLE:$PATH" run devbin_run "$proj" macos doctor extra
  assert_exit_code 1
  assert_output_contains "macos doctor takes no arguments, got: extra"
  [ "$(calls .)" -eq 0 ] || fail "a usage error called a tool: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

# ============================================================================
# THE DECLARATION (Done when 1)
# ============================================================================

@test "the macos: keys validate, an unknown one is refused by name, and keychain and asset take their defaults" {
  on_macos
  apple_stubs
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  macos:
    enabled: true
macos:
  app: build/Demo.app
  build: make app
  bundle_id: com.example.demo
  entitlements: Demo.entitlements
  keychain: demo.apple
  asset: Demo-mac.zip
YAML
  )"
  run devbin_run "$proj" doctor
  refute_output_contains "unknown key: macos"
  printf 'project:\n  name: demo\ncommands:\n  macos:\n    enabled: true\nmacos:\n  bundle: com.example.demo\n' >"$proj/bin/.devbin/config.yaml"
  run devbin_run "$proj" doctor
  assert_output_contains "unknown key: macos.bundle"
  printf 'project:\n  name: demo\ncommands:\n  macos:\n    enabled: true\nmacos:\n  app: build/Demo.app\n  bundle_id: com.example.demo\n' >"$proj/bin/.devbin/config.yaml"
  macos_in "$proj" doctor || true
  run macos_in "$proj" doctor
  assert_output_contains "devbin.apple"
  assert_output_contains "Demo.app.zip"
  assert_output_contains "none: signed without"
}

@test "app-sign without macos.app or macos.bundle_id refuses, naming every key missing, and signs nothing" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
commands:
  macos:
    enabled: true
YAML
  )"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "declares no macos.app"
  assert_output_contains "macos.bundle_id"
  [ "$(calls '^codesign')" -eq 0 ] || fail "a refused app-sign signed: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

# ============================================================================
# DOCTOR AND THE KEYCHAIN (Done when 2)
# ============================================================================

@test "doctor reports each credential PRESENT and the identity by count and team, never a value or the identity whole" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  run macos_in "$proj" doctor
  assert_success
  assert_output_contains "1 found, team $TEAM"
  assert_output_contains "signs and verifies"
  for k in APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID; do
    assert_output_matches "  $k +PRESENT"
  done
  no_secret
}

@test "doctor reports each credential and the identity MISSING when the keychain holds none, and exits 1" {
  on_macos
  apple_stubs
  proj="$(app_project)"
  run macos_in "$proj" doctor
  assert_failure
  assert_output_contains 'MISSING (no "Developer ID Application" identity'
  for k in APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID; do
    assert_output_matches "  $k +MISSING"
  done
  # The credentials were asked for under the prefix, and nothing was written.
  [ "$(calls 'find-generic-password .* -s devbin.apple.APPLE_ID ')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(calls 'add-generic-password')" -eq 0 ] || fail "doctor wrote to the keychain"
}

@test "a declared keychain prefix is the one the credentials are read under" {
  on_macos
  apple_stubs
  proj="$(app_project "  keychain: demo.apple")"
  run macos_in "$proj" doctor
  [ "$(calls '-s demo.apple.APPLE_APP_PASSWORD ')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(calls '-s devbin.apple.')" -eq 0 ] || fail "read under the default prefix too: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

@test "store-creds refuses without a terminal, writing nothing to the keychain" {
  on_macos
  apple_stubs
  proj="$(app_project)"
  run macos_in "$proj" store-creds
  assert_failure
  assert_output_contains "store-creds is interactive"
  [ "$(calls 'add-generic-password')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

# ============================================================================
# THE STAGE (Done when 3)
# ============================================================================

@test "app-sign signs a staged copy outside the build tree, inside-out, and never the build product" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  before="$(product_sum "$proj")"
  run macos_in "$proj" app-sign
  assert_success
  dist="$(stage_of)"
  [ -n "$dist" ] || fail "no staged Demo.app under $XDG_STATE_HOME: $output"
  case "$dist" in "$proj"/*) fail "the stage $dist is inside the project" ;; esac
  # Every signature went onto the staged copy: the nested helper first, then
  # the bundle, and nothing under the project.
  [ "$(calls "^codesign .*--sign .* $dist/Contents/Helpers/helper\$")" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(calls "^codesign .*--sign .* $dist\$")" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(calls "^codesign .* $proj")" -eq 0 ] || fail "codesign touched the project: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(product_sum "$proj")" = "$before" ] || fail "the build product changed"
  assert_output_matches "identifier +com\.example\.demo"
  assert_output_matches "team +$TEAM"
  no_secret
}

@test "app-sign runs macos.build at the project root before it stages" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "  build: ./mkapp")"
  # The build is what makes the product: it is removed first, so a staged
  # copy can only be the one the build made.
  rm -rf "$proj/build/Products/Release/Demo.app"
  printf '#!/usr/bin/env bash\npwd -P >"%s/built.at"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/mkapp"
  declare -f make_app >>"$proj/mkapp"
  printf 'make_app build/Products/Release\n' >>"$proj/mkapp"
  chmod +x "$proj/mkapp"
  git -C "$proj" add mkapp
  git -C "$proj" -c user.name=t -c user.email=t@t commit -qm build
  git -C "$proj" -c user.name=t -c user.email=t@t tag -f -a v1.0.0 -m "- first" >/dev/null
  run macos_in "$proj" app-sign
  assert_success
  [ "$(cat "$DEVBIN_TEST_TMPDIR/built.at")" = "$(cd "$proj" && pwd -P)" ] || fail "the build ran in $(cat "$DEVBIN_TEST_TMPDIR/built.at")"
  [ -n "$(stage_of)" ] || fail "nothing staged: $output"
}

@test "a stage inside the project is refused before it is made, and nothing is signed" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  XDG_STATE_HOME="$proj/build/state" run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "the subject of signing is a copy outside the build tree"
  [ ! -e "$proj/build/state" ] || fail "the refused stage was made"
  [ "$(calls '^codesign')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

@test "a stage whose path holds . or .. past the part that exists is refused before it is made, as cargo_place refuses it, and nothing is signed (0267)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  [[ "$proj" == "$DEVBIN_TEST_TMPDIR"/* ]] || fail "the fixture project $proj is not under $DEVBIN_TEST_TMPDIR, which this spelling needs"
  # nope is not there, so the kernel never reads the `..` after it, and as
  # text the stage is outside the project: made, it lands in the build tree.
  XDG_STATE_HOME="$DEVBIN_TEST_TMPDIR/nope/..${proj#"$DEVBIN_TEST_TMPDIR"}/build/state" run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "names . or .. beneath a directory that does not exist yet"
  [ ! -e "$DEVBIN_TEST_TMPDIR/nope" ] || fail "the refused stage's path was made"
  [ ! -e "$proj/build/state" ] || fail "the refused stage was made in the project"
  [ "$(calls '^codesign')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

@test "a stage inside the project spelled in another case is refused where the disk folds case, and nothing is signed (0267)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  local name upper
  name="${proj##*/}"
  upper="${proj%/*}/$(tr '[:lower:]' '[:upper:]' <<<"$name")"
  [ "$upper" != "$proj" ] || fail "the fixture project's name $name holds no lower-case letter to spell in another case"
  [ "$upper" -ef "$proj" ] || skip "this disk does not fold case, where $upper is no spelling of $proj: the other-case stage was NOT checked"
  XDG_STATE_HOME="$upper/build/state" run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "the subject of signing is a copy outside the build tree"
  [ ! -e "$proj/build/state" ] || fail "the refused stage was made in the project"
  [ "$(calls '^codesign')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

@test "app-sign refuses off the release tag, and in a dirty tree, building and signing nothing" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "  build: ./mkapp")"
  printf '#!/bin/sh\n: >"%s/built"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/mkapp"
  chmod +x "$proj/mkapp"
  git -C "$proj" add mkapp
  git -C "$proj" -c user.name=t -c user.email=t@t commit -qm "past the tag"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "app-sign signs only the release's build: HEAD at v1.0.0"
  assert_output_contains "git worktree add --detach <dir> v1.0.0"
  git -C "$proj" -c user.name=t -c user.email=t@t tag -f -a v1.0.0 -m "- first" >/dev/null
  printf 'x\n' >"$proj/dirt"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "with changes"
  [ ! -e "$DEVBIN_TEST_TMPDIR/built" ] || fail "a refused app-sign ran the build"
  [ "$(calls '^codesign')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

@test "a staged copy with another bundle id, or another version, is refused and removed, with nothing signed" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  for bad in id version; do
    rm -rf "$proj/build/Products/Release/Demo.app"
    case "$bad" in
      id) make_app "$proj/build/Products/Release" com.example.other 1.0.0 ;;
      version) make_app "$proj/build/Products/Release" com.example.demo 0.9.0 ;;
    esac
    run macos_in "$proj" app-sign
    assert_failure
    assert_output_contains "the staged Demo.app cannot ship with release v1.0.0 -- nothing signed"
    case "$bad" in
      id) assert_output_contains "its bundle id is com.example.other, and macos.bundle_id is com.example.demo" ;;
      version) assert_output_contains "its version is 0.9.0, and the project is at 1.0.0" ;;
    esac
    [ -z "$(stage_of)" ] || fail "the refused stage was left: $(stage_of)"
  done
  [ "$(calls '^codesign')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
}

# ============================================================================
# NOTARISE, AND THE ATTACH THROUGH THE RELEASE CORE (Done when 2 and 4)
# ============================================================================

@test "app-notarize submits the signed copy, staples it only when Accepted, and passes no credential to the output" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  macos_in "$proj" app-sign >/dev/null
  dist="$(stage_of)"
  printf 'Invalid\n' >"$DEVBIN_TEST_TMPDIR/notary.status"
  run macos_in "$proj" app-notarize
  assert_failure
  assert_output_contains "notarisation was not Accepted (status: Invalid) -- nothing stapled"
  [ ! -e "$dist/Contents/stapled" ] || fail "an Invalid submission was stapled"
  rm "$DEVBIN_TEST_TMPDIR/notary.status"
  run macos_in "$proj" app-notarize
  assert_success
  [ -e "$dist/Contents/stapled" ] || fail "an Accepted submission was not stapled: $output"
  assert_output_contains "quarantined copy accepted, source=Notarized Developer ID"
  no_secret
}

@test "publish attaches the stapled zip through release attach --from: one upload, SHA256SUMS over it, read back" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  macos_in "$proj" app-sign >/dev/null
  macos_in "$proj" app-notarize >/dev/null
  run macos_in "$proj" publish
  assert_success
  assert_output_contains "published: Demo.app.zip on release v1.0.0"
  assert_output_contains "release: attach v1.0.0: the files under"
  [ "$(gh_calls '^gh release upload .* v1.0.0 Demo.app.zip$')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
  zip="$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/Demo.app.zip"
  [ -f "$zip" ] || fail "no Demo.app.zip on the release object"
  [ "$(cat "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/SHA256SUMS")" = "$(sha256_of "$zip")  Demo.app.zip" ] ||
    fail "SHA256SUMS: $(cat "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/SHA256SUMS")"
  mkdir "$BATS_TEST_TMPDIR/unzip"
  ditto -x -k "$zip" "$BATS_TEST_TMPDIR/unzip"
  [ -e "$BATS_TEST_TMPDIR/unzip/Demo.app/Contents/stapled" ] || fail "the asset is not the stapled bundle"
  no_secret
  # Again: the core reads what is already there, and uploads nothing more.
  run macos_in "$proj" publish
  assert_success
  [ "$(gh_calls '^gh release upload')" -eq 2 ] || fail "a second publish uploaded again: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "publish refuses a copy that is not stapled, uploading nothing" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  macos_in "$proj" app-sign >/dev/null
  run macos_in "$proj" publish
  assert_failure
  assert_output_contains "is not notarised and stapled -- nothing uploaded"
  [ "$(gh_calls '^gh release upload')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

# ============================================================================
# AN APP THAT VERSIONS APART, ITS STAMPS, ITS PATHS, LAUNCH SERVICES (0243)
# ============================================================================

# The keys of an app that versions apart: its own version file, and the commit
# stamp that shows its build is the tag's.
APART_YAML=$'  version_from: app/VERSION\n  commit_stamp: AppCommit'

# stamp_app <bundle> <key> <value> -- <key> written into <bundle>'s
# Info.plist, as a build that stamps writes it.
stamp_app() { plutil -replace "$2" -string "$3" "$1/Contents/Info.plist"; }

# product <proj> -- the build product's bundle.
product() { printf '%s\n' "$1/build/Products/Release/Demo.app"; }

# tag_commit <proj> -- the commit v1.0.0 names.
tag_commit() { git -C "$1" rev-parse 'v1.0.0^{commit}'; }

# not_the_tag <proj> -- 16 hex characters that are no prefix of the tag's
# commit: its own, with the first changed.
not_the_tag() {
  local t
  t="$(tag_commit "$1")"
  printf '%s%s\n' "$([ "${t:0:1}" = 0 ] && printf 1 || printf 0)" "${t:1:15}"
}

# physical <dir> -- <dir> as Launch Services lists it.
physical() { (cd "$1" && pwd -P); }

# signed_and_stapled <proj> -- app-sign and app-notarize, each required to pass.
signed_and_stapled() {
  macos_in "$1" app-sign >/dev/null || fail "app-sign failed"
  macos_in "$1" app-notarize >/dev/null || fail "app-notarize failed"
}

@test "an app that versions apart signs, notarises and publishes under the project's tag and version, its commit stamp the tag's (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "$APART_YAML" 0.4.7)"
  stamp_app "$(product "$proj")" AppCommit "$(tag_commit "$proj")"
  run macos_in "$proj" app-sign
  assert_success
  run macos_in "$proj" app-notarize
  assert_success
  run macos_in "$proj" publish
  assert_success
  assert_output_contains "published: Demo.app.zip on release v1.0.0"
  [ "$(gh_calls '^gh release upload .* v1.0.0 Demo.app.zip$')" -eq 1 ] ||
    fail "the asset did not go to the project's release v1.0.0: $(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "a commit stamp that is not the tag's commit, or not a commit, is refused at app-sign, and at publish (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "$APART_YAML" 0.4.7)"
  local app bad tagged
  app="$(product "$proj")"
  bad="$(not_the_tag "$proj")"
  tagged="$(tag_commit "$proj")"
  stamp_app "$app" AppCommit "$bad"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "the staged Demo.app cannot ship with release v1.0.0 -- nothing signed"
  assert_output_contains "its AppCommit is $bad, and the tag v1.0.0 names ${tagged:0:12} -- it was built off the tag"
  stamp_app "$app" AppCommit not-a-commit
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "its AppCommit is not-a-commit, not a commit of 8 to 40 lowercase hex characters"
  [ "$(calls '^codesign .*--sign')" -eq 0 ] || fail "a refused copy was signed: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  # Signed and stapled with the tag's stamp, then stamped otherwise: publish
  # asks the same of the copy it would ship.
  stamp_app "$app" AppCommit "$tagged"
  signed_and_stapled "$proj"
  stamp_app "$(stage_of)" AppCommit "$bad"
  run macos_in "$proj" publish
  assert_failure
  assert_output_contains "Demo.app cannot ship with release v1.0.0 -- nothing uploaded"
  assert_output_contains "its AppCommit is $bad"
  [ "$(gh_calls '^gh release upload')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "an app that versions apart with no commit stamp declared is refused before anything is built, naming the key (0243)" {
  on_macos
  apple_stubs
  keychain_full
  # A build that leaves a mark, under tmp/, which the tree ignores: the
  # refusal must come before it runs.
  proj="$(app_project $'  version_from: app/VERSION\n  build: mkdir -p tmp/built' 0.4.7)"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "macos.version_from ($proj/app/VERSION) is not the project's version file"
  assert_output_contains "declare macos.commit_stamp"
  assert_output_contains "nothing built or signed"
  [ ! -e "$proj/tmp/built" ] || fail "macos.build ran before the refusal"
  [ -z "$(stage_of)" ] || fail "a stage was made: $(stage_of)"
  run macos_in "$proj" publish
  assert_failure
  assert_output_contains "declare macos.commit_stamp"
  assert_output_contains "nothing uploaded"
}

@test "macos.version_from naming the project's own version file, relatively, is not an app apart, so app-sign needs no commit stamp (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project '  version_from: VERSION')"
  run macos_in "$proj" app-sign
  assert_success
  refute_output_contains "is not the project's version file"
}

@test "macos.version_from and project.version_from naming the project's version file as absolute paths is not an app apart, so app-sign needs no commit stamp (0243)" {
  on_macos
  apple_stubs
  keychain_full
  local file="$DEVBIN_TEST_TMPDIR/demo/VERSION"
  proj="$(app_project "  version_from: $file" "" "  version_from: $file")"
  [ "$proj/VERSION" -ef "$file" ] || fail "the fixture's version file is not $file: $proj"
  run macos_in "$proj" app-sign
  assert_success
  refute_output_contains "is not the project's version file"
}

@test "with the tag gone from the tree, app-sign and publish refuse, naming it (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "$APART_YAML" 0.4.7)"
  stamp_app "$(product "$proj")" AppCommit "$(tag_commit "$proj")"
  signed_and_stapled "$proj"
  git -C "$proj" tag -d v1.0.0 >/dev/null
  run macos_in "$proj" publish
  assert_failure
  assert_output_contains "there is no tag v1.0.0 here"
  assert_output_contains "nothing uploaded"
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "there is no tag v1.0.0 here"
}

@test "a declared kind stamp with another value is refused at app-sign, and at publish (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project "  kind_stamp: AppKind")"
  local app
  app="$(product "$proj")"
  stamp_app "$app" AppKind debug
  run macos_in "$proj" app-sign
  assert_failure
  assert_output_contains "its AppKind is debug, not release -- it was built off the tag v1.0.0 or from a dirty tree"
  stamp_app "$app" AppKind release
  signed_and_stapled "$proj"
  stamp_app "$(stage_of)" AppKind debug
  run macos_in "$proj" publish
  assert_failure
  assert_output_contains "its AppKind is debug, not release"
  [ "$(gh_calls '^gh release upload')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "macos.kind_value without macos.kind_stamp, or empty, is refused as config, by doctor and by macos itself (0243)" {
  local name block want
  while IFS='|' read -r name block want; do
    [ -n "$name" ] || continue
    proj="$(mkproj "$name" <<YAML
project:
  name: demo
commands:
  macos:
    enabled: true
macos:
  app: build/Demo.app
  bundle_id: com.example.demo
$(printf '%b' "$block")
YAML
    )"
    run devbin_run "$proj" doctor
    assert_output_contains "$want"
    # macos refuses off macOS before it reads the config, so this half is
    # macOS's alone.
    if [ "$(uname -s)" = Darwin ]; then
      run devbin_run "$proj" macos app-sign
      assert_failure
      assert_output_contains "$want"
      assert_output_contains "macos: $proj/bin/.devbin/config.yaml does not validate (above)"
    fi
  done <<'EOF2'
alone|  kind_value: release|macos.kind_value is read only when macos.kind_stamp is declared
empty|  kind_stamp: AppKind\n  kind_value: ""|macos.kind_value is empty, so a bundle with no kind stamp would pass
EOF2
}

@test "macos.app written from the home or an XDG base directory resolves to a bundle outside the project, and any other leading tilde or variable form, or a HOME that is not absolute, is refused by name (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  local home="$DEVBIN_TEST_TMPDIR/home" state="$DEVBIN_TEST_TMPDIR/state" cfg spec xdg want
  cfg="$proj/bin/.devbin/config.yaml"
  mkdir -p "$home/apps" "$home/.local/state/apps" "$state/apps"
  make_app "$home/apps"
  make_app "$home/.local/state/apps"
  make_app "$state/apps"
  while IFS='|' read -r spec xdg want; do
    [ -n "$spec" ] || continue
    printf 'project:\n  name: demo\ncommands:\n  macos:\n    enabled: true\nmacos:\n  app: "%s"\n  bundle_id: com.example.demo\n' "$spec" >"$cfg"
    want="${want//@H@/$home}"
    want="${want//@S@/$state}"
    xdg="${xdg//@S@/$state}"
    HOME="$home" XDG_STATE_HOME="$xdg" run macos_in "$proj" doctor
    assert_output_contains "$want (present)"
  done <<'EOF2'
~/apps/Demo.app|@S@|@H@/apps/Demo.app
$HOME/apps/Demo.app|@S@|@H@/apps/Demo.app
${HOME}/apps/Demo.app|@S@|@H@/apps/Demo.app
${XDG_STATE_HOME}/apps/Demo.app|@S@|@S@/apps/Demo.app
${XDG_STATE_HOME}/apps/Demo.app|relative/state|@H@/.local/state/apps/Demo.app
$XDG_STATE_HOME/apps/Demo.app||@H@/.local/state/apps/Demo.app
EOF2
  # Each refusal names the key and what the value opens with, so nothing is
  # read as a path in the project: another variable, a fallback the XDG spec
  # already gives, a ~ naming a user, a variable that only starts with HOME,
  # and a HOME that is not absolute. The rows are literal text.
  local at
  while IFS='|' read -r spec at want; do
    [ -n "$spec" ] || continue
    printf 'project:\n  name: demo\ncommands:\n  macos:\n    enabled: true\nmacos:\n  app: "%s"\n  bundle_id: com.example.demo\n' "$spec" >"$cfg"
    HOME="${at//@H@/$home}" run macos_in "$proj" doctor
    assert_failure
    assert_output_contains "$want"
  done <<'EOF2'
$FOO/apps/Demo.app|@H@|macos.app is $FOO/apps/Demo.app, which opens with $FOO, and only ~, $HOME, $XDG_STATE_HOME, $XDG_DATA_HOME, $XDG_CONFIG_HOME and $XDG_CACHE_HOME are expanded, each written alone as $NAME or ${NAME}: an XDG variable that is unset falls back to its XDG default
${XDG_STATE_HOME:-$HOME/.local/state}/apps/Demo.app|@H@|macos.app is ${XDG_STATE_HOME:-$HOME/.local/state}/apps/Demo.app, which opens with ${XDG_STATE_HOME:-$HOME/.local/state}, and only
~user/apps/Demo.app|@H@|macos.app is ~user/apps/Demo.app, which opens with ~user, and only
$HOMEX/apps/Demo.app|@H@|macos.app is $HOMEX/apps/Demo.app, which opens with $HOMEX, and only
~/apps/Demo.app|relative/home|macos.app is ~/apps/Demo.app, and HOME (relative/home) is not an absolute path below /, so it cannot be expanded
EOF2
}

@test "each step drops the record its tools gave the staged copy on its way out, a failed step and publish too, and a record that stays is a warning naming the command, the exit standing (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  run macos_in "$proj" app-sign
  assert_success
  local dist
  dist="$(physical "$(stage_of)")"
  grep -qxF "lsregister -u $dist" "$DEVBIN_TEST_TMPDIR/apple.calls" || fail "app-sign dropped no record of $dist: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  ! grep -qxF -- "$dist" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the staged copy's record was left after app-sign"
  printf '%s' "$dist" >"$DEVBIN_TEST_TMPDIR/ls.stuck"
  run macos_in "$proj" app-notarize
  assert_success
  assert_output_contains "could not drop the Launch Services record for $dist: lsregister -u exited 0 and the record is still listed; drop it with: $APPLE/lsregister -u $dist"
  rm "$DEVBIN_TEST_TMPDIR/ls.stuck"
  # A STEP THAT FAILS DROPS IT TOO: Launch Services registered the copy again
  # on its own, and Apple refuses the submission, a die before any drop on the
  # step's success path.
  printf '%s\n' "$dist" >>"$DEVBIN_TEST_TMPDIR/ls.records"
  printf 'Invalid' >"$DEVBIN_TEST_TMPDIR/notary.status"
  run macos_in "$proj" app-notarize
  assert_failure
  assert_output_contains "notarisation was not Accepted (status: Invalid) -- nothing stapled"
  ! grep -qxF -- "$dist" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the staged copy's record was left after app-notarize failed"
  rm "$DEVBIN_TEST_TMPDIR/notary.status"
  # And publish, the last step, drops it once more.
  printf '%s\n' "$dist" >>"$DEVBIN_TEST_TMPDIR/ls.records"
  run macos_in "$proj" publish
  assert_success
  ! grep -qxF -- "$dist" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the staged copy's record was left after publish"
}

@test "a record that stays on the Gatekeeper check's copy, which is gone, fails the step that made it, and the staged copy is dropped on the way out (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  : >"$DEVBIN_TEST_TMPDIR/apple.calls"
  printf '/devbin-macos-check.' >"$DEVBIN_TEST_TMPDIR/ls.stuck"
  run macos_in "$proj" app-verify
  assert_failure
  assert_output_contains "the Gatekeeper check's copy of Demo.app was not dropped from Launch Services and removed (above)"
  local copy
  copy="$(sed -n 's/^spctl -a -t exec -vv //p' "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ -n "$copy" ] || fail "no Gatekeeper check ran: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  assert_output_contains "could not drop the Launch Services record for $copy: lsregister -u exited 0 and the record is still listed"
  [ ! -e "${copy%/Demo.app}" ] || fail "the Gatekeeper check's dir was left: ${copy%/Demo.app}"
  # stapler validate registered the staged copy, and the die that stopped
  # app-verify left the EXIT trap to drop it.
  ! grep -qxF -- "$(physical "$(stage_of)")" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the staged copy's record was left after app-verify failed"
}

@test "a TERM during the Gatekeeper check ends the step, and its copy's record and its dir go on the way out (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  : >"$DEVBIN_TEST_TMPDIR/apple.calls"
  : >"$DEVBIN_TEST_TMPDIR/spctl.signal"
  run macos_in "$proj" app-verify
  [ "$status" -eq 1 ] || fail "app-verify exited $status: $output"
  grep -qE '^term_macos signalled [0-9]+, running: .*/lib/cmd/macos app-verify; its parent runs: ' "$DEVBIN_TEST_TMPDIR/apple.calls" ||
    fail "the macos process was not the one signalled: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  ! grep -qE '; its parent runs: .*/lib/cmd/macos ' "$DEVBIN_TEST_TMPDIR/apple.calls" ||
    fail "a subshell of the macos process was signalled, not the process: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  local copy
  copy="$(sed -n 's/^spctl -a -t exec -vv //p' "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ -n "$copy" ] || fail "no Gatekeeper check ran: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  grep -qxF "lsregister -u $copy" "$DEVBIN_TEST_TMPDIR/apple.calls" || fail "the check copy's record was never dropped: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  ! grep -qxF -- "$copy" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the check copy's record was left: $(cat "$DEVBIN_TEST_TMPDIR/ls.records")"
  [ ! -e "${copy%/Demo.app}" ] || fail "the Gatekeeper check's dir was left: ${copy%/Demo.app}"
}

@test "a record that stays on publish's proof copy fails the run after the upload, saying first that the asset is published (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  printf '/unpacked/' >"$DEVBIN_TEST_TMPDIR/ls.stuck"
  run macos_in "$proj" publish
  [ "$status" -eq 1 ] || fail "publish exited $status: $output"
  assert_output_contains "published: Demo.app.zip on release v1.0.0"
  assert_output_contains "published Demo.app.zip on release v1.0.0; could not drop its proof copy's Launch Services record or remove the dir it was proven in:"
  assert_output_contains "/unpacked/Demo.app: lsregister -u exited 0 and the record is still listed"
  [ "$(gh_calls '^gh release upload .* v1.0.0 Demo.app.zip$')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "a proof dir that cannot be removed fails the run after the upload, saying first that the asset is published, and how to remove it (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  printf '/unpacked/' >"$DEVBIN_TEST_TMPDIR/ls.lockdir"
  run macos_in "$proj" publish
  [ "$status" -eq 1 ] || fail "publish exited $status: $output"
  assert_output_contains "published: Demo.app.zip on release v1.0.0"
  assert_output_contains "published Demo.app.zip on release v1.0.0; could not drop its proof copy's Launch Services record or remove the dir it was proven in:"
  local locked staging
  locked="$(cat "$DEVBIN_TEST_TMPDIR/ls.locked")"
  staging="${locked%/unpacked}"
  [ -n "$staging" ] && [ "$staging" != "$locked" ] || fail "the fake locked no proof dir: $locked"
  assert_output_contains "could not remove $staging; remove it with: rm -rf $staging"
  [ "$(gh_calls '^gh release upload .* v1.0.0 Demo.app.zip$')" -eq 1 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}

@test "a record list that cannot be read after the upload fails the run, saying first that the asset is published (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  # The list fails once the asset is on the release, so every read before the
  # upload is a good one.
  printf '%s' "$DEVBIN_TEST_TMPDIR/gh.assets/v1.0.0/Demo.app.zip" >"$DEVBIN_TEST_TMPDIR/dump.fail"
  run macos_in "$proj" publish
  [ "$status" -eq 1 ] || fail "publish exited $status: $output"
  assert_output_contains "published Demo.app.zip on release v1.0.0; could not drop"
  assert_output_contains "lsregister -dump failed (exit 1), saying lsregister: dump failed, so whether it is gone is unknown"
}

@test "a TERM during the proof copy's drop does not cut it short: its record and its dir go, the list is read back, and publish exits 0 (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  printf '/unpacked/' >"$DEVBIN_TEST_TMPDIR/ls.signal"
  run macos_in "$proj" publish
  assert_success
  assert_output_contains "published: Demo.app.zip on release v1.0.0"
  grep -qE '^term_macos signalled [0-9]+, running: .*/lib/cmd/macos publish; its parent runs: ' "$DEVBIN_TEST_TMPDIR/apple.calls" ||
    fail "the macos process was not the one signalled: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  ! grep -qE '; its parent runs: .*/lib/cmd/macos ' "$DEVBIN_TEST_TMPDIR/apple.calls" ||
    fail "a subshell of the macos process was signalled, not the process: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  awk '/^term_macos signalled/ { s = NR } /^lsregister -dump/ { d = NR } END { exit !(s && d > s) }' "$DEVBIN_TEST_TMPDIR/apple.calls" ||
    fail "the record list was not read back after the signal: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  ! grep -qF /unpacked/ "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the proof copy's record was left: $(cat "$DEVBIN_TEST_TMPDIR/ls.records")"
  local staging
  staging="$(sed -n 's#^lsregister -u \(.*\)/unpacked/Demo\.app$#\1#p' "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ -n "$staging" ] || fail "the proof copy was never dropped: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ ! -e "$staging" ] || fail "the proof copy's dir was left: $staging"
}

@test "after the upload, publish drops every record under the build root, and one that stays is a warning, the exit standing (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  signed_and_stapled "$proj"
  # The build registers its own product, as a real build can.
  local prod
  prod="$(physical "$(product "$proj")")"
  printf '%s\n' "$prod" >>"$DEVBIN_TEST_TMPDIR/ls.records"
  run macos_in "$proj" publish
  assert_success
  ! grep -qxF -- "$prod" "$DEVBIN_TEST_TMPDIR/ls.records" || fail "the product's record was left after publish"
  printf '%s\n' "$prod" >>"$DEVBIN_TEST_TMPDIR/ls.records"
  printf '/build/Products/' >"$DEVBIN_TEST_TMPDIR/ls.stuck"
  run macos_in "$proj" publish
  assert_success
  assert_output_contains "could not drop the Launch Services record for $prod: lsregister -u exited 0 and the record is still listed"
}

@test "a build root that is /, or holds the home directory or a directory installed apps live in, is refused before anything is built or uploaded (0243)" {
  on_macos
  apple_stubs
  keychain_full
  proj="$(app_project)"
  local cfg root placed why home rows checked=0
  cfg="$proj/bin/.devbin/config.yaml"
  mkdir -p "$HOME"
  home="$(physical "$HOME")"
  # root|as placed|why: every dir build_root_why refuses, each as typed.
  rows='/|/|is /, so the drop would sweep every record on this Mac
~|@HOME@|holds @HOME@, so the drop would sweep the records of the apps installed there
@T@|@T@|holds @HOME@, so the drop would sweep the records of the apps installed there
/Applications|/Applications|holds /Applications, so the drop would sweep the records of the apps installed there
~/Applications|@HOME@/Applications|holds @HOME@/Applications, so the drop would sweep the records of the apps installed there
/System|/System|holds /System/Applications, so the drop would sweep the records of the apps installed there
/System/Library/CoreServices|/System/Library/CoreServices|holds /System/Library/CoreServices, so the drop would sweep the records of the apps installed there'
  while IFS='|' read -r root placed why; do
    root="${root//@T@/$DEVBIN_TEST_TMPDIR}"
    placed="${placed//@T@/$DEVBIN_TEST_TMPDIR}"
    placed="${placed//@HOME@/$home}"
    why="${why//@HOME@/$home}"
    printf 'project:\n  name: demo\ncommands:\n  release:\n    enabled: true\n  macos:\n    enabled: true\nmacos:\n  app: build/Products/Release/Demo.app\n  bundle_id: com.example.demo\n  build: mkdir -p tmp/built\n  build_root: "%s"\n' "$root" >"$cfg"
    run macos_in "$proj" app-sign </dev/null
    assert_failure
    [ ! -e "$proj/tmp/built" ] || fail "macos.build ran before the refusal of $root"
    assert_output_contains "publish's last Launch Services drop would sweep $placed (macos.build_root, else the directory holding macos.app), which $why -- declare macos.build_root as the directory the build writes its products under; nothing built or signed"
    run macos_in "$proj" publish </dev/null
    assert_failure
    assert_output_contains "publish's last Launch Services drop would sweep $placed"
    assert_output_contains "nothing uploaded"
    checked=$((checked + 1))
  done <<<"$rows"
  [ "$checked" -eq "$(grep -c "|" <<<"$rows")" ] || fail "checked $checked of the table's roots"
  [ -z "$(stage_of)" ] || fail "a stage was made: $(stage_of)"
  [ "$(calls '^codesign .*--sign')" -eq 0 ] || fail "something was signed: $(cat "$DEVBIN_TEST_TMPDIR/apple.calls")"
  [ "$(gh_calls '^gh release upload')" -eq 0 ] || fail "$(cat "$DEVBIN_TEST_TMPDIR/gh.calls")"
}
