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

/// Uttrflow keeps a recording only until its words land, and for a day when they do not
/// so the dictation can be retried. Every sentence about audio has to say that, and no
/// sentence anywhere may say the audio goes further than this Mac.
@Suite("What the app says it keeps is what it keeps")
struct SettingsPrivacyCopyTests {
    /// Words that put audio somewhere it can be found again.
    private static let storage = [
        "saved", "save", "stored", "store", "kept", "keep", "on disk", "written",
        "history", "deleted", "delete",
    ]

    /// Words that would send audio off this Mac.
    private static let egress = ["upload", "sent", "send", "server", "cloud", "share"]

    /// A sentence that stores audio must say where, and that the storing ends.
    @Test("every sentence that keeps a recording keeps it on this Mac and says when it goes")
    func audioStaysOnThisMacAndGoes() {
        for string in everyUserFacingString() {
            for sentence in sentences(of: string) where mentionsAudio(sentence) {
                let stores = Self.storage.contains { sentence.contains($0) }
                guard stores, !sentence.contains("never saved") else { continue }
                #expect(sentence.contains("this mac"), "audio is kept somewhere unnamed, in: \(sentence)")
                #expect(
                    sentence.contains("deleted") || sentence.contains("until"),
                    "audio is kept with no end in sight, in: \(sentence)")
            }
        }
    }

    /// The one claim no wording may make, however the storage sentence is put.
    @Test("no sentence anywhere sends a recording off this Mac")
    func nothingSendsAudioAnywhere() {
        for string in everyUserFacingString() {
            for sentence in sentences(of: string) where mentionsAudio(sentence) {
                for word in Self.egress where sentence.contains(word) {
                    let denied = ["nothing", "never", "not "].contains { sentence.contains($0) }
                    #expect(denied, "“\(word)” sends audio somewhere, in: \(sentence)")
                }
            }
        }
    }

    /// Pinned so that softening it has to be a deliberate edit to a test rather than a
    /// quiet edit to a string.
    @Test("the promise says the audio is deleted as it becomes text, and kept a day only to retry")
    func thePromiseIsTheHonestOne() {
        let promise = SettingsPresenter.recordingsPromise
        #expect(promise.contains("deleted the moment it becomes text"))
        #expect(promise.contains("kept on this Mac for a day only"))
        #expect(promise.contains("retry"))
        #expect(SettingsPresenter.privacyPromise.hasPrefix(promise))
        #expect(!SettingsPresenter.privacyPromise.contains("Recordings are never saved"))
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

    /// One promise, one wording. Two screens saying the same thing two ways is a promise
    /// the user has to reconcile for themselves.
    @Test("settings and onboarding describe the recordings in the same words")
    func oneWordingEverywhere() {
        let microphone = OnboardingPresenter.page(
            for: OnboardingState(step: .microphone, detail: .permission(.notDetermined)),
            hotkey: .optionSpace)
        #expect(SettingsPresenter.privacyPromise.contains(SettingsPresenter.recordingsPromise))
        #expect(microphone.body?.contains(SettingsPresenter.recordingsPromise) == true)
    }
}
