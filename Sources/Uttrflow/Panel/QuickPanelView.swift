// The quick panel's layout: search, list, menu and bottom bar; its parts live in the files beside it.

import AppKit
import SwiftUI
import UttrflowClipboard
import UttrflowUX

/// Lays out the quick panel; every decision about rows is `PanelPresenter`'s. See Docs/app-quick-panel.md.
struct QuickPanelView: View {
    let presentation: PanelPresentation
    /// Keystrokes, and the clicks that are keystrokes said another way.
    var onKey: (PanelKey) -> Void = { _ in }
    /// A row's own actions. The ones the panel can answer itself arrive as keys instead.
    var onIntent: (PanelIntent) -> Void = { _ in }
    /// Bumped by the controller on every open, so the caret returns to the search field.
    var openCount: Int = 0
    var compositionStatus: (() -> Bool)?
    @State var query: String = ""
    /// True while `query` is being set from `presentation.query` rather than typed, so that set is never relayed as a search.
    @State var isSyncingQuery = false
    /// Which row's ⋯ menu is open, if any; every action in it also has a key of its own.
    @State var rowMenu = PanelRowMenuState()
    /// Which menu item the pointer is on, tracked by `PointerWatch` because `onHover` is inactive here.
    @State private var hoveredItem: String?
    @FocusState var isSearchFocused: Bool
    @FocusState var isSheetFocused: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            chipRow
            list
            // Sits above the hint because it reports what just happened, not what the keys do.
            if let scope = presentation.scope { microphoneStatus(scope) }
            if let status = presentation.microphone.status { microphoneStatus(status) }
            if let notice = presentation.notice { noticeBar(notice) }
            hint
            tabBar
        }
        // Fills the window so a dragged border never leaves the panel's corners empty.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuickPanelBackdrop())
        .clipShape(.rect(cornerRadius: QuickPanelMetrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: QuickPanelMetrics.corner)
                .strokeBorder(Color.panelEdge, lineWidth: 1)
        )
        // Over the list, so the row a sheet asks about stays visible behind it.
        .overlay { if let sheet = presentation.sheet { sheetOverlay(sheet) } }
        .overlay(alignment: .topTrailing) { menuOverlay }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didLiveScrollNotification)) { _ in
            rowMenu.handle(.scroll)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            rowMenu.handle(.windowResignedKey)
        }
        // Hands focus back to the search when a sheet closes; see Docs/app-quick-panel.md on focus.
        .task(id: presentation.sheet == nil) {
            guard presentation.sheet == nil else { return }
            isSheetFocused = false
            isSearchFocused = true
        }
        // Closes a leftover menu and resets the field before the panel shows, so no stale text ever flashes.
        .onChange(of: openCount) {
            rowMenu = PanelRowMenuState()
            isSyncingQuery = true
            query = presentation.query
            isSyncingQuery = false
        }
        .task(id: openCount) {
            // A resumed sheet with a field keeps the caret; its `onAppear` does not run again (#920).
            guard presentation.sheet?.takesTyping == true else {
                isSearchFocused = true
                return
            }
            isSearchFocused = false
            await Task.yield()
            isSheetFocused = true
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 9) {
            logo
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.panelLabelDim)
                    .accessibilityHidden(true)
                field
            }
            .padding(.horizontal, 14)
            .frame(height: QuickPanelMetrics.searchHeight)
            .background(searchGround)

            // Starts a dictation into the search field.
            Button {
                onIntent(.dictate)
            } label: {
                Image(systemName: presentation.microphone.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        presentation.microphone.isEnabled
                            ? Color.panelLabelSoft : Color.panelLabelDim
                    )
                    .frame(
                        width: QuickPanelMetrics.controlHeight,
                        height: QuickPanelMetrics.controlHeight
                    )
                    .background(Color.panelCard, in: .rect(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.panelLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!presentation.microphone.isEnabled)
            .accessibilityLabel(presentation.microphone.label)
            .help(presentation.microphone.status ?? presentation.microphone.label)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The search field's film, accent ring and glow; the glow goes with the caret.
    private var searchGround: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return shape.fill(Color.panelCard)
            .overlay(shape.strokeBorder(Color.panelAccent.opacity(0.45), lineWidth: 1))
            .shadow(color: Color.panelAccent.opacity(isSearchFocused ? 0.45 : 0), radius: 10)
    }

    /// Draws the placeholder itself, because `TextField` cannot give it the panel's measured grey.
    private var field: some View {
        ZStack(alignment: .leading) {
            if query.isEmpty {
                Text(presentation.searchPlaceholder)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.panelLabelDim)
                    .allowsHitTesting(false)
            }
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.panelLabel)
                .focused($isSearchFocused)
                .accessibilityLabel(presentation.searchPlaceholder)
                // Reports the whole contents: the field owns its own selection, deletion and dictation.
                .onChange(of: query) { _, text in
                    // A programmatic reset from `presentation.query`, not a keystroke; nothing to relay (#861).
                    guard !isSyncingQuery else { return }
                    // Under a sheet with no field, typing would filter away the row being asked about (#946).
                    if let sheet = presentation.sheet, !sheet.takesTyping {
                        if text != presentation.query { query = presentation.query }
                        return
                    }
                    relayKey(.search(text))
                }
                // On the field, not the panel: `NSTextField` swallows arrow keys itself.
                .onKeyPress(.upArrow) { send(.up) }
                .onKeyPress(.downArrow) { send(.down) }
                .onKeyPress(.return) { send(.return) }
                .onKeyPress(.escape) { send(.escape) }
                .onKeyPress(phases: .down) { keyPress($0) }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // One structure whether grouped or flat, so a row's identity changes with its section.
                    ForEach(sections) { section in
                        if let title = section.title { groupHeading(title) }
                        ForEach(section.rows) { row in
                            // Keyed by section as well as clip, or SwiftUI keeps the old rendering.
                            rowView(row, isSelected: row.id == presentation.selectedRow?.id)
                                .id(section.key(for: row))
                        }
                        if let text = section.moreLine { moreLine(text) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .overlay {
                if let empty = presentation.emptyState {
                    PanelEmptyStateView(
                        state: empty, showsClearSearch: !presentation.query.isEmpty,
                        emptyAction: presentation.emptyAction,
                        onClearSearch: { relayKey(.clearSearch) }, onIntent: onIntent)
                }
            }
            .frame(maxHeight: .infinity)
            // Keeps the selection on screen; `anchor: nil` moves the list by the least it can.
            .onChange(of: presentation.selectedRow?.id) { _, _ in
                guard let selection = selectedKey else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(selection, anchor: nil)
                }
            }
            // Restore the highlighted row when reopening, even when selection predates this view.
            .task(id: openCount) {
                await Task.yield()
                guard let selection = selectedKey else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(selection, anchor: nil)
                }
            }
        }
    }

    /// The selected row under the key it is drawn with, so the list can scroll to it.
    private var selectedKey: String? {
        guard let row = presentation.selectedRow else { return nil }
        let sectionID = row.matched.map(String.init(describing:)) ?? "all"
        return "\(sectionID)-\(row.id)"
    }

    /// The list as drawn: one unnamed run while browsing, one run per heading while searching.
    private var sections: [QuickPanelSection] {
        guard !presentation.listGroups.isEmpty else {
            return [QuickPanelSection(id: "all", title: nil, rows: presentation.listRows, moreLine: nil)]
        }
        return presentation.listGroups.map {
            QuickPanelSection(
                id: String(describing: $0.field), title: $0.title, rows: $0.rows,
                moreLine: $0.moreLine)
        }
    }

    // MARK: - Row

    /// Why the microphone is dimmed; a disabled control with no reason beside it gets pressed twice.
    private func microphoneStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Color.panelLabelDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    /// What the panel says when it could only copy; not an error, because the words are on the clipboard.
    private func noticeBar(_ notice: PanelNotice) -> some View {
        HStack(spacing: 7) {
            Image(systemName: notice.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.panelKey)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.system(size: 11))
                .foregroundStyle(Color.panelLabel)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action = notice.action {
                Button(action.title) { onIntent(action.intent) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.panelAccentBright)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.panelKey.opacity(0.10))
        .overlay(alignment: .top) { hairline }
    }

    private func groupHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color.panelLabelDim)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// Draws the presenter's overflow sentence, so the user does not read the list as complete.
    private func moreLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Color.panelLabelDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    /// The row view with this panel's callbacks; only its value inputs decide whether it redraws.
    private func rowView(_ row: PanelRow, isSelected: Bool) -> some View {
        QuickPanelRow(
            row: row, isSelected: isSelected, hasSelection: presentation.selectedRow != nil,
            isMenuOpen: rowMenu.rowID == row.id, hint: presentation.rowHint, openCount: openCount,
            onKey: { relayKey($0) }, onAction: { perform($0) }, onMenu: { rowMenu.open($0) }
        )
        .equatable()
    }

    /// The open ⋯ menu, anchored to the panel's edge so the scroll view never clips it, plus its click-away.
    @ViewBuilder private var menuOverlay: some View {
        if let id = rowMenu.rowID, let row = presentation.rows.first(where: { $0.id == id }) {
            ZStack(alignment: .topTrailing) {
                // Catches the click-away; not dimmed, because the list is the menu's context.
                Color.black.opacity(0.001)
                    .contentShape(.rect)
                    .onTapGesture { rowMenu.handle(.clickAway) }
                actionMenu(for: row)
                    .padding(.top, 84)
                    .padding(.trailing, 10)
            }
            .transition(.opacity)
        }
    }

    /// The ⋯ menu, drawn here rather than as an `NSMenu` and headed by the clip it acts on.
    @ViewBuilder private func actionMenu(for row: PanelRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.panelLabelSoft)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.panelLabelDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { hairline }

            ForEach(row.actions) { action in
                menuItem(action)
            }
        }
        .frame(width: 200)
        .panelPopover(cornerRadius: 11, shadowOpacity: 0.55, radius: 22, y: 10)
    }

    private func menuItem(_ action: PanelAction) -> some View {
        let isDestructive = action.isDestructive
        // Delete is last and is the only item ruled off from the rest.
        return Button {
            rowMenu.select(action, perform: perform)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        hoveredItem == action.id
                            ? (isDestructive ? Color.panelDestructive : Color.panelAccentBright)
                            : Color.panelLabelSoft
                    )
                    .frame(width: 15)
                Text(action.title)
                    .font(.system(size: 12.5))
                    // Delete reads at full weight until hovered; a greyed item looks unavailable.
                    .foregroundStyle(
                        isDestructive && hoveredItem == action.id
                            ? Color.panelDestructive : Color.panelLabel)
                Spacer(minLength: 0)
                // The chord is how the action is found without the pointer, so it is drawn beside it.
                if let shortcut = action.shortcut {
                    Text(shortcut.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.panelLabelDim)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                hoveredItem == action.id
                    ? (isDestructive
                        ? Color.panelDestructive.opacity(0.13) : Color.panelAccent.opacity(0.13))
                    : Color.clear
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if isDestructive { hairline }
        }
        .background(
            PointerWatch { isInside in
                if isInside {
                    hoveredItem = action.id
                } else if hoveredItem == action.id {
                    hoveredItem = nil
                }
            }
        )
    }

    // MARK: - Bottom

    /// The line that teaches the three keystrokes, in the presenter's words.
    private var hint: some View {
        HStack(spacing: 8) {
            Text(presentation.hint)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcuts = presentation.shortcutsHint {
                Text(shortcuts).fixedSize()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.panelLabelDim)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .overlay(alignment: .top) { hairline }
    }

    /// The bottom bar; what each tab means is the presenter's, and every button does something.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(presentation.tabs) { tab in
                Button {
                    perform(tab.intent)
                } label: {
                    ZStack(alignment: .top) {
                        if tab.isActive {
                            Capsule()
                                .fill(Color.panelAccent)
                                .frame(width: 22, height: 2)
                        }
                        tabGlyph(tab.glyph)
                            .foregroundStyle(
                                tab.isActive ? Color.panelAccent : Color.panelLabelDim
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay(alignment: .top) { hairline }
    }

    /// A tab's glyph: a symbol, or the mark at 13 points so it sits level with the 13-point symbols.
    @ViewBuilder
    private func tabGlyph(_ glyph: PanelTabGlyph) -> some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .regular))
        case .brandMark:
            UttrflowMarkView(height: 13)
        }
    }
}
