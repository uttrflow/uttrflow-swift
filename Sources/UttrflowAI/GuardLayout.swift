import UttrflowCore
import UttrflowDictionary

// The guard's checks on layout, list marks, breaks, quotation marks and the text's overall shape.
extension MeaningPreservationGuard {
    /// Refuses a rewrite that flattened a break the speaker asked for, since layout is the passes' to decide.
    static func layoutVerdict(
        kept: String, rewritten: String, layout: LayoutPolicy = [.paragraphs, .lists]
    ) -> GuardVerdict {
        let wanted = breaks(in: kept)
        let got = breaks(in: rewritten)
        guard wanted.paragraphs <= got.paragraphs, wanted.lines <= got.lines else {
            return .rejected(reason: "the rewrite dropped a line break the speaker asked for", kind: .layout)
        }
        // A list may be laid out and never composed, so one may appear only where the destination lays them out.
        guard layout.contains(.lists) || listMarks(in: rewritten) <= listMarks(in: kept) else {
            return .rejected(reason: "the rewrite composed a list the speaker did not speak", kind: .layout)
        }
        // Somewhere with no paragraphs to make, a break the speaker did not ask for is the model's own shape.
        guard layout.contains(.paragraphs) || got.paragraphs + got.lines <= wanted.paragraphs + wanted.lines
        else {
            return .rejected(
                reason: "the rewrite added a line break the speaker did not ask for", kind: .layout)
        }
        return .accepted
    }

    /// List items, counted the way every pass counts them, so the guard and the passes agree on what one is.
    private static func listMarks(in text: String) -> Int {
        Draft(keepingLineBreaks: text).words.count { $0.isListMark }
    }

    /// Paragraph breaks and line breaks, counting a paragraph as one break rather than two lines.
    private static func breaks(in text: String) -> (paragraphs: Int, lines: Int) {
        let paragraphs = text.components(separatedBy: "\n\n").count - 1
        let lines = text.filter { $0.isNewline }.count - paragraphs
        return (paragraphs, lines)
    }

    /// Accepts a rewrite unless it is empty, chatty (unless excused), far longer, mostly dropped, invents a number, or adds a symbol.
    static func textVerdict(original: String, rewritten: String, excusingPreamble: Bool) -> GuardVerdict {
        let originalWords = TextTidy.words(original)
        let rewrittenWords = TextTidy.words(rewritten)

        if !originalWords.isEmpty, rewrittenWords.isEmpty {
            return .rejected(reason: "the rewrite is empty", kind: .emptyRewrite)
        }
        // A speaker who opens with "I have" or "sure" gets their words; the entry's punctuation is the model's, not theirs.
        if !excusingPreamble,
            let preamble = Self.preambles.first(where: {
                rewritten.lowercased().hasPrefix($0)
                    && !original.lowercased().hasPrefix($0.trimmingCharacters(in: .punctuationCharacters))
            })
        {
            return .rejected(reason: "the rewrite begins with '\(preamble)'", kind: .preamble)
        }
        if Double(rewrittenWords.count) > Double(originalWords.count) * Self.maximumGrowthFactor + 4 {
            return .rejected(reason: "the rewrite is far longer than what was said", kind: .tooLong)
        }
        if originalWords.count > Self.shortUtteranceWords {
            let retained = Double(rewrittenWords.count) / Double(originalWords.count)
            if retained < Self.minimumRetainedFraction {
                return .rejected(reason: "the rewrite dropped most of what was said", kind: .tooShort)
            }
        }
        if let invented = Self.inventedNumber(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite introduced the number \(invented)", kind: .inventedNumber)
        }
        if let changed = Self.changedQuantity(original: original, rewritten: rewritten) {
            return .rejected(reason: "the rewrite wrote \(changed) as another amount", kind: .changedNumber)
        }
        if let changed = Self.changedIndianGrouping(original: original, rewritten: rewritten) {
            return .rejected(
                reason: "the rewrite changed the Indian grouping in \(changed)", kind: .changedNumber)
        }
        return symbolVerdict(original: original, rewritten: rewritten)
    }

    /// One row of the symbol table: what the rewrite may not do with one kind of symbol, and how a refusal reads.
    struct SymbolCheck: Sendable {
        let name: String
        let reason: String
        let kind: RefusalKind
        let violates: @Sendable (_ original: String, _ rewritten: String) -> Bool
    }

    /// Every symbol kind the guard holds a rewrite to, in the order a refusal names them.
    static let symbolChecks: [SymbolCheck] = [
        SymbolCheck(
            name: "ampersand", reason: "the rewrite changed a spoken ampersand", kind: .lostWord,
            violates: { original, rewritten in count("&", in: original) != count("&", in: rewritten) }),
        SymbolCheck(
            name: "quotation", reason: "the rewrite added quotation marks", kind: .inventedQuotation,
            violates: { original, rewritten in addsQuotationPair(original: original, rewritten: rewritten) }),
        SymbolCheck(
            name: "exclamation", reason: "the rewrite added an exclamation mark", kind: .inventedExclamation,
            violates: { original, rewritten in count("!", in: rewritten) > count("!", in: original) }),
        addedKind("emoji", "an emoji", isEmoji),
        addedKind("dash", "a dash") { $0 == "\u{2014}" || $0 == "\u{2013}" },
        addedKind("ellipsis", "an ellipsis character") { $0 == "\u{2026}" },
        addedKind("asterisk", "an asterisk") { $0 == "*" },
        addedKind("hash", "a hash sign") { $0 == "#" },
        addedKind("at", "an at sign") { $0 == "@" },
        addedKind("bullet", "a bullet") { $0 == "\u{2022}" },
    ]

    /// A row refusing a symbol kind the rewrite holds and the draft neither holds nor names.
    private static func addedKind(
        _ name: String, _ noun: String, _ member: @escaping @Sendable (Character) -> Bool
    ) -> SymbolCheck {
        SymbolCheck(
            name: name, reason: "the rewrite added \(noun)", kind: .inventedSymbol,
            violates: { original, rewritten in
                rewritten.contains(where: member) && !original.contains(where: member)
                    && !TextTidy.words(original).contains { word in
                        symbolNames[word.lowercased()].map { $0.contains(where: member) } ?? false
                    }
            })
    }

    /// How many times a symbol occurs in a text.
    private static func count(_ symbol: Character, in text: String) -> Int {
        text.count(where: { $0 == symbol })
    }

    /// Refuses a rewrite that breaks any row of the symbol table, naming the first.
    static func symbolVerdict(original: String, rewritten: String) -> GuardVerdict {
        guard let broken = symbolChecks.first(where: { $0.violates(original, rewritten) }) else {
            return .accepted
        }
        return .rejected(reason: broken.reason, kind: broken.kind)
    }

    /// Whether a character draws as an emoji, by default or through its presentation selector.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0 == "\u{FE0F}" }
    }

    /// Whether the rewrite adds a quoted word span that has no counterpart in the draft.
    private static func addsQuotationPair(original: String, rewritten: String) -> Bool {
        var originalSpans = quotationSpans(in: original)
        for span in quotationSpans(in: rewritten) {
            guard let match = originalSpans.firstIndex(of: span) else { return true }
            originalSpans.remove(at: match)
        }
        return false
    }

    /// The word spans held by straight and curly quotation pairs.
    private static func quotationSpans(in text: String) -> [String] {
        let characters = Array(text)
        let pairs: [(Character, Character)] = [
            ("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}"),
            ("'", "'"),
        ]
        return pairs.flatMap { open, close in
            let openings = characters.indices.filter { characters[$0] == open }
                .filter { !isApostropheDelimiter(at: $0, in: characters) }
            let closings = characters.indices.filter { characters[$0] == close }
                .filter { !isApostropheDelimiter(at: $0, in: characters) }
            var unmatched = openings
            var spans: [String] = []
            for closing in closings {
                guard let index = unmatched.firstIndex(where: { $0 < closing }) else { continue }
                let opening = unmatched.remove(at: index)
                let content = String(characters[(opening + 1)..<closing])
                spans.append(grammarTokens(content).map(\.matching).joined(separator: " "))
            }
            return spans
        }
    }

    /// Whether a single quote mark is an apostrophe or a decade elision rather than a delimiter.
    private static func isApostropheDelimiter(at index: Int, in characters: [Character]) -> Bool {
        (characters[index] == "'" || characters[index] == "\u{2019}")
            && (isWordApostrophe(at: index, in: characters) || isDecadeElision(at: index, in: characters))
    }

    /// Whether an apostrophe stands between two letters in one word.
    private static func isWordApostrophe(at index: Int, in characters: [Character]) -> Bool {
        index > 0 && index + 1 < characters.count
            && characters[index - 1].isLetter && characters[index + 1].isLetter
    }

    /// Whether an apostrophe abbreviates the leading digits of a decade such as ’90s.
    private static func isDecadeElision(at index: Int, in characters: [Character]) -> Bool {
        guard index + 2 < characters.count, characters[index + 1].isNumber,
            characters[index + 2].isNumber
        else { return false }
        return index + 3 == characters.count || !characters[index + 3].isNumber
    }
}
