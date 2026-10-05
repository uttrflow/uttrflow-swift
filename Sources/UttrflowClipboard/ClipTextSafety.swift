// Describes, displays and removes invisible characters without changing the stored clip.
import Foundation

public enum ClipTextSafety {
    /// Whether text has a character that can be hidden or interpreted by a destination.
    public static func containsDisplayHazards(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isDisplayHazard)
    }

    /// The text with invisible and control scalars shown as named code points.
    public static func escaped(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isDisplayHazard(scalar) {
                let codePoint = String(scalar.value, radix: 16, uppercase: true)
                let paddedCodePoint =
                    String(repeating: "0", count: max(0, 4 - codePoint.count))
                    + codePoint
                output.append(
                    contentsOf: "⟦U+\(paddedCodePoint) \(displayName(for: scalar))⟧"
                        .unicodeScalars)
            } else {
                output.append(scalar)
            }
        }
        return String(output)
    }

    /// The text with invisible and control scalars removed for an explicit cleaned paste.
    public static func removingDisplayHazards(from text: String) -> String {
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isDisplayHazard(scalar) {
            output.append(scalar)
        }
        return String(output)
    }

    /// Whether this scalar can disappear or change how following text is presented.
    public static func isDisplayHazard(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar != "\t", scalar != "\n", scalar != "\r" else { return false }
        return scalar.properties.isDefaultIgnorableCodePoint
            || scalar.properties.generalCategory == .control
            || scalar.properties.generalCategory == .format
    }

    /// Gives unnamed control scalars a useful category label alongside their exact code point.
    private static func displayName(for scalar: Unicode.Scalar) -> String {
        if let name = scalar.properties.name { return name }
        return scalar.properties.generalCategory == .control ? "CONTROL CHARACTER" : "UNNAMED CHARACTER"
    }
}
