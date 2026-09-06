import CoreGraphics
import Testing

@testable import UttrflowContext

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

/// The window every framed fixture below sits in.
private let screen = CGRect(x: 100, y: 100, width: 800, height: 600)

private func lines(_ read: Surroundings) -> [String] {
    read.text?.split(separator: "\n").map(String.init) ?? []
}

@Suite("What is on screen around the field")
struct SurroundingsTests {
    @Test(
        "The thread beside the compose box comes last, the sidebar first, and the field itself is left out.")
    func nearestTextComesLast() {
        let read = Surroundings.collect(around: compose, in: FakeTree(root: chatWindow), windowTitle: "Priya")
        #expect(read.windowTitle == "Priya")
        let lines = lines(read)
        #expect(lines.first == "Priya")
        #expect(lines.last == "Priya: are you coming tonight?")
        #expect(!lines.contains("on my w"))
        #expect(!lines.contains("Send"))
        #expect(lines.firstIndex(of: "Mum")! < lines.firstIndex(of: "Priya: found it, thanks!")!)
        #expect(
            lines.firstIndex(of: "Priya: where did the notarisation log go?")!
                < lines.firstIndex(of: "Me: in dist/, one sec")!)
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
        "Rulers, bullets, colour wells, steppers, dividers and gauges are controls too, whatever text they carry.",
        arguments: ["AXColorWell", "AXIncrementor", "AXValueIndicator", "AXSplitter", "AXListMarker"])
    func moreControlsAreSkipped(role: String) {
        let control = Node(id: 5, role: role, text: "12 pt", children: [label(6, "inside the control")])
        let window = Node(id: 0, role: "AXWindow", children: [Node(id: 40, children: [control, compose])])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(read.text == nil)
    }

    @Test("Text scrolled out of the window is not on screen, and nor is anything under it.")
    func offWindowSubtreesArePruned() {
        let above = CGRect(x: 120, y: -900, width: 600, height: 40)
        let straddling = CGRect(x: 120, y: 80, width: 600, height: 40)
        let inside = CGRect(x: 120, y: 300, width: 600, height: 40)
        let window = Node(
            id: 0, role: "AXWindow", frame: screen,
            children: [
                Node(
                    id: 40, frame: CGRect(x: 100, y: 100, width: 800, height: 400),
                    children: [
                        Node(id: 41, frame: above, children: [label(42, "scrolled away", frame: inside)]),
                        label(43, "half shown", frame: straddling),
                        label(44, "in view", frame: inside),
                        label(45, "says no frame"),
                        label(46, "no size", frame: CGRect(x: 120, y: 300, width: 0, height: 40)),
                        compose,
                    ])
            ])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, windowFrame: screen)
        #expect(read.text == "half shown\nin view\nsays no frame")
    }

    @Test(
        "With no window frame to hold it against, only an element's own size decides whether it is on screen."
    )
    func anUnknownWindowFrameTrustsEveryPlacedElement() {
        let far = CGRect(x: 5_000, y: 5_000, width: 10, height: 10)
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [label(41, "far off", frame: far), compose])])
        for frame in [nil, CGRect.zero] {
            let read = Surroundings.collect(
                around: compose, in: FakeTree(root: window), windowTitle: nil, windowFrame: frame)
            #expect(read.text == "far off")
        }
    }

    @Test("In a long thread the newest messages survive the element allowance, in the order they were said.")
    func theNewestMessagesSurviveTheElementAllowance() {
        let thread = Node(id: 20, children: (100..<1_000).map { Node(id: $0, role: "AXStaticText") })
        var newest = thread
        newest.children[895] = label(995, "second to last")
        newest.children[899] = label(999, "last")
        let window = Node(id: 0, role: "AXWindow", children: [Node(id: 40, children: [newest, compose])])
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil)
        #expect(read.text == "second to last\nlast")
        #expect(visits.count == Surroundings.maximumElements)
    }

    @Test(
        "In a long thread the newest messages survive the character cap, cut at their far end, oldest first.")
    func theNewestMessagesSurviveTheCharacterCap() {
        // Each message is 101 characters, so eleven fit whole and the twelfth is cut.
        let messages = (100..<130).map { label($0, String(repeating: "m\($0) ", count: 20) + ".") }
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [Node(id: 20, children: messages), compose])])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        let lines = lines(read)
        #expect(read.text?.count == Surroundings.maximumCharacters)
        #expect(lines.last == messages[29].text)
        #expect(lines.count == 12)
        // The line the cap falls in keeps its end, which is the side nearer the field.
        #expect(lines.first?.hasSuffix("m118 .") == true && lines.first?.count == 78)
        #expect(Array(lines.dropFirst()) == messages.suffix(11).compactMap(\.text))
    }

    @Test(
        "A container's label reads before its lines whichever way it was walked, and a following line is cut at its end."
    )
    func labelsLeadTheirLinesOnBothSides() {
        let before = Node(id: 20, text: "Thread", children: [label(21, "first"), label(22, "second")])
        let after = Node(id: 30, text: "Footer", children: [label(31, "third"), label(32, "fourth")])
        let window = Node(
            id: 0, role: "AXWindow", children: [Node(id: 40, children: [before, compose, after])])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(read.text == "Thread\nfirst\nsecond\nFooter\nthird\nfourth")

        // Two full lines leave room for 398 characters, so the 399-character third loses its last one.
        let long = String(repeating: "ab", count: 200)
        let third = "xyz" + String(repeating: "ab", count: 198)
        let full = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [compose, label(50, long), label(51, long), label(52, third)])])
        let cut = Surroundings.collect(around: compose, in: FakeTree(root: full), windowTitle: nil)
        #expect(cut.text?.count == Surroundings.maximumCharacters)
        #expect(lines(cut).last == String(third.dropLast()))
    }

    @Test("Once the characters are gathered, no farther ring is walked at all.")
    func aFullReadStopsWalkingOutward() {
        let wall = String(repeating: "w", count: Surroundings.maximumCharactersPerElement)
        let near = Node(
            id: 20, children: [label(21, wall), label(22, wall), label(23, wall), label(24, wall)])
        let far = Node(id: 10, children: (100..<200).map { label($0, "preview \($0)") })
        let window = Node(id: 0, role: "AXWindow", children: [far, Node(id: 40, children: [near, compose])])
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil)
        #expect(visits.count == 4)
        #expect(read.text?.contains("preview") == false)
        #expect(read.text?.count == Surroundings.maximumCharacters)
    }

    @Test(
        "A line that only repeats its container's label is read once, under the nearest label that names it.")
    func repeatedLabelsAreReadOnce() {
        let sticker = Node(
            id: 20, text: "Sticker", children: [label(21, "Sticker"), label(22, "from Priya")])
        let nested = Node(
            id: 23, text: "Messages in chat with Sam",
            children: [Node(id: 24, children: [label(25, "chat with Sam"), label(26, "Sam: hello")])])
        // A label is held against the nearest labelled container only, so a farther one does not swallow a line.
        let farther = Node(
            id: 27, text: "Design team, design review",
            children: [Node(id: 28, text: "review notes", children: [label(29, "Design team")])])
        let window = Node(
            id: 0, role: "AXWindow", children: [Node(id: 40, children: [sticker, nested, farther, compose])])
        let read = Surroundings.collect(around: compose, in: FakeTree(root: window), windowTitle: nil)
        #expect(
            read.text
                == "Sticker\nfrom Priya\nMessages in chat with Sam\nSam: hello\nDesign team, design review\nreview notes\nDesign team"
        )
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
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil)
        let lines = lines(read)
        #expect(lines.first == "row 100")
        #expect(lines.count > 0 && lines.count < many.count)
        #expect(visits.count <= Surroundings.maximumElements)
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

    @Test(
        "A chat whose messages carry their text as descriptions under a labelled group is still read, marks and all."
    )
    func labelledGroupsAndDescribedMessagesAreRead() {
        // WhatsApp's shape: empty-valued static texts whose text is the description, dates in nested headings.
        let messages = Node(
            id: 60, text: "\u{200E}Messages in chat with Sam",
            children: [
                Node(id: 61, role: "AXStaticText", text: "\u{200E}message, are you coming tonight?"),
                Node(id: 62, role: "AXHeading", children: [Node(id: 63, role: "AXHeading", text: "Today")]),
                Node(id: 64, role: "AXStaticText", text: "\u{200E}message, phone off hone wala hai"),
            ])
        let window = Node(
            id: 0, role: "AXWindow",
            children: [
                Node(id: 40, children: [messages, compose, Node(id: 41, role: "AXButton", text: "Send")])
            ])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: "\u{200E}Chat")
        #expect(
            read.text
                == "Messages in chat with Sam\nmessage, are you coming tonight?\nToday\nmessage, phone off hone wala hai"
        )
        #expect(read.windowTitle == "\u{200E}Chat")
    }

    @Test(
        "A message's timestamp parts are dropped from what is read, and a label that was only a time is nothing."
    )
    func timestampsAreDropped() {
        #expect(
            Surroundings.trimmed("\u{200E}Photo, 3Septemberat5:00 PM, \u{200E}Received from Priya")
                == "Photo, Received from Priya")
        #expect(Surroundings.trimmed("12:46 PM") == nil)
    }

    @Test("Control and direction marks are dropped from what is read, and blank text stays nothing.")
    func marksAreCleaned() {
        #expect(Surroundings.cleaned("\u{200E}Whats\u{0E}App\u{200F}") == "WhatsApp")
        #expect(Surroundings.trimmed("\u{200E} \u{200F}") == nil)
        #expect(Surroundings.trimmed(" \u{200E}hello ") == "hello")
    }

    @Test("An element with no parent at all has no surroundings.")
    func anOrphanHasNoSurroundings() {
        let read = Surroundings.collect(around: compose, in: FakeTree(root: compose), windowTitle: "t")
        #expect(read == Surroundings(windowTitle: "t", text: nil))
    }
}
