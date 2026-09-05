import UttrflowCore

/// A word split into the punctuation before it, the word itself, and the punctuation after it.
struct WordShape: Equatable {
    let prefix: String
    let core: String
    let suffix: String

    init(_ text: String) {
        let leading = text.prefix(while: Self.isMark)
        let rest = text.dropFirst(leading.count)
        let trailing = rest.reversed().prefix(while: Self.isMark).reversed()
        prefix = String(leading)
        core = String(rest.dropLast(trailing.count))
        suffix = String(trailing)
    }

    /// The word lower-cased, which is what every pass compares on.
    var key: String { core.lowercased() }

    /// Whether the word closes a clause or a sentence.
    var endsClause: Bool { suffix.contains(where: { ",.;:!?".contains($0) }) }

    /// Whether the word closes a sentence.
    var endsSentence: Bool { suffix.contains(where: { ".!?".contains($0) }) }

    /// The same word with a new core, keeping the punctuation around it.
    func replacingCore(with text: String) -> String { prefix + text + suffix }

    private static func isMark(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }
}

extension Draft {
    /// The shape of the word at `index`.
    func shape(at index: Int) -> WordShape { WordShape(words[index].text) }
}

/// Words that mean the word after them is being talked about rather than dictated.
enum MentionGuard {
    static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "each", "every",
        "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// Whether the mark word at `position` in `live` is mentioned rather than used.
    static func isMentioned(at position: Int, spanning length: Int, in live: [Int], of draft: Draft) -> Bool {
        guard position > 0 else { return true }
        if determiners.contains(draft.shape(at: live[position - 1]).key) { return true }
        let next = position + length
        return next < live.count && draft.shape(at: live[next]).key == "of"
    }
}
