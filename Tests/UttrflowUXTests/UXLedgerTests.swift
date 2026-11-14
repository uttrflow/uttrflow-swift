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
        record(.onboardingPage(1), 6)
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
        #expect(store.load(asOf: at(500), calendar: Self.calendar) == scriptedDay())
        try store.reset()
        #expect(store.load() == nil)
    }

    /// The declared type of each stored property of `value`, read by reflection.
    private func names(_ value: Any) -> [String] {
        Mirror(reflecting: value).children.map { String(describing: type(of: $0.value)) }
    }

    /// The declared type of every stored property of the ledger and of each of its days.
    private func storedTypes(of ledger: UXLedger) -> [String] {
        names(ledger) + (ledger.days + [UXDay(number: 0)]).flatMap { names($0) }
    }

    /// Types in `types` that are not on the explicit list of what the ledger may hold.
    private func unlisted(_ types: [String]) -> [String] {
        let allowed: Set = [
            "Int", "Double", "Date", "Optional<Date>", "Optional<Int>", "UXOutcome", "UXLanding",
            "Array<UXDay>", "Dictionary<UXOutcome, Int>", "Dictionary<UXLanding, Int>",
        ]
        return types.filter { !allowed.contains($0) }
    }

    @Test("the stored types are only integers, dates, doubles and closed enumerations")
    func noText() {
        #expect(unlisted(storedTypes(of: scriptedDay())) == [])
        #expect(unlisted(storedTypes(of: UXLedger(installedOn: start))) == [])
    }

    private struct TextPayload { var note = "" }

    private struct EmptyTextHolders {
        var items: [TextPayload] = []
        var maybe: TextPayload?
    }

    @Test("the privacy check refuses an empty container and a nil optional of a text-bearing type")
    func noTextCheckRefusesUnknownContainers() {
        let reflected = names(EmptyTextHolders())
        #expect(reflected.count == 2)
        #expect(unlisted(reflected).count == 2)
    }

    @Test("a day number follows local midnight in a zone away from UTC")
    func localMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3_600 + 1_800) ?? .gmt
        var ledger = UXLedger(installedOn: start)
        let local =
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 50)) ?? start
        ledger.record(.started, at: local, calendar: calendar)
        ledger.record(.started, at: local.addingTimeInterval(1_200), calendar: calendar)
        #expect(ledger.days.count == 2)
        ledger.record(.started, at: local.addingTimeInterval(-86_400), calendar: calendar)
        #expect(ledger.days.count == 3)
    }

    @Test("a retry across midnight is counted on the day of the cancel and leaves with it")
    func retryAcrossMidnight() {
        var ledger = UXLedger(installedOn: start)
        let cal = Self.calendar
        let midnight = cal.startOfDay(for: start).addingTimeInterval(86_400)
        ledger.record(.started, at: midnight.addingTimeInterval(-30), calendar: cal)
        ledger.record(.ended(.cancelled), at: midnight.addingTimeInterval(-20), calendar: cal)
        ledger.record(.started, at: midnight.addingTimeInterval(10), calendar: cal)
        #expect(ledger.days.first?.retries == 1)
        #expect(ledger.figures.abandonment == 0)
        ledger.record(.ended(.failed), at: midnight.addingTimeInterval(20), calendar: cal)
        ledger.record(
            .started, at: midnight.addingTimeInterval(86_400 * Double(UXLedger.daysKept - 1)), calendar: cal)
        #expect(ledger.days.first?.retries == 0)
        #expect(ledger.figures.abandonment == 0.5)
    }

    @Test("a ledger reopened after a long idle drops its stale days on load")
    func loadPrunes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ux-ledger-\(UUID().uuidString)/ledger.json")
        let store = UXLedgerStore(url: url)
        try store.save(scriptedDay())
        let later = start.addingTimeInterval(86_400 * Double(UXLedger.daysKept + 5))
        #expect(store.load(asOf: later, calendar: Self.calendar)?.figures.started == 0)
        try store.reset()
    }
}
