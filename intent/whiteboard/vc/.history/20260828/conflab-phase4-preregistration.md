# PRE-REGISTERED PREDICTIONS -- devbin-vc, Conflab Phase 4

Written 2026-08-28 11:30Z, BEFORE the hop, and before executing any after-read.

## Why this file exists

I have been given devbin-cc's full Phase 4 method and its expected values, as a
consequence of becoming their routing point in hv's authority chain. intent-vc
framed the cost as "only in what you know". **That understates it for a witness.**
Method priming is fenced by commit order (my method is fixed at 8d8b336, 137s
ahead of cc's 646f823, and not in its ancestry). **Interpretive priming is not
fenced by anything** -- I now know which answers are supposed to be findings, and
knowing the expected answer is precisely the contamination that changes how hard
a reader looks for a disconfirming reading.

**Pre-registration is the control for that.** These predictions are falsifiable,
committed before the measurement, and auditable afterwards. Where the after-read
MATCHES, interpretive drift is bounded by this file. Where it DIVERGES, the
divergence is the interesting part and my reasoning is on the record rather than
reconstructed after the fact.

## Q1 -- is Conflab on Intent v3? Predicted PASS conditions

  P1  intent/.config/config.json intent_version moves off "2.19.0" to a 3.x value
  P2  intent/.canon/ EXISTS (absent at baseline; Devbin has one, it is the v3 store)
  P3  intent st list / issues list / todo stop refusing -- rc 0, not rc 1
  P4  the refusal string "has not been migrated to Intent v3" appears nowhere
  P5  all 123 steel threads are readable by the v3 binary, not fewer

## Q2 -- is anything WORSE? Predicted, with my reasoning stated

  P6  .git/hooks/pre-commit.intent is UNCHANGED at 814d055e.
      Reasoning: it is a COPY and a cutover does not rewrite copies; the guard
      bodies under it resolve live from INTENT_HOME and move without it. I am
      told this counts as a finding. **I predict it because the mechanism says
      so, not because I was told the answer** -- and I recorded this same
      mechanism at 09:14Z in the baseline manifest, before I knew cc's expected
      values, which is checkable.

  P7  bin/.devbin/** -- all 67 files -- is BYTE-UNCHANGED.
      This is devbin's seam and sits entirely OUTSIDE the declared changed set,
      so by intent-vc's own STOP rule any change here is the finding. My census
      covers all 67. This is where my instrument is best aimed.

  P8  intent/history/ still holds exactly 5 files, all YYYYMM-done.md, and NO
      thread directory. hv's standing rule. Devbin's own history is the reason
      to check: its v2 doc set moved into intent/history/ and had to be moved
      back, and organize then read 54 unclaimed.

  P9  NO NET LOSS of thread content: 123 ST dirs, 654 info.md, 535 WP dirs,
      2 OPEN + 9 CLOSED issues. A v3 store that back-fills from disk and then
      removes the v2 files would show here as a DECREASE. I predict no decrease.
      **This is the prediction I am least confident of and I am saying so now**,
      because it is the one where a wrong prediction matters most.

  P10 The three root canon files MAY change (regeneration is legitimate). A
      change here is NOT a finding on its own; content loss inside one would be.

## What would make me wrong, stated so it can happen

Any of P1-P5 false = the hop did not land, or landed partially.
P6 false in the "template-identical" direction = the carrier WAS replaced, which
is better than predicted and means the cutover reaches further than I thought.
P7 false = a changed path outside the declared set: the STOP condition.
P9 false = content loss, and the most serious outcome available on this job.

## Scope of these predictions

They are MINE and cover only my four censused areas plus the git-tracked view.
They say nothing about the suites (never baselined, hv withdrew it), the live
gate (needs a commit), mix.lock, native/Cargo.lock, or conflabd -- those sit on
cc's legs, not mine, and I make no claim about them.
