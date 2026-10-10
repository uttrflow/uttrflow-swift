// What an alias is: the one reduction both saving and matching use, and what saving one would do.
public import Foundation
public import UttrflowClipboard

/// What would happen if this alias were saved: what is stored, whether it changed, and who has it.
public struct AliasProposal: Sendable, Equatable {
    /// What will be stored — the typed text after correction.
    public let corrected: String
    /// Whether correction changed anything, for the quiet note under the field; not an error.
    public let wasCorrected: Bool
    /// The clip that already answers to this alias, if there is one.
    public let takenBy: Clip.ID?
    /// Whether the spelling mixes writing systems that cannot be resolved to one script.
    public let mixesScripts: Bool
    /// Whether the bundled Unicode data was available for the comparison.
    public let canCompareUnicodeNames: Bool

    /// An empty alias is not a conflict, it is simply nothing to save.
    public var isUsable: Bool {
        !corrected.isEmpty && takenBy == nil && !mixesScripts && canCompareUnicodeNames
    }

    /// Builds a proposal.
    public init(
        corrected: String, wasCorrected: Bool, takenBy: Clip.ID?, mixesScripts: Bool = false,
        canCompareUnicodeNames: Bool = true
    ) {
        self.corrected = corrected
        self.wasCorrected = wasCorrected
        self.takenBy = takenBy
        self.mixesScripts = mixesScripts
        self.canCompareUnicodeNames = canCompareUnicodeNames
    }
}

/// The one place that decides what an alias is, so creation and matching cannot disagree.
public enum PanelAlias {
    /// An alias reduced to what identifies it: no leading slash, no whitespace, case, accents and width folded.
    public static func handle(_ text: String, locale: Locale) -> String {
        String(
            text
                .filter { !$0.isWhitespace }
                .drop { $0 == "/" }
        )
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }

    /// Whether two aliases are one name: equal under the search comparison, which ignores a nukta, or
    /// confusable when either handle holds a non-ASCII character, so `m1` and `ml` stay distinct.
    static func matches(_ first: String, _ second: String, locale: Locale) -> Bool {
        guard case .success(let rules) = AliasUnicodeRules.loaded else { return false }
        let firstHandle = handle(first, locale: locale)
        let secondHandle = handle(second, locale: locale)
        if firstHandle.equals(secondHandle, ignoringCaseAndAccentsIn: locale) { return true }
        guard !(firstHandle + secondHandle).unicodeScalars.allSatisfy(\.isASCII) else { return false }
        return rules.skeleton(first, locale: locale) == rules.skeleton(second, locale: locale)
    }

    /// What saving `typed` as `clip`'s alias would do; the clip itself is not a conflict with itself.
    public static func propose(
        _ typed: String, for clip: Clip.ID, among clips: [Clip], locale: Locale
    ) -> AliasProposal {
        let corrected = handle(typed, locale: locale)
        // Compared against the typed text minus its slash, so dropping the slash is not a correction.
        let asTyped = String(typed.drop { $0 == "/" })
        guard case .success(let rules) = AliasUnicodeRules.loaded else {
            return AliasProposal(
                corrected: corrected, wasCorrected: !corrected.isEmpty && corrected != asTyped,
                takenBy: nil, canCompareUnicodeNames: false)
        }
        let mixesScripts = rules.mixesScripts(typed)
        let holder = clips.first {
            $0.id != clip && $0.alias.map { matches($0, typed, locale: locale) } == true
        }
        return AliasProposal(
            corrected: corrected,
            wasCorrected: !corrected.isEmpty && corrected != asTyped,
            takenBy: corrected.isEmpty ? nil : holder?.id,
            mixesScripts: mixesScripts)
    }
}
