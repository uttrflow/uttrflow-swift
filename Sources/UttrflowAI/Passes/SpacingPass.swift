public import UttrflowCore

/// Fixes a mark that arrived as its own word onto the word before it when `MarkSpacing` says it goes there, splits a mark glued between two words, spaces every em dash as a spoken one is, and settles each run of marks to its legal form.
public struct SpacingPass: PieceCleaningPass {
    public static let id: PassID = .spacing
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

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
        var previous: Int?
        for index in draft.presentIndices {
            let text = draft.words[index].text
            if let previous, text.allSatisfy(MarkSpacing.attachesBefore) {
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

    /// "home—the" as "home —" and "the": every em dash written as `WordShape.marked` writes a spoken one, or nil when it already is.
    static func spacedDashes(_ text: String) -> [String]? {
        let dash: Character = "\u{2014}"
        guard text.contains(dash) else { return nil }
        var words: [String] = []
        for (position, part) in text.split(separator: dash, omittingEmptySubsequences: false).enumerated() {
            if position > 0 {
                if let last = words.popLast() {
                    words.append(WordShape.marked(last, with: String(dash)))
                } else {
                    words.append(String(dash))
                }
            }
            let word = part.trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { words.append(word) }
        }
        return words == [text] ? nil : words
    }

    /// "done.Next" as "done." and "Next", "the.env" as "the" and ".env": one mark between plain words, never a file, host or abbreviation.
    static func gluedHalves(_ text: String) -> (String, String)? {
        let marks = text.indices.filter { WordShape.clauseMarks.contains(text[$0]) }
        guard marks.count == 1, let at = marks.first else { return nil }
        let left = text[..<at]
        let right = text[text.index(after: at)...]
        let mark = text[at]
        // Before the file-name check: "the.env" reads as a file name, but a function word never starts one.
        if mark == ".", left.count >= 2, left.allSatisfy(\.isLetter), FunctionWords.holds(left.lowercased()),
            !right.isEmpty, right.allSatisfy(\.isLowercase)
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
