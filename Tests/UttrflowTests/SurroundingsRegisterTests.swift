// Pins issue #795: the collector's cleanup once erased the timed turns Register needed to see.

import CoreGraphics
import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

/// A window of plain values standing in for another application's elements, for one collector-to-register check.
private struct Item: Equatable {
    let id: Int
    var role: String? = "AXStaticText"
    var text: String? = nil
    var children: [Item] = []
}

/// The tree the collector walks, with parents found by search since a fixture has no back-pointers.
private struct FlatTree: ElementTree {
    let root: Item
    func role(of element: Item) -> String? { element.role }
    func text(of element: Item) -> String? { element.text }
    func children(of element: Item) -> [Item] { element.children }
    func frame(of element: Item) -> CGRect? { nil }
    func parent(of element: Item) -> Item? { parent(of: element, under: root) }

    private func parent(of element: Item, under candidate: Item) -> Item? {
        if candidate.children.contains(element) { return candidate }
        for child in candidate.children {
            if let found = parent(of: element, under: child) { return found }
        }
        return nil
    }
}

/// A field named the way a message composer names itself, focused in `window`.
private func composer(named field: String?, in window: Item) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.example.chat", applicationName: "Chat", role: "AXTextArea",
        placeholder: field, accessibilityDescription: field, value: "",
        selection: NSRange(location: 0, length: 0),
        isComposing: true)
}

@Suite("The collector keeps what Register needs to recognize a conversation")
struct SurroundingsRegisterTests {
    /// A name and a stamp on their own lines beside a message composer, the layout issue #795 reported.
    private static let compose = Item(id: 100, role: "AXTextArea")
    private static let thread = Item(
        id: 2,
        children: [
            Item(id: 3, text: "Neha"), Item(id: 4, text: "10:31 AM"),
            Item(id: 5, text: "Standup moved, please confirm."),
            Item(id: 6, text: "Arjun"), Item(id: 7, text: "10:33 AM"), Item(id: 8, text: "Confirmed."),
        ])
    private static let window = Item(
        id: 0, role: "AXWindow",
        children: [Item(id: 1, text: "Chats"), thread, Item(id: 9, children: [compose])])

    @Test("A name and its stamp on separate lines still read as timed turns once collected")
    func separateNameAndStampSurviveCollection() {
        let around = Surroundings.collect(
            around: Self.compose, in: FlatTree(root: Self.window), windowTitle: nil)
        // The stamps are gone from the prompt text, which is what `Timestamps.without` exists to guarantee.
        #expect(around.text == "Chats\nNeha\nStandup moved, please confirm.\nArjun\nConfirmed.")
        #expect(around.timedTurnLines == 2)

        let situation = SuggestionMoment.situation(
            of: composer(named: "Message #platform", in: Self.window), surroundings: around, recentLines: [])
        #expect(
            !situation.surroundings!.contains("10:3"), "the collected text still must not carry a clock time")
        #expect(Register.infer(from: situation, typed: "").isConversational)
    }

    @Test("The same screen behind an ordinary field is not read as a conversation")
    func aPlainFieldIsNotSwayedByTheStamps() {
        let around = Surroundings.collect(
            around: Self.compose, in: FlatTree(root: Self.window), windowTitle: nil)
        let situation = SuggestionMoment.situation(
            of: composer(named: "Notes", in: Self.window), surroundings: around, recentLines: [])
        #expect(!Register.infer(from: situation, typed: "").isConversational)
    }
}
