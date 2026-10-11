// What the user is told after the panel has closed: a clip that did not visibly arrive, or a deliberate Copy.
public import UttrflowCore

/// How a clipboard action from the panel ended, as the app saw it after the panel had gone.
public enum PanelPasteResult: Sendable, Equatable {
    /// The text path answered, with how the words were sent and whether they were seen to arrive.
    case text(InsertionAttempt)
    /// Every text strategy refused; the words are still on the clipboard.
    case textRefused
    /// Clipboard-free insertion refused; the panel did not replace the user's clipboard.
    case textCouldNotPaste
    /// The picture reached the clipboard and the paste keystroke was refused.
    case pictureRefused
    /// The picture's file went between drawing the panel and pressing Return.
    case pictureMissing
    /// An explicit Copy placed this kind of content on the clipboard.
    case copied(PanelCopyContent)
}

/// What a deliberate Copy placed on the clipboard.
public enum PanelCopyContent: Sendable, Equatable {
    /// Visible text.
    case text
    /// A secret, written concealed so clipboard managers skip it.
    case hiddenText
    /// A picture.
    case picture
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

    /// Silent after a text insertion, except when the words are left on the clipboard.
    public static func after(_ result: PanelPasteResult) -> PanelPasteReport? {
        switch result {
        case .copied(.text), .copied(.picture): copied
        case .copied(.hiddenText): copiedHidden
        case .text(let attempt) where attempt.method == .clipboard:
            copied
        case .text:
            nil
        case .textRefused, .pictureRefused:
            copied
        case .textCouldNotPaste:
            PanelPasteReport(
                symbolName: "exclamationmark.circle",
                primaryLine: "Couldn't paste this clip", secondaryLine: nil,
                spoken: "Couldn't paste this clip. Your clipboard was left unchanged.")
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

    /// A secret on the clipboard, confirmed without showing any of it.
    private static let copiedHidden = PanelPasteReport(
        symbolName: "doc.on.clipboard", primaryLine: "Copied hidden clip — press ⌘V", secondaryLine: nil,
        spoken: "Copied a hidden clip to the clipboard, not pasted. Press Command V to paste it.")
}
