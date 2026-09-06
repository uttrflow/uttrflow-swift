public import UttrflowCore

/// Removes the doubled short word a false start leaves behind: "the the deployment".
public struct StammersPass: CleaningPass {
    public static let id: PassID = .stammers

    /// Longer repeated words are emphasis or a real repetition, so only these are stammers.
    static let longestStammer = 4

    /// Short words English doubles on purpose: a past perfect, a doubled relative, a farewell, an emphatic.
    static let legitimateDoubles: Set<String> = ["had", "that", "bye", "no", "so"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var previous: String?
        for index in draft.presentIndices {
            let word = draft.words[index].text.lowercased()
            // A number said twice is two digits of one value — "four four two" is 442, not 42.
            if word == previous, word.count <= Self.longestStammer,
                !Self.legitimateDoubles.contains(word), !NumberWords.isNumber(word)
            {
                draft.remove(at: index, by: Self.id)
                continue
            }
            previous = word
        }
        return draft
    }
}
