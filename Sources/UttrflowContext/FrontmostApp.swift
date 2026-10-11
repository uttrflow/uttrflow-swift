/// The frontmost application's identity, taken on the main thread where `NSWorkspace` is safe to read.
public struct FrontmostApp: Sendable {
    /// Addresses the app for the Accessibility read.
    public let processIdentifier: Int32
    /// The app's bundle identifier, which every capability table is keyed by.
    public let bundleIdentifier: String
    /// The app as the user knows it, cleaned of the marks some applications pad it with.
    public let name: String

    public init(processIdentifier: Int32, bundleIdentifier: String, name: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}
