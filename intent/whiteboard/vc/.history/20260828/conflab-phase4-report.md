# Conflab Phase 4 -- independent witness report

devbin-vc, 2026-08-28 12:13Z. Fenced to the method committed at `8d8b336`; matches bounded by
the pre-registration at `2ab7ef4`. Anything outside those is under POST-EXPOSURE
and is NOT corroboration.

## Method, and its priming, stated first

Executed `conflab-afterread.sh` (`ffc44be`, committed BEFORE the measurement).
Census of 1365 baseline files re-run and diffed; git view; four read verbs;
structure counts; hook carriers; binary identity.

**Independence is method-level and provable, not interpretation-level.** My method
commit `8d8b336` precedes devbin-cc's `646f823` by **137 seconds** and is **not in
its ancestry by any route** -- the ancestry half is clock-free. What I do NOT have
is interpretive independence: intent-vc's chain-handover message gave me cc's full
unit including its expected values. Pre-registration is the control for that and it
bounds only what I actually predicted.

**Controls.** Negative control ran inside this invocation, not at authoring time:
the census comparison detected a planted difference (**must be 1, was 1**). Binary
verified myself: sha256 `1dd65db8...`, matching the carried-in value. Preconditions
verified before measuring: HEAD matched the announced sha exactly, porcelain 0, the
rollback point is an ancestor, exactly two commits.

## Q1 -- is Conflab on Intent v3? YES.

| prediction | result |
| ---------- | ------ |
| P1 `intent_version` off 2.19.0 | **3.0.0** -- confirmed |
| P2 `intent/.canon/` exists | **PRESENT** (absent at baseline) -- confirmed |
| P3 read verbs stop refusing | `st list`, `issues list`, `todo` **rc=0**; `doctor` rc=1 but **not a refusal** |
| P4 refusal string gone | **0 occurrences** across all four verbs -- confirmed |
| P5 123 threads readable | **123** st dirs, and the store holds **123** `.canon/st/*.json` -- confirmed |

The refusal that was the pre-hop signature is gone. `doctor`'s rc=1 is a findings
verdict, not a migration refusal, and is treated as Q2 material below.

## Q2 -- is anything worse? NO CONTENT LOSS. One unresolved question about the gate.

**vanished = 0.** Not one file in the four censused areas ceased to exist.
appeared = 140, changed = 40, and every one is accounted for:

- **123** `.canon/st/*.json` + **9** `.canon/issues/*.json` + `project.json` -- the v3 store.
- **4** `.v2` attachments under ST0121-0124 -- exactly the hand-finished carry `7652c9b4` describes.
- **1** `intent/.cache/` write -- the only expected ignored write.
- **~30** re-renders under ST0121-0124 and their WPs; **4** conflab node boards (their own work); `steel_threads.md`, `config.json`.
- **AGENTS.md** and **CLAUDE.md** changed; **README.md** and **usage-rules.md** byte-identical.

| prediction | result |
| ---------- | ------ |
| **P6** carrier UNCHANGED at `814d055e` | **WRONG.** Changed to `b0ed7edd`, 5090 -> 7332 b, mode 711 |
| **P7** `bin/.devbin/**` byte-unchanged | **CONFIRMED. 0 changes.** The STOP condition did not fire |
| **P8** `intent/history/` 5 files, no thread dirs | **CONFIRMED.** 5 files, 0 non-`YYYYMM-done` entries |
| **P9** no net loss (123/654/535) | **CONFIRMED, all identical.** This was the one I flagged as least confident |
| **P10** root canon may change | 2 of 4 changed; legitimate regeneration |

**P6 is my one miss and it is the informative one.** I predicted the carrier would
survive because it is a copy and a cutover does not rewrite copies. It was replaced.
My reasoning was wrong, not merely my answer.

## The one finding I cannot close: the gate's arming state is UNRESOLVED

**`intent doctor` reports `gate-not-running` on `.git/hooks/pre-commit.intent`:**
*"the hook carrier is present and names no guard runner at all, so it executes no
guards -- this is the Baize state, in which every surface reports health while
nothing is enforced."*

**devbin-cc's path trace says the opposite conclusion from the same fact.** Both of
us measured that the carrier names no guard runner (their disambiguated
`GUARD_RUNNER`=0, `pre-commit-guards.sh`=0; doctor's finding). We differ on what it
means.

**Measured, and this is the part neither leg had:**

    Devbin   carrier 20899 b  ae5d0695   GUARD_RUNNER=4  guards.sh=3  intent/home=0
    Conflab  carrier  7332 b  b0ed7edd   GUARD_RUNNER=0  guards.sh=0  intent/home=2

Devbin's gate **demonstrably runs guards** -- `guards: 4 ran` on roughly fifteen of
my own commits today. It has the MONOLITHIC shape. Conflab's new carrier is a SHIM,
and its chain resolves on disk: `~/.intent/home` -> `/Users/matts/Devel/prj/Intent`,
`lib/templates/hooks/pre-commit.sh` present, executable, **47 guard references**.

**So doctor's premise is true and its inference does not hold for a shim.** A shim
names no guard runner BY DESIGN. On that evidence doctor's finding is very likely a
**FALSE POSITIVE on the shim architecture** -- and if so it will fire on every estate
that moves to the shim, which is a false RED on the one command every estate runs.

**I am not upgrading "very likely" to "is", and neither should the report that
consumes this.** Nobody has driven Conflab's gate red. Path tracing proves the chain
RESOLVES; it does not prove a guard fires and refuses a bad commit. The decisive test
is a commit, which is barred. cc says the same of their own leg and asked to be
recorded that way.

## POST-EXPOSURE -- run after I saw cc's method; NOT corroboration

- **The ~50 `model-inconsistent` doctor findings are NOT migration damage.** Checked
  the v2 sources: `ST0016` has no `completed:` line at all, `ST0029` and `ST0096`
  have it empty. **Positive control: 64 completed threads DO carry a date in the
  store, 49 do not** -- so the migration carried dates where they existed and the 49
  are pre-existing v2 gaps that v3 surfaces for the first time. Better observability,
  not new damage.
- **Store and disk disagree on issue count**: 9 `.canon/issues/*.json` against 1 OPEN
  + 8 CLOSED directories = 9. These agree. `intent issues list` shows 1 row (open
  only). No discrepancy; recorded because I initially suspected one.

## What this report does NOT establish

- **Whether anything that was green went red.** No suite was run, ever. All five
  declared languages need a build; builds were barred and hv withdrew the baseline.
  **Nothing here should be read as covering functional regression.**
- **Whether the gate actually fires.** See above. Unresolved, not clean.
- **Anything outside my four censused areas** for untracked or ignored files. Covered
  instead by the run's own porcelain and the STOP condition, per intent-vc.
- **cc's legs**: lockfiles, `conflabd`, the 20-file `bin/.devbin/cmd/` population.
  Not mine, not claimed.

---

## ADDENDUM 2026-08-28 12:18Z -- the gate finding upgrades, and how far

**The section above says "very likely" and I am NOT rewriting it.** What I concluded
at report time, on the evidence I had then, stays visible beside what changed it.

**devbin-cc read Intent's source; I verified every citation against the artefact
rather than taking it.** `Intent/native/rust/crates/intentsvcs/src/doctor.rs`:

    :1086  if !carrier.contains("pre-commit-guards.sh") -> GateState::CarrierRunsNoGuards
    :1205  template = read_to_string(home.join("lib/templates/hooks/pre-commit.sh"))

**The decisive measurement, which needs no inference:**

    lib/templates/hooks/pre-commit-shim.sh   7332 b   marker count = 0
    lib/templates/hooks/pre-commit.sh       34701 b   marker count = 6

Conflab's carrier is **7332 b / `b0ed7edd`** -- the shim, byte-for-byte. **The shim
contains the marker doctor requires ZERO times, by construction.** So
`CarrierRunsNoGuards` is not a judgement doctor makes about a broken estate; it is
the only answer the check can return for ANY shim estate. **Upgraded from "very
likely a false positive" to CERTAIN** -- and in the end it needed no inference, only
a count.

**The check states its own premise, and the premise expired:** *"the marker is the
guard runner the carrier MUST REACH"*. True of a monolithic carrier. False of a shim,
where the carrier reaches the GATE and the gate reaches the runner. **The
architecture moved and the check did not.**

**A SECOND DEFECT, cc's, and it is the worse one.** `:1205` compares the carrier
against the GATE template while canon's `install_carrier` writes the SHIM template to
that path. Different files, so `template != carrier` is **permanently true** on a
shim estate and it reports `BehindTheTemplate` forever. Doctor's own source condemns
that outcome a few lines below: *"a check that reds every estate in the fleet
permanently is one operators learn to skip, and a skipped check is not there for the
two estates that are actually broken either."* **Fixing only the guard check leaves
the estate red anyway.**

### How far this is confirmed, and no further

**By source reading and three independent measurements** -- my `doctor` run, cc's
disambiguated grep, and the template marker counts. **NOT by execution.** Neither of
us built Intent or drove `gate_state`; it is a pure function deliberately separated
from its IO so every arm CAN be driven, but that needs a build and rule 2's bar is
intent-vc's to lift. **The hop landing is not the same as the bar expiring.**

**And none of it says whether Conflab's gate FIRES.** It establishes that doctor's
red is wrong, not that the gate is right. conflab-ic's two-arm control remains the
only instrument today that tests invocation rather than resolution.

---

## CLOSURE 2026-08-28 12:39Z -- superseded on the gate, exactly as pre-stated

**conflab-ic's two-arm control returned, and it settles what neither devbin leg could.**
Arm 1, a stamp without `Z`: **REFUSED, check B named, rc 1, HEAD unmoved.** Arm 2, a
`date -u` stamp: **COMMITTED at Conflab `2b770740`.**

**That is invocation, not resolution.** Both devbin legs could only show the chain
RESOLVES -- cc by path tracing, me by source reading and marker counts. A refusal that
names its check and leaves HEAD unmoved proves the carrier is EXECUTED and a guard
FIRES. The two arms together also separate a gate that refuses everything from one
that discriminates, which a single arm cannot.

**So `doctor`'s `gate-not-running` on a shim is a false positive BY MEASUREMENT**, no
longer by source reading plus inference. This supersedes the addendum above on that
point -- the disposition that addendum pre-stated for itself.

**What the closure does NOT change:** whether the hop broke anything functional. No
suite was ever run. That gap is unchanged and is still the honest answer.
