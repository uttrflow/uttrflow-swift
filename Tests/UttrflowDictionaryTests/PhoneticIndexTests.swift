// Tests for the phonetic index.

import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("Finding words by the sound of them")
struct PhoneticIndexTests {
    // MARK: Lookup

    /// The reason the index is keyed on sound: an entry has to be reachable from what was heard instead.
    @Test("the revision is equal for equal contents and moves when a word is added or used")
    func revisionFollowsTheContents() {
        let entry = word("Zorvex", from: .added)
        var used = entry
        used.timesUsed += 1
        let same = PhoneticIndex(entries: [entry]).revision
        #expect(PhoneticIndex(entries: [entry]).revision == same)
        #expect(PhoneticIndex(entries: [entry, word("Quillon", from: .learned)]).revision != same)
        #expect(PhoneticIndex(entries: [used]).revision != same)
        #expect(PhoneticIndex(entries: []).revision != same)
    }

    @Test("finds an entry from the word a recogniser heard instead")
    func findsByMishearing() {
        let index = PhoneticIndex(entries: [word("Claude", from: .added)])
        #expect(index.candidates(soundingLike: "clawed").map(\.word) == ["Claude"])
        #expect(index.candidates(soundingLike: "cloud").map(\.word) == ["Claude"])
        #expect(index.candidates(soundingLike: "kubectl").isEmpty)
    }

    @Test("finds accented Latin names from either spelling")
    func findsAccentedLatinNames() {
        let accented = PhoneticIndex(entries: [word("Émile", from: .added)])
        let plain = PhoneticIndex(entries: [word("Emile", from: .added)])

        #expect(accented.candidates(soundingLike: "Emile").map(\.word) == ["Émile"])
        #expect(plain.candidates(soundingLike: "Émile").map(\.word) == ["Emile"])
        #expect(
            PhoneticIndex(entries: [word("Müller", from: .added)])
                .candidates(soundingLike: "Muller").map(\.word) == ["Müller"])
    }

    /// Quotes or brackets a recogniser put around a word still find the entry the bare word would.
    @Test(
        "finds an entry when the heard word is quoted or bracketed",
        arguments: ["\"utterflow\"", "(utterflow)", "\u{201C}utterflow\u{201D}"])
    func findsThroughSurroundingMarks(heard: String) {
        let index = PhoneticIndex(entries: [word("Uttrflow", from: .added), word("Knight", from: .added)])
        #expect(index.candidates(soundingLike: heard).map(\.word) == ["Uttrflow"])
        #expect(index.candidates(soundingLike: "\"night\"").map(\.word) == ["Knight"])
    }

    /// A name spelt nothing like it is said is filed under the pronunciation.
    @Test("files a name under how it is said, not how it is written")
    func usesThePronunciation() {
        let index = PhoneticIndex(entries: [word("Siobhan", saying: "Shivawn", from: .added)])
        #expect(index.candidates(soundingLike: "Chevonne").map(\.word) == ["Siobhan"])
    }

    /// A pronunciation with a number word is found whether the recogniser writes the number as a word or a digit.
    @Test("finds a spoken-number pronunciation from a digit", arguments: ["s three", "S 3", "S3"])
    func findsSpokenNumberFromDigit(heard: String) {
        let index = PhoneticIndex(entries: [word("S3", saying: "s three", from: .added)])
        #expect(index.candidates(soundingLike: heard).map(\.word) == ["S3"])
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

    @Test("shows that four spoken pronunciation words cannot fit a lookup span")
    func fourWordPronunciationCannotMatch() {
        let entry = word("DBMS", saying: "dee bee em ess", from: .added)
        let index = PhoneticIndex(entries: [entry])
        let heard = Utterance(heard: "the dee bee em ess is down", confidence: 1)

        #expect(PhoneticIndex.wordCount(in: "dee bee em ess") == 4)
        #expect(index.candidates(for: heard).isEmpty)
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

    // MARK: - Every entry has an address

    /// The invariant: a word in the dictionary that nothing can look up is a word that does not work.
    @Test(
        "files every entry where its own spelling finds it",
        arguments: [
            "Uttrflow", "kubectl", "caf\u{00E9}", "2024", "\u{0930}\u{094B}\u{0939}\u{0928}",
            "\u{5317}\u{4EAC}", "\u{041C}\u{043E}\u{0441}\u{043A}\u{0432}\u{0430}",
        ])
    func everyEntryIsReachable(spelling: String) {
        let entry = word(spelling, from: .added)
        let index = PhoneticIndex(entries: [entry])

        #expect(index.candidates(soundingLike: spelling).map(\.id) == [entry.id])
        #expect(index.unaddressable.isEmpty)
    }

    /// A pronunciation is still what a user writes when the spelling misleads, and it still wins.
    @Test("keys on the pronunciation where there is one, whatever the spelling is")
    func pronunciationStillWins() {
        let entry = word("\u{0930}\u{094B}\u{0939}\u{0928}", saying: "Rohan", from: .added)
        let index = PhoneticIndex(entries: [entry])

        #expect(index.candidates(soundingLike: "rohan").map(\.id) == [entry.id])
        #expect(index.candidates(soundingLike: "\u{0930}\u{094B}\u{0939}\u{0928}").map(\.id) == [entry.id])
    }

    @Test("names an entry nothing can address rather than dropping it in silence")
    func namesWhatItCannotFile() {
        let unfilable = word("!!!", from: .added)
        let index = PhoneticIndex(entries: [unfilable, word("Uttrflow", from: .added)])

        #expect(index.unaddressable.map(\.word) == ["!!!"])
        #expect(index.candidates(soundingLike: "Uttrflow").count == 1)
    }

    /// The domain `DictionaryEntry` enforces means this subtraction can no longer overflow. See #1183.
    @Test("orders entries at the extremes of the counter domain without crashing")
    func ordersExtremeCountersWithoutCrashing() {
        let untouched = word("Uttrflow", from: .added, used: 0, reverted: .max)
        let heavilyUsed = word("Uttrflow", from: .added, used: .max, reverted: 0)
        #expect(PhoneticIndex.isMoreUseful(heavilyUsed, untouched))

        // Both share a sound and a bucket, so building the index sorts them by the same subtraction.
        let index = PhoneticIndex(entries: [untouched, heavilyUsed])
        #expect(index.candidates(soundingLike: "Uttrflow").map(\.id) == [heavilyUsed.id, untouched.id])
    }
}
