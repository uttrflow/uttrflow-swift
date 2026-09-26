# The context read's budget

`MacContextEngine` describes what the user is looking at, and the one thing it may never do is
make them wait for the answer. This page holds the numbers that decide how long it waits and how
much it keeps, and the traps that come with them.

## 100 ms, measured

`MacContextEngine.budget` is 100 ms.

Against the application the user is actually typing in — the only one that matters here — a
focused-window read came back in **0.08–0.12 ms** warm, and **35 ms** on the very first read of a
session, when the connection to that application is set up.

The slow case is an application that has stopped pumping its run loop. With a 100 ms
Accessibility messaging timeout in place, seven background applications on the probe machine each
blocked for the full **101–105 ms** and returned nothing.

So 100 ms buys every realistic reading a thousand times over, and truncates only the readings that
were going to fail anyway.

It is also below the ~200 ms at which a person notices a delay, which is the ceiling that matters.

An ordinary dictation reads the screen once, at key-down: `DictationPipeline.beginWorkingAhead`
starts this same context read the moment recording begins, to warm the tidier for where the words
are heading and to rank the recogniser's vocabulary from it. That one reading is carried into
tidying as `earlyContext` rather than taken again, so a dictation cut into five pieces pays for one
reading, not five, and the words the recogniser listened for and the screen the tidier resolves
against describe the same instant. Because the read overlaps the recording itself, its 100 ms is
additive to the time between stopping speaking and seeing text only when a dictation is too short
to cover it — the number this budget is defending.

## Three different waits

"100 ms" names three different things in this file, and only one of them is `MacContextEngine.budget`:

- **The whole-request deadline** — `MacContextEngine.budget` — bounds one `currentContext()` call:
  identity, then the focused-window read, together. `Deadline` gives up waiting at 100 ms and hands
  back whatever was gathered; it never extends the wait for a read still in flight.
- **The per-message timeout** — `MacContextEngine.budgetInSeconds`, the same 100 ms expressed for
  `AXUIElementSetMessagingTimeout` — bounds one Accessibility message to one element. A focused
  window read sends several (title, focused field, selection, caret), so a napped application can
  cost close to the whole-request deadline one message at a time even though no single message
  waited longer than its own timeout.
- **The lifetime of abandoned work** — unbounded in principle. See below.

## The seconds conversion is not cosmetic

`AXUIElementSetMessagingTimeout` takes a `Float` of seconds and **reads zero as "use the global
default"**. Reaching for `budget.components.seconds` alone would round a sub-second budget to zero
and quietly leave the Accessibility calls with no timeout at all, which is why
`MacContextEngine.budgetInSeconds` converts once, in one place, and a test asserts it is 0.1 and
not 0.

## What is abandoned rather than cancelled

When the whole-request deadline runs out the reading is left behind, not stopped. By then it may be
blocked inside a synchronous Accessibility call that will not notice a cancellation; the point is
only that the dictation stops waiting, and the Accessibility layer's own per-message timeout is what
eventually frees the thread — up to one messaging timeout past the deadline for whichever message
was already in flight when it expired, and `read(_:while:)` also stops sending any *further*
messages the moment its caller's deadline has passed, so an abandoned read degrades to at most one
more message rather than working through the rest of its sequence. That loser turning up late must
therefore be harmless: `Deadline` resumes the caller once, and `MacContextEngine` lets only the
latest uncancelled read update the remembered application behind Uttrflow.

That blocking read runs on a dispatch queue of its own rather than the cooperative pool, because a
napped application measurably does not answer for a tenth of a second and holding a pool thread
that long would stall unrelated work in the app. That queue is concurrent, not serial: an abandoned
read has no bound on how long it keeps a thread, and a serial queue would make every read behind it
wait out that same unbounded time before starting its own — spending a second read's whole
allowance on nothing but queueing. Concurrent reads cost nothing apps do not already pay for
elsewhere: each targets a different element with its own messaging timeout, so there is no shared
state for two reads to race over.

## 512 characters of selection

`MacContextEngine.selectedTextLimit` is 512.

The selection rides into the prompt beside the transcript, and "select all, then dictate the
replacement" is an ordinary thing to do. Uncapped, that pastes a whole document into an on-device
model with a few thousand tokens of room, and the transcript it is supposed to be helping gets
crowded out.

The selection is there to disambiguate, not to be read: the symbol under the cursor, the sentence
being rewritten. The evaluation corpus's own case is `setUserPrefs`, twelve characters. 512 is
roughly a long paragraph, ~128 tokens, and past that a selection stops adding meaning and starts
costing context. What is cut keeps a `…` so a model reading it does not take the fragment for a
finished sentence.
