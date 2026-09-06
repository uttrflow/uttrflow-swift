# Reading memory and processor use from inside the process

`UttrflowEval`'s `MemoryFootprint` and `CPUFootprint` read the kernel's own accounting for this
process. The interfaces are not interchangeable, and the obvious single call gives the wrong
answer in more than one place. This page holds what was measured so the code can say one line.
`Docs/performance.md` holds the numbers these readers produced.

## Two memory figures, and why both are reported

- `phys_footprint` is what Activity Monitor calls Memory and what a memory limit is enforced
  against: dirty and compressed pages, not clean file-backed ones. It is the number that decides
  whether a Mac starts swapping.
- `resident_size` is every page currently in physical RAM, mapped model weights included. It is
  larger and evictable under pressure, so it overstates the cost.
- The product memory-maps a 646 MB CoreML model. The mapped weights are clean, file-backed
  pages, so they show in the resident size and not in the footprint. A report showing only the
  footprint looks as though 300 MB of model has gone missing; a report showing only the resident
  size charges the app for pages the kernel can drop.
- Reported per model, because a laptop with 16 GB is a target and a model that wins on quality
  but needs 12 GB has not won.

## Polling for a peak

- Readings before and after a transcription say nothing about the middle, and the middle is
  where a 16 GB Mac is pushed into swap. `PeakMemory.observed` keeps asking while the work runs.
- The default interval is 20 ms: fast enough to catch a CoreML model materialising its weights,
  slow enough that the polling is not itself what is being measured.
- Each field of the peak is its own maximum, and the two may come from different instants. That
  is what "peak" has to mean when the process is only sampled.
- One more reading is taken after the work finishes, so a peak in the final milliseconds does
  not fall between polls.
- The poller is cancelled *and awaited* on both the success and the failure path, never
  abandoned in a `defer`. An abandoned poller outlives the call that started it, can take one more
  reading and attribute it to work that has already finished, and the stack it belongs to may be
  torn down underneath it. Waiting costs one scheduler hop.
- The wait between readings is injectable, and for a sharper reason than convenience: the
  default waits on the wall clock, so a test asserting that polling happened would be asserting
  that the machine was not busy, and on a loaded Mac it fails. A test supplies a wait it controls
  and gets an exact number of readings. A `Clock` would not do: every manual clock in this
  codebase returns from `sleep` immediately, which turns the poller into a spin and makes the
  count less predictable. Returning `false` from the wait is how cancellation is reported and how
  a test says it has seen enough.
- The default wait is a named function, not a closure literal in the default argument. A default
  argument is compiled at the call site, so an `async` closure written there has its frame
  allocated by whichever task evaluates it, and when that is not the task that later awaits it
  the runtime's allocator is entitled to object.

## Processor time: two interfaces, half of each

- `task_info` gives the times, and it takes two calls: `TASK_BASIC_INFO_64` counts threads that
  have already finished and `TASK_THREAD_TIMES_INFO` counts the ones still running. A process
  measured by the first alone appears to use no processor at all until its threads exit.
- `proc_pid_rusage` gives the hardware counters (cycles and instructions), and *only* those are
  read from it. Its `ri_user_time` looks like exactly the number wanted and is stale for the
  calling process: measured against a burn of a known length it reported 0.005 s where the true
  figure was 0.214 s, agreed by `task_info` and `getrusage` independently. The cycle and
  instruction counts in the same struct were right to the megahertz. The shorter version of this
  code is wrong in a way that reports success.
- The `rusage_info_t *` parameter reads as a pointer to a pointer and is not: the kernel writes
  the whole struct at the address given. The buffer is passed by rebinding a pointer to the
  struct itself. Handing it the address of a pointer variable compiles, runs, and overruns the
  stack.

## The four processor figures

No one of them survives being quoted alone:

- **processor seconds**: user plus system, summed across every thread. Ten seconds of it is ten
  seconds whether one core or eight did it.
- **cores**: processor seconds over wall seconds. 1.0 is one core saturated; 4.0 is four. This
  is what Activity Monitor's CPU column shows and the difference between "busy" and "hot".
  A dictation that fits in 274 MB but holds four cores busy for ten seconds is a fan spinning up.
- **cycles** and **instructions**: read from the processor's own counters. They do not depend on
  how fast this Mac is, so they are the only figures that say anything about a Mac that was not
  measured. The implied clock speed (`gigahertz`) is printed so a reader can check the
  arithmetic against a chip they can look up; a figure far from the real clock means the
  counters and the times disagree and the cycle counts should not be trusted.
- A reading is a running total since launch and means nothing on its own; every reported figure
  is a difference between two readings. Counters are unsigned and only rise, so a smaller "after"
  means the readings did not come from one uninterrupted run and the cost is `nil` rather than a
  wrapped-round astronomical number. A counter missing from any piece of a phase makes the total
  missing, rather than a sum that reads as complete and is short.
- The system share is reported separately because user and system time have different cures:
  user time is code this project wrote or linked; system time is syscalls, and a process that
  lives there is usually polling something.
