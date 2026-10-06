// Tests for the shipped technical lexicon: it loads from the bundle, and the entry checks reject what cannot ship.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("The technical lexicon ships as data and rejects entries that cannot ship")
struct TechnicalLexiconTests {
    @Test("The shipped lexicon loads from the bundle with a term in every category.")
    func shipped() {
        #expect(TechnicalLexicon.isBundled)
        #expect(!TechnicalLexicon.terms.isEmpty)
        let categories = Set(TechnicalLexicon.terms.map(\.category))
        #expect(categories == Set(TechnicalTerm.Category.allCases))
        #expect(TechnicalLexicon.table.source == .bundled)
    }

    @Test("The file endings marked everyday in the lexicon are the ones that need a cue to be a file name.")
    func everydayEndings() {
        #expect(TechnicalToken.wordLikeFileExtensions == ["swift", "go", "sh", "java", "zip", "lock"])
        #expect(TechnicalToken.wordLikeFileExtensions.isSubset(of: TechnicalToken.fileExtensions))
    }

    @Test("Every shipped term is well formed when nothing is treated as an ordinary word.")
    func shippedWellFormed() {
        #expect(TechnicalLexicon.problems(in: TechnicalLexicon.terms) { _ in false }.isEmpty)
    }

    @Test("A term said as an ordinary word is rejected unless a destination limits it.")
    func ordinaryNeedsDestination() throws {
        let terms = try decode(
            #"""
            [{"id": "main", "category": "concept", "spoken": ["main"]},
             {"id": "pull", "category": "command", "spoken": ["pull"], "destinations": ["terminal"]}]
            """#)
        let problems = TechnicalLexicon.problems(in: terms) { ["main", "pull"].contains($0) }
        #expect(problems == [.ordinaryWithoutDestination(id: "main")])
    }

    @Test("A term with no spoken form, a malformed one, or no destination is rejected.")
    func malformedRejected() throws {
        let terms = try decode(
            #"""
            [{"id": "a", "category": "acronym", "spoken": []},
             {"id": "b", "category": "acronym", "spoken": ["B  c", "d-e"]},
             {"id": "c", "category": "tool", "spoken": ["c"], "destinations": []}]
            """#)
        #expect(
            TechnicalLexicon.problems(in: terms) { _ in false } == [
                .unspoken(id: "a"), .malformedSpoken(id: "b", spoken: "B  c"),
                .malformedSpoken(id: "b", spoken: "d-e"), .appliesNowhere(id: "c"),
            ])
    }

    @Test("A non-Latin written form, or a phrase said twice in one category and place, is rejected.")
    func collisionsRejected() throws {
        let terms = try decode(
            #"""
            [{"id": "API", "category": "acronym", "spoken": ["a p i"]},
             {"id": "\u0917\u093F\u091F", "category": "command", "spoken": ["git"]},
             {"id": "APIs", "category": "acronym", "spoken": ["a p i"]},
             {"id": "ssh", "category": "command", "spoken": ["s s h"], "destinations": ["terminal"]},
             {"id": "SSH", "category": "acronym", "spoken": ["s s h"]},
             {"id": "Ssh", "category": "command", "spoken": ["s s h"], "destinations": ["codeEditor"]}]
            """#)
        #expect(
            TechnicalLexicon.problems(in: terms) { _ in false } == [
                .malformedWritten(id: "\u{0917}\u{093F}\u{091F}"),
                .duplicateSpoken(id: "APIs", spoken: "a p i", earlier: "API"),
            ])
    }

    @Test("Pronunciations default to empty, and a term without destinations applies everywhere.")
    func defaults() throws {
        let term = try #require(
            try decode(#"[{"id": "API", "category": "acronym", "spoken": ["a p i"]}]"#).first)
        #expect(term.pronunciations.isEmpty)
        #expect(Destination.allCases.allSatisfy(term.applies(in:)))
    }

    @Test("A written form repeated in the file refuses the whole file.")
    func repeatedWritten() {
        #expect(throws: DataTableError.duplicateID("API")) {
            _ = try decode(
                #"""
                [{"id": "API", "category": "acronym", "spoken": ["a p i"]},
                 {"id": "API", "category": "acronym", "spoken": ["a pee i"]}]
                """#)
        }
    }

    @Test("An unknown category refuses the whole file.")
    func unknownCategory() {
        let file = #"{"schema": 1, "rows": [{"id": "x", "category": "brand", "spoken": ["x"]}]}"#
        #expect(throws: DataTableError.malformed) {
            try DataTable<TechnicalTerm>.decode(Data(file.utf8), schema: 1, limits: .standard)
        }
    }

    private func decode(_ rows: String) throws -> [TechnicalTerm] {
        try DataTable<TechnicalTerm>.decode(
            Data(#"{"schema": 1, "rows": \#(rows)}"#.utf8), schema: 1, limits: .standard)
    }
}
