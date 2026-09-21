// Tests that the recording sound setting reaches the cue the pipeline already holds.

import Synchronization
import Testing
import UttrflowAudio
import UttrflowSettings

@testable import Uttrflow

/// A ``SoundPlayer`` that makes no sound and remembers what it was asked to play.
private final class HeardPlayer: SoundPlayer {
    private let heard = Mutex<[SystemSound]>([])

    func play(_ sound: SystemSound) -> Bool {
        heard.withLock { $0.append(sound) }
        return true
    }

    var played: [SystemSound] { heard.withLock { $0 } }
}

/// Settings with only the recording sound decided.
private func settings(sound: Bool) -> Settings {
    var settings = Settings()
    settings.playsSoundWhenRecordingStarts = sound
    return settings
}

@Suite("The recording sound setting and the cue already in use")
struct RecordingSoundsTests {
    @Test("turning the sound off silences the cue the pipeline already holds")
    func enabledToDisabled() {
        let player = HeardPlayer()
        let sounds = RecordingSounds(player: player, enabled: true)
        sounds.cue.playStart()
        sounds.cue.playStop()

        sounds.apply(settings(sound: false))
        sounds.cue.playStart()
        sounds.cue.playStop()

        #expect(player.played == [.tink, .morse])
        #expect(!sounds.isEnabled)
    }

    @Test("turning the sound on after a silent launch makes the same cue audible")
    func disabledToEnabled() {
        let player = HeardPlayer()
        let sounds = RecordingSounds(player: player, enabled: false)
        sounds.cue.playStart()
        sounds.cue.playStop()

        sounds.apply(settings(sound: true))
        sounds.cue.playStart()
        sounds.cue.playStop()

        #expect(player.played == [.tink, .morse])
        #expect(sounds.isEnabled)
    }

    @Test("turning the sound on mid-recording owes no stop for a start that was never heard")
    func onMidRecording() {
        let player = HeardPlayer()
        let sounds = RecordingSounds(player: player, enabled: false)
        sounds.cue.playStart()

        sounds.apply(settings(sound: true))
        sounds.cue.playStop()

        #expect(player.played.isEmpty)
    }

    @Test("turning the sound off mid-recording silences the stop")
    func offMidRecording() {
        let player = HeardPlayer()
        let sounds = RecordingSounds(player: player, enabled: true)
        sounds.cue.playStart()

        sounds.apply(settings(sound: false))
        sounds.cue.playStop()

        #expect(player.played == [.tink])
    }
}
