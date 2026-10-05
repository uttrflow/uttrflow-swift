import Foundation

/// One Accessibility answer, keeping apart the refusals the focused-field read decides differently on.
public enum FieldAnswer: @unchecked Sendable, Equatable {  // a value is an immutable object, read once
    /// The element answered with this value.
    case value(Any)
    /// The element supports the attribute but holds nothing in it now.
    case noValue
    /// The element does not support the attribute at all.
    case unsupported
    /// The application could not complete the message.
    case cannotComplete
    /// The application did not answer within the element's messaging timeout.
    case timedOut

    /// The answer as text, or nothing for a refusal or a value of another type.
    var string: String? {
        guard case .value(let value) = self else { return nil }
        return value as? String
    }

    /// The answer as a whole number, or nothing for a refusal or a value of another type.
    var integer: Int? {
        guard case .value(let value) = self else { return nil }
        return (value as? NSNumber)?.intValue ?? value as? Int
    }

    /// Accessibility's error codes for the answers told apart, as `AXError` raw values.
    static let successCode: Int32 = 0
    static let cannotCompleteCode: Int32 = -25204
    static let noValueCode: Int32 = -25212

    /// One message's outcome: a cannot-complete at or past the element's timeout is the timeout, any other failure unsupported.
    static func classify(
        code: Int32, value: Any?, elapsedSeconds: Double, timeoutSeconds: Double
    ) -> FieldAnswer {
        switch code {
        case successCode: value.map { .value($0) } ?? .noValue
        case noValueCode: .noValue
        case cannotCompleteCode: elapsedSeconds >= timeoutSeconds ? .timedOut : .cannotComplete
        default: .unsupported
        }
    }

    /// Two values match by their text or number; refusals match by kind.
    public static func == (lhs: FieldAnswer, rhs: FieldAnswer) -> Bool {
        switch (lhs, rhs) {
        case (.value, .value): lhs.string == rhs.string && lhs.integer == rhs.integer
        case (.noValue, .noValue), (.unsupported, .unsupported), (.cannotComplete, .cannotComplete),
            (.timedOut, .timedOut):
            true
        default: false
        }
    }
}
