// The Dictation page: today's dictations and their figures.

import UttrflowUX
import SwiftUI

/// Today's dictations and the figures the app can vouch for; every decision is `DictationPresenter`'s.
struct DictationPageView: View {
    let presentation: DictationPresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        if let blocked = presentation.blocked {
            MainEmptyStateView(state: blocked, onIntent: onIntent)
        } else if let empty = presentation.emptyState {
            MainEmptyStateView(state: empty, onIntent: onIntent)
        } else {
            HStack(alignment: .top, spacing: 15) {
                list
                rail
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            MainSectionLabel(text: presentation.caption)
                .padding(.bottom, 7)
            ScrollView {
                MainRowsCard(rows: presentation.rows) { row in
                    DictationRowView(row: row, onIntent: onIntent)
                }
            }
            if let footnote = presentation.footnote {
                MainFootnote(text: footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rail: some View {
        VStack(spacing: 9) {
            ForEach(presentation.figures) { MainFigureTile(statistic: $0) }
        }
        .frame(width: MainMetrics.railWidth)
    }
}

/// One dictation; the hover controls are only made invisible, so pointing at a row does not reflow it.
struct DictationRowView: View {
    let row: DictationRow
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.when)
                .font(.system(size: MainMetrics.footnoteSize))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                if row.status != nil {
                    // A recording has no words yet, so a waveform stands where they will go.
                    Label(row.text, systemImage: "waveform")
                        .font(.system(size: MainMetrics.bodySize))
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.text)
                        .font(.system(size: MainMetrics.bodySize))
                        .fixedSize(horizontal: false, vertical: true)
                }
                meta
            }
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions(row.actions + row.more, onIntent: onIntent)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let application = row.application {
                MainApplicationChip(application: application)
                Text("·")
            }
            Text(row.detail).fixedSize()
            if let status = row.status {
                Text(status.rawValue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MainTone.warning.background, in: .rect(cornerRadius: 5))
                    .foregroundStyle(MainTone.warning.foreground)
            }
            if let changes = row.changes {
                Button(changes.title) { onIntent(changes.intent) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MainTone.accent.background, in: .rect(cornerRadius: 5))
                    .foregroundStyle(Color.dockAccent)
                    .help("See what Uttrflow changed in this dictation")
            }
            Spacer(minLength: 8)
            if let prominent = row.prominent {
                MainActionButton(action: prominent, isProminent: true, onIntent: onIntent)
            }
            actions
        }
        .font(.system(size: MainMetrics.footnoteSize))
        .foregroundStyle(.secondary)
        .frame(height: 24)
    }

    private var actions: some View {
        HStack(spacing: 5) {
            ForEach(row.actions) { MainIconButton(action: $0, onIntent: onIntent) }
            Menu {
                ForEach(row.more) { action in
                    Button(action.title, role: action.isDestructive ? .destructive : nil) {
                        onIntent(action.intent)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
            .accessibilityLabel("More")
        }
        // Hidden, not removed, and still hit-testable, so a VoiceOver user can activate these.
        .opacity(isHovered ? 1 : 0)
    }
}
