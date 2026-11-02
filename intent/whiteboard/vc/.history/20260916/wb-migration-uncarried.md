# What the store migration did not carry -- devbin, 2026-09-16 07:02Z

Written by vc immediately after `intent wb migrate hv cc vc` on Intent 3.0.3 build `d24487079`.
The pre-migration boards and inboxes are beside this file, each cmp-verified byte-identical before the run.

Every line below is migrate's own stderr, verbatim. Nothing here is a summary.

## hv

```
uncarried: intent/whiteboard/hv/wip.md:14 -- Human-driven. No session loop, `session_id: none`, heartbeat advisory. Maintained on hv's behalf by vc under hv's explicit grant; **last written 2026-09-03 09:15Z, and this write ADDS A DIRECTIVE rather than correcting a fact -- the first time that has happened.** Standing directives were **1342 bytes, 10 bullets** and are now **2241 bytes, 11 bullets**, re-measured after the write rather than predicted before it; **the change is hv's ruling of 2026-09-03 09:15Z on the guard-sequencing escalation, taken interactively, and it is recorded here because a block whose invariant is _unchanged_ needs an explicit note on the one occasion it changes.** Two different extractors report 12 and 13 lines and neither has lost anything: dropping the HEADING gives one, dropping the TRAILING BLANK gives the other. **Verify against the BYTE COUNT and the bullet COUNT, never the line count alone** -- on 2026-09-01 the line-count alarm fired on a second, harmless cause and sent a reader hunting for a directive that was never missing.
  reason: above the first `## ` section: a board's lead paragraph belongs to the document rather than to any item, and the model has no field for it
uncarried: intent/whiteboard/hv/wip.md:16 -- **This board is where hv's standing directives live.** They were scattered across the cc and vc boards until 2026-08-24, which meant a ruling's home was whichever agent happened to be in the room when it was made. Peers read this section at pickup.
  reason: above the first `## ` section: a board's lead paragraph belongs to the document rather than to any item, and the model has no field for it
```

## cc

```
uncarried: intent/whiteboard/cc/wip.md:14 -- **Board cut 2026-09-14 at hv's wrap, released to `paused`.** The pre-fold board is archived verbatim at [`.history/20260914/wip-prefold-2158Z.md`](.history/20260914/wip-prefold-2158Z.md), in its own commit `492d1f1`, before this cut. Finished work lives in its commits and closed issues and is not restated here.
  reason: above the first `## ` section: a board's lead paragraph belongs to the document rather than to any item, and the model has no field for it
uncarried: intent/whiteboard/cc/.history/20260828/clockguard-fix-arm.sh -- clockguard-fix-arm.sh
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/clockguard-gnu-arm.sh -- clockguard-gnu-arm.sh
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/clockguard-loop-arm.sh -- clockguard-loop-arm.sh
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/clockguard-measurement.txt -- clockguard-measurement.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/conflab-phase4-result.txt -- conflab-phase4-result.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/conflab-phase4.sh -- conflab-phase4.sh
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260828/conflab-prehop-20260828.txt -- conflab-prehop-20260828.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260914/0056-census-column-work.patch -- 0056-census-column-work.patch
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/cc/.history/20260914/0062-message-half-tests.patch -- 0062-message-half-tests.patch
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
```

## vc

```
uncarried: intent/whiteboard/vc/wip.md:14 -- **Board cut 2026-09-09 20:10Z. Pre-fold at `.history/20260909/wip-prefold-2011Z.md`, 4471 b, cmp-verified against the working file, and its body verified identical to HEAD below the header.** One form promoted to `intent/llm/LESSONS.md` before the cut, grepped to confirm it landed once.
  reason: above the first `## ` section: a board's lead paragraph belongs to the document rather than to any item, and the model has no field for it
uncarried: intent/whiteboard/vc/wip.md:16 -- **THE DAY'S ONE-LINE SHAPE: I ANSWERED A PEER'S QUESTION ABOUT MY OWN INSTRUMENT, GOT IT WRONG FROM A SOURCE I HAD CHECKED CAREFULLY, AND THE PREDICTION I GAVE THEM TO FALSIFY IS WHAT FOUND BOTH DEFECTS.** The general form is in LESSONS. What is not in LESSONS and belongs on a board: a falsifiable prediction with an untested precondition is cheaper than a hedge nobody can check.
  reason: above the first `## ` section: a board's lead paragraph belongs to the document rather than to any item, and the model has no field for it
uncarried: intent/whiteboard/vc/.history/20260828/conflab-afterread.sh -- conflab-afterread.sh
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-binary-identity.txt -- conflab-prehop-binary-identity.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-census.txt -- conflab-prehop-census.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-config.json -- conflab-prehop-config.json
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-devbin-doctor.txt -- conflab-prehop-devbin-doctor.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-hooks.txt -- conflab-prehop-hooks.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-porcelain.txt -- conflab-prehop-porcelain.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-readverbs.txt -- conflab-prehop-readverbs.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
uncarried: intent/whiteboard/vc/.history/20260828/conflab-prehop-structure.txt -- conflab-prehop-structure.txt
  reason: a `.history/` file that is not markdown: the snapshot carry splits a document into prose sections, and there is nothing here that would read these bytes back
```

## Silent loss, not reported by migrate

Heading text after the first word is dropped, because `kind_of` matches the leading word only:

- `hv` 18:## Standing directives
- `hv` 36:## TODO -- one upstream, the rest downstream, none of it devbin's own code
