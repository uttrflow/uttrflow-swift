import Foundation
import UttrflowAI
import UttrflowPredict

/// The parts of the scorer that never touch MLX, so tests reach them without a model.
extension MLXCandidateScorer {
    /// The last pass's prompt tokens and the model's state after them, so the next pass reads only what changed. See `Docs/performance-suggestions.md`.
    struct KeptPrefix<Cache>: @unchecked Sendable {
        // Held by one pass at a time, which is what makes writing to it safe.
        let tokens: [Int]
        let cache: Cache
    }

    /// Restores a prefix a pass took only while no newer pass has left one and the model remains loaded.
    static func restoring<Cache>(
        current: KeptPrefix<Cache>?, taken: KeptPrefix<Cache>?, weightsLoaded: Bool
    )
        -> KeptPrefix<Cache>?
    {
        current ?? (weightsLoaded ? taken : nil)
    }

    /// How many opening tokens two prompts share, the last one always left to be read again so the model has a token to answer from, or nothing when that is no more than the warmed instructions hold.
    static func sharedPrefix(of read: [Int], and all: [Int], beating warmed: Int) -> Int? {
        guard !all.isEmpty else { return nil }
        let shared = min(zip(read, all).prefix { $0 == $1 }.count, all.count - 1)
        guard shared > warmed else { return nil }
        return shared
    }

    /// What the parser makes of a pass, withholding a budget-cut line that has not ended.
    static func completions(
        from run: Run, typed: String, asking ask: Ask, in situation: GenerationSituation
    ) -> [String] {
        guard !(ask == .one && run.stop == .length) else { return [] }
        var response = run.written + run.text
        if ask != .one, run.stop == .length, let last = response.last, !last.isNewline {
            if let newline = response.lastIndex(where: \.isNewline) {
                response = String(response[..<newline])
            } else {
                response = ""
            }
        }
        return CompletionText.modelCompletions(
            from: response, typed: typed, echoPolicy: .required, in: situation)
    }
}

extension MLXCandidateScorer {
    /// The most tokens one tidied utterance may produce.
    static let tidyTokens = 256

    /// A reply a little longer than the prompt it tidies, so a runaway stops early and the guard declines it.
    static func tidyBudget(for prompt: String) -> Int {
        min(tidyTokens, 32 + prompt.utf8.count / 2)
    }
}
