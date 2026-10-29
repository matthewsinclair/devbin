#!/usr/bin/env bats
#
# gate_critic must not report `ok` over an EMPTY DENOMINATOR.
#
# Measured: the Intent3 flip took this tree's shell critic from `2 of 6 rule(s)
# ASKED; 2 armed in total` to `0 of 0 rule(s) ASKED; 0 armed in total`, and the
# verdict line did not change by one character. Both runs printed
# `ok: no shell findings at severity >= warning across 28 file(s)` and both
# exited 0, so two commits landed through a gate that enforced nothing.
#
# The number that moved is `armed in total`, which is the LIBRARY-side count,
# not `ASKED of this run`, which is the runner's. So the rule library went
# empty rather than the runner deciding fewer rules applied -- and that is
# exactly why this gate is the right place to catch it. Whatever the cause
# upstream, a gate that armed nothing has not passed; it has abstained.
#
# THE PREDICATE IS `--format json`, NOT THE TEXT OUTPUT, and that is deliberate.
# The census line is right there in the human output and parsing it would work
# today. `.git/hooks/pre-commit.intent` already resolves INTENT_HOME by
# `sed`-ing the DISPLAY TEXT of `intent info`, and that file carries its own
# comment about what a renderer change would cost it. One instance of that
# pattern in this repository is one more than it needs.
#
set -euo pipefail

load "../lib/test_helper"

setup() {
  devbin_setup
  STUB_BIN="$DEVBIN_TEST_TMPDIR/stub-bin"
  mkdir -p "$STUB_BIN"
}

teardown() {
  devbin_teardown
}

# stub_intent <armed> -- an `intent` answering as a library with <armed> rules.
#
# It answers BOTH shapes because the gate is entitled to ask either: `--format
# json` for the decision and plain text for the human. A stub that answered only
# the shape the fix happens to use would go green against an implementation that
# had stopped asking anything at all.
#
# AND IT PARSES ITS ARGUMENTS THE WAY THE RUNNER DOES (issue 0075). The first
# version accepted anything, so when Intent 3.0.3 made `--files` take one path
# per flag the gate's call was refused by the real runner and green against
# this stub for a week. After the `critic` subcommand: one positional (the
# language), exactly one value after each `--files` and `--format`, and any
# further positional refused with rc 2 and an empty stdout, as
# `intent critic shell --files a b` answers.
stub_intent() {
  local armed="$1"
  cat >"$STUB_BIN/intent" <<EOF
#!/usr/bin/env bash
orig=("\$@")
[ "\${1:-}" = --version ] && { echo "intent 3.0.3"; exit 0; }
[ "\${1:-}" = critic ] && shift
pos=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --files | --format)
      [ \$# -ge 2 ] || { echo "error: \$1 needs a value" >&2; exit 2; }
      shift 2
      ;;
    --staged) shift ;;
    -*) echo "error: unexpected argument '\$1' found" >&2; exit 2 ;;
    *)
      pos=\$((pos + 1))
      [ "\$pos" -eq 1 ] || { echo "error: unexpected argument '\$1' found" >&2; exit 2; }
      shift
      ;;
  esac
done
for a in "\${orig[@]}"; do
  if [ "\$a" = "json" ]; then
    printf '{"armed": $armed, "asked": $armed, "census": [], "findings": [], "language": "shell", "refused": [], "total": $armed}\n'
    exit 0
  fi
done
printf 'critic: shell -- $armed of 6 rule(s) ASKED of this run; $armed armed in total.\n'
printf 'ok: no shell findings at severity >= warning across 28 file(s)\n'
exit 0
EOF
  chmod +x "$STUB_BIN/intent"
}

# The gate is normally reached through the dispatcher, which exports
# PROJECT_ROOT and DEVBIN_LIB for it. Invoking the script directly means
# supplying both -- and the first draft of this file did not, so the gate died
# on `PROJECT_ROOT: unbound variable` and TWO of the four tests passed anyway:
# one asserting failure, one asserting absence of a string. A test suite that
# is satisfied by the script never starting is not red-first, it is untested,
# and it would have gone green against any fix at all.
run_critic_gate() {
  cd "$DEVBIN_ORIGINAL_PWD" || return 1
  PROJECT_ROOT="$DEVBIN_ORIGINAL_PWD" \
    DEVBIN_LIB="$DEVBIN_LIB_DIR" \
    PATH="$STUB_BIN:$PATH" \
    run bin/.devbin/cmd/.lib/shell-gate critic
}

@test "gate_critic REFUSES when the library armed zero rules" {
  stub_intent 0
  run_critic_gate
  assert_failure
}

@test "gate_critic names the empty denominator rather than only failing" {
  stub_intent 0
  run_critic_gate
  # The count is the whole diagnosis: a reader who sees only "failed" will go
  # looking for findings that do not exist. 0018's lesson, one issue over.
  assert_output_contains "0"
  assert_output_contains "armed"
}

@test "gate_critic never prints ok over an empty denominator" {
  stub_intent 0
  run_critic_gate
  # The exact string the disarmed gate printed while passing.
  refute_output_contains "ok: no shell findings"
}

@test "gate_critic still passes when the library armed rules -- the control" {
  # Without this the suite above is satisfied by a gate that refuses everything,
  # which is not a fix, it is a different outage.
  stub_intent 2
  run_critic_gate
  assert_success
}

# ---- the v2 shape ---------------------------------------------------------
#
# v2.19.0's `--format json` emits the FINDINGS ARRAY alone (`[]`) and puts the
# census on stderr, so it carries no `armed` field at all. The gate reads its
# census line instead, and these tests exist because that fallback is a
# real branch that the v3-shaped stub above never touches. Found by running the
# fix against the frozen v2 rather than by reading it: the first version of
# this fix hard-failed a runner that arms 2 of 6 rules perfectly well.

stub_intent_v2() {
  local armed="$1"
  cat >"$STUB_BIN/intent" <<EOF
#!/usr/bin/env bash
printf 'critic: shell -- $armed of 6 rule(s) ASKED of this run; $armed armed in total.\n' >&2
for a in "\$@"; do
  if [ "\$a" = "json" ]; then printf '[]\n'; exit 0; fi
done
printf 'ok: no shell findings at severity >= warning across 28 file(s)\n'
exit 0
EOF
  chmod +x "$STUB_BIN/intent"
}

@test "gate_critic reads the v2 census when the JSON carries no armed field" {
  stub_intent_v2 2
  run_critic_gate
  assert_success
}

@test "gate_critic REFUSES a disarmed v2 too -- the fallback is not a bypass" {
  stub_intent_v2 0
  run_critic_gate
  assert_failure
  refute_output_contains "ok: no shell findings"
}

@test "gate_critic refuses a runner it cannot read a count from at all" {
  # Neither shape. The gate must not read this as a clean corpus or an empty
  # library -- those have different remedies and it knows which it is: neither.
  cat >"$STUB_BIN/intent" <<'EOF'
#!/usr/bin/env bash
printf 'some future output nobody planned for\n'
exit 0
EOF
  chmod +x "$STUB_BIN/intent"
  run_critic_gate
  assert_failure
  assert_output_contains "refusing rather than guessing"
}

# ---- the call itself (issue 0075) -----------------------------------------

@test "gate_critic gives the runner one --files per path, over a corpus of more than one file" {
  # The control above passes only if the strict stub ACCEPTS the call, and the
  # corpus is every shell file in bin, lib and tests, so it is never one path.
  stub_intent 2
  run_critic_gate
  assert_success
  refute_output_contains "unexpected argument"
}

@test "a runner that REFUSES the call is reported as a refusal, with its exit code and its words" {
  # Not as an unreadable output shape: that sentence sent the reader after the
  # toolchain for a week while the runner was saying exactly what was wrong.
  cat >"$STUB_BIN/intent" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --version "*) echo "intent 9.9.9"; exit 0 ;; esac
echo "error: unexpected argument 'nope' found" >&2
exit 2
EOF
  chmod +x "$STUB_BIN/intent"
  run_critic_gate
  assert_failure
  assert_output_contains "exited 2"
  assert_output_contains "unexpected argument 'nope' found"
}

# ---- a corpus that cannot be listed whole (issue 0139) ----------------------
#
# shell_files ran find with its errors sent to /dev/null, and head the same, so
# a directory find could not read and a file head could not open were both a
# file that is not shell: never gated, and the gate passed beside a planted
# breach it could not see. Every gate asks shell_corpus, so every gate runs.

# run_gate_in <root> <gate> -- one gate over a fixture tree rather than this one.
run_gate_in() {
  PROJECT_ROOT="$1" DEVBIN_LIB="$DEVBIN_LIB_DIR" PATH="$STUB_BIN:$PATH" \
    run "$DEVBIN_HOME/bin/.devbin/cmd/.lib/shell-gate" "$2"
}

@test "each shell gate refuses a corpus it cannot list whole, never a pass over part of it (0139, 0145)" {
  require_command shellcheck
  stub_intent 2
  local root="$DEVBIN_TEST_TMPDIR/gated" g i
  local -a st=() out=()
  mkdir -p "$root/bin" "$root/lib/locked" "$root/tests"
  printf '#!/usr/bin/env bash\necho ok\n' >"$root/bin/ok"
  printf '#!/usr/bin/env bash\nif then fi\n' >"$root/lib/locked/broken"
  # THE CONTROL: readable, the syntax gate finds the planted breach, over every
  # file the fixture holds, each of them a shell script.
  run_gate_in "$root" syntax
  assert_failure
  assert_output_contains "syntax: $(find "$root" -type f | grep -c .) file(s), 1 breach(es)"
  chmod 000 "$root/lib/locked"
  if [ -r "$root/lib/locked" ]; then
    chmod 755 "$root/lib/locked"
    skip "running with permissions that read a mode-000 directory: the unreadable case was NOT checked"
  fi
  for g in syntax lint critic; do
    run_gate_in "$root" "$g"
    st+=("$status")
    out+=("$output")
  done
  chmod 755 "$root/lib/locked"
  i=0
  for g in syntax lint critic; do
    [ "${st[$i]}" -ne 0 ] || fail "$g passed over a corpus it could not list: ${out[$i]}"
    [[ "${out[$i]}" == *"$g: could not list every file"* ]] || fail "$g did not say its corpus was partial: ${out[$i]}"
    # It stops there: a partial corpus is not an empty one, and the empty
    # corpus's guard would name the wrong cause.
    [[ "${out[$i]}" != *"examined NO files"* ]] || fail "$g went on to blame an empty corpus for a partial one: ${out[$i]}"
    assert_find_denied "lib/locked" "${out[$i]}"
    i=$((i + 1))
  done
  # AN UNREADABLE FILE is no more a file that is not shell than an unreadable
  # directory is an empty one.
  rm -rf "$root/lib/locked"
  printf '#!/usr/bin/env bash\nif then fi\n' >"$root/lib/hidden"
  chmod 000 "$root/lib/hidden"
  run_gate_in "$root" syntax
  chmod 644 "$root/lib/hidden"
  assert_failure
  assert_output_contains "cannot read lib/hidden to tell whether it is a shell file"
  assert_output_contains "syntax: could not list every file"
  # AND A DIRECTORY IT CAN LIST BUT NOT SEARCH, mode 0644 (issue 0145): macOS's
  # find passed over it at rc 0, and the gate was green over a breach beneath it.
  rm -f "$root/lib/hidden"
  mkdir -p "$root/lib/shut"
  printf '#!/usr/bin/env bash\nif then fi\n' >"$root/lib/shut/broken"
  chmod 644 "$root/lib/shut"
  if [ -x "$root/lib/shut" ]; then
    chmod 755 "$root/lib/shut"
    skip "running with permissions that search a mode-644 directory: the 0145 half was NOT checked"
  fi
  run_gate_in "$root" syntax
  chmod 755 "$root/lib/shut"
  assert_failure
  assert_output_contains "cannot search lib/shut -- nothing beneath it was looked at"
  assert_output_contains "syntax: could not list every file"
}
