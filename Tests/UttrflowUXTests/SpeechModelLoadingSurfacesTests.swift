// Tests the home page, the menu bar and the clipboard panel while the speech model downloads or loads.
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

    @Test("the hero says the model is getting ready, with a sliding bar and the start pill dimmed")
    func homeShowsTheLoad() throws {
        let page = home(.loading(elapsed: .seconds(1)))
        let status = try #require(page.hero.modelStatus)

        #expect(status.title == "Getting ready…")
        #expect(status.subtitle == "Loading the speech model")
        #expect(status.tone == .dictation)
        #expect(status.progress == .sliding)
        #expect(status.action == nil, "the dimmed start pill stands where a button would")
        #expect(!page.hero.canStart)
        #expect(
            status.accessibilityLabel
                == "Loading the speech model. Dictation starts working as soon as it’s ready.")
        #expect(!page.status.isReady)
        #expect(page.status.text == "Loading speech model")
        #expect(page.nextStep == nil, "the hero is the only place the load is shown")
    }

    @Test("the hero gains the time left and a bar filled to the estimate only once the load has run on")
    func homeEstimateWaits() throws {
        let early = try #require(home(.loading(elapsed: .seconds(3))).hero.modelStatus)
        let late = try #require(home(.loading(elapsed: .seconds(90))).hero.modelStatus)

        #expect(!early.title.contains("min"))
        #expect(!early.subtitle.contains("min"))
        #expect(early.progress == .sliding)
        #expect(late.title == "Getting ready · about 1 min left")
        #expect(late.subtitle == "Only after a restart. Everything else already works.")
        #expect(late.progress == .fraction(SpeechModelLoadEstimate(elapsed: .seconds(90)).fraction))
        #expect(late.tone == .dictation)
        #expect(late.action == nil)
        #expect(
            late.accessibilityLabel
                == "Getting ready, about 1 minute left. Only after a restart. Everything else already works.")
    }

    @Test("the hero holds its bar below full once the typical load time has passed")
    func homeHolds() throws {
        let status = try #require(
            home(.loading(elapsed: SpeechModelLoadEstimate.typicalColdLoad + .seconds(30))).hero.modelStatus)

        #expect(status.title == "Almost ready…")
        #expect(status.progress == .fraction(SpeechModelLoadEstimate.ceiling))
        #expect(
            status.accessibilityLabel == "Almost ready. Only after a restart. Everything else already works.")
    }

    @Test("the hero carries the load's start, so its own clock moves the estimate without a window redraw")
    func homeCarriesTheStart() throws {
        let status = try #require(home(.loading(elapsed: .seconds(30))).hero.modelStatus)
        let since = try #require(status.loadingSince)
        let later = HomeModelStatus.loading(since: since, at: since.addingTimeInterval(90))

        #expect(since == HistoryFixture.now.addingTimeInterval(-30))
        #expect(later.title == "Getting ready · about 1 min left")
        #expect(later.progress == .fraction(SpeechModelLoadEstimate(elapsed: .seconds(90)).fraction))
        #expect(later.loadingSince == since)
        #expect(HomeModelStatus.loading(since: since, at: since.addingTimeInterval(1)).progress == .sliding)
    }

    @Test("only a load under way carries a start; a failed, damaged, missing or downloading model does not")
    func onlyALoadCarriesAStart() throws {
        for load in [SpeechModelLoad.failed, .broken, .missing] {
            #expect(try #require(home(load).hero.modelStatus).loadingSince == nil)
        }
        #expect(try #require(home(downloading: 0.42).hero.modelStatus).loadingSince == nil)
    }

    @Test("the menu bar says the same time left as the hero, over a bar filled to the estimate")
    func menuBarGivesTheEstimate() throws {
        let state = MenuBarState(speechModel: .loading, speechLoadElapsed: .seconds(90))
        let menu = MenuBarPresenter.present(state)
        let hero = try #require(home(.loading(elapsed: .seconds(90))).hero.modelStatus)

        #expect(menu.statusLine == "Getting ready · about 1 min left")
        #expect(menu.statusLine == hero.title)
        #expect(
            menu.header
                == .status(
                    MenuBarStatus(
                        title: "Getting ready · about 1 min left", detail: "Loading the speech model",
                        progress: .fraction(SpeechModelLoadEstimate(elapsed: .seconds(90)).fraction))))
        #expect(!MenuBarPresenter.canStartDictation(in: state))
    }

    @Test("the menu bar keeps its sliding bar and no minutes through a load's first seconds")
    func menuBarWaitsForTheEstimate() {
        let menu = MenuBarPresenter.present(
            MenuBarState(speechModel: .loading, speechLoadElapsed: .seconds(4)))

        #expect(menu.statusLine == "Getting ready…")
        #expect(
            menu.header
                == .status(
                    MenuBarStatus(
                        title: "Getting ready…", detail: "Loading the speech model", progress: .indeterminate)
                ))
    }

    @Test("the menu bar ignores a load time once the model is ready")
    func menuBarIgnoresElapsedWhenReady() {
        let menu = MenuBarPresenter.present(
            MenuBarState(speechModel: .ready, speechLoadElapsed: .seconds(90)))

        #expect(menu.statusLine == "Ready")
    }

    @Test("the waveform comes back once the model has loaded")
    func homeClearsWhenLoaded() {
        let page = home(nil)

        #expect(page.hero.modelStatus == nil)
        #expect(page.hero.canStart)
        #expect(page.status == HomeStatus(text: "Ready", isReady: true))
        #expect(page.nextStep == nil)
    }

    @Test("a failed load says nothing was lost and offers an amber Try again that loads it again")
    func homeShowsTheFailure() throws {
        let page = home(.failed)
        let status = try #require(page.hero.modelStatus)

        #expect(status.title == "Speech model didn’t load")
        #expect(status.subtitle == "Nothing was lost. Try loading it again.")
        #expect(status.tone == .warning)
        #expect(status.progress == nil)
        #expect(status.action == MainAction(title: "Try again", intent: .recover(.retry)))
        #expect(status.actionTone == .warning)
        #expect(page.status.text == "Speech model didn’t load")
    }

    @Test("a damaged model offers an amber Download again, not another reload")
    func homeShowsTheDamage() throws {
        let page = home(.broken)
        let status = try #require(page.hero.modelStatus)

        #expect(status.title == "Speech model is damaged")
        #expect(status.subtitle == "Download it again to repair it.")
        #expect(status.tone == .warning)
        #expect(
            status.action == MainAction(title: "Download again", intent: .recover(.downloadSpeechModel)))
        #expect(page.status.text == "Speech model is damaged")
    }

    /// A failed load reloads once; a second failure or missing files turn every surface to a download.
    @Test(
        "Home, the menu bar and Diagnostics offer the same fix for the model's state",
        arguments: [
            (SpeechModelReadiness.loadFailed, RecoveryAction.retry),
            (.loadFailedAgain, .downloadSpeechModel),
            (.incomplete, .downloadSpeechModel),
            (.notInstalled, .downloadSpeechModel),
        ])
    func everySurfaceAgrees(readiness: SpeechModelReadiness, fix: RecoveryAction) throws {
        let load = try #require(readiness.load(since: nil as ContinuousClock.Instant?, now: .now))
        #expect(readiness.recovery == fix)
        #expect(load.recovery == fix)

        #expect(try #require(home(load).hero.modelStatus).action?.intent == .recover(fix))

        guard case .status(let menu) = MenuBarPresenter.present(MenuBarState(speechModel: readiness)).header
        else {
            Issue.record("the menu bar shows no status for \(readiness)")
            return
        }
        #expect(menu.action?.intent == .recover(fix))

        let presence = DiagnosticsModelPresence(
            isInstalled: readiness == .loadFailed || readiness == .loadFailedAgain, bytesOnDisk: nil,
            isMultilingual: true)
        let diagnostics = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(speechModel: presence, speechReadiness: readiness))
        #expect(diagnostics.storage.first?.action?.intent == .recover(fix))
        #expect(diagnostics.summary.action?.intent == .recover(fix))
    }

    @Test("a completed load reports readiness from the result and whether its model remains installed")
    func loadResultAndInstallationDetermineReadiness() {
        #expect(SpeechModelReadiness.afterLoad(isReady: true, isInstalled: true) == .ready)
        #expect(SpeechModelReadiness.afterLoad(isReady: true, isInstalled: false) == .ready)
        #expect(SpeechModelReadiness.afterLoad(isReady: false, isInstalled: true) == .loadFailed)
        #expect(SpeechModelReadiness.afterLoad(isReady: false, isInstalled: false) == .notInstalled)
    }

    @Test("a first failed load offers a reload; a failed reload offers a download instead")
    func secondFailureOffersADownload() {
        let first = SpeechModelReadiness.settled(
            isReady: false, isInstalled: true, isIncomplete: false, failedBefore: false)
        let second = SpeechModelReadiness.settled(
            isReady: false, isInstalled: true, isIncomplete: false, failedBefore: true)

        #expect(first == .loadFailed)
        #expect(first.recovery == .retry)
        #expect(second == .loadFailedAgain)
        #expect(second.recovery == .downloadSpeechModel)
    }

    @Test("an incomplete folder counts as not installed, and says it needs downloading again")
    func incompleteFolderIsNotInstalled() {
        let settled = SpeechModelReadiness.settled(
            isReady: false, isInstalled: false, isIncomplete: true, failedBefore: false)

        #expect(settled == .incomplete)
        #expect(settled.recovery == .downloadSpeechModel)
        #expect(settled.load(since: nil as ContinuousClock.Instant?, now: .now) == .broken)
        #expect(
            SpeechModelReadiness.settled(
                isReady: false, isInstalled: false, isIncomplete: false, failedBefore: true)
                == .notInstalled)
        #expect(
            SpeechModelReadiness.settled(
                isReady: true, isInstalled: true, isIncomplete: false, failedBefore: true)
                == .ready)
    }

    @Test("a missing permission keeps its card and still leaves the model's state in the hero")
    func permissionAndLoadBothShow() throws {
        let page = HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .denied], shortcut: "⌥Space", now: HistoryFixture.now,
                speechModel: .loading(elapsed: .seconds(1))),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)

        #expect(page.nextStep != nil)
        #expect(page.status.text == "Not ready")
        #expect(try #require(page.hero.modelStatus).title == "Getting ready…")
        #expect(!page.hero.canStart)
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

    @Test("a missing model offers a teal Download speech model, puts the ring out and invites no talking")
    func homeShowsTheMissingModel() throws {
        let page = home(.missing)
        let status = try #require(page.hero.modelStatus)

        #expect(status.title == "Speech model not installed")
        #expect(status.subtitle == "Dictation needs it · works offline after")
        #expect(status.tone == .warning)
        #expect(
            status.action
                == MainAction(title: "Download speech model", intent: .recover(.downloadSpeechModel)))
        #expect(status.actionTone == .dictation)
        #expect(page.status == HomeStatus(text: "Speech model not downloaded", isReady: false))
        #expect(page.subtitle == "Uttrflow cannot listen yet.")
    }

    /// The home page with every permission granted while the model downloads.
    private func home(downloading fraction: Double) -> HomePresentation {
        HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .granted, .accessibility: .granted],
                shortcut: "⌥Space", now: HistoryFixture.now, speechDownload: fraction),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("a download shows its percentage, a bar filled to it, and the start pill dimmed")
    func homeShowsTheDownload() throws {
        let page = home(downloading: 0.42)
        let status = try #require(page.hero.modelStatus)

        #expect(status.title == "Setting up… 42%")
        #expect(status.subtitle == "Downloading the speech model")
        #expect(status.tone == .dictation)
        #expect(status.progress == .fraction(0.42))
        #expect(status.action == nil)
        #expect(status.accessibilityLabel == "Setting up. Downloading the speech model, 42 percent.")
        #expect(!page.hero.canStart)
        #expect(page.status == HomeStatus(text: "Setting up… 42%", isReady: false))
        #expect(page.subtitle == "Uttrflow cannot listen yet.")
    }

    @Test("a download with a known size says how much has arrived")
    func downloadCountsTheBytes() {
        let status = HomeModelStatus.downloading(0.42, bytes: 1_400_000_000)
        #expect(status.subtitle == "Downloading the speech model · 588 MB of 1.4 GB")
        #expect(HomeModelStatus.downloading(1.4, bytes: 1_000_000).subtitle.hasSuffix("1 MB of 1 MB"))
    }

    @Test("a download's bar never runs past either end")
    func downloadIsClamped() {
        #expect(HomeModelStatus.downloading(1.4).progress == .fraction(1))
        #expect(HomeModelStatus.downloading(1.4).title == "Setting up… 100%")
        #expect(HomeModelStatus.downloading(-0.2).progress == .fraction(0))
    }

    @Test("a download under way outranks a load that has not started")
    func downloadOutranksTheLoad() throws {
        let snapshot = HomeSnapshot(
            shortcut: "⌥Space", now: HistoryFixture.now, speechModel: .missing, speechDownload: 0.1)

        #expect(try #require(snapshot.modelStatus).title == "Setting up… 10%")
    }

    @Test("readiness gives the download's share, zero while unmeasured, and nothing otherwise")
    func readinessGivesTheDownload() {
        #expect(SpeechModelReadiness.downloading(fractionCompleted: 0.3).download == 0.3)
        #expect(SpeechModelReadiness.downloading(fractionCompleted: nil).download == 0)
        #expect(SpeechModelReadiness.ready.download == nil)
        #expect(SpeechModelReadiness.loading.download == nil)
        #expect(SpeechModelReadiness.notInstalled.download == nil)
    }

    @Test("home and the menu bar say the same words during a download")
    func downloadAgreesWithTheMenuBar() {
        let readiness = SpeechModelReadiness.downloading(fractionCompleted: 0.42)
        let menu = MenuBarPresenter.present(MenuBarState(speechModel: readiness))

        #expect(home(downloading: 0.42).status.text == menu.statusLine)
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: readiness)))
    }

    /// Two surfaces that disagree about whether dictation works leave the person to find out by trying.
    @Test(
        "home and the menu bar agree on whether the model can dictate",
        arguments: [
            SpeechModelReadiness.notInstalled, .loading, .loadFailed, .ready,
        ])
    func surfacesAgree(readiness: SpeechModelReadiness) {
        let load = readiness.load(since: nil as ContinuousClock.Instant?, now: .now)
        let homeReady = home(load).status.isReady
        let menuReady = MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: readiness))

        #expect(homeReady == (readiness == .ready))
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

    @Test("the hero blurs behind the setup ring only while setup runs with nothing to press")
    func heroWaitsOnlyWhileSetupRuns() throws {
        #expect(try #require(home(.loading(elapsed: .seconds(1))).hero.modelStatus).isWaiting)
        #expect(HomeModelStatus.downloading(0.4).isWaiting)
        #expect(!HomeModelStatus.load(.failed).isWaiting, "a failed load keeps its Try again button in view")
        #expect(!HomeModelStatus.missing(bytes: nil).isWaiting)
    }
}
