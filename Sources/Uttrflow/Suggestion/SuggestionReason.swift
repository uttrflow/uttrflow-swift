import UttrflowPredictCapture
import struct Foundation.Date

/// Why the loop is running this turn, which decides what capture is told about it.
enum SuggestionReason {
    /// A key was pressed in another application.
    case keystroke
    /// Return was pressed, which is the user saying the value is finished.
    case returnPressed
    /// The application in front changed.
    case applicationChanged
    /// Time passed, which is the only way a pause can be noticed.
    case tick

    /// What must not be lost to a later wake: a Return commits a line, a switch changes the field, a tick changes nothing.
    var urgency: Int {
        switch self {
        case .returnPressed: 3
        case .applicationChanged: 2
        case .keystroke: 1
        case .tick: 0
        }
    }

    /// The event capture is handed for this turn, carrying the line rather than the whole field.
    func event(holding value: String, at moment: Date) -> CaptureEvent {
        switch self {
        case .keystroke, .applicationChanged: .keystroke(value, at: moment)
        case .returnPressed: .returnPressed(at: moment)
        case .tick: .tick(at: moment)
        }
    }
}
