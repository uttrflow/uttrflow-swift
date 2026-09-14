/// A git repository read straight off disk — `.git`, `refs` and `packed-refs` — so a branch is checked without running git.
struct GitRepository: Sendable {
    /// The directory that holds the refs, shared by every worktree of the repository.
    let commonDirectory: String
    /// The disk it is read from.
    let files: any FileSystemProbing

    /// How far up from the working directory `.git` is looked for.
    static let deepestSearch = 64

    /// The largest `packed-refs` read, past which a ref is not believed rather than the file read at length.
    static let packedRefsLimit = 8 << 20

    /// How many remotes are looked through for a branch of the same name.
    static let remoteLimit = 32

    /// The repository holding a directory, absent outside one or where its refs cannot be read as files.
    static func holding(_ directory: String, files: any FileSystemProbing) -> GitRepository? {
        var current = directory
        for _ in 0..<deepestSearch {
            let dotGit = TerminalPath.joined(current, ".git")
            switch files.kind(atPath: dotGit) {
            case .directory:
                return repository(gitDirectory: dotGit, files: files)
            case .file:
                guard let pointer = files.contents(ofFile: dotGit, limit: 4_096),
                    let named = Self.value(of: "gitdir:", in: pointer)
                else { return nil }
                return repository(gitDirectory: TerminalPath.resolved(named, from: current), files: files)
            case .unknown:
                return nil
            case .missing:
                guard current != "/" else { return nil }
                current = TerminalPath.parent(of: current)
            }
        }
        return nil
    }

    /// The repository whose git directory this is, following a worktree's `commondir`; absent for refs kept in a reftable.
    private static func repository(gitDirectory: String, files: any FileSystemProbing) -> GitRepository? {
        let common =
            files.contents(ofFile: TerminalPath.joined(gitDirectory, "commondir"), limit: 4_096)
            .map {
                TerminalPath.resolved($0.trimmingCharacters(in: .whitespacesAndNewlines), from: gitDirectory)
            }
            ?? gitDirectory
        guard files.kind(atPath: TerminalPath.joined(common, "reftable")) == .missing else { return nil }
        return GitRepository(commonDirectory: common, files: files)
    }

    /// The text after a `key:` line's key, trimmed.
    private static func value(of key: String, in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first { $0.hasPrefix(key) }
            .map { $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Whether a name could be a ref at all, so no name can climb out of the refs directory.
    static func isRefName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasSuffix("/"), !name.hasSuffix(".lock"),
            !name.contains(".."), !name.contains("//"), !name.contains("@{")
        else { return false }
        return !name.contains {
            $0.isWhitespace || "~^:?*[\\".contains($0) || $0.asciiValue.map { $0 < 32 } == true
        }
    }

    /// Whether a full ref such as `refs/heads/main` exists, loose or packed; false when `packed-refs` is too large to trust.
    func has(_ ref: String) -> Bool {
        if case .file = files.kind(atPath: TerminalPath.joined(commonDirectory, ref)) { return true }
        return packedRefs?.contains(ref) ?? false
    }

    /// Every ref `packed-refs` names, absent when it cannot be read whole.
    private var packedRefs: Set<String>? {
        let path = TerminalPath.joined(commonDirectory, "packed-refs")
        guard files.kind(atPath: path) != .missing else { return [] }
        guard let text = files.contents(ofFile: path, limit: Self.packedRefsLimit) else { return nil }
        return Set(
            text.split(whereSeparator: \.isNewline).compactMap { line in
                guard !line.hasPrefix("#"), !line.hasPrefix("^"), let space = line.firstIndex(of: " ") else {
                    return nil
                }
                return String(line[line.index(after: space)...])
            })
    }

    /// The namespaces a ref's short name is read from, as `git for-each-ref` shortens them.
    static let namespaces = ["refs/heads/", "refs/tags/", "refs/remotes/"]

    /// How deep a ref's name may nest in folders before the walk stops.
    static let deepestRef = 8

    /// The short name of every branch, tag and remote branch, loose or packed, sorted, at most `limit` of them; a remote's `HEAD` is left out.
    func refNames(limit: Int) -> [String] {
        var found: Set<String> = []
        for namespace in Self.namespaces {
            collect(under: namespace, trimming: namespace, depth: 0, limit: limit, into: &found)
        }
        for ref in packedRefs ?? [] {
            guard let namespace = Self.namespaces.first(where: ref.hasPrefix) else { continue }
            found.insert(String(ref.dropFirst(namespace.count)))
        }
        return Array(found.filter { $0 != "HEAD" && !$0.hasSuffix("/HEAD") }.sorted().prefix(limit))
    }

    /// Every loose ref under one folder of the refs, by its name past the namespace.
    private func collect(
        under folder: String, trimming namespace: String, depth: Int, limit: Int,
        into found: inout Set<String>
    ) {
        guard depth < Self.deepestRef, found.count < limit,
            let names = files.names(
                inDirectory: TerminalPath.joined(commonDirectory, String(folder.dropLast())), limit: limit)
        else { return }
        for name in names.sorted() where found.count < limit {
            let ref = folder + name
            switch files.kind(atPath: TerminalPath.joined(commonDirectory, ref)) {
            case .directory:
                collect(under: ref + "/", trimming: namespace, depth: depth + 1, limit: limit, into: &found)
            case .file:
                found.insert(String(ref.dropFirst(namespace.count)))
            case .missing, .unknown:
                continue
            }
        }
    }

    /// Whether a local branch of this name exists.
    func hasBranch(_ name: String) -> Bool {
        Self.isRefName(name) && has("refs/heads/\(name)")
    }

    /// Whether any remote has a branch of this name, which `checkout` and `switch` turn into a local one.
    func hasRemoteBranch(named name: String) -> Bool {
        guard Self.isRefName(name) else { return false }
        let remotes = TerminalPath.joined(commonDirectory, "refs/remotes")
        for remote in files.names(inDirectory: remotes, limit: Self.remoteLimit) ?? []
        where has("refs/remotes/\(remote)/\(name)") {
            return true
        }
        return packedRefs?.contains { ref in
            guard ref.hasPrefix("refs/remotes/") else { return false }
            return ref.dropFirst("refs/remotes/".count).drop { $0 != "/" }.dropFirst() == name
        } ?? false
    }

    /// Whether a name is anything `checkout` could take as a commit: `HEAD` and its relatives, a branch, a tag or a remote's branch.
    func hasCommit(named name: String) -> Bool {
        let base = String(name.prefix { $0 != "~" && $0 != "^" })
        guard
            base.count == name.count
                || name.dropFirst(base.count).allSatisfy({ "~^".contains($0) || $0.isNumber })
        else { return false }
        if base == "HEAD" || base == "@" { return true }
        guard Self.isRefName(base) else { return false }
        return ["refs/heads/", "refs/tags/", "refs/remotes/", "refs/"].contains { has($0 + base) }
    }
}
