import UttrflowAI
import UttrflowPipeline

/// The snippet matcher, built from what is on disk at the moment of the dictation.
struct StoredSnippets: SnippetExpanding {
    let store: SnippetStore

    func expand(_ text: String, in application: String?) async -> ExpandedTranscript {
        let expansion = await store.expander(in: application).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(
                    snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            }, caret: expansion.caret)
    }
}
