public import UttrflowCore

/// Fixes a mark that arrived as its own word onto the word before it, splits a mark glued between two words, and collapses doubled clause marks.
public struct SpacingPass: PieceCleaningPass {
    public static let id: PassID = .spacing

    static let clauseMarks: Set<Character> = [",", ".", "?", "!", ":", ";"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices.reversed() {
            guard let (left, right) = Self.gluedHalves(draft.words[index].text) else { continue }
            draft.replace(at: index, with: left, by: Self.id)
            draft.insert(right, at: index + 1, by: Self.id)
        }
        var previous: Int?
        for index in draft.presentIndices {
            let text = draft.words[index].text
            if let previous, text.allSatisfy(Self.clauseMarks.contains) {
                let merged = Self.collapsed(draft.words[previous].text + text)
                draft.replace(at: previous, with: merged, by: Self.id)
                draft.remove(at: index, by: Self.id)
                continue
            }
            draft.replace(at: index, with: Self.collapsed(text), by: Self.id)
            previous = index
        }
        return draft
    }

    /// "done.Next" as "done." and "Next", "the.env" as "the" and ".env": one mark between plain words, never a file, host or abbreviation.
    static func gluedHalves(_ text: String) -> (String, String)? {
        let marks = text.indices.filter { clauseMarks.contains(text[$0]) }
        guard marks.count == 1, let at = marks.first, TechnicalToken.classify(text) == nil else { return nil }
        let left = text[..<at]
        let right = text[text.index(after: at)...]
        let mark = text[at]
        // A glued colon or semicolon is code as often as prose ("api:latest", "a;b"), so neither splits.
        guard ",.?!".contains(mark), left.count >= 2, left.allSatisfy(\.isLetter), let first = right.first,
            right.allSatisfy(\.isLetter),
            Abbreviations.kind(of: String(left)) == nil
        else { return nil }
        // A function word never starts a dotted name, so the dot opens a dot-file name after it: "the.env".
        if mark == ".", FunctionWords.holds(left.lowercased()), right.allSatisfy(\.isLowercase) {
            return (String(left), "." + right)
        }
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

    /// The word with a run of the same comma, colon, semicolon, question mark or exclamation mark at its end reduced to one.
    private static func collapsed(_ text: String) -> String {
        guard let last = text.last, ",;:?!".contains(last) else { return text }
        var trimmed = text
        while trimmed.count > 1, trimmed.dropLast().last == last { trimmed.removeLast() }
        return trimmed
    }
}
