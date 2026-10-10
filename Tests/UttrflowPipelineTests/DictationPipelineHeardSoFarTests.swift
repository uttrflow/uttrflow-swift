// Tests the finished pieces shown in the panel while the key is held, never typed into the field.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Collects every value a stream gives, so a test can read the latest one.
private actor Latest {
    private(set) var values: [String?] = []
    func add(_ value: String?) { values.append(value) }
    var last: String?? { values.last }
}

@Suite("Words heard while the key is held")
struct DictationPipelineHeardSoFarTests {
    private static let rate = AudioSamples.canonicalSampleRate

    private static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Two phrases with a clear pause after the first, so one piece is finished while the key is held.
    private static let twoPieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.4))

    private func start(
        secure: Bool = false
    ) async -> (DictationPipeline, Latest, Task<Void, Never>, ScenarioSession) {
        let session = await ScenarioDriver.session(
            Scenario(
                pieces: (1...8).map { ScriptedPiece("w\($0) x") }, context: .fixture(isSecure: secure),
                cleaner: FakeTranscriptCleaner(producedBy: .foundationModels), take: Self.twoPieces))
        let pipeline = session.pipeline
        let latest = Latest()
        let stream = await pipeline.wordsHeardSoFar()
        let watching = Task {
            for await words in stream { await latest.add(words) }
        }
        await pipeline.startRecording()
        return (pipeline, latest, watching, session)
    }

    @Test("a finished piece's words are shown before key-up, and nothing is typed")
    func showsTheFirstPieceBeforeKeyUp() async throws {
        let (pipeline, latest, watching, session) = await start()
        let inserter = session.inserter
        defer { watching.cancel() }

        try await eventually { (await latest.last ?? nil)?.isEmpty == false }

        #expect(await pipeline.currentState == .recording)
        #expect(inserter.received.isEmpty)
        await pipeline.finishRecording()
        #expect(await latest.last == .some(nil))
    }

    @Test("a cancel clears the words, and nothing is typed")
    func cancelClearsTheWords() async throws {
        let (pipeline, latest, watching, session) = await start()
        let inserter = session.inserter
        defer { watching.cancel() }

        try await eventually { (await latest.last ?? nil) != nil }
        await pipeline.cancel()

        try await eventually { await latest.last == .some(nil) }
        #expect(inserter.received.isEmpty)
    }

    @Test("a secure field shows no words")
    func secureFieldShowsNothing() async throws {
        let (pipeline, latest, watching, session) = await start(secure: true)
        defer { watching.cancel() }

        try await eventually { await session.speech.hints.count >= 2 }
        await pipeline.finishRecording()

        #expect(await latest.values.allSatisfy { $0 == nil })
    }
}
