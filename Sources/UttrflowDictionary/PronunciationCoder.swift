// How a spelling is addressed in the index, for the spellings Double Metaphone cannot speak.

internal import Foundation

/// Every key a spelling is filed and looked up under, so no entry is stored at an address nothing reaches.
public enum PronunciationCoder {
    /// Double Metaphone where the spelling has English letters in it; the folded spelling where it has none.
    public static func keys(for text: String) -> [String] {
        let sound = DoubleMetaphone.code(for: text)
        guard sound.isSilent else { return sound.keys }
        let spelling = spellingKey(for: text)
        return spelling.isEmpty ? [] : [spelling]
    }

    /// The spelling itself as one key: case and accents folded away, and everything but letters and digits dropped.
    static func spellingKey(for text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}
