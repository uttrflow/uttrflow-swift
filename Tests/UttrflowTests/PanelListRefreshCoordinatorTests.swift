import Foundation
import Testing
import UttrflowClipboard
import UttrflowCore
@testable import Uttrflow

@Suite("Panel list refresh execution")
@MainActor
struct PanelListRefreshCoordinatorTests {
    private enum Source: CaseIterable { case store, recorded }
    private enum Phase: CaseIterable { case read, facts }
    private func clip(_ text: String) -> Clip {
        Clip(text: text, kind: .text, copiedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func facts(for clip: Clip) -> PanelListFacts {
        .init(missingPictures: [clip.id], missingFiles: [clip.id: ["missing.txt"]], formattable: [.swift])
    }

    @Test(
        "recorded clips bypass reading and reporting; store clips report before facts",
        arguments: Source.allCases)
    private func preservesReadOrdering(_ source: Source) async {
        let recorded = source == .recorded
        let coordinator = PanelListRefreshCoordinator()
        let clips = [clip("first"), clip("second")]
        let facts = facts(for: clips[0])
        var events: [String] = []
        var published = 0
        await coordinator.refresh(
            using: recorded ? clips : nil,
            readers: .init(
                clips: {
                    events.append("read"); return clips
                },
                reportUnreadable: { events.append("report") },
                facts: { received in
                    #expect(received == clips)
                    events.append("facts")
                    return facts
                }),
            publish: { received, receivedFacts in
                events.append("publish")
                published += 1
                #expect(received == clips)
                #expect(receivedFacts.missingPictures == facts.missingPictures)
                #expect(receivedFacts.missingFiles == facts.missingFiles)
                #expect(receivedFacts.formattable == facts.formattable)
            })
        #expect(events == (recorded ? ["facts", "publish"] : ["read", "report", "facts", "publish"]))
        #expect(published == 1)
    }

    private func suspendedReaders(
        for clip: Clip, phase: Phase, barrier: PanelRefreshBarrier
    ) -> PanelListRefreshCoordinator.Readers {
        let facts = facts(for: clip)
        return .init(
            clips: {
                if phase == .read { await barrier.pause() }
                return [clip]
            }, reportUnreadable: {},
            facts: { received in
                #expect(received == [clip])
                if phase == .facts { await barrier.pause() }
                return facts
            })
    }

    @Test("a newer refresh supersedes an earlier read or facts result", arguments: Phase.allCases)
    private func rejectsSupersededRefresh(_ phase: Phase) async {
        let coordinator = PanelListRefreshCoordinator()
        let first = clip("earlier")
        let latest = clip("latest")
        let latestFacts = facts(for: latest)
        let barrier = PanelRefreshBarrier()
        var published: [Clip.ID] = []
        let earlier = Task {
            await coordinator.refresh(
                readers: suspendedReaders(for: first, phase: phase, barrier: barrier),
                publish: { clips, _ in published.append(contentsOf: clips.map(\.id)) })
        }
        await barrier.waitUntilEntered()
        await coordinator.refresh(
            using: [latest],
            readers: .init(
                clips: {
                    Issue.record("recorded refresh read the store"); return []
                },
                reportUnreadable: { Issue.record("recorded refresh reported indexes") },
                facts: { received in
                    #expect(received == [latest])
                    return latestFacts
                }),
            publish: { clips, receivedFacts in
                published.append(contentsOf: clips.map(\.id))
                #expect(receivedFacts.missingPictures == latestFacts.missingPictures)
            })
        barrier.resume()
        await earlier.value
        #expect(published == [latest.id])
    }
}

@MainActor
private final class PanelRefreshBarrier {
    private let entered: AsyncStream<Void>
    private let arrival: AsyncStream<Void>.Continuation
    private let resumed: AsyncStream<Void>
    private let release: AsyncStream<Void>.Continuation

    init() {
        (entered, arrival) = AsyncStream.makeStream(of: Void.self)
        (resumed, release) = AsyncStream.makeStream(of: Void.self)
    }

    func pause() async {
        arrival.yield(())
        for await _ in resumed { break }
    }

    func waitUntilEntered() async {
        for await _ in entered { break }
    }

    func resume() {
        release.yield(())
        arrival.finish()
        release.finish()
    }
}
