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

    @Test("a second call for a window being walked waits for that walk instead of starting its own")
    func concurrentCallsShareOneWalk() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let calls = Counter()
        let walk: @Sendable () async -> Surroundings? = {
            await walks.bump()
            while await calls.count < 2 { await Task.yield() }
            return Self.around
        }
        let read: @Sendable () async -> Surroundings? = {
            await calls.bump()
            return await cache.surroundings(for: "notes", reading: walk)
        }

        async let first = read()
        async let second = read()
        let answers = await [first, second]

        #expect(await walks.count == 1)
        #expect(answers.allSatisfy { $0?.windowTitle == "Notes" })
    }

    @Test("Different windows can finish their own shared walks")
    func concurrentWindowsKeepTheirOwnWalks() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let notes: @Sendable () async -> Surroundings? = {
            await walks.bump()
            while await walks.count < 2 { await Task.yield() }
            return Self.around
        }
        let mail: @Sendable () async -> Surroundings? = {
            await walks.bump()
            while await walks.count < 2 { await Task.yield() }
            return Surroundings(windowTitle: "Mail", text: "a message")
        }

        async let notesResult = cache.surroundings(for: "notes", reading: notes)
        async let mailResult = cache.surroundings(for: "mail", reading: mail)
        let answers = await [notesResult, mailResult]

        #expect(await walks.count == 2)
        #expect(answers[0]?.windowTitle == "Notes")
        #expect(answers[1]?.windowTitle == "Mail")
    }

    @Test("Cancelling the only waiter cancels its walk and does not cache the late answer")
    func cancellingTheOnlyWaiterCancelsItsWalk() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let cancelledWalks = Counter()
        let walk: @Sendable () async -> Surroundings? = {
            await walks.bump()
            while !Task.isCancelled { await Task.yield() }
            await cancelledWalks.bump()
            return Self.around
        }
        let read = Task { await cache.surroundings(for: "notes", reading: walk) }

        #expect(await waitUntil { await walks.count == 1 })
        read.cancel()
        #expect(await read.value == nil)
        #expect(await waitUntil { await cancelledWalks.count == 1 })

        let next = await cache.surroundings(
            for: "notes",
            reading: {
                await walks.bump()
                return Self.around
            })
        #expect(next == Self.around)
        #expect(await walks.count == 2)
    }

    @Test("A successful surroundings lifetime starts when the walk finishes")
    func lifetimeStartsAtWalkCompletion() async {
        let cache = SuggestionContextCache()
        let walks = Counter()
        let start = ContinuousClock().now
        let walk: @Sendable () async -> Surroundings? = {
            await walks.bump()
            return Self.around
        }

        _ = await cache.surroundings(
            for: "notes", now: start, finishTime: { start + .milliseconds(1_500) }, reading: walk)
        _ = await cache.surroundings(
            for: "notes", now: start + .seconds(2), finishTime: { start + .seconds(2) }, reading: walk)

        #expect(await walks.count == 1)
    }
}

/// Counts the walks a test asked for.
private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}

/// Waits for an actor-backed condition without relying on a wall-clock sleep.
private func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<10_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}
