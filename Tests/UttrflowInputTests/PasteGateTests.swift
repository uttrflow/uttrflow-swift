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
    private static let elsewhere = ScriptedFocus(secure: false, identity: otherField, application: mail)

    private static func situation(
        into app: String = "com.apple.Terminal", text: String = "ls\npwd", agreed: Bool = false
    ) -> PasteQuestion.Situation {
        .init(bundleIdentifier: app, text: text, confirmsMultiline: true, isAgreed: agreed)
    }

    @Test("a one-line clip, hidden or not, pastes at once in any field")
    func oneLine() async {
        let decision = await PasteGate().decide(
            Self.situation(into: "com.example.mail", text: "hello"), focus: Self.visible)

        #expect(decision == .pasteNow)
    }

    @Test("agreeing pastes while the focus is on the field that was asked about")
    func agreeing() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(), focus: Self.visible)

        #expect(await gate.decide(Self.situation(agreed: true), focus: Self.visible) == .pasteNow)
    }

    @Test("an answer is spent once given, and cannot be reused")
    func spent() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(), focus: Self.visible)
        _ = await gate.decide(Self.situation(agreed: true), focus: Self.visible)

        #expect(await gate.decide(Self.situation(agreed: true), focus: Self.visible) == .refuse(.fieldMoved))
    }

    @Test("a closed panel forgets the question")
    func forgotten() async {
        let gate = PasteGate()
        _ = await gate.decide(Self.situation(), focus: Self.visible)
        gate.forget()

        #expect(await gate.decide(Self.situation(agreed: true), focus: Self.visible) == .refuse(.fieldMoved))
    }

    @Test("a terminal question remembers its field too")
    func terminal() async {
        let gate = PasteGate()
        let ask = Self.situation()
        let agreed = Self.situation(agreed: true)

        #expect(await gate.decide(ask, focus: Self.visible) == .ask(.multilineIntoTerminal(lines: 2)))
        #expect(await gate.decide(agreed, focus: Self.elsewhere) == .refuse(.fieldMoved))
    }
}
