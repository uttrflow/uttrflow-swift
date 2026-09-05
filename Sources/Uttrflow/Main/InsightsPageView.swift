import UttrflowUX
import SwiftUI

/// A fortnight of dictations, and only the things that can honestly be said about them.
struct InsightsPageView: View {
    let presentation: InsightsPresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        if let empty = presentation.emptyState {
            MainEmptyStateView(state: empty, onIntent: onIntent)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    if !presentation.figures.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(presentation.figures) { MainFigureTile(statistic: $0) }
                        }
                    }
                    if !presentation.places.isEmpty {
                        places
                    }
                    if let footnote = presentation.footnote {
                        MainFootnote(text: footnote)
                    }
                }
            }
        }
    }

    private var chart: some View {
        MainCard(padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(presentation.chartTitle)
                        .font(.system(size: MainMetrics.titleSize, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(presentation.chartCaption)
                        .font(.system(size: MainMetrics.footnoteSize))
                        .foregroundStyle(.secondary)
                }
                InsightsBars(days: presentation.days, average: presentation.average)
            }
        }
    }

    private var places: some View {
        MainCard(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Where you dictate")
                    .font(.system(size: MainMetrics.bodySize, weight: .semibold))
                ForEach(presentation.places) { place in
                    HStack(spacing: 8) {
                        MainApplicationChip(application: place.application, showsName: true)
                            .frame(width: 92, alignment: .leading)
                        MainBar(fraction: place.share)
                        Text(place.words)
                            .font(.system(size: MainMetrics.footnoteSize))
                            .monospacedDigit()
                            .foregroundStyle(Color.mainDim)
                            .frame(width: 84, alignment: .trailing)
                        Text(place.percentage)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .font(.system(size: MainMetrics.footnoteSize))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// One bar per day of the window, silent days included.
struct InsightsBars: View {
    let days: [InsightsDay]
    /// The mean, drawn across the bars. Absent when there is nothing to average.
    var average: InsightsAverage?

    /// The tallest a bar may be drawn. The presenter has already reduced each day to a
    /// fraction of the busiest one, so this is the only number the view supplies.
    private let height: CGFloat = 70

    /// The room the day labels take under the bars, so the average line can be placed
    /// against the bars' own baseline rather than the row's.
    private let labelHeight: CGFloat = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colour(for: day))
                        // A silent day still gets a sliver, so the gap in the row is
                        // visibly a day with nothing in it rather than a missing column.
                        .frame(height: day.isSilent ? 4 : max(6, height * day.fraction))
                    Text(day.label)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.label): \(day.words) words")
            }
        }
        .frame(height: 86)
        .overlay(alignment: .bottomLeading) { averageLine }
    }

    /// A dashed rule at the mean, labelled at its right-hand end.
    ///
    /// Behind the bars rather than over them would hide it on the busy days, which are
    /// exactly the days somebody is comparing against it.
    @ViewBuilder private var averageLine: some View {
        if let average {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Color.mainMuted.opacity(0.45))
                    .frame(height: 1)
                    .mask(dashes)
                Text(average.label)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Color.mainDim)
                    .padding(.horizontal, 3)
                    .background(Color.mainCard)
                    .offset(y: -11)
            }
            .padding(.bottom, labelHeight + height * average.fraction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Average, \(average.label)")
        }
    }

    private var dashes: some View {
        // A dashed line, so it reads as a reference rather than as one more bar laid on
        // its side.
        HorizontalRule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(.black)
    }

    private func colour(for day: InsightsDay) -> Color {
        if day.isSilent { return .secondary.opacity(0.35) }
        return day.isToday ? .dockAccent : .dockAccentLight
    }
}

/// A horizontal rule, as a shape, so it can be dashed.
struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
