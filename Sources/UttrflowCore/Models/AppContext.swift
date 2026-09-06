/// What the user is looking at when they dictate; every field is optional, macOS grants each conditionally.
public struct AppContext: Sendable, Equatable, Codable {
    /// Localised name of the frontmost application, e.g. `"Slack"`.
    public let applicationName: String?
    /// Bundle identifier of the frontmost application, e.g. `"com.tinyspeck.slackmacgap"`.
    public let bundleIdentifier: String?
    /// Title of the focused window or document, where the app exposes it.
    public let documentName: String?
    /// Text the user had selected, where readable. Never modified by the pipeline.
    public let selectedText: String?
    /// Up to ``InsertionPoint/precedingLimit`` characters before the caret; `nil` when the field will not say.
    public let precedingText: String?
    /// Up to ``InsertionPoint/followingLimit`` characters after the selection; `nil` when the field will not say.
    public let followingText: String?

    /// A context; anything not supplied is unknown.
    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        documentName: String? = nil,
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.documentName = documentName
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
    }

    /// The context available when macOS tells us nothing.
    public static let unknown = AppContext()

    /// `true` when no field carries information, so a prompt can leave the context section out.
    public var isEmpty: Bool {
        applicationName == nil
            && bundleIdentifier == nil
            && documentName == nil
            && selectedText == nil
            && precedingText == nil
            && followingText == nil
    }
}
