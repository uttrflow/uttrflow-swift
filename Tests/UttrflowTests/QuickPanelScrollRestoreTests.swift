// Reopening the panel keeps its restored selection in the visible part of the list.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowClipboard
import UttrflowTestSupport
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Restoring a quick panel selection",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its accessibility tree for a trusted client"),
    .serialized,
    .timeLimit(.minutes(1))
)
struct QuickPanelScrollRestoreTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("the restored row is inside the list viewport on reopen")
    func restoredSelectionScrollsIntoView() async throws {
        let now = Date()
        let clips = (0..<40).map { index in
            Clip(
                text: "clip-\(index)", kind: .text,
                copiedAt: now.addingTimeInterval(TimeInterval(-index)))
        }
        let selected = try #require(clips.last)
        let snapshot = PanelSnapshot(clips: clips, selection: selected.id, now: now)
        let presentation = PanelPresenter.present(snapshot)
        let label = QuickPanelSpeech.label(for: try #require(presentation.selectedRow))

        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: QuickPanelView(presentation: presentation, openCount: 1))
        window.contentView = host
        window.orderFrontRegardless()

        try await eventually {
            host.subviews
                .flatMap { descendants(of: $0) }
                .contains { $0 is NSScrollView && $0.bounds.height > 100 && $0.bounds.width > 300 }
        }
        await askAsAnAssistiveApp()

        let scrollView = try #require(
            host.subviews
                .flatMap { descendants(of: $0) }
                .compactMap { $0 as? NSScrollView }
                .first { $0.bounds.height > 100 && $0.bounds.width > 300 })
        let scrollFrame = window.convertToScreen(scrollView.convert(scrollView.bounds, to: nil))
        // The restore scrolls with an eased animation, and the lazy list builds the row only once it is near.
        try await eventually {
            let row = elements(under: host).first { ($0.accessibilityLabel?() ?? nil) == label }
            return (row?.accessibilityFrame?() ?? nil)?.intersects(scrollFrame) == true
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
