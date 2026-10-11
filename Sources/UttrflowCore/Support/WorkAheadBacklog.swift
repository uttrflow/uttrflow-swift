// How much of a dictation was still undecoded when the key came up. See `Docs/early-transcription.md`.
import Foundation

/// The audio working ahead has not reached at key-up, which is the part of the wait that grows with the dictation.
public struct WorkAheadBacklog: Sendable, Equatable {
    /// Seconds of audio not yet decoded at key-up.
    public let seconds: Double
    /// The pieces that audio is cut into, the one under way at key-up included.
    public let pieces: Int

    /// A backlog of `seconds` of audio in `pieces` pieces.
    public init(seconds: Double, pieces: Int) {
        self.seconds = seconds
        self.pieces = pieces
    }
}
