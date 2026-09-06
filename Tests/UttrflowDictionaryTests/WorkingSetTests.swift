// Tests for the working set.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowDictionary

@Suite("What to condition the recogniser with")
struct WorkingSetTests {
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
            WorkingSet.value(of: fresh, now: epoch, wanted: [])
                > WorkingSet.value(of: stale, now: epoch, wanted: []))
    }

    /// Half the value at the half-life, which is the only thing the constant means.
    @Test("halves what a word is worth every thirty days")
    func halfLife() {
        let new = word("New", from: .added)
        let month = word("Month", from: .added, daysAgo: WorkingSet.recencyHalfLifeInDays)
        #expect(WorkingSet.value(of: new, now: epoch, wanted: []) == 1)
        #expect(WorkingSet.value(of: month, now: epoch, wanted: []) == 0.5)
    }

    /// A clock that slipped backwards must not make the dictionary infinitely valuable.
    @Test("treats a word stamped in the future as merely new")
    func futureDates() {
        let future = word("Future", from: .added, daysAgo: -400)
        #expect(WorkingSet.value(of: future, now: epoch, wanted: []) == 1)
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
                of: word("kubectl"), now: epoch, wanted: WorkingSet.soundsOnScreen(in: selection))
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
}
