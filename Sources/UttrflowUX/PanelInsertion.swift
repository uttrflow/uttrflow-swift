// Whether the panel can place a clip at the caret, and what it says when it can only copy.
import Foundation
import UttrflowClipboard

/// Why the panel cannot put a clip at the caret, knowable before Return so the panel can say so.
public enum PanelInsertionObstacle: Sendable, Equatable, CaseIterable {
    /// B5 — macOS will not let this process type into other applications.
    case accessibilityNotGranted
    /// B4 — there is no caret anywhere to insert at.
    case nothingFocused
    /// Uttrflow itself is in front, so there is no other caret; the way out is to click where the text goes.
    case uttrflowInFront
}

/// Whether choosing a clip will place it or only copy it; set by the app when the panel opens.
public enum PanelInsertion: Sendable, Equatable {
    /// A paste can be attempted.
    case atCaret
    /// The clip only reaches the clipboard, for this reason.
    case clipboardOnly(PanelInsertionObstacle)
}

extension PanelInsertion {
    /// What Return will do; it never asks what is focused. See Docs/ux-panel-insertion.md.
    public static func decided(
        isAccessibilityGranted: Bool, isSelfFrontmost: Bool
    ) -> PanelInsertion {
        guard isAccessibilityGranted else { return .clipboardOnly(.accessibilityNotGranted) }
        guard !isSelfFrontmost else { return .clipboardOnly(.uttrflowInFront) }
        return .atCaret
    }
}

/// What the panel says when it could not place a clip; the three obstacles are told apart on screen.
public struct PanelNotice: Sendable, Equatable {
    /// The SF Symbol beside the sentence.
    public let symbolName: String
    /// The sentence.
    public let message: String
    /// The one thing that would fix it, where there is one.
    public let action: PanelAction?

    /// Builds a notice; no action unless given one.
    public init(symbolName: String, message: String, action: PanelAction? = nil) {
        self.symbolName = symbolName
        self.message = message
        self.action = action
    }
}

extension PanelNotice {
    /// The disk refused the change, said rather than swallowed, so a failed write looks unlike a success.
    public static func writeFailed(_ why: String) -> PanelNotice {
        PanelNotice(symbolName: "exclamationmark.triangle", message: why, action: nil)
    }
}

extension PanelInsertionObstacle {
    /// What the user is told and can do; neither says "failed", since the words are on the clipboard.
    public var notice: PanelNotice {
        switch self {
        case .nothingFocused:
            PanelNotice(
                symbolName: "doc.on.clipboard",
                message: "Copied — press ⌘V where you want it")
        case .uttrflowInFront:
            PanelNotice(
                symbolName: "doc.on.clipboard",
                message: "Copied — click where you want it, then press ⌘V")
        case .accessibilityNotGranted:
            PanelNotice(
                symbolName: "hand.raised",
                message: "Copied — press ⌘V. Turn on Accessibility and Uttrflow can paste for you.",
                action: PanelAction(
                    title: "Open Accessibility settings", symbolName: "gearshape",
                    intent: .openAccessibilitySettings))
        }
    }
}
