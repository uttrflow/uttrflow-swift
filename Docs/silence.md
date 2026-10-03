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
`DecodingFallback.init` and `SegmentSeeker` — but in WhisperKit 1.1.0 the value it is
compared against is a constant:

```swift
// WhisperKit 1.1.0, Core/TextDecoder.swift:817
let noSpeechProb: Float = 0 // TODO: implement no speech prob
```

`0 > 0.6` is never true, so the gate is dead in both places. Passing a different
threshold changes nothing. This is worth knowing before anybody tries to fix silence by
tuning the decoder: there is no value that works.

## The brackets that are markers, and the ones the speaker dictated

A recogniser writes what it heard instead of speech in brackets — `[BLANK_AUDIO]`,
`(silence)`, `[ Music ]`, `(upbeat music)` — and `RawTranscript.cleaned` takes those out
before anything else sees the text. It used to decide by shape alone: a bracket standing
on its own, holding at most three words, all of them letters. That shape is a
parenthesis the speaker dictated at least as often as it is a marker, and the words went
silently — "the API (version two) is ready" arrived as "the API is ready", upstream of
every guard the cleaning passes have.

So the test is now positive. `markerWords` lists the words a recogniser actually writes
for non-speech, and a bracket is a marker only when **every** word inside it is one of
them. "version two" is not, so it stays. A marker whose wording is not on the list stays
too, which is the side of the line this product errs on: an unfamiliar `[whirring]` in
the text is visible and fixable, and a deleted clause is neither.

## What the app does instead

`VoiceActivity` in `UttrflowCore` judges the audio before it is decoded, and
`BackedSpeechEngine` refuses what holds no speech with `SpeechEngineError.nothingHeard`
— which already had a message, a severity and an interface treatment.

Loudness is measured over 20 ms frames. Two tests have to pass:

- the loudest frames reach an absolute floor of about −90 dBFS, which excludes digital
  silence and values below the recording's usable range;
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

The loudness a frame must reach to be kept is one expression, `VoiceActivity.threshold(forFloor:)`,
and both readers of it — the trim here and the pause `SpeechWindowing` cuts a piece at — ask
it rather than writing it out. It is three times the tenth-percentile frame, floored at the
absolute floor and **capped at the speaking level**, and the cap is the half that was
missing here: without it, a recording whose own quiet frames are loud — a piece of a long
dictation is mostly speech, so its tenth percentile is not the room — set a bar above
ordinary speech and trimmed real words off the head, where the piece before it had already
ended. Nothing downstream could tell: the boundary falls at a pause, so what is left still
reads as a whole sentence. A cap at the speaking level cannot do that, for the same reason
the second test above is bounded by the first: anything at a speaking level is speech
whatever the rest of the recording looks like.

Clean speech down to −55 dBFS active-speech RMS is accepted in a quiet room. The −90 dBFS
absolute floor leaves headroom for low input gain, while the three-to-one comparison
against the recording's tenth-percentile frame continues to reject steady room tone and
hiss.

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

The general word-list rule has four conditions before a bracket is treated as a marker,
because each one alone destroys real dictation:

- the bracket stands alone, not attached to a word — otherwise `get_user(id)` loses its
  argument, and dictating code is a headline use of this product;
- the contents are only letters — otherwise `[1, 2, 3]` disappears;
- there are at most three words — otherwise a spoken aside in parentheses goes with them;
- and, the decisive one, **every word is in `markerWords`** — the closed vocabulary a
  recogniser actually writes for non-speech. The first three are shape checks a spoken
  aside can also satisfy, as "(version two)" does; the vocabulary check is what tells
  them apart, and it is why "version two" survives while "(music)" does not.

## Caption forms reproduced in issue #2372

[Issue #2372](https://github.com/uttrflow/uttrflow-swift/issues/2372) records recogniser
outputs that survived `RawTranscript.cleaned` in its reproduction probe. The added phrase
entries below are exact phrases from that report; they do not make their component words
general-purpose markers.

| Reproduced output | Evidence recorded in the issue | Matching rule |
|---|---|---|
| `[door slams]` | Kept after mapping and title-cased by both tidiers | Exact phrase `door slams` |
| `(phone ringing)` | Kept after mapping and title-cased by both tidiers | Exact phrase `phone ringing` |
| `[clears throat]` | Kept after mapping and rules tidier | Exact phrase `clears throat` |
| `(sneezes)` | Kept after mapping and rules tidier | Exact phrase `sneezes` |
| `[inaudible 00:02]` | Kept after mapping and rules tidier | `inaudible` followed by a two-digit `MM:SS` timestamp |
| `(speaking in foreign language)` | Kept after mapping and rules tidier | Exact four-word phrase |
| `[ Background Conversations ]` | Kept after mapping and both tidiers | Exact phrase after case and whitespace normalization |
| `♪♪`, `♪ la la la ♪`, `[♪♪♪]` | Kept after mapping; the tidiers also retained or altered the notation | Two or more notes enclosing only words and whitespace |
| `>> Hello there.` | The speaker mark survived mapping and rules cleanup | A `>>` prefix at the start of the transcript |

The same issue table reports `[Music]`, `(applause)`, `[SOUND]`, and `(upbeat music)`;
those already match the existing closed `markerWords` vocabulary. The timestamp and
music-note forms have dedicated structural checks. `(see the attached file)` and `[TODO]`
remain unchanged because neither is one of these exact phrases or a known marker.

A marker is removed from the recogniser's **words** as well as from its text, and where the
words were reported the text is derived from them. The two used to be edited separately, so
a transcript holding one marker no longer spelled its own word list, `Draft` could not line
the confidences up with it, and it fell back to treating every word as certain — which
silently switched off the doubtful-word repair for that piece while the per-word scores were
still being asked for and paid for. One representation cannot disagree with itself.

The same positive rule handles the recogniser's asterisks. A standalone `*…*` is removed
only when every word inside it is in `markerWords`; the incident's words `pain`, `painful`,
`thud`, `thunk`, `puff`, `crack` and `gunshot` are included. `*really*` stays because `really` is
not a marker word. A standalone run of three or more asterisks, such as `*******`, is an
unlabelled non-speech span and is removed on its own; surrounding speech such as `review the
******* Kubernetes` remains. With only markers left, the mapped transcript is blank, so the
pipeline treats it as nothing heard and refuses insertion.
