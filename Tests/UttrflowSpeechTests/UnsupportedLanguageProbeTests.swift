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
    @Test("refuses every French, German and Japanese clip and prints, per clip, what became of it")
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
        var inserted: [String: Int] = [:]
        var refused: [String: Int] = [:]
        for set in UnsupportedLanguageClips.sets {
            for sentence in set.sentences {
                index += 1
                let path = try Self.speak(sentence, voice: set.voice, into: folder, name: "clip\(index)")
                let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
                kit.textDecoder = plain
                let free = try await kit.detectLanguage(audioPath: path)
                kit.textDecoder = held
                let ranked = free.langProbs.sorted { $0.value > $1.value }
                let top = ranked.first.map { "\($0.key) \(String(format: "%.2f", $0.value))" } ?? "-"
                do {
                    let results = try await kit.transcribe(
                        audioArray: samples,
                        decodeOptions: VocabularyPrompt.decodingOptions(languageHint: nil))
                    let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    inserted[set.language, default: 0] += 1
                    print(
                        "PROBE \(set.language) #\(index) free=\(top) INSERTED held=\(results.first?.language ?? "-") text=\(text)"
                    )
                } catch SpeechEngineError.unsupportedLanguage(let language) {
                    refused[set.language, default: 0] += 1
                    print("PROBE \(set.language) #\(index) free=\(top) REFUSED \(language.value)")
                }
            }
        }
        print("PROBE SUMMARY refused=\(refused) inserted=\(inserted)")
        // Spanish is heard as English by the unrestricted detector, so detection cannot reach it.
        for language in ["French", "German", "Japanese"] {
            #expect(refused[language] == 10, "every \(language) clip is refused")
            #expect(inserted[language] == nil, "no \(language) clip is inserted")
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

/// Speech in the languages the product does write, which the refusal must never touch.
@Suite(
    "Probing that English and Hindi speech is never refused",
    .enabled(
        if: ProcessInfo.processInfo.environment["UTTRFLOW_PROBE_UNSUPPORTED"] != nil
            && FileManager.default.fileExists(atPath: ProbeInputs.modelFolder.path),
        "set UTTRFLOW_PROBE_UNSUPPORTED and install the shipping model"))
struct TranscribedLanguageGate {
    /// Invented sentences, each set read by the system voice named with it.
    static let sets: [(voice: String, sentences: [String])] = [
        (
            "Daniel",
            [
                "Tomorrow afternoon we are visiting my grandmother in the village.",
                "I need to buy bread, milk and a few apples before six.",
                "The train to the coast is running late because of the rain.",
                "Could you send me the report before the end of the week.",
                "The team meeting has moved to Thursday morning.",
            ]
        ),
        (
            "Rishi",
            [
                "Please book a table for four people tonight.",
                "My sister works in a library near the river.",
                "It is very hot today and nobody wants to leave the house.",
                "I learned to cook a new recipe from an old book.",
                "The teacher explained the lesson with patience and humour.",
            ]
        ),
        (
            "Samantha",
            [
                "I left my umbrella in the taxi last night.",
                "Let us review the schedule for the next three weeks.",
                "The new design looks cleaner than the last one.",
                "Remind me to call the dentist on Monday.",
                "Add two bottles of water to the shopping list.",
            ]
        ),
        (
            "Lekha",
            [
                "कल दोपहर हम गाँव में दादी से मिलने जाएँगे।",
                "मुझे छह बजे से पहले रोटी, दूध और कुछ सेब खरीदने हैं।",
                "बारिश की वजह से तट की ओर जाने वाली गाड़ी देर से चल रही है।",
                "कृपया हफ़्ते के अंत से पहले मुझे रिपोर्ट भेज दीजिए।",
                "आज बहुत गर्मी है और कोई घर से बाहर नहीं निकलना चाहता।",
                "मेरी बहन नदी के पास एक पुस्तकालय में काम करती है।",
                "टीम की बैठक गुरुवार सुबह के लिए बदल दी गई है।",
                "शिक्षक ने धैर्य और हँसी के साथ पाठ समझाया।",
            ]
        ),
    ]

    @Test("refuses none of the system-voice clips, nor any real recording named in UTTRFLOW_PROBE_RECORDINGS")
    func gate() async throws {
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: ProbeInputs.modelFolder.path, tokenizerFolder: ProbeInputs.modelFolder,
                verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
        kit.textDecoder = LanguageHeldDecoder(wrapping: kit.textDecoder, languages: LanguageCode.transcribed)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "transcribed-language-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var paths: [String] = []
        for set in Self.sets {
            for sentence in set.sentences {
                paths.append(
                    try UnsupportedLanguageProbe.speak(
                        sentence, voice: set.voice, into: folder, name: "gate\(paths.count)"))
            }
        }
        let recordings = (ProcessInfo.processInfo.environment["UTTRFLOW_PROBE_RECORDINGS"] ?? "")
            .split(separator: ",").map(String.init)
        for session in recordings {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: session)) ?? []
            paths += names.filter { $0.hasSuffix(".wav") }.sorted().map { "\(session)/\($0)" }
        }
        var refused = 0
        for path in paths {
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            do {
                _ = try await kit.transcribe(
                    audioArray: samples, decodeOptions: VocabularyPrompt.decodingOptions(languageHint: nil))
            } catch SpeechEngineError.unsupportedLanguage(let language) {
                refused += 1
                print("GATE REFUSED \(URL(fileURLWithPath: path).lastPathComponent) as \(language.value)")
            }
        }
        print("GATE SUMMARY clips=\(paths.count) refused=\(refused)")
        #expect(refused == 0)
    }
}
