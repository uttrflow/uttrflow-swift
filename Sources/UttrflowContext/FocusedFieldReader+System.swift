import AppKit
import ApplicationServices
import Foundation
import UttrflowCore

private import Synchronization

@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(
    _ element: AXUIElement, _ windowNumber: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// Reads the focused field once, for everything the suggestion loop needs. See `Docs/predict.md`.
public enum FocusedFieldReader {
    /// Its own thread, because these calls block until the other application answers.
    private static let queue = LatestOnlyQueue(label: "com.uttrflow.focused-field", qos: .userInitiated)

    /// Keeps armed-offer checks from replacing a full field read.
    private static let selectionQueue = LatestOnlyQueue(
        label: "com.uttrflow.focused-selection", qos: .utility)

    /// Holds the stable answers for one focused field and window only.
    private static let stableSnapshot = OneEntryCache<StableSnapshotKey, StableAnswers>()

    /// The process, field and window that give cached answers their identity.
    private struct StableSnapshotKey: @unchecked Sendable, Equatable {
        let processIdentifier: Int32
        let field: AXUIElement
        let window: AXUIElement?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.processIdentifier == rhs.processIdentifier && CFEqual(lhs.field, rhs.field)
                && sameWindow(lhs.window, rhs.window)
        }
    }

    /// The primary screen's top edge, cached because `NSScreen` is main-thread-only and this reads off it.
    private static let cachedPrimaryScreenMaxY = Mutex<CGFloat>(0)

    /// Whether the caches are already being kept up to date, so preparing twice observes once.
    @MainActor private static var prepared = false

    /// Fills the caches the off-main read depends on and keeps them filled. See `Docs/predict-ime.md`.
    @MainActor
    public static func prepare() {
        guard !prepared else { return }
        prepared = true
        CompositionProbe.startObservingInputSource()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { refreshPrimaryScreenMaxY() } }
        }
        refreshPrimaryScreenMaxY()
    }

    /// Asks AppKit where the primary screen ends, the one place in the read path that touches `NSScreen`.
    @MainActor
    private static func refreshPrimaryScreenMaxY() {
        let maxY = NSScreen.screens.first?.frame.maxY ?? 0
        cachedPrimaryScreenMaxY.withLock { $0 = maxY }
    }

    /// The frontmost application's identity, or `nil` when it is Uttrflow, whose AX tree must not be walked off the main actor.
    @MainActor
    public static func frontmostApp() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        // Some applications pad their name with control and direction marks, which would reach the model verbatim.
        let name = SurroundingsText.cleaned(app.localizedName ?? bundleIdentifier)
            .trimmingCharacters(in: .whitespaces)
        return FrontmostApp(
            processIdentifier: app.processIdentifier, bundleIdentifier: bundleIdentifier,
            name: name.isEmpty ? bundleIdentifier : name)
    }

    /// One reading, off the main thread, or `nil` when nothing usable is focused.
    public static func read() async -> FocusedFieldSnapshot? {
        let fullTreeGeneration = fullTree.generation
        // Identity is taken on the main actor first, because the blocking read below may not touch `NSWorkspace`.
        guard let app = await frontmostApp() else { return nil }
        // A field that stops answering costs the turn half a second at most, and no later turn waits behind it.
        return await queue.run(within: .milliseconds(500)) { isWanted in
            let reading = snapshot(app: app, while: isWanted)
            // A browser engine answers zero-size caret bounds until its full tree is on.
            if FullTreeSwitch.isNeeded(in: app.bundleIdentifier, after: reading) {
                fullTree.switchOn(
                    processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                    host: fullTreeHost(app.processIdentifier), generation: fullTreeGeneration)
            }
            return reading
        }
    }

    /// Reads only the focused element and selection, for the short time a suggestion is armed.
    public static func focusedSelection() async -> FocusedFieldSelectionRead {
        guard let app = await frontmostApp() else { return .unavailable }
        let read: FocusedFieldSelectionRead? = await selectionQueue.run(within: .milliseconds(250)) {
            isWanted in
            guard isWanted(), AXIsProcessTrusted(),
                let field = SurfaceProbe.focusedField(of: app.processIdentifier), isWanted()
            else { return .unavailable }
            _ = AXUIElementSetMessagingTimeout(field, elementTimeoutInSeconds)
            guard let range = SurfaceProbe.selectedRange(field), isWanted() else { return .unavailable }
            return .selection(
                FocusedFieldSelection(
                    processIdentifier: app.processIdentifier, elementHash: CFHash(field),
                    range: NSRange(location: range.location, length: range.length)))
        }
        return read ?? .timedOut
    }

    /// Cancels a selection poll when the offer is withdrawn.
    public static func cancelFocusedSelectionRead() { selectionQueue.invalidate() }

    /// Stops the current field read after its in-flight message, so a canceled turn sends no further questions.
    public static func cancelRead() { queue.invalidate() }

    /// The full Accessibility trees the suggestion loop turned on, kept so stopping the loop turns them off.
    private static let fullTree = FullTreeSwitch()

    /// Gives a restarted suggestion loop a generation newer than any queued release.
    package static func beginFullTreeSession() { fullTree.beginSession() }

    /// Runs releases in order, away from the caller, so an older release cannot undo a newer one.
    private static let fullTreeReleaseQueue = DispatchQueue(
        label: "com.uttrflow.full-tree-release", qos: .utility)

    /// Invalidates earlier reads now and turns off owned trees on the release queue, never on the caller's thread.
    public static func releaseFullTrees(except processIdentifier: Int32? = nil) {
        let generation = fullTree.invalidatePendingReads()
        fullTreeReleaseQueue.async {
            fullTree.switchOffEverything(
                except: processIdentifier, generation: generation, host: fullTreeHost)
        }
    }

    /// One application's full-tree switches, each message capped so a stalled application cannot hold the caller.
    private static func fullTreeHost(_ processIdentifier: Int32) -> FullTreeSwitch.Host {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, elementTimeoutInSeconds)
        return FullTreeSwitch.Host(
            read: { attribute in
                var value: AnyObject?
                guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success
                else { return nil }
                return (value as? NSNumber)?.boolValue
            },
            write: { attribute, isOn in
                AXUIElementSetAttributeValue(
                    application, attribute as CFString, isOn ? kCFBooleanTrue : kCFBooleanFalse) == .success
            })
    }

    /// Its own thread for the wider walk, so an application slow to describe its window never holds up a field read.
    private static let surroundingsQueue = LatestOnlyQueue(
        label: "com.uttrflow.surroundings", qos: .utility)

    /// How long one Accessibility call into another application may wait, since a stalled one would otherwise wait seconds.
    static let elementTimeoutInSeconds: Float = 0.05

    /// How long the turn waits for the wider walk before going on without it.
    private static let surroundingsAllowance = Duration.milliseconds(200)

    /// What is on screen around the focused field, or `nil` when nothing usable is focused or the wait ran out.
    public static func surroundings() async -> Surroundings? {
        guard let app = await frontmostApp() else { return nil }
        // The queue ticket reaches the collector so a cancelled turn stops between Accessibility messages.
        return await surroundingsQueue.run(within: surroundingsAllowance) { isWanted in
            surroundings(of: app, while: isWanted)
        }
    }

    /// The same read synchronously, for an application front or not, which is what a probe shows the operator.
    public static func surroundings(of app: FrontmostApp) -> Surroundings? {
        surroundings(of: app, while: { true })
    }

    /// The same synchronous read, stopping at its budget or when its queue ticket is invalidated.
    private static func surroundings(
        of app: FrontmostApp, while isWanted: @escaping @Sendable () -> Bool
    ) -> Surroundings? {
        // The budget covers the focus and window lookups too, and no message is sent once it is spent.
        let deadline = ContinuousClock.now + .milliseconds(Surroundings.budgetInMilliseconds)
        // A field with no window, or a window focused as a whole, has nothing around it worth a walk.
        guard isWanted(), AXIsProcessTrusted(), !slowFields.isQuiet(app.processIdentifier),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier), isWanted(),
            !slowFields.isResting(SlowFields.Key(process: app.processIdentifier, element: CFHash(field))),
            prepareMessage(field, deadline: deadline), isWanted(),
            let window = SurfaceProbe.element(field, kAXWindowAttribute),
            !CFEqual(field, window)
        else { return nil }
        let answers = AXNode(window, deadline: deadline).answers
        return Surroundings.collect(
            around: AXNode(field, deadline: deadline), in: AXElementTree(), windowTitle: answers.title,
            windowFrame: answers.frame, deadline: deadline, isWanted: isWanted
        )
    }

    /// Caps one Accessibility message to the walk's time left, or leaves it unsent once that time is spent.
    static func prepareMessage(_ element: AXUIElement, deadline: ContinuousClock.Instant?) -> Bool {
        prepareMessage(deadline: deadline, maximum: elementTimeoutInSeconds) { timeout in
            AXUIElementSetMessagingTimeout(element, timeout) == .success
        }
    }

    /// Applies one message timeout only while the deadline still has time to spend; no deadline leaves it as it is.
    static func prepareMessage(
        deadline: ContinuousClock.Instant?, maximum: Float, now: ContinuousClock.Instant = .now,
        applyTimeout: (Float) -> Bool
    ) -> Bool {
        guard let deadline else { return true }
        guard let timeout = WalkBudget(deadline: deadline).messageTimeoutInSeconds(maximum: maximum, now: now)
        else { return false }
        return applyTimeout(timeout)
    }

    /// The fields whose reads ran past their budget lately, which are left alone until their rest is over.
    static let slowFields = SlowFields()

    /// Forgets which fields ran slow, so a reset leaves no record of the fields this Mac has read.
    public static func forgetSlowFields() {
        slowFields.forgetEverything()
    }

    /// Lets an application quieted by a resting field be asked again, for a click, a switch or a key that may move focus.
    public static func focusMayHaveMoved() {
        slowFields.focusMayHaveMoved()
        fieldMayHaveChanged()
    }

    /// Drops the kept field and window answers, for a key or a scroll that can move the caret, grow the field or move its window.
    public static func fieldMayHaveChanged() {
        stableSnapshot.clear()
    }

    /// The same reading, synchronously, for the queue above and for the capability probe; the identity is read on main.
    static func snapshot(
        app: FrontmostApp, while isWanted: @Sendable () -> Bool = { true }
    ) -> FocusedFieldSnapshot? {
        let started = DispatchTime.now().uptimeNanoseconds
        let budget = FieldReadBudget.start()
        // An application whose focused field rests is not even asked for its focus, which can itself be the slow part.
        guard AXIsProcessTrusted(), !slowFields.isQuiet(app.processIdentifier),
            let field = SurfaceProbe.focusedField(of: app.processIdentifier)
        else { return nil }
        let slow = SlowFields.Key(process: app.processIdentifier, element: CFHash(field))
        // A field whose read ran over lately is asked nothing, so a heavy document does not stall its application every turn.
        guard !slowFields.isResting(slow) else { return nil }
        // Every question to the field gives up quickly, so a field that stops answering costs a moment, not the loop.
        _ = AXUIElementSetMessagingTimeout(field, elementTimeoutInSeconds)
        var ranOver = false
        // Checked before every question after the first: a superseded read stops, and one past its budget stops and rests the field.
        let goOn: () -> Bool = {
            guard isWanted() else { return false }
            guard budget.isSpent else { return true }
            ranOver = true
            return false
        }
        let answer = snapshot(
            of: AXNode(keepingTimeout: field), in: AXElementTree(),
            from: sources(for: app, field: field, started: started), while: goOn)
        if ranOver {
            slowFields.ranOver(slow)
        } else if answer != nil {
            slowFields.answered(slow)
        }
        return answer
    }

    /// The cache, the window server and the input source as one read of `field` asks them.
    private static func sources(
        for app: FrontmostApp, field: AXUIElement, started: UInt64
    ) -> SnapshotSources<AXNode> {
        let key = { (window: AXNode?) in
            StableSnapshotKey(processIdentifier: app.processIdentifier, field: field, window: window?.element)
        }
        // Taken before any question, so answers read across a key or a scroll are not kept for the next read.
        let generation = stableSnapshot.generation
        return SnapshotSources(
            app: app, decode: .capping, cached: { stableSnapshot.value(for: key($0)) },
            keep: { stableSnapshot.insert($0, for: key($1), readSince: generation) },
            elementHash: { CFHash($0.element) },
            windowNumber: { windowNumber(of: $0.element) },
            primaryScreenMaxY: { cachedPrimaryScreenMaxY.withLock { $0 } },
            inputSourceKind: CompositionProbe.inputSourceKind,
            elapsedMicroseconds: { Int((DispatchTime.now().uptimeNanoseconds - started) / 1000) })
    }

    /// The system window containing this field, which distinguishes same-app windows with identical AX fields.
    static func windowNumber(of field: AXUIElement) -> UInt32? {
        var number: CGWindowID = 0
        guard axUIElementGetWindow(field, &number) == .success else { return nil }
        return number
    }

    /// Whether both keys name the same window, including the absence of a window.
    private static func sameWindow(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let lhs?, let rhs?): CFEqual(lhs, rhs)
        default: false
        }
    }
}
