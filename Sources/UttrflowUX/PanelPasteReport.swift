// What the user is told after the panel has closed and a chosen clip did not visibly arrive.
public import UttrflowCore

/// How a paste from the panel ended, as the app saw it after the panel had gone.
public enum PanelPasteResult: Sendable, Equatable {
    /// The text path answered, with how the words were sent and whether they were seen to arrive.
    case text(InsertionAttempt)
    /// Every text strategy refused; the words are still on the clipboard.
    case textRefused
    /// The picture reached the clipboard and the paste keystroke was refused.
    case pictureRefused
    /// The picture's file went between drawing the panel and pressing Return.
    case pictureMissing
}

/// What the floating button says about a panel paste; one decision for text and pictures. See `Docs/app-quick-panel.md`.
public struct PanelPasteReport: Sendable, Equatable {
    /// The SF Symbol beside the words.
    public let symbolName: String
    /// The line the user reads.
    public let primaryLine: String
    /// The quieter line under it, where there is one.
    public let secondaryLine: String?
    /// What VoiceOver says, with the key spelled out.
    public let spoken: String

    /// Silent when the words were seen to arrive or the target cannot say; a sentence otherwise.
    public static func after(_ result: PanelPasteResult) -> PanelPasteReport? {
        switch result {
        case .text(let attempt) where attempt.method == .clipboard:
            copied
        case .text(let attempt) where attempt.arrival == .unconfirmed:
            PanelPasteReport(
                symbolName: "questionmark.circle", primaryLine: "Inserted — not confirmed",
                secondaryLine: "Still on the clipboard — press ⌘V if it is missing",
                spoken:
                    "Inserted, but not confirmed. It is still on the clipboard, so press Command V "
                    + "if it is missing.")
        case .text:
            nil
        case .textRefused, .pictureRefused:
            copied
        case .pictureMissing:
            PanelPasteReport(
                symbolName: "photo.badge.exclamationmark",
                primaryLine: "That picture is no longer on this Mac", secondaryLine: nil,
                spoken: "That picture is no longer on this Mac. Nothing was pasted.")
        }
    }

    /// On the clipboard and not pasted, in the words the copy-only notices and the dictation use.
    static let copied = PanelPasteReport(
        symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V", secondaryLine: nil,
        spoken: "Copied to the clipboard, not pasted. Press Command V to paste it.")
}
