import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore

/// The promise, as tests.
///
/// Uttrflow's owner wants to know how the app is used and has said plainly that they do not
/// want anybody's words. Those two are only compatible if the second is *enforced* rather
/// than intended, because an intention lasts exactly until the first Monday somebody is
/// debugging a bad transcription and thinks "if only we had the text".
///
/// So this suite is the enforcement, and it is deliberately blunt about it:
///
/// **``TelemetryReport`` must never gain a field capable of holding free text.** Not a
/// `String`, not an optional one, not an array of them, at any depth. If you are here
/// because you added one and this failed, the answer is not to relax the test. Audio,
/// transcripts, dictionary entries, window titles, application names and corrected words
/// do not leave the user's Mac. Counts of them may. If you need a new number, add a number
/// — and a matching column in `migrations/0005_telemetry.sql`, which refuses text for the
/// same reason.
///
/// The two timestamps are the one place a string appears on the wire, and they are
/// produced by `Date.formatted(.iso8601)` during encoding from a `Date` that is a count of
/// seconds. There is no way for a caller to reach them.
@Suite("Telemetry cannot carry anybody's words")
struct TelemetryPrivacyTests {
    /// A report with every optional populated and every collection non-empty, so the walk
    /// below has something to look at in every corner of the type.
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

    /// Every stored property, at every depth, by its declared type.
    ///
    /// By type rather than by value, so that a `String?` left `nil` is caught just as
    /// surely as one somebody filled in.
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

    /// The other half of the same promise: the intake refuses text too.
    ///
    /// A report with no text on it would still be no protection at all if the collector
    /// accepted a transcript and threw it away — the words would have been handed to a
    /// subsystem whose whole job is uploading, one refactor away from going with them.
    /// ``TelemetryCollector`` has no method that takes one, so this is checked by the
    /// compiler on every build: the line below is the only shape a dictation can be
    /// reported in, and it is five numbers and two enumerations.
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

    /// An unfamiliar language becomes `und` rather than travelling as itself.
    ///
    /// A rare tag identifies a person far more sharply than a common one, and the product
    /// question is answered either way.
    @Test("an unrecognised language is reported as undetermined, not passed through")
    func unknownLanguagesAreNotPassedThrough() throws {
        let obscure = try #require(LanguageCode("kok"))
        #expect(TelemetryLanguage(obscure) == .other)
        #expect(TelemetryLanguage.other.rawValue == "und")
    }

    /// Every value the wire can carry is either a number or one of a closed, short set of
    /// tags — so even the encoded form has nowhere to hide a sentence.
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
            // Even if one slipped through the check above, there is not room in it for a
            // sentence. The server's `language_tag` domain caps tags at twelve characters.
            #expect(string.count <= 20)
        }
    }

    private func allStrings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap(allStrings)
        case let dictionary as [String: Any]: dictionary.values.flatMap(allStrings)
        default: []
        }
    }

    /// The set of languages is closed and comfortably inside the server's limit of
    /// sixty-four entries, so `languages` cannot overflow it however people dictate.
    @Test("the language list cannot outgrow what the server accepts")
    func languageSetIsBounded() {
        #expect(TelemetryLanguage.allCases.count <= 64)
        #expect(Set(TelemetryLanguage.allCases.map(\.rawValue)).count == TelemetryLanguage.allCases.count)
    }
}
