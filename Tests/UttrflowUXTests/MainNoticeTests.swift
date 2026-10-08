// Tests that a refused main-window change keeps the failure's own sentence and is drawn by what it cost.
import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

@Suite("What the main window says when a change is refused")
struct MainNoticeTests {
    /// The store already writes the sentence, so the page must not word the same refusal a second way.
    @Test("a store's refusal is said in the store's own words")
    func keepsTheStoresSentence() {
        #expect(
            MainNotice(refusing: HistoryStoreError.couldNotWrite).message
                == HistoryStoreError.couldNotWrite.userMessage)
        #expect(
            MainNotice(refusing: SnippetStoreError.couldNotWrite).message
                == SnippetStoreError.couldNotWrite.userMessage)
        #expect(
            MainNotice(refusing: DictionaryStoreError.couldNotWrite).message
                == DictionaryStoreError.couldNotWrite.userMessage)
    }

    /// A lost write costs the user something, so it is drawn as a fault rather than as a caption.
    @Test("a lost write is drawn as something that went wrong")
    func drawsALostWriteAsAFault() {
        let notice = MainNotice(refusing: HistoryStoreError.couldNotWrite)
        #expect(notice.tone == .critical)
        #expect(notice.symbolName == "exclamationmark.triangle")
    }

    /// An error nobody typed still has to reach the screen, and never as a type name.
    @Test("an unforeseen error is said plainly and offers another attempt")
    func describesAnUnforeseenError() {
        struct Nameless: Error {}
        let notice = MainNotice(refusing: Nameless())
        #expect(notice.message == MainNotice.unforeseenMessage)
        #expect(notice.tone == .warning)
        #expect(notice.symbolName == "arrow.clockwise")
    }

    /// Every severity draws, so a refusal added later cannot inherit a tone nobody chose.
    @Test("each cost the user can be put to has a tone and a symbol of its own")
    func drawsEverySeverity() {
        let drawings = FailureSeverity.allCases.map { MainNotice.drawing(for: $0) }
        #expect(drawings.map(\.tone) == [.critical, .critical, .warning, .neutral])
        #expect(!drawings.contains { $0.symbolName.isEmpty })
    }

    /// The first sentence is the notice's title and the rest sits under it, with no word lost.
    @Test("a notice splits its sentence into a title and the line under it")
    func splitsIntoTitleAndDetail() {
        let notice = MainNotice(
            message: "Microphone is off. Turn it on.", symbolName: "mic.slash", tone: .critical)
        #expect(notice.headline == "Microphone is off.")
        #expect(notice.detail == "Turn it on.")
        let single = MainNotice(message: "Copied", symbolName: "doc.on.clipboard", tone: .neutral)
        #expect(single.headline == "Copied")
        #expect(single.detail == nil)
    }

    /// A refusal that says what would fix it offers that fix as the notice's button.
    @Test("a refusal with a recovery offers it, and one without offers nothing")
    func offersTheFailuresRecovery() {
        let blocked = MainNotice(refusing: HotkeyError.observationNotPermitted)
        #expect(blocked.action?.intent == .recover(.openSystemSettings(.accessibility)))
        #expect(MainNotice(refusing: HistoryStoreError.couldNotWrite).action == nil)
        #expect(MainNotice.action(for: .retry)?.title == "Try Again")
        #expect(MainNotice.action(for: .pasteManually) == nil)
        #expect(MainNotice.action(for: nil) == nil)
    }

    @Test(
        "Apple model availability has distinct explanations and only the switched-off state offers Settings")
    func explainsAppleIntelligenceAvailability() {
        let switchedOff = MainNotice.appleIntelligenceUnavailable(.appleIntelligenceDisabled)
        #expect(switchedOff.message.contains("switched off"))
        #expect(switchedOff.action?.intent == .recover(.openSystemSettings(.appleIntelligence)))
        #expect(switchedOff.tone == .critical)

        let downloading = MainNotice.appleIntelligenceUnavailable(.modelNotReady)
        #expect(downloading.message.contains("downloading"))
        #expect(downloading.action == nil)

        let ineligible = MainNotice.appleIntelligenceUnavailable(.deviceNotEligible)
        #expect(ineligible.message.contains("cannot run Apple Intelligence"))
        #expect(ineligible.action == nil)
    }

    @Test("only a dictation no clean-up finished on is announced as inserted without it")
    func announcesSkippedCleanUp() throws {
        let skipped = try #require(MainNotice.cleanUpSkipped(by: .untidied))
        #expect(skipped.headline == "Inserted without clean-up.")
        #expect(skipped.action == nil)
        #expect(MainNotice.cleanUpSkipped(by: .rules) == nil)
        #expect(MainNotice.cleanUpSkipped(by: .foundationModels) == nil)
    }

    @Test("a notice built from its parts keeps them")
    func keepsItsParts() {
        let notice = MainNotice(message: "No.", symbolName: "xmark", tone: .good)
        #expect(notice.message == "No.")
        #expect(notice.symbolName == "xmark")
        #expect(notice.tone == .good)
        #expect(notice.action == nil)
    }
}
