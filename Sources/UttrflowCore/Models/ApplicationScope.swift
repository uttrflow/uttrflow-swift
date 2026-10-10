// The applications a snippet or a word is confined to, as the person chose them. See `Docs/ai-snippet-store.md`.
import Foundation

/// Which applications a record applies in: none listed means every application, as before scopes existed.
public enum ApplicationScope {
    /// Whether a record confined to `applications` applies where `bundleIdentifier` is in front; an unknown front admits only unconfined ones.
    public static func admits(_ applications: [String], in bundleIdentifier: String?) -> Bool {
        guard !applications.isEmpty else { return true }
        guard let bundleIdentifier else { return false }
        return applications.contains { ApplicationKey.same($0, as: bundleIdentifier) }
    }

    /// The list as a record keeps it: trimmed, blanks dropped and one identifier per application, in the order chosen.
    public static func normalised(_ applications: [String]) -> [String] {
        var seen: Set<String> = []
        return applications.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && seen.insert(ApplicationKey.of($0)).inserted
        }
    }
}
