// Tests for the version string the sidebar shows.
import Foundation
import Testing

@testable import UttrflowUX

/// Which build the sidebar says this is, pinned because every wrong form costs somebody a round trip.
@Suite("The version in the sidebar")
struct AppVersionTests {
    @Test("says the version and the build where there is room for both")
    func fullCarriesBoth() {
        #expect(AppVersion(short: "0.2.0", build: "3").full == "0.2.0 (3)")
    }

    /// The rail is forty-four points wide, so the short form has to stand alone and mean something.
    @Test("the short form is the version alone")
    func shortStandsAlone() {
        #expect(AppVersion(short: "0.2.0", build: "3").short == "0.2.0")
    }

    /// A version with no build number is not one this project ships, but the parentheses must not be empty.
    @Test("drops the parentheses when there is no build number")
    func noBuildMeansNoBrackets() {
        #expect(AppVersion(short: "0.2.0", build: "").full == "0.2.0")
    }

    /// Nothing rather than "unknown": an unreadable bundle costs a missing line, not a misleading one.
    @Test("an unknown version is empty and says so")
    func unknownIsEmpty() {
        #expect(!AppVersion.unknown.isKnown)
        #expect(AppVersion.unknown.full.isEmpty)
        #expect(!AppVersion(short: "", build: "9").isKnown)
        #expect(AppVersion(short: "", build: "9").full.isEmpty)
    }

    @Test("a version with a build is known")
    func knownWhenThereIsAShortVersion() {
        #expect(AppVersion(short: "0.2.0", build: "3").isKnown)
    }

    /// The sidebar is drawn from the presentation alone, so the version has to survive the trip.
    @Test("reaches the sidebar from the snapshot")
    func thePresenterCarriesIt() {
        let snapshot = SidebarSnapshot(
            selection: .page(.home),
            shortcutKeys: ["⌥", "Space"],
            version: AppVersion(short: "0.2.0", build: "3"),
            now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(SidebarPresenter.sidebar(for: snapshot).version.full == "0.2.0 (3)")
    }

    @Test("and is absent when the snapshot has none")
    func absentByDefault() {
        let snapshot = SidebarSnapshot(
            selection: .page(.home),
            shortcutKeys: ["⌥", "Space"],
            now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(!SidebarPresenter.sidebar(for: snapshot).version.isKnown)
    }
}
