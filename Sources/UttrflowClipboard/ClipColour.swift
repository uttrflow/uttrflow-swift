import Foundation

/// A colour, as four numbers a swatch can be filled with.
///
/// Plain `Double`s and no `NSColor` on purpose. This module is linked by the store and
/// runs on the copy path; an AppKit import here would drag a UI framework into a layer
/// that has no window to draw in. The view owns the conversion, and owning it there is
/// also what lets the swatch be drawn in whatever colour space the display asks for
/// without this file having an opinion about it.
public struct ClipColour: Sendable, Equatable {
    /// Straight sRGB, each in `0...1`. ``ClipKindDetector/colour(in:)`` clamps into that
    /// range rather than rejecting what falls outside it — see there for why.
    public let red: Double
    public let green: Double
    public let blue: Double
    /// Fully opaque is `1`. The notations that carry no alpha are read as opaque, so a
    /// caller never has to distinguish "no alpha given" from "alpha of one".
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension ClipKindDetector {
    /// What colour a clip is, for the swatch drawn beside it.
    ///
    /// Deliberately a different question from ``kind(of:)``, and deliberately a smaller
    /// answer. Detection asks whether the text is *written as* a colour, which is what
    /// decides the row's kind and is settled by the notation alone. This asks which
    /// colour, which only the notations with a direct sRGB reading can answer.
    /// `oklch(0.7 0.2 20)` is unmistakably a colour and is filed as one; it returns
    /// `nil` here, because converting it needs a real colour-space implementation and a
    /// swatch that is confidently the wrong red is worse than a row with no swatch on
    /// it. So the caller must treat `nil` as "no swatch", never as "not a colour".
    ///
    /// - Parameter text: Exactly what was copied, untrimmed, as ``kind(of:)`` takes it.
    /// - Returns: The colour for `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`,
    ///   `rgba()`, `hsl()` and `hsla()`; `nil` for everything else, including the
    ///   perceptual notations `ColourShape` still recognises.
    public static func colour(in text: String) -> ClipColour? {
        ColourValue.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Reads the colour notations that have a direct sRGB reading.
///
/// The set is smaller than the one ``ColourShape`` recognises, and the two are allowed
/// to differ: knowing a thing is a colour is worth a row's icon on its own, and is a far
/// cheaper question than knowing which. The one direction that must not drift is that
/// everything readable here is also detected there, which is pinned by a test rather
/// than by a shared regex, because sharing one would force detection down to whatever
/// this file can currently convert.
enum ColourValue {
    static func parse(_ text: String) -> ClipColour? {
        guard let first = text.first else { return nil }
        // The `#` is compulsory, and that is the whole reason bare `fff` is not a
        // colour. Three hex letters are also three ordinary English words — `dad`,
        // `bed`, `fee`, `ace`, `add` — and six are `decade`, `facade`, `deface`,
        // `deeded`. Accepting them would put a swatch beside a word far more often
        // than beside a colour, and the words are exactly the short ones a person
        // copies on their own. Requiring the hash costs a designer nothing: every
        // tool that emits hex emits the hash with it.
        if first == "#" { return hex(text.dropFirst()) }
        return functional(text)
    }

    // MARK: - Hex

    private static func hex(_ digits: Substring) -> ClipColour? {
        // `hexDigitValue` alone would accept the fullwidth digits, which the detector's
        // ASCII-only pattern never lets through; agreeing with it here keeps the two
        // from disagreeing about the same string.
        let values = digits.compactMap { $0.isASCII ? $0.hexDigitValue : nil }
        guard values.count == digits.count else { return nil }

        let channels: [Double]
        switch values.count {
        case 3, 4:
            // `#f0a` is `#ff00aa`, not `#f000a0`: the shorthand doubles each digit,
            // which is why the multiplier is 17 and not 16.
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

    /// Only the four that map straight onto sRGB. `hwb`, `lab`, `lch`, `oklab`, `oklch`
    /// and `color` are matched by ``ColourShape`` and left unread here.
    nonisolated(unsafe) private static let call =
        #/(?i)(?<name>rgba?|hsla?)\((?<arguments>[^()]*)\)/#

    private static func functional(_ text: String) -> ClipColour? {
        guard let match = text.wholeMatch(of: call) else { return nil }
        // Commas, spaces and the slash are all just separators. CSS spells the legacy
        // form `rgb(0, 128, 255)` and the modern one `rgb(0 128 255 / 50%)`, and reading
        // them through one splitter is less code than two parsers and cannot disagree
        // about the components either of them produced.
        let parts = match.output.arguments.split(whereSeparator: isSeparator)
        guard parts.count == 3 || parts.count == 4,
            let alpha = parts.count == 4 ? fraction(parts[3], of: 1) : 1,
            // `rgba()` with three components and `rgb()` with four are the same thing in
            // CSS Color 4, so the trailing `a` is not read as a promise of one.
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

    /// HSL to RGB, written the way the CSS colour specification writes it: three samples
    /// of one hue function, rather than a six-way switch on which sector the hue falls
    /// in. Identical numbers, a sixth of the branches, and branches are the unit a
    /// coverage floor is counted in.
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

    /// One component as a fraction of its maximum, clamped into `0...1`.
    ///
    /// Clamping rather than rejecting, which is the decision `rgb(300, 0, 0)` forces.
    /// It is what every browser does with that string, and it keeps a clip's kind a
    /// question about notation rather than about arithmetic: `rgb(300, 0, 0)` is a
    /// colour somebody is working on, almost always a typo or a slider read in the
    /// wrong units, and showing them red is more use than quietly filing it as prose
    /// while its neighbours get swatches.
    ///
    /// Non-finite values are the exception and are rejected, because `rgb(nan, 0, 0)`
    /// clamps to a confident, arbitrary colour rather than to an obviously wrong one.
    private static func fraction(_ part: Substring, of full: Double) -> Double? {
        let isPercentage = part.hasSuffix("%")
        guard let value = Double(isPercentage ? part.dropLast() : part), value.isFinite
        else { return nil }
        return clamped(value / (isPercentage ? 100 : full))
    }

    /// A hue in degrees, wrapped into one turn so that `hsl(-40, …)` and `hsl(320, …)`
    /// are the same colour, as CSS says they are.
    ///
    /// `deg` is the only unit spelled out. `rad`, `grad` and `turn` are legal CSS that
    /// no design tool has ever put on a clipboard, and a unit read as a bare number
    /// would be worse than no swatch.
    private static func angle(_ part: Substring) -> Double? {
        let digits = part.lowercased().hasSuffix("deg") ? part.dropLast(3) : part
        guard let degrees = Double(digits), degrees.isFinite else { return nil }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func clamped(_ value: Double) -> Double { max(0, min(1, value)) }
}
