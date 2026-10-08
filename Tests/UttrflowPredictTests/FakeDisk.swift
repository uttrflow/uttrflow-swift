import Foundation
import Synchronization

@testable import UttrflowPredict

/// A disk laid out by a test that records every question put to it, which is the only way terminal verification reaches the machine.
final class FakeDisk: FileSystemProbing {
    /// One question put to the disk.
    enum Operation: Equatable {
        case stat(String)
        case read(String)
        case list(String)
    }

    let environment: FileSystemEnvironment
    private let kinds: [String: PathKind]
    private let texts: [String: String]
    private let cancelAfterVisitedNames: Int?
    private let listsInReverse: Bool
    private let asked = Mutex<[Operation]>([])
    private let visitedNames = Mutex<[String: Int]>([:])

    /// A disk holding these directories, files, executables and texts, under this home and search path.
    init(
        home: String = "/Users/someone", searchPaths: [String] = ["/usr/bin"], directories: [String] = [],
        files: [String] = [], executables: [String] = [], texts: [String: String] = [:],
        unknown: [String] = [], cancelAfterVisitedNames: Int? = nil, listsInReverse: Bool = false
    ) {
        environment = FileSystemEnvironment(homeDirectory: home, searchPaths: searchPaths)
        var kinds: [String: PathKind] = [:]
        func parents(of path: String) {
            var parent = (path as NSString).deletingLastPathComponent
            while parent.count > 1 {
                kinds[parent] = .directory
                parent = (parent as NSString).deletingLastPathComponent
            }
            kinds["/"] = .directory
        }
        for path in directories + [home] {
            parents(of: path)
            kinds[path] = .directory
        }
        for path in files + Array(texts.keys) {
            parents(of: path)
            kinds[path] = .file(executable: false)
        }
        for path in executables {
            parents(of: path)
            kinds[path] = .file(executable: true)
        }
        for path in unknown { kinds[path] = .unknown }
        self.kinds = kinds
        self.texts = texts
        self.cancelAfterVisitedNames = cancelAfterVisitedNames
        self.listsInReverse = listsInReverse
    }

    /// Every question asked so far, in order.
    var operations: [Operation] { asked.withLock { $0 } }

    func nameCountVisited(inDirectory path: String) -> Int {
        visitedNames.withLock { $0[Self.collapse(path), default: 0] }
    }

    func kind(atPath path: String) -> PathKind {
        asked.withLock { $0.append(.stat(path)) }
        return kinds[Self.collapse(path)] ?? .missing
    }

    func contents(ofFile path: String, limit: Int) -> String? {
        asked.withLock { $0.append(.read(path)) }
        return texts[path].flatMap { $0.utf8.count <= limit ? $0 : nil }
    }

    func visitNames(inDirectory path: String, _ visit: (String) -> Bool) -> Bool? {
        asked.withLock { $0.append(.list(path)) }
        let here = Self.collapse(path)
        guard kinds[here] == .directory else { return nil }
        let prefix = here == "/" ? "/" : here + "/"
        let names = Set(
            kinds.keys.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
                .map { String($0.dropFirst(prefix.count).prefix { $0 != "/" }) }
        ).sorted()
        for name in listsInReverse ? names.reversed() : names {
            guard !Task.isCancelled else { return nil }
            let count = visitedNames.withLock { count -> Int in
                count[here, default: 0] += 1
                return count[here, default: 0]
            }
            if count == cancelAfterVisitedNames { withUnsafeCurrentTask { $0?.cancel() } }
            let shouldContinue = visit(name)
            guard !Task.isCancelled else { return nil }
            guard shouldContinue else { return false }
        }
        return Task.isCancelled ? nil : true
    }

    /// Folds the empty, `.`, and `..` components the kernel would, so a fake without symlinks still answers the way the real one does.
    private static func collapse(_ path: String) -> String {
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
}

/// A machine index reader that remembers which kinds it was asked for and answers none of them.
actor KindRecorder: EnvironmentReading {
    private(set) var asked: [EnvironmentKind] = []

    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        asked.append(kind)
        return nil
    }
}
