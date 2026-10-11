import Foundation
import UttrflowCore

extension ClipboardStore {
    /// The clip this arrival is another copy of, if the same list already holds it.
    static func previous(for clip: Clip, in existing: [Clip]) -> Clip? {
        // Only within one list: a sentence dictated and the same sentence copied are two clips.
        let sameList = existing.filter { $0.origin == clip.origin }
        if let sha = clip.image?.sha {
            return sameList.first { $0.image?.sha == sha }
        }
        if let files = clip.files {
            return sameList.first { $0.files?.map(\.path) == files.map(\.path) }
        }
        guard clip.image == nil else { return nil }
        return sameList.first { $0.text == clip.text && $0.image == nil && $0.files == nil }
    }

    /// A copy of a clip keeping its identity and every field the user chose, differing only where named.
    static func rebuilding(
        _ clip: Clip, text: String, richText: String?, image: ClipImage?
    ) -> Clip {
        let classified =
            image == nil
            ? ClipKindDetector.classification(of: text)
            : ClipClassification(kind: .image, language: nil)
        return clip.with {
            $0.text = text
            $0.kind = classified.kind
            $0.language = classified.language
            $0.richText = richText
            $0.image = image
            // An unlinked dictation copy keeps its first words, the only thing deleting its dictation can match.
            $0.dictatedText = clip.dictatedText ?? (clip.isUnlinkedDictationCopy ? clip.text : nil)
        }
    }

    /// The same clip, copying only `dictations`.
    static func relinking(_ clip: Clip, to dictations: [UUID]) -> Clip {
        clip.with { $0.dictations = dictations }
    }

    /// Carries what the user chose about a clip onto the copy that has just replaced it.
    static func inheriting(_ previous: Clip, from arrival: Clip) -> Clip {
        // A kept clip the user chose to keep on disk is never made a memory-only secret by a repeat of the same text.
        let staysKept = previous.isKept && Self.isPersistable(previous) && !Self.isPersistable(arrival)
        let classified = staysKept ? previous : arrival
        // Built on the previous clip, so its identity, origin and everything the user decided stay with it.
        return previous.with {
            $0.text = arrival.text
            $0.kind = classified.kind
            $0.copiedAt = arrival.copiedAt
            $0.source = arrival.source
            // Both dictations, so the clip goes only once neither of them is left.
            $0.dictations += arrival.dictations.filter { !previous.dictations.contains($0) }
            // Copying something again is reaching for it, so the eviction clock moves too.
            $0.lastUsedAt = arrival.copiedAt
            // Detected from the text recorded now and from this pasteboard, unless the kind stayed the kept clip's.
            $0.language = classified.language
            // A plain repeat keeps the clip's rich text, which may be a note the user wrote in the panel.
            $0.richText = arrival.richText ?? previous.richText
            // The file already on disk, not the one just written; the arrival's would strand it.
            $0.image = previous.image ?? arrival.image
            // The newest bookmarks, since they follow the files that moved.
            $0.files = arrival.files ?? previous.files
            // One more time, not a new clip; saturates at Int.max instead of trapping.
            $0.timesCopied = previous.timesCopied == .max ? .max : previous.timesCopied + 1
        }
    }

    /// Restoring a duplicate revives the deleted clip's choices without rewinding the newer copy.
    static func restoring(_ deleted: Clip, over newer: Clip) -> Clip {
        newer.with {
            $0.dictations += deleted.dictations.filter { !newer.dictations.contains($0) }
            $0.dictatedText = newer.dictatedText ?? deleted.dictatedText
            $0.alias = newer.alias ?? deleted.alias
            $0.tags = newer.tags.isEmpty ? deleted.tags : newer.tags
            $0.category = newer.category ?? deleted.category
            $0.isPinned = newer.isPinned || deleted.isPinned
            $0.timesCopied = newer.timesCopied == .max ? .max : newer.timesCopied + 1
        }
    }
}
