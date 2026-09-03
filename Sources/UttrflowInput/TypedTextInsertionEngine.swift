public import UttrflowCore

/// Types text as key events, the one route into a hidden field that never borrows the clipboard.
public protocol KeystrokeTyping: Sendable {
    /// Types `text` into whatever has focus.
    func type(_ text: String) throws(TextInsertionError)
}

/// Puts text in by typing it, for the fields Accessibility cannot write into.
public struct TypedTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .typed

    private let focus: any AccessibilityFocus
    private let typist: any KeystrokeTyping

    public init(focus: any AccessibilityFocus, typist: any KeystrokeTyping) {
        self.focus = focus
        self.typist = typist
    }

    /// Anything but ourselves; Electron apps expose no focused element and still take typing.
    public func canInsert() async -> Bool { !focus.isSelfFrontmost() }

    public func insert(_ text: String) async throws(TextInsertionError) {
        try typist.type(text)
    }
}
