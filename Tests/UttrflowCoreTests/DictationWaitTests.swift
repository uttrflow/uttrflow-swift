import Testing

@testable import UttrflowCore

@Suite("Splitting a dictation's wait by cause")
struct DictationWaitTests {
    @Test("Fallback seconds, screen reads, a timed-out tidy and the insertion are each named; the rest is other.")
    func stagesMapToCauses() {
        let wait = DictationWait(
            wait: .seconds(10),
            stages: [
                StageMeasurement(stage: .transformation, duration: .seconds(3), succeeded: false),
                StageMeasurement(stage: .insertion, duration: .seconds(1), succeeded: true),
                StageMeasurement(stage: .transcription, duration: .seconds(2), succeeded: true),
            ],
            decoding: [DecodeEffort(fallbacks: 1, fallbackSeconds: 1.5)],
            screenReads: .milliseconds(500))
        #expect(wait.spent[.tidyTimeout] == .seconds(3))
        #expect(wait.spent[.insertionConfirmation] == .seconds(1))
        #expect(wait.spent[.fallbackDecode] == .milliseconds(1_500))
        #expect(wait.spent[.contextRead] == .milliseconds(500))
        #expect(wait.spent[.other] == .seconds(4))
    }

    @Test("A tidy that finished in time is not a timeout.")
    func finishedTidyIsNotATimeout() {
        let wait = DictationWait(
            wait: .seconds(2),
            stages: [StageMeasurement(stage: .transformation, duration: .seconds(1), succeeded: true)],
            decoding: [], screenReads: .zero)
        #expect(wait.spent[.tidyTimeout] == nil)
    }

    @Test("A slow dictation is named by the cause furthest past its usual cost in the log.")
    func logNamesTheCauseAgainstTheMedian() {
        var log = DictationWaits()
        for _ in 0..<5 {
            log.classify(
                DictationWait(wait: .seconds(3), spent: [.contextRead: .seconds(2), .other: .seconds(1)]))
        }
        let slow = log.classify(
            DictationWait(
                wait: .seconds(6),
                spent: [.contextRead: .milliseconds(2_500), .fallbackDecode: .seconds(2), .other: .seconds(1)]))
        #expect(slow.cause == .fallbackDecode)
        #expect(log.causeCounts == [.fallbackDecode: 1])
    }

    @Test("A wait within the target has no cause.")
    func fastWaitHasNoCause() {
        var log = DictationWaits()
        #expect(log.classify(DictationWait(wait: DictationWait.target, spent: [.other: .seconds(4)])).cause == nil)
    }

    @Test("p50 and p95 are observed waits, per dictation, and the log keeps only the newest hundred.")
    func percentilesAndCapacity() {
        var log = DictationWaits()
        for second in 1...120 { log.keep(TimedWait(wait: DictationWait(wait: .seconds(second), spent: [:]), cause: nil)) }
        #expect(log.timed.count == DictationWaits.capacity)
        #expect(log.typical == .seconds(71))
        #expect(log.tail == .seconds(115))
    }
}
