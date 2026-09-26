// What a Return turn tells capture, so characters typed after the last keystroke turn are not lost.
public import Foundation

/// Turns the line a Return turn read into the events capture needs, catching up a keystroke the Return displaced.
public enum ReturnCatchUp {
    /// The read line as a keystroke and then Return, when it is the handed line grown; otherwise Return alone.
    public static func events(read line: String, handed: String, at moment: Date) -> [CaptureEvent] {
        let read = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = handed.trimmingCharacters(in: .whitespacesAndNewlines)
        // A line that is not the handed one grown is what the field shows after the Return, not what was sent.
        guard read != last, read.hasPrefix(last) else { return [.returnPressed(at: moment)] }
        return [.keystroke(read, at: moment), .returnPressed(at: moment)]
    }
}
