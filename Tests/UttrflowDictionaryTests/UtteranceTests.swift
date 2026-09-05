// Tests for utterances and their runs of words.

import Testing

@testable import UttrflowDictionary

@Suite("What one utterance offers the dictionary")
struct UtteranceTests {
    /// A negative confidence would sort itself to the front and take the whole candidate budget.
    @Test("takes a confidence it can rely on, whatever it was handed")
    func confidenceIsClamped() {
        #expect(SpokenWord(text: "clawed", confidence: -3).confidence == 0)
        #expect(SpokenWord(text: "clawed", confidence: 4).confidence == 1)
        #expect(SpokenWord(text: "clawed", confidence: 0.4).confidence == 0.4)
    }

    @Test("can be built from a whole transcript scored in one piece")
    func fromATranscript() {
        let utterance = Utterance(heard: "  ask   clawed  ", confidence: 0.5)
        #expect(utterance.words.map(\.text) == ["ask", "clawed"])
        #expect(utterance.words.allSatisfy { $0.confidence == 0.5 })
        #expect(Utterance(heard: "   ", confidence: 1).words.isEmpty)
    }

    /// Nobody dictates "PaymentSheet" as one word, so single-word lookups miss every camel-cased entry.
    @Test("offers the runs of words a closed-up entry is spoken as")
    func runsOfWords() {
        let utterance = Utterance(heard: "set user prefs", confidence: 0.5)
        let spans = Set(utterance.spans(upTo: 3).map(\.text))
        #expect(spans == ["set", "user", "prefs", "set user", "user prefs", "set user prefs"])
    }

    /// The count of runs is a function of the utterance alone, the arithmetic the guarantee is built on.
    @Test("offers a number of runs bounded by the utterance")
    func runCountIsBounded() {
        #expect(Utterance(heard: "one two three four", confidence: 1).spans(upTo: 3).count == 9)
        #expect(Utterance(heard: "one", confidence: 1).spans(upTo: 3).count == 1)
        #expect(Utterance(words: []).spans(upTo: 3).isEmpty)
    }

    /// The budget should run out on the words the recogniser was sure about, not the ones it guessed.
    @Test("puts the least certain words first")
    func leastCertainFirst() {
        let utterance = Utterance(words: [
            SpokenWord(text: "the", confidence: 0.99),
            SpokenWord(text: "clawed", confidence: 0.2),
            SpokenWord(text: "report", confidence: 0.8),
        ])
        #expect(utterance.spans(upTo: 1).map(\.text) == ["clawed", "report", "the"])
    }

    /// A run is only as trusted as its weakest word, which sorts it ahead of the confident words inside it.
    @Test("trusts a run no more than its weakest word")
    func runConfidence() {
        let utterance = Utterance(words: [
            SpokenWord(text: "payment", confidence: 0.9),
            SpokenWord(text: "sheet", confidence: 0.3),
        ])
        let pair = utterance.spans(upTo: 2).first { $0.text == "payment sheet" }
        #expect(pair?.confidence == 0.3)
        #expect(utterance.spans(upTo: 2).first?.text == "payment sheet")
    }

    /// Equally uncertain runs come back in the same order every time.
    @Test("orders equally uncertain runs the same way every time")
    func orderIsTotal() {
        let utterance = Utterance(heard: "alpha beta", confidence: 0.5)
        #expect(utterance.spans(upTo: 2).map(\.text) == ["alpha beta", "alpha", "beta"])
        #expect(utterance.spans(upTo: 2) == utterance.spans(upTo: 2))
    }
}
