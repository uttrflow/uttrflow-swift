// Tests that the last dictation's trace reaches the Diagnostics page and never the copied report.
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowUX

@Suite("The dictation trace is shown under Last dictation and kept out of the copy")
struct DiagnosticsTraceTests {
    private static let lines = ["piece 1     zorblaxquent", "result      quillithmar"]

    @Test("the page shows the trace lines as given")
    func pageShowsTrace() {
        let page = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot().tracing(Self.lines), locale: DiagnosticsFixture.locale)
        #expect(page.trace == Self.lines)
    }

    @Test("without a trace the page shows none")
    func noTraceByDefault() {
        #expect(DiagnosticsPresenter.page(for: DiagnosticsSnapshot()).trace.isEmpty)
    }

    @Test("Copy diagnostics quotes no trace line")
    func copyLeavesTraceOut() {
        let page = DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot().tracing(Self.lines), locale: DiagnosticsFixture.locale)
        guard case .copy(let copied) = page.copyAction.intent else {
            Issue.record("Copy diagnostics copies nothing")
            return
        }
        #expect(!copied.contains("zorblaxquent"))
        #expect(!copied.contains("quillithmar"))
    }
}

@Suite("The recorder holds the last trace only while its switch is on")
struct DiagnosticsRecorderTraceTests {
    private final class Switch: Sendable {
        private let state = Mutex(false)
        var isOn: Bool {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
    }

    @Test("off by default, a trace handed over is not kept")
    func offKeepsNothing() {
        let recorder = DiagnosticsRecorder { false }
        recorder.recordTrace(["result      words"])
        #expect(recorder.trace.isEmpty)
    }

    @Test("on, the last trace is kept until the switch is turned off")
    func switchOffDrops() {
        let toggle = Switch()
        toggle.isOn = true
        let recorder = DiagnosticsRecorder { toggle.isOn }
        recorder.recordTrace(["result      first"])
        recorder.recordTrace(["result      second"])
        #expect(recorder.trace == ["result      second"])
        toggle.isOn = false
        #expect(recorder.trace.isEmpty)
        toggle.isOn = true
        #expect(recorder.trace.isEmpty)
    }

    @Test("a reset that forgets the last dictation drops the trace")
    func forgetDrops() async {
        let recorder = DiagnosticsRecorder { true }
        recorder.recordTrace(["result      words"])
        await recorder.forget()
        #expect(recorder.trace.isEmpty)
    }
}
