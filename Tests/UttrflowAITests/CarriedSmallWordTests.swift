import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Small words that place or own a sentence are kept; a Devanagari draft keeps its word count.
@Suite("Carried small words and romanised word count")
struct CarriedSmallWordTests {
    private func accepted(_ spoken: String, _ rewritten: String) -> Bool {
        MeaningPreservationGuard().verdict(draft: Draft(text: spoken), rewritten: rewritten).isAccepted
    }

    @Test(
        "a rewrite that drops a time word, a demonstrative or a Hindi owner word is refused",
        arguments: [
            ("that was a good point", "Was a good point."),
            ("after the rain stopped", "The rain stopped."),
            ("bas that is all for today", "Bas, is all for today."),
            ("mera lucky number hai seven", "Lucky number hai seven."),
            ("bus mein khaali seats bachi hain sirf two", "Bus khaali seats bachi hain sirf two."),
        ])
    func refusesDrops(spoken: String, rewritten: String) {
        #expect(!accepted(spoken, rewritten))
    }

    @Test("a rewrite that keeps those words is accepted")
    func acceptsKept() {
        #expect(accepted("that was a good point", "That was a good point."))
        #expect(accepted("mera lucky number hai seven", "Mera lucky number hai seven."))
    }

    @Test("a Devanagari draft keeps its words, and a repeated false start may be written once")
    func devanagariWordCount() {
        let spoken = "इसे अंग्रेज़ी में बदल दो"
        #expect(
            MeaningPreservationGuard.scriptWordCountVerdict(original: spoken, rewritten: "Ise mein badal do.")
                != .accepted)
        #expect(
            MeaningPreservationGuard.scriptWordCountVerdict(
                original: spoken, rewritten: "Ise angrezi mein badal do. Also book it.") != .accepted)
        #expect(
            MeaningPreservationGuard.scriptWordCountVerdict(
                original: spoken, rewritten: "Ise angrezi mein badal do.") == .accepted)
        #expect(
            MeaningPreservationGuard.scriptWordCountVerdict(original: "वो वो bug", rewritten: "Wo bug.")
                == .accepted)
    }

    @Test("a Devanagari draft's words keep their order, a small word included")
    func devanagariWordOrder() {
        let spoken = "इसे अंग्रेज़ी में बदल दो"
        #expect(
            MeaningPreservationGuard.scriptWordOrderVerdict(
                original: spoken, rewritten: "Ise mein angrezi badal do.")
                != .accepted)
        #expect(
            MeaningPreservationGuard.scriptWordOrderVerdict(
                original: spoken, rewritten: "Ise angrezi mein badal do.") == .accepted)
    }

    @Test("two small words that trade places beside a word written as a mark are refused")
    func smallWordsSwappedBesideAMark() {
        let said = "a fixed fee of 12,500 dollars with delivery in four weeks"
        #expect(!accepted(said, "A fixed fee of $12,500 delivery with in four weeks."))
        #expect(accepted(said, "A fixed fee of $12,500 with delivery in four weeks."))
    }
}
