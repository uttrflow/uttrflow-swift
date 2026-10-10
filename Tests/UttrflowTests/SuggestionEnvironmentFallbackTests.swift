// Tests that the coordinator's machine fallback answers only for terminals (#1318).

import Foundation
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("The machine fallback answers only for terminals")
struct SuggestionEnvironmentFallbackTests {
    @Test(
        "An empty corpus falls back to the machine in a terminal and to nothing in an editor on the same folder"
    )
    func fallbackIsTerminalOnly() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-1318-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: "notes.txt"))
        let container = folder.appending(path: "container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let index = EnvironmentIndex(reader: FallbackMachine())
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true), environmentIndex: index
        )
        let scope = folder.path(percentEncoded: false)
        let shell = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: scope)
        let editor = Surface(bundleIdentifier: "com.apple.dt.Xcode", role: "AXTextArea", scope: scope)
        // One instant for every ask, so a stalled run cannot age the listing past its lifetime between them.
        let now = ContinuousClock.now

        // The first ask starts reads; settle their task handles before asking for the completed result.
        _ = await coordinator.candidates(
            for: SuggestionQuery(surface: shell, typed: "cat no", generation: 1), at: now)
        await index.settle()
        let offered = await coordinator.candidates(
            for: SuggestionQuery(surface: shell, typed: "cat no", generation: 2), at: now
        ).map(\.text)
        #expect(offered == ["cat notes.txt"])

        // The folder's listing is now held, so an empty answer here is the gate and not a read still pending.
        let inEditor = await coordinator.candidates(
            for: SuggestionQuery(surface: editor, typed: "cat no", generation: 3), at: now)
        #expect(inEditor.isEmpty)
    }
}

private struct FallbackMachine: EnvironmentReading {
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        if case .entries = kind { return ["notes.txt"] }
        return []
    }
}
