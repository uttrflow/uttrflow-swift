import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

@Suite("The main window's shared vocabulary")
struct MainPresentationTests {
    @Test("the window is named once")
    func windowTitle() {
        #expect(MainPresenter.windowTitle == "Uttrflow")
    }

    /// Every recovery a failure can offer has a verb here. A missing one would leave a
    /// button with no title on whichever page happened to hit that failure.
    @Test("every recovery action has a button title")
    func everyRecoveryHasATitle() {
        let every: [RecoveryAction] =
            SystemSettingsPane.allCases.map { .openSystemSettings($0) }
            + [.retry, .downloadSpeechModel, .pasteManually, .showRecentDictations]
        for action in every {
            #expect(!MainPresenter.title(for: action).isEmpty)
        }
    }

    @Test("each recovery reads as the verb the failure already used")
    func recoveryTitles() {
        #expect(MainPresenter.title(for: .openSystemSettings(.microphone)) == "Open Settings")
        #expect(MainPresenter.title(for: .retry) == "Try Again")
        #expect(MainPresenter.title(for: .downloadSpeechModel) == "Download")
        #expect(MainPresenter.title(for: .pasteManually) == "Paste")
        #expect(MainPresenter.title(for: .showRecentDictations) == "Show Recent")
    }

    @Test("an action is identified by its title")
    func actionIdentity() {
        let action = MainAction(title: "Undo", intent: .undoCorrection(UUID()))
        #expect(action.id == "Undo")
        #expect(action.symbolName == nil)
        #expect(!action.isDestructive)
    }

    @Test("an empty state carries nothing extra unless it is given some")
    func emptyStateDefaults() {
        let state = MainEmptyState(symbolName: "clock", title: "Nothing", message: "Nothing yet.")
        #expect(state.action == nil)
        #expect(state.chips.isEmpty)
        #expect(state.progress == nil)
        #expect(state.footnote == nil)
    }

    @Test("a statistic is identified by what it counts")
    func statisticIdentity() {
        let figure = MainStatistic(value: "3", caption: "Dictations")
        #expect(figure.id == "Dictations")
        #expect(figure.comment == nil)
        #expect(figure.meters.isEmpty)
    }
}

@Suite("Large numbers, read at a glance")
struct MainCompactFormattingTests {
    private let locale = Locale(identifier: "en_GB")

    @Test("small counts are written out in full")
    func small() {
        #expect(MainFormatting.compact(0, locale: locale) == "0")
        #expect(MainFormatting.compact(964, locale: locale) == "964")
        #expect(MainFormatting.compact(999, locale: locale) == "999")
    }

    @Test("thousands and millions are shortened")
    func shortened() {
        #expect(MainFormatting.compact(1_000, locale: locale) == "1K")
        #expect(MainFormatting.compact(12_400, locale: locale) == "12.4K")
        #expect(MainFormatting.compact(242_000, locale: locale) == "242K")
        #expect(MainFormatting.compact(1_200_000, locale: locale) == "1.2M")
    }

    /// Rounded down, never to nearest. `12.4K` from 12,499 is a floor the user can trust;
    /// `12.5K` would be a number of words they never actually said.
    @Test("never rounds up to a figure that was not reached")
    func roundsDown() {
        #expect(MainFormatting.compact(12_499, locale: locale) == "12.4K")
        #expect(MainFormatting.compact(1_999, locale: locale) == "1.9K")
        #expect(MainFormatting.compact(999_999, locale: locale) == "999.9K")
    }

    /// "12K" reads better than "12.0K", and the trailing zero says nothing.
    @Test("a whole number of thousands carries no decimal")
    func noTrailingZero() {
        #expect(MainFormatting.compact(12_000, locale: locale) == "12K")
        #expect(MainFormatting.compact(3_000_000, locale: locale) == "3M")
    }
}

@Suite("The pages of the main window")
struct MainPageTests {
    /// The order is the sidebar's, minus Settings — which is a window rather than a
    /// page. Pinned because the sidebar reads it and a tidy into alphabetical order
    /// would silently rearrange the window.
    @Test("the pages are in sidebar order")
    func order() {
        #expect(
            MainTab.allCases == [
                .home,
                .dictation, .history, .dictionary, .corrections, .insights, .snippets,
                .style, .diagnostics, .account,
            ])
    }

    /// Stored, so a rename of the case must not change what a saved window position
    /// means.
    @Test("each page has a stable stored name")
    func rawValues() {
        #expect(MainTab.dictation.rawValue == "dictation")
        #expect(MainTab.account.rawValue == "account")
        #expect(MainTab(rawValue: "insights") == .insights)
    }
}

@Suite("What stands in the way of using the app")
struct MainObstructionTests {
    @Test("nothing stands in the way when both permissions are granted")
    func nothingBlocked() {
        #expect(
            MainPresenter.obstruction(in: [.microphone: .granted, .accessibility: .granted])
                == nil)
    }

    /// Absent is not the same as refused. A permission nobody has asked about yet must
    /// not be reported as withheld.
    @Test("a permission that has not been checked is not an obstruction")
    func unknownIsSilent() {
        #expect(MainPresenter.obstruction(in: [:]) == nil)
    }

    @Test("a permission nobody has been asked for invites setting up")
    func notDeterminedOffersSetUp() {
        let blocked = MainPresenter.obstruction(in: [.microphone: .notDetermined])
        #expect(blocked?.symbolName == "hand.raised")
        #expect(blocked?.title == "Microphone has not been set up")
        #expect(blocked?.action?.intent == .go(.onboarding))
    }

    @Test("a refused permission says so and offers the way to fix it")
    func deniedOffersSettings() {
        let blocked = MainPresenter.obstruction(in: [.accessibility: .denied])
        #expect(blocked?.symbolName == "exclamationmark.triangle")
        #expect(blocked?.title == "Accessibility access is off")
        #expect(blocked?.action?.intent == .recover(.openSystemSettings(.accessibility)))
    }

    /// A device policy is not something the user can undo, so there is no button to
    /// pretend otherwise with.
    @Test("a restricted microphone offers nothing to press")
    func restrictedOffersNothing() {
        let blocked = MainPresenter.obstruction(in: [.microphone: .restricted])
        #expect(blocked?.title == "Microphone access is off")
        #expect(blocked?.action == nil)
    }

    /// The microphone comes first because nothing can be heard without it, so a Mac
    /// missing both is given one thing to fix rather than two.
    @Test("only the first thing in the way is reported")
    func onlyTheFirst() {
        let blocked = MainPresenter.obstruction(
            in: [.microphone: .denied, .accessibility: .denied])
        #expect(blocked?.title == "Microphone access is off")
    }

    @Test("each kind and status pairs with the failure that describes it")
    func failureMapping() {
        #expect(
            MainPresenter.permissionError(for: .microphone, status: .restricted)
                == .microphoneRestricted)
        #expect(
            MainPresenter.permissionError(for: .microphone, status: .denied) == .microphoneDenied)
        #expect(
            MainPresenter.permissionError(for: .accessibility, status: .denied)
                == .accessibilityNotTrusted)
    }
}

@Suite("Numbers as every page writes them")
struct MainFormattingTests {
    @Test("a machine timing is written to the hundredth")
    func seconds() {
        #expect(MainFormatting.seconds(.milliseconds(1_250)) == "1.25s")
    }

    /// "0.00s" reads as "not measured" when it means "too quick to matter".
    @Test("anything faster than a hundredth is reported as being faster")
    func tinyDurations() {
        #expect(MainFormatting.seconds(.milliseconds(2)) == "under 0.01s")
    }

    /// A person is timed in whole seconds. Hundredths matter when the app is being
    /// measured and are noise when a speaker is.
    @Test("how long somebody talked is whole seconds")
    func spoken() {
        #expect(MainFormatting.spoken(.milliseconds(11_400)) == "11s")
        #expect(MainFormatting.spoken(.milliseconds(11_600)) == "12s")
        #expect(MainFormatting.spoken(.seconds(-3)) == "0s")
    }

    @Test("bytes are written the way the Finder writes them")
    func bytes() {
        #expect(!MainFormatting.bytes(2_000_000, locale: HistoryFixture.locale).isEmpty)
    }

    @Test("a fraction is written as a percentage to one decimal place")
    func percentage() {
        #expect(MainFormatting.percentage(0.972, locale: HistoryFixture.locale) == "97.2%")
    }

    @Test("a count agrees with the thing it counts")
    func counts() {
        #expect(MainFormatting.count(1, "day", "days") == "1 day")
        #expect(MainFormatting.count(0, "day", "days") == "0 days")
        #expect(MainFormatting.count(7, "day", "days") == "7 days")
    }

    /// One definition of a word, so a row and a total cannot disagree about the length
    /// of the same sentence.
    @Test("words are whitespace-separated runs")
    func words() {
        #expect(MainFormatting.words(in: "hello there  friend") == 3)
        #expect(MainFormatting.words(in: "   ") == 0)
        #expect(MainFormatting.words(in: "one\ntwo") == 2)
    }

    @Test("a time of day is written as a clock reads it")
    func time() {
        #expect(!MainFormatting.time(HistoryFixture.now, locale: HistoryFixture.locale).isEmpty)
    }

    @Test("a recent day is named the way somebody would say it")
    func days() {
        let calendar = HistoryFixture.calendar
        let now = HistoryFixture.now
        func day(_ offset: Int) -> String {
            MainFormatting.day(
                now.addingTimeInterval(Double(-offset) * 86_400), now: now, calendar: calendar,
                locale: HistoryFixture.locale)
        }
        #expect(day(0) == "Today")
        #expect(day(1) == "Yesterday")
        // Within the past week, the weekday is clearer than the date.
        #expect(day(3) == "Thursday")
        // Beyond it, a bare weekday would be ambiguous, so the date is given.
        #expect(day(20) == "26 May")
    }
}
