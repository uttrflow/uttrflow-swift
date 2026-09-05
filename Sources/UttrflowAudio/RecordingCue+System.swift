// Plays recording cues through AppKit's system sounds.
import UttrflowCore
private import AppKit
private import Synchronization

/// The part that makes noise, excluded from coverage; whether to play lives next door and is tested.
// MARK: - The part that makes noise
/// Plays system sounds through AppKit; the cue bleeds into the recording. See Docs/audio-capture.md.
public final class SystemSoundPlayer: SoundPlayer {
    /// Sounds are kept rather than looked up per cue, since a restart is only reliable on the same instance.
    private let sounds = Mutex<[SystemSound: NSSound]>([:])
    private let volume: Float

    /// Plays at under half volume by default, since every decibel of a cue is also in the recording.
    public init(volume: Float = 0.4) {
        self.volume = volume
    }

    @discardableResult
    public func play(_ sound: SystemSound) -> Bool {
        guard let nsSound = resolve(sound) else { return false }

        // Stopped first, so a retrigger inside the previous cue's tail restarts the sound instead of failing.
        nsSound.stop()
        nsSound.volume = volume
        return nsSound.play()
    }

    public func prewarm(_ sounds: [SystemSound]) {
        // Warming each is cheap and does not assume which sound a cue reaches for first.
        for sound in sounds {
            guard let nsSound = resolve(sound) else { continue }
            nsSound.volume = 0
            nsSound.play()
            nsSound.stop()
        }
    }

    /// Looks a sound up once and keeps it; `nil` for a name the system has no sound for.
    private func resolve(_ sound: SystemSound) -> NSSound? {
        sounds.withLock { cache in
            if let existing = cache[sound] { return existing }
            guard let loaded = NSSound(named: NSSound.Name(sound.name)) else { return nil }
            cache[sound] = loaded
            return loaded
        }
    }
}
