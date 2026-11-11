---
verblock: "11 Nov 2026:v3.67: Matthew Sinclair - globalfold: 0.1.22 shipped; the desk serves Intent 3.3.0"
---

# Work In Progress

DOING and TODO only, one line each. Done work lives in git, `intent issues list` and `RELEASES/`.

## DOING

- Intent 3.3.0, to be cut today (hv, 2026-11-11): devbin-vc holds the desk (decision 153) and serves Intent alone until the cut ends; intent-vc drives the route (issue 0680, the devbin 0.1.22 sweep in intent#ST0091, ST0092's WP-09, WP-06 and WP-10, each run, judged and landed; docs/reference; build all at HEAD); then hv runs the history rewrite, the kovacs line and the cut. Live state: vc's scratch state file and the desk queue in `intent estate status`.
- ST0011, devbin's release shape, in its consumer phase: 18 of 21 ACs, with AC-3.4, AC-4.3 and AC-5.4 met only at the consumers' cuts; WP15 and WP16 (dc) are WIP. Live state: vc's board.

## TODO

- WP10, WP11, WP13 and WP14: each remaining consumer's first cut in the new shape (utilz#ST0031, gtools#ST0020, conflab#ST0126/WP-06, laksa#ISSUE:0058); Intent's (WP12) rides 3.3.0. Gtools's kovacs leg needs its tools there first (vc's todo 186).
- WP15: read each consumer's macOS leg at its cut against design.md's expected column, beside Devbin's measured line.
- WP16 (dc): closes when AC-5.4 is satisfied at the first consumer cut.
- Issue 0326 stays open until pplr#0001, cldr#0001 and ccusage#0007 close (decision 154); the reader notice goes to each of those vcs when it comes up (vc's todo 201).
- Webber after Intent's cut: the /29 Xcode UI run re-asked from a fresh tip, then webber-ic's todo 66, one at a time on the desk; Webber's Elixir runs on gyges.
- For hv: gyges cannot build iOS (no simulator runtime, no Webber clone, codesign fails over ssh, its data volume 97% full); whether to install a runtime there is hv's call through gyges-sysadm.
- For hv: push Molt-matts 6bc343e (dvb emitted by the devbin on PATH); remove the unused opt install at ~/Devel/opt/devbin (0.1.19).
- dvb follow-up, not started: the install's refusal inside a project could name dvb or bin/devbin; in devbin's own checkout dvb runs the dev tree by design.
- A release.gates entry starting with `release` runs a cut inside a cut (devbin-cc's finding beside 0327, vc's todo 203): weigh it for the release after next.
- Bank refs left in canon by cc and dc after the 0.1.20 work (vc's todo 200): clear the landed ones.
- LAST, after everything above (hv, 2026-10-31): WP18, `docs/assembly-and-the-build-cache.md`, "Devbin's Build Cache for Optimised Release Assembly", written from the as-built (vc's todo 183).
- Prodinfra's next session hears hv's 2026-10-15 ruling: `infra --profile` takes a path, with no name form (vc's todo 159).
- The no-vendor mode, deferred until devbin was public (decision 64): hv to schedule.
- Another estate's work is held.
- `--ivault`: do not start until hv says start.
