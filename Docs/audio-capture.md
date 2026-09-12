# Capturing the microphone

`UttrflowAudio` turns whatever the microphone delivers into canonical mono 16 kHz `[Float]`
samples and plays a cue at each end of a recording. This page holds the measured traps behind
the one-line comments. `Docs/microphone.md` covers the hardware moving under the app;
`Docs/silence.md` covers what happens to audio with no speech in it.

## AVAudioConverter

- Microphones hand back 44.1 or 48 kHz, one channel or several, interleaved or not.
  `AudioResampler` normalises once, so nothing downstream cares.
- The converter consumes roughly 4000 frames per supply and then reports `inputRanDry` rather
  than asking again, so a single large buffer is silently truncated: measured at 51% of the
  expected output when upsampling 8 kHz. Feeding it in 2048-frame slices recovers 99.8%.
  Calling `convert` repeatedly does not help; only re-supplying does.
- Above stereo the converter has no spatial mapping to mix down with and silently produces
  silence, a dead microphone on a multi-input audio interface. The first channel is taken
  instead, which is predictable and audible; mono and stereo keep the default, which averages.
- Slicing works off the raw buffer list rather than `floatChannelData`, so it is correct for
  interleaved and deinterleaved layouts alike: a buffer's byte size divided by its frame count
  is the bytes per frame in both.
- The converter is stateful and not thread-safe. It is only touched from the capture thread; the
  lock makes that safe rather than merely true today. Its input block is declared `@Sendable`
  but is called synchronously before `convert` returns and never escapes, which is why
  `ConversionInput` is `@unchecked Sendable`.

## The level meter

- A microphone tap runs on a real-time thread that must never wait on an actor, so
  `SampleAccumulator` is a lock-guarded box. One producer, one consumer, and every critical
  section is short and allocation-free — see the block storage below, which is what keeps the
  producer's section short now that it is read while it writes. `momentaryLevel` is `nonisolated` on the capture
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

Working ahead reads the audio while it is still growing: `capturedSoFar()` is called once a
second for the whole of a dictation. When the accumulator was one `[Float]`, handing that array
out made it non-uniquely referenced, so the very next `append` — which runs on the tap's
real-time thread, inside the same lock — had to copy the whole buffer before it could add
anything. At canonical mono 16 kHz that is 15.4 MB at four minutes, once per read, charged to
the one thread that must never pay for anything.

So the samples live in fixed 4096-sample blocks. A block is written until it is full, then
sealed and never touched again, and a fresh one is opened with its capacity reserved up front.
A reader takes references to the sealed blocks and a copy of the open one — at most 16 KB —
and lays them end to end after the lock is released. The capture thread therefore only ever
appends into a block it uniquely owns, and its cost per block is bounded by the block size
rather than by the length of the recording.

`copiedOnAppend` counts the samples the capture thread has had to copy because its storage moved
under it, which is what makes the invariant above checkable instead of asserted: it is zero
across any number of reads, and on the single-array shape it grew by the whole buffer every time.
`Tests/UttrflowAudioTests/SampleAccumulatorTests.swift` holds the measurement.

**What is not measured.** Whether the old copy ever made the tap late. The block budget is 85 ms
and a 15 MB copy is on the order of a millisecond or two, so the step from the copy to a dropped
block and a missing syllable is plausible and has never been observed. The allocation behaviour
is what is measured here; the latency is not.

## Draining the tap at key-up

A tap delivers whole buffers. Installed at 4096 frames, it fills for about 85 ms at 48 kHz before it
calls back, so at the instant the key comes up the hardware is part-way through a buffer that has
not been handed over. Removing the tap there discards it, and nothing downstream can add samples
that were never captured — usually that falls in the gap between the last word and the key release,
and when the user lets go quickly it takes the tail of the final word.

So `MicrophoneSource.stop(draining:)` waits before tearing anything down. `TapDrain` returns as soon
as the next block arrives and at the latest when the window closes, and the window is one tap period
computed from the buffer size and the rate the device is actually running at — not a constant, so it
stays right if the buffer is ever tuned. It is capped at 250 ms, because a device that misreports its
rate would otherwise hold key-up open for as long as it liked.

A cancelled recording does not drain: its audio is discarded, so waiting for more of it would only
delay the key coming up.

Measured at the seam rather than on hardware, with a fake source holding one block back: a drained
stop returns 1,365 more canonical samples than an undrained one, which is 85.3 ms — one tap period
at 4096 frames and 48 kHz, resampled to 16 kHz. What the converter keeps back is a separate and much
smaller loss: `AudioResampler` reuses one stateful `AVAudioConverter` across calls, so its delay line
is emitted on the next call and only the final residual is lost.

## Cue bleed

Playing a cue around capture puts the cue into the recording. Measured on macOS 26.5, built-in
speakers to built-in microphone, eight interleaved trials with and without the cue: the cue
raised the peak level of the first 700 ms of capture by about 6 dB on average, and the loudest
trial reached −11.5 dBFS against a −25.3 dBFS quiet mean, comfortably inside the range the
recogniser treats as speech.

The head of the recording is exposed, because `NSSound.play()` returns immediately (0.1 ms warm)
while the sound goes on for another half second: `DictationController` plays the start cue after
the pipeline is listening, so the whole cue lands in the recording.

The tail is not. `AVAudioCaptureEngine.stop()` plays the stop cue after the microphone source has
stopped and before the buffer is taken, so none of it is recorded. The drain below sits in front of
that, so the cue now lands up to one tap period after the key comes up rather than immediately. The controller and the engine hold the same cue, which is what keeps a stop
from sounding after a start that did not. A cancelled recording plays no stop cue.

What mitigates it, in descending order of effect:

1. Acoustic echo cancellation. `AVAudioInputNode.setVoiceProcessingEnabled(true)` cut the bleed
   from +14.2 dB to +1.5 dB over room noise. Not adopted: it belongs to the capture engine, not
   the cue; it changed the input format from 1 channel to 9 on this machine, which the resampler
   would reduce to channel 0; and it imposes AGC and noise suppression the recogniser has not
   been tuned against.
2. Trimming a lead-in. The cue occupies a known window at the head of the recording, before any
   human has begun speaking; discarding it is a pipeline decision.
3. Being short and quiet, which is all the cue can do by itself. `Tink` is the shortest sound in
   `/System/Library/Sounds` on macOS 26.5 at 0.564 s, chosen for brevity rather than taste, and
   the default volume is 0.4.

Deliberately not a mitigation: waiting for the start cue to finish before opening the
microphone. It buys silence at the cost of half a second before the user may speak.

## Playing a system sound reliably

- Uttrflow carries no audio of its own. A borrowed system sound is one the user recognises as
  their machine rather than this app, it follows whatever they replaced it with in
  `~/Library/Sounds`, and there is no asset to lose.
- `play()` on an `NSSound` that is still playing returns `false` and does nothing, so a second
  dictation inside the previous cue's half-second tail would be silent and, worse, would report
  failure and suppress its own stop cue. Stopping first makes a retrigger restart the sound:
  measured 5/5 successes at 120 ms spacing against 0/5 without. It also covers a starved main run
  loop, where `isPlaying` never clears.
- The first sound of a process costs about 118 ms inside AppKit building its output graph, then
  12 ms per sound. Prewarming pays it at construction rather than on the keystroke that starts a
  dictation.
- A stop cue is owed only after a start cue the user could have heard, and the pair is closed
  whether or not the stop cue plays, so a cue suppressed by the setting is never left owed to the
  next recording.
