// The entry point.

import AppKit
import Foundation
import OSLog
import UttrflowCore
import UttrflowLocalModel
import UttrflowPipeline
import UttrflowPredict

/// The app, owning nothing but the objects it wires together.
@main
enum UttrflowApp {
    static func main() {
        // Before any model or keyboard monitor exists, so a second copy never builds either.
        guard let instance = claimTheOnlyInstance() else { exit(0) }
        let application = NSApplication.shared
        // One model both validates a remembered suggestion and invents one where there is none; its weights are fetched when the feature is first built, never at launch.
        let model = IdleReleasingModel(
            model: MLXCandidateScorer(model: .gemma3),
            idleAfter: IdleRelease.window(physicalMemory: ProcessInfo.processInfo.physicalMemory))
        // Every use is discretionary: utility priority, and no pass in Low Power Mode or under thermal pressure.
        let generating = DiscretionaryGenerator(
            model, mayRun: { EnergyConditions.current().allowsDiscretionaryWork })
        let scoring = DiscretionaryModel(
            model, mayRun: { EnergyConditions.current().allowsDiscretionaryWork })
        let delegate = AppDelegate(
            scoring: scoring, generating: generating,
            prepareModel: { onProgress in try await scoring.prepare(onProgress: onProgress) },
            releaseModel: { await scoring.release() })
        application.delegate = delegate
        // A reload that finds the weights gone asks for them again in Settings rather than fetching them unasked.
        Task { [weak delegate] in
            await scoring.whenReloadFails { Task { @MainActor in delegate?.suggestionModelWentMissing() } }
        }
        // Regular, not accessory: Uttrflow has a Dock icon and its window opens at launch.
        application.setActivationPolicy(.regular)
        // A regular app with no main menu loses ⌘C, ⌘V, ⌘A and ⌘Z in every text field.
        application.mainMenu = MainMenu.build()
        // The lock lives as long as the run loop, which is the life of the process.
        withExtendedLifetime(instance) { application.run() }
    }

    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "launch")

    /// The lock to keep, `nil` after handing off to a copy already running, or no lock when the file cannot be locked.
    private static func claimTheOnlyInstance() -> SingleInstanceLock?? {
        let file = SingleInstanceLock.defaultFile()
        var outcome = SingleInstanceLock.acquire(at: file)
        // No other copy is visible, so the holder is one that is quitting, as it does while an update relaunches.
        if case .heldElsewhere = outcome, otherInstance() == nil {
            outcome = SingleInstanceLock.acquire(at: file, waitingUpTo: .seconds(5))
        }
        switch outcome {
        case .acquired(let lock):
            return .some(lock)
        case .unavailable:
            log.error("Could not take the single-instance lock; launching unguarded")
            return .some(nil)
        case .heldElsewhere:
            log.notice("Another copy is running; handing off to it and exiting")
            if let running = otherInstance() { handOff(to: running) }
            return nil
        }
    }

    /// Another running process with this bundle identifier, from whatever path it was started.
    private static func otherInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Brings the running copy forward and asks it to reopen, which shows its window when none is visible.
    private static func handOff(to running: NSRunningApplication) {
        guard let bundle = running.bundleURL else {
            running.activate()
            return
        }
        let done = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
            if error != nil { running.activate() }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
    }
}
