import Foundation
import UttrflowCore
import UttrflowEval
import UttrflowSpeech

/// Draws a ``PerformanceReport`` as the table `Docs/performance.md` quotes.
///
/// Only formatting. Every figure below is read off the report — nothing is derived here,
/// so a number in the document and the same number in a test come from one place.
struct ProfilePrinter {
    let report: PerformanceReport
    let model: SpeechModel
    let includesCleanup: Bool

    private static let labelWidth = 30

    func emit() {
        machine()
        memory()
        loading()
        latency()
        processor()
        leak()
        disk()
    }

    private func machine() {
        let machine = report.machine
        print("Uttrflow performance")
        row(
            "machine",
            "\(machine.chip) · \(gibibytes(machine.memoryBytes)) · \(machine.operatingSystem)")
        row("speech model", model.variant)
        row("measures", includesCleanup ? "transcription and clean-up" : "transcription only")
    }

    private func memory() {
        print("\nMemory")
        print(
            "  " + "moment".padded(to: Self.labelWidth) + "footprint".padded(to: 12)
                + "resident".padded(to: 12) + "change")
        for (sample, change) in zip(report.timeline.samples, report.timeline.increments) {
            print(
                "  " + sample.label.padded(to: Self.labelWidth)
                    + megabytes(sample.reading.footprintBytes).padded(to: 12)
                    + megabytes(sample.reading.residentBytes).padded(to: 12)
                    + (change.map(signedMegabytes) ?? "—"))
        }
        if let peak = report.timeline.peak {
            print(
                "  " + "peak, mid-dictation".padded(to: Self.labelWidth)
                    + megabytes(peak.footprintBytes).padded(to: 12)
                    + megabytes(peak.residentBytes))
        } else {
            print("  peak was not sampled")
        }
        print(
            "  footprint is what Activity Monitor shows; resident includes the model's"
                + " mapped weights")
    }

    private func loading() {
        let load = report.modelLoad
        print("\nLoading the speech model")
        row("first load in this process", seconds(load.first) + " s")
        if let warm = load.warm {
            let saved = load.savedByWarming.map { " (\(percent($0)) less)" } ?? ""
            row("warm load, same process", seconds(warm) + " s" + saved)
        } else {
            row("warm load, same process", "not measured")
        }
        if let added = load.addedBytes {
            row("added to the footprint", megabytes(added))
        }
        if let cpu = load.cpu {
            row("processor time to load", seconds(cpu.cpuSeconds) + " s" + cores(cpu))
        }
    }

    /// What a dictation costs the processor, as opposed to how long it makes somebody
    /// wait.
    ///
    /// The two are different questions and a table of seconds answers only the first. A
    /// dictation that finishes in 3.6 seconds having held four cores busy has spent
    /// fourteen processor-seconds, and it is that figure — not the 3.6 — that decides
    /// whether the fans come on, what the battery does, and how the same work behaves on
    /// a Mac with four cores instead of twelve.
    private func processor() {
        let utterances = report.utterances.filter { $0.cpu != nil }
        guard !utterances.isEmpty else {
            print("\nProcessor: not measured.")
            return
        }

        print("\nProcessor cost of one dictation")
        print(
            "  " + "length".padded(to: 9) + "audio".padded(to: 8) + "cpu s".padded(to: 9)
                + "cores".padded(to: 8) + "cpu s/audio s".padded(to: 15)
                + "kernel".padded(to: 9) + "instructions")
        print("  " + String(repeating: "─", count: 74))
        for utterance in utterances {
            guard let cpu = utterance.cpu, let each = utterance.cpuSecondsPerDictation else {
                continue
            }
            var line = utterance.length.rawValue.padded(to: 9)
            line += seconds(utterance.audioSeconds).padded(to: 8)
            line += seconds(each).padded(to: 9)
            line += (cpu.cores.map { String(format: "%.2f", $0) } ?? "—").padded(to: 8)
            line += (utterance.cpuSecondsPerAudioSecond.map { seconds($0) } ?? "—").padded(to: 15)
            line += (cpu.systemShare.map(percent) ?? "—").padded(to: 9)
            line += billions(cpu.instructions, over: utterance.runs)
            print("  " + line)
        }
        print("  cores is the average over the dictation — 1.00 is one core saturated")

        if let whole = report.cpu {
            print("\nThe whole run")
            row("processor time", seconds(whole.cpuSeconds) + " s" + cores(whole))
            row("wall clock", seconds(whole.wallSeconds) + " s")
            // Printed so the arithmetic can be checked against a chip anybody can look
            // up. A figure nothing like this Mac's real clock means the counters and the
            // times disagree, and that every instruction count above is suspect.
            if let clock = whole.gigahertz {
                let ipc = whole.instructionsPerCycle.map { String(format: "%.2f", $0) } ?? "—"
                row("implied clock", String(format: "%.2f GHz", clock) + " · \(ipc) instr/cycle")
            }
        }
    }

    /// The parenthesised "· 3.9 cores" that follows a processor-seconds figure.
    private func cores(_ cost: CPUCost) -> String {
        cost.cores.map { String(format: " · %.2f cores", $0) } ?? ""
    }

    /// Instructions per dictation, in billions, or a dash when the counters were absent.
    private func billions(_ instructions: UInt64?, over runs: Int) -> String {
        guard let instructions, runs > 0 else { return "—" }
        return String(format: "%.1f G", Double(instructions) / Double(runs) / 1e9)
    }

    private func latency() {
        guard !report.utterances.isEmpty else {
            print("\nNothing was timed.")
            return
        }

        print("\nLatency by utterance length — typical and slowest, in seconds")
        let stages = report.timedStages
        var header = "length".padded(to: 9) + "audio".padded(to: 8) + "runs".padded(to: 6)
        header += "end-to-end".padded(to: 20)
        for stage in stages { header += stage.rawValue.padded(to: 20) }
        print("  " + header)
        print("  " + String(repeating: "─", count: header.count))

        for utterance in report.utterances {
            var line = utterance.length.rawValue.padded(to: 9)
            line += seconds(utterance.audioSeconds).padded(to: 8)
            line += "\(utterance.endToEnd.samples)".padded(to: 6)
            line += pair(utterance.endToEnd.typical, utterance.endToEnd.slowest).padded(to: 20)
            for stage in stages {
                let latency = utterance.stages.first { $0.stage == stage }
                line += (latency.map { pair($0.typical, $0.slowest) } ?? "—").padded(to: 20)
            }
            print("  " + line)
        }

        let unmeasured = Set(report.utterances.flatMap(\.unmeasuredStages).map(\.rawValue))
        if !unmeasured.isEmpty {
            print("  not measured here: " + unmeasured.sorted().joined(separator: ", "))
        }

        print("\nHow cost grows with length — extra seconds of work per extra second of speech")
        scaling("end-to-end", report.scaling)
        for stage in stages { scaling(stage.rawValue, report.scaling(of: stage)) }
    }

    private func scaling(_ name: String, _ analysis: ScalingAnalysis) {
        let marginals = analysis.steps.map {
            "\($0.from.rawValue)→\($0.to.rawValue) \(String(format: "%.3f", $0.marginalCost))"
        }
        row(name, marginals.joined(separator: "   ").padded(to: 40) + analysis.verdict.rawValue)
    }

    private func leak() {
        let leak = report.leak
        print("\nLeak check — \(leak.footprints.count) consecutive dictations")
        for (index, bytes) in leak.footprints.enumerated() {
            print("  " + "\(index + 1)".padded(to: 6) + megabytes(bytes))
        }
        let gaps = max(0, leak.footprints.count - 1)
        row(
            "growth",
            signedMegabytes(leak.growthBytes) + " over \(gaps) dictations"
                + " (\(signedMegabytes(leak.perDictationBytes)) each)")
        row("never fell back", leak.neverFellBack ? "yes" : "no")
        row("allowance", megabytes(leak.allowanceBytes))
        row("verdict", leak.verdict.rawValue.uppercased())
    }

    private func disk() {
        print("\nDisk, once installed")
        row("speech model", megabytes(report.disk.speechModelBytes))
        if let application = report.disk.applicationBytes {
            row("application", megabytes(application))
            row("total", megabytes(report.disk.totalBytes))
        } else {
            row("application", "not built here")
        }
    }

    // MARK: Formatting

    private func row(_ label: String, _ value: String) {
        print("  " + label.padded(to: Self.labelWidth) + value)
    }

    private func pair(_ typical: Duration, _ slowest: Duration) -> String {
        seconds(typical).padded(to: 10) + seconds(slowest)
    }

    private func seconds(_ duration: Duration) -> String { seconds(duration.inSeconds) }

    private func seconds(_ value: Double) -> String { String(format: "%.2f", value) }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// Installed RAM, in the units the machine is sold in — a 48 GB Mac holds
    /// 51.5 decimal gigabytes, and printing that invites an argument about the wrong thing.
    private func gibibytes(_ bytes: Int64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1e6)
    }

    private func signedMegabytes(_ bytes: Int64) -> String {
        String(format: "%+.1f MB", Double(bytes) / 1e6)
    }
}
