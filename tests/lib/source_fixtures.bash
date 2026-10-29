#!/usr/bin/env bash
# source_fixtures.bash -- fixtures that build a devbin SOURCE, not an install.
#
# SEPARATE FROM test_helper.bash ON PURPOSE, and the reason is a guard rather
# than tidiness. `install.bats` asserts structurally that the harness contains
# no `cp -R "$DEVBIN_LIB_DIR"` -- because a second copy of the installer living
# in the harness is exactly what the one-installer rule refuses, and a
# behavioural test would pass against one. A SOURCE builder legitimately copies
# `lib/`: it is producing the thing `install --into` consumes, not standing in
# for it. Putting it here keeps the guard's population exactly what its claim
# is about.
#
# Loaded by the suites that need a source and an install of it side by side:
# vendor.bats, for the direction and state arms, and version.bats, for the
# runtime digest, whose whole contract is that those two agree.

# mkempty [name] -- an empty directory under the test tmpdir, to install INTO.
mkempty() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-target}"
  mkdir -p "$dir"
  echo "$dir"
}

# mksrc [name] -- a real, MUTABLE devbin source, copied rather than symlinked so
# editing it cannot reach back into the checkout under test.
#
# It carries BOTH halves of the seam, because a source has to RUN as well as be
# read from: `lib/` and `bin/devbin` are what is_devbin_source and
# vendored_paths look at, and `bin/.devbin/` is devbin-the-project's own config,
# cmd/ and help/ -- without which the copy cannot execute its own `install` and
# every fixture dies on "no config" before reaching what it meant to test.
#
# ONE HOME: vendor.bats built these fixtures first and version.bats now needs
# the same pair, because the runtime digest's whole contract is a claim about a
# source and an install of it agreeing. A second copy would be two fixtures
# drifting under one name, in the suites that compare them.
mksrc() {
  local dir="$DEVBIN_TEST_TMPDIR/${1:-src}"
  mkdir -p "$dir/bin"
  cp "$DEVBIN_BIN_DIR/devbin" "$dir/bin/devbin"
  chmod +x "$dir/bin/devbin"
  cp -R "$DEVBIN_LIB_DIR" "$dir/lib"
  cp -R "$DEVBIN_HOME/bin/.devbin" "$dir/bin/.devbin"
  [ -f "$DEVBIN_HOME/VERSION" ] && cp "$DEVBIN_HOME/VERSION" "$dir/VERSION"
  echo "$dir"
}
