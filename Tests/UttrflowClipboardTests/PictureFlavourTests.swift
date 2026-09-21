// Tests for turning a copied picture's bytes into the PNG the store keeps.

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import UttrflowClipboard

/// A screenshot is PNG already, so re-encoding it is pure cost; every other flavour is converted once.
@Suite("A copied picture becomes PNG without an uncompressed copy")
struct PictureFlavourTests {
    /// A small picture with a gradient in it, so its encodings are not all alike.
    static func image(width: Int = 40, height: Int = 30) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<width {
            context.setFillColor(red: Double(x) / Double(width), green: 0.4, blue: 0.7, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try #require(context.makeImage())
    }

    /// The picture encoded as `type`.
    static func encoded(_ image: CGImage, as type: UTType) throws -> Data {
        let out = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(out as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    @Test("PNG bytes are kept exactly as they arrived, sized from the header")
    func pngKeptAsIs() throws {
        let png = try Self.encoded(Self.image(), as: .png)
        let picture = try #require(PictureFlavour.fromPNG(png))
        #expect(picture.data == png)
        #expect(picture.width == 40)
        #expect(picture.height == 30)
    }

    @Test("bytes that only claim to be PNG are refused, so the next flavour is tried")
    func notPNGRefused() throws {
        #expect(PictureFlavour.fromPNG(Data("not a picture".utf8)) == nil)
        #expect(PictureFlavour.fromPNG(try Self.encoded(Self.image(), as: .tiff)) == nil)
    }

    @Test(
        "other flavours are encoded once as PNG at their own size",
        arguments: [UTType.tiff, .jpeg, .heic, .bmp])
    func othersConverted(_ type: UTType) throws {
        let data = try Self.encoded(Self.image(width: 24, height: 16), as: type)
        let picture = try #require(PictureFlavour.converting(data))
        let source = try #require(CGImageSourceCreateWithData(picture.data as CFData, nil))
        #expect(CGImageSourceGetType(source) == UTType.png.identifier as CFString)
        #expect(picture.width == 24)
        #expect(picture.height == 16)
    }

    @Test("a PNG handed to the converter is still kept as it is")
    func pngThroughConverter() throws {
        let png = try Self.encoded(Self.image(), as: .png)
        #expect(PictureFlavour.converting(png)?.data == png)
    }

    @Test("bytes no reader understands give no picture")
    func garbage() {
        #expect(PictureFlavour.converting(Data()) == nil)
        #expect(PictureFlavour.converting(Data("not a picture".utf8)) == nil)
    }
}
