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
    /// The island as an icon rail, wide enough that the traffic lights, which end at 79pt, stay inside it.
    static let iconRailWidth: CGFloat = 88
    /// The sidebar with its names showing: the island and the margin that floats it off the window's edge.
    static let sidebarWidth: CGFloat = 232
    /// The figures rail down the right of a page, wide enough that "Words per minute" and "2.7K" fit.
    static let railWidth: CGFloat = 186
    static let titleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let calloutSize: CGFloat = 12
    static let subheadSize: CGFloat = 11
    static let footnoteSize: CGFloat = 10
}

extension MainTone {
    /// What a tone's text is drawn in; one mapping, so two pages cannot end up with two different oranges.
    var foreground: Color {
        switch self {
        case .neutral: .secondary
        case .accent: .accentInk
        case .warning: .warningInk
        case .good: .successInk
        case .critical: .criticalInk
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
    var isBeta = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: MainMetrics.subheadSize, weight: .semibold))
                .foregroundStyle(Color.mainMuted)
            if isBeta { BetaBadge() }
        }
        .padding(.leading, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBeta ? BetaFeature.accessibilityName(text) : text)
    }
}

/// The shared visible and spoken marker for beta features.
struct BetaBadge: View {
    var body: some View {
        Text(BetaFeature.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(PagePalette.suggestion)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(PagePalette.suggestion.opacity(0.16), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// The small print under a page.
struct MainFootnote: View {
    let text: String
    var isCentred = false

    var body: some View {
        Text(text)
            .font(.system(size: MainMetrics.footnoteSize))
            // The quiet text token, which clears 4.5:1 on the page in both appearances.
            .foregroundStyle(PagePalette.quiet)
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

/// A glass notice in the window's top-right corner saying what happened, with a way on and a way to put it away.
struct MainNoticeBar: View {
    let notice: MainNotice
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MainTintedTile(symbolName: notice.symbolName, color: notice.tone.glow)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notice.headline)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(PagePalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        onIntent(.dismissNotice)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PagePalette.faint)
                            .frame(width: 16, height: 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
                if let detail = notice.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(PagePalette.text.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                if let action = notice.action {
                    HStack(spacing: 6) {
                        // Put away first, so a refusal the action itself raises is the one left showing.
                        Button(action.title) {
                            onIntent(.dismissNotice)
                            onIntent(action.intent)
                        }
                        .buttonStyle(MainPrimaryButtonStyle(size: .compact))
                        Button("Not now") { onIntent(.dismissNotice) }
                            .buttonStyle(MainSecondaryButtonStyle(size: .compact))
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background { glass }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PagePalette.controlEdge, lineWidth: 1)
        }
        .shadow(color: PagePalette.floatShadow, radius: 25, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.message)
    }

    /// Frosted glass with the notice's colour glowing up from behind its tile.
    private var glass: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.ultraThinMaterial)
            PagePalette.toastGlass
            // The design's blurred blob, centred on the top-left corner and filling the notice, so it never sizes it.
            RadialGradient(
                stops: [
                    .init(color: notice.tone.glow.opacity(0.3), location: 0),
                    .init(color: notice.tone.glow.opacity(0.26), location: 0.4),
                    .init(color: notice.tone.glow.opacity(0.1), location: 0.72),
                    .init(color: notice.tone.glow.opacity(0), location: 1),
                ],
                center: .topLeading, startRadius: 0, endRadius: 150)
        }
        .accessibilityHidden(true)
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

    /// The window's question host, when there is one; an action that asks first asks through it.
    @Environment(MainConfirmationCenter.self) private var confirmations: MainConfirmationCenter?

    var body: some View {
        Button {
            MainConfirmationCenter.press(action, in: confirmations, onIntent: onIntent)
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

/// What a page shows instead of content: its colour glowing behind a small scene, a title, a sentence and one way on.
struct MainEmptyStateView: View {
    let state: MainEmptyState
    var onIntent: (MainIntent) -> Void

    private var accent: Color { state.scene.accent.color }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                MainEmptyStateScene(
                    scene: state.scene, symbolName: state.symbolName, progress: state.progress
                )
                .frame(height: 56)
                Text(state.title)
                    .font(BrandFont.display(size: 24, weight: .semibold))
                    .foregroundStyle(PagePalette.text)
                    .multilineTextAlignment(.center)
                Text(state.message)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(PagePalette.text.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = state.progress {
                    MainEmptyStateSteps(progress: progress, color: accent)
                }
                if !state.chips.isEmpty {
                    MainChipsRow(chips: state.chips).padding(.top, 6)
                }
                if let action = state.action {
                    MainEmptyStateButton(action: action, glow: accent, onIntent: onIntent)
                        .padding(.top, 6)
                }
            }
            .background { glow }
            Spacer(minLength: 12)
            if let footnote = state.footnote {
                MainFootnote(text: footnote, isCentred: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.title). \(state.message)")
    }

    /// The page's colour, soft and wide, centred a little above the words.
    private var glow: some View {
        EllipticalGradient(
            colors: [accent.opacity(0.2), accent.opacity(0.07), accent.opacity(0)],
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
        )
        .frame(width: 560, height: 400)
        .offset(y: -30)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    .fill(
                        Color(
                            hue: hue, saturation: BrandPalette.Redesign.appTileTone.saturation,
                            brightness: BrandPalette.Redesign.appTileTone.brightness)
                    )
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
                    .foregroundStyle(Color.warningInk)
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

/// When a row's hover-revealed controls are drawn.
enum RowReveal {
    /// While the pointer is over the row or any of its controls has keyboard focus.
    static func isDrawn(isHovered: Bool, focusedControl: String?) -> Bool {
        isHovered || focusedControl != nil
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
