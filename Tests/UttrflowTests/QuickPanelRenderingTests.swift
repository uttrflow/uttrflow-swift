// Synthetic panel rows and collection chips exercise the rendered controls and their actions.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowClipboard
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Quick panel row rendering", .serialized)
struct QuickPanelRenderingTests {
    private func row(
        kind: ClipKind = .text, selected: Bool = false, decorated: Bool = false
    ) -> PanelRow {
        PanelRow(
            id: UUID(), summary: kind == .secret ? "••••••" : "Synthetic clip preview",
            additionalLineCount: decorated ? 12 : 0, preview: "Synthetic clip preview\nSecond line",
            kind: kind,
            swatch: kind == .colour ? ClipColour(red: 1, green: 0, blue: 0, alpha: 0.5) : nil,
            symbolName: "doc", when: "2 minutes ago", alias: decorated ? "/fixture" : nil,
            category: decorated ? "Fixtures" : nil, isPinned: decorated, isMasked: kind == .secret,
            isSelected: selected, matched: nil, measurements: decorated ? "80 × 60 · 1 KB" : nil,
            checklist: decorated ? "1 of 3" : nil,
            imageFile: kind == .image
                ? FileManager.default.temporaryDirectory.appending(
                    path: "uttrflow-row-\(UUID().uuidString).png")
                : nil,
            isImageMissing: kind == .image,
            language: kind == .code ? "swift" : nil, isMonospaced: kind == .code,
            containsDisplayHazards: decorated,
            actions: [PanelAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(UUID()))])
    }

    private func view(_ row: PanelRow, menu: Bool = false) -> QuickPanelRow {
        QuickPanelRow(
            row: row, isSelected: row.isSelected, hasSelection: row.isSelected, isMenuOpen: menu,
            hint: "Return inserts this clip", openCount: 1, onKey: { _ in },
            onAction: { _ in }, onMenu: { _ in })
    }

    private func render(_ content: some View, width: CGFloat = 420) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: width))
        host.setFrameSize(NSSize(width: width, height: host.fittingSize.height))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    @Test("every clip kind fits the same row without clipping its height")
    func kindsKeepRowGeometry() throws {
        for kind in ClipKind.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for selected in [false, true] {
                    let bitmap = try render(
                        view(row(kind: kind, selected: selected, decorated: true))
                            .environment(\.colorScheme, scheme))
                    #expect(bitmap.size.width == 420)
                    #expect(bitmap.size.height == QuickPanelMetrics.rowHeight)
                    let visiblePixels = (0..<bitmap.pixelsWide).filter { x in
                        bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0 > 0.1
                    }
                    #expect(visiblePixels.count > 10, "a row includes visible text and its kind glyph")
                }
            }
        }
    }

    @Test("selection draws a visible wash and opening a menu preserves row geometry")
    func selectionIsVisible() throws {
        let ordinary = try render(view(row()))
        let selected = try render(view(row(selected: true)))
        let menu = try render(view(row(selected: true), menu: true))
        let restingPixel = try #require(ordinary.colorAt(x: 210, y: 3))
        let selectedPixel = try #require(selected.colorAt(x: 210, y: 3))
        #expect(selectedPixel != restingPixel)
        #expect(menu.pixelsHigh == selected.pixelsHigh)
        #expect(menu.pixelsWide == selected.pixelsWide)
    }

    @Test("a multiline preview stays one row at narrow and wide panel sizes")
    func longPreviewDoesNotGrowTheRow() throws {
        let clip = Clip(
            text: String(repeating: "Synthetic preview words ", count: 60) + "\nSecond\nThird",
            kind: .text, copiedAt: Date(timeIntervalSince1970: 1_000_000), alias: "/long",
            category: "Fixtures", isPinned: true)
        var snapshot = PanelSnapshot(clips: [clip], selection: clip.id, now: clip.copiedAt)
        snapshot.scope = .pinned
        let presentation = PanelPresenter.present(snapshot)
        let displayed = try #require(presentation.rows.first)
        #expect(displayed.additionalLineCount == 2)
        for width: CGFloat in [320, 420, 680] {
            let bitmap = try render(view(displayed), width: width)
            #expect(bitmap.size.width == width)
            #expect(bitmap.size.height == QuickPanelMetrics.rowHeight)
        }
    }

    @Test("a colour swatch draws its copied colour rather than the generic glyph")
    func swatchKeepsItsColour() throws {
        let bitmap = try render(
            QuickPanelColourSwatch(colour: ClipColour(red: 1, green: 0, blue: 0, alpha: 1)), width: 22)
        let colours = (0..<22).flatMap { x in
            (0..<22).compactMap { y in bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) }
        }
        #expect(colours.contains { $0.redComponent > $0.greenComponent + 0.3 && $0.alphaComponent > 0.2 })
    }

    @Test("a selected masked row speaks no preview, including when decorated")
    func maskedPreviewStaysPrivate() throws {
        let hidden = row(kind: .secret, selected: true, decorated: true)
        let bitmap = try render(view(hidden, menu: true))
        #expect(bitmap.size.width == 420)
        #expect(hidden.tooltip == nil)
        #expect(!QuickPanelSpeech.label(for: hidden).contains("Synthetic clip preview"))
        #expect(!QuickPanelSpeech.label(for: hidden).contains("1 of 3"))
    }
}

@MainActor
@Suite(
    "Quick panel rendered actions", .serialized,
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct QuickPanelRenderedActionTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    private func withHost(
        _ view: some View, check: (NSView) async throws -> Void
    ) async rethrows {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 420, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view.frame(width: 420))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        try await check(host)
    }

    @Test("a row without named actions still exposes its default selection action")
    func rowDefaultActionWithoutMenu() async throws {
        let id = UUID()
        let row = PanelRow(
            id: id, summary: "Default activation fixture", kind: .text, symbolName: "doc",
            when: "now", alias: nil, category: nil, isPinned: false, isMasked: false,
            isSelected: false, matched: nil, isMonospaced: false, actions: [])
        var keys: [PanelKey] = []
        let view = QuickPanelRow(
            row: row, isSelected: false, hasSelection: false, isMenuOpen: false,
            hint: "Select this clip", openCount: 1,
            onKey: { keys.append($0) }, onAction: { _ in }, onMenu: { _ in })
        try await withHost(view) { host in
            let button = try #require(elements(under: host).first {
                ($0.accessibilityLabel?() ?? nil) == "Text, Default activation fixture, now"
            })
            #expect(button.accessibilityRole?() == .button)
            #expect(button.accessibilityPerformPress?() == true)
            #expect(keys == [.choose(id)])
        }
    }

    @Test("pressing the row sends its own clip key and each custom action sends its intent")
    func rowActionsReachCallbacks() async throws {
        let id = UUID()
        let actions = [
            PanelAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(id)),
            PanelAction(title: "Pin", symbolName: "pin", intent: .pin(id)),
            PanelAction(title: "Delete", symbolName: "trash", intent: .delete(id), isDestructive: true),
        ]
        let row = PanelRow(
            id: id, summary: "Action fixture", kind: .text, symbolName: "doc", when: "just now",
            alias: nil, category: nil, isPinned: false, isMasked: false, isSelected: true,
            matched: nil, isMonospaced: false, actions: actions)
        var keys: [PanelKey] = []
        var intents: [PanelIntent] = []
        let view = QuickPanelRow(
            row: row, isSelected: true, hasSelection: true, isMenuOpen: false,
            hint: "Return inserts this clip", openCount: 1, onKey: { keys.append($0) },
            onAction: { intents.append($0) }, onMenu: { _ in })
        try await withHost(view) { host in
            let button = try #require(
                elements(under: host).first {
                    ($0.accessibilityLabel?() ?? nil) == "Text, Action fixture, just now"
                })
            #expect(button.accessibilityRole?() == .button)
            #expect(button.isAccessibilitySelected?() == true)
            #expect(button.accessibilityPerformPress?() == true)
            #expect(keys == [.choose(id)])
            let custom: [NSAccessibilityCustomAction] = (button.accessibilityCustomActions?() ?? nil) ?? []
            #expect(Set(custom.map(\.name)) == ["Copy", "Pin", "Delete"])
            for action in custom {
                let handler = try #require(action.handler)
                #expect(handler())
            }
            #expect(
                Set(intents.map { String(describing: $0) })
                    == Set(actions.map { String(describing: $0.intent) }))
        }
    }

    @Test("a collection pill exposes its full name and rename and delete actions")
    func collectionActionsReachCallbacks() async throws {
        let title = String(repeating: "Synthetic collection ", count: 8)
        let presentation = PanelPresentation(
            rows: [], filters: [], categories: [], query: "", searchPlaceholder: "Search",
            emptyState: nil, hint: "")
        var intents: [PanelIntent] = []
        var presses = 0
        let panel = QuickPanelView(presentation: presentation, onIntent: { intents.append($0) })
        try await withHost(panel.pill(title, category: title, isActive: true, shortcut: 2) { presses += 1 }) {
            host in
            let button = try #require(
                elements(under: host).first {
                    ($0.accessibilityLabel?() ?? nil) == title
                })
            #expect(button.isAccessibilitySelected?() == true)
            #expect(button.accessibilityPerformPress?() == true)
            #expect(presses == 1)
            let custom: [NSAccessibilityCustomAction] = (button.accessibilityCustomActions?() ?? nil) ?? []
            #expect(Set(custom.map(\.name)) == ["Rename collection", "Delete collection"])
            for action in custom {
                let handler = try #require(action.handler)
                #expect(handler())
            }
            #expect(intents.contains(.renameCategory(title)))
            #expect(intents.contains(.deleteCategory(title)))
        }
    }
}
