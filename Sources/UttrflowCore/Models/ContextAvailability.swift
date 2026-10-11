/// Whether the screen around the field was read, so a layer can tell an empty field from a screen nobody looked at.
package enum ContextAvailability: Sendable, Equatable {
    /// The read ran, so empty text means the field really is empty.
    case present
    /// The read was never asked for, as for a retry of a kept recording.
    case absentByDesign
    /// The read was asked for and ended without the field's text.
    case unreadable
    /// The field hides what is typed, so none of its text is read.
    case secure

    /// Whether empty field text is evidence that the field is empty.
    package var emptyTextIsEvidence: Bool { self == .present }
}
