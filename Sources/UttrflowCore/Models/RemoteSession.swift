import Foundation

/// A terminal handed to another machine, which nothing on this disk describes. See `Docs/predict-terminal-paths.md`.
public enum RemoteSession {
    /// What a remote session is scoped by: no path and no host, so nothing here resolves a file or a listing from it.
    public static let scope = "remote-session:"

    /// The scope of a terminal whose title cannot establish which machine runs its shell.
    public static let unknownScope = "unknown-terminal-session:"

    /// The programs that hand a terminal to another machine, named as a window title names the foreground one.
    static let programs: Set<String> = ["ssh", "mosh", "mosh-client", "autossh"]

    /// Whether a window title names a program running this terminal on another machine.
    public static func isNamed(inWindowTitle title: String?) -> Bool {
        guard let title else { return false }
        let words = Self.words(of: title)
        return words.contains { programs.contains($0) }
            || Self.hasCommand("docker", "exec", in: words)
            || Self.hasCommand("kubectl", "exec", in: words)
            || Self.hasCommand("gcloud", "compute", "ssh", in: words)
            || Self.remoteHost(in: words)
    }

    /// Whether a scope prevents this Mac's disk from vouching for a terminal session.
    public static func names(_ scope: String?) -> Bool {
        scope == Self.scope || scope == Self.unknownScope
    }

    /// Whether the title proves this terminal is local or leaves its machine uncertain.
    public static func scope(inWindowTitle title: String?) -> String? {
        guard let title else { return unknownScope }
        if isNamed(inWindowTitle: title) { return scope }
        return Self.namesLocalHost(in: Self.words(of: title)) ? nil : unknownScope
    }

    /// The title's words, keeping what a path is made of together, so a directory called `~/.ssh` is not the program `ssh`.
    static func words(of title: String) -> [String] {
        title.split { !($0.isLetter || $0.isNumber || "-_./~@+".contains($0)) }.map(String.init)
    }

    private static func hasCommand(_ command: String, _ subcommand: String, in words: [String]) -> Bool {
        words.indices.contains { index in
            index + 1 < words.count && words[index] == command && words[index + 1] == subcommand
        }
    }

    private static func hasCommand(
        _ first: String, _ second: String, _ third: String, in words: [String]
    ) -> Bool {
        words.indices.contains { index in
            index + 2 < words.count && words[index] == first && words[index + 1] == second
                && words[index + 2] == third
        }
    }

    private static func remoteHost(in words: [String]) -> Bool {
        words.contains { word in
            guard let separator = word.firstIndex(of: "@") else { return false }
            let host = String(word[word.index(after: separator)...])
            guard !host.isEmpty else { return false }
            return !localHostNames.contains(normalizedHost(host))
        }
    }

    private static func namesLocalHost(in words: [String]) -> Bool {
        words.contains { word in
            guard let separator = word.firstIndex(of: "@") else { return false }
            let host = String(word[word.index(after: separator)...])
            return !host.isEmpty && localHostNames.contains(normalizedHost(host))
        }
    }

    private static var localHostNames: Set<String> {
        let names: [String?] = [Host.current().name, ProcessInfo.processInfo.hostName]
        return Set(names.compactMap { $0.map(normalizedHost) })
    }

    private static func normalizedHost(_ name: String) -> String {
        let lowercased = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return lowercased.hasSuffix(".local") ? String(lowercased.dropLast(6)) : lowercased
    }
}
