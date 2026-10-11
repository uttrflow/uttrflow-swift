// The panel presentation value. See `Docs/panel.md`.
public import Foundation

/// What the quick panel shows.
public struct PanelPresentation: Sendable, Equatable {
    let selectedIndex: Int?
    let rowCacheID: UUID
    private let baseRows: [PanelRow]
    private let baseGroups: [PanelResultGroup]
    public var rows: [PanelRow] { markingSelected(baseRows, at: selectedIndex) }
    package var listRows: [PanelRow] { baseRows }
    public let filters: [PanelFilterChip]
    /// The bottom bar, left to right.
    public let tabs: [PanelTab]
    /// Empty when nothing is filed anywhere, rather than a lone chip saying nothing.
    public let categories: [PanelCategoryChip]
    public let query: String
    public let searchPlaceholder: String
    /// Set only when ``rows`` is empty, naming which of the four nothings this is.
    public let emptyState: MainEmptyState?
    /// The line along the bottom that teaches the three keystrokes.
    public let hint: String
    /// The sheet over the list — naming, filing or confirming a delete — or `nil` for a plain list.
    public let sheet: PanelSheetPresentation?
    /// H1 — the same rows cut into runs, and empty until something is typed.
    public var groups: [PanelResultGroup] {
        guard let selectedRow, let field = selectedRow.matched else { return baseGroups }
        return baseGroups.map { group in
            guard group.field == field else { return group }
            return PanelResultGroup(
                field: group.field, title: group.title,
                rows: markingSelected(group.rows, at: group.rows.firstIndex { $0.id == selectedRow.id }),
                more: group.more)
        }
    }
    package var listGroups: [PanelResultGroup] { baseGroups }
    /// H3 — the one thing to do about an empty result, in the panel's vocabulary.
    public let emptyAction: PanelAction?
    /// B3–B5 — what the panel is saying about a clip it could only copy.
    public let notice: PanelNotice?
    /// I1–I7 — the microphone, and what it can do right now.
    public let microphone: PanelMicrophone
    /// H7 — what the list is scoped to when that differs from the chip last pressed.
    public let scope: String?
    /// What VoiceOver is told when each line appears in the open panel.
    public let announcements: [String]
    /// Stable identities for the corresponding lines, changed only when a new announcement event occurs.
    public let announcementIDs: [UUID]
    /// What VoiceOver says choosing a row will do, which is a copy when the panel cannot paste.
    public let rowHint: String

    public init(
        rows: [PanelRow],
        filters: [PanelFilterChip],
        tabs: [PanelTab] = [],
        categories: [PanelCategoryChip],
        query: String,
        searchPlaceholder: String,
        emptyState: MainEmptyState?,
        hint: String,
        sheet: PanelSheetPresentation? = nil,
        groups: [PanelResultGroup] = [],
        emptyAction: PanelAction? = nil,
        notice: PanelNotice? = nil,
        microphone: PanelMicrophone = PanelPresenter.microphone(for: .ready),
        scope: String? = nil,
        announcements: [String] = [],
        announcementIDs: [UUID] = [],
        rowHint: String = PanelPresenter.pasteRowHint
    ) {
        self.selectedIndex = rows.firstIndex(where: \.isSelected)
        self.rowCacheID = UUID()
        self.baseRows = rows
        self.filters = filters
        self.tabs = tabs
        self.categories = categories
        self.query = query
        self.searchPlaceholder = searchPlaceholder
        self.emptyState = emptyState
        self.hint = hint
        self.sheet = sheet
        self.baseGroups = groups
        self.emptyAction = emptyAction
        self.notice = notice
        self.microphone = microphone
        self.scope = scope
        self.announcements = announcements
        self.announcementIDs = announcementIDs
        self.rowHint = rowHint
    }

    init(
        rows: [PanelRow], filters: [PanelFilterChip], tabs: [PanelTab],
        categories: [PanelCategoryChip], query: String, searchPlaceholder: String,
        emptyState: MainEmptyState?, hint: String, sheet: PanelSheetPresentation?,
        groups: [PanelResultGroup], emptyAction: PanelAction?, notice: PanelNotice?,
        microphone: PanelMicrophone, scope: String?, announcements: [String],
        announcementIDs: [UUID], rowHint: String, selectedIndex: Int?, rowCacheID: UUID
    ) {
        self.selectedIndex = selectedIndex
        self.rowCacheID = rowCacheID
        self.baseRows = rows
        self.filters = filters
        self.tabs = tabs
        self.categories = categories
        self.query = query
        self.searchPlaceholder = searchPlaceholder
        self.emptyState = emptyState
        self.hint = hint
        self.sheet = sheet
        self.baseGroups = groups
        self.emptyAction = emptyAction
        self.notice = notice
        self.microphone = microphone
        self.scope = scope
        self.announcements = announcements
        self.announcementIDs = announcementIDs
        self.rowHint = rowHint
    }

    /// Whether the footer is offering ⌘Z to put a deleted clip back, which is then what ⌘Z does.
    public var offersUndo: Bool { hint == PanelPresenter.undoHint || hint == PanelPresenter.searchUndoHint }

    /// The key that opens the keyboard guide, said under the list but not under a sheet's own keys.
    package var shortcutsHint: String? { sheet == nil ? PanelPresenter.shortcutsHint : nil }

    /// The row Return would insert, so neither the view nor the app counts rows itself.
    public var selectedRow: PanelRow? {
        guard let selectedIndex, baseRows.indices.contains(selectedIndex) else { return nil }
        var row = baseRows[selectedIndex]
        row.isSelected = true
        return row
    }

    var selectedRowID: UUID? { selectedRow?.id }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        let sameSmallFields =
            lhs.selectedIndex == rhs.selectedIndex
            && lhs.filters == rhs.filters && lhs.tabs == rhs.tabs
            && lhs.categories == rhs.categories && lhs.query == rhs.query
            && lhs.searchPlaceholder == rhs.searchPlaceholder && lhs.emptyState == rhs.emptyState
            && lhs.hint == rhs.hint && lhs.sheet == rhs.sheet && lhs.emptyAction == rhs.emptyAction
            && lhs.notice == rhs.notice && lhs.microphone == rhs.microphone && lhs.scope == rhs.scope
            && lhs.announcements == rhs.announcements && lhs.announcementIDs == rhs.announcementIDs
            && lhs.rowHint == rhs.rowHint
        guard sameSmallFields else { return false }
        if lhs.rowCacheID == rhs.rowCacheID { return true }
        return lhs.baseRows == rhs.baseRows && lhs.baseGroups == rhs.baseGroups
    }
}

private func markingSelected(_ rows: [PanelRow], at index: Int?) -> [PanelRow] {
    guard let index, rows.indices.contains(index) else { return rows }
    var values = rows
    values[index].isSelected = true
    return values
}
