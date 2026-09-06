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
  `SampleAccumulator` is a lock-guarded box. The lock is uncontended in practice: one producer,
  one consumer, never at the same moment. `momentaryLevel` is `nonisolated` on the capture
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

## Cue bleed

Playing a cue around capture puts the cue into the recording. Measured on macOS 26.5, built-in
speakers to built-in microphone, eight interleaved trials with and without the cue: the cue
raised the peak level of the first 700 ms of capture by about 6 dB on average, and the loudest
trial reached −11.5 dBFS against a −25.3 dBFS quiet mean, comfortably inside the range the
recogniser treats as speech.

The recording is exposed at both ends, because `NSSound.play()` returns immediately (0.1 ms
warm) while the sound goes on for another half second: `DictationController` plays the start cue
after the pipeline is listening, so the whole cue lands in the recording, and the stop cue before
`finishRecording()`, so its onset lands in the tail.

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
