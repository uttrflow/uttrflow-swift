// The quick panel's layout: search, chips, list, menu, sheets and colours.

import UttrflowClipboard
import UttrflowUX
import SwiftUI

/// Lays out the quick panel; every decision about rows is `PanelPresenter`'s. See Docs/app-quick-panel.md.
struct QuickPanelView: View {
    let presentation: PanelPresentation
    /// Keystrokes, and the clicks that are keystrokes said another way.
    var onKey: (PanelKey) -> Void = { _ in }
    /// A row's own actions. The ones the panel can answer itself arrive as keys instead.
    var onIntent: (PanelIntent) -> Void = { _ in }
    /// Bumped by the controller on every open, so the caret returns to the search field.
    var openCount: Int = 0

    @State private var query: String = ""
    @State private var hovered: UUID?
    /// Which row's ⋯ menu is open, if any; every action in it also has a key of its own.
    @State private var openMenu: UUID?
    /// Which menu item the pointer is on, tracked by `PointerWatch` because `onHover` is inactive here.
    @State private var hoveredItem: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isSheetFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .background(Color.panelSurface)
        .clipShape(.rect(cornerRadius: QuickPanelMetrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: QuickPanelMetrics.corner)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        )
        // Over the list, so the row a sheet asks about stays visible behind it.
        .overlay { if let sheet = presentation.sheet { sheetOverlay(sheet) } }
        .overlay(alignment: .topTrailing) { menuOverlay }
        // Hands focus back to the search when a sheet closes; see Docs/app-quick-panel.md on focus.
        .task(id: presentation.sheet == nil) {
            guard presentation.sheet == nil else { return }
            isSheetFocused = false
            isSearchFocused = true
        }
        // Closes a menu left open from the last showing; the panel is built once and shown many times.
        .onChange(of: openCount) { openMenu = nil }
        .task(id: openCount) {
            query = presentation.query
            hovered = nil
            isSearchFocused = true
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 9) {
            logo
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelLabelDim)
                    .accessibilityHidden(true)
                field
            }
            .padding(.horizontal, 11)
            .frame(height: QuickPanelMetrics.controlHeight)
            .background(Color.panelCard, in: .rect(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    // A soft ring, so the empty search field does not outshine the row Return would paste.
                    .strokeBorder(
                        isSearchFocused ? Color.panelAccent.opacity(0.30) : Color.panelLine,
                        lineWidth: 1)
            )

            // Starts a dictation into the search field.
            Button {
                onIntent(.dictate)
            } label: {
                Image(systemName: presentation.microphone.symbolName)
                    .font(.system(size: 14, weight: .medium))
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
                .onChange(of: query) { _, text in relayKey(.search(text)) }
                // On the field, not the panel: `NSTextField` swallows arrow keys itself.
                .onKeyPress(.upArrow) { send(.up) }
                .onKeyPress(.downArrow) { send(.down) }
                .onKeyPress(.return) { send(.return) }
                .onKeyPress(.escape) { send(.escape) }
                .onKeyPress(phases: .down) { commandKey($0) }
        }
    }

    // MARK: - Chips

    /// The mark at the head of the search bar, or nothing when the bundle lacks the resource.
    @ViewBuilder private var logo: some View {
        if let mark = Bundle.module.image(forResource: "uttrflow-logo") {
            // The resource is an alpha shape, so the tint here is what draws it.
            Image(nsImage: mark)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.panelAccentBright)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Uttrflow")
        }
    }

    /// One scrolling row of kind filters and collection chips, divided because the two axes combine.
    private var chipRow: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(presentation.filters) { chip in
                            pill(chip.title, isActive: chip.isActive, shortcut: nil) {
                                relayKey(.filter(chip.filter))
                            }
                        }
                        if !presentation.categories.isEmpty {
                            Rectangle()
                                .fill(Color.panelLine)
                                .frame(width: 1, height: 15)
                                .padding(.horizontal, 3)
                                .accessibilityHidden(true)
                        }
                        ForEach(presentation.categories) { chip in
                            pill(
                                chip.title, isActive: chip.isActive, shortcut: chip.shortcut,
                                tint: .panelAccentBright
                            ) {
                                // `chosen`, not `shortcut`: a chip past the ninth has no number.
                                relayKey(.category(number: chip.chosen))
                            }
                            .id(chip.id)
                            // On the chip, which is the thing renamed or deleted; All has no menu.
                            .contextMenu {
                                if let category = chip.category {
                                    Button("Rename…") { onIntent(.renameCategory(category)) }
                                    Button("Delete…") { onIntent(.deleteCategory(category)) }
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.never)
                // Scrolls a collection chosen by ⌘-digit into view, so the chip agrees with the list.
                .onChange(of: activeCategory) { _, active in
                    guard let active else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(active, anchor: .trailing)
                    }
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 26)
        .padding(.bottom, 10)
    }

    /// Which collection is on, if any — the thing the row scrolls to keep in view.
    private var activeCategory: String? {
        presentation.categories.first { $0.isActive }?.id
    }

    /// One chip; `tint` tells a kind filter (where you are) from a collection (something you made).
    private func pill(
        _ title: String, isActive: Bool, shortcut: Int?, tint: Color = .panelAccent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.65)
                }
            }
            .foregroundStyle(isActive ? tint : Color.panelLabelSoft)
            // Nine points either side keeps eight chips within a 420-point panel.
            .padding(.horizontal, 9)
            .frame(height: 26)
            // A wash, not a fill, so the active chip stays quieter than the clip about to be pasted.
            .background(isActive ? tint.opacity(0.16) : .clear, in: .capsule)
            .overlay(
                Capsule().strokeBorder(
                    isActive ? tint.opacity(0.35) : Color.panelLine, lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(shortcut.map { "Shortcut command \($0)" } ?? "")
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
                            rowView(row).id(section.key(for: row))
                        }
                        if section.more > 0 { moreLine(section.more) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .overlay { if let empty = presentation.emptyState { emptyView(empty) } }
            .frame(maxHeight: .infinity)
            // Keeps the selection on screen; `anchor: nil` moves the list by the least it can.
            .onChange(of: presentation.selectedRow?.id) { _, _ in
                guard let selection = selectedKey else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(selection, anchor: nil)
                }
            }
        }
    }

    /// The selected row under the key it is drawn with, so the list can scroll to it.
    private var selectedKey: String? {
        for section in sections {
            if let row = section.rows.first(where: \.isSelected) { return section.key(for: row) }
        }
        return nil
    }

    /// The list as drawn: one unnamed run while browsing, one run per heading while searching.
    private var sections: [QuickPanelSection] {
        guard !presentation.groups.isEmpty else {
            return [QuickPanelSection(id: "all", title: nil, rows: presentation.rows, more: 0)]
        }
        return presentation.groups.map {
            QuickPanelSection(
                id: String(describing: $0.field), title: $0.title, rows: $0.rows, more: $0.more)
        }
    }

    private func emptyView(_ state: MainEmptyState) -> some View {
        VStack(spacing: 8) {
            Image(systemName: state.symbolName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.panelLabelDim)
            Text(state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelLabelSoft)
            Text(state.message)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.panelLabelDim)
                .multilineTextAlignment(.center)
            // Outside the combined accessibility element, so a screen reader reaches it as a button.
            if let action = presentation.emptyAction {
                Button(action.title) { onIntent(action.intent) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.panelAccentBright)
                    .padding(.top, 2)
                    .accessibilityHidden(false)
            }
        }
        .padding(.horizontal, 40)
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

    /// Admits that the list is capped, so the user does not read it as complete.
    private func moreLine(_ count: Int) -> some View {
        Text("\(count) more · keep typing to narrow it")
            .font(.system(size: 10.5))
            .foregroundStyle(Color.panelLabelDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    /// B6 — ⌘-click is ⌘⏎ on the row under the pointer.
    private func choose(_ row: PanelRow, plain: Bool) {
        relayKey(plain ? .choosePlain(row.id) : .choose(row.id))
    }

    private func rowView(_ row: PanelRow) -> some View {
        let look = QuickPanelRowAppearance.of(
            row, hovered: hovered, hasSelection: presentation.selectedRow != nil)
        return Button {
            // Reads ⌘ at the click rather than tracking it as state; a modifier is not a mode.
            choose(row, plain: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 9) {
                mark(row)
                if let file = row.imageFile { thumbnail(file) }
                if let alias = row.alias { aliasChip(alias) }
                if let language = row.language { languageChip(language) }
                if let measurements = row.measurements {
                    Text(measurements)
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            row.isImageMissing ? Color.panelKey : Color.panelLabelSoft
                        )
                        .lineLimit(1)
                        // Sized to content, or an empty summary takes half the row and truncates this.
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(row.summary)
                    .font(
                        .system(
                            size: row.isMasked ? 12 : 12.5,
                            design: row.isMonospaced ? .monospaced : .default)
                    )
                    .foregroundStyle(row.isMasked ? Color.panelLabelDim : Color.panelLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Shows the whole line as a tooltip; whether there is one is `PanelRow.tooltip`'s answer.
                    .help(row.tooltip ?? "")
                trailing(row, showsActions: look.showsActions)
            }
            // Tighter on the leading edge: the glyph sits in the gutter, the ⋯ wants the room on the right.
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .frame(height: QuickPanelMetrics.rowHeight)
            .background(
                look.isSelected
                    // A wash of the accent under the ring; together they mark the row without shouting.
                    ? AnyShapeStyle(Color.panelAccent.opacity(0.08))
                    : AnyShapeStyle(look.isFilled ? Color.panelCardHigh : .clear),
                in: .rect(cornerRadius: 8)
            )
            // A faint ring, not a brighter fill, because hover fills too and only one row answers Return.
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        look.isSelected ? Color.panelAccent.opacity(0.38) : .clear,
                        lineWidth: 1)
            )
            .opacity(look.isSubdued ? 0.55 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(PressableRow())
        // In front of the row, not behind it: hit testing stops at the first view that claims the point.
        .overlay(
            RightClickWatch { openMenu = row.id }
        )
        // `NSTrackingArea` rather than `.onHover`, which only reports while Uttrflow is the active app.
        .background(
            PointerWatch { isInside in
                if isInside {
                    hovered = row.id
                } else if hovered == row.id {
                    hovered = nil
                }
            }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: look)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuickPanelSpeech.label(for: row))
        .accessibilityHint("Pastes where you were typing")
        .accessibilityAddTraits(look.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            // The same actions the pointer gets, spoken; the ⋯ button is hidden from VoiceOver.
            ForEach(row.actions) { action in
                Button(action.title) { perform(action.intent) }
            }
        }
    }

    @ViewBuilder private func mark(_ row: PanelRow) -> some View {
        let glyph = Image(systemName: row.symbolName)
        let colour = tint(for: row.kind)
        if QuickPanelSpeech.hasTile(row.kind) {
            glyph
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(colour)
                .frame(width: 22, height: 22)
                .background(colour.opacity(0.15), in: .rect(cornerRadius: 6))
        } else {
            // Small and dim: four rows in five carry this glyph, so it must read as texture, not signal.
            glyph
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(colour.opacity(0.62))
                .frame(width: 17)
        }
    }

    /// The picture, decoded once at drawn size; a file that has gone shows the card colour.
    private func thumbnail(_ file: URL) -> some View {
        Group {
            // Decoded once and at the size it is drawn; see `PanelThumbnails`.
            if let picture = PanelThumbnails.shared.thumbnail(for: file) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.panelCard
            }
        }
        .frame(width: 34, height: 24)
        .clipShape(.rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.panelLine, lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// Drawn only when the detector is confident, and quieter than the alias chip beside it.
    private func languageChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.panelCode)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.panelCode.opacity(0.12), in: .rect(cornerRadius: 5))
            .fixedSize()
            .accessibilityLabel("\(text) code")
    }

    private func aliasChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.panelKey)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color.panelKey.opacity(0.14), in: .rect(cornerRadius: 6))
            .fixedSize()
    }

    /// The pin and the ⋯, anchored outside any hover swap so the far right of a row never moves.
    @ViewBuilder private func trailing(_ row: PanelRow, showsActions: Bool) -> some View {
        HStack(spacing: 6) {
            // Only state that belongs to this clip: a pin. Time and actions live in the ⋯ menu.
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.panelAccentBright)
            }
            Button {
                openMenu = openMenu == row.id ? nil : row.id
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    // Ghost grey at rest, ordinary grey on the row being looked at: findable, not noticeable.
                    .foregroundStyle(colourOfDots(for: row, showsActions: showsActions))
                    .frame(width: 20, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The row already speaks every action through its accessibility actions.
            .accessibilityHidden(true)
        }
        .fixedSize()
    }

    private func colourOfDots(for row: PanelRow, showsActions: Bool) -> Color {
        if openMenu == row.id { return .panelAccentBright }
        if showsActions || row.isSelected { return .panelLabelSoft }
        return .panelGhost
    }

    /// The open ⋯ menu, anchored to the panel's edge so the scroll view never clips it, plus its click-away.
    @ViewBuilder private var menuOverlay: some View {
        if let id = openMenu, let row = presentation.rows.first(where: { $0.id == id }) {
            ZStack(alignment: .topTrailing) {
                // Catches the click-away; not dimmed, because the list is the menu's context.
                Color.black.opacity(0.001)
                    .contentShape(.rect)
                    .onTapGesture { openMenu = nil }
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
        .background(Color.panelCardHigh, in: .rect(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11).strokeBorder(Color.panelLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
    }

    private func menuItem(_ action: PanelAction) -> some View {
        let isDestructive = action.isDestructive
        // Delete is last and is the only item ruled off from the rest.
        return Button {
            openMenu = nil
            perform(action.intent)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        hoveredItem == action.id
                            ? (isDestructive ? Color.dockWarning : Color.panelAccentBright)
                            : Color.panelLabelSoft
                    )
                    .frame(width: 15)
                Text(action.title)
                    .font(.system(size: 12.5))
                    // Delete reads at full weight until hovered; a greyed item looks unavailable.
                    .foregroundStyle(
                        isDestructive && hoveredItem == action.id
                            ? Color.dockWarning : Color.panelLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                hoveredItem == action.id
                    ? (isDestructive
                        ? Color.dockWarning.opacity(0.13) : Color.panelAccent.opacity(0.13))
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
        Text(presentation.hint)
            .font(.system(size: 10))
            .foregroundStyle(Color.panelLabelDim)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A tab's glyph: a symbol, or the mark at 13 points so it sits level with 15-point symbols.
    @ViewBuilder
    private func tabGlyph(_ glyph: PanelTabGlyph) -> some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .regular))
        case .brandMark:
            UttrflowMarkView(height: 13)
        }
    }

    // MARK: - Sheets

    /// The question on top of the list, dimming but not hiding the row it is about.
    @ViewBuilder
    private func sheetOverlay(_ sheet: PanelSheetPresentation) -> some View {
        ZStack {
            // Catches the click that would otherwise land on a row, and means what esc means.
            Color.black.opacity(0.45)
                .contentShape(.rect)
                .onTapGesture { relayKey(.escape) }

            VStack(alignment: .leading, spacing: 12) {
                Text(sheet.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelLabel)

                if sheet.takesTyping {
                    sheetField(sheet)
                }
                if !sheet.collections.isEmpty {
                    collectionList(sheet)
                }
                if !sheet.diff.isEmpty { diffView(sheet.diff) }
                if let conflict = sheet.conflict {
                    sheetNote(conflict, tint: Color.panelKey)
                }
                if let note = sheet.note {
                    sheetNote(note, tint: Color.panelLabelDim)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { relayKey(.escape) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.panelLabelSoft)
                    Button(sheet.confirmTitle) { relayKey(.return) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.panelAccentText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                sheet.isConfirmEnabled ? Color.panelAccent : Color.panelLine)
                        )
                        .disabled(!sheet.isConfirmEnabled)
                }
            }
            .padding(16)
            // A cap, not a width, so the sheet shrinks with a panel narrower than the design.
            .frame(maxWidth: QuickPanelMetrics.width - 56, alignment: .leading)
            .padding(.horizontal, 28)
            .background(Color.panelCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.panelLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
    }

    /// Bound to the presentation, not `@State`, so the field cannot disagree with its conflict note.
    private func sheetField(_ sheet: PanelSheetPresentation) -> some View {
        TextField(
            sheet.placeholder,
            text: Binding(get: { sheet.draft }, set: { relayKey(.draft($0)) })
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Color.panelLabel)
        .focused($isSheetFocused)
        .onKeyPress(.escape) { send(.escape) }
        // Both writes, in this order, in one update; see Docs/app-quick-panel.md on focus.
        .onAppear {
            isSearchFocused = false
            // On the next turn: a focus request made during `onAppear` is dropped silently.
            Task { isSheetFocused = true }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.panelSurface)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.panelAccent, lineWidth: 1)
        )
        .onSubmit { relayKey(.return) }
    }

    /// What the formatter wants to change, signed as well as coloured for colour-blind readers.
    private func diffView(_ lines: [TextDiff.Line]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Text(sign(for: line.kind))
                            .frame(width: 8, alignment: .leading)
                        Text(line.text.isEmpty ? " " : line.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(colour(for: line.kind))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(background(for: line.kind))
                }
            }
        }
        .frame(maxHeight: 150)
        .background(Color.panelSurface, in: .rect(cornerRadius: 6))
    }

    private func sign(for kind: TextDiff.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .same: " "
        }
    }

    private func colour(for kind: TextDiff.Kind) -> Color {
        switch kind {
        case .added: .panelAccentBright
        case .removed: .panelKey
        case .same: .panelLabelDim
        }
    }

    private func background(for kind: TextDiff.Kind) -> Color {
        switch kind {
        case .added: Color.panelAccent.opacity(0.12)
        case .removed: Color.panelKey.opacity(0.10)
        case .same: .clear
        }
    }

    /// G1 — the collections that exist, with how full each one is.
    private func collectionList(_ sheet: PanelSheetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sheet.collections) { option in
                Button {
                    relayKey(.draft(option.name))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.isCurrent ? "folder.fill" : "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(
                                option.isCurrent ? Color.panelAccentBright : Color.panelLabelDim)
                        Text(option.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.panelLabel)
                        Spacer()
                        Text("\(option.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.panelLabelDim)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(
                    option.name == sheet.draft
                        ? Color.panelCardHigh : Color.clear,
                    in: .rect(cornerRadius: 6))
            }
        }
        .frame(maxHeight: 132)
    }

    private func sheetNote(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The rule between the panel's bands.
    private var hairline: some View {
        Rectangle().fill(Color.panelLine).frame(height: 1)
    }

    // MARK: - Keys

    private func send(_ key: PanelKey) -> KeyPress.Result {
        relayKey(key)
        return .handled
    }

    /// Every ⌘-chord in one handler; two `onKeyPress(phases:)` on one view do not compose.
    private func commandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }
        if press.characters == "z" {
            onIntent(.undoDelete)
            return .handled
        }
        // ⌘⏎ pastes the words without the formatting: a modifier, not a mode.
        if press.key == .return {
            relayKey(.returnPlain)
            return .handled
        }
        return commandDigit(press)
    }

    /// ⌘1–⌘9 pick a collection; anything else still reaches the field.
    private func commandDigit(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command),
            let digit = Int(press.characters), (1...9).contains(digit)
        else { return .ignored }
        return send(.category(number: digit))
    }

    /// Sends a key to the controller, letting esc close an open menu before it closes the panel.
    private func relayKey(_ key: PanelKey) {
        if key == .escape, openMenu != nil {
            openMenu = nil
            return
        }
        if openMenu != nil { openMenu = nil }
        onKey(key)
    }

    private func perform(_ intent: PanelIntent) {
        // Anything the snapshot can answer goes through `intent.key`, so button and keystroke share a path.
        if let key = intent.key {
            relayKey(key)
            return
        }
        onIntent(intent)
    }

    private func tint(for kind: ClipKind) -> Color {
        switch kind {
        case .link: .panelLink
        case .code: .panelCode
        case .secret: .panelKey
        case .text, .colour, .image, .filePath: .panelLabelDim
        }
    }
}

// MARK: - Sizes

/// Claims right-clicks and ctrl-clicks in `hitTest` and lets every other click through to the row.
struct RightClickWatch: NSViewRepresentable {
    let clicked: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.clicked = clicked
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.clicked = clicked
    }

    final class Catcher: NSView {
        var clicked: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(convert(point, from: superview)),
                let event = NSApp.currentEvent
            else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return self
            case .leftMouseDown, .leftMouseUp:
                // A ctrl-click arrives as a left click carrying ⌃ and must open the menu too.
                return event.modifierFlags.contains(.control) ? self : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { clicked?() }

        /// Answers the ctrl-click claimed in `hitTest`; a claimed press that does nothing is a dead press.
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { clicked?() } else { super.mouseDown(with: event) }
        }
    }
}

/// Reports the pointer entering and leaving even while Uttrflow is not the active application.
struct PointerWatch: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> Tracker {
        let view = Tracker()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: Tracker, context: Context) {
        view.changed = changed
    }

    final class Tracker: NSView {
        var changed: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self))
        }

        override func mouseEntered(with event: NSEvent) { changed?(true) }
        override func mouseExited(with event: NSEvent) { changed?(false) }

        /// Nothing here answers a click; the row behind it does.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The measurements the approved design is drawn to.
enum QuickPanelMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 560
    static let corner: CGFloat = 16
    static let controlHeight: CGFloat = 34
    /// Every row the same height, so arrow-key counting stays right.
    static let rowHeight: CGFloat = 34
}

// MARK: - Colours

/// Darkens the row while the mouse is down; the click's only other feedback is the panel vanishing.
private struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

extension Color {
    /// The window's own greys; contrast ratios are in Docs/app-quick-panel.md.
    static let panelSurface = Color(rgb: 0x0B_0C10)
    static let panelCard = Color(rgb: 0x0E_1016)
    static let panelCardHigh = Color(rgb: 0x12_151C)
    static let panelLine = Color(rgb: 0x1E_212A)
    static let panelLabel = Color(rgb: 0xF4_F4F6)
    /// 7.4:1 on the panel.
    static let panelLabelSoft = Color(rgb: 0x8B_90A0)
    /// The dimmest grey in the design, for what the eye reaches only when it goes looking.
    static let panelLabelDim = Color(rgb: 0x56_5B68)
    /// Below the dimmest grey, for the row glyph and the ⋯; both lift to ordinary grey when looked at.
    static let panelGhost = Color(rgb: 0x3A_3F4A)
    /// Where you are: the focused field, the chosen row, the filter that is on, the current tab.
    static let panelAccent = Color(rgb: 0x29_C0B4)
    /// The accent as a foreground, 12.2:1 on the panel; `panelAccent` is mixed to sit under white text.
    static let panelAccentBright = Color(rgb: 0x5F_E0D3)
    /// Ink on a teal fill, where white measures 2.1:1.
    static let panelAccentText = Color(rgb: 0x04_332F)
    static let panelLink = Color(rgb: 0x6B_B4F5)
    static let panelCode = Color(rgb: 0xC4_9BF5)
    static let panelKey = Color(rgb: 0xF0_BE63)
}
