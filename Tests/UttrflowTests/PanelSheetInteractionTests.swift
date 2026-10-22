import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Synthetic panel sheet and auxiliary controls",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI exposes controls only to a trusted accessibility client"),
    .serialized, .timeLimit(.minutes(1)))
struct PanelSheetInteractionTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    private func host<Content: View>(_ content: Content) async -> (NSWindow, NSHostingView<Content>) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return (window, host)
    }

    /// Suspends, which lets the run loop turn, until `found` yields an element; the suite's time limit ends a wait that never does.
    private func awaiting(_ found: () -> AnyObject?) async throws -> AnyObject {
        while true {
            if let element = found() { return element }
            if Task.isCancelled { throw CancellationError() }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func button(_ name: String, under host: NSView) async throws -> AnyObject {
        try await awaiting {
            elements(under: host).first {
                $0.accessibilityRole?() == .button && $0.accessibilityLabel?() as? String == name
            }
        }
    }

    /// Suspends until the sheet field holds focus, which the sheet takes on a later turn and echoes to its draft as it does.
    private func fieldFocused(in window: NSWindow) async throws {
        while !(window.firstResponder is NSText) {
            if Task.isCancelled { throw CancellationError() }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Suspends until the relayed value satisfies `condition`, since a press reports success before its action has run.
    private func relayed(until condition: () -> Bool) async throws {
        while !condition() {
            if Task.isCancelled { throw CancellationError() }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func panel(enabled: Bool = true, onKey: @escaping (PanelKey) -> Void) -> QuickPanelView {
        let sheet = PanelSheetPresentation(
            kind: .moving, title: "Synthetic move", draft: "", placeholder: "Synthetic collection",
            note: nil, conflict: nil,
            collections: [PanelCollectionOption(name: "Synthetic destination", count: 2, isCurrent: false)],
            confirmTitle: "Synthetic confirm", isConfirmEnabled: enabled)
        return QuickPanelView(
            presentation: PanelPresentation(
                rows: [], filters: [], categories: [], query: "", searchPlaceholder: "Synthetic search",
                emptyState: nil, hint: "", sheet: sheet), onKey: onKey)
    }

    @Test("sheet cancel, confirm and collection controls relay only synthetic panel keys")
    func sheetButtonsRelay() async throws {
        var keys: [PanelKey] = []
        let (window, view) = await host(panel { keys.append($0) })
        defer { window.close() }
        let cancel = try await button("Cancel", under: view)
        let confirm = try await button("Synthetic confirm", under: view)
        try await fieldFocused(in: window)
        keys.removeAll()
        #expect(cancel.accessibilityPerformPress?() == true)
        #expect(confirm.accessibilityPerformPress?() == true)
        let collection = try await awaiting {
            elements(under: view).first {
                $0.accessibilityRole?() == .button
                    && ($0.accessibilityLabel?() as? String)?.contains("Synthetic destination") == true
            }
        }
        #expect(collection.accessibilityPerformPress?() == true)
        try await relayed { keys.count >= 3 }
        #expect(keys == [.escape, .return, .draft("Synthetic destination")])
    }

    @Test("a disabled confirmation remains visible and refuses activation")
    func disabledConfirmation() async throws {
        var keys: [PanelKey] = []
        let (window, view) = await host(panel(enabled: false) { keys.append($0) })
        defer { window.close() }
        let confirm = try await button("Synthetic confirm", under: view)
        try await fieldFocused(in: window)
        keys.removeAll()
        #expect(confirm.isAccessibilityEnabled?() == false)
        _ = confirm.accessibilityPerformPress?()
        #expect(keys.isEmpty)
    }

    @Test("empty recovery controls invoke the supplied callbacks without a clipboard")
    func emptyRecoveryCallbacks() async throws {
        var clears = 0
        var intents: [PanelIntent] = []
        let state = MainEmptyState(symbolName: "doc", title: "Synthetic title", message: "Synthetic message")
        let action = PanelAction(
            title: "Synthetic recovery", symbolName: "magnifyingglass", intent: .keepQuery("synthetic"))
        let (window, view) = await host(
            PanelEmptyStateView(
                state: state, showsClearSearch: true, emptyAction: action,
                onClearSearch: { clears += 1 }, onIntent: { intents.append($0) }))
        defer { window.close() }
        #expect(try await button("Clear search · Esc", under: view).accessibilityPerformPress?() == true)
        #expect(try await button("Synthetic recovery", under: view).accessibilityPerformPress?() == true)
        try await relayed { clears >= 1 && !intents.isEmpty }
        #expect(clears == 1)
        #expect(intents == [.keepQuery("synthetic")])
    }

    @Test("Every App clears only the synthetic bound draft")
    func clearApplicationScope() async throws {
        var applications = ["com.example.synthetic-editor"]
        let binding = Binding(get: { applications }, set: { applications = $0 })
        let (window, view) = await host(
            ApplicationScopeRow(
                line: ApplicationScopeLine(applications: applications), applications: binding))
        defer { window.close() }
        #expect(try await button("Every App", under: view).accessibilityPerformPress?() == true)
        try await relayed { applications.isEmpty }
        #expect(applications.isEmpty)
        #expect(try await button("Add App…", under: view).isAccessibilityEnabled?() == true)
    }
}
