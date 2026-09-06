/// Whether Uttrflow is drawn light, dark, or as the Mac is; dark by default, as the ring's colours need it.
public enum AppAppearance: String, Sendable, Equatable, CaseIterable, Codable {
    /// Light, whatever the Mac is set to.
    case light
    /// Dark, whatever the Mac is set to. The default.
    case dark
    /// Whichever the Mac is using at the moment.
    case system

    /// What the settings row calls each one.
    public var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match my Mac"
        }
    }
}
