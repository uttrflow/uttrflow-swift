public import UttrflowCore

/// Cases the first word the way the formatter's policy and the caret say.
public enum FirstWordRule {
    /// `heard` is the transcript, whose first word's case is what `.asSpoken` keeps.
    public static func apply(
        _ text: String, heard: String, policy: FirstWordPolicy, state: InsertionPoint.SentenceState
    ) -> String {
        switch policy {
        case .alwaysCapital:
            return replacingFirstCharacter(of: text) { $0.uppercased() }
        case .asSpoken:
            return matchingHeardCase(text, heard: heard)
        case .fromInsertionPoint:
            guard state == .midSentence, let first = firstWord(of: text), !keepsCapital(first) else {
                return text
            }
            return replacingFirstCharacter(of: text) { $0.isLetter ? $0.lowercased() : String($0) }
        }
    }

    /// Whether a word keeps its capital mid-sentence: "I" and its contractions, or an acronym.
    static func keepsCapital(_ word: Substring) -> Bool {
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I\u{2019}") { return true }
        let letters = word.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }

    /// Copies the case the output's first word was heard in, skipping any filler heard before it.
    private static func matchingHeardCase(_ text: String, heard: String) -> String {
        guard let written = firstWord(of: text)?.filter(\.isLetter).lowercased(), !written.isEmpty,
            let spoken = heard.split(whereSeparator: \.isWhitespace)
                .first(where: { $0.filter(\.isLetter).lowercased() == written }),
            let lead = spoken.first(where: \.isLetter)
        else { return text }
        return replacingFirstCharacter(of: text) { character in
            guard character.isLetter else { return String(character) }
            return lead.isUppercase ? character.uppercased() : character.lowercased()
        }
    }

    private static func firstWord(of text: String) -> Substring? {
        text.split(whereSeparator: \.isWhitespace).first
    }

    /// Rewrites the first character that is not whitespace, leaving everything else alone.
    private static func replacingFirstCharacter(
        of text: String, with transform: (Character) -> String
    ) -> String {
        guard let index = text.firstIndex(where: { !$0.isWhitespace }) else { return text }
        return text[..<index] + transform(text[index]) + text[text.index(after: index)...]
    }
}

/// Adds or withholds the final full stop the way the formatter's policy says.
public enum TerminalStopRule {
    public static func apply(_ text: String, policy: TerminalStopPolicy) -> String {
        switch policy {
        case .always:
            return TextTidy.ensureTerminalPunctuation(text)
        case .never:
            return withoutTrailingStop(text)
        case .offForShortMessages(let sentences):
            let finished = TextTidy.ensureTerminalPunctuation(text)
            guard sentenceCount(finished) <= sentences else { return finished }
            return withoutTrailingStop(finished)
        }
    }

    /// Takes back one trailing full stop; a question or exclamation mark, or an ellipsis, stays.
    static func withoutTrailingStop(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    /// How many sentences the text holds, counting a last one that has no mark yet.
    static func sentenceCount(_ text: String) -> Int {
        var count = 0
        var openSentence = false
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if sentenceEnds.contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // A stop between two digits is a decimal point, not the end of a sentence.
                let insideNumber = character == "." && (next?.isNumber ?? false)
                let endsHere = next == nil || (next?.isWhitespace ?? false)
                if openSentence, endsHere, !insideNumber {
                    count += 1
                    openSentence = false
                }
            } else if !character.isWhitespace {
                openSentence = true
            }
        }
        return count + (openSentence ? 1 : 0)
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}
