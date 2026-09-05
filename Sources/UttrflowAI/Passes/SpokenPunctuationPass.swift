public import UttrflowCore

/// Turns a punctuation mark said by name into the mark, when it is used rather than mentioned.
public struct SpokenPunctuationPass: CleaningPass {
    public static let id: PassID = .spokenPunctuation

    /// What each spoken name becomes, longest names first so "question mark" wins over nothing.
    static let marks: [(words: [String], mark: String)] = [
        (["full", "stop"], "."), (["question", "mark"], "?"), (["exclamation", "mark"], "!"),
        (["exclamation", "point"], "!"), (["semi", "colon"], ";"), (["open", "quote"], "\""),
        (["close", "quote"], "\""), (["comma"], ","), (["period"], "."), (["colon"], ":"),
        (["semicolon"], ";"), (["hyphen"], "-"), (["dash"], "\u{2014}"),
    ]

    /// The particles after which "dash" and "hyphen" are the verbs they also are: "dash off a note".
    static let particles: Set<String> = [
        "off", "out", "over", "up", "down", "back", "away", "through", "in", "to", "into", "across",
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
                !isVerb(found.words, at: position, in: live, of: draft),
                isPlaced(found.mark, before: position + found.words.count, in: live, of: draft),
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

    /// Whether "dash" or "hyphen" is the verb rather than the mark, told by the particle after it.
    private func isVerb(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard words == ["dash"] || words == ["hyphen"], position + 1 < live.count else { return false }
        return Self.particles.contains(draft.shape(at: live[position + 1]).key)
    }

    /// A full stop is used only where the text closes; a hyphen or dash is used only where it does not.
    private func isPlaced(_ mark: String, before next: Int, in live: [Int], of draft: Draft) -> Bool {
        switch mark {
        case ".": return closes(at: next, in: live, of: draft)
        case "-", "\u{2014}": return !closes(at: next, in: live, of: draft)
        default: return true
        }
    }

    /// Whether the text ends at `next`, or a layout word, a layout mark or a closing quote stands there.
    private func closes(at next: Int, in live: [Int], of draft: Draft) -> Bool {
        next == live.count || draft.words[live[next]].isLayoutMark
            || matches(["close", "quote"], at: next, in: live, of: draft)
            || LayoutWordsPass.marks.contains { matches($0.words, at: next, in: live, of: draft) }
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

    /// The word with the mark on its end; a clause mark replaces one already there, a quote follows it.
    private static func marked(_ text: String, with mark: String) -> String {
        if mark == "\u{2014}" { return text + " " + mark }
        if let last = text.last, ",.;:!?".contains(last), ",.;:!?".contains(mark) {
            return String(text.dropLast()) + mark
        }
        return text + mark
    }
}
