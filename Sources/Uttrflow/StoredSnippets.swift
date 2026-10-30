import UttrflowAI
import UttrflowPipeline

/// The snippet matcher, built from what is on disk at the moment of the dictation.
struct StoredSnippets: SnippetExpanding {
    let store: SnippetStore

    func expand(_ text: String, in application: String?) async -> ExpandedTranscript {
        await store.expander(in: application).expanded(text)
    }
}
