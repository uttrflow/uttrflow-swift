# AI suggestions in a terminal: the machine as the model's tools

In a terminal, an AI suggestion (tab-to-complete) is checked against what is true on this Mac
before the model writes and again after. The line is classified (`LineShape`, `CommandGrammar` in
`Sources/UttrflowPredict/LineShape.swift`), the machine is asked for the values the next word may
take (`EnvironmentReading+System.swift`, cached by `EnvironmentIndex` in `EnvironmentSource.swift`),
the model is held to those values where they are known (`TokenChoice` in
`Sources/UttrflowLocalModel/TokenHealing.swift`), and every word the model adds is attested before
the line is drawn (`Verifier.options`, `Verifier.standing`). A suggestion that is wrong is worse
than none: a `cd` into a directory read from stale scrollback, or a file the model invented, is a
command somebody may run with one key.

The whole-line path check that runs before this is [predict-terminal-paths.md](predict-terminal-paths.md);
how the machine's programs are run safely is [command-lookups.md](command-lookups.md); the loop and
the gates are in [predict.md](predict.md).

The verifier's remembered decisions live in `VerificationSession`, whose generation invalidates
captured `VerificationOperation` values when it forgets. An operation holds its field and exact
whole-line refusal identity; the actor retains deadlines, corpus-write draining and retries.
`EnvironmentVerification` owns listing unions, completeness and per-kind case rules. Capture and
publication use one operation per batch and compare probes with live session state; its production
metadata mode is disabled, so capture, revision checks and reset perform no alias-body reads.

## The shape: classify → tools → one constrained pass → verify

| Stage | Budget | What it does |
|---|---|---|
| Classify | < 1 ms | `LineShape.of(token)`: the command, the argument position, the argument's kind (`ArgumentKind`: program, subcommand, directory, file, branch, branch-or-file, or free) |
| Tools | < 5 ms cached | The machine's values of that kind for this working directory, a path prefix resolved against it, git subcommands and branches |
| Constrain | one pass | A closed kind with values: the model ranks among them, held to them byte by byte; a closed kind with none: no pass, quiet for `notOnThisMachine`; a free kind: ordinary generation |
| Verify | ~1 ms | Every word a generated line adds goes through the attestation gate; an argument the machine does not know drops the line |

The tools are deterministic Swift functions, and the model runs once. A plan → tool → answer loop
on the 4B model is two or three passes, 1.5–3 s, before the first keystroke of context, so a
multi-pass agent loop is not used; the stages above give routing, tool results as context and
checked answers without a second pass.

## Classifying the line

`LineShape.of(token)` reads the last simple command (after `&&`, `||`, `|` or `;`), past leading
assignments and wrappers (`sudo`, `doas`, `time`, `nohup`, `env`, `exec`, `command`, `nice`, …),
drops flags from the count, and gives the next word a kind from `CommandGrammar`, which is data in
one place:

| Commands | `CommandGrammar` set | The word is |
|---|---|---|
| `cd`, `pushd`, `rmdir` | `directoryCommands` | A directory |
| `ls`, `cat`, `vim`, `open`, `rm`, `cp`, `mv`, `tar`, `rsync`, … | `fileCommands` | A file or directory |
| `python`, `node`, `ruby`, `sh`, … | `interpreters` | A script first, unless a flag names what to run |
| `grep`, `rg`, `ag`, … | `patternCommands` | A pattern, then files |
| `git`, `docker`, `kubectl`, `npm`, `brew`, `cargo`, `gh`, `swift`, `terraform`, … | `subcommandPrograms` | One of the program's verbs first |
| `make`, `just` | `targetPrograms` | A target the project declares |
| `npm`, `yarn`, `pnpm`, `bun` `run` | `scriptRunners` | A script the project declares |
| `git checkout`, `switch`, `merge`, `rebase`, `branch`, `cherry-pick` | `gitBranchVerbs` | A branch |
| `git log`, `diff`, `reset` | `gitBranchOrFileVerbs` | A branch or a file |
| `git add`, `rm`, `mv`, `restore` | `gitFileVerbs` | A path |

An unknown command's arguments are free. Prose registers are free everywhere. Attestation, the
machine's own candidates and the verifier's kinds all read the same shape.

## The tools

`EnvironmentKind` names what the machine can list: `executable`, `alias`, `branch`, `gitAlias`,
`entries(under:)`, `directories(under:)` and `subcommand(of:)`. A path is resolved from the
terminal's directory as the shell resolves it (`..` and `~` included), and its last name is looked
up under the directory before it, so `projects/beacon/` from a directory holding no `projects`
yields an empty set — which is the answer.

Verbs are read from the program itself: git's command list, the Makefile, the justfile,
`package.json`, `cargo --list`, `brew commands --quiet`, `npm help` and `--help` for the rest. The
branch list includes tags and remote branches beside local ones, read from the refs on disk. A
reader answers `nil` for a failure and `[]` for a directory that is not there, and the index keeps
both, so a missing directory denies every name and a program that would not list its verbs denies
none. `EnvironmentIndex` believes a directory's answer for `lifetimeInSeconds` (5 s) and a program's
verbs for `programLifetimeInSeconds` (60 s).

Internal alias snapshots derive expansions and uncertainty from one read of the existing shell
configuration files. Expansion names and bodies retain at most 200 entries and 64 KiB of UTF-8
content; finite integer flags mark shaped-command shadows and uncertain chains by retained-map
position. These flags have at most one position per grammar member and per retained alias; their
fixed integer overhead is separate from the UTF-8 content budget. Unsupported or omitted bodies
cannot certify a command grammar, while an unrelated
unsupported alias leaves an unshadowed command certain. Text and flags share refresh, revision,
expiry and forgetting. The metadata overload of `LineShape.of` distinguishes uncertainty from a
known free slot, records whether an alias supplies the grammar, and resolves supported aliases
before wrappers; the dictionary overload keeps
its existing contract. `EnvironmentIndex` owns an injected metadata provider and settles and
forgets that provider; its default owner does not opt into configuration reads.

`uttrflow-dev machine --directory <dir> --under <path>` prints everything the index lists there.

## Choosing among the machine's values

`Verifier.options(for:in:now:)` runs before a pass and answers one of three things
(`ArgumentOptions`):

- `.open` — the model writes freely: the field has no working directory, the word is free, the word
  is already whole and known, or a relevant listing has not answered yet.
- `.among(values)` — whole values beginning as the typed word does, sorted shortest first and capped
  at `Verification.mostChoices` (40). The prompt names the values and `TokenChoice` holds the decode
  to one of them, byte by byte, freeing the model once a value is written whole; the other values
  are the alternatives, with no second pass.
- `.none` — every relevant listing answered and nothing begins that way, so no pass runs and the turn
  is quiet for `notOnThisMachine`.

A word not yet begun is not offered hidden names. A path ending in its slash offers what is under
it; where a branch is wanted, a prefix ending in a slash also offers the branches under it
(`feat/` → `feat/login`). Where a runner's scripts are listed, each `run script` is offered whole
and bare `run` is not, so the choice covers both words.

## Attesting what the model wrote

`Verifier.standing(_:after:in:now:)` takes every word a generated line adds past the typing
(`Verification.words(of:addedAfter:)`) and asks the machine whether it can deny it
(`Verification.attestation(for:)`): a program or alias in the command position, git's second word
among its subcommands and aliases, a path from here by its first name, a dotfile by name among the
files listed, and each argument by the kind its position holds. A word the machine has listed
nothing like drops the line; when every line is dropped the turn is quiet for `notOnThisMachine`,
and the log counts what was dropped (`ATTEST … dropped=`). A ref form (`HEAD~1`, a tag, a hash,
`origin/main`) is git's to accept, not the branch list's to deny; a lone `~` is free; `.` after a
directory command is open. A listing that has not answered yet vouches for nothing, and only the
disk itself may confirm a word meanwhile. The alternatives behind the drawn line go through the same
gate. `Verification.isClosedVocabulary(for:)` says whether the listed kinds are complete enough that
an unknown word is wrong rather than new, which decides whether a refusal is written to the corpus.

## Measured

`uttrflow-bakeoff complete --fixtures --only terminal/`, Release, Gemma 3 4B. `Grounding` in the
bakeoff (`Sources/uttrflow-bakeoff/Grounding.swift`) stands each fixture on a substitute machine,
asks it before the pass and sieves after it as the app does, and every result records `invented`:
a completion naming a file, directory, branch or program the machine does not have.

| Set | Cases | Hit | Invented |
|---|---|---|---|
| `terminal/cwd` (`CatalogueCwd.swift`): paths that exist and do not, stale scrollback, `cd` into a subtree, real branches, `vim` of a real and an absent file | 54 | 53 | 0 |
| Every terminal scenario, each grounded on a machine | 256 | 248 | 1 |

The one `terminal/cwd` miss is `git s` → `git stash`, a real verb the fixture did not want. The one
invented line is `node scripts` → `scripts/build.mjs`: a whole known directory left open and then
finished with a file that is not there.

**A slower second opinion is not used.** `uttrflow-bakeoff complete --second-opinion` spends the
wider alternatives pass wherever the first pass leaves nothing. Over 1,154 cases it was spent 7
times (0.6%) and rescued 3 (`git l` → `git log -p`, `npm i` → `npm install` twice) at a median
887 ms more, one at 2.7 s. All three are verbs a real Mac lists, so on a grounded field the
constrained pass already has them.
