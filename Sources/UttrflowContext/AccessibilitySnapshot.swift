public import Foundation

/// What one application answered about its focused field, kept as JSON so a reading can be replayed without it.
public struct AccessibilitySnapshot: Codable, Sendable, Equatable {
    /// The schema this file is written in; a reader refuses any other.
    public static let currentSchema = 1

    public let schema: Int
    /// The application family the fixture stands for, such as a browser text area or a terminal.
    public let family: String
    public let windowTitle: String?
    public let document: String?
    public let focused: Element
    /// The window's bounded subtree holding an element equal to `focused`, so the surroundings walk can be replayed.
    public let window: Element?

    /// One element: its answers by attribute, and the ranged text it gives where it reads by range.
    public struct Element: Codable, Sendable, Equatable {
        public let attributes: [String: Answer]
        /// The answer to every ranged `AXStringForRange` read, or a refusal standing for all of them.
        public let rangedText: Answer?
        public let children: [Element]

        public init(attributes: [String: Answer], rangedText: Answer? = nil, children: [Element] = []) {
            self.attributes = attributes
            self.rangedText = rangedText
            self.children = children
        }
    }

    /// One answer: a text or number value, or the kind of refusal, with how long it took.
    public struct Answer: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case value, noValue, unsupported, cannotComplete, timedOut
        }

        public let kind: Kind
        public let text: String?
        public let number: Int?
        public let milliseconds: Double?

        public init(kind: Kind, text: String? = nil, number: Int? = nil, milliseconds: Double? = nil) {
            self.kind = kind
            self.text = text
            self.number = number
            self.milliseconds = milliseconds
        }

        /// The answer as the field read sees it.
        public var fieldAnswer: FieldAnswer {
            switch kind {
            case .value: text.map { .value($0) } ?? number.map { .value($0) } ?? .noValue
            case .noValue: .noValue
            case .unsupported: .unsupported
            case .cannotComplete: .cannotComplete
            case .timedOut: .timedOut
            }
        }
    }

    public enum DecodingFailure: Error, Equatable {
        case unsupportedSchema(Int)
    }

    /// Reads a fixture, refusing one written in a schema this build does not know.
    public static func decode(_ data: Data) throws -> AccessibilitySnapshot {
        let snapshot = try JSONDecoder().decode(AccessibilitySnapshot.self, from: data)
        guard snapshot.schema == currentSchema else {
            throw DecodingFailure.unsupportedSchema(snapshot.schema)
        }
        return snapshot
    }
}
