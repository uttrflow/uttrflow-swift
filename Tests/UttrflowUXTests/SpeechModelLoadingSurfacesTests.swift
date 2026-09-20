// Tests the home page, the menu bar and the clipboard panel while the speech model loads.
import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowUX

@Suite("Where a person would dictate, while the speech model loads")
struct SpeechModelLoadingSurfacesTests {
    /// The home page with every permission granted and the model at one point in its load.
    private func home(_ load: SpeechModelLoad?) -> HomePresentation {
        HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .granted, .accessibility: .granted],
                shortcut: "⌥Space", now: HistoryFixture.now, speechModel: load),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("the home page shows a loading card while the model loads, and puts the ring out")
    func homeShowsTheLoad() throws {
        let page = home(.loading(elapsed: .seconds(1)))
        let notice = try #require(page.speechModel)

        #expect(notice.isLoading)
        #expect(notice.title == "Loading the speech model…")
        #expect(notice.action == nil)
        #expect(
            notice.accessibilityLabel
                == "Loading the speech model. Dictation starts working as soon as it’s ready.")
        #expect(!page.status.isReady)
        #expect(page.status.text == "Loading speech model")
        #expect(page.nextStep == nil, "the load card is the only card while nothing else blocks dictation")
    }

    @Test("the home page's card gains the minutes only once the load has run on")
    func homeEstimateWaits() throws {
        let early = try #require(home(.loading(elapsed: .seconds(3))).speechModel)
        let late = try #require(home(.loading(elapsed: .seconds(90))).speechModel)

        #expect(!early.message.contains("minute"))
        #expect(late.message.contains("2–3 minutes"))
    }

    @Test("the card is gone once the model has loaded")
    func homeClearsWhenLoaded() {
        let page = home(nil)

        #expect(page.speechModel == nil)
        #expect(page.status == HomeStatus(text: "Ready", isReady: true))
        #expect(page.nextStep == nil)
    }

    @Test("a failed load shows a failed card with Download")
    func homeShowsTheFailure() throws {
        let page = home(.failed)
        let notice = try #require(page.speechModel)

        #expect(!notice.isLoading)
        #expect(notice.title == "The speech model didn’t load")
        #expect(notice.action == MainAction(title: "Download", intent: .recover(.downloadSpeechModel)))
        #expect(page.status.text == "Speech model didn’t load")
    }

    @Test("a missing permission outranks the load, since it is the thing to fix first")
    func permissionOutranksTheLoad() {
        let page = HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .denied], shortcut: "⌥Space", now: HistoryFixture.now,
                speechModel: .loading(elapsed: .seconds(1))),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)

        #expect(page.speechModel == nil)
        #expect(page.status.text == "Not ready")
    }

    @Test("readiness tells the load from the injected clock, and nothing once ready")
    func readinessTimesTheLoad() {
        let clock = ManualClock()
        let started = clock.now
        clock.advance(by: .seconds(12))
        let now = clock.now

        #expect(
            SpeechModelReadiness.loading.load(since: started, now: now) == .loading(elapsed: .seconds(12)))
        #expect(SpeechModelReadiness.loading.load(since: nil, now: now) == .loading(elapsed: .zero))
        #expect(SpeechModelReadiness.loadFailed.load(since: started, now: now) == .failed)
        #expect(SpeechModelReadiness.ready.load(since: started, now: now) == nil)
        #expect(SpeechModelReadiness.notInstalled.load(since: started, now: now) == .missing)
        #expect(
            SpeechModelReadiness.downloading(fractionCompleted: 0.5).load(since: started, now: now) == nil)
    }

    @Test("a missing model shows a card with Download, puts the ring out and invites no talking")
    func homeShowsTheMissingModel() throws {
        let page = home(.missing)
        let notice = try #require(page.speechModel)

        #expect(!notice.isLoading)
        #expect(notice.title == "The speech model isn’t downloaded")
        #expect(notice.action == MainAction(title: "Download", intent: .recover(.downloadSpeechModel)))
        #expect(page.status == HomeStatus(text: "Speech model not downloaded", isReady: false))
        #expect(page.subtitle == "Uttrflow cannot listen yet.")
    }

    /// The Dictation page with every permission granted, nothing dictated, and the model at one point.
    private func dictation(_ load: SpeechModelLoad?) -> DictationPresentation {
        DictationPresenter.page(
            for: DictationSnapshot(
                permissions: [.microphone: .granted, .accessibility: .granted],
                shortcut: "⌥Space", now: HistoryFixture.now, speechModel: load),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("the Dictation page says the model is missing in place of the invitation to talk")
    func dictationShowsTheMissingModel() throws {
        let empty = try #require(dictation(.missing).emptyState)

        #expect(empty.title == "The speech model isn’t downloaded")
        #expect(empty.action == MainAction(title: "Download", intent: .recover(.downloadSpeechModel)))
        #expect(!empty.message.contains("anywhere and talk"))
    }

    @Test("the Dictation page says a load is under way, with nothing to press")
    func dictationShowsTheLoad() throws {
        let empty = try #require(dictation(.loading(elapsed: .seconds(1))).emptyState)

        #expect(empty.title == "Loading the speech model…")
        #expect(empty.symbolName == "hourglass")
        #expect(empty.action == nil)
    }

    @Test("the Dictation page invites talking once the model is ready")
    func dictationInvitesOnceReady() throws {
        let empty = try #require(dictation(nil).emptyState)

        #expect(empty.message.contains("anywhere and talk"))
    }

    /// Two surfaces that disagree about whether dictation works leave the person to find out by trying.
    @Test(
        "home, the Dictation page and the menu bar agree on whether the model can dictate",
        arguments: [
            SpeechModelReadiness.notInstalled, .loading, .loadFailed, .ready,
        ])
    func surfacesAgree(readiness: SpeechModelReadiness) {
        let load = readiness.load(since: nil as ContinuousClock.Instant?, now: .now)
        let homeReady = home(load).status.isReady
        let dictationInvites = dictation(load).emptyState?.message.contains("anywhere and talk") == true
        let menuReady = MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: readiness))

        #expect(homeReady == (readiness == .ready))
        #expect(dictationInvites == homeReady)
        #expect(menuReady == homeReady)
        if let load {
            #expect(MenuBarPresenter.present(MenuBarState(speechModel: readiness)).statusLine != "Ready")
            #expect(home(load).status.text == load.status)
        }
    }

    @Test("the menu bar names a failed load rather than calling setup unfinished")
    func menuBarNamesTheFailure() {
        let menu = MenuBarPresenter.present(MenuBarState(speechModel: .loadFailed))

        #expect(menu.statusLine == "Speech model didn't load")
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: .loadFailed)))
    }

    @Test("the clipboard panel's microphone says loading, not downloading, during a load")
    func panelSaysLoading() {
        var snapshot = PanelFixture.panel()
        snapshot.dictation = .unavailable(.modelLoading)
        let mic = PanelPresenter.present(snapshot).microphone

        #expect(!mic.isEnabled)
        #expect(mic.label == "The speech model is still loading")
        #expect(mic.status == "Speech model still loading")
    }
}
