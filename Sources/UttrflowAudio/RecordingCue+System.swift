import UttrflowCore
private import AppKit
private import Synchronization

/// The part that makes noise.
///
/// Excluded from the coverage gate: a test that verified this would have to play a
/// sound. Everything that decides *whether* to play one is measured, next door.
// MARK: - The part that makes noise
/// Plays system sounds through AppKit.
///
/// ## Cue bleed
///
/// Playing a cue around capture *does* put the cue into the recording, and this is not
/// theoretical. Measured on this machine (macOS 26.5, built-in speakers to built-in
/// microphone, eight interleaved trials with and without the cue): the cue raised the
/// peak level of the first 700 ms of capture by about 6 dB on average, and the loudest
/// trial reached −11.5 dBFS against a −25.3 dBFS quiet mean — comfortably inside the
/// range the recogniser treats as speech.
///
/// The recording is exposed at both ends, because ``NSSound/play()`` returns
/// immediately (0.1 ms warm) while the sound goes on for another half second:
///
/// - ``DictationController`` plays the start cue *after* the pipeline is listening, so
///   the whole cue lands in the recording.
/// - It plays the stop cue *before* `finishRecording()`, so the cue's onset lands in
///   the tail.
///
/// What actually mitigates it, in descending order of effect:
///
/// 1. Acoustic echo cancellation. `AVAudioInputNode.setVoiceProcessingEnabled(true)`
///    cut the bleed from +14.2 dB to +1.5 dB over room noise here. It is not adopted
///    because it belongs to the capture engine, not the cue, and it is not free: it
///    changed the input format from 1 channel to 9 on this machine, which
///    ``AudioResampler`` would reduce to channel 0, and it imposes AGC and noise
///    suppression on audio the recogniser has not been tuned against.
/// 2. Trimming a lead-in. The cue occupies a known window at the head of the recording,
///    before any human has begun speaking; discarding it is a pipeline decision.
/// 3. Being short and quiet, which is all this type can do by itself — hence
///    ``SystemSound/tink`` and a default volume well under full.
///
/// Deliberately *not* a mitigation: waiting for the start cue to finish before opening
/// the microphone. It buys silence at the cost of half a second before the user may
/// speak, which is the one thing a dictation shortcut cannot afford.
public final class SystemSoundPlayer: SoundPlayer {
    /// Sounds are kept rather than looked up per cue, because a cue must be restarted
    /// on the same instance to be reliable — see ``play(_:)``.
    private let sounds = Mutex<[SystemSound: NSSound]>([:])
    private let volume: Float

    /// - Parameter volume: Under half by default. A cue only has to be noticed, and
    ///   every decibel of it is also a decibel in the recording.
    public init(volume: Float = 0.4) {
        self.volume = volume
    }

    @discardableResult
    public func play(_ sound: SystemSound) -> Bool {
        guard let nsSound = resolve(sound) else { return false }

        // `play()` on an instance that is still playing returns false and does nothing,
        // so without this a second dictation inside the previous cue's half-second tail
        // would be silent — and, worse, would report failure and suppress its own stop
        // cue. Stopping first makes a retrigger restart the sound instead: measured
        // 5/5 successes at 120 ms spacing, against 0/5 without.
        //
        // It also covers a main run loop that is starved or blocked, where `isPlaying`
        // never clears and every subsequent cue in the process would otherwise be lost.
        nsSound.stop()
        nsSound.volume = volume
        return nsSound.play()
    }

    public func prewarm(_ sounds: [SystemSound]) {
        // One sound is enough — the cost is AppKit building its output graph once per
        // process, not per sound (118 ms, then 12 ms) — but warming each is cheap and
        // does not assume which one a cue reaches for first.
        for sound in sounds {
            guard let nsSound = resolve(sound) else { continue }
            nsSound.volume = 0
            nsSound.play()
            nsSound.stop()
        }
    }

    /// Looks a sound up once and keeps it. Returns `nil` for a name the system has no
    /// sound for, which is the only way ``play(_:)`` can honestly report failure.
    private func resolve(_ sound: SystemSound) -> NSSound? {
        sounds.withLock { cache in
            if let existing = cache[sound] { return existing }
            guard let loaded = NSSound(named: NSSound.Name(sound.name)) else { return nil }
            cache[sound] = loaded
            return loaded
        }
    }
}
