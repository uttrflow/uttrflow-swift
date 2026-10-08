// What a new collection name may be: one rule for filing a clip under a new name and for renaming one.
import Foundation
import UttrflowClipboard

/// Why a typed name cannot become a collection; the presenter words each one.
enum PanelCollectionRefusal: Sendable, Equatable {
    /// Another collection already answers to it, spelt as it is held.
    case taken(String)
    /// The panel already holds ``PanelCollectionName/maximumCount`` collections.
    case tooMany
    /// It reads as a kind filter's chip in the same row, spelt as that chip is.
    case filterName(String)
    /// It holds a line break, a tab, or a character that is invisible or controls the text around it.
    case invisibleCharacters
    /// It is longer than ``PanelCollectionName/maximumLength`` characters.
    case tooLong
}

/// The limits on a collection name, decided once; see `Docs/panel.md`.
enum PanelCollectionName {
    /// The longest name, in characters as a person counts them.
    static let maximumLength = 40
    /// The most collections the panel makes; filing into an existing one is never refused.
    static let maximumCount = 50

    /// Whether `name` holds anything that breaks a one-line chip or hides in it.
    static func hasInvisibleCharacters(_ name: String) -> Bool {
        name.contains(where: \.isNewline)
            || name.unicodeScalars.contains { $0 == "\t" || ClipTextSafety.isDisplayHazard($0) }
    }
}

extension PanelSnapshot {
    /// Why trimmed `name` cannot be a new collection, or `nil`; `replacing` names the one a rename retires.
    func collectionRefusal(_ name: String, replacing renamed: String? = nil) -> PanelCollectionRefusal? {
        if let taken = existingCategory(named: name, besides: renamed) { return .taken(taken) }
        // A rename keeps the count unchanged, so only a new collection can pass the limit.
        if renamed == nil, categories.count >= PanelCollectionName.maximumCount { return .tooMany }
        if let filter = PanelFilter.allCases.first(where: {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return .filterName(filter.title)
        }
        if PanelCollectionName.hasInvisibleCharacters(name) { return .invisibleCharacters }
        if name.count > PanelCollectionName.maximumLength { return .tooLong }
        return nil
    }
}
