# The context read's budget

`MacContextEngine` (`Sources/UttrflowContext/MacContextEngine.swift`) describes what the user is
looking at, and the one thing it may never do is make them wait for the answer. This page holds the
numbers that decide how long it waits and how much it keeps, and the traps that come with them.
[context-accessibility.md](context-accessibility.md) covers what applications answer.

| Constant | Value | Meaning |
|---|---|---|
| `MacContextEngine.budget` | 100 ms | Longest one `currentContext()` call is waited for |
| `MacContextEngine.budgetInSeconds` | 0.1 | The same budget as a `Float`, for `AXUIElementSetMessagingTimeout` |
| `MacContextEngine.selectedTextLimit` | 512 characters | Longest selection kept; read by range over at most 2,052 UTF-16 units, so a longer one is cut and ends in `…` and a refused range read keeps none |
| `StageTimeout.quick` | 15 s | The pipeline's own cap on a context read, for an injected engine that keeps no budget |

## 100 ms

Against the application the user is typing in, a focused-window read takes a fraction of a
millisecond warm and tens of milliseconds on the first read of a session, when the connection to
that application is set up; `uttrflow-dev context` prints the time of one read as `read in`. The
slow case is an application that has stopped pumping its run loop, which does not answer until the
per-message timeout expires and then returns nothing. So 100 ms covers every realistic reading and
truncates only the ones that were going to fail. It is also below the roughly 200 ms at which a
person notices a delay.

## When the screen is read

`DictationPipeline.beginWorkingAhead` starts a context read the moment recording begins, so it
overlaps the speaking. That reading warms the tidier for where the words are heading, ranks the
recogniser's vocabulary, and is carried into tidying as `earlyContext` rather than taken again. Its
100 ms adds to the time between stopping speaking and seeing text only when a dictation is too
short to cover it.

Two later reads look at the caret as it is then rather than as it was: correction reads the screen
again for each piece it corrects, and insertion reads it once more immediately before writing
(`insertionContextForWrite`), to pad the words against the text beside the caret and decide the
first word's capital. That last reading is discarded if the application in front is no longer the
one the dictation was read from.

## Three different waits

"100 ms" names three different things, and only one of them is `MacContextEngine.budget`:

- **The whole-request deadline** (`MacContextEngine.budget`) bounds one `currentContext()` call:
  identity, then the focused-window read, together. `withDeadline`
  (`Sources/UttrflowCore/Support/StageTimeout.swift`) stops waiting at 100 ms and hands back
  whatever was gathered; it never extends the wait for a read still in flight.
- **The per-message timeout** (`MacContextEngine.budgetInSeconds`) bounds one Accessibility
  message to one element. A focused-window read sends several (title, focused field, selection,
  caret text), so a napped application can cost close to the whole-request deadline one message at
  a time even though no single message waited longer than its own timeout.
- **The lifetime of abandoned work**, which is unbounded in principle; see below.

## The seconds conversion is not cosmetic

`AXUIElementSetMessagingTimeout` takes a `Float` of seconds and reads zero as "use the global
default". Taking `budget.components.seconds` alone would round a sub-second budget to zero and
leave the Accessibility calls with no timeout at all, which is why `budgetInSeconds` converts once,
in one place, and `MacContextEngineTests` asserts it is 0.1 and not 0.

## What is abandoned rather than cancelled

When the deadline runs out, the reading is left behind, not stopped: it may be blocked inside a
synchronous Accessibility call that will not notice a cancellation. The per-message timeout is what
eventually frees the thread, up to one messaging timeout past the deadline for the message already
in flight, and `read(_:while:)` sends no further message once its caller has stopped waiting, so an
abandoned read costs at most one more message. A loser turning up late is harmless: `withDeadline`
resumes the caller once, and `MacContextEngine` lets only the latest uncancelled read update the
remembered application behind Uttrflow.

The blocking read runs on a dispatch queue of its own (`com.uttrflow.context`) rather than the
cooperative pool, because holding a pool thread for a napped application's timeout would stall
unrelated work in the app. The queue is concurrent, not serial: an abandoned read has no bound on
how long it keeps a thread, and a serial queue would make every read behind it wait that time out
before starting its own. Concurrent reads share no state, since each targets a different element
with its own messaging timeout.

## What each consumer needs

`ContextNeed` (`Sources/UttrflowContext/ContextNeed.swift`) is the slice one consumer reads: which
parts, and a UTF-16 cap before the caret, after the selection and on the selection.
`FocusedFieldRead.text` takes the union of the needs it serves and asks the field for no more.
Every call site reads `ContextNeed.turn` today, so nothing has narrowed yet.

| Consumer | Needs | Cap |
|---|---|---|
| Leading and trailing space padding | caret edges | 2 units each side |
| Sentence state, list item | line before | `ValueWindow.unitsBefore` |
| Recogniser prompt | sentence before | `ValueWindow.unitsBefore` |
| Prompt describer | selection | 120 characters (`AppContextDescriber.selectionLimit`) |
| `MacContextEngine` selection | selection | 512 characters (`selectedTextLimit`) |

`FocusedFieldReadTests.caretEdgesNeedCopiesNoMoreThanSixteenUnits` holds the caret-edges need to
ranged reads of at most 16 units. A new consumer adds its row in the same pull request.

## 512 characters of selection

The selection rides into the prompt beside the transcript, and "select all, then dictate the
replacement" is an ordinary thing to do. Uncapped, that pastes a whole document into an on-device
model with a few thousand tokens of room, and the transcript is crowded out.

The selection is there to disambiguate, not to be read: the symbol under the cursor, the sentence
being rewritten. The evaluation corpus's own case is `setUserPrefs`, twelve characters. 512
characters is roughly a long paragraph, about 128 tokens; past that a selection stops adding
meaning and starts costing context. What is cut ends in `…` (`MacContextEngine.truncationMarker`)
so a model does not take the fragment for a finished sentence.

## Naming the frontmost application

Identity is read from `NSWorkspace.shared.frontmostApplication` directly, off the main actor, the
same rule `UttrflowInput` follows for `isSelfFrontmost()` and `frontmostApplication()`. Hopping to
the main actor first would let any main-actor work at key-down, such as redrawing the menu bar for
`.recording`, spend the whole budget before identity was asked for.

If identity still misses the budget, the engine names the application from the
`didActivateApplicationNotification` feed it already keeps (the application behind Uttrflow when
Uttrflow itself activated last) and logs `Context identity timed out; named from the activation
feed` under the `context` category.
