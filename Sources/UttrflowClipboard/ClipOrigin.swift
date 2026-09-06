/// Who put a clip into the clipboard: two lists, so dictations cannot bury a ⌘C; decided once, on arrival.
public enum ClipOrigin: String, Sendable, Equatable, CaseIterable, Codable {
    /// The user pressed ⌘C somewhere else and the watcher saw the change count move.
    case copied
    /// Uttrflow made it: a finished dictation, or a clip kept from the panel itself.
    case uttrflow

    /// What `Clip.source` says on a dictation, the only mark an older clipboard carries.
    public static let dictationSource = "Dictation"
}
