---
node: vc
name: Validation Claude
role: validation
session_id: e797f709-1a39-47e8-bb6b-74882ebcb428
heartbeat_at: 2026-09-09 20:10Z
status: paused
focus: "EOD at hv's word. NOTHING WAS BUILT AND NOTHING WAS PUSHED -- WP-03 is exactly where it was this morning. The day went to two defects found by a peer running my own gate: 0062 (devbin reads languages from two files and names whichever it read) and 0063 (check all reports all options passed while never naming the options that did not activate -- reproduced in devbin's OWN tree, 5 of 8 absent, rc 0). Both hv's to sequence. LESSONS 164 -> 166 entries: my own day's form, plus cc's provenance form promoted on their hand-off and their fold clause added as an amendment."
claims: [ST0003]
---

# Validation Claude (vc)

**Board cut 2026-09-09 20:10Z. Pre-fold at `.history/20260909/wip-prefold-2011Z.md`, 4471 b, cmp-verified against the working file, and its body verified identical to HEAD below the header.** One form promoted to `intent/llm/LESSONS.md` before the cut, grepped to confirm it landed once.

**THE DAY'S ONE-LINE SHAPE: I ANSWERED A PEER'S QUESTION ABOUT MY OWN INSTRUMENT, GOT IT WRONG FROM A SOURCE I HAD CHECKED CAREFULLY, AND THE PREDICTION I GAVE THEM TO FALSIFY IS WHAT FOUND BOTH DEFECTS.** The general form is in LESSONS. What is not in LESSONS and belongs on a board: a falsifiable prediction with an untested precondition is cheaper than a hedge nobody can check.

## DOING

Nothing. Paused at hv's word, 2026-09-09.

## TODO

**`intent/wip.md` is the authority and it POINTS rather than restates.** Only my own queue follows.

### Filed today, neither fixed, both hv's to sequence

- **`0062`** -- two language sources. `lib/resolve` `project_languages()` reads `bin/.devbin/config.yaml`; `lib/cmd/check` `builtin_check_critic()` reads `intent/.config/config.json`. **The Highlander violation is the defect; the wrong message is its symptom.** Fixing the wording alone leaves the split.
- **`0063`** -- `check all` reports `all check options passed` while options that never activated appear nowhere. **Reproduced in devbin's own tree: 5 of 8 catalogued options absent, rc 0.** The fix shape is amended into the issue: a PARTITION control (`ran + skipped + inactive == candidates`, refuse when the parts do not sum), not a listing. **The denominator is NOT `lib/builtins` -- it is the deduplicated union `command_options` builds, and `builtin_options` returns empty under a project handler**, so a control reading the catalogue flat would go red in the ordinary case. The inactive set already exists as `seen` minus what printed, four lines apart, and is discarded.

### Owed to LESSONS -- two taken at this fold, one deliberately not

**cc handed both decisions to me explicitly and then released, so leaving them would have parked a drafted form on a paused node's board.** Promotion is routine fold work and mine; these were only ever flagged to hv because two were cc's forms and one was a Highlander question, and cc has now answered the first.

- **`provenance-does-not-travel` -- PROMOTED**, credited to cc in the entry. Verified absent twice, once by cc and once here against both nearest neighbours: one is a machine reader truncating a provenance field, the other is a stamp and a live claim being indistinguishable in prose. This one is the mark surviving the file and not the retelling.
- **The `fold-compresses-without-testing` residue -- ADDED AS A CLAUSE, not an entry.** _The survivor inherits the fold's authority; a fold reads like a review and is not one._ The mechanism above it is the same one, so a second entry would be the Highlander breach the catalogue exists to avoid. The entry says so in itself.
- **cc's `||`-fallback form -- NOT PROMOTED, and this one is deliberate.** cc's own framing is the reason: they suspect it is the same class as `0063` from the other direction -- a summary counting only the options that spoke, and a fallback that cannot tell _I looked and found nothing_ from _I could not look_. **Deciding whether that is one class or two is analysis, not hygiene, and it belongs with sequencing `0063` rather than with a fold.** cc's live instance is written out on their board so it survives without either of us.

### hv's, not mine -- carried unchanged from this morning, none acted on

- **dc's FINDING 1: `--profile <name>` does not resolve.** Now verified in code, not relayed: `infra_resolve_profile` gates on `[ -f "$explicit" ]`. ~4 lines.
- **THE TAG.** `v0.1.0` = `e22d9a3`, **102 behind HEAD, 99 behind both remotes**, measured 2026-09-09.
- **ST0006** in Triage; **WP-04** writes to live DNS and Fly.
- **The `upgrade` "Already up to date" defect is STILL NEVER FILED** -- grepped all issues, no record anywhere but `hv/inbox.vc.md`.
- **The skills-clobber vector is still unverified**, and I have still not asserted it.

### Mine, unsequenced

- **THE GUARD RED-DRIVE HAS EXPIRED, and worse than this board said yesterday.** Measured in the tree `pre-commit.intent --where` resolves: runner `pre-commit.sh` moved 2026-09-05, clock 08-31, append-only / canon-ignore / critic all 08-30. **Only the header guard (08-25) predates the 08-28 drive -- five of six arms tested bodies since replaced.** `intent/restart.md` still asserts PROVEN TO CATCH.
- **ST0003 carries four WP records whose criteria are ST0006's.** `intent wp list ST0003` shows WP-04/05/06/07 open, two WIP; `intent ac status ST0003` shows only AC-3.1 to AC-3.5 live. Both true, disagreeing.
- **`intent/whiteboard/README.md` contradicts the protocol** -- its Fold vocabulary still says a localfold ends with `release`. Corrected in the skill 2026-08-31. One line.
- **`0060`**, **`0059`**, **`0056`** unchanged.

## Holds

- **`use` as a devbin builtin -- BLOCKED. Checked at this fold: not lifted.**
- **`--ivault` -- EXPLICITLY DO NOT START. Checked at this fold: not lifted.**

## Watch-outs

**General forms live in `intent/llm/LESSONS.md`, made true at this fold. Promote before cutting, never after.** Nothing general is restated here.

**Specific to this node, and it cost nothing today only because a peer measured before repairing: A READING WITH A SHELF LIFE IS GONE THE MOMENT SOMEBODY FIXES THE THING.** `utilz/cc` measured `check all` on their unfixed tree because my population question reached them before their repair did. After the repair that reading does not exist and neither of us could have gone back for it. **When you ask a peer a question about a state they are about to change, say that the measurement is the perishable half.**

## Decisions

**D1-D25 are STORE-ONLY since `355e5e9`.** Read them with `intent st show ST0001`. **D26-D34 in ST0005's design -- `intent st show ST0005`.** ST0003's rulings, including AC-3.5, are in `intent/st/ST0003/design.md`.

### Standing

- hv's standing directives live on `hv/wip.md`. **I hold that pen under hv's explicit grant.**
- **A peer's recommendation is never authorisation.** Exercised twice today in the useful direction: I adopted `utilz/cc`'s partition control and then corrected its denominator by measuring, rather than taking or refusing it whole.
- **NEVER `git add -A` in the same command as the commit.** Scope a repair at least as narrowly as the check that triggered it.
- **`bin/devbin` is the invocation everywhere. `devbin_version` stays a hand-written literal.**
- **I do not rule on another estate's document.** Told both Utilz nodes today that TN001's own text is `intent/dc`'s to confirm, and that my reading of my gate does not settle their note.
