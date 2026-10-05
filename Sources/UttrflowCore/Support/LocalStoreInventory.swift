public import Foundation

/// Every file or folder this build keeps under its Application Support folder, as the one home of each name.
public enum LocalStoreEntry: String, CaseIterable, Sendable {
    case clipboard
    case clipboardPreferences
    case clipboardImages
    case savedClips
    case dictationHistory
    case personalDictionary
    case snippets
    case predict
    case predictConsent
    case recordings
    case speechModels
    case encryptionKey
    case instanceLock
    case speechModelLoads
    case networkActivity
    case evidenceLedger

    /// The name on disk, relative to this build's folder.
    public var name: String {
        switch self {
        case .clipboard: "clipboard.v1.json"
        case .clipboardPreferences: "clipboard-preferences.v1.json"
        case .clipboardImages: "Images"
        case .savedClips: "saved.v1.json"
        case .dictationHistory: "history.v1.json"
        case .personalDictionary: "dictionary.v1.json"
        case .snippets: "snippets.v1.json"
        case .predict: "predict.v1.sqlite"
        case .predictConsent: "predict-consent.v1.json"
        case .recordings: "recordings"
        case .speechModels: "Models"
        case .encryptionKey: "local-store-encryption-key.v1"
        case .instanceLock: "instance.lock"
        case .speechModelLoads: "speech-model-loads.v1.json"
        case .networkActivity: "network-activity.v1.json"
        case .evidenceLedger: "evidence.v1.json"
        }
    }

    /// Whether the entry is one folder of many files rather than a single file.
    public var isDirectory: Bool { self == .recordings || self == .speechModels || self == .clipboardImages }

    /// Every name on disk this entry owns, including the files SQLite keeps beside its database.
    public var claimedNames: [String] {
        switch self {
        case .predict: return [name, name + "-wal", name + "-shm", name + "-journal"]
        case .personalDictionary:
            let stem = (name as NSString).deletingPathExtension
            return [name, stem + ".seeded.json", stem + ".refused.json"]
        default: return [name]
        }
    }

    /// Where this entry lives for one build inside `container`.
    public func location(in container: URL, for identifier: String? = Bundle.main.bundleIdentifier) -> URL {
        isDirectory
            ? LocalStore.directory(name, in: container, for: identifier)
            : LocalStore.file(name, in: container, for: identifier)
    }
}

/// What one entry occupies on disk right now.
public struct LocalStoreUsage: Equatable, Sendable {
    public let entry: LocalStoreEntry
    public let files: Int
    public let bytes: Int64
    public let oldest: Date?

    public init(entry: LocalStoreEntry, files: Int, bytes: Int64, oldest: Date?) {
        self.entry = entry
        self.files = files
        self.bytes = bytes
        self.oldest = oldest
    }
}

/// A read-only account of what this build keeps on this Mac, measured from the files themselves.
public enum LocalStoreInventory {
    /// The usage of every entry, in declaration order, with zero for an entry that has no files yet.
    public static func usage(
        in container: URL, for identifier: String? = Bundle.main.bundleIdentifier
    ) -> [LocalStoreUsage] {
        let folder = LocalStore.directory("", in: container, for: identifier)
        return LocalStoreEntry.allCases.map { entry in
            let files = entry.claimedNames.flatMap { regularFiles(at: folder.appending(path: $0)) }
            let values = files.compactMap {
                try? $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            }
            return LocalStoreUsage(
                entry: entry,
                files: values.count,
                bytes: values.reduce(0) { $0 + Int64($1.fileSize ?? 0) },
                oldest: values.compactMap(\.contentModificationDate).min()
            )
        }
    }

    /// Top-level names in this build's folder that no entry claims, so a new store cannot ship unlisted.
    public static func unlisted(
        in container: URL, for identifier: String? = Bundle.main.bundleIdentifier
    ) -> [String] {
        let folder = LocalStore.directory("", in: container, for: identifier)
        let claimed = Set(LocalStoreEntry.allCases.flatMap(\.claimedNames))
        let present =
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return present.filter { !claimed.contains($0) && $0 != ".DS_Store" }.sorted()
    }

    private static func regularFiles(at url: URL) -> [URL] {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        return (walker?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}
