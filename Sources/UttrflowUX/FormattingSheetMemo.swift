// Draws the formatting sheet once per pair of texts for as long as the panel is open.
import UttrflowClipboard

/// Remembers the last formatting sheet drawn, so a panel update does not compare the texts again.
final class FormattingSheetMemo: Sendable {
    /// Identifies the inputs for a formatting sheet.
    private struct Source: Equatable, Sendable {
        let original: String
        let formatted: String
        let title: String
        let confirmTitle: String
    }

    private enum Slot: Hashable, Sendable { case sheet }

    private let drawn = Memo<Slot, Source, PanelSheetPresentation>(limit: 1)

    init() {}

    /// Returns the sheet for this pair, comparing the texts only when this pair has not been drawn before.
    func sheet(
        from original: String, to formatted: String,
        title: String = "Format this code?", confirmTitle: String = "Keep it",
        kind: PanelSheetPresentation.Kind = .formatting
    ) -> PanelSheetPresentation {
        drawn.value(
            for: .sheet,
            source: Source(original: original, formatted: formatted, title: title, confirmTitle: confirmTitle)
        ) {
            PanelPresenter.formattingSheet(
                TextDiff.compare(from: original, to: formatted), changes: original != formatted,
                title: title, confirmTitle: confirmTitle, kind: kind)
        }
    }

    /// Keeps a sheet drawn elsewhere, so presenting its pair does no comparison.
    func remember(_ prepared: PreparedFormattingSheet) {
        drawn.store(
            prepared.sheet, for: .sheet,
            source: Source(
                original: prepared.original, formatted: prepared.formatted,
                title: "Format this code?", confirmTitle: "Keep it"))
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
