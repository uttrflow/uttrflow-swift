import Foundation

/// Reads the targets a Makefile declares, which is what `make` takes.
enum MakefileTargets {
    /// Every target the text declares, in order, without the special ones, pattern rules or variables.
    static func names(in makefile: String) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for line in makefile.split(separator: "\n") {
            // A rule's head stands at the margin and ends at its colon; an indented line is a recipe, `:=` a variable.
            guard let first = line.first, !first.isWhitespace, first != "#",
                let colon = line.firstIndex(of: ":"),
                !line[colon...].hasPrefix(":="), !line[colon...].hasPrefix("::=")
            else { continue }
            let head = line[..<colon]
            guard !head.contains("="), !head.contains("$") else { continue }
            for target in head.split(separator: " ")
            where !target.hasPrefix(".") && !target.contains("%") && seen.insert(String(target)).inserted {
                names.append(String(target))
            }
        }
        return names
    }
}

/// Reads the scripts a `package.json` declares, which is what `npm run` and its kin take.
enum PackageScripts {
    /// Every script name the manifest declares, sorted; absent when the manifest is not JSON.
    static func names(in manifest: String) -> [String]? {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(manifest.utf8)),
            let object = parsed as? [String: Any]
        else { return nil }
        let scripts = object["scripts"] as? [String: Any] ?? [:]
        return scripts.keys.sorted()
    }
}

/// Reads the verbs a program lists in its own help, which is how docker, kubectl and gh advertise them.
enum HelpCommands {
    /// Every command name the help text lists: an indented name set off from its description or alone, a bare name on its own line, or the names of an indented comma-separated list.
    static func names(in help: String) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for raw in help.split(separator: "\n") {
            let line = raw.drop { $0 == " " || $0 == "\t" }
            let indented = raw.count - line.count
            for name in listed(in: line, indented: indented) where seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    /// The names one line lists, none for a heading, a sentence or an option.
    private static func listed(in line: Substring, indented: Int) -> [String] {
        // A list of names on one line, as npm's `All commands:` gives them, is every name on it, the line's own trailing comma dropped.
        let commaSeparated = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if indented >= 2, commaSeparated.count >= 2, commaSeparated.allSatisfy({ isName(Substring($0)) }) {
            return commaSeparated
        }
        guard let first = line.split(separator: " ").first else { return [] }
        // gh writes each name with a colon after it, which is the layout's and not the name's.
        let name = first.hasSuffix(":") ? first.dropLast() : first
        guard isName(name) else { return [] }
        let described = line.dropFirst(first.count)
        // A listed command is indented, alone or set off from its description by two spaces or more; a bare name at the margin lists itself.
        let listed =
            indented >= 2 && (described.isEmpty || described.hasPrefix("  ") || described.hasPrefix("\t"))
        let bare = indented == 0 && described.isEmpty
        return listed || bare ? [String(name)] : []
    }

    /// What a command name looks like: lowercase, starting with a letter, with the dashes some programs use.
    private static func isName(_ text: Substring) -> Bool {
        guard let first = text.first, first.isLowercase, first.isLetter else { return false }
        return text.allSatisfy { ($0.isLowercase && $0.isLetter) || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
