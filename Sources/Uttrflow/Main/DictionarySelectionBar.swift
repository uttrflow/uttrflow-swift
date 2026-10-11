// The bar over the Dictionary table while rows are ticked.

import UttrflowUX
import SwiftUI

/// Over the table while rows are ticked: how many, and Restore selected and Delete selected for all of them.
struct DictionarySelectionBar: View {
    let selection: DictionarySelection
    var onSelectAll: () -> Void
    var onClear: () -> Void
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(selection.count)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(PagePalette.text)
            if let selectAll = selection.selectAll {
                Button(selectAll, action: onSelectAll)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.clipboardInk)
            }
            Button(selection.clear, action: onClear)
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(PagePalette.clipboardInk)
            Spacer(minLength: 6)
            if let restore = selection.restore {
                PageButton(action: restore, onIntent: acting)
            }
            PageButton(action: selection.delete, onIntent: acting)
        }
        .accessibilityElement(children: .contain)
    }

    /// Carries the batch out, then unticks the rows it acted on.
    private func acting(_ intent: MainIntent) {
        onIntent(intent)
        onClear()
    }
}
