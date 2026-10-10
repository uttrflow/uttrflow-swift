import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

/// Training labels trust the passage except where two independent decodings agree it was misread.
@Suite("Training labels")
struct TrainingLabelsTests {
    /// How the reader departed from one passage, at a passage word index.
    enum Deviation {
        case skipped(Int)
        case repeated(Int)
        case swapped(Int)
    }

    static let passageCount = 10
    static let passageLength = 30
    static let deviations: [Int: Deviation] = [
        0: .skipped(4), 2: .repeated(11), 4: .swapped(25), 6: .skipped(11), 8: .repeated(4),
    ]

    static func passage(_ number: Int) -> [String] {
        (0..<passageLength).map { "p\(number)w\($0)" }
    }

    /// What the reader actually said: the passage with this passage's deviation, if any.
    static func spoken(_ number: Int) -> [String] {
        var words = passage(number)
        switch deviations[number] {
        case .skipped(let index): words.remove(at: index)
        case .repeated(let index): words.insert(words[index], at: index)
        case .swapped(let index): words[index] = "misread\(number)"
        case nil: break
        }
        return words
    }

    /// The spoken words with a decoder's own errors, 3 or more words from any deviation so no tie merges.
    static func decoded(_ number: Int, errorsAt indices: [Int], tag: String) -> [String] {
        var words = spoken(number)
        for (order, index) in indices.enumerated().reversed() {
            switch order % 3 {
            case 0: words[index] = "\(tag)\(number)x\(order)"
            case 1: words.remove(at: index)
            default: words.insert("\(tag)\(number)x\(order)", at: index)
            }
        }
        return words
    }

    static func labels(_ number: Int) -> TrainingLabels {
        TrainingLabels.label(
            passage: passage(number),
            decoding: decoded(number, errorsAt: [1, 8, 15, 22, 28], tag: "first"),
            corroborating: [decoded(number, errorsAt: [0, 18], tag: "second")])
    }

    @Test("All 5 reader deviations are unreliable and none of 50 recogniser errors are")
    func deviationsExcluded() {
        let all = (0..<Self.passageCount).map(Self.labels)
        let combined = TrainingLabels.combined(all)
        #expect(combined.excludedSpanCount == 5)
        #expect(combined.fittable.count { $0.label.isError } == 50)
        for (number, deviation) in Self.deviations {
            let excluded = all[number].spans.filter { $0.reliability == .unreliable }
            #expect(excluded.count == 1)
            switch deviation {
            case .skipped(let index):
                #expect(
                    excluded.first
                        == LabelledSpan(
                            label: .dropped("p\(number)w\(index)"), passageIndex: index,
                            reliability: .unreliable))
            case .repeated(let index):
                #expect(excluded.first?.label == .inserted("p\(number)w\(index)"))
            case .swapped(let index):
                let wanted = SpanLabel.substituted(truth: "p\(number)w\(index)", heard: "misread\(number)")
                #expect(excluded.first?.label == wanted)
            }
        }
    }

    @Test("Every span comes from the one aligner, in its order")
    func spansFollowTheAligner() {
        let passage = Self.passage(4)
        let decoding = Self.decoded(4, errorsAt: [1, 6, 10], tag: "first")
        let labels = TrainingLabels.label(passage: passage, decoding: decoding, corroborating: [])
        let alignment = WordErrorRate.measure(reference: passage, hypothesis: decoding).alignment
        #expect(labels.spans.map(\.label) == alignment.map(SpanLabel.init))
        #expect(labels.excludedSpanCount == 0)
    }

    @Test("A second decoding that errs at the same word differently leaves the error reliable")
    func differentErrorStaysReliable() {
        let labels = TrainingLabels.label(
            passage: ["send", "the", "file"], decoding: ["send", "a", "file"],
            corroborating: [["send", "this", "file"], ["send", "the", "file"]])
        #expect(labels.excludedSpanCount == 0)
        #expect(labels.fittable[1].label == .substituted(truth: "the", heard: "a"))
    }

    @Test("A doubled insertion needs both insertions corroborated")
    func doubledInsertionCountsEach() {
        let labels = TrainingLabels.label(
            passage: ["send", "file"], decoding: ["send", "the", "the", "file"],
            corroborating: [["send", "the", "file"]])
        #expect(labels.excludedSpanCount == 1)
        #expect(labels.fittable.count { $0.label == .inserted("the") } == 1)
    }

    @Test("Text is compared under the scorer's normaliser")
    func textUsesTheNormaliser() {
        let labels = TrainingLabels.label(
            passage: "Send the file.", decoding: "send file", corroborating: ["SEND FILE"])
        #expect(labels.spans.map(\.label) == [.correct("send"), .dropped("the"), .correct("file")])
        #expect(labels.excludedSpanCount == 1)
    }
}
