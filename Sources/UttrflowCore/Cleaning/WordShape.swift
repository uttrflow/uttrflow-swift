/// A word split into the punctuation before it, the word itself, and the punctuation after it.
public struct WordShape: Equatable, Sendable {
    public let prefix: String
    public let core: String
    public let suffix: String

    public init(_ text: String) {
        let leading = text.prefix(while: Self.isMark)
        let rest = text.dropFirst(leading.count)
        let trailing = rest.reversed().prefix(while: Self.isMark).reversed()
        prefix = String(leading)
        core = String(rest.dropLast(trailing.count))
        suffix = String(trailing)
    }

    /// The word lower-cased, which is what every pass compares on.
    public var key: String { core.lowercased() }

    /// Lower-cased runs of letters and digits, which is the unit every word comparison counts in.
    public static func words(_ text: String) -> [String] {
        WordTokens.words(text.lowercased(), .comparison)
    }

    /// Whether the word closes a clause or a sentence.
    public var endsClause: Bool { suffix.contains(where: { ",.;:!?".contains($0) }) }

    /// Whether the word is a command option such as "-i" or "--force", whose letters are case-sensitive.
    public var isOption: Bool {
        (prefix == "-" || prefix == "--") && core.first.map { $0.isLetter || $0.isNumber } == true
    }

    /// Whether the word is a spoken cut-off: letters left hanging on a bare hyphen.
    public var isCutOff: Bool { suffix == "-" && !core.isEmpty }

    /// Whether the word closes a sentence.
    public var endsSentence: Bool { suffix.contains(where: { ".!?।॥".contains($0) }) }

    /// Whether marks after a word are an ellipsis with no question or exclamation mark, which is a pause rather than a stop.
    public static func trailsOff(_ marks: String) -> Bool {
        (marks.contains("\u{2026}") || marks.contains("...")) && !marks.contains(where: { "?!".contains($0) })
    }

    /// The word with each run of clause marks after it reduced to its one legal form. See `Docs/cleanup.md`.
    public static func settlingMarks(_ text: String) -> String {
        let shape = WordShape(text)
        var settled = ""
        var run = ""
        for mark in shape.suffix {
            if runMarks.contains(mark) {
                run.append(mark)
                continue
            }
            settled += legalRun(run) + String(mark)
            run = ""
        }
        return shape.prefix + shape.core + settled + legalRun(run)
    }

    /// Marks that combine into one run after a word.
    private static let runMarks: Set<Character> = [".", ",", ";", ":", "?", "!", "\u{2026}"]

    /// One run as a single mark, a pause or an interrobang pair; otherwise its strongest member.
    private static func legalRun(_ run: String) -> String {
        guard run.count > 1 else { return run }
        let ask = run.firstIndex(of: "?")
        let exclaim = run.firstIndex(of: "!")
        if let ask, let exclaim { return ask < exclaim ? "?!" : "!?" }
        if ask != nil { return "?" }
        if exclaim != nil { return "!" }
        if run.contains("\u{2026}") { return "\u{2026}" }
        let dots = run.filter { $0 == "." }.count
        if dots >= 3 { return "..." }
        if dots > 0 { return "." }
        let pauses: [Character] = [";", ":", ","]
        return pauses.first(where: { run.contains($0) }).map { String($0) } ?? run
    }

    /// The same word with a new core, keeping the punctuation around it.
    public func replacingCore(with text: String) -> String { prefix + text + suffix }

    private static func isMark(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }

    // MARK: Shaping a word

    /// Uppercases the first letter; a leading digit counts as the start and stays as it is.
    public static func capitalised(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return text }
        guard !keepsWrittenCase(firstWord(of: text)) else { return text }
        return String(text[..<start]) + text[start].uppercased() + String(text[text.index(after: start)...])
    }

    /// Lowercases the first letter; a leading digit counts as the start and stays as it is.
    public static func lowercased(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0.isLetter || $0.isNumber }), text[start].isLetter else {
            return text
        }
        guard !keepsWrittenCase(firstWord(of: text)) else { return text }
        return String(text[..<start]) + text[start].lowercased() + String(text[text.index(after: start)...])
    }

    /// The first whitespace-separated word, whose case alone decides how a sentence opens.
    private static func firstWord(of text: String) -> String {
        String(text.drop(while: \.isWhitespace).prefix(while: { !$0.isWhitespace }))
    }

    /// Whether a word is cased as written: an internal capital, or a technical token such as a path or URL.
    public static func keepsWrittenCase(_ text: String) -> Bool {
        hasInternalCapital(text) || TechnicalToken.classify(text) != nil
    }

    /// Whether a word carries an uppercase letter after its first letter.
    public static func hasInternalCapital(_ text: String) -> Bool {
        guard let first = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return false }
        return text[text.index(after: first)...].contains(where: { $0.isUppercase })
    }

    /// The six Latin marks that end a clause or a sentence.
    package static let clauseMarks: Set<Character> = [",", ".", ";", ":", "!", "?"]

    /// Marks that end a text already: a clause mark or an ellipsis; a closing bracket may stand before a stop and is not one.
    static let finishers: Set<Character> = clauseMarks.union(["\u{2026}", "।", "॥"])

    /// Each closing bracket mapped to the bracket that opens it.
    public static let bracketOpeners: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// Quotes that open a quotation, read on the word's own prefix.
    public static let openingQuotes: Set<Character> = ["\"", "'", "\u{201C}", "\u{2018}", "\u{00AB}"]

    /// Quotes a full stop belongs inside, which is where a spoken "close quote" leaves the end of a sentence.
    static let closingQuotes: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}"]

    /// The word with a full stop, or `mark`, where the sentence wants one; `preceding` is the text before it, read for an opening bracket.
    public static func finished(
        _ text: String, with mark: String = ".", after preceding: String = ""
    ) -> String {
        let shape = WordShape(text)
        guard !shape.core.isEmpty, !shape.suffix.contains(where: finishers.contains) else { return text }
        let closers = String(
            text.reversed().prefix { closingQuotes.contains($0) || bracketOpeners[$0] != nil }.reversed())
        let body = String(text.dropLast(closers.count))
        guard let bracket = closers.lastIndex(where: { bracketOpeners[$0] != nil }) else {
            // A quotation opening and closing on one word is a quoted term rather than a sentence, so it takes none.
            guard closers.isEmpty || !shape.prefix.contains(where: openingQuotes.contains) else {
                return text
            }
            return quotationIsSpeech(preceding) ? body + mark + closers : text + mark
        }
        let enclosed = preceding + " " + body + closers[..<bracket]
        if bracketFollowsOperator(enclosed, closedBy: closers[bracket]) { return text }
        if bracketOpensSentence(enclosed, closedBy: closers[bracket]) { return body + mark + closers }
        let quoted = trailingQuotes(of: closers)
        return String(text.dropLast(quoted.count)) + mark + quoted
    }

    /// Verbs of saying, which make the quotation after them reported speech rather than a quoted term.
    static let speechVerbs: Set<String> = [
        "say", "says", "said", "reply", "replies", "replied", "ask", "asks", "asked", "answer", "answers",
        "answered", "tell", "tells", "told", "write", "writes", "wrote", "shout", "shouts", "shouted",
    ]

    /// Whether the quotation the last word closes is speech: it opens its sentence, follows a verb of saying, or opens on a subject.
    private static func quotationIsSpeech(_ preceding: String) -> Bool {
        let line = CaretStructure.caretLine(of: preceding)
        let words = WordTokens.words(line, .display).map(WordShape.init)
        guard let start = words.lastIndex(where: { $0.prefix.contains(where: openingQuotes.contains) }) else {
            return true
        }
        guard start > 0, !words[start - 1].endsSentence, !speechVerbs.contains(words[start - 1].key) else {
            return true
        }
        return QuestionShape.newSubjects.contains(words[start].key)
    }

    /// Whether the bracket that `closer` matches is the first thing in its sentence, so the whole sentence sits inside it.
    private static func bracketOpensSentence(_ text: String, closedBy closer: Character) -> Bool {
        guard let opener = bracketOpeners[closer] else { return false }
        var depth = 0
        for index in text.indices.reversed() {
            let character = text[index]
            if character == closer {
                depth += 1
            } else if character == opener {
                guard depth == 0 else {
                    depth -= 1
                    continue
                }
                let before = text[..<index].reversed().drop {
                    ($0.isWhitespace && !$0.isNewline) || openingQuotes.contains($0)
                }
                guard let last = before.first else { return true }
                return SentenceMarks.ends.contains(last) || last.isNewline
            }
        }
        return false
    }

    /// Whether the bracket that `closer` matches opens right after an operator, as in `x = [1, 2]`: a value, not prose.
    private static func bracketFollowsOperator(_ text: String, closedBy closer: Character) -> Bool {
        guard let opener = bracketOpeners[closer] else { return false }
        var depth = 0
        for index in text.indices.reversed() {
            let character = text[index]
            if character == closer {
                depth += 1
            } else if character == opener {
                guard depth == 0 else {
                    depth -= 1
                    continue
                }
                let last = text[..<index].reversed().first { !$0.isWhitespace }
                return last.map { "=<>+-*/%&|^".contains($0) } ?? false
            }
        }
        return false
    }

    /// The word with `mark` on its end; a clause mark replaces one already there, a quote follows it.
    public static func marked(_ text: String, with mark: String) -> String {
        if mark == "\u{2014}" { return text + " " + mark }
        if let last = text.last, ",.;:!?".contains(last), ",.;:!?".contains(mark) {
            if last == ".", Abbreviations.ownsStop(WordShape(text).core) {
                return mark == "." ? text : text + mark
            }
            return String(text.dropLast()) + mark
        }
        return text + mark
    }

    /// The word with every mark of `marks` on its end, each merged in turn under `marked(_:with:)`.
    public static func marked(_ text: String, withAll marks: some Sequence<Character>) -> String {
        marks.reduce(text) { marked($0, with: String($1)) }
    }

    /// Takes back one trailing full stop, inside a closing quote too; a question or exclamation mark, or an ellipsis, stays.
    public static func withoutTrailingStop(_ text: String) -> String {
        let quoted = trailingQuotes(of: text)
        let body = String(text.dropLast(quoted.count))
        guard body.hasSuffix("."), !body.hasSuffix("..") else { return text }
        return String(body.dropLast()) + quoted
    }

    /// The run of closing quotes the text ends on, which a full stop goes inside rather than after.
    private static func trailingQuotes(of text: String) -> String {
        String(text.reversed().prefix(while: closingQuotes.contains).reversed())
    }
}

extension Draft {
    /// The shape of the word at `index`, counted while a test has `wordsRead` bound.
    public func shape(at index: Int) -> WordShape {
        Self.wordsRead?.record()
        return WordShape(words[index].text)
    }

    /// The live positions from `position` to the end of the sentence it sits in, which one spoken phrase cannot run past.
    public func sentenceRun(from position: Int, in live: [Int]) -> Range<Int> {
        position..<sentenceEnd(from: position, in: live)
    }

    /// The exclusive end of the sentence containing `position`.
    public func sentenceEnd(from position: Int, in live: [Int]) -> Int {
        guard position < live.count else { return live.count }
        for index in position..<live.count where shape(at: live[index]).endsSentence {
            return index + 1
        }
        return live.count
    }

    /// Whether at least `count` words remain before this sentence ends.
    public func sentenceContains(_ count: Int, from position: Int, in live: [Int]) -> Bool {
        let end = min(position + count, live.count)
        guard position < end else { return count == 0 }
        for index in position..<end where shape(at: live[index]).endsSentence {
            return index + 1 == end
        }
        return end == position + count
    }

    /// Whether the live words from `position` are the phrase `words`, inside one sentence unless `acrossSentences`.
    public func spells(
        _ words: [String], at position: Int, in live: [Int], acrossSentences: Bool = false
    ) -> Bool {
        position + words.count <= live.count
            && (acrossSentences || sentenceContains(words.count, from: position, in: live))
            && zip(words, live[position..<position + words.count]).allSatisfy { $0 == shape(at: $1).key }
    }
}
