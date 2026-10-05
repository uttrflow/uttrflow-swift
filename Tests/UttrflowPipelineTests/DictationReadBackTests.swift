// Tests how much of a dictation is spoken back after insertion and on request.
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("Dictation read-back")
struct DictationReadBackTests {
    private static let long = Array(
        repeating: "Right, so the plan for tomorrow is to finish the drafting.", count: 12
    ).joined(separator: " ")

    private static func inserted(_ text: String, secure: Bool = false) -> DictationState {
        .inserted(
            DictationOutcome(
                text: text, method: .accessibility, cleanedBy: .rules, intoSecureField: secure))
    }

    @Test("off announces the outcome without any of the words")
    func off() {
        #expect(
            DictationPresenter.announcement(for: Self.inserted(Self.long), readBack: .off)
                == DictationAnnouncement(text: "Inserted.", isUrgent: false))
    }

    @Test("preview stays the default glance")
    func preview() throws {
        let said = try #require(DictationPresenter.announcement(for: Self.inserted(Self.long)))
        #expect(said == DictationPresenter.announcement(for: Self.inserted(Self.long), readBack: .preview))
        #expect(said.text.hasSuffix("…"))
    }

    @Test("whole speaks exactly the inserted text")
    func whole() {
        #expect(
            DictationPresenter.announcement(for: Self.inserted(Self.long), readBack: .whole)?.text
                == "Inserted: \(Self.long)")
    }

    @Test("no setting speaks the words of a secure field")
    func secure() throws {
        for readBack in DictationReadBack.allCases {
            let said = try #require(
                DictationPresenter.announcement(
                    for: Self.inserted(Self.long, secure: true), readBack: readBack))
            #expect(!said.text.contains("drafting"), "\(readBack)")
        }
        #expect(DictationReadBack.pieces(of: Self.long, intoSecureField: true) == nil)
    }

    @Test("pieces are sentences that join back to the inserted text exactly")
    func pieces() throws {
        let text = "Version 3.5 shipped. Did it work?  Yes!\nGood"
        let pieces = try #require(DictationReadBack.pieces(of: text, intoSecureField: false))
        #expect(pieces == ["Version 3.5 shipped. ", "Did it work?  ", "Yes!\n", "Good"])
        #expect(pieces.joined() == text)
        let longPieces = try #require(DictationReadBack.pieces(of: Self.long, intoSecureField: false))
        #expect(longPieces.count == 12)
        #expect(longPieces.joined() == Self.long)
    }

    @Test("an empty insertion has nothing to read back")
    func empty() {
        #expect(DictationReadBack.pieces(of: "", intoSecureField: false) == nil)
    }
}
