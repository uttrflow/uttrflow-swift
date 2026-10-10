# Capture quality: what each recording sounded like

A bad transcript has two possible causes: the recogniser erred, or the microphone gave it
something it could not use. `CaptureQuality` in `UttrflowCore` describes the second, so the two
can be told apart. It makes no decision itself; it is a column for later tools to report.

## What is measured

`CaptureQuality.measure(samples:sampleRate:)` runs once per dictation, over the whole recording
the pipeline is about to transcribe (`DictationPipeline.process`), and hands the result to the
pipeline's `MetricsRecording` through `recordCaptureQuality`.

| Field | Meaning |
|---|---|
| `peakDecibels` | the loudest sample, in dBFS |
| `speechLevelDecibels` | the `VoiceActivity.ceilingPercentile` frame, as RMS in dBFS |
| `noiseFloorDecibels` | the `VoiceActivity.floorPercentile` frame, as RMS in dBFS |
| `signalToNoiseDecibels` | speech level minus noise floor; `nil` when the floor is digital silence |
| `clippedFraction` | share of samples at or above `CaptureQuality.clippingMagnitude` |
| `offset` | mean sample, the DC offset as a fraction of full scale |
| `sampleRate` | samples per second of the audio measured |
| `gaps` | holes the hardware clock showed, their total milliseconds, and buffers lost into them |
| `chosenInputMissing` | the microphone chosen in Settings was absent at an open in this recording, so the system default recorded; never the device's name or UID |

Frame loudness and percentiles are `VoiceActivity.frameLoudness` and `VoiceActivity.percentile`,
over the same `VoiceActivity.frameDuration` frames, so the figures describe the audio exactly as
the silence judgement in [silence.md](silence.md) hears it. There is one loudness measure, not two.

Levels are RMS-based dBFS: a full-scale sine reads 0 dBFS peak and about −3 dBFS level. Digital
silence reads negative infinity rather than a stand-in number, and too little audio to compare
two frames measures nothing at all.

## What is kept

Aggregates only: no samples, no text. `DiagnosticsRecorder` keeps them in memory, bounded like
its stage timings, and nothing writes them to disk. Recorders that do not describe audio,
including the usage telemetry, take the protocol's empty default and never see them.

The figures describe the canonical audio the recogniser receives, after resampling to the
canonical rate and taking the first channel. The input device's own rate and channel count are
not carried through capture yet.

## Accuracy and cost

`Tests/UttrflowCoreTests/CaptureQualityTests.swift` recovers each figure from synthetic signals
built to a known answer: a sine at a known level, a hard-clipped sine, a sine on an offset, and a
tone over seeded white noise. Each is within 0.5 dB, or 0.5 percentage points for the fractions.

Cost, one minute of canonical audio in a release build: `VoiceActivity.frameLoudness` alone is
about 1.2 ms and the whole measure is about 2 ms at best. That run was on a heavily loaded
machine, so the figure is an upper bound and is re-measured on an idle one before it is relied on.
