import UttrflowAI
import UttrflowClipboard
import UttrflowCore
import UttrflowDictionary

/// Prepares the chosen personal-data archive and its disclosure for export.
enum PersonalDataExport {
    enum Choice: Sendable {
        case excludeSecretSnippets
        case includeAllSnippets
    }

    static let disclosureMessage =
        "The export file is not encrypted. You can exclude snippets that contain recognized credentials, or include every snippet."

    /// `refused` is oldest first, as the archive keeps it.
    static func archive(
        dictionary: [DictionaryEntry], snippets: [Snippet], refused: [String] = [], choice: Choice
    ) -> PersonalDataArchive {
        let exportedSnippets: [Snippet]
        switch choice {
        case .excludeSecretSnippets:
            exportedSnippets = snippets.filter {
                !SecretShapes.matches($0.trigger) && !SecretShapes.matches($0.expansion)
            }
        case .includeAllSnippets:
            exportedSnippets = snippets
        }
        return PersonalDataArchive(dictionary: dictionary, snippets: exportedSnippets, refused: refused)
    }
}
