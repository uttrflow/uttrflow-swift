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
                    Text(row.when).foregroundStyle(.secondary)
                }
                .font(.system(size: MainMetrics.footnoteSize))
                Text(row.text)
                    .font(.system(size: MainMetrics.bodySize))
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
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
            .foregroundStyle(Color.dockAccent)
            Spacer(minLength: 0)
        }
        .font(.system(size: MainMetrics.footnoteSize))
        .padding(.top, 2)
    }
}
