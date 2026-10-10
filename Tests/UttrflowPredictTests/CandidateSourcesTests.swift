import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Choosing between remembered and machine candidates")
struct CandidateSourcesTests {
    @Test("Remembered candidates take precedence over environment candidates")
    func rememberedCandidatesWin() async {
        let personal = Candidate(text: "git checkout", source: .personal)
        let store = SourceStore(candidates: [personal])
        let environment = EnvironmentSource(index: EnvironmentIndex(reader: SourceMachine()))
        let result = await CandidateSources.candidates(
            from: store, environment: environment,
            for: Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/tmp"),
            matching: "git ch", now: .now)
        #expect(result == [personal])
    }

    @Test("An empty history lets terminal environment candidates through")
    func environmentSuppliesCandidatesWhenHistoryIsEmpty() async {
        let store = SourceStore(candidates: [])
        let index = EnvironmentIndex(reader: SourceMachine())
        _ = await index.values(of: .subcommand(of: "git"), in: "/tmp", now: .now)
        await index.settle()
        let result = await CandidateSources.candidates(
            from: store, environment: EnvironmentSource(index: index),
            for: Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: "/tmp"),
            matching: "git ch", now: .now)
        #expect(result.map(\.text) == ["git checkout"])
        #expect(result.first?.source == .environment)
    }
}

private struct SourceStore: PredictionStore {
    let candidates: [Candidate]
    func candidates(for surface: Surface, matching typed: String) async throws -> [Candidate] {
        candidates
    }
}

private struct SourceMachine: EnvironmentReading {
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        kind == .subcommand(of: "git") ? ["checkout"] : []
    }
}
