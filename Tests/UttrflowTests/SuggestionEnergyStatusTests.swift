import Testing
import UttrflowPredict

@testable import Uttrflow

@Suite("Suggestion energy pause announcement")
struct SuggestionEnergyStatusTests {
    @Test("announces the reason only when the energy gate is holding the model", .bug(id: 3409))
    func announcesOnlyTheEnergyGate() async {
        let unavailable = UnavailableGenerator()
        let heldByEnergy = DiscretionaryGenerator(unavailable, mayRun: { false })
        let allowedButUnavailable = DiscretionaryGenerator(unavailable, mayRun: { true })

        #expect(!unavailable.isReady)
        #expect(!(await heldByEnergy.isReady))
        #expect(!(await allowedButUnavailable.isReady))
        #expect(SuggestionEnergyStatus.shouldAnnouncePause(for: nil) == false)
        #expect(SuggestionEnergyStatus.shouldAnnouncePause(for: unavailable) == false)
        #expect(SuggestionEnergyStatus.shouldAnnouncePause(for: allowedButUnavailable) == false)
        #expect(SuggestionEnergyStatus.shouldAnnouncePause(for: heldByEnergy))
    }
}

private struct UnavailableGenerator: CandidateGenerating {
    var isReady: Bool { false }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        []
    }
}
