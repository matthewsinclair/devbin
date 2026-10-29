#!/usr/bin/env bash
# install-shellcheck.sh -- put ONE pinned shellcheck on PATH, on either platform.
#
# WHY A PIN AND NOT A PACKAGE. Before the pin, the CI jobs each installed this
# tool a different way and got two different analysers:
#
# (Note the wrapping: a comment line STARTING with the word for this tool is
# parsed as a directive, SC1072/SC1073. `shell-gate` documents that same trap
# and the first draft of this file still carried one.)
#
#   job "Test on Ubuntu"         apt-get install   0.9.0
#   job "Shell Script Analysis"  apt-get install   0.9.0
#   job "Test on macOS"          brew install      0.11.0
#   a developer's machine        brew install      0.11.0
#
# 0.9.0 reports SC2015 on `[ -f "$f" ] && [ -x "$f" ] || continue`; 0.11.0 does
# not. So the shellcheck job failed for five days on three findings that every
# local `bin/devbin check lint` reported clean, and BOTH GATES WERE HONEST. The
# local one was not running at a lower severity -- devbin issue 0052 first said
# it was, and that was wrong. It was running a different program.
#
# A GATE WHOSE ANALYSER FLOATS IS A GATE THAT CHANGES ITS VERDICT ON A COMMIT
# THAT CHANGED NOTHING. `apt-get install shellcheck` moves whenever the runner
# image does, so the red arrives detached from any edit and reads as a mystery.
# Pinning makes an analyser upgrade an explicit commit, which is the only form
# in which anyone can review it.
#
# The version lives HERE and nowhere else. Bump it in one place, in a commit
# whose diff is the bump, and let CI show what it newly finds.
set -euo pipefail

SHELLCHECK_VERSION="v0.11.0"

case "$(uname -s)" in
  Linux)  platform="linux" ;;
  Darwin) platform="darwin" ;;
  *) echo "install-shellcheck: unsupported platform $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch="x86_64" ;;
  arm64|aarch64) arch="aarch64" ;;
  *) echo "install-shellcheck: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.${platform}.${arch}.tar.xz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "install-shellcheck: fetching ${SHELLCHECK_VERSION} for ${platform}.${arch}"
# Fetched whole, then unpacked: tar can stop reading at its end-of-archive
# marker, and curl, piped into it, would take SIGPIPE writing the rest (0031).
curl -fsSL -o "$tmp/shellcheck.tar.xz" "$url"
tar -xJf "$tmp/shellcheck.tar.xz" -C "$tmp"
sudo install -m 0755 "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck

# ASSERT WHAT LANDED, because an installer that silently does nothing leaves the
# previously-installed binary on PATH and every downstream job then measures the
# thing this script exists to replace -- and reports it as a pass.
got="$(shellcheck --version | awk '/^version:/ { print $2 }')"
want="${SHELLCHECK_VERSION#v}"
if [ "$got" != "$want" ]; then
  echo "install-shellcheck: PATH shellcheck is $got, wanted $want" >&2
  echo "  which shellcheck: $(command -v shellcheck)" >&2
  exit 1
fi
echo "install-shellcheck: shellcheck $got on PATH"
