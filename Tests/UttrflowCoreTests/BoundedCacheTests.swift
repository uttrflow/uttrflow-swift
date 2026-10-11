import Foundation
import Testing

@testable import UttrflowCore

@Suite("A bounded cache")
struct BoundedCacheTests {
    @Test("A stored value comes back for its key and no other.")
    func storesAndReads() {
        var cache = BoundedCache<String, Int>(capacity: 4)
        cache.store(1, for: "one")
        #expect(cache.value(for: "one") == 1)
        #expect(cache.value(for: "two") == nil)
    }

    @Test("Past capacity the least recently used entry is dropped, and a read counts as use.")
    func evictsLeastRecentlyUsed() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache.store(1, for: "one")
        cache.store(2, for: "two")
        #expect(cache.value(for: "one") == 1)
        cache.store(3, for: "three")
        #expect(cache.count == 2)
        #expect(cache.value(for: "two") == nil)
        #expect(cache.value(for: "one") == 1)
        #expect(cache.value(for: "three") == 3)
    }

    @Test("Storing a key again replaces its value and makes it the most recently used.")
    func replacesInPlace() {
        var cache = BoundedCache<String, Int>(capacity: 2)
        cache.store(1, for: "one")
        cache.store(2, for: "two")
        cache.store(10, for: "one")
        cache.store(3, for: "three")
        #expect(cache.count == 2)
        #expect(cache.value(for: "one") == 10)
        #expect(cache.value(for: "two") == nil)
    }

    @Test("An entry stops being believed once its lifetime has passed, and the next store sweeps it.")
    func expires() {
        var cache = BoundedCache<String, Int>(capacity: 4, lifetime: .seconds(5))
        let now = ContinuousClock.now
        cache.store(1, for: "one", now: now)
        #expect(cache.value(for: "one", now: now + .seconds(4)) == 1)
        #expect(cache.value(for: "one", now: now + .seconds(6)) == nil)
        cache.store(2, for: "two", now: now + .seconds(6))
        #expect(cache.count == 1)
    }

    @Test("Removing one key and forgetting everything leave the chain usable.")
    func removesAndForgets() {
        var cache = BoundedCache<Int, Int>(capacity: 3)
        for index in 0..<3 { cache.store(index, for: index) }
        cache.remove(1)
        #expect(cache.count == 2)
        cache.store(3, for: 3)
        cache.store(4, for: 4)
        #expect(cache.value(for: 0) == nil)
        cache.forgetEverything()
        #expect(cache.count == 0)
        cache.store(5, for: 5)
        #expect(cache.value(for: 5) == 5)
    }

    @Test("A capacity of zero holds nothing.")
    func zeroCapacity() {
        var cache = BoundedCache<Int, Int>(capacity: 0)
        cache.store(1, for: 1)
        #expect(cache.count == 0)
    }

    @Test("Many uses stay within capacity and keep exactly the most recent keys.")
    func manyUses() {
        var cache = BoundedCache<Int, Int>(capacity: 8)
        for index in 0..<1_000 {
            cache.store(index, for: index % 13)
            _ = cache.value(for: (index * 7) % 13)
        }
        #expect(cache.count == 8)
    }

    /// The files that hold a bounded cache, written out so a new holder has to be seen.
    private static let holders: Set<String> = [
        "UttrflowContext/FieldReadBudget.swift", "UttrflowLocalModel/GeneratedConfidence.swift",
        "UttrflowLocalModel/JudgementCache.swift", "UttrflowLocalModel/PromptTokens.swift",
        "UttrflowPredict/VerdictCache.swift",
    ]

    /// One call a function makes on the way from Settings' reset down to a cache.
    private struct Step {
        let file: String
        let function: String
        let call: String
    }

    /// Settings' reset of every suggestion, which every chain below ends at.
    private static let settingsReset = [
        Step(
            file: "Uttrflow/Suggestion/PredictCorpus.swift", function: "forgetEverySuggestion()",
            call: "loop.forgetEverySuggestion()"),
        Step(
            file: "UttrflowUX/SettingsReset.swift", function: "remove(",
            call: "suggestions?.forgetEverySuggestion()"),
    ]

    /// The running loop's forget, down through the verifier.
    private static let loopReset =
        [
            Step(
                file: "Uttrflow/Suggestion/SuggestionCoordinator.swift",
                function: "forgetWhatThisLoopRemembers(", call: "verifier.forgetEverything(then:"),
            Step(
                file: "Uttrflow/Suggestion/SuggestionCoordinator.swift", function: "forgetEverySuggestion()",
                call: "forgetWhatThisLoopRemembers("),
        ] + settingsReset

    /// The local model's forget, reached through the verifier's scorer.
    private static func scorerReset(_ call: String) -> [Step] {
        [
            Step(
                file: "UttrflowLocalModel/MLXCandidateScorer.swift", function: "forgetEverything()",
                call: call),
            Step(
                file: "UttrflowPredict/Verifier.swift", function: "forgetEverything(then",
                call: "scoring?.forgetEverything()"),
        ] + loopReset
    }

    /// Each holder's chain of calls from its cache up to Settings' reset, written out so a broken link names itself.
    private static let resetPaths: [String: [Step]] = [
        "UttrflowPredict/VerdictCache.swift": [
            Step(
                file: "UttrflowPredict/VerdictCache.swift", function: "forgetEverything()",
                call: "held.forgetEverything()"),
            Step(
                file: "UttrflowPredict/Verifier.swift", function: "forgetEverything(then",
                call: "cache.forgetEverything()"),
        ] + loopReset,
        "UttrflowLocalModel/JudgementCache.swift": [
            Step(
                file: "UttrflowLocalModel/JudgementCache.swift", function: "forgetEverything()",
                call: "held.forgetEverything()")
        ] + scorerReset("judgementCache.forgetEverything()"),
        "UttrflowLocalModel/GeneratedConfidence.swift": [
            Step(
                file: "UttrflowLocalModel/GeneratedConfidence.swift", function: "forgetEverything()",
                call: "scores.forgetEverything()")
        ] + scorerReset("confidenceMemory.forgetEverything()"),
        "UttrflowLocalModel/PromptTokens.swift": [
            Step(
                file: "UttrflowLocalModel/PromptTokens.swift", function: "forgetEverything()",
                call: "$0.forgetEverything()")
        ] + scorerReset("prompt?.forgetEverything()"),
        "UttrflowContext/FieldReadBudget.swift": [
            Step(
                file: "UttrflowContext/FieldReadBudget.swift", function: "forgetEverything()",
                call: "rests.forgetEverything()"),
            Step(
                file: "UttrflowContext/FocusedFieldReader+System.swift", function: "forgetSlowFields()",
                call: "slowFields.forgetEverything()"),
            Step(
                file: "Uttrflow/Suggestion/PredictCorpus.swift", function: "forgetEverySuggestion()",
                call: "FocusedFieldReader.forgetSlowFields()"),
            Step(
                file: "UttrflowUX/SettingsReset.swift", function: "remove(",
                call: "suggestions?.forgetEverySuggestion()"),
        ],
    ]

    /// The package's `Sources` directory.
    private static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources")
    }

    /// The body of the first function whose declaration starts `func <function>`, braces matched, or nil.
    private static func body(of function: String, in text: String) -> Substring? {
        guard let declared = text.range(of: "func " + function),
            let open = text[declared.upperBound...].firstIndex(of: "{")
        else { return nil }
        var depth = 0
        for index in text[open...].indices {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" { depth -= 1 }
            if depth == 0 { return text[open...index] }
        }
        return nil
    }

    @Test("Every bounded cache is reached from Settings' reset by a chain of calls, each link still made.")
    func everyCacheIsReachedFromTheReset() throws {
        #expect(Set(Self.resetPaths.keys) == Self.holders)
        for (holder, steps) in Self.resetPaths {
            #expect(
                steps.last?.file == "UttrflowUX/SettingsReset.swift",
                "\(holder) stops short of Settings' reset")
            for step in steps {
                let text = try String(contentsOf: Self.sources.appending(path: step.file), encoding: .utf8)
                let body = Self.body(of: step.function, in: text)
                #expect(
                    body?.contains(step.call) == true,
                    "\(holder): \(step.file) \(step.function) no longer calls \(step.call)")
            }
        }
    }

    @Test("Every bounded cache is listed here and its holder forgets it on the reset path.")
    func everyCacheIsForgotten() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var found: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(sources.path.count + 1))
            guard relative != "UttrflowCore/Support/BoundedCache.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("BoundedCache<") else { continue }
            found.insert(relative)
            #expect(text.contains(".forgetEverything()"), "\(relative) never forgets its cache")
        }
        #expect(found == Self.holders)
    }
}
