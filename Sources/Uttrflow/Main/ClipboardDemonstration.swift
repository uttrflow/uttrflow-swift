// The home page's drawn demonstration of the paste, the view alone.

import UttrflowUX
import SwiftUI

/// The clipboard shown doing the whole gesture, drawn rather than recorded. See Docs/app-main-window.md.
struct ClipboardDemonstration: View {
    let demonstration: HomeDemonstration

    /// Whether anybody can currently see this; starts true so the animation runs from the first frame.
    @State private var isVisible = true

    /// The width the page offers this card, measured outside the clock so no frame has to ask for it.
    @State private var offeredWidth: CGFloat = 0

    var body: some View {
        card
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                offeredWidth = $0
            }
    }

    /// The card itself, its arrangement settled before the clock starts so a frame only redraws.
    private var card: some View {
        let arrangement = ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: offeredWidth)
        // Paused when nothing can see it, which is where this card spends most of its life.
        return TimelineView(.animation(paused: !isVisible)) { timeline in
            contents(phase: .at(timeline.date), arrangement: arrangement)
                .padding(ClipboardDemonstrationMetrics.padding)
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

    /// Side by side while the width holds the document's line, stacked otherwise.
    @ViewBuilder
    private func contents(
        phase: ClipboardDemonstrationPhase, arrangement: ClipboardDemonstrationArrangement
    ) -> some View {
        switch arrangement {
        case .sideBySide(let explanationWidth):
            HStack(alignment: .top, spacing: ClipboardDemonstrationMetrics.columnSpacing) {
                explanation(phase: phase)
                    .frame(width: explanationWidth, alignment: .leading)
                stage(phase: phase)
                    .frame(
                        width: ClipboardDemonstrationMetrics.documentWidth,
                        height: ClipboardDemonstrationMetrics.stageHeight)
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 16) {
                explanation(phase: phase)
                stage(phase: phase)
                    .frame(maxWidth: .infinity)
                    .frame(height: ClipboardDemonstrationMetrics.stageHeight)
            }
        }
    }

    /// The words beside the demonstration, defined once so both arrangements agree.
    private func explanation(phase: ClipboardDemonstrationPhase) -> some View {
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

    // MARK: - The pieces

    private func keys(phase: ClipboardDemonstrationPhase) -> some View {
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
    private func stage(phase: ClipboardDemonstrationPhase) -> some View {
        ZStack(alignment: .top) {
            document(phase: phase)
            panel(phase: phase)
                .padding(.horizontal, 9)
                .padding(.top, 34)
        }
    }

    private func document(phase: ClipboardDemonstrationPhase) -> some View {
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
    private func typedLine(phase: ClipboardDemonstrationPhase) -> some View {
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

    private func panel(phase: ClipboardDemonstrationPhase) -> some View {
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
