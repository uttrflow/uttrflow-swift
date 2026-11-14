# Local counters about how dictation goes

`UXLedger` (`Sources/UttrflowUX/UXLedger.swift`) is a small on-device ledger that holds integers,
dates and closed enumerations, never text, over a rolling thirty days. `UXLedgerStore` saves it to a
caller-supplied file, owner-only, and `UXLedgerStore.reset()` deletes that file; nothing here touches
the network. The app does not yet create a store or offer Reset.

## What it records

- The install date, the first press, the first confirmed insert and the furthest onboarding page.
- Per day: dictations started, outcomes (inserted, copied, cancelled, failed), retries, undos, and
  the time from key release to words in five buckets.

## Definitions

- **Time to first text** is the first press to the first confirmed insert.
- **Abandonment** is dictations cancelled or failed with no start inside sixty seconds, over
  dictations started.
- **Retry** is a start that comes within sixty seconds of a cancelled or failed dictation.
- **Landing** is the time from key release to text landing, in the buckets under 250 ms, 500 ms, 1 s
  and 2 s, and over 2 s.

`UXLedgerTests` feeds a scripted day and asserts each figure, and asserts the stored type has no text.
