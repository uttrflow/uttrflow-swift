// Tests the linguistic class given to each aligned recogniser error.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite struct ErrorClassTests {
    let classifier = ErrorClassifier(
        sameSound: { Set([$0, $1]) == ["hear", "here"] }, properNouns: ["Priya"])

    func classes(_ reference: String, _ heard: String) -> [ErrorClass] {
        let split = { (text: String) in text.split(separator: " ").map(String.init) }
        let rate = WordErrorRate.measure(reference: split(reference), hypothesis: split(heard))
        return classifier.classify(rate.alignment)
    }

    @Test(arguments: [
        ("please pay with paymentsheet now", "please pay with payment sheet now"),
        ("please pay with payment sheet now", "please pay with paymentsheet now"),
    ])
    func splitOrMergedWordIsBoundary(reference: String, heard: String) {
        #expect(classes(reference, heard) == [.wordBoundary, .wordBoundary])
    }

    @Test func eachClassIsNamed() {
        #expect(classes("i can hear you", "i can here you") == [.homophone])
        #expect(classes("send 42 now", "send 40 now") == [.numeralForm])
        #expect(classes("we tried it", "we try it") == [.inflection])
        #expect(classes("we stopped it", "we stop it") == [.inflection])
        #expect(classes("put it on the desk", "put it on desk") == [.functionWord])
        #expect(classes("call priya today", "call maria today") == [.properNoun])
        #expect(classes("open the window", "open the widow") == [.other])
    }

    @Test func unrelatedNeighboursAreNotBoundary() {
        #expect(classes("big red barn", "big bed") == [.other, .other])
    }

    @Test func reportSharesSumToOne() {
        let report = TranscriptionReport(
            label: "test",
            scores: [
                score(
                    "a", reference: ["the", "dog", "can", "hear", "you"],
                    heard: ["dog", "can", "here", "you"])
            ])
        let rows = report.errorClasses(by: classifier)
        #expect(rows.map(\.errorClass) == [.functionWord, .homophone])
        #expect(rows.map(\.share).reduce(0, +) == 1)
    }

    @Test func scoredPassageNamesItsOwnProperNouns() {
        let passage = TranscriptionCase(
            id: "names", language: .english, stressor: .properNouns,
            romanised: "Please call Priya today. Marcus wrote it.")
        let scored = TranscriptionScorer.score("please call maria today marcos wrote it", against: passage)
        #expect(scored.properNouns == ["priya"])
        let report = TranscriptionReport(label: "test", scores: [scored])
        let rows = report.errorClasses(by: ErrorClassifier())
        #expect(rows.map(\.errorClass) == [.other, .properNoun])
    }
}
