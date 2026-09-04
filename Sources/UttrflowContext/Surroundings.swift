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
    /// Whether the element is on screen at all, since text in a collapsed pane is not what the user is looking at.
    func isVisible(_ element: Element) -> Bool
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
        "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuButton",
    ]

    /// Collects the text around the focused element, nearest first, within the budget and the caps.
    public static func collect<Tree: ElementTree>(
        around focused: Tree.Element, in tree: Tree, windowTitle: String?,
        deadline: ContinuousClock.Instant = .now + .milliseconds(budgetInMilliseconds)
    ) -> Surroundings {
        var walk = Walk<Tree>(tree: tree, deadline: deadline)
        var levels: [[String]] = []
        var child = focused
        // Each ancestor's other children are one ring further out, so the message list beside a compose box comes first.
        while let parent = tree.parent(of: child), !walk.isExhausted {
            var ring: [String] = []
            for sibling in tree.children(of: parent) where sibling != child {
                walk.gather(sibling, into: &ring)
            }
            if !ring.isEmpty { levels.append(ring) }
            child = parent
        }
        // Farthest first and nearest last, so cutting to the cap keeps what sits closest to the field.
        let joined = levels.reversed().flatMap { $0 }.joined(separator: "\n")
        let kept = joined.count > maximumCharacters ? String(joined.suffix(maximumCharacters)) : joined
        return Surroundings(windowTitle: windowTitle, text: kept.isEmpty ? nil : kept)
    }

    /// One read's running state: how many elements it has visited and when it has to stop.
    private struct Walk<Tree: ElementTree> {
        let tree: Tree
        let deadline: ContinuousClock.Instant
        var visited = 0

        /// Whether the read has spent its budget or its element allowance.
        var isExhausted: Bool { visited >= maximumElements || ContinuousClock.now >= deadline }

        /// Every readable text under the element, in reading order, stopping the moment the read is exhausted.
        mutating func gather(_ element: Tree.Element, into runs: inout [String]) {
            var stack = [element]
            while let next = stack.popLast(), !isExhausted {
                visited += 1
                guard tree.isVisible(next) else { continue }
                let role = tree.role(of: next) ?? ""
                guard !skippedRoles.contains(role) else { continue }
                let text = Surroundings.trimmed(tree.text(of: next))
                // A container's label names what it holds, as "Messages in chat with …" does, so it is read before its children.
                if let text { runs.append(text) }
                // A text element that says its text is a leaf, since its children only repeat it; one that says nothing is walked.
                if textRoles.contains(role), text != nil { continue }
                stack.append(contentsOf: tree.children(of: next).reversed())
            }
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
