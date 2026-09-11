import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// Regression for issue 217, the second candidate source: the same restraint, stated once and asked here too.
@Suite("Issue 217 sweep: DictionaryCandidates asks the same restraint")
struct Issue217SweepTests {
    private static func index(_ words: [String]) -> PhoneticIndex {
        PhoneticIndex(
            entries: words.map {
                DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
            })
    }

    @Test("refuses a dictionary word that only collides on the sound key")
    func refusesACollidingEntry() async {
        let source = DictionaryCandidates { Self.index(["Modo", "MDT", "Kubernetes"]) }
        let found = await source.candidates(
            for: Draft.Word("made", confidence: 0.42), in: .showing(title: "notes.txt"))
        #expect(found.isEmpty)
    }

    @Test("still offers the user's own spelling of what they said")
    func keepsTheUsersSpelling() async {
        let source = DictionaryCandidates { Self.index(["PaymentSheet", "Kestrel"]) }
        let sheet = await source.candidates(
            for: Draft.Word("payment sheet", confidence: 0.42), in: .unknown)
        let kestrel = await source.candidates(
            for: Draft.Word("kestral", confidence: 0.42), in: .unknown)
        #expect(sheet == ["PaymentSheet"])
        #expect(kestrel == ["Kestrel"])
    }

    @Test("caps what one sound may offer, so it cannot spend a span's whole budget")
    func capsWhatItOffers() async {
        let words = ["Maude", "Madi", "Modo", "MDT", "Mito", "Motto", "Miti", "Mahdee"]
        let source = DictionaryCandidates { Self.index(words) }
        let found = await source.candidates(
            for: Draft.Word("made", confidence: 0.42), in: .showing(title: "notes.txt"))
        #expect(found.count <= DictionaryCandidates.maximumOffered)
    }

    @Test("asked first, it can no longer crowd the restrained sources out")
    func doesNotCrowdTheOthersOut() async {
        let words = ["Modo", "MDT", "Midi", "Moda", "Mito"]
        let sources = DoubtfulWords.including(dictionary: { Self.index(words) })
        let spans = await sources.spans(
            in: .heard("i ?made a change", unsure: 0.42), for: .showing(title: "notes.txt"))
        #expect(spans.isEmpty)
    }
}

/// Not a defect: a screen word differing only in case is the spelling decision the feature exists for.
@Suite("Issue 217 sweep: a case variant is a reading, and is offered once")
struct Issue217CaseSweepTests {
    /// "Aarav" over "arav" is a tier-one cleaning, so the capital a screen shows is a reading, not a duplicate.
    @Test("offers a screen word that differs from what was heard only in case")
    func offersACaseVariant() async {
        let found = await ScreenCandidates().candidates(
            for: Draft.Word("cache", confidence: 0.42), in: .showing(title: "Cache"))
        #expect(found == ["Cache"])
    }

    @Test("the merge keeps that reading once, whatever cases the sources answered in")
    func mergeKeepsItOnce() {
        #expect(DoubtfulWords.merged([["Cache", "CACHE", "cached"]], heard: "cache") == ["Cache", "cached"])
    }
}
