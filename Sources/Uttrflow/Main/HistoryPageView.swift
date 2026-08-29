import UttrflowUX
import SwiftUI

/// The history page: what was dictated, grouped by day, and what is kept.
///
/// The retention sentence is drawn whether or not there is anything in the list, because
/// ``HistoryPresenter`` always writes one: somebody checking what the app holds about them
/// should not have to dictate first in order to find out.
struct HistoryPageView: View {
    let presentation: HistoryPresentation
    var onIntent: (MainIntent) -> Void = { _ in }

    var body: some View {
        // Lazy for the reason `MainRowsCard` is: ninety days of dictations is up to a
        // thousand rows, and this page is rebuilt from scratch on every keystroke in its
        // own search field. The whole page sits in a `ScrollView`.
        LazyVStack(alignment: .leading, spacing: 14) {
            if let empty = presentation.emptyState {
                MainCard { MainEmptyStateView(state: empty, onIntent: onIntent) }
            }
            ForEach(presentation.days) { day in
                VStack(alignment: .leading, spacing: 7) {
                    MainSectionLabel(text: day.title)
                    // Hairlines rather than a card per day, so a fortnight of dictations
                    // reads as one list with days marked in it rather than as fourteen
                    // panels stacked up.
                    VStack(spacing: 0) {
                        ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                MainDivider()
                            }
                            entry(row)
                        }
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
