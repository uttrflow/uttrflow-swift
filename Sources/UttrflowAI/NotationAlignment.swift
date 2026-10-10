import UttrflowCore

/// What was said and what was written, read through the notation rows so a spoken name and the mark its row writes are one token. See Docs/adapters.md, section 4.
struct NotationAlignment: Sendable {
    /// One run of spoken words a row names, and what the rewrite wrote in its place.
    struct Name: Sendable, Equatable {
        /// What stands in the rewrite for a spoken name.
        enum Standing: Sendable, Equatable {
            case dropped, asSaid, asMark
        }

        let words: [String]
        let standing: Standing
    }

    /// The written marks only notation writes, in written order, that no spoken name or spoken mark stands behind.
    let unsourced: [String]
    /// The marks only notation writes that the spoken side already held, in order, and the rewrite left out.
    let dropped: [String]
    /// Every spoken name, in spoken order.
    let names: [Name]

    /// The rows that write a mark in place of its spoken name: prose punctuation, code symbols and flags.
    static let notationRows = SpokenCommands.all.filter { row in
        switch row.action {
        case .mark, .codeSymbol, .flag: true
        case .layout, .casing, .leadIn, .replace, .lineMark, .spanMark, .emoji, .key: false
        }
    }

    /// A percent said by name is a mark too: "percent s" written as the format specifier `%s`.
    private static let standard = NotationLexicon(
        notationRows,
        naming: MeaningPreservationGuard.symbolNames.merging(Quantities.percentWords) { joining, _ in joining
        })

    /// Aligns `written` to `spoken` in order with the shared word alignment, each spoken name standing as its row's mark.
    static func align(spoken: String, written: String) -> NotationAlignment {
        align(spoken: spoken, written: written, lexicon: standard)
    }

    /// The same alignment through other rows, which is how a test states a table of its own.
    static func align(spoken: String, written: String, table: [SpokenCommand]) -> NotationAlignment {
        align(spoken: spoken, written: written, lexicon: NotationLexicon(table, naming: [:]))
    }

    private static func align(
        spoken: String, written: String, lexicon: NotationLexicon
    ) -> NotationAlignment {
        let said = lexicon.units(in: spoken)
        let wrote = lexicon.units(in: written)
        let landed = WordErrorRate.measure(reference: said.map(\.key), hypothesis: wrote.map(\.key))
            .matchedColumns
        let matched = Set(landed.compactMap { $0 })
        let unsourced = wrote.indices.filter { !matched.contains($0) && lexicon.isJudged(wrote[$0]) }
        let dropped = said.indices.filter { landed[$0] == nil && lexicon.isJudged(said[$0]) }
        let names = said.indices.compactMap { index in
            said[index].name.map {
                Name(words: $0, standing: lexicon.standing(of: landed[index].map { wrote[$0] }, for: $0))
            }
        }
        return NotationAlignment(
            unsourced: unsourced.map { wrote[$0].text }, dropped: dropped.map { said[$0].text }, names: names)
    }

    /// The kept words of each name the rewrite writes, found in order, so the survival check does not look for them as words.
    func writtenNames(in kept: [MeaningPreservationGuard.GrammarToken]) -> Set<Int> {
        var written: Set<Int> = []
        var next = kept.startIndex
        for name in names {
            let start = kept.indices.dropFirst(next).first { start in
                start + name.words.count <= kept.count
                    && zip(name.words, kept[start...]).allSatisfy { $0 == $1.matching }
            }
            guard let start else { continue }
            next = start + name.words.count
            if name.standing != .dropped { written.formUnion(start..<next) }
        }
        return written
    }
}

/// The notation rows as the alignment reads them: each spoken name and each mark joined to the marks any row writes for it.
private struct NotationLexicon: Sendable {
    /// One token of either side: a word, or a mark standing for the class of names and marks it belongs to.
    struct Unit: Sendable {
        let key: String
        let text: String
        let mark: Int?
        /// The spoken words this mark was read from, when spoken rather than written.
        let name: [String]?
        /// Whether the mark is written hard against what stands before it, and against what follows.
        var touches: (before: Bool, after: Bool) = (true, true)
    }

    /// Each spoken name, as its words, with its class; longest first, so "dash dash" is read before "dash".
    private let names: [(words: [String], mark: Int)]
    /// Each written mark with its class; longest first, so `--` is read before `-`.
    private let marks: [(text: String, mark: Int)]
    /// The class each one-word name stands for, so a draft that wrote "dash dash" as two dashes still reads as the name.
    private let wordMarks: [String: Int]
    /// The classes only a code or flag row writes; a prose mark is the prose checks' to judge.
    private let notationOnly: Set<Int>
    /// The side each mark a row writes goes on, which says what it must touch to stand for its name.
    private let placements: [String: SpokenMarkKind]
    /// The names a code or flag row writes, whose mark may stand as a word of its own.
    private let codeNames: Set<[String]>
    /// The names some row says, whose mark is placed as that row places it.
    private let rowNames: Set<[String]>

    /// The rows, and names the guard reads as marks without a row of their own, which source a mark but are never judged.
    init(_ rows: [SpokenCommand], naming extra: [String: String]) {
        let pairs =
            rows.map { ($0.words, $0.text) }
            + extra.map { ($0.key.split(separator: " ").map(String.init), $0.value) }
        var classes = MarkClasses()
        for (words, text) in pairs { classes.join("name:" + words.joined(separator: " "), "mark:" + text) }
        let named = pairs.map { (words: $0.0, mark: classes.find("mark:" + $0.1)) }
        names = named.sorted { $0.words.count > $1.words.count }
        marks = pairs.map { (text: $0.1, mark: classes.find("mark:" + $0.1)) }
            .sorted { $0.text.count > $1.text.count }
        wordMarks = Dictionary(
            named.filter { $0.words.count == 1 }.map { ($0.words[0], $0.mark) }, uniquingKeysWith: { $1 })
        let prose = Set(rows.filter { $0.action == .mark }.map { classes.find("mark:" + $0.text) })
        notationOnly = Set(rows.filter { $0.action != .mark }.map { classes.find("mark:" + $0.text) })
            .subtracting(prose)
        placements = Dictionary(rows.map { ($0.text, $0.placement) }, uniquingKeysWith: { first, _ in first })
        codeNames = Set(rows.filter { $0.action != .mark }.map(\.words))
        rowNames = Set(rows.map(\.words))
    }

    /// What stands for a spoken name: nothing, the name as said, or its mark; a prose mark spaced as prose may be the rewrite's own.
    func standing(of written: Unit?, for name: [String]) -> NotationAlignment.Name.Standing {
        guard let written else { return .dropped }
        guard let mark = written.mark, written.name == nil else { return .asSaid }
        // A code symbol's name written as its mark standing alone is the mark as an argument: `docker build .`.
        let standsAlone = !written.touches.before && !written.touches.after && codeNames.contains(name)
        // A name no row says, such as "percent" in `%s`, is read by the mark touching a word on either side.
        let attached =
            rowNames.contains(name) ? isAttached(written) : written.touches.before || written.touches.after
        return notationOnly.contains(mark) || attached || standsAlone ? .asMark : .dropped
    }

    /// Whether a mark touches what its side asks for: an opening mark what follows, a closing one what precedes, the rest both.
    private func isAttached(_ unit: Unit) -> Bool {
        switch placements[unit.text] {
        case .opening?, .leading?: unit.touches.after
        case .closing?: unit.touches.before
        case .trailing?, .joining?: unit.touches.before && unit.touches.after
        case .standalone?: true
        case nil: unit.touches.before || unit.touches.after
        }
    }

    /// Whether a unit is a mark as written, of a class only notation writes, so prose punctuation never adds or drops it.
    func isJudged(_ unit: Unit) -> Bool {
        unit.mark.map(notationOnly.contains) == true && marks.contains { $0.text == unit.text }
    }

    /// The text's words and marks in order, each run of words a row names read as that row's mark.
    func units(in text: String) -> [Unit] {
        let characters = Array(text)
        var units: [Unit] = []
        var start = 0
        while start < characters.count {
            let kind = Self.kind(of: characters, at: start)
            var end = start + 1
            while end < characters.count, Self.kind(of: characters, at: end) == kind { end += 1 }
            switch kind {
            case .word: units += wordUnits(String(characters[start..<end]))
            case .symbol:
                let before = start > 0 && !characters[start - 1].isWhitespace
                let after = end < characters.count && !characters[end].isWhitespace
                units += symbolUnits(String(characters[start..<end]), touching: (before, after))
            case .space: break
            }
            start = end
        }
        return namesRead(in: units)
    }

    private enum CharacterKind { case word, symbol, space }

    /// A letter or digit, or an apostrophe inside a word, is a word's; whitespace is space; the rest are symbols.
    private static func kind(of characters: [Character], at index: Int) -> CharacterKind {
        let character = characters[index]
        if character.isLetter || character.isNumber { return .word }
        if character.isApostrophe, index > 0, characters[index - 1].isLetter { return .word }
        return character.isWhitespace ? .space : .symbol
    }

    /// A run of letters as its words, cut at each camel hump with its apostrophes out, which is how the speaker said it.
    private func wordUnits(_ run: String) -> [Unit] {
        MeaningPreservationGuard.identifierParts(run).map { Unit(key: $0, text: $0, mark: nil, name: nil) }
    }

    /// A run of symbols as the marks the rows write, longest first; a symbol no row writes is no notation.
    private func symbolUnits(_ run: String, touching edges: (before: Bool, after: Bool)) -> [Unit] {
        var units: [Unit] = []
        var rest = Substring(run)
        while !rest.isEmpty {
            guard let found = marks.first(where: { rest.hasPrefix($0.text) }) else {
                rest = rest.dropFirst()
                continue
            }
            var unit = Unit(key: Self.key(found.mark), text: found.text, mark: found.mark, name: nil)
            unit.touches = (
                rest.startIndex > run.startIndex || edges.before, rest.count > found.text.count || edges.after
            )
            units.append(unit)
            rest = rest.dropFirst(found.text.count)
        }
        return units
    }

    /// Each run a row names, read as the mark its row writes: said as words, or already written one mark per word.
    private func namesRead(in units: [Unit]) -> [Unit] {
        var read: [Unit] = []
        var index = 0
        while index < units.count {
            guard let name = names.first(where: { spells($0.words, at: index, in: units) }) else {
                read.append(units[index])
                index += 1
                continue
            }
            let run = units[index..<(index + name.words.count)]
            let said = run.allSatisfy { $0.mark == nil }
            read.append(
                Unit(
                    key: Self.key(name.mark), text: run.map(\.text).joined(separator: " "), mark: name.mark,
                    name: said ? name.words : nil))
            index += name.words.count
        }
        return read
    }

    /// Whether the units from `index` spell a name: each word said, or for a longer name each word's own mark.
    private func spells(_ words: [String], at index: Int, in units: [Unit]) -> Bool {
        guard index + words.count <= units.count else { return false }
        return zip(words, units[index...]).allSatisfy { word, unit in
            unit.mark == nil ? unit.key == word : words.count > 1 && wordMarks[word] == unit.mark
        }
    }

    /// The key a mark's class aligns by, which no spoken word can spell.
    private static func key(_ mark: Int) -> String { "\u{0}\(mark)" }
}

/// Names and marks joined into classes, so "dot", "period" and `.` are one mark and "dash" reaches `-` and the em dash.
private struct MarkClasses {
    private var parent: [String: String] = [:]
    private var numbers: [String: Int] = [:]

    mutating func join(_ first: String, _ second: String) {
        let (one, other) = (root(first), root(second))
        if one != other { parent[one] = other }
    }

    /// The class a member belongs to, numbered in the order classes are first asked for.
    mutating func find(_ member: String) -> Int {
        let top = root(member)
        if let number = numbers[top] { return number }
        numbers[top] = numbers.count
        return numbers.count - 1
    }

    private mutating func root(_ member: String) -> String {
        guard let up = parent[member], up != member else { return member }
        let top = root(up)
        parent[member] = top
        return top
    }
}

extension Character {
    /// A straight or curly apostrophe, which a word holds inside it.
    fileprivate var isApostrophe: Bool { self == "'" || self == "\u{2019}" }
}
