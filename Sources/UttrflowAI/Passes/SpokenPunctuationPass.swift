public import UttrflowCore

/// Turns a punctuation mark said by name into the mark, when it is used rather than mentioned.
public struct SpokenPunctuationPass: CleaningPass {
    public static let id: PassID = "spokenPunctuation"

    /// What each spoken name becomes, longest names first so "question mark" wins over nothing.
    static let marks: [(words: [String], mark: String)] = [
        (["full", "stop"], "."), (["question", "mark"], "?"), (["exclamation", "mark"], "!"),
        (["exclamation", "point"], "!"), (["semi", "colon"], ";"), (["open", "quote"], "\""),
        (["close", "quote"], "\""), (["comma"], ","), (["period"], "."), (["colon"], ":"),
        (["semicolon"], ";"), (["hyphen"], "-"), (["dash"], "\u{2014}"),
    ]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard
                let found = Self.marks.first(where: { matches($0.words, at: position, in: live, of: draft) }),
                !MentionGuard.isMentioned(at: position, spanning: found.words.count, in: live, of: draft),
                attach(
                    found.mark, opening: found.words.first == "open", at: position,
                    spanning: found.words.count,
                    in: &live, of: &draft)
            else {
                position += 1
                continue
            }
        }
        return draft
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }

    /// Fixes the mark to its neighbour and drops the spoken name, or refuses when the neighbour is missing.
    private func attach(
        _ mark: String, opening: Bool, at position: Int, spanning length: Int, in live: inout [Int],
        of draft: inout Draft
    ) -> Bool {
        let after = position + length
        let previous = live[position - 1]
        if opening {
            guard after < live.count else { return false }
            draft.replace(at: live[after], with: mark + draft.words[live[after]].text, by: Self.id)
        } else if mark == "-" {
            guard after < live.count else { return false }
            let joined = draft.words[previous].text + mark + draft.words[live[after]].text
            draft.replace(at: previous, with: joined, by: Self.id)
            draft.remove(at: live[after], by: Self.id)
            live.remove(at: after)
        } else {
            draft.replace(
                at: previous, with: Self.marked(draft.words[previous].text, with: mark), by: Self.id)
        }
        for index in live[position..<after] { draft.remove(at: index, by: Self.id) }
        live.removeSubrange(position..<after)
        return true
    }

    /// The word with the mark on its end, replacing any clause mark already there.
    private static func marked(_ text: String, with mark: String) -> String {
        if mark == "\u{2014}" { return text + " " + mark }
        if let last = text.last, ",.;:!?".contains(last) { return String(text.dropLast()) + mark }
        return text + mark
    }
}
