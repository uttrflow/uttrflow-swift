// Which dictionary words a landed dictation wrote.

public import struct Foundation.UUID
public import UttrflowDictionary

/// The entries a dictation used, whether a rewrite wrote the spelling or the prompt made the recogniser spell it.
public enum DictionaryAppearances {
    /// Each entry `applied` names, then each other entry whose spelling stands in `text` as whole words, once.
    public static func used(
        _ entries: [DictionaryEntry], applied: [UUID], writtenIn text: String
    ) -> [UUID] {
        let written = entries.lazy
            .filter { MeaningPreservationGuard.isWritten($0.word, in: text) }
            .map(\.id)
        var counted: Set<UUID> = []
        return (applied + written).filter { counted.insert($0).inserted }
    }
}
