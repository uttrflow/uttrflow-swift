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
    /// Whether the focused field hides what is typed, so none of its text is carried and nothing is kept.
    public let isSecure: Bool

    /// A context; anything not supplied is unknown.
    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        documentName: String? = nil,
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil,
        isSecure: Bool = false
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.documentName = documentName
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
        self.isSecure = isSecure
    }

    private enum CodingKeys: String, CodingKey {
        case applicationName, bundleIdentifier, documentName, selectedText, precedingText
        case followingText, isSecure
    }

    /// Reads a context written before ``isSecure`` existed as one that is not secure.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            applicationName: try container.decodeIfPresent(String.self, forKey: .applicationName),
            bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier),
            documentName: try container.decodeIfPresent(String.self, forKey: .documentName),
            selectedText: try container.decodeIfPresent(String.self, forKey: .selectedText),
            precedingText: try container.decodeIfPresent(String.self, forKey: .precedingText),
            followingText: try container.decodeIfPresent(String.self, forKey: .followingText),
            isSecure: try container.decodeIfPresent(Bool.self, forKey: .isSecure) ?? false)
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
