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

/// Turns a punctuation mark said by name into the mark, and a spoken email address into the address, when used rather than mentioned.
public struct SpokenPunctuationPass: PieceCleaningPass {
    public static let id: PassID = .spokenPunctuation
    private let destination: Destination

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

    /// Romanised Hindi function words that can follow an explicitly spoken mark.
    private static let romanisedHindiEvidence: Set<String> = [
        "aur", "ya", "toh", "phir", "lekin", "par", "ki", "ke", "ka", "ko", "main", "hum", "tum",
        "aap", "yeh", "woh",
    ]

    public init(destination: Destination = .plain) {
        self.destination = destination
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        let repeated = repeatedNames(in: live, of: draft)
        let literal = literalDashes(in: live, of: draft)
        var position = 0
        // The end of the sentence `position` sits in, kept until a write changes the words; nil once stale.
        var sentenceEnd: Int?
        while position < live.count {
            let literalHyphens = literal.contains(live[position])
            if literalHyphens, replaceLongFlag(at: position, in: &live, of: &draft) {
                sentenceEnd = nil
                continue
            }
            if literalHyphens, replaceShortFlag(at: position, in: &live, of: &draft) {
                sentenceEnd = nil
                position += 1
                continue
            }
            if sentenceEnd.map({ position >= $0 }) ?? true {
                sentenceEnd = draft.sentenceEnd(from: position, in: live)
            }
            if let end = sentenceEnd,
                let address = SpokenAddress.read(at: position, before: end, in: live, of: draft)
            {
                write(address, at: position, in: &live, of: &draft)
                sentenceEnd = nil
                position += 1
                continue
            }
            guard
                let found = Self.marks.first(where: { matches($0.words, at: position, in: live, of: draft) }),
                !MentionGuard.isMentioned(
                    at: position, spanning: found.words.count, in: live, of: draft,
                    reach: MentionGuard.phraseReach, kind: found.kind),
                !isVerb(found.words, at: position, in: live, of: draft),
                isEvidenced(found.words, at: position, in: live, of: draft, repeated: repeated),
                isPlaced(
                    found.mark, before: position + found.words.count, spanning: found.words.count,
                    in: live, of: draft),
                attach(
                    mark(found.mark, literalHyphens: literalHyphens), kind: found.kind,
                    at: position, spanning: found.words.count,
                    in: &live, of: &draft)
            else {
                position += 1
                continue
            }
            sentenceEnd = nil
        }
        return draft
    }

    private var isTechnicalDestination: Bool {
        destination == .terminal || destination == .codeEditor || destination == .sqlEditor
    }

    private func mark(_ value: String, literalHyphens: Bool) -> String {
        literalHyphens && value == "\u{2014}" ? "-" : value
    }

    /// Tools whose name starts a command, so every dash after it in the sentence is one of its options.
    static let toolCues: Set<String> = ["git", "npm", "yarn", "pnpm"]

    /// Nouns that introduce a name, so only dashes joining the name said right after them are literal.
    static let nameCues: Set<String> = ["branch", "command", "terminal"]

    /// Words that may stand between a name cue and its name: "the branch is fix dash login".
    static let nameLinks: Set<String> = ["is", "called", "named"]

    /// The word indices of spoken dashes that belong to a command or a name rather than to prose.
    private func literalDashes(in live: [Int], of draft: Draft) -> Set<Int> {
        let dashes = live.filter { draft.shape(at: $0).key == "dash" }
        if isTechnicalDestination { return Set(dashes) }
        var literal: Set<Int> = []
        var inCommand = false
        var position = 0
        while position < live.count {
            let shape = draft.shape(at: live[position])
            if inCommand && shape.key == "dash" { literal.insert(live[position]) }
            if Self.toolCues.contains(shape.key) { inCommand = true }
            if Self.nameCues.contains(shape.key) && !shape.endsSentence {
                position = nameDashes(after: position, in: live, of: draft, into: &literal)
                continue
            }
            if shape.endsSentence { inCommand = false }
            position += 1
        }
        return literal
    }

    /// Collects the dashes chaining the name after a name cue and returns the position of its last word.
    private func nameDashes(
        after cue: Int, in live: [Int], of draft: Draft, into literal: inout Set<Int>
    ) -> Int {
        var position = cue + 1
        if position < live.count && Self.nameLinks.contains(draft.shape(at: live[position]).key) {
            position += 1
        }
        guard position < live.count, draft.shape(at: live[position]).key != "dash" else { return cue + 1 }
        while position + 2 < live.count, !draft.shape(at: live[position]).endsSentence,
            draft.shape(at: live[position + 1]).key == "dash",
            draft.shape(at: live[position + 2]).key != "dash"
        {
            literal.insert(live[position + 1])
            position += 2
        }
        return position
    }

    /// Turns two consecutive spoken dashes into a long option, including one at the start of a command.
    private func replaceLongFlag(at position: Int, in live: inout [Int], of draft: inout Draft) -> Bool {
        guard position + 2 < live.count,
            matches(["dash"], at: position, in: live, of: draft),
            matches(["dash"], at: position + 1, in: live, of: draft),
            !MentionGuard.isMentioned(
                at: position, spanning: 1, in: live, of: draft,
                reach: MentionGuard.phraseReach, kind: .joining),
            !MentionGuard.isMentioned(
                at: position + 1, spanning: 1, in: live, of: draft,
                reach: MentionGuard.phraseReach, kind: .joining)
        else { return false }
        let value = live[position + 2]
        let option = draft.words[value].text
        let joinsDevelopmentSuffix =
            option == "save" && position + 3 < live.count
            && draft.shape(at: live[position + 3]).key == "dev"
        draft.replace(
            at: value, with: "--" + option + (joinsDevelopmentSuffix ? "-dev" : ""), by: Self.id)
        if joinsDevelopmentSuffix { draft.remove(at: live[position + 3], by: Self.id) }
        draft.remove(at: live[position], by: Self.id)
        draft.remove(at: live[position + 1], by: Self.id)
        live.removeSubrange(position..<(position + (joinsDevelopmentSuffix ? 4 : 2)))
        return true
    }

    /// Leaves a one-letter option as its own token: `git commit -m`, not `git commit-m`.
    private func replaceShortFlag(at position: Int, in live: inout [Int], of draft: inout Draft) -> Bool {
        guard position + 1 < live.count, position > 0,
            matches(["dash"], at: position, in: live, of: draft),
            !MentionGuard.isMentioned(
                at: position, spanning: 1, in: live, of: draft,
                reach: MentionGuard.phraseReach, kind: .joining)
        else { return false }
        let next = draft.words[live[position + 1]].text
        guard (1...2).contains(next.utf8.count),
            next.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) })
        else { return false }
        let index = live[position]
        draft.replace(at: index, with: "-" + next, by: Self.id)
        draft.remove(at: live[position + 1], by: Self.id)
        live.remove(at: position + 1)
        return true
    }

    /// Writes the address over the first of its words and drops the rest, which spelled it.
    private func write(
        _ address: SpokenAddress, at position: Int, in live: inout [Int], of draft: inout Draft
    ) {
        let after = position + address.length
        draft.replace(at: live[position], with: address.text, by: Self.id)
        for index in live[(position + 1)..<after] { draft.remove(at: index, by: Self.id) }
        live.removeSubrange((position + 1)..<after)
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && draft.sentenceContains(words.count, from: position, in: live)
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }

    /// Whether an ordinary name stands at a seam: it is sentence-final, follows punctuation, or has a continuation.
    private func isEvidenced(
        _ words: [String], at position: Int, in live: [Int], of draft: Draft, repeated: Set<Int>
    ) -> Bool {
        guard Self.ordinaryNames.contains(words) else { return true }
        let next = position + words.count
        if closes(at: next, in: live, of: draft) || repeated.contains(live[position]) { return true }
        if position > 0 && draft.shape(at: live[position - 1]).endsClause { return true }
        return next == live.count
            || next < live.count
                && isFunctionWordEvidence(draft.shape(at: live[next]).key)
    }

    private func isFunctionWordEvidence(_ word: String) -> Bool {
        FunctionWords.holds(word) || Self.romanisedHindiEvidence.contains(word)
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

    /// A full stop is used where the text closes or commas bracket its name; a hyphen or dash is used only where it does not.
    private func isPlaced(
        _ mark: String, before next: Int, spanning length: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        switch mark {
        case ".":
            return closes(at: next, in: live, of: draft)
                || isCommaBracketed(before: next, spanning: length, in: live, of: draft)
        case "-", "\u{2014}": return !closes(at: next, in: live, of: draft)
        default: return true
        }
    }

    /// A model brackets a dictated full stop with commas when it writes both the mark and its name.
    private func isCommaBracketed(
        before next: Int, spanning length: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard next < live.count, next > length else { return false }
        return draft.shape(at: live[next - length - 1]).suffix.hasSuffix(",")
            && draft.shape(at: live[next - 1]).suffix.hasSuffix(",")
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
            let following = draft.words[live[after]].text
            let balanced =
                mark == "\"" && following.hasSuffix("'")
                ? String(following.dropLast()) + mark : following
            draft.replace(at: live[after], with: mark + balanced, by: Self.id)
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
