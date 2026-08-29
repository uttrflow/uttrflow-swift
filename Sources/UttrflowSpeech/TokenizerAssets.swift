public import Foundation

/// The vocabulary a recogniser turns its output tokens back into words with.
///
/// Its own type because two parts of the module must agree about it and neither owns
/// the other: the store, which cannot honestly call a model installed without one, and
/// the recogniser, which must find it beside the weights or WhisperKit will fetch it
/// from the network at the moment somebody speaks.
public enum TokenizerAssets {
    /// What a complete tokenizer consists of.
    ///
    /// `tokenizer.json` carries the vocabulary and the merges; `tokenizer_config.json`
    /// names the tokeniser class and its special tokens. WhisperKit's loader looks for
    /// the first to decide a folder is worth reading and needs the second to build the
    /// tokeniser from it, so a folder holding only one of them is no use.
    public static let fileNames = ["tokenizer.json", "tokenizer_config.json"]

    /// Whether a complete tokenizer sits directly in `folder`.
    ///
    /// Directly, not nested: that is where WhisperKit searches when it is told the
    /// model's own directory, and matching it here is what makes ``SpeechModelStore``'s
    /// answer to "is this installed?" the same question the recogniser will ask.
    public static func arePresent(in folder: URL) -> Bool {
        fileNames.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// Removes whatever tokenizer files are in `folder`.
    ///
    /// Unwinds a fetch that got part way. Half a tokenizer is worse than none, because
    /// the next attempt would have to decide whether to trust what it found.
    public static func remove(from folder: URL) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
