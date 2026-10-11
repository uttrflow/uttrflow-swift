// Measures what the shipping recogniser writes for speech in a language the product does not transcribe.
import Foundation
import Testing
import UttrflowCore
import WhisperKit

@testable import UttrflowSpeech

/// Ten invented sentences per language and the system voice that speaks them.
enum UnsupportedLanguageClips {
    static let sets: [(language: String, voice: String, sentences: [String])] = [
        (
            "Spanish", "Mónica",
            [
                "Mañana por la tarde vamos a visitar a mi abuela en el pueblo.",
                "Necesito comprar pan, leche y unas manzanas antes de las seis.",
                "El tren hacia la costa sale con retraso por la lluvia.",
                "Me gustaría reservar una mesa para cuatro personas esta noche.",
                "La reunión del equipo se ha cambiado al jueves por la mañana.",
                "Mi hermana trabaja en una biblioteca cerca del río.",
                "Por favor envíame el informe antes de que termine la semana.",
                "Hoy hace mucho calor y nadie quiere salir de casa.",
                "Aprendí a cocinar paella con una receta muy antigua.",
                "El profesor explicó la lección con paciencia y buen humor.",
            ]
        ),
        (
            "French", "Thomas",
            [
                "Demain matin nous allons au marché acheter des légumes frais.",
                "Je voudrais réserver une chambre pour deux nuits en septembre.",
                "Le train pour Lyon part dans dix minutes depuis le quai trois.",
                "Ma soeur travaille dans une petite boulangerie près de la gare.",
                "Pouvez-vous m'envoyer le document avant la fin de la journée.",
                "Il pleut depuis ce matin et les rues sont presque vides.",
                "Nous avons dîné dans un restaurant au bord de la rivière.",
                "Le professeur a expliqué la leçon avec beaucoup de patience.",
                "J'ai oublié mon parapluie dans le taxi hier soir.",
                "La réunion de l'équipe est déplacée à jeudi après-midi.",
            ]
        ),
        (
            "German", "Anna",
            [
                "Morgen Nachmittag besuchen wir meine Großmutter auf dem Land.",
                "Ich muss noch Brot, Milch und ein paar Äpfel einkaufen.",
                "Der Zug zur Küste hat wegen des Regens Verspätung.",
                "Wir möchten für heute Abend einen Tisch für vier Personen reservieren.",
                "Die Teambesprechung wurde auf Donnerstagvormittag verschoben.",
                "Meine Schwester arbeitet in einer Bibliothek am Fluss.",
                "Bitte schicken Sie mir den Bericht noch vor dem Wochenende.",
                "Heute ist es so heiß, dass niemand das Haus verlassen möchte.",
                "Der Lehrer erklärte die Aufgabe mit viel Geduld und Humor.",
                "Ich habe meinen Regenschirm gestern Abend im Taxi vergessen.",
            ]
        ),
        (
            "Japanese", "Kyoko",
            [
                "明日の午後、田舎に住むおばあちゃんを訪ねる予定です。",
                "夕方までにパンと牛乳とりんごを買わなければなりません。",
                "雨のため、海へ向かう電車は遅れて出発します。",
                "今夜、四人で食事ができる席を予約したいのですが。",
                "チームの会議は木曜日の朝に変更になりました。",
                "私の姉は川の近くの図書館で働いています。",
                "週末までに報告書を送ってください。",
                "今日はとても暑くて、誰も外に出たがりません。",
                "先生は辛抱強く、楽しそうに授業を説明しました。",
                "昨日の夜、タクシーに傘を忘れてしまいました。",
            ]
        ),
    ]
}

/// The real model on spoken clips, run only when `UTTRFLOW_PROBE_UNSUPPORTED` is set and the model is installed.
@Suite(
    "Probing the shipping recogniser on languages it does not transcribe",
    .enabled(
        if: ProcessInfo.processInfo.environment["UTTRFLOW_PROBE_UNSUPPORTED"] != nil
            && FileManager.default.fileExists(atPath: ProbeInputs.modelFolder.path),
        "set UTTRFLOW_PROBE_UNSUPPORTED and install the shipping model"))
struct UnsupportedLanguageProbe {
    @Test("prints, per clip, the language chosen, its margin among the allowed and among all, and the text")
    func probe() async throws {
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: ProbeInputs.modelFolder.path, tokenizerFolder: ProbeInputs.modelFolder,
                verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
        let plain = kit.textDecoder
        let held = LanguageHeldDecoder(wrapping: plain, languages: LanguageCode.transcribed)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "unsupported-language-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var index = 0
        for set in UnsupportedLanguageClips.sets {
            for sentence in set.sentences {
                index += 1
                let path = try Self.speak(sentence, voice: set.voice, into: folder, name: "clip\(index)")
                let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
                kit.textDecoder = plain
                let free = try await kit.detectLanguage(audioPath: path)
                kit.textDecoder = held
                let results = try await kit.transcribe(
                    audioArray: samples, decodeOptions: VocabularyPrompt.decodingOptions(languageHint: nil))
                let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                let chosen = results.first?.language ?? "-"
                let ranked = free.langProbs.sorted { $0.value > $1.value }
                let top = ranked.first.map { "\($0.key) \(String(format: "%.2f", $0.value))" } ?? "-"
                print("PROBE \(set.language) #\(index) held=\(chosen) free=\(top) text=\(text)")
            }
        }
    }

    /// The sentence spoken by `voice` into a 16 kHz mono wav.
    static func speak(_ sentence: String, voice: String, into folder: URL, name: String) throws -> String {
        let aiff = folder.appendingPathComponent("\(name).aiff").path
        let wav = folder.appendingPathComponent("\(name).wav").path
        try run("/usr/bin/say", ["-v", voice, "-o", aiff, sentence])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav])
        return wav
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
