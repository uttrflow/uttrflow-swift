import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// I1, I6, I7. The microphone in this panel shipped as a control that did nothing: its
/// action re-sent the search it already had, under the label "Dictate a search". These
/// exist so that whatever it says about itself is true.
@Suite("I1, I6, I7 · the panel's microphone")
struct PanelMicrophoneTests {
    static func mic(_ state: PanelDictation) -> PanelMicrophone {
        var snapshot = PanelFixture.panel()
        snapshot.dictation = state
        return PanelPresenter.present(snapshot).microphone
    }

    @Test("I1 · when it can dictate, it says where the words will go")
    func readySaysWhatItDoes() {
        let mic = Self.mic(.ready)

        #expect(mic.isEnabled)
        #expect(mic.status == nil, "nothing is in the way, so nothing is said")
        #expect(mic.label.contains("cursor"), "and the label is not merely “Microphone”")
    }

    @Test("I6 · without permission it is off, and says which permission")
    func microphoneOff() {
        let mic = Self.mic(.unavailable(.microphoneNotGranted))

        #expect(!mic.isEnabled)
        #expect(mic.symbolName == "mic.slash")
        #expect(mic.status?.contains("microphone") == true)
    }

    /// The clipboard is unaffected while the model downloads, and saying which half is
    /// not ready is the difference between one control waiting and the panel being broken.
    @Test("I7 · while the model downloads it is off, and says so specifically")
    func modelNotReady() {
        let mic = Self.mic(.unavailable(.modelNotReady(percent: 42)))

        #expect(!mic.isEnabled)
        #expect(mic.status?.contains("42%") == true)
        #expect(mic.status?.contains("Speech model") == true)
    }

    @Test("a percentage nobody knows yet is left out rather than shown as zero")
    func unknownProgress() {
        let mic = Self.mic(.unavailable(.modelNotReady(percent: nil)))

        #expect(mic.status?.contains("%") == false)
        #expect(mic.status?.isEmpty == false)
    }

    /// A dimmed control with no reason beside it is one people press twice and then
    /// distrust, so every unavailable state owes an explanation.
    @Test(
        "every state that cannot dictate says why",
        arguments: [
            PanelDictation.unavailable(.microphoneNotGranted),
            .unavailable(.modelNotReady(percent: nil)),
            .unavailable(.modelNotReady(percent: 7)),
        ])
    func everyRefusalExplainsItself(state: PanelDictation) {
        let mic = Self.mic(state)

        #expect(!mic.isEnabled)
        #expect(mic.status?.isEmpty == false)
        #expect(!state.canStart)
    }

    /// The panel cannot start a dictation by itself — the pipeline belongs to the app —
    /// so this is an intent and never a key.
    @Test("dictating is an intent, not a keystroke the panel answers")
    func dictateIsAnIntent() {
        #expect(PanelIntent.dictate.key == nil)
    }
}
