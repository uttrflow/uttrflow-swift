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

    let homeDirectory: String
    let searchPaths: [String]
    private let kinds: [String: PathKind]
    private let texts: [String: String]
    private let asked = Mutex<[Operation]>([])

    /// A disk holding these directories, files, executables and texts, under this home and search path.
    init(
        home: String = "/Users/someone", searchPaths: [String] = ["/usr/bin"], directories: [String] = [],
        files: [String] = [], executables: [String] = [], texts: [String: String] = [:],
        unknown: [String] = []
    ) {
        homeDirectory = home
        self.searchPaths = searchPaths
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
    }

    /// Every question asked so far, in order.
    var operations: [Operation] { asked.withLock { $0 } }

    func kind(atPath path: String) -> PathKind {
        asked.withLock { $0.append(.stat(path)) }
        return kinds[path] ?? .missing
    }

    func contents(ofFile path: String, limit: Int) -> String? {
        asked.withLock { $0.append(.read(path)) }
        return texts[path].flatMap { $0.utf8.count <= limit ? $0 : nil }
    }

    func names(inDirectory path: String, limit: Int) -> [String]? {
        asked.withLock { $0.append(.list(path)) }
        guard kinds[path] == .directory else { return nil }
        let prefix = path == "/" ? "/" : path + "/"
        let names = kinds.keys.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
            .map { String($0.dropFirst(prefix.count).prefix { $0 != "/" }) }
        let distinct = Array(Set(names)).sorted()
        return distinct.count <= limit ? distinct : nil
    }
}

/// A machine index reader that remembers which kinds it was asked for and answers none of them.
actor KindRecorder: EnvironmentReading {
    private(set) var asked: [EnvironmentKind] = []

    func values(of kind: EnvironmentKind, in directory: String) async -> [String]? {
        asked.append(kind)
        return nil
    }
}
