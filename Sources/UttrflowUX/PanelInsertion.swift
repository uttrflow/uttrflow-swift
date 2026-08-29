import Foundation
import UttrflowClipboard

/// Why the panel cannot put a clip where the caret is.
///
/// Both of these are knowable *before* the user presses Return, which is the whole reason
/// they are modelled. A panel that closes and then discovers it could not insert has
/// nowhere left to say so; a panel that knows beforehand can say it on the screen the user
/// is already looking at.
public enum PanelInsertionObstacle: Sendable, Equatable, CaseIterable {
    /// B5 — macOS will not let this process type into other applications.
    case accessibilityNotGranted
    /// B4 — there is no caret anywhere to insert at.
    case nothingFocused
    /// Uttrflow itself is the front application, so there is no *other* caret to paste
    /// into — its own window is the one holding focus.
    ///
    /// Modelled separately because the way out is different and specific: click where the
    /// text should go, then paste. Folding it into ``nothingFocused`` would tell somebody
    /// nothing was focused while their cursor sat blinking in a document behind Uttrflow's
    /// own window, which is the kind of accurate-sounding wrongness that sends people
    /// looking for a fault in the wrong place.
    case uttrflowInFront
}

/// Whether choosing a clip will place it, or only copy it.
///
/// Held on the snapshot and set by the app when the panel opens, because the answer is a
/// fact about the machine at that moment rather than anything the panel can work out.
public enum PanelInsertion: Sendable, Equatable {
    case atCaret
    case clipboardOnly(PanelInsertionObstacle)
}

extension PanelInsertion {
    /// What Return will do, given what the machine can answer about itself.
    ///
    /// Here rather than in the app because it is a decision, and the app is the one file
    /// no test can reach. It also has to stay in step with what the insertion engines
    /// actually require, and that is the thing it got wrong.
    ///
    /// **It must not ask whether anything is focused.** That question is the
    /// Accessibility engine's precondition, not the paste engine's: pasting needs only
    /// that some *other* application is in front to receive the ⌘V. Cursor, VS Code and
    /// Claude's desktop app expose no focused element and take a paste perfectly well —
    /// which is why the same precondition was already removed from the engine once, after
    /// it sent every one of Cursor's dictations to the clipboard. It survived here, in the
    /// panel's pre-flight, where it did the identical damage from one step further back:
    /// the panel decided in advance that it could not insert, said "Copied — press ⌘V",
    /// and never called the engine that would have worked.
    ///
    /// - Parameters:
    ///   - isAccessibilityGranted: Whether macOS lets this process type into other
    ///     applications. Both engines that place text need it.
    ///   - isSelfFrontmost: Whether Uttrflow's own window is in front, in which case a
    ///     ⌘V would land in the panel rather than in the document behind it.
    /// - Returns: `.atCaret` when a paste can be attempted, and the obstacle otherwise.
    public static func decided(
        isAccessibilityGranted: Bool, isSelfFrontmost: Bool
    ) -> PanelInsertion {
        guard isAccessibilityGranted else { return .clipboardOnly(.accessibilityNotGranted) }
        guard !isSelfFrontmost else { return .clipboardOnly(.uttrflowInFront) }
        return .atCaret
    }
}

/// What the panel says when it could not place a clip.
///
/// The spec's one forbidden outcome is a panel that closes having done nothing. These
/// exist so that the three ways insertion can fall short are told apart on screen: the
/// user's next move differs in each, and a single "something went wrong" would leave them
/// guessing which.
public struct PanelNotice: Sendable, Equatable {
    public let symbolName: String
    public let message: String
    /// The one thing that would fix it, where there is one.
    public let action: PanelAction?

    public init(symbolName: String, message: String, action: PanelAction? = nil) {
        self.symbolName = symbolName
        self.message = message
        self.action = action
    }
}

extension PanelNotice {
    /// F10 — the disk refused the change.
    ///
    /// Said rather than swallowed. Every write here was a `try?`, so a full or
    /// read-only disk meant the user named a clip, watched the sheet close, and found the
    /// name gone the next time they looked — with nothing in between to suggest anything
    /// had happened at all. A change that did not happen has to look different from one
    /// that did.
    public static func writeFailed(_ why: String) -> PanelNotice {
        PanelNotice(symbolName: "exclamationmark.triangle", message: why, action: nil)
    }
}

extension PanelInsertionObstacle {
    /// What the user is told, and what they can do about it.
    ///
    /// Neither says "failed". The words are on the clipboard in both cases, so what
    /// happened is that the paste became a manual one — which is a smaller thing than the
    /// word failure suggests, and saying it the larger way would send people looking for a
    /// problem that is not there.
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
