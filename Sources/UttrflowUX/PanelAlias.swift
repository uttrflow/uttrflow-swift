public import Foundation
public import UttrflowClipboard

/// What would happen if this alias were saved.
///
/// Three answers in one, because the field has to show all three at once: what will
/// actually be stored, whether that differs from what was typed, and whether somebody
/// else already has it.
public struct AliasProposal: Sendable, Equatable {
    /// What will be stored — the typed text after correction.
    public let corrected: String
    /// Whether correction changed anything, which is what the quiet note under the field
    /// is for. Not an error: the alias is still accepted.
    public let wasCorrected: Bool
    /// The clip that already answers to this alias, if there is one.
    public let takenBy: Clip.ID?

    /// An empty alias is not a conflict, it is simply nothing to save.
    public var isUsable: Bool { !corrected.isEmpty && takenBy == nil }

    public init(corrected: String, wasCorrected: Bool, takenBy: Clip.ID?) {
        self.corrected = corrected
        self.wasCorrected = wasCorrected
        self.takenBy = takenBy
    }
}

/// The one place that decides what an alias *is*.
///
/// Creation and matching must use the same rule or the feature is a trap: an alias
/// stored one way and looked up another fails to match, and it fails at the moment the
/// user is typing it in a hurry into somebody else's application. The spec calls this out
/// as the thing that "makes the whole feature untrustworthy", so both paths are held to
/// ``handle(_:locale:)`` and there is a test that they agree.
public enum PanelAlias {
    /// An alias reduced to the part that identifies it.
    ///
    /// Three reductions, each for a way the same name gets typed differently:
    ///
    /// - The leading `/` goes, because the convention prints it and nobody in a hurry
    ///   types it.
    /// - Whitespace goes, all of it, anywhere. This is the reduction that was missing:
    ///   an alias saved as "pg prod" could never be found by typing "pgprod", and the
    ///   person who saved it has no way to know which spelling they used months later.
    ///   Removing it from both sides means either spelling finds it.
    /// - Case and accents fold, for the reason the history page gives — what people type
    ///   when looking for a word is rarely how it was spelt when it arrived.
    public static func handle(_ text: String, locale: Locale) -> String {
        String(text.drop { $0 == "/" })
            .filter { !$0.isWhitespace }
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }

    /// What saving `typed` as the alias of `clip` would do.
    ///
    /// The clip being aliased is excluded from the conflict search, so re-saving a clip's
    /// own alias unchanged is not reported as a clash with itself.
    public static func propose(
        _ typed: String, for clip: Clip.ID, among clips: [Clip], locale: Locale
    ) -> AliasProposal {
        let corrected = handle(typed, locale: locale)
        // Compared against the *typed* text with only its slash removed, so that merely
        // dropping the convention's slash is not reported as a correction — that is the
        // spelling the interface itself prints.
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
