import CoreGraphics

@testable import UttrflowContext

/// A window of plain values standing in for another application's elements.
struct Node: Equatable {
    let id: Int
    var role: String? = "AXGroup"
    var text: String? = nil
    var visible = true
    /// Where the node sits on screen, or nothing for one that does not say and is trusted.
    var frame: CGRect? = nil
    var children: [Node] = []
}

/// How many elements one read visited, which only a reference can report back out of a walk.
final class VisitCounter {
    var count = 0
}

/// The tree the collector walks, with parents found by search since a fixture has no back-pointers.
struct FakeTree: ElementTree {
    let root: Node
    var visits: VisitCounter? = nil

    func role(of element: Node) -> String? { element.role }
    func text(of element: Node) -> String? { element.text }
    func children(of element: Node) -> [Node] { element.children }
    /// A hidden node reports no size, which is how a collapsed pane's text looks through Accessibility.
    func frame(of element: Node) -> CGRect? {
        visits?.count += 1
        return element.visible ? element.frame : .zero
    }
    func parent(of element: Node) -> Node? { parent(of: element, under: root) }

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
