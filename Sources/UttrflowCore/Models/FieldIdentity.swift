// Tells one focused text field apart from every other, so a write can refuse a field that is not the one read.

/// One focused element, told apart from every other by its owner, its window and the element itself.
public struct FieldIdentity: Sendable, Hashable, Codable {
    public let processIdentifier: Int32
    public let windowNumber: UInt32?
    /// The element's own hash, which differs between two fields of one window.
    public let element: Int

    public init(processIdentifier: Int32, windowNumber: UInt32?, element: Int) {
        self.processIdentifier = processIdentifier
        self.windowNumber = windowNumber
        self.element = element
    }

    /// Whether `other` is this field, comparing windows only where both reads could name one.
    public func isSameField(as other: FieldIdentity) -> Bool {
        guard processIdentifier == other.processIdentifier, element == other.element else { return false }
        guard let windowNumber, let otherWindow = other.windowNumber else { return true }
        return windowNumber == otherWindow
    }
}
