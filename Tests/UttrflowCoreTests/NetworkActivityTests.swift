import Foundation
import Testing

@testable import UttrflowCore

@Suite("The network-activity ledger")
struct NetworkActivityTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func days(_ count: Double) -> TimeInterval { count * 86_400 }

    /// Every stored property at every depth, by declared type.
    private func storedTypes(of value: Any, path: String = "") -> [(path: String, type: String)] {
        Mirror(reflecting: value).children.flatMap { child -> [(String, String)] in
            let childPath = path + "." + (child.label ?? "[]")
            let described = String(describing: type(of: child.value))
            return [(childPath, described)] + storedTypes(of: child.value, path: childPath)
        }
    }

    @Test("counts each purpose and keeps the latest moment")
    func countsByPurpose() {
        var activity = NetworkActivity.none
        activity.record(.account, at: start)
        activity.record(.account, at: start.addingTimeInterval(days(2)))
        activity.record(.updateCheck, at: start.addingTimeInterval(days(3)))

        let tallies = activity.tallies(at: start.addingTimeInterval(days(3)))
        #expect(tallies[.account] == NetworkTally(count: 2, last: start.addingTimeInterval(days(2))))
        #expect(tallies[.updateCheck]?.count == 1)
        #expect(tallies[.crashReport] == nil)
    }

    @Test("forgets a request once it is older than thirty days")
    func forgetsAfterTheWindow() {
        var activity = NetworkActivity.none
        activity.record(.modelDownload, at: start)
        #expect(activity.tallies(at: start.addingTimeInterval(days(29)))[.modelDownload]?.count == 1)
        #expect(activity.tallies(at: start.addingTimeInterval(days(31))).isEmpty)

        activity.record(.account, at: start.addingTimeInterval(days(31)))
        #expect(activity.days.allSatisfy { $0.purpose == .account })
    }

    @Test("holds only integers, dates and purposes, never text")
    func holdsNoText() {
        var activity = NetworkActivity.none
        for purpose in NetworkPurpose.allCases { activity.record(purpose, at: start) }
        let types = Set(storedTypes(of: activity).map(\.type))
        #expect(types.isSubset(of: ["Array<Day>", "Day", "NetworkPurpose", "Date", "Int", "Double"]))
        #expect(!types.contains { $0.contains("String") })
    }

    @Test("survives a relaunch through its file")
    func persists() throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "network-activity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        NetworkActivityLedger(file: file).record(.usageStatistics, at: start)
        let reopened = NetworkActivityLedger(file: file).activity()
        #expect(reopened.tallies(at: start)[.usageStatistics]?.count == 1)
    }
}
