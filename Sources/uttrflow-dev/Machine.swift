import ArgumentParser
import Foundation
import UttrflowPredict

/// Shows what tab-to-complete reads off this Mac for one directory, which is what a `notOnThisMachine` silence was judged against.
struct Machine: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report what tab-to-complete reads off this Mac for a directory."
    )

    @Option(name: .shortAndLong, help: "The directory a terminal would be sitting in.")
    var directory = FileManager.default.currentDirectoryPath

    @Option(
        name: .long, parsing: .upToNextOption, help: "Programs whose verbs to list, e.g. git make docker.")
    var programs: [String] = ["git", "make", "npm run", "docker", "kubectl", "gh", "brew", "cargo", "npm"]

    @Option(name: .long, help: "A path from the directory whose entries to list, e.g. Sources or ../other.")
    var under: String = "."

    func run() async throws {
        let reader = SystemEnvironmentReader()
        var kinds: [(String, EnvironmentKind)] = [
            ("branches", .branch), ("entries under \(under)", .entries(under: under)),
            ("directories under \(under)", .directories(under: under)), ("aliases", .alias),
            ("git aliases", .gitAlias),
        ]
        kinds += programs.map { ("\($0) verbs", .subcommand(of: $0)) }
        for (label, kind) in kinds {
            let started = ContinuousClock.now
            let values = await reader.values(of: kind, in: directory)
            let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
            let shown = values.map {
                "\($0.count): \($0.prefix(12).joined(separator: " "))\($0.count > 12 ? " …" : "")"
            }
            print("  \(label.padded(to: 28)) \(String(elapsed).leftPadded(to: 5))ms  \(shown ?? "no answer")")
        }
        let started = ContinuousClock.now
        let programsOnPath = await reader.values(of: .executable, in: directory)
        let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
        print(
            "  \("programs".padded(to: 28)) \(String(elapsed).leftPadded(to: 5))ms  \(programsOnPath?.count ?? 0)"
        )
    }
}

extension String {
    /// The string with spaces after it until it is this wide, so a column of labels lines up.
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    /// The string with spaces in front until it is this wide, so a column of numbers lines up.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
