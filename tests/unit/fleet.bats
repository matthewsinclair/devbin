#!/usr/bin/env bats
#
# `devbin fleet` -- the generator behind intent/docs/devbin-users.md.
#
# THE POINT OF THESE TESTS IS THE REFUSAL, not the happy path. The document this
# command writes is made entirely of claims with expiry dates, and the failure
# that matters is not a crash: it is a scan that silently drops an estate and
# produces a document indistinguishable from a correct one. That happened during
# development -- one pass reported 13 estates and the next reported 12, the
# missing one being the only root under Dropbox -- and it was never reproducible
# afterwards, which is exactly why it needed a control rather than care.
#
# The scan is therefore taken twice and the write is refused when the two
# disagree. A control that cannot be driven red is not a control, so the
# disagreement is simulated here by stubbing `scan` in a copy of the handler:
# the stub IS the unstable filesystem, and every other line of the code path is
# the real one.
#
set -euo pipefail

load "../lib/test_helper"

setup() {
  devbin_setup
  FLEET="$DEVBIN_HOME/bin/.devbin/cmd/fleet"
  # For sha256_of. Spelling the tool by hand here is issue 0052's defect
  # reproduced in a gate rather than a product.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  ROOTS="$DEVBIN_TEST_TMPDIR/roots"
  PROJ="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$ROOTS" "$PROJ/intent/docs"
  # THE WALK OUTSIDE THE ROOTS (issue 0116) reads DEVBIN_FLEET_HOME, and every
  # arm points it at an empty directory, so no arm walks a real home directory.
  # EXPORTED, because most arms call the handler directly rather than through
  # run_fleet. The arms about the walk put installs under it.
  export DEVBIN_FLEET_HOME="$DEVBIN_TEST_TMPDIR/walkhome"
  mkdir -p "$DEVBIN_FLEET_HOME"
}

teardown() {
  devbin_teardown
}

# mkinstall <path-under-roots> -- a minimal but REAL devbin install: a launcher,
# a lib to digest, and a manifest carrying the three header fields the scan
# reads and an entry for the lib file. Not a stub of the scan's input; the scan
# reads these off disk. The entry is what makes the manifest vouch for a file:
# one cut to its header records none, which `upgrade` refuses unless forced and
# the sweep names rather than runs (issue 0159).
mkinstall() {
  local d="$ROOTS/$1"
  mkdir -p "$d/bin/.devbin/lib"
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$d/bin/devbin"
  printf 'lib bytes for %s\n' "$1" > "$d/bin/.devbin/lib/helpers"
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: deadbeefcafe1234\n' \
    > "$d/bin/.devbin/manifest.sha256"
  vouch "$1"
}

# vouch <path-under-roots> -- record the install's lib file in its manifest,
# with its real sum, after the header an arm or mkinstall wrote: a manifest of
# header lines alone records no files, which upgrade refuses and the census and
# the sweep name (issue 0159).
vouch() {
  printf '%s  bin/.devbin/lib/helpers\n' "$(sha256_of "$ROOTS/$1/bin/.devbin/lib/helpers")" \
    >>"$ROOTS/$1/bin/.devbin/manifest.sha256"
}

run_fleet() {
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" "$@"
}

@test "bare fleet exits 1 -- naming no subcommand did not succeed" {
  run_fleet
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: bin/devbin fleet"* ]]
}

@test "fleet --help exits 0 -- asking for usage is not a usage error" {
  run_fleet --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: bin/devbin fleet"* ]]
}

@test "an unknown fleet option is refused, not ignored" {
  run_fleet nosuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown fleet option: nosuch"* ]]
}

@test "audit finds an install by its manifest and reads the header fields" {
  mkinstall alpha
  run_fleet audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"estate"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"0.1.0"* ]]
  [[ "$output" == *"deadbeefcafe"* ]]
}

# AN INSTALL IS FOUND BY ITS RUNTIME AS WELL AS BY ITS MANIFEST (issue 0154).
# The walk looked for manifest.sha256 alone, so an install that had lost its
# manifest -- a launcher and a vendored lib with no record of what devbin wrote
# there, the state 0146 made `upgrade` refuse -- had no row at all, and the
# census exited 0 as if it were not there. The arms below hold the audit, the
# document, the outside walk and the sweep; the lib-less half of the union,
# a manifest with no lib, is held by the `libgone` arms further down.

# mkinstall_nomanifest <path-under-roots> -- mkinstall, then its manifest removed.
mkinstall_nomanifest() {
  mkinstall "$1"
  rm "$ROOTS/$1/bin/.devbin/manifest.sha256"
}

# _row_of <name> -- every audit row in $output whose path ends in /<name>.
_row_of() {
  printf '%s\n' "$output" | awk -F'\t' -v n="/$1" \
    'NF >= 7 && length($2) >= length(n) && substr($2, length($2) - length(n) + 1) == n'
}

@test "audit lists an install that has lost its manifest, as NO MANIFEST, and still exits 0 (0154)" {
  mkinstall alpha
  mkinstall_nomanifest beta
  run_fleet audit
  assert_success
  local row
  row="$(_row_of beta)"
  [ -n "$row" ] || fail "no row for the install that has lost its manifest: $output"
  [ "$(printf '%s\n' "$row" | awk -F'\t' '{print $1 "|" $3 "|" $4 "|" $6}')" = "estate|NO MANIFEST|NO MANIFEST|NO MANIFEST" ] ||
    fail "its version, commit and last-vendored cells do not say NO MANIFEST: $row"
  [[ "$(printf '%s\n' "$row" | awk -F'\t' '{print $5}')" =~ ^[0-9a-f]{12}$ ]] ||
    fail "its seam was not digested: $row"
  [ -n "$(_row_of alpha)" ] || fail "the whole install lost its row: $output"
}

@test "audit reads an install whose manifest records no files as NO FILES, keeps its header's version and commit, and still exits 0 (0159)" {
  # A manifest cut to its header vouches for no file, so upgrade refuses it and
  # doctor fails it; the census read it as a healthy row.
  mkinstall alpha
  mkinstall beta
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: deadbeefcafe1234\n' \
    >"$ROOTS/beta/bin/.devbin/manifest.sha256"
  run_fleet audit
  assert_success
  local row
  row="$(_row_of beta)"
  [ -n "$row" ] || fail "no row for the install whose manifest records no files: $output"
  [ "$(printf '%s\n' "$row" | awk -F'\t' '{print $3 "|" $4 "|" $6}')" = "0.1.0|deadbeefcafe|NO FILES" ] ||
    fail "its version, commit and last-vendored cells: $row"
  [[ "$(_row_of alpha | awk -F'\t' '{print $6}')" != "NO FILES" ]] || fail "a manifest that records a file read as NO FILES: $output"
}

@test "an install marked by both its manifest and its lib is listed once (0154)" {
  mkinstall both
  run_fleet audit
  assert_success
  local n
  n="$(_row_of both | grep -c . || true)"
  [ "$n" -eq 1 ] || fail "an install carrying a manifest and a lib was listed $n times: $output"
}

@test "doc lists an install that has lost its manifest, and says what NO MANIFEST means (0154)" {
  mkinstall alpha
  mkinstall_nomanifest beta
  run_fleet doc
  assert_success
  local doc="$PROJ/intent/docs/devbin-users.md" row
  row="$(grep -E '^\| [^|]*/beta +\|' "$doc" || true)"
  [ -n "$row" ] || fail "the document has no row for the install that has lost its manifest: $(cat "$doc")"
  [[ "$row" == *"| NO MANIFEST "* ]] || fail "its row does not say NO MANIFEST: $row"
  grep -q 'A `NO MANIFEST` row' "$doc" || fail "the document does not say what NO MANIFEST means"
}

@test "doc lists an install whose manifest records no files, and says what NO FILES means (0159)" {
  mkinstall alpha
  mkinstall beta
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: deadbeefcafe1234\n' \
    >"$ROOTS/beta/bin/.devbin/manifest.sha256"
  run_fleet doc
  assert_success
  local doc="$PROJ/intent/docs/devbin-users.md" row
  row="$(grep -E '^\| [^|]*/beta +\|' "$doc" || true)"
  [ -n "$row" ] || fail "the document has no row for the install whose manifest records no files: $(cat "$doc")"
  [[ "$row" == *"| NO FILES "* ]] || fail "its row does not say NO FILES: $row"
  grep -q 'A `NO FILES` row' "$doc" || fail "the document does not say what NO FILES means"
}

# BOTH STAT SPELLINGS, DRIVEN ON EVERY RUNNER. mtime_epoch tries BSD's
# `stat -f %m` and then GNU's `stat -c %Y`. GNU's `-f` means FILESYSTEM status:
# it prints that block to stdout AND returns 1, so an uncaptured first arm left
# the block in front of the epoch, and every Ubuntu run read the manifest's time
# as UNREADABLE. The whole file went red on CI while macOS stayed green. A
# stand-in `stat` of each shape goes on PATH here, so both arms run on macOS and
# on Linux, and each hands back a fixed epoch whose time the arm can name.

# stat_shim <gnu|bsd> -- a `stat` of that shape on PATH, returning 1700000000.
stat_shim() {
  local d="$DEVBIN_TEST_TMPDIR/shim-$1"
  mkdir -p "$d"
  case "$1" in
    gnu)
      cat > "$d/stat" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -f)
    printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n' "$3"
    printf "stat: cannot read file system information for '%s'\n" "$2" >&2
    exit 1
    ;;
  -c) [ "$2" = %Y ] && { echo 1700000000; exit 0; } ;;
esac
exit 1
EOF
      ;;
    bsd)
      cat > "$d/stat" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -f) [ "$2" = %m ] && { echo 1700000000; exit 0; } ;;
  -c) echo "stat: illegal option -- c" >&2 ;;
esac
exit 1
EOF
      ;;
  esac
  chmod +x "$d/stat"
  printf '%s' "$d"
}

@test "last vendored reads under a GNU stat, whose -f prints a filesystem block and fails" {
  mkinstall alpha
  local shim
  shim="$(stat_shim gnu)"
  PATH="$shim:$PATH" run_fleet audit
  [ "$status" -eq 0 ] || fail "want 0 under a GNU stat, got $status:
$output"
  [[ "$output" == *"2023-11-14 22:13Z"* ]] || fail "no epoch-read time:
$output"
  [[ "$output" != *"UNREADABLE"* ]] || fail "the time read UNREADABLE:
$output"
}

@test "last vendored reads under a BSD stat, which refuses -c -- the GNU arm's control" {
  mkinstall alpha
  local shim
  shim="$(stat_shim bsd)"
  PATH="$shim:$PATH" run_fleet audit
  [ "$status" -eq 0 ] || fail "want 0 under a BSD stat, got $status:
$output"
  [[ "$output" == *"2023-11-14 22:13Z"* ]] || fail "no epoch-read time:
$output"
}

@test "a stray bin/devbin with no install mark at all is still not an install (0154)" {
  # Until 0154 this arm held that a launcher and a vendored lib with no
  # manifest were not an install. That pair is one now -- an install that has
  # lost its manifest is the one upgrade refuses -- so what this keeps is its
  # original intent: a launcher with neither mark is not an install.
  mkdir -p "$ROOTS/notaninstall/bin/.devbin"
  printf 'x\n' > "$ROOTS/notaninstall/bin/devbin"
  run_fleet audit
  [ "$status" -eq 0 ]
  [[ "$output" != *"notaninstall"* ]]
}

@test "a lib skeleton with no launcher -- a tree-index mirror's shape -- is not an install, and the census stays clean (0154)" {
  # An Intent tree-index mirror carries a project's directory skeleton: an
  # empty bin/.devbin/lib and no bin/devbin. Counted by its lib, it was a row
  # whose seam could not be digested, and the census on a real machine failed.
  mkinstall alpha
  mkdir -p "$ROOTS/alpha/intent/.treeindex/bin/.devbin/lib" "$ROOTS/alpha/intent/.treeindex/bin/.devbin/help"
  run_fleet audit
  assert_success
  [[ "$output" != *".treeindex"* ]] || fail "the mirror was counted as an install: $output"
  [ -n "$(_row_of alpha)" ] || fail "the real install lost its row: $output"
}

@test "an install with a manifest and a lib but no launcher is still found, by its manifest (0154)" {
  # The lib mark needs a launcher; the manifest mark never did, so a root
  # carrying both is the manifest's, whichever of the two the walk met first.
  mkinstall nolauncher
  rm "$ROOTS/nolauncher/bin/devbin"
  run_fleet audit
  assert_failure
  assert_output_contains "could not digest the seam of $ROOTS/nolauncher"
  [ -n "$(_row_of nolauncher)" ] || fail "the install with a manifest lost its row: $output"
}

@test "install_roots takes a root its manifest marks as the manifest's, even when its lib comes first (0154)" {
  # The arm above cannot fail on every disk: find meets a directory's entries in
  # the filesystem's own order, and APFS gives manifest.sha256 before lib
  # whichever was made first, so a mapping where the first mark met decides
  # passes it there. Fed to install_roots directly, lib first, the root its
  # manifest marks still needs no launcher, and a root its lib alone marks
  # still does.
  local copy="$DEVBIN_TEST_TMPDIR/fleet-install-roots" m="$ROOTS/marked" l="$ROOTS/libonly"
  mkdir -p "$m/bin/.devbin/lib" "$l/bin/.devbin/lib"
  printf '# kind: project\n' >"$m/bin/.devbin/manifest.sha256"
  {
    sed '/^case "${1:-}" in$/,$d' "$FLEET"
    printf 'install_roots\n'
  } >"$copy"
  run env PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash -c \
    'printf "%s\n" "$2/bin/.devbin/lib" "$3/bin/.devbin/lib" "$2/bin/.devbin/manifest.sha256" | bash "$1"' \
    _ "$copy" "$m" "$l"
  assert_success
  assert_output "$m"
}

@test "an install with no manifest whose lib is a symlink is still found (0154)" {
  # find meets a linked lib as a link, never as a directory, and devbin's own
  # test for an install follows it.
  mkinstall_nomanifest linkedlib
  local d="$ROOTS/linkedlib" real="$DEVBIN_TEST_TMPDIR/reallib"
  mv "$d/bin/.devbin/lib" "$real"
  ln -s "$real" "$d/bin/.devbin/lib"
  run_fleet audit
  local row
  row="$(_row_of linkedlib)"
  [ -n "$row" ] || fail "an install whose lib is a link and whose manifest is gone has no row: $output"
  [ "$(printf '%s\n' "$row" | awk -F'\t' '{print $3}')" = "NO MANIFEST" ] || fail "its version cell: $row"
}

@test "an install with no manifest whose launcher is a dangling link is found, and the audit names it (0154)" {
  mkinstall_nomanifest danglinglauncher
  rm "$ROOTS/danglinglauncher/bin/devbin"
  ln -s "$DEVBIN_TEST_TMPDIR/no-such-launcher" "$ROOTS/danglinglauncher/bin/devbin"
  run_fleet audit
  assert_failure
  assert_output_contains "could not digest the seam of $ROOTS/danglinglauncher"
  [ -n "$(_row_of danglinglauncher)" ] || fail "a launcher that is a dangling link dropped the install: $output"
}

@test "a manifest that is a link to nothing is missing, as upgrade reads it: NO MANIFEST in the census, and not swept (0154)" {
  # One definition, manifest_missing (lib/install, 0146), the test upgrade
  # refuses on. Read as UNREADABLE here, the census failed and the sweep
  # planned the very run upgrade refuses.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate danglingm
  local m="$ROOTS/danglingm/bin/.devbin/manifest.sha256"
  rm "$m"
  ln -s "$DEVBIN_TEST_TMPDIR/no-such-manifest" "$m"
  run bash -c '. "$1/helpers" && . "$1/install" && manifest_missing "$2"' _ "$DEVBIN_LIB_DIR" "$ROOTS/danglingm"
  [ "$status" -eq 0 ] || fail "upgrade's own test does not call this manifest missing (rc $status): $output"
  run_fleet audit
  assert_success
  [ "$(_row_of danglingm | awk -F'\t' '{print $3 "|" $4 "|" $6}')" = "NO MANIFEST|NO MANIFEST|NO MANIFEST" ] ||
    fail "the census does not read a link to nothing as NO MANIFEST: $output"
  run_sweep
  assert_success
  assert_output_matches 'danglingm +\| +NO MANIFEST -- not swept'
}

@test "a lib that is a link to nothing marks no install, as devbin's own test counts none (0154)" {
  mkinstall_nomanifest ghost
  rm -r "$ROOTS/ghost/bin/.devbin/lib"
  ln -s "$DEVBIN_TEST_TMPDIR/no-such-lib" "$ROOTS/ghost/bin/.devbin/lib"
  run_fleet audit
  assert_success
  [[ "$output" != *"/ghost"* ]] || fail "a lib that leads nowhere was counted as an install: $output"
}

@test "an estate that is its own checkout and has lost its manifest, uncommitted, reads DIRTY, and the audit still exits 0 (0154)" {
  # Every NO MANIFEST arm above is built on mkinstall, which makes no
  # repository, so none could see the absent manifest read UNREADABLE by git.
  mkinstall_committed alpha
  rm "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  run_fleet audit
  assert_success
  [ "$(committed_field alpha)" = DIRTY ] || fail "a removal git has not been told of reads '$(committed_field alpha)': $output"
  [ "$(_row_of alpha | awk -F'\t' '{print $3}')" = "NO MANIFEST" ] || fail "its version cell: $output"
}

@test "an estate whose manifest's removal is committed reads committed, and doc publishes it (0154)" {
  mkinstall_committed beta
  git -C "$ROOTS/beta" rm -q bin/.devbin/manifest.sha256
  git -C "$ROOTS/beta" -c user.email=t@t -c user.name=t commit -q -m 'the manifest goes'
  run_fleet audit
  assert_success
  [ "$(committed_field beta)" = committed ] || fail "a committed removal reads '$(committed_field beta)': $output"
  run_fleet doc
  assert_success
  grep -qE '^\| [^|]*/beta +\|' "$PROJ/intent/docs/devbin-users.md" || fail "the document has no row for beta"
}

@test "a directory inside a runtime that cannot be searched is not a hole in the walk (0154)" {
  # The prune keeps a runtime's insides out of the walk: nothing beneath a lib
  # is an install, so "installs beneath it may be missing" would be false.
  mkinstall eps
  local sealed="$ROOTS/eps/bin/.devbin/lib/sealed"
  mkdir -m 000 "$sealed"
  if [ -x "$sealed" ]; then
    chmod 755 "$sealed"
    skip "running with permissions that search a mode-000 directory"
  fi
  run_fleet audit
  chmod 755 "$sealed"
  [[ "$output" != *"could not read all of"* ]] || fail "the walk reported a hole inside a runtime: $output"
  [ -n "$(_row_of eps)" ] || fail "the install lost its row: $output"
}

@test "an install whose lib cannot be searched is no hole in the walk, and its digest still fails the audit (0175)" {
  # The lib itself, not a directory inside it: the walk asked whether it could
  # search a directory before it asked whether the directory marked an install,
  # so it named the lib a hole, "installs beneath it may be missing", where
  # nothing beneath a lib is an install. The digest is what names it, and it
  # may name the lib it cannot read: BSD's find says so itself, and under GNU's
  # find_walk does, so only the walk's own line is refuted here.
  mkinstall eps
  local lib="$ROOTS/eps/bin/.devbin/lib"
  chmod 644 "$lib"
  if [ -x "$lib" ]; then
    chmod 755 "$lib"
    skip "running with permissions that search a mode-0644 directory"
  fi
  run_fleet audit
  chmod 755 "$lib"
  [ "$status" -ne 0 ] || fail "an install whose seam cannot be digested passed the audit: $output"
  assert_output_contains "could not digest the seam of $ROOTS/eps"
  [[ "$output" != *"installs beneath it may be missing"* ]] || fail "the walk named the lib a hole: $output"
  [ -n "$(_row_of eps)" ] || fail "the install lost its row: $output"
}

@test "a lib-shaped directory that is not bin/.devbin/lib and cannot be searched is still a hole (0175)" {
  # The lib is marked ahead of the hole check, so the mark's path is what keeps
  # every other unsearchable directory a hole: a project's own lib/ holding an
  # install, and a .devbin/lib outside any bin/.
  local d
  for d in "$ROOTS/proj/lib" "$ROOTS/odd/.devbin/lib"; do
    ROOTS="$d" mkinstall inner
    chmod 644 "$d"
    if [ -x "$d" ]; then
      chmod 755 "$d"
      skip "running with permissions that search a mode-0644 directory"
    fi
    run_fleet audit
    chmod 755 "$d"
    [ "$status" -ne 0 ] || fail "a scan over $d, which it could not search, exited 0: $output"
    assert_output_contains "cannot search $d -- nothing beneath it was looked at"
    assert_output_contains "could not read all of $ROOTS -- installs beneath it may be missing"
    rm -rf "$d"
  done
}

@test "a lib skeleton that cannot be searched is no hole either (0175)" {
  # Pruned by its shape, launcher or not: nothing beneath a bin/.devbin/lib is
  # an install, and the skeleton is no install, so the census stays clean.
  local lib="$ROOTS/alpha/intent/.treeindex/bin/.devbin/lib"
  mkinstall alpha
  mkdir -p "$lib"
  chmod 644 "$lib"
  if [ -x "$lib" ]; then
    chmod 755 "$lib"
    skip "running with permissions that search a mode-0644 directory"
  fi
  run_fleet audit
  chmod 755 "$lib"
  assert_success
  [[ "$output" != *".treeindex"* ]] || fail "the skeleton was named: $output"
  [ -n "$(_row_of alpha)" ] || fail "the real install lost its row: $output"
}

@test "an install two overlapping roots both reach is listed once (0154)" {
  # Each root's walk is mapped to installs together, so a frame whose roots
  # overlap no longer lists one install twice.
  mkinstall alpha
  run env DEVBIN_FLEET_ROOTS="$ROOTS $ROOTS/alpha" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  assert_success
  local n
  n="$(_row_of alpha | grep -c . || true)"
  [ "$n" -eq 1 ] || fail "two overlapping roots listed one install $n times: $output"
}

@test "a census that cannot tell which installs the walk found fails by name, never as a short list (0154)" {
  mkinstall alpha
  # And one outside the frame, so the walk outside the roots has one to map too.
  mkdir -p "$DEVBIN_FLEET_HOME/away/bin/.devbin/lib"
  printf '#!/usr/bin/env bash\n' >"$DEVBIN_FLEET_HOME/away/bin/devbin"
  local shim="$DEVBIN_TEST_TMPDIR/awkshim" real
  real="$(command -v awk)"
  mkdir -p "$shim"
  # Fails install_roots' program alone; every other awk runs as itself.
  printf '#!/bin/sh\ncase "$*" in *"manifest[p]"*) exit 2 ;; esac\nexec %s "$@"\n' "$real" >"$shim/awk"
  chmod +x "$shim/awk"
  PATH="$shim:$PATH" run_fleet audit
  assert_failure
  assert_output_contains "could not tell which installs the walk found"
  assert_output_contains "could not tell which installs the walk outside the roots found"
}

@test "a deps/ checkout INSIDE a worktree is a dep, not a worktree" {
  # The ordering bug this pins: testing `.worktrees/` first labelled four
  # package-manager artifacts as worktrees. Dep-ness is the stronger claim --
  # a worktree is a tree somebody could work in, a deps/ checkout is not.
  mkworktree ".worktrees/cc"
  mkinstall ".worktrees/cc"
  mkinstall ".worktrees/cc/deps/arca"
  run_fleet audit
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | grep 'deps/arca' | cut -f1)" == "dep" ]]
  [[ "$(printf '%s\n' "$output" | grep -v 'deps/arca' | grep '.worktrees/cc' | cut -f1)" == "worktree" ]]
}

@test "an UNRECORDED source commit is reported as such, not as a blank" {
  mkinstall beta
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n' \
    > "$ROOTS/beta/bin/.devbin/manifest.sha256"
  vouch beta
  run_fleet audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRECORDED"* ]]
}

@test "two installs with identical bytes share a seam digest; different bytes do not" {
  mkinstall same_a
  mkinstall same_b
  # Same launcher and lib content in both, so the digest must collide.
  printf '#!/usr/bin/env bash\necho x\n' > "$ROOTS/same_a/bin/devbin"
  printf '#!/usr/bin/env bash\necho x\n' > "$ROOTS/same_b/bin/devbin"
  printf 'identical\n' > "$ROOTS/same_a/bin/.devbin/lib/helpers"
  printf 'identical\n' > "$ROOTS/same_b/bin/.devbin/lib/helpers"
  run_fleet audit
  [ "$status" -eq 0 ]
  local a b
  a="$(printf '%s\n' "$output" | grep 'same_a' | cut -f5)"
  b="$(printf '%s\n' "$output" | grep 'same_b' | cut -f5)"
  [ -n "$a" ]
  [ "$a" = "$b" ]

  # And the digest must MOVE when the bytes move, or it is not measuring them.
  printf 'different\n' > "$ROOTS/same_b/bin/.devbin/lib/helpers"
  run_fleet audit
  b="$(printf '%s\n' "$output" | grep 'same_b' | cut -f5)"
  [ "$a" != "$b" ]
}

@test "doc writes the document when the scan is stable" {
  mkinstall alpha
  mkinstall beta
  run_fleet doc
  [ "$status" -eq 0 ]
  [ -s "$PROJ/intent/docs/devbin-users.md" ]
  grep -q '^## Estates -- 2$' "$PROJ/intent/docs/devbin-users.md"
  grep -q '^> ## GENERATED AT: ' "$PROJ/intent/docs/devbin-users.md"
}

# 0069
@test "doc names its roots relative to HOME and carries the home directory nowhere" {
  # The document is TRACKED, and its "Roots scanned" list printed each root
  # absolute -- this machine's home directory, in a committed file. Its paste
  # line already wrote `~/`; the roots did not.
  export HOME="$DEVBIN_TEST_TMPDIR"
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  doc="$PROJ/intent/docs/devbin-users.md"
  grep -q '^- `~/roots`$' "$doc"
  [ "$(grep -cF "$HOME/" "$doc" || true)" = 0 ]
}

# 0069
@test "doc carries no home directory in any column when HOME ends in a slash" {
  # The estate table's Project column stripped "$HOME/" by hand, so a HOME
  # written with a trailing slash stripped nothing and printed every estate's
  # full path. The check is for the bare directory, with no slash after it, so
  # a path printed any way at all is caught.
  export HOME="$DEVBIN_TEST_TMPDIR/"
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  doc="$PROJ/intent/docs/devbin-users.md"
  grep -q '^| roots/alpha ' "$doc"
  [ "$(grep -cF "$DEVBIN_TEST_TMPDIR" "$doc" || true)" = 0 ]
}

@test "every row of a generated table is the same width" {
  mkinstall alpha
  mkinstall beta
  run_fleet doc
  [ "$status" -eq 0 ]
  # One width per table; the standard asks for aligned columns and a table
  # padded by hand drifts the first time a value grows by a character.
  run bash -c "awk '/^\|/{ print length(\$0) }' '$PROJ/intent/docs/devbin-users.md' | sort -u | wc -l"
  [ "$output" -ge 1 ]
  run bash -c "awk '/^\|/{ c[length(\$0)]++ } END { for (k in c) if (c[k] < 3) print \"ragged:\" k }' '$PROJ/intent/docs/devbin-users.md'"
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# THE STALENESS HEADER. hv ruled that this document is a quick snapshot rather
# than a steel thread, and that it must say so at the top: an explicit
# generated-at stamp, an explicit instruction not to trust it if that stamp is
# not current, and a requirement that an agent ASK hv before rebuilding.
#
# Pinned because an instruction that can be quietly deleted is an instruction
# that will be, and because its absence is invisible -- the document renders
# perfectly well without it and reads as authoritative.
# ---------------------------------------------------------------------------

@test "the stamp is the FIRST thing after the title, not buried under the tables" {
  # Order is the whole point. A generated-at line below the tables is read after
  # they have already been believed.
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  local second
  second="$(sed -n '3p' "$PROJ/intent/docs/devbin-users.md")"
  [[ "$second" == "> ## GENERATED AT: "* ]]
}

@test "the header carries the do-not-rely and ask-hv-first instructions" {
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  grep -q 'DO NOT RELY ON ANYTHING BELOW IF THAT TIMESTAMP IS NOT FROM RIGHT NOW' "$PROJ/intent/docs/devbin-users.md"
  grep -q 'DO NOT REGENERATE IT SILENTLY -- ASK hv FIRST' "$PROJ/intent/docs/devbin-users.md"
  grep -q 'Do not hand-edit' "$PROJ/intent/docs/devbin-users.md"
}

@test "the stamp is READ FROM A CLOCK -- UTC-marked and within minutes of now" {
  # A hardcoded or carried-forward stamp is the exact failure this document is
  # built to avoid, and it is indistinguishable from a real one by inspection.
  # So: the format must carry its Z, and the value must actually be now.
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]

  local stamp now_e stamp_e delta
  stamp="$(sed -n '3p' "$PROJ/intent/docs/devbin-users.md" | sed 's/^> ## GENERATED AT: //')"
  [[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}Z$ ]] ||
    fail "stamp is not a UTC-marked minute-granularity time: '$stamp'"

  now_e="$(date -u +%s)"
  stamp_e="$(date -u -j -f '%Y-%m-%d %H:%M' "${stamp%Z}" +%s 2>/dev/null ||
             date -u -d "${stamp%Z}" +%s 2>/dev/null)"
  [ -n "$stamp_e" ] || skip "no portable UTC date parser on this host"
  delta=$(( now_e > stamp_e ? now_e - stamp_e : stamp_e - now_e ))
  [ "$delta" -le 300 ] || fail "stamp is $delta seconds from now -- it was not read from a clock in this run"
}

@test "the command's own output states the hv gate, not only the file" {
  # The gate has to reach whoever just ran the command, who may never open the
  # document they have just replaced.
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"hv confirms before the next rebuild"* ]]
}

@test "an absent root is named as absent rather than silently dropped" {
  mkinstall alpha
  run env DEVBIN_FLEET_ROOTS="$ROOTS $DEVBIN_TEST_TMPDIR/nosuchroot" \
    PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" doc
  [ "$status" -eq 0 ]
  grep -q 'ABSENT on this machine' "$PROJ/intent/docs/devbin-users.md"
}

# ---------------------------------------------------------------------------
# The refusal. Everything above is the happy path; this is why the command has
# a control at all.
# ---------------------------------------------------------------------------

# stub_unstable_scan -- a copy of the handler whose `scan` loses one install on
# the second call. Simulates the observed Dropbox behaviour: an estate present
# in pass 1 and gone in pass 2.
stub_unstable_scan() {
  local copy="$DEVBIN_TEST_TMPDIR/fleet-unstable"
  local counter="$DEVBIN_TEST_TMPDIR/scan-counter"
  rm -f "$counter"
  {
    # Everything up to the dispatcher, then the stub, then the dispatcher.
    sed '/^case "${1:-}" in$/,$d' "$FLEET"
    cat <<STUB
scan() {
  local C="$counter" n=0
  [ -f "\$C" ] && n=\$(cat "\$C")
  n=\$((n + 1)); printf '%s\n' "\$n" > "\$C"
  printf 'estate\talpha\t0.1.0\tdead\tdig1\t2026-01-01 00:00Z\n'
  [ "\$n" -ge 2 ] || printf 'estate\tbeta\t0.1.0\tdead\tdig2\t2026-01-01 00:00Z\n'
}
STUB
    sed -n '/^case "${1:-}" in$/,$p' "$FLEET"
  } > "$copy"
  printf '%s\n' "$copy"
}

@test "doc REFUSES to write when the two scans disagree about which installs exist" {
  local copy
  copy="$(stub_unstable_scan)"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$copy" doc
  [ "$status" -ne 0 ]
  [[ "$output" == *"disagree about which installs exist"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "a REFUSED run leaves the previous document byte-identical" {
  # The defect this pins is not hypothetical: `render_doc > $DOC_REL` truncates
  # the target BEFORE render_doc runs, so the refusal above -- whose entire
  # purpose is declining to publish a bad document -- destroyed the good one it
  # was declining to replace. The doc went to 0 bytes on an rc-1 run. That is
  # issue 0002's shape (`version set` destroying a sidecar, the gate then
  # certifying it clean) in a command written by someone who had read 0002.
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ]
  local before
  before="$(sha256_of "$PROJ/intent/docs/devbin-users.md")"

  local copy
  copy="$(stub_unstable_scan)"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$copy" doc
  [ "$status" -ne 0 ]

  local after
  after="$(sha256_of "$PROJ/intent/docs/devbin-users.md")"
  [ "$before" = "$after" ]
}

@test "the refusal control can actually be driven -- a stable stub still writes" {
  # THE NEGATIVE CONTROL'S OWN CONTROL. The tests above prove the refusal fires;
  # this proves it is the DISAGREEMENT firing it and not the stub merely
  # breaking the command, which would make them pass vacuously.
  local copy="$DEVBIN_TEST_TMPDIR/fleet-stable"
  {
    sed '/^case "${1:-}" in$/,$d' "$FLEET"
    cat <<'STUB'
scan() {
  printf 'estate\talpha\t0.1.0\tdead\tdig1\t2026-01-01 00:00Z\n'
  printf 'estate\tbeta\t0.1.0\tdead\tdig2\t2026-01-01 00:00Z\n'
}
STUB
    sed -n '/^case "${1:-}" in$/,$p' "$FLEET"
  } > "$copy"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$copy" doc
  [ "$status" -eq 0 ]
  grep -q '^## Estates -- 2$' "$PROJ/intent/docs/devbin-users.md"
}

# ---------------------------------------------------------------------------
# The write (issue 0084). The document is written through replace_file: staged
# beside the file it replaces, never in TMPDIR, with that file's mode, and
# through a link into the file the link names. The render runs first, in the
# handler's own shell, so errexit still stops a render that fails partway and a
# refusal has nothing staged to leave behind.
# ---------------------------------------------------------------------------

# stub_md_table_fails -- a copy of the handler whose table formatter fails after
# the scans have agreed. It leaves a marker, so an arm can tell a render
# that reached the tables from a copy that never ran.
stub_md_table_fails() {
  local copy="$DEVBIN_TEST_TMPDIR/fleet-table-fails"
  {
    sed '/^case "${1:-}" in$/,$d' "$FLEET"
    cat <<STUB
md_table() {
  cat >/dev/null
  : >"$DEVBIN_TEST_TMPDIR/md_table-ran"
  return 1
}
STUB
    sed -n '/^case "${1:-}" in$/,$p' "$FLEET"
  } > "$copy"
  printf '%s\n' "$copy"
}

@test "doc writes through a link to the document, and the link survives (0084)" {
  mkinstall alpha
  mkdir -p "$PROJ/shared"
  printf 'old\n' > "$PROJ/shared/devbin-users.md"
  ln -s ../../shared/devbin-users.md "$PROJ/intent/docs/devbin-users.md"
  run_fleet doc
  [ "$status" -eq 0 ] || fail "doc through a link failed: $output"
  assert_symlink_exists "$PROJ/intent/docs/devbin-users.md" ../../shared/devbin-users.md
  grep -q '^## Estates -- 1$' "$PROJ/shared/devbin-users.md" ||
    fail "the file the link names was not written: $(cat "$PROJ/shared/devbin-users.md")"
  [ "$(ls -A "$PROJ/intent/docs")" = devbin-users.md ] ||
    fail "a file was left beside the link: $(ls -A "$PROJ/intent/docs")"
  [ "$(ls -A "$PROJ/shared")" = devbin-users.md ] ||
    fail "a file was left beside the file the link names: $(ls -A "$PROJ/shared")"
}

@test "doc keeps the document's mode, and a new document takes the umask's, never mktemp's 0600 (0084)" {
  # 0640 under umask 002 tells the three apart: kept is -rw-r-----, the umask's
  # is -rw-rw-r--, and mktemp's is -rw-------, which the document took on every
  # run before, at exit 0. And 002 shows a new file's base through, where under
  # 022 or 027 a base of 0644 and one of 0666 print the same.
  mkinstall alpha
  umask 002
  printf 'old\n' > "$PROJ/intent/docs/devbin-users.md"
  chmod 0640 "$PROJ/intent/docs/devbin-users.md"
  run_fleet doc
  [ "$status" -eq 0 ] || fail "doc failed: $output"
  [ "$(mode_of "$PROJ/intent/docs/devbin-users.md")" = "-rw-r-----" ] ||
    fail "the document's 0640 came out $(mode_of "$PROJ/intent/docs/devbin-users.md")"
  rm "$PROJ/intent/docs/devbin-users.md"
  run_fleet doc
  [ "$status" -eq 0 ] || fail "doc failed: $output"
  [ "$(mode_of "$PROJ/intent/docs/devbin-users.md")" = "-rw-rw-r--" ] ||
    fail "a new document under umask 002 came out $(mode_of "$PROJ/intent/docs/devbin-users.md")"
}

@test "the document ends in the one newline its render does (0084)" {
  # The render is captured before it is written, and a capture drops trailing
  # newlines, so the write puts the one back.
  mkinstall alpha
  run_fleet doc
  [ "$status" -eq 0 ] || fail "doc failed: $output"
  [ "$(tail -c 1 "$PROJ/intent/docs/devbin-users.md" | od -An -tx1 | tr -d ' ')" = 0a ] ||
    fail "the document does not end in a newline"
  [ "$(tail -c 2 "$PROJ/intent/docs/devbin-users.md" | od -An -tx1 | tr -d ' \n' | cut -c1-2)" != 0a ] ||
    fail "the document ends in more than one newline"
}

@test "doc stages the document beside itself, never in TMPDIR (0084)" {
  # A rename is atomic within one filesystem only, and from a TMPDIR on another
  # one mv copies. So a TMPDIR naming no directory at all changes nothing here.
  mkinstall alpha
  run env TMPDIR="$DEVBIN_TEST_TMPDIR/no-such-dir" DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" doc
  [ "$status" -eq 0 ] || fail "doc needed TMPDIR: $output"
  grep -q '^## Estates -- 1$' "$PROJ/intent/docs/devbin-users.md" || fail "the document was not written: $output"
}

@test "a dangling link at the document is refused naming it, and nothing is written (0084)" {
  mkinstall alpha
  ln -s ../../shared/missing.md "$PROJ/intent/docs/devbin-users.md"
  run_fleet doc
  [ "$status" -ne 0 ] || fail "doc replaced a dangling link at exit 0: $output"
  [[ "$output" == *"intent/docs/devbin-users.md is a symbolic link that leads to no file"* ]] ||
    fail "the link was not named: $output"
  [[ "$output" == *"could not write intent/docs/devbin-users.md, which is left as it was"* ]] ||
    fail "the command did not say what it could not do: $output"
  assert_symlink_exists "$PROJ/intent/docs/devbin-users.md" ../../shared/missing.md
  [ ! -e "$PROJ/shared/missing.md" ] || fail "a file was created where the link points"
  [ "$(ls -A "$PROJ/intent/docs")" = devbin-users.md ] ||
    fail "a file was left beside the link: $(ls -A "$PROJ/intent/docs")"
}

@test "a refused doc leaves nothing beside the document (0084)" {
  # render_doc's refusals `die`. Run as replace_file's command they would exit
  # with a temporary already staged beside the document, which is one reason the
  # render runs before anything is staged.
  printf 'previous\n' > "$PROJ/intent/docs/devbin-users.md"
  mkdir "$DEVBIN_TEST_TMPDIR/tmpdir"
  local copy
  copy="$(stub_unstable_scan)"
  run env TMPDIR="$DEVBIN_TEST_TMPDIR/tmpdir" DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$copy" doc
  [ "$status" -ne 0 ] || fail "the unstable scan was not refused: $output"
  [[ "$output" == *"disagree about which installs exist"* ]] || fail "refused for another reason: $output"
  [ "$(cat "$PROJ/intent/docs/devbin-users.md")" = previous ] || fail "the document was changed"
  [ "$(ls -A "$PROJ/intent/docs")" = devbin-users.md ] ||
    fail "a refused run left a file beside the document: $(ls -A "$PROJ/intent/docs")"
  [ -z "$(ls -A "$DEVBIN_TEST_TMPDIR/tmpdir")" ] ||
    fail "a refused run left a file in TMPDIR: $(ls -A "$DEVBIN_TEST_TMPDIR/tmpdir")"
}

@test "a render that fails after the scans agree is refused, and the document is left as it was (0084)" {
  # render_doc checks its scans and leans on errexit for the rest, and bash
  # ignores errexit for a whole function run inside a condition. As
  # replace_file's command the render ran inside one, and a document without its
  # tables was published at exit 0 (measured 2026-09-17).
  mkinstall alpha
  printf 'previous\n' > "$PROJ/intent/docs/devbin-users.md"
  mkdir "$DEVBIN_TEST_TMPDIR/tmpdir"
  local copy
  copy="$(stub_md_table_fails)"
  run env TMPDIR="$DEVBIN_TEST_TMPDIR/tmpdir" DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$copy" doc
  [ -e "$DEVBIN_TEST_TMPDIR/md_table-ran" ] || fail "the render never reached the tables, so this drove nothing: $output"
  [ "$status" -ne 0 ] || fail "a render whose tables failed exited 0: $output"
  [ "$(cat "$PROJ/intent/docs/devbin-users.md")" = previous ] ||
    fail "a render that failed replaced the document: $(cat "$PROJ/intent/docs/devbin-users.md")"
  [ "$(ls -A "$PROJ/intent/docs")" = devbin-users.md ] ||
    fail "a file was left beside the document: $(ls -A "$PROJ/intent/docs")"
  [ -z "$(ls -A "$DEVBIN_TEST_TMPDIR/tmpdir")" ] ||
    fail "a file was left in TMPDIR: $(ls -A "$DEVBIN_TEST_TMPDIR/tmpdir")"
}

# mkinstall_dirty <path-under-roots> -- an install whose manifest records what
# `install` ACTUALLY writes when the source tree's seam was dirty at vendor
# time. Not an invented format: `source_commit_of` prints exactly this at
# lib/install:273, and issue 0033 is the reason the marker exists at all.
mkinstall_dirty() {
  local d="$ROOTS/$1"
  mkdir -p "$d/bin/.devbin/lib"
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$d/bin/devbin"
  printf 'lib bytes for %s\n' "$1" > "$d/bin/.devbin/lib/helpers"
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: deadbeefcafe1234 +dirty -- THESE BYTES MATCH NO COMMIT\n' \
    > "$d/bin/.devbin/manifest.sha256"  vouch "$1"
}

@test "audit does not render a DIRTY source_commit as a clean commit" {
  mkinstall_dirty smudged
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(printf '%s\n' "$output" | awk -F'\t' '$2 ~ /smudged$/ { print $4 }')"
  [ -n "$field" ] || fail "no estate row for smudged -- the test's own vehicle is broken"
  # The manifest says these bytes match NO commit. Truncating that to twelve
  # characters prints a bare sha, which says the opposite and says it with
  # confidence. A provenance column that cannot express "unknown" is worse
  # than no column.
  [[ "$field" == *dirty* ]] || fail "provenance reads '$field' -- the manifest said these bytes match NO commit"
}

@test "the DOCUMENT does not render a DIRTY source_commit as a clean commit" {
  mkinstall_dirty smudged
  mkinstall cleanproj
  run_fleet doc
  [ "$status" -eq 0 ]
  local row
  row="$(grep 'smudged' "$PROJ/intent/docs/devbin-users.md" || true)"
  [ -n "$row" ] || fail "smudged is absent from the document the scan just wrote"
  [[ "$row" == *dirty* ]] || fail "document row reads '$row' -- it presents unprovenanced bytes as provenanced"
  # The control: a genuinely clean estate must NOT pick up the marker, or the
  # test above would pass against an implementation that flags everything.
  local clean
  clean="$(grep 'cleanproj' "$PROJ/intent/docs/devbin-users.md" || true)"
  [[ "$clean" != *dirty* ]] || fail "a CLEAN estate was flagged dirty -- the flag carries no information"
}

# ===========================================================================
# IS THE SEAM COMMITTED (issue 0056)
# ===========================================================================
#
# Every column above answers "what bytes are on this machine". Readers used the
# census to answer "what is the fleet running", and those diverge the moment a
# re-vendor is not committed: three estates were in that state the day 0056 was
# filed and the census reported none of them. The column added for it must
# never let an ABSENT answer read as a clean one, so most arms below assert a
# refusal to say `committed`.

# mkinstall_committed <path-under-roots> -- mkinstall, then that install made a
# repository of its own with everything committed.
mkinstall_committed() {
  mkinstall "$1"
  git -C "$ROOTS/$1" init -q
  git -C "$ROOTS/$1" add -A
  git -C "$ROOTS/$1" -c user.email=t@t -c user.name=t commit -q -m fixture
}

# committed_field <name> -- the audit's seam-committed column for one install.
committed_field() {
  printf '%s\n' "$output" | awk -F'\t' -v n="$1" '$2 ~ ("/" n "$") { print $7 }'
}

@test "audit reports a seam committed in its own repository as committed" {
  mkinstall_committed tidy
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field tidy)"
  [ -n "$field" ] || fail "no seam-committed column for tidy in: $output"
  [ "$field" = committed ] || fail "a fully committed seam reads '$field'"
}

@test "a re-vendor that was never committed reads DIRTY, not level" {
  # The Gtools-geodica shape, reported by gtools-vc on 2026-09-14: a sync moved
  # ONLY the manifest's source_commit, every file hash unchanged, and it sat
  # uncommitted for three days while the census had no column that could say so.
  mkinstall_committed moved
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: 0123456789abcdef\n' \
    > "$ROOTS/moved/bin/.devbin/manifest.sha256"
  vouch moved
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field moved)"
  [ "$field" = DIRTY ] || fail "an uncommitted re-vendor reads '$field'"
}

@test "a vendored file deleted and not committed reads DIRTY" {
  # Why the pathspec is the seam's DIRECTORY and never a list of names found on
  # disk: a deleted file is no longer found, so a name list would ask git only
  # about the survivors and hear clean (usage-rules.md, The seam).
  mkinstall_committed pruned
  rm "$ROOTS/pruned/bin/.devbin/lib/helpers"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field pruned)"
  [ "$field" = DIRTY ] || fail "a deleted vendored file reads '$field'"
}

@test "an install that is not a git checkout says so, and never reads committed" {
  mkinstall loose
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field loose)"
  [ "$field" = "not a checkout" ] || fail "an install with no repository reads '$field'"
}

@test "an install inside SOMEBODY ELSE's ignored directory does not read committed" {
  # A deps/ checkout that is not a repository of its own lives in its host's
  # tree, where the host ignores deps/. `git status` there prints nothing for an
  # ignored path, which is exactly the output a clean seam produces.
  local host="$ROOTS/host"
  mkdir -p "$host"
  git -C "$host" init -q
  printf 'deps/\n' > "$host/.gitignore"
  git -C "$host" add -A
  git -C "$host" -c user.email=t@t -c user.name=t commit -q -m host
  mkinstall host/deps/vendored
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field vendored)"
  [ "$field" = "not its own checkout" ] || fail "an install inside another repository reads '$field'"
}

@test "a committed seam with a directory the symlink scan cannot search reads UNREADABLE, never committed (0145)" {
  # seam_git_state looks for links beneath each seam path; macOS's find passed
  # over a directory it could list but not search, mode 0644, at rc 0, so a
  # link there went unseen and the cell read committed.
  mkinstall shutseam
  local d="$ROOTS/shutseam" field
  mkdir -p "$d/bin/.devbin/lib/pages"
  printf 'a page\n' >"$d/bin/.devbin/lib/pages/one.md"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m shutseam
  # THE CONTROL: readable, committed.
  run_fleet audit
  [ "$(committed_field shutseam)" = committed ] || fail "the control does not read committed: $output"
  chmod 644 "$d/bin/.devbin/lib/pages"
  if [ -x "$d/bin/.devbin/lib/pages" ]; then
    chmod 755 "$d/bin/.devbin/lib/pages"
    skip "running with permissions that search a mode-644 directory: NOT checked"
  fi
  run_fleet audit
  field="$(committed_field shutseam)"
  chmod 755 "$d/bin/.devbin/lib/pages"
  [ "$field" = UNREADABLE ] || fail "a seam the scan could not search reads '$field'"
}

@test "a seam its own repository does not track reads not tracked, not committed" {
  # The same silence from the other side: the install IS a repository root, but
  # it ignores bin/, so status says nothing about the seam because it is not
  # watching it.
  mkinstall ignoring
  local d="$ROOTS/ignoring"
  git -C "$d" init -q
  printf 'bin/\n' > "$d/.gitignore"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m ignoring
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field ignoring)"
  [ "$field" = "not tracked" ] || fail "an untracked seam reads '$field'"
}

@test "a seam whose LIB is ignored reads not tracked, although bin/devbin and the manifest are committed" {
  # critic-shell on the first cut: a `.gitignore` carrying `lib/` leaves the
  # launcher and the manifest tracked and the runtime never committed, and a
  # check that asked only whether the manifest was tracked said `committed`.
  mkinstall halfignored
  local d="$ROOTS/halfignored"
  git -C "$d" init -q
  printf 'lib/\n' > "$d/.gitignore"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m halfignored
  git -C "$d" ls-files --error-unmatch bin/.devbin/manifest.sha256 >/dev/null ||
    fail "the fixture did not commit the manifest -- this arm is not testing the half-ignored case"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field halfignored)"
  [ "$field" = "not tracked" ] || fail "a seam with an ignored lib reads '$field'"
}

@test "an untracked file under the seam reads DIRTY even when the estate's repo hides untracked files" {
  # The shape that hid one -- an untracked bin/.devbin/lib/cmd/fullcycle -- under
  # `status.showUntrackedFiles=no`, which made plain `git status` print nothing.
  mkinstall_committed hiding
  git -C "$ROOTS/hiding" config status.showUntrackedFiles no
  printf 'new\n' > "$ROOTS/hiding/bin/.devbin/lib/fullcycle"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field hiding)"
  [ "$field" = DIRTY ] || fail "an untracked seam file under showUntrackedFiles=no reads '$field'"
}

@test "an untracked file under the seam reads DIRTY when the CALLER's git -c ignores every file" {
  # A setting `--untracked-files=all` does NOT override, or this arm pins nothing
  # the flags do not already (critic-shell, 2026-09-16): a caller's excludesFile
  # of `*` would turn the untracked file ignored, and DIRTY into `not tracked`.
  mkinstall_committed callerhides
  printf 'new\n' > "$ROOTS/callerhides/bin/.devbin/lib/fullcycle"
  printf '*\n' > "$DEVBIN_TEST_TMPDIR/ignore-all"
  run env GIT_CONFIG_PARAMETERS="'core.excludesfile=$DEVBIN_TEST_TMPDIR/ignore-all'" \
    DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field callerhides)"
  [ "$field" = DIRTY ] || fail "a caller's git -c silenced an untracked seam file: '$field'"
}

@test "an inherited GIT_DIR or GIT_COMMON_DIR does not answer for every estate" {
  # One value from the caller's environment would point every estate's question
  # at ONE repository. The first cut cleared three of git's fifteen local
  # variables; GIT_COMMON_DIR alone turned every estate UNREADABLE.
  mkinstall_committed ownrepo
  local other="$DEVBIN_TEST_TMPDIR/otherrepo"
  mkdir -p "$other"
  git -C "$other" init -q
  run env GIT_DIR="$other/.git" GIT_COMMON_DIR="$other/.git" \
    DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field ownrepo)"
  [ "$field" = committed ] || fail "an inherited git environment changed a committed estate's answer to '$field'"
}

@test "a seam edit hidden by assume-unchanged reads not watched, never committed" {
  # git reports a file it has been told not to look at as clean. That is git
  # declining to read it, not the file being committed.
  mkinstall_committed blinkered
  git -C "$ROOTS/blinkered" update-index --assume-unchanged bin/.devbin/lib/helpers
  printf 'edited\n' >> "$ROOTS/blinkered/bin/.devbin/lib/helpers"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field blinkered)"
  [ "$field" = "not watched" ] || fail "an assume-unchanged edit reads '$field'"
}

@test "a seam edit hidden by skip-worktree reads not watched, never committed" {
  mkinstall_committed skipping
  git -C "$ROOTS/skipping" update-index --skip-worktree bin/.devbin/lib/helpers
  printf 'edited\n' >> "$ROOTS/skipping/bin/.devbin/lib/helpers"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field skipping)"
  [ "$field" = "not watched" ] || fail "a skip-worktree edit reads '$field'"
}

@test "an assume-unchanged mark on a LATER line of ls-files still reads not watched" {
  # bin/devbin sorts after bin/.devbin/..., so its tag is the last line.
  mkinstall_committed latemark
  git -C "$ROOTS/latemark" update-index --assume-unchanged bin/devbin
  printf 'edited\n' >> "$ROOTS/latemark/bin/devbin"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field latemark)"
  [ "$field" = "not watched" ] || fail "a later-line assume-unchanged edit reads '$field'"
}

@test "an ignored seam file on a LATER line still reads not tracked" {
  mkinstall_committed lateignore
  local d="$ROOTS/lateignore"
  printf '*.orig\n' > "$d/.gitignore"
  git -C "$d" add .gitignore
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m ignore
  printf 'a\n' > "$d/bin/.devbin/lib/a.orig"
  printf 'z\n' > "$d/bin/.devbin/lib/z.orig"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field lateignore)"
  [ "$field" = "not tracked" ] || fail "ignored seam files read '$field'"
}

@test "an ignored file does not HIDE a real edit -- DIRTY is said first" {
  # A global gitignore carrying .DS_Store is every Mac: one Finder visit put an
  # ignored file beside the edit, and `not tracked` was checked first.
  mkinstall_committed finder
  local d="$ROOTS/finder"
  printf '.DS_Store\n' > "$d/.gitignore"
  git -C "$d" add .gitignore
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m ignore
  printf 'x' > "$d/bin/.devbin/lib/.DS_Store"
  printf 'edited\n' >> "$d/bin/.devbin/lib/helpers"
  run_fleet audit
  [ "$status" -eq 0 ]
  local field
  field="$(committed_field finder)"
  [ "$field" = DIRTY ] || fail "an edit beside an ignored file reads '$field'"
}

@test "an estate's OWN lib/ does not answer for a deleted vendored lib" {
  # The Elixir shape: the project keeps its code in lib/ at the root. The scope
  # used to fall back to that lib/ when bin/.devbin/lib was not a directory, so
  # a vendored lib deleted and not committed read committed.
  mkinstall elixirish
  local d="$ROOTS/elixirish"
  mkdir -p "$d/lib"
  printf 'defmodule X do end\n' > "$d/lib/x.ex"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m fixture
  rm -rf "$d/bin/.devbin/lib"
  run_fleet audit
  [ "$status" -ne 0 ] || fail "a scan over a missing seam exited 0: $output"
  local field
  field="$(committed_field elixirish)"
  [ "$field" = UNREADABLE ] || fail "a deleted vendored lib beside the project's own lib/ reads '$field'"
}

@test "a vendored lib replaced by a committed SYMLINK reads not tracked" {
  # git records the link's text; the bytes behind it are what runs and what the
  # digest reads, and a change to them is invisible to status.
  mkinstall linked
  local d="$ROOTS/linked" real="$DEVBIN_TEST_TMPDIR/reallib"
  mv "$d/bin/.devbin/lib" "$real"
  ln -s "$real" "$d/bin/.devbin/lib"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m fixture
  printf 'edited\n' >> "$real/helpers"
  run_fleet audit
  local field
  field="$(committed_field linked)"
  [ "$field" = "not tracked" ] || fail "a symlinked vendored lib reads '$field'"
}

@test "a LAUNCHER that is a committed symlink reads not tracked" {
  mkinstall linkedlauncher
  local d="$ROOTS/linkedlauncher" real="$DEVBIN_TEST_TMPDIR/reallauncher"
  mv "$d/bin/devbin" "$real"
  ln -s "$real" "$d/bin/devbin"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m fixture
  printf 'echo edited\n' >> "$real"
  run_fleet audit
  local field
  field="$(committed_field linkedlauncher)"
  [ "$field" = "not tracked" ] || fail "a symlinked launcher reads '$field'"
}

@test "an install whose LAUNCHER is gone has no digest, rather than a digest of its lib alone" {
  mkinstall_committed nolauncher
  rm "$ROOTS/nolauncher/bin/devbin"
  run_fleet audit
  [ "$status" -ne 0 ] || fail "an audit over a missing launcher exited 0: $output"
  local rows
  rows="$(awk -F'\t' '$2 ~ /\/nolauncher$/ && $5 == "UNREADABLE"' <<<"$output")"
  grep -q . <<<"$rows" ||
    fail "the row for nolauncher does not carry an UNREADABLE digest: $output"
}

@test "a submodule's own ignore setting does not hide an edit to the seam" {
  mkinstall sub
  local d="$ROOTS/sub" libsrc="$DEVBIN_TEST_TMPDIR/libsrc"
  mv "$d/bin/.devbin/lib" "$libsrc"
  git -C "$libsrc" init -q
  git -C "$libsrc" add -A
  git -C "$libsrc" -c user.email=t@t -c user.name=t commit -q -m lib
  git -C "$d" init -q
  git -C "$d" -c protocol.file.allow=always submodule add -q "$libsrc" bin/.devbin/lib >/dev/null 2>&1 ||
    fail "the fixture could not add the submodule"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m fixture
  git -C "$d" config -f .gitmodules submodule.bin/.devbin/lib.ignore all
  git -C "$d" config diff.ignoreSubmodules all
  git -C "$d" add .gitmodules
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m ignore
  printf 'edited\n' >> "$d/bin/.devbin/lib/helpers"
  [ -z "$(git -C "$d" status --porcelain)" ] || fail "the fixture's ignore setting does not hide the edit -- this arm tests nothing"
  run_fleet audit
  local field
  field="$(committed_field sub)"
  [ "$field" = DIRTY ] || fail "an edit inside an ignored submodule seam reads '$field'"
}

@test "the estate's core.fsmonitor hook is never run by the census" {
  mkinstall_committed monitored
  local d="$ROOTS/monitored" hook="$DEVBIN_TEST_TMPDIR/fsmonitor-hook"
  printf '#!/bin/sh\ntouch "%s/fsmonitor-ran"\nexit 1\n' "$DEVBIN_TEST_TMPDIR" > "$hook"
  chmod +x "$hook"
  git -C "$d" config core.fsmonitor "$hook"
  git -C "$d" status >/dev/null 2>&1 || true
  [ -e "$DEVBIN_TEST_TMPDIR/fsmonitor-ran" ] || skip "this git does not run a core.fsmonitor hook"
  rm -f "$DEVBIN_TEST_TMPDIR/fsmonitor-ran"
  run_fleet audit
  [ ! -e "$DEVBIN_TEST_TMPDIR/fsmonitor-ran" ] || fail "the census ran an estate's fsmonitor hook"
}

@test "a repository git cannot read is UNREADABLE and fails the scan, never 'not a checkout'" {
  mkinstall_committed corrupt
  printf 'garbage\n' > "$ROOTS/corrupt/.git/HEAD"
  mkinstall_committed intact
  run_fleet audit
  [ "$status" -ne 0 ] || fail "a scan with an unreadable repository exited 0: $output"
  local field
  field="$(committed_field corrupt)"
  [ "$field" = UNREADABLE ] || fail "a corrupt repository reads '$field'"
  [[ "$output" == *"git could not say whether the seam of $ROOTS/corrupt is committed"* ]] ||
    fail "the unreadable estate was not named: $output"
  [ "$(committed_field intact)" = committed ] || fail "the intact estate was not still reported"
}

@test "an estate whose .git is a dangling link is UNREADABLE, never 'not a checkout' (0185)" {
  # git says "not a git repository" here, the words the census used to read;
  # the filesystem says a .git is there, so git failing is not an answer.
  mkinstall_committed intact
  mkinstall dangling
  ln -s "$DEVBIN_TEST_TMPDIR/nowhere" "$ROOTS/dangling/.git"
  run_fleet audit
  [ "$status" -ne 0 ] || fail "a scan with an unreadable estate exited 0: $output"
  local field
  field="$(committed_field dangling)"
  [ "$field" = UNREADABLE ] || fail "a dangling .git link reads '$field'"
  [ "$(committed_field intact)" = committed ] || fail "the intact estate was not still reported"
}

@test "an estate git refuses to read is UNREADABLE, and one below a repository git refuses is not its own checkout (0185)" {
  # The issue's own fleet case. GIT_TEST_ASSUME_DIFFERENT_OWNER=1 marks every
  # repository another user's. The estate with a .git of its own cannot be
  # answered for and fails the scan; the one whose only .git is above it is not
  # its own checkout whatever git would say of that repository.
  mkinstall_committed refused
  local host="$ROOTS/host"
  mkdir -p "$host"
  git -C "$host" init -q
  git -C "$host" -c user.email=t@t -c user.name=t commit -q --allow-empty -m host
  mkinstall host/nested
  require_git_refusal "$ROOTS/refused"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run_fleet audit
  [ "$status" -ne 0 ] || fail "a scan with a refused estate exited 0: $output"
  local field
  field="$(committed_field refused)"
  [ "$field" = UNREADABLE ] || fail "an estate git refuses reads '$field'"
  [[ "$output" == *"git could not say whether the seam of $ROOTS/refused is committed"* ]] ||
    fail "the refused estate was not named: $output"
  field="$(committed_field nested)"
  [ "$field" = "not its own checkout" ] || fail "an estate below a refused repository reads '$field'"
}

@test "an estate below a .git that GIT_CEILING_DIRECTORIES hides is not a checkout, and the scan passes (0185)" {
  # git stops below a ceiling and says there is no repository; the census had
  # read any .git above as one git could not read, and failed the scan.
  local home="$ROOTS/home"
  mkdir -p "$home"
  git -C "$home" init -q
  mkinstall home/plain
  GIT_CEILING_DIRECTORIES="$home" run_fleet audit
  [ "$status" -eq 0 ] || fail "a scan with an estate below a hidden .git failed: $output"
  local field
  field="$(committed_field plain)"
  [ "$field" = "not a checkout" ] || fail "an estate below a hidden .git reads '$field'"
  # The control: without the ceiling git reads the repository above.
  run_fleet audit
  field="$(committed_field plain)"
  [ "$field" = "not its own checkout" ] || fail "without the ceiling the estate reads '$field'"
}

@test "an estate below an empty .git never fails the scan as UNREADABLE (0185)" {
  # git passes over a .git that is no repository and says there is none. The
  # walk does not, and the census says `not its own checkout`, the declared
  # limit; `not a checkout` would be as true. What is required is that it is
  # one of the two, and that the scan passes.
  mkdir -p "$ROOTS/hollow/.git"
  mkinstall hollow/plain
  run_fleet audit
  [ "$status" -eq 0 ] || fail "a scan with an estate below an empty .git failed: $output"
  local field
  field="$(committed_field plain)"
  case "$field" in
    "not a checkout" | "not its own checkout") ;;
    *) fail "an estate below an empty .git reads '$field'" ;;
  esac
}

@test "a census root that cannot be entered is UNREADABLE, never not its own checkout (0185)" {
  # `not its own checkout` is said of a root whose only .git is above it. A root
  # that vanished, or was locked, between the walk and the census is neither.
  local lib="$DEVBIN_TEST_TMPDIR/fleet-lib"
  sed '/^case "${1:-}" in$/,$d' "$FLEET" >"$lib"
  mkdir -p "$ROOTS/locked"
  lock "$ROOTS/locked"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" \
    bash -c '. "$1" && seam_committed "$2" && seam_committed "$3"' _ "$lib" "$ROOTS/gone" "$ROOTS/locked"
  chmod 755 "$ROOTS/locked"
  assert_success
  [ "$output" = "UNREADABLE
UNREADABLE" ] || fail "a removed root and a locked one read: $output"
}

@test "with no git to ask, an estate with no .git is not a checkout and one with its own is UNREADABLE (0185)" {
  # A git that exits 127, as a missing one does, so every git call fails.
  mkinstall_committed own
  mkinstall loose
  local stub="$DEVBIN_TEST_TMPDIR/nogit"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 127\n' >"$stub/git"
  chmod +x "$stub/git"
  PATH="$stub:$PATH" run_fleet audit
  [ "$status" -ne 0 ] || fail "a scan that could not ask git about an estate's own .git exited 0: $output"
  local field
  field="$(committed_field loose)"
  [ "$field" = "not a checkout" ] || fail "an estate with no .git reads '$field' with no git to ask"
  field="$(committed_field own)"
  [ "$field" = UNREADABLE ] || fail "an estate with its own .git reads '$field' with no git to ask"
}

@test "an unreadable manifest reads UNREADABLE and fails the scan, never UNRECORDED" {
  mkinstall locked
  local m="$ROOTS/locked/bin/.devbin/manifest.sha256"
  chmod 000 "$m"
  if [ -r "$m" ]; then
    chmod 644 "$m"
    skip "running with permissions that read a mode-000 file"
  fi
  run_fleet audit
  chmod 644 "$m"
  [ "$status" -ne 0 ] || fail "a scan over an unreadable manifest exited 0: $output"
  [[ "$output" != *UNRECORDED* ]] || fail "an unreadable manifest read UNRECORDED: $output"
  [[ "$output" == *"could not read the manifest of $ROOTS/locked"* ]] || fail "the manifest was not named: $output"
}

@test "an install whose lib is gone is named and fails the audit, and its row is still printed" {
  mkinstall_committed libgone
  mkinstall_committed whole
  rm -rf "$ROOTS/libgone/bin/.devbin/lib"
  run_fleet audit
  [ "$status" -ne 0 ] || fail "an audit over a missing seam exited 0: $output"
  [[ "$output" == *"could not digest the seam of $ROOTS/libgone"* ]] || fail "the missing seam was not named: $output"
  local rows
  rows="$(awk -F'\t' '$2 ~ /\/libgone$/ && $5 == "UNREADABLE"' <<<"$output")"
  grep -q . <<<"$rows" ||
    fail "the row for libgone does not carry an UNREADABLE digest: $output"
  [ "$(committed_field whole)" = committed ] || fail "the whole estate was not still reported"
}

@test "doc REFUSES when a scan fails PARTWAY, not only at find, and leaves the document alone" {
  # The doc path runs scan under `||`, which turns errexit off inside it: a step
  # that failed there was skipped and a row digesting the launcher alone was
  # published at exit 0 (critic-shell, 2026-09-16).
  mkinstall_committed libgone
  rm -rf "$ROOTS/libgone/bin/.devbin/lib"
  printf 'previous document\n' > "$PROJ/intent/docs/devbin-users.md"
  run_fleet doc
  [ "$status" -ne 0 ] || fail "doc published from a scan that failed partway: $output"
  [[ "$output" == *"refusing to write intent/docs/devbin-users.md from an incomplete scan"* ]] ||
    fail "the refusal did not say why: $output"
  [ "$(cat "$PROJ/intent/docs/devbin-users.md")" = "previous document" ] || fail "the existing document was overwritten"
}

@test "a churning directory under a PRUNED name never fails the scan" {
  # The prune list was a filter: find still walked _build, so an unreadable or
  # vanishing directory inside it failed a scan that had nothing to find there.
  mkinstall_committed building
  mkdir -p "$ROOTS/building/_build/locked"
  chmod 000 "$ROOTS/building/_build/locked"
  if [ -r "$ROOTS/building/_build/locked" ]; then
    chmod 755 "$ROOTS/building/_build/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  run_fleet audit
  chmod 755 "$ROOTS/building/_build/locked"
  [ "$status" -eq 0 ] || fail "an unreadable directory under a pruned name failed the scan: $output"
}

@test "the scan asks git for its local variable list ONCE, however many estates it reads" {
  # The list was cached inside `$(...)`, so every call asked again: three asks
  # per estate while the comment said once per process (vc, 2026-09-16).
  mkinstall_committed countone
  mkinstall_committed counttwo
  mkinstall_committed countthree
  local wrap="$DEVBIN_TEST_TMPDIR/gitwrap" real
  real="$(command -v git)"
  mkdir -p "$wrap"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/git.calls"\nexec "%s" "$@"\n' "$DEVBIN_TEST_TMPDIR" "$real" >"$wrap/git"
  chmod +x "$wrap/git"
  run env PATH="$wrap:$PATH" DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  [ "$status" -eq 0 ] || fail "the audit failed: $output"
  [ "$(committed_field countthree)" = committed ] || fail "the wrapper changed an answer: $output"
  local asks
  asks="$(grep -c -- '--local-env-vars' "$DEVBIN_TEST_TMPDIR/git.calls" || true)"
  [ "$asks" -eq 1 ] || fail "the scan asked for the variable list $asks times over three estates"
}

@test "a root that cannot be read in full is NAMED and fails the audit, and the other roots are still scanned (0145)" {
  # critic-shell, beside the first cut: one unreadable directory under the first
  # root ended the scan before the second root, at exit 0, with no message.
  local r1="$DEVBIN_TEST_TMPDIR/rootone" r2="$DEVBIN_TEST_TMPDIR/roottwo"
  mkdir -p "$r1/locked/inner" "$r2"
  ROOTS="$r1" mkinstall first
  ROOTS="$r2" mkinstall second
  chmod 000 "$r1/locked"
  if [ -r "$r1/locked" ]; then
    chmod 755 "$r1/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  run env DEVBIN_FLEET_ROOTS="$r1 $r2" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  chmod 755 "$r1/locked"
  [ "$status" -ne 0 ] || fail "an incomplete scan exited 0: $output"
  [[ "$output" == *"could not read all of $r1"* ]] || fail "the incomplete root was not named: $output"
  [[ "$output" == *"/roottwo/second"* ]] || fail "the second root was not scanned: $output"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and an install beneath it was missing unsaid.
  chmod 644 "$r1/locked"
  run env DEVBIN_FLEET_ROOTS="$r1 $r2" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit
  chmod 755 "$r1/locked"
  [ "$status" -ne 0 ] || fail "a scan over a directory it could not search exited 0: $output"
  [[ "$output" == *"cannot search $r1/locked -- nothing beneath it was looked at"* ]] || fail "the directory was not named: $output"
  [[ "$output" == *"could not read all of $r1"* ]] || fail "the incomplete root was not named: $output"
}

@test "doc REFUSES to publish from an incomplete scan, and leaves the existing document alone" {
  local r1="$DEVBIN_TEST_TMPDIR/rootone"
  mkdir -p "$r1/locked"
  ROOTS="$r1" mkinstall first
  chmod 000 "$r1/locked"
  if [ -r "$r1/locked" ]; then
    chmod 755 "$r1/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  printf 'previous document\n' > "$PROJ/intent/docs/devbin-users.md"
  run env DEVBIN_FLEET_ROOTS="$r1" PROJECT_ROOT="$PROJ" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" doc
  chmod 755 "$r1/locked"
  [ "$status" -ne 0 ] || fail "doc published from an incomplete scan"
  [ "$(cat "$PROJ/intent/docs/devbin-users.md")" = "previous document" ] || fail "the existing document was overwritten"
}

@test "a DIRTY estate does not make doc refuse, and the document says which is which" {
  # The column REPORTS and never judges: an estate can be dirty by ruling and frozen,
  # and a census that would not publish while a ruled exception exists is one
  # nobody can run.
  mkinstall_committed unsaved
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: 0123456789abcdef\n' \
    > "$ROOTS/unsaved/bin/.devbin/manifest.sha256"
  vouch unsaved
  mkinstall_committed saved
  run_fleet doc
  [ "$status" -eq 0 ]
  local row clean
  row="$(grep 'unsaved' "$PROJ/intent/docs/devbin-users.md" || true)"
  [ -n "$row" ] || fail "unsaved is absent from the document"
  [[ "$row" == *DIRTY* ]] || fail "the document row for an uncommitted seam reads '$row'"
  # The control: the committed estate must not pick the flag up, or the arm
  # above passes against a column that says DIRTY for everything.
  # `/saved` then padding then a cell edge, rather than `saved`: every `unsaved`
  # row contains `saved`, the path column is absolute so the name follows a
  # slash, and md_table pads each cell to its column's width.
  clean="$(grep -E '/saved +[|]' "$PROJ/intent/docs/devbin-users.md" || true)"
  [ -n "$clean" ] || fail "saved is absent from the document"
  [[ "$clean" != *DIRTY* ]] || fail "a committed estate was flagged DIRTY"
  [[ "$clean" == *committed* ]] || fail "the committed estate's row reads '$clean'"
  # The caveat says what is measured and nothing more: HEAD, not a clone.
  grep -q "matches this checkout's HEAD" "$PROJ/intent/docs/devbin-users.md" ||
    fail "the caveat does not say the comparison is with this checkout's HEAD"
  ! grep -q "a clone gets" "$PROJ/intent/docs/devbin-users.md" ||
    fail "the caveat still promises what a clone gets"
}

# ===========================================================================
# THE SWEEP (ST0005 WP-03)
# ===========================================================================
#
# WHAT IT DISTRIBUTES IS THE INSTALL'S BYTES, NOT THE DEV TREE'S. That is the
# whole point of the install existing: the sweep runs from the dev tree, because
# `fleet` lives in devbin's project half rather than in the vendored runtime, but
# what lands on an estate can only ever have come from a tree the dirty gate let
# through.
#
# EVERY ARM BELOW EITHER ASSERTS A REFUSAL TO WRITE OR ASSERTS THAT SOMETHING
# EXCLUDED WAS NAMED. A whole-of-estate write is fleet-blast-radius, so the
# dangerous direction is a sweep that does more than it said, and the silent
# direction is a sweep that does less than it said without saying so.

# mkinstall_prefix -- a machine install for the sweep to distribute FROM.
mkinstall_prefix() {
  local d="$DEVBIN_TEST_TMPDIR/opt/devbin"
  # Written by the one stub writer (0288).
  stub_install "$d" /nowhere || return 1
  # The link names it, as `devbin use opt` leaves it (0213): the sweep
  # distributes the install the switch names.
  switch_to "$d"
  printf '%s\n' "$d"
}

# mkestate <path> -- as mkinstall, but with an EXECUTABLE launcher.
#
# The sweep tests reachability with `-x`, matching the `dvb` shell function the
# operator drives devbin through: it runs a launcher that is -x and reports one
# that is merely -f as a problem. `mkinstall` above writes a launcher with no
# execute bit because the AUDIT never runs one -- it only reads manifests -- so
# the sweep needs its own fixture rather than a changed shared one.
mkestate() {
  mkinstall "$1"
  chmod +x "$ROOTS/$1/bin/devbin"
}

# mkworktree <path> -- make <path> a REAL linked git worktree, of a repository
# kept outside every scan root's installs. Call it BEFORE mkinstall/mkestate,
# which then populate it: `git worktree add` wants a path that does not exist.
#
# The fixtures used to model a worktree as any directory under `.worktrees/`,
# the same proxy the scan used, so they could not catch it missing a worktree
# kept anywhere else -- Intent/tmp/wt-0516 was swept on 2026-09-22. A hand-made
# `.git` file was tried first and was wrong the other way: its gitdir did not
# exist, so audit asked git about the seam and correctly failed.
mkworktree() {
  local repo="$ROOTS/elsewhere"
  if [ ! -d "$repo/.git" ]; then
    git init -q "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  fi
  mkdir -p "$(dirname "$ROOTS/$1")"
  git -C "$repo" worktree add -q --detach "$ROOTS/$1"
}

# A devbin config for the sweep's own project, naming the prefix.
#
# CALLED WITH NO ARGUMENT IT OMITS THE KEY, which is a state the sweep has to
# have an answer for now that `lib/install` carries no baked default to fall
# through to. One builder with a switch rather than a near-identical sibling:
# two spellings of "devbin's own config" is how the two come to disagree about
# everything except the line under test (IN-AG-HIGHLANDER-001).
mkproj_cfg() {
  mkdir -p "$PROJ/bin/.devbin"
  printf 'project:\n  name: devbin\ndevbin_version: "^0.1.0"\n' \
    > "$PROJ/bin/.devbin/config.yaml"
  # An `if`, not `[ -n ... ] && printf`: bats runs a test body under errexit and
  # the AND-list is the final command of its own statement, so the no-argument
  # call would abort the test rather than omit the key.
  if [ -n "${1:-}" ]; then
    printf 'install:\n  prefix: %s\n' "$1" >> "$PROJ/bin/.devbin/config.yaml"
  fi
}

run_sweep() {
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade "$@"
}

@test "the sweep REFUSES an incomplete scan rather than dropping the estates it could not reach (0056)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkdir -p "$ROOTS/locked"
  chmod 000 "$ROOTS/locked"
  if [ -r "$ROOTS/locked" ]; then
    chmod 755 "$ROOTS/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  run_sweep
  chmod 755 "$ROOTS/locked"
  assert_failure
  assert_output_contains "incomplete scan"
  refute_output_contains "DRY RUN"
}

# AT-3.1
@test "the sweep is DRY RUN by default and writes nothing at all" {
  # THE ARM THAT MATTERS MOST. Applying is fleet-blast-radius, so the default
  # must be the one that cannot damage anything.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  before="$(sha256_of "$ROOTS/alpha/bin/.devbin/manifest.sha256")"
  run_sweep
  assert_success
  assert_output_contains "DRY RUN"
  assert_output_contains "Nothing was written"
  [ "$(sha256_of "$ROOTS/alpha/bin/.devbin/manifest.sha256")" = "$before" ]
}

# AT-3.1
@test "the plan NAMES what it would do, so the dry run is readable not merely safe" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_output_contains "alpha"
  assert_output_contains "upgrade + repoint"
  assert_output_contains "fleet upgrade --apply"
}

# The control for the arms below, and the first arm to reach `level` at all: an
# estate already vendored from the prefix, at the prefix's commit.
@test "an estate at the prefix's commit that records install is LEVEL (0153)" {
  # The current form names no place: the switch says where the install is, and
  # mkinstall_prefix pointed the link at this prefix.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  printf '# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n' \
    > "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  vouch alpha
  run_sweep
  assert_success
  assert_output_contains "0 to upgrade, 0 of those repointed, 1 already level"
}

# 0069, 0153
@test "an estate whose source is recorded as ~/ plans a repoint, though the path names the prefix (0153)" {
  # Until 0153 this arm held the opposite: 0069's `~/` form was the current one,
  # so an estate recording it at the prefix's commit was level. The current
  # form is `install`, which names no place, so a recorded path is replaced
  # even where it resolves to the prefix -- the record moves although the
  # place does not.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  printf '# devbin_version: 0.1.0\n# source: ~/opt/devbin\n# source_commit: aaaabbbbccccdddd\n' \
    > "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  vouch alpha
  run_sweep
  assert_success
  assert_output_contains "1 to upgrade, 1 of those repointed, 0 already level"
  assert_output_matches 'alpha +\| +upgrade \+ repoint'
}

# 0069
@test "an estate recording the prefix ABSOLUTE when the prefix is under HOME is NOT level" {
  # THE ROLLOUT CASE. Every estate vendored before 0069 records its source
  # absolute. Read back, that path equals the prefix, so a sweep comparing
  # paths alone called the estate level and never ran it again -- and the home
  # directory stayed in every tracked manifest until some later release moved
  # the commit. Level means the recorded FORM is current too.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  printf '# devbin_version: 0.1.0\n# source: %s\n# source_commit: aaaabbbbccccdddd\n' "$prefix" \
    > "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  vouch alpha
  run_sweep
  assert_success
  assert_output_contains "1 to upgrade, 1 of those repointed, 0 already level"
}

# 0069
@test "--apply takes a second pass when the first leaves the source recorded absolute" {
  # An estate's FIRST upgrade runs the runtime it already has, and a pre-0069
  # runtime writes the source absolute even as it installs the new one. The
  # commit then matches, so a convergence check on the commit alone stops after
  # one pass with the home directory still recorded. This launcher stands in
  # for that runtime: its first run writes the absolute form, its second the
  # current one.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  printf '# devbin_version: 0.1.0\n# source: %s\n# source_commit: 0000000000000000\n' "$prefix" \
    > "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  vouch alpha
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'd="$(cd "$(dirname "$0")" && pwd)/.devbin"' \
    'n=$(( $(cat "$d/runs" 2>/dev/null || echo 0) + 1 ))' \
    'printf "%s\n" "$n" >"$d/runs"' \
    'if [ "$n" -eq 1 ]; then src="'"$prefix"'"; else src=install; fi' \
    'printf "# devbin_version: 0.1.0\n# source: %s\n# source_commit: aaaabbbbccccdddd\n" "$src" >"$d/manifest.sha256"' \
    > "$ROOTS/alpha/bin/devbin"
  chmod +x "$ROOTS/alpha/bin/devbin"
  run_sweep --apply
  assert_success
  assert_output_contains "1 upgraded (1 needed a second pass to converge provenance), 0 HELD BACK, 0 FAILED"
  [ "$(sed -n 's/^# source: //p' "$ROOTS/alpha/bin/.devbin/manifest.sha256")" = install ]
}

# 0153, 0213
@test "the sweep refuses when the switch names no install it could distribute (0153, 0213)" {
  # A swept estate finds its install through the switch afterwards, so a sweep
  # the switch names nothing for has nothing the estates could find again.
  prefix="$(mkinstall_prefix)"
  rm "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "this machine's switch names no devbin install"
  assert_output_contains "refusing to sweep"
}

# 0153, 0213
@test "the sweep distributes the install the link names, never install.prefix by itself (0153, 0213)" {
  # The estates it upgrades read the same switch at their next upgrade, so the
  # sweep and every estate agree on the install by construction.
  prefix="$(mkinstall_prefix)"
  other="$DEVBIN_TEST_TMPDIR/other/devbin"
  stub_install "$other" checkout
  ln -sfn "$other/bin/devbin" "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_success
  assert_output_contains "distributing: $(cd -P "$other" && pwd -P), named by the link $HOME/.local/bin/devbin"
}

# 0153, 0213
@test "a link the switch cannot follow refuses the sweep with its reason (0153, 0213)" {
  prefix="$(mkinstall_prefix)"
  ln -sfn "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "leads to no file it can follow"
  assert_output_contains "refusing to sweep"
}

# 0213
@test "the sweep refuses while the switch names devbin's checkout: it distributes an install (0213)" {
  prefix="$(mkinstall_prefix)"
  src="$(mkdevsrc)"
  ln -sfn "$src/bin/devbin" "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "which is no install -- a sweep distributes an install: run devbin use opt or devbin use brew first"
}

# 0197
@test "on a machine whose install is Homebrew's, the sweep distributes from it by its opt path, and install.prefix is not asked (0197)" {
  # install.prefix names a checkout's install that nothing points at: on a brew
  # machine that is not the machine's install, and the sweep does not use it.
  prefix="$(mkinstall_prefix)"
  brew_keg --stub 0.1.0
  rm -f "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_success
  assert_output_contains "distributing: $HOMEBREW_PREFIX/opt/devbin/libexec, named by HOMEBREW_PREFIX's opt/devbin"
  assert_output_contains "1 to upgrade"
  # And with no install.prefix declared at all.
  mkproj_cfg
  run_sweep
  assert_success
  assert_output_contains "distributing: $HOMEBREW_PREFIX/opt/devbin/libexec"
}

# 0197, 0213
@test "a machine with a keg and a link that cannot be followed is not passed over for Homebrew: the sweep refuses with the link's reason (0197, 0213)" {
  prefix="$(mkinstall_prefix)"
  brew_keg --stub 0.1.0
  ln -sfn "$DEVBIN_TEST_TMPDIR/gone/bin/devbin" "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "leads to no file it can follow"
  refute_output_contains "distributing: $HOMEBREW_PREFIX"
}

# 0197
@test "an opt link that names no devbin install refuses the sweep by name (0197)" {
  prefix="$(mkinstall_prefix)"
  brew_keg --empty 0.1.0
  rm -f "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "HOMEBREW_PREFIX's opt/devbin names"
  assert_output_contains "this machine's switch names no devbin install"
}

# 0153, 0213
@test "DEVBIN_INSTALL_PREFIX lets the sweep run with no link, and says what a shell without it reads (0153, 0213)" {
  prefix="$(mkinstall_prefix)"
  rm "$HOME/.local/bin/devbin"
  mkproj_cfg "$prefix"
  mkestate alpha
  export DEVBIN_INSTALL_PREFIX="$prefix"
  run_sweep
  assert_success
  assert_output_contains "1 to upgrade"
  # It runs, and says what the estates it upgrades will need: a shell without
  # the variable reads the switch, which names no install for them.
  assert_output_contains "DEVBIN_INSTALL_PREFIX names $prefix, and without it the switch names no install"
  # Said only while the switch without it names another tree.
  ln -sfn "$prefix/bin/devbin" "$HOME/.local/bin/devbin"
  run_sweep
  assert_success
  refute_output_contains "DEVBIN_INSTALL_PREFIX names $prefix, and"
}

# 0153, 0213
@test "DEVBIN_INSTALL_PREFIX is read before the link: the sweep distributes the install it names, and says the link names another (0153, 0213)" {
  local other="$DEVBIN_TEST_TMPDIR/other/devbin"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  stub_install "$other" checkout
  export DEVBIN_INSTALL_PREFIX="$other"
  run_sweep
  assert_success
  assert_output_contains "distributing: $other, named by DEVBIN_INSTALL_PREFIX"
  assert_output_contains "DEVBIN_INSTALL_PREFIX names $other, and without it the switch names"
}

# 0153
@test "an estate recording install is no repoint when the machine spells the prefix another way (0153)" {
  # The sweep accepts the machine's install by -ef, so the plan asks the same
  # question: compared as strings, a trailing slash called every behind estate
  # a repoint.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  printf '# devbin_version: 0.1.0\n# source: install\n# source_commit: 0000000000000000\n' \
    > "$ROOTS/alpha/bin/.devbin/manifest.sha256"
  vouch alpha
  export DEVBIN_INSTALL_PREFIX="$prefix/"
  run_sweep
  assert_success
  assert_output_contains "1 to upgrade, 0 of those repointed"
}

# AT-3.2
@test "it refuses to sweep from something that is not an install" {
  # A tree can look installable and not be the machine install. Sweeping the
  # estate from an ordinary project would distribute whatever that project had.
  notinstall="$DEVBIN_TEST_TMPDIR/notinstall"
  mkdir -p "$notinstall/bin/.devbin/lib"
  printf '#!/usr/bin/env bash\n' > "$notinstall/bin/devbin"
  printf 'x\n' > "$notinstall/bin/.devbin/lib/helpers"
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: dead\n' \
    > "$notinstall/bin/.devbin/manifest.sha256"
  export DEVBIN_INSTALL_PREFIX="$notinstall"
  mkproj_cfg "$notinstall"
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "which is no install -- a sweep distributes an install"
}

# AT-3.2
@test "it refuses when there is no install at all, and names the steps that make one" {
  mkproj_cfg "$DEVBIN_TEST_TMPDIR/opt/devbin"
  mkestate alpha
  run_sweep
  assert_failure
  # Under an absolute HOMEBREW_PREFIX holding no devbin, the remedy is installing
  # it, said once, by brew_unplaced_fix (0250).
  assert_output_contains "this machine's switch names no devbin install (no devbin at $HOMEBREW_PREFIX/opt/devbin/libexec, under HOMEBREW_PREFIX) -- refusing to sweep: install devbin with Homebrew"
  refute_output_contains "export HOMEBREW_PREFIX"
}

# 0250
@test "with HOMEBREW_PREFIX unset or relative, the sweep refuses giving exporting it as the remedy, never installing devbin, and from a dev tree adds the checkout's use opt (0250)" {
  local export_fix="export HOMEBREW_PREFIX in the profile this process reads, as brew shellenv exports it" src
  mkproj_cfg "$DEVBIN_TEST_TMPDIR/opt/devbin"
  mkestate alpha
  export HOMEBREW_PREFIX=relative/brew
  run_sweep
  assert_failure
  assert_output_contains "this machine's switch names no devbin install (HOMEBREW_PREFIX, 'relative/brew', is not an absolute path) -- refusing to sweep: $export_fix"
  refute_output_contains "install devbin"
  unset HOMEBREW_PREFIX
  run_sweep
  assert_failure
  assert_output_contains "this machine's switch names no devbin install (HOMEBREW_PREFIX is not set) -- refusing to sweep: $export_fix"
  refute_output_contains "install devbin"
  refute_output_contains "use opt"
  # A sweep distributes an install, so from devbin's checkout the clause names
  # use opt alone, by the checkout's own bin/devbin.
  src="$(mkdevsrc)"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$src" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_failure
  assert_output_contains "refusing to sweep: $export_fix, or run bin/devbin use opt in your devbin checkout"
  refute_output_contains "use dev"
}

# AT-3.3
@test "the repoint count is reported SEPARATELY from the upgrade count" {
  # Two different things happen to an estate -- its runtime moves, and the
  # source it points at moves -- and one number cannot say so. Once the fleet is
  # settled most estates will have the first without the second.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate beta
  # beta already records the install, in the current form, so only its runtime
  # is behind: a recorded path, even the prefix's, is a repoint (issue 0153).
  printf '# devbin_version: 0.1.0\n# source: install\n# source_commit: 0000000000000000\n' \
    > "$ROOTS/beta/bin/.devbin/manifest.sha256"
  vouch beta
  run_sweep
  assert_output_contains "2 to upgrade, 1 of those repointed"
}

# AT-3.4
@test "a FROZEN estate is named, never silently dropped" {
  # The estate a reader would otherwise assume had been swept. A sweep that
  # quietly skips one is a population filter wearing no clothes.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate frozenone
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN="frozenone" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "Not swept"
  assert_output_contains "frozenone"
  assert_output_contains "FROZEN"
  assert_output_contains "1 frozen"
}

# AT-3.4
@test "and WITHOUT the freeze the same estate IS in the plan -- the control" {
  # Without this, a sweep that dropped every estate would satisfy the arm above.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate frozenone
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN=" " DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "upgrade + repoint"
  assert_output_contains "0 frozen"
}

@test "the sweep freezes nothing of its own, and its plan says what is frozen, none included (0154)" {
  # devbin keeps no list of the projects that use it, so which estates a sweep
  # leaves alone is the machine's to declare -- and an estate nobody declared
  # must read as IN the plan, never as quietly left alone.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  run env -u DEVBIN_FLEET_FROZEN DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "frozen:       none declared"
  assert_output_contains "0 frozen"
  assert_output_contains "upgrade + repoint"
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN="alpha" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "frozen:       alpha"
  assert_output_contains "1 frozen"
}

@test "a frozen list is names, never a glob: a * freezes no file of the project (0154)" {
  # The handler runs from the project root, where a globbed `*` named every
  # file there as a frozen estate.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  run env DEVBIN_FLEET_ROOTS="$ROOTS" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN='*' DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "frozen:       *"
  assert_output_contains "0 frozen"
  # And no estate is labelled `*`, so the plan says the name matches none (0182).
  assert_output_contains "matches none: *"
  # Matched as written, never as a pattern: beside a name that does match, `*`
  # still matches none.
  DEVBIN_FLEET_FROZEN='alpha *' run_sweep
  assert_success
  assert_output_contains "1 frozen"
  assert_output_contains "matches none: *"
}

# THE FROZEN NAME IS THE LABEL ITS ROW PRINTS (0182). Every arm above freezes an
# estate at a root's top level, where the label and the basename are one, so
# none could tell them apart. Solo sits at the top level and Child under two
# groups, so here the two part company.
mkgroups() {
  mkestate Solo
  mkestate GroupA/Child
  mkestate GroupB/Child
}

@test "a frozen name is the label its row prints: GroupA/Child freezes that estate alone (0182)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  DEVBIN_FLEET_FROZEN="GroupA/Child" run_sweep
  assert_success
  assert_output_contains "frozen:       GroupA/Child"
  assert_output_matches 'GroupA/Child +\| +FROZEN'
  assert_output_matches 'GroupB/Child +\| +upgrade \+ repoint'
  assert_output_contains "1 frozen"
  refute_output_contains "matches none"
}

@test "a basename freezes neither estate it ends, and is named as matching none (0182)" {
  # The collision that moved the labels off the basename: Child named both.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  DEVBIN_FLEET_FROZEN="Child" run_sweep
  assert_success
  assert_output_matches 'GroupA/Child +\| +upgrade \+ repoint'
  assert_output_matches 'GroupB/Child +\| +upgrade \+ repoint'
  assert_output_contains "0 frozen"
  assert_output_contains "matches none: Child"
}

@test "a frozen name that labels no estate is named as matching none, and the plan never offers --apply (0182)" {
  # A mistyped or stale name echoed in the header read as a freeze.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  DEVBIN_FLEET_FROZEN="NoSuchEstate" run_sweep
  assert_success
  assert_output_contains "frozen:       NoSuchEstate"
  assert_output_contains "matches none: NoSuchEstate"
  assert_output_contains "0 frozen"
  assert_output_contains "Nothing was written, and --apply refuses while a frozen name matches none"
  refute_output_contains "To do it:"
  # Two names that label nothing are both named, as declared.
  DEVBIN_FLEET_FROZEN="Child NoSuchEstate" run_sweep
  assert_success
  assert_output_contains "matches none: Child NoSuchEstate"
}

@test "at a root's top level the label is the basename, so Solo still freezes Solo -- the control (0182)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  DEVBIN_FLEET_FROZEN="Solo" run_sweep
  assert_success
  assert_output_matches 'Solo +\| +FROZEN'
  assert_output_contains "1 frozen"
  refute_output_contains "matches none"
}

@test "--apply refuses while a frozen name matches no estate, before it writes anything, naming it (0182)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  # Each estate's runtime leaves a mark when the sweep runs it, so a sweep that
  # reaches any estate changes the fingerprint.
  local e before
  for e in Solo GroupA/Child GroupB/Child; do
    printf '#!/usr/bin/env bash\nprintf ran >>"%s/ran"\n' "$ROOTS/$e" >"$ROOTS/$e/bin/devbin"
  done
  before="$(cd "$ROOTS" && find . -type f -exec cksum {} + | LC_ALL=C sort)"
  DEVBIN_FLEET_FROZEN="Solo NoSuchEstate" run_sweep --apply
  [ "$(cd "$ROOTS" && find . -type f -exec cksum {} + | LC_ALL=C sort)" = "$before" ] ||
    fail "the refused sweep wrote under the roots"
  assert_failure
  # Refused before the plan, naming only the name that matches none.
  refute_output_contains "APPLYING"
  assert_output_contains "(NoSuchEstate)"
  assert_output_contains "drop a name only when what it was meant for is no estate under these roots"
  # The control: with the name dropped the same sweep runs the estates it may,
  # so the fingerprint above can change. It ends FAILED by design, the stub
  # recording no provenance, so only its mark is read.
  DEVBIN_FLEET_FROZEN="Solo" run_sweep --apply
  [ -f "$ROOTS/GroupA/Child/ran" ] || fail "the control never ran GroupA/Child, so the fingerprint proves nothing"
  [ ! -e "$ROOTS/Solo/ran" ] || fail "the control ran Solo, which it froze"
}

@test "the help page says a frozen name is the plan's label, and that --apply refuses one matching none (0182)" {
  local page="$DEVBIN_HOME/bin/.devbin/help/fleet.md"
  assert_file_contains "$page" "as the sweep's plan prints it"
  assert_file_contains "$page" "--apply refuses while one is declared"
}

@test "a frozen name that labels a dependency checkout froze no estate, and is named as matching none (0182)" {
  # A freeze reaches only the rows the sweep could touch, and a dependency
  # checkout is never swept, so a name for one protects nothing.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate alpha/deps/depcopy
  DEVBIN_FLEET_FROZEN="alpha/deps/depcopy" run_sweep
  assert_success
  assert_output_matches 'depcopy +\| +NOT AN ESTATE -- a dependency checkout'
  assert_output_contains "0 frozen"
  assert_output_contains "matches none: alpha/deps/depcopy"
}

@test "a label follows this run's roots: framed at GroupA, GroupA/Child matches none and Child is that estate (0182)" {
  # A name written for one frame can label nothing in another, and dropping it
  # would sweep the estate it was written for; the plan names it instead.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkgroups
  run env DEVBIN_FLEET_ROOTS="$ROOTS/GroupA" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN="GroupA/Child" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_contains "matches none: GroupA/Child"
  assert_output_matches '\| Child +\| +upgrade \+ repoint'
  run env DEVBIN_FLEET_ROOTS="$ROOTS/GroupA" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_FLEET_FROZEN="Child" DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  assert_output_matches '\| Child +\| +FROZEN'
  assert_output_contains "1 frozen"
  refute_output_contains "matches none"
}

@test "an incomplete scan is refused before a frozen name that matches none, the deeper cause first (0182)" {
  # An estate under a directory the walk could not read matches nothing only
  # because the scan never reached it, so renaming or dropping is no remedy.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkdir -p "$ROOTS/locked"
  lock "$ROOTS/locked"
  DEVBIN_FLEET_FROZEN="NoSuchEstate" run_sweep --apply
  chmod 755 "$ROOTS/locked"
  assert_failure
  assert_output_contains "incomplete scan"
  refute_output_contains "DEVBIN_FLEET_FROZEN"
}

# AT-3.4
@test "an UNREACHABLE estate is named, never silently dropped" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate broken
  chmod -x "$ROOTS/broken/bin/devbin"
  run_sweep
  assert_output_contains "UNREACHABLE"
  assert_output_contains "broken"
  assert_output_contains "1 unreachable"
}

# AT-3.2
@test "a dependency checkout is not an estate and is not swept" {
  # `deps/` copies arrive through a package manager and belong to somebody
  # else's repository. Sweeping one would write into a tree its own project
  # rebuilds from scratch.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate alpha/deps/depcopy
  run_sweep
  assert_output_contains "alpha"
  # NOT SWEPT, AND NAMED RATHER THAN DROPPED (issue 0101). This arm used to
  # refute `depcopy` anywhere in the output, which pinned the silence itself:
  # the sweep skipped it without a row, where audit and doc list it apart and
  # every other exclusion is named. It must be absent from the PLAN and present
  # in the not-swept table, as a dependency checkout, and counted.
  plan="$(printf '%s\n' "$output" | sed -n '/^| Estate .*Action/,/^$/p')"
  [[ "$plan" != *depcopy* ]] || fail "the dependency checkout is in the plan:
$plan"
  assert_output_matches 'depcopy +\| +NOT AN ESTATE -- a dependency checkout'
  assert_output_contains "1 to upgrade"
  assert_output_contains "1 not an estate"
}

@test "a worktree is not swept, and is named with its kind (0101)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkworktree alpha/.worktrees/wt
  mkestate alpha/.worktrees/wt
  run_sweep
  plan="$(printf '%s\n' "$output" | sed -n '/^| Estate .*Action/,/^$/p')"
  [[ "$plan" != *".worktrees/wt"* ]] || fail "the worktree is in the plan:
$plan"
  assert_output_matches 'wt +\| +NOT AN ESTATE -- a worktree'
  assert_output_contains "1 not an estate"
}

@test "a linked worktree is not swept WHEREVER it sits, not only under .worktrees/" {
  # Measured on 2026-09-22: Intent/tmp/wt-0516, a worktree an Intent node was
  # using for its issue 0516, was upgraded by the sweep. The scan knew worktrees
  # only by the directory they conventionally live in; a worktree is defined by
  # its .git FILE naming a gitdir under .git/worktrees/, and that is the test.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkworktree alpha/tmp/wt-0516
  mkestate alpha/tmp/wt-0516
  run_sweep
  plan="$(printf '%s\n' "$output" | sed -n '/^| Estate .*Action/,/^$/p')"
  [[ "$plan" != *wt-0516* ]] || fail "the worktree is in the plan:
$plan"
  assert_output_matches 'wt-0516 +\| +NOT AN ESTATE -- a worktree'
  assert_output_contains "1 to upgrade"
  assert_output_contains "1 not an estate"
}

@test "a .git FILE that is not a worktree -- a submodule -- stays an estate" {
  # The positive control for the arm above: the test must key on WHERE the
  # gitdir points, not on .git being a file, or a submodule would be dropped.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate alpha/sub
  printf 'gitdir: ../.git/modules/sub\n' > "$ROOTS/alpha/sub/.git"
  run_sweep
  assert_output_contains "2 to upgrade"
  assert_output_contains "0 not an estate"
}

@test "every row is labelled by its PATH, so two copies with one name read as two (0112 follow-up)" {
  # The 2026-09-22 sweep printed "arca_cli" and "arca_config" twelve times in
  # its not-swept table: each row carried the directory's bare name, so copies
  # under six different estates were indistinguishable. The label is the path
  # below the scan root.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate beta
  mkestate alpha/deps/lib
  mkestate beta/deps/lib
  mkestate beta/nested/gamma
  run_sweep
  assert_output_matches 'alpha/deps/lib +\| +NOT AN ESTATE'
  assert_output_matches 'beta/deps/lib +\| +NOT AN ESTATE'
  assert_output_matches '\| beta/nested/gamma +\| upgrade'
}

# --- --apply, against REAL installs rather than stubs ------------------------

# AT-3.2
@test "--apply upgrades a real estate FROM THE INSTALL and repoints it" {
  # THE ONLY ARM THAT WRITES. Everything above proves the sweep declines to act;
  # this proves it acts correctly when told to, against a real dev tree, a real
  # published install and a real vendored estate rather than stub manifests.
  #
  # HOME IS SET OUTSIDE THE TMPDIR. It was set for issue 0069, when the raw
  # `# source:` lines asserted below were paths, absolute only while not under
  # HOME; since issue 0153 they are words. It stays because the sweep walks HOME
  # for installs outside the roots, which must be this arm's empty directory,
  # never the runner's home.
  export HOME="$DEVBIN_TEST_TMPDIR/elsewhere"
  mkdir -p "$HOME"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  prefix="$DEVBIN_TEST_TMPDIR/opt/devbin"
  # The switch names the install, as `devbin use opt` makes it the machine's
  # (0213): the sweep distributes what the switch names.
  switch_to "$prefix"
  want="$(sed -n 's/^# source_commit: //p' "$prefix/bin/.devbin/manifest.sha256")"
  [ -n "$want" ]

  estates="$DEVBIN_TEST_TMPDIR/estates"
  mkdir -p "$estates/one"
  run devbin_run "$src" install --into "$estates/one" --name one
  assert_success
  # It came from the dev tree, which is the state every estate is really in,
  # and it records that kind of tree, never its place (issue 0153).
  [ "$(sed -n 's/^# source: //p' "$estates/one/bin/.devbin/manifest.sha256")" = checkout ]

  mkproj_cfg "$prefix"
  run env DEVBIN_FLEET_ROOTS="$estates" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade --apply
  assert_success
  assert_output_contains "APPLYING"
  # The control for 0074's arm: an estate with nothing edited holds nothing back.
  assert_output_contains "1 upgraded"
  assert_output_contains "0 HELD BACK"
  refute_output_contains "Held back"

  # REPOINTED and CURRENT, asserted off disk rather than off the report.
  [ "$(sed -n 's/^# source: //p' "$estates/one/bin/.devbin/manifest.sha256")" = install ]
  [ "$(sed -n 's/^# source_commit: //p' "$estates/one/bin/.devbin/manifest.sha256")" = "$want" ]
}

# AT-3.1
@test "the DRY RUN of that same sweep leaves the estate untouched" {
  # The control for the arm above, and the one that matters: same fixtures, same
  # command, one flag removed. Without it, a sweep that always wrote would pass
  # the apply test and the default would be silently dangerous.
  #
  # HOME outside the TMPDIR, for the reason the arm above gives.
  export HOME="$DEVBIN_TEST_TMPDIR/elsewhere"
  mkdir -p "$HOME"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  prefix="$DEVBIN_TEST_TMPDIR/opt/devbin"
  # The switch names the install, as `devbin use opt` makes it the machine's
  # (0213): the sweep distributes what the switch names.
  switch_to "$prefix"

  estates="$DEVBIN_TEST_TMPDIR/estates"
  mkdir -p "$estates/one"
  run devbin_run "$src" install --into "$estates/one" --name one
  assert_success
  before="$(sha256_of "$estates/one/bin/.devbin/manifest.sha256")"

  mkproj_cfg "$prefix"
  run env DEVBIN_FLEET_ROOTS="$estates" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade
  assert_success
  [ "$(sha256_of "$estates/one/bin/.devbin/manifest.sha256")" = "$before" ]
  [ "$(sed -n 's/^# source: //p' "$estates/one/bin/.devbin/manifest.sha256")" = checkout ]
}

@test "an estate whose upgrade HELD BACK an edited file is not counted as upgraded, and the file is named (0074)" {
  # Measured in the 0069 sweep of 2026-09-16: Laksa's upgrade skipped two files
  # edited in place -- correctly -- and the sweep, which discarded the upgrade's
  # output, reported `16 upgraded ... 0 FAILED`. A summary read instead of sixteen
  # logs must not fold "some files held back" into "upgraded".
  #
  # Against a real install and a real vendored estate, so the sweep reads the
  # upgrade's actual output rather than a stub's idea of it.
  export HOME="$DEVBIN_TEST_TMPDIR/elsewhere"
  mkdir -p "$HOME"
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  prefix="$DEVBIN_TEST_TMPDIR/opt/devbin"
  # The switch names the install, as `devbin use opt` makes it the machine's
  # (0213): the sweep distributes what the switch names.
  switch_to "$prefix"

  estates="$DEVBIN_TEST_TMPDIR/estates"
  mkdir -p "$estates/one"
  run devbin_run "$src" install --into "$estates/one" --name one
  assert_success
  printf '# a local patch\n' >>"$estates/one/bin/.devbin/lib/runlog"

  mkproj_cfg "$prefix"
  run env DEVBIN_FLEET_ROOTS="$estates" PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" upgrade --apply
  # NOT LEVEL, SO NOT GREEN: an operator chaining the sweep into a commit must stop.
  assert_failure
  assert_output_contains "0 upgraded"
  assert_output_contains "1 HELD BACK"
  assert_output_contains "bin/.devbin/lib/runlog"
  assert_output_matches '\| one +\| .*bin/\.devbin/lib/runlog'
  # And the file really was held: the local patch is still there.
  grep -q '^# a local patch$' "$estates/one/bin/.devbin/lib/runlog"
}

@test "a held file upgrade COUNTS but does not name is still reported, and a RELEASED file is held (0074)" {
  # The count on upgrade's summary line checks the per-file lines, so an upgrade
  # whose wording moves cannot turn a hold into silence. The stub stands in for an
  # estate runtime: one `released` line, a summary counting two, and a current
  # manifest so provenance converges on the first pass.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'd="$(cd "$(dirname "$0")" && pwd)/.devbin"' \
    'printf "  released   bin/.devbin/lib/gone\n"' \
    'printf "\n0 added, 0 updated, 5 unchanged, 0 removed, 2 skipped\n"' \
    'printf "# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"' \
    > "$ROOTS/alpha/bin/devbin"
  chmod +x "$ROOTS/alpha/bin/devbin"
  run_sweep --apply
  assert_failure
  assert_output_contains "0 upgraded (0 needed a second pass to converge provenance), 1 HELD BACK, 0 FAILED"
  assert_output_contains "bin/.devbin/lib/gone"
  assert_output_contains "1 more file(s) counted as skipped but not named"
}

# stub_estate <name> <body> -- an estate whose launcher is <body>, standing in for
# the runtime `fleet upgrade` drives. `$d` is its .devbin, `$n` its run count.
stub_estate() {
  mkestate "$1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'd="$(cd "$(dirname "$0")" && pwd)/.devbin"' \
    'n=$(( $(cat "$d/runs" 2>/dev/null || echo 0) + 1 ))' \
    'printf "%s\n" "$n" >"$d/runs"' \
    "$2" > "$ROOTS/$1/bin/devbin"
  chmod +x "$ROOTS/$1/bin/devbin"
}

@test "a RELEASED file reported only by the FIRST of two passes is still held (0074)" {
  # critic-shell: pass 1 prints `released` and drops the path from the manifest,
  # so pass 2 has nothing to say about it -- and a sweep reading only the last
  # pass reported the estate converged with nothing held. The second pass is the
  # common case: the 0069 sweep put 16 of 16 estates through one.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  # shellcheck disable=SC2016
  stub_estate alpha '
printf "  skipped    bin/.devbin/lib/kept (edited in place -- upgrade with --force to replace it)\n"
if [ "$n" -eq 1 ]; then
  printf "  released   bin/.devbin/lib/gone\n\n0 added, 0 updated, 5 unchanged, 0 removed, 2 skipped\n"
  printf "# devbin_version: 0.1.0\n# source: '"$prefix"'\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"
else
  printf "\n0 added, 0 updated, 5 unchanged, 0 removed, 1 skipped\n"
  printf "# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"
fi'
  run_sweep --apply
  assert_failure
  assert_output_contains "1 HELD BACK"
  # Its own label, not merely its path: the remedy text below says "no longer
  # shipped" whenever anything is held, so only the label proves the kind.
  assert_output_contains "bin/.devbin/lib/gone (no longer shipped, now untracked)"
  # Its own remedy: --force cannot reach a file the manifest no longer lists.
  assert_output_contains "no longer shipped"
  assert_output_contains "delete it if it is dead"
  # A file BOTH passes skip is one held file, named once.
  [ "$(printf '%s\n' "$output" | grep -o 'bin/.devbin/lib/kept (edited in place)' | wc -l | tr -d ' ')" = 1 ] ||
    fail "a file skipped by both passes was not named exactly once:
$output"
  refute_output_contains "counted as skipped but not named"
}

@test "a held path containing a SPACE is named whole (0074)" {
  # The manifest carries such paths (lib/install); splitting on fields named
  # `lib/my` and the count cross-check could not see it.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  # shellcheck disable=SC2016
  stub_estate alpha '
printf "  skipped    bin/.devbin/lib/my file (edited in place -- upgrade with --force to replace it)\n\n0 added, 0 updated, 5 unchanged, 0 removed, 1 skipped\n"
printf "# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"'
  run_sweep --apply
  assert_failure
  assert_output_contains "bin/.devbin/lib/my file (edited in place)"
  assert_output_contains "--force"
}

@test "a held line whose WORDING has moved is still reported, not counted as named (0074)" {
  # critic-shell, second pass: the counter matched `skipped` loosely while the
  # extractor needed upgrade's exact suffix, so a runtime printing a different
  # suffix had its hold counted as named, extracted as nothing, and reported as a
  # clean upgrade. The estate's own runtime prints these lines, and it can be
  # older or newer than the fleet.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  # shellcheck disable=SC2016
  stub_estate alpha '
printf "  skipped    bin/.devbin/lib/a (edited in place)\n\n0 added, 0 updated, 5 unchanged, 0 removed, 1 skipped\n"
printf "# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"'
  run_sweep --apply
  assert_failure
  assert_output_contains "1 HELD BACK"
  assert_output_contains "bin/.devbin/lib/a"
}

@test "a FAILED upgrade says how it failed and keeps its held files (0074)" {
  # Every FAILED row used to say "provenance did not converge", including when the
  # upgrade itself had exited non-zero, and its captured output was thrown away.
  export HOME="$DEVBIN_TEST_TMPDIR"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  # shellcheck disable=SC2016
  stub_estate alpha '
printf "  skipped    bin/.devbin/lib/runlog (edited in place -- upgrade with --force to replace it)\n"
exit 3'
  run_sweep --apply
  assert_failure
  assert_output_contains "1 FAILED"
  assert_output_contains "upgrade exited 3"
  refute_output_contains "provenance did not converge"
  assert_output_contains "bin/.devbin/lib/runlog"
}

# AT-3.11
@test "the sweep guesses no directory: with nothing on the switch it refuses, whatever devbin's own config declares (0213)" {
  # A fallback here would have the fleet vendored out of a directory named
  # after whoever's $HOME the runtime was built on -- and a sweep that reads
  # the wrong install still reports a perfectly ordinary plan. Since 0213 the
  # sweep reads the switch, not install.prefix, so neither a declared prefix
  # nor its absence names an install.
  HOME="$DEVBIN_TEST_TMPDIR/fakehome"
  mkdir -p "$HOME"
  export HOME
  mkproj_cfg
  mkestate alpha
  run_sweep
  assert_failure
  assert_output_contains "this machine's switch names no devbin install"
  refute_output_contains "to upgrade"
}

# --- the census frame (issue 0116) -------------------------------------------
#
# The roots were `$HOME/Devel/prj`, a default in code, justified by a search the
# disk later outgrew: Gtools-geodica ran devbin 0.1.1 under ~/Devel/cfg, unseen
# by every sweep from 0.1.2 to 0.1.7. The frame is now a tracked file, and every
# run walks the rest of the home directory for what the frame misses.

# run_frame [args] -- the handler with NO DEVBIN_FLEET_ROOTS, so the roots file
# under $PROJ is what names the frame.
run_frame() {
  run env -u DEVBIN_FLEET_ROOTS PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" "$@"
}

# rows -- audit's stdout rows alone, one install a line; its notes are on stderr.
rows() {
  env -u DEVBIN_FLEET_ROOTS PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" audit 2>/dev/null
}

@test "with no DEVBIN_FLEET_ROOTS the frame is bin/.devbin/fleet.roots, comments skipped and ~ expanded (0116)" {
  export HOME="$DEVBIN_TEST_TMPDIR/h"
  export DEVBIN_FLEET_HOME="$HOME"
  mkdir -p "$PROJ/bin/.devbin"
  printf '# the frame\n~/r1\n\n  ~/r2   # a note\n# ~/r3\n' >"$PROJ/bin/.devbin/fleet.roots"
  ROOTS="$HOME/r1" mkinstall alpha
  ROOTS="$HOME/r2" mkinstall beta
  ROOTS="$HOME/r3" mkinstall gamma
  run_frame audit
  assert_success
  assert_output_contains "the frame, from bin/.devbin/fleet.roots: ~/r1 ~/r2"
  local r
  r="$(rows)"
  grep -q $'^estate\tr1/alpha\t' <<<"$r" || fail "alpha, under the first root, is not a row: $r"
  grep -q $'^estate\tr2/beta\t' <<<"$r" || fail "beta, under an indented root with a trailing comment, is not a row: $r"
  ! grep -q 'gamma' <<<"$r" || fail "gamma sits under a commented-out root and was scanned as one: $r"
  # And the walk outside the frame finds gamma, which is the point of it.
  assert_output_matches 'estate +~/r3/gamma'
}

@test "a missing roots file is refused by name, never read as an empty frame (0116)" {
  mkdir -p "$PROJ/bin/.devbin"
  run_frame audit
  assert_failure
  assert_output_contains "bin/.devbin/fleet.roots is missing"
  assert_output_contains "DEVBIN_FLEET_ROOTS"
  refute_output_contains "outside it"
}

@test "a roots file naming no root is refused, never read as a machine with nothing on it (0116)" {
  mkdir -p "$PROJ/bin/.devbin"
  printf '# nothing but a comment\n\n   \n' >"$PROJ/bin/.devbin/fleet.roots"
  run_frame audit
  assert_failure
  assert_output_contains "names no root"
  run_frame doc
  assert_failure
  assert_output_contains "names no root"
  [ ! -s "$PROJ/intent/docs/devbin-users.md" ] || fail "doc wrote a census over no roots"
}

@test "DEVBIN_FLEET_ROOTS overrides the file, and the report names which of them set the frame (0116)" {
  mkdir -p "$PROJ/bin/.devbin"
  printf '%s\n' "$DEVBIN_TEST_TMPDIR/fromfile" >"$PROJ/bin/.devbin/fleet.roots"
  ROOTS="$DEVBIN_TEST_TMPDIR/fromfile" mkinstall filed
  mkinstall envd
  run_fleet audit
  assert_success
  assert_output_contains "the frame, from DEVBIN_FLEET_ROOTS:"
  assert_output_contains "envd"
  refute_output_contains "filed"
}

@test "audit names each install outside the frame with its kind, and none inside it (0116)" {
  # The walk starts ABOVE the roots here, so pruning each root by its path is
  # what keeps alpha from being listed twice.
  export DEVBIN_FLEET_HOME="$DEVBIN_TEST_TMPDIR"
  mkinstall alpha
  ROOTS="$DEVBIN_TEST_TMPDIR/elsewhere" mkinstall stray
  ROOTS="$DEVBIN_TEST_TMPDIR/opt" mkinstall devbin
  # In the header, where a reader of a header line looks: it stops at the first
  # entry, and mkinstall records one.
  local m="$DEVBIN_TEST_TMPDIR/opt/devbin/bin/.devbin/manifest.sha256"
  { printf '# kind: install\n'; cat "$m"; } >"$m.new" && mv "$m.new" "$m"
  run_fleet audit
  assert_success
  assert_output_contains "outside it: 2 install(s) -- 1 estate, 1 install"
  assert_output_matches "estate +[^ ]*elsewhere/stray"
  assert_output_matches "install +[^ ]*opt/devbin"
  refute_output_matches "estate +[^ ]*roots/alpha"
}

@test "POSITIVE CONTROL: with nothing outside the frame, audit says none (0116)" {
  # The walk covers the roots here as well, so a walk that listed everything it
  # found would name alpha and never say none.
  export DEVBIN_FLEET_HOME="$DEVBIN_TEST_TMPDIR"
  mkinstall alpha
  run_fleet audit
  assert_success
  assert_output_contains "outside it: none"
  refute_output_matches "estate +[^ ]*roots/alpha"
}

@test "upgrade names an install outside the frame in its not-swept table, and counts it (0116)" {
  # The sweep's plan reached only what the frame held, so it read as the whole
  # fleet without Gtools-geodica for six releases.
  export DEVBIN_FLEET_HOME="$DEVBIN_TEST_TMPDIR/walkhome"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  ROOTS="$DEVBIN_FLEET_HOME/cfg" mkestate stray
  run_sweep
  assert_success
  plan="$(printf '%s\n' "$output" | sed -n '/^| Estate .*Action/,/^$/p')"
  [[ "$plan" != *stray* ]] || fail "the install outside the frame is in the plan:
$plan"
  assert_output_matches 'cfg/stray +\| +OUTSIDE THE ROOTS -- estate; no root in DEVBIN_FLEET_ROOTS covers it'
  assert_output_contains "0 not an estate, 1 outside the roots"
}

@test "the walk outside the frame finds an install that has lost its manifest (0154)" {
  ROOTS="$DEVBIN_FLEET_HOME/cfg" mkinstall_nomanifest stray
  run_fleet audit
  assert_success
  assert_output_contains "outside it: 1 install(s) -- 1 estate"
  assert_output_matches "estate +[^ ]*cfg/stray"
}

@test "an install outside the roots whose lib cannot be searched is no hole in that walk (0175)" {
  # The walk outside the roots digests nothing, so the install is listed and
  # the walk is whole: nothing beneath its lib could be an install.
  ROOTS="$DEVBIN_FLEET_HOME/cfg" mkinstall stray
  local lib="$DEVBIN_FLEET_HOME/cfg/stray/bin/.devbin/lib"
  chmod 644 "$lib"
  if [ -x "$lib" ]; then
    chmod 755 "$lib"
    skip "running with permissions that search a mode-0644 directory"
  fi
  run_fleet audit
  chmod 755 "$lib"
  [[ "$output" != *"installs outside the roots may be missing"* ]] || fail "the walk outside the roots named the lib a hole: $output"
  [[ "$output" != *"cannot search $lib"* ]] || fail "the walk named the lib as a directory it could not search: $output"
  assert_success
  assert_output_contains "outside it: 1 install(s) -- 1 estate"
  assert_output_matches "estate +[^ ]*cfg/stray"
}

@test "the machine install that has lost its manifest is an install outside the roots, not an estate (0153)" {
  # Read by its manifest alone, the machine's own install with no manifest was
  # an estate, and the census told the reader to add it to the roots. The
  # link names it (0213).
  ROOTS="$DEVBIN_FLEET_HOME/opt" mkinstall_nomanifest devbin
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$DEVBIN_FLEET_HOME/opt/devbin/bin/devbin" "$HOME/.local/bin/devbin"
  run_fleet audit
  assert_success
  assert_output_contains "outside it: 1 install(s) -- 1 install"
  assert_output_matches "install +[^ ]*opt/devbin"
}

@test "an estate whose lib cannot be searched is planned, and --apply names it FAILED while the others are swept (0175)" {
  # The false hole refused the whole sweep as an incomplete scan. Now the walk
  # is whole, the estate is planned, and its own launcher, which needs its lib,
  # fails the upgrade by name, leaving its bytes alone.
  local before lib="$ROOTS/beta/bin/.devbin/lib"
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate beta
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'd="$(cd "$(dirname "$0")" && pwd)/.devbin"' \
    'printf "# devbin_version: 0.1.0\n# source: install\n# source_commit: aaaabbbbccccdddd\n" >"$d/manifest.sha256"' \
    >"$ROOTS/alpha/bin/devbin"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' 'cat "$(dirname "$0")/.devbin/lib/helpers" >/dev/null || exit 1' \
    >"$ROOTS/beta/bin/devbin"
  before="$(sha256_of "$ROOTS/beta/bin/.devbin/manifest.sha256")"
  chmod 644 "$lib"
  if [ -x "$lib" ]; then
    chmod 755 "$lib"
    skip "running with permissions that search a mode-0644 directory"
  fi
  run_sweep
  local dry_status="$status" dry_output="$output"
  run_sweep --apply
  chmod 755 "$lib"
  [ "$dry_status" -eq 0 ] || fail "the dry run refused: $dry_output"
  [[ "$dry_output" != *"incomplete scan"* ]] || fail "the dry run read the lib as a hole: $dry_output"
  [[ "$dry_output" =~ beta\ +\|\ +upgrade ]] || fail "the estate was not planned: $dry_output"
  assert_failure
  assert_output_matches 'beta +\| +FAILED'
  assert_output_contains "1 upgraded"
  [ "$(sha256_of "$ROOTS/beta/bin/.devbin/manifest.sha256")" = "$before" ] || fail "--apply wrote to the estate whose lib cannot be searched"
}

@test "the sweep names an estate whose manifest records no files as not swept, with the remedy, and counts it apart (0159)" {
  # upgrade refuses a manifest that records no files as it does a missing one,
  # so the sweep must not plan a run it would refuse.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate beta
  printf '# devbin_version: 0.1.0\n# source: /nowhere\n# source_commit: deadbeefcafe1234\n' \
    >"$ROOTS/beta/bin/.devbin/manifest.sha256"
  printf '#!/usr/bin/env bash\ntouch "$0.ran"\n' >"$ROOTS/beta/bin/devbin"
  local before
  before="$(sha256_of "$ROOTS/beta/bin/.devbin/manifest.sha256")"
  run_sweep
  assert_success
  assert_output_matches 'beta +\| +NO FILES -- not swept: its manifest records no files'
  refute_output_matches 'beta +\| +upgrade'
  assert_output_contains "upgrade --from $(home_relative "$prefix") --force"
  assert_output_contains ", 0 with no manifest, 1 whose manifest records no files, 0 whose manifest cannot be read"
  run_sweep --apply
  [ ! -e "$ROOTS/beta/bin/devbin.ran" ] || fail "--apply ran the launcher of the estate whose manifest records no files"
  [ "$(sha256_of "$ROOTS/beta/bin/.devbin/manifest.sha256")" = "$before" ] || fail "--apply wrote its manifest"
}

@test "the sweep names an estate whose manifest cannot be read as not swept, and --apply leaves it alone (0159)" {
  # upgrade refuses it (0144), so the sweep must not plan it: an older runtime
  # in it would read the manifest as recording no edits, and overwrite one.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  mkestate beta
  printf '#!/usr/bin/env bash\ntouch "$0.ran"\n' >"$ROOTS/beta/bin/devbin"
  local m="$ROOTS/beta/bin/.devbin/manifest.sha256"
  chmod 000 "$m"
  if [ -r "$m" ]; then
    chmod 644 "$m"
    skip "running with permissions that read a mode-000 file"
  fi
  run_sweep
  local dry_status="$status" dry_output="$output"
  run_sweep --apply
  chmod 644 "$m"
  [ "$dry_status" -eq 0 ] || fail "the dry run refused: $dry_output"
  [[ "$dry_output" =~ beta\ +\|\ +UNREADABLE\ MANIFEST\ --\ not\ swept ]] || fail "the estate was not named: $dry_output"
  [[ ! "$dry_output" =~ beta\ +\|\ +upgrade ]] || fail "the estate was planned: $dry_output"
  [[ "$dry_output" == *", 1 whose manifest cannot be read"* ]] || fail "it was not counted: $dry_output"
  [ ! -e "$ROOTS/beta/bin/devbin.ran" ] || fail "--apply ran the launcher of the estate whose manifest cannot be read"
}

@test "the sweep names an estate that has lost its manifest as not swept, with the remedy, and --apply leaves it alone (0154)" {
  # 0146 made `upgrade` refuse an install with no manifest unless forced,
  # because an edit there cannot be named. The sweep never planned one at all:
  # it could not see it.
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate beta
  rm "$ROOTS/beta/bin/.devbin/manifest.sha256"
  # A launcher that says it ran: mkinstall's stub writes nothing, so a sweep
  # that ran it anyway would have left the bytes below exactly as they were.
  printf '#!/usr/bin/env bash\ntouch "$0.ran"\n' >"$ROOTS/beta/bin/devbin"
  local before
  before="$(sha256_of "$ROOTS/beta/bin/devbin")"
  run_sweep
  assert_success
  assert_output_matches 'beta +\| +NO MANIFEST -- not swept'
  assert_output_contains "upgrade --from $(home_relative "$prefix") --force"
  assert_output_contains ", 1 with no manifest"
  run_sweep --apply
  assert_success
  [ ! -e "$ROOTS/beta/bin/devbin.ran" ] || fail "--apply ran the launcher of the estate that has lost its manifest"
  [ "$(sha256_of "$ROOTS/beta/bin/devbin")" = "$before" ] || fail "--apply wrote to the estate that has lost its manifest"
  [ ! -e "$ROOTS/beta/bin/.devbin/manifest.sha256" ] || fail "--apply wrote a manifest into it"
}

@test "doc names where its frame came from, and says what lies outside it -- including nothing (0116)" {
  mkinstall alpha
  run_fleet doc
  assert_success
  doc="$PROJ/intent/docs/devbin-users.md"
  grep -q 'Roots scanned, from `DEVBIN_FLEET_ROOTS` for this run, overriding `bin/.devbin/fleet.roots`' "$doc" ||
    fail "the document does not say where its frame came from"
  grep -q '^## Outside the roots -- 0$' "$doc" || fail "the document has no outside section when nothing is outside"
  grep -q 'None was found' "$doc" || fail "the empty outside section does not say none was found"
  ROOTS="$DEVBIN_FLEET_HOME/cfg" mkinstall stray
  run_fleet doc
  assert_success
  grep -q '^## Outside the roots -- 1$' "$doc" || fail "the document does not count the install outside the frame"
  grep -q '^| estate | .*cfg/stray' "$doc" || fail "the document does not list the install outside the frame"
}

@test "a walk outside the frame that cannot read everything fails audit and refuses the doc (0116, 0145)" {
  # A list with a hole in it is not "none outside".
  mkinstall alpha
  mkdir -p "$DEVBIN_FLEET_HOME/locked"
  chmod 000 "$DEVBIN_FLEET_HOME/locked"
  if [ -r "$DEVBIN_FLEET_HOME/locked" ]; then
    chmod 755 "$DEVBIN_FLEET_HOME/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  run_fleet audit
  local audit_status="$status" audit_output="$output"
  run_fleet doc
  chmod 755 "$DEVBIN_FLEET_HOME/locked"
  [ "$audit_status" -ne 0 ] || fail "audit exited 0 over a walk it could not finish: $audit_output"
  [[ "$audit_output" == *"installs outside the roots may be missing"* ]] || fail "audit did not say the walk was incomplete: $audit_output"
  assert_failure
  assert_output_contains "the walk outside the roots could not read everything"
  # AND ONE IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's find
  # passed over it at rc 0, and "none outside" was said over a hole.
  chmod 644 "$DEVBIN_FLEET_HOME/locked"
  run_fleet audit
  chmod 755 "$DEVBIN_FLEET_HOME/locked"
  [ "$status" -ne 0 ] || fail "audit exited 0 over a directory it could not search: $output"
  assert_output_contains "cannot search $DEVBIN_FLEET_HOME/locked -- nothing beneath it was looked at"
  assert_output_contains "installs outside the roots may be missing"
}

@test "a DEVBIN_FLEET_ROOTS naming no root is refused by name, as the file is, by audit, doc and upgrade (0116)" {
  # A variable of blanks is set, so it wins over the file, and it split into no
  # root at all: audit and the upgrade plan exited 0 over an empty census, and
  # doc said only that devbin had a defect (cc's review).
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  local verb
  for verb in audit doc upgrade; do
    run env DEVBIN_FLEET_ROOTS=" " PROJECT_ROOT="$PROJ" DEVBIN_DIR="$PROJ/bin/.devbin" \
      DEVBIN_LIB="$DEVBIN_LIB_DIR" bash "$FLEET" "$verb"
    [ "$status" -ne 0 ] || fail "$verb exited 0 over DEVBIN_FLEET_ROOTS=' ': $output"
    [[ "$output" == *"DEVBIN_FLEET_ROOTS names no root"* ]] || fail "$verb did not name the variable: $output"
    [[ "$output" != *"devbin defect"* ]] || fail "$verb blamed itself instead: $output"
  done
  [ ! -s "$PROJ/intent/docs/devbin-users.md" ] || fail "doc wrote a census over no roots"
}

@test "the walk prunes the home's own Library and .Trash by path, walks a project's Library/, and every report says what it did not walk (0116)" {
  # By -name, Library was pruned wherever it sat, a project's own included. And
  # what the walk skips has to be said, or "none outside" reads as none anywhere:
  # ~/Dropbox is a symlink into ~/Library/CloudStorage, and find follows no link
  # (cc's review).
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  ROOTS="$DEVBIN_FLEET_HOME/Library/CloudStorage/Dropbox" mkinstall cloudy
  ln -s "$DEVBIN_FLEET_HOME/Library/CloudStorage/Dropbox" "$DEVBIN_FLEET_HOME/Dropbox"
  ROOTS="$DEVBIN_FLEET_HOME/.Trash" mkinstall binned
  ROOTS="$DEVBIN_FLEET_HOME/work/app/Library" mkinstall kept
  run_fleet audit
  assert_success
  assert_output_matches 'estate +[^ ]*work/app/Library/kept'
  refute_output_contains 'cloudy'
  refute_output_contains 'binned'
  assert_output_contains 'not walked for them: '
  assert_output_contains '/Library, which holds Library/CloudStorage'
  assert_output_contains '/.Trash, and anything reached only through a symlink'
  run_fleet doc
  assert_success
  grep -q 'Outside the roots means outside in what the walk reached.* It does not look in .*/Library, which holds Library/CloudStorage' \
    "$PROJ/intent/docs/devbin-users.md" || fail "the document does not say what the walk did not reach"
  run_sweep
  assert_success
  assert_output_contains 'not walked for installs outside the roots: '
}

@test "upgrade names a walk outside the frame it could not finish as NOT KNOWN, and still exits 0 (0116)" {
  # audit fails and doc refuses on this, since their product is the list. The
  # sweep's product is the sweep, and an install outside the frame is never
  # swept either way, so the hole is named rather than failing it (cc's Q3).
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkestate alpha
  # THE CONTROL: a walk that read everything names no hole.
  run_sweep
  assert_success
  refute_output_contains "NOT KNOWN"
  mkdir -p "$DEVBIN_FLEET_HOME/locked"
  chmod 000 "$DEVBIN_FLEET_HOME/locked"
  if [ -r "$DEVBIN_FLEET_HOME/locked" ]; then
    chmod 755 "$DEVBIN_FLEET_HOME/locked"
    skip "running with permissions that read a mode-000 directory"
  fi
  run_sweep
  chmod 755 "$DEVBIN_FLEET_HOME/locked"
  assert_success
  assert_output_matches '\| +NOT KNOWN -- the walk outside the roots could not read everything'
  assert_output_contains "installs outside the roots may be missing"
}

# AN ARCHIVE IS NEVER WALKED (issue 0351). A directory named _Archive, at any
# depth under a root, is pruned by rule: nothing in it is read, swept or
# counted, and every report names it once, as ARCHIVE -- not walked. Each arm
# builds its archives under this test's own roots and home, with an estate in
# each whose launcher leaves a mark if anything runs it.

# mkarchived <path-under-roots> -- mkestate, with a launcher that records any run
# of it beside the roots.
mkarchived() {
  mkestate "$1"
  printf '#!/usr/bin/env bash\n: >"%s/ran-%s"\n' "$DEVBIN_TEST_TMPDIR" "${1//\//-}" >"$ROOTS/$1/bin/devbin"
}

# archive_listing -- every path under the roots' archives, with its size, sorted.
archive_listing() {
  find "$ROOTS/_Archive" "$ROOTS/group/_Archive" -print | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s %s\n' "$p" "$(wc -c <"$p" 2>/dev/null || printf dir)"
  done
}

@test "audit gives each archive under the roots one row, archive and not walked, and no row for an install in one, at any depth (0351)" {
  mkinstall alpha
  mkinstall _Archive/old
  mkinstall group/_Archive/older/deep
  run_fleet audit
  assert_success
  local top nested
  top="$(_row_of _Archive)"
  [[ "$top" == "archive"$'\t'*"/roots/_Archive"$'\t'"not walked"* ]] || fail "no archive row for _Archive: $output"
  nested="$(printf '%s\n' "$output" | awk -F'\t' '$2 ~ /\/group\/_Archive$/')"
  [[ "$nested" == "archive"$'\t'*$'\t'"not walked"* ]] || fail "no archive row for group/_Archive: $output"
  refute_output_contains "_Archive/old"
  refute_output_contains "_Archive/older"
  [ -n "$(_row_of alpha)" ] || fail "the estate beside the archives has no row: $output"
}

@test "the sweep names each archive as ARCHIVE -- not walked, and --apply runs nothing in one and leaves it as it was (0351)" {
  prefix="$(mkinstall_prefix)"
  mkproj_cfg "$prefix"
  mkarchived _Archive/old
  mkarchived group/_Archive/older
  local before
  before="$(archive_listing)"
  : >"$DEVBIN_TEST_TMPDIR/before-apply"
  run_sweep --apply
  assert_success
  assert_output_matches '\| _Archive +\| +ARCHIVE -- not walked'
  assert_output_matches '\| group/_Archive +\| +ARCHIVE -- not walked'
  assert_output_contains "2 archive(s) not walked"
  refute_output_contains "_Archive/old"
  refute_output_contains "_Archive/older"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ran-_Archive-old" ] || fail "the sweep ran the launcher of an estate in _Archive"
  [ ! -e "$DEVBIN_TEST_TMPDIR/ran-group-_Archive-older" ] || fail "the sweep ran the launcher of an estate in group/_Archive"
  [ "$(archive_listing)" = "$before" ] || fail "the archives' files changed:
$(diff <(printf '%s\n' "$before") <(archive_listing))"
  local newer
  newer="$(find "$ROOTS/_Archive" "$ROOTS/group/_Archive" -newer "$DEVBIN_TEST_TMPDIR/before-apply" -print)"
  [ -z "$newer" ] || fail "the sweep wrote in an archive: $newer"
}

@test "doc names each archive under the roots in its own section, and lists no install in one (0351)" {
  mkinstall alpha
  mkinstall _Archive/old
  mkinstall group/_Archive/older
  run_fleet doc
  assert_success
  local doc="$PROJ/intent/docs/devbin-users.md"
  grep -qx '## Archives, not walked -- 2' "$doc" || fail "the document has no archives section of two: $(cat "$doc")"
  grep -qE '^\| [^|]*/roots/_Archive +\| ARCHIVE -- not walked +\|$' "$doc" || fail "no row for _Archive: $(cat "$doc")"
  grep -qE '^\| [^|]*/roots/group/_Archive +\| ARCHIVE -- not walked +\|$' "$doc" || fail "no row for group/_Archive: $(cat "$doc")"
  ! grep -q '_Archive/old' "$doc" || fail "the document lists an install in an archive"
}

@test "doc has no archives section when no archive is under the roots (0351)" {
  mkinstall alpha
  run_fleet doc
  assert_success
  ! grep -q '## Archives' "$PROJ/intent/docs/devbin-users.md" || fail "an archives section with no archive in it"
}

@test "the walk outside the roots never enters an archive, and every report says so (0351)" {
  mkinstall alpha
  ROOTS="$DEVBIN_FLEET_HOME/_Archive" mkinstall gone
  ROOTS="$DEVBIN_FLEET_HOME/work/_Archive" mkinstall older
  run_fleet audit
  assert_success
  refute_output_contains "gone"
  refute_output_contains "older"
  assert_output_contains "outside it: none"
  assert_output_contains "or held in a directory named _Archive"
}
