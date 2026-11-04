// A matcher's expansion in the form the pipeline writes, and a matcher over snippets already in hand.
package import UttrflowAI
package import UttrflowCore

extension SnippetExpander {
    /// What this matcher makes of `text`, as the pipeline records an expansion.
    package func expanded(_ text: String) -> ExpandedTranscript {
        let expansion = expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            }, caret: expansion.caret)
    }
}

/// The snippet matcher over a fixed list, for a harness that hands the pipeline snippets rather than a store.
package struct ListedSnippets: SnippetExpanding {
    let snippets: [Snippet]

    package init(_ snippets: [Snippet]) {
        self.snippets = snippets
    }

    package func expand(_ text: String, in application: String?) async -> ExpandedTranscript {
        SnippetExpander(snippets: snippets, in: application).expanded(text)
    }
}
