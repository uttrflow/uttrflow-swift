// A case written the way a dictation is: through the pipeline, with the case's snippets stored.
import struct Foundation.Date
package import UttrflowCore
import UttrflowPipeline

extension EvaluationCase {
    /// What the pipeline writes for this case with `cleaner` as its tidier and the case's dictionary and snippets stored.
    package func written(
        through cleaner: any TranscriptCleaning, layers: QualityLayers = QualityLayers(),
        withholdingContext: Bool = false
    ) async -> String {
        let stored = snippets.map {
            Snippet(trigger: $0.key, expansion: $0.value, created: Date(timeIntervalSince1970: 0))
        }
        let pipeline = LayerAblation.chain(expanding: ListedSnippets(stored))(
            layers, DegradedPathMatrix.corrector(for: self), DegradedPathMatrix.speechWords(for: self),
            cleaner)
        let cleaned = await pipeline.clean([transcription], seeing: withholdingContext ? .unknown : context)
        return cleaned.text ?? ""
    }
}
