import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// Regression for issue 217: the user's own dictionary is exempt from the restraint the other two sources ask.
@Suite("A taught spelling is evidence, so DictionaryCandidates is exempt", .bug(id: 217))
struct DictionaryCandidatesRestraintExemptionTests {
    private static func index(_ words: [String]) -> PhoneticIndex {
        PhoneticIndex(
            entries: words.map {
                DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
            })
    }

    /// A mishearing a personal dictionary exists to repair rarely opens like the word: K for C, PH for F, a shifted vowel.
    @Test(
        "offers a taught spelling whose opening the mishearing lost",
        arguments: [
            ("cooper netties", "Kubernetes"), ("questral", "Kestrel"), ("arav", "Aarav"),
            ("fil", "Phil"),
        ]
    )
    func offersASpellingThatOpensDifferently(heard: String, taught: String) async {
        let source = DictionaryCandidates { Self.index([taught]) }
        let found = await source.candidates(for: Draft.Word(heard, evidence: .score(0.42)), in: .unknown)
        #expect(found.map(\.spelling) == [taught])
    }

    /// The source and the correction engine must answer the same question, or a spelling is applied and never offered.
    @Test("offers what the correction engine recalls for the same run")
    func answersTheEnginesQuestion() async {
        let dictionary = Self.index(["Kubernetes"])
        let source = DictionaryCandidates { dictionary }
        let found = await source.candidates(
            for: Draft.Word("cooper netties", evidence: .score(0.42)), in: .unknown)
        let engine = WordCorrectionEngine.spellings(of: "cooper netties", in: dictionary)
        #expect(
            found.map(\.spelling)
                == Array(engine.map(\.word).prefix(DictionaryCandidates.maximumOffered)))
        #expect(!found.isEmpty)
    }

    @Test("caps what one sound may offer, so it cannot spend a span's whole budget")
    func capsWhatItOffers() async {
        let words = ["Maude", "Madi", "Modo", "MDT", "Mito", "Motto", "Miti", "Mahdee"]
        let source = DictionaryCandidates { Self.index(words) }
        let found = await source.candidates(
            for: Draft.Word("made", evidence: .score(0.42)), in: .showing(title: "notes.txt"))
        #expect(found.count <= DictionaryCandidates.maximumOffered)
    }

    /// The cap is what keeps the exempt source from filling the line, since the restraint no longer thins it.
    @Test("asked first, it leaves room on the line for the restrained sources")
    func leavesRoomForTheOthers() async {
        let words = ["Modo", "MDT", "Midi", "Moda", "Mito"]
        let sources = DoubtfulWords.including(dictionary: { Self.index(words) })
        let spans = await sources.spans(
            in: .heard("i ?made a change", unsure: 0.42), for: .showing(title: "notes.txt"))
        let fromDictionary = spans.first?.candidates.filter { $0.entryID != nil } ?? []
        #expect(spans.count == 1)
        #expect(fromDictionary.count <= DictionaryCandidates.maximumOffered)
        #expect((spans.first?.candidates.count ?? 0) <= DoubtfulWords.maximumCandidatesPerSpan)
    }
}

/// Not a defect: a screen word differing only in case is the spelling decision the feature exists for.
@Suite("A case variant is a reading, and is offered once", .bug(id: 217))
struct CaseVariantReadingTests {
    /// "Aarav" over "arav" is a tier-one cleaning, so the capital a screen shows is a reading, not a duplicate.
    @Test("offers a screen word that differs from what was heard only in case")
    func offersACaseVariant() async {
        let found = await ScreenCandidates().candidates(
            for: Draft.Word("cache", evidence: .score(0.42)), in: .showing(title: "Cache"))
        #expect(found == ["Cache"])
    }

    @Test("the merge keeps that reading once, whatever cases the sources answered in")
    func mergeKeepsItOnce() {
        #expect(DoubtfulWords.merged([["Cache", "CACHE", "cached"]], heard: "cache") == ["Cache", "cached"])
    }
}
