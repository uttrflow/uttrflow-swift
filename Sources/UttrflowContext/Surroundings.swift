public import CoreGraphics
public import struct Foundation.NSRange
import Synchronization
import UttrflowPredict

/// One element tree as the collector walks it, so a test can hand it a tree of plain values instead of another app.
public protocol ElementTree {
    associatedtype Element: Equatable

    /// The element's Accessibility role, or nothing when it will not say.
    func role(of element: Element) -> String?
    /// The element's semantic Accessibility subrole, or nothing when it will not say.
    func subrole(of element: Element) -> String?
    /// Whether this element is a list of links to other conversations.
    func isConversationLinkList(_ element: Element) -> Bool
    /// Whether the element hides what is typed into it, judged without reading its text.
    func isSecure(_ element: Element) -> Bool
    /// The text a person reads on the element: its value, or its title where it has no value.
    func text(of element: Element) -> String?
    /// The element's children in the order they are laid out, which is the order they are read in.
    func children(of element: Element) -> [Element]
    /// Whether the element is hidden from the user.
    func isHidden(_ element: Element) -> Bool
    /// The element this one sits in, or nothing at the window.
    func parent(of element: Element) -> Element?
    /// Where the element is on screen, or nothing when it will not say, which is trusted.
    func frame(of element: Element) -> CGRect?
    /// One attribute of the element, its refusal kept apart from an empty answer.
    func attribute(_ name: String, of element: Element) -> FieldAnswer
    /// One attribute asked with a UTF-16 range, which is how part of a field's text is read.
    func attribute(_ name: String, of element: Element, range: NSRange) -> FieldAnswer
    /// Several attributes in one message, one answer each in the order asked.
    func attributes(_ names: [String], of element: Element) -> [FieldAnswer]
}

extension ElementTree {
    /// A tree without subroles has no landmark boundary to apply.
    public func subrole(of element: Element) -> String? { nil }
    /// A tree without link semantics has no conversation list to prune.
    public func isConversationLinkList(_ element: Element) -> Bool { false }
    /// A tree that has no hidden-state signal treats its elements as visible.
    public func isHidden(_ element: Element) -> Bool { false }
    /// A tree walked only for its text answers no field attribute.
    public func attribute(_ name: String, of element: Element) -> FieldAnswer { .unsupported }
    /// A tree walked only for its text reads no range.
    public func attribute(_ name: String, of element: Element, range: NSRange) -> FieldAnswer { .unsupported }
    /// A tree without batching asks each attribute on its own.
    public func attributes(_ names: [String], of element: Element) -> [FieldAnswer] {
        names.map { attribute($0, of: element) }
    }
}

/// What is on screen around the focused field, read for one pass and written nowhere. See `Docs/predict-context.md`.
public struct Surroundings: Sendable, Equatable {
    /// The window's title, which names the recipient, the page or the directory more often than not.
    public let windowTitle: String?
    /// The visible text around the field, nearest the field last, so the tail is what matters most.
    public let text: String?
    /// How many on-screen elements were nothing but a clock time, and so vanished from `text` when it was cleaned for the prompt.
    public let timedTurnLines: Int

    public init(windowTitle: String?, text: String?, timedTurnLines: Int = 0) {
        self.windowTitle = windowTitle
        self.text = text
        self.timedTurnLines = timedTurnLines
    }

    /// How much surrounding text the model is ever shown, which bounds the prompt and the read alike.
    public static let maximumCharacters = 1_200

    /// How much of one element's text is taken, so a second document beside the field cannot crowd out the rest.
    public static let maximumCharactersPerElement = 400

    /// How many elements one read may visit, since an Electron window can hold thousands.
    public static let maximumElements = 400

    /// How many ancestors one read may climb, so a deep or cyclic parent chain cannot spend the budget on the way up.
    public static let maximumAncestors = 400

    /// Counts the pending-step entries a read builds while this is bound, so a test can bound the wrapping work without a clock.
    @TaskLocal package static var stepTally: SurroundingsStepTally?

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

    /// The roles that hold a web page, beyond which a browser's own tab strip, toolbar and infobars sit.
    static let pageRoles: Set<String> = ["AXWebArea"]

    /// The page landmarks whose text is outside the conversation that owns the focused field.
    static let unrelatedLandmarkSubroles: Set<String> = [
        "AXLandmarkNavigation", "AXLandmarkComplementary", "AXLandmarkBanner",
    ]

    /// Collects the text around the focused element, nearest first, within the budget and the caps.
    public static func collect<Tree: ElementTree>(
        around focused: Tree.Element, in tree: Tree, windowTitle: String?, windowFrame: CGRect? = nil,
        deadline: ContinuousClock.Instant = .now + .milliseconds(budgetInMilliseconds)
    ) -> Surroundings {
        // Nothing is gathered around a secure field, so its own value is never read to be left out.
        guard !tree.isSecure(focused) else { return Surroundings(windowTitle: windowTitle, text: nil) }
        var walk = Walk<Tree>(tree: tree, window: windowFrame, budget: WalkBudget(deadline: deadline))
        let levels = walk.rings(around: focused)
        // Farthest first and nearest last, so the tail of the text is what sits closest to the field.
        let raw = levels.reversed().flatMap { $0 }
        // Drops text reached twice, and the focused field's own draft, so neither spends the prompt budget.
        let focusedText = SurroundingsText.trimmed(tree.text(of: focused))
        let joined = SurroundingsText.deduplicated(raw, dropping: focusedText).joined(separator: "\n")
        return Surroundings(
            windowTitle: windowTitle, text: joined.isEmpty ? nil : joined,
            timedTurnLines: walk.clockOnlyElements)
    }

    /// One read's traversal: which elements it reads and in what order, spending its `WalkBudget` as it goes.
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
        var budget: WalkBudget
        /// Elements whose whole text was a clock time, so cleaning them for `text` dropped the line entirely.
        var clockOnlyElements = 0

        init(tree: Tree, window: CGRect?, budget: WalkBudget) {
            self.tree = tree
            self.window = window.flatMap { $0.isEmpty ? nil : $0 }
            self.budget = budget
        }

        /// Each ancestor's other children, one ring per level and nearest first; a page is never left.
        mutating func rings(around focused: Tree.Element) -> [[String]] {
            var levels: [[String]] = []
            var child = focused
            var climbed = 0
            while climbed < maximumAncestors, !budget.isExhausted,
                !pageRoles.contains(tree.role(of: child) ?? ""), let parent = tree.parent(of: child)
            {
                climbed += 1
                let ring = self.ring(of: parent, around: child)
                if !ring.isEmpty { levels.append(ring) }
                child = parent
            }
            return levels
        }

        /// The parent's other children in reading order, both sides read nearest first so the caps cut the farthest.
        private mutating func ring(of parent: Tree.Element, around child: Tree.Element) -> [String] {
            let siblings = tree.children(of: parent)
            let position = siblings.firstIndex(of: child) ?? siblings.count
            var before: [String] = []
            gather(siblings[..<position].reversed(), .backward, into: &before)
            var after: [String] = []
            gather(siblings.suffix(from: min(position + 1, siblings.count)), .forward, into: &after)
            return before.reversed() + after
        }

        /// Every readable text under the roots, nearest root first, stopping the moment the read is exhausted.
        mutating func gather<Roots: BidirectionalCollection>(
            _ roots: Roots, _ direction: Direction, into runs: inout [String]
        ) where Roots.Element == Tree.Element {
            // Only the roots a visit could still reach are worth wrapping, however many more the caller has.
            let reachable = roots.prefix(budget.remainingVisits)
            var stack: [Step] = reachable.reversed().map { .visit($0, under: nil) }
            Surroundings.stepTally?.record(stack.count)
            while !budget.isExhausted, let step = stack.popLast() {
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
            budget.spendVisit()
            guard admits(element), let text = readableText(of: element) else { return }
            // A child that only repeats its container's label, as a sticker row does, adds nothing.
            let said = text.flatMap { SurroundingsText.repeats($0, in: label) ? nil : $0 }
            // A container's label names what it holds, so it reads before its children whichever way they are walked.
            if let said, direction == .forward { runs.append(take(said, direction)) }
            if let said, direction == .backward { stack.append(.say(said)) }
            // A text element that says its text is a leaf, since its children only repeat it; one that says nothing is walked.
            if textRoles.contains(tree.role(of: element) ?? ""), text != nil { return }
            stack.append(contentsOf: children(of: element, under: text ?? label, direction))
        }

        /// Whether the element is on screen and neither a control, an unrelated landmark, a conversation list nor a secure field.
        private func admits(_ element: Tree.Element) -> Bool {
            guard isOnScreen(element) else { return false }
            guard !skippedRoles.contains(tree.role(of: element) ?? "") else { return false }
            guard !unrelatedLandmarkSubroles.contains(tree.subrole(of: element) ?? "") else { return false }
            // A secure field is passed over whole, its text never asked for and its children never walked.
            return !tree.isConversationLinkList(element) && !tree.isSecure(element)
        }

        /// The element's trimmed text wrapped once, nothing inside when it says nothing, or nothing at all when it is masked.
        private mutating func readableText(of element: Tree.Element) -> String?? {
            let raw = tree.text(of: element)
            let text = SurroundingsText.trimmed(raw)
            // Text of mask characters alone is a password field that does not declare itself, so it is passed over too.
            guard !(text.map(SecureField.looksMasked) ?? false) else { return nil }
            // A stamp on its own line, "10:31 AM" beside a name rather than glued to a message, is gone once trimmed.
            if text == nil, SurroundingsText.isClockOnly(raw) { clockOnlyElements += 1 }
            return .some(text)
        }

        /// The steps for the children a visit could still reach, nearest kept, ordered for the stack.
        private func children(
            of element: Tree.Element, under label: String?, _ direction: Direction
        ) -> [Step] {
            let all = tree.children(of: element)
            let budget = budget.remainingVisits
            // Forward keeps the nearest (first) reachable children; backward keeps the nearest (last) ones.
            let reachable = direction == .forward ? all.prefix(budget) : all.suffix(budget)
            let children = reachable.map { Step.visit($0, under: label) }
            Surroundings.stepTally?.record(children.count)
            return direction == .forward ? children.reversed() : children
        }

        /// Whether the element is on screen: one with no frame is trusted, one with no size or outside the window is not.
        private func isOnScreen(_ element: Tree.Element) -> Bool {
            guard let frame = tree.frame(of: element) else { return true }
            guard frame.width > 0, frame.height > 0 else { return false }
            return window.map { frame.intersects($0) } ?? true
        }

        /// As much of the text as still fits, cut on its far side, which is the front when reading backward.
        private mutating func take(_ text: String, _ direction: Direction) -> String {
            budget.take(text, direction == .backward ? .keepEnd : .keepStart)
        }
    }
}

/// How many pending-step entries `Surroundings.collect` built while bound to `Surroundings.stepTally`.
package final class SurroundingsStepTally: Sendable {
    private let built = Mutex(0)

    package init() {}

    /// The entries built so far.
    package var count: Int { built.withLock { $0 } }

    func record(_ entries: Int) { built.withLock { $0 += entries } }
}
