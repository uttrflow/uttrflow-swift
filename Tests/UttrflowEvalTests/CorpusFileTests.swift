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
