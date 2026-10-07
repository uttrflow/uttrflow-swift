// Which colour a colour clip is, for the swatch.

import Foundation

/// A colour as four `Double`s, with no `NSColor`, so the store never links AppKit.
public struct ClipColour: Sendable, Equatable {
    /// Straight sRGB in `0...1`; values outside their notation's range have no swatch.
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

/// Reads bounded sRGB values from colours and common declarations.
enum ColourValue {
    static func parse(_ text: String) -> ClipColour? {
        let declaration = declarationValue(text)
        let value = declaration ?? text
        guard let first = value.first else { return nil }
        // The `#` is compulsory, or `dad`, `bed` and `facade` would get swatches.
        if first == "#" {
            let digits = value.dropFirst()
            guard declaration != nil || acceptsHash(digits) else { return nil }
            return hex(digits)
        }
        if let colour = functional(value) { return colour }
        if value.lowercased() == "transparent" {
            return ClipColour(red: 0, green: 0, blue: 0, alpha: 0)
        }
        return CSSNamedColour.value(named: value)
    }

    private static func declarationValue(_ text: String) -> String? {
        if let colon = text.firstIndex(of: ":") {
            let property = text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard isColourProperty(property) else { return nil }
            return cleaned(String(text[text.index(after: colon)...]))
        }
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let name = text[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        guard isColourProperty(name) else { return nil }
        let rawValue = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard rawValue.count >= 2, let quote = rawValue.first, rawValue.last == quote,
            quote == "\"" || quote == "'"
        else { return nil }
        let value = rawValue.dropFirst().dropLast()
        guard !value.contains(quote) else { return nil }
        return String(value)
    }

    private static func cleaned(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped =
            value.hasSuffix(";")
            ? String(value.dropLast()).trimmingCharacters(in: .whitespaces)
            : value
        guard !unwrapped.isEmpty, !unwrapped.contains(";") else { return nil }
        return unwrapped
    }

    private static func isColourProperty(_ name: String) -> Bool {
        name == "color" || name == "background" || name == "fill" || name == "stroke"
            || name == "bgcolor" || name.hasSuffix("-color") || name.hasPrefix("--")
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

    private static func acceptsHash(_ digits: Substring) -> Bool {
        let lowercase = String(digits).lowercased()
        guard digits.count == 3 || digits.count == 4 else {
            let lowercaseWord = lowercase.allSatisfy { $0.isASCII && $0.isLetter }
            return !lowercaseWord || lowercase.allSatisfy { $0 == lowercase.first }
        }
        let lettersOnly = lowercase.allSatisfy { $0.isASCII && $0.isLetter }
        let repeated = lowercase.allSatisfy { $0 == lowercase.first }
        return !digits.allSatisfy(\.isNumber) && (!lettersOnly || repeated)
    }

    // MARK: - The functional notations

    /// Only the four that map straight onto sRGB; the perceptual notations are detected and left unread.
    nonisolated(unsafe) private static let call =
        #/(?i)(?<name>rgba?|hsla?)\((?<arguments>[^()]*)\)/#

    private static func functional(_ text: String) -> ClipColour? {
        guard let match = text.wholeMatch(of: call) else { return nil }
        let arguments = match.output.arguments
        let isRGB = match.output.name.lowercased().hasPrefix("rgb")
        guard let parts = components(in: arguments, commaRGBChannels: isRGB),
            parts.count == 3 || (parts.count == 4 && usesAlphaSeparator(arguments)),
            let alpha = parts.count == 4 ? bounded(parts[3], of: 1) : 1,
            // `rgba()` with three components and `rgb()` with four are the same thing in CSS Color 4.
            let channels = isRGB ? straight(parts) : fromHue(parts)
        else { return nil }
        return ClipColour(
            red: channels.0, green: channels.1, blue: channels.2, alpha: alpha)
    }

    private static func components(
        in arguments: Substring, commaRGBChannels: Bool
    ) -> [Substring]? {
        let source = String(arguments).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        if source.contains(",") {
            guard !source.contains("/") else { return nil }
            let parts = source.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { !$0.isWhitespace } }) else {
                return nil
            }
            if commaRGBChannels {
                guard parts.count >= 3 else { return nil }
                let firstIsPercentage = parts[0].hasSuffix("%")
                guard parts[1].hasSuffix("%") == firstIsPercentage,
                    parts[2].hasSuffix("%") == firstIsPercentage
                else { return nil }
            }
            return parts.map { $0[...] }
        }

        let sections = source.split(separator: "/", omittingEmptySubsequences: false)
        guard sections.count <= 2, sections.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        let channels = sections[0].split(whereSeparator: \.isWhitespace)
        guard channels.count == 3 else { return nil }
        guard sections.count == 2 else { return channels }
        let alpha = sections[1].split(whereSeparator: \.isWhitespace)
        guard alpha.count == 1 else { return nil }
        return channels + alpha
    }

    private static func usesAlphaSeparator(_ arguments: Substring) -> Bool {
        arguments.contains(",") || arguments.contains("/")
    }

    private static func straight(_ parts: [Substring]) -> (Double, Double, Double)? {
        let values = parts.prefix(3).compactMap { bounded($0, of: 255) }
        guard values.count == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    /// HSL to RGB as the CSS specification writes it: three samples of one hue function.
    private static func fromHue(_ parts: [Substring]) -> (Double, Double, Double)? {
        guard let hue = angle(parts[0]),
            let saturation = bounded(parts[1], of: 100),
            let lightness = bounded(parts[2], of: 100)
        else { return nil }

        let amplitude = saturation * min(lightness, 1 - lightness)
        func channel(_ offset: Double) -> Double {
            let position = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            return lightness - amplitude * max(-1, min(position - 3, 9 - position, 1))
        }
        return (channel(0), channel(8), channel(4))
    }

    // MARK: - Components

    /// One finite component inside its notation's range.
    private static func bounded(_ part: Substring, of full: Double) -> Double? {
        let isPercentage = part.hasSuffix("%")
        guard let value = Double(isPercentage ? part.dropLast() : part), value.isFinite
        else { return nil }
        let maximum = isPercentage ? 100 : full
        guard value >= 0, value <= maximum else { return nil }
        return value / maximum
    }

    /// A hue inside one turn, converted from any CSS angle unit into degrees.
    private static func angle(_ part: Substring) -> Double? {
        let lowercase = part.lowercased()
        let digits: Substring
        let multiplier: Double
        if lowercase.hasSuffix("deg") {
            digits = part.dropLast(3)
            multiplier = 1
        } else if lowercase.hasSuffix("grad") {
            digits = part.dropLast(4)
            multiplier = 0.9
        } else if lowercase.hasSuffix("rad") {
            digits = part.dropLast(3)
            multiplier = 180 / .pi
        } else if lowercase.hasSuffix("turn") {
            digits = part.dropLast(4)
            multiplier = 360
        } else {
            digits = part
            multiplier = 1
        }
        guard let value = Double(digits), value.isFinite else { return nil }
        let degrees = value * multiplier
        guard degrees.isFinite, (0...360).contains(degrees) else { return nil }
        return degrees == 360 ? 0 : degrees
    }
}
