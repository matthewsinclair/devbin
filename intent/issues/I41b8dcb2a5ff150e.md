---
issue: I41b8dcb
title: Two leg starts of one project on one host are kept apart only by the Desk, so a second start can clear or share the first's run
status: CLOSED
severity: medium
created: 2026-11-27
closed: 2026-11-27
reporter: Matthew Sinclair
---

## What is wrong

A remote leg's start (release_leg_start, lib/release.legs) first tidies the host for its project, then makes its own run. Its sweep finishes and clears ended runs at other commits and gone runs at any commit, and deletes each leg ref that no run's worktree holds. Its remote start bounds the project's gate cache, unless a run of the project is going. Nothing in the code keeps a second start of the same project on the same host from doing this while a first run is there. Today only the Desk keeps such starts apart. The code says so in _release_leg_run_state's comment, and devbin 0.1.35's note tells the user not to start a second cut or `release gates --leg` of the project on a host while one runs.

So two cuts, or a cut and a rehearsal, on one host can damage each other's runs:

- A second start's sweep reads a first run between its worktree add and its runner's launch as gone, and clears it.
- It deletes the first start's leg ref between that start's send-pack and its worktree add.
- It clears the first run once that run has ended, before the first cut reads it. It copies only the run's log into its own tree, and removes the worktree that held the pair. So the first cut reads its own run as unknown or none, never its verdict, and waits on it to its deadline.
- Two runs at different commits share the project's gate cache, work/<project>-leg.cache, and the host's memory and CPU.

The facts the fix rests on:

- A remote leg's start is four steps from the starting machine, each its own ssh call: the bare repo made (_release_leg_remote_init); the sweep (_release_leg_clear_ended); the send-pack of refs/devbin/legs/<sha>; then the remote start (the cache bounded, the TMPDIR, the worktree add, the log's header, the runner launched). So no one process on the host spans a start.
- A refused start answers `unknown`. A rehearsal stops on it at once. A cut's legs_round reads every word but green and failed as one to wait on, so a cut waits on `unknown` to its deadline.

## The fix

The start takes a lock for its project on the host. A second start refuses while the lock is held, and names the holder. The cut reads that refusal as its leg's red at once.

## What the lock means (devbin-cc's word, 2026-11-27 07:25Z by date -u)

1. Scope. The lock is the project's, on the host: one for each project on each host. It keeps each start of the project on that host apart from any run of the project there. Other projects' runs, and the host's load, stay outside it: the Desk keeps those.
2. What it holds. A start takes it before the first step that changes anything on the host, the sweep. The run that start makes holds it until that run is cleared from the host: by its own cut's read, or by a later start's sweep once the holder is found gone. A start that makes no run frees it before it answers.
3. Why until the run is cleared, not until it ends. A run that has ended waits for its own cut's read. A second start's sweep clears an ended run at another commit (issue 0367) before that read, as "What is wrong" says, so a lock freed at the run's end would still let a second start take the first cut's verdict away.
4. The holder is named. The lock records the project, the commit, the machine and tree the start came from, the time it was taken, and, once the run is launched, its worktree. A refusal prints that record.
5. A held lock refuses. A start that finds the lock held by a live holder changes nothing a run on the host reads, and refuses, naming the holder. A cut reads that refusal as its leg's red at once, never as a word to wait on to the deadline, and a rehearsal stops on it as it does now. The lock does not queue. The Desk keeps runs apart, and the lock is what holds when the Desk does not, so it fails at once and loudly.
6. Live and stale. A holder is live while its runner is alive, by the test _release_leg_run_state reads (issue I0a62f4a). Before its runner is launched, and after its run has ended but before it is cleared, it is live while the process that started it is alive on the machine the lock names. A holder found gone is stale: the next start breaks the lock, warns once naming the holder, and goes on, and its sweep finishes the holder's run as it does now (ended, or gone). A holder that cannot be tested from where the start runs, eg a lock that names another machine, is taken as live, and the start refuses. A lock is never broken on a guess.
7. The same commit. A start at the commit of the run that holds the lock asks for the same run. Today it joins that run ("a run at <sha> was started there before, and its seal is the record"). Under the lock it joins only when the holder's starting process is gone, and it then holds the lock in that process's place. While that process is live it refuses, as in item 5, since two readers of one run each clear it.
8. Every leg host. The tests work with the tools each leg host has, macOS's and uutils' included.
9. What it changes. The caution in _release_leg_run_state's comment ("safe only while two starts of one project on one host never overlap, which the cut ... and the booking of every run keep") becomes a rule the code keeps. So does the caution in devbin 0.1.35's note. The release that ships the lock says that a second start refuses, naming the run that holds the host.
10. Outside it: the local gates on the starting machine, the release tags in the bare repo, and a lock between projects.

devbin-cc's answers to devbin-dc's two questions, and its two conditions (2026-11-27 07:31Z by date -u), which devbin-dc took into the shape below:

- (1) init makes work/ and the bare repo, when they are missing, before the take. That is harmless: whenever a lock is held, its run's worktree hangs off that bare repo, so the step changes nothing. Where someone removed the repo by hand, the step makes an empty repo that no run reads. So a refused start changes nothing a run on the host reads.
- (2) An ended run whose holder names another machine is live, untested, so the start refuses. The read that clears that run is that machine's own cut's, and only that machine can test whether its starter is alive. Breaking the lock would take that cut's verdict away (item 3).
- (a) The refusal's word is `failed`, so legs_round stops the cut red at once and keeps its one decision. The header's word list in lib/release.legs then says that failed also answers a start the host's lock refused, which ran no gate. The detail names the holder, so a seal that records the leg says why.
- (b) The by-hand step is printed only for a holder that could not be tested. A refusal for a holder found live names it and says what ends it, and prints no rm: removing the lock under a live holder lets two runs share the host's cache and load, or lets two readers each clear one run.

## Its shape (devbin-dc's word, 2026-11-27 07:29Z by date -u, with conditions (a) and (b))

1. The lock on the host. It is a directory, work/<project>-leg.lock, beside the bare repo, made by mkdir. mkdir is atomic on every leg host's file system, and macOS has no flock. Its file `holder` holds key=value lines, read with a here-string and never sourced: project, commit, machine (the starting machine's uname -n), tree (the starting checkout's root), pid and pid_start (the starting process and its start time, from `ps -o lstart= -p <pid>`, which BSD ps and procps both print), taken (UTC), token, and, once the runner is launched, worktree.
2. The token. The starting process makes one per start, from its machine, its pid and a random part, and hands it to each remote half. Each half that changes the host (the sweep, the start and the finish) first checks that the lock's token is its own, and refuses if not. So a lock broken while a start was between its ssh steps stops that start before it changes anything. send-pack checks nothing: it only adds a ref, and the start half after it checks.
3. Held across the steps. The take joins the first ssh call, _release_leg_remote_init, so it costs no round trip. init makes the bare repo, takes the lock, and answers `ready` or `held<TAB><the holder's lines><TAB><its run's state>`. The run's state is _release_leg_run_state's word (going, ended or gone) for the worktree the record names, read on the host, or `none` before launch. The lock stays on disk between the calls. The start half writes `worktree` into the record after it launches the runner.
4. Live or stale, decided on the starting machine from init's answer:
   - going: live, since its runner is alive. Refuse.
   - gone: stale.
   - ended or none: live while the starting process is alive. If machine is this machine's uname -n, it is live only when `ps -o lstart= -p <pid>` prints pid_start, and stale if not. If machine names another machine, it is live, untested. Refuse.

   A second remote call breaks a stale holder: _release_leg_remote_lock_break <project> <its token> <my record>. It renames the lock directory to <lock>.broken.<its token>, which only one breaker can do, takes the lock as in item 1, then removes the renamed copy. A breaker that loses the rename takes nothing and reads the lock again. The start warns once, naming the holder, and goes on. Its sweep then finishes the holder's run, as it does now.

5. The same commit. A start at the holder's commit whose starting process is gone breaks the lock as in item 4, then joins the run, as it does today. While that process is live, the start refuses as in item 6.
6. The refusal's word is `failed`, with the holder in its detail: "the host holds a run of <project> at <commit12>, started at <taken> from <machine>:<tree>, pid <pid>", and what ends it (item 8). legs_round reads failed as red at once, and every other word as one to wait on to the deadline, so legs_round does not change and lib/cmd/release keeps its one decision. A rehearsal reads failed as red too, and exits 1. A refused start changes nothing a run on the host reads: init took nothing, and no sweep or send-pack ran. The header's word list in lib/release.legs says that failed also answers a start the host's lock refused, which ran no gate.
7. Freed. A start that launches no run frees the lock before it answers: each failure after the take calls _release_leg_remote_unlock <project> <token>, which removes the lock only if the token is its own. A start whose ssh fails after the take cannot call it. Its lock then names its own process, and goes stale when that process ends. The run's own read frees it: _release_leg_finish clears the run, then the lock, by the run's token. The sweep that finishes a broken holder's run leaves the lock alone, since the new start holds it.
8. Freed by hand. No new verb. The refusal prints the by-hand step only for a holder that could not be tested, eg one that names another machine: ssh -n <host> 'rm -rf -- "$HOME/work/<project>-leg.lock"'. The next start's sweep finishes the run the lock named. For a live holder, the refusal names the holder and what ends it: for a going runner, wait for the run to end; for a starter alive on this machine, stop that process or wait for it. It prints no rm. A verb or a --break-lock flag would change the interface, which is ic's shape and hv's call.
9. Where it lives. lib/release.legs: the take in _release_leg_remote_init, _release_leg_remote_lock_break, _release_leg_remote_unlock, the token check as one function in RELEASE_LEG_REMOTE_SHARED for the sweep, start and finish halves, the local liveness test, and release_leg_start's and _release_leg_finish's calls to them. lib/cmd/release: the token, made once per process beside LEG_SHA. legs_round does not change. lib/pages/release.md and the leg host's ~/work layout name the lock. The note of the release that ships it says that a second start refuses, naming the run that holds the host.
10. The arms, ten in all, each red at the base, in releaselegs.bats on the fake hosts unless named:
    - a. A second start while a run is going answers failed, naming the holder, and leaves the host's refs, worktrees and cache as they were.
    - b. A holder whose starting process and runner are gone is broken: the start warns once, naming it, answers pending, and its sweep finishes the gone run.
    - c. A holder that names another machine refuses, untested, and names the by-hand step.
    - d. The same commit: refused while the starting process is live; joined, with the lock taken in its place, once that process is gone.
    - e. A start whose remote start half refuses frees the lock: the next start takes it with no break and no warning.
    - f. The run's read frees the lock: the lock is there, naming the worktree, while the run goes, and gone once the read finishes the run.
    - g. Two breakers of one stale lock: one takes it, and the other refuses, naming the first.
    - h. releasecut.bats: a cut whose kovacs start is refused stops red at once, naming the holder, and not at its deadline.
    - i. A refusal for a going holder prints the holder and no by-hand step.
    - j. An ended run, not yet read, whose starter is alive on this machine keeps the lock: a second start refuses, and the first cut's read then finds its own verdict and frees the lock.

    The liveness test reads pid_start with this machine's own ps. The GNU phase runs the arms under gnubin, and a kovacs leg runs them on procps. Existing arms that change: the 0361 going arm (a second start now refuses), the I0a62f4a own-commit retry arm (it joins only once the starter is gone), and every arm that starts twice at one host with no read between.

11. Size L: three new remote halves and a shared check; the take, break and free paths through release_leg_start and _release_leg_finish; a local liveness test; ten new arms; and changes to the existing two-start arms.

## Scope

Filed only, on hv's word "File it" (2026-11-27, through devbin-vc; vc watchout 40). Size L, accepted by devbin-vc. Its build is scheduled later, on devbin-vc's word, and it rides the devbin release after it lands. Until then the Desk keeps two starts of one project on one host apart, as devbin 0.1.35's note says.

## Provenance

Filed by devbin-cc on devbin-vc's word, after devbin 0.1.35's cut ended. The meaning is devbin-cc's word and the shape devbin-dc's. Both read lib/release.legs and lib/cmd/release at f257282e, read only, and ran nothing. The question first came up in devbin-cc's word on issue I0a62f4a (2026-11-26 18:43Z by date -u, item 2), where a lock was left as a unit of its own.

Resolution: Moved, not fixed: the leg-start lock is work package ST7c3a851/b4ffc553, not started, in thread ST7c3a851 for devbin's next release (hv's words of 2026-11-27, through devbin-vc). That package's body holds this issue's text.

---

_Generated by Intent v3 from the issue canon. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
