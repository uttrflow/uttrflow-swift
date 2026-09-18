// Draws the formatting sheet once per pair of texts for as long as the panel is open.
private import Synchronization
import UttrflowClipboard

/// Remembers the last formatting sheet drawn, so a panel update does not compare the texts again.
final class FormattingSheetMemo: Sendable, Equatable {
    /// Holds the two texts compared and the sheet drawn from them.
    private struct Drawn {
        let original: String
        let formatted: String
        let sheet: PanelSheetPresentation
    }

    private let drawn = Mutex<Drawn?>(nil)

    init() {}

    /// Returns the sheet for this pair, comparing the texts only when this pair has not been drawn before.
    func sheet(from original: String, to formatted: String) -> PanelSheetPresentation {
        if let last = drawn.withLock({ $0 }), last.original == original, last.formatted == formatted {
            return last.sheet
        }
        let sheet = PanelPresenter.formattingSheet(
            TextDiff.compare(from: original, to: formatted), changes: original != formatted)
        drawn.withLock { $0 = Drawn(original: original, formatted: formatted, sheet: sheet) }
        return sheet
    }

    /// Compares equal to any other memo, because a cache is not part of what the panel shows.
    static func == (lhs: FormattingSheetMemo, rhs: FormattingSheetMemo) -> Bool { true }
}
