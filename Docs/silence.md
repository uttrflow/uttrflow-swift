# Silence, and why it has to be caught before the recogniser

## What users saw

Hold the shortcut, say nothing, let go — and "Thank you." is typed into the document.
Hold it in a quiet room and get "..." instead. Speak normally with a pause before and
after, and a stray word is appended to the end of a good sentence.

## Why

Whisper does not return nothing for audio with no speech in it. It was trained on
captioned video, and the captions over the silent parts are sign-offs and filler, so
silence decodes to the most likely caption for silence. Measured here on the shipping
model, `openai_whisper-large-v3-v20240930_turbo_632MB`:

| Input, 20 seconds            | Transcript  |
|------------------------------|-------------|
| digital silence              | `Thank you.` |
| room tone at about −60 dBFS  | `...`        |
| room tone at about −34 dBFS  | `...`        |
| broadband hiss at −30 dBFS   | `...`        |
| two keyboard clicks          | `...`        |
| a breath on the microphone   | `...`        |

`...` matters as much as `Thank you.` does: it is not whitespace, so
`Transcription.isBlank` is false, and the pipeline inserts it. Insertion through the
Accessibility route writes to the *selected* text, so a stray transcript can replace
whatever the user had highlighted.

## Why WhisperKit's own guard does not fire

`DecodingOptions.noSpeechThreshold` defaults to 0.6 and is consulted in two places —
`DecodingFallback.init` and `SegmentSeeker` — but in WhisperKit 0.18 the value it is
compared against is a constant:

```swift
// WhisperKit 0.18, Core/TextDecoder.swift:993
let noSpeechProb: Float = 0 // TODO: implement no speech prob
```

`0 > 0.6` is never true, so the gate is dead in both places. Passing a different
threshold changes nothing. This is worth knowing before anybody tries to fix silence by
tuning the decoder: there is no value that works.

## What the app does instead

`VoiceActivity` in `UttrflowCore` judges the audio before it is decoded, and
`BackedSpeechEngine` refuses what holds no speech with `SpeechEngineError.nothingHeard`
— which already had a message, a severity and an interface treatment.

Loudness is measured over 20 ms frames. Two tests have to pass:

- the loudest frames reach an absolute floor of about −46 dBFS, which a quiet room
  does not;
- and either they reach a speaking level, or they stand at least three times above the
  recording's own tenth-percentile frame — noise sits at one level where speech rises
  and falls.

The second test is bounded by the first clause deliberately. It cannot tell a steady
tone from a steady hiss, and getting that wrong in one direction costs a dictation
while the other costs a stray line, so anything at a speaking level is kept whatever
its shape.

The same pass returns *where* the speech is, and only that span is transcribed, with a
200 ms margin either side so no onset is clipped. Segment timings are shifted back by
the trimmed lead-in, so they still describe the recording the user made.

## What it is worth

Measured on a 13-second sentence with 2.5 s of lead-in and 3 s of tail — an ordinary
hold-to-talk recording:

| | transcript | time |
|---|---|---|
| before | correct sentence, plus a hallucinated word from the tail | 1.70 s |
| after  | correct sentence | 1.01 s |

The silence was 30% of the recording and 41% of the transcription time. A trimmed
recording now costs exactly what the same speech costs with no padding at all.

## The bracketed markers, which are a different thing

Recognisers also emit explicit non-speech markers — `[BLANK_AUDIO]`, `(music)`,
`[ Silence ]` — and `RawTranscript.cleaned` strips them. That is a separate defence from
the one above and still earns its place: a recording that *does* hold speech can carry a
marker in the middle of it.

Three conditions have to hold together before a bracket is treated as a marker, because
each one alone destroys real dictation:

- the bracket stands alone, not attached to a word — otherwise `get_user(id)` loses its
  argument, and dictating code is a headline use of this product;
- the contents are only letters — otherwise `[1, 2, 3]` disappears;
- there are at most three words — otherwise a spoken aside in parentheses goes with them.
