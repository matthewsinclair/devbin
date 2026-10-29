#!/usr/bin/env bats
# install.bats - vendoring, the manifest, and upgrade (WP-09)
#
# The claim under test is that devbin can be put into a project and taken
# forward again WITHOUT ever destroying something a person wrote. It rests on:
#
#   the seam       everything under bin/.devbin/lib/ is devbin's; config.yaml,
#                  cmd/ and help/ are the project's and are never written
#   the manifest   a vendored file edited in place is DETECTED, refused, and
#                  stays flagged -- including across the manifest rewrite that
#                  the refusing upgrade itself performs
#
# The manifest is the one that had a real defect in it. Upgrade correctly
# declined to overwrite an edited file and then re-checksummed it into the
# manifest, so the next doctor pronounced it intact: two correct-looking steps
# composing into a false green. "an edit stays flagged after the refusing
# upgrade rewrites the manifest" exists for that alone.
#
# Note that the WHOLE SUITE is also an install test, since fixtures install
# through the real installer: install_devbin in the harness runs the real
# command, so every fixture in every file is an install that has to have worked
# for the test to mean anything.

load "../lib/test_helper"

setup() {
  devbin_setup
  export PROJECT_ROOT="$DEVBIN_TEST_TMPDIR"
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  init_colors off
}
teardown() { devbin_teardown; }

# A bare directory -- NOT create_test_project, which already scaffolds the
# .devbin tree. Install has to be the thing that makes this a devbin project.
mkempty() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-target}"
  mkdir -p "$dir"
  echo "$dir"
}

# THIS HARNESS CAN REACH THE OPERATOR'S REAL MACHINE INSTALL, AND THAT IS WHY
# THIS GUARD EXISTS (ST0005).
#
# `install` and `upgrade` gained a PUBLISH mode that fires when they are run
# inside devbin's own source tree with no --into -- and $DEVBIN_HOME IS that
# tree. So a call here with neither --into nor --prefix resolves `install.prefix`
# from devbin's real config and writes to the machine install: the tree every
# project on the machine vendors from, replaced by a test fixture's bytes.
#
# Refused at the choke point rather than left to every future test author to
# remember, because the failure is silent -- the test would PASS, and the damage
# would be somewhere else entirely.
devbin_install() {
  case " $* " in
    *" --into "* | *" --prefix "*) ;;
    *)
      printf 'devbin_install: refusing a call with neither --into nor --prefix.\n' >&2
      printf '  $DEVBIN_HOME is devbin OWN source tree, so this would PUBLISH to\n' >&2
      printf '  the real install.prefix -- see ST0005.\n' >&2
      return 64
      ;;
  esac
  # The checkout this vendors from is the one the switch names: since issue
  # 0153 a project records only the KIND of its source, and since 0213 a bare
  # `upgrade` reads the tree the switch names, for every kind.
  switch_to "$DEVBIN_HOME"
  run devbin_run "$DEVBIN_HOME" install "$@"
}

@test "install vendors the dispatcher and the whole runtime" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  assert_executable "$target/bin/devbin"
  assert_file_exists "$target/bin/.devbin/lib/helpers"
  assert_file_exists "$target/bin/.devbin/lib/resolve"
  assert_executable "$target/bin/.devbin/lib/cmd/version"
}

@test "the vendored set is exactly what vendored_paths enumerates" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    assert_file_exists "$target/$rel"
  done <<EOF
$(vendored_paths "$DEVBIN_HOME")
EOF
}

# _enumerate <fn> <root> -- one of the vendored-set enumerators, in a clean
# shell with only its libraries, so its own status is what `run` sees.
_enumerate() { _in_lib "$1 '$2'"; }

# _in_lib <snippet> -- <snippet> in a clean shell with only devbin's libraries,
# so the function's own status is what `run` sees.
_in_lib() {
  run bash -c ". '$DEVBIN_LIB_DIR/helpers' && . '$DEVBIN_LIB_DIR/install' && $1"
}

@test "vendored_paths FAILS when find cannot read part of lib/, rather than listing less (0127)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  src="$(mkdevsrc)"
  # THE CONTROL: readable, the pages are listed.
  _enumerate vendored_paths "$src"
  assert_success
  assert_output_contains "bin/.devbin/lib/pages/doctor.md"
  # Unreadable, the list is refused, with find's error naming the path. It was
  # a shorter list at rc 0, so a publish shipped without the pages.
  chmod 000 "$src/lib/pages"
  _enumerate vendored_paths "$src"
  chmod 755 "$src/lib/pages"
  assert_failure
  assert_output_contains "Permission denied"
  refute_output_contains "bin/devbin"
}

@test "vendored_dir_files FAILS when find cannot read part of an install's lib/ (0127)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  _enumerate vendored_dir_files "$proj"
  assert_success
  assert_output_contains "bin/.devbin/lib/pages/doctor.md"
  chmod 000 "$proj/bin/.devbin/lib/pages"
  _enumerate vendored_dir_files "$proj"
  chmod 755 "$proj/bin/.devbin/lib/pages"
  assert_failure
  assert_output_contains "Permission denied"
}

@test "_sha256_of_set FAILS and names a present file it cannot read, still printing the rows it read (0144)" {
  local d="$DEVBIN_TEST_TMPDIR/set"
  mkdir -p "$d"
  printf 'a\n' >"$d/a"
  printf 'b\n' >"$d/b"
  # THE CONTROL: both read, a row each, rc 0 -- and `c`, asked for and absent,
  # is no failure: only a file that is THERE and has no row is unreadable.
  local -a made=("$d"/*)
  _in_lib "_sha256_of_set '$d' \$'a\nb\nc'"
  assert_success
  [ "$(printf '%s\n' "$output" | grep -cE '[[:space:]](a|b)$')" -eq "${#made[@]}" ] || fail "wanted a row for a and for b:\n$output"
  # It returned 0 here with one row, the tool's own line the only word, so
  # every caller took one row fewer for the whole set.
  make_unreadable "$d/b"
  _in_lib "_sha256_of_set '$d' \$'a\nb\nc'"
  assert_failure
  assert_output_contains "cannot read $d/b"
  grep -qE "^$(sha256_of "$d/a")[[:space:]]+a\$" <<<"$output" || fail "the row it did read, a's, is not printed:\n$output"
  ! grep -qE '^[0-9a-f]{64}[[:space:]]+b$' <<<"$output" || fail "a row for the unreadable b:\n$output"
  refute_output_contains "cannot read $d/c"
}

@test "manifest_write REFUSES over a shipped file it cannot read, and leaves the manifest as it was (0144)" {
  local m before
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  m="$target/bin/.devbin/manifest.sha256"
  # THE CONTROL: all readable, it writes, and records the file.
  _in_lib "manifest_write '$target' '$DEVBIN_HOME' 9.9.9"
  assert_success
  grep -q '  bin/.devbin/lib/gatecmd$' "$m" || fail "the control's manifest does not record gatecmd"
  before="$(cat "$m")"
  # It wrote a manifest one row short at rc 0, and manifest_check walks the
  # manifest's entries, so the file left out was never checked again.
  make_unreadable "$target/bin/.devbin/lib/gatecmd"
  _in_lib "manifest_write '$target' '$DEVBIN_HOME' 9.9.9"
  assert_failure
  assert_output_contains "cannot read $target/bin/.devbin/lib/gatecmd"
  assert_output_contains "refusing to write $m"
  [ "$(cat "$m")" = "$before" ] || fail "the refusing write changed the manifest"
}

@test "a manifest devbin cannot read FAILS by name, in manifest_entries and manifest_check, never reading as empty (0144)" {
  local m
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  m="$target/bin/.devbin/manifest.sha256"
  # THE CONTROL: readable, entries and ok states.
  _in_lib "manifest_check '$target'"
  assert_success
  assert_output_contains "ok	bin/.devbin/lib/gatecmd"
  # It read as a manifest of no entries at rc 0: nothing to check, all passed.
  make_unreadable "$m"
  _in_lib "manifest_entries '$target'"
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  _in_lib "manifest_check '$target'"
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  refute_output_contains "bin/.devbin/lib/"
  # And an ABSENT manifest keeps its old answers, silently: no entries at rc 1,
  # no states at rc 0, and readable -- nothing there to refuse.
  chmod 644 "$m"
  rm "$m"
  _in_lib "manifest_entries '$target'"
  assert_failure
  [ -z "$output" ] || fail "an absent manifest said something:\n$output"
  _in_lib "manifest_check '$target'"
  assert_success
  [ -z "$output" ] || fail "manifest_check over an absent manifest said something:\n$output"
  _in_lib "manifest_readable '$target'"
  assert_success
  [ -z "$output" ] || fail "manifest_readable over an absent manifest said something:\n$output"
}

@test "manifest_missing tells an install that lost its manifest from a project devbin was never installed in (0146)" {
  local fresh
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # THE CONTROL: installed, with its manifest -- not missing.
  _in_lib "manifest_missing '$target'"
  [ "$status" -eq 1 ] || fail "wanted rc 1 over an install with its manifest, got $status:\n$output"
  # Installed, bin/.devbin/lib present, and no manifest: the one case. There
  # was no such question, so every reader took the absence as no entries.
  rm "$target/bin/.devbin/manifest.sha256"
  _in_lib "manifest_missing '$target'"
  assert_success
  # Present and unreadable is not missing: that is 0144's case, refused by
  # manifest_readable, and doctor asks this first.
  printf '# placeholder\n' >"$target/bin/.devbin/manifest.sha256"
  make_unreadable "$target/bin/.devbin/manifest.sha256"
  _in_lib "manifest_missing '$target'"
  [ "$status" -eq 1 ] || fail "wanted rc 1 over an unreadable manifest, got $status:\n$output"
  # Never installed: no bin/.devbin/lib, nothing vendored to protect, and a
  # first install goes through and writes the manifest.
  fresh="$(mkempty fresh)"
  _in_lib "manifest_missing '$fresh'"
  [ "$status" -eq 1 ] || fail "wanted rc 1 over a project never installed in, got $status:\n$output"
  devbin_install --into "$fresh" --name fresh
  assert_success
  assert_file_exists "$fresh/bin/.devbin/manifest.sha256"
  _in_lib "manifest_missing '$fresh'"
  [ "$status" -eq 1 ] || fail "wanted rc 1 after the first install, got $status:\n$output"
}

@test "manifest_write REFUSES over a manifest it cannot read, rather than dropping what it recorded (0144)" {
  local m before
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  m="$target/bin/.devbin/manifest.sha256"
  # THE CONTROL: readable, it writes.
  _in_lib "manifest_write '$target' '$DEVBIN_HOME' 9.9.9"
  assert_success
  before="$(cat "$m")"
  # WRITABLE AND NOT READABLE, mode 0200: the one shape where the loss is real.
  # Its old entries read as none, and it truncated and rewrote the file
  # without them at rc 0 -- the checksums preserved files keep, gone.
  make_unreadable "$m"
  chmod 200 "$m"
  _in_lib "manifest_write '$target' '$DEVBIN_HOME' 9.9.9"
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  assert_output_contains "refusing to write $m"
  chmod 644 "$m"
  [ "$(cat "$m")" = "$before" ] || fail "the refusing write changed the manifest"
}

@test "install --force over a manifest it cannot read refuses, and replaces nothing (0144)" {
  local src m kept
  src="$(mkdevsrc)"
  target="$(mkempty)"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  m="$target/bin/.devbin/manifest.sha256"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$target/bin/.devbin/lib/builtins" "$kept"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  # It read as no previous manifest, so nothing to retire, then copied.
  make_unreadable "$m"
  run devbin_run "$src" install --into "$target" --name demo --force
  assert_failure
  assert_output_contains "cannot read the manifest at $m"
  cmp -s "$kept" "$target/bin/.devbin/lib/builtins" || fail "the refusing install replaced or removed builtins"
  # THE CONTROL: readable again, the same install goes through.
  chmod 644 "$m"
  run devbin_run "$src" install --into "$target" --name demo --force
  assert_success
  grep -q 'moved on in the source' "$target/bin/.devbin/lib/builtins" || fail "the control install did not replace builtins"
}

@test "install --force from a source with a file it cannot read refuses, and replaces nothing (0144)" {
  local src m before kept
  src="$(mkdevsrc)"
  target="$(mkempty)"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  m="$target/bin/.devbin/manifest.sha256"
  before="$(cat "$m")"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$target/bin/.devbin/lib/builtins" "$kept"
  # builtins sorts before gatecmd, so a copy loop that stops at gatecmd has
  # already replaced it -- under the old manifest, which doctor then reads as
  # an edit in place.
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  make_unreadable "$src/lib/gatecmd"
  run devbin_run "$src" install --into "$target" --name demo --force
  assert_failure
  assert_output_contains "cannot read $src/lib/gatecmd"
  assert_output_contains "nothing was installed"
  cmp -s "$kept" "$target/bin/.devbin/lib/builtins" || fail "the refusing install replaced or removed builtins"
  [ "$(cat "$m")" = "$before" ] || fail "the refusing install changed the manifest"
  # THE CONTROL: readable again, the same install goes through.
  chmod 644 "$src/lib/gatecmd"
  run devbin_run "$src" install --into "$target" --name demo --force
  assert_success
  grep -q 'moved on in the source' "$target/bin/.devbin/lib/builtins" || fail "the control install did not replace builtins"
}

# _unchecked_set_reads <dir> -- every read of vendored_paths or
# vendored_dir_files under <dir> that does not stop on its status. A read
# passes only as an assignment whose `||` goes to return, die or fail, on the
# same line or the one it continues onto. `|| :` and `|| true` are exactly the
# swallows this exists to find, and a bare `||` passes nothing by itself.
_unchecked_set_reads() {
  local files f
  files="$(grep -rlE '\$\((vendored_paths|vendored_dir_files) ' "$1")" || [ $? -eq 1 ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    awk -v file="$f" '
      pending {
        if ($0 !~ /^[ \t]*(return|die|fail)([ \t]|$)/) print file ":" pline ": " ptext
        pending = 0
      }
      /\$\((vendored_paths|vendored_dir_files) / {
        if ($0 ~ /^[ \t]*[a-z_]+="\$\((vendored_paths|vendored_dir_files) [^)]*\)" *\|\| *(return|die|fail)([ \t]|$)/) next
        if ($0 ~ /^[ \t]*[a-z_]+="\$\((vendored_paths|vendored_dir_files) [^)]*\)" *\|\| *$/) { pending = 1; pline = FNR; ptext = $0; next }
        print file ":" FNR ": " $0
      }
      END { if (pending) print file ":" pline ": " ptext }
    ' "$f" || return 1
  done <<<"$files"
}

@test "every read of the vendored set in lib/ takes its status, never a heredoc's silence (0127)" {
  local n out probe="$DEVBIN_TEST_TMPDIR/scan"
  # POSITIVE CONTROL: every shape that loses the status, planted, is found --
  # the heredoc and nested reads that hid the failure, and the two swallows --
  # and neither shape that stops on it is.
  mkdir -p "$probe"
  printf 'done <<EOF\n$(vendored_paths "$srcroot")\nEOF\n' >"$probe/heredoc"
  printf 'x="$(_sha256_of_set "$d" "$(vendored_paths "$s")")"\n' >"$probe/nested"
  printf 'paths="$(vendored_paths "$s")" || :\n' >"$probe/colon"
  printf 'have="$(vendored_dir_files "$d")" ||\n  true\n' >"$probe/true"
  out="$(_unchecked_set_reads "$probe")" || fail "the scan could not read its own probe"
  local -a plants=("$probe"/*)
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq "${#plants[@]}" ] || fail "the scan missed a planted unchecked read:\n$out"
  rm "$probe"/*
  printf 'paths="$(vendored_paths "$s")" || return 1\n' >"$probe/same"
  printf 'paths="$(vendored_paths "$s")" ||\n  die "cannot list"\n' >"$probe/continued"
  out="$(_unchecked_set_reads "$probe")" || fail "the scan could not read its own probe"
  [ -z "$out" ] || fail "the scan flags a read that stops on its status:\n$out"
  # PRESENCE: the reads that exist, so a scan matching nothing is not a pass.
  n="$(grep -rnE '\$\((vendored_paths|vendored_dir_files) ' "$DEVBIN_LIB_DIR" | grep -c .)" || n=0
  [ "$n" -gt 0 ] || fail "found no read of the vendored set under lib/ -- the scan would read nothing"
  out="$(_unchecked_set_reads "$DEVBIN_LIB_DIR")" || fail "the scan could not read lib/"
  [ -z "$out" ] || fail "a read of the vendored set loses its status:\n$out"
}

@test "an installed devbin can seed another project" {
  first="$(mkempty first)"
  devbin_install --into "$first" --name first
  assert_success
  second="$DEVBIN_TEST_TMPDIR/second"
  mkdir -p "$second"
  # The SOURCE here is the vendored copy in `first`, not this checkout. That is
  # the whole point of resolving the source off the running runtime rather than
  # from a path baked into the installer.
  run devbin_run "$first" install --into "$second" --name second
  assert_success
  assert_file_exists "$second/bin/.devbin/lib/helpers"
  assert_executable "$second/bin/devbin"
}

@test "the executable bit survives the copy" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # A handler arriving non-executable resolves and then does not run, which is
  # silent: known_commands requires -x, so the command simply is not there.
  assert_executable "$target/bin/.devbin/lib/cmd/check"
  refute_assertion assert_executable "$target/bin/.devbin/lib/helpers"
}

@test "install scaffolds the project's own half of the tree" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  assert_directory_exists "$target/bin/.devbin/cmd"
  assert_directory_exists "$target/bin/.devbin/help"
  assert_file_exists "$target/bin/.devbin/config.yaml"
}

@test "a freshly installed project runs and reports a surface" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  run devbin_run "$target" help
  assert_success
  assert_output_contains demo
}

@test "the starter config passes the schema devbin itself validates against" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo --lang shell
  assert_success
  # An empty `languages:` key would be out of the config subset and this is the
  # test that catches it -- the installer writing a file its own validator
  # rejects is the least forgivable shape of first-run failure.
  run devbin_run "$target" doctor
  assert_success
  assert_output_contains "parses and validates"
}

@test "the derived project name is lower-cased, so it agrees with the explicit path" {
  # With no --name, install derives the project name from the target directory's
  # basename. Project directories are routinely capitalised, so a verbatim
  # basename gives `Notebook`.
  #
  # THE ORIGINAL REASON IS RETIRED AND THE BEHAVIOUR IS NOT. It was lower-cased
  # because the name became the launcher SYMLINK and `bin/Notebook` is not a
  # conforming Unix command name; the per-project symlink is retired, so
  # nothing in bin/ carries the name any more. What keeps it is the test below:
  # an EXPLICIT --name carrying a capital is REFUSED, and a derivation that
  # quietly accepted what the flag rejects would make one command answer the
  # same question two ways.
  #
  # This survived nine installs. All six capitalised projects happened to pass
  # an explicit --name, and the two taking the default already had lowercase
  # directories, so the derivation had never once run on a capitalised one.
  target="$(mkempty Notebook)"
  devbin_install --into "$target"
  assert_success

  # Asserted on the RECORDED name. That used to be `ls bin/`, which was the only
  # thing that could see a stored name on a case-insensitive filesystem; with
  # the symlink gone, config is where the name lives.
  assert_file_contains "$target/bin/.devbin/config.yaml" "name: notebook"
  refute_file_contains "$target/bin/.devbin/config.yaml" "name: Notebook"
}

@test "an explicit --name or --alias carrying a capital is REFUSED, not quietly lowered" {
  # A derivation devbin performs is devbin's to get right silently. A value a
  # person typed is an instruction, and silently changing it would hide that
  # the name they asked for is not one they can have.
  target="$(mkempty)"
  devbin_install --into "$target" --name Demo
  assert_failure
  assert_output_contains "must be lower case"

  target2="$(mkempty other)"
  devbin_install --into "$target2" --name demo --alias D
  assert_failure
  assert_output_contains "must be lower case"
}

@test "install refuses to vendor devbin into a devbin source tree" {
  # WIDENED, and the arm's old name recorded the old, narrower claim.
  # The guard compared the TARGET to the SOURCE, so it only caught a tree
  # installed into itself -- and the harm it cites has nothing to do with the
  # two being the same. Installing from the machine install into this tree has a
  # different source and the identical consequence: a vendored copy sits ahead
  # of lib/ in the dispatcher's search order, every edit stops taking effect,
  # and the suite goes on passing against the copy. It is now keyed on what the
  # TARGET is.
  devbin_install --into "$DEVBIN_HOME"
  assert_failure
  assert_output_contains "devbin SOURCE tree"
  assert_output_contains "It runs lib/ in place"
  # The reason, not an internal rule id: a user reads this (0172).
  refute_output_contains "D""12"
}

# --- a target that is not a directory (issue 0258) ----------------------------
#
# install makes no directory, so a mistyped path is never made into a project,
# and each refusal says what is at the path. Only a path with nothing at it is
# told to make one, by a line quoted to be pasted, which these arms run.

@test "install --into a path with nothing at it makes nothing, and names a quoted mkdir that, run, lets install seed it (0258)" {
  local parent="$DEVBIN_TEST_TMPDIR/no where" target remedy
  target="$parent/proj"
  devbin_install --into "$target" --name demo
  assert_failure
  assert_output_contains "no such directory: $target"
  [ ! -e "$parent" ] || fail "the refused install made $parent"
  remedy="$(sed -n 's/^ *make it, then run install again:  //p' <<<"$output")"
  [ -n "$remedy" ] || fail "the refusal names no way to make the directory: $output"
  run bash -euc "$remedy" </dev/null
  assert_success
  devbin_install --into "$target" --name demo
  assert_success
  assert_executable "$target/bin/devbin"
}

@test "install --into a file, a link to nothing or a quoted ~ is refused for what it is, and told to make nothing (0258)" {
  local d file="$DEVBIN_TEST_TMPDIR/afile" dangling="$DEVBIN_TEST_TMPDIR/dangling"
  : >"$file"
  ln -s "$DEVBIN_TEST_TMPDIR/gone" "$dangling"
  for d in "$file" "$dangling"; do
    devbin_install --into "$d" --name demo
    assert_failure
    assert_output_contains "not a directory: $d"
    refute_output_contains "mkdir -p"
  done
  [ ! -e "$DEVBIN_TEST_TMPDIR/gone" ] || fail "the refused install made the link's target"
  # A ~ the user quoted reaches install unexpanded, and install expands none.
  # shellcheck disable=SC2088
  devbin_install --into '~/proj' --name demo
  assert_failure
  assert_output_contains "no such directory: ~/proj"
  assert_output_contains "its ~ was not expanded"
  refute_output_contains "mkdir -p"
  [ ! -e "$DEVBIN_HOME/~" ] || fail "the refused install made a directory named ~ where it ran"
}

@test "install --into a directory it cannot enter keeps cd's reason, and is told to make nothing (0258)" {
  local target
  target="$(mkempty)"
  make_unreadable "$target"
  devbin_install --into "$target" --name demo
  assert_failure
  assert_output_contains "cannot enter $target (above)"
  refute_output_contains "no such directory"
  refute_output_contains "mkdir -p"
}

# --- an empty --into (issue 0268) ---------------------------------------------
#
# The mode is chosen by whether --into was given, so an empty one, as an unset
# `--into "$dir"` passes, was read as none: a machine install vendored into the
# current directory, and devbin's own tree selected PUBLISH.

@test "install --into an empty name from devbin's own tree is refused naming --into, and never selects PUBLISH (0268)" {
  # No --name: PUBLISH refuses that vendor-only flag before it publishes, so
  # with one the arm would never see the publish an empty --into caused.
  local src
  src="$(mkdevsrc)"
  run devbin_run "$src" install --into ""
  assert_failure
  assert_output_contains "--into is empty"
  refute_output_contains "PUBLISH"
  [ ! -e "$DEVBIN_TEST_TMPDIR/opt/devbin" ] || fail "the refused install published the checkout"
  [ -z "$(git -C "$src" status --porcelain)" ] || fail "the refused install wrote into the checkout: $(git -C "$src" status --porcelain)"
}

@test "install --into an empty name from a machine install is refused naming --into, and vendors nothing into the current directory (0268)" {
  local src cwd
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  cwd="$(mkempty)"
  run bash -c 'cd "$1" && "$2" install --into "" --name demo </dev/null' _ "$cwd" "$DEVBIN_TEST_TMPDIR/opt/devbin/bin/devbin"
  assert_failure
  assert_output_contains "--into is empty"
  [ -z "$(ls -A "$cwd")" ] || fail "the refused install wrote into the current directory: $(ls -A "$cwd")"
}

# --- a relative target read from the current directory alone (issue 0267) ----
#
# A bare `cd <dir> && pwd` read a relative name through an exported CDPATH and
# a lone `-` as $OLDPWD, and printed the directory it changed to into the
# capture: install wrote the project under a path holding a newline, beside
# the directory the CDPATH entry or OLDPWD named, at exit 0.

# refute_newline_names <dir> -- no path under <dir> has a newline in its name.
# Each hit is printed shell-quoted by bash's printf, one to a line, so the
# newline it reports survives (BSD printf(1) has no %q), and its backslashes
# are doubled, since fail prints its message through %b.
refute_newline_names() {
  local found
  # shellcheck disable=SC2016 # $@ is the inner bash's
  found="$(find "$1" -name $'*\n*' -exec bash -c 'printf "%q\n" "$@"' _ {} +)" || fail "could not walk $1"
  [ -z "$found" ] || fail "a path holding a newline was written:\n${found//\\/\\\\}"
}

@test "install --into a relative name installs into the current directory's, never the one an exported CDPATH holds, and writes nothing there (0267)" {
  local here="$DEVBIN_TEST_TMPDIR/here" decoy="$DEVBIN_TEST_TMPDIR/decoy"
  mkdir -p "$here/proj" "$decoy/proj"
  switch_to "$DEVBIN_HOME"
  run env CDPATH="$decoy" bash -c 'cd "$1" && "$2" install --into proj --name demo </dev/null' _ "$here" "$DEVBIN_HOME/bin/devbin"
  assert_success
  assert_executable "$here/proj/bin/devbin"
  [ "$(ls -A "$decoy")" = proj ] || fail "the install wrote beside CDPATH's proj: $(printf '%q' "$(ls -A "$decoy")")"
  [ -z "$(ls -A "$decoy/proj")" ] || fail "the install wrote into CDPATH's proj: $(ls -A "$decoy/proj")"
  refute_newline_names "$DEVBIN_TEST_TMPDIR"
}

@test "install --into - installs into the current directory's -, never into OLDPWD's directory (0267)" {
  local here="$DEVBIN_TEST_TMPDIR/here" decoy="$DEVBIN_TEST_TMPDIR/decoy"
  mkdir -p "$here/-" "$decoy"
  switch_to "$DEVBIN_HOME"
  run bash -c 'cd "$1" && OLDPWD="$2" "$3" install --into - --name demo </dev/null' _ "$here" "$decoy" "$DEVBIN_HOME/bin/devbin"
  assert_success
  assert_executable "$here/-/bin/devbin"
  [ -z "$(ls -A "$decoy")" ] || fail "the install wrote into OLDPWD's directory: $(ls -A "$decoy")"
  refute_newline_names "$DEVBIN_TEST_TMPDIR"
}

# ============================================================================
# IDEMPOTENCE AND CLOBBERING (AC-09.2, AC-09.3)
# ============================================================================

@test "a second install refuses and names the flag that overrides it" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  devbin_install --into "$target" --name demo
  assert_failure
  assert_output_contains "already installed"
  assert_output_contains "--force"
}

@test "install --force re-vendors and leaves the same tree" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  before="$(cd "$target" && find . -type f | LC_ALL=C sort)"
  devbin_install --into "$target" --name demo --force
  assert_success
  after="$(cd "$target" && find . -type f | LC_ALL=C sort)"
  [ "$before" = "$after" ] || {
    echo "tree changed across --force"
    diff <(echo "$before") <(echo "$after")
    return 1
  }
}

# _retiring_source -- a source that ships lib/cmd/which, a project vendored
# from it with `which` enabled, and then the handler retired from the source.
# Prints the source; the project is $DEVBIN_TEST_TMPDIR/consumer.
_retiring_source() {
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(mkdevsrc)"
  printf '#!/usr/bin/env bash\necho "the retired handler ran"\n' >"$src/lib/cmd/which"
  chmod +x "$src/lib/cmd/which"
  git -C "$src" add -A >/dev/null 2>&1
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m ship >/dev/null 2>&1
  mkdir -p "$proj"
  devbin_run "$src" install --into "$proj" --name consumer >/dev/null
  printf 'project:\n  name: consumer\ncommands:\n  which:\n    enabled: true\n' >"$proj/bin/.devbin/config.yaml"
  git -C "$src" rm -q lib/cmd/which >/dev/null 2>&1
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m retire >/dev/null 2>&1
  printf '%s\n' "$src"
}

@test "install --force retires a handler the source stopped shipping, names it, and the name stops running it (0129)" {
  # It copied and deleted nothing: the retired handler stayed, dropped out of
  # the manifest, and went on answering its name -- where no later upgrade
  # could reach it, since upgrade retires only what the manifest lists.
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(_retiring_source)"
  run devbin_run "$proj" which
  assert_output_contains "the retired handler ran"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/cmd/which (devbin no longer ships it)"
  [ ! -e "$proj/bin/.devbin/lib/cmd/which" ] || fail "the retired handler is still on disk"
  run devbin_run "$proj" which
  refute_output_contains "the retired handler ran"
  assert_exit_code 3
}

# _case_renamed_source [edit] -- a source shipping lib/case.d/Foo, a project
# vendored from it, and then Foo renamed to foo in the source, by case alone and
# with new content. With `edit`, the project's copy is edited in place first.
# Prints the source; the project is $DEVBIN_TEST_TMPDIR/consumer (issue 0140).
_case_renamed_source() {
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(mkdevsrc)"
  ship_in_source "$src" case.d Foo '# shipped as Foo'
  mkdir -p "$proj"
  devbin_run "$src" install --into "$proj" --name consumer >/dev/null
  [ "${1:-}" != edit ] || printf '# the project edited this\n' >>"$proj/bin/.devbin/lib/case.d/Foo"
  rename_case_in_source "$src" case.d Foo foo '# shipped as foo now'
  printf '%s\n' "$src"
}

# _only_foo <proj> -- the case.d directory holds one file, under the spelling
# devbin ships.
_only_foo() {
  [ "$(ls "$1/bin/.devbin/lib/case.d" 2>&1)" = foo ] ||
    fail "case.d does not hold foo alone: $(ls -la "$1/bin/.devbin/lib/case.d" 2>&1)"
}

@test "install --force keeps a file devbin renamed only in case, as the file it ships, on a case-insensitive disk (0129, 0140)" {
  # On this disk the new spelling is written into the old entry, so Foo and foo
  # are one file, and the removal of the unshipped Foo deleted the foo it had
  # just vendored: rc 0, "removed bin/.devbin/lib/case.d/Foo", case.d gone
  # (found reviewing 0123).
  require_case_folding "$DEVBIN_TEST_TMPDIR"
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(_case_renamed_source)"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  refute_output_contains "removed    bin/.devbin/lib/case.d/Foo"
  assert_output_contains "kept bin/.devbin/lib/case.d/Foo as bin/.devbin/lib/case.d/foo"
  _only_foo "$proj"
  grep -qx '# shipped as foo now' "$proj/bin/.devbin/lib/case.d/foo" || fail "foo does not hold what devbin ships"
}

@test "on a case-SENSITIVE disk a rename only in case still retires the old spelling: Foo and foo are two files there (0140)" {
  # The control for the arms around it, which keep Foo because on their
  # disk it IS foo. Here it is not, so it is a file devbin stopped shipping.
  # It runs on CI's Ubuntu leg and skips on a Mac.
  require_case_sensitive "$DEVBIN_TEST_TMPDIR"
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(_case_renamed_source)"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/case.d/Foo"
  refute_output_contains "kept bin/.devbin/lib/case.d/Foo"
  _only_foo "$proj"
}

@test "upgrade keeps and updates a file devbin renamed only in case, on a case-insensitive disk (0140)" {
  # It updated foo and then retired Foo, the same file, as no longer shipped:
  # rc 0 and case.d empty. That code shipped in 0.1.7.
  require_case_folding "$DEVBIN_TEST_TMPDIR"
  local src proj="$DEVBIN_TEST_TMPDIR/consumer" sum
  src="$(_case_renamed_source)"
  run devbin_run "$proj" upgrade --from "$src"
  assert_success
  refute_output_contains "removed    bin/.devbin/lib/case.d/Foo"
  assert_output_contains "kept bin/.devbin/lib/case.d/Foo as bin/.devbin/lib/case.d/foo"
  _only_foo "$proj"
  grep -qx '# shipped as foo now' "$proj/bin/.devbin/lib/case.d/foo" || fail "foo was not updated"
  sum="$(awk '$2 == "bin/.devbin/lib/case.d/foo" { print $1 }' "$(manifest_of "$proj")")"
  [ -n "$sum" ] || fail "the manifest does not record foo"
  ! grep -q 'case.d/Foo' "$(manifest_of "$proj")" || fail "the manifest still records the old spelling"
}

@test "upgrade refuses to overwrite an edit to a file devbin renamed only in case, keeps it, and records it as edited (0140)" {
  # The shipped foo had no manifest entry, so its state read as new: the
  # edited-in-place refusal never fired and the copy overwrote the project's
  # edit. And a preserved foo had no recorded checksum, so the edit would have
  # been written down as canonical, 0021's laundering.
  require_case_folding "$DEVBIN_TEST_TMPDIR"
  local src proj="$DEVBIN_TEST_TMPDIR/consumer" sum now
  src="$(_case_renamed_source edit)"
  run devbin_run "$proj" upgrade --from "$src"
  assert_success
  assert_output_contains "skipped    bin/.devbin/lib/case.d/foo (edited in place"
  _only_foo "$proj"
  grep -qx '# the project edited this' "$proj/bin/.devbin/lib/case.d/foo" || fail "the project's edit was overwritten"
  sum="$(awk '$2 == "bin/.devbin/lib/case.d/foo" { print $1 }' "$(manifest_of "$proj")")"
  now="$(sha256_stdin <"$proj/bin/.devbin/lib/case.d/foo")"
  [ -n "$sum" ] || fail "the manifest does not record foo"
  [ "$sum" != "$now" ] || fail "the manifest records the refused edit as canonical"
}

@test "install --force leaves a file under bin/.devbin/lib/ that no manifest recorded -- it may be the project's (0129)" {
  # THE CANDIDATES ARE WHAT THE MANIFEST RECORDED, never everything on disk:
  # doctor names an unowned file and tells the project to move it, and a
  # re-vendor that deleted it would be deleting the project's work.
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(_retiring_source)"
  printf 'mine\n' >"$proj/bin/.devbin/lib/mine"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  [ -f "$proj/bin/.devbin/lib/mine" ] || fail "a file no manifest recorded was removed"
  refute_output_contains "lib/mine"
}

@test "install --force retires an EDITED file the source stopped shipping too, and names it, as --force copies over edits (0129)" {
  local src proj="$DEVBIN_TEST_TMPDIR/consumer"
  src="$(_retiring_source)"
  printf '# edited here\n' >>"$proj/bin/.devbin/lib/cmd/which"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/cmd/which (devbin no longer ships it)"
  [ ! -e "$proj/bin/.devbin/lib/cmd/which" ] || fail "the edited retired file is still on disk"
}

@test "a manifest line outside bin/.devbin/lib/ never points install --force's removal at the project's own half (0129)" {
  local src proj="$DEVBIN_TEST_TMPDIR/consumer" m
  src="$(_retiring_source)"
  printf '#!/usr/bin/env bash\necho mine\n' >"$proj/bin/.devbin/cmd/mine"
  chmod +x "$proj/bin/.devbin/cmd/mine"
  m="$proj/bin/.devbin/manifest.sha256"
  printf '%064d  bin/.devbin/config.yaml\n%064d  bin/.devbin/lib/../cmd/mine\n' 0 0 >>"$m"
  run devbin_run "$src" install --into "$proj" --name consumer --force
  assert_success
  [ -f "$proj/bin/.devbin/config.yaml" ] || fail "the project's config.yaml was removed"
  [ -f "$proj/bin/.devbin/cmd/mine" ] || fail "the project's own handler was removed through a .. path"
}

@test "install never overwrites the project's config, with or without --force" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# a line a person wrote\n' >>"$target/bin/.devbin/config.yaml"
  devbin_install --into "$target" --name demo --force
  assert_success
  assert_file_contains "$target/bin/.devbin/config.yaml" "a line a person wrote"
}

@test "install never overwrites a handler or an authored help topic" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '#!/usr/bin/env bash\necho mine\n' >"$target/bin/.devbin/cmd/mine"
  chmod +x "$target/bin/.devbin/cmd/mine"
  printf '# mine\n\nAuthored by a person.\n' >"$target/bin/.devbin/help/mine.md"
  devbin_install --into "$target" --name demo --force
  assert_success
  assert_file_contains "$target/bin/.devbin/cmd/mine" "echo mine"
  assert_file_contains "$target/bin/.devbin/help/mine.md" "Authored by a person"
}

@test "re-installing keeps the identity the project already declared" {
  target="$(mkempty)"
  devbin_install --into "$target" --name myapp --alias cf
  assert_success
  # No --name and no --alias this time. Guessing from the directory would rename
  # the project silently.
  devbin_install --into "$target" --force
  assert_success
  # The evidence moved from the launcher symlinks to config when the per-project
  # symlink was retired -- the claim is unchanged: a re-install must not reinvent
  # an identity the project already declared.
  assert_file_contains "$target/bin/.devbin/config.yaml" "name: myapp"
  assert_file_contains "$target/bin/.devbin/config.yaml" "alias: cf"
}

# ============================================================================
# THE LAUNCHER (AC-09.5, INVERTED -- the per-project symlink retired)
# ============================================================================

@test "install creates bin/devbin and NO per-project symlink" {
  target="$(mkempty)"
  devbin_install --into "$target" --name myapp --alias cf
  assert_success
  # bin/devbin was always the real dispatcher; the project-named files were
  # aliases to it, and they collided with the binaries these projects BUILD --
  # one ships a binary under its own name, Intent ships an `intent`. Retired.
  assert_executable "$target/bin/devbin"
  assert_file_not_exists "$target/bin/myapp"
  assert_file_not_exists "$target/bin/cf"
}

@test "bin/devbin runs, and reports the project's own identity" {
  target="$(mkempty)"
  devbin_install --into "$target" --name myapp --alias cf
  assert_success
  run devbin_run "$target" --version
  assert_success
  # The INVOCATION is bin/devbin everywhere; DEVBIN_NAME still answers the other
  # question, which is which project this is.
  assert_output_contains myapp
}

@test "a real file at the project name is left completely alone" {
  target="$(mkempty)"
  mkdir -p "$target/bin"
  # This is now the NORMAL case rather than a migration edge: it is the binary
  # the project builds, standing where the old alias used to shadow it.
  printf '#!/usr/bin/env bash\necho the project binary\n' >"$target/bin/myapp"
  devbin_install --into "$target" --name myapp
  assert_success
  assert_file_contains "$target/bin/myapp" "the project binary"
  # And install says nothing about it, because there is nothing to say.
  refute_output_contains "not a symlink"
}

# ============================================================================
# THE MANIFEST (AC-09.6, AC-09.7)
# ============================================================================

@test "the manifest records every vendored file plus version and source" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  assert_file_exists "$target/bin/.devbin/manifest.sha256"
  [ "$(manifest_version "$target")" = "$(cat "$DEVBIN_HOME/VERSION")" ]
  [ "$(manifest_field "$target" source)" = checkout ]
  [ "$(manifest_source "$target")" = "$DEVBIN_HOME" ]
  count="$(manifest_entries "$target" | grep -c . || true)"
  want="$(vendored_paths "$DEVBIN_HOME" | grep -c . || true)"
  [ "$count" = "$want" ] || {
    echo "manifest has $count entries, vendored set has $want"
    return 1
  }
}

# --- The recorded source never names the home directory (issue 0069) --------
#
# The manifest is TRACKED in the projects that vendor devbin, several of them
# public, and `# source:` was the one line in it naming the operator's home
# directory -- rewritten on every upgrade, so a scrub never survived. 0069
# recorded a source under $HOME as `~/<rest>`; since issue 0153 the writer
# records the KIND of the source and no path at all. The arms below hold what is
# left of 0069: the manifest names no home directory, `home_relative`'s edges
# for its remaining callers (fleet's lines and the pointer line), and the
# reader, for the forms every manifest written before 0153 still carries.
#
# EACH ARM SETS HOME rather than inheriting it: the assertion is about where the
# source sits relative to HOME, and the operator's real home is not a thing a
# test may depend on.

# _manifest_with_source <dir> <value> -- a manifest whose source line reads
# <value> verbatim, for the reader arms.
_manifest_with_source() {
  mkdir -p "$1/bin/.devbin"
  printf '# devbin_version: 0.1.0\n# source: %s\n# source_commit: abc123\n' "$2" \
    >"$1/bin/.devbin/manifest.sha256"
}

@test "a source under HOME is recorded as its kind, and the home directory appears nowhere in the manifest (0069, 0153)" {
  target="$(mkempty)"
  export HOME="${DEVBIN_HOME%/*}"
  devbin_install --into "$target" --name demo
  assert_success
  manifest="$target/bin/.devbin/manifest.sha256"
  [ "$(sed -n 's/^# source: //p' "$manifest")" = checkout ]
  [ "$(grep -cF "$HOME/" "$manifest" || true)" = 0 ]
  # And the reader still hands back the checkout, from the switch, read in the
  # test's own home.
  [ "$(HOME="$DEVBIN_TEST_TMPDIR/home" manifest_source "$target")" = "$(cd -P "$DEVBIN_HOME" && pwd -P)" ]
}

@test "a source outside HOME is recorded as its kind too, never as its absolute path (0069, 0153)" {
  target="$(mkempty)"
  export HOME="$DEVBIN_TEST_TMPDIR/elsewhere"
  mkdir -p "$HOME"
  devbin_install --into "$target" --name demo
  assert_success
  [ "$(sed -n 's/^# source: //p' "$target/bin/.devbin/manifest.sha256")" = checkout ]
  [ "$(grep -cF "$DEVBIN_HOME" "$target/bin/.devbin/manifest.sha256" || true)" = 0 ]
  [ "$(manifest_source "$target")" = "$DEVBIN_HOME" ]
}

@test "home_relative: a HOME that is only a STRING prefix of a path is not a directory it is under (0069)" {
  # `/x/Devbi` is a prefix of `/x/Devbin` as a string and is not its parent. A
  # strip of "$HOME" rather than "$HOME/" gives `~n`, which names a different
  # user's home directory.
  export HOME="${DEVBIN_HOME%?}"
  [ "$(home_relative "$DEVBIN_HOME")" = "$DEVBIN_HOME" ]
}

@test "home_relative: a HOME that ends in a slash still gives ~/ (0069)" {
  # The reader's trailing-slash arm has a twin here: "$HOME"/ with HOME=/x/ is
  # /x//, which no real path starts with, so an untrimmed HOME gives the
  # absolute path -- the home directory, again.
  export HOME="${DEVBIN_HOME%/*}/"
  [ "$(home_relative "$DEVBIN_HOME")" = '~/'"${DEVBIN_HOME##*/}" ]
}

@test "home_relative: an EMPTY HOME leaves a path absolute rather than under / (0069)" {
  # With HOME empty, "$HOME/" is "/", and every absolute path starts with it --
  # so an unguarded encoder gives `~/Users/...`, which expands under the next
  # reader's HOME to a path that does not exist.
  export HOME=""
  [ "$(home_relative "$DEVBIN_HOME")" = "$DEVBIN_HOME" ]
}

@test "install.prefix expands ~/ against HOME, and leaves it as written under an empty HOME (0069)" {
  # The config reader had its own copy of the `~` expansion, and it turned
  # `~/opt/devbin` into `/opt/devbin` when HOME was empty -- a real directory,
  # and one a publish would then have written into.
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg="$DEVBIN_TEST_TMPDIR/config.yaml"
  printf 'install:\n  prefix: ~/opt/devbin\n' >"$cfg"
  cfg_load "$cfg"
  export HOME="$DEVBIN_TEST_TMPDIR/home"
  [ "$(install_prefix_configured)" = "$DEVBIN_TEST_TMPDIR/home/opt/devbin" ]
  export HOME=""
  [ "$(install_prefix_configured)" = '~/opt/devbin' ]
}

@test "manifest_source expands ~/ and a bare ~ against HOME (0069)" {
  export HOME="$DEVBIN_TEST_TMPDIR/home"
  d="$DEVBIN_TEST_TMPDIR/consumer"
  _manifest_with_source "$d" '~/opt/devbin'
  [ "$(manifest_source "$d")" = "$HOME/opt/devbin" ]
  _manifest_with_source "$d" '~'
  [ "$(manifest_source "$d")" = "$HOME" ]
}

@test "manifest_source joins a HOME with a trailing slash without doubling it (0069)" {
  export HOME="$DEVBIN_TEST_TMPDIR/home/"
  d="$DEVBIN_TEST_TMPDIR/consumer"
  _manifest_with_source "$d" '~/opt/devbin'
  [ "$(manifest_source "$d")" = "$DEVBIN_TEST_TMPDIR/home/opt/devbin" ]
}

@test "manifest_source leaves an absolute source, a ~user form, and ~/ under an empty HOME as recorded (0069)" {
  d="$DEVBIN_TEST_TMPDIR/consumer"
  export HOME="$DEVBIN_TEST_TMPDIR/home"
  _manifest_with_source "$d" /abs/devbin
  [ "$(manifest_source "$d")" = /abs/devbin ]
  # Not a form devbin writes. Handed back verbatim, so the refusal downstream
  # names what is actually recorded.
  _manifest_with_source "$d" '~other/devbin'
  [ "$(manifest_source "$d")" = '~other/devbin' ]
  # With no HOME to expand against, "/opt/devbin" would be a real path that is
  # not the source. Verbatim is refused by name; a wrong absolute path is not.
  export HOME=""
  _manifest_with_source "$d" '~/opt/devbin'
  [ "$(manifest_source "$d")" = '~/opt/devbin' ]
  # HOME=/ behaves as empty ONLY because the trailing-slash trim reduces it to
  # nothing -- a property of that trim rather than a line of its own, so it is
  # pinned here: expanding would give `//opt/devbin`.
  export HOME=/
  _manifest_with_source "$d" '~/opt/devbin'
  [ "$(manifest_source "$d")" = '~/opt/devbin' ]
}

# --- Nothing devbin SHIPS is shaped like a home directory path (issue 0109) --
#
# The arms above hold the manifest's `# source:` line. These hold the BYTES,
# which is a different population and is where the next instance landed: 0069's
# own fix wrote an example of what an empty HOME would record into a comment in
# lib/helpers, and that example was a home-shaped path. It shipped in v0.1.1 to
# v0.1.5, and a consumer's release-archive guard then refused its own vendored copy
# of it. That guard matches /Users/<name> or /home/<name> in any tracked file
# and cannot tell prose from a path, which is not a thing a pattern can be asked
# to do. A consumer is right to refuse those bytes, so the constraint is ours.
#
# SCOPE IS THE SEAM AND NOT THE REPOSITORY, measured rather than assumed. Ask
# the repository yourself, since a number written here would be read instead of
# run:
#
#   git grep -lIE '/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+' HEAD
#
# Apart from this file, every file it names is a project record that devbin
# does not ship. THIS FILE is in the list on purpose -- its 0069 fixtures are
# home paths, and so is the control below. The records are left as they are on
# the condition that devbin writes no home path into a tracked file, so a
# repository-wide arm would go red on those records and force their scrub by
# accident. What reaches a project is what vendored_paths says, and that is the
# population this defect lives in.

# _home_shaped <file> -- the consumer's predicate, defined once so that the scan
# and its own control cannot drift apart. Prints every matching line; 1 = clean.
#
# `-I` because the predicate this copies is `git grep -lIE`: without it a binary
# file in the seam reports "Binary file ... matches" and lands in the hit list
# as a line that names no line.
#
# AND IT IS A HAND COPY OF ANOTHER PROJECT'S GUARD, with nothing holding the two
# in step. The other project's guard is the original. If that project widens its
# pattern, this arm keeps passing while the bytes devbin ships start failing
# there -- the drift is invisible from inside this repository, and the only
# remedy available here is to say so.
_home_shaped() {
  grep -nIE '/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+' "$1"
}

@test "no file devbin vendors carries a home-shaped path, and the probe still hits (0109)" {
  local rel src out rc hits="" scanned=0 control
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$(vendor_source_path "$DEVBIN_HOME" "$rel")" \
      || fail "vendored_paths names $rel and vendor_source_path cannot place it"
    [ -f "$src" ] || fail "vendored_paths names $rel, which is no file at $src"
    scanned=$((scanned + 1))
    # THE STATUS IS READ, NOT TREATED AS A BOOLEAN. grep answers 1 for "no
    # match" and 2 for "I could not read it", and an `if` collapses the two --
    # a file the probe never read would be counted as a file with nothing in
    # it, which is this project's own fallback-keyed-on-exit-status class
    # sitting inside a guard.
    rc=0
    out="$(_home_shaped "$src")" || rc=$?
    case "$rc" in
      0) hits="${hits}${rel}"$'\n'"${out}"$'\n' ;;
      1) ;;
      *) fail "the probe could not read $src (exit $rc) -- that is not a file with no match" ;;
    esac
  done <<EOF
$(vendored_paths "$DEVBIN_HOME")
EOF

  # THE POPULATION IS COUNTED AGAINST A SECOND, INDEPENDENT ENUMERATION rather
  # than against a floor. A floor of ten passed a scan that had reached ten of
  # forty-five files, and `vendored_paths` can return short without failing:
  # it suppresses find's errors and its status is the loop's, so an unreadable
  # corner of lib/ gives a short list at exit 0. The seam is the
  # launcher plus every file under the source lib, so `find` counts it here by a
  # different route -- deliberately a second enumeration, used as a control and
  # never as the source of truth.
  # find's own status is read, so an unreadable corner of lib/ fails the
  # control as well, and the two counts cannot agree on a short seam.
  local independent listing
  listing="$(find "$DEVBIN_HOME/lib" -type f)" \
    || fail "the control enumeration could not read all of $DEVBIN_HOME/lib"
  independent="$(grep -c . <<<"$listing")" \
    || fail "the control enumeration of $DEVBIN_HOME/lib found nothing to count"
  independent=$((independent + 1)) # bin/devbin
  [ "$scanned" = "$independent" ] \
    || fail "the scan covered $scanned vendored file(s) and an independent count of the seam says $independent"

  # The probe, exercised before the verdict, ON BOTH OF ITS BRANCHES. A pattern
  # that has stopped matching is silent in exactly the way a clean seam is, and
  # an alternation whose control drives one side leaves the other free to be
  # deleted with every arm still green -- measured by removing the /home half,
  # which left this file green.
  control="$DEVBIN_TEST_TMPDIR/home-shaped-control"
  printf 'one shape: /Users/someone/Devel\nthe other: /home/someone/src\n' >"$control"
  rc=0
  out="$(_home_shaped "$control")" || rc=$?
  [ "$rc" = 0 ] \
    || fail "the probe answered $rc on a file holding home paths, so its silence over the seam means nothing"
  local shapes
  shapes="$(grep -c . "$control")" || fail "the control file holds no shape"
  [ "$(grep -c . <<<"$out")" = "$shapes" ] \
    || fail "the probe caught $(grep -c . <<<"$out") of the $shapes home-path shapes it must catch: $out"

  [ -z "$hits" ] \
    || fail "vendored files carry a home-shaped path, which a consumer's guard refuses:"$'\n'"$hits"
}

# A throwaway source repo. `git init` and one commit, so HEAD resolves; the
# committer is passed with -c because a test host need not have a global one.
mksrc() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-src}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf 'seed\n' >"$dir/seed"
  git -C "$dir" add seed
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm seed
  echo "$dir"
}

# WHY SEVERAL ARMS AND NOT ONE. `source_commit` exists so a consumer can ask what
# its vendored tree corresponds to OUTSIDE itself -- `devbin_version` is a semver
# that moves once a release, so it cannot separate two installs from one release,
# and a re-vendor rewrites the files and the manifest together. The failure that
# motivated it was a consumer reporting "stock, 27 of 27" over an uncommitted
# re-vendor, with every check correct and none of them asking the question.
#
# The clean arm is asserted as a BARE sha and nothing else, because the way this
# breaks is a warning leaking onto every line -- which reads as caution and makes
# the field useless for comparison. The clean and dirty arms are then asserted to
# DIFFER, because a function that returns one string for both states passes any
# test that only checks each arm is non-empty.

@test "the manifest header names the source COMMIT, not just the version" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  [ -n "$(manifest_source_commit "$target")" ]
  [ "$(manifest_source_commit "$target")" = "$(source_commit_of "$DEVBIN_HOME")" ]
}

@test "source_commit on a clean checkout is the bare sha and nothing else" {
  src="$(mksrc)"
  want="$(git -C "$src" rev-parse HEAD)"
  got="$(source_commit_of "$src")"
  [ "$got" = "$want" ] || {
    echo "wanted the bare sha '$want', got '$got'"
    return 1
  }
  [ "${#got}" -eq 40 ]
}

@test "source_commit on a dirty checkout says the bytes match no commit" {
  src="$(mksrc)"
  clean="$(source_commit_of "$src")"
  printf 'uncommitted\n' >"$src/seed"
  dirty="$(source_commit_of "$src")"
  [[ "$dirty" == *"MATCH NO COMMIT"* ]]
  [[ "$dirty" == "$(git -C "$src" rev-parse HEAD)"* ]]
  [ "$dirty" != "$clean" ]
}

@test "source_commit on a non-checkout says so instead of going quiet" {
  src="$(mkempty notarepo)"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"not a git checkout"* ]]
  [ -n "$got" ]
}

@test "source_commit on a checkout git refuses to read says so, never 'not a git checkout' (0185)" {
  src="$(mksrc)"
  require_git_refusal "$src"
  got="$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 source_commit_of "$src")"
  [ "$got" = "a checkout git could not read -- these bytes name no commit" ] || fail "got: $got"
}

@test "vendoring from a checkout git refuses to read records so beside source: checkout, never 'not a git checkout' (0185)" {
  # Measured: the run exited 0 and the manifest contradicted itself.
  git -C "$DEVBIN_HOME" rev-parse --git-dir >/dev/null 2>&1 || skip "the devbin under test is not a checkout"
  require_git_refusal "$DEVBIN_HOME"
  target="$(mkempty)"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 devbin_install --into "$target" --name demo
  assert_success
  local m="$target/bin/.devbin/manifest.sha256"
  assert_file_contains "$m" "# source: checkout"
  assert_file_contains "$m" "# source_commit: a checkout git could not read -- these bytes name no commit"
  refute_file_contains "$m" "not a git checkout"
}

# A source with a REAL seam in it: bin/devbin plus a lib/, which is what
# devbin_lib_dir resolves and therefore what vendored_scope points git at. The
# tests above use a repo with no seam at all, which is why they could not
# have caught issue 0033 -- with nothing to narrow to, tree-wide and narrowed
# are the same question.
mkseamsrc() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-seamsrc}"
  rm -rf "$dir"
  mkdir -p "$dir/lib" "$dir/bin"
  printf '#!/usr/bin/env bash\necho devbin\n' >"$dir/bin/devbin"
  printf 'alpha\n' >"$dir/lib/alpha"
  printf 'beta\n' >"$dir/lib/beta"
  printf 'notes\n' >"$dir/NOTES.md"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm seed
  echo "$dir"
}

# WHY SEVERAL ARMS AND NOT ONE (issue 0033). The stamp answers what the VENDORED
# bytes correspond to, so the axis under test is INSIDE-vs-OUTSIDE the seam, and
# only the OUTSIDE-the-seam arm changed behaviour. The others are the regression
# guards, and the DELETION arm is the one that matters most: the fix originally
# proposed for 0033 built its pathspec from vendored_paths, which enumerates
# with `find` -- so a vendored file deleted but not committed stops being listed
# and git is asked about the names that survive. Measured on this exact fixture,
# that predicate answers CLEAN while lib/beta is missing. Under-reporting clean
# is the one direction this subsystem must never go, and no other arm here
# catches it.

@test "source_commit ignores a dirty file OUTSIDE the seam" {
  src="$(mkseamsrc)"
  want="$(git -C "$src" rev-parse HEAD)"
  printf 'scratch\n' >>"$src/NOTES.md"
  got="$(source_commit_of "$src")"
  [ "$got" = "$want" ] || {
    echo "a file outside the seam should not move the stamp; wanted '$want', got '$got'"
    return 1
  }
}

@test "source_commit still stamps a MODIFIED file inside the seam" {
  src="$(mkseamsrc)"
  printf 'edited\n' >>"$src/lib/alpha"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"MATCH NO COMMIT"* ]]
}

@test "source_commit still stamps a DELETED file inside the seam" {
  src="$(mkseamsrc)"
  rm -f "$src/lib/beta"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"MATCH NO COMMIT"* ]] || {
    echo "a deleted vendored file must still stamp dirty; got '$got'"
    return 1
  }
}

# THE STAMP AND THE CENSUS ASK ONE QUESTION THROUGH ONE FUNCTION (issue 0056).
# `fleet` was hardened against every way git can report a seam clean without
# looking at it, and this stamp was not, so `install` could record a bare sha
# over bytes the census called DIRTY. Each arm below is a way git stays silent.

@test "0056: source_commit stamps an IGNORED file inside the seam" {
  src="$(mkseamsrc)"
  printf '*.orig\n' >"$src/.gitignore"
  git -C "$src" add .gitignore
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm ignore
  printf 'stray\n' >"$src/lib/alpha.orig"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"MATCH NO COMMIT"* ]] || fail "an ignored file vendored from the seam stamped '$got'"
}

@test "0056: source_commit stamps a seam edit hidden by assume-unchanged" {
  src="$(mkseamsrc)"
  git -C "$src" update-index --assume-unchanged lib/beta
  printf 'edited\n' >>"$src/lib/beta"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"MATCH NO COMMIT"* ]] || fail "an assume-unchanged edit stamped '$got'"
}

@test "0056: source_commit stamps a SYMLINK inside the seam, whose target git never reads" {
  src="$(mkseamsrc)"
  printf 'one\n' >"$DEVBIN_TEST_TMPDIR/target"
  ln -s "$DEVBIN_TEST_TMPDIR/target" "$src/lib/linked"
  git -C "$src" add lib/linked
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm link
  printf 'two\n' >"$DEVBIN_TEST_TMPDIR/target"
  got="$(source_commit_of "$src")"
  [[ "$got" == *"MATCH NO COMMIT"* ]] || fail "a symlinked seam file stamped '$got'"
}

@test "0056: an inherited GIT_DIR does not pair another repository's status with this HEAD" {
  src="$(mkseamsrc)"
  printf 'edited\n' >>"$src/lib/alpha"
  other="$DEVBIN_TEST_TMPDIR/other"
  mkdir -p "$other"
  git -C "$other" init -q
  got="$(GIT_DIR="$other/.git" source_commit_of "$src")"
  [[ "$got" == "$(git -C "$src" rev-parse HEAD) +dirty"* ]] || fail "under an inherited GIT_DIR the stamp reads '$got'"
}

@test "0056: seam_git_verdict reads every line, and DIRTY outranks the silences" {
  # Pure: each shape as a string, and each offending line placed LATER than an
  # innocent one, because a fixture with one offending file puts it first.
  local v
  v="$(seam_git_verdict "" "H bin/devbin")"; [ "$v" = committed ] || fail "empty status: $v"
  v="$(seam_git_verdict "?? lib/new" "")"; [ "$v" = DIRTY ] || fail "untracked: $v"
  v="$(seam_git_verdict " D lib/beta" "H lib/beta")"; [ "$v" = DIRTY ] || fail "deleted: $v"
  v="$(seam_git_verdict $'!! lib/a.orig\n!! lib/b.orig' "")"; [ "$v" = "not tracked" ] || fail "ignored: $v"
  v="$(seam_git_verdict $'!! lib/.DS_Store\n M lib/alpha' "")"; [ "$v" = DIRTY ] || fail "an ignored file hid an edit: $v"
  v="$(seam_git_verdict "" $'H lib/alpha\nh lib/beta')"; [ "$v" = "not watched" ] || fail "assume-unchanged on a later line: $v"
  v="$(seam_git_verdict "" $'H lib/alpha\nS lib/beta')"; [ "$v" = "not watched" ] || fail "skip-worktree on a later line: $v"
  v="$(seam_git_verdict "!! lib/a.orig" $'H lib/alpha\nh lib/beta')"; [ "$v" = "not watched" ] || fail "not watched outranks not tracked: $v"
}

@test "0154: seam_git_state asks git about a path named --may-be-gone, and only that path may be missing" {
  local r="$DEVBIN_TEST_TMPDIR/seamrepo" m=bin/.devbin/manifest.sha256 v
  mkdir -p "$r/bin/.devbin/lib"
  printf 'x\n' >"$r/bin/devbin"
  printf 'y\n' >"$r/bin/.devbin/lib/helpers"
  printf 'z\n' >"$r/$m"
  git -C "$r" init -q
  git -C "$r" add -A
  git -C "$r" -c user.email=t@t -c user.name=t commit -q -m seam
  # There, it is read like every other path.
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib --may-be-gone "$m")"
  [ "$v" = committed ] || fail "there and committed: $v"
  # Removed and not committed: git is still asked, and says so.
  rm "$r/$m"
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib --may-be-gone "$m")"
  [ "$v" = DIRTY ] || fail "a removal git has not been told of: $v"
  # Opt-in: a path named without the option must be there, as it always had to.
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib "$m")"
  [ "$v" = UNREADABLE ] || fail "without the option a missing path read: $v"
  # A mark that stops git looking reaches the verdict for a gone path too.
  git -C "$r" update-index --skip-worktree "$m"
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib --may-be-gone "$m")"
  [ "$v" = "not watched" ] || fail "a skip-worktree removal: $v"
  git -C "$r" update-index --no-skip-worktree "$m"
  # The removal committed: the seam is as HEAD has it.
  git -C "$r" rm -q "$m"
  git -C "$r" -c user.email=t@t -c user.name=t commit -q -m gone
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib --may-be-gone "$m")"
  [ "$v" = committed ] || fail "a committed removal: $v"
  # A gone path alone is no seam, and an option naming no path is no call.
  v="$(seam_git_state "$r" --may-be-gone "$m")"
  [ "$v" = UNREADABLE ] || fail "only a gone path: $v"
  v="$(seam_git_state "$r" bin/devbin --may-be-gone)"
  [ "$v" = UNREADABLE ] || fail "an option naming no path: $v"
  # A path that IS there is read like every other, links included: a committed
  # link to a real file is not tracked, by the link rule, where asked of git
  # alone it would read committed.
  printf 'w\n' >"$r/real-manifest"
  ln -s ../../real-manifest "$r/$m"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@t -c user.name=t commit -q -m linked
  v="$(seam_git_state "$r" bin/devbin bin/.devbin/lib --may-be-gone "$m")"
  [ "$v" = "not tracked" ] || fail "a committed link named --may-be-gone: $v"
}

@test "source_commit falls back to the whole tree when there is no seam to point at" {
  src="$(mksrc nolib)"
  printf 'dirty\n' >>"$src/seed"
  got="$(source_commit_of "$src")"
  # Nothing here can be identified as devbin's half, so the narrow question
  # cannot be asked. Absent must never be readable as clean.
  [[ "$got" == *"MATCH NO COMMIT"* ]]
}

@test "the manifest records only files inside the vendored seam" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '#!/usr/bin/env bash\n' >"$target/bin/.devbin/cmd/mine"
  chmod +x "$target/bin/.devbin/cmd/mine"
  devbin_install --into "$target" --name demo --force
  assert_success
  # Asserted over the ENTRIES, not by grepping the file. It grepped the file
  # first, for "config.yaml" -- which the manifest's own header names, in the
  # course of saying it is NOT listed. So the refutation matched the prose that
  # promises the opposite of what it was refuting, and failed on a correct
  # manifest. Third time a refutation in this suite has matched documentation
  # rather than data; asking the parsed form instead makes it impossible.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    rel="${line#*	}"
    case "$rel" in
      bin/devbin | bin/.devbin/lib/*) : ;;
      *)
        echo "manifest records a path outside the seam: $rel"
        return 1
        ;;
    esac
  done <<EOF
$(manifest_entries "$target")
EOF
}

@test "a clean install verifies clean" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  states="$(manifest_check "$target")"
  case "$states" in
    *modified* | *missing*)
      echo "$states"
      return 1
      ;;
  esac
  # Not merely "nothing wrong": a verifier that examined zero files also reports
  # nothing wrong, and that is the failure mode this whole subsystem exists to
  # rule out.
  [ "$(printf '%s\n' "$states" | grep -c '^ok	' || true)" -eq \
    "$(vendored_paths "$DEVBIN_HOME" | grep -c . || true)" ]
}

@test "an edited vendored file is detected" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# edited\n' >>"$target/bin/.devbin/lib/helpers"
  states="$(manifest_check "$target")"
  case "$states" in
    *"modified	bin/.devbin/lib/helpers"*) : ;;
    *)
      echo "$states"
      return 1
      ;;
  esac
}

@test "a deleted vendored file is detected as missing, not as unchanged" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  rm "$target/bin/.devbin/lib/gatecmd"
  states="$(manifest_check "$target")"
  case "$states" in
    *"missing	bin/.devbin/lib/gatecmd"*) : ;;
    *)
      echo "$states"
      return 1
      ;;
  esac
}

@test "a vendored file devbin cannot read is detected as unreadable, not as modified (0144)" {
  local total
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  total="$(manifest_entries "$target" | grep -c .)" || total=0
  [ "$total" -gt 0 ] || fail "the manifest records no entries, so no count below means anything"
  # THE CONTROL: every entry read and ok.
  states="$(manifest_check "$target")"
  [ "$(printf '%s\n' "$states" | grep -c '^ok	')" -eq "$total" ] || fail "the control is not all ok:\n$states"
  # It read as modified: an empty sum against the recorded one.
  make_unreadable "$target/bin/.devbin/lib/gatecmd"
  states="$(manifest_check "$target")"
  case "$states" in
    *"unreadable	bin/.devbin/lib/gatecmd"*) : ;;
    *) fail "gatecmd is not unreadable:\n$states" ;;
  esac
  [[ "$states" != *"modified	bin/.devbin/lib/gatecmd"* ]] || fail "gatecmd read as modified"
  # And only it: every other entry still read and ok.
  [ "$(printf '%s\n' "$states" | grep -c '^ok	')" -eq "$((total - 1))" ] || fail "the rest are not all ok:\n$states"
}

# ============================================================================
# UPGRADE (AC-09.7, AC-09.8, AC-09.9)
# ============================================================================

@test "upgrade with nothing to do says so rather than printing an empty report" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "Already up to date"
  assert_output_contains unchanged
}

@test "upgrade with no --from follows a source recorded as ~/, and records the kind in its place (0069, 0153)" {
  target="$(mkempty)"
  export HOME="${DEVBIN_HOME%/*}"
  devbin_install --into "$target" --name demo
  assert_success
  # The ~/ form every manifest written before issue 0153 carries is WRITTEN IN
  # HERE, and DEVBIN_SOURCE is unset, so the recorded path is the only thing
  # that can lead a bare upgrade back to the source.
  m="$target/bin/.devbin/manifest.sha256"
  awk -v v='~/'"${DEVBIN_HOME##*/}" '/^# source: / { print "# source: " v; next } { print }' "$m" >"$m.new"
  mv "$m.new" "$m"
  unset DEVBIN_SOURCE
  run devbin_run "$target" upgrade
  assert_success
  # No file moves and the record does: the path gives way to the kind.
  assert_output_contains "source was:    ~/${DEVBIN_HOME##*/}"
  assert_output_contains "source now:    checkout"
  [ "$(header_of "$target" source)" = checkout ]
}

@test "a run that moves NO file but DOES move the provenance says so, and names it" {
  # THE DEFECT, measured across the projects that vendor devbin: upgrade printed
  # `Already up to date.` and left the tree MODIFIED. manifest_write rewrites
  # the header unconditionally, so `source_commit` advances on its own whenever
  # the source has moved past what was vendored -- correct behaviour, reported
  # as no behaviour, on the one file that records where the runtime came from.
  #
  # The field state is reproduced by rewriting the recorded commit rather than
  # by advancing a source: every vendored byte matches and the provenance does
  # not, which is exactly what an older install left behind in every project.
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success

  m="$target/bin/.devbin/manifest.sha256"
  sed -i.bak 's|^# source_commit: .*|# source_commit: 0000000000000000000000000000000000000000|' "$m"
  rm -f "$m.bak"

  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "0 updated"
  # The whole point: the old message is now WRONG here and must not appear.
  refute_output_contains "Already up to date"
  assert_output_contains "PROVENANCE moved"
  assert_output_contains "manifest.sha256"
  assert_output_contains "0000000000"
}

@test "upgrade replaces a vendored file that fell behind" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # Rolled back to something the manifest does NOT know, then re-recorded, so
  # the file is legitimately stale rather than edited: this is what a project
  # that installed an older devbin looks like.
  printf '#!/usr/bin/env bash\n# an older gatecmd\n' >"$target/bin/.devbin/lib/gatecmd"
  manifest_write "$target" "$DEVBIN_HOME" "$(cat "$DEVBIN_HOME/VERSION")"
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "updated    bin/.devbin/lib/gatecmd"
  assert_file_contains "$target/bin/.devbin/lib/gatecmd" "run_gate"
}

@test "upgrade restores a vendored file someone deleted" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  rm "$target/bin/.devbin/lib/gatecmd"
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "added      bin/.devbin/lib/gatecmd"
  assert_file_exists "$target/bin/.devbin/lib/gatecmd"
}

@test "upgrade refuses to overwrite a file edited in place" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "skipped    bin/.devbin/lib/helpers"
  assert_file_contains "$target/bin/.devbin/lib/helpers" "someones debugging line"
}

@test "an edit stays flagged after the refusing upgrade rewrites the manifest" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"
  run devbin_run "$target" upgrade
  assert_success
  # THE DEFECT THIS TEST EXISTS FOR. Upgrade rewrites the manifest at the end,
  # and re-checksumming a file it had just refused to replace recorded the edit
  # as canonical -- so the refusal held while the evidence for it was destroyed,
  # and the very next upgrade found nothing to refuse.
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "skipped    bin/.devbin/lib/helpers"
}

@test "upgrade --force does replace an edited file" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"
  run devbin_run "$target" upgrade --force
  assert_success
  assert_output_contains "updated    bin/.devbin/lib/helpers"
  refute_file_contains "$target/bin/.devbin/lib/helpers" "someones debugging line"
}

@test "upgrade removes a vendored file devbin no longer ships" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # A file the manifest knows and the source does not: what a devbin that DROPPED
  # a library looks like from the target's side. Left behind, it is dead code in
  # every project that ever installed the older version.
  printf '# a library from an older devbin\n' >"$target/bin/.devbin/lib/retired"
  sum="$(sha256_of "$target/bin/.devbin/lib/retired")"
  printf '%s  bin/.devbin/lib/retired\n' "$sum" >>"$target/bin/.devbin/manifest.sha256"
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/retired"
  assert_file_not_exists "$target/bin/.devbin/lib/retired"
}

@test "upgrade releases an EDITED orphan rather than deleting it" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '# an older library\n' >"$target/bin/.devbin/lib/retired"
  printf 'deadbeef  bin/.devbin/lib/retired\n' >>"$target/bin/.devbin/manifest.sha256"
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "released   bin/.devbin/lib/retired"
  assert_file_exists "$target/bin/.devbin/lib/retired"
  # And it says so IN FULL, because this is the last time devbin mentions the
  # file: it leaves the manifest here, so the next upgrade has no entry for it.
  assert_output_contains "no longer tracked"
  # The closing advice must not offer --force for it (issue 0102): --force never
  # reaches a file the manifest no longer lists. The remedy is the released
  # file's own, and the edited-in-place advice is not printed when none is.
  assert_output_contains "1 file(s) devbin no longer ships"
  refute_output_contains "Re-run with --force"
  run devbin_run "$target" upgrade
  assert_success
  refute_output_contains retired
}

@test "upgrade counts an edited file and a released one apart, each with its own remedy (0102)" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '\n# edited in place\n' >>"$target/bin/.devbin/lib/helpers"
  printf '# an older library\n' >"$target/bin/.devbin/lib/retired"
  printf 'deadbeef  bin/.devbin/lib/retired\n' >>"$target/bin/.devbin/manifest.sha256"
  run devbin_run "$target" upgrade
  assert_success
  # The summary line keeps its shape: fleet parses it across devbin versions.
  assert_output_contains "0 removed, 2 skipped"
  assert_output_contains "1 file(s) edited in place were left alone"
  assert_output_contains "Re-run with --force to replace them"
  assert_output_contains "1 file(s) devbin no longer ships were released to the project"
}

@test "upgrade never touches the project's own files" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  printf '#!/usr/bin/env bash\necho mine\n' >"$target/bin/.devbin/cmd/mine"
  chmod +x "$target/bin/.devbin/cmd/mine"
  printf '# mine\n\nAuthored.\n' >"$target/bin/.devbin/help/mine.md"
  printf '\n# a line a person wrote\n' >>"$target/bin/.devbin/config.yaml"
  run devbin_run "$target" upgrade --force
  assert_success
  assert_file_contains "$target/bin/.devbin/cmd/mine" "echo mine"
  assert_file_contains "$target/bin/.devbin/help/mine.md" "Authored."
  assert_file_contains "$target/bin/.devbin/config.yaml" "a line a person wrote"
}

@test "upgrade from a source that is not devbin writes nothing" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  before="$(sha256_of "$target/bin/devbin")"
  notdevbin="$DEVBIN_TEST_TMPDIR/notdevbin"
  mkdir -p "$notdevbin"
  run devbin_run "$target" upgrade --from "$notdevbin"
  assert_failure
  assert_output_contains "not a devbin source"
  assert_output_contains "--from"
  # Half a replaced runtime is a project that will not start at all, which is
  # worse than the stale one it was replacing.
  [ "$(sha256_of "$target/bin/devbin")" = "$before" ]
}

@test "upgrade from a source find cannot fully read refuses and SAYS WHY, removing nothing (0127, 0145)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  # It exited 1 and printed nothing at all: the failed find ended the list's
  # command substitution under errexit, with find's stderr thrown away. A list
  # that came back short instead would have removed the pages as no longer
  # shipped, so refusing is right; refusing in silence is not.
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  chmod 000 "$src/lib/pages"
  run devbin_run "$proj" upgrade --from "$src"
  chmod 755 "$src/lib/pages"
  assert_failure
  assert_output_contains "Permission denied"
  assert_output_contains "cannot list what devbin ships"
  [ -f "$proj/bin/.devbin/lib/pages/doctor.md" ] || fail "the refusing upgrade removed a page it could not see in the source"
  # AND A SOURCE DIRECTORY IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145):
  # macOS's find passed over it at rc 0, and the list came back short.
  chmod 644 "$src/lib/pages"
  run devbin_run "$proj" upgrade --from "$src"
  chmod 755 "$src/lib/pages"
  assert_failure
  assert_output_contains "cannot search $src/lib/pages -- nothing beneath it was looked at"
  assert_output_contains "cannot list what devbin ships"
  [ -f "$proj/bin/.devbin/lib/pages/doctor.md" ] || fail "the refusing upgrade removed a page it could not see in the source"
}

# _unreadable_upgrade <side> -- a project installed from a devbin source, the
# source moved on in builtins, and gatecmd unreadable on <side> (here | source),
# then upgraded: the refusal both upgrade arms below are stated over.
_unreadable_upgrade() {
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  before="$(cat "$proj/bin/.devbin/manifest.sha256")"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$proj/bin/.devbin/lib/builtins" "$kept"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  case "$1" in
    here) locked="$proj/bin/.devbin/lib/gatecmd" ;;
    source) locked="$src/lib/gatecmd" ;;
  esac
  make_unreadable "$locked"
  run devbin_run "$proj" upgrade --from "$src"
}

# _refused_whole <reason> -- refused naming gatecmd for <reason>, nothing
# written, then the control: readable again, the same upgrade goes through.
_refused_whole() {
  assert_failure
  assert_output_contains "unreadable bin/.devbin/lib/gatecmd ($1"
  assert_output_contains "Nothing was upgraded: 1 file(s) cannot be read"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refusing upgrade replaced or removed builtins"
  [ "$(cat "$proj/bin/.devbin/manifest.sha256")" = "$before" ] || fail "the refusing upgrade changed the manifest"
  chmod 644 "$locked"
  run devbin_run "$proj" upgrade --from "$src"
  assert_success
  assert_output_contains "updated    bin/.devbin/lib/builtins"
}

@test "upgrade REFUSES a file here it cannot read, and writes nothing (0144)" {
  # It read as modified, so upgrade skipped it as an edit, or with --force
  # replaced a file whose contents nobody could say.
  _unreadable_upgrade here
  _refused_whole "cannot be read here"
}

@test "upgrade REFUSES a source file it cannot read, and writes nothing (0144)" {
  # The copy loop stopped at gatecmd with builtins already replaced under the
  # old manifest.
  _unreadable_upgrade source
  _refused_whole "the source copy cannot be read"
}

@test "upgrade REFUSES over a manifest it cannot read, with or without --from, and writes nothing (0144)" {
  local src proj m kept
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  m="$proj/bin/.devbin/manifest.sha256"
  # An edit here that upgrade must refuse -- and would overwrite, reading every
  # state as new over a manifest of no entries.
  printf '\n# a local edit\n' >>"$proj/bin/.devbin/lib/builtins"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$proj/bin/.devbin/lib/builtins" "$kept"
  make_unreadable "$m"
  run devbin_run "$proj" upgrade --from "$src"
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  assert_output_contains "nothing was written"
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  assert_output_contains "nothing was written"
  refute_output_contains "name one with --from"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refusing upgrade replaced or removed builtins"
  # THE CONTROL: readable again, the edit is refused as an edit, and kept.
  chmod 644 "$m"
  run devbin_run "$proj" upgrade --from "$src"
  assert_success
  assert_output_contains "skipped    bin/.devbin/lib/builtins"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the control upgrade overwrote the edit"
}

@test "upgrade REFUSES an install with no manifest, with or without --from, writes nothing, and --force accepts the loss (0146)" {
  local src proj m kept
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  m="$proj/bin/.devbin/manifest.sha256"
  # An edit here, and the source moved on in the same file.
  printf '\n# a local edit\n' >>"$proj/bin/.devbin/lib/builtins"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$proj/bin/.devbin/lib/builtins" "$kept"
  # It read every file as new, overwrote the edit at exit 0 (`1 updated`), and
  # wrote a fresh manifest over it, so doctor passed the next run.
  rm "$m"
  run devbin_run "$proj" upgrade --from "$src"
  assert_failure
  assert_output_contains "there is no manifest at bin/.devbin/manifest.sha256, so which vendored files were edited here cannot be told; nothing was written"
  assert_output_contains "to accept that:  bin/devbin upgrade --from <dir> --force"
  assert_output_contains "install --into $proj --force"
  refute_output_contains "Upgrading from"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refusing upgrade replaced builtins"
  assert_file_not_exists "$m"
  # With no --from it is refused the same way, not sent to --from.
  run devbin_run "$proj" upgrade
  assert_failure
  assert_output_contains "there is no manifest at bin/.devbin/manifest.sha256"
  refute_output_contains "name one with --from"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refusing upgrade replaced builtins"
  assert_file_not_exists "$m"
  # A --force run whose --from is no devbin dies on that, having announced no
  # replacement it never made.
  run devbin_run "$proj" upgrade --from "$DEVBIN_TEST_TMPDIR" --force
  assert_failure
  assert_output_contains "not a devbin source"
  refute_output_contains "replaces every vendored file"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refused forced upgrade replaced builtins"
  assert_file_not_exists "$m"
  # THE CONTROL: --force accepts it, says so, replaces the edit, and writes
  # the manifest; doctor then checks the files against it.
  run devbin_run "$proj" upgrade --from "$src" --force
  assert_success
  assert_output_contains "Upgrading from"
  assert_output_contains "--force replaces every vendored file unchecked, an edit included"
  assert_output_contains "updated    bin/.devbin/lib/builtins"
  # Said once, and never the direction notice: with nothing recorded it is
  # `unknown`, and its remedy, vendor, refuses this tree.
  [ "$(grep -c 'there is no manifest' <<<"$output")" -eq 1 ] || fail "the missing manifest was said more than once:\n$output"
  refute_output_contains "cannot tell whether this source is ahead"
  refute_output_contains "vendor' first"
  grep -q 'moved on in the source' "$proj/bin/.devbin/lib/builtins" || fail "the forced upgrade did not replace builtins"
  assert_file_exists "$m"
  grep -q "^$(sha256_of "$proj/bin/.devbin/lib/builtins")  bin/.devbin/lib/builtins\$" "$m" || fail "the manifest does not record builtins at its new checksum"
  run devbin_run "$proj" doctor
  assert_output_contains "vendored files intact"
}

@test "upgrade REFUSES a manifest that records no files, as one that is missing, and the edit under it survives (0159)" {
  local src proj m kept
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  printf '\n# a local edit\n' >>"$proj/bin/.devbin/lib/builtins"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$proj/bin/.devbin/lib/builtins" "$kept"
  # Over a manifest cut to its header, every file read as new and the edit was
  # overwritten at exit 0.
  m="$proj/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$proj" upgrade --from "$src"
  assert_failure
  assert_output_contains "the manifest at bin/.devbin/manifest.sha256 records no files, so which vendored files were edited here cannot be told; nothing was written"
  cmp -s "$kept" "$proj/bin/.devbin/lib/builtins" || fail "the refusing upgrade replaced the edited builtins"
  run devbin_run "$proj" upgrade --from "$src" --force
  assert_success
  assert_output_contains "the manifest at bin/.devbin/manifest.sha256 records no files: --force replaces every vendored file unchecked"
}

@test "upgrade from a directory that does not exist fails without writing" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  run devbin_run "$target" upgrade --from "$DEVBIN_TEST_TMPDIR/nowhere"
  assert_failure
  assert_output_contains "no such directory"
}

@test "upgrade --from a relative name reads it from the current directory, never through an exported CDPATH (0267)" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # The source by a bare name in the project, where upgrade runs, and a
  # directory of the same name, no devbin, where CDPATH points.
  ln -s "$DEVBIN_HOME" "$target/src"
  mkdir -p "$DEVBIN_TEST_TMPDIR/decoy/src"
  CDPATH="$DEVBIN_TEST_TMPDIR/decoy" run devbin_run "$target" upgrade --from src
  assert_success
  assert_output_contains "Upgrading from $target/src"
  refute_output_contains "$DEVBIN_TEST_TMPDIR/decoy"
}

@test "upgrade --from - reads - as a directory under the current directory, never as OLDPWD's directory (0267)" {
  local decoy="$DEVBIN_TEST_TMPDIR/decoy"
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  # The source as a `-` in the project, where upgrade runs, and OLDPWD naming
  # a directory that is no devbin.
  ln -s "$DEVBIN_HOME" "$target/-"
  mkdir -p "$decoy"
  run bash -c 'cd "$1" && OLDPWD="$2" ./bin/devbin upgrade --from - </dev/null' _ "$target" "$decoy"
  assert_success
  assert_output_contains "Upgrading from $target/-"
  refute_output_contains "$decoy"
}

@test "upgrade in a devbin checkout refuses, names install --force and install, and never dead-ends (0213)" {
  # THE SUBJECT OF THIS TEST MOVED TWICE, AND ITS INTENT DID NOT (ST0005, 0213).
  #
  # It asserted that `upgrade` in a devbin checkout REFUSES, naming the rule
  # that devbin uses devbin; then, once the checkout had an install to publish
  # to, that it published. Since issue 0213 publishing has one verb, `install`,
  # and `install --force` is the one re-publish route, so upgrade here refuses
  # again and names both.
  #
  # What the original was really protecting is kept: the output must not point
  # at a dead end. It used to advise `install --into` this very tree, which is
  # the exact command install refuses.
  #
  # NOT run against $DEVBIN_HOME, so no arm of this file is ever one typo from
  # publishing to the operator's real install.prefix -- see devbin_install above.
  src="$(mkdevsrc)"
  run devbin_run "$src" upgrade
  assert_failure
  assert_output_contains "install --force"
  refute_output_contains "install --into"
}

@test "upgrade defaults to the source recorded at install" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "$DEVBIN_HOME"
}

# ============================================================================
# UNINSTALL (AC-09.16)
# ============================================================================

@test "removing what the manifest names leaves the project's own files behind" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo --alias dm
  assert_success
  printf '#!/usr/bin/env bash\necho mine\n' >"$target/bin/.devbin/cmd/mine"
  chmod +x "$target/bin/.devbin/cmd/mine"
  printf '# mine\n\nAuthored.\n' >"$target/bin/.devbin/help/mine.md"

  # The documented procedure (lib/pages/upgrade.md, "Uninstalling"). Devbin
  # ships no uninstall COMMAND -- it is a few rm's against paths the manifest
  # already names, and a command whose whole job is deletion is a worse thing
  # to leave lying around than those lines.
  rm -f "$target/bin/devbin"
  rm -rf "$target/bin/.devbin/lib"
  rm -f "$target/bin/.devbin/manifest.sha256"
  rm -f "$target/bin/demo" "$target/bin/dm"

  # Nothing of devbin's left...
  assert_file_not_exists "$target/bin/devbin"
  assert_directory_not_exists "$target/bin/.devbin/lib"
  assert_file_not_exists "$target/bin/.devbin/manifest.sha256"
  # ...and everything of the project's still here, which is what makes
  # re-installing over the top a restore rather than a fresh start.
  assert_file_contains "$target/bin/.devbin/cmd/mine" "echo mine"
  assert_file_contains "$target/bin/.devbin/help/mine.md" "Authored."
  assert_file_exists "$target/bin/.devbin/config.yaml"
}

@test "re-installing after an uninstall restores the project intact" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo --alias dm
  assert_success
  printf '#!/usr/bin/env bash\necho mine\n' >"$target/bin/.devbin/cmd/mine"
  chmod +x "$target/bin/.devbin/cmd/mine"
  rm -f "$target/bin/devbin" "$target/bin/demo" "$target/bin/dm"
  rm -rf "$target/bin/.devbin/lib"
  rm -f "$target/bin/.devbin/manifest.sha256"

  devbin_install --into "$target"
  assert_success
  run devbin_run "$target" doctor
  assert_success
  run devbin_run "$target" help
  assert_output_contains mine
}

# ============================================================================
# VERSION CONSTRAINTS (AC-09.13)
# ============================================================================

@test "version_satisfies honours a caret constraint on both sides of its bound" {
  version_satisfies 0.1.0 "^0.1.0"
  version_satisfies 0.1.9 "^0.1.0"
  version_satisfies 0.2.0 "^0.1.0"
  refute_assertion version_satisfies 0.0.9 "^0.1.0"
  refute_assertion version_satisfies 1.0.0 "^0.1.0"
}

@test "version_satisfies handles >= and an exact pin" {
  version_satisfies 1.2.3 ">=1.0.0"
  version_satisfies 2.0.0 ">=1.0.0"
  refute_assertion version_satisfies 0.9.9 ">=1.0.0"
  version_satisfies 1.2.3 1.2.3
  refute_assertion version_satisfies 1.2.4 1.2.3
}

@test "an undeclared constraint is satisfied and an unparseable version is not" {
  version_satisfies 0.1.0 ""
  # `unknown` is what read_version returns when it finds nothing, and it must
  # not slide past a declared constraint as though it had been checked.
  refute_assertion version_satisfies unknown "^0.1.0"
  refute_assertion version_satisfies 0.1 "^0.1.0"
}

# ============================================================================
# WHAT IS DELIBERATELY NOT BUILT (AC-09.17)
# ============================================================================

@test "there is no list command -- help --why already is one" {
  assert_file_not_exists "$DEVBIN_LIB_DIR/cmd/list"
  run devbin_run "$DEVBIN_HOME" help --why
  assert_success
  # Where each command comes from and what is not offered here, as `list` was
  # specified to print.
  assert_output_contains "from:"
  assert_output_contains "Not offered here:"
}

@test "new writes no metadata sidecar" {
  target="$(mkempty)"
  devbin_install --into "$target" --name demo
  assert_success
  run devbin_run "$target" new greet --summary "Say hello"
  assert_success
  assert_file_not_exists "$target/bin/.devbin/cmd/greet.yaml"
  # The header IS the sidecar (one source per fact).
  assert_file_contains "$target/bin/.devbin/cmd/greet" "devbin: summary"
}

# ============================================================================
# THE HARNESS USES THE REAL INSTALLER (AC-09.18)
# ============================================================================

@test "the harness installs fixtures by running devbin install" {
  # Structural, and structural on purpose: a behavioural test would pass just as
  # well with a second copy of install sitting in the harness, which is exactly
  # the thing being refused (fixtures install through the real installer).
  #
  # SCOPED TO test_helper.bash, AND THE SCOPE IS NOT AN OVERSIGHT.
  # `tests/lib/source_fixtures.bash` DOES `cp -R "$DEVBIN_LIB_DIR"`, legally: it
  # builds a devbin SOURCE, which is the thing `install --into` consumes rather
  # than a stand-in for it. Extending this grep to the whole harness would
  # forbid the one copy that has to exist. Said here because the alternative is
  # a later reader moving those fixtures back and meeting a guard whose reason
  # is invisible.
  assert_file_contains "$DEVBIN_HOME/tests/lib/test_helper.bash" 'devbin" install --into'
  run grep -nE '^\s*cp -R .*DEVBIN_LIB_DIR' "$DEVBIN_HOME/tests/lib/test_helper.bash"
  assert_failure
}
