import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

@Suite("Suggestion model storage")
struct SuggestionModelStoragePresentationTests {
    @Test("reports local disk use and offers to remove the downloaded model")
    func showsUsageAndRemoval() throws {
        let locale = Locale(identifier: "en_GB")
        let page = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(), suggestionModelBytesOnDisk: 1_000_000, locale: locale)
        let row = try #require(page.storage.first { $0.title == "Suggestion model" })

        #expect(row.detail == "\(MainFormatting.bytes(1_000_000, locale: locale)) on this Mac")
        #expect(row.action?.title == "Remove")
        #expect(row.action?.intent == .removeSuggestionModel)
        #expect(row.action?.isDestructive == true)
    }
}
