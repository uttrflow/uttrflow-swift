public import CoreGraphics

/// One element tree as the collector walks it, so a test can hand it a tree of plain values instead of another app.
public protocol ElementTree {
    associatedtype Element: Equatable

    /// The element's Accessibility role, or nothing when it will not say.
    func role(of element: Element) -> String?
    /// The text a person reads on the element: its value, or its title where it has no value.
    func text(of element: Element) -> String?
    /// The element's children in the order they are laid out, which is the order they are read in.
    func children(of element: Element) -> [Element]
    /// The element this one sits in, or nothing at the window.
    func parent(of element: Element) -> Element?
    /// Where the element is on screen, or nothing when it will not say, which is trusted.
    func frame(of element: Element) -> CGRect?
}

/// What is on screen around the focused field, read for one pass and written nowhere. See `Docs/predict-context.md`.
public struct Surroundings: Sendable, Equatable {
    /// The window's title, which names the recipient, the page or the directory more often than not.
    public let windowTitle: String?
    /// The visible text around the field, nearest the field last, so the tail is what matters most.
    public let text: String?

    public init(windowTitle: String?, text: String?) {
        self.windowTitle = windowTitle
        self.text = text
    }

    /// How much surrounding text the model is ever shown, which bounds the prompt and the read alike.
    public static let maximumCharacters = 1_200

    /// How much of one element's text is taken, so a second document beside the field cannot crowd out the rest.
    public static let maximumCharactersPerElement = 400

    /// How many elements one read may visit, since an Electron window can hold thousands.
    public static let maximumElements = 400

    /// How long one read may take before it settles for what it has.
    public static let budgetInMilliseconds = 60

    /// The roles whose text a person reads: labels, messages, headings, links, and the text of other fields.
    static let textRoles: Set<String> = [
        "AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXLink", "AXCell", "AXComboBox",
    ]

    /// The roles never worth descending into, which are controls and their labels rather than what is being talked about.
    static let skippedRoles: Set<String> = [
        "AXMenuBar", "AXMenu", "AXMenuItem", "AXScrollBar", "AXToolbar", "AXPopUpButton", "AXSlider",
        "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuButton", "AXColorWell", "AXIncrementor",
        "AXValueIndicator", "AXSplitter", "AXListMarker",
    ]

    /// Collects the text around the focused element, nearest first, within the budget and the caps.
    public static func collect<Tree: ElementTree>(
        around focused: Tree.Element, in tree: Tree, windowTitle: String?, windowFrame: CGRect? = nil,
        deadline: ContinuousClock.Instant = .now + .milliseconds(budgetInMilliseconds)
    ) -> Surroundings {
        var walk = Walk<Tree>(tree: tree, window: windowFrame, deadline: deadline)
        var levels: [[String]] = []
        var child = focused
        // Each ancestor's other children are one ring further out, so the message list beside a compose box comes first.
        while let parent = tree.parent(of: child), !walk.isExhausted {
            let siblings = tree.children(of: parent)
            let at = siblings.firstIndex(of: child) ?? siblings.count
            // Both sides are read nearest first, so what the caps cut is the farthest, then put back in reading order.
            var before: [String] = []
            walk.gather(siblings[..<at].reversed(), .backward, into: &before)
            var after: [String] = []
            walk.gather(siblings.suffix(from: min(at + 1, siblings.count)), .forward, into: &after)
            let ring = before.reversed() + after
            if !ring.isEmpty { levels.append(ring) }
            child = parent
        }
        // Farthest first and nearest last, so the tail of the text is what sits closest to the field.
        let joined = levels.reversed().flatMap { $0 }.joined(separator: "\n")
        return Surroundings(windowTitle: windowTitle, text: joined.isEmpty ? nil : joined)
    }

    /// One read's running state: how much it has visited and gathered, and when it has to stop.
    private struct Walk<Tree: ElementTree> {
        /// Which way a subtree is read: forward in reading order, or backward from its last line to its label.
        enum Direction { case forward, backward }

        /// One thing left to do: read an element under the label of the container it sits in, or say a label held back.
        enum Step {
            case visit(Tree.Element, under: String?)
            case say(String)
        }

        let tree: Tree
        let window: CGRect?
        let deadline: ContinuousClock.Instant
        var visited = 0
        var gathered = 0

        init(tree: Tree, window: CGRect?, deadline: ContinuousClock.Instant) {
            self.tree = tree
            self.window = window.flatMap { $0.isEmpty ? nil : $0 }
            self.deadline = deadline
        }

        /// How many characters the read may still take, the separator before them counted.
        var room: Int { maximumCharacters - gathered - (gathered > 0 ? 1 : 0) }

        /// Whether the read has spent its budget, its element allowance or its characters.
        var isExhausted: Bool {
            visited >= maximumElements || room <= 0 || ContinuousClock.now >= deadline
        }

        /// Every readable text under the roots, nearest root first, stopping the moment the read is exhausted.
        mutating func gather<Roots: Sequence>(
            _ roots: Roots, _ direction: Direction, into runs: inout [String]
        ) where Roots.Element == Tree.Element {
            var stack: [Step] = roots.reversed().map { .visit($0, under: nil) }
            while !isExhausted, let step = stack.popLast() {
                switch step {
                case .say(let text): runs.append(take(text, direction))
                case .visit(let element, let label):
                    visit(element, under: label, direction, into: &runs, pending: &stack)
                }
            }
        }

        /// Reads one element, then queues its children, and its label too when it is to be said after them.
        private mutating func visit(
            _ element: Tree.Element, under label: String?, _ direction: Direction, into runs: inout [String],
            pending stack: inout [Step]
        ) {
            visited += 1
            guard isOnScreen(element) else { return }
            let role = tree.role(of: element) ?? ""
            guard !skippedRoles.contains(role) else { return }
            let text = Surroundings.trimmed(tree.text(of: element))
            // A child that only repeats its container's label, as a sticker row does, adds nothing.
            let said = text.flatMap { label?.contains($0) == true ? nil : $0 }
            // A container's label names what it holds, so it reads before its children whichever way they are walked.
            if let said, direction == .forward { runs.append(take(said, direction)) }
            if let said, direction == .backward { stack.append(.say(said)) }
            // A text element that says its text is a leaf, since its children only repeat it; one that says nothing is walked.
            if textRoles.contains(role), text != nil { return }
            let children = tree.children(of: element).map { Step.visit($0, under: text ?? label) }
            stack.append(contentsOf: direction == .forward ? children.reversed() : children)
        }

        /// Whether the element is on screen: one with no frame is trusted, one with no size or outside the window is not.
        private func isOnScreen(_ element: Tree.Element) -> Bool {
            guard let frame = tree.frame(of: element) else { return true }
            guard frame.width > 0, frame.height > 0 else { return false }
            return window.map { frame.intersects($0) } ?? true
        }

        /// As much of the text as still fits, cut on its far side, which is the front when reading backward.
        private mutating func take(_ text: String, _ direction: Direction) -> String {
            let room = room
            let piece =
                text.count <= room
                ? text : String(direction == .backward ? text.suffix(room) : text.prefix(room))
            gathered += piece.count + (gathered > 0 ? 1 : 0)
            return piece
        }
    }

    /// The text without surrounding whitespace, control and direction marks, cut to the per-element cap, or nothing.
    static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        var clean = Substring(cleaned(text))
        while let first = clean.first, first.isWhitespace { clean.removeFirst() }
        while let last = clean.last, last.isWhitespace { clean.removeLast() }
        guard !clean.isEmpty else { return nil }
        return String(clean.suffix(maximumCharactersPerElement))
    }

    /// The text without the control and direction marks accessibility labels are padded with, which a model would only read as noise.
    public static func cleaned(_ text: String) -> String {
        String(
            text.unicodeScalars.filter {
                !($0.properties.generalCategory == .control || $0.properties.generalCategory == .format)
            })
    }
}
