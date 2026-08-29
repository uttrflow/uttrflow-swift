import UttrflowUX
import SwiftUI

/// Every word Uttrflow changed today, and why.
///
/// The page the whole product is accountable through. Nothing here is summarised or
/// abbreviated in the drawing either: if a sentence is long, the row grows.
struct CorrectionsPageView: View {
    let presentation: CorrectionsPresentation
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MainCalloutView(callout: presentation.callout)
                .padding(.bottom, 12)
            if let empty = presentation.emptyState {
                MainEmptyStateView(state: empty, onIntent: onIntent)
            } else {
                MainSectionLabel(text: presentation.caption)
                    .padding(.bottom, 7)
                ScrollView {
                    MainRowsCard(rows: presentation.rows) { row in
                        CorrectionRowView(row: row, onIntent: onIntent)
                    }
                }
                if let footnote = presentation.footnote {
                    MainFootnote(text: footnote)
                }
            }
        }
    }
}

/// One change: what was heard, what was written, why, where, and the way back.
struct CorrectionRowView: View {
    let row: CorrectionRow
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 10) {
            change
            MainPillView(pill: row.reason)
                .frame(width: 126, alignment: .leading)
            origin
            HStack {
                Spacer(minLength: 0)
                if let undo = row.undo {
                    MainActionButton(action: undo, onIntent: onIntent)
                } else {
                    MainPillView(pill: MainPill(text: "Undone", tone: .good))
                }
            }
            .frame(width: 82)
        }
        .font(.system(size: MainMetrics.calloutSize))
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var change: some View {
        HStack(spacing: 7) {
            Text("“\(row.heard)”")
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            // Struck through when it has been put back, because the word on screen is
            // the one that was heard.
            Text(row.wrote)
                .fontWeight(row.isUndone ? .regular : .semibold)
                .foregroundStyle(row.isUndone ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .strikethrough(row.isUndone)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var origin: some View {
        HStack(spacing: 5) {
            Text(row.when)
            if let application = row.application {
                Text("·")
                MainApplicationChip(application: application)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(width: 118, alignment: .leading)
    }

    private var accessibilityLabel: String {
        let outcome = row.isUndone ? "was changed to, and put back from," : "was changed to"
        return """
            “\(row.heard)” \(outcome) “\(row.wrote)”. \(row.reason.text). \
            \(row.when)\(row.application.map { ", \($0.name)" } ?? "").
            """
    }
}
