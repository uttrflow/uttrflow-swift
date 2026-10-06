# Decisions ledger

One row per approach that was rejected, or adopted over a named alternative. Read it before
proposing a change: if the idea is here, the row says what was measured and what would have to
change for the answer to change. The evidence lives on the linked page; this page only indexes it.

A new row goes in when a `Docs/` page records a rejection. "Reopen when" names a condition that
can be checked, not a feeling; a row whose condition has come true is re-measured, and the page
it links is updated with the new result.

## Dictation and recognition

| Decision | Why | Evidence | Reopen when |
|---|---|---|---|
| No concurrent recognition workers (WhisperKit's own voice-activity chunking with four workers) | Same wall time at every length; the Neural Engine runs one job at a time | [early-transcription.md](early-transcription.md) | The recogniser runs on a resource that executes jobs in parallel, or a pinned WhisperKit release changes how work reaches the Neural Engine |
| No parallel tidying sessions | Four sessions at once took as long as four in a row; the model serialises them | [early-transcription.md](early-transcription.md) | The on-device language model accepts concurrent sessions without serialising |
| Hindi stays Devanagari inside the decoder; no prompt or token trick to make it write romanised Hindi | Every way of spending fewer decoder steps changed what the speaker sees: a translation, an untested spelling, or a script that varies clip to clip | [speech-engines.md](speech-engines.md) | A decoder that writes romanised Hindi as its own output exists, and a recorded Hindi baseline exists to judge it against ([measuring-accuracy.md](measuring-accuracy.md)) |
| No word list and no confidence floor to reject a temperature-fallback misreading | The ladder's average log-probability is 0.02 apart for the right and the wrong reading; a word list fires only by accident | [speech-engines.md](speech-engines.md) | The decoder exposes a per-word signal on the shipping path that separates the pair across the corpus |
| WhisperKit 1.1.0 was declined until a measurement could say better or worse | Nobody could say whether it improved recognition; the package then took it anyway without that measurement | [measuring-accuracy.md](measuring-accuracy.md) | The recorded-corpus baseline that page describes exists, so a version change is scored before it lands |
| The dictation start cue is not trimmed from the front of the recording | A fixed trim turns a probabilistic bleed into certain word loss for users who press and speak; the sweep found no word errors at the loudest leak | [audio-capture.md](audio-capture.md) | A sweep with the current shaped cue, not the earlier one, finds word errors from the bleed |
| Voice processing (echo cancellation) is not enabled on the input | Cut the cue bleed most, but changed the input to nine channels, and imposes gain control and noise suppression the recogniser was never tuned against | [audio-capture.md](audio-capture.md) | The bake-off is re-run with voice processing on and the recogniser scores no worse |
| Calling the audio converter again is not a way to recover dropped frames | It reports `inputRanDry` after about 4000 frames; only re-supplying input in slices recovers the output | [audio-capture.md](audio-capture.md) | A macOS release changes `AVAudioConverter`'s pull behaviour |
| The decode loop is the repository's (`DecodeSession`), not WhisperKit's `decodeText` | Per-step needs (no-speech probability, biasing, scoring, branching) cannot be reached inside a `public`, non-`open` method; the session is built on WhisperKit's public primitives and matched it byte for byte on 75 windows | [decode-session.md](decode-session.md) | A pinned WhisperKit release opens its loop to per-step hooks, or the parity probe finds a clip class that differs |
| No language-specific punctuation marks (inverted marks, French spacing, guillemets) | Only English and Hindi are transcribed, and romanised Hindi is typed with English marks; there is no language for such rules to serve | [adding-a-language.md](adding-a-language.md#punctuation-conventions) | A Latin-script language is added to `LanguageCode.transcribed` |

## Clean-up and the language model

| Decision | Why | Evidence | Reopen when |
|---|---|---|---|
| "Make the output more polished" is declined | It is a rewrite; the tidier is a filter that keeps every meant word in order and register | [agents/product.md](agents/product.md), [cleanup.md](cleanup.md) | Never as a change to tidying; a rewrite is a separate, user-requested feature |
| Destination examples replace the prompt's generic ones rather than adding to them | The bake-off showed examples matter, and prompt size costs tenths of a second | [cleanup-design.md](cleanup-design.md) | A measured prompt-size cost falls enough that the bake-off scores more examples as a net gain |
| A recording is cut into pieces rather than tidied whole | Past about four minutes the tidier loses words (943 spoken, 253 returned) and the meaning guard throws the answer away | [early-transcription.md](early-transcription.md) | The on-device model returns a long passage without dropping words, measured on the same input |
| Spelling variants and fillers are not folded away before scoring word error rate | Folding spellings grows a dictionary into a fudge factor; stripping fillers hides the failure the passages exist to measure | [eval-methodology.md](eval-methodology.md) | Never for fillers; spellings only with a published, fixed variant list the report prints |

## Rendering and energy

| Decision | Why | Evidence | Reopen when |
|---|---|---|---|
| No frame-rate cap on the animated card | Sixty a second saved 6% of a core, not worth the loss of smoothness on a 120 Hz display; ten a second is visibly steppy | [performance.md](performance.md) | A cap is offered as a user-chosen trade, or the structural repair leaves a large per-frame cost |
| `ViewThatFits` is not hoisted above the clock | A `TimelineView` inside a `ViewThatFits` candidate is never driven: the animation stops silently and the measurement looks like a win | [performance.md](performance.md) | A SwiftUI release drives a `TimelineView` inside a `ViewThatFits` candidate |
| Separate hosting views, SwiftUI-driven rise and fade, and a constant shadow were not kept | None was distinguishable from the ±5 point noise; the wake schedule is the lever | [performance.md](performance.md) | The wake schedule stops dominating the remaining cost |
| `NSView.visibleRect` is not used to tell whether a card is on screen | It does not see SwiftUI's scroll clipping; the scrolled-out card still cost 31% | [performance.md](performance.md) | AppKit's visible rect starts reflecting SwiftUI scroll clipping |

## Storage, account and system

| Decision | Why | Evidence | Reopen when |
|---|---|---|---|
| The retention clock neither reads a future stamp as `now` nor rewrites the stored stamp | Reading it as `now` bounds nothing; rewriting it edits the user's record of when they spoke | [retention-clock.md](retention-clock.md) | The record gains a separate, system-owned timestamp that retention may edit |
| Pinning the designated requirement does not make an ad-hoc build's keychain item readable by the next build | The keychain's access list is not the designated requirement; measured with two ad-hoc builds | [account-keychain.md](account-keychain.md) | A macOS release changes how the file-based keychain names an ad-hoc application |
| Deleting a test preferences suite's file first is not a cleanup | The daemon writes the plist back twenty to thirty seconds later | [preferences-suites.md](preferences-suites.md) | A macOS release stops `cfprefsd` writing back a domain it still holds |
| A server `5xx` is not reported as "no connection" | The server was reached; that message sends the user to check their Wi-Fi over an outage | [account-session.md](account-session.md) | Never; the distinction is the point |
| Telemetry failures are not `UttrflowFailure` | That protocol owes the user a sentence and a recovery, and an alert about analytics interrupts their work | [account-telemetry.md](account-telemetry.md) | Telemetry gains a failure the user can act on |
| WhisperKit is the only recogniser; the system recogniser is deleted, not kept as a fallback | It lacks Hindi, per-word confidence and the conditioning prompt, and fetched an asset on the dictation path | [speech-engines.md](speech-engines.md#one-recogniser) | A measured replacement beats WhisperKit end to end on English and Hindi, with the loser deleted |

## Release and insertion

| Decision | Why | Evidence | Reopen when |
|---|---|---|---|
| No five-part calendar version | It signs and verifies, but Apple documents the version keys as three integers, so the App Store would refuse it | [releasing.md](releasing.md) | Apple documents more than three version components |
| Typed text does not use one representation alone: not a bare Unicode string on key code 0, and not a layout key | Key code 0 alone reads as the A key to apps and input methods that read physical keys; a layout key alone cannot type a character the layout has no key for (é on US, any Latin letter on a Russian or Devanagari layout). So every event carries the Unicode string, `LayoutKeyCode.keypresses(for:stroke:)` adds the layout key where one exists, and it is the only planner | [input-synthetic-keystrokes.md](input-synthetic-keystrokes.md) | A per-application insertion measurement shows an app or input method that misreads the mapped key, or drops a key-code-0 character |
| "Copy to Paste Elsewhere" does not relaunch the original destination and wait for it | The timing belongs to the user, not the page | [insertion.md](insertion.md) | A measured insertion path can bring the destination to front without a race the user sees |
