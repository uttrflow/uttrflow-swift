# Word times as pause evidence

Sentence breaks, paragraph breaks and commas built on the gap between one word's end and the
next word's start rest on the recogniser's word times. Those times come from aligning
cross-attention to the audio, not from measuring the signal. This page records how far they can
be trusted to show a pause, and which measure the timing rules use.

## The probe

`uttrflow-eval pause-timing` speaks twelve phrase pairs with `say` (four voices), cuts each
phrase to its speech at 10 ms, and joins the pair with silence of a known length (0, 150, 300,
600 and 1,000 ms) under seeded room noise at -60 dBFS. The pause is exact because both phrases
are trimmed to their speech before they are joined. Each clip goes through the shipping engine
with word times. The word-time gap is the start of the first word after the pause less the end of
the last word before it; the error is that gap less the length built in. A clip whose transcript
has a different number of words is skipped, because its boundary cannot be found; a clip with the
right count but a drifted boundary is not caught by that check. The probe reads word times from
`SpeechEngine.transcribe`, which applies `PauseSnapping`, so a re-run reports the snapped times and
not the recogniser's own.

The audio column is `VoiceActivity.trailingSilence` on the clip as far as the second phrase
begins: the quiet the shipping voice-activity code finds after the first phrase.

The pairs end the first phrase on a content word, a function word, a filler ("um", "uh") or a
word that precedes a number.

```bash
swift run uttrflow-eval pause-timing                      # the table below
swift run uttrflow-eval pause-timing --voices Samantha --pauses 0 300   # a reduced run
```

## Measured

Shipping model, debug build, 239 clips (1 skipped). Synthetic speech only: no recorded speech
was used, so the hand-marked recorded clips the question also asks for are not in this table.

By pause length

| | Trials | Timed | Word-time error ms (median) | Absolute error ms (median) | Audio error ms (median) | Real pause missing | Pause invented |
|---|---|---|---|---|---|---|---|
| 0 ms | 47 | 47 | +0 | 0 | +40 | n/a | 0% |
| 150 ms | 48 | 48 | -150 | 150 | +10 | n/a | 12% |
| 300 ms | 48 | 48 | -300 | 300 | +0 | 69% | n/a |
| 600 ms | 48 | 48 | -20 | 425 | +0 | 46% | n/a |
| 1000 ms | 48 | 48 | +10 | 220 | +0 | 27% | n/a |

By word before the pause

| | Trials | Timed | Word-time error ms (median) | Absolute error ms (median) | Audio error ms (median) | Real pause missing | Pause invented |
|---|---|---|---|---|---|---|---|
| before a number | 60 | 60 | -25 | 150 | +5 | 50% | 4% |
| content word | 60 | 60 | +0 | 225 | +10 | 36% | 17% |
| filler | 59 | 59 | +0 | 130 | +0 | 39% | 0% |
| function word | 60 | 60 | -150 | 150 | +0 | 64% | 4% |

By word before the pause, pauses of 300 ms and longer only

| | Trials | Timed | Word-time error ms (median) | Absolute error ms (median) | Audio error ms (median) | Real pause missing | Pause invented |
|---|---|---|---|---|---|---|---|
| before a number | 36 | 36 | -210 | 270 | +0 | 50% | n/a |
| content word | 36 | 36 | +140 | 290 | +0 | 36% | n/a |
| filler | 36 | 36 | +10 | 160 | -10 | 39% | n/a |
| function word | 36 | 36 | -300 | 300 | +0 | 64% | n/a |

Clips skipped because the recogniser wrote a different number of words: 1

## Reading the table

- The word-time gap is not a measure of the pause. At 300 ms the median gap is 0 (error -300 ms)
  and 69% of real pauses are missing; at 600 ms the median absolute error is 425 ms and 46% are
  missing; at 1,000 ms 27% are still missing. The probe does not establish why; it shows only that the
  pause is often absent from the word times.
- The same word times invent a pause of 300 ms or more in 12% of the 150 ms clips and in 17% of
  the clips that pause after a content word.
- A pause after a function word is the worst case (64% of pauses of 300 ms and more missing, median
  error -300 ms). A content word has the fewest missing (36%) and a filler has the smallest median
  absolute error (160 ms), but none is good enough to trust.
- No pause length from 150 ms to 1,000 ms meets the trust test (median absolute error within 100 ms
  and the pause shown in 90% of trials, at every length from there up), so the trusted minimum for
  the word times is none.
- The audio measure's median error is between +0 and +40 ms at every length (the 20 ms frame of
  `VoiceActivity` is the likely floor). This is the best case for it: the room is
  quiet and the pause is digital silence between two trimmed phrases. A louder room, breath and a
  trailing consonant decay are not in this probe.

## Decision

**Use the audio measure.** Pause-relative timing rules (sentence breaks, paragraph breaks and
commas) take the length of a pause from the signal, by the energy measure `VoiceActivity` already
implements, and never from the gap between word times. The word times stay usable for which word
is nearest a pause, not for how long the pause was. A rule that wants both must treat the audio
measure as the evidence when they disagree.

Reopened by: a recogniser or alignment change that brings the word-time median absolute error
within 100 ms at 300 ms with the pause shown in 90% of trials, or a run on recorded speech whose
audio-measure error at 300 ms exceeds 100 ms.

## Where the decision is applied

`PauseSnapping.snapped` (`UttrflowSpeech`) runs once, in `BackedSpeechEngine.transcribe`, on the
recogniser's words and the speech it heard. It takes each quiet run of at least 100 ms from
`VoiceActivity.quietRuns`, gives it to the word boundary nearest it (within 150 ms), and ends the
word before at the run's start and begins the word after at its end. A gap of 300 ms or more that
less than half a quiet run covers is closed. Audio with no quiet run is left as heard, so a noisy
room costs no pauses it had. Every reader of `Draft.pause(before:)` then reads the audio's pause.
