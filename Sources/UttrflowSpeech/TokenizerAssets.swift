// What a complete tokenizer consists of, and whether one is present.
public import Foundation

/// The vocabulary a recogniser decodes with; the store and the recogniser must agree where it lives.
public enum TokenizerAssets {
    /// What a complete tokenizer consists of; WhisperKit needs both files or the folder is no use.
    public static let fileNames = ["tokenizer.json", "tokenizer_config.json"]

    /// Whether a complete tokenizer sits directly in `folder`, which is where WhisperKit searches.
    public static func arePresent(in folder: URL) -> Bool {
        fileNames.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// Removes whatever tokenizer files are in `folder`, since half a tokenizer is worse than none.
    public static func remove(from folder: URL) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
