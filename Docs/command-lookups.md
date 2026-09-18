# Command lookups in a terminal

Tab-to-complete checks the verbs a model offers for a command (`docker compose`, `cargo build`)
against what the program on this Mac says it accepts. That answer comes from running the
program once and reading its help. This page is where and how that run happens.
`Sources/UttrflowPredict/ProgramLauncher.swift` and `Sources/UttrflowPredict/CommandLookup.swift`
hold the rules; `Sources/UttrflowPredict/EnvironmentReading+System.swift` asks for them.

## Where a lookup runs

**Never in the terminal's folder.** Many command-line tools read settings from the folder they
start in and the folders above it, and some hand over to a version of themselves pinned by that
folder. A lookup is a question about the installed program, so it runs somewhere that answers
nothing: a fresh directory under the temporary directory, created empty for each run, readable
only by this user, and removed afterwards. `ProgramLaunch` has no working-directory field, so a
caller cannot choose one.

## Which programs run

- **Verbs of a named program** (`--help`, `cargo --list`, `brew commands --quiet`, `npm help`):
  only a bare name, looked up in `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/opt/homebrew/bin` and
  `/usr/local/bin`. A name with a `/` or a leading `.` is refused, as is any directory with a
  `node_modules` component or inside the terminal's folder, and any program whose resolved path
  lies inside that folder. Nothing a project ships is run.
- **git**: from its fixed install locations only. The verb list runs without a repository.
  Aliases read `git -C <folder> config --get-regexp`, which reads configuration and runs nothing.
- **Makefile targets and `package.json` scripts** are read as files; neither `make` nor a package
  manager runs.

## The environment

A lookup inherits nothing from this process. It gets `PATH` (the directories above), `HOME`,
`NO_COLOR=1`, `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `GOTOOLCHAIN=local` and
`COREPACK_ENABLE_NETWORK=0`. Standard input is `/dev/null`; every descriptor other than the
output pipe is closed in the child.

## Bounds

The program starts as the leader of a new process group. Its output is read as it arrives,
against a deadline that starts at launch: 0.5 s for git, 2 s for help. At the deadline, or past
1 MiB of output, the whole group is killed, and the lookup has no answer. When the program exits
while something it started still holds the pipe, what it wrote is kept and the group is killed.
A lookup with no answer leaves the words it would have checked unverified, never refused.
