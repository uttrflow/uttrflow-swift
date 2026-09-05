# Temporary `UserDefaults` suites in tests

## What went wrong

A handful of tests have to touch real preferences. The adapters over `UserDefaults` —
`SystemUserDefaults`, `SystemDefaultsStorage` — claim only that bytes go in and come
back, and nothing short of a real domain would notice if that stopped being true.

Each of those tests named its own suite, `com.uttrflow.tests.<UUID>`, and cleaned up
with `removePersistentDomain(forName:)` in a `defer`. That looks complete and is not.
466 empty 42-byte plists had collected in `~/Library/Preferences` on the first Mac
anybody counted — one per test per run, on every machine that ran `make verify`,
including CI runners.

## `cfprefsd` owns the file, not us

Emptying a domain does not remove it. `cfprefsd` writes
`~/Library/Preferences/<suite>.plist` on the first write, and **writes the domain back
after the owning process exits**.

That last part is what makes this hard to get right, and easy to think you have. A test
can empty the domain, delete the file, watch `fileExists` return `false`, and pass — and
the plist is on disk again twenty to thirty seconds after the run finished.

Deleting the file first does not help either. Measured directly: create four suites with
a cleanup that leaves the domain with the daemon, delete the files while it still holds
them, and all four are back thirty seconds later, named after processes that have
already exited.

Each cleanup below was measured against a thirty-second wait *after* process exit:

| cleanup | file gone after exit? |
| --- | --- |
| `removePersistentDomain(forName:)` alone | no |
| `removeSuite(named:)` as well | no |
| `CFPreferencesSynchronize` as well | no |
| delete the plist from inside the process | no, it returns |
| `/usr/bin/defaults delete`, then delete the plist | yes |

Nothing in-process dislodges the daemon's copy, because the registration being flushed
belongs to *this* process. Asking from another process is what works.

## Why that is still not airtight

Even with the subprocess, the race is only mostly won. From a drained baseline, roughly
one run in three to one in eight leaves two files behind. No in-process cleanup can be
airtight, because the write happens after the process is gone.

So the helper does not rely on winning it. A suite from `withTemporaryDefaultsSuite`
exists for the few milliseconds of one closure, which means **any file matching the
prefix that is older than a few minutes was abandoned by a run that has finished**.
Sweeping those once per test process makes the accumulation self-healing: a later run
clears what an earlier one left, and the count cannot grow without bound.

The ten-minute threshold is what keeps the sweep safe when two checkouts run their tests
at once, which is normal here. A suite in use is seconds old and can never be caught.

## What it is worth

Fourteen consecutive runs, without clearing between them:

- rounds 1–4: 0 files
- round 5: 2 files, the race lost
- rounds 6–13: 2 files, held, still under the cutoff
- round 14: 0 files, the sweep reclaiming them

Peak 2, ending at 0. The same sequence before this work would have reached 70 and kept
climbing.

## The ordering, and what the numbers do not say

`remove()` flushes this process's own pending write with `synchronize()` before asking
the daemon to forget the domain. Over eight rounds each that measured 0/8 rounds leaking
against 1/8 for the other ordering.

That is suggestive and not proof: at a one-in-eight rate, a change that does nothing
shows 0/8 about a third of the time. The ordering is kept because flushing before the
handover is correct on its own terms, not because eight rounds settle it.

## Measuring this without fooling yourself

Two mistakes cost a lot of time here, and both look like success:

**Do not measure against a large baseline.** Runs compared against the existing 466
files showed "466 → 466" and read as proof. A delta of two is invisible at that scale.
Drain to zero first, and drain twice — a writeback still in flight from an earlier run
lands in the next run's window and is easily blamed on it.

**Do not instrument the cleanup.** Adding file I/O to `remove()` to log what it did
shifted the timing enough to hide the race: sixteen consecutive rounds came back clean
while an uninstrumented run had just leaked. That measured the probe, not the code. Use
per-suite marker files or an external observer instead of writing from inside the path
being timed.
