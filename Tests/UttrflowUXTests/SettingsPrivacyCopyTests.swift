import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

// MARK: - Fixtures

/// Every page onboarding can draw, including the combinations no single run reaches,
/// so a page cannot be added and quietly left out of the sweep below.
private let everyOnboardingState: [OnboardingState] = {
    var states: [OnboardingState] = [
        OnboardingState(step: .welcome, detail: .reading),
        OnboardingState(step: .setup, detail: .reading),
        OnboardingState(step: .setup, detail: .installing(0.5)),
        OnboardingState(step: .setup, detail: .installFailed("It stopped.")),
        OnboardingState(step: .ready, detail: .reading),
    ]
    for step in [OnboardingStep.microphone, .accessibility] {
        states.append(OnboardingState(step: step, detail: .awaitingSystemSettings))
        for status in [PermissionStatus.notDetermined, .granted, .denied, .restricted] {
            states.append(OnboardingState(step: step, detail: .permission(status)))
        }
    }
    for readiness in OnboardingReadiness.allCases {
        states.append(OnboardingState(step: .ready, detail: .finishing(readiness)))
    }
    return states
}()

/// Everything the app says about what it keeps, gathered from the three screens that
/// say it: the privacy tab makes the promise, the history page restates it under the
/// list, and onboarding makes it before the user has dictated a word.
///
/// Every pane and every page, not the ones that happen to mention audio today: a claim
/// that reappears on some fifth screen is exactly the one nobody would think to add
/// here, so the sweep is over all of them.
private func everyUserFacingString() -> [String] {
    var strings: [String] = []

    // Every tab, and every shape the counts can be in: the sentences in front of a
    // destructive button are written per count, and the ones nobody sweeps are the ones
    // that get to say something untrue about what is kept.
    for personalisation in SettingsPersonalisationFixtures.every {
        for tab in SettingsTab.allCases {
            let pane = SettingsPresenter.pane(
                for: tab, settings: .default, capabilities: .everything,
                personalisation: personalisation)
            strings += [pane.title]
            strings += [pane.banner?.title, pane.banner?.message, pane.callout?.message]
                .compactMap(\.self)
            strings += pane.groups.compactMap(\.title)
            for row in pane.groups.flatMap(\.rows) {
                strings += [row.label, row.explanation, row.unavailability].compactMap(\.self)
                switch row.control {
                case .segmented(let options, _), .menu(let options, _):
                    strings += options.map(\.title)
                case .removal(let removal):
                    strings += [removal.title]
                    strings += [
                        removal.confirmation?.title, removal.confirmation?.message,
                        removal.confirmation?.confirmTitle, removal.confirmation?.cancelTitle,
                    ].compactMap(\.self)
                case .action(let title, _):
                    strings += [title]
                case .text(let value):
                    strings += [value]
                case .toggle, .anchorPicker, .shortcut, .tick, .applicationSwitch:
                    break
                }
            }
        }
    }

    for state in everyOnboardingState {
        let page = OnboardingPresenter.page(for: state, hotkey: .optionSpace)
        strings += [page.title, page.subtitle, page.accessibilityLabel]
        strings += [page.body, page.note?.text].compactMap(\.self)
        strings += page.buttons.map(\.title)
    }

    // With something in the list and with nothing, because the notice is drawn either
    // way and the empty states are their own sentences about what is held.
    let now = Date()
    let entry = HistoryEntry(id: UUID(), text: "Hello", when: now, applicationName: "Mail")
    for entries in [[entry], []] {
        let page = HistoryPresenter.page(for: HistorySnapshot(entries: entries, now: now))
        strings += [page.retentionNotice.sentence, page.retentionNotice.link.title]
        strings += [page.emptyState?.title, page.emptyState?.message].compactMap(\.self)
    }

    return strings
}

/// Roughly a sentence. Enough to keep a denial with the claim it denies, so that
/// "Recordings are never saved. The text is kept for 7 days." is read as two things.
private func sentences(of string: String) -> [String] {
    string.lowercased()
        .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

private func mentionsAudio(_ sentence: String) -> Bool {
    ["recording", "audio", "what you say", "your voice"].contains { sentence.contains($0) }
}

// MARK: - The promise

/// Uttrflow kept audio on disk for seven days in its copy and never once in its code.
/// The claim erred in the user's favour, which is why it survived four screens and a
/// design review — so what stops it coming back cannot be a reader noticing.
@Suite("What the app says it keeps is what it keeps")
struct SettingsPrivacyCopyTests {
    /// Words that put audio somewhere it can be found again.
    private static let storage = [
        "saved", "save", "stored", "store", "kept", "keep", "on disk", "written",
        "history", "deleted", "delete",
    ]

    /// The one way a sentence may pair audio with storage: by denying it. Struck out
    /// before the sentence is examined, so "recordings are never saved" reads as a
    /// sentence about recordings with nothing left in it about storing them.
    private static let denials = [
        "never saved", "not saved", "never kept", "not kept", "never stored",
        "not stored", "never written", "not written", "nothing is recorded",
    ]

    /// Audio lives in memory for the length of one dictation and is gone. A sentence
    /// that says otherwise — on any screen, in any wording — describes a product that
    /// does not exist, and over-promising in the user's favour is not a defence: it is
    /// what let the old wording stand.
    @Test("no sentence anywhere claims a recording is stored")
    func nothingClaimsAudioIsStored() {
        for string in everyUserFacingString() {
            for sentence in sentences(of: string) where mentionsAudio(sentence) {
                var remaining = sentence
                for denial in Self.denials {
                    remaining = remaining.replacingOccurrences(of: denial, with: "")
                }
                for word in Self.storage {
                    #expect(
                        !remaining.contains(word),
                        "“\(word)” claims audio is stored, in: \(sentence)")
                }
            }
        }
    }

    /// The wording that replaced the false one, in the one place it is written. Pinned
    /// so that softening it back towards "deleted after a while" has to be a deliberate
    /// edit to a test rather than a quiet edit to a string.
    @Test("the promise says audio is never written down, not that it is tidied up later")
    func thePromiseIsTheStrongerOne() {
        let promise = SettingsPresenter.privacyPromise
        #expect(promise.contains("Recordings are never saved"))
        #expect(!promise.lowercased().contains("recordings and transcripts are stored"))
    }

    /// Not absolutist. The speech model arrives over the network and a cloud engine may
    /// one day be offered, so a promise that Uttrflow never reaches out would be the next
    /// inaccuracy in the same place.
    @Test("the promise never claims the app stays off the network")
    func thePromiseDoesNotOverreachAboutTheNetwork() {
        let promise = SettingsPresenter.privacyPromise.lowercased()
        for claim in ["never connects", "no internet", "never online", "offline", "no network"] {
            #expect(!promise.contains(claim), "the promise claims “\(claim)”")
        }
    }

    /// One promise, one wording. Three screens saying the same thing three ways is a
    /// promise the user has to reconcile for themselves, and three wordings are how the
    /// old one drifted far enough for nobody to notice it was wrong.
    @Test("every screen denies keeping audio in the same words")
    func oneWordingEverywhere() {
        let denial = "Recordings are never saved"
        let history = HistoryPresenter.page(for: HistorySnapshot(entries: [], now: Date()))
        let microphone = OnboardingPresenter.page(
            for: OnboardingState(step: .microphone, detail: .permission(.notDetermined)),
            hotkey: .optionSpace)

        #expect(SettingsPresenter.privacyPromise.contains(denial))
        #expect(history.retentionNotice.sentence.contains(denial))
        #expect(microphone.body?.contains(denial) == true)
    }
}
