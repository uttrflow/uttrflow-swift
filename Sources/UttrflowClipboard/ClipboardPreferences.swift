// Per-application clipboard capture choices, kept separately from general UI settings.
public import Foundation
public import UttrflowCore

/// Applications whose clipboard contents should never enter Uttrflow's history.
public struct ClipboardPreferences: Sendable, Equatable, Codable {
    /// The applications the user excluded.
    private var chosenExclusions: Set<String>
    /// The shipped banking and health families the user turned capture back on in.
    private var capturedFamilies: Set<String>
    public var pausedUntil: Date?
    /// Whether a multi-line clip asks before it is pasted into a terminal.
    public var confirmsMultilinePaste: Bool

    /// What is excluded: the user's choices and every shipped banking or health family still off, each matched by family.
    public var excludedBundleIdentifiers: Set<String> {
        chosenExclusions.union(
            SensitiveApplications.families.map(\.prefix).filter { !capturedFamilies.contains($0) })
    }

    public init(
        excludedBundleIdentifiers: Set<String> = [], pausedUntil: Date? = nil,
        confirmsMultilinePaste: Bool = true
    ) {
        self.chosenExclusions = Set(excludedBundleIdentifiers.map { $0.lowercased() })
        self.capturedFamilies = []
        self.pausedUntil = pausedUntil
        self.confirmsMultilinePaste = confirmsMultilinePaste
    }

    private enum CodingKeys: String, CodingKey {
        case chosenExclusions = "excludedBundleIdentifiers"
        case capturedFamilies, pausedUntil, confirmsMultilinePaste
    }

    /// Reads a file with no paste check entry as having the check on, and one from before the shipped families as keeping them off.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            excludedBundleIdentifiers: try values.decode(
                Set<String>.self, forKey: .chosenExclusions),
            pausedUntil: try values.decodeIfPresent(Date.self, forKey: .pausedUntil),
            confirmsMultilinePaste: try values.decodeIfPresent(Bool.self, forKey: .confirmsMultilinePaste)
                ?? true)
        capturedFamilies = try values.decodeIfPresent(Set<String>.self, forKey: .capturedFamilies) ?? []
    }

    /// Whether copies from this application stay out of the history, an exclusion covering its whole family.
    public func excludes(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return Self.excludes(bundleIdentifier, in: excludedBundleIdentifiers)
    }

    /// Whether an identifier is in one of the excluded families, which is how every exclusion is matched.
    static func excludes(_ bundleIdentifier: String, in excluded: Set<String>) -> Bool {
        let identifier = ApplicationKey.of(bundleIdentifier)
        return excluded.contains { ApplicationFamily.member(identifier, of: $0) }
    }

    public mutating func exclude(_ bundleIdentifier: String) {
        let identifier = ApplicationKey.of(bundleIdentifier)
        capturedFamilies.remove(identifier)
        chosenExclusions.insert(identifier)
    }

    public mutating func include(_ bundleIdentifier: String) {
        let identifier = ApplicationKey.of(bundleIdentifier)
        chosenExclusions.remove(identifier)
        if SensitiveApplications.families.contains(where: { $0.prefix == identifier }) {
            capturedFamilies.insert(identifier)
        }
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
