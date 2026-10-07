// The Diagnostics tab: the model cards, this Mac, the timings, and the last dictation.

import UttrflowUX
import SwiftUI

/// What is installed, what is allowed, and how fast it runs, in the Settings page's cards.
struct SettingsDiagnosticsView: View {
    let presentation: DiagnosticsPresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if presentation.summary.needsAttention {
                summary
            }
            section("Models") {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(presentation.models) { SettingsModelCardView(card: $0) }
                }
            }
            section("This Mac") {
                rows(presentation.system + presentation.permissions + presentation.availability)
            }
            timings
            if !presentation.speechModelLoads.isEmpty {
                section("Speech model load") {
                    rows(presentation.speechModelLoads)
                }
            }
            if !presentation.arrivals.isEmpty {
                section("Where dictations arrived") {
                    rows(presentation.arrivals)
                }
            }
            if !presentation.decoding.isEmpty {
                section("Recognition effort") {
                    rows(presentation.decoding)
                }
            }
            if !presentation.waits.isEmpty {
                section("Wait after release") {
                    rows(presentation.waits)
                }
            }
            if !presentation.reliability.isEmpty {
                section("How often each step worked") {
                    rows(
                        presentation.reliability.map {
                            DiagnosticsRow(title: $0.caption, detail: $0.value, state: .good)
                        })
                }
            }
            section("Recogniser prompt") {
                rows([presentation.vocabularyPrompt])
            }
            section("Quality layers") {
                rows(presentation.qualityLayers)
            }
            section("Last dictation") {
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(presentation.cleanUp.enumerated()), id: \.element.id) { index, row in
                            fact(row, icon: index == 0 ? .symbol("waveform.path.ecg", .suggestion) : nil)
                                .overlay(alignment: .top) { if index > 0 { rule } }
                        }
                        copyRow.overlay(alignment: .top) { rule }
                    }
                }
            }
            Text(presentation.footnote)
                .font(.system(size: 11))
                .foregroundStyle(PagePalette.quiet)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Pieces

    private var rule: some View {
        Rectangle().fill(SettingsPalette.ink(0.07)).frame(height: 1)
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: title)
            content()
        }
    }

    private func rows(_ rows: [DiagnosticsRow]) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    fact(row, icon: icon(for: row))
                        .overlay(alignment: .top) { if index > 0 { rule } }
                }
            }
        }
    }

    /// The tile beside a fact about this Mac, matched on the fact's own title.
    private func icon(for row: DiagnosticsRow) -> SettingsIcon? {
        switch row.title {
        case "Uttrflow": .symbol("cpu", .mint)
        case "macOS": .symbol("macbook", .neutral)
        case "Microphone": .symbol("mic", .dictation)
        case "Accessibility": .symbol("hand.raised", .info)
        case "Dictation shortcut": .symbol("keyboard", .dictation)
        case "Input device": .symbol("mic", .dictation)
        default: nil
        }
    }

    /// One fact: its name, and its value coloured by whether it is fine, with the fix beside it.
    private func fact(_ row: DiagnosticsRow, icon: SettingsIcon?) -> some View {
        HStack(spacing: 14) {
            if let icon {
                SettingsIconTile(icon: icon)
            }
            Text(row.title)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            // The build and the machine are values to quote, so they are set as code and selectable.
            if presentation.system.contains(row) {
                Text(row.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SettingsPalette.ink(0.75))
                    .textSelection(.enabled)
            } else if row.state == .good {
                SettingsStatusView(text: row.detail)
            } else {
                // Wrapped rather than truncated: a step's row names the words it changed.
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        row.state == .attention ? PagePalette.clipboardInk : PagePalette.faint
                    )
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = row.action {
                Button(action.title) { onIntent(action.intent) }
                    .buttonStyle(SettingsButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title): \(row.detail)")
    }

    private var copyRow: some View {
        HStack(spacing: 14) {
            SettingsIconTile(icon: .symbol("list.clipboard", .amber))
            VStack(alignment: .leading, spacing: 3) {
                Text("Copy diagnostics")
                    .font(.system(size: 13.5))
                Text("For a bug report; contains no transcripts")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.faint)
            }
            Spacer(minLength: 0)
            Button("Copy") { onIntent(presentation.copyAction.intent) }
                .buttonStyle(SettingsButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// The verdict, shown only when something needs the user.
    private var summary: some View {
        let summary = presentation.summary
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.clipboard)
            Text(summary.text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action = summary.action {
                Button(action.title) { onIntent(action.intent) }
                    .buttonStyle(SettingsButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(PagePalette.clipboard.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PagePalette.clipboard.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.text)
    }

    // MARK: - Timings

    @ViewBuilder private var timings: some View {
        if let latency = presentation.latency {
            section("Time from letting go of the key to text on screen") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(latency.headline)
                                    .font(BrandFont.display(size: 20, weight: .semibold))
                                    .monospacedDigit()
                                Text(latency.caption)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(PagePalette.faint)
                                    .fixedSize(horizontal: false, vertical: true)
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
                            .frame(height: 10)
                            .clipShape(.capsule)
                            .accessibilityHidden(true)
                        }
                        .padding(16)
                        ForEach(latency.stages) { stage in
                            stageRow(stage).overlay(alignment: .top) { rule }
                        }
                        // Below the timed stages, in the grey "not known" style: a stage nothing ran is a fact.
                        ForEach(latency.unmeasured) { row in
                            fact(row, icon: nil).overlay(alignment: .top) { rule }
                        }
                    }
                }
            }
        } else if let empty = presentation.latencyEmptyState {
            section("Timings") {
                SettingsCard {
                    HStack(spacing: 14) {
                        SettingsIconTile(icon: .symbol("gauge.with.dots.needle.bottom.50percent", .info))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(empty.title).font(.system(size: 13.5))
                            Text(empty.message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(PagePalette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
        }
    }

    private func stageRow(_ stage: DiagnosticsStageRow) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colour(for: stage))
                .frame(width: 8, height: 8)
            Text(stage.title)
                .font(.system(size: 13))
            Spacer(minLength: 0)
            Text("\(stage.typical) typical")
                .frame(width: 110, alignment: .trailing)
            Text("\(stage.slowest) slowest")
                .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(SettingsPalette.ink(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stage.accessibilityLabel)
    }

    /// Colours taken in the journey's order, so a stage cannot swap colours between the bar and the list.
    private func colour(for stage: DiagnosticsStageRow) -> Color {
        switch stage.stage {
        case .microphoneOpen, .keyDownToAudio, .capture, .drain: PagePalette.dictation.opacity(0.45)
        case .transcription: PagePalette.dictation
        case .correction: PagePalette.clipboard
        case .transformation: PagePalette.suggestion
        case .expansion: PagePalette.info
        case .insertion: SettingsPalette.good
        }
    }
}

/// One model as a card: what it is for, its plain name, its facts, and whether it is ready.
struct SettingsModelCardView: View {
    let card: DiagnosticsModelCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsIconTile(icon: .symbol(card.symbolName, card.tint))
                Text(card.title)
                    .font(BrandFont.display(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                status
            }
            Text(card.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsPalette.ink(0.85))
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(card.chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(SettingsPalette.ink(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(SettingsPalette.ink(0.07), in: .rect(cornerRadius: 5))
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsPalette.ink(0.045), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettingsPalette.ink(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title): \(card.name), \(card.status)")
    }

    @ViewBuilder private var status: some View {
        switch card.state {
        case .good: SettingsStatusView(text: card.status)
        case .attention: SettingsStatusView(text: card.status, tone: PagePalette.clipboardInk)
        case .unknown: SettingsStatusView(text: card.status, tone: PagePalette.faint)
        }
    }
}
