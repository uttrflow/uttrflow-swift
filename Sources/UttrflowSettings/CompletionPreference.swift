private import Foundation

/// Whether tab-to-complete runs at all, which is off until somebody asks for it. See `Docs/predict.md`.
public struct CompletionPreference: Sendable {
    /// Its own defaults key rather than a field of ``Settings``, until the feature has a screen to be turned on from.
    public static let key = "com.uttrflow.predict.enabled"

    private let read: @Sendable (String) -> Bool

    public init(read: @escaping @Sendable (String) -> Bool) {
        self.read = read
    }

    /// The app's own defaults domain, where a key nobody has written reads as off.
    public static let system = CompletionPreference { UserDefaults.standard.bool(forKey: $0) }

    /// Whether the loop may run.
    public var isEnabled: Bool { read(Self.key) }
}
