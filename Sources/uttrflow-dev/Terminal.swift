// Helpers for writing to the terminal.
private import Foundation

/// Lines the commands write over themselves on standard error, so a countdown or a meter never scrolls away.
enum Terminal {
    static func show(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Wipes the progress line, so the next print starts clean.
    static func clearLine() {
        show("\r\u{1B}[2K")
    }
}
