import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// The report, against the schema it has to satisfy.
///
/// The backend's ingest schema is `.strict()`: a key it does not recognise is a 400, not a
/// field it quietly ignores. That is the behaviour Uttrflow wants — a rejected request is a
/// bug report and a silently dropped field is a bug nobody finds — but it means the key
/// set here and the one in `src/telemetry/report.ts` have to agree exactly, so the key set
/// is asserted rather than assumed.
@Suite("The telemetry report matches the backend's schema")
struct TelemetryReportTests {
    /// Copied from `telemetryReportSchema` in the backend. If this list and that object
    /// diverge, every report Uttrflow sends is refused.
    private static let schemaKeys: Set<String> = [
        "windowStartedAt", "windowEndedAt", "appVersion", "osVersionMajor",
        "dictationCount", "cancelledCount", "failureCount",
        "audioTotalMs", "processingTotalMs", "charactersInserted",
        "latencyP50Ms", "latencyP90Ms", "latencyP99Ms",
        "languages", "stages",
    ]

    @Test("encodes every key the schema declares and not one more")
    func keysMatchTheSchema() throws {
        let report = try #require(
            Telemetry.report(
                osVersionMajor: 26, latencyP50Ms: 1, latencyP90Ms: 2, latencyP99Ms: 3,
                languages: [.english: 1],
                stages: [.init(stage: .insertion, failureCount: 0, latencyP50Ms: 1, latencyP90Ms: 2)]))

        #expect(Set(Telemetry.encodedObject(report).keys) == Self.schemaKeys)
    }

    /// Zod's `.optional()` accepts a missing key and refuses an explicit `null`, so an
    /// unmeasured percentile has to be absent rather than null.
    @Test("omits absent optionals rather than encoding null")
    func absentOptionalsAreOmitted() throws {
        let report = try #require(Telemetry.report(osVersionMajor: nil))
        let keys = Set(Telemetry.encodedObject(report).keys)

        #expect(!keys.contains("osVersionMajor"))
        #expect(!keys.contains("latencyP50Ms"))
        #expect(keys.union(Self.schemaKeys) == Self.schemaKeys)
    }

    /// `z.iso.datetime()` wants an ISO-8601 instant. Produced here rather than left to the
    /// caller's encoder, so a caller with a different date strategy cannot send a number.
    @Test("writes the window as ISO-8601 instants whatever the caller's encoder does")
    func windowIsISO8601() throws {
        let report = try #require(Telemetry.report())
        let object = Telemetry.encodedObject(report)

        #expect(object["windowStartedAt"] as? String == "2023-11-14T22:13:20Z")
        #expect(object["windowEndedAt"] as? String == "2023-11-14T23:13:20Z")
    }

    @Test("encodes the app version as three numbers, never as a string")
    func versionIsThreeNumbers() throws {
        let report = try #require(Telemetry.report())
        let version = try #require(Telemetry.encodedObject(report)["appVersion"] as? [String: Any])

        #expect(version["major"] as? Int == 1)
        #expect(version["minor"] as? Int == 4)
        #expect(version["patch"] as? Int == 2)
    }

    // MARK: - Refusals

    /// The table has `check (window_ended_at > window_started_at)`. A report that fails it
    /// is a 500 rather than a 400, so it is refused here instead.
    @Test("refuses a window that did not advance")
    func refusesAnEmptyWindow() {
        #expect(Telemetry.report(windowEndedAt: Telemetry.noon) == nil)
        #expect(Telemetry.report(windowEndedAt: Telemetry.noon.addingTimeInterval(-1)) == nil)
    }

    /// Nothing happened, so there is nothing to say. Sending it would cost the user's
    /// battery to tell the server that Uttrflow was not used.
    @Test("refuses a window with no dictations in it")
    func refusesAnIdleWindow() {
        #expect(Telemetry.report(dictationCount: 0) == nil)
        #expect(Telemetry.report(dictationCount: -5) == nil)
    }

    // MARK: - Ranges

    /// Every one of these is a refusal on the server: `count` and `durationMs` have upper
    /// bounds in Zod, and `cancelled_count <= dictation_count` is a `check` on the table.
    /// A rounded number is worth more than a rejected report.
    @Test("brings out-of-range numbers inside what the server accepts")
    func clampsToTheServersRanges() throws {
        let report = try #require(
            Telemetry.report(
                osVersionMajor: 10_000, dictationCount: .max, cancelledCount: .max,
                failureCount: -1, audioTotalMs: .max, processingTotalMs: -9, charactersInserted: -3))

        #expect(report.osVersionMajor == 999)
        #expect(report.dictationCount == 2_147_483_647)
        #expect(report.cancelledCount == report.dictationCount)
        #expect(report.failureCount == 0)
        #expect(report.audioTotalMs == 604_800_000)
        #expect(report.processingTotalMs == 0)
        #expect(report.charactersInserted == 0)
    }

    @Test("clamps every part of the app version")
    func clampsTheVersion() {
        let version = TelemetryReport.AppVersion(major: -1, minor: 1_000, patch: 12)
        #expect(version == TelemetryReport.AppVersion(major: 0, minor: 999, patch: 12))
    }

    /// The table refuses percentiles that go backwards, on the grounds that wrong numbers
    /// are worse than no numbers. Raised into order rather than dropped, so the report
    /// still arrives.
    @Test("raises percentiles that arrive out of order")
    func percentilesAreMonotonic() throws {
        let report = try #require(Telemetry.report(latencyP50Ms: 900, latencyP90Ms: 100, latencyP99Ms: 50))

        #expect(report.latencyP50Ms == 900)
        #expect(report.latencyP90Ms == 900)
        #expect(report.latencyP99Ms == 900)
    }

    /// The same rule one level down, where the table's per-stage `check` lives.
    @Test("raises a stage's p90 to its p50")
    func stagePercentilesAreMonotonic() {
        let outcome = TelemetryReport.StageOutcome(
            stage: .tidying, failureCount: -4, latencyP50Ms: 500, latencyP90Ms: 20)

        #expect(outcome.failureCount == 0)
        #expect(outcome.latencyP50Ms == 500)
        #expect(outcome.latencyP90Ms == 500)
    }

    /// A p99 with no p90 above it still has to clear the p50.
    @Test("raises the p99 past the p50 when there is no p90 between them")
    func p99ClearsTheMedianWithoutAP90() throws {
        let report = try #require(Telemetry.report(latencyP50Ms: 700, latencyP99Ms: 10))
        #expect(report.latencyP99Ms == 700)
    }

    /// A percentile with nothing beneath it has nothing to be raised above, so it stands as
    /// measured. Only the collector can produce these, and only briefly, but the ordering
    /// rule has to hold when the floor is missing as well as when it is there.
    @Test("leaves a percentile alone when the ones below it were not measured")
    func percentilesWithNoFloorAreLeftAlone() throws {
        let withoutMedian = try #require(Telemetry.report(latencyP90Ms: 5, latencyP99Ms: 9))
        #expect(withoutMedian.latencyP50Ms == nil)
        #expect(withoutMedian.latencyP90Ms == 5)
        #expect(withoutMedian.latencyP99Ms == 9)

        let onlyP99 = try #require(Telemetry.report(latencyP99Ms: 7))
        #expect(onlyP99.latencyP99Ms == 7)

        let stage = TelemetryReport.StageOutcome(
            stage: .insertion, failureCount: 0, latencyP50Ms: nil, latencyP90Ms: 5)
        #expect(stage.latencyP50Ms == nil)
        #expect(stage.latencyP90Ms == 5)
    }

    // MARK: - Collections

    /// Sixty-four language entries is the server's limit, and duplicate rows are summed
    /// there rather than refused. A dictionary in means neither can happen.
    @Test("sorts languages by tag and drops the ones with no dictations")
    func languagesAreSortedAndSparse() throws {
        let report = try #require(
            Telemetry.report(languages: [.hindi: 4, .english: 9, .tamil: 0, .french: -2]))

        #expect(report.languages.map(\.language) == [.english, .hindi])
        #expect(report.languages.map(\.dictationCount) == [9, 4])
    }

    /// `telemetry_stage_outcomes` is keyed on `(report_id, stage)`. Two rows for one stage
    /// would be summed by the upsert, which would silently double a failure count.
    @Test("keeps one outcome per stage, in the journey's order")
    func stagesAreUniqueAndOrdered() throws {
        let report = try #require(
            Telemetry.report(stages: [
                .init(stage: .insertion, failureCount: 1, latencyP50Ms: nil, latencyP90Ms: nil),
                .init(stage: .audioCapture, failureCount: 2, latencyP50Ms: nil, latencyP90Ms: nil),
                .init(stage: .insertion, failureCount: 99, latencyP50Ms: nil, latencyP90Ms: nil),
            ]))

        #expect(report.stages.map(\.stage) == [.audioCapture, .insertion])
        #expect(report.stages.map(\.failureCount) == [2, 1])
    }

    // MARK: - Vocabulary

    /// The stages the server has a name for, and the server's names for them. A new
    /// stage in ``PipelineStage`` makes ``TelemetryStage/init(_:)`` fail to compile,
    /// which is the moment somebody should decide whether it is reportable.
    @Test("names every reportable pipeline stage the way the server's enumeration does")
    func stageNamesMatchTheServer() {
        let mapped = PipelineStage.allCases.compactMap { TelemetryStage($0)?.rawValue }
        #expect(mapped == ["audio-capture", "transcription", "tidying", "insertion"])
    }

    /// The backend's `pipeline_stage` domain is closed and is not this repository's to
    /// widen, so the two stages it has no name for are measured on the Mac and kept
    /// there rather than sent under a name that would be rejected.
    @Test("a stage the server cannot name is not reportable")
    func unreportableStages() {
        #expect(TelemetryStage(.correction) == nil)
        #expect(TelemetryStage(.expansion) == nil)
    }

    @Test("narrows a known language and falls back for everything else")
    func languageNarrowing() throws {
        #expect(TelemetryLanguage(.english) == .english)
        #expect(TelemetryLanguage(.hindi) == .hindi)
        #expect(TelemetryLanguage(try #require(LanguageCode("EN-gb"))) == .english)
        #expect(TelemetryLanguage(try #require(LanguageCode("xyz"))) == .other)
    }

    /// Every tag has to satisfy the server's `language_tag` domain, or the report is a 400
    /// the first time somebody dictates in that language.
    @Test("every language tag matches the pattern the server enforces")
    func everyTagIsWellFormed() throws {
        let pattern = /^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$/
        for language in TelemetryLanguage.allCases {
            #expect(try pattern.wholeMatch(in: language.rawValue) != nil, "\(language.rawValue)")
            #expect(language.rawValue.count <= 12)
        }
    }
}
