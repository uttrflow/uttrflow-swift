import Testing

@testable import UttrflowCore

/// Every confirm-before-paste question comes from one decision.
@Suite("Deciding whether a paste asks first")
struct PasteQuestionTests {
    private static let terminal = "com.apple.Terminal"

    private static func situation(
        into app: String? = "com.example.mail", text: String = "hello", multiline: Bool = true
    ) -> PasteQuestion.Situation {
        .init(bundleIdentifier: app, text: text, confirmsMultiline: multiline)
    }

    @Test("a plain one-line clip pastes at once")
    func plain() {
        #expect(PasteQuestion.decide(Self.situation()) == .pasteNow)
    }

    @Test("asks about a clip with several lines in a terminal, naming the count")
    func multiLine() {
        let decision = PasteQuestion.decide(Self.situation(into: Self.terminal, text: "ls\npwd\nwhoami"))

        #expect(decision == .ask(.multilineIntoTerminal(lines: 3)))
        #expect(
            PasteQuestion.Reason.multilineIntoTerminal(lines: 3).title
                == "This clip has 3 lines. Paste anyway?")
    }

    @Test("asks about a single line that ends in a newline")
    func trailingNewline() {
        let decision = PasteQuestion.decide(Self.situation(into: Self.terminal, text: "rm -rf build\n"))

        #expect(decision == .ask(.multilineIntoTerminal(lines: 1)))
        #expect(
            PasteQuestion.Reason.multilineIntoTerminal(lines: 1).title
                == "This clip ends with a new line. Paste anyway?")
        #expect(PasteQuestion.lineCount(of: "a\r\nb\r\n") == 2)
    }

    @Test("lets a single line through a terminal")
    func singleLine() {
        #expect(PasteQuestion.decide(Self.situation(into: Self.terminal, text: "ls -la")) == .pasteNow)
    }

    @Test("lets any clip through in an app that is not a terminal")
    func notATerminal() {
        #expect(
            PasteQuestion.decide(Self.situation(into: "com.apple.TextEdit", text: "a\nb\n")) == .pasteNow)
        #expect(PasteQuestion.decide(Self.situation(into: nil, text: "a\nb\n")) == .pasteNow)
    }

    @Test("lets a multi-line clip through when the terminal switch is off")
    func multilineSwitchOff() {
        #expect(
            PasteQuestion.decide(Self.situation(into: Self.terminal, text: "a\nb", multiline: false))
                == .pasteNow)
    }

    @Test("the reason has a title and a note")
    func wording() {
        let reason = PasteQuestion.Reason.multilineIntoTerminal(lines: 2)

        #expect(!reason.title.isEmpty && !reason.note.isEmpty)
    }

    @Test("an agreed paste goes in while the field is unchanged and is refused once it moved")
    func agreed() {
        var agreed = Self.situation(into: Self.terminal, text: "a\nb")
        agreed.isAgreed = true

        #expect(PasteQuestion.decide(agreed) == .pasteNow)

        agreed.fieldUnchanged = false

        #expect(PasteQuestion.decide(agreed) == .refuse(.fieldMoved))
        #expect(!PasteQuestion.Refusal.fieldMoved.message.isEmpty)
    }
}
