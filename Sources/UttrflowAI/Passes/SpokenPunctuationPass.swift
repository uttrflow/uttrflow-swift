public import UttrflowCore

/// Which side of its name a spoken mark goes, which is what decides where a mention of it could stand.
enum SpokenMarkKind: Sendable, Equatable {
    /// Goes on the word before it: a comma, a full stop, a question mark.
    case trailing
    /// Joins the words on both sides of it: a hyphen, a dash.
    case joining
    /// Opens a quotation, so it goes on the word after it and needs nothing before it.
    case opening
    /// Closes one, so it goes on the word before it as a trailing mark does.
    case closing
}

/// Turns a punctuation mark said by name into the mark, when it is used rather than mentioned.
public struct SpokenPunctuationPass: CleaningPass {
    public static let id: PassID = .spokenPunctuation

    /// Marks written as the pair they are, so adding one is a row rather than two rows and a guard clause.
    static let pairs: [(open: [String], close: [String], mark: String)] = [
        (["open", "quote"], ["close", "quote"], "\"")
    ]

    /// What each spoken name becomes, longest names first so "question mark" wins over nothing.
    static let marks: [(words: [String], mark: String, kind: SpokenMarkKind)] =
        [
            (["full", "stop"], ".", .trailing), (["question", "mark"], "?", .trailing),
            (["exclamation", "mark"], "!", .trailing), (["exclamation", "point"], "!", .trailing),
            (["semi", "colon"], ";", .trailing),
        ]
        + pairs.flatMap { [($0.open, $0.mark, SpokenMarkKind.opening), ($0.close, $0.mark, .closing)] }
        + [
            (["comma"], ",", .trailing), (["period"], ".", .trailing), (["colon"], ":", .trailing),
            (["semicolon"], ";", .trailing), (["hyphen"], "-", .joining),
            (["dash"], "\u{2014}", .joining),
        ]

    /// The particles after which "dash" and "hyphen" are the verbs they also are: "dash off a note".
    static let particles: Set<String> = [
        "off", "out", "over", "up", "down", "back", "away", "through", "in", "to", "into", "across",
    ]

    /// Names that are everyday nouns too, so a mid-sentence one is a mark only on positive evidence. See `Docs/cleanup.md`.
    static let ordinaryNames: Set<[String]> = [["comma"], ["colon"], ["dash"]]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        let repeated = repeatedNames(in: live, of: draft)
        var position = 0
        while position < live.count {
            guard
                let found = Self.marks.first(where: { matches($0.words, at: position, in: live, of: draft) }),
                !MentionGuard.isMentioned(
                    at: position, spanning: found.words.count, in: live, of: draft,
                    reach: MentionGuard.phraseReach, kind: found.kind),
                !isVerb(found.words, at: position, in: live, of: draft),
                isEvidenced(found.words, at: position, in: live, of: draft, repeated: repeated),
                isPlaced(found.mark, before: position + found.words.count, in: live, of: draft),
                attach(
                    found.mark, kind: found.kind, at: position, spanning: found.words.count,
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
            && draft.sentenceRun(from: position, in: live).count >= words.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }

    /// Whether an ordinary name stands at a seam: the text closes, a mark precedes it, a small word follows, or it is said again.
    private func isEvidenced(
        _ words: [String], at position: Int, in live: [Int], of draft: Draft, repeated: Set<Int>
    ) -> Bool {
        guard Self.ordinaryNames.contains(words) else { return true }
        let next = position + words.count
        if closes(at: next, in: live, of: draft) || repeated.contains(live[position]) { return true }
        if position > 0 && draft.shape(at: live[position - 1]).endsClause { return true }
        return next < live.count && FunctionWords.holds(draft.shape(at: live[next]).key)
    }

    /// The word indices of ordinary names said more than once in one sentence, which is a list rather than a noun.
    private func repeatedNames(in live: [Int], of draft: Draft) -> Set<Int> {
        var sentence = 0
        var seen: [String: [Int]] = [:]
        for (position, index) in live.enumerated() {
            let shape = draft.shape(at: index)
            if Self.ordinaryNames.contains([shape.key])
                && !MentionGuard.isMentioned(
                    at: position, spanning: 1, in: live, of: draft, reach: MentionGuard.phraseReach)
            {
                seen["\(sentence) \(shape.key)", default: []].append(index)
            }
            if shape.endsSentence { sentence += 1 }
        }
        return Set(seen.values.filter { $0.count > 1 }.joined())
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
            || Self.pairs.contains { matches($0.close, at: next, in: live, of: draft) }
            || LayoutWordsPass.marks.contains { matches($0.words, at: next, in: live, of: draft) }
    }

    /// Fixes the mark to its neighbour and drops the spoken name, or refuses when the neighbour is missing.
    private func attach(
        _ mark: String, kind: SpokenMarkKind, at position: Int, spanning length: Int,
        in live: inout [Int], of draft: inout Draft
    ) -> Bool {
        let after = position + length
        // An opening mark needs the word it goes on to stand after it; every other mark needs the one before.
        guard kind == .opening ? after < live.count : position > 0 else { return false }
        if kind == .opening {
            draft.replace(at: live[after], with: mark + draft.words[live[after]].text, by: Self.id)
        } else if mark == "-" {
            let joined = draft.words[live[position - 1]].text + mark + draft.words[live[after]].text
            draft.replace(at: live[position - 1], with: joined, by: Self.id)
            draft.remove(at: live[after], by: Self.id)
            live.remove(at: after)
        } else {
            let previous = live[position - 1]
            draft.replace(
                at: previous, with: WordShape.marked(draft.words[previous].text, with: mark), by: Self.id)
        }
        for index in live[position..<after] { draft.remove(at: index, by: Self.id) }
        live.removeSubrange(position..<after)
        return true
    }
}
