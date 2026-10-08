// Tests that the Dictionary and Snippets editor fields expose their visible labels to VoiceOver.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Dictionary and Snippets field accessibility names",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"),
    .serialized)
struct DictionarySnippetFieldAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The editor's elements, laid out in an offscreen window for inspection by the accessibility API.
    private func fieldNames<Content: View>(in view: Content) -> [String] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 720, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view.frame(width: 720))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        askAsAnAssistiveApp()
        return elements(under: host)
            .filter { $0.accessibilityRole?() == .textField || $0.accessibilityRole?() == .textArea }
            .compactMap { $0.accessibilityLabel?() ?? nil }
    }

    @Test("Dictionary fields are named by their visible labels")
    func dictionaryFields() {
        let presentation = DictionaryPresenter.page(
            for: DictionarySnapshot(draft: DictionaryDraft(), now: .now))
        let editor = DictionaryEditorView(
            editor: presentation.editor!, draft: .constant(DictionaryDraft()), onIntent: { _ in })

        #expect(Set(fieldNames(in: editor)) == ["Write it as", "Say it like"])
    }

    @Test("Snippet fields are named by their visible labels")
    func snippetFields() {
        let presentation = SnippetsPresenter.page(
            for: SnippetsSnapshot(draft: SnippetDraft(), now: .now))
        let editor = SnippetEditorView(
            editor: presentation.editor!, draft: .constant(SnippetDraft()), onIntent: { _ in })

        #expect(Set(fieldNames(in: editor)) == ["When I say", "Type this"])
    }
}
