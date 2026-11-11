import UttrflowCore

/// A number, the unit said after it, or a negator that a pass lost or changed without a rule that allows it.
struct IntegrityViolation: Sendable, Equatable {
    /// What kind of word was changed.
    enum Kind: Sendable, Equatable {
        case number
        case unit
        case negator
    }

    /// The pass answerable for the change.
    let pass: PassID
    let kind: Kind
    /// The word as the recogniser heard it.
    let heard: String
}

/// Reads a draft for numbers, units and negators a pass altered or dropped. See `Docs/cleanup.md`.
enum IntegrityAudit {
    /// Every violation in the order the words were said; a change a removal grant covers is not one.
    static func violations(
        in draft: Draft, grants: [PassID: RemovalGrant]
    ) -> [IntegrityViolation] {
        let unauthorised = Set(RemovalAudit.unauthorisedPlaces(in: draft, grants: grants))
        let written = Set(WordTokens.words(draft.text.lowercased(), .comparison))
        let heard = draft.words.filter { !$0.isLayoutMark && !$0.heard.isEmpty }.map { WordShape($0.heard) }
        var found: [IntegrityViolation] = []
        var afterNumber = false
        var place = 0
        for index in draft.words.indices {
            let word = draft.words[index]
            guard !word.isLayoutMark, !word.heard.isEmpty else { continue }
            defer { place += 1 }
            let key = WordShape(word.heard).key
            if let kind = protectedKind(of: key, afterNumber: afterNumber),
                let pass = kind == .unit && key.count == 1
                    ? lostLetter(
                        at: index, in: draft, grants: grants, unauthorised: unauthorised.contains(index))
                    : answerable(
                        word, kind: kind, grants: grants,
                        unauthorised: unauthorised.contains(index) && !written.contains(key),
                        scaled: NumberFormsPass.sharedScaleDigits(at: place, heard: heard))
            {
                found.append(IntegrityViolation(pass: pass, kind: kind, heard: word.heard))
            }
            afterNumber = NumberWords.isNumber(key)
        }
        return found
    }

    /// What a heard word must keep: a numeral, a negator, or a unit straight after a number.
    private static func protectedKind(of key: String, afterNumber: Bool) -> IntegrityViolation.Kind? {
        if key.contains(where: \.isNumber) { return .number }
        if MeaningPreservationGuard.isNegation(key) { return .negator }
        guard afterNumber, key.allSatisfy(\.isLetter) else { return nil }
        return key.count > 1 || unitLetters.contains(key) ? .unit : nil
    }

    /// The unit symbols of one letter, from the number cues.
    static let unitLetters = NumberCues.words(for: .unitLetter)

    /// The pass that lost a unit letter; nil while it stands, joined on ("15k"), or correction took it back.
    private static func lostLetter(
        at index: Int, in draft: Draft, grants: [PassID: RemovalGrant], unauthorised: Bool
    ) -> PassID? {
        let word = draft.words[index]
        let pass: PassID
        switch word.state {
        case .kept, .inserted: return nil
        case .replaced(let by, _): pass = by
        case .removed(let by):
            let grant = grants[by] ?? .conversion
            if !unauthorised, grant == .retraction || grant == .repetition { return nil }
            pass = by
        }
        let letter = WordShape(word.heard).key
        let live = draft.words.indices.filter { draft.words[$0].isPresent && !draft.words[$0].isLayoutMark }
        let before = live.last { $0 < index }
        let after = live.first { $0 > index }
        let key = { (place: Int?) in place.map { WordShape(draft.words[$0].text).key } ?? "" }
        // A neighbour holds the letter only once a pass rewrote it, so an untouched "green" is not "g".
        let joined = { (place: Int?) in
            place.flatMap { WordShape(draft.words[$0].heard).key == key($0) ? nil : $0 }
        }
        let stands =
            key(word.isPresent ? index : nil).hasPrefix(letter) || key(joined(before)).hasSuffix(letter)
            || key(joined(after)).hasPrefix(letter)
        return stands ? nil : pass
    }

    /// The pass that lost or changed the word without a licence, or nil when it stands or a grant allows it.
    private static func answerable(
        _ word: Draft.Word, kind: IntegrityViolation.Kind, grants: [PassID: RemovalGrant],
        unauthorised: Bool, scaled: String?
    ) -> PassID? {
        switch word.state {
        case .removed(let pass):
            let grant = grants[pass] ?? .conversion
            let soundTookNegator = kind == .negator && grant == .sound
            let spokenCommand = kind == .unit && grant == .conversion
            return (unauthorised || soundTookNegator) && !spokenCommand ? pass : nil
        case .kept, .inserted:
            return nil
        case .replaced(let pass, _):
            return changed(word, kind: kind, scaled: scaled) ? pass : nil
        }
    }

    /// Whether the word as it reads now lacks what was heard; `scaled` is the digits a shared-scale range writes from the heard words there.
    private static func changed(_ word: Draft.Word, kind: IntegrityViolation.Kind, scaled: String?) -> Bool {
        let now = WordShape(word.text).key
        let heard = WordShape(word.heard).key
        switch kind {
        case .number:
            return digits(now) != digits(heard) && !writesItsValue(now, heard: heard) && digits(now) != scaled
        case .negator:
            return carries(now) && !letterRuns(now).contains(where: MeaningPreservationGuard.isNegation)
        case .unit: return plainWord(word.text) && now != heard
        }
    }

    /// Whether a grouped decimal, "2.5,000", now stands as the whole number its scale makes of it, "2,500".
    private static func writesItsValue(_ now: String, heard: String) -> Bool {
        NumberFormsPass.scaledGroupedDecimal(heard).map { String($0) == digits(now) } ?? false
    }

    /// Whether a word is spelled in letters or digits; an operator or a symbol is a command's spelling of what was said.
    private static func carries(_ key: String) -> Bool {
        key.contains { $0.isLetter || $0.isNumber }
    }

    /// Whether a word is nothing but letters, so a mark in it shows a command wrote it.
    private static func plainWord(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isLetter)
    }

    /// The runs of letters in a word, so "--no-cache" still holds the "no" said inside it.
    private static func letterRuns(_ key: String) -> [String] {
        WordTokens.words(key, .letters)
    }

    /// The digits of a word alone, so grouping and decimal marks do not read as a change.
    private static func digits(_ key: String) -> String { key.filter(\.isNumber) }
}
