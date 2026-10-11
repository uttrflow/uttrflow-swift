import Foundation
import Testing
import UttrflowEval

struct ConfusionLearningCurveTests {
    typealias Curve = ConfusionLearningCurve
    private let events = [
        Curve.Event(heard: "wine", meant: "vine", soundClass: "v/w"),
        Curve.Event(heard: "wine", meant: "vine", soundClass: "v/w"),
        Curve.Event(heard: "tink", meant: "think", soundClass: "th"),
    ]

    private var trial: Curve.Trial {
        Curve.Trial(
            heard: "wine", meant: "vine",
            candidates: [
                .init(word: "wine", score: 1.0, soundClass: "none"),
                .init(word: "vine", score: 0.6, soundClass: "v/w"),
            ])
    }

    @Test func aFittedPairTurnsTheMeantWordToTheTop() {
        let model = Curve.Model(fitting: events)
        let without = Curve.evaluate([trial], model: nil, level: .backOff, classes: 10)
        #expect(without.topOneRecall == 0)
        for level in Curve.Level.allCases {
            let with = Curve.evaluate([trial], model: model, level: level, classes: 10)
            #expect(with.topOneRecall == 1, "level \(level)")
        }
        #expect(model.storedBytes > 0)
    }

    @Test func anEmptyModelIsNeutral() {
        let empty = Curve.Model(fitting: [])
        #expect(empty.classLogRatio("v/w", classes: 10) == 0)
        #expect(empty.logRatio(heard: "a", meant: "b", soundClass: "c", classes: 4, level: .wordPair) == 0)
        #expect(Curve.evaluate([], model: empty, level: .backOff, classes: 4).topOneRecall == 0)
    }

    @Test func overturningARightAnswerCountsAsAFalseOverride() {
        let wrongLesson = Curve.Model(
            fitting: Array(repeating: Curve.Event(heard: "wine", meant: "vine", soundClass: "v/w"), count: 20)
        )
        let right = Curve.Trial(
            heard: "wine", meant: "wine",
            candidates: [
                .init(word: "wine", score: 1.0, soundClass: "none"),
                .init(word: "vine", score: 0.9, soundClass: "v/w"),
            ])
        let result = Curve.evaluate([right], model: wrongLesson, level: .wordPair, classes: 10)
        #expect(result.falseOverrideRate == 1)
        #expect(Curve.evaluate([trial], model: nil, level: .wordPair, classes: 10).falseOverrideRate == 0)
    }

    @Test func splitKeepsTimeOrderAndClamps() {
        let ordered = [1, 2, 3, 4]
        #expect(Curve.split(ordered, first: 2).fit == [1, 2])
        #expect(Curve.split(ordered, first: 2).test == [3, 4])
        #expect(Curve.split(ordered, first: 50).test.isEmpty)
        #expect(Curve.split(ordered, first: -1).fit.isEmpty)
    }

    @Test func poisoningReplacesTheStatedShareRepeatably() {
        let many = Array(repeating: events[0], count: 10)
        let vocabulary = ["alpha", "beta", "gamma"]
        let first = Curve.poisoned(many, fraction: 0.3, vocabulary: vocabulary, seed: 7)
        #expect(first == Curve.poisoned(many, fraction: 0.3, vocabulary: vocabulary, seed: 7))
        #expect(first.prefix(3).allSatisfy { vocabulary.contains($0.meant) })
        #expect(first.dropFirst(3).allSatisfy { $0 == events[0] })
        #expect(Curve.poisoned(many, fraction: 0.3, vocabulary: [], seed: 7) == many)
    }
}
