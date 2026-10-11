import CoreGraphics
import Synchronization
import Testing

@testable import UttrflowContext

/// A chat window: page landmarks, a conversation list and the thread containing the compose box.
private let compose = Node(id: 1, role: "AXTextArea", text: "on my w")
private let chatWindow = Node(
    id: 0, role: "AXWindow",
    children: [
        Node(
            id: 10, subrole: "AXLandmarkNavigation",
            children: [
                Node(
                    id: 11, role: "AXList",
                    children: [
                        Node(id: 12, role: "AXLink", text: "Priya: call after lunch"),
                        Node(id: 13, role: "AXLink", text: "Design team: review due"),
                        Node(id: 14, role: "AXLink", text: "Mum: dinner at seven"),
                    ])
            ]),
        Node(
            id: 20,
            children: [
                Node(
                    id: 19, role: "AXList",
                    children: [Node(id: 27, role: "AXLink", text: "Another chat: call at noon")]),
                Node(id: 15, subrole: "AXLandmarkBanner", children: [label(16, "Sponsored")]),
                Node(id: 17, subrole: "AXLandmarkComplementary", children: [label(18, "Related threads")]),
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
    @Test("Only the thread containing the compose box reaches the prompt.")
    func onlyTheFocusedConversationIsRead() {
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: chatWindow), windowTitle: "Priya", deadline: unhurried)
        #expect(read.windowTitle == "Priya")
        let lines = lines(read)
        #expect(lines.last == "Priya: are you coming tonight?")
        #expect(
            lines == [
                "Priya: where did the notarisation log go?", "Me: in dist/, one sec",
                "Priya: found it, thanks!", "Priya: are you coming tonight?",
            ])
        #expect(!lines.contains(where: { $0.contains("Sponsored") || $0.contains("Related") }))
        #expect(
            !lines.contains(where: {
                $0.contains("call after lunch") || $0.contains("review due") || $0.contains("call at noon")
            }))
        #expect(!lines.contains("on my w"))
        #expect(!lines.contains("Send"))
    }

    @Test("The focused field's value never reaches the prompt as a line of text.")
    func focusedFieldValueNeverReachesThePrompt() {
        let reads = TextReadLog()
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: chatWindow, textReads: reads), windowTitle: nil,
            deadline: unhurried)
        #expect(!reads.ids.isEmpty)
        #expect(read.text?.contains(compose.text ?? "") != true)
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
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(read.text == "visible label")
        #expect(read.windowTitle == nil)
    }

    @Test(
        "Rulers, bullets, colour wells, steppers, dividers and gauges are controls too, whatever text they carry.",
        arguments: ["AXColorWell", "AXIncrementor", "AXValueIndicator", "AXSplitter", "AXListMarker"])
    func moreControlsAreSkipped(role: String) {
        let control = Node(id: 5, role: role, text: "12 pt", children: [label(6, "inside the control")])
        let window = Node(id: 0, role: "AXWindow", children: [Node(id: 40, children: [control, compose])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
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
            around: compose, in: FakeTree(root: window), windowTitle: nil, windowFrame: screen,
            deadline: unhurried)
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
                around: compose, in: FakeTree(root: window), windowTitle: nil, windowFrame: frame,
                deadline: unhurried)
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
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil, deadline: unhurried
        )
        #expect(read.text == "second to last\nlast")
        #expect(visits.count == Surroundings.maximumElements)
    }

    @Test("An invalidated queue ticket stops the tree walk before its next element")
    func anInvalidatedWalkStopsBetweenElements() {
        let siblings = (100..<120).map { label($0, "message \($0)") }
        let window = Node(id: 0, role: "AXWindow", children: [Node(id: 40, children: siblings + [compose])])
        let visits = VisitCounter()
        let checks = Mutex(0)
        let isWanted: @Sendable () -> Bool = {
            checks.withLock { count in
                count += 1
                return count < 6
            }
        }

        _ = Surroundings.collect(
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil,
            deadline: unhurried, isWanted: isWanted)

        #expect(visits.count > 0)
        #expect(visits.count < siblings.count)
    }

    @Test(
        "In a long thread the newest messages survive the character cap, cut at their far end, oldest first.")
    func theNewestMessagesSurviveTheCharacterCap() {
        // Each message is 101 characters, so eleven fit whole and the twelfth is cut.
        let messages = (100..<130).map { label($0, String(repeating: "m\($0) ", count: 20) + ".") }
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [Node(id: 20, children: messages), compose])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
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
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(read.text == "Thread\nfirst\nsecond\nFooter\nthird\nfourth")

        // Two full lines leave room for 398 characters, so the 399-character third loses its last one.
        let long1 = String(repeating: "ab", count: 200)
        let long2 = "cd" + String(repeating: "ef", count: 199)
        let third = "xyz" + String(repeating: "gh", count: 198)
        let full = Node(
            id: 0, role: "AXWindow",
            children: [
                Node(id: 40, children: [compose, label(50, long1), label(51, long2), label(52, third)])
            ])
        let cut = Surroundings.collect(
            around: compose, in: FakeTree(root: full), windowTitle: nil, deadline: unhurried)
        #expect(cut.text?.count == Surroundings.maximumCharacters)
        #expect(lines(cut).last == String(third.dropLast()))
    }

    @Test("Once the characters are gathered, no farther ring is walked at all.")
    func aFullReadStopsWalkingOutward() {
        // Four distinct 400-character walls, so the budget runs out on the third and the fourth is unread.
        let lines = (21..<25).map { String(repeating: "w\($0)", count: 133) + "w\($0)" }
        let near = Node(
            id: 20, children: lines.enumerated().map { label(21 + $0.offset, $0.element) })
        let far = Node(id: 10, children: (100..<200).map { label($0, "preview \($0)") })
        let window = Node(id: 0, role: "AXWindow", children: [far, Node(id: 40, children: [near, compose])])
        let visits = VisitCounter()
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil, deadline: unhurried
        )
        #expect(read.text?.contains("preview") == false)
        #expect(read.text?.count == Surroundings.maximumCharacters)
        // The budget runs out partway through the third wall, so only three of the four are visited.
        #expect(visits.count == 4)
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
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(
            read.text
                == "Sticker\nfrom Priya\nMessages in chat with Sam\nSam: hello\nDesign team, design review\nreview notes\nDesign team"
        )
    }

    /// "Sam" is spelled inside "Samantha", and a name is not repeated by a longer name that contains it.
    @Test("A line the label only spells inside a longer word is read, not swallowed.")
    func aLabelSwallowsWholeWordsOnly() {
        #expect(SurroundingsText.repeats("chat with Sam", in: "Messages in chat with Sam"))
        #expect(!SurroundingsText.repeats("Sam", in: "Samantha's messages"))
        #expect(!SurroundingsText.repeats("notes", in: nil))
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
            around: compose, in: FakeTree(root: window, visits: visits), windowTitle: nil, deadline: unhurried
        )
        let lines = lines(read)
        #expect(lines.first == "row 100")
        #expect(lines.count > 0 && lines.count < many.count)
        #expect(visits.count <= Surroundings.maximumElements)
    }

    /// #1300: a very wide sibling array must not cost more pending-step storage than the cap allows, at any width.
    @Test(
        "A very wide sibling array still builds no more pending steps than the element allowance",
        arguments: [500, 5_000, 50_000])
    func widthDoesNotGrowThePendingWork(width: Int) {
        let many = (0..<width).map { label(1_000 + $0, "row \($0)") }
        let window = Node(
            id: 0, role: "AXWindow", children: [Node(id: 40, children: [compose] + many)])
        let tally = SurroundingsStepTally()
        let read = Surroundings.$stepTally.withValue(tally) {
            Surroundings.collect(
                around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        }
        #expect(!(lines(read).isEmpty))
        #expect(
            tally.count <= Surroundings.maximumElements,
            "\(width) siblings built \(tally.count) pending steps")
    }

    @Test("A text element's value is taken once, not again from its children, and blank text is nothing.")
    func textElementsAreLeaves() {
        let field = Node(
            id: 50, role: "AXTextField", text: "  hello  ",
            children: [label(51, "hello"), label(52, "hello")])
        let window = Node(
            id: 0, role: "AXWindow", children: [Node(id: 40, children: [compose, field, label(53, "   ")])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
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
            around: compose, in: FakeTree(root: window), windowTitle: "\u{200E}Chat", deadline: unhurried)
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
            SurroundingsText.trimmed("\u{200E}Photo, 3Septemberat5:00 PM, \u{200E}Received from Priya")
                == "Photo, Received from Priya")
        #expect(SurroundingsText.trimmed("12:46 PM") == nil)
    }

    @Test("Control and direction marks are dropped from what is read, and blank text stays nothing.")
    func marksAreCleaned() {
        #expect(SurroundingsText.cleaned("\u{200E}Whats\u{0E}App\u{200F}") == "WhatsApp")
        #expect(SurroundingsText.trimmed("\u{200E} \u{200F}") == nil)
        #expect(SurroundingsText.trimmed(" \u{200E}hello ") == "hello")
    }

    @Test(
        "A line break or tab between two words still parts them in what is read.",
        arguments: ["\n", "\r\n", "\r", "\t", "\n\n", "\t\u{200E}\n"])
    func separatorsKeepWordsApart(separator: String) {
        let focused = Node(id: 1, role: "AXTextArea", text: "Reply")
        let message = Node(id: 2, role: "AXTextArea", text: "Please review" + separator + "the report")
        let window = Node(id: 0, role: "AXWindow", children: [message, focused])
        let read = Surroundings.collect(
            around: focused, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(read.text?.split(whereSeparator: \.isWhitespace) == ["Please", "review", "the", "report"])
    }

    @Test("A run of line breaks and tabs is one space, and a mark inside a word still joins it.")
    func separatorsBecomeOneSpace() {
        #expect(SurroundingsText.cleaned("one\r\ntwo\tthree") == "one two three")
        #expect(SurroundingsText.cleaned("a\n\u{200F}\t\nb") == "a b")
        #expect(SurroundingsText.cleaned("Whats\u{0E}App\u{0007}") == "WhatsApp")
        #expect(SurroundingsText.trimmed("\n\tHi there\r\n") == "Hi there")
    }

    @Test("Zero-width joiners survive, since they join an emoji or keep two letters apart.")
    func joinersSurvive() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(SurroundingsText.cleaned(family) == family)
        let word = "\u{645}\u{6CC}\u{200C}\u{631}\u{648}\u{645}"
        #expect(SurroundingsText.cleaned(word) == word)
        #expect(SurroundingsText.cleaned("\u{200E}" + word + "\u{200F}") == word)
    }

    @Test("An element with no parent at all has no surroundings.")
    func anOrphanHasNoSurroundings() {
        let read = Surroundings.collect(around: compose, in: FakeTree(root: compose), windowTitle: "t")
        #expect(read == Surroundings(windowTitle: "t", text: nil))
    }

    /// #1947: a subtree the ring walk reaches from two ancestor levels is read once, not twice.
    @Test("A subtree reachable from two ancestor levels is read once, not twice.")
    func aReachableSubtreeIsReadOnce() {
        // The chat list sits both beside the thread and inside it — the shape Chrome's AX tree has when the nav is mirrored under the conversation.
        let chatListBesideThread = label(80, "Chats")
        let chatListInsideThread = label(180, "Chats")
        let thread = Node(
            id: 20,
            text: "Conversation with Riya",
            children: [
                chatListInsideThread,
                Node(
                    id: 21,
                    children: [
                        label(22, "Riya: are we still on for the design review on Friday?")
                    ]),
            ])
        let page = Node(
            id: 10,
            children: [chatListBesideThread, thread])
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [page, compose])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: "Priya", deadline: unhurried)
        let got = lines(read)
        #expect(got.filter { $0 == "Chats" }.count == 1, "the chat list reads once, not twice: \(got)")
    }

    /// A substring of one line that also reads as a whole line elsewhere is kept whole once.
    @Test("A short line that repeats in a long line drops only the repeat, not the long one.")
    func aSubstringDoesNotCollapseIntoItsHost() {
        let chats = label(80, "Chats")
        let longLine = "Chats — see the conversations beside the threads you have open"
        let thread = Node(
            id: 20, text: "Conversation with Riya",
            children: [
                label(180, "Chats"),
                label(181, longLine),
            ])
        let page = Node(
            id: 10,
            children: [chats, thread])
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [page, compose])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        let got = lines(read)
        #expect(got.filter { $0 == "Chats" }.count == 1, "the short label collapses once: \(got)")
        #expect(got.contains(longLine), "the long line is not eaten by the substring match: \(got)")
    }

    @Test(
        "A short message repeated as the newest line stays last, so the tail is still the message being answered."
    )
    func aRepeatedNewestLineStaysLast() {
        let window = Node(
            id: 0, role: "AXWindow",
            children: [
                Node(
                    id: 60, children: [label(61, "ok"), label(62, "Can you send the file?"), label(63, "ok")]),
                compose,
            ])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(lines(read) == ["Can you send the file?", "ok"])
    }

    @Test("Of lines read twice, the copy nearest the field is kept in its place")
    func theNearestCopyIsKept() {
        #expect(SurroundingsText.deduplicated(["a", "b", "a", "c"], dropping: nil) == ["b", "a", "c"])
        #expect(SurroundingsText.deduplicated(["a", "draft", "b"], dropping: "draft") == ["a", "b"])
    }

    /// #1947: the focused field's value must not be carried into its surroundings when a web view mirrors it.
    @Test("The focused field's own value is not carried into its surroundings.")
    func theFocusedFieldIsNotItsOwnSurroundings() {
        // The textarea is also reachable as a sibling of the path — the shape Chrome's AX tree produces when a web view's contents are mirrored.
        let mirror = Node(
            id: 50, role: "AXTextArea", text: "on my w",
            children: [label(51, "on my w")])
        let window = Node(
            id: 0, role: "AXWindow",
            children: [Node(id: 40, children: [compose, mirror])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: nil, deadline: unhurried)
        #expect(read.text?.contains("on my w") != true)
    }

    @Test("In a browser the walk stays inside the page, so other tabs' titles and infobars are never read")
    func aBrowserWalkStaysInsideThePage() {
        let tabStrip = Node(
            id: 70, role: "AXTabGroup",
            children: [label(71, "Quarterly plan – 2 Tabs"), label(72, "Holiday photos")])
        let infobar = Node(id: 73, children: [label(74, "Infobar Container")])
        let page = Node(
            id: 80, role: "AXWebArea", text: "Sign in",
            children: [Node(id: 81, children: [label(82, "Email"), compose])])
        let window = Node(
            id: 0, role: "AXWindow", children: [tabStrip, infobar, Node(id: 90, children: [page])])
        let read = Surroundings.collect(
            around: compose, in: FakeTree(root: window), windowTitle: "Sign in", deadline: unhurried)
        #expect(lines(read) == ["Email"])
    }
}
