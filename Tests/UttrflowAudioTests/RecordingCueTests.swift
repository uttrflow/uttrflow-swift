import Synchronization
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

/// A ``SoundPlayer`` that makes no sound and remembers everything it was asked for.
private final class SpyPlayer: SoundPlayer {
    private struct State {
        var requested: [SystemSound] = []
        var prewarmed: [SystemSound] = []
        var refused: Set<SystemSound> = []
    }

    private let state = Mutex(State())

    /// - Parameter refusing: Sounds the "system" claims not to have.
    init(refusing: Set<SystemSound> = []) {
        state.withLock { $0.refused = refusing }
    }

    func play(_ sound: SystemSound) -> Bool {
        state.withLock { state in
            state.requested.append(sound)
            return !state.refused.contains(sound)
        }
    }

    func prewarm(_ sounds: [SystemSound]) {
        state.withLock { $0.prewarmed.append(contentsOf: sounds) }
    }

    var requested: [SystemSound] { state.withLock(\.requested) }
    var prewarmed: [SystemSound] { state.withLock(\.prewarmed) }
}

/// A player that leaves ``SoundPlayer/prewarm(_:)`` to the protocol's default.
private final class MinimalPlayer: SoundPlayer {
    private let count = Mutex(0)
    func play(_ sound: SystemSound) -> Bool {
        count.withLock { $0 += 1 }
        return true
    }
    var playCount: Int { count.withLock { $0 } }
}

/// A "sounds off" setting the user can flip mid-recording.
private final class Setting: Sendable {
    private let enabled: Mutex<Bool>

    init(_ enabled: Bool) {
        self.enabled = Mutex(enabled)
    }

    func turn(on: Bool) { enabled.withLock { $0 = on } }
    var reader: @Sendable () -> Bool { { self.enabled.withLock { $0 } } }
}

@Suite("SystemSound")
struct SystemSoundTests {
    @Test("carries the name it was given")
    func carriesName() {
        #expect(SystemSound("Purr").name == "Purr")
    }

    @Test("two sounds of the same name are the same sound")
    func equality() {
        #expect(SystemSound("Purr") == SystemSound("Purr"))
        #expect(SystemSound("Purr") != SystemSound("Frog"))
        #expect(Set([SystemSound("Purr"), SystemSound("Purr")]).count == 1)
    }

    @Test("defaults to the two shortest system sounds, to minimise cue bleed")
    func defaultsAreShortest() {
        #expect(SystemSound.tink.name == "Tink")
        #expect(SystemSound.morse.name == "Morse")
    }
}

@Suite("SoundPlayingRecordingCue")
struct SoundPlayingRecordingCueTests {
    @Test("plays the start sound when recording begins")
    func playsStart() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()

        #expect(player.requested == [.tink])
    }

    @Test("plays the stop sound after a start")
    func playsStopAfterStart() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStop()

        #expect(player.requested == [.tink, .morse])
    }

    @Test("says nothing when asked to stop what never started")
    func stopWithoutStartIsSilent() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStop()

        #expect(player.requested.isEmpty, "a stop cue answering nothing is a glitch, not a cue")
    }

    @Test("answers a start exactly once, however often stop is called")
    func stopIsIdempotent() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStop()
        cue.playStop()
        cue.playStop()

        #expect(player.requested == [.tink, .morse])
    }

    @Test("plays both cues again on the next recording")
    func repeatedRecordings() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStop()
        cue.playStart()
        cue.playStop()

        #expect(player.requested == [.tink, .morse, .tink, .morse])
    }

    @Test("stays armed when a start arrives twice")
    func repeatedStartStaysArmed() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStart()
        cue.playStop()

        #expect(player.requested == [.tink, .tink, .morse])
    }

    @Test("uses the sounds it was given")
    func customSounds() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(
            player: player, startSound: SystemSound("Frog"), stopSound: SystemSound("Purr")
        )

        cue.playStart()
        cue.playStop()

        #expect(player.requested == [SystemSound("Frog"), SystemSound("Purr")])
    }

    @Test("warms both of its sounds before either is needed")
    func prewarmsItsSounds() {
        let player = SpyPlayer()
        _ = SoundPlayingRecordingCue(
            player: player, startSound: SystemSound("Frog"), stopSound: SystemSound("Purr")
        )

        #expect(player.prewarmed == [SystemSound("Frog"), SystemSound("Purr")])
        #expect(player.requested.isEmpty, "warming must not be audible")
    }

    // MARK: The sounds-off setting

    @Test("says nothing at all when sounds are off")
    func soundsOffIsSilent() {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player, soundsEnabled: { false })

        cue.playStart()
        cue.playStop()

        #expect(player.requested.isEmpty)
    }

    @Test("does not answer a start the user never heard")
    func turnedOnMidRecording() {
        let player = SpyPlayer()
        let setting = Setting(false)
        let cue = SoundPlayingRecordingCue(player: player, soundsEnabled: setting.reader)

        cue.playStart()
        setting.turn(on: true)
        cue.playStop()

        #expect(player.requested.isEmpty, "the stop cue would be the first sound of the recording")
    }

    @Test("honours sounds being turned off part-way through a recording")
    func turnedOffMidRecording() {
        let player = SpyPlayer()
        let setting = Setting(true)
        let cue = SoundPlayingRecordingCue(player: player, soundsEnabled: setting.reader)

        cue.playStart()
        setting.turn(on: false)
        cue.playStop()

        #expect(player.requested == [.tink])
    }

    @Test("does not owe a stop cue to the next recording")
    func suppressedStopDoesNotCarryOver() {
        let player = SpyPlayer()
        let setting = Setting(true)
        let cue = SoundPlayingRecordingCue(player: player, soundsEnabled: setting.reader)

        cue.playStart()
        setting.turn(on: false)
        cue.playStop()
        setting.turn(on: true)
        cue.playStop()

        #expect(player.requested == [.tink], "the pair closed when it was suppressed")
    }

    // MARK: A system that will not co-operate

    @Test("does not answer a start sound the system refused to play")
    func refusedStartDoesNotArm() {
        let player = SpyPlayer(refusing: [.tink])
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStop()

        #expect(player.requested == [.tink], "only the start was attempted")
    }

    @Test("recovers on the next recording after a refused start")
    func refusedStartRecovers() {
        let player = SpyPlayer(refusing: [SystemSound("Missing")])
        let cue = SoundPlayingRecordingCue(
            player: player, startSound: SystemSound("Missing"), stopSound: .morse
        )

        cue.playStart()
        cue.playStop()
        #expect(player.requested == [SystemSound("Missing")])
    }

    @Test("a refused stop sound still closes the pair")
    func refusedStopStillDisarms() {
        let player = SpyPlayer(refusing: [.morse])
        let cue = SoundPlayingRecordingCue(player: player)

        cue.playStart()
        cue.playStop()
        cue.playStop()

        #expect(player.requested == [.tink, .morse])
    }

    // MARK: Concurrency

    @Test("never plays more stop cues than start cues under concurrent use")
    func concurrentUse() async {
        let player = SpyPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { cue.playStart() }
                group.addTask { cue.playStop() }
            }
        }

        let starts = player.requested.count { $0 == .tink }
        let stops = player.requested.count { $0 == .morse }
        #expect(starts == 200)
        #expect(stops <= starts, "every stop cue must answer a start cue")
    }
}

@Suite("RecordingCue boundary")
struct RecordingCueBoundaryTests {
    /// Stands in for ``DictationController``, which is written against Core's protocol.
    private func drive(_ cue: any RecordingCueing) {
        cue.playStart()
        cue.playStop()
    }

    @Test("a cue from this module satisfies the controller's boundary")
    func satisfiesCoreProtocol() {
        let player = SpyPlayer()
        drive(SoundPlayingRecordingCue(player: player))

        #expect(player.requested == [.tink, .morse])
    }

    @Test("a player that ignores warming still works")
    func defaultPrewarmIsHarmless() {
        let player = MinimalPlayer()
        let cue = SoundPlayingRecordingCue(player: player)

        #expect(player.playCount == 0, "the default warming must be silent")

        cue.playStart()
        cue.playStop()
        #expect(player.playCount == 2)
    }
}
