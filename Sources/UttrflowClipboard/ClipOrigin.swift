/// Who put a clip into the clipboard: two lists, so chosen dictations cannot bury a ⌘C.
public enum ClipOrigin: String, Sendable, Equatable, CaseIterable, Codable {
    /// The user pressed ⌘C somewhere else and the watcher saw the change count move.
    case copied
    /// Uttrflow made it: a clip the user kept from History or the panel.
    case uttrflow

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        let rawValue = try values.decode(String.self)
        self = Self(rawValue: rawValue) ?? .copied
    }

    /// What `Clip.source` says on a dictation, the only mark an older clipboard carries.
    public static let dictationSource = "Dictation"
}
