# Recordings kept for retry

Every dictation's audio is written to disk **while the key is held**, beside the buffer the
recogniser reads, and deleted the moment the words land. If the words are lost — the
recogniser throws or never answers, the app crashes mid-dictation — the file stays, and
the Dictation page lists it with a Retry.

This reverses the earlier promise that recordings were never saved. The privacy stance is
unchanged in substance: nothing leaves the Mac. The copy changed instead, in one place
(`SettingsPresenter.recordingsPromise`) that Settings and onboarding both repeat, and
`SettingsPrivacyCopyTests` now checks that every sentence about audio names this Mac and
says when the audio goes.

## The write is the commit

`AVAudioCaptureEngine` opens a `RecordingWriter` before installing the tap, and the tap
block appends every block to both the `SampleAccumulator` and the writer. The writer
queues the write on its own utility queue, so the capture thread never waits on a disk.
Releasing the key still hands WhisperKit the in-memory buffer at once; the file is a
side effect, never a source, for a live dictation.

The file is a plain 16-bit mono WAV at the canonical 16 kHz, built from the same header
and PCM bytes `WAVEncoder` produces, so a finished file is byte-for-byte what the encoder
would have written. It opens with a header claiming zero frames; `finish()` rewrites the
count. A file whose header still says zero is one the writer never finished — a crash —
and `RecordingWriter.repair` patches the count from the bytes that reached disk, which
is how a recording from before a crash becomes readable at the next launch.

## Life of a recording

| State | Where | What happens |
|---|---|---|
| Recording | `RecordingStore.open` | Growing. Not listed: it is not a recording yet. |
| Current | `RecordingStore.last` | The key was released. The pipeline reads its id once. |
| Waiting | any `.wav` in the folder | Words were lost. Listed on the Dictation page. |
| Gone | — | Words landed, silence, cancelled, retried, or a day old. |

The folder is `Application Support/Uttrflow/recordings/`, one `<uuid>.wav` per take. The
file's creation date is set to the recording's start time, so a later launch knows how
old it is without a sidecar.

## When the pipeline keeps it

`DictationPipeline.fail` decides, and the rule is one sentence: **the audio is kept
exactly when the words were lost.** A failure with a transcript (insertion failed, the
words are on the clipboard) discards it. An informational failure (silence) discards it.
Everything else keeps it and, when the failure's own recovery was `retry` or nothing,
offers `retryFromRecording` instead — the floating button's Retry then opens the
Dictation page rather than starting a new dictation. A failure with a different fix, like
a missing speech model, keeps that fix and the recording both.

`cancel()` after the key is released discards the recording. `retry(_:)` reads the file
through `AudioFileReader`, so the samples arrive in the same shape the microphone
delivers, and runs the same stages with two differences: no screen context is read
(Uttrflow's own window is in front), and the words are delivered to the clipboard rather
than typed, because the field they were meant for is gone. The outcome carries
`fromRecording`, so the floating button says "Copied" without blaming Accessibility.

## Retention

A waiting recording is deleted when the list is next read if it is older than
`RecordingStore.defaultRetention`, 24 hours. There is no setting for it: the window
exists to bound what a crash can leave behind, not to be a preference.

## What is not here

- No playback. The row shows a waveform glyph and the duration.
- No re-transcribing a dictation that came out wrong: the audio behind a finished
  transcript is deleted, so History has nothing to replay.
- No setting to turn it off. The write is what makes retry possible at all.
