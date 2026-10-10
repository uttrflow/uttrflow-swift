# Watching the heap over hours

`Scripts/soak.sh` (`make soak`) answers one question about a running Uttrflow: **is something
accumulating?** It samples the process's heap on a clock and reports which object classes grew
between the first sample and the last. It exists for one crash class: a deinit cascade deep
enough to exhaust a thread's stack, entered when a long-lived object is released (the dictation
keyboard's `stop()` on the quit path is where it shows). A cascade needs a chain, and a chain
long enough to overflow a stack is built over hours of use, so the thing to watch is a
duration, not a gesture. A fresh session does not reproduce it.

```bash
make soak                                  # 6 samples, 10 minutes apart
./Scripts/soak.sh --every 60 --times 30    # half an hour, finer
./Scripts/soak.sh --pid 1234               # a process other than the first `Uttrflow`
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--every` | 600 | Seconds between samples. |
| `--times` | 6 | Number of samples. |
| `--pid` | first `pgrep -x Uttrflow` | The process to watch. |
| `--compare FIRST LAST` | none | Print only the growth report for two saved samples; what `make soak-test` exercises. |

Leave the app running and **used** while it samples: dictations, the clipboard, and
suggestions switched on. A soak against an idle app measures an idle app.

## What it reports

Each sample is `heap <pid>`, reduced to a count per class, kept as
`dist/soak-<timestamp>/sample-<n>.tsv`, with the physical footprint and live node count
appended to `footprint.tsv`. At the end it prints the twenty classes that grew most between the
first and last sample, comparing the union of class names so a class that appeared or vanished
counts as zero on the other side, then the footprint over the run.

**A count that only ever rises is the answer.** One class climbing while everything else moves
about is the chain; that class is one end of it, and whatever frees the head of it is the other.

A chain need not be a class `heap` can name. Closure contexts are the example: a bare closure
kept in a `Mutex` and read out through `withLock`'s `inout` is re-wrapped in a reabstraction
thunk and written back, so every read adds a layer, and releasing the last reference frees the
layers recursively. `SystemKeyboard` therefore keeps its keystroke sink as a struct holding
the closure (`Sink` in `Sources/UttrflowInput/SystemKeyboard.swift`), and the sink is copied out
of its lock, called and released, never written back.

## The tests that guard the keyboard

A soak cannot measure stack depth; these tests do, in `Tests/UttrflowInputTests/`:

| Test | What it holds |
| --- | --- |
| `SystemKeyboardDeliveryTests` | The 500th keystroke reaches the sink no deeper in the stack than the first, and releasing the sink after 500 keystrokes frees it no deeper than after one. |
| `SystemKeyboardTeardownDepthTests` | 120,000 real `CGEvent`s (a six-event press, release and typing sequence, 20,000 times) through the real tap callback, `Delivery` and `ActivationMonitor`, then the quit path's `stop()`, all on a 64 KiB thread. Stack growth from first keystroke to last stays under 4 KiB, and no keystroke arrives after `stop()`. |

With the sink put back as a bare closure in the `Mutex`, `SystemKeyboardTeardownDepthTests`
kills its process with `SIGBUS`, the same signal as the field crash, so a chain of that kind
cannot return unnoticed.

Two facts bound where else a chain can come from. Nothing on the keystroke path allocates per
keystroke: the only allocations are per start (the tap, its thread, the sink) and per press
(the reconciliation timer), and each replaces the one before. And a finished `Task` releases
what it captured, so the task chains elsewhere in the app
(`let previous = task; task = Task { await previous?.value }`) unwind as they complete. Release
builds keep their dSYM beside the bundle (`Scripts/bundle.sh`), which is what symbolicates a
field report's frames against the exact binary.

## What it cannot tell you

It counts objects; it does not say who retains them. Once a class is named, the next step is
`MallocStackLogging=1` and `malloc_history <pid> -allBySize`, or Instruments' Allocations
template with a generation marked before and after. Those give the allocation backtrace, which
turns "this is growing" into "this is what holds it".

It also cannot prove a fix. A run that stays flat for an hour is evidence, not a guarantee; report
the numbers rather than a verdict.

## Why it is not part of any gate

It takes hours, needs a real windowing session, and measures a process nobody is driving unless
somebody is. `make bench` runs only `make soak-test`, which checks
the growth report against fixtures. A soak is run deliberately, at a machine.

Related: [ui-tests.md](ui-tests.md) (driving the real app), `Docs/performance.md` (memory
budgets and the leak check in `uttrflow-bakeoff profile`).
