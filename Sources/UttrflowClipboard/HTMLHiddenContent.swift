import Foundation
import UttrflowCore

/// Drops what the page hides from its reader, since the page and not the browser chooses what the HTML flavour holds.
enum HiddenContent {
    /// The tokens a reader would see: every hidden element is removed with everything inside it.
    static func removed(from tokens: [HTMLToken]) -> [HTMLToken] {
        var kept: [HTMLToken] = []
        kept.reserveCapacity(tokens.count)
        var hiddenName: String?
        var depth = 0
        for token in tokens {
            if let name = hiddenName {
                guard case .tag(let tag) = token, tag.name == name else { continue }
                depth += tag.isClosing ? -1 : 1
                if depth == 0 { hiddenName = nil }
                continue
            }
            if case .tag(let tag) = token, !tag.isClosing, isHidden(tag) {
                if !HTMLElements.void.contains(tag.name) {
                    hiddenName = tag.name
                    depth = 1
                }
                continue
            }
            kept.append(token)
        }
        return kept
    }

    /// Whether a start tag hides its element: `hidden`, `aria-hidden="true"`, or an inline style that hides it.
    static func isHidden(_ tag: HTMLTag) -> Bool {
        if tag.attribute("hidden") != nil { return true }
        if tag.attribute("aria-hidden")?.trimmingCharacters(in: .whitespaces).lowercased() == "true" {
            return true
        }
        return tag.styleDeclarations.contains { declaration in
            (declaration.property == "display" && declaration.value == "none")
                || (declaration.property == "visibility" && declaration.value == "hidden")
        }
    }
}
