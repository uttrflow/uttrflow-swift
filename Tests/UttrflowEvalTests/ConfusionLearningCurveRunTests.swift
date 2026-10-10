// Tests that the learning curve holds each speaker out, scores against the others' global key and prints every row.
import Testing
import UttrflowEval

@Suite("ConfusionLearningCurve run")
struct ConfusionLearningCurveRunTests {
    static func utterance(_ speaker: String, _ pairs: [(String, String)]) -> HarvestUtterance {
        HarvestUtterance(reference: pairs.map(\.0), recognised: pairs.map(\.1), group: "g", speaker: speaker)
    }

    /// Speaker "a" always writes "wine" for "vine"; the others write "wine" for "whine".
    static let speakers = ConfusionLearningCurve.events(
        [utterance("a", Array(repeating: ("vine", "wine"), count: 8))]
            + ["b", "c"].map { utterance($0, Array(repeating: ("whine", "wine"), count: 8)) })

    @Test func eventsAreReadFromSubstitutionsPerSpeakerWithTheirSoundClass() {
        #expect(Self.speakers["a"]?.count == 8)
        #expect(Self.speakers["a"]?.first == .init(heard: "wine", meant: "vine", soundClass: "v/w"))
    }

    @Test func trialsOfferTheGlobalPairsPlusHeardAndMeant() {
        let trials = ConfusionLearningCurve.trials(
            [.init(heard: "wine", meant: "vine", soundClass: "v/w")], global: ["wine": ["whine": 4]])
        #expect(trials.first?.candidates.map(\.word) == ["vine", "whine", "wine"])
        #expect(trials.first?.candidates.max { $0.score < $1.score }?.word == "whine")
    }

    @Test func learningTheSpeakerBeatsTheGlobalKeyOnceFitted() {
        let rows = ConfusionLearningCurve.curve(Self.speakers, ks: [0, 5], poisonings: [0, 0.3])
        func row(
            _ level: ConfusionLearningCurve.Level?, _ k: Int, _ poisoning: Double = 0
        ) -> ConfusionLearningCurve.Row? {
            rows.first { $0.level == level && $0.k == k && $0.poisoning == poisoning }
        }
        #expect(rows.count == 2 * (1 + 3 * 2))
        let global = row(nil, 5)?.recall?.value ?? 1
        let learned = row(.wordPair, 5)?.recall?.value ?? 0
        #expect(learned > global)
        #expect(row(.wordPair, 0)?.recall?.value == row(nil, 0)?.recall?.value)
        #expect((row(.wordPair, 5)?.storedBytes ?? 0) > (row(.wordPair, 0)?.storedBytes ?? 0))
        #expect(row(.backOff, 5, 0.3)?.trials == row(.backOff, 5)?.trials)
    }

    @Test func markdownHasAHeaderAndOneLinePerRow() {
        let rows = ConfusionLearningCurve.curve(Self.speakers, ks: [5], poisonings: [0])
        let lines = ConfusionLearningCurve.markdown(rows).split(separator: "\n")
        #expect(lines.count == 2 + rows.count)
        #expect(lines[2].hasPrefix("| global key | 5 | 0% |"))
    }

    @Test func aSpeakerWithNothingLeftToTestIsSkipped() {
        let rows = ConfusionLearningCurve.curve(Self.speakers, ks: [50], poisonings: [0])
        #expect(
            rows.allSatisfy {
                $0.trials == 0 && $0.recall == nil && $0.falseOverrideRate == 0 && $0.storedBytes == 0
            })
        #expect(ConfusionLearningCurve.markdown(rows).contains("| - |"))
    }
}
