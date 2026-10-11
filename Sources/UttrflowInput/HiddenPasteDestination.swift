import UttrflowCore

/// The field a hidden clip would land in, read to decide whether to ask and read again before pasting.
struct HiddenPasteDestination: Sendable, Equatable {
    /// The kind of field that has focus.
    typealias Field = PasteQuestion.Field

    /// What kind of field has focus.
    let field: Field
    /// The application that owns the focused element.
    let application: InsertionDestination?
    /// The focused element itself, so a move to another field of the same app is seen.
    let identity: FieldIdentity?

    /// Reads the focused field off the main thread, answering unclassified when the reader gives up.
    static func read(from focus: any AccessibilityFocus) async -> HiddenPasteDestination {
        let reading = await AccessibilityThread.run(orElse: nil as Reading?) {
            Reading(
                isSecure: focus.focusedFieldIsSecure(), identity: focus.focusedFieldIdentity(),
                application: focus.focusedApplication())
        }
        guard let reading else { return .init(field: .unclassified, application: nil, identity: nil) }
        let field: Field =
            reading.isSecure ? .secure : (reading.identity == nil ? .unclassified : .nonSecure)
        return .init(field: field, application: reading.application, identity: reading.identity)
    }

    /// Whether the focus is still on the field this reading describes, so a confirmation never answers for another field.
    func isUnchanged(on focus: any AccessibilityFocus) async -> Bool {
        let now = await Self.read(from: focus)
        guard now.field == field else { return false }
        switch (application, now.application) {
        case (nil, nil): break
        case (let before?, let after?): guard before.isSameApplication(as: after) else { return false }
        default: return false
        }
        switch (identity, now.identity) {
        case (nil, nil): return true
        case (let before?, let after?): return before.isSameField(as: after)
        default: return false
        }
    }

    private struct Reading: Sendable {
        let isSecure: Bool
        let identity: FieldIdentity?
        let application: InsertionDestination?
    }
}
