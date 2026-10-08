// What produced a bake-off result, stored with it so two runs of one engine stay apart and comparable.
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval

/// The configuration one bake-off run measured, shared by every candidate it scored.
struct RunHeader: Codable, Sendable, Equatable {
    let runID: String
    let date: Date
    let promptVersion: String
    let corpusIdentity: String
    let caseCount: Int
    /// The source commit the rules and the guard come from, with "+dirty" when the tree had edits.
    let sourceRevision: String
    let systemBuild: String
    let chip: String
    let memoryBytes: Int64
    let contextWithheld: Bool
    /// The quality layers the run had on, by name; nil in a result stored before runs named them, which ran the defaults.
    var layers: [String]? = nil

    /// A field a change can hold fixed, named as `--allow-difference` takes it.
    enum Field: String, CaseIterable, Sendable {
        case corpus, system, hardware, context, layers
    }

    /// This Mac, this tree and this corpus, now.
    static func current(
        contextWithheld: Bool, layers: QualityLayers = QualityLayers(), date: Date = Date()
    ) -> RunHeader {
        let machine = MachineDescription.current()
        return RunHeader(
            runID: runID(for: date), date: date, promptVersion: PromptBuilder.version,
            corpusIdentity: EvaluationCase.corpusIdentity(of: EvaluationCorpus.all),
            caseCount: EvaluationCorpus.all.count, sourceRevision: sourceRevision(),
            systemBuild: SpeechModelLoadLog.currentSystemBuild, chip: machine.chip,
            memoryBytes: machine.memoryBytes, contextWithheld: contextWithheld, layers: layers.names)
    }

    /// A sortable UTC timestamp, so a directory listing is also the run order.
    static func runID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// One reason per held-fixed field that differs from `baseline`, skipping the ones `allowed` names.
    func differences(from baseline: RunHeader, allowing allowed: Set<Field>) -> [String] {
        Field.allCases.filter { !allowed.contains($0) }.compactMap { field in
            let (mine, theirs): (String, String)
            switch field {
            case .corpus: (mine, theirs) = (corpusIdentity, baseline.corpusIdentity)
            case .system: (mine, theirs) = (systemBuild, baseline.systemBuild)
            case .hardware: (mine, theirs) = (hardware, baseline.hardware)
            case .context: (mine, theirs) = (String(contextWithheld), String(baseline.contextWithheld))
            case .layers: (mine, theirs) = (layerNames, baseline.layerNames)
            }
            return mine == theirs ? nil : "\(field.rawValue) differs: baseline \(theirs), now \(mine)"
        }
    }

    /// The layers by name, the defaults where the result predates the field.
    var layerNames: String {
        (layers ?? QualityLayers().names).joined(separator: ",")
    }

    var hardware: String { "\(chip), \(memoryBytes / 1_073_741_824) GB" }

    /// One line naming everything the run held, printed above its table.
    var summary: String {
        "run \(runID): prompt \(promptVersion), corpus \(corpusIdentity) (\(caseCount) cases), source \(sourceRevision), macOS \(systemBuild), \(hardware), layers \(layerNames)"
    }

    private static func sourceRevision() -> String {
        guard let commit = git(["rev-parse", "--short=12", "HEAD"]), !commit.isEmpty else { return "unknown" }
        let status = git(["status", "--porcelain", "--untracked-files=no"]) ?? ""
        return status.isEmpty ? commit : commit + "+dirty"
    }

    private static func git(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The last run for each prompt version and macOS build, as a Markdown table.
enum ResultLedger {
    static func markdown(of measurements: [Measurement]) -> String {
        var latest: [String: Measurement] = [:]
        for measurement in measurements {
            guard let header = measurement.header else { continue }
            let key = "\(header.promptVersion)|\(header.systemBuild)|\(measurement.description.fileName)"
            if let kept = latest[key]?.header, kept.runID >= header.runID { continue }
            latest[key] = measurement
        }
        let rows = latest.values.compactMap { measurement -> String? in
            guard let header = measurement.header else { return nil }
            let rate = Int((measurement.report.passRate * 100).rounded())
            return "| \(header.promptVersion) | \(header.systemBuild) | \(measurement.description.name) "
                + "\(measurement.description.parameters) | \(rate)% | \(header.runID) | \(header.corpusIdentity) "
                + "| \(header.sourceRevision) | \(header.hardware) |"
        }.sorted()
        return """
            # Bake-off results ledger

            Generated by `make bakeoff ARGS="--ledger <path>"`; do not edit by hand. The last stored run of each \
            candidate for each prompt version and macOS build.

            | prompt | macOS | candidate | pass | run | corpus | source | hardware |
            |---|---|---|---|---|---|---|---|

            """ + rows.joined(separator: "\n") + "\n"
    }
}
