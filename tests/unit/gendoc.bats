#!/usr/bin/env bats
# gendoc.bats - generated_doc_write and its refusals (issue 0028)
#
# Devbin owns the DISCIPLINE of writing a generated document safely; every
# project keeps its own producer. So the whole of this file is about what the
# helper REFUSES, and each refusal has a measured incident behind it in a
# consumer project.
#
# A guard that has never fired is a guard nobody has tested, so every contract
# here is proven by firing it -- and the accepting path is proven separately, or
# a helper that refuses everything would pass the lot.

load "../lib/test_helper"

setup() {
  devbin_setup
  # shellcheck source=lib/helpers
  . "$DEVBIN_LIB_DIR/helpers"
  BEGIN_M="GEN-BEGIN"
  END_M="GEN-END"
  DOC="$DEVBIN_TEST_TMPDIR/runbook.md"
  seed_doc
}
teardown() { devbin_teardown; }

# A hand-authored document with a generated region in the middle. The prose
# either side is the judgement a probe can never produce, and R4 is about it.
seed_doc() {
  cat >"$DOC" <<EOF
# Runbook

Hand-authored decision: this estate stays on the pooler and changing that needs
the owner's say-so.

$BEGIN_M
stale generated content
$END_M

Hand-authored warning: DROP OWNED will take the schema with it.
EOF
}

producer() { printf 'cluster: abc123\nusers: 4\n'; }

# ============================================================================
# THE ACCEPTING PATH -- proven first, or every refusal below is vacuous
# ============================================================================

@test "CONTROL: a clean producer replaces the generated region and returns 0" {
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_file_contains "$DOC" "cluster: abc123"
  refute_file_contains "$DOC" "stale generated content"
}

# ============================================================================
# R4 -- THE HAND-AUTHORED HALF SURVIVES
# ============================================================================

@test "R4: prose on BOTH sides of the markers survives a regeneration" {
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_file_contains "$DOC" "stays on the pooler and changing that needs"
  assert_file_contains "$DOC" "DROP OWNED will take the schema with it"
  # Both markers survive too, or the NEXT regeneration has nowhere to write.
  assert_file_contains "$DOC" "$BEGIN_M"
  assert_file_contains "$DOC" "$END_M"
}

@test "R4: a target with no markers is REFUSED, not appended to" {
  printf 'no markers here\n' >"$DOC"
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_failure
  assert_output_contains "exactly once"
  assert_file_contains "$DOC" "no markers here"
  refute_file_contains "$DOC" "cluster: abc123"
}

@test "R4: a DUPLICATED marker is refused rather than guessed at" {
  # Two begins is ambiguous about which region is generated, and guessing is how
  # a generator eats the wrong half of a file.
  printf '%s\na\n%s\nb\n%s\n' "$BEGIN_M" "$BEGIN_M" "$END_M" >"$DOC"
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_failure
  assert_output_contains "begin=2"
}

@test "R4: an end marker ABOVE the begin marker is refused" {
  printf '%s\nmiddle\n%s\n' "$END_M" "$BEGIN_M" >"$DOC"
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_failure
  assert_output_contains "before or at the begin marker"
}

@test "R4: a target that does not exist is refused rather than created" {
  run generated_doc_write --target "$DEVBIN_TEST_TMPDIR/absent.md" \
    --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_failure
  assert_output_contains "does not exist"
  assert_file_not_exists "$DEVBIN_TEST_TMPDIR/absent.md"
}

# ============================================================================
# R2 -- NEVER WRITE FROM A FAILED MEASUREMENT
# ============================================================================

@test "R2: a producer that exits non-zero leaves the target untouched" {
  failing() { printf 'ERROR:  permission denied for schema public\n'; return 1; }
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- failing
  assert_failure
  assert_output_contains "exited non-zero"
  # The incident this is for: the ERROR TEXT itself got captured into a runbook
  # and then counted off, which is a refuted inference in the format of a
  # measurement.
  refute_file_contains "$DOC" "permission denied"
  assert_file_contains "$DOC" "stale generated content"
}

@test "R2: a producer that writes NOTHING leaves the target untouched" {
  silent() { :; }
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- silent
  assert_failure
  assert_output_contains "wrote nothing"
  assert_file_contains "$DOC" "stale generated content"
}

# ============================================================================
# R1 -- NEVER INLINE A SECRET
# ============================================================================

@test "R1: a denied variable whose VALUE appears in the block refuses the write" {
  export PGPASSWORD="s3cr3t-value"
  leaky() { printf 'url: postgresql://u:s3cr3t-value@host/db\n'; }
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --deny-env PGPASSWORD -- leaky
  assert_failure
  assert_output_contains "PGPASSWORD"
  # THE ADVICE IS PART OF THE REFUSAL (issue 0187): env indirection, naming the
  # variable, with no example URI that a secret scanner reads as a credential,
  # and never the value it refused.
  assert_output_contains "Use env indirection in the producer's output -- write the literal text \$PGPASSWORD where the value would go"
  refute_output_contains "://"
  refute_output_contains "s3cr3t-value"
  assert_file_contains "$DOC" "stale generated content"
}

@test "R1: env INDIRECTION passes -- the point is to permit the safe form" {
  export PGPASSWORD="s3cr3t-value"
  safe() { printf 'url: postgresql://u:$PGPASSWORD@host/db\n'; }
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --deny-env PGPASSWORD -- safe
  assert_file_contains "$DOC" 'postgresql://u:$PGPASSWORD@host/db'
}

@test "R1: an UNSET denied variable is refused AS UNSET, never reported as a leak" {
  # THE PROMISED RED-CHECK, and the reason it is worth having. An unset variable
  # makes the naive check compare against the empty string, which every block
  # contains -- so the helper refuses, correctly, and says the secret leaked.
  # It did not. A wrong recorded reason is worse than none: this one sends the
  # reader hunting a credential leak that never happened, in a file that is
  # fine. The refusal must name the real fault.
  unset PGPASSWORD
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --deny-env PGPASSWORD -- producer
  assert_failure
  assert_output_contains "unset or empty"
  refute_output_contains "appears in the generated block"
  assert_file_contains "$DOC" "stale generated content"
}

@test "R1: an EMPTY denied variable is refused the same way" {
  # The other half of the same hole: set-but-empty must not silently disable a
  # secret guard either.
  export PGPASSWORD=""
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --deny-env PGPASSWORD -- producer
  assert_failure
  assert_output_contains "unset or empty"
}

@test "R1: a secret containing glob characters is matched LITERALLY" {
  # A password of `a*b` must not be read as a pattern. The block below is the
  # discriminating input and was chosen deliberately: `axxb` is matched by the
  # GLOB `*a*b*` and not by the literal string `a*b`, so an unquoted comparison
  # refuses this innocent block and a correct one writes it.
  #
  # The first version of this test used a block containing no `a` at all, which
  # both the glob and the literal decline to match -- it passed either way and
  # so proved nothing. Ask what else would make a test green.
  export PGPASSWORD='a*b'
  clean() { printf 'cluster: axxb\n'; }
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --deny-env PGPASSWORD -- clean
  assert_file_contains "$DOC" "cluster: axxb"
}

# ============================================================================
# R5 -- VALIDATE THE ARTEFACT, NOT THE EXIT PATH
# ============================================================================

@test "R5: a block shorter than the producer DECLARED is refused" {
  # A producer exiting 0 says it ran. It does not say it produced the document.
  local declared=10
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --expect-lines "$declared" -- producer
  assert_failure
  assert_output_contains "fewer than the $declared declared"
  assert_file_contains "$DOC" "stale generated content"
}

@test "R5: a block missing a declared required string is refused" {
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --expect-contains "extensions:" -- producer
  assert_failure
  assert_output_contains "extensions:"
  assert_file_contains "$DOC" "stale generated content"
}

@test "R5: declared expectations that ARE met still write" {
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" \
    --expect-lines 2 --expect-contains "cluster:" -- producer
  assert_file_contains "$DOC" "cluster: abc123"
}

# ============================================================================
# R3 -- ATOMIC REPLACE
# ============================================================================

# The temp is created BESIDE the target rather than in TMPDIR, because rename is
# atomic only within a filesystem. That choice is right and it puts droppings in
# the user's repository if a path forgets to clean up.
#
# WHAT IS AND IS NOT COVERED HERE, stated because the gap is invisible
# otherwise. The tests below prove the SUCCESS path and an EARLY-REFUSAL
# path leave nothing behind. The cleanup after the temp exists is replace_file's
# (lib/helpers), and helpers.bats holds it for a write that fails; a failed
# RENAME still needs a filesystem fault that cannot be staged portably, and is
# not held anywhere. The first version of the refusal test used a failing
# producer and looked like it covered cleanup; it does not, because the producer
# check returns before the temp is ever created, so it passed no matter what the
# cleanup did. A test that cannot fail is worse than an absent one, because the
# absent one does not claim the coverage.

@test "R3: an early refusal leaves no temporary file beside the target" {
  failing() { return 1; }
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- failing
  assert_failure
  run bash -c "ls '$DEVBIN_TEST_TMPDIR'/runbook.md.* 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

@test "R3: a successful write leaves no temporary file either" {
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  run bash -c "ls '$DEVBIN_TEST_TMPDIR'/runbook.md.* 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

@test "R3: an unwritable directory is refused, and the target survives" {
  # This one DOES reach the temp-creation branch, which is the only post-marker
  # R3 path that can be staged without a fault injector.
  if [ "$(id -u)" = 0 ]; then
    skip "root bypasses directory permissions, so this proves nothing as root"
  fi
  local dir="$DEVBIN_TEST_TMPDIR/ro"
  mkdir -p "$dir"
  cp "$DOC" "$dir/runbook.md"
  chmod a-w "$dir"
  run generated_doc_write --target "$dir/runbook.md" \
    --begin "$BEGIN_M" --end "$END_M" -- producer
  chmod u+w "$dir"
  assert_failure
  assert_output_contains "could not create a temporary file"
  assert_file_contains "$dir/runbook.md" "stale generated content"
}

# ============================================================================
# USAGE ERRORS DIE -- they are the caller's bug, not a fact about the world
# ============================================================================

@test "a missing marker option is a usage error, not a refusal" {
  run generated_doc_write --target "$DOC" --end "$END_M" -- producer
  assert_failure
  assert_output_contains "--begin marker is required"
}

@test "the END marker is required too, so neither side is silently defaulted" {
  # The twin of the test above, and the reason both exist: a DEFAULT marker
  # would encode a comment syntax, and a framework that ships an HTML comment
  # has quietly decided its consumers write HTML. Devbin must not learn that the
  # output is Markdown, so there is no default to fall back to on either side.
  #
  # The first version of this test grepped lib/helpers for a comment sequence
  # and matched the sentence above -- an unanchored search over a file that
  # documents the thing it is searching for. Asserting the BEHAVIOUR cannot be
  # fooled by its own rationale.
  run generated_doc_write --target "$DOC" --begin "$BEGIN_M" -- producer
  assert_failure
  assert_output_contains "--end marker is required"
}

# ============================================================================
# THE REPLACE KEEPS THE DOCUMENT'S MODE (replace_file)
# ============================================================================

@test "a regeneration keeps the document's mode" {
  # mktemp creates 0600 and the rename carried it onto the runbook, so a 0644
  # document came out 0600, with nothing in git to show it. 604 is no umask's
  # new-file mode, so a writer that fell back to the umask cannot pass either.
  chmod 604 "$DOC"
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_file_contains "$DOC" "cluster: abc123"
  [ "$(mode_of "$DOC")" = "-rw----r--" ] || fail "the runbook came out $(mode_of "$DOC")"
}

@test "a regeneration through a link writes the document the link names, and the link survives" {
  # Issue 0084: before it, the rename replaced the link with a regular file and
  # the document it named kept its stale region, rc 0.
  local shared="$DEVBIN_TEST_TMPDIR/shared"
  mkdir -p "$shared"
  mv "$DOC" "$shared/runbook.md"
  chmod 604 "$shared/runbook.md"
  ln -s shared/runbook.md "$DOC"
  generated_doc_write --target "$DOC" --begin "$BEGIN_M" --end "$END_M" -- producer
  assert_symlink_exists "$DOC" shared/runbook.md
  assert_file_contains "$shared/runbook.md" "cluster: abc123"
  refute_file_contains "$shared/runbook.md" "stale generated content"
  [ "$(mode_of "$shared/runbook.md")" = "-rw----r--" ] || fail "the runbook the link names came out $(mode_of "$shared/runbook.md")"
}
