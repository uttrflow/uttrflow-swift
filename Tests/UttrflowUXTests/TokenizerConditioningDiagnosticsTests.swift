// A decode without a tokenizer is recorded in the cleaning record and, once it persists, offers the repair.
import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("Tokenizer conditioning diagnostics")
struct TokenizerConditioningDiagnosticsTests {
    private let unconditioned = DecodeConditioning.unavailable(.tokenizerUnavailable)

    @Test("a cleaning record carries that the decode ran unconditioned, and merging keeps it")
    func recordCarriesConditioning() {
        let merged = CleaningRecord.merging([CleaningRecord(changes: []), .decoded(unconditioned)])
        #expect(merged.conditioning == unconditioned)
        #expect(!merged.isEmpty)
        #expect(CleaningRecord(changes: []).conditioning == .available)
    }

    @Test("the clean-up rows name an unconditioned decode")
    func rowNamesIt() {
        let rows = DiagnosticsPresenter.cleanUpRows(for: .decoded(unconditioned))
        #expect(rows.first?.title == "Recognition")
        #expect(rows.first?.state == .attention)
    }

    @Test("three unconditioned pieces in a row offer the repair, and two do not")
    func repairAfterThree() throws {
        func card(_ run: Int) throws -> DiagnosticsModelCard {
            let page = DiagnosticsPresenter.page(
                for: DiagnosticsSnapshot(
                    speechInUse: .whisperKit,
                    speechModel: DiagnosticsModelPresence(
                        isInstalled: true, bytesOnDisk: nil, isMultilingual: true),
                    speechReadiness: .ready, unconditionedRun: run),
                locale: DiagnosticsFixture.locale)
            return try #require(page.models.first { $0.title == "Speech" })
        }
        #expect(try card(2).status == "In use")
        #expect(try card(3).status == "Damaged")
    }
}
