/// Why a context read ends without the field's text, so an unread field is never taken for an empty one.
public enum ContextUnavailableReason: String, Sendable, CaseIterable {
    /// Uttrflow has no Accessibility grant, so no application answers.
    case notTrusted
    /// The application names no focused element to read.
    case noFocusedElement
    /// The application or the field would not give what was asked.
    case refused
    /// The read ran out of time before the field gave its text.
    case timedOut
    /// The field hides what is typed, so none of its text is read.
    case secure
    /// The focused element publishes no text at all, as a remote screen, a virtual machine or a drawn canvas does.
    case notTextSurface
}
