import NaturalLanguage
public import UttrflowCore

/// Turns a punctuation mark said by name into the mark, and a spoken email address into the address, when used rather than mentioned.
public struct SpokenPunctuationPass: PieceCleaningPass {
    public static let id: PassID = .spokenPunctuation
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    private let destination: Destination
    /// Whether the field holds addresses, so a plain-word mailbox needs no announcing word: a recipient field.
    private let addressesExpected: Bool

    /// The particles after which "dash" and "hyphen" are the verbs they also are: "dash off a note".
    static let particles: Set<String> = [
        "off", "out", "over", "up", "down", "back", "away", "through", "in", "to", "into", "across",
    ]

    /// Names that are everyday nouns too, so a mid-sentence one is a mark only on positive evidence. See `Docs/cleanup.md`.
    static let ordinaryNames: Set<[String]> = [["comma"], ["colon"], ["dash"]]

    /// Quotation names that are everyday words too: an opening is a mark only with its closing later in the sentence, a closing only inside an open quotation.
    static let partneredNames: Set<[String]> = [["quote"], ["unquote"]]

    public init(destination: Destination = .plain, fieldRole: FieldRole = .unknown) {
        self.destination = destination
        self.addressesExpected = fieldRole == .recipient
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        markLeadIns(in: &draft)
        var live = draft.presentIndices
        let repeated = repeatedNames(in: live, of: draft)
        var names: Set<Int> = []
        let literal = literalDashes(in: live, of: draft, names: &names)
        let pairs = dashPairs(in: live, of: draft, literal: literal, repeated: repeated)
        var position = 0
        // The brackets written so far and not yet closed, innermost last.
        var openBrackets: [Character] = []
        // The end of the sentence `position` sits in, kept until a write changes the words; nil once stale.
        var sentenceEnd: Int?
        // The quotes opened and not yet closed, innermost last.
        var openQuotes: [String] = []
        while position < live.count {
            if replaceLongFlag(at: position, literal: literal, in: &live, of: &draft) {
                sentenceEnd = nil
                continue
            }
            let literalHyphens = literal.contains(live[position])
            if literalHyphens, !names.contains(live[position]),
                replaceShortFlag(at: position, in: &live, of: &draft)
            {
                sentenceEnd = nil
                position += 1
                continue
            }
            if sentenceEnd.map({ position >= $0 }) ?? true {
                sentenceEnd = draft.sentenceEnd(from: position, in: live)
            }
            if let end = sentenceEnd,
                let address = SpokenAddress.read(
                    at: position, before: end, in: live, of: draft, announced: addressesExpected)
            {
                write(address, at: position, in: &live, of: &draft)
                sentenceEnd = nil
                position += 1
                continue
            }
            if let echoed = echoedName(at: position, in: live, of: draft) {
                for index in live[position..<(position + echoed)] { draft.remove(at: index, by: Self.id) }
                live.removeSubrange(position..<(position + echoed))
                sentenceEnd = nil
                continue
            }
            guard
                let found = SpokenCommands.marks.first(where: {
                    draft.spells($0.words, at: position, in: live)
                }),
                case let paired = found.words == ["dash"] ? pairs[live[position]] : nil,
                paired ?? true,
                paired != nil
                    || isUsed(found, at: position, in: live, of: draft, repeated: repeated),
                isPaired(
                    found, at: position, in: live, of: draft, open: openBrackets,
                    quoting: !openQuotes.isEmpty),
                isPlaced(
                    found.text, before: position + found.words.count, spanning: found.words.count,
                    in: live, of: draft),
                case let written = Self.quote(found, inside: openQuotes)
                    ?? mark(found.text, literalHyphens: literalHyphens),
                attach(
                    written, kind: found.placement, at: position, spanning: found.words.count,
                    in: &live, of: &draft)
            else {
                position += 1
                continue
            }
            if found.placement == .opening, !SpokenCommands.isBracket(found.text) {
                openQuotes.append(written)
            }
            if found.placement == .closing, !SpokenCommands.isBracket(found.text) { _ = openQuotes.popLast() }
            track(found.text, in: &openBrackets)
            sentenceEnd = nil
        }
        return draft
    }

    /// The quote a quotation mark writes: a double quote opened inside a double quote is single, and a close matches the quote still open.
    static func quote(_ found: SpokenCommand, inside open: [String]) -> String? {
        guard !SpokenCommands.isBracket(found.text) else { return nil }
        return switch found.placement {
        case .opening: open.last == "\"" && found.text == "\"" ? "'" : found.text
        case .closing: open.last ?? found.text
        case .trailing, .joining, .standalone, .leading: nil
        }
    }

    /// Writes a lead-in row's mark onto its last word when more of the same clause follows it.
    private func markLeadIns(in draft: inout Draft) {
        let live = draft.presentIndices
        for row in SpokenCommands.leadIns where row.isEnabled(in: destination) {
            for position in live.indices where position + row.words.count < live.count {
                let last = live[position + row.words.count - 1]
                guard draft.spells(row.words, at: position, in: live),
                    !draft.shape(at: last).endsClause,
                    !draft.words[live[position + row.words.count]].isLayoutMark,
                    !MentionGuard.isMentioned(
                        at: position, spanning: row.words.count, in: live, of: draft,
                        reach: MentionGuard.phraseReach)
                else { continue }
                let marked = WordShape.marked(draft.words[last].text, with: row.text)
                draft.replace(at: last, with: marked, by: Self.id)
            }
        }
    }

    /// Whether a mark name is used rather than mentioned, said as the verb, or said without evidence of a seam.
    private func isUsed(
        _ found: SpokenCommand, at position: Int, in live: [Int], of draft: Draft, repeated: Set<Int>
    ) -> Bool {
        !MentionGuard.isMentioned(
            at: position, spanning: found.words.count, in: live, of: draft,
            reach: MentionGuard.phraseReach, kind: found.placement)
            && !isVerb(found.words, at: position, in: live, of: draft)
            && isEvidenced(found.words, at: position, in: live, of: draft, repeated: repeated)
    }

    /// Decides a sentence's two prose dashes around words as one, by word index: marks when either is used and both may stand there.
    private func dashPairs(
        in live: [Int], of draft: Draft, literal: Set<Int>, repeated: Set<Int>
    ) -> [Int: Bool] {
        guard let row = SpokenCommands.marks.first(where: { $0.words == ["dash"] }) else { return [:] }
        var decided: [Int: Bool] = [:]
        var start = 0
        while start < live.count {
            let end = draft.sentenceEnd(from: start, in: live)
            let dashes = (start..<end).filter {
                draft.shape(at: live[$0]).key == "dash" && !literal.contains(live[$0])
            }
            if dashes.count == 2, dashes[1] - dashes[0] > 1 {
                let fits = dashes.allSatisfy {
                    !isVerb(row.words, at: $0, in: live, of: draft)
                        && isPlaced(row.text, before: $0 + 1, spanning: 1, in: live, of: draft)
                }
                let used = dashes.contains { isUsed(row, at: $0, in: live, of: draft, repeated: repeated) }
                for position in dashes { decided[live[position]] = fits && used }
            }
            start = max(end, start + 1)
        }
        return decided
    }

    /// A spoken bracket, or a partnered name, is a mark only as half of a pair around words: an opening needs its closing later in the sentence, a bracket closing needs its opening.
    private func isPaired(
        _ command: SpokenCommand, at position: Int, in live: [Int], of draft: Draft, open: [Character],
        quoting: Bool
    ) -> Bool {
        let partnered = Self.partneredNames.contains(command.words)
        if partnered, command.placement == .closing { return quoting }
        guard SpokenCommands.isBracket(command.text) || partnered, let bracket = command.text.first
        else { return true }
        if let opener = WordShape.bracketOpeners[bracket] { return open.last == opener }
        // The closing must leave at least one word between it and the opening.
        var next = position + command.words.count + 1
        while next < live.count, !draft.shape(at: live[next - 2]).endsSentence {
            if SpokenCommands.closings.contains(where: {
                (partnered ? $0.text.first : WordShape.bracketOpeners[$0.text.first ?? " "]) == bracket
                    && draft.spells($0.words, at: next, in: live)
            }) {
                return true
            }
            next += 1
        }
        return false
    }

    /// Records a bracket the pass wrote: an opening is pushed, a closing pops its opening.
    private func track(_ mark: String, in open: inout [Character]) {
        guard SpokenCommands.isBracket(mark), let bracket = mark.first else { return }
        if WordShape.bracketOpeners[bracket] != nil { open.removeLast() } else { open.append(bracket) }
    }

    /// Whether every spoken dash here is an option marker, which the flag rows' destinations say.
    private var isCommandLine: Bool {
        SpokenCommands.flags.contains { $0.isEnabled(in: destination) }
    }

    private func mark(_ value: String, literalHyphens: Bool) -> String {
        literalHyphens && value == "\u{2014}" ? "-" : value
    }

    /// The lexicon's programs, whose name starts a command, so every dash after it in the sentence is one of its options.
    private static let commands = TechnicalLexicon.terms.filter { $0.category == .command }

    /// Whether a program the lexicon knows is named at `position`, by its written form or a spoken one.
    private func namesCommand(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        let key = draft.shape(at: live[position]).key
        return Self.commands.contains { term in
            term.applies(in: destination)
                && (term.id.lowercased() == key
                    || term.spoken.contains {
                        // Only a phrase opening on this word can match, so the rest are not read word by word.
                        $0.split(separator: " ").first.map(String.init) == key
                            && draft.spells($0.split(separator: " ").map(String.init), at: position, in: live)
                    })
        }
    }

    /// Nouns that introduce a name, so only dashes joining the name said right after them are literal.
    static let nameCues: Set<String> = ["branch", "command", "terminal"]

    /// Words that may stand between a name cue and its name: "the branch is fix dash login".
    static let nameLinks: Set<String> = ["is", "called", "named"]

    /// The word indices of spoken dashes that belong to a command or a name rather than to prose.
    private func literalDashes(in live: [Int], of draft: Draft, names: inout Set<Int>) -> Set<Int> {
        let dashes = live.filter { draft.shape(at: $0).key == "dash" }
        if isCommandLine { return Set(dashes) }
        var literal: Set<Int> = []
        var inCommand = false
        var position = 0
        while position < live.count {
            let shape = draft.shape(at: live[position])
            if inCommand && shape.key == "dash" { literal.insert(live[position]) }
            if namesCommand(at: position, in: live, of: draft) { inCommand = true }
            if Self.nameCues.contains(shape.key) && !shape.endsSentence {
                var joins: Set<Int> = []
                position = nameDashes(after: position, in: live, of: draft, into: &joins)
                literal.formUnion(joins)
                if !inCommand { names.formUnion(joins) }
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

    /// Turns a long option marker said in a command into the option; a doubled dash names no single mark, so "add" cannot make it a mention.
    private func replaceLongFlag(
        at position: Int, literal: Set<Int>, in live: inout [Int], of draft: inout Draft
    ) -> Bool {
        guard
            let row = SpokenCommands.flags.first(where: { row in
                let length = row.words.count
                return length > 1 && position + length < live.count
                    && literal.contains(live[position + length - 1])
                    && draft.spells(row.words, at: position, in: live)
            })
        else { return false }
        let length = row.words.count
        let value = live[position + length]
        var (option, end) = optionSegments(from: position + length, literal: literal, in: live, of: draft)
        let joinsDevelopmentSuffix =
            option == "save" && end + 1 < live.count && draft.shape(at: live[end + 1]).key == "dev"
        if joinsDevelopmentSuffix {
            option += "-dev"
            end += 1
        }
        draft.replace(at: value, with: row.text + option, by: Self.id)
        for index in live[position..<(position + length)] + live[(position + length + 1)..<(end + 1)] {
            draft.remove(at: index, by: Self.id)
        }
        live.removeSubrange((position + length + 1)..<(end + 1))
        live.removeSubrange(position..<(position + length))
        return true
    }

    /// The option's name, one word or several joined by spoken literal dashes, and the position of its last word.
    private func optionSegments(
        from start: Int, literal: Set<Int>, in live: [Int], of draft: Draft
    ) -> (String, Int) {
        var option = draft.words[live[start]].text
        var end = start
        while end + 2 < live.count, !draft.shape(at: live[end]).endsClause,
            literal.contains(live[end + 1]),
            draft.shape(at: live[end + 2]).key != "dash",
            // A dash before spelled letters or a number opens the next short option: `--rm -p 80`.
            letterCluster(after: end + 1, in: live, of: draft) == nil,
            numericOption(after: end + 1, in: live, of: draft) == nil
        {
            option += "-" + draft.words[live[end + 2]].text
            end += 2
        }
        return (option, end)
    }

    /// The most letters one spoken short-option cluster joins: `tar -xzvf` and a little more.
    static let clusterLimit = 6

    /// Writes a short option and its spelled letters or spoken number as one token: `ls -la`, `rm -rf`, `head -20`.
    private func replaceShortFlag(at position: Int, in live: inout [Int], of draft: inout Draft) -> Bool {
        guard position + 1 < live.count, position > 0,
            let row = SpokenCommands.flags.first(where: {
                $0.words.count == 1 && draft.spells($0.words, at: position, in: live)
            }),
            !MentionGuard.isMentioned(
                at: position, spanning: 1, in: live, of: draft,
                reach: MentionGuard.phraseReach, kind: .joining),
            let (option, length) =
                letterCluster(after: position, in: live, of: draft)
                ?? numericOption(after: position, in: live, of: draft)
        else { return false }
        // The option keeps the mark its last word carried, so a spoken stop or comma survives the join.
        let closing = draft.shape(at: live[position + length]).suffix
        draft.replace(at: live[position], with: row.text + option + closing, by: Self.id)
        for index in live[(position + 1)...(position + length)] { draft.remove(at: index, by: Self.id) }
        live.removeSubrange((position + 1)...(position + length))
        return true
    }

    /// The letters spelled after an option marker, each one spoken alone or after "capital", and how many words said them.
    private func letterCluster(after position: Int, in live: [Int], of draft: Draft) -> (String, Int)? {
        var letters = ""
        var next = position + 1
        while next < live.count, letters.count < Self.clusterLimit {
            let said = draft.shape(at: live[next])
            let capital = said.key == "capital" && said.suffix.isEmpty && next + 1 < live.count
            let shape = capital ? draft.shape(at: live[next + 1]) : said
            // A one-word option said whole, "dash la", is its own cluster and ends it.
            let limit = letters.isEmpty && !capital ? 2 : 1
            guard shape.prefix.isEmpty, (1...limit).contains(shape.core.utf8.count),
                Self.isLatinLetters(shape.core)
            else { break }
            letters += capital ? shape.core.uppercased() : shape.core
            next += capital ? 2 : 1
            if shape.core.utf8.count > 1 || !shape.suffix.isEmpty { break }
        }
        return letters.isEmpty ? nil : (letters, next - position - 1)
    }

    /// A spoken or written whole number after an option marker, `head -20`, and how many words said it.
    private func numericOption(after position: Int, in live: [Int], of draft: Draft) -> (String, Int)? {
        let first = draft.shape(at: live[position + 1])
        if first.prefix.isEmpty, !first.core.isEmpty,
            first.core.unicodeScalars.allSatisfy({ (48...57).contains($0.value) })
        {
            return (first.core, 1)
        }
        // The number stops at the first word that closes a clause, so "dash twenty, then" reads twenty.
        let rest = live[(position + 1)...]
        let end = rest.firstIndex { draft.shape(at: $0).endsClause }.map { $0 + 1 } ?? rest.endIndex
        let said = rest[..<end]
        guard let read = NumberWords.cardinal(said.map { draft.shape(at: $0).key }[...]) else { return nil }
        return (String(read.value), read.count)
    }

    private static func isLatinLetters(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { (65...90).contains($0.value) || (97...122).contains($0.value) }
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

    /// How many words name a mark already written on the word before, as a model writes ", comma,"; nil when none does.
    private func echoedName(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard position > 0,
            let found = SpokenCommands.marks.first(where: { draft.spells($0.words, at: position, in: live) }),
            !found.placement.attachesAfter, found.placement != .standalone,
            draft.shape(at: live[position - 1]).suffix.hasSuffix(found.text)
        else { return nil }
        // The name's own mark must be nothing or the same mark, so removing it loses nothing the model wrote.
        let own = draft.shape(at: live[position + found.words.count - 1]).suffix
        return own.isEmpty || own == found.text ? found.words.count : nil
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
                && (isFunctionWordEvidence(draft.shape(at: live[next]).key)
                    || closesAPhrase(words, at: position, in: live, of: draft))
    }

    /// Names that stand between two phrases, where the noun "comma" or "colon" would instead be the object or modifier of the word before.
    static let seamNames: Set<[String]> = [["comma"], ["colon"]]

    /// Word classes after which the noun reading takes the name as an object or modifier: "has colon trouble", "from colon cancer".
    private static let nounTakers: Set<NLTag> = [.verb, .preposition, .adjective, .determiner]

    /// Whether a spoken comma or colon follows a word that closes a phrase, so it is not the object or modifier of that word and does not join the word after it into a compound.
    private func closesAPhrase(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard Self.seamNames.contains(words), position > 0 else { return false }
        var start = position
        while start > 0, !draft.shape(at: live[start - 1]).endsSentence { start -= 1 }
        let end = draft.sentenceEnd(from: position, in: live)
        let keys = live[start..<end].map { draft.shape(at: $0).key }
        let tags = LexicalClass.tags(ofWords: keys)
        let before = position - 1 - start
        let after = position + 1 - start
        // A participle after the name joins it into a compound modifier, as in comma-separated.
        if after < keys.count, tags[after] == .verb,
            LexicalClass.lemma(ofWordAt: after, in: keys).map({ $0 != keys[after] }) ?? false
        {
            return false
        }
        // The first word of a sentence is an imperative or a heading, never the verb the name is the object of.
        guard let tag = tags[before], before > 0 || tag != .verb else { return true }
        return !Self.nounTakers.contains(tag)
    }

    private func isFunctionWordEvidence(_ word: String) -> Bool {
        FunctionWords.holds(word) || Self.isRomanisedHindiEvidence(word)
    }

    /// Whether a romanised Hindi word can follow an explicitly spoken mark: a conjunction, postposition or pronoun in `hindi-words.json`, in any listed spelling.
    static func isRomanisedHindiEvidence(_ word: String) -> Bool {
        guard let key = HindiWords.spellingKey(of: word) else { return false }
        return !HindiWords.classes(of: key).isDisjoint(with: [.conjunction, .postposition, .pronoun])
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
                || opensDeterminerClause(at: next, in: live, of: draft)
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

    /// Whether a determiner-led clause starts at `next`, so a full stop before it is a sentence boundary.
    private func opensDeterminerClause(
        at next: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard next < live.count, next + 1 < live.count else { return false }
        let head = draft.shape(at: live[next]).key
        guard MentionGuard.determiners.contains(head) else { return false }
        return LexicalClass.tag(ofWordAt: next + 1, in: live.map { draft.shape(at: $0).key })
            .map { $0 == .noun || $0 == .verb } ?? false
    }

    /// Whether the text ends at `next`, or a layout word, a layout mark or a closing quote stands there.
    private func closes(at next: Int, in live: [Int], of draft: Draft) -> Bool {
        next == live.count || draft.words[live[next]].isLayoutMark
            || SpokenCommands.closings.contains { draft.spells($0.words, at: next, in: live) }
            || SpokenCommands.layout.contains { draft.spells($0.words, at: next, in: live) }
    }

    /// Fixes the mark to its neighbour and drops the spoken name, or refuses when the neighbour is missing.
    private func attach(
        _ mark: String, kind: SpokenMarkKind, at position: Int, spanning length: Int,
        in live: inout [Int], of draft: inout Draft
    ) -> Bool {
        let after = position + length
        // An opening or leading mark needs the word it goes on after it, a standalone one a word on each side, every other the one before.
        let needsBefore = !kind.attachesAfter
        let needsAfter = kind.attachesAfter || kind == .standalone
        guard !needsBefore || position > 0, !needsAfter || after < live.count else { return false }
        if kind == .standalone {
            draft.replace(at: live[position], with: mark, by: Self.id)
            for index in live[(position + 1)..<after] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange((position + 1)..<after)
            return true
        }
        if kind.attachesAfter {
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
