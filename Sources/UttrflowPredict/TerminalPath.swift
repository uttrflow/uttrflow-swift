/// Paths as a shell's `cd` reads them: lexically, with `.` and `..` folded before anything is asked of the disk.
enum TerminalPath {
    /// A path with its empty and `.` components dropped and each `..` taking the one before it, never above root.
    static func normalized(_ path: String) -> String {
        var kept: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": _ = kept.popLast()
            default: kept.append(component)
            }
        }
        return "/" + kept.joined(separator: "/")
    }

    /// A path taken from a directory: as given when absolute, otherwise from there.
    static func resolved(_ path: String, from directory: String) -> String {
        normalized(path.hasPrefix("/") ? path : directory + "/" + path)
    }

    /// One name under a directory.
    static func joined(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// The directory one level up, root being its own.
    static func parent(of path: String) -> String {
        normalized(path + "/..")
    }

    /// The last name of a path.
    static func lastName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
