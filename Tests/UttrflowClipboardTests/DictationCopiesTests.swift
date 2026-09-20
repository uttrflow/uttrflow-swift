// Tests for finding and forgetting the clipboard copy of one dictation.

import Foundation
import Testing

@testable import UttrflowClipboard

/// The copy a dictation leaves on the clipboard, found by the dictation's identifier rather than its words.
@Suite("The clipboard copy of a dictation")
struct DictationCopiesTests {
    private static func copy(_ text: String, of dictation: UUID) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: Date(), source: ClipOrigin.dictationSource,
            origin: .uttrflow, dictations: [dictation])
    }

    @Test("an edited copy is still deleted with its dictation")
    func editedCopyGoes() async throws {
        let folder = try TemporaryFolder()
        let dictation = UUID()
        let clip = Self.copy("print SQL", of: dictation)
        _ = try await folder.store.record(clip, keeping: folder.retention)
        _ = try await folder.store.setText("print SQL now", of: clip.id, keeping: folder.retention)

        _ = try await folder.store.deleteCopies(
            ofDictation: dictation, saying: "print SQL", keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    @Test("a pinned copy is deleted with its dictation, because deleting words is the point")
    func pinnedCopyGoes() async throws {
        let folder = try TemporaryFolder()
        let dictation = UUID()
        let clip = Self.copy("print SQL", of: dictation)
        _ = try await folder.store.record(clip, keeping: folder.retention)
        _ = try await folder.store.setPinned(true, of: clip.id, keeping: folder.retention)

        _ = try await folder.store.deleteCopies(
            ofDictation: dictation, saying: "print s q l", keeping: folder.retention)

        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    @Test("a copy of another dictation, or a ⌘C of the same words, stays")
    func othersStay() async throws {
        let folder = try TemporaryFolder()
        let other = Self.copy("print SQL", of: UUID())
        let copied = Clip(text: "print SQL", kind: .text, copiedAt: Date())
        _ = try await folder.store.record(other, keeping: folder.retention)
        _ = try await folder.store.record(copied, keeping: folder.retention)

        let left = try await folder.store.deleteCopies(
            ofDictation: UUID(), saying: "print SQL", keeping: folder.retention)

        #expect(Set(left.map(\.id)) == [other.id, copied.id])
    }

    @Test("a copy made before the link is matched on its words")
    func unlinkedCopyMatchesItsWords() async throws {
        let folder = try TemporaryFolder()
        let old = Clip(
            text: "print SQL", kind: .text, copiedAt: Date(), source: ClipOrigin.dictationSource,
            origin: .uttrflow)
        let typed = Clip(text: "print SQL", kind: .code, copiedAt: Date(), origin: .uttrflow)
        _ = try await folder.store.record(old, keeping: folder.retention)

        let left = try await folder.store.deleteCopies(
            ofDictation: UUID(), saying: "print SQL", keeping: folder.retention)
        #expect(left.isEmpty)

        // A clip typed into the panel has no dictation behind it, whatever its words.
        _ = try await folder.store.record(typed, keeping: folder.retention)
        let kept = try await folder.store.deleteCopies(
            ofDictation: UUID(), saying: "print SQL", keeping: folder.retention)
        #expect(kept.map(\.id) == [typed.id])
    }

    @Test("the same words dictated twice are one clip that either dictation deletes")
    func repeatKeepsBothLinks() async throws {
        let folder = try TemporaryFolder()
        let first = UUID()
        let second = UUID()
        _ = try await folder.store.record(Self.copy("print SQL", of: first), keeping: folder.retention)
        _ = try await folder.store.record(Self.copy("print SQL", of: second), keeping: folder.retention)
        _ = try await folder.store.record(Self.copy("print SQL", of: second), keeping: folder.retention)

        let merged = try #require(await folder.store.clips(keeping: folder.retention).first)
        #expect(merged.dictations == [first, second])

        _ = try await folder.store.deleteCopies(
            ofDictation: first, saying: nil, keeping: folder.retention)
        #expect(await folder.store.clips(keeping: folder.retention).isEmpty)
    }

    @Test("the link survives being written and read back, and an older file reads as unlinked")
    func linkRoundTrips() throws {
        let dictation = UUID()
        let clip = Self.copy("print SQL", of: dictation).used(at: Date())
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(decoded.dictations == [dictation])

        var older = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        older["dictations"] = nil
        let unlinked = try JSONDecoder().decode(
            Clip.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(unlinked.dictations.isEmpty)
    }

    @Test("nothing to delete keeps every clip and answers with what is there")
    func nothingToDelete() async throws {
        let folder = try TemporaryFolder()
        let clip = Clip(text: "kept", kind: .text, copiedAt: Date())
        _ = try await folder.store.record(clip, keeping: folder.retention)

        let left = try await folder.store.deleteCopies(
            ofDictation: UUID(), saying: nil, keeping: folder.retention)

        #expect(left.map(\.id) == [clip.id])
    }
}
