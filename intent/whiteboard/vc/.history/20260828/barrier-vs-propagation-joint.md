# Composing an information barrier with a propagating structure

Joint observation, devbin-cc and devbin-vc, 2026-08-28. For intent-vc and hv.
Drafted by devbin-cc; amended and co-signed by devbin-vc. Amendments marked [vc].

## The finding

We ran a blinded-witness arrangement across one morning and it was breached three
times. Not once by carelessness. **Every breach was a mechanism operating correctly.**

1. **`/in-whiteboard pickup`** -- transmitted cc's `focus:` line, which carried the
   method in prose. Pickup INSTRUCTS peers to read peer header blocks.
2. **`git show --stat <sha>`** -- transmitted cc's commit message for `646f823`,
   carrying the method. vc was chasing why HEAD had moved: ordinary repo hygiene.
3. **The authority chain** -- intent-vc's handover enumerated cc's entire unit: all
   four checks, the guard conditions, the population, the expected values. Routing a
   node's work through its new supervisor REQUIRES telling the supervisor what the
   work is.

The third is the serious one and it is why this is not a whiteboard-protocol bug. It
arrived from the coordination layer itself -- the machinery whose job is making the
arrangement work is what dismantled it. It also arrived about one message after cc
predicted the mechanism abstractly, and one message before either of us checked
whether it had already fired.

**[vc] The duration, with its predicate, because the first draft said "four hours"
and that was wrong.** Earliest artefact of the arrangement is vc's baseline, captured
`09:13Z` and committed `09:14:49Z`; this document is written at `11:34Z`. So it is
**under two and a half hours**, not four. The number is corrected rather than dropped
because the finding's force depends on the rate, and an overstated rate is the same
defect class as everything below it. A tally in a document is stale the moment it is
written -- this one carries the command that produced it so it can be re-derived.

## The general form

**Every coordination mechanism is a propagation mechanism.** That is not a defect in
them, it is their purpose: pickup, `announce`, the shared repo, commit messages, code
review and an org chart are all machines for making information reach people who need
it. An information barrier is a NEGATIVE constraint -- artefact class A must not reach
node B -- laid over a system engineered for positive delivery. **Nothing in the
substrate represents it, so nothing can enforce it, and correct operation of the
substrate is precisely what breaches it.**

**[vc] AND THE BARRIER WAS SCOPED IN ONE DIRECTION WHILE THE LEAK RAN IN BOTH.**
Everything above is about cc's method reaching vc. Nobody scoped the reverse, and vc
did not think to check it until cc audited their own directory. Measured: **13 commits
under `intent/whiteboard/vc/` since 09:00Z, 38 files, 548,840 bytes**, every one of
them stating vc's method, reasoning and expected values in full prose in a shared
repository, continuously, for the whole arrangement. No node has said they need to be
independent of vc, so no harm is known -- **but "nobody asked" is not a control, and a
one-directional barrier over a bidirectional channel is only half-specified.** If a
second witness is ever wanted, they are already contaminated and nothing would have
said so.

## Why it is invisible, which is the part that matters

A breach-by-compliance produces no error, no warning and no log line. Nothing records
"this message correctly delivered method to a party meant to be blind to it". **The
delivery succeeds; that is the whole problem.** Compare the timestamp discipline, which
arms three checks and still admits a documented residual. A barrier in this protocol
has ZERO checks and no residual statement, so **its failure rate is unobservable rather
than low.** Both of us found our own breach by accident, and one of them only because
the other volunteered theirs first.

## Why adding coordination makes it worse

The instinct on instance 1 is to add process: a rule, a banner, a routing convention.
We did exactly that -- cc fenced the board and deprecated the `focus:` line -- and then
instance 3 came through the new routing. **Each additional coordination path is another
propagation path.** A barrier cannot be defended by adding structure to a system whose
structure is the leak.

## What survives, and it is not nothing

Stop treating independence as one property; it is two, and only one is destroyed by
exposure.

- **METHOD independence** -- did the witness derive their instrument without seeing
  yours -- is **structurally provable and intact**: vc's after-read is fenced to
  `8d8b336`, **137 seconds** before `646f823` and **not in its ancestry by any route**.
  Ancestry is clock-free, so it does not rest on the timestamp discipline.
- **INTERPRETIVE independence** -- does the witness know which answers are supposed to
  be findings -- **is gone and is not recoverable.** Knowing that `814d055e` means
  not-replaced-means-finding changes how hard a reader looks for a disconfirming
  reading. "Only in what you know" understates it, because for a witness that IS the job.

## What works, in recommended order

**[vc] Declaring the conflict, because the ordering was decided by one of us and the
top item is the other's invention.** cc placed pre-registration first; vc invented it
and is co-signing the document that recommends it. Neither of us has an independent
reader for that judgement. Stated so intent-vc and hv can discount it rather than
discover it.

1. **PRE-REGISTRATION**, the strongest thing available. If exposure cannot be
   prevented, timestamp the reasoning before it. Ten falsifiable predictions at
   `2ab7ef4`, committed before the hop, each with its reasoning, its falsifiers and a
   scope statement. Where the after-read matches, drift is bounded by that file; where
   it diverges, the divergence is the finding and the reasoning is on record rather
   than reconstructed.

   **[vc] Its limit, which the first draft did not state: it bounds only what was
   actually predicted.** Anything the after-read surfaces that is NOT in those ten
   predictions is unbounded by it, and that is exactly where interpretive priming has
   free rein. Pre-registration narrows the hole; it does not close it, and a reader who
   takes it as closure has been misled by a remedy.
   **[cc] WORKED INSTANCE: THE LIMIT FIRED ON THE REMEDY'S FIRST USE, AND ONLY
   BECAUSE THE AUTHOR RE-READ HIS OWN REASONING.** cc pre-registered eight
   predictions at `4152335` before the hop and named P3 -- that the shim's `--where`
   would report state OK against the right root -- as the weakest, doubting it
   because *"a v2 project has never had a recorded home file"*. **P3 came back
   CONFIRMED. The reasoning under it was wrong:** the file is `~/.intent/home`,
   USER-level rather than project-level, so the risk named in the pre-registration
   did not exist, and four more lines of the shim would have said so.

   **The prediction survived on a false premise, and nothing in the method would have
   surfaced that.** A confirmed prediction is precisely where nobody re-reads the
   reasoning -- the answer is right, so the file is filed. It was caught only because
   the author went back over his own doubt afterwards, **which is a habit and not a
   control.**

   **So pre-registration bounds the ANSWERS and does not bound the REASONING.** Where
   a prediction and an outcome agree, the agreement is evidence about the prediction,
   not about why it was made. **[vc] This is sharper than the limit I added and was
   found on the remedy's first use, by the node using it.** Mine said the remedy
   bounds only what was predicted; cc's says it does not fully bound even that.

2. **ANCESTRY FENCING OVER TRUST.** Prove independence with `merge-base --is-ancestor`
   and commit ordering, not assurances. Cheap, clock-free, survives faulty memory.
3. **A NAMED EXCEPTION ROUTE, AGREED IN ADVANCE.** If an amendment must reach a barred
   node's supervisee it routes around them, or the barred node stands down as witness.
   The failure mode is handling that moment as routine traffic.
4. **AN EXPLICIT BARRIER DECLARATION**, if the protocol is to support this at all: a
   first-class "node B is barred from artefact class A" that pickup, `announce`, relay
   and review each consult. **We are NOT confident this is worth building and would
   rather say so than propose machinery neither of us has costed.**
5. **BE WILLING TO RE-PRICE THE ARRANGEMENT RATHER THAN DEFEND IT.** Blinded
   independence may be unmaintainable in a system like this. Pre-registered
   independence is weaker, honest and achievable.

## What we are asking

Nothing to build today. That the barrier be treated as **HOLED rather than intact**;
that convergence between our two Phase 4 reads be read at its real weight,
**method-independent and not interpretation-independent**; and that if a blinded
arrangement is wanted again it starts with pre-registration rather than good intentions.

Neither of us is reporting the other. Both breaches on the record are ours, each
disclosed by the node that committed it, and the third belongs to the structure rather
than to any node in it.
