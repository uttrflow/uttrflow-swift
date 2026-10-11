// Collection chips keep bounded geometry and carry their complete names to assistive clients.

import AppKit
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Quick panel chip rendering", .serialized)
struct QuickPanelChipRenderingTests {
    private func presentation(active: Int?) -> PanelPresentation {
        let categories = (1...12).map { position in
            PanelCategoryChip(
                title: position == 1 ? "All" : "Fixture \(position)",
                category: position == 1 ? nil : "Fixture \(position)",
                shortcut: position <= 9 ? position : nil, position: position,
                isActive: position == active)
        }
        return PanelPresentation(
            rows: [],
            filters: [
                PanelFilterChip(title: "All", filter: .all, isActive: true),
                PanelFilterChip(title: "Text", filter: .text, isActive: false),
            ], categories: categories, query: "", searchPlaceholder: "Search", emptyState: nil, hint: "")
    }

    private func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    @Test("long collection names cannot stretch a pill or make it multiline")
    func longNamesStayBounded() throws {
        let panel = QuickPanelView(presentation: presentation(active: 2))
        for title in ["Fixture", String(repeating: "Synthetic collection ", count: 12), "First\nSecond"] {
            for active in [false, true] {
                for shortcut: Int? in [nil, 2] {
                    let bitmap = try render(
                        panel.pill(title, category: title, isActive: active, shortcut: shortcut) {})
                    #expect(bitmap.pixelsHigh == 26)
                    #expect(bitmap.pixelsWide > 18)
                    #expect(bitmap.pixelsWide <= 220)
                }
            }
        }
    }

    @Test("active and inactive chips have visibly different fills in both appearances")
    func activeChipHasVisibleFill() throws {
        let panel = QuickPanelView(presentation: presentation(active: 2))
        for scheme in [ColorScheme.light, .dark] {
            let resting = try render(
                panel.pill("Fixture", category: "Fixture", isActive: false, shortcut: nil) {}
                    .environment(\.colorScheme, scheme))
            let active = try render(
                panel.pill("Fixture", category: "Fixture", isActive: true, shortcut: nil) {}
                    .environment(\.colorScheme, scheme))
            let x = resting.pixelsWide / 2
            let restingPixel = try #require(resting.colorAt(x: x, y: 3))
            let activePixel = try #require(active.colorAt(x: x, y: 3))
            #expect(activePixel.alphaComponent > restingPixel.alphaComponent)
            #expect(active.pixelsHigh == resting.pixelsHigh)
        }
    }

    @Test("collections beyond the numeric shortcuts remain in the scrolling strip")
    func longStripKeepsItsGeometry() throws {
        for selected: Int? in [nil, 1, 2, 12] {
            let panel = QuickPanelView(presentation: presentation(active: selected))
            let bitmap = try render(panel.chipRow.frame(width: 420))
            #expect(bitmap.pixelsWide == 420)
            #expect(bitmap.pixelsHigh == Int(QuickPanelMetrics.chipRowHeight) + 10)
        }
    }

    @Test("an All pill with no collection still draws its shortcut")
    func allPillDrawsWithoutCollectionActions() throws {
        let panel = QuickPanelView(presentation: presentation(active: 1))
        let all = try render(panel.pill("All", category: nil, isActive: true, shortcut: 1) {})
        let withoutShortcut = try render(panel.pill("All", category: nil, isActive: true, shortcut: nil) {})
        #expect(all.pixelsWide > withoutShortcut.pixelsWide)
        #expect(all.pixelsHigh == withoutShortcut.pixelsHigh)
    }
}
