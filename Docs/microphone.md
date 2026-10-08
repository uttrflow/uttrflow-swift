# The microphone, and the hardware moving under it

When the audio hardware changes during a recording, `AVAudioEngineMicrophoneSource`
(`Sources/UttrflowAudio/AVAudioEngineMicrophoneSource.swift`) rebuilds the engine on the new
device, `InputDeviceSession` (`Sources/UttrflowAudio/InputDeviceSession.swift`) retries a device
that has gone, and `AVAudioCaptureEngine` (`Sources/UttrflowAudio/AVAudioCaptureEngine.swift`)
decides whether the recording can still be handed over. How samples are captured and converted is
[`audio-capture.md`](audio-capture.md); what happens to a recording with no speech in it is
[`silence.md`](silence.md).

## The failure this handles

`AVAudioEngine` stops itself whenever the audio hardware configuration changes, and posts
`AVAudioEngineConfigurationChangeNotification`. The installed tap stops delivering buffers.
**No error is raised anywhere.** Unobserved, a recording that meets one carries on looking
healthy (the menu bar lit, the waveform drawn, the key held) and captures nothing.

The triggers are ordinary, which is what makes this look random:

- AirPods or any Bluetooth headset connecting **mid-recording**;
- headphones with a microphone going in or coming out;
- a dock or a monitor with audio being attached;
- the input device being changed in System Settings;
- a USB interface changing its sample rate.

Bluetooth is the common one: a headset that connects while somebody is speaking is not an edge
case.

## The rebuild

`AVAudioEngineMicrophoneSource` keeps the caller's sample sink rather than handing it straight to
one engine, observes the notification, and rebuilds: a new engine, a new tap, and a **new
`AudioResampler` for the new input format**. The device that arrives can have a different sample
rate and channel count from the one that left, and the old resampler would convert from a format
nothing is producing.

The accumulated audio survives, because it is held by `AVAudioCaptureEngine` rather than by the
source.

## When the device has gone

If the device has gone and nothing replaced it, `InputDeviceSession` retries the reopen across the
few seconds a device takes to re-enumerate. It owns that schedule because the notification that
announces a configuration change is posted by an engine: once a reopen has failed there is no
engine, so nothing would announce the device coming back.

| `ReopenSchedule.standard` delays | Total (`ReopenSchedule.total`) |
|---|---|
| 100, 200, 400, 800, 1,500 ms | 3 s |

That covers a Bluetooth re-enumeration and a sample-rate change. `DeviceHealth` reports `.live`,
`.reopening` or `.gone`. The reopen goes through the same `open()` as the first open, so it checks
microphone permission the same way ([`audio-capture.md`](audio-capture.md)).

## Whether the recording can be handed over

| What happened | Result |
|---|---|
| Device changed before the first sample, reopened | the recording continues |
| Device changed after any sample, reopened | handed over whole, with a discontinuity at the change |
| Device never came back | refused: "The microphone did not come back after the device changed." |

A gap is kept, not refused. The audio from before the change and the audio from after it sit next
to each other with the missing seconds gone, so the change is recorded as a discontinuity: a sample
offset in `AudioSamples.discontinuities`. `SpeechWindowing` always ends a piece there (at a pause
just before it when there is one), never joins a short tail back across it, and the pieces either
side are recognised apart and joined at the seam as pieces cut at a pause are. No word is invented
across the hole and none is dropped.

The hole is recorded the moment the device goes, at the sample count the callback sees, not when
the reopen resolves. That ordering is load-bearing: a stop landing while the retry is still in
flight cancels it, so a report that waited for the outcome would never be made.

A device that never comes back is refused rather than handed over: audio
captured *before* the change survives, so a recording that ends this way can still contain
speech, and half a sentence reads as a whole one. The refusal is `.engineFailed`, and the WAV
is finished before the refusal, so `DictationPipeline` claims that recording and the notice offers
`.retryFromRecording` (the Dictation page's Retry, which delivers to the clipboard) and never
`.retry`, which would open the microphone for a new dictation in place of the kept one. See
[`recordings.md`](recordings.md).

## What this cannot fix

macOS decides what the default input is. If AirPods connect while somebody is dictating, the rest
of the sentence is recorded through the AirPods, whose microphone is worse. That is the right
behaviour, since it is the device the system has chosen, but the transcript can be visibly worse
either side of the join.
