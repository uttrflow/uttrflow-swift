import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// The field a paste question is about, so agreeing never answers for another.
@Suite("The field a paste question names")
struct PasteDestinationTests {
    private static let mail = InsertionDestination(
        applicationName: "Mail", bundleIdentifier: "com.example.mail", processIdentifier: 41)
    private static let field = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 100)
    private static let otherField = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 200)

    @Test("the same field is unchanged")
    func unchanged() async {
        let focus = ScriptedFocus(secure: false, identity: Self.field, application: Self.mail)
        let asked = await PasteDestination.read(from: focus)

        #expect(await asked.isUnchanged(on: focus))
    }

    @Test("another field of the same application is a change")
    func otherFieldChanged() async {
        let asked = await PasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))
        let now = ScriptedFocus(secure: false, identity: Self.otherField, application: Self.mail)

        #expect(await !asked.isUnchanged(on: now))
    }

    @Test("a focus that was lost is a change")
    func lostFocusChanged() async {
        let asked = await PasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))

        #expect(await !asked.isUnchanged(on: ScriptedFocus(secure: false, identity: nil, application: nil)))
    }

    @Test("another application is a change")
    func otherApplicationChanged() async {
        let notes = InsertionDestination(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", processIdentifier: 52)
        let asked = await PasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))
        let now = ScriptedFocus(
            secure: false,
            identity: FieldIdentity(processIdentifier: 52, windowNumber: 3, element: 100),
            application: notes)

        #expect(await !asked.isUnchanged(on: now))
    }

}

/// A reader that answers fixed focus facts and nothing else.
struct ScriptedFocus: AccessibilityFocus {
    let secure: Bool
    let identity: FieldIdentity?
    let application: InsertionDestination?

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { identity != nil }
    func isSelfFrontmost() -> Bool { false }
    func focusedFieldIsSecure() -> Bool { secure }
    func focusedFieldIdentity() -> FieldIdentity? { identity }
    func focusedApplication() -> InsertionDestination? { application }
}
