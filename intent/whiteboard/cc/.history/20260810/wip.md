# cc -- archived 2026-08-10 (evening)

Rolled out of the live board at the day's second globalfold. Everything below was the DOING/TODO state after ST0002 closed; the items that closed later the same day are marked.

## Resolved after this was written

- **Riffle's 22 credo findings -- CLOSED.** The trigger fired: the concurrent session quiesced and `bin/riffle test all` seals green on both arms. The list below was never worked from, which is exactly what a trigger-based deferral is for.
- **Prolix's Dockerfile -- CLOSED** on hv's ruling. All three toolchain rows now name one compiler. Unbuilt: Docker was not running.
- **Prolix CI's credo step -- CLOSED.** `--only error` is now `--strict`, possible only because the real gate reached zero.
- **Prolix ST0028 -- HALF CLOSED.** Gates half done, dependency half not started.

---

## DOING

- **Nothing. ST0002 is CLOSED, 25/25 satisfied, and it was this node's only claim.** Four projects migrated (MicroGPTEx fresh; arca_config, arca_cli, Prolix by `scripts/` migration), two cancelled (Multiplyer EOL, Molt is the product), two parked (Utilz, Pplr).

## TODO

- **ST0002 is CLOSED (25/25) and this node holds no claim.** Next work is hv's to set.
- **PICK UP WHEN RIFFLE'S OTHER SESSION QUIESCES: fix Riffle's 22 credo findings.** hv ruled 2026-08-10, twice -- first "fix these inline now", then "fair, leave it until the other session quiesces" once told what was in flight, and then "when it does, we'll pick it up". So this is DEFERRED, not dropped, and the trigger is that session going idle rather than a date.
  - **Done already** (`fb3e34a`): credo added to `mix.exs` and `.credo.exs` written from arca_config's, disabling `Credo.Check.Design.AliasUsage` alone -- 44 of the original 66 findings, the same check and the same reason as arca_config's 129 of 139. The gate RUNS now: 68 checks over 42 files, where before it died with "the task credo could not be found".
  - **Left**: 22 real findings, 10 refactoring and 12 readability -- roughly 5 alias ordering, 4 explicit `try`, 3 `apply/2,3` with a known arity, 3 cyclomatic complexity, and the remainder. They sit in `lib/riffle/predicate/*`.
  - **Why not now**: that is exactly what the other session is refactoring (focus "PFIC transform + hydration consolidation"), it had `lib/riffle/predicate/dsl/macro.ex` and `test/riffle/predicate/dsl/loader_test.exs` modified and `statements.ex` newly created, and its MIX arm was RED at 282/284 with two failures in flight. **Those two failures are ITS work, not a regression** -- the same tree ran 282 passed and clean three minutes earlier, before its edit landed.
  - **On pickup**: re-run `bin/riffle test credo` first rather than working from the list above. Its refactor is in the same files and will have moved the findings.
- **Riffle now runs devbin** (launcher `bin/riffle`, elixir declared, doctor 8/0). It is NOT part of any thread -- it was a drive-by off hv's question about a capitalised launcher, and it produced devbin issues 0012 and 0013.
- **hv owes a deploy at Prolix.** The Oban v13->v14 migration reaches prod via `fly.toml`'s `release_command` on the NEXT deploy, not before. Until then the deployed app runs the old schema.
- **hv owes three credential decisions at Prolix, and it is a PATTERN not three items.** `bin/.devbin/cmd/flysql` (geodica-db, already ruled: proceed as if rotated, rotate the sharing projects together later); **NEW and not covered by that ruling** -- `config/.env` is TRACKED and holds a live MailerSend API token, and `priv/repo/seeds_prod.exs:2` carries the prolix database password in a comment. The APNs signing key was checked and is fine. All in `intent/st/COMPLETED/ST0002/WP/08/equivalence.md` and mirrored into Prolix ST0028.
- **hv's call: Prolix's Dockerfile trails the pins.** `check toolchain` is red on the image arm -- pins 1.20.3/29.0.5, the image builds 1.19.3/28.2. Deploy-affecting, and it would land on the same deploy as the Oban migration.
- **hv's call: Prolix CI's credo step examines nothing.** `mix credo --only error` runs 0 checks over 267 files and reports "found no issues". Third project in the fleet with it. Left alone because the real gate is red at 228 and sizing that is the arca_cli call again.
- **Prolix ST0028** (Not Started): nine constraint-blocked majors, 11 compile warnings, the Dockerfile half of the toolchain, plus the five findings above. hv returns to it.
- **The fleet's `log:` restatements are now redundant.** Issue 0011 made a config `run:` inherit the catalogue's seal suffix and grammar, so Conflab, Laksa, Baize, Lamplight and arca_config no longer need to restate `log:` beside every overridden gate. No urgency and no obligation -- they are identical values today. Drop them at each project's next touch.
- **The fleet is not re-vendored.** Only Prolix has issues 0010 and 0011. Everyone else takes them at their next `devbin upgrade`; nothing is broken until then, and 0011 cannot bite a project that restates `log:`.
- **Deploy-build proofs pending, owner-run**: Conflab `317fb67c`, Laksa `84a264d9`, Lamplight `cb5d3948a` moved deploy images to registry-verified tags; each proves itself at its next `fly deploy`.
- Baize dirt for a Baize-side ruling someday: `db reset` rides the root `mix setup` alias its own `db setup` documents avoiding.
- Unfiled tenth-candidate, low: `upgrade --force` counter reporting (noted in closed issue 0008).
- Issue 0004 remains OPEN (session-gate docs vs reality); half upstream in Intent's templates.

