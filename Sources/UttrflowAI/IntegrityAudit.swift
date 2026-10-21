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
        var found: [IntegrityViolation] = []
        var afterNumber = false
        for index in draft.words.indices {
            let word = draft.words[index]
            guard !word.isLayoutMark, !word.heard.isEmpty else { continue }
            let key = WordShape(word.heard).key
            if let kind = protectedKind(of: key, afterNumber: afterNumber),
                let pass = answerable(
                    word, kind: kind, grants: grants,
                    unauthorised: unauthorised.contains(index) && !written.contains(key))
            {
                found.append(IntegrityViolation(pass: pass, kind: kind, heard: word.heard))
            }
            afterNumber = NumberWords.isNumber(key)
        }
        return found
    }

    /// What a heard word must keep: a numeral, a negator, or the word of two letters or more straight after a number.
    private static func protectedKind(of key: String, afterNumber: Bool) -> IntegrityViolation.Kind? {
        if key.contains(where: \.isNumber) { return .number }
        if MeaningPreservationGuard.isNegation(key) { return .negator }
        return afterNumber && key.count > 1 && key.allSatisfy(\.isLetter) ? .unit : nil
    }

    /// The pass that lost or changed the word without a licence, or nil when it stands or a grant allows it.
    private static func answerable(
        _ word: Draft.Word, kind: IntegrityViolation.Kind, grants: [PassID: RemovalGrant],
        unauthorised: Bool
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
            return changed(word, kind: kind) ? pass : nil
        }
    }

    /// Whether the word as it reads now lacks what was heard.
    private static func changed(_ word: Draft.Word, kind: IntegrityViolation.Kind) -> Bool {
        let now = WordShape(word.text).key
        let heard = WordShape(word.heard).key
        switch kind {
        case .number: return digits(now) != digits(heard) && !writesItsValue(now, heard: heard)
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
