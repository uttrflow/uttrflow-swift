// Tests for the phonetic index.

import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("Finding words by the sound of them")
struct PhoneticIndexTests {
    // MARK: Lookup

    /// The reason the index is keyed on sound: an entry has to be reachable from what was heard instead.
    @Test("finds an entry from the word a recogniser heard instead")
    func findsByMishearing() {
        let index = PhoneticIndex(entries: [word("Claude", from: .added)])
        #expect(index.candidates(soundingLike: "clawed").map(\.word) == ["Claude"])
        #expect(index.candidates(soundingLike: "cloud").map(\.word) == ["Claude"])
        #expect(index.candidates(soundingLike: "kubectl").isEmpty)
    }

    /// A name spelt nothing like it is said is filed under the pronunciation.
    @Test("files a name under how it is said, not how it is written")
    func usesThePronunciation() {
        let index = PhoneticIndex(entries: [word("Siobhan", saying: "Shivawn", from: .added)])
        #expect(index.candidates(soundingLike: "Chevonne").map(\.word) == ["Siobhan"])
    }

    /// A word with two readings is filed under both, found from either, and comes back once.
    @Test("finds a word with two readings from either of them, once")
    func ambiguousWords() {
        let index = PhoneticIndex(entries: [word("Gemma", from: .added)])
        #expect(index.candidates(soundingLike: "Jemma").map(\.word) == ["Gemma"])
        #expect(index.candidates(soundingLike: "Kemma").map(\.word) == ["Gemma"])
        #expect(index.candidates(soundingLike: "Gemma").count == 1)
    }

    /// An entry whose spelling makes no sound cannot become the bucket every soundless entry falls into.
    @Test("files nothing under a word that makes no sound")
    func soundlessEntries() {
        let index = PhoneticIndex(entries: [word("2024", from: .added), word("Claude")])
        #expect(index.candidates(soundingLike: "1999").isEmpty)
        #expect(index.candidates(soundingLike: "clawed").map(\.word) == ["Claude"])
    }

    // MARK: Retirement

    /// A retired entry is still in the store and still shown, but stops being offered.
    @Test("stops offering an entry that has retired itself")
    func retiredEntriesAreNotOffered() {
        let retired = word("Claude", used: 10, reverted: 9)
        #expect(retired.isTrustworthy == false)
        #expect(PhoneticIndex(entries: [retired]).candidates(soundingLike: "clawed").isEmpty)
        #expect(
            PhoneticIndex(entries: [word("Claude", used: 10, reverted: 1)])
                .candidates(soundingLike: "clawed").count == 1)
    }

    // MARK: Bounded buckets

    /// Without a cap, a sound thousands of entries share would turn one probe into a scan.
    @Test("keeps a bounded number of entries for any one sound")
    func bucketsAreCapped() {
        let homophones = (0..<200).map { word("Claude", used: $0) }
        let index = PhoneticIndex(entries: homophones)
        #expect(index.candidates(soundingLike: "clawed").count == PhoneticIndex.maximumPerSound)
    }

    /// Which eight survive is not arbitrary: the ones the user actually keeps.
    @Test("keeps the most useful entries when a sound is crowded")
    func bucketKeepsTheBest() {
        let entries = (0..<20).map { word("Claude", used: $0, reverted: 0, daysAgo: Double($0)) }
        let kept = PhoneticIndex(entries: entries).candidates(soundingLike: "Claude")
        #expect(kept.map(\.timesUsed) == [19, 18, 17, 16, 15, 14, 13, 12])
    }

    /// Uses the user undid do not count towards keeping a slot.
    @Test("ranks by the uses that stuck, then by newness, then by spelling, then by identity")
    func rankingIsATotalOrder() {
        let noisy = word("Claude", used: 50, reverted: 49)
        let quiet = word("Klaude", used: 2)
        #expect(PhoneticIndex.isMoreUseful(quiet, noisy))

        let older = word("Claude", daysAgo: 10)
        let newer = word("Claude", daysAgo: 1)
        #expect(PhoneticIndex.isMoreUseful(newer, older))

        let alphabetical = word("Alpha", daysAgo: 1)
        let later = word("Beta", daysAgo: 1)
        #expect(PhoneticIndex.isMoreUseful(alphabetical, later))

        let sameA = word("Claude", daysAgo: 1)
        let sameB = word("Claude", daysAgo: 1)
        #expect(PhoneticIndex.isMoreUseful(sameA, sameB) == (sameA.id.uuidString < sameB.id.uuidString))
    }

    // MARK: An utterance

    /// Runs of words, not just words, because entries are written closed and spoken open.
    @Test("finds a closed-up entry from the words it was spoken as")
    func findsCamelCasedEntriesFromSpeech() {
        let index = PhoneticIndex(entries: [
            word("PaymentSheet", from: .added), word("setUserPrefs", from: .added),
        ])
        let heard = Utterance(heard: "open the payment sheet and set user prefs", confidence: 0.4)
        #expect(Set(index.candidates(for: heard).map(\.word)) == ["PaymentSheet", "setUserPrefs"])
    }

    @Test("offers nothing for an utterance with nothing of the user's in it")
    func nothingRelevant() {
        let index = PhoneticIndex(entries: [word("Claude", from: .added)])
        #expect(index.candidates(for: Utterance(heard: "back in ten minutes", confidence: 1)).isEmpty)
    }

    /// A caller that asks for nothing gets nothing, rather than a cap that never bites.
    @Test("offers nothing when there is no budget to offer it in")
    func zeroBudget() {
        let index = PhoneticIndex(entries: [word("Claude", from: .added)])
        #expect(index.candidates(for: Utterance(heard: "clawed", confidence: 0.1), limit: 0).isEmpty)
    }

    /// The budget is spent on the words the recogniser was least sure of.
    @Test("spends a small budget on the least certain word")
    func budgetGoesToTheLeastCertainWord() {
        let index = PhoneticIndex(entries: [
            word("Claude", from: .added), word("Uttrflow", from: .added),
        ])
        let heard = Utterance(words: [
            SpokenWord(text: "utterflow", confidence: 0.95),
            SpokenWord(text: "clawed", confidence: 0.1),
        ])
        #expect(index.candidates(for: heard, limit: 1).map(\.word) == ["Claude"])
        #expect(Set(index.candidates(for: heard, limit: 2).map(\.word)) == ["Claude", "Uttrflow"])
    }

    /// The same words must always produce the same shortlist, or the guarantee cannot be asserted.
    @Test("answers the same utterance the same way every time")
    func answersAreStable() {
        let index = PhoneticIndex(entries: (0..<40).map { word("Claude\($0 % 3)", used: $0) })
        let heard = Utterance(heard: "clawed cloud one", confidence: 0.3)
        #expect(index.candidates(for: heard) == index.candidates(for: heard))
    }
}
