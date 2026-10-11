// Reads clipboard indexes while retaining their recovery state.
import Foundation
import UttrflowCore

/// Holds the recovery state discovered while reading clipboard indexes.
struct ClipboardIndexReader {
    /// Detector versions travel with each sealed index and survive launches.
    var classifierVersions: [URL: Int] = [:]
    /// Whether a file this process read was there and could not be read, so its pictures are unknown.
    var hasUnreadableIndex = false
    /// Files that could not be read or moved aside, which no write may replace.
    var unreplaceable: Set<URL> = []
    /// Copies of damaged indexes waiting for the app to tell the user where they were saved.
    var unreadableIndexSetAsides: [URL] = []
    /// Records discovered since the last user notice.
    var unreadableRecordCount = 0
    /// Records for which the whole original index could not be preserved.
    var unpreservedRecordCount = 0
    /// Payload schemas written by newer builds, which this build must leave untouched.
    var unsupportedFormatVersions: [URL: Int] = [:]
    var reportedUnsupportedIndexVersions: Set<Int> = []
    /// Indexes with fields this build cannot preserve if it rewrites the decoded clips.
    var unknownFieldIndexes: Set<URL> = []
    /// Released bare-array payloads that can be safely upgraded after both files are inspected.
    var legacyIndexes: Set<URL> = []

    private let encryptedStore: EncryptedStore?

    init(encryptedStore: EncryptedStore?) {
        self.encryptedStore = encryptedStore
    }

    mutating func takeUnreadableIndexSetAsides() -> [URL] {
        defer { unreadableIndexSetAsides = [] }
        return unreadableIndexSetAsides
    }

    mutating func takeUnreadableRecordCount() -> Int {
        let count = unreadableRecordCount
        unreadableRecordCount = 0
        return count
    }

    mutating func takeUnpreservedRecordCount() -> Int {
        let count = unpreservedRecordCount
        unpreservedRecordCount = 0
        return count
    }

    mutating func takeUnsupportedFormatVersions() -> [Int] {
        let pending = Set(unsupportedFormatVersions.values).subtracting(reportedUnsupportedIndexVersions)
        reportedUnsupportedIndexVersions.formUnion(pending)
        return pending.sorted()
    }

    mutating func read(_ url: URL) -> [Clip] {
        guard !unreplaceable.contains(url) else { return [] }
        let stored: StoredList<ClipboardIndex>
        if let encryptedStore {
            stored = encryptedStore.read(
                ClipboardIndex.self, from: url, recoveringPreviousGeneration: true)
        } else {
            stored = LocalStore.read(ClipboardIndex.self, from: url)
        }
        if case .unsupportedVersion(let version) = stored {
            unsupportedFormatVersions[url] = Int(version)
            return []
        }
        if case .unreadable(let setAside) = stored {
            hasUnreadableIndex = true
            if let setAside {
                unreadableIndexSetAsides.append(setAside)
            } else {
                unreplaceable.insert(url)
            }
        }
        if case .recovered = stored {
            unreadableRecordCount += stored.droppedRecordCount
            hasUnreadableIndex = true
            unreadableIndexSetAsides.append(contentsOf: stored.quarantineRecords)
            if let copy = stored.preservedOriginal {
                unreadableIndexSetAsides.append(copy)
            }
            if !stored.preservationSucceeded {
                unreplaceable.insert(url)
                unpreservedRecordCount += stored.droppedRecordCount
            }
        }
        guard let index = stored.value else { return [] }
        if index.isUnsupported { unsupportedFormatVersions[url] = index.version }
        if index.hasUnknownJSONKeys { unknownFieldIndexes.insert(url) }
        if index.isLegacy { legacyIndexes.insert(url) }
        classifierVersions[url] = index.classifierVersion
        return index.clips
    }
}
