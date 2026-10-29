#!/usr/bin/env bats
# gitremote.bats - a call to a remote cannot ask for a credential (issue 0217).
#
# git asks an askpass program -- GIT_ASKPASS, else core.askPass, else
# SSH_ASKPASS -- before it reads GIT_TERMINAL_PROMPT, so turning the terminal
# prompt off alone leaves a GUI or an IDE's helper free to ask. git_remote
# (lib/helpers) empties all three for the call, and release_git_remote, the
# release core's one door to a remote, runs through it.
#
# A remote that cannot be reached never asks for a credential, so each arm
# points git at a local server that answers every request 401 with a Basic
# challenge: git reaches its credential step, and its own words about that step
# ("could not read Username") show it did. The askpass named is a script that
# records being run.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - a credential helper that asks by its own means (Git Credential Manager's
#     dialog): git_remote passes credential.interactive=never and
#     GCM_INTERACTIVE=never, which no fixture here exercises;
#   - ssh's own asks, which BatchMode stops (releasestatus.bats's arms).

load "../lib/test_helper"

setup() {
  devbin_setup
  require_command perl
  # No system config: a machine's credential.helper stays out of the arms.
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_ASKPASS SSH_ASKPASS
  ASKED="$BATS_TEST_TMPDIR/asked"
  ASKPASS="$BATS_TEST_TMPDIR/askpass"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nprintf "x\\n"\n' "$ASKED" >"$ASKPASS"
  chmod +x "$ASKPASS"
  # The server: 127.0.0.1 on a port the kernel picks, written to a file once it
  # listens, answering every request 401 until teardown kills it.
  perl -MIO::Socket::INET -e '
    my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 5, ReuseAddr => 1) or die "listen: $!";
    open(my $f, ">", "$ARGV[0].tmp") or die; print $f $s->sockport; close $f; rename "$ARGV[0].tmp", $ARGV[0];
    while (my $c = $s->accept) {
      while (my $l = <$c>) { last if $l =~ /^\r?\n$/ }
      print $c "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"devbin\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
      close $c;
    }' "$BATS_TEST_TMPDIR/port" 3>&- &
  SERVER=$!
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$BATS_TEST_TMPDIR/port" ] && break
    sleep 0.2
  done
  [ -s "$BATS_TEST_TMPDIR/port" ] || fail "the 401 server did not start"
  URL="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")/demo.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
}

teardown() {
  [ -z "${SERVER:-}" ] || kill "$SERVER" 2>/dev/null || true
  devbin_teardown
}

# remote_read <function> -- <function> ls-remote URL, from REPO, with the
# release core loaded as the release verb loads it.
remote_read() {
  run bash -c 'set -euo pipefail; . "$1/helpers"; . "$1/release.notes"; . "$1/release.steps"; cd "$2"; "$3" ls-remote "$4"' \
    _ "$DEVBIN_LIB_DIR" "$REPO" "$1" "$URL"
}

# asked_none -- the askpass script never ran, and git said, in its own words,
# that it reached the credential step and got nothing: "unable to get password
# from user" where it honours credential.interactive=never, "could not read
# Username" where that key is unknown to it and the terminal prompt is off.
asked_none() {
  [ ! -e "$ASKED" ] || fail "the askpass program was run, so the call could ask:
$(cat "$ASKED")"
  assert_failure
  grep -qE 'unable to get password from user|could not read Username' <<<"$output" ||
    fail "git did not say it reached its credential step and got nothing:
$output"
}

@test "release_git_remote never runs GIT_ASKPASS against a remote that asks for a credential" {
  export GIT_ASKPASS="$ASKPASS"
  remote_read release_git_remote
  asked_none
}

@test "release_git_remote never runs core.askPass, set in the repository's config" {
  # The suite's global config is /dev/null (devbin_setup), so the repository's
  # own: the run stands in it, and -c on the command line outranks both.
  git -C "$REPO" config core.askPass "$ASKPASS"
  remote_read release_git_remote
  asked_none
}

@test "release_git_remote never runs SSH_ASKPASS, which git falls back to for a credential" {
  export SSH_ASKPASS="$ASKPASS"
  remote_read release_git_remote
  asked_none
}

@test "git_remote is lib/helpers' own, so a project's command calls it with nothing else loaded" {
  export GIT_ASKPASS="$ASKPASS"
  run bash -c 'set -euo pipefail; . "$1/helpers"; cd "$2"; git_remote ls-remote "$3"' _ "$DEVBIN_LIB_DIR" "$REPO" "$URL"
  asked_none
}
