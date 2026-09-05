import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// Enforces that ``TelemetryReport`` has no field able to hold text: counts leave the Mac, words never do.
@Suite("Telemetry cannot carry anybody's words")
struct TelemetryPrivacyTests {
    /// A report with every optional populated and every collection non-empty, so the walk sees every corner.
    private var fullyPopulated: TelemetryReport {
        get throws {
            try #require(
                Telemetry.report(
                    dictationCount: 12, cancelledCount: 2, failureCount: 1, audioTotalMs: 61_000,
                    processingTotalMs: 8_400, charactersInserted: 3_912, latencyP50Ms: 410,
                    latencyP90Ms: 900, latencyP99Ms: 1_400,
                    languages: [.english: 9, .hindi: 3],
                    stages: [
                        .init(stage: .transcription, failureCount: 1, latencyP50Ms: 300, latencyP90Ms: 640)
                    ]))
        }
    }

    /// Every stored property at every depth, by declared type, so a `String?` left `nil` is caught too.
    private func storedTypes(of value: Any, path: String = "") -> [(path: String, type: String)] {
        let mirror = Mirror(reflecting: value)
        return mirror.children.flatMap { child -> [(String, String)] in
            let childPath = path + "." + (child.label ?? "[]")
            let described = String(describing: type(of: child.value))
            return [(childPath, described)] + storedTypes(of: child.value, path: childPath)
        }
    }

    @Test("has no field, at any depth, that could hold a transcript")
    func noFreeTextAnywhere() throws {
        let offenders = storedTypes(of: try fullyPopulated).filter { $0.type.contains("String") }
        #expect(
            offenders.isEmpty,
            """
            TelemetryReport gained a text-shaped field: \(offenders).
            Uttrflow does not send anybody's words. Send a count instead.
            """)
    }

    /// ``TelemetryCollector`` has no method that takes text, so the compiler enforces the intake half.
    @Test("the collector has no way to be handed text in the first place")
    func intakeTakesOnlyNumbers() throws {
        let collector = Telemetry.collector()
        collector.recordDictation(
            .completed, language: TelemetryLanguage(.english), audio: .seconds(4),
            processing: .milliseconds(300), charactersInserted: 88)

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        #expect(report.charactersInserted == 88)
        #expect(storedTypes(of: report).filter { $0.type.contains("String") }.isEmpty)
    }

    /// An unfamiliar language becomes `und`, because a rare tag identifies a person far too sharply.
    @Test("an unrecognised language is reported as undetermined, not passed through")
    func unknownLanguagesAreNotPassedThrough() throws {
        let obscure = try #require(LanguageCode("kok"))
        #expect(TelemetryLanguage(obscure) == .other)
        #expect(TelemetryLanguage.other.rawValue == "und")
    }

    /// Every wire value is a number or one of a closed, short set of tags, so nothing can hide a sentence.
    @Test("every string on the wire is a timestamp or a language or stage tag")
    func encodedFormCarriesNoProse() throws {
        let object = Telemetry.encodedObject(try fullyPopulated)
        let strings = allStrings(in: object)

        #expect(!strings.isEmpty)
        for string in strings {
            let isTimestamp = string.hasSuffix("Z") && string.count == 20
            let isTag =
                TelemetryLanguage(rawValue: string) != nil || TelemetryStage(rawValue: string) != nil
            #expect(isTimestamp || isTag, "'\(string)' is neither a timestamp nor a known tag")
            // The server caps a `language_tag` at twelve characters, leaving no room for a sentence.
            #expect(string.count <= 20)
        }
    }

    /// Every string anywhere inside a decoded JSON value.
    private func allStrings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap(allStrings)
        case let dictionary as [String: Any]: dictionary.values.flatMap(allStrings)
        default: []
        }
    }

    /// The language set is closed and inside the server's limit of sixty-four, so it cannot overflow.
    @Test("the language list cannot outgrow what the server accepts")
    func languageSetIsBounded() {
        #expect(TelemetryLanguage.allCases.count <= 64)
        #expect(Set(TelemetryLanguage.allCases.map(\.rawValue)).count == TelemetryLanguage.allCases.count)
    }
}
