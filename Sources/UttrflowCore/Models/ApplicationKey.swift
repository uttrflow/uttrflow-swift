// The one spelling an application is filed under, wherever this app keeps something per application.

/// The key an application's settings, consent and overrides are all filed under.
public enum ApplicationKey {
    /// This application's key: lowercased, because macOS is not consistent about a bundle identifier's case.
    public static func of(_ bundleIdentifier: String) -> String { bundleIdentifier.lowercased() }

    /// Whether two identifiers name the same application, which is the only way to ask.
    public static func same(_ one: String, as other: String) -> Bool { of(one) == of(other) }
}
