# Tab-to-complete: the machine as the agent's tools

Two ghosts set this plan. In a terminal whose working directory was `backend`, `cd
projects/x-growth/` drew `backend/` — a line the model read in the scrollback, correct from
Desktop, false from here. `vim .env` drew `.vim`, a file the model invented in a directory it was
never shown. Both came from the model (`corpus=0` → `GENERATE`), and both are the same failure:
a suggestion that was never checked against what is true on this Mac.

The operator's demand is the right one: classify first, know the working directory, list it, and
only then let a model write — a suggestion that is wrong is worse than none. This document is the
plan for that, precise about what exists and what changes, with the latency bar unchanged: a
suggestion lands well under a second after a pause.

## What exists

- **A machine index.** `EnvironmentReading+System` reads, per working directory, the files in it,
  the git branches of its repository, the executables on `PATH` and the shell's aliases;
  `EnvironmentIndex` caches each answer with a time to live; `EnvironmentSource` offers matching
  values as candidates when the corpus has none. All of it is tested against a substitute machine.
- **An attestation gate.** `Verifier` passes every *remembered* line through it: the last word of the
  line is looked up among the machine's values for the kinds that position may hold, and a line
  the machine vouches for skips the model's plausibility score. `Verification.attestingKinds(for:)`
  decides those kinds by position alone — the first word is a program or an alias, any later word
  a branch or a file — and `Verification.isClosedVocabulary` says which kinds are complete enough
  that an unknown word is wrong rather than new.
- **A generation path** that runs when the corpus and the machine offer nothing, with the line
  written into the model's turn and `TokenHealing` holding its first tokens to the typed word.
  Its output is drawn as the model's own and is judged by nothing.

The gap is exact: the machine is asked *before* the model as a source, never *after* it as a judge,
and it does not know that `cd` takes a directory or that a path with a slash names a subtree.

## The shape: classify → tools → one constrained pass → verify

This is an agent in the sense that matters — the situation chooses the tools, the tools' answers
shape the model's, the answer is checked — with two differences from an LLM agent loop. The tools
are deterministic Swift functions that answer in microseconds, and the model runs once, constrained
to real values where the values are known. A plan → tool → answer loop on the 4B model is two or
three passes, 1.5–3 s, before the first keystroke of context; the frameworks that run such loops
(LangGraph, CrewAI, the OpenAI and Anthropic agent SDKs) are Python or cloud-bound; Apple's
on-device `Tool` protocol sits on a model that scored 41 % on this catalogue (`predict-llm.md`).
None fits an offline Swift keystroke loop, and everything they add — routing, tool results as
context, checked answers — the five stages below provide without a second pass.

| Stage | Budget | What it does |
|---|---|---|
| Classify | < 1 ms | `LineShape`: the command, the argument position, the argument's kind — directory, file, branch, subcommand, executable, or free |
| Tools | < 5 ms cached | the machine's values of that kind for this working directory, a path prefix resolved against it, git subcommands and branches |
| Constrain | one pass, 600–800 ms | a closed kind with values: the model ranks among them, held to them byte by byte by the logit processor already in place; a closed kind with none: nothing, for a named reason; a free kind: today's generation |
| Verify | ~1 ms | every generated line of a closed kind through the attestation gate; an argument the machine does not know is rejected before it is drawn |
| Measure | catalogue | a `terminal/cwd` set against a substitute machine, with a new metric that must read zero: invented arguments |

## The steps

**A4 — Verify what the model wrote (first, because it stops the lies).** In `SuggestionCoordinator.generate`,
before a generated line is settled, the verifier attests its last word the way it attests a
remembered line's. A word of a closed kind — a program, an alias, a branch, a file where the
machine has listed the directory — that the machine does not know is dropped; when nothing is left
the turn is quiet for the reason `notOnThisMachine`. Free kinds and prose pass untouched. Tested
against the substitute machine: `vim .env` + `.vim` in a directory holding `.env` yields nothing;
`git checkout ma` + `in` with a `main` branch is kept; a word in a prose field is never asked about.

**A1 — Classify the line.** A pure `LineShape` in `UttrflowPredict`: from the typed line, the
command word, the argument position, and the kind that position holds. The command table is data
in one place, of the kind `zsh`'s completion system keeps: `cd`, `pushd`, `rmdir` take directories;
`vim`, `cat`, `source`, `open`, `less` take files; `git checkout`, `git switch`, `git merge`,
`git rebase` take branches; `git`, `docker`, `kubectl`, `npm`, `make`, `brew` take a subcommand
first. An unknown command's arguments are files or free. Prose registers are free everywhere.
`Verification.attestingKinds(for:)` reads the kind from the shape instead of the position.

**A2 — Two more tools.** Directories under a path prefix, resolved against the working directory,
so `projects/x-growth/` from `backend` yields an empty set — which is the answer — and `..` and
`~` resolve as the shell would; and the subcommands a program advertises where they can be read
cheaply (git's, from its own completion list; docker's and kubectl's from their help, cached for
the session). Same per-directory cache, same budget.

**A3 — One constrained pass.** For a closed kind with values, the pass is given the values in the
prompt and `TokenHealing` is generalised from "hold the first tokens to the typed word" to "hold
the continuation to one of these strings", so the model chooses and orders among real directories
or branches and can write nothing else. The alternatives list is the remaining values in the
model's order. Where the kind is closed and the tool returned nothing, no pass runs.

**A5 — Measure it.** A `terminal/cwd` catalogue set whose fixtures carry a substitute machine:
paths that exist and paths that do not, a stale scrollback line, `cd` into a subtree, `git
checkout` with real branches, `vim` of a file that exists and a name that does not. The scorecard
gains the column *invented arguments* — completions naming a file, directory, branch or program
the machine does not have — and it is held at zero.

**A6 — A slower second opinion, measured last.** Where a free-kind line has no suggestion after a
second, an agentic pass — Apple's on-device model with tools, or a framework-driven local loop —
may refine it and replace the ghost; the person never waits for it. Whether it earns its place is
a measurement, not a foundation.

Order: A4, then A1 with A2, then A3, A5 beside each, A6 at the end. Each step is gated and
recorded in `predict-reliability.md`.

## Where it stands

- **A1 — done, 2026-09-05.** `LineShape.of(token)` reads the last simple command (after `&&`, `|`, `;`,
  through `sudo`, `time`, `nohup`), drops flags from the count, and gives the word a kind from
  `CommandGrammar`: directory commands, file commands, pattern commands, programs with verbs, git's
  branch and path verbs, `make`'s targets, a runner's `run` scripts. Attestation, the machine's own
  candidates and the verifier's kinds all read the shape; an unknown command's arguments are free.
- **A2 — done, 2026-09-05.** `EnvironmentKind` gained `entries(under:)`, `directories(under:)` and
  `subcommand(of:)`. A path is resolved from the terminal's directory as the shell resolves it and its
  last name looked up under the directory before it; verbs are read from the program itself (git's
  command list, the Makefile, `package.json`, `--help` for docker, kubectl, gh and the rest, `cargo
  --list`, `brew commands`). A reader answers `nil` for a failure and `[]` for a directory that is not
  there, and the index keeps both, so a missing directory denies every name and a program that would
  not list its verbs denies none. `uttrflow-dev machine --directory … --under …` prints it all.
- **A3 — done, 2026-09-05.** `Verifier.options(for:in:now:)` runs before a pass: `.open`, `.among`
  (whole values beginning as the typed word does, capped at 40) or `.none` (quiet, `notOnThisMachine`,
  no pass). For `.among` the prompt names the values and `TokenChoice` holds the decode to one of
  them, byte by byte, freeing the model once a value is written whole; the other values are the
  alternatives, with no second pass. A path ending in its slash offers what is under it; a branch
  prefix offers the branches under it too; a word already whole and known is open.
- **A5 — done, 2026-09-05.** `terminal/cwd` (15 lines, 47 cuts) and `terminal/cwd-absent` (7 whole
  lines whose right answer is nothing) stand on a substitute machine; `Grounding` in the bakeoff asks
  it before the pass and sieves after, as the app does, and every result records `invented`. Run 3
  of the set: 53/54 hit, 54/54 in register, **invented 0**; the one miss is `git s` → `git stash`, a
  real verb the fixture did not want. Run 1 of the set found the whole-line bug in A4 (see
  `predict-reliability.md`), which is what the set is for. The four older terminal scenarios (git,
  containers, node, shell) now stand on machines too — the api service, the web project and a home
  directory — so every terminal fixture is grounded: 248/256 hit, invented 1 (`node scripts` →
  `scripts/build.mjs`, a whole known directory left open and then finished with a file that is not
  there). Grounding them found three more things to fix, recorded in `predict-reliability.md`: refs
  denied as branches, `~` and `.` denied as names, and a runner's `run` freed before its script.
- **A6 — measured, 2026-09-05, and not wired.** `uttrflow-bakeoff complete --second-opinion` spends the
  wider alternatives pass wherever the first pass leaves nothing and records what it rescues and
  what it costs. Over run 7's 80 misses it was spent 7 times (the 7 empties in 1 154 cases, 0.6 %),
  rescued 3 (`git l` → `git log -p`, `npm i` → `npm install` twice) at a median 887 ms more, one at
  2.7 s. All three are verbs a real Mac lists, so on a grounded field the constrained pass has them
  already; the two `to` notes and the two addresses stayed empty. A second pass that rescues nothing
  the machine would not have given, on one turn in a hundred and sixty, at a second's cost, does not
  earn a place in the loop; the flag stays in the bakeoff so the question can be asked again when the
  free-kind misses change. Apple's model with tools was not tried: at 41 % on this catalogue it would
  have to be measured against nothing, and the same measurement applies.
- **A4 — done, 2026-09-05.** `Verifier.standing(_:after:in:now:)` takes every word a generated line
  adds (`Verification.words`) and asks the machine what it can deny (`Verification.attestation(for:)`):
  the first word among programs and aliases, git's second word among its subcommands and aliases, a
  path from here by its first name and a dotfile by name among the files listed. A word the machine
  has listed nothing like drops the line; when every line is dropped the turn is quiet for
  `notOnThisMachine`, and the log names what was dropped (`ATTEST … dropped=`). Until A1, a flag, a
  number, a quotation, an expansion, an address and a plain argument are not asked about, since
  position alone cannot say whether `npm observe` names a file; a machine that has not answered yet
  denies nothing. The alternatives behind the drawn line go through the same gate.
