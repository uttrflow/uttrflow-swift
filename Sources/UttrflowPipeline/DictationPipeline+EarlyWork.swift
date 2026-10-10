// What the early loop holds while the key is down, and what it hands the release pass. See `Docs/early-transcription.md`.
import Foundation
import UttrflowCore

extension DictationPipeline {
    /// One span of a recording: the words a pass finished it with, or audio a later pass still has to do.
    enum Span {
        case done(Piece, span: UUID?)
        case pending(Range<Int>)
        /// Still being tidied when the key came up; joined by the release pass instead of waited on at the hand-off.
        case tidying(Tidying)

        /// A tidy under way and the words it tidies, which the next piece reads before the tidy ends.
        struct Tidying {
            let task: Task<Piece, Never>
            let heard: Transcription
            let span: UUID
        }

        /// The words recognised for this span, or `nil` for audio not yet recognised.
        var heard: Transcription? {
            switch self {
            case .done(let piece, _): piece.heard
            case .pending: nil
            case .tidying(let tidying): tidying.heard
            }
        }
    }

    /// The early loop's state, beside the main sequence rather than in it. See `Docs/early-transcription.md`.
    struct EarlyWork {
        /// Spans the early loop reached while the key was held, and where the audio it consumed ends.
        var spans: [Span] = []
        /// The pieces those spans finished, with the seams between them decided as each arrived.
        var running = RunningMessage()
        var cut = 0
        var lastWindowStart: Int?
        var task: Task<Void, Never>?
        /// A tidy the early loop started but has not yet folded into `spans`, picked up by the release pass at key-up.
        var tidyTask: Span.Tidying?
        /// Whether a piece is being recognised or tidied right now, which is what makes the drain a wait worth timing.
        var pieceInFlight = false
        /// Early recogniser calls still running after their cancelled task has returned.
        var decodesInFlight = 0
        /// Whether the loop is inside a recognition, which key-up lets finish rather than cancel.
        var recognising = false
        var context: AppContext?
        /// A microphone opened while a modifier press settles, before it belongs to a dictation.
        var pendingCapture: Task<Void, Never>?
        var pendingCaptureElapsed: (@Sendable () -> Duration)?
        /// Text from an unconfirmed paste, checked at the caret before another dictation starts.
        var pendingInsertion: String?
        var readsSettled = 0

        /// Clears what a previous dictation left, before the loop for this one starts.
        mutating func begin() {
            spans = []
            running = RunningMessage()
            cut = 0
            lastWindowStart = nil
            tidyTask = nil
            context = nil
        }

        /// Stops the loop and drops everything it reached.
        mutating func cancel() {
            task?.cancel()
            task = nil
            begin()
            pieceInFlight = false
        }

        /// Returns what the drained loop reached and clears it, a tidy still running joining as its last span.
        mutating func handOff() -> (
            spans: [Span], running: RunningMessage, cut: Int, lastWindowStart: Int?, context: AppContext?
        ) {
            var handed = spans
            if let tidyTask { handed.append(.tidying(tidyTask)) }
            let result = (handed, running, cut, lastWindowStart, context)
            task = nil
            begin()
            pieceInFlight = false
            return result
        }
    }

    /// What the early loop hands over: the spans it cut and the message they make, the audio left, the screen it read.
    struct Takeover {
        let spans: [Span]
        let running: RunningMessage
        let remainder: [Range<Int>]
        let context: AppContext?
    }
}
