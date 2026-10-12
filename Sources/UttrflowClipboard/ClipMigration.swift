import Foundation
import UttrflowCore

/// The synchronous eligibility and upgrade policy for clipboard index migrations.
enum ClipMigration {
    static func canRewriteIndexes(_ reader: ClipboardIndexReader) -> Bool {
        reader.unsupportedFormatVersions.isEmpty && reader.unknownFieldIndexes.isEmpty
            && !reader.hasUnreadableIndex
    }

    static func canReclassify(
        _ url: URL, reader: ClipboardIndexReader, secrecy: inout ClipSecrecyOverrides
    ) -> Bool {
        // A set-aside copy is left for the user to recover; it never makes this file unwritable.
        guard !reader.hasUnreadableIndex, !reader.unreplaceable.contains(url),
            !LocalStore.hasSetAside(url),
            reader.unsupportedFormatVersions.isEmpty, reader.unknownFieldIndexes.isEmpty
        else { return false }
        // Without the user's answers a clip they unmasked would be masked again and leave the disk.
        return secrecy.areKnown()
    }

    static func indexesAreTrustworthy(_ reader: ClipboardIndexReader, history: URL, saved: URL) -> Bool {
        reader.unsupportedFormatVersions.isEmpty && reader.unknownFieldIndexes.isEmpty
            && !reader.hasUnreadableIndex
            && !LocalStore.hasSetAside(history) && !LocalStore.hasSetAside(saved)
    }

    static func migrateLegacy(
        _ url: URL, clips: [Clip], reader: ClipboardIndexReader,
        persist: ([Clip], URL) throws(ClipboardStoreError) -> Void
    ) -> Bool {
        guard reader.legacyIndexes.contains(url), !reader.unreplaceable.contains(url),
            !LocalStore.hasSetAside(url)
        else {
            return false
        }
        do {
            try persist(clips.filter(ClipboardStore.isPersistable), url)
            return true
        } catch {
            // The legacy format remains readable and a later user write can retry the migration.
            return false
        }
    }
}
