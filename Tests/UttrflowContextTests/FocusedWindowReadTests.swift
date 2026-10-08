import Foundation
import Testing
import UttrflowCore

@testable import UttrflowContext

/// A window read the test stops at a chosen message, standing in for the budget expiring there.
private final class StallingSource: FocusedWindowSource {
    enum Step: CaseIterable { case title, field, names, selection, text, selectedText, multiline }

    let stallAfter: Step?
    let names: FieldNames
    let isValueSecure: Bool
    var field: FieldIdentity?
    var stub: HiddenInputLine.Probe = .notStub
    private(set) var stalled = false
    private(set) var visited: [Step] = []

    init(
        stallAfter: Step?, names: FieldNames = FocusedWindowReadTests.plainNames, isValueSecure: Bool = false
    ) {
        self.stallAfter = stallAfter
        self.names = names
        self.isValueSecure = isValueSecure
    }

    private func answered(_ step: Step) {
        visited.append(step)
        if step == stallAfter { stalled = true }
    }

    func windowTitle() -> String? {
        answered(.title)
        return "Notes"
    }
    func focusedField() -> FocusedFieldLookup<Int> {
        answered(.field)
        return .found(1)
    }
    func names(of field: Int) -> FieldNames {
        answered(.names)
        return names
    }
    func selection(of field: Int) -> AccessibilitySelection {
        answered(.selection)
        return .range(CFRange(location: 5, length: 0))
    }
    func text(of field: Int, names: FieldNames, at range: CFRange?) -> FieldText {
        answered(.text)
        return FieldText(
            value: isValueSecure ? nil : "hello world", selection: NSRange(location: 5, length: 0),
            isSecure: isValueSecure, rung: isValueSecure ? .none : .wholeValue)
    }
    func selectedText(of field: Int, at range: CFRange?) -> String? {
        answered(.selectedText)
        return ""
    }
    func isMultiline(_ field: Int) -> Bool? {
        answered(.multiline)
        return true
    }
    func identity(of field: Int) -> FieldIdentity? { self.field }
    func inputStub(
        of field: Int, role: String?, value: String?, while goOn: () -> Bool
    ) -> HiddenInputLine.Probe { stub }
}

@Suite("Focused window read")
struct FocusedWindowReadTests {
    static let plainNames = FieldNames(
        role: "AXTextArea", subrole: nil, identifier: nil, placeholder: nil, description: nil, title: "Body")

    /// What the sink holds at the moment the source stalls, which is what the budget would keep.
    private func banked(_ source: StallingSource) -> FocusedWindow? {
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { !source.stalled })
        return sink.value
    }

    @Test("carries the field's identity through a secure field, a stalled read and a full one")
    func carriesTheFieldIdentity() {
        let identity = FieldIdentity(processIdentifier: 4, windowNumber: 2, element: 9)
        for source in [
            StallingSource(stallAfter: nil), StallingSource(stallAfter: .names),
            StallingSource(stallAfter: nil, isValueSecure: true),
        ] {
            source.field = identity
            #expect(banked(source)?.field == identity)
        }
    }

    @Test("keeps the title when the read stalls right after it, with no caret text")
    func stallAfterTitle() {
        let window = banked(StallingSource(stallAfter: .title))
        #expect(window == FocusedWindow(title: "Notes"))
    }

    @Test("gives nothing but the title when the read stalls inside the secure check")
    func stallInsideSecureCheck() {
        let window = banked(StallingSource(stallAfter: .names))
        #expect(window == FocusedWindow(title: "Notes"))
        #expect(window?.precedingText == nil && window?.accessibilityRole == nil)
    }

    @Test("banks the secure flag and no text for a field secure by its value")
    func secureByValue() {
        let window = banked(StallingSource(stallAfter: nil, isValueSecure: true))
        #expect(window == FocusedWindow(title: "Notes", isSecure: true, unavailable: .secure))
    }

    @Test("banks the secure flag and no text for a field secure by its names")
    func secureByNames() {
        let names = FieldNames(
            role: "AXTextField", subrole: "AXSecureTextField", identifier: nil, placeholder: nil,
            description: nil)
        let window = banked(StallingSource(stallAfter: nil, names: names))
        #expect(window == FocusedWindow(title: "Notes", isSecure: true, unavailable: .secure))
    }

    @Test("refuses unknown names before asking for selection or text")
    func unknownNames() {
        let names = FieldNames(
            role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil,
            refusal: .refused)
        let source = StallingSource(stallAfter: nil, names: names)

        #expect(banked(source) == FocusedWindow(title: "Notes", isSecure: true, unavailable: .refused))
        #expect(!source.visited.contains(.selection))
        #expect(!source.visited.contains(.text))
    }

    @Test("keeps role, label and selection when the read stalls before the caret text")
    func stallAfterSelectedText() {
        let window = banked(StallingSource(stallAfter: .selectedText))
        #expect(
            window
                == FocusedWindow(
                    title: "Notes", selectedText: "", accessibilityRole: "AXTextArea", fieldLabel: "Body"))
    }

    @Test("a read that completes gives the whole window")
    func completes() {
        let window = banked(StallingSource(stallAfter: nil))
        #expect(
            window
                == FocusedWindow(
                    title: "Notes", selectedText: "", precedingText: "hello", followingText: " world",
                    accessibilityRole: "AXTextArea", isMultiline: true, fieldLabel: "Body",
                    readRung: .wholeValue))
    }

    @Test("a secure field once banked is never replaced by a later answer")
    func secureIsSticky() {
        let sink = FocusedWindowSink()
        sink.bank(FocusedWindow(title: "Login", isSecure: true))
        sink.bank(FocusedWindow(title: "Login", precedingText: "hunter2"))
        #expect(sink.value == FocusedWindow(title: "Login", isSecure: true))
    }

    @Test("the banked window names the rung that gave its caret text, and none when no rung did")
    func namesTheRung() {
        #expect(banked(StallingSource(stallAfter: nil))?.readRung == .wholeValue)
        let rendered = StallingSource(stallAfter: nil)
        rendered.stub = .line(
            HiddenInputLine.Reading(before: "select ", after: "", caret: .zero, line: .zero))
        #expect(banked(rendered)?.readRung == .renderedRows)
        let unread = StallingSource(stallAfter: nil)
        unread.stub = .unread
        #expect(banked(unread)?.readRung == ContextReadRung.none)
        #expect(banked(StallingSource(stallAfter: .selectedText))?.readRung == nil)
    }
}
