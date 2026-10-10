// Turns correct rewrites into wrong ones, one class of model error at a time, for the guard's false-accept rate.

internal import Foundation

/// A class of model error, made by one mutation of a correct rewrite.
public enum ModelErrorClass: String, CaseIterable, Sendable {
    case dropContentWord, addNegation, swapWords, changeNumber, appendClause
    case answerInsteadOfTidy, translate, wrapInLabel, moveWordAcrossSentence

    /// Applies this error to a correct rewrite, or nil when the rewrite has nothing it can act on.
    public func mutate(_ text: String, seed: Int) -> String? {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        switch self {
        case .dropContentWord:
            guard let index = words.firstIndex(where: Self.isContentWord), words.count > 3 else { return nil }
            words.remove(at: index)
            return Self.capitalised(words.joined(separator: " "))
        case .addNegation:
            guard let index = words.firstIndex(where: { Self.auxiliaries.contains($0.lowercased()) })
            else { return nil }
            words.insert("not", at: index + 1)
            return words.joined(separator: " ")
        case .swapWords:
            guard
                let index = words.indices.dropLast().first(where: {
                    Self.isContentWord(words[$0]) && Self.isContentWord(words[$0 + 1])
                        && words[$0].lowercased() != words[$0 + 1].lowercased()
                })
            else { return nil }
            words.swapAt(index, index + 1)
            return words.joined(separator: " ")
        case .changeNumber:
            guard let index = text.lastIndex(where: \.isNumber), let digit = text[index].wholeNumberValue
            else { return nil }
            return text.replacingCharacters(in: index...index, with: String((digit + 1) % 10))
        case .appendClause:
            return text + " " + Self.clauses[seed % Self.clauses.count]
        case .answerInsteadOfTidy:
            return Self.answers[seed % Self.answers.count]
        case .translate:
            let translated = words.map { Self.foreign[$0.lowercased()] ?? $0 }
            let changed = zip(words, translated).count { $0 != $1 }
            return changed >= 2 ? translated.joined(separator: " ") : nil
        case .wrapInLabel:
            return Self.labels[seed % Self.labels.count] + text
        case .moveWordAcrossSentence:
            return Self.movedAcrossSentence(words)
        }
    }

    /// Each case's expected text mutated by each class, bar no-ops; `perClass` keeps that many per class, spread evenly.
    public static func mutations(
        of corpus: [EvaluationCase], perClass: Int? = nil
    ) -> [(sample: EvaluationCase, errorClass: ModelErrorClass, rewrite: String)] {
        let all = corpus.enumerated().flatMap { seed, sample in
            allCases.compactMap { errorClass -> (EvaluationCase, ModelErrorClass, String)? in
                guard let rewrite = errorClass.mutate(sample.expected, seed: seed), rewrite != sample.expected
                else { return nil }
                return (sample, errorClass, rewrite)
            }
        }
        guard let perClass else { return all }
        return allCases.flatMap { errorClass in
            let ofClass = all.filter { $0.1 == errorClass }
            guard ofClass.count > perClass else { return ofClass }
            return (0..<perClass).map { ofClass[$0 * ofClass.count / perClass] }
        }
    }

    /// The last content word of the first sentence, moved to the end of the last one.
    private static func movedAcrossSentence(_ original: [String]) -> String? {
        var words = original
        guard let end = words.firstIndex(where: { $0.hasSuffix(".") }), end < words.count - 2,
            let index = words[..<end].lastIndex(where: isContentWord), index > 0
        else { return nil }
        let moved = words.remove(at: index)
        let last = words.count - 1
        let tail = words[last]
        guard let stop = tail.last, stop.isPunctuation else { return nil }
        words[last] = String(tail.dropLast()) + " " + moved.lowercased() + String(stop)
        return words.joined(separator: " ")
    }

    private static func isContentWord(_ word: String) -> Bool {
        word.count >= 4 && word.allSatisfy(\.isLetter)
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static let auxiliaries: Set<String> = [
        "is", "are", "was", "were", "will", "can", "should", "could",
    ]
    private static let clauses = [
        "Also remember to book the meeting room.", "Let me know if that works.",
        "I think we should cancel the order too.",
    ]
    private static let answers = [
        "Sure, I can help with that. What would you like me to change?",
        "That sounds like a good plan to me.", "I am an assistant and cannot send messages for you.",
    ]
    private static let labels = ["Here is the cleaned text: ", "Output: ", "Corrected version: "]
    private static let foreign: [String: String] = [
        "the": "el", "and": "y", "is": "es", "with": "con", "for": "para", "today": "hoy",
        "tomorrow": "manana", "we": "nosotros", "you": "usted", "but": "pero", "this": "esto",
    ]
}
