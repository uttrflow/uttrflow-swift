import ArgumentParser
private import Foundation
private import Synchronization
private import UttrflowEval

/// Brings the corpus catalogue, and as much of its audio as is wanted, onto this Mac.
struct PullCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "List the corpus catalogue and download its audio. Resumable, and cached."
    )

    @OptionGroup var connection: CorpusConnection

    @Option(name: .long, help: "Only one BCP-47 language tag, e.g. hi-IN.")
    var language: String?

    @Option(name: .long, help: "Only samples carrying one stress, e.g. proper-nouns.")
    var stress: String?

    @Flag(name: .long, help: "Only the held-out samples, which no threshold may be fitted to.")
    var heldOut = false

    @Flag(name: .long, help: "List the catalogue and stop, without downloading anything.")
    var listOnly = false

    func run() async throws {
        let library = try connection.library()
        let query = CorpusQuery(
            language: language, stress: stress, heldOut: heldOut ? true : nil)

        let samples: [CorpusSample]
        do {
            samples = try await library.samples(matching: query)
        } catch {
            throw CleanExit.message("\(error)")
        }
        guard !samples.isEmpty else {
            print("The catalogue has nothing matching that.")
            return
        }

        let held = library.held(of: samples)
        print(
            "\(counted(samples.count, "sample")) in the catalogue; "
                + "\(held.cached) already here (\(megabytes(held.bytes)))")
        summarise(samples)
        if listOnly { return }

        // A mutex rather than a captured `var`, because the progress callback is `@Sendable`.
        let done = Mutex(0)
        let failures = await library.fetchAll(samples) { _, _ in
            let count = done.withLock { count in
                count += 1
                return count
            }
            // On standard error and on one line, so the catalogue summary is not scrolled away.
            Terminal.show("\rfetching \(count)/\(samples.count)…")
        }
        Terminal.clearLine()

        guard !failures.isEmpty else {
            print("\nEverything is on this Mac.")
            return
        }
        // Grouped by reason, because a thousand samples behind one misconfigured backend is one problem.
        print("\n\(failures.count) could not be fetched:")
        let byReason = Dictionary(grouping: failures) { "\($0.error)" }
        for (reason, group) in byReason.sorted(by: { $0.key < $1.key }) {
            print("  \(group.count) × \(reason)")
            print("    " + group.map(\.sample.slug).listed())
        }
        print("\nEverything already here was kept; run pull again to pick up the rest.")
    }

    /// Prints what the catalogue holds by language and cohort before a byte is downloaded.
    private func summarise(_ samples: [CorpusSample]) {
        print("\nlanguage".padded(to: 16) + "samples".padded(to: 10) + "speech")
        for (tag, group) in Dictionary(grouping: samples, by: \.language).sorted(by: { $0.key < $1.key }) {
            let seconds = group.reduce(0) { $0 + $1.durationMs } / 1000
            print(tag.padded(to: 16) + "\(group.count)".padded(to: 10) + "\(seconds / 60)m \(seconds % 60)s")
        }
        print("\nstress".padded(to: 22) + "samples")
        let stresses = samples.flatMap(\.stresses)
        for (label, count) in Dictionary(grouping: stresses, by: { $0 }).mapValues(\.count)
            .sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) })
        {
            print(label.padded(to: 22) + "\(count)")
        }
        let heldOut = samples.count(where: \.isHeldOut)
        print("\n\(heldOut) held out, \(samples.count - heldOut) available for tuning")
    }

    private func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
