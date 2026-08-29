import ArgumentParser
private import Foundation
private import Synchronization
private import UttrflowEval

/// Brings the corpus catalogue, and as much of its audio as is wanted, onto this Mac.
///
/// The corpus outgrew a directory of eighteen WAVs some time ago. It lives in a private
/// bucket, is listed by the backend, and is fetched through short-lived signed URLs —
/// none of which the app knows anything about, and none of which needs to happen more
/// than once per sample per machine.
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
            "\(samples.count) sample\(samples.count == 1 ? "" : "s") in the catalogue; "
                + "\(held.cached) already here (\(megabytes(held.bytes)))")
        summarise(samples)
        if listOnly { return }

        // A mutex rather than a plain counter: the progress callback is `@Sendable`, and
        // a captured `var` would be a data race the compiler is right to refuse.
        let done = Mutex(0)
        let failures = await library.fetchAll(samples) { _, _ in
            let count = done.withLock { count in
                count += 1
                return count
            }
            // On standard error and on one line, so a thousand samples do not scroll the
            // catalogue summary off the screen.
            FileHandle.standardError.write(Data("\rfetching \(count)/\(samples.count)…".utf8))
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))

        guard !failures.isEmpty else {
            print("\nEverything is on this Mac.")
            return
        }
        // Grouped by reason, because a thousand samples behind one misconfigured backend
        // is one problem, not a thousand.
        print("\n\(failures.count) could not be fetched:")
        let byReason = Dictionary(grouping: failures) { "\($0.error)" }
        for (reason, group) in byReason.sorted(by: { $0.key < $1.key }) {
            print("  \(group.count) × \(reason)")
            print(
                "    \(group.prefix(5).map(\.sample.slug).joined(separator: ", "))"
                    + (group.count > 5 ? ", and \(group.count - 5) more" : ""))
        }
        print("\nEverything already here was kept; run pull again to pick up the rest.")
    }

    /// What the catalogue holds, before a byte is downloaded.
    ///
    /// Printed because a pull is the moment somebody finds out the corpus is not the
    /// shape they assumed — nine hundred English samples and forty Hindi ones is a
    /// finding, and it is invisible in a per-sample list.
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
