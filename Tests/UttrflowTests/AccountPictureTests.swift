// Tests that the account picture is decoded once per drawn size and the banner's aurora is blurred once per size.

import AppKit
import Testing

@testable import Uttrflow

@MainActor
@Suite("Account pictures and the banner aurora")
struct AccountPictureTests {
    /// A square PNG `side` pixels wide, filled with one colour.
    private static func png(side: Int, grey: CGFloat) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: grey, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    @Test("a picture is decoded to the size it is drawn at, and kept for that size and those bytes")
    func decodesAtTheDrawnSize() async throws {
        let bytes = try Self.png(side: 400, grey: 0.3)
        let large = try #require(await AccountPictures.image(for: bytes, longestSide: 168))
        #expect(max(large.width, large.height) == 168)
        #expect(AccountPictures.cached(for: bytes, longestSide: 168) === large)
        #expect(AccountPictures.cached(for: bytes, longestSide: 90) == nil)
        #expect(await AccountPictures.image(for: bytes, longestSide: 168) === large)
        #expect(AccountPictures.cached(for: try Self.png(side: 400, grey: 0.6), longestSide: 168) == nil)
    }

    @Test("while the drawn size decodes, the largest size already decoded stands in")
    func anySizeStandsIn() async throws {
        let bytes = try Self.png(side: 300, grey: 0.45)
        #expect(AccountPictures.anyCached(for: bytes) == nil)
        let small = try #require(await AccountPictures.image(for: bytes, longestSide: 40))
        #expect(AccountPictures.anyCached(for: bytes) === small)
        let large = try #require(await AccountPictures.image(for: bytes, longestSide: 180))
        #expect(AccountPictures.anyCached(for: bytes) === large)
    }

    @Test("a cancelled decode cannot publish or cache its picture")
    func cancelledDecodeIsNotCached() async throws {
        let bytes = try Self.png(side: 53, grey: 0.17)
        let barrier = PictureDecodeBarrier()
        let loading = Task {
            await AccountPictures.image(for: bytes, longestSide: 47) { data, longestSide in
                await barrier.waitUntilReleased()
                return PictureDecoder.thumbnail(of: data, longestSide: longestSide)
            }
        }

        await barrier.waitUntilEntered()
        loading.cancel()
        await barrier.release()
        let image = await loading.value

        #expect(image == nil)
        #expect(AccountPictures.cached(for: bytes, longestSide: 47) == nil)
    }

    @Test("the banner's aurora is blurred once per size and handed back after that")
    func auroraIsBlurredOncePerSize() throws {
        let size = CGSize(width: 640, height: AccountBanner.height)
        let picture = try #require(AccountAurora.picture(for: size))
        #expect(picture.size == size)
        #expect(AccountAurora.picture(for: size) === picture)
        let wider = try #require(AccountAurora.picture(for: CGSize(width: 700, height: AccountBanner.height)))
        #expect(wider !== picture)
        #expect(AccountAurora.picture(for: .zero) == nil)
    }
}

private actor PictureDecodeBarrier {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilReleased() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
