public import UttrflowCore

/// Removes the doubled function word a false start leaves behind: "the the deployment".
public struct StammersPass: CleaningPass {
    public static let id: PassID = .stammers

    /// Function words English doubles on purpose: a past perfect, a doubled relative, a conjunction, a comforting.
    static let legitimateDoubles: Set<String> = ["had", "that", "so", "there"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var previous: String?
        for index in draft.presentIndices {
            let word = draft.words[index].text.lowercased()
            // A doubled content word is emphasis, a name, or a digit of one number, so only a function word stammers.
            if word == previous, !FunctionWords.isContent(word),
                !Self.legitimateDoubles.contains(word)
            {
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                continue
            }
            previous = word
        }
        return draft
    }
}
