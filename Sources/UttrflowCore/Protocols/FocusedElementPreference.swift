/// Decides which of a system-wide and a per-application reading of the focused element to keep. See `Docs/insertion.md`.
public enum FocusedElementPreference {
    /// The roles a person types into; a static text, a group or a cell under the caret is none of these.
    private static let textEntryRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXWebArea",
    ]

    /// Whether a role is one text is entered into.
    public static func isTextEntry(_ role: String?) -> Bool {
        role.map(textEntryRoles.contains) ?? false
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
