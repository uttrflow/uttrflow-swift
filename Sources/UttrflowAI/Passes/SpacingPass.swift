public import UttrflowCore

/// Fixes a mark that arrived as its own word onto the word before it when `MarkSpacing` says it goes there, splits a mark glued between two words, spaces every em dash as a spoken one is, and settles each run of marks to its legal form.
public struct SpacingPass: PieceCleaningPass {
    public static let id: PassID = .spacing
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    public static let orderIndependentWith: Set<PassID> = [.pauseStop]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices.reversed() {
            let text = draft.words[index].text
            guard let words = Self.spacedDashes(text) ?? Self.gluedHalves(text).map({ [$0, $1] }),
                let first = words.first
            else { continue }
            draft.replace(at: index, with: first, by: Self.id)
            for (offset, word) in words.dropFirst().enumerated() {
                draft.insert(word, at: index + 1 + offset, by: Self.id)
            }
        }
        Self.joinNumbersAfterSymbols(&draft)
        var previous: Int?
        for index in draft.presentIndices {
            let text = draft.words[index].text
            if let previous, text.allSatisfy(MarkSpacing.attachesBefore),
                !Self.isWrittenSymbol(draft.words[index])
            {
                let merged = WordShape.settlingMarks(draft.words[previous].text + text)
                draft.replace(at: previous, with: merged, by: Self.id)
                draft.remove(at: index, by: Self.id)
                continue
            }
            draft.replace(at: index, with: WordShape.settlingMarks(text), by: Self.id)
            previous = index
        }
        return draft
    }

    /// The symbols that join the words on both sides of them in code, as "=" does in `--memory=2g`.
    private static let joiningSymbols = Set(
        SpokenCommands.codeSymbols.filter { $0.placement == .joining }.map(\.text))

    /// The one-letter size units a command-line value takes straight after its digits, as the "g" of `--memory=2g`.
    private static let sizeSuffixes = NumberCues.words(for: .sizeSuffix)

    /// Joins the digits a joining symbol waited for onto it, with a size unit after them, as `--memory=` and "2 g" are `--memory=2g`.
    private static func joinNumbersAfterSymbols(_ draft: inout Draft) {
        let live = draft.presentIndices
        var position = 0
        while position + 1 < live.count {
            let word = draft.words[live[position]]
            guard word.edits.last?.by == CodeEditorCommandsPass.id,
                joiningSymbols.contains(where: { endsNameThen($0, word.text) }),
                let digits = draft.words[live[position + 1]].text.first, digits.isNumber,
                draft.words[live[position + 1]].text.allSatisfy(\.isNumber)
            else {
                position += 1
                continue
            }
            var joined = word.text + draft.words[live[position + 1]].text
            draft.remove(at: live[position + 1], by: id)
            var next = position + 2
            if next < live.count, sizeSuffixes.contains(draft.words[live[next]].text.lowercased()) {
                joined += draft.words[live[next]].text
                draft.remove(at: live[next], by: id)
                next += 1
            }
            draft.replace(at: live[position], with: joined, by: id)
            position = next
        }
    }

    /// Whether `text` is a name with `symbol` written straight after it, as `--memory=` is and a lone `>=` is not.
    private static func endsNameThen(_ symbol: String, _ text: String) -> Bool {
        guard text.hasSuffix(symbol), let last = text.dropLast(symbol.count).last else { return false }
        return last.isLetter || last.isNumber || last == "_"
    }

    /// Whether a spoken name was written as a word of its own, as "dot" is "." in "git add dot", which stays apart from the word before it.
    private static func isWrittenSymbol(_ word: Draft.Word) -> Bool {
        word.edits.contains { $0.by == SpokenPunctuationPass.id && $0.kind == .replaced }
    }

    /// "home—the" as "home —" and "the": every mark `MarkSpacing` spaces on both sides written as `WordShape.marked` writes a spoken one, or nil when it already is.
    static func spacedDashes(_ text: String) -> [String]? {
        guard text.contains(where: MarkSpacing.spacesJoin) else { return nil }
        var words: [String] = []
        var part = ""
        func endPart() {
            let word = part.trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { words.append(word) }
            part = ""
        }
        for character in text {
            guard MarkSpacing.spacesJoin(character) else {
                part.append(character)
                continue
            }
            endPart()
            let mark = String(character)
            words.append(words.popLast().map { WordShape.marked($0, with: mark) } ?? mark)
        }
        endPart()
        return words == [text] ? nil : words
    }

    /// Labels a colon sets off from the clause it heads, which a colon glued to one is never code for ("status:blocked").
    private static let labelWords: Set<String> = [
        "status", "warning", "summary", "reminder", "question", "answer",
    ]

    /// "1:open" as "1:" and "open", and "status:blocked." as "status:" and "blocked.": a step number or a label word, then letters, which no time, ratio or port is.
    private static func gluedLabel(_ left: String, _ right: String) -> (String, String)? {
        let numbered = (1...3).contains(left.count) && left.allSatisfy { $0.isASCII && $0.isNumber }
        guard numbered || labelWords.contains(left.lowercased()) else { return nil }
        let word = String(right.reversed().drop { ",.?!".contains($0) }.reversed())
        guard word.count >= 2, word.allSatisfy(\.isLetter), !["am", "pm"].contains(word.lowercased()) else {
            return nil
        }
        return (left + ":", right)
    }

    /// "done.Next" as "done." and "Next", "the.env" as "the" and ".env": one mark between plain words, never a file, host or abbreviation.
    static func gluedHalves(_ text: String) -> (String, String)? {
        if text.filter({ $0 == ":" }).count == 1, TechnicalToken.classify(text) == nil,
            let colon = text.firstIndex(of: ":"),
            let halves = gluedLabel(String(text[..<colon]), String(text[text.index(after: colon)...]))
        {
            return halves
        }
        let marks = text.indices.filter { WordShape.clauseMarks.contains(text[$0]) }
        guard marks.count == 1, let at = marks.first else { return nil }
        let left = text[..<at]
        let right = text[text.index(after: at)...]
        let mark = text[at]
        // Only a dot-file name splits off a function word, as in "the.env"; "out.txt" and "in.sql" are files.
        if mark == ".", left.count >= 2, left.allSatisfy(\.isLetter), FunctionWords.holds(left.lowercased()),
            TechnicalToken.dotFileNames.contains(String(right))
        {
            return (String(left), "." + right)
        }
        guard TechnicalToken.classify(text) == nil else { return nil }
        // A glued colon or semicolon is code as often as prose ("api:latest", "a;b"), so neither splits.
        guard ",.?!".contains(mark), left.count >= 2, left.allSatisfy(\.isLetter), let first = right.first,
            right.allSatisfy(\.isLetter),
            Abbreviations.kind(of: String(left)) == nil
        else { return nil }
        let ending = right.lowercased()
        guard !TechnicalToken.fileExtensions.contains(ending), !TechnicalToken.topLevels.contains(ending)
        else {
            return nil
        }
        // A stop also joins names ("Draft.pages", "Self.id"), so it splits only lower case before Capitalised.
        if mark == "." {
            guard left.allSatisfy(\.isLowercase), first.isUppercase,
                right.dropFirst().allSatisfy(\.isLowercase)
            else { return nil }
        }
        return (left + String(mark), String(right))
    }
}
