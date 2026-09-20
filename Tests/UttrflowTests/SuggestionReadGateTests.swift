// Tests that a suggestion turn reads no field where suggestions cannot be drawn (#903).

import Foundation
import Testing
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
                front: "com.apple.dt.Xcode", own: "com.example.self", preferences: Self.on, at: Self.now))
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
}
