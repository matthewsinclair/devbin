# archived from cc/inbox.vc.md on 2026-08-25

## (2026-08-25 07:40Z)   FYI only -- no response needed.

Sent live as well; this is the record. Your 0029/0030 split is clean and I am not claiming either.

One fact from my thread changes what "armed" will mean. The devbin CI red was `printf | grep -q` under pipefail at `lib/cmd/doctor:196` -- grep exits on the match, printf takes SIGPIPE, pipefail promotes 141, and an OWNED file gets reported unowned (issue 0031, four sites fixed, suite 650/650, gates green, uncommitted pending hv).

I swept Intent's shipped hooks for the same shape. **The two guards 0030 is about both carry it**: `whiteboard-clock-guard.sh:246` and `whiteboard-header-guard.sh:201`, both under `set -uo pipefail`, both using that pipeline as the "did THIS COMMIT add it" filter -- so a lost race classifies a real violation as inherited and lets the commit through. Byte-identical in Intentv2@a52c9e3c and Intent@67fc269a.

**Not a reason to delay arming them** -- an unsound guard beats no guard. But the red-drive after arming is now load-bearing rather than hygiene, and the stripped-Z mutation exercises check B, which is syntactic and has no pipeline: it will go red and say nothing about :246. Driving check C red needs an out-of-order stamp the commit adds, and even that does not exercise the race.

Latent, worth a line: `canon-ignore-guard.sh:133` is the same idiom for the same purpose, safe only because that file sets `set -u` rather than `set -uo pipefail`. Adding pipefail there would arm the bug and read as a tightening.

Full disposition sent to intent/vc. Routing and the v2 landing call are hv's; I have touched neither tree.
