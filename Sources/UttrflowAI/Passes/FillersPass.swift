public import UttrflowCore

/// Removes hesitation sounds while keeping standalone replies and fixed interjections.
public struct FillersPass: PieceCleaningPass {
    public static let id: PassID = .fillers
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    public static let orderIndependentWith: Set<PassID> = [.repeatedPhrase]
    public static let removes: RemovalGrant = .sound

    /// Whole words that carry no meaning; "like", "well", "so", "basically" and "mm" (millimetres) are out.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm",
    ]

    /// Words a sentence sets off with a comma of its own, which a removed filler beside them leaves in place.
    static let discourseWords: Set<String> = [
        "yes", "no", "yeah", "okay", "ok", "well", "thanks", "so", "now", "actually",
    ]

    private static let standaloneReplies: Set<String> = ["hmm", "mhm"]
    /// Only er also names a noun; the other filler spellings remain sounds after determiners.
    private static let nounLikeFillerWords: Set<String> = ["er", "erm"]
    public init() {}

    /// Whether the comma before a bracketed filler belongs to the sentence rather than to the pause.
    private func sentenceOwnsComma(
        before: Int, fillerAt position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        if Self.discourseWords.contains(draft.shape(at: before).key) { return true }
        if position + 1 < live.count, Self.discourseWords.contains(draft.shape(at: live[position + 1]).key) {
            return true
        }
        guard let at = live.firstIndex(of: before) else { return false }
        // An opening content word owns its comma; a function word such as "I" in "I, um, think so" does not.
        if at == 0 { return FunctionWords.isContent(draft.shape(at: before).key) }
        let last = draft.words[live[at - 1]].text.last
        return last == "." || last == "?" || last == "!"
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var previous: Int?
        var consumed: Set<Int> = []
        for (position, index) in live.enumerated() {
            guard !consumed.contains(index) else { continue }
            if let unglued = Self.withoutGluedFillers(draft.words[index].text) {
                if unglued.isEmpty {
                    draft.remove(at: index, by: Self.id, carryingMarks: true)
                    continue
                }
                draft.replace(at: index, with: unglued, by: Self.id)
            }
            if let word = Self.withoutVowelEchoes(draft.words[index].text) {
                draft.replace(at: index, with: word, by: Self.id)
            }
            let word = draft.words[index].text
            if let pair = Self.interjection(at: position, in: live, of: draft) {
                let shape = draft.shape(at: index)
                let written = position == 0 ? WordShape.capitalised(pair.written) : pair.written
                draft.replace(at: index, with: shape.replacingCore(with: written), by: Self.id)
                draft.remove(at: pair.second, by: Self.id, carryingMarks: true)
                consumed.insert(pair.second)
                previous = index
                continue
            }
            if live.count == 1, Self.standaloneReplies.contains(draft.shape(at: index).key) {
                previous = index
                continue
            }
            // Only noun-capable filler spellings need protection when a determiner opens their noun phrase.
            guard Self.fillerWords.contains(draft.shape(at: index).key),
                !MentionGuard.namesToken(at: position, in: live, of: draft),
                !Self.nounLikeFillerWords.contains(draft.shape(at: index).key)
                    || position == 0
                    || !MentionGuard.isMentioned(at: position, spanning: 1, in: live, of: draft)
            else {
                previous = index
                continue
            }
            // A filler bracketed by commas takes the opening one too, unless the sentence needs it.
            if word.hasSuffix(","), let before = previous, draft.words[before].text.hasSuffix(","),
                !sentenceOwnsComma(before: before, fillerAt: position, in: live, of: draft)
            {
                draft.replace(
                    at: before, with: String(draft.words[before].text.dropLast()), by: Self.id)
            }
            if Self.stopIsThePause(at: position, in: live, of: draft) {
                Self.runOn(live[position + 1], in: &draft)
                draft.replace(at: index, with: draft.shape(at: index).core, by: Self.id)
            }
            draft.remove(at: index, by: Self.id, carryingMarks: true)
        }
        return draft
    }

    /// The token without the fillers an ellipsis glues to its words, keeping the ellipses between words; nil if none.
    static func withoutGluedFillers(_ token: String) -> String? {
        let characters = Array(token)
        var parts = [""]
        var joins: [String] = []
        var index = 0
        while index < characters.count {
            let length = ellipsisLength(in: characters, at: index)
            let joinsWords =
                length > 0 && index > 0 && index + length < characters.count
                && isWordCharacter(characters[index - 1]) && isWordCharacter(characters[index + length])
            if joinsWords {
                joins.append(String(characters[index..<(index + length)]))
                parts.append("")
                index += length
            } else {
                parts[parts.count - 1].append(characters[index])
                index += 1
            }
        }
        guard parts.count > 1 else { return nil }
        let isFiller = parts.map { part in
            let shape = WordShape(part)
            return shape.core.allSatisfy(\.isLetter) && fillerWords.contains(shape.key)
        }
        guard isFiller.contains(true) else { return nil }
        var kept = ""
        for (position, part) in parts.enumerated() where !isFiller[position] {
            if !kept.isEmpty { kept += joins[position - 1] }
            kept += part
        }
        if isFiller.last == true, !kept.isEmpty { kept += WordShape(parts[parts.count - 1]).suffix }
        return kept
    }

    /// Sounds that cannot start a stretched word, so "uh-oh" and "oh-oh" stay replies.
    private static let echoSounds: Set<String> = ["oh", "uh", "ah", "o", "u", "a"]

    /// The word without the hyphenated vowel echoes a stretched word is written with ("So-oh-oh" to "So"); nil if none.
    static func withoutVowelEchoes(_ token: String) -> String? {
        let shape = WordShape(token)
        let parts = shape.core.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1, let word = parts.first, let last = word.lowercased().last,
            word.allSatisfy(\.isLetter), !echoSounds.contains(word.lowercased()),
            !fillerWords.contains(word.lowercased())
        else { return nil }
        let isEcho = { (part: String) -> Bool in
            let lower = part.lowercased()
            guard let first = lower.first, first == last, "aou".contains(first) else { return false }
            return lower.allSatisfy { $0 == first || $0 == "h" }
                && lower.drop(while: { $0 == first }).allSatisfy { $0 == "h" }
        }
        guard parts.dropFirst().allSatisfy(isEcho) else { return nil }
        return shape.prefix + word + shape.suffix
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The length of a single-character or three-dot ellipsis starting at `index`, else 0.
    private static func ellipsisLength(in characters: [Character], at index: Int) -> Int {
        if characters[index] == SentenceMarks.ellipsis { return 1 }
        return characters[index...].prefix(3).elementsEqual("...") ? 3 : 0
    }

    /// Joins the two heard words that form a fixed assent or alarm reply.
    private static func interjection(
        at position: Int, in live: [Int], of draft: Draft
    ) -> (second: Int, written: String)? {
        guard position + 1 < live.count else { return nil }
        let first = draft.shape(at: live[position])
        let secondIndex = live[position + 1]
        let second = draft.shape(at: secondIndex)
        guard first.prefix.isEmpty, first.suffix.isEmpty, second.prefix.isEmpty
        else { return nil }
        let written: String
        switch (first.key, second.key) {
        case ("uh", "huh"): written = "uh-huh"
        case ("uh", "oh"): written = "uh-oh"
        case ("mm", "hmm"): written = "mm-hmm"
        default: return nil
        }
        return (secondIndex, written)
    }

    /// Whether the filler's full stop marks the pause in a clause: the next word runs on in lower case, or the one before cannot end a sentence.
    static func stopIsThePause(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard draft.shape(at: live[position]).suffix == ".", position > 0, position + 1 < live.count
        else { return false }
        let before = draft.words[live[position - 1]]
        let after = draft.words[live[position + 1]]
        let marks = WordShape(before.text).suffix
        guard !before.isLayoutMark, !after.isLayoutMark, marks.isEmpty || WordShape.trailsOff(marks)
        else { return false }
        return WordShape.lowercased(after.text) == after.text
            || FunctionWords.leadsOn(WordShape(before.text).key)
    }

    /// Lowers the capital the filler's stop gave the next word, unless it is "I", an acronym or a name the text shows.
    private static func runOn(_ index: Int, in draft: inout Draft) {
        let word = draft.words[index].text
        guard !FirstWordPass.keepsCapital(word), !FirstWordPass.looksLikeName(word, in: [draft.text]) else {
            return
        }
        draft.replace(at: index, with: WordShape.lowercased(word), by: Self.id)
    }
}
