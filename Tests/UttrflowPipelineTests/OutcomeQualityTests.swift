// Tests that a dictation's quality is decided once and every surface words it from one table.
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("Outcome quality")
struct OutcomeQualityTests {
    private static let words = "Send the draft to the team before noon."

    private static func state(_ quality: OutcomeQuality) -> DictationState {
        .inserted(DictationOutcome(text: words, method: .typed, cleanedBy: .rules, quality: quality))
    }

    private static let unavailable = CleaningRecord(
        changes: [],
        unavailableEngines: [.init(engine: "foundationModels", reason: .appleIntelligenceDisabled)])

    @Test("the rules after an unavailable, failed or refused model are named for that cause")
    func rulesRungs() {
        let refused = CleaningRecord(
            changes: [], refusals: [.init(engine: "localModel", reason: "x", kind: .lostWord)])
        let failed = CleaningRecord(
            changes: [], engineFailures: [.init(engine: "localModel", failureClass: .decoding)])
        #expect(
            OutcomeQuality(producedBy: .rules, account: Self.unavailable, missedPieces: 0)
                == .tidiedByRules(.modelUnavailable))
        #expect(
            OutcomeQuality(producedBy: .rules, account: failed, missedPieces: 0)
                == .tidiedByRules(.modelFailed))
        #expect(
            OutcomeQuality(producedBy: .rules, account: refused, missedPieces: 0)
                == .tidiedByRules(.answerRefused))
    }

    @Test("rules chosen on purpose, or a model that tidied, are complete")
    func completeRungs() {
        let empty = CleaningRecord(changes: [])
        for kind in [TransformerKind.rules, .foundationModels, .localModel] {
            #expect(OutcomeQuality(producedBy: kind, account: empty, missedPieces: 0) == .complete)
        }
        #expect(
            OutcomeQuality(producedBy: .foundationModels, account: Self.unavailable, missedPieces: 0)
                == .complete)
    }

    @Test("untidied words are degraded only when a cause is on record")
    func untidiedRungs() {
        let timeout = CleaningRecord.skipped(.tidy, .timeout)
        let error = CleaningRecord.skipped(.tidy, .error)
        #expect(
            OutcomeQuality(producedBy: .untidied, account: timeout, missedPieces: 0) == .untidied(.timedOut))
        #expect(OutcomeQuality(producedBy: .untidied, account: error, missedPieces: 0) == .untidied(.failed))
        #expect(
            OutcomeQuality(producedBy: .untidied, account: CleaningRecord(changes: []), missedPieces: 0)
                == .complete)
    }

    @Test("missing speech outranks every clean-up cause")
    func partialWins() {
        #expect(
            OutcomeQuality(producedBy: .untidied, account: .skipped(.tidy, .timeout), missedPieces: 1)
                == .partial)
    }

    @Test("an outcome built with only missed pieces is partial, and one without is complete")
    func defaultQuality() {
        let missed = DictationOutcome(text: "a", method: .typed, cleanedBy: .rules, missedPieces: 1)
        let whole = DictationOutcome(text: "a", method: .typed, cleanedBy: .rules)
        #expect(missed.quality == .partial)
        #expect(whole.quality == .complete)
    }

    @Test("every incomplete quality has a dock line and an announcement, and none names an engine")
    func everyRowIsShown() throws {
        let engines = TransformerKind.allCases.map(\.rawValue) + ["Apple", "MLX", "Foundation"]
        for quality in OutcomeQuality.incomplete {
            let row = try #require(quality.presentation, "\(quality)")
            let dock = DictationPresenter.dock(for: Self.state(quality))
            #expect(dock.primaryLine == row.line, "\(quality)")
            #expect(dock.secondaryLine == row.detail, "\(quality)")
            #expect(dock.accessibilityLabel.contains(row.sentence), "\(quality)")
            let said = try #require(DictationPresenter.announcement(for: Self.state(quality)))
            #expect(said.text.contains(row.sentence), "\(quality)")
            #expect(!said.isUrgent)
            for name in engines {
                #expect(!(row.line + row.detail + row.sentence).contains(name), "\(quality) names \(name)")
            }
            #expect(row.line.count <= 40, "\(quality) must fit the dock")
        }
    }

    @Test("a complete dictation shows nothing new")
    func completeIsQuiet() {
        #expect(OutcomeQuality.complete.presentation == nil)
        let dock = DictationPresenter.dock(for: Self.state(.complete))
        #expect(dock.primaryLine == "Inserted")
        let said = DictationPresenter.announcement(for: Self.state(.complete))
        #expect(said?.text.hasPrefix("Inserted: ") == true)
    }

    @Test("the copied and unconfirmed notices carry the quality sentence too")
    func otherOutcomesCarryIt() throws {
        let row = try #require(OutcomeQuality.untidied(.timedOut).presentation)
        let copied = DictationState.inserted(
            DictationOutcome(
                text: Self.words, method: .clipboard, cleanedBy: .untidied,
                quality: .untidied(.timedOut)))
        #expect(DictationPresenter.dock(for: copied).accessibilityLabel.contains(row.sentence))
        let said = try #require(DictationPresenter.announcement(for: copied))
        #expect(said.text.contains(row.sentence))
    }
}
