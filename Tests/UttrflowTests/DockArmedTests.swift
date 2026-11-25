// Tests the listening shell the dock draws from key-down, before the microphone has opened.

import Foundation
import Testing
import UttrflowPipeline

@testable import Uttrflow

@MainActor
@Suite("The dock's armed form")
struct DockArmedTests {
    private func model() -> DockViewModel {
        DockViewModel(
            presentation: DictationPresenter.dock(for: .idle), shortcut: "⌥Space",
            anchor: .bottomRight)
    }

    @Test("the armed look is a meter without a recording")
    func armedIsAShellNotARecording() {
        let armed = DockPresentation.armed

        #expect(armed.isArmed)
        #expect(armed.showsWaveform)
        #expect(!armed.isRecording)
        #expect(!DictationPresenter.dock(for: .recording).isArmed)
    }

    @Test("shows flat bars and a clock at zero, without starting the clock")
    func armedShowsFlatBarsAtZero() {
        let dock = model()
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        dock.show(DictationPresenter.dock(for: .recording), now: now)
        _ = dock.meter(0.8)
        dock.show(DictationPresenter.dock(for: .idle), now: now)

        dock.show(.armed, now: now)

        #expect(dock.bars.levels.allSatisfy { $0 == 0 })

        #expect(dock.recordingStartedAt == nil)
        #expect(DockWording.clockText(for: .armed, startedAt: nil, now: now) == "0:00")
    }

    @Test("speaks getting ready, and the recording that follows speaks as it always did")
    func armedSpeaksGettingReady() {
        #expect(DockWording.spokenValue(for: .armed) == "Getting ready")
        let recording = DictationPresenter.dock(for: .recording)
        #expect(DockWording.spokenValue(for: .armed) != DockWording.spokenValue(for: recording))
    }
}
