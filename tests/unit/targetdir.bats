#!/usr/bin/env bats
#
# check targetdir -- the cargo target dir is the shared one.
#
# Every arm asserts CONTENT, never `$?` alone. The home-config arm matters
# most: it is the one that must REPORT without failing, and a gate that
# failed there would go red in a checkout whose own contents are correct.

load ../lib/test_helper

setup() { devbin_setup; }
teardown() { devbin_teardown; }

rustproj() {
  local proj
  proj="$(mkproj rustdemo <<'EOF'
project:
  name: rustdemo
  alias: rd
  languages:
    - rust
EOF
)"
  echo "$proj"
}

@test "RED ARM: a forked CARGO_TARGET_DIR fails, and names the path" {
  local proj; proj="$(rustproj)"

  CARGO_TARGET_DIR=/tmp/my-private-target run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "/tmp/my-private-target"
  assert_output_contains "per-session fork"
}

# THE MESSAGE MUST NAME THE CAUSE, NOT JUST THE RULE. A developer forks because
# a silent lock wait is indistinguishable from a hang; a gate that only says
# "don't" is one they switch off and fork anyway.
@test "the breach explains WHY forking happens, not only that it is forbidden" {
  local proj; proj="$(rustproj)"

  CARGO_TARGET_DIR=/tmp/my-private-target run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "build lock"
  assert_output_contains "looks identical to a hang"
}

@test "a CARGO_TARGET_DIR set but empty fails, in the words fullcycle refuses it in (0148)" {
  # cargo refuses an empty value, and fullcycle refuses it before its clean; a
  # check that read it as unset passed it, green, and named the shared tree.
  local proj; proj="$(rustproj)"
  # A Cargo.toml at the root makes <root>/target the shared tree clean removes (0167).
  : >"$proj/Cargo.toml"

  CARGO_TARGET_DIR= run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "CARGO_TARGET_DIR='' is empty, and cargo refuses an empty target directory -- unset it, or set it to the shared tree at $proj/target."
  refute_output_contains "no target-dir override"
}

@test "CARGO_TARGET_DIR pointing AT the shared tree is not a fork" {
  local proj; proj="$(rustproj)"
  # A Cargo.toml at the root makes <root>/target the shared tree clean removes (0167).
  : >"$proj/Cargo.toml"

  CARGO_TARGET_DIR="$proj/target" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "points at the shared tree"
}

@test "a project .cargo/config.toml fork fails and is distinguished from the env one" {
  # cargo's answer is the verdict (issue 0150), so the project has a crate for
  # cargo to be asked about.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "/tmp/project-wide-fork"\n' >"$proj/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "/tmp/project-wide-fork"
  assert_output_contains "every session in this project"
}

# REPORTED, NOT FAILED. A machine-level fork is neither this project's fault nor
# something this project can fix.
@test "a HOME cargo config fork is reported and does NOT fail the gate" {
  need_cargo
  local proj home; proj="$(rustproj)"
  real_crate "$proj"
  home="$BATS_TEST_TMPDIR/fakecargo"
  mkdir -p "$home"
  printf '[build]\ntarget-dir = "/tmp/machine-wide-fork"\n' >"$home/config.toml"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "/tmp/machine-wide-fork"
  # Asked of cargo for the crate here, not only read from the file: the
  # no-crate line alone held this arm green with the gate's CARGO_HOME leg
  # removed.
  assert_output_contains "and cargo builds . into "
  assert_output_contains "EVERY rust project"
  assert_output_contains "not failed here"
}

@test "with nothing set the gate says WHAT IT LOOKED AT, so silence is not mistaken for absence" {
  local proj home; proj="$(rustproj)"
  # A Cargo.toml at the root makes <root>/target the shared tree clean removes (0167).
  : >"$proj/Cargo.toml"
  home="$BATS_TEST_TMPDIR/emptycargo"
  mkdir -p "$home"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "no target-dir override"
  assert_output_contains "shared tree"
}

@test "a project config fork with no crate to build with it is reported, not failed (0150)" {
  # cargo's answer is the verdict, and with no crate there is nothing to ask
  # and nothing built into the tree it names: a downgrade from fail, held here.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "/tmp/project-wide-fork"\n' >"$proj/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "config   .cargo/config.toml sets build.target-dir = /tmp/project-wide-fork, and no crate here builds with it -- not failed"
}

@test "a CARGO_BUILD_TARGET_DIR fork fails as CARGO_TARGET_DIR's does, and an empty one is refused in the same words (0150)" {
  local proj; proj="$(rustproj)"

  CARGO_BUILD_TARGET_DIR=/tmp/my-private-target run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "CARGO_BUILD_TARGET_DIR=/tmp/my-private-target -- a per-session fork of the build cache"

  CARGO_BUILD_TARGET_DIR= run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "CARGO_BUILD_TARGET_DIR='' is empty, and cargo refuses an empty target directory"
}

@test "a fork from a config nearer the crate, which neither the project's config nor the machine's accounts for, fails with its cause unknown (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  # A crate at the root makes <root>/target the shared tree clean removes (0167).
  real_crate "$proj"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo"
  printf '[build]\ntarget-dir = "out"\n' >"$proj/native/cli/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "cargo builds native/cli into "
  assert_output_contains "/native/cli/out, not its own target or the shared tree at $proj/target"
  assert_output_contains "no config this check can read accounts for it -- its cause is not named here."
}

@test "a crate with no carrier builds into its own target, which is no fork: the control (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"

  run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "no target-dir override"
}

@test "a project config fork fails though CARGO_TARGET_DIR points at the shared tree: the config is judged without the environment (0150)" {
  # With the variable set, cargo was not asked, and a fork hitting every other
  # session passed as "no crate here builds with it".
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "/tmp/project-wide-fork"\n' >"$proj/.cargo/config.toml"

  CARGO_TARGET_DIR="$proj/target" run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "every session in this project"
  refute_output_contains "no crate here builds with it"
}

@test "a machine config fork in a spelling other than target-dir = \"...\" is still reported, not failed (0150)" {
  # A dotted key, a trailing comment and the legacy file name each failed as
  # a fork from "a config nearer the crate": the machine's fork is asked of
  # cargo now, not read by sed.
  need_cargo
  local proj home; proj="$(rustproj)"
  real_crate "$proj"
  home="$BATS_TEST_TMPDIR/fakecargo2/"
  mkdir -p "$home"
  printf 'build.target-dir = "/tmp/mw-dotted" # a comment\n' >"$home/config"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "and cargo builds . into "
  assert_output_contains "/tmp/mw-dotted"
  assert_output_contains "not failed here"
  # The legacy file alone is the one cargo reads, and the one named (0164).
  assert_output_contains "machine  ${home%/}/config moves the build tree"
}

@test "a nested crate's config pinning the shared tree through .. passes before the tree exists (0150)" {
  # cargo answers native/cli/../../target, which read as a fork on a fresh
  # clone until target/ existed.
  need_cargo
  local proj; proj="$(rustproj)"
  # A crate at the root makes <root>/target the shared tree clean removes (0167).
  real_crate "$proj"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo"
  printf '[build]\ntarget-dir = "../../target"\n' >"$proj/native/cli/.cargo/config.toml"
  [ ! -e "$proj/target" ] || rm -rf "$proj/target"

  run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "cargo    native/cli builds into the shared tree"
}

@test "a project config's relative target-dir is placed from the project root and named as the fork's cause (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "forked"\n' >"$proj/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains ".cargo/config.toml sets build.target-dir = forked, and cargo builds native/cli into "
  assert_output_contains "every session in this project"
}

@test "a config that includes another config naming target-dir is asked of cargo, and its fork seen (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo"
  printf 'include = ["other.toml"]\n' >"$proj/native/cli/.cargo/config.toml"
  printf '[build]\ntarget-dir = "/tmp/inc-fork"\n' >"$proj/native/cli/.cargo/other.toml"

  run devbin_run "$proj" check targetdir

  if [[ "$output" == *"cargo cannot say where"* ]]; then
    skip "this cargo does not read include: NOT checked"
  fi
  assert_failure
  assert_output_contains "cargo builds native/cli into "
  assert_output_contains "/tmp/inc-fork"
}

@test "a CARGO_BUILD_TARGET_DIR that CARGO_TARGET_DIR shadows is no fork (0150)" {
  local proj; proj="$(rustproj)"
  # A Cargo.toml at the root makes <root>/target the shared tree clean removes (0167).
  : >"$proj/Cargo.toml"

  CARGO_TARGET_DIR="$proj/target" CARGO_BUILD_TARGET_DIR=/tmp/fk run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "CARGO_BUILD_TARGET_DIR is set, and CARGO_TARGET_DIR, which cargo puts first, decides the tree"
}

@test "a project's own fork is not taken for the machine's when TMPDIR sits inside the project (0150)" {
  # The probe for the machine's config hears every config above it, so with
  # TMPDIR inside the project the project's fork, in a spelling sed cannot
  # read, was reported as the machine's and not failed.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$proj/.cargo" "$proj/.tmp"
  printf 'build.target-dir = "/tmp/dotfork"\n' >"$proj/.cargo/config.toml"

  TMPDIR="$proj/.tmp" run devbin_run "$proj" check targetdir

  assert_failure
  refute_output_contains "not failed here"
  # Its cause unnamed, the clouded probe is said rather than left silent (0164).
  assert_output_contains "Where the machine's config sends a build could not be measured: a cargo config at or above $proj/.tmp may apply too."
}

@test "a directory the walk for crates cannot read is reported, not failed, with no cargo config anywhere (0150)" {
  # The docker-volume shape: a directory another uid owns. No carrier is in
  # play, so failing would be a refusal this check never made before 0150.
  local proj readable=0; proj="$(rustproj)"
  mkdir -p "$proj/data/mysql"
  chmod 000 "$proj/data/mysql"
  [ ! -r "$proj/data/mysql" ] || readable=1
  if [ "$readable" = 1 ]; then chmod 755 "$proj/data/mysql"; skip "running with permissions that read a mode-000 directory: NOT checked"; fi

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "could not read the whole project for its crates (the error above names it); no cargo config naming target-dir or include is in play here -- not failed"
  refute_output_contains "where every crate builds could not be known"
}

@test "the same unreadable directory is reported, not failed, when only the machine's cargo config names target-dir (0150, 0164)" {
  # This failed while the same fork, once a crate was answered, was reported,
  # rc 0: the machine's config was in play over a hole, and only over a hole.
  # It sends a crate beneath the hole where it sends every crate on this
  # machine, so it is never in play, and a fork it makes is reported as one,
  # as cargo reads it: the probe needs cargo, though nothing here is a crate.
  need_cargo
  local proj home fork; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo3"
  fork="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/machine-wide-fork"
  mkdir -p "$proj/data/mysql" "$home"
  printf '[build]\ntarget-dir = "%s"\n' "$fork" >"$home/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "machine  $home/config.toml moves the build tree to $fork, and no crate the walk reached builds with it"
  assert_output_contains "Not this project to fix, and not failed here."
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
  refute_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "a machine config that only includes, beside an unreadable directory with no crate answered, is reported as moving nothing, not failed (0164)" {
  # The include moves nothing, and was in play only because no crate was
  # answered to show it. Cargo, asked, says it moves nothing, and that is
  # what is reported (the title promised a report no line gave).
  need_cargo
  local proj home; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo6"
  mkdir -p "$proj/data/mysql" "$home"
  printf 'include = []\n' >"$home/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  if [[ "$output" == *"cargo cannot say where"* ]]; then skip "this cargo does not read include: NOT checked"; fi
  assert_success
  assert_output_contains "machine  $home/config.toml names target-dir or include, and moves no build tree -- not failed"
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
  refute_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

# need_cargo_include -- skip, saying so, where this cargo cannot read a config
# naming `include`, asked once of a throwaway crate rather than read from an
# arm's output, whose own lines name include too.
need_cargo_include() {
  need_cargo
  local d="$BATS_TEST_TMPDIR/include-probe"
  mkdir -p "$d/src" "$d/.cargo" "$d/home"
  printf '[package]\nname = "probe"\nversion = "0.0.0"\nedition = "2021"\n' >"$d/Cargo.toml"
  : >"$d/src/main.rs"
  printf 'include = []\n' >"$d/.cargo/config.toml"
  (cd "$d" && CARGO_HOME="$d/home" cargo metadata --offline --no-deps --format-version 1 >/dev/null 2>&1) ||
    skip "cargo could not read a config naming include: NOT checked"
}

# hole_arm <dir> -- mode 000, or skip where this runner reads it anyway.
hole_arm() {
  chmod 000 "$1"
  if [ -r "$1" ]; then chmod 755 "$1"; skip "running with permissions that read a mode-000 directory: NOT checked"; fi
}

# acl_hole <dir> -- an ACL denying the running user a listing its mode bits
# allow, a hole find_walk cannot record, or skip where this runner sets none.
# acl_clear <dir> lifts it.
acl_hole() {
  /bin/chmod +a "user:$(id -un) deny list" "$1" 2>/dev/null || skip "no chmod +a on this runner: NOT checked"
  if ls "$1" >/dev/null 2>&1; then acl_clear "$1"; skip "running with permissions that list past an ACL: NOT checked"; fi
}
acl_clear() {
  /bin/chmod -a "user:$(id -un) deny list" "$1"
}

@test "a machine-wide fork is reported, not failed, though TMPDIR sits beneath the directory holding CARGO_HOME (0150)" {
  # The probe's walk up met ~/.cargo/config.toml, the machine's own config,
  # and gave up, so the fork failed.
  need_cargo
  local proj fake; proj="$(rustproj)"
  real_crate "$proj"
  fake="$BATS_TEST_TMPDIR/fakehome"
  mkdir -p "$fake/.cargo" "$fake/tmp"
  printf '[build]\ntarget-dir = "/tmp/machine-wide-fork"\n' >"$fake/.cargo/config.toml"

  CARGO_HOME="$fake/.cargo" TMPDIR="$fake/tmp" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "not failed here"
}

@test "a config below the project root whose only crate lies beneath an unreadable directory fails the check (0150)" {
  # None of the in-play tests saw it, and the check said no config was
  # anywhere it read.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/.cargo" "$proj/native/locked/cli"
  printf '[build]\ntarget-dir = "/tmp/native-fork"\n' >"$proj/native/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "a crate config pinning the shared tree, beside an unrelated unreadable directory, is reported, not failed (0150)" {
  # A config every crate beneath it accounts for leaves the unread part no
  # more exposed than a project with no config.
  need_cargo
  local proj; proj="$(rustproj)"
  # A crate at the root makes <root>/target the shared tree clean removes (0167).
  real_crate "$proj"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "../../target"\n' >"$proj/native/cli/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "native/cli builds into the shared tree"
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a crate config that forks, beside an unrelated unreadable directory, fails the check (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "/tmp/cli-fork"\n' >"$proj/native/cli/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "a project-root config that forks, beside an unreadable directory, fails the check (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$proj/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "/tmp/root-fork"\n' >"$proj/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "a config above the project that every crate accounts for, beside an unreadable directory, is reported, not failed (0150)" {
  # With d=/ the in-play prefix never matched under bash 5.3, so a config
  # above the project was always in play.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$DEVBIN_TEST_TMPDIR/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "%s/target"\n' "$proj" >"$DEVBIN_TEST_TMPDIR/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a machine config that moves nothing, beside an unreadable directory, is reported, not failed (0150)" {
  need_cargo
  local proj home; proj="$(rustproj)"
  real_crate "$proj"
  home="$BATS_TEST_TMPDIR/fakecargo4"
  mkdir -p "$home" "$proj/data/mysql"
  printf 'include = []\n' >"$home/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  if [[ "$output" == *"cargo cannot say where"* ]]; then skip "this cargo does not read include: NOT checked"; fi
  assert_success
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a machine fork beside an unreadable directory stays reported, not failed (0150)" {
  # The machine's config applies under the hole as it does to the crates
  # answered, so its fork stays reported, and the output does not say "not
  # failed" and then fail.
  need_cargo
  local proj home; proj="$(rustproj)"
  real_crate "$proj"
  home="$BATS_TEST_TMPDIR/fakecargo5"
  mkdir -p "$home" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "/tmp/mwf"\n' >"$home/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "not failed here"
  assert_output_contains "is in play here -- not failed"
}

@test "a project-local CARGO_HOME's git database is not taken for a crate (0150)" {
  # .cargo/git/db/<repo>/config matched '*/.cargo/*' and was asked of cargo as
  # a crate.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$proj/.cargo/git/db/foo-abc"
  printf '[core]\n\tbare = true\n' >"$proj/.cargo/git/db/foo-abc/config"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_success
  refute_output_contains "git/db"
}

@test "a config that is a link, whose only crate lies beneath an unreadable directory, is in play (0150)" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/.cargo" "$proj/native/locked/cli"
  printf '[build]\ntarget-dir = "/tmp/symfork"\n' >"$proj/forkcfg.toml"
  ln -s ../../forkcfg.toml "$proj/native/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include"
}

@test "a crate whose Cargo.toml is a link is asked of cargo, and its fork seen (0150)" {
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/real"
  mkdir -p "$proj/native/cli/.cargo"
  cp -R "$proj/real/src" "$proj/native/cli/src"
  ln -s ../../real/Cargo.toml "$proj/native/cli/Cargo.toml"
  printf '[build]\ntarget-dir = "/tmp/p9fork"\n' >"$proj/native/cli/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains "cargo builds native/cli into "
  assert_output_contains "/tmp/p9fork"
}

@test "a machine config fork with no crate here is reported with the tree it moves to, not failed (0164)" {
  # No arm held this wording, and with the whole walk dropped from the report
  # the line below it said there was no target-dir override in a config that
  # sets one, at rc 0.
  need_cargo
  local proj home fork; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo7"
  fork="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/machine-wide-fork"
  mkdir -p "$home"
  printf '[build]\ntarget-dir = "%s"\n' "$fork" >"$home/config.toml"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "machine  $home/config.toml moves the build tree to $fork, and no crate here builds with it"
  assert_output_contains "Not this project to fix, and not failed here."
  refute_output_contains "no crate the walk reached"
  refute_output_contains "no target-dir override"
}

@test "a machine config fork in a spelling sed cannot read, beside an unreadable directory with no crate answered, is still reported (0164)" {
  # The report waited on sed's reading, so a trailing comment, a dotted key
  # and an include naming target-dir were not reported at all. Cargo reads
  # each.
  need_cargo
  local proj home fork; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo8"
  fork="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)/mw-unread"
  mkdir -p "$proj/data/mysql" "$home"
  printf 'build.target-dir = "%s" # one cache\n' "$fork" >"$home/config.toml"
  hole_arm "$proj/data/mysql"
  CARGO_HOME="$home" run devbin_run "$proj" check targetdir
  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "machine  $home/config.toml moves the build tree to $fork, and no crate the walk reached builds with it"

  printf 'include = ["fork.toml"]\n' >"$home/config.toml"
  printf '[build]\ntarget-dir = "%s"\n' "$fork" >"$home/fork.toml"
  hole_arm "$proj/data/mysql"
  CARGO_HOME="$home" run devbin_run "$proj" check targetdir
  chmod 755 "$proj/data/mysql"
  if [[ "$output" == *"cargo cannot say where"* ]]; then skip "this cargo does not read include: NOT checked"; fi
  assert_success
  assert_output_contains "machine  $home/config.toml moves the build tree to $fork, and no crate the walk reached builds with it"
}

@test "a machine config fork spelled through a link is the machine's, compared as it resolves (0164)" {
  # cargo names the tree as the config spells it, and the probe's answer is
  # placed as the crate's is; only macOS's /tmp link held that placement.
  need_cargo
  local proj home base; proj="$(rustproj)"
  real_crate "$proj"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$BATS_TEST_TMPDIR/fakecargo9"
  mkdir -p "$home" "$base/real"
  ln -s "$base/real" "$base/lnk"
  printf '[build]\ntarget-dir = "%s/lnk/mwf"\n' "$base" >"$home/config.toml"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "machine  $home/config.toml moves the build tree, and cargo builds . into $base/real/mwf"
  refute_output_contains "its cause is not named here"
}

@test "with both config and config.toml in CARGO_HOME, the machine's fork is config's, the file cargo reads, and named so (0164)" {
  # cargo reads config and warns when both are there; check read config.toml
  # first, and named a file cargo ignores (measured on cargo 1.99.0).
  need_cargo
  local proj home base; proj="$(rustproj)"
  real_crate "$proj"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  home="$BATS_TEST_TMPDIR/fakecargo10"
  mkdir -p "$home"
  printf '[build]\ntarget-dir = "%s/from-bare"\n' "$base" >"$home/config"
  printf '[build]\ntarget-dir = "%s/from-toml"\n' "$base" >"$home/config.toml"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "machine  $home/config moves the build tree, and cargo builds . into $base/from-bare"
  refute_output_contains "from-toml"
  refute_output_contains "$home/config.toml"
}

@test "a crate config naming the shared tree in another case, where the disk folds case, builds into the shared tree (0164)" {
  # Trees are compared as one directory where both exist, not by text alone:
  # cargo_place keeps the case a path is written in.
  need_cargo
  local proj; proj="$(rustproj)"
  # A crate at the root makes <root>/target the shared tree clean removes (0167).
  real_crate "$proj"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/target" "$proj/native/cli/.cargo"
  [ -e "$proj/TARGET" ] || skip "this disk does not fold case: NOT checked"
  printf '[build]\ntarget-dir = "%s/TARGET"\n' "$proj" >"$proj/native/cli/.cargo/config.toml"

  run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "cargo    native/cli builds into the shared tree"
}

@test "cargo_config_file names the file cargo reads, and cargo_config_in_home and cargo_tree_cause read by it (0164)" {
  # Measured on cargo 1.99.0: config where it can be opened, else config.toml
  # where it is there at all.
  local proj d; proj="$(rustproj)"
  d="$BATS_TEST_TMPDIR/cfgdir"
  mkdir -p "$d"
  run fixture_ask "$proj" cargo_config_file "$d"
  assert_success
  [ -z "$output" ] || fail "neither file named something: $output"
  printf '[build]\ntarget-dir = "x"\n' >"$d/config.toml"
  [ "$(fixture_ask "$proj" cargo_config_file "$d")" = "$d/config.toml" ] || fail "config.toml alone"
  printf '# nothing\n' >"$d/config"
  [ "$(fixture_ask "$proj" cargo_config_file "$d")" = "$d/config" ] || fail "both: config, which cargo reads"
  [ "$(CARGO_HOME="$d" fixture_run "$proj" 'cargo_config_in_home && echo yes || echo no')" = no ] ||
    fail "CARGO_HOME's config names nothing, so config.toml beside it is no carrier"
  rm "$d/config"
  [ "$(CARGO_HOME="$d" fixture_run "$proj" 'cargo_config_in_home && echo yes || echo no')" = yes ] || fail "config.toml alone names target-dir"
  ln -s "$d/nowhere" "$d/config"
  [ "$(fixture_ask "$proj" cargo_config_file "$d")" = "$d/config.toml" ] || fail "a dangling config is passed over"
  [ "$(fixture_ask "$proj" cargo_tree_cause /t /t /t)" = project ] || fail "the project's first"
  [ "$(fixture_ask "$proj" cargo_tree_cause /t /p /t)" = machine ] || fail "the machine's"
  [ "$(fixture_ask "$proj" cargo_tree_cause /t "" /t)" = machine ] || fail "the machine's, no project tree"
  run fixture_ask "$proj" cargo_tree_cause /t /p /m
  assert_success
  [ -z "$output" ] || fail "neither: $output"
  run fixture_ask "$proj" cargo_tree_cause /t "" ""
  assert_success
  [ -z "$output" ] || fail "nothing to compare: $output"
  rm "$d/config"
  printf '# unreadable\n' >"$d/config"
  chmod 000 "$d/config"
  if [ -r "$d/config" ]; then chmod 644 "$d/config"; skip "running with permissions that read a mode-000 file: NOT checked"; fi
  [ "$(fixture_ask "$proj" cargo_config_file "$d")" = "$d/config.toml" ] || { chmod 644 "$d/config"; fail "an unreadable config is passed over"; }
  rm -f "$d/config"
  # An unreadable config.toml alone is still the file cargo reads, and fails on.
  chmod 000 "$d/config.toml"
  [ "$(fixture_ask "$proj" cargo_config_file "$d")" = "$d/config.toml" ] || { chmod 644 "$d/config.toml"; fail "an unreadable config.toml alone"; }
  chmod 644 "$d/config.toml"
}

@test "a machine config beside a config above TMPDIR, with no crate here, is reported as not measured, never as moving nothing (0164)" {
  # The probe hears every config above its scratch directory, so its answer is
  # no measure of the machine's alone: that is said, not "moves no build tree".
  #
  # IT LOOKS FOR CARGO ON PATH, AND NEVER RUNS IT (0198). cargo_probe_build_dir
  # asks `command -v cargo` first, so with none on PATH the probe says that
  # instead, and gives up at the config above TMPDIR before cargo would run.
  # So a stub stands in for cargo, first on PATH, that fails loudly if run: the
  # arm runs on a machine with no cargo, and "never runs it" is asserted, where
  # the comment here said "needs no cargo" and failed on a machine without it.
  local proj home stub; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo11"
  stub="$BATS_TEST_TMPDIR/stubcargo"
  mkdir -p "$home" "$proj/.tmp" "$proj/.cargo" "$stub"
  printf '[build]\ntarget-dir = "/tmp/mw-above"\n' >"$home/config.toml"
  printf 'include = []\n' >"$proj/.cargo/config.toml"
  printf '#!/bin/sh\necho "stub cargo was run: $*" >&2\nexit 97\n' >"$stub/cargo"
  chmod +x "$stub/cargo"

  CARGO_HOME="$home" TMPDIR="$proj/.tmp" PATH="$stub:$PATH" run devbin_run "$proj" check targetdir

  assert_success
  refute_output_contains "stub cargo was run"
  assert_output_contains "machine  $home/config.toml names target-dir or include, and where it alone sends a build could not be measured: a cargo config at or above $proj/.tmp may apply too -- not failed"
  refute_output_contains "moves no build tree"
}

@test "a machine config cargo cannot read, with no crate here, is reported as not measured, in cargo's words, never as moving nothing (0164)" {
  # The report's fourth outcome: the probe failed, and said why above it.
  need_cargo
  local proj home; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo12"
  mkdir -p "$home"
  printf '[build]\ntarget-dir = \n' >"$home/config.toml"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "cargo cannot say where"
  assert_output_contains "machine  $home/config.toml names target-dir or include, and where it sends a build could not be measured (the error above says why) -- not failed"
  refute_output_contains "moves no build tree"
}

@test "a machine config with no crate here and cargo not on PATH is reported as not measured, saying so once (0164)" {
  # The probe was asked with no crate here, and with cargo gone said so as
  # cargo's failure in a scratch directory already removed.
  need_cargo
  local proj home cargoless; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo13"
  mkdir -p "$home"
  printf '[build]\ntarget-dir = "/tmp/mw-nocargo"\n' >"$home/config.toml"
  # Cargo goes from every PATH entry that holds one, since a machine can carry
  # more than one, eg Homebrew's and then rustup's (0234).
  cargoless="$(path_without cargo)" || fail "path_without could not hide cargo, as its line above says"

  CARGO_HOME="$home" PATH="$cargoless" run devbin_run "$proj" check targetdir

  assert_success
  assert_output_contains "cargo is not on PATH, so where the machine's cargo config sends a build cannot be measured"
  assert_output_contains "machine  $home/config.toml names target-dir or include, and where it sends a build could not be measured (the error above says why) -- not failed"
  refute_output_contains "cargo cannot say where"
}

@test "with both .cargo/config and .cargo/config.toml at the project root, the fork is config's, the file cargo reads, and named so (0176)" {
  # cargo reads config and warns when both are there; this check read
  # config.toml first, so the fork config makes went unattributed, its cause
  # "not named here" (measured on cargo 1.99.0).
  need_cargo
  local proj base; proj="$(rustproj)"
  real_crate "$proj"
  base="$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "%s/toml-fork"\n' "$base" >"$proj/.cargo/config.toml"
  printf '[build]\ntarget-dir = "%s/bare-fork"\n' "$base" >"$proj/.cargo/config"

  run devbin_run "$proj" check targetdir

  assert_failure
  assert_output_contains ".cargo/config sets build.target-dir = $base/bare-fork, and cargo builds . into $base/bare-fork"
  refute_output_contains "toml-fork"
}

@test "a config.toml cargo ignores, beside a .cargo/config that names no target-dir, is no fork, and the file read is the one named (0176)" {
  # With no crate, this check reported config.toml's value, which cargo never
  # reads, and its passing line named .cargo/config.toml whatever it read.
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "/tmp/toml-fork"\n' >"$proj/.cargo/config.toml"
  printf '# nothing\n' >"$proj/.cargo/config"

  run devbin_run "$proj" check targetdir

  assert_success
  refute_output_contains "/tmp/toml-fork"
  assert_output_contains "no target-dir override in the environment, .cargo/config or"
}

@test "a config whose own target forks a workspace beneath an unreadable directory under it fails the check (0163)" {
  # cargo builds ws2, beneath a/locked, into a/target, a fork; crate a, the
  # only one the walk saw, builds there as its own target, so the config passed
  # as accounted for. What the config itself pins is asked now. Both kinds of
  # hole: one the walk can list but not search, and one it cannot read.
  need_cargo
  local proj mode; proj="$(rustproj)"
  real_crate "$proj/a"
  real_crate "$proj/a/locked/ws2"
  mkdir -p "$proj/a/.cargo"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/a/.cargo/config.toml"
  for mode in 644 000; do
    chmod "$mode" "$proj/a/locked"
    if [ -x "$proj/a/locked" ]; then chmod 755 "$proj/a/locked"; skip "running with permissions that search a mode-$mode directory: NOT checked"; fi
    run devbin_run "$proj" check targetdir
    chmod 755 "$proj/a/locked"
    assert_failure
    assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
    # In play because a crate beneath the hole would fork, never because
    # cargo could not answer.
    refute_output_contains "cargo cannot say where"
    refute_output_contains "could not be measured"
  done
}

@test "a workspace's own target-dir = \"target\", beside an unreadable directory not beneath it, is reported, not failed (0163)" {
  # A config moves only crates beneath its own directory, so a hole elsewhere
  # tells nothing about it: the remedy fullcycle offers a machine fork stays
  # green beside a docker volume.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo" "$proj/data/mysql" "$proj/native/cli-db"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/native/cli/.cargo/config.toml"
  hole_arm "$proj/data/mysql"
  # A sibling whose name begins with the config's directory is not beneath it.
  hole_arm "$proj/native/cli-db"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql" "$proj/native/cli-db"
  assert_success
  assert_output_contains "native/cli builds into its own target"
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a config that moves nothing, over an unreadable directory beneath it with no crate answered, is reported, not failed (0163)" {
  # Its crates may lie beneath the hole, so it was in play; cargo, asked what
  # it pins, says nothing moves.
  need_cargo_include
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/.cargo" "$proj/native/locked/cli"
  printf 'include = []\n' >"$proj/native/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_success
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "cargo_build_dirs names the walk's holes in a fifth array, each kind, and only when asked (0163)" {
  local proj out tmp; proj="$(rustproj)"
  tmp="$BATS_TEST_TMPDIR/holes-tmp"
  mkdir -p "$proj/listed" "$proj/sealed" "$proj/searchonly" "$tmp"
  chmod 644 "$proj/listed"
  chmod 000 "$proj/sealed"
  # Searchable by its owner, not readable: missed until the clause asked for a
  # read bit too.
  chmod 100 "$proj/searchonly"
  if [ -x "$proj/listed" ] || [ -r "$proj/sealed" ] || [ -r "$proj/searchonly" ]; then chmod 755 "$proj/listed" "$proj/sealed" "$proj/searchonly"; skip "running with permissions that read a mode-000 directory: NOT checked"; fi
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(TMPDIR="$tmp" fixture_run "$proj" 'rc=0; cargo_build_dirs c t "" f h 2>/dev/null || rc=$?; printf "rc=%s n=%s\n" "$rc" "${#h[@]}"; printf "%s\n" "${h[@]}" | sort' 2>&1)" || true
  [ "$out" = "rc=2 n=3
$proj/listed
$proj/sealed
$proj/searchonly" ] || { chmod 755 "$proj/listed" "$proj/sealed" "$proj/searchonly"; fail "holes: $out"; }
  # Asked or not, no holes file is left in TMPDIR.
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(TMPDIR="$tmp" fixture_run "$proj" 'rc=0; cargo_build_dirs c t "" f 2>/dev/null || rc=$?; printf "rc=%s" "$rc"' 2>&1)" || true
  chmod 755 "$proj/listed" "$proj/sealed" "$proj/searchonly"
  [ "$out" = "rc=2" ] || fail "four names: $out"
  [ -z "$(ls -A "$tmp")" ] || fail "left in TMPDIR: $(ls -A "$tmp")"
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(fixture_run "$proj" 'rc=0; cargo_build_dirs c t "" f h || rc=$?; printf "rc=%s n=%s|%s" "$rc" "${#h[@]}" "${h[*]}"' 2>&1)" || true
  [ "$out" = "rc=0 n=0|" ] || fail "no hole: $out"
}

@test "a config cargo cannot read, over an unreadable directory beneath it, stays in play (0163)" {
  # The probe cannot say what it pins, so it is not cleared.
  need_cargo
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/.cargo" "$proj/native/locked/cli"
  printf '[build]\ntarget-dir = \n' >"$proj/native/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
  # Cargo was asked from the hole's parent, and refused the config.
  assert_output_contains "cargo cannot say where"
  assert_output_contains "check targetdir: where a crate beneath $proj/native would build could not be measured (the error above says why)"
  # The config is what to fix, so the hole's remedy is not offered.
  refute_output_contains "move it out of the workspace"
}

@test "a project config that moves nothing, over a hole beneath it, is not put in play by the machine's fork (0163)" {
  # Asked from the project root, the probe hears the machine's config too;
  # where every crate on the machine builds is no fork of this project's.
  need_cargo_include
  local proj home; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo14"
  mkdir -p "$home" "$proj/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "%s/mw-hole"\n' "$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)" >"$home/config.toml"
  printf 'include = []\n' >"$proj/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a config above the project that forks, over an unreadable directory holding the only crate, fails the check (0163)" {
  # Asked from the hole's parent, cargo reads the config above the project as
  # a crate beneath the hole would (nothing pinned the config above the
  # project toward red).
  need_cargo
  local proj; proj="$(rustproj)"
  mkdir -p "$DEVBIN_TEST_TMPDIR/.cargo" "$proj/native/locked/cli"
  printf '[build]\ntarget-dir = "%s/above-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
  refute_output_contains "could not be measured"
}

@test "a config above the project that a project config overrides, beside an unreadable directory, is not in play (0163)" {
  # A crate beneath the hole reads the project's config first, which pins the
  # shared tree; asking the config above from its own directory read it alone
  # and failed a correct project.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$DEVBIN_TEST_TMPDIR/.cargo" "$proj/.cargo" "$proj/pgdata"
  printf '[build]\ntarget-dir = "%s/above-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/.cargo/config.toml"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/.cargo/config.toml"
  hole_arm "$proj/pgdata"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/pgdata"
  assert_success
  assert_output_contains "cargo    . builds into"
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a workspace's own target-dir = \"target\", over an unreadable directory beneath it, fails, saying how to clear it (0163)" {
  # A crate beneath the hole builds into the workspace's target as a member or
  # as a second workspace forked into it, and only what the hole hides tells
  # which, so it fails, where 0.1.8 cleared the config; the failure gives the
  # remedy.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo" "$proj/native/cli/data/pg"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/native/cli/.cargo/config.toml"
  hole_arm "$proj/native/cli/data/pg"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/cli/data/pg"
  assert_failure
  assert_output_contains "native/cli builds into its own target"
  assert_output_contains "so a crate beneath it may build elsewhere unasked -- a crate beneath $proj/native/cli/data would build into $proj/native/cli/target, and only what the directory hides tells whether that forks: make the directory readable to the user running this check, or move it out of the workspace."
}

@test "a hole put in play because the machine's tree cannot be measured says so (0163)" {
  # TMPDIR beneath the project's config clouds the machine's reading, so a
  # probe answering the machine's fork cannot be told from it (in play, and
  # nothing said why).
  need_cargo_include
  local proj home; proj="$(rustproj)"
  home="$BATS_TEST_TMPDIR/fakecargo-unread"
  mkdir -p "$home" "$proj/.cargo" "$proj/data/mysql" "$proj/tmp"
  printf '[build]\ntarget-dir = "%s/mw-unread"\n' "$(cd -P "$DEVBIN_TEST_TMPDIR" && pwd -P)" >"$home/config.toml"
  printf 'include = []\n' >"$proj/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  CARGO_HOME="$home" TMPDIR="$proj/tmp" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_failure
  assert_output_contains "Where the machine's config sends a build could not be measured, so"
  assert_output_contains "a cargo config at or above $proj/tmp may apply too."
}

@test "a hole the walk cannot place is asked of a config above the project from the project root, so the root's own config is read first (0163)" {
  # An ACL hole is not recorded, so it lies, for all the walk can tell,
  # anywhere. Asked from above the root, cargo read the config above alone and
  # failed a project whose own config pins the shared tree.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj"
  mkdir -p "$DEVBIN_TEST_TMPDIR/.cargo" "$proj/.cargo" "$proj/pgdata"
  printf '[build]\ntarget-dir = "%s/above-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$DEVBIN_TEST_TMPDIR/.cargo/config.toml"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/.cargo/config.toml"
  acl_hole "$proj/pgdata"

  run devbin_run "$proj" check targetdir

  acl_clear "$proj/pgdata"
  assert_success
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "a config inside a directory the walk can search but not list is read, and its fork fails the check (0163)" {
  # Cargo, run from inside, reads native/vault/.cargo/config.toml, which the
  # walk could not list; asked from the parent, nothing applied and it passed.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/vault/cli"
  mkdir -p "$proj/native/vault/.cargo"
  printf '[build]\ntarget-dir = "%s/vault-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/native/vault/.cargo/config.toml"
  chmod 100 "$proj/native/vault"
  if [ -r "$proj/native/vault" ]; then chmod 755 "$proj/native/vault"; skip "running with permissions that read a mode-100 directory: NOT checked"; fi

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/vault"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "a hole the walk cannot place, beside one it can, is still asked of every config (0163)" {
  # The 000 directory is recorded, the ACL hole holding the only crate is not;
  # one recorded hole dropped the record saying the other lay somewhere.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/locked/cli"
  mkdir -p "$proj/native/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "%s/acl-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/native/.cargo/config.toml"
  acl_hole "$proj/native/locked"
  chmod 000 "$proj/data/mysql"
  if [ -r "$proj/data/mysql" ]; then chmod 755 "$proj/data/mysql"; acl_clear "$proj/native/locked"; skip "running with permissions that read a mode-000 directory: NOT checked"; fi

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  acl_clear "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
}

@test "cargo_build_dirs reads a failed walk with no hole recorded as one hole it cannot place (0163)" {
  local proj out; proj="$(rustproj)"
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(fixture_run "$proj" 'cargo_walk() { return 1; }; rc=0; cargo_build_dirs c t "" f h 2>/dev/null || rc=$?; printf "rc=%s n=%s|%s|" "$rc" "${#h[@]}" "${h[0]-unset}"' 2>&1)" || true
  [ "$out" = "rc=2 n=1||" ] || fail "a failed walk: $out"
}

@test "a FIND_WALK_HOLES inherited is dropped at load, and one set after is not written by cargo_build_dirs not asked for holes (0163)" {
  # Inherited, helpers unsets it at load, so no walk appends to it; set in
  # the shell after load, cargo_build_dirs' own prefix empties it for its
  # walk. Either one gone, a walk writes to it.
  local proj out f; proj="$(rustproj)"
  f="$BATS_TEST_TMPDIR/inherited.holes"
  : >"$f"
  mkdir -p "$proj/sealed"
  hole_arm "$proj/sealed"
  export FIND_WALK_HOLES="$f"
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(fixture_run "$proj" 'rc=0; find_walk . -print >/dev/null 2>&1 || rc=$?; printf "rc=%s" "$rc"' 2>&1)" || true
  unset FIND_WALK_HOLES
  [ "$out" = "rc=1" ] && [ ! -s "$f" ] || { chmod 755 "$proj/sealed"; fail "inherited: $out, records [$(tr '\0' '|' <"$f")]"; }
  # shellcheck disable=SC2016 # the script is fixture_run's, expanded there
  out="$(fixture_run "$proj" 'FIND_WALK_HOLES="$1"; rc=0; cargo_build_dirs c t "" cf 2>/dev/null || rc=$?; printf "rc=%s" "$rc"' "$f" 2>&1)" || true
  chmod 755 "$proj/sealed"
  [ "$out" = "rc=2" ] || fail "set after load: $out"
  [ ! -s "$f" ] || fail "set after load, the file was written: $(tr '\0' '|' <"$f")"
}

@test "a crate the walk answered forking, beside an unrelated unreadable directory, fails without the hole's remedy (0163)" {
  # The fork is named and failed as such; making the directory readable would
  # not clear it, so the hole's failure does not say it would.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"
  mkdir -p "$proj/native/cli/.cargo" "$proj/data/mysql"
  printf '[build]\ntarget-dir = "%s/cli-fork"\n' "$DEVBIN_TEST_TMPDIR" >"$proj/native/cli/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_failure
  assert_output_contains "cargo builds native/cli into $DEVBIN_TEST_TMPDIR/cli-fork"
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
  refute_output_contains "move it out of the workspace"
}

@test "the probe answers beneath a project that declares a [workspace], so a correct project over a hole passes (0163)" {
  # With TMPDIR inside the project, the probe crate sat beneath its workspace
  # and cargo refused a package that workspace does not list; the hole then
  # counted as in play.
  need_cargo_include
  local proj; proj="$(rustproj)"
  real_crate "$proj/a"
  printf '[workspace]\nmembers = ["a"]\nresolver = "2"\n' >"$proj/Cargo.toml"
  mkdir -p "$proj/.cargo" "$proj/data/mysql" "$proj/tmp"
  printf 'include = []\n' >"$proj/.cargo/config.toml"
  hole_arm "$proj/data/mysql"

  TMPDIR="$proj/tmp" run devbin_run "$proj" check targetdir

  chmod 755 "$proj/data/mysql"
  assert_success
  refute_output_contains "believes it's in a workspace"
  assert_output_contains "no cargo config naming target-dir or include is in play here -- not failed"
}

@test "with no Cargo.toml at the project root, <root>/target is no shared tree: a nested crate is told where cargo builds, and a value pinning it fails (0167)" {
  # clean removes a tree only beside a Cargo.toml, so <root>/target outlives
  # every clean here, and fullcycle fails a cycle built there; check called it
  # the shared tree three ways and passed each.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"

  run devbin_run "$proj" check targetdir
  assert_success
  assert_output_contains "cargo builds each crate into its own workspace target"
  refute_output_contains "shared tree"

  CARGO_TARGET_DIR="$proj/target" run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "CARGO_TARGET_DIR=$proj/target -- no Cargo.toml sits beside it at the project root, so clean never removes it"
  refute_output_contains "points at the shared tree"

  mkdir -p "$proj/native/cli/.cargo"
  printf '[build]\ntarget-dir = "../../target"\n' >"$proj/native/cli/.cargo/config.toml"
  run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "cargo builds native/cli into $proj/target, not its own target, and $proj/target, with no Cargo.toml beside it, is no tree clean removes"
  refute_output_contains "builds into the shared tree"
}

@test "build_tree_rebuildable asks clean's question: a manifest beside the tree, on the path as given (0167)" {
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/a/target" "$proj/b/target"
  : >"$proj/a/Cargo.toml"
  run fixture_run "$proj" 'build_tree_rebuildable "$1/a/target" Cargo.toml && echo a; build_tree_rebuildable "$1/b/target" Cargo.toml || echo not-b; build_tree_rebuildable "$1/a/target/" Cargo.toml && echo slash' "$proj"
  assert_success
  [ "$output" = "a
not-b
slash" ] || fail "$output"
}

@test "a config pinning <root>/target over an unreadable directory, with no Cargo.toml at the root, is in play (0167)" {
  # A crate beneath the hole would build into a tree clean never removes, so
  # the tree that config pins is no shared one to clear it by.
  need_cargo
  local proj; proj="$(rustproj)"
  mkdir -p "$proj/native/.cargo" "$proj/native/locked/cli"
  printf '[build]\ntarget-dir = "../target"\n' >"$proj/native/.cargo/config.toml"
  : >"$proj/native/locked/cli/Cargo.toml"
  hole_arm "$proj/native/locked"

  run devbin_run "$proj" check targetdir

  chmod 755 "$proj/native/locked"
  assert_failure
  assert_output_contains "a cargo config here names target-dir or include, and the walk for crates could not read everything"
  # The probe's answer is what put it in play.
  assert_output_contains "would build into $proj/target"
  refute_output_contains "could not be measured"
}

@test "with no Cargo.toml at the project root, an empty variable, a crate's own target and a root config pinning <root>/target each fail truthfully (0167)" {
  # There is no shared tree to name, so none is offered; a crate's own target
  # set by hand is still a per-session fork, never said not to be that
  # target; and a root config pinning <root>/target says why that tree is
  # wrong here.
  need_cargo
  local proj; proj="$(rustproj)"
  real_crate "$proj/native/cli"

  CARGO_TARGET_DIR="" run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "CARGO_TARGET_DIR='' "
  assert_output_contains "-- unset it."
  refute_output_contains "set it to the shared tree"

  CARGO_TARGET_DIR="$proj/native/cli/target" run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "a per-session fork of the build cache, and with no Cargo.toml at the project root there is no shared tree to set it to: unset it"
  refute_output_contains "not each crate's own"

  mkdir -p "$proj/.cargo"
  printf '[build]\ntarget-dir = "target"\n' >"$proj/.cargo/config.toml"
  run devbin_run "$proj" check targetdir
  assert_failure
  assert_output_contains "cargo builds native/cli into $proj/target -- this forks the cache for every session in this project, not just yours. With no Cargo.toml beside it, $proj/target is no tree clean removes."
}
