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
}
