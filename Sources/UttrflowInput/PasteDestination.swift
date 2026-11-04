import UttrflowCore

/// The field a paste question is about, read at the question and again at the paste.
struct PasteDestination: Sendable, Equatable {
    /// The application that owns the focused element.
    let application: InsertionDestination?
    /// The focused element itself, so a move to another field of the same app is seen.
    let identity: FieldIdentity?
    /// Whether the field hides what is typed, so a switch is seen when neither field has a readable identity.
    let isSecure: Bool

    /// Reads the focused field off the main thread, answering nothing when the reader gives up.
    static func read(from focus: any AccessibilityFocus) async -> PasteDestination {
        let reading = await AccessibilityThread.run(orElse: nil as Reading?) {
            Reading(
                isSecure: focus.focusedFieldIsSecure(), identity: focus.focusedFieldIdentity(),
                application: focus.focusedApplication())
        }
        return .init(
            application: reading?.application, identity: reading?.identity,
            isSecure: reading?.isSecure ?? false)
    }

    /// Whether the focus is still on the field this reading describes, so a confirmation never answers for another field.
    func isUnchanged(on focus: any AccessibilityFocus) async -> Bool {
        let now = await Self.read(from: focus)
        guard now.isSecure == isSecure else { return false }
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
