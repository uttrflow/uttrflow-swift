// Tests that every message the floating button's wide form shows fits it without losing words.

import AppKit
import UttrflowCore
import UttrflowPipeline
import Testing

@testable import Uttrflow

/// Measures with AppKit's text layout at the view's own font and width, so nothing is drawn.
@MainActor
@Suite("The wide form of the floating button")
struct DockNoticeTextTests {
    /// Every first line the wide form can be handed: each failure, the fallback, and the speech model's load.
    nonisolated private static var messages: [String] {
        FailureCatalogue.everyFailure.map(\.userMessage)
            + [
                DictationFailure(CocoaError(.fileNoSuchFile)).message,
                SpeechModelLoad.refusal,
                SpeechModelLoad.loading(elapsed: .zero).line,
                SpeechModelLoad.failed.line,
            ]
    }

    /// The second lines the speech model's load puts under its first.
    nonisolated private static var details: [String] {
        [
            SpeechModelLoad.loading(elapsed: .zero).detail,
            SpeechModelLoad.loading(elapsed: .seconds(60)).detail,
            SpeechModelLoad.failed.detail,
        ]
    }

    /// How many lines `text` wraps to in `width` at `font`, against the height of one line of it.
    nonisolated private static func lines(_ text: String, font: NSFont, width: CGFloat) -> Int {
        func height(_ string: String) -> CGFloat {
            (string as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
        }
        return Int((height(text) / height("Ag")).rounded())
    }

    @Test("wraps every message within its line limit", arguments: messages)
    func everyMessageFits(_ message: String) {
        let font = NSFont.systemFont(ofSize: DockMetrics.bodySize, weight: .medium)
        // Two points short of the real width, so a rounding difference from SwiftUI's layout cannot cut a word.
        let needed = Self.lines(message, font: font, width: DockMetrics.noticeTextWidth - 2)

        #expect(needed <= DockMetrics.noticeMaxLines, "\(message) needs \(needed) lines")
    }

    @Test("keeps every speech-model detail on its one line", arguments: details)
    func everyDetailFits(_ detail: String) {
        let font = NSFont.systemFont(ofSize: DockMetrics.footnoteSize)

        #expect(Self.lines(detail, font: font, width: DockMetrics.noticeTextWidth - 2) == 1)
    }

    @Test("offers the whole notice on hover, first line then second")
    func hoverCarriesBothLines() {
        let presentation = DictationPresenter.dock(
            for: .failed(
                DictationFailure(
                    message: "Recording stopped unexpectedly. Try again.", recovery: .retry,
                    severity: .recoverable, transcript: "the words that were said")))
        let line = presentation.primaryLine ?? ""

        #expect(
            DockView.hoverText(for: presentation, primaryLine: line)
                == "Recording stopped unexpectedly. Try again.\nthe words that were said")
    }

    @Test("offers only the first line on hover when there is no second")
    func hoverWithoutASecondLine() {
        let presentation = DictationPresenter.dock(for: .failed(.stillLoading))

        #expect(
            DockView.hoverText(for: presentation, primaryLine: SpeechModelLoad.refusal)
                == SpeechModelLoad.refusal)
    }
}
