import Testing
import UttrflowCore

@testable import UttrflowEval

/// Holds the corpus to showing what a pass may delete surviving as well as being deleted, so the bake-off cannot score over-deletion as a win.
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

    /// The scales a repeat is deleted at: one word in `StammersPass`, a run of two to four in `RepeatedPhrasePass`.
    static let repeatScales: [(scale: String, lengths: [Int])] = [
        ("one word", [1]), ("a run of two to four words", [2, 3, 4]),
    ]

    /// Whether a run of any of those lengths is said twice in a row anywhere in the text.
    private static func hasRepeat(_ lengths: [Int], in text: String) -> Bool {
        let words = words(text)
        return lengths.contains { length in
            guard words.count >= 2 * length else { return false }
            return (0...(words.count - 2 * length)).contains {
                Array(words[$0..<$0 + length]) == Array(words[$0 + length..<$0 + 2 * length])
            }
        }
    }

    @Test("keeps a verbatim repeat in some case as well as deleting one, at both scales a pass deletes them")
    func everyRepeatScaleIsMeasuredBothWays() {
        for (scale, lengths) in Self.repeatScales {
            #expect(
                EvaluationCorpus.all.contains {
                    Self.hasRepeat(lengths, in: $0.spoken) && !Self.hasRepeat(lengths, in: $0.expected)
                },
                "no case deletes a repeat of \(scale), so the deletion is unmeasured")
            #expect(
                EvaluationCorpus.all.contains { Self.hasRepeat(lengths, in: $0.expected) },
                "no case keeps a repeat of \(scale), so deleting every one of them scores as a win")
        }
    }
}
