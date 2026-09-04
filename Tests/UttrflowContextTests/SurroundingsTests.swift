import Testing

@testable import UttrflowContext

/// A window of plain values standing in for another application's elements.
private struct Node: Equatable {
    let id: Int
    var role: String = "AXGroup"
    var text: String? = nil
    var visible = true
    var children: [Node] = []
}

/// The tree the collector walks, with parents found by search since a fixture has no back-pointers.
private struct FakeTree: ElementTree {
    let root: Node

    func role(of element: Node) -> String? { element.role }
    func text(of element: Node) -> String? { element.text }
    func children(of element: Node) -> [Node] { element.children }
    func isVisible(_ element: Node) -> Bool { element.visible }
    func parent(of element: Node) -> Node? { parent(of: element, under: root) }

    private func parent(of element: Node, under candidate: Node) -> Node? {
        if candidate.children.contains(element) { return candidate }
        for child in candidate.children {
            if let found = parent(of: element, under: child) { return found }
        }
        return nil
    }
}

private func label(_ id: Int, _ text: String, visible: Bool = true) -> Node {
    Node(id: id, role: "AXStaticText", text: text, visible: visible)
}

/// A chat window: a sidebar of other conversations, a thread, and the compose box the caret is in.
private let compose = Node(id: 1, role: "AXTextArea", text: "on my w")
private let chatWindow = Node(
    id: 0, role: "AXWindow",
    children: [
        Node(id: 10, children: [label(11, "Priya"), label(12, "Design team"), label(13, "Mum")]),
        Node(
            id: 20,
            children: [
                Node(
                    id: 21,
                    children: [
                        label(22, "Priya: where did the notarisation log go?"),
                        label(23, "Me: in dist/, one sec"),
                    ]),
                Node(
                    id: 24,
                    children: [
                        label(25, "Priya: found it, thanks!"), label(26, "Priya: are you coming tonight?"),
                    ]),
                Node(id: 30, children: [compose, Node(id: 31, role: "AXButton", text: "Send")]),
            ]),
    ])

@Suite("What is on screen around the field")
struct SurroundingsTests {
    @Test(
        "The thread beside the compose box comes last, the sidebar first, and the field itself is left out.")
    func nearestTextComesLast() {
        let read = Surroundings.collect(around: compose, in: FakeTree(root: chatWindow), windowTitle: "Priya")
        #expect(read.windowTitle == "Priya")
        let lines = read.text?.split(separator: "\n").map(String.init) ?? []
        #expect(lines.first == "Priya")
        #expect(lines.last == "Priya: are you coming tonight?")
        #expect(!lines.contains("on my w"))
        #expect(!lines.contains("Send"))
        #expect(lines.firstIndex(of: "Mum")! < lines.firstIndex(of: "Priya: found it, thanks!")!)
    }

    @Test("Hidden text, controls and menus are not what the user is looking at, so they are not read.")
    func hiddenAndControlsAreSkipped() {
        let window = Node(
            id: 0, role: "AXWindow",
            children: [
                Node(id: 5, role: "AXMenuBar", children: [label(6, "File")]),
                Node(id: 7, role: "AXToolbar", children: [label(8, "Bold")]),
                label(9, "collapsed pane", visible: false),
                Node(id: 40, children: [compose, label(41, "visible label")]),
            ])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(read.text == "visible label")
        #expect(read.windowTitle == nil)
    }

    @Test(
        "Text is cut from the front to the cap, so the nearest lines survive and a novel beside the field does not."
    )
    func theCapKeepsTheTail() {
        let novel = String(repeating: "far away words ", count: 200)
        let window = Node(
            id: 0, role: "AXWindow",
            children: [
                label(3, novel),
                Node(id: 40, children: [compose, label(41, "the line that matters")]),
            ])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(read.text!.count <= Surroundings.maximumCharacters)
        #expect(read.text!.hasSuffix("the line that matters"))
        // One element gives up at most its own cap, so the far text is present but bounded.
        #expect(
            read.text!.count <= Surroundings.maximumCharactersPerElement + "\nthe line that matters".count)
    }

    @Test("A read whose time is already up settles for the title alone rather than walking anything.")
    func aSpentBudgetReadsNothing() {
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: chatWindow), windowTitle: "Priya",
            deadline: .now - .milliseconds(1))
        #expect(read.windowTitle == "Priya")
        #expect(read.text == nil)
    }

    @Test("A window with thousands of elements is read only as far as the element allowance goes.")
    func theElementAllowanceHolds() {
        let many = (100..<3_000).map { label($0, "row \($0)") }
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [compose] + many)])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        let lines = read.text?.split(separator: "\n").count ?? 0
        #expect(lines > 0 && lines < many.count)
    }

    @Test("A text element's value is taken once, not again from its children, and blank text is nothing.")
    func textElementsAreLeaves() {
        let field = Node(
            id: 50, role: "AXTextField", text: "  hello  ",
            children: [label(51, "hello"), label(52, "hello")])
        let window = Node(
            id: 0, role: "AXWindow", children: [Node(id: 40, children: [compose, field, label(53, "   ")])])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(read.text == "hello")
    }

    @Test("An element with no parent at all has no surroundings.")
    func anOrphanHasNoSurroundings() {
        let read = Surroundings.collect(around: compose, in: FakeTree(root: compose), windowTitle: "t")
        #expect(read == Surroundings(windowTitle: "t", text: nil))
    }
}
