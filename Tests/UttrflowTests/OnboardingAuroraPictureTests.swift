// The onboarding aurora's cached picture keeps the original backdrop while it turns.

import AppKit
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Onboarding aurora picture")
struct OnboardingAuroraPictureTests {
    private let size = CGSize(width: 860, height: 560)
    /// An 8-bit picture quantised once and resampled when turned differs by up to 6 levels from the live blur.
    private static let tolerance: CGFloat = 6.0 / 255

    @Test("the blurred picture matches the original sign-in aurora at every turn")
    func cachedPictureMatchesTheOriginal() throws {
        for scale in [CGFloat(1), CGFloat(2)] {
            let picture = try #require(
                OnboardingAuroraPicture.image(
                    mood: .brand, saturation: 1, size: size, scale: scale))
            for degrees in [0.0, 23.0, 90.0, 180.0] {
                let original = try #require(render(originalAurora(degrees: degrees), scale: scale))
                let cached = try #require(render(cachedAurora(picture, degrees: degrees), scale: scale))
                #expect(maximumChannelDifference(original, cached) <= Self.tolerance)
            }
        }
    }

    @Test("the same size and mood reuse the blurred picture")
    func cachedPictureIsReused() throws {
        let first = try #require(
            OnboardingAuroraPicture.image(mood: .brand, saturation: 1, size: size, scale: 1))
        let second = try #require(
            OnboardingAuroraPicture.image(mood: .brand, saturation: 1, size: size, scale: 1))
        #expect(first === second)
    }

    private func originalAurora(degrees: Double) -> some View {
        AngularGradient(
            colors: BrandPalette.Onboarding.brandAurora.map { Color(rgb: $0) }
                + BrandPalette.Onboarding.brandAurora.prefix(1).map { Color(rgb: $0) },
            center: UnitPoint(x: 0.35, y: 0.55),
            startAngle: .degrees(120), endAngle: .degrees(480)
        )
        .frame(width: size.width * 1.5, height: size.height * 1.5)
        .rotationEffect(.degrees(degrees))
        .blur(radius: 70)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func cachedAurora(_ picture: NSImage, degrees: Double) -> some View {
        let canvas = OnboardingAuroraPicture.canvasSize(for: size)
        return Image(nsImage: picture)
            .resizable()
            .interpolation(.high)
            .frame(width: canvas.width, height: canvas.height)
            .rotationEffect(.degrees(degrees))
            .position(x: size.width / 2, y: size.height / 2)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func render(_ view: some View, scale: CGFloat) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// The largest channel difference in device RGB, converting each distinct pixel value once.
    private func maximumChannelDifference(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) -> CGFloat {
        guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh,
            let firstPixels = PackedPixels(first), let secondPixels = PackedPixels(second)
        else { return 1 }
        let sameLayout = first.colorSpace == second.colorSpace && first.bitmapFormat == second.bitmapFormat
        var differing = Set<UInt64>()
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                let a = firstPixels.value(x: x, y: y)
                let b = secondPixels.value(x: x, y: y)
                if a != b || !sameLayout {
                    firstPixels.note(a, x: x, y: y)
                    secondPixels.note(b, x: x, y: y)
                    differing.insert(UInt64(a) << 32 | UInt64(b))
                }
            }
        }
        var largest: CGFloat = 0
        for pair in differing {
            guard let a = firstPixels.deviceRGB(UInt32(truncatingIfNeeded: pair >> 32)),
                let b = secondPixels.deviceRGB(UInt32(truncatingIfNeeded: pair))
            else { return 1 }
            largest = max(largest, zip(a, b).map { abs($0 - $1) }.max() ?? 1)
        }
        return largest
    }
}

/// A bitmap's 8-bit pixels read as one value each, with every distinct value converted to device RGB once.
private final class PackedPixels {
    private let bitmap: NSBitmapImageRep
    private let data: UnsafeMutablePointer<UInt8>
    private var positions: [UInt32: (x: Int, y: Int)] = [:]
    private var converted: [UInt32: [CGFloat]] = [:]

    init?(_ bitmap: NSBitmapImageRep) {
        guard !bitmap.isPlanar, bitmap.bitsPerPixel == 32, let data = bitmap.bitmapData else { return nil }
        self.bitmap = bitmap
        self.data = data
    }

    func value(x: Int, y: Int) -> UInt32 {
        UnsafeRawPointer(data).loadUnaligned(fromByteOffset: y * bitmap.bytesPerRow + x * 4, as: UInt32.self)
    }

    /// Remembers where a value first appears, so its colour is read from the bitmap itself.
    func note(_ value: UInt32, x: Int, y: Int) {
        if positions[value] == nil { positions[value] = (x, y) }
    }

    /// The value's colour as `colorAt` reads it, converted to device RGB.
    func deviceRGB(_ value: UInt32) -> [CGFloat]? {
        if let known = converted[value] { return known }
        guard let position = positions[value],
            let colour = bitmap.colorAt(x: position.x, y: position.y)?.usingColorSpace(.deviceRGB)
        else { return nil }
        let channels = [
            colour.redComponent, colour.greenComponent, colour.blueComponent, colour.alphaComponent,
        ]
        converted[value] = channels
        return channels
    }
}
