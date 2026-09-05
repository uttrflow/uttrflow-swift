# Working ahead while the key is held

A dictation used to begin its work the moment the key was released: transcribe all of
it, tidy all of it, insert. Now the recording is cut into pieces at the speaker's own
pauses, each piece is recognised and tidied while the key is still held, and releasing
the key leaves only the last piece to do. This is why a two-minute dictation and a
ten-second one now wait about the same.

## What was measured, and why this is the fix

Taken on 5 September 2026, M5 Pro, the shipping turbo Whisper model already loaded,
Apple's on-device model tidying, synthesised speech cut to exact lengths, median of two
runs. The wait is what happened between the key going up and the words being ready.

| speech | transcription | tidying | wait |
|---|---|---|---|
| 10 s | 0.9 s | 1.05 s | 2.0 s |
| 30 s | 2.3 s | 2.0 s | 4.3 s |
| 60 s | 4.0 s | 3.7 s | 7.7 s |
| 120 s | 7.5 s | 6.7 s | 14.2 s |
| 180 s | 11.2 s | 9.7 s | 20.9 s |
| 240 s | 14.5 s | 13.8 s | 28.3 s |
| 300 s | 18.2 s | 6.0 s, then the raw words | 24.2 s |

Both stages grow with the speech, at about 0.06 s and 0.055 s per spoken second, on
top of roughly 0.3 s and 0.5 s that every dictation pays. The wait is therefore about
12% of what was said plus a second, and the recogniser runs at sixteen times real time
— which is the whole opportunity: it can keep up with a speaker with room to spare, and
so can the tidier.

**The two stages do not compete.** Run at the same moment, a 120-second transcription
took 8.47 s alone and 8.47 s beside a tidy, and the tidy took 3.79 s alone and 3.90 s
beside the transcription. One is Neural Engine work and the other is not.

**Cutting the tidying into pieces costs nothing.** Four pieces of a five-minute
transcript tidied one after another took 16.6 s; the whole would have taken about 17 s.

**Two things do not help, and were measured so nobody tries them again.** WhisperKit's
own voice-activity chunking with four concurrent workers changed nothing at any length
(300 s: 18.5 s against 18.6 s), because the Neural Engine is one serial resource. Four
tidying sessions started at once took exactly as long as four in a row (16.1 s against
16.6 s); the model serialises them.

**Past about four minutes the tidier loses words.** Given 943 spoken words Apple's
model returned 253; given 755 it returned 747. The meaning guard rejects the short
answer, six seconds are spent finding that out, and the user gets the raw words. Pieces
never get near that length, so this cannot happen any more — but the last row of the
table is what a retry of a kept five-minute recording used to produce.

## How it works

`SpeechWindowing` decides where a piece ends, from the loudness frames `VoiceActivity`
already computes. A piece must hold at least five seconds; after that, a pause of 0.8 s
ends it, which is a sentence ending rather than a breath. Once a piece holds fifteen
seconds, a pause of 0.4 s will do. A piece never holds more than thirty seconds, the
recogniser's own window, and with no pause at all it is cut there — which is exactly
what the recogniser would have done to it anyway.

While recording, `DictationPipeline` looks at the audio so far once a second
(`AudioCaptureEngine.capturedSoFar()`, a copy of the buffer at the canonical rate). The
moment a piece can be ended it is recognised, put through the dictionary, and tidied,
against the screen as it was when the piece was cut. Its timings are not recorded: the
diagnostics page reports what the user waited for, and nobody waited for these.

When the key comes up, a piece under way is finished rather than thrown away, and the
audio after the last cut is windowed the same way and processed in order — the final
piece, usually, or every piece for a retried recording. Those timings are added up per
stage into one measurement, so a dictation done in pieces still reports one figure for
transcription and one for tidying.

The pieces are then joined with a space. Corrections keep their word ranges by being
shifted past the words of the pieces before them. If any piece fell back to the rules,
the whole dictation is reported as tidied by the rules, because "tidied by Apple's
model" would be untrue of some of the words.

### What a piece boundary costs

The tidier sees each piece alone. A sentence that straddles a pause long enough to cut
at is tidied as two sentences, and each piece is given a terminal full stop, so a
speaker who pauses 0.8 s mid-sentence in the first fifteen seconds gets a full stop
there. That is the trade the pause lengths above are set to make rare, and it is the
whole reason the early threshold is a sentence-length pause rather than any pause.

Snippets and the blank check run over the joined text, as before, so a trigger cannot
be assembled across a piece boundary any more than across a sentence.

### What cancelling means

Cancelling still leaves no trace: no piece is inserted, and a piece that finishes after
the cancel is dropped, because every piece checks its dictation's generation before it
is kept. Nothing reaches the screen before the key is released.

### Warming the tidier

Apple's model pays for its instructions before it reads the utterance. Made at the
start of the recording and pre-warmed, a session brought a ten-second utterance's
tidying from 1.25 s to 0.92 s, so `TranscriptCleaning.warm()` is called as recording
begins and `AppleFoundationCleanupModel` keeps that one session for the request that
follows. It is still a fresh session per utterance: it is handed out once.

## Reproducing the numbers

`uttrflow-dev transcribe <file>` prints transcription and tidying separately for one
file. The sweep above used `say -v Samantha` at 16 kHz cut to exact lengths, and
`uttrflow-dev clean` for the tidying-only measurements.
