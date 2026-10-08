// Counted-work bounds for every cleaning pass, taken from the pipelines, so a pass that grows quadratically fails here.
import Testing
import UttrflowCore

@testable import UttrflowAI

/// Long dictation with no sentence end, the shape that made earlier passes quadratic.
private enum LongDictation {
    /// Words every pass has something to do with: fillers, restarts, numbers, spoken marks and layout.
    static let vocabulary = [
        "so", "um", "the", "the", "garden", "i", "mean", "two", "hundred", "and", "five", "comma",
        "new", "line", "tomatoes", "are", "are", "growing", "uh", "well", "at", "sign", "example",
        "dot", "com", "no", "wait", "three", "percent", "it's", "first", "quote", "this", "year",
    ]

    /// `count` words drawn by a fixed linear congruential sequence, so every run reads the same text.
    static func words(_ count: Int) -> String {
        var state: UInt64 = 0x5DEE_CE66D
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return vocabulary[Int(state >> 33) % vocabulary.count]
        }.joined(separator: " ")
    }

    /// The words the draft's helpers read while `work` runs.
    static func wordsRead(_ work: () -> Void) -> Int {
        let tally = WorkTally()
        Draft.$wordsRead.withValue(tally) { work() }
        return tally.count
    }
}

/// Reads to the end of the sentence from every word, as the passes once did, so its cost grows with the square.
private struct QuadraticPass: PieceCleaningPass {
    static let id = PassID.spacing
    static let laws: Set<PassLaw> = []

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        for position in live.indices { _ = draft.sentenceEnd(from: position, in: live) }
        return draft
    }
}

@Suite("Every cleaning pass does linear work on a long dictation")
struct CleaningPassScalingTests {
    static let short = 250
    /// Four times the short text, so linear work grows 4x and quadratic work 16x.
    static let long = 1_000
    /// The most a pass's counted work may grow from the short text to the long one.
    static let growthLimit = 6.0
    /// The one pass known to grow faster than linear, until #5871 is fixed and its markers here are removed.
    static let knownQuadratic = PassID.spokenPunctuation
    /// The most words the helpers may read per dictated word across every pass of one pipeline.
    static let readsPerWord = 400

    /// Every pass the shipped pipelines run, in every destination, so a new pass is measured without being listed.
    static let pipelines: [(String, CleaningPipeline)] = Destination.allCases.flatMap { destination in
        let situation = Situation(app: .unknown, insertion: .unknown, destination: destination)
        let formatter = DestinationFormatter.standard(for: destination)
        let standard = CleaningPipeline.standard(for: formatter, situation: situation)
        let afterModel = CleaningPipeline.afterModel(for: formatter, situation: situation)
        return [
            ("\(destination.rawValue) standard", standard),
            ("\(destination.rawValue) after model", afterModel),
        ]
    }

    /// The counted work of each pass over the text the passes before it left, keyed by pass.
    private static func work(of pipeline: CleaningPipeline, over count: Int) -> [(PassID, Int)] {
        var draft = Draft(text: LongDictation.words(count))
        return pipeline.passes.map { pass in
            var next = draft
            let read = LongDictation.wordsRead { next = pass.apply(draft) }
            draft = next
            return (pass.id, read)
        }
    }

    /// Passes whose counted work grows faster than linear between the two lengths.
    private static func superLinear(_ pipeline: CleaningPipeline) -> [String] {
        zip(work(of: pipeline, over: short), work(of: pipeline, over: long)).compactMap { small, large in
            let limit = Double(max(small.1, short)) * growthLimit
            return Double(large.1) > limit ? "\(small.0.rawValue): \(small.1) -> \(large.1)" : nil
        }
    }

    @Test("no pass in any shipped pipeline grows its counted work more than 6x when the text grows 4x")
    func everyPassIsLinear() {
        for (name, pipeline) in Self.pipelines {
            let found = Self.superLinear(pipeline)
            #expect(found.filter { !$0.hasPrefix(Self.knownQuadratic.rawValue) }.isEmpty, "\(name): \(found)")
            withKnownIssue("SpokenPunctuationPass rescans to the sentence end after every mark: #5871") {
                #expect(found.isEmpty, "\(name): \(found)")
            }
        }
    }

    @Test("a pass that reads to the sentence end from every word fails the bound")
    func quadraticPassIsCaught() {
        let pipeline = CleaningPipeline(piece: [QuadraticPass()])
        #expect(Self.superLinear(pipeline).count == 1)
    }

    @Test("a 3000-word dictation through the rules stays inside the budget, counted as words read per word")
    func longDictationIsInsideTheBudget() {
        let read = Self.work(of: .standard, over: 3_000).reduce(0) { $0 + $1.1 }
        withKnownIssue("SpokenPunctuationPass rescans to the sentence end after every mark: #5871") {
            #expect(read <= 3_000 * Self.readsPerWord, "\(read)")
        }
    }
}
