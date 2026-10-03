// Per-application clipboard capture choices, kept separately from general UI settings.
public import Foundation
import UttrflowCore

/// Applications whose clipboard contents should never enter Uttrflow's history.
public struct ClipboardPreferences: Sendable, Equatable, Codable {
    public private(set) var excludedBundleIdentifiers: Set<String>
    public var pausedUntil: Date?

    public init(excludedBundleIdentifiers: Set<String> = [], pausedUntil: Date? = nil) {
        self.excludedBundleIdentifiers = Set(excludedBundleIdentifiers.map { $0.lowercased() })
        self.pausedUntil = pausedUntil
    }

    public func excludes(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return excludedBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }

    public mutating func exclude(_ bundleIdentifier: String) {
        excludedBundleIdentifiers.insert(bundleIdentifier.lowercased())
    }

    public mutating func include(_ bundleIdentifier: String) {
        excludedBundleIdentifiers.remove(bundleIdentifier.lowercased())
    }
}

/// Private on-disk storage for clipboard privacy choices.
public struct ClipboardPreferencesFile: Sendable {
    private let path: String

    public init(path: String) { self.path = path }

    public static func defaultFile(in directory: URL) -> URL {
        LocalStoreEntry.clipboardPreferences.location(in: directory)
    }

    public func load() -> StoredList<ClipboardPreferences> {
        LocalStore.read(ClipboardPreferences.self, from: URL(fileURLWithPath: path))
    }

    public func restore(from url: URL) throws -> ClipboardPreferences {
        let preferences = try JSONDecoder().decode(ClipboardPreferences.self, from: Data(contentsOf: url))
        try save(preferences)
        return preferences
    }

    public func save(_ preferences: ClipboardPreferences) throws {
        try PrivateFile.write(JSONEncoder().encode(preferences), to: URL(fileURLWithPath: path))
    }
}
