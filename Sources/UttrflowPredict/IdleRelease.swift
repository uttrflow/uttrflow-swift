// Lets a loaded model go when nothing has asked for it in a while, and loads it again when something does.

import Foundation
import UttrflowCore

/// A model that can be loaded and let go, which is all an idle release needs of one.
public protocol ReleasableModel: CandidateScoring, CandidateGenerating {
    /// Loads the weights, reporting how far along the fetch is.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Loads the weights again from disk only, throwing rather than fetching anything, since nobody asked for a download.
    func reload() async throws
    /// Drops the weights.
    func release() async
}

/// How long a suggestion model may sit unasked before it is let go. See `Docs/performance-suggestions.md`.
public enum IdleRelease {
    /// The window on a Mac with at least 16 GB.
    public static let roomy = Duration.seconds(600)
    /// The window on a Mac with less.
    public static let tight = Duration.seconds(180)

    /// The window for a Mac with this much physical memory, in bytes.
    public static func window(physicalMemory: UInt64) -> Duration {
        physicalMemory < 16 * 1_073_741_824 ? tight : roomy
    }
}

/// How a reload that follows an idle release is going.
public enum IdleReload: Sendable, Equatable {
    /// A query finds the model let go and starts loading it again.
    case started
    /// The reload is done and the model can answer.
    case finished
    /// The reload ends without a model that can answer.
    case failed
}

/// Holds a model only while something keeps asking for it; a release by the caller is never undone by a query.
public actor IdleReleasingModel<Model: ReleasableModel>: ReleasableModel {
    private let model: Model
    private let idleAfter: Duration
    private let clock: any Clock<Duration>
    private let elapsed: @Sendable () -> Duration
    /// Whether the caller wants the model, which only ``prepare(onProgress:)`` and ``release()`` change.
    private var isWanted = false
    /// Whether the weights are loaded or loading, so a query does not start a second load.
    private var isHeld = false
    /// The latest prepare, release or reload; a step that finishes under an older one changes nothing.
    private var generation = 0
    private var lastAsked = Duration.zero
    /// The latest load or release, which the next one waits for so they land in the order they were asked.
    private var work: Task<Void, Never>?
    /// Stops the load in flight, so a release reads no more weights and fetches no more bytes for it.
    private var stopLoading: @Sendable () -> Void = {}
    private var watch: Task<Void, Never>?
    /// Receives each step of a reload that follows an idle release.
    private let onReload: @Sendable (IdleReload) -> Void
    /// Told when a reload finds the weights gone from disk, so the app can ask for them again.
    private var onReloadFailed: @Sendable () -> Void = {}

    public init(
        model: Model, idleAfter: Duration, clock: any Clock<Duration> = ContinuousClock(),
        onReload: @escaping @Sendable (IdleReload) -> Void = { _ in }
    ) {
        self.model = model
        self.idleAfter = idleAfter
        self.clock = clock
        self.elapsed = stopwatch(from: clock)
        self.onReload = onReload
    }

    /// Whether the weights are loaded or on their way; internal so a test can read it.
    var holdsTheModel: Bool { isHeld }

    public func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        isWanted = true
        isHeld = true
        lastAsked = elapsed()
        let asked = advance()
        let previous = work
        let model = model
        let step = Task { () -> (any Error)? in
            await previous?.value
            do {
                try await model.prepare(onProgress: onProgress)
                return nil
            } catch {
                return error
            }
        }
        work = Task { _ = await step.value }
        stopLoading = { step.cancel() }
        // A caller that gives up on the load stops it, rather than leaving it to read every weight.
        if let error = await withTaskCancellationHandler(
            operation: { await step.value }, onCancel: { step.cancel() })
        {
            await settle(asked)
            throw error
        }
        guard isCurrent(asked) else { return }
        watchForIdle()
    }

    /// Loads the weights again from disk only, as a query's reload does.
    public func reload() async throws {
        try await model.reload()
    }

    /// Sets what to tell when a query's reload fails, which is how the app learns the model must be fetched again.
    public func whenReloadFails(_ handler: @escaping @Sendable () -> Void) {
        onReloadFailed = handler
    }

    public func release() async {
        isWanted = false
        isHeld = false
        advance()
        watch?.cancel()
        // The load in flight stops at its next safe point, so the release waits for no download and no read.
        stopLoading()
        stopLoading = {}
        let previous = work
        let model = model
        let step = Task {
            await previous?.value
            await model.release()
        }
        work = step
        await step.value
    }

    /// Lets a later query reload weights after memory pressure without loading them now.
    public func allowReloadAfterRelease() {
        guard !isHeld else { return }
        isWanted = true
    }

    /// Whether the model can answer now, loading it again in the background when an idle release let it go.
    public var isReady: Bool {
        get async {
            lastAsked = elapsed()
            if await model.isReady { return true }
            if isWanted, !isHeld { reloadInBackground() }
            return false
        }
    }

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        lastAsked = elapsed()
        return try await model.completions(for: typed, in: situation)
    }

    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        lastAsked = elapsed()
        return try await model.alternatives(for: typed, in: situation, excluding: leader)
    }

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        lastAsked = elapsed()
        return await model.logLikelihood(of: candidate, following: context)
    }

    public func confidence(ofGenerated line: String) async -> Double? {
        await model.confidence(ofGenerated: line)
    }

    /// Clears the wrapped scorer's retained candidates and confidences.
    public func forgetEverything() async {
        await model.forgetEverything()
    }

    /// Lets the model go when it has not been asked for in the window; returns whether it is still held.
    @discardableResult
    func releaseIfIdle(at now: Duration) async -> Bool {
        guard isHeld else { return false }
        guard isWanted, now - lastAsked >= idleAfter else { return true }
        isHeld = false
        advance()
        let previous = work
        let model = model
        let step = Task {
            await previous?.value
            await model.release()
        }
        work = step
        await step.value
        return false
    }

    /// The idle watch, which ends once it lets the model go; internal so a test can wait for it.
    var watching: Task<Void, Never>? { watch }

    /// The background load a query starts; internal so a test can wait for it.
    var pendingWork: Task<Void, Never>? { work }

    private func reloadInBackground() {
        isHeld = true
        let asked = advance()
        onReload(.started)
        let previous = work
        let model = model
        let reload = Task { [weak self] in
            await previous?.value
            do {
                // Never a download: a query is typing, and only the person may start a fetch.
                try await model.reload()
                await self?.loaded(asked)
            } catch {
                await self?.reloadFailed(asked)
            }
        }
        work = reload
        stopLoading = { reload.cancel() }
    }

    /// Settles a reload that failed and says so, unless something newer was asked for since.
    private func reloadFailed(_ asked: Int) async {
        guard isCurrent(asked) else { return }
        onReloadFailed()
        await settle(asked)
        guard isCurrent(asked) else { return }
        onReload(.failed)
    }

    /// Whether no prepare, release or reload has been asked for since this one.
    private func isCurrent(_ asked: Int) -> Bool { generation == asked }

    /// Starts a new generation and returns it, so every step already queued knows it is stale.
    @discardableResult
    private func advance() -> Int {
        generation += 1
        return generation
    }

    /// Watches a background load that succeeded, unless something newer was asked for since.
    private func loaded(_ asked: Int) {
        guard isCurrent(asked) else { return }
        onReload(.finished)
        watchForIdle()
    }

    /// Takes the hold from what the model reports after a failed load, if that load is still the latest.
    private func settle(_ asked: Int) async {
        guard isCurrent(asked) else { return }
        let ready = await model.isReady
        guard isCurrent(asked) else { return }
        isHeld = ready
        if ready { watchForIdle() }
    }

    /// Checks for idleness once each time the window could have run out, for as long as the model is held.
    private func watchForIdle() {
        watch?.cancel()
        let first = idleAfter
        watch = Task { [weak self] in
            var wait = first
            while !Task.isCancelled {
                try? await self?.clock.sleep(for: wait)
                guard !Task.isCancelled, let self, await releaseIfIdle(at: elapsed()) else { return }
                wait = await timeUntilIdle(at: elapsed())
            }
        }
    }

    /// How long until the window runs out if nothing asks again, never less than a tenth of it.
    func timeUntilIdle(at now: Duration) -> Duration {
        max(idleAfter - (now - lastAsked), idleAfter / 10)
    }
}
