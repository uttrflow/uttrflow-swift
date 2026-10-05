import CoreGraphics
import Foundation

@testable import UttrflowContext

/// A window of plain values standing in for another application's elements.
struct Node: Equatable {
    let id: Int
    var role: String? = "AXGroup"
    var subrole: String? = nil
    var text: String? = nil
    var visible = true
    /// Whether the node declares itself a field that hides what is typed.
    var secure = false
    /// Where the node sits on screen, or nothing for one that does not say and is trusted.
    var frame: CGRect? = nil
    var children: [Node] = []
    /// What the node answers when asked an attribute as a focused field, absent ones unsupported.
    var answers: [String: FieldAnswer] = [:]
}

/// Which attributes a read asked, in order, so a test can count the messages one read sends.
final class MessageLog {
    var asked: [String] = []
    /// The range of every ranged read, so a test can bound how much text one read copies.
    var ranges: [NSRange] = []
}

/// A deadline an hour after the read starts, so only the caps decide what a test's read comes to.
var unhurried: ContinuousClock.Instant { .now + .seconds(3_600) }

/// How many elements one read visited, which only a reference can report back out of a walk.
final class VisitCounter {
    var count = 0
}

/// Which nodes a read asked for their text, which is the one question that can copy a whole document.
final class TextReadLog {
    var ids: [Int] = []
}

/// The tree the collector walks, with parents found by search since a fixture has no back-pointers.
struct FakeTree: ElementTree {
    let root: Node
    var visits: VisitCounter? = nil
    var textReads: TextReadLog? = nil
    var messages: MessageLog? = nil
    /// Whether several attributes go in one message, as Accessibility batches them, or one message each.
    var batches = true

    func role(of element: Node) -> String? { element.role }
    func subrole(of element: Node) -> String? { element.subrole }
    func isConversationLinkList(_ element: Node) -> Bool {
        element.role == "AXList" && element.children.contains { $0.role == "AXLink" }
    }
    func isSecure(_ element: Node) -> Bool { element.secure }
    func text(of element: Node) -> String? {
        textReads?.ids.append(element.id)
        return element.text
    }
    func children(of element: Node) -> [Node] { element.children }
    func isHidden(_ element: Node) -> Bool { !element.visible }
    /// A hidden node reports no size, which is how a collapsed pane's text looks through Accessibility.
    func frame(of element: Node) -> CGRect? {
        visits?.count += 1
        return element.visible ? element.frame : .zero
    }
    func parent(of element: Node) -> Node? { parent(of: element, under: root) }

    func attribute(_ name: String, of element: Node) -> FieldAnswer {
        messages?.asked.append(name)
        return element.answers[name] ?? .unsupported
    }

    /// A batch is logged as one message, its attributes joined, unless the tree is set not to batch.
    func attributes(_ names: [String], of element: Node) -> [FieldAnswer] {
        guard batches else { return names.map { attribute($0, of: element) } }
        messages?.asked.append(names.joined(separator: "+"))
        return names.map { element.answers[$0] ?? .unsupported }
    }

    /// The marker rung answers what the node holds under `AXSelectedTextMarkerRange`, logged as one message.
    func markerSelection(of element: Node) -> MarkerSelection? {
        messages?.asked.append("AXSelectedTextMarkerRange")
        return element.answers["AXSelectedTextMarkerRange"].flatMap {
            guard case .value(let value) = $0 else { return nil }
            return value as? MarkerSelection
        }
    }

    /// A ranged read cuts the node's `AXValue` answer, or refuses as the node says for `AXStringForRange`.
    func attribute(_ name: String, of element: Node, range: NSRange) -> FieldAnswer {
        messages?.asked.append(name)
        messages?.ranges.append(range)
        if let refusal = element.answers[name] { return refusal }
        guard let whole = element.answers["AXValue"]?.string,
            let cut = Range(range, in: whole)
        else { return .unsupported }
        return .value(String(whole[cut]))
    }

    private func parent(of element: Node, under candidate: Node) -> Node? {
        if candidate.children.contains(element) { return candidate }
        for child in candidate.children {
            if let found = parent(of: element, under: child) { return found }
        }
        return nil
    }
}

/// One line of text on screen, which is what most of a window is made of.
func label(_ id: Int, _ text: String, visible: Bool = true, frame: CGRect? = nil) -> Node {
    Node(id: id, role: "AXStaticText", text: text, visible: visible, frame: frame)
}
