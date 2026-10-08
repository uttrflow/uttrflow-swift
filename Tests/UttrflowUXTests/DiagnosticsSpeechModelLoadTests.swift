import Foundation
import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("Diagnostics: speech model load")
struct DiagnosticsSpeechModelLoadTests {
    private var loads: [SpeechModelLoadRecord] {
        var history = SpeechModelLoadHistory()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        history.append(
            date: start, seconds: 2, parts: nil, systemBuild: "25A100", modelRevision: "0123456789abc")
        history.append(
            date: start.addingTimeInterval(3600), seconds: 75, parts: nil, systemBuild: "25B200",
            modelRevision: "0123456789abc")
        return history.records
    }

    @Test("The page lists each kept load newest first, with its macOS build, model revision and reason.")
    func pageListsLoads() {
        let rows = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(speechModelLoads: loads), locale: DiagnosticsFixture.locale
        ).speechModelLoads
        #expect(
            rows.map(\.detail) == [
                "75.00s, macOS 25B200, model 0123456, macOS updated, slow expected, likely recompile",
                "2.00s, macOS 25A100, model 0123456, first load recorded, slow expected",
            ])
    }

    @Test("The copied report carries the same load lines, and says when none is recorded.")
    func reportCarriesLoads() {
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(speechModelLoads: loads), locale: DiagnosticsFixture.locale)
        #expect(report.contains("Speech model load\n"))
        #expect(
            report.contains("macOS 25B200, model 0123456, macOS updated, slow expected, likely recompile"))
        #expect(
            DiagnosticsPresenter.report(for: DiagnosticsSnapshot()).contains(
                "Speech model load: none recorded yet"))
    }

    @Test("Every reason reads as words.")
    func reasons() {
        let record = { (change: SpeechModelLoadChange) in
            SpeechModelLoadRecord(
                date: .distantPast, seconds: 1, parts: nil, systemBuild: "b", modelRevision: "r",
                change: change,
                isLikelyRecompile: false)
        }
        #expect(
            SpeechModelLoadChange.allCases.map { DiagnosticsPresenter.reason(for: record($0)) } == [
                "first load recorded, slow expected", "nothing changed", "macOS updated, slow expected",
                "model changed, slow expected",
            ])
    }
}
