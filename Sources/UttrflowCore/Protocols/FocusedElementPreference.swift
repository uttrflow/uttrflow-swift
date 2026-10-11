/// Decides which of a system-wide and a per-application reading of the focused element to keep. See `Docs/insertion.md`.
public enum FocusedElementPreference {
    /// The roles a person types into; a static text, a group or a cell under the caret is none of these.
    private static let textEntryRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField",
    ]

    /// Whether a role is one text is entered into.
    public static func isTextEntry(_ role: String?) -> Bool {
        role.map(textEntryRoles.contains) ?? false
    }

    /// Roles an editor publishes its focus under; they take text only while the element reports itself editable.
    private static let editableContainerRoles: Set<String> = ["AXWebArea", "AXGroup", "AXCell"]

    /// Whether a role is one a rich, web or spreadsheet editor publishes, to be confirmed by the element's editable state.
    public static func isEditableContainer(_ role: String?) -> Bool {
        role.map(editableContainerRoles.contains) ?? false
    }

    /// Whether an element belongs to the requested application and not this process.
    public static func belongsToRequestedApplication(
        owner: Int32?, requested: Int32?, current: Int32
    ) -> Bool {
        guard let owner, let requested else { return false }
        return owner == requested && owner != current
    }

    /// The process typed text reaches: the focused element's owner, else the frontmost application. See `Docs/insertion.md`.
    public static func destination<Application>(
        focusOwner: Application?, frontmost: Application?
    ) -> Application? {
        focusOwner ?? frontmost
    }

    /// The system-wide answer if it is a text-entry role, else the application's, else whichever answered. See `Docs/insertion.md`.
    public static func choose<Element>(
        systemWide: Element?, systemWideRole: (Element) -> String?,
        application: () -> Element?, applicationRole: (Element) -> String?
    ) -> Element? {
        if let systemWide, isTextEntry(systemWideRole(systemWide)) { return systemWide }
        let application = application()
        if let application, isTextEntry(applicationRole(application)) { return application }
        return systemWide ?? application
    }
}
