#!/usr/bin/env bats
# localinstall.bats -- the machine install: publish, publish-upgrade, provenance
#
# WHAT IS UNDER TEST, and it is not "can devbin copy files". devbin already
# vendored fine. What was wrong is that the tree a consumer vendors FROM could be
# an uncommitted working tree, and several consuming projects were running
# bytes stamped `+dirty -- THESE BYTES MATCH NO COMMIT`. Worse, two
# vendors taken ten minutes apart from the same dirty tree carried BYTE-IDENTICAL
# `source_commit` lines over three differing files -- so the stamp could not tell
# two dirty vendors apart, and a reader comparing them concluded "level".
#
# THE DIRTY GATE IS THEREFORE THE SUBJECT, not the directory. An install cut from
# a dirty checkout launders the same bytes through one more hop and gives them the
# LOOK of provenance, which is strictly worse than today: today's manifest at
# least says THESE BYTES MATCH NO COMMIT out loud. Every other arm here supports
# that one.
#
# NOTHING RUNS AGAINST $DEVBIN_HOME. It is devbin's own source tree, so publish
# mode there aims at the operator's real machine install. Every arm uses
# `mkdevsrc` (tests/lib/test_helper.bash), which also makes the dirty gate
# testable in BOTH directions -- the real tree's cleanliness is not ours to set,
# so against it one arm would always be flaky in the direction that passes.
#
# ST0005 WP-01.

load "../lib/test_helper"

setup() {
  devbin_setup
  PREFIX="$DEVBIN_TEST_TMPDIR/opt/devbin"
}
teardown() { devbin_teardown; }

# `git status --porcelain` non-empty, by adding a file the fixture committed none of.
dirty_it() { printf 'uncommitted\n' >"$1/NOTES.md"; }

# --- the dirty gate ---------------------------------------------------------

# AT-1.3
@test "a dirty source tree REFUSES to publish, names the path, and writes nothing" {
  # THE ARM THIS FILE EXISTS FOR. The refusal must also be SILENT on disk: a gate
  # that refuses after writing half a tree has not refused.
  src="$(mkdevsrc)"
  dirty_it "$src"
  run devbin_run "$src" install
  assert_failure
  assert_output_contains "the source tree is dirty"
  assert_output_contains "NOTES.md"
  assert_directory_not_exists "$PREFIX"
}

# THE GATE ASKS THE STAMP'S QUESTION OF DEVBIN'S HALF (issue 0056). A plain
# status lists no ignored file and reads no assume-unchanged mark, and both are
# bytes that ship. After the stamp was hardened, an ignored lib/.DS_Store passed
# this gate and the install it let through was stamped +dirty.
@test "0056: an IGNORED file in the seam REFUSES to publish, and writes nothing" {
  src="$(mkdevsrc)"
  printf '.DS_Store\n' >"$src/.gitignore"
  git -C "$src" add .gitignore
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm ignore
  printf 'x' >"$src/lib/.DS_Store"
  [ -z "$(git -C "$src" status --porcelain)" ] || fail "the fixture is dirty to plain status -- this arm tests nothing"
  run devbin_run "$src" install
  assert_failure
  assert_output_contains "the source tree is dirty"
  assert_output_contains "seam: not tracked"
  assert_directory_not_exists "$PREFIX"
}

@test "0056: a seam edit hidden by assume-unchanged REFUSES publish-upgrade too" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  before="$(header_of "$PREFIX" source_commit)"
  git -C "$src" update-index --assume-unchanged lib/helpers
  printf '\n# hidden\n' >>"$src/lib/helpers"
  [ -z "$(git -C "$src" status --porcelain)" ] || fail "the fixture is dirty to plain status -- this arm tests nothing"
  run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "seam: not watched"
  [ "$(header_of "$PREFIX" source_commit)" = "$before" ] || fail "the refused upgrade rewrote the install"
}

# AT-1.3
@test "the SAME tree publishes once it is clean -- the gate is not refusing everything" {
  # The positive control for the arm above. Without it, a gate that refused
  # unconditionally would pass that test and prove nothing at all.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  assert_file_exists "$PREFIX/bin/devbin"
  assert_file_exists "$PREFIX/bin/.devbin/lib/helpers"
}

# AT-1.3
@test "publish-UPGRADE is gated on dirtiness too, not just publish" {
  # Two verbs reach the same write. A gate on one of them is a gate on neither,
  # since the ungated verb is the one that gets used the second time onwards.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  dirty_it "$src"
  run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "the source tree is dirty"
}

@test "a source git refuses to read REFUSES to publish in words that say so, and writes nothing (0185)" {
  src="$(mkdevsrc)"
  require_git_refusal "$src"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run devbin_run "$src" install
  assert_failure
  assert_output_contains "cannot publish: git cannot read the repository at"
  # git's own first line, in the C locale whatever the runner's.
  assert_output_contains "detected dubious ownership"
  refute_output_contains "is not a git repository"
  assert_directory_not_exists "$PREFIX"
}

@test "and publish-UPGRADE from a source git refuses to read says the same (0185)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  require_git_refusal "$src"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "cannot publish: git cannot read the repository at"
  assert_output_contains "detected dubious ownership"
  refute_output_contains "is not a git repository"
}

@test "a source whose index git cannot read REFUSES to publish with git's own reason, never 'not a git repository' (0185)" {
  # rev-parse answers here and status does not, so the gate cannot say what is
  # in the tree; the old refusal called it no repository, and the refusal must
  # not guess at another user's either.
  src="$(mkdevsrc)"
  break_git_index "$src"
  run devbin_run "$src" install
  assert_failure
  assert_output_contains "cannot publish: git cannot read the repository at"
  assert_output_contains "index file smaller than expected"
  refute_output_contains "is not a git repository"
  refute_output_contains "another user"
  assert_directory_not_exists "$PREFIX"
}

# AT-1.4
@test "a source that is not a git repository is REFUSED, not treated as clean" {
  # Absent must never read as clean. "No changes" and "cannot tell" are different
  # answers and only one of them may publish.
  src="$(mkdevsrc)"
  rm -rf "$src/.git"
  run devbin_run "$src" install
  assert_failure
  # The gate's own words, which git's own line in the other refusal, "fatal: not
  # a git repository", does not carry.
  assert_output_contains "is not a git repository"
  refute_output_contains "git cannot read the repository"
  assert_directory_not_exists "$PREFIX"
}

# --- what an install IS -----------------------------------------------------

# AT-1.1
@test "an install gets the runtime and NOT the project half" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  assert_file_exists "$PREFIX/bin/devbin"
  assert_file_exists "$PREFIX/bin/.devbin/lib/resolve"
  # The absence IS the mechanism, not tidiness -- it is what stops the install
  # being runnable, which is "never a cwd" delivered by construction rather than
  # by a check.
  assert_file_not_exists "$PREFIX/bin/.devbin/config.yaml"
  assert_directory_not_exists "$PREFIX/bin/.devbin/cmd"
  assert_directory_not_exists "$PREFIX/bin/.devbin/help"
}

# AT-1.2
@test "the install manifest declares kind: install, so the kind is read and never inferred" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  [ "$(header_of "$PREFIX" kind)" = install ]
}

# AT-1.2
@test "a CONSUMER manifest carries no kind -- the header is not written unconditionally" {
  # The negative control for the arm above. A `kind:` line on every manifest
  # would satisfy that test while distinguishing nothing.
  src="$(mkdevsrc)"
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  [ -z "$(header_of "$target" kind)" ]
}

# AT-1.8
@test "an install tree REFUSES to be run from, and does not advise install" {
  # `bin/devbin` dies without a config.yaml, which an install deliberately lacks.
  # The generic message says "try: devbin install" -- advice that would turn the
  # machine install into a project, so the install case gets its own.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$PREFIX" doctor
  # 5, its own code (issue 0099): it shared 3, "resolves but not implemented",
  # which let an assertion about one refusal be satisfied by the other.
  assert_exit_code 5
  assert_output_contains "is a devbin INSTALL"
  refute_output_contains "try: devbin install"
}

@test "an install whose manifest cannot be read is refused naming the manifest, never told to run install (0282)" {
  # is_install_tree reads a manifest it cannot read as no install, so the
  # dispatcher's no-config branch told the install to run `install`, which
  # would make it a project, and awk's own line once stood beside it.
  local src m
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  m="$PREFIX/bin/.devbin/manifest.sha256"
  make_unreadable "$m"
  run devbin_run "$PREFIX" doctor
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  assert_output_contains "let devbin read it, or reinstall"
  refute_output_contains "try: devbin install"
  refute_output_contains "can't open"
  refute_output_contains "Permission denied"
}

@test "a tree with no manifest and no config is still told to run install (0282)" {
  # The control for the arm above: with no manifest there is nothing to read,
  # so the advice stands.
  local src
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  rm -f "$PREFIX/bin/.devbin/manifest.sha256"
  [ ! -e "$PREFIX/bin/.devbin/manifest.sha256" ] || fail "the fixture's manifest is still there"
  run devbin_run "$PREFIX" doctor
  assert_failure
  assert_output_contains "try: devbin install"
  refute_output_contains "cannot read the manifest"
}

# --- seeding a project FROM the install (the job an install exists for) ------
#
# THE INSTALL SHIPPED UNABLE TO DO THE ONE THING IT IS FOR. `install` was caught
# by the refusal above, so a project with no devbin yet could not be seeded from
# the install at all, and the two paths that DID work were both wrong: from the
# dev tree you get whatever that tree is mid-development, and from another
# consumer you get the right bytes with THAT consumer's git HEAD recorded as
# `source_commit` -- a hash that does not exist in devbin's history. Found in a
# real onboarding attempt.

@test "install --into SEEDS a project from an install, and forwards the install's commit" {
  src="$(mkdevsrc)"
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install
  assert_success

  target="$DEVBIN_TEST_TMPDIR/seeded"
  mkdir -p "$target"
  run devbin_run "$PREFIX" install --into "$target" --name seeded
  assert_success
  [ -x "$target/bin/devbin" ]

  # The point of the arm: bytes AND provenance, not one or the other. A path
  # that copied correct files while recording a commit from another repository
  # would satisfy every other assertion here.
  [ "$(header_of "$target" source_commit)" = "$head" ]
  # It records the kind, and the switch places it once `use opt` names the
  # install (0153, 0213).
  [ "$(header_of "$target" source)" = install ]
  switch_to "$PREFIX"
  # shellcheck source=lib/helpers
  [ "$( . "$DEVBIN_LIB_DIR/helpers" && manifest_source "$target")" = "$(cd -P "$PREFIX" && pwd -P)" ]
}

@test "a BARE install from an install uses the cwd -- the documented bootstrap still works" {
  # `--into` DEFAULTS TO THE CWD and that default is CORRECT here: the
  # DEVBIN_SOURCE fallback in shell-init runs `install` from inside the new
  # project precisely so the cwd is the target. A first cut of the exemption
  # required --into and would have broken this documented route, which is why
  # the guard moved to the HARM (a dev-tree target) rather than to one flag.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success

  fresh="$DEVBIN_TEST_TMPDIR/fresh"
  mkdir -p "$fresh"
  run bash -c "cd '$fresh' && '$PREFIX/bin/devbin' install </dev/null"
  assert_success
  [ -x "$fresh/bin/devbin" ]
  [ "$(header_of "$fresh" source_commit)" = "$(header_of "$PREFIX" source_commit)" ]
}

@test "installing into a devbin SOURCE tree is refused, whatever the source is" {
  # The guard this replaces compared dstroot to srcroot, so it only caught a
  # tree installed into itself. Installing FROM THE MACHINE INSTALL into the dev
  # tree has a different source and the identical consequence, and it happened:
  # bin/.devbin/lib/ and a manifest landed in devbin's own source tree, where a
  # vendored copy sits AHEAD of lib/ in the search order and every edit stops
  # taking effect with the suite still green against the copy.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success

  run devbin_run "$PREFIX" install --into "$src"
  assert_failure
  assert_output_contains "devbin SOURCE tree"
  [ ! -e "$src/bin/.devbin/lib" ]
  [ ! -e "$src/bin/.devbin/manifest.sha256" ]
}

@test "the install refusal names install --into, not only upgrade" {
  # The message it replaced said `cd <your project> && bin/devbin upgrade`, which
  # a project with no devbin cannot run -- there is no bin/devbin there to run.
  # That is this repository's own "the remediation names a command that EXISTS"
  # defect, in the one message read by someone who has nothing installed yet.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$PREFIX" doctor
  assert_exit_code 5
  assert_output_contains "install --into"
  assert_vendor_hint "$PREFIX" "$src"
}

@test "an install ANSWERS what devbin it is, in every spelling" {
  # An install can answer questions about DEVBIN; it cannot answer questions
  # about a project, because it has none. All of these once failed from
  # $HOME. Answered by the dispatcher rather than routed to
  # lib/cmd/version, which reads a project VERSION file and declared sidecars --
  # in an install there is neither, so it would report `unknown` from a tree
  # whose manifest records the answer exactly.
  src="$(mkdevsrc)"
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install
  assert_success

  # Each prints the tree line, `devbin <version> (opt, <sha12>)` (0213), and
  # names no path (0230).
  local form
  for form in --version version "devbin --version" "devbin version"; do
    # shellcheck disable=SC2086
    run devbin_run "$PREFIX" $form
    assert_success
    [[ "$output" =~ ^devbin\ [^\ ]+\ \(opt,\ ${head:0:12}\)$ ]] || fail "$form printed: $output"
  done
}

@test "an install still refuses PROJECT questions -- the exemption is about devbin, not about scope" {
  # `devbin help` sat here as a refusal until issue 0251: help and devbin devbin
  # are answers about devbin, and an install gives them (machinepointer.bats).
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$PREFIX" doctor
  assert_exit_code 5
  run devbin_run "$PREFIX" test
  assert_exit_code 5
}

@test "shell-init runs FROM an install and bakes the install's OWN path" {
  # THE BOOTSTRAP THAT COULD NOT BOOTSTRAP. `shell-init` was exempt from the
  # wrong-tree guard and NOT from the install-tree refusal, so the one verb
  # needed from an install -- emitting the `dvb` whose whole new job is finding
  # that install -- exited 3. Caught by running the freshly published install
  # rather than by any arm here, which is the second time in one day that the
  # thing shipped and the thing verified were different.
  #
  # And the prefix comes from PROJECT_ROOT, not from config: an install IS the
  # prefix, and it deliberately has no config.yaml to read one from.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success

  run devbin_run "$PREFIX" shell-init zsh --autoload
  assert_success
  refute_output_contains "dvb() {"
  [[ "$output" == *"$PREFIX"* ]] || fail "the emitted body does not name the install it came from:\n$output"
  refute_output_contains "@@DEVBIN_INSTALL_PREFIX@@"
}

# --- provenance is transitive -----------------------------------------------

# AT-1.7
@test "the commit survives BOTH hops: dev tree to install to consumer" {
  # THE SHARPEST ARM. An install is not a git checkout, so re-deriving the commit
  # at the second hop yields "not a git checkout -- these bytes name no commit"
  # and every consumer records LESS provenance than before the install existed --
  # the exact opposite of this thread's purpose. Measured as a real defect on the
  # first consumer built against the first install, then fixed by forwarding.
  src="$(mkdevsrc)"
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install
  assert_success
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  run devbin_run "$target" upgrade --from "$PREFIX"
  assert_success

  [ "$(header_of "$PREFIX" source_commit)" = "$head" ]
  [ "$(header_of "$target" source_commit)" = "$head" ]
  # It records the kind, and the switch places it once `use opt` names the
  # install (0153, 0213).
  [ "$(header_of "$target" source)" = install ]
  switch_to "$PREFIX"
  # shellcheck source=lib/helpers
  [ "$( . "$DEVBIN_LIB_DIR/helpers" && manifest_source "$target")" = "$(cd -P "$PREFIX" && pwd -P)" ]
}

# AT-1.3
@test "a dirty publish cannot reach a consumer, because it never becomes an install" {
  # The property the two together are for: there is no path by which uncommitted
  # bytes arrive at a project through the install.
  src="$(mkdevsrc)"
  dirty_it "$src"
  run devbin_run "$src" install
  assert_failure
  assert_directory_not_exists "$PREFIX"
}

# --- the two verbs refuse in opposite directions ----------------------------

# AT-1.5
@test "install refuses an existing install and names install --force (0213)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$src" install
  assert_failure
  assert_output_contains "already installed"
  assert_output_contains "to replace it:  bin/devbin install --force"
}

# AT-1.5
@test "upgrade in devbin's own tree publishes nothing, and names install --force and install (0213)" {
  # Whichever verb you reach for, the wrong one names the right one -- so the
  # refusal is no dead end.
  src="$(mkdevsrc)"
  run devbin_run "$src" upgrade
  assert_failure
  assert_output_contains "which upgrade does not publish from"
  assert_output_contains "to replace its opt install:  bin/devbin install --force"
  assert_output_contains "to publish a new one:        bin/devbin install"
  assert_file_not_exists "$PREFIX/bin/devbin"
}

# assert_vendor_hint <dstroot> <src> -- the publish paths, and the refusal to
# run from an install, tell an operator how a project vendors from the install,
# and name no sweep of every project: that command exists only in devbin's own
# tree, and every consumer carries these bytes (0172). The printed line is then
# RUN, as printed, in a consumer vendored from <src>: a string test would pass
# the day every site agreed on a wrong line (0073), so the line has to work,
# and leave the consumer recording the install as its source.
assert_vendor_hint() {
  local dst="$1" src="$2" line consumer="$DEVBIN_TEST_TMPDIR/hintconsumer"
  local -a args
  assert_output_contains "  cd <your project> && bin/devbin upgrade --from $dst"
  refute_output_contains "fleet"
  refute_output_contains "sweep"
  line="$(printf '%s\n' "$output" | sed -n 's/^  cd <your project> && bin\/devbin \(.*\)$/\1/p')"
  [ "$(printf '%s\n' "$line" | grep -c .)" -eq 1 ] || fail "not exactly one vendor hint was printed:\n$output"
  read -r -a args <<<"$line"
  mkdir -p "$consumer"
  devbin_run "$src" install --into "$consumer" --name demo >/dev/null 2>&1 ||
    fail "the consumer the hint is run in could not be vendored"
  run devbin_run "$consumer" "${args[@]}" </dev/null
  assert_success
  [ "$(header_of "$consumer" source)" = install ] ||
    fail "the printed line ran, and the consumer does not record the install as its source:\n$output"
}

@test "PUBLISH tells an operator how a project vendors from the install, and names no sweep (0172)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  assert_output_contains "Published. Consumers vendor from here:"
  assert_vendor_hint "$DEVBIN_TEST_TMPDIR/opt/devbin" "$src"
}

@test "install --force tells an operator how a project vendors from the install, and names no sweep (0172, 0213)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  run devbin_run "$src" install --force
  assert_success
  assert_output_contains "A project carries the OLD bytes until it upgrades from here:"
  assert_vendor_hint "$DEVBIN_TEST_TMPDIR/opt/devbin" "$src"
}

# AT-1.5
@test "install --force REPLACES an existing install and reports the commit it recorded (0213)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  printf '\n# a later commit\n' >>"$src/lib/helpers"
  git -C "$src" add -A >/dev/null 2>&1
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m second >/dev/null 2>&1
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install --force
  assert_success
  assert_output_contains "replaced"
  [ "$(header_of "$PREFIX" source_commit)" = "$head" ]
}

@test "a source find cannot fully read REFUSES to vendor a project, rather than vendoring it short (0127)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  # PUBLISH is already refused here, by the dirty gate's seam line (seam:
  # UNREADABLE). Vendoring a project has no such gate, and it vendored 45 of the
  # 60 files at rc 0, the pages missing: the enumeration is the check that has
  # to refuse.
  src="$(mkdevsrc)"
  target="$DEVBIN_TEST_TMPDIR/fresh"
  mkdir -p "$target"
  chmod 000 "$src/lib/pages"
  run devbin_run "$src" install --into "$target" --name fresh
  chmod 755 "$src/lib/pages"
  assert_failure
  assert_output_contains "Permission denied"
  assert_output_contains "cannot list what devbin ships"
  [ ! -e "$target/bin/devbin" ] || fail "a vendor that could not list the source still wrote the runtime"
}

@test "publish-upgrade removes what the source stopped shipping, says so, and a project seeded after it never receives it (0123)" {
  # Publish copied and never deleted, so a file the source stopped shipping
  # stayed in the install, and every project vendored it from there as devbin's:
  # vendored_paths lists the install's lib/ with find. A project upgrade retires
  # what its source stopped shipping, and that never fired, because the install
  # never stopped shipping it.
  src="$(mkdevsrc)"
  mkdir -p "$src/lib/retired.d"
  printf '# a file devbin will stop shipping\n' >"$src/lib/retired.d/gone"
  git -C "$src" add -A >/dev/null 2>&1
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m ship >/dev/null 2>&1
  run devbin_run "$src" install
  assert_success
  refute_output_contains "removed"
  [ -f "$PREFIX/bin/.devbin/lib/retired.d/gone" ] || fail "the control: the install never held the file"
  git -C "$src" rm -rq lib/retired.d >/dev/null 2>&1
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m retire >/dev/null 2>&1
  run devbin_run "$src" install --force
  assert_success
  assert_output_contains "removed    bin/.devbin/lib/retired.d/gone (devbin no longer ships it)"
  [ ! -e "$PREFIX/bin/.devbin/lib/retired.d/gone" ] || fail "the install still holds the file the source stopped shipping"
  [ ! -d "$PREFIX/bin/.devbin/lib/retired.d" ] || fail "the directory the removal emptied was left behind"
  ! grep -q 'retired.d' "$(manifest_of "$PREFIX")" || fail "the install's manifest still records the retired file"
  target="$DEVBIN_TEST_TMPDIR/seeded"
  mkdir -p "$target"
  run devbin_run "$PREFIX" install --into "$target" --name seeded
  assert_success
  [ ! -e "$target/bin/.devbin/lib/retired.d/gone" ] || fail "a project seeded from the install received the retired file"
}

@test "publish-upgrade keeps a file devbin renamed only in case, as the file it ships, on a case-insensitive disk (0123, 0140)" {
  # The copy wrote foo into the install's Foo, find listed Foo, and the removal
  # of the unshipped Foo took foo with it: "removed bin/.devbin/lib/case.d/Foo",
  # rc 0, and every project vendoring from the install would lose the file
  # (found reviewing 0123).
  require_case_folding "$DEVBIN_TEST_TMPDIR"
  src="$(mkdevsrc)"
  ship_in_source "$src" case.d Foo '# shipped as Foo'
  run devbin_run "$src" install
  assert_success
  [ -f "$PREFIX/bin/.devbin/lib/case.d/Foo" ] || fail "the control: the install never held Foo"
  rename_case_in_source "$src" case.d Foo foo '# shipped as foo now'
  run devbin_run "$src" install --force
  assert_success
  refute_output_contains "removed    bin/.devbin/lib/case.d/Foo"
  assert_output_contains "kept bin/.devbin/lib/case.d/Foo as bin/.devbin/lib/case.d/foo"
  [ "$(ls "$PREFIX/bin/.devbin/lib/case.d" 2>&1)" = foo ] ||
    fail "case.d does not hold foo alone: $(ls -la "$PREFIX/bin/.devbin/lib/case.d" 2>&1)"
  grep -qx '# shipped as foo now' "$PREFIX/bin/.devbin/lib/case.d/foo" || fail "foo does not hold what devbin ships"
}

@test "publish_install cannot remove what it could not see: a short list refuses, and the install keeps its files (0127, 0123)" {
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 directory: the unreadable case was NOT checked"
  # The dirty gate refuses to publish from an unreadable source today, so this
  # calls the writer directly, past the gate. Since 0123 it deletes what the
  # install holds and the list lacks: read without its status, a list short of
  # the pages would delete the install's pages.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  [ -f "$PREFIX/bin/.devbin/lib/pages/doctor.md" ] || fail "the control: the install holds no pages"
  chmod 000 "$src/lib/pages"
  run bash -c ". '$src/lib/helpers' && . '$src/lib/install' && publish_install '$src' '$PREFIX' 0.0.0"
  chmod 755 "$src/lib/pages"
  assert_failure
  [ -f "$PREFIX/bin/.devbin/lib/pages/doctor.md" ] || fail "publish_install deleted a page it could not see in the source"
}

@test "publish_install reads every source file before it writes one: one it cannot read refuses, and the install is left as it was (0144)" {
  # Past the dirty gate, as above: git reports a file it cannot read as
  # modified, so the gate refuses first today, and this does not rely on that.
  # The copy loop stopped at gatecmd with builtins, before it, already replaced.
  local kept m before
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  m="$PREFIX/bin/.devbin/manifest.sha256"
  before="$(cat "$m")"
  kept="$DEVBIN_TEST_TMPDIR/builtins.before"
  cp "$PREFIX/bin/.devbin/lib/builtins" "$kept"
  printf '\n# moved on in the source\n' >>"$src/lib/builtins"
  make_unreadable "$src/lib/gatecmd"
  run bash -c ". '$src/lib/helpers' && . '$src/lib/install' && publish_install '$src' '$PREFIX' 0.0.0"
  assert_failure
  assert_output_contains "cannot read $src/lib/gatecmd"
  assert_output_contains "the install at $PREFIX is left as it was"
  cmp -s "$kept" "$PREFIX/bin/.devbin/lib/builtins" || fail "the refusing publish replaced or removed builtins"
  [ "$(cat "$m")" = "$before" ] || fail "the refusing publish changed the install's manifest"
  # THE CONTROL: readable again, the same write goes through.
  chmod 644 "$src/lib/gatecmd"
  run bash -c ". '$src/lib/helpers' && . '$src/lib/install' && publish_install '$src' '$PREFIX' 0.0.0"
  assert_success
  grep -q 'moved on in the source' "$PREFIX/bin/.devbin/lib/builtins" || fail "the control publish did not replace builtins"
}

# AT-1.5
@test "an EDITED install is named before it is replaced" {
  # An install has no author, so preserving an edit here would preserve damage --
  # the replace is wholesale either way. But a file overwritten in silence is a
  # change nobody can find afterwards.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  printf '\n# hand edit\n' >>"$PREFIX/bin/.devbin/lib/runlog"
  run devbin_run "$src" install --force
  assert_success
  assert_output_contains "edited files"
  assert_output_contains "bin/.devbin/lib/runlog"
}

@test "an install file devbin cannot read is named as such before it is replaced, never as edited (0144)" {
  # It was named as an edit: an empty checksum against the recorded one.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  # THE CONTROL: all readable, nothing is called unreadable.
  run devbin_run "$src" install --force
  assert_success
  refute_output_contains "cannot read"
  make_unreadable "$PREFIX/bin/.devbin/lib/runlog"
  run devbin_run "$src" install --force
  assert_success
  # The file's line directly under the header, not anywhere in the output.
  local under
  under="$(grep -A1 'files devbin cannot read; they are being REPLACED or removed, unread' <<<"$output")" &&
    grep -q 'bin/.devbin/lib/runlog$' <<<"$under" || fail "runlog is not named under the unreadable header:\n$output"
  refute_output_contains "edited files"
  cmp -s "$src/lib/runlog" "$PREFIX/bin/.devbin/lib/runlog" || fail "the replaced runlog is not the source's"
}

@test "install --force over a prefix with no manifest refuses, names the remedy, and writes nothing (0146, 0213)" {
  # 0146's replace-unchecked of an opt install with no manifest is withdrawn by
  # the contract (T2): an opt prefix whose manifest does not say
  # devbin wrote it is not devbin's to replace. A manifest with no rows still
  # says so in its header, and is replaced unchecked (0159, the next arm).
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  # THE CONTROL: with its manifest, nothing is said about one.
  run devbin_run "$src" install --force
  assert_success
  refute_output_contains "has no manifest"
  printf '\n# hand edit\n' >>"$PREFIX/bin/.devbin/lib/runlog"
  rm "$PREFIX/bin/.devbin/manifest.sha256"
  before="$(cksum <"$PREFIX/bin/.devbin/lib/runlog")"
  run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "its manifest does not say devbin wrote it"
  assert_output_contains "move it aside, then run: bin/devbin install"
  [ "$(cksum <"$PREFIX/bin/.devbin/lib/runlog")" = "$before" ] || fail "the refused replace wrote runlog"
  assert_file_not_exists "$PREFIX/bin/.devbin/manifest.sha256"
}

@test "publish-upgrade over an install whose manifest records no files says every file is replaced unchecked (0159)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  # Cut to its header: it read as none edited, as with no manifest at all.
  printf '\n# hand edit\n' >>"$PREFIX/bin/.devbin/lib/runlog"
  local m="$PREFIX/bin/.devbin/manifest.sha256"
  grep "^#" "$m" >"$m.hdr" && mv "$m.hdr" "$m"
  run devbin_run "$src" install --force
  assert_success
  assert_output_contains "this install's manifest records no files, so an edit in it cannot be named; every file is being REPLACED unchecked"
  cmp -s "$src/lib/runlog" "$PREFIX/bin/.devbin/lib/runlog" || fail "the publish did not replace runlog"
}

@test "publish-upgrade REFUSES over an install manifest it cannot read, and the install is left as it was (0144)" {
  local kept m
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  m="$PREFIX/bin/.devbin/manifest.sha256"
  kept="$DEVBIN_TEST_TMPDIR/runlog.before"
  printf '\n# hand edit\n' >>"$PREFIX/bin/.devbin/lib/runlog"
  cp "$PREFIX/bin/.devbin/lib/runlog" "$kept"
  # It read as none, published over it, and carried no ancestry forward.
  make_unreadable "$m"
  run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "cannot read the manifest $m"
  assert_output_contains "nothing was published"
  cmp -s "$kept" "$PREFIX/bin/.devbin/lib/runlog" || fail "the refusing publish replaced runlog"
  # THE CONTROL: readable again, the same publish goes through.
  chmod 644 "$m"
  run devbin_run "$src" install --force
  assert_success
  cmp -s "$src/lib/runlog" "$PREFIX/bin/.devbin/lib/runlog" || fail "the control publish did not replace runlog"
}

# --- the mode is announced --------------------------------------------------

# AT-1.6
@test "PUBLISH announces itself before writing anything" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  assert_output_contains "mode: PUBLISH"
  assert_output_contains "own source tree"
}

# AT-1.6
@test "VENDOR announces itself too, so the mode is never read off silence" {
  # A mode line on one branch only would be indistinguishable from a mode line
  # that failed to print.
  src="$(mkdevsrc)"
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  assert_output_contains "mode: VENDOR"
  refute_output_contains "mode: PUBLISH"
}

# --- the prefix is configuration, not a path in code ------------------------

# AT-1.9
@test "install.prefix comes from config, and --prefix overrides it" {
  src="$(mkdevsrc)"
  other="$DEVBIN_TEST_TMPDIR/elsewhere"
  run devbin_run "$src" install --prefix "$other"
  assert_success
  assert_file_exists "$other/bin/devbin"
  # The configured location is untouched, which is what makes the override real
  # rather than an additional write.
  assert_directory_not_exists "$PREFIX"
}

# AT-1.9
@test "--prefix in VENDOR mode is a usage error, not silently discarded" {
  # A flag ignored in the mode you are in would publish to the configured
  # location while the operator believed they had redirected it.
  src="$(mkdevsrc)"
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --prefix /tmp/nowhere --into "$target"
  assert_failure
  assert_output_contains "--prefix applies only when publishing"
}

# THE SAME RULE IN EVERY MODE OF BOTH VERBS (issue 0103). install refused a
# mode's foreign --prefix and ignored the rest; upgrade ignored all of them. A
# flag dropped in silence is the operator's intent dropped in silence.
@test "install refuses a VENDOR-only flag when it is publishing (0103)" {
  src="$(mkdevsrc)"
  # --force is both modes' since 0213: in PUBLISH it replaces the opt install.
  for flag in "--name demo" "--alias dm" "--lang shell"; do
    # shellcheck disable=SC2086
    run devbin_run "$src" install $flag
    assert_failure
    assert_output_contains "applies only when vendoring into a project"
  done
}

@test "upgrade refuses in devbin's own tree whatever it is given, and has no --prefix in a project (0103, 0213)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" upgrade --from /tmp/nowhere
  assert_failure
  assert_output_contains "which upgrade does not publish from"
  run devbin_run "$src" upgrade --force
  assert_failure
  assert_output_contains "which upgrade does not publish from"
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success
  run devbin_run "$target" upgrade --prefix /tmp/nowhere
  assert_failure
  assert_output_contains "unknown option '--prefix'"
}

# --- the provenance report names the field that moved -----------------------

# AT-1.10
@test "re-pointing a consumer at the install names the SOURCE, not two equal commits" {
  # FOUND BY RUNNING IT, not by reading it. `upgrade` reported "the PROVENANCE
  # moved" and then printed `was recording: <sha>` / `now records: <THE SAME
  # sha>` -- two identical values offered as evidence of a change.
  #
  # Nothing was wrong but the report. The SOURCE PATH had moved and the commit
  # had not, and before an install tree existed those two could not move
  # independently, so the case had never occurred. A report that shows a reader
  # two equal numbers and calls them a difference teaches them to stop reading it.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$DEVBIN_TEST_TMPDIR/consumer"
  mkdir -p "$target"
  run devbin_run "$src" install --into "$target" --name demo
  assert_success

  # Same bytes and same commit on both sides, so ONLY the source path can move.
  run devbin_run "$target" upgrade --from "$PREFIX"
  assert_success
  assert_output_contains "source was:"
  assert_output_contains "source now:"
  # The commit did not move, so it must not be reported as though it had.
  refute_output_contains "commit was:"
}

# --- the prefix is CONFIGURATION, and there is no default --------------------
#
# `lib/install` used to carry `DEVBIN_INSTALL_PREFIX_DEFAULT="$HOME/Devel/opt/devbin"`
# -- one operator's directory layout, baked into the runtime every project
# vendors. The location is configuration; a default is a location written into
# code that merely moves the decision to the absence of a config key. These
# arms hold the removal down.
#
# EVERY ONE OF THEM REDIRECTS $HOME, and that is the point rather than hygiene:
# with the default in place the refusal arms do not merely fail, they PUBLISH --
# to `$HOME/Devel/opt/devbin`, which may be the real tree every project on the
# machine vendors from. The redirect is what makes the red drivable at all.

# `mkdevsrc` with the one key removed, re-committed so the dirty gate is not
# what refuses. Not a second fixture builder: the shared one stays the only
# thing that knows how to build a dev tree.
strip_install_prefix() {
  local dir="$1"
  {
    printf 'project:\n  name: fixturesrc\n'
    printf 'devbin_version: "^0.1.0"\n'
  } >"$dir/bin/.devbin/config.yaml"
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m noprefix >/dev/null 2>&1
}

fakehome() {
  local h="$DEVBIN_TEST_TMPDIR/fakehome"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

@test "publish with NO install.prefix REFUSES and names the key -- it does not guess a home directory" {
  src="$(mkdevsrc)"
  strip_install_prefix "$src"
  HOME="$(fakehome)"
  export HOME
  run devbin_run "$src" install
  assert_failure
  assert_output_contains "install.prefix"
  # THE ASSERTION THAT DRIVES THE RED. A refusal that has already written the
  # tree has not refused, and the baked default wrote exactly here.
  assert_directory_not_exists "$HOME/Devel/opt/devbin"
}

@test "publish-upgrade with NO install.prefix REFUSES the same way" {
  # The mirror of the arm above, because install and upgrade resolve the prefix
  # through the same reader and a fix applied to one is not a fix.
  src="$(mkdevsrc)"
  strip_install_prefix "$src"
  HOME="$(fakehome)"
  export HOME
  run devbin_run "$src" install --force
  assert_failure
  assert_output_contains "install.prefix"
  assert_directory_not_exists "$HOME/Devel/opt/devbin"
}

@test "--prefix publishes with NO config key at all -- the parameter is the whole path in" {
  # THE POSITIVE CONTROL, and it is the arm that proves the refusals above are
  # not simply a publish that stopped working. Passing the location in is what
  # "parameterised out" has to MEAN.
  src="$(mkdevsrc)"
  strip_install_prefix "$src"
  HOME="$(fakehome)"
  export HOME
  dst="$DEVBIN_TEST_TMPDIR/explicit/devbin"
  run devbin_run "$src" install --prefix "$dst"
  assert_success
  assert_file_exists "$dst/bin/devbin"
  assert_file_exists "$dst/bin/.devbin/manifest.sha256"
  # And it went where it was told rather than where it used to default to.
  assert_directory_not_exists "$HOME/Devel/opt/devbin"
}

# --- the direction through an install (issue 0059) ---------------------------
#
# `source_direction` asked git, in the SOURCE, which way the source had moved.
# An install is not a git repository, so for every project vendoring from one --
# every project since ST0005's sweep -- the answer was `unknown`, and
# `unknown` is silent. The BEHIND-you warning that stops a silent revert
# (issue 0021, measured at 11 files) could not fire on the ordinary path.
#
# THE ANSWER IS COMPUTED WHERE THE HISTORY IS, AND CARRIED. A publish runs in a
# checkout, so it can ask git which way every commit the install has ever held
# relates to the one it holds now. The install records that table, and a
# consumer is placed by looking its recorded commit up in it. A commit the
# install never held stays `unknown`: the table is evidence, not a guess.

@test "0059: a consumer AHEAD of a rewound install is warned the install is BEHIND" {
  src="$(mkdevsrc)"
  c1="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install
  assert_success
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  target="$(consumer_of_install "$src")"

  # The install goes BACK to c1, published from a clean checkout of it.
  git -C "$src" reset -q --hard HEAD~1
  run devbin_run "$src" install --force
  assert_success

  run devbin_run "$target" upgrade
  assert_output_contains "BEHIND what is vendored here"
  assert_output_contains "REVERT"
  # And it names the install's commit rather than `unknown`: git has nothing to
  # say about a tree with no .git, and the install's own stamp does.
  assert_output_contains "upgrading to:  $c1"
}

@test "0059: a rewind is still seen two publishes later -- the table is carried, not rebuilt" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  target="$(consumer_of_install "$src")"
  commit_seam "$src" third
  run devbin_run "$src" install --force
  assert_success
  git -C "$src" reset -q --hard HEAD~2
  run devbin_run "$src" install --force
  assert_success

  run devbin_run "$target" upgrade
  assert_output_contains "BEHIND what is vendored here"
}

@test "0059: vendor reads FORWARD through an install" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success

  run devbin_run "$target" vendor
  assert_output_contains "direction         forward --"
}

@test "0059: vendor reads SAME through an install" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"

  run devbin_run "$target" vendor
  assert_output_contains "direction         same --"
}

@test "0059: an install republished from an UNRELATED history says so" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  # An ORPHAN branch in the same repository, so git holds both commits and can
  # say they share no history. A separate repository could not: it has never
  # seen the old commit, and the honest answer there is `unknown`.
  git -C "$src" checkout -q --orphan elsewhere
  git -C "$src" -c user.email=t@t -c user.name=t commit -q -m root >/dev/null 2>&1
  commit_seam "$src" elsewhere
  run devbin_run "$src" install --force
  assert_success

  run devbin_run "$target" upgrade
  assert_output_contains "shares NO history"
}

@test "0059: a commit the install never held stays UNKNOWN -- the table is evidence, not a guess" {
  # The control. Valid hex, the right length, and in no install's history: the
  # one shape a lookup that defaulted to `forward` or `same` would get wrong.
  # Published TWICE so the table has a row, or a lookup that returned its first
  # row whatever the sha would have nothing to return.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  [ -n "$(header_of "$PREFIX" ancestry)" ]
  set_recorded_commit "$target" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

  run devbin_run "$target" vendor
  assert_output_contains "direction         unknown --"
}

@test "0059: the lookup takes the consumer's OWN row, not the first one" {
  # Rows with different directions, and the consumer's commit is not the first:
  # c1 forward, c3 backward, after a rewind from c3 to c2.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  commit_seam "$src" third
  run devbin_run "$src" install --force
  assert_success
  target="$(consumer_of_install "$src")"
  git -C "$src" reset -q --hard HEAD~1
  run devbin_run "$src" install --force
  assert_success
  [ "$(header_of "$PREFIX" ancestry | wc -l | tr -d ' ')" -eq 2 ]
  local ancestry
  ancestry="$(header_of "$PREFIX" ancestry)"
  ancestry="${ancestry%%$'\n'*}"
  grep -q ' forward$' <<<"$ancestry"

  run devbin_run "$target" vendor
  assert_output_contains "direction         backward --"
}

@test "0059: a commit the publishing checkout LACKS is kept as unknown, and a later publish places it" {
  # install_ancestry's claim, held. A shallow clone holds only the commit it was
  # cut at, so a publish from it cannot place c1 and must CARRY it rather than
  # drop it: dropped, the full checkout's next publish never learns the install
  # held c1, and the consumer vendored at c1 reads `unknown` for good.
  src="$(mkdevsrc)"
  c1="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  commit_seam "$src" second
  clone="$DEVBIN_TEST_TMPDIR/shallow"
  git clone -q --depth 1 "file://$src" "$clone" >/dev/null 2>&1
  if git -C "$clone" cat-file -e "$c1^{commit}" 2>/dev/null; then
    fail "the shallow clone holds c1, so this arm tests nothing"
  fi
  run devbin_run "$clone" install --force
  assert_success
  [ "$(header_of "$PREFIX" ancestry)" = "$c1 unknown" ]

  commit_seam "$src" third
  run devbin_run "$src" install --force
  assert_success
  local ancestry
  ancestry="$(header_of "$PREFIX" ancestry)"
  grep -qx "$c1 forward" <<<"$ancestry"

  run devbin_run "$target" vendor
  assert_output_contains "direction         forward --"
}

@test "0059: a record carrying +dirty reads UNKNOWN, never same" {
  # Bytes vendored from C plus uncommitted work are not C. Against an install
  # holding C this read `same`, and upgrade dropped the work without a line.
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  set_recorded_commit "$target" "$(header_of "$PREFIX" source_commit) +dirty -- THESE BYTES MATCH NO COMMIT"

  run devbin_run "$target" vendor
  assert_output_contains "direction         unknown --"
}

@test "0059: UNKNOWN speaks when a vendored byte would change, and stays quiet when none would" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  set_recorded_commit "$target" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

  # Level bytes: nothing to revert, so no line.
  run devbin_run "$target" upgrade
  assert_success
  refute_output_contains "cannot tell"

  set_recorded_commit "$target" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  run devbin_run "$target" upgrade
  assert_output_contains "cannot tell whether this source is ahead of or BEHIND"
}

# versioned_devsrc <version> -- a dev source (mkdevsrc) whose committed VERSION
# is <version>, so an install published from it records that version: a
# fixture source has no VERSION of its own, and an install made from one
# records `unknown`, which no comparison of versions can read (0276).
versioned_devsrc() {
  local dir
  dir="$(mkdevsrc)" || return 1
  printf '%s\n' "$1" >"$dir/VERSION"
  git -C "$dir" add VERSION >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t -c maintenance.auto=false -c gc.auto=0 commit -q -m version >/dev/null 2>&1 || return 1
  printf '%s\n' "$dir"
}

# vendored_later <target> <version> -- <target>'s manifest as a project
# vendored from a later install than this machine's would carry it: a recorded
# commit the install's table cannot name, and <version>.
vendored_later() {
  local m
  set_recorded_commit "$1" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  m="$(manifest_of "$1")"
  sed "s/^# devbin_version: .*/# devbin_version: $2/" "$m" >"$m.new" && mv "$m.new" "$m"
  [ "$(header_of "$1" devbin_version)" = "$2" ] || fail "the fixture's manifest does not record devbin $2"
}

@test "where the commits cannot say which way an install source moved, a lower version reads BEHIND, naming both versions (0276)" {
  # The install's ancestry table was written when it was published, so it
  # cannot name a later commit the project records: the direction read
  # `unknown`, and upgrade said it could not tell, while both manifests'
  # versions said the source was older.
  local there=1.2.3 here a b c
  src="$(versioned_devsrc "$there")"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  [ "$(header_of "$PREFIX" devbin_version)" = "$there" ] ||
    fail "the install records devbin $(header_of "$PREFIX" devbin_version), not its source's $there"
  IFS=. read -r a b c <<<"$there"
  here="$((a + 1)).$b.$c"
  vendored_later "$target" "$here"
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  run devbin_run "$target" upgrade
  assert_output_contains "this source is BEHIND what is vendored here -- upgrading will REVERT the runtime"
  assert_output_contains "devbin $here vendored here, devbin $there in this source"
  refute_output_contains "cannot tell"
}

@test "where the commits cannot say which way an install source moved and the versions are equal, upgrade still cannot tell (0276)" {
  # Two equal X.Y.Z versions, both read: the install's and the one the
  # project records. Equal versions say nothing, since a dev tree's version
  # is not bumped per commit, so the direction stays unknown having compared
  # them, never because one side read no version at all.
  local there=1.2.3
  src="$(versioned_devsrc "$there")"
  run devbin_run "$src" install
  assert_success
  target="$(consumer_of_install "$src")"
  [ "$(header_of "$PREFIX" devbin_version)" = "$there" ] ||
    fail "the install records devbin $(header_of "$PREFIX" devbin_version), not its source's $there"
  vendored_later "$target" "$there"
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  run devbin_run "$target" upgrade
  assert_output_contains "cannot tell whether this source is ahead of or BEHIND"
  # The versions line shows both were read, and equal.
  assert_output_contains "devbin $there vendored here, devbin $there in this source"
  refute_output_contains "this source is BEHIND"
}

@test "0059: a CONSUMER manifest carries no ancestry -- only an install can vouch for its history" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  commit_seam "$src" second
  run devbin_run "$src" install --force
  assert_success
  [ -n "$(header_of "$PREFIX" ancestry)" ]
  target="$(consumer_of_install "$src")"
  [ -z "$(header_of "$target" ancestry)" ]
}

@test "0059: is_commit_sha takes hex of seven or more, and nothing shorter or wider" {
  # The length half is not redundant with the charset half: `a checkout with no
  # HEAD` reduces to `a` by first word, and `a` is valid hex.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/install
  . "$DEVBIN_LIB_DIR/install"
  # `! cmd` never trips errexit, so each refusal is asserted rather than negated.
  local w
  is_commit_sha abcdef1 || fail "a seven-character sha was refused"
  is_commit_sha 0123456789abcdef0123456789abcdef01234567 || fail "a full sha was refused"
  for w in a abcdef ABCDEF1 "abcdef1 +dirty" ""; do
    if is_commit_sha "$w"; then fail "'$w' was taken as a sha"; fi
  done
}

@test "an install published --managed-by brew is Homebrew's: install and upgrade refuse to write into it, and name brew upgrade (0195)" {
  local src keg="$DEVBIN_TEST_TMPDIR/keg/libexec"
  src="$(mkdevsrc)"
  run devbin_run "$src" install --prefix "$keg" --managed-by brew
  assert_success
  [ "$(header_of "$keg" managed_by)" = brew ] || fail "the manifest records managed_by: $(header_of "$keg" managed_by)"
  # A publish-upgrade from a checkout would replace bytes Homebrew owns.
  run devbin_run "$src" install --force --prefix "$keg"
  assert_failure
  assert_output_contains "$keg is the devbin Homebrew installed, and Homebrew replaces it whole at each version, so devbin will not write into it"
  assert_output_contains "to update it:  brew upgrade devbin"
  # So would a re-vendor into it, --force or not.
  run devbin_run "$src" install --into "$keg" --force
  assert_failure
  assert_output_contains "to update it:  brew upgrade devbin"
  # And the mark is Homebrew's alone, and a publish's alone.
  run devbin_run "$src" install --prefix "$DEVBIN_TEST_TMPDIR/other" --managed-by apt
  assert_failure
  assert_output_contains "--managed-by takes brew, the one manager devbin steps aside for, not 'apt'"
  mkdir -p "$DEVBIN_TEST_TMPDIR/proj"
  run devbin_run "$src" install --into "$DEVBIN_TEST_TMPDIR/proj" --managed-by brew
  assert_failure
  assert_output_contains "--managed-by applies only when publishing"
}

@test "an install whose manifest cannot be read is not taken as no keg: publish and publish-upgrade refuse to write into it (0195)" {
  # The check that keeps devbin out of a keg reads only a mark it can read; a
  # manifest that cannot be read is refused by each writer itself (0144), and
  # this holds that the keg is then left exactly as it was.
  [ "$(id -u)" != 0 ] || skip "running as root, which reads a mode-000 file: the unreadable case was NOT checked"
  local src keg="$DEVBIN_TEST_TMPDIR/keg/libexec" m before up_status up_output
  src="$(mkdevsrc)"
  run devbin_run "$src" install --prefix "$keg" --managed-by brew
  assert_success
  m="$keg/bin/.devbin/manifest.sha256"
  before="$(cksum <"$keg/bin/devbin")"
  chmod 000 "$m"
  run devbin_run "$src" install --force --prefix "$keg"
  up_status="$status" up_output="$output"
  run devbin_run "$src" install --prefix "$keg"
  chmod 644 "$m"
  [ "$up_status" -ne 0 ] || fail "install --force wrote into an install whose manifest cannot be read: $up_output"
  # Named by the reader, then refused by publish_replace before its tree check,
  # so it is never called a tree devbin did not write (0144, 0213).
  [[ "$up_output" == *"cannot read the manifest $m"*"its manifest cannot be read"*"nothing was published"* ]] ||
    fail "install --force did not name the unreadable manifest: $up_output"
  [[ "$up_output" != *"does not say devbin wrote it"* ]] ||
    fail "install --force called an unreadable manifest one devbin did not write: $up_output"
  # devbin's own lines only: the shell's message about the redirect it could
  # not open said the named reason again, in a form nobody can act on (0215).
  [[ "$up_output" != *"Permission denied"* ]] ||
    fail "install --force printed the shell's own error beside devbin's refusal: $up_output"
  # A publish refuses any install that is already there, before it reads the
  # manifest at all.
  assert_failure
  assert_output_contains "devbin is already installed at $keg"
  [ "$(cksum <"$keg/bin/devbin")" = "$before" ] || fail "the keg's launcher changed"
  [ "$(header_of "$keg" managed_by)" = brew ] || fail "the keg's manifest lost its mark"
}

@test "a fresh publish places every commit its checkout's HEAD contains as forward, so a new install knows the whole history (0195)" {
  # A Homebrew keg is a fresh publish at every version, so a table carried only
  # from earlier publishes was always empty there.
  local src c1 c2 want
  src="$(mkdevsrc)"
  c1="$(git -C "$src" rev-parse HEAD)"
  commit_seam "$src" second
  c2="$(git -C "$src" rev-parse HEAD)"
  commit_seam "$src" third
  run devbin_run "$src" install --prefix "$DEVBIN_TEST_TMPDIR/fresh"
  assert_success
  want="$(printf '%s forward\n%s forward' "$c2" "$c1")"
  [ "$(header_of "$DEVBIN_TEST_TMPDIR/fresh" ancestry)" = "$want" ] ||
    fail "a fresh install's table is not every commit HEAD contains, newest first:\n  want: $want\n  got:  $(header_of "$DEVBIN_TEST_TMPDIR/fresh" ancestry)"
}

@test "the version line's sha field is a recorded commit's first twelve hex digits, or unknown for one of fewer, and a dev tree's twelve take +dirty while its runtime set is dirty (0244)" {
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  local table rec want checked=0
  # The 64-digit commit is a SHA-256 repository's: until 0244 the field went on
  # from its 41st digit. Twelve and forty are the line as it always was. Each
  # call reads no stdin, which is the table, and every row is counted as
  # checked, so a row swallowed by a reader cannot pass unread.
  table='0123456|unknown
0123456789a|unknown
0123456789ab|0123456789ab
0123456789abcdef0123456789abcdef01234567|0123456789ab
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef|0123456789ab'
  while IFS="|" read -r rec want; do
    [ -n "$rec" ] || continue
    set_recorded_commit "$PREFIX" "$rec" </dev/null
    run devbin_run "$PREFIX" --version </dev/null
    assert_success
    [[ "$output" =~ ^devbin\ [^\ ]+\ \(opt,\ ([^\)]*)\)$ ]] || fail "$rec: --version printed no version line: $output"
    [ "${BASH_REMATCH[1]}" = "$want" ] || fail "$rec: the sha field is ${BASH_REMATCH[1]}, want $want"
    checked=$((checked + 1))
  done <<<"$table"
  [ "$checked" -eq "$(grep -c "|" <<<"$table")" ] || fail "checked $checked of the table's rows"
  local head
  head="$(git -C "$src" rev-parse HEAD)"
  run devbin_run "$src" --version
  assert_success
  [[ "$output" =~ \(dev,\ ${head:0:12}\)$ ]] || fail "a clean dev tree printed: $output"
  printf '# a change git has not committed\n' >>"$src/lib/helpers"
  run devbin_run "$src" --version
  assert_success
  [[ "$output" =~ \(dev,\ ${head:0:12}\+dirty\)$ ]] || fail "a dev tree with its runtime set dirty printed: $output"
}

@test "an opt install whose manifest records a dirty source prints <sha12>+dirty on its version line, and the same commit without the mark prints the twelve alone (0277)" {
  # The value was cut to its first word before anything read the mark, so a
  # recorded dirty source printed the line a clean tree at that commit prints.
  local rec=0123456789abcdef0123456789abcdef01234567
  src="$(mkdevsrc)"
  run devbin_run "$src" install
  assert_success
  set_recorded_commit "$PREFIX" "$rec +dirty -- THESE BYTES MATCH NO COMMIT"
  run devbin_run "$PREFIX" --version
  assert_success
  [[ "$output" =~ \(opt,\ ${rec:0:12}\+dirty\)$ ]] || fail "an opt install recording a dirty source printed: $output"
  set_recorded_commit "$PREFIX" "$rec"
  run devbin_run "$PREFIX" --version
  assert_success
  [[ "$output" =~ \(opt,\ ${rec:0:12}\)$ ]] || fail "an opt install recording a clean source printed: $output"
}
