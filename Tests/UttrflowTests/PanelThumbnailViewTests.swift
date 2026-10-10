// Tests that a picture clip's thumbnail draws from the cache at once, and the card colour until it has one.

import AppKit
import Synchronization
import SwiftUI
import Testing

@testable import Uttrflow

@MainActor
@Suite("A picture clip's thumbnail")
struct PanelThumbnailViewTests {
    private final class RetrySourceState: @unchecked Sendable {
        private let state = Mutex((calls: 0, restored: false))
        var calls: Int { state.withLock { $0.calls } }
        func restore() { state.withLock { $0.restored = true } }
        func load() -> NSImage? {
            state.withLock { state in
                state.calls += 1
                return state.restored ? NSImage(size: NSSize(width: 4, height: 4)) : nil
            }
        }
    }

    /// The colour at the middle of `view` drawn at the row's size.
    private func middle(of view: some View) -> NSColor? {
        let renderer = ImageRenderer(content: view.frame(width: 34, height: 34))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).colorAt(x: 17, y: 17)?.usingColorSpace(.sRGB)
    }

    /// A solid red picture on disk, as a copied screenshot would be.
    private func redPicture() throws -> URL {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<80 {
            for y in 0..<80 { rep.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) }
        }
        let file = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-thumbnail-view-\(UUID().uuidString).png")
        try #require(rep.representation(using: .png, properties: [:])).write(to: file)
        return file
    }

    @Test("a row scrolled back into view draws its cached picture at once")
    func aCachedPictureDrawsAtOnce() async throws {
        let file = try redPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await PanelThumbnails.shared.picture(for: file) != nil)
        let colour = try #require(middle(of: PanelThumbnailView(file: file)))
        #expect(colour.redComponent > 0.9)
        #expect(colour.greenComponent < 0.3)
        #expect(colour.blueComponent < 0.3)
        #expect(colour != middle(of: Color.panelCard))
    }

    @Test("a picture not decoded yet draws the card colour, not an empty hole")
    func aMissDrawsTheCard() throws {
        let file = URL(fileURLWithPath: "/tmp/uttrflow-never-decoded-\(UUID().uuidString).png")
        let drawn = try #require(middle(of: PanelThumbnailView(file: file)))
        let card = try #require(middle(of: Color.panelCard))
        #expect(drawn == card)
        #expect(drawn.alphaComponent > 0)
    }

    @Test("a visible row retries a stale miss through its task")
    func aVisibleRowRetriesAMiss() async throws {
        let file = URL(fileURLWithPath: "/tmp/uttrflow-retry-\(UUID().uuidString).png")
        let state = RetrySourceState()
        let thumbnails = PanelThumbnails(
            source: PanelThumbnailSource { _, _ in state.load() }, retryAfter: .milliseconds(20))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless,
            backing: .buffered, defer: false)
        // Owned by this reference alone, so `close()` cannot release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PanelThumbnailView(file: file, thumbnails: thumbnails))
        window.orderFrontRegardless()
        defer { window.close() }

        for _ in 0..<1_000 where state.calls == 0 { try await Task.sleep(for: .milliseconds(1)) }
        #expect(state.calls == 1)
        state.restore()
        for _ in 0..<1_000 where thumbnails.cached(file) == nil {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(state.calls == 2)
        #expect(thumbnails.cached(file) != nil)
    }
}
