import UttrflowUX
import SwiftUI

/// Today's dictations, and the three figures the app can vouch for.
///
/// Which rows appear, what the badge on one says and whether the rail has two tiles or
/// three are all ``DictationPresenter``'s decisions. This file has no opinions.
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

/// One dictation.
///
/// The hover controls are laid out whether or not the pointer is over the row and are
/// only made invisible, so pointing at a row does not reflow it — the same trick the
/// artboard's CSS uses, and for the same reason.
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
        // Hidden rather than removed: the row must be the same height and the same
        // shape whether or not the pointer happens to be over it.
        //
        // Still hit-testable while invisible, deliberately. `allowsHitTesting(isHovered)`
        // reads like tidiness and is the difference between a control a VoiceOver user
        // can activate and one they cannot — and by the time a *pointer* can reach these,
        // the row is hovered and they are visible, so nothing can be clicked by accident.
        .opacity(isHovered ? 1 : 0)
    }
}
