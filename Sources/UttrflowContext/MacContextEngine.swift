public import UttrflowCore

import Foundation
private import Synchronization

/// One running application, reduced to what a context needs to know about it.
public struct FrontmostApplication: Sendable, Equatable {
    public let name: String?
    public let bundleIdentifier: String?
    /// Addresses the app for the Accessibility read, and identifies Uttrflow to itself
    /// when it runs unbundled and so has no bundle identifier to match on.
    public let processIdentifier: Int32

    public init(name: String? = nil, bundleIdentifier: String? = nil, processIdentifier: Int32) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

/// What the focused window was willing to say about itself.
///
/// The two halves are separately optional because apps answer them separately, which
/// a probe against the running desktop confirmed: Chrome named its window and refused
/// its selection, Terminal answered both, Slack answered neither.
public struct FocusedWindow: Sendable, Equatable {
    public let title: String?
    public let selectedText: String?

    public init(title: String? = nil, selectedText: String? = nil) {
        self.title = title
        self.selectedText = selectedText
    }
}

/// Reports what the user is looking at, without ever making them wait for the answer.
///
/// Two sources, with very different costs. Identity — the app's name and bundle
/// identifier — comes from NSWorkspace, is free, and needs no permission at all: a
/// probe running as an unsigned app with no Accessibility grant still read back
/// `Claude` / `com.anthropic.claudefordesktop` while every Accessibility call it made
/// returned `kAXErrorAPIDisabled`. The window title and the selection come from the
/// Accessibility API, need the permission, and can hang.
///
/// So the two are gathered in that order and recorded as they arrive. Whatever the
/// budget interrupts, the app name is already in hand.
public final class MacContextEngine: ContextEngine, Sendable {
    /// How long a whole reading may take before the dictation stops waiting for it.
    ///
    /// Measured, not guessed. Against the app the user is actually typing in — the only
    /// one that matters here — a focused-window read came back in 0.08–0.12 ms warm,
    /// and 35 ms on the very first read of a session, when the connection to that app
    /// is set up. The slow case is an app that has stopped pumping its run loop: with a
    /// 100 ms Accessibility messaging timeout in place, seven background apps on the
    /// probe machine each blocked for the full 101–105 ms and returned nothing. So
    /// 100 ms buys every realistic reading a thousand times over, and truncates only
    /// the readings that were going to fail anyway.
    ///
    /// It is also below the ~200 ms at which a person notices a delay, which is the
    /// ceiling that matters. This read happens after transcription, not before the
    /// recording — the pipeline asks for it while tidying, so the screen it describes
    /// is the one the text is about to go into — so the cost lands in the wait the user
    /// is already sitting through rather than eating their first word. That makes it
    /// additive to the time between stopping speaking and seeing text, which is the
    /// number this budget is defending.
    public static let budget = Duration.milliseconds(100)

    /// Characters of selected text kept.
    ///
    /// The selection rides into the prompt beside the transcript, and "select all, then
    /// dictate the replacement" is an ordinary thing to do — uncapped, that pastes a
    /// whole document into an on-device model with a few thousand tokens of room, and
    /// the transcript it is supposed to be helping gets crowded out.
    ///
    /// It is there to disambiguate, not to be read: the symbol under the cursor, the
    /// sentence being rewritten. The evaluation corpus's own case is `setUserPrefs`,
    /// twelve characters. 512 is roughly a long paragraph, ~128 tokens, and past that
    /// a selection stops adding meaning and starts costing context.
    public static let selectedTextLimit = 512

    /// ``budget`` as the Accessibility API wants it: seconds, as a `Float`.
    ///
    /// Converted here rather than at the call site because the failure is silent —
    /// `AXUIElementSetMessagingTimeout` reads zero as "use the global default", so
    /// reaching for `components.seconds` alone would quietly leave a sub-second budget
    /// with no timeout at all.
    static let budgetInSeconds =
        Float(budget.inSeconds)

    /// Marks a selection that was cut short, so a model reading it does not take the
    /// fragment for a finished sentence.
    static let truncationMarker = "…"

    private let readFrontmostApplication: @Sendable () async -> FrontmostApplication?
    private let readFocusedWindow: @Sendable (FrontmostApplication) async -> FocusedWindow?
    private let ownBundleIdentifier: String?
    private let ownProcessIdentifier: Int32
    private let clock: any Clock<Duration>

    /// The last application in front of the user that was not Uttrflow.
    ///
    /// Remembered rather than looked up, because macOS offers no way to ask what is
    /// behind the frontmost window: `runningApplications` comes back in launch order,
    /// not activation order. Watching the front change is the only honest source.
    private let appBehind = Mutex<FrontmostApplication?>(nil)

    /// Substitutes both readings. The public `init()` that wires up the real ones lives
    /// alongside them, in `MacContextEngine+System.swift`.
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
            // Identity first, and recorded the moment it arrives. This ordering is the
            // whole degradation guarantee: everything after it can hang, and the app
            // name is already banked.
            let frontmost = await readFrontmostApplication()
            guard let subject = subject(inFrontOf: frontmost) else { return }
            reading.record(application: subject)

            // Only read a window when the subject is what is genuinely on screen. With
            // Uttrflow's own window in front, the focused window is Uttrflow's, and
            // filing its title under the app behind would be a confident lie.
            guard subject == frontmost else { return }
            reading.record(window: await readFocusedWindow(subject))
        }

        let gathered = reading.value
        return AppContext(
            applicationName: Self.meaningful(gathered.application?.name),
            bundleIdentifier: Self.meaningful(gathered.application?.bundleIdentifier),
            documentName: Self.meaningful(gathered.window?.title),
            selectedText: Self.meaningful(gathered.window?.selectedText).map(Self.truncated)
        )
    }

    /// Which application the context is about.
    ///
    /// Uttrflow is never the answer. Its own window comes forward for settings, for
    /// onboarding, for a permission repair prompt, and "you are dictating into Uttrflow"
    /// is both useless and false — the words are on their way somewhere else. The app
    /// that was in front before is the honest answer; when there has not been one,
    /// nothing at all is.
    private func subject(inFrontOf frontmost: FrontmostApplication?) -> FrontmostApplication? {
        guard let frontmost else { return nil }
        guard isOurselves(frontmost) else {
            appBehind.withLock { $0 = frontmost }
            return frontmost
        }
        return appBehind.withLock { $0 }
    }

    /// Two ways to recognise ourselves, because either can be missing. A bundle
    /// identifier is the reliable one but is absent when Uttrflow runs unbundled, from
    /// the command line; the process identifier always holds.
    private func isOurselves(_ application: FrontmostApplication) -> Bool {
        if application.processIdentifier == ownProcessIdentifier { return true }
        // Not `==` on the optionals: an app that reports no bundle identifier must not
        // match a Uttrflow that has none either.
        guard let ownBundleIdentifier else { return false }
        return application.bundleIdentifier == ownBundleIdentifier
    }

    /// Runs `work`, and waits no longer than ``budget`` for it.
    ///
    /// The work is abandoned rather than cancelled. By the time the budget runs out it
    /// is blocked inside a synchronous Accessibility call that will not notice a
    /// cancellation, and the point here is only that the dictation stops waiting; the
    /// Accessibility layer's own messaging timeout is what eventually frees the thread.
    ///
    /// - Parameter work: The reading to attempt, which records what it gets as it goes.
    private func withinBudget(_ work: @escaping @Sendable () async -> Void) async {
        let race = FirstPast()
        var timer: Task<Void, Never>?
        await withCheckedContinuation { continuation in
            // Armed before either racer exists, or `FirstPast.finish` does nothing at all.
            race.arm(continuation)
            Task {
                await work()
                race.finish()
            }
            timer = Task { [clock] in
                try? await clock.sleep(for: Self.budget)
                race.finish()
            }
        }
        // Cancelled so a clock that sleeps for real does not leave a task per reading.
        timer?.cancel()
    }

    /// Drops what carries no information, so ``AppContext/isEmpty`` means what it says.
    ///
    /// Whitespace counts as nothing. A blank window title and a selection that is one
    /// stray space dragged past the end of a word are both "we learned nothing", and
    /// spending prompt tokens saying so makes the transformer's job harder, not easier.
    static func meaningful(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Cuts an over-long selection down to ``selectedTextLimit`` characters.
    static func truncated(_ text: String) -> String {
        // `dropFirst` walks at most the limit, where `count` would walk a whole
        // selected document to answer a question about its first few hundred characters.
        guard !text.dropFirst(selectedTextLimit).isEmpty else { return text }
        return text.prefix(selectedTextLimit) + truncationMarker
    }
}

/// What has been gathered so far, readable the instant the budget expires.
///
/// A class holding a `Mutex` rather than a bare `Mutex`: a `Mutex` is non-copyable and
/// so cannot be captured by the task that fills it in.
private final class Reading: Sendable {
    struct Value: Sendable {
        var application: FrontmostApplication?
        var window: FocusedWindow?
    }

    private let state = Mutex(Value())

    var value: Value { state.withLock { $0 } }

    func record(application: FrontmostApplication) {
        state.withLock { $0.application = application }
    }

    func record(window: FocusedWindow?) {
        state.withLock { $0.window = window }
    }
}

/// Resumes one continuation for whichever of two racers gets there first, and ignores
/// the loser when it eventually turns up.
private final class FirstPast: Sendable {
    private let held = Mutex<CheckedContinuation<Void, Never>?>(nil)

    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        held.withLock { $0 = continuation }
    }

    func finish() {
        let continuation = held.withLock { waiting in
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }
}
