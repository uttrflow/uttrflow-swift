import Testing
import UttrflowCore

@testable import UttrflowEval

/// Holds the corpus to showing each deletion trigger surviving as well as being deleted, so the bake-off cannot score over-deletion as a win.
@Suite("Evidence the corpus must hold both ways")
struct CorpusEvidenceTests {
    /// Triggers no corpus case keeps yet; a trigger may leave this list, and a new trigger may never join it.
    static let owedAKeepCase: Set<String> = [
        "no sorry", "no wait", "wait sorry", "scratch that", "never mind", "i mean", "actually",
    ]

    /// The words of a text, lower-cased with the punctuation dropped, which is how a trigger is matched against it.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    /// Whether the trigger's words appear in that order and next to each other.
    private static func holds(_ trigger: [String], in text: String) -> Bool {
        let words = words(text)
        guard words.count >= trigger.count else { return false }
        return (0...(words.count - trigger.count)).contains {
            Array(words[$0..<$0 + trigger.count]) == trigger
        }
    }

    /// Whether any case speaks the trigger and still has it in the answer.
    private static func isKept(_ trigger: [String]) -> Bool {
        EvaluationCorpus.all.contains { holds(trigger, in: $0.spoken) && holds(trigger, in: $0.expected) }
    }

    @Test("keeps every correction trigger in some case, or records in one place that it does not")
    func everyTriggerIsMeasuredBothWays() {
        for trigger in Restatement.triggers {
            let phrase = trigger.joined(separator: " ")
            let owed = Self.owedAKeepCase.contains(phrase)
            #expect(
                Self.isKept(trigger) == !owed,
                owed
                    ? "\"\(phrase)\" is kept by a case now: take it out of owedAKeepCase"
                    : "\"\(phrase)\" is only ever deleted in the corpus: add a case that keeps it")
        }
    }
}
