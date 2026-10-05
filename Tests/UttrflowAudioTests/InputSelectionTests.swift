// Tests that a chosen input device opens when present and falls back to the default when not.
import Testing
import UttrflowAudio

@Suite("Input device selection")
struct InputSelectionTests {
    private let builtIn = AudioInputDevice(uid: "fixture-built-in", name: "Built-in Microphone")
    private let headset = AudioInputDevice(uid: "fixture-headset", name: "Example Headset")

    @Test("no choice opens the system default")
    func noChoice() {
        let selection = InputSelection.resolve(preferredUID: nil, present: [builtIn, headset])
        #expect(selection == .systemDefault)
        #expect(selection.deviceUID == nil)
    }

    @Test("a chosen device that is present is the one opened")
    func chosenPresent() {
        let selection = InputSelection.resolve(preferredUID: headset.uid, present: [builtIn, headset])
        #expect(selection == .chosen(uid: headset.uid))
        #expect(selection.deviceUID == headset.uid)
    }

    @Test("a chosen device that is absent falls back to the default")
    func chosenAbsent() {
        let selection = InputSelection.resolve(preferredUID: headset.uid, present: [builtIn])
        #expect(selection == .fellBack)
        #expect(selection.deviceUID == nil)
    }

    @Test("a device removed mid-recording falls back on the reopen")
    func removedMidRecording() {
        var present = [builtIn, headset]
        let chosen = InputSelection.resolve(preferredUID: headset.uid, present: present)
        #expect(chosen == .chosen(uid: headset.uid))
        present.removeAll { $0 == headset }
        #expect(InputSelection.resolve(preferredUID: headset.uid, present: present) == .fellBack)
    }

    @Test("a source built with a choice has resolved nothing before it opens")
    func nothingBeforeOpen() {
        let source = AVAudioEngineMicrophoneSource(preferredUID: { "fixture-headset" })
        #expect(source.inputSelection == nil)
    }
}
