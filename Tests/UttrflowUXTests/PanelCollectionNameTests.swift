// Tests for what a new collection name may be, and for a collection that empties while it is open.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// One rule decides a new collection name, whether a clip is filed under it or a collection is renamed to it.
@Suite("Collection names")
struct PanelCollectionNameTests {
    /// Two clips in Work and one unfiled.
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Work"),
        PanelFixture.clip("three", minutesAgo: 3),
    ]

    /// The move sheet over the unfiled clip with this name typed.
    static func moving(_ draft: String, in clips: [Clip] = clips) -> PanelResponse {
        PanelFixture.panel(clips).applying([.move(clips[clips.count - 1].id), .draft(draft)])
    }

    /// The rename sheet over Work with this name typed.
    static func renaming(_ draft: String, in clips: [Clip] = clips) -> PanelResponse {
        PanelFixture.panel(clips).applying([.renameCategory("Work"), .draft(draft)])
    }

    /// Whether the sheet refuses the typed name, both on screen and on Return.
    static func refuses(_ typed: PanelResponse, saying words: String) -> Bool {
        let sheet = PanelPresenter.present(typed.state).sheet
        return sheet?.isConfirmEnabled == false
            && sheet?.conflict?.contains(words) == true
            && typed.state.applying(.return).outcome == .open
    }

    @Test("a name of 40 characters is a collection, and one of 41 is refused")
    func length() {
        let longest = String(repeating: "a", count: 40)
        let clip = Self.clips[2].id

        #expect(
            Self.moving(longest).state.applying(.return).outcome
                == .change(.setCategory(clip, longest)))
        #expect(Self.refuses(Self.moving(longest + "b"), saying: "40 characters"))
        #expect(Self.refuses(Self.renaming(longest + "b"), saying: "40 characters"))
    }

    @Test("the length is counted in characters as a person sees them")
    func lengthInCharacters() {
        let flags = String(repeating: "🇮🇳", count: 40)
        let clip = Self.clips[2].id

        #expect(
            Self.moving(flags).state.applying(.return).outcome
                == .change(.setCategory(clip, flags)))
    }

    @Test(
        "a line break, a tab or an invisible control inside the name is refused",
        arguments: [
            "Two\nlines", "Two\r\nlines", "Tab\there", "Bell\u{07}", "Right\u{202E}left",
            "Zero\u{200B}width", "Line\u{2028}separator",
        ])
    func invisibleCharacters(_ name: String) {
        #expect(Self.refuses(Self.moving(name), saying: "visible characters"))
        #expect(Self.refuses(Self.renaming(name), saying: "visible characters"))
    }

    @Test("outer whitespace is trimmed, never refused")
    func outerWhitespace() {
        let clip = Self.clips[2].id

        #expect(
            Self.moving("\n  Servers \t").state.applying(.return).outcome
                == .change(.setCategory(clip, "Servers")))
    }

    /// The kind filters share the chip row, so a collection with a filter's name would be a second chip reading the same.
    @Test("a kind filter's name is refused in any case", arguments: PanelFilter.allCases)
    func filterNames(_ filter: PanelFilter) {
        #expect(Self.refuses(Self.moving(filter.title.lowercased()), saying: "a filter"))
        #expect(Self.refuses(Self.renaming(filter.title.uppercased()), saying: "a filter"))
    }

    /// A collection made before the rules keeps working: nothing the user filed is hidden or refused.
    @Test("an existing collection that breaks the rules can still be filed into")
    func existingCollectionsKeepWorking() {
        let legacy = "Two\nlines and " + String(repeating: "x", count: 50)
        let clips = [
            PanelFixture.clip("old", minutesAgo: 1, category: legacy),
            PanelFixture.clip("new", minutesAgo: 2),
        ]

        #expect(
            Self.moving(legacy, in: clips).state.applying(.return).outcome
                == .change(.setCategory(clips[1].id, legacy)))
    }
}

/// A collection exists only while a clip carries its name, so the list that arrives decides whether it is still there.
@Suite("A collection that empties while it is open")
struct PanelEmptiedCollectionTests {
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2),
    ]

    @Test("moving the last clip out of the open collection returns the panel to All")
    func returnsToAll() {
        var snapshot = PanelFixture.panel(Self.clips, category: "Work")
        var moved = Self.clips[0]
        moved.category = "Servers"
        snapshot.install(
            [moved, Self.clips[1]], missingImages: [], formattableLanguages: [],
            now: PanelFixture.now)

        #expect(snapshot.category == nil)
        let presentation = PanelPresenter.present(snapshot)
        #expect(
            presentation.rows.map(\.id) == [Self.clips[1].id],
            "History lists the unfiled clip, and the moved one is under its new chip")
        #expect(presentation.categories.map(\.title) == ["Servers"])
        #expect(presentation.categories.filter(\.isActive).isEmpty, "no chip is lit for nothing")
    }

    @Test("a collection that still holds a clip stays open")
    func staysOpen() {
        var snapshot = PanelFixture.panel(Self.clips, category: "Work")
        snapshot.install(
            Self.clips + [PanelFixture.clip("three", minutesAgo: 3)], missingImages: [],
            formattableLanguages: [], now: PanelFixture.now)

        #expect(snapshot.category == "Work")
    }
}
