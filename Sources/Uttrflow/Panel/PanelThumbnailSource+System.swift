// The real thumbnail decoder, via ImageIO.

import AppKit
import ImageIO
import UniformTypeIdentifiers

extension PanelThumbnailSource {
    /// Decoded to the drawn size by `CGImageSourceCreateThumbnailAtIndex`, so the full picture is never held.
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
