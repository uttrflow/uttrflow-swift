import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("Diagnostics: the wait after release")
struct DiagnosticsWaitTests {
    @Test("shows p50 and p95 per dictation, how many ran past the target, and each cause's count")
    func showsPercentilesAndCauses() {
        let waits =
            [1, 2, 3].map { TimedWait(wait: DictationWait(wait: .seconds($0), spent: [:]), cause: nil) }
            + [
                TimedWait(wait: DictationWait(wait: .seconds(9), spent: [:]), cause: .fallbackDecode),
                TimedWait(wait: DictationWait(wait: .seconds(6), spent: [:]), cause: .fallbackDecode),
            ]

        let rows = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(waits: waits), locale: DiagnosticsFixture.locale
        ).waits

        #expect(
            rows.map(\.title) == [
                "Wait after release, p50 / p95", "Over the 4.00s target",
                "Decoding again at a higher temperature",
            ])
        #expect(rows.map(\.detail) == ["3.00s / 9.00s", "2 of 5 dictations", "2 dictations"])
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(waits: waits), locale: DiagnosticsFixture.locale)
        #expect(report.contains("Wait after release (5 dictations)"))
        #expect(report.contains("  Decoding again at a higher temperature: 2 dictations"))
    }

    @Test("shows nothing before a dictation is timed")
    func emptyUntilTimed() {
        #expect(DiagnosticsPresenter.page(for: DiagnosticsSnapshot()).waits.isEmpty)
    }
}
