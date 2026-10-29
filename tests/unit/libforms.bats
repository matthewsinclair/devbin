#!/usr/bin/env bats
# libforms.bats - library forms a project's own commands call, each the
# one home of what devbin's own callers do (issue 0218):
#
#   git_local_env_clear  git_readonly's clearing, in the current shell
#   url_host_path        a remote url read as HOST and OWNER/NAME
#   text_shown           every url's userinfo out of any text
#
# Each is loaded from lib/helpers alone, as a project's command loads it.
#
# WHAT THIS DOES NOT CATCH, declared so a green is never read as covering it:
#   - release_repo's and release_text_shown's own answers, which releasecut and
#     releasestatus hold as they were;
#   - a secret in a url's query, which text_shown does not look for.

load "../lib/test_helper"

setup() {
  devbin_setup
}
teardown() { devbin_teardown; }

# in_helpers <script> [args...] -- <script> under bash with lib/helpers loaded.
in_helpers() {
  local script="$1"
  shift
  run bash -c '. "$1/helpers"; shift; '"$script" _ "$DEVBIN_LIB_DIR" "$@"
}

@test "git_local_env_clear clears a hook's repository variables from the current shell, so git -C acts on its own repository" {
  git init -q "$BATS_TEST_TMPDIR/hook"
  git init -q "$BATS_TEST_TMPDIR/site"
  site="$(cd "$BATS_TEST_TMPDIR/site" && pwd -P)"
  GIT_DIR="$BATS_TEST_TMPDIR/hook/.git" GIT_INDEX_FILE="$BATS_TEST_TMPDIR/hook/.git/index" \
    in_helpers 'git_local_env_clear || exit 7; printf "%s|%s\n" "${GIT_DIR-unset}" "$(git -C "$1" rev-parse --absolute-git-dir)"' \
    "$BATS_TEST_TMPDIR/site"
  assert_success
  [ "$output" = "unset|$site/.git" ] || fail "the hook's repository still answered: $output"
}

@test "git_local_env_clear fails, clearing nothing, when git cannot list its variables" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/git"
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  GIT_DIR=/nowhere PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    in_helpers 'rc=0; git_local_env_clear || rc=$?; printf "rc=%s GIT_DIR=%s\n" "$rc" "${GIT_DIR-unset}"'
  [ "$output" = "rc=1 GIT_DIR=/nowhere" ] || fail "it did not fail as git_readonly_prime does, leaving GIT_DIR: $output"
}

@test "url_host_path reads https, ssh and scp urls as HOST and OWNER/NAME, the userinfo dropped" {
  in_helpers 'for u in "$@"; do url_host_path "$u" || printf "FAILED %s\n" "$u"; done' \
    "https://user:tok@github.com/owner/name.git" \
    "ssh://git@host.example:2222/owner/name/" \
    "git@github.com:owner/name.git"
  assert_success
  [ "$output" = $'github.com\towner/name\nhost.example\towner/name\ngithub.com\towner/name' ] ||
    fail "read as:\n$output"
}

@test "url_host_path takes the userinfo from the authority alone, so an @ in the path never moves the host" {
  # Stripped at the first @ anywhere, this read as host github.com and path
  # owner/name: a remote on one host named as a repository on another.
  in_helpers 'rc=0; url_host_path "$1" || rc=$?; printf "rc=%s\n" "$rc"' "https://evil.example/x@github.com/owner/name"
  [ "$output" = "rc=4" ] || fail "read as: $output"
}

@test "url_host_path reads an scp url with no user by git's own rule: no / before the first :" {
  in_helpers 'url_host_path "$1"' "alias:owner/name"
  assert_success
  [ "$output" = $'alias\towner/name' ] || fail "read as: $output"
}

@test "url_host_path fails with a status of its own for no host, a second @, and a path that is not OWNER/NAME" {
  in_helpers 'for u in "$@"; do rc=0; url_host_path "$u" >/dev/null || rc=$?; printf "%s %s\n" "$rc" "$u"; done' \
    /local/path/repo file:///x/y "https://a@b@host/o/n" "https://host/a/b/c"
  [ "$output" = $'2 /local/path/repo\n2 file:///x/y\n3 https://a@b@host/o/n\n4 https://host/a/b/c' ] ||
    fail "statuses:\n$output"
}

@test "text_shown drops the userinfo of every url in free text, https and ssh, a password holding a raw @ whole" {
  in_helpers 'text_shown "$1"' \
    "fatal: unable to access 'https://user:t@k@host.example/o/n.git/': 403 and user:tok@host.example: Permission denied (publickey)"
  assert_success
  [ "$output" = "fatal: unable to access 'https://host.example/o/n.git/': 403 and host.example: Permission denied (publickey)" ] ||
    fail "shown as: $output"
}

@test "text_shown keeps a user alone, and a line with no url, as they are" {
  in_helpers 'text_shown "$1"; text_shown "$2"' \
    "git@github.com: Permission denied (publickey)." "everything up-to-date"
  assert_success
  [ "$output" = $'git@github.com: Permission denied (publickey).\neverything up-to-date' ] || fail "shown as:\n$output"
}

@test "text_shown keeps each line, and passes a byte that is not UTF-8 through" {
  in_helpers 'text_shown "$1"' $'one https://u:p@h/x\ntwo \xff end'
  assert_success
  [ "$output" = $'one https://h/x\ntwo \xff end' ] || fail "shown as:\n$output"
}
