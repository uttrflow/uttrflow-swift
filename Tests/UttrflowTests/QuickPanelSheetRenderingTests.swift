import AppKit
import SwiftUI
import Testing
import UttrflowClipboard
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Quick panel sheet rendering")
struct QuickPanelSheetRenderingTests {
    private let kinds: [PanelSheetPresentation.Kind] = [
        .aliasing, .moving, .confirmingDelete, .confirmingMakeNote, .renamingCategory,
        .deletingCategory, .formatting, .reindenting, .editing,
    ]

    private func sheet(
        _ kind: PanelSheetPresentation.Kind, enabled: Bool = true, destructive: Bool = false,
        hasDetails: Bool = false
    ) -> PanelSheetPresentation {
        PanelSheetPresentation(
            kind: kind, title: "Synthetic sheet", draft: "Synthetic collection",
            placeholder: "Synthetic name", note: hasDetails ? "Synthetic explanation" : nil,
            conflict: hasDetails ? "Synthetic conflict" : nil,
            collections: hasDetails
                ? [
                    PanelCollectionOption(name: "Synthetic collection", count: 2, isCurrent: true),
                    PanelCollectionOption(name: "Another collection", count: 0, isCurrent: false),
                ] : [],
            confirmTitle: "Synthetic confirm", isConfirmDestructive: destructive,
            isConfirmEnabled: enabled,
            diff: hasDetails
                ? [
                    TextDiff.Line(kind: .removed, text: "before"),
                    TextDiff.Line(kind: .added, text: "after"),
                    TextDiff.Line(kind: .same, text: ""),
                ] : [])
    }

    private func panel(_ sheet: PanelSheetPresentation) -> QuickPanelView {
        QuickPanelView(
            presentation: PanelPresentation(
                rows: [], filters: [], categories: [], query: "", searchPlaceholder: "Synthetic search",
                emptyState: nil, hint: "Synthetic hint", sheet: sheet))
    }

    private func picture(_ content: some View, width: CGFloat = 420) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content.frame(width: width, height: 340))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    @Test("every sheet kind draws an opaque dialog over a dimmed panel")
    func allKindsDraw() throws {
        for kind in kinds {
            let presentation = sheet(kind)
            let image = try picture(panel(presentation).sheetOverlay(presentation))
            #expect(image.pixelsWide == 420)
            #expect(image.pixelsHigh == 340)
            let middle = try #require(image.colorAt(x: 210, y: 170))
            let veil = try #require(image.colorAt(x: 1, y: 170))
            #expect(middle.alphaComponent > veil.alphaComponent)
            #expect(veil.alphaComponent > 0.3)
            #expect(veil.alphaComponent < 0.6)
        }
    }

    @Test("confirmation enabled and destructive states produce distinct button drawings")
    func confirmationsShowTheirState() throws {
        var drawings: [Data] = []
        for (enabled, destructive) in [(true, false), (false, false), (true, true)] {
            let presentation = sheet(.confirmingDelete, enabled: enabled, destructive: destructive)
            let image = try picture(panel(presentation).sheetOverlay(presentation))
            drawings.append(try #require(image.representation(using: .png, properties: [:])))
        }
        #expect(Set(drawings).count == 3)
    }

    @Test("collections, notes and signed diff remain visible in a narrow panel")
    func detailsFitNarrowPanel() throws {
        let simple = sheet(.moving)
        let detailed = sheet(.moving, hasDetails: true)
        let plain = try picture(panel(simple).sheetOverlay(simple), width: 320)
        let details = try picture(panel(detailed).sheetOverlay(detailed), width: 320)
        #expect(details.pixelsWide == 320)
        #expect(details.pixelsHigh == 340)
        #expect(
            details.representation(using: .png, properties: [:])
                != plain.representation(using: .png, properties: [:]))
        let edge = try #require(details.colorAt(x: 5, y: 170))
        #expect(edge.alphaComponent < 0.6, "the dialog respects the panel's horizontal inset")
    }

    @Test("hosting typing and non-typing sheets retains usable geometry through a transition")
    func liveSheetTransitions() throws {
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: panel(sheet(.editing)))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(host.fittingSize.height > 0)
        host.rootView = panel(sheet(.confirmingMakeNote, hasDetails: true))
        host.layoutSubtreeIfNeeded()
        #expect(host.frame.width == 420)
        #expect(host.frame.height == 360)
    }
}
