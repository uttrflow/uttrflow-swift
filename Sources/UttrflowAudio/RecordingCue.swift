public import UttrflowCore

private import Synchronization

/// A sound the operating system already ships, addressed by name.
///
/// Uttrflow deliberately carries no audio of its own. A borrowed system sound is one the
/// user already recognises as their machine rather than as this app, it follows whatever
/// they have replaced it with in `~/Library/Sounds`, and there is no asset to lose.
public struct SystemSound: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    /// 0.564 s — the shortest sound in `/System/Library/Sounds` on macOS 26.5.
    ///
    /// Brevity is the selection criterion, not taste: see the bleed note on
    /// ``SystemSoundPlayer``. The cue overlaps the head of the recording, so the
    /// shortest sound that still reads as a cue contaminates the least of it.
    public static let tink = SystemSound("Tink")

    /// 0.704 s — the next shortest, and unmistakably not ``tink``.
    public static let morse = SystemSound("Morse")
}

/// Somewhere to send a sound.
///
/// The seam that lets the rules in ``SoundPlayingRecordingCue`` — respect the setting,
/// never stop what never started — be exercised in silence.
public protocol SoundPlayer: Sendable {
    /// Begins playing `sound` and returns without waiting for it to finish.
    ///
    /// - Returns: `false` when nothing will be heard, so a caller can tell "played"
    ///   from "asked, and the system had no such sound".
    @discardableResult
    func play(_ sound: SystemSound) -> Bool

    /// Pays up front for whatever the first ``play(_:)`` would otherwise cost. Silent.
    func prewarm(_ sounds: [SystemSound])
}

extension SoundPlayer {
    /// Most players have no warming to do, and a cue must not care which kind it holds.
    public func prewarm(_ sounds: [SystemSound]) {}
}

/// Plays a pair of sounds around a recording, and knows when not to.
///
/// All the judgement lives here and none of the noise: the two rules worth being sure
/// of — that a user who turned sounds off hears nothing, and that a stop cue never
/// arrives without the start cue it answers — are decided against ``SoundPlayer`` and
/// so are testable in silence.
public final class SoundPlayingRecordingCue: RecordingCueing {
    private let player: any SoundPlayer
    private let startSound: SystemSound
    private let stopSound: SystemSound
    private let soundsEnabled: @Sendable () -> Bool

    /// Whether a start cue was actually heard, and so whether a stop cue is owed.
    ///
    /// Mutable because the pair spans two calls, and locked because those calls arrive
    /// on whichever thread the controller's actor is running on.
    private let awaitingStop = Mutex(false)

    /// - Parameters:
    ///   - player: Where the sound actually goes.
    ///   - startSound: Defaults to the shortest system sound. See ``SystemSound/tink``.
    ///   - stopSound: Played when a recording that was heard to start ends.
    ///   - soundsEnabled: Read on every cue rather than captured once, so turning
    ///     sounds off takes effect on the recording already in progress.
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

        // The first sound of a process costs about 118 ms inside AppKit; paying it now
        // keeps it off the keystroke that starts a dictation. Measured on macOS 26.5.
        player.prewarm([startSound, stopSound])
    }

    public func playStart() {
        guard soundsEnabled() else { return }

        // Armed only by a sound the user could actually have heard. A start cue the
        // system silently declined must not license a stop cue answering nothing.
        let played = player.play(startSound)
        awaitingStop.withLock { $0 = played }
    }

    public func playStop() {
        // Disarmed whether or not it plays: a stop cue suppressed by the setting still
        // closes the pair, rather than leaving one owed to the next recording.
        let owed = awaitingStop.withLock { awaiting -> Bool in
            defer { awaiting = false }
            return awaiting
        }

        guard owed, soundsEnabled() else { return }
        player.play(stopSound)
    }
}
