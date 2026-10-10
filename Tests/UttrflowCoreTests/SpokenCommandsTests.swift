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
        #expect(SpokenCommands.codeSymbols.count == 48)
        #expect(SpokenCommands.keywords.count == 29)
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

    @Test("No two rows read by the same pass share a phrase in the same destination and language.")
    func phrasesAreUnique() {
        let languages: [CodeLanguage?] = [nil] + CodeLanguage.allCases
        for destination in Destination.allCases {
            for language in languages {
                var seen: Set<String> = []
                for row in SpokenCommands.table.rows
                where row.isEnabled(in: destination) && row.isEnabled(for: language) {
                    let key = "\(row.action) \(row.words.joined(separator: " "))"
                    #expect(
                        seen.insert(key).inserted,
                        "\(key) is said twice in \(destination) for \(language?.rawValue ?? "no language")")
                }
            }
        }
    }

    @Test("A row naming its languages is notation only in those, and in none where no language is known.")
    func languageRows() {
        let arrows = SpokenCommands.codeSymbols.filter { $0.words == ["arrow"] }
        #expect(Set(arrows.map(\.text)) == ["->", "=>"])
        let written = { (language: CodeLanguage?) in
            arrows.filter { $0.isEnabled(for: language) }.map(\.text)
        }
        #expect(written(.swift) == ["->"])
        #expect(written(.python) == ["->"])
        #expect(written(.javascript) == ["=>"])
        #expect(written(.typescript) == ["=>"])
        #expect(written(nil).isEmpty)
        #expect(written(.go).isEmpty)
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
