# The microphone, and the hardware moving under it

## The failure

`AVAudioEngine` stops itself whenever the audio hardware configuration changes, and posts
`AVAudioEngineConfigurationChangeNotification`. The installed tap stops delivering
buffers. **No error is raised anywhere.**

Nothing in the app observed that notification, so a recording that met one carried on
looking healthy — the menu bar lit, the waveform drawn, the key held — and captured
nothing at all. When the user let go they got a hallucinated transcript, or now
"Didn't catch that".

The triggers are ordinary, which is what makes this look random:

- AirPods or any Bluetooth headset connecting **mid-recording**;
- headphones with a microphone going in or coming out;
- a dock or a monitor with audio being attached;
- the input device being changed in System Settings;
- a USB interface changing its sample rate.

Bluetooth is the common one. A headset that connects while somebody is speaking is not
an edge case — it is a Tuesday.

## What the app does now

`AVAudioEngineMicrophoneSource` keeps the caller's sample sink rather than handing it
straight to one engine, observes the notification, and rebuilds: a new engine, a new tap,
and a **new `AudioResampler` for the new input format**. That last part matters — the
device that arrives can have a different sample rate and channel count from the one that
left, and reusing the old resampler would convert from a format nothing is producing.

The accumulated audio survives, because it is held by `AVAudioCaptureEngine` rather than
by the source. A dictation interrupted by a device change loses the fraction of a second
the changeover takes, and keeps the rest.

If the device has gone and nothing replaced it, the reopen is retried across the few
seconds a device takes to re-enumerate — a Bluetooth headset or a sample-rate change is
usually back well inside that. `InputDeviceSession` owns that schedule, because the
notification that announces a configuration change is posted by an engine: once a reopen
has failed there is no engine, so nothing would announce the device coming back, and a
single `try?` left the microphone dead for the rest of the recording.

When the device does come back, the session says so too, and the recording is refused rather than
handed over. It sounds wrong to refuse a recording the microphone recovered from, but `AudioSamples`
is a run of samples and a sample rate: it cannot say that time passed. The audio from before the
change and the audio from after it sit next to each other with the missing seconds simply gone, so
the words either side are joined into one sentence that nobody spoke. Refusing it offers the user a
retry instead, which is the only honest option while a gap cannot be represented.

When the device never comes back, the session says so and the recording ends as a failure
with a Retry, rather than handing back what it managed to capture. That distinction only
holds before the first word: audio captured *before* the change survives, so a recording
that ends this way can still contain speech, and half a sentence reads as a whole one. It
is `.engineFailed`, so `DictationPipeline` keeps the audio and offers the retry. See
`Docs/silence.md` for what the voice-activity check does with a recording that holds no
speech at all.

## What this cannot fix

macOS decides what the default input is. If a user starts dictating and their AirPods
connect, the rest of the sentence is recorded through the AirPods, whose microphone is
worse. That is the right behaviour — it is the device the system has chosen — but the
transcript can be visibly worse either side of the join.
