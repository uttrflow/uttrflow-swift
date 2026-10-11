import UttrflowAI
import UttrflowCore

/// One piece of the recording, through every stage that runs before the words are joined.
struct Piece: Sendable {
    let heard: Transcription
    let corrected: CorrectedTranscript
    let cleaned: TransformationResult
}
