// Tests that the floating windows' glass shadows fall inside the window that hosts them.

import AppKit
import SwiftUI
import Testing

@testable import Uttrflow

/// How far past each edge of `size` a view's drawing reaches, in points, when nothing clips it.
@MainActor
private func overhang(
    of view: some View, fitting size: CGSize, appearance: NSAppearance.Name
) throws
    -> NSEdgeInsets
{
    let room: CGFloat = 80
    let renderer = ImageRenderer(
        content: view.frame(width: size.width, height: size.height).padding(room))
    renderer.scale = 1
    var image: CGImage?
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance { image = renderer.cgImage }
    let picture = try #require(image)
    let bitmap = NSBitmapImageRep(cgImage: picture)
    var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            // 3 of 255 is below what a person can see as an edge on any desktop.
            guard let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent, alpha > 3 / 255 else { continue }
            (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
        }
    }
    try #require(minX <= maxX)
    return NSEdgeInsets(
        top: room - CGFloat(minY), left: room - CGFloat(minX),
        bottom: CGFloat(maxY + 1) - room - size.height, right: CGFloat(maxX + 1) - room - size.width)
}

@MainActor
@Suite("Floating glass shadows fit their windows")
struct FloatingGlassShadowTests {
    nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test(
        "the dock's glass and its shadow fit inside the margin the panel is sized to", arguments: appearances)
    func dockShadowFits(appearance: NSAppearance.Name) throws {
        let capsule = CGSize(width: 220, height: DockSetupMetrics.capsuleHeight)
        let form = Color.clear
            .frame(width: capsule.width, height: capsule.height)
            .glass(cornerRadius: capsule.height / 2)
            .padding(DockMetrics.gripHitPadding)
        let window = CGSize(
            width: capsule.width + DockMetrics.gripHitPadding * 2,
            height: capsule.height + DockMetrics.gripHitPadding * 2)
        let reach = try overhang(of: form, fitting: window, appearance: appearance)
        #expect(reach.top <= 0)
        #expect(reach.left <= 0)
        #expect(reach.bottom <= 0)
        #expect(reach.right <= 0)
    }

    @Test("the dock panel draws the window shadow the glass leaves out")
    func dockPanelCastsShadow() {
        #expect(DockPanelController().castsWindowShadow)
    }

    @Test("the menu bar popover's glass and its shadow fit inside its shadow margin", arguments: appearances)
    func menuBarShadowFits(appearance: NSAppearance.Name) throws {
        let card = CGSize(width: 300, height: 200)
        let margin = MenuBarPopoverView.shadowMargin
        let form = Color.clear
            .frame(width: card.width, height: card.height)
            .menuBarGlass()
            .padding(margin)
        let window = CGSize(width: card.width + margin * 2, height: card.height + margin * 2)
        let reach = try overhang(of: form, fitting: window, appearance: appearance)
        #expect(reach.top <= 0)
        #expect(reach.left <= 0)
        #expect(reach.bottom <= 0)
        #expect(reach.right <= 0)
    }
}
