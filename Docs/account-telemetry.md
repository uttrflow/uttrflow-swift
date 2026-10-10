# Telemetry: what leaves the Mac, and why a dictation never waits for it

Uttrflow's usage reporting is opt-in counts and timings, never text. Four types in
`Sources/UttrflowAccount/` carry it: `TelemetryCollector` accumulates counters,
`TelemetryReport` is the value that goes on the wire, `TelemetryService` queues and sends
reports and remembers what it sent, and `HTTPTelemetrySender` posts them. In the app target,
`Sources/Uttrflow/UsageTelemetry.swift` owns the service, feeds it each finished dictation and
flushes it on a timer; `AppDelegate.startTelemetry()` builds it from the saved setting. The
code says what each type does; this page says what is sent, when, and what the shapes
guarantee.

## Is it on?

**Off by default.** The switch is `Settings.sharesUsageStatistics`
(`Sources/UttrflowSettings/SettingsStore.swift`), `false` until the user chooses to share. It
appears in two places:

| Where | UI |
|---|---|
| Settings → Privacy → "Your data" | toggle "Share usage statistics", explained as "Counts and timings, linked to your account when you are signed in. Never what you dictate." |
| Onboarding, sign-in page | "Keep off" and "Share" buttons, with "Usage statistics are off unless you choose to share them." |

The statistics are not anonymous while somebody is signed in: every report is attributed to
their account (see **Where is it sent?**). What a report can carry does not change with that:
it is numbers only. Turning the switch off stops collection at once and drops every report
still waiting to be sent; turning it back on starts from an empty window.

## What is sent?

One `TelemetryReport` per window, and nothing else. Every field is an `Int`, a `Date` or a
closed enumeration:

| Field | What it holds |
|---|---|
| `windowStartedAt`, `windowEndedAt` | the period summarised, encoded as ISO-8601 |
| `appVersion` | `CFBundleShortVersionString` as three numbers (`26.0926.0` → `26`, `926`, `0`); an unreadable version becomes `0.0.0` |
| `osVersionMajor` | the macOS major version |
| `dictationCount` | dictations counted in the window (inserted, cancelled or failed) |
| `cancelledCount` | dictations the user abandoned, never more than `dictationCount` |
| `failureCount` | dictations that failed |
| `audioTotalMs` | total time spoken, from each inserted dictation's spoken duration |
| `processingTotalMs` | total time the user waited, from the end of listening to insertion, cancellation or failure |
| `charactersInserted` | a count of characters inserted, not the characters |
| `latencyP50Ms`, `latencyP90Ms`, `latencyP99Ms` | end-to-end wait percentiles of inserted dictations |
| `languages` | dictations per `TelemetryLanguage`, sorted by tag |
| `stages` | per `TelemetryStage`: failure count and p50/p90 latency, sorted by name |

## What feeds it?

`UsageTelemetry.observe` receives every pipeline state change. It starts the wait clock when
the pipeline leaves recording, and on `.inserted` or `.failed` calls
`TelemetryCollector.recordDictation` with the outcome, the wait, the spoken duration and the
inserted text's length; the language is the first of the user's preferred languages in
Settings. When an active dictation returns directly to `.idle`, it records a cancellation, with
no audio or latency sample. The pipeline's stage timings reach the collector through
`MetricsFanOut`, beside the diagnostics recorder, so the pipeline needs no telemetry-specific code.

## When is it sent?

| Constant | Value | Meaning |
|---|---|---|
| `UsageTelemetry.flushInterval` | 3600 s | the timer flushes once an hour, the first an hour after launch |
| `UsageTelemetry.quitBudget` | 3 s | the flush while quitting gives up after this |

On quit, `applicationShouldTerminate` lets the dictation in flight land first, then calls
`flushBeforeQuitting`. A flush closes the window, queues its report and posts everything
queued. A window with no dictation in it produces no report, so an idle Mac sends nothing.

## Where is it sent?

`HTTPTelemetrySender` posts the report's `encodedForIngest()` bytes to the same API root the
account uses, through the same `BackendTransport` (see
[account-transport.md](account-transport.md)). It asks
`HTTPAuthenticationService.accessTokenIfSignedIn()` for a bearer token before each post and
posts without one when nobody is signed in. Any `2xx` is delivery; anything else is
`TelemetryError.refused(status:)`, no answer is `TelemetryError.unreachable`, and either
leaves the report queued for the next flush.

`OnboardingAccountLayer` wires `HTTPTelemetrySender` only in a build that has a backend
configured. A development build gets `RecordingTelemetrySender`, which keeps reports in
memory and sends nothing anywhere.

## Why is there no `String` in a report?

The stored properties of `TelemetryReport` are the complete answer to "what leaves my Mac".
There is no `String` on the type, none on any type it contains, and none reachable through
either, so there is nowhere to put a transcript, a window title, an application name or a
dictionary entry. `TelemetryPrivacyTests` checks this at every depth. The dates are numbers of
seconds; the ISO-8601 string the server wants is produced during encoding rather than stored.

The same line is held at the point of collection: no recording method on `TelemetryCollector`
has a parameter of any text type, so a caller cannot hand it a transcript to discard.

### Languages are a closed set

`TelemetryLanguage` narrows the app's `LanguageCode` once, in its initialiser, to one of 28
BCP-47 primary subtags or `other` (`und`, BCP-47's own "undetermined"). `LanguageCode` wraps a
`String`, and a `String` on an uploaded type is a place a transcript could go. Unrecognised
languages become `other` rather than passing through, because an unusual tag is itself
identifying. The mapping is one line (`TelemetryLanguage(rawValue:) ?? .other`): a hand-written
table is a table somebody could add a passthrough to. `TelemetryPrivacyTests` checks the list
stays within what the server accepts.

### Stages the server cannot name are not sent

`TelemetryStage` is a separate vocabulary from `PipelineStage`: the server names four stages
(`audio-capture`, `transcription`, `tidying`, `insertion`), and spells two of them differently
from the app (`capture` → `audio-capture`, `transformation` → `tidying`). The mapping in
`TelemetryStage.init(_:)` is a total `switch`, so a stage added to the pipeline is a compile
error there, which is the moment to decide whether it is reported. `microphoneOpen`,
`keyDownToAudio`, `drain`, `correction` and `expansion` map to `nil` and are not sent, because
the server's stage set is closed and an unknown value would refuse the whole report. No total
is lost: `processingTotalMs` still times the whole wait.

## Which values are clamped, and which refused?

The server's ingest schema rejects unknown keys and out-of-range values, and for a measurement
a report that cannot be sent is worse than one rounded into shape. `TelemetryLimit`
(`TelemetryReport.swift`) names the ranges once so the types that enforce them cannot drift
apart:

| Limit | Range | Used for |
|---|---|---|
| `TelemetryLimit.count` | 0...2 147 483 647 | every count, a non-negative 32-bit integer |
| `TelemetryLimit.durationMs` | 0...604 800 000 | every duration and latency (a week) |
| `TelemetryLimit.versionPart` | 0...999 | the version's third number, and `osVersionMajor` |
| `TelemetryLimit.versionDate` | 0...9999 | the version's first two numbers, a year and a month-and-day |

Counts and durations are clamped. Percentiles are never allowed below the one under them (p90
is raised to p50, p99 to p90), `cancelledCount` is capped at `dictationCount`, and a negative
`Duration` is floored at zero so a clock stepping backwards cannot cost the whole report.

### The version is refused, not clamped

A version is not a quantity, and rounding one into range makes it another release's version,
which a reader has no way to doubt. So a version part outside its range, or an
`osVersionMajor` outside `versionPart`, makes the initialiser return `nil` and the window
produces no report. `versionDate` is wide enough for a two-digit year and a month-and-day up
to `1231`, and for a four-digit year.

The initialiser also returns `nil` when the window did not advance (`windowEndedAt` must be
after `windowStartedAt`) or held no dictation: a report of nothing costs the user's battery
to tell the server nothing.

Optionals are omitted with `encodeIfPresent` rather than encoded as `null`, because the
server refuses an explicit `null` for an optional field. The timestamps are formatted inside
`encode(to:)` rather than left to the encoder's date strategy, so a differently configured
`JSONEncoder` cannot send a number and be refused. `TelemetryBackendContractTests` posts real
bytes to a running backend when `UTTRFLOW_BACKEND_URL` is set.

## Why does a dictation never wait?

Every recording method on `TelemetryCollector` is synchronous. The compiler enforces that: a
function with no `async` in its signature has no suspension point, so a dictation calling it
cannot be parked behind a network request, a disk write, or another actor's queue. Each call
does a handful of integer additions and at most one array element written in place, under a
`Mutex`. Sending lives in `TelemetryService.flush`, the only `async` work in the subsystem,
and only the timer and the quit path call it.

`TelemetryCollector` conforms to `MetricsRecording` rather than inventing a second way to time
things. The protocol requirement is `async` and the witness is not, which Swift allows and
which is the point.

### Sample capacity

| Constant | Value |
|---|---|
| `TelemetryCollector.sampleCapacity` | 512 samples per latency series |

Each series is a ring that overwrites its earliest entry when full. The window between reports
lasts until the next flush, and a flush that finds no dictation leaves the window open, so an
unbounded array could grow without limit. 512 `Int` samples cost four kilobytes. Overwriting
rather than refusing keeps the recent latencies; a buffer that stopped accepting would report
old percentiles for ever.

The percentile index is `count * fraction`, which at `0.5` is `count / 2`, the same median
`StageLatency.typical` reports, so Uttrflow has one definition of its own median;
`TelemetryCollectorTests` checks the two agree. A series nothing timed answers `nil`, not
zero: a stage nothing timed is not a stage that was instant, and the field is optional on the
wire so the difference survives.

## What does opting out forget?

Everything. `TelemetryCollector.setEnabled` discards the counters in the same call, and
`TelemetryService.setEnabled(false, at:)` empties the outbox too. Reports waiting for a
connection have not left the Mac yet, and a user who has just opted out has said something
about those as well. `reset` assigns a whole fresh `State` rather than zeroing fields one by
one, so a counter added later cannot be left holding the previous window's data.

The opt-out is enforced at one door: every accumulation goes through `mutate`, `state` is
private, and a recording method added later cannot forget to check. `flush` re-checks
`isEnabled` under the outbox lock, so an opt-out that lands mid-flush still drops the report.

Signing out or deleting an account also clears the current counters and reports still waiting
to send, while keeping the user's opt-in choice. A dictation already in flight at that boundary
cannot contribute its outcome or stage timings to the next account. Each stage sample carries
the pipeline generation that produced it, so the recorder fences the old generation even when
its terminal state observer is delayed. Measurements from a later dictation are retained after
the boundary snapshot, and revisioned state events that arrive while that snapshot is pending
are replayed if they belong to the new generation. The hourly timer is restarted at its saved
interval, and a flush cancelled while resolving its bearer token stops before creating a network
request. A request already handed to the transport can still finish, but its response is not
acknowledged into the local ledger after the reset.

## The outbox and the ledger

| Constant | Value |
|---|---|
| `TelemetryService.outboxCapacity` | 8 reports waiting to be sent |
| `TelemetryService.ledgerCapacity` | 64 sent reports remembered |

An outbox is the classic place for an offline app to quietly consume a disk. When it
overflows the earliest report is dropped, because a recent window says more about how Uttrflow
behaves.

The ledger (`sentReports`) holds each `TelemetryDispatch`: the very value that was encoded and
posted, and when. `encodedForIngest()` is the one encoding, so anything that shows a report
shows the bytes that were posted.

`flush` cannot throw and cannot report a problem. No caller should do anything differently
because telemetry failed, and a version that threw would eventually be `try`-ed somewhere that
mattered. One flush runs at a time: two overlapping ones would each see the same report at the
front of the queue and send it twice. A delivered report is removed from the queue by value
rather than assumed to still be at the front, because opting out can empty the queue while a
send is in flight.

`TelemetryError` is not a `UttrflowFailure`. Everything conforming to that protocol owes the
user a sentence and an offer of recovery, and telemetry owes neither: an alert about it would
interrupt somebody's work to complain about the app's own analytics. Its status is a number
rather than the server's message, so no string from the network becomes the one text-shaped
thing in the subsystem.

## Related

- [account-session.md](account-session.md): the access token a report is attributed with.
- [crash-reporting.md](crash-reporting.md): the other opt-in report, sent separately.
- [offline.md](offline.md): every network path in the app.
