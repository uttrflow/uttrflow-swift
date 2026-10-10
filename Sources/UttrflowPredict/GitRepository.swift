private import Synchronization

/// A git repository read straight off disk — `.git`, `refs` and `packed-refs` — so a branch is checked without running git.
struct GitRepository: Sendable {
    /// The directory that holds the refs, shared by every worktree of the repository.
    let commonDirectory: String
    /// The disk it is read from.
    let files: any FileSystemProbing
    /// The packed refs parsed lazily once for this repository lookup.
    private let packedRefsCache: PackedRefsCache

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
                return repository(gitDirectory: dotGit, worktreeRoot: current, files: files)
            case .file:
                guard let pointer = files.contents(ofFile: dotGit, limit: 4_096),
                    let named = Self.value(of: "gitdir:", in: pointer)
                else { return nil }
                return repository(
                    gitDirectory: TerminalPath.resolved(named, from: current), worktreeRoot: current,
                    files: files)
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
    private static func repository(
        gitDirectory: String, worktreeRoot: String, files: any FileSystemProbing
    ) -> GitRepository? {
        let commonPath = TerminalPath.joined(gitDirectory, "commondir")
        let common: String
        switch files.kind(atPath: commonPath) {
        case .missing:
            common = gitDirectory
        case .file:
            guard let text = files.contents(ofFile: commonPath, limit: 4_096) else { return nil }
            common = TerminalPath.resolved(
                text.trimmingCharacters(in: .whitespacesAndNewlines), from: gitDirectory)
        case .directory, .unknown:
            return nil
        }
        guard
            validMetadata(
                gitDirectory: gitDirectory, commonDirectory: common, worktreeRoot: worktreeRoot, files: files)
        else { return nil }
        guard files.kind(atPath: TerminalPath.joined(common, "reftable")) == .missing else { return nil }
        return GitRepository(
            commonDirectory: common,
            files: files,
            packedRefsCache: PackedRefsCache(path: TerminalPath.joined(common, "packed-refs"), files: files))
    }

    /// Keeps metadata inside this worktree or proves a linked worktree belongs to its common Git directory.
    private static func validMetadata(
        gitDirectory: String, commonDirectory: String, worktreeRoot: String,
        files: any FileSystemProbing
    ) -> Bool {
        if gitDirectory == TerminalPath.joined(worktreeRoot, ".git"), commonDirectory == gitDirectory {
            return true
        }
        guard TerminalPath.lastName(of: commonDirectory) == ".git" else { return false }
        let worktrees = TerminalPath.joined(commonDirectory, "worktrees") + "/"
        guard gitDirectory.hasPrefix(worktrees), !gitDirectory.dropFirst(worktrees.count).contains("/") else {
            return false
        }
        guard let backlink = files.contents(ofFile: TerminalPath.joined(gitDirectory, "gitdir"), limit: 4_096)
        else { return false }
        return TerminalPath.resolved(
            backlink.trimmingCharacters(in: .whitespacesAndNewlines), from: gitDirectory)
            == TerminalPath.joined(worktreeRoot, ".git")
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
    private var packedRefs: Set<String>? { packedRefsCache.value }

    /// A per-lookup memo that is discarded when the next repository verification starts.
    private final class PackedRefsCache: Sendable {
        private enum State: Sendable {
            case unread
            case read(Set<String>?)
        }

        private let path: String
        private let files: any FileSystemProbing
        private let state = Mutex<State>(.unread)

        init(path: String, files: any FileSystemProbing) {
            self.path = path
            self.files = files
        }

        var value: Set<String>? {
            state.withLock { state in
                if case .read(let refs) = state { return refs }
                let refs = Self.read(path: path, files: files)
                state = .read(refs)
                return refs
            }
        }

        private static func read(path: String, files: any FileSystemProbing) -> Set<String>? {
            guard files.kind(atPath: path) != .missing else { return [] }
            guard let text = files.contents(ofFile: path, limit: GitRepository.packedRefsLimit) else {
                return nil
            }
            return Set(
                text.split(whereSeparator: \.isNewline).compactMap { line in
                    guard !line.hasPrefix("#"), !line.hasPrefix("^"), let space = line.firstIndex(of: " ")
                    else {
                        return nil
                    }
                    return String(line[line.index(after: space)...])
                })
        }
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

    /// Whether exactly one remote has a branch of this name, which is when `checkout` and `switch` turn it into a local one.
    func hasRemoteBranch(named name: String) -> Bool {
        remotes(holdingBranch: name)?.count == 1
    }

    /// The remotes with a branch of this name, loose or packed, each counted once; absent when `packed-refs` cannot be read whole.
    func remotes(holdingBranch name: String) -> Set<String>? {
        guard Self.isRefName(name) else { return [] }
        guard let packed = packedRefs else { return nil }
        var holding: Set<String> = []
        let remotes = TerminalPath.joined(commonDirectory, "refs/remotes")
        for remote in files.names(inDirectory: remotes, limit: Self.remoteLimit) ?? [] {
            let ref = TerminalPath.joined(commonDirectory, "refs/remotes/\(remote)/\(name)")
            if case .file = files.kind(atPath: ref) { holding.insert(remote) }
        }
        for ref in packed where ref.hasPrefix("refs/remotes/") {
            let rest = ref.dropFirst("refs/remotes/".count)
            guard let slash = rest.firstIndex(of: "/"), rest[rest.index(after: slash)...] == name else {
                continue
            }
            holding.insert(String(rest[..<slash]))
        }
        return holding
    }

    /// Whether a name is a commit ref or `HEAD`, with optional parent and ancestor selectors.
    func hasCommit(named name: String) -> Bool {
        if name.hasPrefix("@{-"), Self.validCommitSelectors(name) { return true }
        if name.hasPrefix(":/"), name.count > 2 { return true }
        let base = String(name.prefix { $0 != "~" && $0 != "^" && !($0 == "@" && name.contains("@{")) })
        guard Self.validCommitSelectors(String(name.dropFirst(base.count))) else { return false }
        if base == "HEAD" || base == "@" { return true }
        guard Self.isRefName(base) else { return false }
        if ["refs/heads/", "refs/tags/", "refs/remotes/", "refs/"].contains(where: { has($0 + base) }) {
            return true
        }
        return false
    }

    /// Whether revision operators have Git's numeric and braced selector shapes.
    private static func validCommitSelectors(_ suffix: String) -> Bool {
        var rest = suffix[...]
        while !rest.isEmpty {
            if rest.first == "~" {
                rest = rest.dropFirst()
                rest = rest.dropFirst(rest.prefix(while: \.isNumber).count)
            } else if rest.first == "^" {
                rest = rest.dropFirst()
                if rest.first == "{" {
                    guard let close = rest.firstIndex(of: "}") else { return false }
                    let type = rest[rest.index(after: rest.startIndex)..<close]
                    guard type.isEmpty || ["commit", "tree", "blob", "tag"].contains(String(type)) else {
                        return false
                    }
                    rest = rest[rest.index(after: close)...]
                } else {
                    rest = rest.dropFirst(rest.prefix(while: \.isNumber).count)
                }
            } else if rest.hasPrefix("@{") {
                rest = rest.dropFirst(2)
                guard let close = rest.firstIndex(of: "}"), close != rest.startIndex else { return false }
                let selector = rest[..<close]
                guard selector.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
                rest = rest[rest.index(after: close)...]
            } else if rest.hasPrefix(":/") {
                return rest.dropFirst(2).isEmpty == false
            } else {
                return false
            }
        }
        return true
    }
}
