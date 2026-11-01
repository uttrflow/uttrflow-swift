// Tests for the daily pass that settles observed edits.

import Foundation
import Testing

@testable import UttrflowDictionary

private func day(_ number: Int) -> Date { Date(timeIntervalSince1970: Double(number) * 86_400 + 3_600) }

@Suite("The daily pass counts observed edits")
struct EditSettlerTests {
    private func settler(_ sandbox: borrowing Sandbox) -> EditSettler {
        EditSettler(store: PersonalDictionaryStore(file: sandbox.file))
    }

    @Test("Observed edits change nothing until the pass runs, then recurrence makes one entry")
    func learnsAtThePass() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        for number in [10, 10, 11] {
            await settler.observe(heard: "cooper nettys", wrote: "Kubernetes", at: day(number))
        }
        #expect(sandbox.onDisk() == nil)
        let report = await settler.settle(on: day(12)) { true }
        #expect(report.learnt.map(\.word) == ["Kubernetes"])
        #expect(report.ending == .finished)
        #expect(await settler.pendingCount == 0)
    }

    @Test("A second pass on the same day changes nothing")
    func idempotent() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        for number in [10, 11, 12] {
            await settler.observe(heard: "cooper nettys", wrote: "Kubernetes", at: day(number))
        }
        _ = await settler.settle(on: day(13)) { true }
        let before = sandbox.onDisk()
        await settler.observe(heard: "gate", wrote: "git", at: day(13))
        let again = await settler.settle(on: day(13)) { true }
        #expect(again.ending == .alreadyRan)
        #expect(again.counted == 0)
        #expect(sandbox.onDisk() == before)
        #expect(await settler.pendingCount == 1)
    }

    @Test("A pass never starts an edit while something else holds the machine")
    func yieldsWhenBusy() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        await settler.observe(heard: "gate", wrote: "git", at: day(10))
        let report = await settler.settle(on: day(11)) { false }
        #expect(report.ending == .notIdle)
        #expect(report.counted == 0)
        #expect(report.remaining == 1)
        let resumed = await settler.settle(on: day(11)) { true }
        #expect(resumed.ending == .finished)
        #expect(resumed.remaining == 0)
    }

    @Test("A pass out of time leaves the rest held and may be run again")
    func stopsAtTheBudget() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        await settler.observe(heard: "gate", wrote: "git", at: day(10))
        let report = await settler.settle(on: day(11), budget: .zero) { true }
        #expect(report.ending == .outOfTime)
        #expect(report.remaining == 1)
    }

    @Test("A backlog past the bound keeps the newest edits")
    func boundsTheBacklog() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        for _ in 0..<(EditSettler.maximumPending + 25) {
            await settler.observe(heard: "gate", wrote: "git", at: day(10))
        }
        #expect(await settler.pendingCount == EditSettler.maximumPending)
    }

    @Test("A full backlog settles inside the time budget")
    func fullBacklogWithinBudget() async {
        let sandbox = Sandbox()
        let settler = settler(sandbox)
        for index in 0..<EditSettler.maximumPending {
            await settler.observe(heard: "gate \(index % 40)", wrote: "git", at: day(10 + index % 3))
        }
        let start = ContinuousClock.now
        let report = await settler.settle(on: day(20)) { true }
        #expect(report.ending == .finished)
        #expect(ContinuousClock.now - start < EditSettler.timeBudget)
    }

    @Test("A store that cannot be written keeps the edit held")
    func keepsWhatItCouldNotWrite() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let settler = EditSettler(store: store)
        for number in [10, 11, 12] {
            await settler.observe(heard: "cooper nettys", wrote: "Kubernetes", at: day(number))
        }
        try FileManager.default.createDirectory(
            at: sandbox.root, withIntermediateDirectories: true)
        try Data().write(to: sandbox.folder)
        let report = await settler.settle(on: day(13)) { true }
        #expect(report.ending == .couldNotWrite)
        #expect(report.remaining >= 1)
    }
}
