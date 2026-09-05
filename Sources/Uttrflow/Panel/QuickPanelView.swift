import UttrflowClipboard
import UttrflowUX
import SwiftUI

/// The quick panel: search, filters, the list, and the bars along the bottom.
///
/// Layout and nothing else. Which row the ring is on, which rows a chip leaves behind,
/// what a masked secret shows and which words go under an empty list are all decided in
/// `PanelPresenter`; every gesture leaves here as a `PanelKey` or a `PanelIntent` and is
/// answered by `PanelSnapshot.applying(_:)`. The view keeps exactly two pieces of state
/// of its own — what is in the search field, and which row the pointer is over — and
/// neither can change which clip Return means.
struct QuickPanelView: View {
    let presentation: PanelPresentation
    /// Keystrokes, and the clicks that are keystrokes said another way.
    var onKey: (PanelKey) -> Void = { _ in }
    /// A row's own actions. The ones the panel can answer itself arrive as keys instead.
    var onIntent: (PanelIntent) -> Void = { _ in }
    /// Bumped by the controller on every open, so the caret goes back to the search
    /// field for a panel that is built once and shown hundreds of times.
    var openCount: Int = 0

    @State private var query: String = ""
    @State private var hovered: UUID?
    /// C8 — whose ⋯ is open, and `nil` when none is.
    ///
    /// Held by the view rather than the snapshot, and that is a smaller claim than it
    /// looks: this is the *pointer's* way in, exactly as the six buttons it replaces were.
    /// Every action in it already has a key of its own that works on the selected row
    /// without the menu being open at all, so nothing here is the only route to anything.
    @State private var openMenu: UUID?
    /// Which item in the open menu the pointer is on. Its own state because SwiftUI's
    /// `onHover` does not fire while another application is frontmost, which this panel
    /// guarantees; see the note on the row's own `PointerWatch`.
    @State private var hoveredItem: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isSheetFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            chipRow
            list
            // Above the hint, because it is about what just happened rather than about
            // what the keys do, and the eye leaves the list downwards.
            if let scope = presentation.scope { microphoneStatus(scope) }
            if let status = presentation.microphone.status { microphoneStatus(status) }
            if let notice = presentation.notice { noticeBar(notice) }
            hint
            tabBar
        }
        // Fills whatever the window is, rather than fixing the design's size here. The
        // window opens at that size and the user may drag its border; a view that pinned
        // itself to 420×560 would leave the panel's corners empty and its list the same
        // length however far the border was pulled.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.panelSurface)
        .clipShape(.rect(cornerRadius: QuickPanelMetrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: QuickPanelMetrics.corner)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        )
        // Over the list rather than replacing it: every sheet is about one row, and the
        // row it is about should still be visible behind the question being asked.
        .overlay { if let sheet = presentation.sheet { sheetOverlay(sheet) } }
        .overlay(alignment: .topTrailing) { menuOverlay }
        // Both ways across a sheet, and the opening direction is the one that was
        // missing. Focusing the sheet is still the field's own job — this runs before
        // that field exists — but *unfocusing the search* is not something the field can
        // do, and until it happened the field's request landed nowhere.
        //
        // Two `@FocusState` bindings both asking for focus is not a contest the newer one
        // wins. The search field is the panel's first responder from the moment it opens
        // and stays it until told to let go, so `isSheetFocused = true` set a flag that
        // never became focus: the sheet sat showing its placeholder while every keystroke
        // went into the search box behind it, filtering the list the sheet was covering.
        // Silently — the user is looking at the field they think they are typing into.
        //
        // Measured, three seconds after the sheet opened, by typing nine characters and
        // finding all nine in the search field. There is a comment on the field below
        // saying this was fixed once already; it was moved, not fixed.
        .task(id: presentation.sheet == nil) {
            guard presentation.sheet == nil else { return }
            isSheetFocused = false
            isSearchFocused = true
        }
        // Not `onAppear`: the panel is built once and shown over and over, so the one
        // thing that must be true on every open has to watch something that changes.
        // The panel is built once and shown many times, so this state outlives a closing
        // — and an open menu that came back with the next ⇧⌘V would be sitting over a
        // freshly read list, naming a clip the user had chosen a minute ago and no longer
        // has in front of them. It cost an hour of testing: a stale menu looked exactly
        // like a right-click that had worked.
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
                    // Softened with the selected row, and for the same reason: with the
                    // row calmed down, a full-strength ring here made the empty search
                    // field the loudest thing on a panel whose answer to Return is a row
                    // further down.
                    .strokeBorder(
                        isSearchFocused ? Color.panelAccent.opacity(0.30) : Color.panelLine,
                        lineWidth: 1)
            )

            // It used to re-send the search it already had, under the label "Dictate a
            // search" — a control that looked like one and was not.
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

    /// The placeholder is drawn rather than handed to `TextField`, which offers no way
    /// to give it the measured grey the rest of the panel uses.
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
                // The whole contents, not the character typed: the field owns its own
                // selection, deletion and dictation, and what it now says is the only
                // thing about it worth reporting.
                .onChange(of: query) { _, text in relayKey(.search(text)) }
                // Held on the field, not on the panel: the field always has the caret,
                // and an arrow key an `NSTextField` has already swallowed never reaches
                // an ancestor.
                .onKeyPress(.upArrow) { send(.up) }
                .onKeyPress(.downArrow) { send(.down) }
                .onKeyPress(.return) { send(.return) }
                .onKeyPress(.escape) { send(.escape) }
                .onKeyPress(phases: .down) { commandKey($0) }
        }
    }

    // MARK: - Chips

    /// One row for both ways of narrowing the list: what kind of thing a clip is, and
    /// which collection it was filed in.
    ///
    /// They used to be two rows, and the second appeared the moment anything was filed
    /// anywhere — a whole line of a 420-point panel, permanently, for two chips. One row
    /// that scrolls when it runs out of width costs nothing until there is something to
    /// pay for, and gives the height back to the list.
    ///
    /// The divider is doing real work. These are two different questions — "images" and
    /// "work" narrow along axes that combine — and a run of chips with no break in it
    /// would read as one set where choosing one clears the others.
    ///
    /// The trailing control sits outside the scroller, so the way to the sort options
    /// does not scroll off the end of a long row of collections.
    /// The mark, before anything else on the row.
    ///
    /// The panel opens over another application and belongs to no window the user can
    /// see, so without it there is nothing on screen that says whose it is. Loaded from
    /// the bundle rather than drawn from the app icon: that one is the mark on its ink
    /// tile, which on this surface is a tile inside a tile.
    ///
    /// `nil` if it is ever missing — a build that lost the resource should be a panel
    /// with no mark, not a panel with a broken-image glyph where the mark goes.
    @ViewBuilder private var logo: some View {
        if let mark = Bundle.module.image(forResource: "uttrflow-logo") {
            // The resource is an alpha shape with no colour of its own, so the tint here
            // is what draws it — which is also what lets the panel pick a value that
            // holds against its own translucent backing.
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
                                // `chosen`, not `shortcut`: a chip past the ninth prints
                                // no number and must still work, and pressing the one
                                // already showing is how you get back to everything.
                                relayKey(.category(number: chip.chosen))
                            }
                            .id(chip.id)
                            // G5, G6 — on the chip itself, because that is the thing
                            // being renamed or deleted. All has no menu: there is no
                            // collection behind it to act on.
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
                // ⌘4 can choose a collection that is scrolled off the end, and a filter
                // that has visibly done nothing is indistinguishable from one that is
                // broken. The list underneath changes either way; this makes the chip
                // agree with it.
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

    /// One chip, in whichever accent it belongs to.
    ///
    /// `tint` rather than one accent for both rows of chips: a kind filter is where you
    /// are, and a collection is something you made, and the panel now says which is
    /// which in the same two colours the rest of the app uses for those two ideas.
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
            // 11 before. Both kinds of chip share one row now, and on a 420-point panel
            // a point either side of eight chips is a collection name's worth of width.
            .padding(.horizontal, 9)
            .frame(height: 26)
            // A wash rather than a fill. Filled, the one chip that is on was the
            // brightest thing on a panel whose brightest thing should be the clip you
            // are about to paste.
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
                    // Grouped while searching, flat while browsing — but one structure
                    // either way, which is not a tidiness point.
                    //
                    // These were two branches of an `if`, and a row kept its `.id(row.id)`
                    // across the switch between them. SwiftUI took that as the same view
                    // moving and left its rendering alone: after a search narrowed the
                    // list, the row Return would paste was drawn exactly as it had been
                    // drawn a moment earlier in the flat list — unringed, unfilled — while
                    // the presentation said, correctly, that it was selected. The panel
                    // was lying about what Return meant on the one screen where the reader
                    // most needs to be told.
                    ForEach(sections) { section in
                        if let title = section.title { groupHeading(title) }
                        ForEach(section.rows) { row in
                            // Keyed by the run it is drawn in as well as by the clip.
                            // An explicit id is a promise to SwiftUI that this is the
                            // same view as before, and a row that keeps its id while
                            // moving from the flat list into a heading is a promise the
                            // panel cannot keep: the old rendering stays, so the ring
                            // never arrives on the row Return would paste.
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
            // The whole promise is three keystrokes, and a selection that has scrolled
            // out of sight makes the third one a bet. `anchor: nil` moves the list by
            // the least it can, so a row already on screen never jumps.
            .onChange(of: presentation.selectedRow?.id) { _, _ in
                guard let selection = selectedKey else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(selection, anchor: nil)
                }
            }
        }
    }

    /// Where the ring is, in the same key the rows are drawn under, so the list can be
    /// scrolled to it.
    private var selectedKey: String? {
        for section in sections {
            if let row = section.rows.first(where: \.isSelected) { return section.key(for: row) }
        }
        return nil
    }

    /// The list as it is drawn: one unnamed run while browsing, one run per heading
    /// while searching.
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
            // H3 — a way forward, where there is one. Outside the combined accessibility
            // element above, so a screen reader reaches it as the button it is rather
            // than as one more clause of the sentence.
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

    /// I6, I7 — why the microphone is dimmed. A disabled control with no reason beside it
    /// is one people press twice and then stop trusting.
    private func microphoneStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Color.panelLabelDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    /// B3–B5 — what the panel says when it could only copy.
    ///
    /// Not styled as an error. The words are on the clipboard either way, so what happened
    /// is that the paste became a manual one, and dressing that in red would send people
    /// looking for a problem that is not there.
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

    /// H6 — said rather than left off the end. A capped list that does not admit it is a
    /// list the user reads as complete.
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
            // B6 — the same row, minus the formatting, when ⌘ is down. Read at the
            // moment of the click rather than tracked as state: a modifier held and
            // released between the press and the handler is not a mode.
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
                        // Sized to its content rather than greedy. This and the summary
                        // below both asked for all the width, so a picture row split it
                        // in two and truncated "1000 × 700 · 133 KB" to "1000 × 7…" —
                        // half the row spent on a summary that is empty, because a
                        // picture has no text. Seen on screen; the code read as correct.
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
                    // C6 — the whole line after a delay, which is what a tooltip is for.
                    // Whether there is one to show is the presentation's answer, not a
                    // condition written here; see `PanelRow.tooltip`.
                    .help(row.tooltip ?? "")
                trailing(row, showsActions: look.showsActions)
            }
            // Tighter on the leading edge than the trailing one: the glyph belongs in the
            // gutter beside the list rather than in the column of words, and the ⋯ wants
            // the room on the right.
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .frame(height: QuickPanelMetrics.rowHeight)
            .background(
                look.isSelected
                    // A wash of the accent under the ring. It is what lets the ring be
                    // faint: together they say "this one" at a glance, where the ring
                    // alone had to shout to be seen at all.
                    ? AnyShapeStyle(Color.panelAccent.opacity(0.08))
                    : AnyShapeStyle(look.isFilled ? Color.panelCardHigh : .clear),
                in: .rect(cornerRadius: 8)
            )
            // A ring, not a brighter fill: hover fills too, and the two can land on
            // different rows while only one of them answers Return.
            //
            // A hairline at a third strength rather than a full-weight line in the accent
            // itself. At 1.5 points and full strength it was the loudest thing on the
            // panel — brighter than the clip it was pointing at, which is the one thing
            // the panel is for.
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
        // C8 — the second way in, and the same menu. `.contextMenu` used to be here, and
        // it handed the job to an `NSMenu`: the system's grey, the system's metrics, no
        // icons. Two ways in drawn two different ways is worse than either of them alone,
        // because the one the user meets second looks like a different application.
        //
        // An overlay, not a background, and that is the whole of why it did nothing at
        // all. Behind the row it was never asked: the row is a `Button`, the button's own
        // view is in front, and hit testing stops at the first view that claims the point.
        // The right-click reached the button instead, which has no answer for one — so the
        // row simply latched into its pressed shade and stayed there. In front, the
        // catcher is asked first and answers `nil` for every button but the right one, so
        // the left click that pastes a clip still goes straight through to the row.
        .overlay(
            RightClickWatch { openMenu = row.id }
        )
        // `.onHover` would be the obvious thing, and it does not work here: SwiftUI's
        // hover only reports while the *application* is active, and this panel is never
        // the active application — that is the whole point of it. So the rows under the
        // pointer stayed cold, while a row that had been hovered during some moment of
        // activity kept its buttons for ever, because the matching exit never arrived.
        // Two rows looking hovered at once is what it looks like from outside.
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
            // The same actions the pointer gets, spoken. The buttons that appear under
            // the pointer are hidden from VoiceOver because these say the same thing
            // and do not require one.
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
            // Smaller, dimmer and narrower than it was — 13 pt at full tint in a 22 pt
            // column. On a list where four rows in five are ordinary text that glyph is
            // the same drawing over and over: not a category the eye reads but a texture
            // it has to cross to reach the words. It earns its place only on the rows
            // where it differs, so it is drawn at the weight of something you find rather
            // than something you are shown.
            glyph
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(colour.opacity(0.62))
                .frame(width: 17)
        }
    }

    /// K4 — the picture itself, small.
    ///
    /// Loaded from the file rather than carried through the presentation: a screenshot is
    /// megabytes and the presentation is rebuilt on every keystroke, so passing the bytes
    /// through it would copy them on each one. `NSImage(contentsOf:)` answers `nil` for a
    /// file that has gone, which is the same answer B8 already draws a row for.
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

    /// D1 — drawn only when the detector was confident. Quieter than the alias chip
    /// beside it: an alias is something the user chose and typed, a language is something
    /// the app worked out, and the two should not carry the same weight on one row.
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

    /// The right-hand end of a row: the time it was copied, or — under the pointer — the
    /// buttons for it. The ⋯ sits outside that swap, and has to.
    ///
    /// It used to live in the not-hovered branch, last. Moving the pointer onto it turned
    /// the row hovered, which replaced that branch with the buttons, whose last one is
    /// Delete — so the pixels the user aimed at became Delete before the click landed.
    /// Two consequences, both real: the menu could not be opened with a mouse at all, and
    /// aiming at it deleted the clip. It cost a clipping while this was being tested.
    ///
    /// Anchoring it here means the far right of a row is the same control whatever the
    /// pointer is doing, and the buttons grow into the space the timestamp gives up.
    @ViewBuilder private func trailing(_ row: PanelRow, showsActions: Bool) -> some View {
        HStack(spacing: 6) {
            // A pin is state, not furniture: it says something about this clip that
            // nothing else on the row says. Everything that was merely *about* the row
            // rather than *in* it has gone.
            //
            // The timestamp went first. It read "1 day ago" on eleven consecutive rows —
            // a column repeating itself down the panel, answering a question nobody asks
            // while scanning. It is still there, at the top of the menu, where it is being
            // asked about one clip.
            //
            // The six buttons went with it. They appeared only under the pointer, so a row
            // changed shape as the mouse crossed it and its own words were pushed aside to
            // make room; a row you have merely arrowed onto should not rearrange itself.
            // Everything they offered is behind the ⋯ that was already sitting beside them.
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
                    // Below the dimmest grey in the design at rest, and ordinary on the
                    // row being looked at. A control that should be findable rather than
                    // noticeable: sixteen of them at full strength is sixteen marks
                    // competing with sixteen phrases.
                    .foregroundStyle(colourOfDots(for: row, showsActions: showsActions))
                    .frame(width: 20, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The row already speaks every one of these through its accessibility
            // actions, so a second spoken way in would be a duplicate, not a help.
            .accessibilityHidden(true)
        }
        .fixedSize()
    }

    private func colourOfDots(for row: PanelRow, showsActions: Bool) -> Color {
        if openMenu == row.id { return .panelAccentBright }
        if showsActions || row.isSelected { return .panelLabelSoft }
        return .panelGhost
    }

    /// The open ⋯ menu, and the click-away that closes it.
    ///
    /// Anchored to the panel's trailing edge below the chips rather than to the row whose
    /// ⋯ was pressed, and that is a deliberate retreat from the drawing. A menu pinned to
    /// a row inside a scroll view is clipped by it near the bottom of the list, so it
    /// would need to know how much room is left and flip — which is placement arithmetic,
    /// and placement is what has already gone wrong twice in this panel: once under the
    /// menu bar and once off the side of the screen. Always in the same place is worth
    /// more here than attached to the thing it acts on, because the header names the clip
    /// so there is never a question of which one it means.
    @ViewBuilder private var menuOverlay: some View {
        if let id = openMenu, let row = presentation.rows.first(where: { $0.id == id }) {
            ZStack(alignment: .topTrailing) {
                // Catches the click that would otherwise land on a row behind the menu.
                // Not dimmed, unlike a sheet: a sheet asks a question and wants the list
                // out of the way, where this is a menu and the list is the context.
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

    /// C8 — the menu the ⋯ opens, drawn rather than handed to AppKit.
    ///
    /// `Menu` gave us an `NSMenu`, and an `NSMenu` is the system's surface: the system's
    /// grey, the system's corner radius, the system's row height, and no icons at all
    /// unless each item is built as an image. Every other pixel of this panel refuses that
    /// look — the chips, the sheets, the tab bar are all drawn here — so the one control
    /// that reached for it was the one place the panel stopped being itself.
    ///
    /// The header is where the row's timestamp went. Taking it off sixteen rows and
    /// putting it on the one clip being asked about is the whole trade, and it only works
    /// because it lands here.
    ///
    /// Delete carries no red, because the palette has four values and adding a fifth for
    /// this was tried once and reverted. It takes the warning orange under the pointer
    /// instead — colour at the moment it means something, rather than a permanent stripe
    /// that has to be ignored every time the menu is opened for any other reason.
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
        // Delete is always the last thing the presenter offers, and it is the only one
        // separated from what is above it. The rule is doing the work a colour would
        // otherwise have to: it says "not one of the others" without shouting it.
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
                    // Delete reads at the same weight as everything else until the pointer
                    // is on it. Dimming it at rest was meant as caution and looked like
                    // the opposite — a greyed word in a menu is the universal drawing of
                    // an action you cannot take, so the one item that must be understood
                    // was the one that looked unavailable.
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

    /// The bottom bar. Every button in it does something.
    ///
    /// It used to draw four, three of them disabled and the fourth wired to an empty
    /// closure — so all four were decoration, in the most reachable strip of the panel.
    /// What each one means is the presenter's to decide; this draws what it is given.
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

    /// A tab's glyph, which is a symbol for three of them and the mark itself for
    /// Uttrflow's own.
    ///
    /// Sized to sit level with the symbols rather than to match them numerically: the
    /// mark is a stroked letterform with no optical padding, where SF Symbols carry
    /// their own, so a 15-point mark beside 15-point symbols reads as the larger one.
    /// Neither takes a colour here — the bar tints them both.
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

    /// The question on top of the list, dimming what is behind it without hiding the row
    /// the question is about.
    @ViewBuilder
    private func sheetOverlay(_ sheet: PanelSheetPresentation) -> some View {
        ZStack {
            // Catches the click that would otherwise land on a row behind the sheet, and
            // means what esc means.
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
            // A cap rather than a width: the sheet is a question about one row and has no
            // reason to grow with the panel, but it must shrink with it — fixed, it was
            // clipped by both borders the moment the panel was narrower than the design.
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

    /// Bound to the presentation rather than to `@State`, so what is on screen is what
    /// the model will act on. A field with its own copy is a field that can disagree with
    /// the conflict message printed under it.
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
        // Both halves, here, in this order, and the order is the whole fix.
        //
        // Two `@FocusState` bindings both wanting focus is not a contest the newer one
        // wins: the search field is the panel's first responder from the moment it opens
        // and keeps it until something lets go. So `isSheetFocused = true` on its own set
        // a flag that never became focus, and every keystroke went into the search box
        // behind the sheet — silently, while the user watched the field they thought they
        // were typing into show its placeholder. Measured three seconds after opening, by
        // typing nine characters and finding all nine in the search field.
        //
        // Releasing the search from the panel above did not fix it either; it only moved
        // the failure, because that release lands *after* this field has appeared and
        // takes the field's focus down with it. The keystrokes then went nowhere at all,
        // which is worse — at least the search box was somewhere the text could be seen.
        // Both writes have to happen here, in one update, with the claim last.
        .onAppear {
            isSearchFocused = false
            // On the *next* turn, not this one. `onAppear` runs while SwiftUI is still
            // assembling the update that puts this field on screen, and a focus request
            // made then is applied against a responder chain the field is not yet in — so
            // it is dropped, silently, exactly as if it had never been made.
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

    /// D6 — what the formatter wants to change, and only that.
    ///
    /// Additions and removals are told apart by a leading sign as well as by colour: a
    /// diff that only uses colour is unreadable to anyone who cannot separate red from
    /// green, and this is a decision they are being asked to make.
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

    /// Every ⌘-chord the panel answers, in one handler.
    ///
    /// One and not two: a second `onKeyPress(phases:)` on the same view does not reliably
    /// compose with the first, and the one that loses simply never fires — silently, with
    /// both still in the source looking correct.
    private func commandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }
        if press.characters == "z" {
            onIntent(.undoDelete)
            return .handled
        }
        // B6 — ⌘⏎ pastes the words without the formatting. A modifier rather than a mode,
        // because for a note the user knows which of the two they want and the app cannot.
        if press.key == .return {
            relayKey(.returnPlain)
            return .handled
        }
        return commandDigit(press)
    }

    /// ⌘1–⌘9, which pick a collection. Anything else is left alone so that it still
    /// reaches the field the user was typing in.
    private func commandDigit(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command),
            let digit = Int(press.characters), (1...9).contains(digit)
        else { return .ignored }
        return send(.category(number: digit))
    }

    /// A row action the panel can answer itself is sent as the key it is, so that a
    /// button and a keystroke provably take one path.
    /// `esc` belongs to the open menu before it belongs to the panel.
    ///
    /// The same rule a sheet already follows, and for the same reason: closing the whole
    /// panel because somebody backed out of a menu would throw away the list they were
    /// working through, and there is no way back to where they were.
    private func relayKey(_ key: PanelKey) {
        if key == .escape, openMenu != nil {
            openMenu = nil
            return
        }
        if openMenu != nil { openMenu = nil }
        onKey(key)
    }

    private func perform(_ intent: PanelIntent) {
        // Anything the snapshot can answer goes through `intent.key` rather than through
        // a second mapping written here — a second mapping is a second thing to keep in
        // step, and the day they part is the day a button and a keystroke disagree.
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

/// Reports a right-click, and lets every other click through untouched.
///
/// SwiftUI offers `.contextMenu` and nothing else, and `.contextMenu` means an `NSMenu` —
/// which is the one surface in this panel we are not willing to let the system draw. So
/// the click is caught here and the panel opens its own menu.
///
/// The trick is in ``Catcher/hitTest(_:)``. A view that claimed every click would swallow
/// the left one that pastes a clip — the whole product — so it asks what is being
/// delivered *right now* and claims only the right button, or a ctrl-click, which macOS
/// reports as a left-down with a modifier. Everything else answers `nil` and falls through
/// to the row behind, exactly as ``PointerWatch`` does.
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
                // A Mac with one button, or a trackpad without the gesture enabled. The
                // system does not translate this for us; it arrives as an ordinary left
                // click carrying ⌃, and a menu that ignored it would be unreachable for
                // anyone who works that way.
                return event.modifierFlags.contains(.control) ? self : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { clicked?() }

        /// The ctrl-click arm above, followed through: having claimed the click we have
        /// to answer it, or it is a press that does nothing at all.
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { clicked?() } else { super.mouseDown(with: event) }
        }
    }
}

/// Reports the pointer entering and leaving, whether or not Uttrflow is the active
/// application.
///
/// `.onHover` cannot do this. Its tracking is active-application-only, and the quick
/// panel deliberately never activates its application: the insertion path declines while
/// Uttrflow is frontmost, so a panel that activated could not paste anywhere. The result
/// was hover that worked only in the moments after the main window had been in front,
/// and stale hover the rest of the time — a row keeping its buttons because the pointer
/// left during a spell when nothing was listening.
///
/// `.activeAlways` is the one line that matters here. `.inVisibleRect` keeps the tracked
/// area in step with a row that scrolls, which is otherwise a second thing to maintain.
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
    /// Every row the same height, because the list is scanned with the arrow keys and
    /// rows that varied would make the count in the user's head wrong.
    static let rowHeight: CGFloat = 34
}

// MARK: - Colours

/// The approved palette, measured rather than chosen: the two greys below carry the
/// contrast ratio they were checked at, because a dimmer pair had already failed.
/// C5 — the row darkens while the mouse is down on it.
///
/// `.plain` gives no feedback at all, and this row's whole job is to close the panel: with
/// nothing between the click and the disappearance, a click that did land and a click that
/// missed look identical, and the second is indistinguishable from the app ignoring you.
private struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

extension Color {
    /// The window's own greys, so the panel sits on the same black as the app it belongs
    /// to. Every value here is the one the artboards are drawn on; the two greys below
    /// still carry the contrast ratio they were checked at.
    static let panelSurface = Color(rgb: 0x0B_0C10)
    static let panelCard = Color(rgb: 0x0E_1016)
    static let panelCardHigh = Color(rgb: 0x12_151C)
    static let panelLine = Color(rgb: 0x1E_212A)
    static let panelLabel = Color(rgb: 0xF4_F4F6)
    /// 7.4:1 on the panel.
    static let panelLabelSoft = Color(rgb: 0x8B_90A0)
    /// The dimmest grey in the design: times, shortcuts, and anything the eye should
    /// reach only when it goes looking.
    static let panelLabelDim = Color(rgb: 0x56_5B68)
    /// Where you are: the focused field, the chosen row, the filter that is on, the tab
    /// you are looking at. The mark's own teal, which the window uses for anything live.
    /// Below the dimmest grey in the design, for two marks that should be found rather
    /// than read: the glyph at the head of a row, and the ⋯ at the end of one.
    ///
    /// It sits under the contrast the rest of the panel holds to, and that is defensible
    /// only because neither mark is ever the only signal — the words are the row, and both
    /// of these lift to an ordinary grey on the row being looked at.
    static let panelGhost = Color(rgb: 0x3A_3F4A)
    static let panelAccent = Color(rgb: 0x29_C0B4)
    /// The accent when it is a foreground rather than a fill: an inline action, a pin, an
    /// added word, the mark. 12.2:1 on the panel, where `panelAccent` is mixed to sit
    /// *under* white text and so reads dull as a foreground.
    ///
    /// A lighter weight of the one accent, not a second hue. It was purple while the
    /// brand was purple; when the brand moved it briefly became warm, which put a
    /// decorative colour a shade away from `dockWarning` and gave the identity a fifth
    /// value it never had.
    static let panelAccentBright = Color(rgb: 0x5F_E0D3)
    /// Ink on a teal fill. White measures 2.1:1 there; this is the same deep teal the
    /// window puts under its own accent buttons.
    static let panelAccentText = Color(rgb: 0x04_332F)
    static let panelLink = Color(rgb: 0x6B_B4F5)
    static let panelCode = Color(rgb: 0xC4_9BF5)
    static let panelKey = Color(rgb: 0xF0_BE63)
}
