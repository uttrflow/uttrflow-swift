import Testing
import UttrflowHistory

@testable import UttrflowUX

@Suite("Diagnostics: where kept dictations arrived")
struct DiagnosticsArrivalTests {
    @Test("kept dictations are counted by arrival, and the report says how many never arrived")
    func countsKeptDictationsByArrival() {
        let snapshot = DiagnosticsSnapshot(arrivals: [.confirmed, .notInserted, .notInserted, nil])

        let rows = DiagnosticsPresenter.page(for: snapshot, locale: DiagnosticsFixture.locale).arrivals
        let report = DiagnosticsPresenter.report(for: snapshot)

        #expect(
            rows.map(\.title) == [
                "Confirmed in the field", "Not inserted", "Kept before arrivals were recorded",
            ])
        #expect(rows.map(\.detail) == ["1 dictation", "2 dictations", "1 dictation"])
        #expect(report.contains("  Not inserted: 2 dictations"))
    }

    @Test("with nothing kept the page has no arrival rows and the report says so")
    func nothingKeptHasNoRows() {
        let snapshot = DiagnosticsSnapshot()

        #expect(DiagnosticsPresenter.page(for: snapshot, locale: DiagnosticsFixture.locale).arrivals.isEmpty)
        #expect(DiagnosticsPresenter.report(for: snapshot).contains("Arrival: no dictations kept"))
    }
}
