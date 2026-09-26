// The History page: dictations grouped by day, with the retention sentence.

import UttrflowUX
import SwiftUI

/// The history page: dictations grouped by day, and the retention sentence even when empty.
struct HistoryPageView: View {
    let presentation: HistoryPresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        // Lazy, as `MainRowsCard` is: a thousand rows rebuilt per keystroke, inside a `ScrollView`.
        LazyVStack(alignment: .leading, spacing: 14) {
            if let empty = presentation.emptyState {
                MainCard { MainEmptyStateView(state: empty, onIntent: onIntent) }
            }
            ForEach(presentation.days) { day in
                VStack(alignment: .leading, spacing: 7) {
                    MainSectionLabel(text: day.title)
                    // Hairlines rather than a card per day, so a fortnight reads as one list.
                    VStack(spacing: 0) {
                        MainDividedRows(rows: day.rows) { entry($0) }
                    }
                }
            }
            retention
        }
    }

    private func entry(_ row: HistoryRow) -> some View {
        HistoryRowView(row: row, onIntent: onIntent)
    }

    private var retention: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            Text(presentation.retentionNotice.sentence)
                .foregroundStyle(.secondary)
            Button(presentation.retentionNotice.link.title) {
                onIntent(presentation.retentionNotice.link.intent)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentInk)
            Spacer(minLength: 0)
        }
        .font(.system(size: MainMetrics.footnoteSize))
        .padding(.top, 2)
    }
}

/// One kept dictation: copy, insert again, flag and more, the same as a Dictation-page row offers.
private struct HistoryRowView: View {
    let row: HistoryRow
    var onIntent: (MainIntent) -> Void

    /// How many lines a dictation is clamped to before "Show more" is offered.
    private static let clampedLines = 4

    @State private var isHovered = false
    @State private var isExpanded = false
    @FocusState private var focusedControl: String?

    /// The More menu's focus identity, kept apart from the action titles.
    private static let moreControl = "the More menu"

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            if let application = row.application {
                MainApplicationTile(application: application)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if let application = row.application {
                        Text(application.name)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(row.time).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(row.when).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    actions
                }
                .font(.system(size: MainMetrics.footnoteSize))
                Text(row.text)
                    .font(.system(size: MainMetrics.bodySize))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : Self.clampedLines)
                if isClampable {
                    Button(isExpanded ? "Show less" : "Show all") { isExpanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: MainMetrics.footnoteSize))
                        .foregroundStyle(Color.accentInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions(row.actions + row.more, onIntent: onIntent)
    }

    /// Long enough that a clamp at ``clampedLines`` could actually be hiding something.
    private var isClampable: Bool {
        row.text.filter { $0.isNewline }.count >= Self.clampedLines
            || row.text.count > 240
    }

    /// Hidden, not removed, and still hit-testable, so a VoiceOver user can activate these.
    private var actions: some View {
        HStack(spacing: 5) {
            ForEach(row.actions) { action in
                MainIconButton(action: action, onIntent: onIntent)
                    .revealedInRow(action.id, isHovered: isHovered, focusedControl: $focusedControl)
            }
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
            .revealedInRow(Self.moreControl, isHovered: isHovered, focusedControl: $focusedControl)
        }
    }
}
