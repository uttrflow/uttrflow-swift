// Tests for the working set.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowDictionary

@Suite("What to condition the recogniser with")
struct WorkingSetTests {
    /// A code with no sound, for scoring with nothing on screen.
    private static let silent = PhoneticCode(primary: "", alternate: "")

    private let xcode = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
        documentName: "PaymentSheet.swift")

    @Test("gives back the spellings, and nothing that could only be a token")
    func returnsSpellings() {
        let words = WorkingSet.words(
            from: [word("Nikhil", saying: "Nikeel", from: .added)], now: epoch)
        #expect(words == ["Nikhil"])
    }

    /// The prompt shares a few hundred tokens with everything else that conditions the decoder.
    @Test("never returns more than the budget allows")
    func respectsTheBudget() {
        let entries = (0..<200).map { word("Word\($0)", used: $0) }
        #expect(WorkingSet.words(from: entries, limit: 5, now: epoch).count == 5)
        #expect(WorkingSet.words(from: entries, now: epoch).count == WorkingSet.defaultLimit)
        #expect(WorkingSet.words(from: entries, limit: 0, now: epoch).isEmpty)
    }

    /// Frequency counts the uses that stuck.
    @Test("prefers the words the user keeps over the words the user undoes")
    func frequency() {
        let kept = word("Kept", from: .added, used: 9, daysAgo: 10)
        let undone = word("Undone", from: .added, used: 9, reverted: 4, daysAgo: 10)
        #expect(WorkingSet.words(from: [undone, kept], now: epoch) == ["Kept", "Undone"])
    }

    @Test("prefers a word learned this week to one learned last year")
    func recency() {
        let fresh = word("Fresh", from: .added, daysAgo: 1)
        let stale = word("Stale", from: .added, daysAgo: 400)
        #expect(WorkingSet.words(from: [stale, fresh], now: epoch) == ["Fresh", "Stale"])
        #expect(
            WorkingSet.value(of: fresh, sounding: Self.silent, now: epoch, wanted: [])
                > WorkingSet.value(of: stale, sounding: Self.silent, now: epoch, wanted: []))
    }

    @Test("puts a word added this week ahead of older words used often")
    func recentAdditionPriority() {
        let recent = word("Maelis", from: .added, daysAgo: 1)
        let older = (0..<40).map { word("Older\($0)", from: .learned, used: 1, daysAgo: 10) }

        let ranked = WorkingSet.words(from: older + [recent], now: epoch)

        #expect(ranked.first == "Maelis")
    }

    /// Half the value at the half-life, which is the only thing the constant means.
    @Test("halves what a word is worth every thirty days")
    func halfLife() {
        let new = word("New", from: .added)
        let month = word("Month", from: .added, daysAgo: WorkingSet.recencyHalfLifeInDays)
        #expect(WorkingSet.value(of: new, sounding: Self.silent, now: epoch, wanted: []) == 1)
        #expect(WorkingSet.value(of: month, sounding: Self.silent, now: epoch, wanted: []) == 0.5)
    }

    /// A clock that slipped backwards must not make the dictionary infinitely valuable.
    @Test("treats a word stamped in the future as merely new")
    func futureDates() {
        let future = word("Future", from: .added, daysAgo: -400)
        #expect(WorkingSet.value(of: future, sounding: Self.silent, now: epoch, wanted: []) == 1)
    }

    /// Dictating into `PaymentSheet.swift` pulls `PaymentSheet` up, through the same phonetics as speech.
    @Test("favours the words the app being dictated into is showing")
    func affinityWithTheFrontmostApp() {
        let relevant = word("PaymentSheet", from: .added, daysAgo: 200)
        let popular = word("Uttrflow", from: .added, used: 50, daysAgo: 200)
        #expect(WorkingSet.words(from: [popular, relevant], now: epoch) == ["Uttrflow", "PaymentSheet"])
        #expect(
            WorkingSet.words(from: [popular, relevant], now: epoch, favouring: xcode)
                == ["PaymentSheet", "Uttrflow"])
    }

    @Test("hears the app's own words through the same phonetics as everything else")
    func affinityIsPhonetic() {
        let misspelt = AppContext(applicationName: "Slack", documentName: "Nikhel Sharma")
        let sounds = WorkingSet.soundsOnScreen(in: misspelt)
        #expect(sounds.contains("NKL"))
        #expect(WorkingSet.soundsOnScreen(in: .unknown).isEmpty)
        #expect(
            WorkingSet.words(from: [word("Nikhil", from: .added)], now: epoch, favouring: misspelt)
                == ["Nikhil"])
    }

    /// Selected text is on screen too, and often the most specific part of it.
    @Test("reads the selection as well as the app and the document")
    func affinityReadsTheSelection() {
        let selection = AppContext(selectedText: "cube cattle")
        #expect(
            WorkingSet.value(
                of: word("kubectl"), sounding: DoubleMetaphone.code(for: "kubectl"), now: epoch,
                wanted: WorkingSet.soundsOnScreen(in: selection))
                > WorkingSet.affinityWeight)
    }

    /// Conditioning a decoder towards a word the user keeps undoing would teach it the mistake.
    @Test("never conditions the recogniser with a word that has retired itself")
    func retiredWordsAreExcluded() {
        let retired = word("Wrong", from: .learned, used: 20, reverted: 19)
        #expect(retired.isTrustworthy == false)
        #expect(WorkingSet.words(from: [retired], now: epoch).isEmpty)
    }

    /// Equal words come back in the same order every run, and in the index's order.
    @Test("breaks a tie the same way the index does")
    func tiesAreBrokenLikeTheIndex() {
        let alpha = word("Alpha", from: .added, used: 4, daysAgo: 3)
        let beta = word("Beta", from: .added, used: 4, daysAgo: 3)
        #expect(WorkingSet.words(from: [beta, alpha], now: epoch) == ["Alpha", "Beta"])
    }

    /// The domain `DictionaryEntry` enforces means this subtraction can no longer overflow. See #1183.
    @Test("ranks a readable entry at the extremes of the counter domain without crashing")
    func ranksExtremeCountersWithoutCrashing() {
        let untouched = word("Untouched", from: .added, used: 0, reverted: .max)
        let heavilyUsed = word("HeavilyUsed", from: .added, used: .max, reverted: 0)
        let words = WorkingSet.words(from: [untouched, heavilyUsed], now: epoch)
        #expect(words == ["HeavilyUsed", "Untouched"])
    }

    @Test(
        "explains every standing an entry can have",
        arguments: [
            ("In", WorkingSet.Standing.inPrompt(rank: 1)),
            ("Past", .belowLimit(rank: 3, limit: 2)),
            ("Nicole", .sharesSound(with: "Nikhil")),
            ("Wrong", .retired),
            ("Stale", .unusedInferred),
            ("Huge", .tooLong(rank: 2)),
        ])
    func explainsEachStanding(spelling: String, expected: WorkingSet.Standing) {
        let entries = [
            word("In", from: .added, used: 9),
            word("Huge", from: .added, used: 8),
            word("Past", from: .added, used: 1, daysAgo: 20),
            word("Nikhil", from: .added, used: 5, daysAgo: 400),
            word("Nicole", from: .added, used: 1, daysAgo: 400),
            word("Wrong", from: .learned, used: 20, reverted: 19),
            word("Stale", from: .observed, daysAgo: 45),
        ]
        let standings = WorkingSet.explain(entries: entries, limit: 2, now: epoch, packed: ["In"])
        let entry = entries.first { $0.word == spelling }
        #expect(entry.flatMap { standings[$0.id] } == expected)
    }

    @Test("marks in the prompt exactly the words it offers, for any dictionary")
    func explainAgreesWithWords() {
        var generator = SystemRandomNumberGenerator()
        let origins = WordOrigin.allCases
        for _ in 0..<200 {
            let entries = (0..<Int.random(in: 0...60, using: &generator)).map { index in
                word(
                    "Word\(index)x\(Int.random(in: 0...9, using: &generator))",
                    from: origins.randomElement(using: &generator) ?? .added,
                    used: Int.random(in: 0...12, using: &generator),
                    reverted: Int.random(in: 0...6, using: &generator),
                    daysAgo: Double.random(in: 0...90, using: &generator))
            }
            let limit = Int.random(in: 0...30, using: &generator)
            let standings = WorkingSet.explain(entries: entries, limit: limit, now: epoch)
            let offered = entries.filter { standings[$0.id]?.isOffered == true }.map(\.word)
            let words = WorkingSet.words(from: entries, limit: limit, now: epoch)
            #expect(Set(offered) == Set(words))
            #expect(offered.count == words.count)
            #expect(standings.count == entries.count)
        }
    }

    @Test("ranking an unchanged dictionary against its index encodes only what is on screen")
    func indexedRankingEncodesOnlyTheScreen() {
        let entries = (0..<1_000).map { word("Word\($0)", used: $0 % 7) }
        let index = PhoneticIndex(entries: entries)
        let onScreen = AppContext(applicationName: "Notes", documentName: "Plan")
        let tally = EncodingTally()
        let words = DoubleMetaphone.$tally.withValue(tally) {
            WorkingSet.words(from: entries, coded: index, now: epoch, favouring: onScreen)
        }
        #expect(words == WorkingSet.words(from: entries, now: epoch, favouring: onScreen))
        #expect(tally.count < 10)
    }
}
