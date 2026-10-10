// Tests for the guided-read profile and its round trip through the evidence ledger.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowCore

@Suite("Calibration profile")
struct CalibrationProfileTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private func store(_ directory: URL? = nil) throws -> (EvidenceLedgerStore, URL) {
        let folder =
            directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ledger.json")
        return (EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys())), folder)
    }

    private let now = Date(timeIntervalSince1970: 20_001 * 86_400 + 43_200)
    private var always: RetentionWindow { RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now) }

    private let first = CalibrationProfile(
        wordsPerMinute: 148.4, medianPause: 0.12, longPause: 0.9, medianConfidence: 0.87, targets: 14,
        missedTargets: ["grep", "awk"])

    @Test("a profile survives its rows, rounded to whole units, and an empty ledger has none")
    func roundTrips() {
        #expect(CalibrationProfile.project([]) == nil)
        let back = CalibrationProfile.project(first.rows(day: 20_000))
        #expect(back?.wordsPerMinute == 148)
        #expect(back?.medianPause == 0.12)
        #expect(back?.longPause == 0.9)
        #expect(back?.medianConfidence == 0.87)
        #expect(back?.targets == 14)
        #expect(back?.missedTargets == ["awk", "grep"])
    }

    @Test("a measure that was not taken writes no row")
    func untakenMeasuresWriteNothing() {
        let sparse = CalibrationProfile(
            wordsPerMinute: nil, medianPause: nil, longPause: nil, medianConfidence: nil, targets: 0,
            missedTargets: [])
        #expect(sparse.rows(day: 1).map(\.subject) == ["targets"])
        #expect(CalibrationProfile.project(sparse.rows(day: 1))?.wordsPerMinute == nil)
        #expect(sparse.pauses == nil)
    }

    @Test("the long gap picks the shortest pause setting whose sentence pause it stays under")
    func picksPauseSetting() {
        func pauses(_ gap: Double) -> PauseLength? {
            CalibrationProfile(
                wordsPerMinute: nil, medianPause: nil, longPause: gap, medianConfidence: nil, targets: 0,
                missedTargets: []
            ).pauses
        }
        #expect(pauses(0.01) == .usual)
        #expect(pauses(100) == .veryLong)
    }

    @Test("running it twice replaces the reading, leaves other evidence, and clearing removes it")
    func replacesNotAdds() async throws {
        let (ledger, _) = try store()
        let other = EvidenceRow(kind: .use, subject: "entry-1", day: 20_000, provenance: .dictation)
        try await ledger.append([other], keeping: always)
        try await ledger.replaceCalibration(with: first, day: 20_000, keeping: always)
        let second = CalibrationProfile(
            wordsPerMinute: 120, medianPause: 0.3, longPause: 1.4, medianConfidence: 0.7, targets: 14,
            missedTargets: ["sed"])
        try await ledger.replaceCalibration(with: second, day: 20_001, keeping: always)
        let rows = await ledger.rows(keeping: always)
        #expect(rows.filter { $0.kind == .use } == [other])
        #expect(CalibrationProfile.project(rows)?.missedTargets == ["sed"])
        #expect(CalibrationProfile.project(rows)?.wordsPerMinute == 120)
        #expect(rows.filter { $0.kind == .calibration }.count == second.rows(day: 20_001).count)
        try await ledger.clearCalibration()
        #expect(await ledger.rows(keeping: always) == [other])
    }

    @Test("the stored rows hold aggregates only: the file is sealed and carries no passage text")
    func storesNoText() async throws {
        let (ledger, folder) = try store()
        try await ledger.replaceCalibration(with: first, day: 20_000, keeping: always)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["ledger.json"])
        let bytes = try Data(contentsOf: folder.appendingPathComponent("ledger.json"))
        #expect(EncryptedStore.isSealed(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("wordsPerMinute"))
    }

    @Test("a failed replace leaves the earlier reading whole")
    func failedReplaceKeepsOldRows() async throws {
        let (ledger, folder) = try store()
        try await ledger.replaceCalibration(with: first, day: 20_000, keeping: always)
        let file = folder.appendingPathComponent("ledger.json")
        let before = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        await #expect(throws: (any Error).self) {
            try await ledger.replaceCalibration(with: first, day: 20_001, keeping: always)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == before)
    }
}
