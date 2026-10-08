// Tests that no shipped technical term claims an ordinary word everywhere.

import Testing
import UttrflowCore
import UttrflowDictionary

@Suite("The shipped technical lexicon against the ordinary-word list")
struct TechnicalLexiconOrdinaryTests {
    @Test("Every term written or said as an ordinary word is limited to the destinations it belongs in.")
    func ordinaryTermsAreLimited() {
        #expect(
            TechnicalLexicon.problems(in: TechnicalLexicon.terms, isOrdinary: GeneralVocabulary.isOrdinary)
                .isEmpty)
    }

    @Test("The language Go, said as an ordinary word, applies only in code and the terminal.")
    func goIsLimited() {
        #expect(GeneralVocabulary.isOrdinary("go"))
        #expect(TechnicalLexicon.terms.first { $0.id == "Go" }?.destinations == [.codeEditor, .terminal])
    }
}
