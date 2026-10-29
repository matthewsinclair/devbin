#!/usr/bin/env bats
# upgradeoffer.bats -- the interactive "upgrade now?" offer, and where it MUST NOT appear
#
# THE NOTICE AND THE OFFER ARE DIFFERENT THINGS AND THIS FILE IS ABOUT THE
# SECOND. `devbin_update_notice` (updatenotice.bats) prints one line to stderr,
# once a day, on a terminal, and asks nothing. This asks a question and can
# rewrite the consumer's working tree, so it carries a heavier guard.
#
# THE ARM THAT MATTERS MOST IS THE ONE ASSERTING SILENCE. A prompt that can
# precede a gate is issue 0058 wearing a friendlier face -- that issue cost a
# 6m30s hang because a check blocked on the operator's terminal.
# `devbin test all` typed at a real terminal reaches the dispatcher with stderr
# still a terminal, so a tty test alone does NOT keep the offer away from gates.
# The offer is therefore scoped to invocations that are never gates by
# construction -- the bare form and `doctor` -- and the negative arm below is
# what stops that scoping being quietly widened later.
#
# ST0005 WP-02, AC-2.2 and AC-2.3.

load "../lib/test_helper"

setup() {
  devbin_setup
  PREFIX="$DEVBIN_TEST_TMPDIR/opt/devbin"
}
teardown() { devbin_teardown; }

# mkbehind_install -- a consumer of a real install that the install has since moved PAST.
#
# A REAL PUBLISH HISTORY, NOT A MADE-UP SHA (issue 0079). This recorded
# `0000...` against the install, and the offer fired because any difference was
# "behind". A sha the install never held is not behind anything -- nothing can
# place it -- so once the offer asks which way the source moved, only a consumer
# the install's ancestry table places as `forward` is offered.
mkbehind_install() {
  local src consumer
  src="$(mkdevsrc)"
  devbin_run "$src" install >/dev/null 2>&1 || return 1
  consumer="$(consumer_of_install "$src")" || return 1
  commit_seam "$src" second || return 1
  devbin_run "$src" install --force >/dev/null 2>&1 || return 1
  printf '%s\n' "$consumer"
}

# mkahead_install -- the mirror: the consumer took the install's second commit, and the
# install was then published again from a checkout rewound to its first. An
# upgrade from it reverts the runtime.
mkahead_install() {
  local src consumer first
  src="$(mkdevsrc)"
  first="$(git -C "$src" rev-parse HEAD)" || return 1
  devbin_run "$src" install >/dev/null 2>&1 || return 1
  commit_seam "$src" second || return 1
  devbin_run "$src" install --force >/dev/null 2>&1 || return 1
  consumer="$(consumer_of_install "$src")" || return 1
  git -C "$src" reset -q --hard "$first" || return 1
  devbin_run "$src" install --force >/dev/null 2>&1 || return 1
  printf '%s\n' "$consumer"
}

# Run a devbin command in <proj> with a controlling pty, TMPDIR redirected so
# the notice's once-a-day stamp cannot leak into the developer's real TMPDIR.
on_a_tty() {
  local proj="$1"
  shift
  run_tty_eof env TMPDIR="$DEVBIN_TEST_TMPDIR" \
    bash -c 'cd "$1" && shift && ./bin/devbin "$@"' _ "$proj" "$@"
}

answer_on_a_tty() {
  local ans="$1" proj="$2"
  shift 2
  run_tty_answer "$ans" env TMPDIR="$DEVBIN_TEST_TMPDIR" \
    bash -c 'cd "$1" && shift && ./bin/devbin "$@"' _ "$proj" "$@"
}

# --- it appears where it should ---------------------------------------------

# AT-2.2
@test "ON A TERMINAL the bare invocation OFFERS the upgrade" {
  require_pty
  consumer="$(mkbehind_install)"
  run on_a_tty "$consumer"
  assert_output_contains "An update to devbin is available"
  assert_output_contains "Upgrade now?"
}

# AT-2.2
@test "doctor offers it too -- it reports the state, so it may offer the fix" {
  require_pty
  consumer="$(mkbehind_install)"
  run on_a_tty "$consumer" doctor
  assert_output_contains "Upgrade now?"
}

# AT-2.2
@test "WITHOUT a terminal the same case is silent -- the terminal is what changed" {
  # The control. Without it, a fixture that somehow printed everywhere would
  # satisfy the arms above and mean nothing.
  consumer="$(mkbehind_install)"
  run devbin_run "$consumer"
  refute_output_contains "Upgrade now?"
  refute_output_contains "An update to devbin is available"
}

# AT-2.2
@test "a project that is LEVEL is not asked, even on a terminal" {
  require_pty
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  consumer="$DEVBIN_TEST_TMPDIR/level"
  mkdir -p "$consumer"
  run devbin_run "$src" install --into "$consumer" --name levelproj
  assert_success
  run devbin_run "$consumer" upgrade --from "$PREFIX"
  assert_success
  run on_a_tty "$consumer"
  refute_output_contains "Upgrade now?"
}

# AT-2.2
@test "the kill switch silences the offer EVEN ON A TERMINAL" {
  require_pty
  consumer="$(mkbehind_install)"
  run run_tty_eof env TMPDIR="$DEVBIN_TEST_TMPDIR" DEVBIN_NO_UPDATE_NOTICE=1 \
    bash -c 'cd "$1" && ./bin/devbin' _ "$consumer"
  refute_output_contains "Upgrade now?"
}

# --- where it must NEVER appear ---------------------------------------------

# AT-2.3
@test "a GATE command is never offered an upgrade, terminal or not" {
  # THE ARM THIS FILE EXISTS FOR. `devbin test` at a real terminal reaches the
  # dispatcher with stderr a terminal and stdin a terminal, so every tty guard
  # in the offer PASSES here. The only thing keeping the prompt away is that the
  # command is not in the offered set -- and this is what fails if someone
  # widens that set to "every command".
  require_pty
  consumer="$(mkbehind_install)"
  run on_a_tty "$consumer" test
  refute_output_contains "Upgrade now?"
  refute_output_contains "An update to devbin is available"
}

# AT-2.3
@test "and neither is check, fmt or clean" {
  require_pty
  consumer="$(mkbehind_install)"
  for verb in check fmt clean; do
    run on_a_tty "$consumer" "$verb"
    refute_output_contains "Upgrade now?"
  done
}

# --- answering it -----------------------------------------------------------

# AT-2.2
@test "declining leaves the tree ALONE and says how to do it later" {
  require_pty
  require_expect
  consumer="$(mkbehind_install)"
  before="$(sed -n 's/^# source_commit: //p' "$consumer/bin/.devbin/manifest.sha256")"
  run answer_on_a_tty n "$consumer"
  assert_output_contains "Left as it is"
  after="$(sed -n 's/^# source_commit: //p' "$consumer/bin/.devbin/manifest.sha256")"
  [ "$before" = "$after" ]
}

# AT-2.2
@test "answering yes actually UPGRADES -- the branch EOF can never reach" {
  require_expect
  # run_tty_eof declines by construction, so every arm above proves only that
  # the question was asked and that declining is safe. A yes branch wired to
  # nothing would pass all of them.
  require_pty
  consumer="$(mkbehind_install)"
  before="$(header_of "$consumer" source_commit)"
  installed="$(header_of "$PREFIX" source_commit)"
  run answer_on_a_tty y "$consumer"
  after="$(header_of "$consumer" source_commit)"
  [ "$after" = "$installed" ]
  [ "$after" != "$before" ]
}

@test "Yes UPGRADES as y does: one answer set for every question devbin asks (0134)" {
  # The offer took y, Y, yes and YES, and the other questions y or Y. Every
  # question now takes y or yes in any case (is_yes_answer); Yes is a case the
  # offer's own list refused, so it is the answer that tells the two apart.
  require_expect
  require_pty
  consumer="$(mkbehind_install)"
  before="$(header_of "$consumer" source_commit)"
  installed="$(header_of "$PREFIX" source_commit)"
  run answer_on_a_tty Yes "$consumer"
  refute_output_contains "Left as it is"
  after="$(header_of "$consumer" source_commit)"
  [ "$after" = "$installed" ] || fail "a Yes answer did not upgrade:
$output"
  [ "$after" != "$before" ]
}

# --- the offer never re-enters itself ---------------------------------------

# AT-2.3
@test "a devbin launched BY the offer does not offer again" {
  # FOUND BY MUTATION, not by reading. The yes branch runs `bin/devbin upgrade`,
  # and while that upgrade runs the project is STILL behind -- so a second offer
  # is made, launching a third upgrade. Widening the offer to every command
  # turned this into a live recursion that HUNG the suite rather than failing an
  # assertion, which is the worst way for a defect to present.
  #
  # The command scoping prevents it today only because `upgrade` is not in the
  # offered set. That is incidental, so the sentinel is what this asserts.
  require_pty
  consumer="$(mkbehind_install)"
  run run_tty_eof env TMPDIR="$DEVBIN_TEST_TMPDIR" DEVBIN_OFFER_IN_PROGRESS=1 \
    bash -c 'cd "$1" && ./bin/devbin' _ "$consumer"
  refute_output_contains "Upgrade now?"
}

# AT-2.3
@test "and WITHOUT the sentinel the same invocation IS offered -- the control" {
  # Without this, a guard that silenced the offer unconditionally would satisfy
  # the arm above and mean nothing.
  require_pty
  consumer="$(mkbehind_install)"
  run run_tty_eof env TMPDIR="$DEVBIN_TEST_TMPDIR" \
    bash -c 'cd "$1" && ./bin/devbin' _ "$consumer"
  assert_output_contains "Upgrade now?"
}

# --- only FORWARD is an update (issue 0079) ---------------------------------
#
# The offer read any difference as "behind", so a consumer AHEAD of a rewound
# install was told "An update to devbin is available", and a yes ran the
# upgrade that reverts it. upgrade's own BEHIND warning (0059) came too late:
# the person had already chosen.

# THE FIXTURE CONTROLS. Without them, a fixture that failed to build its history
# would make the silence arms below pass for the wrong reason. One fixture per
# test: both build into the same tmpdir paths.
@test "0079: the behind fixture is what it says -- the source reads as moved on" {
  consumer="$(mkbehind_install)" || fail "mkbehind_install could not build its history"
  run devbin_run "$consumer" doctor
  assert_output_contains "has moved on"
}

@test "0079: the ahead fixture is what it says -- the source reads as BEHIND" {
  consumer="$(mkahead_install)" || fail "mkahead_install could not build its history"
  run devbin_run "$consumer" doctor
  assert_output_contains "BEHIND this project"
}

@test "0079: a consumer AHEAD of its install is NOT offered the upgrade that reverts it" {
  require_pty
  consumer="$(mkahead_install)"
  run on_a_tty "$consumer"
  refute_output_contains "Upgrade now?"
  refute_output_contains "An update to devbin is available"
}

@test "0079: doctor on a terminal does not offer it either" {
  require_pty
  consumer="$(mkahead_install)"
  run on_a_tty "$consumer" doctor
  refute_output_contains "Upgrade now?"
  assert_output_contains "BEHIND this project"
}

@test "0079: a commit the install never held is not offered" {
  require_pty
  consumer="$(mkbehind_install)"
  set_recorded_commit "$consumer" 0000000000000000000000000000000000000000
  run on_a_tty "$consumer"
  refute_output_contains "Upgrade now?"
}

# --- doctor's source line says the direction --------------------------------

@test "0079: doctor on a consumer BEHIND its install says moved on, and names upgrade" {
  consumer="$(mkbehind_install)"
  run devbin_run "$consumer" doctor
  assert_output_contains "source: the devbin this project came from has moved on"
  assert_output_contains "run: bin/devbin upgrade"
}

@test "0079: doctor on a consumer AHEAD says the source is BEHIND, and never names upgrade" {
  consumer="$(mkahead_install)"
  run devbin_run "$consumer" doctor
  assert_output_contains "BEHIND this project"
  assert_output_contains "run: bin/devbin vendor"
  refute_output_contains "has moved on"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "0079: doctor on a record the install never held reports a difference, not an update" {
  consumer="$(mkbehind_install)"
  set_recorded_commit "$consumer" 0000000000000000000000000000000000000000
  run devbin_run "$consumer" doctor
  assert_output_contains "source: differs"
  refute_output_contains "has moved on"
  refute_output_contains "run: bin/devbin upgrade"
}

@test "0079: doctor on a consumer LEVEL with its install passes the source line" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  consumer="$(consumer_of_install "$src")"
  run devbin_run "$consumer" doctor
  assert_output_contains "source: level with the devbin it was vendored from"
}
