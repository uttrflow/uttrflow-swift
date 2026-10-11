import UttrflowCore

/// The one rule for when spoken code symbols are written: the screen's cues, then the speech's, against one threshold.
enum NotationEvidence {
    /// The confidence notation needs; one screen cue reaches it and no speech cue alone does. See `Docs/adapters.md` §2.
    static let activationThreshold = 1.0

    /// What the screen says before a word is read: a command line or a caret in code for, a comment or prose body against.
    static func applicability(
        destination: Destination, region: CaretStructure.Region, mode: AdapterMode = .auto
    ) -> Applicability {
        // The person's own word comes before any cue: plain prose is never given notation.
        if mode == .prose { return Applicability(cues: [.proseByChoice]) }
        if destination == .terminal { return Applicability(cues: [.commandLine]) }
        // A query's string literal is a value the speaker words, so it is no more a statement than a comment is.
        if destination == .sqlEditor, region != .code, region != .unrecognised {
            return Applicability(cues: [.caretInProse])
        }
        guard destination == .codeEditor else { return .noEvidence }
        switch region {
        case .code, .string: return Applicability(cues: [.caretInCode])
        case .comment, .prose: return Applicability(cues: [.caretInProse])
        case .unrecognised: return .noEvidence
        }
    }

    /// A query editor's screen evidence with the statement already in the field read: a comment or string holds the caret, or a clause is open.
    static func applicability(
        destination: Destination, region: CaretStructure.Region, statement: SQLPosition,
        markup: MarkupPosition? = nil, mode: AdapterMode = .auto
    ) -> Applicability {
        let screen = applicability(destination: destination, region: region, mode: mode)
        if destination == .codeEditor, mode != .prose, let markup { return applicability(markup: markup) }
        guard destination == .sqlEditor, mode != .prose else { return screen }
        if statement.inComment || statement.inString { return Applicability(cues: [.caretInProse]) }
        return screen == .noEvidence && statement.isMidStatement
            ? Applicability(cues: [.queryStatement]) : screen
    }

    /// A markup document's evidence from where the caret is: a tag, a rule or a declaration is code, text between tags says nothing until the speech spells a tag, a comment or quoted value is prose.
    static func applicability(markup: MarkupPosition) -> Applicability {
        switch markup {
        case .quoted: Applicability(cues: [.caretInProse])
        case .slot(.text): .noEvidence
        case .slot: Applicability(cues: [.caretInCode])
        }
    }

    /// Whether a notation pass belongs in the pipeline: on the screen's evidence, or where only the speech can tell, in a query editor or in HTML text.
    static func mayActivate(
        _ screen: Applicability, in destination: Destination, markup: MarkupPosition? = nil
    ) -> Bool {
        screen.activates(at: activationThreshold)
            || (screen == .noEvidence && (destination == .sqlEditor || markup == .slot(.text)))
    }

    /// The elements a spoken tag can name; a word outside this list opens no tag.
    private static let elements: Set<String> = [
        "a", "abbr", "address", "article", "aside", "audio", "b", "blockquote", "body", "br", "button",
        "canvas", "caption", "code", "dd", "details", "div", "dl", "dt", "em", "fieldset", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "i",
        "iframe", "img", "input", "label", "legend", "li", "link", "main", "meta", "nav", "ol", "option",
        "p", "pre", "script", "section", "select", "small", "span", "strong", "style", "sub", "summary",
        "sup", "table", "tbody", "td", "textarea", "tfoot", "th", "thead", "title", "tr", "u", "ul",
        "video",
    ]

    /// Whether the words from `index` spell a whole tag: "open", an element, attributes said as name equals value, and "close".
    static func spellsTag(_ words: [String], at index: Int) -> Bool {
        guard words[index] == "open" else { return false }
        let isEnd = words.indices.contains(index + 2) && words[index + 1] == "slash"
        let element = index + (isEnd ? 2 : 1)
        guard words.indices.contains(element), elements.contains(words[element]) else { return false }
        var end = element + 1
        while end < words.count, !closes(words, at: end) { end += 1 }
        guard end < words.count else { return false }
        // "close it" and "close to" end a sentence about closing something, not a tag.
        let afterClose = end + (words[end] == "slash" ? 2 : 1)
        if words.indices.contains(afterClose), FunctionWords.holds(words[afterClose]) { return false }
        let body = words[(element + 1)..<end]
        if body.isEmpty { return true }
        guard !isEnd, body.count <= maximumAttributeWords,
            !outsideQuotation(Array(body)).contains(where: FunctionWords.holds), let first = body.first,
            let last = body.last, first != "equals", last != "equals"
        else { return false }
        return body.contains("equals")
            && !zip(body, body.dropFirst()).contains { $0 == "equals" && $1 == "equals" }
    }

    private static func closes(_ words: [String], at index: Int) -> Bool {
        let next = words.indices.contains(index + 1) ? words[index + 1] : nil
        // "close quote" ends a quotation, not the tag.
        return (words[index] == "close" && next != "quote")
            || (words[index] == "slash" && next == "close")
    }

    /// The words outside any quotation, which are the attribute names and bare values; a quoted value may hold any word.
    private static func outsideQuotation(_ words: [String]) -> [String] {
        var kept: [String] = []
        var isQuoting = false
        for (index, word) in words.enumerated() {
            let previous = index > 0 ? words[index - 1] : nil
            if isQuoting {
                let endsQuote =
                    word == "unquote" || (word == "quote" && (previous == "close" || previous == "end"))
                if endsQuote { isQuoting = false }
            } else if word == "quote" {
                isQuoting = true
            } else {
                kept.append(word)
            }
        }
        return kept
    }

    /// Whether any run of `words` spells a tag.
    static func spellsTag(in words: [String]) -> Bool {
        words.indices.contains { spellsTag(words, at: $0) }
    }

    /// The most words a tag's attributes are said in before the speech reads as prose.
    private static let maximumAttributeWords = 14

    /// A query editor's evidence, read from the opening word: a statement opens with a statement keyword, a sentence about one does not.
    static func applicability(
        destination: Destination, opening word: String?, given screen: Applicability
    ) -> Applicability {
        guard destination == .sqlEditor, screen == .noEvidence, let word, statementOpeners.contains(word)
        else {
            return screen
        }
        return Applicability(cues: [.queryStatement])
    }

    /// The words a dictated statement opens with; the rest of its keywords are rows of the notation table.
    static let statementOpeners: Set<String> = ["select", "insert", "update", "delete"]

    /// Whether `words` are a statement in a query editor, read from the evidence that writes its notation.
    static func isQueryStatement(
        words: [String], destination: Destination, region: CaretStructure.Region
    ) -> Bool {
        guard destination == .sqlEditor else { return false }
        let screen = applicability(destination: destination, region: region)
        let opened = applicability(destination: destination, opening: words.first, given: screen)
        return applicability(of: words, given: opened).activates(at: activationThreshold)
    }

    /// The screen's evidence with the speech's cues added: an article, or a determiner before a longer non-notation word ("our costs", not "this dot").
    static func applicability(of words: [String], given screen: Applicability) -> Applicability {
        let readsAsProse = words.indices.contains { index in
            if FunctionWords.prose.contains(words[index]) { return true }
            guard FunctionWords.determiners.contains(words[index]), index + 1 < words.count else {
                return false
            }
            let next = words[index + 1]
            return next.count > 1 && FunctionWords.isContent(next) && !notationWords.contains(next)
        }
        return readsAsProse ? screen.adding([.proseWord]) : screen
    }

    /// A word that, just before a notation word, makes it a noun ("a dot") rather than a command.
    static let nounMarker = "a"

    /// Every word that begins a spoken notation command.
    private static let notationWords: Set<String> = Set(SpokenCommands.codeSymbols.compactMap(\.words.first))
}
