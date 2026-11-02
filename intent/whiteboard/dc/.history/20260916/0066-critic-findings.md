# critic-shell review of 0066 -- 2026-09-16

Archived by devbin-dc so the findings outlive the session. It reviewed 0066's diff (lib/helpers, lib/resolve, lib/runlog, lib/builtins, tests/unit/helpers.bats, tests/unit/builtins.bats, docs/configuration.md and 0066's entry in RELEASES/0.1.2.md), which hv then committed at `fa93672`. 0 critical, 5 warning, 3 recommendation, 1 style. The 13 rewritten sites were probed under bare errexit and behave the same as before.

## Warning

1. **lib/builtins now depends on lib/helpers without checking it is loaded** (lib/builtins:322, :201). If `is_no_default` is missing, `! is_no_default` returns 127 and `!` turns that into 0. `builtin_has_default_run build` then returns 0 without helpers, and 1 with them. lib/help:282 and lib/cmd/doctor:293 would both be wrong without a word. No caller reaches this today. Fix: at load time, refuse loudly when `is_no_default` is not defined.
2. **The structural grep only catches one exact layout** (tests/unit/helpers.bats:716-722). It misses:
   - `false|no|0` with no spaces;
   - reordered or quoted word lists;
   - `[ "$g" = - ]` (the form `is_no_default` itself uses), `'-'`, `${g}` and `[[ == - ]]`;
   - `@builtin | -)`.
   Its trailing `|| true` also swallows grep's exit 2. And the release note says more than the test does. Fix: match the words in any layout, add a positive-control fixture, check grep's rc, and correct the note.
3. **The doc-spelling test parses `declare -f`** (tests/unit/helpers.bats:712). It stays green when an extra `[ "$1" = off ] && return 0` line is added, and when `OFF)` or quoted arms are added. It checks only docs/configuration.md, not lib/config.reference.yaml:400-401, and not the "same four spellings" count. Fix: keep the words as data in lib/helpers (eg `_DEVBIN_FALSE_WORDS`), and have the predicates and the test both read that.
4. **lib/cmd/server:31 checks `= true` directly** (pre-existing). An option value of `yes` or `1` for iex is silently ignored. Fix: use `is_true_word`.
5. **The grammar rule (`-` or empty means generic) is written out twice, in `run_option` and in `command_grammar`, and `grammar_for` (lib/runlog:651) holds a third fallback.** Fix: one resolver, in lib/runlog next to `gate_log_suffix`, which also covers gatecmd.

## Recommendation

- lib/gatecmd:90-91 passes suffix and grammar through raw; a `-` would reach `run_gate` unconverted.
- lib/config.reference.yaml:375-386 does not carry the new `grammar: "-"` sentence.
- lib/config validates keys but not values, so `enabled: off` is silently neither true nor false. The predicates make that check cheap. Pre-existing.

## Style

- lib/builtins:6-7: the header comment was never rewrapped, and one line is 135 characters.
