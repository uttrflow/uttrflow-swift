// Tests for the spoken command registry: it ships, it holds every command, and no phrase means two things at once.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("Every spoken command is one row of one registry")
struct SpokenCommandsTests {
    @Test("The registry loads from the bundle with every command the passes held in code.")
    func shipped() {
        #expect(SpokenCommands.table.source == .bundled)
        #expect(SpokenCommands.marks.count == 31)
        #expect(SpokenCommands.layout.count == 5)
        #expect(SpokenCommands.codeSymbols.count == 20)
        #expect(SpokenCommands.casings.count == 7)
        #expect(
            SpokenCommands.openings.map(\.words) == [
                ["open", "quote"], ["open", "single", "quote"], ["quote"], ["open", "paren"],
                ["open", "parenthesis"], ["open", "parentheses"], ["open", "bracket"],
            ])
        #expect(
            SpokenCommands.closings.map(\.words) == [
                ["close", "quote"], ["end", "quote"], ["unquote"], ["close", "single", "quote"],
                ["close", "paren"], ["close", "parenthesis"], ["close", "parentheses"], ["close", "bracket"],
            ])
    }

    @Test("No two rows read by the same pass share a phrase in the same destination.")
    func phrasesAreUnique() {
        for destination in Destination.allCases {
            var seen: Set<String> = []
            for row in SpokenCommands.table.rows where row.isEnabled(in: destination) {
                let key = "\(row.action) \(row.words.joined(separator: " "))"
                #expect(seen.insert(key).inserted, "\(key) is said twice in \(destination)")
            }
        }
    }

    @Test("A row without a placement, list flag or destinations is a trailing mark enabled everywhere.")
    func defaults() throws {
        let json = #"{"schema": 1, "rows": [{"id": "x", "words": ["x"], "action": "mark", "text": "x"}]}"#
        let data = Data(json.utf8)
        let row = try #require(
            try DataTable<SpokenCommand>.decode(data, schema: 1, limits: .standard).first)
        #expect(row.placement == .trailing)
        #expect(!row.requiresLists)
        #expect(Destination.allCases.allSatisfy(row.isEnabled(in:)))
    }
}
