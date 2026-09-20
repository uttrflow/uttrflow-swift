// Tests that one line costs one window walk, and one turn one context (#879).

import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@Suite("What a turn is told about the moment")
struct SuggestionContextCacheTests {
    static let around = Surroundings(windowTitle: "Notes", text: "a page of words")

    static func situation(_ application: String) -> GenerationSituation {
        GenerationSituation(application: application, field: "body")
    }

    @Test("the turn that built a context is given it again, and the next turn is not")
    func oneContextPerTurn() async {
        let cache = SuggestionContextCache()
        await cache.remember(Self.situation("Notes"), forTurn: 7)

        #expect(await cache.situation(forTurn: 7)?.application == "Notes")
        #expect(await cache.situation(forTurn: 8) == nil)
    }

    @Test("an unchanged window is walked once within the lifetime, and again after it")
    func oneWalkPerWindow() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let start = ContinuousClock().now
        let walk: @Sendable () async -> Surroundings? = {
            await walks.bump()
            return Self.around
        }

        _ = await cache.surroundings(for: "notes", now: start, reading: walk)
        _ = await cache.surroundings(for: "notes", now: start + .milliseconds(200), reading: walk)
        #expect(await walks.count == 1)

        _ = await cache.surroundings(for: "mail", now: start + .milliseconds(300), reading: walk)
        #expect(await walks.count == 2, "another window is another walk")

        _ = await cache.surroundings(
            for: "mail", now: start + SuggestionContextCache.surroundingsLifetime + .seconds(1),
            reading: walk)
        #expect(await walks.count == 3, "a stale walk is done again")
    }

    @Test("a walk that answered nothing is not kept")
    func timeoutsAreNotCached() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let start = ContinuousClock().now
        let nothing: @Sendable () async -> Surroundings? = {
            await walks.bump()
            return nil
        }

        _ = await cache.surroundings(for: "notes", now: start, reading: nothing)
        _ = await cache.surroundings(for: "notes", now: start, reading: nothing)

        #expect(await walks.count == 2)
    }
}

/// Counts the walks a test asked for.
private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
