// The text a suggestion pass is read through: echoes found, copies of the screen cut, runaway lines refused.

import Foundation
import UttrflowPredict

/// Everything done to a model's answer that is only text, kept apart from the model so it is tested and counted.
enum CompletionText {
    /// The screen and the text before the line are context, never words to copy; the person's own lines may be repeated.
    static func contextNeverCopied(in situation: GenerationSituation) -> [String] {
        [situation.surroundings, situation.preceding].compactMap { $0 }
    }

    /// A label part shorter than this is a word any line may share; "Delivered" and longer are what a chat writes after a message.
    static let shortestLabelPart = 8

    /// The fewest characters a continuation that opens a new word must have to be a word at all.
    static let shortestNewWord = 3

    /// The line cut where its continuation takes up a part of a screen label — a comma-separated part, eight characters or more, repeated exactly, as "Received from Priya" is — its timestamp parts dropped, or nothing when that leaves no continuation; a reply may still quote the screen in its own words, a shell a file name, a query a column list.
    static func trimmed(_ line: String, typed: String, echoing context: [String]) -> String? {
        let continuation = String(line.dropFirst(typed.count))
        let known = Set(
            context.flatMap { $0.split(whereSeparator: \.isNewline) }.flatMap { labelParts(of: String($0)) })
        var parts = continuation.split(separator: ", ", omittingEmptySubsequences: false).map(String.init)
        // The first part is the line's own words; only a part hung on a comma can be a label's.
        if let copied = parts.indices.dropFirst().first(where: { known.contains(fold(parts[$0])) }) {
            parts.removeSubrange(copied...)
        }
        let own = parts.joined(separator: ", ")
        // A stamp the model wrote after its line is as little the answer as one it copied.
        var kept = Substring(Timestamps.without(own))
        let changed = kept.count < continuation.count
        // The separator the copy or the stamp hung off is not part of the answer either.
        while changed, let last = kept.last, last.isWhitespace || last == "," || last == ";" {
            kept.removeLast()
        }
        let visible = kept.filter { !$0.isWhitespace }.count
        guard visible > 0 else { return nil }
        // A new word of one or two characters is a model made to go on when it meant to stop, not a word.
        if kept.first?.isWhitespace == true, visible < Self.shortestNewWord { return nil }
        return changed ? typed + String(kept) : line
    }

    /// The comma-separated parts of one screen label long enough to be a label's own, as they compare.
    private static func labelParts(of label: String) -> [String] {
        label.split(separator: ", ").map { fold(String($0)) }.filter { $0.count >= shortestLabelPart }
    }

    /// Text as it compares for copying: lowercased, every kind of space the same space, ends trimmed.
    private static func fold(_ text: String) -> String {
        String(text.lowercased().map { $0.isWhitespace ? " " : $0 }).trimmingCharacters(in: .whitespaces)
    }

    /// The typed text with an answer that left out its echo joined on, or nothing when no boundary says how: a space on either side, or punctuation opening the answer, joins as written; letters against letters could be the rest of a word or a new one run together, and no reading is better than a wrong line.
    static func joined(_ typed: String, with answer: String) -> String? {
        guard let last = typed.last, let first = answer.first else { return nil }
        guard last.isWhitespace || first.isWhitespace || first.isPunctuation else { return nil }
        return typed + answer
    }

    /// The text up to the last word cut by the budget, or nothing when the cut fell inside its only word.
    static func wholeWords(of text: String) -> String {
        guard let cut = text.lastIndex(where: \.isWhitespace) else { return "" }
        return String(text[..<cut])
    }

    /// How a turn opens when the next word is one of the machine's values: everything typed before that word, and each value with the space that leads into it.
    struct Choice: Equatable {
        /// What opens the model's turn, which is the line up to the word being chosen.
        let written: String
        /// Every value the word may be, each led by the whitespace that separates it from the line.
        let choices: [String]
    }

    /// The choice for a pass, or nothing when the machine offered no values.
    static func choice(of values: [String], at opening: Ask.Opening) -> Choice? {
        guard !values.isEmpty else { return nil }
        // A word finished with a space is written whole and the value follows it; a word still open is one of the values itself.
        guard !opening.isWordComplete else {
            return Choice(written: opening.written + opening.owed, choices: values.map { " " + $0 })
        }
        let lead = String(opening.owed.prefix { $0.isWhitespace })
        return Choice(written: opening.written, choices: values.map { lead + $0 })
    }

    /// The tokens a pass may spend: the register's share per line, capped, plus the echo of the line each answer repeats.
    static func tokenBudget(perLine: Int, lines: Int, echo: Int, cap: Int) -> Int {
        min(cap, perLine * lines) + echo * lines
    }

    /// The prompt's own headings, which a line quoting the prompt back carries and a real completion never does.
    static let promptMarkers = [
        "continue this text", "continue this line", "continue this reply", "continue this web address",
        "continue this command", "on screen around the field", "lines this person wrote here",
        "the text before the line reads", "hints:", "the next word is one of these",
    ]

    /// A continuation longer than this is a paragraph, not the rest of a line.
    static let maximumContinuationLength = 160

    /// The model's lines, kept only where they extend what was typed in the Latin alphabet, in order and without repeats.
    static func parse(_ response: String, typed: String) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        // The line is read without its indentation, so the echo is matched against the typed text without its own.
        let unindented = String(typed.drop(while: \.isWhitespace))
        for line in response.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            // A bullet or number the person typed is part of the line, so it is read as it is before it is unmarked.
            guard
                let continuation = Self.continuation(of: text, past: unindented)
                    ?? Self.continuation(of: Self.unmarked(text), past: unindented),
                Self.comparable(continuation).contains(where: { $0 != " " }),
                !promptMarkers.contains(where: text.lowercased().contains),
                !isDegenerate(continuation)
            else { continue }
            let whole = typed + continuation
            guard LatinScript.writes(whole), seen.insert(whole).inserted else { continue }
            results.append(whole)
        }
        return results
    }

    /// Whether an answer repeated the typed line anywhere in it, read exactly as `parse` reads an echo.
    static func echoes(_ answer: String, of typed: String) -> Bool {
        let unindented = String(typed.drop(while: \.isWhitespace))
        return answer.split(whereSeparator: \.isNewline).contains { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            return continuation(of: text, past: unindented) != nil
                || continuation(of: unmarked(text), past: unindented) != nil
        }
    }

    /// What the line adds past the typed text, read through the marks, case and spacing a model rewrites and one slip in its echo.
    static func continuation(of line: String, past typed: String) -> String? {
        let wanted = Array(comparable(typed))
        guard !wanted.isEmpty else { return line }
        var end: String.Index
        switch echo(of: wanted, in: line, from: line.startIndex, matched: 0) {
        case .read(let index):
            end = index
        case .slip(let index, let matched):
            guard let index = repaired(line, at: index, wanted: wanted, matched: matched) else { return nil }
            end = index
        case .short:
            return nil
        }
        // Marks ending the typed text fall out of the comparison, so the echo's copies are stepped over rather than added again.
        if typed.last.map(ignoredMarks.contains) == true {
            while end < line.endIndex, ignoredMarks.contains(line[end]) {
                end = line.index(after: end)
            }
        }
        return String(line[end...])
    }

    /// How far the echo of the typed text reads from a point in the line when no slip is allowed.
    private enum Echo {
        /// The typed text is all there, and the line goes on from here.
        case read(String.Index)
        /// The echo departs from the typed text at this character, with this many typed characters matched.
        case slip(at: String.Index, matched: Int)
        /// The line ends before the typed text does.
        case short
    }

    /// Reads the line against the typed text character by character, stopping at the first departure.
    private static func echo(
        of wanted: [Character], in line: String, from start: String.Index, matched: Int
    ) -> Echo {
        var matched = matched
        var index = start
        while matched < wanted.count, index < line.endIndex {
            let piece = Array(comparable(String(line[index])))
            // A further space in a run is the one already matched, since comparing folds a run to one space.
            let folded = piece == [" "] && matched > 0 && wanted[matched - 1] == " "
            guard folded || piece.isEmpty || wanted[matched...].starts(with: piece) else {
                return .slip(at: index, matched: matched)
            }
            if !folded { matched += piece.count }
            index = line.index(after: index)
        }
        return matched == wanted.count ? .read(index) : .short
    }

    /// Where the echo ends once one slip in it — two characters swapped, one added or one changed — is read past, or nothing.
    private static func repaired(
        _ line: String, at index: String.Index, wanted: [Character], matched: Int
    ) -> String.Index? {
        let piece = Array(comparable(String(line[index])))
        let next = line.index(after: index)
        var resumes: [(String.Index, Int)] = []
        // Two characters swapped are both there, so the echo is trusted through to its end.
        if piece.count == 1, matched + 1 < wanted.count, piece[0] == wanted[matched + 1],
            next < line.endIndex,
            comparable(String(line[next])) == String(wanted[matched])
        {
            resumes.append((line.index(after: next), matched + 2))
        }
        // An added character is stepped over; a changed one stands in for a typed one only when more typed text follows to vouch for it.
        resumes.append((next, matched))
        if matched + piece.count < wanted.count { resumes.append((next, matched + piece.count)) }
        for (start, matched) in resumes {
            if case .read(let end) = echo(of: wanted, in: line, from: start, matched: matched) { return end }
        }
        return nil
    }

    /// The text as it compares: lowercased, without the marks and repeated spaces a model tends to rewrite.
    static func comparable(_ text: String) -> String {
        var out = ""
        for character in text.lowercased() {
            if Self.ignoredMarks.contains(character) { continue }
            if character.isWhitespace {
                if out.last != " " { out.append(" ") }
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Marks a model drops or rewrites when it repeats a line, so they never decide whether it repeated it.
    static let ignoredMarks: Set<Character> = ["™", "®", "©", "\u{200E}", "\u{200F}", "\u{FEFF}"]

    /// Whether a continuation is the model looping or rambling rather than finishing the line.
    static func isDegenerate(_ continuation: String) -> Bool {
        guard continuation.count <= maximumContinuationLength else { return true }
        let words = continuation.split(whereSeparator: \.isWhitespace)
        // Six or more words drawn from a third as many distinct ones is a repetition, not a sentence.
        return words.count >= 6 && Set(words).count * 3 <= words.count
    }

    /// Strips a code fence, bullet, or numbering the model added despite being asked not to.
    static func unmarked(_ line: String) -> String {
        if line.hasPrefix("```") { return "" }
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        if let dot = line.firstIndex(of: "."), dot != line.startIndex,
            line[line.startIndex..<dot].allSatisfy(\.isNumber)
        {
            return String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// The opening of the candidate that is already typed, in the candidate's own spelling, or nothing when it does not carry the context.
    static func typedPart(of candidate: String, following context: String) -> String {
        guard !context.isEmpty, candidate.lowercased().hasPrefix(context.lowercased()) else { return "" }
        return String(candidate.prefix(context.count))
    }

    /// The first token the model is judged on, past the tokens the typed opening shares with the whole line.
    static func firstScoredIndex(whole: [Int], typed: [Int]) -> Int? {
        // Scoring starts where the two token streams actually diverge, since the join may retokenise.
        var shared = 0
        while shared < typed.count, shared < whole.count, typed[shared] == whole[shared] {
            shared += 1
        }
        // The first token has nothing before it to be predicted from, so it is never scored.
        let start = max(shared, 1)
        return whole.count > start ? start : nil
    }
}
