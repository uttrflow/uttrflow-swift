import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Prose dictated into a technical app comes out as the same words, with no notation added, on every engine.
@Suite("The abstention corpus")
struct AbstentionCorpusTests {
    /// What went wrong with one output: the words it changed and the symbols it added; empty means it abstained.
    static func misfires(in output: String, for testCase: EvaluationCase) -> [String] {
        let edge = CharacterSet(charactersIn: ".,?!")
        let written = output.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: edge)
        }
        let spoken = testCase.spoken.split(separator: " ").map(String.init)
        var found: [String] = []
        if written.count != spoken.count {
            found.append("has \(written.count) words for \(spoken.count)")
        }
        for (word, said) in zip(written, spoken) where !Self.sameWord(word, said) {
            found.append("wrote \"\(word)\" for \"\(said)\"")
        }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(edge)
            .union(CharacterSet(charactersIn: "'"))
        let added = output.unicodeScalars.filter { !allowed.contains($0) }.map(String.init)
        if !added.isEmpty { found.append("added \(added)") }
        return found
    }

    /// The same word, letting only its first letter change case as a sentence start does.
    private static func sameWord(_ written: String, _ said: String) -> Bool {
        written.dropFirst() == said.dropFirst()
            && written.prefix(1).lowercased() == said.prefix(1).lowercased()
    }

    @Test("holds every family at every region", arguments: AbstentionFamily.allCases)
    func coversEveryRegion(family: AbstentionFamily) {
        let cases = EvaluationCorpus.abstention.filter { $0.destination == family.destination }
        #expect(cases.count == family.sentences.count * family.regions.count)
        #expect(family.sentences.count >= 10)
    }

    /// Source sentences the rules still turn into notation at a code or string caret, a baseline that only shrinks.
    static let knownMisfires: Set<String> = Set(
        [
            "arrow-sign", "close-brace", "close-bracket", "close-paren", "close-parenthesis",
            "colon-semicolon",
            "comma-butterfly", "flour-equals", "open-brace", "open-bracket", "open-paren", "open-parenthesis",
            "star-dot", "underscore",
        ].flatMap { slug in ["code", "string"].map { "abstain-source-\(slug)-\($0)" } }
            + ["abstain-source-underscore-comment", "abstain-source-underscore-docstring"])

    @Test("leaves every word as spoken and adds no symbol under the rules, outside the known misfires")
    func rulesAbstain() async throws {
        var misfired: Set<String> = []
        for testCase in EvaluationCorpus.abstention {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            if !Self.misfires(in: result.text, for: testCase).isEmpty { misfired.insert(testCase.id) }
        }
        let new = misfired.subtracting(Self.knownMisfires).sorted()
        let fixed = Self.knownMisfires.subtracting(misfired).sorted()
        #expect(new.isEmpty, "new misfires: \(new)")
        #expect(fixed.isEmpty, "these now abstain, so leave the baseline: \(fixed)")
    }

    @Test("has a prose case for every notation entry in the spoken-command table")
    func everyNotationEntryHasProse() {
        let spoken = EvaluationCorpus.abstention.map { " \($0.spoken) " }
        for row in SpokenCommands.codeSymbols {
            let phrase = " \(row.words.joined(separator: " ")) "
            #expect(spoken.contains { $0.contains(phrase) }, "\(row.id) has no prose case")
        }
    }

    @Test("names its cases' misfires word by word")
    func misfiresAreNamed() throws {
        let testCase = try #require(EvaluationCorpus.abstention.first { $0.spoken.contains(" dot ") })
        #expect(Self.misfires(in: "The star of the show put a dot on the map.", for: testCase).isEmpty)
        #expect(!Self.misfires(in: "The star of the show put a . on the map.", for: testCase).isEmpty)
        #expect(!Self.misfires(in: "The * of the show put a dot on the map.", for: testCase).isEmpty)
    }
}
