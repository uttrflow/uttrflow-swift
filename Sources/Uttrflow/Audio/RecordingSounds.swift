// The recording cue the pipeline keeps, and the switch the Settings toggle turns.

import Synchronization
import UttrflowAudio
import UttrflowSettings

/// Owns the one cue the pipeline holds and whether it sounds, so a change in Settings reaches it without a rebuild.
final class RecordingSounds: Sendable {
    /// Whether the cue sounds; a class of its own so the cue can read it before this object exists.
    private final class Switch: Sendable {
        let isOn: Mutex<Bool>
        init(_ isOn: Bool) { self.isOn = Mutex(isOn) }
    }

    private let state: Switch
    /// The cue handed to the microphone and the controller for the life of the pipeline.
    let cue: SoundPlayingRecordingCue

    init(player: any SoundPlayer, enabled: Bool) {
        let state = Switch(enabled)
        self.state = state
        cue = SoundPlayingRecordingCue(player: player) { state.isOn.withLock { $0 } }
    }

    /// Whether the next cue sounds.
    var isEnabled: Bool { state.isOn.withLock { $0 } }

    /// Follows the saved setting from the next cue on.
    func apply(_ settings: Settings) {
        state.isOn.withLock { $0 = settings.playsSoundWhenRecordingStarts }
    }
}
