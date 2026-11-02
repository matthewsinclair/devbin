# LESSONS.md

Durable defect classes, in the general form; this project produced each at least once. The specific defect never recurs; the general one always does.

- Mechanical DO / NEVER rules belong in `usage-rules.md`, the shell's own defect class in `ARCHITECTURE-shell.md`, and a fact about a downstream project at that project.
- What lands here is a way of being wrong that survives the language, the tool and the project.

## What a green actually certifies

**A guard must fail when its subject is missing, not skip.** `[ -f "$doc" ] || skip` meant deleting the document would delete its check with the suite still green. Skip for a missing tool, never for a missing subject.

**A marker that carries bad news must be tested at the reader that relays it, not only at the writer.** A reader truncated a `+dirty -- THESE BYTES MATCH NO COMMIT` field to its sha and rendered it as a clean row.

**A status line is informative only if its negation is also emitted and has been seen.** `guards: 4 ran` means something because `NO guard ran` exists; a gate that falls silent instead makes the two states indistinguishable.

**Ask of any success path what it verified, and who could have observed the case it missed.** `swift-format lint` exits 0 with findings, so a freshly fixed arm sealed green over 633 of them; a prompt that fired only at a terminal passed every agent and CI run.

**Before asking what a gate certifies, ask whether anything calls it.** A guard documented as enforced had never run, because the hook roster naming it was copied before it existed. Absence has no output, so read your own `.git/hooks`.

**A determinate-zero path means the non-zero path has never run.** A swift arm with a subcommand the tool never had stayed green for months in a repo with no `.swift` files; the suite needs a case that gets past the empty path.

**An armed gate that has never once been green is evidence about itself, not the code.** A swift arm read as broken Swift for months and was a missing server.

**A gate that examines nothing and exits 0 is a false green, so read the run count, not the exit code.** `mix credo --only error` matched zero checks over 222 files because credo has no `error` category. "No formattable language declared" is an honest determinate pass.

**A verdict must name its denominator, and zero needs wording distinct from a pass.** `every sidecar agrees` printed the same over four sidecars and over none, and `grep -c '^not ok'` returned 0 over an output file not yet written. Read the population (eg the TAP plan line) beside every count.

**Name an instrument's baseline and scope before trusting its green; its clean says nothing outside its contract.** `vendor` answers tree-vs-source and `doctor` tree-vs-install; a review that does not run shellcheck by contract passed a real SC2209.

**A sound instrument aimed one unit wide returns clean and says nothing about its aim.** A profile read from a member manifest when only the workspace root counts, or a `--lib` result quoted for a `--workspace` run; `head` and `-maxdepth` narrow a population just as silently.

**A check with no reachable red state carries zero bits: ask what would have to be true for it to fail.** `cmp` proving two copies identical could not see a defect in the instruction they shared, and a reference count of 0 read 0 in both worlds. A finding withdrawn on such a check leaves nothing to re-measure.

**A result is evidence only if the method could have come out the other way.** `zsh -l -c` never reads `.zshrc`, so it reported a function missing whatever the truth; "0 dirty" after a restore holds both for a correct restore and for one that reverted past an uncommitted start (restore to the state you found, not HEAD). Ask of a negative whether a positive was possible, and of a positive what else would produce it.

**A false zero is never re-run; a high count audits itself.** Seventeen false positives forced an audit, while `46 lines, 0 redundant` came from a lookup key that never matched. Before believing a zero, run the instrument once on something known dirty.

**A clean score over a population that cannot contain the failure is no evidence.** "100% precision" over a corpus with no negation sentences could not exhibit the failure mode, and a project-local check run upstream is clean by position. Measure consumer-facing instruments in a consumer estate.

**Two correct measurements of different questions, spliced, make a wrong one.** A finding took its count from one grep and its names from another that `head` had silently capped. State which instrument produced each half of a claim.

**Count what readers do with a thing, not how many mention it.** Five files that read a path are less exposed than two that parse it.

**A permanently red gate is the mirror of a false green: both stop being read.** `check lint` failed on committed code for a week and blocked nobody.

**A control that used to work can stop without failing.** A detector resolving names through PATH went correctly silent once a binary was darkened; only a before/after comparison sees it.

**When a noun can change kind, re-ask every check that takes it.** Two git checks went silent when their source stopped being a git repository, and silence was already their normal state.

**A fallback keyed on exit status cannot tell "found nothing" from "could not look".** `grep x a b || echo "(none)"` printed its reassurance under real matches because one file was missing, and `if git merge-base --is-ancestor` reads rc 128 (sha not present) as "not an ancestor"; a refusal printed where an answer was expected (ugrep rejecting a pattern, stderr dropped) reads as no match. Read the tool's status table and print the status beside every negative.

**The environment an instrument runs in is part of the instrument.** A suite run with `GIT_OPTIONAL_LOCKS=0` already exported passed every arm asserting devbin sets it. Tests clear what they assert the code establishes, and keep an arm that fails when the harness did it.

**An artefact set looks like a run and is not one.** One minute-stamped directory held artefacts from a failed run and from the passing run after it; mint a run id once per invocation.

**A shared implementation is only shared if something measures adoption.** Three estates carried worse private copies of a shared command, and the health check called them supported overrides. Ask of every override whether the composable path would have done.

**A generated file that nothing regenerates is a copy that keeps asserting it is current.** Removing a generator's only caller orphaned a file advertising a retired command; a fix that adds a source without deleting the old copy has made two sources, so evaluate from a stable location rather than copy.

**When a regeneration can produce something of the right shape, shape is not evidence.** A regenerated `CLAUDE.md` substitutes a well-formed default user block for the lost one; only a full before/after digest sees it.

**Never `head` or `tail` when size or status is the question.** Truncate for reading, never for counting or deciding.

## What a search cannot see

**A survey finds the shape it is looking for; ask what a thing does before where it lives.** A survey for `bin/<prj>` recorded no launcher where four of six projects kept one in `scripts/`.

**A line count is not a reading.** "The 179-line launcher" a plan proposed to migrate was the product; read the head of anything a plan would delete.

**A sweep's completeness is a claim about its enumeration.** Sweeps over a roster of ten installs missed nine more on disk; enumerate from the thing itself and say what was excluded and why. For call sites, a census by reading is weaker than a class arm, and both are weaker than a funnel proof that there is one caller.

**Record the predicate beside every count.** Three "from disk" enumerations of one filesystem gave 23, 22 and 21; when two people's counts disagree, the likeliest cause is that neither stated the population.

**A uniform result across a population describes the query, not the population.** Eleven estates all answering `NONE` meant the query read a filename that does not exist.

**A negative from a lookup by name is only as good as the name, and tools sharing an input agree without corroborating.** `Icon\r` defeated both `git ls-files` and `git check-ignore`.

**An identical observation can support opposite inferences, and the output cannot separate them.** "Not found" reads as "does not exist" or as "the resolver never looked".

**A survey that sizes each project alone cannot see the dependency graph.** A rollout scheduled a project ahead of its own upstream.

**A credential audit that finds one credential has found one; sweep by shape, not by name.** Three credentials in three shapes turned up while chasing other questions.

**Take a sweep's predicate from the model of the defect, not from the instance that revealed it.** A scan for a trailing comma missed bold-terminated values, and a citation checker keyed on `+` missed comma joiners. A sweep for a fact is not a sweep for one spelling of it.

**State the population beside the claim, because the wording will be read as covering everything.** "Four senders" where the rows held five, after a presentational merge, and a tool's "no thread differs on disk" that compared only the canon extract. Re-derive summarised figures from the rows, and title a test for what it actually reads.

**A grep finds a string; whether it is a defect depends on what the surrounding prose does with it.** A rejected config form shown above the section explaining its rejection is the subject, not a bug; searching the concern without its context over-reports confidently.

**A second source of truth is invisible to whoever reads the first, however carefully.** Two files declared a project's languages and each error message named only its own. The tell is two messages about one concept naming two files, so ask what else answers the question.

**A constraint does not record its premise, so it outlives the condition that justified it.** A placement meant to keep a command from shipping fleet-wide survived the ruling that made it fleet-wide. Re-derive the premise after any scope change, including a change in the world.

**A warning that names a number is defended against by changing the number.** A note that `-maxdepth 3` missed nested projects was answered with `-maxdepth 4`, minutes after reading it. Name the shape, and treat a warning that failed a reader who had it in context as a defect in the warning.

**Source every instance of a class to something re-readable.** One of four instances in a class write-up was recalled from impression and had not happened.

## Before you call it a defect

**A wrong stated reason for a correct fix or conclusion closes the instance and leaves the class open.** The reason reads as a guarantee, so nobody looks again; if it is a guess, say so or say nothing.

**A reproduction is a transcript or it is a hypothesis.** A Reproduction section was written in the voice of observation after reading two functions, while the check lived in a third.

**Reading a function is not reading a code path: ask who calls it.** The conclusion was one function wider than what was read.

**A finding that depends on an unread mechanism is a question, and so is a declared limit nobody tried to break.** State it conditionally; a path declared undrivable by reading was driven by a shim in minutes.

**Check whether the code already ruled on it, and whether the outlier is your own tree.** A vacuous-looking green had its reasoning four lines up; four fleet-wide-looking findings in one day were devbin's own config.

**A work item's framing and option set are the question, not the answer.** Six of eight issues closed in a day changed framing, and one offered two options that both removed a flag projects needed. Read the item against what has landed since.

**A difference is symmetric and a cause is not.** `git diff main branch` gave 26 files whether the branch or main changed them, and the branch was an ancestor; run `merge-base --is-ancestor` or `rev-list --left-right --count` before naming a cause.

**Before calling a migration lossy, cross-tab the whole population on what the new model requires.** A criterion flipped to unsatisfied because the new tool refuses sign-offs with no evidence, exposing an old false green; n=1 correlates with everything.

**Verify a peer's message per claim, not per peer.** One message held a true claim and a false one at equal confidence, and the false one was written into a file as an annotation before the file was opened.

**An unverified qualifier is worse than none.** A relay added a project name to a bare issue number that was correct at home, and the next reader resolved a real, unrelated issue.

**A defect that returns the correct answer on the case in front of you is invisible to result-checking.** A config rewritten mid-parse yields valid YAML with wrong contents, and a bash 3.2 associative array prints the right answer through index 0. Read the input twice and compare.

**A default never exercised on the case it exists for has been avoided, not tested.** Install derived names from directory basenames across nine installs that never took the breaking input.

**A setting whose effect you have not observed is a claim, and a dead setting is a trap.** A logger key went inert across a release and file logging died silently for a year; a setting shadowed today fires on the fresh clone that lacks the shadowing file.

**A workaround duplicated into every project stops looking like a workaround.** Four projects hand-restated a config key as though it were the design; when several projects do the same odd thing, fix the base.

**A mitigated anomaly stops producing evidence.** A census that rescans on disagreement hid a filesystem fault a peer met as data loss. Ask what signal each workaround consumes; a fail-closed race clears on retry and so never gets reported.

**A trap documented by its signature is tripped by anything that reproduces the signature.** A different extractor produced the warned-of "twelve lines" by dropping a blank. Verify against the highest-bit invariant (bytes, item counts).

**A reproduction's unusual environment is data, not scaffolding.** A fix's own comment recorded, as setup, that the command it called had been retired, and estates vendored the dead row for months.

**A premise you falsified yourself earlier in the session is the hardest to see.** A test assumed the store held no content for files the author had put there two hours before; when a premise is an absence, check your own recent writes first.

## Tests, fixtures and controls

**A new test proves nothing until it has gone red for the right reason.** One passed on exit 127 rather than a refusal, and one shadowed the command so the assertion compared two empty strings.

**Run the positive control before trusting any zero, and prove both arms of a guard.** A fixture that does not exhibit the trap passes every assertion against a broken implementation.

**Red-before-green proves a test fails when the code is absent, not that it detects code that is wrong.** An arm asserting an error "names both handles" passed because an unrelated warning on the same fixture, or the page under test itself, supplied the strings. Assert on what makes the message that message, and mutate other people's tests where you can.

**A control is only a control if you can say what would make it fail, and which line the break must reach.** A `| tail` reported tail's rc, a `pgrep -f` matched itself, and a reversion that moved the failing statement before its window stayed green.

**A mutation proves nothing until it is shown applied and reached.** A patch that missed its anchor, or a mutant inside a loop that never runs, survives and reads as a robust test, while a wholesale break kills every arm and identifies nothing. Make each break assert its own effect (diff, changed line) before reading its result.

**An equivalent mutant is a finding: either unreachable code or a missing assertion.** Ask what would distinguish the two versions, and whether a test should.

**A guard that shares a failure direction with its bug cannot fire.** An arm grepping output for a backtick in an unquoted heredoc could never see it, because the shell executes it. Assert on the source when the defect destroys its own evidence.

**A fake that accepts every argument tests plumbing, not correctness.** A helper echoing its arguments passed a command line the real tool rejects; make fakes refuse what the tool refuses.

**An `if` around an assertion asserts nothing when its guard is false.** Five "flexible" tests failed when strengthened, because the feature had produced nothing for a long time.

**An assertion can be so wide it forbids the truth.** A refutation of a bare word failed on a correct table header; scope refutations to the instrument under test.

**A test must not read the machine, and the costly assumption is the one that makes it pass.** Arms reading the author's own project path were green locally and red on every CI run. Run the suite with HOME and the project root pointed at empty directories.

**A fixture must not be something that can be repaired out from under you.** A self-test used a real estate as its lossy case until the estate was fixed. A new arm's fixture should also be clean on every existing arm.

**A before/after comparison is void if the work already changed the "before".** Ask of every baseline whether you could already have broken it.

**For each row of an equivalence table, test the claim that could fail, not a true one beside it.**

**A gate that checks less than the one it replaces passes every comparison you would think to make.** Compare what each gate examined, not whether they agreed.

**Run a fix or predicate before publishing it, or label it unrun.** A reasoned Proposed Fix under a measured diagnosis carried the opposite defect, and a repro narrowed during write-up and never re-run read to its recipient as a refutation. The last thing changed before sending is the least likely to have been measured.

**A suite derived from its author's model can only confirm that model; the first outside adopter is the real acceptance run.** The release core passed its author's semver-only tags and failed silently on the first estate whose last tag did not fit.

**Walk a distribution point from nothing, as a user.** A feature shipped with every criterion green while a project with nothing installed, the one path it existed for, was blocked by construction.

**A backup keyed on basename collides, and verifying the restore against it cannot catch it.** Key backups on the full path.

**Editing the tree while a suite runs invalidates the run, and the result still looks like a result.** Kill and restart it; a fingerprint of the inputs before and after is what proves a run undisturbed.

**A killed mutation run leaves the tree poisoned and processes hung.** An interrupted job never reached its restore line, and a mutant executed a binary that blocked on stdin, so a hang looked like slowness. Mutate a copy, verify the restore, and check what a timed-out run left running.

## Scope, ownership and decisions

**Authority does not travel with evidence or with a relay.** A peer's accurate relay of the human's ask is not the human's instruction, and your own well-measured recommendation about another owner's tree is not yours to act on; the rule slips most when you hold the evidence. Route the ask to the owner, attributed, and say when the decision costs nothing to defer.

**The cautious-sounding fix can manufacture the hazard.** "Commit those files" would have committed a third node's claimed work, and "upgrade before merging" would have turned a no-op ancestor merge into a real one. Measure what must be true for a fix to be safe, and across a boundary give options without a recommendation.

**A census identifies files, not owners, and the default owner is whoever you are talking to.** A board's thread-only `claims:` field had nowhere to record a claim on file sets; ask which surface answers "is anyone working these paths".

**A split carved from an unfinished census is wrong at its edges, and no slice holder can see it.** A documentation-audit split omitted all of `docs/`. Enumerate mechanically and state which surfaces were walked.

**An option set can mislead through a phantom cost or a phantom coupling, recommendation or not.** One option priced a false positive the mechanism cannot produce; another bound an outcome to a precedent the decider wanted separately. Check each cost against the mechanism and each pairing for separability.

**When two rules about one field seem to conflict, find the occasion each was written for.** Releasing status before a compact made a working node vanish, and holding it through a suspension made an absent one look live.

**A ruling about one project is not a fleet ruling.** Ask what was true about the project it was made for.

**A defect trail is not a work queue.** When a follow-on grows past what it served, say so and get a ruling.

**A driveby has a ceiling; the ask only sizes the floor.** "Add credo if it is easy" was one line and 139 findings; report the shape and let the ask be re-sized.

**A default is a hard-coded value: when a decision is declared configuration, unset is an error naming the key.** A fallback to one operator's install directory sat in a runtime fourteen estates vendor, and a publish to the wrong place looks like a publish to the right one.

**A live-resolved artefact has no rollout window: the commit is the rollout.** A guard body read from a shared install was in force in every estate before anyone could be told, so announce before committing.

**A guard's first version overreaches and its second underreaches; ask the question positively.** A namespace wildcard caught generated names, and a list of colliding variable names missed a non-name that made `local -n` fall through to success. Compute the answer (eg "is this a variable name") rather than look it up in a history of cases.

**Guard the harm, not one route to it.** A self-install guard compared target to source while the harm was search-order shadowing, and a different source walked past it.

**An incidental protection is not a guard.** A prompt could not recurse only because its verb was missing from a list, and widening the list made it hang.

**A duplicated decision is benign until the copies disagree about the safe direction.** A guard failing closed and a list failing open were held apart only by call order; ask which copy survives a deletion.

**The gaps are where two mechanisms meet, and building the next thing is what finds them.** Most base defects sat on a seam (config against catalogue, a gate against its scope) and surfaced while building something else.

## The machine underneath

**A sync has a direction; measure both sides before choosing it.** Re-rendering from canon by convention would have deleted four sections, human rulings among them, that only the working file held.

**A committed extract or projection is not the source.** A field edited into committed JSON read back through the tool as absent, and restoring that JSON from git rolled back nothing the tool reads. Confirm which artefact a command reads, and read back through the consumer's interface.

**A version string identifies a release, not what is running: cite the sha you read.** Builds turned over while all reported `3.0.0`, and an estate ran a symlink into a working tree. Mark a sha copied from a record as a transcription.

**A case-only rename is invisible to git on macOS.** `core.ignorecase` keeps the old name in the index; use `git mv --force` and check the stored name, since "old name absent" is false on a case-insensitive filesystem.

**On a case-insensitive filesystem a glob is the wrong tool for a selective delete.** List, delete, then verify the survivors.

**A name generated from config cannot be fixed by renaming the file.** Ask what generated a name before renaming it.

**A file no traced code path creates means another writer.** `ps` is the first question, not the fourth.

**Uncommitted bytes in someone else's tree read as an intruder.** Announce a fleet write before it runs and name the trees it leaves uncommitted; a committed change explains itself in the log and a held one nowhere.

**A guard reading global state acts on state you did not create.** A `git diff --cached` check caught peers' staging and its reset discarded it; scope the remedy at least as narrowly as the check.

**Stage, read the status, then commit, as separate calls.** `git add -A && git commit` swept a stray test line that undid an earlier fix.

**`git commit --only` can leave index residue that the next bare commit silently reverts.** A clean tree is evidence in neither direction.

**A file you are about to create may already exist, and something may already parse it.** A fleet roll clobbered an existing ignore file, and an unanchored grep over a pin file emits two lines once the file gains a comment. List before creating, and read the parser.

**A change is a change to everything that reads what it touches, and to everything the new code reads.** Logging a command line put config text in front of unanchored extraction grammars, and swapping `git archive` for `checkout-index` swapped commit attributes for worktree ones. Enumerate readers, including tests that parse the artefact, and the environment a new construct reads.

**A project's formatting hook runs on the install commit, and vendored files are in its blast radius.** Author vendored Markdown formatter-stable and fence the vendored directory.

**Measurements are of the tool and shell you have, not the ones the artefact gets.** A lint construct accepted locally failed CI's older build, and `#!/usr/bin/env bash` resolves to 3.2 on macOS while every measurement was on 5.x. Prefer the shape every version accepts.

**Know which shell you are in before trusting its idioms.** zsh does not word-split `$var` and has no `PIPESTATUS`, and backticks in a double-quoted commit message execute.

**Capture a status the moment it is produced; the last command in a chain decides the verdict.** `cmd | head` lost the status, `... || echo "(no failures)"` exited 0 over a failing suite, and a commit loop printed `git log -1` for trees that never committed. Write `out="$(cmd)"; rc=$?`, then present.

**A `die` at command-substitution depth 2 is swallowed while its message still prints.** Without `inherit_errexit` a release command printed its refusal twice and exited 0. A refusal that really stops may already have written, so check the subject before and after.

**Under `pipefail`, a pipeline is unsound when the reader can decide before consuming everything the writer writes.** The writer's SIGPIPE becomes the pipeline's status, so `printf "$set" | grep -q x` sometimes reports a hit as absent; the race is usually won and has no portable size threshold. Remove the pipe (here-string, `case`), never `|| true`, and make the regression test force the loss.

**A fix verified by construction beats one verified by measurement.** "0 losses in 40 trials" describes the shapes tried, while a here-string is not a pipeline and gives `pipefail` nothing to promote; pair it with a negative control so a fix that matches everything is caught.

**Ask whether the system produces a defect's worst-case shape by construction.** A board header always sits at the top of the file, so the earliest-match `pipefail` loss was the shape every routine rewrite produced.

**State that must outlive a subshell goes in a file.** A call counter incremented inside `$( )` died with the subshell, so a race test passed against a guard that never fired.

**`read` returns 1 at EOF having already assigned.** `read -r line <f || line=""` empties a last line that lacks a newline; a hurried fix lands in the blast radius of the defect it fixes.

**Interpolating a path into a regex makes every `.` a wildcard.** Compare strings exactly unless you want a pattern.

**Parsing display text bets the format holds still, and requesting a format that cannot answer is worse.** A hook asked for `--format text` and branched on rc, so the field that would expose its fail-open case was unreachable. Parse display text only from a frozen renderer, and remember that refusing a healthy gate is its own outage.

**A suppression or directive belongs to its call site and its position.** Moving code orphans a suppression, inserting a function after `# shellcheck disable=` moves it onto the newcomer, and a comment opening with `shellcheck` parses as a directive.

**A pointer is not a move: check the destination, not the return code.** `intent ac descope --to` annotated the source and wrote nothing to the destination.

**A placeholder licenses invention, and a stale reading re-stated as fresh carries no marker at all.** Five well-formed sha256 "placeholders" and a "re-measured just now" with no second command both read as measured. Re-run instead of re-stating, and before correcting a number ask whether it had a source.

**Read the clock before composing the stamp.** Writing the text then running `date` made every stamp a prediction, and a guess that happens to be right is never caught.

**Messages carry timestamps under none of the record's checks, and a zone in a format string is decoration.** `stat -t '%H:%M:%SZ'` prints local time with a literal `Z`; only `TZ=UTC` converts.

## Documenting is a test

**Prose is a test, and a code comment is prose nobody tests.** Writing a help topic found an option nothing read, while "ONE parser, used by BOTH call sites" enforced nothing when a third arrived. Every claim in a comment needs an arm, or a note that it has none.

**A document's address is part of its correctness.** The only description of a command's input format sat in a directory consumers never vendor; ask where the reader will be standing.

**Cite a symbol or quote the sentence, and anchor edits on content, never on line numbers.** Cited lines moved twice in an afternoon, and an `awk NR==` edit using pre-insertion numbering overwrote a line its read-back then confirmed. After an edit, grep for what should still be there.

**A tracking document that accumulates what happened stops reading as what is left.** `wip.md` holds DOING and TODO; the day's findings belong in git, the tracker and this file.

**A number in a document is a second source, and it goes stale when the work or the instrument moves.** `wip.md`'s 218/218 read 79/218 after a tool upgrade with no criterion changed. Print the command and delete a live number, or date a historical one.

**An edit to a generated region is a delay, and a provenance stamp reads as a live claim.** A version-pin fix landed in the part regeneration overwrites. Find the preserved block first, and say whether "for vX" records what generated the file or what is current.

**A fold reads like a review and is not one, and it drops unanswered messages.** Compress only after archiving the full text, and say so; before folding, list each peer's unhandled messages, remembering `intent wb clear <sender>` clears every message from that sender.

**A pointer in an annotation is trusted instead of the body, so a wrong one is worse than none.** A correction cited the wrong line for the value it defended.

**A message has no revision, so it is the copy that rots.** Quote a channel as a channel, never as a document.

**A qualifier survives in the file and is dropped in the retelling.** Before repeating a fact you did not measure, name who measured it in the same sentence.

**A comparative word carries an unwritten baseline that changes when the sentence moves.** A Resolution's "stays failed" was true against the fix's earlier draft and false against the last release, so the release note presented a new failure as an old one. Re-read comparatives against the baseline of the document they land in.

**When something is withheld deliberately, the deliberateness must reach the user.** A correctly withheld command reported only "unknown command".

**A remediation must resolve from where its reader stands.** `run: bin/devbin upgrade` named nothing from a subdirectory; test it from there.

**Report the field that moved.** A change report printed the one unchanged field twice as evidence of a difference.

**A tree that a record cites is never rebuilt in place.** A rebuild took a seal pair the work-in-progress file cited; build each new tree in a new directory and leave cited files at their paths.
