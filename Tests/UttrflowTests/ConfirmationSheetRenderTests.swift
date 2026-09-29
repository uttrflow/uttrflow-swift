import AppKit
import SwiftUI
import Testing

@testable import Uttrflow

@MainActor
@Suite("Confirmation sheet rendering")
struct ConfirmationSheetRenderTests {
    private func effects(in view: NSView) -> [NSVisualEffectView] {
        view.subviews.flatMap { child in
            if let effect = child as? NSVisualEffectView { return [effect] }
            return effects(in: child)
        }
    }

    @Test("offscreen rendering keeps the appearance-aware veil without native material")
    func offscreenRenderKeepsTheVeil() throws {
        var lightRed: CGFloat?
        var darkRed: CGFloat?
        for scheme in [ColorScheme.light, .dark] {
            let sheet = ConfirmationSheet(
                confirmation: .signOut, onCancel: {}, onConfirm: {}
            )
            .environment(\.colorScheme, scheme)
            .frame(width: 800, height: 600)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 1

            let image = try #require(renderer.cgImage)
            let pixel = NSBitmapImageRep(cgImage: image).colorAt(x: 10, y: 10)
            let color = try #require(pixel?.usingColorSpace(.deviceRGB))
            #expect(image.width == 800)
            #expect(image.height == 600)
            #expect(color.alphaComponent > 0.5)
            if scheme == .light {
                lightRed = color.redComponent
            } else {
                darkRed = color.redComponent
            }
        }
        let lightValue = try #require(lightRed)
        let darkValue = try #require(darkRed)
        #expect(lightValue > darkValue + 0.3)
    }

    @Test("a live window receives native full-screen material behind the veil")
    func liveWindowGetsNativeMaterial() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(
            rootView: ConfirmationSheet(confirmation: .signOut, onCancel: {}, onConfirm: {})
                .frame(width: 800, height: 600))
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let effect = try #require(effects(in: host).first)
        #expect(effect.material == .fullScreenUI)
        #expect(effect.blendingMode == .withinWindow)
    }
}
