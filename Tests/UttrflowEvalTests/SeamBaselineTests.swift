// Tests the seam baseline: the cuts only some macOS releases make differ, and what leaves them alone.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Seam baseline")
struct SeamBaselineTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let baseline = SeamBaseline(
        cuts: ["alpha@1", "beta@2"],
        osDependent: SeamBaseline.OSDependent(system: "Version 26.6.2 (Build 25G83)", cuts: ["gamma@3"]))

    @Test("a cut listed as OS-dependent is tolerated whether or not it differs")
    func toleratesListedCuts() {
        #expect(Self.baseline.risen(among: ["alpha@1", "gamma@3"]).isEmpty)
        #expect(Self.baseline.risen(among: ["alpha@1"]).isEmpty)
    }

    @Test("a cut listed in neither section fails the audit")
    func refusesUnlistedCuts() {
        #expect(Self.baseline.risen(among: ["gamma@3", "delta@4", "gamma@4"]) == ["delta@4", "gamma@4"])
    }

    @Test("recording the cuts a run found leaves the OS-dependent section as it was")
    func recordingKeepsOSDependent() {
        let recorded = Self.baseline.recording(["alpha@1", "gamma@3"])
        #expect(recorded.cuts == ["alpha@1"])
        #expect(recorded.osDependent == Self.baseline.osDependent)
        #expect(Self.baseline.recording([]).osDependent == Self.baseline.osDependent)
    }

    @Test("a baseline written and read back keeps the system and the OS-dependent cuts")
    func roundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "seam-baseline-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.baseline.write(to: url)
        #expect(try SeamBaseline.read(from: url) == Self.baseline)
    }

    @Test("a baseline written before the section existed still reads")
    func readsTheOlderShape() throws {
        let older = Data(#"{"cuts":["alpha@1"],"total":1}"#.utf8)
        let baseline = try JSONDecoder().decode(SeamBaseline.self, from: older)
        #expect(baseline == SeamBaseline(cuts: ["alpha@1"]))
    }

    @Test("the committed baseline names the system its OS-dependent cuts were read on, and lists no cut twice")
    func committedBaselineIsWellFormed() throws {
        let baseline = try SeamBaseline.read(from: Self.root.appending(path: "Scripts/seam_baseline.json"))
        let dependent = try #require(baseline.osDependent)
        #expect(!dependent.system.isEmpty)
        #expect(!dependent.cuts.isEmpty)
        #expect(Set(dependent.cuts).isDisjoint(with: baseline.cuts))
        #expect(Set(dependent.cuts).count == dependent.cuts.count)
    }
}
