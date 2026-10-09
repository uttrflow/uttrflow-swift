extension ShellPrompt {
    /// Whether a marker follows a directory, host, or shell name rather than command text.
    static func isPromptMarkerPrefix(_ prefix: Substring) -> Bool {
        let words = prefix.split(whereSeparator: \.isWhitespace)
        guard let name = words.first else { return false }
        if words.count == 1, isDirectoryPrompt(prefix, allowsMarkerSpacing: true) { return true }
        if isNamedPromptWithDirectory(prefix) { return true }
        if words.count == 2 { return isHostDirectoryUserPrompt(words[0], user: words[1]) }
        guard words.count == 1 else { return false }
        if isZshHost(name) || isShellPromptName(name) { return true }
        guard let colon = name.firstIndex(of: ":") else { return false }
        return isZshHost(name[..<colon]) && isZshDirectory(name[name.index(after: colon)...])
    }

    /// Whether two words are the macOS bash default `host:directory user`.
    private static func isHostDirectoryUserPrompt(_ hostDirectory: Substring, user: Substring) -> Bool {
        guard let colon = hostDirectory.firstIndex(of: ":"), colon > hostDirectory.startIndex else {
            return false
        }
        return isBarePromptName(hostDirectory[..<colon]) && isBarePromptName(user)
            && isZshDirectory(hostDirectory[hostDirectory.index(after: colon)...])
    }

    /// Whether a path followed by Starship's branch and status segments ends at a prompt glyph.
    static func isStarshipPromptPrefix(
        _ prefix: Substring, allowsBareBranch: Bool = false
    ) -> Bool {
        let words = prefix.split(whereSeparator: \.isWhitespace)
        guard let path = words.first,
            path.hasPrefix("~") || path.hasPrefix("/") || path.hasPrefix("./")
                || path.hasPrefix("../"),
            let on = words.firstIndex(of: "on"), on == 1
        else { return false }
        var tail = Array(words.dropFirst(on + 1))
        guard let first = tail.first, first != "via", !first.hasPrefix("[") else { return false }
        // Starship themes may put a standalone private-use branch symbol before any branch name.
        if first.unicodeScalars.contains(where: { $0.value >= 0xE000 }) {
            tail.removeFirst()
        }
        guard let branch = tail.first, branch != "via", !branch.hasPrefix("[") else { return false }
        let afterBranch = Array(tail.dropFirst())
        guard let status = afterBranch.first else { return allowsBareBranch }
        if status.hasPrefix("[") {
            guard status.hasSuffix("]") else { return false }
            let following = Array(afterBranch.dropFirst())
            guard let first = following.first else { return true }
            guard first == "via" else { return false }
            return isStarshipVersionTail(Array(following.dropFirst()))
        }
        if status == "via" {
            return isStarshipVersionTail(Array(afterBranch.dropFirst()))
        }
        return status.unicodeScalars.contains { $0.value >= 0xE000 }
            && isStarshipVersionTail(Array(afterBranch.dropFirst()), allowsEmpty: true)
    }

    /// Whether every word is a Starship toolchain symbol or version such as `v20.1`.
    private static func isStarshipVersionTail(
        _ words: [Substring], allowsEmpty: Bool = false
    ) -> Bool {
        (allowsEmpty || !words.isEmpty)
            && words.allSatisfy { word in
                word.unicodeScalars.contains { $0.value >= 0xE000 }
                    || (word.first == "v" && word.dropFirst().allSatisfy { $0.isNumber || $0 == "." })
            }
    }

    /// Whether a prompt name is a shell's own label, such as `bash-5.1` or `zsh`.
    private static func isShellPromptName(_ name: Substring) -> Bool {
        name == "sh" || name.hasPrefix("sh-") || name == "bash" || name.hasPrefix("bash-")
            || name == "zsh" || name == "fish" || name.hasPrefix("fish-")
    }
}
