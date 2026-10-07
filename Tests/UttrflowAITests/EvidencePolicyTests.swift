import Foundation
import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("One answer for unknown confidence", .bug(id: 6206))
struct EvidencePolicyTests {
    private static let unscored = Draft(text: "their going to the bank")
    private static let scored = Draft(
        words: [Draft.Word(text: "their", heard: "their", confidence: 0.2)], confidencesAreReal: true)

    @Test("doubtful-word candidates offer nothing")
    func doubtfulWords() {
        #expect(EvidencePolicy.unscored(Self.unscored, in: .doubtfulWords) == .offerNothing)
    }

    @Test("the meaning guard accepts the rewrite")
    func meaningGuard() {
        #expect(EvidencePolicy.unscored(Self.unscored, in: .meaningGuard) == .acceptRewrite)
    }

    @Test("the rules-alone route sends the text to the model")
    func rulesAlone() {
        #expect(EvidencePolicy.unscored(Self.unscored, in: .rulesAlone) == .askModel)
    }

    @Test("dictionary spellings drop the word scores")
    func dictionarySpellings() {
        #expect(EvidencePolicy.unscored(Self.unscored, in: .dictionarySpellings) == .dropScores)
    }

    @Test("the explanation says the words were not scored")
    func explanation() {
        #expect(EvidencePolicy.unscored(Self.unscored, in: .explanation) == .sayNotScored)
    }

    @Test("real scores are read by every layer")
    func realScoresAreRead() {
        for layer in EvidencePolicy.Layer.allCases {
            #expect(EvidencePolicy.unscored(Self.scored, in: layer) == nil, "\(layer)")
        }
    }

    @Test("no source outside Draft and the policy reads confidencesAreReal")
    func flagLivesInThePolicyAlone() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let owners: Set = ["Draft.swift", "EvidencePolicy.swift"]
        var offenders: [String] = []
        for case let file as URL in files
        where file.pathExtension == "swift" && !owners.contains(file.lastPathComponent) {
            if try String(contentsOf: file, encoding: .utf8).contains("confidencesAreReal") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty)
    }
}
