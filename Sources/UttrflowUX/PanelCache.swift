// Holds what the panel works out from its clips for the life of the process, not one open.
import UttrflowClipboard

/// The memos behind the panel, kept out of ``PanelSnapshot`` so a snapshot is state alone and compares structurally.
final class PanelCache: Sendable {
    /// The cache every panel draws from; a test binds its own so parallel tests cannot disturb its counts.
    @TaskLocal static var current = PanelCache()

    /// The formatting sheet last drawn, so an update does not diff again.
    let formattingSheets = FormattingSheetMemo()
    /// The last lists of rows found, so a keystroke searches the history once and an arrow key not at all.
    let searchMemo = PanelSearchMemo()
    /// The rows last drawn, so an arrow key rebuilds none of them.
    let rowMemo = PanelRowMemo()
    /// Each clip's search-folded text, so a keystroke does not fold every clip again.
    let foldedTexts = FoldedTexts()
    /// Note checklist counts, so typing does not parse formatted notes again.
    let checklistProgresses = ChecklistProgresses()
    /// Which code clips can be re-indented, so neither a keystroke nor a reopen asks again.
    let reindentOffers = ReindentOffers()

    init() {}
}
