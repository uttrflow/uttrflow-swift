// The text a suggestion pass is read through: echoes found, copies of the screen cut, runaway lines refused.

import Foundation
import NaturalLanguage
import UttrflowAI
import UttrflowCore
import UttrflowPredict

/// Everything done to a model's answer that is only text, kept apart from the model so it is tested and counted.
enum CompletionText {
    enum EchoPolicy {
        case required
        case joinAtBoundary
    }

    static let rejectedOpenings: [(phrase: String, rejectedAfterTypedEcho: Bool)] = [
        ("i'm sorry", true), ("i am sorry", true), ("sorry", false), ("i can't help", true),
        ("i cannot help", true), ("as an ai", true), ("as a language model", true),
        ("here is", false), ("here's", false), ("here are", false), ("the instructions say", true),
        ("your instruction says", true), ("your prompt says", true), ("to summarize your request", true),
    ]

    /// Turns a model reply into finished candidates under the echo rule for its generator.
    static func modelCompletions(
        from answer: String, typed: String, echoPolicy: EchoPolicy, in situation: GenerationSituation
    ) -> [String] {
        let context = contextNeverCopied(in: situation)
        let echoedTypedText = echoes(answer, of: typed)
        var lines = parse(answer, typed: typed).compactMap {
            trimmed($0, typed: typed, echoing: context)
        }
        if lines.isEmpty, case .joinAtBoundary = echoPolicy, !echoes(answer, of: typed),
            let joined = joinedContinuation(answer, typed: typed)
        {
            lines = parse(joined, typed: typed).compactMap {
                trimmed($0, typed: typed, echoing: context)
            }
        }
        let continuations = lines.filter { line in
            guard let added = continuation(of: line, past: typed) else { return false }
            return !isRejectedOpening(added, afterTypedEcho: echoedTypedText)
        }
        return finished(continuations, typed: typed, in: situation)
    }

    /// Joins an answer only when the parser can read the result as a non-empty extension.
    private static func joinedContinuation(_ answer: String, typed: String) -> String? {
        guard let joined = joined(typed, with: answer),
            let added = continuation(of: joined, past: typed), !added.isEmpty,
            parse(joined, typed: typed).contains(joined)
        else { return nil }
        return joined
    }

    /// Whether the added words start with a refusal or a remark about the model's instructions.
    private static func isRejectedOpening(_ continuation: String, afterTypedEcho: Bool) -> Bool {
        let continuationWords = words(of: continuation).map {
            $0.text.replacingOccurrences(of: "’", with: "'")
        }
        return rejectedOpenings.contains { opening in
            guard !afterTypedEcho || opening.rejectedAfterTypedEcho else { return false }
            let openingWords = words(of: opening.phrase).map(\.text)
            return continuationWords.starts(with: openingWords)
        }
    }

    /// The screen and the text before the line are context, never words to copy; the person's own lines may be repeated.
    static func contextNeverCopied(in situation: GenerationSituation) -> [String] {
        [situation.surroundings, situation.preceding].compactMap { $0 }
    }

    /// A label part shorter than this is a word any line may share; "Delivered" and longer are what a chat writes after a message.
    static let shortestLabelPart = 8

    /// The fewest characters a continuation that opens a new word must have to be a word at all.
    static let shortestNewWord = 3

    /// The line cut where its continuation takes up a part of a screen label — a comma-separated part, eight characters or more, repeated exactly, as "Received from Priya" is — its trailing timestamp parts dropped, or nothing when that leaves no continuation; a reply may still quote the screen in its own words, a shell a file name, a query a column list.
    static func trimmed(_ line: String, typed: String, echoing context: [String]) -> String? {
        let continuation = String(line.dropFirst(typed.count))
        let known = Set(
            context.flatMap { $0.split(whereSeparator: \.isNewline) }.flatMap { labelParts(of: String($0)) })
        var parts = continuation.split(separator: ", ", omittingEmptySubsequences: false).map(String.init)
        // The first part is the line's own words; only a part hung on a comma can be a label's.
        if let copied = parts.indices.dropFirst().first(where: { known.contains(fold(parts[$0])) }) {
            parts.removeSubrange(copied...)
        }
        // A stamp the model wrote after its line is as little the answer as one it copied; a time inside the line is its words.
        while parts.count > 1, let last = parts.last, Timestamps.isTimestamp(Substring(last)) {
            parts.removeLast()
        }
        var kept = Substring(parts.joined(separator: ", "))
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

    /// The fewest words in a row a continuation must share with the screen to be a copy rather than the person's own line.
    static let copiedRun = 5

    /// Whether the continuation repeats a run of screen words the person's own lines do not hold, counting only words the typed text does not finish.
    static func copiesContext(_ line: String, typed: String, context: [String], ownLines: [String]) -> Bool {
        let added = words(of: line).filter { $0.end > typed.count }.map(\.text)
        guard added.count >= copiedRun else { return false }
        let screen = Set(
            context.flatMap { $0.split(whereSeparator: \.isNewline) }.flatMap {
                runs(of: words(of: String($0)).map(\.text))
            })
        let own = Set(ownLines.flatMap { runs(of: words(of: $0).map(\.text)) })
        return runs(of: added).contains { screen.contains($0) && !own.contains($0) }
    }

    /// Every run of `copiedRun` words in a row, each joined by one space.
    private static func runs(of words: [String]) -> [String] {
        guard words.count >= copiedRun else { return [] }
        return (0...(words.count - copiedRun)).map { words[$0..<($0 + copiedRun)].joined(separator: " ") }
    }

    /// The words of a text lowercased, each with the character offset it ends at.
    private static func words(of text: String) -> [(text: String, end: Int)] {
        var found: [(text: String, end: Int)] = []
        var word = ""
        for (offset, character) in text.enumerated() {
            if character.isLetter || character.isNumber || character == "'" || character == "’" {
                word.append(contentsOf: character.lowercased())
            } else if !word.isEmpty {
                found.append((word, offset))
                word = ""
            }
        }
        if !word.isEmpty { found.append((word, text.count)) }
        return found
    }

    /// Marks that may close a sentence after its end mark, a quote or a bracket.
    private static let sentenceClosers: Set<Character> = ["\"", "'", ")", "”", "’", "]"]

    /// The line ended at the first sentence end its continuation reaches, or the whole line when it reaches none.
    static func firstSentence(of line: String, typed: String) -> String {
        let characters = Array(line)
        var index = typed.count
        while index < characters.count {
            guard SentenceMarks.ends.contains(characters[index]) else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < characters.count, SentenceMarks.ends.contains(characters[end + 1]) { end += 1 }
            let isEllipsis = end > index && characters[index...end].allSatisfy { $0 == "." }
            while end + 1 < characters.count, sentenceClosers.contains(characters[end + 1]) { end += 1 }
            // A mark with no space after it is inside a number, a name or an address, not at a sentence's end.
            if end + 1 < characters.count, characters[end + 1].isWhitespace, !isEllipsis,
                endsSentence(at: index, through: end, in: characters)
            {
                return String(characters[...end])
            }
            index = end + 1
        }
        return line
    }

    /// Whether the mark at `stop`, with its run through `end`, closes the sentence rather than an abbreviation.
    private static func endsSentence(at stop: Int, through end: Int, in characters: [Character]) -> Bool {
        var start = stop
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        let rest = characters[(end + 1)...].drop(while: \.isWhitespace)
        let next = rest.isEmpty ? nil : String(rest.prefix { !$0.isWhitespace })
        return Abbreviations.endsSentence(String(characters[start...end]), followedBy: next)
    }

    /// The lines a pass keeps once each is unsigned, ended at its first sentence where it is prose, grounded in its specifics and held to the register's length; prose that copies the screen is dropped.
    static func finished(_ lines: [String], typed: String, in situation: GenerationSituation) -> [String] {
        let register = Register.infer(from: situation, typed: typed)
        let context = contextNeverCopied(in: situation)
        var seen: Set<String> = []
        return lines.compactMap { line in
            var kept = line
            // A command or a query reuses the paths and names on screen, so only prose is held to its own words.
            if register.endsAtSentence {
                kept = firstSentence(of: kept, typed: typed)
                guard let whole = withoutDanglingEnd(kept, typed: typed) else { return nil }
                kept = whole
                guard
                    let unsigned = SignOff.unsigned(
                        kept, typed: typed, ownLines: situation.recentLines)
                else { return nil }
                kept = unsigned
                guard !copiesContext(kept, typed: typed, context: context, ownLines: situation.recentLines)
                else { return nil }
            } else {
                guard let unsigned = SignOff.unsigned(kept, typed: typed, ownLines: situation.recentLines)
                else { return nil }
                kept = unsigned
            }
            // A number, an amount or an address the model added is kept only where someone already wrote it; code keeps its conventional literals.
            let writesCode = !register.endsAtSentence && !register.answersFromHistoryAlone
            guard Specifics.areGrounded(kept, typed: typed, in: situation, writesCode: writesCode) else {
                return nil
            }
            guard kept.count - typed.count <= register.longestContinuation, seen.insert(kept).inserted
            else { return nil }
            return kept
        }
    }

    /// Prose cut back past an opening bracket or quote, a lone dash, or a conjunction or article at its end; nothing when the cut leaves no more than was typed.
    static func withoutDanglingEnd(_ line: String, typed: String) -> String? {
        var kept = withoutTrailingWhitespace(line)
        while kept.count > typed.count {
            let start = kept.lastIndex(where: \.isWhitespace).map { kept.index(after: $0) } ?? kept.startIndex
            let word = String(kept[start...])
            guard isDangling(word, endingLine: kept) else { return kept }
            kept = withoutTrailingWhitespace(String(kept[..<start]))
        }
        return nil
    }

    /// Whether the last word of a line leaves its phrase open.
    private static func isDangling(_ word: String, endingLine line: String) -> Bool {
        guard let last = word.last else { return false }
        if word.allSatisfy({ "-\u{2013}\u{2014}".contains($0) }) { return true }
        if let scalar = last.unicodeScalars.first, last.unicodeScalars.count == 1,
            scalar.properties.generalCategory == .openPunctuation
                || scalar.properties.generalCategory == .initialPunctuation
        {
            return true
        }
        if isStraightQuote(last), word.count == 1 || hasUnmatchedQuote(last, in: line) { return true }
        guard word.allSatisfy(\.isLetter), let tagged = LexicalClass.tags(in: line).last,
            tagged.word == word
        else { return false }
        // A determiner that can stand alone ("that", "some") ends a phrase; only one that leads on ("the", "my") leaves it open.
        return tagged.tag == .conjunction || (tagged.tag == .determiner && FunctionWords.leadsOn(word))
    }

    /// The comma-separated parts of one screen label long enough to be a label's own, as they compare.
    private static func labelParts(of label: String) -> [String] {
        label.split(separator: ", ").map { fold(String($0)) }.filter { $0.count >= shortestLabelPart }
    }

    /// Text as it compares for copying: lowercased, every kind of space the same space, ends trimmed.
    private static func fold(_ text: String) -> String {
        String(text.lowercased().map { $0.isWhitespace ? " " : $0 }).trimmingCharacters(in: .whitespaces)
    }

    /// The typed text with an answer that left out its echo joined where spaces or punctuation define a boundary; straight quotes open unless the typed text has an unmatched opener, and apostrophes inside words stay attached.
    static func joined(_ typed: String, with answer: String) -> String? {
        guard let last = typed.last, let first = answer.first else { return nil }
        if isStraightQuote(first) {
            if isWordApostrophe(first, at: typed, before: answer) { return typed + answer }
            if hasUnmatchedQuote(first, in: typed) {
                return withoutTrailingWhitespace(typed) + answer
            }
            let separator = last.isWhitespace ? "" : " "
            return typed + separator + answer
        }
        guard last.isWhitespace || first.isWhitespace || isClosingPunctuation(first) else { return nil }
        let prefix = isClosingPunctuation(first) ? withoutTrailingWhitespace(typed) : typed
        let continuation =
            last.isWhitespace && !isClosingPunctuation(first)
            ? answer.drop(while: \.isWhitespace) : answer[...]
        return prefix + continuation
    }

    /// The text without whitespace at its end.
    private static func withoutTrailingWhitespace(_ text: String) -> String {
        var trimmed = text
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        return trimmed
    }

    /// Whether a quote is the same straight mark as an unmatched opening quote in the typed text.
    private static func hasUnmatchedQuote(_ quote: Character, in typed: String) -> Bool {
        let characters = Array(typed)
        let marks = characters.indices.filter { index in
            characters[index] == quote
                && !(quote == "'" && isBetweenLetters(index, in: characters))
        }
        return !marks.count.isMultiple(of: 2)
    }

    /// Whether an apostrophe completes a word across the join.
    private static func isWordApostrophe(
        _ character: Character, at typed: String, before answer: String
    ) -> Bool {
        guard character == "'", let last = typed.last else { return false }
        let remaining = answer.dropFirst()
        return last.isLetter && remaining.first?.isLetter == true && !remaining.contains("'")
    }

    /// Whether this quote sits between letters in one text.
    private static func isBetweenLetters(_ index: Int, in characters: [Character]) -> Bool {
        index > 0 && index + 1 < characters.count
            && characters[index - 1].isLetter && characters[index + 1].isLetter
    }

    /// Whether a character is an ASCII straight quote.
    private static func isStraightQuote(_ character: Character) -> Bool {
        character == "'" || character == "\""
    }

    /// Closing punctuation attaches to the preceding word without a space.
    private static func isClosingPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        return scalar.properties.generalCategory == .closePunctuation
            || scalar.properties.generalCategory == .finalPunctuation
            || ",.!?;:%…".unicodeScalars.contains(scalar)
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
                !Self.closesTypedNumber(typed, with: continuation),
                SuggestionTextSafety.allows(continuation),
                Self.comparable(continuation).contains(where: { $0 != " " }),
                !promptMarkers.contains(where: continuation.lowercased().contains),
                !isDegenerate(continuation)
            else { continue }
            let whole = typed + continuation
            guard LatinScript.writesOnlyLatin(whole), seen.insert(whole).inserted else { continue }
            results.append(whole)
        }
        return results
    }

    /// Refuses a completion that ends a number the person may still be typing.
    private static func closesTypedNumber(_ typed: String, with continuation: String) -> Bool {
        guard typed.last?.isNumber == true, let first = continuation.first else { return false }
        if first.isNumber { return false }
        let remainder = Array(continuation.dropFirst())
        switch first {
        case ".", ",", "_":
            return remainder.first?.isNumber != true
        case "e", "E":
            let exponent =
                remainder.first == "+" || remainder.first == "-" ? Array(remainder.dropFirst()) : remainder
            return exponent.first?.isNumber != true
        default:
            return true
        }
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
        // A letter added to or changed in the echo must leave its whole word in an accepted form.
        let letterSlip = letterSlipNeedsSameForm(line, at: index, wanted: wanted, matched: matched)
        let sameWord =
            letterSlip && sameWordAfterAddedLetter(line, at: index, wanted: wanted, matched: matched)
        // An added apostrophe, space or other non-alphanumeric leaves every typed letter and digit unchanged.
        if sameWord || !(line[index].isLetter || line[index].isNumber) {
            resumes.append((next, matched))
        }
        if matched + piece.count < wanted.count, !letterSlip || sameWord {
            resumes.append((next, matched + piece.count))
        }
        for (start, matched) in resumes {
            if case .read(let end) = echo(of: wanted, in: line, from: start, matched: matched) { return end }
        }
        return nil
    }

    /// Whether this departure changes a letter rather than omitting the space before the next word.
    private static func letterSlipNeedsSameForm(
        _ line: String, at index: String.Index, wanted: [Character], matched: Int
    ) -> Bool {
        guard matched < wanted.count else { return line[index].isLetter }
        guard wanted[matched].isLetter || line[index].isLetter else { return false }
        guard wanted[matched].isWhitespace, line[index].isLetter else { return true }
        return wanted[matched...].drop(while: \.isWhitespace).first != line[index]
    }

    /// Whether an inserted letter leaves the echoed word in a form accepted for the typed word.
    private static func sameWordAfterAddedLetter(
        _ line: String, at index: String.Index, wanted: [Character], matched: Int
    ) -> Bool {
        guard line[index].isLetter else { return false }
        let probe = matched < wanted.count && wanted[matched].isLetter ? matched : matched - 1
        guard probe >= 0, wanted[probe].isLetter else { return false }
        let typedWordStart = wanted[..<probe].lastIndex(where: { !$0.isLetter }).map { $0 + 1 } ?? 0
        let typedWordEnd = wanted[probe...].firstIndex(where: { !$0.isLetter }) ?? wanted.count
        let echoWordStart =
            line[..<index].lastIndex(where: { !$0.isLetter }).map { line.index(after: $0) } ?? line.startIndex
        let echoWordEnd = line[index...].firstIndex(where: { !$0.isLetter }) ?? line.endIndex
        let typedWord = String(wanted[typedWordStart..<typedWordEnd])
        let echoWord = comparable(String(line[echoWordStart..<echoWordEnd]))
        return WordForms.sameForm(typedWord, echoWord)
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
        // A copied phrase loops even when each word appears only twice.
        if words.count >= 4 {
            for phraseLength in 2...(words.count / 2) {
                for start in 0...(words.count - 2 * phraseLength) {
                    let split = start + phraseLength
                    let end = split + phraseLength
                    if words[start..<split].elementsEqual(words[split..<end]) { return true }
                }
            }
        }
        if hasSpelledOutRun(words) { return true }
        // Six or more words drawn from a third as many distinct ones is a repetition, not a sentence.
        return words.count >= 6 && Set(words).count * 3 <= words.count
    }

    /// The fewest one-letter words in a row that spell a word out letter by letter rather than say anything.
    static let spelledOutRunLength = 4

    /// Whether the words hold a run of single letters, as in `a s s p o r t`, which no sentence has.
    static func hasSpelledOutRun(_ words: [Substring]) -> Bool {
        var run = 0
        for word in words {
            run = word.count == 1 && word.first?.isLetter == true ? run + 1 : 0
            if run >= spelledOutRunLength { return true }
        }
        return false
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
        let key = TextMatching.caseFoldedKey(context)
        guard !context.isEmpty, TextMatching.caseFoldedKey(candidate).hasPrefix(key) else { return "" }
        // A fold can change length, as ß against SS, so the opening is measured in folded text, not characters.
        var end = candidate.startIndex
        while end < candidate.endIndex {
            end = candidate.index(after: end)
            let opening = String(candidate[..<end])
            if TextMatching.caseFoldedKey(opening) == key { return opening }
        }
        return ""
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
