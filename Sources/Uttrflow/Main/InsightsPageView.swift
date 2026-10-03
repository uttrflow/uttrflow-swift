// The Insights page: a calendar shaded by how much was said each day, a range switch, and four figures.

import UttrflowUX
import SwiftUI

/// The calendar beside its figures, under a header that carries the range switch.
struct InsightsPageView: View {
    let presentation: InsightsPresentation
    var onIntent: (MainIntent) -> Void
    var onScope: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let empty = presentation.emptyState {
                        MainEmptyStateView(state: empty, onIntent: onIntent)
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            if let calendar = presentation.calendar {
                                InsightsCalendarCard(calendar: calendar, caption: presentation.chartCaption)
                            }
                            VStack(spacing: 12) {
                                ForEach(presentation.figures) { InsightsFigureTile(figure: $0) }
                            }
                            .frame(width: 220)
                        }
                    }
                    if let figures = presentation.suggestionFigures {
                        InsightsSuggestionsCard(figures: figures)
                    }
                }
                .padding(.bottom, 22)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The title with the range switch beside it, and the caption beneath.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(presentation.chrome.title)
                    .font(BrandFont.display(size: 28, weight: .semibold))
                    .tracking(-0.84)
                    .foregroundStyle(PagePalette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if !presentation.ranges.isEmpty {
                    InsightsRangeSwitch(options: presentation.ranges, onPick: onScope)
                }
            }
            if let caption = presentation.chrome.caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(PagePalette.quiet)
            }
        }
        .padding(.bottom, 18)
    }
}

/// The suggestion corpus counts, kept together so their limits are visible.
struct InsightsSuggestionsCard: View {
    let figures: [MainStatistic]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PagePalette.text)
            Text("Stored corpus totals on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(PagePalette.quiet)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(figures) { InsightsFigureTile(figure: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// The calendar's colours: one teal in both appearances, shaded by opacity, over the page's own ink.
private enum InsightsPalette {
    private typealias R = BrandPalette.Redesign

    /// The teal every spoken-on tile is a shade of.
    static let heat = Color(rgb: R.dictationAccent.dark)
    /// The day number on a tile bright enough to need it.
    static let deepInk = Color(rgb: R.calendarDeepInk)
    /// A card's film and hairline, a wash of the page's ink.
    static let cardFill = PagePalette.text.opacity(0.045)
    static let cardEdge = PagePalette.text.opacity(0.08)
    /// A day with nothing said.
    static let bareTile = PagePalette.text.opacity(0.05)
}

/// Three segments; the picked one is filled, one beyond what is kept is dimmed and says why.
struct InsightsRangeSwitch: View {
    let options: [InsightsRangeOption]
    var onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    onPick(option.id)
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: option.isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            option.isSelected ? Color.redesignWindow : PagePalette.text.opacity(0.65)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if option.isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PagePalette.text)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!option.isAvailable)
                .opacity(option.isAvailable ? 1 : 0.4)
                .help(option.unavailableReason ?? "")
                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            PagePalette.text.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

/// The range as weeks of tiles, a legend from less to more above them.
struct InsightsCalendarCard: View {
    let calendar: InsightsCalendar
    let caption: String?

    /// Past this many weeks a square tile would push the grid off the window, so tiles flatten.
    private static let squareWeeks = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((caption ?? calendar.title).uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.84)
                    .foregroundStyle(PagePalette.faint)
                Spacer(minLength: 8)
                legend
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Array(calendar.weekdays.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PagePalette.faint)
                        .accessibilityHidden(true)
                }
                ForEach(0..<calendar.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(calendar.days) { day in
                    InsightsDayTile(day: day, isSquare: calendar.weeks <= Self.squareWeeks)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightsPalette.cardFill, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(InsightsPalette.cardEdge, lineWidth: 1)
        }
    }

    /// "less", four steps of teal, "more".
    private var legend: some View {
        HStack(spacing: 6) {
            Text("less")
            ForEach(InsightsCalendar.legend, id: \.self) { shade in
                RoundedRectangle(cornerRadius: 3)
                    .fill(InsightsPalette.heat.opacity(shade))
                    .frame(width: 12, height: 12)
            }
            Text("more")
        }
        .font(.system(size: 11))
        .foregroundStyle(PagePalette.faint)
        .accessibilityHidden(true)
    }
}

/// One day: bare when nothing was said, otherwise teal as deep as the day was busy.
struct InsightsDayTile: View {
    let day: InsightsCalendarDay
    var isSquare = true

    var body: some View {
        shaped(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(day.isSilent ? InsightsPalette.bareTile : InsightsPalette.heat.opacity(day.shade))
        )
        .overlay {
            Text(day.number)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(day.usesDeepInk ? InsightsPalette.deepInk : PagePalette.text)
        }
        .help(day.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.detail)
    }

    /// Square, or the column's full width at a fixed height when there are too many weeks for squares.
    @ViewBuilder private func shaped(_ tile: some View) -> some View {
        if isSquare {
            tile.aspectRatio(1, contentMode: .fit)
        } else {
            tile.frame(maxWidth: .infinity).frame(height: 26)
        }
    }
}

/// One figure: the number in the display face, what it counts beneath.
struct InsightsFigureTile: View {
    let figure: MainStatistic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure.value)
                .font(BrandFont.display(size: 28, weight: .semibold))
                .tracking(-0.84)
                .monospacedDigit()
                .foregroundStyle(PagePalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(figure.caption)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.quiet)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightsPalette.cardFill, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(InsightsPalette.cardEdge, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(figure.value) \(figure.caption)")
    }
}
