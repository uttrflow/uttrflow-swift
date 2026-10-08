public import UttrflowCore

import Foundation
private import os
private import Synchronization

/// One running application, reduced to what a context needs to know about it.
public struct FrontmostApplication: Sendable, Equatable {
    /// The app as the user knows it, or nothing when it will not name itself.
    public let name: String?
    /// The app's bundle identifier, absent for anything running unbundled.
    public let bundleIdentifier: String?
    /// Addresses the app for the Accessibility read, and names an unbundled Uttrflow to itself.
    public let processIdentifier: Int32

    public init(name: String? = nil, bundleIdentifier: String? = nil, processIdentifier: Int32) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

/// What the focused window says about itself, each half optional on its own. See `Docs/context-accessibility.md`.
public struct FocusedWindow: Sendable, Equatable {
    /// The window's own title, which names the document, the page or the channel.
    public let title: String?
    /// What is selected in the focused field, uncut here and capped before it reaches a prompt.
    public let selectedText: String?
    /// Text before the caret, already cut to ``InsertionPoint/precedingLimit``; `nil` when the field will not say.
    public let precedingText: String?
    /// Text after the selection, already cut to ``InsertionPoint/followingLimit``; `nil` when the field will not say.
    public let followingText: String?
    /// Whether the focused field hides what is typed, judged before its value is read.
    public let isSecure: Bool
    /// The focused field's Accessibility role, when reported.
    public let accessibilityRole: String?
    /// Whether Accessibility says the field accepts multiple lines.
    public let isMultiline: Bool?
    /// What the focused field calls itself, never read from a secure field.
    public let fieldLabel: String?
    /// Whether an input method holds unconfirmed text in the field, which both caret sides already leave out.
    public let isComposing: Bool
    /// The focused field itself, read even when it is secure since it carries no text.
    public let field: FieldIdentity?
    /// Which rung of the read ladder gives the caret text, or `nil` while the read has not reached it.
    public let readRung: ContextReadRung?
    /// Why the read ended without the caret text, or `nil` while it has not ended or when it reached the text.
    let unavailable: ContextUnavailableReason?

    public init(
        title: String? = nil, selectedText: String? = nil, precedingText: String? = nil,
        followingText: String? = nil, isSecure: Bool = false,
        accessibilityRole: String? = nil, isMultiline: Bool? = nil, fieldLabel: String? = nil,
        isComposing: Bool = false, field: FieldIdentity? = nil, readRung: ContextReadRung? = nil,
        unavailable: ContextUnavailableReason? = nil
    ) {
        self.unavailable = unavailable
        self.isComposing = isComposing
        self.title = title
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
        self.isSecure = isSecure
        self.accessibilityRole = accessibilityRole
        self.isMultiline = isMultiline
        self.fieldLabel = fieldLabel
        self.field = field
        self.readRung = readRung
    }
}

/// Reports what the user is looking at, never making them wait for it. See `Docs/context-accessibility.md`.
public final class MacContextEngine: ContextEngine, Sendable {
    /// How long a whole reading may take before the dictation stops waiting. See `Docs/context-budget.md`.
    public static let budget = Duration.milliseconds(100)

    /// Characters of selected text kept, so a selected document cannot crowd out the transcript. See `Docs/context-budget.md`.
    public static let selectedTextLimit = 512

    /// ``budget`` in seconds, converted once because a rounded-down zero would silently uncap the read.
    static let budgetInSeconds = Float(budget.inSeconds)

    /// The budget left for the next message, never zero, which Accessibility reads as its own long default.
    static func timeLeft(since started: ContinuousClock.Instant, now: ContinuousClock.Instant = .now) -> Float
    {
        max(Float((budget - (now - started)).inSeconds), minimumMessageTimeout)
    }

    /// The shortest timeout a message is given once the budget is spent, by which time the read has been abandoned.
    static let minimumMessageTimeout: Float = 0.001

    /// Marks a cut selection, so a model does not take the fragment for a finished sentence.
    static let truncationMarker = "…"

    private let readFrontmostApplication: @Sendable () async -> FrontmostApplication?
    private let readFocusOwner: @Sendable (FrontmostApplication) async -> FrontmostApplication?
    private let readFocusedWindow: @Sendable (FrontmostApplication, FocusedWindowSink) async -> Void
    private let ownBundleIdentifier: String?
    private let ownProcessIdentifier: Int32
    private let clock: any Clock<Duration>

    /// The latest read and the last other application, changed under one lock so old reads cannot replace it.
    private struct AppMemory {
        var requestNumber: UInt64 = 0
        var appBehind: FrontmostApplication?
        /// The last application macOS reported activating, Uttrflow included.
        var lastActivated: FrontmostApplication?
    }

    private let memory = Mutex(AppMemory())

    /// What keeps the activation subscription open; boxed so it can be filled once `self` is fully built.
    private let activationToken = Mutex<(any Sendable)?>(nil)

    /// Substitutes the readings and the activation feed; `MacContextEngine+System.swift` wires up the real ones.
    init(
        readFrontmostApplication: @escaping @Sendable () async -> FrontmostApplication?,
        readFocusOwner: @escaping @Sendable (FrontmostApplication) async -> FrontmostApplication? = { _ in nil
        },
        readFocusedWindow: @escaping @Sendable (FrontmostApplication, FocusedWindowSink) async -> Void,
        ownBundleIdentifier: String?,
        ownProcessIdentifier: Int32,
        clock: any Clock<Duration> = ContinuousClock(),
        observeActivations: (@escaping @Sendable (FrontmostApplication) -> Void) -> any Sendable = { _ in () }
    ) {
        self.readFrontmostApplication = readFrontmostApplication
        self.readFocusOwner = readFocusOwner
        self.readFocusedWindow = readFocusedWindow
        self.ownBundleIdentifier = ownBundleIdentifier
        self.ownProcessIdentifier = ownProcessIdentifier
        self.clock = clock
        // Every stored property now has a value, so `self` is safe to capture from here on.
        let token = observeActivations { [weak self] application in
            guard let self else { return }
            let isOurselves = self.isOurselves(application)
            self.memory.withLock { memory in
                memory.lastActivated = application
                if !isOurselves {
                    // Supersedes any read still in flight, so its older answer is not kept.
                    memory.requestNumber &+= 1
                    memory.appBehind = application
                }
            }
        }
        activationToken.withLock { $0 = token }
    }

    public func currentContext() async -> AppContext {
        let reading = Reading()
        let requestNumber = memory.withLock { memory in
            memory.requestNumber &+= 1
            return memory.requestNumber
        }

        let finished = await withinBudget { [self] in
            // Identity first and banked the moment it arrives, since everything after it can hang.
            let frontmost = await readFrontmostApplication()
            guard let early = subject(inFrontOf: frontmost, for: requestNumber) else { return }
            reading.record(application: early)
            guard let frontmost, early == frontmost else { return }

            // A panel that never activates holds focus over the frontmost application, so its owner is the destination.
            let destination = FocusedElementPreference.destination(
                focusOwner: await readFocusOwner(frontmost), frontmost: frontmost)
            guard let destination, let subject = subject(inFrontOf: destination, for: requestNumber)
            else { return }
            reading.record(application: subject)

            // Uttrflow's own window in front means the focused window is Uttrflow's, and belongs to nobody else.
            guard subject == destination else { return }
            await readFocusedWindow(subject, reading.window)
        }

        var gathered = reading.value
        // Identity missed the budget, so it comes from the activation feed instead.
        if gathered.application == nil, let fallback = activationFallback() {
            Self.log.notice("Context identity timed out; named from the activation feed")
            gathered.application = fallback
        }
        // A read the budget cut short says so, unless it had already banked why it stopped.
        let unavailable = gathered.window?.unavailable ?? (finished ? nil : .timedOut)
        // A secure field's text is dropped here too, so no reader can carry it into a prompt.
        if gathered.window?.isSecure == true {
            return AppContext(
                applicationName: Self.meaningful(gathered.application?.name),
                bundleIdentifier: Self.meaningful(gathered.application?.bundleIdentifier),
                processIdentifier: gathered.application?.processIdentifier,
                documentName: Self.meaningful(gathered.window?.title), isSecure: true,
                field: gathered.window?.field, readRung: gathered.window?.readRung, unavailable: unavailable)
        }
        return AppContext(
            applicationName: Self.meaningful(gathered.application?.name),
            bundleIdentifier: Self.meaningful(gathered.application?.bundleIdentifier),
            processIdentifier: gathered.application?.processIdentifier,
            documentName: Self.meaningful(gathered.window?.title),
            selectedText: Self.meaningful(gathered.window?.selectedText).map(Self.truncated),
            // Kept verbatim: an empty field is the start of the text, not nothing learnt.
            precedingText: gathered.window?.precedingText,
            followingText: gathered.window?.followingText,
            accessibilityRole: gathered.window?.accessibilityRole,
            isMultiline: gathered.window?.isMultiline,
            fieldLabel: gathered.window?.fieldLabel,
            field: gathered.window?.field,
            readRung: gathered.window?.readRung,
            unavailable: unavailable
        )
    }

    /// Which application the context is about, which is never Uttrflow. See `Docs/context-accessibility.md`.
    private func subject(
        inFrontOf frontmost: FrontmostApplication?, for requestNumber: UInt64
    ) -> FrontmostApplication? {
        guard let frontmost else { return nil }
        guard !isOurselves(frontmost) else {
            return memory.withLock { $0.appBehind }
        }
        memory.withLock { memory in
            if memory.requestNumber == requestNumber, !Task.isCancelled {
                memory.appBehind = frontmost
            }
        }
        return frontmost
    }

    /// The application the activation feed says is in front, never Uttrflow; `nil` when the feed is silent.
    private func activationFallback() -> FrontmostApplication? {
        memory.withLock { memory in
            guard let last = memory.lastActivated else { return nil }
            return isOurselves(last) ? memory.appBehind : last
        }
    }

    /// Records a read whose identity half missed the budget, so it can be seen in the field.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "context")

    /// Two ways to recognise ourselves, because either can be missing.
    private func isOurselves(_ application: FrontmostApplication) -> Bool {
        Self.isOurselves(
            application, ownProcessIdentifier: ownProcessIdentifier, ownBundleIdentifier: ownBundleIdentifier)
    }

    /// The identity check, free of `self` so the activation subscription can use it before init finishes.
    private static func isOurselves(
        _ application: FrontmostApplication, ownProcessIdentifier: Int32, ownBundleIdentifier: String?
    ) -> Bool {
        if application.processIdentifier == ownProcessIdentifier { return true }
        // Not `==` on the optionals: an app with no bundle identifier must not match an Uttrflow with none.
        guard let ownBundleIdentifier else { return false }
        return application.bundleIdentifier == ownBundleIdentifier
    }

    /// Runs `work`, waits no longer than ``budget`` for it, and says whether it finished. See `Docs/context-budget.md`.
    private func withinBudget(_ work: @escaping @Sendable () async -> Void) async -> Bool {
        await withDeadline(Self.budget, clock: clock) {
            await work()
            return true
        } ?? false
    }

    /// Drops text that is blank or only whitespace, so ``AppContext/isEmpty`` means what it says.
    static func meaningful(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Cuts an over-long selection down to ``selectedTextLimit`` characters.
    static func truncated(_ text: String) -> String {
        // `dropFirst` walks at most the limit, where `count` would walk a whole selected document.
        guard !text.dropFirst(selectedTextLimit).isEmpty else { return text }
        return text.prefix(selectedTextLimit) + truncationMarker
    }
}

/// What has been gathered so far, readable the instant the budget expires.
private final class Reading: Sendable {
    struct Value: Sendable {
        var application: FrontmostApplication?
        var window: FocusedWindow?
    }

    /// The gathered value under a lock, in a class since a bare `Mutex` cannot be captured by a task.
    private let state = Mutex(Value())

    /// Where the window read banks each answer, so the budget keeps whatever it already had.
    let window = FocusedWindowSink()

    var value: Value {
        var gathered = state.withLock { $0 }
        gathered.window = window.value
        return gathered
    }

    func record(application: FrontmostApplication) {
        state.withLock { $0.application = application }
    }
}

/// The focused window as far as the read has got, readable the instant the budget expires.
final class FocusedWindowSink: Sendable {
    private let state = Mutex<FocusedWindow?>(nil)

    var value: FocusedWindow? { state.withLock { $0 } }

    /// Replaces what was banked with a fuller answer; a field once found secure stays secure.
    func bank(_ window: FocusedWindow) {
        state.withLock { banked in
            guard banked?.isSecure != true else { return }
            banked = window
        }
    }
}
