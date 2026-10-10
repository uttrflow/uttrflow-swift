// Tests the disfluent-speech corpus schema and its metrics on invented takes, before any real take is recorded.
import Foundation
import Testing
import UttrflowAI

@testable import UttrflowEval

@Suite("Disfluent speech")
struct DisfluentSpeechTests {
    /// Invented takes, one or more per pattern, from two invented speaker labels.
    static let invented: [DisfluentUtterance] = [
        .init(
            id: "sound-but", speaker: "s01", pattern: .soundRepetition, marked: "{b-b-}but I want it today"),
        .init(
            id: "sound-call", speaker: "s02", pattern: .soundRepetition,
            marked: "please {c- c-}call the office"),
        .init(
            id: "part-banana", speaker: "s01", pattern: .partWordRepetition, marked: "buy a {ba- ba-}banana"),
        .init(
            id: "whole-i", speaker: "s02", pattern: .wholeWordRepetition, marked: "{I I} I need the report"),
        .init(id: "prolonged-so", speaker: "s01", pattern: .prolongation, marked: "{sss}so the build passed"),
        .init(id: "block-today", speaker: "s02", pattern: .block, marked: "the meeting is to day"),
        .init(
            id: "slow-garden", speaker: "s01", pattern: .slowEffortful,
            marked: "I would like to go to the garden"),
        .init(id: "fluent-plan", speaker: "s02", pattern: .fluent, marked: "the plan works for me"),
    ]

    @Test("reads what was meant and what was said off one marked transcript")
    func meantAndSaid() {
        let take = DisfluentUtterance(
            id: "t", speaker: "s01", pattern: .soundRepetition, marked: "{b-b-}but I {I I} want it")
        #expect(take.meant == "but I want it")
        #expect(take.said == "b-b-but I I I want it")
        #expect(take.disfluentWords == 4)
        let unbalanced = DisfluentUtterance(id: "u", speaker: "s01", pattern: .block, marked: "{b-but")
        #expect(unbalanced.meant == "{b-but")
        #expect(unbalanced.disfluentWords == 0)
    }

    @Test("passes every invented take and refuses each kind of bad mark or label")
    func validation() throws {
        try DisfluentSpeechCorpus(utterances: Self.invented).validate()
        func refusal(_ take: DisfluentUtterance) -> DisfluentSpeechError? {
            do {
                try take.validate()
                return nil
            } catch { return error as? DisfluentSpeechError }
        }
        func take(
            _ pattern: SpeechPattern = .soundRepetition, marked: String = "{b-}but", speaker: String = "s01",
            audio: String? = nil, consent: String? = nil
        ) -> DisfluentUtterance {
            DisfluentUtterance(
                id: "x", speaker: speaker, pattern: pattern, marked: marked, audio: audio, consent: consent)
        }
        #expect(refusal(take(marked: "{b-but")) == .unbalancedMark("x"))
        #expect(refusal(take(marked: "b-}but")) == .unbalancedMark("x"))
        #expect(refusal(take(marked: "{b-{b-}}but")) == .unbalancedMark("x"))
        #expect(refusal(take(marked: "{ }but")) == .emptyMark("x"))
        #expect(refusal(take(marked: "{b-b-}")) == .nothingMeant("x"))
        #expect(refusal(take(.prolongation, marked: "so it passed")) == .markMissing("x", .prolongation))
        #expect(refusal(take(.fluent, marked: "{uh} it passed")) == .markOnFluent("x"))
        #expect(refusal(take(speaker: "Avery Example")) == .speakerNotALabel("x"))
        #expect(refusal(take(audio: "t1.wav")) == .consentMissing("x"))
        #expect(refusal(take(audio: "t1.wav", consent: "")) == .consentMissing("x"))
        #expect(refusal(take(audio: "../t1.wav", consent: "v1")) == .audioOutsideFolder("x"))
        #expect(refusal(take(audio: "s02/t1.wav", consent: "v1")) == .audioOutsideFolder("x"))
        #expect(refusal(take(audio: "t1.wav", consent: "v1")) == nil)
        #expect(refusal(take(.block, marked: "the meeting is to day")) == nil)
        let doubled = DisfluentSpeechCorpus(utterances: [take(), take()])
        #expect(throws: DisfluentSpeechError.duplicateID("x")) { try doubled.validate() }
        let older = DisfluentSpeechCorpus(utterances: [take()], protocolVersion: 0)
        #expect(throws: DisfluentSpeechError.protocolVersion(0)) { try older.validate() }
    }

    @Test("loads a corpus file written by the recording Mac, and refuses one that does not validate")
    func loadsFromDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("corpus.json")
        let corpus = DisfluentSpeechCorpus(utterances: Self.invented)
        try JSONEncoder().encode(corpus).write(to: file)
        #expect(try DisfluentSpeechCorpus.load(from: file) == corpus)
        let json =
            #"{"protocolVersion":1,"utterances":[{"id":"a","speaker":"s01","pattern":"fluent","marked":"{uh}"}]}"#
        try Data(json.utf8).write(to: file)
        #expect(throws: DisfluentSpeechError.self) { try DisfluentSpeechCorpus.load(from: file) }
    }

    @Test("decodes each recorded take from its speaker's folder and prints the report under a corpus line")
    func scoresRecordedFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorded = [
            DisfluentUtterance(
                id: "a", speaker: "s01", pattern: .soundRepetition, marked: "{b-b-}but I want it",
                audio: "a.wav", consent: "v1"),
            DisfluentUtterance(
                id: "b", speaker: "s02", pattern: .fluent, marked: "the plan works", audio: "b.wav",
                consent: "v1"),
        ]
        for take in recorded {
            let speaker = folder.appendingPathComponent(take.speaker)
            try FileManager.default.createDirectory(at: speaker, withIntermediateDirectories: true)
            try Data().write(to: speaker.appendingPathComponent(take.audio ?? ""))
        }
        let corpus = DisfluentSpeechCorpus(utterances: recorded + [Self.invented[0]])
        try JSONEncoder().encode(corpus).write(to: folder.appendingPathComponent("corpus.json"))

        var decoded: [String] = []
        let lines = try await DisfluentSpeechRun.lines(folder: folder) { url in
            decoded.append(url.pathComponents.suffix(2).joined(separator: "/"))
            return url.lastPathComponent == "a.wav"
                ? .init(recognised: "b b but I want it", output: "But I want it.")
                : .init(recognised: "the plan works", output: "The plan works.")
        }
        #expect(decoded == ["s01/a.wav", "s02/b.wav"])
        #expect(
            lines.first
                == "2 recorded takes from 2 speakers; 1 take without audio skipped; "
                + "not enough to decide (needs 100 takes from 5 speakers)")
        #expect(lines.contains("recogniser against meant words"))
        #expect(lines.contains { $0.hasPrefix("sound-repetition\t1\t1\t4\t0\t") })

        try FileManager.default.removeItem(at: folder.appendingPathComponent("s02/b.wav"))
        await #expect(throws: DisfluentSpeechError.audioMissing("b")) {
            try await DisfluentSpeechRun.lines(folder: folder) { _ in .init(recognised: "", output: "") }
        }
    }

    @Test("asks for 100 takes from 5 speakers before a pass decision is read off the report")
    func enoughToDecide() {
        func corpus(takes: Int, speakers: Int) -> DisfluentSpeechCorpus {
            DisfluentSpeechCorpus(
                utterances: (0..<takes).map {
                    DisfluentUtterance(
                        id: "t\($0)", speaker: "s\($0 % speakers)", pattern: .fluent, marked: "it works")
                })
        }
        #expect(corpus(takes: 100, speakers: 5).isEnoughToDecide)
        #expect(!corpus(takes: 99, speakers: 5).isEnoughToDecide)
        #expect(!corpus(takes: 100, speakers: 4).isEnoughToDecide)
        #expect(!DisfluentSpeechCorpus(utterances: Self.invented).isEnoughToDecide)
    }

    @Test("counts a meant word lost, a disfluency left in and a misheard word apart")
    func scoresOneTake() {
        let take = DisfluentUtterance(
            id: "t", speaker: "s01", pattern: .soundRepetition, marked: "{b-b-}but I want it today")
        let clean = DisfluentSpeechScore(utterance: take, output: "But I want it today.")
        #expect((clean.lost, clean.leftIn, clean.misheard) == (0, 0, 0))
        let verbatim = DisfluentSpeechScore(utterance: take, output: take.said)
        #expect((verbatim.lost, verbatim.leftIn) == (0, 2))
        let overDeleted = DisfluentSpeechScore(utterance: take, output: "I want it today.")
        #expect((overDeleted.lost, overDeleted.leftIn) == (1, 0))
        let misheard = DisfluentSpeechScore(utterance: take, recognised: "b but I won it today", output: "")
        #expect(misheard.meantWords == 5)
        #expect(misheard.lost == 5)
        let recognition = misheard.recognition
        #expect(recognition?.insertions == 1)
        #expect(recognition?.substitutions == 1)
        #expect(clean.recognition == nil)
    }

    @Test("reports each pattern's takes, speakers and rates, and the recogniser's rows only with audio")
    func report() throws {
        let scores = Self.invented.map { DisfluentSpeechScore(utterance: $0, output: $0.said) }
        let report = DisfluentSpeechReport(scores: scores)
        #expect(report.rows.map(\.pattern) == SpeechPattern.allCases)
        #expect(report.recognition == nil)
        let sound = try #require(report.rows.first { $0.pattern == .soundRepetition })
        #expect((sound.takes, sound.speakers, sound.disfluentWords, sound.leftIn) == (2, 2, 4, 4))
        #expect(sound.leftInRate == 1)
        #expect(sound.lostRate == 0)
        let fluent = try #require(report.rows.first { $0.pattern == .fluent })
        #expect(fluent.leftInRate == nil)
        #expect(report.lines.count == 1 + SpeechPattern.allCases.count)

        let heard = Self.invented.map {
            DisfluentSpeechScore(utterance: $0, recognised: $0.said, output: $0.meant)
        }
        let withAudio = DisfluentSpeechReport(scores: heard)
        let rows = try #require(withAudio.recognition?.rows)
        #expect(Set(rows.map(\.group)) == Set(SpeechPattern.allCases.map(\.rawValue)))
        #expect(withAudio.rows.allSatisfy { $0.lost == 0 && $0.leftIn == 0 })
        #expect(withAudio.lines.contains("recogniser against meant words"))
    }

    @Test("scores the rules engine over the invented takes, so the metrics run on the shipping clean-up")
    func rulesEngine() async throws {
        var scores: [DisfluentSpeechScore] = []
        for take in Self.invented {
            let request = EvaluationCase(
                id: take.id, category: .everyday, spoken: take.said, expected: take.meant
            )
            .transformationRequest()
            let output = try await RuleBasedTransformer().transform(request).text
            scores.append(DisfluentSpeechScore(utterance: take, recognised: take.said, output: output))
        }
        let report = DisfluentSpeechReport(scores: scores)
        print(report.lines.joined(separator: "\n"))
        for row in report.rows {
            #expect(row.lost + row.misheard <= row.meantWords, "\(row.pattern)")
        }
        let fluent = try #require(report.rows.first { $0.pattern == .fluent })
        #expect((fluent.lost, fluent.leftIn, fluent.misheard) == (0, 0, 0))
    }
}
