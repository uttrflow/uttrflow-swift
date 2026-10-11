// What only the machine knows about the clips in the panel's list, asked on opening and on every refresh.

import UttrflowClipboard
import UttrflowCore

/// B8, D5 — the answers the panel needs beside its clips.
struct PanelListFacts: Sendable {
    /// The picture clips whose files are gone, at one `stat` each and none for text.
    let missingPictures: Set<Clip.ID>
    /// The file clips with a file gone, each with the names that are missing.
    let missingFiles: [Clip.ID: [String]]
    /// D5 — the languages in the list that have a formatter, asked per language and not per clip.
    let formattable: Set<CodeLanguage>

    static func about(
        _ clips: [Clip], clipboard: ClipboardStore, formatter: any CodeFormatting
    ) async -> PanelListFacts {
        var missing: Set<Clip.ID> = []
        for clip in clips {
            guard let image = clip.image else { continue }
            if !(await clipboard.hasImage(for: image)) { missing.insert(clip.id) }
        }
        var answered: Set<CodeLanguage> = []
        for language in Set(clips.compactMap(\.language)) where await formatter.isAvailable(for: language) {
            answered.insert(language)
        }
        return PanelListFacts(
            missingPictures: missing, missingFiles: Clip.missingFiles(among: clips), formattable: answered)
    }
}
