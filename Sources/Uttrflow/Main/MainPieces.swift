// The sizes, tones and small views every main-window page is built from.

import UttrflowUX
import SwiftUI

/// The measurements the artboards are drawn to.
enum MainMetrics {
    /// Wide enough for the list and the figures to breathe on a modern display.
    static let windowSize = CGSize(width: 1180, height: 780)
    static let minimumWindowSize = CGSize(width: 760, height: 500)
    /// The height the traffic lights need before anything else may be drawn.
    static let titleBarInset: CGFloat = 26
    static let toolbarHeight: CGFloat = 40
    static let contentPadding: CGFloat = 22
    static let cardRadius: CGFloat = 10
    static let rowPadding: CGFloat = 13
    /// The icon rail down the left: wide enough for a 44pt target with room either side, and no more.
    static let iconRailWidth: CGFloat = 76
    /// The sidebar with its names showing, sized to eleven rows of thirteen-point text plus the badge.
    static let sidebarWidth: CGFloat = 204
    /// The figures rail down the right of a page, wide enough that "Words per minute" and "2.7K" fit.
    static let railWidth: CGFloat = 186
    static let titleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let calloutSize: CGFloat = 12
    static let subheadSize: CGFloat = 11
    static let footnoteSize: CGFloat = 10
}

extension MainTone {
    /// What a tone is drawn in; one mapping, so two pages cannot end up with two different oranges.
    var foreground: Color {
        switch self {
        case .neutral: .secondary
        case .accent: .dockAccent
        case .warning: .dockWarning
        case .good: .dockSuccess
        case .critical: .dockRecording
        }
    }

    var background: Color {
        switch self {
        case .neutral: .primary.opacity(0.06)
        default: foreground.opacity(0.16)
        }
    }
}

/// The slab everything on a page sits on.
struct MainCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

extension View {
    /// The card treatment: `fill` inside a rounded rectangle, ruled with the hairline colour.
    func cardSurface<Fill: ShapeStyle>(
        _ fill: Fill = Color.mainCard, cornerRadius: CGFloat = MainMetrics.cardRadius
    ) -> some View {
        background(fill, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.mainSeparator, lineWidth: 0.5))
    }
}

/// The heading above a card, and the caption above a list.
struct MainSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: MainMetrics.subheadSize, weight: .semibold))
            .foregroundStyle(Color.mainMuted)
            .padding(.leading, 3)
    }
}

/// The small print under a page.
struct MainFootnote: View {
    let text: String
    var isCentred = false

    var body: some View {
        Text(text)
            .font(.system(size: MainMetrics.footnoteSize))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(isCentred ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: isCentred ? .center : .leading)
            .padding(.top, 12)
    }
}

/// A short label on a tinted background.
struct MainPillView: View {
    let pill: MainPill

    var body: some View {
        Text(pill.text)
            .font(.system(size: MainMetrics.footnoteSize, weight: .medium))
            .foregroundStyle(pill.tone.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pill.tone.background, in: .rect(cornerRadius: 5))
    }
}

/// A tinted paragraph saying what a page is for.
struct MainCalloutView: View {
    let callout: MainCallout

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: callout.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(callout.tone.foreground)
                .padding(.top, 1)
            Text(callout.message)
                .font(.system(size: MainMetrics.subheadSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(callout.tone.background, in: .rect(cornerRadius: MainMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// A capsule filled to a fraction of its width, on a faint track.
struct MainBar: View {
    let fraction: Double
    var fill: Color = .dockAccentLight
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(fill).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: height)
    }
}

/// One bar in a figure.
struct MainMeterView: View {
    let meter: MainMeter

    var body: some View {
        HStack(spacing: 7) {
            Text(meter.label)
                .frame(width: 50, alignment: .leading)
            MainBar(fraction: meter.fraction, fill: meter.isBaseline ? .secondary : .dockAccentLight)
        }
        .font(.system(size: MainMetrics.footnoteSize))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// One figure and what it counts, with whatever it is compared against.
struct MainFigureTile: View {
    let statistic: MainStatistic

    var body: some View {
        MainCard(padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(statistic.value)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                Text(statistic.caption)
                    .font(.system(size: MainMetrics.subheadSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                if !statistic.meters.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(statistic.meters) { MainMeterView(meter: $0) }
                    }
                    .padding(.top, 9)
                }
                if let comment = statistic.comment {
                    Text(comment)
                        .font(.system(size: MainMetrics.footnoteSize))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of figures, divided the way the artboards divide them.
struct MainStatisticsRow: View {
    let statistics: [MainStatistic]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(statistics.enumerated()), id: \.element.id) { index, statistic in
                if index > 0 {
                    Rectangle().fill(Color.mainSeparator).frame(width: 1, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(statistic.value)
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                    Text(statistic.caption)
                        .font(.system(size: MainMetrics.subheadSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .overlay(alignment: .top) { MainDivider() }
        .overlay(alignment: .bottom) { MainDivider() }
    }
}

/// The small figures under an empty pane.
struct MainChipsRow: View {
    let chips: [MainStatistic]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                VStack(spacing: 1) {
                    Text(chip.value)
                        .font(.system(size: MainMetrics.titleSize, weight: .semibold))
                        .monospacedDigit()
                    Text(chip.caption)
                        .font(.system(size: MainMetrics.footnoteSize))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A button offered by a page; every one is a `MainIntent`, so the view never learns what it does.
struct MainActionButton: View {
    let action: MainAction
    var isProminent = false
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Button {
            onIntent(action.intent)
        } label: {
            if let symbol = action.symbolName {
                Label(action.title, systemImage: symbol)
            } else {
                Text(action.title)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private var tint: Color? {
        if action.isDestructive { return .dockRecording }
        return isProminent ? .dockAccent : nil
    }
}

/// An action drawn as its symbol alone, for the row-hover controls.
struct MainIconButton: View {
    let action: MainAction
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Button {
            onIntent(action.intent)
        } label: {
            Image(systemName: action.symbolName ?? "questionmark")
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

/// What a page shows instead of content: a symbol, a sentence, at most one way on, and any figures.
struct MainEmptyStateView: View {
    let state: MainEmptyState
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image(systemName: state.symbolName)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.dockAccent)
                .frame(width: 82, height: 82)
                .background(Color.dockAccent.opacity(0.14), in: .circle)
                .overlay(Circle().strokeBorder(Color.dockAccentTint, lineWidth: 1))
            Text(state.title)
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 18)
            Text(state.message)
                .font(.system(size: MainMetrics.bodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 410)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
            if let progress = state.progress {
                MainProgressView(progress: progress).padding(.top, 20)
            }
            if !state.chips.isEmpty {
                MainChipsRow(chips: state.chips).padding(.top, 20)
            }
            if let action = state.action {
                MainActionButton(action: action, isProminent: true, onIntent: onIntent)
                    .controlSize(.large)
                    .padding(.top, 18)
            }
            Spacer(minLength: 12)
            if let footnote = state.footnote {
                MainFootnote(text: footnote, isCentred: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.title). \(state.message)")
    }
}

/// How far off a page is from having something to draw.
struct MainProgressView: View {
    let progress: MainProgress

    var body: some View {
        VStack(spacing: 8) {
            MainBar(fraction: progress.fraction, height: 7)
            HStack {
                Text(progress.leading)
                Spacer(minLength: 8)
                Text(progress.trailing)
            }
            .font(.system(size: MainMetrics.footnoteSize))
            .foregroundStyle(.secondary)
        }
        .frame(width: 280)
        .accessibilityElement(children: .combine)
    }
}

/// The app's icon, or a tile coloured from its name so one app keeps one colour between launches.
struct MainApplicationTile: View {
    let application: HistoryApplication
    var size: CGFloat = 26

    var body: some View {
        Group {
            // The app's own icon where this Mac has one; the lettered tile stays for everything else.
            if let icon = ApplicationIcons.shared.icon(for: application) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .fill(Color(hue: hue, saturation: 0.55, brightness: 0.62))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(application.initial)
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .accessibilityLabel(application.name)
    }

    private var hue: Double {
        let total = application.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(total % 360) / 360
    }
}

/// The app tile and its name, as the rows write it.
struct MainApplicationChip: View {
    let application: HistoryApplication
    /// Whether to write the name beside the icon: off in lists, on where the app itself is the subject.
    var showsName = false

    var body: some View {
        HStack(spacing: 6) {
            MainApplicationTile(application: application, size: showsName ? 15 : 17)
            if showsName { Text(application.name) }
        }
        .help(application.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(application.name)
    }
}

/// The caption beside an inline editor's field.
struct MainEditorLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: MainMetrics.footnoteSize))
            .foregroundStyle(.secondary)
            .frame(width: 88, alignment: .leading)
    }
}

/// An inline editor's last line: why it cannot be saved, beside Cancel and the Save that refuses.
struct MainEditorFooter: View {
    let problem: String?
    let cancel: MainAction
    let save: MainAction
    let canSave: Bool
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let problem {
                Text(problem)
                    .font(.system(size: MainMetrics.footnoteSize))
                    .foregroundStyle(Color.dockWarning)
            }
            Spacer(minLength: 0)
            MainActionButton(action: cancel, onIntent: onIntent)
            MainActionButton(action: save, isProminent: true, onIntent: onIntent)
                .disabled(!canSave)
        }
    }
}

/// The header row of a table.
struct MainTableHeader: View {
    let columns: [MainColumn]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(columns) { column in
                Text(column.title.uppercased())
                    .frame(width: column.width, alignment: column.alignment)
            }
        }
        .font(.system(size: MainMetrics.footnoteSize, weight: .semibold))
        .foregroundStyle(Color.mainDim)
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One column of a table; widths live in the view because a column width is a layout decision.
struct MainColumn: Identifiable {
    let title: String
    let width: CGFloat?
    var alignment: Alignment = .leading

    var id: String { title }
}

/// Rows with a hairline between each pair, so a list never opens with one above its first row.
struct MainDividedRows<Row: Identifiable, Content: View>: View {
    let rows: [Row]
    @ViewBuilder var content: (Row) -> Content

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 { MainDivider() }
            content(row)
        }
    }
}

/// A list drawn as one card with hairlines between the rows.
struct MainRowsCard<Row: Identifiable, Content: View>: View {
    let rows: [Row]
    var header: MainTableHeader?
    @ViewBuilder var content: (Row) -> Content

    var body: some View {
        // Lazy, because a search rebuilds a thousand rows per keystroke; leading, so the header lines up.
        LazyVStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 || header != nil {
                    MainDivider()
                }
                content(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Offers a row's hover-revealed controls to VoiceOver through the actions rotor, once per row.
    func rowActions(
        _ actions: [MainAction], onIntent: @escaping (MainIntent) -> Void
    )
        -> some View
    {
        accessibilityActions {
            ForEach(actions) { action in
                Button(action.title) { onIntent(action.intent) }
            }
        }
    }
}
