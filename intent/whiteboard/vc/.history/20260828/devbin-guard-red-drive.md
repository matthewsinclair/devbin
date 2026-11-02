# Devbin's commit guards, driven red

**2026-08-28. vc. Question: does `guards: 4 ran, 0 skipped` mean the guards CATCH anything, or only that they EXECUTE?**

hv's board recorded the distinction and left it open: the line is *"evidence they EXECUTE, not evidence they would catch anything, since nobody has driven one red here."* conflab-ic proved invocation in Conflab with a two-arm control. Devbin had never had it. A project whose stated cardinal sin is the false green was running four unexercised guards.

## The roster, established first

`.git/hooks/pre-commit` (268 b) is a shim chaining to `.git/hooks/pre-commit.intent` (20899 b). The carrier **names no guard and holds no roster** by design; it delegates to `$INTENT_HOME/lib/templates/hooks/pre-commit-guards.sh`, which holds the `GUARDS` array. Four entries, and all four applicable to this repo:

| guard | applicability path | subject |
| --- | --- | --- |
| `whiteboard-clock-guard.sh` | `intent/whiteboard` | timestamps (checks A, B, C) |
| `whiteboard-header-guard.sh` | `intent/whiteboard` | header values (YAML escape forms) |
| `canon-ignore-guard.sh` | `intent/.canon` | an ignore rule reaching canon |
| `append-only-guard.sh` | `intent` | a write where an append was meant |

## Six red drives, one green control

Every arm: stage, attempt a real commit, capture rc directly (no pipe), compare HEAD before and after, restore. **A refusal is only a refusal if HEAD did not move**, so HEAD is the measurement and rc is the corroboration.

| # | guard / check | input | rc | HEAD | what it printed |
| --- | --- | --- | --- | --- | --- |
| 1 | clock **B** (no `Z`) | `heartbeat_at: 2026-08-28 12:52` | 1 | unmoved | `[B no Z] ... unmarked: assume LOCAL` |
| 2 | clock **A** (future) | `heartbeat_at: 2026-08-29 09:00Z` | 1 | unmoved | `[A future] ... 1178 minutes ahead of now` |
| 3 | clock **C** (backwards) | inbox entries `13:00Z` then `11:00Z` | 1 | unmoved | `[C order] ... an append-only inbox cannot go backwards` |
| 4 | header | `focus: "a \"quoted\" phrase"` | 1 | unmoved | `BLOCKED: a whiteboard header value has been YAML-escaped.` |
| 5 | append-only | one line deleted from a `.history/` file | 1 | unmoved | `error: append-only path(s) lost lines in this commit` |
| 6 | canon-ignore | `intent/.canon/` appended to `.gitignore` | 1 | unmoved | `BLOCKED: ... adds an ignore rule that reaches intent/.canon/` |
| **C** | **green control** | drive 1's commit, one thing changed: stamp read from `date -u` | **0** | **moved** | committed at `27a19a0` |

**The control is the half that matters.** Six refusals alone are consistent with a gate that blocks everything; the same commit landing once its stamp came off a clock is what distinguishes a guard from a wall. Each red arm also named its OWN check rather than a generic failure, so the three clock checks are separately reachable and not one test wearing three labels.

## What this proves, and precisely what it does not

**Proven.** All four guards are wired, reachable and armed in this repository. Each refuses at least one genuine violation with rc 1 and HEAD unmoved. The clock guard's three documented checks each fire independently and identify themselves. The gate discriminates.

**NOT proven, and not weakly -- these are known holes, not gaps in the experiment.**

- **False negatives are untouched.** The clock guard's own documentation states the residue exactly: a fabricated stamp that carries `Z`, lands in the past, and still increases monotonically **passes all three checks**. I did not construct one because it would pass. *Smaller target, not an empty one* -- and a green here must never be read as the class being closed.
- **`append-only-guard.sh` has TWO subjects and only one was exercised.** `intent/whiteboard/*/.history/**` was driven red; `intent/events.jsonl` was not. It exists here at **0 bytes and untracked**, so it has no lines to lose and git cannot see it -- the guard currently protects nothing on that subject in this repo. Untestable rather than untested.
- **This is devbin only.** The guard bodies are read live out of `INTENT_HOME`, so this says nothing about whether another estate's carrier reaches them. That is the whole subject of `intent#0105`, and one estate's green is not the fleet's.
- **Nothing here tests the critic gate**, which is a separate leg of the same hook.

## Method note

The restoration was verified rather than assumed: `.history` file back to 72 lines, `.gitignore` carrying zero canon rules, `git diff HEAD -- intent/whiteboard` empty. The tree afterwards holds exactly the two generated writes it held before.
