import Foundation
import Testing
import UttrflowAccount
import UttrflowCore
import UttrflowPredict
import UttrflowSettings

@testable import UttrflowUX

/// ``SessionGate`` and ``SessionSurfaces``: with no session nothing opens but sign-in, and nothing runs.
@Suite("Nothing without a session")
struct SessionGateTests {
    /// Every place a request can name, so a new page cannot slip past the gate unlisted.
    static let everyDestination: [UttrflowUX.AppLocation] =
        [.onboarding] + SettingsTab.allCases.map { .settings($0) } + MainTab.allCases.map { .main($0) }

    @Test("only being signed out is not a session; an aged-out entitlement still is")
    func onlyRefusedIsSignedOut() {
        for access in DictationAccess.allCases {
            #expect(SessionGate.isSignedIn(access) == (access != .refused), "\(access)")
        }
    }

    @Test("signed out, every destination opens sign-in instead", arguments: everyDestination)
    func signedOutRoutesToSignIn(destination: UttrflowUX.AppLocation) {
        #expect(SessionGate.route(destination, isSignedIn: false) == .onboarding)
    }

    @Test("signed in, every destination opens where it asked", arguments: everyDestination)
    func signedInRoutesThrough(destination: UttrflowUX.AppLocation) {
        #expect(SessionGate.route(destination, isSignedIn: true) == destination)
    }

    @Test("signed out, the menu runs Quit and nothing else")
    func signedOutMenuRunsOnlyQuit() {
        let intents: [MenuBarIntent] = [
            .startDictation, .stopDictation, .recover(.retry), .insertRecent(id: UUID()),
            .copyRecent(id: UUID()), .insertClip(id: UUID()), .copyClip(id: UUID()),
            .open(.main(.home)), .open(.settings(.general)), .open(.onboarding), .openClipboard,
            .setFeature(.dictation, isOn: false),
        ]
        for intent in intents {
            #expect(!SessionGate.permits(intent, isSignedIn: false), "\(intent)")
            #expect(SessionGate.permits(intent, isSignedIn: true), "\(intent)")
        }
        #expect(SessionGate.permits(.quit, isSignedIn: false))
    }

    @Test("the signed-out menu offers Sign In and Quit, and no dictation, clip or switch")
    func signedOutMenuOffersOnlySignInAndQuit() {
        let menu = SessionGate.signedOutMenu
        #expect(menu.commands.map(\.intent) == [.open(.onboarding), .open(.onboarding), .quit])
        #expect(menu.buttons.isEmpty)
        #expect(menu.clips.isEmpty)
        #expect(menu.lastDictation == nil)
    }

    @Test("signed out, nothing runs however the switches are set")
    func signedOutRunsNothing() {
        var settings = Settings(
            showsFloatingButton: true, suggestions: SuggestionPreferences(isEnabled: true))
        settings.dictationEnabled = true
        settings.clipboardEnabled = true
        let surfaces = SessionSurfaces(isSignedIn: false, settings: settings)
        #expect(!surfaces.listensForDictation)
        #expect(surfaces.claimedShortcuts.isEmpty)
        #expect(!surfaces.watchesTheClipboard)
        #expect(!surfaces.completesWhatIsTyped)
        #expect(!surfaces.showsTheFloatingButton)
    }

    @Test("signed in, each surface follows its own switch")
    func signedInFollowsTheSettings() {
        var settings = Settings(
            showsFloatingButton: true, suggestions: SuggestionPreferences(isEnabled: true))
        settings.dictationEnabled = true
        settings.clipboardEnabled = true
        let on = SessionSurfaces(isSignedIn: true, settings: settings)
        #expect(on.listensForDictation)
        #expect(on.claimedShortcuts == ShortcutRegistry.claimed(in: settings).map(\.action))
        #expect(on.claimedShortcuts.contains(ShortcutAction.clipboard))
        #expect(on.watchesTheClipboard)
        #expect(on.completesWhatIsTyped)
        #expect(on.showsTheFloatingButton)

        settings.dictationEnabled = false
        settings.clipboardEnabled = false
        settings.showsFloatingButton = false
        settings.suggestions = SuggestionPreferences(isEnabled: false)
        let off = SessionSurfaces(isSignedIn: true, settings: settings)
        #expect(!off.listensForDictation)
        #expect(!off.claimedShortcuts.contains(ShortcutAction.clipboard))
        #expect(!off.watchesTheClipboard)
        #expect(!off.completesWhatIsTyped)
        #expect(!off.showsTheFloatingButton)
    }
}
