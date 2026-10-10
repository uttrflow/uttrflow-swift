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

    /// The technical families the corpus covers, each the second part of its case ids.
    static let families = ["sql", "source", "shell", "json", "markup", "formula", "url"]

    /// Notation words a speaker also uses as English, each in some sentence of every family.
    static let ambiguousWords = [
        "star", "dot", "dash", "equals", "arrow", "period", "select", "from", "and", "slash", "open", "close",
    ]

    /// Each family's sentences keyed by the region they are dictated at, the region being the id's last part.
    static func sentencesByRegion(of family: String) -> [String: Set<String>] {
        var regions: [String: Set<String>] = [:]
        for testCase in EvaluationCorpus.abstention where testCase.id.hasPrefix("abstain-\(family)-") {
            let region = String(testCase.id.split(separator: "-").last ?? "")
            regions[region, default: []].insert(testCase.spoken)
        }
        return regions
    }

    @Test("names only its families, in its ids")
    func namesItsFamilies() {
        let named = EvaluationCorpus.abstention.map { $0.id.split(separator: "-").dropFirst().first ?? "" }
        #expect(Set(named.map(String.init)) == Set(Self.families))
    }

    @Test("dictates at least ten sentences of each family at every one of its regions", arguments: families)
    func coversEveryRegion(family: String) {
        let regions = Self.sentencesByRegion(of: family)
        let sentences = regions.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        #expect(sentences.count >= 10)
        for (region, said) in regions {
            let missing = sentences.subtracting(said).sorted()
            #expect(missing.isEmpty, "\(family) misses \(missing) at \(region)")
        }
    }

    @Test("uses every ambiguous notation word in each family", arguments: families)
    func usesEveryAmbiguousWord(family: String) {
        let sentences = Self.sentencesByRegion(of: family).values.joined()
        let words = Set(sentences.flatMap { $0.split(separator: " ") })
        for word in Self.ambiguousWords {
            #expect(words.contains(Substring(word)), "\(family) never says \"\(word)\"")
        }
    }

    @Test("expects the plain-prose result, which is what a document writes for the same words")
    func expectsPlainProse() async throws {
        let document = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.apple.Notes", documentName: "Plan")
        for testCase in EvaluationCorpus.abstention {
            let inDocument = EvaluationCase(
                id: testCase.id, category: .technical, spoken: testCase.spoken, expected: testCase.expected,
                context: document, destination: .document)
            let plain = try await RuleBasedTransformer().transform(inDocument.transformationRequest()).text
            #expect(plain == testCase.expected, "\(testCase.id) is written \"\(plain)\" in a document")
        }
    }

    /// Cases the rules still turn into notation, each under its open issue; a baseline that only shrinks.
    static let knownMisfires: Set<String> = []

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
        let testCase = try #require(
            EvaluationCorpus.abstention.first { $0.id == "abstain-source-star-dot-code" })
        #expect(Self.misfires(in: "The star of the show put a dot on the map.", for: testCase).isEmpty)
        #expect(!Self.misfires(in: "The star of the show put a . on the map.", for: testCase).isEmpty)
        #expect(!Self.misfires(in: "The * of the show put a dot on the map.", for: testCase).isEmpty)
    }
}
