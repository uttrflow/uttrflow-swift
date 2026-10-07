// One History row on the time rail: the time and dot in the gutter, then the dictation's card.

import UttrflowUX
import SwiftUI

/// A dictation or a lost recording beside the day's rail; the hover buttons hide only their glyphs, never themselves.
struct HistoryRailRow: View {
    let row: HistoryRow
    /// Where the row sits in its day, so the rail's line fades from the first row to the last.
    let index: Int
    let count: Int
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false
    @FocusState private var focusedControl: String?

    /// The gutter's width, where its line runs, and how far down the dot sits.
    static let gutter: CGFloat = 58
    static let lineOffset: CGFloat = 44
    static let dotTop: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            card
        }
        .padding(.bottom, 8)
        .background(alignment: .topLeading) { line }
        .contextMenu {
            ForEach(offered) { menuItem($0) }
            if !offered.isEmpty && !row.more.isEmpty { Divider() }
            if !row.fixes.isEmpty {
                Menu("Fix Word") { ForEach(row.fixes) { menuItem($0) } }
            }
            ForEach(row.more) { menuItem($0) }
        }
    }

    /// What the row's buttons do, offered again in its context menu and to VoiceOver.
    private var offered: [MainAction] {
        [row.recording?.play, row.recording?.retry].compactMap(\.self) + row.actions
    }

    /// One context menu item, its symbol beside it and red when it deletes.
    private func menuItem(_ action: MainAction) -> some View {
        Button(role: action.isDestructive ? .destructive : nil) {
            onIntent(action.intent)
        } label: {
            if let symbol = action.symbolName {
                Label(action.title, systemImage: symbol)
            } else {
                Text(action.title)
            }
        }
    }

    /// This row's stretch of the line, teal fading to faint across the day.
    private var line: some View {
        let accent = PagePalette.dictation
        let fade = { (at: Int) in 1 - 0.9 * Double(at) / Double(max(count, 1)) }
        return LinearGradient(
            colors: [accent.opacity(fade(index)), accent.opacity(fade(index + 1))],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: 2)
        .padding(.top, index == 0 ? 8 : 0)
        .padding(.bottom, index == count - 1 ? 16 : 0)
        .padding(.leading, Self.lineOffset)
        .accessibilityHidden(true)
    }

    private var gutter: some View {
        ZStack(alignment: .topLeading) {
            Text(row.time)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(PagePalette.quiet)
                .lineLimit(1)
                .frame(width: 38, alignment: .trailing)
                .padding(.top, 16)
            Circle()
                .fill(tone)
                .frame(width: 10, height: 10)
                .background(Circle().fill(Color.redesignWindow).padding(-3))
                .padding(.leading, Self.lineOffset - 4)
                .padding(.top, Self.dotTop)
                .accessibilityHidden(true)
        }
        .frame(width: Self.gutter, alignment: .leading)
    }

    /// Teal for a dictation, amber for a recording still owed its words.
    private var tone: Color {
        row.recording == nil ? PagePalette.dictation : PagePalette.clipboard
    }

    private var card: some View {
        HStack(spacing: 14) {
            icon
            if let recording = row.recording {
                HistoryRecordingLine(recording: recording, onIntent: onIntent)
            } else {
                words
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PagePalette.text.opacity(0.08), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .rowActions(offered + row.fixes + row.more, onIntent: onIntent)
    }

    /// The card's film, a little brighter when pointed at and tinted amber for a recording.
    private var fill: Color {
        if row.recording != nil { return PagePalette.clipboard.opacity(0.06) }
        return PagePalette.text.opacity(isHovered ? 0.07 : 0.045)
    }

    /// The app's own icon where this Mac has it, a neutral tile otherwise.
    @ViewBuilder private var icon: some View {
        if let application = row.application {
            MainApplicationTile(application: application, size: 30)
        } else {
            Image(systemName: row.recording == nil ? "text.bubble" : "waveform")
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.soft)
                .frame(width: 30, height: 30)
                .background(PagePalette.controlFill, in: .rect(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// The text on one line, then app · time · length · tag, the arrival and the flag when there are.
    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.text)
                .font(.system(size: 14))
                .foregroundStyle(PagePalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                if let application = row.application {
                    Text(application.name)
                    Text("·")
                }
                Text(row.time).font(.system(size: 11.5, weight: .medium, design: .monospaced))
                Text("·")
                Text(row.length)
                if let tag = row.tag {
                    Text("·")
                    Label(tag, systemImage: "wand.and.stars")
                        .labelStyle(HistoryTagLabelStyle())
                        .foregroundStyle(PagePalette.suggestion)
                }
                if let arrival = row.arrival {
                    Label(arrival, systemImage: "exclamationmark.circle")
                        .labelStyle(HistoryTagLabelStyle())
                        .foregroundStyle(PagePalette.clipboardInk)
                }
                if row.isFlagged {
                    Label("Flagged", systemImage: "flag")
                        .labelStyle(HistoryTagLabelStyle())
                        .foregroundStyle(PagePalette.clipboardInk)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(PagePalette.quiet)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only the glyphs wait for the pointer or the keyboard; the buttons stay reachable by VoiceOver.
    private var actions: some View {
        HStack(spacing: 5) {
            ForEach(row.actions) { action in
                Button {
                    onIntent(action.intent)
                } label: {
                    Image(systemName: action.symbolName ?? "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            action.intent == .flagDictation(row.id) && row.isFlagged
                                ? PagePalette.clipboard : PagePalette.text.opacity(0.7))
                }
                .buttonStyle(
                    HomeQuietButtonStyle(
                        isSquare: true,
                        isShown: RowReveal.isDrawn(isHovered: isHovered, focusedControl: focusedControl))
                )
                .help(action.title)
                .accessibilityLabel(action.title)
                .focused($focusedControl, equals: action.id)
            }
        }
    }
}

/// A recording's line: the pill to hear it, what went wrong, and the Retry button.
struct HistoryRecordingLine: View {
    let recording: HistoryRecording
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            pill
            Text(recording.message)
                .font(.system(size: 12.5))
                .foregroundStyle(PagePalette.clipboardInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let retry = recording.retry {
                Button {
                    onIntent(retry.intent)
                } label: {
                    Label(retry.title, systemImage: retry.symbolName ?? "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.redesignWindow)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(PagePalette.text, in: .rect(cornerRadius: 9, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The play button, a still waveform and the length, in an amber capsule.
    private var pill: some View {
        HStack(spacing: 8) {
            Button {
                onIntent(recording.play.intent)
            } label: {
                Image(systemName: recording.play.symbolName ?? "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PagePalette.dotRing)
                    .frame(width: 26, height: 26)
                    .background(PagePalette.clipboard, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(recording.play.title)
            .accessibilityLabel(recording.play.title)
            HistoryMiniWaveform()
                .frame(width: 26 * 4, height: 18)
            Text(recording.duration)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PagePalette.clipboardInk)
                .fixedSize()
        }
        .fixedSize()
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(PagePalette.clipboard.opacity(0.1), in: .capsule)
        .overlay { Capsule().strokeBorder(PagePalette.clipboard.opacity(0.3), lineWidth: 1) }
    }
}

/// A still waveform of thin amber bars, the shape of a short recording.
struct HistoryMiniWaveform: View {
    /// How many bars are drawn.
    static let count = 26

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(Self.count)
            for index in 0..<Self.count {
                let height = size.height * Self.bar(index)
                let rect = CGRect(
                    x: CGFloat(index) * step, y: (size.height - height) / 2, width: 2, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(PagePalette.clipboard.opacity(0.8)))
            }
        }
        .accessibilityHidden(true)
    }

    /// One bar's height as a share of the pill: rippled, tallest in the middle.
    static func bar(_ index: Int) -> Double {
        let ripple = abs(sin(Double(index) * 1.3))
        let bell = sin(Double.pi * (Double(index) + 0.5) / Double(count))
        return (20 + 80 * ripple * bell) / 100
    }
}

/// A tag's small icon close beside its words.
struct HistoryTagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10))
            configuration.title
        }
    }
}
