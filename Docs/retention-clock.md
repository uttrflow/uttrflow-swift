# Retention, against a clock that may be wrong

Three stores promise that something is deleted after a window: the dictation history, the
clipboard, and the recordings kept for a retry. All three decide it through `RetentionWindow` in
`Sources/UttrflowCore/Support/RetentionWindow.swift`, which answers two separate questions about
a stamp: may it still be **shown** (`keeps(_:)`), and may it be **deleted** (`mayDelete(_:)`).
The window never reads a clock; every caller passes in its own `now`.

The naive rule, `stamp.addingTimeInterval(window) > now`, takes the wall clock's word for both
questions, and is wrong about both. A Mac's clock is not a monotonic count of elapsed time: it
is set by hand, restored from a dead battery reading 1970, stepped by the network after a late
boot, and moved by whoever is testing something else.

## The windows

| Store | What ages | Window | Constant | Count cap |
|---|---|---|---|---|
| Dictation history | each `DictationRecord`, by `when` | the user's transcript period; default "Always" | `Settings.transcriptRetentionDays`, default `Settings.defaultTranscriptRetentionDays` = `RetentionWindow.keepAlwaysDays` (36,500) | 1,000 under a finite period, none under Always (`DictationHistoryStore.defaultCapacity`) |
| Recordings for a retry | each recording file, by its creation date | 24 hours | `RecordingStore.defaultRetention` | — |
| Clipboard | each clip, by `copiedAt`, per pool | see below | see below | see below |

The clipboard charges each clip to a pool (`ClipClass` in
`Sources/UttrflowClipboard/ClipboardBudget.swift`), and each pool has its own window and cap
(`ClipboardBudget.standard`, [clipboard-budget.md](clipboard-budget.md)):

| Pool | Window | Window constant | Item cap | Cap constant |
|---|---|---|---|---|
| Copied text | 7 days | `Settings.clipboardRetentionDays`, default `Settings.defaultRetentionDays` = 7 (no control in Settings) | 500 | `ClipboardBudget.standard.copied.items` |
| Dictations Uttrflow put on the clipboard | the user's transcript period, the same setting as the history | `ClipRetention.dictationDays` = `Settings.transcriptRetentionDays` | 500 | `ClipboardBudget.standard.dictation.items` |
| Pictures | 7 days, whatever the setting | `ClipboardBudget.standard.images.days` = 7 | 500 | `ClipboardBudget.standard.images.items` |
| Kept: a clip with an alias, a tag, a category or a pin (`Clip.isKept`) | none | `ClipboardBudget.tier(for: .kept)` is `nil` | none | — |

A pinned clip outlives both the window and the cap: kept clips are never candidates for either
(`ClipClass.isEvictable` is `false`). Kept pictures still count toward the pictures' disk budget,
but only unkept pictures are evicted to meet it.

| Clock constant | Value | Meaning |
|---|---|---|
| `RetentionWindow.clockSkewAllowance` | 300 s (five minutes) | How far ahead of `now` a stamp may be and still be taken at face value. |
| `RetentionWindow.longestBelievableIdle` | 365 × 86,400 s (a year) | How far ahead of a record `now` may claim to be and still be believed enough to delete it. |

## A stamp ahead of the clock is due, not young

The naive rule has no floor on the age it computes. A record stamped a year ahead (written
while the clock was wrong, and read after it was put right) has a negative age, passes the test
for a year, and outlives a window the user was told was seven days. A clip can hold a password;
that is the promise broken, quietly, for as long as the clock was out.

`keeps(_:)` answers `false` for a stamp more than `clockSkewAllowance` ahead of `now`. A record
whose stamp is in the future has no knowable age: all it establishes is that the clock was wrong
when it was written. "Deleted after N days" is a **maximum**, so the unknowable case resolves to
the shorter life, not to however long the clock happened to be out.

Two alternatives are not used:

- Reading a future stamp as `now` does not bound anything: the record is then kept for a fresh
  window at *every* read, so it survives until real time catches up with the stamp.
- Rewriting the stored stamp bounds it, but a retention pass has no business editing the user's
  record of when they spoke.

The five-minute allowance exists because a clock nudged backwards by a second is not a wrong
clock, and a dictation must not expire the instant it is made. It is far beyond any network
time step and far below any window, so nothing turns on the exact figure.

## A clock that jumped forward is not believed to delete

The other direction is worse, because it is not recoverable. One read while the clock is far
ahead would delete everything older than the window from the disk, and when the clock came back
the history would be gone. The read is not meant to be destructive (it is a window being drawn)
and the cause is outside the app.

A clock that jumped forward cannot be told apart from time that really passed. Nothing in the
stamps distinguishes them, nor does a file's modification date, since both are written by the
same clock, and across a reboot with a flat battery there is no monotonic count to appeal to.
So the guard is a refusal rather than a detection: `mayDelete(_:)` answers `false` once `now`
claims to be more than `longestBelievableIdle` ahead of the record.

A year is a judgement, picked by the asymmetry of the two mistakes. Refusing to delete
something the window really has passed costs a later sweep, and the record is hidden from the
user meanwhile, because `keeps(_:)` and `mayDelete(_:)` are separate questions and only the
second is refused. Deleting something the window has *not* passed cannot be taken back. A year
of not dictating is not a state this app is in; a clock a year out is one it meets.

`sweepable` states the same pair of answers as a range of dates, for a stamp that lives in a
file name rather than in a record: `LocalStore.removeSetAside(_:stamped:)` uses it to delete
copies set aside from an unreadable store.

## Where the two answers are asked

Each store keeps two lists rather than one: what the caller may be **shown**, and what may stay
on the **disk**. They differ only for a record the window has passed on a clock too far ahead of
it to be believed: hidden, and still there.

| Store | Shown | Kept on disk |
|---|---|---|
| `DictationHistoryStore` | `retained(_:keeping:)` | `keptOnDisk(_:keeping:)` |
| `ClipboardStore` | `retained(_:keeping:)`, then pool caps and quotas | `keptOnDisk(_:keeping:)`, then the same caps and quotas |
| `RecordingStore` | the list `waiting(now:)` returns | the files `waiting(now:)` deletes, plus unrecognised files outside the window |

Every write goes through the disk answer too: appending a dictation is no better informed about
the time than reading one. The Corrections page filters its rows with the same window
(`CorrectionsPresenter.retained(_:)` in `Sources/UttrflowUX/CorrectionsPresentation.swift`), so an undo can reach every correction it shows.

## What this does not cover

A clock that is wrong by *less* than a year at the moment of a read or a write still prunes.
So does a clock that jumped forward and then had a record written under it, because the newest
stamp then agrees with the clock and there is nothing left to disagree with. Closing that needs
a time source the app can trust (a persisted high-water mark checked against a monotonic clock,
or the network), and none of the three stores has one.
