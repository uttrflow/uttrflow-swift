/// What a trigger phrase needs to see before it takes anything back, so an everyday word is not mistaken for a correction.
public enum RestatementEvidence: String, Decodable, Sendable, Equatable {
    /// Two halves of the same shape: an aligned anchor, two numbers, or one content word replaced in the same slot.
    case alignedHalves
    /// As `alignedHalves`, but a one-word replacement also needs a comma pause before the trigger.
    case alignedHalvesPausedSingleWord
    /// Only a number whose following phrase is repeated after the trigger.
    case restatedNumber
    /// As `restatedNumber`, and only when a comma pause closes the trigger.
    case pausedRestatedNumber
}

/// One spoken phrase that announces a correction, its language, and the evidence it needs.
public struct CorrectionTrigger: DataTableRow, Equatable {
    /// The row's stable name.
    public let id: String
    /// The language the phrase is spoken in, as a BCP 47 code; Hindi is romanised.
    public let language: String
    /// The phrase, as lower-cased word keys.
    public let words: [String]
    /// What the phrase needs before it takes anything back.
    public let evidence: RestatementEvidence
}

/// Where the discarded half of a spoken correction begins, once a trigger phrase announces one. See `Docs/cleanup.md`.
public enum Restatement {
    /// The bundled trigger rows; with none loaded nothing is taken back.
    public static let table = DataTable<CorrectionTrigger>.load(
        "correction-triggers", schema: 1, from: .module, fallback: [])

    /// Phrases that announce a correction, longest first so "no sorry" is one trigger rather than two.
    public static let triggers: [[String]] = rows.map(\.words)

    private static let rows = table.rows.enumerated()
        .sorted { ($0.element.words.count, $1.offset) > ($1.element.words.count, $0.offset) }
        .map(\.element)

    private static let evidenceByPhrase = Dictionary(
        rows.map { ($0.words, $0.evidence) }, uniquingKeysWith: { first, _ in first })

    /// Whether the spoken layout phrase at a live position, of a length, asks for layout rather than naming it.
    public typealias LayoutDecision = (_ position: Int, _ length: Int, _ live: [Int], _ draft: Draft) -> Bool

    /// How many words back number corrections may reach.
    public static let reach = 6

    /// How many words back an anchor may reach when the restart repeats a phrase of two or more words.
    private static let repeatedPhraseReach = 12

    private static let copulas: Set<String> = ["am", "is", "are", "was", "were", "be", "being", "been"]

    /// Words that head an answer, which a second answer pairs with rather than takes back.
    public static let answerHeads: Set<String> = [
        "yes", "yeah", "yep", "no", "nope", "sorry", "thanks", "thank", "okay", "ok",
    ]

    /// Words a restated phrase may not anchor on, because a fresh clause starts with them far more often.
    public static let weakAnchors = Set(subjects + ["yes", "yeah", "ok", "okay", "oh", "well"])
        .union(contractedSubjects).union(HindiWords.subjects)

    /// English subject words, each of which heads a fresh clause.
    static let subjects = ["i", "we", "you", "he", "she", "they", "it", "that", "this", "there"]

    /// Every contracted form of a subject word ("he's", "we're", "they'll"), in either apostrophe.
    static let contractedSubjects = Set(
        subjects.flatMap { subject in
            ["s", "m", "re", "ll", "ve", "d"].flatMap { ending in
                ["'", "\u{2019}"].map { subject + $0 + ending }
            }
        })

    /// Whether a word is a weak anchor, reading a Devanagari word by its Latin spelling.
    static func isWeakAnchor(_ key: String) -> Bool {
        weakAnchors.contains(key)
            || (Romaniser.containsDevanagari(key)
                && HindiWords.subjects.contains(Romaniser.romanised(key).lowercased()))
    }

    /// How many words at `position` are trigger phrases run together, such as "no wait".
    public static func triggerRun(at position: Int, in live: [Int], of draft: Draft) -> Int {
        var length = 0
        while let next = triggerLength(at: position + length, in: live, of: draft) { length += next }
        return length
    }

    private static func triggerLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for trigger in triggers where position + trigger.count <= live.count {
            let keys = live[position..<position + trigger.count].map { draft.shape(at: $0).key }
            if keys == trigger { return trigger.count }
        }
        return nil
    }

    /// Where the discarded half starts, or nil when the halves do not match in shape.
    public static func discardedStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft,
        asksForLayout: LayoutDecision = { _, _, _, _ in true }
    ) -> Int? {
        guard trigger > 0 else { return nil }
        let earliest = max(0, trigger - reach)
        let earliestPhraseAnchor = max(0, trigger - repeatedPhraseReach)
        let firstAfter = draft.shape(at: live[restart]).key
        let triggerWords = live[trigger..<restart].map { draft.shape(at: $0).key }
        let evidence = evidenceByPhrase[triggerWords] ?? .alignedHalves
        switch evidence {
        case .restatedNumber:
            return restatedNumberStart(before: trigger, after: restart, in: live, of: draft)
        case .pausedRestatedNumber:
            guard draft.shape(at: live[restart - 1]).suffix.contains(",") else { return nil }
            return restatedNumberStart(before: trigger, after: restart, in: live, of: draft)
        case .alignedHalves, .alignedHalvesPausedSingleWord: break
        }
        guard !isReportedAnswer(triggerWords, before: trigger, in: live, of: draft) else { return nil }
        let through = standsAlone(trigger, before: restart, in: live, of: draft)
        if isHindiOrDigitNumber(firstAfter) {
            guard let end = numberEnd(before: trigger, after: restart, in: live, of: draft) else {
                return nil
            }
            guard through || !endsSentence(trigger - 1, in: live, of: draft) else { return nil }
            let start = numberStart(through: end, from: earliest, in: live, of: draft)
            guard !coordinates(start, before: trigger, in: live, of: draft) else { return nil }
            return start
        }
        guard !isWeakAnchor(firstAfter) else { return nil }
        let replacesOneWord = replacesSingleWord(
            before: trigger, after: restart, evidence: evidence, in: live, of: draft)
        for candidate in stride(from: trigger - 1, through: earliestPhraseAnchor, by: -1) {
            // A spoken line or paragraph break closes what came before it, so nothing behind it is taken back.
            guard !endsSpokenLayout(candidate, in: live, of: draft, asksForLayout: asksForLayout) else {
                return nil
            }
            let spanStart = camelCaseAnchorStart(
                draft.shape(at: live[candidate]).key,
                the: draft.shape(at: live[restart]).core,
                endingAt: candidate,
                in: live,
                of: draft)
            if let anchor = spanStart,
                anchor >= earliest
                    || repeatsPhrase(from: candidate, before: trigger, after: restart, in: live, of: draft)
            {
                let spanStart = doubledStart(of: anchor, after: restart, in: live, of: draft)
                guard holdsContent(spanStart..<trigger, in: live, of: draft),
                    !coordinates(spanStart, before: trigger, in: live, of: draft)
                else { return nil }
                return spanStart
            }
            if endsSentence(candidate, in: live, of: draft), !(through && candidate == trigger - 1) {
                return replacesOneWord ? trigger - 1 : nil
            }
        }
        return replacesOneWord ? trigger - 1 : nil
    }

    /// A bare no after a copula and before a comma completes a reported answer clause.
    private static func isReportedAnswer(
        _ trigger: [String], before position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger == ["no"], position > 0,
            copulas.contains(draft.shape(at: live[position - 1]).key),
            draft.shape(at: live[position]).suffix.contains(",")
        else { return false }
        return true
    }

    /// A number is taken back only when the phrase after it repeats, so ordinary negation and filler stay intact.
    private static func restatedNumberStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        guard restart < live.count else { return nil }
        let replacement = draft.shape(at: live[restart]).key
        guard isHindiOrDigitNumber(replacement) else { return nil }

        let earliest = max(0, trigger - reach)
        if trigger > earliest {
            for start in stride(from: trigger - 1, through: earliest, by: -1)
            where isHindiOrDigitNumber(draft.shape(at: live[start]).key) {
                let oldTail = live[(start + 1)..<trigger].map { draft.shape(at: $0).key }
                let newTailStart = restart + 1
                let newTailEnd = newTailStart + oldTail.count
                guard !oldTail.isEmpty, newTailEnd <= live.count else { continue }
                let newTail = live[newTailStart..<newTailEnd].map { draft.shape(at: $0).key }
                guard oldTail == newTail,
                    !(start..<trigger).contains(where: { endsSentence($0, in: live, of: draft) }),
                    !(restart..<newTailEnd).contains(where: { endsSentence($0, in: live, of: draft) })
                else { continue }
                return start
            }
        }

        guard trigger > 0 else { return nil }
        let oldNumber = draft.shape(at: live[trigger - 1]).key
        return isHindiOrDigitNumber(oldNumber) ? trigger - 1 : nil
    }

    /// Whether a word is a supported romanised Hindi, English or digit number.
    private static func isHindiOrDigitNumber(_ key: String) -> Bool {
        NumberWords.hindi[key] != nil || NumberWords.isNumber(key)
    }

    /// Whether a trigger sits between two content words in one sentence, replacing the word directly before it.
    private static func replacesSingleWord(
        before trigger: Int, after restart: Int, evidence: RestatementEvidence, in live: [Int],
        of draft: Draft
    ) -> Bool {
        guard trigger > 0, restart < live.count,
            !endsSentence(trigger - 1, in: live, of: draft),
            FunctionWords.isContent(draft.shape(at: live[trigger - 1]).key),
            FunctionWords.isContent(draft.shape(at: live[restart]).key),
            !coordinates(trigger - 1, before: trigger, in: live, of: draft)
        else { return false }

        // Triggers that are also everyday words join content words too, so their pause must corroborate the correction.
        if evidence == .alignedHalvesPausedSingleWord {
            guard draft.shape(at: live[trigger - 1]).suffix.contains(",") else { return false }
        }
        return takesSameSlot(before: trigger, after: restart, in: live, of: draft)
    }

    /// Whether the word after the trigger takes the word class, in that sentence, of the word before it.
    private static func takesSameSlot(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        var start = trigger - 1
        while start > 0, !endsSentence(start - 1, in: live, of: draft) { start -= 1 }
        var end = restart
        while end < live.count - 1, !endsSentence(end, in: live, of: draft) { end += 1 }
        let key = { (position: Int) in draft.shape(at: live[position]).key }
        return WordSlot.fits(
            replacing: key(trigger - 1), after: (start..<trigger - 1).map(key),
            with: (restart...end).map(key))
    }

    /// Where the anchor's run of one word said again starts, reaching back as far as the restart opens on that word said again.
    private static func doubledStart(
        of anchor: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int {
        let key = { (position: Int) in draft.shape(at: live[position]).key }
        var start = anchor
        while start > 0, restart + anchor - start + 1 < live.count,
            !endsSentence(start - 1, in: live, of: draft),
            key(start - 1) == key(anchor), key(restart + anchor - start + 1) == key(restart)
        {
            start -= 1
        }
        return start
    }

    /// Whether the word after an anchor matches the word after the restart, so the restart repeats a phrase rather than one word.
    private static func repeatsPhrase(
        from candidate: Int, before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard candidate + 1 < trigger, restart + 1 < live.count else { return false }
        return draft.shape(at: live[candidate + 1]).key == draft.shape(at: live[restart + 1]).key
    }

    /// A camel-case word can retain a heard word ending at one of its components, such as `payment` in `PaymentSheet`.
    private static func camelCaseAnchorStart(
        _ heard: String, the written: String, endingAt candidate: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        if heard == written.lowercased() { return candidate }
        guard heard.count >= 3 else { return nil }
        let components = camelCaseComponents(in: written)
        guard let component = components.firstIndex(where: { $0.lowercased() == heard }) else { return nil }
        let start = candidate - component
        guard start >= 0 else { return nil }
        let spoken = live[start...candidate].map { draft.shape(at: $0).key }
        guard spoken == components.prefix(component + 1).map({ $0.lowercased() }) else { return nil }
        return start
    }

    private static func camelCaseComponents(in written: String) -> [String] {
        let characters = Array(written)
        guard !characters.isEmpty else { return [] }
        var boundaries = [characters.startIndex]
        for index in characters.indices.dropFirst() {
            let previous = characters[characters.index(before: index)]
            let current = characters[index]
            let next = characters.index(after: index)
            let startsWord = previous.isLowercase && current.isUppercase
            let endsAcronym =
                previous.isUppercase && current.isUppercase
                && next < characters.endIndex && characters[next].isLowercase
            if startsWord || endsAcronym { boundaries.append(index) }
        }
        boundaries.append(characters.endIndex)
        return zip(boundaries, boundaries.dropFirst()).map { String(characters[$0..<$1]) }
    }

    /// Whether the trigger is a sentence of its own after a full stop ("Tuesday. Scratch that. Wednesday"), which is a pause rather than two sentences.
    public static func standsAlone(
        _ trigger: Int, before restart: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger > 0, restart > trigger, restart <= live.count else { return false }
        let phrase = (trigger..<restart).map { draft.shape(at: live[$0]) }
        // A bare "No." is an answer far more often than a correction.
        guard phrase.map(\.key) != ["no"] else { return false }
        return closesWithAStop(trigger - 1, in: live, of: draft)
            && closesWithAStop(restart - 1, in: live, of: draft)
            && phrase.allSatisfy { !$0.suffix.contains(where: { "?!".contains($0) }) }
    }

    /// Whether the word ends its sentence with a full stop, rather than a question or an exclamation.
    private static func closesWithAStop(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        let suffix = draft.shape(at: live[position]).suffix
        return suffix.contains(".") && !suffix.contains(where: { "?!".contains($0) })
    }

    /// The last word of the number taken back, stepping over a unit the restatement repeats ("twelve boxes i mean fifteen boxes").
    private static func numberEnd(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let unit = trigger - 1
        let unitKey = draft.shape(at: live[unit]).key
        if isHindiOrDigitNumber(unitKey) { return unit }
        guard unit > 0, isHindiOrDigitNumber(draft.shape(at: live[unit - 1]).key),
            !endsSentence(unit - 1, in: live, of: draft)
        else { return nil }
        var next = restart
        while next < live.count, isHindiOrDigitNumber(draft.shape(at: live[next]).key) {
            // A unit past a stop belongs to the next sentence, not to this restatement.
            guard !endsSentence(next, in: live, of: draft) else { return nil }
            next += 1
        }
        guard next < live.count, draft.shape(at: live[next]).key == unitKey else { return nil }
        return unit - 1
    }

    /// The first word of the number ending at `end`, reading a spoken "oh" between digits as the zero it stands for.
    private static func numberStart(
        through end: Int, from earliest: Int, in live: [Int], of draft: Draft
    ) -> Int {
        var start = end
        while start > earliest, !endsSentence(start - 1, in: live, of: draft) {
            let key = draft.shape(at: live[start - 1]).key
            guard isHindiOrDigitNumber(key) || NumberWords.spokenDigit(key) != nil else { break }
            start -= 1
        }
        // An "oh" before every digit is an exclamation rather than a zero.
        while start < end, !isHindiOrDigitNumber(draft.shape(at: live[start]).key) { start += 1 }
        return start
    }

    /// Whether the word at `position` closes a sentence, which no anchor may reach past to take words out of the sentence before.
    private static func endsSentence(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        draft.shape(at: live[position]).endsSentence
    }

    /// Whether a spoken layout command, such as "new paragraph", ends at `position`, said as layout rather than named.
    private static func endsSpokenLayout(
        _ position: Int, in live: [Int], of draft: Draft, asksForLayout: LayoutDecision
    ) -> Bool {
        SpokenCommands.layout.contains { command in
            let start = position + 1 - command.words.count
            return start >= 0 && draft.spells(command.words, at: start, in: live, acrossSentences: true)
                && asksForLayout(start, command.words.count, live, draft)
        }
    }

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }

    /// Whether the trigger heads each item of a list rather than correcting one: the word before the half it would take back is the trigger over again, or an answer this trigger answers ("yes … no …", "thanks … sorry …").
    private static func coordinates(
        _ start: Int, before trigger: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard start > 0 else { return false }
        let before = draft.shape(at: live[start - 1]).key
        let head = draft.shape(at: live[trigger]).key
        return before == head || (answerHeads.contains(before) && answerHeads.contains(head))
    }
}
