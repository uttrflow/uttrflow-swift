// One download of the speech model at a time, owned by the app so it outlives the window that asked for it.
public import UttrflowCore

/// Runs one install at a time for every onboarding window, and tells the app how it is going.
@MainActor
public final class SharedModelInstall: OnboardingModelInstaller {
    /// Called with every fraction the running install reports, whichever window started it.
    public var onProgress: ((Double) -> Void)?
    /// Called once when an install ends, with its failure or `nil`.
    public var onEnd: ((SpeechEngineError?) -> Void)?

    private let installer: any OnboardingModelInstaller
    private var running: Task<SpeechEngineError?, Never>?
    private var watchers: [Int: @Sendable (Double) -> Void] = [:]
    private var nextWatcher = 0

    /// Shares `installer` among every caller; it is never asked for two installs at once.
    public init(wrapping installer: any OnboardingModelInstaller) {
        self.installer = installer
    }

    /// Whether the model is on disk.
    public nonisolated var isInstalled: Bool { installer.isInstalled }

    /// Whether an install is running now.
    public var isRunning: Bool { running != nil }

    /// How many callers are waiting on the install in flight.
    var waiting: Int { watchers.count }

    /// Joins the install in flight or starts one; cancelling any caller stops it for all of them.
    public func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError) {
        let watcher = nextWatcher
        nextWatcher += 1
        watchers[watcher] = onProgress
        defer { watchers[watcher] = nil }
        let work = running ?? begin()
        let failure = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if let failure { throw failure }
    }

    /// Starts the one install, fanning its progress out in the order it was reported.
    private func begin() -> Task<SpeechEngineError?, Never> {
        let progress = AsyncStream<Double>.makeStream()
        let download = Task { [installer] () -> SpeechEngineError? in
            defer { progress.continuation.finish() }
            do throws(SpeechEngineError) {
                try await installer.install { progress.continuation.yield($0) }
                return nil
            } catch {
                return error
            }
        }
        let work = Task { [weak self] () -> SpeechEngineError? in
            await withTaskCancellationHandler {
                for await fraction in progress.stream { self?.report(fraction) }
                let failure = await download.value
                self?.end(failure)
                return failure
            } onCancel: {
                download.cancel()
            }
        }
        running = work
        return work
    }

    private func report(_ fraction: Double) {
        for watcher in watchers.values { watcher(fraction) }
        onProgress?(fraction)
    }

    private func end(_ failure: SpeechEngineError?) {
        running = nil
        onEnd?(failure)
    }
}
