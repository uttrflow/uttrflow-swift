import UttrflowUX
import SwiftUI

/// The measurements the artboards are drawn to.
enum MainMetrics {
    /// Wide enough for the list and the figures to breathe.
    ///
    /// Was 900×620, which is cramped once the rail carries four figures — and cramped
    /// beside anything else on a modern display, which is the first thing anyone notices.
    static let windowSize = CGSize(width: 1180, height: 780)
    static let minimumWindowSize = CGSize(width: 760, height: 500)
    /// The height the traffic lights need before anything else may be drawn.
    static let titleBarInset: CGFloat = 26
    static let toolbarHeight: CGFloat = 40
    static let contentPadding: CGFloat = 22
    static let cardRadius: CGFloat = 10
    static let rowPadding: CGFloat = 13
    /// The icon rail down the left of the window: wide enough for a 44pt target with
    /// room either side, and nothing more, because everything it does not take belongs
    /// to the page.
    static let iconRailWidth: CGFloat = 76
    /// The sidebar with its names showing. The design's own width: eleven rows of
    /// thirteen-point text, the longest of which is "Diagnostics", plus the badge.
    static let sidebarWidth: CGFloat = 204
    /// The figures rail down the right of a page. A different rail, and a different
    /// width: this one holds a number, its name and a sentence about it, and at 76
    /// points "Words per minute" wraps one word to a line and "2.7K" truncates to
    /// "2...." — which is what it did for a build, because the two shared a name.
    static let railWidth: CGFloat = 186
    static let titleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let calloutSize: CGFloat = 12
    static let subheadSize: CGFloat = 11
    static let footnoteSize: CGFloat = 10
}

extension MainTone {
    /// What a tone is drawn in. One mapping, so a warning on Dictionary and a warning
    /// on Account cannot end up two different oranges.
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

/// A button offered by a page. Every one of them is a ``MainIntent``, so the view never
/// learns what any of them actually do.
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

/// What a page shows instead of content: a symbol, a sentence, at most one way on, and
/// whatever figures are still true with nothing to list.
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

/// The coloured tile with the app's initial in it.
///
/// The colour is derived from the name so that one app keeps one colour between launches
/// without a table of brand colours that would go stale the moment an app rebrands.
struct MainApplicationTile: View {
    let application: HistoryApplication
    var size: CGFloat = 26

    var body: some View {
        Group {
            // The app's own icon where this Mac has one, which is the whole point: a row
            // that went to Claude should look like it went to Claude, not like the
            // letter C. The lettered tile stays for everything else — an app that has
            // since been deleted, or one whose bundle is not named as it presents
            // itself — because a wrong icon is worse than an honest initial.
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
    /// Whether to write the name beside the icon.
    ///
    /// Off in the lists, where the icon is recognised faster than the word is read and
    /// the column of names was the same three words repeated down the page. On where
    /// the app itself is the subject rather than a stamp on somebody's sentence —
    /// Insights is a list *of applications*, and an icon with no name there would be a
    /// quiz.
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

/// One column of a table. Widths live in the view because a column width is a layout
/// decision and nothing on this side of ``UttrflowUX`` is anything else.
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
        // Lazy, because the history keeps up to a thousand dictations and the window is
        // rebuilt on every keystroke in a search field. Eagerly, that was a thousand rows
        // constructed and laid out per character typed. Every use of this card is inside
        // a `ScrollView`, which is what a `LazyVStack` needs to know how much to build.
        // Hairlines rather than a card, which is the design's one rule about lists: a
        // page is a page, not a stack of panels, and a box drawn around a hundred rows
        // is a box the eye has to keep re-entering. Boxes are kept for the things a
        // reader chooses between — a callout, an editor, an empty state.
        // Leading, not centre. A row fills the width because something inside it does;
        // the table header does not, so under the stack's default alignment it sat
        // centred — its "Word" over the rows' "Sounds like" — and every column label
        // named the wrong column.
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
    /// Offers a row's controls to assistive technology, whatever the pointer is doing.
    ///
    /// The controls themselves are revealed on hover, and a view at `opacity(0)` is hidden
    /// from the accessibility tree — so without this, Copy, Insert Again, Flag, Edit and
    /// Delete simply do not exist for anyone not using a mouse. VoiceOver reaches these
    /// through the actions rotor, which is Apple's own answer for hover-revealed controls.
    ///
    /// Deliberately on the row rather than on each button: a row that announced five
    /// separate buttons would make moving through a table of thirty dictations five times
    /// longer, which is the reason the controls are hidden from sight in the first place.
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
