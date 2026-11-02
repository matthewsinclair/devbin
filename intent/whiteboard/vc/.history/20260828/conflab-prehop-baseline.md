# Conflab PRE-HOP baseline -- devbin-vc, independent witness for Phase 4

Captured 2026-08-28 09:13:00Z, read-only, by devbin-vc's own method. No other node's board,
inbox, findings, runbook or checklist was read before or during capture.

## Provenance of the instrument

  command -v intent  -> /Users/matts/.local/bin/intent
  resolved target    -> /Users/matts/Devel/prj/Intent/native/rust/target/release/intent
  sha256             -> 1dd65db8b49363b1d2ad0b454179e9db67b6e406e10389e6a2f7d6e9ca98ae26
  MATCHES intent-vc's carry-in exactly. intent --version says 3.0.0 (b4d63b44),
  which is a DIFFERENT identifier from the content sha and cannot substitute for it.

## Controls run BEFORE trusting any result

  Census self-compare            -> vanished=0 appeared=0 changed=0
  Census vs deliberately perturbed copy (file removed, hash altered, file added)
                                 -> 1 / 1 / 1, all three shapes detected
  So a zero from this instrument is a measurement, not an empty comparison.

  Perturbation check after MY OWN reads -> 0 / 0 / 0, .git/index mtime unmoved
  at 08:44:54Z. I left the estate byte-identical; that is measured, not assumed.

## State at capture

  HEAD              b7af207fbae152eff91801cc637f61b3f0e3f690 (2026-08-27 23:43:02 +0100)
  working tree      4 M, 4 ??, 152 staged D (all under intent/.treeindex/, which is
                    empty on disk). NOTE: 8 minutes earlier this read 3 M / 8 ??, so
                    the tree is LIVE and these three numbers are a moment, not a state.
  config            intent_version 2.19.0, st_prefix ST,
                    languages shell,elixir,lua,rust,swift
  layout            intent/.canon ABSENT (v2). intent/history PRESENT and correct:
                    exactly 5 files, all YYYYMM-done.md, no thread directory.

## Content census -- the instrument for "is anything worse"

  1365 files hashed: intent/** (1278) + bin/.devbin/** (67) + .git/hooks/** (16)
  + root *.md (4). Positive control: 1278+67+16+4 = 1365, exact.
  Full sha256 list: 10-census.txt

  Structural counts, directory-shaped rather than parsed:
    steel-thread dirs      123    <- the v3 binary independently says 123
    info.md files          654
    WP dirs                535
    issues OPEN / CLOSED   2 / 9
    intent/docs / llm      2 / 15

## Pre-hop command surface -- the instrument for "is it on v3"

  intent st list       rc=1  refuses: "has not been migrated to Intent v3"
  intent issues list   rc=1  same refusal
  intent todo          rc=1  same refusal
  intent doctor        rc=1  "residue: intent/.config/config.json -- unmigrated"
  bin/devbin doctor    rc=0  healthy; reports 9 project shadows (devbin's half,
                             a different tool, unaffected by the Intent hop)

  The v3 binary REFUSES this estate rather than half-reading it. That is the
  sharpest possible before/after discriminator for question 1.

## Hook carriers

  .git/hooks/pre-commit          968 b  2026-08-04T22:29Z  3816004095191b94
  .git/hooks/pre-commit.intent  5090 b  2026-08-14T11:02Z  814d055e9e454222
  The .intent carrier is the v2 one. Devbin's is 20899 b / ae5d0695 and reports
  "guards: 4 ran". Guard BODIES resolve live from INTENT_HOME and move at cutover;
  this CARRIER is a copy and does not.

## What I did NOT measure, and why

  - Conflab's test suites. Building is barred by the standing boundary, and
    every one of its five languages needs a build to test. So I cannot answer
    "did anything that was green go red" and will not imply that I can.
  - The gate running live. Testing it requires a commit, which is barred.
    I recorded the carrier's identity instead.
  - What `intent upgrade` intends to do. It is a write verb and running it
    would BE the hop.
  - Any other node's board, inbox, findings, runbook or checklist.
