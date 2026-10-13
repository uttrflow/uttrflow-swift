// Tests for the version string the sidebar shows.
import Foundation
import Testing

@testable import UttrflowUX

/// Which build the sidebar says this is, pinned because every wrong form costs somebody a round trip.
@Suite("The version in the sidebar")
struct AppVersionTests {
    /// The rail is forty-four points wide, so the short form has to stand alone and mean something.
    @Test("the short form is the version alone")
    func shortStandsAlone() {
        #expect(AppVersion(short: "0.2.0", build: "3").short == "0.2.0")
    }

    /// Nothing rather than "unknown": an unreadable bundle costs a missing line, not a misleading one.
    @Test("an unknown version is empty and says so")
    func unknownIsEmpty() {
        #expect(!AppVersion.unknown.isKnown)
        #expect(!AppVersion(short: "", build: "9").isKnown)
    }

    @Test("the tag is the version as a release names it, and empty when unknown")
    func tag() {
        #expect(AppVersion(short: "26.0926.0", build: "12").tag == "v26.0926.0")
        #expect(AppVersion.unknown.tag.isEmpty)
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

        #expect(SidebarPresenter.sidebar(for: snapshot).version.tag == "v0.2.0")
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
