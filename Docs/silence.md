# Silence, and why it has to be caught before the recogniser

Uttrflow judges a recording for speech before any recogniser sees it, and strips the
non-speech markers a recogniser writes into its text. `VoiceActivity`
(`Sources/UttrflowCore/Support/VoiceActivity.swift`) finds the speech, `BackedSpeechEngine`
(`Sources/UttrflowSpeech/BackedSpeechEngine.swift`) refuses audio with none, and
`RawTranscript.cleaned` (`Sources/UttrflowSpeech/RawTranscript+Mapping.swift`) removes the
markers. The same loudness rule cuts a long recording into pieces
([`early-transcription.md`](early-transcription.md)).

## What silence becomes without it

Hold the shortcut, say nothing, let go, and "Thank you." is typed into the document. Hold it in a
quiet room and get "..." instead. Speak normally with a pause before and after, and a stray word
is appended to the end of a good sentence.

Whisper does not return nothing for audio with no speech in it. It was trained on captioned video,
and the captions over the silent parts are sign-offs and filler, so silence decodes to the most
likely caption for silence. Measured by decoding 20-second files directly with the shipping model,
`openai_whisper-large-v3-v20240930_turbo_632MB`, with no voice-activity check in front of it:

| Input, 20 seconds            | Transcript  |
|------------------------------|-------------|
| digital silence              | `Thank you.` |
| room tone at about −60 dBFS  | `...`        |
| room tone at about −34 dBFS  | `...`        |
| broadband hiss at −30 dBFS   | `...`        |
| two keyboard clicks          | `...`        |
| a breath on the microphone   | `...`        |

`...` matters as much as `Thank you.` does: it is not whitespace, so `Transcription.isBlank` is
false, and it would be inserted. Insertion through the Accessibility route writes to the
*selected* text, so a stray transcript can replace whatever the user had highlighted.

## Why WhisperKit's own guard does not fire

`DecodingOptions.noSpeechThreshold` (0.6, set in `VocabularyPrompt.decodingOptions`) is consulted
in two places, `DecodingFallback.init` and `SegmentSeeker`, but in WhisperKit 1.1.0 the value it
is compared against is a constant:

```swift
// WhisperKit 1.1.0, Core/TextDecoder.swift:817
let noSpeechProb: Float = 0 // TODO: implement no speech prob
```

`0 > 0.6` is never true, so the gate is dead in both places. Passing a different threshold
changes nothing: there is no value that works, so silence is not fixed by tuning the decoder.

## How speech is found

`VoiceActivity.speechRange(in:sampleRate:)` measures loudness as the root mean square of each
20 ms frame. A recording holds speech only if both tests pass:

- its 95th-percentile frame reaches the absolute floor (about −90 dBFS), excluding digital
  silence and values below the recording's usable range;
- and that frame either reaches the speaking level, or stands at least `signalToNoise` times above
  the recording's own 10th-percentile frame: noise sits at one level where speech rises and
  falls.

| Constant | Value | Meaning |
|---|---|---|
| `VoiceActivity.frameDuration` | 20 ms | one loudness frame |
| `VoiceActivity.absoluteFloor` | 0.0000316 RMS, about −90 dBFS | rejects digital silence and values below the recording's usable range |
| `VoiceActivity.assumedSpeechLevel` | 0.05 RMS, about −26 dBFS | louder than this is speech whatever its shape |
| `VoiceActivity.signalToNoise` | 3 | how far speech stands above the room |
| `VoiceActivity.minimumSpeech` | 120 ms | a shorter burst is a click or a bump |
| `VoiceActivity.margin` | 200 ms | audio kept either side of the speech |

The second test is bounded by the speaking level on purpose. It cannot tell a steady tone from a
steady hiss, and getting that wrong in one direction costs a dictation while the other costs a
stray line, so anything at a speaking level is kept whatever its shape.

The same pass returns *where* the speech is: from the first to the last run of at least
`minimumSpeech` above the threshold, with `margin` either side so no onset is clipped. Only that
span is transcribed, and segment timings are shifted back by the trimmed lead-in so they still
describe the recording the user made. A loud, modulated recording with no run long enough to
point at is kept whole.

The loudness a frame must reach is one expression, `VoiceActivity.threshold(forFloor:)`, and both
readers of it (the trim here and the pause `SpeechWindowing` cuts a piece at) ask it rather than
writing it out. It is `signalToNoise` times the 10th-percentile frame, floored at the absolute
floor and **capped at the speaking level**. The cap matters for a piece of a long dictation, which
is mostly speech, so its 10th percentile is not the room: uncapped, the bar would sit above
ordinary speech and trim real words off the piece's head, and nothing downstream could tell,
because the boundary falls at a pause and what is left still reads as a whole sentence.

The focused fixtures accept clean speech at −55 dBFS active-speech RMS over −65 dBFS room noise;
the absolute floor leaves headroom for low input gain while the three-to-one comparison continues
to reject steady room tone and hiss.

A recording that holds no speech is refused with `SpeechEngineError.nothingHeard` ("Didn't catch
that."), whose severity is informational.

## What the trim is worth

Measured on a 13-second sentence with 2.5 s of lead-in and 3 s of tail, an ordinary hold-to-talk
recording, decoded whole and decoded trimmed:

| | transcript | time |
|---|---|---|
| untrimmed | correct sentence, plus a hallucinated word from the tail | 1.70 s |
| trimmed   | correct sentence | 1.01 s |

The silence was 30% of the recording and 41% of the transcription time. A trimmed recording costs
what the same speech costs with no padding at all.

## Recording conditions the loudness measure does not separate

The measure is plain RMS over the whole spectrum, and the floor is one 10th percentile for the
whole recording. Probed with `VoiceActivityConditionTests` (`swift test --filter
VoiceActivityConditionTests`, which prints one `TRIMGRID` line per cell): ten seconds of room noise
at −65 dBFS, two 2-second phrases (a 180 Hz tone with a 3 Hz swell) at 2–4 s and 6–8 s, and one
added condition each. "Clip" is speech cut off; "over" is audio kept beyond speech plus `margin`.

| Speech level | clean | DC offset 0.01 | 60 Hz rumble at −30 dBFS | noise up 15 dB at 5 s |
|---|---|---|---|---|
| −25 dBFS | 0 / 0 ms | 0 / 0 ms | 0 / 0 ms | over 1800 ms |
| −40 dBFS | 0 / 0 ms | **rejected** | **rejected** | over 1800 ms |
| −55 dBFS | 0 / 0 ms | **rejected** | **rejected** | over 1800 ms |

A DC offset or rumble lifts every frame, so the 95th percentile no longer stands three times above
the 10th and the whole dictation is refused as nothing heard. A floor that steps up mid-recording
keeps the louder second half's noise as speech to the end of the recording.

The same grid run through a first- or second-order high-pass at 100 Hz before the measure fixes
DC offset at −40 dBFS but not rumble at either level, and loses −55 dBFS speech that passes
unfiltered (660 ms clipped at first order, rejected at second), because the probe's voice sits at
180 Hz, inside the filter's skirt. Neither filter touches the stepped floor. The measure is
unchanged until a real-speech grid decides between the two candidate changes.

## The bracketed markers

Recognisers also write what they heard instead of speech, in brackets: `[BLANK_AUDIO]`,
`(silence)`, `[ Music ]`, `(upbeat music)`. `RawTranscript.cleaned` takes those out before anything
else sees the text. That is a separate defence from the one above: a recording that *does* hold
speech can carry a marker in the middle of it.

A bracket is also a parenthesis the speaker dictated, at least as often as it is a marker, so the
test is positive. A shape rule alone (a bracket standing on its own, holding at most three words,
all of them letters) is not used, because it deletes a dictated aside: "the API (version two) is
ready" would arrive as "the API is ready", upstream of every guard the cleaning passes have.

A `[…]`, `(…)` or `*…*` is removed only when it stands alone (whitespace or the transcript's edge
before it; whitespace, punctuation or the edge after it) **and** its contents are one of:

| Contents | Rule | Examples removed |
|---|---|---|
| up to three words, every one in `markerWords` | the closed vocabulary a recogniser writes for non-speech | `[Music]`, `(applause)`, `[SOUND]`, `(upbeat music)`, `*thud*` |
| an exact phrase in `markerPhrases` | after case and whitespace are normalised | `[door slams]`, `(phone ringing)`, `[clears throat]`, `(sneezes)`, `(speaking in foreign language)`, `[ Background Conversations ]` |
| `inaudible` and a two-digit `MM:SS` timestamp | `isInaudibleTimestamp` | `[inaudible 00:02]` |
| two or more musical notes, first and last, around letters and whitespace only | `isMusicMarker` | `[♪♪♪]` |

Words are split at whitespace, `_` and `-`. "version two" is not in the vocabulary, so it stays;
`get_user(id)` keeps its argument because the bracket does not stand alone; `[1, 2, 3]`,
`(see the attached file)`, `[TODO]` and `*really*` stay because their words are not markers. A
marker whose wording is not on the list stays too, which is the side of the line this product
errs on: an unfamiliar `[whirring]` in the text is visible and fixable, and a deleted clause is
neither.

Three more forms are removed outside brackets:

- a run of notes enclosing only letters and whitespace, standing alone (the transcript's edge,
  whitespace or punctuation either side), such as `♪♪` or `♪ la la la ♪`; a note inside a word
  stays;
- a standalone run of three or more asterisks, such as `*******`, which is an unlabelled
  non-speech span; speech around it, as in `review the ******* Kubernetes`, remains;
- a `>>` speaker mark at the start of the transcript.

A marker is removed from the recogniser's **words** as well as from its text, and where the words
were reported the text is derived from them (`RawTranscript.cleaned(_ words:)`). Edited separately,
a transcript holding one marker would no longer spell its own word list, `Draft` could not line the
confidences up with it, and it would treat every word as certain, which switches off the
doubtful-word repair for that piece. One representation cannot disagree with itself.

With only markers left, the mapped transcript is blank, so the pipeline treats it as nothing heard
and refuses insertion ([`pipeline.md`](pipeline.md)).

## Measuring what still gets through

`uttrflow-eval nonspeech` (`Sources/uttrflow-eval/NonSpeechProbe.swift`) runs a generated
non-speech corpus through `BackedSpeechEngine`, the same voice-activity check, trim and loop repair
a dictation goes through, so it reports the residual rather than raw decoder behaviour. Every clip
is synthetic and repeatable from its seed (`NonSpeechKind`, `Sources/UttrflowEval/NonSpeech.swift`):

| Kind | Signal, 5 s |
|---|---|
| `silence` | digital zero |
| `roomTone` | low-passed noise at −60 dBFS RMS |
| `hiss` | white noise at −30 dBFS RMS |
| `keyboard` | 15 ms decaying bursts, jittered round one every 0.18 s |
| `breath` | low-passed noise near −40 dBFS rising and falling every 2.5 s |
| `music` | a three-note chord changing every 0.5 s, at −20 dBFS RMS |

Each kind is also appended, `--tail-seconds` long (default 4), after each `SpokenClips` sentence
read by `say`, which is the trailing pause after real speech.

| Rate | Counted per clip | Rule |
|---|---|---|
| insertion rate | the transcript holds words after the last spoken word that were not said; for a clip with no speech, any word | `NonSpeechScore.insertedWords` |
| repetition-loop rate | one phrase of at least 3 words follows itself at least 3 times | `NonSpeechScore.looped` |

Both are gated: the command exits non-zero when either rate is above `--max-insertion-rate` or
`--max-loop-rate`, both 0 by default. `nothingHeard` counts as nothing typed.

## Trim error against known speech boundaries

Probed with `VoiceActivityOnsetGridTests` (`swift test --filter VoiceActivityOnsetGridTests`, one
`ONSETGRID` line per cell). Each clip is one second of white room noise, two synthetic words
150 ms apart, and one second of room, so the speech boundaries are exact. A word is an onset, a
300 ms vowel (a 150 Hz tone) at the speech level, and the onset reversed as its coda. Onsets: a
vowel (none), a plosive (10 ms burst 6 dB down, then a 40 ms gap), a nasal (80 ms of 220 Hz,
12 dB down) and a fricative (100 ms of noise, 20 dB down).

Each cell is the signed error of the start and end of `speechRange`, in milliseconds: a negative
start and a positive end keep audio outside the speech; the reverse would clip it.

| Speech | Floor | vowel | plosive | nasal | fricative |
|---|---|---|---|---|---|
| −45 dBFS | −70 / −60 | −200 / +210 | −160 / +150 | −200…−120 / +210…+130 | −100 / +110 |
| −45 dBFS | −50 to −35 | **rejected** | **rejected** | **rejected** | **rejected** |
| −35 dBFS | −70 to −50 | −200 / +210 | −160 / +150 | −200…−120 / +210…+130 | −200…−100 / +210…+110 |
| −35 dBFS | −40 / −35 | **rejected** | **rejected** | **rejected** | **rejected** |
| −25 dBFS | −70 to −35 | −200 / +210…+190 | −160…−140 / +150 | −200…−120 / +210…+110 | −200…−100 / +210…+90 |
| −15 dBFS | −70 to −35 | −200 / +210 | −160 / +150 | −200…−120 / +210…+130 | −200…−100 / +210…+110 |

No cell clips a speech sample. A quiet onset or coda that stays under the threshold is
covered by `margin`, and what is left of the margin is 200 ms minus the length of the part the
threshold missed: 100 ms for a fricative at its worst, 40 ms of plosive gap and burst. An onset
longer than `margin` and more than `signalToNoise` below its vowel would be clipped; none here is.

Every refused cell has speech 5 dB or less above the floor, under the three-to-one
(about 9.5 dB) comparison, so the whole dictation is refused as nothing heard. The constant
that decides those cells is `signalToNoise`; it stays as it is until a real-speech grid shows
what lowering it admits from steady room tone.
