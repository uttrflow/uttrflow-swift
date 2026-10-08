# Recordings kept for retry

Every dictation's audio is written to disk **while the key is held**, beside the buffer the
recogniser reads, and deleted the moment the words land. If the words are lost — the recogniser
throws or never answers, a piece of speech decodes to no words, the app quits mid-dictation — the
file stays for a day, and the History
page lists it with a Retry. Nothing leaves the Mac. The code is in `Sources/UttrflowAudio/`:
`RecordingStore` owns the folder, `RecordingWriter` writes one recording, and
`EncryptedRecordingFile` is the on-disk format. `DictationPipeline` decides what is kept.

The promise the user reads is `SettingsPresenter.recordingsPromise`, one wording that Settings and
onboarding both repeat: "Audio is deleted the moment it becomes text, and kept on this Mac for a
day only if some of it couldn't be, so you can retry." `SettingsPrivacyCopyTests` checks that every
sentence about audio names this Mac and says when the audio goes.

## The write is the commit

`AVAudioCaptureEngine` opens a `RecordingWriter` before installing the tap, and the tap appends
every block to both the `SampleAccumulator` and the writer. The writer hands each block to an
actor through an `AsyncStream`, so the capture thread never waits on a disk and nothing on the
cooperative pool blocks on one. Releasing the key hands the recogniser the in-memory buffer at
once: `RecordingStore.finish(_:)` answers for the recording from what was handed over and returns,
and the last bytes land behind it. Only a reader of the file waits for them, through
`RecordingStore.settle(_:)`, which `audio(of:)`, `waiting(now:)` and `discard(_:)` all do. For a
live dictation the file is a side effect, never a source.

Starting a recording touches no disk either. `RecordingStore.begin(at:)` returns a writer at once,
and the writer's own task makes the folder, creates the file, marks it out of backups, writes the
header and stamps the creation date before it writes the first block, so the microphone never waits
on a file and every block captured meanwhile still lands. A file that cannot be made keeps nothing
and fails nothing: the dictation goes on from the buffer, and `current()` answers with nothing once
the writer has settled.

## The file format

The file keeps a `.wav` name but is not a WAV. It begins with the 8-byte marker `UTTRWAV1`,
followed by independently sealed chunks:

| Part | Content |
|---|---|
| Chunk header | frame count and envelope length, little-endian `UInt32`s, in the clear |
| Envelope | AES-GCM over up to `EncryptedRecordingFile.maximumChunkFrames` (16,000) frames of 16-bit mono PCM at 16 kHz — one second; only the last chunk can be shorter |

Each chunk is sealed by `EncryptedStore` with a fresh nonce under the shared device-only Keychain
key, and the recording's filename, the chunk's index and its frame count are bound as additional
data, so a chunk cannot be moved to another file or position. The clear frame counts reveal the
duration; the audio cannot be opened by an audio player. The writer seals each chunk as capture
proceeds, with no plaintext temporary file.

After a crash, the reader opens every complete chunk and ignores a torn final one, so at most the
last partial second is lost. Retry and playback both read through `RecordingStore.audio(of:)`;
playback builds a WAV only in memory. A plaintext WAV left by an older build is repaired if needed
(`RecordingWriter.repair`) and re-encoded in place when it is read, keeping its creation date. If
the key is unavailable or that migration fails, the original file stays and is not offered until
it can be read.

## Life of a recording

| State | Held as | What happens |
|---|---|---|
| Recording | `RecordingStore`'s open writer | Growing. Not listed: it is not a recording yet |
| Current | the store's last finished recording, read through `current()` | The key was released; the pipeline claims its id once |
| Waiting | any `<uuid>.wav` in the folder | Some words were lost, the dictation was cancelled after the key was released, or it was cancelled while recording and is inside its restore window. Listed on the History page |
| Gone | — | Every word landed, nothing was heard, cancelled while recording under the restore threshold, restore window closed, retried, or older than a day |

The folder is `recordings/` in the app's Application Support folder (`Uttrflow/` for the shipped
build; another build's identifier gives it its own folder, `LocalStore.directory`). Each take is
`<uuid>.wav`, with a `<uuid>.context` property list beside it holding the destination application
and field kind. The file's creation date is the recording's start time, so a later launch knows its
age without another sidecar. The folder and each file are marked `isExcludedFromBackup`: a
recording exists only as a one-day retry buffer, so backup tools that honour the flag skip it.

## When the pipeline keeps it

`DictationPipeline.settleRecording` decides, and the rule is one sentence: **the audio is kept
exactly when words were lost.** A dictation whose words landed but left out a piece of speech that
decoded to no words twice (`DictationOutcome.missedPieces` above zero) keeps it, so History offers
Retry for the missing words; one with no missed piece discards it. A failure that carries a transcript (insertion failed, and the words are
in History) discards it. An informational failure, such as nothing heard, discards it. A
dictation into a secure field discards it, since its words are a secret. Everything else keeps it
and, when the failure's own recovery was `retry` or none, offers `retryFromRecording` instead, with
the recording's id in `DictationFailure.keptRecording`. The floating button's Retry runs History's
own retry on that recording, so the words reach the clipboard in one press instead of two and the
person stays in the app they were writing in (`noticeRetryTakesOnePress` in
`DictationPipelineRecordingTests`). A failure
with a different fix, such as a missing speech model, keeps that fix and the recording both.

`cancel()` after the key is released, while the words are transcribed, tidied or inserted, keeps
the recording for a retry, so a cancel never loses speech; a secure field's recording is still
discarded. `retry(_:)` reads the audio through
`RecordingStore.audio(of:)`, so the samples arrive in the shape the microphone delivers, and runs
the same stages with two differences: no screen context is read (Uttrflow's own window is in
front), and the words go to the clipboard rather than being typed, because the field they were
meant for is gone. The sidecar supplies the original application's name, bundle identifier and
field kind, so the retry is formatted for that destination even if the frontmost application or
the destination overrides have changed since; an older sidecar holding only the application
resolves the field kind from it. The outcome carries `fromRecording`, so the floating button says
"Copied" without blaming Accessibility. A recording that cannot be read is deleted and reported as
"That recording couldn't be read, so it can't be retried."

## Cancelled while recording

A cancel while the microphone is open, by Escape, the Cancel command or a press that became another
shortcut, is decided by how long the microphone was open:

| Length | What the person gets |
|---|---|
| under `DictationPipeline.restoreThreshold`, 5 s | Nothing: the file is deleted and the dock rests, as for a slip |
| at or over it | The dock line "Discarded", the soft `CueSound.discarded` (under the same sound setting as the start and stop cues), one VoiceOver announcement, and a Restore button |

Restore keeps the file: `AudioCaptureEngine.cancelKeepingRecording()` finishes the writer instead of
deleting it, and Restore is History's Retry run on that recording, so the words reach the clipboard
from the same samples. The pipeline deletes the file once `DictationPipeline.restoreWindow`, 60 s,
passes without a Restore; a quit inside the window leaves it to the one-day rule below. A secure
field's recording is deleted at once and offers no Restore. `CancelPresentationTests` covers each row.

Keeping costs nothing measurable at any length, since the file is written while the key is held
either way, so the threshold is not a cost limit. It sits above a take short enough to say again
and well under the recordings that are costly to lose.

## Retention

A waiting recording is deleted once it is older than `RecordingStore.defaultRetention`, 24 hours.
There is no setting for it: the window bounds what a crash can leave behind, and is not a
preference.

Age alone does not bound the folder: a run of failed or retried dictations can each leave a
recording inside the window. So the list also keeps only the newest recordings whose stored
sizes fit `RecordingStore.defaultByteLimit` together, and deletes the older ones as it reads.
The newest recording is always kept, since it is the retry a failed dictation just offered.
A 240-second recording is about 7.7 MB as 16-bit WAV, so the limit holds about 33 of the longest.

`AppDelegate.sweepExpired` does the deleting at launch, after every dictation that finishes or
fails, when a retention setting changes, and hourly while the app is open, whether or not a window
is open. The same sweep drops transcripts past the History retention setting and clipboard clips
past their retention windows, including their picture files. Opening the main window reads each
list too and deletes as it reads. A file in the recordings folder that is not a recording is deleted
once it is outside the same window.

The window is `RetentionWindow`, the rule the history and the clipboard are held to as well, so a
recording dated ahead of the clock counts as due rather than as not yet made, and a clock that
jumped a year stops listing recordings without deleting the audio a retry still wants.
[retention-clock.md](retention-clock.md) is the reasoning.

## Hearing it

A waiting recording's row on the History page has a play button beside its duration.
`RecordingPlayback` (`Sources/Uttrflow/Main/RecordingPlayback.swift`) reads the file through
`RecordingStore.audio(of:)`, encodes it back to a WAV in memory and plays it, one recording at a
time. A retry or a delete stops the playback first.

## A retry hears what the live dictation heard

A retry reads the 16-bit file back and cuts the whole recording in one pass, where the live path
cut float samples a poll at a time. `uttrflow-eval retry-parity` decodes the same audio both ways,
and also as one piece, at float and at 16-bit, so the cuts and the rounding are measured apart.
Each passage is the eight invented `say` sentences in one voice, joined by silences of 1.2, 0.35,
0.9 and 0.25 s, played at 0 dB and at -30 dB, where 16-bit rounding costs the most precision.
Measured on an Apple M5 Pro with the shipping model:

| Passage | Seconds | Live | Retry, float | Retry, 16-bit | Whole, float | Whole, 16-bit |
|---|---|---|---|---|---|---|
| Samantha, 0 dB and -30 dB | 21.7 | 0 / 4 | 0 / 4 | 0 / 4 | 0 / 1 | 0 / 1 |
| Daniel, 0 dB and -30 dB | 22.8 | 0 / 4 | 0 / 4 | 0 / 4 | 0 / 1 | 0 / 1 |
| Karen, 0 dB and -30 dB | 21.9 | 0 / 4 | 0 / 4 | 0 / 4 | 0 / 1 | 0 / 1 |
| Rishi, 0 dB and -30 dB | 23.8 | 0 / 4 | 0 / 4 | 0 / 4 | 0 / 1 | 0 / 1 |

Each cell is word edits against the reference, then pieces decoded. **Storing at 16 bits changed
no word in any case, and the retry was never worse than the live path.** The passages are clean
synthetic speech with digital silence; recorded voices with room noise and the vocabulary a live
dictation reads from the screen are not covered here.
++ b/Sources/uttrflow-eval/UttrflowEvalCommand.swift
            RetryParityProbe.self, SynthesiseCorpus.self, NonSpeechProbe.self,

## What it does not do

- It does not re-transcribe a dictation that came out wrong: the audio behind a finished
  transcript with no missed piece is deleted, so there is nothing to replay.
- It cannot be turned off. The write is what makes retry possible at all.
