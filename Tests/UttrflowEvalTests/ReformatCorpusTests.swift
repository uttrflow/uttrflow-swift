// Holds every reformat case to its expected text with its words unchanged, and the phrase to the whole utterance.
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowEval

@Suite("Reformat commands on the last dictation change case and layout, never a word")
struct ReformatCorpusTests {
    private let cases = EvaluationCorpus.reformatCases

    private func reformat(_ testCase: ReformatCase) -> Reformat? {
        SpokenCommands.reformats.first { $0.id == testCase.commandID }.flatMap { Reformat(rawValue: $0.text) }
    }

    @Test("every reformat row has 30 cases, and every case names a row")
    func thirtyCasesPerCommand() {
        #expect(SpokenCommands.reformats.count == Reformat.allCases.count)
        for row in SpokenCommands.reformats {
            let count = cases.count { $0.commandID == row.id }
            #expect(count == 30, "\(row.id)")
        }
        let named = cases.allSatisfy { reformat($0) != nil }
        #expect(named)
    }

    @Test("each case writes its expected text, or refuses and writes nothing")
    func writesTheExpectedText() {
        for testCase in cases {
            guard let reformat = reformat(testCase) else { continue }
            let outcome = ReformatCommand.plan(reformat, of: testCase.text, in: testCase.destination)
            switch outcome {
            case .reformatted(let written):
                #expect(written == testCase.expected, "\(testCase.commandID): \(testCase.text)")
            case .refused:
                #expect(testCase.expected == nil, "\(testCase.commandID): \(testCase.text)")
            }
        }
    }

    @Test("every text a case expects holds the dictation's words in order, none added, dropped or changed")
    func keepsTheWordSequence() {
        for testCase in cases {
            guard let expected = testCase.expected else { continue }
            let words = { (text: String) in
                Draft(keepingLineBreaks: text).words.filter { !$0.isLayoutMark }.map {
                    WordShape($0.text).key
                }
                .filter { !$0.isEmpty }
            }
            let rate = WordErrorRate.measure(reference: words(testCase.text), hypothesis: words(expected))
            #expect(rate.errors == 0, "\(testCase.commandID): \(testCase.text)")
            #expect(expected != testCase.text)
        }
    }

    @Test("a change to a word is refused, so no reformat can rewrite one")
    func refusesAChangedWord() {
        #expect(ReformatCommand.keepsWords(of: "Buy milk. Call mum.", in: "- Buy milk.\n- CALL MUM."))
        #expect(
            !ReformatCommand.keepsWords(of: "Buy milk, eggs and bread.", in: "- Buy milk\n- eggs\n- bread"))
        #expect(!ReformatCommand.keepsWords(of: "Meet at five.", in: "Meet at six."))
    }

    @Test("a reformat is read only from the whole utterance, in any written form")
    func readsTheWholeUtterance() {
        for row in SpokenCommands.reformats {
            let phrase = row.words.joined(separator: " ")
            let wanted = Reformat(rawValue: row.text)
            for heard in [phrase, phrase.capitalized + ".", phrase.uppercased(), phrase + "!"] {
                #expect(ReformatCommand.reformat(heard: heard) == wanted, "\(heard)")
            }
            for heard in ["please \(phrase) now", "\(phrase) and send it", "I said \(phrase)"] {
                #expect(ReformatCommand.reformat(heard: heard) == nil, "\(heard)")
            }
        }
    }

    @Test("a reformat row is said only under the command key, so dictating its phrase never runs it")
    func neverRunsInDictation() {
        let keyed = SpokenCommands.reformats.allSatisfy { $0.isSaidUnderEditingKey }
        #expect(keyed)
        #expect(SpokenCommands.phrase(within: ["make", "that", "a", "list"])?.id == nil)
        #expect(SpokenCommands.phrase(within: ["make", "that", "one", "paragraph"])?.id == nil)
    }
}
