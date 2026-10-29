# devbin's Homebrew formula, kept as a TEMPLATE in devbin's own tree, outside
# the set a publish copies. It is never installed from this file:
# `bin/devbin formula render <tag> <out>` writes the formula for a release tag,
# reading the tag's commit from git, and `bin/devbin formula publish` renders
# the newest release into the tap and pushes it. The tag and the revision below
# are placeholders that render fills, exactly one of each.
#
# NOBODY TYPES A TAG OR A COMMIT INTO THIS FORMULA. brew checks out the tag at
# install and stops when its commit is not the revision, so a wrong revision
# fails every install; the offline `brew audit` accepts any 40 hex digits, so it
# would not have caught one.
class Devbin < Formula
  desc "Dev launcher framework that projects vendor as bin/devbin"
  homepage "https://github.com/matthewsinclair/devbin"
  # HTTPS, THE PUBLIC REPOSITORY. devbin publishes each release as a snapshot
  # of the product in a public repository, so brew fetches it with no
  # credential, and the formula installs for anyone. The tag below is that
  # repository's, and render reads the revision there, the snapshot's commit,
  # which a development checkout does not hold.
  url "https://github.com/matthewsinclair/devbin.git",
      tag:      "@@TAG@@",
      revision: "@@REVISION@@"
  license "MIT"

  # devbin refuses macOS's own bash, 3.2, and runs on bash 5 or later, so on
  # macOS this formula depends on Homebrew's. On Linux the launcher runs on the
  # system's bash, which must meet the floor, and devbin refuses one that does
  # not, as it refuses any. What a single verb needs beyond that, `bin/devbin
  # doctor` reports in each project; nothing else is installed here.
  on_macos do
    depends_on "bash"
  end

  def install
    # devbin's own publish, run from the tag's checkout: it refuses a tree that
    # is not clean, copies the runtime git names, writes the manifest with the
    # commit and every commit before it, and records that Homebrew owns this
    # install, so devbin's own install and upgrade refuse to write into it.
    system "bin/devbin", "install", "--prefix", libexec, "--managed-by", "brew"
    # THE GUIDES GO IN THE KEG BESIDE THE README (devbin#0254). Homebrew puts
    # the README, CHANGELOG.md and LICENSE in the keg itself, as metafiles, but
    # the README also links docs/ and RELEASES.md, and a brew user has no
    # checkout to find them in. So the formula installs them at the keg root,
    # the parent of libexec, after the publish above, which refuses a tree that
    # is not clean and so must run before they move out of the checkout.
    prefix.install "docs", "RELEASES", "RELEASES.md"
    # ON macOS THE KEG'S bin/devbin RUNS UNDER THE BASH THIS FORMULA DEPENDS ON.
    # macOS's /bin/bash is 3.2, below devbin's floor, and a process started
    # without Homebrew's PATH, cron or a hook a GUI app launched, finds it
    # first. So on macOS bin/devbin is a script that puts the formula's bash
    # first on PATH, for the dispatcher and every handler it starts, and runs
    # libexec's launcher, which is left as published: the keg's manifest still
    # matches it, and a project vendors the same bytes. That script, and
    # Homebrew's bin link to it, run under the formula's bash; libexec's
    # launcher still runs under the bash PATH finds, so devbin's own hints, its
    # help's seed line and dvb name the keg by this bin/devbin, through the
    # opt link (devbin#0266). On Linux the launcher runs on the system's
    # bash, as above, and finds its runtime from its own resolved path, so bin/
    # needs only a link.
    if OS.mac?
      (bin/"devbin").write_env_script libexec/"bin/devbin", PATH: "#{formula_opt_bin("bash")}:$PATH"
    else
      bin.install_symlink libexec/"bin/devbin"
    end
  end

  def caveats
    <<~EOS
      A project vendors devbin from this install:
        devbin install --into <project>
      and the project's bin/devbin upgrade finds it again at
        #{opt_libexec}
      through HOMEBREW_PREFIX, which `brew shellenv` exports, unless
      DEVBIN_INSTALL_PREFIX or the link ~/.local/bin/devbin names another tree.
      bin/devbin doctor, run in a project, says which install it reads and why.

      A maintainer with a dev checkout or an opt install of devbin chooses
      between them and this install with devbin use (devbin use brew returns
      to this one).

      devbin's own install and upgrade refuse to write into this install.
      Update it with:
        brew upgrade devbin
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/devbin --version")
  end
end
