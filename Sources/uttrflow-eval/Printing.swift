internal import Foundation

/// Lines the commands write over themselves on standard error, so progress never scrolls a report away.
enum Terminal {
    static func show(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Wipes the progress line, so the next print starts clean.
    static func clearLine() {
        show("\r\u{1B}[2K")
    }
}

/// "1 passage", "3 passages": a count with its noun, in the plural when it is not one.
func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }

    /// Cut to fit a column, with an ellipsis so a truncated line cannot be mistaken for a short one.
    func truncated(to width: Int) -> String {
        count <= width ? self : String(prefix(width - 1)) + "…"
    }
}

extension Array where Element == String {
    /// The first few names, and how many more there were.
    func listed(upTo limit: Int = 5) -> String {
        prefix(limit).joined(separator: ", ") + (count > limit ? ", and \(count - limit) more" : "")
    }
}
