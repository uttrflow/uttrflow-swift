// Tests that the prompt is bounded by the utterance.

import Foundation
import Testing

@testable import UttrflowDictionary

/// The guarantee made mechanical: the prompt is bounded by the utterance, never by the dictionary.
@Suite("The prompt is bounded by the utterance, not by the dictionary")
struct PromptSizeGuaranteeTests {
    /// The fixed utterance, with two of the user's words hidden in it and the recogniser unsure of both.
    private let utterance = Utterance(words: [
        SpokenWord(text: "email", confidence: 0.95),
        SpokenWord(text: "clawed", confidence: 0.31),
        SpokenWord(text: "about", confidence: 0.9),
        SpokenWord(text: "the", confidence: 0.99),
        SpokenWord(text: "payment", confidence: 0.42),
        SpokenWord(text: "sheet", confidence: 0.44),
    ])

    /// The ten entries a modest user has.
    private var real: [DictionaryEntry] {
        [
            word("Claude", from: .added, used: 12, id: fixedID(1)),
            word("PaymentSheet", from: .added, used: 9, id: fixedID(2)),
            word("Uttrflow", from: .added, used: 30, id: fixedID(3)),
            word("kubectl", from: .added, used: 7, id: fixedID(4)),
            word("PostgreSQL", from: .added, used: 6, id: fixedID(5)),
            word("setUserPrefs", from: .learned, used: 3, id: fixedID(6)),
            word("Nikhil", saying: "Nikeel", from: .added, used: 4, id: fixedID(7)),
            word("Siobhan", saying: "Shivawn", from: .added, used: 2, id: fixedID(8)),
            word("TestFlight", from: .observed, used: 5, id: fixedID(9)),
            word("Xcode", from: .added, used: 11, id: fixedID(10)),
        ]
    }

    private func fixedID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    /// Filler spelt in `B`, `V` and vowels only, so no filler entry can collide with the utterance.
    private func filler(_ count: Int) -> [DictionaryEntry] {
        (0..<count).map { number in
            let spelling = (0..<16)
                .map { bit in (number >> bit) & 1 == 0 ? "ba" : "va" }
                .joined()
            return word(spelling, from: .observed, used: number % 5, id: fixedID(1_000 + number))
        }
    }

    // MARK: The assertion

    /// Fifty thousand entries. The same six words. The same shortlist.
    @Test("returns an identical shortlist with fifty thousand words as with ten")
    func fiftyThousandEntriesChangeNothing() {
        let ten = real
        let fiftyThousand = real + filler(49_990)
        #expect(ten.count == 10)
        #expect(fiftyThousand.count == 50_000)

        let small = PhoneticIndex(entries: ten)
        let large = PhoneticIndex(entries: fiftyThousand)

        let fromTen = small.candidates(for: utterance)
        let fromFiftyThousand = large.candidates(for: utterance)

        #expect(fromTen == fromFiftyThousand)
        #expect(fromTen.map(\.word) == ["Claude", "PaymentSheet"])
        #expect(fromTen.count <= PhoneticIndex.defaultCandidateLimit)

        print(
            """
            GUARANTEE  dictionary 10 -> shortlist \(fromTen.count) \(fromTen.map(\.word))
            GUARANTEE  dictionary 50,000 -> shortlist \(fromFiftyThousand.count) \
            \(fromFiftyThousand.map(\.word))
            """)
    }

    /// The same, timed; a scan shows up as a factor of thousands, so the tolerance is loose on purpose.
    @Test("takes no longer to look a word up in fifty thousand than in ten")
    func lookupTimeDoesNotGrow() {
        let small = PhoneticIndex(entries: real)
        let large = PhoneticIndex(entries: real + filler(49_990))
        let repetitions = 2_000

        func time(_ index: PhoneticIndex) -> Duration {
            // One untimed pass so that neither measurement pays for a cold cache.
            _ = index.candidates(for: utterance)
            return ContinuousClock().measure {
                for _ in 0..<repetitions { _ = index.candidates(for: utterance) }
            }
        }

        let overTen = time(small)
        let overFiftyThousand = time(large)
        let ratio =
            Double(overFiftyThousand.components.attoseconds)
            / Double(max(1, overTen.components.attoseconds))

        print(
            """
            GUARANTEE  \(repetitions) lookups over 10 entries: \(overTen)
            GUARANTEE  \(repetitions) lookups over 50,000 entries: \(overFiftyThousand)
            GUARANTEE  ratio: \(String(format: "%.2f", ratio))×
            """)

        #expect(overFiftyThousand < overTen * 5 + .milliseconds(20))
    }

    /// Building the index costs the dictionary once; querying it never does.
    @Test("keeps every word, and still offers only a handful")
    func everyWordIsStillThere() {
        let large = PhoneticIndex(entries: real + filler(49_990))
        // The filler is reachable, so the shortlist is small because the lookup is selective.
        #expect(large.candidates(soundingLike: "bababababababababababababababab").isEmpty == false)
        #expect(large.candidates(for: utterance).count == 2)
    }

    /// The adversarial case: everything sounds like the spoken word, and the bucket cap holds.
    @Test("stays bounded even when every word in the dictionary sounds the same")
    func boundedEvenWhenEverythingCollides() {
        let homophones = (0..<50_000).map {
            word("Claude", from: .observed, used: $0, id: fixedID(2_000_000 + $0))
        }
        let index = PhoneticIndex(entries: homophones)
        #expect(index.candidates(soundingLike: "clawed").count == PhoneticIndex.maximumPerSound)
        #expect(index.candidates(for: utterance).count == PhoneticIndex.maximumPerSound)
    }

    /// The working set is a budget too, so the conditioning prompt cannot grow with the dictionary.
    @Test("keeps the conditioning prompt inside its budget at any size")
    func workingSetIsBounded() {
        let words = WorkingSet.words(from: real + filler(49_990), limit: 32, now: epoch)
        #expect(words.count == 32)
        #expect(WorkingSet.words(from: real, limit: 32, now: epoch).count == 10)
    }
}
