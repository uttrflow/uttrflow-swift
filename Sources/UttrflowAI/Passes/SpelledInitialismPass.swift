public import UttrflowCore

/// Joins spoken letter names into an initialism, and letters then digits into one code, keeping "a" and "I" distinct.
public struct SpelledInitialismPass: WholeTextCleaningPass {
    public static let id: PassID = .spelledInitialism

    static let letterNames: [String: String] = [
        "a": "A", "b": "B", "be": "B", "bee": "B", "c": "C", "cee": "C", "see": "C",
        "d": "D", "dee": "D", "e": "E", "f": "F", "ef": "F", "eff": "F", "g": "G",
        "gee": "G", "h": "H", "aitch": "H", "i": "I", "eye": "I", "j": "J", "jay": "J",
        "k": "K", "kay": "K", "l": "L", "el": "L", "ell": "L", "m": "M", "em": "M",
        "n": "N", "en": "N", "o": "O", "oh": "O", "p": "P", "pee": "P", "q": "Q",
        "cue": "Q", "queue": "Q", "r": "R", "ar": "R", "are": "R", "s": "S", "ess": "S",
        "t": "T", "tee": "T", "u": "U", "you": "U", "v": "V", "vee": "V", "w": "W",
        "doubleu": "W", "x": "X", "ex": "X", "y": "Y", "why": "Y", "z": "Z", "zee": "Z",
        "zed": "Z",
    ]
    static let letterNamesForCasing = Set(letterNames.keys)

    /// Letter names that are also common English words, admitted only between single-letter names.
    private static let ambiguousLetterNames: Set<String> = [
        "are", "you", "why", "oh", "be", "see",
    ]

    /// True when `key` is an ambiguous letter name (one of the words in `ambiguousLetterNames`).
    private static func isAmbiguousLetterName(_ key: String) -> Bool {
        ambiguousLetterNames.contains(key)
    }

    /// True when `key` is the spoken form of a single letter — the unambiguous atoms of a run.
    private static func isSingleLetterName(_ key: String) -> Bool {
        letterNames[key] != nil && key.count == 1
    }

    private static let dottedPairs: Set<String> = ["eg", "ie"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = Self.joinHexTokens(in: draft)
        var live = draft.presentIndices
        var joined: Set<Int> = []
        var position = 0
        while position < live.count {
            guard let end = runEnd(from: position, in: live, draft: draft), end - position >= 2 else {
                position += 1
                continue
            }
            let letters = live[position..<end].compactMap { Self.letterName(draft.shape(at: $0)) }
            guard letters.count == end - position, Self.isSpelled(live[position..<end], in: draft) else {
                position += 1
                continue
            }
            let value = letters.joined()
            let first = live[position]
            let symbol =
                Self.followsNumber(position, in: live, draft: draft)
                ? Abbreviations.unitSymbol(spelled: value) : nil
            let output =
                Self.dottedPairs.contains(value.lowercased())
                ? letters.map { $0.lowercased() }.joined(separator: ".") + "."
                : value
            // The run keeps the mark its last letter carried, so a spoken stop or comma survives the join.
            let closing = draft.shape(at: live[end - 1]).suffix
            let cased = symbol ?? Self.casedOutput(output, first: draft.words[first].text)
            draft.replace(
                at: first, with: closing.isEmpty ? cased : WordShape.marked(cased, with: closing), by: Self.id
            )
            if symbol == nil, !output.contains(".") { joined.insert(first) }
            for index in live[(position + 1)..<end] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange((position + 1)..<end)
            position += 1
        }
        return Self.joinCodes(in: draft, initialisms: joined)
    }

    private enum CodePiece {
        case letters(String)
        case digits(String)
        case word(String)
    }

    private static let digitWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    /// What the word at `index` is inside a spoken code, or nil when it cannot be part of one.
    private static func codePiece(at index: Int, in draft: Draft, initialisms: Set<Int>) -> CodePiece? {
        let shape = draft.shape(at: index)
        if initialisms.contains(index) { return .letters(shape.core) }
        if shape.key.count == 1, let letter = letterName(shape) { return .letters(letter) }
        if !shape.key.isEmpty, shape.key.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return .digits(shape.key)
        }
        return digitWords[shape.key].map(CodePiece.word)
    }

    /// Writes a letter run touching digits as one code, abstaining when one bare letter meets one number word.
    private static func joinCodes(in draft: Draft, initialisms: Set<Int>) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var position = 0
        while position < live.count {
            if let prefixed = versionPrefix(at: position, in: live, draft: draft) {
                draft = prefixed
                position += 2
                continue
            }
            guard case .letters = codePiece(at: live[position], in: draft, initialisms: initialisms) else {
                position += 1
                continue
            }
            var pieces: [CodePiece] = []
            var end = position
            while end < live.count, !draft.words[live[end]].isLayoutMark,
                end == position
                    || touches(live[end - 1], live[end], in: draft)
                        && !draft.shape(at: live[end - 1]).endsClause,
                let piece = codePiece(at: live[end], in: draft, initialisms: initialisms)
            {
                pieces.append(piece)
                end += 1
            }
            let opening = draft.shape(at: live[position]).key
            let initialism = initialisms.contains(live[position])
            guard isCode(pieces, startsWithInitialism: initialism, opening: opening) else {
                position += 1
                continue
            }
            let value = pieces.map { piece in
                switch piece {
                case .letters(let text), .digits(let text): text
                case .word(let word): digitWords[word] ?? word
                }
            }.joined()
            let closing = draft.shape(at: live[end - 1]).suffix
            draft.replace(
                at: live[position], with: closing.isEmpty ? value : WordShape.marked(value, with: closing),
                by: id)
            for index in live[(position + 1)..<end] { draft.remove(at: index, by: id) }
            position = end
        }
        return draft
    }

    /// Whether nothing but letters this pass joined lies between two words.
    private static func touches(_ left: Int, _ right: Int, in draft: Draft) -> Bool {
        (left + 1..<right).allSatisfy { draft.words[$0].state == .removed(by: id) }
    }

    /// Whether pieces read as a code: three or more, or an initialism or a lone letter then three digits.
    private static func isCode(_ pieces: [CodePiece], startsWithInitialism: Bool, opening: String) -> Bool {
        let numbers = pieces.filter { if case .letters = $0 { false } else { true } }
        let letters = pieces.count - numbers.count
        guard !numbers.isEmpty else { return false }
        // The article or the pronoun opens a code only beside a second letter.
        if opening == "a" || opening == "i", !startsWithInitialism, letters < 2 { return false }
        if pieces.count >= 3 { return true }
        guard pieces.count == 2, case .digits(let digits) = pieces[1] else { return false }
        return startsWithInitialism || digits.count >= 3
    }

    /// A lower-case "v" or "x" before a dotted number is a version or architecture prefix, written without a space.
    private static func versionPrefix(at position: Int, in live: [Int], draft: Draft) -> Draft? {
        guard position + 1 < live.count, live[position + 1] == live[position] + 1 else { return nil }
        let prefix = draft.shape(at: live[position])
        let number = draft.shape(at: live[position + 1])
        guard prefix.core == "v" || prefix.core == "x", prefix.suffix.isEmpty,
            number.key.contains("."), number.key.first?.isNumber == true,
            number.key.allSatisfy({ $0.isNumber || $0 == "." })
        else { return nil }
        var draft = draft
        draft.replace(at: live[position], with: prefix.core + draft.words[live[position + 1]].text, by: id)
        draft.remove(at: live[position + 1], by: id)
        return draft
    }

    private func runEnd(from position: Int, in live: [Int], draft: Draft) -> Int? {
        guard position < live.count, Self.letterName(draft.shape(at: live[position])) != nil else {
            return nil
        }
        let token = draft.shape(at: live[position])
        let doubled = position + 1 < live.count && draft.shape(at: live[position + 1]).key == token.key
        let spelledDouble = doubled && Self.isSpelledRun(around: position, in: live, draft: draft)
        // The pronoun said twice running is a stammer, never an initialism.
        if token.key == "i", doubled, !spelledDouble {
            return nil
        }
        if token.key == "a", position + 1 < live.count,
            draft.shape(at: live[position + 1]).key == "m",
            isClockContext(before: position, in: live, draft: draft)
        {
            return position + 2
        }
        let inSpokenPhrase = position > 0 && !draft.shape(at: live[position - 1]).endsClause
        if token.key == "a", inSpokenPhrase, !spelledDouble, token.core.first?.isUppercase != true {
            let candidateEnd = candidateRunEnd(from: position, in: live, draft: draft)
            let value = live[position..<candidateEnd].compactMap { Self.letterName(draft.shape(at: $0)) }
                .joined().lowercased()
            guard candidateEnd - position >= 3 || Self.dottedPairs.contains(value) else { return nil }
        }
        let initialismStart = position
        // An ambiguous letter name never starts a run; the run begins on the next single letter.
        guard !Self.isAmbiguousLetterName(draft.shape(at: live[initialismStart]).key) else {
            return nil
        }
        var end = position + 1
        while end < live.count, !draft.shape(at: live[end - 1]).endsClause,
            live[end] == live[end - 1] + 1,
            !draft.words[live[end - 1]].isLayoutMark,
            !draft.words[live[end]].isLayoutMark,
            Self.letterName(draft.shape(at: live[end])) != nil,
            // Mid-run, an ambiguous letter name needs a single-letter name on each side.
            !Self.isAmbiguousLetterName(draft.shape(at: live[end]).key)
                || (Self.isSingleLetterName(draft.shape(at: live[end - 1]).key)
                    && (end + 1 == live.count
                        || Self.isSingleLetterName(draft.shape(at: live[end + 1]).key))),
            // A letter a closing a clause cannot be an article, so it ends the initialism.
            (draft.shape(at: live[end]).key != "a" || end == initialismStart
                || (draft.shape(at: live[end - 1]).key == "a"
                    || end + 1 < live.count && draft.shape(at: live[end + 1]).key == "a")
                    && Self.isSpelledRun(around: end, in: live, draft: draft)
                || end + 1 == live.count || draft.shape(at: live[end]).endsClause
                || end + 1 < live.count
                    && Self.letterName(draft.shape(at: live[end + 1])) != nil
                    && draft.shape(at: live[end + 1]).key != "a")
        {
            end += 1
        }
        return end
    }

    private func isClockContext(before position: Int, in live: [Int], draft: Draft) -> Bool {
        guard position > 0 else { return false }
        let previous = draft.shape(at: live[position - 1])
        if previous.key == "o'clock" { return true }
        if let hour = Int(previous.key), (1...12).contains(hour) { return true }
        let clock = previous.key.split(separator: ":", omittingEmptySubsequences: false)
        if clock.count == 2, let hour = Int(clock[0]), let minute = Int(clock[1]),
            (1...12).contains(hour), (0...59).contains(minute)
        {
            return true
        }
        return NumberWords.cardinal([previous.key]).map { (1...12).contains($0.value) } == true
    }

    private func candidateRunEnd(from position: Int, in live: [Int], draft: Draft) -> Int {
        var end = position
        while end < live.count, end == position || !draft.shape(at: live[end - 1]).endsClause,
            end == position || live[end] == live[end - 1] + 1,
            !draft.words[live[end]].isLayoutMark,
            Self.letterName(draft.shape(at: live[end])) != nil
        {
            end += 1
        }
        return end
    }

    /// Whether the letter at `position` sits in a spelled run: three or more single letters, or two beside a number.
    static func isSpelledRun(around position: Int, in live: [Int], draft: Draft) -> Bool {
        let isLetter = { (i: Int) in
            isSingleLetterName(draft.shape(at: live[i]).key) && letterName(draft.shape(at: live[i])) != nil
        }
        let joins = { (i: Int) in live[i] == live[i - 1] + 1 && !draft.shape(at: live[i - 1]).endsClause }
        guard position < live.count, isLetter(position) else { return false }
        var start = position
        while start > 0, joins(start), isLetter(start - 1) { start -= 1 }
        var end = position + 1
        while end < live.count, joins(end), isLetter(end) { end += 1 }
        if end - start >= 3 { return true }
        guard end - start == 2 else { return false }
        let numberBefore =
            start > 0 && joins(start) && NumberWords.isNumber(draft.shape(at: live[start - 1]).key)
        let numberAfter =
            end < live.count && joins(end) && NumberWords.isNumber(draft.shape(at: live[end]).key)
        return numberBefore || numberAfter
    }

    /// Whether a number, spoken or in digits, directly precedes the run at `position` in the same clause.
    private static func followsNumber(_ position: Int, in live: [Int], draft: Draft) -> Bool {
        guard position > 0, live[position] == live[position - 1] + 1 else { return false }
        let previous = draft.shape(at: live[position - 1])
        return !previous.endsClause && NumberWords.isNumber(previous.key)
    }

    /// The letter a word names, where a cut-off is an unfinished word and names no letter.
    private static func letterName(_ shape: WordShape) -> String? {
        shape.isCutOff ? nil : letterNames[shape.key]
    }

    /// Whether a run is evidence of spelling: three or more letter names, or a pair of bare single letters.
    private static func isSpelled(_ run: ArraySlice<Int>, in draft: Draft) -> Bool {
        run.count >= 3 || run.allSatisfy { draft.shape(at: $0).key.count == 1 }
    }

    private static func casedOutput(_ output: String, first: String) -> String {
        let shape = WordShape(first)
        guard shape.core.first?.isUppercase == true, !output.contains(".") else { return output }
        return WordShape.capitalised(output)
    }
}
