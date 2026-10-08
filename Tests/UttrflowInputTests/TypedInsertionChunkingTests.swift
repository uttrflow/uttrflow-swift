import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowInput

/// Reports an application that a test can change between typed chunks.
private final class MovableFocus: AccessibilityFocus, @unchecked Sendable {
    private let application = Mutex(
        InsertionDestination(applicationName: "Notes", bundleIdentifier: "example.notes"))
    private let isSelf = Mutex(false)

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { isSelf.withLock { $0 } }
    func focusedApplication() -> InsertionDestination? { application.withLock { $0 } }

    func moveTo(_ name: String) {
        let moved = InsertionDestination(applicationName: name, bundleIdentifier: "example.\(name)")
        application.withLock { $0 = moved }
    }

    func becomeSelf() { isSelf.withLock { $0 = true } }
}

/// Records each chunk and runs `afterChunk` with the number of chunks typed so far.
private final class ChunkTypist: KeystrokeTyping, @unchecked Sendable {
    private let chunks = Mutex<[String]>([])
    private let afterChunk: @Sendable (Int) -> Void
    private let failOnChunk: Int?

    init(failOnChunk: Int? = nil, afterChunk: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.failOnChunk = failOnChunk
        self.afterChunk = afterChunk
    }

    var typed: [String] { chunks.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        let count = chunks.withLock { $0.count } + 1
        if count == failOnChunk { throw .accessibilityDenied }
        chunks.withLock { $0.append(text) }
        afterChunk(count)
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {}
}

@Suite("Typing a long text in chunks")
struct TypedInsertionChunkingTests {
    private let length = TypedTextInsertionEngine.chunkLength

    @Test("Long text is typed whole, in bounded chunks, in order.")
    func typesEverythingInChunks() async throws {
        let text = String(repeating: "abcdé🙂 ", count: 40)
        let typist = ChunkTypist()
        let engine = TypedTextInsertionEngine(focus: MovableFocus(), typist: typist)

        _ = try await engine.insert(text)

        #expect(typist.typed.joined() == text)
        #expect(typist.typed.allSatisfy { $0.count <= length })
        #expect(typist.typed.count > 1)
    }

    @Test("No chunk boundary falls inside a ZWJ emoji, flag, combining mark or Devanagari conjunct.")
    func chunksSplitOnlyBetweenClusters() async throws {
        let clusters = [
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F1EE}\u{1F1F3}", "e\u{301}",
            "\u{915}\u{94D}\u{937}",
        ]
        for cluster in clusters {
            let text = String(repeating: "a", count: length - 1) + String(repeating: cluster, count: 3)
            let typist = ChunkTypist()
            _ = try await TypedTextInsertionEngine(focus: MovableFocus(), typist: typist).insert(text)

            #expect(typist.typed.joined() == text)
            #expect(typist.typed.map(\.count).reduce(0, +) == text.count)
            #expect(typist.typed[1].hasPrefix(cluster))
        }
    }

    @Test("Switching app partway stops typing and names how much went in.")
    func stopsWhenTheAppChanges() async {
        let focus = MovableFocus()
        let typist = ChunkTypist { chunk in if chunk == 2 { focus.moveTo("Mail") } }
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)
        let text = String(repeating: "a", count: length * 5)

        await #expect(throws: TextInsertionError.insertionInterrupted(typed: length * 2, total: length * 5)) {
            _ = try await engine.insert(text)
        }
        #expect(typist.typed.count == 2)
    }

    @Test("Uttrflow coming to the front partway stops typing.")
    func stopsWhenSelfIsFrontmost() async {
        let focus = MovableFocus()
        let typist = ChunkTypist { chunk in if chunk == 1 { focus.becomeSelf() } }
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        await #expect(throws: TextInsertionError.insertionInterrupted(typed: length, total: length * 3)) {
            _ = try await engine.insert(String(repeating: "a", count: length * 3))
        }
    }

    @Test("Cancelling the insertion stops typing between chunks.")
    func stopsWhenCancelled() async {
        let started = Mutex<Task<InsertionArrival, any Error>?>(nil)
        let typist = ChunkTypist { chunk in if chunk == 1 { started.withLock { $0?.cancel() } } }
        let engine = TypedTextInsertionEngine(focus: MovableFocus(), typist: typist)
        let text = String(repeating: "a", count: length * 4)
        let gate = Mutex(false)

        let task = Task<InsertionArrival, any Error> {
            while !gate.withLock({ $0 }) { await Task.yield() }
            return try await engine.insert(text)
        }
        started.withLock { $0 = task }
        gate.withLock { $0 = true }

        let result = await task.result
        #expect(throws: TextInsertionError.insertionInterrupted(typed: length, total: length * 4)) {
            try result.get()
        }
        #expect(typist.typed.count == 1)
    }

    @Test("A typist failure after some text went in is a partial insertion, which stops other routes.")
    func laterFailureIsPartial() async {
        let typist = ChunkTypist(failOnChunk: 2)
        let engine = TypedTextInsertionEngine(focus: MovableFocus(), typist: typist)

        await #expect(throws: TextInsertionError.insertionInterrupted(typed: length, total: length * 2)) {
            _ = try await engine.insert(String(repeating: "a", count: length * 2))
        }
        #expect(TextInsertionError.insertionInterrupted(typed: 1, total: 2).stopsFallback)
    }

    @Test("A typist failure before anything went in keeps its own reason.")
    func firstFailureKeepsItsReason() async {
        let engine = TypedTextInsertionEngine(focus: MovableFocus(), typist: ChunkTypist(failOnChunk: 1))

        await #expect(throws: TextInsertionError.accessibilityDenied) {
            _ = try await engine.insert("mit")
        }
    }
}
