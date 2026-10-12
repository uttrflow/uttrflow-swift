import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowEval

extension TranscribeCorpus {
    /// Prints the kept-decode ablation report or fails with its complete refusal diagnostic.
    func reportAblation() async throws {
        let rules = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        do {
            print(
                try await LayerAblation.report(
                    corpus: URL(fileURLWithPath: corpusPath), engineVersion: engineVersion, cleaner: rules
                ))
        } catch {
            print("\(error)")
            throw ExitCode.failure
        }
    }
}
