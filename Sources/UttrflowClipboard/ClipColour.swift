// Which colour a colour clip is, for the swatch.

import Foundation

/// A colour as four `Double`s, with no `NSColor`, so the store never links AppKit.
public struct ClipColour: Sendable, Equatable {
    /// Straight sRGB in `0...1`; `ClipKindDetector.colour(in:)` clamps into the range rather than rejecting.
    public let red: Double
    public let green: Double
    public let blue: Double
    /// Fully opaque is `1`; notations with no alpha read as opaque.
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension ClipKindDetector {
    /// Which colour a clip is, for the swatch; `nil` means "no swatch", never "not a colour".
    public static func colour(in text: String) -> ClipColour? {
        ColourValue.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Reads the colour notations with a direct sRGB reading, a smaller set than `ColourShape` detects.
enum ColourValue {
    static func parse(_ text: String) -> ClipColour? {
        guard let first = text.first else { return nil }
        // The `#` is compulsory, or `dad`, `bed` and `facade` would get swatches.
        if first == "#" { return hex(text.dropFirst()) }
        return functional(text)
    }

    // MARK: - Hex

    private static func hex(_ digits: Substring) -> ClipColour? {
        // ASCII only, agreeing with the detector, which never lets fullwidth digits through.
        let values = digits.compactMap { $0.isASCII ? $0.hexDigitValue : nil }
        guard values.count == digits.count else { return nil }

        let channels: [Double]
        switch values.count {
        case 3, 4:
            // `#f0a` is `#ff00aa`: the shorthand doubles each digit, so the multiplier is 17.
            channels = values.map { Double($0 * 17) / 255 }
        case 6, 8:
            channels = stride(from: 0, to: values.count, by: 2)
                .map { Double(values[$0] << 4 | values[$0 + 1]) / 255 }
        default:
            // One, two, five, seven and nine digits are not a notation in any tool.
            return nil
        }
        return ClipColour(
            red: channels[0], green: channels[1], blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 1)
    }

    // MARK: - The functional notations

    /// Only the four that map straight onto sRGB; the perceptual notations are detected and left unread.
    nonisolated(unsafe) private static let call =
        #/(?i)(?<name>rgba?|hsla?)\((?<arguments>[^()]*)\)/#

    private static func functional(_ text: String) -> ClipColour? {
        guard let match = text.wholeMatch(of: call) else { return nil }
        // Commas, spaces and the slash are all separators, so one splitter reads both CSS forms.
        let parts = match.output.arguments.split(whereSeparator: isSeparator)
        guard parts.count == 3 || parts.count == 4,
            let alpha = parts.count == 4 ? fraction(parts[3], of: 1) : 1,
            // `rgba()` with three components and `rgb()` with four are the same thing in CSS Color 4.
            let channels = match.output.name.lowercased().hasPrefix("rgb")
                ? straight(parts) : fromHue(parts)
        else { return nil }
        return ClipColour(
            red: channels.0, green: channels.1, blue: channels.2, alpha: alpha)
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "," || character == "/" || character.isWhitespace
    }

    private static func straight(_ parts: [Substring]) -> (Double, Double, Double)? {
        let values = parts.prefix(3).compactMap { fraction($0, of: 255) }
        guard values.count == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    /// HSL to RGB as the CSS specification writes it: three samples of one hue function.
    private static func fromHue(_ parts: [Substring]) -> (Double, Double, Double)? {
        guard let hue = angle(parts[0]),
            let saturation = fraction(parts[1], of: 100),
            let lightness = fraction(parts[2], of: 100)
        else { return nil }

        let amplitude = saturation * min(lightness, 1 - lightness)
        func channel(_ offset: Double) -> Double {
            let position = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            return lightness - amplitude * max(-1, min(position - 3, 9 - position, 1))
        }
        return (channel(0), channel(8), channel(4))
    }

    // MARK: - Components

    /// One component as a fraction of its maximum, clamped like a browser does; non-finite is rejected.
    private static func fraction(_ part: Substring, of full: Double) -> Double? {
        let isPercentage = part.hasSuffix("%")
        guard let value = Double(isPercentage ? part.dropLast() : part), value.isFinite
        else { return nil }
        return clamped(value / (isPercentage ? 100 : full))
    }

    /// A hue in degrees wrapped into one turn; `deg` is the only unit read.
    private static func angle(_ part: Substring) -> Double? {
        let digits = part.lowercased().hasSuffix("deg") ? part.dropLast(3) : part
        guard let degrees = Double(digits), degrees.isFinite else { return nil }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func clamped(_ value: Double) -> Double { max(0, min(1, value)) }
}
