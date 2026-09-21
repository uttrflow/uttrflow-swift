// Tests that the app hands tab-to-complete its model as discretionary work.

import Foundation
import Testing

/// The entry point is wiring, so this reads its source to say the generator goes through the energy gate.
@Suite("How the app wires the suggestion model")
struct SuggestionModelWiringTests {
    private var source: String {
        get throws {
            let file = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/Uttrflow/UttrflowApp.swift")
            return try String(contentsOf: file, encoding: .utf8)
        }
    }

    @Test("wraps the generator so Low Power Mode and thermal pressure stop its passes")
    func generatorIsDiscretionary() throws {
        let text = try source
        #expect(text.contains("DiscretionaryGenerator("))
        #expect(text.contains("EnergyConditions.current().allowsDiscretionaryWork"))
    }

    @Test("holds the model only while it is asked for, over a window chosen by the Mac's memory")
    func modelIsReleasedWhenIdle() throws {
        let text = try source
        #expect(text.contains("IdleReleasingModel("))
        #expect(text.contains("IdleRelease.window(physicalMemory: ProcessInfo.processInfo.physicalMemory)"))
    }

    @Test("tells the app when an idle release makes the model load again")
    func reloadsReachTheApp() throws {
        let text = try source
        #expect(text.contains("onReload: { reported.yield($0) }"))
        #expect(text.contains("for await event in reloads { delegate.suggestionModelReloaded(event) }"))
    }

    @Test("tells the app when an idle reload finds the weights gone, rather than fetching them")
    func missingWeightsReachTheApp() throws {
        let text = try source
        #expect(text.contains("scoring.whenReloadFails"))
        #expect(text.contains("suggestionModelWentMissing()"))
    }
}
