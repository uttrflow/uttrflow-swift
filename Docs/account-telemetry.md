# Telemetry: what leaves the Mac, and why a dictation never waits for it

Three types carry Uttrflow's usage reporting: `TelemetryCollector` accumulates counters,
`TelemetryReport` is the value that goes on the wire, and `TelemetryService` sends it and
remembers what it sent. The code says what each does; this page says what the shapes
guarantee and where the numbers come from.

## There is no `String` anywhere in a report

The stored properties of `TelemetryReport` are the complete answer to "what leaves my
Mac". Every one is an `Int`, a `Date`, or a value of a closed enumeration. There is no
`String` on the type, none on any type it contains, and none reachable through either, so
there is nowhere to put a transcript, a window title, an application name or a dictionary
entry, and no reviewer has to take anyone's word for it. `TelemetryPrivacyTests` says the
same thing in a test, and the backend's `migrations/0005_telemetry.sql` says it a third
time in its columns.

The dates are the exception that proves it: a `Date` is a number of seconds, and the
ISO-8601 string the server wants is produced during encoding rather than stored.

The same line is held at the point of collection, not only at the point of upload: no
recording method on `TelemetryCollector` has a parameter of any text type, so a caller
cannot hand it a transcript to discard.

### Languages are a closed set

`TelemetryLanguage` narrows the app's `LanguageCode` once, at its initialiser, and after
that there is no free text in the report. `LanguageCode` wraps a `String`, and a `String`
on an uploaded type is a place a transcript can go, if not today then later, by somebody
who needs "just a bit more context". Every raw value is a BCP-47 primary subtag matching
the pattern the backend's `language_tag` domain enforces, so a value that exists here
cannot be one the server refuses. Unrecognised languages become `other` (`und`, BCP-47's
own "undetermined") rather than passing through: an unusual tag is itself identifying, and
the product question ("which languages do people dictate in") is answered as well by
knowing this one is not on the list. The mapping is one line on purpose: a hand-written
table is a table somebody could add a passthrough to.

### Stages the server cannot name are not sent

`TelemetryStage` is a separate vocabulary from `PipelineStage` because the two genuinely
differ: the server has stages this app does not measure, and spells two of the shared
ones differently. The mapping is a total `switch`, so a stage added to the pipeline is a
compile error here, which is the moment to decide whether it should be reported at all.

Correction and expansion are measured on the Mac and shown on the diagnostics page, but
the backend's `pipeline_stage` column is a closed domain and `migrations/0005_telemetry`
is not this repository's to widen: inventing a value would turn every report from a user
with a dictionary into a 400. Declining to send them costs no total, because
`processingTotalMs` still times the whole journey. When the column gains the two names,
`TelemetryStage.init(_:)` is the one place that changes.

## Ranges are clamped, not refused

The backend's Zod schema is `.strict()` and its table has `check` constraints: an
out-of-range number is a 400 or a 500, and a report that cannot be sent is worse than one
rounded into shape. `TelemetryLimit` names the three ranges once so the four types that
enforce them cannot drift apart:

| limit         | range               | note                                    |
|---------------|---------------------|-----------------------------------------|
| `count`       | 0...2 147 483 647   | a non-negative 32-bit integer           |
| `durationMs`  | 0...604 800 000     | a week; no honest measurement reaches it |
| `versionPart` | 0...999             | each of the three version numbers       |

Percentiles are never allowed below the one under them (p90 is raised to p50, p99 to
p90), `cancelledCount` is capped at `dictationCount`, and a `Duration` is floored at zero
so a clock stepping backwards mid-stage cannot produce a negative number that costs the
whole report.

A report is refused outright (the initialiser returns `nil`) only when the window did not
advance or nothing happened in it: the table requires `window_ended_at > window_started_at`,
and a report of no dictations is a request that costs the user's battery to tell the
server nothing.

Optionals are omitted with `encodeIfPresent` rather than encoded as `null`, because the
server's fields are `.optional()` and Zod refuses an explicit `null` for those. The
timestamps are formatted inside `encode(to:)` rather than left to the encoder's date
strategy, so a differently configured `JSONEncoder` cannot send a number and be refused.

## Why a dictation never waits

Every recording method on `TelemetryCollector` is synchronous and non-`async`. The
compiler enforces that rather than a comment asserting it: a function with no `async` in
its signature has no suspension point, so a dictation calling it cannot be parked behind
a network request, a disk write, or another actor's queue. Each call does a handful of
integer additions and at most one array element written in place, under an uncontended
`Mutex`. Sending lives in `TelemetryService`, the only `async` thing in the subsystem, and
is never called from the dictation path.

`TelemetryCollector` conforms to `MetricsRecording` rather than inventing a second way to
time things, so the pipeline needs no telemetry-specific code: whatever already measures
a stage feeds telemetry too. The protocol requirement is `async` and the witness is not,
which Swift allows and which is the point.

### Sample capacity

Each latency series keeps 512 samples in a ring that overwrites its earliest entry when
full. The window between reports is as long as the app has been running, so an unbounded
array would grow without limit for a user who never quits. 512 samples put a percentile
within a fraction of a millisecond of the true one and cost four kilobytes. Overwriting
rather than refusing keeps the recent latencies, which are the interesting ones; a buffer
that stops accepting would report yesterday's percentiles for ever.

The percentile index is `count * fraction`, which at `0.5` is `count / 2`, the same median
`StageLatency.typical` reports, so Uttrflow has one definition of its own median and
`TelemetryCollectorTests` checks the two agree. A series nothing timed answers `nil`, not
zero: a stage nothing timed is not a stage that was instant, and the server's column is
nullable so the difference survives.

## Opting out forgets everything

Switching collection off discards everything gathered so far in the same call, and
`TelemetryService.setEnabled` empties the outbox too. Reports waiting for a connection
have not left the Mac yet, and a user who has just opted out has said something about
those as well; sending them on the next flight home would keep the letter of the setting
and break all of it that matters. `reset` assigns a whole fresh `State` rather than
zeroing fields one by one, so a counter added later cannot be left behind holding the
previous window's data.

The opt-out is enforced at one door: every accumulation goes through `mutate`, `state` is
private, and a recording method added later cannot forget to check.

## The outbox and the ledger

The outbox holds at most 8 reports. An outbox is the classic place for an offline app to
quietly consume a disk, and a fortnight-old report is worth close to nothing. When it
overflows the earliest report is dropped, because a report describes a window that has
already closed: the recent ones say what Uttrflow is like now.

The ledger of sent reports holds 64 entries, and each entry is the very value that was
encoded and posted, not a description written separately. The privacy page draws from it,
so what the user is shown is what left their machine. `TelemetryReport.encodedForIngest()`
exists so the page showing reports and the sender uploading them look at the same bytes.

`flush` cannot throw and cannot report a problem. No caller should do anything differently
because telemetry failed, and a version that threw would eventually be `try`-ed somewhere
that mattered. One flush runs at a time: two overlapping ones would each see the same
report at the front of the queue and send it twice, which the server would faithfully
count. A delivered report is removed from the queue by value rather than assumed to still
be at the front, because opting out can empty the queue while a send is in flight.

`TelemetryError` is deliberately not a `UttrflowFailure`. Everything conforming to that
protocol owes the user a sentence and an offer of recovery, and telemetry owes neither: an
alert about it would be the app interrupting somebody's work to complain about its own
analytics. Its status is a number rather than the server's message, so no string from the
network becomes the one text-shaped thing in the subsystem.
