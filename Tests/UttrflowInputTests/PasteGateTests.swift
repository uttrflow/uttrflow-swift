import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A question is asked about one field, and agreeing answers for that field only.
@MainActor
@Suite("The gate between a paste and its question")
struct PasteGateTests {
    private static let mail = InsertionDestination(
        applicationName: "Mail", bundleIdentifier: "com.example.mail", processIdentifier: 41)
    private static let field = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 100)
    private static let otherField = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 200)
    private static let visible = ScriptedFocus(secure: false, identity: field, application: mail)
    private static let secure = ScriptedFocus(secure: true, identity: field, application: mail)
    private static let elsewhere = ScriptedFocus(secure: false, identity: otherField, application: mail)

    private static func situation(
        concealed: Bool, into app: String = "com.example.mail", text: String = "hello", agreed: Bool = false
    ) -> PasteQuestion.Situation {
        .init(
            isConcealed: concealed, field: .secure, bundleIdentifier: app, text: text,
            confirmsHiddenClips: true, confirmsMultiline: true, isAgreed: agreed)
    }

    @Test("a hidden clip into a visible field asks")
    func asks() async {
        let decision = await PasteGate().decide(Self.situation(concealed: true), focus: Self.visible)

        #expect(decision == .ask(.hiddenIntoVisibleField))
    }

    @Test("a hidden clip into a secure field pastes at once")
    func secureField() async {
        let decision = await PasteGate().decide(Self.situation(concealed: true), focus: Self.secure)

        #expect(decision == .pasteNow)
    }

    @Test("a clip that is not hidden is never read for its field")
    func visibleClip() async {
        let decision = await PasteGate().decide(Self.situation(concealed: false), focus: Self.visible)

        #expect(decision == .pasteNow)
    }

    @Test("agreeing pastes while the focus is on the field that was asked about")
    func agreeing() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(concealed: true), focus: Self.visible)

        let decision = await gate.decide(Self.situation(concealed: true, agreed: true), focus: Self.visible)

        #expect(decision == .pasteNow)
    }

    @Test("agreeing after the cursor moved refuses")
    func moved() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(concealed: true), focus: Self.visible)

        let decision = await gate.decide(Self.situation(concealed: true, agreed: true), focus: Self.elsewhere)

        #expect(decision == .refuse(.fieldMoved))
    }

    @Test("an answer is spent once given, and cannot be reused")
    func spent() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(concealed: true), focus: Self.visible)
        _ = await gate.decide(Self.situation(concealed: true, agreed: true), focus: Self.visible)

        let again = await gate.decide(Self.situation(concealed: true, agreed: true), focus: Self.visible)

        #expect(again == .refuse(.fieldMoved))
    }

    @Test("a closed panel forgets the question")
    func forgotten() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(concealed: true), focus: Self.visible)
        gate.forget()

        let decision = await gate.decide(Self.situation(concealed: true, agreed: true), focus: Self.visible)

        #expect(decision == .refuse(.fieldMoved))
    }

    @Test("a terminal question remembers its field too")
    func terminal() async {
        let gate = PasteGate()
        let ask = Self.situation(concealed: false, into: "com.apple.Terminal", text: "ls\npwd")
        var agreed = ask
        agreed.isAgreed = true

        #expect(await gate.decide(ask, focus: Self.visible) == .ask(.multilineIntoTerminal(lines: 2)))
        #expect(await gate.decide(agreed, focus: Self.elsewhere) == .refuse(.fieldMoved))
    }
}
