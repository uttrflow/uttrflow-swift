// How a word or a run of words sounds, as keys an index files it under.

internal import Foundation
private import Synchronization

/// The phoneme-class keys of a word or a run of words, from the bundled lexicon and the spelling rules. See `Docs/pronunciation-lexicon.md`.
public struct WordSound: Sendable, Hashable {
    /// Counts the sounds worked out while bound, child tasks included, so a test can bound the work without a clock.
    @TaskLocal package static var tally: EncodingTally?

    /// Every key this text is filed and looked up under; empty for a text with no Latin letter, so `"2024"` has no bucket.
    public let keys: [String]

    /// The sound of one text in the shared lexicon; case, surrounding marks and Latin accents make no difference.
    public init(of text: String) {
        self.init(of: text, in: .shared)
    }

    /// The sound of one text in this lexicon.
    public init(of text: String, in lexicon: PhonemeLexicon) {
        Self.tally?.record()
        keys = lexicon.soundKeys(of: text)
    }

    /// Nothing in the text makes a sound: empty, or digits and punctuation only.
    public var isSilent: Bool { keys.isEmpty }

    /// Whether two texts could be the same words said aloud: any key of one matching any of the other.
    public func sounds(like other: WordSound) -> Bool { keys.contains(where: other.keys.contains) }

    /// Whether any key of this text is among `sounds`, the keys of everything else that was said or shown.
    public func sounds(likeAnyOf sounds: Set<String>) -> Bool { keys.contains(where: sounds.contains) }
}

/// How many sounds were worked out while this was bound to `WordSound.tally`.
package final class EncodingTally: Sendable {
    private let encoded = Mutex(0)

    package init() {}

    /// The sounds worked out so far.
    package var count: Int { encoded.withLock { $0 } }

    func record() { encoded.withLock { $0 += 1 } }
}
