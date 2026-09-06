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
The read happens after transcription, not before the recording — the pipeline asks for it while
tidying, so the screen it describes is the one the text is about to go into — so the cost lands in
the wait the user is already sitting through rather than eating their first word. That makes it
additive to the time between stopping speaking and seeing text, which is the number this budget is
defending.

## The seconds conversion is not cosmetic

`AXUIElementSetMessagingTimeout` takes a `Float` of seconds and **reads zero as "use the global
default"**. Reaching for `budget.components.seconds` alone would round a sub-second budget to zero
and quietly leave the Accessibility calls with no timeout at all, which is why
`MacContextEngine.budgetInSeconds` converts once, in one place, and a test asserts it is 0.1 and
not 0.

## What is abandoned rather than cancelled

When the budget runs out the reading is left behind, not stopped. By then it is blocked inside a
synchronous Accessibility call that will not notice a cancellation; the point is only that the
dictation stops waiting, and the Accessibility layer's own messaging timeout is what eventually
frees the thread. The loser turning up late must therefore be harmless — `Deadline` resumes the
caller once and ignores whichever side arrives second.

That blocking read runs on a dispatch queue of its own rather than the cooperative pool, because a
napped application measurably does not answer for a tenth of a second and holding a pool thread
that long would stall unrelated work in the app.

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
