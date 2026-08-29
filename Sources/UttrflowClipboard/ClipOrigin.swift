/// Who put a clip into the clipboard.
///
/// The clipboard is one list in arrival order, and that is right for as long as one hand
/// is filling it. Uttrflow is a second hand: every finished dictation is recorded as a
/// clip, and a busy morning of dictating pushes a ⌘C from ten minutes ago off the first
/// screen of the panel — not because it stopped being useful but because something else
/// was newer. The two streams were competing for one recency order, and dictation wins
/// that competition every time simply by being more frequent.
///
/// So they are two lists. History holds what the user copied, the Uttrflow tab holds what
/// Uttrflow made, each in its own arrival order, and neither can bury the other.
///
/// Decided once, when the clip arrives, and stored — never re-derived from ``Clip/source``
/// or from the text. A clip that could change which list it is in would move under the
/// user's hand, and the one thing this panel must never get wrong is where a clip is.
public enum ClipOrigin: String, Sendable, Equatable, CaseIterable, Codable {
    /// The user pressed ⌘C somewhere else and the watcher saw the change count move.
    case copied
    /// Uttrflow made it: a finished dictation, or a clip kept from the panel itself.
    case uttrflow

    /// What ``Clip/source`` says on a dictation, and the only thing a clipboard written
    /// before this type existed can be told apart by.
    ///
    /// A string comparison is a poor way to know what something is, which is the whole
    /// reason for this enum — but a file on somebody's disk has only the string, and
    /// reading it once at migration is better than declaring every clip they ever
    /// dictated to be a ⌘C. Written here rather than at the call site so the two
    /// spellings cannot drift; ``Clip/init(from:)`` reads it and `AppDelegate` writes it.
    public static let dictationSource = "Dictation"
}
