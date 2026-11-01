#!/usr/bin/env bats
# formula.bats - the built-in formula (issue 0227): a project's Homebrew formula
# rendered from a template and a release, and published to its tap. It was
# devbin's own command (0195) until 0227 hoisted it into lib/cmd/formula, in two
# modes.
#
# SOURCE: the template holds one placeholder for the release tag and one for its
# commit, filled from git. These arms run over a fixture checkout holding
# devbin's REAL template, so an arm that renders it also proves the template
# holds exactly one of each placeholder.
#
# ASSETS: the templates hold the release's version and a sha256 per asset, read
# from the release's sums file, and an install body devbin generates. A stubbed
# gh serves the sums file, so nothing here reaches a network.
#
# publish pushes to a local bare repository standing in for the tap, and asks a
# person first: the arms that answer it run on a pty through expect
# (run_tty_answer), and are skipped, saying so, where expect is not installed.

load "../lib/test_helper"
# formula_tap, the stand-in for the tap, which releasecut.bats shares.
load "../lib/release_fixtures"

setup() { devbin_setup; }
teardown() { devbin_teardown; }

# formula_checkout -- a fixture devbin checkout at $FX: the real template, a
# config naming no release.tag (so the core's default, v{version}, applies),
# and three tags: v0.0.10 on the first commit and v0.0.9 on the second, both
# annotated and made in that order, so the newest release by version is
# neither the newest tag made nor the last in byte order; and `light`,
# lightweight.
formula_checkout() {
  FX="$DEVBIN_TEST_TMPDIR/devbin"
  git init -q -b main "$FX"
  mkdir -p "$FX/packaging/homebrew" "$FX/bin/.devbin"
  cp "$DEVBIN_HOME/packaging/homebrew/devbin.rb" "$FX/packaging/homebrew/devbin.rb"
  printf 'project:\n  name: devbin\n' >"$FX/bin/.devbin/config.yaml"
  fx_commit_and_tag v0.0.10 v0.0.9
  git -C "$FX" tag light
}

# fx_commit_and_tag <first> <second> -- commit $FX, tag it <first>, then an
# empty commit tagged <second>, both annotated.
fx_commit_and_tag() {
  git -C "$FX" add -A
  git -C "$FX" -c user.name=t -c user.email=t@t commit -q -m one
  git -C "$FX" -c user.name=t -c user.email=t@t tag -a -m "release $1" "$1"
  git -C "$FX" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
  git -C "$FX" -c user.name=t -c user.email=t@t tag -a -m "release $2" "$2"
}

# formula_env -- the environment the dispatcher gives the handler, one
# assignment a line, for `env`: a git identity for publish's commit, its own
# TMPDIR, which every arm that publishes checks it left empty, and the gh stub
# first on PATH.
formula_env() {
  mkdir -p "$DEVBIN_TEST_TMPDIR/tmp"
  printf '%s\n' "TMPDIR=$DEVBIN_TEST_TMPDIR/tmp" \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    "DEVBIN_LIB=$DEVBIN_LIB_DIR" "PROJECT_ROOT=$FX" "DEVBIN_DIR=$FX/bin/.devbin" \
    "DEVBIN_NAME=$(awk '/^  name: / { sub(/^  name: /, ""); print; exit }' "$FX/bin/.devbin/config.yaml")" DEVBIN_INVOKE=bin/devbin \
    "PATH=$DEVBIN_TEST_TMPDIR/ghstub:$PATH"
}

# formula <arg>... -- the built-in, run in $FX as the dispatcher runs it, with
# no terminal: stdin is /dev/null, so nobody is there to answer publish.
formula() {
  local -a e
  mapfile -t e < <(formula_env)
  (cd "$FX" && env "${e[@]}" bash "$DEVBIN_LIB_DIR/cmd/formula" "$@" </dev/null)
}

# formula_tty <answer> <arg>... -- the built-in on a pty, with <answer> typed at
# its prompt (run_tty_answer). Skipped where expect is not installed. It runs
# run_tty_answer under `run` itself and is called without it, as
# publish_cut_answered is: called under `run`, require_expect's skip would end
# only run's subshell, with status 0 and no output, and the arm would fail its
# assertions wherever expect is not installed (issue 0232).
formula_tty() {
  local answer="$1" w="$DEVBIN_TEST_TMPDIR/formula.sh" a
  shift
  require_expect
  {
    printf '#!/usr/bin/env bash\ncd %q || exit 2\nexec env' "$FX"
    while IFS= read -r a; do printf ' %q' "$a"; done < <(formula_env)
    printf ' bash %q "$@"\n' "$DEVBIN_LIB_DIR/cmd/formula"
  } >"$w"
  chmod +x "$w"
  run run_tty_answer "$answer" "$w" "$@"
}

# tmp_left -- what publish left in its TMPDIR, one path a line, which must be
# nothing. Read by glob, never by parsing ls, and a TMPDIR that is not there is
# named rather than read as empty, since it would hold nothing either way.
tmp_left() {
  local d="$DEVBIN_TEST_TMPDIR/tmp" f
  [ -d "$d" ] || {
    printf 'no TMPDIR at %s\n' "$d"
    return 0
  }
  shopt -s nullglob dotglob
  for f in "$d"/*; do printf '%s\n' "$f"; done
}

# --- assets mode fixtures ----------------------------------------------------

SHA_MAC=1111111111111111111111111111111111111111111111111111111111111111
SHA_LIN=2222222222222222222222222222222222222222222222222222222222222222
SHA_PKG=3333333333333333333333333333333333333333333333333333333333333333
SHA_DECOY=4444444444444444444444444444444444444444444444444444444444444444

# assets_checkout -- a fixture project `tool` at $FX in assets mode: a formula
# template with a top-level url for macOS and an on_linux branch with one, a
# cask template, three assets (two named with {version}), one executable, and
# tags v1.2.3 then v1.2.4; and the release's SHA256SUMS for v1.2.4 at $SUMS,
# holding each asset and two decoys whose names are near theirs. The gh stub
# serves $SUMS for `release download` and records every call in gh.calls.
assets_checkout() {
  FX="$DEVBIN_TEST_TMPDIR/tool"
  git init -q -b main "$FX"
  mkdir -p "$FX/packaging/homebrew" "$FX/bin/.devbin"
  cat >"$FX/bin/.devbin/config.yaml" <<'YAML'
project:
  name: tool
release:
  repo: t/tool
formula:
  mode: assets
  repo: t/tool-dist
  cask: packaging/homebrew/tool-app.rb
  assets:
    - tool-aarch64-apple-darwin
    - "tool-{version}-aarch64-linux.tar.gz"
    - "Tool-{version}.pkg"
  bin:
    - bin/tool
YAML
  cat >"$FX/packaging/homebrew/tool.rb" <<'RUBY'
class Tool < Formula
  desc "A tool"
  homepage "https://example.invalid/tool"
  url "https://example.invalid/download/v@@VERSION@@/tool-aarch64-apple-darwin"
  sha256 "@@SHA256:tool-aarch64-apple-darwin@@"
  license "MIT"

  on_linux do
    on_arm do
      url "https://example.invalid/download/v@@VERSION@@/tool-@@VERSION@@-aarch64-linux.tar.gz"
      sha256 "@@SHA256:tool-{version}-aarch64-linux.tar.gz@@"
    end
  end

  def install
    (libexec/"bin").install Dir["tool-*"].first => "tool"
    @@FINISH@@
  end

  def caveats
    "tool use names the tree this machine runs"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tool --version")
  end
end
RUBY
  cat >"$FX/packaging/homebrew/tool-app.rb" <<'RUBY'
cask "tool-app" do
  version "@@VERSION@@"
  sha256 "@@SHA256:Tool-{version}.pkg@@"

  url "https://example.invalid/download/v#{version}/Tool-#{version}.pkg"
  name "Tool"
  pkg "Tool-#{version}.pkg"
end
RUBY
  fx_commit_and_tag v1.2.3 v1.2.4
  SUMS="$DEVBIN_TEST_TMPDIR/SHA256SUMS"
  printf '%s  %s\n' "$SHA_DECOY" Tool-1.2.4.pkg.zip "$SHA_MAC" tool-aarch64-apple-darwin \
    "$SHA_DECOY" tool-aarch64-apple-darwin.tar.gz "$SHA_LIN" tool-1.2.4-aarch64-linux.tar.gz \
    "$SHA_PKG" Tool-1.2.4.pkg >"$SUMS"
  mkdir -p "$DEVBIN_TEST_TMPDIR/ghstub"
  cat >"$DEVBIN_TEST_TMPDIR/ghstub/gh" <<SH
#!/bin/sh
echo "gh \$*" >>"$DEVBIN_TEST_TMPDIR/gh.calls"
[ "\$1 \$2" = "release download" ] || exit 1
dir=""
while [ \$# -gt 0 ]; do
  [ "\$1" = --dir ] && dir="\$2"
  shift
done
cp "$SUMS" "\$dir/SHA256SUMS"
SH
  chmod +x "$DEVBIN_TEST_TMPDIR/ghstub/gh"
}

# ruby_keg <formula> -- run <formula>'s install under plain Ruby, in a keg at
# $DEVBIN_TEST_TMPDIR/keg, from a staging directory holding the macOS asset at
# mode 0644, as GitHub serves it. NOT a brew install: the Formula DSL brew
# supplies is stood in for by the smallest Ruby that runs the install, and
# Pathname#sha256, which brew adds, by Ruby's own Digest.
ruby_keg() {
  local stage="$DEVBIN_TEST_TMPDIR/stage"
  mkdir -p "$stage" "$DEVBIN_TEST_TMPDIR/keg"
  printf 'tool binary\n' >"$stage/tool-aarch64-apple-darwin"
  chmod 0644 "$stage/tool-aarch64-apple-darwin"
  (cd "$stage" && ruby -e '
    require "pathname"
    require "digest"
    require "fileutils"
    class Pathname
      def sha256
        Digest::SHA256.file(self).hexdigest
      end
      def install(map)
        mkpath
        map.each { |src, name| FileUtils.mv(src, self/name) }
      end
      def install_symlink(src)
        mkpath
        File.symlink(src, self/File.basename(src))
      end
    end
    class Formula
      def self.method_missing(*_args, &_blk)
        nil
      end
      def self.respond_to_missing?(*_args)
        true
      end
      # Kernel has a test of its own, which method_missing never sees.
      def self.test(*_args, &_blk)
        nil
      end
      attr_reader :libexec, :bin
      def initialize(root)
        @libexec = Pathname(root)/"libexec"
        @bin = Pathname(root)/"bin"
      end
      def chmod(mode, path)
        File.chmod(mode, path)
      end
    end
    load ARGV[0]
    Tool.new(ARGV[1]).install
  ' "$1" "$DEVBIN_TEST_TMPDIR/keg")
}

# want_header <template> <tag> <commit> -- the header a render opens with
# (issue 0257), written out here rather than read from lib/cmd/formula, so an
# arm comparing a render with it holds the header's words.
want_header() {
  printf '%s\n' "# RENDERED by devbin's formula built-in from the template below, for the tag" \
    "# below and the commit it names: edit the template, not this file, which the" \
    "# next render replaces." \
    "#   template  $1" "#   tag       $2" "#   commit    $3"
}

# template_body <file> -- <file> from its first line that is neither a comment
# nor blank, which is what a render keeps of a template, read with awk rather
# than with the built-in's own code.
template_body() {
  awk 'body || (!/^[[:space:]]*#/ && !/^[[:space:]]*$/) { body = 1; print }' "$1"
}

# --- source mode -------------------------------------------------------------

@test "render fills the template's one tag and one revision from git under a header of its own, and changes no other byte (0195, 0257)" {
  local commit out="$DEVBIN_TEST_TMPDIR/devbin.rb" want="$DEVBIN_TEST_TMPDIR/want.rb"
  formula_checkout
  # The template's header holds the sentences the render must drop, so their
  # absence below says something.
  assert_file_contains "$FX/packaging/homebrew/devbin.rb" 'never installed'
  assert_file_contains "$FX/packaging/homebrew/devbin.rb" 'placeholder'
  commit="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  run formula render v0.0.10 "$out"
  assert_success
  assert_output_contains "devbin v0.0.10 at $commit"
  {
    want_header packaging/homebrew/devbin.rb v0.0.10 "$commit"
    template_body "$FX/packaging/homebrew/devbin.rb" | sed -e 's/@@TAG@@/v0.0.10/' -e "s/@@REVISION@@/$commit/"
  } >"$want"
  cmp -s "$want" "$out" || fail "the rendered formula is not the render's header over the template, with the tag and the commit filled in:
$(diff "$want" "$out")"
  # The template's header is about the template, and brew installs from this
  # file with the tag and the commit filled in (issue 0257).
  refute_file_contains "$out" 'never installed'
  refute_file_contains "$out" 'placeholder'
  assert_file_contains "$out" 'tag:      "v0.0.10",'
  assert_file_contains "$out" "revision: \"$commit\""
  refute_file_contains "$out" '@@'
}

@test "render keeps a magic comment from the template's header above its own, where Ruby reads one, and drops the rest of that header (0257)" {
  local commit out="$DEVBIN_TEST_TMPDIR/devbin.rb" want="$DEVBIN_TEST_TMPDIR/want.rb" t
  formula_checkout
  t="$FX/packaging/homebrew/devbin.rb"
  # An Emacs mode line on the first line; a magic comment; a line of the same
  # `# key: value` shape whose key is no magic one; a blank line; a magic
  # comment with a dash and capitals, which Ruby reads the same; then the
  # template's own header and the rest.
  {
    printf '%s\n' '# -*- coding: utf-8 -*-' '# frozen_string_literal: true' '# Note: rendered' '' '# Warn-Indent: true'
    cat "$t"
  } >"$t.new"
  mv "$t.new" "$t"
  commit="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  run formula render v0.0.10 "$out"
  assert_success
  # The magic comments in their order, then the blank line Homebrew's style
  # asks for after them, then the render's header.
  {
    printf '%s\n' '# -*- coding: utf-8 -*-' '# frozen_string_literal: true' '# Warn-Indent: true' ''
    want_header packaging/homebrew/devbin.rb v0.0.10 "$commit"
    template_body "$t" | sed -e 's/@@TAG@@/v0.0.10/' -e "s/@@REVISION@@/$commit/"
  } >"$want"
  cmp -s "$want" "$out" || fail "the render does not keep the magic comments over its header and the template's body:
$(diff "$want" "$out")"
  if command -v ruby >/dev/null 2>&1; then
    ruby -c "$out" >/dev/null || fail "the rendered formula is not Ruby: $(ruby -c "$out" 2>&1)"
  fi
}

@test "render drops a CRLF template's header as it drops an LF one's, and keeps the rest byte for byte (0257)" {
  # A checkout under autocrlf holds the template with CRLF line ends while git
  # reads it clean, and render reads the working tree: a blank line ending in a
  # carriage return still belongs to the header.
  local commit out="$DEVBIN_TEST_TMPDIR/devbin.rb" want="$DEVBIN_TEST_TMPDIR/want.rb" t
  formula_checkout
  t="$FX/packaging/homebrew/devbin.rb"
  { printf '# a note\n\n'; cat "$t"; } | awk '{ printf "%s\r\n", $0 }' >"$t.new"
  mv "$t.new" "$t"
  commit="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  run formula render v0.0.10 "$out"
  assert_success
  {
    want_header packaging/homebrew/devbin.rb v0.0.10 "$commit"
    template_body "$t" | sed -e 's/@@TAG@@/v0.0.10/' -e "s/@@REVISION@@/$commit/"
  } >"$want"
  cmp -s "$want" "$out" || fail "the CRLF template's header was not dropped, or its body changed:
$(diff "$want" "$out")"
  refute_file_contains "$out" 'never installed'
}

@test "render reads only what ships: a placeholder in the template's header is neither counted nor filled, and a template whose pins sit only there, or with nothing after its header, is refused, writing nothing (0257)" {
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb" pinless="$DEVBIN_TEST_TMPDIR/pinless.rb" empty="$DEVBIN_TEST_TMPDIR/empty.rb" t
  formula_checkout
  t="$FX/packaging/homebrew/devbin.rb"
  # A header naming the placeholders, as a note about the template might.
  { printf '# render fills @@TAG@@ and @@REVISION@@ below\n'; cat "$t"; } >"$t.new"
  mv "$t.new" "$t"
  run formula render v0.0.10 "$out"
  assert_success
  refute_file_contains "$out" 'render fills'
  refute_file_contains "$out" '@@'
  # Pins only in the header: the formula brew evaluates would pin nothing.
  printf '# @@TAG@@ @@REVISION@@\nclass Devbin < Formula\nend\n' >"$t"
  run formula render v0.0.10 "$pinless"
  assert_failure
  assert_output_contains "below its header, the template holds 0 tag placeholder(s) and 0 revision placeholder(s)"
  assert_file_not_exists "$pinless"
  # Nothing after the header: no formula at all.
  printf '# a header\n# and nothing else\n' >"$t"
  run formula render v0.0.10 "$empty"
  assert_failure
  assert_output_contains "holds nothing after its header, so there is no formula to render"
  assert_file_not_exists "$empty"
}

@test "a formula.template declared absolute is named in the header from the project root, so no absolute path reaches the tap (0257)" {
  # The template is read under the project root whatever its spelling, and the
  # rendered file goes to a tap anyone with access reads.
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb"
  formula_checkout
  printf 'formula:\n  template: /packaging/homebrew/devbin.rb\n' >>"$FX/bin/.devbin/config.yaml"
  run formula render v0.0.10 "$out"
  assert_success
  assert_file_contains "$out" '#   template  packaging/homebrew/devbin.rb'
  refute_file_contains "$out" '#   template  /'
}

@test "the rendered formula runs the launcher under the bash it depends on, by write_env_script, on macOS, and links it on Linux (0253)" {
  # macOS's /bin/bash is 3.2, and cron or a hook a GUI app launched finds it
  # first, so on macOS the keg's bin/devbin puts the formula's bash first on
  # PATH, and libexec's launcher stays as published. The install's code, the
  # OS branch's order among it, is compared whole once, by the 0254 arm below;
  # this arm holds 0253's own lines.
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb"
  formula_checkout
  run formula render v0.0.10 "$out"
  assert_success
  assert_file_contains "$out" '    depends_on "bash"'
  grep -qxF '      (bin/"devbin").write_env_script libexec/"bin/devbin", PATH: "#{formula_opt_bin("bash")}:$PATH"' "$out" ||
    fail "the rendered formula writes no env script putting the formula's bash first on PATH: $out"
  grep -qxF '      bin.install_symlink libexec/"bin/devbin"' "$out" ||
    fail "the rendered formula does not link the launcher, as it does on Linux: $out"
}

@test "devbin's rendered formula is Ruby (0253)" {
  command -v ruby >/dev/null 2>&1 || skip "ruby is not on this runner: the rendered formula's syntax is NOT checked"
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb"
  formula_checkout
  run formula render v0.0.10 "$out"
  assert_success
  run ruby -c "$out"
  assert_success
  assert_output_contains "Syntax OK"
}

# brew_metafile <file> -- rc 0 when Homebrew installs the top-level <file> into
# the keg by itself, as a metafile, after the formula's install: rc 1 for a
# directory or an empty file, which Pathname#install_metafiles passes over
# (Library/Homebrew/extend/pathname.rb), and otherwise Metafiles.copy? of its
# name (Library/Homebrew/metafiles.rb), read there and written out here, so the
# arm below holds the rule rather than a list of the README's own links.
brew_metafile() {
  local f ext
  [ -f "$1" ] && [ -s "$1" ] || return 1
  f="${1##*/}"
  f="${f,,}"
  case "${f%%[.-]*}" in
    copying | copyright | license | licence) return 0 ;;
  esac
  if [ "${f%.*}" != "$f" ]; then
    ext="${f##*.}"
    case "$ext" in
      adoc | asc | asciidoc | creole | html | markdown | md | mdown | mediawiki | mkdn | org | pod | rdoc | rst | rtf | textile | txt | wiki) f="${f%.*}" ;;
    esac
  fi
  case "$f" in
    about | authors | changelog | changes | history | news | notes | notice | readme | todo) return 0 ;;
  esac
  return 1
}

@test "the rendered formula installs docs/, RELEASES/ and RELEASES.md into the keg after devbin's publish, and then the launcher (0254)" {
  # Homebrew puts the README in the keg, and none of the guides it links: the
  # install names them, after the publish, which refuses a tree that is not
  # clean and would refuse one they had been moved out of. The install's code
  # whole and in order, its comments left out: the one compare of it.
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb" block
  formula_checkout
  run formula render v0.0.10 "$out"
  assert_success
  block="$(awk '/^  def install$/ { inside = 1; next } inside && /^  end$/ { exit } inside && !/^[[:space:]]*#/ { print }' "$out")" ||
    fail "could not read $out"
  [ "$block" = '    system "bin/devbin", "install", "--prefix", libexec, "--managed-by", "brew"
    prefix.install "docs", "RELEASES", "RELEASES.md"
    if OS.mac?
      (bin/"devbin").write_env_script libexec/"bin/devbin", PATH: "#{formula_opt_bin("bash")}:$PATH"
    else
      bin.install_symlink libexec/"bin/devbin"
    end' ] || fail "the install is not the publish, the guides beside the README, then the launcher:
$block"
}

@test "every relative link in devbin's README names a file the keg holds: one Homebrew installs as a metafile, or one under a name the rendered formula installs beside it, which devbin ships (0254)" {
  # The keg's README linked docs/ and RELEASES.md, and the keg held neither.
  # Without brew: the links read out of the README, and the keg's contents
  # read from the rendered formula and Homebrew's metafile rule. Which
  # prefix.install lines run, and that they run after the publish, is the
  # whole-block arm's above; this arm reads the names those lines give. The
  # formula installs from a tag's checkout, so a name tests/shipped.paths
  # leaves out would be missing from the public tree a formula fetches.
  local out="$DEVBIN_TEST_TMPDIR/devbin.rb" names links target top n broken=""
  formula_checkout
  run formula render v0.0.10 "$out"
  assert_success
  names="$(formula_keg_names "$out")" || fail "could not read the names the formula installs"
  [ -n "$names" ] || fail "the rendered formula installs nothing beside the README"
  while IFS= read -r n; do
    grep -qxF -e "$n" -e "$n/" "$DEVBIN_HOME/tests/shipped.paths" || broken="$broken $n(not shipped)"
  done <<<"$names"
  links="$(grep -oE '\]\([^)]+\)' "$DEVBIN_HOME/README.md" | sed -e 's/^](//' -e 's/)$//' -e 's/#.*//')" ||
    fail "could not read the README's links"
  while IFS= read -r target; do
    case "$target" in
      '' | *://* | mailto:*) continue ;;
    esac
    [ -e "$DEVBIN_HOME/$target" ] || broken="$broken $target(not in the tree)"
    top="${target%%/*}"
    if [ "$top" = "$target" ] && brew_metafile "$DEVBIN_HOME/$target"; then
      continue
    fi
    grep -qxF -- "$top" <<<"$names" || broken="$broken $target"
  done <<<"$links"
  [ -z "$broken" ] || fail "README links the keg would not hold, or names it installs that devbin does not ship:$broken
the formula installs: $names"
}

@test "devbin declares the built-in in source mode, and no command of its own shadows it (0227)" {
  # The retired command's render of v0.1.14 and the built-in's are the same
  # bytes (measured at the build, 0227's resolution); this holds the
  # declaration that makes devbin's own render the built-in's.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg_load "$DEVBIN_HOME/bin/.devbin/config.yaml" >/dev/null
  [ "$(cfg_formula_get mode)" = source ] || fail "devbin's formula.mode is '$(cfg_formula_get mode)'"
  [ "$(cfg_get commands.formula.enabled)" = true ] || fail "devbin does not enable the built-in formula"
  assert_file_not_exists "$DEVBIN_HOME/bin/.devbin/cmd/formula"
  assert_file_not_exists "$DEVBIN_HOME/bin/.devbin/help/formula.md"
}

@test "render refuses a lightweight tag, and writes nothing (0195)" {
  formula_checkout
  run formula render light "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "'light' is a lightweight tag"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "render refuses a tag the checkout does not have, and writes nothing (0195)" {
  formula_checkout
  run formula render v9.9.9 "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "no tag 'v9.9.9'"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

# --- under release.publish.url (0240) ----------------------------------------

# fx_publishes -- $FX declares release.publish.url, the bare repository $PUB
# standing in for the public one, which brew fetches and whose tag names the
# release's snapshot, a commit $FX does not hold.
fx_publishes() {
  PUB="$DEVBIN_TEST_TMPDIR/public.git"
  git init -q --bare -b main "$PUB"
  printf 'release:\n  snapshot:\n    list: VERSION\n    author: "Snap Shot <snap@example.com>"\n  publish:\n    url: %s\n' "$PUB" \
    >>"$FX/bin/.devbin/config.yaml"
}

@test "under release.publish.url render takes the revision from the public repository's tag, which names the snapshot, never this checkout's commit (0240)" {
  local snap here out="$DEVBIN_TEST_TMPDIR/devbin.rb" s="$DEVBIN_TEST_TMPDIR/snapshot"
  formula_checkout
  fx_publishes
  git init -q -b main "$s"
  git -C "$s" -c user.name=s -c user.email=s@s commit -q --allow-empty -m "devbin 0.0.10"
  snap="$(git -C "$s" rev-parse HEAD)"
  git -C "$s" push -q "$PUB" "$snap:refs/tags/v0.0.10"
  here="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  [ "$snap" != "$here" ] || fail "the fixture's public tag names the checkout's own commit"
  run formula render v0.0.10 "$out"
  assert_success
  assert_output_contains "devbin v0.0.10 at $snap"
  assert_file_contains "$out" "revision: \"$snap\""
  refute_file_contains "$out" "$here"
}

@test "under release.publish.url render refuses a tag the public repository does not carry yet, and writes nothing (0240)" {
  formula_checkout
  fx_publishes
  run formula render v0.0.10 "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "carries no tag v0.0.10"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "under release.publish.url an annotated public tag gives the commit it names, never the tag object, as the revision (0240)" {
  local snap obj out="$DEVBIN_TEST_TMPDIR/devbin.rb" s="$DEVBIN_TEST_TMPDIR/snapshot"
  formula_checkout
  fx_publishes
  git init -q -b main "$s"
  git -C "$s" -c user.name=s -c user.email=s@s commit -q --allow-empty -m "devbin 0.0.10"
  git -C "$s" -c user.name=s -c user.email=s@s tag -a -m v0.0.10 v0.0.10
  snap="$(git -C "$s" rev-parse HEAD)"
  obj="$(git -C "$s" rev-parse refs/tags/v0.0.10)"
  [ "$obj" != "$snap" ] || fail "the fixture's tag is not annotated"
  git -C "$s" push -q "$PUB" refs/tags/v0.0.10
  run formula render v0.0.10 "$out"
  assert_success
  assert_file_contains "$out" "revision: \"$snap\""
  refute_file_contains "$out" "$obj"
}

@test "devbin's template fetches the public repository over https, as anyone's brew can (0240)" {
  local t="$DEVBIN_HOME/packaging/homebrew/devbin.rb"
  assert_file_contains "$t" 'url "https://github.com/matthewsinclair/devbin.git",'
  refute_file_contains "$t" 'ssh://'
}

@test "render refuses a template without exactly one of each placeholder, naming the counts, and writes nothing (0195)" {
  formula_checkout
  printf '# a second @@TAG@@\n' >>"$FX/packaging/homebrew/devbin.rb"
  run formula render v0.0.10 "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "holds 2 tag placeholder(s) and 1 revision placeholder(s)"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "render refuses a placeholder it does not fill, by name, and writes nothing (0227)" {
  formula_checkout
  printf '# @@TAGG@@\n' >>"$FX/packaging/homebrew/devbin.rb"
  run formula render v0.0.10 "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "@@TAGG@@ is no placeholder source mode fills"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "render refuses a tag holding a character a release tag never does, since brew evaluates the string it lands in (0195)" {
  formula_checkout
  git -C "$FX" -c user.name=t -c user.email=t@t tag -a -m odd 'v0.0.1#{x}'
  run formula render 'v0.0.1#{x}' "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "holds a character a release tag never does"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "source mode refuses a setting it reads nowhere, rather than ignoring it (0227)" {
  formula_checkout
  printf 'formula:\n  assets:\n    - x\n' >>"$FX/bin/.devbin/config.yaml"
  run formula render v0.0.10 "$DEVBIN_TEST_TMPDIR/devbin.rb"
  assert_failure
  assert_output_contains "formula.assets is declared, and formula.mode is source, which reads it nowhere"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/devbin.rb"
}

@test "publish names the tap, and once the person says yes pushes the newest release by version, leaving this checkout and its TMPDIR as they were (0195, 0227)" {
  local commit head seed
  formula_checkout
  formula_tap
  seed="$(git -C "$TAP" rev-parse main)"
  commit="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  head="$(git -C "$FX" rev-parse HEAD)"
  formula_tty y publish --tap "$TAP"
  assert_success
  assert_output_contains "devbin v0.0.10 at $commit is ready to push to the tap at $TAP"
  assert_output_contains "published devbin v0.0.10 at $commit"
  run git -C "$TAP" show main:Formula/devbin.rb
  assert_success
  assert_output_contains 'tag:      "v0.0.10",'
  assert_output_contains "revision: \"$commit\""
  [ "$(git -C "$TAP" log -1 --format=%s main)" = "devbin 0.0.10" ] ||
    fail "the tap's commit is not 'devbin 0.0.10': $(git -C "$TAP" log -1 --format=%s main)"
  [ "$(git -C "$TAP" rev-parse main^)" = "$seed" ] ||
    fail "the tap's main does not hold exactly the seed and the formula"
  [ "$(git -C "$FX" rev-parse HEAD)" = "$head" ] || fail "publish moved the checkout's HEAD"
  [ -z "$(git -C "$FX" status --porcelain)" ] || fail "publish changed the checkout: $(git -C "$FX" status --porcelain)"
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

@test "publish with nobody to ask names the tap, pushes nothing, and leaves its TMPDIR empty (0227)" {
  local before
  formula_checkout
  formula_tap
  before="$(git -C "$TAP" rev-parse main)"
  run formula publish --tap "$TAP"
  assert_failure
  assert_output_contains "is ready to push to the tap at $TAP"
  assert_output_contains "nobody to ask: no terminal, so nothing was published"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "an unasked publish moved the tap's main"
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

@test "publish takes the cut's yes when DEVBIN_RELEASE_CONFIRMED names the tag it publishes, and says so (0227)" {
  local commit
  formula_checkout
  formula_tap
  commit="$(git -C "$FX" rev-parse 'v0.0.10^{commit}')"
  DEVBIN_RELEASE_CONFIRMED=v0.0.10 run formula publish --tap "$TAP"
  assert_success
  assert_output_contains "formula: confirmed at the cut of v0.0.10, so it is pushed without a second question"
  assert_output_contains "published devbin v0.0.10 at $commit"
  [ "$(git -C "$TAP" log -1 --format=%s main)" = "devbin 0.0.10" ] ||
    fail "the tap's commit is not 'devbin 0.0.10': $(git -C "$TAP" log -1 --format=%s main)"
}

@test "publish ignores a DEVBIN_RELEASE_CONFIRMED naming another tag, and asks (0227)" {
  local before
  formula_checkout
  formula_tap
  before="$(git -C "$TAP" rev-parse main)"
  DEVBIN_RELEASE_CONFIRMED=v0.0.9 run formula publish --tap "$TAP"
  assert_failure
  refute_output_contains "confirmed at the cut"
  assert_output_contains "nobody to ask: no terminal, so nothing was published"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "publish took another tag's yes"
}

@test "publish declined at the prompt pushes nothing (0227)" {
  local before
  formula_checkout
  formula_tap
  before="$(git -C "$TAP" rev-parse main)"
  formula_tty n publish --tap "$TAP"
  assert_failure
  assert_output_contains "declined at the prompt, so nothing was published"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "a declined publish moved the tap's main"
}

@test "a second publish finds the tap carrying the release already, and pushes nothing and asks nobody (0195, 0227)" {
  local before
  formula_checkout
  formula_tap
  formula_tty y publish --tap "$TAP"
  assert_success
  before="$(git -C "$TAP" rev-parse main)"
  run formula publish --tap "$TAP"
  assert_success
  assert_output_contains "already carries devbin v0.0.10"
  refute_output_contains "ready to push"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "the second publish moved the tap's main"
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

@test "publish refuses when no tag names a release, and pushes nothing (0195)" {
  local before
  formula_checkout
  formula_tap
  git -C "$FX" tag -d v0.0.10 v0.0.9 >/dev/null
  before="$(git -C "$TAP" rev-parse main)"
  run formula publish --tap "$TAP"
  assert_failure
  assert_output_contains "no tag matches the release tag template 'v{version}'"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "a refused publish moved the tap's main"
}

@test "publish refuses a template with changes no commit holds, and pushes nothing (0195)" {
  local before
  formula_checkout
  formula_tap
  printf '# not committed\n' >>"$FX/packaging/homebrew/devbin.rb"
  before="$(git -C "$TAP" rev-parse main)"
  run formula publish --tap "$TAP"
  assert_failure
  assert_output_contains "has changes no commit holds"
  [ "$(git -C "$TAP" rev-parse main)" = "$before" ] || fail "a refused publish moved the tap's main"
}

@test "publish refuses a tap it cannot clone, says nothing was published, and leaves its TMPDIR empty (0195)" {
  formula_checkout
  run formula publish --tap "$DEVBIN_TEST_TMPDIR/no-such-tap.git"
  assert_failure
  assert_output_contains "cannot clone the tap from $DEVBIN_TEST_TMPDIR/no-such-tap.git"
  assert_output_contains "so nothing was published"
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

@test "formula with no verb prints its usage and exits 1, and refuses a verb or an argument it does not take (0195)" {
  formula_checkout
  run formula
  assert_exit_code 1
  assert_output_contains "usage: bin/devbin formula render <tag> <out>"
  run formula bump
  assert_failure
  assert_output_contains "formula has no verb 'bump'"
  run formula render v0.0.10
  assert_failure
  assert_output_contains "usage: bin/devbin formula render <tag> <out>"
  run formula publish --force
  assert_failure
  assert_output_contains "publish takes --tap <url> and nothing else, not '--force'"
  run formula publish --tap
  assert_failure
  assert_output_contains "--tap needs the tap's git url"
}

# --- assets mode -------------------------------------------------------------

@test "assets render fills the version and each asset's sha256 by its exact name from the release's sums, and the cask beside it, each under the render's header (0227, 0257)" {
  local commit out="$DEVBIN_TEST_TMPDIR/tool.rb" cask="$DEVBIN_TEST_TMPDIR/tool-app.rb"
  assets_checkout
  commit="$(git -C "$FX" rev-parse 'v1.2.4^{commit}')"
  run formula render v1.2.4 "$out" "$cask"
  assert_success
  assert_output_contains "wrote $out, tool v1.2.4 at $commit"
  assert_output_contains "wrote the cask to $cask"
  # Each opens with the render's header, naming its own template, over the
  # template's first line: these templates have no header of their own (0257).
  [[ "$(cat "$out")" == "$(want_header packaging/homebrew/tool.rb v1.2.4 "$commit")"$'\n''class Tool < Formula'$'\n'* ]] ||
    fail "the rendered formula does not open with the render's header over the template: $(cat "$out")"
  [[ "$(cat "$cask")" == "$(want_header packaging/homebrew/tool-app.rb v1.2.4 "$commit")"$'\n''cask "tool-app" do'$'\n'* ]] ||
    fail "the rendered cask does not open with the render's header over the template: $(cat "$cask")"
  assert_file_contains "$DEVBIN_TEST_TMPDIR/gh.calls" "gh release download --repo t/tool-dist v1.2.4 --pattern SHA256SUMS --dir"
  assert_file_contains "$out" '  url "https://example.invalid/download/v1.2.4/tool-aarch64-apple-darwin"'
  assert_file_contains "$out" "  sha256 \"$SHA_MAC\""
  assert_file_contains "$out" '      url "https://example.invalid/download/v1.2.4/tool-1.2.4-aarch64-linux.tar.gz"'
  assert_file_contains "$out" "      sha256 \"$SHA_LIN\""
  assert_file_contains "$out" '    chmod 0755, libexec/"bin/tool"'
  assert_file_contains "$out" '    lines = ["# tool: tool", "# version: 1.2.4", "# source_commit: '"$commit"'", "# managed_by: brew"]'
  assert_file_contains "$out" '    (libexec/".tool-install").write('
  assert_file_contains "$out" '    bin.install_symlink libexec/"bin/tool"'
  assert_file_contains "$out" '    "tool use names the tree this machine runs"'
  assert_file_contains "$cask" '  version "1.2.4"'
  assert_file_contains "$cask" "  sha256 \"$SHA_PKG\""
  refute_file_contains "$out" "$SHA_DECOY"
  refute_file_contains "$cask" "$SHA_DECOY"
  refute_file_contains "$out" '@@'
  refute_file_contains "$cask" '@@'
  if command -v ruby >/dev/null 2>&1; then
    ruby -c "$out" >/dev/null || fail "the rendered formula is not Ruby: $(ruby -c "$out" 2>&1)"
    ruby -c "$cask" >/dev/null || fail "the rendered cask is not Ruby: $(ruby -c "$cask" 2>&1)"
  fi
}

@test "assets render reads --sums in place of the release's, and asks gh nothing (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb"
  assets_checkout
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/tool-app.rb" --sums "$SUMS"
  assert_success
  assert_file_contains "$out" "  sha256 \"$SHA_MAC\""
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/gh.calls"
}

@test "the generated install body sets 0755, writes T3's manifest over libexec, each file at its own sha256 and itself left out, and links the executable (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb" keg="$DEVBIN_TEST_TMPDIR/keg" commit
  command -v ruby >/dev/null 2>&1 || skip "ruby is not on this runner: the generated install body is NOT run"
  assets_checkout
  commit="$(git -C "$FX" rev-parse 'v1.2.4^{commit}')"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/tool-app.rb" --sums "$SUMS"
  assert_success
  run ruby_keg "$out"
  assert_success
  [ "$(mode_of "$keg/libexec/bin/tool")" = -rwxr-xr-x ] || fail "bin/tool is mode $(mode_of "$keg/libexec/bin/tool")"
  [ -L "$keg/bin/tool" ] || fail "no link at bin/tool"
  run sed -n '1,4p' "$keg/libexec/.tool-install"
  assert_output "# tool: tool
# version: 1.2.4
# source_commit: $commit
# managed_by: brew"
  # THE BODY IS EVERY FILE UNDER libexec BUT THE MANIFEST, each at the sha256
  # lib/helpers takes of it, in T3's `<sha256>  <path>` form: here, bin/tool.
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  [ "$(grep -v '^#' "$keg/libexec/.tool-install")" = "$(cd "$keg/libexec" && sha256_files bin/tool)" ] ||
    fail "the manifest's body is not bin/tool at its sha256:
$(cat "$keg/libexec/.tool-install")"
}

@test "assets render refuses an asset the sums file does not name, one it names twice, and a line in another shape, writing nothing (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb"
  assets_checkout
  grep -v 'Tool-1.2.4.pkg$' "$SUMS" >"$SUMS.lack"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS.lack"
  assert_failure
  assert_output_contains "the release's sums file names no asset Tool-1.2.4.pkg"
  cp "$SUMS" "$SUMS.twice"
  printf '%s  %s\n' "$SHA_DECOY" Tool-1.2.4.pkg >>"$SUMS.twice"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS.twice"
  assert_failure
  assert_output_contains "it names Tool-1.2.4.pkg twice"
  cp "$SUMS" "$SUMS.shape"
  printf 'not a sum line\n' >>"$SUMS.shape"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS.shape"
  assert_failure
  assert_output_contains "a line of it is not '<sha256>  <name>': not a sum line"
  assert_file_not_exists "$out"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/c.rb"
}

@test "assets render refuses a formula without a top-level url, and one with a version line beside a url naming the version, writing nothing (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb" t
  assets_checkout
  t="$FX/packaging/homebrew/tool.rb"
  cp "$t" "$t.orig"
  sed 's|^  url "https://example.invalid/download/v@@VERSION@@/tool-aarch64-apple-darwin"|  # no url|' "$t.orig" >"$t"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "has no url at top level"
  awk '{ print } /^  license "MIT"$/ { print "  version \"@@VERSION@@\"" }' "$t.orig" >"$t"
  grep -q '^  version "@@VERSION@@"' "$t" || fail "the version line was not planted"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "has a version line, and its top-level url names the version"
  assert_file_not_exists "$out"
}

@test "assets render refuses a sha256 placeholder for no listed asset, an asset placed twice, and both install bodies, writing nothing (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb" t
  assets_checkout
  t="$FX/packaging/homebrew/tool.rb"
  cp "$t" "$t.orig"
  printf '# @@SHA256:tool-unknown@@\n' >>"$t"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "holds @@SHA256:tool-unknown@@, and formula.assets names no asset tool-unknown"
  cp "$t.orig" "$t"
  printf '# @@SHA256:Tool-{version}.pkg@@\n' >>"$t"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "the templates hold its @@SHA256:Tool-{version}.pkg@@ 2 time(s)"
  cp "$t.orig" "$t"
  printf '# @@INSTALL@@\n' >>"$t"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "holds 1 @@INSTALL@@ and 1 @@FINISH@@"
  assert_file_not_exists "$out"
}

@test "assets render refuses a placeholder it does not fill, by name, writing nothing (0227)" {
  local out="$DEVBIN_TEST_TMPDIR/tool.rb"
  assets_checkout
  printf '# @@VERSOIN@@\n' >>"$FX/packaging/homebrew/tool.rb"
  run formula render v1.2.4 "$out" "$DEVBIN_TEST_TMPDIR/c.rb" --sums "$SUMS"
  assert_failure
  assert_output_contains "@@VERSOIN@@ is no placeholder assets mode fills"
  assert_file_not_exists "$out"
}

@test "assets publish pushes the formula and the cask to the tap in one commit, once the person says yes (0227)" {
  local seed
  assets_checkout
  formula_tap
  seed="$(git -C "$TAP" rev-parse main)"
  formula_tty y publish --tap "$TAP"
  assert_success
  assert_output_contains "tool v1.2.4"
  assert_output_contains "(Formula/tool.rb Casks/tool-app.rb)"
  [ "$(git -C "$TAP" rev-parse main^)" = "$seed" ] || fail "the tap's main is not one commit on the seed"
  [ "$(git -C "$TAP" log -1 --format=%s main)" = "tool 1.2.4" ] ||
    fail "the tap's commit is not 'tool 1.2.4': $(git -C "$TAP" log -1 --format=%s main)"
  run git -C "$TAP" show main:Casks/tool-app.rb
  assert_success
  assert_output_contains "  sha256 \"$SHA_PKG\""
  run git -C "$TAP" show main:Formula/tool.rb
  assert_success
  assert_output_contains "  sha256 \"$SHA_MAC\""
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

# AT-3.9
@test "assets publish takes the cut's yes when DEVBIN_RELEASE_CONFIRMED names the tag: the formula and the cask go to the tap in one commit, with no question, and it says so (ST0011 WP08)" {
  local seed
  assets_checkout
  formula_tap
  seed="$(git -C "$TAP" rev-parse main)"
  DEVBIN_RELEASE_CONFIRMED=v1.2.4 run formula publish --tap "$TAP"
  assert_success
  assert_output_contains "formula: confirmed at the cut of v1.2.4, so it is pushed without a second question"
  assert_output_contains "(Formula/tool.rb Casks/tool-app.rb)"
  [ "$(git -C "$TAP" rev-parse main^)" = "$seed" ] || fail "the tap's main is not one commit on the seed"
  [ "$(git -C "$TAP" log -1 --format=%s main)" = "tool 1.2.4" ] ||
    fail "the tap's commit is not 'tool 1.2.4': $(git -C "$TAP" log -1 --format=%s main)"
  run git -C "$TAP" show main:Casks/tool-app.rb
  assert_success
  assert_output_contains "  sha256 \"$SHA_PKG\""
  run git -C "$TAP" show main:Formula/tool.rb
  assert_success
  assert_output_contains "  sha256 \"$SHA_MAC\""
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

# --- the release repository is the cut's (0296) ------------------------------

# assets_remotes -- $FX as assets_checkout makes it, its config declaring no
# release.repo and no formula.repo, and two remotes naming two repositories:
# origin, at oo/tool, and up, at ff/tool, which release.remotes declares first.
# The cut and ci-state read ff/tool; so must the formula. No url is fetched.
assets_remotes() {
  assets_checkout
  printf '%s\n' 'project:' '  name: tool' 'release:' '  remotes:' '    - up' 'formula:' '  mode: assets' \
    '  cask: packaging/homebrew/tool-app.rb' '  assets:' '    - tool-aarch64-apple-darwin' \
    '    - "tool-{version}-aarch64-linux.tar.gz"' '    - "Tool-{version}.pkg"' '  bin:' '    - bin/tool' \
    >"$FX/bin/.devbin/config.yaml"
  git -C "$FX" remote add origin https://github.com/oo/tool.git
  git -C "$FX" remote add up https://github.com/ff/tool.git
}

@test "with remotes: declared and no release.repo or formula.repo, assets render reads the sums from the first declared remote's repository, never origin's (0296, ST0011 WP08)" {
  assets_remotes
  run formula render v1.2.4 "$DEVBIN_TEST_TMPDIR/tool.rb" "$DEVBIN_TEST_TMPDIR/tool-app.rb"
  assert_success
  assert_file_contains "$DEVBIN_TEST_TMPDIR/gh.calls" "gh release download --repo ff/tool v1.2.4 --pattern SHA256SUMS --dir"
  refute_file_contains "$DEVBIN_TEST_TMPDIR/gh.calls" "oo/tool"
}

@test "with remotes: declared and no release.repo or formula.tap, publish pushes to homebrew-<name> under the first declared remote's owner, never origin's (0296, ST0011 WP08)" {
  local seed
  assets_remotes
  formula_tap
  seed="$(git -C "$TAP" rev-parse main)"
  # The default tap's url is sent to the bare tap by insteadOf; any other url
  # reaches ssh, which GIT_SSH_COMMAND=false refuses at once.
  printf '[user]\n\tname = t\n\temail = t@t\n[url "%s"]\n\tinsteadOf = ssh://git@github.com/ff/homebrew-tool.git\n' \
    "$TAP" >"$DEVBIN_TEST_TMPDIR/tap.gitconfig"
  GIT_CONFIG_GLOBAL="$DEVBIN_TEST_TMPDIR/tap.gitconfig" GIT_SSH_COMMAND=false DEVBIN_RELEASE_CONFIRMED=v1.2.4 \
    run formula publish
  assert_success
  assert_output_contains "is ready to push to the tap at ssh://git@github.com/ff/homebrew-tool.git"
  refute_output_contains "github.com/oo/"
  [ "$(git -C "$TAP" rev-parse main^)" = "$seed" ] || fail "the tap's main is not one commit on the seed"
  assert_file_contains "$DEVBIN_TEST_TMPDIR/gh.calls" "gh release download --repo ff/tool v1.2.4"
  [ -z "$(tmp_left)" ] || fail "publish left its clone behind: $(tmp_left)"
}

@test "cfg_formula_name is formula.name where it is declared, and project.name where it is not (0227)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg_load_string <<'YAML'
project:
  name: demo
YAML
  [ "$(cfg_formula_name)" = demo ] || fail "undeclared, the name is '$(cfg_formula_name)'"
  cfg_load_string <<'YAML'
project:
  name: demo
formula:
  name: demo-cli
YAML
  [ "$(cfg_formula_name)" = demo-cli ] || fail "declared, the name is '$(cfg_formula_name)'"
}

@test "a formula.mode that is no mode is refused by config validation (0227)" {
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  # shellcheck source=lib/config
  . "$DEVBIN_LIB_DIR/config"
  cfg_load_string <<'YAML'
project:
  name: demo
formula:
  mode: binary
YAML
  run cfg_validate
  assert_failure
  assert_output_contains 'formula.mode: "binary" is not a formula mode -- use source or assets'
}
