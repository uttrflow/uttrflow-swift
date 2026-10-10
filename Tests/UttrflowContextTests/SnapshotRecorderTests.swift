import Foundation
import Testing

@testable import UttrflowContext

struct SnapshotRedactionTests {
    private static let source = """
        Dear Priya, the invoice 4417 for Flat 9 is due.
        Call +91 98450 12345 or write to priya@example.com — thanks! 🙂
        नमस्ते दुनिया 你好世界 Привет 𠀋
        """

    private static func classes(_ text: String) -> [String] {
        text.unicodeScalars.map { scalar in
            if SnapshotRedaction.Synthesiser.isLayout(scalar) { return "layout:\(scalar.value)" }
            if scalar.properties.isEmojiPresentation { return "emoji" }
            return "\(SnapshotRedaction.Group(scalar.properties.generalCategory))"
        }
    }

    @Test func synthesisedTextKeepsLengthLineBreaksAndEveryCharactersClass() {
        let invented = SnapshotRedaction.synthesise(Self.source)
        #expect(invented.utf16.count == Self.source.utf16.count)
        #expect(invented.unicodeScalars.count == Self.source.unicodeScalars.count)
        #expect(Self.classes(invented) == Self.classes(Self.source))
        #expect(invented.split(separator: "\n").count == Self.source.split(separator: "\n").count)
    }

    @Test func synthesisedTextKeepsEachCharactersBlockSoItsScriptHolds() {
        let invented = SnapshotRedaction.synthesise(Self.source)
        for (original, replaced) in zip(Self.source.unicodeScalars, invented.unicodeScalars) {
            #expect(original.value & ~0x7F == replaced.value & ~0x7F)
            #expect(original.utf16.count == replaced.utf16.count)
        }
    }

    @Test func noCharacterOfTheSourceSurvivesWhereItStood() {
        let invented = SnapshotRedaction.synthesise(Self.source)
        for (original, replaced) in zip(Self.source.unicodeScalars, invented.unicodeScalars)
        where !SnapshotRedaction.Synthesiser.isLayout(original) {
            #expect(original != replaced)
        }
        let words = Self.source.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        for word in words where word.count > 1 {
            #expect(!invented.contains(word))
        }
    }

    @Test func synthesisedTextNeverFormsAnAddressHostOrLink() {
        let invented = SnapshotRedaction.synthesise("mail a@b.example.org at https://x.test/path: now")
        #expect(!invented.contains(where: { "@.:/".contains($0) }))
    }

    @Test func aCharacterAloneInItsCategoryTakesAnotherOfItsClass() {
        let invented = SnapshotRedaction.synthesise("-")
        #expect(invented != "-")
        let groups = invented.unicodeScalars.map { SnapshotRedaction.Group($0.properties.generalCategory) }
        #expect(groups == [.punctuation])
    }

    @Test func aCharacterWithNothingOfItsClassNearItTakesAFixedOneOfItsWidth() {
        #expect(SnapshotRedaction.Synthesiser.fallback(for: "a") == "x")
        #expect(SnapshotRedaction.Synthesiser.fallback(for: "x") == "y")
        #expect(SnapshotRedaction.Synthesiser.fallback(for: "\u{20000}").utf16.count == 2)
        #expect(SnapshotRedaction.Synthesiser.fallback(for: "\u{1D400}") == "\u{1D401}")
    }

    @Test func aWindowTitleKeepsOnlyItsExtension() {
        #expect(SnapshotRedaction.title("Quarterly plan for Priya.docx") == "Untitled.docx")
        #expect(SnapshotRedaction.title("main.swift — Sample") == "Untitled.swift")
        #expect(SnapshotRedaction.title("Re: Planning call with Mr. Okafor") == "Untitled")
        #expect(SnapshotRedaction.title("J.Doe") == "Untitled")
        #expect(SnapshotRedaction.title("REPORT.PDF") == "Untitled.PDF")
        #expect(SnapshotRedaction.title("") == "")
        #expect(SnapshotRedaction.title(nil) == nil)
    }

    @Test func aDocumentKeepsOnlyItsSchemeAndExtension() {
        let file = "file:///Users/priya/Documents/Tax%202026.xlsx"
        #expect(SnapshotRedaction.document(file) == "file:///Untitled.xlsx")
        let web = "https://mail.example.com/inbox/42"
        #expect(SnapshotRedaction.document(web) == "https://example.com/Untitled")
        #expect(SnapshotRedaction.document("notes by Priya.txt") == "Untitled.txt")
        #expect(SnapshotRedaction.document(nil) == nil)
    }

    @Test func aRedactedSnapshotKeepsStructureAndNumbersAndInventsTheRest() {
        let value = AccessibilitySnapshot.Answer(kind: .value, text: "Hi Priya", milliseconds: 0.4)
        let field = AccessibilitySnapshot.Element(
            attributes: [
                "AXRole": .init(kind: .value, text: "AXTextArea"), "AXSubrole": .init(kind: .noValue),
                "AXValue": value, "AXNumberOfCharacters": .init(kind: .value, number: 8),
                "AXDocument": .init(kind: .value, text: "file:///Users/priya/a.md"),
            ],
            rangedText: .init(kind: .value, text: "Hi Pr"))
        let window = AccessibilitySnapshot.Element(
            attributes: [
                "AXRole": .init(kind: .value, text: "AXWindow"),
                "AXTitle": .init(kind: .value, text: "Priya notes.md"),
            ],
            children: [field])
        let snapshot = AccessibilitySnapshot(
            schema: 1, family: "native text area", windowTitle: "Priya notes.md",
            document: "file:///Users/priya/a.md", focused: field, window: window)

        let redacted = SnapshotRedaction.redacted(snapshot)
        #expect(redacted.family == "native text area")
        #expect(redacted.windowTitle == "Untitled.md")
        #expect(redacted.document == "file:///Untitled.md")
        #expect(redacted.focused.attributes["AXRole"]?.text == "AXTextArea")
        #expect(redacted.focused.attributes["AXSubrole"] == .init(kind: .noValue))
        #expect(redacted.focused.attributes["AXNumberOfCharacters"]?.number == 8)
        #expect(redacted.focused.attributes["AXDocument"]?.text == "file:///Untitled.md")
        let invented = redacted.focused.attributes["AXValue"]
        #expect(invented?.text?.utf16.count == 8)
        #expect(invented?.text?.contains("Priya") == false)
        #expect(invented?.milliseconds == 0.4)
        #expect(redacted.focused.rangedText?.text?.utf16.count == 5)
        #expect(redacted.window?.attributes["AXTitle"]?.text == "Untitled.md")
        #expect(redacted.window?.children.first?.attributes["AXValue"]?.text?.contains("Priya") == false)
    }
}

struct SnapshotRecorderTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    /// A clock that moves on half a millisecond each time it is read.
    private final class Clock {
        var now: UInt64 = 0
        func read() -> UInt64 {
            now += 500_000
            return now
        }
    }

    private static let field = AccessibilitySnapshot.Element(
        attributes: [
            "AXRole": .init(kind: .value, text: "AXTextArea"), "AXSubrole": .init(kind: .noValue),
            "AXIdentifier": .init(kind: .unsupported),
            "AXNumberOfCharacters": .init(kind: .value, number: 17),
            "AXValue": .init(kind: .value, text: "Lorem ipsum dolor"),
            "AXEnabled": .init(kind: .value, number: 1),
            "AXSelectedTextRange": .init(kind: .cannotComplete), "AXDocument": .init(kind: .timedOut),
        ])

    private static func window(children: [AccessibilitySnapshot.Element]) -> AccessibilitySnapshot.Element {
        AccessibilitySnapshot.Element(
            attributes: [
                "AXRole": .init(kind: .value, text: "AXWindow"),
                "AXTitle": .init(kind: .value, text: "Lorem.txt"),
                "AXDocument": .init(kind: .value, text: "file:///Users/sample/Lorem.txt"),
            ],
            children: children)
    }

    private static let label = AccessibilitySnapshot.Element(
        attributes: [
            "AXRole": .init(kind: .value, text: "AXStaticText"),
            "AXValue": .init(kind: .value, text: "Sit amet"),
        ])

    @Test func aRecordingAsksEveryAttributeTheReaderMayAskAndTimesEach() {
        let window = Self.window(children: [Self.label, Self.field])
        let tree = ReplayTree(
            snapshot: AccessibilitySnapshot(
                schema: 1, family: "x", windowTitle: nil, document: nil, focused: Self.field, window: window))
        let clock = Clock()
        let snapshot = SnapshotRecorder.record(
            family: "native text area", field: Self.field, window: window, in: tree, clock: clock.read)

        #expect(snapshot.schema == AccessibilitySnapshot.currentSchema)
        #expect(snapshot.family == "native text area")
        #expect(snapshot.windowTitle == "Untitled.txt")
        #expect(snapshot.document == "file:///Untitled.txt")
        let focused = snapshot.focused.attributes
        #expect(focused["AXRole"]?.text == "AXTextArea")
        #expect(focused["AXRole"]?.milliseconds == 0.5)
        #expect(focused["AXNumberOfCharacters"]?.number == 17)
        #expect(focused["AXEnabled"]?.number == 1)
        #expect(focused["AXSelectedTextRange"]?.kind == .cannotComplete)
        #expect(focused["AXDocument"]?.kind == .timedOut)
        #expect(focused["AXExpanded"]?.kind == .unsupported)
        #expect(focused["AXValue"]?.text?.utf16.count == 17)
        #expect(focused["AXValue"]?.text?.contains("Lorem") == false)
        #expect(snapshot.focused.rangedText?.kind == .value)
        #expect(snapshot.focused.rangedText?.text?.utf16.count == 17)
        #expect(Set(focused.keys) == Set(SnapshotRecorder.fieldAttributes))
        #expect(tree.messages.asked.filter { $0 == "AXStringForRange" }.count == 1)
    }

    @Test func theWindowSubtreeHoldsTheFieldAsItsOwnRecording() {
        let window = Self.window(children: [Self.label, Self.field])
        let tree = ReplayTree(
            snapshot: AccessibilitySnapshot(
                schema: 1, family: "x", windowTitle: nil, document: nil, focused: Self.field, window: window))
        let snapshot = SnapshotRecorder.record(
            family: "x", field: Self.field, window: window, in: tree, clock: Clock().read)

        let children = snapshot.window?.children ?? []
        #expect(children.count == 2)
        #expect(children.last == snapshot.focused)
        #expect(children.first?.attributes["AXRole"]?.text == "AXStaticText")
        #expect(children.first?.attributes["AXValue"]?.text?.contains("Sit") == false)
        #expect(snapshot.window?.attributes["AXTitle"]?.text == "Untitled.txt")
    }

    @Test func theWindowSubtreeStopsAtItsBounds() {
        let deep = (0..<5).reduce(Self.field) { inner, _ in
            AccessibilitySnapshot.Element(
                attributes: ["AXRole": .init(kind: .value, text: "AXGroup")], children: [inner])
        }
        let window = Self.window(children: [Self.label, Self.label, deep])
        let tree = ReplayTree(
            snapshot: AccessibilitySnapshot(
                schema: 1, family: "x", windowTitle: nil, document: nil, focused: Self.field, window: window))

        let shallow = SnapshotRecorder.record(
            family: "x", field: Self.field, window: window, in: tree,
            bounds: .init(depth: 2, elements: 100), clock: Clock().read)
        #expect(shallow.window?.children.last?.children.first?.children.isEmpty == true)

        let few = SnapshotRecorder.record(
            family: "x", field: Self.field, window: window, in: tree,
            bounds: .init(depth: 8, elements: 2), clock: Clock().read)
        #expect(few.window?.children.count == 1)
    }

    @Test func aFieldWithNoWindowRecordsNoSubtree() {
        let tree = ReplayTree(
            snapshot: AccessibilitySnapshot(
                schema: 1, family: "x", windowTitle: nil, document: nil, focused: Self.field, window: nil))
        let snapshot = SnapshotRecorder.record(
            family: "x", field: Self.field, window: nil, in: tree, clock: Clock().read)
        #expect(snapshot.window == nil)
        #expect(snapshot.windowTitle == nil)
        #expect(snapshot.document == nil)
    }

    @Test func anAnswerTheSchemaCannotHoldIsLeftOut() {
        #expect(SnapshotRecorder.answer(.value(CGPoint.zero), milliseconds: 1) == nil)
        #expect(SnapshotRecorder.answer(.notTrusted, milliseconds: 1) == nil)
        #expect(SnapshotRecorder.answer(.value(NSNumber(value: true)), milliseconds: 1)?.number == 1)
        #expect(SnapshotRecorder.answer(.value("a"), milliseconds: 1)?.text == "a")
        #expect(SnapshotRecorder.answer(.noValue, milliseconds: 1)?.kind == .noValue)
        #expect(SnapshotRecorder.answer(.unsupported, milliseconds: 1)?.kind == .unsupported)
        #expect(SnapshotRecorder.answer(.cannotComplete, milliseconds: 1)?.kind == .cannotComplete)
        #expect(SnapshotRecorder.answer(.timedOut, milliseconds: 2)?.milliseconds == 2)
    }

    @Test func aRecordingOfEveryFixtureDecodesAndCarriesNoneOfItsText() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        for file in files {
            let fixture = try AccessibilitySnapshot.decode(Data(contentsOf: file))
            let tree = ReplayTree(snapshot: fixture)
            let recorded = SnapshotRecorder.record(
                family: fixture.family, field: fixture.focused, window: fixture.window, in: tree,
                clock: Clock().read)
            let data = try JSONEncoder().encode(recorded)
            #expect(try AccessibilitySnapshot.decode(data).family == fixture.family)
            let value = fixture.focused.attributes["AXValue"]?.text ?? ""
            for word in value.split(whereSeparator: { !$0.isLetter }) where word.count > 3 {
                let invented = recorded.focused.attributes["AXValue"]?.text
                #expect(invented?.contains(word) == false, "\(file.lastPathComponent)")
            }
        }
    }
}
