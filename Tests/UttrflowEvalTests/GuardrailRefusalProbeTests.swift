// Measures how often each guardrail configuration of Apple's model refuses ordinary sensitive dictation.
import Foundation
import FoundationModels
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowEval

@Suite("Sensitive-register corpus")
struct SensitiveRegisterCorpusTests {
    @Test("holds at least forty unique cases with every register at least six times")
    func shape() {
        let entries = SensitiveRegisterCorpus.all
        #expect(entries.count >= 40)
        #expect(Set(entries.map(\.evaluation.id)).count == entries.count)
        for register in SensitiveRegisterCorpus.Register.allCases {
            #expect(entries.filter { $0.register == register }.count >= 6, "\(register)")
        }
    }
}

/// What one model call ended as, before the router could fall back.
enum ProbeOutcome: String, Sendable, CaseIterable {
    case answered, guardrail, refusal, otherError, guardRejected
}

/// Collects what each call ended as, per register.
actor ProbeTally {
    private(set) var rows: [(SensitiveRegisterCorpus.Register, ProbeOutcome, String)] = []
    func add(_ register: SensitiveRegisterCorpus.Register, _ outcome: ProbeOutcome, _ id: String) {
        rows.append((register, outcome, id))
    }
}

/// One configuration of Apple's model, recording the raw failure class the shipping model hides.
@available(macOS 26, *)
struct GuardrailProbeModel: CleanupModel {
    enum Configuration: String, Sendable, CaseIterable {
        case structuredDefault, stringPermissive
    }

    let configuration: Configuration
    let failure: ProbeFailureSlot

    func availability(for language: LanguageCode?) async -> TransformerAvailability {
        await AppleFoundationCleanupModel().availability(for: language)
    }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        let options = GenerationOptions(temperature: 0.0)
        do {
            switch configuration {
            case .structuredDefault:
                let session = LanguageModelSession(instructions: instructions)
                return try await session.respond(
                    to: text, generating: CleanedDictation.self, options: options
                ).content.text
            case .stringPermissive:
                let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                let session = LanguageModelSession(model: model, instructions: instructions)
                return try await session.respond(to: text, options: options).content
            }
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation: await failure.set(.guardrail)
            case .refusal: await failure.set(.refusal)
            default: await failure.set(.otherError)
            }
            throw .transformFailed(kind: kind, failure: .ofSystemModel(error))
        } catch {
            await failure.set(.otherError)
            throw .transformFailed(kind: kind, failure: .ofSystemModel(error))
        }
    }
}

/// The failure class of the last call, read once the transformer has returned or thrown.
actor ProbeFailureSlot {
    private(set) var outcome: ProbeOutcome?
    func set(_ value: ProbeOutcome) { outcome = value }
    func reset() { outcome = nil }
}

/// Runs only with UTTRFLOW_GUARDRAIL_PROBE=1, since it makes two live model calls per case.
@Suite("Guardrail refusal probe", .serialized)
struct GuardrailRefusalProbeTests {
    static let enabled = ProcessInfo.processInfo.environment["UTTRFLOW_GUARDRAIL_PROBE"] == "1"

    @Test("records the refusal rate per register for both configurations", .enabled(if: enabled))
    func measure() async throws {
        guard #available(macOS 26, *) else { return }
        guard await AppleFoundationCleanupModel().availability(for: .english).isAvailable else { return }
        for configuration in GuardrailProbeModel.Configuration.allCases {
            let slot = ProbeFailureSlot()
            let transformer = GenerativeTextTransformer(
                kind: .foundationModels,
                model: GuardrailProbeModel(configuration: configuration, failure: slot))
            let tally = ProbeTally()
            for entry in SensitiveRegisterCorpus.all {
                await slot.reset()
                let outcome: ProbeOutcome
                var text = ""
                var detail = ""
                do {
                    text = try await transformer.transform(entry.evaluation.transformationRequest()).text
                    outcome = .answered
                } catch {
                    detail = "\(error)"
                    outcome = await slot.outcome ?? .guardRejected
                }
                await tally.add(entry.register, outcome, entry.evaluation.id)
                print(
                    "PROBE \(configuration.rawValue) \(entry.evaluation.id) \(outcome.rawValue) | \(text) \(detail)"
                )
            }
            let rows = await tally.rows
            for register in SensitiveRegisterCorpus.Register.allCases {
                let mine = rows.filter { $0.0 == register }
                let counts = ProbeOutcome.allCases.map { outcome in
                    "\(outcome.rawValue)=\(mine.filter { $0.1 == outcome }.count)"
                }
                print(
                    "PROBE-SUMMARY \(configuration.rawValue) \(register.rawValue) n=\(mine.count) "
                        + counts.joined(separator: " "))
            }
        }
    }
}
