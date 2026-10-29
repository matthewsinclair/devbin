#!/usr/bin/env bats
# shellinit.bats -- the shell function devbin emits, and the two defects that
# made it a command instead of a README snippet.
#
# BOTH DEFECTS WERE FOUND IN A LANDED COPY, NOT HERE. The snippet had no test at
# all, which is why a body that silently ran a different project's launcher at
# exit 0 survived until the function was first used in a real shell. These arms
# exist so the next change to the body has to face them.

# WHY THIS FILE CALLS create_test_project AND install_devbin RATHER THAN mkproj,
# kept as history (issue 0041). When it was written, mkproj was a four-line
# wrapper over those two, copied into test file after test file instead of
# living in the shared test helpers, and one more copy would have made that
# Highlander breach worse to save two lines. 0041 moved mkproj into
# tests/lib/test_helper.bash; calling the shared helpers directly was never the
# breach, so they stay.

load "../lib/test_helper"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# emit <proj> [shell] -- the body for <shell>, zsh by default, into dvb.<shell>.
emit() {
  local proj="$1" sh="${2:-zsh}"
  devbin_run "$proj" shell-init "$sh" >"$DEVBIN_TEST_TMPDIR/dvb.$sh"
}

# dvb_shells -- set DVB_SHELLS to the shells whose body the arms below run:
# bash, which every devbin machine has, and zsh. On CI a missing zsh FAILS the
# arm, as require_command does, because a bash-only green there would be a
# coverage hole reported as a pass; elsewhere the arm runs the bash half alone.
dvb_shells() {
  DVB_SHELLS=(bash)
  if command_exists zsh; then
    DVB_SHELLS+=(zsh)
  elif [[ -n "${CI:-}" ]]; then
    fail "zsh is not installed on this CI runner, so the arm would prove bash alone -- install it in .github/workflows/tests.yml"
  fi
}

# in_shell <shell> <script> -- run <script> in a clean <shell>, no rc files
# read, with nounset on, as some users' rcs set it, and that shell's emitted dvb
# sourced first: an unguarded variable in the body then fails every arm.
in_shell() {
  case "$1" in
    zsh) zsh -f -c "setopt nounset; source '$DEVBIN_TEST_TMPDIR/dvb.zsh'; $2" ;;
    bash) bash --norc --noprofile -c "set -u; source '$DEVBIN_TEST_TMPDIR/dvb.bash'; $2" ;;
    *) fail "in_shell: no such shell '$1'" ;;
  esac
}

# A project whose launcher announces which one it is.
mklauncher() {
  local dir="$1" label="$2" mode="$3"
  mkdir -p "$dir/bin"
  printf '#!/bin/sh\necho "%s launcher ran"\n' "$label" >"$dir/bin/devbin"
  chmod "$mode" "$dir/bin/devbin"
}

# AT-3.1
@test "shell-init emits a dvb function for zsh and for bash, and says not to edit it" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  for sh in zsh bash; do
    echo "under $sh"
    run devbin_run "$proj" shell-init "$sh"
    assert_success
    assert_output_contains "dvb() {"
    assert_output_contains "do not edit"
    assert_output_contains "shell-init $sh\`"
  done
}

# AT-3.1
@test "one source renders both bodies: bash's and zsh's differ in the line naming the shell alone" {
  # Two bodies would drift, as the three copies of the snippet this command
  # replaced did within an hour, so the shells share every line of the function.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  emit "$proj" zsh
  emit "$proj" bash
  run diff "$DEVBIN_TEST_TMPDIR/dvb.zsh" "$DEVBIN_TEST_TMPDIR/dvb.bash"
  assert_exit_code 1
  [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 2 ] || fail "the bodies differ in more than one line:\n$output"
  assert_output_contains "< # Emitted by \`bin/devbin shell-init zsh\`"
  assert_output_contains "> # Emitted by \`bin/devbin shell-init bash\`"
}

# AT-3.1
@test "the bash body parses under bash and the zsh body under zsh" {
  # A body that does not parse fails the eval in every new shell, silently
  # after the first error line, so each is parsed by the shell it is for.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    run "$sh" -n "$DEVBIN_TEST_TMPDIR/dvb.$sh"
    assert_success
  done
}

@test "shell-init runs from a FOREIGN cwd, because a shell rc is one" {
  # It is exempt from the dispatcher's wrong-tree guard by definition: it writes
  # nothing, and reads only its own project's install.prefix. If this ever
  # reds, the emitted line in someone's .zshrc stops working with no other
  # symptom.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  cd "$DEVBIN_TEST_TMPDIR"
  run "$proj/bin/devbin" shell-init zsh
  assert_success
  assert_output_contains "dvb() {"
}

# AT-3.1
@test "a NON-EXECUTABLE bin/devbin STOPS the walk -- it does not run the parent's" {
  # THE SERIOUS DEFECT. The body tested -x alone, so a launcher that existed and
  # was not executable was stepped over and the walk continued INTO THE PARENT,
  # running a DIFFERENT PROJECT'S launcher and returning 0. Measured against the
  # README body: "OUTER launcher ran", rc 0.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    mklauncher "$DEVBIN_TEST_TMPDIR/outer" OUTER 755
    mklauncher "$DEVBIN_TEST_TMPDIR/outer/inner" INNER 644

    run in_shell "$sh" "cd '$DEVBIN_TEST_TMPDIR/outer/inner'; dvb"
    assert_exit_code 126
    assert_output_contains "not executable"
    refute_output_contains "OUTER launcher ran"
  done
}

# AT-3.1
@test "the same fixture RUNS once the bit is set -- the refusal's negative control" {
  # Without this the arm above passes for a body that refuses everything.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    mklauncher "$DEVBIN_TEST_TMPDIR/outer" OUTER 755
    mklauncher "$DEVBIN_TEST_TMPDIR/outer/inner" INNER 755

    run in_shell "$sh" "cd '$DEVBIN_TEST_TMPDIR/outer/inner'; dvb"
    assert_success
    assert_output_contains "INNER launcher ran"
  done
}

# AT-3.1
@test "the not-found listing prints ONE CANDIDATE PER LINE" {
  # `${^tried}` collapsed them onto one line. The control that missed it is the
  # lesson: at ONE element both forms are byte-identical, so a fixture only one
  # level deep cannot see the difference. This one is deeper on purpose.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh rel=nowhere/a/b
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    deep="$DEVBIN_TEST_TMPDIR/$rel"
    mkdir -p "$deep"

    # `run -127` rather than a bare `run` plus `assert_exit_code 127`: the 127 is
    # the CONDITION UNDER TEST -- `dvb` resolving nowhere -- not a broken command
    # path in the test itself, which is what bats assumes and warns BW01 about.
    # Pinning it at the call site says so, and bats then fails the test itself on
    # any other code. The asymmetry with `buildfmt.bats`'s `run !` is deliberate
    # and reasoned there: pin the number when the test claims the number, use
    # `run !` when it claims only non-zero.
    # DEVBIN_INSTALL_PREFIX POINTED AT NOTHING, and that is isolation rather than
    # convenience. `dvb` now falls back to the machine install, so without this the
    # arm reaches whatever is really installed on the developer's box and asserts
    # against it -- the suite would pass or fail on machine state, which is the
    # one thing a test must never read.
    run -127 in_shell "$sh" "cd '$deep'; DEVBIN_INSTALL_PREFIX='$DEVBIN_TEST_TMPDIR/no-such-install' dvb"
    # A candidate for each directory made below the tmpdir, each on its own line.
    n="$(printf '%s\n' "$output" | grep -c '/bin/devbin$')"
    [ "$n" -ge "$(tr '/' '\n' <<<"$rel" | grep -c .)" ] || fail "expected one candidate per line, got $n line(s):\n$output"
  done
}

# AT-3.1
@test "from / the not-found listing names nowhere it did not look, with no blank candidate line" {
  # At / the walk never runs, so there is no candidate to list, and an empty
  # list printed as one would read as a blank path that was tried.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    run -127 in_shell "$sh" "cd /; unset DEVBIN_SOURCE; DEVBIN_INSTALL_PREFIX='$DEVBIN_TEST_TMPDIR/no-such-install' dvb"
    assert_output_contains "no bin/devbin found"
    ! grep -q '^[[:space:]]*$' <<<"$output" || fail "a blank candidate line was printed:
$output"
  done
}

# ---------------------------------------------------------------------------
# DEVBIN_SOURCE -- the bootstrap fallback
#
# The walker locates devbin THROUGH a project that already has one, so it can
# never install into a project that does not. Bootstrapping a new project hit
# this: the function returned 127 with a candidate list, which is a
# correct report of the wrong thing.
#
# The fallback does NOT reimplement the dispatcher's exemption list, and that
# is the design rather than an omission. It hands whatever was typed to the
# fallback devbin and lets the cwd guard decide: `install` and `shell-init`
# are exempt and run, everything else is refused with exit 4 naming the tree.
# A second copy of that list here would be a Highlander breach that drifts the
# first time an exemption changes.
# ---------------------------------------------------------------------------

# AT-3.1
@test "DEVBIN_SOURCE naming a PROJECT ROOT is used when the walk finds nothing" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    src="$DEVBIN_TEST_TMPDIR/src"
    mklauncher "$src" FALLBACK 755
    deep="$DEVBIN_TEST_TMPDIR/nowhere/a/b"
    mkdir -p "$deep"

    run in_shell "$sh" "cd '$deep'; DEVBIN_SOURCE='$src' dvb"
    assert_success
    assert_output_contains "FALLBACK launcher ran"
  done
}

# AT-3.1
@test "DEVBIN_SOURCE naming the EXECUTABLE directly is used too" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    src="$DEVBIN_TEST_TMPDIR/src"
    mklauncher "$src" FALLBACK 755
    deep="$DEVBIN_TEST_TMPDIR/nowhere/a/b"
    mkdir -p "$deep"

    # Both forms, because a reader will reach for whichever matches how they
    # think about it, and a variable that accepts one silently is a trap.
    run in_shell "$sh" "cd '$deep'; DEVBIN_SOURCE='$src/bin/devbin' dvb"
    assert_success
    assert_output_contains "FALLBACK launcher ran"
  done
}

# AT-3.1
@test "a DEVBIN_SOURCE that resolves to nothing FAILS BY NAME, not into the walk's message" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    deep="$DEVBIN_TEST_TMPDIR/nowhere/a/b"
    mkdir -p "$deep"

    run -127 in_shell "$sh" "cd '$deep'; DEVBIN_SOURCE='$DEVBIN_TEST_TMPDIR/absent' dvb"
    # A misconfiguration must not be reported as an absence. Falling through to
    # "no bin/devbin found ... Looked in:" would answer a question the caller
    # did not ask and hide the one they got wrong.
    assert_output_contains "DEVBIN_SOURCE"
    refute_output_contains "Looked in:"
  done
}

# AT-3.1
@test "a DEVBIN_SOURCE that exists but is not executable returns 126, as the walk does" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    src="$DEVBIN_TEST_TMPDIR/src"
    mklauncher "$src" FALLBACK 644
    deep="$DEVBIN_TEST_TMPDIR/nowhere/a/b"
    mkdir -p "$deep"

    # 126 rather than 127: the same distinction the walk already draws, because
    # "you named it and I cannot run it" is a different fix from "it is absent".
    run -126 in_shell "$sh" "cd '$deep'; DEVBIN_SOURCE='$src' dvb"
    assert_output_contains "not executable"
  done
}

# AT-3.1
@test "with DEVBIN_SOURCE UNSET the not-found path is exactly what it was" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  local sh rel=nowhere/a/b
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    deep="$DEVBIN_TEST_TMPDIR/$rel"
    mkdir -p "$deep"

    # The negative control for the whole feature: adding a fallback must not
    # change the answer for everyone who never sets the variable.
    run -127 in_shell "$sh" "cd '$deep'; unset DEVBIN_SOURCE; DEVBIN_INSTALL_PREFIX='$DEVBIN_TEST_TMPDIR/no-such-install' dvb"
    assert_output_contains "no bin/devbin found"
    n="$(printf '%s\n' "$output" | grep -c '/bin/devbin$')"
    [ "$n" -ge "$(tr '/' '\n' <<<"$rel" | grep -c .)" ] || fail "expected the candidate list intact, got $n line(s):\n$output"
  done
}

@test "an unknown shell is REFUSED by name rather than given a zsh body" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  run devbin_run "$proj" shell-init fish
  assert_failure
  assert_output_contains "no body for 'fish'"
  assert_output_contains "Shells with one: zsh, bash"
  refute_output_contains "dvb() {"
}

@test "--autoload is zsh's alone: shell-init bash --autoload is refused, and so is any bash option" {
  # bash has no autoload, so a body without its wrapper would define nothing
  # there; it is refused by name rather than emitted.
  run devbin_run "$DEVBIN_HOME" shell-init bash --autoload
  assert_failure
  assert_output_contains "--autoload is zsh's"
  refute_output_contains "dvb"
  run devbin_run "$DEVBIN_HOME" shell-init bash --nosuch
  assert_failure
  assert_output_contains "unknown option"
}

@test "bare shell-init is a usage error: exit 1, usage on stderr, NOTHING on stdout (0119)" {
  # 1, not 2: 2 is the dispatcher's answer for a command that is unknown or
  # inactive, and shell-init is neither. Nothing on stdout, because a shell rc
  # evals stdout and the usage carries runnable examples.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  run bash -c "cd '$proj' && bin/devbin shell-init 2>/dev/null"
  assert_exit_code 1
  [ -z "$output" ] || fail "bare shell-init wrote to stdout, which a shell rc evals: $output"
  run bash -c "cd '$proj' && bin/devbin shell-init 2>&1 1>/dev/null"
  assert_exit_code 1
  assert_output_contains "usage:"
}

@test "shell-init -h is a request, not an error: usage on stdout, exit 0 -- the control for the arm above" {
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  run bash -c "cd '$proj' && bin/devbin shell-init -h 2>/dev/null"
  assert_success
  assert_output_contains "usage:"
}

@test "the emitted function falls back to the MACHINE INSTALL, with the prefix resolved" {
  # `dvb` outside every project used to be a flat error, which stopped being the
  # right answer the moment a machine install existed: it can say what devbin is
  # installed and it can seed a new project. Reported from $HOME, where all
  # four spellings failed.
  run devbin_run "$DEVBIN_HOME" shell-init zsh
  assert_success
  assert_output_contains "DEVBIN_INSTALL_PREFIX"
  # THE PLACEHOLDER MUST BE GONE. It travels through a QUOTED heredoc so that
  # $PWD and $@ survive generation verbatim, and is substituted afterwards -- so
  # the failure mode is a literal @@...@@ reaching a user's shell rc.
  refute_output_contains "@@DEVBIN_INSTALL_PREFIX@@"
}

@test "an install Homebrew placed is baked into dvb by its opt link, never by the keg brew upgrade deletes, whichever keg opt leads to (0195, 0252, 0266)" {
  # The launcher resolves its own links, so run through opt it lands in the keg,
  # Cellar/devbin/<version>; baked into dvb, that path would leave every open
  # shell aimed at a keg the next brew upgrade deletes.
  # The keg's own bin/devbin is linked to libexec's launcher, as the formula
  # writes it on Linux: it is what dvb runs from the opt link (0266).
  local src opt="$HOMEBREW_PREFIX/opt/devbin/libexec" keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0" deep="$DEVBIN_TEST_TMPDIR/nowhere/x/y"
  src="$(mkdevsrc)"
  brew_keg --from "$src" 0.1.0
  mkdir -p "$deep"
  run "$opt/bin/devbin" shell-init zsh
  assert_success
  assert_output_contains "\${DEVBIN_INSTALL_PREFIX:-'$HOMEBREW_PREFIX/opt/devbin'}"
  refute_output_contains "Cellar/devbin"
  # And the dvb it bakes runs the keg from outside every project.
  "$opt/bin/devbin" shell-init bash >"$DEVBIN_TEST_TMPDIR/dvb.bash"
  run in_shell bash "cd '$deep'; DEVBIN_INSTALL_PREFIX= dvb --version"
  assert_success
  assert_output_contains "devbin "
  # And the body written out for fpath, which no new shell regenerates.
  run "$opt/bin/devbin" shell-init zsh --autoload
  assert_success
  assert_output_contains "\${DEVBIN_INSTALL_PREFIX:-'$HOMEBREW_PREFIX/opt/devbin'}"
  refute_output_contains "Cellar/devbin"
  # And with opt leading to another keg, as while brew builds the next, the keg
  # run by its own path still bakes in the opt link, where the shell's install
  # will be once the old keg is cleaned up (0252).
  brew_keg --empty 0.1.1
  run "$HOMEBREW_PREFIX/Cellar/devbin/0.1.0/libexec/bin/devbin" shell-init zsh
  assert_success
  assert_output_contains "\${DEVBIN_INSTALL_PREFIX:-'$HOMEBREW_PREFIX/opt/devbin'}"
  refute_output_contains "Cellar/devbin"
}

@test "run from Homebrew's keg, the usage's rc lines name devbin or the opt link, never the keg brew upgrade deletes (0252, 0266)" {
  # The rc lines are what a reader copies into ~/.zshrc. The launcher resolves
  # its own links, so it runs from Cellar/devbin/<version>, and an rc line
  # naming that path breaks the shell at the next brew upgrade. Each half runs
  # the keg by that path, so the name the lines carry is worked out, not echoed.
  local src opt="$HOMEBREW_PREFIX/opt/devbin/libexec" keg="$HOMEBREW_PREFIX/Cellar/devbin/0.1.0"
  src="$(mkdevsrc)"
  brew_keg --from "$src" --linked 0.1.0
  # Homebrew's bin link leads into the keg, but Homebrew's bin is not on PATH,
  # so the devbin on PATH is not this keg's, and the lines name its opt link.
  run "$keg/libexec/bin/devbin" shell-init
  assert_exit_code 1
  assert_output_contains "eval \"\$($HOMEBREW_PREFIX/opt/devbin/bin/devbin shell-init zsh)\""
  assert_output_contains "eval \"\$($HOMEBREW_PREFIX/opt/devbin/bin/devbin shell-init bash)\""
  refute_output_contains "Cellar/devbin"
  # With Homebrew's bin on PATH, its link, through the keg's own bin/devbin,
  # makes the devbin there this keg's, so the lines name devbin, as a reader
  # types it.
  run env PATH="$HOMEBREW_PREFIX/bin:$PATH" "$keg/libexec/bin/devbin" shell-init
  assert_exit_code 1
  assert_output_contains 'eval "$(devbin shell-init zsh)"'
  assert_output_contains 'eval "$(devbin shell-init bash)"'
  refute_output_contains "Cellar/devbin"
  # And where the formula writes the keg's bin/devbin as a script of its own
  # (write_env_script), one that runs libexec's launcher and resolves to itself,
  # Homebrew's bin link to it still makes the devbin on PATH this keg's.
  brew_keg_env_script 0.1.0
  run env PATH="$HOMEBREW_PREFIX/bin:$PATH" "$keg/libexec/bin/devbin" shell-init
  assert_exit_code 1
  assert_output_contains 'eval "$(devbin shell-init zsh)"'
  refute_output_contains "Cellar/devbin"
}

@test "a script of its own at bin/devbin beside an install that is no keg is not that install's launcher, so the rc lines name the install's own (0252)" {
  # The script spelling of a launcher is Homebrew's (write_env_script), and
  # counts only beside a keg's libexec: beside any other tree it could run
  # anything. Unchanged behaviour: the lines named this launcher before 0252.
  local src tree="$DEVBIN_TEST_TMPDIR/tree"
  src="$(mkdevsrc)"
  run devbin_run "$src" install --prefix "$tree/libexec"
  assert_success
  mkdir -p "$tree/bin"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$tree/libexec/bin/devbin" >"$tree/bin/devbin"
  chmod 0755 "$tree/bin/devbin"
  run env PATH="$tree/bin:$PATH" "$tree/libexec/bin/devbin" shell-init
  assert_exit_code 1
  assert_output_contains "eval \"\$($tree/libexec/bin/devbin shell-init zsh)\""
  refute_output_contains 'eval "$(devbin shell-init zsh)"'
}

@test "generation does not expand the runtime variables the function needs" {
  # THE TRAP THIS ARM HOLDS DOWN is the one lib/cmd/infra fell into:
  # unquoting a heredoc to interpolate ONE value silently expands every
  # other variable in it. Here that would emit a function whose $PWD was the
  # generating process's cwd and whose "$@" was empty -- a dvb that always ran
  # devbin against one frozen directory, with no error anywhere.
  local sh
  for sh in zsh bash; do
    echo "under $sh"
    run devbin_run "$DEVBIN_HOME" shell-init "$sh"
    assert_success
    assert_output_contains 'local d=$PWD'
    assert_output_contains '"$@"'
  done
}

# AT-3.1
@test "the machine-install fallback runs ONLY when the walk and DEVBIN_SOURCE both miss" {
  # Ordering is the whole safety property: a project's own launcher and an
  # explicit DEVBIN_SOURCE must both outrank the install, or the fallback would
  # silently shadow the thing the caller is standing in.
  proj="$DEVBIN_TEST_TMPDIR/proj"
  mkdir -p "$proj"
  install_devbin "$proj"
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    fake="$DEVBIN_TEST_TMPDIR/fakeprefix"
    mkdir -p "$fake/bin"
    printf '#!/usr/bin/env bash\nprintf "FROM-THE-INSTALL\\n"\n' > "$fake/bin/devbin"
    chmod +x "$fake/bin/devbin"

    # Inside the project: its own launcher wins.
    run in_shell "$sh" "cd '$proj'; DEVBIN_INSTALL_PREFIX='$fake' dvb --version"
    assert_success
    refute_output_contains "FROM-THE-INSTALL"

    # Outside every project: the install answers.
    deep="$DEVBIN_TEST_TMPDIR/nowhere/x/y"
    mkdir -p "$deep"
    run in_shell "$sh" "cd '$deep'; DEVBIN_INSTALL_PREFIX='$fake' dvb --version"
    assert_success
    assert_output_contains "FROM-THE-INSTALL"
  done
}

@test "--autoload emits a BODY, not a definition, for zsh's fpath" {
  # THE DELIVERY GAP THIS CLOSES, and it is the reason this command exists at
  # all. The README records a hand-pasted snippet diverging within the
  # hour, and says making it a command fixed that. It did not fix it for the
  # person who had already pasted it: their copy is an autoload BODY in a
  # zsh fpath directory, and the eval form cannot be pasted there -- it would
  # define a function inside a function. So every improvement made here since
  # was undeliverable to that setup, silently.
  run devbin_run "$DEVBIN_HOME" shell-init zsh --autoload
  assert_success
  refute_output_contains "dvb() {"
  assert_output_contains 'local d=$PWD'
  assert_output_contains "DEVBIN_INSTALL_PREFIX"
  refute_output_contains "@@DEVBIN_INSTALL_PREFIX@@"
}

@test "the autoload body actually RUNS under zsh autoload" {
  # Asserting on the TEXT would pass for a body that is subtly unloadable. The
  # only assertion worth making is that zsh can autoload it and it works.
  require_command zsh
  run devbin_run "$DEVBIN_HOME" shell-init zsh --autoload
  assert_success
  mkdir -p "$DEVBIN_TEST_TMPDIR/fp"
  printf '%s\n' "$output" > "$DEVBIN_TEST_TMPDIR/fp/dvb"
  deep="$DEVBIN_TEST_TMPDIR/nowhere/q"
  mkdir -p "$deep"
  fake="$DEVBIN_TEST_TMPDIR/fakeprefix2"
  mkdir -p "$fake/bin"
  printf '#!/usr/bin/env bash\nprintf "AUTOLOADED-OK\\n"\n' > "$fake/bin/devbin"
  chmod +x "$fake/bin/devbin"
  run zsh -f -c "fpath=('$DEVBIN_TEST_TMPDIR/fp' \$fpath); autoload -Uz dvb; cd '$deep'; DEVBIN_INSTALL_PREFIX='$fake' dvb --version"
  assert_success
  assert_output_contains "AUTOLOADED-OK"
}

@test "an unknown shell-init zsh option is refused, not silently ignored" {
  run devbin_run "$DEVBIN_HOME" shell-init zsh --nosuch
  assert_failure
  assert_output_contains "unknown option"
}

# --- the emitted body must not carry a path this project never configured ----

@test "shell-init from a CONSUMER project emits no path derived from the home directory" {
  # THE DEFECT THIS DRIVES. `install_prefix_configured` used to fall through to
  # `$HOME/Devel/opt/devbin` -- one operator's layout -- so a consumer project
  # that has never heard of a machine install emitted a `dvb` pointing at a
  # directory named after somebody else's home. Every project that vendors
  # devbin carries this file, and the wrong answer was baked into it rather than
  # configured.
  #
  # $HOME IS REDIRECTED because the assertion is about DERIVATION, not about one
  # path: with the real $HOME the emitted line would still be wrong and would
  # still look plausible.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  HOME="$DEVBIN_TEST_TMPDIR/fakehome"
  mkdir -p "$HOME"
  export HOME
  run devbin_run "$proj" shell-init zsh
  assert_success
  refute_output_contains "$HOME"
  refute_output_contains "@@DEVBIN_INSTALL_PREFIX@@"
}

@test "a project that DECLARES install.prefix gets it baked into dvb, the tilde expanded (0125)" {
  # The arm above is the other half: no declaration, no path. The reference
  # always promised this half, and it never happened until 0125 -- the handler
  # asked a config cache nothing had loaded, so every project answered empty.
  # $HOME is redirected so the expansion is seen to come from the tilde.
  HOME="$DEVBIN_TEST_TMPDIR/fakehome"
  mkdir -p "$HOME"
  export HOME
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
install:
  prefix: ~/opt/devbin
YAML
  )"
  run devbin_run "$proj" shell-init zsh
  assert_success
  assert_output_contains "local prefix=\${DEVBIN_INSTALL_PREFIX:-'$HOME/opt/devbin'}"
}

# --- an install prefix is DATA in the body, whatever it holds (0200) ----------
#
# The prefix used to reach the body through sed's replacement and then sit
# unquoted in `${DEVBIN_INSTALL_PREFIX:-<path>}`, so an `&` came out as sed's
# matched text at rc 0, a `|` or `\` broke the sed, and a `$`, `}` or `'` was
# code to every shell that evals the output. Each arm declares a prefix holding
# one of those characters, puts a launcher at exactly that path, and asks the
# emitted dvb, in each shell, to run it: a body that bent the path in any way
# finds no launcher there.

# prefix_holds <char> -- the arm: install.prefix `<tmp>/pfx/a<char>b`, declared
# in a project's config, is the launcher dvb runs from outside every project.
# The value is single-quoted in the YAML, where a backslash is literal, and
# double-quoted only to carry a `'`: lib/config reads either quote as a bare
# delimiter, but a reader that learned YAML's escapes would read `"\b"` as a
# backspace and fail the arm for a reason that is not shell-init's.
prefix_holds() {
  local pfx="$DEVBIN_TEST_TMPDIR/pfx/a${1}b" proj sh deep q="'"
  [ "$1" != "'" ] || q='"'
  mkdir -p "$pfx/bin"
  printf '#!/bin/sh\necho "the prefix launcher ran"\n' >"$pfx/bin/devbin"
  chmod 755 "$pfx/bin/devbin"
  proj="$(mkproj demo <<<"project:
  name: demo
install:
  prefix: $q$pfx$q")"
  deep="$DEVBIN_TEST_TMPDIR/nowhere/deeper"
  mkdir -p "$deep"
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    run in_shell "$sh" "cd '$deep'; unset DEVBIN_SOURCE DEVBIN_INSTALL_PREFIX; dvb"
    assert_success
    assert_output_contains "the prefix launcher ran"
  done
}

@test "an install prefix holding & is carried exactly, in zsh and bash (0200)" { prefix_holds '&'; }
@test "an install prefix holding | is carried exactly, in zsh and bash (0200)" { prefix_holds '|'; }
@test "an install prefix holding a backslash is carried exactly, in zsh and bash (0200)" { prefix_holds '\'; }
@test "an install prefix holding a space is carried exactly, in zsh and bash, as it was before 0200" { prefix_holds ' '; }
@test "an install prefix holding a dollar sign is carried exactly, in zsh and bash (0200)" {
  prefix_holds '$'
}
@test "an install prefix holding } is carried exactly, in zsh and bash (0200)" { prefix_holds '}'; }
@test "an install prefix holding a single quote is carried exactly, in zsh and bash (0200)" { prefix_holds "'"; }

@test "the --autoload body carries such a prefix exactly too, from the same fill (0200)" {
  # One fill for every body: the autoload form is the eval form unwrapped, so a
  # prefix bent on the way into one would be bent in both.
  require_command zsh
  local pfx="$DEVBIN_TEST_TMPDIR/pfx/a'&\$}b" proj
  mkdir -p "$pfx/bin"
  printf '#!/bin/sh\necho "the prefix launcher ran"\n' >"$pfx/bin/devbin"
  chmod 755 "$pfx/bin/devbin"
  proj="$(mkproj demo <<<"project:
  name: demo
install:
  prefix: \"$pfx\"")"
  mkdir -p "$DEVBIN_TEST_TMPDIR/fp" "$DEVBIN_TEST_TMPDIR/nowhere/q"
  devbin_run "$proj" shell-init zsh --autoload >"$DEVBIN_TEST_TMPDIR/fp/dvb"
  run zsh -f -c "setopt nounset; fpath=('$DEVBIN_TEST_TMPDIR/fp' \$fpath); autoload -Uz dvb; cd '$DEVBIN_TEST_TMPDIR/nowhere/q'; unset DEVBIN_SOURCE DEVBIN_INSTALL_PREFIX; dvb"
  assert_success
  assert_output_contains "the prefix launcher ran"
}

@test "a config shell-init cannot read still emits dvb, with no fallback, and says why on stderr (0125)" {
  # A shell rc runs this, and a shell that will not start is a worse answer
  # than a dvb without its fallback; silence would read as a project that
  # declared none. The launcher refuses an unreadable config before dispatch,
  # so the handler is run directly: the state guarded is a config that stops
  # being readable between the launcher's read and the handler's.
  if [ "$(id -u)" = "0" ]; then
    skip "running as root -- chmod cannot make a file unreadable, so the state cannot be built"
  fi
  proj="$(mkproj demo <<'YAML'
project:
  name: demo
install:
  prefix: /opt/elsewhere
YAML
  )"
  chmod 000 "$proj/bin/.devbin/config.yaml"
  run bash -c "DEVBIN_LIB='$DEVBIN_LIB_DIR' PROJECT_ROOT='$proj' DEVBIN_DIR='$proj/bin/.devbin' DEVBIN_INVOKE=bin/devbin bash '$DEVBIN_LIB_DIR/cmd/shell-init' zsh 2>'$DEVBIN_TEST_TMPDIR/err'"
  chmod 644 "$proj/bin/.devbin/config.yaml"
  assert_success
  assert_output_contains "dvb() {"
  assert_output_contains "local prefix=\${DEVBIN_INSTALL_PREFIX:-''}"
  grep -q 'could not be read' "$DEVBIN_TEST_TMPDIR/err" || fail "nothing said on stderr: $(cat "$DEVBIN_TEST_TMPDIR/err")"
}

# AT-3.1
@test "with NO prefix configured the fallback is SKIPPED, not aimed at /bin/devbin" {
  # `[[ -x $prefix/bin/devbin ]]` with an empty prefix tests `/bin/devbin` --
  # a real path, on the system PATH, that the emitted function would then RUN.
  # Removing the default is what makes an empty prefix reachable, so the guard
  # has to arrive with it.
  proj="$(create_test_project demo)"
  install_devbin "$proj"
  HOME="$DEVBIN_TEST_TMPDIR/fakehome"
  mkdir -p "$HOME"
  export HOME
  local sh
  dvb_shells
  for sh in "${DVB_SHELLS[@]}"; do
    echo "under $sh"
    emit "$proj" "$sh"
    deep="$DEVBIN_TEST_TMPDIR/nowhere/deeper"
    mkdir -p "$deep"
    run -127 in_shell "$sh" "cd '$deep'; unset DEVBIN_SOURCE DEVBIN_INSTALL_PREFIX; dvb"
    # A LOCATION IT DOES NOT HAVE MUST NOT BE NAMED. The old message read
    # "no machine install at " with a blank where a path belongs, which reads as
    # a path that failed rather than as a prefix that was never configured.
    refute_output_contains "no machine install at /bin"
    refute_output_contains "install at ."
    assert_output_contains "no machine install prefix is configured"
    # A user installs from brew: the remedy names it, never a publish from a
    # dev checkout, which is the maintainer's (0210).
    assert_output_contains "install devbin with Homebrew"
    refute_output_contains "inside devbin"
  done
}
