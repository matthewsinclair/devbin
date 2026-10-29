#!/usr/bin/env bats
# cachemodes.bats -- a fixture copied from the file's cache equals a
# real install of the same source into a second fixture, path for path, byte
# for byte and mode for mode, under whatever umask the file runs with (issue
# 0192), and the starter shape's copy a real starter install. harness.bats
# runs it under 022 and under 002. Not under tests/unit, so
# the suite never runs it by itself.

load "../../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# modes <dir> -- for each of the nine mode bits, the paths under <dir>/bin that
# carry it, so two trees compare mode for mode without parsing ls.
modes() {
  local b
  for b in u+r u+w u+x g+r g+w g+x o+r o+w o+x; do
    printf '%s:\n' "$b"
    (cd "$1/bin" && find . -perm -"$b" -print | LC_ALL=C sort)
  done
}

@test "a copied fixture is a real install, path, byte and mode" {
  local copied real
  copied="$(create_test_project copied)"
  install_devbin "$copied"
  real="$(create_test_project real)"
  "$DEVBIN_BIN_DIR/devbin" install --into "$real" --force >/dev/null
  diff -r "$copied/bin" "$real/bin" -x config.yaml || fail "the copy and the install differ in their bytes"
  [ "$(modes "$copied")" = "$(modes "$real")" ] ||
    fail "the copy and the install differ in their modes (umask $(umask)):
$(diff <(modes "$copied") <(modes "$real"))"
}

@test "a copied starter fixture is a real starter install, path, byte and mode, config included" {
  local copied="$DEVBIN_TEST_TMPDIR/copied/demo" real="$DEVBIN_TEST_TMPDIR/real/demo"
  install_devbin_starter "$copied"
  mkdir -p "$real"
  "$DEVBIN_BIN_DIR/devbin" install --into "$real" --name demo --lang shell >/dev/null
  diff -r "$copied" "$real" || fail "the starter copy and the starter install differ in their bytes"
  [ "$(modes "$copied")" = "$(modes "$real")" ] ||
    fail "the starter copy and the starter install differ in their modes (umask $(umask)):
$(diff <(modes "$copied") <(modes "$real"))"
}
