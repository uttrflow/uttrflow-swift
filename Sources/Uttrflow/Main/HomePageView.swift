// The Home page: the greeting, the hero, the stat tiles and the recent-activity rail.

import UttrflowUX
import SwiftUI

/// The page the window opens on: top bar, hero, four stat tiles, then the last few dictations; before any, one centred invitation.
struct HomePageView: View {
    let presentation: HomePresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        if presentation.emptyState != nil {
            HomePageContent(presentation: presentation, onIntent: onIntent)
        } else {
            ScrollView {
                HomePageContent(presentation: presentation, onIntent: onIntent)
            }
            // No scroller gutter, as on the other redesigned pages, so the right margin matches the left.
            .scrollIndicators(.never)
        }
    }
}

/// Home's content, top to bottom, without the scroll view that holds it.
struct HomePageContent: View {
    let presentation: HomePresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar
            if let empty = presentation.emptyState {
                MainEmptyStateView(state: empty, onIntent: onIntent)
            } else {
                HomeHeroCard(hero: presentation.hero, mood: presentation.mood, onIntent: onIntent)
                if let step = presentation.nextStep {
                    MainCard { MainEmptyStateView(state: step, onIntent: onIntent) }
                }
                Group {
                    if !presentation.tiles.isEmpty {
                        tiles
                    }
                    HomeActivityCard(presentation: presentation, onIntent: onIntent)
                }
                // Held in place but unseen until the history is read, then faded in without moving anything.
                .opacity(presentation.isReading ? 0 : 1)
                .allowsHitTesting(!presentation.isReading)
                .accessibilityHidden(presentation.isReading)
                .animation(
                    MotionBudget.current().allowing(.easeOut(duration: 0.2)), value: presentation.isReading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 22)
        .frame(
            maxWidth: .infinity, maxHeight: presentation.emptyState == nil ? nil : .infinity,
            alignment: .topLeading)
    }

    /// The date, and the greeting for the time of day.
    private var topBar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.dateLine)
                    .font(.system(size: 13))
                    .foregroundStyle(PagePalette.quiet)
                Text(presentation.greeting)
                    .font(BrandFont.headline(size: 30))
                    .tracking(-0.9)
                    .foregroundStyle(PagePalette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HomeSearchField(
                action: presentation.search, isEnabled: presentation.canSearch, onIntent: onIntent)
        }
    }

    /// Four across where they fit, two to a row where they do not, decided in layout so the first frame is already right.
    private var tiles: some View {
        HomeTileGrid {
            ForEach(presentation.tiles) { HomeStatTileView(tile: $0) }
        }
    }
}

/// Lays the stat tiles out four across or two to a row from the width it is offered, with no second pass.
struct HomeTileGrid: Layout {
    /// The gap between tiles, across and down.
    static let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? HomeStatTileView.narrowest * 4 + Self.spacing * 3
        let rows = Self.rows(count: subviews.count, width: width)
        let height =
            rows == 0 ? 0 : CGFloat(rows) * HomeStatTileView.height + CGFloat(rows - 1) * Self.spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = HomeStatTileView.columns(forWidth: bounds.width)
        let width = max(0, (bounds.width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns))
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index % columns) * (width + Self.spacing)
            let y = bounds.minY + CGFloat(index / columns) * (HomeStatTileView.height + Self.spacing)
            subview.place(
                at: CGPoint(x: x, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: HomeStatTileView.height))
        }
    }

    /// How many rows `count` tiles take at `width`.
    static func rows(count: Int, width: CGFloat) -> Int {
        let columns = HomeStatTileView.columns(forWidth: width)
        return (count + columns - 1) / columns
    }
}

/// The search field in the top bar: a button that looks like a field and opens History's search, also on ⌘K.
struct HomeSearchField: View {
    let action: MainAction
    /// False while History is empty and has no search field to open; the words are then quieter and the field inert.
    var isEnabled = true
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Button {
            onIntent(action.intent)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.symbolName ?? "magnifyingglass")
                    .font(.system(size: 14))
                Text(action.title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("⌘ K")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PagePalette.text.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PagePalette.text.opacity(0.1), in: .rect(cornerRadius: 6))
            }
            .foregroundStyle(PagePalette.text.opacity(isEnabled ? 0.5 : 0.4))
            .padding(.horizontal, 14)
            .frame(width: 300, height: 40)
            .background(PagePalette.text.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PagePalette.text.opacity(0.12), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .disabled(!isEnabled)
        .help(isEnabled ? "" : Self.nothingToSearch)
        .accessibilityLabel(action.title)
    }

    /// Why the field is dimmed while there is no history.
    static let nothingToSearch = "Nothing to search yet. Your dictations appear here once you have some."

}

/// One figure with its icon disc and goal ring, washed in its accent.
struct HomeStatTileView: View {
    let tile: HomeStatTile

    /// The narrowest a tile is drawn in a row of four before the row breaks into two.
    nonisolated static let narrowest: CGFloat = 180
    /// Every tile's height.
    nonisolated static let height: CGFloat = 74

    /// Four columns where four tiles fit at their narrowest, two otherwise.
    nonisolated static func columns(forWidth width: CGFloat) -> Int {
        width >= narrowest * 4 + 36 ? 4 : 2
    }

    var body: some View {
        let accent = Self.accent(for: tile.kind)
        HStack(spacing: 14) {
            Image(systemName: Self.symbol(for: tile.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.22), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.value)
                    .font(BrandFont.display(size: 21, weight: .semibold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(PagePalette.text)
                    .lineLimit(1)
                Text(tile.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(PagePalette.text.opacity(0.62))
                    .lineLimit(1)
            }
            // Free to run under the ring, as the design lets a long label do.
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .trailing) {
            ring(accent).padding(.trailing, 16)
        }
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.16), PagePalette.text.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
    }

    /// The goal ring, filled clockwise from the top.
    private func ring(_ accent: Color) -> some View {
        ZStack {
            Circle().stroke(PagePalette.ringTrack, lineWidth: 4)
            Circle()
                .trim(from: 0, to: tile.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
        .padding(5)
    }

    static func accent(for kind: HomeStatKind) -> Color {
        switch kind {
        case .wordsToday: PagePalette.dictation
        case .streak: PagePalette.clipboard
        case .pace: PagePalette.suggestion
        case .leftAsDictated: PagePalette.info
        }
    }

    static func symbol(for kind: HomeStatKind) -> String {
        switch kind {
        case .wordsToday: "doc.text"
        case .streak: "flame.fill"
        case .pace: "bolt.fill"
        case .leftAsDictated: "target"
        }
    }
}
