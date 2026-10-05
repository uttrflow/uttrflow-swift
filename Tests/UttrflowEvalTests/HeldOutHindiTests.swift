import Testing

@testable import UttrflowCore
@testable import UttrflowEval

/// The held-out Devanagari set stays out of everything the romaniser was tuned on.
@Suite("The held-out Hindi set")
struct HeldOutHindiTests {
    /// Every word of the set, in the form the romaniser's table is keyed by.
    static let words: Set<String> = Set(
        HeldOutHindi.all.flatMap { sentence in
            sentence.devanagari.split(whereSeparator: { $0.isWhitespace || "।,?!.".contains($0) }).map(keyed)
        })

    static func keyed(_ word: some StringProtocol) -> String {
        String(String.UnicodeScalarView(Romaniser.normalised(Array(word.unicodeScalars))))
    }

    /// Table entries the set already shared when it was written; a new shared word means the table was tuned on it.
    static let sharedWhenWritten: Set<String> = Set(
        [
            "अच्छा", "अपना", "आएगा", "आएगी", "आज", "इसलिए", "उसकी", "एक", "और", "कंप्यूटर", "कभी", "कल", "का", "कि", "किया",
            "की", "कुछ", "के", "को", "कोई", "क्या", "गई", "गए", "गया", "चाय", "चार्ज", "ज़्यादा", "ठीक", "डॉक्टर", "था", "थी", "थोड़ी",
            "दस", "दो", "धन्यवाद", "नहीं", "नौ", "पता", "पर", "पहले", "फ़ोन", "फिर", "बहुत", "बात", "बाद", "भाई", "भी", "मुझे",
            "में", "मेरा", "मैं", "यह", "रहा", "रही", "लेकिन", "सकता", "से", "हम", "हमारी", "हमें", "हुआ", "हुई", "है", "हैं",
        ].map(keyed))

    @Test("holds at least thirty sentences and about four hundred words")
    func size() {
        #expect(HeldOutHindi.all.count >= 30)
        #expect(HeldOutHindi.all.reduce(0) { $0 + $1.devanagari.split(separator: " ").count } >= 300)
        #expect(Set(HeldOutHindi.all.map(\.id)).count == HeldOutHindi.all.count)
    }

    @Test("adds no table entry for a held-out word")
    func tableNotTunedOnIt() {
        let shared = Self.words.filter { Romaniser.commonSpellings[$0] != nil }
        #expect(shared.subtracting(Self.sharedWhenWritten).sorted() == [])
    }

    @Test("shares no sentence with the passages the rules were written against")
    func notInTuningPassages() {
        let tuning = TranscriptionCorpus.all.compactMap(\.devanagari).joined(separator: " ")
        for sentence in HeldOutHindi.all {
            #expect(!tuning.contains(sentence.devanagari), "\(sentence.id)")
        }
    }

    @Test("scores against the closest of several references")
    func bestOfReferences() throws {
        let score = try #require(
            RomanisationScore.measure([("x", ["a b", "c d"])], romanise: { _ in "c d" }))
        #expect(score.words == 1)
        #expect(RomanisationScore.measure([("x", [])], romanise: { $0 }) == nil)
    }
}
