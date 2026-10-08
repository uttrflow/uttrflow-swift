import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Every mark the notation table writes, said in every position and cleaned in every destination, sits where its spacing row says.
@Suite("Mark spacing matrix")
struct MarkSpacingMatrixTests {
    /// Where in the dictation the mark's name is said.
    enum Position: String, CaseIterable {
        case start, middle, end, beforeBracket, beforeQuote
    }

    /// One cell of the matrix: a notation row said at one position, cleaned for one destination.
    struct Cell: CustomStringConvertible {
        let row: SpokenCommand
        let kind: SpokenMarkKind
        let position: Position
        let destination: Destination

        var description: String { "\(destination.rawValue) \(family)" }

        /// The row and position, which name the cell in every destination at once.
        var family: String { "\(row.id) \(position.rawValue)" }

        /// The words said, "alpha" and "beta" giving the mark a word on each side to go on.
        var spoken: String {
            let name = row.words.joined(separator: " ")
            switch position {
            case .start: return "\(name) alpha beta"
            case .middle: return "alpha \(name) beta"
            case .end: return "alpha beta \(name)"
            case .beforeBracket:
                let pair =
                    "()".contains(row.text)
                    ? ("open-bracket", "close-bracket") : ("open-paren", "close-paren")
                return "alpha \(name) \(Self.around(pair))"
            case .beforeQuote:
                let pair =
                    row.text == "\""
                    ? ("open-single-quote", "close-single-quote") : ("open-quote", "close-quote")
                return "alpha \(name) \(Self.around(pair))"
            }
        }

        /// The names of the notation rows `mark.<open>` and `mark.<close>`, said around "beta".
        private static func around(_ pair: (String, String)) -> String {
            [pair.0, pair.1].compactMap { id in
                SpokenCommands.marks.first { $0.id == "mark.\(id)" }?.words.joined(separator: " ")
            }.joined(separator: " beta ")
        }
    }

    /// Every cell: each single-mark notation row, its side from the spacing table or else the row's own placement.
    static let cells: [Cell] = SpokenCommands.marks.flatMap { row -> [Cell] in
        guard row.text.count == 1, let mark = row.text.first else { return [] }
        let kind = MarkSpacing.kind(of: mark) ?? row.placement
        return Destination.allCases.filter(row.isEnabled(in:)).flatMap { destination in
            Position.allCases.map { Cell(row: row, kind: kind, position: $0, destination: destination) }
        }
    }

    /// The text the rule-based transformer writes for `spoken` in `destination`.
    static func rulesText(_ spoken: String, in destination: Destination) async throws -> String {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let request = TransformationRequest(
            transcription: .fixture(text: spoken, language: .english), situation: situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test("covers every mark that both the notation table writes and the spacing table lists")
    func coversTheTables() {
        let written = Set(Self.cells.map(\.row.text))
        let listed = MarkSpacing.table.rows.map(\.id).filter { id in
            SpokenCommands.marks.contains { $0.text == id }
        }
        #expect(!listed.isEmpty)
        #expect(Set(listed).isSubset(of: written))
        #expect(Self.cells.count == Set(Self.cells.map(\.description)).count)
    }

    @Test("writes a mark that replaces its name, on the side its row says, in every position and destination")
    func everyCellIsSpaced() async throws {
        var faults: [String: [String]] = [:]
        for cell in Self.cells {
            let text = try await Self.rulesText(cell.spoken, in: cell.destination)
            guard let fault = Self.fault(in: text, cell: cell) else { continue }
            faults[cell.family, default: []].append("\(cell.destination.rawValue): \(fault) in \"\(text)\"")
        }
        let known = MarkSpacingKnownFaults.cells
        for (family, lines) in faults.sorted(by: { $0.key < $1.key }) where known[family] == nil {
            Issue.record("\(family): \(lines.joined(separator: "; "))")
        }
        for (family, issue) in known.sorted(by: { $0.key < $1.key }) where faults[family] == nil {
            Issue.record("\(family) now passes: take it off MarkSpacingKnownFaults.cells (#\(issue))")
        }
    }

    /// What is wrong with the mark in `text`, or nil when its name stayed words or the mark sits where its row says.
    static func fault(in text: String, cell: Cell) -> String? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let name = cell.row.words
        if words.indices.contains(where: { words[$0...].starts(with: name) }) { return nil }
        guard let mark = cell.row.text.first else { return nil }
        if mark == ".", cell.position == .end, !stopsAlways(cell.destination) { return nil }
        let at = text.indices.filter { text[$0] == mark }
        guard !at.isEmpty else { return "the name went and no \(mark) was written" }
        return at.lazy.compactMap { spacingFault(at: $0, in: text, kind: cell.kind) }.first
    }

    /// Whether `destination` keeps a final stop; where it does not, a stop said last goes under its policy.
    private static func stopsAlways(_ destination: Destination) -> Bool {
        if case .always = DestinationFormatter.standard(for: destination).terminalStop { return true }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The side `kind` puts a mark on, checked against the characters either side of it.
    private static func spacingFault(at index: String.Index, in text: String, kind: SpokenMarkKind) -> String?
    {
        let before = index > text.startIndex ? text[text.index(before: index)] : nil
        let next = text.index(after: index)
        let after = next < text.endIndex ? text[next] : nil
        let spaceBefore = before?.isWhitespace ?? true
        let spaceAfter = after?.isWhitespace ?? true
        switch kind {
        case .trailing, .closing:
            if before == nil || spaceBefore { return "a space or nothing before \(text[index])" }
            return after.map(isWordCharacter) == true ? "a word glued after \(text[index])" : nil
        case .opening, .leading:
            if after == nil || spaceAfter { return "a space or nothing after \(text[index])" }
            return before.map(isWordCharacter) == true ? "a word glued before \(text[index])" : nil
        case .joining:
            return before == nil || after == nil || spaceBefore != spaceAfter
                ? "\(text[index]) spaced on one side only" : nil
        case .standalone:
            return spaceBefore && spaceAfter && before != nil && after != nil
                ? nil : "\(text[index]) not set apart"
        }
    }
}
