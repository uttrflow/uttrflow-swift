// The History page: the header and search, four stat tiles, then every dictation on a time rail by day.

import UttrflowUX
import SwiftUI

/// The history page: the header over an aurora glow, the tiles, the days on the rail, and the retention sentence.
struct HistoryPageView: View {
    let presentation: HistoryPresentation
    let chrome: MainPageChrome
    @Binding var query: String
    /// Rises when Find is chosen; handed on to the search field, which is what takes the focus.
    var searchFocusRequest = 0
    var onIntent: (MainIntent) -> Void = { _ in }
    var onSearch: (String) -> Void = { _ in }

    /// The width the tiles are given, which decides how many share a row.
    @State private var tilesWidth: CGFloat = 0

    var body: some View {
        // Only with no search field, so typing a query that matches nothing never rebuilds the field.
        if presentation.isReading || (presentation.emptyState != nil && !presentation.showsSearch) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let empty = presentation.emptyState {
                    MainEmptyStateView(state: empty, onIntent: onIntent)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .top) { aurora }
        } else {
            list
        }
    }

    /// The days on the rail, scrolled, with the retention sentence under the last.
    private var list: some View {
        ScrollView {
            // Lazy, because a search rebuilds a thousand rows per keystroke.
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if !presentation.tiles.isEmpty {
                    tiles.padding(.top, 10)
                }
                if let empty = presentation.emptyState {
                    MainCard { MainEmptyStateView(state: empty, onIntent: onIntent) }
                        .padding(.top, 18)
                }
                ForEach(presentation.days) { day in
                    dayHeader(day)
                    ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                        HistoryRailRow(
                            row: row, index: index, count: day.rows.count, onIntent: onIntent)
                    }
                }
                Text(presentation.retentionNotice.sentence)
                    .font(.system(size: 12))
                    .foregroundStyle(PagePalette.quiet)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) { aurora }
        }
    }

    /// The aurora's soft glow rising behind the header, a picture blurred once so scrolling never re-blurs it.
    @ViewBuilder private var aurora: some View {
        if let picture = HistoryGlow.aurora {
            let spill = HistoryGlow.spill(70)
            Image(nsImage: picture)
                .resizable()
                .frame(height: 220 + spill * 2)
                .padding(.horizontal, -60 - spill)
                .opacity(0.4)
                .offset(y: -120 - spill)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// "History" beside the search field, then the caption with the way to the privacy settings.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text(chrome.title)
                    .font(BrandFont.display(size: 28, weight: .semibold))
                    .tracking(-0.84)
                    .foregroundStyle(PagePalette.text)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                if let search = chrome.search {
                    HistorySearchField(
                        placeholder: search.placeholder, query: $query,
                        focusRequest: searchFocusRequest, onSearch: onSearch)
                }
            }
            .frame(minHeight: 38)
            caption
        }
        .padding(.bottom, 6)
    }

    /// The link keeps its full width and its own name; the text before it truncates first.
    private var caption: some View {
        let notice = presentation.retentionNotice
        return HStack(spacing: 0) {
            Text(
                [chrome.caption, notice.phrase].compactMap(\.self).filter { !$0.isEmpty }
                    .joined(separator: " · ")
            )
            .foregroundStyle(PagePalette.quiet)
            Text(" · ")
                .foregroundStyle(PagePalette.quiet)
                .accessibilityHidden(true)
                .fixedSize()
            Button(notice.link.title) {
                onIntent(notice.link.intent)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PagePalette.dictation)
            .fixedSize()
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }

    /// Four across where they fit, two to a row where they do not.
    private var tiles: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: HistoryStatTile.columns(forWidth: tilesWidth)),
            spacing: 10
        ) {
            ForEach(presentation.tiles) { HistoryStatTile(tile: $0) }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { tilesWidth = $0 }
    }

    /// "Today" with "4 dictations · 1,284 words" beside it.
    private func dayHeader(_ day: HistoryDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(day.title)
                .font(BrandFont.display(size: 15, weight: .semibold))
                .foregroundStyle(PagePalette.text)
                .accessibilityAddTraits(.isHeader)
            Text(day.summary)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.quiet)
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

/// The search field beside the title, which reports what was typed and decides nothing.
struct HistorySearchField: View {
    let placeholder: String
    @Binding var query: String
    var focusRequest = 0
    var onSearch: (String) -> Void

    @FocusState private var isFocused: Bool
    /// What is selected in the field, held so Find can select the whole query rather than only reach it.
    @State private var selection: TextSelection?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(PagePalette.quiet)
            TextField(placeholder, text: $query, selection: $selection)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.text)
                .focused($isFocused)
                .onChange(of: query) { _, new in onSearch(new) }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(PagePalette.text.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(PagePalette.text.opacity(0.1), lineWidth: 1)
        }
        .onChange(of: focusRequest) { _, _ in
            isFocused = true
            selection = TextSelection(range: query.startIndex..<query.endIndex)
        }
        // Escape empties a field with something in it, and is left alone when there is nothing to clear.
        .onKeyPress(.escape) {
            guard !query.isEmpty else { return .ignored }
            query = ""
            onSearch("")
            return .handled
        }
    }
}

/// One figure with its icon square and a glow of its accent in the corner.
struct HistoryStatTile: View {
    let tile: HomeStatTile

    /// Four columns where four tiles fit at 150 points each, two otherwise.
    static func columns(forWidth width: CGFloat) -> Int {
        width >= 150 * 4 + 30 ? 4 : 2
    }

    var body: some View {
        let accent = HomeStatTileView.accent(for: tile.kind)
        HStack(spacing: 10) {
            Image(systemName: HomeStatTileView.symbol(for: tile.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.18), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(tile.value)
                    .font(BrandFont.display(size: 22, weight: .semibold))
                    .tracking(-0.44)
                    .monospacedDigit()
                    .foregroundStyle(PagePalette.text)
                Text(tile.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.quiet)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(alignment: .topTrailing) {
            if let disc = HistoryGlow.disc {
                let spill = HistoryGlow.spill(34)
                Image(nsImage: disc)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(accent)
                    .frame(width: 90 + spill * 2, height: 90 + spill * 2)
                    .opacity(0.3)
                    .offset(x: 24 + spill, y: -24 - spill)
            }
        }
        .background(PagePalette.text.opacity(0.045))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PagePalette.text.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
    }
}
