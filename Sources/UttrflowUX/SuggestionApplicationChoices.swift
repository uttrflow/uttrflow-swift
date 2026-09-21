public import UttrflowPredict

/// Which running applications the "Add Application…" menu offers to turn suggestions off in.
public enum SuggestionApplicationChoices {
    /// Those not already off, never Uttrflow itself, each once, sorted by name.
    public static func offered(
        _ running: [SuggestionApplication], preferences: SuggestionPreferences, excluding own: String?
    ) -> [SuggestionApplication] {
        let own = own?.lowercased()
        var seen = Set<String>()
        return
            running
            .filter { $0.bundleIdentifier != own && preferences.state(of: $0.bundleIdentifier).isOn }
            .filter { seen.insert($0.bundleIdentifier).inserted }
            .sorted {
                ($0.name.lowercased(), $0.bundleIdentifier) < ($1.name.lowercased(), $1.bundleIdentifier)
            }
    }
}
