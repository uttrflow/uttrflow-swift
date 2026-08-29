import AppKit
import ImageIO
import UniformTypeIdentifiers

extension PanelThumbnailSource {
    /// Decoded straight to the size it is drawn at.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` rather than `NSImage(contentsOf:)` and a
    /// frame: the second decodes the full picture and throws away all but a thirty-four
    /// point square of it, which for a Retina screenshot is twelve megabytes of work per
    /// row. This asks the file for the small version and never holds the large one.
    @MainActor static let system = PanelThumbnailSource { file, maxPixel in
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
