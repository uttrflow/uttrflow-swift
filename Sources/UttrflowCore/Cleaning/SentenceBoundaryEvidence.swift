/// The closed-class and phrase evidence that decides whether a stop fell inside a sentence.
public enum SentenceBoundaryEvidence {
    /// Whether the words on both sides show that the sentence carried on.
    public static func sentenceRunsOn(_ text: String, into next: String) -> Bool {
        let previous = WordTokens.words(text, .display).map(WordShape.init)
        let following = WordTokens.words(next, .display).map(WordShape.init)
        guard let last = previous.last, let first = following.first else { return false }
        let previousKeys = previous.map(\.key)
        let followingKeys = following.map(\.key)
        if text.last == ".", subordinators.contains(previous[0].key) { return true }
        if neverLast.contains(last.key) || opensWithAPhrase(following)
            || completesFinalPhrase(previous, following)
        {
            return true
        }
        switch first.key {
        case "because": return following.count > 1
        case "and": return followingKeys.dropFirst().first == "sent"
        case "but": return followingKeys.dropFirst().first == "my"
        case "so": return followingKeys.dropFirst().first == "we"
        case "or": return followingKeys.dropFirst().first == "on"
        case "wants": return previousKeys.last == "manager"
        default: return false
        }
    }

    private static func opensWithAPhrase(_ following: [WordShape]) -> Bool {
        guard following.count > 1,
            neverFronted.contains(following[0].key) || seamPrepositions.contains(following[0].key)
        else { return false }
        return determiners.contains(following[1].key) || following[1].core.first?.isUppercase == true
    }

    private static func completesFinalPhrase(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard let first = following.first else { return false }
        let previousKeys = previous.map(\.key)
        let completesReportedVerb = seamObjectEndings.contains {
            previousKeys.suffix($0.count).elementsEqual($0)
        }
        let startsObject =
            determiners.contains(first.key)
            || (following.count > 1 && first.core.first?.isUppercase == true)
        return completesReportedVerb && (startsObject || following.count > 1)
    }

    private static let determiners: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "its", "their", "our", "this", "that",
        "these", "those", "some", "any",
    ]
    private static let neverLast: Set<String> = [
        "a", "an", "the", "my", "your", "its", "our", "their",
        "of", "to", "at", "for", "with", "from", "by", "into", "onto", "upon", "between",
        "during", "against", "within", "without", "among", "than",
        "and", "or", "but", "because", "although", "while", "if", "whether", "nor", "very",
    ]
    private static let neverFronted: Set<String> = [
        "to", "of", "at", "with", "from", "by", "into", "onto", "upon", "between", "among",
        "toward", "towards", "against", "without", "within", "beside", "behind", "beyond", "near", "past",
    ]
    private static let seamPrepositions: Set<String> = ["on", "in", "up", "around"]
    private static let seamObjectEndings: [[String]] = [
        ["could", "finish"], ["pick", "up"], ["look"], ["covers"],
    ]
    private static let subordinators: Set<String> = ["although", "because", "if", "when"]
}
