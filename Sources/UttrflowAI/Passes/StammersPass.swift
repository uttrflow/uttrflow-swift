public import UttrflowCore

/// Removes the doubled short word a false start leaves behind: "the the deployment".
public struct StammersPass: CleaningPass {
    public static let id: PassID = .stammers

    /// Longer repeated words are emphasis or a real repetition, so only these are stammers.
    static let longestStammer = 4

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var previous: String?
        for index in draft.presentIndices {
            let word = draft.words[index].text.lowercased()
            if word == previous, word.count <= Self.longestStammer {
                draft.remove(at: index, by: Self.id)
                continue
            }
            previous = word
        }
        return draft
    }
}
