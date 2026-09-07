# Watching the heap over hours

`Scripts/soak.sh` exists for one question, and it is the question #140 could not answer by
reading code: **is something accumulating?**

Both crashes in that issue are a deinit cascade deep enough to exhaust a thread stack, entered
from `DictationController.stop()`. A cascade needs a chain, and a chain long enough to blow a
stack has to be built over time. Neither crash reproduced on a fresh session — the two processes
that died had been running for two hours and nearly thirteen. So the thing to look at is not a
gesture but a duration.

```bash
make soak                                  # 6 samples, 10 minutes apart
./Scripts/soak.sh --every 60 --times 30    # half an hour, finer
./Scripts/soak.sh --pid 1234
```

Leave the app running and **used** while it samples — dictations, the clipboard, and suggestions
switched on, since the longer-lived crash had them enabled. A soak against an idle app measures
an idle app.

## What it reports

Each sample is `heap <pid>`, reduced to a count per class and kept in `dist/`. At the end it
prints the classes that grew most between the first sample and the last, with the footprint and
the live node count beside them.

**A count that only ever rises is the answer.** One class climbing while everything else moves
about is the chain; that class is one end of it, and `ActivationMonitor` and `SystemKeyboard` are
the other, since their deinits are what recurse.

## What it cannot tell you

It counts objects; it does not say who retains them. Once a class is named, the next step is
`MallocStackLogging=1` and `malloc_history <pid> -allBySize`, or Instruments' Allocations
template with a generation marked before and after — those give the allocation backtrace, which
is what turns "this is growing" into "this is what holds it".

It also cannot prove a fix. A run that stays flat for an hour is evidence, not a guarantee, and
the honest report of one is the numbers rather than a verdict.

## Why it is not part of any gate

It takes hours, it needs a real windowing session, and it measures a process nobody is driving
unless somebody is driving it. `make verify` stays fast and hermetic; this is a thing you run
deliberately, at a machine, when you want to know.
