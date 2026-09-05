// Tests for the menu bar's recent dictations.

import Foundation
import Testing

@testable import Uttrflow

// MARK: - Fixtures

/// A fixed instant. Nothing here reads the clock, so a slow machine cannot change a result.
private let recentsEpoch = Date(timeIntervalSince1970: 1_700_000_000)

private func recentsDictation(
    _ text: String, secondsLater: TimeInterval = 0, id: UUID = UUID(), app: String? = nil
) -> RecentDictation {
    RecentDictation(
        id: id, text: text, when: recentsEpoch.addingTimeInterval(secondsLater), applicationName: app)
}

/// Six, so that the fifth and sixth prove the cap from either side.
private let recentsSpokenLines = [
    "First thing I said.",
    "Second thing I said.",
    "Third thing I said.",
    "Fourth thing I said.",
    "Fifth thing I said.",
    "Sixth thing I said.",
]

private func recentsFilled(with lines: [String], capacity: Int? = nil) -> RecentDictations {
    var list = capacity.map { RecentDictations(capacity: $0) } ?? RecentDictations()
    for (index, line) in lines.enumerated() {
        list.add(recentsDictation(line, secondsLater: TimeInterval(index)))
    }
    return list
}

// MARK: - Tests

@Suite("Recent dictations")
struct RecentDictationsTests {
    @Test("A new list is empty and has nothing to preview")
    func startsEmpty() {
        let list = RecentDictations()
        #expect(list.entries.isEmpty)
        #expect(list.previews.isEmpty)
        #expect(list.capacity == RecentDictations.defaultCapacity)
    }

    @Test("The newest dictation comes first")
    func newestFirst() {
        let list = recentsFilled(with: Array(recentsSpokenLines.prefix(3)))
        #expect(
            list.entries.map(\.text) == [
                "Third thing I said.", "Second thing I said.", "First thing I said.",
            ])
    }

    @Test("The list holds five and no more")
    func capHolds() {
        let list = recentsFilled(with: recentsSpokenLines)
        #expect(list.entries.count == RecentDictations.defaultCapacity)
    }

    @Test("Going over the cap drops the oldest, not the newest")
    func dropsTheOldest() {
        let list = recentsFilled(with: recentsSpokenLines)
        #expect(list.entries.first?.text == "Sixth thing I said.")
        #expect(list.entries.last?.text == "Second thing I said.")
        #expect(!list.entries.contains { $0.text == "First thing I said." })
    }

    @Test("A capacity of none keeps nothing, rather than trapping")
    func zeroCapacityKeepsNothing() {
        let list = recentsFilled(with: recentsSpokenLines, capacity: 0)
        #expect(list.entries.isEmpty)
    }

    @Test("A nonsense capacity is clamped, not obeyed")
    func negativeCapacityIsClamped() {
        let list = recentsFilled(with: recentsSpokenLines, capacity: -3)
        #expect(list.capacity == 0)
        #expect(list.entries.isEmpty)
    }

    @Test("Clearing empties the list")
    func clearEmpties() {
        var list = recentsFilled(with: recentsSpokenLines)
        list.clear()
        #expect(list.entries.isEmpty)
        #expect(list.previews.isEmpty)
    }

    @Test("A preview carries the whole dictation, and its identity")
    func previewCarriesTheOriginal() {
        let identifier = UUID()
        var list = RecentDictations()
        let spoken = recentsDictation("Right, the drafting is done.", id: identifier, app: "Mail")
        list.add(spoken)

        let preview = list.previews.first
        #expect(preview?.id == identifier)
        #expect(preview?.dictation == spoken)
        #expect(preview?.dictation.applicationName == "Mail")
        #expect(preview?.dictation.when == recentsEpoch)
    }

    @Test("A dictation with nothing supplied still gets an identity of its own")
    func identitiesAreDistinctByDefault() {
        let first = RecentDictation(text: "One.", when: recentsEpoch)
        let second = RecentDictation(text: "One.", when: recentsEpoch)
        #expect(first.id != second.id)
        #expect(first.applicationName == nil)
    }

    @Test("A short line is shown whole")
    func shortLineIsUntouched() {
        #expect(RecentDictations.shortened("Running late.") == "Running late.")
    }

    @Test("Whitespace is collapsed onto one line")
    func whitespaceCollapses() {
        let ragged = "  Hey John,\n\n  I'll be\tlate.  "
        #expect(RecentDictations.shortened(ragged) == "Hey John, I'll be late.")
    }

    @Test("A long line is shortened to fit a menu")
    func longLineIsShortened() {
        let spoken = String(repeating: "word ", count: 40)
        let shortened = RecentDictations.shortened(spoken)
        #expect(shortened.count == 49)
        #expect(shortened.hasSuffix("…"))
        #expect(shortened.hasPrefix("word word"))
    }

    @Test("The cut never leaves a space before the ellipsis")
    func noSpaceBeforeTheEllipsis() {
        // Forty-eight characters of word, then the space that would land on the cut.
        let spoken = String(repeating: "a", count: 48) + " and more besides"
        let shortened = RecentDictations.shortened(spoken)
        #expect(shortened == String(repeating: "a", count: 48) + "…")

        // And with the limit moved so the cut falls squarely on a space.
        #expect(RecentDictations.shortened("aaa bbb", limit: 4) == "aaa…")
    }

    @Test("Built from the store, it shows the head of what it was handed")
    func showsWhatTheStoreHandedOver() {
        let stored = recentsSpokenLines.enumerated().map { index, line in
            recentsDictation(line, secondsLater: TimeInterval(index))
        }
        let list = RecentDictations(showing: stored)
        #expect(list.entries.count == RecentDictations.defaultCapacity)
        #expect(list.entries.map(\.text) == Array(recentsSpokenLines.prefix(5)))
    }

    /// The store owns the order; the menu must not have an opinion of its own.
    @Test("It shows the store's order rather than imposing one")
    func keepsTheStoresOrder() {
        let newest = recentsDictation("Said last.", secondsLater: 0)
        let older = recentsDictation("Said first.", secondsLater: 60)
        let list = RecentDictations(showing: [newest, older])
        #expect(list.entries.map(\.text) == ["Said last.", "Said first."])
    }

    @Test("Previews follow the order of the list")
    func previewsFollowTheList() {
        let list = recentsFilled(with: Array(recentsSpokenLines.prefix(2)))
        #expect(list.previews.map(\.title) == ["Second thing I said.", "First thing I said."])
    }
}
