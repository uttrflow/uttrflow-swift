import UttrflowCore
import UttrflowDictionary

extension PassID {
    /// The capitals on the name a letter greets and the name it is signed with.
    static let letterNames: PassID = "letterNames"
}

/// Capitalises the words of a letter's greeting name and signature name: "dear ms alvarez," → "Dear Ms Alvarez,". See `Docs/cleanup.md`.
struct LetterNamesPass: WholeTextCleaningPass {
    static let id: PassID = .letterNames
    static let laws: Set<PassLaw> = [.addsNoWords, .idempotent, .keepsDigits, .latinOnly]

    /// The most words a greeting's name takes, as in `EmailStructurePass`.
    private static let longestName = 3

    /// Whether the pass first needs the text itself to be a letter, as it does outside an email.
    var requiresLetter = false
    /// The known spellings that start lower case, keyed in lower case; such a word is the user's to case.
    var ownSpellings: Set<String> = []

    init(requiresLetter: Bool = false, vocabulary: [String] = [], casing: AcronymCasingPass? = nil) {
        self.requiresLetter = requiresLetter
        ownSpellings = Set((casing ?? AcronymCasingPass(vocabulary: vocabulary)).lowerCaseForms.keys)
    }

    func apply(_ draft: Draft) -> Draft {
        guard !requiresLetter || TerminalStopPass.isLetter(draft) else { return draft }
        var draft = draft
        for index in Self.greetingName(in: draft) + TerminalStopPass.emailSignOffName(in: draft) {
            let shape = draft.shape(at: index)
            guard let written = capitalised(shape) else { continue }
            draft.replace(at: index, with: shape.replacingCore(with: written), by: Self.id)
        }
        return draft
    }

    /// The draft indices of the name a leading greeting opener holds: up to three words, the last closed by a comma or ending the paragraph.
    private static func greetingName(in draft: Draft) -> [Int] {
        let live = draft.presentIndices
        let paragraph = Array(live.prefix { !draft.words[$0].isLayoutMark })
        guard let opener = TerminalStopPass.greetingOpenerLength(paragraph, in: draft) else { return [] }
        let name = paragraph.dropFirst(opener).prefix(longestName)
        for (offset, index) in name.enumerated() {
            let closing = draft.shape(at: index).suffix
            if closing.contains(where: { ",.;:!?".contains($0) }) {
                return closing.contains(",") ? Array(name.prefix(offset + 1)) : []
            }
        }
        return paragraph.count - opener <= longestName ? Array(name) : []
    }

    /// The word's capitalised core when it is a name and not a particle, a function word, an everyday word or a spelling the user owns; nil otherwise.
    private func capitalised(_ shape: WordShape) -> String? {
        let core = shape.core
        let key = core.lowercased()
        guard core.count >= 2, core.allSatisfy(\.isLetter), core.allSatisfy(\.isLowercase),
            !ownSpellings.contains(key), !NameParticles.holds(key), !FunctionWords.holds(key),
            !KinshipWords.hindiNameTails.contains(key)
        else { return nil }
        let written = WordShape.capitalised(core)
        guard Abbreviations.kind(of: written) == .title || !GeneralVocabulary.isOrdinary(key) else {
            return nil
        }
        return written
    }
}
