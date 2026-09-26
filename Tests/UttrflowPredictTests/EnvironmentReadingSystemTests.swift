// Tests for issue #767: a directory listing is bounded in work, not only in what it returns.

import Foundation
import Testing

@testable import UttrflowPredict

/// A launcher that is never asked to run anything here.
private struct UnusedLauncher: ProgramLaunching {
    func output(of launch: ProgramLaunch) async -> String? { nil }
}

@Suite("Listing one directory off this Mac")
struct EnvironmentReadingSystemTests {
    /// A thousand subdirectories, only one of which begins `sub_9`, alongside `sub_9`'s own hundred and ten look-alikes.
    private static let manySubdirectories = (0..<1_000).map { "/repo/sub_\($0)" }

    @Test(
        "A name whose alphabetical place is past the 200-name cap is still offered, once the typed prefix rules out everything else."
    )
    func namePastTheCapStillOffered() async throws {
        let disk = FakeDisk(directories: Self.manySubdirectories)
        let reader = SystemEnvironmentReader(
            launcher: UnusedLauncher(), programDirectories: [], files: disk)

        // Alphabetically, "sub_9" sits among the "9xx" names near the end of a thousand — nowhere near the first 200.
        let unfiltered = await reader.values(of: .directories(under: "."), in: "/repo")
        #expect(!(unfiltered?.contains("sub_9") ?? false))

        let narrowed = await reader.values(
            of: .directories(under: "."), in: "/repo", matching: "sub_9")
        #expect(narrowed?.contains("sub_9") == true)
    }

    @Test("Matching a typed prefix ignores case, the same rule `EnvironmentSource` offers candidates by.")
    func matchingIgnoresCase() async throws {
        let disk = FakeDisk(directories: ["/repo/Sources", "/repo/scripts"])
        let reader = SystemEnvironmentReader(
            launcher: UnusedLauncher(), programDirectories: [], files: disk)

        let named = await reader.values(of: .directories(under: "."), in: "/repo", matching: "SOU")
        #expect(named == ["Sources"])
    }

    @Test(
        "Only the names that survive the prefix filter are ever stat'ed, not every entry in a large directory."
    )
    func onlySurvivorsAreStatted() async throws {
        let disk = FakeDisk(directories: Self.manySubdirectories)
        let reader = SystemEnvironmentReader(
            launcher: UnusedLauncher(), programDirectories: [], files: disk)

        _ = await reader.values(of: .directories(under: "."), in: "/repo", matching: "sub_9")

        // "sub_9" itself, "sub_90"…"sub_99", and "sub_900"…"sub_999": 1 + 10 + 100 names begin with it.
        let expectedSurvivors = 111
        let statted = disk.operations.filter {
            if case .stat(let path) = $0, path != "/repo" { return true }
            return false
        }
        #expect(statted.count == expectedSurvivors)
    }

    @Test("A directory read without a typed prefix still lists and caps everything, exactly as before.")
    func emptyPrefixKeepsEverything() async throws {
        let disk = FakeDisk(directories: Self.manySubdirectories)
        let reader = SystemEnvironmentReader(
            launcher: UnusedLauncher(), programDirectories: [], files: disk)

        let all = await reader.values(of: .directories(under: "."), in: "/repo", matching: "")
        #expect(all?.count == SystemEnvironmentReader.valueLimit)
    }
}
