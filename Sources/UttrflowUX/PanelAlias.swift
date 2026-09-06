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

    /// An empty alias is not a conflict, it is simply nothing to save.
    public var isUsable: Bool { !corrected.isEmpty && takenBy == nil }

    /// Builds a proposal.
    public init(corrected: String, wasCorrected: Bool, takenBy: Clip.ID?) {
        self.corrected = corrected
        self.wasCorrected = wasCorrected
        self.takenBy = takenBy
    }
}

/// The one place that decides what an alias is, so creation and matching cannot disagree.
public enum PanelAlias {
    /// An alias reduced to what identifies it: no leading slash, no whitespace, case and accents folded.
    public static func handle(_ text: String, locale: Locale) -> String {
        String(text.drop { $0 == "/" })
            .filter { !$0.isWhitespace }
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }

    /// What saving `typed` as `clip`'s alias would do; the clip itself is not a conflict with itself.
    public static func propose(
        _ typed: String, for clip: Clip.ID, among clips: [Clip], locale: Locale
    ) -> AliasProposal {
        let corrected = handle(typed, locale: locale)
        // Compared against the typed text minus its slash, so dropping the slash is not a correction.
        let asTyped = String(typed.drop { $0 == "/" })
        let holder = clips.first {
            $0.id != clip && $0.alias.map { handle($0, locale: locale) } == corrected
        }
        return AliasProposal(
            corrected: corrected,
            wasCorrected: !corrected.isEmpty && corrected != asTyped,
            takenBy: corrected.isEmpty ? nil : holder?.id)
    }
}
