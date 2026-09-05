// Decides when a recording cue is played, in a form testable in silence.
public import UttrflowCore

private import Synchronization

/// A sound the operating system ships, addressed by name; Uttrflow carries no audio of its own.
public struct SystemSound: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    /// The shortest system sound (0.564 s), chosen so the cue contaminates the least of the recording.
    public static let tink = SystemSound("Tink")

    /// 0.704 s — the next shortest, and unmistakably not ``tink``.
    public static let morse = SystemSound("Morse")
}

/// Somewhere to send a sound, so the cue rules can be exercised in silence.
public protocol SoundPlayer: Sendable {
    /// Begins playing `sound` without waiting; `false` when nothing will be heard.
    @discardableResult
    func play(_ sound: SystemSound) -> Bool

    /// Pays up front for whatever the first ``play(_:)`` would otherwise cost. Silent.
    func prewarm(_ sounds: [SystemSound])
}

extension SoundPlayer {
    /// Most players have no warming to do, and a cue must not care which kind it holds.
    public func prewarm(_ sounds: [SystemSound]) {}
}

/// Plays a pair of sounds around a recording, respecting the setting and never answering an unplayed start.
public final class SoundPlayingRecordingCue: RecordingCueing {
    private let player: any SoundPlayer
    private let startSound: SystemSound
    private let stopSound: SystemSound
    private let soundsEnabled: @Sendable () -> Bool

    /// Whether a start cue was heard and a stop cue is owed; locked because the calls arrive on any thread.
    private let awaitingStop = Mutex(false)

    /// Cues through `player`; `soundsEnabled` is read on every cue, so a change applies mid-recording.
    public init(
        player: any SoundPlayer,
        startSound: SystemSound = .tink,
        stopSound: SystemSound = .morse,
        soundsEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.player = player
        self.startSound = startSound
        self.stopSound = stopSound
        self.soundsEnabled = soundsEnabled

        // The first sound of a process costs about 118 ms inside AppKit; paid now, not on the keystroke.
        player.prewarm([startSound, stopSound])
    }

    public func playStart() {
        guard soundsEnabled() else { return }

        // Armed only by a sound the user could have heard, so a declined start never licenses a stop.
        let played = player.play(startSound)
        awaitingStop.withLock { $0 = played }
    }

    public func playStop() {
        // Disarmed whether or not it plays, so a suppressed stop cue still closes the pair.
        let owed = awaitingStop.withLock { awaiting -> Bool in
            defer { awaiting = false }
            return awaiting
        }

        guard owed, soundsEnabled() else { return }
        player.play(stopSound)
    }
}
