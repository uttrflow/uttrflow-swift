// Tests that a suggestion turn reads no field where suggestions cannot be drawn (#903).

import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@Suite("Reading the field only where suggestions run")
struct SuggestionReadGateTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let on = SuggestionPreferences(isEnabled: true)

    @Test("an ordinary application with suggestions on is read")
    func onIsRead() {
        #expect(
            SuggestionCoordinator.shouldRead(
                front: "com.example.notes", own: "com.example.self", preferences: Self.on, at: Self.now))
    }

    @Test("an application the person turned off is not read")
    func turnedOffIsNotRead() {
        let preferences = SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.notes"])
        #expect(
            !SuggestionCoordinator.shouldRead(
                front: "com.example.notes", own: "com.example.self", preferences: preferences,
                at: Self.now))
    }

    @Test("an application that ships off is not read")
    func offByDefaultIsNotRead() {
        #expect(
            !SuggestionCoordinator.shouldRead(
                front: "com.microsoft.VSCode", own: "com.example.self", preferences: Self.on, at: Self.now))
    }

    @Test("nothing is read while suggestions are paused")
    func pausedIsNotRead() {
        let preferences = SuggestionPreferences(
            isEnabled: true, pausedUntil: Self.now.addingTimeInterval(60))
        #expect(
            !SuggestionCoordinator.shouldRead(
                front: "com.example.notes", own: "com.example.self", preferences: preferences,
                at: Self.now))
    }

    @Test("Uttrflow itself is never read")
    func ownIsNotRead() {
        #expect(
            !SuggestionCoordinator.shouldRead(
                front: "com.example.self", own: "com.example.self", preferences: Self.on, at: Self.now))
    }

    @Test(
        "every Uttrflow build is never read, the dev build from the release and the release from the dev build"
    )
    func everyUttrflowBuildIsNotRead() {
        for (front, own) in [
            ("com.uttrflow.Uttrflow.dev", "com.uttrflow.Uttrflow"),
            ("com.uttrflow.Uttrflow", "com.uttrflow.Uttrflow.dev"),
            ("com.uttrflow.Uttrflow", nil),
        ] {
            #expect(
                !SuggestionCoordinator.shouldRead(
                    front: front, own: own, preferences: Self.on, at: Self.now), "\(front) was read")
        }
    }

    @Test("an application whose identifier only starts like Uttrflow's is still read")
    func lookalikeIsRead() {
        #expect(
            SuggestionCoordinator.shouldRead(
                front: "com.uttrflower.notes", own: "com.uttrflow.Uttrflow", preferences: Self.on,
                at: Self.now))
    }

    @Test("a redraw in an excluded browser never starts a focused-field read")
    func excludedBrowserIsNotReadForRedraw() async {
        let browser = FocusedFieldSnapshot(
            bundleIdentifier: "com.google.Chrome", applicationName: "Browser", role: "AXTextField")
        let preferences = SuggestionPreferences(isEnabled: true, turnedOff: [browser.bundleIdentifier])

        let read = await SuggestionCoordinator.readForFreshDraw(
            front: browser.bundleIdentifier, snapshot: browser, own: nil, preferences: preferences,
        ) { browser }

        #expect(read == nil)
    }

    @Test("a redraw rereads the same application while suggestions are enabled")
    func enabledApplicationIsReadForRedraw() async {
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.notes", applicationName: "Notes", role: "AXTextField")

        let read = await SuggestionCoordinator.readForFreshDraw(
            front: snapshot.bundleIdentifier, snapshot: snapshot, own: nil, preferences: Self.on,
        ) { snapshot }

        #expect(read == snapshot)
    }

    @Test("the delayed redraw calls only through the guarded reader")
    func redrawUsesGuardedReader() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let redraw = try #require(source.range(of: "private func drawFresh("))
        let end = try #require(
            source.range(
                of: "/// Whether the key armed for the drawn line", range: redraw.upperBound..<source.endIndex
            ))
        let body = source[redraw.lowerBound..<end.lowerBound]

        #expect(body.contains("Self.readForFreshDraw("))
        #expect(body.contains("read: { await FocusedFieldReader.read() }"))
    }
}
