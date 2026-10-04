public import UttrflowCore

/// Joins consecutive spoken letter names into an initialism, keeping article "a" and pronoun "I" distinct.
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

    /// Letter names that are also everyday words; a run made only of these is speech, not spelling.
    static let everydayWords: Set<String> = [
        "a", "i", "be", "bee", "see", "are", "you", "why", "oh", "eye", "cue", "queue", "tee",
        "pee", "gee", "jay", "kay", "ex", "em", "en", "el",
    ]

    private static let dottedPairs: Set<String> = ["eg", "ie"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let end = runEnd(from: position, in: live, draft: draft), end - position >= 2 else {
                position += 1
                continue
            }
            let letters = live[position..<end].compactMap { Self.letterName(draft.shape(at: $0)) }
            guard letters.count == end - position else {
                position += 1
                continue
            }
            let hasBareLetter = live[position..<end].contains {
                !Self.everydayWords.contains(draft.shape(at: $0).key)
            }
            guard hasBareLetter else {
                position += 1
                continue
            }
            let value = letters.joined()
            let output =
                Self.dottedPairs.contains(value.lowercased())
                ? letters.map { $0.lowercased() }.joined(separator: ".") + "."
                : value
            let first = live[position]
            draft.replace(
                at: first, with: Self.casedOutput(output, first: draft.words[first].text), by: Self.id)
            for index in live[(position + 1)..<end] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange((position + 1)..<end)
            position += 1
        }
        return draft
    }

    private func runEnd(from position: Int, in live: [Int], draft: Draft) -> Int? {
        guard position < live.count, Self.letterName(draft.shape(at: live[position])) != nil else {
            return nil
        }
        let token = draft.shape(at: live[position])
        // The pronoun said twice running is a stammer, never an initialism.
        if token.key == "i", position + 1 < live.count, draft.shape(at: live[position + 1]).key == "i" {
            return nil
        }
        if token.key == "a", position + 1 < live.count,
            draft.shape(at: live[position + 1]).key == "m",
            isClockContext(before: position, in: live, draft: draft)
        {
            return position + 2
        }
        let inSpokenPhrase = position > 0 && !draft.shape(at: live[position - 1]).endsClause
        if token.key == "a", inSpokenPhrase, token.core.first?.isUppercase != true {
            let candidateEnd = candidateRunEnd(from: position, in: live, draft: draft)
            let value = live[position..<candidateEnd].compactMap { Self.letterName(draft.shape(at: $0)) }
                .joined().lowercased()
            guard candidateEnd - position >= 3 || Self.dottedPairs.contains(value) else { return nil }
        }
        let initialismStart = position
        var end = position + 1
        while end < live.count, !draft.shape(at: live[end - 1]).endsClause,
            live[end] == live[end - 1] + 1,
            !draft.words[live[end - 1]].isLayoutMark,
            !draft.words[live[end]].isLayoutMark,
            Self.letterName(draft.shape(at: live[end])) != nil,
            (draft.shape(at: live[end]).key != "a" || end == initialismStart
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
        while end < live.count, !draft.shape(at: live[end]).endsClause,
            end == position || live[end] == live[end - 1] + 1,
            !draft.words[live[end]].isLayoutMark,
            Self.letterName(draft.shape(at: live[end])) != nil
        {
            end += 1
        }
        return end
    }

    /// The letter a word names, where a cut-off is an unfinished word and names no letter.
    private static func letterName(_ shape: WordShape) -> String? {
        shape.isCutOff ? nil : letterNames[shape.key]
    }

    private static func casedOutput(_ output: String, first: String) -> String {
        let shape = WordShape(first)
        guard shape.core.first?.isUppercase == true, !output.contains(".") else { return output }
        return WordShape.capitalised(output)
    }
}
