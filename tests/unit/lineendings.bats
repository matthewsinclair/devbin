#!/usr/bin/env bats
# lineendings.bats - LF held by the repository (ST0008 WP-01)
#
# A checkout that converts line endings breaks a shell runtime where nothing
# points at the cause: a shebang reads `bash\r`, a vendored file reads as edited
# in place. So devbin's own tree holds LF in its .gitattributes, every project
# devbin is vendored into gets devbin's block in its root .gitattributes, and
# doctor asks git, with `git check-attr eol`, whether the rule holds, and names
# a file that already carries CR bytes, with the cause.

load "../lib/test_helper"

setup() {
  devbin_setup
}
teardown() { devbin_teardown; }

# gitinstalled [name] -- a project devbin is installed into, committed as a
# checkout.
gitinstalled() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-demo}"
  mkdir -p "$dir"
  "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name "${1:-demo}" >/dev/null || return 1
  printf 'tmp/\n' >"$dir/.gitignore"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm install
  printf '%s\n' "$dir"
}

# not_lf <root> -- each of bin/devbin and the files under bin/.devbin/ that
# git does not hold to LF there, as check-attr prints it.
not_lf() {
  local root="$1" f out
  local -a rels=(bin/devbin)
  while IFS= read -r f; do
    rels+=("bin/.devbin/${f#"$root/bin/.devbin"/}")
  done < <(find "$root/bin/.devbin" -type f)
  # rels opens with the launcher, so a find that read nothing leaves it at one.
  [ "${#rels[@]}" -gt 1 ] || {
    echo "no file under $root/bin/.devbin"
    return 0
  }
  # Read whole, its status read, so a git that answered nothing is a failure
  # and never an empty list of loose files.
  out="$(git -C "$root" check-attr eol -- "${rels[@]}")" || {
    echo "git check-attr failed in $root"
    return 1
  }
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq "${#rels[@]}" ] || {
    echo "git answered for fewer than the ${#rels[@]} files asked"
    return 1
  }
  printf '%s\n' "$out" | grep -v ': eol: lf$' || [ $? -eq 1 ]
}

# AT-1.1
@test "devbin's root .gitattributes holds every tracked file to LF, and text=auto leaves binaries alone (AC-1.1)" {
  local out bad tracked
  assert_file_contains "$DEVBIN_HOME/.gitattributes" '* text=auto eol=lf'
  # THE RULE AS GIT READS IT, file by file, so a rule narrowed to `*.sh`, or
  # undone by a later line, leaves the extensionless scripts out and fails.
  out="$(cd "$DEVBIN_HOME" && git ls-files -z | xargs -0 git check-attr text eol --)"
  # Every file git tracks answered, against git's own listing of them.
  tracked="$(cd "$DEVBIN_HOME" && git ls-files | grep -c .)" || fail "git ls-files listed nothing in $DEVBIN_HOME"
  [ "$(printf '%s\n' "$out" | grep -c ': eol: lf$')" -eq "$tracked" ] ||
    fail "check-attr answered eol: lf for fewer than the $tracked files git tracks"
  bad="$(printf '%s\n' "$out" | grep -v -e ': eol: lf$' -e ': text: auto$' || true)"
  [ -z "$bad" ] || fail "tracked files not held to LF, text=auto:
$bad"
}

# AT-1.1
@test "no tracked text file in devbin's tree carries a CR byte (AC-1.1)" {
  local hits
  hits="$(cd "$DEVBIN_HOME" && LC_ALL=C git grep -I -l -e $'\r')" || [ $? -eq 1 ] || fail "git grep could not read the tree"
  [ -z "$hits" ] || fail "tracked text files carrying CR bytes:
$hits"
}

# AT-1.2
@test "install writes devbin's block, and git holds bin/devbin and every file under bin/.devbin/ to LF (AC-1.2)" {
  local proj
  proj="$(gitinstalled)"
  assert_file_contains "$proj/.gitattributes" '# >>> devbin: line endings >>>'
  run not_lf "$proj"
  assert_success
  assert_output ""
  run devbin_run "$proj" doctor
  assert_output_contains "ok    line endings: .gitattributes holds bin/devbin and everything under bin/.devbin/ to LF"
}

# AT-1.2
@test "install keeps the project's own .gitattributes lines, byte for byte, and adds the block after them (AC-1.2)" {
  local dir="$DEVBIN_TEST_TMPDIR/own"
  mkdir -p "$dir"
  printf '*.png binary\n*.md diff=markdown' >"$dir/.gitattributes"
  run "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name own
  assert_success
  assert_output_contains "added      devbin's line-ending block to .gitattributes"
  # Byte for byte: the last line gains the newline the block needs to follow
  # it, and nothing else of the project's moves.
  [ "$(head -c 33 "$dir/.gitattributes" | od -c)" = "$(printf '*.png binary\n*.md diff=markdown\n\n' | od -c)" ] ||
    fail "the project's lines moved: $(cat "$dir/.gitattributes")"
  [ "$(grep -c 'devbin: line endings' "$dir/.gitattributes")" -eq 2 ] || fail "not one block"
}

# AT-1.2
@test "upgrade puts back an edited block and a deleted one, and keeps one as written without a word (AC-1.2)" {
  local proj
  proj="$(gitinstalled)"
  run devbin_run "$proj" upgrade --from "$DEVBIN_HOME"
  assert_success
  refute_output_contains ".gitattributes"
  assert_output_contains "Already up to date."
  sed 's/eol=lf/eol=crlf/' "$proj/.gitattributes" >"$proj/ga" && mv "$proj/ga" "$proj/.gitattributes"
  run devbin_run "$proj" upgrade --from "$DEVBIN_HOME"
  assert_success
  assert_output_contains "updated    devbin's line-ending block in .gitattributes"
  assert_output_contains "Runtime already up to date; only .gitattributes changed (above)."
  run not_lf "$proj"
  assert_output ""
  rm "$proj/.gitattributes"
  run devbin_run "$proj" upgrade --from "$DEVBIN_HOME"
  assert_output_contains "wrote      .gitattributes"
  run not_lf "$proj"
  assert_output ""
  run git -C "$proj" status --porcelain
  assert_output ""
}

# AT-1.2
@test "a block in place keeps the project's last line without its newline, and a quoted marker is the project's line (AC-1.2)" {
  local dir="$DEVBIN_TEST_TMPDIR/tail" before
  mkdir -p "$dir"
  "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name tail >/dev/null
  printf '# see "# >>> devbin: line endings >>>" below\n*.png binary' >>"$dir/.gitattributes"
  before="$(od -c "$dir/.gitattributes")"
  cd "$dir"
  run ./bin/devbin upgrade --from "$DEVBIN_HOME"
  assert_success
  refute_output_contains ".gitattributes"
  [ "$(od -c "$dir/.gitattributes")" = "$before" ] || fail "the file changed: $(cat "$dir/.gitattributes")"
}

# AT-1.2
@test "a marker that does not make one block is refused by name, and the file is left as it was (AC-1.2)" {
  local proj before
  proj="$(gitinstalled)"
  printf 'a\n# >>> devbin: line endings >>>\nb\n' >"$proj/.gitattributes"
  before="$(cat "$proj/.gitattributes")"
  run devbin_run "$proj" upgrade --from "$DEVBIN_HOME"
  assert_failure
  assert_output_contains "has a devbin line-ending marker that does not make one block"
  assert_output_contains "devbin's line-ending block is not in .gitattributes"
  [ "$(cat "$proj/.gitattributes")" = "$before" ] || fail "the file was written"
}

# AT-1.2
@test "a fixture install_devbin makes and a real install leave the same .gitattributes, with the project's own lines or without (AC-1.2)" {
  local fx real
  fx="$(create_test_project fx)"
  install_devbin "$fx"
  real="$DEVBIN_TEST_TMPDIR/real"
  mkdir -p "$real"
  "$DEVBIN_BIN_DIR/devbin" install --into "$real" --name real >/dev/null
  [ -f "$fx/.gitattributes" ] || fail "install_devbin wrote no .gitattributes"
  cmp "$fx/.gitattributes" "$real/.gitattributes" || fail "the fixture's .gitattributes is not the real install's"
  fx="$(create_test_project fx2)"
  printf '*.png binary\n' >"$fx/.gitattributes"
  install_devbin "$fx"
  printf '*.png binary\n' >"$real/.gitattributes"
  "$DEVBIN_BIN_DIR/devbin" install --into "$real" --force >/dev/null
  cmp "$fx/.gitattributes" "$real/.gitattributes" || fail "over the project's own lines, the fixture's .gitattributes is not the real install's"
}

# AT-1.2
@test "doctor names each vendored path a later rule takes off LF, and the fix (AC-1.2)" {
  local proj
  proj="$(gitinstalled)"
  printf 'bin/.devbin/lib/pages/** eol=crlf\n' >>"$proj/.gitattributes"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  line endings:"
  assert_output_contains "not held to LF by .gitattributes"
  assert_output_contains "not LF:  bin/.devbin/lib/pages/doctor.md (eol: crlf)"
  assert_output_contains "fix: bin/devbin upgrade writes devbin's line-ending block into .gitattributes"
  refute_output_contains "not LF:  bin/devbin "
}

# AT-1.2
@test "doctor in a project that is not a git checkout says the rule is not checked, as a note (AC-1.2)" {
  local dir="$DEVBIN_TEST_TMPDIR/plain"
  mkdir -p "$dir"
  "$DEVBIN_BIN_DIR/devbin" install --into "$dir" --name plain >/dev/null
  run devbin_run "$dir" doctor
  assert_output_contains "note  line endings: not a git checkout, so no git converts them and no .gitattributes rule is checked"
  refute_output_contains "FAIL  line endings"
}

# AT-1.3
@test "a vendored file carrying CR bytes fails doctor by name, with CRLF line endings as the cause (AC-1.3)" {
  local proj
  proj="$(gitinstalled)"
  printf '# x\r\n' >>"$proj/bin/.devbin/lib/pages/doctor.md"
  run devbin_run "$proj" doctor
  assert_failure
  assert_output_contains "FAIL  line endings: 1 file(s) carry CR bytes -- CRLF line endings, not an edit"
  assert_output_contains "CRLF:    bin/.devbin/lib/pages/doctor.md"
  assert_output_contains "edited:  bin/.devbin/lib/pages/doctor.md (it carries CR bytes: CRLF line endings, see line endings below)"
  refute_output_contains "CRLF:    bin/.devbin/lib/pages/check.md"
}
