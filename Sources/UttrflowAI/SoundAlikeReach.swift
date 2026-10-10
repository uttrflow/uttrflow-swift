// How far a misheard word gets towards the word meant, at each gate the correction path asks.
internal import Foundation
internal import UttrflowDictionary
internal import UttrflowCore

/// Which correction gates would let `heard` reach `meant` were `meant` in the dictionary. See Docs/eval-methodology.md.
public struct SoundAlikeReach: Sendable, Equatable {
    /// The two spell the same once case, spaces and marks are closed up, so nothing is misheard.
    public let isSameSpelling: Bool
    /// The sound key alone links the two spellings.
    public let sharesKey: Bool
    /// The sound key links them and they are within one phoneme of each other.
    public let passesDistance: Bool
    /// A dictionary entry spelt `meant` accepts `heard` as its reading.
    public let entrySpells: Bool

    public init(heard: String, meant: String) {
        let heardClosed = ReadingRestraint.closedUp(heard)
        let meantClosed = ReadingRestraint.closedUp(meant)
        isSameSpelling = heardClosed == meantClosed
        sharesKey = WordSound(of: heard).sounds(like: WordSound(of: meant))
        passesDistance = sharesKey && ReadingRestraint.soundsNear(meant, heard: heard)
        let entry = DictionaryEntry(word: meant, origin: .added, firstSeen: .distantPast)
        entrySpells = WordCorrectionEngine.spells(entry, asHeard: heard)
    }
}
