// Tests for the technical lexicon's neighbour report.

import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("The technical lexicon's neighbour report")
struct LexiconNeighboursTests {
    @Test("the shipped seed holds at least 300 terms, each with one report line")
    func everyTermReported() {
        let report = LexiconNeighbours.report()
        #expect(TechnicalLexicon.terms.count >= 300)
        #expect(report.map(\.id) == TechnicalLexicon.terms.map(\.id))
        let near = report.filter { !$0.neighbours.isEmpty }
        let ordinary = report.filter(\.isOrdinary).count
        print(
            "lexicon-neighbours: \(report.count) terms, \(near.count) with a neighbour, \(ordinary) ordinary")
        for line in near {
            print("lexicon-neighbours: \(line.id): \(line.neighbours.joined(separator: " "))")
        }
    }

    @Test("every term whose form is an ordinary word is limited to a destination")
    func ordinaryTermsAreLimited() {
        let limited = Set(TechnicalLexicon.terms.filter { $0.destinations != nil }.map(\.id))
        let ordinary = LexiconNeighbours.report().filter(\.isOrdinary).map(\.id)
        #expect(ordinary.allSatisfy(limited.contains))
    }

    @Test("a term's own spoken forms are never listed as its neighbours")
    func ownFormsExcluded() {
        let report = LexiconNeighbours.report()
        for (term, line) in zip(TechnicalLexicon.terms, report) {
            #expect(term.spoken.allSatisfy { !line.neighbours.contains($0) }, "\(term.id)")
        }
    }
}
