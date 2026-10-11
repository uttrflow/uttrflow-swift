// Draws the formatting sheet once per pair of texts for as long as the panel is open.
private import Synchronization
import UttrflowClipboard

/// Remembers the last formatting sheet drawn, so a panel update does not compare the texts again.
final class FormattingSheetMemo: Sendable {
    /// Holds the two texts compared and the sheet drawn from them.
    private struct Drawn {
        let original: String
        let formatted: String
        let title: String
        let confirmTitle: String
        let sheet: PanelSheetPresentation
    }

    private let drawn = Mutex<Drawn?>(nil)

    init() {}

    /// Returns the sheet for this pair, comparing the texts only when this pair has not been drawn before.
    func sheet(
        from original: String, to formatted: String,
        title: String = "Format this code?", confirmTitle: String = "Keep it",
        kind: PanelSheetPresentation.Kind = .formatting
    ) -> PanelSheetPresentation {
        if let last = drawn.withLock({ $0 }), last.original == original, last.formatted == formatted,
            last.title == title, last.confirmTitle == confirmTitle
        {
            return last.sheet
        }
        let sheet = PanelPresenter.formattingSheet(
            TextDiff.compare(from: original, to: formatted), changes: original != formatted,
            title: title, confirmTitle: confirmTitle, kind: kind)
        drawn.withLock {
            $0 = Drawn(
                original: original, formatted: formatted, title: title, confirmTitle: confirmTitle,
                sheet: sheet)
        }
        return sheet
    }

    /// Keeps a sheet drawn elsewhere, so presenting its pair does no comparison.
    func remember(_ prepared: PreparedFormattingSheet) {
        drawn.withLock {
            $0 = Drawn(
                original: prepared.original, formatted: prepared.formatted,
                title: "Format this code?", confirmTitle: "Keep it", sheet: prepared.sheet)
        }
    }

}

/// A formatting sheet drawn ahead of presenting, so the comparison can run off the main actor.
public struct PreparedFormattingSheet: Sendable {
    let original: String
    let formatted: String
    let sheet: PanelSheetPresentation

    /// Compares the texts and draws the sheet; call it from a background task for a large clip.
    public init(from original: String, to formatted: String) {
        self.original = original
        self.formatted = formatted
        sheet = PanelPresenter.formattingSheet(
            TextDiff.compare(from: original, to: formatted), changes: original != formatted)
    }
}
