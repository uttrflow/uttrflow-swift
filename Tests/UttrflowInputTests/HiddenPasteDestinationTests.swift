import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A hidden clip is pasted unasked only into a field known to hide what is typed.
@Suite("Where a hidden clip may be pasted without asking")
struct HiddenPasteDestinationTests {
    private static let mail = InsertionDestination(
        applicationName: "Mail", bundleIdentifier: "com.example.mail", processIdentifier: 41)
    private static let field = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 100)
    private static let otherField = FieldIdentity(processIdentifier: 41, windowNumber: 7, element: 200)

    @Test("a secure field needs no confirmation")
    func secure() async {
        let focus = ScriptedFocus(secure: true, identity: Self.field, application: Self.mail)

        let read = await HiddenPasteDestination.read(from: focus)

        #expect(read.field == .secure)
    }

    @Test("a non-secure field needs confirmation")
    func nonSecure() async {
        let focus = ScriptedFocus(secure: false, identity: Self.field, application: Self.mail)

        let read = await HiddenPasteDestination.read(from: focus)

        #expect(read.field == .nonSecure)
    }

    @Test("a focus that cannot be classified needs confirmation")
    func unclassified() async {
        let focus = ScriptedFocus(secure: false, identity: nil, application: nil)

        let read = await HiddenPasteDestination.read(from: focus)

        #expect(read.field == .unclassified)
    }

    @Test("the same field is unchanged")
    func unchanged() async {
        let focus = ScriptedFocus(secure: false, identity: Self.field, application: Self.mail)
        let asked = await HiddenPasteDestination.read(from: focus)

        #expect(await asked.isUnchanged(on: focus))
    }

    @Test("another field of the same application is a change")
    func otherFieldChanged() async {
        let asked = await HiddenPasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))
        let now = ScriptedFocus(secure: false, identity: Self.otherField, application: Self.mail)

        #expect(await !asked.isUnchanged(on: now))
    }

    @Test("another application is a change")
    func otherApplicationChanged() async {
        let notes = InsertionDestination(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", processIdentifier: 52)
        let asked = await HiddenPasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))
        let now = ScriptedFocus(
            secure: false,
            identity: FieldIdentity(processIdentifier: 52, windowNumber: 3, element: 100),
            application: notes)

        #expect(await !asked.isUnchanged(on: now))
    }

    @Test("a field that turned secure or lost focus is a change")
    func classificationChanged() async {
        let asked = await HiddenPasteDestination.read(
            from: ScriptedFocus(secure: false, identity: Self.field, application: Self.mail))

        let turnedSecure = ScriptedFocus(secure: true, identity: Self.field, application: Self.mail)
        let lost = ScriptedFocus(secure: false, identity: nil, application: nil)

        #expect(await !asked.isUnchanged(on: turnedSecure))
        #expect(await !asked.isUnchanged(on: lost))
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
