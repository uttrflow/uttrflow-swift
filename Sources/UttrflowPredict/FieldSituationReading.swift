/// Reads a situation out of the strings an application publishes about itself, guessing at nothing.
public enum FieldSituationReading {
    /// What separates one fact from another in a window title.
    static let separators: Set<Character> = ["—", "–", "|", "·", "•", "→", "»", "▸", "›"]

    /// Decoration a shell prompt or an editor puts around a title, which carries no fact.
    static let decoration: Set<Character> = [
        "*", "●", "◦", "✗", "✓", "➜", "❯", "➤", "…", "\"", "'", "•", "·", "-",
    ]

    /// Branch names common enough that seeing one alone is not a guess.
    static let trunkNames: Set<String> = ["main", "master", "develop", "trunk"]

    /// What a branch name starts with when it is not a trunk, which is how a bare one is recognised.
    static let branchPrefixes: Set<String> = [
        "feat", "feature", "fix", "bugfix", "hotfix", "chore", "release", "refactor", "docs", "doc",
        "test", "tests", "ci", "perf", "build", "style", "revert", "wip", "spike", "exp", "epic",
        "task", "story", "dependabot", "renovate",
    ]

    /// Words that look like a database name but are the tool doing the printing.
    static let noiseWords: Set<String> = [
        "zsh", "bash", "fish", "sh", "nu", "ssh", "vim", "nvim", "tmux", "git", "node", "python",
        "python3", "ruby", "less", "man", "top", "htop", "make", "docker", "screen", "code",
    ]

    /// The file extensions a title may end on, listed so an address is never mistaken for a file.
    static let sourceExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "ts", "tsx", "jsx", "go", "rs", "rb", "java", "kt", "kts", "c",
        "h", "cc", "cpp", "hpp", "m", "mm", "cs", "php", "pl", "lua", "r", "scala", "ex", "exs",
        "sh", "zsh", "bash", "sql", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss",
        "md", "txt", "csv", "plist", "lock", "cfg", "ini", "conf", "env", "gradle", "tf", "tfvars",
        "proto", "graphql", "ipynb",
    ]

    /// The situation a window describes, absent when nothing in it is recognisable.
    public static func read(
        windowTitle: String? = nil, tabTitle: String? = nil, workingDirectory: String? = nil
    ) -> FieldSituation? {
        let project = projectName(of: workingDirectory)
        let fromTab = tabTitle.map { situation(in: $0, project: project) } ?? .unknown
        let fromWindow = windowTitle.map { situation(in: $0, project: project) } ?? .unknown
        let merged = fromTab.completed(by: fromWindow)
        return merged.isEmpty ? nil : merged
    }

    /// Everything one title says, with the project's own name discounted so it is not read as a branch.
    static func situation(in title: String, project: String?) -> FieldSituation {
        let parts = segments(of: title).map { project == $0.lowercased() ? "" : $0 }
        var branch: String?
        var environment: DeploymentEnvironment?
        var connection: String?
        var file: String?
        var deployments: [Int] = []

        for (index, segment) in parts.enumerated() {
            if branch == nil, let found = markedBranch(in: segment) ?? bareBranch(in: segment) {
                branch = found
                continue
            }
            if let pair = environmentPair(in: segment) {
                environment = environment ?? pair.0
                connection = connection ?? pair.1
                continue
            }
            if let word = DeploymentEnvironment(word: segment) {
                environment = environment ?? word
                deployments.append(index)
                continue
            }
            if file == nil, let named = fileName(in: segment) { file = named }
        }

        return FieldSituation(
            branch: branch,
            connection: connection ?? neighbouringIdentifier(of: deployments, in: parts),
            environment: environment,
            file: file)
    }

    /// The database named beside a deployment, which is how "qa · orders_db" says which one it is.
    static func neighbouringIdentifier(of deployments: [Int], in parts: [String]) -> String? {
        for index in deployments {
            for neighbour in [index + 1, index - 1] where parts.indices.contains(neighbour) {
                if let identifier = databaseIdentifier(in: parts[neighbour]) { return identifier }
            }
        }
        return nil
    }

    /// The directory's own name, which is the project's, so a title repeating it says nothing new.
    static func projectName(of workingDirectory: String?) -> String? {
        guard let workingDirectory else { return nil }
        let components = workingDirectory.split(separator: "/")
        guard let last = components.last else { return nil }
        return String(last).lowercased()
    }

    /// A title cut into the facts it lists, on the punctuation applications use to list them.
    static func segments(of title: String) -> [String] {
        let characters = Array(title)
        var pieces: [String] = []
        var current: [Character] = []
        for (index, character) in characters.enumerated() {
            if separators.contains(character) || isSpacedBreak(at: index, in: characters) {
                pieces.append(String(current))
                current = []
                continue
            }
            current.append(character)
        }
        pieces.append(String(current))
        return pieces.map(stripped(_:)).filter { !$0.isEmpty }
    }

    /// Whether a hyphen or colon is being used as punctuation here rather than as part of a name.
    static func isSpacedBreak(at index: Int, in characters: [Character]) -> Bool {
        let following = index + 1 < characters.count ? characters[index + 1] : " "
        guard following == " " else { return false }
        if characters[index] == ":" { return true }
        guard characters[index] == "-" else { return false }
        return index > 0 && characters[index - 1] == " "
    }

    /// One fact without the decoration around it.
    static func stripped(_ segment: String) -> String {
        var characters = Array(Whitespace.trimmed(segment))
        while let first = characters.first, decoration.contains(first) || first.isWhitespace {
            characters.removeFirst()
        }
        while let last = characters.last, decoration.contains(last) || last.isWhitespace {
            characters.removeLast()
        }
        return String(characters)
    }

    /// A branch a prompt has labelled as one, which may be named anything at all.
    static func markedBranch(in segment: String) -> String? {
        if let inside = enclosed(in: segment, after: "git:(", before: ")") { return inside }
        let characters = Array(segment)
        guard let marker = characters.firstIndex(of: "⎇") else { return nil }
        let token = characters[(marker + 1)...].drop(while: \.isWhitespace).prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }

    /// A branch nothing labelled, recognised only when its own name says what it is.
    static func bareBranch(in segment: String) -> String? {
        if isBranchShaped(segment) { return segment }
        for (opener, closer) in [("(", Character(")")), ("[", Character("]"))] {
            if let inside = enclosed(in: segment, after: opener, before: closer), isBranchShaped(inside) {
                return inside
            }
        }
        return nil
    }

    /// Whether a name is one only a branch would have, which trunks and prefixed names are.
    static func isBranchShaped(_ token: String) -> Bool {
        guard isReferenceShaped(token) else { return false }
        let folded = token.lowercased()
        if trunkNames.contains(folded) { return true }
        guard let slash = folded.firstIndex(of: "/") else { return false }
        return branchPrefixes.contains(String(folded[..<slash]))
    }

    /// Whether a name could be a git reference at all, which a path and a sentence could not.
    static func isReferenceShaped(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 80, let first = token.first, first.isLetter || first.isNumber
        else { return false }
        return token.allSatisfy { $0.isLetter || $0.isNumber || "._-/+".contains($0) }
    }

    /// The deployment and database an `env@name` pair names, absent unless one side is a deployment.
    static func environmentPair(in segment: String) -> (DeploymentEnvironment, String?)? {
        let sides = segment.split(separator: "@", omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        let left = String(sides[0])
        let right = String(sides[1])
        if let deployment = DeploymentEnvironment(word: left) {
            return (deployment, databaseIdentifier(in: right))
        }
        if let deployment = DeploymentEnvironment(word: right) {
            return (deployment, databaseIdentifier(in: left))
        }
        return nil
    }

    /// A name shaped like a database or schema, which excludes anything capitalised like an application.
    static func databaseIdentifier(in segment: String) -> String? {
        guard segment.count >= 2, segment.count <= 64 else { return nil }
        guard !noiseWords.contains(segment.lowercased()) else { return nil }
        guard DeploymentEnvironment(word: segment) == nil, let first = segment.first, first.isLetter
        else { return nil }
        let allowed = segment.allSatisfy {
            ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "."
        }
        return allowed ? segment : nil
    }

    /// The file a title names, recognised by an extension rather than by having a dot in it.
    static func fileName(in segment: String) -> String? {
        guard !segment.contains("/"), !segment.contains(" "), let dot = segment.lastIndex(of: ".") else {
            return nil
        }
        guard dot != segment.startIndex else { return nil }
        let suffix = String(segment[segment.index(after: dot)...]).lowercased()
        return sourceExtensions.contains(suffix) ? segment : nil
    }

    /// What sits between an opening marker and the next closing character, absent when either is missing.
    static func enclosed(in segment: String, after opener: String, before closer: Character) -> String? {
        let characters = Array(segment)
        let marker = Array(opener)
        guard let start = firstIndex(of: marker, in: characters) else { return nil }
        let content = characters[(start + marker.count)...]
        guard let end = content.firstIndex(of: closer) else { return nil }
        let inside = String(content[content.startIndex..<end])
        return inside.isEmpty ? nil : inside
    }

    /// Where one run of characters first occurs in another.
    static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }
}
