// Tests that every way into the app meets the sign-in gate, with no window put on screen.

import AppKit
import Foundation
import Synchronization
import Testing
import UttrflowAccount
import UttrflowCore
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

/// An app over a held session that draws nothing, so the gate's answer is read rather than seen.
@MainActor
private func app(signedIn: Bool, in sandbox: borrowing Sandbox) -> (AppDelegate, HeldSession) {
    let session = HeldSession(signedIn: signedIn)
    let app = AppDelegate(container: sandbox.root, account: session.layer)
    app.drawsWindows = false
    return (app, session)
}

/// Every place a request can name.
private let everyDestination: [UttrflowUX.AppLocation] =
    [.onboarding] + SettingsTab.allCases.map { .settings($0) } + MainTab.allCases.map { .main($0) }

/// Every menu item but Quit, which would end the test run.
private let everyMenuIntentButQuit: [MenuBarIntent] = [
    .startDictation, .stopDictation, .recover(.retry), .recover(.showHistory),
    .recover(.retryFromRecording), .insertRecent(id: UUID()), .copyRecent(id: UUID()),
    .insertClip(id: UUID()), .copyClip(id: UUID()), .open(.main(.home)), .open(.main(.account)),
    .open(.settings(.general)), .open(.onboarding), .openClipboard,
    .setFeature(.dictation, isOn: false),
]

@MainActor
@Suite("Signed out, only sign-in opens", .serialized)
struct SignedOutGateTests {
    @Test("a request for any page or tab opens sign-in instead", arguments: everyDestination)
    func everyDestinationOpensSignIn(destination: UttrflowUX.AppLocation) {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: false, in: sandbox)

        app.carryOut(MainIntent.go(destination))

        #expect(app.lastOpened == .onboarding)
        #expect(app.mainWindow == nil)
    }

    @Test("the Dock icon, the Window and app menus, ⌘, and Help all open sign-in")
    func systemEntryPointsOpenSignIn() {
        let sandbox = Sandbox()
        let entries: [(String, @MainActor (AppDelegate) -> Void)] = [
            ("Dock reopen", { _ = $0.applicationShouldHandleReopen(.shared, hasVisibleWindows: false) }),
            ("Window ▸ Uttrflow", { $0.showMainWindowFromMenu(nil) }),
            ("Settings… ⌘,", { $0.showSettingsFromMenu(nil) }),
            ("Help", { $0.showDiagnosticsFromMenu(nil) }),
        ]
        for (name, enter) in entries {
            let (app, _) = app(signedIn: false, in: sandbox)
            enter(app)
            #expect(app.lastOpened == .onboarding, "\(name)")
            #expect(app.mainWindow == nil, "\(name)")
        }
    }

    @Test(
        "every menu bar item but Quit asks for sign-in and does nothing else",
        arguments: everyMenuIntentButQuit)
    func menuItemsAskForSignIn(intent: MenuBarIntent) {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: false, in: sandbox)

        app.carryOut(intent)

        #expect(app.lastOpened == .onboarding)
        #expect(!app.isQuickPanelOpen)
    }

    @Test("the menu bar offers only Sign In and Quit, and a click on it asks for sign-in")
    func menuBarIsLocked() {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: false, in: sandbox)

        app.followSession()

        #expect(app.menuBarPresentation == SessionGate.signedOutMenu)
    }

    @Test("no shortcut is held, the clipboard panel stays shut, and nothing listens")
    func nothingListens() async {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: false, in: sandbox)

        app.followSession()
        await app.perform(.clipboard)
        await app.perform(.pasteLastTranscript)
        await app.perform(.copyLastTranscript)

        #expect(app.armedShortcuts.isEmpty)
        #expect(!app.isQuickPanelOpen)
        #expect(!app.isWatchingTheClipboard)
        #expect(!app.isFloatingButtonShown)
        #expect(!app.surfaces.listensForDictation)
        #expect(!app.surfaces.completesWhatIsTyped)
    }

    @Test("a Mac that kept the retired Mac-account record and has no session opens sign-in")
    func upgradeFromTheMacAccountOpensSignIn() {
        let sandbox = Sandbox()
        let storage = KeyedBytes()
        storage.set(Data(#"{"name":"Sam","since":0}"#.utf8), forKey: RetiredLocalAccount.key)
        let service = InMemoryAuthenticationService()
        let app = AppDelegate(
            container: sandbox.root,
            account: OnboardingAccountLayer(
                authentication: service,
                profiles: UserDefaultsProfileCache(storage: storage, verifier: service.verifier)))
        app.drawsWindows = false

        RetiredLocalAccount.forget(in: storage)
        app.showMainWindowFromMenu(nil)

        #expect(!app.isSignedIn)
        #expect(app.lastOpened == .onboarding)
        #expect(storage.data(forKey: RetiredLocalAccount.key) == nil)
    }
}

@MainActor
@Suite("Signed in, every way in opens", .serialized)
struct SignedInGateTests {
    @Test("a request for any page or tab opens where it asked", arguments: everyDestination)
    func everyDestinationOpens(destination: UttrflowUX.AppLocation) {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: true, in: sandbox)

        app.carryOut(MainIntent.go(destination))

        #expect(app.lastOpened == destination)
    }

    @Test("the Dock icon, the Window and app menus, ⌘, and Help open their own windows")
    func systemEntryPointsOpen() {
        let sandbox = Sandbox()
        let entries: [(UttrflowUX.AppLocation, @MainActor (AppDelegate) -> Void)] = [
            (.main(.home), { _ = $0.applicationShouldHandleReopen(.shared, hasVisibleWindows: false) }),
            (.main(.home), { $0.showMainWindowFromMenu(nil) }),
            (.settings(.general), { $0.showSettingsFromMenu(nil) }),
            (.settings(.diagnostics), { $0.showDiagnosticsFromMenu(nil) }),
        ]
        for (expected, enter) in entries {
            let (app, _) = app(signedIn: true, in: sandbox)
            enter(app)
            #expect(app.lastOpened == expected)
        }
    }

    @Test("a menu bar item that opens a page opens that page")
    func menuItemsOpen() {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: true, in: sandbox)

        app.carryOut(MenuBarIntent.open(.main(.history)))

        #expect(app.lastOpened == .main(.history))
    }

    @Test("dictation, the claimed shortcuts, the clipboard and the floating button follow their switches")
    func surfacesFollowTheSettings() {
        let sandbox = Sandbox()
        let (app, _) = app(signedIn: true, in: sandbox)

        #expect(app.isSignedIn)
        #expect(app.surfaces == SessionSurfaces(isSignedIn: true, settings: Settings()))
        #expect(app.surfaces.listensForDictation)
        #expect(app.surfaces.claimedShortcuts.contains(.clipboard))
    }
}

@MainActor
@Suite("Losing the session closes everything", .serialized)
struct SessionLossTests {
    @Test("signing out closes the main window and the panels, stops listening, and opens sign-in")
    func signOutClosesEverything() {
        let sandbox = Sandbox()
        let (app, session) = app(signedIn: true, in: sandbox)
        app.mainWindow = app.makeMainWindow()

        app.carryOut(MainIntent.signOut)

        #expect(session.load() == nil)
        #expect(app.mainWindow == nil)
        #expect(app.lastOpened == .onboarding)
        #expect(!app.isQuickPanelOpen)
        #expect(!app.isFloatingButtonShown)
        #expect(!app.isWatchingTheClipboard)
        #expect(app.armedShortcuts.isEmpty)
        #expect(app.menuBarPresentation == SessionGate.signedOutMenu)
    }

    @Test("a session the server ended is closed the same way as a sign-out")
    func revokedSessionClosesEverything() async {
        let sandbox = Sandbox()
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(
            container: sandbox.root,
            account: OnboardingAccountLayer(authentication: EndedSession(), profiles: session))
        app.drawsWindows = false
        app.mainWindow = app.makeMainWindow()

        await app.refreshAccount().value

        #expect(session.load() == nil)
        #expect(app.mainWindow == nil)
        #expect(app.lastOpened == .onboarding)
        #expect(app.menuBarPresentation == SessionGate.signedOutMenu)
    }

    @Test("a refresh that cannot reach the server keeps a signed session and everything open")
    func offlineKeepsTheSession() async {
        let sandbox = Sandbox()
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(
            container: sandbox.root,
            account: OnboardingAccountLayer(authentication: UnreachableServer(), profiles: session))
        app.drawsWindows = false
        let window = app.makeMainWindow()
        app.mainWindow = window

        await app.refreshAccount().value

        #expect(session.load() != nil)
        #expect(app.isSignedIn)
        #expect(app.mainWindow === window)
    }
}

@MainActor
@Suite("The menu bar icon while signed out")
struct LockedMenuBarTests {
    @Test("opening the menu asks for sign-in and never shows the popover")
    func openingAsksForSignIn() {
        let bar = MenuBarController()
        var asked: [MenuBarIntent] = []
        bar.onCommand = { asked.append($0) }
        bar.requiresSignIn = true

        bar.openMenu()

        #expect(asked == [.open(.onboarding)])
        #expect(!bar.isPopoverShown)
    }
}

/// Bytes in memory under string keys, standing in for the defaults domain.
private final class KeyedBytes: SessionStorage {
    private let contents = Mutex<[String: Data]>([:])

    func data(forKey key: String) -> Data? { contents.withLock { $0[key] } }

    func set(_ data: Data?, forKey key: String) { contents.withLock { $0[key] = data } }
}

/// A backend that answers every profile request with a 401, as a revoked session does.
private struct EndedSession: AuthenticationService {
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        throw .serverUnreachable
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        throw .serverUnreachable
    }

    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        .signedOut
    }

    func avatar(at path: String) async -> Data? { nil }

    func signOut() async {}
}

/// A backend that cannot be reached, as on a plane.
private struct UnreachableServer: AuthenticationService {
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        throw .serverUnreachable
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        throw .serverUnreachable
    }

    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        throw .serverUnreachable
    }

    func avatar(at path: String) async -> Data? { nil }

    func signOut() async {}
}
