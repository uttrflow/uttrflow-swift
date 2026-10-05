import Foundation
import UttrflowCore

/// The messages the dictation's window read sends, one per answer, so a fake can stall between any two.
protocol FocusedWindowSource {
    associatedtype Field
    func windowTitle() -> String?
    func focusedField() -> Field?
    func names(of field: Field) -> FieldNames
    func selection(of field: Field) -> AccessibilitySelection
    func text(of field: Field, names: FieldNames, at range: CFRange?) -> FieldText
    func selectedText(of field: Field, at range: CFRange?) -> String?
    func isMultiline(_ field: Field) -> Bool?
    func markedRange(of field: Field) -> CFRange?
    func identity(of field: Field) -> FieldIdentity?
}

extension FocusedWindowSource {
    func markedRange(of field: Field) -> CFRange? { nil }
    func identity(of field: Field) -> FieldIdentity? { nil }
}

extension MacContextEngine {
    /// Banks each answer as it lands; no text is banked before the secure check finishes. See `Docs/context-accessibility.md`.
    static func read<Source: FocusedWindowSource>(
        _ source: Source, isTerminal: Bool, into sink: FocusedWindowSink, while isWanted: () -> Bool
    ) {
        // Read separately, so an app that names its window but hides its selection still gives the half.
        let title = source.windowTitle()
        sink.bank(FocusedWindow(title: title))
        guard isWanted(), let field = source.focusedField() else { return }
        let identity = source.identity(of: field)
        sink.bank(FocusedWindow(title: title, field: identity))
        // The same names, selection and bounded value the suggestion read asks, so the secure order is decided once.
        let names = source.names(of: field)
        guard !names.isDeclaredSecure else {
            return sink.bank(FocusedWindow(title: title, isSecure: true, field: identity))
        }
        guard isWanted() else { return }
        let resolvedSelection = source.selection(of: field)
        if case .discontinuous = resolvedSelection { return }
        let range: CFRange? = if case .range(let range) = resolvedSelection { range } else { nil }
        let text = source.text(of: field, names: names, at: range)
        guard !text.isSecure else {
            return sink.bank(FocusedWindow(title: title, isSecure: true, field: identity))
        }
        let role = names.role
        sink.bank(
            FocusedWindow(title: title, accessibilityRole: role, fieldLabel: names.label, field: identity))
        let selected = source.selectedText(of: field, at: range)
        sink.bank(
            FocusedWindow(
                title: title, selectedText: selected, accessibilityRole: role, fieldLabel: names.label,
                field: identity))
        guard isWanted() else { return }
        let selection = text.selection.flatMap {
            AccessibilityRange.selection(location: $0.location, length: $0.length)
        }
        let marked = source.markedRange(of: field).flatMap {
            AccessibilityRange.selection(location: $0.location, length: $0.length)
        }
        let caret =
            isTerminal
            ? CaretText.inTerminal(text.value, selection: selection, windowTitle: title)
            : CaretText.around(
                text.value, selection: selection,
                marked: CaretText.shift(
                    marked, from: range.map { $0.location }, to: text.selection.map { $0.location }))
        let multiline =
            source.isMultiline(field)
            ?? role.flatMap { role in
                switch role {
                case "AXTextArea": true
                case "AXTextField", "AXSearchField": false
                default: nil
                }
            }
        sink.bank(
            FocusedWindow(
                title: title, selectedText: selected,
                precedingText: caret?.preceding, followingText: caret?.following,
                accessibilityRole: role, isMultiline: multiline, fieldLabel: names.label,
                isComposing: marked?.isEmpty == false, field: identity))
    }
}
