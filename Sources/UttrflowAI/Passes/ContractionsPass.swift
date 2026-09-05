public import UttrflowCore

/// Puts the apostrophe back into a contraction speech left without one: "dont" → "don't". See `Docs/cleanup.md`.
public struct ContractionsPass: CleaningPass {
    public static let id: PassID = .contractions

    /// Whole words that are a contraction and nothing else, so no sentence can want them as they stand.
    static let unambiguous: [String: String] = [
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't", "wont": "won't",
        "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
        "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't", "couldnt": "couldn't",
        "shouldnt": "shouldn't", "wouldnt": "wouldn't", "ive": "I've", "im": "I'm",
        "youre": "you're", "theyre": "they're", "weve": "we've", "thats": "that's",
    ]

    /// Words that are also ordinary English, repaired only where the capital says the speaker meant "I".
    static let capitalisedOnly: [String: String] = ["ill": "I'll", "id": "I'd"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices {
            let shape = draft.shape(at: index)
            guard let repaired = Self.repaired(shape) else { continue }
            draft.replace(at: index, with: shape.replacingCore(with: repaired), by: Self.id)
        }
        return draft
    }

    /// The contraction the word stands for, or nil when the word is not one or is a word in its own right.
    static func repaired(_ shape: WordShape) -> String? {
        if let capitalised = capitalisedOnly[shape.key] {
            return shape.core.first?.isUppercase == true ? capitalised : nil
        }
        guard let contraction = unambiguous[shape.key] else { return nil }
        // "I've" and "I'm" carry their own capital; everything else keeps the case it was heard in.
        if contraction.hasPrefix("I") { return contraction }
        return shape.core.first?.isUppercase == true ? WordShape.capitalised(contraction) : contraction
    }
}
