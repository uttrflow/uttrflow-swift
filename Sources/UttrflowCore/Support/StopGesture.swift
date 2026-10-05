/// What the user has to do, or does not, to end a recording that is already under way.
public enum StopGesture: Sendable, Equatable {
    /// Hold-to-talk: releasing the keys ends the recording.
    case letGo
    /// A control started the recording, so clicking it again ends the recording.
    case clickAgain
    /// Press-to-toggle: pressing the shortcut again ends the recording; releasing does not.
    case pressAgain
    /// A hold-to-talk double tap left the microphone open, so pressing the shortcut again ends it.
    case pressAgainHandsFree

    /// The visible instruction, in the words the dock can fit beside the waveform.
    public var recordingLine: String {
        switch self {
        case .letGo: "Let go to finish"
        case .clickAgain: "Click to finish"
        case .pressAgain: "Press shortcut to finish"
        case .pressAgainHandsFree: "Hands-free — press shortcut to finish"
        }
    }

    /// What VoiceOver reads before the optional countdown.
    public var recordingAccessibilityPrefix: String {
        switch self {
        case .letGo: "Listening. Let go to finish"
        case .clickAgain: "Listening. Click the button again to finish"
        case .pressAgain: "Listening. Press the shortcut again to finish"
        case .pressAgainHandsFree: "Listening. Hands-free. Press the shortcut again to finish"
        }
    }
}
