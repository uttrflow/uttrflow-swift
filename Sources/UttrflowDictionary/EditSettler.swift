// The daily pass that counts the edits observed since the last one, bounded and in memory only.

import UttrflowCore

import struct Foundation.Date

/// Holds observed edits until the daily pass counts them into the pair ledger; see Docs/app-dictionary.md.
actor EditSettler {
    /// The most observed edits held at once; past it the oldest lapse.
    static let maximumPending = 5_000
    /// The longest one pass runs before it leaves the rest for the next.
    static let timeBudget = Duration.seconds(10)

    /// How a pass ended.
    enum Ending: Sendable, Equatable {
        /// Every held edit was counted.
        case finished
        /// The time budget ran out first; the rest stay held.
        case outOfTime
        /// Something else needed the machine; the rest stay held.
        case notIdle
        /// The dictionary could not be written; the edit that failed stays held.
        case couldNotWrite
        /// A pass already finished today.
        case alreadyRan
    }

    /// What one pass did.
    struct Report: Sendable, Equatable {
        let counted: Int
        let learnt: [DictionaryEntry]
        let remaining: Int
        let ending: Ending
    }

    private struct Observation {
        let heard: String
        let wrote: String
        let moment: Date
    }

    private let store: PersonalDictionaryStore
    private var held: [Observation] = []
    private var finishedDay: Int?

    init(store: PersonalDictionaryStore) { self.store = store }

    /// How many observed edits wait for the next pass.
    var pendingCount: Int { held.count }

    /// Holds one observed edit; the text is kept in memory only and never written.
    func observe(heard: String, wrote: String, at moment: Date) {
        held.append(Observation(heard: heard, wrote: wrote, moment: moment))
        if held.count > Self.maximumPending { held.removeFirst(held.count - Self.maximumPending) }
    }

    /// Counts held edits oldest first until none is left, `mayContinue` says no or `budget` runs out; one finished pass a day.
    func settle(
        on moment: Date, budget: Duration = EditSettler.timeBudget,
        mayContinue: @Sendable () async -> Bool
    ) async -> Report {
        let today = EvidenceRow.day(of: moment)
        guard finishedDay != today else {
            return Report(counted: 0, learnt: [], remaining: held.count, ending: .alreadyRan)
        }
        let deadline = ContinuousClock.now.advanced(by: budget)
        var counted = 0
        var learnt: [DictionaryEntry] = []
        var ending = Ending.finished
        while let next = held.first {
            if ContinuousClock.now >= deadline { ending = .outOfTime; break }
            if await !mayContinue() { ending = .notIdle; break }
            do {
                learnt += try await store.learnEdit(heard: next.heard, wrote: next.wrote, at: next.moment)
            } catch {
                ending = .couldNotWrite
                break
            }
            held.removeFirst()
            counted += 1
        }
        if ending == .finished { finishedDay = today }
        return Report(counted: counted, learnt: learnt, remaining: held.count, ending: ending)
    }
}
