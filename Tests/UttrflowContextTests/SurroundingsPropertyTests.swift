import CoreGraphics
import Testing

@testable import UttrflowContext

/// Words a window might show, none of them carrying the `#` that marks a node's own id.
private let vocabulary = [
    "Priya", "where", "did", "the", "log", "go", "found", "it", "thanks", "are", "you", "coming", "tonight",
    "Send", "Today", "message", "kal", "milenge", "🙏", "नमस्ते", "chai", "release", "notes", "e\u{301}clair",
]

/// Control and format marks accessibility labels are padded with, which must never reach the model.
private let marks = [
    "\u{200E}", "\u{200F}", "\u{202A}", "\u{202C}", "\u{FEFF}", "\u{00AD}", "\u{0007}", "\u{000E}",
    "\u{200B}",
    "\t", "\n",
]

/// Every role a random window may hand out, text roles and skipped roles among them.
private let roles: [String?] = [
    "AXGroup", "AXGroup", "AXGroup", "AXStaticText", "AXStaticText", "AXTextArea", "AXTextField", "AXHeading",
    "AXLink", "AXCell", "AXComboBox", "AXButton", "AXMenuBar", "AXToolbar", "AXScrollBar", "AXPopUpButton",
    "AXCheckBox", "AXMenu", "AXList", "AXTable", "AXWindow", "AXColorWell", "AXSplitter", nil,
]

/// The window frame every random window is held against.
private let stage = CGRect(x: 0, y: 0, width: 1_000, height: 800)

/// One window built from a seed, with the facts the oracle needs kept beside the tree.
private struct Window {
    let root: Node
    let focused: Node
    let nodes: [Int: Node]
    let parents: [Int: Int]

    /// A window of about `size` nodes, focused on a random node.
    init(seed: Int, size: Int) {
        var random = Seeded(seed: seed)
        var budget = size
        let built = Window.grow(depth: 0, budget: &budget, nextId: 0, random: &random).node
        var nodes: [Int: Node] = [:]
        var parents: [Int: Int] = [:]
        Window.index(built, parent: nil, into: &nodes, parents: &parents)
        self.init(root: built, focusedId: Int.random(in: 1..<max(nodes.count, 2), using: &random))
    }

    /// One pane holding far more lines than the allowance, with the field among them, so the allowance decides the read.
    static func wide(seed: Int) -> Window {
        var random = Seeded(seed: seed)
        let count = Int.random(in: 500...1_200, using: &random)
        var rows = (2...count).map { id -> Node in
            var row = Node(id: id, role: random.pick(roles), text: text(for: id, random: &random))
            row.visible = random.chance(0.85)
            row.frame = frame(random: &random)
            return row
        }
        rows.insert(Node(id: 1), at: Int.random(in: 0..<rows.count, using: &random))
        return Window(
            root: Node(id: 0, role: "AXWindow", children: [Node(id: count + 1, children: rows)]), focusedId: 1
        )
    }

    private init(root built: Node, focusedId: Int) {
        root = Window.focusing(built, on: focusedId)
        var nodes: [Int: Node] = [:]
        var parents: [Int: Int] = [:]
        Window.index(root, parent: nil, into: &nodes, parents: &parents)
        self.nodes = nodes
        self.parents = parents
        focused = nodes[focusedId] ?? root
    }

    /// One random node and its subtree, ids handed out in creation order so the deepest last leaf has the highest.
    private static func grow(
        depth: Int, budget: inout Int, nextId: Int, random: inout Seeded
    ) -> (node: Node, nextId: Int) {
        var id = nextId
        var node = Node(id: id, role: random.pick(roles), text: text(for: id, random: &random))
        node.visible = random.chance(0.85)
        node.frame = frame(random: &random)
        id += 1
        let fanout = depth >= 7 ? 0 : Int.random(in: 0...4, using: &random)
        for _ in 0..<fanout where budget > 0 {
            budget -= 1
            let child = grow(depth: depth + 1, budget: &budget, nextId: id, random: &random)
            node.children.append(child.node)
            id = child.nextId
        }
        return (node, id)
    }

    /// Where one node sits: mostly nowhere it will say, else on the stage, else scrolled off it.
    private static func frame(random: inout Seeded) -> CGRect? {
        guard random.chance(0.3) else { return nil }
        let size = CGSize(
            width: Int.random(in: 1...300, using: &random), height: Int.random(in: 1...100, using: &random))
        if random.chance(0.7) {
            return CGRect(
                origin: CGPoint(
                    x: Int.random(in: -50...950, using: &random), y: Int.random(in: -50...750, using: &random)
                ),
                size: size)
        }
        return CGRect(origin: CGPoint(x: 20, y: Int.random(in: -3_000 ... -200, using: &random)), size: size)
    }

    /// The text of one node: nothing, something blank, or words ending in the node's own `#id`, marks sprinkled in.
    private static func text(for id: Int, random: inout Seeded) -> String? {
        switch Int.random(in: 0..<10, using: &random) {
        case 0..<3: return nil
        case 3: return random.pick(["", "   ", "\u{200E}", " \u{200F}\t"])
        default:
            let count =
                random.chance(0.1)
                ? Int.random(in: 60...160, using: &random) : Int.random(in: 1...8, using: &random)
            var text = random.pick(["", " ", "  ", "\t"])
            for _ in 0..<count {
                text += random.pick(vocabulary)
                text += random.chance(0.2) ? random.pick(marks) : " "
            }
            return text + "#\(id)" + random.pick(["", " ", "\n", "\u{200E}"])
        }
    }

    /// The same tree with one node made the focused field.
    private static func focusing(_ node: Node, on id: Int) -> Node {
        var copy = node
        if node.id == id {
            copy.role = "AXTextArea"
            copy.text = "focus #\(id)"
            copy.visible = true
        }
        copy.children = node.children.map { focusing($0, on: id) }
        return copy
    }

    private static func index(
        _ node: Node, parent: Int?, into nodes: inout [Int: Node], parents: inout [Int: Int]
    ) {
        nodes[node.id] = node
        if let parent { parents[node.id] = parent }
        for child in node.children { index(child, parent: node.id, into: &nodes, parents: &parents) }
    }

    /// How many steps up from the focused field the ring holding this node begins.
    func ring(of id: Int) -> Int {
        var onPath: [Int: Int] = [:]
        var step = focused.id
        var distance = 0
        while true {
            onPath[step] = distance
            guard let parent = parents[step] else { break }
            step = parent
            distance += 1
        }
        var node = id
        while onPath[node] == nil, let parent = parents[node] { node = parent }
        return onPath[node] ?? Int.max
    }
}

/// Whether a node is on the stage: a hidden one is not, one with no frame is trusted, the rest by their frame.
private func onScreen(_ node: Node) -> Bool {
    guard node.visible else { return false }
    guard let frame = node.frame else { return true }
    return frame.width > 0 && frame.height > 0 && frame.intersects(stage)
}

/// Which way the oracle reads a subtree, matching the collector's nearest-first walk on either side of the field.
private enum Direction { case forward, backward }

/// What the collector should read, recomputed plainly: each ring nearest first until the caps, then reading order.
private struct Oracle {
    let runs: [String]
    /// How many elements the walk pops before it is done, invisible and skipped ones included.
    let popped: Int
    /// Whether the characters, rather than the elements, ended the read.
    let isFull: Bool

    init(_ window: Window) {
        var read = Read()
        var levels: [[String]] = []
        var child = window.focused.id
        while let parent = window.parents[child], !read.isDone {
            let siblings = window.nodes[parent]?.children ?? []
            let at = siblings.firstIndex { $0.id == child } ?? siblings.count
            var before: [String] = []
            for sibling in siblings[..<at].reversed() {
                Oracle.gather(sibling, .backward, under: nil, into: &before, read: &read)
            }
            var after: [String] = []
            for sibling in siblings.dropFirst(at + 1) {
                Oracle.gather(sibling, .forward, under: nil, into: &after, read: &read)
            }
            let ring = before.reversed() + after
            if !ring.isEmpty { levels.append(ring) }
            child = parent
        }
        runs = levels.reversed().flatMap { $0 }
        popped = read.popped
        isFull = read.room <= 0
    }

    var text: String? {
        let joined = runs.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// The ids of every node whose text is read.
    var readIds: Set<Int> { Set(runs.compactMap(trailingId)) }

    /// The caps as the read spends them: elements popped and characters taken, separators included.
    private struct Read {
        var popped = 0
        var gathered = 0
        var room: Int { Surroundings.maximumCharacters - gathered - (gathered > 0 ? 1 : 0) }
        var isDone: Bool { popped >= Surroundings.maximumElements || room <= 0 }

        /// What fits of the text, cut at its far end.
        mutating func take(_ text: String, _ direction: Direction) -> String {
            let room = room
            let piece =
                text.count <= room
                ? text : String(direction == .backward ? text.suffix(room) : text.prefix(room))
            gathered += piece.count + (gathered > 0 ? 1 : 0)
            return piece
        }
    }

    private static func gather(
        _ node: Node, _ direction: Direction, under label: String?, into runs: inout [String],
        read: inout Read
    ) {
        guard !read.isDone else { return }
        read.popped += 1
        guard onScreen(node), !Surroundings.skippedRoles.contains(node.role ?? "") else { return }
        let text = cleaned(node.text)
        // A line its container's label already holds is not read again.
        let said = text.flatMap { label?.contains($0) == true ? nil : $0 }
        if direction == .forward, let said { runs.append(read.take(said, direction)) }
        if !(Surroundings.textRoles.contains(node.role ?? "") && text != nil) {
            let children = direction == .forward ? node.children : node.children.reversed()
            for child in children { gather(child, direction, under: text ?? label, into: &runs, read: &read) }
        }
        // Read backward, a label comes after its lines, which is farther from the field than they are.
        if direction == .backward, let said, !read.isDone { runs.append(read.take(said, direction)) }
    }

    /// The text as a person reads it: no control or format marks, no surrounding whitespace, the tail kept.
    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let scalars = text.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }
        var clean = Substring(String(scalars))
        while clean.first?.isWhitespace == true { clean.removeFirst() }
        while clean.last?.isWhitespace == true { clean.removeLast() }
        return clean.isEmpty ? nil : String(clean.suffix(Surroundings.maximumCharactersPerElement))
    }
}

/// The node id a line ends with, or nothing for a line whose id was cut off.
private func trailingId(_ line: String) -> Int? {
    guard let hash = line.lastIndex(of: "#") else { return nil }
    return Int(line[line.index(after: hash)...])
}

private func lines(of read: Surroundings) -> [String] {
    read.text?.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) ?? []
}

/// A deadline no test reaches, so only the caps decide what a random window comes to.
private let unhurried = ContinuousClock.Instant.now + .seconds(60)

@Suite("What is on screen around the field, over random windows")
struct SurroundingsPropertyTests {
    @Test(
        "A window under the element allowance reads exactly its rings, nearest first to the cap, cleaned, in reading order.",
        arguments: 0..<240)
    func smallWindowsMatchTheOracle(seed: Int) {
        var random = Seeded(seed: seed)
        let window = Window(seed: seed, size: Int.random(in: 2...120, using: &random))
        let oracle = Oracle(window)
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: window.focused, in: FakeTree(root: window.root, visits: visits), windowTitle: "w\(seed)",
            windowFrame: stage, deadline: unhurried)
        #expect(read.text == oracle.text)
        #expect(read.windowTitle == "w\(seed)")
        #expect(visits.count == oracle.popped)
        #expect(oracle.popped < Surroundings.maximumElements)
    }

    @Test(
        "Whatever the window, the read leaves out the field, hidden, scrolled-off and control elements, and holds every cap.",
        arguments: 0..<240)
    func everyWindowHoldsTheInvariants(seed: Int) {
        var random = Seeded(seed: seed)
        let window =
            random.chance(0.3)
            ? Window.wide(seed: seed) : Window(seed: seed, size: Int.random(in: 2...200, using: &random))
        let oracle = Oracle(window)
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: window.focused, in: FakeTree(root: window.root, visits: visits), windowTitle: nil,
            windowFrame: stage, deadline: unhurried)
        let lines = lines(of: read)
        #expect((read.text?.count ?? 0) <= Surroundings.maximumCharacters)
        #expect(visits.count == oracle.popped)
        #expect(visits.count <= Surroundings.maximumElements)
        #expect(read.text?.contains("focus #\(window.focused.id)") != true)
        var rings: [Int] = []
        for line in lines {
            #expect(line.count <= Surroundings.maximumCharactersPerElement)
            let marked = line.unicodeScalars.contains {
                $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
            }
            #expect(!marked)
            guard let id = trailingId(line), let node = window.nodes[id] else { continue }
            #expect(id != window.focused.id)
            #expect(onScreen(node))
            #expect(!Surroundings.skippedRoles.contains(node.role ?? ""))
            #expect(oracle.readIds.contains(id))
            rings.append(window.ring(of: id))
        }
        // Farthest rings come first, so the ring number never rises along the text.
        let farthestFirst = zip(rings, rings.dropFirst()).allSatisfy { $0 >= $1 }
        #expect(farthestFirst)
    }

    @Test(
        "A window with more elements than the allowance is read up to the allowance, or until the characters run out.",
        arguments: 0..<12)
    func theAllowanceBoundsTheWalk(seed: Int) {
        let window = Window.wide(seed: seed)
        let oracle = Oracle(window)
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: window.focused, in: FakeTree(root: window.root, visits: visits), windowTitle: nil,
            windowFrame: stage, deadline: unhurried)
        #expect(window.nodes.count > Surroundings.maximumElements)
        #expect(visits.count == oracle.popped)
        #expect(visits.count == Surroundings.maximumElements || oracle.isFull)
        #expect(lines(of: read).count <= Surroundings.maximumElements)
    }

    @Test(
        "A read whose time is already up walks nothing and reads nothing, whatever the window.",
        arguments: 0..<40)
    func aPastDeadlineReadsNothing(seed: Int) {
        let window = Window(seed: seed, size: 60)
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: window.focused, in: FakeTree(root: window.root, visits: visits), windowTitle: "t",
            deadline: .now - .milliseconds(1))
        #expect(read == Surroundings(windowTitle: "t", text: nil))
        #expect(visits.count == 0)
    }

    @Test(
        "A text element that says its text is a leaf, and one that says nothing is walked for its children.",
        arguments: Array(Surroundings.textRoles))
    func textElementsAreLeavesOnlyWhenTheySpeak(role: String) {
        let compose = Node(id: 1, role: "AXTextArea", text: "typing")
        for own in ["said #2", nil, "  \u{200E} "] {
            let spoken = Node(
                id: 2, role: role, text: own, children: [label(3, "inner #3"), label(4, "deeper #4")])
            let window = Node(id: 0, role: "AXWindow", children: [Node(id: 10, children: [spoken, compose])])
            let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
            if own == "said #2" {
                #expect(read.text == "said #2")
            } else {
                #expect(read.text == "inner #3\ndeeper #4")
            }
        }
    }
}
