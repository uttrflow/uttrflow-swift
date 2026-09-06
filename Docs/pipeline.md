# The dictation pipeline

`DictationPipeline` is the whole product expressed once, over protocols only, so every
rule below is tested without a microphone, a model or another app on screen.

## The two rules that outrank the others

**The user's words are never lost.** If tidying fails, what they actually said is
inserted instead. If insertion fails, the transcript comes back with the failure so the
interface can offer it. Only a failure before there are any words can end with nothing
to show. This is §19, and it is why `correct`, `tidy` and `expand` all swallow their
errors and return the text unchanged.

**Cancelling leaves no trace.** Nothing is transcribed, nothing is inserted, and the
audio is discarded. Cancelling *after* the recording has stopped is honoured too: every
stage checks before moving on, so a cancel arriving during transcription discards the
result rather than inserting it.

## The order of the stages, and why it is that order

```
capture → transcribe → correct → tidy → expand → insert → count, learn
```

The first three run per piece of the recording, and most pieces are done before the key
is released; see `Docs/early-transcription.md`. Everything from `expand` on sees the
pieces joined.

- **Correction before tidying.** A correction is argued from the sentence as it was
  *heard*. Word ranges into what the recogniser said stop meaning anything the moment
  the tidier drops a filler, and the evidence the engine weighs — this word said
  clearly elsewhere in the same breath — is evidence about the utterance, not about the
  prose it is about to become.
- **Tidying removes and formats, never composes.** What the tidier may and may not do
  to the words is catalogued in `Docs/cleanup.md`; the guard beneath it refuses a
  rewrite that drops or invents.
- **Snippets after tidying.** The matcher tolerates the punctuation the tidier adds — a
  comma inside a trigger is a speaker pausing mid-phrase — and refuses a trigger
  assembled across a full stop. Run first, it would be matching a transcript with no
  sentence boundaries at all, and could not tell "Please sign. Off we go" from somebody
  saying "sign off".
- **Counting and learning last.** A word earns its place by *surviving* a dictation, so
  nothing is learnt from one that never landed — and the user has their text before any
  of it is attempted, so a slow disk cannot show up as a slow dictation.

## Blank is refused twice, and neither is pedantry

A blank transcript is refused, and so is a transcript that *tidying* reduced to nothing
— "um" is entirely filler and the rule-based transformer strips it.

Inserting an empty string is worse than doing nothing. The Accessibility route writes to
the *selected* text, so an empty string deletes whatever the user had highlighted, and
the interface would then report it as a dictation that worked. Someone who selects a
paragraph to replace, hesitates, and says "um" must get their paragraph back, not a
success message over an empty document.

The same reasoning is why `expand` treats a blank expansion as nothing to do rather than
as an expansion.

## Generations

`generation` counts dictations and `cancelledGeneration` names the last one abandoned.
Every stage carries the generation it belongs to and compares against that, rather than
re-reading the pipeline's current one — a run suspended in a stage would otherwise be
comparing against a number that moved the moment the user began their next dictation.

`wasCancelled` uses `<=` rather than `==`: a cancel at any generation up to and
including this one abandons this run, and later cancels belong to later runs.

## Timeouts

Every stage runs somebody else's code and none of it promises to return. See
`Docs/stuck-recording.md`.
