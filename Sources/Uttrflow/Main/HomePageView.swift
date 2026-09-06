// The Home page: stage, figures, today's dictations and the clipboard demonstration.

import UttrflowUX
import SwiftUI

/// The page the window opens on: stage, figures, today's dictations, then the clipboard demonstration.
struct HomePageView: View {
    let presentation: HomePresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OrbitStage(presentation: presentation, onIntent: onIntent)
                if !presentation.figures.isEmpty {
                    figures
                    MainDivider()
                }
                if let step = presentation.nextStep {
                    MainCard { MainEmptyStateView(state: step, onIntent: onIntent) }
                        .padding(MainMetrics.contentPadding)
                }
                today
                if let demonstration = presentation.demonstration {
                    ClipboardDemonstration(demonstration: demonstration)
                        .padding(.horizontal, MainMetrics.contentPadding)
                        .padding(.bottom, 18)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Today's dictations with the clipboard beside them; the list takes the width, the rail is fixed.
    private var today: some View {
        HStack(alignment: .top, spacing: 0) {
            recent
                .padding(.horizontal, MainMetrics.contentPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let demonstration = presentation.demonstration {
                Rectangle().fill(Color.mainSeparator).frame(width: 1)
                ClipboardRail(demonstration: demonstration, onIntent: onIntent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(width: 300, alignment: .leading)
            }
        }
    }

    /// The figures in one centred row under the stage, or a grid when the window is too narrow for the row.
    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(presentation.figures.enumerated()), id: \.element.id) {
                    index, figure in
                    OrbitFigure(statistic: figure, tint: Self.tint(at: index))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 12)],
                alignment: .leading, spacing: 12
            ) {
                ForEach(presentation.figures) { figure in
                    MainFigureTile(statistic: figure)
                }
            }
            .padding(.horizontal, MainMetrics.contentPadding)
            .padding(.vertical, 16)
        }
    }

    /// Bright teal, plain, deep teal, plain — the rhythm the row is drawn with.
    private static func tint(at index: Int) -> Color? {
        switch index % 4 {
        case 0: .dockActive
        case 2: .dockAccent
        default: nil
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                MainSectionLabel(text: presentation.recentTitle)
                Spacer(minLength: 0)
                if let seeAll = presentation.seeAll {
                    MainActionButton(action: seeAll, onIntent: onIntent)
                }
            }
            .padding(.bottom, 4)
            // Hairlines rather than a card: the list is the page's own content, not a panel dropped onto it.
            ForEach(presentation.recent) { row in
                MainDivider()
                HomeRowView(row: row, onIntent: onIntent)
            }
        }
    }
}

/// One dictation, at a glance.
struct HomeRowView: View {
    let row: HomeRow
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.when)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(Color.mainDim)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)
                .padding(.top, 2)
            Text(row.text)
                .font(.system(size: MainMetrics.bodySize))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let application = row.application {
                MainApplicationChip(application: application)
                    .padding(.top, 1)
            }
            // Hidden rather than removed, so the row keeps its shape and a keyboard can still reach it.
            MainIconButton(action: row.open, onIntent: onIntent)
                .opacity(isHovered ? 1 : 0)
                .padding(.top, -2)
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions([row.open], onIntent: onIntent)
    }
}

/// The clipboard shown doing the whole gesture, drawn rather than recorded. See Docs/app-main-window.md.
struct ClipboardDemonstration: View {
    let demonstration: HomeDemonstration

    /// Whether anybody can currently see this; starts true so the animation runs from the first frame.
    @State private var isVisible = true

    /// How long the whole story takes: long enough to read the pasted line, short enough to see it happen.
    private static let loop: Double = 8

    /// Wide enough for the pasted line to arrive unwrapped: 373 points of text and ten of padding a side.
    private static let documentWidth: CGFloat = 400

    var body: some View {
        // Paused when nothing can see it, which is where this card spends most of its life.
        TimelineView(.animation(paused: !isVisible)) { timeline in
            let phase = Self.phase(at: timeline.date)
            // Side by side while the document holds its line, stacked otherwise. See Docs/app-main-window.md.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    // An ideal width, because a greedy column never "fits" in `ViewThatFits`.
                    explanation(phase: phase)
                        .frame(idealWidth: 360, maxWidth: 460, alignment: .leading)
                    stage(phase: phase)
                        .frame(width: Self.documentWidth, height: 172)
                }
                VStack(alignment: .leading, spacing: 16) {
                    explanation(phase: phase)
                    stage(phase: phase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 172)
                }
            }
            .padding(17)
        }
        .cardSurface()
        // One element, one sentence: a screen reader hears what this teaches, not frames.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            """
            \(demonstration.title). \(demonstration.explanation) \
            Press \(demonstration.keys.joined(separator: " ")), choose a line, press \
            Return, and it is typed into \(demonstration.insertedInto). \
            \(demonstration.footnote)
            """
        )
        .onWindowVisibilityChange { isVisible = $0 }
    }

    /// The words beside the demonstration, defined once so both arrangements agree.
    private func explanation(phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(demonstration.title)
                .font(.system(size: MainMetrics.bodySize, weight: .semibold))
            Text(demonstration.explanation)
                .font(.system(size: MainMetrics.calloutSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            keys(phase: phase)
                .padding(.top, 2)
            Text(demonstration.footnote)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Where the loop is

    private struct Phase {
        let keysAreDown: Bool
        let returnIsDown: Bool
        /// 0 while the panel is absent, 1 once it is fully there.
        let panel: Double
        let selected: Int
        let highlight: Double
        /// How much of the chosen line has been typed into the document, 0 to 1.
        let typed: Double
    }

    /// The whole animation as a function of the clock, so the page can redraw under it without a stutter.
    private static func phase(at date: Date) -> Phase {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        func at(
            keys: Bool = false, enter: Bool = false, panel: Double, row: Int,
            highlight: Double, typed: Double = 0
        ) -> Phase {
            Phase(
                keysAreDown: keys, returnIsDown: enter, panel: panel, selected: row,
                highlight: highlight, typed: typed)
        }
        switch t {
        // Someone is part-way through writing something. Nothing is happening yet.
        case ..<1.0: return at(panel: 0, row: 0, highlight: 0)
        // The keys go down and the panel arrives with them.
        case ..<1.9: return at(keys: true, panel: eased((t - 1.0) / 0.9), row: 0, highlight: 0)
        // It settles, and the first line is under the cursor.
        case ..<2.5: return at(panel: 1, row: 0, highlight: 1)
        // Down, and down again — which is how it is actually used.
        case ..<3.1: return at(panel: 1, row: 1, highlight: 1)
        case ..<3.9: return at(panel: 1, row: 2, highlight: 1)
        // Return. The panel goes.
        case ..<4.3: return at(enter: true, panel: 1, row: 2, highlight: 1)
        case ..<4.9:
            return at(panel: 1 - eased((t - 4.3) / 0.6), row: 2, highlight: 1)
        // And the words land where the cursor was, which is the whole point of the thing.
        case ..<5.9:
            return at(panel: 0, row: 2, highlight: 0, typed: eased((t - 4.9) / 1.0))
        // Long enough to read what arrived before it resets.
        default: return at(panel: 0, row: 2, highlight: 0, typed: 1)
        }
    }

    /// Ease-out, so things arrive rather than snapping.
    private static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    // MARK: - The pieces

    private func keys(phase: Phase) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(demonstration.keys.enumerated()), id: \.offset) { _, key in
                keycap(key, isDown: phase.keysAreDown)
            }
            Text("then")
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
            keycap("⏎", isDown: phase.returnIsDown)
        }
        .animation(.easeOut(duration: 0.12), value: phase.keysAreDown)
        .animation(.easeOut(duration: 0.12), value: phase.returnIsDown)
    }

    private func keycap(_ key: String, isDown: Bool) -> some View {
        Text(key)
            .font(.system(size: 13, weight: .medium))
            .frame(minWidth: 26, minHeight: 26)
            .background(
                isDown ? Color.dockAccent : Color.primary.opacity(0.06),
                in: .rect(cornerRadius: 6)
            )
            .foregroundStyle(isDown ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.mainSeparator, lineWidth: isDown ? 0 : 0.5)
            )
            .offset(y: isDown ? 1 : 0)
    }

    /// The document being written in, with the panel over it.
    private func stage(phase: Phase) -> some View {
        ZStack(alignment: .top) {
            document(phase: phase)
            panel(phase: phase)
                .padding(.horizontal, 9)
                .padding(.top, 34)
        }
    }

    private func document(phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.primary.opacity(0.14)).frame(width: 7, height: 7)
                }
                Text(demonstration.insertedInto)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            MainDivider()
            typedLine(phase: phase)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .cardSurface(Color.mainBackground, cornerRadius: 10)
    }

    /// What is in the document: what was there, as much of the pasted line as has arrived, then the caret.
    private func typedLine(phase: Phase) -> some View {
        let pasted = demonstration.chosenRow?.text ?? ""
        let shown = String(pasted.prefix(Int((Double(pasted.count) * phase.typed).rounded())))
        // One `Text` with runs inside it, so the pasted words wrap with the sentence they land in.
        var line = AttributedString(demonstration.existingText)
        line.foregroundColor = .secondary
        var arriving = AttributedString(shown)
        arriving.foregroundColor = .dockAccent
        arriving.font = .system(size: MainMetrics.footnoteSize, weight: .medium)
        line.append(arriving)
        if phase.typed > 0 && phase.typed < 1 {
            var caret = AttributedString("|")
            caret.foregroundColor = .dockAccent
            line.append(caret)
        }
        return Text(line)
            .font(.system(size: MainMetrics.footnoteSize))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func panel(phase: Phase) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(demonstration.rows.enumerated()), id: \.element.id) { index, row in
                demonstrationRow(
                    row, isSelected: index == phase.selected, highlight: phase.highlight)
                if index < demonstration.rows.count - 1 { MainDivider() }
            }
        }
        .cardSurface(.regularMaterial, cornerRadius: 10)
        .shadow(color: .black.opacity(0.20 * phase.panel), radius: 14, y: 5)
        .opacity(phase.panel)
        // Rises as it arrives, the way the real panel does.
        .offset(y: (1 - phase.panel) * 10)
        .scaleEffect(0.96 + 0.04 * phase.panel, anchor: .top)
    }

    private func demonstrationRow(
        _ row: HomeDemonstrationRow, isSelected: Bool, highlight: Double
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: row.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white : Color.dockAccent)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.text)
                    .font(.system(size: MainMetrics.footnoteSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Dimmer as well as bulleted, so a masked row reads as withheld, not as full stops.
                    .foregroundStyle(
                        isSelected ? .white : (row.isMasked ? .secondary : .primary))
                Text(row.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.dockAccent.opacity(isSelected ? 0.92 * highlight : 0),
            in: .rect(cornerRadius: 7)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}
