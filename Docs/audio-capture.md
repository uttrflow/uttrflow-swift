# Capturing the microphone

`UttrflowAudio` (`Sources/UttrflowAudio/`) turns whatever the microphone delivers into canonical
mono 16 kHz `[Float]` samples and plays a cue at each end of a recording.
`AVAudioEngineMicrophoneSource` owns the engine and its tap, `AudioResampler` converts,
`SampleAccumulator` holds the samples, `AVAudioCaptureEngine` is the actor the pipeline talks to,
and `CueSounds.swift` names the cues. This page holds the measured traps behind the one-line
comments. [`microphone.md`](microphone.md) covers the hardware moving under the app;
[`silence.md`](silence.md) covers what happens to audio with no speech in it.

| Constant | Value | What it is |
|---|---|---|
| `AVAudioEngineMicrophoneSource.tapBufferSize` | 4096 frames | the tap's buffer, about 85 ms at 48 kHz |
| `AudioResampler.maxFramesPerConversion` | 2048 frames | the slice fed to `AVAudioConverter` |
| `SampleAccumulator.blockSize` | 4096 samples | one storage block of canonical audio |
| `SampleAccumulator.release` | 0.62 | the share of the momentary level a silent block keeps |
| `TapDrain.cap` | 250 ms | the longest key-up drain |

## AVAudioConverter

- Microphones hand back 44.1 or 48 kHz, one channel or several, interleaved or not.
  `AudioResampler` normalises once, so nothing downstream cares.
- The converter consumes roughly 4000 frames per supply and then reports `inputRanDry` rather
  than asking again, so a single large buffer is silently truncated: measured at 51% of the
  expected output when upsampling 8 kHz. Feeding it in 2048-frame slices recovers 99.8%.
  Calling `convert` repeatedly does not help; only re-supplying does.
- For multichannel input, `AudioResampler` chooses the channel with the greatest energy in each
  2048-frame block. A microphone on any input reaches the recogniser without summing away an
  opposite-phase signal; when several inputs are active, the loudest channel wins and quieter
  simultaneous channels are not mixed.
- Slicing works off the raw buffer list rather than `floatChannelData`, so it is correct for
  interleaved and deinterleaved layouts alike: a buffer's byte size divided by its frame count
  is the bytes per frame in both.
- The converter is stateful and not thread-safe. It is only touched from the capture thread; the
  lock makes that safe rather than merely true today. Its input block is declared `@Sendable`
  but is called synchronously before `convert` returns and never escapes, which is why
  `ConversionInput` is `@unchecked Sendable`.
- The 2048-frame slice and the conversion output are each one buffer, allocated once at
  `AudioResampler.init` and reused for every callback, on the path a buffer already in the
  resampler's own format takes — which is the only path the tap ever exercises, together with
  the object that hands the slice to the converter. The tap reads each converted chunk straight
  out of that output buffer (`resample(_:into:)`), so it builds no array; a buffer in a different format (never produced by the tap; only a misuse
  test constructs one) still allocates its own scratch rather than corrupt the reused pair.

## Resampler fidelity

`AudioResampler` sets the converter's sample-rate quality to `AVAudioQuality.max` and leaves
the prime method at its default. `AudioResamplerFidelityTests` measures what each quality does
to a signal: a 0.5 amplitude
sine on channel 0 of a one-second buffer, passband tones at 100 Hz, 1, 4 and 7 kHz, and
stopband tones at 9, 10, 12, 16 and 20 kHz (each only where the input rate can carry it).
Gain and alias are the RMS of the middle half of the output, relative to the input's RMS.
Measured on an Apple M5 Pro, macOS 26.5; the converter fed in the same 2048-frame slices.

| Input rate | Length error | Passband gain, default | Worst alias, default | Passband gain, max | Worst alias, max |
|---|---|---|---|---|---|
| 8 kHz | 0.20% | 0.0 dB | n/a | 0.0 dB | n/a |
| 16 kHz | 0.00% | 0.0 dB | n/a | 0.0 dB | n/a |
| 22.05 kHz | 0.08% | -4.2 to 0.0 dB | -63.7 dB | -2.0 to 0.0 dB | -115.8 dB |
| 44.1 kHz | 0.04% | -5.0 to 0.0 dB | -21.7 dB | -3.6 to 0.0 dB | -115.3 dB |
| 48 kHz | 0.04% | -5.2 to 0.0 dB | -18.6 dB | -3.8 to 0.0 dB | -102.5 dB |
| 88.2 kHz | 0.02% | -5.5 to 0.0 dB | -12.1 dB | -4.7 to 0.0 dB | -30.8 dB |
| 96 kHz | 0.02% | -5.6 to -0.1 dB | -11.1 dB | -4.9 to 0.0 dB | -26.9 dB |
| 192 kHz | 0.01% | -5.9 to -2.3 dB | -8.3 dB | -5.4 to 0.0 dB | -13.8 dB |

- The length error column is the default quality. The highest quality keeps back a longer delay
  line, worst at 8 kHz, where it holds back 0.60% of one second; the test's length ceiling is 0.7%.
- Every row is identical for mono, stereo, interleaved stereo and 9 channels: the channel map
  selects channel 0 cleanly in each layout.
- The lowest passband gain is always the 7 kHz tone, so both settings roll off before the
  canonical Nyquist; the worst alias is the 9 kHz tone, inside the transition band.
- At the default, 44.1 and 48 kHz (the rates microphones deliver) leak a 9 kHz tone at
  roughly -20 dB; the highest quality pushes that below -100 dB.
- CPU, 60 s of 48 kHz mono in 4096-frame blocks: about 1.5 ms per audio second at the default
  and 3.5 ms at the highest quality.

The highest quality is used: it removes the -20 dB alias at the rates microphones deliver for
about 2 ms more CPU per audio second, 0.35% of one core. `AudioResamplerFidelityTests` holds
the production path to the highest-quality alias figures per rate, so a fall back to the
default fails.

## Microphone access is read before the engine

`EngineDevice.open()` refuses with `AudioCaptureError.microphoneDenied` unless
`AVCaptureDevice.authorizationStatus(for: .audio)` is `authorized`, and it does so before an
`AVAudioEngine` exists. Nothing else in the capture path reads the authorisation, and the
hardware check after it, `format.sampleRate > 0` and a channel count above zero, catches a
missing device and not a refused one, because a refused microphone still reports the device's
real format.

Without the guard the engine opens, the tap delivers, and the samples carry no speech, so
`VoiceActivity` refuses the recording and the user is told "Didn't catch that." with no recovery
action, for a permission only System Settings can give back. Measured on macOS 26.5.1: three
seconds of digital silence through `uttrflow-dev transcribe` comes back
`SpeechEngineError.nothingHeard`, which is `informational` and offers nothing
([probe-log.md](probe-log.md#rows)).

The guard covers the reopen after a hardware change as well as the first open, because
`InputDeviceSession` reaches the device through the same `open()`.

**Not measured:** whether a refused microphone taps zeros or never calls back at all. Either way
the guard fires first, and either way the message without it is wrong: silence reads as
`nothingHeard`, and an empty recording as `audioTooShort`.

## What the tap thread does

The tap callback converts its buffer and copies the result into `TapHandoff`, and nothing else.
`TapHandoff` is a single-producer, single-consumer ring of floats allocated once per engine: the
tap writes a block behind a length marker, publishes it with one atomic store and signals a
semaphore. A consumer thread of its own delivers each block, in order and one call per callback,
to the sink; the sink check under the device lock, the accumulator, the recording writer's stream
and the drain count all run there, never on the tap thread.

- The ring holds two seconds of canonical audio. A block that does not fit is dropped whole and
  counted in `droppedSamples`; nothing is queued beyond the ring and nothing is reordered.
- The only lock left on the tap thread is the resampler's, which no other thread takes while the
  tap runs, so it is never contended.
- Closing the engine removes the tap, then `finish()` delivers whatever is already in the ring and
  joins the consumer, so a drained stop still receives the block the hardware was filling.

`TapHandoffTests` checks order across the ring's wrap, one delivery per callback, the bounded drop
when full, and that a callback carried through the handoff equals the same buffer resampled whole.
The ring's storage is allocated once in `init` and the producer path holds no array, by
construction. **Not measured:** an allocation count on the real tap thread, callback duration, and
late blocks during a real microphone recording; those need Instruments against a live microphone.
`AVAudioConverter` and the Swift-to-Objective-C bridging of its input block may still allocate
internally, which this code cannot remove.

## Gaps in the capture timeline

Samples cannot say that time passed, so a buffer the tap never received, a conversion that threw,
or a block the full ring refused would otherwise join the audio either side of it and cut or fuse
words. `TapClock` checks every buffer's `AVAudioTime.sampleTime` against where the last delivered
buffer ended (`CaptureTimeline`):

- A hole under half a buffer is clock jitter and is ignored; a step backwards is a new clock.
- A hole up to 100 ms is filled with silence of the same length, pushed in the same block as the
  buffer after it, from zeros allocated once per engine, so word timings stay on the real clock.
- A longer hole sets a flag the handoff's thread takes before delivering the next block, and the
  session reports it as `CaptureInterruption.began`, which marks a discontinuity exactly as a
  device change does (see [`microphone.md`](microphone.md)).
- A lost buffer leaves the expected start where it was, so it reappears as the hole before the next
  one; lost buffers, holes and total hole length are counted on the timeline.

`CaptureTimelineTests` drops every fifth 1024-frame buffer at 48 kHz for 201 buffers and gets a
canonical sample count equal to the elapsed time within one block. **Not measured:** how often
holes happen on a real microphone under load, and so whether 100 ms is the right bound.

Each engine's counts are copied to atomics after every buffer, summed across the engines one
recording ran on (a device change reopens one), and read once after the microphone stops. They
travel with the recording as `AudioSamples.gaps` and reach the capture-quality summary as
`CaptureQuality.gaps` (see [`capture-quality.md`](capture-quality.md)).

## The level meter

- A microphone tap runs on a real-time thread that must never wait on an actor, so samples reach
  `SampleAccumulator` through the handoff above, on its consumer thread. The accumulator is a
  lock-guarded box with one producer and one consumer; sealing a block allocates the next one, which
  is why that work stays off the tap thread. `momentaryLevel` is `nonisolated` on the capture
  engine for the same reason: a meter on the main actor reads it twenty times a second and must
  not queue behind a `stop()` that is converting a recording.
- The momentary level is root mean square, not the block's peak: a meter driven by peaks reads
  every click and lip smack as speech, which makes an animated meter look as though it is not
  listening to anything.
- Attack is immediate and release is gradual (0.62 of the level survives a silent block). It is
  applied per block because blocks are the only clock the accumulator has: one arrives roughly
  every 85 ms at the tap's 4096 frames, and a decay in wall time would need a timestamp the
  capture thread should not be asked for.
- `peakLevel` is a high-water mark that never falls: useful for asking afterwards whether the
  microphone was muted, useless for a meter, because one loud syllable would peg it.
- The accumulator is reset before a recording starts, not after it stops, so a crash
  mid-recording cannot prepend audio to the next one.

## Why the samples are stored in blocks

Working ahead reads the audio while it is still growing: `capturedSoFar(from:)` is called once
a second for the whole of a dictation. A single `[Float]` is not used: handing that array out
makes it non-uniquely referenced, so the very next `append`, which runs on the tap's real-time
thread inside the same lock, would copy the whole buffer before it could add anything. At
canonical mono 16 kHz that is 15.4 MB at four minutes, once per read, charged to the one thread
that must never pay for anything.

So the samples live in fixed 4096-sample blocks. A block is written until it is full, then
sealed and never touched again, and a fresh one is opened with its capacity reserved up front.
A reader takes references to the sealed blocks and a copy of the open one — at most 16 KB —
and lays them end to end after the lock is released. The capture thread therefore only ever
appends into a block it uniquely owns, and its cost per block is bounded by the block size
rather than by the length of the recording.

`copiedOnAppend` counts the samples the capture thread has had to copy because its storage moved
under it, which is what makes the invariant above checkable instead of asserted: it is zero
across any number of reads, where a single array grows it by the whole buffer on every read.
`Tests/UttrflowAudioTests/SampleAccumulatorTests.swift` holds the measurement.

**Not measured:** whether a whole-buffer copy would make the tap late. The block budget is 85 ms
and a 15 MB copy is on the order of a millisecond or two, so a dropped block is plausible and has
not been observed. The allocation behaviour is measured; the latency is not.

## Draining the tap at key-up

A tap delivers whole buffers. Installed at 4096 frames, it fills for about 85 ms at 48 kHz before it
calls back, so at the instant the key comes up the hardware is part-way through a buffer that has
not been handed over. Removing the tap there discards it, and nothing downstream can add samples
that were never captured — usually that falls in the gap between the last word and the key release,
and when the user lets go quickly it takes the tail of the final word.

So `MicrophoneSource.stop(draining:)` waits before tearing anything down. `TapDrain` returns as soon
as the next block arrives and at the latest when the window closes, and the window is one tap period
computed from the buffer size and the rate the device is actually running at
(`TapDrain.window(tapFrames:sampleRate:)`), not a constant, so it follows the buffer size. It is capped at 250 ms, because a device that misreports its
rate would otherwise hold key-up open for as long as it liked.

A cancelled recording does not drain: its audio is discarded, so waiting for more of it would only
delay the key coming up.

Not draining gives up the rendezvous with the render thread, so a tap callback already in flight at
teardown can still run afterwards. Two guards make that harmless. Each recording's sample closure
runs behind a gate that `stop()` and `cancel()` close under the same lock the closure appends under,
so once teardown returns nothing more reaches that recording's buffer or file. And the device pins
each tap to the sink it was opened for, so a late callback from an earlier engine never reaches the
sink a later recording installed.

Measured at the seam rather than on hardware, with a fake source holding one block back: a drained
stop returns 1,365 more canonical samples than an undrained one, which is 85.3 ms — one tap period
at 4096 frames and 48 kHz, resampled to 16 kHz. What the converter keeps back is a separate and much
smaller loss: `AudioResampler` reuses one stateful `AVAudioConverter` across calls, so its delay line
is emitted on the next call and only the final residual is lost.

## Timing the drain on a device

`TapDrain.wait` returns what it found: how long it slept, whether a block arrived inside the
window, and how many converted samples the latest block carried. The microphone source keeps the
latest one with the tap size and device rate as `lastDrain`, and `uttrflow-dev record` prints it
after each stop, so repeated records on one input give the drain time per device:

```bash
uttrflow-dev record --seconds 3
```

The last block's sample count shows whether the device honoured the tap size: at 4096 frames and
48 kHz a block converts to about 1,365 samples at 16 kHz, and a larger count means the engine
delivered a larger block than asked. **Not measured:** drain p50 and p95 per device and the
delivered block length at 1024 and 2048 frames, which need a person speaking into each input, and
the CPU cost of a smaller tap.

## A key released before the last word ends

The drain keeps the block that was filling at key-up and nothing after it, so a hold released while
the last word is still being said loses whatever of that word falls past the block boundary.
`uttrflow-eval tail` measures how often that costs the word. It synthesises invented sentences with
`say` in four voices (32 clips at 48 kHz), finds where each clip's speech ends (the last 10 ms frame
within `TailCut.speechFloorDecibels` of the loudest), and cuts it so that the speech runs on 0 to
400 ms after the key-up. `TailCut.kept` then keeps what the drained stop would keep for each tap size,
at four evenly spaced block phases, and the result goes through the installed recogniser exactly as
a captured buffer does. A last word counts as kept only when the word alignment ends on a match.

```bash
swift build --disable-sandbox --product uttrflow-eval
.build/debug/uttrflow-eval tail --model-folder <installed model folder>
```

Measured on an Apple M5 Pro with `openai_whisper-large-v3-v20240930_turbo_632MB`. The whole clips lose
no last word (0 of 32), so every loss below comes from the cut. Percentages are of 128 trials per cell
(32 for the undrained row, which has no phase).

| tap frames | drain at 48 kHz | drain at 44.1 kHz | +0 ms | +100 ms | +200 ms | +300 ms | +400 ms |
|---|---|---|---|---|---|---|---|
| undrained | none | none | 0.0% | 6.2% | 18.8% | 43.8% | 68.8% |
| 1024 | 21.3 ms | 23.2 ms | 0.0% | 3.1% | 12.5% | 36.7% | 64.1% |
| 2048 | 42.7 ms | 46.4 ms | 0.0% | 3.1% | 10.9% | 41.4% | 60.2% |
| 4096 | 85.3 ms | 92.9 ms | 0.0% | 3.1% | 7.0% | 38.3% | 50.8% |

The tap size moves the loss by a few points and cannot remove it: even the longest block keeps under
100 ms of the overrun, and from 300 ms on more than a third of last words are gone at every size. So
the tap stays at 4096 frames, and a slow release is answered, if at all, by capture continuing for a
bounded time after key-up rather than by a larger block. A grace of G ms brings every overrun up to G
down to the whole-clip rate, so meeting "loss at 300 ms no worse than at 0 ms" needs G of at least
300 ms on a hold, and it adds G to every hold's key-up wait.

## Cue bleed

Playing a cue around capture puts the cue into the recording. Measured on macOS 26.5, built-in
speakers to built-in microphone, eight interleaved trials with and without the cue: the cue
raised the peak level of the first 700 ms of capture by about 6 dB on average, and the loudest
trial reached −11.5 dBFS against a −25.3 dBFS quiet mean, comfortably inside the range the
recogniser treats as speech.

The head of the recording is exposed, because playing a cue returns immediately (under 0.1 ms;
the engine start happens on the player's own queue) while the sound goes on afterwards:
`DictationController` plays the start cue after the pipeline is listening, so the whole cue lands
in the recording.

The tail is not. `AVAudioCaptureEngine.stop()` plays the stop cue after the microphone source has
stopped and before the buffer is taken, so none of it is recorded. The key-up drain sits in front
of that, so the stop cue lands up to one tap period after the key comes up. The controller and the
engine hold the same cue, which is what keeps a stop from sounding after a start that did not. A
cancelled recording plays no stop cue.

What mitigates it, in descending order of effect:

1. Acoustic echo cancellation. `AVAudioInputNode.setVoiceProcessingEnabled(true)` cut the bleed
   from +14.2 dB to +1.5 dB over room noise. Not adopted: it belongs to the capture engine, not
   the cue; it changed the input format from 1 channel to 9 on the Mac measured, which the
   resampler would reduce to one channel; and it imposes AGC and noise suppression the recogniser
   has not been tuned against.
2. Being quiet and soft, which is all the cue can do by itself. The low-pass takes off the bright
   top that carries furthest into a microphone. Measured on the source samples, before speakers or
   room: the shaped start cue peaks at −14.0 dBFS against −16.7 dBFS for an unshaped `Tink` at
   0.4, and its first 700 ms average −36.1 dBFS RMS against −36.7 dBFS. It is 1.94 s long, most
   of it a quiet tail.

Deliberately not a mitigation: waiting for the start cue to finish before opening the
microphone. It buys silence at the cost of half a second before the user may speak.

**Trimming a lead-in is also deliberately not a mitigation, by measured decision.** A fixed-window
trim would convert a probabilistic bleed into deterministic word loss for users who press and
speak, so the cue stays in the buffer. `uttrflow-eval cue-bleed` measures what the bleed costs: it
renders the shipping start cue (`Pop`, −3 semitones, 3000 Hz low-pass; 1.94 s, source peak
−14.1 dBFS) with `CueShaping`, scales it to a leak level, mixes it into the head of the 32 `say`
clips the `tail` probe uses, with the speech starting 0, 700 or 1200 ms in so it lands inside the
cue's tail, and compares the words from `BackedSpeechEngine` against the same clip with no cue.
Measured on an Apple M5 Pro with the shipping Whisper model, word edits over 244 reference words:

| Speech starts | No cue | −20.0 dBFS | −11.5 dBFS | −8.8 dBFS |
|---|---|---|---|---|
| 0 ms | 4 | 5 | 5 | 5 |
| 700 ms | 1 | 1 | 1 | 1 |
| 1200 ms | 1 | 1 | 1 | 1 |

−11.5 dBFS is the loudest measured real leak and −8.8 dBFS is 2.7 dB above it, the margin by
which the shaped cue's source peak exceeds the unshaped `Tink` it replaced. Speech inside the tail
loses nothing at any level. Speech from the first sample costs one word in one clip, the same at
every level, so it follows the cue's onset under the first word rather than its loudness.

```bash
swift build --disable-sandbox --product uttrflow-eval
.build/debug/uttrflow-eval cue-bleed --model-folder <installed model folder>
```

## Spoken announcements

VoiceOver speaks through the same speakers the cue does, and unlike the cue it speaks words, which
the recogniser writes down. `uttrflow-eval announcement-bleed` renders each line VoiceOver could
speak while the microphone is open with `say -v Samantha`, scales it to the cue's leak levels,
mixes it into the head of the same 32 clips, and counts the announcement's words that reach the
recogniser's output and are not in the clip. Measured on an Apple M5 Pro with the shipping Whisper
model; each cell is words added, with the clips that gained any in brackets:

| Line | Speech starts | −25.3 dBFS | −20.0 dBFS | −11.5 dBFS | −8.8 dBFS |
|---|---|---|---|---|---|
| "Listening." | 0 ms | 0 (0) | 0 (0) | 0 (0) | 0 (0) |
| "Listening." | 700 ms | 14 (14) | 28 (28) | 32 (32) | 32 (32) |
| "Listening." | 1200 ms | 32 (32) | 32 (32) | 32 (32) | 32 (32) |
| The cap warning | 0 ms | 0 (0) | 0 (0) | 1 (1) | 1 (1) |
| The cap warning | 700 ms | 0 (0) | 0 (0) | 0 (0) | 0 (0) |
| The cap warning | 1200 ms | 0 (0) | 8 (2) | 19 (5) | 15 (4) |
| A read-back, "Inserted: …" | 0 ms | 0 (0) | 0 (0) | 0 (0) | 3 (2) |
| A read-back, "Inserted: …" | 700 ms | 1 (1) | 4 (4) | 13 (13) | 15 (15) |
| A read-back, "Inserted: …" | 1200 ms | 10 (10) | 46 (12) | 126 (17) | 157 (21) |

A line spoken into silence is transcribed; speech over its first word hides it. So nothing is
spoken while the microphone is open, through one rule in `AnnouncementHold` and
`DictationAnnouncer`:

1. **Start.** A heard start cue is the announcement; "Listening." is spoken only when sounds are
   off (`RecordingCueing.isAudible`).
2. **Cap warning.** The warning cue and the floating button's countdown carry it;
   `DictationWarningReporter` speaks it only when that cue is not heard.
3. **Every other line** raised while recording waits in `AnnouncementHold` and is spoken, in order,
   when the microphone closes. "Can't hear you" is the one exception: it is said only when the
   input is dead, so there is nothing to record it.

The table is synthetic: a recorded VoiceOver line, through real speakers at VoiceOver's own
volumes, has not been measured, and a read-back still being spoken when the next recording starts
is not held back, since it was posted before the microphone opened.

```bash
.build/debug/uttrflow-eval announcement-bleed --model-folder <installed model folder>
```

## Changing the cue sounds

The three cues are one line each in `Sources/UttrflowAudio/CueSounds.swift`:

```swift
public static let start = CueSound("Pop", semitones: -3, lowPassHz: 3000, volume: 0.7)
public static let stop = CueSound("Tink", semitones: -9, lowPassHz: 2200, volume: 0.7)
public static let warning = CueSound("Glass", semitones: -3, lowPassHz: 3000, volume: 0.7)
```

- The name is any sound in `/System/Library/Sounds` (or `~/Library/Sounds`), without its extension.
- `semitones` shifts pitch by reading the sound faster or slower, so it also changes the length:
  the rate is 2^(semitones/12), and −12 plays an octave down at twice the length.
- `lowPassHz` is the cutoff of a second-order low-pass whose resonance is 0.5 dB, the unit and
  value a browser's `BiquadFilterNode` reads `Q` in, so a sound auditioned there with
  `playbackRate`, a `lowpass` filter at `Q` 0.5 and a gain node sounds the same here.
- `volume` is linear gain from 0 to 1.

`CueSoundsTests` (`Tests/UttrflowAudioTests/CueSoundsTests.swift`) pins the values, so a change edits the test beside it. Whatever the start cue
becomes lands in the recording; re-measure it against the numbers under *Cue bleed*.

## Playing a system sound reliably

- Uttrflow carries no audio of its own, and ships no copy of a system sound: the shaping runs on
  the Mac's own file when the app starts. A borrowed system sound is one the user recognises as
  their machine rather than this app, it follows whatever they replaced it with in
  `~/Library/Sounds`, and there is no asset to lose.
- Playing is a chain. `ShapedSoundPlayer` plays the shaped cue through an output-only
  `AVAudioEngine`; when its engine or the sound file cannot be had, `SystemSoundPlayer` plays the
  same named sound unshaped through `NSSound` at the cue's volume; when that fails too, the cue is
  silent and dictation carries on. An engine that fails to start after `play` has returned leaves
  that one cue silent and hands the next to `NSSound` while it rebuilds.
- Shaping happens once, at prewarm, into one 48 kHz (`ShapedSoundPlayer.outputRate`) mono buffer per cue, each on its own player
  node so a stop cue never cuts off a start cue still sounding. The first engine start of a process
  costs about 37 ms, paid at prewarm; a start from pause costs 8 to 40 ms depending on how long the
  output device has been idle, and happens on the player's queue rather than the caller's.
- The engine pauses one second (`ShapedSoundPlayer.idleSeconds`) after the last cue ends, so the output device is not held open
  between dictations, and it is rebuilt when the output device changes.
- `play()` on an `NSSound` that is still playing returns `false` and does nothing, so a second
  dictation inside the previous cue's half-second tail would be silent and, worse, would report
  failure and suppress its own stop cue. Stopping first makes a retrigger restart the sound:
  measured 5/5 successes at 120 ms spacing against 0/5 without. It also covers a starved main run
  loop, where `isPlaying` never clears.
- The first `NSSound` of a process costs about 118 ms inside AppKit building its output graph,
  then 12 ms per sound. Prewarming pays it at construction rather than on the keystroke that starts
  a dictation.
- A stop cue is owed only after a start cue the user could have heard, and the pair is closed
  whether or not the stop cue plays, so a cue suppressed by the setting is never left owed to the
  next recording.
