import Foundation
import UttrflowCore

/// The few names a surroundings read lets dictation keep, so spelling a colleague's name needs no more than the name.
enum SurroundingsNames {
    /// The most names one read keeps, which bounds what correction and the recogniser vocabulary ever see.
    static let maximum = 32

    /// The shortest name worth keeping; below this an initial or a stray capital matches everything.
    static let shortest = 2

    /// The names in the visible text, nearest the field first: capitalised words and @mentions, secret-shaped runs refused.
    static func names(in surroundings: Surroundings) -> [String] {
        guard let text = surroundings.text else { return [] }
        return names(inText: text)
    }

    /// The names in text that reads farthest first and ends at the field.
    static func names(inText text: String) -> [String] {
        let safe = SecretShapes.vocabulary(of: text)
        let runs = runs(in: safe)
        // A word seen in lower case anywhere is an ordinary word that began a sentence, not a name.
        let ordinary = Set(
            runs.filter { !$0.isMention && $0.word.first?.isLowercase == true }.map { $0.word.lowercased() })
        var seen: Set<String> = []
        var kept: [String] = []
        for run in runs.reversed() {
            guard kept.count < maximum, isName(run, ordinary: ordinary) else { continue }
            if seen.insert(run.word.lowercased()).inserted { kept.append(run.word) }
        }
        return kept
    }

    /// One word of the text and whether an at sign introduced it.
    private struct Run {
        let word: String
        let isMention: Bool
    }

    /// Chat labels for the two sides of a conversation, which are never a name to spell.
    private static let speakerLabels: Set<String> = ["me", "you"]

    private static func isName(_ run: Run, ordinary: Set<String>) -> Bool {
        let word = run.word
        guard word.count >= shortest, !SecretShapes.matches(word) else { return false }
        if run.isMention { return true }
        guard !speakerLabels.contains(word.lowercased()) else { return false }
        guard let first = word.first, first.isUppercase, word.contains(where: \.isLowercase),
            !word.contains(where: \.isNumber)
        else { return false }
        return !ordinary.contains(word.lowercased())
    }

    /// The text split into words of letters (with inner apostrophes and hyphens), a handle keeping its digits and dots.
    private static func runs(in text: String) -> [Run] {
        var runs: [Run] = []
        var current = ""
        var mention = false
        var opensWithAt = false
        func finish() {
            let word = current.trimmingCharacters(in: Self.joiners)
            if !word.isEmpty { runs.append(Run(word: word, isMention: mention)) }
            current = ""
            mention = false
            opensWithAt = false
        }
        for character in text {
            if character == "@", current.isEmpty {
                opensWithAt = true
            } else if character.isLetter || character.isNumber
                || (opensWithAt && (character == "_" || character == "."))
                || (!current.isEmpty && (character == "'" || character == "’" || character == "-"))
            {
                if opensWithAt { mention = true }
                current.append(character)
            } else {
                finish()
            }
        }
        finish()
        return runs
    }

    private static let joiners = CharacterSet(charactersIn: "'’-._")
}
