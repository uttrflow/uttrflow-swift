/// Whether Uttrflow is drawn light, dark, or however the Mac is set.
///
/// A preference rather than following the system unconditionally, and **dark by
/// default**, which is the one choice here worth arguing about.
///
/// Following the system is the conventional answer and it is the wrong one for this
/// product: the app that was designed should be the app that is seen. Uttrflow's own
/// artboards are dark — the ring's teal and purple are two saturated colours that only
/// hold their meaning against something dark, and on a white panel `#00C3D0` is a pale
/// smudge. The light variant exists and is drawn from the same tokens, but it is the
/// alternative rather than the default.
///
/// ``system`` is kept because taking the choice away is worse than defaulting it: a user
/// who wants their whole Mac to change together should be able to have that.
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
