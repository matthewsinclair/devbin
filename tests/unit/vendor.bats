#!/usr/bin/env bats
# vendor.bats - the tree-vs-SOURCE comparison, and upgrade's use of it (issue 0017, 0021)
#
# THE QUESTION NEITHER doctor NOR upgrade COULD ANSWER. `doctor` compares the
# vendored tree to the checksums recorded AT INSTALL TIME, which is an internal
# check: a re-vendor rewrites the files and the manifest together, so it cannot
# tell a local patch from a fresh copy. `upgrade` knows and only says so by
# DOING it. `vendor` asks how these bytes compare to the devbin they came from,
# and writes nothing.
#
# THE FIXTURES USE A MUTABLE SOURCE, which is what makes the interesting states
# constructible at all. Every test here that matters needs the SOURCE to move
# independently of the target -- a patch that has since been upstreamed is a
# fact about two trees, and with the real checkout as an immovable source it can
# only be faked by hand-editing a manifest, which would test an artificial state
# rather than the one the carry doctrine actually produces.
#
load "../lib/test_helper"
load "../lib/source_fixtures"

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


# `mksrc` and `mkempty` are in tests/lib/test_helper.bash -- version.bats needs
# the same source/install pair the runtime-digest contract is stated over.

# mkgitsrc [name] -- a mksrc that is also a real checkout with one commit, so
# the direction arms have a commit graph to be right or wrong about.
mkgitsrc() {
  local dir
  dir="$(mksrc "${1:-gitsrc}")"
  git -C "$dir" init -q
  git -C "$dir" config user.email dev@test
  git -C "$dir" config user.name dev
  git -C "$dir" add -A
  git -C "$dir" commit -qm "first"
  echo "$dir"
}

# install_from <src> <target> -- <target> vendored from <src>, which
# DEVBIN_INSTALL_PREFIX then names. Since issue 0153 a project records the KIND
# of its source, and since 0213 the machine's switch says where every kind is
# read from, so a bare `vendor` or `upgrade` here reaches <src> only because
# this names it. The override, taken as given, rather than the link: most
# sources here are mksrc trees with no .git, which are no devbin tree the link
# could name (use.bats holds what the link names).
install_from() {
  local src="$1" target="$2"
  export DEVBIN_INSTALL_PREFIX="$src"
  run devbin_run "$src" install --into "$target" --name demo
}

# ============================================================================
# THE STATES
# ============================================================================

@test "a freshly installed tree is level with its source and exits 0" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success

  run devbin_run "$target" vendor
  assert_success
  assert_output_contains "Level with"
  # The count is part of the output for the same reason doctor prints one: a
  # comparison that examined nothing must not read as a clean bill.
  assert_output_matches "[0-9]+ tracked"
  assert_output_contains "0 divergent"
}

@test "--all lists the files that match, which the default report leaves out" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success

  # The default report is the findings, so a level tree prints none of them.
  run devbin_run "$target" vendor
  assert_success
  refute_output_contains "level      bin/.devbin/lib/helpers"

  run devbin_run "$target" vendor --all
  assert_success
  assert_output_contains "level      bin/.devbin/lib/helpers"
}

@test "a file edited in place reports patched, and says upgrade would refuse it" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"

  run devbin_run "$target" vendor
  # NOT LEVEL IS AN ANSWER, NOT A FAULT -- but it is not success either, which
  # is what lets a sweep assert convergence by exit status.
  assert_failure
  assert_output_contains "patched    bin/.devbin/lib/helpers"
  assert_output_contains "refuse"
}

@test "a file the source has moved past reports behind, not patched" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # The SOURCE moves; the target is untouched. doctor cannot see this at all --
  # the tree still matches its install-time checksums exactly.
  printf '\n# a later devbin\n' >>"$src/lib/helpers"

  run devbin_run "$target" doctor
  assert_success

  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "behind     bin/.devbin/lib/helpers"
}

@test "an edit the source has since adopted reports converged, not patched" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success

  # THE CARRY DOCTRINE'S OWN SHAPE, and the state issue 0021 was filed about:
  # patch here, and the patch lands upstream. The bytes now agree with the
  # canonical ones and the manifest still records the pre-patch checksum, so
  # doctor calls it edited forever with nothing left to replace.
  printf '\n# the carried patch\n' >>"$target/bin/.devbin/lib/helpers"
  printf '\n# the carried patch\n' >>"$src/lib/helpers"

  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "converged  bin/.devbin/lib/helpers"
  refute_output_contains "patched    bin/.devbin/lib/helpers"
}

@test "a deleted vendored file reports absent" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  rm -f "$target/bin/.devbin/lib/gatecmd"

  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "absent     bin/.devbin/lib/gatecmd"
}

@test "a file the source no longer ships reports orphaned" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  rm -f "$src/lib/gatecmd"

  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "orphaned   bin/.devbin/lib/gatecmd"
}

@test "a file unreadable on BOTH sides reports unreadable, never level, and the tree is not level (0144)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # THE CONTROL: all readable, level.
  run devbin_run "$target" vendor
  assert_success
  # Two unreadable copies gave two empty sums, which are equal, and the
  # manifest's `modified` made that converged: counted as level, a false green.
  make_unreadable "$target/bin/.devbin/lib/gatecmd" "$src/lib/gatecmd"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "unreadable	bin/.devbin/lib/gatecmd"
  refute_output_contains "level	bin/.devbin/lib/gatecmd"
  refute_output_contains "converged	bin/.devbin/lib/gatecmd"
  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "unreadable bin/.devbin/lib/gatecmd"
  refute_output_contains "Level with"
  assert_output_contains "make each file marked unreadable readable"
}

@test "a file unreadable on ONE side reports unreadable, never patched or behind (0144)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # One empty sum against a real one differed, and the manifest's verdict
  # made that patched or behind: a verdict about bytes nobody read.
  make_unreadable "$target/bin/.devbin/lib/gatecmd"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "unreadable	bin/.devbin/lib/gatecmd"
  refute_output_contains "patched	bin/.devbin/lib/gatecmd"
  chmod 644 "$target/bin/.devbin/lib/gatecmd"
  make_unreadable "$src/lib/gatecmd"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "unreadable	bin/.devbin/lib/gatecmd"
  refute_output_contains "behind	bin/.devbin/lib/gatecmd"
  # THE CONTROL: readable on both sides again, level.
  chmod 644 "$src/lib/gatecmd"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "level	bin/.devbin/lib/gatecmd"
}

@test "a file no longer shipped that devbin cannot read here reports unreadable, and upgrade refuses it (0144)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  rm -f "$src/lib/gatecmd"
  # An orphan is removed as intact or released as edited, on its checksum. With
  # none it read as modified, so released: a verdict about bytes nobody read.
  make_unreadable "$target/bin/.devbin/lib/gatecmd"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "unreadable	bin/.devbin/lib/gatecmd"
  refute_output_contains "orphaned	bin/.devbin/lib/gatecmd"
  refute_output_contains "released	bin/.devbin/lib/gatecmd"
  run devbin_run "$target" upgrade --from "$src"
  assert_failure
  assert_output_contains "unreadable bin/.devbin/lib/gatecmd (no longer shipped, and cannot be read here"
  assert_output_contains "Nothing was upgraded: 1 file(s) cannot be read"
  [ -e "$target/bin/.devbin/lib/gatecmd" ] || fail "the refusing upgrade removed gatecmd"
  # THE CONTROL: readable again, it is an intact orphan, and upgrade removes it.
  chmod 644 "$target/bin/.devbin/lib/gatecmd"
  run devbin_run "$target" upgrade --from "$src"
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/gatecmd"
}

@test "vendor REFUSES a manifest it cannot read, with or without --from, rather than comparing against none (0144)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # THE CONTROL: readable, level, with level rows.
  run devbin_run "$target" vendor --from "$src"
  assert_success
  assert_output_contains "Level with"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "level	bin/.devbin/lib/"
  # It read as none: every file `new`, and with no --from no source recorded.
  make_unreadable "$target/bin/.devbin/manifest.sha256"
  run devbin_run "$target" vendor --from "$src"
  assert_failure
  assert_output_contains "cannot read the manifest $target/bin/.devbin/manifest.sha256"
  assert_output_contains "so this tree cannot be compared"
  refute_output_contains "Level with"
  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "cannot read the manifest $target/bin/.devbin/manifest.sha256"
  refute_output_contains "name one with --from"
  # And vendor_states itself, which seam_is_level asks too: no rows, rc 1.
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_failure
  refute_output_contains "level	bin/.devbin/lib/"
}

@test "vendor REFUSES an install with no manifest, with or without --from, never reading it as level or behind (0146)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # THE CONTROL: with its manifest, level, with level rows.
  run devbin_run "$target" vendor --all --from "$src"
  assert_success
  assert_output_contains "Level with"
  assert_output_contains "level      bin/.devbin/lib/"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_success
  assert_output_contains "level	bin/.devbin/lib/"
  # Every file read as new: a copy matching the source as level, so this tree,
  # with nothing recorded, said "Level with" at exit 0.
  rm "$target/bin/.devbin/manifest.sha256"
  run devbin_run "$target" vendor --all --from "$src"
  assert_failure
  assert_output_contains "there is no manifest at bin/.devbin/manifest.sha256, so which vendored files were edited here cannot be told, and this tree cannot be compared"
  assert_output_contains "upgrade --from <dir> --force"
  assert_output_contains "install --into $target --force"
  refute_output_contains "Level with"
  refute_output_contains "level      bin/.devbin/lib/"
  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "there is no manifest at bin/.devbin/manifest.sha256"
  refute_output_contains "name one with --from"
  # And vendor_states itself, which seam_is_level asks too: named, no rows,
  # rc 1 -- an edit read as `behind` there, "upgrade would replace this".
  printf '\n# a local edit\n' >>"$target/bin/.devbin/lib/builtins"
  PROJECT_ROOT="$target" run vendor_states "$target" "$src"
  assert_failure
  assert_output_contains "there is no manifest at $target/bin/.devbin/manifest.sha256"
  refute_output_contains "level	bin/.devbin/lib/"
  refute_output_contains "behind	bin/.devbin/lib/builtins"
}

@test "vendor REFUSES a manifest that records no files, never reading the tree as level (0159)" {
  local src proj m
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  m="$proj/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$proj" vendor --from "$src"
  assert_failure
  assert_output_contains "the manifest at bin/.devbin/manifest.sha256 records no files, so which vendored files were edited here cannot be told, and this tree cannot be compared"
  refute_output_contains "Level with"
}

@test "an unlisted file is reported and does NOT make the tree non-level" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # Nobody's file: not shipped by the source, not recorded by the manifest.
  # doctor already notes this; naming it here is what makes the report add up to
  # what is on disk. It is a note in both places, so the status stays 0.
  printf 'scratch\n' >"$target/bin/.devbin/lib/scratch"

  run devbin_run "$target" vendor
  assert_success
  assert_output_contains "unlisted   bin/.devbin/lib/scratch"
}

# ============================================================================
# WHAT IT IS COMPARING AGAINST -- the half that makes the report readable
# ============================================================================

@test "the report names the source it compared against" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success

  run devbin_run "$target" vendor
  assert_success
  # AN INSTRUMENT GREEN OVER AN UNNAMED BASELINE CERTIFIES NOTHING. Every run
  # says which tree it read, so a reader can tell a stale --from from a real one.
  assert_output_contains "$src"
}

@test "vendor --from a relative name reads it from the current directory, never through an exported CDPATH (0267)" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # The source by a bare name in the project, where vendor runs, and a
  # directory of the same name, no devbin, where CDPATH points.
  ln -s "$src" "$target/up"
  mkdir -p "$DEVBIN_TEST_TMPDIR/decoy/up"
  CDPATH="$DEVBIN_TEST_TMPDIR/decoy" run devbin_run "$target" vendor --from up
  assert_success
  assert_output_contains "Level with $target/up."
  refute_output_contains "$DEVBIN_TEST_TMPDIR/decoy"
}

@test "vendor --from - reads - as a directory under the current directory, never as OLDPWD's directory (0267)" {
  local decoy="$DEVBIN_TEST_TMPDIR/decoy"
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # The source as a `-` in the project, where vendor runs, and OLDPWD naming a
  # directory that is no devbin.
  ln -s "$src" "$target/-"
  mkdir -p "$decoy"
  run bash -c 'cd "$1" && OLDPWD="$2" ./bin/devbin vendor --from - </dev/null' _ "$target" "$decoy"
  assert_success
  assert_output_contains "Level with $target/-."
  refute_output_contains "$decoy"
}

@test "a source that is not a checkout reports the direction as unknown, never as fine" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success

  run devbin_run "$target" vendor
  assert_success
  # `unknown` is a real answer. The dangerous reading is the one that lets
  # "cannot tell" pass for "in step".
  assert_output_contains "unknown"
}

# THESE TWO WERE ONE TEST, AND ISSUE 0033 SPLIT THEM.
#
# The original dirtied a NON-vendored file on purpose, so the tree would be
# level and the header would be the only thing that could mislead, and asserted
# `Level with` and `MATCH NO COMMIT` together. That pairing is no longer
# reachable and should not be: the stamp answers what the VENDORED bytes
# correspond to, and NOTES.md is not one of them. The old test asserted a
# warning printed over a report in which `vendored from`, `source now at`,
# `direction same` and `0 divergent` were every one of them true.
#
# What was RIGHT in it survives as the dirty-vendored-file test below -- a bare
# sha beside a verdict read off the working tree is a confident false statement
# -- and it is aimed at a vendored file, where the working tree really does
# differ from HEAD. The OUTSIDE-the-seam test is the 0033 behaviour itself, and
# it is the regression guard: without it, widening the predicate back to the
# tree passes everything else.

@test "a dirty vendored file says so rather than printing a clean sha" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # Inside the seam, so the comparison below really does read bytes that are
  # not in any commit. This is the case the stamp exists for.
  printf 'edited\n' >>"$src/lib/install"

  run devbin_run "$target" vendor
  # NOT assert_success. A vendored file edited in the source makes the target
  # divergent, and vendor's exit status answers "is this level" -- so 1 is the
  # correct answer and asserting 0 here tested the harness, not the stamp.
  assert_failure
  assert_output_contains "MATCH NO COMMIT"
  assert_output_contains "1 divergent"
}

@test "a dirty file OUTSIDE the seam leaves the source commit stamped clean" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  want="$(git -C "$src" rev-parse HEAD)"
  # Outside the seam. The vendored bytes still match HEAD exactly, so the
  # honest answer is the bare sha (issue 0033).
  printf 'scratch\n' >"$src/NOTES.md"

  run devbin_run "$target" vendor
  assert_success
  assert_output_contains "Level with"
  assert_output_contains "$want"
  refute_output_contains "MATCH NO COMMIT"
}

@test "a source ahead of what was vendored reports forward" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# later\n' >>"$src/lib/helpers"
  git -C "$src" commit -qam "second"

  run devbin_run "$target" vendor
  assert_failure
  assert_output_contains "forward"
}

@test "a source BEHIND what was vendored reports backward" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # Install stamped HEAD. Roll the source back one commit and the recorded
  # commit is now a DESCENDANT of it -- which is the silent downgrade upgrade
  # will otherwise perform while printing `updated` per file (issue 0021).
  printf '\n# later\n' >>"$src/lib/helpers"
  git -C "$src" commit -qam "second"
  run devbin_run "$src" install --into "$target" --force --name demo
  assert_success
  git -C "$src" reset -q --hard HEAD~1

  run devbin_run "$target" vendor
  assert_output_contains "backward"
}

# ============================================================================
# IT WRITES NOTHING
# ============================================================================

@test "vendor leaves the manifest and every vendored file exactly as it found them" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"
  before="$(sha256_of "$target/bin/.devbin/manifest.sha256")"
  before_file="$(sha256_of "$target/bin/.devbin/lib/helpers")"

  run devbin_run "$target" vendor
  assert_failure
  # PROOF THE COMMAND ACTUALLY RAN. Without this the test passed against a
  # devbin that has no `vendor` at all: a command that does not exist also
  # writes nothing, and "wrote nothing" cannot tell the two apart.
  assert_output_contains "patched    bin/.devbin/lib/helpers"

  # A REPORTER THAT RESTAMPS IS A LAUNDERER. The manifest is the evidence for
  # the very state being reported, so writing it here would destroy the finding
  # in the act of printing it -- the same defect the refusing upgrade had.
  [ "$(sha256_of "$target/bin/.devbin/manifest.sha256")" = "$before" ]
  [ "$(sha256_of "$target/bin/.devbin/lib/helpers")" = "$before_file" ]
}

@test "vendor in a devbin checkout says it runs lib/ in place rather than naming a dead-end install" {
  # THE SAME UNREACHABLE STATE THE UPGRADE SUITE ALREADY RETIRED. Deleting
  # bin/.devbin/lib and expecting "not installed" cannot work: with the runtime
  # gone the DISPATCHER dies first, hunting the library it must load in order to
  # have a `vendor` command at all -- so the test passes on exit 127 and proves
  # nothing. The reachable case is the devbin checkout, running its own lib/ via
  # the devbin-uses-devbin fallback, where is_devbin_installed is correctly
  # false and there is genuinely nothing vendored to compare.
  #
  # THE REFUSAL HAS TO BE A REFUSAL: a status is not a verdict unless something
  # in the output says which verdict it is.
  run devbin_run "$DEVBIN_HOME" vendor
  assert_failure
  assert_output_contains "not installed"
  assert_output_contains "lib/ in place"
  # The dead-end remediation upgrade was corrected for: `install --into` this
  # very tree is the exact command install refuses.
  refute_output_contains "install --into"
}

# ============================================================================
# UPGRADE'S USE OF THE SAME COMPARISON (issue 0021)
# ============================================================================

@test "upgrade heals a converged file instead of skipping it forever" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# the carried patch\n' >>"$target/bin/.devbin/lib/helpers"
  printf '\n# the carried patch\n' >>"$src/lib/helpers"

  # THE DEFECT: the modified-vs-manifest check ran BEFORE the source-equality
  # compare, so a file that already matched the canonical bytes was skipped as
  # "edited in place", kept its install-time checksum, and left doctor red with
  # nothing upgrade could ever change.
  run devbin_run "$target" upgrade
  assert_success
  refute_output_contains "skipped    bin/.devbin/lib/helpers"

  run devbin_run "$target" doctor
  assert_success

  run devbin_run "$target" vendor
  assert_success
}

@test "upgrade still refuses a file that differs from the source" {
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# someones debugging line\n' >>"$target/bin/.devbin/lib/helpers"

  # The converged fix must not become a licence to overwrite. Equality is the
  # whole of it: differ by one byte and the refusal stands.
  run devbin_run "$target" upgrade
  assert_success
  assert_output_contains "skipped    bin/.devbin/lib/helpers"
  assert_file_contains "$target/bin/.devbin/lib/helpers" "someones debugging line"
}

@test "upgrade warns before reverting the runtime to an older source" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# later\n' >>"$src/lib/helpers"
  git -C "$src" commit -qam "second"
  run devbin_run "$src" install --into "$target" --force --name demo
  assert_success
  git -C "$src" reset -q --hard HEAD~1

  # Measured before it was guarded: 11 files silently reverted, `updated`
  # printed per file, doctor green afterwards. The warning is what makes the
  # difference visible; it is deliberately not a refusal, because a deliberate
  # rollback is a real thing to do.
  run devbin_run "$target" upgrade
  assert_output_contains "REVERT"
}

@test "upgrade --force over a manifest that records no files still warns of a REVERT, and never sends the reader to vendor, which refuses that manifest (0159)" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf '\n# later\n' >>"$src/lib/helpers"
  git -C "$src" commit -qam "second"
  run devbin_run "$src" install --into "$target" --force --name demo
  assert_success
  git -C "$src" reset -q --hard HEAD~1
  # Cut to its header, which still records the commit, so the direction is read.
  local m="$target/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$target" upgrade --force
  assert_success
  assert_output_contains "REVERT"
  refute_output_contains "vendor' first"
}

@test "upgrade --force over a manifest that records no files, from a source that cannot place it, never sends the reader to vendor either (0159)" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # A recorded commit the source does not hold: the direction is unknown, and
  # bytes would move, so the notice speaks.
  printf '\n# moved on\n' >>"$src/lib/helpers"
  git -C "$src" commit -qam "moved on"
  local m="$target/bin/.devbin/manifest.sha256"
  grep "^#" "$m" | sed 's/^# source_commit: .*/# source_commit: 0123456789abcdef0123456789abcdef01234567/' >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$target" upgrade --force
  assert_success
  assert_output_contains "cannot tell whether this source is ahead of or BEHIND"
  refute_output_contains "vendor' first"
}

@test "vendor_states reads a manifest that records no files as it reads a missing one: no rows, rc 1, named (0159)" {
  local src proj m
  src="$(mkdevsrc)"
  proj="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$proj"
  run devbin_run "$src" install --into "$proj" --name consumer
  assert_success
  m="$proj/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run vendor_states "$proj" "$src"
  [ "$status" -eq 1 ] || fail "vendor_states over a manifest that records no files returned $status:\n$output"
  assert_output_contains "the manifest at $m records no files, so which vendored files were edited there cannot be told"
  refute_output_contains "level	"
}

# ============================================================================
# THE NOTICE ANSWERS A QUESTION ABOUT BYTES, NOT ONE ABOUT COMMITS (issue 0053)
#
# `source_direction` compares history. `will REVERT the runtime` is a claim
# about this tree. The two came apart the moment a commit touched no vendored
# file, which is the ordinary case rather than an exotic one: a documentation
# commit, a planning-file commit, a released note. Measured on this repository:
# two commits that differ by zero paths under `bin/devbin` and `lib/`, and a
# project installed from the later one was told upgrading to the earlier would
# REVERT its runtime, four lines before the same command reported `No vendored
# file differs`.
#
# The tests below cover both directions and each is needed. The REVERT
# test above this section is the control: it edits `lib/helpers`, so its bytes
# really do move and its warning must survive this change untouched.
# ============================================================================

@test "a source BEHIND but byte-identical does NOT say REVERT" {
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # A commit that touches nothing under the seam. This is what a docs commit,
  # a planning-file commit or a release note looks like to `upgrade`.
  printf 'notes\n' >"$src/NOTES.md"
  git -C "$src" add -A
  git -C "$src" commit -qm "docs only, no seam change"
  run devbin_run "$src" install --into "$target" --force --name demo
  assert_success
  git -C "$src" reset -q --hard HEAD~1

  run devbin_run "$target" upgrade
  refute_output_contains "REVERT"
  assert_output_contains "NO vendored file would change"
  assert_output_contains "byte-identical"
}

@test "the direction is still reported when nothing would change -- it is the reason, not the alarm" {
  # Suppressing the whole notice would be the other over-correction. The stamp
  # really does move backward, and `fleet audit` reads that stamp -- so an
  # operator has something to know here even though no byte moves.
  src="$(mkgitsrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  printf 'notes\n' >"$src/NOTES.md"
  git -C "$src" add -A
  git -C "$src" commit -qm "docs only, no seam change"
  run devbin_run "$src" install --into "$target" --force --name demo
  assert_success
  git -C "$src" reset -q --hard HEAD~1

  run devbin_run "$target" upgrade
  assert_output_contains "BEHIND what is vendored here"
  assert_output_contains "vendored from:"
  assert_output_contains "upgrading to:"
}

@test "seam_is_level FAILS CLOSED when the comparison cannot be made" {
  # The default matters more than the happy path: a broken check that returned
  # "level" would silence a real REVERT warning exactly when the instrument
  # itself is the thing that is broken.
  src="$(mksrc)"
  target="$(mkempty)"
  install_from "$src" "$target"
  assert_success
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  PROJECT_ROOT="$target" run seam_is_level "$target" "$DEVBIN_TEST_TMPDIR/not-a-source"
  assert_failure
}
