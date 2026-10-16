import SwiftUI
import UttrflowUX

/// What History keeps, then the way to the privacy settings: the words give way first when the window is narrow.
struct HistoryCaptionView: View {
    let text: String
    let link: MainAction
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .foregroundStyle(PagePalette.quiet)
                .lineLimit(1)
            // The dot only separates the two for the eye; the link is named by its own words.
            Text(" · ")
                .foregroundStyle(PagePalette.quiet)
                .accessibilityHidden(true)
            Button(link.title) { onIntent(link.intent) }
                .buttonStyle(.plain)
                .foregroundStyle(PagePalette.dictation)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
        .font(.system(size: 13))
    }
}
