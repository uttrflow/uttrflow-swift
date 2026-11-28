// The two rules for finding what a program can be asked, kept apart from the code that runs programs so they are tested.
import Foundation

/// Where programs are looked for, and how one is asked to list its verbs.
enum EnvironmentSearchRules {
    /// Where programs are looked for beyond the `PATH` this process was launched with, which an app's is not the shell's.
    static let extraSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// The directories programs are looked for in: `path` as launched, then where Homebrew and installers put them, each once, in order.
    static func searchPaths(path: String?) -> [String] {
        let launched = (path ?? "").split(separator: ":").map(String.init)
        var seen: Set<String> = []
        return (launched + extraSearchPaths).filter { seen.insert($0).inserted }
    }

    /// How a program is asked to list its verbs, which is `--help` for most and a listing command for the few that keep one.
    static func listingArguments(for program: String) -> [String] {
        switch program {
        case "cargo": ["--list"]
        case "brew": ["commands", "--quiet"]
        case "npm": ["help"]
        default: ["--help"]
        }
    }
}
