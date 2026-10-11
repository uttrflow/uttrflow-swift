import Testing

@testable import UttrflowCore

/// Every confirm-before-paste question comes from one decision.
@Suite("Deciding whether a paste asks first")
struct PasteQuestionTests {
    private static let terminal = "com.apple.Terminal"

    private static func situation(
        concealed: Bool = false, field: PasteQuestion.Field = .nonSecure,
        into app: String? = "com.example.mail", text: String = "hello", hidden: Bool = true,
        multiline: Bool = true
    ) -> PasteQuestion.Situation {
        .init(
            isConcealed: concealed, field: field, bundleIdentifier: app, text: text,
            confirmsHiddenClips: hidden, confirmsMultiline: multiline)
    }

    @Test("a plain one-line clip pastes at once")
    func plain() {
        #expect(PasteQuestion.decide(Self.situation()) == .pasteNow)
    }

    @Test("a hidden clip into a secure field pastes at once")
    func secure() {
        #expect(PasteQuestion.decide(Self.situation(concealed: true, field: .secure)) == .pasteNow)
    }

    @Test("a hidden clip into a visible field asks")
    func visible() {
        #expect(
            PasteQuestion.decide(Self.situation(concealed: true, field: .nonSecure))
                == .ask(.hiddenIntoVisibleField))
    }

    @Test("a hidden clip into a field that cannot be read asks, worded differently")
    func unreadable() {
        let decision = PasteQuestion.decide(Self.situation(concealed: true, field: .unclassified))
        let visible = PasteQuestion.Reason.hiddenIntoVisibleField
        let unreadable = PasteQuestion.Reason.hiddenIntoUnreadableField

        #expect(decision == .ask(unreadable))
        #expect(unreadable.title != visible.title)
        #expect(unreadable.note != visible.note)
    }

    @Test("a hidden clip pastes at once when its switch is off")
    func hiddenSwitchOff() {
        #expect(PasteQuestion.decide(Self.situation(concealed: true, hidden: false)) == .pasteNow)
        #expect(!Self.situation(concealed: true, hidden: false).needsFieldRead)
        #expect(Self.situation(concealed: true).needsFieldRead)
        #expect(!Self.situation().needsFieldRead)
    }

    @Test("a field is not asked about for a clip that is not hidden")
    func visibleClipIgnoresField() {
        #expect(PasteQuestion.decide(Self.situation(concealed: false, field: .nonSecure)) == .pasteNow)
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

    @Test("a hidden multi-line clip into a terminal asks once, about the hidden clip first")
    func hiddenBeforeTerminal() {
        let decision = PasteQuestion.decide(
            Self.situation(concealed: true, field: .nonSecure, into: Self.terminal, text: "a\nb"))

        #expect(decision == .ask(.hiddenIntoVisibleField))
    }

    @Test("a hidden multi-line clip into a secure terminal field still asks about the lines")
    func secureStillChecksLines() {
        let decision = PasteQuestion.decide(
            Self.situation(concealed: true, field: .secure, into: Self.terminal, text: "a\nb"))

        #expect(decision == .ask(.multilineIntoTerminal(lines: 2)))
    }

    @Test("every reason has a title and a note")
    func wording() {
        let reasons: [PasteQuestion.Reason] = [
            .hiddenIntoVisibleField, .hiddenIntoUnreadableField, .multilineIntoTerminal(lines: 2),
        ]

        #expect(reasons.allSatisfy { !$0.title.isEmpty && !$0.note.isEmpty })
    }

    @Test("an agreed paste goes in while the field is unchanged and is refused once it moved")
    func agreed() {
        var agreed = Self.situation(concealed: true, field: .nonSecure, into: Self.terminal, text: "a\nb")
        agreed.isAgreed = true

        #expect(PasteQuestion.decide(agreed) == .pasteNow)
        #expect(!agreed.needsFieldRead)

        agreed.fieldUnchanged = false

        #expect(PasteQuestion.decide(agreed) == .refuse(.fieldMoved))
        #expect(!PasteQuestion.Refusal.fieldMoved.message.isEmpty)
    }

    @Test("only the terminal question is not about a hidden clip")
    func hiddenReasons() {
        #expect(PasteQuestion.Reason.hiddenIntoVisibleField.isAboutHiddenClip)
        #expect(PasteQuestion.Reason.hiddenIntoUnreadableField.isAboutHiddenClip)
        #expect(!PasteQuestion.Reason.multilineIntoTerminal(lines: 2).isAboutHiddenClip)
    }
}
