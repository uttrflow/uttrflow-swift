import Synchronization
import Testing

@testable import UttrflowContext
@testable import UttrflowCore

/// A one-shot signal, so two concurrent steps can be put in an exact order without
/// sleeping. Every timing rule in this suite is proved this way rather than against the
/// wall clock, which would make it both slow and flaky.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let resuming = waiting
        waiting = []
        for continuation in resuming { continuation.resume() }
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
}

/// A clock whose sleep returns only once its gate is opened, so a test decides exactly
/// when the engine's budget expires — or, by never opening it, proves that the budget
/// is not what ended the reading.
private struct GatedClock: Clock {
    let gate = Gate()

    var now: ContinuousClock.Instant { ContinuousClock.now }
    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        await gate.wait()
    }
}

private let uttrflowBundle = "com.uttrflow.Uttrflow"
private let uttrflowProcess: Int32 = 501

private let slack = FrontmostApplication(
    name: "Slack",
    bundleIdentifier: "com.tinyspeck.slackmacgap",
    processIdentifier: 75_616
)
private let uttrflow = FrontmostApplication(
    name: "Uttrflow",
    bundleIdentifier: uttrflowBundle,
    processIdentifier: 900
)

/// The clock never fires unless a test opens its gate, so nothing here depends on how
/// long anything actually takes.
private func makeEngine(
    frontmost: @escaping @Sendable () async -> FrontmostApplication?,
    window: @escaping @Sendable (FrontmostApplication) async -> FocusedWindow? = { _ in nil },
    ownBundleIdentifier: String? = uttrflowBundle,
    ownProcessIdentifier: Int32 = uttrflowProcess,
    clock: any Clock<Duration> = GatedClock()
) -> MacContextEngine {
    MacContextEngine(
        readFrontmostApplication: frontmost,
        readFocusedWindow: window,
        ownBundleIdentifier: ownBundleIdentifier,
        ownProcessIdentifier: ownProcessIdentifier,
        clock: clock
    )
}

private func makeEngine(
    frontmost: FrontmostApplication?,
    window: FocusedWindow? = nil,
    ownBundleIdentifier: String? = uttrflowBundle
) -> MacContextEngine {
    makeEngine(
        frontmost: { frontmost },
        window: { _ in window },
        ownBundleIdentifier: ownBundleIdentifier
    )
}

@Suite("MacContextEngine")
struct MacContextEngineTests {
    // MARK: - Assembling a context

    @Test("names the frontmost application and its bundle")
    func reportsTheFrontmostApplication() async {
        let context = await makeEngine(frontmost: slack).currentContext()

        #expect(context.applicationName == "Slack")
        #expect(context.bundleIdentifier == "com.tinyspeck.slackmacgap")
    }

    @Test("takes the document name from the focused window's title")
    func reportsTheWindowTitle() async {
        let window = FocusedWindow(title: "#finance-ops", selectedText: "setUserPrefs")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == "#finance-ops")
        #expect(context.selectedText == "setUserPrefs")
        #expect(context.isEmpty == false)
    }

    @Test("carries the caret text verbatim, so an empty field reads as the start of the text")
    func reportsTheCaretText() async {
        let window = FocusedWindow(title: "Notes", precedingText: "", followingText: "  ")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.precedingText == "")
        #expect(context.followingText == "  ")
        #expect(context.insertionPoint.sentenceState == .startOfText)
    }

    @Test("reports no caret text when the field would not say")
    func reportsNoCaretText() async {
        let context = await makeEngine(frontmost: slack, window: FocusedWindow(title: "Notes"))
            .currentContext()

        #expect(context.precedingText == nil)
        #expect(context.followingText == nil)
        #expect(context.insertionPoint.sentenceState == .unknown)
    }

    @Test("reads the window of the application it is reporting on")
    func readsTheWindowOfTheSubject() async {
        let asked = Mutex<FrontmostApplication?>(nil)
        let engine = makeEngine(
            frontmost: { slack },
            window: { subject in
                asked.withLock { $0 = subject }
                return nil
            }
        )

        _ = await engine.currentContext()
        #expect(asked.withLock { $0 } == slack)
    }

    @Test("knows nothing when macOS names no frontmost application")
    func nothingInFront() async {
        let context = await makeEngine(frontmost: nil).currentContext()

        #expect(context == .unknown)
        #expect(context.isEmpty)
    }

    @Test("does not go looking for a window when there is no application to attach it to")
    func noWindowReadWithoutASubject() async {
        let asked = Mutex(false)
        let engine = makeEngine(
            frontmost: { nil },
            window: { _ in
                asked.withLock { $0 = true }
                return nil
            }
        )

        _ = await engine.currentContext()
        #expect(asked.withLock { $0 } == false)
    }

    // MARK: - Independent degradation

    @Test("keeps the application name when the window cannot be read at all")
    func windowFailureLeavesIdentityIntact() async {
        let context = await makeEngine(frontmost: slack, window: nil).currentContext()

        #expect(context.applicationName == "Slack")
        #expect(context.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(context.documentName == nil)
        #expect(context.selectedText == nil)
    }

    /// Chrome, in the probe against the running desktop: it named its window and
    /// answered `kAXErrorNoValue` for the selection.
    @Test("keeps a window title whose selection the application refused")
    func titleWithoutSelection() async {
        let window = FocusedWindow(title: "Vast.ai | Console", selectedText: nil)
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == "Vast.ai | Console")
        #expect(context.selectedText == nil)
    }

    @Test("keeps a selection whose window would not give up its title")
    func selectionWithoutTitle() async {
        let window = FocusedWindow(title: nil, selectedText: "SELECT * FROM users")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == nil)
        #expect(context.selectedText == "SELECT * FROM users")
    }

    @Test("keeps a bundle identifier for an application that will not name itself")
    func bundleWithoutName() async {
        let anonymous = FrontmostApplication(
            name: nil, bundleIdentifier: "com.example.tool", processIdentifier: 42)
        let context = await makeEngine(frontmost: anonymous).currentContext()

        #expect(context.applicationName == nil)
        #expect(context.bundleIdentifier == "com.example.tool")
    }

    // MARK: - Never waiting

    @Test("gives up on a window read that never returns, and keeps the application name")
    func timesOutOnAHungWindowRead() async {
        let clock = GatedClock()
        let started = Gate()
        let hung = Gate()
        let engine = makeEngine(
            frontmost: { slack },
            window: { _ in
                await started.open()
                await hung.wait()
                return FocusedWindow(title: "never arrives")
            },
            clock: clock
        )

        async let reading = engine.currentContext()
        // The read is now provably stuck, with the identity already banked. Expiring
        // the budget from here is what makes the race deterministic.
        await started.wait()
        await clock.gate.open()
        let context = await reading

        #expect(context.applicationName == "Slack")
        #expect(context.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(context.documentName == nil, "a hung read must not be waited for")
        #expect(context.selectedText == nil)
    }

    @Test("returns nothing rather than waiting when even the identity read hangs")
    func timesOutBeforeAnythingIsGathered() async {
        let clock = GatedClock()
        let started = Gate()
        let hung = Gate()
        let engine = makeEngine(
            frontmost: {
                await started.open()
                await hung.wait()
                return slack
            },
            clock: clock
        )

        async let reading = engine.currentContext()
        await started.wait()
        await clock.gate.open()
        let context = await reading

        #expect(context == .unknown)
    }

    @Test("returns as soon as the reading is done, without waiting out the budget")
    func doesNotWaitOutTheBudgetOnASuccessfulRead() async {
        // The clock's gate is never opened, so the only way this test can finish at all
        // is by the reading itself ending the wait.
        let window = FocusedWindow(title: "revenue.sql — billing")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == "revenue.sql — billing")
    }

    @Test("survives the abandoned reading finishing after the budget has expired")
    func lateReadingIsHarmless() async {
        let clock = GatedClock()
        let started = Gate()
        let release = Gate()
        let engine = makeEngine(
            frontmost: { slack },
            window: { _ in
                await started.open()
                await release.wait()
                return FocusedWindow(title: "too late")
            },
            clock: clock
        )

        async let reading = engine.currentContext()
        await started.wait()
        await clock.gate.open()
        let context = await reading
        #expect(context.documentName == nil)

        // The loser of the race now arrives. It must not resume the continuation a
        // second time, which would trap.
        await release.open()
        let next = await engine.currentContext()
        #expect(next.applicationName == "Slack")
    }

    @Test("the budget is short enough that nobody notices it")
    func budgetIsImperceptible() {
        #expect(MacContextEngine.budget == .milliseconds(100))
        #expect(MacContextEngine.budget < .milliseconds(200))
    }

    /// `AXUIElementSetMessagingTimeout` reads zero as "use the global default", so a
    /// sub-second budget that rounded to zero would silently leave the Accessibility
    /// calls uncapped.
    @Test("expresses the budget in seconds without rounding it away")
    func budgetSurvivesConversionToSeconds() {
        #expect(MacContextEngine.budgetInSeconds > 0)
        #expect(abs(MacContextEngine.budgetInSeconds - 0.1) < 0.0001)
    }

    // MARK: - Never reporting Uttrflow

    @Test("reports the application behind it when Uttrflow's own window is in front")
    func reportsTheApplicationBehindItself() async {
        let front = Mutex(slack)
        let engine = makeEngine(frontmost: { front.withLock { $0 } })

        let first = await engine.currentContext()
        #expect(first.applicationName == "Slack")

        front.withLock { $0 = uttrflow }
        let context = await engine.currentContext()

        #expect(context.applicationName == "Slack", "the words are on their way to Slack, not here")
        #expect(context.bundleIdentifier == "com.tinyspeck.slackmacgap")
    }

    @Test("recognises itself by process identifier when it has no bundle identifier")
    func recognisesItselfWhenRunningUnbundled() async {
        let unbundled = FrontmostApplication(
            name: "uttrflow-dev", bundleIdentifier: nil, processIdentifier: uttrflowProcess)
        let front = Mutex(slack)
        let engine = makeEngine(
            frontmost: { front.withLock { $0 } },
            ownBundleIdentifier: nil
        )

        let first = await engine.currentContext()
        #expect(first.applicationName == "Slack")

        front.withLock { $0 = unbundled }
        let context = await engine.currentContext()
        #expect(context.applicationName == "Slack")
    }

    @Test("does not mistake another nameless application for itself")
    func anotherAnonymousApplicationIsNotUs() async {
        let stranger = FrontmostApplication(
            name: "Some Tool", bundleIdentifier: nil, processIdentifier: 4_242)
        let context = await makeEngine(
            frontmost: stranger, ownBundleIdentifier: nil
        ).currentContext()

        #expect(context.applicationName == "Some Tool")
    }

    @Test("reports nothing when Uttrflow is in front and nothing has been behind it yet")
    func nothingBehindUttrflow() async {
        let context = await makeEngine(frontmost: uttrflow).currentContext()

        #expect(context == .unknown)
        #expect(context.isEmpty)
    }

    @Test("never files its own window title under the application behind it")
    func doesNotAttributeItsOwnWindowToAnotherApplication() async {
        let front = Mutex(slack)
        let reads = Mutex(0)
        let engine = makeEngine(
            frontmost: { front.withLock { $0 } },
            window: { _ in
                reads.withLock { $0 += 1 }
                return FocusedWindow(title: "Uttrflow Settings", selectedText: "a preference")
            }
        )

        _ = await engine.currentContext()
        front.withLock { $0 = uttrflow }
        let context = await engine.currentContext()

        #expect(context.applicationName == "Slack")
        #expect(context.documentName == nil, "that window belongs to Uttrflow, not to Slack")
        #expect(context.selectedText == nil)
        #expect(reads.withLock { $0 } == 1, "there is no point reading our own window")
    }

    @Test("follows the user from one application to the next")
    func remembersTheMostRecentApplication() async {
        let xcode = FrontmostApplication(
            name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 28_165)
        let front = Mutex(slack)
        let engine = makeEngine(frontmost: { front.withLock { $0 } })

        _ = await engine.currentContext()
        front.withLock { $0 = xcode }
        _ = await engine.currentContext()
        front.withLock { $0 = uttrflow }
        let context = await engine.currentContext()

        #expect(context.applicationName == "Xcode")
    }

    // MARK: - Empty means nothing

    @Test(
        "treats a field that carries no information as absent",
        arguments: ["", " ", "\t", "\n", "   \n  "]
    )
    func blankFieldsBecomeNil(blank: String) async {
        let application = FrontmostApplication(
            name: blank, bundleIdentifier: blank, processIdentifier: 7)
        let window = FocusedWindow(title: blank, selectedText: blank)
        let context = await makeEngine(frontmost: application, window: window).currentContext()

        #expect(context.applicationName == nil)
        #expect(context.bundleIdentifier == nil)
        #expect(context.documentName == nil)
        #expect(context.selectedText == nil)
        #expect(context.isEmpty, "isEmpty is only meaningful if blanks do not count")
    }

    @Test("trims the whitespace a drag-selection picks up at its edges")
    func trimsSurroundingWhitespace() async {
        let window = FocusedWindow(title: "  Untitled  ", selectedText: "\n setUserPrefs \n")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == "Untitled")
        #expect(context.selectedText == "setUserPrefs")
    }

    @Test("keeps the whitespace inside a field")
    func keepsInnerWhitespace() async {
        let window = FocusedWindow(title: "revenue.sql — billing")
        let context = await makeEngine(frontmost: slack, window: window).currentContext()

        #expect(context.documentName == "revenue.sql — billing")
    }

    @Test("meaningful() drops a missing field as readily as a blank one")
    func meaningfulHandlesNil() {
        #expect(MacContextEngine.meaningful(nil) == nil)
        #expect(MacContextEngine.meaningful("Slack") == "Slack")
    }

    // MARK: - Truncation

    @Test("leaves a selection at the limit exactly as it was")
    func selectionAtTheLimitIsUntouched() async {
        let selection = String(repeating: "x", count: MacContextEngine.selectedTextLimit)
        let context = await makeEngine(
            frontmost: slack, window: FocusedWindow(selectedText: selection)
        ).currentContext()

        #expect(context.selectedText == selection)
    }

    @Test("cuts a selection one character past the limit, and says that it did")
    func selectionPastTheLimitIsCut() async {
        let selection = String(repeating: "x", count: MacContextEngine.selectedTextLimit + 1)
        let context = await makeEngine(
            frontmost: slack, window: FocusedWindow(selectedText: selection)
        ).currentContext()

        #expect(context.selectedText?.hasSuffix(MacContextEngine.truncationMarker) == true)
        #expect(
            context.selectedText?.count == MacContextEngine.selectedTextLimit + 1,
            "the limit's worth of text, plus the marker that says there was more"
        )
    }

    @Test("keeps the beginning of a selected document, never the whole of it")
    func aWholeDocumentIsNotPastedIntoThePrompt() async {
        let document = "SELECT * FROM users; " + String(repeating: "filler ", count: 10_000)
        let context = await makeEngine(
            frontmost: slack, window: FocusedWindow(selectedText: document)
        ).currentContext()

        let selected = context.selectedText ?? ""
        #expect(selected.hasPrefix("SELECT * FROM users;"))
        #expect(selected.count == MacContextEngine.selectedTextLimit + 1)
        #expect(selected.count < document.count / 100)
    }

    @Test("does not truncate a window title, which is short by construction")
    func titlesAreNotTruncated() async {
        let long = String(repeating: "t", count: MacContextEngine.selectedTextLimit + 50)
        let context = await makeEngine(
            frontmost: slack, window: FocusedWindow(title: long)
        ).currentContext()

        #expect(context.documentName == long)
    }

    @Test("the limit is a paragraph, not a document")
    func limitIsSized() {
        #expect(MacContextEngine.selectedTextLimit == 512)
    }

    @Test("truncated() counts characters, not bytes")
    func truncationIsCharacterwise() {
        let emoji = String(repeating: "🇮🇳", count: MacContextEngine.selectedTextLimit + 10)
        let cut = MacContextEngine.truncated(emoji)

        #expect(cut.count == MacContextEngine.selectedTextLimit + 1)
        #expect(cut.hasPrefix("🇮🇳🇮🇳"))
    }
}
