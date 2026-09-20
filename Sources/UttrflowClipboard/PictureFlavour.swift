// Turns a copied picture's bytes into the PNG the store keeps, without an uncompressed copy in between.

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A copied picture as the store keeps it: PNG bytes and the size in pixels. See `Docs/clipboard-budget.md`.
enum PictureFlavour {
    /// PNG bytes kept as they are, sized from the header without decoding a pixel.
    static func fromPNG(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) == UTType.png.identifier as CFString,
            let size = pixelSize(of: source)
        else { return nil }
        return (data, size.width, size.height)
    }

    /// Any other picture ImageIO reads, such as TIFF, HEIC or JPEG, encoded once as PNG.
    static func converting(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        if CGImageSourceGetType(source) == UTType.png.identifier as CFString {
            return fromPNG(data)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return png(of: image)
    }

    /// A decoded picture encoded once as PNG, sized from the image itself.
    static func png(of image: CGImage) -> (data: Data, width: Int, height: Int)? {
        let out = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                out as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (out as Data, image.width, image.height)
    }

    /// The first image's size in pixels, read from its properties rather than its pixels.
    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        return (width, height)
    }
}
