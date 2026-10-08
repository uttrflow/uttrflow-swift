/// The rules every finished dictation satisfies before it is written, whatever the destination. See `Docs/insertion.md`.
public enum OutputSafety {
    /// Text that satisfies the rules, and how many characters were changed to get there.
    public struct Checked: Equatable, Sendable {
        public let text: String
        public let violations: Int
    }

    /// Removes escape sequences, turns other control characters into a space and drops trailing line breaks.
    public static func checked(_ text: String) -> Checked {
        var scalars: [Unicode.Scalar] = []
        var violations = 0
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\u{1B}" {
                violations += 1
                skipEscapeSequence(&iterator)
            } else if isForbiddenControl(scalar) {
                violations += 1
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        while let last = scalars.last, last == "\n" || last == "\r" {
            violations += 1
            scalars.removeLast()
        }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars)
        return Checked(text: String(result), violations: violations)
    }

    /// Whether a scalar is a C0 or C1 control or delete, other than tab and line feed.
    private static func isForbiddenControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\t" || scalar == "\n" { return false }
        return scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }

    /// Consumes the rest of an ANSI sequence: a CSI up to its final byte, or the one character after ESC.
    private static func skipEscapeSequence(_ iterator: inout String.UnicodeScalarView.Iterator) {
        guard let introducer = iterator.next(), introducer == "[" else { return }
        while let next = iterator.next(), !(0x40...0x7E).contains(next.value) {}
    }
}
