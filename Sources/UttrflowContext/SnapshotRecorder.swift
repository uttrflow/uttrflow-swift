import ApplicationServices
import Foundation

/// Records what a focused field and its window answer as an `AccessibilitySnapshot`, its text always invented by `SnapshotRedaction`.
enum SnapshotRecorder {
    /// Every attribute the focused-field read may ask of the field itself.
    static let fieldAttributes =
        FocusedFieldRead.nameAttributes + [
            kAXNumberOfCharactersAttribute, kAXValueAttribute, kAXSelectedTextRangeAttribute,
            kAXSelectedTextRangesAttribute, "AXTextInputMarkedRange", kAXDocumentAttribute,
            kAXEnabledAttribute,
            "AXIsEditable", kAXExpandedAttribute, kAXPositionAttribute, kAXSizeAttribute,
        ]

    /// What the surroundings walk reads of each element around the field.
    static let surroundingAttributes =
        FocusedFieldRead.nameAttributes + [kAXValueAttribute, kAXDocumentAttribute]

    /// How far the window's subtree is walked, so one recording stays a fixture and not a dump.
    struct Bounds: Equatable {
        var depth = 8
        var elements = 160
    }

    /// The longest ranged read recorded, from the field's start.
    static let rangedReadLength = 256

    /// The snapshot of `field` in `window`, with each answer timed by `clock` in nanoseconds and every text redacted.
    static func record<Tree: ElementTree>(
        family: String, field: Tree.Element, window: Tree.Element?, in tree: Tree, bounds: Bounds = Bounds(),
        clock: @escaping () -> UInt64
    ) -> AccessibilitySnapshot {
        let recorder = Walk(tree: tree, clock: clock)
        let focused = recorder.field(field)
        var remaining = bounds.elements
        let subtree = window.map {
            recorder.subtree($0, field: field, recorded: focused, depth: bounds.depth, remaining: &remaining)
        }
        let windowTitle = window.flatMap { tree.attribute(kAXTitleAttribute, of: $0).string }
        let document =
            focused.attributes[kAXDocumentAttribute]?.text
            ?? window.flatMap { tree.attribute(kAXDocumentAttribute, of: $0).string }
        return SnapshotRedaction.redacted(
            AccessibilitySnapshot(
                schema: AccessibilitySnapshot.currentSchema, family: family, windowTitle: windowTitle,
                document: document, focused: focused, window: subtree))
    }

    /// The answer as the schema holds it, or nothing for a value it cannot hold, such as a range or a point.
    static func answer(_ answer: FieldAnswer, milliseconds: Double) -> AccessibilitySnapshot.Answer? {
        switch answer {
        case .value(let value):
            if let text = value as? String {
                return .init(kind: .value, text: text, milliseconds: milliseconds)
            }
            guard let number = value as? NSNumber else { return nil }
            return .init(kind: .value, number: number.intValue, milliseconds: milliseconds)
        case .noValue: return .init(kind: .noValue, milliseconds: milliseconds)
        case .unsupported: return .init(kind: .unsupported, milliseconds: milliseconds)
        case .cannotComplete: return .init(kind: .cannotComplete, milliseconds: milliseconds)
        case .timedOut: return .init(kind: .timedOut, milliseconds: milliseconds)
        case .notTrusted: return nil
        }
    }

    /// One recording's questions, each asked once and timed.
    private struct Walk<Tree: ElementTree> {
        let tree: Tree
        let clock: () -> UInt64

        func field(_ element: Tree.Element) -> AccessibilitySnapshot.Element {
            let attributes = answers(SnapshotRecorder.fieldAttributes, of: element)
            let length = attributes[kAXNumberOfCharactersAttribute]?.number ?? 0
            let range = NSRange(location: 0, length: min(max(length, 0), SnapshotRecorder.rangedReadLength))
            let ranged = timed {
                tree.attribute(kAXStringForRangeParameterizedAttribute, of: element, range: range)
            }
            return AccessibilitySnapshot.Element(attributes: attributes, rangedText: ranged)
        }

        /// The window's elements down to `depth`, the field standing as its own fuller recording wherever it is met.
        func subtree(
            _ element: Tree.Element, field: Tree.Element, recorded: AccessibilitySnapshot.Element, depth: Int,
            remaining: inout Int
        ) -> AccessibilitySnapshot.Element {
            remaining -= 1
            guard element != field else { return recorded }
            var children: [AccessibilitySnapshot.Element] = []
            if depth > 0 {
                for child in tree.children(of: element) where remaining > 0 {
                    children.append(
                        subtree(
                            child, field: field, recorded: recorded, depth: depth - 1,
                            remaining: &remaining))
                }
            }
            return AccessibilitySnapshot.Element(
                attributes: answers(SnapshotRecorder.surroundingAttributes, of: element), children: children)
        }

        private func answers(
            _ names: [String], of element: Tree.Element
        ) -> [String: AccessibilitySnapshot.Answer] {
            var answers: [String: AccessibilitySnapshot.Answer] = [:]
            for name in names {
                answers[name] = timed { tree.attribute(name, of: element) }
            }
            return answers
        }

        private func timed(_ ask: () -> FieldAnswer) -> AccessibilitySnapshot.Answer? {
            let started = clock()
            let answer = ask()
            let elapsed = Double(clock() &- started) / 1_000_000
            return SnapshotRecorder.answer(answer, milliseconds: (elapsed * 100).rounded() / 100)
        }
    }
}
