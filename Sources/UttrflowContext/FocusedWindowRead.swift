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
    func inputStub(
        of field: Field, role: String?, value: String?, while goOn: () -> Bool
    ) -> HiddenInputLine.Probe
}

extension FocusedWindowSource {
    func markedRange(of field: Field) -> CFRange? { nil }
    func identity(of field: Field) -> FieldIdentity? { nil }
    func inputStub(
        of field: Field, role: String?, value: String?, while goOn: () -> Bool
    ) -> HiddenInputLine.Probe {
        .notStub
    }
}

/// How a tree's raw answers become the elements and ranges the window read needs.
struct FieldAnswerDecoder<Element> {
    let element: (Any) -> Element?
    let range: (Any) -> CFRange?
}

/// The attributes the dictation's window read asks together, each list one message.
enum WindowReadAttributes {
    /// The application's focused window and focused element.
    static let focus = ["AXFocusedWindow", "AXFocusedUIElement"]
    /// The field's selection, length, line mode and marked run, none of them its text.
    static let state = [
        "AXSelectedTextRanges", "AXSelectedTextRange", "AXNumberOfCharacters", "AXMultiline",
        "AXTextInputMarkedRange",
    ]
}

/// The dictation's window read over any `ElementTree`, the focus and the field's state each one message.
final class TreeWindowSource<Tree: ElementTree>: FocusedWindowSource {
    private let tree: Tree
    private let app: Tree.Element
    private let decode: FieldAnswerDecoder<Tree.Element>
    private let cap: (Tree.Element) -> Void
    private let identify: (Tree.Element) -> FieldIdentity?
    private var field: Tree.Element?
    private var state: [FieldAnswer] = []
    private var markerCount: Int?

    /// `cap` sets an element's messaging timeout to the time left before it is asked anything.
    init(
        tree: Tree, app: Tree.Element, decode: FieldAnswerDecoder<Tree.Element>,
        cap: @escaping (Tree.Element) -> Void, identify: @escaping (Tree.Element) -> FieldIdentity?
    ) {
        self.tree = tree
        self.app = app
        self.decode = decode
        self.cap = cap
        self.identify = identify
    }

    func windowTitle() -> String? {
        cap(app)
        let focus = tree.attributes(WindowReadAttributes.focus, of: app)
        field = focus.count == 2 ? value(focus[1]).flatMap(decode.element) : nil
        guard let window = focus.first.flatMap(value).flatMap(decode.element) else { return nil }
        cap(window)
        return tree.attribute("AXTitle", of: window).string
    }

    func focusedField() -> Tree.Element? { field }

    func names(of field: Tree.Element) -> FieldNames {
        cap(field)
        return FocusedFieldRead.names(of: field, in: tree)
    }

    func selection(of field: Tree.Element) -> AccessibilitySelection {
        cap(field)
        let asked = tree.attributes(WindowReadAttributes.state, of: field)
        state = asked.count == WindowReadAttributes.state.count ? asked : []
        markerCount = nil
        let plural = answer(0).flatMap { $0 as? [Any] }
        if let plural, plural.count > 1 { return .discontinuous }
        let resolved = AccessibilitySelection.resolve(
            singular: answer(1).flatMap(decode.range), plural: plural?.compactMap(decode.range),
            textLength: count)
        guard case .unavailable = resolved, let marker = tree.markerSelection(of: field) else {
            return resolved
        }
        // The marker rung counts the field itself, so a field that also refuses its length still gets a window.
        let byMarker = AccessibilitySelection.resolve(
            singular: CFRange(location: marker.range.location, length: marker.range.length), plural: nil,
            textLength: marker.count)
        if case .range = byMarker { markerCount = marker.count }
        return byMarker
    }

    /// The field's length from the state batch, or from the marker rung when that was what answered.
    private var count: Int? { state.isEmpty ? nil : state[2].integer }

    func text(of field: Tree.Element, names: FieldNames, at range: CFRange?) -> FieldText {
        cap(field)
        return FocusedFieldRead.text(
            of: field, in: tree, names: names,
            at: range.map { NSRange(location: $0.location, length: $0.length) },
            count: { self.markerCount ?? self.count })
    }

    func selectedText(of field: Tree.Element, at range: CFRange?) -> String? {
        cap(field)
        return FocusedFieldRead.selectedText(
            of: field, in: tree, at: range.map { NSRange(location: $0.location, length: $0.length) })
    }

    func isMultiline(_ field: Tree.Element) -> Bool? { (answer(3) as? NSNumber)?.boolValue }

    func markedRange(of field: Tree.Element) -> CFRange? { answer(4).flatMap(decode.range) }

    func identity(of field: Tree.Element) -> FieldIdentity? { identify(field) }

    func inputStub(
        of field: Tree.Element, role: String?, value: String?, while goOn: () -> Bool
    ) -> HiddenInputLine.Probe {
        HiddenInputLine.probe(
            field, role: role, value: value,
            frame: {
                cap(field)
                return tree.frame(of: field)
            }, in: tree, while: goOn)
    }

    /// One answer from the state batch, or nothing when the field refused it or the batch was not asked.
    private func answer(_ index: Int) -> Any? { state.indices.contains(index) ? value(state[index]) : nil }

    private func value(_ answer: FieldAnswer) -> Any? {
        guard case .value(let value) = answer else { return nil }
        return value
    }
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
        // An editor that draws its own text leaves an empty input at the caret; its edges are the rendered line.
        let stub: HiddenInputLine.Probe =
            isTerminal
            ? .notStub : source.inputStub(of: field, role: role, value: text.value, while: isWanted)
        let caret: CaretText.Sides? =
            switch stub {
            case .line(let line):
                CaretText.around(
                    line.before + line.after,
                    selection: line.before.utf16.count..<line.before.utf16.count)
            case .unread: nil
            case .notStub:
                isTerminal
                    ? CaretText.inTerminal(text.value, selection: selection, windowTitle: title)
                    : CaretText.around(
                        text.value, selection: selection,
                        marked: CaretText.shift(
                            marked, from: range.map { $0.location },
                            to: text.selection.map { $0.location }))
            }
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
