// The Dictionary page's short list of words learnt lately, each with Undo.

import UttrflowUX
import SwiftUI

/// The words learnt lately, each with the Undo that removes it and keeps it from coming back.
struct DictionaryRecentlyLearntView: View {
    let section: DictionaryRecentlyLearnt
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageSectionLabel(text: section.title)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(section.rows) { row in
                    if row.id != section.rows.first?.id { PageDivider() }
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.word)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PagePalette.text)
                            Text(row.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(PagePalette.faint)
                        }
                        Spacer(minLength: 6)
                        Text(row.place)
                            .font(.system(size: 11.5))
                            .foregroundStyle(PagePalette.faint)
                            .multilineTextAlignment(.trailing)
                        Button {
                            onIntent(row.undo.intent)
                        } label: {
                            Label(row.undo.title, systemImage: row.undo.symbolName ?? "arrow.uturn.backward")
                                .font(.system(size: 11.5))
                                .foregroundStyle(PagePalette.clipboardInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(
                                localized: "Undo, \(row.word)",
                                comment: "Recently learnt row: Undo button label, names the word"))
                    }
                    .padding(.horizontal, PageMetrics.rowInset)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .contain)
                }
            }
            .pageCard()
        }
    }
}
