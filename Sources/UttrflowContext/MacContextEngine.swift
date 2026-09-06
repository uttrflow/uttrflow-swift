public import UttrflowCore

import Foundation
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

    public init(
        title: String? = nil, selectedText: String? = nil, precedingText: String? = nil,
        followingText: String? = nil
    ) {
        self.title = title
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
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

    /// Marks a cut selection, so a model does not take the fragment for a finished sentence.
    static let truncationMarker = "…"

    private let readFrontmostApplication: @Sendable () async -> FrontmostApplication?
    private let readFocusedWindow: @Sendable (FrontmostApplication) async -> FocusedWindow?
    private let ownBundleIdentifier: String?
    private let ownProcessIdentifier: Int32
    private let clock: any Clock<Duration>

    /// The last application in front of the user that was not Uttrflow, which macOS will not be asked for.
    private let appBehind = Mutex<FrontmostApplication?>(nil)

    /// Substitutes both readings; `MacContextEngine+System.swift` wires up the real ones.
    init(
        readFrontmostApplication: @escaping @Sendable () async -> FrontmostApplication?,
        readFocusedWindow: @escaping @Sendable (FrontmostApplication) async -> FocusedWindow?,
        ownBundleIdentifier: String?,
        ownProcessIdentifier: Int32,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.readFrontmostApplication = readFrontmostApplication
        self.readFocusedWindow = readFocusedWindow
        self.ownBundleIdentifier = ownBundleIdentifier
        self.ownProcessIdentifier = ownProcessIdentifier
        self.clock = clock
    }

    public func currentContext() async -> AppContext {
        let reading = Reading()

        await withinBudget { [self] in
            // Identity first and banked the moment it arrives, since everything after it can hang.
            let frontmost = await readFrontmostApplication()
            guard let subject = subject(inFrontOf: frontmost) else { return }
            reading.record(application: subject)

            // Uttrflow's own window in front means the focused window is Uttrflow's, and belongs to nobody else.
            guard subject == frontmost else { return }
            reading.record(window: await readFocusedWindow(subject))
        }

        let gathered = reading.value
        return AppContext(
            applicationName: Self.meaningful(gathered.application?.name),
            bundleIdentifier: Self.meaningful(gathered.application?.bundleIdentifier),
            documentName: Self.meaningful(gathered.window?.title),
            selectedText: Self.meaningful(gathered.window?.selectedText).map(Self.truncated),
            // Kept verbatim: an empty field is the start of the text, not nothing learnt.
            precedingText: gathered.window?.precedingText,
            followingText: gathered.window?.followingText
        )
    }

    /// Which application the context is about, which is never Uttrflow. See `Docs/context-accessibility.md`.
    private func subject(inFrontOf frontmost: FrontmostApplication?) -> FrontmostApplication? {
        guard let frontmost else { return nil }
        guard isOurselves(frontmost) else {
            appBehind.withLock { $0 = frontmost }
            return frontmost
        }
        return appBehind.withLock { $0 }
    }

    /// Two ways to recognise ourselves, because either can be missing.
    private func isOurselves(_ application: FrontmostApplication) -> Bool {
        if application.processIdentifier == ownProcessIdentifier { return true }
        // Not `==` on the optionals: an app with no bundle identifier must not match an Uttrflow with none.
        guard let ownBundleIdentifier else { return false }
        return application.bundleIdentifier == ownBundleIdentifier
    }

    /// Runs `work`, waits no longer than ``budget`` for it, and abandons what is left. See `Docs/context-budget.md`.
    private func withinBudget(_ work: @escaping @Sendable () async -> Void) async {
        _ = await Deadline.first(within: Self.budget, on: clock) {
            await work()
            return true
        }
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

    var value: Value { state.withLock { $0 } }

    func record(application: FrontmostApplication) {
        state.withLock { $0.application = application }
    }

    func record(window: FocusedWindow?) {
        state.withLock { $0.window = window }
    }
}
