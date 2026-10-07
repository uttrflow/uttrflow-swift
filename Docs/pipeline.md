# The dictation pipeline

`DictationPipeline` (`Sources/UttrflowPipeline/DictationPipeline.swift`) is one actor that runs a
dictation from the microphone opening to the words landing in the focused field. It talks to
every part of the product through protocols only (`AudioCaptureEngine`, `SpeechEngine`,
`TranscriptCleaning`, `ContextEngine`, `TextInserting` and the rest), so every rule below is
tested without a microphone, a model or another app on screen. Turning key presses and clicks
into calls on it is `DictationController`'s job: see [`pipeline-gestures.md`](pipeline-gestures.md).

## The two rules that outrank the others

**The user's words are never lost.** If tidying fails, what they actually said is inserted
instead. If insertion fails, the transcript comes back with the failure so the interface can
offer it. Only a failure before there are any words can end with nothing to show, and then the
kept recording is offered for a retry ([`recordings.md`](recordings.md)). This is why `correct`, `tidy`
and `expand` all swallow their errors and return the text unchanged.

**Cancelling leaves no trace.** Nothing is transcribed, nothing is inserted, and the audio is
discarded. Cancelling *after* the recording has stopped is honoured too: every stage checks
before moving on, so a cancel arriving during transcription discards the result rather than
inserting it.

## The stages, and why they run in this order

```
capture → transcribe → correct → tidy → join → expand → insert → count, learn
```

| Stage | What runs | Measured as (`PipelineStage`) | Time limit (`StageTimeout`) |
|---|---|---|---|
| capture | drain and convert the microphone buffer | `.capture` | `quick`, 15 s |
| transcribe | the recogniser, per piece | `.transcription` | `transcription`, 120 s |
| correct | the personal dictionary, per piece | `.correction` | `quick`, 15 s |
| tidy | the clean-up engines, per piece | `.transformation` | `transformation`, 30 s |
| expand | snippets, over the joined text | `.expansion` | `quick`, 15 s |
| insert | the text inserter, or the clipboard for a retry | `.insertion` | `quick`, 15 s |

`.microphoneOpen`, `.keyDownToAudio` and `.drain` are measured too. Transcribe, correct and tidy
run per piece of the recording, and most pieces are done before the key is released; see
[`early-transcription.md`](early-transcription.md). Everything from the join on sees the pieces
as one text.

- **Correction before tidying.** A correction is argued from the sentence as it was *heard*.
  Word ranges into what the recogniser said stop meaning anything the moment the tidier drops a
  filler, and the evidence the engine weighs (this word said clearly elsewhere in the same
  breath) is evidence about the utterance, not about the prose it is about to become. A second
  correction pass runs over the joined text and keeps only proposals that cross a piece
  boundary (`correctAcrossSeams`).
- **Tidying removes and formats, never composes.** What the tidier may and may not do to the
  words is catalogued in [`cleanup.md`](cleanup.md); the guard beneath it refuses a rewrite that
  drops or invents.
- **Joining lays out the seams.** `PieceJoiner` joins the pieces under the destination's
  formatter; [`cleanup-design.md`](cleanup-design.md) covers what a seam can show. The cleaner's
  message-level passes (`finishMessage`) then run once over the joined text, and
  `LatinScript.enforced` holds the result to Latin letters ([`latin-output.md`](latin-output.md)).
- **Snippets after tidying.** The matcher tolerates the punctuation the tidier adds (a comma
  inside a trigger is a speaker pausing mid-phrase) and refuses a trigger assembled across a full
  stop. Run first, it would be matching a transcript with no sentence boundaries at all, and
  could not tell "Please sign. Off we go" from somebody saying "sign off". Expansions are held to
  Latin letters too.
- **The field is read again just before writing.** `FirstWordPass` sets the first word's case
  from the text around the caret, and `paddedBoundary` adds a space where the surrounding text
  would otherwise run into the words. Both edges read one table in `CaretJoin`, keyed by the
  class of the character either side and the destination; where code is written, a word runs
  straight into the bracket after it. If the frontmost app is no longer the one the dictation
  began in, that read is discarded and both work from an unknown field.
- **Counting and learning last.** A word earns its place by *surviving* a dictation, so nothing
  is learnt from one that never landed, from a paste that was not confirmed, or from a secure
  field; and the user has their text before any of it is attempted, so a slow disk cannot show
  up as a slow dictation.

## Blank is refused twice, and neither is pedantry

A blank transcript is refused, and so is a transcript that *tidying* or snippet expansion reduced
to nothing: "um" is entirely filler and the rule-based tidier strips it. Both end as
`SpeechEngineError.nothingHeard`.

Inserting an empty string is worse than doing nothing. The Accessibility route writes to the
*selected* text, so an empty string deletes whatever the user had highlighted, and the interface
would then report it as a dictation that worked. Someone who selects a paragraph to replace,
hesitates, and says "um" must get their paragraph back, not a success message over an empty
document.

The same reasoning is why `expand` treats a blank expansion as nothing to do rather than as an
expansion.

## Settings are fixed for the length of a dictation

The tidier, the per-app destination overrides and the language profile are taken when the
microphone opens (`takeSettings`), so a change made in Settings while somebody is speaking lands
on the next dictation. A new recogniser chosen in Settings waits until no dictation is under way
(`adopt(speech:)`), so one is never swapped out under a decode. While the recogniser is loading,
`startRecording()` refuses with `.stillLoading` rather than recording words that would wait
behind the load.

## A retry goes to the clipboard

`retry(_:)` runs a kept recording through the same stages and delivers to the clipboard instead
of the field, because the field it was meant for is gone. It reuses the destination recorded
with the audio, so it is tidied for the app it was spoken into.

## Generations

`generation` counts dictations and `cancelledGeneration` names the last one abandoned. Every
stage carries the generation it belongs to and compares against that, rather than re-reading the
pipeline's current one: a run suspended in a stage would otherwise be comparing against a number
that moved the moment the user began their next dictation.

`wasCancelled` uses `<=` rather than `==`: a cancel at any generation up to and including this
one abandons this run, and later cancels belong to later runs.

## The turn

`hasTurn` is held across every await that runs before the state shows what a dictation is doing,
because an actor is reentrant across each one. `startRecording()` holds it while the microphone
opens. `stopListening()` holds it while the buffer drains: the state still reads `.recording`
then, so without it a second stop gesture reaches a microphone that has already closed and
publishes a failure over a dictation that goes on to succeed. `retry(_:)` holds it while it reads
the file, or a dictation could open the microphone underneath it. It is released with no await
before `process` moves the state on, so nothing can enter in between.

`process` checks for a cancel before it moves the state, so a cancel that arrived during the drain
is not overwritten by `.transcribing` and left there. A cancel during the drain also deletes the
recording, which was not yet known when the cancel ran.

The states a dictation passes through are `DictationState`: `.idle`, `.recording`,
`.transcribing`, `.tidying`, `.inserting`, then `.inserted` or `.failed`.

## A press while the last dictation finishes

`startRecording()` returns without a word while `isBusy` holds, and `isBusy` covers
`.transcribing`, `.tidying` and `.inserting` as well as `.recording`. The controller plays the
start cue only when the pipeline is then listening, so a press in that window opens no
microphone, plays no cue and shows no failure: the user speaks into nothing.

How long the window lasts, from key-up to the pipeline leaving the busy states, measured with
`uttrflow-dev bench` (debug build, real-time playback, shipping tidier, printing inserter, so no
target app's insertion time is included) on an Apple M5 Pro under heavy parallel load, with five
synthetic `say` clips each run twice:

| Clip audio | Busy after key-up, run 1 | Run 2 |
|---|---|---|
| 0.99 s | 1.14 s | 3.45 s |
| 2.08 s | 8.65 s | 4.02 s |
| 3.40 s | 5.23 s | 10.24 s |
| 5.46 s | 5.73 s | 16.88 s |
| 8.78 s | 6.12 s | 15.81 s |

Median 5.9 s, range 1.1 to 16.9 s. A real target app's insertion and paste confirmation add to
this. The window is long enough that a second sentence started right after the first one lands in
it. How often a second press lands there in use is not measurable from this harness.

```bash
swift build --disable-sandbox --product uttrflow-dev
.build/debug/uttrflow-dev bench jobs.tsv --idle-before 3   # "wait" is the busy window
```

## Timeouts

Every stage runs somebody else's code and none of it promises to return. A stage that passes its
`StageTimeout` is cancelled and not awaited. See [`stuck-recording.md`](stuck-recording.md).
