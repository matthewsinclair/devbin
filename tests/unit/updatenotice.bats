#!/usr/bin/env bats
# updatenotice.bats - the vendored runtime telling a consumer it has moved on
#
# The notice is its guards and one comparison, and THE GUARDS ARE THE FEATURE
# that keep it from CI logs, from sealed gate output, and from a consumer without
# devbin's source on disk: a notice that reached any of those would be worse than
# no notice at all, so those are what is asserted hardest here.
#
# THE FIRING PATH NEEDS A TERMINAL ON FD 2, and bats captures stderr into a
# pipe, so it cannot be reached by an ordinary test. It is reached here through
# `run_tty_eof`, which allocates a pty and makes it the child's controlling
# terminal; `require_pty` skips those tests visibly on a runner with no
# `script(1)` rather than leaving them quietly absent.
#
# THAT PARAGRAPH USED TO PROMISE THIS AND NO SUCH TEST EXISTED (issue 0040).
# Every test asserted SILENCE, so every guard was covered and the arm
# they guard was not, while the comment told a reader the gap declared itself.
# A comment asserting coverage that does not exist is worse than saying nothing:
# it converts an open question into a settled one. Do not let it drift back --
# the terminal tests below are what make it true.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  init_colors off
}
teardown() { devbin_teardown; }

# A fake devbin source: a git repo with one commit, so it has a real HEAD.
mksource() {
  local dir="$DEVBIN_TEST_TMPDIR/fakesource"
  mkdir -p "$dir"
  git -C "$dir" init -q 2>/dev/null
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  : >"$dir/marker"
  git -C "$dir" add -A
  git -C "$dir" commit -qm one
  echo "$dir"
}

# mkforward -- a consumer vendored at a git source's FIRST commit, with the source
# one commit further on: REALLY behind, which is the one case that may be called
# an update (issue 0079). A made-up sha is not behind anything: nothing can place
# it, so it reads as a difference of unknown direction.
mkforward() {
  local src
  src="$(mksource)"
  mkconsumer "$src" "$(git -C "$src" rev-parse HEAD)" >/dev/null || return 1
  git -C "$src" commit -q --allow-empty -m two || return 1
  printf '%s\n' "$DEVBIN_TEST_TMPDIR/consumer"
}

# mkahead -- the mirror: a consumer vendored at the source's SECOND commit, with
# the source rewound to its first. Upgrading from it would revert the runtime.
mkahead() {
  local src first
  src="$(mksource)"
  first="$(git -C "$src" rev-parse HEAD)" || return 1
  git -C "$src" commit -q --allow-empty -m two || return 1
  mkconsumer "$src" "$(git -C "$src" rev-parse HEAD)" >/dev/null || return 1
  git -C "$src" reset -q --hard "$first" || return 1
  printf '%s\n' "$DEVBIN_TEST_TMPDIR/consumer"
}

# A consumer tree carrying a manifest that names <source> at <commit>.
mkconsumer() {
  local src="$1" commit="$2" dir="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$dir/bin/.devbin"
  cat >"$dir/bin/.devbin/manifest.sha256" <<EOF
# devbin manifest -- written by: devbin install.
# devbin_version: 0.1.0
# source: $src
# source_commit: $commit
deadbeef  bin/devbin
EOF
  echo "$dir"
}

# ---------------------------------------------------------------------------
# The manifest readers, which MOVED to lib/helpers -- regression on the move
# ---------------------------------------------------------------------------

@test "manifest_source and manifest_source_commit still read after the move to helpers" {
  src="$(mksource)"
  consumer="$(mkconsumer "$src" abc123)"
  run manifest_source "$consumer"
  assert_success
  assert_output "$src"
  run manifest_source_commit "$consumer"
  assert_success
  assert_output "abc123"
}

@test "lib/install no longer carries its own copy of the manifest readers" {
  # The move is only worth anything if the original did not stay behind. Two
  # readers of one header format is the drift this project names first.
  run grep -c '^manifest_field()' "$DEVBIN_LIB_DIR/install"
  assert_output "0"
  run grep -c '^manifest_field()' "$DEVBIN_LIB_DIR/helpers"
  assert_output "1"
}

# ---------------------------------------------------------------------------
# The guards -- each asserted as SILENCE, which is what they are for
# ---------------------------------------------------------------------------

@test "NOT A TERMINAL is silence, even when the source has genuinely moved on" {
  # THE LOAD-BEARING GUARD. devbin seals gate output with 2>&1 into a run log
  # that the extraction grammars parse, and CI logs are not a terminal either.
  # A notice that fired here would be issue 0025's class: devbin's own chatter
  # becoming input to a verdict.
  consumer="$(mkforward)"
  run devbin_update_notice "$consumer"
  assert_success
  assert_output ""
}

@test "the kill switch silences it" {
  consumer="$(mkforward)"
  DEVBIN_NO_UPDATE_NOTICE=1 run devbin_update_notice "$consumer"
  assert_success
  assert_output ""
}

@test "an absent source tree is silence, not an error -- the ordinary consumer case" {
  consumer="$(mkconsumer "$DEVBIN_TEST_TMPDIR/does-not-exist" abc123)"
  run devbin_update_notice "$consumer"
  assert_success
  assert_output ""
}

@test "a project with no manifest at all is silence, not an error" {
  mkdir -p "$DEVBIN_TEST_TMPDIR/bare"
  run devbin_update_notice "$DEVBIN_TEST_TMPDIR/bare"
  assert_success
  assert_output ""
}

@test "no argument is silence, not an unbound-variable abort" {
  run devbin_update_notice
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# The comparison, tested directly -- no terminal required
# ---------------------------------------------------------------------------

@test "a DIRTY record at the source's own commit says NOTHING -- the field is not a bare sha" {
  # Since 0079 the notice is silent here because the state is `unknown`; the arm
  # that holds the STATE to not-level is the 0079 one below.
  src="$(mksource)"
  head="$(git -C "$src" rev-parse HEAD)"
  # source_commit_of stamps `<sha> +dirty -- THESE BYTES MATCH NO COMMIT` when
  # devbin's own half is uncommitted, which is the ordinary state of a tree
  # someone is working in. Compared whole against `git rev-parse HEAD` that can
  # never match, so the notice fired on every invocation and `upgrade` could not
  # clear it -- it rewrites the same dirty stamp. Measured in a consumer.
  consumer="$(mkconsumer "$src" "$head +dirty -- THESE BYTES MATCH NO COMMIT")"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output ""
}

@test "a DIRTY record whose commit the source has moved past still SPEAKS, but never as an update" {
  # 0079: `+dirty` bytes are not the commit they started from, so no direction
  # follows from the sha -- source_direction says `unknown`, and this said
  # UPDATE. The difference is still reported; the upgrade is not offered.
  consumer="$(mkforward)"
  src="$(manifest_source "$consumer")"
  first="$(git -C "$src" rev-parse HEAD~1)"
  mkconsumer "$src" "$first +dirty -- THESE BYTES MATCH NO COMMIT" >/dev/null
  run _devbin_update_line "$consumer"
  assert_success
  assert_output_contains "vendored ${first:0:12}"
  refute_output_contains "UPDATE: devbin has moved on"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "a clean source at the SAME commit says nothing -- the negative control" {
  src="$(mksource)"
  head="$(git -C "$src" rev-parse HEAD)"
  consumer="$(mkconsumer "$src" "$head")"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output ""
}

@test "a record that names NO commit at all says nothing" {
  # An older devbin, or a source that is not a checkout. Bytes that name no
  # commit cannot be said to have fallen behind one.
  src="$(mksource)"
  consumer="$(mkconsumer "$src" "not a git checkout -- these bytes name no commit")"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output ""
}

@test "the remediation names a command that EXISTS" {
  # `<name> devbin upgrade` is not a command: `devbin` is its own builtin, about
  # devbin itself, answering `usage: <name> devbin [templates|--version]`. The
  # upgrade verb is top level. Measured in a consumer, where the printed
  # remediation did nothing at all.
  consumer="$(mkforward)"
  DEVBIN_NAME=webapp run _devbin_update_line "$consumer"
  # First it said `webapp devbin upgrade`, which is a different builtin and
  # does nothing. Then `webapp upgrade`, which was right for one afternoon.
  # The launcher convention retired the per-project name entirely, so the
  # remediation is the invocation -- correct in every project, and it no longer
  # depends on what the project happens to be called.
  assert_output_contains "run: bin/devbin upgrade"
  refute_output_contains "webapp upgrade"
  refute_output_contains "devbin devbin upgrade"
}

@test "the notice body carries no trailing prompt and both shas differ when shown" {
  consumer="$(mkforward)"
  src="$(manifest_source "$consumer")"
  head="$(git -C "$src" rev-parse HEAD)"
  first="$(git -C "$src" rev-parse HEAD~1)"
  run _devbin_update_line "$consumer"
  assert_output_contains "vendored ${first:0:12}, source now ${head:0:12}"
}

# ---------------------------------------------------------------------------
# THE FIRING PATH. Everything above this line asserts the notice stays SILENT.
# These are the only tests that watch it SPEAK, and they need a real terminal.
# ---------------------------------------------------------------------------

# notice_on_a_tty <consumer> [env...] -- run devbin_update_notice with fd 2 on a
# real pty, so `[ -t 2 ]` passes the way it does for a human at a prompt.
#
# TMPDIR is redirected into the test tmpdir because the once-a-day stamp lives
# there. Without it the stamp is written into the developer's real TMPDIR, keyed
# on the fixture path -- so these tests would pass once and then go silent for a
# day, which is a suite that reports differently on its second run.
notice_on_a_tty() {
  local consumer="$1"
  shift
  run_tty_eof env \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" \
    TMPDIR="$DEVBIN_TEST_TMPDIR" \
    CONSUMER="$consumer" \
    "$@" \
    bash -c '. "$DEVBIN_LIB/helpers"; devbin_update_notice "$CONSUMER"'
}

@test "ON A TERMINAL the notice actually SPEAKS -- the arm no other test reaches" {
  require_pty
  consumer="$(mkforward)"
  run notice_on_a_tty "$consumer"
  assert_success
  assert_output_contains "UPDATE: devbin has moved on"
  assert_output_contains "run: bin/devbin upgrade"
}

@test "the terminal is what changed, not the fixture -- the same case is SILENT without one" {
  # THE CONTROL FOR THE TEST ABOVE. Without it, a pty that somehow made every
  # command print would satisfy the firing test and mean nothing. Same source,
  # same consumer, same function -- only the terminal removed.
  require_pty
  consumer="$(mkforward)"
  run devbin_update_notice "$consumer"
  assert_success
  assert_output ""
}

@test "the kill switch silences it EVEN ON A TERMINAL" {
  # The existing kill-switch test runs where `[ -t 2 ]` already fails, so it
  # cannot tell a working switch from the terminal guard doing the work. This
  # one can: the terminal guard is satisfied and the switch is the only thing
  # left standing between the fixture and the message.
  require_pty
  consumer="$(mkforward)"
  run notice_on_a_tty "$consumer" DEVBIN_NO_UPDATE_NOTICE=1
  assert_success
  refute_output_contains "UPDATE: devbin has moved on"
}

@test "ONCE A DAY: the second call on the same terminal is silent" {
  # The rate limit is the one guard whose failure is invisible in every other
  # test here, because a suite that never reaches the firing path never writes
  # a stamp either.
  require_pty
  consumer="$(mkforward)"

  run notice_on_a_tty "$consumer"
  assert_output_contains "UPDATE: devbin has moved on"

  run notice_on_a_tty "$consumer"
  assert_success
  refute_output_contains "UPDATE: devbin has moved on"
}

# ---------------------------------------------------------------------------
# THE SOURCE CAN NOW BE AN INSTALL, WHICH IS NOT A GIT CHECKOUT (ST0005)
# ---------------------------------------------------------------------------

# mkinstall <commit> [<sha> <direction>]... -- a source shaped like the machine
# install: no .git at all, and its own manifest declaring `kind: install`, the
# commit it holds, and the ancestry table a publish writes (issue 0059) placing
# each earlier commit against that one.
mkinstall() {
  local commit="$1" dir="$DEVBIN_TEST_TMPDIR/fakeinstall"
  shift
  mkdir -p "$dir/bin/.devbin"
  {
    printf '# devbin manifest -- written by: devbin install.\n'
    printf '# devbin_version: 0.1.0\n# kind: install\n# source: /somewhere/else\n'
    printf '# source_commit: %s\n' "$commit"
    while [ "$#" -ge 2 ]; do
      printf '# ancestry: %s %s\n' "$1" "$2"
      shift 2
    done
    printf 'deadbeef  bin/devbin\n'
  } >"$dir/bin/.devbin/manifest.sha256"
  printf '%s\n' "$dir"
}

# AT-2.1
@test "an INSTALL source that has moved on still speaks -- it has no git to ask" {
  # THE REGRESSION ST0005 WOULD OTHERWISE HAVE SHIPPED, measured before it did.
  # This function asked `git -C "$src" rev-parse HEAD`, which is right for a dev
  # tree and returns NOTHING for an install. So the notice went silent for every
  # consumer the moment consumers were repointed at the install -- which is the
  # entire job of WP-03 -- and silently, because silence is this notice's
  # ordinary state. Same consumer, same staleness, one field changed.
  src="$(mkinstall 1111111111111111111111111111111111111111 0000000000000000000000000000000000000000 forward)"
  consumer="$(mkconsumer "$src" 0000000000000000000000000000000000000000)"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output_contains "UPDATE: devbin has moved on"
  assert_output_contains "000000000000"
  assert_output_contains "111111111111"
}

# AT-2.1
@test "an INSTALL source at the SAME commit says nothing -- the negative control" {
  # Without this, a change that made the notice fire unconditionally against an
  # install would satisfy the arm above.
  src="$(mkinstall 1111111111111111111111111111111111111111)"
  consumer="$(mkconsumer "$src" 1111111111111111111111111111111111111111)"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output ""
}

# AT-2.1
@test "an install whose own manifest names no commit is silence, not a false alarm" {
  src="$(mkinstall 'not a git checkout -- these bytes name no commit')"
  consumer="$(mkconsumer "$src" 0000000000000000000000000000000000000000)"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output ""
}

# --- devbin_source_state: level and cannot-tell never collapse --------------

# AT-2.4
@test "devbin_source_state separates LEVEL from CANNOT-TELL, which the notice cannot" {
  # The notice is quiet for both, correctly -- it asserts nothing. A CHECK must
  # not collapse them: absent is not clean.
  src="$(mkinstall 1111111111111111111111111111111111111111)"

  consumer="$(mkconsumer "$src" 1111111111111111111111111111111111111111)"
  run devbin_source_state "$consumer"
  assert_output "level"

  src="$(mkinstall 1111111111111111111111111111111111111111 0000000000000000000000000000000000000000 forward)"
  consumer="$(mkconsumer "$src" 0000000000000000000000000000000000000000)"
  run devbin_source_state "$consumer"
  assert_output_contains "behind 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111"

  consumer="$(mkconsumer /no/such/source 0000000000000000000000000000000000000000)"
  run devbin_source_state "$consumer"
  assert_output_contains "unknown"
  assert_output_contains "not on this machine"
}

# AT-2.4
@test "devbin_source_state never answers LEVEL when it could not look" {
  # The one thing this function must never do. Every unknown path is checked
  # against the word that would be a false green.
  for c in "" "/no/such/root"; do
    run devbin_source_state "$c"
    refute_output_contains "level"
  done
  consumer="$(mkconsumer "" 0000000000000000000000000000000000000000)"
  run devbin_source_state "$consumer"
  refute_output_contains "level"
}

# --- the DIRECTION, not just the difference (issue 0079) ---------------------
#
# The notice, the offer and doctor called ANY difference "behind". So a source
# BEHIND the project -- a rewound install, a checkout on an older branch -- was
# announced as an update, and the offer's yes reverted the runtime (issue 0021's
# silent revert, measured at 11 files). Every reader now asks source_direction,
# the one answer upgrade and vendor already use, and only `forward` is behind.
#
# setup() sources lib/helpers ALONE, as the dispatcher does before it offers, so
# every arm here also proves the direction reader is reachable without
# lib/install.

@test "0079: a consumer AHEAD of a rewound git source reads ahead, not behind" {
  consumer="$(mkahead)"
  src="$(manifest_source "$consumer")"
  rec="$(manifest_source_commit "$consumer")"
  [ "$rec" != "$(git -C "$src" rev-parse HEAD)" ] || fail "the fixture is not ahead"
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_source_state "$consumer"
  assert_success
  assert_output "ahead $rec $head"
}

@test "0079: the notice says the source is BEHIND this project, and never names upgrade" {
  consumer="$(mkahead)"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output_contains "BEHIND this project"
  assert_output_contains "run: bin/devbin vendor"
  refute_output_contains "UPDATE: devbin has moved on"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "0079: a consumer AHEAD of an install reads ahead through the install's table" {
  src="$(mkinstall 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 backward)"
  consumer="$(mkconsumer "$src" 2222222222222222222222222222222222222222)"
  run devbin_source_state "$consumer"
  assert_output "ahead 2222222222222222222222222222222222222222 1111111111111111111111111111111111111111"
  run _devbin_update_line "$consumer"
  assert_output_contains "BEHIND this project"
  refute_output_contains "UPDATE:"
}

@test "0079: a commit the install never held DIFFERS, and is never called an update" {
  # NOT FOUND IS UNKNOWN (install_direction). The shas differ, so the difference
  # is reported -- silence would hide a real divergence -- but nothing vouches
  # that the source is newer.
  src="$(mkinstall 1111111111111111111111111111111111111111)"
  consumer="$(mkconsumer "$src" 0000000000000000000000000000000000000000)"
  run devbin_source_state "$consumer"
  assert_output_contains "differs 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111"
  run _devbin_update_line "$consumer"
  assert_success
  assert_output_contains "vendored 000000000000, source now 111111111111"
  assert_output_contains "run: bin/devbin vendor"
  refute_output_contains "UPDATE:"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "0079: a source on a DIFFERENT history differs, and says so" {
  src="$(mksource)"
  main="$(git -C "$src" symbolic-ref --short HEAD)"
  git -C "$src" checkout -q --orphan other
  git -C "$src" commit -q --allow-empty -m elsewhere
  other="$(git -C "$src" rev-parse HEAD)"
  git -C "$src" checkout -q "$main"
  consumer="$(mkconsumer "$src" "$other")"
  run devbin_source_state "$consumer"
  assert_output_contains "differs $other"
  assert_output_contains "different history"
  run _devbin_update_line "$consumer"
  refute_output_contains "UPDATE:"
}

@test "0079: a DIRTY record at the source's own commit is never LEVEL" {
  # It was: the sha was stripped of ` +dirty` and compared, so bytes vendored
  # from uncommitted work on C read level against a source holding C.
  src="$(mksource)"
  head="$(git -C "$src" rev-parse HEAD)"
  consumer="$(mkconsumer "$src" "$head +dirty -- THESE BYTES MATCH NO COMMIT")"
  run devbin_source_state "$consumer"
  refute_output_contains "level"
  assert_output_contains "unknown"
}

@test "0079: a record too short to name a commit is unknown, not behind" {
  # `a checkout with no HEAD` reduces to `a` by first word, and `a` is hex. The
  # copies of the sha check here had no length test; is_commit_sha does.
  src="$(mksource)"
  consumer="$(mkconsumer "$src" abc12)"
  run devbin_source_state "$consumer"
  assert_output_contains "unknown"
  refute_output_contains "behind"
}

# EXACT MATCHES ONLY (install_direction). is_commit_sha admits any seven hex
# characters, so a hand-shortened record reaches the install's comparisons, and
# a prefix match there would read it as a commit it does not name. A prefix match
# survived every arm above; the PREFIX arms below are what hold the claim.

@test "0079: a record that is a PREFIX of the install's commit is never level" {
  src="$(mkinstall 1111111111111111111111111111111111111111)"
  consumer="$(mkconsumer "$src" 111111111111)"
  run devbin_source_state "$consumer"
  refute_output_contains "level"
  assert_output_contains "differs 111111111111 1111111111111111111111111111111111111111"
}

@test "0079: a record that is a PREFIX of a row in the install's table takes no direction from it" {
  src="$(mkinstall 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 backward)"
  consumer="$(mkconsumer "$src" 222222222222)"
  run devbin_source_state "$consumer"
  refute_output_contains "ahead"
  assert_output_contains "differs 222222222222 1111111111111111111111111111111111111111"
}

@test "0079: one sha check and one direction reader, across lib/, bin/devbin and bin/.devbin/cmd" {
  # Every root a copy could hide in, as 0066's vocabulary test searches. A
  # definition in either spelling, the charset test (a whole sha's regex too,
  # since is_commit_sha's full form answers that, ST0011), and the ancestry
  # question itself are each held to their one home.
  local f roots hits
  roots=("$DEVBIN_LIB_DIR" "$DEVBIN_HOME/bin/devbin" "$DEVBIN_HOME/bin/.devbin/cmd")
  for f in is_commit_sha source_direction commit_direction install_direction manifest_ancestry; do
    hits="$(grep -rlE "^(function +)?$f *(\(\))? *(\{|$)" "${roots[@]}" | sort -u)"
    [ "$hits" = "$DEVBIN_LIB_DIR/helpers" ] || fail "$f defined in: [${hits//$'\n'/ }]"
  done
  hits="$(grep -rn -e '\[!0-9a-f\]' -e '\[\[:xdigit:\]\]' -e '\[0-9a-f\]{7' -e '\[0-9a-f\]{40' "${roots[@]}")"
  [ "$(printf '%s\n' "$hits" | grep -c .)" = 1 ] || fail "sha checks: $hits"
  case "$hits" in "$DEVBIN_LIB_DIR/helpers:"*) ;; *) fail "the sha check is not in lib/helpers: $hits" ;; esac
  hits="$(grep -rn 'merge-base --is-ancestor' "${roots[@]}" | grep -v '^[^:]*:[0-9]*: *#')"
  [ "$(printf '%s\n' "$hits" | cut -d: -f1 | sort -u)" = "$DEVBIN_LIB_DIR/helpers" ] ||
    fail "ancestry asked outside lib/helpers: $hits"
}

# ---------------------------------------------------------------------------
# 0224: A FORWARD MOVE THAT CHANGES NO VENDORED BYTE IS NOT AN UPDATE
#
# source_direction compares commits, so a devbin commit that touched only
# coordination state (a board event, an issue) read `behind`, and every project
# linked to the checkout was told to upgrade for no change to any file it
# vendored. The byte answer is seam_is_level's (lib/install), the one upgrade
# already asks on its backward and unrelated arms (issue 0053).
# ---------------------------------------------------------------------------

# mkvendored -- a project installed from a real devbin checkout, which the
# switch names, as `devbin use dev` leaves it.
mkvendored() {
  local src proj="$DEVBIN_TEST_TMPDIR/vendored"
  src="$(mkdevsrc)"
  mkdir -p "$proj"
  devbin_run "$src" install --into "$proj" --name vendored >/dev/null 2>&1 || return 1
  switch_to "$src" || return 1
  [ "$(manifest_source "$proj")" = "$src" ] || return 1
  printf '%s\n' "$proj"
}

# commit_outside <src> -- a commit that moves the checkout and no vendored byte.
commit_outside() {
  mkdir -p "$1/intent/whiteboard"
  printf 'heartbeat\n' >>"$1/intent/whiteboard/board.json"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "board only" >/dev/null 2>&1
}

@test "0224: a source moved on only outside the seam is not an update: the notice is quiet and doctor names no upgrade" {
  local proj src rec head
  proj="$(mkvendored)" || fail "the fixture did not build"
  src="$(manifest_source "$proj")"
  rec="$(manifest_source_commit "$proj")"
  commit_outside "$src"
  head="$(git -C "$src" rev-parse HEAD)"
  [ "$rec" != "$head" ] || fail "the fixture did not move the source"
  run devbin_source_state "$proj"
  assert_success
  assert_output "moved $rec $head"
  run _devbin_update_line "$proj"
  assert_success
  assert_output ""
  run devbin_run "$proj" doctor
  assert_output_contains "source: every vendored file is level with the devbin it came from"
  assert_output_contains "its commit has moved on outside them: vendored ${rec:0:12}, source now ${head:0:12}"
  refute_output_contains "has moved on since"
  refute_output_contains "the devbin this project came from has moved on"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "0224: a source moved on inside the seam is still an update, in the notice and in doctor" {
  local proj src rec head
  proj="$(mkvendored)" || fail "the fixture did not build"
  src="$(manifest_source "$proj")"
  rec="$(manifest_source_commit "$proj")"
  commit_outside "$src"
  commit_seam "$src" "a vendored byte"
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_source_state "$proj"
  assert_success
  assert_output "behind $rec $head"
  run _devbin_update_line "$proj"
  assert_output_contains "UPDATE: devbin has moved on since this project vendored it."
  assert_output_contains "run: bin/devbin upgrade"
  run devbin_run "$proj" doctor
  assert_output_contains "source: the devbin this project came from has moved on"
  assert_output_contains "run: bin/devbin upgrade"
}

@test "0224: when the bytes cannot be compared, a forward move is still an update" {
  local proj src rec head
  proj="$(mkvendored)" || fail "the fixture did not build"
  src="$(manifest_source "$proj")"
  rec="$(manifest_source_commit "$proj")"
  commit_outside "$src"
  head="$(git -C "$src" rev-parse HEAD)"
  make_unreadable "$proj/bin/.devbin/lib/helpers"
  run devbin_source_state "$proj"
  assert_success
  assert_output "behind $rec $head"
}
