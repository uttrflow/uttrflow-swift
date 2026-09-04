import Foundation
import Testing

@testable import UttrflowPredict

/// A moment to measure the half-hour pause from, so no test depends on when it ran.
private let noon = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("What the user has decided about tab-to-complete")
struct SuggestionPreferencesTests {
    @Test("Draws nothing until it is asked for, which is what off by default means.")
    func offByDefault() {
        #expect(!SuggestionPreferences.default.isEnabled)
        #expect(!SuggestionPreferences.default.isEnabled(in: "com.apple.Notes", at: noon))
    }

    @Test("Runs in an ordinary application the moment the feature is switched on.")
    func onEverywhereElse() {
        let preferences = SuggestionPreferences(isEnabled: true)
        #expect(preferences.isEnabled(in: "com.apple.Notes", at: noon))
        #expect(preferences.state(of: "com.apple.Notes") == .on)
    }

    @Test(
        "Ships switched off in the four editors that already complete from the whole file.",
        arguments: [
            "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
            "dev.zed.Zed",
        ])
    func editorsShipOff(bundleIdentifier: String) {
        let preferences = SuggestionPreferences(isEnabled: true)
        #expect(preferences.state(of: bundleIdentifier) == .offByDefault)
        #expect(!preferences.isEnabled(in: bundleIdentifier, at: noon))
    }

    @Test("An editor the user asks for comes back on, and stays on.")
    func anEditorCanBeAskedFor() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.dt.Xcode", isOn: true)
        #expect(preferences.state(of: "com.apple.dt.Xcode") == .on)
        #expect(preferences.isEnabled(in: "com.apple.dt.Xcode", at: noon))
    }

    @Test("Switching an application off says so, and switching it back on undoes exactly that.")
    func oneApplicationGoesOffAndBackOn() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.Notes", isOn: false)
        #expect(preferences.state(of: "com.apple.Notes") == .turnedOff)
        #expect(!preferences.turnedOn.contains("com.apple.notes"))

        preferences.set("com.apple.Notes", isOn: true)
        #expect(preferences.state(of: "com.apple.Notes") == .on)
        #expect(!preferences.turnedOff.contains("com.apple.notes"))
    }

    @Test("A bundle identifier is compared without regard to case, however it was written.")
    func identifiersAreCompared() {
        var preferences = SuggestionPreferences(isEnabled: true, turnedOff: ["COM.Apple.Notes"])
        #expect(preferences.state(of: "com.apple.notes") == .turnedOff)
        preferences.set("Com.Apple.Notes", isOn: true)
        #expect(preferences.state(of: "COM.APPLE.NOTES") == .on)
    }

    @Test("Switching the feature off silences an application nothing was said about.")
    func theMasterSwitchWinsEverywhere() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.Notes", isOn: true)
        preferences.isEnabled = false
        #expect(!preferences.isEnabled(in: "com.apple.Notes", at: noon))
        #expect(preferences.state(of: "com.apple.Notes") == .on)
    }
}

@Suite("The half-hour pause")
struct SuggestionPauseTests {
    @Test("Lasts half an hour from the moment it was started.")
    func lastsHalfAnHour() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.setPaused(true, at: noon)
        #expect(preferences.pausedUntil == noon.addingTimeInterval(30 * 60))
    }

    @Test("Silences every application while it runs, whatever each of them says.")
    func silencesEverywhere() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.Notes", isOn: true)
        preferences.setPaused(true, at: noon)
        #expect(!preferences.isEnabled(in: "com.apple.Notes", at: noon.addingTimeInterval(60)))
    }

    @Test("Lifts itself at the half hour, so it cannot be forgotten in the off position.")
    func expiresOnItsOwn() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.setPaused(true, at: noon)
        #expect(preferences.isPaused(at: noon.addingTimeInterval(29 * 60)))
        #expect(!preferences.isPaused(at: noon.addingTimeInterval(30 * 60)))
        #expect(preferences.isEnabled(in: "com.apple.Notes", at: noon.addingTimeInterval(30 * 60)))
    }

    @Test("Expires against the moment it is asked about, never against when it was started.")
    func expiryIsAgainstTheGivenMoment() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.setPaused(true, at: noon)
        #expect(preferences.isPaused(at: noon))
        #expect(!preferences.isPaused(at: noon.addingTimeInterval(3 * 3_600)))
    }

    @Test("Says how much is left while it runs, and nothing once it has run out.")
    func reportsWhatIsLeft() throws {
        var preferences = SuggestionPreferences(isEnabled: true)
        #expect(preferences.pauseRemaining(at: noon) == nil)
        preferences.setPaused(true, at: noon)
        let left = try #require(preferences.pauseRemaining(at: noon.addingTimeInterval(10 * 60)))
        #expect(abs(left - 20 * 60) < 0.001)
        #expect(preferences.pauseRemaining(at: noon.addingTimeInterval(30 * 60)) == nil)
    }

    @Test("Can be lifted before it runs out, which leaves no deadline behind.")
    func canBeLiftedEarly() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.setPaused(true, at: noon)
        preferences.setPaused(false, at: noon.addingTimeInterval(60))
        #expect(preferences.pausedUntil == nil)
        #expect(!preferences.isPaused(at: noon.addingTimeInterval(60)))
    }
}

@Suite("Which key accepts, once the user has chosen one")
struct SuggestionAcceptKeyChoiceTests {
    @Test("Falls back to the shipped answer for an application nothing was chosen for.")
    func fallsBackToTheShippedAnswer() {
        let preferences = SuggestionPreferences(isEnabled: true)
        #expect(preferences.acceptKeys.key(forBundleIdentifier: "com.apple.Notes") == .tab)
        #expect(
            preferences.acceptKeys.key(forBundleIdentifier: "com.apple.Terminal") == .rightArrow)
        #expect(preferences.acceptKeys.key(forBundleIdentifier: "com.apple.dt.Xcode") == .optionTab)
    }

    @Test("Uses the key the user chose for that application, over the shipped answer.")
    func theChoiceWins() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.setAcceptKey(.rightArrow, in: "com.apple.dt.Xcode")
        #expect(
            preferences.acceptKeys.key(forBundleIdentifier: "com.apple.dt.Xcode") == .rightArrow)
        #expect(preferences.acceptKeys.key(forBundleIdentifier: "com.apple.Notes") == .tab)
    }
}

@Suite("Every application that has been switched off can be found again")
struct SuggestionApplicationListTests {
    @Test("Lists the four shipped editors before the user has touched anything.")
    func theShippedEditorsAreListed() {
        let listed = SuggestionPreferences.default.knownApplications().map(\.bundleIdentifier)
        for editor in SuggestionApplications.offByDefault {
            #expect(listed.contains(editor.bundleIdentifier))
        }
    }

    @Test("Lists every application the user switched off, whichever way it was switched off.")
    func everythingTurnedOffIsListed() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.Notes", isOn: false)
        preferences.set("com.tinyspeck.slackmacgap", isOn: false)
        let listed = preferences.knownApplications()
        for identifier in preferences.turnedOff {
            #expect(listed.contains { $0.bundleIdentifier == identifier })
        }
    }

    @Test("Lists an application switched off by its own identifier, exactly as the screen would.")
    func switchingOffCannotHideAnApplication() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.Notes", isOn: false)
        #expect(preferences.state(of: "com.apple.Notes") == .turnedOff)
        #expect(preferences.knownApplications().contains { $0.bundleIdentifier == "com.apple.notes" })
    }

    @Test("Lists an application only once, however many things there are to say about it.")
    func noApplicationIsListedTwice() {
        var preferences = SuggestionPreferences(isEnabled: true)
        preferences.set("com.apple.dt.Xcode", isOn: true)
        preferences.setAcceptKey(.tab, in: "com.apple.dt.Xcode")
        let listed = preferences.knownApplications(learnedIn: ["com.apple.dt.xcode"])
        #expect(listed.count(where: { $0.bundleIdentifier == "com.apple.dt.xcode" }) == 1)
    }

    @Test("Adds an application that has taught it something, so its corpus can be forgotten.")
    func whatHasTaughtItIsListed() {
        let listed = SuggestionPreferences.default.knownApplications(learnedIn: ["com.apple.Mail"])
        #expect(listed.contains { $0.bundleIdentifier == "com.apple.mail" })
    }

    @Test("Sorts by the name on screen, so the list reads the way it is written.")
    func sortedByName() {
        let names = SuggestionPreferences.default.knownApplications().map(\.name)
        #expect(names == names.sorted { $0.lowercased() < $1.lowercased() })
    }

    @Test("Names the applications it ships knowing about, rather than showing an identifier.")
    func namesTheOnesItKnows() {
        #expect(SuggestionApplications.name(of: "com.apple.dt.Xcode") == "Xcode")
        #expect(SuggestionApplications.name(of: "com.microsoft.VSCode") == "Visual Studio Code")
        #expect(SuggestionApplications.name(of: "com.todesktop.230313mzl4w4u92") == "Cursor")
        #expect(SuggestionApplications.name(of: "dev.zed.Zed") == "Zed")
    }

    @Test("Makes a name out of an identifier it has never seen, rather than showing nothing.")
    func namesTheOnesItDoesNot() {
        #expect(SuggestionApplications.name(of: "com.tinyspeck.slackmacgap") == "Slackmacgap")
        #expect(SuggestionApplications.name(of: "notes") == "Notes")
        #expect(SuggestionApplications.name(of: "com.trailing.") == "Trailing")
        #expect(SuggestionApplications.name(of: "") == "")
        #expect(SuggestionApplications.name(of: "...") == "...")
    }
}
