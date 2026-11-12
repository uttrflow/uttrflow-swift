import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// An app's formatting mode reaches the dictation path: "Work it out" writes notation, "Plain prose" does not.
@Suite("Dictation: the per-app formatting mode", .bug(id: 3898))
struct DictationAdapterModeTests {
    private static let xcode = DestinationRules.xcode

    private let editor = AppContext.fixture(
        applicationName: "Xcode", bundleIdentifier: DestinationRules.xcode,
        documentName: "Parser.swift", precedingText: "let value = ")

    /// The same words heard in each of `dictations` takes, one window each, tidied by the rules alone.
    private func scenario(
        saying heard: String, dictations: Int = 1, overrides: DestinationOverrides,
        in context: AppContext
    ) -> Scenario {
        Scenario(
            pieces: Array(repeating: ScriptedPiece(heard), count: dictations), context: context,
            cleaner: TransformerRouter(
                engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies),
            take: ScenarioDriver.oneWindow, destinationOverrides: overrides)
    }

    private func inserted(
        saying heard: String, overrides: DestinationOverrides, in context: AppContext
    ) async -> String? {
        await ScenarioDriver.run(scenario(saying: heard, overrides: overrides, in: context)).writes.last
    }

    @Test("work it out writes spoken symbols in code; plain prose leaves the words as said")
    func modeDecidesNotation() async {
        let spoken = "limit equals twelve"
        let auto = await inserted(saying: spoken, overrides: .none, in: editor)
        let prose = await inserted(
            saying: spoken,
            overrides: DestinationOverrides.none.setting(
                mode: .prose, for: Self.xcode, named: "Xcode", fallback: .codeEditor),
            in: editor)
        #expect(auto?.contains("limit = 12") == true, "\(auto ?? "nil")")
        #expect(prose?.contains("=") == false, "\(prose ?? "nil")")
        #expect(prose?.lowercased().contains("limit equals") == true, "\(prose ?? "nil")")
    }

    @Test("the mode belongs to one app: another app and a forced adapter still write notation")
    func modeIsPerApp() async {
        let spoken = "limit equals twelve"
        let other = DestinationOverrides.none.setting(
            mode: .prose, for: "com.example.Other", named: "Other", fallback: .codeEditor)
        let forced = DestinationOverrides.none.setting(
            mode: .forced(AdapterID(rawValue: "source.swift")), for: Self.xcode, named: "Xcode",
            fallback: .codeEditor)
        #expect(await inserted(saying: spoken, overrides: other, in: editor)?.contains("limit = 12") == true)
        #expect(await inserted(saying: spoken, overrides: forced, in: editor)?.contains("limit = 12") == true)
    }

    @Test("as typed applies to the next dictation only, shows while pending and can be taken back")
    func oneShotAsTyped() async {
        let spoken = "limit equals twelve"
        let session = await ScenarioDriver.session(
            scenario(saying: spoken, dictations: 3, overrides: .none, in: editor))
        let pipeline = session.pipeline
        let inserter = session.inserter
        #expect(await pipeline.pendingFormat == nil)
        await pipeline.format(next: .prose)
        #expect(await pipeline.pendingFormat == .prose)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(inserter.received.last?.contains("=") == false, "\(inserter.received)")
        #expect(await pipeline.pendingFormat == nil)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(inserter.received.last?.contains("limit = 12") == true, "\(inserter.received)")
        await pipeline.format(next: .prose)
        await pipeline.format(next: nil)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(inserter.received.last?.contains("limit = 12") == true, "\(inserter.received)")
    }

    @Test("a one-shot choice is never stored")
    func oneShotIsNotStored() throws {
        let held = DestinationOverrides.none.holding(oneShot: .prose)
        let data = try JSONEncoder().encode(held)
        #expect(try JSONDecoder().decode(DestinationOverrides.self, from: data).oneShotMode == nil)
        #expect(held.mode(for: editor) == .prose)
    }
}
