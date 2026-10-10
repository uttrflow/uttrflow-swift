// Turns a copied picture's bytes into the PNG the store keeps, sized from its header before any pixel is decoded.

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A copied picture as the store keeps it: PNG bytes and the size in pixels. See `Docs/clipboard-budget.md`.
enum PictureFlavour {
    typealias Picture = (data: Data, width: Int, height: Int)

    /// Decodes the first image upright at no more than the given longest edge; a test swaps it to count decodes.
    typealias Decoder = (CGImageSource, Int) -> CGImage?

    /// What a picture's bytes came to once its header was read.
    enum Reading {
        /// The picture as the store keeps it.
        case kept(Picture)
        /// A header claiming more pixels than `ClipboardBudget.largestPicture`, refused without a decode.
        case refused(width: Int, height: Int)
        /// Bytes that are not this flavour, or that no reader understands.
        case unreadable

        /// The kept picture, or `nil` for a refusal or unreadable bytes.
        var picture: Picture? {
            guard case .kept(let picture) = self else { return nil }
            return picture
        }
    }

    /// PNG bytes kept as they are, sized from the header without decoding a pixel.
    static func fromPNG(_ data: Data, within budget: ClipboardBudget = .standard) -> Picture? {
        readingPNG(data, within: budget).picture
    }

    /// Any other picture ImageIO reads, such as TIFF, HEIC or JPEG, encoded once as PNG.
    static func converting(_ data: Data, within budget: ClipboardBudget = .standard) -> Picture? {
        reading(data, within: budget).picture
    }

    /// PNG bytes judged by their header, kept as they are when the picture fits.
    static func readingPNG(_ data: Data, within budget: ClipboardBudget) -> Reading {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) == UTType.png.identifier as CFString,
            let size = pixelSize(of: source)
        else { return .unreadable }
        guard fits(size, within: budget) else { return .refused(width: size.width, height: size.height) }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        // ImageIO hands back an image for a truncated pixel stream; only its decoded pixels prove it reads.
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options), image.dataProvider?.data != nil
        else { return .unreadable }
        return .kept((data, size.width, size.height))
    }

    /// Any picture judged by its header, then decoded no larger than `budget.pictureEdge` and encoded once as PNG.
    static func reading(
        _ data: Data, within budget: ClipboardBudget, decode: Decoder = PictureFlavour.upright(from:edge:)
    ) -> Reading {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let size = pixelSize(of: source)
        else { return .unreadable }
        if CGImageSourceGetType(source) == UTType.png.identifier as CFString {
            return readingPNG(data, within: budget)
        }
        guard fits(size, within: budget) else { return .refused(width: size.width, height: size.height) }
        let longest = max(size.width, size.height)
        let edge = budget.pictureEdge > 0 ? min(longest, budget.pictureEdge) : longest
        guard let image = decode(source, edge), let picture = png(of: image) else { return .unreadable }
        return .kept(picture)
    }

    /// Whether a header's size is within `largestPicture`, where zero means no bound.
    static func fits(_ size: (width: Int, height: Int), within budget: ClipboardBudget) -> Bool {
        budget.fitsPicture(width: size.width, height: size.height)
    }

    /// The first image turned the way its orientation tag says it is shown, at most `edge` pixels long.
    static func upright(from source: CGImageSource, edge: Int) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard let size = pixelSize(of: source) else { return nil }
        if orientation == 1, max(size.width, size.height) <= edge {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        // Downsampled while decoding, so a picture over the edge never exists at full size.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A decoded picture encoded once as PNG, sized from the image itself.
    static func png(of image: CGImage) -> Picture? {
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
    static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        return (width, height)
    }
}
