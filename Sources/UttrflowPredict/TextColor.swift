import func Foundation.pow

/// Holds a field's own text colour in sRGB, which the ghost is drawn in so it reads against the field's background.
public struct TextColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Each channel is clamped into 0...1, and a channel that is not a number is taken as 0.
    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    /// Returns the WCAG relative luminance, 0 for black and 1 for white.
    public var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// Returns this colour laid at the given share over a background, which is what the eye sees of the ghost.
    public func blended(_ share: Double, over background: TextColor) -> TextColor {
        let share = Self.clamped(share)
        return TextColor(
            red: red * share + background.red * (1 - share),
            green: green * share + background.green * (1 - share),
            blue: blue * share + background.blue * (1 - share))
    }

    /// Returns the WCAG contrast ratio between two colours, 1 for none and 21 for black on white.
    public static func contrast(_ first: TextColor, _ second: TextColor) -> Double {
        let (light, dark) = (max(first.luminance, second.luminance), min(first.luminance, second.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    public static let black = TextColor(red: 0, green: 0, blue: 0)
    public static let white = TextColor(red: 1, green: 1, blue: 1)

    private static func clamped(_ channel: Double) -> Double {
        channel.isNaN ? 0 : min(max(channel, 0), 1)
    }

    /// Converts an sRGB channel to linear light with the sRGB transfer function.
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
