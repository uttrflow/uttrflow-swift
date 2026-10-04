import Foundation

/// The focused field's names and bounded value, decided over any `ElementTree` so every refusal is testable.
enum FocusedFieldRead {
    /// The names the secure check and the field label read, in the order a batched read answers them.
    static let nameAttributes = [
        "AXRole", "AXSubrole", "AXIdentifier", "AXPlaceholderValue", "AXDescription", "AXTitle",
    ]

    /// The field's names, asked in one message where the tree batches them.
    static func names<Tree: ElementTree>(of field: Tree.Element, in tree: Tree) -> FieldNames {
        let named = tree.attributes(nameAttributes, of: field).map(\.string)
        guard named.count == nameAttributes.count else {
            return FieldNames(role: nil, subrole: nil, identifier: nil, placeholder: nil, description: nil)
        }
        return FieldNames(
            role: named[0], subrole: named[1], identifier: named[2], placeholder: named[3],
            description: named[4], title: named[5])
    }

    /// The field's text around the caret with the selection moved into it, never read from a declared secure field.
    static func text<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, names: FieldNames, at selection: NSRange?,
        need: ContextNeed = .turn
    ) -> FieldText {
        guard !names.isDeclaredSecure else {
            return FieldText(value: nil, selection: nil, isSecure: true)
        }
        let count = selection == nil ? nil : tree.attribute("AXNumberOfCharacters", of: field).integer
        let read = ValueWindow.read(
            count: count, selection: selection, need: need,
            whole: { tree.attribute("AXValue", of: field).string },
            part: { tree.attribute("AXStringForRange", of: field, range: $0).string })
        return FieldText(
            value: read.value, selection: read.selection, isSecure: names.isSecure(value: { read.value }))
    }
}

extension FocusedFieldRead {
    /// UTF-16 units of a selection asked for: one character past the kept limit at four units each, so a cut is seen.
    static let selectionReadUnits = (MacContextEngine.selectedTextLimit + 1) * 4

    /// The selection's opening stretch by a ranged read, or `nil` when the field refuses it, never the whole selection.
    static func selectedText<Tree: ElementTree>(
        of field: Tree.Element, in tree: Tree, at selection: NSRange?
    ) -> String? {
        guard let selection, selection.location >= 0, selection.length > 0 else { return nil }
        let window = NSRange(location: selection.location, length: min(selection.length, selectionReadUnits))
        return tree.attribute("AXStringForRange", of: field, range: window).string
    }
}

/// The focused field's text around the caret, with the selection moved into it, and whether the field is secure.
struct FieldText {
    let value: String?
    let selection: NSRange?
    let isSecure: Bool
}
