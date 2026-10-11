import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

/// A temporary store keeps the adapter's fixtures separate from the app's snippets.
private struct SnippetSandbox: ~Copyable {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "uttrflow-stored-snippets-\(UUID().uuidString)")

    var store: SnippetStore { SnippetStore(file: root.appending(path: "snippets.v1.json")) }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// The real store's expansion as the dictation pipeline receives it.
@Suite("Stored snippets at the pipeline boundary")
struct StoredSnippetsTests {
    @Test("an adapter reads snippets saved after it is created")
    func currentStoreThroughProtocol() async throws {
        let sandbox = SnippetSandbox()
        let store = sandbox.store
        let adapter: any SnippetExpanding = StoredSnippets(store: store)
        let text = "alpha marker"
        #expect(try await adapter.expand(text, in: nil) == .unchanged(text))

        let snippet = Snippet(
            trigger: text, expansion: "First token", created: Date(timeIntervalSince1970: 0))
        try await store.save(snippet)

        #expect(
            try await adapter.expand(text, in: nil)
                == ExpandedTranscript(
                    text: "First token",
                    snippets: [SnippetUse(snippetID: snippet.id, matched: text, expansion: "First token")]))
    }

    @Test("every firing keeps its identity, original matched words and replacement in order")
    func orderedFirings() async throws {
        let sandbox = SnippetSandbox()
        let store = sandbox.store
        let first = Snippet(
            trigger: "alpha marker", expansion: "First token", created: Date(timeIntervalSince1970: 0))
        let second = Snippet(
            trigger: "beta marker", expansion: "Second token", created: Date(timeIntervalSince1970: 0))
        try await store.save(first)
        try await store.save(second)
        let adapter: any SnippetExpanding = StoredSnippets(store: store)

        #expect(
            try await adapter.expand("alpha marker then BETA marker then alpha marker", in: nil)
                == ExpandedTranscript(
                    text: "First token then Second token then First token",
                    snippets: [
                        SnippetUse(snippetID: first.id, matched: "alpha marker", expansion: "First token"),
                        SnippetUse(snippetID: second.id, matched: "BETA marker", expansion: "Second token"),
                        SnippetUse(snippetID: first.id, matched: "alpha marker", expansion: "First token"),
                    ]))
    }

    @Test("the marker-free replacement and caret reach the pipeline together")
    func caretPropagation() async throws {
        let sandbox = SnippetSandbox()
        let store = sandbox.store
        let snippet = Snippet(
            trigger: "alpha marker", expansion: "Dear {caret},\nThanks",
            created: Date(timeIntervalSince1970: 0))
        try await store.save(snippet)
        let adapter: any SnippetExpanding = StoredSnippets(store: store)

        #expect(
            try await adapter.expand("Before 🙂 alpha marker", in: nil)
                == ExpandedTranscript(
                    text: "Before 🙂 Dear ,\nThanks",
                    snippets: [
                        SnippetUse(
                            snippetID: snippet.id, matched: "alpha marker", expansion: "Dear ,\nThanks")
                    ], caret: "Before 🙂 Dear ".utf16.count))
    }

    @Test("a confined snippet fires only in its chosen application")
    func applicationScope() async throws {
        let sandbox = SnippetSandbox()
        let store = sandbox.store
        let snippet = Snippet(
            trigger: "alpha marker", expansion: "First token", created: Date(timeIntervalSince1970: 0),
            applications: ["com.example.fixture-editor"])
        try await store.save(snippet)
        let adapter: any SnippetExpanding = StoredSnippets(store: store)

        #expect(
            try await adapter.expand("alpha marker", in: "com.example.fixture-editor")
                == ExpandedTranscript(
                    text: "First token",
                    snippets: [
                        SnippetUse(snippetID: snippet.id, matched: "alpha marker", expansion: "First token")
                    ]))
        #expect(
            try await adapter.expand("alpha marker", in: "com.example.other-editor")
                == .unchanged("alpha marker"))
        #expect(try await adapter.expand("alpha marker", in: nil) == .unchanged("alpha marker"))
    }
}
