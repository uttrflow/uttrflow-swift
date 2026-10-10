# AI suggestions in a terminal: only what exists from here

An AI suggestion (tab-to-complete) in a terminal is a command somebody may run with one key. A
`cd` into a directory that is gone, a `cat` of a file in another project, a `git checkout` of a
branch this repository never had: each costs more than no suggestion at all. So before a terminal
line is drawn, from the corpus or from the model, `TerminalLineCheck`
(`Sources/UttrflowPredict/TerminalLineCheck.swift`) reads the whole line the way the shell would
and asks the disk whether everything it names is there. False negatives are accepted; a wrong path
is not. The parser is `ShellWords`, the disk `FileSystemProbing` and the refs `GitRepository`, all in
`Sources/UttrflowPredict`; the session test `RemoteSession` is in `Sources/UttrflowCore/Models`. What the machine offers before the
model writes is in [predict-agent.md](predict-agent.md).

## Who owns the prompt

`ShellPrompt` (`Sources/UttrflowContext/ShellPrompt.swift`) owns prompt parsing and heredoc
detection, and `FocusedFieldSnapshot.shellInput` is the one place either reader asks it. The
suggestion snapshot takes its `currentLine` from it; the dictation read takes its text before the
caret from it through `CaretText.inTerminal`. So dictation sees only the shell input, never
scrollback or the prompt, and a heredoc body or a full-screen program gives it no edges at all.

## Where it runs

`Verifier.admits` runs first in both paths to the screen:

- `Verifier.verified`, for remembered lines and the machine's own candidates, before any verdict.
- `Verifier.standing`, for every line the model wrote and the alternatives built from the
  machine's values in `SuggestionCoordinator.generate`.

A line refused here is simply not drawn. It is not superseded in the corpus, because a directory
that is missing today may exist tomorrow.

Two rules decide what runs where:

1. **A destructive line is never offered, in any field.** `DestructiveCommand.matches` reads the
   same parsed commands as the terminal path check and is asked of every line, whatever its evidence.
   Unresolved shell syntax is refused in every field, so a line the model writes is held to the same
   test as a learned or machine line; ordinary editor prose without shell syntax is not parsed as a
   terminal command. The same test keeps destructive lines out of the corpus (`CaptureGate`), so
   here it closes the lines the model writes and any older line already in the corpus.
2. **The path check runs only in a terminal**, meaning an application `TerminalApplications`
   names. An editor's document also has a directory for a scope, but its lines are prose, and a
   shell grammar would refuse all of them.

## What the check reads

`ShellWords` splits the line into simple commands, with quotes and backslashes undone, `~` and
`$HOME` expanded, and redirections set aside (a file read with `<` is kept and checked). A word the
shell would still rewrite — a glob, any other variable, `~name` — is marked unresolved. A line
with a subshell, a command or process substitution, a here-document or unbalanced quoting is
refused whole, since only running it could say what it names.

Then, per simple command, after leading assignments and wrappers (`sudo`, `doas`, `env`, `nice`,
`nohup`, `time`, `command`, `exec`, …) are read past:

| What | Must be |
|---|---|
| the command word | a builtin, an alias from the shell's configuration, or an executable file on the search path; a word with a slash, an executable file at that path |
| `cd`, `pushd` | one directory; with none, home; `cd -` and the directory stack are allowed but lose track of where the line is |
| `cat`, `less`, `more`, `head`, `tail`, `bat`, `wc`, `source`, `.` | every operand a file |
| `ls`, `du`, `tree`, `stat`, `file`, `diff`, `open`, `rm`, `rmdir`, the editors | every operand a file or a directory |
| `cp`, `mv` | every source; the destination may be new |
| `chmod`, `chown`, `chgrp` | every operand after the mode |
| `python3`, `node`, `ruby`, `sh`, … | the script, when no flag comes first |
| `grep`, `rg`, … | every operand after the pattern; a file named by `-f` or `--file` must exist as a file |
| `git checkout` | a branch, tag, remote branch or `HEAD` relative that the refs hold, or paths that exist; a new branch's start point |
| `git switch` | a local branch, or a remote branch of that name; with `-c` or `--detach`, a commit the refs hold |
| `git add`, `restore`, `rm`, `mv` | paths that exist |

Any other command's arguments are not judged. A trailing slash asks for a directory. Flags that
take a value (`head -n 5`, `open -a Safari`) have the value skipped, not checked.

**The working directory.** The terminal's directory is `Surface.scope`, which comes from the
field's `AXDocument` and otherwise from the window title. It is believed only when it is an absolute
path, or one from `~`, that names a directory that exists; otherwise it is unknown, and every
relative path is refused while absolute and `~` paths are still checked. A `cd` in the line moves
the directory for the commands after it when they surely follow it (`&&`, `;`); after `||`, `|` or
`&` the directory is unknown. `..` is folded lexically, as `cd` does.

**Branches.** `GitRepository` finds `.git` by walking up from the directory and follows a linked
worktree's `gitdir:` and `commondir` only when the common `.git` directory contains its admin
directory and the reciprocal `gitdir` points back to the worktree. It looks a ref up as a loose
file under `refs/` or a line of `packed-refs`. Commit selectors may add reflog (`@{...}`), peel
(`^{...}`), ancestry (`~n` or `^n`) or message (`:/...`) operators to a known ref or `HEAD`. A
repository whose refs live in a reftable, or whose `packed-refs` is over 8 MB
(`GitRepository.packedRefsLimit`), is not read, and its branch lines are refused. A commit hash is
refused too, since telling one from a typo means reading the object store.

## A session on another machine

After `ssh`, the shell that prints the prompt is not on this Mac. Its `AXDocument` is not updated,
so the terminal goes on publishing the directory the session started in, and everything that reads
`Surface.scope` then describes this disk while the line runs on another: the check above stats the
remote command's paths here, the machine index offers local files, branches and programs, and the
lines are remembered under the local directory's corpus.

So a terminal in a remote session is scoped as that session — `RemoteSession.scope`, which is
neither a path nor a host — rather than as a directory. Three things follow from the one change:
`EnvironmentSource.workingDirectory` finds no directory, so nothing here is listed or offered;
`Verifier.admits` refuses every line in that surface, because no question put to this disk could
stand behind one; and what is typed there is remembered under the session rather than under the
directory this Mac was left in. Nothing is stat'ed on the strength of a remote prompt.

**How the session is recognised, and how reliable that is.** `RemoteSession.scope(inWindowTitle:)`
reads the window title. A title naming `ssh`, `mosh`, `mosh-client`, `autossh`, `docker exec`,
`kubectl exec`, or `gcloud compute ssh` is scoped as remote (`RemoteSession.scope`). A `user@host`
title is remote unless its host matches one of this Mac's own host names. A path-like title such as
`~/.ssh` is not a remote program name, because a title's words keep path characters together.

The title cannot prove locality in every terminal configuration. A title that names neither a
remote command nor `user@` this Mac, and a terminal with no title, receive
`RemoteSession.unknownScope`. That opaque
scope is also refused by the verifier, so an overwritten remote title, a shell inside tmux or
screen, or an unfamiliar command cannot use this Mac's files, branches, programs, or remembered
lines. This withholds terminal suggestions in a local terminal whose title does not show
`user@host` for this Mac; that is the cost of not treating an uncertain machine as this one.

A process check is not used: the terminal process is the shell, not the program that shell runs,
and inspecting its descendants would require access beyond the window title.

## tmux and screen panes

A tmux or GNU screen client presents its panes inside one terminal window and one Accessibility
text area. The document directory exposed there belongs to the outer terminal process; it does not
identify the pane currently under the caret. Pane switches therefore cannot safely reuse that
directory for path checks, branch lookups, machine candidates, or corpus identity.

A title that names `tmux` or `screen` and not `user@` this Mac provides no trustworthy machine
identity, so the field receives `RemoteSession.unknownScope`. The verifier refuses terminal lines, no local
directory index is queried, and observations stay outside the outer directory's corpus. A pane's
filesystem cannot be inferred from the outer terminal's Accessibility document.

## What it never does

It never runs a program. Everything it knows comes through `FileSystemProbing`: a `stat`, an
`access(X_OK)`, a bounded read and a lazy directory walk that stops at its result limit or when the
turn is cancelled. The test double records every question and visited name, and
the tests hold that a line the check refuses reaches the machine index only for the shell's
aliases, which are read from its configuration as text. The machine index's branch list is read
from the same refs, so no `git` process is started for branches either. A line the check lets
through still goes on to the verdicts in `Verifier`, whose verb lookups are the machine index's
own ([predict-agent.md](predict-agent.md), "The tools").

It never lists a directory to check a path; a path is one `stat`. The only listing is
`refs/remotes`, which holds a handful of names.

## Cost

Measured on an Apple silicon Mac under heavy load (load average above 20), on a directory of
10,000 entries (9,000 files and 1,000 directories), seven lines per turn:

| | Per turn |
|---|---|
| `TerminalLineCheck`, uncached | 0.29 ms |
| the same through `CachedFileSystem` | 0.13 ms |
| `git checkout main` from inside a worktree, uncached | 0.10 ms |
| for comparison, the machine index listing that directory's files | 29 ms |
| and its directories, one `stat` per entry | 41 ms |

`CachedFileSystem` believes a stat or a small read for `lifetimeInSeconds` (2 s). A path on
`/Volumes`, `/Network` or `/net` is stat'ed on a queue of its own and waited for `remoteBudget`
(20 ms); a volume that misses the deadline is answered `unknown`, which refuses the line, and is
left alone for `slowVolumeLifetimeInSeconds` (30 s).

## Fixtures

`uttrflow-bakeoff complete --fixtures --only terminal`, Release, Gemma 3 4B from disk, 256 cuts.
`Grounding` stands each fixture on a `FixtureDisk` built from its machine.

| | Hit | Precision (wrong shown) | Coverage | p50 |
|---|---|---|---|---|
| without the check | 247 | 96.77 % (8) | 96.88 % | 166 ms |
| with the check | 239 | 97.07 % (7) | 93.36 % | 136 ms |

Every one of the eight hits the check costs is a first line it refuses because running it would
fail or harm: `cat docs`, `tail logs`, `tail -f logs`, `cat ~/Desktop` and `node public` stop at a
directory where a file is needed; `cd ~Projects` names a user's home that is not there;
`cat projects/api/README.md` names a file the fixture's disk does not hold; and
`kubectl delete api` is destructive. The catalogue counts a line ending on a whole word of the
right answer as a hit, which is why they count without the check.

## Limits, each a false negative

- A shell function, a `CDPATH` entry, or a program installed somewhere the search path does not
  name (the launch `PATH`, `/etc/paths`, `/etc/paths.d` and the usual install directories) is
  refused.
- A glob or a variable in a checked position refuses the line, even where it would match.
- A local terminal whose title does not show `user@` this Mac is offered nothing, and a title
  whose words include `ssh` or `mosh` is read as a remote session.
