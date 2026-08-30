import Testing

@testable import UttrflowCore
@testable import UttrflowUX

// MARK: - Fixtures

/// A blocking failure: the microphone is off, so nothing can be dictated at all.
private let microphoneOff = FailurePresenter.present(PermissionError.microphoneDenied)

/// A degraded one: the words arrived, just on the clipboard rather than in the app.
private let clipboardFallback = FailurePresenter.present(
    TextInsertionError.insertionRejected(description: "read-only field"))

/// One with nothing to offer, to prove the menu does not invent a row for it.
private let noWayOut = FailurePresenter.present(AudioCaptureError.unsupportedInputFormat)

private let twoRecents = [
    MenuBarRecent(
        title: "Hey John, I'll probably be about 20 minutes…",
        fullText: "Hey John, I'll probably be about 20 minutes late, sorry."),
    MenuBarRecent(
        title: "The deployment is still running, so I'll…",
        fullText: "The deployment is still running, so I'll follow up this afternoon."),
]

extension MenuBarPresentation {
    /// The command whose intent is this one, if the menu is offering it at all.
    fileprivate func command(_ intent: MenuBarIntent) -> MenuBarCommand? {
        commands.first { $0.intent == intent }
    }

    fileprivate var titles: [String] { commands.map(\.title) }
}

// MARK: - The icon

@Suite("What the menu bar icon shows")
struct MenuBarIconTests {
    /// The menu bar is the only part of Uttrflow that is always on screen, so the icon
    /// has to carry the state on its own — a user who never opens the menu still needs
    /// to know whether the microphone is live.
    @Test("shows a different icon for resting, listening, working and done")
    func iconFollowsActivity() {
        let icons = DictationActivity.allCases.map {
            MenuBarPresenter.present(MenuBarState(activity: $0)).icon
        }
        #expect(
            icons == [
                .mark, .symbol("mic.fill"), .symbol("sparkles"), .symbol("checkmark"),
            ])
        #expect(Set(icons).count == DictationActivity.allCases.count)
    }

    /// Resting is the one moment the slot has nothing to report, so it says whose app
    /// this is instead. Every other state has news and shows a symbol for it.
    @Test("carries the mark only while nothing is happening")
    func restIsTheMark() {
        #expect(MenuBarPresenter.present(MenuBarState(activity: .idle)).icon == .mark)
        for activity in DictationActivity.allCases where activity != .idle {
            #expect(MenuBarPresenter.present(MenuBarState(activity: activity)).icon != .mark)
        }
    }

    @Test("overrides every activity when something needs fixing")
    func attentionOutranksActivity() {
        for activity in DictationActivity.allCases {
            let shown = MenuBarPresenter.present(
                MenuBarState(activity: activity, failure: microphoneOff))
            #expect(shown.icon == .symbol("exclamationmark.triangle.fill"))
            #expect(shown.isAttentionNeeded)
            #expect(shown.emphasis == .attention)
        }
    }

    /// A failure shown beside the work has already been seen. Lighting the menu bar up
    /// as well would leave an orange warning over an app that is working perfectly.
    @Test("stays calm about a failure the floating button already reported")
    func degradedFailureDoesNotLightTheMenuBar() {
        let shown = MenuBarPresenter.present(MenuBarState(failure: clipboardFallback))
        #expect(!shown.isAttentionNeeded)
        #expect(shown.icon == .mark)
        // It is still the news of the moment, so it still leads the menu.
        #expect(shown.statusLine == clipboardFallback.headline)
    }

    @Test("marks a live microphone even with nothing wrong")
    func listeningIsItsOwnEmphasis() {
        #expect(MenuBarPresenter.present(MenuBarState(activity: .listening)).emphasis == .live)
        #expect(MenuBarPresenter.present(MenuBarState(activity: .idle)).emphasis == .normal)
        #expect(MenuBarPresenter.present(MenuBarState(activity: .finished)).emphasis == .normal)
    }
}

// MARK: - The status line

@Suite("What the menu bar says")
struct MenuBarStatusTests {
    @Test("names each moment in the user's words, not the machinery's")
    func statusLinePerActivity() {
        let lines = DictationActivity.allCases.map {
            MenuBarPresenter.present(MenuBarState(activity: $0)).statusLine
        }
        #expect(lines == ["Ready", "Listening…", "Tidying up…", "Inserted"])
    }

    /// "Ready" over a model that has not downloaded is a lie the user finds out about
    /// by pressing the shortcut and getting nothing.
    @Test("says setting up rather than ready while the model is still coming")
    func setupOutranksReady() {
        #expect(
            MenuBarPresenter.present(MenuBarState(speechModel: .downloading(fractionCompleted: nil)))
                .statusLine == "Setting up…")
        #expect(
            MenuBarPresenter.present(
                MenuBarState(speechModel: .downloading(fractionCompleted: 0.42))
            ).statusLine == "Setting up… 42%")
        #expect(
            MenuBarPresenter.present(MenuBarState(speechModel: .notInstalled)).statusLine
                == "Setup hasn't finished")
    }

    /// A downloader reporting 140% is a bug in the downloader, and the menu bar is the
    /// wrong place for the user to find out about it.
    @Test("keeps a nonsense percentage out of the menu bar")
    func percentageIsClamped() {
        #expect(MenuBarPresenter.percentage(of: -3) == 0)
        #expect(MenuBarPresenter.percentage(of: 1.4) == 100)
        #expect(MenuBarPresenter.percentage(of: 0.005) == 1)
    }

    @Test("leads with the failure, whatever else is happening")
    func failureOutranksEverything() {
        let shown = MenuBarPresenter.present(
            MenuBarState(
                activity: .listening, failure: microphoneOff,
                speechModel: .downloading(fractionCompleted: 0.5)))
        #expect(shown.statusLine == microphoneOff.headline)
    }

    /// VoiceOver reads this instead of the icon, so it has to be a sentence — and it
    /// has to come from the same string the status line does, or the two drift apart
    /// and the one that drifts is the one nobody can see.
    @Test("says the same thing aloud that it says on screen")
    func accessibilityLabelFollowsTheStatusLine() {
        #expect(
            MenuBarPresenter.present(MenuBarState()).accessibilityLabel == "Uttrflow. Ready.")
        #expect(
            MenuBarPresenter.present(MenuBarState(activity: .listening)).accessibilityLabel
                == "Uttrflow. Listening.")
        #expect(
            MenuBarPresenter.present(MenuBarState(activity: .working)).accessibilityLabel
                == "Uttrflow. Tidying up.")
        // The failure's own sentence already ends in a full stop; a second would be read
        // out as a second pause.
        #expect(
            MenuBarPresenter.present(MenuBarState(failure: microphoneOff)).accessibilityLabel
                == "Uttrflow. \(microphoneOff.headline)")
    }
}

// MARK: - What the menu contains

@Suite("What the menu offers")
struct MenuBarContentsTests {
    /// The order of the design, top to bottom.
    @Test("lays the menu out the way the design does")
    func menuOrder() {
        let shown = MenuBarPresenter.present(MenuBarState(recents: twoRecents))
        #expect(
            shown.titles == [
                // Directly under dictation, because they are the app's two halves and
                // the clipboard is the half people reach for most.
                "Start Dictation", "Clipboard",
                twoRecents[0].title, "Copy “\(twoRecents[0].title)”",
                twoRecents[1].title, "Copy “\(twoRecents[1].title)”",
                "Open Uttrflow", "Settings…", "Quit Uttrflow",
            ])
        guard case .status = shown.items.first else {
            Issue.record("the menu does not begin with the status line")
            return
        }
        #expect(shown.items.contains(.sectionHeader("Recent")))
    }

    /// The problem and its one fix sit together at the top; anything between them makes
    /// the user hunt for the way out of the thing they opened the menu about.
    @Test("puts the one fix directly under the problem")
    func recoverySitsUnderTheProblem() {
        let shown = MenuBarPresenter.present(MenuBarState(failure: microphoneOff))
        guard case .status = shown.items.first,
            case .command(let fix) = shown.items[1]
        else {
            Issue.record("the fix is not the row under the status line")
            return
        }
        #expect(fix.title == "Open System Settings…")
        #expect(fix.intent == .recover(.openSystemSettings(.microphone)))
        #expect(fix.isEnabled)
    }

    /// A menu row that opens something else gets an ellipsis; a row that just does the
    /// thing does not. The banner button keeps the plainer wording either way.
    @Test("adds the ellipsis only where a menu should")
    func menuTitleEllipsis() {
        let shown = MenuBarPresenter.present(MenuBarState(failure: clipboardFallback))
        #expect(shown.command(.recover(.pasteManually))?.title == "Paste")
        #expect(clipboardFallback.action?.title == "Paste")
    }

    @Test("offers nothing extra for a failure that has no fix")
    func noFixMeansNoRow() {
        let shown = MenuBarPresenter.present(MenuBarState(failure: noWayOut))
        #expect(shown.statusLine == noWayOut.headline)
        #expect(shown.commands.allSatisfy { if case .recover = $0.intent { false } else { true } })
    }

    /// The menu names where it wants to go and the app owns the windows, so a new place
    /// to open is one more ``Destination`` rather than one more callback.
    @Test("asks for a window by naming the place, not by opening it")
    func windowsAreNamedAsDestinations() {
        let shown = MenuBarPresenter.present(MenuBarState())
        #expect(shown.command(.open(.main(.dictation)))?.title == "Open Uttrflow")
        #expect(shown.command(.open(.settings(.general)))?.title == "Settings…")
    }

    /// Every shortcut the design prints on a menu row.
    @Test("prints the shortcuts the design prints")
    func shortcuts() {
        let shown = MenuBarPresenter.present(MenuBarState())
        #expect(shown.command(.startDictation)?.shortcut == MenuBarShortcut(key: " ", modifiers: .option))
        #expect(
            shown.command(.open(.main(.dictation)))?.shortcut
                == MenuBarShortcut(key: "0", modifiers: .command))
        #expect(
            shown.command(.open(.settings(.general)))?.shortcut
                == MenuBarShortcut(key: ",", modifiers: .command))
        #expect(shown.command(.quit)?.shortcut == MenuBarShortcut(key: "q", modifiers: .command))
    }

    /// Quitting has to work whatever else is broken; a user who cannot dictate and
    /// cannot quit either is stuck with an icon they can do nothing about.
    @Test("always lets the user leave")
    func quitIsAlwaysAvailable() {
        for failure in [microphoneOff, clipboardFallback, noWayOut] {
            let shown = MenuBarPresenter.present(
                MenuBarState(activity: .working, failure: failure, speechModel: .notInstalled))
            #expect(shown.command(.quit)?.isEnabled == true)
            #expect(shown.command(.open(.main(.dictation)))?.isEnabled == true)
            #expect(shown.command(.open(.settings(.general)))?.isEnabled == true)
        }
    }
}

// MARK: - What may be chosen

@Suite("What the menu lets the user do")
struct MenuBarEnablementTests {
    /// Disabled rather than silently failing: pressing Start Dictation while the
    /// microphone is refused would look like the app is broken.
    @Test("refuses to start a dictation that cannot happen")
    func startDictationEnablement() {
        #expect(MenuBarPresenter.canStartDictation(in: MenuBarState()))
        #expect(MenuBarPresenter.canStartDictation(in: MenuBarState(activity: .finished)))

        // Already dictating.
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(activity: .listening)))
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(activity: .working)))
        // A permission in the way.
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(failure: microphoneOff)))
        // Nothing to transcribe with yet.
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: .notInstalled)))
        #expect(
            !MenuBarPresenter.canStartDictation(
                in: MenuBarState(speechModel: .downloading(fractionCompleted: 0.9))))
    }

    /// A failure the user can carry on past must not take dictation away from them —
    /// the whole point of calling it degraded is that the product still works.
    @Test("still lets a degraded failure be dictated past")
    func degradedFailureDoesNotBlock() {
        #expect(MenuBarPresenter.canStartDictation(in: MenuBarState(failure: clipboardFallback)))
        let shown = MenuBarPresenter.present(MenuBarState(failure: clipboardFallback))
        #expect(shown.command(.startDictation)?.isEnabled == true)
    }

    @Test("greys the item rather than hiding it")
    func startDictationIsAlwaysPresent() {
        let shown = MenuBarPresenter.present(
            MenuBarState(activity: .idle, failure: microphoneOff, speechModel: .notInstalled))
        #expect(shown.command(.startDictation)?.isEnabled == false)
        #expect(shown.titles.contains("Start Dictation"))
    }

    /// A dictation begun from the menu has to be endable from the menu. It was not: the
    /// item read "Start Dictation" throughout, so the microphone stayed open with the
    /// only escape being the shortcut — a short tap of which hits the slip rule and
    /// silently discards everything recorded.
    @Test("offers a way to stop a dictation it started")
    func stopIsOfferedWhileListening() {
        let shown = MenuBarPresenter.present(MenuBarState(activity: .listening))

        #expect(shown.titles.contains("Stop Dictation"))
        #expect(!shown.titles.contains("Start Dictation"))
        #expect(shown.command(.stopDictation)?.isEnabled == true)
    }

    /// Even when something is wrong. A blocking failure must not strand the microphone
    /// open by greying out the only thing that closes it.
    @Test("still offers stop when a blocking failure would refuse a start")
    func stopSurvivesABlockingFailure() {
        let shown = MenuBarPresenter.present(
            MenuBarState(activity: .listening, failure: microphoneOff, speechModel: .notInstalled))

        #expect(shown.command(.stopDictation)?.isEnabled == true)
    }

    /// Transcription cannot be interrupted, and an enabled Stop that did nothing would
    /// be worse than no Stop at all.
    @Test("offers no stop once the words are being worked on")
    func noStopWhileWorking() {
        let shown = MenuBarPresenter.present(MenuBarState(activity: .working))

        #expect(!shown.titles.contains("Stop Dictation"))
        #expect(shown.command(.startDictation)?.isEnabled == false)
    }

    /// A permanently greyed "No recent dictations" row is a line of the menu spent
    /// telling the user something they can already see.
    @Test("leaves out the Recent section entirely when there is nothing in it")
    func noRecentsMeansNoSection() {
        let shown = MenuBarPresenter.present(MenuBarState())
        #expect(!shown.items.contains(.sectionHeader("Recent")))
        #expect(shown.commands.allSatisfy { if case .insertRecent = $0.intent { false } else { true } })
    }

    /// Reaching for an old dictation while a new one is on its way into the same text
    /// field would race the insertion that is already happening.
    @Test("will not re-insert a dictation in the middle of another")
    func recentsAreDisabledWhileBusy() {
        for activity in [DictationActivity.listening, .working] {
            let shown = MenuBarPresenter.present(
                MenuBarState(activity: activity, recents: twoRecents))
            #expect(shown.command(.insertRecent(index: 0))?.isEnabled == false)
            #expect(shown.command(.copyRecent(index: 0))?.isEnabled == false)
        }
        for activity in [DictationActivity.idle, .finished] {
            let shown = MenuBarPresenter.present(
                MenuBarState(activity: activity, recents: twoRecents))
            #expect(shown.command(.insertRecent(index: 0))?.isEnabled == true)
        }
    }

    /// Positions rather than text: the menu hands back which row was chosen and the app
    /// looks it up in the list it already owns.
    @Test("identifies a recent dictation by where it is in the list")
    func recentsCarryTheirPosition() {
        let shown = MenuBarPresenter.present(MenuBarState(recents: twoRecents))
        #expect(shown.command(.insertRecent(index: 1))?.title == twoRecents[1].title)
        #expect(shown.command(.insertRecent(index: 2)) == nil)
    }

    /// Copying is the rarer wish, so it hides behind Option on the same row rather than
    /// doubling the length of the section — and the tooltip is the whole dictation,
    /// because the shortened title is not what clicking would insert.
    @Test("hides copying behind Option and tells the truth in the tooltip")
    func copyIsTheAlternateRow() {
        let shown = MenuBarPresenter.present(MenuBarState(recents: twoRecents))
        let insert = shown.command(.insertRecent(index: 0))
        let copy = shown.command(.copyRecent(index: 0))
        #expect(insert?.isAlternate == false)
        #expect(copy?.isAlternate == true)
        #expect(copy?.shortcut == MenuBarShortcut(key: "", modifiers: .option))
        #expect(insert?.tooltip == twoRecents[0].fullText)
        #expect(copy?.tooltip == twoRecents[0].fullText)
    }

    /// The status line is a label, and a clickable label is a promise the menu cannot
    /// keep.
    @Test("never makes the status line clickable")
    func statusLineIsNotACommand() {
        let shown = MenuBarPresenter.present(MenuBarState(failure: microphoneOff))
        #expect(shown.items.contains(.status(text: microphoneOff.headline, emphasis: .attention)))
        #expect(!shown.titles.contains(microphoneOff.headline))
    }

    /// Two presentations of the same moment are compared to decide whether the menu bar
    /// has anything new to draw.
    @Test("presents the same state as the same thing twice")
    func presentationsAreValues() {
        let state = MenuBarState(activity: .listening, recents: twoRecents)
        #expect(MenuBarPresenter.present(state) == MenuBarPresenter.present(state))
        #expect(MenuBarPresenter.present(state) != MenuBarPresenter.present(MenuBarState()))
    }
}

/// The menu prints its shortcuts, and a printed shortcut is a promise about which keys
/// do the thing. These are about the promise being kept — the clipboard's said ⇧⌘V in
/// the model while the app translated it to ⌘V, so the menu offered paste's own keys.
@Suite("What the menu's shortcuts say")
struct MenuBarShortcutTests {
    @Test("the clipboard is reachable from the menu, with its real shortcut")
    func clipboardShortcut() {
        let shown = MenuBarPresenter.present(MenuBarState())
        guard
            case .command(let clipboard)? = shown.items.first(where: {
                if case .command(let command) = $0 { return command.intent == .openClipboard }
                return false
            })
        else {
            Issue.record("the menu has no way to the clipboard")
            return
        }
        #expect(clipboard.title == "Clipboard")
        #expect(clipboard.shortcut?.key == "v")
        #expect(clipboard.shortcut?.modifiers == [.command, .shift])
    }

    /// Shift is the one that was missing, so it is named rather than left to the set
    /// comparison above: a test that only compares option sets passes just as happily
    /// when the value is right and the thing reading it ignores half of it.
    @Test("shift is a modifier this model can express")
    func shiftIsExpressible() {
        let both: MenuBarModifiers = [.command, .shift]
        #expect(both.contains(.shift))
        #expect(both.contains(.command))
        #expect(!both.contains(.option))
    }

    /// The app target translates these into AppKit flags by switching over `allCases`,
    /// which only stays honest while every case has a distinct one-modifier value. A
    /// duplicate here would silently bind two modifiers to one flag.
    @Test("every modifier is a distinct single value, and answers to itself")
    func everyModifierIsItsOwn() {
        let each = MenuBarModifier.allCases.map { MenuBarModifiers.one($0) }
        #expect(Set(each.map(\.rawValue)).count == MenuBarModifier.allCases.count)
        for modifier in MenuBarModifier.allCases {
            #expect(MenuBarModifiers.one(modifier).contains(modifier))
            for other in MenuBarModifier.allCases where other != modifier {
                #expect(!MenuBarModifiers.one(modifier).contains(other))
            }
        }
    }
}

/// Saying that an update is happening, which it never did before.
@Suite("Updating, in the menu bar")
struct MenuBarUpdateTests {
    private func line(_ progress: UpdateProgress) -> String {
        MenuBarPresenter.present(MenuBarState(updateProgress: progress)).statusLine
    }

    @Test("an install about to happen says so")
    func installingIsVisible() {
        #expect(line(.installing) == "Updating…")
    }

    /// The wait is the part that needs explaining. "Ready" with nothing happening for a
    /// minute looks stuck; saying what it waits for makes the pause legible.
    @Test("a staged update says what it is waiting for")
    func readyExplainsTheWait() {
        #expect(line(.readyToInstall).contains("when you pause"))
    }

    @Test("a download reports its progress, and copes with not knowing it yet")
    func downloading() {
        #expect(line(.downloading(fraction: 0.42)) == "Downloading update… 42%")
        #expect(line(.downloading(fraction: nil)) == "Downloading update…")
    }

    @Test("nothing happening says nothing about updates")
    func idleIsSilent() {
        #expect(line(.idle) == "Ready")
    }

    /// A failure is why the user opened the menu. An update is not a problem, so it does
    /// not get to hide one.
    @Test("a failure still outranks an update")
    func failureWins() {
        var state = MenuBarState(updateProgress: .installing)
        state.failure = FailurePresentation(
            headline: "Something went wrong", detail: nil, symbolName: "exclamationmark.triangle",
            severity: .blocking, placement: .menuBar, action: nil)
        #expect(MenuBarPresenter.present(state).statusLine == "Something went wrong")
    }

    /// Below a failure but above everything else: an update is about to take the app
    /// away, which outranks whatever it was otherwise doing.
    @Test("an update outranks the ordinary activity line")
    func updateOutranksActivity() {
        let state = MenuBarState(activity: .listening, updateProgress: .installing)
        #expect(MenuBarPresenter.present(state).statusLine == "Updating…")
    }

    @Test("VoiceOver reads it as a sentence")
    func spoken() {
        let spoken = MenuBarPresenter.present(MenuBarState(updateProgress: .installing))
            .accessibilityLabel
        #expect(spoken == "Uttrflow. Updating.")
    }
}
