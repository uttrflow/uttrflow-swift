// Tests that corpus cases kept as data load whole, and that a broken file is refused with the case it breaks on.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

/// Checks the corpus file loader: the bundled files load, and every schema break names its case.
@Suite("Corpus files")
struct CorpusFileTests {
    private func decode(_ json: String) throws -> [EvaluationCase] {
        try CorpusFile.decode(Data(json.utf8), as: .oneLineField)
    }

    private func failure(_ json: String) -> CorpusFile.Failure? {
        do {
            _ = try decode(json)
            return nil
        } catch let failure as CorpusFile.Failure {
            return failure
        } catch {
            return nil
        }
    }

    @Test func theBundledOneLineFieldFileLoadsEveryCase() throws {
        let cases = try CorpusFile.load(.oneLineField)
        #expect(cases.count == 10)
        #expect(EvaluationCorpus.cases(in: .oneLineField) == cases)
        let context = try #require(cases.first?.context)
        #expect(context.accessibilityRole == "AXTextField")
        #expect(context.isMultiline == false)
    }

    /// A file that fails to load reads as an empty list, so every bundled file is loaded here by name.
    @Test func everyBundledFileLoadsAndEveryCaseInItReachesTheCorpus() throws {
        let names = CorpusFile.bundledNames
        #expect(names.count >= 13)
        let corpus = Dictionary(uniqueKeysWithValues: EvaluationCorpus.all.map { ($0.id, $0) })
        for name in names {
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            let category = try #require(
                EvaluationCase.Category(rawValue: parts[0]), "\(name) names no category")
            let cases = try CorpusFile.load(category, set: parts.count > 1 ? parts[1] : nil)
            #expect(!cases.isEmpty, "\(name) holds no case")
            for loaded in cases {
                #expect(
                    corpus[loaded.id] == loaded, "\(name) case \(loaded.id) is not in EvaluationCorpus.all")
            }
        }
    }

    @Test func aNamedSetIsReadFromItsOwnFile() throws {
        let cases = try CorpusFile.load(.notARequest, set: "hostileSelectedText")
        #expect(cases == EvaluationCorpus.hostileSelectedText)
        #expect(cases.allSatisfy { $0.category == .notARequest && $0.context.selectedText != nil })
    }

    @Test func aNoteIsReadAndClassesReachTheCase() throws {
        let json = #"""
            [{"id": "n", "note": "Why the case exists.", "spoken": "stop here", "expected": "Stop here.",
              "classes": ["sentence-boundaries"]}]
            """#
        let only = try #require(try decode(json).first)
        #expect(only.classes == [.sentenceBoundaries])
        #expect(
            only
                == EvaluationCase(
                    id: "n", category: .oneLineField, spoken: "stop here", expected: "Stop here.",
                    classes: [.sentenceBoundaries]))
    }

    /// The loader and the scorer share one reading, so a word the scorer finds in `expected` is never refused.
    @Test func aMustKeepWordIsReadAsTheScorerReadsIt() throws {
        let json =
            #"[{"id": "s", "spoken": "no I think so", "expected": "No, I think so.", "mustKeep": ["no"]}]"#
        let only = try #require(try decode(json).first)
        #expect(Scorer.lost(only.mustKeep, in: only.expected).isEmpty)
        #expect(Scorer.score(only.expected, against: only).keptEverythingRequired)
    }

    @Test func absentKeysTakeTheInitialiserDefaults() throws {
        let only = try #require(
            try decode(#"[{"id": "a", "spoken": "hello there", "expected": "Hello there."}]"#).first)
        #expect(
            only
                == EvaluationCase(
                    id: "a", category: .oneLineField, spoken: "hello there", expected: "Hello there."))
    }

    @Test func everyStatedKeyReachesTheCase() throws {
        let json = #"""
            [{"id": "b", "spoken": "ship it", "expected": "Ship it.", "language": "hi", "origin": "synthetic",
              "addedFor": 3777, "mustKeep": ["Ship"], "mustNotAdd": ["now"], "destination": "codeEditor",
              "mustBeginWith": "Ship", "mustEndWith": ".", "expectedExact": "Ship it.", "doubtful": ["ship"],
              "pausedAfter": [0], "context": {"bundleIdentifier": "com.example.notes", "precedingText": "Plan: "}}]
            """#
        let only = try #require(try decode(json).first)
        #expect(only.language == .hindi)
        #expect(only.origin == .synthetic)
        #expect(only.addedFor == 3777)
        #expect(only.mustKeep == ["Ship"])
        #expect(only.mustNotAdd == ["now"])
        #expect(only.destination == .codeEditor)
        #expect(only.mustBeginWith == "Ship")
        #expect(only.mustEndWith == ".")
        #expect(only.expectedExact == "Ship it.")
        #expect(only.doubtful == ["ship"])
        #expect(only.pausedAfter == [0])
        #expect(only.context.bundleIdentifier == "com.example.notes")
        #expect(only.context.precedingText == "Plan: ")
    }

    @Test func aDuplicateIdIsRefusedByName() {
        let json =
            #"[{"id": "x", "spoken": "a", "expected": "A"}, {"id": "x", "spoken": "b", "expected": "B"}]"#
        #expect(
            failure(json) == CorpusFile.Failure(category: .oneLineField, caseID: "x", reason: "duplicate id"))
    }

    @Test func aMustKeepWordMissingFromExpectedIsRefusedByName() {
        let json = #"[{"id": "k", "spoken": "use kubectl", "expected": "Use it.", "mustKeep": ["kubectl"]}]"#
        #expect(failure(json)?.caseID == "k")
    }

    @Test func aMisspeltKeyIsRefusedRatherThanDropped() {
        #expect(failure(#"[{"id": "m", "spoken": "a", "expected": "A", "mustEndwith": "."}]"#) != nil)
        #expect(
            failure(#"[{"id": "m", "spoken": "a", "expected": "A", "context": {"role": "AXTextField"}}]"#)
                != nil)
    }

    @Test func aMissingRequiredKeyOrBadLanguageIsRefused() {
        #expect(failure(#"[{"id": "r", "spoken": "a"}]"#) != nil)
        #expect(failure(#"[{"id": "l", "spoken": "a", "expected": "A", "language": "4"}]"#)?.caseID == "l")
        #expect(failure(#"[{"id": "", "spoken": "a", "expected": "A"}]"#) != nil)
    }
}
