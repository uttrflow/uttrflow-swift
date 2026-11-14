import Foundation
import Testing

@testable import UttrflowUX

@Suite("The local UX ledger")
struct UXLedgerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A scripted day: one clean dictation, one cancel that is retried at once, one cancel left, one undo.
    private func scriptedDay() -> UXLedger {
        var ledger = UXLedger(installedOn: start)
        func record(_ event: UXEvent, _ seconds: TimeInterval) {
            ledger.record(event, at: at(seconds), calendar: Self.calendar)
        }
        record(.started, 10)
        record(.landed(milliseconds: 400), 12)
        record(.ended(.inserted), 12)
        record(.started, 100)
        record(.ended(.cancelled), 102)
        record(.started, 120)
        record(.ended(.inserted), 125)
        record(.started, 300)
        record(.ended(.cancelled), 301)
        record(.undone, 400)
        record(.onboardingPage(3), 5)
        return ledger
    }

    @Test("time to first text runs from the first press to the first confirmed insert")
    func timeToFirstText() {
        #expect(scriptedDay().figures.timeToFirstText == 2)
    }

    @Test("abandonment counts cancels not retried within sixty seconds, over starts")
    func abandonment() {
        let figures = scriptedDay().figures
        #expect(figures.started == 4)
        #expect(figures.abandonment == 0.25)
    }

    @Test("a retry after the window is not a retry")
    func lateRetry() {
        var ledger = UXLedger(installedOn: start)
        ledger.record(.started, at: at(0), calendar: Self.calendar)
        ledger.record(.ended(.failed), at: at(1), calendar: Self.calendar)
        ledger.record(.started, at: at(80), calendar: Self.calendar)
        #expect(ledger.figures.abandonment == 0.5)
    }

    @Test("undos and landing buckets are counted")
    func undosAndLandings() {
        let figures = scriptedDay().figures
        #expect(figures.undos == 1)
        #expect(figures.landings == [.under500ms: 1])
        #expect(UXLanding(milliseconds: 249) == .under250ms)
        #expect(UXLanding(milliseconds: 2_000) == .over2s)
    }

    @Test("onboarding keeps the furthest page reached")
    func onboarding() {
        #expect(scriptedDay().onboardingPagesReached == 3)
    }

    @Test("only the last thirty days are kept")
    func rolling() {
        var ledger = UXLedger(installedOn: start)
        for day in 0..<40 {
            ledger.record(.started, at: at(Double(day) * 86_400), calendar: Self.calendar)
        }
        #expect(ledger.days.count == UXLedger.daysKept)
        #expect(ledger.figures.started == UXLedger.daysKept)
    }

    @Test("the ledger survives a relaunch and is gone after Reset")
    func persistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ux-ledger-\(UUID().uuidString)/ledger.json")
        let store = UXLedgerStore(url: url)
        try store.save(scriptedDay())
        #expect(store.load() == scriptedDay())
        try store.reset()
        #expect(store.load() == nil)
    }

    /// Every stored property at every depth, by declared type.
    private func storedTypes(of value: Any) -> [String] {
        Mirror(reflecting: value).children.flatMap { child -> [String] in
            [String(describing: type(of: child.value))] + storedTypes(of: child.value)
        }
    }

    @Test("the stored type holds only integers, dates, doubles and closed enumerations")
    func noText() {
        let allowed = ["Int", "Bool", "Double", "Date", "UXOutcome", "UXLanding", "UXDay", "Optional<Date>"]
        let types = storedTypes(of: scriptedDay())
        #expect(!types.contains { $0.contains("String") })
        let words = types.filter { type in
            !allowed.contains(type) && !type.hasPrefix("Array<") && !type.hasPrefix("Dictionary<")
                && !type.hasPrefix("(") && !type.hasPrefix("Optional<") && !type.hasPrefix("_")
                && !type.hasPrefix("Element") && !type.contains("Index")
        }
        #expect(words.isEmpty, "unexpected stored types: \(words)")
    }
}
