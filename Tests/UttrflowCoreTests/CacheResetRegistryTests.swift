import Foundation
import Testing

@Suite("Every bounded cache is reachable from the reset path")
struct CacheResetRegistryTests {
    /// One cache holder, and the file and call that reach its `forgetEverything` from the reset path.
    private struct Entry {
        let holder: String
        let holderForgets: String
        let reset: String
        let resetCalls: String
    }

    /// Each file that holds a `BoundedCache`; a new holder is added here or the test fails.
    private static let registry = [
        Entry(
            holder: "UttrflowPredict/VerdictCache.swift",
            holderForgets: "held.forgetEverything()",
            reset: "UttrflowPredict/VerificationSession.swift",
            resetCalls: "cache.forgetEverything()"),
        Entry(
            holder: "UttrflowLocalModel/JudgementCache.swift",
            holderForgets: "held.forgetEverything()",
            reset: "UttrflowLocalModel/MLXCandidateScorer+Lifecycle.swift",
            resetCalls: "judgementCache.forgetEverything()"),
        Entry(
            holder: "UttrflowLocalModel/GeneratedConfidence.swift",
            holderForgets: "scores.forgetEverything()",
            reset: "UttrflowLocalModel/MLXCandidateScorer+Lifecycle.swift",
            resetCalls: "confidenceMemory.forgetEverything()"),
        Entry(
            holder: "UttrflowLocalModel/PromptTokens.swift",
            holderForgets: "$0.forgetEverything()",
            reset: "UttrflowLocalModel/MLXCandidateScorer+Lifecycle.swift",
            resetCalls: "prompt?.forgetEverything()"),
        Entry(
            holder: "UttrflowContext/FieldReadBudget.swift",
            holderForgets: "state.rests.forgetEverything()",
            reset: "UttrflowContext/FocusedFieldReader+System.swift",
            resetCalls: "slowFields.forgetEverything()"),
    ]

    /// The privacy reset entry points that the registry's reset files must in turn be reached from.
    private static let resetEntryPoints = [
        (file: "Uttrflow/Suggestion/PredictCorpus.swift", call: "FocusedFieldReader.forgetSlowFields()"),
        (
            file: "Uttrflow/Suggestion/SuggestionCoordinator.swift",
            call: "verifier.forgetEverything(then: clearingCorpus)"
        ),
        (file: "UttrflowPredict/Verifier.swift", call: "scoring?.forgetEverything()"),
        (file: "UttrflowPredict/Verifier.swift", call: "session.forgetEverything()"),
    ]

    private static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: sources.appending(path: path), encoding: .utf8)
    }

    @Test("Every file that declares a bounded cache is in the registry.")
    func registryListsEveryHolder() throws {
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)
        let enumerator = try #require(files)
        var holders: Set<String> = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let relative = String(file.path.dropFirst(Self.sources.path.count + 1))
            if relative == "UttrflowCore/Support/BoundedCache.swift" { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("BoundedCache<") { holders.insert(relative) }
        }
        #expect(holders == Set(Self.registry.map(\.holder)))
    }

    @Test("Each holder forgets its cache and its reset file calls the holder.")
    func everyCacheIsReachable() throws {
        for entry in Self.registry {
            let holder = try Self.text(entry.holder)
            #expect(holder.contains(entry.holderForgets), "\(entry.holder) does not forget its cache")
            let reset = try Self.text(entry.reset)
            #expect(reset.contains(entry.resetCalls), "\(entry.reset) does not reach \(entry.holder)")
        }
    }

    @Test("The reset files are themselves called from the privacy reset.")
    func resetFilesAreReached() throws {
        for point in Self.resetEntryPoints {
            #expect(try Self.text(point.file).contains(point.call), "\(point.file) lost \(point.call)")
        }
    }
}
