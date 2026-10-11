import UttrflowCore

/// Confirms the focused element is a writable text control before exposing it to insertion.
enum FocusedTextFieldEligibility {
    /// A readable selection alone does not establish that the element accepts text writes.
    static func accepts(
        role: String?, selectedTextIsReadable: () -> Bool, selectedTextIsSettable: () -> Bool
    ) -> Bool {
        FocusedElementPreference.isTextEntry(role)
            && selectedTextIsReadable()
            && selectedTextIsSettable()
    }
}
