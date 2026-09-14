import Foundation
import UttrflowPredict

/// The substitute machine a fixture stands on: it says what the model may write, and whether what it wrote is there. See `Docs/predict-agent.md`, A5.
struct Grounding {
    /// A machine that answers what the fixture says and nothing else, as the real reader answers for a directory.
    private struct FixtureMachine: EnvironmentReading {
        let answers: [EnvironmentKind: [String]]

        func values(of kind: EnvironmentKind, in directory: String) async -> [String]? { answers[kind] }
    }

    private let verifier: Verifier
    private let surface: Surface
    private let now = Date()

    /// The grounding for a fixture with a machine, warmed so every answer is already in; nothing for a fixture without one.
    init?(for fixture: Fixture) async {
        guard let machine = fixture.machine, let directory = fixture.situation.document else { return nil }
        let index = EnvironmentIndex(reader: FixtureMachine(answers: machine))
        for kind in machine.keys { _ = await index.values(of: kind, in: directory, now: now) }
        await index.settle()
        verifier = Verifier(index: index, files: FixtureDisk(machine: machine, directory: directory))
        // A terminal's own identifier, so the whole-line path check runs as it does in the app.
        surface = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: directory)
    }

    /// What the next word may be, as the app would ask before a pass.
    func options(for typed: String) async -> ArgumentOptions {
        await verifier.options(for: typed, in: surface, now: now)
    }

    /// The model's lines the machine lets stand, as the app would sieve them before drawing.
    func standing(_ lines: [String], after typed: String) async -> [String] {
        await verifier.standing(lines, after: typed, in: surface, now: now)
    }
}

/// The disk a fixture's machine describes: its directories, files, programs and branches, and nothing else.
struct FixtureDisk: FileSystemProbing {
    let homeDirectory: String
    let searchPaths = ["/usr/bin"]
    /// What every path the machine names is.
    private let kinds: [String: PathKind]

    /// The disk under one directory, its home being the `/Users/name` the directory sits in.
    init(machine: [EnvironmentKind: [String]], directory: String) {
        let parts = directory.split(separator: "/")
        let home = parts.count >= 2 && parts[0] == "Users" ? "/Users/\(parts[1])" : directory
        homeDirectory = home
        var kinds: [String: PathKind] = [:]
        func add(_ written: String, _ kind: PathKind) {
            let path = (written as NSString).standardizingPath
            var parent = (path as NSString).deletingLastPathComponent
            while parent.count > 1, kinds[parent] == nil {
                kinds[parent] = .directory
                parent = (parent as NSString).deletingLastPathComponent
            }
            if kinds[path] != .directory { kinds[path] = kind }
        }
        func base(_ under: String) -> String {
            if under == "~" { return home }
            if under.hasPrefix("~/") { return home + under.dropFirst() }
            return under.hasPrefix("/") ? under : (directory as NSString).appendingPathComponent(under)
        }
        add(directory, .directory)
        for (kind, names) in machine {
            switch kind {
            case .directories(let under):
                for name in names { add((base(under) as NSString).appendingPathComponent(name), .directory) }
            case .entries(let under):
                let folders = Set(machine[.directories(under: under)] ?? [])
                let listsFolders = machine[.directories(under: under)] != nil
                for name in names {
                    // Where the machine does not say which names are folders, a name without an extension is one.
                    let isFolder =
                        folders.contains(name)
                        || (!listsFolders && (name as NSString).pathExtension.isEmpty && !name.hasPrefix("."))
                    let path = (base(under) as NSString).appendingPathComponent(name)
                    add(path, isFolder ? .directory : .file(executable: name.hasSuffix(".sh")))
                }
            case .executable:
                for name in names { add("/usr/bin/\(name)", .file(executable: true)) }
            case .branch:
                for name in names {
                    let ref =
                        name.hasPrefix("origin/")
                        ? "refs/remotes/\(name)"
                        : (name.first == "v" && name.dropFirst().first?.isNumber == true
                            ? "refs/tags/\(name)" : "refs/heads/\(name)")
                    add("\(directory)/.git/\(ref)", .file(executable: false))
                }
            case .alias, .subcommand, .gitAlias:
                continue
            }
        }
        self.kinds = kinds
    }

    func kind(atPath path: String) -> PathKind { kinds[path] ?? .missing }

    func contents(ofFile path: String, limit: Int) -> String? { nil }

    func names(inDirectory path: String, limit: Int) -> [String]? {
        guard kinds[path] == .directory else { return nil }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return kinds.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
            .map { String($0.dropFirst(prefix.count)) }
    }
}
