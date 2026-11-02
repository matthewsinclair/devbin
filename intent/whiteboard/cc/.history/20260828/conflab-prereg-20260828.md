# devbin-cc pre-registration, Conflab v3 hoist, Phase 4

**Committed 2026-08-28 11:33Z, BEFORE the hop.** Verified un-landed at time of writing: Conflab HEAD `cd09d711` (Phase 0 board headers only), `intent_version` still `2.19.0`, no `intent/.canon`, carrier still `814d055e`.

> **devbin-vc: this file states my CONCLUSIONS and you are the blinded witness. You may prefer not to read it.** It is committed rather than kept private on purpose -- pre-registration's entire value is a timestamp someone else can check, and a scratchpad mtime is not that. The marginal priming is low because the chain handover already gave you my expected values; the credible timestamp is worth more than the residue. This is the trade-off the joint escalation names, taken deliberately rather than stumbled into.

## Why this exists

devbin-vc pre-registered ten predictions at `2ab7ef4`. I ranked pre-registration the strongest available remedy in the escalation I drafted an hour ago. **Recommending it and not doing it would make my own after-read the unbounded half of the convergence.** Where my Phase 4 read matches these, my interpretive drift is bounded by this file; where it diverges, the divergence is itself the finding and my reasoning is on the record instead of reconstructed afterwards.

## Predictions

| # | Prediction | Reasoning | What falsifies it |
| - | ---------- | --------- | ----------------- |
| P1 | Carrier is REPLACED, and equals the shim template read in the same command | `canon.rs:497-500` `install_carrier` writes `hooks/pre-commit-shim.sh` to `pre-commit.intent` via `write_if_changed`; `core.hooksPath` unset so canon resolves to `.git/hooks/`; `template()` does no interpolation | sha stays `814d055e` (hop-3 did not run or failed), or differs from BOTH |
| P2 | Carrier is executable afterwards | `canon.rs` states the mode is set on the unchanged path too, via `make_executable` | any mode without `x` |
| P3 | `--where` runs (because P1) and reports `state: OK`, `root: /Users/matts/Devel/prj/Intent` | shim resolves a recorded home file; this box's `INTENT_HOME` is that path | `state: ABSENT` or `UNUSABLE`, or a different root |
| P4 | All 20 files under `bin/.devbin/cmd/` unchanged; porcelain clean | `cmd/` is project-owned by the manifest's own header; canon writes `intent/**` and hooks, not project dirs | any hash differs, or porcelain non-empty |
| P5 | Intent binary still `1dd65db8...` | rule 2 barred builds in the Intent tree | any other sha -- which means rule 2 was broken, not that my check is wrong |
| P6 | `conflabd` still pid 7438; `conflab`/`conflabd` release binaries unchanged | the hop touches `intent/`, hooks and config, not `native/target/` | pid change, daemon gone, or either product sha moves |
| P7 | `mix.lock` and `native/Cargo.lock` unchanged | no build runs under the withdrawn baseline; the hop does not resolve language deps | either sha moves |
| P8 | `intent_version` moves `2.19.0` -> `3.0.0` and `intent/.canon` appears | that is what the hop is for | it does not, in which case P1 is very unlikely to hold either |

## Where I am least confident, stated before the fact

**P3 is the weakest and I expect it to be the interesting one.** The shim resolves its root from a recorded home file. Conflab is a v2 project that has never had one, so `state: OK` depends on the hop WRITING that file, which I have not verified it does -- I read the shim's reader, not canon's writer. **If P3 comes back `ABSENT` that is a real finding about the hop and not a defect in my check**, and I want that distinction on the record now rather than argued afterwards.

**P1 and P2 are near-certain by code reading, which is exactly why I have written them down.** A prediction that feels certain is the one nobody checks, and `install_carrier`'s own doc comment exists because eleven estates once carried the frozen v2 gate byte-for-byte, correctly, at rc=0.

## Scope -- what I am NOT predicting

Anything about whether the hop is CORRECT beyond these artefacts. My unit is the carrier verdict and the shadow verdict plus the live-service and lockfile before/after. **I am not measuring whether anything that was green went red** -- hv withdrew that baseline, and the changed-set argument that replaced it belongs to intent-cc and intent-dc. If asked afterwards whether Conflab still works, my honest answer is that nothing in my unit can tell you.
