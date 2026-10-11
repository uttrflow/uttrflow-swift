import Testing
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("The mark property probe catches broken idempotence")
struct IllegalMarkSequenceProbeTests {
    @Test("a seeded non-idempotent pass reaches the shared detector", arguments: Destination.allCases)
    func catchesBrokenPass(destination: Destination) {
        for seed in IllegalMarkSequencePropertyTests.seeds {
            var random = Seeded(seed: seed)
            let words = IllegalMarkSequencePropertyTests.dictation(&random)
            let (once, twice) = doubling(words, destination)
            #expect(once != twice, "seed \(seed), destination \(destination)")
            #expect(
                IllegalMarkSequencePropertyTests.broken(words, in: destination, cleaning: doubling)
                    .contains(.notIdempotent), "seed \(seed), destination \(destination)")
        }
    }

    @Test("the shared shrinker preserves the seeded defect in one word", arguments: Destination.allCases)
    func shrinksBrokenPass(destination: Destination) {
        for seed in IllegalMarkSequencePropertyTests.seeds {
            var random = Seeded(seed: seed)
            let words = IllegalMarkSequencePropertyTests.dictation(&random)
            let smallest = IllegalMarkSequencePropertyTests.shrunk(
                words, .notIdempotent, in: destination, cleaning: doubling)
            #expect(smallest.count == 1, "seed \(seed), destination \(destination)")
            #expect(
                IllegalMarkSequencePropertyTests.broken(smallest, in: destination, cleaning: doubling)
                    .contains(.notIdempotent), "seed \(seed), destination \(destination)")
        }
    }

    @Test("a stable pass never produces a false idempotence defect", arguments: Destination.allCases)
    func stablePass(destination: Destination) {
        for seed in IllegalMarkSequencePropertyTests.seeds {
            var random = Seeded(seed: seed)
            let words = IllegalMarkSequencePropertyTests.dictation(&random)
            #expect(
                !IllegalMarkSequencePropertyTests.broken(words, in: destination, cleaning: identity)
                    .contains(.notIdempotent), "seed \(seed), destination \(destination)")
        }
    }

    private func doubling(_ words: [String], _ destination: Destination) -> (once: String, twice: String) {
        runs(words, through: CleaningPipeline(passes: [MarkProbeDoublingPass()]))
    }

    private func identity(_ words: [String], _ destination: Destination) -> (once: String, twice: String) {
        runs(words, through: CleaningPipeline(passes: []))
    }

    private func runs(_ words: [String], through pipeline: CleaningPipeline) -> (once: String, twice: String)
    {
        let once = pipeline.run(Draft(text: words.joined(separator: " "))).text
        return (once, pipeline.run(Draft(text: once)).text)
    }
}

/// Repeats the first word on every run so the property probe has a known defective pass.
private struct MarkProbeDoublingPass: PieceCleaningPass {
    static let id: PassID = "markProbeDoubling"
    static let laws: Set<PassLaw> = [.idempotent]

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if let first = draft.presentIndices.first {
            let word = draft.words[first].text
            draft.replace(at: first, with: word + " " + word, by: Self.id)
        }
        return draft
    }
}
