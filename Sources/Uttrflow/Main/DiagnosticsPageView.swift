// The Diagnostics page: timings, engines, permissions and storage.

import UttrflowUX
import SwiftUI

/// The diagnostics page: how long things took, what is running, and what is in the way; no placeholders.
struct DiagnosticsPageView: View {
    let presentation: DiagnosticsPresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            if let empty = presentation.latencyEmptyState {
                MainCard { MainEmptyStateView(state: empty, onIntent: onIntent) }
            }
            if let latency = presentation.latency {
                MainSectionLabel(text: "Time from letting go of the key to text on screen")
                headline(latency)
                VStack(spacing: 0) {
                    MainDividedRows(rows: latency.stages) { stageRow($0) }
                    // Below the timed stages, in the grey "not known" style: a stage nothing ran is a fact.
                    ForEach(latency.unmeasured) { row in
                        MainDivider()
                        factRow(row)
                    }
                }
            }
            if !presentation.reliability.isEmpty {
                MainStatisticsRow(statistics: presentation.reliability)
            }
            section("Engines", presentation.engines)
            section("Clean-up steps, last dictation", presentation.cleanUp)
            section("Permissions", presentation.permissions)
            section("On this Mac", presentation.storage)
            footer
        }
    }

    private func headline(_ latency: DiagnosticsLatency) -> some View {
        MainCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(latency.headline)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                    Text(latency.caption)
                        .font(.system(size: MainMetrics.calloutSize))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(latency.stages) { stage in
                            Rectangle()
                                .fill(colour(for: stage))
                                .frame(width: proxy.size.width * stage.share)
                        }
                    }
                }
                .frame(height: 22)
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityHidden(true)
            }
        }
    }

    private func stageRow(_ stage: DiagnosticsStageRow) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(colour(for: stage))
                .frame(width: 9, height: 9)
            Text(stage.title)
            Spacer(minLength: 0)
            Text("\(stage.typical) typical")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text("\(stage.slowest) slowest")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
        .font(.system(size: MainMetrics.calloutSize))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            """
            \(stage.title): \(stage.typical) typically, \(stage.slowest) at worst, \
            over \(stage.samples) measurements.
            """)
    }

    /// Colours taken in the journey's order, so a stage cannot swap colours between the bar and the list.
    private func colour(for stage: DiagnosticsStageRow) -> Color {
        switch stage.stage {
        case .capture: .dockAccentTint
        case .transcription: .dockAccentLight
        case .correction: .dockAccent
        case .transformation: .dockActive
        case .expansion: .dockAccentWash
        case .insertion: .dockSuccess
        }
    }

    /// The verdict, above the facts it is drawn from.
    private var summary: some View {
        let summary = presentation.summary
        let tint: Color = summary.needsAttention ? .dockWarning : .dockSuccess
        return HStack(spacing: 11) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(summary.text)
                .font(.system(size: MainMetrics.bodySize))
                .foregroundStyle(summary.needsAttention ? Color.mainText : Color.mainMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action = summary.action {
                MainActionButton(action: action, onIntent: onIntent)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // The all-clear is a plain panel, so an amber banner is the only coloured thing on the page.
            summary.needsAttention ? Color.dockWarning.opacity(0.10) : Color.mainCard,
            in: .rect(cornerRadius: MainMetrics.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MainMetrics.cardRadius)
                .strokeBorder(
                    summary.needsAttention ? Color.dockWarning.opacity(0.28) : Color.mainSeparator,
                    lineWidth: summary.needsAttention ? 1 : 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.text)
    }

    @ViewBuilder private func section(_ title: String, _ rows: [DiagnosticsRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                MainSectionLabel(text: title)
                VStack(spacing: 0) {
                    MainDividedRows(rows: rows) { factRow($0) }
                }
            }
        }
    }

    private func factRow(_ row: DiagnosticsRow) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colour(for: row.state))
                .frame(width: 8, height: 8)
            Text(row.title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            // Wrapped rather than truncated: a step's row names the words it changed.
            Text(row.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if let action = row.action {
                MainActionButton(action: action, onIntent: onIntent)
            }
        }
        .font(.system(size: MainMetrics.calloutSize))
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title): \(row.detail)")
    }

    /// Grey for unknown, so a state nobody has checked never looks like one checked and fine.
    private func colour(for state: DiagnosticsState) -> Color {
        switch state {
        case .good: .dockSuccess
        case .attention: .dockWarning
        case .unknown: .secondary
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text(presentation.footnote)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            MainActionButton(action: presentation.copyAction, onIntent: onIntent)
        }
    }
}
